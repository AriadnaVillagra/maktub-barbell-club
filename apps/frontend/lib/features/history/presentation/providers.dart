import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../data/http_history_repository.dart';
import '../domain/history_repository.dart';

/// Tests replace it with a fake.
final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HttpHistoryRepository(ref.watch(clienteApiProvider)),
);

Future<String?> _clubId(Ref ref) =>
    ref.watch(meProvider.future).then((me) => me?.activeClub?.club.id);

/// The pages of an athlete's history loaded so far.
class HistoryListState {
  const HistoryListState({
    this.entries = const [],
    this.next,
    this.loadingMore = false,
    this.moreError,
  });

  /// Newest first.
  final List<HistoryEntry> entries;

  /// The `antesDe` of the next page; null when everything is loaded.
  final DateTime? next;
  final bool loadingMore;

  /// Why the last "Cargar más" failed, if it did.
  final Object? moreError;

  bool get hasMore => next != null;

  HistoryListState copyWith({
    List<HistoryEntry>? entries,
    DateTime? next,
    bool clearNext = false,
    bool? loadingMore,
    Object? moreError,
  }) => HistoryListState(
    entries: entries ?? this.entries,
    next: clearNext ? null : (next ?? this.next),
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: moreError,
  );
}

/// An athlete's history by athlete id: the first page on build, older ones with [HistoryList.loadMore].
final historyListProvider =
    AsyncNotifierProvider.family<HistoryList, HistoryListState, String>(
      HistoryList.new,
    );

class HistoryList extends AsyncNotifier<HistoryListState> {
  HistoryList(this.athleteId);

  final String athleteId;

  @override
  Future<HistoryListState> build() async {
    final clubId = await _clubId(ref);
    if (clubId == null) return const HistoryListState();
    final page = await ref
        .watch(historyRepositoryProvider)
        .page(clubId, athleteId);
    return HistoryListState(entries: page.entries, next: page.next);
  }

  /// Appends the next page. Does nothing while one loads or when everything is loaded; a failure stays in
  /// [HistoryListState.moreError] and keeps what was loaded.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
      if (clubId == null) {
        state = AsyncData(current);
        return;
      }
      final page = await ref
          .read(historyRepositoryProvider)
          .page(clubId, athleteId, before: current.next);
      final known = {for (final e in current.entries) e.sessionId};
      state = AsyncData(
        current.copyWith(
          entries: [
            ...current.entries,
            for (final e in page.entries)
              if (!known.contains(e.sessionId)) e,
          ],
          next: page.next,
          clearNext: page.next == null,
          loadingMore: false,
        ),
      );
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, moreError: e));
    }
  }
}

/// One session of an athlete's history.
final sessionHistoryProvider =
    FutureProvider.family<
      SessionHistory,
      ({String athleteId, String sessionId})
    >((ref, key) async {
      final clubId = await _clubId(ref);
      if (clubId == null) throw StateError('Sin club activo.');
      return ref
          .watch(historyRepositoryProvider)
          .session(clubId, key.athleteId, key.sessionId);
    });
