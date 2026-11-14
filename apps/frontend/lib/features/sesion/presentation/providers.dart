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
import '../domain/block_time_write.dart';
import '../domain/guided_session.dart';
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

/// The device's draft and queue of set writes and block times (E7.9, E7.21). It outlives the screen, so leaving it does not drop anything.
final setSyncQueueProvider = Provider<SetSyncQueue>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  final queue = SetSyncQueue(
    send: (p) => repository.recordSet(p.clubId, p.sessionId, p.write),
    sendTime: (t) =>
        repository.recordBlockTime(t.clubId, t.sessionId, t.id, t.write),
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

/// Whether what the device queued reached the server, kept current as the queue changes.
class SaveStateController extends Notifier<SaveState> {
  @override
  SaveState build() {
    final queue = ref.watch(setSyncQueueProvider);
    final subscription = queue.changes.listen((_) => state = queue.saveState);
    ref.onDispose(subscription.cancel);
    return queue.saveState;
  }
}

final saveStateProvider =
    NotifierProvider.autoDispose<SaveStateController, SaveState>(
      SaveStateController.new,
    );

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

/// The present athlete on screen: the chosen one, else the user if present, else the first present.
String? athleteOnScreen(
  SessionDayData data,
  SessionScreenState state,
  LiveSession live,
) {
  final present = live.session.presentAthleteIds;
  return state.athleteId ??
      (present.contains(data.ownAthleteId)
          ? data.ownAthleteId
          : present.firstOrNull);
}

/// The plan's day of the open session; null if the plan no longer has it.
PlanDay? liveDayOf(SessionDayData data, LiveSession live) {
  final days = data.plan.weekModelOf(live.session.week)?.days ?? const [];
  final day = live.session.day;
  return day >= 1 && day <= days.length ? days[day - 1] : null;
}

/// The guided mode's clock. Tests override it.
final guidedClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The guided mode over the open session (E7.20): the pure [GuidedSession], fed with the session's records, and the
/// set writes it leads to, through the same draft and queue as the session's list (E7.8, E7.9). Null without an open
/// session. Its position is local and is dropped when the guided screen closes.
class GuidedController extends Notifier<GuidedSession?> {
  @override
  GuidedSession? build() {
    // A set another device marks, or one this device wrote, may close the block.
    ref.listen(
      sessionScreenProvider.select((s) => s.live?.records),
      (_, _) => _update((s) => s.settle(recorded, now: _now)),
    );
    final data = ref.read(sessionDayProvider).value;
    final screen = ref.read(sessionScreenProvider);
    final live = screen.live;
    if (data == null || live == null) return null;
    final day = liveDayOf(data, live);
    if (day == null) return null;
    final athlete = athleteOnScreen(data, screen, live) ?? data.ownAthleteId;
    return GuidedSession.choosing(day, [?athlete]);
  }

  LiveSession? get _live => ref.read(sessionScreenProvider).live;

  /// The done sets of the session, wherever they were marked.
  Set<BlockSet> get recorded => recordedSets(_live?.records ?? const []);

  DateTime get _now => ref.read(guidedClockProvider)();

  void _update(GuidedSession Function(GuidedSession) change) {
    final s = state;
    if (s != null) _set(s, change(s));
  }

  /// Moves to [next] and, for each block it closed as done or interrupted (a skipped one leaves no time), queues the
  /// block's time (E7.21). Every change of state goes through here, so a block closed by any path leaves its time.
  void _set(GuidedSession previous, GuidedSession next) {
    state = next;
    for (var i = 0; i < next.runs.length && i < previous.runs.length; i++) {
      final run = next.runs[i];
      final timed =
          run.status == GuidedBlockStatus.done ||
          run.status == GuidedBlockStatus.interrupted;
      final wasTimed =
          previous.runs[i].status == GuidedBlockStatus.done ||
          previous.runs[i].status == GuidedBlockStatus.interrupted;
      if (timed && !wasTimed) _queueTime(next, run);
    }
  }

  void _queueTime(GuidedSession guided, GuidedBlockRun run) {
    final live = _live;
    final start = run.start;
    final end = run.end;
    if (live == null || start == null || end == null) return;
    final block = guided.day.blocks[run.blockIndex];
    unawaited(
      ref
          .read(setSyncQueueProvider)
          .submitBlockTime(
            clubId: live.session.clubId,
            sessionId: live.session.id,
            write: BlockTimeWrite(
              blockIndex: run.blockIndex,
              blockName: block.name,
              athleteMode: blockHasSteps(block) ? run.athleteMode : null,
              athleteIds: guided.athleteIds,
              start: start,
              end: end,
              interrupted: run.status == GuidedBlockStatus.interrupted,
            ),
          )
          .then((_) {}, onError: (_) {}),
    );
  }

  void toggleAthlete(String athleteId) =>
      _update((s) => s.toggleAthlete(athleteId));

  /// "Comenzar". An athlete who is not present yet is added to the session first, since only present athletes record
  /// sets. Rethrows the backend's error so the screen can show it.
  Future<void> begin() async {
    final s = state;
    final live = _live;
    final data = ref.read(sessionDayProvider).value;
    if (s == null || live == null || data == null) return;
    final present = live.session.presentAthleteIds;
    if (!s.athleteIds.every(present.contains)) {
      await ref
          .read(sessionScreenProvider.notifier)
          .open(
            data,
            week: live.session.week,
            day: live.session.day,
            present: {...present, ...s.athleteIds},
          );
    }
    _update((s) => s.begin(now: _now));
  }

  void setAthleteMode(AthleteMode mode) =>
      _update((s) => s.withAthleteMode(mode));

  void setExecutionMode(ExecutionMode mode) =>
      _update((s) => s.withExecutionMode(mode));

  void startBlock() => _update((s) => s.startBlock(recorded, now: _now));

  void skipBlock() => _update((s) => s.skipBlock(now: _now));

  void interruptBlock() => _update((s) => s.interruptBlock(now: _now));

  void startStep() => _update((s) => s.startStep(recorded));

  void toggleNotDone(String athleteId) =>
      _update((s) => s.toggleNotDone(athleteId, recorded));

  void edit(String athleteId, SetEdit edit) =>
      _update((s) => s.edit(athleteId, edit, recorded));

  void leaveExercise(String athleteId) =>
      _update((s) => s.leaveExercise(athleteId, recorded, now: _now));

  void skipExercise() => _update((s) => s.skipExercise(recorded, now: _now));

  /// "Terminar serie": moves on at once and writes each athlete's set with what their card shows. Rethrows the
  /// backend's refusal so the screen can show it.
  Future<void> finishStep() async {
    final s = state;
    final done = recorded;
    final run = s?.run;
    final step = s?.currentStep(done);
    if (s == null || run == null || step == null) return;
    final draft = s.draftFor(step);
    final result = s.finishStep(done, now: _now);
    final writes = [
      for (final a in result.record)
        _markWrite(
          s.day.blocks[run.blockIndex],
          run.blockIndex,
          step.prescription,
          step.set,
          a,
          draft.edits[a],
        ),
    ];
    _set(s, result.next);
    await _send(writes);
  }

  /// "Terminar bloque" of a block without steps. A timed block's sets that nobody recorded yet are recorded as the
  /// plan has them, for every athlete training.
  Future<void> finishBlock() async {
    final s = state;
    final run = s?.run;
    final block = s?.block;
    if (s == null || run == null || block == null) return;
    final done = recorded;
    final writes = [
      for (final a in s.athleteIds)
        for (var p = 0; p < block.prescriptions.length; p++)
          for (var set = 0; set < block.prescriptions[p].sets.length; set++)
            if (!done.contains((run.blockIndex, AthleteSet(a, p, set))))
              _markWrite(block, run.blockIndex, p, set, a, null),
    ];
    _set(s, s.finishBlock(now: _now));
    await _send(writes);
  }

  SetWrite _markWrite(
    PlanBlock block,
    int b,
    int p,
    int set,
    String athleteId,
    SetEdit? edit,
  ) {
    final screen = ref.read(sessionScreenProvider);
    final current = screen.live?.records
        .where(
          (r) =>
              r.athleteId == athleteId &&
              r.blockIndex == b &&
              r.prescriptionIndex == p &&
              r.setIndex == set,
        )
        .firstOrNull;
    final write = SetWrite.of(
      current,
      athleteId: athleteId,
      blockIndex: b,
      prescriptionIndex: p,
      setIndex: set,
      adjustment: screen
          .adjustmentsOf(athleteId)
          .effectiveFor(block.prescriptions[p].exerciseId ?? ''),
    ).markedDone();
    return edit == null
        ? write
        : write.edited(manualKg: edit.manualKg, reps: edit.reps);
  }

  /// Sends every write even if the server refuses one, and then rethrows the first refusal.
  Future<void> _send(List<SetWrite> writes) async {
    final clubId = _live?.session.clubId;
    if (clubId == null) return;
    final screen = ref.read(sessionScreenProvider.notifier);
    Object? refused;
    for (final w in writes) {
      try {
        await screen.writeSet(clubId, w);
      } catch (e) {
        refused ??= e;
      }
    }
    if (refused != null) throw refused;
  }
}

final guidedProvider =
    NotifierProvider.autoDispose<GuidedController, GuidedSession?>(
      GuidedController.new,
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
