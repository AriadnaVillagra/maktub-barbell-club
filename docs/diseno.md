# Diseño — Maktub Barbell Club

Documento vivo. Describe cómo queremos que funcione la app y la divide en features
para planificar el desarrollo. Estado: borrador con las preguntas de diseño cerradas,
2026-11-07; actualizado el 2026-11-21 con lo que se decidió durante M1. El registro de decisiones
está en la sección 12.

**No es un port.** La app de Apps Script en `reference/` replica un patrón de entrenamiento
específico: estiramiento → calentamiento → principal → final → WoD, con semanas
descarga/carga fijas y dos atletas. Esta app es una iteración y la referencia es eso, una
referencia: sirve para rescatar reglas que ya probamos (sección 11) y como fuente del historial
a migrar. [reference/DISENO.md](../reference/DISENO.md) sigue siendo la fuente del porqué de
esas reglas y de las rarezas de los datos viejos.

---

## 1. Visión

Maktub Barbell Club es una app de entrenamiento de levantamiento de pesas y de gimnasio en
general. Tiene dos modos:

- **Planificación**: el coach diseña planes, mantiene el catálogo de ejercicios y las
  referencias de cada atleta (RMs, marcas). Se usa con tiempo, normalmente fuera del gimnasio.
- **Entrenamiento**: un grupo de atletas ejecuta un día de un plan. La app dice qué toca, a
  quién y con cuánto peso o qué ritmo, toma los tiempos y registra lo hecho. Se usa en el
  gimnasio, con el celular en la mano y entre series.

Sobre lo registrado, la app ofrece **reportes**: cómo progresan los atletas, qué músculos y
patrones trabajaron más, dónde tienen dificultades y cuánto cumplen el plan. Y entiende los
**planes de test**, que no buscan entrenar sino producir referencias nuevas (RMs, marcas).

Es una **PWA en Flutter**, con backend en **Dart Frog** y base de datos **MongoDB**. **Varios
dispositivos leen y escriben contra el mismo backend y se sincronizan al instante**: lo que un
atleta marca en su celular aparece en el de los demás y en una tablet compartida, si la hay.

Empezamos con un grupo chico (Andi, Ari y algunos más), pero el modelo está pensado para
**varios clubes** desde el primer día.

## 2. Principios

1. **Estructura configurable, no fija.** Cuántos bloques tiene un día, qué es cada bloque y
   cómo se ejecuta se decide al planificar. El código no conoce "calentamiento" ni
   "bloque final".
2. **El contenido es dato.** Ejercicios, categorías, temporizadores, formatos de WoD y
   equipo se editan desde la app, no en el código.
3. **El peso es una medida entre otras.** Un ejercicio puede medirse en kilos, reps, tiempo,
   distancia, calorías o una combinación de ellas. El modelo no supone series × reps × kg.
4. **El historial no miente.** Cada registro guarda lo que se hizo en valores absolutos, más
   una referencia estable a la referencia del atleta y al ejercicio que se usaron. Editar un
   plan, subir un RM o archivar un ejercicio no cambia el pasado.
5. **Multi-atleta de primera clase.** Que varios atletas entrenen juntos el mismo día es el
   caso normal, no una excepción.
6. **Multi-club en los datos, un club en la UI.** Todo pertenece a un club. Al principio la
   interfaz asume un solo club, pero los datos no.
7. **Reglas puras y compartidas.** Los cálculos (cargas, ubicación en el ciclo, orden de
   ejecución, fases de temporizador) viven en `maktub_core`, sin I/O, y los usan el frontend
   y el backend por igual.

## 3. Modelo del dominio

### 3.1 Club, usuarios y roles

- **Club**: la unidad de aislamiento. Catálogo propio, planes, atletas, sesiones y registros
  pertenecen a un club. Un club nuevo **se pide y se aprueba**: quien entra con Google sin cuenta
  pide un club y ve "Tu pedido está en revisión" hasta que un administrador de plataforma lo aprueba
  o lo rechaza desde la app (sin emails). Al aprobarse se crean el club, el usuario y su membresía:
  queda como administrador del club, coach y atleta. El catálogo base no se copia: el club ya lo ve
  (3.2).
- **Pedido de club**: email (probado por Google), nombre de quien pide, nombre del club, nota
  opcional, estado *pendiente*, *aprobado* o *rechazado*, el club creado al aprobarse, y quién y
  cuándo lo revisó. Es dato de plataforma. Un pedido rechazado queda como historial y su autor puede
  pedir de nuevo.
- **Club personal**: todo usuario tiene uno implícito, que la UI presenta como "mi
  entrenamiento". Ahí puede seguir los **planes por defecto** de la plataforma y registrar sus
  referencias, pero no planificar: para eso tiene que unirse a un club o pedir uno. Así el modelo
  sigue teniendo un solo camino (todo pertenece a un club) y el uso individual no es un caso aparte.
- **Usuario**: una persona con login propio, con **Google o con email y contraseña**. Las dos
  formas con el mismo email son el mismo usuario. **No existen atletas sin usuario.**
- **Membresía**: usuario × club × roles. Un usuario puede pertenecer a varios clubes, con roles
  distintos en cada uno. Por ahora se entra a un club por **alta del administrador del club**, con el
  email de la persona y sus roles; las invitaciones por link o código quedan para el resto de F1.
  - **Coach**: planifica y asigna; crea, edita, archiva y elimina los ejercicios del club; gestiona
    referencias, factores y kilajes; elimina planes; lee la ficha y el historial de todos los atletas;
    decide si un día perdido se recupera o queda como falta. Qué planes de otros coaches ve depende
    de la visibilidad del plan (3.4).
  - **Atleta**: ejecuta y registra lo suyo, y también lo de sus compañeros de la misma sesión.
  - **Administrador del club** (`admin_club`): se suma a los otros roles. Da de alta miembros y
    cambia sus roles; mantiene categorías, temporizadores y equipo del club (los ejercicios también,
    como el coach); elimina cualquier plan del club y, si también es coach, alcanza los privados de
    otros coaches. Lee la ficha y el historial de los atletas, pero sin el rol de coach no edita
    referencias ni planifica.
  - Una membresía puede tener varios roles: un coach que también entrena. Un club siempre tiene al
    menos un administrador y un coach activos.
- **Administrador de plataforma**: nosotros. Mantiene lo que es de todos: el catálogo base, las
  categorías base, los grupos musculares y patrones base, y la biblioteca de planes por defecto.
  Revisa los pedidos de club. Esa marca **no da permisos dentro de un club**: para eso hace falta una
  membresía.
- **Atleta**: el perfil de entrenamiento de un miembro dentro del club. Todo registro sabe
  qué usuario lo escribió.

### 3.2 Catálogo

**Dos niveles**: un **catálogo base** de plataforma que todos los clubes ven y usan tal cual, más
los **ejercicios propios** de cada club. Un club no modifica ni oculta los base; si uno no le sirve,
crea uno propio. Los base los edita solo el administrador de plataforma, y un cambio en uno se ve en
todos los clubes (los registros conservan el nombre que tenía al momento). Un club nuevo no recibe
una copia: ve el catálogo base desde el primer día. En la app, lo base se marca **Default** y lo del
club **Custom**. Los planes por defecto usan solo ejercicios base. La semilla del catálogo base son
los ejercicios de `reference/` (catálogo e historial importado), completados con músculos y patrón,
más un set general de gimnasio y cardio.

**Ejercicio**: entrada del catálogo (base o del club), con:

- nombre;
- **categorías**: una o varias; definen en qué bloques se puede elegir;
- **métricas**: qué se mide (ver 3.5). Si al planificar se le carga peso a un ejercicio que no lo
  medía, el ejercicio pasa a medir carga (ver 4);
