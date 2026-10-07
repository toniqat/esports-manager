extends RefCounted

## `extract data` 테스트 — fixture `extract_basic`:
## cards.csv (숫자 id, BOM + CRLF, 따옴표 · 참조 · 토큰 · 빈 칸, 일부 alias 는 이미 원본에 있음),
## mech_cards.csv (name_key 는 이미 이행, description 만 남음), finance_specials.csv (문자 id),
## missing.csv (config 에만 있음).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")

const FIXTURE := "extract_basic"


func test_extract_all(t: TestKit) -> void:
	var dir: String = t.copy_fixture(FIXTURE)
	var l: L10n = _open(dir)
	t.eq(l.cmd_extract(PackedStringArray(["data"])), "", "성공")
	l.catalog.reload()
	var cat: Catalog = l.catalog
	# cards.csv — 헤더 · 바뀐 셀만, BOM · CRLF · 따옴표 스타일 유지, 빈 칸 행은 그대로
	var k1n: String = cat.key_of_alias("card.pilot.1.name")
	var k1d: String = cat.key_of_alias("card.pilot.1.desc")
	var k3n: String = cat.key_of_alias("card.pilot.3.name")
	var k3d: String = cat.key_of_alias("card.pilot.3.desc")
	var k5n: String = cat.key_of_alias("card.pilot.5.name")
	var k5d: String = cat.key_of_alias("card.pilot.5.desc")
	var want: String = "id,name_key,cost,description_key,scope\r\n1,%s,6,%s,top|mid\r\n2,tx_P2NAME0001,1,tx_P2DESC0001,top\r\n3,%s,0,%s,mid\r\n4,,0,,mid\r\n5,%s,2,%s,top\r\n" % [k1n, k1d, k3n, k3d, k5n, k5d]
	var bytes: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	bytes.append_array(want.to_utf8_buffer())
	t.eq(TestKit.read_bytes(dir.path_join("csv/cards.csv")), bytes, "cards.csv 바이트")
	t.eq(cat.source_text(k1d), "3턴 간 교전, 범위 내 \"모두\" 참여", "따옴표 · 쉼표 원문")
	t.eq(cat.source_text(cat.key_of_alias("card.pilot.2.name")), "로켓 펀치")
	t.eq(cat.source_text("tx_P2DESC0001"), "옛 설명", "원문이 다른 기존 alias 는 덮어쓰지 않는다")
	t.eq(cat.key_of_alias("card.pilot.4.name"), "", "빈 칸은 key 없음")
	var e1: Dictionary = cat.entry(k1n)
	t.eq(e1["context"], "cards.csv name (id=1)", "자동 context")
	t.eq(e1["tr"]["en"]["text"], "", "번역은 비움")
	# 문자 id → 소문자 alias, 새 도메인 파일
	var fin: String = FileAccess.get_file_as_string(dir.path_join("csv/finance_specials.csv"))
	var ks1: String = cat.key_of_alias("finance.special.s01.name")
	t.ok(ks1 != "", "finance.special.s01.name")
	t.eq(fin, "id,name_key,kind,cost,desc_key\nS01,%s,coach_hire,250,%s\nS02,%s,coach_hire,300,%s\n" % [ks1,
			cat.key_of_alias("finance.special.s01.desc"), cat.key_of_alias("finance.special.s02.name"),
			cat.key_of_alias("finance.special.s02.desc")], "finance_specials.csv (LF)")
	t.ok(FileAccess.file_exists(dir.path_join("src/finance.csv")), "finance 도메인 파일 생성")
	# 일부 이행된 표 — name_key 는 그대로, description 만 추출
	var mech: String = FileAccess.get_file_as_string(dir.path_join("csv/mech_cards.csv"))
	t.eq(mech, "id,mech_id,name_key,count,description_key\n1,24,tx_M1NAME0001,1,%s\n2,24,tx_M2NAME0001,1,\n" % cat.key_of_alias("card.mech.1.desc"))
	# 보고서
	var rep: String = FileAccess.get_file_as_string(dir.path_join("generated/extract_report.md"))
	t.ok(rep.contains("\"공격\" ×3"), "중복 텍스트: " + rep)
	t.ok(rep.contains("## E036 후보 (1)") and rep.contains("\"캐시\""), "E036 후보")
	t.ok(rep.contains("missing.csv: 파일 없음"), "없는 csv")
	t.ok(rep.contains("옛 설명"), "원문 불일치 보고")
	t.ok(rep.contains("mech_cards.csv name_key: 이미 이행됨 — 검사 통과 2 · 불일치 0"), "이행된 컬럼 검사")


