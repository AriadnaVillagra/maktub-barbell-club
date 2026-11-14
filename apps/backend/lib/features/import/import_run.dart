/// The importer of the old spreadsheet (E8, design.md 3.5 "Scripts"): a list of steps run in order by
/// `tool/importar.dart`. Each step reads its CSVs, compares them with what the club already has and writes
/// only through the existing use cases (never straight to Mongo). Every step is idempotent and supports a
/// dry run that reports what it would do.
///
/// Later issues (E8.3 athletes/RMs, E8.4 plans, E8.5 history) add an [ImportStep] and register it in the
/// script; they reuse [importedId] for stable ids and [ImportAdjustments] for decisions about the data.
library;

import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_core/maktub_core.dart';

/// Author recorded in the audit of imported documents (not a real user).
const importAuthor = 'sistema:importador';

/// What every step receives.
class ImportRun {
  const ImportRun({required this.club, required this.sheets, required this.adjustments, required this.dryRun});

  /// The club the data goes to, acting as [importAuthor].
  final ClubContext club;
  final SheetDirectory sheets;
  final ImportAdjustments adjustments;

  /// When true nothing is written: the report says what would be.
  final bool dryRun;
}

abstract interface class ImportStep {
  /// The name used in the report and in `--solo`.
  String get name;

  Future<ImportReport> run(ImportRun run);
}

/// The context the importer acts with: coach and club admin of [clubId], and platform admin, because
/// adding a sheet category to a default exercise is a change to the default catalog (tracker, "Para E8.2").
ClubContext importClubContext(String clubId, TipoClub clubType) => ClubContext(
  clubId: clubId,
  userId: importAuthor,
  roles: const {Rol.coach, Rol.adminClub},
  clubType: clubType,
  isPlatformAdmin: true,
);

/// The stable id of a document the importer creates from the sheet row whose id is [sheetId]. Being
/// derived from the club and the sheet id is what makes a re-run find what the previous run created,
/// and lets a later step resolve a sheet id without a lookup table.
String importedId(String clubId, String sheetId) => '$clubId-$sheetId';
