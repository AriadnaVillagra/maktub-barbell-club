import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/cliente_api.dart';
import '../data/http_auth_api.dart';
import '../data/shared_preferences_token_store.dart';
import '../domain/session_manager.dart';
import '../domain/session_repositories.dart';
import 'google_button/google_button.dart';
import 'sign_in_controller.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SharedPreferencesTokenStore());

final authApiProvider = Provider<AuthApi>(
  (ref) => HttpAuthApi(ClienteApi(base: Uri.parse(urlApi), cliente: ref.watch(httpClientProvider))),
);

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(ref.watch(tokenStoreProvider), ref.watch(authApiProvider));
  ref.onDispose(manager.dispose);
  return manager;
});

/// Whether this device is signed in. Starts as [SessionStatus.restoring] while the saved tokens load;
/// goes to [SessionStatus.signedOut] when the user logs out or a renewal is rejected.
final sessionControllerProvider = NotifierProvider<SessionController, SessionStatus>(SessionController.new);

class SessionController extends Notifier<SessionStatus> {
  SessionManager get _manager => ref.read(sessionManagerProvider);

  @override
  SessionStatus build() {
    final manager = ref.watch(sessionManagerProvider);
    final subscription = manager.changes.listen((status) => state = status);
    ref.onDispose(subscription.cancel);
    unawaited(manager.restore());
    return manager.status;
  }

  Future<void> signInWithGoogle(String idToken, {String? device}) =>
      _manager.signInWithGoogle(idToken, device: device);

  Future<void> signOut() => _manager.signOut();
}

/// Draws the sign-in button. Tests replace it with a plain button that hands over a fake ID token.
final googleButtonProvider = Provider<GoogleButtonBuilder>((ref) => googleButton);

final signInControllerProvider =
    NotifierProvider.autoDispose<SignInController, SignInState>(SignInController.new);

/// Adapts the session to what [ClienteApi] needs to authenticate its requests.
class SessionTokenSource implements AccessTokenSource {
  const SessionTokenSource(this._manager);

  final SessionManager _manager;

  @override
  Future<String?> accessToken() => _manager.currentAccessToken();

  @override
  Future<bool> renewAfterUnauthorized(String rejectedToken) => _manager.renewAfterUnauthorized(rejectedToken);
}
