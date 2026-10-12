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
    },
    maxActiveNodes: 1,
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
      nodeId: 'm0-poster-proof',
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
      ],
      order: 0,
    ),
  ]);

  final compiled = const ProcessingGraphCompiler().compileLocal(
    graph: graph,
    backend: backend,
  );
  return compiled.plan.toPlatformMap();
}
