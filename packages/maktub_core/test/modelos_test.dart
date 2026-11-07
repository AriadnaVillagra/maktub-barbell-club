import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  test('Plan viaja ida y vuelta por JSON', () {
    final plan = Plan(
      id: 'p1',
      nombre: 'Plan',
      activo: true,
      inicio: DateTime.utc(2026, 11, 2),
      dias: const [
        PlanDia(dia: 1, primario: 'sq_espalda', variantes: {
          Variante.carga2: ContenidoVariante(ejercicios: [
            Prescripcion(
              bloque: Bloque.principal,
              orden: 1,
              ejercicio: 'sq_espalda',
              series: [SeriePlan(reps: 8, pct: 60), SeriePlan(reps: 3, pct: 80)],
            ),
          ]),
        }),
      ],
    );

    final copia = Plan.fromJson(plan.toJson());

    expect(copia.inicio, DateTime.utc(2026, 11, 2));
    expect(copia.tieneCarga2, isTrue);
    expect(copia.dia(1)!.variantes[Variante.carga2]!.ejercicios.single.series.last.pct, 80);
  });

  test('SesionRegistrada valida su forma y tiene una clave por día', () {
    final sesion = SesionRegistrada(
      atleta: 'a1',
      plan: 'p1',
      ciclo: 1,
      semana: 5,
      dia: 1,
      fecha: DateTime.utc(2026, 11, 7),
    );

    expect(sesion.validar(), ['la semana debe estar entre 1 y 4']);
    expect(sesion.clave, 'a1|p1|1|5|1');
  });

  test('el bloque final viaja como "final"', () {
    const fila = FilaRegistro(ejercicio: 'curl', bloque: Bloque.cierre, pesoKg: 12);
    expect(fila.toJson()['bloque'], 'final');
    expect(FilaRegistro.fromJson(fila.toJson()).bloque, Bloque.cierre);
  });
}
