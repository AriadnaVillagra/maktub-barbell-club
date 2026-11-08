import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'ficha_atleta_store.dart';

/// `GET /clubes/{clubId}/atletas/{athleteId}` → `{atletaId, referencias, factores, kilajes}`: the RM and
/// work factor histories and the fixed weights of one athlete. The order of the histories is not defined
/// yet (open question in E3.4): they come as the store returns them. [store] is for tests.
///
/// Access: anyone with [Accion.verReportesDeTodos] (the coach) reads any athlete of the club; anyone with
/// only [Accion.verReportesPropios] reads the athlete linked to their own user. Asking for another
/// athlete's sheet, or for one that does not exist in the club, gets the same 404, so the answer
/// does not say whether that athlete exists.
Future<Response> athleteSheetEndpoint(
  RequestContext context,
  String athleteId, {
  AthleteSheetStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verReportesPropios);
  final sheet = await ReadAthleteSheet(
    store ?? MongoAthleteSheetStore(context.read<Db>()),
  )(club, athleteId);
  return Response.json(body: sheet);
}

class ReadAthleteSheet {
  ReadAthleteSheet(this._store);

  final AthleteSheetStore _store;

  Future<Json> call(ClubContext club, String athleteId) async {
    final linkedUser = await _store.athleteUserId(club.clubId, athleteId);
    final allowed =
        linkedUser != null &&
        (club.can(Accion.verReportesDeTodos) || linkedUser == club.userId);
    if (!allowed) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }
    // Work factors and fixed weights are the coach's: an athlete only gets their RMs.
    final seesAll = club.can(Accion.editarReferencias);
    final references = await _store.references(club.clubId, athleteId);
    final factors = seesAll
        ? await _store.workFactors(club.clubId, athleteId)
        : const <WorkFactor>[];
    final weights = seesAll
        ? await _store.fixedWeights(club.clubId, athleteId)
        : const <FixedWeight>[];
    return {
      'atletaId': athleteId,
      'referencias': [for (final r in references) r.toJson()],
      'factores': [for (final f in factors) f.toJson()],
      'kilajes': [for (final w in weights) w.toJson()],
    };
  }
}
