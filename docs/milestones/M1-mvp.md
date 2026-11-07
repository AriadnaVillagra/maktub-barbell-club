# M1 — MVP: la app de referencia sobre la base nueva

Estado: definido, por arrancar. 2026-11-07.
Contexto: [diseño general](../diseno.md), [referencia](../../reference/DISENO.md) (`reference/`).

## 1. Objetivo

Que Andi y Ari dejen la planilla y entrenen solo con la app nueva. La app hace **lo mismo que hacía
la referencia**, sobre el modelo de `docs/diseno.md` y con los defectos conocidos corregidos.

**No se agregan funcionalidades nuevas.** Todo lo que el diseño suma por encima de la referencia
(reportes, planes de test, análisis del plan, motor de pasos, cardio, varios clubes) queda para
después de M1. Los modelos sí se escriben completos, como pide `CLAUDE.md`, para no migrar más
adelante: lo que se recorta es la interfaz y la lógica, no los campos.

**Se cumple cuando** los dos entrenan un ciclo completo de 4 semanas solo con la app y el historial
de la planilla está migrado y verificado (ver 7).

## 2. Decisiones de alcance

| # | Decisión | Por qué |
|---|---|---|
| M1-D1 | **Login solo con Google.** El club Maktub, los usuarios de Andi y Ari, sus membresías (coach + atleta) y sus perfiles de atleta se crean por script. Un email que no está dado de alta no entra. | La referencia también pedía solo una cuenta de Google. Email y contraseña, invitaciones, club personal y crear clubes son nuevos. |
| M1-D2 | **Escritura por serie con sincronización en vivo** entre los dispositivos de la sesión (WebSocket con ticket, secuencia y resincronización), con borrador local y cola de reintentos. | Corrige que las series marcadas se perdían al recargar y que guardar el día entero hacía que un dispositivo pisara al otro. |
| M1-D3 | **Factor de trabajo por atleta y ejercicio con RM**, con historial. | Corrige el problema que la referencia tenía anotado: a Ari le proponía alrededor de un 20 % de más en sentadilla. |
| M1-D4 | **Se migra todo**: catálogo, RMs, planes e historial, corrigiendo el error 85 % → 80 % de octubre 2026. El test de febrero 2026 entra como referencias *testeadas*. | La app nueva reemplaza a la vieja sin perder nada. |
| M1-D5 | Quien crea un club queda como coach + atleta (F1 S1). Corregir un ejercicio base se refleja en todos los clubes, también en el historial (F2 S4). | Confirmado por el usuario el 2026-11-07. |

## 3. Qué hace la referencia y cómo queda en M1

| Hoy en la referencia | En M1 | Tipo de cambio |
|---|---|---|
| Acceso con cualquier cuenta de Google; el script lee y escribe como dueño | Login con Google y sesión propia; solo usuarios dados de alta; roles coach/atleta | Diseño (A1, P1) |
| Dos atletas fijos (`a1`, `a2`) y un plan activo global | Un club, un grupo con los dos atletas y una **asignación** plan × grupo × fecha de inicio | Diseño (P1b, P3) |
| Mes modelo de 4 semanas con variantes fijas descarga/carga/carga2 | **Modelos de semana** libres, asignados a las 4 semanas (la referencia es `A, B, B, A`) | Diseño (3.4) |
| Día fijo: estiramiento, calentamiento, principal (primario + secundario), final, WoD | **Bloques configurables** con nombre y categoría; el editor arma los mismos bloques de la referencia | Diseño (3.4, sección 11) |
| Estiramiento y calentamiento deducidos en vivo según el primario | Se eligen en el editor; en la sesión no se rellena nada | Diseño (sección 11) |
| "Sin referencia = accesorio" | Categorías y métricas explícitas en el ejercicio | Diseño (3.2, 3.5) |
| Catálogo, temporizadores, WoDs, RMs y kilajes de accesorios editados en la planilla | Se editan desde la app (rol coach) | Corrección |
| Tres RMs, solo el último valor | RMs como **referencias con historial** y vigencia por fecha | Diseño (3.3) |
| Barra y discos como constantes en el código | **Equipo** del club en datos, con el estándar por defecto | Corrección |
| Kilos = RM × % al cargable más cercano; rampas; barra vacía con el % más chico; kilaje fijo para accesorios | Igual, más el **factor de trabajo** | Se rescata + M1-D3 |
| Ajuste del día en dos niveles; las series tocadas no se pisan | Igual, por atleta | Se rescata |
| Checks de serie solo en memoria: recargar los pierde | Cada serie se registra al marcarla, con borrador local | Corrección (M1-D2) |
| Guardar reemplaza el día entero | Upsert por serie, idempotente, difundido en vivo | Corrección (M1-D2) |
| Registro desnormalizado con `rm × pct ≈ kg` | Igual, más objetivo, referencia por id, factor, quién escribió y posición en el plan | Diseño (3.6) |
| RPE como nota de texto | La nota del plan sigue siendo texto libre | Sin cambio |
| Temporizadores countdown / EMOM / tabata; vibración y pantalla encendida fallan dentro del iframe | Los mismos tres formatos en la PWA, con sonido, vibración y pantalla encendida | Corrección |
| WoD: descripción + temporizador | Bloque de categoría `wod` con nota y temporizador | Diseño, misma funcionalidad |
| Plan de octubre con 85 % donde va 80 % | Corregido al migrar | Corrección (M1-D4) |

