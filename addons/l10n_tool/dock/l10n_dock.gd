@tool
extends VBoxContainer

# L10n 조회 도크 — 설계서 §11.1 · §11.2(D12). 레이아웃은 l10n_dock.tscn, 검색 · 필터 ·
# 상세 · 용어집 · 씬 미리보기 행은 dock_model.gd. 여기서는 노드에 그리고 명령만 부른다.
# plugin.gd 가 `setup(plugin)` 을 부른 뒤에만 동작한다(씬 편집 · 헤드리스 로드 시엔 빈 화면).
# 도크가 숨겨지면 카탈로그 · 행을 놓고, 다시 보이면 디스크에서 읽는다.
# 씬 미리보기는 노드 속성을 읽기만 한다 — 절대 쓰지 않는다(번역문 누수 방지, E057).

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const DockModel = preload("res://addons/l10n_tool/dock/dock_model.gd")

const COL_ALIAS := 0
const COL_SOURCE := 1
const COL_FIRST_LOCALE := 2
const PV_PATH := 0
const PV_PROP := 1
const PV_KEY := 2
const PV_ALIAS := 3
const PV_TEXT := 4
const LOG_MAX_LINES := 500
const STATUS_CHOICES := ["", DockModel.ST_NONE, DockModel.ST_DRAFT, DockModel.ST_APPROVED]

@onready var _hint: Label = %Hint
@onready var _tabs: TabContainer = %Tabs
@onready var _search: LineEdit = %Search
@onready var _domain: OptionButton = %Domain
@onready var _status_locale: OptionButton = %StatusLocale
@onready var _status_filter: OptionButton = %StatusFilter
@onready var _stale_only: CheckBox = %StaleOnly
@onready var _unused_only: CheckBox = %UnusedOnly
@onready var _glossary_only: CheckBox = %GlossaryOnly
@onready var _key_tree: Tree = %KeyTree
@onready var _count: Label = %Count
@onready var _detail_key: Label = %DetailKey
@onready var _copy_key: Button = %CopyKey
@onready var _detail_text: RichTextLabel = %DetailText
@onready var _usage_list: ItemList = %UsageList
@onready var _approve_locale: OptionButton = %ApproveLocale
@onready var _approve: Button = %Approve
@onready var _approve_dialog: ConfirmationDialog = %ApproveDialog
@onready var _glossary_tree: Tree = %GlossaryTree
@onready var _glossary_keys: ItemList = %GlossaryKeys
@onready var _orphan_list: ItemList = %OrphanList
@onready var _preview_page: Control = get_node("%씬 미리보기")
@onready var _preview_locale: OptionButton = %PreviewLocale
@onready var _preview_refresh: Button = %PreviewRefresh
@onready var _preview_info: Label = %PreviewInfo
@onready var _preview_tree: Tree = %PreviewTree
@onready var _log_view: TextEdit = %Log
@onready var _new_key_dialog: ConfirmationDialog = %NewKeyDialog
@onready var _nk_domain: LineEdit = %NkDomain
@onready var _nk_alias: LineEdit = %NkAlias
@onready var _nk_text: LineEdit = %NkText
@onready var _nk_context: LineEdit = %NkContext

var _plugin: EditorPlugin
var _l: L10n
var _model: DockModel
var _selected_key: String = ""
var _approve_keys: PackedStringArray = PackedStringArray()
var _preview_dirty: bool = true


## plugin.gd 가 도크에 붙이기 전에 부른다.
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	plugin.scene_changed.connect(_on_scene_changed)


func _ready() -> void:
	if _plugin == null:
		return
	_connect_ui()
	visibility_changed.connect(_on_visibility_changed)
	if is_visible_in_tree():
		_load()


