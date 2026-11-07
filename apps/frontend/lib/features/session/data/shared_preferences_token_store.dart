import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/session_repositories.dart';

/// Saves the tokens with `shared_preferences`: `localStorage` in the PWA.
///
/// Chosen in E1.12. On the web there is no truly secret storage (secure-storage packages also end
/// up in `localStorage`), cookies are ruled out because the app and the API live on different sites,
/// and the tokens have to survive closing the tab so the installed PWA stays logged in.
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.session';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<IssuedSession?> read() async {
    final prefs = await _preferences();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return IssuedSession.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } on Object {
      await prefs.remove(key); // unreadable: same as no session
      return null;
    }
  }

  @override
  Future<void> write(IssuedSession session) async {
    final prefs = await _preferences();
    await prefs.setString(key, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await _preferences();
    await prefs.remove(key);
  }
}
