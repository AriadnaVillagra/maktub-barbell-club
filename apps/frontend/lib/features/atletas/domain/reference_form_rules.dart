/// What the sheet's edit form records.
enum ReferenceKind { rm, factor, fixedWeight }

/// A number typed by the coach (comma or point as decimal separator). Null unless it is > 0.
double? parsePositive(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite && v > 0 ? v : null;
}