func _connect_ui() -> void:
	%Reload.pressed.connect(_load)
	%NewKey.pressed.connect(_on_new_key_pressed)
	%Sync.pressed.connect(_run.bind("sync"))
	%Validate.pressed.connect(_run.bind("validate"))
	%BuildDev.pressed.connect(_run.bind("build"))
	%Scan.pressed.connect(_run.bind("scan"))
	_search.text_changed.connect(func(_s: String) -> void: _refresh_list())
	for ob in [_domain, _status_locale, _status_filter]:
		(ob as OptionButton).item_selected.connect(func(_i: int) -> void: _refresh_list())
	for cb in [_stale_only, _unused_only]:
		(cb as CheckBox).toggled.connect(func(_on: bool) -> void: _refresh_list())
	_glossary_only.toggled.connect(_on_glossary_only_toggled)
	_key_tree.multi_selected.connect(_on_key_multi_selected)
	_copy_key.pressed.connect(_on_copy_key_pressed)
	_usage_list.item_activated.connect(_on_usage_activated)
	_approve.pressed.connect(_on_approve_pressed)
	_approve_dialog.confirmed.connect(_on_approve_confirmed)
	_new_key_dialog.confirmed.connect(_on_new_key_confirmed)
	_glossary_tree.item_selected.connect(_on_glossary_selected)
	_glossary_keys.item_activated.connect(_on_glossary_key_activated)
	_orphan_list.item_activated.connect(_on_orphan_activated)
	_tabs.tab_changed.connect(_on_tab_changed)
	_preview_locale.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_preview_refresh.pressed.connect(_refresh_preview)
	_preview_tree.item_selected.connect(_on_preview_selected)


# ── 데이터 ──────────────────────────────────────────────────────────────

## config · 원본 · index.json 을 디스크에서 다시 읽는다(검증 결과는 이어 쓴다).
func _load() -> void:
	var old_issues: Array = _model.issue_items if _model != null and _model.validated else []
	_l = L10n.open()
	_l.echo = false
	_model = DockModel.new()
	if _l.ok():
		_model.setup(_l.config, _l.catalog, DockModel.read_index(_index_path()))
		if not old_issues.is_empty():
			_model.set_issues(old_issues)
	else:
		_model.setup(null, null, {})
		_append_log(_l.output)
	_preview_dirty = true
	_fill_options()
	_refresh_all()


## 숨겨질 때 — 무거운 상태를 놓는다.
func _release() -> void:
	_l = null
	_model = null
	_key_tree.clear()
	_glossary_tree.clear()
	_glossary_keys.clear()
	_orphan_list.clear()
	_preview_tree.clear()
	_usage_list.clear()
	_show_detail("")


func _index_path() -> String:
	return _l.config.gen_dir.path_join("index.json")


func _ready_model() -> bool:
	if _model == null:
		_load()
	return _l != null and _l.ok()


## 파사드 명령 실행 → 로그 · 행 갱신. build · scan 뒤에는 index 를 다시 읽고 파일시스템 스캔.
func _run(what: String) -> void:
	if not _ready_model():
		return
	var start: int = _l.output.size()
	match what:
		"sync":
			_l.cmd_sync()
		"validate":
			_l.cmd_validate(L10n.MODE_DEV)
		"build":
			_l.cmd_build(L10n.MODE_DEV)
		"scan":
			_l.cmd_scan()
	_append_log(_l.output.slice(start))
	if what == "validate" or what == "build":
		_model.set_issues(_l.issues.items)
	_after_command(what == "build" or what == "scan")


func _after_command(fs_scan: bool) -> void:
	var idx: Dictionary = _l.index if not _l.index.is_empty() else DockModel.read_index(_index_path())
	_model.index = idx
	_model.rebuild()
	if fs_scan:
		EditorInterface.get_resource_filesystem().scan()
	_fill_options()
	_refresh_all()


# ── 그리기 ──────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_update_hint()
	_refresh_list()
	_refresh_glossary()
	_refresh_orphans()
	if _is_preview_shown():
		_refresh_preview()


func _update_hint() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if _l == null or not _l.ok():
		parts.append("config.json 을 읽지 못했다 — data/l10n/config.json 확인")
	else:
		if _l.catalog.load_issues.error_count() > 0:
			parts.append("원본 읽기 오류 %d개 — validate 로그 확인" % _l.catalog.load_issues.error_count())
		if _model.rows.is_empty():
			parts.append("l10n 엔트리 0개 — new_key 로 추가")
		elif not _model.has_usage_data():
			parts.append("사용처 정보 없음 — scan 을 실행하세요")
	_hint.text = "  ·  ".join(parts)
	_hint.visible = not parts.is_empty()


