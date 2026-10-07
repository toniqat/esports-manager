@tool
extends VBoxContainer

# L10n editor — the "L10n" main screen tab (next to 2D · 3D · Script), the tool's only UI.
# Tabs: Keys (the sheet: one row per key — alias · source text · one column per target language
# with a status dot, plus context · max_len · note when languages are picked), Glossary, Orphan
# texts, Scene preview (the edited scene's key texts in a locale — read-only, row click selects the
# node) and Log (output of every command). Layout lives in l10n_sheet.tscn; UI text follows the
# editor language (ko, else en — `TEXTS`); search · filters · rows · glossary · preview rows come
# from sheet_model.gd; every write goes through the facade (`cmd_edit` · `cmd_new_key` ·
# `cmd_approve`, re-read from disk → write → save). build dev stays a separate button.
# Usages (generated/index.json, refreshed by the scan button) show in the bottom list and the
# row's right-click menu: .gd → script line, .tscn → open scene, .tres → resource, anything else
# (data CSVs) and the key's own source CSV row → external editor at that line.
# Inactive until plugin.gd calls `setup(plugin)`.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const SheetModel = preload("res://addons/l10n_tool/sheet/sheet_model.gd")
const ScreenMap = preload("res://addons/l10n_tool/sheet/screen_map.gd")
## Usage tooltip code preview: lines per file, characters per line.
const PREVIEW_LINES := 4
const PREVIEW_COLS := 110

const KIND_ALIAS := "alias"
const KIND_TEXT := "text"
const KIND_META := "meta"
## Status filter values (SheetModel.ST_*; "" = any).
const STATUS_CHOICES := ["", SheetModel.ST_NONE, SheetModel.ST_DRAFT, SheetModel.ST_APPROVED]
## Dot colours — not started · draft · approved · stale (source changed after translating).
const STATUS_COLORS := {
	SheetModel.ST_NONE: Color(0.93, 0.32, 0.32),
	SheetModel.ST_DRAFT: Color(0.96, 0.82, 0.26),
	SheetModel.ST_APPROVED: Color(0.36, 0.82, 0.42),
	"stale": Color(1.0, 0.56, 0.16),
}
const MENU_ALL_ID := 0
## Editor icons per button, first one the editor theme has wins.
const BUTTON_ICONS := {"AddRow": ["Add"], "Reload": ["Reload"], "Scan": ["Search"], "Validate": ["ImportCheck", "StatusSuccess"],
	"Sync": ["Loop", "RotateRight"], "BuildDev": ["Tools", "Play"], "PreviewRefresh": ["Reload"]}
