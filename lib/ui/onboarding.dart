import 'package:flutter/material.dart';

import 'brand.dart';
import 'theme.dart';

/// 처음 실행할 때 보여 주는 4장짜리 사용법. 메뉴의 "사용법"으로 다시 볼 수 있다.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.onDone});
  final VoidCallback onDone;

  static const prefsKey = 'onboarded_v1';

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _Page {
  const _Page(this.title, this.body, this.art);
  final String title;
  final String body;
  final Widget Function(bool active) art;
}

class _OnboardingState extends State<Onboarding> {
  final _pc = PageController();
  int _i = 0;

  late final _pages = <_Page>[
    _Page('큰 목표를 작게 쪼개요', '목표 → 프로젝트 → 액션.\n오늘 바로 할 수 있는 크기까지 나눠 보세요.', (a) => _TreeArt(active: a)),
    _Page('순서는 앱이 계산해요', '"이게 끝나야 시작" 할 일을 정해 두면\n무엇부터 할지 단계로 보여 줘요.', (a) => _StagesArt(active: a)),
    _Page('오늘 할 일에 집중', '★로 오늘 할 일을 고르고\n오른쪽으로 밀면 완료예요.', (a) => _TodayArt(active: a)),
    _Page('어디서나 이어서', '폰과 웹이 자동으로 맞춰지고\n인터넷이 끊겨도 저장돼요. 홈 화면 위젯도 있어요.', (a) => _SyncArt(active: a)),
  ];

  bool get _last => _i == _pages.length - 1;

  void _next() {
    if (_last) {
      widget.onDone();
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _last ? null : widget.onDone,
                      style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                      child: const Text('건너뛰기'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _i = i),
                    itemBuilder: (context, i) {
                      final p = _pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            Expanded(child: Center(child: p.art(i == _i))),
                            Text(
                              p.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              p.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15.5, height: 1.5, color: Tone.muted(context)),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _i ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _i ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _next,
                    child: Text(_last ? '시작하기' : '다음', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 그림

/// 페이지가 보일 때마다 0→1로 다시 재생되는 진행값
class _Play extends StatelessWidget {
  const _Play({required this.active, required this.builder, this.ms = 900});
  final bool active;
  final int ms;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(active),
    tween: Tween(begin: active ? 0 : 1, end: 1),
    duration: Duration(milliseconds: active ? ms : 1),
    builder: (_, t, _) => builder(t),
  );
}

double _stagger(double t, int i, {double step = 0.18, double len = 0.45}) =>
    Curves.easeOutCubic.transform(((t - i * step) / len).clamp(0.0, 1.0));

Widget _slideIn(double v, Widget child, {double dy = 14}) => Opacity(
  opacity: v,
  child: Transform.translate(offset: Offset(0, (1 - v) * dy), child: child),
);

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({this.done = false});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).colorScheme.primary;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? p : Colors.transparent,
        border: Border.all(color: p, width: 2),
      ),
      child: done ? Icon(Icons.check, size: 12, color: Theme.of(context).colorScheme.onPrimary) : null,
    );
  }
}

class _TreeArt extends StatelessWidget {
  const _TreeArt({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (0, '여행 준비', '목표'),
      (1, '숙소 예약', '프로젝트'),
      (2, '후보 3곳 비교', '액션'),
      (2, '예약하기', '액션'),
      (1, '짐 싸기', '프로젝트'),
    ];
    return _Play(
      active: active,
      ms: 1100,
      builder: (t) => _Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, r) in rows.indexed)
              _slideIn(
                _stagger(t, i, step: 0.12),
                Padding(
                  padding: EdgeInsets.only(left: r.$1 * 20.0, top: 5, bottom: 5),
                  child: Row(
                    children: [
                      if (r.$1 == 2) const _Dot() else Icon(Icons.expand_more, size: 18, color: Tone.muted(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.$2, style: TextStyle(fontWeight: r.$1 == 0 ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      _Chip(r.$3, color: r.$1 == 2 ? Tone.muted(context) : null),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StagesArt extends StatelessWidget {
  const _StagesArt({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stages = [
      (['후보 3곳 비교', '일정 정하기'], true),
      (['예약하기'], false),
      (['짐 싸기'], false),
    ];
    return _Play(
      active: active,
      ms: 1200,
      builder: (t) => _Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, s) in stages.indexed)
              _slideIn(
                _stagger(t, i, step: 0.22),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == 0 ? scheme.primary : scheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: i == 0 ? scheme.onPrimary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.$2)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '지금 단계 · 동시 진행 가능 2개',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
                                ),
                              ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final x in s.$1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: i == 0 ? scheme.primaryContainer.withValues(alpha: .6) : scheme.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
                                    ),
                                    child: Text(x, style: const TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayArt extends StatelessWidget {
  const _TodayArt({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Play(
      active: active,
      ms: 1700,
      builder: (t) {
        // 둘째 카드가 오른쪽으로 밀리며 완료되는 모습
        final swipe = Curves.easeInOut.transform(((t - 0.35) / 0.4).clamp(0.0, 1.0));
        final back = Curves.easeOut.transform(((t - 0.8) / 0.2).clamp(0.0, 1.0));
        final dx = (swipe - back) * 90;
        final done = t > 0.72;
        Widget card(String title, {bool star = false, bool isDone = false, double offset = 0, double v = 1}) =>
            _slideIn(
              v,
              Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Icon(Icons.check, color: scheme.onPrimary),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(offset, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
                      ),
                      child: Row(
                        children: [
                          _Dot(done: isDone),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: isDone ? TextDecoration.lineThrough : null,
                                color: isDone ? Tone.muted(context) : null,
                              ),
                            ),
                          ),
                          Icon(
                            star ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: star ? Tone.warn(context) : Tone.muted(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
        return SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              card('후보 3곳 비교', star: true, v: _stagger(t, 0, len: 0.25)),
              const SizedBox(height: 8),
              card('일정 정하기', star: true, isDone: done, offset: dx, v: _stagger(t, 1, step: 0.1, len: 0.25)),
              const SizedBox(height: 8),
              card('예약하기', v: _stagger(t, 2, step: 0.1, len: 0.25)),
            ],
          ),
        );
      },
    );
  }
}

class _SyncArt extends StatelessWidget {
  const _SyncArt({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget device(IconData icon, String label) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .5), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: scheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: Tone.muted(context), fontWeight: FontWeight.w600),
        ),
      ],
    );
    return _Play(
      active: active,
      ms: 1400,
      builder: (t) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _slideIn(_stagger(t, 0), device(Icons.smartphone_rounded, '폰 · 위젯')),
          SizedBox(
            width: 80,
            child: Opacity(
              opacity: _stagger(t, 1),
              child: Transform.rotate(
                angle: t * 3.1416 * 2,
                child: Icon(Icons.sync_rounded, size: 34, color: scheme.primary),
              ),
            ),
          ),
          _slideIn(_stagger(t, 2), device(Icons.laptop_mac_rounded, '웹')),
        ],
      ),
    );
  }
}

/// 사용법을 다시 볼 때 쓰는 화면 (메뉴 → 사용법)
Future<void> showOnboarding(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(fullscreenDialog: true, builder: (ctx) => Onboarding(onDone: () => Navigator.of(ctx).pop())),
);

/// 브랜드 확인용: 로그인 화면 머리에 쓰는 로고
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [brandColor, brandDeep],
      ),
      borderRadius: BorderRadius.circular(size * .26),
    ),
    padding: EdgeInsets.all(size * .2),
    child: const StairsLogo(),
  );
}
