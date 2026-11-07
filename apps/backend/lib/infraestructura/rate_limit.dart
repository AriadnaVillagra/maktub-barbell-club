import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Attempts allowed per client and route within [attemptWindow]. Chosen in E1.8: a person fumbling
/// a login or a few devices renewing at once stay far below it; a guessing script does not.
const maxAttempts = 10;

/// Length of the counting window (fixed window, restarts on the first attempt after it ends).
const attemptWindow = Duration(minutes: 1);

/// Fixed-window attempt counter kept in process memory.
///
/// Valid because the API runs as a single instance (`max-instances=1` on Cloud Run, see "Multi-dispositivo"
/// in the design doc). Behind an interface so a shared store can replace it if that changes.
abstract interface class AttemptLimiter {
  /// Registers an attempt for [key]. Returns `null` if allowed, or how long to wait if over the limit.
  Duration? register(String key);
}

class InMemoryAttemptLimiter implements AttemptLimiter {
  InMemoryAttemptLimiter({this.max = maxAttempts, this.window = attemptWindow, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final int max;
  final Duration window;
  final DateTime Function() _now;
  final _windows = <String, _Window>{};

  @override
  Duration? register(String key) {
    final now = _now();
    if (_windows.length > 10000) _windows.removeWhere((_, w) => !now.isBefore(w.start.add(window)));

    var w = _windows[key];
    if (w == null || !now.isBefore(w.start.add(window))) {
      w = _windows[key] = _Window(now);
    }
    if (w.count >= max) return w.start.add(window).difference(now);
    w.count++;
    return null;
  }
}

class _Window {
  _Window(this.start);
  final DateTime start;
  int count = 0;
}

/// Client address. On Cloud Run the proxy appends the real peer to `X-Forwarded-For`, so the last
/// entry is trusted (earlier ones can be forged by the client).
String clientAddress(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null) {
    final last = forwarded.split(',').last.trim();
    if (last.isNotEmpty) return last;
  }
  try {
    return request.connectionInfo.remoteAddress.address;
  } catch (_) {
    return 'unknown';
  }
}

/// Rejects with 429 (`Retry-After` in seconds, `{error}` body) a `POST` to one of [paths] when the
/// client is over the limit. The request never reaches the handler, so no session is created or rotated.
/// Each path counts apart.
Middleware limitAttempts(AttemptLimiter limiter, {required Set<String> paths}) => (handler) => (context) async {
      final request = context.request;
      if (request.method == HttpMethod.post && paths.contains(request.uri.path)) {
        final wait = limiter.register('${request.uri.path}|${clientAddress(request)}');
        if (wait != null) {
          final seconds = (wait.inMilliseconds / 1000).ceil().clamp(1, 1 << 30);
          return Response.json(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'Retry-After': '$seconds'},
            body: {'error': 'Demasiados intentos. Probá de nuevo en unos segundos.'},
          );
        }
      }
      return handler(context);
    };
