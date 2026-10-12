import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const PrismaAndroidStackSpike());

class PrismaAndroidStackSpike extends StatefulWidget {
  const PrismaAndroidStackSpike({super.key});

  @override
  State<PrismaAndroidStackSpike> createState() => _PrismaAndroidStackSpikeState();
}

class _PrismaAndroidStackSpikeState extends State<PrismaAndroidStackSpike> {
  static const mediaChannel = MethodChannel('prisma.pi/media');
  static const discoveryChannel = EventChannel('prisma.pi/discovery');

  String nativeBoundary = 'not probed';
  String lastKey = 'none';
  String discoveryState = 'not started';
  StreamSubscription<dynamic>? discoverySubscription;

  Future<void> probeNativeBoundary() async {
    try {
      final result = await mediaChannel.invokeMapMethod<String, dynamic>('ping');
      setState(() => nativeBoundary = '${result?['platform']}/${result?['boundary']}');
    } on PlatformException catch (e) {
      setState(() => nativeBoundary = 'platform error: ${e.code}');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KeyboardListener(
        autofocus: true,
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) setState(() => lastKey = event.logicalKey.keyLabel);
        },
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PRISMA-PI / M0 ANDROID STACK SPIKE', textScaler: TextScaler.linear(1.2)),
                  const SizedBox(height: 24),
                  Text('Native media boundary: $nativeBoundary'),
                  Text('Last hardware key: $lastKey'),
                  Text('NSD: $discoveryState'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: probeNativeBoundary, child: const Text('Probe native boundary')),
                  ElevatedButton(onPressed: startDiscoveryProbe, child: const Text('Probe PRISMA NSD')),
                  const Spacer(),
                  const Text('Diagnostic harness only — not product UI.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
