import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/wods/domain/wod_draft.dart';
import 'package:maktub_frontend/features/wods/domain/wod_repository.dart';

Wod sampleWod({
  String id = 'w1',
  String name = 'Fran',
  String? description,
  String? timerId,
  List<Prescription> prescriptions = const [],
}) => Wod(
  id: id,
  clubId: 'c1',
  name: name,
  description: description,
  timerId: timerId,
  prescriptions: prescriptions,
  auditoria: Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1)),
);

/// Keeps the library in memory and answers like the API would.
class FakeWodRepository implements WodRepository {
  FakeWodRepository({List<Wod> wods = const [], this.failure})
    : stored = {for (final w in wods) w.id: w};

  final Map<String, Wod> stored;

  /// When set, [wods] throws it.
  final Object? failure;

  /// When set, [create] and [save] throw it instead of storing.
  Object? writeFailure;

  /// When set, [delete] throws it.
  Object? deleteFailure;
  final calls = <String>[];

  /// Drafts sent to [create] and [save], in order.
  final sent = <WodDraft>[];

  @override
  Future<List<Wod>> wods(String clubId) async {
    calls.add('wods:$clubId');
    if (failure != null) throw failure!;
    return stored.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Wod _store(String id, WodDraft d) {
    final wod = sampleWod(
      id: id,
      name: d.name.trim(),
      description: d.description.trim().isEmpty ? null : d.description.trim(),
      timerId: d.timerId,
      prescriptions: d.prescriptions,
    );
    stored[id] = wod;
    return wod;
  }

  @override
  Future<Wod> create(String clubId, WodDraft draft) async {
    calls.add('create:$clubId');
    sent.add(draft);
    if (writeFailure != null) throw writeFailure!;
    return _store('new${stored.length}', draft);
  }

  @override
  Future<Wod> save(String clubId, String wodId, WodDraft draft) async {
    calls.add('save:$clubId:$wodId');
    sent.add(draft);
    if (writeFailure != null) throw writeFailure!;
    return _store(wodId, draft);
  }

  @override
  Future<void> delete(String clubId, String wodId) async {
    calls.add('delete:$clubId:$wodId');
    if (deleteFailure != null) throw deleteFailure!;
    stored.remove(wodId);
  }
}
