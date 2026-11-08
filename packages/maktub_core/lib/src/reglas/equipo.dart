import '../modelos/base.dart';
import '../modelos/json.dart';

/// Problemas de un equipo (F2 §5): se devuelven en vez de lanzar.
enum EquipoProblem {
  /// El inventario no tiene ninguna barra.
  noBars,

  /// Alguna barra no pesa más de 0.
  barNotPositive,

  /// Algún disco no pesa más de 0.
  plateNotPositive,

  /// Dos filas de barra con el mismo peso: se suman en una con más cantidad.
  duplicateBar,

  /// Dos filas de disco con el mismo peso: se suman en una con más pares.
  duplicatePlate,

  /// Alguna cantidad está fuera de 1..[maxCantidadInventario].
  quantityOutOfRange,

  /// Demasiados pesos de disco distintos.
  tooManyPlates,
}

/// Máximo de pesos de disco distintos de un inventario.
const maxTiposDisco = 30;

/// Máximo de unidades de una misma fila del inventario.
const maxCantidadInventario = 50;

/// Una fila del inventario: un peso y cuántos hay. En discos, [cantidad] son pares.
class ItemInventario {
  const ItemInventario(this.kg, [this.cantidad = 1]);

  final double kg;
  final int cantidad;

  ItemInventario conCantidad(int nueva) => ItemInventario(kg, nueva);

  factory ItemInventario.fromJson(Json j) =>
      ItemInventario((j['kg'] as num).toDouble(), (j['cantidad'] as num? ?? 1).toInt());

  Json toJson() => {'kg': kg, 'cantidad': cantidad};

  @override
  bool operator ==(Object other) => other is ItemInventario && other.kg == kg && other.cantidad == cantidad;

  @override
  int get hashCode => Object.hash(kg, cantidad);
}

/// Inventario del club (uno por club): barras y pares de discos con su cantidad, en datos.
///
/// Sin `clubId` explícito es el estándar de plataforma ([clubPlataforma]), que usan las pruebas y los
/// clubes que aún no lo editaron. [auditoria] es nula en el estándar sin persistir.
///
/// Los pesos propuestos se ajustan a lo que se puede armar de verdad: redondear a múltiplos de 2.5
/// proponía números imposibles y perdía lo que habilitan los pares de 1.5 (23, 25.5, 28, 45.5...).
class Equipo implements DelClub {
  Equipo({
    this.clubId = clubPlataforma,
    this.barras = estandarBarras,
    this.discos = estandarDiscos,
    this.auditoria,
  });

  /// Una barra de [barraKg] y un par de cada peso de [paresDiscos].
  factory Equipo.deUnaBarra({
    String clubId = clubPlataforma,
    double barraKg = 20,
    List<double> paresDiscos = const [],
    Auditoria? auditoria,
  }) => Equipo(
    clubId: clubId,
    barras: [ItemInventario(barraKg)],
    discos: [for (final d in paresDiscos) ItemInventario(d)],
    auditoria: auditoria,
  );

  /// Barra de 20 kg y un par de 20, 15, 10, 5, 2.5, 1.5 y 1.25: 88 pesos cargables.
  static final estandar = Equipo();

  static const estandarBarras = <ItemInventario>[ItemInventario(20)];
  static const estandarDiscos = <ItemInventario>[
    ItemInventario(20),
    ItemInventario(15),
    ItemInventario(10),
    ItemInventario(5),
    ItemInventario(2.5),
    ItemInventario(1.5),
    ItemInventario(1.25),
  ];

  /// El estándar como equipo de [clubId]: lo que se crea o se asume para un club sin equipo propio.
  factory Equipo.estandarDe(String clubId, {Auditoria? auditoria}) => Equipo(clubId: clubId, auditoria: auditoria);

  @override
  final String clubId;

  final Auditoria? auditoria;

  final List<ItemInventario> barras;

  /// En cada fila, `cantidad` son pares: un disco por lado.
  final List<ItemInventario> discos;

  /// La barra que se usa si un ejercicio no indica otra: la más pesada. 0 si no hay barras.
  double get barraKg => barras.isEmpty ? 0 : barras.map((b) => b.kg).reduce((a, b) => a > b ? a : b);

