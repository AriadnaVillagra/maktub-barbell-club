import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/seguimiento/domain/usecases/armar_registro.dart';
import 'package:maktub_frontend/features/seguimiento/domain/usecases/construir_sesion.dart';

import '../../../datos_de_prueba.dart';

void main() {
  final equipo = Equipo.estandar;
  const construir = ConstruirSesion();

  test('arma el día: orden por bloque/grupo/orden, pesos por RM y fijos', () {
    final sesion = construir(snapshotDePrueba(), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);

    expect(sesion.variante, Variante.descarga);
    expect(sesion.primario?.id, 'sq');
    expect(sesion.items.map((i) => i.ejercicio.id), ['sq', 'curl', 'face']);

    final sq = sesion.items[0].vista(sesion.ajuste, equipo);
    // 30 % de 80 = 24: empate entre 23 y 25, gana el menor. 0.8 se lee como 80 % → 64 → 63.
    expect(sq.map((s) => s.pesoKg), [23, 63]);
    expect(sesion.items[1].vista(sesion.ajuste, equipo).first.pesoKg, 12);
    expect(sesion.items[2].vista(sesion.ajuste, equipo).first.pesoKg, isNull); // sin peso fijo cargado
  });

  test('deduce el calentamiento por la referencia del primario', () {
    final sesion = construir(snapshotDePrueba(), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);
    expect(sesion.calentamiento.map((e) => e.id), unorderedEquals(['cal_sq', 'cal_aprox']));
  });

  test('la semana 3 repite carga si el plan no define carga2', () {
    final sesion = construir(snapshotDePrueba(), atletaId: 'a2', ciclo: 1, semana: 3, dia: 1);
    expect(sesion.variante, Variante.carga);
    expect(sesion.items.single.vista(sesion.ajuste, equipo).single.pesoKg, 60); // 85 % de 70 = 59.5 → 60 cargable
  });

  test('el ajuste recalcula lo no tocado y respeta lo editado a mano', () {
    var sesion = construir(snapshotDePrueba(), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);
    sesion = sesion.editarSerie(0, 0, equipo, pesoKg: 30);
    sesion = sesion.cambiarAjuste(-5);

    final sq = sesion.items[0].vista(sesion.ajuste, equipo);
    expect(sq[0].pesoKg, 30);
    expect(sq[1].pesoKg, 60.5); // 76 % de 80 = 60.8 → 60.5 cargable
    expect(sesion.items[0].editado(sesion.ajuste, equipo), isTrue);

    sesion = sesion.restaurar(0);
    expect(sesion.items[0].editado(sesion.ajuste, equipo), isFalse);
  });

  test('el ajuste por ejercicio pisa al de la sesión y 0 vuelve a heredar', () {
    var sesion = construir(snapshotDePrueba(), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);
    sesion = sesion.cambiarAjuste(10).cambiarAjusteItem(0, -5);
    expect(sesion.items[0].ajusteEfectivo(sesion.ajuste), 105);

    sesion = sesion.cambiarAjusteItem(0, 0);
    expect(sesion.items[0].ajusteEfectivo(sesion.ajuste), 110);
  });

  test('el registro mantiene rm × pct ≈ peso, también con kilos escritos a mano', () {
    var sesion = construir(snapshotDePrueba(), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);
    sesion = sesion.cambiarAjuste(-5).editarSerie(0, 0, equipo, pesoKg: 30);

    final registro = const ArmarRegistro()(sesion, planId: 'p1', fecha: DateTime.utc(2026, 11, 3), equipo: equipo);
    final sq = registro.filas.where((f) => f.ejercicio == 'sq').toList();

    expect(sq[0].pct, 37.5); // 30 / 80, escrito a mano
    expect(sq[1].pct, 76); // 80 % con −5 % de ajuste
    for (final f in sq) {
      expect(f.rmVigente, 80);
    }
    expect(registro.filas.where((f) => f.bloque == Bloque.calentamiento), hasLength(2));
    expect(registro.filas.firstWhere((f) => f.ejercicio == 'curl').rmVigente, isNull);
  });

  test('un día registrado retoma lo guardado', () {
    final guardada = SesionRegistrada(
      atleta: 'a1',
      plan: 'p1',
      ciclo: 1,
      semana: 1,
      dia: 1,
      fecha: DateTime.utc(2026, 11, 3),
      filas: const [
        FilaRegistro(ejercicio: 'sq', bloque: Bloque.principal, serie: 1, pesoKg: 22.5, reps: 8, nota: 'pesada'),
      ],
    );
    final sesion = construir(snapshotDePrueba(sesiones: [guardada]), atletaId: 'a1', ciclo: 1, semana: 1, dia: 1);

    expect(sesion.registrada, isTrue);
    final sq = sesion.items[0];
    expect(sq.series.single.hecha, isTrue);
    expect(sq.vista(sesion.ajuste, equipo).single.pesoKg, 22.5);
    expect(sq.nota, 'pesada');
  });
}
