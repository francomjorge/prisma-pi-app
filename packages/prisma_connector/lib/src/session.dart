import 'dart:async';

import 'package:prisma_domain/prisma_domain.dart';

import 'connector.dart';

enum SessionPhase {
  idle,
  connecting,
  authenticating,
  synchronizing,
  ready,
  stale,
  reconnecting,
  closed,
  failed,
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.phase,
    this.device,
    this.capabilities,
    this.state,
    this.mediaEndpoints = const [],
    this.lastError,
  });

  final SessionPhase phase;
  final DeviceDescriptor? device;
  final DeviceCapabilities? capabilities;
  final PrismaState? state;
  final List<MediaEndpoint> mediaEndpoints;
  final Object? lastError;

  bool get canIssueCommands => phase == SessionPhase.ready && state != null;

  SessionSnapshot copyWith({
    SessionPhase? phase,
    DeviceDescriptor? device,
    DeviceCapabilities? capabilities,
    PrismaState? state,
    List<MediaEndpoint>? mediaEndpoints,
    Object? lastError,
    bool clearError = false,
  }) {
    return SessionSnapshot(
      phase: phase ?? this.phase,
      device: device ?? this.device,
      capabilities: capabilities ?? this.capabilities,
      state: state ?? this.state,
      mediaEndpoints: mediaEndpoints ?? this.mediaEndpoints,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Owns one remote appliance session. It does not own synthesizer state: the
/// appliance remains authoritative and this class keeps a synchronized mirror.
class PrismaSessionManager {
  PrismaSessionManager(this.connector);

  final PrismaConnector connector;
  final GenerationCursor _cursor = GenerationCursor();
  final StreamController<SessionSnapshot> _snapshots =
      StreamController<SessionSnapshot>.broadcast(sync: true);

  StreamSubscription<PrismaEvent>? _eventSubscription;
  SessionSnapshot _snapshot = const SessionSnapshot(phase: SessionPhase.idle);
  bool _resyncInProgress = false;

  SessionSnapshot get snapshot => _snapshot;
  Stream<SessionSnapshot> get snapshots => _snapshots.stream;

  Future<void> open(DiscoveryRecord record) async {
    _publish(const SessionSnapshot(phase: SessionPhase.connecting));
    try {
      final device = await connector.connect(record);
      _publish(_snapshot.copyWith(phase: SessionPhase.authenticating, device: device));
      await connector.authenticate();

      _publish(_snapshot.copyWith(phase: SessionPhase.synchronizing));
      final capabilities = await connector.getCapabilities();
      final state = await connector.getState();
      final mediaEndpoints = await connector.getMediaEndpoints();
      _cursor.resetToSnapshot(state.generation);

      await _eventSubscription?.cancel();
      _eventSubscription = connector.events().listen(
        _onEvent,
        onError: _onEventError,
        onDone: _onEventDone,
      );

      _publish(SessionSnapshot(
        phase: SessionPhase.ready,
        device: device,
        capabilities: capabilities,
        state: state,
        mediaEndpoints: List.unmodifiable(mediaEndpoints),
      ));
    } catch (error) {
      _publish(_snapshot.copyWith(phase: SessionPhase.failed, lastError: error));
      rethrow;
    }
  }

  Future<Map<String, dynamic>> issue(PrismaCommand command) async {
    if (!_snapshot.canIssueCommands) {
      throw StateError('Session is not ready for commands: ${_snapshot.phase}');
    }
    return connector.sendCommand(command);
  }

  Future<void> refresh() => _resync(SessionPhase.synchronizing);

  Future<void> close() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await connector.disconnect();
    _publish(_snapshot.copyWith(phase: SessionPhase.closed));
  }

  Future<void> dispose() async {
    await close();
    await _snapshots.close();
  }

  void _onEvent(PrismaEvent event) {
    final currentDevice = _snapshot.device;
    if (currentDevice == null || event.deviceId != currentDevice.deviceId) return;

    final decision = _cursor.inspect(event.generation);
    switch (decision) {
      case GenerationDecision.staleOrDuplicate:
        return;
      case GenerationDecision.gap:
        _publish(_snapshot.copyWith(phase: SessionPhase.stale));
        unawaited(_resync(SessionPhase.synchronizing));
        return;
      case GenerationDecision.accept:
        _cursor.accept(event.generation);
        // Until typed event reducers are frozen, re-read the authoritative
        // snapshot. This is intentionally correct-before-optimized behavior.
        unawaited(_resync(SessionPhase.synchronizing));
    }
  }

  void _onEventError(Object error, StackTrace stackTrace) {
    _publish(_snapshot.copyWith(phase: SessionPhase.stale, lastError: error));
  }

  void _onEventDone() {
    if (_snapshot.phase != SessionPhase.closed) {
      _publish(_snapshot.copyWith(phase: SessionPhase.stale));
    }
  }

  Future<void> _resync(SessionPhase transientPhase) async {
    if (_resyncInProgress || _snapshot.phase == SessionPhase.closed) return;
    _resyncInProgress = true;
    _publish(_snapshot.copyWith(phase: transientPhase));
    try {
      final state = await connector.getState();
      final endpoints = await connector.getMediaEndpoints();
      _cursor.resetToSnapshot(state.generation);
      _publish(_snapshot.copyWith(
        phase: SessionPhase.ready,
        state: state,
        mediaEndpoints: List.unmodifiable(endpoints),
        clearError: true,
      ));
    } catch (error) {
      _publish(_snapshot.copyWith(phase: SessionPhase.stale, lastError: error));
    } finally {
      _resyncInProgress = false;
    }
  }

  void _publish(SessionSnapshot next) {
    _snapshot = next;
    if (!_snapshots.isClosed) _snapshots.add(next);
  }
}
