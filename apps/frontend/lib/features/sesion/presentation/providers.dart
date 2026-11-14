import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../../asignacion/domain/calendar_repository.dart';
import '../../asignacion/presentation/calendar_providers.dart'
    show calendarRepositoryProvider;
import '../../asignacion/presentation/providers.dart'
    show assignmentRepositoryProvider;
import '../../atletas/presentation/providers.dart'
    show athleteRepositoryProvider, todayProvider;
import '../../catalogo/presentation/providers.dart'
    show catalogRepositoryProvider;
import '../data/http_session_repository.dart';
import '../data/shared_preferences_draft_store.dart';
import '../domain/athlete_adjustments.dart';
import '../domain/session_draft_store.dart';
import '../domain/session_repository.dart';
import '../domain/set_sync_queue.dart';
import '../domain/set_write.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => HttpSessionRepository(ref.watch(clienteApiProvider)),
);

final sessionDraftStoreProvider = Provider<SessionDraftStore>(
  (ref) => SharedPreferencesDraftStore(),
);

/// How often a queue with writes left tries again. E7.10 also flushes it when the live channel reconnects.
const queueRetryInterval = Duration(seconds: 15);

/// The device's draft and queue of set writes (E7.9). It outlives the screen, so leaving it does not drop anything.
final setSyncQueueProvider = Provider<SetSyncQueue>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  final queue = SetSyncQueue(
    send: (p) => repository.recordSet(p.clubId, p.sessionId, p.write),
    store: ref.watch(sessionDraftStoreProvider),
    isRetryable: isTransientWriteError,
  );
  Timer? retry;
  final subscription = queue.changes.listen((pending) {
    if (pending.isEmpty) {
      retry?.cancel();
      retry = null;
    } else {
      retry ??= Timer.periodic(queueRetryInterval, (_) => queue.flush());
    }
  });
  unawaited(queue.flush()); // what a previous run left queued
  ref.onDispose(() {
    retry?.cancel();
    subscription.cancel();
    queue.dispose();
  });
  return queue;
});

/// What the session screen needs for today: the group, where today falls in its assignment and the published plan.
class SessionDayData {
  const SessionDayData({
    required this.clubId,
    required this.group,
    required this.location,
    required this.plan,
    required this.exerciseNames,
    required this.athleteNames,
    required this.openingDay,
    this.ownAthleteId,
  });

  final String clubId;
  final AthleteGroup group;
  final CalendarLocation location;
  final PublishedPlanView plan;

  /// Exercise name by id.
  final Map<String, String> exerciseNames;

  /// Athlete name by id; empty when the user cannot list them (only coaches can).
  final Map<String, String> athleteNames;

  /// The day of today's week that opens by D13.
  final int openingDay;

  /// The user's athlete id, when they are one in this club.
  final String? ownAthleteId;
}

/// Null when the group has no active assignment.
final sessionDayProvider = FutureProvider.autoDispose<SessionDayData?>((
  ref,
) async {
  final access = (await ref.watch(meProvider.future))?.activeClub;
  if (access == null) return null;
  final clubId = access.club.id;
  final groups = await ref.watch(assignmentRepositoryProvider).groups(clubId);
  if (groups.isEmpty) return null;
  final group = groups.first;
  final calendar = ref.watch(calendarRepositoryProvider);
  final location = await calendar.locate(
    clubId,
    group.id,
    ref.watch(todayProvider),
  );
  if (location == null) return null;
  final plan = await calendar.publishedPlan(clubId, location.planId);
  final exercises = await ref
      .watch(catalogRepositoryProvider)
      .exercises(clubId);
  final athletes = access.can(Accion.verReportesDeTodos)
      ? await ref.watch(athleteRepositoryProvider).athletes(clubId)
      : const [];
  final today = ref.watch(todayProvider);
  final states = await calendar.dayStates(clubId, group.id, today, today);
  final dayCount = plan.weekModelOf(location.week)?.days.length ?? 0;
  return SessionDayData(
    clubId: clubId,
    group: group,
    location: location,
    plan: plan,
    exerciseNames: {for (final e in exercises) e.id: e.name},
    athleteNames: {for (final a in athletes) a.id: a.name},
    openingDay: firstPendingDay(
      states,
      cycle: location.cycle,
      week: location.week,
      dayCount: dayCount,
    ),
    ownAthleteId: access.athleteId,
  );
});

/// The screen's state: which day is chosen, who is present, the open session and each athlete's adjustment.
class SessionScreenState {
  const SessionScreenState({
    this.week,
    this.day,
    this.present,
    this.live,
    this.athleteId,
    this.adjustments = const {},
    this.opening = false,
  });

  /// The chosen week and day; null keeps today's week and the D13 day.
  final int? week;
  final int? day;

  /// The chosen present athletes; null is the default (the user, if they are in the group).
  final Set<String>? present;

  /// The opened session of the chosen day; null while choosing.
  final LiveSession? live;

  /// The athlete on screen; null is the default (the user, or the first present).
  final String? athleteId;

  /// Day adjustment by athlete id. Missing is neutral.
  final Map<String, AthleteAdjustments> adjustments;
  final bool opening;

  AthleteAdjustments adjustmentsOf(String athleteId) =>
      adjustments[athleteId] ?? const AthleteAdjustments();
}

class SessionScreenController extends Notifier<SessionScreenState> {
  @override
  SessionScreenState build() => const SessionScreenState();

