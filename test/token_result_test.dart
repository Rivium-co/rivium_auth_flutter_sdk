import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rivium_auth/rivium_auth.dart';

/// A token shaped like the ones Rivium signs (the SDK never checks the signature; Rivium's servers do).
String jwt(Map<String, dynamic> payload) {
  String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  return '${b64('{"alg":"ES256","typ":"JWT"}')}.${b64(jsonEncode(payload))}.c2ln';
}

const now = 1793000000;
final standard = <String, dynamic>{
  'iss': 'rivium',
  'aud': 'rivium_user',
  'sub': 'ru_user1',
  'pid': 'p1',
  'iat': now,
  'exp': now + 3600,
  'auth_time': now - 86400,
  'amr': ['google'],
  'meta': {'pid': 'p1', 'srv': true, 'iat': now},
};
DateTime at(int s) =>
    DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

void main() {
  test(
      "decodes every field, flat, custom claims included; meta is Rivium's own and left out",
      () {
    final token = jwt({
      ...standard,
      'plan': 'pro',
      'team': {'id': 't1', 'role': 'editor'},
      'نقش': 'مدیر 👋'
    });
    final r = RiviumTokenResult.fromToken(token)!;
    expect(r.token, token);
    expect(r.claims['plan'], 'pro');
    expect(r.claims['team'], {'id': 't1', 'role': 'editor'});
    expect(r.claims['نقش'], 'مدیر 👋');
    expect(r.claims['sub'], 'ru_user1');
    expect(r.claims.containsKey('meta'), isFalse);
    expect(r.expirationTime, at(now + 3600));
    expect(r.issuedAtTime, at(now));
    expect(r.authTime, at(now - 86400));
    expect(r.signInProvider, 'google');
  });

  test('a broken token gives null; no auth_time falls back to the issue time',
      () {
    expect(RiviumTokenResult.fromToken('one-part'), isNull);
    expect(RiviumTokenResult.fromToken('a.!!!.c'), isNull);
    expect(RiviumTokenResult.fromToken(jwt({'sub': 'x'})), isNull);
    final old = Map<String, dynamic>.of(standard)..remove('auth_time');
    expect(RiviumTokenResult.fromToken(jwt(old))!.authTime, at(now));
  });

  test(
      'from the client: null when signed out; forceRefresh gets new claims at once',
      () async {
    var plan = 'free';
    var clock = DateTime.utc(2026, 10, 16, 12);
    final client = MockClient((req) async {
      final iat = clock.millisecondsSinceEpoch ~/ 1000;
      final body = {
        'accessToken':
            jwt({...standard, 'iat': iat, 'exp': iat + 3600, 'plan': plan}),
        'expiresIn': 3600,
        'expiresAt': clock.add(const Duration(hours: 1)).toIso8601String(),
        'refreshToken': 'refresh-1-xxxxxxxxxxxxxxxxxxxx',
        'userId': 'ru_user1',
      };
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'});
    });
    final auth = await RiviumAuth.create('rv_live_test',
        httpClient: client,
        storage: MemoryRiviumAuthStorage(),
        clock: () => clock);
    expect(await auth.getTokenResult(), isNull);
    await auth.signInAnonymously();
    expect((await auth.getTokenResult())!.claims['plan'], 'free');
    plan = 'pro'; // the developer's server changed the claims
    expect((await auth.getTokenResult())!.claims['plan'],
        'free'); // the same token until it is renewed
    expect(
        (await auth.getTokenResult(forceRefresh: true))!.claims['plan'], 'pro');
  });

  test('custom claims nested under `claims` (Rivium server) come out by name; token fields win', () {
    final r = RiviumTokenResult.fromToken(jwt({
      ...(Map.of(standard)..remove('auth_time')),
      'claims': {'levels': ['A1'], 'sub': 'someone-else'},
    }))!;
    expect(r.claims['levels'], ['A1']);
    expect(r.claims['sub'], 'ru_user1');
    expect(r.claims.containsKey('claims'), isFalse);
    expect(r.authTime, r.issuedAtTime); // no auth_time: the issue time
  });
}
