import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../logic/graph.dart';
import '../models/item.dart';
import 'app_scope.dart';
import 'common.dart';
import 'theme.dart';

Future<void> openItemSheet(BuildContext context, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .4,
      maxChildSize: 1,
      builder: (ctx, sc) => _ItemSheet(id: id, scroll: sc, hostContext: context),
    ),
  );
}

/// 삭제 + 되돌리기 스낵바
void deleteWithUndo(BuildContext context, Repository repo, String id) {
  final it = repo[id];
  if (it == null) return;
  final snap = repo.remove(id);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('"${it.title}" 삭제됨'),
      action: SnackBarAction(label: '되돌리기', onPressed: () => repo.restore(snap)),
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.id, required this.scroll, required this.hostContext});
  final String id;
  final ScrollController scroll;
  final BuildContext hostContext;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  final _depQuery = TextEditingController();
  Timer? _tDebounce, _nDebounce;
  Repository? _repo;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = AppScope.repo(context);
      final it = _repo![widget.id];
      _title.text = it?.title ?? '';
      _note.text = it?.note ?? '';
    }
  }

  @override
  void dispose() {
    _flush();
    _title.dispose();
    _note.dispose();
    _depQuery.dispose();
    super.dispose();
  }

  void _flush() {
    final repo = _repo;
    if (repo == null) return;
    final id = widget.id;
    // dispose 중에는 다른 위젯을 다시 그릴 수 없으므로 다음 틱에 저장
    if (_tDebounce?.isActive ?? false) {
      _tDebounce!.cancel();
      final t = _title.text.trim();
      Future.microtask(() => repo.update(id, (x) => x.title = t.isEmpty ? '(제목 없음)' : t));
    }
    if (_nDebounce?.isActive ?? false) {
      _nDebounce!.cancel();
      final n = _note.text;
      Future.microtask(() => repo.update(id, (x) => x.note = n));
    }
  }

  void _saveTitle() {
    final t = _title.text.trim();
    _repo!.update(widget.id, (x) => x.title = t.isEmpty ? '(제목 없음)' : t);
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final g = repo.graph;
        final it = g[widget.id];
        if (it == null) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(32), child: Text('삭제된 항목입니다.')),
          );
        }
        return _body(context, repo, g, it);
      },
    );
  }

  Widget _body(BuildContext context, Repository repo, Graph g, Item it) {
    final scheme = Theme.of(context).colorScheme;
    final leaf = g.isLeaf(it.id);
    final sib = g.kids(g.parentOf(it.id));
    final idx = sib.indexWhere((s) => s.id == it.id);
    final path = g.path(it.id);
    const gap = SizedBox(height: 18);

    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        Row(
          children: [
            Badge2(it.levelName, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path.isEmpty ? '최상위' : path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Tone.muted(context), fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: '제목'),
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            _tDebounce?.cancel();
            _tDebounce = Timer(const Duration(milliseconds: 500), _saveTitle);
          },
          onSubmitted: (_) {
            _tDebounce?.cancel();
            _saveTitle();
          },
        ),
        gap,
        if (leaf) ...[
          _label('상태'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'todo', label: Text('할 일')),
              ButtonSegment(value: 'doing', label: Text('진행 중')),
              ButtonSegment(value: 'done', label: Text('완료')),
            ],
            selected: {it.status},
            onSelectionChanged: (s) => repo.setStatus(it.id, s.first),
          ),
        ] else ...[
          _label('진행률'),
          Row(
            children: [
              ProgressBar(g.progress(it.id), width: 140),
              const SizedBox(width: 10),
              Text('하위 액션 ${g.leaves(it.id).length}개', style: TextStyle(color: Tone.muted(context))),
            ],
          ),
        ],
        gap,
        _label('우선순위'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final p in [1, 2, 3]) ButtonSegment(value: p, label: Text(Item.priorityNames[p]!)),
          ],
          selected: {it.priority},
          onSelectionChanged: (s) => repo.update(it.id, (x) => x.priority = s.first),
        ),
        gap,
        _label('마감'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.event, size: 18),
                label: Text(it.due == null ? '날짜 선택' : '${it.due}  ·  ${ddayLabel(dday(it.due))}'),
                onPressed: () async {
                  final now = DateTime.now();
                  final init = it.due != null ? DateTime.tryParse(it.due!) ?? now : now;
                  final d = await showDatePicker(
                    context: context,
                    initialDate: init,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (d != null) repo.setDue(it.id, dateKey(d));
                },
              ),
            ),
            if (it.due != null)
              IconButton(tooltip: '마감 지우기', onPressed: () => repo.setDue(it.id, null), icon: const Icon(Icons.close)),
          ],
        ),
        const SizedBox(height: 8),
        if (leaf)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('오늘 할 일 ★'),
            value: it.today,
            onChanged: (v) => repo.update(it.id, (x) => x.today = v),
          ),
        if (it.level < 2)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('하위 순차 진행'),
            subtitle: const Text('위에서부터 하나씩'),
            value: it.seq,
            onChanged: (v) => repo.update(it.id, (x) => x.seq = v),
          ),
        gap,
        _deps(context, repo, g, it, idx, sib),
        gap,
        _label('메모'),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: '메모'),
          onChanged: (v) {
            _nDebounce?.cancel();
            _nDebounce = Timer(const Duration(milliseconds: 600), () => repo.update(it.id, (x) => x.note = v));
          },
        ),
        gap,
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: idx > 0 ? () => repo.move(it.id, -1) : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text('위로'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: idx >= 0 && idx < sib.length - 1 ? () => repo.move(it.id, 1) : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: const Text('아래로'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size.fromHeight(44)),
          onPressed: () {
            final host = widget.hostContext;
            Navigator.of(context).pop();
            deleteWithUndo(host, repo, it.id);
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(g.descendants(it.id).isEmpty ? '삭제' : '삭제 (하위 ${g.descendants(it.id).length}개 포함)'),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tone.muted(context)),
    ),
  );

  Widget _deps(BuildContext context, Repository repo, Graph g, Item it, int idx, List<Item> sib) {
    final cands = g.depCandidates(it.id);
    final deps = it.deps.toSet();
    final q = _depQuery.text.trim().toLowerCase();
    final shown = q.isEmpty ? cands : cands.where((c) => c.title.toLowerCase().contains(q)).toList();
    final parent = g.parentOf(it.id);
    final autoPrev = parent != null && g[parent]!.seq && idx > 0 ? sib[idx - 1] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('선행 항목 · 이게 끝나야 시작'),
        if (autoPrev != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '순차 진행: "${autoPrev.title}" 자동 선행',
              style: TextStyle(fontSize: 12.5, color: Tone.muted(context)),
            ),
          ),
        if (cands.isEmpty)
          Text('고를 수 있는 항목이 없습니다.', style: TextStyle(color: Tone.muted(context)))
        else ...[
          if (cands.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                controller: _depQuery,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: '검색'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final c in shown)
                  Builder(
                    builder: (_) {
                      final on = deps.contains(c.id);
                      final dis = !on && g.reaches(c.id, it.id);
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.only(left: 4.0 + (c.level - 1).clamp(0, 2) * 16, right: 8),
                        value: on,
                        onChanged: dis
                            ? null
                            : (v) => repo.update(it.id, (x) {
                                final s = x.deps.toSet();
                                v == true ? s.add(c.id) : s.remove(c.id);
                                x.deps = s.toList();
                              }),
                        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: dis ? const Text('순환이 생겨 선택 불가') : null,
                        secondary: Badge2(c.levelName),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
