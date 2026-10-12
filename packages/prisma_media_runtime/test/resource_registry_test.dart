import 'package:prisma_media_runtime/prisma_media_runtime.dart';
import 'package:test/test.dart';

void main() {
  const budget = MediaResourceBudget(
    maxDecodedImageBytes: 1000,
    maxThumbnailCacheBytes: 500,
    maxConcurrentVideoDecoders: 1,
    maxActiveRenderSurfaces: 2,
  );

  test('resource leases account and release idempotently', () async {
    final registry = MediaResourceRegistry(budget: budget);
    var nativeReleases = 0;

    final image = registry.acquire(
      resourceId: 'image-a',
      kind: MediaResourceKind.decodedImage,
      bytes: 400,
      releaseNative: () => nativeReleases++,
    );
    registry.acquire(
      resourceId: 'video-a',
      kind: MediaResourceKind.videoDecoder,
      releaseNative: () => nativeReleases++,
    );
    registry.acquire(
      resourceId: 'surface-a',
      kind: MediaResourceKind.renderSurface,
      releaseNative: () => nativeReleases++,
    );

    expect(registry.snapshot.decodedImageBytes, 400);
    expect(registry.snapshot.activeVideoDecoders, 1);
    expect(registry.snapshot.activeRenderSurfaces, 1);
    expect(registry.pressure, ResourcePressureLevel.normal);

    await image.release();
    await image.release();

    expect(nativeReleases, 1);
    expect(registry.snapshot.decodedImageBytes, 0);
    expect(registry.activeLeases, hasLength(2));
  });

  test('budget breach escalates pressure and selective release recovers', () async {
    final registry = MediaResourceRegistry(budget: budget);

    registry.acquire(
      resourceId: 'thumb-a',
      kind: MediaResourceKind.thumbnail,
      bytes: 650,
      releaseNative: () {},
    );
    registry.acquire(
      resourceId: 'video-a',
      kind: MediaResourceKind.videoDecoder,
      releaseNative: () {},
    );
    registry.acquire(
      resourceId: 'video-b',
      kind: MediaResourceKind.videoDecoder,
      releaseNative: () {},
    );

    expect(registry.pressure, ResourcePressureLevel.critical);
    expect(
      registry.snapshot.violations(budget),
      containsAll(['THUMBNAIL_CACHE_BYTES', 'VIDEO_DECODERS']),
    );

    await registry.releaseWhere(
      (lease) => lease.resourceId == 'video-b' ||
          lease.kind == MediaResourceKind.thumbnail,
    );

    expect(registry.pressure, ResourcePressureLevel.normal);
    expect(registry.snapshot.activeVideoDecoders, 1);
    expect(registry.snapshot.thumbnailCacheBytes, 0);
  });

  test('duplicate ownership is rejected', () {
    final registry = MediaResourceRegistry(budget: budget);
    registry.acquire(
      resourceId: 'surface-a',
      kind: MediaResourceKind.renderSurface,
      releaseNative: () {},
    );

    expect(
      () => registry.acquire(
        resourceId: 'surface-a',
        kind: MediaResourceKind.renderSurface,
        releaseNative: () {},
      ),
      throwsStateError,
    );
  });
}