## Approve menu ids.
enum { APPROVE_SELECTED, APPROVE_VISIBLE }
## Tab order in the scene and their TEXTS ids.
const TAB_TEXTS := ["tab_keys", "tab_glossary", "tab_orphans", "tab_preview", "tab_log"]
const LOG_MAX_LINES := 500
## Row menu ids; usages follow from MENU_USAGE_BASE.
enum { MENU_COPY_KEY, MENU_COPY_ALIAS, MENU_OPEN_SOURCE, MENU_COPY_SOURCE }
const MENU_USAGE_BASE := 100
const USAGE_SOURCE := "source"
## Environment the external editor must not inherit (see _open_external).
const CHILD_ENV_STRIP := ["ELECTRON_RUN_AS_NODE"]
## UI text per editor language.
const TEXTS := {
	"ko": {
		"search_ph": "검색 — key · alias · 원문 · 번역",
		"all_domains": "전체 도메인",
		"all_langs": "모든 언어",
		"langs": "언어: %s",
		"langs_tip": "볼 언어 — 고르면 그 언어 열과 context · max_len · note 를 보여 주고, 상태 필터도 그 언어 기준",
		"all_status": "모든 상태",
		SheetModel.ST_NONE: "미착수",
		SheetModel.ST_DRAFT: "작성 필요",
		SheetModel.ST_APPROVED: "완료",
		"stale": "원문 변경됨",
		"stale_only": "변경된 항목만 표시",
		"stale_tip": "원문이 바뀐 뒤 아직 고치지 않은 번역만",
		"add_tip": "행 추가 — key 발급 → <domain>.csv 끝에 행 추가",
		"reload_tip": "다시 읽기 — 원본 CSV",
		"build_tip": "build dev — sync → 검증 → 생성물(generated/). 저장한 내용을 게임에 반영",
		"apply": "적용 (Ctrl+Enter)",
		"revert": "되돌리기",
		"pick_cell": "셀을 고르세요 — 더블클릭으로 바로 편집, 긴 문장은 여기서",
		"not_editable": "(이 칸은 편집하지 않는다)",
		"source": "%s (원문)",
		"add_title": "행 추가 (new_key)",
		"add_ok": "추가",
		"text_label": "원문",
		"alias_ph": "ui.button.confirm (첫 세그먼트 = domain)",
		"context_ph": "어디에 쓰는 문구인지 (번역가용)",
		"saved": "%s · %s 저장 — build dev 로 게임에 반영",
		"save_failed": "저장 실패: %s",
		"cfg_failed": "config.json 을 읽지 못했다 — data/l10n/config.json 확인",
		"load_errors": "원본 읽기 오류 %d개 — validate 후 로그 탭 확인",
		"build_ok": "build dev 완료 — Warn %d (generated/report.md)",
		"build_fail": "build dev 실패 — Error %d, 생성물을 쓰지 않았다 (generated/report.md)",
		"add_failed": "행 추가 실패: %s",
		"added": "행 추가: %s = %s — 번역 칸을 채우세요",
		"over_len": "max_len %d 초과: %d자",
		"scan_tip": "사용처 다시 찾기 — scan → generated/index.json",
		"scan_done": "scan 완료 — key %d개, 고아 텍스트 %d개",
		"usages": "사용처 — 더블클릭으로 이동",
		"usages_of": "사용처 %d곳 — 더블클릭으로 이동",
		"source_item": "원본: %s",
		"no_usage_data": "사용처 정보 없음 — 돋보기(scan) 버튼",
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
		"validate_tip": "validate — 원본 · 사용처 검증 + generated/report.md (결과는 로그 탭)",
		"sync_tip": "sync — 해시가 빈 번역에 현재 원문 해시 · draft 기록",
		"unused_only": "미사용만",
		"unused_tip": "active 인데 코드 · 씬 어디에서도 안 쓰는 key (scan 필요)",
		"glossary_only": "용어집 위반만",
		"glossary_tip": "용어집 규칙(W071 · W072)에 걸린 key — 처음 켜면 validate 를 돌린다",
		"approve": "승인…",
		"approve_tip": "번역을 approved 로 — 오너 전용 (확인 창이 뜬다)",
		"approve_selected": "선택한 칸 승인",
		"approve_visible": "보이는 행 모두 승인",
		"approve_title": "approve — 오너 전용",
		"approve_ok": "approve",
		"approve_body": "approve 는 오너 전용이다 (LLM · 일반 작업자는 draft 까지).\n\n%s 번역 %d개를 approved 로 바꾸고 해시를 갱신한다:\n%s",
		"approve_need_locale": "승인할 언어를 정하세요 — 번역 칸을 고르거나 언어 메뉴에서 하나만 고른다",
		"approve_none": "승인할 번역이 없다 (비었거나 이미 approved)",
		"approve_done": "approve %s: %d개",
		"cmd_done": "%s: Error %d · Warn %d — 자세한 내용은 로그 탭",
		"sync_done": "sync: %d개 번역에 해시 · draft 기록",
		"no_usage_hint": "사용처 정보 없음 — 돋보기(scan) 버튼",
		"issues": "검증:",
		"terms": "용어: %s",
		"forbidden": "금지",
		"glossary_keys_tip": "원문에 이 용어가 들어간 key — 더블클릭하면 키 탭에서 연다",
		"glossary_no_keys": "이 용어가 들어간 key 없음",
		"orphan_title": "key 가 아닌 표시 텍스트 (scan 결과) — 더블클릭으로 이동",
		"no_orphans": "고아 텍스트 없음",
		"no_index": "사용처 정보 없음 — 돋보기(scan) 버튼",
		"preview_refresh": "새로 고침",
		"preview_note": "편집 중인 씬의 key 를 고른 언어 번역문으로 보여 준다 — 씬은 수정하지 않는다. 행 클릭 = 노드 선택",
		"preview_no_scene": "열린 씬 없음",
		"preview_info": "%s — key %d개",
		"preview_missing": "(번역 없음)",
		"preview_unknown": "(없는 key)",
		"col_node": "노드",
		"col_prop": "속성",
		"open_title": "파일을 열 수 없음",
		"open_missing": "파일이 없다:\n%s\n\n사용처 정보가 오래됐을 수 있다 — 돋보기(scan) 버튼으로 다시 찾기.",
		"open_no_editor": "연결된 외부 편집기가 없다:\n%s\n\nEditor Settings → Text Editor → External → Exec Path 에 VS Code 등을 지정하면 그 줄로 바로 열린다.",
		"open_launch_failed": "외부 편집기를 실행하지 못했다:\n%s\n\n파일: %s\nEditor Settings → Text Editor → External → Exec Path 를 확인.",
		"copy_path": "경로 복사",
		"open_default": "기본 프로그램으로 열기",
	},
	"en": {
		"search_ph": "Search — key · alias · source · translation",
		"all_domains": "All domains",
		"all_langs": "All languages",
		"langs": "Languages: %s",
		"langs_tip": "Languages to show — picking some shows their columns plus context · max_len · note, and scopes the status filter",
		"all_status": "All statuses",
		SheetModel.ST_NONE: "Not started",
		SheetModel.ST_DRAFT: "Draft",
		SheetModel.ST_APPROVED: "Approved",
		"stale": "Source changed",
		"stale_only": "Show changed only",
		"stale_tip": "Only translations not updated since the source text changed",
		"add_tip": "Add row — issue a key, append to <domain>.csv",
		"reload_tip": "Reload the source CSVs",
		"build_tip": "build dev — sync → validate → generated/. Applies saved edits to the game",
		"apply": "Apply (Ctrl+Enter)",
		"revert": "Revert",
		"pick_cell": "Pick a cell — double-click to edit in place, long text here",
		"not_editable": "(not editable)",
		"source": "%s (source)",
		"add_title": "Add row (new_key)",
		"add_ok": "Add",
		"text_label": "Source",
		"alias_ph": "ui.button.confirm (first segment = domain)",
		"context_ph": "Where the text is used (for translators)",
		"saved": "%s · %s saved — run build dev to apply in game",
		"save_failed": "Save failed: %s",
		"cfg_failed": "Could not read config.json — check data/l10n/config.json",
		"load_errors": "%d source read errors — run validate (Log tab)",
		"build_ok": "build dev done — %d warnings (generated/report.md)",
		"build_fail": "build dev failed — %d errors, nothing generated (generated/report.md)",
		"add_failed": "Add row failed: %s",
		"added": "Row added: %s = %s — fill in the translations",
		"over_len": "over max_len %d: %d chars",
		"scan_tip": "Find usages again — scan → generated/index.json",
		"scan_done": "scan done — %d keys, %d orphan texts",
		"usages": "Usages — double-click to open",
		"usages_of": "%d usages — double-click to open",
		"source_item": "Source: %s",
		"no_usage_data": "No usage data — press the search (scan) button",
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
		"validate_tip": "validate — check sources · usages + generated/report.md (results in the Log tab)",
		"sync_tip": "sync — stamp the current source hash · draft on translations with no hash",
		"unused_only": "Unused only",
		"unused_tip": "Active keys used nowhere in code or scenes (needs scan)",
		"glossary_only": "Glossary violations",
		"glossary_tip": "Keys breaking glossary rules (W071 · W072) — runs validate the first time",
		"approve": "Approve…",
		"approve_tip": "Mark translations approved — owner only (asks to confirm)",
		"approve_selected": "Approve selected cell",
		"approve_visible": "Approve all visible rows",
		"approve_title": "approve — owner only",
		"approve_ok": "approve",
		"approve_body": "approve is for the owner only (LLMs · other workers stop at draft).\n\nMarks %s translations of %d keys approved and refreshes their hash:\n%s",
		"approve_need_locale": "Pick the language to approve — select a translation cell, or pick one language in the menu",
		"approve_none": "Nothing to approve (empty or already approved)",
		"approve_done": "approve %s: %d",
		"cmd_done": "%s: %d errors · %d warnings — see the Log tab",
		"sync_done": "sync: hash · draft stamped on %d translations",
		"no_usage_hint": "No usage data — press the search (scan) button",
		"issues": "Checks:",
		"terms": "Terms: %s",
		"forbidden": "Forbidden",
		"glossary_keys_tip": "Keys whose source contains this term — double-click to open in Keys",
		"glossary_no_keys": "No key uses this term",
		"orphan_title": "Display text that is not a key (scan result) — double-click to open",
		"no_orphans": "No orphan texts",
		"no_index": "No usage data — press the search (scan) button",
		"preview_refresh": "Refresh",
		"preview_note": "Shows the edited scene's keys in the chosen language — the scene is never modified. Click a row to select the node",
		"preview_no_scene": "No scene open",
		"preview_info": "%s — %d keys",
		"preview_missing": "(no translation)",
		"preview_unknown": "(unknown key)",
		"col_node": "Node",
		"col_prop": "Property",
		"open_title": "Cannot open file",
		"open_missing": "File not found:\n%s\n\nUsage data may be out of date — press the search (scan) button.",
		"open_no_editor": "No external editor is set:\n%s\n\nSet Editor Settings → Text Editor → External → Exec Path (e.g. VS Code) to open files at the line.",
		"open_launch_failed": "Could not launch the external editor:\n%s\n\nFile: %s\nCheck Editor Settings → Text Editor → External → Exec Path.",
		"copy_path": "Copy path",
		"open_default": "Open with default app",
	},
}

