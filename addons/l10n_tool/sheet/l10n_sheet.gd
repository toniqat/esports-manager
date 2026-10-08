@tool
extends VBoxContainer

# L10n editor: the "L10n" main screen tab (next to 2D · 3D · Script), the tool's only UI.
# Top bar: edit mode (read only · edit content · admin; always opens read only), the language
# menu (target columns of the Keys and Glossary tables), Sync Data (sync → scan + checks →
# index.json · report.md → reload; read only skips the sync write) and Build Data. Tabs, each
# with its own filter / action bar: Keys (read-only sheet: one row per key: key · alias · source ·
# one column per target language with a status dot, plus context · max_len · note when languages
# are picked; header click = sort; filter menu = changed · unused · glossary violations; Ctrl+C =
# the selected cell's text), Glossary (terms with their linked key's texts and status dots),
# Orphan texts, Scene preview (the edited scene's key texts in a locale: read-only, row click
# selects the node) and Log (output of every command). Clicking a cell tints its row and fills the
# bottom dock (shared by Keys and Glossary, moved between them) with that row: source + target
# language (the clicked language) + read-only example (key references expanded) + context ·
# max_len · note: the only place edits happen (edit modes only). `{` in the source / target field
# opens tag completion (tag_edit.gd, `{term_` = glossary words); "find string" / "find in
# glossary" open the key picker. Layout lives in l10n_sheet.tscn; UI text follows the editor
# language (ko, else en: `TEXTS`); search · filters · rows · glossary · preview rows come from
# sheet_model.gd; every write goes through the facade (`cmd_edit` · `cmd_new_key` · `cmd_approve`
# (admin), re-read from disk → write → save).
# Usages (generated/index.json, refreshed by Sync Data) show in the dock tree and the row's
# right-click menu, each file followed by the screen scenes it ends up in: .gd → script line,
# .tscn → open scene, .tres → resource, anything else (data CSVs) and the key's own source CSV
# row → external editor at that line.
# Inactive until plugin.gd calls `setup(plugin)`.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const SheetModel = preload("res://addons/l10n_tool/sheet/sheet_model.gd")
const ScreenMap = preload("res://addons/l10n_tool/sheet/screen_map.gd")
const TagEdit = preload("res://addons/l10n_tool/sheet/tag_edit.gd")
const KeyRefs = preload("res://addons/l10n_tool/core/key_refs.gd")
const Tokens = preload("res://addons/l10n_tool/core/tokens.gd")
const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
## Usage tooltip code preview: lines per file, characters per line.
const PREVIEW_LINES := 4
const PREVIEW_COLS := 110
## Sync Data work per editor frame (ms): the progress window redraws between slices.
const SYNC_FRAME_MS := 30

## Column kinds. KIND_INFO = read-only glossary columns (term_id · forbidden · dnt · note).
const KIND_KEY := "key"
const KIND_ALIAS := "alias"
const KIND_TEXT := "text"
const KIND_META := "meta"
const KIND_INFO := "info"
## Status menu items (menu id = index). All picked = no status filter.
const STATUS_CHOICES := [SheetModel.ST_NONE, SheetModel.ST_DRAFT, SheetModel.ST_APPROVED]
## Dot colours — not started · draft · approved · stale (source changed after translating).
const STATUS_COLORS := {
	SheetModel.ST_NONE: Color(0.93, 0.32, 0.32),
	SheetModel.ST_DRAFT: Color(0.96, 0.82, 0.26),
	SheetModel.ST_APPROVED: Color(0.36, 0.82, 0.42),
	"stale": Color(1.0, 0.56, 0.16),
}
const MENU_ALL_ID := 0
## Editor icons per button, first one the editor theme has wins.
const BUTTON_ICONS := {"AddRow": ["Add"], "RemoveRow": ["Remove"], "SyncData": ["Reload", "Loop"], "BuildData": ["Tools", "Play"],
	"PreviewRefresh": ["Reload"], "LogClear": ["Clear", "Remove"], "Apply": ["ImportCheck", "StatusSuccess"],
	"Revert": ["UndoRedo", "RotateLeft", "Reload"], "Approve": ["ImportCheck", "StatusSuccess"],
	"GlApprove": ["ImportCheck", "StatusSuccess"], "FilterMenu": ["AnimationFilter", "Filter", "Search"]}
## Filter fields: magnifier on the right like the FileSystem dock's "Filter Files".
const SEARCH_FIELDS := ["Search", "GlSearch", "KpSearch"]
## Approve menu ids.
enum { APPROVE_SELECTED, APPROVE_VISIBLE }
## Edit modes (EditMode option id = value). Read-only writes nothing to the sources; content edit =
## everything but approve; admin = approve too. The editor always opens read-only.
enum { MODE_READ, MODE_EDIT, MODE_ADMIN }
const MODE_TEXTS := ["edit_read", "edit_content", "edit_admin"]
## Keys filter menu: id = index, value = SheetModel.search filter name.
const FILTER_CHOICES := ["stale", "unused", "glossary"]
const FILTER_TEXTS := ["stale_only", "unused_only", "glossary_only"]
const FILTER_TIPS := ["stale_tip", "unused_tip", "glossary_tip"]
## Tab order in the scene and their TEXTS ids.
const TAB_TEXTS := ["tab_keys", "tab_glossary", "tab_orphans", "tab_preview", "tab_log"]
const TAB_KEYS := 0
const TAB_GLOSSARY := 1
const LOG_MAX_LINES := 500
## Tint of the selected cell's row (editor accent colour at this alpha); the cell itself keeps the
## tree's own selection look.
const ROW_TINT_ALPHA := 0.16
## Key picker: rows listed at most.
const PICKER_MAX := 300
## Row menu ids; usages follow from MENU_USAGE_BASE.
enum { MENU_COPY_KEY, MENU_COPY_ALIAS, MENU_OPEN_SOURCE, MENU_COPY_SOURCE }
const MENU_USAGE_BASE := 100
const USAGE_SOURCE := "source"
## Row menu: screen rows (the scene a usage file ends up in) indented under their file.
const USAGE_SCREEN := "screen"
const SCREEN_INDENT := "      └ "
## Environment the external editor must not inherit (see _open_external).
const CHILD_ENV_STRIP := ["ELECTRON_RUN_AS_NODE"]
## UI text per editor language.
const TEXTS := {
	"ko": {
		"search_ph": "Filter",
		"all_domains": "전체 도메인",
		"all_langs": "모든 언어",
		"langs": "언어: %s",
		"langs_tip": "볼 언어: 고르면 그 언어 열(키 탭은 context · max_len · note 도)을 보여 주고, 상태 필터도 그 언어 기준",
		"all_status": "모든 상태",
		"statuses": "상태: %s",
		"status_none": "상태: 없음",
		"status_tip": "볼 번역 상태: 여러 개 고를 수 있다 (셋 다 = 모든 상태)",
		SheetModel.ST_NONE: "미착수",
		SheetModel.ST_DRAFT: "작성 필요",
		SheetModel.ST_APPROVED: "완료",
		"stale": "원문 변경됨",
		"stale_only": "변경된 항목만 표시",
		"stale_tip": "원문이 바뀐 뒤 아직 고치지 않은 번역만",
		"add_tip": "행 추가 — key 발급 → <domain>.csv 끝에 행 추가",
		"remove_tip": "행 제거: 선택한 key 의 행을 원본 CSV 에서 지운다 (확인 창이 뜬다)",
		"remove_pick": "행 제거: 지울 행을 먼저 선택",
		"remove_title": "행 제거",
		"remove_ok": "제거",
		"remove_body": "%s  ·  %s

이 key 의 행을 %s 에서 지운다. 번역 · 상태도 함께 사라진다(되돌리기 = git).
L.gd · strings 는 Build Data 때 반영된다.",
		"remove_used": "사용처 %d곳이 이 key 를 쓴다. 지우면 코드 · 씬 · 데이터 · 다른 문장의 참조가 깨진다 (더블클릭 = 이동):",
		"remove_unused": "사용처 없음.",
		"remove_no_index": "사용처 정보 없음: Sync Data 로 먼저 확인하는 것을 권한다.",
		"remove_glossary": "용어집 %s (glossary.csv:%d) 가 이 key 에 연결됨",
		"removed": "행 제거: %s (%s)",
		"remove_failed": "행 제거 실패: %s",
		"build_tip": "Build Data",
		"sync_tip": "Sync Data",
		"apply": "적용",
		"apply_tip": "적용 (Ctrl+Enter)",
		"revert": "되돌리기",
		"dock_pick": "행을 선택해서 편집",
		"edit_read": "읽기 전용",
		"edit_content": "내용 수정",
		"edit_admin": "관리자",
		"edit_mode_tip": "읽기 전용: 보기만 (Sync Data 는 원본을 쓰지 않는다)
내용 수정: 원문 · 번역 · context 수정, 행 추가, Build Data
관리자: 승인까지",
		"filters_on": "사용 중: %s",
		"filter_tip": "목록 필터: 여러 개 고르면 모두 만족하는 행만",
		"find_term": "{term_} 용어집에서 찾기",
		"kp_term_title": "용어집 찾기: 더블클릭 · Enter 로 넣기",
		"source": "%s (원문)",
		"no_target": "번역 언어 없음",
		"example": "예시",
		"example_tip": "%s 텍스트에서 key 참조 {tx_…} 를 펼친 문장 (읽기 전용, 마지막으로 고르거나 고친 언어)",
		"example_bad": "(펼칠 수 없음: 없는 key 참조 또는 순환)",
		"example_empty": "(번역 없음)",
		"len": "%d / %d자",
		"find_string": "{tx_} 스트링 찾기",
		"kp_title": "스트링 찾기: 더블클릭 · Enter 로 넣기",
		"kp_ok": "넣기",
		"kp_more": "… %d개 더: 검색어를 좁히세요",
		"term_no_key": "%s: key 에 연결되지 않은 용어 (glossary.csv:%d 에서 직접 고친다)",
		"usages_menu": "사용처 %d곳",
		"log_clear": "로그 지우기",
		"add_title": "행 추가 (new_key)",
		"add_ok": "추가",
		"alias_ph": "이름 (아래 도메인 트리에서 고른 곳에 붙는다)",
		"ar_preview": "alias: %s",
		"ar_pick_domain": "아래 트리에서 도메인을 고르세요",
		"ar_new_row": "(새 행)",
		"saved": "%s · %s 저장: Build Data 로 게임에 반영",
		"save_failed": "저장 실패: %s",
		"cfg_failed": "config.json 을 읽지 못했다 — data/l10n/config.json 확인",
		"load_errors": "원본 읽기 오류 %d개: Sync Data 후 로그 탭 확인",
		"build_ok": "Build Data 완료: Warn %d (generated/report.md)",
		"build_fail": "Build Data 실패: Error %d, 생성물을 쓰지 않았다 (generated/report.md)",
		"add_failed": "행 추가 실패: %s",
		"added": "행 추가: %s = %s. 원문을 입력하세요",
		"over_len": "max_len %d 초과: %d자",
		"sync_data_done": "Sync Data: 해시 · draft %d개 · key %d개 · 고아 텍스트 %d개 · Error %d · Warn %d (로그 탭)",
		"sync_stage_sync": "원본 번역 해시 기록 중…",
		"sync_stage_scan": "사용처 스캔 중…",
		"sync_stage_check": "규칙 검증 중…",
		"sync_stage_write": "index.json · report.md 쓰는 중…",
		"usages": "사용처",
		"usages_of": "사용처 %d곳",
		"source_item": "원본: %s",
		"no_usage_data": "사용처 정보 없음: Sync Data 버튼",
		"no_usages": "사용처 없음",
		"copy_key": "key 복사",
		"copy_alias": "alias 복사",
		"open_source": "원본 CSV 열기 (외부 편집기)",
		"copy_source": "원본 경로 복사",
		"copied": "복사함: %s",
		"opened": "열기: %s",
		"open_failed": "열기 실패: %s",
		"look_for": "파일 안에서 찾을 이름: %s",
		"look_dynamic": "실행 중에 만드는 key — 파일 안의 `# l10n-dynamic:` 주석 패턴으로 연결",
		"screen_line": "화면: %s   (%s)",
		"screen_none": "화면: 찾지 못함 — 게임 화면에서 이 파일로 이어지는 연결이 없다(공용 코드이거나 쓰이지 않음)",
		"tab_keys": "키",
		"tab_glossary": "용어집",
		"tab_orphans": "고아 텍스트",
		"tab_preview": "씬 미리보기",
		"tab_log": "로그",
		"unused_only": "미사용만",
		"unused_tip": "active 인데 코드 · 씬 어디에서도 안 쓰는 key (scan 필요)",
		"glossary_only": "용어집 위반만",
		"glossary_tip": "용어집 규칙(W071 · W072)에 걸린 key: 처음 켜면 검증을 돌린다",
		"approve": "승인…",
		"approve_tip": "번역을 approved 로 — 오너 전용 (확인 창이 뜬다)",
		"approve_locked": "승인은 관리자 모드에서만",
		"approve_selected": "선택한 칸 승인",
		"approve_visible": "보이는 행 모두 승인",
		"approve_title": "approve — 오너 전용",
		"approve_ok": "approve",
		"approve_body": "approve 는 오너 전용이다 (LLM · 일반 작업자는 draft 까지).\n\n%s 번역 %d개를 approved 로 바꾸고 해시를 갱신한다:\n%s",
		"approve_need_locale": "승인할 언어를 정하세요 — 번역 칸을 고르거나 언어 메뉴에서 하나만 고른다",
		"approve_none": "승인할 번역이 없다 (비었거나 이미 approved)",
		"approve_done": "approve %s: %d개",
		"cmd_done": "%s: Error %d · Warn %d — 자세한 내용은 로그 탭",
		"no_usage_hint": "사용처 정보 없음: Sync Data 버튼",
		"issues": "검증: %s",
		"terms": "용어: %s",
		"forbidden": "금지",
		"glossary_keys_tip": "원문에 이 용어가 들어간 key: 더블클릭하면 키 탭에서 연다",
		"glossary_keys": "이 용어가 들어간 key %d개",
		"col_key": "키",
		"col_source": "원문",
		"glossary_no_keys": "이 용어가 들어간 key 없음",
		"orphan_title": "key 가 아닌 표시 텍스트 (scan 결과) — 더블클릭으로 이동",
		"no_orphans": "고아 텍스트 없음",
		"no_index": "사용처 정보 없음: Sync Data 버튼",
		"preview_refresh": "새로 고침",
		"preview_note": "편집 중인 씬의 key 를 고른 언어 번역문으로 보여 준다 — 씬은 수정하지 않는다. 행 클릭 = 노드 선택",
		"preview_no_scene": "열린 씬 없음",
		"preview_info": "%s — key %d개",
		"preview_missing": "(번역 없음)",
		"preview_unknown": "(없는 key)",
		"col_node": "노드",
		"col_prop": "속성",
		"open_title": "파일을 열 수 없음",
		"open_missing": "파일이 없다:\n%s\n\n사용처 정보가 오래됐을 수 있다: Sync Data 버튼으로 다시 찾기.",
		"open_no_editor": "연결된 외부 편집기가 없다:\n%s\n\nEditor Settings → Text Editor → External → Exec Path 에 VS Code 등을 지정하면 그 줄로 바로 열린다.",
		"open_launch_failed": "외부 편집기를 실행하지 못했다:\n%s\n\n파일: %s\nEditor Settings → Text Editor → External → Exec Path 를 확인.",
		"copy_path": "경로 복사",
		"open_default": "기본 프로그램으로 열기",
	},
	"en": {
		"search_ph": "Filter",
		"all_domains": "All domains",
		"all_langs": "All languages",
		"langs": "Languages: %s",
		"langs_tip": "Languages to show: picking some shows their columns (plus context · max_len · note in Keys) and scopes the status filter",
		"all_status": "All statuses",
		"statuses": "Status: %s",
		"status_none": "Status: none",
		"status_tip": "Translation statuses to show: pick several (all three = all statuses)",
		SheetModel.ST_NONE: "Not started",
		SheetModel.ST_DRAFT: "Draft",
		SheetModel.ST_APPROVED: "Approved",
		"stale": "Source changed",
		"stale_only": "Show changed only",
		"stale_tip": "Only translations not updated since the source text changed",
		"add_tip": "Add row — issue a key, append to <domain>.csv",
		"remove_tip": "Remove row: delete the selected key's row from its source CSV (asks first)",
		"remove_pick": "Remove row: select a row first",
		"remove_title": "Remove row",
		"remove_ok": "Remove",
		"remove_body": "%s  ·  %s

Deletes this key's row from %s, translations and statuses included (undo = git).
L.gd · strings follow on Build Data.",
		"remove_used": "%d usages use this key. Removing it breaks those code · scene · data · key references (double-click = go):",
		"remove_unused": "No usages.",
		"remove_no_index": "No usage data: run Sync Data first to check.",
		"remove_glossary": "Glossary term %s (glossary.csv:%d) links to this key",
		"removed": "Row removed: %s (%s)",
		"remove_failed": "Remove row failed: %s",
		"build_tip": "Build Data",
		"sync_tip": "Sync Data",
		"apply": "Apply",
		"apply_tip": "Apply (Ctrl+Enter)",
		"revert": "Revert",
		"dock_pick": "Select a row to edit",
		"edit_read": "Read only",
		"edit_content": "Edit content",
		"edit_admin": "Admin",
		"edit_mode_tip": "Read only: view (Sync Data writes no source)
Edit content: source · translation · context edits, add row, Build Data
Admin: approve too",
		"filters_on": "On: %s",
		"filter_tip": "List filters: rows must match every one picked",
		"find_term": "{term_} Find in glossary",
		"kp_term_title": "Find in glossary: double-click or Enter to insert",
		"source": "%s (source)",
		"no_target": "No target language",
		"example": "Example",
		"example_tip": "The %s text with key references {tx_…} expanded (read-only, last picked or edited language)",
		"example_bad": "(cannot expand: unknown key reference or a cycle)",
		"example_empty": "(no translation)",
		"len": "%d / %d chars",
		"find_string": "{tx_} Find string",
		"kp_title": "Find string: double-click or Enter to insert",
		"kp_ok": "Insert",
		"kp_more": "… %d more: narrow the filter",
		"term_no_key": "%s: term not linked to a key (edit glossary.csv:%d directly)",
		"usages_menu": "%d usages",
		"log_clear": "Clear log",
		"add_title": "Add row (new_key)",
		"add_ok": "Add",
		"alias_ph": "Name (appended to the domain picked below)",
		"ar_preview": "alias: %s",
		"ar_pick_domain": "Pick a domain in the tree below",
		"ar_new_row": "(new row)",
		"saved": "%s · %s saved: run Build Data to apply in game",
		"save_failed": "Save failed: %s",
		"cfg_failed": "Could not read config.json — check data/l10n/config.json",
		"load_errors": "%d source read errors: run Sync Data (Log tab)",
		"build_ok": "Build Data done: %d warnings (generated/report.md)",
		"build_fail": "Build Data failed: %d errors, nothing generated (generated/report.md)",
		"add_failed": "Add row failed: %s",
		"added": "Row added: %s = %s. Type the source text",
		"over_len": "over max_len %d: %d chars",
		"sync_data_done": "Sync Data: %d hashes · drafts, %d keys, %d orphan texts, %d errors, %d warnings (Log tab)",
		"sync_stage_sync": "Recording translation hashes…",
		"sync_stage_scan": "Scanning usages…",
		"sync_stage_check": "Checking rules…",
		"sync_stage_write": "Writing index.json · report.md…",
		"usages": "Usages",
		"usages_of": "%d usages",
		"source_item": "Source: %s",
		"no_usage_data": "No usage data: press Sync Data",
		"no_usages": "No usages",
		"copy_key": "Copy key",
		"copy_alias": "Copy alias",
		"open_source": "Open source CSV (external editor)",
		"copy_source": "Copy source path",
		"copied": "Copied: %s",
		"opened": "Opened: %s",
		"open_failed": "Could not open: %s",
		"look_for": "Appears in the file as: %s",
		"look_dynamic": "Key built at runtime — linked by a `# l10n-dynamic:` pattern comment in the file",
		"screen_line": "Screen: %s   (%s)",
		"screen_none": "Screen: not found — nothing on a game screen leads to this file (shared code, or unused)",
		"tab_keys": "Keys",
		"tab_glossary": "Glossary",
		"tab_orphans": "Orphan texts",
		"tab_preview": "Scene preview",
		"tab_log": "Log",
		"unused_only": "Unused only",
		"unused_tip": "Active keys used nowhere in code or scenes (needs scan)",
		"glossary_only": "Glossary violations",
		"glossary_tip": "Keys breaking glossary rules (W071 · W072): runs the checks the first time",
		"approve": "Approve…",
		"approve_tip": "Mark translations approved — owner only (asks to confirm)",
		"approve_locked": "Approve is available in Admin mode only",
		"approve_selected": "Approve selected cell",
		"approve_visible": "Approve all visible rows",
		"approve_title": "approve — owner only",
		"approve_ok": "approve",
		"approve_body": "approve is for the owner only (LLMs · other workers stop at draft).\n\nMarks %s translations of %d keys approved and refreshes their hash:\n%s",
		"approve_need_locale": "Pick the language to approve — select a translation cell, or pick one language in the menu",
		"approve_none": "Nothing to approve (empty or already approved)",
		"approve_done": "approve %s: %d",
		"cmd_done": "%s: %d errors · %d warnings — see the Log tab",
		"no_usage_hint": "No usage data: press Sync Data",
		"issues": "Checks: %s",
		"terms": "Terms: %s",
		"forbidden": "Forbidden",
		"glossary_keys_tip": "Keys whose source contains this term: double-click to open in Keys",
		"glossary_keys": "%d keys with this term",
		"col_key": "Key",
		"col_source": "Source",
		"glossary_no_keys": "No key uses this term",
		"orphan_title": "Display text that is not a key (scan result) — double-click to open",
		"no_orphans": "No orphan texts",
		"no_index": "No usage data: press Sync Data",
		"preview_refresh": "Refresh",
		"preview_note": "Shows the edited scene's keys in the chosen language — the scene is never modified. Click a row to select the node",
		"preview_no_scene": "No scene open",
		"preview_info": "%s — %d keys",
		"preview_missing": "(no translation)",
		"preview_unknown": "(unknown key)",
		"col_node": "Node",
		"col_prop": "Property",
		"open_title": "Cannot open file",
		"open_missing": "File not found:\n%s\n\nUsage data may be out of date: press Sync Data.",
		"open_no_editor": "No external editor is set:\n%s\n\nSet Editor Settings → Text Editor → External → Exec Path (e.g. VS Code) to open files at the line.",
		"open_launch_failed": "Could not launch the external editor:\n%s\n\nFile: %s\nCheck Editor Settings → Text Editor → External → Exec Path.",
		"copy_path": "Copy path",
		"open_default": "Open with default app",
	},
}

