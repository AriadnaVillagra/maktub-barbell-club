import 'package:shared_preferences/shared_preferences.dart';

import '../domain/calendar_layout.dart';

/// Keeps the chosen calendar layout with `shared_preferences`: `localStorage` in the PWA. A browser that blocks
/// storage leaves the default layout.
class SharedPreferencesCalendarLayoutStore implements CalendarLayoutStore {
  SharedPreferencesCalendarLayoutStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.calendarLayout';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<CalendarLayout?> load() async {
    try {
      final name = (await _preferences()).getString(key);
      return CalendarLayout.values.where((l) => l.name == name).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CalendarLayout layout) async {
    try {
      await (await _preferences()).setString(key, layout.name);
    } catch (_) {
      // Not remembered on this device; the layout still changes.
    }
  }
}
