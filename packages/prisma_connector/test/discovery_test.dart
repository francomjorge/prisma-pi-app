import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  const base = DiscoveryRecord(
    deviceId: 'device-1',
    displayName: 'PRISMA One',
    host: '192.168.4.1',
    controlPort: 80,
    protocol: ProtocolVersion(major: 2, minor: 0),
    pairingRequired: true,
    capabilityDigest: 'caps-a',
  );

  test('coordinator suppresses duplicate observations across providers', () async {
    final coordinator = PrismaDiscoveryCoordinator([
      StaticDiscoveryProvider('mdns', const [base]),
      StaticDiscoveryProvider('manual', const [base]),
    ]);

    final records = await coordinator.discover().toList();
    expect(records, hasLength(1));
    expect(records.single.deviceId, 'device-1');
  });

  test('coordinator emits meaningful endpoint/capability changes', () async {
    const changed = DiscoveryRecord(
      deviceId: 'device-1',
      displayName: 'PRISMA One',
      host: '192.168.4.2',
      controlPort: 8080,
      protocol: ProtocolVersion(major: 2, minor: 0),
      pairingRequired: true,
      capabilityDigest: 'caps-b',
    );

    final coordinator = PrismaDiscoveryCoordinator([
      StaticDiscoveryProvider('first', const [base]),
      StaticDiscoveryProvider('second', const [changed]),
    ]);

    final records = await coordinator.discover().toList();
    expect(records, hasLength(2));
    expect(records.last.host, '192.168.4.2');
    expect(records.last.capabilityDigest, 'caps-b');
  });
}