@onready var _search: LineEdit = %Search
@onready var _domain: OptionButton = %Domain
@onready var _locale_menu: MenuButton = %LocaleMenu
@onready var _status_menu: MenuButton = %StatusMenu
@onready var _filter_menu: MenuButton = %FilterMenu
@onready var _edit_mode: OptionButton = %EditMode
@onready var _count: Label = %Count
@onready var _sheet: Tree = %Sheet
@onready var _dock: Control = %Dock
@onready var _dock_title: Label = %DockTitle
@onready var _dock_sub: Label = %DockSub
@onready var _dock_info: Label = %DockInfo
@onready var _source_head: Label = %SourceHead
@onready var _source_edit: TagEdit = %SourceEdit
@onready var _target_dot: TextureRect = %TargetDot
@onready var _target_head: Label = %TargetHead
@onready var _target_edit: TagEdit = %TargetEdit
@onready var _example_head: Label = %ExampleHead
@onready var _example_edit: TextEdit = %ExampleEdit
@onready var _context_edit: TextEdit = %ContextEdit
@onready var _max_len_edit: LineEdit = %MaxLenEdit
@onready var _note_edit: TextEdit = %NoteEdit
@onready var _apply: Button = %Apply
@onready var _revert: Button = %Revert
@onready var _add_row_dialog: ConfirmationDialog = %AddRowDialog
@onready var _ar_key: LineEdit = %ArKey
@onready var _ar_alias: LineEdit = %ArAlias
@onready var _ar_preview: Label = %ArPreview
@onready var _ar_domains: Tree = %ArDomains
@onready var _remove_row: Button = %RemoveRow
@onready var _remove_row_dialog: ConfirmationDialog = %RemoveRowDialog
@onready var _rr_body: Label = %RrBody
@onready var _rr_usages: ItemList = %RrUsages
@onready var _usage_title: Label = %UsageTitle
@onready var _usage_tree: Tree = %UsageTree
@onready var _row_menu: PopupMenu = %RowMenu
@onready var _open_dialog: AcceptDialog = %OpenDialog
@onready var _hint: Label = %Hint
@onready var _tabs: TabContainer = %Tabs
@onready var _approve: MenuButton = %Approve
@onready var _approve_dialog: ConfirmationDialog = %ApproveDialog
@onready var _gl_search: LineEdit = %GlSearch
@onready var _gl_status_menu: MenuButton = %GlStatusMenu
@onready var _gl_count: Label = %GlCount
@onready var _gl_approve: MenuButton = %GlApprove
@onready var _glossary_tree: Tree = %GlossaryTree
@onready var _glossary_keys: Tree = %GlossaryKeys
@onready var _gl_keys_title: Label = %GlKeysTitle
@onready var _gl_keys_margin: Control = %GlKeysMargin
@onready var _dock_scroll: ScrollContainer = %DockScroll
@onready var _orphan_list: ItemList = %OrphanList
@onready var _preview_page: Control = %Preview
@onready var _preview_locale: OptionButton = %PreviewLocale
@onready var _preview_info: Label = %PreviewInfo
@onready var _preview_tree: Tree = %PreviewTree
@onready var _log_text: TextEdit = %LogText
@onready var _key_picker: AcceptDialog = %KeyPicker
@onready var _kp_search: LineEdit = %KpSearch
@onready var _kp_tree: Tree = %KpTree
@onready var _sync_dialog: Window = %SyncDialog
@onready var _sync_stage: Label = %SyncStage
@onready var _sync_bar: ProgressBar = %SyncBar

var _plugin: EditorPlugin
var _l: L10n
var _model: SheetModel
## UI language — "ko" or "en" (editor language, read once).
var _lang: String = "en"
## Picked target languages in config order (never the source); empty = all languages (no meta columns).
var _sel_locales: PackedStringArray = PackedStringArray()
## Picked statuses per table (STATUS_CHOICES order); all of them = no status filter.
var _sel_statuses: PackedStringArray = PackedStringArray(STATUS_CHOICES)
var _gl_statuses: PackedStringArray = PackedStringArray(STATUS_CHOICES)
## Picked Keys filters (FILTER_CHOICES names).
var _sel_filters: PackedStringArray = PackedStringArray()
## Edit mode (MODE_*): read-only until the user picks another.
var _mode: int = MODE_READ
## Column layouts: [{kind, column (csv column / locale), title}]: rebuilt on load / language pick.
var _cols: Array = []
var _gcols: Array = []
## Keys tab selection by key + column name (column indices move when languages change).
var _sel_key: String = ""
var _sel_column: String = ""
## Glossary tab selection by term_id + column name.
var _gl_term: String = ""
var _gl_column: String = ""
## Header-click sort per table: {column, desc}; column "" = file order. Clicks cycle
## ascending → descending → off.
var _sort: Dictionary = {"keys": {"column": "", "desc": false}, "glossary": {"column": "", "desc": false}}
## Tinted row per table (a TreeItem: freed by the next redraw, checked before use).
var _tinted: Dictionary = {}
## Dock: the key shown, its target language and the values as loaded (dirty check · revert).
var _dock_key: String = ""
var _target_loc: String = ""
var _dock_loaded: Dictionary = {}
## Language the example shows: the last picked or edited one (source or target).
var _example_loc: String = ""
## True while _show_dock / _clear_dock fill the fields (their text_changed is not an edit).
var _filling: bool = false
## Add row: the key issued for the pending row (shown in the table until the dialog closes).
var _pending_key: String = ""
## Remove row: the key the confirm dialog will delete.
var _remove_key: String = ""
## Field the key picker inserts into, and whether it lists glossary terms instead of every key.
var _kp_edit: TagEdit = null
var _kp_terms: bool = false
var _dots: Dictionary = {}
## Key the row menu was opened on, and its usages (menu id - MENU_USAGE_BASE).
var _menu_key: String = ""
var _menu_usages: Array = []
## Usage → screen map (lazy, see _screens_of) and file line cache for previews.
var _screen_map: RefCounted = null
## Sync Data is running (its button is ignored until the job ends).
var _syncing: bool = false
var _lines_cache: Dictionary = {}
## File the open popup is about, and its extra buttons (rebuilt per popup).
var _open_file: String = ""
var _open_dialog_buttons: Array = []
## Locale + keys the approve dialog will apply to.
var _approve_locale: String = ""
var _approve_keys: PackedStringArray = PackedStringArray()
## The scene preview needs redrawing (scene switched while the tab was hidden).
var _preview_dirty: bool = true
## The Keys table's hover look is off (mouse over a blank padding / pending row).
var _hover_off: bool = false


