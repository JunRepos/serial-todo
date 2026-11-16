import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'brand.dart';
import 'onboarding.dart';
import 'theme.dart';

/// 비밀번호 재설정 메일의 링크가 열어 줄 주소(웹 앱). Supabase의 Redirect URLs에 등록돼 있어야 한다.
const passwordResetUrl = 'https://junrepos.github.io/serial-todo/';

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
  String? _info;
  bool _showPw = false;

  /// 가입한 이메일로 재설정 링크를 보낸다. 링크는 웹에서 열리고 거기서 새 비밀번호를 정한다.
  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _info = null;
        _error = '가입한 이메일을 먼저 입력하세요.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: passwordResetUrl);
      setState(() => _info = '$email 로 재설정 메일을 보냈어요. 메일의 링크를 열어 새 비밀번호를 정하세요. 안 보이면 스팸함도 확인하세요.');
    } on AuthException catch (e) {
      setState(() => _error = _msg(e));
    } catch (e) {
      setState(() => _error = '연결할 수 없습니다. 네트워크를 확인하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      _info = null;
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
    if (m.contains('rate limit') || m.contains('security purposes')) return '요청이 너무 잦아요. 잠시 뒤에 다시 해 주세요.';
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
                      obscureText: !_showPw,
                      autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _go(),
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        suffixIcon: IconButton(
                          tooltip: _showPw ? '비밀번호 가리기' : '비밀번호 보기',
                          icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _showPw = !_showPw),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(_info!, style: TextStyle(color: scheme.primary)),
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
                    if (!_signup)
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        onPressed: _busy ? null : _forgot,
                        child: const Text('비밀번호를 잊었어요'),
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

/// 새 비밀번호 정하기. 재설정 메일의 링크로 들어왔을 때와 메뉴의 "비밀번호 변경"에서 쓴다.
class NewPasswordPage extends StatefulWidget {
  const NewPasswordPage({super.key, required this.onDone, this.onCancel, this.fromRecovery = false});

  /// 바꾼 뒤 호출
  final VoidCallback onDone;

  /// null이면 취소 버튼을 보이지 않는다
  final VoidCallback? onCancel;
  final bool fromRecovery;

  @override
  State<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends State<NewPasswordPage> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw = _pw.text;
    if (pw.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }
    if (pw != _pw2.text) {
      setState(() => _error = '두 비밀번호가 서로 다릅니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: pw));
      messenger?.showSnackBar(const SnackBar(content: Text('비밀번호를 바꿨어요. 다른 기기에서는 새 비밀번호로 로그인하세요.')));
      widget.onDone();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(
        () => _error = m.contains('different from the old')
            ? '지금 쓰는 비밀번호와 다른 것으로 정하세요.'
            : m.contains('session')
            ? '링크가 만료됐어요. 로그인 화면에서 재설정 메일을 다시 받으세요.'
            : '바꾸지 못했습니다. (${e.message})',
      );
    } catch (e) {
      setState(() => _error = '연결할 수 없습니다. 네트워크를 확인하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.onCancel == null
          ? null
          : AppBar(
              leading: IconButton(tooltip: '닫기', icon: const Icon(Icons.close), onPressed: widget.onCancel),
              title: const Text('비밀번호 변경'),
            ),
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
                    Text(
                      widget.fromRecovery ? '새 비밀번호를 정하세요' : '새 비밀번호',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('6자 이상. 바꾸면 모든 기기에서 새 비밀번호를 씁니다.', style: TextStyle(color: Tone.muted(context))),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pw,
                      obscureText: true,
                      autofocus: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '새 비밀번호'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw2,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(labelText: '한 번 더'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('비밀번호 바꾸기'),
                    ),
                    if (widget.fromRecovery)
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        onPressed: _busy ? null : widget.onDone,
                        child: const Text('나중에 하기'),
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