@onready var _search: LineEdit = %Search
@onready var _domain: OptionButton = %Domain
@onready var _locale_menu: MenuButton = %LocaleMenu
@onready var _status_filter: OptionButton = %StatusFilter
@onready var _stale_only: CheckBox = %StaleOnly
@onready var _count: Label = %Count
@onready var _sheet: Tree = %Sheet
@onready var _cell_info: Label = %CellInfo
@onready var _apply: Button = %Apply
@onready var _revert: Button = %Revert
@onready var _cell_edit: TextEdit = %CellEdit
@onready var _status: Label = %Status
@onready var _add_row_dialog: ConfirmationDialog = %AddRowDialog
@onready var _ar_domain: LineEdit = %ArDomain
@onready var _ar_alias: LineEdit = %ArAlias
@onready var _ar_text: LineEdit = %ArText
@onready var _ar_context: LineEdit = %ArContext
@onready var _usage_title: Label = %UsageTitle
@onready var _usage_list: ItemList = %UsageList
@onready var _row_menu: PopupMenu = %RowMenu
@onready var _open_dialog: AcceptDialog = %OpenDialog
@onready var _hint: Label = %Hint
@onready var _tabs: TabContainer = %Tabs
@onready var _unused_only: CheckBox = %UnusedOnly
@onready var _glossary_only: CheckBox = %GlossaryOnly
@onready var _approve: MenuButton = %Approve
@onready var _approve_dialog: ConfirmationDialog = %ApproveDialog
@onready var _glossary_tree: Tree = %GlossaryTree
@onready var _glossary_keys: ItemList = %GlossaryKeys
@onready var _orphan_list: ItemList = %OrphanList
@onready var _preview_page: Control = %Preview
@onready var _preview_locale: OptionButton = %PreviewLocale
@onready var _preview_info: Label = %PreviewInfo
@onready var _preview_tree: Tree = %PreviewTree
@onready var _log_text: TextEdit = %LogText

