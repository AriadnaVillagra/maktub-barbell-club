import 'dart:convert';
import 'dart:typed_data';

import 'package:maktub_backend/features/auth/google_id_token.dart';
import 'package:test/test.dart';

/// Test-only RSA-2048 keys (generated with openssl for these tests; never used anywhere else).
final _keyA = _TestKey(
  'e1f7102bb94ffb44bedbd2170571c241c3cdb9d4fe916450eb12c60000139ccc85441c356fa95f6238ed2bb43bc309ad9ea8693ab61677eb8c380a979820a36e9b234d06933b9044848d99cda73c483a9e5a2052419936532e0b1d87c886185247e5bc642ae2bd8941b87c72b0092279546464bb8da8232e574bc59ebc183c47661cdc5bde396e188dcb97425f171dfdb0fc6681d936a7d852cb4dc8335f30fd26cfa403489f9f4aa0b92064ff655e826a1f07fbae280994387bc9d8461277896ecf1f6898fac24706e6e8d28319cd850377373c5488d8d97dfcf8d333e1fd9a382a39887e3e48603d034a9b541d8467d31084e15c6201e41f9eb49a70c67811',
  '40152b16db551d735f9543bd97a3ad6dad33f8d1b8e84ec4cc05e4f5371058d57fadd33a2c52a2645eb4944266f867143ffc8eeb419c99a1c9805330aeca02cf695bd78a57d2fa9513ea7c85e039ae5a417259dc3a12535fbf9d1360e0b376ce4ee98e45f20b9fa8ff646c96b1e9c5471771e9476f6311a720c6b262d4012386abaeb010d209d80d0a17eab5c370faf55d8b37e22a9a02ff5cf566b399d442107bc23ee8bf149c01996ea432849bc39ad2f908a37ffbfd4dc84661b7f9acd84df552decd6ccafe8a7f045eb885631548eb4b76ac1e2e39f5d9294c9500c354a25670ca8944ea0c24672174b32accfdc25dcff9cd11dcbffe902804e7af265449',
);
final _keyB = _TestKey(
  'b1ce2ebd8d1218b1ab1820433cfdf5d0d0c9f8947ea24904391818e98e5d521d9308844917dcbc5c6ae73cc6b47f44baa2c0f1359422159f82a270f7feef2327437580dc1618432ace79cc409805745a44bc6fb817170048154e6f2facc9880cb432420d9dcaeaa7711c79036ba8824381ba839a4a7f90a7214555b6fe5c410e4e6cb495623e3428082902eb139814240976e5a5bbe53ec22aed8a5d65d061529464e467dbcc61709847f2c1c8e7d334a4ee483d41d1897f9baa8cdbf960057daf28ea23609a030211b86187e286c96657ca7eca51c432e4fcb27b3d78906ade297197310b4e8101f58c2f9f2efa650107b60f6292bae7983f64baf7b494ee13',
  '355e54ab3267a71fd4e205f5089e95a4dab674b56599225f711fa98298e7abd912a3f0c8dbafb69deabc838284f4da5546bab0ebcb0dbbfdc7c1283557c0c1856c7b1d7571f05060cddec30ef45256cd2d6a7e01fc743bf266eac6f6c15f3045d7e469ed1a5aa8ba1f7a535c52791eb8527d003954791b9afea2880ac8283aa22623f5032f0d3dd6b260114d9b683971486df6250b4d8db9602c944b671f9a50f6330b5f7c5de3be63980fe569e9acc974bd465cb518a556178d1fbbfccfb6ec4bc2f9288e52b3a61c2ddd0cd5ca967d612b91155d5718baad5c2380edf0dd235d8492c5a8015ed6d08aa9fb087a491e48f958cac75300d6a2dd54eed683c499',
);

class _TestKey {
  _TestKey(String n, String d)
      : n = BigInt.parse(n, radix: 16),
        d = BigInt.parse(d, radix: 16);

  final BigInt n;
  final BigInt d;

  int get length => (n.bitLength + 7) ~/ 8;

  Map<String, dynamic> jwk(String kid) => {'kty': 'RSA', 'alg': 'RS256', 'use': 'sig', 'kid': kid, 'n': _b64(_bytes(n, length)), 'e': 'AQAB'};

  List<int> sign(List<int> message) {
    final em = emsaPkcs1Sha256(message, length)!;
    return _bytes(_int(em).modPow(d, n), length);
  }
}

