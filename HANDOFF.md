# 계열화 To-Do — 앱·웹 개발 인계서

Claude Code에 이 파일과 `prototype.html`을 함께 넘기고 "HANDOFF.md 대로 구현해줘"라고 요청하면 됩니다.

> **작업 원칙 (Claude Code에게)**
> 사용자는 필요한 권한을 모두 열어 두었다. 저장소 생성, Supabase 설정, Secrets 등록, Pages 설정, 빌드·배포까지 **사용자에게 맡기지 말고 직접 실행**한다(`gh`, `supabase` CLI, 관련 MCP·API 등 가능한 수단 사용).
> 일단 시도하고, 권한·인증 문제로 실패했을 때만 무엇이 왜 막혔는지와 필요한 권한을 구체적으로 사용자에게 요청한다. 중간 확인 질문은 최소화한다.

---

## 1. 목표

할 일을 **목표 → 프로젝트 → 액션** 3단계로 쪼개고, 항목 사이의 선행 관계로 실행 순서를 자동 계산하는 To-Do.
**안드로이드 앱(홈 화면 위젯 포함)** 과 **웹사이트**를 만들고, 두 곳의 데이터가 실시간으로 동기화되어야 한다.

- 사용자: 1명(본인). 안드로이드 폰 + PC 브라우저.
- 참고 구현: `prototype.html` (claude.ai 아티팩트로 만든 단일 HTML 프로토타입). 로직·화면 구성은 이걸 기준으로 하되, 아래 변경 사항을 반영한다.

## 2. 프로토타입 대비 변경 요청

| # | 요청 | 구현 방향 |
|---|---|---|
| 1 | 예상 시간 기능 제거 | `est` 필드, 시간 합계 배지, 입력란 모두 삭제 |
| 2 | 자동 저장 | 변경 즉시 저장. 저장 버튼 없음. 오프라인에서도 로컬에 저장 후 온라인 시 동기화 |
| 3 | 앱·웹 연동 | Supabase(로그인 + DB + Realtime)로 동기화 |
| 4 | 홈 화면 위젯 | 안드로이드 위젯: 오늘 할 일 목록 표시 |
| 5 | UI/UX 개선 | 모바일 우선. 아래 4장 참고 |
| 6 | 하위 항목 쉽게 생성 | 아래 4-2 참고 |
| 7 | 캘린더 보기 | 마감일 기준 월간 캘린더 탭 추가 |

## 3. 기술 구성

- **Flutter** (Android + Web 한 코드베이스)
- **Supabase**: 이메일+비밀번호 로그인, `items` 테이블, Realtime 구독
- **home_widget** 패키지 + Kotlin `AppWidgetProvider` (안드로이드 위젯)
- 상태관리: 단순하게 (`ChangeNotifier` 또는 Riverpod 중 택1)
- 로컬 캐시: `shared_preferences` 또는 `hive`에 전체 items JSON + 미전송 변경 큐
- **GitHub 저장소**: `JunRepos/serial-todo` (공개, 사용자가 생성)
- **GitHub Actions**
  - `build-apk.yml`: push 시 release APK 빌드 → Actions 아티팩트 및 GitHub Release로 업로드
  - `deploy-web.yml`: push 시 `flutter build web --base-href /serial-todo/` → GitHub Pages 배포
  - Supabase URL·anon key는 저장소 Secrets(`SUPABASE_URL`, `SUPABASE_ANON_KEY`) → `--dart-define`으로 주입

> 참고: 이전 작업 환경(claude.ai 클라우드)에서는 Flutter SDK·pub.dev·Android SDK 다운로드가 막혀 있어 로컬 빌드를 못 했다. 로컬에 Flutter가 있으면 `flutter analyze` / `flutter build apk`로 검증할 것.

## 4. 기능 명세

### 4-1. 데이터 모델

`items` 한 테이블로 3단계를 모두 표현.

| 필드 | 타입 | 설명 |
|---|---|---|
| id | text (pk) | 클라이언트 생성 UUID |
| user_id | uuid | `auth.uid()` 기본값 |
| parent_id | text null | 상위 항목. 목표는 null |
| level | int | 0 목표 / 1 프로젝트 / 2 액션 |
| sort | double | 형제 간 순서 (중간 삽입 쉽게 double) |
| title | text | |
| status | text | `todo` / `doing` / `done` (하위 없는 항목만 의미 있음) |
| priority | int | 1 높음 / 2 보통 / 3 낮음, 기본 2 |
| due | date null | 마감일 |
| deps | text[] | 선행 항목 id 목록 |
| seq | bool | true면 하위 항목을 위에서부터 순서대로 진행 |
| today | bool | 오늘 할 일 표시(★) |
| note | text | 메모 |
| done_at | timestamptz null | 완료 시각 |
| updated_at | timestamptz | 충돌 시 최신 우선(last-write-wins) |
| deleted | bool | 소프트 삭제 (동기화용) |

