import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prisma_domain/prisma_domain.dart';

import 'connector.dart';

class Protocol2HttpException implements Exception {
  Protocol2HttpException({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.retryable,
  });

  final int statusCode;
  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() =>
      'Protocol2HttpException($statusCode, $code, retryable=$retryable): $message';
}

/// Reference LAN/Wi-Fi implementation of the PRISMA Protocol 2.0 connector.
///
/// Discovery is intentionally injected as [seedRecords] in this package. Real
/// mDNS/DNS-SD discovery belongs to a platform adapter and can feed the same
/// [DiscoveryRecord] contract without changing session or product code.
class Protocol2LanConnector implements PrismaConnector {
  Protocol2LanConnector({
    Iterable<DiscoveryRecord> seedRecords = const [],
    HttpClient? httpClient,
    this.bootstrapCredential,
  })  : _seedRecords = List.unmodifiable(seedRecords),
        _http = httpClient ?? HttpClient();

  static const ProtocolVersion supportedProtocol =
      ProtocolVersion(major: 2, minor: 0);

  final List<DiscoveryRecord> _seedRecords;
  final HttpClient _http;

  /// Optional local appliance bootstrap credential. This is not a Google or
  /// cloud-account token. Cloud identity and appliance trust remain separate.
  final String? bootstrapCredential;

  final StreamController<PrismaEvent> _events =
      StreamController<PrismaEvent>.broadcast(sync: true);

  ConnectorHealth _health =
      const ConnectorHealth(state: ConnectorState.disconnected);
  DiscoveryRecord? _record;
  Uri? _baseUri;
  String? _sessionToken;
  WebSocket? _eventSocket;
  bool _disconnecting = false;

  @override
  ConnectorTransport get transport => ConnectorTransport.lanWifi;

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

    if (supportedProtocol.compatibilityWith(record.protocol) !=
        ProtocolCompatibility.compatible) {
      _health = const ConnectorHealth(
        state: ConnectorState.failed,
        detail: 'Protocol adapter required',
      );
      throw StateError(
        'Protocol ${record.protocol.major}.${record.protocol.minor} requires an adapter',
      );
    }

    _record = record;
    _baseUri = Uri(
      scheme: 'http',
      host: record.host,
      port: record.controlPort,
    );

    final envelope = await _requestJson(
      'GET',
      '/v2/device',
      authenticated: false,
    );
    final result = _resultMap(envelope);
    final device = DeviceDescriptor.fromJson(result);

    if (device.deviceId != record.deviceId) {
      _health = const ConnectorHealth(
        state: ConnectorState.failed,
        detail: 'Discovered identity changed during connect',
      );
      throw StateError(
        'Discovery device_id ${record.deviceId} does not match ${device.deviceId}',
      );
    }

    _health = const ConnectorHealth(state: ConnectorState.authenticating);
    return device;
  }

  @override
  Future<void> authenticate() async {
    _requireConnected();
    _health = const ConnectorHealth(state: ConnectorState.authenticating);

    final envelope = await _requestJson(
      'POST',
      '/v2/auth/session',
      authenticated: false,
      body: {
        if (bootstrapCredential != null)
          'bootstrap_credential': bootstrapCredential,
      },
    );
    final result = _resultMap(envelope);
    final token = result['session_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Protocol 2.0 auth response has no session_token');
    }
    _sessionToken = token;

    // The event channel is established before the session is reported ready so
    // command-generated events cannot be lost between bootstrap and subscribe.
    await _openEventSocket();
    _health = const ConnectorHealth(state: ConnectorState.ready);
  }

  @override
  Future<void> disconnect() async {
    _disconnecting = true;
    try {
      final socket = _eventSocket;
      _eventSocket = null;
      if (socket != null) {
        await socket.close(WebSocketStatus.normalClosure, 'client disconnect');
      }
      _sessionToken = null;
      _record = null;
      _baseUri = null;
      _health = const ConnectorHealth(state: ConnectorState.disconnected);
    } finally {
      _disconnecting = false;
    }
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    final envelope = await _requestJson('GET', '/v2/capabilities');
    return DeviceCapabilities(_resultMap(envelope));
  }

  @override
  Future<PrismaState> getState() async {
    final envelope = await _requestJson('GET', '/v2/state');
    return PrismaState.fromJson(_resultMap(envelope));
  }

  @override
  Future<List<MediaEndpoint>> getMediaEndpoints() async {
    final envelope = await _requestJson('GET', '/v2/media/endpoints');
    final result = envelope['result'];
    if (result is! List) {
      throw const FormatException('Protocol 2.0 media result must be a list');
    }
    return result
        .map((item) => MediaEndpoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) {
    return _requestJson(
      'POST',
      '/v2/request',
      body: {'type': type, 'payload': payload},
    );
  }

  @override
  Future<Map<String, dynamic>> sendCommand(PrismaCommand command) {
    return _requestJson(
      'POST',
      '/v2/commands',
      body: command.toJson(),
    );
  }

  @override
  Stream<PrismaEvent> events() {
    _requireAuthenticated();
    return _events.stream;
  }

  Future<void> _openEventSocket() async {
    _requireAuthenticated();
    final base = _baseUri!;
    final eventUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v2/events',
      query: null,
    );

    final socket = await WebSocket.connect(
      eventUri.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $_sessionToken',
      },
    );
    _eventSocket = socket;

    socket.listen(
      (message) {
        try {
          final decoded = jsonDecode(message as String);
          if (decoded is! Map) {
            throw const FormatException('Event payload is not an object');
          }
          _events.add(
            PrismaEvent.fromJson(Map<String, dynamic>.from(decoded)),
          );
        } catch (error, stackTrace) {
          _events.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disconnecting) return;
        _health = ConnectorHealth(
          state: ConnectorState.degraded,
          detail: 'Event channel error',
          lastError: error,
        );
        _events.addError(error, stackTrace);
      },
      onDone: () {
        if (_disconnecting) return;
        _eventSocket = null;
        final error = StateError('Protocol 2.0 event channel closed');
        _health = ConnectorHealth(
          state: ConnectorState.degraded,
          detail: 'Event channel closed',
          lastError: error,
        );
        _events.addError(error);
      },
      cancelOnError: false,
    );
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    if (_baseUri == null) {
      throw StateError('Connector has no active device base URI');
    }
    if (authenticated) _requireAuthenticated();

    final uri = _baseUri!.replace(path: path, query: null);
    final request = await _http.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.accept.add(ContentType.json);
    if (authenticated) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_sessionToken',
      );
    }
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final dynamic decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Protocol 2.0 response from $path is not an object');
    }
    final envelope = Map<String, dynamic>.from(decoded);

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['ok'] == false) {
      final error = envelope['error'];
      final errorMap = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      throw Protocol2HttpException(
        statusCode: response.statusCode,
        code: errorMap['code'] as String? ?? 'HTTP_ERROR',
        message: errorMap['message'] as String? ??
            'Protocol 2.0 request failed: $path',
        retryable: errorMap['retryable'] as bool? ?? false,
      );
    }

    return envelope;
  }

  Map<String, dynamic> _resultMap(Map<String, dynamic> envelope) {
    final result = envelope['result'];
    if (result is! Map) {
      throw const FormatException('Protocol 2.0 result must be an object');
    }
    return Map<String, dynamic>.from(result);
  }

  void _requireConnected() {
    if (_record == null || _baseUri == null) {
      throw StateError('Protocol 2.0 connector is not connected');
    }
  }

  void _requireAuthenticated() {
    _requireConnected();
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      throw StateError('Protocol 2.0 connector has no appliance session');
    }
  }
}
