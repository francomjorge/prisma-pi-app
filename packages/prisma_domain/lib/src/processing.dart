enum ProcessingExecutionTarget { mobile, appliance, both }

class ProcessingNode {
  ProcessingNode({
    required this.nodeId,
    required this.type,
    required this.enabled,
    required this.bypass,
    required Map<String, dynamic> parameters,
    required this.executionTarget,
    required List<String> requiredCapabilities,
    required this.order,
  })  : parameters = Map.unmodifiable(parameters),
        requiredCapabilities = List.unmodifiable(requiredCapabilities);

  final String nodeId;
  final String type;
  final bool enabled;
  final bool bypass;
  final Map<String, dynamic> parameters;
  final ProcessingExecutionTarget executionTarget;
  final List<String> requiredCapabilities;
  final int order;

  ProcessingNode copyWith({int? order}) => ProcessingNode(
        nodeId: nodeId,
        type: type,
        enabled: enabled,
        bypass: bypass,
        parameters: parameters,
        executionTarget: executionTarget,
        requiredCapabilities: requiredCapabilities,
        order: order ?? this.order,
      );
}

class ProcessingGraph {
  ProcessingGraph(Iterable<ProcessingNode> nodes)
      : nodes = List.unmodifiable(_normalize(nodes));

  final List<ProcessingNode> nodes;

  static List<ProcessingNode> _normalize(Iterable<ProcessingNode> input) {
    final list = input.toList();
    final ids = <String>{};
    for (final node in list) {
      if (!ids.add(node.nodeId)) {
        throw ArgumentError('duplicate node_id: ${node.nodeId}');
      }
    }
    list.sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ];
  }

  ProcessingGraph reorder(String nodeId, int newIndex) {
    if (newIndex < 0 || newIndex >= nodes.length) {
      throw RangeError.index(newIndex, nodes);
    }
    final mutable = nodes.toList();
    final oldIndex = mutable.indexWhere((n) => n.nodeId == nodeId);
    if (oldIndex < 0) throw ArgumentError.value(nodeId, 'nodeId');
    final node = mutable.removeAt(oldIndex);
    mutable.insert(newIndex, node);

    // Reassign order before constructing the new graph so normalization keeps
    // the explicitly requested sequence instead of restoring the old order.
    return ProcessingGraph([
      for (var i = 0; i < mutable.length; i++) mutable[i].copyWith(order: i),
    ]);
  }
}
