import 'package:go_router/go_router.dart';

import 'exercise_detail_page.dart';
import 'exercise_form_page.dart';
import 'exercise_list_page.dart';

/// Exercise catalog routes, relative to a mode: `<mode>/catalogo`, `.../ejercicios/nuevo`,
/// `.../ejercicios/:id` and `.../ejercicios/:id/editar`. Athletes reach them through training mode
/// (they cannot enter planning); coaches through either one. Add the result as a child of each mode route.
GoRoute exerciseCatalogRoute() => GoRoute(
  path: 'catalogo',
  builder: (_, state) => ExerciseListPage(basePath: state.matchedLocation),
  routes: [
    GoRoute(
      path: 'ejercicios/nuevo',
      builder: (_, state) => ExerciseFormPage(
        basePath: _base(state),
        copyFromId: state.uri.queryParameters['desde'],
      ),
    ),
    GoRoute(
      path: 'ejercicios/:id',
      builder: (_, state) => ExerciseDetailPage(
        basePath: _base(state),
        exerciseId: state.pathParameters['id']!,
      ),
      routes: [
        GoRoute(
          path: 'editar',
          builder: (_, state) => ExerciseFormPage(
            basePath: _base(state),
            exerciseId: state.pathParameters['id'],
          ),
        ),
      ],
    ),
  ],
);

/// `<mode>/catalogo` from any location under it.
String _base(GoRouterState state) {
  final path = state.uri.path;
  return path.substring(0, path.indexOf('/catalogo') + '/catalogo'.length);
}
