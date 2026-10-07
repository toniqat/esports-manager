@tool
extends RefCounted

## Which game screen a file ends up in — for the sheet's usage list (no UI, headless-testable).
##
## Files = every .gd / .tscn under the root (skipping EXCLUDE_DIRS and .gdignore folders), keyed
## by their res:// path. "X is used by Y" edges:
##   - a .tscn's ext_resource (script or instanced scene) → used by that .tscn
##   - a .gd's `preload("…")` / `load("…")` of a .gd / .tscn → used by that .gd
##   - a .gd mentioning another script's `class_name` outside comments → used by that .gd
## Screens = `scenes/*.tscn` the game switches to: the main scene, or a path literal on a line
## with `change_scene` or in a `…: String = "res://scenes/…"` const. Navigation literals are not
## edges (switching to a screen does not contain it). `screens_of(path)` walks upward
## (breadth-first) and stops at screens; each hit carries the chain it came by. Walking up:
##   - a script attached to scenes goes only to those scenes (code mentioning a scene's script
##     class is mostly type hints / casts, which would leak into unrelated screens);
##   - a scene goes to what uses it plus what uses the class of a script attached to it alone
##     (`Xxx.create()` callers), minus its own scripts;
##   - any other script goes to what uses it, unless it is a shared library (`_is_hub`).

const SCREEN_DIR := "res://scenes/"
const EXCLUDE_DIRS := ["res://addons/", "res://.godot/", "res://data/l10n/", "res://build/", "res://ios/", "res://_dump/"]
const MAX_DEPTH := 8
## See _is_hub.
const HUB_USERS := 12

## res path → [res paths that use it]
var users: Dictionary = {}
## scene → [scripts it attaches] and script → [scenes attaching it] (ext_resource type="Script")
var scene_scripts: Dictionary = {}
var script_scenes: Dictionary = {}
## res path of each screen scene → true
var screens: Dictionary = {}

var _root: String = "res://"


## Builds the map from the files under `root` (a real folder treated as res://, default the
## project). main_scene = the project's `run/main_scene`.
static func build(main_scene: String, root: String = "res://") -> RefCounted:
	var m: RefCounted = load("res://addons/l10n_tool/sheet/screen_map.gd").new()
	m.call("_build", main_scene, root)
	return m


## Screens the file ends up in: [{screen: "BattleSim", path, chain: [screen … file]}], nearest
## first. The file itself counts when it is a screen.
func screens_of(path: String) -> Array:
	var out: Array = []
	var prev: Dictionary = {path: ""}
	var frontier: Array = [path]
	for _depth in MAX_DEPTH + 1:
		var next: Array = []
		for p in frontier:
			if screens.has(p):
				out.append({"screen": String(p).get_file().get_basename(), "path": p, "chain": _chain(prev, p)})
				continue
			if p != path and _is_hub(p):
				continue
			for u in _up(p):
				if not prev.has(u):
					prev[u] = p
					next.append(u)
		if next.is_empty():
			break
		frontier = next
	return out


## Node path ("Parent/Child") of the `[node …]` section a .tscn line belongs to; "" if none.
static func node_path_at(lines: PackedStringArray, line: int) -> String:
	var re := RegEx.create_from_string("^\\[node name=\"([^\"]+)\"(?:[^\\]]*?parent=\"([^\"]*)\")?")
	for i in range(mini(line, lines.size()) - 1, -1, -1):
		var m := re.search(lines[i])
		if m == null:
			continue
		var node: String = m.get_string(1)
		var parent: String = m.get_string(2)
		if m.get_start(2) < 0:
			return node
		return node if parent == "." else "%s/%s" % [parent, node]
	return ""


## A shared library (scene-less script used by more than HUB_USERS files — themes, enums,
## helpers): passing through it would tie a file to every screen, so the walk does not climb
## past one (it still starts from one).
func _is_hub(p: String) -> bool:
	return not script_scenes.has(p) and p.ends_with(".gd") and (users.get(p, []) as Array).size() > HUB_USERS


## Next files up from p (see the class comment).
func _up(p: String) -> Array:
	if script_scenes.has(p):
		return script_scenes[p]
	var out: Array = (users.get(p, []) as Array).duplicate()
	var own: Array = scene_scripts.get(p, [])
	for sc in own:
		# Only the scene's own class — a helper attached to many scenes (DragScroll) says
		# nothing about who opens this one.
		if (script_scenes.get(sc, []) as Array).size() != 1:
			continue
		for u in users.get(sc, []):
			if not out.has(u) and not (script_scenes.get(sc, []) as Array).has(u):
				out.append(u)
	return out.filter(func(u: String) -> bool: return not own.has(u))


