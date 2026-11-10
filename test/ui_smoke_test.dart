import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serial_todo/data/repository.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/models/item.dart';
import 'package:serial_todo/ui/app_scope.dart';
import 'package:serial_todo/ui/shell.dart';
import 'package:serial_todo/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'graph_test.dart' show sample;

Future<Repository> _repo() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = Repository(
    prefs,
    SupabaseClient('http://localhost:1', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false)),
  );
  final items = sample();
  final now = DateTime.now();
  items.firstWhere((e) => e.id == 'a1')
    ..today = true
    ..due = dateKey(now);
  items.firstWhere((e) => e.id == 'a2').due = dateKey(now.subtract(const Duration(days: 2)));
  items.firstWhere((e) => e.id == 'g1').due = dateKey(now.add(const Duration(days: 9)));
  repo.debugLoad('u1', items);
  return repo;
}

Widget _app(Repository repo, SharedPreferences prefs, Brightness b) => AppScope(
  repo: repo,
  prefs: prefs,
  child: MaterialApp(
    theme: buildTheme(b),
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const Shell(),
  ),
);

/// 남은 타이머(전송 대기·재시도·스낵바) 정리
Future<void> _done(WidgetTester t, Repository repo) async {
  await repo.stop();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    for (final b in Brightness.values) {
      testWidgets('4개 탭과 편집 시트가 그려진다 ${size.width.toInt()} ${b.name}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final repo = await _repo();
        final prefs = await SharedPreferences.getInstance();
        await t.pumpWidget(_app(repo, prefs, b));
        await t.pump();

        // 구조
        expect(find.text('g1'), findsWidgets);
        expect(find.textContaining('대기 · '), findsWidgets);

        // 편집 시트
        await t.tap(find.text('a3').first);
        await t.pumpAndSettle();
        expect(find.text('선행 항목 · 이게 끝나야 시작'), findsOneWidget);
        expect(find.textContaining('예상'), findsNothing);
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();

        // 순서
        await t.tap(find.text('순서').last);
        await t.pumpAndSettle();
        expect(find.textContaining('지금 단계'), findsOneWidget);
        expect(find.textContaining('동시 진행 가능 2개'), findsOneWidget);

        // 오늘
        await t.tap(find.text('오늘').last);
        await t.pumpAndSettle();
        expect(find.text('바로 할 수 있음'), findsOneWidget);
        expect(find.text('대기 중'), findsOneWidget);

        // 캘린더
        await t.tap(find.text('캘린더').last);
        await t.pumpAndSettle();
        expect(find.textContaining('마감 없는 항목'), findsOneWidget);
        expect(find.text('a1'), findsWidgets);
        await _done(t, repo);
      });
    }
  }

  testWidgets('체크·여러 줄 붙여넣기', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await _repo();
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(_app(repo, prefs, Brightness.light));
    await t.pump();

    // a1 완료 체크 → a2만 남아도 a3는 여전히 대기
    await t.tap(find.bySemanticsLabel('완료').first);
    await t.pump();
    expect(repo['a1']!.status, 'done');
    expect(repo.pendingCount, greaterThan(0));

    // 목표 행의 + → 여러 줄 붙여넣기
    await t.tap(find.byTooltip('프로젝트 추가').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '시장 조사\n  경쟁사 A\n  경쟁사 B\n기획서\n  목차');
    await t.pump();
    // 붙여넣기만으로는 아직 추가되지 않고, 버튼에 개수가 나온다
    expect(repo.graph.kids('g1').where((e) => e.title == '기획서'), isEmpty);
    // 목록 아래쪽이라 화면 가운데로 올린 뒤 누른다
    await Scrollable.ensureVisible(t.element(find.widgetWithText(FilledButton, '5개 추가')), alignment: 0.5);
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '5개 추가'));
    await t.pump();
    final g = repo.graph;
    final newProj = g.kids('g1').where((e) => e.title == '시장 조사' || e.title == '기획서').toList();
    expect(newProj.length, 2);
    expect(g.kids(newProj.first.id).map((e) => e.title), ['경쟁사 A', '경쟁사 B']);
    expect(newProj.first.level, 1);
    expect(g.kids(newProj.first.id).first.level, 2);
    expect(find.text('5개 추가'), findsOneWidget);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(repo.graph.byId.values.where((Item i) => i.deleted).isEmpty, isTrue);
    await _done(t, repo);
  });

  testWidgets('목표 추가: Enter는 줄바꿈, [추가] 버튼으로 추가', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await _repo();
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(_app(repo, prefs, Brightness.light));
    await t.pumpAndSettle();
    final before = repo.graph.goals.length;

    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    final field = find.widgetWithText(TextField, '새 목표 · 한 줄에 하나씩');
    expect(field, findsOneWidget);
    // 비어 있으면 추가 버튼이 꺼져 있다
    final btn = find.widgetWithText(FilledButton, '추가');
    expect(t.widget<FilledButton>(btn).onPressed, isNull);

    // Enter(줄바꿈)만으로는 추가되지 않는다
    await t.enterText(field, '운동하기\n');
    await t.pump();
    expect(repo.graph.goals.length, before);

    await t.enterText(field, '운동하기\n책 읽기');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '2개 추가'));
    await t.pump();
    expect(repo.graph.goals.length, before + 2);
    expect(repo.graph.goals.map((e) => e.title), containsAll(['운동하기', '책 읽기']));
    // 추가 후 입력창은 비워진 채 열려 있다
    expect(find.widgetWithText(TextField, '새 목표 · 한 줄에 하나씩'), findsOneWidget);

    await t.enterText(field, '혼자 추가');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '추가'));
    await t.pump();
    expect(repo.graph.goals.map((e) => e.title), contains('혼자 추가'));
    await _done(t, repo);
  });
}
