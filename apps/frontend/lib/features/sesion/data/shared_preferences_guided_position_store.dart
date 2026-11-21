import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/guided_position.dart';
import '../domain/guided_session.dart';

/// Keeps the guided mode's position with `shared_preferences`: `localStorage` in the PWA, so it survives a reload. A
/// browser that blocks storage keeps it only while the app is open.
class SharedPreferencesGuidedPositionStore implements GuidedPositionStore {
  SharedPreferencesGuidedPositionStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'maktub.guidedPosition';

  final Future<SharedPreferences> Function() _preferences;

  /// What was written last, so an unchanged position is not written again on every refresh of the pass.
  String? _written;

  @override
  Future<GuidedPosition?> load() async {
    try {
      final raw = (await _preferences()).getString(key);
      if (raw == null) return null;
      _written = raw;
      return guidedPositionFromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(GuidedPosition? position) async {
    try {
      final raw = position == null
          ? null
          : jsonEncode(guidedPositionToJson(position));
      if (raw == _written) return;
      _written = raw;
      final preferences = await _preferences();
      if (raw == null) {
        await preferences.remove(key);
      } else {
        await preferences.setString(key, raw);
      }
    } catch (_) {
      // Not remembered across a reload on this device; it still is while the app is open.
    }
  }
}

Map<String, dynamic> guidedPositionToJson(GuidedPosition p) => {
  'sessionId': p.sessionId,
  'passId': p.passId,
  'block': p.block,
  if (p.draft case final d?) 'draft': _draftToJson(d),
  if (p.reviewing case final s?)
    'reviewing': {
      'prescription': s.prescription,
      'set': s.set,
      'athleteIds': s.athleteIds,
    },
  if (p.reviewDraft case final d?) 'reviewDraft': _draftToJson(d),
};

GuidedPosition guidedPositionFromJson(Map<String, dynamic> json) {
  final reviewing = (json['reviewing'] as Map?)?.cast<String, dynamic>();
  return GuidedPosition(
    sessionId: json['sessionId'] as String,
    passId: json['passId'] as String,
    block: json['block'] as int,
    draft: _draftFromJson(json['draft']),
    reviewing: reviewing == null
        ? null
        : GuidedStep(
            prescription: reviewing['prescription'] as int,
            set: reviewing['set'] as int,
            athleteIds: List.unmodifiable(
              (reviewing['athleteIds'] as List).cast<String>(),
            ),
          ),
    reviewDraft: _draftFromJson(json['reviewDraft']),
  );
}

Map<String, dynamic> _draftToJson(GuidedStepDraft d) => {
  'prescription': d.prescription,
  'set': d.set,
  'running': d.running,
  'notDone': d.notDone.toList(),
  'edits': {
    for (final MapEntry(:key, :value) in d.edits.entries)
      key: {'manualKg': value.manualKg, 'reps': value.reps},
  },
};

GuidedStepDraft? _draftFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final edits = (json['edits'] as Map? ?? const {}).cast<String, dynamic>();
  return GuidedStepDraft(
    prescription: json['prescription'] as int,
    set: json['set'] as int,
    running: json['running'] as bool? ?? false,
    notDone: {...(json['notDone'] as List? ?? const []).cast<String>()},
    edits: {
      for (final MapEntry(:key, :value) in edits.entries)
        key: SetEdit(
          manualKg: ((value as Map)['manualKg'] as num?)?.toDouble(),
          reps: value['reps'] as int?,
        ),
    },
  );
}
