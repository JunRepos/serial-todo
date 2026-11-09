import 'package:flutter_test/flutter_test.dart';
import 'package:serial_todo/logic/graph.dart';
import 'package:serial_todo/logic/outline.dart';
import 'package:serial_todo/models/item.dart';

/// prototype.html 의 예시 데이터와 같은 구조
List<Item> sample() {
  Item it(String id, String? parent, int level, double sort,
          {bool seq = false, List<String>? deps, String status = 'todo'}) =>
      Item(id: id, parentId: parent, level: level, sort: sort, title: id, seq: seq, deps: deps, status: status);
  return [
    it('g1', null, 0, 1),
    it('p1', 'g1', 1, 1),
    it('a1', 'p1', 2, 1),
    it('a2', 'p1', 2, 2),
    it('a3', 'p1', 2, 3, deps: ['a1', 'a2']),
    it('p2', 'g1', 1, 2, seq: true, deps: ['p1']),
    it('a4', 'p2', 2, 1),
    it('a5', 'p2', 2, 2),
    it('a6', 'p2', 2, 3),
    it('p3', 'g1', 1, 3, seq: true, deps: ['p2']),
    it('a7', 'p3', 2, 1),
    it('a8', 'p3', 2, 2),
  ];
}

Graph withDone(List<Item> items, Set<String> done) {
  for (final i in items) {
    if (done.contains(i.id)) i.status = 'done';
  }
  return Graph(items);
}

void main() {
  group('완료·진행률', () {
    test('하위가 있으면 모든 하위 완료일 때만 완료', () {
      final g = withDone(sample(), {'a1', 'a2'});
      expect(g.isDone('p1'), isFalse);
      expect(g.progress('p1'), 67);
      final g2 = withDone(sample(), {'a1', 'a2', 'a3'});
      expect(g2.isDone('p1'), isTrue);
      expect(g2.progress('g1'), 38); // 3/8
    });

    test('말단 하나짜리 목표', () {
      final g = Graph([Item(id: 'x', title: 'x')]);
      expect(g.progress('x'), 0);
    });
  });

  group('유효 선행·대기', () {
    test('seq 부모면 바로 위 형제가 선행', () {
      final g = Graph(sample());
      expect(g.effDeps('a4'), isEmpty);
      expect(g.effDeps('a5'), ['a4']);
      expect(g.effDeps('a6'), ['a5']);
      expect(g.effDeps('a3').toSet(), {'a1', 'a2'});
    });

    test('상위의 선행도 대기 사유가 된다', () {
      final g = Graph(sample());
      expect(g.blockers('a4'), ['p1']);
      expect(g.blockers('a1'), isEmpty);
      expect(g.blockers('a3').toSet(), {'a1', 'a2'});
      expect(g.blockers('a7'), ['p2']);
    });

    test('선행 완료 후 대기 해제', () {
      final g = withDone(sample(), {'a1', 'a2', 'a3'});
      expect(g.blockers('a4'), isEmpty);
      expect(g.blockers('a5'), ['a4']);
    });

    test('삭제된 항목은 무시', () {
      final items = sample();
      items.firstWhere((e) => e.id == 'a1').deleted = true;
      final g = Graph(items);
      expect(g['a1'], isNull);
      expect(g.effDeps('a3'), ['a2']);
    });
  });

  group('실행 단계', () {
    test('프로토타입과 같은 단계', () {
      final g = Graph(sample());
      final r = g.sequenceOf('g1');
      expect(r.cyc, isEmpty);
      expect(r.stages, [
        ['a1', 'a2'],
        ['a3'],
        ['a4'],
        ['a5'],
        ['a6'],
        ['a7'],
        ['a8'],
      ]);
    });

    test('순환 감지', () {
      final items = [
        Item(id: 'g', title: 'g'),
        Item(id: 'x', parentId: 'g', level: 1, sort: 1, title: 'x', deps: ['y']),
        Item(id: 'y', parentId: 'g', level: 1, sort: 2, title: 'y', deps: ['x']),
      ];
      final r = Graph(items).sequenceOf('g');
      expect(r.cyc, isNotEmpty);
    });

    test('reaches 로 순환 후보 판별', () {
      final g = Graph(sample());
      // a3은 a1에 의존 → a1의 선행으로 a3을 고르면 순환
      expect(g.reaches('a3', 'a1'), isTrue);
      expect(g.reaches('a1', 'a3'), isFalse);
    });
  });

  group('선행 후보', () {
    test('액션은 같은 목표 안, 자기·상위·하위 제외', () {
      final items = sample()..add(Item(id: 'g2', sort: 2, title: 'g2'));
      final g = Graph(items);
      final c = g.depCandidates('a4').map((e) => e.id).toList();
      expect(c, isNot(contains('a4')));
      expect(c, isNot(contains('p2')));
      expect(c, isNot(contains('g1')));
      expect(c, isNot(contains('g2')));
      expect(c, containsAll(['p1', 'a1', 'a5', 'p3', 'a7']));
    });

    test('목표는 다른 목표만', () {
      final items = sample()..add(Item(id: 'g2', sort: 2, title: 'g2'));
      final g = Graph(items);
      expect(g.depCandidates('g1').map((e) => e.id), ['g2']);
    });
  });

  group('오늘 목록', () {
    test('대기·바로·오늘 분류', () {
      final items = sample();
      items.firstWhere((e) => e.id == 'a2').today = true;
      final l = Graph(items).todayLists();
      expect(l.today.map((e) => e.id), ['a2']);
      expect(l.ready.map((e) => e.id), ['a1']);
      expect(l.wait.map((e) => e.id), ['a3', 'a4', 'a5', 'a6', 'a7', 'a8']);
    });
  });

  group('dday', () {
    test('오늘·지남·남음', () {
      final now = DateTime(2026, 3, 10, 23, 30);
      expect(dday('2026-03-10', now: now), 0);
      expect(dday('2026-03-08', now: now), -2);
      expect(dday('2026-04-01', now: now), 22);
      expect(ddayLabel(-2), '2일 지남');
    });
  });

  group('여러 줄 붙여넣기', () {
    test('들여쓰기 2칸으로 단계 구분', () {
      final r = parseOutline('시장 조사\n  경쟁사 A 홈페이지 분석\n  경쟁사 B 가격표 정리\n기획서 초안\n  목차 구성\n');
      expect(r.map((e) => e.title), ['시장 조사', '기획서 초안']);
      expect(r[0].children.map((e) => e.title), ['경쟁사 A 홈페이지 분석', '경쟁사 B 가격표 정리']);
      expect(r[1].children.single.title, '목차 구성');
    });

    test('- 와 탭', () {
      final r = parseOutline('A\n- a1\n- a2\nB\n\t- b1\n');
      expect(r.length, 2);
      expect(r[0].children.length, 2);
      expect(r[1].children.single.title, 'b1');
    });

    test('모두 - 로 시작하면 같은 단계', () {
      final r = parseOutline('- x\n- y\n  - y1');
      expect(r.map((e) => e.title), ['x', 'y']);
      expect(r[1].children.single.title, 'y1');
    });

    test('갑자기 깊어져도 한 단계씩만', () {
      final r = parseOutline('A\n      deep');
      expect(r.single.children.single.title, 'deep');
    });
  });
}