## 4. Fuera de M1

| Queda afuera | Feature |
|---|---|
| Email y contraseña, verificación, recuperación, invitaciones, club personal, crear clubes, selector de club, planes por defecto | F1 (resto) |
| UI de grupos musculares, patrones, sugerencias y relaciones; set general del catálogo base; edición del catálogo base desde la app | F2 (resto) |
| Referencias de cardio (marca, ritmo, FC) | F3 (resto) |
| Atajos del editor (duplicar, generar rampa, copiar series) | F6 (resto) |
| Estados recuperado y falta, y la decisión del coach; pausar asignaciones | F7 (resto) |
| Motor de pasos, modo circuito, modo por turnos y cambio de modo en vivo | F10 |
| AMRAP, for time, intervalos y resultados de bloques por tiempo | F11 |
| RPE o RIR numérico por serie | F12 (resto) |
| Reportes, gráficos y exportación a CSV | F13 |
| Planes de test | F15 |
| Análisis del plan | F16 |
| Despliegue automático del backend desde GitHub | F0 (opcional) |

## 5. Plan

Las etapas van en orden. Dentro de una etapa, las tareas siguen su columna "Depende de". Cada tarea
termina con tests y `dart analyze` / `flutter analyze` limpios. Tamaño: **S** ≈ medio día,
**M** ≈ 1–2 días, **L** ≈ 3 días o más.

### Etapa 0 — Cerrar F0

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 0.1 | Publicar la PWA en GitHub Pages y cargar el origen en `ORIGENES_PERMITIDOS` | — | S | La app abre desde `github.io` y llega a `/health` de la API |
| [ ] 0.2 | Que la app abra sin señal: caché de la app en el dispositivo (service worker) | 0.1 | S | Con el modo avión, la app instalada abre y muestra lo último que tenía |
| [ ] 0.3 | Backup programado: job de Cloud Run con `mongodump` a Cloud Storage | — | M | Hay un backup diario y está probado restaurarlo en local |

### Etapa 1 — Acceso (F1 recortado, rama `auth`)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [x] 1.1 | Modelos de usuario, club, membresía, invitación, atleta y matriz de permisos | — | S | Hecho (`eb26f6e`) |
| [x] 1.2 | Sesión propia: token de acceso, refresh token con rotación y detección de reuso, `requireUser` | — | M | Hecho (`1bcd49f`), desplegado |
| [ ] 1.3 | Login con Google: verificar el ID token y entrar al usuario con ese email; rechazar emails no dados de alta | 1.2 | M | Un email dado de alta entra; uno desconocido recibe un mensaje claro |
| [ ] 1.4 | Contexto de club: middleware de club + rol, filtro obligatorio por `clubId` y un test de aislamiento reutilizable | 1.2 | M | Un pedido con otro `clubId` no ve nada; el test se puede aplicar a cualquier endpoint |
| [ ] 1.5 | Script de alta: club Maktub, usuarios de Andi y Ari, membresías coach + atleta, atletas | 1.1 | S | Idempotente; correrlo dos veces no duplica nada |
| [ ] 1.6 | App: ingreso con Google, tokens guardados en la app, header, renovación de a una, cerrar sesión | 1.3 | M | Criterio 11 de F1, salvo lo de email |
| [ ] 1.7 | App: mostrar u ocultar planificación según el rol | 1.4, 1.6 | S | Un usuario solo atleta no ve el editor |

