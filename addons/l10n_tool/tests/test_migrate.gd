extends RefCounted

## 이행 도구 테스트 — new_keys · write_l · extract scenes · extract code · 씬 auto_translate_mode 건너뛰기.
## fixture `migrate_basic`: src/ui.csv(ui.confirm · ui.greet), proj/ui/UI_View_Hud.tscn(LF, 상속 ·
## 자리표시 · 여러 줄 · 이스케이프 · 가짜 헤더 줄), proj/ui/Other.tscn(BOM + CRLF, Window title),
## proj/debug/Dbg.tscn(ignore_paths), proj/res/Info.tres, proj/Main.gd · proj/sub/Sub.gd(코드 고아).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Config = preload("res://addons/l10n_tool/core/config.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const Scanner = preload("res://addons/l10n_tool/core/scanner.gd")
const Extractor = preload("res://addons/l10n_tool/core/extractor.gd")

const FIXTURE := "migrate_basic"
const PANEL_SRC := "a \"인용\" back\\slash\n[node name=\"가짜\" parent=\".\"]\n[b]둘째 줄[/b] C:\\new"


func _open(t: TestKit) -> L10n:
	var dir: String = t.copy_fixture(FIXTURE)
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	return l


func _write_json(path: String, v: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v))
	f.close()


func _snapshot(dir: String) -> Dictionary:
	var out: Dictionary = {}
	for sub in ["src", "proj/ui", "proj/res", "proj/debug"]:
		var p: String = dir.path_join(sub)
		for fn in DirAccess.get_files_at(p):
			out[sub + "/" + fn] = TestKit.read_bytes(p.path_join(fn))
	return out


# ── new_keys ────────────────────────────────────────────────────────────

func test_new_keys_success(t: TestKit) -> void:
	var l: L10n = _open(t)
	var base: String = l.config.base_dir
	var ui_before: String = FileAccess.get_file_as_string(l.config.domain_path("ui"))
	var items: Array = [
		{"domain": "hud", "alias": "hud.title", "ko": "제목", "context": "HUD 제목", "max_len": 12, "en": "Title"},
		{"domain": "ui", "alias": "ui.greet", "ko": "안녕"},
		{"domain": "ui", "alias": "ui.new_one", "ko": "새, \"것\""},
		{"domain": "ui", "alias": "ui.new_one", "ko": "새, \"것\""},
	]
	_write_json(base.path_join("in.json"), items)
	var out_path: String = base.path_join("out/res.json")
	t.eq(l.cmd_new_keys(base.path_join("in.json"), out_path), "", "성공")
	var res: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	t.ok(typeof(res) == TYPE_ARRAY and (res as Array).size() == 4, "결과 json 4개")
	var st: Array = []
	for r in res:
		st.append(r["status"])
	t.eq(st, ["new", "reused", "new", "reused"], "상태 (원본 재사용 · 묶음 안 재사용)")
	t.eq(res[1]["key"], "tx_E6ST3V4W5X", "재사용 key")
	t.eq(res[2]["key"], res[3]["key"], "묶음 안 같은 alias = 같은 key")
	l.catalog.reload()
	var kh: String = l.catalog.key_of_alias("hud.title")
	var kn: String = l.catalog.key_of_alias("ui.new_one")
	t.eq(kh, String(res[0]["key"]))
	# 새 도메인 파일 = 표준 헤더 + 행, 번역은 draft + 해시
	t.eq(FileAccess.get_file_as_string(l.config.domain_path("hud")),
			"key,alias,status,context,max_len,note,ko,en,en_status,en_hash\n%s,hud.title,active,HUD 제목,12,,제목,Title,draft,%s\n" % [kh, Hasher.hash_text("제목")],
			"hud.csv 생성")
	t.eq(FileAccess.get_file_as_string(l.config.domain_path("ui")), ui_before + "%s,ui.new_one,active,,,,\"새, \"\"것\"\"\",,,\n" % kn, "ui.csv 끝에 한 행만")