const _clientId = 'test-client.apps.googleusercontent.com';
final _now = DateTime.utc(2026, 11, 7, 12);

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

BigInt _int(List<int> bytes) => bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

Uint8List _bytes(BigInt v, int length) {
  final out = Uint8List(length);
  for (var i = length - 1; i >= 0; i--, v >>= 8) {
    out[i] = (v & BigInt.from(0xff)).toInt();
  }
  return out;
}

int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Map<String, Object?> _claims({Map<String, Object?> override = const {}}) => {
      'iss': 'https://accounts.google.com',
      'azp': _clientId,
      'aud': _clientId,
      'sub': '110169484474386276334',
      'email': 'atleta@example.com',
      'email_verified': true,
      'iat': _seconds(_now.subtract(const Duration(minutes: 1))),
      'exp': _seconds(_now.add(const Duration(minutes: 59))),
      ...override,
    };

String _token({_TestKey? key, String kid = 'kid-a', String alg = 'RS256', Map<String, Object?>? claims}) {
  final header = _b64(utf8.encode(jsonEncode({'alg': alg, 'kid': kid, 'typ': 'JWT'})));
  final payload = _b64(utf8.encode(jsonEncode(claims ?? _claims())));
  final signature = (key ?? _keyA).sign(ascii.encode('$header.$payload'));
  return '$header.$payload.${_b64(signature)}';
}

/// Stands in for Google's JWKS endpoint: serves whatever keys the test sets and counts downloads.
class _FakeJwksEndpoint {
  _FakeJwksEndpoint(this.keys);

  Map<String, _TestKey> keys;
  Duration? maxAge = const Duration(hours: 6);
  var downloads = 0;

  Future<Jwks> fetch() async {
    downloads++;
    final body = jsonEncode({
      'keys': [for (final e in keys.entries) e.value.jwk(e.key)],
    });
    return Jwks.parse(body, maxAge: maxAge);
  }
}

