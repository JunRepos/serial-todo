import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import '../models/item.dart';
import 'app_scope.dart';
import 'common.dart';
import 'item_sheet.dart';
import 'quick_add.dart';
import 'theme.dart';

class TreePage extends StatefulWidget {
  const TreePage({super.key});

  @override
  State<TreePage> createState() => TreePageState();
}

class TreePageState extends State<TreePage> {
  static const _kCollapsed = 'ui_collapsed';
  Set<String> _collapsed = {};
  String? _addingTo;
  bool _addingGoal = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _collapsed = (AppScope.prefsOf(context).getStringList(_kCollapsed) ?? const []).toSet();
    }
  }

  /// FAB: 새 목표 입력창 열기
  void startGoal() => setState(() {
    _addingGoal = true;
    _addingTo = null;
  });

  void _toggle(String id) {
    setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id));
    AppScope.prefsOf(context).setStringList(_kCollapsed, _collapsed.toList());
  }

  void _startAdd(String id) => setState(() {
    _addingTo = id;
    _addingGoal = false;
    if (_collapsed.remove(id)) AppScope.prefsOf(context).setStringList(_kCollapsed, _collapsed.toList());
  });

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.watch(context);
    final g = repo.graph;
    final rows = <Widget>[];

    if (_addingGoal || g.goals.isEmpty) {
      rows.add(
        QuickAddField(
          key: const ValueKey('add-goal'),
          parentId: null,
          hint: '새 목표 · 여러 줄 붙여넣기 가능',
          autofocus: _addingGoal,
          onClose: g.goals.isEmpty ? null : () => setState(() => _addingGoal = false),
        ),
      );
    }
    if (g.goals.isEmpty) {
      rows.add(const EmptyHint('목표를 하나 입력해 시작하세요.'));
    }

    void walk(Item it) {
      final open = !_collapsed.contains(it.id);
      rows.add(
        _Row(
          key: ValueKey(it.id),
          g: g,
          it: it,
          open: open,
          onToggle: () => _toggle(it.id),
          onAdd: it.level < 2 ? () => _startAdd(it.id) : null,
        ),
      );
      if (open) {
        g.kids(it.id).forEach(walk);
        if (_addingTo == it.id) {
          rows.add(
            QuickAddField(
              key: ValueKey('add-${it.id}'),
              parentId: it.id,
              indent: (it.level + 1) * 18.0,
              hint: '${Item.levelNames[it.level + 1]} 추가 · Enter 계속',
              onClose: () => setState(() => _addingTo = null),
            ),
          );
        }
      }
    }

    for (final goal in g.goals) {
      walk(goal);
      rows.add(const Divider(height: 12));
    }
    rows.add(const SizedBox(height: 96));

    return ListView(padding: const EdgeInsets.only(top: 4), children: rows);
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.g, required this.it, required this.open, required this.onToggle, this.onAdd});
  final Graph g;
  final Item it;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final scheme = Theme.of(context).colorScheme;
    final leaf = g.isLeaf(it.id);
    final done = g.isDone(it.id);
    final blocked = !done && g.blockers(it.id).isNotEmpty;
    final badges = itemBadges(context, g, it);
    final titleStyle = TextStyle(
      fontSize: it.level == 0 ? 16 : 15,
      fontWeight: it.level == 0 ? FontWeight.w700 : (it.level == 1 ? FontWeight.w600 : FontWeight.w400),
      decoration: done ? TextDecoration.lineThrough : null,
      color: done || blocked ? Tone.muted(context) : scheme.onSurface,
    );

    Widget row = InkWell(
      onTap: () => openItemSheet(context, it.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(left: 4.0 + it.level * 18, right: 4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: leaf
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: open ? '접기' : '펼치기',
                        icon: AnimatedRotation(
                          turns: open ? .25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(Icons.chevron_right),
                        ),
                        onPressed: onToggle,
                      ),
              ),
              leaf
                  ? StatusCheck(status: it.status, blocked: blocked, onTap: () => repo.toggleDone(it.id))
                  : ProgressRing(g.progress(it.id)),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (it.today && !done)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.star_rounded, size: 16, color: Tone.warn(context)),
                            ),
                          Flexible(child: Text(it.title, style: titleStyle)),
                        ],
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: badges),
                      ],
                    ],
                  ),
                ),
              ),
              if (onAdd != null)
                IconButton(
                  tooltip: '${Item.levelNames[it.level + 1]} 추가',
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
            ],
          ),
        ),
      ),
    );

    if (leaf && it.level > 0) {
      row = Dismissible(
        key: ValueKey('sw-${it.id}'),
        background: _swipeBg(
          context,
          Alignment.centerLeft,
          done ? Icons.undo : Icons.check,
          scheme.primary,
          done ? '되돌리기' : '완료',
        ),
        secondaryBackground: _swipeBg(
          context,
          Alignment.centerRight,
          Icons.star_rounded,
          Tone.warn(context),
          it.today ? '★ 해제' : '오늘 ★',
        ),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            repo.toggleDone(it.id);
          } else {
            repo.toggleToday(it.id);
          }
          return false;
        },
        child: row,
      );
    }
    return row;
  }

  Widget _swipeBg(BuildContext context, Alignment a, IconData icon, Color c, String label) {
    final children = [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ];
    return Container(
      color: c,
      alignment: a,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: a == Alignment.centerLeft ? children : children.reversed.toList(),
      ),
    );
  }
}

/// 항목 추가 시 상위 선택 (캘린더·오늘 탭 FAB용)
Future<String?> pickParent(BuildContext context, Repository repo, {String title = '어디에 추가할까요?'}) {
  final g = repo.graph;
  final cands = g.inTreeOrder.where((i) => i.level < 2).toList();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      builder: (ctx, sc) => ListView(
        controller: sc,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('새 목표로'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          const Divider(),
          for (final c in cands)
            ListTile(
              contentPadding: EdgeInsets.only(left: 20.0 + c.level * 18, right: 16),
              leading: Badge2(c.levelName),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, c.id),
            ),
        ],
      ),
    ),
  );
}
