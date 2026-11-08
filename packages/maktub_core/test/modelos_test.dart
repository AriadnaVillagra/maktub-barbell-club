import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  test('Auditoria viaja ida y vuelta por JSON en UTC', () {
    final creada = Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 7, 10));
    final modificada = creada.modificada('u2', ahora: DateTime.utc(2026, 11, 8, 9));

    final copia = Auditoria.fromJson(modificada.toJson());

    expect(copia.creadoPor, 'u1');
    expect(copia.creadoEn, DateTime.utc(2026, 11, 7, 10));
    expect(copia.modificadoPor, 'u2');
    expect(copia.modificadoEn, DateTime.utc(2026, 11, 8, 9));
    expect(creada.toJson().containsKey('modificadoPor'), isFalse);
  });

  test('desdeCable tolera mayúsculas y espacios y rechaza lo desconocido', () {
    expect(TipoTemporizador.deCable(' EMOM '), TipoTemporizador.emom);
    expect(() => TipoTemporizador.deCable('otro'), throwsFormatException);
  });

  test('Temporizador viaja ida y vuelta por JSON', () {
    const t = Temporizador(id: 'tabata', nombre: 'Tabata', tipo: TipoTemporizador.tabata, trabajoSeg: 20, descansoSeg: 10, rondas: 8);
    final copia = Temporizador.fromJson(t.toJson());
    expect((copia.tipo, copia.trabajoSeg, copia.descansoSeg, copia.rondas), (TipoTemporizador.tabata, 20, 10, 8));
  });
}