func test_new_keys_atomic_failure(t: TestKit) -> void:
	var l: L10n = _open(t)
	var base: String = l.config.base_dir
	var before: Dictionary = _snapshot(base)
	var items: Array = [
		{"domain": "hud", "alias": "hud.ok", "ko": "정상"},
		{"domain": "ui", "alias": "ui.greet", "ko": "다른 원문"},
		{"domain": "ui", "alias": "Bad.alias", "ko": "x"},
		{"domain": "ui", "alias": "hud.wrong", "ko": "x"},
		{"domain": "ui", "alias": "ui.typo", "text": "x"},
		{"domain": "ui", "alias": "ui.empty", "ko": "  "},
	]
	_write_json(base.path_join("in.json"), items)
	var err: String = l.cmd_new_keys(base.path_join("in.json"))
	t.ok(err.contains("ui.greet") and err.contains("원문이 다름"), "원문이 다른 기존 alias: " + err)
	t.ok(err.contains("Bad.alias") and err.contains("hud.wrong"), "alias 형식 · 첫 세그먼트")
	t.ok(err.contains("알 수 없는 필드 'text'"), "알 수 없는 필드")
	t.ok(err.contains("ui.empty") and err.contains("비어"), "빈 원문")
	t.eq(_snapshot(base), before, "아무것도 바뀌지 않음")
	t.ok(not FileAccess.file_exists(l.config.domain_path("hud")), "새 도메인 파일도 만들지 않음")
	# L 상수 충돌 (ui.x.y_z ↔ ui.x_y.z → UI_X_Y_Z) · 예약 이름
	_write_json(base.path_join("in2.json"), [
		{"domain": "ui", "alias": "ui.x.y_z", "ko": "a"}, {"domain": "ui", "alias": "ui.x_y.z", "ko": "b"}])
	t.ok(l.cmd_new_keys(base.path_join("in2.json")).contains("L 상수 이름 충돌 UI_X_Y_Z"), "L 상수 충돌")
	t.eq(_snapshot(base), before, "충돌도 아무것도 바꾸지 않음")
	# Excel 잠금
	TestKit.write_bytes(base.path_join("src/~$ui.csv"), PackedByteArray([0]))
	_write_json(base.path_join("in3.json"), [{"domain": "ui", "alias": "ui.locked", "ko": "a"}])
	t.ok(l.cmd_new_keys(base.path_join("in3.json")).contains("Excel 잠금"), "Excel 잠금")
	t.eq(FileAccess.get_file_as_string(l.config.domain_path("ui")).contains("ui.locked"), false)


# ── write_l / write_strings ─────────────────────────────────────────────

func test_write_generated(t: TestKit) -> void:
	var l: L10n = _open(t)
	var gen: String = l.config.gen_dir
	t.eq(l.cmd_write_generated("l"), "", "write_l")
	var lgd: String = FileAccess.get_file_as_string(gen.path_join("L.gd"))
	t.ok(lgd.contains("const UI_CONFIRM := \"tx_D5MN0P1Q2R\"") and lgd.contains("const UI_GREET"), "L.gd 상수")
	t.ok(not FileAccess.file_exists(gen.path_join("strings_ko.csv")), "write_l 은 L.gd 만")
	t.eq(l.cmd_write_generated("strings"), "", "write_strings")
	t.eq(FileAccess.get_file_as_string(gen.path_join("strings_en.csv")), "keys,en\ntx_D5MN0P1Q2R,OK\ntx_E6ST3V4W5X,안녕\n", "dev strings")
	t.ok(not FileAccess.file_exists(gen.path_join("refs.json")), "refs.json 은 쓰지 않음")
	# 원본 읽기 오류면 거부 (상수가 빠진 L.gd 를 쓰지 않도록)
	TestKit.write_bytes(l.config.domain_path("broken"), "key,alias,status,ko,en,en_status,en_hash\n\"tx_A,b\n".to_utf8_buffer())
	t.ok(l.cmd_write_generated("l") != "", "읽기 오류 → 거부")
	t.eq(FileAccess.get_file_as_string(gen.path_join("L.gd")), lgd, "L.gd 그대로")


# ── 스캐너: parse_scene · auto_translate_mode ───────────────────────────