## plugin.gd calls this before adding the sheet to the main screen.
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	if _plugin == null:
		return
	_lang = _editor_lang()
	_apply_texts()
	%AddRow.pressed.connect(_on_add_row_pressed)
	_remove_row.pressed.connect(_on_remove_row_pressed)
	_remove_row_dialog.confirmed.connect(_on_remove_row_confirmed)
	_rr_usages.item_activated.connect(_on_rr_usage_activated)
	%SyncData.pressed.connect(_on_sync_data_pressed)
	%BuildData.pressed.connect(_on_build_pressed)
	%LogClear.pressed.connect(func() -> void: _log_text.text = "")
	%PreviewRefresh.pressed.connect(_refresh_preview)
	_edit_mode.item_selected.connect(func(i: int) -> void: _set_mode(_edit_mode.get_item_id(i)))
	for mb in [_approve, _gl_approve]:
		(mb as MenuButton).get_popup().id_pressed.connect(_on_approve_menu_id)
	_approve_dialog.confirmed.connect(_on_approve_confirmed)
	_glossary_tree.select_mode = Tree.SELECT_SINGLE
	_glossary_tree.cell_selected.connect(_on_glossary_selected)
	_glossary_tree.column_title_clicked.connect(func(c: int, _b: int) -> void: _on_title_clicked("glossary", c))
	_glossary_tree.item_activated.connect(_focus_dock_field)
	_glossary_tree.gui_input.connect(_on_table_input.bind(_glossary_tree))
	_glossary_keys.item_activated.connect(_on_glossary_key_activated)
	# The dock tables fit their rows and do not scroll: the wheel over them scrolls the dock.
	for dt in [_glossary_keys, _usage_tree]:
		(dt as Tree).gui_input.connect(_on_dock_table_input.bind(dt))
	_gl_search.text_changed.connect(func(_s: String) -> void: _refresh_glossary())
	_orphan_list.item_activated.connect(_on_orphan_activated)
	_tabs.tab_changed.connect(_on_tab_changed)
	_preview_locale.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_preview_tree.item_selected.connect(_on_preview_selected)
	_usage_tree.item_activated.connect(_on_usage_activated)
	_usage_tree.item_collapsed.connect(func(_it: TreeItem) -> void: _fit_usage_tree.call_deferred())
	_sheet.select_mode = Tree.SELECT_SINGLE
	_sheet.cell_selected.connect(_on_cell_selected)
	_sheet.item_mouse_selected.connect(_on_sheet_mouse_selected)
	_sheet.column_title_clicked.connect(func(c: int, _b: int) -> void: _on_title_clicked("keys", c))
	_sheet.item_activated.connect(_focus_dock_field)
	_sheet.gui_input.connect(_on_table_input.bind(_sheet))
	_sheet.gui_input.connect(_on_sheet_hover)
	_sheet.mouse_exited.connect(_set_sheet_hover.bind(true))
	_row_menu.id_pressed.connect(_on_row_menu_id)
	_open_dialog.custom_action.connect(_on_open_dialog_action)
	_search.text_changed.connect(func(_s: String) -> void: _refresh_list())
	_domain.item_selected.connect(func(_i: int) -> void: _refresh_list())
	for mb in [_locale_menu, _status_menu, _gl_status_menu, _filter_menu]:
		(mb as MenuButton).get_popup().hide_on_checkable_item_selection = false
	_filter_menu.get_popup().id_pressed.connect(_on_filter_menu_id)
	_locale_menu.get_popup().id_pressed.connect(_on_locale_menu_id)
	_status_menu.get_popup().id_pressed.connect(func(id: int) -> void: _on_status_menu_id(false, id))
	_gl_status_menu.get_popup().id_pressed.connect(func(id: int) -> void: _on_status_menu_id(true, id))
	_apply.pressed.connect(_on_apply_pressed)
	_revert.pressed.connect(_show_dock.bind(true))
	for e in [_source_edit, _target_edit]:
		e.gui_input.connect(_on_dock_input)
		e.text_changed.connect(_on_example_field.bind(e))
		e.focus_entered.connect(_on_example_field.bind(e))
		e.find_string_requested.connect(_open_key_picker.bind(false))
		e.find_term_requested.connect(_open_key_picker.bind(true))
	for le in [_context_edit, _max_len_edit, _note_edit]:
		le.gui_input.connect(_on_dock_input)
	for te in [_context_edit, _note_edit]:
		te.text_changed.connect(_update_dock_live)
	_max_len_edit.text_changed.connect(func(_s: String) -> void: _update_dock_live())
	_key_picker.register_text_enter(_kp_search)
	_key_picker.confirmed.connect(_on_key_picked)
	_kp_search.text_changed.connect(func(_s: String) -> void: _refresh_key_picker())
	_kp_tree.item_activated.connect(_on_key_picker_activated)
	_add_row_dialog.confirmed.connect(_on_add_row_confirmed)
	_add_row_dialog.canceled.connect(_on_add_row_canceled)
	_add_row_dialog.register_text_enter(_ar_alias)
	_ar_alias.text_changed.connect(func(_s: String) -> void: _update_ar_preview())
	_ar_domains.item_selected.connect(_update_ar_preview)
	_sheet.resized.connect(_pad_sheet)
	visibility_changed.connect(_on_visibility_changed)


# ── text · icons ────────────────────────────────────────────────────────

func _tr(id: String) -> String:
	return String((TEXTS[_lang] as Dictionary).get(id, (TEXTS["en"] as Dictionary).get(id, id)))


static func _editor_lang() -> String:
	if Engine.is_editor_hint():
		var es: EditorSettings = EditorInterface.get_editor_settings()
		if es != null and String(es.get_setting("interface/editor/editor_language")).begins_with("ko"):
			return "ko"
	return "en"


func _button(node_name: String) -> Button:
	return get_node("%" + node_name) as Button


## Static UI text + button icons (texts that depend on data are set where they are drawn).
func _apply_texts() -> void:
	for node_name in SEARCH_FIELDS:
		(get_node("%" + node_name) as LineEdit).placeholder_text = _tr("search_ph")
	_locale_menu.tooltip_text = _tr("langs_tip")
	_status_menu.tooltip_text = _tr("status_tip")
	_gl_status_menu.tooltip_text = _tr("status_tip")
	_filter_menu.tooltip_text = _tr("filter_tip")
	_fill_filter_menu()
	_edit_mode.clear()
	for m in MODE_TEXTS.size():
		_edit_mode.add_item(_tr(MODE_TEXTS[m]), m)
	_edit_mode.select(_edit_mode.get_item_index(_mode))
	_edit_mode.tooltip_text = _tr("edit_mode_tip")
	%AddRow.tooltip_text = _tr("add_tip")
	%BuildData.tooltip_text = _tr("build_tip")
	%SyncData.tooltip_text = _tr("sync_tip")
	%LogClear.tooltip_text = _tr("log_clear")
	_apply.text = _tr("apply")
	_apply.tooltip_text = _tr("apply_tip")
	_revert.text = _tr("revert")
	_example_edit.placeholder_text = _tr("example_empty")
	_add_row_dialog.title = _tr("add_title")
	_add_row_dialog.ok_button_text = _tr("add_ok")
	_remove_row_dialog.title = _tr("remove_title")
	_remove_row_dialog.ok_button_text = _tr("remove_ok")
	_ar_alias.placeholder_text = _tr("alias_ph")
	_key_picker.title = _tr("kp_title")
	_key_picker.ok_button_text = _tr("kp_ok")
	for i in TAB_TEXTS.size():
		_tabs.set_tab_title(i, _tr(TAB_TEXTS[i]))
	for mb in [_approve, _gl_approve]:
		(mb as MenuButton).text = _tr("approve")
		var apm: PopupMenu = (mb as MenuButton).get_popup()
		apm.clear()
		apm.add_item(_tr("approve_selected"), APPROVE_SELECTED)
		apm.add_item(_tr("approve_visible"), APPROVE_VISIBLE)
	_approve_dialog.title = _tr("approve_title")
	_approve_dialog.ok_button_text = _tr("approve_ok")
	_glossary_keys.tooltip_text = _tr("glossary_keys_tip")
	(%OrphanTitle as Label).text = _tr("orphan_title")
	(%PreviewRefresh as Button).tooltip_text = _tr("preview_refresh")
	(%PreviewNote as Label).text = _tr("preview_note")
	for e in [_source_edit, _target_edit]:
		e.find_label = _tr("find_string")
		e.find_term_label = _tr("find_term")
	_apply_mode()
	if Engine.is_editor_hint():
		var ed_theme: Theme = EditorInterface.get_editor_theme()
		for node_name in BUTTON_ICONS:
			for icon_name in BUTTON_ICONS[node_name]:
				if ed_theme.has_icon(icon_name, &"EditorIcons"):
					_button(node_name).icon = ed_theme.get_icon(icon_name, &"EditorIcons")
					break
		var search_icon: Texture2D = ed_theme.get_icon(&"Search", &"EditorIcons") if ed_theme.has_icon(&"Search", &"EditorIcons") else null
		for node_name in SEARCH_FIELDS:
			(get_node("%" + node_name) as LineEdit).right_icon = search_icon
		for e in [_source_edit, _target_edit]:
			e.find_icon = search_icon


## Status of one translation cell: SheetModel.ST_* or "stale".
static func _status_of(t: Dictionary) -> String:
	if bool(t.get("stale", false)):
		return "stale"
	return String(t.get("status", SheetModel.ST_NONE))


## Coloured dot icon for a status (cached per status).
func _dot(status: String) -> Texture2D:
	if _dots.has(status):
		return _dots[status]
	var px: int = 12
	if Engine.is_editor_hint():
		px = roundi(12 * EditorInterface.get_editor_scale())
	var col: Color = STATUS_COLORS.get(status, STATUS_COLORS[SheetModel.ST_NONE])
	var img: Image = Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r: float = px / 2.0
	for y in px:
		for x in px:
			var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(col, clampf(r - 0.5 - d + 0.5, 0.0, 1.0)))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_dots[status] = tex
	return tex


# ── data ────────────────────────────────────────────────────────────────

## Re-reads config · sources from disk and redraws (selection kept).
func _load() -> void:
	_lines_cache.clear()
	var old_issues: Array = _model.issue_items if _model != null and _model.validated else []
	_l = L10n.open()
	_l.echo = false
	_model = SheetModel.new()
	if not _l.ok():
		_model.setup(null, null, {})
		_set_status(_tr("cfg_failed"), true)
	else:
		_model.setup(_l.config, _l.catalog, SheetModel.read_index(_l.config.gen_dir.path_join("index.json")))
		if not old_issues.is_empty():
			_model.set_issues(old_issues)
		var n_err: int = _l.catalog.load_issues.error_count()
		if n_err > 0:
			_set_status(_tr("load_errors") % n_err, true)
		var keep: PackedStringArray = PackedStringArray()
		for loc in _l.config.target_locales():
			if _sel_locales.has(loc):
				keep.append(loc)
		_sel_locales = keep
		var terms: Array = []
		for g in _model.glossary_terms():
			if String(g["key"]) != "":
				terms.append({"id": g["term_id"], "key": g["key"], "text": (g["texts"] as Dictionary).get(_l.config.source_locale, ""), "texts": g["texts"]})
		for e in [_source_edit, _target_edit]:
			e.key_prefix = _l.config.key_prefix
			e.terms = terms
	_build_columns()
	_fill_options()
	_refresh_all()


## Called by plugin.gd after its menu commands.
func refresh() -> void:
	if is_visible_in_tree():
		_load()


## plugin.gd forwards EditorPlugin.scene_changed — the scene preview follows the edited scene.
func on_scene_changed(_scene_root: Node) -> void:
	_preview_dirty = true
	if _is_preview_shown():
		_refresh_preview()


func _refresh_all() -> void:
	_refresh_list()
	_refresh_glossary()
	_refresh_orphans()
	_update_hint()
	if _is_preview_shown():
		_refresh_preview()
	else:
		_preview_dirty = true


func _update_hint() -> void:
	_hint.text = _tr("no_usage_hint") if _model != null and _l != null and _l.ok() and not _model.has_usage_data() else ""


func _ready_model() -> bool:
	if _model == null:
		_load()
	return _l != null and _l.ok()


## Target languages whose columns are shown — all when nothing is picked.
func _shown_targets() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _l == null or not _l.ok():
		return out
	for loc in _l.config.target_locales():
		if _sel_locales.is_empty() or _sel_locales.has(loc):
			out.append(loc)
	return out


