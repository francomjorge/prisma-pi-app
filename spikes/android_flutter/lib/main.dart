import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_media_import_diagnostic.dart';

void main() => runApp(const PrismaAndroidStackSpike());

class PrismaAndroidStackSpike extends StatefulWidget {
  const PrismaAndroidStackSpike({super.key});

  @override
  State<PrismaAndroidStackSpike> createState() => _PrismaAndroidStackSpikeState();
}

class _PrismaAndroidStackSpikeState extends State<PrismaAndroidStackSpike> {
  static const mediaChannel = MethodChannel('prisma.pi/media');
  static const securityChannel = MethodChannel('prisma.pi/security');
  static const discoveryChannel = EventChannel('prisma.pi/discovery');

  final FocusNode keyboardFocusNode = FocusNode(debugLabel: 'm0-hardware-keyboard');
  late final AndroidMediaImportDiagnostic mediaImportDiagnostic;

  String nativeBoundary = 'not probed';
  String secureStoreState = 'not probed';
  String lastKey = 'none';
  String discoveryState = 'not started';
  String mediaImportState = 'not tested';
  bool mediaImportBusy = false;
  StreamSubscription<dynamic>? discoverySubscription;

  @override
  void initState() {
    super.initState();
    mediaImportDiagnostic = AndroidMediaImportDiagnostic(mediaChannel);
  }

  Future<void> probeNativeBoundary() async {
    try {
      final result = await mediaChannel.invokeMapMethod<String, dynamic>('ping');
      if (!mounted) return;
      setState(() => nativeBoundary = '${result?['platform']}/${result?['boundary']}');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => nativeBoundary = 'platform error: ${e.code}');
    }
  }

  Future<void> probeSecureStore() async {
    try {
      final result =
          await securityChannel.invokeMapMethod<String, dynamic>('secureStoreProbe');
      final supported = result?['supported'] == true;
      final roundTrip = result?['round_trip'] == true;
      if (!mounted) return;
      setState(() {
        secureStoreState = supported
            ? 'AndroidKeyStore AES/GCM round-trip=${roundTrip ? 'ok' : 'failed'}'
            : 'unsupported: ${result?['reason'] ?? 'unknown'}';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => secureStoreState = 'keystore error: ${e.code}');
    }
  }

  Future<void> pickAndImportMedia() async {
    if (mediaImportBusy) return;
    setState(() {
      mediaImportBusy = true;
      mediaImportState = 'waiting for Android document picker';
    });

    try {
      final asset = await mediaImportDiagnostic.pickAndImport();
      if (!mounted) return;
      setState(() {
        mediaImportState = asset == null
            ? 'picker cancelled'
            : '${asset.type.name}: ${asset.displayName} · '
                '${asset.width ?? '?'}x${asset.height ?? '?'} · '
                '${asset.byteSize} bytes · SHA-256 ${asset.contentHash.value.substring(0, 12)}…';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => mediaImportState = 'platform error: ${error.code}');
    } catch (error) {
      if (!mounted) return;
      setState(() => mediaImportState = 'import error: $error');
    } finally {
      if (mounted) setState(() => mediaImportBusy = false);
    }
  }

  void startDiscoveryProbe() {
    discoverySubscription?.cancel();
    setState(() => discoveryState = 'listening for _prisma-pi._tcp');
    discoverySubscription = discoveryChannel.receiveBroadcastStream().listen(
      (event) {
        if (!mounted) return;
        final record = Map<String, dynamic>.from(event as Map);
        setState(() {
          discoveryState =
              '${record['service_name'] ?? 'PRISMA'} @ ${record['host'] ?? '?'}:${record['port'] ?? '?'}';
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        if (error is PlatformException) {
          setState(() => discoveryState = 'discovery error: ${error.code}');
        } else {
          setState(() => discoveryState = 'discovery error: $error');
        }
      },
    );
  }

  @override
  void dispose() {
    discoverySubscription?.cancel();
    keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KeyboardListener(
        autofocus: true,
        focusNode: keyboardFocusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            setState(() => lastKey = event.logicalKey.keyLabel);
          }
        },
        child: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'PRISMA-PI / M0 ANDROID STACK SPIKE',
                  textScaler: TextScaler.linear(1.2),
                ),
                const SizedBox(height: 24),
                Text('Native media boundary: $nativeBoundary'),
                Text('Secure store: $secureStoreState'),
                Text('Last hardware key: $lastKey'),
                Text('NSD: $discoveryState'),
                Text('SAF managed import: $mediaImportState'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: probeNativeBoundary,
                  child: const Text('Probe native boundary'),
                ),
                ElevatedButton(
                  onPressed: probeSecureStore,
                  child: const Text('Probe Android Keystore'),
                ),
                ElevatedButton(
                  onPressed: startDiscoveryProbe,
                  child: const Text('Probe PRISMA NSD'),
                ),
                ElevatedButton(
                  onPressed: mediaImportBusy ? null : pickAndImportMedia,
                  child: const Text('Pick + import image/video'),
                ),
                const SizedBox(height: 36),
                const Text('Diagnostic harness only — not product UI.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
