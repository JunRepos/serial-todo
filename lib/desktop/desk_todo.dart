import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import '../ui/common.dart';

import '../ui/theme.dart';
import 'desk_bridge.dart';
import 'desk_calendar.dart';
import 'desk_frame.dart';
import 'desk_main.dart';

/// 바탕화면 할 일 목록: ★오늘 · 바로 할 수 있음 · 계열(목표별로 접고 펴기) · 오늘 끝냄
class DeskTodo extends StatefulWidget {
  const DeskTodo({super.key});

  @override
  State<DeskTodo> createState() => _DeskTodoState();
}

class _DeskTodoState extends State<DeskTodo> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  bool _showDone = false;

  /// 펼쳐 둔 것들: 목표 id, 접은 프로젝트는 '-id', 접은 구역은 '#이름'
  static const _kOpen = 'desk_todo_open';
  final _open = <String>{};
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      final saved = p.getStringList(_kOpen);
      if (saved != null && mounted) setState(() => _open.addAll(saved));
    }, onError: (_) {});
  }

  void _flip(String key) {
    setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));
    _prefs?.setStringList(_kOpen, _open.toList());
  }

  /// 목표 하나를 펼친 내용: 프로젝트는 접을 수 있는 소제목, 액션은 들여쓴 줄
  List<Widget> _series(Graph g, Item goal) {
    final out = <Widget>[];
    void walk(String parent, int depth) {
      for (final it in g.kids(parent)) {
        final pad = EdgeInsets.only(left: 6.0 + depth * 14, right: 6);
        if (g.isLeaf(it.id)) {
          out.add(
            Padding(
              padding: pad,
              child: DeskItemRow(it: it, graph: g, showPath: false),
            ),
          );
          continue;
        }
        final shut = _open.contains('-${it.id}');
        final l = g.leaves(it.id);
        out.add(
          Padding(
            padding: pad,
            child: _GroupHeader(
              title: it.title,
              count: '${l.where(g.isDone).length}/${l.length}',
              open: !shut,
              done: g.isDone(it.id),
              blocked: g.isBlocked(it.id),
              onTap: () => _flip('-${it.id}'),
            ),
          ),
        );
        if (!shut) walk(it.id, depth + 1);
      }
    }

    walk(goal.id, 1);
    return out;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    DeskScope.of(context).add(t, today: true);
    _c.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final data = DeskScope.of(context);
    final now = DateTime.now();
    final date = DateFormat('M월 d일 EEEE', 'ko').format(now);

    if (!data.ready) {
      return DeskFrame(
        title: const Text('오늘 할 일'),
        subtitle: Text(date),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!data.signedIn) {
      return DeskFrame(
        title: const Text('오늘 할 일'),
        subtitle: Text(date),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('로그인하면 할 일이 여기 보여요.', style: TextStyle(color: Tone.muted(context))),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => DeskNative.show('calendar'), child: const Text('캘린더 창에서 로그인')),
              ],
            ),
          ),
        ),
      );
    }

    final g = data.graph;
    final lists = g.todayLists();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final doneToday = lists.recent.where((e) {
      final d = e.doneAt?.toLocal();
      return d != null && DateFormat('yyyy-MM-dd').format(d) == todayKey;
    }).toList();
    final remaining = lists.today.length;
    final total = remaining + doneToday.where((e) => e.today).length;
    final progress = total == 0 ? 0.0 : (total - remaining) / total;
    final scheme = Theme.of(context).colorScheme;

    Widget section(String label, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(
        '$label  $count',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.muted(context)),
      ),
    );

    Widget foldable(String label, int count, bool open, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: section(label, count)),
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8),
            child: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: Tone.muted(context)),
          ),
        ],
      ),
    );

    // 계열: 하위가 있고 아직 끝나지 않은 목표
    final series = [
      for (final goal in g.orderedGoals())
        if (!g.isLeaf(goal.id) && !g.isDone(goal.id)) goal,
    ];

    return DeskFrame(
      title: const Text('오늘 할 일'),
      subtitle: Text(remaining == 0 ? date : '$date · $remaining개 남음'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                section('★ 오늘', lists.today.length),
                if (lists.today.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      '아래 목록의 ☆를 눌러 오늘 할 일을 골라 보세요.',
                      style: TextStyle(fontSize: 12.5, color: Tone.muted(context)),
                    ),
                  ),
                for (final it in lists.today) _row(DeskItemRow(it: it, graph: g)),
                if (lists.ready.isNotEmpty) ...[
                  foldable('바로 할 수 있음', lists.ready.length, !_open.contains('#ready'), () => _flip('#ready')),
                  if (!_open.contains('#ready'))
                    for (final it in lists.ready.take(30)) _row(DeskItemRow(it: it, graph: g)),
                ],
                if (series.isNotEmpty) ...[
                  section('계열', series.length),
                  for (final goal in series) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _GroupHeader(
                        title: goal.title,
                        count: '${g.leaves(goal.id).where(g.isDone).length}/${g.leaves(goal.id).length}',
                        open: _open.contains(goal.id),
                        done: false,
                        blocked: g.isBlocked(goal.id),
                        goal: true,
                        onTap: () => _flip(goal.id),
                      ),
                    ),
                    if (_open.contains(goal.id)) ..._series(g, goal),
                  ],
                ],
                if (doneToday.isNotEmpty) ...[
                  foldable('오늘 끝냄', doneToday.length, _showDone, () => setState(() => _showDone = !_showDone)),
                  if (_showDone)
                    for (final it in doneToday) _row(DeskItemRow(it: it, graph: g)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    onTap: DeskNative.activate,
                    decoration: const InputDecoration(hintText: '오늘 할 일 추가', isDense: true),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) =>
                      FilledButton(onPressed: _c.text.trim().isEmpty ? null : _submit, child: const Text('추가')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child);
}

/// 계열(목표)·프로젝트 제목 줄. 누르면 접고 편다.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.open,
    required this.done,
    required this.blocked,
    required this.onTap,
    this.goal = false,
  });
  final String title, count;
  final bool open, done, blocked;
  final VoidCallback onTap;

  /// 목표 줄은 조금 더 크게
  final bool goal;

  @override
  Widget build(BuildContext context) {
    final muted = Tone.muted(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: goal ? 7 : 5),
        child: Row(
          children: [
            SizedBox(width: 40, child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20, color: muted)),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: goal ? 14 : 13,
                  fontWeight: goal ? FontWeight.w700 : FontWeight.w600,
                  color: done ? muted : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (blocked && !done)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Badge2('대기', color: Tone.warn(context)),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 10),
              child: Text(count, style: TextStyle(fontSize: 11.5, color: muted)),
            ),
          ],
        ),
      ),
    );
  }
}