### Etapa 2 — Catálogo (F2 recortado)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 2.1 | Modelos: ejercicio (todos los campos de 3.2), categoría, equipo y temporizador con ámbito; validaciones puras | — | M | Viajan ida y vuelta por JSON; las validaciones tienen tests |
| [ ] 2.2 | Backend: leer el catálogo visible (plataforma + club) con filtro por categoría | 1.4, 2.1 | S | Devuelve los base y los del club, nunca los de otro club |
| [ ] 2.3 | Backend: escritura del club: ejercicios, categorías, temporizadores y equipo; archivar en vez de borrar si está en uso | 2.2 | M | Un ejercicio usado se archiva y los registros viejos lo siguen resolviendo |
| [ ] 2.4 | Semilla del catálogo base desde `reference/`: ejercicios, categorías, temporizadores, WoDs y el equipo estándar. La lista la revisás antes de cargarla | 2.1 | M | Script idempotente; lista aprobada |
| [ ] 2.5 | App: catálogo, ficha de ejercicio, categorías, temporizadores y equipo | 2.3 | L | El coach crea, edita y archiva sin tocar la base |
| [ ] 2.6 | App: selector de ejercicios filtrado por categoría, reutilizable en el editor | 2.2 | S | Lo usa la etapa 5 |

### Etapa 3 — Atletas y referencias (F3 recortado)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 3.1 | Modelos: referencia (todos los tipos en el modelo, solo `rm` en la app), factor de trabajo con historial, kilaje fijo; vigencia por fecha | 2.1 | M | La referencia vigente para una fecha es la última con `fecha ≤` esa fecha |
| [ ] 3.2 | Backend: RMs con historial, factores y kilajes fijos; un RM nuevo vuelve el factor a 100 % | 3.1, 1.4 | M | Solo el coach escribe; el atleta lee lo suyo |
| [ ] 3.3 | App: ficha del atleta con RMs e historial, factores y kilajes fijos | 3.2 | M | Reemplaza las hojas `RMs` y `PesosAccesorios` |

### Etapa 4 — Reglas de carga (F4 recortado)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 4.1 | Objetivo de una serie: `RM × factor × % del plan` al cargable más cercano según el equipo, kilaje fijo, barra vacía en la rampa con el % más chico, ajuste del día en dos niveles, series tocadas que no se pisan, % derivados de kg escritos a mano | 3.1 | M | Puro en `maktub_core`; reproduce los kilos de la referencia en los casos de `reference/` |

### Etapa 5 — Editor de plan (F5 + F6 recortados)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 5.1 | Modelos: plan, modelo de semana, asignación de las 4 semanas, día, bloque (con modos, aunque M1 use solo secuencial), prescripción y serie; validaciones de la referencia | 2.1 | M | Cubre todo lo de 3.4 |
| [ ] 5.2 | Backend: crear, leer, listar y guardar un plan entero | 5.1, 1.4 | M | Guardar es atómico; solo el coach |
| [ ] 5.3 | App: estructura: modelos de semana, asignación a las 4 semanas, días (1 a 7) y bloques con nombre y categoría | 5.2 | L | Se arma un plan con la forma de la referencia (`A, B, B, A`, 3 días, 5 bloques) |
| [ ] 5.4 | App: prescripciones: ejercicio filtrado por categoría, series una por una (reps, %, kg), series por defecto al agregar (como la referencia), nota, temporizador, y la misma validación al guardar | 5.3, 2.6 | L | Se puede reescribir a mano el plan de octubre |

### Etapa 6 — Asignación y calendario (F7 recortado)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 6.1 | Modelos y backend: grupo de atletas y asignación plan × grupo × inicio (activa o terminada); ubicación por fecha (ciclo, semana, día) | 5.2, 3.2 | M | Reemplaza la estrella de "plan activo" |
| [ ] 6.2 | App: asignar un plan al grupo y ver qué toca hoy, con días hechos y pendientes | 6.1 | M | Igual que las pills de semana y día de la referencia |

### Etapa 7 — Sesión y registro en vivo (F8 + F9 + F12 recortados)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 7.1 | Modelos: sesión (asignación, ciclo, semana, día, fecha, presentes) y registro por serie con todos los campos de 3.6 | 5.1, 3.1 | M | Respeta `rm × pct_real ≈ kg` |
| [ ] 7.2 | Backend: abrir o retomar la sesión del día, leerla y upsert por `sesión + atleta + bloque + prescripción + serie` | 7.1, 6.1 | M | Repetir una escritura no duplica; dos dispositivos no se pisan |
| [ ] 7.3 | Backend: canal en vivo: ticket de un solo uso, WebSocket por sesión, número de secuencia, resincronización al reconectar, difusión en memoria detrás de una interfaz | 7.2 | L | Cortar la conexión y reconectar no pierde marcas |
| [ ] 7.4 | App: pantalla de la sesión: día por fecha o elegido, presentes, cambio de atleta, kilos calculados, ajuste del día, marcar serie, editar kg y reps, nota y restaurar | 7.2, 4.1, 6.2 | L | Hace todo lo que hacía la pantalla de seguimiento |
| [ ] 7.5 | App: borrador local, cola de reintentos y conexión al canal en vivo | 7.3, 7.4 | L | Con el modo avión se sigue marcando; al volver la señal se sincroniza |
| [ ] 7.6 | App: temporizadores en la sesión: el de la prescripción al marcar una serie, selector manual, sonido, vibración y pantalla encendida; WoD con su nota y su temporizador | 7.4 | M | Countdown, EMOM y tabata como en la referencia; nada falla si el dispositivo no lo permite |

