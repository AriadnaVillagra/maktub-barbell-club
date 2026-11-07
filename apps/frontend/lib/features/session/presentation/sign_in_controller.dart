import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/cliente_api.dart';
import 'providers.dart';

/// What the sign-in screen shows: whether an ID token is on its way to the API, and why the last
/// attempt failed.
class SignInState {
  const SignInState({this.sending = false, this.failure});

  final bool sending;
  final String? failure;
}

/// Sends the ID token from Google's button to the API. Once the session opens, the router leaves
/// the sign-in screen on its own.
class SignInController extends Notifier<SignInState> {
  static const noConnection = 'No se pudo conectar con el servidor. Revisá la conexión y probá de nuevo.';

  @override
  SignInState build() => const SignInState();

  Future<void> submitIdToken(String idToken) async {
    if (state.sending) return;
    state = const SignInState(sending: true);
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithGoogle(idToken);
      if (ref.mounted) state = const SignInState();
    } on ErrorDeApi catch (e) {
      // An unknown email is a 403 with the API's own message. It never reaches the token renewal:
      // the auth endpoints use a client without one.
      if (ref.mounted) state = SignInState(failure: e.estado == null ? noConnection : e.mensaje);
    }
  }

  /// Google's button couldn't work (e.g. its library didn't load).
  void googleFailed(String message) => state = SignInState(failure: message);
}
