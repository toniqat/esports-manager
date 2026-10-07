@tool
extends EditorPlugin

# Project → Tools → L10n 메뉴와 조회 도크를 등록하는 껍데기. 로직은 전부 core/ 의
# RefCounted(`core/l10n.gd` 파사드)에 있다 — csv_to_db 와 같은 이유(EditorPlugin 은
# 헤드리스에서 만들 수 없다).

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const DOCK_SCENE := "res://addons/l10n_tool/dock/l10n_dock.tscn"
const MENU_NAME := "L10n"

enum { ID_BUILD_DEV, ID_BUILD_RELEASE, ID_VALIDATE, ID_SCAN, ID_SYNC }

var _menu: PopupMenu
var _dock: Control


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
	if ResourceLoader.exists(DOCK_SCENE):
		_dock = (load(DOCK_SCENE) as PackedScene).instantiate()
		if _dock.has_method("setup"):
			_dock.call("setup", self)
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


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
