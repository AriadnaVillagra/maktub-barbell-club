import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart' show NoLocalCopy;
import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../../../core/red/cliente_api.dart' show ErrorDeApi;
import '../../access/presentation/providers.dart';
import '../../asignacion/domain/calendar_repository.dart';
import '../../asignacion/presentation/calendar_providers.dart'
    show calendarRepositoryProvider;
import '../../asignacion/presentation/providers.dart'
    show assignmentRepositoryProvider;
import '../../atletas/presentation/providers.dart'
    show athleteRepositoryProvider, todayProvider;
import '../../catalogo/presentation/providers.dart'
    show catalogAdminRepositoryProvider, catalogRepositoryProvider;
import '../../session/domain/session_manager.dart' show SessionStatus;
import '../../session/presentation/providers.dart'
    show sessionControllerProvider;
import '../data/cached_proposed_days_repository.dart';
import '../data/cached_session_repository.dart';
import '../data/http_proposed_days_repository.dart';
import '../data/http_session_repository.dart';
import '../data/shared_preferences_calendar_layout_store.dart';
import '../data/shared_preferences_collapsed_blocks_store.dart';
import '../domain/collapsed_blocks.dart';
import '../data/shared_preferences_draft_store.dart';
import '../data/web_socket_live_channel.dart';
import '../domain/athlete_adjustments.dart';
import '../domain/block_time_write.dart';
import '../domain/calendar_layout.dart';
import '../domain/guided_session.dart';
import '../domain/live_channel.dart';
import '../domain/live_session_sync.dart';
import '../domain/open_day_session.dart';
import '../domain/preload_days.dart';
import '../domain/proposed_days.dart';
import '../domain/session_draft_store.dart';
import '../domain/session_repository.dart';
import '../domain/set_sync_queue.dart';
import '../domain/set_write.dart';

/// The session straight from the server. Tests replace it to keep the device's copy in between.
final remoteSessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => HttpSessionRepository(ref.watch(clienteApiProvider)),
);

/// The proposed kilos by date straight from the server (E7.14). Tests replace it.
final remoteProposedDaysRepositoryProvider = Provider<ProposedDaysRepository>(
  (ref) => HttpProposedDaysRepository(ref.watch(clienteApiProvider)),
);

/// The proposed kilos by date, kept on the device for each date (E7.15).
final proposedDaysRepositoryProvider = Provider<CachedProposedDaysRepository>(
  (ref) => CachedProposedDaysRepository(
    ref.watch(remoteProposedDaysRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
);

/// The session with the device's copy as fallback without signal (E7.15).
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => CachedSessionRepository(
    ref.watch(remoteSessionRepositoryProvider),
    ref.watch(localCopyReadsProvider),
    ref.watch(proposedDaysRepositoryProvider),
  ),
);

/// The device's copy of the sessions, when the repository keeps one (tests that replace it may not).
final sessionCopyProvider = Provider<SessionCopy?>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  return repository is SessionCopy ? repository as SessionCopy : null;
});

/// How long a saved copy is kept: older ones are dropped on every preload.
const localCopyRetention = Duration(days: 14);

/// Clock of the copy's pruning. Tests override it.
final localCopyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Preloads today and the next days on the device once the user is signed in (E7.15). The app keeps it listened
/// to, so it runs on every start with a session; without signal it changes nothing.
final preloadDaysProvider = FutureProvider<void>((ref) async {
  if (ref.watch(sessionControllerProvider) != SessionStatus.signedIn) return;
  final now = ref.read(localCopyClockProvider)();
  await ref
      .read(localCopyStoreProvider)
      .prune(now.subtract(localCopyRetention));
  await PreloadDays(
    me: ref.read(meRepositoryProvider),
    assignments: ref.read(assignmentRepositoryProvider),
    calendar: ref.read(calendarRepositoryProvider),
    catalog: ref.read(catalogRepositoryProvider),
    catalogAdmin: ref.read(catalogAdminRepositoryProvider),
    athletes: ref.read(athleteRepositoryProvider),
    proposedDays: ref.read(proposedDaysRepositoryProvider),
  )(ref.read(todayProvider));
});

/// The live channel of the open session (E7.10). Tests replace it with a fake.
final liveChannelProvider = Provider<LiveChannel>(
  (ref) => WebSocketLiveChannel(ref.watch(clienteApiProvider)),
);

/// The waits between attempts to reopen the live channel. Tests shorten them.
final liveReconnectBackoffProvider = Provider<List<Duration>>(
  (ref) => LiveSessionSync.defaultBackoff,
);

final sessionDraftStoreProvider = Provider<SessionDraftStore>(
  (ref) => SharedPreferencesDraftStore(),
);

/// How often a queue with writes left tries again. It is also flushed every time the live channel opens (E7.10).
const queueRetryInterval = Duration(seconds: 15);