```sql
create table public.items (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  parent_id text,
  level int not null default 0,
  sort double precision not null default 0,
  title text not null default '',
  status text not null default 'todo',
  priority int not null default 2,
  due date,
  deps text[] not null default '{}',
  seq boolean not null default false,
  today boolean not null default false,
  note text not null default '',
  done_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
alter table public.items enable row level security;
create policy "own rows" on public.items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
alter publication supabase_realtime add table public.items;
create index on public.items (user_id, updated_at);
```

### 4-2. 핵심 로직 (prototype.html의 `effDeps`, `blockers`, `sequenceOf` 참고)

- **완료 판정**: 하위가 없으면 `status == done`. 하위가 있으면 모든 하위가 완료일 때 완료.
- **진행률**: 하위 말단(leaf) 중 완료 비율.
- **유효 선행(effDeps)**: 명시한 `deps` + (부모가 `seq`이면 바로 위 형제).
- **대기(blocked)**: 자기 자신과 모든 상위 항목의 유효 선행 중 하나라도 미완료면 대기.
- **실행 단계(stage)**: 목표 하나 안의 말단 항목들로 그래프를 만든다. 말단 L의 선행 = L과 그 상위(목표 제외)의 유효 선행 각각의 말단들. stage = 선행 stage 최댓값 + 1. 같은 stage는 동시 진행 가능. 순환은 감지해서 경고 표시.
- **선행 선택 제한**: 액션·프로젝트는 같은 목표 안의 항목만, 목표는 다른 목표만. 자기 자신·상위·하위는 제외. 순환을 만드는 후보는 비활성화.
- 삭제 시 하위 전체 삭제 + 다른 항목의 `deps`에서 제거.

### 4-3. 화면 (하단 탭 4개, 웹 넓은 화면에서는 왼쪽 레일)

1. **구조**: 트리. 접기/펼치기, 체크박스(말단), 진행률 바(상위), 배지(우선·마감 D-day·순차·대기 사유).
2. **순서**: 목표별 실행 단계 타임라인. 현재 단계 강조, 같은 단계는 "동시 진행 가능" 표시.
3. **오늘**: 오늘(★) / 바로 할 수 있음(대기 아님, 우선순위→마감→stage 순) / 대기 중(무엇을 기다리는지) / 최근 7일 완료.
4. **캘린더**: 월간 달력. 날짜 칸에 그 날 마감인 항목 점·개수 표시, 지난 마감 미완료는 빨간색. 날짜 탭 → 그 날 항목 목록. 항목 길게 눌러 다른 날로 이동하거나 편집 시트에서 마감 변경. 상단에 "마감 없는 항목 n개" 바로가기.

**편집**: 항목 탭 → 바텀시트. 제목, 상태, 우선순위, 마감(날짜 선택기), 오늘 표시, 순차 진행(상위만), 선행 항목(검색 가능한 체크 목록), 메모, 위/아래 이동, 삭제(되돌리기 스낵바).

### 4-4. 하위 항목 쉽게 만들기

- 각 상위 행에 **+ 버튼** → 바로 아래 인라인 입력. Enter로 추가 후 입력창 유지(연속 추가), 빈 상태 Enter/Esc로 닫기.
- **여러 줄 붙여넣기**: 입력창에 여러 줄을 붙여넣으면 줄마다 항목 생성. 들여쓰기(공백 2칸/탭)나 `-`로 단계 구분 → 프로젝트·액션을 한 번에 생성.
  ```
  시장 조사
    경쟁사 A 홈페이지 분석
    경쟁사 B 가격표 정리
  기획서 초안
    목차 구성
  ```
- 액션 행에서 **스와이프**: 오른쪽 = 완료, 왼쪽 = 오늘(★) 토글.
- 상위 항목 편집 시트의 "하위 순차 진행" 토글로 선행 관계를 한 번에 설정.
- 하단 FAB: 현재 탭 맥락에 맞게 추가(구조 탭=목표, 캘린더 탭=선택 날짜 마감 액션 + 상위 선택).

### 4-5. 자동 저장·동기화

- 모든 변경은 즉시 로컬 상태 반영 → 로컬 캐시 저장 → Supabase upsert. 실패 시 큐에 보관, 재연결 시 재전송.
- 앱 시작: 캐시로 즉시 화면 표시 → 서버에서 `updated_at > 마지막 동기화` 변경분 가져오기 → Realtime 구독.
- 충돌: `updated_at` 최신 우선.
- 상단에 작은 동기화 상태 표시(동기화됨 / 오프라인 · 대기 n건).

