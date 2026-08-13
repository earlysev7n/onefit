import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../app_clock.dart';

/// Single source of truth for whether the app should behave as offline.
///
/// [isOffline] is `true` when either the device genuinely has no connection
/// (`connectivity_plus`) **or** the Developer-Mode [forceOfflineEnabled] switch
/// is on — the latter lets the whole offline experience be tested without
/// touching Wi-Fi. The dev switch additionally drives Firestore's own
/// `disableNetwork()`/`enableNetwork()` so it is a *real* offline test (cached
/// reads + queued writes), not merely a UI gate. Real connectivity changes are
/// left to the Firestore SDK, which detects them and queues writes on its own.
///
/// **Reconnect → adaptive system.** On every offline→online transition (after
/// any queued writes have been flushed) this fires the callbacks registered via
/// [addReconnectListener], so screens can refresh their providers — e.g.
/// `ProfileProvider.recomputeGoal(uid)` — and the daily weekly-adaptive goal is
/// recomputed from the now-synced logs. It never re-runs the weekly
/// `AdaptationEngine`; that stays guarded by `UserProfile.lastAdaptationWeekId`.
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider() {
    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    forceOfflineEnabled.addListener(_onDevChanged);
    developerModeEnabled.addListener(_onDevChanged);
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final List<Future<void> Function()> _reconnectListeners =
      <Future<void> Function()>[];

  bool _rawOffline = false;
  bool _effectiveOffline = false;
  // Tracks whether *we* put Firestore into offline mode (dev toggle), so we only
  // re-enable a network we ourselves disabled — real offline is the SDK's job.
  bool _firestoreDisabledByUs = false;

  /// Whether the app should present as offline right now.
  bool get isOffline => _effectiveOffline;

  bool get _devForced =>
      developerModeEnabled.value && forceOfflineEnabled.value;

  Future<void> _init() async {
    try {
      final r = await _connectivity.checkConnectivity();
      _rawOffline = _isNone(r);
    } catch (_) {
      _rawOffline = false; // fail open: assume online when we can't tell
    }
    await _recompute();
  }

  void _onConnectivityChanged(List<ConnectivityResult> r) {
    _rawOffline = _isNone(r);
    _recompute();
  }

  void _onDevChanged() {
    _recompute();
  }

  static bool _isNone(List<ConnectivityResult> results) =>
      results.isEmpty ||
      results.every((r) => r == ConnectivityResult.none);

  /// Registers [cb] to run once on each offline→online transition, after the
  /// Firestore write queue has been flushed. Safe to add/remove from a
  /// widget's initState/dispose.
  void addReconnectListener(Future<void> Function() cb) {
    if (!_reconnectListeners.contains(cb)) _reconnectListeners.add(cb);
  }

  void removeReconnectListener(Future<void> Function() cb) {
    _reconnectListeners.remove(cb);
  }

  Future<void> _recompute() async {
    // Drive Firestore's own network state ONLY for the dev-forced case; the SDK
    // auto-detects genuine connectivity loss.
    final devForced = _devForced;
    if (devForced && !_firestoreDisabledByUs) {
      _firestoreDisabledByUs = true;
      try {
        await FirebaseFirestore.instance.disableNetwork();
      } catch (_) {}
    } else if (!devForced && _firestoreDisabledByUs) {
      _firestoreDisabledByUs = false;
      try {
        // Flush the queue and re-establish listeners BEFORE we refresh
        // providers, so the reconnect refresh reads synced data.
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
    }

    final next = _rawOffline || devForced;
    if (next == _effectiveOffline) return;

    final wasOffline = _effectiveOffline;
    _effectiveOffline = next;
    notifyListeners();

    if (wasOffline && !next) {
      await _fireReconnect();
    }
  }

  Future<void> _fireReconnect() async {
    for (final cb in List<Future<void> Function()>.of(_reconnectListeners)) {
      try {
        await cb();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    forceOfflineEnabled.removeListener(_onDevChanged);
    developerModeEnabled.removeListener(_onDevChanged);
    _reconnectListeners.clear();
    super.dispose();
  }
}
