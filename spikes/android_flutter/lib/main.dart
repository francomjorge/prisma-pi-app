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
  String resourceState = 'not sampled';
  bool mediaImportBusy = false;
  bool nativeSurfaceVisible = false;
  int nativeSurfaceGeneration = 0;
  AndroidMediaImportDiagnosticResult? activeMedia;
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

  Future<void> probeResources() async {
    try {
      final result = await mediaChannel.invokeMapMethod<String, dynamic>(
        'resourceSnapshot',
      );
      if (!mounted) return;
      setState(() {
        resourceState = 'images=${result?['decoded_image_bytes'] ?? '?'} B · '
            'decoders=${result?['active_video_decoders'] ?? '?'} · '
            'surfaces=${result?['active_render_surfaces'] ?? '?'}';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => resourceState = 'resource error: ${error.code}');
    }
  }

  Future<void> pickAndImportMedia() async {
    if (mediaImportBusy) return;
    setState(() {
      mediaImportBusy = true;
      mediaImportState = 'waiting for Android document picker';
    });

    try {
      final diagnostic = await mediaImportDiagnostic.pickAndImport();
      if (!mounted) return;
      setState(() {
        if (diagnostic == null) {
          mediaImportState = 'picker cancelled';
          return;
        }

        final asset = diagnostic.asset;
        final decode = diagnostic.decodeProbe;
        activeMedia = diagnostic;
        nativeSurfaceGeneration += 1;
        nativeSurfaceVisible = true;
        mediaImportState = '${asset.type.name}: ${asset.displayName} · '
            '${asset.width ?? '?'}x${asset.height ?? '?'} · '
            '${asset.byteSize} bytes · SHA-256 ${asset.contentHash.value.substring(0, 12)}… · '
            'decode=${decode['backend'] ?? '?'} '
            '${decode['width'] ?? '?'}x${decode['height'] ?? '?'}';
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) await probeResources();
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

  void releaseNativeSurface() {
    setState(() => nativeSurfaceVisible = false);
    Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
      if (mounted) probeResources();
    });
  }

  void reopenNativeSurface() {
    if (activeMedia == null) return;
    setState(() {
      nativeSurfaceGeneration += 1;
      nativeSurfaceVisible = true;
    });
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
    final isVideo = activeMedia?.asset.type.name == 'video';

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
                Text('Native resources: $resourceState'),
                if (activeMedia != null)
                  Text(
                    'Render path: ${isVideo ? 'Media3 → SurfaceTexture → OES/GLSL → POSTERIZE' : 'target-sized native image'}',
                  ),
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
                  child: const Text('Pick + import + decode image/video'),
                ),
                ElevatedButton(
                  onPressed: probeResources,
                  child: const Text('Sample native media resources'),
                ),
                if (activeMedia != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              nativeSurfaceVisible ? releaseNativeSurface : reopenNativeSurface,
                          child: Text(
                            nativeSurfaceVisible
                                ? 'Release native surface'
                                : 'Reopen native surface',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (activeMedia != null && nativeSurfaceVisible) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 240,
                    child: AndroidView(
                      key: ValueKey(
                        '${activeMedia!.managedPath}-$nativeSurfaceGeneration',
                      ),
                      viewType: isVideo
                          ? 'prisma.pi/gpu_video_surface'
                          : 'prisma.pi/native_media_surface',
                      creationParamsCodec: const StandardMessageCodec(),
                      creationParams: {
                        'path': activeMedia!.managedPath,
                        'kind': activeMedia!.asset.type.name,
                        'fit': 'contain',
                        'target_width': 1280,
                        'target_height': 720,
                        'autoplay': true,
                        'loop': true,
                        'muted': true,
                        'effect': isVideo ? 'posterize' : 'passthrough',
                        'effect_amount': 0.85,
                        'posterize_levels': 6,
                      },
                    ),
                  ),
                ],
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