- **barra** (opcional): con cuál barra del inventario se carga, o que no usa barra (mancuernas). Sin
  barra indicada, o si el club no la tiene, se usa la barra por defecto del equipo;
- **patrón de movimiento**: sentadilla, bisagra, empuje horizontal/vertical, tracción
  horizontal/vertical, core, cardio…;
- **grupos musculares con peso**: principales (100 %) y secundarios (50 %). Una sentadilla
  suma una serie a cuádriceps y media a glúteos. Patrón y músculos alimentan el balance muscular
  de los reportes (sección 8);
- **referencia de carga** (opcional): si se carga por % de su propio RM o del de otro
  ejercicio (Press militar → bench);
- **relaciones de sugerencia**: qué ejercicios suele acompañar, por ejemplo "movilidad de
  cadera" acompaña a sentadilla. Las usa el editor (ver 4);
- estado **activo / archivado**. Un ejercicio usado en algún plan o registro **no se borra,
  se archiva**: deja de aparecer en el menú, pero los registros viejos lo siguen resolviendo.

**Categoría**: etiqueta como "fuerza", "accesorio", "movilidad", "cardio" o "wod". Sirve para
filtrar qué ejercicios puede tener un bloque. Hay un **set base** de plataforma y cada club puede
**agregar las suyas**.

**Grupos musculares y patrones**: una lista base de plataforma (unos 12 grupos: cuádriceps,
isquios, glúteos, pecho, dorsales, hombro, bíceps, tríceps, core…; y los patrones) que **cada club
puede extender, pero no borrar ni renombrar**. Un club puede agregar grupos nuevos o **subdividir**
uno base: "deltoides lateral" como hijo de "hombro". Los ejercicios base suman al grupo base y los
propios pueden sumar al hijo. Los reportes agregan hacia arriba, así que todo sigue siendo
comparable al nivel base.

**Temporizador**: preset reutilizable (countdown, EMOM, tabata, AMRAP, for time, intervalos).
Se expande a una lista de fases. Ver sección 6.

**Equipo**: el inventario del club (uno por club), en datos: barras y pares de discos, cada fila con
su peso y su cantidad. La barra por defecto es la más pesada. Definen qué pesos son cargables con
cada barra; un club que no editó su equipo usa el estándar (barra de 20 y un par de 20, 15, 10, 5,
2.5, 1.5 y 1.25).

### 3.3 Referencias del atleta

Cada referencia es **un documento propio con id e historial**: atleta, ejercicio, tipo, valor,
fecha y origen (testeado, estimado o importado).

| Tipo | Para qué ejercicios | Ejemplo de prescripción |
|---|---|---|
| `rm` | cualquiera que se mida por carga × repeticiones; los básicos siempre | 80 % del RM |
| `marca` | cardio: mejor tiempo para una distancia o mejor distancia en un tiempo | 5 km al 90 % de la marca |
| `ritmo` | cardio: min/km, min/500 m | ritmo + 15 s, o un % del ritmo |
| `fc_max` / zonas | del atleta, no de un ejercicio | Z2 durante 30 min |

- La **referencia vigente** para una fecha es la última con `fecha ≤ esa fecha`.
- Cada registro guarda el **id y el valor** de la referencia que usó.
- Las referencias con origen *testeado* las crea automáticamente un plan de test (sección 7).
  También se pueden cargar a mano.

**Factor de trabajo**: un porcentaje por atleta y por ejercicio con RM, con historial,
editado por el coach. Sirve para entrenar sobre un máximo menor al testeado: los datos
históricos muestran que Ari carga sobre ~80 % de su RM en sentadilla, ~91 % en peso muerto y
~90 % en bench. **Solo aplica a RMs**; el cardio se prescribe directo contra marca o ritmo.
**Cuando entra un RM nuevo, el factor de ese ejercicio vuelve a 100 %.** Si hace falta, el coach
lo vuelve a bajar.

**Kilaje fijo**: peso por atleta y por ejercicio para lo que no carga por porcentaje, como
las mancuernas.

### 3.4 Plan y asignación

```
Plan
├── modelos de semana: A, B, C…          (cada uno con 1 a 7 días)
├── asignación: semana 1→A, 2→B, 3→B, 4→A (4 posiciones; un modelo puede repetirse)
└── se repite en ciclos idénticos, sin fin

Asignación de plan
└── plan × atletas (cada uno con desde–hasta) × fecha de inicio (calendario común)
```

- **Tipo de plan**: *regular* (entrena, se repite sin fin), *de test* (dura un ciclo y produce
  referencias nuevas; ver sección 7) o *histórico* (reconstruido al migrar lo registrado antes de la
  app; no se vuelve a asignar y puede no tener % ni reps, porque el registro viejo no los tenía).
- **Borrador y versión publicada**: guardar deja un borrador; publicar exige el plan completo y es
  lo único que ven atletas, sesiones y calendario. Editar un plan asignado no cambia nada hasta volver
  a publicar. Un plan histórico se publica sin %, solo desde el importador. Republicar con una sesión a
  medias no está cubierto: los registros se ubican por posición.
- **Activo o pasado**: lo marca el coach, para separar la lista de planes. Un histórico siempre es
  pasado.
- **Visibilidad** para los otros coaches del club: *privado* (por defecto), *compartido para ver*
  (lo ven, lo copian y lo asignan) o *compartido para editar* (también lo guardan y lo publican). Quien
  lo creó y los administradores del club lo alcanzan entero; eliminarlo y cambiar quién lo ve queda
  para ellos.
- **Copiar como plan nuevo** crea un plan regular en borrador con sus modelos de semana y su
  asignación de semanas. **Eliminar un plan** borra el plan y sus asignaciones; sesiones, registros y
  tiempos de bloque quedan para el historial y los reportes.
- **Plan**: 4 semanas. Cada semana usa un **modelo de semana**. Las 4 pueden usar el mismo
  modelo, usar 4 distintos o repetir alguno. El patrón de la referencia
  (descarga/carga/carga/descarga) es solo una asignación posible: `A, B, B, A`.
- **Ciclo**: cada vuelta completa a las 4 semanas. Un plan **se repite sin fin**, hasta que el
  coach lo desactiva o lo reemplaza, y **todos los ciclos son idénticos**. La progresión sale de
  actualizar referencias y factores, o de editar el plan. El número de ciclo es parte de la
  clave del registro: sin él, el ciclo 2 pisaría al 1.
- **Modelo de semana**: nombre más una lista de **días** (1 a 7).
- **Día**: nombre opcional más una **lista ordenada de bloques**. Cuántos hay y cuáles son se
  decide al planificar.
- **Bloque**:
  - nombre ("Movilidad", "Fuerza", "Triserie de hombros", "WoD");
  - **categoría**: filtra los ejercicios elegibles;
  - **modo de ejecución**: secuencial, circuito o por tiempo (ver 5.1);
  - **modo de atletas por defecto**: simultáneo o por turnos (se puede cambiar en vivo, ver 5.1);
  - temporizador de descanso por defecto, o temporizador del bloque si es por tiempo;
  - lista ordenada de **prescripciones**.
- **Prescripción**: un ejercicio más sus **series**, una por una. Cada serie declara sus
  objetivos en las métricas del ejercicio: reps, % del RM, kg, tiempo, distancia, % de la
  marca, ritmo, zona… Las rampas (8 @ barra → 5 → 3 → 3×3) se representan así, con cada serie
  distinta. Opcionales: nota/RPE (texto libre, no se interpreta), temporizador propio y una barra que
  pisa la del ejercicio.
