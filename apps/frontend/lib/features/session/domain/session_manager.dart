import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

import 'session_repositories.dart';

enum SessionStatus { restoring, signedIn, signedOut }

/// The login session of this device: holds the tokens, renews them one refresh at a time and ends
/// the session.
///
/// The refresh token rotates on every use and the API treats a reused one as theft, so two
/// refreshes must never run at once: every request that gets a 401 while a refresh is in flight
/// waits for that same refresh, and a 401 for a token that was already replaced just retries.
class SessionManager {
  SessionManager(this._store, this._api);

  final TokenStore _store;
  final AuthApi _api;
  final _changes = StreamController<SessionStatus>.broadcast(sync: true);

  IssuedSession? _session;
  SessionStatus _status = SessionStatus.restoring;
  Future<void>? _restoring;
  Future<bool>? _renewal;

  /// Bumped whenever the session is replaced or ended, so a refresh that finishes afterwards
  /// doesn't bring the old session back.
  int _epoch = 0;

  SessionStatus get status => _status;
  Stream<SessionStatus> get changes => _changes.stream;
  String? get accessToken => _session?.accessToken;

  /// The access token a request should carry now: waits for the saved tokens to load and for a
  /// renewal in flight, so new requests don't go out with a token that is being replaced.
  Future<String?> currentAccessToken() async {
    await restore();
    final pending = _renewal;
    if (pending != null) {
      try {
        await pending;
      } on Exception {
        // The request goes out with what there is and reports its own error.
      }
    }
    return _session?.accessToken;
  }

  /// Loads the tokens saved by a previous launch. Safe to call more than once.
  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    final saved = await _store.read();
    if (_status != SessionStatus.restoring) return; // signed in or out meanwhile
    _session = saved;
    _setStatus(saved == null ? SessionStatus.signedOut : SessionStatus.signedIn);
  }

  Future<void> signInWithGoogle(String idToken, {String? device}) async {
    final issued = await _api.signInWithGoogle(idToken, device: device);
    _epoch++;
    _session = issued;
    await _store.write(issued);
    _setStatus(SessionStatus.signedIn);
  }

  /// See [AccessTokenSource.renewAfterUnauthorized] in `core/red/cliente_api.dart`.
  Future<bool> renewAfterUnauthorized(String rejectedToken) {
    final current = _session;
    if (current == null) return Future.value(false);
    if (current.accessToken != rejectedToken) return Future.value(true); // already renewed
    return _renewal ??= _renew(current).whenComplete(() => _renewal = null);
  }

  Future<bool> _renew(IssuedSession current) async {
    final epoch = _epoch;
    try {
      final next = await _api.refresh(current.refreshToken);
      if (epoch != _epoch) return _session != null;
      _session = next;
      await _store.write(next);
      return true;
    } on SessionRejected {
      if (epoch != _epoch) return _session != null;
      _epoch++;
      _session = null;
      await _store.clear();
      _setStatus(SessionStatus.signedOut);
      return false;
    }
  }

  /// Revokes this device's session in the API and forgets the tokens. The local tokens are cleared
  /// even when the API can't be reached.
  Future<void> signOut() async {
    // Log out with the newest refresh token: the API only revokes the current one.
    final pending = _renewal;
    if (pending != null) {
      try {
        await pending;
      } on Exception {
        // The renewal failing doesn't stop the logout.
      }
    }
    final ending = _session;
    _epoch++;
    _session = null; // no renewal can start from here on
    try {
      if (ending != null) await _api.logout(ending.refreshToken);
    } on Exception {
      // Without signal the session stays valid in the API until it expires; locally it's over.
    } finally {
      await _store.clear();
      _setStatus(SessionStatus.signedOut);
    }
  }

  void _setStatus(SessionStatus status) {
    if (_status == status) return;
    _status = status;
    _changes.add(status);
  }

  void dispose() => _changes.close();
}
