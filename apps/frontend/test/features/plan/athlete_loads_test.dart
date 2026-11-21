import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/catalog_admin_providers.dart';
import 'package:maktub_frontend/features/plan/domain/athlete_loads.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_labels.dart';
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

  group('kilos by hand per athlete (Ari, 2026-11-21)', () {
    test('typed by hand: the kilos as typed, the % of the RM they amount to, and marked as by hand', () {
      expect(manualAthleteLoad(50, _andi), const AthleteSetLoad(pct: 62.5, kg: 50, manualKg: true));
      expect(manualAthleteLoad(40, _noRm), const AthleteSetLoad(kg: 40, manualKg: true));
      const slow = AthleteBasis(id: 'a', name: 'A', rm: 100, workFactor: 90);
      expect(manualAthleteLoad(72, slow).pct, 80);
    });

    test('only the entries typed by hand are kept when the set is worked out again', () {
      expect(
        manualLoads(const {
          'andi': AthleteSetLoad(pct: 65, kg: 52.5),
          'ari': AthleteSetLoad(pct: 69.44, kg: 50, manualKg: true),
        }),
        {'ari': const AthleteSetLoad(pct: 69.44, kg: 50, manualKg: true)},
      );
    });

    test('the suggestion shows the RM, the % and the kilos, or says there is no RM', () {
      final byPct = athleteLoads(pct: 65, kg: null, athletes: const [_andi], equipo: _equipo)['andi'];
      final kg = formatNumber(_equipo.masCercano(52));
      expect(
        athleteSuggestion(_andi, setPct: 65, suggested: byPct, number: formatNumber),
        'Andi · RM 80 kg × 65 % = $kg kg',
      );
      final byKg = athleteLoads(pct: null, kg: 50, athletes: const [_andi], equipo: _equipo)['andi'];
      expect(
        athleteSuggestion(_andi, setPct: null, suggested: byKg, number: formatNumber),
        'Andi · RM 80 kg · 50 kg = 62,5 %',
      );
      expect(athleteSuggestion(_andi, setPct: null, suggested: null, number: formatNumber), 'Andi · RM 80 kg');
      expect(athleteSuggestion(_noRm, setPct: 65, suggested: null, number: formatNumber), 'Nadie · sin RM');
      const slow = AthleteBasis(id: 'a', name: 'A', rm: 100, workFactor: 90);
      final slowLoad = athleteLoads(pct: 80, kg: null, athletes: const [slow], equipo: _equipo)['a'];
      expect(
        athleteSuggestion(slow, setPct: 80, suggested: slowLoad, number: formatNumber),
        'A · RM 100 kg × 80 % = ${formatNumber(_equipo.masCercano(72))} kg (factor 90 %)',
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

    String fieldText(WidgetTester tester, String key) => tester
        .widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)))
        .controller!
        .text;

    testWidgets('for a single athlete typing % fills their kg in the kg field, with no line under it', (tester) async {
      final result = await open(tester, athletes: PrescriptionAthletes(athletes: const [_andi], equipo: _equipo));
      await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '50');
      await tester.pump();
      expect(fieldText(tester, 'set-kg-0-0-1'), '40');
      expect(find.byKey(const Key('set-athletes-0')), findsNothing);

      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      final set = (await result)!.sets.single;
      expect([set.pct, set.kg], [50, 40]);
      expect(set.byAthlete['andi'], const AthleteSetLoad(pct: 50, kg: 40));
    });

    testWidgets('for a single athlete typing kg fills their %', (tester) async {
      final result = await open(tester, athletes: PrescriptionAthletes(athletes: const [_andi], equipo: _equipo));
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '60');
      await tester.pump();
      expect(fieldText(tester, 'set-pct-0-0-1'), '75');

      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      expect((await result)!.sets.single.pct, 75);
    });

    group('kilos by hand per athlete in a plan for several (Ari, 2026-11-21)', () {
      final assigned = PrescriptionAthletes(athletes: const [_andi, _ari, _noRm], equipo: _equipo, assigned: true);

      testWidgets('each athlete gets a line with their suggestion and a field for kilos by hand; blank keeps the '
          'suggestion', (tester) async {
        final result = await open(tester, athletes: assigned);
        await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '65');
        await tester.pump();

        final andiKg = _equipo.masCercano(52);
        expect(
          tester.widget<Text>(find.byKey(const Key('set-suggestion-0-andi'))).data,
          'Andi · RM 80 kg × 65 % = ${formatNumber(andiKg)} kg',
        );
        expect(tester.widget<Text>(find.byKey(const Key('set-suggestion-0-nadie'))).data, 'Nadie · sin RM');
        expect(find.text('${formatNumber(andiKg)} (sugerido)'), findsOneWidget);
        expect(fieldText(tester, 'set-manual-kg-0-andi-0'), '');
        expect(find.byKey(const Key('set-athletes-0')), findsNothing);

        await tester.enterText(find.byKey(const ValueKey('set-manual-kg-0-ari-0')), '50');
        await tester.enterText(find.byKey(const ValueKey('set-manual-kg-0-nadie-0')), '40');
        await tester.tap(find.byKey(const Key('prescription-ok')));
        await tester.pumpAndSettle();
        final set = (await result)!.sets.single;
        expect(set.pct, 65);
        expect(set.byAthlete, {
          'andi': AthleteSetLoad(pct: 65, kg: andiKg),
          'ari': AthleteSetLoad(pct: pctDesdePeso(50, 72), kg: 50, manualKg: true),
          'nadie': const AthleteSetLoad(kg: 40, manualKg: true),
        });
      });

      testWidgets('kilos by hand stay when the % changes, and clearing them gives back the suggestion', (tester) async {
        final result = await open(
          tester,
          athletes: assigned,
          initial: Prescription(
            exerciseId: 'sq',
            sets: [
              PlanSet(
                reps: 5,
                pct: 65,
                byAthlete: {
                  'andi': const AthleteSetLoad(pct: 62.5, kg: 50, manualKg: true),
                  'ari': AthleteSetLoad(pct: 65, kg: _equipo.masCercano(46.8)),
                },
              ),
            ],
          ),
        );
        expect(fieldText(tester, 'set-manual-kg-0-andi-0'), '50');
        expect(fieldText(tester, 'set-manual-kg-0-ari-0'), '');

        await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '70');
        await tester.pump();
        expect(fieldText(tester, 'set-manual-kg-0-andi-0'), '50');
        await tester.tap(find.byKey(const Key('prescription-ok')));
        await tester.pumpAndSettle();
        final set = (await result)!.sets.single;
        expect(set.byAthlete['andi'], const AthleteSetLoad(pct: 62.5, kg: 50, manualKg: true));
        expect(set.byAthlete['ari'], AthleteSetLoad(pct: 70, kg: _equipo.masCercano(72 * 0.7)));
      });

      testWidgets('clearing kilos typed by hand gives the athlete the suggestion again', (tester) async {
        final result = await open(
          tester,
          athletes: assigned,
          initial: const Prescription(
            exerciseId: 'sq',
            sets: [
              PlanSet(reps: 5, pct: 50, byAthlete: {'andi': AthleteSetLoad(pct: 62.5, kg: 50, manualKg: true)}),
            ],
          ),
        );
        await tester.enterText(find.byKey(const ValueKey('set-manual-kg-0-andi-0')), '');
        await tester.tap(find.byKey(const Key('prescription-ok')));
        await tester.pumpAndSettle();
        expect((await result)!.sets.single.byAthlete['andi'], AthleteSetLoad(pct: 50, kg: _equipo.masCercano(40)));
      });

      testWidgets('a plan for one athlete keeps today\'s fields, with no line per athlete', (tester) async {
        await open(tester, athletes: PrescriptionAthletes(athletes: const [_andi], equipo: _equipo, assigned: true));
        expect(find.byKey(const Key('set-athlete-manual-0')), findsNothing);
        expect(find.byKey(const ValueKey('set-manual-kg-0-andi-0')), findsNothing);
      });
    });
  });
}
