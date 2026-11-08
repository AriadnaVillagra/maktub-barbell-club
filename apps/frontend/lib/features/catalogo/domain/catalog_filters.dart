import 'package:maktub_core/maktub_core.dart';

/// Which origin a management list shows.
enum ScopeFilter { all, base, club }

/// Whether an item passes the list filters: its origin matches [scope], and it is active, or archived
/// when [showArchived] (never both at once).
bool matchesCatalogFilters(
  DelClub item,
  CatalogStatus status, {
  ScopeFilter scope = ScopeFilter.all,
  bool showArchived = false,
}) {
  final inScope = switch (scope) {
    ScopeFilter.all => true,
    ScopeFilter.base => scopeOf(item) == CatalogScope.base,
    ScopeFilter.club => scopeOf(item) == CatalogScope.club,
  };
  return inScope && (status == CatalogStatus.archived) == showArchived;
}
