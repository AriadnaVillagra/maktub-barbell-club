import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_identity_services_web/id.dart' as gis;
import 'package:google_identity_services_web/loader.dart' as gis;
import 'package:maktub_ui/maktub_ui.dart';
import 'package:web/web.dart' as web;

Widget platformGoogleButton({
  required String clientId,
  required ValueChanged<String> onIdToken,
  required ValueChanged<String> onError,
}) =>
    _GisButton(clientId: clientId, onIdToken: onIdToken, onError: onError);

const _loadFailed = 'No se pudo cargar el ingreso con Google. Revisá la conexión y recargá la página.';

/// The Google Identity Services client of the page. GIS wants a single `initialize`, so the SDK is
/// loaded and initialized once, and each ID token goes to whichever button is on screen.
abstract final class _Gis {
  static Future<void>? _ready;
  static final _idTokens = StreamController<String>.broadcast();

  static Stream<String> get idTokens => _idTokens.stream;

  /// Loads and initializes GIS. A failed load (no signal) is retried by the next button.
  static Future<void> ready(String clientId) => _ready ??= _load(clientId);

  static Future<void> _load(String clientId) async {
    try {
      await gis.loadWebSdk().timeout(const Duration(seconds: 20));
    } on Object {
      _ready = null;
      rethrow;
    }
    gis.id.initialize(gis.IdConfiguration(
      client_id: clientId,
      callback: _onCredential,
      ux_mode: gis.UxMode.popup,
      auto_select: false,
    ));
  }

  static void _onCredential(gis.CredentialResponse response) {
    final idToken = response.credential;
    if (idToken != null && idToken.isNotEmpty) _idTokens.add(idToken);
  }
}

class _GisButton extends StatefulWidget {
  const _GisButton({required this.clientId, required this.onIdToken, required this.onError});

  final String clientId;
  final ValueChanged<String> onIdToken;
  final ValueChanged<String> onError;

  @override
  State<_GisButton> createState() => _GisButtonState();
}

class _GisButtonState extends State<_GisButton> {
  late final Future<void> _ready;
  late final StreamSubscription<String> _idTokens;

  @override
  void initState() {
    super.initState();
    _idTokens = _Gis.idTokens.listen((idToken) => widget.onIdToken(idToken));
    _ready = _Gis.ready(widget.clientId);
    _ready.catchError((Object _) {
      if (mounted) widget.onError(_loadFailed);
    });
  }

  @override
  void dispose() {
    _idTokens.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox.shrink(); // the screen shows the message
          if (snapshot.connectionState != ConnectionState.done) {
            return const AspectRatio(aspectRatio: 1, child: CircularProgressIndicator());
          }
          final dark = Theme.of(context).brightness == Brightness.dark;
          return SizedBox(
            width: SignInPanel.externalButtonWidth,
            height: SignInPanel.externalButtonHeight,
            child: HtmlElementView.fromTagName(
              key: ValueKey(dark),
              tagName: 'div',
              onElementCreated: (element) => _render(element as web.HTMLElement, dark: dark),
            ),
          );
        },
      );

  static void _render(web.HTMLElement container, {required bool dark}) {
    // Without this, a dark page paints a white box behind Google's iframe.
    container.style.colorScheme = 'light';
    gis.id.renderButton(
      container,
      gis.GsiButtonConfiguration(
        type: gis.ButtonType.standard,
        theme: dark ? gis.ButtonTheme.filled_black : gis.ButtonTheme.outline,
        size: gis.ButtonSize.large,
        text: gis.ButtonText.signin_with,
        shape: gis.ButtonShape.pill,
        logo_alignment: gis.ButtonLogoAlignment.left,
        width: SignInPanel.externalButtonWidth,
        locale: 'es',
      ),
    );
  }
}
