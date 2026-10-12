import 'dart:async';

import 'package:prisma_domain/prisma_domain.dart';

enum ConnectorTransport { lanWifi, usbCable, legacyEsp32, mock }

enum ConnectorState { disconnected, discovering, connecting, authenticating, ready, degraded, failed }

/// Transport-level connector failure shared by Protocol 2.0, legacy HTTP and
/// future USB/network adapters. Product code can reason about retryability
/// without depending on one protocol implementation.
class ConnectorTransportException implements Exception {
  ConnectorTransportException({
    required this.operation,
    required this.message,
    required this.retryable,
    this.cause,
  });

  final String operation;
  final String message;
  final bool retryable;
  final Object? cause;

  @override
  String toString() =>
      'ConnectorTransportException($operation, retryable=$retryable): $message';
}

class DiscoveryRecord {
  const DiscoveryRecord({
    required this.deviceId,
    required this.displayName,
    required this.host,
    required this.controlPort,
    required this.protocol,
    required this.pairingRequired,
    required this.capabilityDigest,
  });

  final String deviceId;
  final String displayName;
  final String host;
  final int controlPort;
  final ProtocolVersion protocol;
  final bool pairingRequired;
  final String capabilityDigest;
}

class ConnectorHealth {
  const ConnectorHealth({
    required this.state,
    this.detail,
    this.lastError,
  });

  final ConnectorState state;
  final String? detail;
  final Object? lastError;
}

abstract interface class PrismaConnector {
  ConnectorTransport get transport;
  ConnectorHealth get health;

  Stream<DiscoveryRecord> discover();
  Future<DeviceDescriptor> connect(DiscoveryRecord record);
  Future<void> authenticate();
  Future<void> disconnect();

  Future<DeviceCapabilities> getCapabilities();
  Future<PrismaState> getState();
  Future<List<MediaEndpoint>> getMediaEndpoints();

  Future<Map<String, dynamic>> request(String type, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> sendCommand(PrismaCommand command);
  Stream<PrismaEvent> events();
}

abstract interface class ConnectorFactory {
  ConnectorTransport get transport;
  PrismaConnector create();
}
