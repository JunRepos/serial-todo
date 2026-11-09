import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../logic/graph.dart';

/// 안드로이드 홈 화면 위젯과 데이터 주고받기.
class WidgetSync {
  static const androidName = 'TodayWidgetProvider';
  static const _kData = 'widget_json';
  static const _kDoneQueue = 'widget_done_queue';

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

  static Map<String, dynamic> buildData(Graph g) {
    final lists = g.todayLists();
    final useToday = lists.today.isNotEmpty;
    final src = useToday ? lists.today : lists.ready;
    return {
      'title': useToday ? '오늘' : '바로 할 수 있음',
      'count': src.length,
      'items': [
        for (final it in src.take(5))
          {'id': it.id, 'title': it.title, 'due': ddayLabel(dday(it.due)) ?? '', 'over': (dday(it.due) ?? 0) < 0},
      ],
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

  /// 위젯 탭으로 앱이 열렸을 때 편집할 항목 id
  static String? itemIdFromUri(Uri? uri) {
    if (uri == null || uri.host != 'open') return null;
    return uri.queryParameters['id'];
  }
}

/// 위젯 체크 버튼 → 백그라운드 isolate에서 실행.
/// 위젯 표시에서 바로 빼고, 완료 큐에 넣어 두면 앱이 열릴 때 반영·동기화한다.
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
    final items = List<Map>.from(data['items'] as List);
    final before = items.length;
    items.removeWhere((e) => e['id'] == id);
    if (items.length != before) {
      data['items'] = items;
      data['count'] = ((data['count'] as num?)?.toInt() ?? 1) - 1;
      await HomeWidget.saveWidgetData<String>(WidgetSync._kData, jsonEncode(data));
    }
  }
  await HomeWidget.updateWidget(androidName: WidgetSync.androidName);
}
