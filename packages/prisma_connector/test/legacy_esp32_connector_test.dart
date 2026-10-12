import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prisma_connector/prisma_connector.dart';
import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  group('LegacyEsp32Connector', () {
    late HttpServer server;
    late StreamSubscription<HttpRequest> serverSubscription;
    late Map<String, dynamic> legacyState;
    late DiscoveryRecord record;
    late LegacyEsp32Connector connector;

    setUp(() async {
      legacyState = <String, dynamic>{
        'on': true,
        'mode': 0,
        'intensity': 61,
        'generation': 1,
        'filename': 'F1_MOON.JPG',
        'effects': [false, true, false, true, false, true],
        'values': [10, 20, 30, 40, 50, 60],
      };

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverSubscription = server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/api/state') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(legacyState));
          await request.response.close();
          return;
        }

        if (request.method == 'GET' &&
            request.uri.path == '/source/F1_MOON.JPG') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.add(const [0xff, 0xd8, 0xff, 0xd9]);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      record = DiscoveryRecord(
        deviceId: 'legacy-test-device',
        displayName: 'PRISMA Legacy Test',
        host: server.address.address,
        controlPort: server.port,
        protocol: LegacyEsp32Connector.legacyProtocol,
        pairingRequired: false,
        capabilityDigest: 'legacy-http-readonly-v1',
      );
      connector = LegacyEsp32Connector(
        seedRecords: [record],
        pollInterval: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await connector.disconnect();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    test('normalizes current /api/state into PrismaState', () async {
      final discovered = await connector.discover().first;
      final device = await connector.connect(discovered);
      await connector.authenticate();
      final state = await connector.getState();

      expect(device.protocol.family, 'PRISMA_LEGACY');
      expect(device.securityProfiles, ['LEGACY_UNAUTHENTICATED']);
      expect(state.power, isTrue);
      expect(state.mode, SynthesisMode.random);
      expect(state.intensity, 61);
      expect(state.generation, 1);
      expect(state.source.sourceId, 'F1_MOON.JPG');
      expect(
        state.coreEffects.map((effect) => effect.id).toList(),
        ['PIXEL', 'GLITCH', 'POSTER', 'HUE', 'MIRROR', 'MIX'],
      );
      expect(state.coreEffects[1].enabled, isTrue);
      expect(state.coreEffects[5].enabled, isTrue);
      expect(state.coreEffects[5].value, 60);
    });

    test('advertises actual legacy limitations rather than fake capabilities',
        () async {
      await connector.connect(record);
      await connector.authenticate();
      final capabilities = await connector.getCapabilities();

      expect(capabilities.supports('control.commands'), isFalse);
      expect(capabilities.supports('control.events'), isFalse);
      expect(capabilities.supports('control.adapter_polling'), isTrue);
      expect(capabilities.supports('security.legacy_unauthenticated'), isTrue);
      expect(capabilities.supports('preview.source'), isTrue);
      expect(capabilities.supports('preview.processed'), isFalse);
      expect(capabilities.supports('media.video'), isFalse);
    });

    test('maps current source to a normalized HTTP JPEG media endpoint',
        () async {
      await connector.connect(record);
      await connector.authenticate();
      final endpoints = await connector.getMediaEndpoints();

      expect(endpoints, hasLength(1));
      final endpoint = endpoints.single;
      expect(endpoint.purpose, MediaPurpose.sourcePreview);
      expect(endpoint.transport, 'http-jpeg');
      expect(endpoint.codecOrFormat, 'jpeg');
      expect(
        endpoint.sessionDescriptor['url'],
        'http://${server.address.address}:${server.port}/source/F1_MOON.JPG',
      );
    });

    test('remote commands fail explicitly because protected baseline is read-only',
        () async {
      await connector.connect(record);
      await connector.authenticate();
      final response = await connector.sendCommand(const PrismaCommand(
        commandId: 'legacy-command',
        type: 'SET_INTENSITY',
        payload: {'intensity': 80},
        origin: 'TEST',
        expectedGeneration: 1,
        timestampMs: 1,
      ));

      expect(response['ok'], isFalse);
      expect((response['error'] as Map)['code'], 'UNSUPPORTED_COMMAND');
      expect(legacyState['intensity'], 61);
    });

    test('poll adapter emits state changes and session resynchronizes', () async {
      final session = PrismaSessionManager(
        connector,
        reconnectPolicy: const ReconnectPolicy(
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 20),
          maxAttempts: 2,
        ),
      );
      addTearDown(session.dispose);

      await session.open(record);
      expect(session.snapshot.phase, SessionPhase.ready);
      expect(session.snapshot.state?.generation, 1);

      final updated = session.snapshots.firstWhere(
        (snapshot) =>
            snapshot.phase == SessionPhase.ready &&
            snapshot.state?.generation == 2,
      );

      legacyState = <String, dynamic>{
        ...legacyState,
        'generation': 2,
        'intensity': 77,
      };

      final snapshot = await updated.timeout(const Duration(seconds: 2));
      expect(snapshot.state?.intensity, 77);
      expect(snapshot.state?.generation, 2);
    });

    test('legacy mode value 1 maps to bypass', () async {
      legacyState = <String, dynamic>{...legacyState, 'mode': 1};
      await connector.connect(record);
      await connector.authenticate();
      expect((await connector.getState()).mode, SynthesisMode.bypass);
    });
  });
}
