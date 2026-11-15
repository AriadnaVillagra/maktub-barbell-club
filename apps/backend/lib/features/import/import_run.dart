/// The importer of the old spreadsheet (E8, design.md 3.5 "Scripts"): a list of steps run in order by
/// `tool/importar.dart`. Each step reads its CSVs, compares them with what the club already has and writes
/// only through the existing use cases (never straight to Mongo). Every step is idempotent and supports a
/// dry run that reports what it would do.
///
/// Later issues (E8.3 athletes/RMs, E8.4 plans, E8.5 history) add an [ImportStep] and register it in the
/// script; they reuse [importedId] for stable ids and [ImportAdjustments] for decisions about the data.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
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

/// The stable id of a document built from a sheet row that has no id of its own (Registro, Tiempos), from its
/// natural key [parts]: a UUID in the shape of version 5 (SHA-1 of club, [kind] and parts). The same row gives
/// the same id on every run, so a re-run overwrites instead of duplicating; it also fits the ids the app's
/// clients generate (block times accept at most 64 letters, digits, `-` and `_`).
String stableImportId(String clubId, String kind, List<Object> parts) {
  final bytes = sha1.convert(utf8.encode(['maktub-import', clubId, kind, ...parts].join('\u0000'))).bytes.sublist(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
