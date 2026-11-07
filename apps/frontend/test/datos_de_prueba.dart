import 'package:maktub_core/maktub_core.dart';

/// Un plan de un día con rampa de sentadilla y una biserie de accesorios.
SeguimientoSnapshot snapshotDePrueba({List<SesionRegistrada> sesiones = const []}) => SeguimientoSnapshot(
      atletas: const [
        Atleta(id: 'a1', nombre: 'Andi', rms: {Basico.sentadilla: 80}, pesosAccesorios: {'curl': 12}),
        Atleta(id: 'a2', nombre: 'Ari', rms: {Basico.sentadilla: 70}),
      ],
      ejercicios: const {
        'sq': Ejercicio(id: 'sq', nombre: 'Sentadilla', categoria: Categoria.primario, referencia: Basico.sentadilla),
        'curl': Ejercicio(id: 'curl', nombre: 'Curl', categoria: Categoria.accesorio),
        'face': Ejercicio(id: 'face', nombre: 'Face pull', categoria: Categoria.accesorio),
        'cal_sq': Ejercicio(id: 'cal_sq', nombre: 'Movilidad cadera', categoria: Categoria.calentamiento, referencia: Basico.sentadilla),
        'cal_bp': Ejercicio(id: 'cal_bp', nombre: 'Movilidad hombro', categoria: Categoria.calentamiento, referencia: Basico.bench),
        'cal_aprox': Ejercicio(id: 'cal_aprox', nombre: 'Aproximación', categoria: Categoria.calentamiento),
      },
      temporizadores: const {
        'desc_90': Temporizador(id: 'desc_90', nombre: 'Descanso 1:30', tipo: TipoTemporizador.countdown, trabajoSeg: 90),
      },
      plan: Plan(
        id: 'p1',
        nombre: 'Plan de prueba',
        activo: true,
        inicio: DateTime.utc(2026, 11, 2),
        dias: const [
          PlanDia(dia: 1, primario: 'sq', variantes: {
            Variante.descarga: ContenidoVariante(ejercicios: [
              Prescripcion(bloque: Bloque.cierre, grupo: 1, orden: 2, ejercicio: 'face', series: [SeriePlan(reps: 12)]),
              Prescripcion(bloque: Bloque.cierre, grupo: 1, orden: 1, ejercicio: 'curl', series: [SeriePlan(reps: 12), SeriePlan(reps: 12)], temporizador: 'desc_90'),
              Prescripcion(
                bloque: Bloque.principal,
                orden: 1,
                ejercicio: 'sq',
                series: [SeriePlan(reps: 8, pct: 30), SeriePlan(reps: 3, pct: 0.8)],
              ),
            ]),
            Variante.carga: ContenidoVariante(ejercicios: [
              Prescripcion(bloque: Bloque.principal, orden: 1, ejercicio: 'sq', series: [SeriePlan(reps: 3, pct: 85)]),
            ]),
          }),
        ],
      ),
      sesiones: sesiones,
    );
