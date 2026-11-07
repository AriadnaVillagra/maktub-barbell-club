# F17 — Design system

Estado: listo para desarrollar. Paleta, tonos derivados y tipografía aprobados (sección 6).
2026-11-07.
Contexto: [diseño general](../diseno.md) y decisiones DS1–DS4.

## 1. Objetivo

Un paquete en `packages/` con los estilos y componentes de la app, para que todas las pantallas se
vean y se comporten igual desde la primera, y para que cambiar la identidad visual no obligue a
tocar las pantallas. Se construye sobre **Material 3**, con **tokens propios**, y en **tema oscuro y
claro**.

## 2. Alcance

- Paquete Flutter `maktub_ui` en `packages/`, dependencia del frontend.
- **Tokens**: color, tipografía, espaciado, radios, elevación, movimiento, tamaños táctiles,
  breakpoints.
- **Temas** oscuro y claro, armados desde los tokens (`ThemeData` + `ThemeExtension` para lo que
  Material no cubre).
- **Densidades**: *planificación* (normal) y *entrenamiento* (grande).
- **Componentes base** y **componentes de dominio** (sección 5).
- **Galería** de componentes para verlos en los dos temas y densidades, más tests de golden.

## 3. Fuera de alcance

- La identidad completa de marca (logo final, material de redes).
- Los componentes de gráficos de reportes: entran con F13/F16, pero usan los tokens de este paquete.
- Animaciones elaboradas: solo las transiciones y el feedback básicos.

## 4. Principios

**El contexto de uso manda.** La pantalla más exigente es la de entrenamiento: celular en una mano,
dedos con tiza o transpiración, el teléfono apoyado en el banco y leído a uno o dos metros, entre
series y con el pulso alto. De ahí salen estas reglas:

1. **Los números son lo más importante de la pantalla.** Kilos, reps y tiempo se muestran grandes,
   con cifras tabulares (que no bailan al cambiar), y legibles a distancia.
2. **Áreas táctiles generosas**: 48 dp como mínimo en planificación y 56 dp en entrenamiento, con
   separación suficiente para no tocar la acción de al lado.
3. **Escribir poco**: en entrenamiento se usan steppers (± 2.5 kg, ± 1 rep) y selecciones antes que
   el teclado.
4. **Contraste alto**: WCAG AA como mínimo en los dos temas. El estado nunca depende solo del color.
5. **El oscuro es el tema de entrenamiento**: entrenamiento abre en oscuro por defecto (menos
   encandilamiento, menos batería en pantallas OLED). El resto de la app sigue la preferencia del
   sistema. El usuario puede fijar cualquiera de los dos.
6. **Planificación es densa, entrenamiento es grande**: el editor de planes se usa en tablet o
   escritorio y muestra mucho a la vez; entrenamiento muestra poco, muy grande.

**Reglas para quien escribe pantallas**:

- Nunca colores, tamaños ni espaciados literales en las apps: siempre un token o un componente del
  paquete.
- Si falta un componente, se agrega al paquete con su entrada en la galería. No se resuelve en la
  pantalla.

## 5. Estructura

### 5.1 Tokens en tres capas

```
primitivos      paleta cruda, escala tipográfica, escala de espaciado (no se usan directo)
   ↓
semánticos      roles: superficie, texto, acento, éxito, alerta, error, serie hecha,
                serie pendiente, turno activo, zonas de intensidad, colores de discos…
   ↓
componentes     botones, tarjetas, stepper… consumen solo semánticos
```

Los temas oscuro y claro son dos asignaciones de primitivos a semánticos. Cambiar la identidad
visual es cambiar los primitivos.

| Grupo | Contenido |
|---|---|
| Color | roles de Material 3 (`ColorScheme`) + extensión propia: estados de serie, turno activo, zonas de intensidad (5), colores de discos, base vs propio en el catálogo |
| Tipografía | escala de texto + **escala numérica** aparte (display para el peso en entrenamiento, cifras tabulares) |
| Espaciado | escala de 4 en 4 (4, 8, 12, 16, 24, 32, 48) |
| Radios | chico, medio, grande, pastilla |
| Elevación | superficies por nivel, con tinte en oscuro según Material 3 |
| Movimiento | duraciones y curvas estándar; respeta "reducir movimiento" del sistema |
| Táctil | mínimo por densidad (48 / 56 dp) |
| Breakpoints | compacto (celular), medio (tablet), expandido (escritorio) |

