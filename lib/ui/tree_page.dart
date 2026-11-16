import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import '../models/item.dart';
import 'app_scope.dart';
import 'common.dart';
import 'item_sheet.dart';
import 'quick_add.dart';
import 'theme.dart';

/// 완료한 항목 숨기기 (메뉴에서 켜고 끈다)
final hideDone = ValueNotifier<bool>(false);
const kHideDone = 'ui_hide_done';

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

  // 끌어 옮기는 동안 목록 위아래 끝에 가까이 가면 저절로 스크롤한다
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScroll;
  double _scrollSpeed = 0;

  void _onDragUpdate(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(global).dy, h = box.size.height;
    const edge = 64.0;
    _scrollSpeed = y < edge ? -(edge - y) / 4 : (y > h - edge ? (y - (h - edge)) / 4 : 0);
    if (_scrollSpeed == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        _scroll.jumpTo((pos.pixels + _scrollSpeed).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      });
    }
  }

  void _onDragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  @override
  void dispose() {
    hideDone.removeListener(_onHideDone);
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _collapsed = (AppScope.prefsOf(context).getStringList(_kCollapsed) ?? const []).toSet();
      hideDone.value = AppScope.prefsOf(context).getBool(kHideDone) ?? false;
      hideDone.addListener(_onHideDone);
    }
  }

  void _onHideDone() {
    if (mounted) setState(() {});
  }

  /// 메뉴: 전부 접기 / 전부 펴기
  void collapseAll(bool collapse) {
    final g = AppScope.repo(context).graph;
    setState(
      () => _collapsed = collapse
          ? {
              for (final i in g.byId.values)
                if (!g.isLeaf(i.id)) i.id,
            }
          : {},
    );
    AppScope.prefsOf(context).setStringList(_kCollapsed, _collapsed.toList());
  }

  /// FAB: 새 목표 입력창 열기
  void startGoal() {
    setState(() {
      _addingGoal = true;
      _addingTo = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // 입력창이 화면 밖에 생기면 보이는 곳까지 스크롤한다
  final _addKey = GlobalKey();
  void _revealAdd([int tries = 12]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _addingTo == null) return;
      final ctx = _addKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 200));
      } else if (tries > 0 && _scroll.hasClients) {
        // 아직 그려지지 않을 만큼 아래에 있다: 조금씩 내려가며 찾는다
        final pos = _scroll.position;
        _scroll.jumpTo((pos.pixels + pos.viewportDimension * .8).clamp(0, pos.maxScrollExtent));
        _revealAdd(tries - 1);
      }
    });
  }

  void _toggle(String id) {
    setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id));
    AppScope.prefsOf(context).setStringList(_kCollapsed, _collapsed.toList());
  }

  void _startAdd(String id) {
    setState(() {
      _addingTo = id;
      _addingGoal = false;
      if (_collapsed.remove(id)) AppScope.prefsOf(context).setStringList(_kCollapsed, _collapsed.toList());
    });
    _revealAdd();
  }

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
          hint: '새 목표 · 한 줄에 하나씩',
          autofocus: _addingGoal,
          onClose: g.goals.isEmpty ? null : () => setState(() => _addingGoal = false),
        ),
      );
    }
    if (g.goals.isEmpty) {
      rows.add(const EmptyHint('목표를 하나 입력해 시작하세요.'));
    }

    final hide = hideDone.value;
    var hidden = 0;
    void walk(Item it) {
      if (hide && g.isDone(it.id)) {
        hidden++;
        return;
      }
      final open = !_collapsed.contains(it.id);
      rows.add(
        _DragRow(
          key: ValueKey(it.id),
          g: g,
          it: it,
          // 펼쳐진 상위 항목은 아래쪽에 놓으면 그 안으로 들어간다
          hasOpenKids: open && g.kids(it.id).isNotEmpty,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          child: _Row(
            g: g,
            it: it,
            open: open,
            onToggle: () => _toggle(it.id),
            onAdd: it.level < 2 ? () => _startAdd(it.id) : null,
          ),
        ),
      );
      if (open) {
        g.kids(it.id).forEach(walk);
        if (_addingTo == it.id) {
          rows.add(
            QuickAddField(
              key: _addKey,
              parentId: it.id,
              indent: (it.level + 1) * 18.0,
              hint: '새 ${Item.levelNames[it.level + 1]} · 한 줄에 하나씩',
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
    if (hidden > 0) {
      rows.add(
        Center(
          child: TextButton(
            onPressed: () {
              hideDone.value = false;
              AppScope.prefsOf(context).setBool(kHideDone, false);
            },
            child: Text('완료한 항목 $hidden개 숨김 · 모두 보기'),
          ),
        ),
      );
    }
    rows.add(const SizedBox(height: 96));

    return ListView(key: _listKey, controller: _scroll, padding: const EdgeInsets.only(top: 4), children: rows);
  }
}

enum _Drop { before, into, after }

/// 한 줄을 길게 눌러 끌 수 있게 하고, 다른 줄이 그 위에 놓일 자리(앞·안·뒤)를 표시한다.
class _DragRow extends StatefulWidget {
  const _DragRow({
    super.key,
    required this.g,
    required this.it,
    required this.hasOpenKids,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });
  final Graph g;
  final Item it;
  final bool hasOpenKids;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  State<_DragRow> createState() => _DragRowState();
}

class _DragRowState extends State<_DragRow> {
  _Drop? _zone;

  /// 끌어 온 항목을 이 줄의 어디에 놓을 수 있는지. 놓을 수 없으면 null.
  _Drop? _zoneFor(String dragId, Offset global) {
    final g = widget.g, it = widget.it;
    if (dragId == it.id || g.descendants(dragId).contains(it.id)) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final f = box.globalToLocal(global).dy / box.size.height;
    final parent = g.parentOf(it.id);
    final canInto = g.canMove(dragId, it.id), canSibling = g.canMove(dragId, parent);
    if (canInto && (widget.hasOpenKids ? f > .35 : (f > .3 && f < .7))) return _Drop.into;
    if (canSibling) return f < .5 ? _Drop.before : (widget.hasOpenKids ? null : _Drop.after);
    return canInto ? _Drop.into : null;
  }

  void _accept(String dragId, _Drop zone) {
    final repo = AppScope.repo(context);
    final it = widget.it, g = widget.g;
    final before = [for (final x in g.byId.values) x.copy()];
    final ok = switch (zone) {
      _Drop.into => repo.moveTo(dragId, it.id),
      _Drop.before => repo.moveTo(dragId, g.parentOf(it.id), before: it.id),
      _Drop.after => repo.moveTo(dragId, g.parentOf(it.id), after: it.id),
    };
    if (!ok) return;
    HapticFeedback.selectionClick();
    final moved = repo[dragId];
    final where = moved == null
        ? ''
        : (repo.graph.parentOf(dragId) == null ? '목표로' : '"${repo.graph.path(dragId).split(' › ').last}" 아래로');
    showTopToast(
      context,
      '"${moved?.title ?? ''}" $where 옮김',
      actionLabel: '되돌리기',
      onAction: () => repo.restore(before),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final it = widget.it;
    final line = BorderSide(color: scheme.primary, width: 2.5);
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) => _zoneFor(d.data, d.offset) != null,
      onMove: (d) {
        final z = _zoneFor(d.data, d.offset);
        if (z != _zone) setState(() => _zone = z);
      },
      onLeave: (_) => setState(() => _zone = null),
      onAcceptWithDetails: (d) {
        final z = _zoneFor(d.data, d.offset);
        setState(() => _zone = null);
        if (z != null) _accept(d.data, z);
      },
      builder: (context, cand, _) => Container(
        foregroundDecoration: BoxDecoration(
          color: _zone == _Drop.into ? scheme.primary.withValues(alpha: .14) : null,
          border: Border(
            top: _zone == _Drop.before ? line : BorderSide.none,
            bottom: _zone == _Drop.after ? line : BorderSide.none,
          ),
        ),
        child: widget.child,
      ),
    );
    return LongPressDraggable<String>(
      data: it.id,
      // 손가락(마우스) 위치를 기준으로 놓을 자리를 계산한다
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: HapticFeedback.mediumImpact,
      onDragUpdate: (d) => widget.onDragUpdate(d.globalPosition),
      onDragEnd: (_) => widget.onDragEnd(),
      onDraggableCanceled: (_, _) => widget.onDragEnd(),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator, size: 18, color: Tone.muted(context)),
                const SizedBox(width: 6),
                Flexible(child: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: target),
      child: target,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.g, required this.it, required this.open, required this.onToggle, this.onAdd});
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
                        children: [Flexible(child: Text(it.title, style: titleStyle))],
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: badges),
                      ],
                    ],
                  ),
                ),
              ),
              if (leaf && !done)
                IconButton(
                  tooltip: it.today ? '오늘 할 일에서 빼기' : '오늘 할 일로',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    it.today ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 20,
                    color: it.today ? Tone.warn(context) : scheme.outline,
                  ),
                  onPressed: () => repo.toggleToday(it.id),
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
    final fg = onColor(c);
    final children = [
      Icon(icon, color: fg),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
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
