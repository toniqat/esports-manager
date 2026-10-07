@tool
extends VBoxContainer

# "UI 트리" 독 — 진입 씬(`scenes/*.tscn`) · UI_View 씬 아래에 그 씬이 담는 UI 씬을 Scene 탭처럼 보여 준다.
#
#   열 0 이름 — 씬에 인스턴스된 것 (`×n` = 인스턴스 수) + 그 씬 스크립트가 코드로 만드는 것
#               (스크립트 아이콘 · "코드 생성"). 맨 아래 그룹은 어느 씬에도 · 어느 씬 스크립트에도
#               걸리지 않은 Comp (헬퍼 스크립트만 쓰거나 안 쓰는 씬)
#   열 1 TODO — 그 씬 안의 TODO 노드 수, `(+n)` 은 아래 씬들의 합 (같은 씬은 한 번만)
#   열 2 노드 — 그 씬 루트 아래 노드 수 (인스턴스 노드는 1개로). 툴팁 = 노드 경로 NODE_TOOLTIP_MAX 개 + "외 n개"
# 열에 마우스를 올리면 노드 목록. 더블클릭 = 씬 열기 + Scene 탭, 우클릭 = 접기 · 펼치기 · FileSystem 에서 보기.
# 글자는 에디터 언어가 한국어면 한국어, 아니면 영어 (`_STRINGS`).

const Scanner = preload("res://addons/ui_scene_tree/ui_scene_scanner.gd")

const COL_NAME: int = 0
const COL_TODO: int = 1
const COL_NODES: int = 2
const COUNT_COL_WIDTH: int = 72
const TOOLTIP_MAX_LINES: int = 30
const NODE_TOOLTIP_MAX: int = 10
const REFRESH_DELAY: float = 0.4
const ORPHAN_KEY: String = "#orphans"

enum MenuId { COLLAPSE_ALL, EXPAND_ALL, TOGGLE_THIS, SHOW_IN_FILESYSTEM }

const _STRINGS: Dictionary = {
	"dock_title": ["UI 트리", "UI Tree"],
	"filter": ["씬 이름 필터", "Filter scenes"],
	"todo_only": ["TODO만", "TODO only"],
	"todo_only_tip": ["TODO 가 있는 씬(과 그 위 씬)만 보기", "Show only scenes with TODO (and their parents)"],
	"reload_tip": ["다시 읽기", "Rescan"],
	"orphan_group": ["씬에 포함 안 된 Comp (%d)", "Comps not in any scene (%d)"],
	"orphan_group_tip": ["어느 씬에도 인스턴스되지 않고 어느 씬 스크립트도 만들지 않는 UI_Comp — 헬퍼 스크립트가 만들거나 안 쓰는 씬",
		"UI_Comps no scene instances and no scene script creates — built by helper scripts, or unused"],
	"tag_code": ["[코드]", "[code]"],
	"tag_unused": ["[미사용]", "[unused]"],
	"code_child": ["코드 생성", "code"],
	"code_child_tip": ["코드 생성 — %s 가 만든다", "Created in code by %s"],
	"cycle": ["순환", "cycle"],
	"more": ["… 외 %d", "… and %d more"],
	"error": ["오류: %s", "Error: %s"],
	"error_read": ["씬 파일을 읽을 수 없음", "Cannot read the scene file"],
	"instanced_by": ["포함하는 씬: %s", "Instanced by: %s"],
	"created_by": ["코드로 만드는 씬: %s", "Created in code by: %s"],
	"code_refs": ["코드에서 참조: %s", "Referenced in code: %s"],
	"no_refs": ["참조하는 씬 · 코드 없음 — 안 쓰는 씬일 수 있음", "No scene or script references it — possibly unused"],
	"todo_title": ["TODO — 구현할 자리", "TODO — work to implement"],
	"more_nodes": ["외 %d개", "%d more"],
	"summary": ["Screen %d · View %d · Comp %d · TODO %d", "Screen %d · View %d · Comp %d · TODO %d"],
	"collapse_all": ["모두 접기", "Collapse All"],
	"expand_all": ["모두 펼치기", "Expand All"],
	"expand_this": ["이 씬 펼치기", "Expand This Scene"],
	"collapse_this": ["이 씬 접기", "Collapse This Scene"],
	"show_in_fs": ["FileSystem 에서 보기", "Show in FileSystem"],
}

