import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logic/graph.dart';
import '../models/item.dart';

/// 일정 알림.
/// - 안드로이드: 앱이 꺼져 있어도 울리도록 시스템에 예약한다. 일정이 바뀔 때마다 전부 다시 예약.
/// - 윈도우 위젯·웹: 앱이 떠 있는 동안 시각이 되면 알린다(윈도우는 시스템 알림, 웹은 화면 위 알림).
class NotifSync {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Timer? _debounce, _ticker;
  static DateTime _lastTick = DateTime.now();

  /// 앱이 꺼져 있어도 알림을 예약할 수 있는 플랫폼
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 한 번에 예약하는 최대 개수와 기간
  static const maxScheduled = 40, horizonDays = 60;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'events',
      '일정 알림',
      channelDescription: '일정 시작 전에 알려 줍니다',
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready || !(supported || _windows)) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: '할일이많아',
            appUserModelId: 'io.github.junrepos.serial_todo',
            guid: '5f0b3b1e-7a52-4c1b-9a53-3e8f1d2c6a40',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notification init failed: $e');
    }
  }

  /// 알림 권한 묻기 (안드로이드 13+). 알림을 처음 켤 때 부른다.
  static Future<void> askPermission() async {
    if (!supported) return;
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('notification permission failed: $e');
    }
  }

  /// 알림이 걸려 있고 아직 울리지 않은 일정들 (이른 순)
  static List<Item> upcoming(Graph g, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final limit = t.add(const Duration(days: horizonDays));
    final list = [
      for (final e in g.events.values)
        if (e.remindAt case final at? when at.isAfter(t) && at.isBefore(limit)) e,
    ]..sort((a, b) => a.remindAt!.compareTo(b.remindAt!));
    return list.take(maxScheduled).toList();
  }

  static String body(Item e) => e.eventSummary;

  /// 데이터가 바뀔 때마다 호출. 짧게 모아서 다시 예약한다.
  static void schedule(Graph g) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => _reschedule(g));
  }

  static Future<void> _reschedule(Graph g) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final e in upcoming(g)) {
        await _plugin.zonedSchedule(
          id: e.id.hashCode & 0x7fffffff,
          title: e.title,
          body: body(e),
          // 절대 시각으로 넘기므로 기기 시간대 이름을 몰라도 된다
          scheduledDate: tz.TZDateTime.from(e.remindAt!, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: e.id,
        );
      }
    } catch (e) {
      debugPrint('notification schedule failed: $e');
    }
  }

  /// 예약을 못 하는 플랫폼(윈도우·웹): 앱이 떠 있는 동안 시각이 지난 알림을 찾아 알린다.
  /// [onFire]는 화면 안 알림을 띄우는 콜백(웹). 윈도우는 시스템 알림도 함께 보낸다.
  static void watch(Graph Function() graph, {void Function(Item e)? onFire}) {
    if (supported) return;
    _ticker?.cancel();
    _lastTick = DateTime.now();
    if (_windows) init();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = DateTime.now();
      for (final e in due(graph(), _lastTick, now)) {
        onFire?.call(e);
        if (_windows && _ready) {
          _plugin
              .show(id: e.id.hashCode & 0x7fffffff, title: e.title, body: body(e), notificationDetails: _details)
              .catchError((Object err) => debugPrint('notification failed: $err'));
        }
      }
      _lastTick = now;
    });
  }

  /// (from, to] 사이에 알림 시각이 든 일정
  static List<Item> due(Graph g, DateTime from, DateTime to) => [
    for (final e in g.events.values)
      if (e.remindAt case final at? when at.isAfter(from) && !at.isAfter(to)) e,
  ];

  static void stop() {
    _ticker?.cancel();
    _ticker = null;
  }
}