var _plugin: EditorPlugin
var _l: L10n
var _model: SheetModel
## UI language — "ko" or "en" (editor language, read once).
var _lang: String = "en"
## Picked target languages in config order (never the source); empty = all languages (no meta columns).
var _sel_locales: PackedStringArray = PackedStringArray()
## Column layout: [{kind, column (csv column / locale), title}] — rebuilt on load / language pick.
var _cols: Array = []
## Selected cell by key + column name (column indices move when languages change).
var _sel_key: String = ""
var _sel_column: String = ""
var _dots: Dictionary = {}
## Key the row menu was opened on, and its usages (menu id - MENU_USAGE_BASE).
var _menu_key: String = ""
var _menu_usages: Array = []
## Usage → screen map (lazy, see _screens_of) and file line cache for previews.
var _screen_map: RefCounted = null
var _lines_cache: Dictionary = {}
## File the open popup is about, and its extra buttons (rebuilt per popup).
var _open_file: String = ""
var _open_dialog_buttons: Array = []
## Locale + keys the approve dialog will apply to.
var _approve_locale: String = ""
var _approve_keys: PackedStringArray = PackedStringArray()
## The scene preview needs redrawing (scene switched while the tab was hidden).
var _preview_dirty: bool = true


## plugin.gd calls this before adding the sheet to the main screen.
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	if _plugin == null:
		return
	_lang = _editor_lang()
	_apply_texts()
	%AddRow.pressed.connect(_on_add_row_pressed)
	%Reload.pressed.connect(_on_reload_pressed)
	%BuildDev.pressed.connect(_on_build_pressed)
	%Scan.pressed.connect(_on_scan_pressed)
	%Validate.pressed.connect(_on_validate_pressed)
	%Sync.pressed.connect(_on_sync_pressed)
	%PreviewRefresh.pressed.connect(_refresh_preview)
	_unused_only.toggled.connect(func(_on: bool) -> void: _refresh_list())
	_glossary_only.toggled.connect(_on_glossary_only_toggled)
	_approve.get_popup().id_pressed.connect(_on_approve_menu_id)
	_approve_dialog.confirmed.connect(_on_approve_confirmed)
	_glossary_tree.item_selected.connect(_on_glossary_selected)
	_glossary_keys.item_activated.connect(_on_glossary_key_activated)
	_orphan_list.item_activated.connect(_on_orphan_activated)
	_tabs.tab_changed.connect(_on_tab_changed)
	_preview_locale.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_preview_tree.item_selected.connect(_on_preview_selected)
	_usage_list.item_activated.connect(_on_usage_activated)
	_sheet.item_mouse_selected.connect(_on_sheet_mouse_selected)
	_row_menu.id_pressed.connect(_on_row_menu_id)
	_open_dialog.custom_action.connect(_on_open_dialog_action)
	_search.text_changed.connect(func(_s: String) -> void: _refresh_list())
	for ob in [_domain, _status_filter]:
		(ob as OptionButton).item_selected.connect(func(_i: int) -> void: _refresh_list())
	_stale_only.toggled.connect(func(_on: bool) -> void: _refresh_list())
	var pm: PopupMenu = _locale_menu.get_popup()
	pm.hide_on_checkable_item_selection = false
	pm.id_pressed.connect(_on_locale_menu_id)
	_sheet.select_mode = Tree.SELECT_SINGLE
	_sheet.cell_selected.connect(_on_cell_selected)
	_sheet.item_edited.connect(_on_item_edited)
	_apply.pressed.connect(_on_apply_pressed)
	_revert.pressed.connect(_show_cell)
	_cell_edit.gui_input.connect(_on_cell_edit_input)
	_add_row_dialog.confirmed.connect(_on_add_row_confirmed)
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