## Keys: key · alias · source always, target languages per the language menu, meta columns only
## when languages are picked. Glossary: term_id · alias · source · targets · forbidden · dnt · note.
func _build_columns() -> void:
	_cols.clear()
	_gcols.clear()
	if _l == null or not _l.ok():
		return
	var src: Dictionary = {"kind": KIND_TEXT, "column": _l.config.source_locale, "title": _tr("source") % _l.config.source_locale}
	_cols.append({"kind": KIND_KEY, "column": "key", "title": "key"})
	_cols.append({"kind": KIND_ALIAS, "column": "alias", "title": "alias"})
	_cols.append(src)
	_gcols.append({"kind": KIND_INFO, "column": "term_id", "title": "term_id"})
	_gcols.append({"kind": KIND_ALIAS, "column": "alias", "title": "alias"})
	_gcols.append(src.duplicate())
	for loc in _shown_targets():
		_cols.append({"kind": KIND_TEXT, "column": loc, "title": loc})
		_gcols.append({"kind": KIND_TEXT, "column": loc, "title": loc})
	if not _sel_locales.is_empty():
		for c in L10n.EDIT_META_COLS:
			_cols.append({"kind": KIND_META, "column": c, "title": c})
	_gcols.append({"kind": KIND_INFO, "column": "forbidden", "title": _tr("forbidden")})
	_gcols.append({"kind": KIND_INFO, "column": "dnt", "title": "dnt"})
	_gcols.append({"kind": KIND_INFO, "column": "note", "title": "note"})


static func _col_in(cols: Array, column: String) -> int:
	for i in cols.size():
		if cols[i]["column"] == column:
			return i
	return -1


func _col_index(column: String) -> int:
	return _col_in(_cols, column)


# ── drawing ─────────────────────────────────────────────────────────────

func _fill_options() -> void:
	var dom: String = _selected_meta(_domain)
	_domain.clear()
	_domain.add_item(_tr("all_domains"))
	_domain.set_item_metadata(0, "")
	for d in _model.domains():
		_domain.add_item(d)
		_domain.set_item_metadata(_domain.item_count - 1, d)
	_select_by_meta(_domain, dom)
	_fill_status_menu(_status_menu, _sel_statuses)
	_fill_status_menu(_gl_status_menu, _gl_statuses)
	_fill_locale_menu()


## Language menu: "all" + one check item per language; button text = "모든 언어" / "언어: a, b".
func _fill_locale_menu() -> void:
	var pm: PopupMenu = _locale_menu.get_popup()
	pm.clear()
	pm.add_radio_check_item(_tr("all_langs"), MENU_ALL_ID)
	pm.set_item_checked(0, _sel_locales.is_empty())
	pm.add_separator()
	var locs: PackedStringArray = _l.config.locales if _l != null and _l.ok() else PackedStringArray()
	for i in locs.size():
		# The source column is always shown — listed checked and disabled, marked as source.
		var is_src: bool = locs[i] == _l.config.source_locale
		pm.add_check_item(_tr("source") % locs[i] if is_src else locs[i], MENU_ALL_ID + 1 + i)
		pm.set_item_checked(pm.item_count - 1, is_src or _sel_locales.has(locs[i]))
		pm.set_item_disabled(pm.item_count - 1, is_src)
	_locale_menu.text = _tr("all_langs") if _sel_locales.is_empty() else _tr("langs") % ", ".join(_sel_locales)


## Status menu: one check item (with its dot) per status; all checked reads "모든 상태".
func _fill_status_menu(mb: MenuButton, sel: PackedStringArray) -> void:
	var pm: PopupMenu = mb.get_popup()
	pm.clear()
	var names: PackedStringArray = PackedStringArray()
	for i in STATUS_CHOICES.size():
		var st: String = STATUS_CHOICES[i]
		pm.add_icon_check_item(_dot(st), _tr(st), i)
		pm.set_item_checked(i, sel.has(st))
		if sel.has(st):
			names.append(_tr(st))
	if sel.size() == STATUS_CHOICES.size():
		mb.text = _tr("all_status")
	elif sel.is_empty():
		mb.text = _tr("status_none")
	else:
		mb.text = _tr("statuses") % ", ".join(names)


## Filter menu: one check item per filter. The button is an icon; while any filter is on it gets
## an accent background and the tooltip lists the filters in use.
func _fill_filter_menu() -> void:
	var pm: PopupMenu = _filter_menu.get_popup()
	pm.clear()
	var on: PackedStringArray = PackedStringArray()
	for i in FILTER_CHOICES.size():
		pm.add_check_item(_tr(FILTER_TEXTS[i]), i)
		pm.set_item_checked(i, _sel_filters.has(FILTER_CHOICES[i]))
		pm.set_item_tooltip(i, _tr(FILTER_TIPS[i]))
		if _sel_filters.has(FILTER_CHOICES[i]):
			on.append(_tr(FILTER_TEXTS[i]))
	_filter_menu.tooltip_text = _tr("filter_tip") + ("" if on.is_empty() else "\n" + _tr("filters_on") % ", ".join(on))
	for sb_name in [&"normal", &"hover", &"pressed", &"focus"]:
		_filter_menu.remove_theme_stylebox_override(sb_name)
	_filter_menu.flat = on.is_empty()
	if not on.is_empty():
		var accent: Color = get_theme_color(&"accent_color", &"Editor") if Engine.is_editor_hint() else Color(0.44, 0.73, 0.98)
		for sb_name in [&"normal", &"hover", &"pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(accent, 0.45 if sb_name == &"normal" else 0.6)
			sb.set_corner_radius_all(3)
			sb.set_content_margin_all(4)
			_filter_menu.add_theme_stylebox_override(sb_name, sb)


## Filter menu click: toggles one filter. The glossary filter needs check results: the first time
## it is ticked the checks run (they redraw the list).
func _on_filter_menu_id(id: int) -> void:
	if id < 0 or id >= FILTER_CHOICES.size():
		return
	var f: String = FILTER_CHOICES[id]
	if _sel_filters.has(f):
		_sel_filters.remove_at(_sel_filters.find(f))
	else:
		_sel_filters.append(f)
	_fill_filter_menu()
	if f == "glossary" and _sel_filters.has(f) and _model != null and not _model.validated:
		_run_checks()
		return
	_refresh_list()


# ── edit mode ───────────────────────────────────────────────────────────

func _can_edit() -> bool:
	return _mode != MODE_READ


func _set_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	_apply_mode()
	_show_dock(true)


## Shows / enables what the mode allows: approve = admin (shown dimmed otherwise), add · remove
## row · Build Data = edit modes; the dock fields follow in _show_dock.
func _apply_mode() -> void:
	for mb in [_approve, _gl_approve]:
		(mb as MenuButton).disabled = _mode != MODE_ADMIN
		(mb as MenuButton).tooltip_text = _tr("approve_tip") if _mode == MODE_ADMIN else _tr("approve_locked")
	(%AddRow as Button).visible = _can_edit()
	_remove_row.visible = _can_edit()
	_update_remove_row()
	(%BuildData as Button).disabled = not _can_edit()


## Remove row is enabled only while a Keys row is selected (dimmed otherwise).
func _update_remove_row() -> void:
	var has_row: bool = _sel_key != "" and _model != null and not _model.row_of(_sel_key).is_empty()
	_remove_row.disabled = not (_can_edit() and has_row)
	_remove_row.tooltip_text = _tr("remove_tip") if has_row else _tr("remove_pick")


## The status filter for search: null when every status is picked (no condition).
static func _status_filter(sel: PackedStringArray) -> Variant:
	return null if sel.size() == STATUS_CHOICES.size() else sel


## Column titles (sorted column gets ▲ / ▼) and width rules of a table.
func _setup_columns(tree: Tree, cols: Array, which: String) -> void:
	tree.columns = maxi(cols.size(), 1)
	var st: Dictionary = _sort[which]
	for c in cols.size():
		var kind: String = cols[c]["kind"]
		var column: String = cols[c]["column"]
		var title: String = cols[c]["title"]
		if st["column"] == column:
			title += "  ▼" if st["desc"] else "  ▲"
		tree.set_column_title(c, title)
		tree.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)
		tree.set_column_clip_content(c, true)
		var narrow: bool = column == "max_len" or column == "dnt"
		tree.set_column_expand(c, kind == KIND_TEXT or ((kind == KIND_META or kind == KIND_INFO) and not narrow and column != "term_id"))
		tree.set_column_expand_ratio(c, 3 if kind == KIND_TEXT else 1)
		var min_w: int = 140
		match kind:
			KIND_KEY:
				min_w = 130
			KIND_ALIAS:
				min_w = 240 if which == "keys" else 180
			KIND_TEXT:
				min_w = 200 if which == "keys" else 140
		if narrow:
			min_w = 64
		tree.set_column_custom_minimum_width(c, min_w)


## Sorts rows in place by the table's sort column (natural, case-insensitive). value(row, col).
func _sort_rows(rows: Array, which: String, cols: Array, value: Callable) -> void:
	var st: Dictionary = _sort[which]
	var col: int = _col_in(cols, String(st["column"]))
	if col < 0:
		return
	var desc: bool = st["desc"]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var c: int = String(value.call(a, col)).naturalnocasecmp_to(String(value.call(b, col)))
		return c > 0 if desc else c < 0)


## Header click: sort by that column; clicking it again cycles ascending → descending → off.
func _on_title_clicked(which: String, col: int) -> void:
	var cols: Array = _cols if which == "keys" else _gcols
	if col < 0 or col >= cols.size():
		return
	var st: Dictionary = _sort[which]
	if st["column"] == cols[col]["column"]:
		if st["desc"]:
			st["column"] = ""
		st["desc"] = not st["desc"] and st["column"] != ""
	else:
		st["column"] = cols[col]["column"]
		st["desc"] = false
	if which == "keys":
		_refresh_list()
	else:
		_refresh_glossary()


## Tints every cell of the selected row except the clicked one (that keeps the selection look).
func _tint_row(which: String, tree: Tree, item: TreeItem, sel_col: int) -> void:
	var prev: Variant = _tinted.get(which)
	if prev != null and is_instance_valid(prev):
		for c in tree.columns:
			(prev as TreeItem).clear_custom_bg_color(c)
	_tinted.erase(which)
	if item == null:
		return
	var tint: Color = get_theme_color(&"accent_color", &"Editor")
	tint.a = ROW_TINT_ALPHA
	for c in tree.columns:
		if c != sel_col:
			item.set_custom_bg_color(c, tint)
	_tinted[which] = item


func _refresh_list() -> void:
	_sheet.clear()
	_tinted.erase("keys")
	if _model == null:
		return
	_setup_columns(_sheet, _cols, "keys")
	var root: TreeItem = _sheet.create_item()
	var filters: Dictionary = {"domain": _selected_meta(_domain), "locales": _shown_targets()}
	for f in FILTER_CHOICES:
		filters[f] = _sel_filters.has(f)
	var sts: Variant = _status_filter(_sel_statuses)
	if sts != null:
		filters["statuses"] = sts
	var res: Array = _model.search(_search.text, filters)
	_sort_rows(res, "keys", _cols, _cell_value)
	var sel_item: TreeItem = null
	for r in res:
		var it: TreeItem = _sheet.create_item(root)
		_fill_item(it, r)
		if r["key"] == _sel_key:
			sel_item = it
	_count.text = "%d / %d" % [res.size(), _model.rows.size()]
	if _pending_key != "":
		_add_pending_item()
	_pad_sheet()
	var sel_col: int = _col_index(_sel_column)
	if sel_item != null and sel_col >= 0:
		sel_item.select(sel_col)
		_tint_row("keys", _sheet, sel_item, sel_col)
		_sheet.scroll_to_item(sel_item, true)
	else:
		_sel_key = ""
		_sel_column = ""
	_show_dock()


## Height of one table row (font or icon, plus the tree's row gap).
func _tree_row_height(tree: Tree) -> float:
	var font: Font = tree.get_theme_font(&"font")
	var h: float = font.get_height(tree.get_theme_font_size(&"font_size"))
	if Engine.is_editor_hint():
		h = maxf(h, 16 * EditorInterface.get_editor_scale())
	return h + tree.get_theme_constant(&"v_separation") + 2


## Empty rows under the last key so the last row (a new one) can scroll up to the middle.
## Padding rows have no metadata and cannot be selected.
func _pad_sheet() -> void:
	var root: TreeItem = _sheet.get_root()
	if root == null:
		return
	var last: TreeItem = root.get_child(root.get_child_count() - 1) if root.get_child_count() > 0 else null
	while last != null and last.get_metadata(0) == null:
		root.remove_child(last)
		last.free()
		last = root.get_child(root.get_child_count() - 1) if root.get_child_count() > 0 else null
	var n: int = floori(_sheet.size.y / _tree_row_height(_sheet) / 2.0)
	for i in n:
		var it: TreeItem = _sheet.create_item(root)
		for c in _sheet.columns:
			it.set_selectable(c, false)


## The add-row placeholder (key issued, alias still being typed): last real row, tinted.
func _add_pending_item() -> TreeItem:
	var root: TreeItem = _sheet.get_root()
	var idx: int = 0
	while idx < root.get_child_count() and root.get_child(idx).get_metadata(0) != null:
		idx += 1
	var it: TreeItem = _sheet.create_item(root, idx)
	it.set_metadata(0, "")
	var tint: Color = get_theme_color(&"accent_color", &"Editor")
	tint.a = ROW_TINT_ALPHA * 2
	for c in _sheet.columns:
		it.set_selectable(c, false)
		it.set_custom_bg_color(c, tint)
		match String(_cols[c]["kind"]) if c < _cols.size() else "":
			KIND_KEY:
				it.set_text(c, _pending_key)
			KIND_ALIAS:
				it.set_text(c, _tr("ar_new_row"))
	return it


func _fill_item(it: TreeItem, r: Dictionary) -> void:
	if r.is_empty():
		return
	it.set_metadata(0, r["key"])
	var max_len: int = String(r["max_len"]).to_int()
	for c in _cols.size():
		var kind: String = _cols[c]["kind"]
		var column: String = _cols[c]["column"]
		it.clear_custom_color(c)
		if kind == KIND_KEY or kind == KIND_ALIAS:
			it.set_text(c, r["key"] if kind == KIND_KEY else r["alias"])
			it.set_tooltip_text(c, "%s\n%s\n%s · %s\n%s:%d" % [r["key"], r["alias"], r["domain"], r["status"], r["file"], int(r["line"])])
			if r["status"] != "active":
				it.set_custom_color(c, Color(1, 1, 1, 0.45))
			continue
		var value: String = _cell_value(r, c)
		var tip: String = value
		it.set_text(c, value.replace("\n", " ⏎ "))
		if kind == KIND_TEXT:
			if column != _l.config.source_locale:
				var st: String = _status_of((r["tr"] as Dictionary).get(column, {}))
				it.set_icon(c, _dot(st))
				tip = "[%s]\n%s" % [_tr(st), value]
			if max_len > 0 and value.length() > max_len:
				it.set_custom_color(c, get_theme_color(&"warning_color", &"Editor"))
				tip += "\n\n(%s)" % (_tr("over_len") % [max_len, value.length()])
		it.set_tooltip_text(c, tip)