- **Kilos por atleta en la serie** (`porAtleta`): se congelan al planificar, para cada atleta de la
  asignación.
  - En una serie por %, el coach escribe % o kg, y cada atleta con RM queda con su % y sus kg
    (con su factor de trabajo, como en F4). La sesión propone esos kg con el ajuste del día.
  - En un plan de varios atletas, una serie en kilos pide un peso para cada uno, sin valor general;
    las reps son las mismas para todos. La sesión propone esos kilos tal cual, sin ajuste del día.
    Publicar exige el de cada atleta; un plan sin asignación usa un solo peso.
  - Un atleta sumado después recibe su kilaje fijo o nada, y republicar pide cargar el suyo.
- **Asignación**: el coach asigna un plan a una **lista de atletas** con una fecha de inicio, y
  comparten el calendario. Cada atleta tiene un período en la asignación (desde–hasta): el coach suma
  o saca atletas sin terminar el plan, quien sale conserva sus días anteriores, y quien vuelve abre
  otro período. Un plan puede ser de varios atletas o de uno solo; los grupos ya no se usan para
  asignar. **Un atleta puede estar en cualquier cantidad de
  asignaciones activas**, aunque caigan el mismo día (ej. fuerza lunes y miércoles, otro plan los
  sábados, o un plan propio junto al del grupo); si hay dos en un día, la sesión ofrece una por plan.
  Una asignación puede estar *activa*, *pausada* (mientras se hace un plan de test) o *terminada*.

### 3.5 Métricas de un ejercicio

Un ejercicio declara qué se mide y la serie fija un objetivo en esas métricas:

| Métrica | Ejemplos | Objetivo en el plan | Registro |
|---|---|---|---|
| Carga por % de RM | Sentadilla, Press militar | `pct` del plan | kg reales, id del RM, factor, % del plan y % real |
| Carga fija | Curl con mancuerna | kg por atleta | kg reales |
| Peso corporal (± lastre) | Dominadas, fondos | lastre opcional | lastre |
| Repeticiones | casi todo | reps, o "máx." | reps hechas |
| Tiempo | Plancha, correr 10 min | segundos, o % de la marca | segundos, id de la marca |
| Distancia | Correr, remo | metros, o % de la marca | metros, id de la marca |
| Ritmo | Correr, remo | ritmo absoluto o relativo al de referencia | ritmo logrado, id del ritmo |
| Zona cardíaca | Cardio continuo | zona | FC, si se carga a mano |
| Calorías | Bici de aire | cal | cal |
| Intento | Test tipo torneo | aproximaciones + 3 intentos | kg, válido / nulo |

**Esfuerzo percibido**: cualquier serie puede registrar opcionalmente el esfuerzo. El atleta lo
carga como **RPE (6–10, con medios puntos) o como RIR (0–5)**, lo que prefiera, y se guarda
normalizado como RPE (`RPE = 10 − RIR`). La nota del plan sigue siendo texto libre.

Un ejercicio combina métricas: correr usa distancia y tiempo, y la serie fija una de las dos
como objetivo. "Por series" deja de ser obligatorio: un ejercicio por tiempo puede tener una
sola "serie" de 20 minutos.

### 3.6 Sesión y registro

- **Sesión**: la ejecución de un día de una asignación (plan, ciclo, semana, día) en una
  fecha, con los **atletas presentes**. Una sesión ejecuta **un solo plan**. Se sigue desde varios
  dispositivos a la vez.
  - **No se abre a mano**: se crea con la primera escritura (una serie, un valor, un ajuste, una nota
    o "Comenzar" del modo guiado), y cada atleta que escribe se suma a los presentes. Los presentes
    son de entre los atletas que la asignación tiene ese día. Antes de existir, la app la busca sin
    crearla.
  - **Nota** de la sesión, libre y compartida por todos.
  - **Secuencia**: el número del último cambio de la sesión (`secuencia`) y el del último cambio a
    la sesión misma, es decir nota, presentes o pasada guiada (`secuenciaSesion`). Ver sección 9.
  - **Pasada guiada** (opcional): el estado del modo guiado, el mismo en todos los dispositivos
    (ver 5.4).
- **Estado de un día por atleta**: sale de sus series contra las planificadas del día: *hecho* con
  todas, *en curso n/m* con algunas y *pendiente* sin ninguna. Es por atleta: la serie de uno no
  marca el día del otro. Rehacer un día ya hecho en otra fecha **edita la sesión original**: no hay
  "recuperado" por eso. Para después de M1 quedan *recuperado* (lo hizo después, fuera de la sesión
  grupal) y *falta*, que decide el coach.
- **Registro**: lo hecho, **una entrada por atleta, ejercicio y serie** (o por ronda/resultado en
  bloques por tiempo). Desnormalizado a propósito: guarda los valores absolutos, **el objetivo que
  tenía la serie**, el id y el valor de la referencia, el factor, los porcentajes, el RPE si se
  cargó, el nombre del ejercicio al momento, la posición en el plan (bloque, prescripción, serie) y
  quién lo escribió. Guardar el objetivo junto a lo hecho es lo que permite medir dificultades sin
  reconstruir el plan. Nunca punteros que cambien de
  significado. Además:
  - **nota** del ejercicio, en la primera serie (un ejercicio sin series no tiene nota);
  - **secuencia**: el número del cambio de la sesión que lo modificó por última vez;
  - **estimada**: series cargadas por el importador con los kilos que propone la app (RM × %), no
    registradas por nadie. Solo el importador la pone; cualquier escritura desde la app la saca.
- **Tiempo de bloque**: inicio, fin y duración de un bloque hecho en el modo guiado, con el nombre
  del bloque al momento, el modo de atletas, los atletas y si se interrumpió. Un id por bloque y
  pasada, para que dos dispositivos lo escriban una sola vez. La hoja Tiempos de la referencia se
  importó acá.
- **Invariante** en cargas por porcentaje: `rm × pct_real ≈ kg`, con
  `pct_real = factor × pct_plan`. Si el atleta escribió los kilos a mano, los dos % se derivan de
  ellos.

## 4. Modo planificación

Reservado al coach y al administrador del club, cada uno con lo suyo (3.1).

1. **Catálogo**: crear, editar, archivar y eliminar ejercicios (coach o administrador); definir
   métricas, barra, referencia de carga y relaciones de sugerencia. Categorías, equipo y
   temporizadores, solo el administrador del club.
2. **Atletas y referencias**: alta de miembros (administrador del club); registrar RMs, marcas,
   ritmos y FC (con historial); factores de trabajo; kilajes fijos. El administrador sin rol de coach
   solo lee fichas e historial.
3. **Editor de plan**:
   - crear modelos de semana y asignarlos a las 4 semanas;
   - por modelo: agregar, quitar y reordenar días;
   - por día: agregar, quitar y reordenar bloques; elegir nombre, categoría, modo de ejecución y
     modo de atletas por defecto;
   - por bloque: elegir ejercicios del menú filtrado por la categoría (como en la referencia) y
     cargar series y objetivos;
   - **sugerencias**: para un bloque, el editor propone ejercicios según los ejercicios principales
     del día, usando las relaciones del catálogo. El coach acepta o no, y el plan guarda lo elegido.
     En la sesión no se rellena nada automáticamente: un bloque vacío queda vacío;
   - **peso en cualquier ejercicio**: toda serie ofrece kilos o %. En blanco es sin peso; si se
     carga, al guardar el plan el ejercicio suma la métrica (con % "Carga (% del RM)", y RM propio si
     mide reps; solo kilos, "Carga fija"). Lo ve solo quien puede escribir ese ejercicio;
   - kilos por atleta (3.4): con % o kg en series por %, y un peso por atleta en series en kilos de
     planes de varios atletas;
   - atajos: duplicar día/bloque/modelo (un día se puede duplicar en otro modelo de semana), generar
     una rampa a partir del % de trabajo, copiar series a otro ejercicio;
   - guardar (borrador) y publicar; marcar activo o pasado; elegir quién lo ve; copiar como plan
     nuevo; eliminar (3.4).