## Static UI text + button icons (texts that depend on data are set where they are drawn).
func _apply_texts() -> void:
	_search.placeholder_text = _tr("search_ph")
	_locale_menu.tooltip_text = _tr("langs_tip")
	_stale_only.text = _tr("stale_only")
	_stale_only.tooltip_text = _tr("stale_tip")
	%AddRow.tooltip_text = _tr("add_tip")
	%Reload.tooltip_text = _tr("reload_tip")
	%BuildDev.tooltip_text = _tr("build_tip")
	%Scan.tooltip_text = _tr("scan_tip")
	_apply.text = _tr("apply")
	_revert.text = _tr("revert")
	_add_row_dialog.title = _tr("add_title")
	_add_row_dialog.ok_button_text = _tr("add_ok")
	(%TextLabel as Label).text = _tr("text_label")
	_ar_alias.placeholder_text = _tr("alias_ph")
	_ar_context.placeholder_text = _tr("context_ph")
	for i in TAB_TEXTS.size():
		_tabs.set_tab_title(i, _tr(TAB_TEXTS[i]))
	%Validate.tooltip_text = _tr("validate_tip")
	%Sync.tooltip_text = _tr("sync_tip")
	_unused_only.text = _tr("unused_only")
	_unused_only.tooltip_text = _tr("unused_tip")
	_glossary_only.text = _tr("glossary_only")
	_glossary_only.tooltip_text = _tr("glossary_tip")
	_approve.text = _tr("approve")
	_approve.tooltip_text = _tr("approve_tip")
	var apm: PopupMenu = _approve.get_popup()
	apm.clear()
	apm.add_item(_tr("approve_selected"), APPROVE_SELECTED)
	apm.add_item(_tr("approve_visible"), APPROVE_VISIBLE)
	_approve_dialog.title = _tr("approve_title")
	_approve_dialog.ok_button_text = _tr("approve_ok")
	_glossary_keys.tooltip_text = _tr("glossary_keys_tip")
	(%OrphanTitle as Label).text = _tr("orphan_title")
	(%PreviewRefresh as Button).tooltip_text = _tr("preview_refresh")
	(%PreviewNote as Label).text = _tr("preview_note")
	if Engine.is_editor_hint():
		var ed_theme: Theme = EditorInterface.get_editor_theme()
		for node_name in BUTTON_ICONS:
			for icon_name in BUTTON_ICONS[node_name]:
				if ed_theme.has_icon(icon_name, &"EditorIcons"):
					(get_node("%" + node_name) as Button).icon = ed_theme.get_icon(icon_name, &"EditorIcons")
					break


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
	for loc in _l.config.target_locales():
		if _sel_locales.is_empty() or _sel_locales.has(loc):
			out.append(loc)
	return out


## Source column always; target languages per the language menu; meta columns only when
## languages are picked.
func _build_columns() -> void:
	_cols.clear()
	if _l == null or not _l.ok():
		return
	_cols.append({"kind": KIND_ALIAS, "column": "alias", "title": "alias"})
	_cols.append({"kind": KIND_TEXT, "column": _l.config.source_locale, "title": _tr("source") % _l.config.source_locale})
	for loc in _shown_targets():
		_cols.append({"kind": KIND_TEXT, "column": loc, "title": loc})
	if not _sel_locales.is_empty():
		for c in L10n.EDIT_META_COLS:
			_cols.append({"kind": KIND_META, "column": c, "title": c})


func _col_index(column: String) -> int:
	for i in _cols.size():
		if _cols[i]["column"] == column:
			return i
	return -1


## Writes one cell through the facade. On success redraws that row; on failure restores it.
func _write_cell(key: String, col: int, value: String) -> void:
	if not _ready_model() or not _is_editable(col):
		return
	var before: Dictionary = _model.row_of(key)
	if not before.is_empty() and _cell_value(before, col) == value:
		return
	var err: String = _l.cmd_edit([{"key": key, "column": String(_cols[col]["column"]), "value": value}])
	_model.rebuild()
	if err != "":
		_set_status(_tr("save_failed") % err, true)
	else:
		_set_status(_tr("saved") % [_model.row_of(key).get("alias", key), _cols[col]["title"]], false)
	var it: TreeItem = _find_item(key)
	if it != null:
		_fill_item(it, _model.row_of(key))
	if key == _sel_key and _cols[col]["column"] == _sel_column:
		_show_cell()


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

	var st: String = _selected_meta(_status_filter)
	_status_filter.clear()
	for s in STATUS_CHOICES:
		if s == "":
			_status_filter.add_item(_tr("all_status"))
		else:
			_status_filter.add_icon_item(_dot(s), _tr(s))
		_status_filter.set_item_metadata(_status_filter.item_count - 1, s)
	_select_by_meta(_status_filter, st)

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


func _refresh_list() -> void:
	_sheet.clear()
	if _model == null:
		return
	_sheet.columns = maxi(_cols.size(), 1)
	for c in _cols.size():
		var kind: String = _cols[c]["kind"]
		var is_max_len: bool = _cols[c]["column"] == "max_len"
		_sheet.set_column_title(c, _cols[c]["title"])
		_sheet.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)
		_sheet.set_column_clip_content(c, true)
		_sheet.set_column_expand(c, kind == KIND_TEXT or (kind == KIND_META and not is_max_len))
		_sheet.set_column_expand_ratio(c, 3 if kind == KIND_TEXT else 1)
		var min_w: int = 240
		if kind == KIND_TEXT:
			min_w = 200
		elif kind == KIND_META:
			min_w = 70 if is_max_len else 140
		_sheet.set_column_custom_minimum_width(c, min_w)
	var root: TreeItem = _sheet.create_item()
	var res: Array = _model.search(_search.text, {
		"domain": _selected_meta(_domain),
		"locales": _shown_targets() if _l != null and _l.ok() else PackedStringArray(),
		"status": _selected_meta(_status_filter),
		"stale": _stale_only.button_pressed,
		"unused": _unused_only.button_pressed,
		"glossary": _glossary_only.button_pressed,
	})
	var sel_item: TreeItem = null
	for r in res:
		var it: TreeItem = _sheet.create_item(root)
		_fill_item(it, r)
		if r["key"] == _sel_key:
			sel_item = it
	_count.text = "%d / %d" % [res.size(), _model.rows.size()]
	var sel_col: int = _col_index(_sel_column)
	if sel_item != null and sel_col >= 0:
		sel_item.select(sel_col)
		_sheet.scroll_to_item(sel_item)
	else:
		_sel_key = ""
		_sel_column = ""
	_show_cell()


