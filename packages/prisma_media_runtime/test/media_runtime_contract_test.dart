import 'package:prisma_media_runtime/prisma_media_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('video source requires positive dimensions and duration', () {
    expect(
      () => LocalMediaSource(
        assetId: 'video-1',
        runtimeLocator: '/managed/video.mp4',
        kind: RuntimeMediaKind.video,
        mimeType: 'video/mp4',
        width: 1920,
        height: 1080,
        durationMs: 0,
      ),
      throwsArgumentError,
    );
  });

  test('capabilities are explicit per media kind and MIME type', () {
    const capabilities = MediaRuntimeCapabilities(
      imageDecode: true,
      videoDecode: true,
      loopingVideo: true,
      seek: true,
      audioTrack: true,
      hardwareAcceleration: true,
      supportedMimeTypes: {'image/jpeg', 'video/mp4'},
    );

    final image = LocalMediaSource(
      assetId: 'image-1',
      runtimeLocator: '/managed/image.jpg',
      kind: RuntimeMediaKind.image,
      mimeType: 'image/jpeg',
      width: 800,
      height: 600,
    );
    final unsupported = LocalMediaSource(
      assetId: 'image-2',
      runtimeLocator: '/managed/image.png',
      kind: RuntimeMediaKind.image,
      mimeType: 'image/png',
      width: 800,
      height: 600,
    );

    expect(capabilities.supports(image), isTrue);
    expect(capabilities.supports(unsupported), isFalse);
  });

  test('media lifecycle accepts playback loop and rejects resurrection', () {
    expect(
      MediaLifecycle.canTransition(
        MediaSessionState.opening,
        MediaSessionState.playing,
      ),
      isTrue,
    );
    expect(
      MediaLifecycle.canTransition(
        MediaSessionState.playing,
        MediaSessionState.ended,
      ),
      isTrue,
    );
    expect(
      MediaLifecycle.canTransition(
        MediaSessionState.ended,
        MediaSessionState.playing,
      ),
      isTrue,
    );
    expect(
      () => MediaLifecycle.requireTransition(
        MediaSessionState.closed,
        MediaSessionState.playing,
      ),
      throwsStateError,
    );
  });

  test('runtime locator is explicitly ephemeral and cannot be empty', () {
    expect(
      () => LocalMediaSource(
        assetId: 'image-1',
        runtimeLocator: '',
        kind: RuntimeMediaKind.image,
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
      ),
      throwsArgumentError,
    );
  });
}
