@tool
extends RefCounted

# UI 씬(`UI_View_*` / `UI_Comp_*`) + 진입 씬(`scenes/*.tscn`) 포함 관계 · 마킹 스캐너 — 로직 본체.
#
# 독(`ui_scene_tree_dock.gd`)과 분리해 둔 이유는 csv_to_db 와 같다: 순수 RefCounted 라
# 헤드리스로도 돌릴 수 있다(`load(".../ui_scene_scanner.gd").new().scan()`).
#
# 씬은 `.tscn` 텍스트를 직접 읽는다 — 인스턴스 노드(`instance=`)가 어떤 씬인지,
# 각 노드의 `editor_description` 이 무엇인지. 마킹 규칙은 `docs/ui_scene_migration.md` §3 규칙 5 —
# 설명의 어느 줄이든 `TODO` 로 시작하면 구현할 자리.

const VIEW_PREFIX: String = "UI_View_"
const COMP_PREFIX: String = "UI_Comp_"
const TODO_PREFIX: String = "TODO"
const SCREEN_DIR: String = "res://scenes"
const SKIP_DIRS: PackedStringArray = ["res://addons", "res://build", "res://ios"]


## 씬 경로 → 정보 사전:
## { path, name, kind ("screen" / "view" / "comp"), todo: [[노드 경로, 설명]],
##   nodes: [루트 아래 노드 경로 — 인스턴스 노드는 1개, 그 속은 원본 씬 몫],
##   children: {자식 UI 씬 경로: 인스턴스 수}, parents: [경로],
##   scripts: [이 씬 노드에 붙은 .gd], code_refs: [이 씬 경로를 가진 .gd],
##   code_children: {이 씬 스크립트가 만드는 UI 씬 경로: .gd}, code_parents: [경로],
##   error ("" / "read") }
func scan() -> Dictionary:
	var tscn_files: PackedStringArray = []
	var gd_files: PackedStringArray = []
	_collect("res://", tscn_files, gd_files)

	var scenes: Dictionary = {}
	for path in tscn_files:
		if is_tracked_scene(path):
			scenes[path] = _read_scene(path)

	for path in scenes:
		for child in scenes[path]["children"]:
			if scenes.has(child):
				scenes[child]["parents"].append(path)

	_attach_code_refs(scenes, gd_files)
	_link_code_children(scenes)
	return scenes


## UI 씬 + 진입 씬 (Lobby · RunResult 등 — 코드로 탭 · 행을 만드는 화면의 뿌리).
static func is_tracked_scene(path: String) -> bool:
	return is_ui_scene(path) or (path.ends_with(".tscn") and path.get_base_dir() == SCREEN_DIR)


static func is_ui_scene(path: String) -> bool:
	var file: String = path.get_file()
	return file.ends_with(".tscn") and (file.begins_with(VIEW_PREFIX) or file.begins_with(COMP_PREFIX))


func _collect(dir_path: String, tscn_files: PackedStringArray, gd_files: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		match file.get_extension():
			"tscn":
				tscn_files.append(dir_path.path_join(file))
			"gd":
				gd_files.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		var sub_path: String = dir_path.path_join(sub)
		if not SKIP_DIRS.has(sub_path):
			_collect(sub_path, tscn_files, gd_files)


func _read_scene(path: String) -> Dictionary:
	var info: Dictionary = {
		"path": path,
		"name": path.get_file().get_basename(),
		"kind": _kind(path),
		"todo": [],
		"nodes": [],
		"children": {},
		"parents": [],
		"scripts": [],
		"code_refs": [],
		"code_children": {},
		"code_parents": [],
		"error": "",
	}
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		info["error"] = "read"
		return info

	var scene_ids: Dictionary = {}
	var script_ids: Dictionary = {}
	var node_path: String = ""
	var lines: PackedStringArray = text.split("\n")
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i]
		if line.begins_with("[ext_resource ") and _attr(line, "type") == "PackedScene":
			scene_ids[_attr(line, "id")] = _attr(line, "path")
		elif line.begins_with("[ext_resource ") and _attr(line, "type") == "Script":
			script_ids[_attr(line, "id")] = _attr(line, "path")
		elif line.begins_with("script = ExtResource(\"") and node_path != "":
			var script_path: String = script_ids.get(line.get_slice("\"", 1), "")
			if script_path != "" and not info["scripts"].has(script_path):
				info["scripts"].append(script_path)
		elif line.begins_with("[node "):
			node_path = _node_path(info["name"], line)
			if node_path != info["name"]:
				info["nodes"].append(node_path)
			var inst_id: String = _instance_id(line)
			var inst_path: String = scene_ids.get(inst_id, "")
			if is_tracked_scene(inst_path):
				info["children"][inst_path] = int(info["children"].get(inst_path, 0)) + 1
		elif line.begins_with("editor_description = \"") and node_path != "":
			var desc: Array = _read_string(lines, i, "editor_description = ".length())
			i = desc[1]
			_classify(info, node_path, desc[0])
		elif line.begins_with("[") and not line.begins_with("[node "):
			node_path = ""
		i += 1
	return info


