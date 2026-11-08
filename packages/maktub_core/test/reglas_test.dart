import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  group('Equipo', () {
    final equipo = Equipo.estandar;

    test('el equipo estándar da 88 pesos cargables', () {
      expect(equipo.cargables, hasLength(88));
      expect(equipo.cargables.first, 20);
    });

    test('habilita los pesos que permiten los pares de 1.5', () {
      expect(equipo.cargables, containsAll([23, 25.5, 28, 45.5]));
    });

    test('ajusta al cargable más cercano y ante empate gana el menor', () {
      expect(equipo.masCercano(64), 63); // 80 % de 80 → 63, como en los datos de octubre
      expect(equipo.masCercano(21.25), 20); // empate entre 20 y 22.5
      expect(equipo.masCercano(5), 20); // nunca menos que la barra
    });
  });

  group('porcentajes', () {
    test('normalizarPct acepta 65 o 0.65', () {
      expect(normalizarPct(65), 65);
      expect(normalizarPct(0.65), 65);
      expect(normalizarPct(0.725), 72.5);
      expect(normalizarPct(0), isNull);
      expect(normalizarPct(null), isNull);
    });

    test('pctEfectivo aplica el ajuste del día', () {
      expect(pctEfectivo(80, 100), 80);
      expect(pctEfectivo(80, 95), 76);
      expect(pctEfectivo(72.5, 105), 76.13);
    });

    test('pesoPorPorcentaje usa el cargable más cercano y es nulo sin RM', () {
      expect(pesoPorPorcentaje(rm: 80, pct: 80, equipo: Equipo.estandar), 63);
      expect(pesoPorPorcentaje(rm: null, pct: 80, equipo: Equipo.estandar), isNull);
      expect(pesoPorPorcentaje(rm: 0, pct: 80, equipo: Equipo.estandar), isNull);
    });

    test('pesoPorPorcentaje: a neutral work factor of 100 changes nothing', () {
      expect(pesoPorPorcentaje(rm: 80, pct: 80, equipo: Equipo.estandar, workFactor: 100), 63);
      expect(
        pesoPorPorcentaje(rm: 100, pct: 61, equipo: Equipo.estandar, workFactor: 100),
        pesoPorPorcentaje(rm: 100, pct: 61, equipo: Equipo.estandar),
      );
    });

    test('pesoPorPorcentaje: another work factor applies rm × factor × pct, rounded to loadable', () {
      // 100 × 0.8 × 0.75 = 60 (loadable).
      expect(pesoPorPorcentaje(rm: 100, pct: 75, equipo: Equipo.estandar, workFactor: 80), 60);
      // 83 × 0.9 × 0.7 = 52.29, nearest loadable is not the raw value.
      final w = pesoPorPorcentaje(rm: 83, pct: 70, equipo: Equipo.estandar, workFactor: 90)!;
      expect(w, Equipo.estandar.masCercano(83 * 0.9 * 0.7));
      expect(Equipo.estandar.cargables, contains(w));
      expect(pesoPorPorcentaje(rm: 100, pct: 80, equipo: Equipo.estandar, workFactor: 110), 88);
    });

    test('pesoPorPorcentaje: no RM gives null whatever the work factor', () {
      expect(pesoPorPorcentaje(rm: null, pct: 80, equipo: Equipo.estandar, workFactor: 80), isNull);
      expect(pesoPorPorcentaje(rm: 0, pct: 80, equipo: Equipo.estandar, workFactor: 80), isNull);
    });

    test('pesoPorPorcentaje: a tie between loadables goes to the lower one', () {
      // 50 × 0.5 × 0.85 = 21.25, halfway between 20 and 22.5.
      expect(pesoPorPorcentaje(rm: 50, pct: 85, equipo: Equipo.estandar, workFactor: 50), 20);
    });

    test('pctDesdePeso mantiene el invariante rm × pct ≈ peso', () {
      expect(pctDesdePeso(63, 80), 78.75);
    });

    test('el ajuste se acota entre 50 y 150', () {
      expect(Ajuste.acotar(40), 50);
      expect(Ajuste.acotar(160), 150);
      expect(Ajuste.acotar(105), 105);
    });
  });

  group('ciclo', () {
    final inicio = DateTime.utc(2026, 11, 2);

    test('ubica la fecha en ciclo y semana', () {
      UbicacionEnCiclo en(DateTime f) => UbicacionEnCiclo.desdeFechas(inicio: inicio, fecha: f);

      expect(en(DateTime.utc(2026, 11, 2)), const UbicacionEnCiclo(ciclo: 1, semana: 1));
      expect(en(DateTime.utc(2026, 11, 8)), const UbicacionEnCiclo(ciclo: 1, semana: 1));
      expect(en(DateTime.utc(2026, 11, 9)), const UbicacionEnCiclo(ciclo: 1, semana: 2));
      expect(en(DateTime.utc(2026, 11, 30)), const UbicacionEnCiclo(ciclo: 2, semana: 1));
      expect(en(DateTime.utc(2026, 10, 1)), const UbicacionEnCiclo(ciclo: 1, semana: 1));
    });

    test('los ciclos se repiten sin fin', () {
      final ubicacion = UbicacionEnCiclo.desdeFechas(inicio: inicio, fecha: inicio.add(const Duration(days: 7 * 41)));
      expect(ubicacion, const UbicacionEnCiclo(ciclo: 11, semana: 2));
    });
  });

  group('fases', () {
    test('tabata no tiene descanso al final', () {
      final fases = fasesDe(const Temporizador(
        id: 't',
        nombre: 'Tabata',
        tipo: TipoTemporizador.tabata,
        trabajoSeg: 20,
        descansoSeg: 10,
        rondas: 8,
      ));
      expect(fases, hasLength(15));
      expect(fases.last.esTrabajo, isTrue);
    });

    test('emom tiene una fase por ronda', () {
      final fases = fasesDe(const Temporizador(
        id: 'e',
        nombre: 'EMOM',
        tipo: TipoTemporizador.emom,
        trabajoSeg: 60,
        rondas: 10,
      ));
      expect(fases.map((f) => f.etiqueta).last, 'Minuto 10');
    });

    test('reloj formatea mm:ss', () {
      expect(reloj(90), '01:30');
      expect(reloj(-3), '00:00');
    });
  });
}
