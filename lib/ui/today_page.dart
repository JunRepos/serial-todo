import 'package:flutter/material.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import 'app_scope.dart';
import 'common.dart';
import 'item_sheet.dart';
import 'theme.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.watch(context);
    final g = repo.graph;
    final l = g.todayLists();
    final events = [
      for (final e in g.byDate[dateKey(DateTime.now())] ?? const <Item>[])
        if (e.isEvent) e,
    ];
    // ★는 아니지만 마감이 오늘이거나 지난 것: 놓치지 않게 따로 모은다
    bool urgent(Item i) => (dday(i.due) ?? 1) <= 0;
    final due = [...l.ready.where(urgent), ...l.wait.where(urgent)];
    final ready = l.ready.where((i) => !urgent(i)).toList();
    final wait = l.wait.where((i) => !urgent(i)).toList();
    return ListView(
      children: [
        if (events.isNotEmpty) ...[
          SectionTitle('오늘 일정', trailing: '${events.length}개'),
          for (final e in events)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              minLeadingWidth: 4,
              title: Text(e.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              subtitle: Text(e.eventSummary),
              onTap: () => openItemSheet(context, e.id),
            ),
        ],
        SectionTitle('오늘', trailing: '${l.today.length}개'),
        if (l.today.isEmpty)
          const EmptyHint('아래 목록이나 구조 탭에서 ☆를 눌러 오늘 할 일을 고르세요.')
        else
          for (final it in l.today) ItemCard(g: g, it: it),
        if (due.isNotEmpty) ...[
          SectionTitle('오늘 마감 · 지난 마감', trailing: '${due.length}개'),
          for (final it in due) ItemCard(g: g, it: it),
        ],
        SectionTitle('바로 할 수 있음', trailing: '${ready.length}개'),
        if (ready.isEmpty) const EmptyHint('바로 할 수 있는 액션이 없습니다.') else for (final it in ready) ItemCard(g: g, it: it),
        if (wait.isNotEmpty) ...[
          SectionTitle('대기 중', trailing: '${wait.length}개'),
          for (final it in wait) ItemCard(g: g, it: it),
        ],
        if (l.recent.isNotEmpty) ...[
          SectionTitle('최근 7일 완료', trailing: '${l.recent.length}개'),
          for (final it in l.recent) ItemCard(g: g, it: it),
        ],
        const SizedBox(height: 96),
      ],
    );
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.g, required this.it, this.draggable = false, this.showDue = true});
  final Graph g;
  final Item it;
  final bool draggable;
  final bool showDue;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final scheme = Theme.of(context).colorScheme;
    final leaf = g.isLeaf(it.id);
    final done = g.isDone(it.id);
    final path = g.path(it.id);
    final badges = done ? const <Widget>[] : itemBadges(context, g, it, full: true, showDue: showDue);

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: it.status == 'doing' ? scheme.primaryContainer.withValues(alpha: .35) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openItemSheet(context, it.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              leaf
                  ? StatusCheck(status: it.status, onTap: () => repo.toggleDone(it.id))
                  : ProgressRing(g.progress(it.id)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? Tone.muted(context) : null,
                        ),
                      ),
                      if (path.isNotEmpty)
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Tone.muted(context)),
                        ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: badges),
                      ],
                    ],
                  ),
                ),
              ),
              if (!done && leaf && it.status != 'doing')
                IconButton(
                  tooltip: '시작',
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => repo.setStatus(it.id, 'doing'),
                ),
              if (!done && leaf)
                IconButton(
                  tooltip: '오늘 할 일',
                  isSelected: it.today,
                  selectedIcon: Icon(Icons.star_rounded, color: Tone.warn(context)),
                  icon: const Icon(Icons.star_outline_rounded),
                  onPressed: () => repo.toggleToday(it.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (!draggable) return card;
    return LongPressDraggable<String>(
      data: it.id,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: card),
      child: card,
    );
  }
}
