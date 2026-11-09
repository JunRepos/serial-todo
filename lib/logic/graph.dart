import '../models/item.dart';

/// prototype.html의 reindex/effDeps/blockers/sequenceOf 등을 옮긴 순수 계산 모음.
/// 삭제되지 않은 항목 목록으로 한 번 만들고, 데이터가 바뀌면 새로 만든다.
class Graph {
  Graph(Iterable<Item> all) {
    for (final i in all) {
      if (!i.deleted) byId[i.id] = i;
    }
    for (final i in byId.values) {
      final p = (i.parentId != null && byId.containsKey(i.parentId)) ? i.parentId! : _root;
      (_kids[p] ??= []).add(i);
    }
    for (final l in _kids.values) {
      l.sort((a, b) {
        final c = a.sort.compareTo(b.sort);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    }
    var n = 0;
    void walk(String? p) {
      for (final c in kids(p)) {
        treePos[c.id] = n++;
        walk(c.id);
      }
    }

    walk(null);
  }

  static const _root = '_';
  final Map<String, Item> byId = {};
  final Map<String, List<Item>> _kids = {};
  final Map<String, int> treePos = {};
  final Map<String, bool> _doneMemo = {};
  final Map<String, List<String>> _leavesMemo = {};

  Item? operator [](String id) => byId[id];

  List<Item> kids(String? id) => _kids[id ?? _root] ?? const [];
  List<Item> get goals => kids(null);

  String? parentOf(String id) {
    final p = byId[id]?.parentId;
    return (p != null && byId.containsKey(p)) ? p : null;
  }

  List<String> ancestors(String id) {
    final r = <String>[];
    var p = parentOf(id);
    while (p != null) {
      r.add(p);
      p = parentOf(p);
    }
    return r;
  }

  Item? goalOf(String id) {
    var it = byId[id];
    while (it != null && parentOf(it.id) != null) {
      it = byId[parentOf(it.id)];
    }
    return it;
  }

  List<String> descendants(String id) {
    final r = <String>[];
    void w(String x) {
      for (final c in kids(x)) {
        r.add(c.id);
        w(c.id);
      }
    }

    w(id);
    return r;
  }

  List<String> leaves(String id) => _leavesMemo[id] ??= () {
        final k = kids(id);
        if (k.isEmpty) return [id];
        return [for (final c in k) ...leaves(c.id)];
      }();

  bool isLeaf(String id) => kids(id).isEmpty;

  bool isDone(String id) => _doneMemo[id] ??= () {
        final k = kids(id);
        if (k.isEmpty) return byId[id]?.status == 'done';
        return k.every((c) => isDone(c.id));
      }();

  /// 명시한 deps + (부모가 seq이면 바로 위 형제)
  List<String> effDeps(String id) {
    final it = byId[id];
    if (it == null) return const [];
    final d = <String>{for (final x in it.deps) if (byId.containsKey(x) && x != id) x};
    final p = parentOf(id);
    if (p != null && byId[p]!.seq) {
      final sib = kids(p);
      final i = sib.indexWhere((s) => s.id == id);
      if (i > 0) d.add(sib[i - 1].id);
    }
    return d.toList();
  }

  /// 자기와 모든 상위의 유효 선행 중 미완료인 것
  List<String> blockers(String id) {
    final out = <String>{};
    for (final x in [id, ...ancestors(id)]) {
      for (final d in effDeps(x)) {
        if (!isDone(d)) out.add(d);
      }
    }
    return out.toList();
  }

  bool isBlocked(String id) => !isDone(id) && blockers(id).isNotEmpty;

  int progress(String id) {
    final l = leaves(id);
    if (l.length == 1 && l.first == id) return isDone(id) ? 100 : 0;
    final d = l.where(isDone).length;
    return (d / l.length * 100).round();
  }

  String path(String id) => ancestors(id).reversed.map((a) => byId[a]!.title).join(' › ');

  Sequence sequenceOf(String goalId) {
    final l = leaves(goalId);
    final set = l.toSet();
    final pre = <String, List<String>>{};
    for (final leaf in l) {
      final s = <String>{};
      for (final x in [leaf, ...ancestors(leaf)]) {
        if (x == goalId) continue;
        for (final d in effDeps(x)) {
          for (final dl in leaves(d)) {
            if (set.contains(dl) && dl != leaf) s.add(dl);
          }
        }
      }
      pre[leaf] = s.toList();
    }
    final stage = <String, int>{};
    final visiting = <String>{};
    final cyc = <String>{};
    int st(String x) {
      final known = stage[x];
      if (known != null) return known;
      if (visiting.contains(x)) {
        cyc.add(x);
        return 0;
      }
      visiting.add(x);
      var m = 0;
      for (final d in pre[x]!) {
        final v = st(d) + 1;
        if (v > m) m = v;
      }
      visiting.remove(x);
      stage[x] = m;
      return m;
    }

    l.forEach(st);
    final buckets = <int, List<String>>{};
    for (final leaf in l) {
      (buckets[stage[leaf]!] ??= []).add(leaf);
    }
    final keys = buckets.keys.toList()..sort();
    final stages = [
      for (final k in keys) buckets[k]!..sort((a, b) => treePos[a]!.compareTo(treePos[b]!)),
    ];
    return Sequence(stages, stage, cyc.toList());
  }

  Map<String, int> stageMap() {
    final m = <String, int>{};
    for (final g in goals) {
      m.addAll(sequenceOf(g.id).stage);
    }
    return m;
  }

  /// from에서 선행/하위 관계를 따라가 target에 닿는지 (순환 검사용)
  bool reaches(String from, String target) {
    final seen = <String>{};
    final st = [from];
    while (st.isNotEmpty) {
      final x = st.removeLast();
      if (x == target) return true;
      if (!seen.add(x)) continue;
      for (final y in [x, ...ancestors(x)]) {
        st.addAll(effDeps(y));
      }
      st.addAll(kids(x).map((c) => c.id));
    }
    return false;
  }

  /// 선행으로 고를 수 있는 후보. 목표는 다른 목표, 나머지는 같은 목표 안(자기·상위·하위 제외).
  List<Item> depCandidates(String id) {
    final it = byId[id]!;
    if (it.level == 0 || parentOf(id) == null) {
      return goals.where((g) => g.id != id).toList();
    }
    final g = goalOf(id)!;
    final ex = {id, g.id, ...ancestors(id), ...descendants(id)};
    final r = <Item>[];
    void w(String p) {
      for (final c in kids(p)) {
        if (!ex.contains(c.id)) r.add(c);
        w(c.id);
      }
    }

    w(g.id);
    return r;
  }

  /// 목표 간 순서 (목표 deps 기준)
  List<Item> orderedGoals() {
    final gs = <String, int>{};
    final vis = <String>{};
    int gst(String g) {
      final k = gs[g];
      if (k != null) return k;
      if (!vis.add(g)) return 0;
      var m = 0;
      for (final d in effDeps(g)) {
        final v = gst(d) + 1;
        if (v > m) m = v;
      }
      gs[g] = m;
      return m;
    }

    final list = goals.toList();
    list.sort((a, b) {
      final c = gst(a.id).compareTo(gst(b.id));
      return c != 0 ? c : a.sort.compareTo(b.sort);
    });
    return list;
  }

  bool get hasGoalDeps => goals.any((g) => effDeps(g.id).isNotEmpty);

  TodayLists todayLists({DateTime? now}) {
    final t = now ?? DateTime.now();
    final sm = stageMap();
    final today = <Item>[], ready = <Item>[], wait = <Item>[], recent = <Item>[];
    for (final i in byId.values) {
      if (!isLeaf(i.id)) continue;
      if (i.status == 'done') {
        if (i.doneAt != null && t.difference(i.doneAt!.toLocal()).inDays < 7) recent.add(i);
        continue;
      }
      if (i.today) {
        today.add(i);
      } else if (blockers(i.id).isNotEmpty) {
        wait.add(i);
      } else {
        ready.add(i);
      }
    }
    int cmp(Item a, Item b) {
      final da = a.status == 'doing' ? 0 : 1, db = b.status == 'doing' ? 0 : 1;
      if (da != db) return da - db;
      if (a.priority != b.priority) return a.priority - b.priority;
      final x = dday(a.due, now: t) ?? 1 << 30, y = dday(b.due, now: t) ?? 1 << 30;
      if (x != y) return x - y;
      final s = (sm[a.id] ?? 0) - (sm[b.id] ?? 0);
      if (s != 0) return s;
      return treePos[a.id]! - treePos[b.id]!;
    }

    today.sort(cmp);
    ready.sort(cmp);
    wait.sort((a, b) => treePos[a.id]! - treePos[b.id]!);
    recent.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return TodayLists(today, ready, wait, recent);
  }

  /// 트리 순서로 정렬된 전체 항목
  List<Item> get inTreeOrder {
    final l = byId.values.toList();
    l.sort((a, b) => treePos[a.id]!.compareTo(treePos[b.id]!));
    return l;
  }
}

class Sequence {
  Sequence(this.stages, this.stage, this.cyc);
  final List<List<String>> stages;
  final Map<String, int> stage;
  final List<String> cyc;
}

class TodayLists {
  TodayLists(this.today, this.ready, this.wait, this.recent);
  final List<Item> today, ready, wait, recent;
}

/// 마감까지 남은 날 수. 오늘=0, 지남=음수.
int? dday(String? due, {DateTime? now}) {
  if (due == null || due.isEmpty) return null;
  final d = DateTime.tryParse(due);
  if (d == null) return null;
  final t = now ?? DateTime.now();
  return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
}

String? ddayLabel(int? n) {
  if (n == null) return null;
  if (n < 0) return '${-n}일 지남';
  if (n == 0) return 'D-day';
  return 'D-$n';
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