### 4-6. 안드로이드 위젯

- 크기: 2×2 이상 리사이즈 가능. 다크/라이트 대응.
- 내용: "오늘" 제목 + 남은 개수, 오늘(★) 항목 최대 5개(없으면 "바로 할 수 있음" 상위 5개), 마감 D-day 표시.
- 탭: 앱 열기(항목 탭 시 해당 항목 편집 시트로 이동하면 더 좋음).
- 체크 버튼으로 위젯에서 바로 완료 처리 (home_widget 백그라운드 콜백 → 로컬 반영 + 동기화 큐). 어려우면 1차는 표시 전용으로.
- 앱에서 데이터가 바뀔 때마다 `HomeWidget.saveWidgetData` + `updateWidget`. WorkManager로 30분마다 서버 변경분 받아 위젯 갱신(선택).

### 4-7. UI/UX 원칙

- 모바일 우선, 터치 영역 44px 이상, 다크모드.
- 글자는 간결하게. 안내 문구 최소화.
- 폰트: Pretendard(또는 IBM Plex Sans KR). 포인트 컬러 1개(프로토타입의 짙은 녹색 #2E5B4E).
- 빈 상태엔 다음 행동 하나만 제시.
- 첫 실행 시 예시 목표 1개(신제품 기획서 작성) 생성, 삭제 쉽게.

## 5. 설정·배포 (Claude Code가 직접 실행)

1. GitHub에 `JunRepos/serial-todo` 공개 저장소 생성 (`gh repo create`).
2. Supabase 프로젝트 생성 → 4-1 SQL 실행 → Authentication의 "Confirm email" 끄기 → Project URL·anon key 확보 (`supabase` CLI 또는 Management API).
3. 저장소 Secrets에 `SUPABASE_URL`, `SUPABASE_ANON_KEY` 등록 (`gh secret set`). Pages Source를 GitHub Actions로 설정 (`gh api`).
4. Supabase Authentication → URL Configuration에 Pages 주소(`https://junrepos.github.io/serial-todo/`) 추가.
5. push 후 Actions 두 워크플로 성공 확인, 실패하면 로그 보고 수정해 재실행.
6. 막히는 단계가 있으면 그 단계만 사용자에게 권한·로그인 요청.

**사용자가 마지막에 할 일**: GitHub Release에서 APK 받아 폰에 설치(출처를 알 수 없는 앱 허용) → 홈 화면에 위젯 추가. Claude Code는 이 방법과 웹사이트 주소, 로그인 방법을 짧게 안내하고 끝낸다.

## 6. 완료 기준

- [ ] 웹(GitHub Pages)과 안드로이드 앱에서 같은 계정으로 로그인하면 같은 목록이 보인다.
- [ ] 한쪽에서 체크하면 다른 쪽에 몇 초 안에 반영된다.
- [ ] 비행기 모드에서 수정 → 네트워크 복구 후 서버에 반영된다.
- [ ] 위젯에 오늘 할 일이 보이고, 앱에서 바꾸면 위젯도 갱신된다.
- [ ] 캘린더에서 마감일별 항목을 보고 마감을 바꿀 수 있다.
- [ ] 여러 줄 붙여넣기로 프로젝트+액션이 한 번에 생성된다.
- [ ] 선행 관계·순차 진행에 따라 "대기" 표시와 "순서" 탭 단계가 프로토타입과 같게 계산된다.
- [ ] 예상 시간 관련 UI가 남아 있지 않다.
- [ ] `flutter analyze` 경고 없음, Actions 두 워크플로 모두 성공.

## 7. 권장 파일 구조

```
lib/
  main.dart                 Supabase·위젯 초기화
  models/item.dart
  data/repository.dart      캐시·큐·Realtime
  logic/graph.dart          완료·대기·단계 계산 (단위 테스트 작성)
  ui/shell.dart             탭/레일
  ui/tree_page.dart
  ui/sequence_page.dart
  ui/today_page.dart
  ui/calendar_page.dart
  ui/item_sheet.dart
  ui/quick_add.dart         인라인·여러 줄 입력 파서
  ui/auth_page.dart
  widget/widget_sync.dart
android/app/src/main/kotlin/.../TodayWidgetProvider.kt
android/app/src/main/res/layout/today_widget.xml
android/app/src/main/res/xml/today_widget_info.xml
test/graph_test.dart
.github/workflows/build-apk.yml
.github/workflows/deploy-web.yml
README.md                   설치·설정 안내
```
