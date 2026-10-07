class_name UiSceneDump
extends RefCounted

## 개발 도구 — **실행 중인** 코드 생성 UI 서브트리를 `.tscn` 초안으로 저장한다
## (`docs/ui_scene_migration.md` §6 T4). 결과는 절대 좌표 노드 그대로라 컨테이너로
## 다시 짜야 하는 **참고용 초안**이다. 게임 코드는 이 파일을 부르지 않는다 —
## 실행은 `UiSceneDumpRunner.gd`(CLI) 가 한다. 사용법 · 한계는 `resources/README.md`.
##
## 라이브 트리는 건드리지 않는다: 노드마다 새 노드를 만들어 저장 속성만 복사한다
## (`Node.duplicate()` 를 쓰지 않는 이유 — 시그널까지 복사되고, 스크립트 `_init` 이
## 만든 자식과 복사된 자식이 겹친다).

const DEFAULT_DIR: String = "res://_dump/"
## 자동 이름(`@Label@123`)을 글자에서 딴 이름으로 바꿀 때 쓰는 최대 글자 수.
const NAME_TEXT_CHARS: int = 24
## `editor_description` 머리말 — §3 규칙 5 의 `TODO:` 마킹과 섞이지 않게 따로 둔다.
const NOTE_PREFIX: String = "dump: "

## 마지막 `dump()` 의 보고서. 키: path, bytes, nodes, instances, scripted, scripts
## (스크립트 경로 → 개수), init_children_freed, renamed, embedded (클래스 → 개수),
## external, connections_dropped, persistent_dropped, props_dropped, skipped (Array[String]).
static var last_report: Dictionary = {}


## `res://_dump/<노드 이름>.tscn` — 자동 이름(`@Control@2`)이면 스크립트 class_name · 엔진 클래스.
static func default_path(node: Node) -> String:
	return DEFAULT_DIR + _root_name(node).validate_filename() + ".tscn"


## `live_root` 서브트리를 `out_path`(빈 문자열이면 `default_path`) 에 저장한다.
## opts:
##   keep_scripts      (true)  자손 노드의 스크립트 참조 유지(§3 규칙 3 — `_draw` 위젯은 노드로 배치)
##   keep_root_script  (false) 루트 스크립트 유지. 루트 스크립트는 보통 이 트리 전체를 코드로
##                             짓는 빌더라, 붙여 두면 초안을 실행할 때 화면이 두 겹이 된다
##   rename_auto       (true)  `@Class@123` 자동 이름 → `Class_글자` 같은 읽히는 이름
##   annotate          (true)  스크립트 노드 · 루트에 `editor_description = "dump: …"` 출처 메모
##   keep_meta         (false) `metadata/*` 유지. 런타임 표시(예: HapticUi 의 `haptic_bound`)라
##                             씬에 남으면 "이미 처리됨" 으로 읽혀 바인딩을 건너뛴다 — 기본은 버린다
static func dump(live_root: Node, out_path: String = "", opts: Dictionary = {}) -> Error:
	if live_root == null:
		return ERR_INVALID_PARAMETER
	var target: String = out_path if out_path != "" else default_path(live_root)
	var o: Dictionary = {
		"keep_scripts": true, "keep_root_script": false, "rename_auto": true, "annotate": true,
		"keep_meta": false,
	}
	o.merge(opts, true)
	var rep: Dictionary = {
		"path": target, "bytes": 0, "nodes": 0, "instances": 0, "scripted": 0, "scripts": {},
		"init_children_freed": 0, "renamed": 0, "embedded": {}, "external": 0,
		"connections_dropped": 0, "persistent_dropped": 0, "props_dropped": 0, "meta_dropped": 0,
		"draw_callbacks_lost": 0, "skipped": [],
	}
	last_report = rep
	var seen: Dictionary = {}

	var copy_root: Node = _make_copy(live_root, true, o, rep, seen)
	if copy_root == null:
		return ERR_CANT_CREATE
	copy_root.name = _root_name(live_root)
	if o["annotate"]:
		var src_scene: String = live_root.scene_file_path
		if src_scene == "" and live_root.owner != null:
			src_scene = live_root.owner.scene_file_path
		var note: String = NOTE_PREFIX + "%s (scene %s)" % [live_root.get_path(), src_scene]
		var scr: Script = live_root.get_script() as Script
		if scr != null and not o["keep_root_script"]:
			note += " — root script %s not attached (keep_root_script)" % scr.resource_path
		_add_note(copy_root, note)
	_mirror_children(live_root, copy_root, copy_root, false, o, rep, seen)

	var packed: PackedScene = PackedScene.new()
	var err: Error = packed.pack(copy_root)
	copy_root.free()
	if err != OK:
		push_error("UiSceneDump: pack failed (%s)" % error_string(err))
		return err
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	err = ResourceSaver.save(packed, target)
	if err != OK:
		push_error("UiSceneDump: save to %s failed (%s)" % [target, error_string(err)])
		return err
	var f: FileAccess = FileAccess.open(target, FileAccess.READ)
	if f != null:
		rep["bytes"] = f.get_length()
		f.close()
	return OK


