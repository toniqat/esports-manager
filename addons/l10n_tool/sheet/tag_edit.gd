@tool
extends TextEdit

# Text field of the L10n editor dock (source · target). Typing `{` opens a VS Code style list under
# the caret: the row's tags (`tags`: placeholders, josa tags), `{plural:` (offer_plural) and "find
# string". Typing on filters it; after `{tx_` (the key prefix) only "find string" is left.
# Up / Down move, Enter / Tab pick, Esc closes, click picks. Picking "find string" emits
# find_string_requested; the sheet opens the key picker and calls insert_key_ref.
# The list is our own top-level ItemList (never focused): CodeEdit's built-in completion is only
# requested by the script editor, and it draws inside the field, so a one-line field clips it.
# Height follows the content (scroll_fit_content_height, one line minimum).

signal find_string_requested(edit: TextEdit)

const LIST_WIDTH := 260
const LIST_MAX_ROWS := 8

## Tag names offered after `{`: set by the sheet per row.
var tags: PackedStringArray = PackedStringArray()
## Offer `{plural:` (target languages).
var offer_plural: bool = false
## Display text of the "find string" item (UI language).
var find_label: String = "Find string…"
var key_prefix: String = "tx_"
var find_icon: Texture2D = null

var _list: ItemList = null
## Options shown in the list: [{label, insert, find}].
var _shown: Array = []


func _ready() -> void:
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	_list = ItemList.new()
	_list.top_level = true
	_list.focus_mode = Control.FOCUS_NONE
	_list.auto_height = true
	_list.z_as_relative = false
	_list.z_index = 100
	_list.visible = false
	_list.item_clicked.connect(func(index: int, _pos: Vector2, _button: int) -> void: _pick(index))
	add_child(_list, false, Node.INTERNAL_MODE_FRONT)
	text_changed.connect(_update_list)
	caret_changed.connect(func() -> void:
		if _list.visible:
			_update_list())
	focus_exited.connect(_close_list)


## Column of the `{` the caret is inside (no `}` between it and the caret), -1 when none.
func open_brace() -> int:
	var line: String = get_line(get_caret_line()).left(get_caret_column())
	var b: int = line.rfind("{")
	if b < 0 or line.find("}", b) >= 0:
		return -1
	return b


## Options for what was typed after `{`: tags / plural starting with it, "find string" always,
## only "find string" once the typed text starts with the key prefix.
func completions(typed: String) -> Array:
	var t: String = typed.to_lower()
	var out: Array = []
	if not t.begins_with(key_prefix):
		var all: Array = []
		for tag in tags:
			all.append({"label": "{%s}" % tag, "insert": tag + "}", "find": false})
		if offer_plural:
			all.append({"label": "{plural:name|…}", "insert": "plural:", "find": false})
		for o in all:
			var ins: String = String(o["insert"]).to_lower()
			if ins.begins_with(t) and ins != t:
				out.append(o)
	out.append({"label": find_label, "insert": "", "find": true})
	return out


func _update_list() -> void:
	var b: int = open_brace()
	if not has_focus() or not editable or b < 0:
		_close_list()
		return
	_shown = completions(get_line(get_caret_line()).substr(b + 1, get_caret_column() - b - 1))
	_list.clear()
	for o in _shown:
		_list.add_item(String(o["label"]), find_icon if o["find"] else null)
	_list.max_columns = 1
	_list.select(0)
	var w: float = LIST_WIDTH * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)
	_list.custom_minimum_size = Vector2(w, 0)
	_list.size = Vector2(w, 0)
	_list.reset_size()
	var row_h: float = get_line_height()
	var pos: Vector2 = global_position + get_caret_draw_pos() + Vector2(0, row_h * 0.35)
	var bottom: float = get_viewport_rect().size.y
	if pos.y + _list.size.y > bottom:
		pos.y = global_position.y + get_caret_draw_pos().y - row_h - _list.size.y
	_list.global_position = pos
	_list.visible = true


func _close_list() -> void:
	if _list != null:
		_list.visible = false


func _gui_input(event: InputEvent) -> void:
	if _list == null or not _list.visible:
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.ctrl_pressed or k.alt_pressed:
		return
	var sel: int = _list.get_selected_items()[0] if _list.is_anything_selected() else 0
	match k.keycode:
		KEY_UP:
			_list.select(maxi(sel - 1, 0))
		KEY_DOWN:
			_list.select(mini(sel + 1, _list.item_count - 1))
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			_pick(sel)
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
	if o["find"]:
		find_string_requested.emit(self)
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
