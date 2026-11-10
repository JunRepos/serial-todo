import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'brand.dart';
import 'onboarding.dart';
import 'theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final email = _email.text.trim();
    final pw = _pw.text;
    if (email.isEmpty || pw.length < 6) {
      setState(() => _error = '이메일과 6자 이상 비밀번호를 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_signup) {
        final r = await auth.signUp(email: email, password: pw);
        if (r.session == null) await auth.signInWithPassword(email: email, password: pw);
      } else {
        await auth.signInWithPassword(email: email, password: pw);
      }
    } on AuthException catch (e) {
      setState(() => _error = _msg(e));
    } catch (e) {
      setState(() => _error = '연결할 수 없습니다. 네트워크를 확인하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return '이메일 또는 비밀번호가 맞지 않습니다.';
    if (m.contains('already registered')) return '이미 가입된 이메일입니다. 로그인하세요.';
    if (m.contains('password')) return '비밀번호 조건을 확인하세요. (${e.message})';
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 72)),
                    const SizedBox(height: 16),
                    const Text(
                      '할일이많아',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Tone.muted(context)),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '이메일'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw,
                      obscureText: true,
                      autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _go(),
                      decoration: const InputDecoration(labelText: '비밀번호'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy ? null : _go,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signup ? '가입하고 시작' : '로그인'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: _busy ? null : () => setState(() => _signup = !_signup),
                      child: Text(_signup ? '이미 계정이 있어요 · 로그인' : '처음이에요 · 가입'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