## 로케일 · 도메인 선택지 — 선택은 유지한다.
func _fill_options() -> void:
	var dom: String = _selected_text(_domain)
	_domain.clear()
	_domain.add_item("전체 도메인")
	_domain.set_item_metadata(0, "")
	for d in _model.domains():
		_domain.add_item(d)
		_domain.set_item_metadata(_domain.item_count - 1, d)
	_select_by_meta(_domain, dom)

	var targets: PackedStringArray = _model.target_locales()
	_fill_locale_option(_status_locale, targets, "모든 로케일")
	_fill_locale_option(_approve_locale, targets, "")
	var all_locs: PackedStringArray = _l.config.locales if _l != null and _l.ok() else PackedStringArray()
	var pv: String = _selected_text(_preview_locale)
	_fill_locale_option(_preview_locale, all_locs, "")
	if pv == "" and _l != null and _l.ok():
		pv = _l.config.fallback_locale
	_select_by_meta(_preview_locale, pv)

	if _status_filter.item_count == 0:
		for s in STATUS_CHOICES:
			_status_filter.add_item("모든 상태" if s == "" else String(s))
			_status_filter.set_item_metadata(_status_filter.item_count - 1, s)


func _fill_locale_option(ob: OptionButton, locs: PackedStringArray, all_label: String) -> void:
	var keep: String = _selected_text(ob)
	ob.clear()
	if all_label != "":
		ob.add_item(all_label)
		ob.set_item_metadata(0, "")
	for loc in locs:
		ob.add_item(loc)
		ob.set_item_metadata(ob.item_count - 1, loc)
	_select_by_meta(ob, keep)


func _filters() -> Dictionary:
	return {
		"domain": _selected_text(_domain),
		"locale": _selected_text(_status_locale),
		"status": _selected_text(_status_filter),
		"stale": _stale_only.button_pressed,
		"unused": _unused_only.button_pressed,
		"glossary": _glossary_only.button_pressed,
	}


func _refresh_list() -> void:
	_key_tree.clear()
	if _model == null:
		return
	var locs: PackedStringArray = _model.target_locales()
	_key_tree.columns = COL_FIRST_LOCALE + locs.size()
	_key_tree.set_column_title(COL_ALIAS, "alias")
	_key_tree.set_column_title(COL_SOURCE, _l.config.source_locale if _l != null and _l.ok() else "원문")
	for i in locs.size():
		_key_tree.set_column_title(COL_FIRST_LOCALE + i, locs[i])
		_key_tree.set_column_expand(COL_FIRST_LOCALE + i, false)
		_key_tree.set_column_custom_minimum_width(COL_FIRST_LOCALE + i, 110)
	var root: TreeItem = _key_tree.create_item()
	var res: Array = _model.search(_search.text, _filters())
	var dim: Color = Color(1, 1, 1, 0.45)
	var found: bool = false
	for r in res:
		var it: TreeItem = _key_tree.create_item(root)
		it.set_text(COL_ALIAS, r["alias"])
		it.set_tooltip_text(COL_ALIAS, "%s\n%s" % [r["key"], r["alias"]])
		it.set_text(COL_SOURCE, String(r["source"]).replace("\n", " "))
		it.set_tooltip_text(COL_SOURCE, r["source"])
		for i in locs.size():
			var t: Dictionary = (r["tr"] as Dictionary).get(locs[i], {})
			it.set_text(COL_FIRST_LOCALE + i, DockModel.status_cell(t))
			it.set_tooltip_text(COL_FIRST_LOCALE + i, String(t.get("text", "")))
		if r["status"] != "active":
			for c in _key_tree.columns:
				it.set_custom_color(c, dim)
		it.set_metadata(0, r["key"])
		if r["key"] == _selected_key:
			it.select(0)
			found = true
	_count.text = "%d / %d" % [res.size(), _model.rows.size()]
	if not found:
		_show_detail("")


func _show_detail(key: String) -> void:
	_selected_key = key
	_usage_list.clear()
	var d: Dictionary = _model.detail(key) if _model != null and key != "" else {}
	_detail_key.text = key if not d.is_empty() else "(key 를 고르세요)"
	_copy_key.disabled = d.is_empty()
	_detail_text.text = _model.detail_text(d) if not d.is_empty() else ""
	if d.is_empty():
		return
	if not _model.has_usage_data():
		_usage_list.add_item("사용처 정보 없음 — scan 을 실행하세요", null, false)
		return
	if (d["usages"] as Array).is_empty():
		_usage_list.add_item("사용처 없음", null, false)
	for u in d["usages"]:
		var i: int = _usage_list.add_item(DockModel.usage_label(u))
		_usage_list.set_item_metadata(i, u)


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
	_glossary_tree.set_column_title(c_forbid, "금지")
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