var _tree: Tree
var _search: LineEdit
var _todo_only: Button
var _summary: Label
var _menu: PopupMenu
var _refresh_timer: Timer

var _korean: bool = false
var _scenes: Dictionary = {}
var _subtree_cache: Dictionary = {}
var _expanded: Dictionary = {}
var _menu_item: TreeItem
var _building: bool = false


static func is_korean_editor() -> bool:
	var lang: String = str(EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language"))
	return lang.begins_with("ko")


static func dock_title() -> String:
	return _STRINGS["dock_title"][0 if is_korean_editor() else 1]


func _ready() -> void:
	_korean = is_korean_editor()
	_build_ui()
	request_refresh()


func request_refresh(_saved_path: String = "") -> void:
	if _refresh_timer != null:
		_refresh_timer.start()


func _t(key: String) -> String:
	return _STRINGS[key][0 if _korean else 1]


func _build_ui() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	add_child(bar)

	_search = LineEdit.new()
	_search.placeholder_text = _t("filter")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.right_icon = _icon(&"Search")
	_search.text_changed.connect(func(_t_: String) -> void: _rebuild())
	bar.add_child(_search)

	_todo_only = Button.new()
	_todo_only.text = _t("todo_only")
	_todo_only.toggle_mode = true
	_todo_only.tooltip_text = _t("todo_only_tip")
	_todo_only.toggled.connect(func(_on: bool) -> void: _rebuild())
	bar.add_child(_todo_only)

	var reload: Button = Button.new()
	reload.flat = true
	reload.icon = _icon(&"Reload")
	reload.tooltip_text = _t("reload_tip")
	reload.pressed.connect(_rescan)
	bar.add_child(reload)

	_tree = Tree.new()
	_tree.columns = 3
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_rmb_select = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for col in [COL_TODO, COL_NODES]:
		_tree.set_column_expand(col, false)
		_tree.set_column_custom_minimum_width(col, COUNT_COL_WIDTH)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	_tree.empty_clicked.connect(_on_empty_clicked)
	add_child(_tree)

	_summary = Label.new()
	_summary.add_theme_color_override(&"font_color", get_theme_color(&"font_readonly_color", &"Editor"))
	add_child(_summary)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)

	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.wait_time = REFRESH_DELAY
	_refresh_timer.timeout.connect(_rescan)
	add_child(_refresh_timer)


func _icon(icon_name: StringName) -> Texture2D:
	return get_theme_icon(icon_name, &"EditorIcons")


func _rescan() -> void:
	_scenes = Scanner.new().scan()
	_subtree_cache.clear()
	_rebuild()


# ── 트리 만들기 ───────────────────────────────────────────────────────────────

func _rebuild() -> void:
	if _tree == null:
		return
	_building = true
	_tree.clear()
	var root: TreeItem = _tree.create_item()

	var screens: Array = []
	var views: Array = []
	var orphans: Array = []
	for path in _scenes:
		var info: Dictionary = _scenes[path]
		match info["kind"]:
			"screen":
				screens.append(path)
			"view":
				views.append(path)
			_:
				if _is_orphan(info):
					orphans.append(path)
	screens.sort_custom(_by_name)
	views.sort_custom(_by_name)
	orphans.sort_custom(_by_name)

	for path in screens + views:
		_add_scene_item(root, path, 1, "", path, [path])

	if not orphans.is_empty():
		var group: TreeItem = _tree.create_item(root)
		group.set_text(COL_NAME, _t("orphan_group") % orphans.size())
		group.set_icon(COL_NAME, _icon(&"Folder"))
		group.set_tooltip_text(COL_NAME, _t("orphan_group_tip"))
		group.set_metadata(COL_NAME, {"path": "", "key": ORPHAN_KEY})
		var kept: int = 0
		for path in orphans:
			if _add_scene_item(group, path, 1, "", ORPHAN_KEY + ">" + path, [path]) != null:
				kept += 1
		if kept == 0:
			root.remove_child(group)
			group.free()
		else:
			group.collapsed = not _is_filtering() and not _expanded.get(ORPHAN_KEY, false)

	_update_summary()
	_building = false


