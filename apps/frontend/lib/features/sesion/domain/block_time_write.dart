import 'package:maktub_core/maktub_core.dart';

/// The write of one block's time (E7.19), as the guided mode builds it when a block closes. The time's id is not
/// here: the queue gives each write its own, once, and reuses it on every retry.
class BlockTimeWrite {
  const BlockTimeWrite({
    required this.blockIndex,
    required this.blockName,
    this.athleteMode,
    required this.athleteIds,
    required this.start,
    required this.end,
    this.interrupted = false,
  });

  /// Reads what [toJson] wrote, as the local queue keeps it.
  factory BlockTimeWrite.fromJson(Json j) => BlockTimeWrite(
    blockIndex: (j['bloque'] as num).toInt(),
    blockName: '${j['bloqueNombre']}',
    athleteMode: j['modoAtletas'] == null
        ? null
        : AthleteMode.deCable(j['modoAtletas']),
    athleteIds: [for (final a in (j['atletaIds'] as List)) '$a'],
    start: DateTime.parse('${j['inicio']}').toUtc(),
    end: DateTime.parse('${j['fin']}').toUtc(),
    interrupted: j['interrumpido'] == true,
  );

  final int blockIndex;
  final String blockName;

  /// Null for a block without steps.
  final AthleteMode? athleteMode;
  final List<String> athleteIds;
  final DateTime start;
  final DateTime end;
  final bool interrupted;

  Json toJson() => {
    'bloque': blockIndex,
    'bloqueNombre': blockName,
    'modoAtletas': ?athleteMode?.cable,
    'atletaIds': athleteIds,
    'inicio': start.toUtc().toIso8601String(),
    'fin': end.toUtc().toIso8601String(),
    'interrumpido': interrupted,
  };
}
