/// Ayudas de lectura de JSON tolerantes a números que llegan como int o double.
library;

typedef Json = Map<String, dynamic>;

double? numOpcional(Object? v) => switch (v) {
      null => null,
      final num n => n.toDouble(),
      final String s when s.trim().isEmpty => null,
      final String s => double.parse(s),
      _ => throw FormatException('Número inválido: $v'),
    };

int? enteroOpcional(Object? v) => numOpcional(v)?.round();

String? textoOpcional(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

List<Json> listaJson(Object? v) => [for (final e in (v as List? ?? const [])) (e as Map).cast<String, dynamic>()];

/// Elimina las claves con valor nulo para que el JSON quede compacto.
Json sinNulos(Json m) => {
      for (final e in m.entries)
        if (e.value != null) e.key: e.value,
    };
