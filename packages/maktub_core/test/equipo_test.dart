import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final audit = Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 7, 10));

  group('Equipo como dato', () {
    test('el estándar por defecto es barra de 20 y siete pares', () {
      final e = Equipo.estandarDe('club1');
      expect(e.clubId, 'club1');
      expect(e.barraKg, 20);
      expect(e.discos.map((d) => d.kg), [20, 15, 10, 5, 2.5, 1.5, 1.25]);
      expect(e.cargables, hasLength(88));
      expect(e.validar(), isEmpty);
    });

    test('cambiar el equipo cambia los pesos cargables y el más cercano', () {
      final estandar = Equipo.estandarDe('club1');
      final sinPequenos = estandar.copyWith(discos: [for (final kg in [20.0, 15.0, 10.0, 5.0, 2.5]) ItemInventario(kg)]);
      final barra15 = estandar.copyWith(barras: const [ItemInventario(15)]);

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
      final e = Equipo.deUnaBarra(clubId: 'club1', barraKg: 15, paresDiscos: [10, 2.5], auditoria: audit);
      final copia = Equipo.fromJson(e.toJson());
      expect(copia.clubId, 'club1');
      expect(copia.barraKg, 15);
      expect(copia.discos.map((d) => d.kg), [10, 2.5]);
      expect(copia.auditoria?.creadoPor, 'u1');
      expect(copia.cargables, orderedEquals(e.cargables));
      expect(Equipo.estandarDe('c').toJson().containsKey('auditoria'), isFalse);
    });

    test('un JSON sin barra ni discos toma el estándar', () {
      final e = Equipo.fromJson({'clubId': 'club1'});
      expect(e.cargables, orderedEquals(Equipo.estandar.cargables));
    });

    test('validaciones', () {
      expect(Equipo.deUnaBarra(barraKg: 0).validar(), [EquipoProblem.barNotPositive]);
      expect(Equipo.deUnaBarra(paresDiscos: [10, -5]).validar(), [EquipoProblem.plateNotPositive]);
      expect(Equipo.deUnaBarra(paresDiscos: [10, 10]).validar(), [EquipoProblem.duplicatePlate]);
      final muchos = Equipo.deUnaBarra(paresDiscos: [for (var i = 1; i <= maxTiposDisco + 1; i++) i.toDouble()]);
      expect(muchos.validar(), [EquipoProblem.tooManyPlates]);
      expect(Equipo.deUnaBarra(paresDiscos: const []).validar(), isEmpty);
      expect(Equipo(barras: const []).validar(), [EquipoProblem.noBars]);
      expect(Equipo(barras: const [ItemInventario(20), ItemInventario(20)]).validar(), [EquipoProblem.duplicateBar]);
      expect(
        Equipo(discos: const [ItemInventario(10, 0)]).validar(),
        [EquipoProblem.quantityOutOfRange],
      );
    });

    test('varios pares del mismo peso amplían lo cargable', () {
      final uno = Equipo(discos: const [ItemInventario(10)]);
      final tres = Equipo(discos: const [ItemInventario(10, 3)]);
      expect(uno.cargables, [20, 40]);
      expect(tres.cargables, [20, 40, 60, 80]);
    });

    test('muchos pares no hacen explotar el cálculo y no acumulan error decimal', () {
      final e = Equipo(discos: [
        for (final kg in [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 2.0, 1.5, 1.25, 1.0, 0.5, 0.25]) ItemInventario(kg, 10),
      ]);
      expect(e.cargables.first, 20);
      expect(e.cargables, contains(20.5));
      expect(e.cargables.every((k) => (k * 1000).roundToDouble() == k * 1000), isTrue);
    });

    test('cada ejercicio carga con su barra, y si el club no la tiene con la por defecto', () {
      final e = Equipo(
        barras: const [ItemInventario(20), ItemInventario(15)],
        discos: const [ItemInventario(10)],
      );
      expect(e.barraKg, 20);
      expect(e.cargablesCon(15), [15, 35]);
      expect(e.masCercano(36), 40);
      expect(e.masCercano(36, barKg: 15), 35);
      expect(e.masCercano(36, barKg: 10), 40);
    });

    test('un equipo guardado en el formato anterior se sigue leyendo', () {
      final e = Equipo.fromJson({'clubId': 'c', 'barraKg': 15, 'paresDiscos': [10, 5]});
      expect(e.barras, const [ItemInventario(15)]);
      expect(e.discos, const [ItemInventario(10), ItemInventario(5)]);
    });

    test('el inventario viaja por JSON con sus cantidades', () {
      final e = Equipo(clubId: 'c', discos: const [ItemInventario(10, 3)]);
      expect(Equipo.fromJson(e.toJson()).discos, const [ItemInventario(10, 3)]);
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
