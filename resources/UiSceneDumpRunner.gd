extends SceneTree

## CLI 러너 — 씬을 띄우고 N 프레임 기다린 뒤 서브트리를 `UiSceneDump` 로 저장하고 끝낸다.
## 게임 코드 · project.godot 를 건드리지 않고 아무 화면이나 덤프하려고 `--script` 메인 루프로 둔다.
##
##   <godot> --path . --script res://resources/UiSceneDumpRunner.gd -- \
##       --scene res://scenes/Season.tscn --node HubView [--frames 30] \
##       [--out res://_dump/UI_View_HubView.tscn] [--shot C:/tmp/live.png] [--press "경기 시작|…"] \
##       [--keep-root-script] [--no-scripts]
##
## --press : 보이는 Button 을 글자로 찾아 `pressed` 를 쏜다(`|` 로 여러 개, 하나마다 다시 N 프레임
##           대기) — 버튼 한 번 뒤에 있는 화면(MatchFlow PREP → BAN_PICK)까지 가는 용도.
## --node  : `.` = 씬 루트, `/` 가 들어 있으면 씬 루트 기준 경로, 아니면 이름 · 스크립트
##           class_name · 엔진 클래스가 같은 첫 노드(너비 우선). 생략하면 덤프하지 않는다
##           (`--shot` 만 — 덤프한 초안을 `--scene res://_dump/X.tscn` 로 띄워 찍을 때).
## --shot  : 루트 뷰포트 스크린샷 PNG (창 모드에서만 — `--headless` 는 빈 그림).
## 자세한 설명 · 한계: `resources/README.md` "UiSceneDump".

const DEFAULT_FRAMES: int = 30

var _opts: Dictionary = {}
var _frames_left: int = DEFAULT_FRAMES
var _exit_code: int = 0
var _done: bool = false
var _presses: Array[String] = []


func _initialize() -> void:
	_opts = _parse_args(OS.get_cmdline_user_args())
	var scene_path: String = str(_opts.get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("UiSceneDumpRunner: --scene <res://….tscn> is required (got '%s')" % scene_path)
		_frames_left = 0
		_exit_code = 1
		return
	_frames_left = int(_opts.get("frames", DEFAULT_FRAMES))
	if _opts.has("press"):
		for s: String in str(_opts["press"]).split("|", false):
			_presses.append(s)
	change_scene_to_file(scene_path)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if _frames_left > 0:
		_frames_left -= 1
		return false
	# `--press "A|B"` — 버튼을 글자로 찾아 하나씩 누르고, 누를 때마다 다시 N 프레임 기다린다.
	if _exit_code == 0 and not _presses.is_empty():
		var label: String = _presses.pop_front()
		var btn: BaseButton = _find_button(get_root(), label)
		if btn == null:
			push_error("UiSceneDumpRunner: --press button '%s' not found" % label)
			_exit_code = 1
		else:
			print("UiSceneDumpRunner: press '%s' (%s)" % [label, btn.get_path()])
			btn.pressed.emit()
			_frames_left = int(_opts.get("frames", DEFAULT_FRAMES))
			return false
	if _exit_code == 0:
		_exit_code = _run()
	_done = true
	quit(_exit_code)
	return true


func _run() -> int:
	var scene_root: Node = current_scene
	if scene_root == null:
		push_error("UiSceneDumpRunner: scene did not load")
		return 1
	var shot: String = str(_opts.get("shot", ""))
	if shot != "":
		var img: Image = get_root().get_texture().get_image()
		if img == null or img.save_png(shot) != OK:
			push_error("UiSceneDumpRunner: screenshot to %s failed" % shot)
		else:
			print("UiSceneDumpRunner: screenshot → %s (%dx%d)" % [shot, img.get_width(), img.get_height()])
	var query: String = str(_opts.get("node", ""))
	if query == "":
		return 0
	var target: Node = _find(scene_root, query)
	if target == null:
		push_error("UiSceneDumpRunner: node '%s' not found under %s" % [query, scene_root.get_path()])
		_print_tree_hint(scene_root)
		return 1
	var dump_opts: Dictionary = {
		"keep_root_script": _opts.has("keep-root-script"),
		"keep_scripts": not _opts.has("no-scripts"),
	}
	var err: Error = UiSceneDump.dump(target, str(_opts.get("out", "")), dump_opts)
	if err != OK:
		push_error("UiSceneDumpRunner: dump failed (%s)" % error_string(err))
		return 1
	print(UiSceneDump.report_text())
	return 0


static func _find(scene_root: Node, query: String) -> Node:
	if query == ".":
		return scene_root
	if query.contains("/"):
		return scene_root.get_node_or_null(NodePath(query))
	var queue: Array[Node] = [scene_root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		var scr: Script = n.get_script() as Script
		if String(n.name) == query or n.get_class() == query \
				or (scr != null and String(scr.get_global_name()) == query):
			return n
		queue.append_array(n.get_children())
	return null


# 보이는 버튼 중 글자가 같은 첫 것(앞뒤 공백 무시).
static func _find_button(from: Node, label: String) -> BaseButton:
	var queue: Array[Node] = [from]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Button and (n as Button).is_visible_in_tree() \
				and (n as Button).text.strip_edges() == label.strip_edges():
			return n as BaseButton
		queue.append_array(n.get_children())
	return null


static func _print_tree_hint(scene_root: Node) -> void:
	print("UiSceneDumpRunner: children of the scene root:")
	for c: Node in scene_root.get_children():
		var scr: Script = c.get_script() as Script
		print("  %s (%s%s)" % [c.name, c.get_class(),
				"" if scr == null else ", " + scr.resource_path])


# `--key value` / `--flag` → Dictionary.
static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--"):
			var key: String = a.substr(2)
			if key.contains("="):
				out[key.get_slice("=", 0)] = key.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out
