enum ProcessingRuntimeBackendKind { gpu, cpu, remote }

enum ProcessingFrameTransport {
  opaqueGpuTexture,
  opaqueNativeSurface,
  cpuBuffer,
  remoteStream,
}

enum UnsupportedNodePolicy { reject, bypass }

class ProcessingBackendCapabilities {
  ProcessingBackendCapabilities({
    required this.backendId,
    required this.kind,
    required Iterable<String> supportedNodeTypes,
    required Iterable<String> providedCapabilities,
    required this.maxActiveNodes,
    required Iterable<ProcessingFrameTransport> supportedInputTransports,
    required Iterable<ProcessingFrameTransport> supportedOutputTransports,
    required this.supportsDynamicGraphUpdates,
    required this.supportsAlpha,
  })  : supportedNodeTypes = Set.unmodifiable(
          supportedNodeTypes.map(_normalizeNodeType),
        ),
        providedCapabilities = Set.unmodifiable(providedCapabilities),
        supportedInputTransports = Set.unmodifiable(supportedInputTransports),
        supportedOutputTransports = Set.unmodifiable(supportedOutputTransports) {
    if (backendId.trim().isEmpty) {
      throw ArgumentError.value(backendId, 'backendId', 'must not be empty');
    }
    if (maxActiveNodes < 1) {
      throw ArgumentError.value(
        maxActiveNodes,
        'maxActiveNodes',
        'must be at least 1',
      );
    }
    if (this.supportedInputTransports.isEmpty) {
      throw ArgumentError('supportedInputTransports must not be empty');
    }
    if (this.supportedOutputTransports.isEmpty) {
      throw ArgumentError('supportedOutputTransports must not be empty');
    }
  }

  final String backendId;
  final ProcessingRuntimeBackendKind kind;
  final Set<String> supportedNodeTypes;
  final Set<String> providedCapabilities;
  final int maxActiveNodes;
  final Set<ProcessingFrameTransport> supportedInputTransports;
  final Set<ProcessingFrameTransport> supportedOutputTransports;
  final bool supportsDynamicGraphUpdates;
  final bool supportsAlpha;

  bool supportsNodeType(String type) =>
      supportedNodeTypes.contains(_normalizeNodeType(type));

  bool providesAll(Iterable<String> capabilities) =>
      capabilities.every(providedCapabilities.contains);
}

class ProcessingInputBinding {
  ProcessingInputBinding({
    required this.bindingId,
    required this.transport,
    required this.locator,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    _validateBinding(bindingId, locator);
  }

  final String bindingId;
  final ProcessingFrameTransport transport;
  final String locator;
  final Map<String, Object?> metadata;
}

class ProcessingOutputBinding {
  ProcessingOutputBinding({
    required this.bindingId,
    required this.transport,
    required this.locator,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    _validateBinding(bindingId, locator);
  }

  final String bindingId;
  final ProcessingFrameTransport transport;
  final String locator;
  final Map<String, Object?> metadata;
}

class RuntimeProcessingNode {
  RuntimeProcessingNode({
    required this.nodeId,
    required String type,
    required Map<String, Object?> parameters,
    required this.order,
  })  : type = _normalizeNodeType(type),
        parameters = Map.unmodifiable(parameters) {
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(nodeId, 'nodeId', 'must not be empty');
    }
    if (this.type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'must not be empty');
    }
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must not be negative');
    }
  }

  final String nodeId;
  final String type;
  final Map<String, Object?> parameters;
  final int order;

  RuntimeProcessingNode copyWith({int? order}) => RuntimeProcessingNode(
        nodeId: nodeId,
        type: type,
        parameters: parameters,
        order: order ?? this.order,
      );

  Map<String, Object?> toPlatformMap() => {
        'node_id': nodeId,
        'type': type,
        'order': order,
        'parameters': parameters,
      };
}

class ProcessingPlan {
  factory ProcessingPlan({
    int schemaVersion = 1,
    required Iterable<RuntimeProcessingNode> nodes,
  }) {
    if (schemaVersion < 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be at least 1',
      );
    }

    final sorted = nodes.toList()..sort((a, b) => a.order.compareTo(b.order));
    final ids = <String>{};
    for (final node in sorted) {
      if (!ids.add(node.nodeId)) {
        throw ArgumentError('duplicate processing node id: ${node.nodeId}');
      }
    }

    final normalized = <RuntimeProcessingNode>[
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
    ];
    return ProcessingPlan._(
      schemaVersion: schemaVersion,
      nodes: List.unmodifiable(normalized),
    );
  }

  const ProcessingPlan._({
    required this.schemaVersion,
    required this.nodes,
  });

  final int schemaVersion;
  final List<RuntimeProcessingNode> nodes;

  bool get isPassThrough => nodes.isEmpty;

  Map<String, Object?> toPlatformMap() => {
        'schema_version': schemaVersion,
        'nodes': [for (final node in nodes) node.toPlatformMap()],
      };
}

class ProcessingSessionRequest {
  ProcessingSessionRequest({
    required this.plan,
    required this.input,
    required this.output,
  });

  final ProcessingPlan plan;
  final ProcessingInputBinding input;
  final ProcessingOutputBinding output;

  void validateAgainst(ProcessingBackendCapabilities capabilities) {
    if (!capabilities.supportedInputTransports.contains(input.transport)) {
      throw ProcessingRuntimeException(
        code: 'UNSUPPORTED_INPUT_TRANSPORT',
        message:
            '${capabilities.backendId} does not support ${input.transport.name}',
      );
    }
    if (!capabilities.supportedOutputTransports.contains(output.transport)) {
      throw ProcessingRuntimeException(
        code: 'UNSUPPORTED_OUTPUT_TRANSPORT',
        message:
            '${capabilities.backendId} does not support ${output.transport.name}',
      );
    }
    if (plan.nodes.length > capabilities.maxActiveNodes) {
      throw ProcessingRuntimeException(
        code: 'ACTIVE_NODE_LIMIT_EXCEEDED',
        message:
            '${plan.nodes.length} active nodes exceed backend limit ${capabilities.maxActiveNodes}',
      );
    }
  }
}

abstract interface class ProcessingRuntimeAdapter {
  ProcessingBackendCapabilities get capabilities;

  Future<ProcessingRuntimeSession> openSession(ProcessingSessionRequest request);
}

abstract interface class ProcessingRuntimeSession {
  String get sessionId;

  ProcessingPlan get plan;

  Future<void> updatePlan(ProcessingPlan plan);

  Future<void> close();
}

class ProcessingRuntimeException implements Exception {
  const ProcessingRuntimeException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'ProcessingRuntimeException($code): $message';
}

String normalizeProcessingNodeType(String type) => _normalizeNodeType(type);

String _normalizeNodeType(String type) => type.trim().toUpperCase();

void _validateBinding(String bindingId, String locator) {
  if (bindingId.trim().isEmpty) {
    throw ArgumentError.value(bindingId, 'bindingId', 'must not be empty');
  }
  if (locator.trim().isEmpty) {
    throw ArgumentError.value(locator, 'locator', 'must not be empty');
  }
}
