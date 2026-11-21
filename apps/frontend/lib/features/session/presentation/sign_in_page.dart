import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../club_requests/presentation/club_request_form.dart';
import 'providers.dart';
import 'sign_in_controller.dart';

/// Sign-in with the button Google draws. The router brings the user here without a session and
/// takes them away as soon as one opens. Without an account, the same screen leads to requesting a
/// club and then says where the request stands.
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  static const title = 'Maktub Barbell Club';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    final googleButton = ref.watch(googleButtonProvider);
    Widget google() => googleButton(onIdToken: controller.submitIdToken, onError: controller.googleFailed);
    final back = TextButton(
      key: const Key('club-request-back'),
      onPressed: controller.backToSignIn,
      child: const Text('Volver al ingreso'),
    );

    final panel = switch (state.stage) {
      SignInStage.signIn => SignInPanel(
        logo: const ClubLogo(),
        title: title,
        subtitle: 'Ingresá con la cuenta de Google que dio de alta tu coach.',
        busy: state.sending,
        message: state.failure,
        action: google(),
      ),
      SignInStage.noAccount => SignInPanel(
        logo: const ClubLogo(),
        title: title,
        subtitle: 'Ingresá con la cuenta de Google que dio de alta tu coach.',
        busy: state.sending,
        message: state.failure,
        action: google(),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Espacio.s,
          children: [
            Text(
              '¿Entrenás a un equipo? Podés pedir un club propio.',
              style: context.textos.bodyMedium,
              textAlign: TextAlign.center,
            ),
            OutlinedButton.icon(
              key: const Key('club-request-open'),
              onPressed: controller.openRequestForm,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Pedir un club para mi equipo'),
            ),
          ],
        ),
      ),
      SignInStage.requestForm => SignInPanel(
        title: 'Pedir un club',
        subtitle:
            'Un administrador de Maktub revisa cada pedido. Cuando lo apruebe, vas a ingresar con esta misma cuenta de Google.',
        busy: state.sending,
        message: state.failure,
        action: const Icon(Icons.groups_outlined),
        footer: ClubRequestForm(
          sending: state.sending,
          onSubmit: controller.sendRequest,
          onCancel: controller.backToSignIn,
        ),
      ),
      SignInStage.requestPending => SignInPanel(
        logo: const ClubLogo(),
        title: 'Tu pedido está en revisión',
        subtitle: 'Cuando un administrador lo apruebe, vas a poder ingresar con esta cuenta de Google.',
        action: const Icon(Icons.hourglass_top),
        footer: back,
      ),
      SignInStage.requestRejected => SignInPanel(
        logo: const ClubLogo(),
        title: 'Tu pedido no fue aprobado',
        subtitle: 'Podés enviar un pedido nuevo o ingresar con otra cuenta.',
        action: const Icon(Icons.block),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Espacio.s,
          children: [
            FilledButton(
              key: const Key('club-request-again'),
              onPressed: controller.openRequestForm,
              child: const Text('Pedir de nuevo'),
            ),
            back,
          ],
        ),
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(padding: const EdgeInsets.all(Espacio.xl), child: panel),
        ),
      ),
    );
  }
}

/// Shown for the instant the saved tokens take to load.
class SessionRestoringPage extends StatelessWidget {
  const SessionRestoringPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
