import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// The body of the sign-in screen: the club's name, a line of help, the slot for the sign-in button
/// and the reason the last attempt failed.
///
/// The button is drawn by Google's library (an HTML element), so the panel only reserves its room:
/// [externalButtonWidth] × [externalButtonHeight]. While [busy], a progress indicator takes the
/// button's place. It doesn't scroll: the screen wraps it in a scroll view.
class SignInPanel extends StatelessWidget {
  const SignInPanel({
    super.key,
    this.logo,
    required this.title,
    this.subtitle,
    required this.action,
    this.busy = false,
    this.message,
  });

  /// Width asked from Google's button, in logical pixels (Google allows up to 400).
  static const externalButtonWidth = 320.0;

  /// Room for Google's "large" button (40 px tall) without clipping its focus ring.
  static const externalButtonHeight = 44.0;

  static const _maxWidth = 400.0;

  /// Centered above the [title].
  final Widget? logo;
  final String title;
  final String? subtitle;
  final Widget action;
  final bool busy;

  /// Why the last attempt failed, shown under the button. Null when there's nothing to say.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final logo = this.logo;
    final subtitle = this.subtitle;
    final message = this.message;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logo != null) ...[
            Center(child: logo),
            const SizedBox(height: Espacio.xl),
          ],
          Text(title, style: context.textos.displaySmall, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: Espacio.s),
            Text(
              subtitle,
              style: context.textos.bodyLarge?.copyWith(color: context.esquema.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Espacio.xxl),
          SizedBox(
            height: externalButtonHeight,
            child: Center(
              child: busy
                  ? const AspectRatio(aspectRatio: 1, child: CircularProgressIndicator())
                  : action,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: Espacio.l),
            _FailureMessage(message),
          ],
        ],
      ),
    );
  }
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = context.esquema.onErrorContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.m),
        decoration: BoxDecoration(
          color: context.esquema.errorContainer,
          borderRadius: const BorderRadius.all(Radius.circular(Radios.medio)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: Espacio.m),
            Expanded(child: Text(text, style: context.textos.bodyMedium?.copyWith(color: color))),
          ],
        ),
      ),
    );
  }
}
