# addons/l10n_tool/ — 현지화 도구 (에디터 플러그인 + 헤드리스)

사양: **`docs/localization_design.md`** (확정 사항 §0.5 가 본문보다 우선). 이 README 는 파일 지도와 모듈 계약이다.

## 실행

| 경로 | 방법 |
|---|---|
| 에디터 | **Project → Tools → L10n** (build dev · build release · validate · scan · sync), 조회 도크(오른쪽 위) |
| 헤드리스 | `godot --headless --path . --script res://addons/l10n_tool/cli.gd -- <명령>` — 인자 없이 실행하면 사용법 |
| 테스트 | `godot --headless --path . --script res://addons/l10n_tool/tests/run_tests.gd [-- <파일 이름 필터>]` |

Windows 에서는 콘솔 실행 파일(`Godot_v4.5-stable_win64_console.exe`)을 써야 출력이 보인다.

## 파일

| 파일 | 역할 |
|---|---|
| `plugin.cfg` · `plugin.gd` | 메뉴 · 도크 등록만. 도크는 `dock/l10n_dock.tscn` 이 있으면 붙인다(`setup(plugin)` 호출) |
| `cli.gd` | 헤드리스 진입점 → `L10n.run_cli` |
| `core/l10n.gd` | **명령 파사드** — `cmd_new_key` · `cmd_add_locale` · `cmd_sync` · `cmd_approve` · `cmd_rename_alias` · `cmd_scan` · `cmd_validate` · `cmd_build` · `cmd_extract`. 상태: `config` · `catalog` · `issues` · `index` |
| `core/config.gd` | `data/l10n/config.json`. 경로는 config 위치 기준(`src/` · `generated/`), `scan.roots` · `data_csv_dir` 의 상대 경로도 config 폴더 기준. `expand_alias()` = data_columns alias 규칙(값은 소문자, `[a-z0-9_]` 밖은 `_`) |
| `core/csv_io.gd` | CSV 읽기 · 쓰기 — **바뀐 행만 다시 쓴다**, BOM · 줄바꿈 · 따옴표 스타일 보존, E001 · E002 |
| `core/catalog.gd` | 원본 전체(`src/*.csv` + glossary) 로드, `add_entry`(= new_key) · `set_translation`(LLM 은 draft) · `set_field` · `save_all` · Excel 잠금(`~$…`) 검사 |
| `core/keygen.gd` · `hasher.gd` · `tokens.gd` | key 발급 · 원문 해시 · 토큰 문법(§5) |
| `core/refs.gd` | 설명문 `[이름]` → 참조 key (ref_domains 의 alias `*.name` 엔트리). E034 · E036. 결과 = refs.json 본문 |
| `core/issues.gd` | 검증 결과 모음 `{code, level, msg, file, line, key}` |
| `core/validator.gd` | 원본 규칙(§13, E05x 제외) + `report.md` |
| `core/scanner.gd` | 사용처 스캔(§9) + E05x · W05x + `index.json` |
| `core/builder.gd` | `strings_<loc>.csv` · `L.gd` · `refs.json` · 프로젝트 설정 등록 |
| `core/status_ops.gd` | sync · approve · add_locale · rename_alias |
| `core/extractor.gd` | `extract data` — 데이터 CSV 텍스트 컬럼 → key |
| `dock/` | 조회 도크 + 씬 미리보기 (D12) |
| `tests/` | `run_tests.gd` · `test_kit.gd` · `test_*.gd`, fixture 는 `tests/fixtures/<이름>/`(.gdignore, git `-text`) |

## 모듈 계약

- 모듈(`validator` · `scanner` · `builder` · `status_ops` · `extractor`)은 **static 함수만** 갖고, 첫 인자로 파사드(`core/l10n.gd` 인스턴스, 순환 preload 를 피하려고 타입 없이 `l`)를 받는다. 모듈끼리 서로 부르지 않는다 — 필요한 것은 파사드가 넘겨준다(`l.index`, `l.resolve_refs()`).
- 원본 수정은 반드시 `catalog`(→ `csv_io`)를 거친다. 파일을 통째로 다시 쓰지 않는다.
- `class_name` 을 쓰지 않는다(애드온 전역 이름 충돌 방지) — `preload` 상수로 참조. 예외는 생성물 `L` 과 런타임 `Loc`(`resources/Loc.gd`).
- `cmd_build` 순서: sync → 스캔 + 검증 → Error 0 이면 생성물 → index.json · report.md.
