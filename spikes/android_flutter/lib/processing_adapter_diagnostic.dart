import 'package:prisma_domain/prisma_domain.dart';
import 'package:prisma_processing_runtime/prisma_processing_runtime.dart';

Map<String, Object?> buildDiagnosticProcessingPlan() {
  final backend = ProcessingBackendCapabilities(
    backendId: 'android-gpu-surface-texture-spike',
    kind: ProcessingRuntimeBackendKind.gpu,
    supportedNodeTypes: const {'POSTER', 'GRAYSCALE'},
    providedCapabilities: const {
      'gpu.external_texture',
      'gpu.fragment_shader',
      'gpu.ping_pong_targets',
    },
    maxActiveNodes: 4,
    supportedInputTransports: const {
      ProcessingFrameTransport.opaqueNativeSurface,
      ProcessingFrameTransport.opaqueGpuTexture,
    },
    supportedOutputTransports: const {
      ProcessingFrameTransport.opaqueNativeSurface,
      ProcessingFrameTransport.opaqueGpuTexture,
    },
    supportsDynamicGraphUpdates: false,
    supportsAlpha: true,
  );

  final graph = ProcessingGraph([
    ProcessingNode(
      nodeId: 'm0-poster-pass',
      type: 'POSTER',
      enabled: true,
      bypass: false,
      parameters: const {
        'amount': 0.85,
        'levels': 6,
      },
      executionTarget: ProcessingExecutionTarget.mobile,
      requiredCapabilities: const [
        'gpu.external_texture',
        'gpu.fragment_shader',
        'gpu.ping_pong_targets',
      ],
      order: 0,
    ),
    ProcessingNode(
      nodeId: 'm0-grayscale-pass',
      type: 'GRAYSCALE',
      enabled: true,
      bypass: false,
      parameters: const {
        'amount': 0.35,
      },
      executionTarget: ProcessingExecutionTarget.mobile,
      requiredCapabilities: const [
        'gpu.fragment_shader',
        'gpu.ping_pong_targets',
      ],
      order: 1,
    ),
  ]);

  final compiled = const ProcessingGraphCompiler().compileLocal(
    graph: graph,
    backend: backend,
  );
  return compiled.plan.toPlatformMap();
}