### 5.2 Componentes

**Base**, los que necesitan F1 y F2 primero:

- botones (primario, secundario, texto, peligro) e ícono-botón;
- campos de texto, de número y de búsqueda; selector; chips de filtro;
- **stepper numérico** (kg con paso configurable, reps, segundos);
- tarjeta, lista y fila de lista, encabezado de sección;
- diálogo, hoja inferior, toast/snackbar;
- estados de vacío, carga y error;
- barra de navegación y selector de club (F1);
- insignia (por ejemplo, *base* / *propio* en el catálogo, F2).

**De dominio**, para entrenamiento y planificación:

- **tarjeta de serie**: objetivo, valor registrado, check de hecha, editada a mano, RPE;
- **visor de discos**: qué discos van por lado para un peso dado, con los colores de discos y el
  equipo del club;
- **cronómetro grande**: fase, tiempo restante, ronda, controles;
- **control de ajuste del día** (± por sesión y por ejercicio);
- **indicador de turno**: a qué atleta le toca, en modo por turnos;
- **chip de atleta** con presencia en la sesión;
- **fila de prescripción** del editor: ejercicio, series, objetivos;
- **indicador de zona de intensidad**.

### 5.3 Galería

Una app o ruta de desarrollo que muestra cada componente en sus variantes, en los dos temas y las dos
densidades. Sirve para revisar sin navegar la app y es la referencia viva del sistema. Los
componentes clave tienen tests de golden en los dos temas.

## 6. Dirección visual

### 6.1 Paleta de marca

Definida por el usuario:

| Nombre | Hex | Rol principal |
|---|---|---|
| Black | `#000000` | fondo del tema oscuro y de entrenamiento, texto del tema claro |
| Maroon | `#830000` | énfasis profundo: encabezados de marca, contenedores oscuros, texto destacado en claro |
| Dark red | `#BC0202` | **color primario**: botón principal, selección, estado activo |
| Red | `#FF0000` | acento vivo: turno activo, cronómetro, resaltados; texto de acento solo en oscuro |

### 6.2 Cómo se usa cada color, según el contraste medido

| Color | Sobre negro | Sobre `#121212` | Sobre blanco | Texto blanco encima |
|---|---|---|---|---|
| `#830000` | 1.97 | 1.75 | 10.69 | 10.69 |
| `#BC0202` | 3.15 | 2.81 | 6.67 | 6.67 |
| `#FF0000` | 5.25 | 4.69 | 4.00 | 4.00 |

De ahí salen las reglas (WCAG AA: 4.5 para texto normal, 3 para texto grande e íconos):

- **Botón primario en los dos temas**: fondo `#BC0202` con texto blanco (6.67).
- **Tema oscuro**: texto e íconos de acento en `#FF0000` (4.69 sobre `#121212`) o en los tonos
  claros derivados (6.3). `#830000` y `#BC0202` **nunca como texto sobre fondo oscuro**, solo como
  fondo de contenedores o botones con texto blanco.
- **Tema claro**: texto de acento en `#BC0202` o `#830000`. `#FF0000` **solo en elementos grandes
  o no textuales** (cronómetro, barras, indicadores), nunca en texto chico.

### 6.3 Tonos derivados ("pasteles")

Las cuatro tintas de marca no alcanzan para una interfaz completa: faltan tonos claros para fondos
de contenedores, estados suaves y el tema claro. Se derivan así:

- **Escala tonal desde la marca**: con el algoritmo HCT de Material 3, usando `#BC0202` como
  semilla, se genera una escala del tono 0 (negro) al 100 (blanco) con el mismo matiz. Los cuatro
  colores de marca se **fijan** en la escala tal cual. Los demás pasos son derivados.
- **Pasteles** = tonos altos de esa escala:
  - 90–95: fondos de contenedores en el tema claro (chips seleccionados, tarjeta activa, filas
    marcadas);
  - 80: texto e íconos de acento suaves en el tema oscuro;
  - 20–30: contenedores en el tema oscuro (entre negro y maroon).
- **Neutros**: una escala de grises con un tinte muy leve hacia el matiz de la marca, para que los
  grises "pertenezcan" al rojo en lugar de verse fríos. Va del negro de marca al blanco.

Muestra visual con los valores generados y la verificación de contraste:
<https://claude.ai/artifact/5kTa6rqaxpAekXgkYpTWcx> (**aprobada** el 2026-11-07).