func test_parse_scene(t: TestKit) -> void:
	var l: L10n = _open(t)
	var vals: Array = l.parse_scene(FileAccess.get_file_as_string(l.config.base_dir.path_join("proj/ui/UI_View_Hud.tscn")))
	var rows: Array = []
	for v in vals:
		rows.append("%d %s %s %s" % [int(v["line"]), v["node_path"], v["prop"], "off" if v["disabled"] else "on"])
	t.eq(rows, ["11 Title text on", "20 Box/Label text off", "28 Box/Inner/Label text on", "35 Panel/Label text on",
			"41 Panel/Edit placeholder_text on", "42 Panel/Edit tooltip_text on", "45 Num text on", "48 Key text on",
			"51 Leak text on", "55 Fixed text off"], "값 · 노드 경로 · 상속된 auto_translate_mode (값 안의 가짜 헤더 줄 무시)")
	t.eq(vals[3]["value"], PANEL_SRC, "언이스케이프 (\\\\n 은 줄바꿈이 아님)")
	var tres: Array = l.parse_scene(FileAccess.get_file_as_string(l.config.base_dir.path_join("proj/res/Info.tres")))
	t.eq([tres[0]["section"], tres[0]["section_id"], tres[1]["section"]], ["sub_resource", "Resource_x1", "resource"], ".tres 섹션")
	t.eq(Scanner.unescape("a\\\\nb\\n\\\"c\\u00e9"), "a\\nb\n\"cé", "unescape")


func test_scanner_skips_translate_disabled(t: TestKit) -> void:
	var l: L10n = _open(t)
	l.cmd_scan(false)
	var hud: Array = []
	for o in l.index["orphans"]:
		if String(o["file"]).ends_with("UI_View_Hud.tscn"):
			hud.append("%s:%d:%s" % [o["kind"], int(o["line"]), o.get("node", "")])
	t.eq(hud, ["orphan_scene:11:Title", "orphan_scene:28:Box/Inner/Label", "orphan_scene:35:Panel/Label",
			"orphan_scene:41:Panel/Edit", "orphan_scene:42:Panel/Edit", "preview_leak:51:"],
			"auto_translate_mode = 2 (직접 · 상속) 는 W052 · E057 대상 아님, ALWAYS 로 되돌린 자식은 대상")
	var w052: int = 0
	for it in l.issues.items:
		if it["code"] == "W052" and String(it["file"]).ends_with("UI_View_Hud.tscn"):
			w052 += 1
	t.eq(w052, 5, "W052")


# ── extract scenes ──────────────────────────────────────────────────────

func test_extract_scenes(t: TestKit) -> void:
	var l: L10n = _open(t)
	var base: String = l.config.base_dir
	var hud_p: String = base.path_join("proj/ui/UI_View_Hud.tscn")
	var other_p: String = base.path_join("proj/ui/Other.tscn")
	var hud0: String = FileAccess.get_file_as_string(hud_p)
	var other0: PackedByteArray = TestKit.read_bytes(other_p)
	var before: Dictionary = _snapshot(base)
	# --dry: 계획만
	t.eq(l.cmd_extract(PackedStringArray(["scenes", "ui", base.path_join("proj/ui"), "--dry"])), "", "dry")
	t.eq(_snapshot(base), before, "dry 는 아무것도 안 바꿈")
	t.ok("\n".join(l.output).contains("ui.hud.panel_label"), "dry 계획 출력")
	# 실제
	t.eq(l.cmd_extract(PackedStringArray(["scenes", "ui", base.path_join("proj/ui"), base.path_join("proj/debug")])), "", "extract scenes")
	l.catalog.reload()
	var cat = l.catalog
	var want_alias: Dictionary = {
		"ui.hud.title": "제목", "ui.hud.label": "다시 번역", "ui.hud.panel_label": PANEL_SRC,
		"ui.hud.edit.placeholder_text": "입력", "ui.hud.edit.tooltip_text": "도움말",
		"ui.other.label": "다른 씬", "ui.other.win.title": "창 제목",
	}
	for a in want_alias.keys():
		t.eq(cat.source_text(cat.key_of_alias(a)), want_alias[a], "원문 " + a)
	t.eq(cat.entry(cat.key_of_alias("ui.hud.panel_label"))["context"], "UI_View_Hud.tscn Panel/Label text", "context")
	t.eq(cat.entry(cat.key_of_alias("ui.hud.edit.tooltip_text"))["tr"]["en"]["text"], "", "번역은 비움")
	t.eq(cat.all_entries.size(), 2 + 7, "신규 7개만 (자리표시 · 숫자 · key · 누수 · ignore_paths 제외)")
	# 씬 — 그 값 바이트만 바뀐다
	var hud_want: String = hud0
	for a in ["ui.hud.title", "ui.hud.label", "ui.hud.edit.placeholder_text", "ui.hud.edit.tooltip_text"]:
		hud_want = hud_want.replace("\"%s\"" % want_alias[a], "\"%s\"" % cat.key_of_alias(a))
	var ps: int = hud_want.find("text = \"a ") + 8
	var pe: int = hud_want.find("new\"", ps) + 3
	hud_want = hud_want.substr(0, ps) + cat.key_of_alias("ui.hud.panel_label") + hud_want.substr(pe)
	t.eq(FileAccess.get_file_as_string(hud_p), hud_want, "UI_View_Hud.tscn")
	var other_want: String = other0.slice(3).get_string_from_utf8() \
			.replace("\"다른 씬\"", "\"%s\"" % cat.key_of_alias("ui.other.label")) \
			.replace("\"창 제목\"", "\"%s\"" % cat.key_of_alias("ui.other.win.title"))
	var ob: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	ob.append_array(other_want.to_utf8_buffer())
	t.eq(TestKit.read_bytes(other_p), ob, "Other.tscn — BOM · CRLF 유지")
	t.ok(FileAccess.get_file_as_string(base.path_join("proj/debug/Dbg.tscn")).contains("\"디버그\""), "ignore_paths 는 그대로")
	t.ok(FileAccess.get_file_as_string(hud_p).contains("text = \"자리표시\"") and FileAccess.get_file_as_string(hud_p).contains("text = \"직접\""), "auto_translate_mode = 2 는 그대로")
	# 멱등 — 두 번째는 아무것도 안 바꿈
	var snap: Dictionary = _snapshot(base)
	t.eq(l.cmd_extract(PackedStringArray(["scenes", "ui", base.path_join("proj/ui")])), "", "두 번째")
	t.eq(_snapshot(base), snap, "두 번째 실행은 그대로")
	# 씬만 되돌린 뒤 다시 — 원문 · context 가 같은 alias 는 재사용, 원본은 그대로
	TestKit.write_bytes(hud_p, hud0.to_utf8_buffer())
	TestKit.write_bytes(other_p, other0)
	t.eq(l.cmd_extract(PackedStringArray(["scenes", "ui", base.path_join("proj/ui")])), "", "되돌린 뒤")
	t.eq(_snapshot(base), snap, "같은 key 로 다시 치환 · 새 행 없음")


