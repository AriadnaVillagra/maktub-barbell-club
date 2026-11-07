import '../features/session/domain/session_manager.dart';
import 'router.dart';

/// Where the app has to go for the session's [status], or null to stay at [location].
///
/// Without a session every route leads to sign-in; with one, sign-in leads into the app. The route
/// the user asked for travels in `desde`, so a deep link survives the detour. The gallery (debug
/// only) is open to everyone.
String? sessionRedirect(SessionStatus status, Uri location) {
  final path = location.path;
  if (path == Rutas.galeria) return null;
  final inSessionGate = path == Rutas.signIn || path == Rutas.restoring;

  String gate(String route) {
    final from = inSessionGate ? location.queryParameters[_from] : _requested(location);
    return Uri(path: route, queryParameters: from == null ? null : {_from: from}).toString();
  }

  return switch (status) {
    SessionStatus.restoring => path == Rutas.restoring ? null : gate(Rutas.restoring),
    SessionStatus.signedOut => path == Rutas.signIn ? null : gate(Rutas.signIn),
    SessionStatus.signedIn => inSessionGate ? _safeTarget(location.queryParameters[_from]) : null,
  };
}

const _from = 'desde';

/// The route to come back to, or null for the default one.
String? _requested(Uri location) {
  final requested = location.toString();
  return requested == Rutas.entrenamiento || requested == '/' ? null : requested;
}

/// Only paths inside the app, and never back to a session gate.
String _safeTarget(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) return Rutas.entrenamiento;
  final path = Uri.parse(from).path;
  if (path == Rutas.signIn || path == Rutas.restoring) return Rutas.entrenamiento;
  return from;
}
