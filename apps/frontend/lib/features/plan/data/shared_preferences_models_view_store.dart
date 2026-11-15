import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models_view.dart';

/// Keeps the chosen view of the week models with `shared_preferences`: `localStorage` in the PWA. A browser
/// that blocks storage leaves the default view.
class SharedPreferencesModelsViewStore implements ModelsViewStore {
  SharedPreferencesModelsViewStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.planModelsView';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<ModelsView?> load() async {
    try {
      final name = (await _preferences()).getString(key);
      return ModelsView.values.where((v) => v.name == name).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(ModelsView view) async {
    try {
      await (await _preferences()).setString(key, view.name);
    } catch (_) {
      // Not remembered on this device; the view still changes.
    }
  }
}
