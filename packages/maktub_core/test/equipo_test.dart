import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final audit = Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 7, 10));

  group('Equipo como dato', () {
    test('el estándar por defecto es barra de 20 y siete pares', () {
      final e = Equipo.estandarDe('club1');
      expect(e.clubId, 'club1');
      expect(e.barraKg, 20);
      expect(e.paresDiscos, [20, 15, 10, 5, 2.5, 1.5, 1.25]);
      expect(e.cargables, hasLength(88));
      expect(e.validar(), isEmpty);
    });

    test('cambiar el equipo cambia los pesos cargables y el más cercano', () {
      final estandar = Equipo.estandarDe('club1');
      final sinPequenos = estandar.copyWith(paresDiscos: [20, 15, 10, 5, 2.5]);
      final barra15 = estandar.copyWith(barraKg: 15);

      expect(estandar.masCercano(23), 23);
      expect(sinPequenos.cargables, isNot(contains(23)));
      expect(sinPequenos.masCercano(23), 25);
      expect(barra15.cargables.first, 15);
      expect(
        pesoPorPorcentaje(rm: 100, pct: 61, equipo: estandar),
        isNot(pesoPorPorcentaje(rm: 100, pct: 61, equipo: sinPequenos)),
      );
    });

    test('viaja ida y vuelta por JSON', () {
      final e = Equipo(clubId: 'club1', barraKg: 15, paresDiscos: [10, 2.5], auditoria: audit);
      final copia = Equipo.fromJson(e.toJson());
      expect(copia.clubId, 'club1');
      expect(copia.barraKg, 15);
      expect(copia.paresDiscos, [10, 2.5]);
      expect(copia.auditoria?.creadoPor, 'u1');
      expect(copia.cargables, orderedEquals(e.cargables));
      expect(Equipo.estandarDe('c').toJson().containsKey('auditoria'), isFalse);
    });

    test('un JSON sin barra ni discos toma el estándar', () {
      final e = Equipo.fromJson({'clubId': 'club1'});
      expect(e.cargables, orderedEquals(Equipo.estandar.cargables));
    });

    test('validaciones', () {
      expect(Equipo(barraKg: 0).validar(), [EquipoProblem.barNotPositive]);
      expect(Equipo(paresDiscos: [10, -5]).validar(), [EquipoProblem.plateNotPositive]);
      expect(Equipo(paresDiscos: [10, 10]).validar(), [EquipoProblem.duplicatePlate]);
      final muchos = Equipo(paresDiscos: [for (var i = 1; i <= 13; i++) i.toDouble()]);
      expect(muchos.validar(), [EquipoProblem.tooManyPlates]);
      expect(Equipo(paresDiscos: const []).validar(), isEmpty);
    });
  });

  group('Temporizador con ámbito', () {
    test('el ámbito se deduce del clubId y viaja con auditoría', () {
      final base = Temporizador(
        id: 't1',
        nombre: 'Tabata',
        tipo: TipoTemporizador.tabata,
        trabajoSeg: 20,
        descansoSeg: 10,
        rondas: 8,
        auditoria: audit,
      );
      const propio = Temporizador(
        id: 't2',
        clubId: 'club1',
        nombre: 'Mío',
        tipo: TipoTemporizador.emom,
        trabajoSeg: 60,
        rondas: 10,
      );

      expect(scopeOf(base), CatalogScope.base);
      expect(scopeOf(propio), CatalogScope.club);
      expect(isVisibleTo(propio, 'club2'), isFalse);

      final copia = Temporizador.fromJson(base.toJson());
      expect((copia.clubId, copia.tipo, copia.rondas), (clubPlataforma, TipoTemporizador.tabata, 8));
      expect(copia.auditoria?.creadoPor, 'u1');
      expect(Temporizador.fromJson(propio.toJson()).clubId, 'club1');
      expect(fasesDe(copia), hasLength(15));
    });
  });
}
