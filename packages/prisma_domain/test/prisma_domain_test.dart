import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ProtocolVersion', () {
    test('major mismatch requires compatibility adapter', () {
      const v2 = ProtocolVersion(major: 2, minor: 0);
      const legacy = ProtocolVersion(major: 1, minor: 9);
      expect(v2.compatibilityWith(legacy), ProtocolCompatibility.requiresAdapter);
    });
  });

  group('GenerationCursor', () {
    test('detects sequential events, stale events and gaps', () {
      final cursor = GenerationCursor(10);
      expect(cursor.inspect(11), GenerationDecision.accept);
      cursor.accept(11);
      expect(cursor.inspect(11), GenerationDecision.staleOrDuplicate);
      expect(cursor.inspect(13), GenerationDecision.gap);
    });
  });

  test('PrismaState requires exactly six Core FX slots and round-trips JSON', () {
    final effects = List.generate(
      6,
      (i) => CoreEffectState(id: 'FX${i + 1}', enabled: i.isEven, value: i * 10, generation: 4),
    );
    final state = PrismaState(
      power: true,
      mode: SynthesisMode.random,
      intensity: 61,
      source: const SourceState(
        sourceId: 'moon',
        playbackState: PlaybackState.playing,
        positionMs: 0,
        generation: 4,
      ),
      coreEffects: effects,
      generation: 4,
    );
    final decoded = PrismaState.fromJson(state.toJson());
    expect(decoded.generation, 4);
    expect(decoded.intensity, 61);
    expect(decoded.coreEffects, hasLength(6));
    expect(decoded.source.sourceId, 'moon');
  });

  test('ProcessingGraph normalizes order and supports deterministic reorder', () {
    ProcessingNode node(String id, int order) => ProcessingNode(
          nodeId: id,
          type: 'visual_fx',
          enabled: true,
          bypass: false,
          parameters: const {'amount': 50},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: order,
        );

    final graph = ProcessingGraph([node('poster', 2), node('pixel', 0), node('glitch', 1)]);
    expect(graph.nodes.map((e) => e.nodeId), ['pixel', 'glitch', 'poster']);
    final moved = graph.reorder('poster', 0);
    expect(moved.nodes.map((e) => e.nodeId), ['poster', 'pixel', 'glitch']);
    expect(moved.nodes.map((e) => e.order), [0, 1, 2]);
  });
}
