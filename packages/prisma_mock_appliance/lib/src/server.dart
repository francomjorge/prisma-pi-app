import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';

/// Networked Protocol 2.0 simulator.
///
/// This server is deliberately development/test only. Its session token is not
/// a production security mechanism; production pairing and transport security
/// are validated separately.
class PrismaMockApplianceServer {
  PrismaMockApplianceServer({MockPrismaConnector? backend})
      : backend = backend ?? MockPrismaConnector();

  final MockPrismaConnector backend;

  static const String _sessionToken = 'prisma-mock-session-v1';

  HttpServer? _server;
  StreamSubscription<PrismaEvent>? _eventSubscription;
  DeviceDescriptor? _device;
  final Set<WebSocket> _eventClients = <WebSocket>{};

  Duration _responseLatency = Duration.zero;
  String? _failNextPath;
  int _failNextStatus = HttpStatus.serviceUnavailable;
  String _failNextCode = 'MOCK_INJECTED_FAILURE';
  bool _failNextRetryable = true;

  bool get isRunning => _server != null;
  int get eventClientCount => _eventClients.length;

  Uri get baseUri {
    final server = _server;
    if (server == null) throw StateError('Mock Appliance server is not running');
    final host = server.address.address;
    return Uri(scheme: 'http', host: host, port: server.port);
  }

  DiscoveryRecord get discoveryRecord {
    final server = _server;
    final device = _device;
    if (server == null || device == null) {
      throw StateError('Mock Appliance server is not running');
    }
    return DiscoveryRecord(
      deviceId: device.deviceId,
      displayName: device.displayName,
      host: server.address.address,
      controlPort: server.port,
      protocol: device.protocol,
      pairingRequired: device.pairingRequired,
      capabilityDigest: device.capabilityDigest,
    );
  }

  Future<void> start({
    InternetAddress? address,
    int port = 0,
  }) async {
    if (_server != null) throw StateError('Mock Appliance server already started');

    final discovered = await backend.discover().first;
    _device = await backend.connect(discovered);
    await backend.authenticate();
    _eventSubscription = backend.events().listen(_broadcastEvent);

    final bound = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _server = bound;
    unawaited(_serve(bound));
  }

  Future<void> close() async {
    final server = _server;
    _server = null;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await disconnectEventClients(reason: 'server shutdown');

    if (server != null) {
      await server.close(force: true);
    }
    await backend.disconnect();
  }

  /// Adds deterministic latency before every HTTP/WebSocket endpoint handler.
  void setResponseLatency(Duration latency) {
    if (latency.isNegative) throw ArgumentError.value(latency, 'latency');
    _responseLatency = latency;
  }

  /// Makes the next request to [path] fail once, then automatically clears the
  /// injected fault.
  void failNextRequest(
    String path, {
    int statusCode = HttpStatus.serviceUnavailable,
    String code = 'MOCK_INJECTED_FAILURE',
    bool retryable = true,
  }) {
    if (!path.startsWith('/')) throw ArgumentError.value(path, 'path');
    _failNextPath = path;
    _failNextStatus = statusCode;
    _failNextCode = code;
    _failNextRetryable = retryable;
  }

  /// Forces all current event WebSockets closed while keeping HTTP alive.
  /// A resilient client should reconnect, re-authenticate and resynchronize.
  Future<void> disconnectEventClients({
    String reason = 'injected event transport failure',
  }) async {
    final sockets = List<WebSocket>.of(_eventClients);
    _eventClients.clear();
    for (final socket in sockets) {
      try {
        await socket.close(WebSocketStatus.goingAway, reason);
      } catch (_) {
        // Best-effort fault injection / cleanup.
      }
    }
  }

  void injectGenerationGap({int skipped = 1}) {
    backend.injectGenerationGap(skipped: skipped);
  }

