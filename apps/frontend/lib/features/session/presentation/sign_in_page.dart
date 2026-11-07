import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'providers.dart';

/// Sign-in with the button Google draws. The router brings the user here without a session and
/// takes them away as soon as one opens.
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    final googleButton = ref.watch(googleButtonProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Espacio.xl),
            child: SignInPanel(
              title: 'Maktub Barbell Club',
              subtitle: 'Ingresá con la cuenta de Google que dio de alta tu coach.',
              busy: state.sending,
              message: state.failure,
              action: googleButton(onIdToken: controller.submitIdToken, onError: controller.googleFailed),
            ),
          ),
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
