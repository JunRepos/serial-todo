import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../logic/graph.dart';
import '../models/item.dart';

/// 안드로이드 홈 화면 위젯과 데이터 주고받기.
class WidgetSync {
  static const androidName = 'TodayWidgetProvider';

  /// 같은 데이터를 쓰는 홈 화면 위젯 전부 (오늘 · 계열 · 일정)
  static const androidNames = [androidName, 'SeriesWidgetProvider', 'AgendaWidgetProvider'];

  /// 계열·일정 위젯에 넣는 최대 줄 수
  static const maxSeriesRows = 300, maxAgenda = 60;
  static const _kData = 'widget_json';
  static const _kDoneQueue = 'widget_done_queue';

  /// 위젯에 넣는 최대 항목 수 (위젯 크기에 따라 Kotlin 쪽에서 더 줄인다)
  static const maxItems = 6;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Timer? _debounce;

  static Future<void> init() async {
    if (!supported) return;
    await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  }

  /// 앱 데이터가 바뀔 때마다 호출. 짧게 모아서 한 번만 갱신.
  static void schedule(Graph g) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => push(g));
  }

  /// 위젯 표시용 데이터.
  /// 오늘(★) 항목을 먼저, 자리가 남으면 "바로 할 수 있음" 항목으로 채운다.
  /// 마감은 날짜 그대로 넘겨 위젯이 그날 기준으로 D-day를 계산한다(자정이 지나도 정확).
  static Map<String, dynamic> buildData(Graph g, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final lists = g.todayLists(now: t);
    final todayKey = dateKey(t);
    final doneToday = g.byId.values
        .where(
          (i) => g.isLeaf(i.id) && i.status == 'done' && i.doneAt != null && dateKey(i.doneAt!.toLocal()) == todayKey,
        )
        .length;

    Map<String, dynamic> row(Item it, bool today) {
      final parent = g.parentOf(it.id);
      return {
        'id': it.id,
        'title': it.title,
        'parent': parent == null ? '' : g[parent]!.title,
        'due': it.due ?? '',
        'today': today,
        'done': false,
      };
    }

    final items = [
      for (final it in lists.today.take(maxItems)) row(it, true),
      for (final it in lists.ready.take(maxItems - lists.today.take(maxItems).length)) row(it, false),
    ];
    return {
      'v': 3,
      'remaining': lists.today.length,
      'ready': lists.ready.length,
      'doneToday': doneToday,
      'items': items,
      'series': _series(g),
      'agenda': _agenda(g, todayKey),
    };
  }

  /// 계열 위젯: 하위가 있고 끝나지 않은 목표마다, 그 아래 프로젝트·액션을 트리 순서로.
  static List<Map<String, dynamic>> _series(Graph g) {
    final out = <Map<String, dynamic>>[];
    var budget = maxSeriesRows;
    for (final goal in g.orderedGoals()) {
      if (g.isLeaf(goal.id) || g.isDone(goal.id)) continue;
      final rows = <Map<String, dynamic>>[];
      void walk(String parent, int depth) {
        for (final it in g.kids(parent)) {
          if (budget <= 0) return;
          budget--;
          if (g.isLeaf(it.id)) {
            rows.add({
              'id': it.id,
              'title': it.title,
              't': 'a',
              'depth': depth,
              'done': it.status == 'done',
              'blocked': g.isBlocked(it.id),
              'today': it.today,
              'due': it.due ?? '',
            });
          } else {
            final l = g.leaves(it.id);
            rows.add({
              'id': it.id,
              'title': it.title,
              't': 'p',
              'depth': depth,
              'count': '${l.where(g.isDone).length}/${l.length}',
            });
            walk(it.id, depth + 1);
          }
        }
      }

      walk(goal.id, 1);
      final l = g.leaves(goal.id);
      out.add({
        'id': goal.id,
        'title': goal.title,
        'done': l.where(g.isDone).length,
        'total': l.length,
        'blocked': g.isBlocked(goal.id),
        'rows': rows,
      });
    }
    return out;
  }

  /// 일정 위젯: 오늘부터의 일정 + 끝나지 않은 마감(지난 것 포함)을 날짜순으로.
  static List<Map<String, dynamic>> _agenda(Graph g, String todayKey) {
    final out = <Map<String, dynamic>>[];
    final dates = g.byDate;
    for (final date in dates.keys.toList()..sort()) {
      for (final it in dates[date]!) {
        if (it.isEvent ? date.compareTo(todayKey) < 0 : g.isDone(it.id)) continue;
        if (out.length >= maxAgenda) return out;
        out.add({
          'id': it.id,
          'title': it.title,
          'date': date,
          'e': it.isEvent,
          'parent': it.isEvent ? '' : g.path(it.id),
        });
      }
    }
    return out;
  }

  static Future<void> updateAll() async {
    for (final name in androidNames) {
      await HomeWidget.updateWidget(androidName: name);
    }
  }

  static Future<void> push(Graph g) async {
    if (!supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(_kData, jsonEncode(buildData(g)));
      await updateAll();
    } catch (e) {
      debugPrint('widget update failed: $e');
    }
  }

  /// 위젯에서 체크한 뒤 아직 앱에 반영되지 않은 id들 (꺼내면서 비운다)
  static Future<List<String>> takeDoneQueue() async {
    if (!supported) return const [];
    try {
      final raw = await HomeWidget.getWidgetData<String>(_kDoneQueue);
      if (raw == null || raw.isEmpty) return const [];
      await HomeWidget.saveWidgetData<String>(_kDoneQueue, null);
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return const [];
    }
  }

  /// 위젯 체크를 표시 데이터에 반영: 체크 표시 + 남은 수·오늘 완료 수 갱신.
  /// 같은 항목을 두 번 누르면 아무것도 바꾸지 않는다.
  static Map<String, dynamic> markDone(Map<String, dynamic> data, String id) {
    final out = Map<String, dynamic>.from(data);
    var changed = false;

    // 오늘 위젯 목록
    final items = [for (final e in (data['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final hit = items.where((e) => e['id'] == id && e['done'] != true).toList();
    if (hit.isNotEmpty) {
      hit.first['done'] = true;
      out['items'] = items;
      if (hit.first['today'] == true) {
        out['remaining'] = (((data['remaining'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
      } else {
        out['ready'] = (((data['ready'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
      }
      changed = true;
    }

    // 계열 위젯: 그 줄에 체크 표시, 목표의 완료 수 +1
    final series = [for (final e in (data['series'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    for (final goal in series) {
      final rows = [for (final r in (goal['rows'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
      final row = rows.where((r) => r['id'] == id && r['t'] == 'a' && r['done'] != true).toList();
      if (row.isEmpty) continue;
      row.first['done'] = true;
      goal['rows'] = rows;
      goal['done'] = ((goal['done'] as num?)?.toInt() ?? 0) + 1;
      out['series'] = series;
      // 오늘 위젯 목록에 없던 ★ 항목이면 남은 수도 줄인다
      if (!changed && row.first['today'] == true) {
        out['remaining'] = (((data['remaining'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
      }
      changed = true;
      break;
    }
    if (!changed) return data;

    // 일정 위젯: 끝낸 마감은 뺀다
    out['agenda'] = [
      for (final e in (data['agenda'] as List? ?? const []))
        if ((e as Map)['id'] != id) e,
    ];
    out['doneToday'] = ((data['doneToday'] as num?)?.toInt() ?? 0) + 1;
    return out;
  }
}

/// 위젯 체크 버튼 → 백그라운드 isolate에서 실행.
/// 위젯에는 바로 체크 표시를 하고, 완료 큐에 넣어 두면 앱이 열릴 때 반영·동기화한다.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri == null || uri.host != 'done') return;
  final id = uri.queryParameters['id'];
  if (id == null) return;

  final rawQ = await HomeWidget.getWidgetData<String>(WidgetSync._kDoneQueue);
  final q = rawQ == null || rawQ.isEmpty ? <String>[] : List<String>.from(jsonDecode(rawQ) as List);
  if (!q.contains(id)) q.add(id);
  await HomeWidget.saveWidgetData<String>(WidgetSync._kDoneQueue, jsonEncode(q));

  final raw = await HomeWidget.getWidgetData<String>(WidgetSync._kData);
  if (raw != null) {
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    await HomeWidget.saveWidgetData<String>(WidgetSync._kData, jsonEncode(WidgetSync.markDone(data, id)));
  }
  await WidgetSync.updateAll();
}
