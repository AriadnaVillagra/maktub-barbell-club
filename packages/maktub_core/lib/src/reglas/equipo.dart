import '../modelos/base.dart';
import '../modelos/json.dart';

/// Problemas de un equipo (F2 §5): se devuelven en vez de lanzar.
enum EquipoProblem {
  /// La barra no pesa más de 0.
  barNotPositive,

  /// Algún disco no pesa más de 0.
  plateNotPositive,

  /// Dos pares del mismo peso: no cambian lo cargable.
  duplicatePlate,

  /// Demasiados pares: las combinaciones crecen como 2^n.
  tooManyPlates,
}

/// Máximo de pares de discos distintos de un equipo.
const maxParesDiscos = 12;

/// Equipo del club (uno por club, F2 S3), en datos con el estándar por defecto.
///
/// Sin `clubId` explícito es el estándar de plataforma ([clubPlataforma]), que usan las pruebas y los
/// clubes que aún no lo editaron. [auditoria] es nula en el estándar sin persistir.
///
/// Equipo disponible. Los pesos propuestos se ajustan a lo que se puede armar de verdad:
/// redondear a múltiplos de 2.5 proponía números imposibles y perdía lo que habilitan
/// los pares de 1.5 (23, 25.5, 28, 45.5...).
class Equipo implements DelClub {
  Equipo({
    this.clubId = clubPlataforma,
    this.barraKg = estandarBarraKg,
    this.paresDiscos = estandarParesDiscos,
    this.auditoria,
  }) : cargables = _calcularCargables(barraKg, paresDiscos);

  /// Barra de 20 kg y pares de 20, 15, 10, 5, 2.5, 1.5 y 1.25: 88 pesos cargables.
  static final estandar = Equipo();

  static const estandarBarraKg = 20.0;
  static const estandarParesDiscos = <double>[20, 15, 10, 5, 2.5, 1.5, 1.25];

  /// El estándar como equipo de [clubId]: lo que se crea o se asume para un club sin equipo propio.
  factory Equipo.estandarDe(String clubId, {Auditoria? auditoria}) => Equipo(clubId: clubId, auditoria: auditoria);

  @override
  final String clubId;

  final Auditoria? auditoria;

  final double barraKg;

  /// Un disco de cada peso por lado.
  final List<double> paresDiscos;

  /// Todos los totales armables, ordenados de menor a mayor.
  final List<double> cargables;

  Equipo copyWith({double? barraKg, List<double>? paresDiscos, Auditoria? auditoria}) => Equipo(
    clubId: clubId,
    barraKg: barraKg ?? this.barraKg,
    paresDiscos: paresDiscos ?? this.paresDiscos,
    auditoria: auditoria ?? this.auditoria,
  );

  /// Valida barra y discos. Vacío si el equipo es válido.
  List<EquipoProblem> validar() {
    final problemas = <EquipoProblem>{};
    if (!(barraKg > 0)) problemas.add(EquipoProblem.barNotPositive);
    if (paresDiscos.any((d) => !(d > 0))) problemas.add(EquipoProblem.plateNotPositive);
    if (paresDiscos.toSet().length != paresDiscos.length) problemas.add(EquipoProblem.duplicatePlate);
    if (paresDiscos.length > maxParesDiscos) problemas.add(EquipoProblem.tooManyPlates);
    return problemas.toList();
  }

  factory Equipo.fromJson(Json j) => Equipo(
    clubId: '${j['clubId']}',
    barraKg: (j['barraKg'] as num?)?.toDouble() ?? estandarBarraKg,
    paresDiscos: j['paresDiscos'] == null
        ? estandarParesDiscos
        : [for (final d in (j['paresDiscos'] as List)) (d as num).toDouble()],
    auditoria: j['auditoria'] == null ? null : Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
  );

  Json toJson() =>
      sinNulos({'clubId': clubId, 'barraKg': barraKg, 'paresDiscos': paresDiscos, 'auditoria': auditoria?.toJson()});

  /// El peso cargable más cercano. Ante un empate gana el menor.
  double masCercano(double kg) {
    var mejor = cargables.first;
    for (final c in cargables) {
      if ((c - kg).abs() < (mejor - kg).abs()) mejor = c;
    }
    return mejor;
  }

  static List<double> _calcularCargables(double barra, List<double> pares) {
    // Un equipo inválido por exceso de pares no se expande: 2^n colgaría al construirlo.
    if (pares.length > maxParesDiscos) return [barra];
    final totales = <double>{};
    void recorrer(int i, double porLado) {
      if (i == pares.length) {
        totales.add(barra + 2 * porLado);
        return;
      }
      recorrer(i + 1, porLado);
      recorrer(i + 1, porLado + pares[i]);
    }

    recorrer(0, 0);
    return totales.toList()..sort();
  }
}