static func _kind(path: String) -> String:
	if path.get_file().begins_with(VIEW_PREFIX):
		return "view"
	if path.get_file().begins_with(COMP_PREFIX):
		return "comp"
	return "screen"


# `.tscn` 텍스트를 직접 읽는다 — PackedScene 으로 불러오면 스크립트까지 컴파일해 느리다.
static func _attr(header: String, key: String) -> String:
	var start: int = header.find(" %s=\"" % key)
	if start < 0:
		return ""
	start += key.length() + 3
	return header.substr(start, header.find("\"", start) - start)


static func _instance_id(header: String) -> String:
	var start: int = header.find("instance=ExtResource(\"")
	if start < 0:
		return ""
	start += "instance=ExtResource(\"".length()
	return header.substr(start, header.find("\"", start) - start)


static func _node_path(scene_name: String, header: String) -> String:
	var node_name: String = _attr(header, "name")
	if header.find(" parent=\"") < 0:
		return scene_name
	var parent: String = _attr(header, "parent")
	return node_name if parent == "." else parent.path_join(node_name)


## 따옴표 문자열 값 (여러 줄 가능, `\"` · `\\` 이스케이프) → [값, 마지막 줄 번호].
static func _read_string(lines: PackedStringArray, line_idx: int, quote_col: int) -> Array:
	var out: String = ""
	var idx: int = line_idx
	var col: int = quote_col + 1
	while idx < lines.size():
		var line: String = lines[idx]
		while col < line.length():
			var ch: String = line[col]
			if ch == "\\" and col + 1 < line.length():
				var nxt: String = line[col + 1]
				out += {"n": "\n", "t": "\t"}.get(nxt, nxt)
				col += 2
				continue
			if ch == "\"":
				return [out, idx]
			out += ch
			col += 1
		out += "\n"
		idx += 1
		col = 0
	return [out, idx]


func _classify(info: Dictionary, node_path: String, desc: String) -> void:
	for line in desc.split("\n"):
		if line.strip_edges().begins_with(TODO_PREFIX):
			info["todo"].append([node_path, line.strip_edges()])


# 씬 경로를 문자열로 들고 있는 스크립트(`preload("res://…/UI_Comp_X.tscn")`, `SCENE_PATH`)를 찾는다.
# 팩토리 패턴 — 씬에 붙은 스크립트가 제 씬을 불러 `Xxx.create()` 로 만드는 경우 — 은
# `Xxx.create(` 를 부르는 스크립트도 그 씬을 참조하는 것으로 친다.
func _attach_code_refs(scenes: Dictionary, gd_files: PackedStringArray) -> void:
	var texts: Dictionary = {}
	for gd in gd_files:
		var text: String = FileAccess.get_file_as_string(gd)
		if text != "":
			texts[gd] = text
	for gd in texts:
		for path in scenes:
			if texts[gd].contains("\"%s\"" % path):
				scenes[path]["code_refs"].append(gd)

	var class_re: RegEx = RegEx.create_from_string(r"(?m)^class_name\s+(\w+)")
	for path in scenes:
		var info: Dictionary = scenes[path]
		for gd in info["scripts"]:
			if not info["code_refs"].has(gd) or not texts.has(gd):
				continue
			var found: RegExMatch = class_re.search(texts[gd])
			if found == null:
				continue
			var call_re: RegEx = RegEx.create_from_string(r"(?<![A-Za-z0-9_])%s\.create\(" % found.get_string(1))
			for other in texts:
				if other != gd and not info["code_refs"].has(other) and call_re.search(texts[other]) != null:
					info["code_refs"].append(other)


# 코드가 만드는 씬을, 그 코드(.gd)가 붙어 있는 UI 씬 아래에 단다. 이미 인스턴스로 들어 있으면 건너뛴다.
# 어느 UI 씬에도 붙지 않은 스크립트(HudBuilder 같은 헬퍼)의 참조는 code_refs 로만 남는다.
func _link_code_children(scenes: Dictionary) -> void:
	var owners: Dictionary = {}
	for path in scenes:
		for gd in scenes[path]["scripts"]:
			if not owners.has(gd):
				owners[gd] = []
			owners[gd].append(path)
	for path in scenes:
		if not is_ui_scene(path):
			continue  # 진입 씬은 코드가 만드는 게 아니라 화면 전환 대상이다
		for gd in scenes[path]["code_refs"]:
			for owner_path in owners.get(gd, []):
				var owner_info: Dictionary = scenes[owner_path]
				if owner_path == path or owner_info["children"].has(path) or owner_info["code_children"].has(path):
					continue
				owner_info["code_children"][path] = gd
				scenes[path]["code_parents"].append(owner_path)
