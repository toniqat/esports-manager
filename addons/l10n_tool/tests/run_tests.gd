extends SceneTree

# 헤드리스 테스트 러너:
#   godot --headless --path . --script res://addons/l10n_tool/tests/run_tests.gd [-- <파일 이름 필터>]
# tests/ 의 `test_*.gd`(extends RefCounted)마다 `test_` 로 시작하는 메서드를 하나씩
# 부르고 인자로 단언 도우미 `T` 를 넘긴다. fixture 는 tests/fixtures/<이름>/ (.gdignore
# 아래라 Godot 이 임포트하지 않는다) — 고치는 테스트는 `T.copy_fixture()` 로 임시
# 폴더(user://l10n_test/…)에 복사해서 쓴다.

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const TESTS_DIR := "res://addons/l10n_tool/tests"


func _initialize() -> void:
	var filt: String = ""
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filt = user_args[0]
	var files: Array = Array(DirAccess.get_files_at(TESTS_DIR))
	files.sort()
	var total: int = 0
	var failed: int = 0
	for fn in files:
		if not (fn.begins_with("test_") and fn.ends_with(".gd")) or fn == "test_kit.gd":
			continue
		if filt != "" and not fn.contains(filt):
			continue
		var script: GDScript = load(TESTS_DIR.path_join(fn))
		var inst: Object = script.new()
		for m in inst.get_method_list():
			var mn: String = m["name"]
			if not mn.begins_with("test_"):
				continue
			var t: TestKit = TestKit.new()
			t.label = "%s::%s" % [fn, mn]
			inst.call(mn, t)
			total += 1
			if t.failures.is_empty():
				print("  ok   ", t.label)
			else:
				failed += 1
				print("  FAIL ", t.label)
				for f in t.failures:
					print("         ", f)
	print("tests: %d, failed: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
