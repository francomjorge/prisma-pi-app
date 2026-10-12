import 'dart:async';

import 'package:prisma_domain/prisma_domain.dart';

import 'connector.dart';

/// Deterministic in-memory appliance used to validate client/session behavior
/// before a physical appliance or network adapter is involved.
class MockPrismaConnector implements PrismaConnector {
  MockPrismaConnector({PrismaState? initialState})
      : _state = initialState ?? _defaultState();

  final StreamController<PrismaEvent> _events =
      StreamController<PrismaEvent>.broadcast(sync: true);

  PrismaState _state;
  bool _connected = false;
  bool _authenticated = false;
  int _eventCounter = 0;
  int _connectCount = 0;
  ConnectorHealth _health =
      const ConnectorHealth(state: ConnectorState.disconnected);

  static const String mockDeviceId = '00000000-0000-4000-8000-000000000001';

  int get connectCount => _connectCount;

  @override
  ConnectorTransport get transport => ConnectorTransport.mock;

  @override
  ConnectorHealth get health => _health;

  @override
  Stream<DiscoveryRecord> discover() async* {
    _health = const ConnectorHealth(state: ConnectorState.discovering);
    yield const DiscoveryRecord(
      deviceId: mockDeviceId,
      displayName: 'PRISMA Mock Appliance',
      host: 'mock.local',
      controlPort: 0,
      protocol: ProtocolVersion(major: 2, minor: 0),
      pairingRequired: false,
      capabilityDigest: 'mock-v1',
    );
    _health = const ConnectorHealth(state: ConnectorState.disconnected);
  }

  @override
  Future<DeviceDescriptor> connect(DiscoveryRecord record) async {
    if (record.deviceId != mockDeviceId) {
      throw StateError('Mock connector cannot open ${record.deviceId}');
    }
    _connectCount += 1;
    _health = const ConnectorHealth(state: ConnectorState.connecting);
    _connected = true;
    _health = const ConnectorHealth(state: ConnectorState.authenticating);
    return const DeviceDescriptor(
      deviceId: mockDeviceId,
      displayName: 'PRISMA Mock Appliance',
      model: 'MOCK-2.0',
      firmwareVersion: '2.0.0-dev',
      protocol: ProtocolVersion(major: 2, minor: 0),
      pairingRequired: false,
      securityProfiles: ['MOCK_TRUSTED'],
      capabilityDigest: 'mock-v1',
    );
  }

  @override
  Future<void> authenticate() async {
    _requireConnected();
    _authenticated = true;
    _health = const ConnectorHealth(state: ConnectorState.ready);
  }

  @override
  Future<void> disconnect() async {
    _authenticated = false;
    _connected = false;
    _health = const ConnectorHealth(state: ConnectorState.disconnected);
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    _requireReady();
    return DeviceCapabilities({
      'control': {
        'commands': true,
        'events': true,
        'expected_generation': true,
      },
      'security': {'pairing': true, 'session_auth': true},
      'media': {'image': true, 'video': true, 'video_audio': true},
      'preview': {
        'source': true,
        'processed': true,
        'transports': [
          {'id': 'mock-frames', 'max_width': 1280, 'max_height': 720, 'max_fps': 30}
        ],
      },
      'processing': {
        'graph': true,
        'execution_targets': ['APPLIANCE'],
      },
      'files': {'list': true, 'upload': true, 'download': true},
    });
  }

  @override
  Future<PrismaState> getState() async {
    _requireReady();
    return _state;
  }

