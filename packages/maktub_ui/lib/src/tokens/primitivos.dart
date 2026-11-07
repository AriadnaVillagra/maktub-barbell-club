import 'dart:ui';

/// Capa 1: valores crudos. **No se usan directo** fuera de `tokens/` y `tema/`:
/// las pantallas y los componentes leen los semánticos.
///
/// Paleta APROBADA (F17 §6, decisión DS6 de docs/diseno.md, 2026-11-07). Escalas HCT de
/// material-color-utilities; el número de cada nombre es el tono (0 negro … 100 blanco).
/// Cambiar la identidad visual es cambiar este archivo.
abstract final class Paleta {
  static const negro = Color(0xFF000000);
  static const blanco = Color(0xFFFFFFFF);

  // Marca: semilla #BC0202. Los tres colores de marca están fijados en su tono (~26, ~39, ~53).
  static const maroon = Color(0xFF830000);
  static const rojoOscuro = Color(0xFFBC0202); // primario
  static const rojo = Color(0xFFFF0000); // acento vivo: solo elementos grandes o no textuales en claro
  static const marca10 = Color(0xFF410000);
  static const marca20 = Color(0xFF690000);
  static const marca80 = Color(0xFFFFB4A8);
  static const marca90 = Color(0xFFFFDAD4);

  // Neutros: matiz de la marca con croma 4.
  static const neutro5 = Color(0xFF15100F);
  static const neutro10 = Color(0xFF201A19);
  static const neutro15 = Color(0xFF2B2423);
  static const neutro20 = Color(0xFF362F2E);
  static const neutro50 = Color(0xFF7F7573);
  static const neutro70 = Color(0xFFB4A9A7);
  static const neutro90 = Color(0xFFEDE0DD);
  static const neutro92 = Color(0xFFF3E5E3);
  static const neutro95 = Color(0xFFFBEEEC);
  static const neutro98 = Color(0xFFFFF8F6);

  // Neutros variantes: croma 8, para bordes y texto secundario.
  static const neutroVar20 = Color(0xFF3B2D2B);
  static const neutroVar30 = Color(0xFF534341);
  static const neutroVar40 = Color(0xFF6B5A58);
  static const neutroVar50 = Color(0xFF857370);
  static const neutroVar60 = Color(0xFFA08C89);
  static const neutroVar80 = Color(0xFFD8C2BE);
  static const neutroVar90 = Color(0xFFF5DDDA);

  // Error: naranja, semilla #FB8C00 (fuera de la familia roja de la marca).
  static const error10 = Color(0xFF2E1500);
  static const error20 = Color(0xFF4C2700);
  static const error40 = Color(0xFF8F4E00);
  static const error70 = Color(0xFFFF8F06);
  static const error90 = Color(0xFFFFDCC2);

  // Alerta: amarillo, semilla #F2C200.
  static const alerta30 = Color(0xFF574400);
  static const alerta40 = Color(0xFF745B00);
  static const alerta80 = Color(0xFFF1C100);
  static const alerta90 = Color(0xFFFFE08A);

  // Éxito: verde, semilla #2E9D4F.
  static const exito30 = Color(0xFF005321);
  static const exito40 = Color(0xFF006E2F);
  static const exito80 = Color(0xFF71DC86);
  static const exito90 = Color(0xFF8DFAA0);

  // Azul: terciario (fases de trabajo del cronómetro) y marca de serie editada. No definido en
  // la paleta aprobada; se revisa cuando lleguen esos componentes.
  static const azul300 = Color(0xFF8AB4FF);
  static const azul700 = Color(0xFF2453B3);

  // Discos: colores de la muestra aprobada. Solo dentro del visor de discos.
  static const disco25 = Color(0xFFD32F2F);
  static const disco20 = Color(0xFF1D4FD6);
  static const disco15 = Color(0xFFF2C200);
  static const disco10 = Color(0xFF2E9D4F);
  static const disco5 = Color(0xFFF4F1EE);
  static const disco2_5 = Color(0xFF2B2423);
  static const disco1_5 = Color(0xFF7F7573);
  static const disco1_25 = Color(0xFFB4A9A7);
  static const discoOtro = Color(0xFF59504F);

  // Zonas de intensidad Z1..Z5: de frío a caliente. No definidas en la paleta aprobada.
  static const zona1 = Color(0xFF8FA3B8);
  static const zona2 = Color(0xFF4CAF7A);
  static const zona3 = Color(0xFFE3C13B);
  static const zona4 = Color(0xFFF08A24);
  static const zona5 = Color(0xFFE5483B);
}

/// Escala de espaciado, de 4 en 4 (F17 §5.1).
abstract final class Espacio {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

abstract final class Radios {
  static const chico = 6.0;
  static const medio = 12.0;
  static const grande = 20.0;
  static const pastilla = 999.0;
}

/// Grosor de bordes: en oscuro se separan superficies con bordes, no sombras.
abstract final class Borde {
  static const fino = 1.0;
  static const marcado = 2.0;
}

/// Anchos donde cambia el layout (Material 3: compacto / medio / expandido).
enum TamanoPantalla {
  compacto,
  medio,
  expandido;

  static const anchoMedio = 600.0;
  static const anchoExpandido = 840.0;

  static TamanoPantalla para(double ancho) => ancho >= anchoExpandido
      ? expandido
      : ancho >= anchoMedio
          ? medio
          : compacto;
}
