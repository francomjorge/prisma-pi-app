import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  group('PrismaSessionManager', () {
    test('bootstraps descriptor, capabilities, state and media endpoints', () async {
      final connector = MockPrismaConnector();
      final record = await connector.discover().first;
      final session = PrismaSessionManager(connector);

      await session.open(record);

      expect(session.snapshot.phase, SessionPhase.ready);
      expect(session.snapshot.device?.deviceId, MockPrismaConnector.mockDeviceId);
      expect(session.snapshot.capabilities?.supports('control.events'), isTrue);
      expect(session.snapshot.state?.generation, 1);
      expect(session.snapshot.mediaEndpoints, hasLength(2));

      await session.dispose();
    });

    test('command event reconciles back to authoritative state', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(connector);
      await session.open(await connector.discover().first);

      final synchronized = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state?.generation == 2,
      );

      final response = await session.issue(PrismaCommand(
        commandId: 'cmd-1',
        type: 'SET_INTENSITY',
        payload: const {'intensity': 81},
        origin: 'TEST',
        expectedGeneration: 1,
        timestampMs: 1,
      ));

      expect(response['ok'], isTrue);
      final next = await synchronized;
      expect(next.state?.intensity, 81);
      expect(next.state?.generation, 2);

      await session.dispose();
    });

    test('generation gap forces a full authoritative resync', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(connector);
      await session.open(await connector.discover().first);

      final synchronized = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            (snapshot.state?.generation ?? 0) >= 3,
      );

      connector.injectGenerationGap(skipped: 1);

      final next = await synchronized;
      expect(next.state?.generation, 3);
      expect(next.phase, SessionPhase.ready);

      await session.dispose();
    });

    test('generation conflict is explicit and does not mutate state', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(connector);
      await session.open(await connector.discover().first);

      final response = await session.issue(PrismaCommand(
        commandId: 'cmd-conflict',
        type: 'SET_POWER',
        payload: const {'power': false},
        origin: 'TEST',
        expectedGeneration: 999,
        timestampMs: 1,
      ));

      expect(response['ok'], isFalse);
      expect((response['error'] as Map)['code'], 'GENERATION_CONFLICT');
      expect((await connector.getState()).generation, 1);
      expect((await connector.getState()).power, isTrue);

      await session.dispose();
    });
  });
}