## Text of a Keys cell for row r.
func _cell_value(r: Dictionary, col: int) -> String:
	var kind: String = _cols[col]["kind"]
	var column: String = _cols[col]["column"]
	match kind:
		KIND_KEY:
			return String(r["key"])
		KIND_ALIAS:
			return String(r["alias"])
		KIND_META:
			return String(r.get(column, ""))
	if column == _l.config.source_locale:
		return String(r["source"])
	return String(((r["tr"] as Dictionary).get(column, {}) as Dictionary).get("text", ""))


# ── bottom dock (row of the selected cell) ─────────────────────────────

## Key of the row the dock shows: Keys selection, or the selected term's linked key.
func _dock_row_key() -> String:
	if _tabs.current_tab == TAB_GLOSSARY:
		return String(_term(_gl_term).get("key", ""))
	return _sel_key


## Column name of the selected cell in the current table.
func _dock_column() -> String:
	return _gl_column if _tabs.current_tab == TAB_GLOSSARY else _sel_column


## Target language: the selected cell's language, else the previous one if still shown, else the
## first shown target.
func _resolve_target() -> String:
	var shown: PackedStringArray = _shown_targets()
	var col: String = _dock_column()
	if shown.has(col):
		return col
	if shown.has(_target_loc):
		return _target_loc
	return shown[0] if not shown.is_empty() else ""


## Fills the dock with the selected row. Unless force, unsaved edits of the same row · language
## are kept (a filter redraw does not wipe them); Revert and Apply force.
func _show_dock(force: bool = false) -> void:
	_update_remove_row()
	if _model == null or _l == null or not _l.ok():
		_clear_dock("")
		return
	var key: String = _dock_row_key()
	var r: Dictionary = _model.row_of(key) if key != "" else {}
	_show_usages(r)
	if r.is_empty():
		var msg: String = _tr("dock_pick")
		if _tabs.current_tab == TAB_GLOSSARY and _gl_term != "":
			msg = _tr("term_no_key") % [_gl_term, int(_term(_gl_term).get("line", 0))]
		_clear_dock(msg)
		return
	var target: String = _resolve_target()
	# Example language follows the clicked cell: source column → source, a language → that one.
	var col: String = _dock_column()
	if col == _l.config.source_locale:
		_example_loc = col
	elif col == target or _example_loc != _l.config.source_locale:
		_example_loc = target
	if not force and key == _dock_key and target == _target_loc and not _dock_edits().is_empty():
		_update_dock_live()
		return
	_dock_key = key
	_target_loc = target
	_dock_title.text = "%s  ·  %s" % [key, r["alias"]]
	_dock_sub.text = "%s · %s:%d · %s" % [r["domain"], String(r["file"]).get_file(), int(r["line"]), r["status"]]
	_dock_sub.tooltip_text = String(r["file"])
	var src: String = String(r["source"])
	var tgt: String = String(((r["tr"] as Dictionary).get(target, {}) as Dictionary).get("text", "")) if target != "" else ""
	_dock_loaded = {"source": src, "target": tgt, "context": String(r["context"]), "max_len": String(r["max_len"]), "note": String(r["note"])}
	var can: bool = _can_edit()
	_filling = true
	_set_field(_source_edit, src, can)
	_set_field(_target_edit, tgt, can and target != "")
	_filling = false
	_context_edit.text = _dock_loaded["context"]
	_max_len_edit.text = _dock_loaded["max_len"]
	_note_edit.text = _dock_loaded["note"]
	for le in [_context_edit, _max_len_edit, _note_edit]:
		le.editable = can
	var ph: PackedStringArray = Tokens.placeholders(src, _l.config.josa_tags)
	var src_tags: PackedStringArray = ph.duplicate()
	for t in _l.config.josa_tags:
		src_tags.append(String(t))
	_source_edit.tags = src_tags
	_source_edit.offer_plural = false
	_target_edit.tags = ph
	_target_edit.offer_plural = true
	_source_edit.term_locale = _l.config.source_locale
	_target_edit.term_locale = target
	_update_dock_live()


func _clear_dock(msg: String) -> void:
	_dock_key = ""
	_dock_loaded = {}
	_show_usages({})
	_dock_title.text = msg
	_dock_sub.text = ""
	_dock_info.text = ""
	_dock_info.visible = false
	_filling = true
	_set_field(_source_edit, "", false)
	_set_field(_target_edit, "", false)
	_filling = false
	_example_edit.text = ""
	for le in [_context_edit, _max_len_edit, _note_edit]:
		le.text = ""
		le.editable = false
	_source_head.text = ""
	_target_head.text = ""
	_example_head.text = ""
	_target_dot.texture = null
	_apply.disabled = true
	_revert.disabled = true


static func _set_field(e: TextEdit, text: String, editable: bool) -> void:
	e.text = text
	e.editable = editable
	e.clear_undo_history()


## Heads (status, length vs max_len), example and info line: redrawn on every keystroke.
func _update_dock_live() -> void:
	var r: Dictionary = _model.row_of(_dock_key) if _model != null and _dock_key != "" else {}
	if r.is_empty():
		return
	var max_len: int = _max_len_edit.text.strip_edges().to_int()
	_set_head(_source_head, _tr("source") % _l.config.source_locale, _source_edit.text, max_len)
	if _target_loc == "":
		_target_dot.texture = null
		_target_head.text = _tr("no_target")
	else:
		var st: String = _status_of((r["tr"] as Dictionary).get(_target_loc, {}))
		_target_dot.texture = _dot(st)
		_target_dot.tooltip_text = _tr(st)
		_set_head(_target_head, _target_loc, _target_edit.text, max_len)
		_target_head.tooltip_text = _tr(st)
	# The example shows the last picked / edited language (source or target).
	var ex_loc: String = _l.config.source_locale if _example_loc == _l.config.source_locale or _target_loc == "" else _target_loc
	var text: String = _source_edit.text if ex_loc == _l.config.source_locale else _target_edit.text
	_example_head.text = "%s · %s" % [_tr("example"), ex_loc]
	_example_head.tooltip_text = _tr("example_tip") % ex_loc
	var shown: String = KeyRefs.expand(_l.catalog, text, ex_loc, "dev")
	_example_edit.text = shown if shown != "" or text == "" else _tr("example_bad")
	var parts: PackedStringArray = PackedStringArray()
	if not (r["glossary"] as Array).is_empty():
		parts.append(_tr("terms") % ", ".join(PackedStringArray(r["glossary"])))
	var codes: PackedStringArray = PackedStringArray()
	for it in _model.detail(_dock_key).get("issues", []):
		codes.append("%s %s" % [it["code"], it["msg"]])
	if not codes.is_empty():
		parts.append(_tr("issues") % " / ".join(codes))
	_dock_info.text = "\n".join(parts)
	_dock_info.visible = not parts.is_empty()
	var dirty: bool = not _dock_edits().is_empty()
	_apply.disabled = not dirty
	_revert.disabled = not dirty


## Typing in / focusing the source or target field makes the example follow that language.
func _on_example_field(e: TagEdit) -> void:
	if _l == null or not _l.ok():
		return
	if not _filling:
		_example_loc = _l.config.source_locale if e == _source_edit else _target_loc
	_update_dock_live()


## Field head (left column): language, plus "n / max" on a second line when max_len is set
## (warning colour when over).
func _set_head(head: Label, label: String, text: String, max_len: int) -> void:
	head.text = label if max_len <= 0 else "%s\n%s" % [label, _tr("len") % [text.length(), max_len]]
	if max_len > 0 and text.length() > max_len:
		head.add_theme_color_override(&"font_color", get_theme_color(&"warning_color", &"Editor"))
	else:
		head.remove_theme_color_override(&"font_color")


## Changed dock fields as cmd_edit items: source before target (the translation then gets the
## new source hash as a draft).
func _dock_edits() -> Array:
	var out: Array = []
	if _dock_key == "" or _dock_loaded.is_empty():
		return out
	if _source_edit.text != _dock_loaded["source"]:
		out.append({"key": _dock_key, "column": _l.config.source_locale, "value": _source_edit.text})
	if _target_loc != "" and _target_edit.text != _dock_loaded["target"]:
		out.append({"key": _dock_key, "column": _target_loc, "value": _target_edit.text})
	var metas: Dictionary = {"context": _context_edit.text, "max_len": _max_len_edit.text.strip_edges(), "note": _note_edit.text}
	for c in metas:
		if metas[c] != _dock_loaded[c]:
			out.append({"key": _dock_key, "column": c, "value": metas[c]})
	return out


func _on_apply_pressed() -> void:
	var edits: Array = _dock_edits()
	if edits.is_empty() or not _can_edit() or not _ready_model():
		return
	var key: String = _dock_key
	var err: String = _l.cmd_edit(edits)
	_model.rebuild()
	if err != "":
		_set_status(_tr("save_failed") % err, true)
		return
	var cols: PackedStringArray = PackedStringArray()
	for e in edits:
		cols.append(String(e["column"]))
	_set_status(_tr("saved") % [_model.row_of(key).get("alias", key), ", ".join(cols)], false)
	var it: TreeItem = _find_item(key)
	if it != null:
		_fill_item(it, _model.row_of(key))
	_refresh_glossary()
	_show_dock(true)


## Ctrl+Enter in any dock field = Apply.
func _on_dock_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and k.ctrl_pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_on_apply_pressed()


## Ctrl+C on the Keys / Glossary table copies the selected cell's full text.
## Blank rows (padding under the table, the pending add row) show no hover: Tree has no per-item
## hover flag, so the hover styleboxes are blanked while the mouse is over one.
func _on_sheet_hover(event: InputEvent) -> void:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm == null:
		return
	var it: TreeItem = _sheet.get_item_at_position(mm.position)
	_set_sheet_hover(it == null or (it.get_metadata(0) is String and String(it.get_metadata(0)) != ""))


func _set_sheet_hover(on: bool) -> void:
	if on != _hover_off:
		return
	_hover_off = not on
	for sb_name in [&"hovered", &"hovered_dimmed"]:
		if on:
			_sheet.remove_theme_stylebox_override(sb_name)
		else:
			_sheet.add_theme_stylebox_override(sb_name, StyleBoxEmpty.new())
	for c_name in [&"font_hovered_color", &"font_hovered_dimmed_color"]:
		if on:
			_sheet.remove_theme_color_override(c_name)
		else:
			_sheet.add_theme_color_override(c_name, _sheet.get_theme_color(&"font_color"))


func _on_table_input(event: InputEvent, tree: Tree) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_C or not k.is_command_or_control_pressed() or k.shift_pressed:
		return
	var it: TreeItem = tree.get_selected()
	var col: int = tree.get_selected_column()
	if it == null or col < 0 or _model == null:
		return
	var text: String = ""
	if tree == _sheet:
		var r: Dictionary = _model.row_of(String(it.get_metadata(0)))
		if r.is_empty() or col >= _cols.size():
			return
		text = _cell_value(r, col)
	else:
		var g: Dictionary = _term(String(it.get_metadata(0)))
		if g.is_empty() or col >= _gcols.size():
			return
		text = _gl_value(g, col)
	tree.accept_event()
	_copy(text)


## Double-click a cell → its dock field (source column → source, anything else → target).
func _focus_dock_field() -> void:
	if _dock_column() == _l.config.source_locale:
		_source_edit.grab_focus()
	elif _target_edit.editable:
		_target_edit.grab_focus()


# ── key picker ("find string" from tag completion) ─────────────────────

## terms = list glossary terms (their linked keys) instead of every key.
func _open_key_picker(edit: TagEdit, terms: bool) -> void:
	_kp_edit = edit
	_kp_terms = terms
	_key_picker.title = _tr("kp_term_title" if terms else "kp_title")
	_kp_search.text = ""
	_refresh_key_picker()
	_key_picker.popup_centered()
	_kp_search.grab_focus()


func _refresh_key_picker() -> void:
	_kp_tree.clear()
	if _model == null or _l == null or not _l.ok():
		return
	var loc: String = _target_loc if _target_loc != "" else _l.config.source_locale
	var titles: Array = ["term_id" if _kp_terms else "key", "alias", _tr("source") % _l.config.source_locale, loc]
	_kp_tree.columns = titles.size()
	for c in titles.size():
		_kp_tree.set_column_title(c, titles[c])
		_kp_tree.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)
		_kp_tree.set_column_clip_content(c, true)
		_kp_tree.set_column_expand(c, c >= 2)
		_kp_tree.set_column_custom_minimum_width(c, 130 if c == 0 else (220 if c == 1 else 160))
	var root: TreeItem = _kp_tree.create_item()
	var res: Array = _term_rows(_kp_search.text) if _kp_terms else _model.search(_kp_search.text)
	var first: TreeItem = null
	for i in res.size():
		if i == PICKER_MAX:
			var more: TreeItem = _kp_tree.create_item(root)
			more.set_text(1, _tr("kp_more") % (res.size() - PICKER_MAX))
			more.set_selectable(0, false)
			break
		var r: Dictionary = res[i]
		var it: TreeItem = _kp_tree.create_item(root)
		it.set_text(0, String(r.get("term_id", r["key"])))
		it.set_tooltip_text(0, r["key"])
		it.set_text(1, r["alias"])
		it.set_text(2, String(r["source"]).replace("\n", " "))
		var t: String = String(r["source"]) if loc == _l.config.source_locale else String(((r["tr"] as Dictionary).get(loc, {}) as Dictionary).get("text", ""))
		it.set_text(3, t.replace("\n", " "))
		it.set_metadata(0, r["key"])
		if first == null:
			first = it
	if first != null:
		first.select(0)


## OK / Enter → the selected key into the field that asked.
func _on_key_picked() -> void:
	var it: TreeItem = _kp_tree.get_selected()
	var key: Variant = it.get_metadata(0) if it != null else null
	if key is String and _kp_edit != null and is_instance_valid(_kp_edit):
		_kp_edit.insert_key_ref(key)


