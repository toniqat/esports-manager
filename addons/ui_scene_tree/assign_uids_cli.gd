extends SceneTree

# 헤드리스: uid 가 없는 `.tscn` 헤더에 uid 를 넣는다 (에디터로 열어 저장하는 것과 같은 결과).
#
#   godot --headless --path . -s res://addons/ui_scene_tree/assign_uids_cli.gd [-- --dry]
#
# 코드나 LLM 이 텍스트로 만든 씬은 첫 줄 `[gd_scene … format=3]` 에 `uid="uid://…"` 가 없다.
# 이 스크립트는 그런 파일마다 `ResourceUID.create_id()` 로 새 id 를 받아 **첫 줄만** 고친다
# (나머지 바이트는 그대로, diff 는 한 줄). 다음 `--import` · 에디터 스캔이 그 uid 를 등록한다.
# 경로로 참조하던 다른 씬 · 스크립트는 그대로 동작한다.
#
# `--dry` = 고치지 않고 목록만. 제외: `addons/` · `build/` · `ios/` 와 숨김 폴더(`.godot` · `.claude` …).

const SKIP_DIRS: Array = ["res://addons", "res://build", "res://ios"]


func _init() -> void:
	var dry: bool = OS.get_cmdline_user_args().has("--dry")
	var found: Array = []
	_walk("res://", found)
	var fixed: int = 0
	for path in found:
		if dry:
			print("NO UID  ", path)
			continue
		var uid_text: String = _assign(String(path))
		if uid_text != "":
			fixed += 1
			print("UID     ", path, "  ", uid_text)
	print("assign_uids: %d without uid, %d fixed%s" % [found.size(), fixed, " (dry run)" if dry else ""])
	quit()


## `.tscn` files under `dir` whose header line has no uid.
func _walk(dir: String, out: Array) -> void:
	if SKIP_DIRS.has(dir.trim_suffix("/")):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for sub in d.get_directories():
		if String(sub).begins_with("."):
			continue
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if String(f).get_extension() != "tscn":
			continue
		var path: String = dir.path_join(f)
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		var head: String = fa.get_line()
		if head.begins_with("[gd_scene") and head.find("uid=\"uid://") < 0:
			out.append(path)


## Insert a fresh uid into the header of `path`. Returns the uid text, "" on failure.
func _assign(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var text: String = fa.get_as_text()
	fa.close()
	var nl: int = text.find("\n")
	var head: String = text.substr(0, nl) if nl >= 0 else text
	var close: int = head.rfind("]")
	if close < 0:
		return ""
	var uid_text: String = ResourceUID.id_to_text(ResourceUID.create_id())
	var new_head: String = head.substr(0, close) + " uid=\"%s\"" % uid_text + head.substr(close)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return ""
	out.store_string(new_head + (text.substr(nl) if nl >= 0 else ""))
	out.close()
	return uid_text
