@tool
extends TextEdit

# Text field of the L10n editor dock (source · target). Typing `{` opens a VS Code style list under
# the caret: the row's tags (`tags`: placeholders, josa tags), `{plural:` (offer_plural),
# "{term_} find in glossary" and "{tx_} find string" (both with a magnifier at the right edge).
# Typing on filters it; after `{tx_` (the key prefix) only "find string" is left; after `{term_`
# the glossary words (`terms`, picking one inserts its key reference `{tx_…}`) and "find in
# glossary". Up / Down move, Enter / Tab pick, Esc closes, click picks. The two find items emit
# find_string_requested / find_term_requested; the sheet opens the modeless key picker (all keys /
# glossary terms) and calls insert_key_ref.
# The list is our own top-level Tree (never focused, two columns so the find icon sits at the right):
# CodeEdit's built-in completion is only requested by the script editor, and it draws inside the
# field, so a one-line field clips it.
# Height follows the content (scroll_fit_content_height, one line minimum).

signal find_string_requested(edit: TextEdit)
signal find_term_requested(edit: TextEdit)

const LIST_WIDTH := 300
const LIST_MAX_ROWS := 8
const TERM_PREFIX := "term_"

## Tag names offered after `{`: set by the sheet per row.
var tags: PackedStringArray = PackedStringArray()
## Offer `{plural:` (target languages).
var offer_plural: bool = false
## Offer key references: glossary words and "find string" / "find in glossary". Off for name
## rows (alias `….name`): names are plain text (E043).
var offer_refs: bool = true
## Display text of the "find string" / "find in glossary" items (UI language).
var find_label: String = "{tx_} Find string"
var find_term_label: String = "{term_} Find in glossary"
var key_prefix: String = "tx_"
var find_icon: Texture2D = null
## Glossary words linked to a key, set by the sheet: [{id (term_id), key, text (source)}].
var terms: Array = []

var _list: Tree = null
## Options shown in the list: [{label, insert, find}]; find = "" · "key" · "term"; a glossary
## word also has `key` (inserted as `{key}`).
var _shown: Array = []
var _items: Array = []
var _sel: int = 0


func _ready() -> void:
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	_list = Tree.new()
	_list.top_level = true
	_list.focus_mode = Control.FOCUS_NONE
	_list.hide_root = true
	_list.columns = 2
	_list.select_mode = Tree.SELECT_ROW
	_list.scroll_horizontal_enabled = false
	_list.set_column_expand(0, true)
	_list.set_column_expand(1, false)
	_list.z_as_relative = false
	_list.z_index = 100
	_list.visible = false
	_list.item_mouse_selected.connect(func(_pos: Vector2, _button: int) -> void:
		var it: TreeItem = _list.get_selected()
		if it != null:
			_pick(int(it.get_metadata(0))))
	add_child(_list, false, Node.INTERNAL_MODE_FRONT)
	text_changed.connect(_update_list)
	caret_changed.connect(func() -> void:
		if _list.visible:
			_update_list())
	focus_exited.connect(_close_list)


## Row tags + `{plural:` as list options.
func _tag_options() -> Array:
	var all: Array = []
	for tag in tags:
		all.append({"label": "{%s}" % tag, "insert": tag + "}", "find": ""})
	if offer_plural:
		all.append({"label": "{plural:name|…}", "insert": "plural:", "find": ""})
	return all


## Column of the `{` the caret is inside (no `}` between it and the caret), -1 when none.
func open_brace() -> int:
	var line: String = get_line(get_caret_line()).left(get_caret_column())
	var b: int = line.rfind("{")
	if b < 0 or line.find("}", b) >= 0:
		return -1
	return b


