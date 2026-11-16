import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/graph.dart';
import '../widget/notif_sync.dart';
import 'app_scope.dart';
import 'common.dart';
import 'theme.dart';

/// 알림 선택지: 시작 몇 분 전 (null = 없음)
const reminderChoices = <int?, String>{null: '없음', 0: '정시', 10: '10분 전', 30: '30분 전', 60: '1시간 전', 1440: '하루 전'};

/// 일정 만들기·고치기. [id]가 있으면 그 일정을 고치고, 없으면 [day]에 새로 만든다.
Future<void> openEventEditor(BuildContext context, {String? id, DateTime? day, String title = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _EventEditor(id: id, day: day ?? DateTime.now(), initialTitle: title, hostContext: context),
  );
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.id, required this.day, required this.initialTitle, required this.hostContext});
  final String? id;
  final DateTime day;
  final String initialTitle;
  final BuildContext hostContext;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  final _title = TextEditingController();
  final _loc = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  DateTime? _endDate;
  TimeOfDay? _start, _end;
  int? _remind;
  bool _loaded = false;

  static TimeOfDay? _parse(String? s) {
    final p = s?.split(':');
    if (p == null || p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _date = DateTime(widget.day.year, widget.day.month, widget.day.day);
    _title.text = widget.initialTitle;
    final it = widget.id == null ? null : AppScope.repo(context)[widget.id!];
    if (it == null) return;
    _title.text = it.title;
    _loc.text = it.location;
    _note.text = it.note;
    _date = DateTime.tryParse(it.due ?? '') ?? _date;
    _endDate = DateTime.tryParse(it.endDate ?? '');
    _start = _parse(it.startTime);
    _end = _parse(it.endTime);
    _remind = it.remindMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _loc.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _allDay => _start == null;

  Future<void> _pickDate({required bool end}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? _date) : _date,
      firstDate: end ? _date : DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 10),
    );
    if (d == null) return;
    setState(() {
      if (end) {
        _endDate = d.isAfter(_date) ? d : null;
      } else {
        // 시작을 옮기면 기간은 그대로 유지한다
        final span = _endDate?.difference(_date);
        _date = d;
        _endDate = span == null ? null : d.add(span);
      }
    });
  }

  Future<void> _pickTime({required bool end}) async {
    final now = TimeOfDay.now();
    final init = end
        ? (_end ?? TimeOfDay(hour: ((_start?.hour ?? now.hour) + 1) % 24, minute: _start?.minute ?? 0))
        : (_start ?? TimeOfDay(hour: (now.hour + 1) % 24, minute: 0));
    final t = await showTimePicker(context: context, initialTime: init);
    if (t == null) return;
    setState(() {
      if (end) {
        _end = t;
      } else {
        // 시작을 옮기면 끝도 같은 길이만큼 따라간다
        if (_start != null && _end != null) {
          final len = (_end!.hour * 60 + _end!.minute) - (_start!.hour * 60 + _start!.minute);
          final e = (t.hour * 60 + t.minute + len).clamp(0, 23 * 60 + 59);
          _end = TimeOfDay(hour: e ~/ 60, minute: e % 60);
        }
        _start = t;
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = AppScope.repo(context);
    final nav = Navigator.of(context);
    // 같은 날 안에서 끝이 시작보다 이르면 끝 시각은 버린다
    var end = _end;
    if (_start != null && end != null && _endDate == null) {
      if (end.hour * 60 + end.minute <= _start!.hour * 60 + _start!.minute) end = null;
    }
    repo.saveEvent(
      id: widget.id,
      title: title,
      date: dateKey(_date),
      note: _note.text,
      attrs: {
        't': _start == null ? null : _fmt(_start!),
        'e': _start == null || end == null ? null : _fmt(end),
        'end': _endDate == null ? null : dateKey(_endDate!),
        'loc': _loc.text.trim(),
        'rem': _remind?.toString(),
      },
    );
    if (_remind != null) await NotifSync.askPermission();
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.id != null;
    final df = DateFormat('M월 d일 (E)', 'ko');
    final loc = MaterialLocalizations.of(context);

    Widget pill(String text, VoidCallback onTap, {bool muted = false}) => OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: muted ? Tone.muted(context) : null,
      ),
      child: Text(text),
    );

    Widget line(IconData icon, Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 36, child: Icon(icon, size: 20, color: Tone.muted(context))),
          Expanded(child: child),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Badge2('일정', color: scheme.primary, filled: true),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                const SizedBox(width: 4),
                ListenableBuilder(
                  listenable: _title,
                  builder: (context, _) =>
                      FilledButton(onPressed: _title.text.trim().isEmpty ? null : _save, child: const Text('저장')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              autofocus: !editing,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: '일정 제목'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              secondary: Icon(Icons.schedule, size: 20, color: Tone.muted(context)),
              title: const Text('하루 종일'),
              value: _allDay,
              onChanged: (v) => setState(() {
                if (v) {
                  _start = null;
                  _end = null;
                } else {
                  final h = (TimeOfDay.now().hour + 1) % 24;
                  _start = TimeOfDay(hour: h, minute: 0);
                  _end = h < 23 ? TimeOfDay(hour: h + 1, minute: 0) : null;
                }
              }),
            ),
            line(
              Icons.play_arrow_rounded,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  pill(df.format(_date), () => _pickDate(end: false)),
                  if (!_allDay) pill(loc.formatTimeOfDay(_start!), () => _pickTime(end: false)),
                ],
              ),
            ),
            line(
              Icons.stop_rounded,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  pill(
                    _endDate == null ? '같은 날' : df.format(_endDate!),
                    () => _pickDate(end: true),
                    muted: _endDate == null,
                  ),
                  if (!_allDay)
                    pill(
                      _end == null ? '끝 시각' : loc.formatTimeOfDay(_end!),
                      () => _pickTime(end: true),
                      muted: _end == null,
                    ),
                  if (_endDate != null || _end != null)
                    IconButton(
                      tooltip: '끝 지우기',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _endDate = null;
                        _end = null;
                      }),
                    ),
                ],
              ),
            ),
            line(
              Icons.place_outlined,
              TextField(
                controller: _loc,
                decoration: const InputDecoration(hintText: '장소'),
                textInputAction: TextInputAction.done,
              ),
            ),
            line(
              Icons.notifications_none_rounded,
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final e in reminderChoices.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _remind == e.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _remind = e.key),
                    ),
                ],
              ),
            ),
            if (_remind != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 4),
                child: Text(
                  '${_allDay ? '하루 종일 일정은 그날 오전 9시 기준. ' : ''}${NotifSync.supported ? '이 폰에서 알림이 울립니다.' : '알림은 안드로이드 앱에서 울리고, 여기서는 앱이 열려 있을 때 화면에 표시됩니다.'}',
                  style: TextStyle(fontSize: 12, color: Tone.muted(context)),
                ),
              ),
            line(
              Icons.notes_rounded,
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(hintText: '메모'),
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: () {
                        AppScope.repo(context).setEvent(widget.id!, false);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('할 일로 바꾸기'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () {
                        final repo = AppScope.repo(context);
                        final host = widget.hostContext;
                        final it = repo[widget.id!];
                        Navigator.pop(context);
                        if (it == null) return;
                        final snap = repo.remove(it.id);
                        showTopToast(
                          host,
                          '"${it.title}" 삭제됨',
                          actionLabel: '되돌리기',
                          onAction: () => repo.restore(snap),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('삭제'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
