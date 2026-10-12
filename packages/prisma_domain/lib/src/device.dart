import 'protocol.dart';

enum MediaPurpose { sourcePreview, processedPreview, programOutput }

class DeviceDescriptor {
  const DeviceDescriptor({
    required this.deviceId,
    required this.displayName,
    required this.model,
    required this.firmwareVersion,
    required this.protocol,
    required this.pairingRequired,
    required this.securityProfiles,
    required this.capabilityDigest,
  });

  final String deviceId;
  final String displayName;
  final String model;
  final String firmwareVersion;
  final ProtocolVersion protocol;
  final bool pairingRequired;
  final List<String> securityProfiles;
  final String capabilityDigest;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'display_name': displayName,
        'model': model,
        'firmware_version': firmwareVersion,
        'protocol': protocol.toJson(),
        'pairing_required': pairingRequired,
        'security_profiles': securityProfiles,
        'capability_digest': capabilityDigest,
      };

  factory DeviceDescriptor.fromJson(Map<String, dynamic> json) => DeviceDescriptor(
        deviceId: json['device_id'] as String,
        displayName: json['display_name'] as String? ?? 'PRISMA Device',
        model: json['model'] as String? ?? 'unknown',
        firmwareVersion: json['firmware_version'] as String? ?? 'unknown',
        protocol: ProtocolVersion.fromJson(Map<String, dynamic>.from(json['protocol'] as Map)),
        pairingRequired: json['pairing_required'] as bool? ?? true,
        securityProfiles: List<String>.from(json['security_profiles'] as List? ?? const []),
        capabilityDigest: json['capability_digest'] as String? ?? '',
      );
}

class DeviceCapabilities {
  DeviceCapabilities(Map<String, dynamic> values) : values = Map.unmodifiable(values);
  final Map<String, dynamic> values;

  dynamic read(String dottedPath) {
    dynamic cursor = values;
    for (final segment in dottedPath.split('.')) {
      if (cursor is! Map || !cursor.containsKey(segment)) return null;
      cursor = cursor[segment];
    }
    return cursor;
  }

  bool supports(String dottedPath) => read(dottedPath) == true;
}

class MediaEndpoint {
  const MediaEndpoint({
    required this.purpose,
    required this.transport,
    required this.codecOrFormat,
    required this.width,
    required this.height,
    required this.fps,
    required this.audio,
    required this.latencyClass,
    required this.sessionDescriptor,
  });

  final MediaPurpose purpose;
  final String transport;
  final String codecOrFormat;
  final int width;
  final int height;
  final double fps;
  final bool audio;
  final String latencyClass;
  final Map<String, dynamic> sessionDescriptor;

  Map<String, dynamic> toJson() => {
        'purpose': switch (purpose) {
          MediaPurpose.sourcePreview => 'SOURCE_PREVIEW',
          MediaPurpose.processedPreview => 'PROCESSED_PREVIEW',
          MediaPurpose.programOutput => 'PROGRAM_OUTPUT',
        },
        'transport': transport,
        'codec_or_format': codecOrFormat,
        'width': width,
        'height': height,
        'fps': fps,
        'audio': audio,
        'latency_class': latencyClass,
        'session_descriptor': sessionDescriptor,
      };
}
