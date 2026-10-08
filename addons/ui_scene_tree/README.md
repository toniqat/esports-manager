# addons/ui_scene_tree — UI 트리 독

에디터 왼쪽 위(Scene 탭 옆) **"UI 트리" / "UI Tree"** 탭. UI 씬 구조와 `editor_description` 마킹을 한 눈에 본다
(규칙: `docs/ui_scene_migration.md` §3 규칙 5 · 9 · 10). 글자는 에디터 언어가 `ko*` 면 한국어, 아니면 영어
(`ui_scene_tree_dock.gd` `_STRINGS` — 문구를 바꾸면 두 언어 모두).

| 파일 | 역할 |
|---|---|
| `plugin.cfg` · `plugin.gd` | EditorPlugin 껍데기 — 독을 `DOCK_SLOT_LEFT_UR` 에 붙이고, 씬 저장 · 파일시스템 변경을 독의 `request_refresh()` 에 연결 |
| `ui_scene_tree_dock.gd` | 독 화면 — 필터 · TODO만 토글 · 다시 읽기, 3열 `Tree`(헤더 없음), 우클릭 메뉴, 펼침 상태 기억 (갱신은 0.4초 디바운스) |
| `assign_uids_cli.gd` | 헤드리스 도구: 헤더에 uid 가 없는 `.tscn` 첫 줄에 `ResourceUID.create_id()` uid 를 넣는다 (아래 "uid 채우기") |
| `ui_scene_scanner.gd` | 스캔 로직 (순수 RefCounted, 헤드리스 가능) — `.tscn` · `.gd` 텍스트를 직접 파싱 (`addons/` · `build/` · `ios/` 제외) |

## 화면
- **루트** = 진입 씬 `scenes/*.tscn` (▶ 아이콘) → `UI_View_*` 전부. 그 아래:
  - **인스턴스** — 씬 파일에 들어 있는 UI 씬 (`×n` = 인스턴스 수, 서로 담으면 `(순환)`)
  - **코드 생성** (스크립트 아이콘 · 흐린 글자) — 그 씬 노드에 붙은 `.gd` 가 만드는 UI 씬. 판정:
    ① `.gd` 가 `"res://…/UI_X.tscn"` 경로 문자열을 가짐(preload · `SCENE_PATH`), 또는
    ② 팩토리 — Comp 에 붙은 스크립트가 제 씬을 부르고(`class_name Xxx` + 제 경로), 다른 `.gd` 가 `Xxx.create(` 를 부름.
    진입 씬은 코드 생성 대상이 아니다(화면 전환 경로라서). 이미 인스턴스로 들어 있으면 코드 생성으로 다시 달지 않는다.
    그 씬에 붙은 스크립트 자신의 경로 참조(팩토리, 같은 스크립트를 쓰는 변형 씬 목록: `BaseMap.gd` 의 맵 12장)는
    부모로 치지 않는다. 치면 변형끼리 완전 그래프가 되어 트리 항목이 폭발하고 에디터가 시작 때 멈춘다.
- 맨 아래 **"씬에 포함 안 된 Comp"** 그룹 — 인스턴스도 코드 생성도 아닌 `UI_Comp_*` (`[코드]` = 어느 씬에도
  안 붙은 헬퍼 스크립트만 참조, `[미사용]` = 참조 없음). 지금 0개.
- **오른쪽 두 열** (헤더 없음, 아이콘으로 구분)
  - ⚠ TODO — 설명의 어느 줄이든 `TODO` 로 시작하는 노드 수. `(+n)` = 아래 씬들의 합(같은 씬은 한 번).
    마우스 → 노드 경로 + TODO 줄.
  - 노드 — 그 씬 루트 아래 노드 수 (인스턴스 노드는 1개, 그 속은 원본 씬 몫). 마우스 → 노드 경로 10개 + "외 n개".
- 이름 열 툴팁 = 경로 · 포함하는 씬 · 코드로 만드는 씬 · 코드 참조.
- **더블클릭** = 씬 열기 + Scene 탭으로 전환. **우클릭** = 모두 접기 · 모두 펼치기 · 이 씬 펼치기/접기(하위 전체) ·
  FileSystem 에서 보기. 빈 곳 우클릭 = 모두 접기 · 펼치기만.

## uid 채우기 (`assign_uids_cli.gd`)
텍스트로 만든 씬(코드 · LLM)은 에디터로 열어 저장하기 전까지 헤더에 uid 가 없다. 에디터를 켜지 않고:

```
godot --headless --path . -s res://addons/ui_scene_tree/assign_uids_cli.gd            # 채우기
godot --headless --path . -s res://addons/ui_scene_tree/assign_uids_cli.gd -- --dry   # 목록만
```

- 첫 줄 `[gd_scene …]` 에만 `uid="uid://…"` 를 더한다. 나머지 바이트는 그대로라 diff 는 파일마다 한 줄.
- 대상: 프로젝트 전체 `.tscn` (`addons/` · `build/` · `ios/` · 숨김 폴더 제외). uid 가 이미 있는 파일은 건드리지 않는다.
- 다음 `--import` (또는 에디터 스캔)가 uid 를 등록한다. 경로로 참조하던 씬 · 스크립트는 그대로 동작한다.

## 한계
- 씬 계층만 보인다(일반 노드는 툴팁으로).
- 코드 생성 판정은 텍스트 일치 — `uid://` 로 불러오거나 `create()` 가 아닌 이름의 팩토리는 못 잡는다.
  주석 · 미리보기 코드에 경로가 적혀 있어도 코드 생성으로 잡힌다.
- 같은 씬이 여러 부모 아래 반복해서 보인다(Scene 탭과 달리 "어디에 쓰이나" 를 다 보여 주기 위해).
