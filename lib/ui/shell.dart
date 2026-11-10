import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import 'app_scope.dart';
import 'calendar_page.dart';
import 'item_sheet.dart';
import 'onboarding.dart';
import 'sequence_page.dart';
import 'theme.dart';
import 'today_page.dart';
import 'tree_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, this.widgetUri});

  /// 홈 화면 위젯에서 들어온 동작 (open?id=… 항목 편집, add 오늘 할 일 추가)
  final ValueNotifier<Uri?>? widgetUri;

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
    widget.widgetUri?.addListener(_openFromWidget);
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
    widget.widgetUri?.removeListener(_openFromWidget);
    super.dispose();
  }

  void _openFromWidget() {
    final n = widget.widgetUri;
    final uri = n?.value;
    if (uri == null || !mounted) return;
    n!.value = null;
    // 위젯은 "오늘" 기준이므로 오늘 탭으로 연다
    setState(() => _tab = 2);
    AppScope.prefsOf(context).setInt(_kTab, 2);
    if (uri.host == 'add') {
      _fab();
      return;
    }
    final id = uri.queryParameters['id'];
    if (id != null && AppScope.repo(context)[id] != null) openItemSheet(context, id);
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
    final pages = [TreePage(key: _treeKey), const SequencePage(), const TodayPage(), CalendarPage(key: _calKey)];
    final body = IndexedStack(index: _tab, children: pages);
    final fabLabel = switch (_tab) {
      0 || 1 => '목표',
      2 => '오늘 할 일',
      _ => '마감 항목',
    };

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
          ? Row(
              children: [
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
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: body),
                  ),
                ),
              ],
            )
          : body,
    );
  }

  Widget _menu(BuildContext context) {
    String email = '';
    try {
      email = Supabase.instance.client.auth.currentUser?.email ?? '';
    } catch (_) {} // 테스트 등 Supabase 미초기화
    return PopupMenuButton<String>(
      tooltip: '메뉴',
      onSelected: (v) {
        if (v == 'logout') Supabase.instance.client.auth.signOut();
        if (v == 'sync') AppScope.repo(context).refresh();
        if (v == 'help') showOnboarding(context);
        if (v == 'delete') _deleteAccount();
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(email)),
        const PopupMenuItem(value: 'sync', child: Text('지금 동기화')),
        const PopupMenuItem(value: 'help', child: Text('사용법')),
        const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
        PopupMenuItem(
          value: 'delete',
          child: Text('계정 삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );
  }

  /// 계정과 모든 할 일을 서버에서 지운다 (되돌릴 수 없음).
  Future<void> _deleteAccount() async {
    final repo = AppScope.repo(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계정을 삭제할까요?'),
        content: const Text('계정과 모든 할 일이 서버에서 영구히 지워집니다. 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final client = Supabase.instance.client;
      await client.rpc<void>('delete_my_account');
      await repo.forgetLocal();
      await client.auth.signOut();
      messenger.showSnackBar(const SnackBar(content: Text('계정을 삭제했습니다.')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('삭제하지 못했습니다. 인터넷 연결을 확인하세요.')));
    }
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
