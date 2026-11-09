/// 목표(0) → 프로젝트(1) → 액션(2) 3단계를 한 테이블로 표현하는 항목.
class Item {
  Item({
    required this.id,
    this.parentId,
    this.level = 0,
    this.sort = 0,
    this.title = '',
    this.status = 'todo',
    this.priority = 2,
    this.due,
    List<String>? deps,
    this.seq = false,
    this.today = false,
    this.note = '',
    this.doneAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : deps = deps ?? <String>[],
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String? parentId;
  int level;
  double sort;
  String title;

  /// todo / doing / done
  String status;

  /// 1 높음 / 2 보통 / 3 낮음
  int priority;

  /// 'yyyy-MM-dd' 형식의 마감일
  String? due;
  List<String> deps;
  bool seq;
  bool today;
  String note;
  DateTime? doneAt;
  DateTime updatedAt;
  bool deleted;

  static const levelNames = ['목표', '프로젝트', '액션'];
  static const priorityNames = {1: '높음', 2: '보통', 3: '낮음'};

  String get levelName => levelNames[level.clamp(0, 2)];

  Item copy() => Item.fromJson(toJson());

  void touch() => updatedAt = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'id': id,
    'parent_id': parentId,
    'level': level,
    'sort': sort,
    'title': title,
    'status': status,
    'priority': priority,
    'due': due,
    'deps': deps,
    'seq': seq,
    'today': today,
    'note': note,
    'done_at': doneAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as String,
    parentId: j['parent_id'] as String?,
    level: (j['level'] as num?)?.toInt() ?? 0,
    sort: (j['sort'] as num?)?.toDouble() ?? 0,
    title: (j['title'] as String?) ?? '',
    status: (j['status'] as String?) ?? 'todo',
    priority: (j['priority'] as num?)?.toInt() ?? 2,
    due: _date(j['due']),
    deps: (j['deps'] as List?)?.map((e) => e.toString()).toList() ?? [],
    seq: j['seq'] == true,
    today: j['today'] == true,
    note: (j['note'] as String?) ?? '',
    doneAt: _ts(j['done_at']),
    updatedAt: _ts(j['updated_at']),
    deleted: j['deleted'] == true,
  );

  static String? _date(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toUtc();
  }
}
