import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final equipo = Equipo.estandar;

  group('proposeLoad', () {
    test('reference and % with RM: the target of RM × factor × %', () {
      final p = proposeLoad(
        hasReference: true,
        pct: 80,
        rm: 80,
        fixedKg: 30,
        equipo: equipo,
      );
      expect(
        p,
        LoadProposal(
          source: LoadSource.rm,
          weightKg: pesoPorPorcentaje(rm: 80, pct: 80, equipo: equipo),
        ),
      );
      expect(p.weightKg, 63);
    });

    test('reference and % with RM: rounds on the bar it is given', () {
      final twoBars = Equipo(
        barras: const [ItemInventario(20), ItemInventario(15)],
        discos: const [ItemInventario(1.25)],
      );
      LoadProposal propose({double? barKg}) => proposeLoad(
        hasReference: true,
        pct: 16,
        rm: 100,
        fixedKg: null,
        equipo: twoBars,
        barKg: barKg,
      );

      expect(propose().weightKg, 20);
      expect(propose(barKg: 15).weightKg, 15);
    });

    test('reference and % with RM: the work factor applies', () {
      final p = proposeLoad(
        hasReference: true,
        pct: 75,
        rm: 100,
        fixedKg: null,
        equipo: equipo,
        workFactor: 80,
      );
      expect(p.weightKg, 60);
    });

    test(
      '% with a missing RM: nothing proposed, and the fixed weight is not used',
      () {
        for (final rm in <double?>[null, 0]) {
          final p = proposeLoad(
            hasReference: true,
            pct: 80,
            rm: rm,
            fixedKg: 30,
            equipo: equipo,
          );
          expect(p.source, LoadSource.rm);
          expect(p.weightKg, isNull);
        }
      },
    );

    test(
      'no reference: the fixed weight as loaded, even with a % and an RM',
      () {
        final p = proposeLoad(
          hasReference: false,
          pct: 80,
          rm: 100,
          fixedKg: 12.3,
          equipo: equipo,
        );
        expect(p, const LoadProposal(source: LoadSource.fixed, weightKg: 12.3));
      },
    );

    test('no reference and no fixed weight: nothing proposed', () {
      final p = proposeLoad(
        hasReference: false,
        pct: null,
        rm: null,
        fixedKg: null,
        equipo: equipo,
      );
      expect(p, const LoadProposal(source: LoadSource.fixed, weightKg: null));
    });

    test('reference but the set has no %: falls to the fixed weight', () {
      for (final pct in <double?>[null, 0]) {
        final p = proposeLoad(
          hasReference: true,
          pct: pct,
          rm: 100,
          fixedKg: 25,
          equipo: equipo,
        );
        expect(p, const LoadProposal(source: LoadSource.fixed, weightKg: 25));
      }
    });

    test('reference, no %, no fixed weight: nothing proposed', () {
      final p = proposeLoad(
        hasReference: true,
        pct: null,
        rm: 100,
        fixedKg: null,
        equipo: equipo,
      );
      expect(p.weightKg, isNull);
    });
  });
}
