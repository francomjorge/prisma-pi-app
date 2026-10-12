import 'dart:math' as math;

enum MediaFitMode {
  contain,
  cover,
  fill,
  fitWidth,
  fitHeight,
  nativePixels,
  scaleDown,
}

enum MediaDecodeIntent {
  thumbnail,
  preview,
  processingSource,
  programOutput,
}

enum ResourcePressureLevel {
  normal,
  elevated,
  critical,
}

class PixelSize {
  const PixelSize(this.width, this.height)
      : assert(width > 0),
        assert(height > 0);

  final int width;
  final int height;

  int get pixelCount => width * height;
  double get aspectRatio => width / height;

  @override
  bool operator ==(Object other) =>
      other is PixelSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// Platform-neutral presentation and decode policy.
///
/// This contract intentionally separates visual fit from the underlying native
/// decoder. Android/iOS adapters may use different APIs while honoring the same
/// geometry and resource limits.
class MediaPresentationPolicy {
  const MediaPresentationPolicy({
    required this.fit,
    required this.intent,
    this.alignmentX = 0,
    this.alignmentY = 0,
    this.allowUpscale = false,
    this.maxDecodePixels,
  })  : assert(alignmentX >= -1 && alignmentX <= 1),
        assert(alignmentY >= -1 && alignmentY <= 1),
        assert(maxDecodePixels == null || maxDecodePixels > 0);

  final MediaFitMode fit;
  final MediaDecodeIntent intent;

  /// Normalized alignment in the range -1..1, matching the semantics used by
  /// common UI frameworks: -1 is leading/top, 0 centered, 1 trailing/bottom.
  final double alignmentX;
  final double alignmentY;

  /// Decoders should normally avoid upscaling. Upscaling belongs in the render
  /// path unless a backend has a measured reason to decode larger.
  final bool allowUpscale;

  /// Optional hard pixel-count ceiling for the decoded image/frame target.
  /// A platform resource policy supplies the actual value at runtime.
  final int? maxDecodePixels;

  PixelSize resolveDecodeSize({
    required PixelSize source,
    required PixelSize viewport,
  }) {
    double scale;

    switch (fit) {
      case MediaFitMode.contain:
        scale = math.min(
          viewport.width / source.width,
          viewport.height / source.height,
        );
        break;
      case MediaFitMode.cover:
        scale = math.max(
          viewport.width / source.width,
          viewport.height / source.height,
        );
        break;
      case MediaFitMode.fill:
        final resolved = PixelSize(viewport.width, viewport.height);
        return _capPixels(resolved);
      case MediaFitMode.fitWidth:
        scale = viewport.width / source.width;
        break;
      case MediaFitMode.fitHeight:
        scale = viewport.height / source.height;
        break;
      case MediaFitMode.nativePixels:
        scale = 1;
        break;
      case MediaFitMode.scaleDown:
        scale = math.min(
          1,
          math.min(
            viewport.width / source.width,
            viewport.height / source.height,
          ),
        );
        break;
    }

    if (!allowUpscale) scale = math.min(scale, 1);

    final resolved = PixelSize(
      math.max(1, (source.width * scale).round()),
      math.max(1, (source.height * scale).round()),
    );
    return _capPixels(resolved);
  }

  PixelSize _capPixels(PixelSize size) {
    final cap = maxDecodePixels;
    if (cap == null || size.pixelCount <= cap) return size;

    final factor = math.sqrt(cap / size.pixelCount);
    return PixelSize(
      math.max(1, (size.width * factor).floor()),
      math.max(1, (size.height * factor).floor()),
    );
  }
}

/// Runtime memory/decoder limits supplied by the platform after device-class
/// assessment. No universal product constants are baked into this contract.
class MediaResourceBudget {
  const MediaResourceBudget({
    required this.maxDecodedImageBytes,
    required this.maxThumbnailCacheBytes,
    required this.maxConcurrentVideoDecoders,
    required this.maxActiveRenderSurfaces,
  })  : assert(maxDecodedImageBytes > 0),
        assert(maxThumbnailCacheBytes >= 0),
        assert(maxConcurrentVideoDecoders > 0),
        assert(maxActiveRenderSurfaces > 0);

  final int maxDecodedImageBytes;
  final int maxThumbnailCacheBytes;
  final int maxConcurrentVideoDecoders;
  final int maxActiveRenderSurfaces;
}

class MediaResourceSnapshot {
  const MediaResourceSnapshot({
    required this.decodedImageBytes,
    required this.thumbnailCacheBytes,
    required this.activeVideoDecoders,
    required this.activeRenderSurfaces,
  });

  final int decodedImageBytes;
  final int thumbnailCacheBytes;
  final int activeVideoDecoders;
  final int activeRenderSurfaces;

  List<String> violations(MediaResourceBudget budget) {
    final result = <String>[];
    if (decodedImageBytes > budget.maxDecodedImageBytes) {
      result.add('DECODED_IMAGE_BYTES');
    }
    if (thumbnailCacheBytes > budget.maxThumbnailCacheBytes) {
      result.add('THUMBNAIL_CACHE_BYTES');
    }
    if (activeVideoDecoders > budget.maxConcurrentVideoDecoders) {
      result.add('VIDEO_DECODERS');
    }
    if (activeRenderSurfaces > budget.maxActiveRenderSurfaces) {
      result.add('RENDER_SURFACES');
    }
    return List.unmodifiable(result);
  }
}

class ResourceReleasePolicy {
  const ResourceReleasePolicy({
    required this.evictThumbnailCache,
    required this.releaseIdleImages,
    required this.releasePausedVideoDecoders,
    required this.releaseNonProgramSurfaces,
  });

  final bool evictThumbnailCache;
  final bool releaseIdleImages;
  final bool releasePausedVideoDecoders;
  final bool releaseNonProgramSurfaces;

  factory ResourceReleasePolicy.forPressure(ResourcePressureLevel level) {
    return switch (level) {
      ResourcePressureLevel.normal => const ResourceReleasePolicy(
          evictThumbnailCache: false,
          releaseIdleImages: false,
          releasePausedVideoDecoders: false,
          releaseNonProgramSurfaces: false,
        ),
      ResourcePressureLevel.elevated => const ResourceReleasePolicy(
          evictThumbnailCache: true,
          releaseIdleImages: true,
          releasePausedVideoDecoders: false,
          releaseNonProgramSurfaces: true,
        ),
      ResourcePressureLevel.critical => const ResourceReleasePolicy(
          evictThumbnailCache: true,
          releaseIdleImages: true,
          releasePausedVideoDecoders: true,
          releaseNonProgramSurfaces: true,
        ),
    };
  }
}

/// Native resources such as decoders, textures and render surfaces must have an
/// explicit owner and an idempotent release path.
abstract interface class ReleasableMediaResource {
  bool get released;
  Future<void> release();
}