4. **Análisis del plan** mientras se arma (ver 4.1).
5. **Asignar** un plan a atletas con fecha de inicio; sumar o sacar atletas sin terminarlo;
   desactivarlo, reemplazarlo o pausarlo para un plan de test.
6. **Asistencia**: ver días pendientes por atleta y decidir *recuperar* o *falta*.

### 4.1 Análisis del plan

El editor muestra en vivo el volumen y la intensidad del plan que se está armando, y lo compara con
el anterior. Sirve para saber, antes de ejecutar, si un plan es mucho o poco respecto de lo que se
venía haciendo.

**En qué términos**:

- **Relativo, por defecto**: sin atleta, en los términos del plan: series, reps, % medio, reps por
  zona de intensidad, series ponderadas por grupo muscular y por patrón.
- **Proyectado, opcional**: se elige un atleta o un grupo y se ve en kilos (tonelaje), con sus
  referencias y factores vigentes.

**Desglose**: por semana (cómo se mueve la carga entre las 4, ej. `A-B-B-A`), por día y bloque, por
grupo muscular y patrón, y por ejercicio, incluido el agregado por ejercicio de referencia (todo lo
que cuelga del RM de sentadilla, por ejemplo).

**Comparación**, lado a lado y con la diferencia:

- **Plan anterior planificado**: lo que decía el plan previo, en los mismos términos.
- **Plan anterior ejecutado**: lo que realmente se hizo con él, sacado del registro, con ajustes,
  faltas y kilos bajados incluidos. Por defecto se compara el promedio por ciclo, con opción de elegir
  un ciclo puntual.

"Anterior" es el plan que tuvo antes el grupo elegido. Si el plan todavía no tiene grupo, se elige
uno para comparar.

**Un solo motor de métricas**: el análisis del plan y los reportes (sección 8) calculan lo mismo
(series, reps, tonelaje, zonas, balance muscular) sobre una lista de series. En un caso son las
**prescritas** y en el otro las **registradas**. Por eso planificado y ejecutado son comparables
directamente. Ese motor vive en `maktub_core`.

## 5. Modo entrenamiento y modalidades de ejecución

Es donde la referencia más se queda corta. Hoy ejecuta todas las series de un ejercicio antes de
pasar al siguiente, y no distingue cómo se reparten los atletas.

### 5.1 Cómo se recorre un bloque

**Modo de ejecución** (por bloque, fijado en el plan):

| Modo | Orden | Uso típico |
|---|---|---|
| **Secuencial** | todas las series del ejercicio 1, después todas las del 2… | bloque de fuerza, rampas |
| **Circuito / rondas** | serie 1 de cada ejercicio, después serie 2 de cada uno… | biseries, triseries |
| **Por tiempo** | lo manda un temporizador: AMRAP, EMOM, tabata, for time, intervalos | WoD, cardio |

En un circuito con ejercicios de distinta cantidad de series, el que se queda sin series se
saltea en las rondas siguientes.

**Modo de atletas** (el plan propone un default por bloque; **se cambia en vivo** durante la
sesión, según cuántas barras o estaciones haya libres):

| Modo | Qué pasa | Uso típico |
|---|---|---|
| **Simultáneo** | todos hacen el mismo paso a la vez; un solo descanso | accesorios, WoD, cada uno en su estación |
| **Por turnos** | A hace su serie, después B, y así; el descanso de uno es el turno del otro | comparten barra en el bloque principal |

### 5.2 El motor de pasos

El bloque, su modo de ejecución, el modo de atletas vigente y los atletas presentes se expanden a
una **lista plana de pasos**: qué atleta(s), qué ejercicio, qué serie, qué objetivo y qué descanso
sigue. Es la misma idea que los temporizadores (config → lista de fases → un solo motor). La UI
recorre esa lista sin saber de modos. Cambiar el modo de atletas en vivo **recalcula solo lo que
falta del bloque**; lo ya hecho no se toca.

Ejemplo de triserie en circuito, por turnos, con Andi y Ari:

```
R1  Andi·Elev lateral  → Ari·Elev lateral → Andi·Face pull → Ari·Face pull → Andi·Curl → Ari·Curl → descanso
R2  …
```

El mismo bloque en simultáneo:

```
R1  [Andi+Ari]·Elev lateral → [Andi+Ari]·Face pull → [Andi+Ari]·Curl → descanso
```

La lista es la propuesta, no una prisión: se puede saltear, reordenar o marcar fuera de orden, y
el registro guarda lo que se hizo.

### 5.3 En la pantalla

- **Sesión del día y calendario son una pantalla**, con un selector entre las dos vistas. Abre en el
  día que toca: la fecha da ciclo y semana, y el día es el primero de esa semana que el atleta de la primera
  pestaña (el usuario, si está en el plan) no completó; el día 1 si están todos hechos.
  La sesión tiene una pestaña por atleta, y no se eligen presentes (3.6). Cada bloque se colapsa
  desde su cabecera.
- El **calendario** muestra el ciclo con el estado de cada día **por atleta** (*hecho*, *en curso
  n/m*, *pendiente*), con un selector de atleta, en tres vistas que se recuerdan en el dispositivo:
  compacta (solo los ejercicios), tarjetas y detallada.
- Un atleta también puede abrir un día pendiente por su cuenta para **recuperarlo** fuera de la
  sesión grupal, si el coach lo habilitó (después de M1).
- Cada paso muestra, por atleta, el objetivo ya calculado: kg cargables, reps, tiempo, ritmo o
  zona. En cargas por porcentaje se muestra **el % del plan**.
- Ajuste del día: uno por sesión y otro por ejercicio que lo pisa, por atleta. Nunca modifica las
  referencias. Una serie editada a mano no se pisa si después se mueve el ajuste.
- Marcar una serie como hecha la registra, la difunde a los demás dispositivos y dispara el
  descanso que corresponde.
- Una nota por ejercicio y una por sesión. "Volver a lo planificado" es por ejercicio: devuelve kilos
  y reps a lo propuesto y deja las series marcadas como estaban.
- Los temporizadores del club están siempre a mano, también desde el modo guiado.

### 5.4 Modo guiado

"Entrenar" recorre el día con el motor de pasos (5.2), como el modo guiado de la referencia viva:
bloque por bloque con una previa, un paso (una serie) por tarjeta, simultáneo o por turnos, y el
orden (secuencial o circuito) elegido al entrenar, arrancando en el del plan, sin cambiar el plan.
El cambio de modo en vivo recalcula solo lo pendiente. La lista de la sesión queda como vista
general.

- **La pasada es de la sesión**, no del dispositivo: quién entrena, si se rehace el día, inicio y
  fin, y por bloque su estado (*pendiente*, *en curso*, *terminado*, *interrumpido*, *salteado*),
  instantes, modo de atletas, orden, series pasadas y ejercicios dejados. El paso en pantalla no se
  guarda: sale de los registros y de lo ya pasado.
- Se escribe con acciones (comenzar, iniciar, saltar o terminar bloque, pasar series, dejar,
  terminar…) que una regla compartida de `maktub_core` aplica sobre el estado actual, en el servidor
  y en el teléfono. No hay rechazo por versión: una acción que ya no tiene sentido no cambia nada, y
  dos "Comenzar" a la vez quedan en una sola pasada.
- Nunca desmarca: arranca desde lo que falta, porque desmarcar borraría lo del otro teléfono. Una
  serie rehecha se escribe con lo propuesto y pisa la anterior.
