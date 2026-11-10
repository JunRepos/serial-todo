import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serial_todo/ui/brand.dart';
import 'package:serial_todo/ui/onboarding.dart';
import 'package:serial_todo/ui/theme.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    for (final b in Brightness.values) {
      testWidgets('사용법 4장을 넘기고 시작하기 ${size.width.toInt()} ${b.name}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var done = false;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(b),
            home: Onboarding(onDone: () => done = true),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('큰 목표를 작게 쪼개요'), findsOneWidget);
        for (final title in ['순서는 앱이 계산해요', '오늘 할 일에 집중', '어디서나 이어서']) {
          await t.tap(find.text('다음'));
          await t.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
        }
        expect(find.text('시작하기'), findsOneWidget);
        await t.tap(find.text('시작하기'));
        expect(done, isTrue);
      });
    }
  }

  testWidgets('건너뛰기', (t) async {
    var done = false;
    await t.pumpWidget(MaterialApp(home: Onboarding(onDone: () => done = true)));
    await t.pumpAndSettle();
    await t.tap(find.text('건너뛰기'));
    expect(done, isTrue);
  });

  testWidgets('시작 애니메이션이 끝나면 본 화면만 남는다', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: IntroSplash(child: Scaffold(body: Text('본 화면'))),
      ),
    );
    expect(find.text(appName), findsOneWidget);
    // 등장 1.3초 + 머무름 0.25초 + 사라짐 0.38초
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text(appName), findsNothing);
    expect(find.text('본 화면'), findsOneWidget);
  });

  testWidgets('탭하면 시작 애니메이션을 건너뛴다', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: IntroSplash(child: Scaffold(body: Text('본 화면'))),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(const Offset(200, 300));
    // 사라지는 애니메이션(0.38초) 동안 프레임을 돌린다
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(appName), findsNothing);
    // 남은 등장 애니메이션·대기 타이머 정리
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  });
}
