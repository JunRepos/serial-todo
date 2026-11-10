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
      'v': 2,
      'remaining': lists.today.length,
      'ready': lists.ready.length,
      'doneToday': doneToday,
      'items': items,
    };
  }

  static Future<void> push(Graph g) async {
    if (!supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(_kData, jsonEncode(buildData(g)));
      await HomeWidget.updateWidget(androidName: androidName);
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
    final items = [for (final e in (data['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final hit = items.where((e) => e['id'] == id && e['done'] != true).toList();
    if (hit.isEmpty) return data;
    hit.first['done'] = true;
    final out = Map<String, dynamic>.from(data)..['items'] = items;
    if (hit.first['today'] == true) {
      out['remaining'] = (((data['remaining'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
    } else {
      out['ready'] = (((data['ready'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
    }
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
  await HomeWidget.updateWidget(androidName: WidgetSync.androidName);
}