func test_extract_scenes_alias_rules(t: TestKit) -> void:
	t.eq(Extractor.scene_alias_parts("UI_View_BattleHud.tscn"), "battle_hud")
	t.eq(Extractor.scene_alias_parts("UI_Comp_PilotRow.tscn"), "pilot_row")
	t.eq(Extractor.scene_alias_parts("Lobby.tscn"), "lobby")
	t.eq(Extractor.alias_segment("BanPickPortrait_Pilot0", "x"), "ban_pick_portrait_pilot_0")
	t.eq(Extractor.alias_segment("HPLabel", "x"), "hp_label")
	t.eq(Extractor.alias_segment("탭", "node"), "node", "글자가 하나도 남지 않으면 fallback")
	var l: L10n = _open(t)
	t.ok(l.cmd_extract(PackedStringArray(["scenes", "Bad", l.config.base_dir.path_join("proj/ui")])).contains("domain"), "domain 형식")


# ── extract code ────────────────────────────────────────────────────────

func test_extract_code(t: TestKit) -> void:
	var l: L10n = _open(t)
	var base: String = l.config.base_dir
	var before: Dictionary = _snapshot(base)
	t.eq(l.cmd_extract(PackedStringArray(["code"])), "", "전체")
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(l.config.gen_dir.path_join("extract_code.json")))
	t.eq(int(all["total"]), 3)
	var got: Array = []
	for f in all["files"]:
		for it in f["items"]:
			got.append("%s:%d:%s" % [String(f["file"]).trim_prefix(base + "/"), int(it["line"]), it["text"]])
	t.eq(got, ["proj/Main.gd:4:한글 하나", "proj/Main.gd:6:plain", "proj/sub/Sub.gd:2:하위 폴더"], "scanner 와 같은 판정")
	var out_p: String = base.path_join("generated/extract_code_sub.json")
	t.eq(l.cmd_extract(PackedStringArray(["code", base.path_join("proj/sub"), "--out=" + out_p])), "", "경로 · --out")
	var sub: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out_p))
	t.eq([int(sub["total"]), (sub["files"] as Array).size()], [1, 1], "proj/sub 만")
	t.eq(_snapshot(base), before, "원본 · 코드는 그대로")
