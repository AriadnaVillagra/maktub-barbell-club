/// Verification of Google ID tokens (F1, "Identidad"), without any Google SDK: the RS256 signature is
/// checked against the public keys Google publishes as a JWKS, plus `iss`, `aud`, `exp` and
/// `email_verified`. Fetching that JWKS over plain HTTP is the only contact with Google, so the backend
/// stays portable to any VM.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// OAuth client ID of the app in GCP project `maktub-514012` (E1.1). Not a secret: it is the `aud`
/// every ID token must carry. `GOOGLE_CLIENT_ID` overrides it.
const defaultGoogleClientId = '312703406459-c6kmar4snieeg2o1bqi8446rq498ujgg.apps.googleusercontent.com';

/// Where Google publishes the keys that sign ID tokens.
final googleJwksUri = Uri.parse('https://www.googleapis.com/oauth2/v3/certs');

const _googleIssuers = {'accounts.google.com', 'https://accounts.google.com'};

/// Tolerance for clock differences with Google when checking `exp`.
const clockLeeway = Duration(seconds: 30);

/// Who Google says the token belongs to.
class GoogleIdentity {
  const GoogleIdentity({required this.sub, required this.email});

  /// Stable Google account id. The email can change; this does not.
  final String sub;
  final String email;
}

enum GoogleTokenRejection { malformed, unsupportedAlgorithm, unknownKey, invalidSignature, wrongIssuer, wrongAudience, expired, emailNotVerified }

/// The ID token is not acceptable. Callers answer 401 without telling the client which check failed.
class InvalidGoogleToken implements Exception {
  const InvalidGoogleToken(this.reason);

  final GoogleTokenRejection reason;

  @override
  String toString() => 'InvalidGoogleToken(${reason.name})';
}

/// An RSA public key (modulus and public exponent), as found in a JWK.
class RsaPublicKey {
  RsaPublicKey(this.modulus, this.exponent);

  /// From a JWK with `kty: RSA`; `n` and `e` are unsigned big-endian base64url.
  factory RsaPublicKey.fromJwk(Map<String, dynamic> jwk) =>
      RsaPublicKey(_bigIntFrom(_base64UrlBytes(jwk['n'] as String)), _bigIntFrom(_base64UrlBytes(jwk['e'] as String)));

  final BigInt modulus;
  final BigInt exponent;

  int get lengthInBytes => (modulus.bitLength + 7) ~/ 8;

  /// RSASSA-PKCS1-v1_5 with SHA-256 (RFC 8017 §8.2.2): rebuilds the expected encoded message and
  /// compares it whole, so no part of the decrypted signature is parsed.
  bool verifyRs256(List<int> message, List<int> signature) {
    final k = lengthInBytes;
    if (signature.length != k) return false;
    final s = _bigIntFrom(signature);
    if (s >= modulus) return false;
    final encoded = _bytesOf(s.modPow(exponent, modulus), k);
    final expected = emsaPkcs1Sha256(message, k);
    if (expected == null) return false;
    var diff = 0;
    for (var i = 0; i < k; i++) {
      diff |= encoded[i] ^ expected[i];
    }
    return diff == 0;
  }
}

const _sha256DigestInfo = [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20];

/// `0x00 0x01 FF..FF 0x00 DigestInfo(SHA-256(message))`, [length] bytes long, or `null` if it does not fit.
Uint8List? emsaPkcs1Sha256(List<int> message, int length) {
  final t = [..._sha256DigestInfo, ...sha256.convert(message).bytes];
  if (length < t.length + 11) return null;
  return Uint8List(length)
    ..[1] = 0x01
    ..fillRange(2, length - t.length - 1, 0xff)
    ..setRange(length - t.length, length, t);
}

/// What one download of the JWKS returned: the keys by `kid`, and how long Google says to cache them.
class Jwks {
  const Jwks(this.keys, {this.maxAge});

  /// Parses the JWKS body; keys that are not RSA (or not for RS256) are skipped.
  factory Jwks.parse(String body, {Duration? maxAge}) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    return Jwks({
      for (final jwk in (json['keys'] as List).cast<Map<String, dynamic>>())
        if (jwk['kty'] == 'RSA' && (jwk['alg'] ?? 'RS256') == 'RS256' && jwk['kid'] is String) jwk['kid'] as String: RsaPublicKey.fromJwk(jwk),
    }, maxAge: maxAge);
  }

  final Map<String, RsaPublicKey> keys;
  final Duration? maxAge;
}

/// Downloads Google's JWKS with `dart:io` and reads `max-age` from `Cache-Control`.
Future<Jwks> fetchGoogleJwks() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(googleJwksUri)).close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) throw HttpException('Google JWKS answered ${response.statusCode}', uri: googleJwksUri);
    return Jwks.parse(body, maxAge: maxAgeFrom(response.headers.value(HttpHeaders.cacheControlHeader)));
  } finally {
    client.close();
  }
}

Duration? maxAgeFrom(String? cacheControl) {
  final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl ?? '');
  return match == null ? null : Duration(seconds: int.parse(match.group(1)!));
}

