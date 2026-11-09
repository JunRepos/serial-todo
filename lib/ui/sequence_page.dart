import 'package:flutter/material.dart';

import '../logic/graph.dart';
import 'app_scope.dart';
import 'common.dart';
import 'item_sheet.dart';
import 'theme.dart';

class SequencePage extends StatelessWidget {
  const SequencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.watch(context);
    final g = repo.graph;
    final scheme = Theme.of(context).colorScheme;
    if (g.goals.isEmpty) return const EmptyHint('구조 탭에서 목표를 먼저 추가하세요.');

    final children = <Widget>[];
    if (g.hasGoalDeps) {
      final ordered = g.orderedGoals();
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Text('목표 순서', style: TextStyle(color: Tone.muted(context), fontSize: 13)),
            for (var i = 0; i < ordered.length; i++) ...[
              if (i > 0) Icon(Icons.arrow_forward, size: 14, color: Tone.muted(context)),
              ActionChip(
                label: Text(ordered[i].title,
                    style: TextStyle(decoration: g.isDone(ordered[i].id) ? TextDecoration.lineThrough : null)),
                onPressed: () => openItemSheet(context, ordered[i].id),
              ),
            ],
          ],
        ),
      ));
    }

    for (final goal in g.goals) {
      final r = g.sequenceOf(goal.id);
      final p = g.progress(goal.id);
      final due = ddayLabel(dday(goal.due));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => openItemSheet(context, goal.id),
              child: Text(goal.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          if (due != null) ...[Badge2(due), const SizedBox(width: 8)],
          ProgressBar(p),
        ]),
      ));
      if (r.cyc.isNotEmpty) {
        children.add(Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
          child: Text('선행 관계가 순환합니다: ${r.cyc.map((c) => g[c]!.title).join(', ')}',
              style: TextStyle(color: scheme.onErrorContainer)),
        ));
      }
      if (r.stages.length == 1 && r.stages.first.first == goal.id && g.isLeaf(goal.id)) {
        children.add(const EmptyHint('하위 항목이 없습니다.'));
        continue;
      }
      var nowFound = false;
      for (var i = 0; i < r.stages.length; i++) {
        final arr = r.stages[i];
        final allDone = arr.every(g.isDone);
        final isNow = !allDone && !nowFound;
        if (isNow) nowFound = true;
        children.add(_Stage(index: i + 1, leaves: arr, g: g, goalId: goal.id, now: isNow, past: allDone));
      }
    }
    children.add(const SizedBox(height: 96));
    return ListView(children: children);
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.index,
    required this.leaves,
    required this.g,
    required this.goalId,
    required this.now,
    required this.past,
  });
  final int index;
  final List<String> leaves;
  final Graph g;
  final String goalId;
  final bool now, past;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final scheme = Theme.of(context).colorScheme;
    final info = <String>[
      if (now) '지금 단계',
      if (leaves.length > 1) '동시 진행 가능 ${leaves.length}개',
      if (past) '완료',
    ];
    return Opacity(
      opacity: past ? .55 : 1,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 56,
            child: Column(children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: now ? scheme.primary : scheme.surfaceContainerHighest,
                ),
                child: Text('$index',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: now ? scheme.onPrimary : scheme.onSurfaceVariant)),
              ),
              Expanded(child: VerticalDivider(width: 2, thickness: 2, color: scheme.outlineVariant)),
            ]),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 16, bottom: 10),
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              decoration: now
                  ? BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (info.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
                    child: Text(info.join(' · '),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: now ? scheme.primary : Tone.muted(context))),
                  ),
                for (final l in leaves)
                  Builder(builder: (context) {
                    final it = g[l]!;
                    final done = g.isDone(l);
                    final parent = g.parentOf(l);
                    final par = parent != null && parent != goalId ? g[parent]!.title : null;
                    return InkWell(
                      onTap: () => openItemSheet(context, l),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(children: [
                        StatusCheck(status: it.status, onTap: () => repo.toggleDone(l)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(it.title,
                                style: TextStyle(
                                    decoration: done ? TextDecoration.lineThrough : null,
                                    color: done ? Tone.muted(context) : null)),
                            if (par != null)
                              Text(par, style: TextStyle(fontSize: 12, color: Tone.muted(context))),
                          ]),
                        ),
                      ]),
                    );
                  }),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
