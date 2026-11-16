import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serial_todo/data/repository.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/models/item.dart';
import 'package:serial_todo/ui/app_scope.dart';
import 'package:serial_todo/ui/common.dart';
import 'package:serial_todo/ui/item_sheet.dart';
import 'package:serial_todo/ui/shell.dart';
import 'package:serial_todo/ui/theme.dart';
import 'package:serial_todo/widget/notif_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'graph_test.dart' show sample;

Future<(Repository, SharedPreferences)> _repo([List<Item>? items]) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = Repository(
    prefs,
    SupabaseClient('http://localhost:1', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false)),
  )..debugLoad('u1', items ?? sample());
  return (repo, prefs);
}

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  group('끌어 옮기기(moveTo)', () {
    test('같은 상위 안에서 순서만 바꾸면 선행 관계는 그대로', () async {
      final (repo, _) = await _repo();
      expect(repo.moveTo('a3', 'p1', before: 'a1'), isTrue);
      expect(repo.graph.kids('p1').map((e) => e.id), ['a3', 'a1', 'a2']);
      expect(repo['a3']!.deps, ['a1', 'a2']);
      await repo.stop();
    });

    test('다른 프로젝트 아래로: 상위·순서가 바뀌고, 순환이 되는 선행은 끊는다', () async {
      final (repo, _) = await _repo();
      expect(repo.moveTo('a1', 'p2', before: 'a5'), isTrue);
      final g = repo.graph;
      expect(g.kids('p2').map((e) => e.id), ['a4', 'a1', 'a5', 'a6']);
      expect(g.kids('p1').map((e) => e.id), ['a2', 'a3']);
      // p2는 p1이 끝나야 시작하는데 a3(p1 안)이 a1(이제 p2 안)을 기다리면 서로 물린다 → 그 선행은 끊는다
      expect(repo['a3']!.deps, ['a2']);
      expect(g.sequenceOf('g1').cyc, isEmpty);
      await repo.stop();
    });

    test('액션을 최상위로 올리면 목표가 되고, 목표 밖 선행은 끊긴다', () async {
      final (repo, _) = await _repo();
      expect(repo.moveTo('a3', null), isTrue);
      expect(repo['a3']!.level, 0);
      expect(repo['a3']!.deps, isEmpty);
      expect(repo.graph.goals.map((e) => e.id), ['g1', 'a3']);
      await repo.stop();
    });

    test('프로젝트를 통째로 목표로, 하위 단계도 함께 바뀐다', () async {
      final (repo, _) = await _repo();
      expect(repo.moveTo('p2', null), isTrue);
      expect(repo['p2']!.level, 0);
      expect(repo['a4']!.level, 1);
      // p3 → p2 선행은 목표가 달라져 끊긴다
      expect(repo['p3']!.deps, isEmpty);
      await repo.stop();
    });

    test('자기 하위로, 또는 3단계를 넘게는 옮길 수 없다', () async {
      final (repo, _) = await _repo();
      expect(repo.moveTo('p1', 'a1'), isFalse);
      expect(repo.moveTo('p1', 'p2'), isFalse); // p1 아래 액션이 4단계가 된다
      expect(repo.moveTo('g1', 'p1'), isFalse);
      expect(repo.graph.canMove('a1', 'g1'), isTrue);
      await repo.stop();
    });

    test('옮긴 뒤 순환이 생기면 묶음 밖 선행을 끊는다', () async {
      final (repo, _) = await _repo();
      // a4는 p2(→p1 선행) 안에 있다. a1(p1 안)이 a4를 기다리게 한 뒤 a4를 p1로 옮겨도 순환이 남지 않아야 한다
      repo.moveTo('a4', 'p3');
      final g = repo.graph;
      expect(g.sequenceOf('g1').cyc, isEmpty);
      await repo.stop();
    });
  });

  group('그래프 보강', () {
    test('상위 관계가 서로 물린 항목도 사라지지 않고 최상위에 보인다', () {
      final g = Graph([
        Item(id: 'x', parentId: 'y', level: 1, title: 'x'),
        Item(id: 'y', parentId: 'x', level: 1, title: 'y'),
        Item(id: 'g', title: 'g'),
      ]);
      expect(g.inTreeOrder.length, 3);
      expect(g.goals.length, 2);
      expect(g.leaves('x'), isNotEmpty);
    });

    test('프로젝트가 자기 하위에 기대는 항목을 선행으로 삼으면 순환', () {
      final items = sample()..add(Item(id: 'c', parentId: 'p2', level: 2, sort: 9, title: 'c', deps: ['a1']));
      final g = Graph(items);
      // p1 → c 를 걸면 a1 은 c 를, c 는 a1 을 기다리게 된다
      expect(g.reaches('c', 'p1'), isTrue);
    });

    test('touch는 기기 시계가 느려도 항상 뒤 시각을 찍는다', () {
      final it = Item(id: 'i', updatedAt: DateTime.now().toUtc().add(const Duration(minutes: 5)));
      final before = it.updatedAt;
      it.touch();
      expect(it.updatedAt.isAfter(before), isTrue);
    });
  });

  group('일정', () {
    test('시간·장소·알림을 담고, 달력에는 시각 순 한 줄로', () async {
      final (repo, _) = await _repo();
      final a = repo.saveEvent(
        title: '회의',
        date: '2026-11-20',
        attrs: {'t': '14:00', 'e': '15:00', 'loc': '교무실', 'rem': '10'},
      )!;
      repo.saveEvent(title: '조회', date: '2026-11-20', attrs: {'t': '08:30'});
      repo.saveEvent(title: '체험학습', date: '2026-11-19', attrs: {'end': '2026-11-21'});
      final g = repo.graph;
      expect(g.byId.containsKey(a.id), isFalse); // 할 일 트리에는 없다
      expect(a.chipTitle, '14:00 회의');
      expect(a.eventSummary, '14:00–15:00 · 교무실');
      expect(a.remindAt, DateTime(2026, 11, 20, 13, 50));
      // 여러 날 일정은 날마다, 하루 종일 → 이른 시각 순
      expect(g.byDate['2026-11-20']!.map((e) => e.title), ['체험학습', '조회', '회의']);
      expect(g.byDate['2026-11-21']!.map((e) => e.title), ['체험학습']);

      // 고치면 지운 정보는 사라진다
      repo.saveEvent(id: a.id, title: '회의', date: '2026-11-20', attrs: {'t': null, 'e': null, 'rem': '1440'});
      final b = repo[a.id]!;
      expect(b.startTime, isNull);
      expect(b.location, '교무실');
      expect(b.remindAt, DateTime(2026, 11, 19, 9)); // 하루 종일은 오전 9시 기준, 하루 전
      await repo.stop();
    });

    test('알림: 앞으로 울릴 것만 이른 순으로, 지난 것은 뺀다', () async {
      final (repo, _) = await _repo();
      repo.saveEvent(title: '지남', date: '2026-11-01', attrs: {'t': '10:00', 'rem': '0'});
      repo.saveEvent(title: '나중', date: '2026-11-25', attrs: {'t': '10:00', 'rem': '60'});
      repo.saveEvent(title: '먼저', date: '2026-11-21', attrs: {'rem': '0'});
      repo.saveEvent(title: '알림 없음', date: '2026-11-22');
      final now = DateTime(2026, 11, 20, 12);
      expect(NotifSync.upcoming(repo.graph, now: now).map((e) => e.title), ['먼저', '나중']);
      expect(NotifSync.due(repo.graph, DateTime(2026, 11, 25, 8, 59), DateTime(2026, 11, 25, 9)).map((e) => e.title), [
        '나중',
      ]);
      await repo.stop();
    });
  });

  testWidgets('삭제 알림은 화면 위쪽에 뜨고 되돌릴 수 있다 · 캘린더 + 는 일정 편집을 연다', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (repo, prefs) = await _repo();
    await t.pumpWidget(
      AppScope(
        repo: repo,
        prefs: prefs,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Shell(),
        ),
      ),
    );
    await t.pump();

    // 항목 삭제 → 위쪽 알림 → 되돌리기
    deleteWithUndo(t.element(find.byType(Shell)), repo, 'a1');
    await t.pump();
    expect(repo['a1'], isNull);
    final toast = find.text('"a1" 삭제됨');
    expect(toast, findsOneWidget);
    expect(t.getTopLeft(toast).dy, lessThan(120)); // 화면 위쪽
    expect(find.byType(SnackBar), findsNothing);
    await t.tap(find.text('되돌리기'));
    await t.pump();
    expect(repo['a1'], isNotNull);
    expect(toast, findsNothing);

    // 캘린더 탭의 + 는 일정 편집 화면
    await t.tap(find.text('캘린더').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.text('하루 종일'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, '일정 제목'), '학부모 상담');
    await t.enterText(find.widgetWithText(TextField, '장소'), '상담실');
    await t.pump();
    await t.tap(find.widgetWithText(ChoiceChip, '10분 전'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '저장'));
    await t.pumpAndSettle();
    final ev = repo.graph.events.values.single;
    expect(ev.title, '학부모 상담');
    expect(ev.location, '상담실');
    expect(ev.remindMinutes, 10);
    expect(ev.due, dateKey(DateTime.now()));

    hideTopToast();
    await repo.stop();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
