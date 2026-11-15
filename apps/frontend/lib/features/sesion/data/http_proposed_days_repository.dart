import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/proposed_days.dart';

class HttpProposedDaysRepository implements ProposedDaysRepository {
  HttpProposedDaysRepository(this._client);

  final ClienteApi _client;

  @override
  Future<List<ProposedDate>> proposedDays(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to,
  ) async {
    final j = await _client.get(
      '/clubes/${Uri.encodeComponent(clubId)}'
      '/asignaciones/${Uri.encodeComponent(assignmentId)}/kilos-propuestos'
      '?desde=${aIsoFecha(from)}&hasta=${aIsoFecha(to)}',
    );
    return [
      for (final f in (j['fechas'] as List? ?? const []))
        ProposedDate.fromJson((f as Map).cast<String, dynamic>()),
    ];
  }
}
