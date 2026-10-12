enum RuntimeMediaKind { image, video }

enum MediaSessionState {
  opening,
  ready,
  playing,
  paused,
  ended,
  failed,
  closed,
}

enum MediaRuntimeEventType {
  stateChanged,
  positionChanged,
  durationChanged,
  loopBoundary,
  fault,
}

/// Ephemeral runtime locator for a validated managed asset.
///
/// `runtimeLocator` may be an absolute app-private path or another
/// platform-owned handle. It must never be serialized into a portable project.
class LocalMediaSource {
  LocalMediaSource({
    required this.assetId,
    required this.runtimeLocator,
    required this.kind,
    required this.mimeType,
    required this.width,
    required this.height,
    this.durationMs,
    this.hasAudio = false,
  }) {
    if (assetId.trim().isEmpty) throw ArgumentError.value(assetId, 'assetId');
    if (runtimeLocator.trim().isEmpty) {
      throw ArgumentError.value(runtimeLocator, 'runtimeLocator');
    }
    if (mimeType.trim().isEmpty) throw ArgumentError.value(mimeType, 'mimeType');
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Media dimensions must be positive');
    }
    if (kind == RuntimeMediaKind.video && (durationMs ?? 0) <= 0) {
      throw ArgumentError('Video source requires a positive duration');
    }
  }

  final String assetId;
  final String runtimeLocator;
  final RuntimeMediaKind kind;
  final String mimeType;
  final int width;
  final int height;
  final int? durationMs;
  final bool hasAudio;
}

class MediaOpenOptions {
  const MediaOpenOptions({
    this.loop = true,
    this.autoplay = true,
    this.startPositionMs = 0,
    this.muted = true,
  }) : assert(startPositionMs >= 0);

  final bool loop;
  final bool autoplay;
  final int startPositionMs;
  final bool muted;
}

class MediaRuntimeCapabilities {
  const MediaRuntimeCapabilities({
    required this.imageDecode,
    required this.videoDecode,
    required this.loopingVideo,
    required this.seek,
    required this.audioTrack,
    required this.hardwareAcceleration,
    this.supportedMimeTypes = const {},
  });

  final bool imageDecode;
  final bool videoDecode;
  final bool loopingVideo;
  final bool seek;
  final bool audioTrack;
  final bool hardwareAcceleration;
  final Set<String> supportedMimeTypes;

  bool supports(LocalMediaSource source) {
    if (supportedMimeTypes.isNotEmpty &&
        !supportedMimeTypes.contains(source.mimeType)) {
      return false;
    }
    return switch (source.kind) {
      RuntimeMediaKind.image => imageDecode,
      RuntimeMediaKind.video => videoDecode,
    };
  }
}

class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.sessionId,
    required this.sourceAssetId,
    required this.state,
    required this.positionMs,
    required this.loop,
    required this.muted,
    this.durationMs,
    this.decodeBackend,
    this.faultCode,
  });

  final String sessionId;
  final String sourceAssetId;
  final MediaSessionState state;
  final int positionMs;
  final int? durationMs;
  final bool loop;
  final bool muted;
  final String? decodeBackend;
  final String? faultCode;
}

class MediaRuntimeEvent {
  const MediaRuntimeEvent({
    required this.sessionId,
    required this.type,
    required this.timestampMs,
    required this.payload,
  });

  final String sessionId;
  final MediaRuntimeEventType type;
  final int timestampMs;
  final Map<String, dynamic> payload;
}

abstract interface class LocalMediaRuntime {
  MediaRuntimeCapabilities get capabilities;

  Future<MediaSessionSnapshot> open(
    LocalMediaSource source, {
    MediaOpenOptions options = const MediaOpenOptions(),
  });

  Future<MediaSessionSnapshot> play(String sessionId);
  Future<MediaSessionSnapshot> pause(String sessionId);
  Future<MediaSessionSnapshot> seek(String sessionId, int positionMs);
  Future<MediaSessionSnapshot> setLoop(String sessionId, bool enabled);
  Future<MediaSessionSnapshot> setMuted(String sessionId, bool muted);
  Future<MediaSessionSnapshot> snapshot(String sessionId);
  Future<void> close(String sessionId);
  Stream<MediaRuntimeEvent> events(String sessionId);
}
