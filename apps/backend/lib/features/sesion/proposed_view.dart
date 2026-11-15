import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

// What the two "proposed kilos" endpoints share: by session (E7.7) and by assignment and date (E7.14).

/// [set] as [club]'s user may see it: the work factor only travels to whoever can edit references, so an athlete
/// is told their kilos but not their factor.
Json proposedSetForViewer(ProposedSet set, ClubContext club) =>
    club.can(Accion.editarReferencias)
    ? set.toJson()
    : (set.toJson()..remove('factor'));

/// The `ajuste` query parameter: the day's session-level adjustment (50..150), or null when absent. 400 if
/// malformed.
int? sessionAdjustmentParam(List<String>? values) {
  if (values == null || values.isEmpty) return null;
  final parsed = int.tryParse(values.last);
  if (parsed == null || parsed < Ajuste.minimo || parsed > Ajuste.maximo) {
    throw const ErrorDeSolicitud('"ajuste" debe ser un entero entre 50 y 150.');
  }
  return parsed;
}

/// The `ajusteEjercicio=<exerciseId>:<value>` query parameters, each overriding `ajuste` for one exercise. 400 if
/// one is malformed.
Map<String, int> exerciseAdjustmentsParam(List<String>? values) {
  final result = <String, int>{};
  for (final value in values ?? const <String>[]) {
    final colon = value.lastIndexOf(':');
    final id = colon <= 0 ? '' : value.substring(0, colon);
    final parsed = colon <= 0 ? null : int.tryParse(value.substring(colon + 1));
    if (id.isEmpty ||
        parsed == null ||
        parsed < Ajuste.minimo ||
        parsed > Ajuste.maximo) {
      throw const ErrorDeSolicitud(
        '"ajusteEjercicio" debe ser <ejercicioId>:<entero entre 50 y 150>.',
      );
    }
    result[id] = parsed;
  }
  return result;
}
