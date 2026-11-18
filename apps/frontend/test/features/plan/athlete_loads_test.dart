import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/catalog_admin_providers.dart';
import 'package:maktub_frontend/features/plan/domain/athlete_loads.dart';
import 'package:maktub_frontend/features/plan/presentation/prescription_dialog.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../catalogo/catalog_fakes.dart';

final _equipo = Equipo.estandarDe('c1');
const _andi = AthleteBasis(id: 'andi', name: 'Andi', rm: 80);
const _ari = AthleteBasis(id: 'ari', name: 'Ari', rm: 72);
const _noRm = AthleteBasis(id: 'nadie', name: 'Nadie', rm: null);

void main() {
  group('athleteLoads', () {
    test('kilos typed: each athlete gets the % of their RM and the same kilos', () {
      final loads = athleteLoads(pct: null, kg: 50, athletes: const [_andi, _ari, _noRm], equipo: _equipo);
      expect(loads, {
        'andi': const AthleteSetLoad(pct: 62.5, kg: 50),
        'ari': const AthleteSetLoad(pct: 69.44, kg: 50),
      });
    });

    test('% typed: each athlete gets the same % and their kilos, to the nearest loadable', () {
      final loads = athleteLoads(pct: 70, kg: null, athletes: const [_andi, _ari], equipo: _equipo);
      expect(loads['andi'], AthleteSetLoad(pct: 70, kg: _equipo.masCercano(56)));
      expect(loads['ari']!.kg, _equipo.masCercano(72 * 0.7));
    });

    test('the work factor counts both ways, as in the session', () {
      const slow = AthleteBasis(id: 'a', name: 'A', rm: 100, workFactor: 90);
      expect(athleteLoads(pct: 80, kg: null, athletes: const [slow], equipo: _equipo)['a']!.kg, _equipo.masCercano(72));
      expect(athleteLoads(pct: null, kg: 72, athletes: const [slow], equipo: _equipo)['a']!.pct, 80);
    });

    test('nothing typed, nothing frozen', () {
      expect(athleteLoads(pct: null, kg: null, athletes: const [_andi], equipo: _equipo), isEmpty);
    });

    test('the summary follows the athletes order', () {
      final loads = athleteLoads(pct: null, kg: 50, athletes: const [_andi, _ari], equipo: _equipo);
      expect(
        athleteLoadsSummary(loads, const [_andi, _ari], (v) => v.toString()),
        'Andi 50.0 kg 62.5 % · Ari 50.0 kg 69.44 %',
      );
    });
  });

  group('the prescription dialog (E5.16)', () {
    Future<Future<Prescription?>> open(
      WidgetTester tester, {
      Prescription? initial,
      PrescriptionAthletes? athletes,
    }) async {
      late Future<Prescription?> result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clubTimersProvider.overrideWith((ref) async => const <Temporizador>[])],
          child: MaterialApp(
            theme: TemaMaktub.claro(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => result = askPrescription(
                  context,
                  initial: initial ?? const Prescription(exerciseId: 'sq', sets: [PlanSet(reps: 5)]),
                  exercise: ex('sq', 'Sentadilla'),
                  athletes: athletes ?? PrescriptionAthletes(athletes: const [_andi, _ari], equipo: _equipo),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('typing kg shows and keeps each athlete\'s %', (tester) async {
      final result = await open(tester);
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '50');
      await tester.pump();
      expect(find.text('Andi 50 kg 62,5 % · Ari 50 kg 69,44 %'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      final set = (await result)!.sets.single;
      expect(set.kg, 50);
      expect(set.pct, isNull);
      expect(set.byAthlete['andi'], const AthleteSetLoad(pct: 62.5, kg: 50));
    });

    testWidgets('typing % clears the kilos and freezes each athlete\'s kilos', (tester) async {
      final result = await open(
        tester,
        initial: const Prescription(exerciseId: 'sq', sets: [PlanSet(reps: 5, kg: 50)]),
      );
      await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '70');
      await tester.pump();
      expect(find.byKey(const ValueKey('set-kg-0-0-1')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('set-kg-0-0-1')), matching: find.byType(TextField))).controller!.text,
        '',
      );

      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      final set = (await result)!.sets.single;
      expect(set.pct, 70);
      expect(set.kg, isNull);
      expect(set.byAthlete['andi'], AthleteSetLoad(pct: 70, kg: _equipo.masCercano(56)));
    });

    testWidgets('an assigned plan offers no choice of athletes', (tester) async {
      await open(tester);
      expect(find.text('Calcular para'), findsNothing);
    });

    testWidgets('without an assignment the coach chooses who it is worked out for', (tester) async {
      Set<String>? remembered;
      final result = await open(
        tester,
        athletes: PrescriptionAthletes(
          athletes: const [_andi, _ari, _noRm],
          equipo: _equipo,
          chosen: const {'andi', 'ari', 'nadie'},
          onChosen: (ids) => remembered = ids,
        ),
      );
      expect(find.text('Calcular para'), findsOneWidget);
      expect(find.text('Nadie (sin RM)'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '50');
      await tester.pump();
      expect(find.text('Andi 50 kg 62,5 % · Ari 50 kg 69,44 %'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription-athlete-andi')));
      await tester.pump();
      expect(remembered, {'ari', 'nadie'});
      expect(find.text('Ari 50 kg 69,44 %'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      expect((await result)!.sets.single.byAthlete.keys, ['ari']);
    });

  });
}
