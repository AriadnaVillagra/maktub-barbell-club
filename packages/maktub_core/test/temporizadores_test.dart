import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

Temporizador _t(TipoTemporizador tipo, {int trabajo = 60, int descanso = 0, int rondas = 1, int series = 1, int entre = 0, int? limite, int? senal, bool deathBy = false, List<Temporizador> bloques = const []}) =>
    Temporizador(id: 't', nombre: 'n', tipo: tipo, trabajoSeg: trabajo, descansoSeg: descanso, rondas: rondas, series: series, descansoSeriesSeg: entre, limiteSeg: limite, senalCadaSeg: senal, deathBy: deathBy, bloques: bloques);

void main() {
  test('tabata 8 x 20/10 dura 03:50, sin descanso final', () {
    expect(duracionTotalSeg(_t(TipoTemporizador.tabata, trabajo: 20, descanso: 10, rondas: 8)), 230);
  });

  test('las series repiten el temporizador con el descanso entre ellas', () {
    final fases = fasesDe(_t(TipoTemporizador.amrap, trabajo: 300, series: 3, entre: 60));
    expect(fases.map((f) => f.segundos), [300, 60, 300, 60, 300]);
    expect(fases.first.series, 3);
    expect(fases.last.serie, 3);
    expect(duracionTotalSeg(_t(TipoTemporizador.amrap, trabajo: 300, series: 3, entre: 60)), 1020);
  });

  test('for time sin límite es abierto; con límite dura el límite y lleva su señal', () {
    final abierto = fasesDe(_t(TipoTemporizador.forTime)).single;
    expect(abierto.abierta, isTrue);
    expect(duracionTotalSeg(_t(TipoTemporizador.forTime)), isNull);
    final conTope = fasesDe(_t(TipoTemporizador.forTime, limite: 600, senal: 60)).single;
    expect(conTope.abierta, isFalse);
    expect(conTope.segundos, 600);
    expect(conTope.senalCadaSeg, 60);
  });

  test('EMOM Death By no tiene fin fijo', () {
    final t = _t(TipoTemporizador.emom, deathBy: true);
    expect(duracionTotalSeg(t), isNull);
    expect(fasesDe(t), hasLength(maxRondasDeathBy));
    expect(fasesDe(t).first.rondas, 0);
  });

  test('mix encadena bloques, los repite y usa su etiqueta', () {
    final mix = _t(TipoTemporizador.mix, rondas: 2, bloques: [
      const Temporizador(id: '', nombre: 'Remo', tipo: TipoTemporizador.trabajo, trabajoSeg: 60),
      const Temporizador(id: '', nombre: '', tipo: TipoTemporizador.countdown, trabajoSeg: 30),
    ]);
    expect(fasesDe(mix).map((f) => f.etiqueta), ['Remo · Trabajo', 'Descanso', 'Remo · Trabajo', 'Descanso']);
    expect(duracionTotalSeg(mix), 180);
  });

  test('validaciones de cada modo', () {
    expect(_t(TipoTemporizador.forTime, trabajo: 0).validar(), isEmpty);
    expect(_t(TipoTemporizador.amrap, trabajo: 0).validar(), [TimerProblem.workNotPositive]);
    expect(_t(TipoTemporizador.forTime, limite: 0).validar(), [TimerProblem.capNotPositive]);
    expect(_t(TipoTemporizador.mix).validar(), [TimerProblem.blocksEmpty]);
    expect(
      _t(TipoTemporizador.mix, bloques: [_t(TipoTemporizador.mix, bloques: [_t(TipoTemporizador.amrap)])]).validar(),
      [TimerProblem.nestedMix],
    );
    expect(_t(TipoTemporizador.amrap, series: 0).validar(), [TimerProblem.setsNotPositive]);
    const bloque = Temporizador(id: '', nombre: '', tipo: TipoTemporizador.trabajo, trabajoSeg: 30);
    expect(bloque.validar(comoBloque: true), isEmpty);
    expect(bloque.validar(), [TimerProblem.nameEmpty]);
  });

  test('viaja ida y vuelta por JSON con sus opciones y bloques', () {
    final t = _t(TipoTemporizador.mix, rondas: 2, bloques: [
      _t(TipoTemporizador.forTime, limite: 600, senal: 60, series: 2, entre: 30),
      _t(TipoTemporizador.emom, deathBy: true),
    ]);
    final copia = Temporizador.fromJson(t.toJson());
    expect(copia.bloques.first.limiteSeg, 600);
    expect(copia.bloques.first.senalCadaSeg, 60);
    expect(copia.bloques.first.series, 2);
    expect(copia.bloques.last.deathBy, isTrue);
  });
}
