import 'package:flutter/material.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import 'theme.dart';

/// 달력 칸 안의 한 줄: 일정은 색을 채운 막대, 할 일 마감은 옅은 막대 + 체크 표시.
class CalChip extends StatelessWidget {
  const CalChip({
    super.key,
    required this.it,
    required this.done,
    required this.past,
    this.faded = false,
    this.fontSize = 11,
  });
  final Item it;

  /// 할 일이 끝났는지 (일정에는 쓰지 않는다)
  final bool done;

  /// 날짜가 지났는지
  final bool past;

  /// 이번 달이 아닌 칸
  final bool faded;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg, fg;
    if (it.isEvent) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (done) {
      bg = scheme.onSurface.withValues(alpha: .07);
      fg = Tone.muted(context);
    } else if (past) {
      bg = Tone.danger(context).withValues(alpha: .16);
      fg = Tone.danger(context);
    } else {
      bg = scheme.primary.withValues(alpha: .16);
      fg = scheme.onSurface;
    }
    return Opacity(
      opacity: faded ? .45 : (it.isEvent && past ? .6 : 1),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (!it.isEvent)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: fontSize, color: fg),
              ),
            Expanded(
              child: Text(
                it.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.15,
                  color: fg,
                  fontWeight: it.isEvent ? FontWeight.w600 : FontWeight.w400,
                  decoration: done && !it.isEvent ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 칸 높이에 들어가는 만큼만 막대를 쌓고, 넘치면 마지막 줄에 +n.
class CalChipStack extends StatelessWidget {
  const CalChipStack({
    super.key,
    required this.items,
    required this.graph,
    required this.past,
    this.faded = false,
    this.lineHeight = 17,
    this.fontSize = 11,
  });
  final List<Item> items;
  final Graph graph;
  final bool past, faded;
  final double lineHeight, fontSize;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final room = (box.maxHeight / lineHeight).floor().clamp(0, 30);
        if (room == 0) {
          // 막대를 그릴 자리가 없으면 얇은 띠로만 있다는 것을 알린다
          return Align(
            alignment: Alignment.topLeft,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final shown = items.length > room ? room - 1 : items.length;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final it in items.take(shown))
                  SizedBox(
                    height: lineHeight,
                    child: CalChip(
                      it: it,
                      done: !it.isEvent && graph.isDone(it.id),
                      past: past,
                      faded: faded,
                      fontSize: fontSize,
                    ),
                  ),
                if (shown < items.length)
                  SizedBox(
                    height: lineHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        '+${items.length - shown}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: Tone.muted(context),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
