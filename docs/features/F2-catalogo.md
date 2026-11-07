# F2 — Catálogo

Estado: listo para desarrollar, con los supuestos de la sección 8 por confirmar. 2026-11-07.
Contexto: [diseño general](../diseno.md), §3.2, y decisiones P4, R4, C1–C4.

## 1. Objetivo

Tener el vocabulario con el que se arman los planes y se leen los reportes: **qué ejercicios
existen, qué miden, qué músculos trabajan, en qué bloques entran y contra qué se cargan**. El
catálogo existe en dos niveles: uno base de plataforma, compartido por todos, y uno propio de cada
club.

## 2. Alcance

- **Ejercicios** base y propios del club: alta, edición, archivado y borrado si nunca se usaron.
- **Categorías** base y propias.
- **Grupos musculares y patrones de movimiento**: lista base, que cada club extiende o subdivide.
- **Equipo** del club: barra y pares de discos.
- **Temporizadores**: presets base y propios (la ejecución es F8).
- **Selector de ejercicios**: el componente de menú filtrable que reutiliza el editor de planes (F6).
- **Semilla** del catálogo base.

## 3. Fuera de alcance

- Que un club modifique u oculte ejercicios base (decisión C1: se usan tal cual).
- Videos o imágenes de ejecución.
- Compartir ejercicios propios entre clubes.
- Las referencias del atleta (RMs, marcas): son F3. Acá solo se declara *si* un ejercicio puede
  tener RM o contra qué se carga.

## 4. Modelo

**Ámbito**: todo elemento del catálogo es *base* o *del club*. Los base usan un `clubId` reservado
de plataforma (por ejemplo `plataforma`). Así se mantiene el invariante "todo documento tiene
`clubId`", y leer el catálogo de un club es `clubId ∈ {plataforma, club actual}`.

| Entidad | Campos principales |
|---|---|
| **Ejercicio** | id, ámbito, nombre, categorías[], métricas[] (con la métrica objetivo por defecto), patrón, músculos[] (grupo + peso `principal` 100 % \| `secundario` 50 %), referencia de carga, sugerencias[] (ids de ejercicios que suele acompañar), notas, estado (`activo` \| `archivado`) |
| **Categoría** | id, ámbito, nombre, estado |
| **Grupo muscular** | id, ámbito, nombre, padre (opcional, solo en grupos del club) |
| **Patrón** | id, ámbito, nombre, padre (opcional, solo en patrones del club) |
| **Equipo** | clubId, barra (kg), pares de discos[] |
| **Temporizador** | id, ámbito, nombre, tipo, parámetros del tipo |

**Métricas** posibles (ver diseño §3.5): carga por % de RM, carga fija, peso corporal (± lastre),
repeticiones, tiempo, distancia, ritmo, zona cardíaca, calorías, intento.

**Referencia de carga**, una de:

- `propia`: el ejercicio tiene RM propio. Solo vale si mide carga × repeticiones (P4).
- `de otro ejercicio`: se carga como % del RM de otro (Press militar → bench).
- `marca`/`ritmo`: es cardio y se prescribe contra una marca o ritmo propio (P4b).
- `ninguna`: kilaje fijo por atleta, peso corporal o valores absolutos.

## 5. Reglas

- **Un club usa los base tal cual.** No los edita, no los oculta. Si uno no le sirve, crea uno propio.
- Un ejercicio del club puede referenciar el RM de un ejercicio base o de otro del club. Un base solo
  puede referenciar otro base.
- La referencia `propia` exige que el ejercicio tenga carga y repeticiones entre sus métricas.
- No hay ciclos de referencia: A → B → A se rechaza. Si B carga por el RM de otro, A termina en el
  RM final de la cadena.
- **Archivar, no borrar**: un ejercicio, una categoría o un grupo usado en algún plan, registro o
  ejercicio **no se borra, se archiva**. Lo archivado no aparece en el selector, pero sigue
  resolviéndose donde ya se usa. Lo que nunca se usó sí se puede borrar.
- **Grupos y patrones**: un club agrega grupos o subdivide uno base, pero no borra ni renombra los
  base. Profundidad máxima: base → hijo del club (dos niveles). Los reportes agregan hacia el grupo
  base.
- Los ejercicios base solo pueden usar grupos, patrones y categorías base. Los del club pueden usar
  base o del club.
- Las sugerencias son una relación dirigida ("movilidad de cadera acompaña a sentadilla") y solo
  apuntan a ejercicios visibles para el club.
- El equipo del club arranca con el estándar (barra de 20 y pares de 20/15/10/5/2.5/1.5/1.25). Los
  pesos cargables se recalculan al cambiarlo.
