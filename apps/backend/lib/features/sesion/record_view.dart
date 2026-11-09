import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';

/// Whether [club]'s user can see work factors. The factor is the coach's (like in the athlete sheet), and the real
/// percent would give it away next to the plan's, so whoever cannot edit references gets neither.
bool canSeeFactors(ClubContext club) => club.can(Accion.editarReferencias);

Json _recordJson(SetRecord record, {required bool seesFactors}) {
  final json = record.toJson();
  if (seesFactors) return json;
  return json
    ..remove('factor')
    ..remove('pctReal');
}

/// [record] as JSON for [club]'s user.
Json recordForViewer(SetRecord record, ClubContext club) =>
    _recordJson(record, seesFactors: canSeeFactors(club));

/// [change] as JSON for someone who can or cannot see work factors.
Json changeForViewer(SessionChange change, {required bool seesFactors}) {
  final record = change.record;
  if (record == null) return change.toJson();
  return {
    ...change.toJson(),
    'registro': _recordJson(record, seesFactors: seesFactors),
  };
}
