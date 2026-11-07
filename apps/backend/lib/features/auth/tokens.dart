/// Token mechanics for the API's own login sessions (F1, "Identidad"). Pure: no I/O, the clock is passed in.
///
/// - Access token: short-lived, signed (JWT, HS256), checked without touching the database.
/// - Refresh token: `<sessionId>.<secret>`, random, stored only as a SHA-256 hash, rotated on every use.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const accessTokenLifetime = Duration(minutes: 15);

/// Sliding: every refresh pushes the expiry forward again.
const refreshTokenLifetime = Duration(days: 30);

final _random = Random.secure();

/// Random URL-safe text with [bytes] bytes of entropy.
String randomToken([int bytes = 32]) =>
    base64Url.encode(Uint8List.fromList(List.generate(bytes, (_) => _random.nextInt(256)))).replaceAll('=', '');

/// Random id for documents created by the auth slices (hex, 24 chars like an ObjectId).
String newId() => List.generate(12, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

String hashSecret(String secret) => sha256.convert(utf8.encode(secret)).toString();

/// Compares in constant time so the comparison does not leak how many characters matched.
bool sameText(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Who an access token belongs to.
class AccessClaims {
  const AccessClaims({required this.userId, required this.sessionId, required this.expiresAt});

  final String userId;
  final String sessionId;
  final DateTime expiresAt;
}

/// Signs and verifies access tokens with an HMAC secret.
class AccessTokenCodec {
  AccessTokenCodec(String secret) : _hmac = Hmac(sha256, utf8.encode(secret)) {
    if (secret.length < 32) throw ArgumentError('The token secret must have at least 32 characters.');
  }

  /// From `TOKEN_SECRET`. Without it (local development) a random secret is used: access tokens then
  /// stop being valid on every restart and the app simply renews them with its refresh token.
  factory AccessTokenCodec.fromEnvironment() {
    final secret = Platform.environment['TOKEN_SECRET'];
    if (secret != null && secret.isNotEmpty) return AccessTokenCodec(secret);
    // stdout, not stderr: `dart_frog dev` kills the server on any stderr output before hot reload is up.
    stdout.writeln('TOKEN_SECRET is not set: using a random secret for this process.');
    return AccessTokenCodec(randomToken(48));
  }

  final Hmac _hmac;

  static final _header = _encode({'alg': 'HS256', 'typ': 'JWT'});

  ({String token, DateTime expiresAt}) issue({required String userId, required String sessionId, required DateTime now}) {
    final expiresAt = now.toUtc().add(accessTokenLifetime);
    final payload = _encode({
      'sub': userId,
      'sid': sessionId,
      'iat': _seconds(now),
      'exp': _seconds(expiresAt),
    });
    return (token: '$_header.$payload.${_sign('$_header.$payload')}', expiresAt: expiresAt);
  }

  /// `null` if the token is malformed, tampered with or expired.
  AccessClaims? verify(String token, {required DateTime now}) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _header) return null;
    if (!sameText(_sign('${parts[0]}.${parts[1]}'), parts[2])) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch((payload['exp'] as int) * 1000, isUtc: true);
      if (!now.toUtc().isBefore(expiresAt)) return null;
      return AccessClaims(userId: payload['sub'] as String, sessionId: payload['sid'] as String, expiresAt: expiresAt);
    } on Object {
      return null;
    }
  }

  String _sign(String data) => base64Url.encode(_hmac.convert(utf8.encode(data)).bytes).replaceAll('=', '');

  static String _encode(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  static int _seconds(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;
}

/// A refresh token as the app holds it: `<sessionId>.<secret>`.
class RefreshToken {
  const RefreshToken(this.sessionId, this.secret);

  factory RefreshToken.generate(String sessionId) => RefreshToken(sessionId, randomToken());

  /// `null` if it does not have the expected shape.
  static RefreshToken? parse(String text) {
    final dot = text.indexOf('.');
    if (dot <= 0 || dot == text.length - 1) return null;
    return RefreshToken(text.substring(0, dot), text.substring(dot + 1));
  }

  final String sessionId;
  final String secret;

  String get hash => hashSecret(secret);

  @override
  String toString() => '$sessionId.$secret';
}

/// The token in `Authorization: Bearer <token>`, or `null`.
String? bearerToken(Map<String, String> headers) {
  final value = headers['authorization'] ?? headers['Authorization'];
  if (value == null) return null;
  final match = RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false).firstMatch(value.trim());
  return match?.group(1);
}
