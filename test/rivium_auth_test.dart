import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rivium_auth/rivium_auth.dart';

/// A fake Rivium Auth server: records requests and answers from [handler].
class FakeServer {
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request req) handler;
  int _n = 0;

  /// Session JSON with a fresh access + refresh token.
  Map<String, dynamic> session({String userId = 'u1', int expiresIn = 3600}) {
    _n++;
    return {
      'accessToken': 'access-$_n',
      'expiresIn': expiresIn,
      'expiresAt': '2026-01-01T00:00:00.000Z',
      'refreshToken': 'refresh-$_n-xxxxxxxxxxxxxxxxxxxx',
      'userId': userId,
    };
  }

  MockClient get client => MockClient((req) {
        requests.add(req);
        return handler(req);
      });

  List<http.Request> to(String path) =>
      requests.where((r) => r.url.path == path).toList();
}

http.Response json(Object? body, [int status = 200, Map<String, String>? headers]) =>
    http.Response(body == null ? '' : jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

Map<String, dynamic> me(String id, {bool anonymous = false, List<String> providers = const []}) => {
      'id': id,
      'anonymous': anonymous,
      'emailVerified': false,
      'createdAt': '2026-10-16T10:00:00.000Z',
      'providers': providers,
    };

void main() {
  late FakeServer server;
  late MemoryRiviumAuthStorage storage;
  late DateTime now;

  Future<RiviumAuth> auth() => RiviumAuth.create('rv_live_test',
      httpClient: server.client, storage: storage, clock: () => now);

  String? storedRefresh() =>
      storage.values.entries.where((e) => e.key.endsWith('.refresh')).map((e) => e.value).firstOrNull;

  setUp(() {
    server = FakeServer();
    storage = MemoryRiviumAuthStorage();
    now = DateTime.utc(2026, 10, 16, 12);
  });

  group('sign-in', () {
    test('anonymous sign-in stores the refresh token, keeps the access token in memory', () async {
      final s = server.session();
      server.handler = (req) async => json(s);
      final a = await auth();
      final events = <RiviumAuthUser?>[];
      final sub = a.authStateChanges.listen(events.add);

      final user = await a.signInAnonymously();

      expect(user.id, 'u1');
      expect(user.anonymous, isTrue);
      expect(a.currentUser, user);
      expect(storedRefresh(), s['refreshToken']);
      expect(storage.values.values.any((v) => v.contains('access-')), isFalse);
      expect(await a.getToken(), s['accessToken']);
      expect(server.requests, hasLength(1));
      expect(server.requests.single.headers['x-api-key'], 'rv_live_test');
      await Future<void>.delayed(Duration.zero);
      expect(events, [null, user]);
      await sub.cancel();
    });

    test('a second signInAnonymously returns the same anonymous user', () async {
      server.handler = (req) async => json(server.session());
      final a = await auth();
      final first = await a.signInAnonymously();
      final second = await a.signInAnonymously();
      expect(second, first);
      expect(server.to('/v1/anonymous'), hasLength(1));
    });

    test('e-mail sign-in loads the profile with the new access token', () async {
      final s = server.session(userId: 'u7');
      server.handler = (req) async {
        if (req.url.path == '/v1/password/sign-in') {
          expect(jsonDecode(req.body), {'email': 'a@b.co', 'password': 'pw-123456'});
          return json(s);
        }
        if (req.url.path == '/v1/me') {
          expect(req.headers['authorization'], 'Bearer ${s['accessToken']}');
          return json(me('u7', providers: ['password']));
        }
        return json({'code': 'INVALID_INPUT', 'message': 'Not found'}, 404);
      };
      final a = await auth();
      final user = await a.signInWithEmail(email: 'a@b.co', password: 'pw-123456');
      expect(user.id, 'u7');
      expect(user.providers, ['password']);
      expect(a.isSignedIn, isTrue);
    });

    test('Apple sign-in sends the raw nonce, not the hashed one', () async {
      server.handler = (req) async =>
          req.url.path == '/v1/apple' ? json(server.session()) : json(me('u1', providers: ['apple']));
      final a = await auth();
      final raw = RiviumAuthNonce.generate();
      await a.signInWithApple(idToken: 'id.token.x', rawNonce: raw, authorizationCode: 'c1');
      final body = jsonDecode(server.to('/v1/apple').single.body) as Map;
      expect(body['nonce'], raw);
      expect(body['idToken'], 'id.token.x');
      expect(body['authorizationCode'], 'c1');
    });

    test('Google sign-in sends the raw nonce', () async {
      server.handler = (req) async =>
          req.url.path == '/v1/google' ? json(server.session()) : json(me('u1', providers: ['google']));
      final a = await auth();
      final raw = RiviumAuthNonce.generate();
      await a.signInWithGoogle(idToken: 'g.id.token', rawNonce: raw);
      final body = jsonDecode(server.to('/v1/google').single.body) as Map;
      expect(body, {'idToken': 'g.id.token', 'nonce': raw});
    });

    test('sign-up without a session (e-mail must be confirmed first) does not sign in', () async {
      server.handler = (req) async => json({'userId': 'u9', 'verificationSent': true, 'session': null});
      final a = await auth();
      final r = await a.signUpWithEmail(email: 'a@b.co', password: 'pw-123456', redirectUrl: 'https://app.example/verify');
      expect(r.signedIn, isFalse);
      expect(r.verificationSent, isTrue);
      expect(a.isSignedIn, isFalse);
    });
  });

  group('refresh', () {
    late RiviumAuth a;
    late Map<String, dynamic> first;

    setUp(() async {
      first = server.session();
      server.handler = (req) async => json(first);
      a = await auth();
      await a.signInAnonymously();
      server.requests.clear();
    });

    test('no request while the access token is fresh', () async {
      now = now.add(const Duration(minutes: 30));
      expect(await a.getToken(), first['accessToken']);
      expect(server.requests, isEmpty);
    });

    test('renews about 2 minutes before expiry', () async {
      final next = server.session();
      server.handler = (req) async => json(next);
      now = now.add(const Duration(minutes: 58, seconds: 30));
      expect(await a.getToken(), next['accessToken']);
      expect(server.to('/v1/token/refresh'), hasLength(1));
    });

    test('concurrent callers share one refresh request', () async {
      final next = server.session();
      final gate = Completer<void>();
      server.handler = (req) async {
        await gate.future;
        return json(next);
      };
      now = now.add(const Duration(hours: 2));

      final calls = [a.getToken(), a.getToken(), a.tokenProvider()];
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final tokens = await Future.wait(calls);

      expect(tokens, everyElement(next['accessToken']));
      expect(server.to('/v1/token/refresh'), hasLength(1));
    });

    test('rotation stores the new refresh token and uses it next time', () async {
      final second = server.session();
      final third = server.session();
      final answers = [second, third];
      server.handler = (req) async => json(answers.removeAt(0));

      now = now.add(const Duration(hours: 2));
      await a.getToken();
      expect(storedRefresh(), second['refreshToken']);

      now = now.add(const Duration(hours: 2));
      expect(await a.getToken(), third['accessToken']);
      final sent = server.to('/v1/token/refresh').map((r) => jsonDecode(r.body)['refreshToken']).toList();
      expect(sent, [first['refreshToken'], second['refreshToken']]);
      expect(storedRefresh(), third['refreshToken']);
    });

    for (final code in ['SESSION_REVOKED', 'SESSION_EXPIRED', 'TOKEN_INVALID']) {
      test('$code signs the user out', () async {
        server.handler = (req) async => json({'code': code, 'message': 'Session ended, sign in again'}, 401);
        final events = <RiviumAuthUser?>[];
        final sub = a.authStateChanges.listen(events.add);
        now = now.add(const Duration(hours: 2));

        expect(await a.getToken(), isNull);
        expect(a.currentUser, isNull);
        expect(a.isSignedIn, isFalse);
        expect(storage.values, isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(events.last, isNull);
        await sub.cancel();
      });
    }

    test('a network error keeps the session', () async {
      server.handler = (req) async => throw http.ClientException('offline');
      now = now.add(const Duration(hours: 2));

      await expectLater(a.getToken(),
          throwsA(isA<RiviumAuthException>().having((e) => e.code, 'code', RiviumAuthErrorCode.networkError)));
      expect(a.isSignedIn, isTrue);
      expect(storedRefresh(), first['refreshToken']);

      final next = server.session();
      server.handler = (req) async => json(next);
      expect(await a.getToken(), next['accessToken']);
    });

    test('a network error inside the margin returns the still-valid token', () async {
      server.handler = (req) async => throw http.ClientException('offline');
      now = now.add(const Duration(minutes: 59));
      expect(await a.getToken(), first['accessToken']);
    });

    test('a refresh that finishes after sign-out does not sign back in', () async {
      final gate = Completer<void>();
      server.handler = (req) async {
        if (req.url.path == '/v1/token/refresh') {
          await gate.future;
          return json(server.session());
        }
        return json(null, 204);
      };
      now = now.add(const Duration(hours: 2));
      final pending = a.getToken();
      await Future<void>.delayed(Duration.zero);
      await a.signOut();
      gate.complete();
      expect(await pending, isNull);
      expect(a.isSignedIn, isFalse);
      expect(storage.values, isEmpty);
    });
  });

  group('account', () {
    test('deleteAccount calls DELETE /v1/me and clears the session', () async {
      final s = server.session();
      server.handler = (req) async => req.url.path == '/v1/anonymous' ? json(s) : json(null, 204);
      final a = await auth();
      await a.signInAnonymously();

      await a.deleteAccount();

      final del = server.requests.last;
      expect(del.method, 'DELETE');
      expect(del.url.path, '/v1/me');
      expect(del.headers['authorization'], 'Bearer ${s['accessToken']}');
      expect(a.currentUser, isNull);
      expect(storage.values, isEmpty);
      expect(await a.getToken(), isNull);
    });

    test('a failed deleteAccount keeps the session', () async {
      server.handler = (req) async => req.url.path == '/v1/anonymous'
          ? json(server.session())
          : json({'code': 'RATE_LIMITED', 'message': 'Too many attempts', 'retryAfterSec': 42}, 429, {'retry-after': '42'});
      final a = await auth();
      await a.signInAnonymously();
      await expectLater(
          a.deleteAccount(),
          throwsA(isA<RiviumAuthException>()
              .having((e) => e.code, 'code', 'RATE_LIMITED')
              .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 42))));
      expect(a.isSignedIn, isTrue);
    });

    test('signOut clears locally even when the server is unreachable', () async {
      final s = server.session();
      server.handler = (req) async => req.url.path == '/v1/anonymous' ? json(s) : throw http.ClientException('offline');
      final a = await auth();
      await a.signInAnonymously();
      await a.signOut();
      expect(a.isSignedIn, isFalse);
      expect(jsonDecode(server.to('/v1/sign-out').single.body), {'refreshToken': s['refreshToken']});
    });

    test('linking keeps the id, replaces the session and ends the old one', () async {
      final anon = server.session(userId: 'u1');
      final linked = server.session(userId: 'u1');
      server.handler = (req) async {
        switch (req.url.path) {
          case '/v1/anonymous':
            return json(anon);
          case '/v1/link/google':
            expect(req.headers['authorization'], 'Bearer ${anon['accessToken']}');
            return json(linked);
          case '/v1/me':
            return json(me('u1', providers: ['google']));
          default:
            return json(null, 204);
        }
      };
      final a = await auth();
      await a.signInAnonymously();
      final raw = RiviumAuthNonce.generate();
      final user = await a.linkGoogle(idToken: 'g.id.token', rawNonce: raw);
      await Future<void>.delayed(Duration.zero);

      expect(user.id, 'u1');
      expect(user.anonymous, isFalse);
      expect(storedRefresh(), linked['refreshToken']);
      expect(jsonDecode(server.to('/v1/link/google').single.body)['nonce'], raw);
      expect(jsonDecode(server.to('/v1/sign-out').single.body), {'refreshToken': anon['refreshToken']});
    });

    test('PROVIDER_ALREADY_LINKED is a typed error and keeps the anonymous user', () async {
      server.handler = (req) async => req.url.path == '/v1/anonymous'
          ? json(server.session())
          : json({'code': 'PROVIDER_ALREADY_LINKED', 'message': 'This account is already used by another user'}, 409);
      final a = await auth();
      final anon = await a.signInAnonymously();
      await expectLater(a.linkApple(idToken: 'x', rawNonce: RiviumAuthNonce.generate()),
          throwsA(isA<RiviumProviderAlreadyLinkedException>()));
      expect(a.currentUser, anon);
    });

    test('the session survives an app restart; the first token call refreshes', () async {
      final s = server.session();
      server.handler = (req) async => json(s);
      await (await auth()).signInAnonymously();

      final next = server.session();
      server.handler = (req) async => json(next);
      final restarted = await auth();
      expect(restarted.currentUser?.id, 'u1');
      expect(await restarted.getToken(), next['accessToken']);
      expect(jsonDecode(server.to('/v1/token/refresh').single.body), {'refreshToken': s['refreshToken']});
    });

    test('signed-in routes without a user throw UNAUTHENTICATED', () async {
      server.handler = (req) async => json(null, 204);
      final a = await auth();
      await expectLater(a.getMe(),
          throwsA(isA<RiviumAuthException>().having((e) => e.code, 'code', RiviumAuthErrorCode.unauthenticated)));
      expect(server.requests, isEmpty);
    });
  });

  group('helpers', () {
    test('sha256Hex matches the standard test vector', () {
      expect(RiviumAuthNonce.sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('generate makes distinct nonces of the requested length', () {
      final a = RiviumAuthNonce.generate();
      expect(a, hasLength(32));
      expect(RiviumAuthNonce.generate(), isNot(a));
      expect(() => RiviumAuthNonce.generate(8), throwsArgumentError);
    });

    test('token providers match the types the other Rivium SDKs take', () async {
      server.handler = (req) async => json(null, 204);
      final a = await auth();
      // Sync, Push and A/B Testing: FutureOr<String?> Function(). Chat: Future<String> Function().
      final FutureOr<String?> Function() sync = a.tokenProvider;
      final Future<String> Function() chat = a.chatTokenProvider;
      expect(await sync(), isNull);
      await expectLater(chat(), throwsA(isA<RiviumAuthException>()));
    });

    test('getMethods reads the methods the project offers', () async {
      server.handler = (req) async => json({'methods': ['anonymous', 'telegram'], 'telegramBot': 'my_bot'});
      final m = await (await auth()).getMethods();
      expect(m.anonymous, isTrue);
      expect(m.apple, isFalse);
      expect(m.telegramBot, 'my_bot');
    });
  });
}
