/// Design system de Maktub Barbell Club (docs/features/F17-design-system.md).
///
/// Tres capas: primitivos (`Paleta`, `Espacio`, `Radios`…) → semánticos (`ColorScheme`,
/// `ColoresMaktub`, `NumerosMaktub`, `Densidad`) → componentes (temas de Material y, más
/// adelante, componentes propios). Las pantallas no usan colores, tamaños ni estilos
/// literales: solo tokens (`context.colores`, `Espacio.l`…) o componentes de este paquete.
library;

export 'src/componentes/sign_in_panel.dart';
export 'src/galeria/galeria.dart' show GaleriaMaktub, GaleriaDeModo, Muestrario;
export 'src/tema/contexto.dart';
export 'src/tema/modo.dart';
export 'src/tema/tema_maktub.dart';
export 'src/tokens/colores.dart' show ColoresMaktub, ParColor;
export 'src/tokens/contraste.dart';
export 'src/tokens/densidad.dart';
export 'src/tokens/primitivos.dart' show Espacio, Radios, Borde, TamanoPantalla;
export 'src/tokens/texto.dart' show NumerosMaktub, Familias;
