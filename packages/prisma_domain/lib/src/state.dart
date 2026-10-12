enum SynthesisMode { random, bypass }
enum PlaybackState { stopped, playing, paused }

class SourceState {
  const SourceState({required this.sourceId, required this.playbackState, required this.positionMs, required this.generation});
  final String? sourceId;
  final PlaybackState playbackState;
  final int positionMs;
  final int generation;

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'playback_state': playbackState.name.toUpperCase(),
        'position_ms': positionMs,
        'generation': generation,
      };

  factory SourceState.fromJson(Map<String, dynamic> json) => SourceState(
        sourceId: json['source_id'] as String?,
        playbackState: PlaybackState.values.firstWhere(
          (v) => v.name.toUpperCase() == (json['playback_state'] as String? ?? 'STOPPED'),
          orElse: () => PlaybackState.stopped,
        ),
        positionMs: json['position_ms'] as int? ?? 0,
        generation: json['generation'] as int? ?? 0,
      );
}

class CoreEffectState {
  const CoreEffectState({required this.id, required this.enabled, required this.value, required this.generation});
  final String id;
  final bool enabled;
  final double value;
  final int generation;

  Map<String, dynamic> toJson() => {'id': id, 'enabled': enabled, 'value': value, 'generation': generation};

  factory CoreEffectState.fromJson(Map<String, dynamic> json) => CoreEffectState(
        id: json['id'] as String,
        enabled: json['enabled'] as bool? ?? false,
        value: (json['value'] as num? ?? 0).toDouble(),
        generation: json['generation'] as int? ?? 0,
      );
}

class PrismaState {
  PrismaState({
    required this.power,
    required this.mode,
    required this.intensity,
    required this.source,
    required List<CoreEffectState> coreEffects,
    required this.generation,
  }) : coreEffects = List.unmodifiable(coreEffects) {
    if (intensity < 0 || intensity > 100) throw RangeError.range(intensity, 0, 100, 'intensity');
    if (coreEffects.length != 6) throw ArgumentError.value(coreEffects.length, 'coreEffects', 'exactly six Core FX slots required');
  }

  final bool power;
  final SynthesisMode mode;
  final int intensity;
  final SourceState source;
  final List<CoreEffectState> coreEffects;
  final int generation;

  Map<String, dynamic> toJson() => {
        'power': power,
        'mode': mode.name.toUpperCase(),
        'intensity': intensity,
        'source': source.toJson(),
        'core_effects': coreEffects.map((e) => e.toJson()).toList(growable: false),
        'generation': generation,
      };

  factory PrismaState.fromJson(Map<String, dynamic> json) => PrismaState(
        power: json['power'] as bool? ?? false,
        mode: (json['mode'] as String? ?? 'BYPASS') == 'RANDOM' ? SynthesisMode.random : SynthesisMode.bypass,
        intensity: json['intensity'] as int? ?? 0,
        source: SourceState.fromJson(Map<String, dynamic>.from(json['source'] as Map? ?? const {})),
        coreEffects: (json['core_effects'] as List? ?? const [])
            .map((e) => CoreEffectState.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        generation: json['generation'] as int? ?? 0,
      );
}
