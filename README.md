# 계열화 To-Do

할 일을 **목표 → 프로젝트 → 액션** 3단계로 쪼개고, 항목 사이의 선행 관계로 실행 순서를 자동 계산하는 To-Do.
안드로이드 앱(홈 화면 위젯 포함)과 웹이 Supabase로 실시간 동기화됩니다.

- 웹: https://junrepos.github.io/serial-todo/
- 안드로이드 APK: [Releases](https://github.com/JunRepos/serial-todo/releases/latest) → `serial-todo.apk`

## 사용

1. 웹이나 앱에서 이메일·비밀번호로 **가입**합니다(이메일 확인 없음). 다른 기기에서는 같은 계정으로 로그인합니다.
2. **구조** 탭: 행의 `+`로 하위 항목을 연속 추가합니다. 여러 줄을 붙여넣으면 들여쓰기(공백 2칸·탭)나 `-` 기준으로 프로젝트·액션이 한 번에 생깁니다.
   액션 행을 오른쪽으로 밀면 완료, 왼쪽으로 밀면 오늘 ★입니다.
3. 항목을 탭하면 편집 시트가 열립니다: 상태, 우선순위, 마감, 오늘 ★, 하위 순차 진행, 선행 항목, 메모, 순서 이동, 삭제(되돌리기 가능).
4. **순서** 탭: 선행 관계로 계산한 실행 단계입니다. 같은 단계는 동시에 진행할 수 있습니다.
5. **오늘** 탭: 오늘 ★ / 바로 할 수 있음 / 대기 중 / 최근 7일 완료.
6. **캘린더** 탭: 마감일별 항목. 항목을 길게 눌러 다른 날짜로 끌어 놓으면 마감이 바뀝니다.

### 안드로이드 설치·위젯

1. Releases에서 `serial-todo.apk`를 폰으로 받아 엽니다. "출처를 알 수 없는 앱" 설치를 허용합니다.
2. 홈 화면을 길게 누름 → 위젯 → **계열화 To-Do · 오늘 할 일**을 추가합니다.
3. 위젯은 오늘 ★ 항목(없으면 바로 할 수 있는 항목)을 최대 5개 보여줍니다. 체크하면 완료되고, 다음에 앱을 열 때 서버에 동기화됩니다.

## 동작 방식

- 모든 변경은 즉시 화면 → 로컬 캐시(`shared_preferences`) → Supabase upsert 순서로 반영됩니다. 실패하면 큐에 두었다가 재연결 시 다시 보냅니다.
- 충돌은 `updated_at` 최신 우선(last-write-wins)입니다. 서버 트리거가 더 오래된 변경을 무시합니다.
- 변경분 가져오기는 서버가 찍는 `synced_at` 기준이라 기기 시계가 달라도 누락되지 않습니다.
- 삭제는 소프트 삭제(`deleted = true`)라 다른 기기에도 전파됩니다.

## 개발

```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

- 스키마: [`supabase/migrations`](supabase/migrations) (`npx supabase db push --remote`)
- 핵심 계산: [`lib/logic/graph.dart`](lib/logic/graph.dart) (테스트: `test/graph_test.dart`)
- CI: `.github/workflows/build-apk.yml`(APK → Release), `deploy-web.yml`(GitHub Pages)

필요한 저장소 Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.
