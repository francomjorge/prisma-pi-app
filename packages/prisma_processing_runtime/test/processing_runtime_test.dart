import 'package:prisma_domain/prisma_domain.dart';
import 'package:prisma_processing_runtime/prisma_processing_runtime.dart';
import 'package:test/test.dart';

void main() {
  final backend = ProcessingBackendCapabilities(
    backendId: 'android-gpu-spike',
    kind: ProcessingRuntimeBackendKind.gpu,
    supportedNodeTypes: const {'POSTER', 'HUE'},
    providedCapabilities: const {'gpu.external_texture', 'gpu.fragment_shader'},
    maxActiveNodes: 4,
    supportedInputTransports: const {
      ProcessingFrameTransport.opaqueGpuTexture,
      ProcessingFrameTransport.opaqueNativeSurface,
    },
    supportedOutputTransports: const {
      ProcessingFrameTransport.opaqueGpuTexture,
      ProcessingFrameTransport.opaqueNativeSurface,
    },
    supportsDynamicGraphUpdates: true,
    supportsAlpha: true,
  );

  group('ProcessingGraphCompiler', () {
    const compiler = ProcessingGraphCompiler();

    test('compiles only active mobile/both nodes and preserves order', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'remote-pixel',
          type: 'PIXEL',
          enabled: true,
          bypass: false,
          parameters: const {'amount': 0.5},
          executionTarget: ProcessingExecutionTarget.appliance,
          requiredCapabilities: const [],
          order: 0,
        ),
        ProcessingNode(
          nodeId: 'poster',
          type: 'poster',
          enabled: true,
          bypass: false,
          parameters: const {'amount': 0.85, 'levels': 6},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const ['gpu.external_texture'],
          order: 1,
        ),
        ProcessingNode(
          nodeId: 'bypassed-hue',
          type: 'HUE',
          enabled: true,
          bypass: true,
          parameters: const {'degrees': 20},
          executionTarget: ProcessingExecutionTarget.both,
          requiredCapabilities: const [],
          order: 2,
        ),
        ProcessingNode(
          nodeId: 'disabled-hue',
          type: 'HUE',
          enabled: false,
          bypass: false,
          parameters: const {'degrees': 40},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 3,
        ),
      ]);

      final result = compiler.compileLocal(graph: graph, backend: backend);

      expect(result.diagnostics, isEmpty);
      expect(result.plan.nodes, hasLength(1));
      expect(result.plan.nodes.single.nodeId, 'poster');
      expect(result.plan.nodes.single.type, 'POSTER');
      expect(result.plan.nodes.single.order, 0);
      expect(result.plan.nodes.single.parameters['levels'], 6);
    });

    test('compiled plan order follows domain graph reorder exactly', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'poster',
          type: 'POSTER',
          enabled: true,
          bypass: false,
          parameters: const {'amount': 0.8},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 0,
        ),
        ProcessingNode(
          nodeId: 'hue',
          type: 'HUE',
          enabled: true,
          bypass: false,
          parameters: const {'degrees': 30},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 1,
        ),
      ]);

      final original = compiler.compileLocal(graph: graph, backend: backend);
      final reorderedGraph = graph.reorder('hue', 0);
      final reordered = compiler.compileLocal(
        graph: reorderedGraph,
        backend: backend,
      );

      expect(
        original.plan.nodes.map((node) => node.nodeId).toList(),
        ['poster', 'hue'],
      );
      expect(
        reordered.plan.nodes.map((node) => node.nodeId).toList(),
        ['hue', 'poster'],
      );
      expect(reordered.plan.nodes.map((node) => node.order).toList(), [0, 1]);
    });

    test('bypass removes a supported node without changing remaining order', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'poster',
          type: 'POSTER',
          enabled: true,
          bypass: true,
          parameters: const {'amount': 0.8},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 0,
        ),
        ProcessingNode(
          nodeId: 'hue',
          type: 'HUE',
          enabled: true,
          bypass: false,
          parameters: const {'degrees': 30},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 1,
        ),
      ]);

      final result = compiler.compileLocal(graph: graph, backend: backend);

      expect(result.plan.nodes.map((node) => node.nodeId).toList(), ['hue']);
      expect(result.plan.nodes.single.order, 0);
    });

    test('rejects an unsupported local node by default', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'glitch',
          type: 'GLITCH',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 0,
        ),
      ]);

      expect(
        () => compiler.compileLocal(graph: graph, backend: backend),
        throwsA(
          isA<ProcessingRuntimeException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_NODE_TYPE',
          ),
        ),
      );
    });

    test('can explicitly bypass unsupported nodes with diagnostics', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'glitch',
          type: 'GLITCH',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 0,
        ),
        ProcessingNode(
          nodeId: 'poster',
          type: 'POSTER',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 1,
        ),
      ]);

      final result = compiler.compileLocal(
        graph: graph,
        backend: backend,
        unsupportedNodePolicy: UnsupportedNodePolicy.bypass,
      );

      expect(result.plan.nodes.map((node) => node.nodeId), ['poster']);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.code, 'UNSUPPORTED_NODE_TYPE');
      expect(result.diagnostics.single.nodeId, 'glitch');
    });

    test('rejects a node when a required backend capability is missing', () {
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'poster',
          type: 'POSTER',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const ['gpu.compute_shader'],
          order: 0,
        ),
      ]);

      expect(
        () => compiler.compileLocal(graph: graph, backend: backend),
        throwsA(
          isA<ProcessingRuntimeException>().having(
            (error) => error.code,
            'code',
            'MISSING_BACKEND_CAPABILITY',
          ),
        ),
      );
    });

    test('enforces backend active-node limit', () {
      final limitedBackend = ProcessingBackendCapabilities(
        backendId: 'one-node-gpu',
        kind: ProcessingRuntimeBackendKind.gpu,
        supportedNodeTypes: const {'POSTER', 'HUE'},
        providedCapabilities: const {},
        maxActiveNodes: 1,
        supportedInputTransports: const {
          ProcessingFrameTransport.opaqueGpuTexture,
        },
        supportedOutputTransports: const {
          ProcessingFrameTransport.opaqueGpuTexture,
        },
        supportsDynamicGraphUpdates: false,
        supportsAlpha: false,
      );
      final graph = ProcessingGraph([
        ProcessingNode(
          nodeId: 'poster',
          type: 'POSTER',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 0,
        ),
        ProcessingNode(
          nodeId: 'hue',
          type: 'HUE',
          enabled: true,
          bypass: false,
          parameters: const {},
          executionTarget: ProcessingExecutionTarget.mobile,
          requiredCapabilities: const [],
          order: 1,
        ),
      ]);

      expect(
        () => compiler.compileLocal(graph: graph, backend: limitedBackend),
        throwsA(
          isA<ProcessingRuntimeException>().having(
            (error) => error.code,
            'code',
            'ACTIVE_NODE_LIMIT_EXCEEDED',
          ),
        ),
      );
    });
  });

  group('ProcessingPlan', () {
    test('serializes a deterministic platform-neutral plan', () {
      final plan = ProcessingPlan(
        nodes: [
          RuntimeProcessingNode(
            nodeId: 'poster',
            type: 'poster',
            parameters: const {'amount': 0.85, 'levels': 6},
            order: 4,
          ),
        ],
      );

      expect(plan.nodes.single.order, 0);
      expect(plan.toPlatformMap(), {
        'schema_version': 1,
        'nodes': [
          {
            'node_id': 'poster',
            'type': 'POSTER',
            'order': 0,
            'parameters': {'amount': 0.85, 'levels': 6},
          },
        ],
      });
    });

    test('validates opaque transport bindings against backend capabilities', () {
      final request = ProcessingSessionRequest(
        plan: ProcessingPlan(nodes: const []),
        input: ProcessingInputBinding(
          bindingId: 'decoder-output',
          transport: ProcessingFrameTransport.opaqueNativeSurface,
          locator: 'native://decoder-output/1',
        ),
        output: ProcessingOutputBinding(
          bindingId: 'gpu-target',
          transport: ProcessingFrameTransport.opaqueGpuTexture,
          locator: 'gpu://target/1',
        ),
      );

      expect(() => request.validateAgainst(backend), returnsNormally);
    });
  });
}