func _refresh_orphans() -> void:
	_orphan_list.clear()
	if _model == null:
		return
	var list: Array = _model.orphans()
	if list.is_empty():
		_orphan_list.add_item("고아 텍스트 없음" if _model.has_usage_data() else "index 없음 — scan 을 실행하세요", null, false)
		return
	for o in list:
		var i: int = _orphan_list.add_item("%s  —  %s" % [DockModel.usage_label(o), String(o.get("text", ""))])
		_orphan_list.set_item_metadata(i, o)


func _is_preview_shown() -> bool:
	return _tabs.get_current_tab_control() == _preview_page and is_visible_in_tree()


## 씬 미리보기 — 편집 중인 씬의 key 를 선택 로케일 텍스트로 보여 준다. 노드는 읽기만.
func _refresh_preview() -> void:
	_preview_tree.clear()
	_preview_dirty = false
	if _model == null or _l == null or not _l.ok():
		return
	var scene: Node = EditorInterface.get_edited_scene_root()
	if scene == null:
		_preview_info.text = "열린 씬 없음"
		return
	var loc: String = _selected_text(_preview_locale)
	var rows: Array = DockModel.scene_rows(scene, _l.config.scan_list("scene_text_props"), _l.catalog, loc, _l.config.key_prefix)
	_preview_info.text = "%s — key %d개" % [scene.scene_file_path.get_file() if scene.scene_file_path != "" else String(scene.name), rows.size()]
	_preview_tree.columns = 5
	for pair in [[PV_PATH, "노드"], [PV_PROP, "속성"], [PV_KEY, "key"], [PV_ALIAS, "alias"], [PV_TEXT, loc]]:
		_preview_tree.set_column_title(pair[0], pair[1])
	var root: TreeItem = _preview_tree.create_item()
	for r in rows:
		var it: TreeItem = _preview_tree.create_item(root)
		it.set_text(PV_PATH, r["path"])
		it.set_text(PV_PROP, r["prop"])
		it.set_text(PV_KEY, r["key"])
		it.set_text(PV_ALIAS, r["alias"])
		var shown: String = String(r["text"]).replace("\n", " ")
		if not r["known"]:
			shown = "(없는 key)"
		elif r["missing"]:
			shown = "(번역 없음)"
		it.set_text(PV_TEXT, shown)
		it.set_tooltip_text(PV_TEXT, r["text"])
		if not r["known"] or r["missing"]:
			it.set_custom_color(PV_TEXT, get_theme_color(&"warning_color", &"Editor"))
		it.set_metadata(0, r["path"])


