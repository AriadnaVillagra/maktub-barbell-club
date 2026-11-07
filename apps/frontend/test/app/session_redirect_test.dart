import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/app/session_redirect.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';

void main() {
  String? go(SessionStatus status, String location) => sessionRedirect(status, Uri.parse(location));

  group('signed out', () {
    test('every route leads to sign-in, keeping the requested one', () {
      expect(go(SessionStatus.signedOut, Rutas.entrenamiento), Rutas.signIn);
      expect(go(SessionStatus.signedOut, Rutas.planificacion), '${Rutas.signIn}?desde=%2Fplanificacion');
    });

    test('stays at sign-in', () {
      expect(go(SessionStatus.signedOut, Rutas.signIn), isNull);
      expect(go(SessionStatus.signedOut, '${Rutas.signIn}?desde=%2Fplanificacion'), isNull);
    });

    test('leaves the loading screen for sign-in with the same destination', () {
      expect(go(SessionStatus.signedOut, '${Rutas.restoring}?desde=%2Fplanificacion'),
          '${Rutas.signIn}?desde=%2Fplanificacion');
    });

    test('the gallery is open', () {
      expect(go(SessionStatus.signedOut, Rutas.galeria), isNull);
    });
  });

  group('restoring', () {
    test('waits on the loading screen', () {
      expect(go(SessionStatus.restoring, Rutas.planificacion), '${Rutas.restoring}?desde=%2Fplanificacion');
      expect(go(SessionStatus.restoring, Rutas.restoring), isNull);
    });
  });

  group('signed in', () {
    test('sign-in and loading lead into the app, to the requested route', () {
      expect(go(SessionStatus.signedIn, Rutas.signIn), Rutas.entrenamiento);
      expect(go(SessionStatus.signedIn, '${Rutas.signIn}?desde=%2Fplanificacion'), Rutas.planificacion);
      expect(go(SessionStatus.signedIn, '${Rutas.restoring}?desde=%2Fplanificacion'), Rutas.planificacion);
    });

    test('app routes stay', () {
      expect(go(SessionStatus.signedIn, Rutas.planificacion), isNull);
    });

    test('never goes back to a gate or outside the app', () {
      expect(go(SessionStatus.signedIn, '${Rutas.signIn}?desde=%2Fingreso'), Rutas.entrenamiento);
      expect(go(SessionStatus.signedIn, '${Rutas.signIn}?desde=https%3A%2F%2Fevil.example'), Rutas.entrenamiento);
      expect(go(SessionStatus.signedIn, '${Rutas.signIn}?desde=%2F%2Fevil.example'), Rutas.entrenamiento);
    });
  });
}
