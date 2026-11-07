import 'package:maktub_core/maktub_core.dart';

/// Lowercase without Spanish diacritics, so "sentadilla" finds "Sentadilla" and "pres" finds "Press".
String normalizeForSearch(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString().trim();
}

/// What the exercise picker shows: only active exercises visible to [clubId] (base or the club's own)
/// that belong to [categoryId] (all when null) and whose name contains [query]. The ones in
/// [recentIds] come first, in that order; the rest keep the order of [exercises] (by name).
List<Exercise> pickableExercises(
  List<Exercise> exercises, {
  required String clubId,
  String? categoryId,
  String query = '',
  List<String> recentIds = const [],
}) {
  final q = normalizeForSearch(query);
  final matches = [
    for (final e in exercises)
      if (e.isActive &&
          isVisibleTo(e, clubId) &&
          (categoryId == null || e.categoryIds.contains(categoryId)) &&
          (q.isEmpty || normalizeForSearch(e.name).contains(q)))
        e,
  ];
  final rank = {for (final (i, id) in recentIds.indexed) id: i};
  final recent = matches.where((e) => rank.containsKey(e.id)).toList()
    ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  return [...recent, ...matches.where((e) => !rank.containsKey(e.id))];
}
