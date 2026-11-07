import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/rate_limit.dart';

// One limiter per process (single instance, see `rate_limit.dart`). Logout is not limited.
final _limiter = InMemoryAttemptLimiter();

Handler middleware(Handler handler) =>
    handler.use(limitAttempts(_limiter, paths: {'/auth/google', '/auth/refresh'}));