func test_extract_idempotent(t: TestKit) -> void:
	var dir: String = t.copy_fixture(FIXTURE)
	var l: L10n = _open(dir)
	t.eq(l.cmd_extract(PackedStringArray(["data"])), "")
	var snap: Dictionary = _snapshot(dir)
	var rep1: String = FileAccess.get_file_as_string(dir.path_join("generated/extract_report.md"))
	t.eq(l.cmd_extract(PackedStringArray(["data"])), "", "두 번째 실행")
	t.eq(_snapshot(dir), snap, "두 번째 실행은 아무것도 바꾸지 않는다")
	var rep2: String = FileAccess.get_file_as_string(dir.path_join("generated/extract_report.md"))
	t.ok(rep2.contains("cards.csv name_key: 이미 이행됨 — 검사 통과 4 · 불일치 0"), "검사 모드: " + rep2)
	t.ok(rep2.contains("\"공격\" ×3"), "중복 보고 유지")
	t.ok(rep1.contains("신규") and not rep2.contains("신규"), "두 번째는 발급 없음")


func test_extract_filter(t: TestKit) -> void:
	var dir: String = t.copy_fixture(FIXTURE)
	var before: Dictionary = _snapshot(dir)
	var l: L10n = _open(dir)
	t.eq(l.cmd_extract(PackedStringArray(["data", "finance_specials.csv", "nope.csv"])), "")
	var after: Dictionary = _snapshot(dir)
	t.eq(after["csv/cards.csv"], before["csv/cards.csv"], "필터 밖 csv 그대로")
	t.eq(after["src/card.csv"], before["src/card.csv"], "필터 밖 도메인 그대로")
	t.ok(after["csv/finance_specials.csv"] != before["csv/finance_specials.csv"], "필터 안 csv 이행")
	var rep: String = FileAccess.get_file_as_string(dir.path_join("generated/extract_report.md"))
	t.ok(rep.contains("nope.csv: config.data_columns 에 없는 csv"), "모르는 csv 보고")


func test_extract_excel_lock(t: TestKit) -> void:
	for lock in ["csv/~$cards.csv", "src/~$card.csv"]:
		var dir: String = t.copy_fixture(FIXTURE)
		TestKit.write_bytes(dir.path_join(lock), PackedByteArray([0]))
		var before: Dictionary = _snapshot(dir)
		var l: L10n = _open(dir)
		var err: String = l.cmd_extract(PackedStringArray(["data", "cards.csv"]))
		t.ok(err.contains("Excel 잠금"), "잠금 거부 (%s): %s" % [lock, err])
		t.eq(_snapshot(dir), before, "잠금 → 아무것도 바꾸지 않음 (%s)" % lock)


func test_extract_bad_alias_changes_nothing(t: TestKit) -> void:
	var dir: String = t.copy_fixture(FIXTURE)
	TestKit.write_bytes(dir.path_join("csv/finance_specials.csv"),
			"id,name,kind,cost,desc\nS01,코치,coach_hire,250,x\n,이름만,coach_hire,1,y\n".to_utf8_buffer())
	var before: Dictionary = _snapshot(dir)
	var l: L10n = _open(dir)
	var err: String = l.cmd_extract(PackedStringArray(["data", "finance_specials.csv"]))
	t.ok(err.contains("alias 규칙 위반"), "빈 id → 오류: " + err)
	t.eq(_snapshot(dir), before, "오류 → 아무것도 바꾸지 않음")
	t.ok(not FileAccess.file_exists(dir.path_join("src/finance.csv")), "도메인 파일도 만들지 않음")
	t.eq(l.catalog.key_of_alias("finance.special.s01.name"), "", "메모리 카탈로그도 되돌림")


func test_extract_verify_mismatch(t: TestKit) -> void:
	var dir: String = t.copy_fixture(FIXTURE)
	var l: L10n = _open(dir)
	t.eq(l.cmd_extract(PackedStringArray(["data", "cards.csv"])), "")
	var tab: CsvIo = CsvIo.load_file(dir.path_join("csv/cards.csv"))
	tab.set_cell(2, "name_key", "tx_M1NAME0001")
	tab.set_cell(4, "name_key", "tx_ZZZZZZZZZZ")
	tab.save()
	var before: Dictionary = _snapshot(dir)
	t.eq(l.cmd_extract(PackedStringArray(["data", "cards.csv"])), "", "검사 불일치는 보고만")
	t.eq(_snapshot(dir), before, "검사 모드는 쓰지 않음")
	var rep: String = FileAccess.get_file_as_string(dir.path_join("generated/extract_report.md"))
	t.ok(rep.contains("alias 'card.mech.1.name' ≠ 규칙 'card.pilot.3.name'"), "alias 불일치: " + rep)
	t.ok(rep.contains("없는 key 'tx_ZZZZZZZZZZ'"), "없는 key")
	t.ok(rep.contains("검사 통과 2 · 불일치 2"), "집계")


func _open(dir: String) -> L10n:
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	return l


# csv/ · src/ 파일 → 바이트
func _snapshot(dir: String) -> Dictionary:
	var out: Dictionary = {}
	for sub in ["csv", "src"]:
		var p: String = dir.path_join(sub)
		for fn in DirAccess.get_files_at(p):
			out[sub + "/" + fn] = TestKit.read_bytes(p.path_join(fn))
	return out