  /// Choosing another week goes to its first day, as the calendar does, and leaves the open session.
  void selectWeek(int week) =>
      state = SessionScreenState(week: week, day: 1, present: state.present);

  /// Choosing another day leaves the open session.
  void selectDay(int week, int day) =>
      state = SessionScreenState(week: week, day: day, present: state.present);

  void setPresent(Set<String> present) => state = SessionScreenState(
    week: state.week,
    day: state.day,
    present: present,
    live: state.live,
    athleteId: state.athleteId,
    adjustments: state.adjustments,
  );

  /// Opens or resumes the session. Rethrows the backend's error so the screen can show it.
  Future<void> open(
    SessionDayData data, {
    required int week,
    required int day,
    required Set<String> present,
  }) async {
    state = _with(opening: true);
    try {
      final live = await ref
          .read(sessionRepositoryProvider)
          .open(
            data.clubId,
            assignmentId: data.location.assignmentId,
            date: ref.read(todayProvider),
            week: week,
            day: day,
            presentAthleteIds: present,
          );
      final unsent = await ref
          .read(setSyncQueueProvider)
          .resume(live.session.id);
      state = SessionScreenState(
        week: state.week,
        day: state.day,
        present: state.present,
        live: unsent.fold<LiveSession>(
          live,
          (l, w) => _replacing(
            l,
            projectedRecord(
              _recordOf(l, w),
              w,
              clubId: data.clubId,
              sessionId: l.session.id,
            ),
          ),
        ),
      );
    } finally {
      state = _with(opening: false);
    }
  }

  /// Writes one set through the draft and queue and keeps what the server stored, or what the write leaves while it
  /// stays queued without signal. Rethrows the backend's refusal so the screen can show it.
  Future<void> writeSet(String clubId, SetWrite write) async {
    final sessionId = state.live?.session.id;
    if (sessionId == null) return;
    final stored = await ref
        .read(setSyncQueueProvider)
        .submit(clubId: clubId, sessionId: sessionId, write: write);
    final live = state.live;
    if (live == null || live.session.id != sessionId) return;
    state = _with(
      live: _replacing(
        live,
        stored ??
            projectedRecord(
              _recordOf(live, write),
              write,
              clubId: clubId,
              sessionId: sessionId,
            ),
      ),
    );
  }

  static SetRecord? _recordOf(LiveSession live, SetWrite write) => live.records
      .where(
        (r) =>
            r.athleteId == write.athleteId &&
            r.blockIndex == write.blockIndex &&
            r.prescriptionIndex == write.prescriptionIndex &&
            r.setIndex == write.setIndex,
      )
      .firstOrNull;

  static LiveSession _replacing(LiveSession live, SetRecord record) =>
      LiveSession(
        session: live.session,
        records: [
          for (final r in live.records)
            if (!_sameSet(r, record)) r,
          record,
        ],
      );

  /// Writes the session's note. Rethrows the backend's error so the screen can show it.
  Future<void> saveSessionNote(String clubId, String note) async {
    final sessionId = state.live?.session.id;
    if (sessionId == null) return;
    final session = await ref
        .read(sessionRepositoryProvider)
        .saveSessionNote(clubId, sessionId, note);
    final live = state.live;
    if (live == null || live.session.id != sessionId) return;
    state = _with(
      live: LiveSession(session: session, records: live.records),
    );
  }

  static bool _sameSet(SetRecord a, SetRecord b) =>
      a.athleteId == b.athleteId &&
      a.blockIndex == b.blockIndex &&
      a.prescriptionIndex == b.prescriptionIndex &&
      a.setIndex == b.setIndex;

  void selectAthlete(String athleteId) => state = _with(athleteId: athleteId);

  void stepSessionAdjustment(String athleteId, int delta) =>
      _updateAdjustments(athleteId, (a) => a.stepSession(delta));

  void stepExerciseAdjustment(String athleteId, String exerciseId, int delta) =>
      _updateAdjustments(athleteId, (a) => a.stepExercise(exerciseId, delta));

  void _updateAdjustments(
    String athleteId,
    AthleteAdjustments Function(AthleteAdjustments) update,
  ) => state = SessionScreenState(
    week: state.week,
    day: state.day,
    present: state.present,
    live: state.live,
    athleteId: state.athleteId,
    adjustments: {
      ...state.adjustments,
      athleteId: update(state.adjustmentsOf(athleteId)),
    },
    opening: state.opening,
  );

  SessionScreenState _with({
    bool? opening,
    String? athleteId,
    LiveSession? live,
  }) => SessionScreenState(
    week: state.week,
    day: state.day,
    present: state.present,
    live: live ?? state.live,
    athleteId: athleteId ?? state.athleteId,
    adjustments: state.adjustments,
    opening: opening ?? state.opening,
  );
}

final sessionScreenProvider =
    NotifierProvider.autoDispose<SessionScreenController, SessionScreenState>(
      SessionScreenController.new,
    );

/// The proposed kilos of one athlete in one session.
typedef ProposedLoadsQuery = ({
  String clubId,
  String sessionId,
  String athleteId,
  AthleteAdjustments adjustments,
});

final proposedLoadsProvider = FutureProvider.autoDispose
    .family<List<ProposedSet>, ProposedLoadsQuery>(
      (ref, q) => ref
          .watch(sessionRepositoryProvider)
          .proposedLoads(q.clubId, q.sessionId, q.athleteId, q.adjustments),
    );
