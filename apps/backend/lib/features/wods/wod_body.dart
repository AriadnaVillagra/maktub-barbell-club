import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

/// Builds the [Wod] a create or save request describes. The server owns `id`, `clubId` and `auditoria`: what
/// the body says for them is ignored. Throws [ErrorDeSolicitud] (400 for a malformed body, 422 with the
/// problems, and nothing written, for a WoD without name or with a prescription without exercise).
Wod wodFromBody(
  Json body, {
  required String id,
  required String clubId,
  required Auditoria auditoria,
}) {
  final Wod wod;
  try {
    wod = Wod.fromJson({
      ...body,
      'id': id,
      'clubId': clubId,
      'auditoria': auditoria.toJson(),
    });
  } on FormatException {
    throw const ErrorDeSolicitud('El WoD tiene un formato inválido.');
  } on TypeError {
    throw const ErrorDeSolicitud('El WoD tiene un formato inválido.');
  }
  final problems = validateWod(wod);
  if (problems.isNotEmpty) {
    throw ErrorDeSolicitud(
      'El WoD tiene ${problems.length} problema(s); no se guardó.',
      estado: 422,
      extra: {
        'problemas': [
          for (final p in problems)
            {
              'codigo': p.code.name,
              if (p.prescriptionIndex != null)
                'prescripcion': p.prescriptionIndex,
            },
        ],
      },
    );
  }
  return Wod(
    id: wod.id,
    clubId: wod.clubId,
    name: wod.name.trim(),
    description: wod.description,
    timerId: wod.timerId,
    prescriptions: wod.prescriptions,
    auditoria: wod.auditoria,
  );
}
