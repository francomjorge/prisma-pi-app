import 'dart:io';

import 'package:prisma_mock_appliance/prisma_mock_appliance.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8791 : int.parse(args.first);
  final server = PrismaMockApplianceServer();
  await server.start(address: InternetAddress.anyIPv4, port: port);

  stdout.writeln('PRISMA Mock Appliance listening at ${server.baseUri}');
  stdout.writeln('Press Ctrl+C to stop.');

  ProcessSignal.sigint.watch().first.then((_) async {
    await server.close();
    exit(0);
  });
}