## `via_script` 가 비어 있지 않으면 인스턴스가 아니라 그 스크립트가 코드로 만드는 씬.
## 필터에 걸러지면 만들지 않고 null 을 돌려준다.
func _add_scene_item(parent: TreeItem, path: String, count: int, via_script: String, key: String, stack: Array) -> TreeItem:
	var info: Dictionary = _scenes[path]
	var item: TreeItem = _tree.create_item(parent)
	item.set_metadata(COL_NAME, {"path": path, "key": key})

	var label: String = info["name"]
	if count > 1:
		label += "  ×%d" % count
	if via_script != "":
		label += "  (%s)" % _t("code_child")
	if _is_orphan(info):
		label += "  " + (_t("tag_code") if not info["code_refs"].is_empty() else _t("tag_unused"))
	item.set_text(COL_NAME, label)

	var tip: String = _name_tooltip(info)
	if via_script != "":
		tip = _t("code_child_tip") % via_script.get_file() + "\n" + tip
		item.set_custom_color(COL_NAME, get_theme_color(&"font_readonly_color", &"Editor"))
	item.set_tooltip_text(COL_NAME, tip)
	if info["error"] != "":
		item.set_icon(COL_NAME, _icon(&"StatusError"))
	elif via_script != "":
		item.set_icon(COL_NAME, _icon(&"Script"))
	else:
		item.set_icon(COL_NAME, _icon({"screen": &"PlayScene", "view": &"PackedScene"}.get(info["kind"], &"Instance")))

	var descendants: Array = _descendants(path)
	_fill_count(item, COL_TODO, info, "todo", descendants, _icon(&"StatusWarning"),
			get_theme_color(&"warning_color", &"Editor"), _t("todo_title"))
	_fill_nodes(item, info)

	var child_kept: bool = false
	var instanced: Array = info["children"].keys()
	instanced.sort_custom(_by_name)
	for child in instanced:
		if _add_child_item(item, child, int(info["children"][child]), "", key, stack):
			child_kept = true
	var coded: Array = info["code_children"].keys()
	coded.sort_custom(_by_name)
	for child in coded:
		if _add_child_item(item, child, 1, info["code_children"][child], key, stack):
			child_kept = true

	if not child_kept and not _passes_filter(info):
		parent.remove_child(item)
		item.free()
		return null

	if item.get_child_count() > 0:
		item.collapsed = not _is_filtering() and not _expanded.get(key, false)
	return item


func _add_child_item(item: TreeItem, child: String, count: int, via_script: String, key: String, stack: Array) -> bool:
	if not _scenes.has(child):
		return false
	var child_key: String = key + ">" + child
	if stack.has(child):
		var loop: TreeItem = _tree.create_item(item)
		loop.set_text(COL_NAME, "%s  (%s)" % [_scenes[child]["name"], _t("cycle")])
		loop.set_icon(COL_NAME, _icon(&"StatusWarning"))
		loop.set_metadata(COL_NAME, {"path": child, "key": child_key})
		return true
	return _add_scene_item(item, child, count, via_script, child_key, stack + [child]) != null


