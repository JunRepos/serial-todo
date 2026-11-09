import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/graph.dart';
import '../models/item.dart';
import 'app_scope.dart';
import 'common.dart';
import 'item_sheet.dart';
import 'theme.dart';
import 'today_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime selected;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    selected = DateTime(n.year, n.month, n.day);
  }

  void _shift(int m) => setState(() => _month = DateTime(_month.year, _month.month + m));

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.watch(context);
    final g = repo.graph;
    final scheme = Theme.of(context).colorScheme;

    final byDay = <String, List<Item>>{};
    for (final it in g.inTreeOrder) {
      if (it.due != null) (byDay[it.due!] ??= []).add(it);
    }
    final noDue = g.inTreeOrder.where((i) => g.isLeaf(i.id) && !g.isDone(i.id) && i.due == null).toList();
    final selKey = dateKey(selected);
    final selItems = byDay[selKey] ?? const <Item>[];
    final today = DateTime.now();
    final todayKey = dateKey(today);

    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday % 7; // 일요일 시작
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((lead + days) / 7).ceil() * 7;

    final top = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(
          children: [
            IconButton(tooltip: '이전 달', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: TextButton(
                onPressed: () => setState(() {
                  _month = DateTime(today.year, today.month);
                  selected = DateTime(today.year, today.month, today.day);
                }),
                child: Text(
                  DateFormat('yyyy년 M월').format(_month),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(tooltip: '다음 달', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
      if (noDue.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ActionChip(
              avatar: const Icon(Icons.event_busy, size: 18),
              label: Text('마감 없는 항목 ${noDue.length}개'),
              onPressed: () => _showNoDue(context, g, noDue),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final (i, w) in ['일', '월', '화', '수', '목', '금', '토'].indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: i == 0 ? scheme.error : Tone.muted(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(
          builder: (context, box) {
            // 칸 높이는 44~64로 제한해 넓은 화면에서도 달력이 지나치게 커지지 않게
            final w = box.maxWidth / 7;
            final h = (w / .86).clamp(44.0, 64.0);
            return GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: w / h,
              children: [
                for (var c = 0; c < cells; c++)
                  Builder(
                    builder: (context) {
                      final day = c - lead + 1;
                      if (day < 1 || day > days) return const SizedBox.shrink();
                      final d = DateTime(_month.year, _month.month, day);
                      final key = dateKey(d);
                      final items = byDay[key] ?? const <Item>[];
                      final open = items.where((i) => !g.isDone(i.id)).toList();
                      final overdue = key.compareTo(todayKey) < 0 && open.isNotEmpty;
                      return _DayCell(
                        day: day,
                        isToday: key == todayKey,
                        selected: key == selKey,
                        total: items.length,
                        open: open.length,
                        overdue: overdue,
                        sunday: d.weekday == DateTime.sunday,
                        onTap: () => setState(() => selected = d),
                        onDrop: (id) {
                          repo.setDue(id, key);
                          setState(() => selected = d);
                        },
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    ];
    final dayList = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          children: [
            Text(
              DateFormat('M월 d일 (E)', 'ko').format(selected),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Text('${selItems.length}개', style: TextStyle(color: Tone.muted(context))),
            const SizedBox(width: 8),
            Expanded(
              child: selItems.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '길게 눌러 날짜 이동',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Tone.muted(context)),
                    ),
            ),
          ],
        ),
      ),
      if (selItems.isEmpty)
        const EmptyHint('이 날 마감인 항목이 없습니다.')
      else
        for (final it in selItems) ItemCard(g: g, it: it, draggable: true, showDue: false),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 720) {
          // 넓은 화면: 달력 | 선택한 날 목록
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ListView(padding: const EdgeInsets.only(bottom: 24), children: top),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: ListView(padding: const EdgeInsets.only(top: 16, bottom: 96), children: dayList),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [...top, const Divider(height: 24), ...dayList],
        );
      },
    );
  }

  void _showNoDue(BuildContext context, Graph g, List<Item> items) {
    showModalBottomSheet<void>(
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
              child: Text(
                '마감 없는 항목 ${items.length}개',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final it in items)
              ListTile(
                title: Text(it.title),
                subtitle: g.path(it.id).isEmpty
                    ? null
                    : Text(g.path(it.id), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () {
                    AppScope.repo(context).setDue(it.id, dateKey(selected));
                    Navigator.pop(ctx);
                  },
                  child: Text(DateFormat('M/d').format(selected)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  openItemSheet(context, it.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.total,
    required this.open,
    required this.overdue,
    required this.sunday,
    required this.onTap,
    required this.onDrop,
  });
  final int day, total, open;
  final bool isToday, selected, overdue, sunday;
  final VoidCallback onTap;
  final void Function(String id) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = overdue ? scheme.error : (open > 0 ? scheme.primary : scheme.outline);
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, cand, _) {
        final hover = cand.isNotEmpty;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: hover
                  ? scheme.primary.withValues(alpha: .25)
                  : selected
                  ? scheme.primaryContainer.withValues(alpha: .6)
                  : null,
              border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontWeight: isToday || selected ? FontWeight.w700 : FontWeight.w400,
                    color: sunday ? scheme.error : null,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: total == 0
                      ? null
                      : total <= 3
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < total; i++)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < open ? dotColor : scheme.outlineVariant,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          '$total',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dotColor),
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
