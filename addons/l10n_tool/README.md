# addons/l10n_tool/ — 현지화 도구 (에디터 플러그인 + 헤드리스)

사양: **`docs/localization_design.md`** (확정 사항 §0.5 가 본문보다 우선). 이 README 는 파일 지도와 모듈 계약이다.

## 실행

| 경로 | 방법 |
|---|---|
| 에디터 | **Project → Tools → L10n** (build dev · build release · validate · scan · sync), 조회 도크(오른쪽 위) |
| 헤드리스 | `godot --headless --path . --script res://addons/l10n_tool/cli.gd -- <명령>` — 인자 없이 실행하면 사용법. `validate --fix-preview-leak` 은 E057 누수를 key 로 되돌린다. `set_tr <locale> <json>` 은 번역 초안 일괄(draft) |
| 이행 (병렬 에이전트용) | `new_keys <json> [--out=<json>]` 일괄 발급(원자적) · `write_l` / `write_strings [dev\|release]` 생성물 하나만(검증 관문 없음) · `extract scenes <domain> <경로…> [--dry]` · `extract code [경로…] [--out=<json>]` — 아래 상세. 경로는 `res://…` · 프로젝트 기준 상대 경로 · 프로젝트 안 절대 경로 |
| Rebuild game.db (헤드리스) | `godot --headless --path . --script res://addons/l10n_tool/rebuild_db.gd` |
| Rebuild game.db | csv_to_db 가 DB 를 쓴 뒤 `build dev` 를 부른다 — 실패해도 DB 는 남고 오류만 돌려준다 |
| 테스트 | `godot --headless --path . --script res://addons/l10n_tool/tests/run_tests.gd [-- <파일 이름 필터>]` |

Windows 에서는 콘솔 실행 파일(`Godot_v4.5-stable_win64_console.exe`)을 써야 출력이 보인다.

## 파일

| 파일 | 역할 |
|---|---|
| `plugin.cfg` · `plugin.gd` | 메뉴 · 도크 등록만. 도크는 `dock/l10n_dock.tscn` 이 있으면 붙인다(`setup(plugin)` 호출) |
| `cli.gd` | 헤드리스 진입점 → `L10n.run_cli` |
| `core/l10n.gd` | **명령 파사드** — `cmd_new_key` · `cmd_new_keys` · `cmd_add_locale` · `cmd_sync` · `cmd_approve` · `cmd_rename_alias` · `cmd_scan` · `cmd_validate` · `cmd_build` · `cmd_write_generated` · `cmd_extract` · `cmd_set_translations`, 모듈 공유 도우미 `scan_orphans()` · `parse_scene()` · `resolve_path()`. 상태: `config` · `catalog` · `issues` · `index` |
| `core/config.gd` | `data/l10n/config.json`. 경로는 config 위치 기준(`src/` · `generated/`), `scan.roots` · `data_csv_dir` 의 상대 경로도 config 폴더 기준. `expand_alias()` = data_columns alias 규칙(값은 소문자, `[a-z0-9_]` 밖은 `_`) |
| `core/csv_io.gd` | CSV 읽기 · 쓰기 — **바뀐 행만 다시 쓴다**, BOM · 줄바꿈 · 따옴표 스타일 보존, E001 · E002. 새 파일(`create`)은 LF · BOM 없음 |
| `core/catalog.gd` | 원본 전체(`src/*.csv` + glossary) 로드, `add_entry`(= new_key) · `set_translation`(LLM 은 draft) · `set_field` · `save_all` · `const_map`(L 상수 → alias, 일괄 발급의 E013 사전 검사) · Excel 잠금(`~$…`) 검사 |
| `core/keygen.gd` · `hasher.gd` · `tokens.gd` | key 발급 · 원문 해시 · 토큰 문법(§5) |
| `core/term_match.gd` | Glossary term matcher per locale — `match_<loc>` regex (case-insensitive) if the glossary row has one, else substring of the standard form. Shared by validator (W072 · E074), scanner (index.json `glossary`) and `dock_model` |
| `core/refs.gd` | 설명문 `[이름]` → 참조 key (ref_domains 의 alias `*.name` 엔트리). E034 · E036. 결과 = refs.json 본문 |
| `core/issues.gd` | 검증 결과 모음 `{code, level, msg, file, line, key}` |
| `core/validator.gd` | 원본 규칙(§13, E05x 제외) + `report.md` — 아래 상세 |
| `core/scanner.gd` | 사용처 스캔(§9) + E05x · W05x + `index.json` · `fix_preview_leak` — 아래 상세 |
| `core/builder.gd` | `strings_<loc>.csv` · `L.gd` · `refs.json` · 프로젝트 설정 등록 — 아래 상세 |
| `core/status_ops.gd` | sync · approve · add_locale · rename_alias · new_keys — 아래 상세 |
| `core/extractor.gd` | `extract data` · `extract scenes` · `extract code` — 아래 상세 |
| `dock/` | 조회 도크 + 씬 미리보기 (D12) — 아래 상세 |
| `tests/` | `run_tests.gd` · `test_kit.gd` · `test_*.gd`, fixture 는 `tests/fixtures/<이름>/`(.gdignore, git `-text`) |

