import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../../club_requests/presentation/club_request_form.dart';
import '../../club_requests/presentation/providers.dart';
import 'providers.dart';

/// Where the sign-in screen is: the Google button, the offer to request a club after a "no account"
/// answer, the request form, or where a sent request stands.
enum SignInStage { signIn, noAccount, requestForm, requestPending, requestRejected }

/// What the sign-in screen shows: the [stage], whether something is on its way to the API, and why the
/// last attempt failed.
class SignInState {
  const SignInState({this.stage = SignInStage.signIn, this.sending = false, this.failure, this.idToken});

  final SignInStage stage;
  final bool sending;
  final String? failure;

  /// The Google ID token of the refused sign-in: it proves the email when a club request is sent. Only kept
  /// in memory, while the screen is open.
  final String? idToken;

  SignInState copyWith({SignInStage? stage, bool? sending, String? failure}) =>
      SignInState(stage: stage ?? this.stage, sending: sending ?? this.sending, failure: failure, idToken: idToken);
}

/// Sends the ID token from Google's button to the API. Once the session opens, the router leaves
/// the sign-in screen on its own. Without an account, it leads to requesting a club (2026-11-21).
class SignInController extends Notifier<SignInState> {
  static const noConnection = 'No se pudo conectar con el servidor. Revisá la conexión y probá de nuevo.';
  static const tokenExpired =
      'Pasó demasiado tiempo desde que elegiste la cuenta. Ingresá con Google de nuevo y enviá el pedido.';

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
      if (!ref.mounted) return;
      final refusal = e.estado == 403 ? SignInRefusal.fromWireOrNull(e.cuerpo?['codigo']) : null;
      state = switch (refusal) {
        SignInRefusal.noAccount => SignInState(stage: SignInStage.noAccount, failure: e.mensaje, idToken: idToken),
        SignInRefusal.requestPending => const SignInState(stage: SignInStage.requestPending),
        SignInRefusal.requestRejected => SignInState(stage: SignInStage.requestRejected, idToken: idToken),
        null => SignInState(failure: e.estado == null ? noConnection : e.mensaje),
      };
    }
  }

  /// Google's button couldn't work (e.g. its library didn't load).
  void googleFailed(String message) => state = SignInState(failure: message);

  /// Only after a refused sign-in, which left the ID token that proves the email.
  void openRequestForm() {
    if (state.idToken == null) return;
    state = state.copyWith(stage: SignInStage.requestForm);
  }

  Future<void> sendRequest(ClubRequestFields fields) async {
    final idToken = state.idToken;
    if (state.sending || idToken == null) return;
    state = state.copyWith(sending: true);
    try {
      await ref.read(clubRequestApiProvider).send(
        idToken: idToken,
        clubName: fields.clubName,
        requesterName: fields.requesterName,
        note: fields.note,
      );
      if (ref.mounted) state = const SignInState(stage: SignInStage.requestPending);
    } on ErrorDeApi catch (e) {
      if (!ref.mounted) return;
      if (e.estado == 409 && SignInRefusal.fromWireOrNull(e.cuerpo?['codigo']) == SignInRefusal.requestPending) {
        state = const SignInState(stage: SignInStage.requestPending);
      } else if (e.estado == 401) {
        state = const SignInState(failure: tokenExpired);
      } else {
        state = state.copyWith(sending: false, failure: e.estado == null ? noConnection : e.mensaje);
      }
    }
  }

  void backToSignIn() => state = const SignInState();
}
