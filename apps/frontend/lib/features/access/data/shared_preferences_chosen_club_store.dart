import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chosen_club_store.dart';

/// Keeps the picked club with `shared_preferences` (`localStorage` in the PWA), together with who picked it, so
/// another user signing in on the same device starts in their own default club. Every access is guarded: without
/// storage the app works in the default club.
class SharedPreferencesChosenClubStore implements ChosenClubStore {
  SharedPreferencesChosenClubStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.chosenClub';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<Club?> read(String userId) async {
    try {
      final raw = (await _preferences()).getString(key);
      if (raw == null) return null;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (j['userId'] != userId) return null;
      return Club.fromJson((j['club'] as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String userId, Club? club) async {
    try {
      final preferences = await _preferences();
      if (club == null) {
        await preferences.remove(key);
      } else {
        await preferences.setString(key, jsonEncode({'userId': userId, 'club': club.toJson()}));
      }
    } catch (_) {
      // Without storage the pick lasts until the app reloads `GET /me`.
    }
  }
}
