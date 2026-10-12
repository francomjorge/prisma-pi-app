import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prisma_domain/prisma_domain.dart';

import 'connector.dart';

/// Compatibility adapter for the protected current ESP32-S3 web baseline.
///
/// The current firmware exposes a plaintext HTTP SoftAP surface with:
///
/// - GET /api/state
/// - GET /source/<filename>
///
/// It does not expose remote command or event endpoints. This adapter therefore
/// normalizes state into [PrismaState] and synthesizes connector events by
/// polling. It must remain visibly classified as insecure/read-only legacy
/// compatibility and must never be mistaken for Protocol 2.0.
class LegacyEsp32Connector implements PrismaConnector {
  LegacyEsp32Connector({
    Iterable<DiscoveryRecord> seedRecords = const [],
    HttpClient? httpClient,
    this.pollInterval = const Duration(milliseconds: 300),
    this.requestTimeout = const Duration(seconds: 3),
  })  : _seedRecords = List.unmodifiable(seedRecords),
        _http = httpClient ?? HttpClient();

  static const ProtocolVersion legacyProtocol = ProtocolVersion(
    family: 'PRISMA_LEGACY',
    major: 1,
    minor: 0,
  );

  static const List<String> coreEffectIds = [
    'PIXEL',
    'GLITCH',
    'POSTER',
    'HUE',
    'MIRROR',
    'MIX',
  ];

  final List<DiscoveryRecord> _seedRecords;
  final HttpClient _http;
  final Duration pollInterval;
  final Duration requestTimeout;
  final StreamController<PrismaEvent> _events =
      StreamController<PrismaEvent>.broadcast(sync: true);

  ConnectorHealth _health =
      const ConnectorHealth(state: ConnectorState.disconnected);
  DiscoveryRecord? _record;
  Uri? _baseUri;
  bool _authenticated = false;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _eventCounter = 0;
  int? _lastObservedGeneration;
  PrismaState? _lastState;

  @override
  ConnectorTransport get transport => ConnectorTransport.legacyEsp32;

  @override
  ConnectorHealth get health => _health;

  @override
  Stream<DiscoveryRecord> discover() async* {
    _health = const ConnectorHealth(state: ConnectorState.discovering);
    for (final record in _seedRecords) {
      yield record;
    }
    _health = const ConnectorHealth(state: ConnectorState.disconnected);
  }

  @override
  Future<DeviceDescriptor> connect(DiscoveryRecord record) async {
    _health = const ConnectorHealth(state: ConnectorState.connecting);
    _record = record;
    _baseUri = Uri(
      scheme: 'http',
      host: record.host,
      port: record.controlPort,
    );

    // Probe the only authoritative legacy state endpoint before reporting a
    // successful connection.
    final state = await _fetchState();
    _lastState = state;
    _lastObservedGeneration = state.generation;
    _health = const ConnectorHealth(state: ConnectorState.authenticating);

    return DeviceDescriptor(
      deviceId: record.deviceId,
      displayName: record.displayName,
      model: 'WAVESHARE-ESP32-S3-TOUCH-LCD-1.54',
      firmwareVersion: 'legacy-web-baseline',
      protocol: legacyProtocol,
      pairingRequired: false,
      securityProfiles: const ['LEGACY_UNAUTHENTICATED'],
      capabilityDigest: record.capabilityDigest.isEmpty
          ? 'legacy-http-readonly-v1'
          : record.capabilityDigest,
    );
  }

  @override
  Future<void> authenticate() async {
    _requireConnected();
    // Explicit compatibility no-op. The current protected baseline has no
    // application authentication; production connectors must not copy this.
    _authenticated = true;
    _health = const ConnectorHealth(
      state: ConnectorState.ready,
      detail: 'LEGACY_UNAUTHENTICATED',
    );
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _authenticated = false;
    _record = null;
    _baseUri = null;
    _lastState = null;
    _lastObservedGeneration = null;
    _health = const ConnectorHealth(state: ConnectorState.disconnected);
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    _requireReady();
    return DeviceCapabilities({
      'control': {
        'commands': false,
        'events': false,
        'expected_generation': false,
        'adapter_polling': true,
        'poll_interval_ms': pollInterval.inMilliseconds,
      },
      'security': {
        'pairing': false,
        'session_auth': false,
        'legacy_unauthenticated': true,
        'profiles': ['LEGACY_UNAUTHENTICATED'],
      },
      'media': {
        'image': true,
        'video': false,
        'video_audio': false,
      },
      'preview': {
        'source': true,
        'processed': false,
        'transports': [
          {'id': 'http-jpeg-current-source'}
        ],
      },
      'processing': {
        'core_fx_state': true,
        'remote_control': false,
      },
      'files': {
        'list': false,
        'upload': false,
        'download_current_source': true,
      },
    });
  }

  @override
  Future<PrismaState> getState() async {
    _requireReady();
    final state = await _fetchState();
    _lastState = state;
    _lastObservedGeneration = state.generation;
    return state;
  }