## 모듈 계약

- 모듈(`validator` · `scanner` · `builder` · `status_ops` · `extractor`)은 **static 함수만** 갖고, 첫 인자로 파사드(`core/l10n.gd` 인스턴스, 순환 preload 를 피하려고 타입 없이 `l`)를 받는다. 모듈끼리 서로 부르지 않는다 — 필요한 것은 파사드가 넘겨준다(`l.index`, `l.resolve_refs()`).
- 원본 수정은 반드시 `catalog`(→ `csv_io`)를 거친다. 파일을 통째로 다시 쓰지 않는다.
- `L.gd` 예약 상수 `SOURCE_LOCALE` · `FALLBACK_LOCALE` · `LOCALES` 는 `Config.RESERVED_L_CONSTS` 하나가 정의한다(builder · scanner E051 · validator E013).
- `class_name` 을 쓰지 않는다(애드온 전역 이름 충돌 방지) — `preload` 상수로 참조. 예외는 생성물 `L` 과 런타임 `Loc`(`resources/Loc.gd`).
- `cmd_build` 순서: sync → 스캔 + 검증 → Error 0 이면 생성물 → index.json · report.md.

## 모듈 상세

**`core/validator.gd`** — 원본 규칙 검증(§13, 사용처 규칙 E05x · W05x 는 scanner 몫)과 `generated/report.md`. 형식 규칙(E003 status · W003 · E010 ~ E013 · E031)은 deprecated 포함 모든 행, 번역 품질 규칙(W031 · W032 · E033 · E035 · W034 · W035 · W071 · W072)은 active 행만 본다. E034 · E036 은 `l.resolve_refs()`, E004 는 `StrategyIcon.JOSA` 키와 비교(파일이 없으면 건너뜀). `data_columns` 는 E041 · E042 를 보고, CSV 나 컬럼이 아직 없으면 (csv, column)마다 **W041(이행 전)** 경고 하나. E061 은 `release` 에서만 — `l.index.keys` 가 비면 active 전부, 있으면 usages 가 있는 key 만. Term matching: forbidden forms = substring (case-insensitive); standard-form presence (W072, and whether the source contains the term) = `TermMatch` — the glossary row's `match_<loc>` regex if present (compile failure = E074), else substring. report.md = 진행표(`progress(l)`, 진행률 = approved · 비-stale / active) → Error → Warn(코드별) → 범례.

**`core/scanner.gd`** — 사용처 스캔(§9) → `index.json`, E051 · W052/E052 · W053/E053 · W054 · E055 · W056 · E057. 파일마다 정규식 한 번으로 문자열 · 주석 토큰을 뽑고 `tx_…`(literal, 모든 대상 파일) · `L.X`(const, 문자열 · 주석 밖) · `# l10n-dynamic:` / `# l10n-keys:` 패턴(dynamic, `*` = 세그먼트 하나) · `data_columns` 셀(data, CSV 행 줄)을 사용처로 기록한다. 고아 검사(D16)는 주석, `scan.log_funcs` 호출 인자(여러 줄 괄호 추적), `# l10n-ignore` 줄 · func 줄에 붙으면 함수 전체, `scan.ignore_paths`, NodePath · StringName(`^"` `$"` `&"` `%"`), 단독 `"""…"""` 를 뺀다. 씬 값이 원문이 아닌 번역문과 같으면 `preview_leak`(E057, orphans 에 후보 `keys`) — `fix_preview_leak(l)` 이 후보가 하나인 것만 그 값 바이트만 key 로 되돌린다. `scan.roots` · `exclude_dirs` · `ignore_paths` 의 상대 경로는 config 폴더 기준, `.gdignore` 폴더는 루트 아래에서만 건너뛴다. 씬 값은 `parse_scene(re, text)` 한 곳에서 뽑는다 — 값 범위 · 줄 · prop · 언이스케이프 값(`unescape`, Godot `.tscn` 표기를 한 글자씩; `c_unescape` 는 `\\n` 을 잘못 푼다) · 섹션(node / sub_resource / resource) · 노드 경로 · `disabled`. **`auto_translate_mode = 2`(DISABLED)인 노드는 W052/E052 · E057 대상이 아니다** — 값이 INHERIT(0, 줄 없음)이면 같은 파일 안 부모 경로를 올라가 처음 만난 명시 값(1 · 2)을 쓰고, 파일에 없는 조상은 건너뛴다. 여러 줄 값 안의 `[node …]` 같은 줄은 섹션 헤더로 보지 않는다. orphan_scene 항목은 `prop` · `node` 도 담는다.

