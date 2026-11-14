import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_copy.dart';

/// Keeps the day's copy with `shared_preferences` (`localStorage` in the PWA), one entry per read.
///
/// Same storage as the draft (E7.9): today plus seven days of one group is a few hundred kilobytes at most (the
/// proposed kilos are the biggest part), well under the browser's quota, and old entries are pruned on every
/// preload. Every access is guarded, so a browser that blocks storage leaves the app working as without a copy.
class SharedPreferencesLocalCopyStore implements LocalCopyStore {
  SharedPreferencesLocalCopyStore({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  static const prefix = 'maktub.copy.';

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;

  @override
  Future<LocalCopy?> read(String key) async {
    try {
      final raw = (await _preferences()).getString('$prefix$key');
      if (raw == null) return null;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return LocalCopy(savedAt: DateTime.parse('${j['t']}'), data: j['d']);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? data) async {
    try {
      await (await _preferences()).setString(
        '$prefix$key',
        jsonEncode({'t': _now().toUtc().toIso8601String(), 'd': data}),
      );
    } catch (_) {
      // Without storage (or over its quota) there is no copy; the read already succeeded.
    }
  }

  @override
  Future<List<String>> keys(String keyPrefix) async {
    try {
      final all = (await _preferences()).getKeys();
      return [
        for (final k in all)
          if (k.startsWith('$prefix$keyPrefix')) k.substring(prefix.length),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> prune(DateTime before) async {
    try {
      final prefs = await _preferences();
      for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        final copy = await read(k.substring(prefix.length));
        if (copy == null || copy.savedAt.isBefore(before)) await prefs.remove(k);
      }
    } catch (_) {
      // Nothing to prune without storage.
    }
  }
}
