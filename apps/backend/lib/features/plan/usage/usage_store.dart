import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the usage slice reads: whether any stored plan or library WoD refers to an exercise or a timer.
abstract interface class PlanUsageStore {
  /// Whether a plan has a prescription of [exerciseId]. Only plans of [clubId] count; a null [clubId]
  /// means every club (the question for a platform base item, which any club may use).
  Future<bool> exerciseInPlans(String? clubId, String exerciseId);

  /// Whether a plan has [timerId] as the timer of a block or of a prescription. Same club rule.
  Future<bool> timerInPlans(String? clubId, String timerId);

  /// Whether a library WoD has a prescription of [exerciseId]. Same club rule as [exerciseInPlans].
  Future<bool> exerciseInWods(String? clubId, String exerciseId);

  /// Whether a library WoD has [timerId] as its timer or as the timer of a prescription. Same club rule.
  Future<bool> timerInWods(String? clubId, String timerId);
}

const _blocks = 'modelosSemana.dias.bloques';
const _exercisePath = '$_blocks.prescripciones.ejercicioId';
const _blockTimerPath = '$_blocks.temporizadorId';
const _prescriptionTimerPath = '$_blocks.prescripciones.temporizadorId';

const _wodExercisePath = 'prescripciones.ejercicioId';
const _wodTimerPath = 'temporizadorId';
const _wodPrescriptionTimerPath = 'prescripciones.temporizadorId';

class MongoPlanUsageStore implements PlanUsageStore {
  MongoPlanUsageStore(this._db);

  final Db _db;

  Future<bool> _any(
    String collection,
    String? clubId,
    Map<String, Object?> condition,
  ) async {
    final doc = await _db.collection(collection).findOne({
      'clubId': ?clubId,
      ...condition,
    });
    return doc != null;
  }

  @override
  Future<bool> exerciseInPlans(String? clubId, String exerciseId) =>
      _any(Colecciones.planes, clubId, {_exercisePath: exerciseId});

  @override
  Future<bool> timerInPlans(String? clubId, String timerId) =>
      _any(Colecciones.planes, clubId, {
        r'$or': [
          {_blockTimerPath: timerId},
          {_prescriptionTimerPath: timerId},
        ],
      });

  @override
  Future<bool> exerciseInWods(String? clubId, String exerciseId) =>
      _any(Colecciones.wods, clubId, {_wodExercisePath: exerciseId});

  @override
  Future<bool> timerInWods(String? clubId, String timerId) =>
      _any(Colecciones.wods, clubId, {
        r'$or': [
          {_wodTimerPath: timerId},
          {_wodPrescriptionTimerPath: timerId},
        ],
      });
}
