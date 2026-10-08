extends SceneTree

# Headless Draft import (mental events):
#   godot --headless --path . --script res://addons/draft_import/cli.gd [-- --dry] [-- --no-rebuild]
# Reads `res://data/draft/*.json` (Draft runtime export), syncs `data/l10n/src/mental.csv`,
# writes `mental_events.csv` / `mental_texts.csv`, then rebuilds game.db (+ l10n build dev)
# unless `--dry` / `--no-rebuild`.

const DraftImport = preload("res://addons/draft_import/draft_import.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var dry: bool = args.has("--dry")
	var rep: Dictionary = DraftImport.run(DraftImport.DATA_DIR, dry)
	for w in rep["warnings"]:
		print("경고: ", w)
	print("Draft import%s: 이벤트 %d · 새 텍스트 %d · 수정 %d칸 · 삭제 %d" % [
			" (dry)" if dry else "", rep["events"], rep["new"], rep["edited"], rep["removed"]])
	if String(rep["error"]) != "":
		printerr("오류: ", rep["error"])
		quit(1)
		return
	if dry or args.has("--no-rebuild"):
		quit(0)
		return
	var err: String = load("res://addons/csv_to_db/csv_to_db.gd").new().call("rebuild")
	if err != "":
		printerr(err)
	quit(1 if err != "" else 0)