  void injectMediaEndpointChange() {
    backend.injectMediaEndpointChange();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (_responseLatency > Duration.zero) {
        await Future<void>.delayed(_responseLatency);
      }

      if (_failNextPath == path) {
        _failNextPath = null;
        return _sendJson(request, _failNextStatus, {
          'ok': false,
          'error': {
            'code': _failNextCode,
            'message': 'Injected Mock Appliance failure for $path',
            'retryable': _failNextRetryable,
          }
        });
      }

      if (request.method == 'GET' && path == '/healthz') {
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'result': {'status': 'ok'}
        });
      }

      if (request.method == 'GET' && path == '/v2/device') {
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'result': _device!.toJson(),
        });
      }

      if (request.method == 'POST' && path == '/v2/auth/session') {
        await _readJsonObject(request); // validates JSON if present
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'result': {
            'session_token': _sessionToken,
            'expires_in_seconds': 3600,
            'security_profile': 'MOCK_TRUSTED',
          }
        });
      }

      if (!_isAuthorized(request)) {
        return _sendJson(request, HttpStatus.unauthorized, {
          'ok': false,
          'error': {
            'code': 'SESSION_UNAUTHORIZED',
            'message': 'Missing or invalid appliance session',
            'retryable': false,
          }
        });
      }

      if (request.method == 'GET' && path == '/v2/events') {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          return _sendJson(request, HttpStatus.upgradeRequired, {
            'ok': false,
            'error': {
              'code': 'WEBSOCKET_REQUIRED',
              'message': 'Event endpoint requires WebSocket upgrade',
              'retryable': true,
            }
          });
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _eventClients.add(socket);
        socket.done.whenComplete(() => _eventClients.remove(socket));
        return;
      }

      if (request.method == 'GET' && path == '/v2/capabilities') {
        final capabilities = await backend.getCapabilities();
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'result': capabilities.values,
        });
      }

      if (request.method == 'GET' && path == '/v2/state') {
        final state = await backend.getState();
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'generation': state.generation,
          'result': state.toJson(),
        });
      }

      if (request.method == 'GET' && path == '/v2/media/endpoints') {
        final state = await backend.getState();
        final endpoints = await backend.getMediaEndpoints();
        return _sendJson(request, HttpStatus.ok, {
          'ok': true,
          'generation': state.generation,
          'result': endpoints.map((e) => e.toJson()).toList(growable: false),
        });
      }

      if (request.method == 'POST' && path == '/v2/commands') {
        final body = await _readJsonObject(request);
        final command = PrismaCommand.fromJson(body);
        final result = await backend.sendCommand(command);
        return _sendJson(
          request,
          result['ok'] == true ? HttpStatus.ok : HttpStatus.conflict,
          result,
        );
      }

      if (request.method == 'POST' && path == '/v2/request') {
        final body = await _readJsonObject(request);
        final type = body['type'] as String?;
        if (type == null || type.isEmpty) {
          return _sendJson(request, HttpStatus.badRequest, {
            'ok': false,
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'type is required',
              'retryable': false,
            }
          });
        }
        final payload = Map<String, dynamic>.from(
          body['payload'] as Map? ?? const {},
        );
        final result = await backend.request(type, payload);
        return _sendJson(
          request,
          result['ok'] == true ? HttpStatus.ok : HttpStatus.badRequest,
          result,
        );
      }

      return _sendJson(request, HttpStatus.notFound, {
        'ok': false,
        'error': {
          'code': 'NOT_FOUND',
          'message': '${request.method} $path is not defined',
          'retryable': false,
        }
      });
    } catch (error) {
      try {
        _sendJson(request, HttpStatus.internalServerError, {
          'ok': false,
          'error': {
            'code': 'MOCK_INTERNAL_ERROR',
            'message': error.toString(),
            'retryable': false,
          }
        });
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {
          // Response may already be upgraded or closed.
        }
      }
    }
  }

  bool _isAuthorized(HttpRequest request) {
    return request.headers.value(HttpHeaders.authorizationHeader) ==
        'Bearer $_sessionToken';
  }

  Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Expected JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _sendJson(HttpRequest request, int statusCode, Map<String, dynamic> body) {
    final response = request.response;
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    unawaited(response.close());
  }

  void _broadcastEvent(PrismaEvent event) {
    final encoded = jsonEncode(event.toJson());
    for (final socket in List<WebSocket>.of(_eventClients)) {
      if (socket.readyState == WebSocket.open) {
        socket.add(encoded);
      } else {
        _eventClients.remove(socket);
      }
    }
  }
}