func _fill_item(it: TreeItem, r: Dictionary) -> void:
	if r.is_empty():
		return
	it.set_metadata(0, r["key"])
	var max_len: int = String(r["max_len"]).to_int()
	for c in _cols.size():
		var kind: String = _cols[c]["kind"]
		var column: String = _cols[c]["column"]
		it.clear_custom_color(c)
		if kind == KIND_ALIAS:
			it.set_text(c, r["alias"])
			it.set_tooltip_text(c, "%s\n%s · %s\n%s:%d" % [r["key"], r["domain"], r["status"], r["file"], int(r["line"])])
			if r["status"] != "active":
				it.set_custom_color(c, Color(1, 1, 1, 0.45))
			continue
		var value: String = _cell_value(r, c)
		var tip: String = value
		it.set_text(c, value)
		it.set_editable(c, true)
		if kind == KIND_TEXT:
			it.set_edit_multiline(c, value.contains("\n"))
			if column != _l.config.source_locale:
				var st: String = _status_of((r["tr"] as Dictionary).get(column, {}))
				it.set_icon(c, _dot(st))
				tip = "[%s]\n%s" % [_tr(st), value]
			if max_len > 0 and value.length() > max_len:
				it.set_custom_color(c, get_theme_color(&"warning_color", &"Editor"))
				tip += "\n\n(%s)" % (_tr("over_len") % [max_len, value.length()])
		it.set_tooltip_text(c, tip)


## Text of an editable cell for row r ("" for the alias column).
func _cell_value(r: Dictionary, col: int) -> String:
	var kind: String = _cols[col]["kind"]
	var column: String = _cols[col]["column"]
	if kind == KIND_META:
		return String(r.get(column, ""))
	if kind != KIND_TEXT:
		return ""
	if column == _l.config.source_locale:
		return String(r["source"])
	return String(((r["tr"] as Dictionary).get(column, {}) as Dictionary).get("text", ""))


func _is_editable(col: int) -> bool:
	return col >= 0 and col < _cols.size() and _cols[col]["kind"] != KIND_ALIAS


## Loads the selected cell into the bottom editor (also = "되돌리기") and the row's usages.
func _show_cell() -> void:
	var r: Dictionary = _model.row_of(_sel_key) if _model != null and _sel_key != "" else {}
	_show_usages(r)
	var col: int = _col_index(_sel_column)
	var ok: bool = not r.is_empty() and _is_editable(col)
	_cell_edit.editable = ok
	_apply.disabled = not ok
	_revert.disabled = not ok
	if not ok:
		_cell_edit.text = ""
		_cell_info.text = _tr("pick_cell") if r.is_empty() else "%s\n%s" % [r["alias"], _tr("not_editable")]
		return
	_cell_edit.text = _cell_value(r, col)
	var lines: PackedStringArray = PackedStringArray([r["alias"], _cols[col]["title"]])
	if String(r["context"]) != "":
		lines.append("context: " + String(r["context"]))
	if String(r["max_len"]) != "":
		lines.append("max_len: " + String(r["max_len"]))
	if not (r["glossary"] as Array).is_empty():
		lines.append(_tr("terms") % ", ".join(PackedStringArray(r["glossary"])))
	var its: Array = _model.detail(_sel_key).get("issues", [])
	if not its.is_empty():
		lines.append(_tr("issues"))
		for it in its:
			lines.append("  %s %s" % [it["code"], it["msg"]])
	_cell_info.text = "\n".join(lines)


## Bottom usage list: the key's source CSV row first, then index.json usages.
func _show_usages(r: Dictionary) -> void:
	_usage_list.clear()
	_usage_title.text = _tr("usages")
	if r.is_empty():
		return
	var src: Dictionary = _source_usage(r)
	var i: int = _usage_list.add_item(_tr("source_item") % String(src["file"]).get_file(), _file_icon(src["file"]))
	_usage_list.set_item_tooltip(i, String(src["file"]))
	_usage_list.set_item_metadata(i, src)
	if not _model.has_usage_data():
		_usage_list.add_item(_tr("no_usage_data"), null, false)
		return
	var files: Array = _usage_files(r["usages"])
	_usage_title.text = _tr("usages_of") % files.size()
	if files.is_empty():
		_usage_list.add_item(_tr("no_usages"), null, false)
	for u in files:
		i = _usage_list.add_item(_usage_label(u), _file_icon(u["file"]))
		_usage_list.set_item_tooltip(i, _usage_tip(u, r))
		_usage_list.set_item_metadata(i, u)


static func _source_usage(r: Dictionary) -> Dictionary:
	return {"kind": USAGE_SOURCE, "file": String(r["file"]), "line": int(r["line"])}


