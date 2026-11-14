/// What one import step did, or would do in a dry run. Lines are in Spanish: the script prints them.
class ImportReport {
  ImportReport(this.step);

  final String step;

  /// New documents.
  final created = <String>[];

  /// Existing documents that were changed (only additive changes, such as a category added).
  final updated = <String>[];

  /// Already there and nothing to change.
  final unchanged = <String>[];

  /// Already there but different from the sheet: left as they are, because the app may have changed
  /// them on purpose. Listed so a person can review them.
  final differing = <String>[];

  /// Rows that were not imported, and why.
  final problems = <String>[];

  /// Findings about the data that did not stop anything (duplicated ids, rows merged, mappings).
  final notes = <String>[];

  bool get hasChanges => created.isNotEmpty || updated.isNotEmpty;

  String summary({required bool dryRun}) =>
      '$step: ${created.length} ${dryRun ? 'a crear' : 'creados'}, '
      '${updated.length} ${dryRun ? 'a actualizar' : 'actualizados'}, ${unchanged.length} sin cambios, '
      '${differing.length} difieren (no se tocan), ${problems.length} problemas, ${notes.length} avisos.';

  void writeTo(StringSink out, {required bool dryRun, bool verbose = false}) {
    void section(String title, List<String> lines) {
      if (lines.isEmpty) return;
      out.writeln('  $title (${lines.length}):');
      for (final l in lines) {
        out.writeln('    - $l');
      }
    }

    out.writeln('== $step${dryRun ? ' (simulación: no se escribe nada)' : ''}');
    section(dryRun ? 'Se crearía' : 'Creado', created);
    section(dryRun ? 'Se actualizaría' : 'Actualizado', updated);
    if (verbose) section('Sin cambios', unchanged);
    section('Difiere de la planilla (no se toca)', differing);
    section('Problemas (fila no importada)', problems);
    section('Avisos', notes);
    out.writeln('  ${summary(dryRun: dryRun)}');
  }
}