### Etapa 8 — Migración (F14)

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 8.1 | Exportar las hojas de la planilla a CSV (las bajás vos) | — | S | Están todas las hojas de `reference/Esquema.gs` |
| [ ] 8.2 | Importador: catálogo, RMs (el test de feb 2026 como *testeado*), kilajes, planes (variantes → modelos de semana, bloques fijos → bloques) e historial. Corrige octubre 85 % → 80 % | 8.1, 2.4, 3.2, 5.2, 7.2 | L | Idempotente; se puede correr de nuevo en el corte |
| [ ] 8.3 | Verificación: cantidades por hoja, el invariante `rm × pct ≈ kg` y una muestra revisada a mano | 8.2 | M | Sin diferencias sin explicar |
| [ ] 8.4 | Corte: congelar la planilla, importar lo último y pasar a la app | 8.3, etapas 0–7 | S | La planilla queda solo de lectura |

### Etapa 9 — Cierre

| # | Tarea | Depende de | Tamaño | Hecho cuando |
|---|---|---|---|---|
| [ ] 9.1 | Prueba en el gimnasio: una semana entrenando con la app (dos teléfonos, la sesión en vivo) | 7.6 | — | Lista de problemas corregida |
| [ ] 9.2 | Merge de `auth` y de las ramas siguientes a `main`; despliegue | todas | S | `main` desplegado |

## 6. Ruta y paralelismo

```
0 ─────────────────────────────────────────────────────┐
1 ──► 2 ──► 3 ──► 4 ──┐                                 ├──► 8.4 ──► 9
            └──► 5 ──► 6 ──► 7 ─────────────────────────┤
                                  8.1–8.3 (desde 5.2/7.2)┘
```

- La etapa 0 corre en paralelo con todo.
- 4.1 depende de 3.1 pero no de la app, y puede adelantarse.
- 7.3 (canal en vivo) es la tarea con más riesgo: conviene arrancarla apenas existe 7.2.
- El importador (8.2) sirve también para probar las etapas 5 a 7 con datos reales.

## 7. Criterios de aceptación de M1

1. Andi y Ari entran con Google desde sus teléfonos con la PWA instalada; un email desconocido no entra.
2. El coach edita catálogo, equipo, temporizadores, RMs, factores y kilajes desde la app, sin tocar la base.
3. El coach arma un plan con la forma de la referencia y lo asigna al grupo con una fecha de inicio.
4. La app abre en el día que toca por fecha, con ciclo y semana correctos, y permite elegir otro día.
5. Los kilos propuestos coinciden con los de la referencia para los mismos RMs, y con el factor aplicado cuando lo hay.
6. El ajuste del día en dos niveles funciona por atleta y no pisa las series editadas a mano.
7. Con dos teléfonos en la misma sesión, una serie marcada en uno aparece en el otro al instante; cortar la conexión o recargar no pierde nada.
8. Sin señal se puede seguir marcando, y al volver se sincroniza.
9. Los temporizadores suenan, vibran y mantienen la pantalla encendida en la PWA instalada.
10. El historial migrado coincide con la planilla, con octubre corregido.
11. Un ciclo completo de 4 semanas entrenado solo con la app.

## 8. Riesgos y supuestos

| # | Riesgo o supuesto | Qué hacer |
|---|---|---|
| R1 | La sincronización en vivo es lo más costoso del MVP y depende de los límites de Cloud Run (WebSocket de hasta 60 min, una instancia) | Arrancar 7.3 temprano; el borrador local (7.5) cubre los cortes |
| R2 | Google Sign-In con el origen `github.io` y sin dominio propio (F1 S7) | Probarlo al empezar 1.3, antes de construir la pantalla |
| R3 | La planilla es la única fuente del historial | No editarla durante la migración; corte con la planilla congelada (8.4) |
| R4 | Este alcance cambia el orden del camino crítico de `docs/diseno.md` ("Features") y recorta F1 a F12 | Llevarlo a la sesión que mantiene `diseno.md` para que lo refleje |
