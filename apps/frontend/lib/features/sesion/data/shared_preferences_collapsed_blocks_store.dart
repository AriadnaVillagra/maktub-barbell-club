import 'package:shared_preferences/shared_preferences.dart';

import '../domain/collapsed_blocks.dart';

/// Keeps the collapsed block cards with `shared_preferences`: `localStorage` in the PWA. A browser that blocks
/// storage leaves every card expanded.
class SharedPreferencesCollapsedBlocksStore implements CollapsedBlocksStore {
  SharedPreferencesCollapsedBlocksStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.collapsedBlocks';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<Set<int>> load() async {
    try {
      final saved = (await _preferences()).getStringList(key) ?? const [];
      return {for (final s in saved) ?int.tryParse(s)};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Set<int> collapsed) async {
    try {
      await (await _preferences()).setStringList(key, [
        for (final i in collapsed) '$i',
      ]);
    } catch (_) {
      // Not remembered on this device; the cards still change.
    }
  }
}
