import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session/presentation/providers.dart';
import 'cliente_api.dart';

/// The API client for everything except the auth endpoints: sends the session's access token and
/// renews it on a 401.
final clienteApiProvider = Provider<ClienteApi>(
  (ref) => ClienteApi(
    base: Uri.parse(urlApi),
    cliente: ref.watch(httpClientProvider),
    auth: SessionTokenSource(ref.watch(sessionManagerProvider)),
  ),
);
