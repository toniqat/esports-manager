extends RefCounted

## core 계약 테스트 — csv_io · keygen · hasher · tokens · catalog · refs (§15 1단계).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const Tokens = preload("res://addons/l10n_tool/core/tokens.gd")
const Config = preload("res://addons/l10n_tool/core/config.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Refs = preload("res://addons/l10n_tool/core/refs.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")


func test_csv_roundtrip_preserves_bytes(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var p: String = dir.path_join("src/card.csv")
	var before: PackedByteArray = TestKit.read_bytes(p)
	var tab: CsvIo = CsvIo.load_file(p)
	t.ok(tab.ok(), "parse ok")
	t.ok(tab.bom, "BOM 감지")
	t.eq(tab.eol, "\r\n", "CRLF 감지")
	t.eq(tab.row_count(), 3)
	t.eq(tab.get_cell(1, "ko"), "공격. 명중 시 +{p1}, [캐시] 찾기", "따옴표 셀")
	t.eq(tab.row_lines[2], 4, "줄 번호")
	# 강제로 dirty 를 만들지 않고 저장 → 바이트 동일
	tab.save()
	t.eq(TestKit.read_bytes(p), before, "변경 없음 → 파일 그대로")
	# 셀 하나만 바꾸면 그 줄만 바뀐다
	tab.set_cell(2, "en_status", "approved")
	t.eq(tab.save(), "")
	var after: String = TestKit.read_bytes(p).slice(3).get_string_from_utf8()
	var lines_before: PackedStringArray = before.slice(3).get_string_from_utf8().split("\r\n")
	var lines_after: PackedStringArray = after.split("\r\n")
	t.eq(lines_after.size(), lines_before.size(), "줄 수 유지")
	t.eq(lines_after[2], lines_before[2], "따옴표 행 원문 유지")
	t.eq(lines_after[3], "tx_C4RT8NW2HJ,card.pilot.7.name,active,카드 이름,,,캐시,Cache,approved,", "바뀐 행")
	t.eq(TestKit.read_bytes(p).slice(0, 3), PackedByteArray([0xEF, 0xBB, 0xBF]), "BOM 유지")


func test_csv_lf_append_and_quote(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var p: String = dir.path_join("src/ui.csv")
	var tab: CsvIo = CsvIo.load_file(p)
	t.ok(not tab.bom and tab.eol == "\n", "LF · BOM 없음")
	tab.append_row({"key": "tx_0000000000", "alias": "ui.x", "status": "active", "ko": "a,\"b\""})
	tab.save()
	var s: String = FileAccess.get_file_as_string(p)
	t.ok(s.ends_with("tx_0000000000,ui.x,active,,,,\"a,\"\"b\"\"\",,,\n"), "끝에 추가 · 따옴표 이스케이프: " + s.right(60))
	t.ok(not s.contains("\r"), "LF 유지")
	var again: CsvIo = CsvIo.load_file(p)
	t.eq(again.get_cell(3, "ko"), "a,\"b\"", "다시 읽기")


func test_csv_errors(t: TestKit) -> void:
	var p: String = TestKit.TMP_ROOT.path_join("bad_%d.csv" % Time.get_ticks_usec())
	TestKit.write_bytes(p, "a,b\n1,\"x\n".to_utf8_buffer())
	var tab: CsvIo = CsvIo.load_file(p)
	t.ok(not tab.ok() and tab.errors[0]["code"] == "E001", "닫히지 않은 따옴표 → E001")
	TestKit.write_bytes(p, PackedByteArray([0x61, 0x2C, 0x62, 0x0A, 0xB0, 0xA1, 0x0A]))   # CP949 '가'
	tab = CsvIo.load_file(p)
	t.ok(not tab.ok() and tab.errors[0]["code"] == "E002", "비 UTF-8 → E002")


func test_csv_add_rename_remove_column(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var p: String = dir.path_join("csv/cards.csv")
	var tab: CsvIo = CsvIo.load_file(p)
	tab.add_column("ja", "")
	tab.rename_column("cost", "cost2")
	tab.remove_column("description_key")
	tab.save()
	t.eq(FileAccess.get_file_as_string(p), "id,name_key,cost2,ja\r\n6,tx_7KQ2M9XA4P,1,\r\n7,tx_C4RT8NW2HJ,0,\r\n")


func test_keygen_10k_unique(t: TestKit) -> void:
	var seen: Dictionary = {}
	for i in 10000:
		var k: String = Keygen.generate("tx_", seen)
		t.ok(Keygen.is_valid(k, "tx_"), "형식: " + k)
		seen[k] = true
	t.eq(seen.size(), 10000, "1만 개 중복 0")
	t.ok(not Keygen.is_valid("tx_7KQ2M9XA4I", "tx_"), "I 금지")
	t.ok(not Keygen.is_valid("tx_7KQ2M9XA4", "tx_"), "9자 금지")


func test_hasher(t: TestKit) -> void:
	t.eq(Hasher.hash_text("a\r\nb"), Hasher.hash_text("a\nb"), "CRLF 정규화")
	t.ok(Hasher.hash_text(" a") != Hasher.hash_text("a"), "공백 유지")
	t.eq(Hasher.hash_text("확인").length(), 8)


func test_tokens(t: TestKit) -> void:
	var josa: Array = ["eul", "eun", "i", "wa"]
	var bb: Array = ["b", "color"]
	t.eq(Tokens.placeholders("{name}{i} {p1} {name}", josa), PackedStringArray(["name", "p1"]))
	t.eq(Tokens.josa("{name}{i} [카드]{eul}", josa), PackedStringArray(["i", "eul"]))
	t.eq(Tokens.refs("[b]굵게[/b] [로켓 펀치]{eul} [color=red]x[/color] [캐시]", bb), PackedStringArray(["로켓 펀치", "캐시"]))
	t.eq(Tokens.bbcode("[b]x[/b][color=red]y[/color]", bb), PackedStringArray(["b", "/b", "color", "/color"]))
	t.ok(Tokens.has_decomposed_jamo("가"), "자모")
	t.ok(not Tokens.has_decomposed_jamo("가"), "음절")


func test_catalog_load_and_new_key(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	t.eq(l.catalog.load_issues.items.size(), 0, "읽기 오류 없음")
	t.eq(l.catalog.domains(), PackedStringArray(["card", "keyword", "ui"]))
	t.eq(l.catalog.text("tx_7KQ2M9XA4P", "en"), "Rocket Punch")
	t.eq(l.catalog.key_of_alias("ui.confirm"), "tx_D5MN0P1Q2R")
	t.ok(not l.catalog.is_stale("tx_D5MN0P1Q2R", "en"), "approved 해시 일치")
	var res: Dictionary = l.cmd_new_key("lobby", "lobby.start_button", "새 시즌", "로비 시작 버튼")
	t.eq(res["error"], "")
	var tab: CsvIo = CsvIo.load_file(dir.path_join("src/lobby.csv"))
	t.eq(tab.headers, l.config.domain_header(), "새 도메인 파일 헤더")
	t.eq(tab.get_cell(0, "ko"), "새 시즌")
	t.eq(l.cmd_new_key("lobby", "lobby.start_button", "x")["error"] != "", true, "alias 중복 거부")
	t.eq(l.cmd_new_key("lobby", "ui.bad", "x")["error"] != "", true, "첫 세그먼트 ≠ domain 거부")
	# set_translation → draft + 해시
	t.eq(l.catalog.set_translation(res["key"], "en", "New Season"), "")
	t.eq(l.catalog.save_all(), "")
	l.catalog.reload()
	var e: Dictionary = l.catalog.entry(res["key"])
	t.eq(e["tr"]["en"]["status"], "draft")
	t.eq(e["tr"]["en"]["hash"], Hasher.hash_text("새 시즌"))


func test_cmd_edit(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	var name_key: String = "tx_7KQ2M9XA4P"
	# translation edit → draft + current source hash, other rows untouched
	t.eq(l.cmd_edit([{"key": name_key, "column": "en", "value": "Rocket Fist"}]), "")
	var e: Dictionary = l.catalog.entry(name_key)
	t.eq(e["tr"]["en"]["text"], "Rocket Fist")
	t.eq(e["tr"]["en"]["status"], "draft", "approved → draft")
	t.eq(e["tr"]["en"]["hash"], Hasher.hash_text("로켓 펀치"))
	t.eq(l.catalog.text("tx_C4RT8NW2HJ", "en"), "Cache", "다른 행 그대로")
	# source edit → translation goes stale; meta columns
	t.eq(l.cmd_edit([{"key": name_key, "column": "ko", "value": "로켓 주먹"},
		{"key": name_key, "column": "note", "value": "a,b"}, {"key": name_key, "column": "max_len", "value": "12"}]), "")
	t.ok(l.catalog.is_stale(name_key, "en"), "원문 수정 → stale")
	var tab: CsvIo = CsvIo.load_file(dir.path_join("src/card.csv"))
	t.eq(tab.get_cell(0, "ko"), "로켓 주먹", "디스크에 저장")
	t.eq(tab.get_cell(0, "note"), "a,b")
	t.eq(tab.get_cell(0, "max_len"), "12")
	# cleared translation clears status · hash
	t.eq(l.cmd_edit([{"key": "tx_C4RT8NW2HJ", "column": "en", "value": ""}]), "")
	t.eq(l.catalog.entry("tx_C4RT8NW2HJ")["tr"]["en"], {"text": "", "status": "", "hash": ""})
	# any bad edit → nothing written
	var before: PackedByteArray = TestKit.read_bytes(dir.path_join("src/card.csv"))
	t.ok(l.cmd_edit([{"key": name_key, "column": "en", "value": "X"}, {"key": name_key, "column": "alias", "value": "card.x"}]) != "", "alias 편집 거부")
	t.ok(l.cmd_edit([{"key": name_key, "column": "max_len", "value": "abc"}]) != "", "max_len 정수 아님 거부")
	t.ok(l.cmd_edit([{"key": "tx_NOPE000000", "column": "en", "value": "X"}]) != "", "없는 key 거부")
	t.eq(TestKit.read_bytes(dir.path_join("src/card.csv")), before, "거부 → 파일 그대로")
	# edits made on disk after open are kept (reload before write)
	var ext: CsvIo = CsvIo.load_file(dir.path_join("src/card.csv"))
	ext.set_cell(2, "context", "외부 수정")
	ext.save()
	t.eq(l.cmd_edit([{"key": name_key, "column": "en", "value": "Rocket"}]), "")
	t.eq(CsvIo.load_file(dir.path_join("src/card.csv")).get_cell(2, "context"), "외부 수정", "외부 수정 보존")


func test_refs_resolve(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	var iss: Issues = Issues.new()
	var refs: Dictionary = l.resolve_refs(iss)
	t.eq(refs, {"tx_B3PZ8RW1MC": ["tx_C4RT8NW2HJ"]})
	t.eq(iss.items.size(), 0, "E034/E036 없음: " + str(iss.items))
	# 번역 참조 불일치 → E034
	l.catalog.set_translation("tx_B3PZ8RW1MC", "en", "Attack, search [Stash]")
	iss = Issues.new()
	l.resolve_refs(iss)
	t.ok(iss.has_code("E034"), "번역 참조 불일치")
	# 이름 중복 → E036
	l.catalog.set_field("tx_Q9M2HX7ZK1", "ko", "캐시")
	iss = Issues.new()
	l.resolve_refs(iss)
	t.ok(iss.has_code("E036"), "이름 중복")


func test_expand_alias(t: TestKit) -> void:
	t.eq(Config.expand_alias("finance.special.{id}.name", {"id": "S01"}), "finance.special.s01.name")
	t.eq(Config.expand_alias("mental.{event_id}.{id}", {"event_id": "I-01", "id": "3"}), "mental.i_01.3")


func test_const_name_and_data_alias(t: TestKit) -> void:
	var dir: String = t.copy_fixture("basic")
	var cfg: Config = Config.load_from(dir.path_join("config.json"))
	t.eq(Config.const_name("lobby.start_button"), "LOBBY_START_BUTTON")
	t.ok(cfg.is_data_alias("card.pilot.6.name"), "데이터 alias")
	t.ok(cfg.is_data_alias("card.pilot.s01.desc"), "데이터 alias (문자 id)")
	t.ok(not cfg.is_data_alias("card.pilot.6.flavor"), "규칙 밖")
	t.ok(not cfg.is_data_alias("keyword.track.name"), "코드 alias")
