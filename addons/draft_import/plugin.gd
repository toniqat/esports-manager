@tool
extends EditorPlugin

# Project → Tools → "Draft: Import mental events" — same as the headless `cli.gd`:
# Draft runtime JSON (res://data/draft) → mental csv tables + l10n source, then Rebuild game.db.

const DraftImport = preload("res://addons/draft_import/draft_import.gd")
const MENU: String = "Draft: Import mental events"


func _enter_tree() -> void:
	add_tool_menu_item(MENU, _import)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU)


func _import() -> void:
	var rep: Dictionary = DraftImport.run()
	for w in rep["warnings"]:
		push_warning("Draft import: " + String(w))
	if String(rep["error"]) != "":
		push_error("Draft import: " + String(rep["error"]))
		return
	print("Draft import: 이벤트 %d · 새 텍스트 %d · 수정 %d칸 · 삭제 %d" % [
			rep["events"], rep["new"], rep["edited"], rep["removed"]])
	var err: String = load("res://addons/csv_to_db/csv_to_db.gd").new().call("rebuild")
	if err != "":
		push_error(err)
	EditorInterface.get_resource_filesystem().scan()
