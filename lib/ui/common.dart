import 'package:flutter/material.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import 'theme.dart';

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.color, this.filled = false});
  final String text;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Tone.muted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: filled ? Colors.white : c, height: 1.3),
      ),
    );
  }
}

/// 우선·마감·순차·대기 배지 묶음
List<Widget> itemBadges(BuildContext context, Graph g, Item it, {bool full = false, bool showDue = true}) {
  final done = g.isDone(it.id);
  final leaf = g.isLeaf(it.id);
  final scheme = Theme.of(context).colorScheme;
  final out = <Widget>[];
  if (!done && it.priority == 1) out.add(Badge2('우선', color: scheme.error));
  if (!done && it.priority == 3) out.add(const Badge2('낮음'));
  if (leaf && it.status == 'doing') out.add(Badge2('진행 중', color: scheme.primary));
  if (showDue) {
    final n = dday(it.due);
    if (n != null) {
      Color? c;
      if (!done && n < 0) c = Tone.danger(context);
      if (!done && n >= 0 && n <= 2) c = Tone.warn(context);
      out.add(Badge2(ddayLabel(n)!, color: c));
    }
  }
  if (!leaf && it.seq) out.add(Badge2('순차', color: scheme.tertiary));
  if (!done) {
    final bl = g.blockers(it.id);
    if (bl.isNotEmpty) {
      final names = bl.map((b) => g[b]!.title).toList();
      final t = full ? names.join(', ') : names.first + (names.length > 1 ? ' 외 ${names.length - 1}' : '');
      out.add(Badge2('대기 · $t', color: Tone.warn(context)));
    }
  }
  return out;
}

class StatusCheck extends StatelessWidget {
  const StatusCheck({super.key, required this.status, required this.onTap, this.blocked = false});
  final String status;
  final VoidCallback onTap;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = status == 'done';
    final doing = status == 'doing';
    return Semantics(
      checked: done,
      button: true,
      label: '완료',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: done || doing ? scheme.primary : scheme.outline.withValues(alpha: blocked ? .4 : 1),
                  width: 2,
                ),
              ),
              child: done
                  ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
                  : doing
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          ),
                        )
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing(this.pct, {super.key});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: pct / 100,
                strokeWidth: 3,
                backgroundColor: scheme.outlineVariant.withValues(alpha: .5),
              ),
              Text('$pct', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar(this.pct, {super.key, this.width = 64});
  final int pct;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 5,
            backgroundColor: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('$pct%', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ]);
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: Tone.muted(context))),
        if (action != null) ...[
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onAction, child: Text(action!)),
        ],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: TextStyle(color: Tone.muted(context), fontSize: 13)),
        ],
      ]),
    );
  }
}
