@tool
extends EditorPlugin

# 에디터 왼쪽 위(Scene 탭 옆)에 "UI 트리" 독을 붙이는 껍데기.
# 화면 · 갱신은 `ui_scene_tree_dock.gd`, 스캔 로직은 `ui_scene_scanner.gd`.

const Dock = preload("res://addons/ui_scene_tree/ui_scene_tree_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = Dock.dock_title()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _dock)
	scene_saved.connect(_dock.request_refresh)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_dock.request_refresh)


func _exit_tree() -> void:
	if _dock == null:
		return
	scene_saved.disconnect(_dock.request_refresh)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_dock.request_refresh)
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
