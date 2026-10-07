extends Node

## Dev-only l10n key mode: **Ctrl+Alt+K** (or the run argument `--l10n-keys`) swaps the current
## locale's translation for one that maps every key to its alias, so each on-screen text shows
## where it comes from (`battle.pile_viewer.title`) — find it in the L10n sheet by that alias.
## Both paths to the screen go through `TranslationServer` (`Loc.t` and scene auto-translate),
## so nothing else changes. Scene texts refresh at once; texts code already set (`label.text =
## Loc.t(…)` in `_ready`) refresh when that UI is rebuilt — turn it on before opening a screen.
## Aliases come from `data/l10n/generated/index.json` (local, written by l10n scan / build);
## without it the raw `tx_` keys are shown. Release builds free this node at start.

const INDEX_PATH := "res://data/l10n/generated/index.json"
const RUN_ARG := "--l10n-keys"

var _on: bool = false
var _locale: String = ""
var _alias_tr: Translation = null
## Translations taken out of the TranslationServer while the mode is on.
var _removed: Array = []
var _badge: CanvasLayer = null


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has(RUN_ARG) or OS.get_cmdline_args().has(RUN_ARG):
		set_enabled.call_deferred(true)


func _input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_K and k.ctrl_pressed and k.alt_pressed:
		set_enabled(not _on)
		get_viewport().set_input_as_handled()


func is_enabled() -> bool:
	return _on


func set_enabled(on: bool) -> void:
	if on == _on:
		return
	if on:
		_locale = TranslationServer.get_locale()
		_removed.clear()
		var cur: Translation = TranslationServer.get_translation_object(_locale)
		while cur != null and _removed.size() < 8:
			_removed.append(cur)
			TranslationServer.remove_translation(cur)
			cur = TranslationServer.get_translation_object(_locale)
		_alias_tr = _build_alias_translation(_locale)
		TranslationServer.add_translation(_alias_tr)
	else:
		TranslationServer.remove_translation(_alias_tr)
		for t in _removed:
			TranslationServer.add_translation(t)
		_removed.clear()
		_alias_tr = null
	_on = on
	_show_badge(on)
	# Same locale again — notifies every node so auto-translated scene texts redraw.
	TranslationServer.set_locale(_locale)
	print("L10nKeyMode: %s" % ("on" if on else "off"))


## key → alias for every key in index.json; else key → key from the removed translations.
func _build_alias_translation(locale: String) -> Translation:
	var t := Translation.new()
	t.locale = locale
	var keys: Dictionary = {}
	if FileAccess.file_exists(INDEX_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			keys = (parsed as Dictionary).get("keys", {})
	if keys.is_empty():
		push_warning("L10nKeyMode: %s 없음 — key 를 그대로 표시 (l10n scan / build 후 다시)" % INDEX_PATH)
		for removed in _removed:
			for msg in (removed as Translation).get_message_list():
				t.add_message(msg, msg)
		return t
	for k in keys:
		var alias: String = String((keys[k] as Dictionary).get("alias", ""))
		t.add_message(k, alias if alias != "" else String(k))
	return t


func _show_badge(on: bool) -> void:
	if not on:
		if _badge != null:
			_badge.queue_free()
			_badge = null
		return
	_badge = CanvasLayer.new()
	_badge.layer = 128
	var label := Label.new()
	label.text = "L10N KEYS · Ctrl+Alt+K"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override(&"font_color", Color(1, 0.85, 0.2))
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	label.add_theme_font_size_override(&"font_size", 28)
	label.position = Vector2(12, 8)
	_badge.add_child(label)
	add_child(_badge)