# ── build ───────────────────────────────────────────────────────────────

func _build(main_scene: String, root: String) -> void:
	_root = root.trim_suffix("/") + "/"
	var files: PackedStringArray = PackedStringArray()
	_collect(_root, files)
	var texts: Dictionary = {}
	var class_paths: Dictionary = {}
	var re_class := RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for f in files:
		var text: String = FileAccess.get_file_as_string(_disk(f))
		texts[f] = text
		if f.ends_with(".gd"):
			var m := re_class.search(text)
			if m != null:
				class_paths[m.get_string(1)] = f
	if main_scene != "":
		screens[main_scene] = true
	var re_ext := RegEx.create_from_string("\\[ext_resource[^\\]]*?path=\"(res://[^\"]+\\.(?:gd|tscn))\"")
	var re_ext_script := RegEx.create_from_string("\\[ext_resource[^\\]]*?type=\"Script\"[^\\]]*?path=\"(res://[^\"]+\\.gd)\"")
	var re_load := RegEx.create_from_string("\\b(?:pre)?load\\(\\s*\"(res://[^\"]+\\.(?:gd|tscn))\"")
	var re_screen := RegEx.create_from_string("\"(" + SCREEN_DIR + "[^\"/]+\\.tscn)\"")
	var re_ident := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9_]*\\b")
	for f in files:
		var text: String = texts[f]
		if f.ends_with(".tscn"):
			for m in re_ext.search_all(text):
				_edge(m.get_string(1), f)
			for m in re_ext_script.search_all(text):
				_add(scene_scripts, f, m.get_string(1))
				_add(script_scenes, m.get_string(1), f)
			continue
		var code: String = _strip_comments(text)
		for m in re_load.search_all(code):
			_edge(m.get_string(1), f)
		for line in code.split("\n"):
			if line.contains("change_scene") or line.contains(": String = \"" + SCREEN_DIR):
				for m in re_screen.search_all(line):
					screens[m.get_string(1)] = true
		var seen: Dictionary = {}
		for m in re_ident.search_all(_strip_comments(text, true)):
			var ident: String = m.get_string()
			if seen.has(ident) or not class_paths.has(ident):
				continue
			seen[ident] = true
			_edge(class_paths[ident], f)


func _edge(used: String, by: String) -> void:
	if used != by:
		_add(users, used, by)


static func _add(d: Dictionary, k: String, v: String) -> void:
	var arr: Array = d.get(k, [])
	if not arr.has(v):
		arr.append(v)
	d[k] = arr


func _collect(dir_res: String, out: PackedStringArray) -> void:
	for ex in EXCLUDE_DIRS:
		if _res(dir_res).begins_with(ex):
			return
	var d := DirAccess.open(_disk(_res(dir_res)))
	if d == null or d.file_exists(".gdignore"):
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(_res(dir_res).path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(_res(dir_res).path_join(sub) + "/", out)


## Root-relative folder/file → res:// path (identity for the real project).
func _res(p: String) -> String:
	return "res://" + p.trim_prefix(_root) if not p.begins_with("res://") else p


## res:// path → path on disk under the root.
func _disk(res_path: String) -> String:
	return _root + res_path.trim_prefix("res://")


func _chain(prev: Dictionary, last: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var p: String = last
	while p != "":
		out.append(p)
		p = String(prev.get(p, ""))
	return out


## Drops `#` comments (outside "…" / '…' strings) so class names in comments are not edges;
## drop_strings also empties string contents (the quotes stay) for the class-name scan.
static func _strip_comments(text: String, drop_strings: bool = false) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i in lines.size():
		var s: String = lines[i]
		if not s.contains("#") and not (drop_strings and (s.contains("\"") or s.contains("'"))):
			continue
		var out: String = ""
		var quote: String = ""
		var j: int = 0
		while j < s.length():
			var ch: String = s[j]
			if quote != "":
				if ch == "\\":
					if not drop_strings:
						out += s.substr(j, 2)
					j += 1
				elif ch == quote:
					quote = ""
					out += ch
				elif not drop_strings:
					out += ch
			elif ch == "#":
				break
			else:
				if ch == "\"" or ch == "'":
					quote = ch
				out += ch
			j += 1
		lines[i] = out
	return "\n".join(lines)