## Options for what was typed after `{`: tags / plural starting with it, then "find in glossary"
## (while the typed text could still become `term_`) and "find string"; only "find string" once
## the typed text starts with the key prefix; glossary words (`term_<id>` starting with it) +
## "find in glossary" once it starts with `term_`.
func completions(typed: String) -> Array:
	var t: String = typed.to_lower()
	var out: Array = []
	var find_term: Dictionary = {"label": find_term_label, "insert": "", "find": "term"}
	if not offer_refs:
		for o in _tag_options():
			var ins0: String = String(o["insert"]).to_lower()
			if ins0.begins_with(t) and ins0 != t:
				out.append(o)
		return out
	if t.begins_with(TERM_PREFIX):
		for g in terms:
			var term_tag: String = TERM_PREFIX + String(g["id"])
			if term_tag.begins_with(t):
				out.append({"label": "%s  %s" % [term_tag, g["text"]], "insert": "", "find": "", "key": g["key"]})
		out.append(find_term)
		return out
	if not t.begins_with(key_prefix):
		for o in _tag_options():
			var ins: String = String(o["insert"]).to_lower()
			if ins.begins_with(t) and ins != t:
				out.append(o)
		if not terms.is_empty() and TERM_PREFIX.begins_with(t):
			out.append(find_term)
	out.append({"label": find_label, "insert": "", "find": "key"})
	return out


func _update_list() -> void:
	var b: int = open_brace()
	if not has_focus() or not editable or b < 0:
		_close_list()
		return
	_shown = completions(get_line(get_caret_line()).substr(b + 1, get_caret_column() - b - 1))
	if _shown.is_empty():
		_close_list()
		return
	_list.clear()
	_items.clear()
	var root: TreeItem = _list.create_item()
	for i in _shown.size():
		var o: Dictionary = _shown[i]
		var it: TreeItem = _list.create_item(root)
		it.set_text(0, String(o["label"]))
		it.set_metadata(0, i)
		if o["find"] != "" and find_icon != null:
			it.set_icon(1, find_icon)
		_items.append(it)
	var ui_scale: float = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	_list.set_column_custom_minimum_width(1, int(24 * ui_scale))
	_select(0)
	var w: float = LIST_WIDTH * ui_scale
	# Long lists (glossary words) scroll inside LIST_MAX_ROWS rows instead of growing.
	var font: Font = _list.get_theme_font(&"font")
	var row: float = maxf(font.get_height(_list.get_theme_font_size(&"font_size")), 16 * ui_scale) + _list.get_theme_constant(&"v_separation") + 2
	var panel: StyleBox = _list.get_theme_stylebox(&"panel")
	var h: float = row * mini(_shown.size(), LIST_MAX_ROWS) + (panel.get_minimum_size().y if panel != null else 0.0) + 4
	_list.custom_minimum_size = Vector2(w, h)
	_list.size = Vector2(w, h)
	var row_h: float = get_line_height()
	var pos: Vector2 = global_position + get_caret_draw_pos() + Vector2(0, row_h * 0.35)
	var bottom: float = get_viewport_rect().size.y
	if pos.y + _list.size.y > bottom:
		pos.y = global_position.y + get_caret_draw_pos().y - row_h - _list.size.y
	_list.global_position = pos
	_list.visible = true


func _select(i: int) -> void:
	if _items.is_empty():
		return
	_sel = clampi(i, 0, _items.size() - 1)
	(_items[_sel] as TreeItem).select(0)
	_list.scroll_to_item(_items[_sel])


func _close_list() -> void:
	if _list != null:
		_list.visible = false


func _gui_input(event: InputEvent) -> void:
	if _list == null or not _list.visible:
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.ctrl_pressed or k.alt_pressed:
		return
	match k.keycode:
		KEY_UP:
			_select(_sel - 1)
		KEY_DOWN:
			_select(_sel + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			_pick(_sel)
		KEY_ESCAPE:
			_close_list()
		_:
			return
	accept_event()


func _pick(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	var o: Dictionary = _shown[index]
	_close_list()
	match String(o["find"]):
		"key":
			find_string_requested.emit(self)
		"term":
			find_term_requested.emit(self)
		_:
			if o.has("key"):
				_replace_open_tag("{%s}" % o["key"], true)
			else:
				_replace_open_tag(String(o["insert"]), false)


## Puts `{key}` at the caret, replacing an open `{…` typed before it (e.g. `{tx_`).
func insert_key_ref(key: String) -> void:
	grab_focus()
	_replace_open_tag("{%s}" % key, true)


func _replace_open_tag(text: String, with_brace: bool) -> void:
	var line: int = get_caret_line()
	var col: int = get_caret_column()
	var b: int = open_brace()
	begin_complex_operation()
	if b >= 0:
		select(line, b if with_brace else b + 1, line, col)
		delete_selection()
	insert_text_at_caret(text)
	end_complex_operation()
