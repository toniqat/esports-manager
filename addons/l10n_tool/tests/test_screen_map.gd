extends RefCounted

## sheet/screen_map.gd — usage file → game screen (fixture: tests/fixtures/screen_map_basic).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const ScreenMap = preload("res://addons/l10n_tool/sheet/screen_map.gd")


func _map(t: TestKit) -> RefCounted:
	return ScreenMap.build("res://scenes/Main.tscn", t.copy_fixture("screen_map_basic"))


func _names(hits: Array) -> Array:
	return hits.map(func(h: Dictionary) -> String: return h["screen"])


func test_screens_detected(t: TestKit) -> void:
	var m: RefCounted = _map(t)
	var screens: Array = (m.get("screens") as Dictionary).keys()
	screens.sort()
	t.eq(screens, ["res://scenes/Battle.tscn", "res://scenes/Main.tscn"], "main + change_scene target; preloaded Card.tscn is not a screen")


func test_screens_of(t: TestKit) -> void:
	var m: RefCounted = _map(t)
	var viewer: Array = m.call("screens_of", "res://battle/Viewer.gd")
	t.eq(_names(viewer), ["Battle"], "class_name use → Battle")
	t.eq(viewer[0]["chain"], PackedStringArray(["res://scenes/Battle.tscn", "res://battle/Battle.gd", "res://battle/Viewer.gd"]))
	var hud: Array = m.call("screens_of", "res://battle/Hud.gd")
	t.eq(hud[0]["chain"], PackedStringArray(["res://scenes/Battle.tscn", "res://battle/UI_View_Hud.tscn", "res://battle/Hud.gd"]), "script → scene → instanced in screen")
	t.eq(_names(m.call("screens_of", "res://cards/CardFace.gd")), ["Battle"], "via preloaded component scene")
	t.eq(_names(m.call("screens_of", "res://ui/Main.gd")), ["Main"])
	t.eq(_names(m.call("screens_of", "res://lobby/Lonely.gd")), [], "unused → no screen")
	# A scene built by its own script's create() → whoever calls the class.
	var popup: Array = m.call("screens_of", "res://battle/UI_View_Popup.tscn")
	t.eq(_names(popup), ["Battle"], "create() caller; not Main through the shared Theme library")
	t.eq(_names(m.call("screens_of", "res://lib/Theme.gd")), ["Main"], "a library as the start still climbs")
	t.eq(popup[0]["chain"], PackedStringArray(["res://scenes/Battle.tscn", "res://battle/Battle.gd", "res://battle/UI_View_Popup.tscn"]))
	t.eq(_names(m.call("screens_of", "res://battle/Popup.gd")), ["Battle"], "scene script → its scene → caller")


func test_scene_script_stays_in_its_scene(t: TestKit) -> void:
	var m: RefCounted = _map(t)
	# Main.gd type-hints BattleScreen (Battle.gd, attached to the Battle screen) — Viewer must
	# not leak into Main through it.
	t.ok((m.get("users") as Dictionary).get("res://battle/Battle.gd", []).has("res://ui/Main.gd"), "the type hint is an edge")
	t.eq(_names(m.call("screens_of", "res://battle/Viewer.gd")), ["Battle"], "but the walk stays in Battle")


func test_no_false_edges(t: TestKit) -> void:
	var m: RefCounted = _map(t)
	var users: Dictionary = m.get("users")
	t.eq(users.get("res://battle/Viewer.gd", []), ["res://battle/Battle.gd"], "comment mention and .gdignore folder are not users")
	t.eq(users.get("res://battle/Hud.gd", []), ["res://battle/UI_View_Hud.tscn"], "class name in a comment / string is not a use")
	t.ok(not (users.get("res://scenes/Battle.tscn", []) as Array).has("res://ui/Main.gd"), "change_scene is navigation, not an edge")


func test_node_path_at(t: TestKit) -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string(t.copy_fixture("screen_map_basic").path_join("battle/UI_View_Hud.tscn")).split("\n")
	t.eq(ScreenMap.node_path_at(lines, 6), "Hud", "root node")
	t.eq(ScreenMap.node_path_at(lines, 9), "Title", "child of root")
	t.eq(ScreenMap.node_path_at(lines, 12), "Box/Inner", "nested")
	t.eq(ScreenMap.node_path_at(lines, 2), "", "before any node")
