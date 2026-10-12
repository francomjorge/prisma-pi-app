import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  testWidgets('M0 diagnostic harness boots', (tester) async {
    await tester.pumpWidget(const PrismaAndroidStackSpike());
    expect(find.text('PRISMA-PI / M0 ANDROID STACK SPIKE'), findsOneWidget);
    expect(find.textContaining('Diagnostic harness only'), findsOneWidget);
  });
}
