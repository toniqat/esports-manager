extends RefCounted

## scanner 테스트 — 사용처(§9.2) 줄 번호 · 고아 제외 규칙(D16) · E05x · W05x · E057 · fix (§15 5단계).
## fixture `scanner_basic/proj/` 의 줄 번호가 기대값이다 — fixture 를 고치면 여기도 고친다.

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Scanner = preload("res://addons/l10n_tool/core/scanner.gd")


func _open(t: TestKit) -> L10n:
	var dir: String = t.copy_fixture("scanner_basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	return l


func _rel(l: L10n, p: String) -> String:
	return p.trim_prefix(l.config.base_dir + "/")


# [{file, line, kind}] → ["file:line:kind", …] (base 기준 상대 경로)
func _usages(l: L10n, key: String) -> Array:
	var out: Array = []
	for u in l.index["keys"][key]["usages"]:
		out.append("%s:%d:%s" % [_rel(l, u["file"]), int(u["line"]), u["kind"]])
	return out


func _orphans(l: L10n, kind: String) -> Array:
	var out: Array = []
	for o in l.index["orphans"]:
		if o["kind"] == kind:
			out.append("%s:%d" % [_rel(l, o["file"]), int(o["line"])])
	return out


func _issue_lines(l: L10n, code: String) -> Array:
	var out: Array = []
	for it in l.issues.items:
		if it["code"] == code:
			out.append("%s:%d" % [_rel(l, it["file"]), int(it["line"])])
	return out


func test_usages_by_line(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	t.eq(_usages(l, "tx_H1J2K3M4N5"), ["proj/Main.gd:3:dynamic", "proj/Main.gd:4:const"], "l10n-keys + const")
	t.eq(_usages(l, "tx_J2K3M4N5P6"), ["proj/Main.gd:3:dynamic", "proj/Main.gd:5:const"])
	t.eq(_usages(l, "tx_D5MN0P1Q2R"), ["proj/Main.gd:30:literal", "proj/Main.gd:10:const"], "literal · const")
	t.eq(_usages(l, "tx_7KQ2M9XA4P"), ["proj/Main.gd:21:dynamic", "csv/cards.csv:2:data"], "dynamic * + data")
	t.eq(_usages(l, "tx_C4RT8NW2HJ"), ["proj/Main.gd:21:dynamic", "csv/cards.csv:3:data"])
	t.eq(_usages(l, "tx_B3PZ8RW1MC"), ["csv/cards.csv:2:data"], "data 만 (desc 는 패턴 밖)")
	t.eq(_usages(l, "tx_E6ST3V4W5X"), ["proj/debug/Cheat.gd:2:const"], "ignore_paths 도 사용처는 기록 · .gdignore · exclude_dirs 는 제외")
	t.eq(_usages(l, "tx_K3M4N5P6Q7"), ["proj/sub/Screen.tscn:6:literal"], "씬 literal")
	t.eq(_usages(l, "tx_F7YZ6A7B8C"), ["proj/Main.gd:11:literal"])


func test_orphans_and_exclusions(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	# 13~15 로그 · 17 주석 · 18 l10n-ignore · 23 NodePath · 24 StringName · 31 단독 """ ·
	# 36~40 l10n-ignore 함수 · 45 assert 는 빠진다. 46 = "…" 안의 실제 줄바꿈.
	var want: Array = []
	for n in [12, 16, 19, 25, 27, 28, 29, 32, 44, 46, 47]:
		want.append("proj/Main.gd:%d" % n)
	t.eq(_orphans(l, "orphan_code"), want, "orphan_code 줄")
	t.eq(_issue_lines(l, "W053"), want, "W053")
	var texts: Array = []
	for o in l.index["orphans"]:
		if o["kind"] == "orphan_code":
			texts.append(o["text"])
	t.eq(texts[2], "plain text", "tr 첫 인자 비-key 리터럴")
	t.eq(texts[3], "여러\n줄 한글", "여러 줄 문자열")
	t.eq(_orphans(l, "orphan_scene"), ["proj/sub/Res.tres:4", "proj/sub/Screen.tscn:12", "proj/sub/Screen.tscn:13", "proj/sub/Screen.tscn:20"], "orphan_scene 줄")
	t.eq(l.issues.count_code("W052"), 4)
	t.ok(not l.issues.has_code("E052") and not l.issues.has_code("E053"), "warn 모드")


func test_strict_orphans(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.config.strict_orphans = "error"
	l.cmd_scan(false)
	t.eq(l.issues.count_code("E053"), 11)
	t.eq(l.issues.count_code("E052"), 4)
	t.ok(not l.issues.has_code("W053"), "strict 면 W 없음")


func test_usage_rules(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	t.eq(_issue_lines(l, "E051"), ["proj/Main.gd:22"], "없는 상수 (주석 · 문자열 안은 제외)")
	t.eq(_issue_lines(l, "W054"), ["proj/Main.gd:20"], "주석 없는 동적 key (ignore_paths 제외)")
	t.eq(l.index["dynamic_bare"].size(), 1)
	t.eq(_issue_lines(l, "E055"), ["proj/Main.gd:11"], "deprecated 사용")
	var w056: Array = []
	for it in l.issues.items:
		if it["code"] == "W056":
			w056.append(it["key"])
	w056.sort()
	t.eq(w056, ["tx_G8HJ9K0M1N", "tx_M4N5P6Q7R8", "tx_N5P6Q7R8S9", "tx_P6Q7R8S9T0"], "미사용 active")


func test_index_shape(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	var k: Dictionary = l.index["keys"]
	t.eq(k.size(), 13, "모든 카탈로그 key")
	t.eq(k["tx_G8HJ9K0M1N"]["glossary"], ["confirm", "hand"], "용어집 (key 용어 · 언어 용어)")
	t.eq(k["tx_K3M4N5P6Q7"]["translations"]["en"]["text"], "Start Game")
	t.eq(k["tx_D5MN0P1Q2R"]["translations"]["en"]["stale"], false)
	t.eq(k["tx_K3M4N5P6Q7"]["translations"]["en"]["stale"], true, "해시 없음 → stale")
	t.eq(k["tx_D5MN0P1Q2R"]["source"], {"text": "확인", "hash": "468266d6"})
	t.ok(String(l.index["generated_at"]).ends_with("Z"), "UTC")
	t.eq(Scanner.write_index(l, l.index), "")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(l.config.gen_dir.path_join("index.json")))
	t.ok(typeof(parsed) == TYPE_DICTIONARY and (parsed["keys"] as Dictionary).size() == 13, "index.json 왕복")


func test_preview_leak_and_fix(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	t.eq(_orphans(l, "preview_leak"), ["proj/sub/Screen.tscn:9", "proj/sub/Screen.tscn:19"], "누수 (원문과 같은 Mech 는 제외)")
	t.eq(_issue_lines(l, "E057"), ["proj/sub/Screen.tscn:9", "proj/sub/Screen.tscn:19"])
	var p: String = l.config.base_dir.path_join("proj/sub/Screen.tscn")
	var before: PackedByteArray = TestKit.read_bytes(p)
	var n_issues: int = l.issues.items.size()
	t.eq(Scanner.fix_preview_leak(l), 1, "key 가 하나인 것만 고친다")
	t.eq(l.issues.items.size(), n_issues, "fix 는 issues 를 건드리지 않음")
	var want: String = before.get_string_from_utf8().replace("text = \"Start Game\"\r\n", "text = \"tx_K3M4N5P6Q7\"\r\n")
	t.eq(TestKit.read_bytes(p), want.to_utf8_buffer(), "그 줄만 바뀜 · CRLF 유지")
	l.cmd_scan(false)
	t.eq(_issue_lines(l, "E057"), ["proj/sub/Screen.tscn:19"], "고친 뒤 모호한 것만 남음")
	t.eq(_usages(l, "tx_K3M4N5P6Q7"), ["proj/sub/Screen.tscn:6:literal", "proj/sub/Screen.tscn:9:literal"])
	t.eq(Scanner.fix_preview_leak(l), 0, "두 번째는 없음")
