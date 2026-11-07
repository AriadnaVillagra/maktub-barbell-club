import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/api_providers.dart';
import '../../session/domain/session_manager.dart';
import '../../session/presentation/providers.dart';
import '../data/http_me_repository.dart';
import '../domain/me.dart';
import '../domain/me_repository.dart';

final meRepositoryProvider = Provider<MeRepository>(
  (ref) => HttpMeRepository(ref.watch(clienteApiProvider)),
);

/// Who the signed-in user is. Null without a session; fetched again whenever the session changes.
final meProvider = FutureProvider<Me?>((ref) async {
  if (ref.watch(sessionControllerProvider) != SessionStatus.signedIn) {
    return null;
  }
  return ref.watch(meRepositoryProvider).fetch();
});

/// Whether the user can plan in the active club: null while it is not known yet. When `GET /me`
/// fails the answer is false (the API enforces the rule anyway); a retry comes with the next session.
final canPlanProvider = Provider<bool?>((ref) {
  final me = ref.watch(meProvider);
  if (me.isLoading && !me.hasValue) {
    return null;
  }
  return me.value?.canPlan ?? false;
});
