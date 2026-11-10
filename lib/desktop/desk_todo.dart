import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/theme.dart';
import 'desk_bridge.dart';
import 'desk_calendar.dart';
import 'desk_frame.dart';
import 'desk_main.dart';

/// 바탕화면 할 일 목록: ★오늘 · 바로 할 수 있음 · 최근 완료
class DeskTodo extends StatefulWidget {
  const DeskTodo({super.key});

  @override
  State<DeskTodo> createState() => _DeskTodoState();
}

class _DeskTodoState extends State<DeskTodo> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  bool _showDone = false;

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
                  section('바로 할 수 있음', lists.ready.length),
                  for (final it in lists.ready.take(30)) _row(DeskItemRow(it: it, graph: g)),
                ],
                if (doneToday.isNotEmpty) ...[
                  InkWell(
                    onTap: () => setState(() => _showDone = !_showDone),
                    child: Row(
                      children: [
                        Expanded(child: section('오늘 끝냄', doneToday.length)),
                        Padding(
                          padding: const EdgeInsets.only(right: 12, top: 8),
                          child: Icon(_showDone ? Icons.expand_less : Icons.expand_more, size: 18),
                        ),
                      ],
                    ),
                  ),
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
