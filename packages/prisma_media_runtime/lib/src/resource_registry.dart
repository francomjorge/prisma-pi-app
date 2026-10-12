import 'dart:async';

import 'presentation.dart';

enum MediaResourceKind {
  decodedImage,
  thumbnail,
  videoDecoder,
  renderSurface,
  gpuTexture,
}

class MediaResourceLease implements ReleasableMediaResource {
  MediaResourceLease._({
    required this.resourceId,
    required this.kind,
    required this.bytes,
    required FutureOr<void> Function() releaseNative,
    required void Function(MediaResourceLease lease) onReleased,
  })  : _releaseNative = releaseNative,
        _onReleased = onReleased;

  final String resourceId;
  final MediaResourceKind kind;
  final int bytes;
  final FutureOr<void> Function() _releaseNative;
  final void Function(MediaResourceLease lease) _onReleased;

  bool _released = false;

  @override
  bool get released => _released;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _releaseNative();
    } finally {
      _onReleased(this);
    }
  }
}

/// Platform-neutral ownership registry for expensive media resources.
///
/// Native adapters remain responsible for the actual Bitmap/Surface/decoder
/// objects. The registry gives application/runtime code deterministic ownership,
/// accounting and idempotent release semantics without importing platform APIs.
class MediaResourceRegistry {
  MediaResourceRegistry({required this.budget});

  final MediaResourceBudget budget;
  final Map<String, MediaResourceLease> _leases = {};

  MediaResourceLease acquire({
    required String resourceId,
    required MediaResourceKind kind,
    int bytes = 0,
    required FutureOr<void> Function() releaseNative,
  }) {
    if (resourceId.trim().isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId');
    }
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    if (_leases.containsKey(resourceId)) {
      throw StateError('Resource already acquired: $resourceId');
    }

    late final MediaResourceLease lease;
    lease = MediaResourceLease._(
      resourceId: resourceId,
      kind: kind,
      bytes: bytes,
      releaseNative: releaseNative,
      onReleased: (_) => _leases.remove(resourceId),
    );
    _leases[resourceId] = lease;
    return lease;
  }

  MediaResourceSnapshot get snapshot {
    var decodedImageBytes = 0;
    var thumbnailCacheBytes = 0;
    var videoDecoders = 0;
    var renderSurfaces = 0;

    for (final lease in _leases.values) {
      switch (lease.kind) {
        case MediaResourceKind.decodedImage:
          decodedImageBytes += lease.bytes;
          break;
        case MediaResourceKind.thumbnail:
          thumbnailCacheBytes += lease.bytes;
          break;
        case MediaResourceKind.videoDecoder:
          videoDecoders += 1;
          break;
        case MediaResourceKind.renderSurface:
        case MediaResourceKind.gpuTexture:
          renderSurfaces += 1;
          break;
      }
    }

    return MediaResourceSnapshot(
      decodedImageBytes: decodedImageBytes,
      thumbnailCacheBytes: thumbnailCacheBytes,
      activeVideoDecoders: videoDecoders,
      activeRenderSurfaces: renderSurfaces,
    );
  }

  ResourcePressureLevel get pressure {
    final violations = snapshot.violations(budget);
    if (violations.isEmpty) return ResourcePressureLevel.normal;

    final severe = snapshot.decodedImageBytes > budget.maxDecodedImageBytes * 1.25 ||
        snapshot.thumbnailCacheBytes > budget.maxThumbnailCacheBytes * 1.25 ||
        snapshot.activeVideoDecoders > budget.maxConcurrentVideoDecoders ||
        snapshot.activeRenderSurfaces > budget.maxActiveRenderSurfaces;
    return severe ? ResourcePressureLevel.critical : ResourcePressureLevel.elevated;
  }

  Iterable<MediaResourceLease> get activeLeases =>
      List<MediaResourceLease>.unmodifiable(_leases.values);

  Future<void> releaseWhere(bool Function(MediaResourceLease lease) predicate) async {
    final targets = _leases.values.where(predicate).toList(growable: false);
    for (final lease in targets) {
      await lease.release();
    }
  }

  Future<void> releaseAll() => releaseWhere((_) => true);
}
