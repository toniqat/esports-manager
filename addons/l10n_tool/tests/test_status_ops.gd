extends RefCounted

## status_ops 테스트 — sync · approve · add_locale · rename_alias (§7.1 · §8 · §3.2).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const StatusOps = preload("res://addons/l10n_tool/core/status_ops.gd")


func _open(t: TestKit, fixture: String = "status_basic") -> L10n:
	var dir: String = t.copy_fixture(fixture)
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	return l


func _tr(l: L10n, key: String) -> Dictionary:
	return l.catalog.entry(key)["tr"]["en"]


func test_sync(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(StatusOps.sync(l), 2, "해시 빈 번역 2개 (approved 수동 승인은 제외)")
	l.catalog.reload()
	t.eq(_tr(l, "tx_E6ST3V4W5X"), {"text": "{name} arrived", "status": "draft", "hash": Hasher.hash_text("{name}{i} 왔다")}, "빈 status → draft")
	t.eq(_tr(l, "tx_M4NP5Q6R7S")["status"], "draft", "draft 유지")
	t.eq(_tr(l, "tx_M4NP5Q6R7S")["hash"], Hasher.hash_text("초안"))
	t.eq(_tr(l, "tx_K2LM3N4P5Q"), {"text": "Manual", "status": "approved", "hash": ""}, "수동 approved 는 그대로(E031)")
	t.eq(_tr(l, "tx_F7YZ6A7B8C")["status"], "", "미번역은 그대로")
	t.eq(StatusOps.sync(l), 0, "다시 돌리면 0")


func test_approve(t: TestKit) -> void:
	var l: L10n = _open(t)
	var p: String = l.config.domain_path("ui")
	var before: PackedByteArray = TestKit.read_bytes(p)
	t.ok(StatusOps.approve(l, "en", PackedStringArray(["ui.greet", "ui.todo"])) != "", "빈 번역 → 오류")
	t.ok(StatusOps.approve(l, "en", PackedStringArray(["ui.nope"])) != "", "없는 alias → 오류")
	t.ok(StatusOps.approve(l, "ko", PackedStringArray(["ui.greet"])) != "", "원문 로케일 → 오류")
	t.eq(TestKit.read_bytes(p), before, "오류면 아무것도 바꾸지 않는다")
	t.eq(StatusOps.approve(l, "en", PackedStringArray(["ui.greet", "tx_M4NP5Q6R7S"])), "")
	l.catalog.reload()
	t.eq(_tr(l, "tx_E6ST3V4W5X")["status"], "approved")
	t.eq(_tr(l, "tx_E6ST3V4W5X")["hash"], Hasher.hash_text("{name}{i} 왔다"))
	t.eq(_tr(l, "tx_M4NP5Q6R7S")["status"], "approved", "key 로도")
	t.ok(not l.catalog.is_stale("tx_M4NP5Q6R7S", "en"))
	# 원문이 바뀐 stale 번역 → approve 로 해시만 갱신
	l.catalog.set_field("tx_D5MN0P1Q2R", "ko", "확인함")
	l.catalog.save_all()
	t.ok(l.catalog.is_stale("tx_D5MN0P1Q2R", "en"), "stale")
	t.eq(StatusOps.approve(l, "en", PackedStringArray(["ui.confirm"])), "")
	t.ok(not l.catalog.is_stale("tx_D5MN0P1Q2R", "en"), "stale 해소")


func test_add_locale(t: TestKit) -> void:
	var l: L10n = _open(t, "basic")
	var p: String = l.config.domain_path("card")
	var before: String = TestKit.read_bytes(p).slice(3).get_string_from_utf8()
	t.ok(StatusOps.add_locale(l, "en") != "", "이미 있는 로케일 거부")
	t.ok(StatusOps.add_locale(l, "Bad!") != "", "형식 위반 거부")
	t.eq(StatusOps.add_locale(l, "ja"), "")
	var raw: PackedByteArray = TestKit.read_bytes(p)
	t.eq(raw.slice(0, 3), PackedByteArray([0xEF, 0xBB, 0xBF]), "BOM 유지")
	var lines_b: PackedStringArray = before.split("\r\n")
	var lines_a: PackedStringArray = raw.slice(3).get_string_from_utf8().split("\r\n")
	t.eq(lines_a.size(), lines_b.size(), "CRLF · 줄 수 유지")
	t.eq(lines_a[0], lines_b[0] + ",ja,ja_status,ja_hash", "컬럼은 끝에")
	for i in range(1, lines_b.size()):
		if lines_b[i] != "":
			t.eq(lines_a[i], lines_b[i] + ",,,", "다른 셀 그대로 (%d행)" % i)
	t.eq(l.config.locales, PackedStringArray(["ko", "en", "ja"]))
	var cfg_text: String = FileAccess.get_file_as_string(l.config.path)
	t.ok(cfg_text.contains("\"ja\""), "config.json 저장")
	t.ok(cfg_text.contains("data_csv_dir"), "모르는 키 보존")
	t.eq(l.catalog.load_issues.items.size(), 0, "다시 읽어도 E003 없음: " + str(l.catalog.load_issues.items))
	var ui: CsvIo = CsvIo.load_file(l.config.domain_path("ui"))
	t.eq(ui.headers, l.config.domain_header(), "모든 도메인 파일")


func test_add_locale_excel_lock(t: TestKit) -> void:
	var l: L10n = _open(t)
	TestKit.write_bytes(l.config.src_dir.path_join("~$ui.csv"), PackedByteArray([0]))
	t.ok(StatusOps.add_locale(l, "ja") != "", "Excel 잠금 → 거부")
	t.eq(l.config.locales, PackedStringArray(["ko", "en"]), "config 그대로")


func test_rename_alias(t: TestKit) -> void:
	var l: L10n = _open(t)
	var base: String = l.config.base_dir
	t.ok(StatusOps.rename_alias(l, "ui.confirm", "ui.greet") != "", "이미 있는 alias")
	t.ok(StatusOps.rename_alias(l, "ui.confirm", "card.ok") != "", "다른 도메인")
	t.ok(StatusOps.rename_alias(l, "ui.confirm", "ui.data.9.name") != "", "데이터 alias 로")
	t.ok(StatusOps.rename_alias(l, "ui.data.3.name", "ui.data_name") != "", "데이터 alias 는 못 바꾼다")
	t.ok(StatusOps.rename_alias(l, "ui.nope", "ui.x") != "", "없는 alias")
	t.eq(StatusOps.rename_alias(l, "ui.confirm", "ui.ok_button"), "")
	t.eq(l.catalog.key_of_alias("ui.ok_button"), "tx_D5MN0P1Q2R", "key 유지")
	t.eq(l.catalog.key_of_alias("ui.confirm"), "")
	t.eq(l.catalog.text("tx_D5MN0P1Q2R", "en"), "OK", "번역 유지")
	t.eq(FileAccess.get_file_as_string(base.path_join("proj/Code.gd")), "extends Node\n\n\nfunc _ready() -> void:\n"
		+ "\tvar a := Loc.t(L.UI_OK_BUTTON)\n"
		+ "\tvar b := Loc.t(L.UI_CONFIRM_EXTRA)\n"
		+ "\tvar c := XL.UI_CONFIRM\n"
		+ "\tprint(a, b, c, L.UI_OK_BUTTON)\n", "단어 단위 치환")
	t.eq(FileAccess.get_file_as_string(base.path_join("proj/skip/Skip.gd")), "extends Node\n\nvar x := L.UI_CONFIRM\n", "exclude_dirs 는 건드리지 않는다")
	var lgd: String = FileAccess.get_file_as_string(l.config.gen_dir.path_join("L.gd"))
	t.ok(lgd.contains("const UI_OK_BUTTON := \"tx_D5MN0P1Q2R\""), "L.gd 재생성")
	t.ok(not lgd.contains("UI_CONFIRM"), "옛 상수 없음")
	t.ok(not lgd.contains("UI_DATA_3_NAME"), "데이터 alias 상수 없음")
	t.ok(not FileAccess.file_exists(l.config.gen_dir.path_join("strings_ko.csv")), "L.gd 만 쓴다")
