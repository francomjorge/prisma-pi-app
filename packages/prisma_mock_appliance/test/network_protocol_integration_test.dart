import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';
import 'package:prisma_mock_appliance/prisma_mock_appliance.dart';
import 'package:test/test.dart';

void main() {
  group('Protocol 2.0 network integration', () {
    late PrismaMockApplianceServer server;
    late Protocol2LanConnector connector;
    late PrismaSessionManager session;

    setUp(() async {
      server = PrismaMockApplianceServer();
      await server.start();
      connector = Protocol2LanConnector(seedRecords: [server.discoveryRecord]);
      session = PrismaSessionManager(
        connector,
        reconnectPolicy: const ReconnectPolicy(
          initialDelay: Duration(milliseconds: 20),
          maxDelay: Duration(milliseconds: 100),
          multiplier: 2,
          maxAttempts: 4,
        ),
      );
    });

    tearDown(() async {
      if (session.snapshot.phase != SessionPhase.closed) {
        await session.dispose();
      }
      await server.close();
    });

    test('discovers, authenticates and synchronizes through HTTP + WebSocket',
        () async {
      final record = await connector.discover().first;
      expect(record.protocol.major, 2);

      await session.open(record);

      expect(session.snapshot.phase, SessionPhase.ready);
      expect(session.snapshot.device?.model, 'MOCK-2.0');
      expect(session.snapshot.state?.generation, 1);
      expect(session.snapshot.capabilities?.supports('control.events'), isTrue);
      expect(session.snapshot.mediaEndpoints, hasLength(2));
      expect(
        session.snapshot.mediaEndpoints.first.purpose,
        MediaPurpose.sourcePreview,
      );
    });

    test('command event advances authoritative generation over WebSocket',
        () async {
      await session.open(server.discoveryRecord);
      final initialGeneration = session.snapshot.state!.generation;

      final updated = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state != null &&
            snapshot.state!.generation > initialGeneration,
      );

      final result = await session.issue(PrismaCommand(
        commandId: 'network-command-1',
        type: 'SET_INTENSITY',
        payload: const {'intensity': 73},
        origin: 'NETWORK_TEST',
        expectedGeneration: initialGeneration,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));

      expect(result['ok'], isTrue);
      final snapshot = await updated.timeout(const Duration(seconds: 3));
      expect(snapshot.state!.generation, initialGeneration + 1);
      expect(snapshot.state!.intensity, 73);
    });

    test('generation gap forces snapshot recovery over the network', () async {
      await session.open(server.discoveryRecord);
      final initialGeneration = session.snapshot.state!.generation;

      final recovered = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state != null &&
            snapshot.state!.generation >= initialGeneration + 2,
      );

      server.injectGenerationGap(skipped: 1);

      final snapshot = await recovered.timeout(const Duration(seconds: 3));
      expect(snapshot.phase, SessionPhase.ready);
      expect(snapshot.state!.generation, initialGeneration + 2);
    });

    test('generic request uses authenticated Protocol 2.0 envelope', () async {
      await session.open(server.discoveryRecord);
      final response = await connector.request('GET_DEVICE_INFO', const {});
      expect(response['ok'], isTrue);
      expect(
        (response['result'] as Map)['device_id'],
        MockPrismaConnector.mockDeviceId,
      );
    });

    test('forced WebSocket loss reconnects and restores command/event flow',
        () async {
      await session.open(server.discoveryRecord);
      expect(server.eventClientCount, 1);

      final reconnecting = session.snapshots.firstWhere(
        (snapshot) => snapshot.phase == SessionPhase.reconnecting,
      );
      final readyAgain = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            server.eventClientCount == 1,
      );

      await server.disconnectEventClients();
      await reconnecting.timeout(const Duration(seconds: 2));
      final recovered = await readyAgain.timeout(const Duration(seconds: 3));
      expect(recovered.phase, SessionPhase.ready);

      final before = recovered.state!.generation;
      final advanced = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            (snapshot.state?.generation ?? 0) > before,
      );

      final result = await session.issue(PrismaCommand(
        commandId: 'after-reconnect',
        type: 'SET_POWER',
        payload: const {'power': false},
        origin: 'NETWORK_TEST',
        expectedGeneration: before,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));
      expect(result['ok'], isTrue);
      final next = await advanced.timeout(const Duration(seconds: 3));
      expect(next.state?.power, isFalse);
    });

    test('one-shot HTTP fault is surfaced as retryable typed exception', () async {
      await session.open(server.discoveryRecord);
      server.failNextRequest(
        '/v2/request',
        code: 'MOCK_TRANSIENT',
        retryable: true,
      );

      await expectLater(
        connector.request('GET_DEVICE_INFO', const {}),
        throwsA(
          isA<Protocol2HttpException>()
              .having((e) => e.code, 'code', 'MOCK_TRANSIENT')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );

      final recovered = await connector.request('GET_DEVICE_INFO', const {});
      expect(recovered['ok'], isTrue);
    });

    test('artificial latency preserves protocol correctness', () async {
      server.setResponseLatency(const Duration(milliseconds: 20));
      await session.open(server.discoveryRecord);
      expect(session.snapshot.phase, SessionPhase.ready);
      expect(session.snapshot.state?.generation, 1);
    });
  });
}
