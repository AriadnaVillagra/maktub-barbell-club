import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';

/// [record] as JSON for [club]'s user. The work factor is the coach's (like in the athlete sheet), and the real
/// percent would give it away next to the plan's, so whoever cannot edit references gets neither.
Json recordForViewer(SetRecord record, ClubContext club) {
  final json = record.toJson();
  if (club.can(Accion.editarReferencias)) return json;
  return json
    ..remove('factor')
    ..remove('pctReal');
}
