import '../../domain/entities/sesion_del_dia.dart';

/// 62.5 → "62.5", 60.0 → "60".
String numeroCorto(num? n) {
  if (n == null) return '—';
  return n == n.roundToDouble() ? n.round().toString() : n.toString();
}

String kg(double? valor) => valor == null ? '— kg' : '${numeroCorto(valor)} kg';

String etiquetaGrupo(int cantidad) => switch (cantidad) {
      1 => '',
      2 => 'Biserie',
      3 => 'Triserie',
      _ => 'Serie de $cantidad',
    };

/// "80% de 70 kg (sentadilla) · RPE 8", o la alerta de qué falta cargar.
({String texto, bool alerta}) metaDeItem(ItemCargado it, int ajusteSesion) {
  final partes = <String>[];
  var alerta = false;
  final conRm = it.plantilla.where((s) => s.porRm).toList();

  if (conRm.isNotEmpty) {
    final basico = it.ejercicio.referencia?.etiqueta ?? '';
    final rm = conRm.first.rm;
    final pcts = {for (final s in conRm) s.pctAplicado(it.ajusteEfectivo(ajusteSesion))!};
    if (rm == null) {
      alerta = true;
      partes.add('falta el RM de $basico');
    } else if (pcts.length == 1) {
      partes.add('${numeroCorto(pcts.single)}% de ${numeroCorto(rm)} kg ($basico)');
    } else {
      final orden = pcts.toList()..sort();
      partes.add('${numeroCorto(orden.first)}–${numeroCorto(orden.last)}% de ${numeroCorto(rm)} kg ($basico)');
    }
  } else if (it.plantilla.any((s) => s.pesoFijo == null)) {
    alerta = true;
    partes.add('sin peso fijo cargado para este atleta');
  } else {
    partes.add('peso fijo');
  }

  if (it.rpe != null) partes.add('RPE ${it.rpe}');
  return (texto: partes.join(' · '), alerta: alerta);
}

/// "5 × 3 / 62.5 kg" si todas las series son iguales; si no, "8×20 · 5×40 ...".
String resumenDeSeries(List<SerieVista> series) {
  if (series.isEmpty) return '';
  final primera = series.first;
  final uniforme = series.every((s) => s.pesoKg == primera.pesoKg && s.reps == primera.reps);
  if (uniforme) return '${series.length} × ${primera.reps ?? '?'}\n${kg(primera.pesoKg)}';
  return series.map((s) => '${s.reps ?? '?'}×${numeroCorto(s.pesoKg)}').join(' · ');
}