## Key rows of the glossary terms linked to a key, each with its term_id, matching the query
## (term_id · key · alias · texts, case-insensitive), glossary order.
func _term_rows(query: String) -> Array:
	var q: String = query.strip_edges().to_lower()
	var out: Array = []
	for g in _model.glossary_terms():
		var r: Dictionary = _model.row_of(String(g["key"]))
		if r.is_empty():
			continue
		var hay: PackedStringArray = PackedStringArray([g["term_id"], r["key"], r["alias"], r["source"]])
		for loc in (r["tr"] as Dictionary):
			hay.append(String(((r["tr"] as Dictionary)[loc] as Dictionary).get("text", "")))
		if q != "" and " ".join(hay).to_lower().find(q) < 0:
			continue
		var row: Dictionary = r.duplicate()
		row["term_id"] = g["term_id"]
		out.append(row)
	return out


func _on_key_picker_activated() -> void:
	_on_key_picked()
	_key_picker.hide()


## Bottom usage list: the key's source CSV row first, then index.json usages.
func _show_usages(r: Dictionary) -> void:
	_usage_tree.clear()
	_usage_title.text = _tr("usages")
	var root: TreeItem = _usage_tree.create_item()
	if r.is_empty():
		_fit_usage_tree()
		return
	var src: Dictionary = _source_usage(r)
	_usage_row(root, _tr("source_item") % String(src["file"]).get_file(), _file_icon(src["file"]), String(src["file"]), src)
	if not _model.has_usage_data():
		_usage_row(root, _tr("no_usage_data"), null, "", null)
		_fit_usage_tree()
		return
	var files: Array = _usage_files(r["usages"], String(r["file"]))
	_usage_title.text = _tr("usages_of") % files.size()
	if files.is_empty():
		_usage_row(root, _tr("no_usages"), null, "", null)
	for e in _usage_entries(files, r):
		var it: TreeItem = _usage_row(root, e["label"], e["icon"], e["tip"], e["usage"])
		for c in e["screens"]:
			_usage_row(it, c["label"], c["icon"], c["tip"], c["usage"])
		it.collapsed = true
	_fit_usage_tree()


## One usage tree row; usage null = a plain note (not selectable).
func _usage_row(parent: TreeItem, label: String, icon: Texture2D, tip: String, usage: Variant) -> TreeItem:
	var it: TreeItem = _usage_tree.create_item(parent)
	it.set_text(0, label)
	if icon != null:
		it.set_icon(0, icon)
	it.set_tooltip_text(0, tip)
	it.set_metadata(0, usage)
	it.set_selectable(0, usage != null)
	return it


func _fit_usage_tree() -> void:
	_fit_dock_tree(_usage_tree)


## Dock tables have no scroll of their own (the dock scrolls): height = visible rows (+ titles).
func _fit_dock_tree(tree: Tree) -> void:
	var rows: int = 1 if tree.column_titles_visible else 0
	var it: TreeItem = tree.get_root().get_next_visible() if tree.get_root() != null else null
	while it != null:
		rows += 1
		it = it.get_next_visible()
	var font: Font = tree.get_theme_font(&"font")
	var row_h: float = font.get_height(tree.get_theme_font_size(&"font_size")) + tree.get_theme_constant(&"v_separation")
	if Engine.is_editor_hint():
		row_h = maxf(row_h, 16 * EditorInterface.get_editor_scale() + tree.get_theme_constant(&"v_separation"))
	var panel: StyleBox = tree.get_theme_stylebox(&"panel")
	tree.custom_minimum_size.y = rows * (row_h + 2) + (panel.get_minimum_size().y if panel != null else 0.0) + 4


## Wheel over a dock table scrolls the dock (the table itself never scrolls).
func _on_dock_table_input(event: InputEvent, tree: Tree) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or (mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN):
		return
	var bar: VScrollBar = _dock_scroll.get_v_scroll_bar()
	var step: float = bar.page / 8.0 * (mb.factor if mb.factor > 0.0 else 1.0)
	bar.value += -step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step
	tree.accept_event()


static func _source_usage(r: Dictionary) -> Dictionary:
	return {"kind": USAGE_SOURCE, "file": String(r["file"]), "line": int(r["line"])}


## Usage rows: each usage file with the screen scenes it ends up in (ScreenMap) as child rows
## that open the scene (the dock tree shows them folded, the row menu indented).
## [{label, icon, tip, usage, screens: [{label, icon, tip, usage}]}].
func _usage_entries(files: Array, r: Dictionary) -> Array:
	var out: Array = []
	for u in files:
		var f: String = String(u["file"])
		var screens: Array = []
		for h in _screens_of(f):
			var scene: String = String(h["path"])
			if scene == f:
				continue
			var chain: PackedStringArray = PackedStringArray()
			for c in h["chain"]:
				chain.append(String(c).get_file())
			screens.append({"label": scene.get_file(), "icon": _file_icon(scene),
				"tip": "%s\n%s" % [scene, _tr("screen_line") % [h["screen"], " › ".join(chain)]],
				"usage": {"kind": USAGE_SCREEN, "file": scene, "line": 0}})
		out.append({"label": f.get_file(), "icon": _file_icon(f), "tip": _usage_tip(u, r), "usage": u, "screens": screens})
	return out


## Usage tooltip: path · screens with the chain that leads there · each place in the file (code
## line, or the scene node + property) · what to search for — code refers to a key by its `L`
## constant (alias upper-cased, dots → "_"), runtime-built keys through a `# l10n-dynamic:`
## pattern comment, scenes and data rows by the raw key.
func _usage_tip(u: Dictionary, r: Dictionary) -> String:
	var f: String = String(u.get("file", ""))
	var out: PackedStringArray = PackedStringArray([f, ""])
	var hits: Array = _screens_of(f)
	if hits.is_empty():
		out.append(_tr("screen_none"))
	for h in hits:
		var chain: PackedStringArray = PackedStringArray()
		for c in h["chain"]:
			chain.append(String(c).get_file())
		out.append(_tr("screen_line") % [h["screen"], " › ".join(chain)])
	out.append("")
	var lines: PackedStringArray = _file_lines(f)
	var shown: int = 0
	for v in r["usages"]:
		if String(v.get("file", "")) != f:
			continue
		if shown == PREVIEW_LINES:
			out.append("…")
			break
		var n: int = int(v.get("line", 0))
		var code: String = lines[n - 1].strip_edges() if n >= 1 and n <= lines.size() else ""
		if f.ends_with(".tscn"):
			var node: String = ScreenMap.node_path_at(lines, n)
			code = "%s.%s" % [node if node != "" else "?", code.get_slice("=", 0).strip_edges()]
		out.append("%d │ %s" % [n, code.left(PREVIEW_COLS) + ("…" if code.length() > PREVIEW_COLS else "")])
		shown += 1
	var hint: String = _tr("look_for") % String(r["key"])
	match String(u.get("kind", "")):
		"const":
			hint = _tr("look_for") % ("L." + String(r["alias"]).to_upper().replace(".", "_"))
		"dynamic":
			hint = _tr("look_dynamic")
	out.append("")
	out.append(hint)
	return "\n".join(out)


## Screens a file ends up in — ScreenMap, built on first use (≈ 0.25 s) and kept until the
## reload / scan buttons.
func _screens_of(path: String) -> Array:
	if _screen_map == null and _l != null and _l.ok():
		_screen_map = ScreenMap.build(String(ProjectSettings.get_setting("application/run/main_scene", "")))
	return _screen_map.call("screens_of", path) if _screen_map != null else []


## File lines for previews (cached until the next load).
func _file_lines(path: String) -> PackedStringArray:
	if not _lines_cache.has(path):
		_lines_cache[path] = FileAccess.get_file_as_string(path).split("\n") if FileAccess.file_exists(path) else PackedStringArray()
	return _lines_cache[path]


static func _use_external_editor() -> bool:
	var es: EditorSettings = EditorInterface.get_editor_settings()
	return es.has_setting("text_editor/external/use_external_editor") and bool(es.get_setting("text_editor/external/use_external_editor"))


## One usage per file (its first line): the list shows file names, not lines. The key's own
## source CSV (source_file) is left out: it already has its "원본" row.
static func _usage_files(usages: Array, source_file: String) -> Array:
	var seen: Dictionary = {source_file: true}
	var out: Array = []
	for u in usages:
		var f: String = String(u.get("file", ""))
		if not seen.has(f):
			seen[f] = true
			out.append(u)
	return out


