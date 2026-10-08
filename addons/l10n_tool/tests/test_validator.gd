extends RefCounted

## validator 테스트 — 원본 규칙(§13) + report.md (§15 2단계).
## validator_errors = 규칙마다 의도적 오류, validator_clean = Error 0.

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Validator = preload("res://addons/l10n_tool/core/validator.gd")

## validator 가 내는 코드 — scanner(E05x · W05x) 결과와 섞이지 않게 이것만 본다.
const OWN_CODES := ["E003", "E004", "W003", "E010", "E011", "E012", "E013", "E031", "W031", "W032",
	"E033", "E034", "E035", "E036", "W036", "W034", "W035", "E041", "E042", "W041", "E061", "W071", "W072", "E072", "E073", "E074"]


func _open(t: TestKit, fixture: String) -> L10n:
	var dir: String = t.copy_fixture(fixture)
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open " + fixture)
	return l


func _own(iss: Issues) -> Array:
	var out: Array = []
	for it in iss.items:
		if OWN_CODES.has(it["code"]):
			out.append(Issues.format_item(it))
	return out


# key 로 그 코드가 났는가.
func _has(iss: Issues, code: String, key: String) -> bool:
	for it in iss.items:
		if it["code"] == code and it["key"] == key:
			return true
	return false


func test_clean_has_no_errors(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_clean")
	var iss: Issues = l.cmd_validate("dev", false)
	t.eq(iss.error_count(), 0, "dev Error 0: " + str(_own(iss)))
	t.eq(_own(iss), [], "validator 경고도 0")
	iss = l.cmd_validate("release", false)
	t.eq(iss.error_count(), 0, "release Error 0: " + str(_own(iss)))


func test_errors_fixture_detects_every_rule(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_errors")
	var iss: Issues = l.cmd_validate("dev", false)
	for code in ["E003", "W003", "E010", "E011", "E012", "E013", "E031", "W031", "W032", "E033", "E034",
			"E035", "E036", "W036", "W034", "W035", "E041", "E042", "W041", "W071", "W072", "E072", "E073", "E074"]:
		t.ok(iss.has_code(code), "검출: " + code)
	t.ok(not iss.has_code("E061"), "dev 에서는 E061 없음")
	t.ok(not iss.has_code("E004"), "josa_tags 일치")
	# 행 단위로 맞는 key 에 붙었는지
	t.ok(_has(iss, "E003", "tx_G1H2J3K4M8"), "E003 status")
	t.ok(_has(iss, "E003", "tx_G1H2J3K4M9"), "E003 en_status")
	t.ok(_has(iss, "E010", "tx_bad"), "E010")
	t.eq(iss.count_code("E011"), 1, "E011 한 번")
	t.ok(_has(iss, "E012", "tx_G1H2J3K4M5"), "E012 형식")
	t.ok(_has(iss, "E012", "tx_G1H2J3K4M6"), "E012 도메인")
	t.ok(_has(iss, "E012", "tx_G1H2J3K4M7"), "E012 중복")
	t.ok(_has(iss, "E013", "tx_J1K2M3N4P5"), "E013")
	t.ok(_has(iss, "E031", "tx_D5MN0P1Q2R"), "E031")
	t.ok(_has(iss, "W031", "tx_F7YZ6A7B8C"), "W031")
	t.ok(_has(iss, "W032", "tx_H1J2K3M4N5"), "W032")
	t.ok(_has(iss, "E033", "tx_B3PZ8RW1MC"), "E033")
	t.ok(_has(iss, "E035", "tx_E6ST3V4W5X"), "E035")
	t.ok(_has(iss, "W034", "tx_H1J2K3M4N6"), "W034")
	t.eq(iss.count_code("W035"), 2, "W035 ko · en")
	t.ok(_has(iss, "W003", "tx_H1J2K3M4N8"), "W003")
	t.ok(_has(iss, "E034", "tx_J1K2M3N4P8"), "E034")
	t.ok(_has(iss, "W036", "tx_B3PZ8RW1MC"), "W036 이름으로 적은 참조")
	t.ok(_has(iss, "E041", "tx_ZZZZZZZZZZ"), "E041")
	t.ok(_has(iss, "E042", "tx_7KQ2M9XA4P"), "E042")
	t.eq(iss.count_code("W041"), 2, "W041 파일 없음 · 컬럼 없음")
	t.ok(_has(iss, "W071", "tx_J1K2M3N4P6"), "W071 ko 금지 표기")
	t.ok(_has(iss, "W071", "tx_J1K2M3N4P7"), "W071 en 금지 표기")
	t.ok(_has(iss, "W072", "tx_J1K2M3N4P7"), "W072 표준 표기")
	t.ok(_has(iss, "W072", "tx_K1M2N3P4Q5"), "W072 dnt")
	t.ok(_has(iss, "W072", "tx_K1M2N3P4Q6"), "W072 key 용어")
	t.eq(iss.count_code("E072"), 2, "E072 값 함께 · 없는 key")
	t.eq(iss.count_code("E073"), 2, "E073 중복 · 형식")
	# match_<loc> regex: 턴 inside 어시스턴트 is not the term, 3턴 is
	t.eq(iss.count_code("E074"), 1, "E074 bad regex")
	t.ok(not _has(iss, "W072", "tx_M1N2P3Q4R5"), "match_ko skips word-internal 턴")
	t.ok(_has(iss, "W072", "tx_M1N2P3Q4R6"), "match_ko still matches 3턴")
	# 파일 · 줄
	for it in iss.items:
		if it["code"] == "E033":
			t.ok(String(it["file"]).ends_with("src/card.csv") and int(it["line"]) == 3, "E033 위치: " + Issues.format_item(it))


func test_release_e061(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_clean")
	# draft 로 내리면 release 에서 E061, dev 에서는 아님
	t.eq(l.catalog.set_translation("tx_E6ST3V4W5X", "en", "{name} arrived"), "")
	t.eq(l.catalog.save_all(), "")
	var iss: Issues = l.cmd_validate("dev", false)
	t.ok(not iss.has_code("E061"), "dev 는 E061 없음")
	iss = l.cmd_validate("release", false)
	t.ok(_has(iss, "E061", "tx_E6ST3V4W5X"), "release E061 (draft)")
	# 원문 수정 → stale → W031 + release E061
	t.eq(l.catalog.set_field("tx_D5MN0P1Q2R", "ko", "확인!"), "")
	t.eq(l.catalog.save_all(), "")
	iss = l.cmd_validate("release", false)
	t.ok(_has(iss, "W031", "tx_D5MN0P1Q2R"), "stale W031")
	t.ok(_has(iss, "E061", "tx_D5MN0P1Q2R"), "stale E061")
	# 사용처 인덱스가 있으면 사용 중인 key 만 본다
	l.index = {"keys": {"tx_D5MN0P1Q2R": {"usages": [{"file": "x.gd", "line": 1}]}, "tx_E6ST3V4W5X": {"usages": []}}}
	l.issues = Issues.new()
	Validator.validate(l, "release")
	t.ok(_has(l.issues, "E061", "tx_D5MN0P1Q2R"), "사용 중 → E061")
	t.ok(not _has(l.issues, "E061", "tx_E6ST3V4W5X"), "미사용 → E061 없음")


func test_e004_josa_tags(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_clean")
	l.config.josa_tags = ["eul", "eun", "i"]
	var iss: Issues = l.cmd_validate("dev", false)
	t.ok(iss.has_code("E004"), "josa_tags 불일치 → E004")


func test_deprecated_skips_quality_rules(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_clean")
	# deprecated 행의 자리표시자 불일치 · 조사 태그는 보지 않는다
	t.eq(l.catalog.set_translation("tx_F7YZ6A7B8C", "en", "{x}{i}"), "")
	t.eq(l.catalog.save_all(), "")
	var iss: Issues = l.cmd_validate("dev", false)
	t.ok(not iss.has_code("E033") and not iss.has_code("E035"), "deprecated 제외: " + str(_own(iss)))


func test_write_report(t: TestKit) -> void:
	var l: L10n = _open(t, "validator_errors")
	l.cmd_validate("dev", true)
	var p: String = l.config.gen_dir.path_join("report.md")
	t.ok(FileAccess.file_exists(p), "report.md 생성")
	var md: String = FileAccess.get_file_as_string(p)
	t.ok(md.contains("# L10n 검증 보고서 — dev"), "제목")
	t.ok(md.contains("| locale | total | 미착수 | draft | approved | stale | 진행률 |"), "진행표 헤더")
	t.ok(md.contains("## Error (") and md.contains("## Warn ("), "Error · Warn 묶음")
	t.ok(md.find("## Error") < md.find("## Warn"), "Error 먼저")
	t.ok(md.contains("- **E033** `") and md.contains("`tx_B3PZ8RW1MC` (card.pilot.6.desc) — "), "이슈 줄 형식")
	t.ok(md.contains("- **W041** — "), "범례에 W041")
	# 진행표 숫자 — clean: active 8, 모두 approved · 비-stale
	var lc: L10n = _open(t, "validator_clean")
	lc.cmd_validate("dev", true)
	md = FileAccess.get_file_as_string(lc.config.gen_dir.path_join("report.md"))
	t.ok(md.contains("| en | 8 | 0 | 0 | 8 | 0 | 100.0% |"), "clean 진행표: " + md.substr(0, 400))
	var rows: Array = Validator.progress(l)
	t.eq(rows.size(), 1)
	t.ok(int(rows[0]["stale"]) >= 1 and int(rows[0]["untouched"]) >= 1, "errors 진행표: " + str(rows[0]))
