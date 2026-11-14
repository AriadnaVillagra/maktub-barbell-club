import 'package:maktub_core/maktub_core.dart';

/// The kilos proposed for one date of an assignment, for every day of that date's week and every athlete asked
/// for (E7.14). The day is chosen at training time (D13), so all of them come.
class ProposedDate {
  const ProposedDate({
    required this.date,
    required this.cycle,
    required this.week,
    required this.days,
  });

  final DateTime date;
  final int cycle;
  final int week;

  /// Sets by athlete id, by 1-based day.
  final Map<int, Map<String, List<ProposedSet>>> days;

  /// The sets of [athleteId] on [day], or null when the date does not have them.
  List<ProposedSet>? setsOf(int day, String athleteId) => days[day]?[athleteId];

  /// The wire shape of one entry of `fechas`.
  factory ProposedDate.fromJson(Json j) => ProposedDate(
    date: soloFecha(DateTime.parse('${j['fecha']}')),
    cycle: (j['ciclo'] as num).toInt(),
    week: (j['semana'] as num).toInt(),
    days: {
      for (final d in (j['dias'] as List? ?? const []).cast<Map>())
        (d['dia'] as num).toInt(): {
          for (final a in (d['atletas'] as List? ?? const []).cast<Map>())
            '${a['atletaId']}': [
              for (final s in (a['series'] as List? ?? const []))
                ProposedSet.fromJson((s as Map).cast<String, dynamic>()),
            ],
        },
    },
  );

  Json toJson() => {
    'fecha': aIsoFecha(date),
    'ciclo': cycle,
    'semana': week,
    'dias': [
      for (final d in days.entries)
        {
          'dia': d.key,
          'atletas': [
            for (final a in d.value.entries)
              {
                'atletaId': a.key,
                'series': [for (final s in a.value) s.toJson()],
              },
          ],
        },
    ],
  };
}

abstract interface class ProposedDaysRepository {
  /// The kilos proposed on each date from [from] to [to] (at most 31 days) of [assignmentId], for every athlete of
  /// its group the user may see, without day adjustment. Dates outside the assignment are left out.
  Future<List<ProposedDate>> proposedDays(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to,
  );
}
