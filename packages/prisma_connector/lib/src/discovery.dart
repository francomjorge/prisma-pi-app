import 'dart:async';

import 'connector.dart';

/// A source of appliance discovery records. Platform implementations may use
/// Android NSD/mDNS, iOS Bonjour, USB enumeration, legacy fixed endpoints, or
/// deterministic test fixtures.
abstract interface class PrismaDiscoveryProvider {
  String get providerId;
  Stream<DiscoveryRecord> discover();
}

/// Merges discovery providers and suppresses duplicate observations while still
/// emitting meaningful endpoint/capability changes for the same device_id.
class PrismaDiscoveryCoordinator {
  PrismaDiscoveryCoordinator(Iterable<PrismaDiscoveryProvider> providers)
      : providers = List.unmodifiable(providers);

  final List<PrismaDiscoveryProvider> providers;

  Stream<DiscoveryRecord> discover() async* {
    if (providers.isEmpty) return;

    final controller = StreamController<DiscoveryRecord>();
    final subscriptions = <StreamSubscription<DiscoveryRecord>>[];
    final fingerprints = <String, String>{};
    var remaining = providers.length;

    String fingerprint(DiscoveryRecord record) => [
          record.host,
          record.controlPort,
          record.protocol.family,
          record.protocol.major,
          record.protocol.minor,
          record.pairingRequired,
          record.capabilityDigest,
        ].join('|');

    void completed() {
      remaining -= 1;
      if (remaining == 0 && !controller.isClosed) {
        unawaited(controller.close());
      }
    }

    for (final provider in providers) {
      late final StreamSubscription<DiscoveryRecord> subscription;
      subscription = provider.discover().listen(
        (record) {
          final nextFingerprint = fingerprint(record);
          if (fingerprints[record.deviceId] == nextFingerprint) return;
          fingerprints[record.deviceId] = nextFingerprint;
          controller.add(record);
        },
        onError: controller.addError,
        onDone: completed,
        cancelOnError: false,
      );
      subscriptions.add(subscription);
    }

    try {
      yield* controller.stream;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      if (!controller.isClosed) await controller.close();
    }
  }
}

/// Simple provider useful for manual/fixed endpoints and tests.
class StaticDiscoveryProvider implements PrismaDiscoveryProvider {
  StaticDiscoveryProvider(this.providerId, Iterable<DiscoveryRecord> records)
      : _records = List.unmodifiable(records);

  @override
  final String providerId;
  final List<DiscoveryRecord> _records;

  @override
  Stream<DiscoveryRecord> discover() async* {
    for (final record in _records) {
      yield record;
    }
  }
}
