import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../logic/graph.dart';
import '../logic/outline.dart';
import '../models/item.dart';

enum SyncState { synced, syncing, offline, error }

const _uuid = Uuid();
String newId() => _uuid.v4();

/// 로컬 캐시 + 미전송 큐 + Supabase upsert/pull + Realtime.
/// 모든 변경은 즉시 메모리 → 캐시 → 서버 순으로 반영한다.
class Repository extends ChangeNotifier {
  Repository(this._prefs, this._client);

  final SharedPreferences _prefs;
  final SupabaseClient _client;

  final Map<String, Item> _items = {};
  final Set<String> _pending = {};
  Graph graph = Graph(const []);
  String? _uid;
  String? _cursor; // 서버 synced_at 기준 마지막으로 받은 시각
  RealtimeChannel? _channel;
  StreamSubscription? _connSub;
  Timer? _pushTimer, _retryTimer;
  bool _pushing = false;
  bool _pulledOnce = false;

  SyncState sync = SyncState.syncing;
  int get pendingCount => _pending.length;

  /// 데이터가 바뀔 때마다 호출 (위젯 갱신 등)
  void Function(Graph g)? onGraphChanged;

  String get _kItems => 'items_v1_$_uid';
  String get _kPending => 'pending_v1_$_uid';
  String get _kCursor => 'cursor_v1_$_uid';
  String get _kSeeded => 'seeded_v1_$_uid';

  // ---------------------------------------------------------------- 시작/종료

