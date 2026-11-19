import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/api_providers.dart';
import '../../catalogo/presentation/providers.dart' show catalogClubIdProvider;
import '../data/http_quick_timers_repository.dart';
import '../domain/quick_timers_repository.dart';

final quickTimersRepositoryProvider = Provider<QuickTimersRepository>(
  (ref) => HttpQuickTimersRepository(ref.watch(clienteApiProvider)),
);

/// The ids of the timers the user keeps at hand in the active club, in the order they chose them.
final quickTimerIdsProvider = FutureProvider<List<String>>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return const [];
  return ref.watch(quickTimersRepositoryProvider).ids(clubId);
});

/// Adds [timerId] to the timers at hand (at the end) or takes it out, and refreshes the list. Errors propagate.
Future<void> setQuickTimer(WidgetRef ref, String timerId, {required bool atHand}) async {
  final clubId = ref.read(catalogClubIdProvider);
  if (clubId == null) return;
  final current = await ref.read(quickTimerIdsProvider.future);
  final next = [
    for (final id in current)
      if (id != timerId) id,
    if (atHand) timerId,
  ];
  await ref.read(quickTimersRepositoryProvider).save(clubId, next);
  ref.invalidate(quickTimerIdsProvider);
}
