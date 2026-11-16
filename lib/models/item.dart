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

  static const levelNames = ['목표', '프로젝트', '액션', '일정'];

  /// 일정은 할 일 트리 밖에 있는 항목이다. level 3으로 구분하고 날짜는 [due]에 둔다.
  static const eventLevel = 3;
  bool get isEvent => level == eventLevel;

  // 일정의 부가 정보는 일정에서 쓰지 않는 [deps]에 'key=value' 로 담는다(스키마 변경 없이 동기화).
  //   t=HH:mm 시작 시각(없으면 하루 종일) · e=HH:mm 끝 시각 · end=yyyy-MM-dd 끝 날짜
  //   loc=장소 · rem=알림(시작 몇 분 전, 하루 종일이면 그날 09:00 기준)
  String? attr(String key) {
    if (!isEvent) return null;
    final p = '$key=';
    for (final d in deps) {
      if (d.startsWith(p)) return d.substring(p.length);
    }
    return null;
  }

  void setAttr(String key, String? value) {
    final p = '$key=';
    deps = [
      for (final d in deps)
        if (!d.startsWith(p)) d,
      if (value != null && value.isNotEmpty) '$p$value',
    ];
  }

  String? get startTime => attr('t');
  String? get endTime => attr('e');
  String? get endDate => attr('end');
  String get location => attr('loc') ?? '';
  int? get remindMinutes => int.tryParse(attr('rem') ?? '');

  /// 달력 칸에 쓰는 한 줄: 시각이 있으면 앞에 붙인다
  String get chipTitle => startTime == null ? title : '$startTime $title';

  /// 시작 일시(하루 종일이면 그날 09:00). 알림 계산용.
  DateTime? get eventStart {
    final d = DateTime.tryParse(due ?? '');
    if (d == null) return null;
    final t = startTime?.split(':');
    final h = t == null ? 9 : int.tryParse(t[0]) ?? 9, m = t == null || t.length < 2 ? 0 : int.tryParse(t[1]) ?? 0;
    return DateTime(d.year, d.month, d.day, h, m);
  }

  /// 알림이 울릴 시각
  DateTime? get remindAt {
    final r = remindMinutes, s = eventStart;
    return r == null || s == null ? null : s.subtract(Duration(minutes: r));
  }

  /// "14:00–15:00 · 장소" 같은 한 줄 요약
  String get eventSummary {
    final parts = <String>[
      if (startTime != null) endTime == null ? startTime! : '$startTime–$endTime' else '하루 종일',
      if (endDate != null && endDate != due) '~ ${endDate!.substring(5).replaceAll('-', '/')}',
      if (location.isNotEmpty) location,
    ];
    return parts.join(' · ');
  }

  static const priorityNames = {1: '높음', 2: '보통', 3: '낮음'};

  String get levelName => levelNames[level.clamp(0, 3)];

  Item copy() => Item.fromJson(toJson());

  /// 고친 시각을 찍는다. 기기 시계가 다른 기기보다 느려도 이 변경이 서버에서 버려지지 않도록
  /// 직전 값보다는 반드시 뒤가 되게 한다.
  void touch() {
    final now = DateTime.now().toUtc();
    final min = updatedAt.add(const Duration(milliseconds: 1));
    updatedAt = now.isAfter(min) ? now : min;
  }

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
