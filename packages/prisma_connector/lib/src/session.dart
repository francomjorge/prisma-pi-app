import 'dart:async';
import 'dart:math' as math;

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

/// Bounded exponential backoff for appliance-session recovery.
///
/// Attempts are zero-based: attempt 0 uses [initialDelay], attempt 1 uses
/// initialDelay * multiplier, and so on, capped by [maxDelay].
class ReconnectPolicy {
  const ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 16),
    this.multiplier = 2.0,
    this.maxAttempts = 8,
  })  : assert(multiplier >= 1.0),
        assert(maxAttempts > 0);

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;
  final int maxAttempts;

  bool allowsAttempt(int zeroBasedAttempt) => zeroBasedAttempt < maxAttempts;

  Duration delayForAttempt(int zeroBasedAttempt) {
    if (zeroBasedAttempt < 0) {
      throw ArgumentError.value(zeroBasedAttempt, 'zeroBasedAttempt');
    }
    final scaled = initialDelay.inMilliseconds *
        math.pow(multiplier, zeroBasedAttempt).toDouble();
    final millis = math.min(scaled.round(), maxDelay.inMilliseconds);
    return Duration(milliseconds: millis);
  }
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
  PrismaSessionManager(
    this.connector, {
    this.reconnectPolicy = const ReconnectPolicy(),
  });

  final PrismaConnector connector;
  final ReconnectPolicy reconnectPolicy;
  final GenerationCursor _cursor = GenerationCursor();
  final StreamController<SessionSnapshot> _snapshots =
      StreamController<SessionSnapshot>.broadcast(sync: true);

  StreamSubscription<PrismaEvent>? _eventSubscription;
  Timer? _reconnectTimer;
  DiscoveryRecord? _record;
  SessionSnapshot _snapshot = const SessionSnapshot(phase: SessionPhase.idle);
  bool _resyncInProgress = false;
  bool _closing = false;
  int _reconnectAttempt = 0;

  SessionSnapshot get snapshot => _snapshot;
  Stream<SessionSnapshot> get snapshots => _snapshots.stream;
  int get reconnectAttempt => _reconnectAttempt;

  Future<void> open(DiscoveryRecord record) async {
    _closing = false;
    _record = record;
    _cancelReconnect();
    _reconnectAttempt = 0;
    _publish(const SessionSnapshot(phase: SessionPhase.connecting));

    try {
      await _establish(record);
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

  /// Immediately retries the current appliance session, bypassing the current
  /// backoff delay. Intended for explicit user retry and deterministic tests.
  Future<void> reconnectNow() async {
    if (_closing || _record == null || _snapshot.phase == SessionPhase.closed) {
      return;
    }
    _cancelReconnect();
    await _performReconnect();
  }

  Future<void> close() async {
    _closing = true;
    _cancelReconnect();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await connector.disconnect();
    } finally {
      _record = null;
      _publish(_snapshot.copyWith(phase: SessionPhase.closed));
    }
  }

  Future<void> dispose() async {
    await close();
    await _snapshots.close();
  }

  Future<void> _establish(DiscoveryRecord record) async {
    final device = await connector.connect(record);
    _publish(_snapshot.copyWith(
      phase: SessionPhase.authenticating,
      device: device,
    ));
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

    _reconnectAttempt = 0;
    _publish(SessionSnapshot(
      phase: SessionPhase.ready,
      device: device,
      capabilities: capabilities,
      state: state,
      mediaEndpoints: List.unmodifiable(mediaEndpoints),
    ));
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
    if (_closing) return;
    _publish(_snapshot.copyWith(phase: SessionPhase.stale, lastError: error));
    _scheduleReconnect(error);
  }

  void _onEventDone() {
    if (_closing || _snapshot.phase == SessionPhase.closed) return;
    final error = StateError('Appliance event stream closed');
    _publish(_snapshot.copyWith(phase: SessionPhase.stale, lastError: error));
    _scheduleReconnect(error);
  }

  Future<void> _resync(SessionPhase transientPhase) async {
    if (_resyncInProgress || _snapshot.phase == SessionPhase.closed || _closing) {
      return;
    }
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
      _scheduleReconnect(error);
    } finally {
      _resyncInProgress = false;
    }
  }

  void _scheduleReconnect(Object error) {
    if (_closing || _record == null || _snapshot.phase == SessionPhase.closed) {
      return;
    }
    if (_reconnectTimer != null) return;

    if (!reconnectPolicy.allowsAttempt(_reconnectAttempt)) {
      _publish(_snapshot.copyWith(
        phase: SessionPhase.failed,
        lastError: error,
      ));
      return;
    }

    final delay = reconnectPolicy.delayForAttempt(_reconnectAttempt);
    _reconnectAttempt += 1;
    _publish(_snapshot.copyWith(
      phase: SessionPhase.reconnecting,
      lastError: error,
    ));

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_performReconnect());
    });
  }

  Future<void> _performReconnect() async {
    final record = _record;
    if (_closing || record == null || _snapshot.phase == SessionPhase.closed) {
      return;
    }

    _publish(_snapshot.copyWith(phase: SessionPhase.reconnecting));
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await connector.disconnect();
    } catch (_) {
      // Reconnect must continue even if cleanup of the failed transport fails.
    }

    if (_closing) return;

    try {
      await _establish(record);
    } catch (error) {
      _publish(_snapshot.copyWith(
        phase: SessionPhase.stale,
        lastError: error,
      ));
      _scheduleReconnect(error);
    }
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _publish(SessionSnapshot next) {
    _snapshot = next;
    if (!_snapshots.isClosed) _snapshots.add(next);
  }
}