## Usage list / menu label: "File.gd · BattleSim, MatchFlow" (screens from ScreenMap).
func _usage_label(u: Dictionary) -> String:
	var f: String = String(u["file"])
	var names: PackedStringArray = PackedStringArray()
	for h in _screens_of(f):
		names.append(String(h["screen"]))
	return f.get_file() if names.is_empty() else "%s  ·  %s" % [f.get_file(), ", ".join(names)]


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


## One usage per file (its first line) — the list shows file names, not lines.
static func _usage_files(usages: Array) -> Array:
	var seen: Dictionary = {}
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
	# CSVs sit under .gdignore (never imported) so the filesystem has no type for them:
	# l10n sources get the translation icon, data tables a grid icon.
	var names: Array = [EditorInterface.get_resource_filesystem().get_file_type(path)]
	if path.get_extension().to_lower() == "csv":
		var l10n_src: bool = _l != null and _l.ok() and path.begins_with(_l.config.src_dir)
		names = ["Translation", "TextFile"] if l10n_src else ["GridContainer", "Grid", "TextFile"]
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
		if String(it.get_metadata(0)) == key:
			return it
		it = it.get_next()
	return null


func _set_status(msg: String, is_error: bool) -> void:
	_status.text = msg
	_append_log(PackedStringArray([msg]))
	if is_error:
		_status.add_theme_color_override(&"font_color", get_theme_color(&"error_color", &"Editor"))
		push_warning("L10n: " + msg)
	else:
		_status.remove_theme_color_override(&"font_color")


# ── handlers ────────────────────────────────────────────────────────────

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_load()


func _on_reload_pressed() -> void:
	_screen_map = null
	_load()


func _on_scan_pressed() -> void:
	if not _ready_model():
		return
	_screen_map = null
	var start: int = _l.output.size()
	var idx: Dictionary = _l.cmd_scan()
	_append_log(_l.output.slice(start))
	_load()
	_set_status(_tr("scan_done") % [(idx.get("keys", {}) as Dictionary).size(), (idx.get("orphans", []) as Array).size()], false)


func _on_usage_activated(index: int) -> void:
	var u: Variant = _usage_list.get_item_metadata(index)
	if u is Dictionary:
		_go_usage(u)


