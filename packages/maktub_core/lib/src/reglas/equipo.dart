/// Equipo disponible. Los pesos propuestos se ajustan a lo que se puede armar de verdad:
/// redondear a múltiplos de 2.5 proponía números imposibles y perdía lo que habilitan
/// los pares de 1.5 (23, 25.5, 28, 45.5...).
class Equipo {
  Equipo({this.barraKg = 20, this.paresDiscos = const [20, 15, 10, 5, 2.5, 1.5, 1.25]})
      : cargables = _calcularCargables(barraKg, paresDiscos);

  /// Barra de 20 kg y pares de 20, 15, 10, 5, 2.5, 1.5 y 1.25: 88 pesos cargables.
  static final estandar = Equipo();

  final double barraKg;

  /// Un disco de cada peso por lado.
  final List<double> paresDiscos;

  /// Todos los totales armables, ordenados de menor a mayor.
  final List<double> cargables;

  /// El peso cargable más cercano. Ante un empate gana el menor.
  double masCercano(double kg) {
    var mejor = cargables.first;
    for (final c in cargables) {
      if ((c - kg).abs() < (mejor - kg).abs()) mejor = c;
    }
    return mejor;
  }

  static List<double> _calcularCargables(double barra, List<double> pares) {
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