- Cada bloque cerrado deja su **tiempo de bloque** (3.6), y el día termina con un resumen.
  "Terminar el día" con un bloque en curso lo cierra como interrumpido.
- Las acciones que se tocan sin querer (saltar ejercicio, saltar bloque, interrumpir) van en
  "Más acciones". Reordenar pasos queda para después.
- **"Atrás"** vuelve a los pasos ya hechos del bloque en curso, uno por vez, para verlos o corregirlos.
  Es local a cada dispositivo: no mueve la pasada ni a los otros teléfonos. Terminar de nuevo un paso
  pisa sus series, sin desmarcar.
- Cada dispositivo **recuerda dónde quedó** (bloque, paso y lo tipeado) aunque se salga a otra
  pantalla o se recargue la PWA. Si la pasada cambió mientras tanto, arranca desde lo que dice ella.

## 6. Temporizadores, cardio y WoD

La referencia los tiene, pero no se probaron bien. Acá son bloques de primera clase.

- **Formatos**: countdown, EMOM, tabata (sin descanso tras la última ronda), AMRAP, for time
  (cronómetro hacia arriba, con tope opcional) e intervalos (trabajo/descanso configurables por
  ronda). El temporizador base `Cronómetro` es el for time sin tope.
- Todos se expanden a **fases de duración fija** (o abiertas, en for time sin tope y Death By, que se cierran con
  "Terminar") que corre un único
  motor. El tiempo se mide **contra el reloj del sistema**, no sumando ticks, para que apagar la
  pantalla no atrase la cuenta.
- **Resultado**: depende del formato. AMRAP registra rondas + reps, for time registra el tiempo,
  y cardio registra distancia, tiempo, ritmo o FC según la métrica. Se guarda por atleta.
- Avisos sonoros y vibración al cambiar de fase, y la pantalla encendida mientras corre. Al ser una
  PWA instalada el soporte es mejor que en una pestaña, pero todo debe fallar en silencio si el
  dispositivo no lo permite.

## 7. Planes de test

El mes en que se establecen referencias nuevas es distinto a los demás: no busca acumular
entrenamiento, busca producir un número. La referencia nunca lo modeló: el test de febrero 2026 se
anotó como un bloque más y los RMs se copiaron a mano.

**Un plan de test es un plan aparte**, de tipo *test*, armado con el mismo editor: semanas de
preparación y una semana con los días de test. Se diferencia de un plan regular en que:

- **dura un ciclo** y termina, no se repite;
- tiene **bloques de test**, cuyo resultado produce una referencia nueva.

**Formatos de test**:

- **Tipo torneo** (fuerza): aproximaciones prescritas y después **3 intentos**: apertura, segundo y
  tercero. El peso de cada intento se elige en el momento según cómo salió el anterior. Cada intento
  se marca **válido o nulo**. El RM nuevo es **el mayor intento válido**; si todos son nulos, queda el
  RM anterior.
- **Cardio**: contrarreloj en una distancia (ej. 5 km) o distancia en un tiempo fijo. Produce una
  marca nueva y el ritmo que se deriva de ella.

**El resultado rige automáticamente**: al registrarse, se crea la referencia nueva con origen
*testeado*, vigente desde la fecha del test, y **el factor de trabajo de ese ejercicio vuelve a
100 %**. Las que no se testearon no cambian.

**Ciclo de vida en el calendario**:

```
asignación regular (activa) ──► pausada ──────────────────────► activa de nuevo, con RMs nuevos
                                   │                              (o terminada, si el coach arma
                                   └─► asignación de test: 1 ciclo ─┘  un plan nuevo)
```

1. El coach asigna el plan de test al grupo. Si el grupo tenía un plan regular, esa asignación
   queda **pausada**.
2. Al terminar el test, el coach elige: **retomar** el plan regular o **asignar un plan nuevo**.
3. Si retoma, **el coach elige la fecha y la semana** desde donde se sigue. El plan regular usa las
   referencias nuevas sin tocar nada, porque la vigencia es por fecha.

## 8. Reportes

Todo se calcula sobre el registro. Por eso el registro guarda el objetivo junto a lo hecho, las
referencias por id y el RPE.

**Acceso**: el coach ve a todos los atletas y puede compararlos; el administrador del club también
los lee; cada atleta ve solo lo suyo.

**Historial por atleta** (ya en M1): las sesiones pasadas del atleta por fecha, de cualquier plan
(también terminados, históricos o eliminados), y al tocar una el detalle con kilos y reps. Una sesión
es del atleta si figura en sus presentes. El detalle usa la versión publicada actual del plan; de un
plan eliminado muestra solo lo registrado. El atleta llega desde su perfil; coach y administrador,
desde la ficha del atleta.

**Análisis**:

| Área | Qué muestra | Sale de |
|---|---|---|
| **Progresión de fuerza** | Referencias a lo largo del tiempo, con los tests marcados; **RM estimado** entre tests a partir de las series registradas (fórmula tipo Epley, que se ajusta con el RPE cuando está) | referencias, series con kg × reps |
| **Volumen e intensidad** | kg × reps y series por ejercicio, semana y ciclo; % real del RM; distribución de series por zona de intensidad | registro con % real |
| **Balance muscular** | Series ponderadas por grupo muscular y por patrón de movimiento; comparación empuje/tracción y pierna/torso | registro + músculos y patrón del catálogo |
| **Dificultades** | Ejercicios donde el atleta no llega al objetivo, baja kilos a mano, usa ajuste < 100 % o registra RPE alto respecto de lo previsto, de forma repetida | objetivo vs. hecho, ajustes, RPE |
| **Adherencia** | Días hechos, recuperados y faltas por atleta y por plan | estado de los días |
| **Cardio** | Marcas y ritmos en el tiempo; resultados de WoD | referencias de cardio, resultados |

**Cómo llegan**:

- **Panel a demanda**: gráficos filtrables por atleta, ejercicio, grupo muscular y período.
- **Resumen de ciclo**: al cerrar cada ciclo de 4 semanas, un resumen por atleta con volumen,
  intensidad, balance, dificultades y adherencia, comparado con el ciclo anterior.
- **Resumen post-sesión**: al terminar una sesión, cada atleta ve lo que hizo contra lo planeado.
- **Exportación a CSV** del historial (decisión P9).

## 9. Multi-dispositivo

- Un solo backend como fuente de verdad. Cualquier dispositivo de un atleta de la asignación puede
  escribir en la sesión del día; la primera escritura la crea (3.6), y mientras no existe la app la
  vuelve a buscar cada 15 s.
- **Tiempo real**: los dispositivos de una sesión abierta reciben los cambios al instante, por
  WebSocket. El backend corre en Cloud Run (P10c), lo que impone estas condiciones:
  - **Reconexión con resincronización**: Cloud Run corta cada WebSocket al llegar a su tiempo
    máximo (hasta 60 min), y una sesión de entrenamiento suele durar más. El cliente reconecta solo
    y pide lo que cambió desde el último evento que recibió. Para eso cada cambio de una sesión
    lleva un número de secuencia. Un corte no se nota en la pantalla y no pierde marcas.
  - **Una sola instancia**: la difusión entre dispositivos se hace en memoria, así que el servicio
    queda fijo en una instancia. La difusión va detrás de una interfaz, para cambiarla por un bus
    (Pub/Sub o similar) si algún día hacen falta más instancias.
  - **Arranque en frío**: sin uso, el servicio se apaga y el primer pedido tarda 1–2 s. La app lo
    absorbe con estados de carga y con el borrador local; nunca bloquea marcar una serie.
  - Un WebSocket abierto cuenta como pedido activo y consume la cuota gratis mientras dura. Para el
    grupo chico debería alcanzar; se verifica con el uso real.