## 보고서를 사람이 읽는 여러 줄 문자열로.
static func report_text(rep: Dictionary = last_report) -> String:
	var lines: PackedStringArray = []
	lines.append("UiSceneDump → %s (%d bytes)" % [rep.get("path", "?"), rep.get("bytes", 0)])
	lines.append("  nodes %d · scene instances %d · scripted %d · renamed %d" % [
		rep.get("nodes", 0), rep.get("instances", 0), rep.get("scripted", 0), rep.get("renamed", 0)])
	lines.append("  embedded sub_resources %s · external refs %d" % [
		str(rep.get("embedded", {})), rep.get("external", 0)])
	lines.append("  connections dropped %d (persistent %d) · props dropped %d · meta dropped %d · init children freed %d" % [
		rep.get("connections_dropped", 0), rep.get("persistent_dropped", 0),
		rep.get("props_dropped", 0), rep.get("meta_dropped", 0), rep.get("init_children_freed", 0)])
	lines.append("  draw callbacks lost %d (those nodes render empty — see their editor_description)"
			% rep.get("draw_callbacks_lost", 0))
	var scripts: Dictionary = rep.get("scripts", {})
	for p: String in scripts:
		lines.append("  script %s × %d" % [p, scripts[p]])
	for s: String in rep.get("skipped", []):
		lines.append("  skipped: " + s)
	return "\n".join(lines)


# ── 복사 ─────────────────────────────────────────────────────────────────────

# 라이브 노드 하나 → 저장용 새 노드. 하위 씬 인스턴스면 그 씬을 인스턴스한다.
static func _make_copy(live: Node, is_root: bool, o: Dictionary, rep: Dictionary,
		seen: Dictionary) -> Node:
	var cls: String = live.get_class()
	if not ClassDB.can_instantiate(cls):
		rep["skipped"].append("%s (%s not instantiable)" % [live.get_path(), cls])
		return null
	var copy: Node = null
	var scene_path: String = live.scene_file_path
	if not is_root and scene_path != "" and ResourceLoader.exists(scene_path):
		var ps: PackedScene = load(scene_path) as PackedScene
		if ps != null:
			# 에디터 빌드에선 인스턴스 상태를 남겨 `pack()` 이 씬과 다른 값만 저장하게 한다
			# (내보낸 템플릿엔 이 모드가 없다 — 그땐 모든 값이 오버라이드로 들어간다).
			var gen: int = PackedScene.GEN_EDIT_STATE_INSTANCE if OS.has_feature("editor") \
					else PackedScene.GEN_EDIT_STATE_DISABLED
			copy = ps.instantiate(gen)
			rep["instances"] += 1
	var note: String = ""
	if copy == null:
		copy = ClassDB.instantiate(cls) as Node
		var scr: Script = live.get_script() as Script
		if scr != null and o["keep_scripts"] and (not is_root or o["keep_root_script"]):
			copy.set_script(scr)
			rep["scripted"] += 1
			var scripts: Dictionary = rep["scripts"]
			scripts[scr.resource_path] = int(scripts.get(scr.resource_path, 0)) + 1
			# `_init` 에서 자기 자식을 짓는 스크립트(팝업 CanvasLayer 류) — 그 자식은 아래에서
			# 라이브 트리를 따라 다시 복사되므로 지금 것은 버린다(이름 충돌 · 이중 노드 방지).
			for c: Node in copy.get_children(true):
				copy.remove_child(c)
				c.free()
				rep["init_children_freed"] += 1
			if o["annotate"]:
				note = NOTE_PREFIX + "script " + scr.resource_path
	_copy_props(live, copy, o, rep, seen)
	if note != "":
		_add_note(copy, note)
	_count_connections(live, copy, o, rep)
	rep["nodes"] += 1
	return copy


# `skip_scene_owned`: `live` 가 하위 씬 인스턴스라 그 씬이 소유한 자식은 인스턴스가 이미 갖고
# 있다 — 런타임에 덧붙은 자식만 복사한다.
static func _mirror_children(live: Node, copy: Node, copy_root: Node, skip_scene_owned: bool,
		o: Dictionary, rep: Dictionary, seen: Dictionary) -> void:
	for child: Node in live.get_children():
		if skip_scene_owned and child.owner == live:
			continue
		var c: Node = _make_copy(child, false, o, rep, seen)
		if c == null:
			continue
		var child_name: String = String(child.name)
		if o["rename_auto"] and child_name.begins_with("@"):
			child_name = _readable_name(child)
			rep["renamed"] += 1
		c.name = child_name
		copy.add_child(c, true)
		c.owner = copy_root
		_mirror_children(child, c, copy_root, c.scene_file_path != "", o, rep, seen)


