import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/outline.dart';
import 'app_scope.dart';

/// 인라인 빠른 추가.
/// - [추가] 버튼으로 추가한다. Enter는 줄바꿈이라 한 줄에 하나씩 여러 개를 적을 수 있다.
/// - Ctrl/⌘+Enter는 추가 단축키, Esc나 ✕는 닫기.
/// - 여러 줄을 붙여넣으면 들여쓰기·`-` 기준으로 하위 단계까지 한 번에 만든다.
/// 추가한 뒤에도 입력창은 열려 있어 이어서 입력할 수 있다.
class QuickAddField extends StatefulWidget {
  const QuickAddField({
    super.key,
    required this.parentId,
    required this.hint,
    this.onClose,
    this.autofocus = true,
    this.indent = 0,
  });

  final String? parentId;
  final String hint;
  final VoidCallback? onClose;
  final bool autofocus;
  final double indent;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _c = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }
    final enter = e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final keys = HardwareKeyboard.instance;
    if (enter && (keys.isControlPressed || keys.isMetaPressed)) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _lines => _c.text.split('\n').where((l) => l.trim().isNotEmpty).toList();

  void _submit() {
    final lines = _lines;
    if (lines.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final repo = AppScope.repo(context);
    if (lines.length == 1) {
      repo.add(widget.parentId, lines.first.trim());
    } else {
      final made = repo.addOutline(widget.parentId, parseOutline(_c.text));
      if (made.isNotEmpty) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('${made.length}개 추가'),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () {
                for (final it in made.where((e) => e.parentId == widget.parentId)) {
                  repo.remove(it.id);
                }
              },
            ),
          ),
        );
      }
    }
    _c.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final n = _lines.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + widget.indent, 4, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focus,
              autofocus: widget.autofocus,
              // Enter는 줄바꿈. 한 줄에 하나씩 적거나 여러 줄을 붙여넣을 수 있다.
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.hint,
                suffixIcon: widget.onClose == null
                    ? null
                    : IconButton(tooltip: '닫기', icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: n == 0 ? null : _submit,
              icon: const Icon(Icons.add, size: 18),
              label: Text(n > 1 ? '$n개 추가' : '추가'),
            ),
          ),
        ],
      ),
    );
  }
}
