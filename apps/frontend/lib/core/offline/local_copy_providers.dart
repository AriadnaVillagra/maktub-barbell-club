import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_copy.dart';
import 'shared_preferences_local_copy_store.dart';

/// The device's copy of the day's reads (E7.15). Tests replace it, or give `shared_preferences` mock values.
final localCopyStoreProvider = Provider<LocalCopyStore>(
  (ref) => SharedPreferencesLocalCopyStore(),
);

/// Since when the screens show saved data instead of the server's: the oldest copy served since the last read that
/// reached the server, or null while reads reach it.
class LocalCopyNoticeController extends Notifier<DateTime?>
    implements LocalCopyReporter {
  @override
  DateTime? build() => null;

  @override
  void servedFresh() {
    if (state != null) state = null;
  }

  @override
  void servedFromCopy(DateTime savedAt) {
    final current = state;
    if (current == null || savedAt.isBefore(current)) state = savedAt;
  }
}

final localCopyNoticeProvider =
    NotifierProvider<LocalCopyNoticeController, DateTime?>(
      LocalCopyNoticeController.new,
    );

/// Reads through the network with the copy as fallback, for the cached repositories of each feature.
final localCopyReadsProvider = Provider<LocalCopyReads>(
  (ref) => LocalCopyReads(
    ref.watch(localCopyStoreProvider),
    ref.read(localCopyNoticeProvider.notifier),
  ),
);