static func _copy_props(live: Node, copy: Node, o: Dictionary, rep: Dictionary,
		seen: Dictionary) -> void:
	for p: Dictionary in live.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var pname: String = p["name"]
		if pname == "script" or pname == "scene_file_path":
			continue
		if pname.begins_with("metadata/") and not o["keep_meta"]:
			rep["meta_dropped"] += 1
			continue
		var v: Variant = live.get(pname)
		if not _is_saveable(v):
			rep["props_dropped"] += 1
			continue
		if pname == "editor_description" and String(v) == "":
			continue
		copy.set(pname, v)
		_note_resources(v, rep, seen)


# 저장할 수 없는 값(Callable · Signal · RID · 리소스가 아닌 Object) 은 버린다 —
# 주로 `set_meta` 로 붙은 런타임 핸들.
static func _is_saveable(v: Variant) -> bool:
	match typeof(v):
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_OBJECT:
			return v == null or v is Resource
		TYPE_ARRAY:
			for e: Variant in v:
				if not _is_saveable(e):
					return false
		TYPE_DICTIONARY:
			for k: Variant in v:
				if not _is_saveable(k) or not _is_saveable(v[k]):
					return false
	return true


# 코드로 만든 리소스(경로 없음 / 다른 파일의 내장) = 초안에 sub_resource 로 박힌다 → 클래스별 개수.
static func _note_resources(v: Variant, rep: Dictionary, seen: Dictionary) -> void:
	if typeof(v) == TYPE_ARRAY:
		for e: Variant in v:
			_note_resources(e, rep, seen)
		return
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			_note_resources(v[k], rep, seen)
		return
	if typeof(v) != TYPE_OBJECT or not (v is Resource):
		return
	var res: Resource = v
	if seen.has(res):
		return
	seen[res] = true
	if res.resource_path != "" and not res.resource_path.contains("::"):
		rep["external"] += 1
		return
	var embedded: Dictionary = rep["embedded"]
	embedded[res.get_class()] = int(embedded.get(res.get_class(), 0)) + 1
	for p: Dictionary in res.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE != 0 and p["name"] != "script":
			_note_resources(res.get(p["name"]), rep, seen)


# 런타임 연결은 하나도 저장하지 않는다 — 새 노드에 연결을 복사하지 않으므로 `pack()` 이 볼
# 연결 자체가 없다(람다 · bind 는 원래도 CONNECT_PERSIST 가 아니라 저장 대상이 아니다).
# 몇 개를 잃었는지만 센다. 단 `draw` 연결은 **그림 자체**라(예: `OutgameTheme` 둥근 초상이
# 평범한 Control 의 `draw` 에 람다를 건다) 초안에선 빈 노드로 남는다 — 그 노드에 메모를 단다.
static func _count_connections(live: Node, copy: Node, o: Dictionary, rep: Dictionary) -> void:
	for sig: Dictionary in live.get_signal_list():
		for con: Dictionary in live.get_signal_connection_list(sig["name"]):
			rep["connections_dropped"] += 1
			if int(con["flags"]) & Object.CONNECT_PERSIST != 0:
				rep["persistent_dropped"] += 1
			if sig["name"] == &"draw":
				rep["draw_callbacks_lost"] += 1
				if o["annotate"]:
					var cb: Callable = con["callable"]
					_add_note(copy, NOTE_PREFIX + "drawn by a `draw` callback (%s) — not saved, "
							% str(cb) + "this node is empty in the draft; rebuild as a widget")


static func _readable_name(live: Node) -> String:
	var base: String = live.get_class()
	var scr: Script = live.get_script() as Script
	if scr != null and scr.get_global_name() != &"":
		base = String(scr.get_global_name())
	if "text" in live:
		var t: String = str(live.get("text")).strip_edges().replace("\n", " ") \
				.replace("'", "").replace("\"", "")
		if t != "":
			base += "_" + t.left(NAME_TEXT_CHARS)
	var out: String = base.validate_node_name().strip_edges()
	return out if out != "" else live.get_class()


static func _root_name(node: Node) -> String:
	if not String(node.name).begins_with("@"):
		return String(node.name)
	var scr: Script = node.get_script() as Script
	if scr != null and scr.get_global_name() != &"":
		return String(scr.get_global_name())
	return node.get_class()


static func _add_note(node: Node, note: String) -> void:
	if node.editor_description == "":
		node.editor_description = note
	else:
		node.editor_description += "\n" + note
