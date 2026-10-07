@tool
extends EditorPlugin

# Shell that registers the Project → Tools → L10n menu and the "L10n" main screen tab (the
# sheet editor — sheet/). All logic lives in core/ RefCounted classes (`core/l10n.gd` facade):
# an EditorPlugin cannot be created headless.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const SHEET_SCENE := "res://addons/l10n_tool/sheet/l10n_sheet.tscn"
const MENU_NAME := "L10n"

enum { ID_BUILD_DEV, ID_BUILD_RELEASE, ID_VALIDATE, ID_SCAN, ID_SYNC }

var _menu: PopupMenu
# Main screen "L10n" tab — sheet editor.
var _sheet: Control


func _enter_tree() -> void:
	_menu = PopupMenu.new()
	_menu.add_item("build dev", ID_BUILD_DEV)
	_menu.add_item("build release (export 직전, 커밋 금지)", ID_BUILD_RELEASE)
	_menu.add_separator()
	_menu.add_item("validate", ID_VALIDATE)
	_menu.add_item("scan", ID_SCAN)
	_menu.add_item("sync", ID_SYNC)
	_menu.id_pressed.connect(_on_menu)
	add_tool_submenu_item(MENU_NAME, _menu)
	if ResourceLoader.exists(SHEET_SCENE):
		_sheet = (load(SHEET_SCENE) as PackedScene).instantiate()
		_sheet.call("setup", self)
		_sheet.hide()
		EditorInterface.get_editor_main_screen().add_child(_sheet)
		scene_changed.connect(Callable(_sheet, "on_scene_changed"))


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null


func _has_main_screen() -> bool:
	return true


func _make_visible(shown: bool) -> void:
	if _sheet != null:
		_sheet.visible = shown


func _get_plugin_name() -> String:
	return MENU_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Translation", &"EditorIcons")


func _on_menu(id: int) -> void:
	var l: L10n = L10n.open()
	if not l.ok():
		push_error("L10n: config.json 을 읽지 못했다")
		return
	match id:
		ID_BUILD_DEV:
			l.cmd_build(L10n.MODE_DEV)
		ID_BUILD_RELEASE:
			l.cmd_build(L10n.MODE_RELEASE)
		ID_VALIDATE:
			l.cmd_validate(L10n.MODE_DEV)
		ID_SCAN:
			l.cmd_scan()
		ID_SYNC:
			l.cmd_sync()
	EditorInterface.get_resource_filesystem().scan()
