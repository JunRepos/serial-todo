/// 여러 줄 붙여넣기 → 트리. 들여쓰기(공백 2칸/탭)나 `-`·`*`·`•`·`1.` 로 단계를 구분한다.
class OutlineNode {
  OutlineNode(this.title);
  final String title;
  final List<OutlineNode> children = [];

  int get count => 1 + children.fold(0, (s, c) => s + c.count);
}

final _bullet = RegExp(r'^([-*•·]|\d+[.)])\s+');
final _checkbox = RegExp(r'^\[[ xX]\]\s*');

List<OutlineNode> parseOutline(String text) {
  final rows = <(int, String)>[];
  for (final raw in text.replaceAll('\r', '').split('\n')) {
    if (raw.trim().isEmpty) continue;
    var spaces = 0;
    var i = 0;
    while (i < raw.length && (raw[i] == ' ' || raw[i] == '\t' || raw[i] == '　')) {
      spaces += raw[i] == '\t' ? 2 : (raw[i] == '　' ? 2 : 1);
      i++;
    }
    var rest = raw.substring(i);
    var depth = spaces ~/ 2;
    final m = _bullet.firstMatch(rest);
    if (m != null) {
      rest = rest.substring(m.end);
      depth += 1;
    }
    rest = rest.replaceFirst(_checkbox, '').trim();
    if (rest.isEmpty) continue;
    rows.add((depth, rest));
  }
  if (rows.isEmpty) return [];
  final minDepth = rows.map((r) => r.$1).reduce((a, b) => a < b ? a : b);

  final roots = <OutlineNode>[];
  final stack = <OutlineNode>[];
  for (final (d0, title) in rows) {
    var d = d0 - minDepth;
    if (d > stack.length) d = stack.length; // 한 번에 두 단계 이상 깊어지지 않게
    final node = OutlineNode(title);
    stack.length = d;
    if (d == 0) {
      roots.add(node);
    } else {
      stack[d - 1].children.add(node);
    }
    stack.add(node);
  }
  return roots;
}