void main() {
  late DateTime clock;
  late _FakeJwksEndpoint google;
  late GoogleIdTokenVerifier verifier;

  setUp(() {
    clock = _now;
    google = _FakeJwksEndpoint({'kid-a': _keyA});
    verifier = GoogleIdTokenVerifier(clientId: _clientId, keys: GoogleKeys(fetch: google.fetch, now: () => clock), now: () => clock);
  });

  Future<void> expectRejected(String token, GoogleTokenRejection reason) => expectLater(
        verifier.verify(token),
        throwsA(isA<InvalidGoogleToken>().having((e) => e.reason, 'reason', reason)),
      );

  test('the RSA verification interoperates with openssl signatures', () {
    // `printf 'header.payload' | openssl dgst -sha256 -sign a.pem`, base64url.
    const openssl =
        'frOjzCeTg2rtCRcPeXNVBn5aDifisg1RQcypnbg8geeiQ77924RLeU4ABvs0PxIWs-Ww7Lk91jJ9-TCVcWdDOzXgdmH6xUbX8E2xWUb3dmVjaaeQjAQYH57bH39jkRkk7QFkX-I6DNs5mCA_VCKDUVsjhNFAj5uiLtJ7NRJBPgzmp6keq1e6A8p-66bj5BAlneqouWosGUjOZl3Osz5ggTj_jfTm37ypwQwPJcG4ZeMrrMOkBTSe6MvkD8PKOneEUcAwKqnnUUmtSPHbZNuYFxzaxYyT1OGBD-kuuukUp8_t0UAdVFEMBzA-_sEDn8M4rAKkjeouaNWymyS9kKJBrw';
    final key = RsaPublicKey.fromJwk(_keyA.jwk('kid-a'));
    final signature = base64Url.decode(base64Url.normalize(openssl));
    expect(key.verifyRs256(ascii.encode('header.payload'), signature), isTrue);
    expect(key.verifyRs256(ascii.encode('header.payloaD'), signature), isFalse);
  });

  test('accepts a valid token and returns sub and email', () async {
    final identity = await verifier.verify(_token());
    expect(identity.sub, '110169484474386276334');
    expect(identity.email, 'atleta@example.com');
  });

  test('accepts the issuer without scheme too', () async {
    final identity = await verifier.verify(_token(claims: _claims(override: {'iss': 'accounts.google.com'})));
    expect(identity.sub, '110169484474386276334');
  });

  test('rejects a token signed by a key Google does not hold', () async {
    await expectRejected(_token(key: _keyB, kid: 'kid-a'), GoogleTokenRejection.invalidSignature);
  });

  test('rejects a token whose payload was altered after signing', () async {
    final parts = _token().split('.');
    final forged = _b64(utf8.encode(jsonEncode(_claims(override: {'email': 'otro@example.com'}))));
    await expectRejected('${parts[0]}.$forged.${parts[2]}', GoogleTokenRejection.invalidSignature);
  });

  test('rejects a token for another client', () async {
    await expectRejected(_token(claims: _claims(override: {'aud': 'other.apps.googleusercontent.com'})), GoogleTokenRejection.wrongAudience);
  });

  test('rejects a token from another issuer', () async {
    await expectRejected(_token(claims: _claims(override: {'iss': 'https://evil.example.com'})), GoogleTokenRejection.wrongIssuer);
  });

  test('rejects an expired token, beyond the clock leeway', () async {
    final expired = _token(claims: _claims(override: {'exp': _seconds(_now.subtract(const Duration(minutes: 1)))}));
    await expectRejected(expired, GoogleTokenRejection.expired);
  });

  test('tolerates a few seconds of clock difference', () async {
    final justExpired = _token(claims: _claims(override: {'exp': _seconds(_now.subtract(const Duration(seconds: 5)))}));
    expect((await verifier.verify(justExpired)).email, 'atleta@example.com');
  });

  test('rejects an email Google has not verified', () async {
    await expectRejected(_token(claims: _claims(override: {'email_verified': false})), GoogleTokenRejection.emailNotVerified);
    final missing = _claims()..remove('email_verified');
    await expectRejected(_token(claims: missing), GoogleTokenRejection.emailNotVerified);
  });

  test('rejects algorithms other than RS256, whatever the header says', () async {
    await expectRejected(_token(alg: 'HS256'), GoogleTokenRejection.unsupportedAlgorithm);
    await expectRejected(_token(alg: 'none'), GoogleTokenRejection.unsupportedAlgorithm);
  });

  test('rejects garbage', () async {
    await expectRejected('not-a-jwt', GoogleTokenRejection.malformed);
    await expectRejected('a.b.c', GoogleTokenRejection.malformed);
  });

  group('keys', () {
    test('are downloaded once and reused while the cache is fresh', () async {
      await verifier.verify(_token());
      clock = clock.add(const Duration(hours: 5));
      await verifier.verify(_token(claims: _claims(override: {'exp': _seconds(clock.add(const Duration(minutes: 30)))})));
      expect(google.downloads, 1);
    });

    test('are downloaded again when max-age runs out', () async {
      await verifier.verify(_token());
      clock = clock.add(const Duration(hours: 7));
      await verifier.verify(_token(claims: _claims(override: {'exp': _seconds(clock.add(const Duration(minutes: 30)))})));
      expect(google.downloads, 2);
    });

    test('follow a rotation: an unknown kid refreshes the cache early', () async {
      await verifier.verify(_token());
      google.keys = {'kid-a': _keyA, 'kid-b': _keyB};
      clock = clock.add(const Duration(minutes: 5));
      final rotated = _token(key: _keyB, kid: 'kid-b', claims: _claims(override: {'exp': _seconds(clock.add(const Duration(minutes: 30)))}));
      expect((await verifier.verify(rotated)).email, 'atleta@example.com');
      expect(google.downloads, 2);
    });

    test('reject a kid Google does not publish, without hammering the endpoint', () async {
      await verifier.verify(_token());
      clock = clock.add(const Duration(minutes: 5));
      await expectRejected(_token(kid: 'made-up'), GoogleTokenRejection.unknownKey);
      await expectRejected(_token(kid: 'made-up-2'), GoogleTokenRejection.unknownKey);
      expect(google.downloads, 2, reason: 'one early refresh per minimum interval');
    });

    test('reject a token signed with a key Google has retired', () async {
      await verifier.verify(_token());
      google.keys = {'kid-b': _keyB};
      clock = clock.add(const Duration(hours: 7));
      await expectRejected(
        _token(claims: _claims(override: {'exp': _seconds(clock.add(const Duration(minutes: 30)))})),
        GoogleTokenRejection.unknownKey,
      );
    });
  });

  test('maxAgeFrom reads Cache-Control', () {
    expect(maxAgeFrom('public, max-age=19800, must-revalidate, no-transform'), const Duration(seconds: 19800));
    expect(maxAgeFrom(null), isNull);
  });
}
