/// Datos iniciales, portados de `reference/Esquema.gs`. Los usa `bin/sembrar.dart`.
library;

import 'package:maktub_core/maktub_core.dart';

const _p = Categoria.primario;
const _s = Categoria.secundario;
const _a = Categoria.accesorio;
const _c = Categoria.calentamiento;
const _e = Categoria.estiramiento;
const _sq = Basico.sentadilla;
const _dl = Basico.pesoMuerto;
const _bp = Basico.bench;

Ejercicio _ej(String id, String nombre, Categoria c, [Basico? ref, String? notas]) =>
    Ejercicio(id: id, nombre: nombre, categoria: c, referencia: ref, notas: notas);

final catalogoInicial = <Ejercicio>[
  // primarios: los tres básicos y sus variantes
  _ej('sq_espalda', 'Sentadilla de espalda', _p, _sq, 'basico'),
  _ej('dl_convencional', 'Peso muerto', _p, _dl, 'basico'),
  _ej('bp_plano', 'Bench press', _p, _bp, 'basico'),
  _ej('sq_frontal', 'Sentadilla frontal', _p, _sq, 'variante'),
  _ej('sq_zercher', 'Zercher squat', _p, _sq, 'variante'),
  _ej('sq_pausa', 'Sentadilla con pausa', _p, _sq, 'variante'),
  _ej('dl_deficit', 'Peso muerto en deficit', _p, _dl, 'variante'),
  _ej('bp_pausa', 'Bench press con pausa', _p, _bp, 'variante'),
  // secundarios del bloque principal
  _ej('mil_press', 'Press militar', _s, _bp),
  _ej('push_press', 'Push press', _s, _bp),
  _ej('bp_inclinado', 'Press inclinado', _s, _bp),
  _ej('rem_barra', 'Remo con barra', _s, _bp),
  _ej('dl_rumano', 'Peso muerto rumano', _s, _dl),
  _ej('good_morning', 'Good morning', _s, _dl),
  _ej('hip_thrust', 'Hip thrust', _s, _dl),
  _ej('prensa', 'Prensa de piernas', _s, _sq),
  _ej('bulgaras', 'Bulgaras', _s, _sq),
  _ej('zancadas', 'Zancadas con mancuernas', _s, _sq),
  // accesorios: kilaje fijo por atleta
  _ej('curl_barra', 'Curl de biceps con barra', _a, null, 'brazos'),
  _ej('curl_martillo', 'Curl martillo', _a, null, 'brazos'),
  _ej('tri_polea', 'Extension de triceps en polea', _a, null, 'brazos'),
  _ej('arnold_press', 'Arnold press', _a, null, 'hombros'),
  _ej('elev_lateral', 'Elevaciones laterales', _a, null, 'hombros'),
  _ej('elev_frontal', 'Elevaciones frontales', _a, null, 'hombros'),
  _ej('face_pull', 'Face pull', _a, null, 'hombros'),
  _ej('shrugs', 'Shrugs', _a, null, 'hombros'),
  _ej('renegade_row', 'Renegade row', _a, null, 'espalda'),
  _ej('dumbbell_row', 'Remo con mancuerna', _a, null, 'espalda'),
  _ej('tbar_row', 'T-bar row', _a, null, 'espalda'),
  _ej('rem_polea', 'Remo en polea', _a, null, 'espalda'),
  _ej('jalon_pecho', 'Jalon al pecho', _a, null, 'espalda'),
  _ej('escapular_pull', 'Escapular pull ups', _a, null, 'espalda'),
  _ej('push_ups', 'Push ups', _a, null, 'pecho'),
  _ej('aperturas', 'Aperturas con mancuernas', _a, null, 'pecho'),
  _ej('dumbbell_press', 'Press con mancuernas', _a, null, 'pecho'),
  // calentamientos: referencia = a qué primario acompañan
  _ej('cal_sq', 'Movilidad de cadera y tobillo', _c, _sq),
  _ej('cal_dl', 'Movilidad de cadera y espalda', _c, _dl),
  _ej('cal_bp', 'Movilidad de hombro y escapula', _c, _bp),
  _ej('cal_aprox', 'Series de aproximacion', _c, null, 'sirve para cualquier dia'),
  // estiramientos
  _ej('est_sq', 'Estiramiento de cuadriceps y aductores', _e, _sq),
  _ej('est_dl', 'Estiramiento de isquios y lumbar', _e, _dl),
  _ej('est_bp', 'Estiramiento de pectoral y hombro', _e, _bp),
];

const _cd = TipoTemporizador.countdown;

const temporizadoresIniciales = <Temporizador>[
  Temporizador(id: 'desc_90', nombre: 'Descanso 1:30', tipo: _cd, trabajoSeg: 90),
  Temporizador(id: 'desc_120', nombre: 'Descanso 2 min', tipo: _cd, trabajoSeg: 120),
  Temporizador(id: 'desc_180', nombre: 'Descanso 3 min', tipo: _cd, trabajoSeg: 180),
  Temporizador(id: 'desc_240', nombre: 'Descanso 4 min', tipo: _cd, trabajoSeg: 240),
  Temporizador(id: 'desc_300', nombre: 'Descanso 5 min', tipo: _cd, trabajoSeg: 300),
  Temporizador(id: 'cuenta_4', nombre: 'Cuenta regresiva 4 min', tipo: _cd, trabajoSeg: 240),
  Temporizador(id: 'cuenta_5', nombre: 'Cuenta regresiva 5 min', tipo: _cd, trabajoSeg: 300),
  Temporizador(id: 'emom_10', nombre: 'EMOM 10 minutos', tipo: TipoTemporizador.emom, trabajoSeg: 60, rondas: 10),
  Temporizador(id: 'emom_15', nombre: 'EMOM 15 minutos', tipo: TipoTemporizador.emom, trabajoSeg: 60, rondas: 15),
  Temporizador(
    id: 'tabata',
    nombre: 'Tabata 20/10 x8',
    tipo: TipoTemporizador.tabata,
    trabajoSeg: 20,
    descansoSeg: 10,
    rondas: 8,
  ),
];