**`core/builder.gd`** — 생성물 작성. `build(l, mode)` 는 `config.locales` 마다 `strings_<loc>.csv`(헤더 `keys,<loc>`, 도메인 파일 이름 순 → 행 순, LF · BOM 없음, 리터럴 `\n` 유지 — Godot 4.5 CSV 임포터가 개행으로 바꾼다)를 §7.3 포함 조건대로 쓴다 — dev: 원문 전부(deprecated 포함), 번역은 텍스트가 있으면 그대로(stale 포함) 없으면 원문 / release: active 만, 번역은 approved · 비-stale 만(나머지는 행 생략 → Godot 폴백). `L.gd` 는 alias 정렬, 데이터 alias(`is_data_alias`) 제외, deprecated 는 `## @deprecated`, 예약 상수를 함께 쓰며 모드와 무관하게 같다. `refs.json` 은 `l.resolve_refs()` 를 key 정렬 · 탭 들여쓰기로(export `include_filter` 에 포함). 내용이 같은 파일은 다시 쓰지 않는다. 실제 프로젝트 config(`Config.DEFAULT_PATH`)일 때만 `internationalization/locale/translations` 에 `strings_<loc>.<loc>.translation`(Godot 4.5 임포터 이름)을 등록하고 `locale/fallback` 을 맞춘다. `write_l_gd(l)` 은 L.gd 만(rename_alias · `write_l`), `write_strings(l, mode)` 는 `strings_<loc>.csv` 만 다시 쓴다(`write_strings`) — 둘 다 검증 관문이 없고, 파사드 `cmd_write_generated` 가 원본 읽기 오류(E001 · E002 · E003)일 때만 거부한다.

**`core/status_ops.gd`** — 원본을 고치는 명령. `sync`: 텍스트가 있고 `<loc>_hash` 가 빈 번역에 현재 원문 해시를 쓰고 빈 status 는 draft 로(approved + 빈 해시 = 수동 승인은 건드리지 않아 E031 로 남는다). `approve`: key/alias 를 모두 확인한 뒤(없거나 번역이 비면 아무것도 바꾸지 않고 오류) approved + 현재 해시. `add_locale`: Excel 잠금 · 읽기 오류를 먼저 보고 모든 도메인 파일 끝에 `<loc>` · `_status` · `_hash` 컬럼을 붙인 뒤 config.json 저장(glossary.csv 컬럼은 손으로). `rename_alias`: 데이터 alias 불가, 형식 · 중복 · L 상수 충돌 · 예약 이름 검사 → alias 셀 저장 → `Builder.write_l_gd`(모듈 간 호출의 유일한 예외) → 스캔 루트의 `.gd` 에서 `L.<OLD>` 를 단어 단위로 `L.<NEW>` 로 치환(`.tscn` · `.tres` 는 대상 아님). `new_keys`: 항목 배열 `[{domain, alias, <원문 로케일>, context?, max_len?, note?, <번역 로케일>?}]` 을 **전부 검사한 뒤**(domain · alias 형식, 첫 세그먼트 = domain, `catalog.const_map()` 으로 L 상수 충돌 · 예약 이름, 알 수 없는 필드, 빈 원문, 대상 도메인 파일의 Excel 잠금 · 읽기 오류) 하나라도 틀리면 아무것도 바꾸지 않는다. 이미 있는 alias(원본 또는 같은 묶음)는 원문이 같으면 그 key(`reused`, 행은 그대로), 다르면 오류. 새 행은 `add_entry(save=false)` → 번역은 `set_translation`(draft + 해시) → `save_all` 한 번. 결과는 입력 순서 `[{alias, key, domain, status}]`.

**`core/extractor.gd`** — `extract data [csv…]` (§14 1순위 · §6 · D15). `config.data_columns` 항목마다 원문 컬럼(`source_column`, 없으면 `column` 에서 `_key` 를 뗀 이름: `desc_key` → `desc`)의 셀로 key 를 발급한다. alias 는 `expand_alias` 규칙, 이미 있는 alias 면 그 key 를 다시 쓴다(원문이 다르면 보고만). 발급한 key 를 도메인 파일에 추가(`save_all` 먼저)한 뒤 데이터 CSV 의 셀을 key 로, 헤더를 `column` 이름으로 바꾼다 — 헤더와 바뀐 셀만 다시 쓴다. 대상 컬럼이 이미 있으면 검사만. Excel 잠금 · alias 위반 · id 중복이면 아무것도 바꾸지 않고 실패. 두 번 돌려도 같다. 번역은 비워 두고, 중복 텍스트와 E036 후보는 `generated/extract_report.md`. 이행 후 csv_to_db `SCHEMAS` · `TABLE_DEFS` 와 로더의 컬럼 이름도 함께 바꾼다.
`godot --headless --path . --script res://addons/l10n_tool/cli.gd -- extract data cards.csv mech_cards.csv`