## Right-click on a row → copy key / alias, open the source CSV row, jump to a usage.
func _on_sheet_mouse_selected(mouse_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var it: TreeItem = _sheet.get_selected()
	if it == null or _model == null:
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
	_menu_usages = _usage_files(r.get("usages", []) as Array)
	_row_menu.add_separator(_tr("usages_of") % _menu_usages.size() if _model.has_usage_data() else _tr("no_usage_data"))
	for i in _menu_usages.size():
		var f: String = String(_menu_usages[i]["file"])
		_row_menu.add_icon_item(_file_icon(f), _usage_label(_menu_usages[i]), MENU_USAGE_BASE + i)
		_row_menu.set_item_tooltip(_row_menu.get_item_index(MENU_USAGE_BASE + i), _usage_tip(_menu_usages[i], r))
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


func _on_cell_selected() -> void:
	var it: TreeItem = _sheet.get_selected()
	if it == null:
		return
	var col: int = _sheet.get_selected_column()
	_sel_key = String(it.get_metadata(0))
	_sel_column = String(_cols[col]["column"]) if col >= 0 and col < _cols.size() else ""
	_show_cell()


func _on_item_edited() -> void:
	var it: TreeItem = _sheet.get_edited()
	var col: int = _sheet.get_edited_column()
	if it == null or not _is_editable(col):
		return
	# Deferred — the tree is still inside its edit callback.
	_write_cell.call_deferred(String(it.get_metadata(0)), col, it.get_text(col))


func _on_apply_pressed() -> void:
	var col: int = _col_index(_sel_column)
	if _sel_key != "" and _is_editable(col):
		_write_cell(_sel_key, col, _cell_edit.text)


func _on_cell_edit_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and k.ctrl_pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		_cell_edit.accept_event()
		_on_apply_pressed()


func _on_build_pressed() -> void:
	if not _ready_model():
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


func _on_add_row_pressed() -> void:
	var dom: String = _selected_meta(_domain)
	if dom != "":
		_ar_domain.text = dom
		if _ar_alias.text == "":
			_ar_alias.text = dom + "."
	_add_row_dialog.popup_centered()
	_ar_alias.grab_focus()
	_ar_alias.caret_column = _ar_alias.text.length()


func _on_add_row_confirmed() -> void:
	if not _ready_model():
		return
	_l.reload()
	var res: Dictionary = _l.cmd_new_key(_ar_domain.text.strip_edges(), _ar_alias.text.strip_edges(), _ar_text.text, _ar_context.text)
	if String(res["error"]) != "":
		_set_status(_tr("add_failed") % String(res["error"]), true)
		return
	_ar_alias.text = ""
	_ar_text.text = ""
	_ar_context.text = ""
	_model.rebuild()
	_fill_options()
	_search.text = ""
	_sel_key = String(res["key"])
	var targets: PackedStringArray = _shown_targets()
	_sel_column = targets[0] if not targets.is_empty() else _l.config.source_locale
	_refresh_list()
	_set_status(_tr("added") % [_model.row_of(_sel_key).get("alias", ""), _sel_key], false)


func _on_validate_pressed() -> void:
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


func _on_sync_pressed() -> void:
	if not _ready_model():
		return
	var start: int = _l.output.size()
	var n: int = _l.cmd_sync()
	_append_log(_l.output.slice(start))
	_model.rebuild()
	_refresh_list()
	_set_status(_tr("sync_done") % n, false)


## The glossary filter needs validate results — run it the first time the box is ticked.
func _on_glossary_only_toggled(on: bool) -> void:
	if on and _model != null and not _model.validated:
		_on_validate_pressed()
		return
	_refresh_list()


# ── approve (owner only) ────────────────────────────────────────────────

## The locale to approve: the selected cell's language, else the one picked language.
func _approve_target_locale() -> String:
	var col: int = _col_index(_sel_column)
	if col >= 0 and _cols[col]["kind"] == KIND_TEXT and _cols[col]["column"] != _l.config.source_locale:
		return String(_cols[col]["column"])
	var shown: PackedStringArray = _shown_targets()
	return shown[0] if shown.size() == 1 else ""


## Rows whose translation in loc can be approved (has text, not approved-and-current).
func _approvable(rows: Array, loc: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for r in rows:
		var t: Dictionary = (r["tr"] as Dictionary).get(loc, {})
		if String(t.get("text", "")) != "" and (t.get("status", "") != SheetModel.ST_APPROVED or bool(t.get("stale", false))):
			out.append(String(r["key"]))
	return out


func _on_approve_menu_id(id: int) -> void:
	if not _ready_model():
		return
	var loc: String = _approve_target_locale()
	if loc == "":
		_set_status(_tr("approve_need_locale"), true)
		return
	var rows: Array = []
	if id == APPROVE_SELECTED:
		if _sel_key != "":
			rows.append(_model.row_of(_sel_key))
	else:
		rows = _current_rows()
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
	if not _ready_model() or _approve_keys.is_empty():
		return
	var start: int = _l.output.size()
	var err: String = _l.cmd_approve(_approve_locale, _approve_keys)
	_append_log(_l.output.slice(start))
	_model.rebuild()
	_refresh_list()
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
		out.append(_model.row_of(String(it.get_metadata(0))))
		it = it.get_next()
	return out


# ── glossary · orphans tabs ─────────────────────────────────────────────

func _refresh_glossary() -> void:
	_glossary_tree.clear()
	_glossary_keys.clear()
	if _model == null or _l == null or not _l.ok():
		return
	var locs: PackedStringArray = _l.config.locales
	_glossary_tree.columns = 1 + locs.size() + 3
	_glossary_tree.set_column_title(0, "term_id")
	for i in locs.size():
		_glossary_tree.set_column_title(1 + i, locs[i])
	var c_forbid: int = 1 + locs.size()
	_glossary_tree.set_column_title(c_forbid, _tr("forbidden"))
	_glossary_tree.set_column_title(c_forbid + 1, "dnt")
	_glossary_tree.set_column_title(c_forbid + 2, "note")
	var root: TreeItem = _glossary_tree.create_item()
	for g in _model.glossary_terms():
		var it: TreeItem = _glossary_tree.create_item(root)
		it.set_text(0, g["term_id"])
		var forbid: PackedStringArray = PackedStringArray()
		for i in locs.size():
			it.set_text(1 + i, String((g["texts"] as Dictionary).get(locs[i], "")))
			var fb: PackedStringArray = (g["forbidden"] as Dictionary).get(locs[i], PackedStringArray())
			if not fb.is_empty():
				forbid.append("%s: %s" % [locs[i], " | ".join(fb)])
		it.set_text(c_forbid, " / ".join(forbid))
		it.set_text(c_forbid + 1, "1" if g["dnt"] else "")
		it.set_text(c_forbid + 2, g["note"])
		it.set_tooltip_text(0, "glossary.csv:%d%s" % [int(g["line"]), (" · key " + String(g["key"])) if g["key"] != "" else ""])
		it.set_metadata(0, g["term_id"])


func _on_glossary_selected() -> void:
	_glossary_keys.clear()
	var it: TreeItem = _glossary_tree.get_selected()
	if it == null or _model == null:
		return
	var keys: Array = _model.keys_with_term(String(it.get_metadata(0)))
	if keys.is_empty():
		_glossary_keys.add_item(_tr("glossary_no_keys"), null, false)
	for k in keys:
		var r: Dictionary = _model.row_of(k)
		var i: int = _glossary_keys.add_item("%s  —  %s" % [r["alias"], r["source"]])
		_glossary_keys.set_item_metadata(i, k)


## Glossary key double-click → that key in the Keys tab.
func _on_glossary_key_activated(index: int) -> void:
	var k: Variant = _glossary_keys.get_item_metadata(index)
	if k is String:
		_focus_key(k)


func _focus_key(key: String) -> void:
	_tabs.current_tab = 0
	_sel_key = key
	if _sel_column == "" or _col_index(_sel_column) < 0:
		_sel_column = _l.config.source_locale
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


func _on_tab_changed(_tab: int) -> void:
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
