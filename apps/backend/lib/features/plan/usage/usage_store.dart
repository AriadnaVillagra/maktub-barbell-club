import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the plan usage slice reads: whether any stored plan refers to an exercise or a timer.
abstract interface class PlanUsageStore {
  /// Whether a plan has a prescription of [exerciseId]. Only plans of [clubId] count; a null [clubId]
  /// means every club (the question for a platform base item, which any club may use).
  Future<bool> exerciseInPlans(String? clubId, String exerciseId);

  /// Whether a plan has [timerId] as the timer of a block or of a prescription. Same club rule.
  Future<bool> timerInPlans(String? clubId, String timerId);
}

const _blocks = 'modelosSemana.dias.bloques';
const _exercisePath = '$_blocks.prescripciones.ejercicioId';
const _blockTimerPath = '$_blocks.temporizadorId';
const _prescriptionTimerPath = '$_blocks.prescripciones.temporizadorId';

class MongoPlanUsageStore implements PlanUsageStore {
  MongoPlanUsageStore(this._db);

  final Db _db;

  Future<bool> _any(String? clubId, Map<String, Object?> condition) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      'clubId': ?clubId,
      ...condition,
    });
    return doc != null;
  }

  @override
  Future<bool> exerciseInPlans(String? clubId, String exerciseId) =>
      _any(clubId, {_exercisePath: exerciseId});

  @override
  Future<bool> timerInPlans(String? clubId, String timerId) => _any(clubId, {
    r'$or': [
      {_blockTimerPath: timerId},
      {_prescriptionTimerPath: timerId},
    ],
  });
}
