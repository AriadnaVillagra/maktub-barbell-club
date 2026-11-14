import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/proposed_days.dart';

/// The proposed kilos by date with the device's copy (E7.15), one saved entry per date, so the preload of today and
/// the next days serves any of them without signal.
class CachedProposedDaysRepository implements ProposedDaysRepository {
  CachedProposedDaysRepository(this._remote, this._reads);

  final ProposedDaysRepository _remote;
  final LocalCopyReads _reads;

  static String _prefix(String clubId, String assignmentId) =>
      '${copyKey(['proposed', clubId, assignmentId])}/';

  static String _key(String clubId, String assignmentId, DateTime date) =>
      '${_prefix(clubId, assignmentId)}${aIsoFecha(date)}';

  @override
  Future<List<ProposedDate>> proposedDays(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to,
  ) async {
    final List<ProposedDate> dates;
    try {
      dates = await _remote.proposedDays(clubId, assignmentId, from, to);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final saved = <ProposedDate>[];
      DateTime? oldest;
      for (
        var d = soloFecha(from);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))
      ) {
        final copy = await _read(_key(clubId, assignmentId, d));
        if (copy == null) continue;
        saved.add(copy.$1);
        if (oldest == null || copy.$2.isBefore(oldest)) oldest = copy.$2;
      }
      if (oldest == null) throw const NoLocalCopy(_missing);
      _reads.reporter.servedFromCopy(oldest);
      return saved;
    }
    _reads.reporter.servedFresh();
    for (final d in dates) {
      await _reads.save(_key(clubId, assignmentId, d.date), d, (d) => d.toJson());
    }
    return dates;
  }

  Future<(ProposedDate, DateTime)?> _read(String key) async {
    final copy = await _reads.store.read(key);
    if (copy == null) return null;
    try {
      return (
        ProposedDate.fromJson((copy.data as Map).cast<String, dynamic>()),
        copy.savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// The saved kilos of [athleteId] on [day] of [week] of [cycle], without adjustment: those of [date] when its week
  /// is that one, else those of the nearest saved date in that week (the user may train another week's day). Null
  /// when nothing saved has them. Reports the copy it serves.
  Future<List<ProposedSet>?> savedSets(
    String clubId,
    String assignmentId, {
    required DateTime date,
    required int cycle,
    required int week,
    required int day,
    required String athleteId,
  }) async {
    final exact = await _read(_key(clubId, assignmentId, date));
    (ProposedDate, DateTime)? found;
    if (exact != null && exact.$1.cycle == cycle && exact.$1.week == week) {
      found = exact;
    } else {
      final day0 = soloFecha(date);
      for (final key in await _reads.store.keys(_prefix(clubId, assignmentId))) {
        final entry = await _read(key);
        if (entry == null ||
            entry.$1.cycle != cycle ||
            entry.$1.week != week ||
            entry.$1.setsOf(day, athleteId) == null) {
          continue;
        }
        final distance = entry.$1.date.difference(day0).inDays.abs();
        if (found == null ||
            distance < found.$1.date.difference(day0).inDays.abs()) {
          found = entry;
        }
      }
    }
    final sets = found?.$1.setsOf(day, athleteId);
    if (found == null || sets == null) return null;
    _reads.reporter.servedFromCopy(found.$2);
    return sets;
  }

  static const _missing =
      'Sin señal y sin kilos guardados para estas fechas. Se cargan cuando vuelva la señal.';
}
