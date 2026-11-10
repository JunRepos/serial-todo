// ignore_for_file: invalid_use_of_visible_for_testing_member
// Play 스토어 스크린샷 생성 (1080×1920, 9:16).
//   flutter test tool/store/store_shots_test.dart --dart-define=STORE_SHOTS=true
// 실제 앱 화면을 예시 데이터로 그린 뒤 브랜드 배경·설명 문구와 합쳐 store/screenshots/ 에 PNG로 저장한다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serial_todo/data/repository.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/models/item.dart';
import 'package:serial_todo/ui/app_scope.dart';
import 'package:serial_todo/ui/brand.dart';
import 'package:serial_todo/ui/onboarding.dart';
import 'package:serial_todo/ui/shell.dart';
import 'package:serial_todo/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _enabled = bool.fromEnvironment('STORE_SHOTS');

Future<void> _loadFonts() async {
  final pre = FontLoader('Pretendard');
  for (final w in ['Regular', 'SemiBold', 'Bold']) {
    pre.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Pretendard-$w.otf').readAsBytesSync())));
  }
  await pre.load();
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

List<Item> _sample() {
  final now = DateTime.now();
  String d(int days) => dateKey(now.add(Duration(days: days)));
  final items = <Item>[];
  Item add(
    String id,
    String? parent,
    int level,
    double sort,
    String title, {
    String status = 'todo',
    bool seq = false,
    List<String>? deps,
    bool today = false,
    String? due,
    int pri = 2,
  }) {
    final it = Item(
      id: id,
      parentId: parent,
      level: level,
      sort: sort,
      title: title,
      status: status,
      seq: seq,
      deps: deps,
      today: today,
      due: due,
      priority: pri,
      doneAt: status == 'done' ? now.toUtc() : null,
    );
    items.add(it);
    return it;
  }

  add('g1', null, 0, 1, '제주 여행 준비', due: d(12), pri: 1);
  add('p1', 'g1', 1, 1, '항공·숙소 예약', seq: true);
  add('a1', 'p1', 2, 1, '항공권 가격 비교', status: 'done');
  add('a2', 'p1', 2, 2, '숙소 후보 3곳 고르기', today: true, due: d(1));
  add('a3', 'p1', 2, 3, '숙소 예약하기', due: d(3));
  add('p2', 'g1', 1, 2, '일정 짜기', deps: ['p1']);
  add('a4', 'p2', 2, 1, '가고 싶은 곳 목록');
  add('a5', 'p2', 2, 2, '동선 정리');
  add('p3', 'g1', 1, 3, '짐 싸기', deps: ['p2']);
  add('a6', 'p3', 2, 1, '준비물 체크리스트');
  add('g2', null, 0, 2, '블로그 글 쓰기', due: d(5));
  add('a7', 'g2', 1, 1, '주제 정하기', today: true, status: 'doing', due: d(0));
  add('a8', 'g2', 1, 2, '초안 쓰기', deps: ['a7']);
  add('a9', 'g2', 1, 3, '사진 고르기', today: true);
  add('a10', 'g2', 1, 4, '발행하기', deps: ['a8', 'a9'], due: d(5));
  add('g3', null, 0, 3, '건강 챙기기');
  add('a11', 'g3', 1, 1, '헬스장 등록 알아보기', due: d(4), pri: 1);
  add('a12', 'g3', 1, 2, '주 3회 러닝 계획 세우기', due: d(0));
  add('a13', 'g3', 1, 3, '물 2L 마시기', status: 'done');
  return items;
}

class _Shot extends StatelessWidget {
  const _Shot({required this.title, required this.sub, required this.child});
  final String title, sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 360,
        height: 640,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [brandColor, brandDeep],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              style: const TextStyle(fontFamily: 'Pretendard', color: brandMint, fontSize: 15),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: Container(
                width: 296,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: 360, height: 640, child: child),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    await _loadFonts();
  });

  final shots = [
    ('01-tree', '큰 목표를 작게 쪼개요', '목표 → 프로젝트 → 액션', 0),
    ('02-sequence', '순서는 앱이 계산해요', '선행 관계로 실행 단계를 자동 정리', 1),
    ('03-today', '오늘 할 일에 집중', '★ 고르고, 바로 할 수 있는 일부터', 2),
    ('04-calendar', '마감은 캘린더로', '길게 눌러 끌면 마감 변경', 3),
  ];

  for (final (name, title, sub, tab) in shots) {
    testWidgets('스크린샷 $name', skip: !_enabled, (t) async {
      t.view.physicalSize = const Size(1080, 1920);
      t.view.devicePixelRatio = 3;
      debugDisableShadows = false;
      debugDisableShadows = false; // 테스트 기본값(그림자=검은 테두리) 대신 실제 그림자
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({'ui_tab': tab});
      final prefs = await SharedPreferences.getInstance();
      final repo = Repository(
        prefs,
        SupabaseClient('http://localhost:1', 'x', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      )..debugLoad('u', _sample());
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            locale: const Locale('ko'),
            supportedLocales: const [Locale('ko')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: _Shot(
              title: title,
              sub: sub,
              child: AppScope(repo: repo, prefs: prefs, child: const Shell()),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      await _save(t, key, name);
      await repo.stop();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    });
  }

  testWidgets('스크린샷 05-onboarding', skip: !_enabled, (t) async {
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 3;
    debugDisableShadows = false;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: _Shot(
            title: '처음이어도 쉬워요',
            sub: '4장으로 끝내는 사용법',
            child: Onboarding(onDone: () {}),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await _save(t, key, '05-onboarding');
  });
}

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final f = File('store/screenshots/$name.png')..parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes!);
  debugDisableShadows = true;
}
