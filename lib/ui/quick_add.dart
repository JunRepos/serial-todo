import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/outline.dart';
import 'app_scope.dart';

/// 인라인 빠른 추가. Enter로 추가 후 입력창 유지, 빈 Enter/Esc로 닫기.
/// 여러 줄을 붙여넣으면 들여쓰기·`-` 기준으로 하위 단계까지 한 번에 만든다.
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
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      _c.clear();
      widget.onClose?.call();
      return;
    }
    final repo = AppScope.repo(context);
    if (lines.length == 1) {
      repo.add(widget.parentId, lines.first);
    } else {
      final made = repo.addOutline(widget.parentId, parseOutline(raw));
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
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + widget.indent, 4, 12, 8),
      child: TextField(
        controller: _c,
        focusNode: _focus,
        autofocus: widget.autofocus,
        // 여러 줄 붙여넣기를 받기 위해 multiline. Enter 입력은 onChanged에서 제출로 처리.
        minLines: 1,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.add, size: 20),
          suffixIcon: widget.onClose == null
              ? null
              : IconButton(tooltip: '닫기', icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
        ),
        onSubmitted: _submit,
        onChanged: (v) {
          if (v.contains('\n')) _submit(v);
        },
      ),
    );
  }
}