/// The device's draft and queue of set writes, guided pass writes and block times (E7.9, E7.21, E7.26). It outlives the screen, so leaving it does not drop anything.
final setSyncQueueProvider = Provider<SetSyncQueue>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  final copy = ref.watch(sessionCopyProvider);
  final queue = SetSyncQueue(
    send: (p) => repository.recordSet(p.clubId, p.sessionId, p.write),
    sendTime: (t) =>
        repository.recordBlockTime(t.clubId, t.sessionId, t.id, t.write),
    sendGuided: (g) =>
        repository.writeGuidedPass(g.clubId, g.sessionId, g.action),
    // Never through the copy: an opening answered from it would look taken while the server never saw it.
    sendOpen: (o) => (copy?.openOnServer ?? repository.open)(
      o.clubId,
      assignmentId: o.assignmentId,
      date: o.date,
      week: o.week,
      day: o.day,
      presentAthleteIds: o.presentAthleteIds.toSet(),
    ),
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

/// What the session screen needs for today in one assignment: who trains it, where today falls in it and the
/// published plan. An athlete can have two on the same date, their group's and their own (E8.8).
class SessionDayData {
  const SessionDayData({
    required this.clubId,
    required this.memberIds,
    required this.ownerLabel,
    required this.location,
    required this.plan,
    required this.exerciseNames,
    required this.athleteNames,
    required this.openingDay,
    this.ownAthleteId,
    this.userId = '',
  });

  final String clubId;

  /// The athletes in the assignment today (E6.7); for a location saved before E6.7, its group's members or its one
  /// athlete.
  final List<String> memberIds;

  /// Who the plan is for, to tell two plans of the same date apart: "Plan propio", "Ari, Andi" or "2 atletas".
  final String ownerLabel;
  final CalendarLocation location;
  final PublishedPlanView plan;

  /// Exercise name by id.
  final Map<String, String> exerciseNames;

  /// Athlete name by id; empty when the user cannot list them (only coaches can).
  final Map<String, String> athleteNames;

  /// The day of today's week that opens by D13: the first one the athlete of the first tab has not finished.
  final int openingDay;

  /// The user's athlete id, when they are one in this club.
  final String? ownAthleteId;

  /// Who is using the app, for the audit of a session opened without signal.
  final String userId;
}

final calendarLayoutStoreProvider = Provider<CalendarLayoutStore>(
  (ref) => SharedPreferencesCalendarLayoutStore(),
);

/// The calendar layout the user chose (E7.25), remembered on the device. Starts compact until the saved one loads;
/// a choice made before that wins.
class CalendarLayoutController extends Notifier<CalendarLayout> {
  var _chosen = false;

  @override
  CalendarLayout build() {
    unawaited(_restore());
    return CalendarLayout.compact;
  }

  Future<void> _restore() async {
    final saved = await ref.read(calendarLayoutStoreProvider).load();
    if (saved != null && !_chosen && ref.mounted) state = saved;
  }

  void choose(CalendarLayout layout) {
    _chosen = true;
    state = layout;
    unawaited(ref.read(calendarLayoutStoreProvider).save(layout));
  }
}

final calendarLayoutProvider =
    NotifierProvider<CalendarLayoutController, CalendarLayout>(
      CalendarLayoutController.new,
    );

final collapsedBlocksStoreProvider = Provider<CollapsedBlocksStore>(
  (ref) => SharedPreferencesCollapsedBlocksStore(),
);

/// The block cards of the session screen the user collapsed, by block index, remembered on the device. Keyed by
/// index (not by day) to stay simple: a block position folds the same way on every day. A change made before the
/// saved set loads wins.
class CollapsedBlocksController extends Notifier<Set<int>> {
  var _changed = false;

  @override
  Set<int> build() {
    unawaited(_restore());
    return const {};
  }

  Future<void> _restore() async {
    final saved = await ref.read(collapsedBlocksStoreProvider).load();
    if (!_changed && ref.mounted) state = saved;
  }

  void _set(Set<int> next) {
    _changed = true;
    state = next;
    unawaited(ref.read(collapsedBlocksStoreProvider).save(next));
  }

  void toggle(int block) => _set(
    state.contains(block) ? ({...state}..remove(block)) : {...state, block},
  );

  /// Collapses the first [count] blocks, or expands them all when they already are.
  void toggleAll(int count) => _set(
    state.containsAll([for (var i = 0; i < count; i++) i])
        ? <int>{}
        : {for (var i = 0; i < count; i++) i},
  );
}

final collapsedBlocksProvider =
    NotifierProvider<CollapsedBlocksController, Set<int>>(
      CollapsedBlocksController.new,
    );

/// Which cycle's day states to fetch: the cycle of the assignment [assignmentId], started on [startDate], as
/// [athleteId] did it (null: done when anyone recorded a set, for an assignment without athletes).
typedef CycleDaysQuery = (
  String clubId,
  String assignmentId,
  DateTime startDate,
  int cycle,
  String? athleteId,
);

/// The state of the days of one cycle for one athlete: done, in progress with its count, or pending (E7.13, E7.24;
/// per athlete since 2026-11-21). Invalidated when sets are recorded, so the day badges follow.
final cycleDayStatesProvider = FutureProvider.autoDispose
    .family<List<DayState>, CycleDaysQuery>((ref, query) {
      final (clubId, assignmentId, startDate, cycle, athleteId) = query;
      final (from, to) = cycleDates(startDate, cycle);
      return ref
          .watch(calendarRepositoryProvider)
          .dayStates(clubId, assignmentId, from, to, athleteId: athleteId);
    });

/// Where today falls for the user: every active assignment they train, their groups' and their own (E8.8). A user
/// who is not an athlete of the club sees the first group's.
Future<List<CalendarLocation>> todaysLocations(
  CalendarRepository calendar,
  String clubId, {
  required String? athleteId,
  required List<AthleteGroup> groups,
  required DateTime today,
}) async {
  if (athleteId != null) {
    return calendar.locateAthlete(clubId, athleteId, today);
  }
  if (groups.isEmpty) return const [];
  return [?await calendar.locate(clubId, groups.first.id, today)];
}

/// Every plan of today, one per active assignment the user trains (E8.8: an athlete's own plan lives alongside their
/// group's). Empty when there is none.
final sessionDaysProvider = FutureProvider.autoDispose<List<SessionDayData>>((
  ref,
) async {
  final me = await ref.watch(meProvider.future);
  final access = me?.activeClub;
  if (access == null) return const [];
  final clubId = access.club.id;
  final groups = await ref.watch(assignmentRepositoryProvider).groups(clubId);
  final calendar = ref.watch(calendarRepositoryProvider);
  final locations = await todaysLocations(
    calendar,
    clubId,
    athleteId: access.athleteId,
    groups: groups,
    today: ref.watch(todayProvider),
  );
  if (locations.isEmpty) return const [];
  final exercises = await ref
      .watch(catalogRepositoryProvider)
      .exercises(clubId);
  final athletes = access.can(Accion.verReportesDeTodos)
      ? await ref.watch(athleteRepositoryProvider).athletes(clubId)
      : const [];
  return [
    for (final location in locations)
      await _dayData(
        ref,
        clubId: clubId,
        location: location,
        groups: groups,
        exerciseNames: {for (final e in exercises) e.id: e.name},
        athleteNames: {for (final a in athletes) a.id: a.name},
        ownAthleteId: access.athleteId,
        userId: me!.user.id,
      ),
  ];
});

Future<SessionDayData> _dayData(
  Ref ref, {
  required String clubId,
  required CalendarLocation location,
  required List<AthleteGroup> groups,
  required Map<String, String> exerciseNames,
  required Map<String, String> athleteNames,
  required String? ownAthleteId,
  required String userId,
}) async {
  final plan = await ref
      .watch(calendarRepositoryProvider)
      .publishedPlan(clubId, location.planId);
  // E6.7: the location lists who is in the plan today. One saved before that does not: it was its group's (or the
  // first group's, before E8.8), or its one athlete's.
  final group = location.athleteIds != null || location.athleteId != null
      ? null
      : groups.where((g) => g.id == location.groupId).firstOrNull ??
            (location.groupId == null ? groups.firstOrNull : null);
  final dayCount = plan.weekModelOf(location.week)?.days.length ?? 0;
  final memberIds =
      location.athleteIds ??
      (location.athleteId != null
          ? [location.athleteId!]
          : group?.memberIds ?? const <String>[]);
  // The day that opens is the first one the athlete of the first tab has not finished.
  final states = await ref.read(
    cycleDayStatesProvider((
      clubId,
      location.assignmentId,
      location.startDate,
      location.cycle,
      defaultAthleteOf(memberIds, ownAthleteId),
    )).future,
  );
  return SessionDayData(
    clubId: clubId,
    memberIds: memberIds,
    ownerLabel: location.athleteIds == null && group != null
        ? 'Grupo ${group.name}'.trim()
        : _ownerLabel(memberIds, athleteNames, ownAthleteId),
    location: location,
    plan: plan,
    exerciseNames: exerciseNames,
    athleteNames: athleteNames,
    openingDay: firstPendingDay(
      states,
      cycle: location.cycle,
      week: location.week,
      dayCount: dayCount,
    ),
    ownAthleteId: ownAthleteId,
    userId: userId,
  );
}

/// Which of today's plans is on screen, by assignment id; null is the first one.
class ChosenPlanController extends Notifier<String?> {
  @override
  String? build() => null;

  void choose(String assignmentId) => state = assignmentId;
}

final chosenPlanProvider = NotifierProvider<ChosenPlanController, String?>(
  ChosenPlanController.new,
);

/// The plan of today on screen: the chosen one among [sessionDaysProvider], else the first. Null when the user has
/// no active assignment.
final sessionDayProvider = FutureProvider.autoDispose<SessionDayData?>((
  ref,
) async {
  final days = await ref.watch(sessionDaysProvider.future);
  final chosen = ref.watch(chosenPlanProvider);
  return days.where((d) => d.location.assignmentId == chosen).firstOrNull ??
      days.firstOrNull;
});

/// The screen's state: which day is chosen, its session if it exists, the athlete on screen and each athlete's
/// adjustment.
class SessionScreenState {
  const SessionScreenState({
    this.week,
    this.day,
    this.live,
    this.athleteId,
    this.adjustments = const {},
    this.opening = false,
    this.liveStatus = LiveStatus.connecting,
  });

  /// The chosen week and day; null keeps today's week and the D13 day.
  final int? week;
  final int? day;

  /// The session of the chosen day; null while it does not exist (E7.27: it is born with the first write).
  final LiveSession? live;

  /// The athlete tab on screen; null is the default (the user if they are in the group, else the first).
  final String? athleteId;

  /// Day adjustment by athlete id. Missing is neutral.
  final Map<String, AthleteAdjustments> adjustments;

  /// Whether a write is creating the session, or adding an athlete to it.
  final bool opening;

  /// How the open session's live channel is doing. Only an indicator: marking a set never waits for it.
  final LiveStatus liveStatus;

  AthleteAdjustments adjustmentsOf(String athleteId) =>
      adjustments[athleteId] ?? const AthleteAdjustments();
}

/// The week and day on screen: the session's when one is shown, else the chosen ones, else today's week and the D13
/// day, kept within the week's days. The session's win so the day never drifts from the records on screen: the D13
/// day moves once the day being trained has its first set done.
({int week, int day}) shownDayOf(
  SessionDayData data,
  SessionScreenState state,
) {
  if (state.live?.session case final s?) return (week: s.week, day: s.day);
  final week = state.week ?? data.location.week;
  final count = data.plan.weekModelOf(week)?.days.length ?? 0;
  final day = (state.day ?? data.openingDay).clamp(1, count < 1 ? 1 : count);
  return (week: week, day: day);
}

/// The plan's [day] of [week]; null if the plan does not have it.
PlanDay? planDayOf(SessionDayData data, int week, int day) {
  final days = data.plan.weekModelOf(week)?.days ?? const [];
  return day >= 1 && day <= days.length ? days[day - 1] : null;
}

/// The screen of the day's session (E7.3, E7.27). There is no "open" step: the chosen day is looked up without
/// creating anything, and its session, if it exists, is taken with its records and followed live. While it does not
/// exist, the lookup is repeated every [queueRetryInterval] so a session another device creates shows up. The first
/// write (a set, a note, an adjustment, "Comenzar") creates it through [ensureSession], adding the athletes it
/// writes for to the present ones.
class SessionScreenController extends Notifier<SessionScreenState> {
  LiveSessionSync? _sync;
  SessionDayData? _data;
  Timer? _poll;
  Future<void> _ensuring = Future.value();
  StreamSubscription<LiveStatus>? _statusSubscription;
  StreamSubscription<List<PendingWrite>>? _queueSubscription;
  StreamSubscription<SessionOpened>? _openedSubscription;
  StreamSubscription<Session>? _guidedSubscription;

  /// Changes from the channel for sets this device still has a write queued for. Showing them would undo on screen
  /// what the user just marked; they apply once that write leaves the queue (its own change follows anyway).
  final _heldBack = <SetKey, SessionChange>{};

  @override
  SessionScreenState build() {
    _openedSubscription = ref
        .read(setSyncQueueProvider)
        .opened
        .listen((o) => unawaited(_onOpened(o)));
    _guidedSubscription = ref
        .read(setSyncQueueProvider)
        .guidedStored
        .listen(_onGuidedStored);
    ref.onDispose(() {
      _openedSubscription?.cancel();
      _guidedSubscription?.cancel();
      _poll?.cancel();
      _stopFollowing();
    });
    return const SessionScreenState();
  }

  SessionDayData? get _dayData => _data ?? ref.read(sessionDayProvider).value;

  /// The screen shows [data]: looks up the chosen day's session, and keeps looking every [queueRetryInterval] while
  /// it does not exist. Called every time the day's view appears, so coming back to it looks again.
  void show(SessionDayData data) {
    _data = data;
    _poll ??= Timer.periodic(queueRetryInterval, (_) {
      if (state.live == null) unawaited(_lookUp());
    });
    if (state.live == null) unawaited(_lookUp());
  }

  /// Reads the chosen day's session without creating it and, if it exists, takes it with what this device still has
  /// queued over it and follows its live channel. A failed read is left for the next attempt.
  ///
  /// A session belongs to a date: today's is looked up first, and a day done on another date with no session today
  /// shows the session it was done in, so its marked sets are there whatever the day it is looked at.
  Future<void> _lookUp() async {
    final data = _dayData;
    if (data == null) return;
    final shown = shownDayOf(data, state);
    final today = ref.read(todayProvider);
    final sessions = ref.read(sessionRepositoryProvider);
    Future<LiveSession?> findOn(DateTime date) => sessions.find(
      data.clubId,
      assignmentId: data.location.assignmentId,
      date: date,
      week: shown.week,
      day: shown.day,
    );
    LiveSession? found;
    try {
      found = await findOn(today);
      if (found == null) {
        final doneOn = await _doneDateOf(data, shown.week, shown.day);
        if (doneOn != null && doneOn != today) found = await findOn(doneOn);
      }
    } catch (_) {
      return;
    }
    bool stale() =>
        !ref.mounted ||
        state.live != null ||
        state.opening ||
        _dayData?.location.assignmentId != data.location.assignmentId ||
        shownDayOf(data, state) != shown;
    if (found == null || stale()) return;
    final unsent = await ref
        .read(setSyncQueueProvider)
        .resume(found.session.id);
    if (stale()) return;
    _follow(found.session);
    state = _with(
      live: _withUnsent(found, unsent),
      liveStatus: _sync?.status ?? LiveStatus.connecting,
    );
  }

  /// The date the athlete on screen started [day] of [week], from the cycle's day states; null when it is pending or
  /// they cannot be read.
  Future<DateTime?> _doneDateOf(SessionDayData data, int week, int day) async {
    final subscription = ref.listen(
      cycleDayStatesProvider((
        data.clubId,
        data.location.assignmentId,
        data.location.startDate,
        data.location.cycle,
        athleteOnScreen(data, state),
      )).future,
      (_, _) {},
    );
    try {
      return doneDateOf(
        await subscription.read(),
        cycle: data.location.cycle,
        week: week,
        day: day,
      );
    } catch (_) {
      return null;
    } finally {
      subscription.close();
    }
  }

  /// The opening of the session on screen reached the server (E7.16): the screen moves to the server's session, with
  /// what is still queued over it, and starts following its live channel.
  Future<void> _onOpened(SessionOpened opened) async {
    final shown = state.live?.session.id;
    final server = opened.live.session;
    if (shown != opened.sessionId && shown != server.id) return;
    final unsent = await ref.read(setSyncQueueProvider).resume(server.id);
    if (!ref.mounted) return;
    final now = state.live?.session.id;
    if (now != opened.sessionId && now != server.id) return;
    // The server answered before the sets behind the opening went out: what the screen shows of them stays.
    final shownRecords = state.live?.records ?? const <SetRecord>[];
    final kept = [
      for (final r in shownRecords)
        if (!opened.live.records.any((o) => sameSet(o, r)))
          SetRecord.fromJson({...r.toJson(), 'sesionId': server.id}),
    ];
    final live = _withUnsent(
      LiveSession(session: server, records: [...opened.live.records, ...kept]),
      unsent,
    );
    _follow(server);
    ref.invalidate(cycleDayStatesProvider);
    state = _with(live: live, liveStatus: _sync?.status);
  }

  /// The server took a write of the guided pass (E7.26): the screen takes the session it answered before the write
  /// leaves the queue, so the pass on screen never steps back.
  void _onGuidedStored(Session session) {
    final live = state.live;
    if (live == null) return;
    final queue = ref.read(setSyncQueueProvider);
    if (queue.currentIdOf(live.session.id) != session.id) return;
    state = _with(
      live: applyChanges(live, [
        SessionChange.ofSession(session.lastSessionChange, session),
      ]),
    );
  }

  static LiveSession _withUnsent(LiveSession live, List<SetWrite> unsent) =>
      unsent.fold<LiveSession>(
        live,
        (l, w) => _replacing(
          l,
          projectedRecord(
            _recordOf(l, w),
            w,
            clubId: l.session.clubId,
            sessionId: l.session.id,
          ),
        ),
      );

  /// Choosing another week goes to its first day, as the calendar does.
  void selectWeek(int week) => selectDay(week, 1);

  /// Choosing another day only shows it: the session on screen stops being followed (nothing open is lost, every
  /// write is already queued) and the new day is looked up. The athlete tab stays; the adjustments are the day's.
  void selectDay(int week, int day) {
    _stopFollowing();
    state = SessionScreenState(
      week: week,
      day: day,
      athleteId: state.athleteId,
    );
    unawaited(_lookUp());
  }

  /// Choosing another of today's plans (E8.8) only shows it, like choosing another day: the session on screen stops
  /// being followed and the new plan's day is looked up. Day, tab and adjustments start over: they are the plan's.
  void selectPlan(String assignmentId) {
    _stopFollowing();
    _data = ref
        .read(sessionDaysProvider)
        .value
        ?.where((d) => d.location.assignmentId == assignmentId)
        .firstOrNull;
    state = const SessionScreenState();
    ref.read(chosenPlanProvider.notifier).choose(assignmentId);
    unawaited(_lookUp());
  }

  /// Follows the live channel of [session] (E7.10) unless it already does. Every time the channel opens, the queue
  /// goes out again; every change that arrives is applied to the screen.
  /// A session opened on the device has no channel yet: it follows once the server takes its opening.
  void _follow(Session session) {
    if (_sync?.sessionId == session.id) return;
    _stopFollowing();
    if (isLocalSessionId(session.id)) return;
    final queue = ref.read(setSyncQueueProvider);
    final sync = _sync = LiveSessionSync(
      channel: ref.read(liveChannelProvider),
      clubId: session.clubId,
      sessionId: session.id,
      since: session.sequence,
      onChanges: _receive,
      onConnected: () => queue.flush().ignore(),
      isFinal: (e) => e is ErrorDeApi && (e.estado == 403 || e.estado == 404),
      backoff: ref.read(liveReconnectBackoffProvider),
    );
    _statusSubscription = sync.statusChanges.listen(
      (s) => state = _with(liveStatus: s),
    );
    _queueSubscription = queue.changes.listen((_) => _releaseHeldBack());
    sync.start();
  }

  void _stopFollowing() {
    _statusSubscription?.cancel();
    _queueSubscription?.cancel();
    _statusSubscription = null;
    _queueSubscription = null;
    _heldBack.clear();
    final sync = _sync;
    _sync = null;
    if (sync != null) unawaited(sync.stop());
  }

  static SetKey _keyOf(SetRecord r) => (
    sessionId: r.sessionId,
    athleteId: r.athleteId,
    blockIndex: r.blockIndex,
    prescriptionIndex: r.prescriptionIndex,
    setIndex: r.setIndex,
  );

  Set<SetKey> get _queuedSets => {
    for (final p in ref.read(setSyncQueueProvider).pending) p.key,
  };

  void _receive(List<SessionChange> changes) {
    final live = state.live;
    if (live == null) return;
    // The copy takes every change at once: it is the server's state, and what is queued goes over it on reopening.
    unawaited(
      ref
          .read(sessionCopyProvider)
          ?.applyChanges(live.session.clubId, live.session.id, changes),
    );
    final queued = _queuedSets;
    final now = <SessionChange>[];
    for (final c in changes) {
      final record = c.record;
      if (record != null && queued.contains(_keyOf(record))) {
        final key = _keyOf(record);
        final held = _heldBack[key];
        if (held == null || held.sequence <= c.sequence) _heldBack[key] = c;
      } else {
        now.add(c);
      }
    }
    _apply(now);
  }

  void _releaseHeldBack() {
    if (_heldBack.isEmpty) return;
    final queued = _queuedSets;
    final ready = [
      for (final e in _heldBack.entries)
        if (!queued.contains(e.key)) e.value,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    _heldBack.removeWhere((k, _) => !queued.contains(k));
    _apply(ready);
  }

  void _apply(List<SessionChange> changes) {
    final live = state.live;
    if (live == null || changes.isEmpty) return;
    final next = applyChanges(live, changes);
    // The day pills follow a set another device marks or unmarks.
    if (!_sameDone(live.records, next.records)) {
      ref.invalidate(cycleDayStatesProvider);
    }
    state = _with(live: next);
  }

  static bool _sameDone(List<SetRecord> a, List<SetRecord> b) {
    Set<SetKey> done(List<SetRecord> rs) => {
      for (final r in rs)
        if (r.done) _keyOf(r),
    };
    final before = done(a);
    final after = done(b);
    return before.length == after.length && before.containsAll(after);
  }

  /// Makes sure the chosen day's session exists with [athleteIds] present before writing for them (E7.27): opens it
  /// with them when it does not exist, or opens it again adding the ones missing. The opening adds, never removes,
  /// and works without signal (E7.16). Calls are taken one after the other, so two quick writes open once. Returns
  /// the session, or null without a day on screen. Rethrows the backend's error so the screen can show it.
  Future<LiveSession?> ensureSession(
    SessionDayData data,
    Set<String> athleteIds,
  ) {
    _data ??= data;
    final next = _ensuring.then((_) => _ensureNow(data, athleteIds));
    _ensuring = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<LiveSession?> _ensure(Set<String> athleteIds) async {
    final data = _dayData;
    return data == null ? null : ensureSession(data, athleteIds);
  }

  Future<LiveSession?> _ensureNow(
    SessionDayData data,
    Set<String> athleteIds,
  ) async {
    final live = state.live;
    final present = live?.session.presentAthleteIds ?? const <String>[];
    if (live != null && athleteIds.every(present.contains)) return live;
    final shown = shownDayOf(data, state);
    // A session on screen is opened again on its own date: it may be the one of a day done on an earlier date.
    await _open(
      data,
      date: live?.session.date ?? ref.read(todayProvider),
      week: shown.week,
      day: shown.day,
      present: {...present, ...athleteIds},
    );
    return state.live;
  }

  Future<void> _open(
    SessionDayData data, {
    required DateTime date,
    required int week,
    required int day,
    required Set<String> present,
  }) async {
    state = _with(opening: true);
    try {
      final queue = ref.read(setSyncQueueProvider);
      final opened =
          await OpenDaySession(
            sessions: ref.read(sessionRepositoryProvider),
            queue: queue,
            copy: ref.read(sessionCopyProvider),
            userId: data.userId,
          )(
            DayToOpen(
              clubId: data.clubId,
              assignmentId: data.location.assignmentId,
              planId: data.location.planId,
              cycle: data.location.cycle,
              date: date,
              week: week,
              day: day,
            ),
            present,
          );
      // Its opening may have gone through while this was reading.
      final id = queue.currentIdOf(opened.session.id);
      final live = id == opened.session.id
          ? opened
          : await ref
                .read(sessionRepositoryProvider)
                .open(
                  data.clubId,
                  assignmentId: data.location.assignmentId,
                  date: date,
                  week: week,
                  day: day,
                  presentAthleteIds: present,
                );
      final unsent = await queue.resume(live.session.id);
      // The user may have gone to another day meanwhile: what was opened stays opened, but is not shown.
      if (!ref.mounted || shownDayOf(data, state) != (week: week, day: day)) {
        return;
      }
      _follow(live.session);
      state = _with(
        liveStatus: _sync?.status ?? LiveStatus.connecting,
        live: _withUnsent(live, unsent),
      );
    } finally {
      if (ref.mounted) state = _with(opening: false);
    }
  }

  /// Writes one set through the draft and queue and keeps what the server stored, or what the write leaves while it
  /// stays queued without signal. Rethrows the backend's refusal so the screen can show it.
  /// The session is created first if it does not exist, with the set's athlete present.
  Future<void> writeSet(String clubId, SetWrite write) async {
    await _ensure({write.athleteId});
    final shownId = state.live?.session.id;
    if (shownId == null) return;
    final queue = ref.read(setSyncQueueProvider);
    final stored = await queue.submit(
      clubId: clubId,
      sessionId: shownId,
      write: write,
    );
    final live = state.live;
    ref.invalidate(cycleDayStatesProvider);
    // A session opened on the device may have taken the server's id meanwhile.
    final sessionId = live?.session.id;
    if (live == null ||
        sessionId == null ||
        queue.currentIdOf(shownId) != queue.currentIdOf(sessionId)) {
      return;
    }
    final current = _recordOf(live, write);
    // A newer change of this set may have arrived from another device meanwhile.
    if (stored != null && current != null && !isNewer(stored, current)) return;
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
            if (!sameSet(r, record)) r,
          record,
        ],
      );

  /// Writes the session's note, creating the session first with [athleteId] (the tab on screen) present. Rethrows the
  /// backend's error so the screen can show it.
  Future<void> saveSessionNote(
    String clubId,
    String note, {
    required String athleteId,
  }) async {
    await _ensure({athleteId});
    final sessionId = state.live?.session.id;
    if (sessionId == null) return;
    final session = await ref
        .read(sessionRepositoryProvider)
        .saveSessionNote(clubId, sessionId, note);
    final live = state.live;
    if (live == null || live.session.id != sessionId) return;
    state = _with(
      live: applyChanges(live, [
        SessionChange.ofSession(session.lastSessionChange, session),
      ]),
    );
  }

  void selectAthlete(String athleteId) => state = _with(athleteId: athleteId);

  /// Moves the day adjustment of [athleteId]. Adjusted kilos are computed by the server within a session (the factor
  /// never reaches the athlete), so a change creates the session with that athlete present (E7.27). If that fails,
  /// the adjustment goes back and the error is rethrown.
  Future<void> stepSessionAdjustment(String athleteId, int delta) =>
      _updateAdjustments(athleteId, (a) => a.stepSession(delta));

  Future<void> stepExerciseAdjustment(
    String athleteId,
    String exerciseId,
    int delta,
  ) => _updateAdjustments(athleteId, (a) => a.stepExercise(exerciseId, delta));

  Future<void> _updateAdjustments(
    String athleteId,
    AthleteAdjustments Function(AthleteAdjustments) update,
  ) async {
    final before = state.adjustmentsOf(athleteId);
    final after = update(before);
    if (after == before) return;
    _setAdjustments(athleteId, after);
    try {
      await _ensure({athleteId});
    } catch (_) {
      if (ref.mounted && state.adjustmentsOf(athleteId) == after) {
        _setAdjustments(athleteId, before);
      }
      rethrow;
    }
  }

  void _setAdjustments(String athleteId, AthleteAdjustments value) =>
      state = SessionScreenState(
        week: state.week,
        day: state.day,
        live: state.live,
        athleteId: state.athleteId,
        adjustments: {...state.adjustments, athleteId: value},
        opening: state.opening,
        liveStatus: state.liveStatus,
      );

  SessionScreenState _with({
    bool? opening,
    String? athleteId,
    LiveSession? live,
    LiveStatus? liveStatus,
  }) => SessionScreenState(
    week: state.week,
    day: state.day,
    live: live ?? state.live,
    athleteId: athleteId ?? state.athleteId,
    adjustments: state.adjustments,
    opening: opening ?? state.opening,
    liveStatus: liveStatus ?? state.liveStatus,
  );
}

final sessionScreenProvider =
    NotifierProvider.autoDispose<SessionScreenController, SessionScreenState>(
      SessionScreenController.new,
    );

/// The athlete tab on screen: the chosen one, else the user if they are in the group, else the group's first. Null
/// for a group without athletes.
String? athleteOnScreen(SessionDayData data, SessionScreenState state) {
  final chosen = state.athleteId;
  if (chosen != null && data.memberIds.contains(chosen)) return chosen;
  return defaultAthleteOf(data.memberIds, data.ownAthleteId);
}

/// The athlete tab shown before choosing one: the user if they are among [memberIds], else the first. Null without
/// athletes.
String? defaultAthleteOf(List<String> memberIds, String? ownAthleteId) =>
    memberIds.contains(ownAthleteId) ? ownAthleteId : memberIds.firstOrNull;

/// The date whose proposed kilos (E7.14) stand for [week] of the cycle on screen: today in today's week, else the
/// first date of that week of the cycle.
DateTime proposedDateOf(SessionDayData data, int week, DateTime today) {
  if (week == data.location.week) return today;
  final (start, _) = cycleDates(data.location.startDate, data.location.cycle);
  return start.add(Duration(days: (week - 1) * 7));
}

/// The guided mode's clock. Tests override it.
final guidedClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Ids of new guided passes (E7.26): unique enough for the passes of one session, and valid as part of a block time's
/// id. Tests override it.
final guidedPassIdProvider = Provider<String Function()>((ref) {
  final random = Random();
  return () =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${random.nextInt(0x7fffffff).toRadixString(36)}';
});

/// The guided mode over the day's session (E7.20): the pure [GuidedSession], fed with the session's records and its
/// guided pass, and the writes it leads to. Null without a plan day on screen. Until "Comenzar" it needs no session
/// (E7.27): choosing who trains writes nothing, and "Comenzar" creates the session with them.
///
/// Since E7.26 the pass is the session's, the same on every device: each action is applied on screen at once and goes
/// to the queue (E7.9) behind the sets; what other devices do arrives with the session over the live channel. What is
/// shown is the server's pass with this device's unsent actions applied over it, so nothing steps back while they
/// travel. Leaving the screen keeps the pass for everyone; only the athletes being chosen and the step's draft are
/// dropped.
class GuidedController extends Notifier<GuidedSession?> {
  /// Actions applied on screen that have not reached the queue yet.
  final _unqueued = <GuidedPassAction>[];
  Future<void> _submitting = Future.value();

  @override
  GuidedSession? build() {
    ref.listen(
      sessionScreenProvider.select((s) => s.live?.session),
      (_, _) => _refresh(),
    );
    // A set another device marks, or one this device wrote, may close the block.
    ref.listen(
      sessionScreenProvider.select((s) => s.live?.records),
      (_, _) => _settle(),
    );
    final queue = ref.read(setSyncQueueProvider);
    final subscription = queue.changes.listen((_) => _refresh());
    ref.onDispose(subscription.cancel);
    final data = ref.read(sessionDayProvider).value;
    final screen = ref.read(sessionScreenProvider);
    if (data == null) return null;
    final live = screen.live;
    final shown = live == null
        ? shownDayOf(data, screen)
        : (week: live.session.week, day: live.session.day);
    final day = planDayOf(data, shown.week, shown.day);
    if (day == null) return null;
    final athlete = athleteOnScreen(data, screen);
    return GuidedSession.entering(day, _shownPass(live), [?athlete]);
  }

  LiveSession? get _live => ref.read(sessionScreenProvider).live;

  /// The done sets of the session, wherever they were marked.
  Set<BlockSet> get recorded => recordedSets(_live?.records ?? const []);

  DateTime get _now => ref.read(guidedClockProvider)();

  /// The server's pass of [live] with what this device has not sent yet applied over it.
  GuidedPass? _shownPass([LiveSession? live]) {
    live ??= _live;
    if (live == null) return null;
    final queue = ref.read(setSyncQueueProvider);
    final id = queue.currentIdOf(live.session.id);
    final unsent = [
      for (final p in queue.pendingGuided)
        if (queue.currentIdOf(p.sessionId) == id) p.action,
      ..._unqueued,
    ];
    return unsent.fold(live.session.guidedPass, applyGuidedAction);
  }

  void _refresh() {
    final s = state;
    if (s != null) state = s.withPass(_shownPass());
  }

  void _settle() {
    final s = state;
    if (s != null) _dispatch(s.settleActions(recorded, now: _now));
  }

  /// Applies [actions] on screen at once and queues them, in order, for the server. For each block they close as done
  /// or interrupted on this device (a skipped one leaves no time), queues the block's time (E7.21) under the pass's id
  /// for it, so a block that two devices close at once still has one time.
  void _dispatch(List<GuidedPassAction> actions, {bool clearDraft = false}) {
    final s = state;
    final live = _live;
    if (s == null || live == null) return;
    if (actions.isEmpty) {
      if (clearDraft) state = s.clearingDraft();
      return;
    }
    final next = s.applying(actions);
    state = clearDraft ? next.clearingDraft() : next;
    _queueTimes(s, next);
    _unqueued.addAll(actions);
    final queue = ref.read(setSyncQueueProvider);
    final clubId = live.session.clubId;
    final sessionId = live.session.id;
    _submitting = _submitting.then((_) async {
      for (final a in actions) {
        try {
          await queue.submitGuided(
            clubId: clubId,
            sessionId: sessionId,
            action: a,
          );
        } catch (_) {
          // Without local storage the write still goes out from memory.
        }
        _unqueued.remove(a);
      }
    });
  }

  void _queueTimes(GuidedSession previous, GuidedSession next) {
    final pass = next.pass;
    if (pass == null || previous.pass?.id != pass.id) return;
    bool timed(GuidedBlockRun r) =>
        r.status == GuidedBlockStatus.done ||
        r.status == GuidedBlockStatus.interrupted;
    for (var i = 0; i < next.runs.length && i < previous.runs.length; i++) {
      final run = next.runs[i];
      if (timed(run) && !timed(previous.runs[i])) _queueTime(next, run);
    }
  }

  void _queueTime(GuidedSession guided, GuidedBlockRun run) {
    final live = _live;
    final start = run.start;
    final end = run.end;
    if (live == null || start == null || end == null) return;
    if (run.blockIndex >= guided.day.blocks.length) return;
    final block = guided.day.blocks[run.blockIndex];
    unawaited(
      ref
          .read(setSyncQueueProvider)
          .submitBlockTime(
            clubId: live.session.clubId,
            sessionId: live.session.id,
            id: blockTimeIdOf(guided.pass!.id, run.blockIndex),
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

  void _update(GuidedSession Function(GuidedSession) change) {
    final s = state;
    if (s != null) state = change(s);
  }

  void toggleAthlete(String athleteId) =>
      _update((s) => s.toggleAthlete(athleteId));

  /// Whether any chosen athlete already has sets done on this day, which makes "Comenzar" ask (E7.23).
  bool get chosenHaveRecords {
    final s = state;
    return s != null && recordedOfAthletes(recorded, s.athleteIds).isNotEmpty;
  }

  /// "Comenzar". Creates the day's session with the chosen athletes, or adds the ones not present yet, since only
  /// present athletes record sets (E7.27). With [redo] every set is walked again and finishing one overwrites its
  /// record (E7.23); nothing is unmarked. A pass another device began meanwhile is joined instead. Rethrows the
  /// backend's error so the screen can show it.
  Future<void> begin({bool redo = false}) async {
    final s = state;
    final data = ref.read(sessionDayProvider).value;
    if (s == null || data == null) return;
    await ref
        .read(sessionScreenProvider.notifier)
        .ensureSession(data, s.athleteIds.toSet());
    final now = state;
    if (now == null || _live == null) return;
    _dispatch(
      now.beginActions(
        passId: ref.read(guidedPassIdProvider)(),
        now: _now,
        redo: redo,
      ),
    );
  }

  /// "Empezar de nuevo": back to choosing who trains, for a pass that replaces this one. The pass goes on for everyone
  /// until "Comenzar".
  void startOver() => _update((s) => s.startingOver());

  /// Leaves "Empezar de nuevo" without writing anything: back to the pass going on.
  void resume() => _update((s) => s.resuming());

  /// "Terminar el día": the pass closes for every device, which all go to the summary.
  void finishDay() => _dispatch(state?.finishDayActions(now: _now) ?? const []);

  void setAthleteMode(AthleteMode mode) =>
      _dispatch(state?.athleteModeActions(mode, now: _now) ?? const []);

  void setExecutionMode(ExecutionMode mode) =>
      _dispatch(state?.executionModeActions(mode, now: _now) ?? const []);

  void startBlock() =>
      _dispatch(state?.startBlockActions(recorded, now: _now) ?? const []);

  void skipBlock() => _dispatch(state?.skipBlockActions(now: _now) ?? const []);

  void interruptBlock() =>
      _dispatch(state?.interruptBlockActions(now: _now) ?? const []);

  void startStep() => _update((s) => s.startStep(recorded));

  void toggleNotDone(String athleteId) =>
      _update((s) => s.toggleNotDone(athleteId, recorded));

  void edit(String athleteId, SetEdit edit) =>
      _update((s) => s.edit(athleteId, edit, recorded));

  void leaveExercise(String athleteId) => _dispatch(
    state?.leaveExerciseActions(athleteId, recorded, now: _now) ?? const [],
  );

  void skipExercise() => _dispatch(
    state?.skipExerciseActions(recorded, now: _now) ?? const [],
    clearDraft: true,
  );

  /// "Terminar serie": moves on at once and writes each athlete's set with what their card shows. The sets go to the
  /// queue ahead of the pass. Rethrows the backend's refusal so the screen can show it.
  Future<void> finishStep() async {
    final s = state;
    final done = recorded;
    final run = s?.run;
    final step = s?.currentStep(done);
    if (s == null || run == null || step == null) return;
    final draft = s.draftFor(step);
    final result = s.finishStepActions(done, now: _now);
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
    final sending = _send(writes);
    _dispatch(result.actions, clearDraft: true);
    await sending;
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
            if (s.redo ||
                !done.contains((run.blockIndex, AthleteSet(a, p, set))))
              _markWrite(block, run.blockIndex, p, set, a, null),
    ];
    final sending = _send(writes);
    _dispatch(s.finishBlockActions(now: _now));
    await sending;
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
    final redo = state?.redo ?? false;
    final current = redo
        ? null // a redone set starts from the proposal, not from what was recorded before
        : screen.live?.records
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

/// The proposed kilos of one athlete on one day without a session (E7.14), by the date that stands for its week.
typedef DayLoadsQuery = ({
  String clubId,
  String assignmentId,
  DateTime date,
  int cycle,
  int week,
  int day,
  String athleteId,
});

/// The kilos of a day before its session exists, or of an athlete not present in it, from the proposed kilos by
/// date (E7.14) with the neutral adjustment, which is the one in force while nobody touched it. Without signal, those
/// the preload saved (E7.15), from the nearest saved date of that week if need be. Empty when the server gives no
/// kilos for that athlete or date.
final dayLoadsProvider = FutureProvider.autoDispose
    .family<List<ProposedSet>, DayLoadsQuery>((ref, q) async {
      final repository = ref.watch(proposedDaysRepositoryProvider);
      try {
        final dates = await repository.proposedDays(
          q.clubId,
          q.assignmentId,
          q.date,
          q.date,
        );
        return dates
                .where((d) => d.cycle == q.cycle && d.week == q.week)
                .firstOrNull
                ?.setsOf(q.day, q.athleteId) ??
            const [];
      } on NoLocalCopy {
        // Without signal and nothing saved for that date: another saved date of the same week may have them.
      }
      final saved = await repository.savedSets(
        q.clubId,
        q.assignmentId,
        date: q.date,
        cycle: q.cycle,
        week: q.week,
        day: q.day,
        athleteId: q.athleteId,
      );
      if (saved == null) throw const NoLocalCopy(noDayLoadsMessage);
      return saved;
    });

const noDayLoadsMessage =
    'Sin señal y sin kilos guardados para este día. Se cargan cuando vuelva la señal.';

final proposedLoadsProvider = FutureProvider.autoDispose
    .family<List<ProposedSet>, ProposedLoadsQuery>(
      (ref, q) => ref
          .watch(sessionRepositoryProvider)
          .proposedLoads(q.clubId, q.sessionId, q.athleteId, q.adjustments),
    );

/// "Plan propio" when the plan is the user's alone, else the athletes' names when known, else how many they are.
String _ownerLabel(
  List<String> ids,
  Map<String, String> names,
  String? ownAthleteId,
) {
  if (ids.length == 1 && ids.single == ownAthleteId) return 'Plan propio';
  if (ids.isNotEmpty && ids.every(names.containsKey)) {
    return ids.map((id) => names[id]).join(', ');
  }
  return ids.length == 1 ? '1 atleta' : '${ids.length} atletas';
}