const wodsIniciales = <Wod>[
  Wod(id: 'wod_amrap5', nombre: 'AMRAP 5 min', formato: 'amrap', temporizador: 'cuenta_5',
      descripcion: 'Repetir hasta que se termine el tiempo, sin descanso.'),
  Wod(id: 'wod_amrap4', nombre: 'AMRAP 4 min', formato: 'amrap', temporizador: 'cuenta_4',
      descripcion: 'Repetir hasta que se termine el tiempo, sin descanso.'),
  Wod(id: 'wod_tabata', nombre: 'Tabata', formato: 'tabata', temporizador: 'tabata',
      descripcion: '8 rondas de 20 segundos de trabajo y 10 de descanso, alternando dos ejercicios.'),
  Wod(id: 'wod_emom10', nombre: 'EMOM 10 min', formato: 'emom', temporizador: 'emom_10',
      descripcion: 'Al inicio de cada minuto, las repeticiones indicadas.'),
  Wod(id: 'wod_fran', nombre: 'Fran', formato: 'for_time', descripcion: '21-15-9 de thrusters y toes to bar.'),
  Wod(id: 'wod_annie', nombre: 'Annie fixed', formato: 'for_time',
      descripcion: '50-40-20-10 de sit ups y jumping jacks.'),
];

const atletasIniciales = <Atleta>[
  Atleta(id: 'a1', nombre: 'Andi'),
  Atleta(id: 'a2', nombre: 'Ari'),
];

/// RMs del test de febrero 2026 (ver reference/DISENO.md): [atleta, básico, kilos].
final rmsIniciales = <(String, Basico, double)>[
  ('a1', _sq, 80), ('a1', _dl, 95), ('a1', _bp, 60),
  ('a2', _sq, 70), ('a2', _dl, 95), ('a2', _bp, 55),
];
final fechaRmsIniciales = DateTime.utc(2026, 2, 1);

// ---------- plan de ejemplo ----------

List<SeriePlan> _series(List<(int, double?)> s) => [for (final (reps, pct) in s) SeriePlan(reps: reps, pct: pct)];

final _seriesEjemplo = {
  _p: {
    Variante.descarga: _series([(8, 60), (5, 65), (3, 70), (3, 70), (3, 70)]),
    Variante.carga: _series([(8, 65), (5, 72.5), (3, 80), (3, 85), (3, 85), (3, 85)]),
  },
  _s: {
    Variante.descarga: _series([(8, 40), (8, 40), (8, 40)]),
    Variante.carga: _series([(6, 50), (6, 50), (6, 50), (6, 50)]),
  },
  _a: {
    Variante.descarga: _series([(12, null), (12, null)]),
    Variante.carga: _series([(10, null), (10, null), (10, null)]),
  },
};

const _temporizadorEjemplo = {_p: 'desc_180', _s: 'desc_120', _a: 'desc_90'};

PlanDia _diaEjemplo(int dia, String primario, String secundario, List<List<String>> grupos, String? wod) {
  ContenidoVariante contenido(Variante v) => ContenidoVariante(
        wod: wod,
        ejercicios: [
          for (final (i, (ej, cat)) in [(primario, _p), (secundario, _s)].indexed)
            Prescripcion(
              bloque: Bloque.principal,
              orden: i + 1,
              ejercicio: ej,
              series: _seriesEjemplo[cat]![v]!,
              temporizador: _temporizadorEjemplo[cat],
            ),
          for (final (g, grupo) in grupos.indexed)
            for (final (i, ej) in grupo.indexed)
              Prescripcion(
                bloque: Bloque.cierre,
                grupo: g + 1,
                orden: i + 1,
                ejercicio: ej,
                series: _seriesEjemplo[_a]![v]!,
                temporizador: _temporizadorEjemplo[_a],
              ),
        ],
      );

  // carga2 no se siembra: por defecto la semana 3 repite carga.
  return PlanDia(
    dia: dia,
    primario: primario,
    variantes: {for (final v in [Variante.descarga, Variante.carga]) v: contenido(v)},
  );
}

Plan planDeEjemplo(DateTime inicio) => Plan(
      id: 'plan_1',
      nombre: 'Plan inicial',
      activo: true,
      inicio: inicio,
      dias: [
        _diaEjemplo(1, 'sq_espalda', 'zancadas', [['elev_lateral', 'face_pull', 'curl_barra']], null),
        _diaEjemplo(2, 'bp_plano', 'mil_press', [['tri_polea', 'aperturas']], null),
        _diaEjemplo(3, 'dl_convencional', 'rem_barra', [['jalon_pecho', 'rem_polea', 'shrugs']], 'wod_tabata'),
      ],
    );