`extract scenes <domain> <경로…> [--dry]` (§14 2순위) — 고아 판정은 파사드 `l.scan_orphans()`(= scanner, index.json 과 같은 결과: ignore_paths · E057 누수 · key · 글자 없는 값 · `auto_translate_mode = 2` 제외)에서 경로(파일 · 폴더) 아래 `orphan_scene` 만 고르고, 값 위치 · 노드 정보는 `l.parse_scene()`(= `Scanner.parse_scene`)로 같은 줄을 찾는다. alias = `<domain>.<scene>.<node>[.<prop>]` — scene = 파일 이름에서 `UI_View_` · `UI_Comp_` 를 떼고 `to_snake_case`(`scene_alias_parts`), node = 노드 이름(`.tres` 는 `resource` · `sub_<id>`), 세그먼트는 `[a-z0-9_]` 밖을 `_` 로(`alias_segment`), `.<prop>` 는 `text` 가 아닐 때만. 충돌(원본 alias · 이번 계획 · L 상수) 시 `<부모>_<노드>` → `<노드>_2` … 순, 파일 이름 순 → 파일 안 순서. context = `<파일 이름> <노드 경로> <prop>`, 원문은 언이스케이프 + CRLF → LF, 번역은 비운다. 같은 alias 가 원문 · context 까지 같으면 재사용. 저장 순서: 도메인 파일 → 씬(값 바이트만 뒤에서부터 치환, BOM · 줄바꿈 유지). `--dry` 는 계획 출력만. 멱등.

`extract code [경로…] [--out=<json>]` (§14 3순위, 작업 목록만) — `scan_orphans()` 의 `orphan_code` 를 경로로 걸러 `{generated_at, paths, total, files: [{file, count, items: [{line, text}]}]}` 를 쓴다(기본 `generated/extract_code.json`, gitignore `extract_code*.json`). key 는 발급하지 않는다 — alias 는 이행하는 쪽이 정해 `new_keys` 로.

**병렬 사용 주의** — 명령마다 원본 전체를 새로 읽고 **바뀐 도메인 파일만** 다시 쓰므로, 서로 다른 도메인 파일을 맡은 프로세스는 동시에 돌려도 된다. 같은 도메인 파일을 두 프로세스가 동시에 쓰면 나중 저장이 앞의 추가 행을 지운다(잠금 없음) — 도메인 파일은 작업자 하나가 소유한다. 같은 씬 파일도 마찬가지. key 중복은 50비트 난수라 사실상 없고, 남아도 E011 로 드러난다. `extract code` 는 `--out` 으로 작업자마다 파일을 나눈다. `write_l` · `write_strings` 는 그때의 원본 전체로 다시 쓰므로 마지막 실행이 이긴다(누가 돌려도 결과는 원본에서 결정된다).

**`dock/`** — 조회 도크 (§11.1) + 씬 미리보기 (D12). `l10n_dock.tscn` 이 레이아웃 전부(`%UniqueName` 바인딩), `l10n_dock.gd` 는 그리기 · 명령 호출만, 검색 · 필터(domain · 로케일별 상태 · stale · 미사용 · 용어집 위반 W071/W072) · 상세 · 용어집 매칭 · 씬 미리보기 행은 순수 RefCounted `dock_model.gd`(헤드리스 테스트 `tests/test_dock_model.gd`). 데이터 = catalog(`L10n.open()`) + `generated/index.json`(없거나 usages 가 비면 "scan 을 실행하세요"). 탭: 키 · 용어집 · 고아 텍스트 · 씬 미리보기(TabContainer 제목이 노드 이름이라 탭 페이지 노드 이름이 한글). 사용처 더블클릭 = `.gd` 줄 열기 · `.tscn` 씬 열기 · `.tres` 리소스 열기 · 그 밖(데이터 CSV)은 `경로:줄` 복사. 버튼 new_key · sync · validate · build dev · scan, approve 는 오너 전용 확인 대화상자. 씬 미리보기는 편집 중인 씬에서 `scene_text_props` 값이 key 인 노드를 선택 로케일 번역문으로 보여 주고 행 클릭 = 노드 선택 — **노드 속성은 절대 쓰지 않는다**. `setup(plugin)` 전에는 아무것도 하지 않고, 도크가 숨겨지면 카탈로그를 놓았다가 보일 때 다시 읽는다.
