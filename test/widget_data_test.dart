import 'package:flutter_test/flutter_test.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/models/item.dart';
import 'package:serial_todo/widget/widget_sync.dart';

import 'graph_test.dart' show sample;

void main() {
  final now = DateTime(2026, 11, 10, 9);

  test('오늘(★)을 먼저, 남는 자리는 바로 할 수 있음으로 채운다', () {
    final items = sample();
    items.firstWhere((e) => e.id == 'a2').today = true;
    items.firstWhere((e) => e.id == 'a1').due = '2026-11-12';
    final d = WidgetSync.buildData(Graph(items), now: now);
    final list = d['items'] as List;
    expect(list.map((e) => e['id']), ['a2', 'a1']);
    expect(list.first['today'], isTrue);
    expect(list[1]['today'], isFalse);
    expect(list[1]['due'], '2026-11-12'); // 날짜 원본 그대로 (위젯이 D-day 계산)
    expect(list.first['parent'], 'p1');
    expect(d['remaining'], 1);
    expect(d['ready'], 1);
    expect(d['doneToday'], 0);
  });

  test('오늘 완료 수는 오늘 끝낸 말단만 센다', () {
    final items = sample();
    items.firstWhere((e) => e.id == 'a1')
      ..status = 'done'
      ..doneAt = DateTime(2026, 11, 10, 8).toUtc();
    items.firstWhere((e) => e.id == 'a2')
      ..status = 'done'
      ..doneAt = DateTime(2026, 11, 9, 20).toUtc();
    final d = WidgetSync.buildData(Graph(items), now: now);
    expect(d['doneToday'], 1);
  });

  test('최대 개수 제한', () {
    final items = sample();
    for (final i in items) {
      i.deps = [];
      i.seq = false;
      i.today = true;
    }
    final d = WidgetSync.buildData(Graph(items), now: now);
    expect((d['items'] as List).length, WidgetSync.maxItems);
    expect(d['remaining'], 8);
  });

  test('위젯 체크: 표시·남은 수·완료 수 갱신, 두 번 눌러도 한 번만', () {
    final items = sample();
    items.firstWhere((e) => e.id == 'a2').today = true;
    var d = WidgetSync.buildData(Graph(items), now: now);
    d = WidgetSync.markDone(d, 'a2');
    expect((d['items'] as List).first['done'], isTrue);
    expect(d['remaining'], 0);
    expect(d['doneToday'], 1);
    final again = WidgetSync.markDone(d, 'a2');
    expect(again['doneToday'], 1);
    d = WidgetSync.markDone(d, 'a1');
    expect(d['ready'], 0);
    expect(d['doneToday'], 2);
  });

  test('계열 위젯: 목표별 줄과 완료 수, 체크하면 그 줄과 완료 수가 바뀐다', () {
    final items = sample();
    var d = WidgetSync.buildData(Graph(items), now: now);
    final series = d['series'] as List;
    expect(series, isNotEmpty);
    final goal = series.first as Map;
    final rows = goal['rows'] as List;
    expect(rows.where((r) => r['t'] == 'a').length, goal['total']);
    final first = rows.firstWhere((r) => r['t'] == 'a') as Map;
    final before = goal['done'] as int;

    d = WidgetSync.markDone(d, first['id'] as String);
    final after = (d['series'] as List).first as Map;
    expect(after['done'], before + 1);
    expect((after['rows'] as List).firstWhere((r) => r['id'] == first['id'])['done'], isTrue);
  });

  test('일정 위젯: 오늘부터의 일정과 끝나지 않은 마감만, 일정은 할 일 목록에 없다', () {
    final items = sample()
      ..add(Item(id: 'e1', level: Item.eventLevel, title: '치과', due: '2026-11-10'))
      ..add(Item(id: 'e0', level: Item.eventLevel, title: '지난 일정', due: '2026-11-01'));
    items.firstWhere((e) => e.id == 'a1').due = '2026-11-05'; // 지난 마감
    final d = WidgetSync.buildData(Graph(items), now: now);
    final agenda = d['agenda'] as List;
    expect(agenda.map((e) => e['id']), ['a1', 'e1']);
    expect(agenda.last['e'], isTrue);
    expect((d['items'] as List).any((e) => e['id'] == 'e1'), isFalse);
    expect(WidgetSync.markDone(d, 'a1')['agenda'].map((e) => e['id']), ['e1']);
  });
}