- **Autenticación del canal en vivo**: las APIs de WebSocket y SSE del navegador no permiten
  mandar headers propios, y como app y API están en sitios distintos tampoco hay cookies (P10c, F1).
  El canal se autentica con un **ticket de un solo uso y vida muy corta**, pedido por HTTP con el
  token normal y pasado al abrir la conexión. Nunca se manda el token de acceso en la URL, porque
  queda en los logs.
- **Se escribe por serie y por atleta, no el día entero.** La referencia reemplazaba la sesión
  completa al guardar. Con varios dispositivos registrando a la vez, eso hace que uno pise al otro.
  Escribir a nivel de serie (upsert por `sesión + atleta + bloque + prescripción + serie`) hace que
  las escrituras concurrentes no choquen y que reintentar sea idempotente.
- **Borrador local**: lo marcado se guarda en el dispositivo antes de enviarse. Si no hay señal, se
  encola, se reintenta y se reconcilia al reconectar. Sin señal también se abren el plan, el
  calendario y la sesión de hoy y de los 7 días siguientes, que la app precarga; una sesión creada
  sin señal entra primera en la cola. No buscamos un modo offline completo.

## 10. Features

Unidades de trabajo para planificar. Cada una se puede detallar después como ítem propio.
"Depende de" significa que debe existir antes.

| # | Feature | Alcance | Depende de |
|---|---|---|---|
| F0 | **Fundaciones** | Monorepo, `maktub_core`, Dart Frog + Mongo, cliente HTTP, PWA, navegación entre los dos modos. Despliegue gratis: PWA en GitHub Pages, backend en Google Cloud Run (europe-north1, una instancia, contenedor Docker estándar sin APIs propias de Google), Atlas M0 (Frankfurt), API en `*.run.app`; job programado de Cloud Run con `mongodump` a Cloud Storage. *Hecho (E0 de M1).* | — |
| F17 | **Design system** ([detalle](features/F17-design-system.md)) | Paquete `maktub_ui`: tokens en tres capas sobre Material 3, temas oscuro y claro, densidades planificación/entrenamiento, componentes base y de dominio, galería y goldens. | F0 |
| F1 | **Clubes, usuarios y acceso** ([detalle](features/F1-clubes-usuarios-acceso.md)) | Login con Google o email, club personal, alta de clubes por pedido y aprobación, alta de miembros e invitaciones, membresías con roles (coach, atleta, administrador del club), administrador de plataforma, permisos y aislamiento por club en el backend. | F0 |
| F2 | **Catálogo** ([detalle](features/F2-catalogo.md)) | Catálogo base + propios por club; ejercicios (categorías, métricas, referencia de carga, patrón, grupos musculares con peso, sugerencias, archivado); categorías base + propias; grupos musculares extensibles por club; equipo; temporizadores; semilla del catálogo base. | F1 |
| F3 | **Atletas y referencias** | Perfiles de atleta; RMs, marcas, ritmos y FC con id e historial; vigencia por fecha; factores de trabajo; kilajes fijos. | F2 |
| F4 | **Reglas de carga y objetivos** | Objetivo por métrica: `RM × factor × % plan` al cargable más cercano, kilaje fijo, % de marca, ritmo, zona; ajuste del día; % derivados de kg escritos a mano. | F3 |
| F5 | **Editor de plan: estructura** | Modelos de semana, asignación a las 4 semanas, días, bloques (nombre, categoría, modos). | F2 |
| F6 | **Editor de plan: prescripciones** | Ejercicios filtrados por categoría, series con objetivos por métrica, sugerencias, rampas, duplicar. | F5 |
| F7 | **Asignaciones y calendario** | Plan × atletas (con desde–hasta) × inicio, varias asignaciones por atleta, estados activa/pausada/terminada, retomar desde fecha y semana elegidas, ubicación por fecha (ciclo/semana/día), estado de los días por atleta (hecho/en curso/pendiente, y recuperado/falta con la decisión del coach). | F3, F5 |
| F8 | **Temporizadores** | Expansión a fases, motor contra el reloj, sonido, vibración y pantalla encendida en la PWA. | F0 |
| F9 | **Sesión de entrenamiento** | La sesión del día (creada con la primera escritura, presentes por quien escribe), objetivos calculados por atleta, ajuste del día, notas, recuperación individual. | F4, F6, F7 |
| F10 | **Motor de pasos** | Secuencial / circuito × simultáneo / por turnos → lista de pasos; modo guiado con pasada compartida y tiempos de bloque; cambio de modo en vivo que recalcula lo pendiente; marcado fuera de orden. | F9 |
| F11 | **Bloques por tiempo: WoD y cardio** | AMRAP, EMOM, tabata, for time e intervalos dentro de la sesión; métricas de tiempo, distancia, ritmo y FC; resultados por atleta. | F8, F10 |
| F12 | **Registro y sincronización en vivo** | Escritura por serie con objetivo y RPE/RIR, borrador local, cola de reintentos, difusión en tiempo real a los dispositivos de la sesión por WebSocket autenticado con ticket, reconexión automática con resincronización por número de secuencia, difusión detrás de una interfaz (en memoria hoy, bus mañana). | F9 |
| F13 | **Reportes** | Progresión (con RM estimado), volumen e intensidad, balance muscular, dificultades, adherencia y cardio; panel a demanda, resumen de ciclo, resumen post-sesión, exportación a CSV; coach ve todo, atleta lo suyo. | F12 |
| F14 | **Migración desde la referencia** | Catálogo (con músculos y patrón), RMs, planes e historial al modelo nuevo, en un club inicial. Corregir el error 85 %→80 % de octubre 2026 antes de migrar. El test de feb 2026 entra como referencias testeadas. | F2, F3, F6, F12 |
| F16 | **Análisis del plan** | Motor de métricas compartido (series prescritas o registradas); vista en vivo en el editor, relativa y proyectada en kg; desglose por semana, día/bloque, músculo/patrón y ejercicio; comparación con el plan anterior planificado y ejecutado. | F6 (relativo), F4 (proyección), F12 (ejecutado) |
| F15 | **Planes de test** | Tipo de plan test, bloques de test (intentos tipo torneo con válido/nulo, contrarreloj de cardio), referencia nueva automática con factor a 100 %, pausar y retomar la asignación regular. | F7, F10, F12 |

**Camino crítico al primer entrenamiento usable**:
F0 → F1 → F2 → F3 → F4 → F5 → F6 → F7 → F9 → F10 → F12.
F17 (design system) arranca justo después de F0 y su estructura y componentes base tienen que estar
antes de las pantallas de F1. Sus componentes de dominio se suman a medida que los piden F8–F12.
F8 y F11 pueden avanzar en paralelo desde F0. F13, F14, F15 y F16 vienen después. F16 puede
arrancar en su parte relativa apenas exista F6. Conviene construir su motor de métricas antes que
F13, porque los reportes lo reutilizan. F15 conviene
tenerlo antes del próximo test de fin de año.

**M1** ([docs/milestones/M1-mvp.md](milestones/M1-mvp.md)) es el primer corte usable: reemplaza la
referencia para Andi y Ari con versiones recortadas de F0 a F12 y F14. Lo que queda afuera está en su
sección "Fuera de M1". Durante M1 entraron, además, el modo guiado y el cambio de modo en vivo de F10
(sin reordenar pasos), el alta de clubes por pedido y aprobación de F1, y el historial por atleta de
F13.

## 11. Qué se rescata de la referencia y qué se deja

**Se rescata** (reglas probadas, ver `reference/DISENO.md`):

