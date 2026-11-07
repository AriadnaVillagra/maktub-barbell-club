import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/rate_limit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

void main() {
  var now = DateTime.utc(2026, 11, 7, 12);
  late InMemoryAttemptLimiter limiter;
  var reached = 0;

  setUp(() {
    now = DateTime.utc(2026, 11, 7, 12);
    reached = 0;
    limiter = InMemoryAttemptLimiter(max: 3, window: const Duration(minutes: 1), now: () => now);
  });

  Future<Response> call(String path, {String ip = '1.1.1.1', HttpMethod method = HttpMethod.post}) async {
    final c = _Context();
    when(() => c.request).thenReturn(Request(
      method.value,
      Uri.parse('http://localhost$path'),
      headers: {'x-forwarded-for': 'forged, $ip'},
    ));
    final handler = limitAttempts(limiter, paths: {'/auth/google', '/auth/refresh'})((_) {
      reached++;
      return Response();
    });
    return handler(c);
  }

  test('past the limit it rejects with 429 and Retry-After, without reaching the handler', () async {
    for (var i = 0; i < 3; i++) {
      expect((await call('/auth/refresh')).statusCode, HttpStatus.ok);
    }
    final r = await call('/auth/refresh');
    expect(r.statusCode, HttpStatus.tooManyRequests);
    expect(r.headers['Retry-After'], '60');
    expect(await r.json(), containsPair('error', isA<String>()));
    expect(reached, 3);
  });

  test('waiting out the window allows attempts again', () async {
    for (var i = 0; i < 4; i++) {
      await call('/auth/google');
    }
    now = now.add(const Duration(seconds: 59));
    expect((await call('/auth/google')).statusCode, HttpStatus.tooManyRequests);
    now = now.add(const Duration(seconds: 1));
    expect((await call('/auth/google')).statusCode, HttpStatus.ok);
  });

  test('counts per route and per client; the forged first X-Forwarded-For entry is ignored', () async {
    for (var i = 0; i < 4; i++) {
      await call('/auth/google');
    }
    expect((await call('/auth/refresh')).statusCode, HttpStatus.ok);
    expect((await call('/auth/google', ip: '2.2.2.2')).statusCode, HttpStatus.ok);
  });

  test('does not limit logout or non-POST requests', () async {
    for (var i = 0; i < 10; i++) {
      expect((await call('/auth/logout')).statusCode, HttpStatus.ok);
      expect((await call('/auth/google', method: HttpMethod.get)).statusCode, HttpStatus.ok);
    }
  });
}
