extends RefCounted

## key 참조 `{tx_…}` 테스트: 펼치기(dev · release) · E033 은 펼친 문장 기준 · E037 · E038 · E039 ·
## 사용처 kind=ref · 언어별 선택(번역은 참조 없이 써도 된다).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Builder = preload("res://addons/l10n_tool/core/builder.gd")
const KeyRefs = preload("res://addons/l10n_tool/core/key_refs.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Tokens = preload("res://addons/l10n_tool/core/tokens.gd")
const StatusOps = preload("res://addons/l10n_tool/core/status_ops.gd")


func _open(t: TestKit) -> L10n:
	var dir: String = t.copy_fixture("key_refs_basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	return l


func _keys_with(iss: Issues, code: String) -> Array:
	var out: Array = []
	for it in iss.items:
		if it["code"] == code:
			out.append(it["key"])
	return out


func test_keys_in(t: TestKit) -> void:
	t.eq(KeyRefs.keys_in("{tx_A0000000A1} {n} {tx_A0000000A1}"), PackedStringArray(["tx_A0000000A1", "tx_A0000000A1"]), "등장 순서 · 중복 포함")
	t.eq(KeyRefs.keys_in("{name}{i} [카드]"), PackedStringArray(), "자리표시자 · 조사 · 카드 참조는 key 참조가 아님")


func test_expand(t: TestKit) -> void:
	var l: L10n = _open(t)
	var cat = l.catalog
	t.eq(KeyRefs.expand(cat, cat.source_text("tx_A0000000A4"), "ko", "dev"), "적 또는 아군", "ko 조합")
	t.eq(KeyRefs.expand(cat, cat.text("tx_A0000000A4", "en"), "en", "dev"), "Ally or enemy", "en 은 참조 없이 직접")
	t.eq(KeyRefs.expand(cat, cat.source_text("tx_A0000000B2"), "ko", "dev"), "모든 파일럿 능력치 +{n}", "중첩 참조")
	t.eq(KeyRefs.expand(cat, cat.source_text("tx_A0000000A7"), "ko", "dev"), "", "순환 = 펼칠 수 없음")
	t.eq(KeyRefs.expand(cat, cat.source_text("tx_A0000000A9"), "ko", "dev"), "", "없는 key = 펼칠 수 없음")


func test_build_strings(t: TestKit) -> void:
	var l: L10n = _open(t)
	var ko: String = Builder.strings_csv(l, "ko", "dev")
	t.ok(ko.contains("tx_A0000000A4,적 또는 아군\n"), "ko dev 펼침")
	t.ok(ko.contains("tx_A0000000B3,파일럿 능력치{eul} 올린다\n"), "조사 태그는 런타임 몫으로 남김")
	t.ok(not ko.contains("tx_A0000000A7,"), "순환 행은 뺌")
	var en: String = Builder.strings_csv(l, "en", "dev")
	t.ok(en.contains("tx_A0000000A5,All pilot stats +{n}\n"), "en dev 펼침")
	t.ok(en.contains("tx_A0000000B1,낡음!\n"), "dev 는 번역 없으면 원문으로 펼침")
	var en_rel: String = Builder.strings_csv(l, "en", "release")
	t.ok(not en_rel.contains("tx_A0000000A5"), "release: 참조 대상이 approved 가 아니면 행을 뺌")


func test_validate(t: TestKit) -> void:
	var l: L10n = _open(t)
	var iss: Issues = l.cmd_validate("dev", false)
	t.eq(_keys_with(iss, "E037"), ["tx_A0000000A9"], "E037 없는 key")
	t.eq(_keys_with(iss, "E038"), ["tx_A0000000B1"], "E038 deprecated 참조")
	var cyc: Array = _keys_with(iss, "E039")
	cyc.sort()
	t.eq(cyc, ["tx_A0000000A7", "tx_A0000000A8"], "E039 순환")
	t.eq(_keys_with(iss, "E033"), ["tx_A0000000B2"], "E033 은 펼친 문장 기준 (A4 · A5 · B3 는 통과)")


func test_scan_usage(t: TestKit) -> void:
	var l: L10n = _open(t)
	var idx: Dictionary = l.cmd_scan(false)
	var us: Array = (idx.get("keys", {}) as Dictionary).get("tx_A0000000A6", {}).get("usages", [])
	var kinds: Array = []
	for u in us:
		kinds.append(u["kind"])
	t.ok(kinds.has("ref") and us.size() >= 2, "참조된 key 는 kind=ref 사용처: " + str(us))


func test_plural_tokens(t: TestKit) -> void:
	var ps: Array = Tokens.plurals("{n} {plural:n|{tx_A0000000A6}|tiles}")
	t.eq(ps.size(), 1, "형태 안 key 참조 허용")
	t.eq(ps[0]["forms"], PackedStringArray(["{tx_A0000000A6}", "tiles"]), "형태 목록")
	t.eq(Tokens.placeholder_set("Move {plural:k|tile|tiles}", []), PackedStringArray(), "복수 태그 이름은 자리표시자가 아님")
	t.eq(Tokens.plurals("{plural:charge+{attack_base}|time|times}")[0]["name"], "charge+{attack_base}", "이름이 식이어도 태그")


func test_plural_validate(t: TestKit) -> void:
	var l: L10n = _open(t)
	var iss: Issues = l.cmd_validate("dev", false)
	t.eq(_keys_with(iss, "E040"), ["tx_A0000000B5"], "E040 형태 수")
	t.ok(not _keys_with(iss, "E033").has("tx_A0000000B4"), "복수 태그가 있어도 E033 없음")
	var en: String = Builder.strings_csv(l, "en", "dev")
	t.ok(en.contains("tx_A0000000B4,{n} {plural:n|stat|stats}\n"), "복수 태그는 런타임 몫으로 남김")
	var ko: String = Builder.strings_csv(l, "ko", "dev")
	t.ok(ko.contains("tx_A0000000B4,{n}{plural:n|파일럿 능력치|파일럿 능력치}\n"), "형태 안 참조는 build 가 펼침")


func test_move_key(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(StatusOps.move_key(l, "ui.stat", "term.stat.pilot"), "", "move_key")
	var e: Dictionary = l.catalog.entry("tx_A0000000A6")
	t.eq(e.get("domain", ""), "term", "도메인 이동")
	t.eq(e.get("alias", ""), "term.stat.pilot", "alias 변경")
	t.eq(l.catalog.text("tx_A0000000A6", "en"), "pilot stats", "번역 유지")
	t.ok(not FileAccess.get_file_as_string(l.config.domain_path("ui")).contains("tx_A0000000A6,ui.stat"), "원래 파일에서 빠짐")
	t.ok(Builder.strings_csv(l, "ko", "dev").contains("tx_A0000000A5,모든 파일럿 능력치 +{n}\n"), "참조는 key 라 그대로 펼쳐짐")
	l.reload()
	t.eq(l.catalog.entry("tx_A0000000B3").get("alias", ""), "ui.josa", "뒤 행 번호 당김 후에도 다시 읽기 정상")
