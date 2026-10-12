enum ProtocolCompatibility { compatible, requiresAdapter }

enum GenerationDecision { accept, staleOrDuplicate, gap }

class ProtocolVersion {
  const ProtocolVersion({this.family = 'PRISMA', required this.major, required this.minor});

  final String family;
  final int major;
  final int minor;

  ProtocolCompatibility compatibilityWith(ProtocolVersion other) {
    if (family != other.family || major != other.major) {
      return ProtocolCompatibility.requiresAdapter;
    }
    return ProtocolCompatibility.compatible;
  }

  Map<String, dynamic> toJson() => {'family': family, 'major': major, 'minor': minor};

  factory ProtocolVersion.fromJson(Map<String, dynamic> json) => ProtocolVersion(
        family: json['family'] as String? ?? 'PRISMA',
        major: json['major'] as int,
        minor: json['minor'] as int,
      );
}

class PrismaCommand {
  const PrismaCommand({
    required this.commandId,
    required this.type,
    required this.payload,
    required this.origin,
    this.expectedGeneration,
    required this.timestampMs,
  });

  final String commandId;
  final String type;
  final Map<String, dynamic> payload;
  final String origin;
  final int? expectedGeneration;
  final int timestampMs;

  Map<String, dynamic> toJson() => {
        'command_id': commandId,
        'type': type,
        'payload': payload,
        'origin': origin,
        if (expectedGeneration != null) 'expected_generation': expectedGeneration,
        'timestamp_ms': timestampMs,
      };

  factory PrismaCommand.fromJson(Map<String, dynamic> json) => PrismaCommand(
        commandId: json['command_id'] as String,
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        origin: json['origin'] as String,
        expectedGeneration: json['expected_generation'] as int?,
        timestampMs: json['timestamp_ms'] as int,
      );
}

class PrismaEvent {
  const PrismaEvent({
    required this.eventId,
    required this.type,
    required this.deviceId,
    required this.generation,
    required this.timestampMs,
    required this.payload,
  });

  final String eventId;
  final String type;
  final String deviceId;
  final int generation;
  final int timestampMs;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'type': type,
        'device_id': deviceId,
        'generation': generation,
        'timestamp_ms': timestampMs,
        'payload': payload,
      };
}

class GenerationCursor {
  GenerationCursor([this.current = 0]);

  int current;

  GenerationDecision inspect(int incoming) {
    if (incoming <= current) return GenerationDecision.staleOrDuplicate;
    if (incoming == current + 1) return GenerationDecision.accept;
    return GenerationDecision.gap;
  }

  void accept(int incoming) {
    final decision = inspect(incoming);
    if (decision != GenerationDecision.accept) {
      throw StateError('Cannot accept generation $incoming from $current: $decision');
    }
    current = incoming;
  }

  void resetToSnapshot(int generation) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    current = generation;
  }
}
