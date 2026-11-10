import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import '../ui/app_scope.dart';
import '../ui/theme.dart';
import 'desk_bridge.dart';
import 'desk_calendar.dart';
import 'desk_todo.dart';

/// 윈도우 바탕화면 위젯 진입점. 네이티브가 창마다 `--desk=calendar|todo`로 엔진을 띄운다.
/// 캘린더 창이 로그인·동기화를 맡고, 할 일 창은 중계로 데이터를 받는다.
Future<void> deskMain(List<String> args, {required String url, required String anonKey}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  DeskNative.init();
  final role = args.contains('--desk=todo') ? 'todo' : 'calendar';

  if (role == 'todo') {
    runApp(_DeskApp(data: RelayData(), child: const DeskTodo()));
    return;
  }

  await Supabase.initialize(url: url, publishableKey: anonKey);
  final prefs = await SharedPreferences.getInstance();
  final repo = Repository(prefs, Supabase.instance.client);
  final data = RepoData(repo);
  runApp(
    AppScope(
      repo: repo,
      prefs: prefs,
      child: _DeskApp(data: data, child: const DeskCalendar()),
    ),
  );
}

class _DeskApp extends StatelessWidget {
  const _DeskApp({required this.data, required this.child});
  final DeskData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DeskScope(
      data: data,
      child: MaterialApp(
        title: '할일이많아',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    );
  }
}

/// 위젯 화면에서 [DeskData]를 꺼내 쓰는 범위.
class DeskScope extends InheritedNotifier<DeskData> {
  const DeskScope({super.key, required DeskData data, required super.child}) : super(notifier: data);

  static DeskData of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DeskScope>()!.notifier!;
}

/// 캘린더 창: 저장소를 직접 쓰고, 바뀔 때마다 할 일 창에 스냅숏을 보낸다.
class RepoData extends DeskData {
  RepoData(this.repo) {
    final auth = Supabase.instance.client.auth;
    _signedIn = auth.currentSession != null;
    if (_signedIn) repo.start(auth.currentSession!.user.id);
    _authSub = auth.onAuthStateChange.listen((s) {
      final uid = s.session?.user.id;
      if (uid != null) {
        if (!_signedIn) repo.start(uid);
        _signedIn = true;
      } else if (s.event == AuthChangeEvent.signedOut) {
        _signedIn = false;
        repo.stop();
      }
      notifyListeners();
      _broadcast();
    });
    repo.addListener(_onRepo);
    DeskRelay.listen(_onMessage);
    // 몇 분마다 새로 고침(실시간 연결이 끊겼을 때 대비)과 날짜 바뀜 반영
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_signedIn) repo.refresh();
      notifyListeners();
    });
  }

  final Repository repo;
  late final StreamSubscription<AuthState> _authSub;
  late final Timer _timer;
  bool _signedIn = false;
  Timer? _debounce;

  @override
  Graph get graph => repo.graph;
  @override
  bool get signedIn => _signedIn;
  @override
  bool get ready => true;
  @override
  DeskSync get sync => DeskSync.values.byName(repo.sync.name);
  @override
  int get pending => repo.pendingCount;

  void _onRepo() {
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _broadcast);
  }

  void _broadcast() {
    DeskRelay.send({
      't': 'snap',
      'signedIn': _signedIn,
      'sync': sync.name,
      'pending': pending,
      'items': [for (final it in repo.graph.byId.values) it.toJson()],
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hello':
        _broadcast();
      case 'act':
        final id = m['id'] as String?;
        switch (m['op']) {
          case 'toggleDone':
            if (id != null) repo.toggleDone(id);
          case 'toggleToday':
            if (id != null) repo.toggleToday(id);
          case 'add':
            add(m['title'] as String? ?? '', due: m['due'] as String?, today: m['today'] == true);
          case 'refresh':
            refresh();
        }
        // 할 일 창이 미리 바꿔 둔 화면을 확정
        _broadcast();
    }
  }

  @override
  void toggleDone(String id) => repo.toggleDone(id);
  @override
  void toggleToday(String id) => repo.toggleToday(id);
  @override
  void add(String title, {String? due, bool today = false}) => repo.add(null, title, due: due, today: today);
  @override
  void refresh() {
    if (_signedIn) repo.refresh();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _timer.cancel();
    _debounce?.cancel();
    repo.removeListener(_onRepo);
    super.dispose();
  }
}

String todayKey() => dateKey(DateTime.now());