- el mes modelo de 4 semanas que se repite, y el ciclo como parte de la clave;
- el calendario por fecha desde el inicio del plan;
- el registro completo y desnormalizado, con el invariante `rm × pct ≈ kg`;
- el peso cargable más cercano con barra de 20 y pares de 20/15/10/5/2.5/1.5/1.25 (ahora como
  equipo en datos);
- el ajuste del día en dos niveles, que no toca referencias, y las series tocadas que no se pisan;
- las series una por una para representar rampas;
- en las rampas compartidas, la barra vacía con el % más chico de los atletas;
- los temporizadores como fases medidas contra el reloj.

**Se deja**:

- la estructura fija del día (estiramiento/calentamiento/principal/final/WoD) → bloques configurables;
- las variantes fijas descarga/carga/carga2 → modelos de semana libres;
- deducir estiramiento y calentamiento en vivo → sugerencias en el editor;
- "sin referencia = accesorio" como única distinción → categorías y métricas explícitas;
- tres RMs con solo el valor más reciente → referencias de varios tipos con id e historial;
- dos atletas fijos y un plan activo global → clubes, roles, grupos y asignaciones;
- guardar el día entero de una vez → escritura por serie con sincronización en vivo;
- todo por series × reps × kg → métricas por ejercicio;
- Apps Script sin login propio → usuarios con rol por club;
- el RPE como texto no interpretado → RPE/RIR numérico registrado por serie (la nota del plan sigue
  siendo texto libre);
- el test de RM anotado como un bloque más y copiado a mano → planes de test que producen
  referencias solas;
- sin reportes → reportes sobre el registro.

**Impacto en el trabajo en curso**: los modelos que se están portando a `maktub_core` siguen la
estructura vieja: `Bloque` como enum fijo, `Variante` descarga/carga/carga2, `Atleta.rms` como mapa
del último valor y `SesionRegistrada` reemplazada entera, sin club ni usuario. Hay que alinearlos con
la sección 3 antes de construir encima.

## 12. Registro de decisiones