/// Google's signing keys, cached for as long as Google says. Google rotates them every few days and
/// publishes the next one in advance; a token signed with a `kid` not in the cache triggers one early
/// refresh, at most once per [minRefreshInterval] so random `kid`s cannot make us hammer Google.
class GoogleKeys {
  GoogleKeys({Future<Jwks> Function()? fetch, DateTime Function()? now})
      : _fetch = fetch ?? fetchGoogleJwks,
        _now = now ?? DateTime.now;

  static const defaultMaxAge = Duration(hours: 1);
  static const minRefreshInterval = Duration(minutes: 1);

  final Future<Jwks> Function() _fetch;
  final DateTime Function() _now;

  Map<String, RsaPublicKey> _keys = const {};
  DateTime? _fetchedAt;
  DateTime? _expiresAt;
  Future<void>? _inFlight;

  /// The key for [kid], or `null` if Google does not publish it. Download errors propagate.
  Future<RsaPublicKey?> key(String kid) async {
    final now = _now();
    if (_expiresAt == null || !now.isBefore(_expiresAt!)) {
      await _refresh();
    } else if (!_keys.containsKey(kid) && now.difference(_fetchedAt!) >= minRefreshInterval) {
      await _refresh();
    }
    return _keys[kid];
  }

  Future<void> _refresh() => _inFlight ??= () async {
        try {
          final jwks = await _fetch();
          final now = _now();
          _keys = jwks.keys;
          _fetchedAt = now;
          _expiresAt = now.add(jwks.maxAge ?? defaultMaxAge);
        } finally {
          _inFlight = null;
        }
      }();
}

/// Checks a Google ID token and returns who it belongs to, or throws [InvalidGoogleToken].
class GoogleIdTokenVerifier {
  GoogleIdTokenVerifier({required this.clientId, required this.keys, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Client ID from `GOOGLE_CLIENT_ID`, or [defaultGoogleClientId].
  factory GoogleIdTokenVerifier.fromEnvironment() {
    final fromEnv = Platform.environment['GOOGLE_CLIENT_ID'];
    return GoogleIdTokenVerifier(
      clientId: fromEnv == null || fromEnv.isEmpty ? defaultGoogleClientId : fromEnv,
      keys: GoogleKeys(),
    );
  }

  final String clientId;
  final GoogleKeys keys;
  final DateTime Function() _now;

  Future<GoogleIdentity> verify(String idToken) async {
    final parts = idToken.split('.');
    if (parts.length != 3) throw const InvalidGoogleToken(GoogleTokenRejection.malformed);
    final Map<String, dynamic> header;
    final Map<String, dynamic> claims;
    final List<int> signature;
    try {
      header = jsonDecode(utf8.decode(_base64UrlBytes(parts[0]))) as Map<String, dynamic>;
      claims = jsonDecode(utf8.decode(_base64UrlBytes(parts[1]))) as Map<String, dynamic>;
      signature = _base64UrlBytes(parts[2]);
    } on Object {
      throw const InvalidGoogleToken(GoogleTokenRejection.malformed);
    }

    // The algorithm is fixed here, never taken from the token ("none" and HS256 tricks).
    if (header['alg'] != 'RS256') throw const InvalidGoogleToken(GoogleTokenRejection.unsupportedAlgorithm);
    final kid = header['kid'];
    if (kid is! String) throw const InvalidGoogleToken(GoogleTokenRejection.unknownKey);
    final key = await keys.key(kid);
    if (key == null) throw const InvalidGoogleToken(GoogleTokenRejection.unknownKey);
    if (!key.verifyRs256(ascii.encode('${parts[0]}.${parts[1]}'), signature)) {
      throw const InvalidGoogleToken(GoogleTokenRejection.invalidSignature);
    }

    if (!_googleIssuers.contains(claims['iss'])) throw const InvalidGoogleToken(GoogleTokenRejection.wrongIssuer);
    final aud = claims['aud'];
    final audiences = aud is List ? aud : [aud];
    if (!audiences.contains(clientId)) throw const InvalidGoogleToken(GoogleTokenRejection.wrongAudience);
    final exp = claims['exp'];
    if (exp is! num) throw const InvalidGoogleToken(GoogleTokenRejection.malformed);
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    if (!_now().toUtc().isBefore(expiresAt.add(clockLeeway))) throw const InvalidGoogleToken(GoogleTokenRejection.expired);
    final verified = claims['email_verified'];
    if (verified != true && verified != 'true') throw const InvalidGoogleToken(GoogleTokenRejection.emailNotVerified);
    final sub = claims['sub'];
    final email = claims['email'];
    if (sub is! String || sub.isEmpty || email is! String || email.isEmpty) {
      throw const InvalidGoogleToken(GoogleTokenRejection.malformed);
    }
    return GoogleIdentity(sub: sub, email: email);
  }
}

Uint8List _base64UrlBytes(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _bigIntFrom(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _bytesOf(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}
