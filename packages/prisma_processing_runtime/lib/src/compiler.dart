import 'package:prisma_domain/prisma_domain.dart';

import 'contracts.dart';

class ProcessingCompileDiagnostic {
  const ProcessingCompileDiagnostic({
    required this.code,
    required this.nodeId,
    required this.message,
  });

  final String code;
  final String nodeId;
  final String message;
}

class ProcessingCompileResult {
  ProcessingCompileResult({
    required this.plan,
    required Iterable<ProcessingCompileDiagnostic> diagnostics,
  }) : diagnostics = List.unmodifiable(diagnostics);

  final ProcessingPlan plan;
  final List<ProcessingCompileDiagnostic> diagnostics;
}

class ProcessingGraphCompiler {
  const ProcessingGraphCompiler();

  ProcessingCompileResult compileLocal({
    required ProcessingGraph graph,
    required ProcessingBackendCapabilities backend,
    UnsupportedNodePolicy unsupportedNodePolicy = UnsupportedNodePolicy.reject,
  }) {
    final runtimeNodes = <RuntimeProcessingNode>[];
    final diagnostics = <ProcessingCompileDiagnostic>[];

    for (final node in graph.nodes) {
      if (!_runsLocally(node.executionTarget)) continue;
      if (!node.enabled || node.bypass) continue;

      final normalizedType = normalizeProcessingNodeType(node.type);
      if (!backend.supportsNodeType(normalizedType)) {
        final diagnostic = ProcessingCompileDiagnostic(
          code: 'UNSUPPORTED_NODE_TYPE',
          nodeId: node.nodeId,
          message:
              '${backend.backendId} does not support processing node $normalizedType',
        );
        if (unsupportedNodePolicy == UnsupportedNodePolicy.reject) {
          throw ProcessingRuntimeException(
            code: diagnostic.code,
            message: '${diagnostic.nodeId}: ${diagnostic.message}',
          );
        }
        diagnostics.add(diagnostic);
        continue;
      }

      final missingCapabilities = node.requiredCapabilities
          .where((capability) => !backend.providedCapabilities.contains(capability))
          .toList(growable: false);
      if (missingCapabilities.isNotEmpty) {
        final diagnostic = ProcessingCompileDiagnostic(
          code: 'MISSING_BACKEND_CAPABILITY',
          nodeId: node.nodeId,
          message:
              '${backend.backendId} is missing ${missingCapabilities.join(', ')}',
        );
        if (unsupportedNodePolicy == UnsupportedNodePolicy.reject) {
          throw ProcessingRuntimeException(
            code: diagnostic.code,
            message: '${diagnostic.nodeId}: ${diagnostic.message}',
          );
        }
        diagnostics.add(diagnostic);
        continue;
      }

      runtimeNodes.add(
        RuntimeProcessingNode(
          nodeId: node.nodeId,
          type: normalizedType,
          parameters: Map<String, Object?>.from(node.parameters),
          order: runtimeNodes.length,
        ),
      );
    }

    if (runtimeNodes.length > backend.maxActiveNodes) {
      throw ProcessingRuntimeException(
        code: 'ACTIVE_NODE_LIMIT_EXCEEDED',
        message:
            '${runtimeNodes.length} local nodes exceed ${backend.backendId} limit ${backend.maxActiveNodes}',
      );
    }

    return ProcessingCompileResult(
      plan: ProcessingPlan(nodes: runtimeNodes),
      diagnostics: diagnostics,
    );
  }

  bool _runsLocally(ProcessingExecutionTarget target) =>
      target == ProcessingExecutionTarget.mobile ||
      target == ProcessingExecutionTarget.both;
}
