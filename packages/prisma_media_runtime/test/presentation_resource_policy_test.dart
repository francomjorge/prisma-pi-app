import 'package:prisma_media_runtime/prisma_media_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('MediaPresentationPolicy', () {
    test('contain preserves aspect ratio and stays within viewport', () {
      const policy = MediaPresentationPolicy(
        fit: MediaFitMode.contain,
        intent: MediaDecodeIntent.preview,
      );

      final result = policy.resolveDecodeSize(
        source: const PixelSize(4000, 3000),
        viewport: const PixelSize(1080, 1920),
      );

      expect(result, const PixelSize(1080, 810));
    });

    test('cover preserves aspect ratio and covers portrait viewport', () {
      const policy = MediaPresentationPolicy(
        fit: MediaFitMode.cover,
        intent: MediaDecodeIntent.preview,
      );

      final result = policy.resolveDecodeSize(
        source: const PixelSize(4000, 3000),
        viewport: const PixelSize(1080, 1920),
      );

      expect(result, const PixelSize(2560, 1920));
    });

    test('upscale is disabled unless explicitly requested', () {
      const noUpscale = MediaPresentationPolicy(
        fit: MediaFitMode.contain,
        intent: MediaDecodeIntent.preview,
      );
      const upscale = MediaPresentationPolicy(
        fit: MediaFitMode.contain,
        intent: MediaDecodeIntent.preview,
        allowUpscale: true,
      );

      expect(
        noUpscale.resolveDecodeSize(
          source: const PixelSize(640, 360),
          viewport: const PixelSize(1920, 1080),
        ),
        const PixelSize(640, 360),
      );
      expect(
        upscale.resolveDecodeSize(
          source: const PixelSize(640, 360),
          viewport: const PixelSize(1920, 1080),
        ),
        const PixelSize(1920, 1080),
      );
    });

    test('pixel cap bounds decoded allocation while preserving ratio', () {
      const policy = MediaPresentationPolicy(
        fit: MediaFitMode.nativePixels,
        intent: MediaDecodeIntent.processingSource,
        maxDecodePixels: 1000000,
      );

      final result = policy.resolveDecodeSize(
        source: const PixelSize(4000, 3000),
        viewport: const PixelSize(4000, 3000),
      );

      expect(result.pixelCount, lessThanOrEqualTo(1000000));
      expect(result.aspectRatio, closeTo(4 / 3, 0.01));
    });
  });

  group('MediaResourceBudget', () {
    const budget = MediaResourceBudget(
      maxDecodedImageBytes: 64 * 1024 * 1024,
      maxThumbnailCacheBytes: 16 * 1024 * 1024,
      maxConcurrentVideoDecoders: 2,
      maxActiveRenderSurfaces: 3,
    );

    test('reports each exceeded resource independently', () {
      const snapshot = MediaResourceSnapshot(
        decodedImageBytes: 70 * 1024 * 1024,
        thumbnailCacheBytes: 20 * 1024 * 1024,
        activeVideoDecoders: 3,
        activeRenderSurfaces: 4,
      );

      expect(
        snapshot.violations(budget),
        containsAll([
          'DECODED_IMAGE_BYTES',
          'THUMBNAIL_CACHE_BYTES',
          'VIDEO_DECODERS',
          'RENDER_SURFACES',
        ]),
      );
    });

    test('critical pressure releases paused decoders and non-program surfaces', () {
      final policy =
          ResourceReleasePolicy.forPressure(ResourcePressureLevel.critical);

      expect(policy.evictThumbnailCache, isTrue);
      expect(policy.releaseIdleImages, isTrue);
      expect(policy.releasePausedVideoDecoders, isTrue);
      expect(policy.releaseNonProgramSurfaces, isTrue);
    });

    test('normal pressure does not force eviction', () {
      final policy = ResourceReleasePolicy.forPressure(ResourcePressureLevel.normal);

      expect(policy.evictThumbnailCache, isFalse);
      expect(policy.releaseIdleImages, isFalse);
      expect(policy.releasePausedVideoDecoders, isFalse);
      expect(policy.releaseNonProgramSurfaces, isFalse);
    });
  });
}
