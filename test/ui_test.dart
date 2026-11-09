import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rivium_auth/rivium_auth_ui.dart';

/// A fake Rivium Auth server for the sign-in screens.
class Fake {
  Fake(this.methods, {this.telegramBot});

  List<String> methods;
  String? telegramBot;
  final requests = <http.Request>[];

  /// When set, sign-in calls wait for it (a slow server).
  Future<void>? gate;

  /// Answers for POST paths; anything else 404.
  final answers = <String, http.Response Function(Map<String, dynamic> body)>{};

  int _n = 0;
  Map<String, dynamic> session(String userId) => {
        'accessToken': 'access-${++_n}',
        'expiresIn': 3600,
        'refreshToken': 'refresh-$_n-xxxxxxxxxxxxxxxxxxxx',
        'userId': userId,
      };

  List<Map<String, dynamic>> bodies(String path) => requests
      .where((r) => r.url.path == path)
      .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
      .toList();

  MockClient get client => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path == '/v1/methods') {
          return res({'methods': methods, 'telegramBot': telegramBot});
        }
        if (path == '/v1/me') {
          return res({
            'id': 'u1',
            'anonymous': false,
            'emailVerified': true,
            'createdAt': '2026-11-08T10:00:00.000Z',
            'providers': ['password'],
          });
        }
        if (gate != null) await gate;
        final a = answers[path];
        if (a == null) return res({'code': 'NOT_FOUND', 'message': 'no'}, 404);
        return a(req.body.isEmpty ? {} : jsonDecode(req.body) as Map<String, dynamic>);
      });
}

http.Response res(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

http.Response err(String code, int status) =>
    res({'code': code, 'message': 'hint for developers'}, status);

Future<RiviumAuth> client(Fake f) => RiviumAuth.create('rv_live_test',
    baseUrl: 'https://auth.example.test',
    httpClient: f.client,
    storage: MemoryRiviumAuthStorage());

Future<Future<RiviumAuthUser?> Function()> pumpScreen(WidgetTester tester, RiviumAuth auth,
    {RiviumSignInOptions options = const RiviumSignInOptions(), Size size = const Size(800, 1000)}) async {
  RiviumAuthUser? signedIn;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RiviumSignInScreen(auth: auth, options: options, onSignedIn: (u) => signedIn = u),
    ),
  ));
  return () async => signedIn;
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)), text);
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Material texts for any locale, so a test app can run in another language.
class AnyMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const AnyMaterial();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) => DefaultMaterialLocalizations.load(locale);
  @override
  bool shouldReload(AnyMaterial old) => false;
}

class AnyCupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const AnyCupertino();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) => DefaultCupertinoLocalizations.load(locale);
  @override
  bool shouldReload(AnyCupertino old) => false;
}

