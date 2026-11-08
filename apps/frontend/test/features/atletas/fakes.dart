import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_fakes.dart';

final today = DateTime.utc(2026, 11, 8);

Auditoria auditAt(DateTime at) => Auditoria(creadoPor: 'u1', creadoEn: at);

Reference rm(
  String id,
  String exerciseId,
  double kg,
  DateTime date, {
  DateTime? createdAt,
}) => Reference(
  id: id,
  clubId: 'c1',
  athleteId: 'a1',
  exerciseId: exerciseId,
  type: ReferenceType.rm,
  value: kg,
  date: date,
  origin: ReferenceOrigin.testeado,
  auditoria: auditAt(createdAt ?? date),
);

WorkFactor factor(
  String id,
  String exerciseId,
  double percent,
  DateTime date,
) => WorkFactor(
  id: id,
  clubId: 'c1',
  athleteId: 'a1',
  exerciseId: exerciseId,
  value: percent,
  date: date,
  auditoria: auditAt(date),
);

FixedWeight fixed(String exerciseId, double kg) => FixedWeight(
  id: 'k-$exerciseId',
  clubId: 'c1',
  athleteId: 'a1',
  exerciseId: exerciseId,
  kg: kg,
  auditoria: auditAt(DateTime.utc(2026, 1, 1)),
);

class FakeAthleteRepository implements AthleteRepository {
  FakeAthleteRepository({
    this.athletesList = const [],
    Map<String, AthleteSheet> sheets = const {},
    this.failure,
    this.writeFailure,
  }) : sheets = {...sheets};

  final List<AthleteSummary> athletesList;
  final Map<String, AthleteSheet> sheets;

  /// Thrown by the write methods when set.
  final Object? writeFailure;
  final Object? failure;
  final calls = <String>[];

  @override
  Future<List<AthleteSummary>> athletes(String clubId) async {
    calls.add('athletes:$clubId');
    if (failure != null) throw failure!;
    return athletesList;
  }

  @override
  Future<AthleteSheet> sheet(String clubId, String athleteId) async {
    calls.add('sheet:$clubId:$athleteId');
    if (failure != null) throw failure!;
    return sheets[athleteId] ?? (throw StateError('no sheet $athleteId'));
  }

  @override
  Future<void> addReference(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double value,
    required DateTime date,
  }) async => _write(
    'rm:$exerciseId:$value:${aIsoFecha(date)}',
    (s) => AthleteSheet(
      athleteId: s.athleteId,
      references: [...s.references, rm('new', exerciseId, value, date)],
      factors: s.factors,
      fixedWeights: s.fixedWeights,
    ),
  );

  @override
  Future<void> addFactor(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double percent,
    required DateTime date,
  }) async => _write(
    'factor:$exerciseId:$percent:${aIsoFecha(date)}',
    (s) => AthleteSheet(
      athleteId: s.athleteId,
      references: s.references,
      factors: [...s.factors, factor('new', exerciseId, percent, date)],
      fixedWeights: s.fixedWeights,
    ),
  );

  @override
  Future<void> setFixedWeight(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double kg,
  }) async => _write(
    'fixed:$exerciseId:$kg',
    (s) => AthleteSheet(
      athleteId: s.athleteId,
      references: s.references,
      factors: s.factors,
      fixedWeights: [
        for (final f in s.fixedWeights)
          if (f.exerciseId != exerciseId) f,
        fixed(exerciseId, kg),
      ],
    ),
  );
}

extension on FakeAthleteRepository {
  void _write(String call, AthleteSheet Function(AthleteSheet) change) {
    calls.add(call);
    if (writeFailure != null) throw writeFailure!;
    sheets['a1'] = change(sheets['a1']!);
  }
}

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

/// Mounts [page] for the club `c1`, with the catalog holding [exercises].
Future<void> pumpAthletePage(
  WidgetTester tester,
  Widget page,
  FakeAthleteRepository repo, {
  List<Exercise> exercises = const [],
  bool settle = true,
  Set<Rol> roles = const {Rol.coach},
  Map<String, String> athleteIds = const {},
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(_SignedIn.new),
        meRepositoryProvider.overrideWithValue(
          FakeMeRepository(
            meWith([
              (club('c1', 'Gimnasio', TipoClub.club), roles),
            ], athleteIds: athleteIds),
          ),
        ),
        catalogRepositoryProvider.overrideWithValue(
          FakeCatalog([...exercises]),
        ),
        athleteRepositoryProvider.overrideWithValue(repo),
        todayProvider.overrideWithValue(today),
      ],
      child: MaterialApp(theme: TemaMaktub.claro(), home: page),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