  @override
  Future<List<MediaEndpoint>> getMediaEndpoints() async {
    _requireReady();
    final state = _lastState ?? await getState();
    final filename = state.source.sourceId;
    if (filename == null || filename.isEmpty) return const [];

    final sourceUri = _baseUri!.resolve(
      '/source/${Uri.encodeComponent(filename)}',
    );
    return [
      MediaEndpoint(
        purpose: MediaPurpose.sourcePreview,
        transport: 'http-jpeg',
        codecOrFormat: 'jpeg',
        width: 0,
        height: 0,
        fps: 0,
        audio: false,
        latencyClass: 'legacy-polling-preview',
        sessionDescriptor: {
          'url': sourceUri.toString(),
          'cache_bust_query': 'v',
          'generation': state.generation,
        },
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    _requireReady();
    switch (type) {
      case 'GET_STATE':
        final state = await getState();
        return {
          'ok': true,
          'generation': state.generation,
          'result': state.toJson(),
        };
      case 'GET_DEVICE_INFO':
        final record = _record!;
        return {
          'ok': true,
          'generation': _lastState?.generation ?? 0,
          'result': {
            'device_id': record.deviceId,
            'model': 'WAVESHARE-ESP32-S3-TOUCH-LCD-1.54',
            'legacy': true,
          }
        };
      default:
        return {
          'ok': false,
          'generation': _lastState?.generation ?? 0,
          'error': {
            'code': 'UNSUPPORTED_REQUEST',
            'retryable': false,
          }
        };
    }
  }

  @override
  Future<Map<String, dynamic>> sendCommand(PrismaCommand command) async {
    _requireReady();
    return {
      'ok': false,
      'generation': _lastState?.generation ?? 0,
      'error': {
        'code': 'UNSUPPORTED_COMMAND',
        'message': 'Current legacy firmware has no remote command endpoint',
        'retryable': false,
      }
    };
  }

  @override
  Stream<PrismaEvent> events() {
    _requireReady();
    _startPolling();
    return _events.stream;
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_pollInFlight || !_authenticated) return;
      _pollInFlight = true;
      unawaited(_pollOnce().whenComplete(() => _pollInFlight = false));
    });
  }

  Future<void> _pollOnce() async {
    try {
      final state = await _fetchState();
      final previous = _lastObservedGeneration;
      _lastState = state;

      if (previous == null) {
        _lastObservedGeneration = state.generation;
        return;
      }

      if (state.generation < previous) {
        final error = StateError(
          'Legacy appliance generation reset from $previous to ${state.generation}',
        );
        _health = ConnectorHealth(
          state: ConnectorState.degraded,
          detail: 'Legacy generation reset',
          lastError: error,
        );
        _pollTimer?.cancel();
        _pollTimer = null;
        _events.addError(error);
        return;
      }

      if (state.generation == previous) return;

      _lastObservedGeneration = state.generation;
      _events.add(PrismaEvent(
        eventId: 'legacy-poll-${++_eventCounter}',
        type: 'STATE_CHANGED',
        deviceId: _record!.deviceId,
        generation: state.generation,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'state': state.toJson(),
          'source': 'LEGACY_POLL_ADAPTER',
        },
      ));
    } catch (error, stackTrace) {
      _health = ConnectorHealth(
        state: ConnectorState.degraded,
        detail: 'Legacy polling failed',
        lastError: error,
      );
      _pollTimer?.cancel();
      _pollTimer = null;
      _events.addError(error, stackTrace);
    }
  }

  Future<PrismaState> _fetchState() async {
    _requireConnected();
    final uri = _baseUri!.resolve('/api/state');
    try {
      final request = await _http.getUrl(uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close().timeout(requestTimeout);
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Legacy state HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Legacy /api/state must return a JSON object');
      }
      return _decodeState(Map<String, dynamic>.from(decoded));
    } on TimeoutException catch (error) {
      throw Protocol2TransportException(
        operation: 'LEGACY GET /api/state',
        message: 'Legacy state request timed out after $requestTimeout',
        retryable: true,
        cause: error,
      );
    } on SocketException catch (error) {
      throw Protocol2TransportException(
        operation: 'LEGACY GET /api/state',
        message: 'Legacy state socket failure: ${error.message}',
        retryable: true,
        cause: error,
      );
    }
  }

  PrismaState _decodeState(Map<String, dynamic> json) {
    final generation = (json['generation'] as num? ?? 0).toInt();
    final filename = json['filename'] as String?;
    final rawEffects = List<dynamic>.from(json['effects'] as List? ?? const []);
    final rawValues = List<dynamic>.from(json['values'] as List? ?? const []);

    if (rawEffects.length != 6 || rawValues.length != 6) {
      throw const FormatException(
        'Legacy state must contain exactly six effects and values',
      );
    }

    return PrismaState(
      power: json['on'] as bool? ?? false,
      mode: (json['mode'] as num? ?? 1).toInt() == 0
          ? SynthesisMode.random
          : SynthesisMode.bypass,
      intensity: (json['intensity'] as num? ?? 0).toInt(),
      source: SourceState(
        sourceId: filename,
        playbackState: PlaybackState.playing,
        positionMs: 0,
        generation: generation,
      ),
      coreEffects: List.generate(
        6,
        (index) => CoreEffectState(
          id: coreEffectIds[index],
          enabled: rawEffects[index] as bool? ?? false,
          value: (rawValues[index] as num? ?? 0).toDouble(),
          generation: generation,
        ),
        growable: false,
      ),
      generation: generation,
    );
  }

  void _requireConnected() {
    if (_record == null || _baseUri == null) {
      throw StateError('Legacy ESP32 connector is not connected');
    }
  }

  void _requireReady() {
    _requireConnected();
    if (!_authenticated) {
      throw StateError('Legacy ESP32 connector is not authenticated');
    }
  }
}