void main() {
  testWidgets('shows only the methods that are on and that the app can run', (tester) async {
    final f = Fake(['anonymous', 'google', 'password', 'magicLink', 'telegram']);
    final auth = await client(f);
    await pumpScreen(tester, auth, options: const RiviumSignInOptions(allowGuest: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rivium-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('rivium-telegram')), findsOneWidget);
    expect(find.byKey(const ValueKey('rivium-guest')), findsOneWidget);
    // Google needs the app's function and magic link the app's URL: neither given.
    expect(find.byKey(const ValueKey('rivium-google')), findsNothing);
    expect(find.byKey(const ValueKey('rivium-magic-link')), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('no password method: no e-mail form', (tester) async {
    final f = Fake(['anonymous', 'telegram']);
    await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rivium-email')), findsNothing);
    expect(find.byKey(const ValueKey('rivium-telegram')), findsOneWidget);
    // Every guest is a new user (counted in the plan): only when the app asks for it.
    expect(find.byKey(const ValueKey('rivium-guest')), findsNothing);
  });

  testWidgets('e-mail sign-in calls the SDK and reports the user', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/sign-in'] = (b) => res(f.session('u1'));
    final signedIn = await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-sign-in');
    expect(find.text('Required'), findsNWidgets(2));
    expect(f.bodies('/v1/password/sign-in'), isEmpty);
    await enter(tester, 'rivium-email', ' ali@example.com ');
    await enter(tester, 'rivium-password', 'a-good-password');
    await tap(tester, 'rivium-sign-in');
    expect(f.bodies('/v1/password/sign-in').single, {'email': 'ali@example.com', 'password': 'a-good-password'});
    expect((await signedIn())?.id, 'u1');
  });

  testWidgets('a wrong password shows a message from the code, not the server hint', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/sign-in'] = (b) => err('INVALID_CREDENTIALS', 401);
    final signedIn = await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await enter(tester, 'rivium-email', 'ali@example.com');
    await enter(tester, 'rivium-password', 'wrong-password');
    await tap(tester, 'rivium-sign-in');
    expect(find.text('Wrong e-mail or password.'), findsOneWidget);
    expect(find.textContaining('hint for developers'), findsNothing);
    expect(await signedIn(), isNull);
  });


  testWidgets('a language the screens do not have, or an odd code, shows English', (tester) async {
    for (final code in ['de', 'constructor', '']) {
      final auth = await client(Fake(['password']));
      await pumpScreen(tester, auth, options: RiviumSignInOptions(languageCode: code));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsWidgets);
      final dir = Directionality.of(tester.element(find.byKey(const ValueKey('rivium-email'))));
      expect(dir, TextDirection.ltr);
    }
  });

  testWidgets('the e-mails follow the open screen, given back on close, never the app’s own choice', (tester) async {
    final f = Fake(['password']);
    final auth = await client(f);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RiviumSignInScreen(auth: auth, options: const RiviumSignInOptions(languageCode: 'en')))));
    await tester.pumpAndSettle();
    expect(auth.languageCode, 'en');
    await tester.pumpWidget(const SizedBox());
    expect(auth.languageCode, isNull);
    await auth.setLanguageCode('en-US');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RiviumSignInScreen(auth: auth, options: const RiviumSignInOptions(languageCode: 'en')))));
    await tester.pumpAndSettle();
    expect(auth.languageCode, 'en-US');
  });

  testWidgets('a screen replaced by another keeps the language for the new one', (tester) async {
    final f = Fake(['password']);
    final auth = await client(f);
    Widget screen() => MaterialApp(
        home: Scaffold(body: RiviumSignInScreen(key: UniqueKey(), auth: auth, options: const RiviumSignInOptions(languageCode: 'en'))));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen()); // the new one opens before the old one closes
    await tester.pumpAndSettle();
    expect(auth.languageCode, 'en');
    await tester.pumpWidget(const SizedBox());
    expect(auth.languageCode, isNull);
  });

  testWidgets('sign-up that needs a confirmed e-mail but sent none: says so; the password is not kept', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/sign-up'] = (b) => res({'userId': 'u9', 'verificationSent': false, 'session': null});
    await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-to-sign-up');
    await enter(tester, 'rivium-sign-up-email', 'new@example.com');
    await enter(tester, 'rivium-sign-up-password', 'a-good-password');
    await tap(tester, 'rivium-sign-up');
    expect(find.byKey(const ValueKey('rivium-sent')), findsNothing);
    expect(find.textContaining('could not be sent'), findsOneWidget);
    final pw = tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('rivium-password')), matching: find.byType(EditableText)));
    expect(pw.controller.text, '');
  });


  testWidgets('an app language the screens do not have shows English', (tester) async {
    final f = Fake(['password']);
    final auth = await client(f);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: const [DefaultWidgetsLocalizations.delegate, AnyMaterial(), AnyCupertino()],
      home: Scaffold(body: RiviumSignInScreen(auth: auth)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('sign-up that needs a confirmed e-mail: link to Rivium’s confirm page', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/sign-up'] = (b) => res({'userId': 'u9', 'verificationSent': true, 'session': null});
    final signedIn = await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-to-sign-up');
    await enter(tester, 'rivium-sign-up-email', 'new@example.com');
    await enter(tester, 'rivium-sign-up-password', 'a-good-password');
    await tap(tester, 'rivium-sign-up');
    expect(f.bodies('/v1/password/sign-up').single['redirectUrl'], 'https://auth.example.test/pages/verify');
    expect(find.byKey(const ValueKey('rivium-sent')), findsOneWidget);
    expect(find.textContaining('confirmation link'), findsOneWidget);
    expect(await signedIn(), isNull);
  });

  testWidgets('sign-up that signs in at once', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/sign-up'] = (b) => res({'userId': 'u1', 'verificationSent': true, 'session': f.session('u1')});
    final signedIn = await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-to-sign-up');
    await enter(tester, 'rivium-sign-up-email', 'new@example.com');
    await enter(tester, 'rivium-sign-up-password', 'a-good-password');
    await tap(tester, 'rivium-sign-up');
    expect((await signedIn())?.id, 'u1');
  });

  testWidgets('forgot password: hosted reset page unless the app gives its own', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/forgot'] = (b) => http.Response('', 202);
    await pumpScreen(tester, await client(f), options: const RiviumSignInOptions(resetRedirectUrl: 'https://app.example.com/reset'));
    await tester.pumpAndSettle();
    await enter(tester, 'rivium-email', 'ali@example.com');
    await tap(tester, 'rivium-forgot');
    await tap(tester, 'rivium-forgot-send');
    expect(f.bodies('/v1/password/forgot').single, {'email': 'ali@example.com', 'redirectUrl': 'https://app.example.com/reset'});
    expect(find.textContaining('choose a new password'), findsOneWidget);
  });

  testWidgets('forgot password without the app’s URL: the server picks Rivium’s reset page', (tester) async {
    final f = Fake(['password']);
    f.answers['/v1/password/forgot'] = (b) => http.Response('', 202);
    await pumpScreen(tester, await client(f));
    await tester.pumpAndSettle();
    await enter(tester, 'rivium-email', 'ali@example.com');
    await tap(tester, 'rivium-forgot');
    await tap(tester, 'rivium-forgot-send');
    expect(f.bodies('/v1/password/forgot').single, {'email': 'ali@example.com'});
  });

  testWidgets('magic link uses the app’s URL', (tester) async {
    final f = Fake(['magicLink']);
    f.answers['/v1/magic-link/send'] = (b) => http.Response('', 202);
    await pumpScreen(tester, await client(f), options: const RiviumSignInOptions(magicLinkRedirectUrl: 'myapp://sign-in'));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-magic-link');
    await enter(tester, 'rivium-magicLink-email', 'not-an-email');
    await tap(tester, 'rivium-magicLink-send');
    expect(find.text('Enter a valid e-mail'), findsOneWidget);
    await enter(tester, 'rivium-magicLink-email', 'ali@example.com');
    await tap(tester, 'rivium-magicLink-send');
    expect(f.bodies('/v1/magic-link/send').single, {'email': 'ali@example.com', 'redirectUrl': 'myapp://sign-in'});
    expect(find.textContaining('sign-in link'), findsOneWidget);
  });

  testWidgets('Telegram: open the bot first, then the code', (tester) async {
    final f = Fake(['telegram'], telegramBot: 'tikashop_bot');
    var sent = false;
    f.answers['/v1/telegram/code'] = (b) => res(sent
        ? {'sent': true, 'expiresIn': 300}
        : {'sent': false, 'botUrl': 'https://t.me/tikashop_bot', 'expiresIn': 0});
    f.answers['/v1/telegram/verify'] =
        (b) => b['code'] == '123456' ? res(f.session('u1')) : err('TOKEN_INVALID', 400);
    final opened = <Uri>[];
    final signedIn = await pumpScreen(tester, await client(f),
        options: RiviumSignInOptions(openUrl: (u) async => opened.add(u)));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-telegram');
    await enter(tester, 'rivium-phone', '+98 912 345-6789');
    await tap(tester, 'rivium-send-code');
    expect(f.bodies('/v1/telegram/code').single, {'phone': '+989123456789'});
    expect(find.textContaining('@tikashop_bot'), findsOneWidget);
    await tester.tap(find.text('https://t.me/tikashop_bot'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://t.me/tikashop_bot');
    sent = true;
    await tap(tester, 'rivium-send-code');
    await enter(tester, 'rivium-code', '000000');
    await tap(tester, 'rivium-verify-code');
    expect(find.text('This code is wrong or has expired.'), findsOneWidget);
    await enter(tester, 'rivium-code', '123456');
    await tap(tester, 'rivium-verify-code');
    expect((await signedIn())?.id, 'u1');
  });

  testWidgets('a bot link that is not https://t.me is never shown or opened', (tester) async {
    final f = Fake(['telegram']);
    f.answers['/v1/telegram/code'] = (b) => res({'sent': false, 'botUrl': 'javascript:alert(1)', 'expiresIn': 0});
    final opened = <Uri>[];
    await pumpScreen(tester, await client(f), options: RiviumSignInOptions(openUrl: (u) async => opened.add(u)));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-telegram');
    await enter(tester, 'rivium-phone', '+989123456789');
    await tap(tester, 'rivium-send-code');
    expect(find.textContaining('javascript'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('Google: the app gets the hashed nonce, Rivium the raw one', (tester) async {
    final f = Fake(['google']);
    f.answers['/v1/google'] = (b) => res(f.session('u1'));
    String? hashed;
    final signedIn = await pumpScreen(tester, await client(f),
        options: RiviumSignInOptions(google: (h) async {
      hashed = h;
      return 'google-id-token';
    }));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-google');
    final body = f.bodies('/v1/google').single;
    expect(body['idToken'], 'google-id-token');
    expect(RiviumAuthNonce.sha256Hex(body['nonce'] as String), hashed);
    expect((await signedIn())?.id, 'u1');
  });

  testWidgets('Google cancelled: nothing sent, no error', (tester) async {
    final f = Fake(['google']);
    await pumpScreen(tester, await client(f), options: RiviumSignInOptions(google: (h) async => null));
    await tester.pumpAndSettle();
    await tap(tester, 'rivium-google');
    expect(f.bodies('/v1/google'), isEmpty);
    expect(find.byKey(const ValueKey('rivium-sign-in-error')), findsNothing);
  });

  testWidgets('no answer from the server: a retry screen', (tester) async {
    final auth = await RiviumAuth.create('rv_live_test',
        baseUrl: 'https://auth.example.test',
        httpClient: MockClient((r) async => throw http.ClientException('offline')),
        storage: MemoryRiviumAuthStorage());
    await pumpScreen(tester, auth);
    await tester.pumpAndSettle();
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('RiviumSignIn.show', () {
    Future<Future<RiviumAuthUser?>> open(WidgetTester tester, RiviumAuth auth, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Future<RiviumAuthUser?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = RiviumSignIn.show(context, auth: auth, options: const RiviumSignInOptions(allowGuest: true)),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('wide screen: a dialog that answers the signed-in user', (tester) async {
      final f = Fake(['anonymous']);
      f.answers['/v1/anonymous'] = (b) => res(f.session('guest-1'));
      final result = await open(tester, await client(f), const Size(1200, 900));
      expect(find.byType(Dialog), findsOneWidget);
      await tap(tester, 'rivium-guest');
      expect((await result)?.id, 'guest-1');
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('no closing while a sign-in runs; it answers the user', (tester) async {
      final f = Fake(['anonymous']);
      final gate = Completer<void>();
      f.answers['/v1/anonymous'] = (b) => res(f.session('guest-1'));
      f.gate = gate.future;
      final auth = await client(f);
      final result = await open(tester, auth, const Size(1200, 900));
      await tester.tap(find.byKey(const ValueKey('rivium-guest')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rivium-close')), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget); // still open
      gate.complete();
      await tester.pumpAndSettle();
      expect((await result)?.id, 'guest-1');
    });

    testWidgets('phone: full screen, closing answers null', (tester) async {
      final f = Fake(['anonymous']);
      final result = await open(tester, await client(f), const Size(390, 844));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('rivium-guest')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rivium-close')));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(f.bodies('/v1/anonymous'), isEmpty);
    });
  });
}