func _fill_count(item: TreeItem, col: int, info: Dictionary, field: String, descendants: Array,
		icon: Texture2D, color: Color, title: String) -> void:
	var own: int = info[field].size()
	var sub: int = 0
	var lines: PackedStringArray = []
	for entry in info[field]:
		lines.append("• %s — %s" % [entry[0], str(entry[1]).get_slice("\n", 0)])
	for path in descendants:
		var n: int = _scenes[path][field].size()
		if n > 0:
			sub += n
			lines.append("↳ %s: %d" % [_scenes[path]["name"], n])
	if own == 0 and sub == 0:
		return

	var text: String = str(own) if own > 0 else ""
	if sub > 0:
		text += (" " if text != "" else "") + "(+%d)" % sub
	item.set_text(col, text)
	item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_icon(col, icon)
	var tint: Color = color if own > 0 else get_theme_color(&"font_readonly_color", &"Editor")
	item.set_custom_color(col, tint)
	item.set_icon_modulate(col, tint)

	if lines.size() > TOOLTIP_MAX_LINES:
		var rest: int = lines.size() - TOOLTIP_MAX_LINES
		lines.resize(TOOLTIP_MAX_LINES)
		lines.append(_t("more") % rest)
	item.set_tooltip_text(col, title + "\n" + "\n".join(lines))