## FileSystem-dock icon for a file: its resource type's editor icon, else the generic file icon.
func _file_icon(path: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var ed_theme: Theme = EditorInterface.get_editor_theme()
	# CSVs sit under .gdignore (never imported) so the filesystem has no type for them: every
	# CSV (l10n source or data table) gets the green grid icon.
	var names: Array = [EditorInterface.get_resource_filesystem().get_file_type(path)]
	if path.get_extension().to_lower() == "csv":
		names = ["GridContainer", "Grid", "TextFile"]
	names.append("File")
	for icon_name in names:
		if icon_name != "" and ed_theme.has_icon(icon_name, &"EditorIcons"):
			return ed_theme.get_icon(icon_name, &"EditorIcons")
	return null


## Opens a usage: .gd line · scene · resource in Godot, anything else in the external editor.
func _go_usage(u: Dictionary) -> void:
	var a: Dictionary = SheetModel.usage_action(u)
	var path: String = a["path"]
	if a["kind"] != SheetModel.KIND_COPY and not ResourceLoader.exists(path):
		a["kind"] = SheetModel.KIND_COPY
	match a["kind"]:
		SheetModel.KIND_SCRIPT:
			# With an external editor on, Godot hands it the file without the line — go direct.
			if _use_external_editor():
				_open_external(path, int(a["line"]))
			else:
				EditorInterface.edit_script(load(path), maxi(int(a["line"]), 1))
				EditorInterface.set_main_screen_editor("Script")
		SheetModel.KIND_SCENE:
			EditorInterface.open_scene_from_path(path)
			EditorInterface.set_main_screen_editor("2D")
		SheetModel.KIND_RESOURCE:
			EditorInterface.edit_resource(load(path))
		_:
			_open_external(path, int(a["line"]))


## Opens a file in the external editor of the editor settings (text_editor/external/exec_path ·
## exec_flags) at a line — VS Code with plain "{file}" flags gets "--goto" so the line is kept.
## No external editor configured, a missing file or a failed launch → popup (OpenDialog).
## Every launch is printed to Output.
func _open_external(path: String, line: int) -> void:
	var file: String = ProjectSettings.globalize_path(path)
	_open_file = file
	if not FileAccess.file_exists(file):
		_show_open_dialog(_tr("open_missing") % file, false)
		return
	var exe: String = _external_editor()
	if exe == "":
		_show_open_dialog(_tr("open_no_editor") % file, true)
		return
	var es: EditorSettings = EditorInterface.get_editor_settings()
	var flags: String = String(es.get_setting("text_editor/external/exec_flags")).strip_edges() if es.has_setting("text_editor/external/exec_flags") else ""
	if (flags == "" or flags == "{file}") and exe.get_file().to_lower().begins_with("code"):
		flags = "{project} --goto {file}:{line}:{col}"
	elif flags == "":
		flags = "{file}"
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var args: PackedStringArray = PackedStringArray()
	for part in _split_args(flags):
		args.append(part.replace("{project}", project).replace("{file}", file).replace("{line}", str(maxi(line, 1))).replace("{col}", "1"))
	# An editor started from a VS Code extension inherits ELECTRON_RUN_AS_NODE=1, which makes
	# Code.exe run as plain Node and exit without opening anything — drop it for the child only.
	var saved_env: Dictionary = {}
	for k in CHILD_ENV_STRIP:
		if OS.has_environment(k):
			saved_env[k] = OS.get_environment(k)
			OS.unset_environment(k)
	var pid: int = OS.create_process(exe, args)
	for k in saved_env:
		OS.set_environment(k, saved_env[k])
	print("L10n: open %s %s → pid %d" % [exe, args, pid])
	if pid <= 0:
		_show_open_dialog(_tr("open_launch_failed") % [exe, file], true)
		return
	_set_status(_tr("opened") % ("%s:%d" % [path.trim_prefix("res://"), line]), false)


## The external editor executable from the editor settings, "" when unset or missing on disk.
static func _external_editor() -> String:
	var es: EditorSettings = EditorInterface.get_editor_settings()
	if not es.has_setting("text_editor/external/exec_path"):
		return ""
	var exe: String = String(es.get_setting("text_editor/external/exec_path")).strip_edges()
	return exe if exe != "" and FileAccess.file_exists(exe) else ""


## Popup for a file that could not be opened. offer_open = also offer "copy path" and
## "open with the default app" (the file exists).
func _show_open_dialog(msg: String, offer_open: bool) -> void:
	_set_status(msg.get_slice("\n", 0), true)
	for b in _open_dialog_buttons:
		if is_instance_valid(b):
			_open_dialog.remove_button(b)
	_open_dialog_buttons.clear()
	_open_dialog.title = _tr("open_title")
	_open_dialog.dialog_text = msg
	if offer_open:
		_open_dialog_buttons.append(_open_dialog.add_button(_tr("copy_path"), false, "copy"))
		_open_dialog_buttons.append(_open_dialog.add_button(_tr("open_default"), false, "shell"))
	_open_dialog.popup_centered()


func _on_open_dialog_action(action: StringName) -> void:
	match String(action):
		"copy":
			_copy(_open_file)
		"shell":
			var err: int = OS.shell_open(_open_file)
			if err != OK:
				_set_status(_tr("open_failed") % _open_file, true)
	_open_dialog.hide()


## Splits exec flags on spaces, keeping double-quoted parts together (quotes dropped).
static func _split_args(flags: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var cur: String = ""
	var quoted: bool = false
	for ch in flags:
		if ch == "\"":
			quoted = not quoted
		elif ch == " " and not quoted:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func _copy(text: String) -> void:
	DisplayServer.clipboard_set(text)
	_set_status(_tr("copied") % text, false)


func _find_item(key: String) -> TreeItem:
	var root: TreeItem = _sheet.get_root()
	if root == null:
		return null
	var it: TreeItem = root.get_first_child()
	while it != null:
		if it.get_metadata(0) is String and String(it.get_metadata(0)) == key and key != "":
			return it
		it = it.get_next()
	return null


## Messages go to the Log tab; errors also pop an editor toast (there is no status line).
func _set_status(msg: String, is_error: bool) -> void:
	_append_log(PackedStringArray([msg]))
	if is_error:
		push_warning("L10n: " + msg)
		if Engine.is_editor_hint():
			EditorInterface.get_editor_toaster().push_toast("L10n: " + msg, EditorToaster.SEVERITY_WARNING)


# ── handlers ────────────────────────────────────────────────────────────

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_load()


## Sync Data = sync (edit modes only: it writes hashes into the sources) → scan + checks →
## index.json · report.md → reload from disk. Check results stay for the glossary filter · dock.
## Runs in slices (`L10n.sync_data_job`, SYNC_FRAME_MS of work per frame) under the modal
## SyncDialog (stage + progress bar, no close) so the editor keeps drawing.
func _on_sync_data_pressed() -> void:
	if _syncing or not _ready_model():
		return
	_syncing = true
	_screen_map = null
	var start: int = _l.output.size()
	var job = _l.sync_data_job(_can_edit())
	_sync_bar.value = 0.0
	_sync_stage.text = _tr("sync_stage_" + job.stage())
	_sync_dialog.popup_centered()
	await get_tree().process_frame
	var done: bool = false
	while not done:
		var t0: int = Time.get_ticks_msec()
		while not done and Time.get_ticks_msec() - t0 < SYNC_FRAME_MS:
			done = job.step()
		_sync_bar.value = job.progress() * 100.0
		_sync_stage.text = _tr("sync_stage_" + job.stage())
		await get_tree().process_frame
	_sync_dialog.hide()
	_syncing = false
	var n: int = int(job.result)
	_append_log(_l.output.slice(start))
	_model.set_issues(_l.issues.items)
	var idx: Dictionary = _l.index
	var errors: int = _l.issues.error_count()
	var warns: int = _l.issues.warn_count()
	_load()
	_set_status(_tr("sync_data_done") % [n, (idx.get("keys", {}) as Dictionary).size(), (idx.get("orphans", []) as Array).size(), errors, warns], errors > 0)


func _on_usage_activated() -> void:
	var it: TreeItem = _usage_tree.get_selected()
	var u: Variant = it.get_metadata(0) if it != null else null
	if u is Dictionary:
		_go_usage(u)


## Right-click on a row → copy key / alias, open the source CSV row, jump to a usage.
func _on_sheet_mouse_selected(mouse_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var it: TreeItem = _sheet.get_selected()
	if it == null or _model == null or not (it.get_metadata(0) is String) or String(it.get_metadata(0)) == "":
		return
	_on_cell_selected()
	_menu_key = String(it.get_metadata(0))
	var r: Dictionary = _model.row_of(_menu_key)
	_row_menu.clear()
	_row_menu.add_item(_tr("copy_key"), MENU_COPY_KEY)
	_row_menu.add_item(_tr("copy_alias"), MENU_COPY_ALIAS)
	_row_menu.add_separator()
	_row_menu.add_item(_tr("open_source"), MENU_OPEN_SOURCE)
	_row_menu.add_item(_tr("copy_source"), MENU_COPY_SOURCE)
	_row_menu.set_item_icon(_row_menu.get_item_index(MENU_OPEN_SOURCE), _file_icon(r["file"]))
	_row_menu.set_item_tooltip(_row_menu.get_item_index(MENU_OPEN_SOURCE), String(r["file"]))
	var files: Array = _usage_files(r.get("usages", []) as Array, String(r["file"]))
	_row_menu.add_separator(_tr("usages_menu") % files.size() if _model.has_usage_data() else _tr("no_usage_data"))
	_menu_usages = []
	for e in _usage_entries(files, r):
		for row in [e] + (e["screens"] as Array):
			var id: int = MENU_USAGE_BASE + _menu_usages.size()
			_menu_usages.append(row["usage"])
			_row_menu.add_icon_item(row["icon"], (SCREEN_INDENT if row != e else "") + String(row["label"]), id)
			_row_menu.set_item_tooltip(_row_menu.get_item_index(id), row["tip"])
	_row_menu.reset_size()
	_row_menu.popup(Rect2i(Vector2i(_sheet.get_screen_position() + mouse_pos), Vector2i.ZERO))


func _on_row_menu_id(id: int) -> void:
	var r: Dictionary = _model.row_of(_menu_key) if _model != null else {}
	if r.is_empty():
		return
	match id:
		MENU_COPY_KEY:
			_copy(_menu_key)
		MENU_COPY_ALIAS:
			_copy(String(r["alias"]))
		MENU_OPEN_SOURCE:
			_go_usage(_source_usage(r))
		MENU_COPY_SOURCE:
			_copy("%s:%d" % [r["file"], int(r["line"])])
		_:
			var i: int = id - MENU_USAGE_BASE
			if i >= 0 and i < _menu_usages.size():
				_go_usage(_menu_usages[i])


func _on_locale_menu_id(id: int) -> void:
	if _l == null or not _l.ok():
		return
	if id == MENU_ALL_ID:
		_sel_locales = PackedStringArray()
	else:
		var loc: String = _l.config.locales[id - MENU_ALL_ID - 1]
		if loc == _l.config.source_locale:
			return
		var picked: PackedStringArray = PackedStringArray()
		for l in _l.config.target_locales():
			if (l == loc) != _sel_locales.has(l):
				picked.append(l)
		_sel_locales = picked
	_fill_locale_menu()
	_build_columns()
	_refresh_list()
	_refresh_glossary()


## Status menu click: toggles one status of the Keys (glossary = false) or Glossary table.
func _on_status_menu_id(glossary: bool, id: int) -> void:
	if id < 0 or id >= STATUS_CHOICES.size():
		return
	var sel: PackedStringArray = _gl_statuses if glossary else _sel_statuses
	var picked: PackedStringArray = PackedStringArray()
	for st in STATUS_CHOICES:
		if (st == STATUS_CHOICES[id]) != sel.has(st):
			picked.append(st)
	if glossary:
		_gl_statuses = picked
		_fill_status_menu(_gl_status_menu, picked)
		_refresh_glossary()
	else:
		_sel_statuses = picked
		_fill_status_menu(_status_menu, picked)
		_refresh_list()


func _on_cell_selected() -> void:
	var it: TreeItem = _sheet.get_selected()
	if it == null or not (it.get_metadata(0) is String) or String(it.get_metadata(0)) == "":
		return
	var col: int = _sheet.get_selected_column()
	_sel_key = String(it.get_metadata(0))
	_sel_column = String(_cols[col]["column"]) if col >= 0 and col < _cols.size() else ""
	_tint_row("keys", _sheet, it, col)
	_show_dock()


func _on_build_pressed() -> void:
	if not _can_edit() or not _ready_model():
		return
	var start: int = _l.output.size()
	var errors: int = _l.cmd_build(L10n.MODE_DEV)
	_append_log(_l.output.slice(start))
	_model.set_issues(_l.issues.items)
	_model.index = SheetModel.read_index(_l.config.gen_dir.path_join("index.json"))
	EditorInterface.get_resource_filesystem().scan()
	_model.rebuild()
	_refresh_all()
	if errors == 0:
		_set_status(_tr("build_ok") % _l.issues.warn_count(), false)
	else:
		_set_status(_tr("build_fail") % errors, true)


## Add row: issues a key, shows it as a pending row at the end of the table (scrolled to the
## middle), then asks for the alias: pick a domain node in the tree, type the name.
func _on_add_row_pressed() -> void:
	if not _can_edit() or not _ready_model():
		return
	_l.reload()
	_pending_key = Keygen.generate(_l.config.key_prefix, _l.catalog.key_set())
	var root: TreeItem = _sheet.get_root()
	if root == null:
		return
	var it: TreeItem = _add_pending_item()
	_pad_sheet()
	_sheet.scroll_to_item(it, true)
	_ar_key.text = _pending_key
	_ar_alias.text = ""
	var pre: String = ""
	var sel: Dictionary = _model.row_of(_sel_key) if _sel_key != "" else {}
	if not sel.is_empty() and not _l.config.is_data_alias(String(sel["alias"])):
		var segs: PackedStringArray = String(sel["alias"]).split(".")
		pre = ".".join(segs.slice(0, segs.size() - 1))
	elif _selected_meta(_domain) != "":
		pre = _selected_meta(_domain)
	_fill_domain_tree(pre)
	_update_ar_preview()
	_add_row_dialog.popup_centered()
	_ar_alias.grab_focus()


## Alias prefixes as a tree: every domain file + every prefix of a (non-data) alias without its
## last segment. pre = the node to select (its parents unfolded); everything else folded.
func _fill_domain_tree(pre: String) -> void:
	_ar_domains.clear()
	var root: TreeItem = _ar_domains.create_item()
	var prefixes: Dictionary = {}
	for d in _model.domains():
		prefixes[String(d)] = true
	for r in _model.rows:
		var alias: String = String(r["alias"])
		if _l.config.is_data_alias(alias):
			continue
		var segs: PackedStringArray = alias.split(".")
		for n in range(1, segs.size()):
			prefixes[".".join(segs.slice(0, n))] = true
	var paths: Array = prefixes.keys()
	paths.sort()
	var items: Dictionary = {}
	for path in paths:
		var cut_at: int = String(path).rfind(".")
		var parent_path: String = String(path).left(cut_at) if cut_at >= 0 else ""
		var parent: TreeItem = items.get(parent_path, root)
		var it: TreeItem = _ar_domains.create_item(parent)
		it.set_text(0, String(path).substr(cut_at + 1))
		it.set_tooltip_text(0, path)
		it.set_metadata(0, path)
		it.collapsed = true
		items[path] = it
	var target: TreeItem = items.get(pre, null)
	if target != null:
		var p: TreeItem = target.get_parent()
		while p != null and p != root:
			p.collapsed = false
			p = p.get_parent()
		target.select(0)
		_ar_domains.scroll_to_item.call_deferred(target, true)


## The alias being built: picked domain node + "." + typed name.
func _ar_full_alias() -> String:
	var name_part: String = _ar_alias.text.strip_edges().trim_prefix(".")
	var it: TreeItem = _ar_domains.get_selected()
	var pre: String = String(it.get_metadata(0)) if it != null else ""
	if pre == "":
		return name_part
	return pre + ("." + name_part if name_part != "" else ".")


func _update_ar_preview() -> void:
	var it: TreeItem = _ar_domains.get_selected()
	_ar_preview.text = _tr("ar_preview") % _ar_full_alias() if it != null else _tr("ar_pick_domain")


func _on_add_row_confirmed() -> void:
	if not _can_edit() or not _ready_model() or _pending_key == "":
		return
	_l.reload()
	var alias: String = _ar_full_alias()
	var res: Dictionary = _l.cmd_new_key(alias.get_slice(".", 0), alias, "", "", _pending_key)
	if String(res["error"]) != "":
		_set_status(_tr("add_failed") % String(res["error"]), true)
		_add_row_dialog.popup_centered.call_deferred()
		_ar_alias.grab_focus.call_deferred()
		return
	_pending_key = ""
	_model.rebuild()
	_fill_options()
	_sel_key = String(res["key"])
	_sel_column = _l.config.source_locale
	_search.text = ""
	_refresh_list()
	if _find_item(_sel_key) == null:
		# Filters hide the new (empty) row: show everything.
		_select_by_meta(_domain, "")
		_sel_statuses = PackedStringArray(STATUS_CHOICES)
		_sel_filters = PackedStringArray()
		_fill_status_menu(_status_menu, _sel_statuses)
		_fill_filter_menu()
		_refresh_list()
	_set_status(_tr("added") % [alias, _sel_key], false)
	_source_edit.grab_focus.call_deferred()


func _on_add_row_canceled() -> void:
	_pending_key = ""
	_refresh_list()


## Remove row: confirm dialog with the key's usages (every line but its own source row) and the
## glossary terms linked to it; double-click a usage = go there (closes the dialog).
func _on_remove_row_pressed() -> void:
	if not _can_edit() or not _ready_model():
		return
	var r: Dictionary = _model.row_of(_sel_key) if _sel_key != "" else {}
	if r.is_empty():
		return
	_remove_key = _sel_key
	var body: PackedStringArray = PackedStringArray([_tr("remove_body") % [r["key"], r["alias"], String(r["file"]).get_file()], ""])
	_rr_usages.clear()
	for g in _model.glossary_terms():
		if String(g["key"]) == _remove_key:
			_rr_usages.add_item(_tr("remove_glossary") % [g["term_id"], int(g["line"])], null, false)
	var n: int = 0
	if _model.has_usage_data():
		for u in r["usages"]:
			var f: String = String(u.get("file", ""))
			var line: int = int(u.get("line", 0))
			if f == String(r["file"]) and line == int(r["line"]):
				continue
			var i: int = _rr_usages.add_item("%s:%d  (%s)" % [f.get_file(), line, String(u.get("kind", ""))], _file_icon(f))
			_rr_usages.set_item_tooltip(i, "%s:%d" % [f, line])
			_rr_usages.set_item_metadata(i, u)
			n += 1
		body.append(_tr("remove_used") % n if n > 0 else _tr("remove_unused"))
	else:
		body.append(_tr("remove_no_index"))
	_rr_body.text = "
".join(body)
	_rr_usages.visible = _rr_usages.item_count > 0
	_remove_row_dialog.popup_centered()


func _on_rr_usage_activated(index: int) -> void:
	var u: Variant = _rr_usages.get_item_metadata(index)
	if u is Dictionary:
		_remove_row_dialog.hide()
		_go_usage(u)


func _on_remove_row_confirmed() -> void:
	if not _can_edit() or not _ready_model() or _remove_key == "":
		return
	var key: String = _remove_key
	var alias: String = String(_model.row_of(key).get("alias", ""))
	_remove_key = ""
	var start: int = _l.output.size()
	var err: String = _l.cmd_remove_key(key)
	_append_log(_l.output.slice(start))
	if err != "":
		_set_status(_tr("remove_failed") % err, true)
		return
	_model.rebuild()
	_fill_options()
	if _sel_key == key:
		_sel_key = ""
	_refresh_all()
	_set_status(_tr("removed") % [key, alias], false)


## Scan + checks without writing the sources (the glossary filter's first use).
func _run_checks() -> void:
	if not _ready_model():
		return
	var start: int = _l.output.size()
	_l.cmd_validate(L10n.MODE_DEV)
	_append_log(_l.output.slice(start))
	_model.set_issues(_l.issues.items)
	_model.index = _l.index
	_model.rebuild()
	_refresh_all()
	_set_status(_tr("cmd_done") % ["validate", _l.issues.error_count(), _l.issues.warn_count()], _l.issues.error_count() > 0)


# ── approve (owner only) ────────────────────────────────────────────────

## The locale to approve: the selected cell's language, else the one shown language.
func _approve_target_locale() -> String:
	var shown: PackedStringArray = _shown_targets()
	if shown.has(_dock_column()):
		return _dock_column()
	return shown[0] if shown.size() == 1 else ""


## Rows whose translation in loc can be approved (has text, not approved-and-current).
func _approvable(rows: Array, loc: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for r in rows:
		var t: Dictionary = (r["tr"] as Dictionary).get(loc, {})
		if String(t.get("text", "")) != "" and (t.get("status", "") != SheetModel.ST_APPROVED or bool(t.get("stale", false))):
			out.append(String(r["key"]))
	return out


## Approve menu of the Keys or Glossary bar: selected = the dock's row, visible = the rows listed
## in the current table (glossary: the terms' linked keys).
func _on_approve_menu_id(id: int) -> void:
	if _mode != MODE_ADMIN or not _ready_model():
		return
	var loc: String = _approve_target_locale()
	if loc == "":
		_set_status(_tr("approve_need_locale"), true)
		return
	var rows: Array = []
	if id == APPROVE_SELECTED:
		var r: Dictionary = _model.row_of(_dock_row_key())
		if not r.is_empty():
			rows.append(r)
	else:
		rows = _visible_glossary_rows() if _tabs.current_tab == TAB_GLOSSARY else _current_rows()
	var keys: PackedStringArray = _approvable(rows, loc)
	if keys.is_empty():
		_set_status(_tr("approve_none"), true)
		return
	_approve_locale = loc
	_approve_keys = keys
	var aliases: PackedStringArray = PackedStringArray()
	for k in keys.slice(0, 10):
		aliases.append(String(_model.row_of(k).get("alias", k)))
	_approve_dialog.dialog_text = _tr("approve_body") % [loc, keys.size(), "\n".join(aliases) + ("\n…" if keys.size() > 10 else "")]
	_approve_dialog.popup_centered()


func _on_approve_confirmed() -> void:
	if _mode != MODE_ADMIN or not _ready_model() or _approve_keys.is_empty():
		return
	var start: int = _l.output.size()
	var err: String = _l.cmd_approve(_approve_locale, _approve_keys)
	_append_log(_l.output.slice(start))
	_model.rebuild()
	_refresh_list()
	_refresh_glossary()
	if err != "":
		_set_status(err, true)
	else:
		_set_status(_tr("approve_done") % [_approve_locale, _approve_keys.size()], false)
	_approve_keys = PackedStringArray()


## Rows currently listed in the sheet (search + filters).
func _current_rows() -> Array:
	var out: Array = []
	var root: TreeItem = _sheet.get_root()
	var it: TreeItem = root.get_first_child() if root != null else null
	while it != null:
		var r: Dictionary = _model.row_of(String(it.get_metadata(0))) if it.get_metadata(0) is String else {}
		if not r.is_empty():
			out.append(r)
		it = it.get_next()
	return out


## Linked-key rows of the terms listed in the glossary table (terms without a key skipped).
func _visible_glossary_rows() -> Array:
	var out: Array = []
	var root: TreeItem = _glossary_tree.get_root()
	var it: TreeItem = root.get_first_child() if root != null else null
	while it != null:
		var r: Dictionary = _model.row_of(String(_term(String(it.get_metadata(0))).get("key", "")))
		if not r.is_empty():
			out.append(r)
		it = it.get_next()
	return out


# ── glossary · orphans tabs ─────────────────────────────────────────────

func _term(term_id: String) -> Dictionary:
	if _model == null or term_id == "":
		return {}
	for g in _model.glossary_terms():
		if g["term_id"] == term_id:
			return g
	return {}


## Text of a glossary cell for term g: languages read through the linked key (sheet_model).
func _gl_value(g: Dictionary, col: int) -> String:
	var column: String = _gcols[col]["column"]
	match column:
		"term_id":
			return String(g["term_id"])
		"alias":
			return String(_model.row_of(String(g["key"])).get("alias", ""))
		"forbidden":
			var parts: PackedStringArray = PackedStringArray()
			for loc in g["forbidden"]:
				var fb: PackedStringArray = g["forbidden"][loc]
				if not fb.is_empty():
					parts.append("%s: %s" % [loc, " | ".join(fb)])
			return " / ".join(parts)
		"dnt":
			return "1" if g["dnt"] else ""
		"note":
			return String(g["note"])
	return String((g["texts"] as Dictionary).get(column, ""))


func _refresh_glossary() -> void:
	_glossary_tree.clear()
	_tinted.erase("glossary")
	if _model == null or _l == null or not _l.ok():
		return
	_setup_columns(_glossary_tree, _gcols, "glossary")
	var filters: Dictionary = {"locales": _shown_targets()}
	var sts: Variant = _status_filter(_gl_statuses)
	if sts != null:
		filters["statuses"] = sts
	var res: Array = _model.search_glossary(_gl_search.text, filters)
	_sort_rows(res, "glossary", _gcols, _gl_value)
	var root: TreeItem = _glossary_tree.create_item()
	var sel_item: TreeItem = null
	for g in res:
		var it: TreeItem = _glossary_tree.create_item(root)
		_fill_gl_item(it, g)
		if g["term_id"] == _gl_term:
			sel_item = it
	_gl_count.text = "%d / %d" % [res.size(), _model.glossary_terms().size()]
	var sel_col: int = _col_in(_gcols, _gl_column)
	if sel_item != null and sel_col >= 0:
		sel_item.select(sel_col)
		_tint_row("glossary", _glossary_tree, sel_item, sel_col)
		_glossary_tree.scroll_to_item(sel_item)
	else:
		_gl_term = ""
		_gl_column = ""
	_fill_glossary_keys()
	_show_dock()


func _fill_gl_item(it: TreeItem, g: Dictionary) -> void:
	var r: Dictionary = _model.row_of(String(g["key"]))
	it.set_metadata(0, g["term_id"])
	for c in _gcols.size():
		var value: String = _gl_value(g, c)
		var column: String = _gcols[c]["column"]
		it.set_text(c, value.replace("\n", " ⏎ "))
		var tip: String = value
		if _gcols[c]["kind"] == KIND_TEXT and column != _l.config.source_locale and not r.is_empty():
			var st: String = _status_of((r["tr"] as Dictionary).get(column, {}))
			it.set_icon(c, _dot(st))
			tip = "[%s]\n%s" % [_tr(st), value]
		it.set_tooltip_text(c, tip)
	it.set_tooltip_text(0, "glossary.csv:%d%s" % [int(g["line"]), (" · key " + String(g["key"])) if g["key"] != "" else ""])


func _on_glossary_selected() -> void:
	var it: TreeItem = _glossary_tree.get_selected()
	if it == null or _model == null:
		return
	var col: int = _glossary_tree.get_selected_column()
	_gl_term = String(it.get_metadata(0))
	_gl_column = String(_gcols[col]["column"]) if col >= 0 and col < _gcols.size() else ""
	_tint_row("glossary", _glossary_tree, it, col)
	_fill_glossary_keys()
	_show_dock()


## Dock table (Glossary tab, above the usages): keys whose source contains the selected term.
func _fill_glossary_keys() -> void:
	_glossary_keys.clear()
	var shown: bool = _tabs.current_tab == TAB_GLOSSARY and _model != null and _gl_term != ""
	_gl_keys_title.visible = shown
	_gl_keys_margin.visible = shown
	if not shown:
		return
	_glossary_keys.set_column_title(0, _tr("col_key"))
	_glossary_keys.set_column_title(1, _tr("col_source"))
	_glossary_keys.set_column_expand(0, false)
	_glossary_keys.set_column_custom_minimum_width(0, 320)
	var root: TreeItem = _glossary_keys.create_item()
	var keys: Array = _model.keys_with_term(_gl_term)
	_gl_keys_title.text = _tr("glossary_keys") % keys.size()
	if keys.is_empty():
		var none: TreeItem = _glossary_keys.create_item(root)
		none.set_text(0, _tr("glossary_no_keys"))
		none.set_selectable(0, false)
		none.set_selectable(1, false)
	for k in keys:
		var r: Dictionary = _model.row_of(k)
		var it: TreeItem = _glossary_keys.create_item(root)
		it.set_text(0, String(r["alias"]))
		it.set_tooltip_text(0, "%s
%s" % [k, r["alias"]])
		it.set_text(1, String(r["source"]).replace("
", " ⏎ "))
		it.set_tooltip_text(1, String(r["source"]))
		it.set_metadata(0, k)
	_fit_dock_tree(_glossary_keys)


## Glossary key double-click → that key in the Keys tab.
func _on_glossary_key_activated() -> void:
	var it: TreeItem = _glossary_keys.get_selected()
	var k: Variant = it.get_metadata(0) if it != null else null
	if k is String:
		_focus_key(k)


func _focus_key(key: String) -> void:
	_sel_key = key
	if _sel_column == "" or _col_index(_sel_column) < 0:
		_sel_column = _l.config.source_locale
	_tabs.current_tab = TAB_KEYS
	_search.text = key
	_refresh_list()


func _refresh_orphans() -> void:
	_orphan_list.clear()
	if _model == null:
		return
	var list: Array = _model.orphans()
	if list.is_empty():
		_orphan_list.add_item(_tr("no_orphans") if _model.has_usage_data() else _tr("no_index"), null, false)
		return
	for o in list:
		var f: String = String(o.get("file", ""))
		var i: int = _orphan_list.add_item("%s:%d  —  %s" % [f.get_file(), int(o.get("line", 0)), String(o.get("text", ""))], _file_icon(f))
		_orphan_list.set_item_tooltip(i, "%s:%d" % [f, int(o.get("line", 0))])
		_orphan_list.set_item_metadata(i, o)


func _on_orphan_activated(index: int) -> void:
	var o: Variant = _orphan_list.get_item_metadata(index)
	if o is Dictionary:
		_go_usage(o)


# ── scene preview tab ───────────────────────────────────────────────────

func _is_preview_shown() -> bool:
	return _tabs.get_current_tab_control() == _preview_page and is_visible_in_tree()


## Keys / Glossary share the bottom dock: it moves under the shown table.
func _on_tab_changed(tab: int) -> void:
	if tab == TAB_KEYS or tab == TAB_GLOSSARY:
		var host: Control = %KeysSplit if tab == TAB_KEYS else %GlSplit
		if _dock.get_parent() != host:
			_dock.reparent(host, false)
		_fill_glossary_keys()
		_show_dock(true)
	if _preview_dirty and _is_preview_shown():
		_refresh_preview()


## The edited scene's key texts in the chosen locale — nodes are only read, never written.
func _refresh_preview() -> void:
	_preview_tree.clear()
	_preview_dirty = false
	if _model == null or _l == null or not _l.ok():
		return
	if _preview_locale.item_count == 0:
		for loc in _l.config.locales:
			_preview_locale.add_item(loc)
			_preview_locale.set_item_metadata(_preview_locale.item_count - 1, loc)
		_select_by_meta(_preview_locale, _l.config.fallback_locale)
	var scene: Node = EditorInterface.get_edited_scene_root()
	if scene == null:
		_preview_info.text = _tr("preview_no_scene")
		return
	var loc: String = _selected_meta(_preview_locale)
	var rows: Array = SheetModel.scene_rows(scene, _l.config.scan_list("scene_text_props"), _l.catalog, loc, _l.config.key_prefix)
	_preview_info.text = _tr("preview_info") % [scene.scene_file_path.get_file() if scene.scene_file_path != "" else String(scene.name), rows.size()]
	_preview_tree.columns = 5
	var titles: Array = [_tr("col_node"), _tr("col_prop"), "key", "alias", loc]
	for c in titles.size():
		_preview_tree.set_column_title(c, titles[c])
	var root: TreeItem = _preview_tree.create_item()
	for r in rows:
		var it: TreeItem = _preview_tree.create_item(root)
		it.set_text(0, r["path"])
		it.set_text(1, r["prop"])
		it.set_text(2, r["key"])
		it.set_text(3, r["alias"])
		var shown: String = String(r["text"]).replace("\n", " ")
		if not r["known"]:
			shown = _tr("preview_unknown")
		elif r["missing"]:
			shown = _tr("preview_missing")
		it.set_text(4, shown)
		it.set_tooltip_text(4, r["text"])
		if not r["known"] or r["missing"]:
			it.set_custom_color(4, get_theme_color(&"warning_color", &"Editor"))
		it.set_metadata(0, r["path"])


func _on_preview_selected() -> void:
	var it: TreeItem = _preview_tree.get_selected()
	var scene: Node = EditorInterface.get_edited_scene_root()
	if it == null or scene == null:
		return
	var n: Node = scene.get_node_or_null(NodePath(String(it.get_metadata(0))))
	if n == null:
		_preview_dirty = true
		return
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(n)
	EditorInterface.edit_node(n)


# ── log tab ─────────────────────────────────────────────────────────────

func _append_log(lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	var all_lines: PackedStringArray = _log_text.text.split("\n", false)
	all_lines.append_array(lines)
	if all_lines.size() > LOG_MAX_LINES:
		all_lines = all_lines.slice(all_lines.size() - LOG_MAX_LINES)
	_log_text.text = "\n".join(all_lines)
	_log_text.scroll_vertical = _log_text.get_line_count()


# ── helpers ─────────────────────────────────────────────────────────────

static func _selected_meta(ob: OptionButton) -> String:
	if ob.item_count == 0 or ob.selected < 0:
		return ""
	var m: Variant = ob.get_item_metadata(ob.selected)
	return String(m) if m != null else ob.get_item_text(ob.selected)


static func _select_by_meta(ob: OptionButton, value: String) -> void:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == value:
			ob.select(i)
			return
	if ob.item_count > 0:
		ob.select(0)