### 6.4 Resto de la dirección

- **Superficies**: el tema oscuro usa **negro puro** de fondo, como la marca (y en pantallas OLED
  ahorra batería en entrenamiento), con superficies elevadas en neutros oscuros y bordes visibles
  en lugar de sombras. El tema claro usa blanco con superficies en neutros muy claros.
- **Estados**, todos fuera de la familia del rojo para que el rojo quede solo para la marca:
  - **error en naranja**, semilla `#FB8C00` (matiz 59, a 32° del rojo de marca). Se descartó un
    naranja más rojizo (`#E8590C`, a 13°) porque sus tonos claros eran casi idénticos a los de la
    marca (tono 90: `#ffdbce` contra `#ffdad4`);
  - **alerta en amarillo**, semilla `#F2C200`;
  - **éxito en verde**, semilla `#2E9D4F`.
  Los contenedores de error llevan además un borde naranja fuerte, porque en los tonos muy claros
  todos los matices se acercan.
  Además, un estado nunca se comunica solo con color: va con ícono y texto.
- **Colores de discos**: los estándar de competición (20 azul, 15 amarillo, 10 verde, 5 blanco,
  2.5 y 1.25 en neutros, 1.5 diferenciado), solo dentro del visor de discos.
- **Tipografía** (aprobada): **Inter** para todo el texto de la interfaz y **Barlow Condensed**
  (500–700) para los números grandes (peso, reps, cronómetro) y los títulos de marca, siempre con
  cifras tabulares. Las dos son de Google Fonts (licencia OFL) y se **empaquetan con la app**, no se
  descargan en cada uso, para que la PWA funcione sin señal.
- **Formas**: radios medios, iconografía de trazo.

## 7. Criterios de aceptación

1. El frontend depende de `maktub_ui` y no define colores, tamaños ni estilos de texto propios.
2. Cambiar un primitivo de color cambia toda la app en los dos temas sin tocar pantallas.
3. Entrenamiento abre en oscuro por defecto; el resto sigue al sistema; el usuario puede fijar uno.
4. Todos los pares texto/fondo de los dos temas pasan WCAG AA, verificado por un test.
5. En densidad de entrenamiento, ningún control táctil mide menos de 56 dp.
6. Los números de peso, reps y tiempo usan cifras tabulares: no se mueven al cambiar de valor.
7. La galería muestra todos los componentes en las dos densidades y los dos temas.
8. Los componentes clave tienen tests de golden en los dos temas.
9. Las fuentes funcionan sin conexión.

## 8. Supuestos a confirmar

| # | Supuesto | Por qué importa |
|---|---|---|
| S1 | El paquete se llama `maktub_ui`. | Nombre en imports y workspace. |
| S2 | La galería es una ruta solo de desarrollo dentro del frontend, no una app aparte, para no sumar otro target al monorepo. | Mantenimiento. |
| S3 | Íconos: Material Symbols (trazo). Si la dirección visual pide otros, se cambian en el paquete. | Coherencia visual. |
| S4 | Los tonos derivados (6.3) se revisan en una muestra visual antes de la tarea 3. Mientras tanto, los tokens usan la paleta de marca y tonos generados provisorios. | No bloquear F1/F2. |
| S5 | ~~El error comparte la familia del rojo.~~ **Resuelto: el error pasa al naranja** (DS5). Las acciones destructivas siempre piden confirmación. | Un botón primario rojo no debe leerse como "peligro". |

## 9. Tareas

En orden. Las tareas 1, 2 y 4 no esperan la aprobación de la dirección visual.

1. **Paquete `maktub_ui`** en el workspace, con la dependencia desde el frontend.
2. **Estructura de tokens** (primitivos, semánticos, `ThemeExtension`) y temas oscuro y claro con
   valores provisorios; densidades; test de contraste.
3. **Valores definitivos**: paleta de marca fija, escala tonal y neutros derivados aprobados, test de
   contraste con las reglas de 6.2; fuentes empaquetadas.
4. **Galería** y la infraestructura de goldens.
5. **Componentes base** que piden F1 y F2.
6. **Componentes de dominio**, a medida que los piden F8–F12 (se pueden adelantar el stepper, la
   tarjeta de serie y el visor de discos).
7. **Migrar el frontend existente** (shell, navegación de modos) al paquete.
