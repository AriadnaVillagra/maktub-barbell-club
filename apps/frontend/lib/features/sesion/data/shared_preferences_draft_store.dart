import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/session_draft_store.dart';

/// Keeps the session's draft and queue with `shared_preferences`: `localStorage` in the PWA.
///
/// Chosen in E7.9 over IndexedDB: the app already depends on it (E1.12), the data is a few kilobytes (one entry per
/// set written during the day), and it reads back whole on start. Every access is guarded, so a browser that blocks
/// storage (private mode, cleared site data) leaves the app working without the draft.
class SharedPreferencesDraftStore implements SessionDraftStore {
  SharedPreferencesDraftStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.sessionDraft';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<DraftSnapshot> load() async {
    try {
      final raw = (await _preferences()).getString(key);
      if (raw == null) return const DraftSnapshot();
      return DraftSnapshot.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const DraftSnapshot();
    }
  }

  @override
  Future<void> save(DraftSnapshot snapshot) async {
    try {
      await (await _preferences()).setString(
        key,
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {
      // Without storage the draft lives only in memory.
    }
  }
}

/// Whether a failed set write is worth sending again later: no connection, the server down or starting, or the
/// session needing a new token. Anything the server refused on purpose (a 4xx) would be refused again.
bool isTransientWriteError(Object error) {
  if (error is! ErrorDeApi) return false;
  final status = error.estado;
  return status == null ||
      status >= 500 ||
      status == 401 ||
      status == 408 ||
      status == 429;
}