  @override
  Future<List<MediaEndpoint>> getMediaEndpoints() async {
    _requireReady();
    return const [
      MediaEndpoint(
        purpose: MediaPurpose.sourcePreview,
        transport: 'mock-frames',
        codecOrFormat: 'rgba8888',
        width: 640,
        height: 360,
        fps: 30,
        audio: false,
        latencyClass: 'interactive-preview',
        sessionDescriptor: {'channel': 'source'},
      ),
      MediaEndpoint(
        purpose: MediaPurpose.processedPreview,
        transport: 'mock-frames',
        codecOrFormat: 'rgba8888',
        width: 640,
        height: 360,
        fps: 30,
        audio: false,
        latencyClass: 'interactive-preview',
        sessionDescriptor: {'channel': 'processed'},
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
        return {'ok': true, 'generation': _state.generation, 'result': _state.toJson()};
      case 'GET_DEVICE_INFO':
        return {
          'ok': true,
          'generation': _state.generation,
          'result': {'device_id': mockDeviceId, 'model': 'MOCK-2.0'}
        };
      default:
        return {
          'ok': false,
          'generation': _state.generation,
          'error': {'code': 'INVALID_REQUEST', 'retryable': false}
        };
    }
  }

  @override
  Future<Map<String, dynamic>> sendCommand(PrismaCommand command) async {
    _requireReady();
    final expected = command.expectedGeneration;
    if (expected != null && expected != _state.generation) {
      return {
        'ok': false,
        'generation': _state.generation,
        'error': {'code': 'GENERATION_CONFLICT', 'retryable': true}
      };
    }

    final previousGeneration = _state.generation;
    switch (command.type) {
      case 'SET_POWER':
        _state = _copyState(power: command.payload['power'] as bool? ?? false);
        break;
      case 'SET_INTENSITY':
        final value = command.payload['intensity'] as int? ?? _state.intensity;
        _state = _copyState(intensity: value);
        break;
      case 'SET_MODE':
        final raw = command.payload['mode'] as String? ?? 'BYPASS';
        _state = _copyState(mode: raw == 'RANDOM' ? SynthesisMode.random : SynthesisMode.bypass);
        break;
      default:
        return {
          'ok': false,
          'generation': _state.generation,
          'error': {'code': 'INVALID_COMMAND', 'retryable': false}
        };
    }

    if (_state.generation != previousGeneration) {
      _emit('STATE_CHANGED', {'state': _state.toJson()});
    }

    return {'ok': true, 'generation': _state.generation, 'result': _state.toJson()};
  }

  @override
  Stream<PrismaEvent> events() {
    _requireReady();
    return _events.stream;
  }

  /// Test-only fault injection: emits a transport-like stream failure without
  /// destroying the reusable broadcast controller. Session code should enter
  /// reconnecting and establish a fresh connector session.
  void injectEventChannelFailure([String message = 'mock event channel failure']) {
    _requireReady();
    final error = StateError(message);
    _health = ConnectorHealth(
      state: ConnectorState.degraded,
      detail: 'Injected event-channel failure',
      lastError: error,
    );
    _events.addError(error);
  }

  /// Test-only fault injection: mutates the authoritative generation without
  /// emitting intermediate events, then emits one future event.
  void injectGenerationGap({int skipped = 1}) {
    _requireReady();
    if (skipped < 1) throw ArgumentError.value(skipped, 'skipped');
    for (var i = 0; i < skipped + 1; i++) {
      _state = _copyState();
    }
    _emit('STATE_CHANGED', {'state': _state.toJson()});
  }

  /// Test-only media renegotiation event.
  void injectMediaEndpointChange() {
    _requireReady();
    _state = _copyState();
    _emit('MEDIA_ENDPOINT_CHANGED', const {});
  }

  PrismaState _copyState({
    bool? power,
    SynthesisMode? mode,
    int? intensity,
  }) {
    final generation = _state.generation + 1;
    return PrismaState(
      power: power ?? _state.power,
      mode: mode ?? _state.mode,
      intensity: intensity ?? _state.intensity,
      source: SourceState(
        sourceId: _state.source.sourceId,
        playbackState: _state.source.playbackState,
        positionMs: _state.source.positionMs,
        generation: generation,
      ),
      coreEffects: _state.coreEffects
          .map((fx) => CoreEffectState(
                id: fx.id,
                enabled: fx.enabled,
                value: fx.value,
                generation: generation,
              ))
          .toList(growable: false),
      generation: generation,
    );
  }

  void _emit(String type, Map<String, dynamic> payload) {
    _events.add(PrismaEvent(
      eventId: 'mock-${++_eventCounter}',
      type: type,
      deviceId: mockDeviceId,
      generation: _state.generation,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    ));
  }

  void _requireConnected() {
    if (!_connected) throw StateError('Mock connector is not connected');
  }

  void _requireReady() {
    if (!_connected || !_authenticated) {
      throw StateError('Mock connector is not authenticated');
    }
  }

  static PrismaState _defaultState() {
    const generation = 1;
    return PrismaState(
      power: true,
      mode: SynthesisMode.random,
      intensity: 50,
      source: const SourceState(
        sourceId: 'mock-source-1',
        playbackState: PlaybackState.playing,
        positionMs: 0,
        generation: generation,
      ),
      coreEffects: List.generate(
        6,
        (index) => CoreEffectState(
          id: 'FX${index + 1}',
          enabled: true,
          value: 0.5,
          generation: generation,
        ),
      ),
      generation: generation,
    );
  }
}
