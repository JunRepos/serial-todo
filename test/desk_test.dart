import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serial_todo/desktop/desk_bridge.dart';
import 'package:serial_todo/desktop/desk_calendar.dart';
import 'package:serial_todo/desktop/desk_main.dart';
import 'package:serial_todo/desktop/desk_todo.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/models/item.dart';
import 'package:serial_todo/ui/common.dart';
import 'package:serial_todo/ui/theme.dart';

/// 네이티브·서버 없이 위젯 화면만 확인하는 가짜 데이터
class FakeData extends DeskData {
  FakeData(List<Item> items) : _items = items;
  final List<Item> _items;
  final added = <(String, String?, bool)>[];

  @override
  Graph get graph => Graph(_items);
  @override
  bool signedIn = true;
  @override
  bool get ready => true;
  @override
  DeskSync get sync => DeskSync.synced;
  @override
  int get pending => 0;

  @override
  void toggleDone(String id) {
    final it = _items.firstWhere((e) => e.id == id);
    it.status = it.status == 'done' ? 'todo' : 'done';
    it.doneAt = it.status == 'done' ? DateTime.now().toUtc() : null;
    notifyListeners();
  }

  @override
  void toggleToday(String id) {
    final it = _items.firstWhere((e) => e.id == id);
    it.today = !it.today;
    notifyListeners();
  }

  @override
  void add(String title, {String? due, bool today = false}) {
    added.add((title, due, today));
    _items.add(Item(id: 'n${added.length}', title: title, due: due, today: today, sort: 99));
    notifyListeners();
  }

  @override
  void refresh() {}
}

List<Item> _items() {
  final today = dateKey(DateTime.now());
  return [
    Item(id: 'g', title: '여행 준비', sort: 1, due: today),
    Item(id: 'a', parentId: 'g', level: 1, sort: 1, title: '숙소 예약', today: true, due: today),
    Item(id: 'b', parentId: 'g', level: 1, sort: 2, title: '짐 싸기'),
    Item(id: 'c', title: '물 마시기', sort: 2),
  ];
}

Widget _wrap(DeskData data, Widget child, Brightness b) => DeskScope(
  data: data,
  child: MaterialApp(
    theme: buildTheme(b),
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: child,
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  for (final b in Brightness.values) {
    for (final size in [const Size(340, 460), const Size(240, 220)]) {
      testWidgets('할 일 창 ${size.width.toInt()} ${b.name}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final data = FakeData(_items());
        await t.pumpWidget(_wrap(data, const DeskTodo(), b));
        await t.pump();
        expect(find.text('오늘 할 일'), findsOneWidget);
        if (size.height > 300) {
          expect(find.text('숙소 예약'), findsOneWidget);
          expect(find.text('짐 싸기'), findsOneWidget);
        }
      });

      testWidgets('캘린더 창 ${size.width.toInt()} ${b.name}', (t) async {
        t.view.physicalSize = size.width < 300 ? const Size(260, 240) : const Size(520, 460);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(_wrap(FakeData(_items()), const DeskCalendar(), b));
        await t.pump();
        expect(find.textContaining('월'), findsWidgets);
      });
    }
  }

  testWidgets('할 일 창: 체크·★·추가', (t) async {
    t.view.physicalSize = const Size(340, 460);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final data = FakeData(_items());
    await t.pumpWidget(_wrap(data, const DeskTodo(), Brightness.light));
    await t.pump();

    // ★ 오늘: 숙소 예약 1개 → 완료하면 '오늘 끝냄'으로
    await t.tap(find.byType(StatusCheck).first);
    await t.pump();
    expect(data.graph['a']!.status, 'done');
    expect(find.text('오늘 끝냄  1'), findsOneWidget);

    // 짐 싸기를 ★로
    await t.tap(find.byTooltip('오늘 할 일로').first);
    await t.pump();
    expect(data.graph.byId.values.where((e) => e.today && e.status != 'done').length, 1);

    // 추가 버튼은 비어 있으면 꺼져 있고, 쓰면 오늘 할 일로 추가된다
    final btn = find.widgetWithText(FilledButton, '추가');
    expect(t.widget<FilledButton>(btn).onPressed, isNull);
    await t.enterText(find.byType(TextField), '보고서 쓰기');
    await t.pump();
    await t.tap(btn);
    await t.pump();
    expect(data.added.single, ('보고서 쓰기', null, true));
    expect(find.text('보고서 쓰기'), findsOneWidget);
  });

  testWidgets('캘린더: 오늘 칸에 마감 항목, 날짜를 누르면 목록과 추가', (t) async {
    t.view.physicalSize = const Size(520, 460);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final data = FakeData(_items());
    await t.pumpWidget(_wrap(data, const DeskCalendar(), Brightness.light));
    await t.pump();
    expect(find.text('숙소 예약'), findsOneWidget);

    await t.tap(find.text('${DateTime.now().day}').first);
    await t.pumpAndSettle();
    expect(find.text('이날 마감으로 추가'), findsOneWidget);
    await t.enterText(find.byType(TextField), '체크인');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '추가'));
    await t.pump();
    expect(data.added.single, ('체크인', dateKey(DateTime.now()), false));
  });

  testWidgets('로그인 전: 할 일 창은 캘린더 창으로 안내', (t) async {
    final data = FakeData(_items())..signedIn = false;
    await t.pumpWidget(_wrap(data, const DeskTodo(), Brightness.light));
    await t.pump();
    expect(find.text('캘린더 창에서 로그인'), findsOneWidget);
  });
}
