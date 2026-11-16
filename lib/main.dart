import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/repository.dart';
import 'desktop/desk_main.dart';
import 'ui/app_scope.dart';
import 'ui/auth_page.dart';
import 'ui/brand.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/common.dart';
import 'widget/notif_sync.dart';
import 'widget/widget_sync.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// 재설정 메일 링크를 요청한 기기가 아닌 곳(예: 폰에서 요청, PC 브라우저에서 열기)에서도
/// 열 수 있도록 코드 교환(PKCE) 대신 토큰이 바로 오는 방식을 쓴다.
const authOptions = FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit);

Future<void> main(List<String> args) async {
  // 윈도우: 바탕화면 위젯(캘린더·할 일 창)으로 실행
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && supabaseUrl.isNotEmpty) {
    return deskMain(args, url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const _ConfigMissing());
    return;
  }
  // 재설정 메일의 링크로 들어왔는지 (Supabase가 주소의 토큰을 지우기 전에 확인)
  final link = Uri.base.toString();
  final recovery = kIsWeb && link.contains('type=recovery') && link.contains('access_token');
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey, authOptions: authOptions);
  final prefs = await SharedPreferences.getInstance();
  final repo = Repository(prefs, Supabase.instance.client)
    ..onGraphChanged = (g) {
      WidgetSync.schedule(g);
      NotifSync.schedule(g);
    };
  await WidgetSync.init();
  await NotifSync.init();
  runApp(SerialTodoApp(repo: repo, prefs: prefs, recovery: recovery));
}

class SerialTodoApp extends StatefulWidget {
  const SerialTodoApp({super.key, required this.repo, required this.prefs, this.recovery = false});
  final Repository repo;
  final SharedPreferences prefs;

  /// 비밀번호 재설정 링크로 열렸다
  final bool recovery;

  @override
  State<SerialTodoApp> createState() => _SerialTodoAppState();
}

class _SerialTodoAppState extends State<SerialTodoApp> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _authSub;
  StreamSubscription<Uri?>? _widgetSub;
  final _widgetUri = ValueNotifier<Uri?>(null);
  Session? _session;
  bool _needNewPassword = false;
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _needNewPassword = widget.recovery;
    WidgetsBinding.instance.addObserver(this);
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    if (_session != null) _startRepo(_session!.user.id);
    _authSub = auth.onAuthStateChange.listen((s) {
      final uid = s.session?.user.id;
      if (uid != null) {
        _startRepo(uid);
      } else if (s.event == AuthChangeEvent.signedOut) {
        widget.repo.stop();
        WidgetSync.clear();
      }
      setState(() {
        _session = s.session;
        if (s.event == AuthChangeEvent.passwordRecovery) _needNewPassword = true;
      });
    });
    // 웹: 앱이 열려 있는 동안 일정 알림 시각이 되면 화면 위에 알린다
    NotifSync.watch(
      () => widget.repo.graph,
      onFire: (e) => showTopToast(
        null,
        '🔔 ${e.title} · ${e.eventSummary}',
        overlay: _nav.currentState?.overlay,
        duration: const Duration(seconds: 20),
      ),
    );
    if (WidgetSync.supported) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetUri);
      _widgetSub = HomeWidget.widgetClicked.listen(_onWidgetUri);
    }
  }

  Future<void> _startRepo(String uid) async {
    await widget.repo.start(uid);
    await _applyWidgetQueue();
  }

  Future<void> _applyWidgetQueue() async {
    final ids = await WidgetSync.takeDoneQueue();
    if (ids.isNotEmpty) widget.repo.applyExternalDone(ids);
  }

  void _onWidgetUri(Uri? uri) {
    if (uri != null && (uri.host == 'open' || uri.host == 'add')) _widgetUri.value = uri;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null) {
      _applyWidgetQueue();
      widget.repo.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub.cancel();
    _widgetSub?.cancel();
    NotifSync.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: widget.repo,
      prefs: widget.prefs,
      child: MaterialApp(
        title: '할일이많아',
        navigatorKey: _nav,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: IntroSplash(child: _home()),
      ),
    );
  }

  Widget _home() {
    if (widget.prefs.getBool(Onboarding.prefsKey) != true) {
      return Onboarding(
        onDone: () {
          widget.prefs.setBool(Onboarding.prefsKey, true);
          setState(() {});
        },
      );
    }
    if (_session != null && _needNewPassword) {
      return NewPasswordPage(fromRecovery: true, onDone: () => setState(() => _needNewPassword = false));
    }
    return _session == null ? const AuthPage() : Shell(widgetUri: _widgetUri);
  }
}

class _ConfigMissing extends StatelessWidget {
  const _ConfigMissing();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'SUPABASE_URL / SUPABASE_ANON_KEY 가 빌드에 주입되지 않았습니다.\n'
            '--dart-define-from-file 로 빌드하세요.',
          ),
        ),
      ),
    ),
  );
}