  Future<void> start(String uid) async {
    if (_uid == uid) return;
    _uid = uid; // await 전에 먼저 표시해 중복 시작을 막는다
    await _teardown();
    if (_uid != uid) return;
    _items.clear();
    _pending.clear();
    _pulledOnce = false;
    final raw = _prefs.getString(_kItems);
    if (raw != null) {
      for (final j in (jsonDecode(raw) as List)) {
        final it = Item.fromJson(Map<String, dynamic>.from(j as Map));
        _items[it.id] = it;
      }
    }
    _pending.addAll(_prefs.getStringList(_kPending) ?? const []);
    _cursor = _prefs.getString(_kCursor);
    _rebuild(save: false);

    _subscribe();
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) refresh();
    });
    unawaited(refresh());
  }

  Future<void> stop() async {
    _uid = null;
    await _teardown();
  }

  /// 계정 삭제 후: 이 기기에 남은 그 계정의 캐시·대기열을 지운다.
  Future<void> forgetLocal() async {
    final uid = _uid;
    await stop();
    if (uid == null) return;
    for (final k in ['items_v1_$uid', 'pending_v1_$uid', 'cursor_v1_$uid', 'seeded_v1_$uid']) {
      await _prefs.remove(k);
    }
    _items.clear();
    _pending.clear();
    graph = Graph(const []);
    notifyListeners();
  }

  Future<void> _teardown() async {
    _pushTimer?.cancel();
    _retryTimer?.cancel();
    await _connSub?.cancel();
    _connSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await _client.removeChannel(ch);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// 서버 변경분 받기 + 큐 전송
  Future<void> refresh() async {
    if (_uid == null) return;
    await _pull();
    await _push();
  }

  // ---------------------------------------------------------------- 서버

  void _subscribe() {
    final uid = _uid!;
    _channel = _client
        .channel('items-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'items',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) {
            final rec = p.newRecord;
            if (rec.isEmpty) return;
            if (_mergeRemote([rec])) _rebuild(push: false);
          },
        )
        .subscribe((status, [err]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            // 끊겼다 다시 붙으면 그 사이 변경분을 받는다
            if (_pulledOnce) unawaited(refresh());
          }
        });
  }

  Future<void> _pull() async {
    try {
      // 다른 기기의 시계와 무관하게, 서버가 찍은 synced_at 으로 변경분을 가져온다
      final since = _cursor == null
          ? null
          : DateTime.parse(_cursor!).subtract(const Duration(seconds: 10)).toUtc().toIso8601String();
      const page = 1000;
      var changed = false;
      for (var from = 0; ; from += page) {
        var q = _client.from('items').select();
        if (since != null) q = q.gt('synced_at', since);
        final rows = await q.order('synced_at').order('id').range(from, from + page - 1);
        if (_mergeRemote(List<Map<String, dynamic>>.from(rows))) changed = true;
        if (rows.length < page) break;
      }
      _pulledOnce = true;
      if (_pending.isEmpty) sync = SyncState.synced;
      if (!_seededLocally()) {
        _seedSample();
      } else if (changed) {
        _rebuild(push: false);
      } else {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('pull failed: $e');
      _markOffline();
    }
  }

  bool _seededLocally() {
    if (_prefs.getBool(_kSeeded) == true) return true;
    if (_items.isNotEmpty) {
      _prefs.setBool(_kSeeded, true);
      return true;
    }
    return false;
  }

  /// 원격 행을 LWW로 합친다. 바뀐 게 있으면 true.
  bool _mergeRemote(List<Map<String, dynamic>> rows) {
    var changed = false;
    for (final r in rows) {
      final s = r['synced_at']?.toString();
      if (s != null && (_cursor == null || s.compareTo(_cursor!) > 0)) _cursor = s;
      final remote = Item.fromJson(r);
      final local = _items[remote.id];
      if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
        if (remote.updatedAt.isAtSameMomentAs(local.updatedAt)) _pending.remove(remote.id);
        continue;
      }
      _items[remote.id] = remote;
      _pending.remove(remote.id);
      changed = true;
    }
    if (_cursor != null) _prefs.setString(_kCursor, _cursor!);
    return changed;
  }

  void _schedulePush([Duration d = const Duration(milliseconds: 400)]) {
    _pushTimer?.cancel();
    _pushTimer = Timer(d, _push);
  }

  Future<void> _push() async {
    if (_pushing || _uid == null) return;
    if (_pending.isEmpty) {
      if (_pulledOnce && sync != SyncState.synced) {
        sync = SyncState.synced;
        notifyListeners();
      }
      return;
    }
    _pushing = true;
    sync = SyncState.syncing;
    notifyListeners();
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.take(200).toList();
        final sent = <String, DateTime>{};
        final rows = <Map<String, dynamic>>[];
        for (final id in batch) {
          final it = _items[id];
          if (it == null) {
            _pending.remove(id);
            continue;
          }
          sent[id] = it.updatedAt;
          rows.add({...it.toJson(), 'user_id': _uid});
        }
        if (rows.isNotEmpty) await _client.from('items').upsert(rows, onConflict: 'id');
        sent.forEach((id, at) {
          if (_items[id]?.updatedAt == at) _pending.remove(id);
        });
        _savePending();
      }
      sync = SyncState.synced;
      _retryTimer?.cancel();
    } catch (e) {
      debugPrint('push failed: $e');
      _markOffline();
    } finally {
      _pushing = false;
      notifyListeners();
    }
  }

  void _markOffline() {
    sync = SyncState.offline;
    notifyListeners();
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 20), refresh);
  }

  // ---------------------------------------------------------------- 로컬 반영

  void _savePending() => _prefs.setStringList(_kPending, _pending.toList());

  // 앱이 바로 꺼져도 잃지 않도록 즉시 저장한다
  void _saveCache() => _prefs.setString(_kItems, jsonEncode(_items.values.map((e) => e.toJson()).toList()));

  void _rebuild({bool save = true, bool push = true}) {
    graph = Graph(_items.values);
    if (save) _saveCache();
    _savePending();
    notifyListeners();
    onGraphChanged?.call(graph);
    if (push && _pending.isNotEmpty) _schedulePush();
  }

  /// 바뀐 항목들을 표시하고 저장·전송한다.
  void _commit(Iterable<Item> changed) {
    for (final it in changed) {
      it.touch();
      _items[it.id] = it;
      _pending.add(it.id);
    }
    _rebuild();
  }

  Item? operator [](String id) => graph[id];

  /// 네트워크 없이 항목만 채운다 (위젯 테스트용)
  @visibleForTesting
  void debugLoad(String uid, List<Item> items) {
    _uid = uid;
    _items
      ..clear()
      ..addAll({for (final i in items) i.id: i});
    sync = SyncState.synced;
    graph = Graph(_items.values);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 변경 API

  Item? add(String? parentId, String title, {String? due, bool today = false}) {
    title = title.trim();
    if (title.isEmpty) return null;
    final p = parentId == null ? null : graph[parentId];
    final sib = graph.kids(parentId);
    final it = Item(
      id: newId(),
      parentId: p?.id,
      level: p == null ? 0 : (p.level + 1).clamp(0, 2),
      sort: sib.isEmpty ? 1 : sib.last.sort + 1,
      title: title,
      due: due,
      today: today,
    );
    // 상위 항목에 하위가 처음 생기면 그 상위의 상태는 의미가 없어지므로 정리
    final changed = [it];
    if (p != null && sib.isEmpty && p.status != 'todo') {
      p.status = 'todo';
      p.doneAt = null;
      changed.add(p);
    }
    _commit(changed);
    return it;
  }

  /// 여러 줄 붙여넣기 결과를 parentId 아래에 생성. 만든 항목 반환.
  List<Item> addOutline(String? parentId, List<OutlineNode> nodes) {
    final parent = parentId == null ? null : graph[parentId];
    if (parent != null && parent.level >= 2) return const [];
    final created = <Item>[];
    final nextSort = <String?, double>{};
    final sib = graph.kids(parentId);
    nextSort[parentId] = sib.isEmpty ? 1 : sib.last.sort + 1;

    Item make(Item? p, String title) {
      final key = p?.id;
      final s = nextSort[key] ?? 1;
      nextSort[key] = s + 1;
      final it = Item(id: newId(), parentId: key, level: p == null ? 0 : p.level + 1, sort: s, title: title);
      created.add(it);
      return it;
    }

    void flat(Item p, OutlineNode n) {
      // 액션 아래로는 내려갈 수 없으므로 더 깊은 줄은 액션 형제로 펼친다
      make(p, n.title);
      for (final c in n.children) {
        flat(p, c);
      }
    }

    void walk(Item? p, List<OutlineNode> ns) {
      for (final n in ns) {
        final level = p == null ? 0 : p.level + 1;
        if (level >= 2) {
          flat(p!, n);
        } else {
          walk(make(p, n.title), n.children);
        }
      }
    }

    walk(parent, nodes);
    if (created.isEmpty) return const [];
    if (parent != null && sib.isEmpty && parent.status != 'todo') {
      parent.status = 'todo';
      parent.doneAt = null;
      created.add(parent);
    }
    final made = created.where((e) => e.id != parent?.id).toList();
    _commit(created);
    return made;
  }

  void update(String id, void Function(Item it) fn) {
    final it = _items[id];
    if (it == null) return;
    fn(it);
    _commit([it]);
  }

  void setStatus(String id, String s) => update(id, (it) => _applyStatus(it, s));

  void _applyStatus(Item it, String s) {
    it.status = s;
    if (s == 'done') {
      it.doneAt = DateTime.now().toUtc();
      it.today = false;
    } else {
      it.doneAt = null;
    }
  }

  void toggleDone(String id) {
    final it = graph[id];
    if (it == null) return;
    setStatus(id, it.status == 'done' ? 'todo' : 'done');
  }

  void toggleToday(String id) => update(id, (it) => it.today = !it.today);

  void setDue(String id, String? due) => update(id, (it) => it.due = due);

  void move(String id, int dir) {
    final it = graph[id];
    if (it == null) return;
    final sib = graph.kids(it.parentId);
    final i = sib.indexWhere((s) => s.id == id), j = i + dir;
    if (i < 0 || j < 0 || j >= sib.length) return;
    final other = sib[j];
    final o = other.sort;
    other.sort = it.sort;
    it.sort = o;
    if (other.sort == it.sort) it.sort += dir;
    _commit([it, other]);
  }

  /// 하위 전체 소프트 삭제 + 다른 항목 deps에서 제거. 되돌리기용 스냅샷 반환.
  List<Item> remove(String id) {
    final gone = {id, ...graph.descendants(id)};
    final snapshot = <Item>[];
    final changed = <Item>[];
    for (final it in _items.values) {
      if (it.deleted) continue;
      if (gone.contains(it.id)) {
        snapshot.add(it.copy());
        it.deleted = true;
        changed.add(it);
      } else if (it.deps.any(gone.contains)) {
        snapshot.add(it.copy());
        it.deps = it.deps.where((d) => !gone.contains(d)).toList();
        changed.add(it);
      }
    }
    _commit(changed);
    return snapshot;
  }

  void restore(List<Item> snapshot) => _commit(snapshot.map((e) => e.copy()));

  /// 위젯에서 체크한 항목 반영
  void applyExternalDone(Iterable<String> ids) {
    final changed = <Item>[];
    for (final id in ids) {
      final it = _items[id];
      if (it == null || it.deleted || it.status == 'done') continue;
      _applyStatus(it, 'done');
      changed.add(it);
    }
    if (changed.isNotEmpty) _commit(changed);
  }

  // ---------------------------------------------------------------- 예시 데이터

  void _seedSample() {
    _prefs.setBool(_kSeeded, true);
    final g = Item(id: newId(), title: '신제품 기획서 작성', priority: 1, note: '예시 목표입니다. 필요 없으면 편집 → 삭제.', sort: 1);
    Item mk(Item parent, String title, double sort, {bool seq = false, List<String>? deps, bool today = false}) => Item(
      id: newId(),
      parentId: parent.id,
      level: parent.level + 1,
      sort: sort,
      title: title,
      seq: seq,
      deps: deps,
      today: today,
    );
    final p1 = mk(g, '시장 조사 및 경쟁사 분석', 1);
    final a1 = mk(p1, '경쟁사 A사 홈페이지 분석 및 캡처', 1, today: true);
    final a2 = mk(p1, '경쟁사 B사 제품 가격표 정리', 2);
    final a3 = mk(p1, '경쟁사 비교표 초안 작성', 3, deps: [a1.id, a2.id]);
    final p2 = mk(g, '기획서 초안 작성', 2, seq: true, deps: [p1.id]);
    final a4 = mk(p2, '목차 구성', 1);
    final a5 = mk(p2, '핵심 기능 3가지 정리', 2);
    final a6 = mk(p2, '본문 초안 작성', 3);
    final p3 = mk(g, '검토 및 제출', 3, seq: true, deps: [p2.id]);
    final a7 = mk(p3, '팀장 검토 요청', 1);
    final a8 = mk(p3, '피드백 반영 후 제출', 2);
    _commit([g, p1, a1, a2, a3, p2, a4, a5, a6, p3, a7, a8]);
  }
}
