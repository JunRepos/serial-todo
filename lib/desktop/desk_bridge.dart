import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/graph.dart';
import '../models/item.dart';

/// 윈도우 바탕화면 위젯의 네이티브 기능(창 이동·크기 조절·숨기기 등).
class DeskNative {
  static const _ch = MethodChannel('serialtodo/desk');
  static final locked = ValueNotifier<bool>(false);

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'locked') locked.value = call.arguments == true;
    });
    _ch.invokeMethod<bool>('isLocked').then((v) => locked.value = v ?? false, onError: (_) {});
  }

  static Future<void> _call(String m, [Object? a]) async {
    try {
      await _ch.invokeMethod(m, a);
    } on MissingPluginException {
      // 테스트 등 네이티브가 없는 환경
    }
  }

  static Future<void> startDrag() => _call('startDrag');
  static Future<void> startResize() => _call('startResize');
  static Future<void> hide() => _call('hide');
  static Future<void> show(String id) => _call('show', id);
  static Future<void> openWeb() => _call('openWeb');
  static Future<void> activate() => _call('activate');
}

/// 두 위젯 창(엔진) 사이의 메시지. 네이티브가 반대쪽 창으로 그대로 전달한다.
class DeskRelay {
  static const _ch = BasicMessageChannel<String>('serialtodo/relay', StringCodec());

  static void listen(void Function(Map<String, dynamic> msg) onMessage) {
    _ch.setMessageHandler((s) async {
      if (s != null) onMessage(jsonDecode(s) as Map<String, dynamic>);
      return '';
    });
  }

  static void send(Map<String, dynamic> msg) {
    _ch.send(jsonEncode(msg)).ignore();
  }
}

enum DeskSync { synced, syncing, offline, error }

/// 위젯 화면이 쓰는 데이터. 캘린더 창은 저장소에서 바로, 할 일 창은 중계로 받는다.
abstract class DeskData extends ChangeNotifier {
  Graph get graph;
  bool get signedIn;

  /// 첫 데이터가 도착했는지
  bool get ready;
  DeskSync get sync;
  int get pending;

  void toggleDone(String id);
  void toggleToday(String id);
  void add(String title, {String? due, bool today = false});
  void refresh();
}

/// 할 일 창: 캘린더 창이 보내 주는 스냅숏으로 그리고, 조작은 캘린더 창에 맡긴다.
class RelayData extends DeskData {
  RelayData() {
    DeskRelay.listen(_onMessage);
    _hello();
  }

  Graph _graph = Graph(const []);
  bool _signedIn = false, _ready = false;
  DeskSync _sync = DeskSync.syncing;
  int _pending = 0;

  @override
  Graph get graph => _graph;
  @override
  bool get signedIn => _signedIn;
  @override
  bool get ready => _ready;
  @override
  DeskSync get sync => _sync;
  @override
  int get pending => _pending;

  /// 캘린더 창이 먼저 떠 있지 않을 수 있어 첫 스냅숏을 받을 때까지 다시 묻는다.
  void _hello() {
    if (_ready) return;
    DeskRelay.send({'t': 'hello'});
    Future.delayed(const Duration(seconds: 2), _hello);
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['t'] != 'snap') return;
    _ready = true;
    _signedIn = m['signedIn'] == true;
    _sync = DeskSync.values.byName(m['sync'] as String? ?? 'synced');
    _pending = m['pending'] as int? ?? 0;
    final items = (m['items'] as List? ?? const [])
        .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _graph = Graph(items);
    notifyListeners();
  }

  void _act(String op, Map<String, dynamic> args) => DeskRelay.send({'t': 'act', 'op': op, ...args});

  @override
  void toggleDone(String id) {
    // 바로 반영해 보이고, 캘린더 창의 다음 스냅숏으로 확정된다.
    final it = _graph[id];
    if (it != null) {
      it.status = it.status == 'done' ? 'todo' : 'done';
      it.doneAt = it.status == 'done' ? DateTime.now().toUtc() : null;
      _graph = Graph(_graph.byId.values);
      notifyListeners();
    }
    _act('toggleDone', {'id': id});
  }

  @override
  void toggleToday(String id) {
    final it = _graph[id];
    if (it != null) {
      it.today = !it.today;
      _graph = Graph(_graph.byId.values);
      notifyListeners();
    }
    _act('toggleToday', {'id': id});
  }

  @override
  void add(String title, {String? due, bool today = false}) =>
      _act('add', {'title': title, 'due': due, 'today': today});

  @override
  void refresh() => _act('refresh', const {});
}
