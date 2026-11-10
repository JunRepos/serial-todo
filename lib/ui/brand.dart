import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 앱 이름과 브랜드 색. 아이콘(계단 + 체크)과 같은 모양을 코드로 그린다.
const appName = '할일이많아';
const appTagline = '큰 목표를 쪼개고, 순서대로 하나씩';
const brandColor = Color(0xFF2E5B4E);
const brandDeep = Color(0xFF234A3F);
const brandMint = Color(0xFFA6E3CB);

/// 계단 + 체크 로고. [steps] 0~1: 계단 세 칸이 차례로 올라옴, [check] 0~1: 체크가 그려짐.
class StairsLogo extends StatelessWidget {
  const StairsLogo({super.key, this.size = 96, this.steps = 1, this.check = 1, this.stepColor = Colors.white});
  final double size;
  final double steps;
  final double check;
  final Color stepColor;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StairsPainter(steps, check, stepColor));
}

class _StairsPainter extends CustomPainter {
  _StairsPainter(this.steps, this.check, this.stepColor);
  final double steps, check;
  final Color stepColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 아이콘과 같은 108 좌표계에서 그림이 차지하는 영역(x 28~80, y 22~82)을 꽉 채우게 맞춘다
    const left = 28.0, top = 22.0, w = 52.0, h = 60.0;
    final s = math.min(size.width / w, size.height / h);
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    canvas.translate(-left, -top);

    final paint = Paint()..color = stepColor;
    const base = 82.0;
    for (var i = 0; i < 3; i++) {
      // 칸마다 조금씩 늦게 올라온다
      final t = Curves.easeOutBack.transform(((steps * 1.6) - i * 0.3).clamp(0.0, 1.0));
      final full = 14.0 + 12 * i; // 칸 높이
      final hh = full * t;
      if (hh <= 0) continue;
      final x = 28.0 + 16 * i;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, base - hh, 16 + (i < 2 ? 2 : 0), hh),
          topLeft: const Radius.circular(2.5),
          topRight: const Radius.circular(2.5),
          bottomLeft: Radius.circular(i == 0 ? 2.5 : 0),
          bottomRight: Radius.circular(i == 2 ? 2.5 : 0),
        ),
        paint,
      );
    }

    if (check > 0) {
      final path = Path()
        ..moveTo(58.5, 31.5)
        ..lineTo(65, 38)
        ..lineTo(78.5, 24.5);
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * Curves.easeOut.transform(check.clamp(0.0, 1.0)));
      canvas.drawPath(
        part,
        Paint()
          ..color = brandMint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StairsPainter old) => old.steps != steps || old.check != check || old.stepColor != stepColor;
}

/// 앱 시작 애니메이션. [child]는 뒤에서 미리 그려 두고(데이터 로딩 겸) 애니메이션이 끝나면 걷어낸다.
/// 화면을 탭하면 바로 넘어간다.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key, required this.child});
  final Widget child;

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _in.forward().whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _leave();
    });
  }

  void _leave() {
    if (_out.isAnimating || _gone || !mounted) return;
    _out.forward().whenComplete(() {
      if (mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: Listenable.merge([_in, _out]),
          builder: (context, _) {
            final t = _in.value;
            final out = Curves.easeIn.transform(_out.value);
            Interval iv(double a, double b) => Interval(a, b, curve: Curves.easeOut);
            final steps = (t / 0.55).clamp(0.0, 1.0);
            final check = iv(0.5, 0.78).transform(t);
            final text = iv(0.62, 1).transform(t);
            return IgnorePointer(
              ignoring: out > 0.5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _leave,
                child: Opacity(
                  opacity: 1 - out,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [brandColor, brandDeep],
                      ),
                    ),
                    child: Transform.scale(
                      scale: 1 + out * 0.08,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StairsLogo(size: 104, steps: steps, check: check),
                            const SizedBox(height: 28),
                            Opacity(
                              opacity: text,
                              child: Transform.translate(
                                offset: Offset(0, (1 - text) * 12),
                                child: const Column(
                                  children: [
                                    Text(
                                      appName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      appTagline,
                                      style: TextStyle(
                                        color: brandMint,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
