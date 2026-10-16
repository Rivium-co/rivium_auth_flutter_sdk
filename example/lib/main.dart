import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rivium_auth/rivium_auth.dart';

// Rivium Auth — Flutter example (SDK 0.1.0)
//
// Paste your public project key (Rivium Console → your project → API keys) into the field, or replace the
// placeholder below. Never put a server secret in an app.
// In a real app call RiviumAuth.initialize(...) once, in main(), before runApp.
const _apiKeyPlaceholder = 'rv_live_YOUR_PUBLIC_KEY';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rivium Auth',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const AuthPage(),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _apiKey = TextEditingController(text: _apiKeyPlaceholder);
  final _email = TextEditingController();
  final _password = TextEditingController();

  RiviumAuth? _auth;
  StreamSubscription<RiviumAuthUser?>? _sub;
  RiviumAuthUser? _user;
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _apiKey.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _configure() async {
    final key = _apiKey.text.trim();
    if (key.isEmpty || key == _apiKeyPlaceholder) {
      setState(() => _status = 'Paste your public API key, then tap Configure.');
      return;
    }
    await _sub?.cancel();
    // Restores the session saved on this device; makes no network call.
    final auth = await RiviumAuth.initialize(key);
    // Emits on sign-in, sign-out and when a session ends.
    _sub = auth.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
    setState(() {
      _auth = auth;
      _user = auth.currentUser;
      _status = 'Configured.';
    });
  }

  /// Runs one SDK call and shows its result or its error code.
  Future<void> _run(Future<String> Function(RiviumAuth auth) action) async {
    final auth = _auth;
    if (auth == null) {
      setState(() => _status = 'Configure the API key first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Working…';
    });
    String status;
    try {
      status = await action(auth);
    } on RiviumAuthException catch (e) {
      status = '${e.code}: ${e.message}';
    } catch (e) {
      status = '$e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
      _user = auth.currentUser;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Rivium Auth')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _apiKey,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Public API key (rv_live_...)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _configure, child: const Text('Configure')),
            const SizedBox(height: 16),
            Text('Current user', style: Theme.of(context).textTheme.titleMedium),
            SelectableText(
              user == null ? 'signed out' : '${user.id}${user.anonymous ? ' (anonymous)' : ''}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ],
            const Divider(height: 32),
            FilledButton(
              onPressed: () => _run((auth) async {
                await auth.signInAnonymously();
                return 'Signed in anonymously.';
              }),
              child: const Text('Sign in anonymously'),
            ),
            const Divider(height: 32),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _run((auth) async {
                      final result = await auth.signUpWithEmail(
                        email: _email.text.trim(),
                        password: _password.text,
                      );
                      return result.user != null
                          ? 'Signed up.'
                          : 'Check your inbox: confirm the e-mail, then sign in.';
                    }),
                    child: const Text('Sign up'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _run((auth) async {
                      await auth.signInWithEmail(email: _email.text.trim(), password: _password.text);
                      return 'Signed in with e-mail.';
                    }),
                    child: const Text('Sign in'),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _run((auth) async {
                      await auth.signOut();
                      return 'Signed out.';
                    }),
                    child: const Text('Sign out'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _run((auth) async {
                      await auth.deleteAccount();
                      return 'Account deleted.';
                    }),
                    child: const Text('Delete account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