| Fecha | # | Decisión |
|---|---|---|
| 2026-11-07 | P1 | Login por usuario. Cada persona tiene su cuenta y el registro sabe quién escribió cada serie. |
| 2026-11-07 | P1b | Roles coach + atleta. El coach planifica y gestiona; el atleta ejecuta y registra lo suyo y lo de los compañeros de su sesión. |
| 2026-11-07 | P1b | Empezamos con un grupo chico y diseñamos para varios clubes: todo pertenece a un club; las membresías tienen rol por club; la UI arranca con un solo club. |
| 2026-11-07 | P2 | Sincronización al instante entre los dispositivos de una sesión (WebSocket/SSE). |
| 2026-11-07 | P3 | Un atleta puede seguir varios planes en días distintos. Una sesión ejecuta un solo plan, con un grupo que lo sigue y una asistencia que varía. |
| 2026-11-07 | P3b | Manda el calendario del grupo. Un día perdido se recupera o queda como falta, según decida el coach. |
| 2026-11-07 | P4 | Puede tener RM cualquier ejercicio por carga × reps; los básicos siempre. El cardio no usa RM. |
| 2026-11-07 | P4b | El cardio usa mejor marca, ritmo y zonas cardíacas. RM, marca, ritmo y FC se unifican como "referencias del atleta" con id e historial. |
| 2026-11-07 | P5 | Factor de trabajo por atleta y ejercicio con RM, con historial. El registro guarda % del plan y % real; en el gimnasio se ve el del plan, en los gráficos el real. |
| 2026-11-07 | P5b | El factor solo aplica a RMs. |
| 2026-11-07 | P6 | El modo de atletas tiene un default por bloque y se cambia en vivo; no hay override por ejercicio ni por serie en el editor. |
| 2026-11-07 | P7 | El plan se repite sin fin, con ciclos idénticos y sin progresión automática. |
| 2026-11-07 | P8 | Sugerencias de ejercicios en el editor según los principales del día; nada se rellena en vivo. |
| 2026-11-07 | P9 | Backup periódico de la base y exportación a CSV desde la app. |
| 2026-11-07 | P10 | ~~Backend en AWS y MongoDB en Atlas, al menor costo.~~ Reemplazada por P10b y luego P10c. La web app se instala como PWA (sigue vigente). |
| 2026-11-07 | P10b | ~~Backend en Oracle Cloud Always Free, API en DuckDNS.~~ Reemplazada por P10c en el hosting del backend. Sigue vigente: todo gratis por ahora; se migra si hace falta. |
| 2026-11-07 | P10c | **Backend en Google Cloud Run** (europe-north1), dentro del plan gratis mensual, porque Oracle rechazó el registro. Se mantienen la PWA en GitHub Pages y MongoDB Atlas M0 (Frankfurt). La API usa la dirección propia de Cloud Run (`*.run.app`, con HTTPS); DuckDNS ya no hace falta. Backups: job programado de Cloud Run con `mongodump` a Cloud Storage. El backend deja de ser un proceso de larga vida: se apaga sin uso (arranque en frío de 1–2 s), queda fijo en una instancia por la difusión en memoria y los WebSocket se cortan a los 60 min como máximo (ver sección 9). Sigue siendo un contenedor Docker estándar sin APIs propias de Google: se puede mover a una máquina propia sin cambios. Reemplaza el hosting de P10b; las consecuencias para F1 (sitios distintos, tokens en header, ticket para el canal en vivo) siguen igual. |
| 2026-11-07 | R1 | Los reportes cubren progresión de fuerza (con RM estimado), volumen e intensidad, balance muscular, dificultades y adherencia. |
| 2026-11-07 | R2 | Las dificultades se detectan con señales implícitas (reps bajo el objetivo, kg bajados, ajuste < 100 %) más un RPE numérico opcional por serie. Reemplaza la regla vieja de "RPE como texto no interpretado". |
| 2026-11-07 | R3 | El coach ve los reportes de todos; cada atleta solo los suyos. |
| 2026-11-07 | R4 | El catálogo mapea cada ejercicio a un patrón de movimiento y a grupos musculares con peso (principal 100 %, secundario 50 %). |
| 2026-11-07 | R5 | El esfuerzo se carga como RPE o como RIR, a elección del atleta, y se guarda como RPE. |
| 2026-11-07 | R6 | Los reportes llegan como panel a demanda, resumen de ciclo y resumen post-sesión. |
| 2026-11-07 | T1 | El test es un plan aparte de un ciclo. La asignación regular se pausa; al terminar, el coach la retoma con los RMs nuevos o asigna un plan nuevo. |
| 2026-11-07 | T2 | Formatos de test: intentos tipo torneo para fuerza; contrarreloj o distancia en tiempo fijo para cardio. |
| 2026-11-07 | T3 | El resultado del test se convierte automáticamente en la referencia nueva, vigente desde la fecha del test. |
| 2026-11-07 | T4 | Con un RM nuevo, el factor de trabajo de ese ejercicio vuelve a 100 %. |
| 2026-11-07 | T5 | Al retomar el plan regular, el coach elige la fecha y la semana. |
| 2026-11-07 | T6 | En el test tipo torneo, el RM es el mayor intento válido; si todos son nulos, queda el anterior. |
| 2026-11-07 | V1 | El editor muestra volumen e intensidad del plan en vivo, en términos relativos por defecto y proyectado en kg para un atleta o grupo elegido. |
| 2026-11-07 | V2 | Se compara contra el plan anterior, tanto planificado como ejecutado. |
| 2026-11-07 | V3 | Desglose por semana, día y bloque, músculo y patrón, y ejercicio. |
| 2026-11-07 | A1 | Login con Google o con email y contraseña; con el mismo email, es el mismo usuario. |
| 2026-11-07 | A2 | ~~Se entra a un club por invitación del coach.~~ Reemplazada por A8 en cómo se entra hoy. Sigue vigente: sin club, el usuario usa la PWA en su club personal con planes por defecto. |
| 2026-11-07 | A3 | No existen atletas sin usuario. |
| 2026-11-07 | A4 | ~~Cualquier usuario puede crear un club y queda como su coach.~~ Reemplazada por A11. |
| 2026-11-07 | A5 | El uso individual se modela como un club personal implícito. Ahí solo se siguen planes por defecto; para planificar hay que estar en un club. |
| 2026-11-07 | A6 | Por ahora, los planes por defecto los publica solo la plataforma. |
| 2026-11-07 | C1 | Catálogo base de plataforma + ejercicios propios por club. Un ejercicio base se usa tal cual. |
| 2026-11-07 | C2 | Grupos musculares y patrones: lista base que cada club extiende o subdivide, sin borrar ni renombrar. Los reportes agregan hacia el grupo base. |
| 2026-11-07 | C3 | Categorías base + propias por club. |
| 2026-11-07 | DS1 | Design system en un paquete de `packages/`, sobre Material 3 con tokens propios y `ThemeExtension`. |
| 2026-11-07 | DS2 | Tema oscuro y claro. Entrenamiento abre en oscuro por defecto; el resto sigue al sistema. |
| 2026-11-07 | DS3 | Paleta de marca: negro `#000000`, maroon `#830000`, dark red `#BC0202` (primario) y red `#FF0000` (acento). Los tonos claros y los neutros se derivan con HCT, con `#BC0202` como semilla. Reemplaza la propuesta inicial "Hierro y tiza". |
| 2026-11-07 | DS5 | El color de error es naranja, no rojo, para que el rojo quede solo para la marca. La alerta se corre al amarillo y el éxito sigue en verde. |
| 2026-11-07 | DS6 | Tonos derivados aprobados: escala HCT de marca (semilla `#BC0202`), neutros con tinte rojo, error `#FB8C00`, alerta `#F2C200`, éxito `#2E9D4F`. Valores y contraste en la muestra enlazada en F17 §6.3. |
| 2026-11-07 | DS7 | Tipografía: Inter para texto y Barlow Condensed para números grandes y títulos de marca, empaquetadas con la app. |
| 2026-11-07 | DS4 | Lo construye la sesión del setup, a partir de la especificación en `docs/features/F17-design-system.md`. |
| 2026-11-07 | C4 | La semilla del catálogo base sale de `reference/`, ampliada con un set general de gimnasio y cardio. |
| 2026-11-08 | A7 | Rol **administrador del club** (`admin_club`), que se suma a coach y atleta: da de alta miembros, cambia roles y mantiene lo del club. Un club siempre tiene un administrador y un coach activos. |
| 2026-11-08 | A8 | Por ahora los miembros entran por alta del administrador del club, con su email. Las invitaciones por link o código quedan para el resto de F1. |
| 2026-11-08 | C5 | Los ejercicios base los edita solo el administrador de plataforma y el cambio se ve en todos los clubes. En la app, lo base se marca "Default" y lo del club "Custom". |
| 2026-11-08 | C6 | El equipo es un inventario por club (barras y pares de discos con cantidad). La barra se indica por ejercicio (o "sin barra"), con la más pesada por defecto, y la prescripción la puede pisar. |
| 2026-11-08 | PL1 | Guardar deja un borrador y publicar exige el plan completo. Asignaciones, calendario y sesiones leen siempre la versión publicada. |
| 2026-11-09 | EN1 | Una nota por ejercicio (en la primera serie) y una por sesión. "Volver a lo planificado" es por ejercicio y no desmarca. |
| 2026-11-14 | EN2 | El modo guiado y el cambio de modo en vivo de F10 entran en M1; reordenar pasos queda afuera. Los tiempos de bloque se registran. |
| 2026-11-14 | EN3 | Sin señal se abren el plan, el calendario y la sesión de los días precargados, y la sesión se puede crear sin señal. |
| 2026-11-15 | EN4 | La pasada del modo guiado es estado de la sesión, igual en todos los dispositivos, y se escribe con acciones aplicadas sobre el estado actual, sin rechazo por versión. |
| 2026-11-15 | EN5 | La sesión no se abre ni se eligen presentes: se crea con la primera escritura y quien escribe queda presente. |
| 2026-11-15 | PL2 | Tipo de plan *histórico* para lo migrado: se publica sin % solo desde el importador, no se asigna y siempre es pasado. Los demás planes los marca el coach como activos o pasados. |
| 2026-11-15 | EN6 | Una serie registrada puede ser *estimada*: la carga el importador con los kilos que propone la app, y cualquier escritura desde la app la saca. |
| 2026-11-16 | PL3 | Un plan se puede eliminar (coach o administrador del club): se borran el plan y sus asignaciones, y lo registrado queda. |
| 2026-11-18 | PL4 | Una serie por % se planifica en % o en kg, y cada atleta de la asignación queda con su % y sus kg congelados. La sesión les aplica el ajuste del día. |
| 2026-11-18 | PL5 | La asignación guarda su lista de atletas, cada uno con desde–hasta, y el coach la cambia sin terminar el plan. Un atleta puede estar en cualquier cantidad de asignaciones activas. Reemplaza la asignación por grupo o por atleta, y elimina el límite de una asignación activa por grupo de M1 (D14). |
| 2026-11-19 | PL6 | Visibilidad del plan para los otros coaches: privado (por defecto), compartido para ver o compartido para editar. Quien lo creó y los administradores del club lo alcanzan entero; eliminarlo y cambiar la visibilidad queda para ellos. |
| 2026-11-21 | EN7 | El estado de un día es por atleta: *hecho* con todas sus series, *en curso n/m* con algunas, *pendiente* sin ninguna. Reemplaza D13 de M1, que miraba la sesión del grupo. |
| 2026-11-21 | EN8 | Rehacer un día ya hecho en otra fecha edita la sesión original; no lo marca como recuperado. |
| 2026-11-21 | PL7 | En un plan de varios atletas, una serie en kilos pide un peso por atleta, sin valor general, con las mismas reps para todos. La sesión los propone sin ajuste del día. |
| 2026-11-21 | C7 | Cualquier ejercicio admite peso al planificar; si se carga, el ejercicio suma la métrica de carga. |
| 2026-11-21 | A9 | El coach crea, edita, archiva y elimina los ejercicios del club. Categorías, temporizadores y equipo siguen siendo del administrador del club. |
| 2026-11-21 | A10 | El administrador del club lee la ficha y el historial de todos los atletas, sin editar referencias ni planificar. La marca de administrador de plataforma no da permisos dentro de un club. |
| 2026-11-21 | A11 | Un club nuevo se pide y lo aprueba o rechaza un administrador de plataforma desde la app. Quien lo pidió queda como administrador del club, coach y atleta. El catálogo base no se copia. |
| 2026-11-21 | R7 | Historial por atleta: sus sesiones pasadas de cualquier plan, con el detalle de kilos y reps. Lo ven el atleta, el coach y el administrador del club. |

## 13. Preguntas abiertas

- **Métricas de un ejercicio (necesita revisión).** Hay demasiadas opciones, se pueden combinar de
  formas incompatibles y "Carga (% del RM)" está fuera de lugar: el RM es un récord del tipo de
  métrica que usa el ejercicio, no una métrica en sí. Marcado en la prueba de E2 (2026-11-08). Por
  ahora el modelo y la pantalla quedan como están. No frena nada de M1.

Las que aparezcan al detallar cada feature se agregan acá, con lo que frenan.
