import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import '../ui/auth_page.dart';
import '../ui/common.dart';
import '../ui/item_sheet.dart';
import '../ui/theme.dart';
import 'desk_frame.dart';
import 'desk_main.dart';

/// 바탕화면 캘린더: 월간 달력 칸마다 그날 마감인 항목을 적어 보여 준다.
class DeskCalendar extends StatefulWidget {
  const DeskCalendar({super.key});

  @override
  State<DeskCalendar> createState() => _DeskCalendarState();
}

class _DeskCalendarState extends State<DeskCalendar> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int n) => setState(() => _month = DateTime(_month.year, _month.month + n));

  @override
  Widget build(BuildContext context) {
    final data = DeskScope.of(context);
    if (!data.signedIn) {
      return const DeskFrame(title: Text('할일이많아'), child: AuthPage());
    }
    final now = DateTime.now();
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    return DeskFrame(
      title: Text(DateFormat('yyyy년 M월', 'ko').format(_month)),
      actions: [
        if (!isThisMonth)
          TextButton(
            onPressed: () => setState(() => _month = DateTime(now.year, now.month)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('오늘'),
          ),
        DeskIconButton(icon: Icons.chevron_left, tooltip: '지난달', onTap: () => _shift(-1)),
        DeskIconButton(icon: Icons.chevron_right, tooltip: '다음달', onTap: () => _shift(1)),
      ],
      // 마우스 휠로 달 넘기기
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && e.scrollDelta.dy.abs() > 0) _shift(e.scrollDelta.dy > 0 ? 1 : -1);
        },
        child: _MonthGrid(month: _month, graph: data.graph, onDay: (d) => showDayDialog(context, d)),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.graph, required this.onDay});
  final DateTime month;
  final Graph graph;
  final void Function(DateTime) onDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byDue = <String, List<Item>>{};
    for (final it in graph.byId.values) {
      if (it.due != null && it.due!.isNotEmpty) (byDue[it.due!] ??= []).add(it);
    }
    for (final l in byDue.values) {
      l.sort((a, b) {
        final da = graph.isDone(a.id) ? 1 : 0, db = graph.isDone(b.id) ? 1 : 0;
        if (da != db) return da - db;
        return a.level != b.level ? a.level - b.level : a.title.compareTo(b.title);
      });
    }
    final first = DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday % 7)); // 일요일 시작
    final todayKey = dateKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              for (final (i, w) in ['일', '월', '화', '수', '목', '금', '토'].indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: i == 0 ? Tone.danger(context) : Tone.muted(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                for (var r = 0; r < 6; r++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < 7; c++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final d = DateTime(start.year, start.month, start.day + r * 7 + c);
                                final key = dateKey(d);
                                return _DayCell(
                                  day: d,
                                  inMonth: d.month == month.month,
                                  today: key == todayKey,
                                  items: byDue[key] ?? const [],
                                  graph: graph,
                                  onTap: () => onDay(d),
                                  scheme: scheme,
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.items,
    required this.graph,
    required this.onTap,
    required this.scheme,
  });

  final DateTime day;
  final bool inMonth, today;
  final List<Item> items;
  final Graph graph;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final muted = Tone.muted(context);
    final sunday = day.weekday == DateTime.sunday;
    final numColor = !inMonth
        ? muted.withValues(alpha: 0.45)
        : today
        ? scheme.onPrimary
        : sunday
        ? Tone.danger(context)
        : scheme.onSurface;
    final overdue = dday(dateKey(day))! < 0;

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: today ? scheme.primaryContainer.withValues(alpha: 0.55) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 3, 2),
            child: LayoutBuilder(
              builder: (context, box) {
                const lineH = 15.0;
                // 칸 높이에 들어가는 만큼만 적고, 넘치면 마지막 줄에 +n
                final room = ((box.maxHeight - 19) / lineH).floor().clamp(0, 20);
                final shown = items.length > room ? (room - 1).clamp(0, 20) : items.length;
                final more = room > 0 && shown < items.length;
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxHeight: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: today
                              ? BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8))
                              : null,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: numColor, height: 1.4),
                          ),
                        ),
                        for (final it in items.take(shown))
                          SizedBox(
                            height: lineH,
                            child: _CellLine(it: it, done: graph.isDone(it.id), overdue: overdue, faded: !inMonth),
                          ),
                        if (more)
                          Text('+${items.length - shown}', style: TextStyle(fontSize: 10.5, color: muted, height: 1.3)),
                        if (room == 0 && items.isNotEmpty)
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CellLine extends StatelessWidget {
  const _CellLine({required this.it, required this.done, required this.overdue, required this.faded});
  final Item it;
  final bool done, overdue, faded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = done
        ? Tone.muted(context)
        : overdue
        ? Tone.danger(context)
        : it.level == 0
        ? scheme.tertiary
        : scheme.primary;
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              it.title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: done ? Tone.muted(context) : scheme.onSurface,
                decoration: done ? TextDecoration.lineThrough : null,
                fontWeight: it.level == 0 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 날짜를 누르면: 그날 마감 항목 목록 + 그날 마감으로 새 항목 추가
Future<void> showDayDialog(BuildContext context, DateTime day) {
  final data = DeskScope.of(context);
  final key = dateKey(day);
  final title = DateFormat('M월 d일 (E)', 'ko').format(day);
  final c = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      void submit() {
        final t = c.text.trim();
        if (t.isEmpty) return;
        data.add(t, due: key);
        c.clear();
      }

      return AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
            IconButton(tooltip: '닫기', icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: ListenableBuilder(
            listenable: data,
            builder: (context, _) {
              final g = data.graph;
              final items = g.byId.values.where((e) => e.due == key).toList()
                ..sort((a, b) => (g.isDone(a.id) ? 1 : 0) - (g.isDone(b.id) ? 1 : 0));
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text('이날 마감인 항목이 없어요.', style: TextStyle(color: Tone.muted(context))),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        children: [for (final it in items) DeskItemRow(it: it, graph: g, onOpen: openItemSheet)],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: c,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: '이날 마감으로 추가', isDense: true),
                          onSubmitted: (_) => submit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ListenableBuilder(
                        listenable: c,
                        builder: (context, _) =>
                            FilledButton(onPressed: c.text.trim().isEmpty ? null : submit, child: const Text('추가')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// 위젯 공용 항목 줄: 완료 체크 · 제목/경로 · 배지 · ★
class DeskItemRow extends StatelessWidget {
  const DeskItemRow({super.key, required this.it, required this.graph, this.onOpen});
  final Item it;
  final Graph graph;
  final Future<void> Function(BuildContext, String)? onOpen;

  @override
  Widget build(BuildContext context) {
    final data = DeskScope.of(context);
    final done = graph.isDone(it.id);
    final leaf = graph.isLeaf(it.id);
    final path = graph.path(it.id);
    final badges = itemBadges(context, graph, it);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onOpen == null ? null : () => onOpen!(context, it.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (leaf)
              StatusCheck(
                status: it.status,
                blocked: graph.blockers(it.id).isNotEmpty,
                onTap: () => data.toggleDone(it.id),
              )
            else
              const SizedBox(width: 40, child: Icon(Icons.folder_outlined, size: 18)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: done ? Tone.muted(context) : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (path.isNotEmpty || badges.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          if (path.isNotEmpty)
                            Flexible(
                              child: Text(
                                path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: Tone.muted(context)),
                              ),
                            ),
                          for (final b in badges.take(2)) Padding(padding: const EdgeInsets.only(left: 4), child: b),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (leaf && !done)
              IconButton(
                tooltip: it.today ? '오늘 할 일에서 빼기' : '오늘 할 일로',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => data.toggleToday(it.id),
                icon: Icon(
                  it.today ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: it.today ? Tone.warn(context) : Tone.muted(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
