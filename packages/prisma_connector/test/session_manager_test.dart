import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ReconnectPolicy', () {
    test('uses bounded exponential backoff', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 4),
        multiplier: 2,
        maxAttempts: 4,
      );

      expect(policy.delayForAttempt(0), const Duration(seconds: 1));
      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 4));
      expect(policy.delayForAttempt(3), const Duration(seconds: 4));
      expect(policy.allowsAttempt(3), isTrue);
      expect(policy.allowsAttempt(4), isFalse);
    });
  });

  group('PrismaSessionManager', () {
    test('bootstraps descriptor, capabilities, state and media endpoints', () async {
      final connector = MockPrismaConnector();
      final record = await connector.discover().first;
      final session = PrismaSessionManager(connector);

      await session.open(record);

      expect(session.snapshot.phase, SessionPhase.ready);
      expect(session.snapshot.device?.deviceId, MockPrismaConnector.mockDeviceId);
      expect(session.snapshot.capabilities?.supports('control.events'), isTrue);
      expect(session.snapshot.capabilities?.supports('control.command_idempotency'), isTrue);
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

    test('same command_id and envelope is idempotent across retransmission', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(connector);
      await session.open(await connector.discover().first);

      const command = PrismaCommand(
        commandId: 'cmd-retry-1',
        type: 'SET_INTENSITY',
        payload: {'intensity': 72},
        origin: 'TEST',
        expectedGeneration: 1,
        timestampMs: 100,
      );

      final synchronized = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state?.generation == 2,
      );

      final first = await session.issue(command);
      await synchronized.timeout(const Duration(seconds: 1));
      final generationAfterFirst = (await connector.getState()).generation;
      final second = await session.issue(command);
      final generationAfterSecond = (await connector.getState()).generation;

      expect(first['ok'], isTrue);
      expect(second['ok'], isTrue);
      expect(second['generation'], first['generation']);
      expect(generationAfterFirst, 2);
      expect(generationAfterSecond, 2);

      await session.dispose();
    });

    test('reusing command_id with different command fails closed', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(connector);
      await session.open(await connector.discover().first);

      final synchronized = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state?.generation == 2,
      );

      final first = await session.issue(const PrismaCommand(
        commandId: 'cmd-reused',
        type: 'SET_INTENSITY',
        payload: {'intensity': 40},
        origin: 'TEST',
        expectedGeneration: 1,
        timestampMs: 1,
      ));
      expect(first['ok'], isTrue);
      await synchronized.timeout(const Duration(seconds: 1));

      final second = await session.issue(const PrismaCommand(
        commandId: 'cmd-reused',
        type: 'SET_INTENSITY',
        payload: {'intensity': 90},
        origin: 'TEST',
        expectedGeneration: 2,
        timestampMs: 2,
      ));

      expect(second['ok'], isFalse);
      expect((second['error'] as Map)['code'], 'COMMAND_ID_REUSE');
      expect((await connector.getState()).intensity, 40);
      expect((await connector.getState()).generation, 2);

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

    test('event-channel failure automatically reconnects and restores ready', () async {
      final connector = MockPrismaConnector();
      final session = PrismaSessionManager(
        connector,
        reconnectPolicy: const ReconnectPolicy(
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 20),
          multiplier: 2,
          maxAttempts: 3,
        ),
      );
      await session.open(await connector.discover().first);
      expect(connector.connectCount, 1);

      final reconnecting = session.snapshots.firstWhere(
        (snapshot) => snapshot.phase == SessionPhase.reconnecting,
      );
      final recovered = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready && connector.connectCount >= 2,
      );

      connector.injectEventChannelFailure();

      await reconnecting.timeout(const Duration(seconds: 1));
      final ready = await recovered.timeout(const Duration(seconds: 1));
      expect(ready.phase, SessionPhase.ready);
      expect(connector.connectCount, 2);
      expect(ready.state?.generation, 1);

      await session.dispose();
    });
  });
}