func _fill_nodes(item: TreeItem, info: Dictionary) -> void:
	var nodes: Array = info["nodes"]
	if nodes.is_empty():
		return
	item.set_text(COL_NODES, str(nodes.size()))
	item.set_text_alignment(COL_NODES, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_icon(COL_NODES, _icon(&"Node"))
	var tint: Color = get_theme_color(&"font_readonly_color", &"Editor")
	item.set_custom_color(COL_NODES, tint)
	item.set_icon_modulate(COL_NODES, tint)
	var lines: PackedStringArray = []
	for node_path in nodes.slice(0, NODE_TOOLTIP_MAX):
		lines.append(node_path)
	if nodes.size() > NODE_TOOLTIP_MAX:
		lines.append(_t("more_nodes") % (nodes.size() - NODE_TOOLTIP_MAX))
	item.set_tooltip_text(COL_NODES, "\n".join(lines))


func _name_tooltip(info: Dictionary) -> String:
	var lines: PackedStringArray = [info["path"]]
	if info["error"] != "":
		lines.append(_t("error") % _t("error_read"))
	if not info["parents"].is_empty():
		lines.append(_t("instanced_by") % ", ".join(_names(info["parents"])))
	if not info["code_parents"].is_empty():
		lines.append(_t("created_by") % ", ".join(_names(info["code_parents"])))
	if not info["code_refs"].is_empty():
		lines.append(_t("code_refs") % ", ".join(info["code_refs"]))
	elif _is_orphan(info):
		lines.append(_t("no_refs"))
	return "\n".join(lines)


func _names(paths: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for p in paths:
		out.append(_scenes[p]["name"])
	return out


## 아래에 들어 있는 UI 씬 전부 — 인스턴스 + 코드 생성 (자기 자신 제외, 같은 씬은 한 번).
func _descendants(path: String) -> Array:
	if _subtree_cache.has(path):
		return _subtree_cache[path]
	var seen: Dictionary = {}
	var queue: Array = [path]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for child in _scenes[cur]["children"].keys() + _scenes[cur]["code_children"].keys():
			if _scenes.has(child) and child != path and not seen.has(child):
				seen[child] = true
				queue.append(child)
	var result: Array = seen.keys()
	_subtree_cache[path] = result
	return result


func _is_orphan(info: Dictionary) -> bool:
	return info["kind"] == "comp" and info["parents"].is_empty() and info["code_parents"].is_empty()


func _passes_filter(info: Dictionary) -> bool:
	if _todo_only.button_pressed and info["todo"].is_empty():
		return false
	var needle: String = _search.text.strip_edges().to_lower()
	return needle == "" or str(info["name"]).to_lower().contains(needle)


func _is_filtering() -> bool:
	return _todo_only.button_pressed or _search.text.strip_edges() != ""


func _by_name(a: String, b: String) -> bool:
	return a.get_file().naturalnocasecmp_to(b.get_file()) < 0


func _update_summary() -> void:
	var kinds: Dictionary = {"screen": 0, "view": 0, "comp": 0}
	var todo: int = 0
	for path in _scenes:
		var info: Dictionary = _scenes[path]
		kinds[info["kind"]] += 1
		todo += info["todo"].size()
	_summary.text = _t("summary") % [kinds["screen"], kinds["view"], kinds["comp"], todo]


# ── 입력 ──────────────────────────────────────────────────────────────────────

func _on_item_activated() -> void:
	var path: String = _item_path(_tree.get_selected())
	if path == "":
		return
	EditorInterface.open_scene_from_path(path)
	_focus_dock(EditorInterface.get_base_control().find_children("*", "SceneTreeDock", true, false))


func _on_item_collapsed(item: TreeItem) -> void:
	if _building or _is_filtering():
		return
	_expanded[item.get_metadata(COL_NAME)["key"]] = not item.collapsed


func _on_item_mouse_selected(mouse_pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_open_menu(_tree.get_item_at_position(mouse_pos), mouse_pos)


func _on_empty_clicked(mouse_pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_open_menu(null, mouse_pos)


func _open_menu(item: TreeItem, mouse_pos: Vector2) -> void:
	_menu_item = item
	_menu.clear()
	_menu.add_icon_item(_icon(&"GuiTreeArrowRight"), _t("collapse_all"), MenuId.COLLAPSE_ALL)
	_menu.add_icon_item(_icon(&"GuiTreeArrowDown"), _t("expand_all"), MenuId.EXPAND_ALL)
	if item != null:
		_menu.add_separator()
		var collapsed: bool = item.collapsed or item.get_child_count() == 0
		_menu.add_item(_t("expand_this") if collapsed else _t("collapse_this"), MenuId.TOGGLE_THIS)
		_menu.set_item_disabled(_menu.get_item_index(MenuId.TOGGLE_THIS), item.get_child_count() == 0)
		if _item_path(item) != "":
			_menu.add_separator()
			_menu.add_icon_item(_icon(&"Filesystem"), _t("show_in_fs"), MenuId.SHOW_IN_FILESYSTEM)
	_menu.reset_size()
	_menu.position = Vector2i(_tree.get_screen_position() + mouse_pos)
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.COLLAPSE_ALL, MenuId.EXPAND_ALL:
			var collapse: bool = id == MenuId.COLLAPSE_ALL
			for top in _tree.get_root().get_children():
				top.set_collapsed_recursive(collapse)
		MenuId.TOGGLE_THIS:
			if _menu_item != null:
				_menu_item.set_collapsed_recursive(not _menu_item.collapsed)
		MenuId.SHOW_IN_FILESYSTEM:
			var path: String = _item_path(_menu_item)
			if path != "":
				var fs_dock: FileSystemDock = EditorInterface.get_file_system_dock()
				fs_dock.navigate_to_path(path)
				_focus_dock([fs_dock])
	_remember_expansion(_tree.get_root())


# 접기 · 펼치기를 한꺼번에 바꾼 뒤 상태를 다시 적는다 — 다음 갱신 때 그대로 그리도록.
func _remember_expansion(item: TreeItem) -> void:
	if item == null or _is_filtering():
		return
	for child in item.get_children():
		var meta: Variant = child.get_metadata(COL_NAME)
		if meta is Dictionary and child.get_child_count() > 0:
			_expanded[meta["key"]] = not child.collapsed
		_remember_expansion(child)


func _item_path(item: TreeItem) -> String:
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(COL_NAME)
	return meta["path"] if meta is Dictionary else ""


# 독이 탭으로 묶여 있으면 그 탭을 앞으로 (Scene 탭은 이 독과 같은 칸이라 전환된다).
func _focus_dock(found: Array) -> void:
	if found.is_empty():
		return
	var dock: Control = found[0] as Control
	var tabs: TabContainer = dock.get_parent() as TabContainer
	if tabs != null:
		tabs.current_tab = dock.get_index()
