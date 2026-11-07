import 'package:flutter/widgets.dart';

import 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';

/// OAuth client ID of the app in GCP project `maktub-514012` (docs/work/M1-mvp/E1.1). It isn't a
/// secret. Change it with `--dart-define=GOOGLE_CLIENT_ID=...`, like `API_URL`. The backend checks
/// the ID token's `aud` against the same value.
const googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: '312703406459-c6kmar4snieeg2o1bqi8446rq498ujgg.apps.googleusercontent.com',
);

/// Builds the sign-in button. [onIdToken] gets each Google ID token as soon as the user picks an
/// account; [onError] gets a message for the user when the button can't work.
typedef GoogleButtonBuilder = Widget Function({
  required ValueChanged<String> onIdToken,
  required ValueChanged<String> onError,
});

/// The button drawn by Google Identity Services on the web (design.md §3.4: `google_sign_in`
/// can't do this on the web). Elsewhere it only says that sign-in needs the web app.
Widget googleButton({
  required ValueChanged<String> onIdToken,
  required ValueChanged<String> onError,
}) =>
    platformGoogleButton(clientId: googleClientId, onIdToken: onIdToken, onError: onError);