func _append_log(lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	var all_lines: PackedStringArray = _log_view.text.split("\n", false)
	all_lines.append_array(lines)
	if all_lines.size() > LOG_MAX_LINES:
		all_lines = all_lines.slice(all_lines.size() - LOG_MAX_LINES)
	_log_view.text = "\n".join(all_lines)
	_log_view.scroll_vertical = _log_view.get_line_count()


func _notify(msg: String) -> void:
	_append_log(PackedStringArray([msg]))


# ── 사용처 이동 ─────────────────────────────────────────────────────────

func _go_usage(u: Dictionary) -> void:
	var a: Dictionary = DockModel.usage_action(u)
	var path: String = a["path"]
	if a["kind"] != DockModel.KIND_COPY and not ResourceLoader.exists(path):
		a["kind"] = DockModel.KIND_COPY
	match a["kind"]:
		DockModel.KIND_SCRIPT:
			EditorInterface.edit_script(load(path), maxi(int(a["line"]), 1))
			EditorInterface.set_main_screen_editor("Script")
		DockModel.KIND_SCENE:
			EditorInterface.open_scene_from_path(path)
		DockModel.KIND_RESOURCE:
			EditorInterface.edit_resource(load(path))
		_:
			DisplayServer.clipboard_set(a["label"])
			_notify("복사함: " + String(a["label"]))


# ── 핸들러 ──────────────────────────────────────────────────────────────

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		if _model == null:
			_load()
		elif _preview_dirty and _is_preview_shown():
			_refresh_preview()
	else:
		_release()


func _on_scene_changed(_scene_root: Node) -> void:
	_preview_dirty = true
	if _model != null and _is_preview_shown():
		_refresh_preview()


func _on_tab_changed(_tab: int) -> void:
	if _preview_dirty and _is_preview_shown():
		_refresh_preview()


func _on_glossary_only_toggled(on: bool) -> void:
	if on and _model != null and not _model.validated and _ready_model():
		var start: int = _l.output.size()
		_l.cmd_validate(L10n.MODE_DEV, false)
		_append_log(_l.output.slice(start))
		_model.set_issues(_l.issues.items)
		_after_command(false)
		return
	_refresh_list()


func _on_key_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if selected:
		_show_detail(String(item.get_metadata(0)))


func _on_copy_key_pressed() -> void:
	if _selected_key != "":
		DisplayServer.clipboard_set(_selected_key)
		_notify("복사함: " + _selected_key)


func _on_usage_activated(index: int) -> void:
	var u: Variant = _usage_list.get_item_metadata(index)
	if u is Dictionary:
		_go_usage(u)


func _on_orphan_activated(index: int) -> void:
	var o: Variant = _orphan_list.get_item_metadata(index)
	if o is Dictionary:
		_go_usage(o)


func _on_glossary_selected() -> void:
	_glossary_keys.clear()
	var it: TreeItem = _glossary_tree.get_selected()
	if it == null or _model == null:
		return
	var keys: Array = _model.keys_with_term(String(it.get_metadata(0)))
	if keys.is_empty():
		_glossary_keys.add_item("이 용어가 들어간 key 없음", null, false)
	for k in keys:
		var r: Dictionary = _model.row_of(k)
		var i: int = _glossary_keys.add_item("%s  —  %s" % [r["alias"], r["source"]])
		_glossary_keys.set_item_metadata(i, k)


## 용어집 탭의 key 더블클릭 → 키 탭에서 그 key 를 보여 준다.
func _on_glossary_key_activated(index: int) -> void:
	var k: Variant = _glossary_keys.get_item_metadata(index)
	if k is String:
		_focus_key(k)


func _focus_key(key: String) -> void:
	_selected_key = key
	_search.text = key
	_tabs.current_tab = 0
	_refresh_list()
	_show_detail(key)


func _on_approve_pressed() -> void:
	_approve_keys = PackedStringArray()
	var it: TreeItem = _key_tree.get_next_selected(null)
	while it != null:
		_approve_keys.append(String(it.get_metadata(0)))
		it = _key_tree.get_next_selected(it)
	var loc: String = _selected_text(_approve_locale)
	if _approve_keys.is_empty() or loc == "":
		_notify("approve: 목록에서 key 와 로케일을 고르세요")
		return
	_approve_dialog.dialog_text = "approve 는 오너 전용이다(§0 규칙 5 — LLM · 일반 작업자는 draft 까지).\n\n%s 번역 %d개를 approved 로 바꾸고 해시를 갱신한다:\n%s" % [
		loc, _approve_keys.size(), "\n".join(_approve_keys.slice(0, 10)) + ("\n…" if _approve_keys.size() > 10 else "")]
	_approve_dialog.popup_centered()


func _on_approve_confirmed() -> void:
	if not _ready_model() or _approve_keys.is_empty():
		return
	var start: int = _l.output.size()
	_l.cmd_approve(_selected_text(_approve_locale), _approve_keys)
	_append_log(_l.output.slice(start))
	_approve_keys = PackedStringArray()
	_after_command(false)


func _on_new_key_pressed() -> void:
	var dom: String = _selected_text(_domain)
	if dom != "" and _nk_domain.text == "":
		_nk_domain.text = dom
	_new_key_dialog.popup_centered()
	_nk_alias.grab_focus()


func _on_new_key_confirmed() -> void:
	if not _ready_model():
		return
	var start: int = _l.output.size()
	var res: Dictionary = _l.cmd_new_key(_nk_domain.text.strip_edges(), _nk_alias.text.strip_edges(), _nk_text.text, _nk_context.text)
	_append_log(_l.output.slice(start))
	if String(res["error"]) != "":
		return
	_nk_alias.text = ""
	_nk_text.text = ""
	_nk_context.text = ""
	_after_command(false)
	_focus_key(String(res["key"]))


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


# ── 도우미 ──────────────────────────────────────────────────────────────

static func _selected_text(ob: OptionButton) -> String:
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
