import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'desk_bridge.dart';
import 'desk_main.dart';

/// 위젯 창의 틀: 머리줄을 끌어 옮기고, 오른쪽 아래 모서리로 크기를 바꾼다.
class DeskFrame extends StatelessWidget {
  const DeskFrame({super.key, required this.title, this.subtitle, this.actions = const [], required this.child});

  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6))),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: DeskNative.locked,
                  builder: (context, locked, _) => MouseRegion(
                    cursor: locked ? SystemMouseCursors.basic : SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => DeskNative.startDrag(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 4, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DefaultTextStyle.merge(
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: title,
                                  ),
                                  if (subtitle != null)
                                    DefaultTextStyle.merge(
                                      style: TextStyle(fontSize: 12, color: Tone.muted(context)),
                                      maxLines: 1,
                                      child: subtitle!,
                                    ),
                                ],
                              ),
                            ),
                            ...actions,
                            const SyncDot(),
                            _HeaderButton(icon: Icons.close, tooltip: '숨기기 (트레이 아이콘에서 다시 열기)', onTap: DeskNative.hide),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
            Positioned(right: 0, bottom: 0, child: _ResizeGrip()),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    color: Tone.muted(context),
    icon: Icon(icon),
  );
}

/// 머리줄에 쓰는 작은 아이콘 버튼
class DeskIconButton extends _HeaderButton {
  const DeskIconButton({super.key, required super.icon, required super.tooltip, required super.onTap});
}

class _ResizeGrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DeskNative.locked,
      builder: (context, locked, _) {
        if (locked) return const SizedBox.shrink();
        return MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => DeskNative.startResize(),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CustomPaint(painter: _GripPainter(Tone.muted(context).withValues(alpha: 0.5))),
            ),
          ),
        );
      },
    );
  }
}

class _GripPainter extends CustomPainter {
  _GripPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (final d in [5.0, 9.0, 13.0]) {
      canvas.drawLine(Offset(size.width - d, size.height - 3), Offset(size.width - 3, size.height - d), p);
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}

/// 동기화 상태 점. 누르면 새로 고침.
class SyncDot extends StatelessWidget {
  const SyncDot({super.key});

  @override
  Widget build(BuildContext context) {
    final data = DeskScope.of(context);
    if (!data.signedIn) return const SizedBox.shrink();
    final (Color c, String text) = switch (data.sync) {
      DeskSync.synced when data.pending == 0 => (const Color(0xFF3FA37A), '동기화됨'),
      DeskSync.synced || DeskSync.syncing => (Tone.muted(context), '동기화 중'),
      DeskSync.offline => (Tone.warn(context), '오프라인 · 대기 ${data.pending}건'),
      DeskSync.error => (Tone.danger(context), '동기화 오류'),
    };
    return Tooltip(
      message: '$text · 눌러서 새로 고침',
      child: InkResponse(
        onTap: data.refresh,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
