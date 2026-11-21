import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../../core/red/cliente_api.dart';
import '../data/http_club_request_api.dart';
import '../data/http_club_requests_repository.dart';
import '../domain/club_request_repositories.dart';

/// Sending a request from the sign-in screen, without a session.
final clubRequestApiProvider = Provider<ClubRequestApi>(
  (ref) => HttpClubRequestApi(ClienteApi(base: Uri.parse(urlApi), cliente: ref.watch(httpClientProvider))),
);

final clubRequestsRepositoryProvider = Provider<ClubRequestsRepository>(
  (ref) => HttpClubRequestsRepository(ref.watch(clienteApiProvider)),
);

/// The pending club requests a platform admin reviews.
final pendingClubRequestsProvider = FutureProvider<List<ClubRequest>>(
  (ref) => ref.watch(clubRequestsRepositoryProvider).pending(),
);