- Nombres únicos dentro de lo visible para un club, comparados sin mayúsculas ni acentos.
- **Permisos**: el coach edita lo del club; los atletas solo leen; el administrador de plataforma
  edita lo base.

## 6. Interfaz

**Recursos del backend**: listar el catálogo visible para el club (con filtros); crear, editar,
archivar y borrar ejercicios, categorías, grupos, patrones y temporizadores del club; ver y editar
el equipo; los mismos recursos en ámbito plataforma para el administrador.

**Pantallas**:

- **Catálogo**: lista con búsqueda y filtros por categoría, patrón, grupo muscular, ámbito
  (base/propio) y archivados. Se distingue a la vista qué es base y qué es propio.
- **Ficha de ejercicio**: nombre, categorías, métricas, patrón, músculos con peso, referencia de
  carga, sugerencias y notas. Los base se ven en modo lectura, con la opción de "crear uno propio a
  partir de este".
- **Categorías, grupos y patrones**: listas con lo base fijo y lo del club editable; subdividir un
  grupo base.
- **Equipo**: barra y discos, con una vista previa de los pesos cargables.
- **Selector de ejercicios** (componente): búsqueda y filtro por una categoría dada, recientes
  primero, sin archivados. Lo usa F6.

## 7. Criterios de aceptación

1. Un club nuevo ve el catálogo base completo sin configurar nada.
2. El coach crea un ejercicio propio, con categoría, métricas, patrón y músculos, y aparece en el
   selector de esa categoría. Los ejercicios propios de un club no aparecen en otro club.
3. Un ejercicio base no se puede editar desde un club. "Crear uno propio a partir de este" deja un
   ejercicio del club con los mismos datos.
4. Marcar referencia `propia` en un ejercicio sin carga × repeticiones se rechaza. Un ciclo de
   referencias se rechaza.
5. Un ejercicio usado en un plan o un registro no se puede borrar, solo archivar. Archivado,
   desaparece del selector y los registros viejos lo siguen mostrando con su nombre.
6. El coach subdivide "hombro" en "deltoides lateral". Un ejercicio propio que suma a "deltoides
   lateral" aparece también en el total de "hombro".
7. No se puede borrar ni renombrar un grupo, patrón o categoría base desde un club.
8. Cambiar el equipo del club cambia los pesos cargables propuestos.
9. Un atleta ve el catálogo pero no puede modificarlo.
10. La semilla carga el catálogo base completo, con músculos y patrón en todos los ejercicios, y se
    puede correr más de una vez sin duplicar.

## 8. Supuestos a confirmar

| # | Supuesto | Por qué importa |
|---|---|---|
| S1 | Los temporizadores siguen el mismo esquema de dos niveles (presets base + propios del club). | No se decidió explícitamente. |
| S2 | Los patrones de movimiento también se pueden subdividir, igual que los grupos musculares. | C2 habla de ambos; confirmar que hace falta para patrones. |
| S3 | El equipo es uno por club. Varias barras (15 kg, trap bar) quedan para después. | Simplifica F3/F4. |
| S4 | Los ejercicios base los edita solo el administrador de plataforma, y un cambio en un base (por ejemplo, corregir músculos) **se refleja en todos los clubes**. Los registros viejos conservan el nombre que tenía el ejercicio al momento. | Afecta reportes históricos de balance muscular. |
| S5 | La lista de la semilla la armo yo y la revisás antes de cargarla. | Calidad del catálogo base. |

## 9. Tareas

En orden. Cada una termina con tests.

1. **Modelos en `maktub_core`**: Ejercicio, Categoría, Grupo muscular, Patrón, Equipo y
   Temporizador con ámbito; métricas y referencia de carga; validaciones puras (referencia propia
   válida, ciclos, profundidad de grupos, nombres únicos).
2. **Agregación de músculos**: función pura que suma series ponderadas por grupo y las agrega hacia el
   grupo base. La usan F13 y F16.
3. **Backend: lectura del catálogo visible** (`plataforma` + club) con filtros.
4. **Backend: escritura del club**: ejercicios, categorías, grupos, patrones y temporizadores, con
   la regla de archivar en vez de borrar (consulta de uso en planes y registros).
5. **Backend: equipo del club**, con el estándar por defecto.
6. **Backend: escritura de plataforma** para el administrador.
7. **Semilla del catálogo base**: armar la lista (de `reference/` más el set general), revisión del
   usuario, y un script idempotente.
8. **Frontend: catálogo y ficha de ejercicio**, incluido "crear uno propio a partir de este".
9. **Frontend: categorías, grupos, patrones y equipo**.
10. **Frontend: selector de ejercicios** como componente reutilizable para F6.
