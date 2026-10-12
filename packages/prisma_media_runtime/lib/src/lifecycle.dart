import 'contracts.dart';

class MediaLifecycle {
  const MediaLifecycle._();

  static bool canTransition(MediaSessionState from, MediaSessionState to) {
    if (from == to) return true;
    return switch (from) {
      MediaSessionState.opening => {
          MediaSessionState.ready,
          MediaSessionState.playing,
          MediaSessionState.failed,
          MediaSessionState.closed,
        }.contains(to),
      MediaSessionState.ready => {
          MediaSessionState.playing,
          MediaSessionState.paused,
          MediaSessionState.failed,
          MediaSessionState.closed,
        }.contains(to),
      MediaSessionState.playing => {
          MediaSessionState.paused,
          MediaSessionState.ended,
          MediaSessionState.failed,
          MediaSessionState.closed,
        }.contains(to),
      MediaSessionState.paused => {
          MediaSessionState.playing,
          MediaSessionState.ended,
          MediaSessionState.failed,
          MediaSessionState.closed,
        }.contains(to),
      MediaSessionState.ended => {
          MediaSessionState.playing,
          MediaSessionState.failed,
          MediaSessionState.closed,
        }.contains(to),
      MediaSessionState.failed => to == MediaSessionState.closed,
      MediaSessionState.closed => false,
    };
  }

  static void requireTransition(MediaSessionState from, MediaSessionState to) {
    if (!canTransition(from, to)) {
      throw StateError(
        'Invalid media session transition: ${from.name} -> ${to.name}',
      );
    }
  }
}
