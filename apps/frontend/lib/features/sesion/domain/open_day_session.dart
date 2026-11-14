import 'dart:math';

import 'package:maktub_core/maktub_core.dart';

import 'session_draft_store.dart';
import 'session_repository.dart';
import 'set_sync_queue.dart';

/// The day whose session opens: what the server's key of the session needs, plus what a session opened on the
/// device needs to stand on its own until the server answers.
class DayToOpen {
  const DayToOpen({
    required this.clubId,
    required this.assignmentId,
    required this.planId,
    required this.cycle,
    required this.date,
    required this.week,
    required this.day,
  });

  final String clubId;
  final String assignmentId;
  final String planId;

  /// The cycle [date] falls in.
  final int cycle;

  /// Calendar date (`DateTime.utc(y, m, d)`).
  final DateTime date;
  final int week;
  final int day;
}

/// Opens or resumes the session of a day (E7.3), also without signal (E7.16, D8).
///
/// - With signal it is the server's opening. If an opening made without signal is still queued for that day, the
///   queue goes out first, so the server has it, and the sets after it, before the session is read.
/// - Without signal, a session this device already opened comes from its copy (E7.15). Athletes chosen as present
///   that the copy does not have are shown at once and their opening is queued, so they travel with it.
/// - Without signal, a session never opened here is opened on the device: a session with a local id, no records and
///   the preloaded kilos, kept in the copy, and its opening queued ahead of the sets marked on it.
class OpenDaySession {
  OpenDaySession({
    required this.sessions,
    required this.queue,
    this.copy,
    required this.userId,
    DateTime Function()? now,
    String Function()? newLocalId,
  }) : _now = now ?? DateTime.now,
       _newLocalId = newLocalId ?? _randomLocalId;

  final SessionRepository sessions;
  final SetSyncQueue queue;

  /// Without a copy, a session opened on the device lives only on screen and in the queue.
  final SessionCopy? copy;

  /// Who opens, for the audit of a session opened on the device. The server stamps its own.
  final String userId;
  final DateTime Function() _now;
  final String Function() _newLocalId;

  Future<LiveSession> call(DayToOpen d, Set<String> present) async {
    final asOpening = PendingSessionOpen(
      clubId: d.clubId,
      sessionId: '',
      assignmentId: d.assignmentId,
      date: d.date,
      week: d.week,
      day: d.day,
      presentAthleteIds: present.toList(),
    );
    if (await queue.openingLike(asOpening) != null) await queue.flush();
    final LiveSession live;
    try {
      live = await sessions.open(
        d.clubId,
        assignmentId: d.assignmentId,
        date: d.date,
        week: d.week,
        day: d.day,
        presentAthleteIds: present,
      );
    } on SessionNotOpenedHere {
      return _openOnDevice(d, asOpening);
    }
    final missing = present.difference(live.session.presentAthleteIds.toSet());
    // The server always adds who comes present, so missing athletes mean the session came from the copy.
    if (missing.isEmpty) return live;
    final queued = await queue.submitOpen(
      _withSession(asOpening, live.session.id),
    );
    final shown = LiveSession(
      session: _withPresent(live.session, queued.presentAthleteIds),
      records: live.records,
    );
    await copy?.remember(shown);
    return shown;
  }

  Future<LiveSession> _openOnDevice(
    DayToOpen d,
    PendingSessionOpen asOpening,
  ) async {
    final queued = await queue.submitOpen(
      _withSession(asOpening, '$localSessionPrefix${_newLocalId()}'),
    );
    final live = LiveSession(
      session: Session(
        id: queued.sessionId,
        clubId: d.clubId,
        assignmentId: d.assignmentId,
        planId: d.planId,
        cycle: d.cycle,
        week: d.week,
        day: d.day,
        date: d.date,
        presentAthleteIds: queued.presentAthleteIds,
        auditoria: Auditoria.nueva(userId, ahora: _now()),
      ),
      records: const [],
    );
    await copy?.remember(live);
    return live;
  }
}

PendingSessionOpen _withSession(PendingSessionOpen o, String sessionId) =>
    PendingSessionOpen(
      clubId: o.clubId,
      sessionId: sessionId,
      assignmentId: o.assignmentId,
      date: o.date,
      week: o.week,
      day: o.day,
      presentAthleteIds: o.presentAthleteIds,
    );

Session _withPresent(Session s, List<String> present) =>
    Session.fromJson({...s.toJson(), 'presentes': present});

final _random = Random.secure();

String _randomLocalId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';
