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
  String nativeBoundary = 'not probed';
  String lastKey = 'none';

  Future<void> probeNativeBoundary() async {
    try {
      final result = await mediaChannel.invokeMapMethod<String, dynamic>('ping');
      setState(() => nativeBoundary = '${result?['platform']}/${result?['boundary']}');
    } on PlatformException catch (e) {
      setState(() => nativeBoundary = 'platform error: ${e.code}');
    }
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
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: probeNativeBoundary, child: const Text('Probe native boundary')),
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