  /// Todos los totales armables con la barra por defecto, de menor a mayor.
  late final List<double> cargables = cargablesCon(barraKg);

  /// La barra con la que se carga un ejercicio que pide [pedida]: esa si está en el inventario, y si no
  /// (o si no pide ninguna) la barra por defecto.
  double barraPara(double? pedida) => pedida != null && barras.any((b) => b.kg == pedida) ? pedida : barraKg;

  /// Todos los totales armables con una barra de [barra] kg, de menor a mayor.
  ///
  /// Trabaja en gramos enteros para no acumular error de coma flotante, y recorre sumas posibles por lado
  /// (no combinaciones), así que muchos pares no la hacen explotar.
  List<double> cargablesCon(double barra) {
    var porLado = <int>{0};
    for (final d in discos) {
      final gramos = (d.kg * 1000).round();
      if (gramos <= 0) continue;
      porLado = {
        for (final suma in porLado)
          for (var n = 0; n <= d.cantidad; n++) suma + n * gramos,
      };
    }
    final base = (barra * 1000).round();
    return ([for (final lado in porLado) base + 2 * lado]..sort()).map((g) => g / 1000).toList();
  }

  Equipo copyWith({List<ItemInventario>? barras, List<ItemInventario>? discos, Auditoria? auditoria}) => Equipo(
    clubId: clubId,
    barras: barras ?? this.barras,
    discos: discos ?? this.discos,
    auditoria: auditoria ?? this.auditoria,
  );

  /// Valida el inventario. Vacío si es válido.
  List<EquipoProblem> validar() {
    bool repite(List<ItemInventario> items) => items.map((i) => i.kg).toSet().length != items.length;
    bool fueraDeRango(ItemInventario i) => i.cantidad < 1 || i.cantidad > maxCantidadInventario;
    return [
      if (barras.isEmpty) EquipoProblem.noBars,
      if (barras.any((b) => !(b.kg > 0))) EquipoProblem.barNotPositive,
      if (discos.any((d) => !(d.kg > 0))) EquipoProblem.plateNotPositive,
      if (repite(barras)) EquipoProblem.duplicateBar,
      if (repite(discos)) EquipoProblem.duplicatePlate,
      if (barras.any(fueraDeRango) || discos.any(fueraDeRango)) EquipoProblem.quantityOutOfRange,
      if (discos.length > maxTiposDisco) EquipoProblem.tooManyPlates,
    ];
  }

  /// Lee también el formato anterior (`barraKg` + `paresDiscos`), que siguen teniendo los equipos ya guardados.
  factory Equipo.fromJson(Json j) {
    final clubId = '${j['clubId']}';
    final auditoria = j['auditoria'] == null
        ? null
        : Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>());
    if (j['barras'] == null && j['discos'] == null) {
      return Equipo(
        clubId: clubId,
        barras: j['barraKg'] == null ? estandarBarras : [ItemInventario((j['barraKg'] as num).toDouble())],
        discos: j['paresDiscos'] == null
            ? estandarDiscos
            : [for (final d in (j['paresDiscos'] as List)) ItemInventario((d as num).toDouble())],
        auditoria: auditoria,
      );
    }
    return Equipo(
      clubId: clubId,
      barras: [for (final b in listaJson(j['barras'])) ItemInventario.fromJson(b)],
      discos: [for (final d in listaJson(j['discos'])) ItemInventario.fromJson(d)],
      auditoria: auditoria,
    );
  }

  Json toJson() => sinNulos({
    'clubId': clubId,
    'barras': [for (final b in barras) b.toJson()],
    'discos': [for (final d in discos) d.toJson()],
    'auditoria': auditoria?.toJson(),
  });

  /// El peso cargable más cercano con la barra [barKg] (la por defecto si es nula o no está en el
  /// inventario). Ante un empate gana el menor.
  double masCercano(double kg, {double? barKg}) {
    final opciones = barKg == null ? cargables : cargablesCon(barraPara(barKg));
    var mejor = opciones.first;
    for (final c in opciones) {
      if ((c - kg).abs() < (mejor - kg).abs()) mejor = c;
    }
    return mejor;
  }
}
