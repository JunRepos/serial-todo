import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/repository.dart';
import 'ui/app_scope.dart';
import 'ui/auth_page.dart';
import 'ui/brand.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'widget/widget_sync.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const _ConfigMissing());
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  final repo = Repository(prefs, Supabase.instance.client)..onGraphChanged = WidgetSync.schedule;
  await WidgetSync.init();
  runApp(SerialTodoApp(repo: repo, prefs: prefs));
}

class SerialTodoApp extends StatefulWidget {
  const SerialTodoApp({super.key, required this.repo, required this.prefs});
  final Repository repo;
  final SharedPreferences prefs;

  @override
  State<SerialTodoApp> createState() => _SerialTodoAppState();
}

class _SerialTodoAppState extends State<SerialTodoApp> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _authSub;
  StreamSubscription<Uri?>? _widgetSub;
  final _widgetUri = ValueNotifier<Uri?>(null);
  Session? _session;

  @override
  void initState() {
    super.initState();
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
      }
      setState(() => _session = s.session);
    });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: widget.repo,
      prefs: widget.prefs,
      child: MaterialApp(
        title: '할일이많아',
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
