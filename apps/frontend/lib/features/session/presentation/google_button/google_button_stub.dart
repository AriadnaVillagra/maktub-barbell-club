import 'package:flutter/widgets.dart';

/// Outside the web there is no Google Identity Services button.
Widget platformGoogleButton({
  required String clientId,
  required ValueChanged<String> onIdToken,
  required ValueChanged<String> onError,
}) =>
    const Text('El ingreso con Google funciona en la versión web de la app.', textAlign: TextAlign.center);
