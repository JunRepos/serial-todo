import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import 'app_scope.dart';
import 'calendar_page.dart';
import 'item_sheet.dart';
import 'sequence_page.dart';
import 'theme.dart';
import 'today_page.dart';
import 'tree_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, this.openItemId});

  /// 위젯에서 탭해 들어온 항목
  final ValueNotifier<String?>? openItemId;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _kTab = 'ui_tab';
  int _tab = 0;
  final _treeKey = GlobalKey<TreePageState>();
  final _calKey = GlobalKey<CalendarPageState>();
  bool _loaded = false;

  static const _dests = [
    (Icons.account_tree_outlined, Icons.account_tree, '구조'),
    (Icons.timeline_outlined, Icons.timeline, '순서'),
    (Icons.today_outlined, Icons.today, '오늘'),
    (Icons.calendar_month_outlined, Icons.calendar_month, '캘린더'),
  ];

  @override
  void initState() {
    super.initState();
    widget.openItemId?.addListener(_openFromWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromWidget());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _tab = AppScope.prefsOf(context).getInt(_kTab) ?? 0;
    }
  }

  @override
  void dispose() {
    widget.openItemId?.removeListener(_openFromWidget);
    super.dispose();
  }

  void _openFromWidget() {
    final n = widget.openItemId;
    final id = n?.value;
    if (id == null || !mounted) return;
    n!.value = null;
    setState(() => _tab = 2);
    if (AppScope.repo(context)[id] != null) openItemSheet(context, id);
  }

  void _setTab(int i) {
    setState(() => _tab = i);
    AppScope.prefsOf(context).setInt(_kTab, i);
  }

  Future<void> _fab() async {
    final repo = AppScope.repo(context);
    switch (_tab) {
      case 0:
      case 1:
        if (_tab != 0) _setTab(0);
        WidgetsBinding.instance.addPostFrameCallback((_) => _treeKey.currentState?.startGoal());
      case 2:
        await _addWithParent(repo, today: true);
      case 3:
        await _addWithParent(repo, due: _calKey.currentState?.selected ?? DateTime.now());
    }
  }

  Future<void> _addWithParent(Repository repo, {bool today = false, DateTime? due}) async {
    final what = due != null ? '${DateFormat('M월 d일').format(due)} 마감' : '오늘 ★';
    final parent = repo.graph.goals.isEmpty ? '' : await pickParent(context, repo, title: '$what 항목 · 어디에 추가할까요?');
    if (parent == null || !mounted) return;
    final title = await _askTitle(what);
    if (title == null || title.trim().isEmpty) return;
    repo.add(parent.isEmpty ? null : parent, title, due: due == null ? null : dateKey(due), today: today);
  }

  Future<String?> _askTitle(String what) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(what),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '제목'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('추가')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final pages = [
      TreePage(key: _treeKey),
      const SequencePage(),
      const TodayPage(),
      CalendarPage(key: _calKey),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    final fabLabel = switch (_tab) { 0 || 1 => '목표', 2 => '오늘 할 일', _ => '마감 항목' };

    return Scaffold(
      appBar: AppBar(
        title: Text(_dests[_tab].$3),
        actions: [const _SyncChip(), _menu(context), const SizedBox(width: 4)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fab,
        icon: const Icon(Icons.add),
        label: Text(fabLabel),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _setTab,
              height: 64,
              destinations: [
                for (final d in _dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _setTab,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _dests)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: body))),
            ])
          : body,
    );
  }

  Widget _menu(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return PopupMenuButton<String>(
      tooltip: '메뉴',
      onSelected: (v) {
        if (v == 'logout') Supabase.instance.client.auth.signOut();
        if (v == 'sync') AppScope.repo(context).refresh();
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(email)),
        const PopupMenuItem(value: 'sync', child: Text('지금 동기화')),
        const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
      ],
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.watch(context);
    final (IconData icon, String text, Color color) = switch (repo.sync) {
      SyncState.synced => (Icons.cloud_done_outlined, '동기화됨', Tone.muted(context)),
      SyncState.syncing => (Icons.sync, '동기화 중', Tone.muted(context)),
      SyncState.offline => (Icons.cloud_off_outlined, '오프라인 · 대기 ${repo.pendingCount}건', Tone.warn(context)),
      SyncState.error => (Icons.error_outline, '오류', Tone.danger(context)),
    };
    final label = repo.sync == SyncState.synced && repo.pendingCount > 0 ? '대기 ${repo.pendingCount}건' : text;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }
}
