extends RefCounted

## Sheet editor logic — sheet/sheet_model.gd (§11) + sheet scene headless load (every %name the script binds exists).

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const SheetModel = preload("res://addons/l10n_tool/sheet/sheet_model.gd")
const SHEET_SCENE := "res://addons/l10n_tool/sheet/l10n_sheet.tscn"

const K_CONFIRM := "tx_D5MN0P1Q2R"
const K_HAND := "tx_E6ST3V4W5X"
const K_OLD := "tx_F7YZ6A7B8C"
const K_DRAW := "tx_G8HJ9K0M1N"
const K_ROCKET := "tx_7KQ2M9XA4P"


func _model(t: TestKit, with_index: bool = true) -> SheetModel:
	var dir: String = t.copy_fixture("sheet_basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	var m: SheetModel = SheetModel.new()
	var idx: Dictionary = SheetModel.read_index(l.config.gen_dir.path_join("index.json")) if with_index else {}
	m.setup(l.config, l.catalog, idx)
	return m


static func _keys(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(r["key"])
	out.sort()
	return out


func test_rows_and_status(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	t.eq(m.rows.size(), 5, "행 수")
	t.ok(m.has_usage_data(), "사용처 있음")
	t.eq(m.domains(), PackedStringArray(["card", "ui"]))
	var hand: Dictionary = m.row_of(K_HAND)
	t.eq(hand["tr"]["en"], {"text": "Your hand is full", "status": "draft", "stale": true}, "draft + stale")
	t.eq(m.row_of(K_CONFIRM)["tr"]["en"]["stale"], false, "approved 해시 일치")
	t.eq(m.row_of(K_DRAW)["tr"]["en"]["status"], SheetModel.ST_NONE, "미착수")
	t.eq(SheetModel.status_cell(hand["tr"]["en"]), "draft · stale")


func test_search(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	t.eq(_keys(m.search("")), _keys(m.rows), "빈 검색 = 전부")
	t.eq(_keys(m.search("TX_7kq")), [K_ROCKET], "key · 대소문자 무시")
	t.eq(_keys(m.search("ui.old")), [K_OLD], "alias")
	t.eq(_keys(m.search("뽑기")), [K_DRAW], "원문")
	t.eq(_keys(m.search("hand is")), [K_HAND], "번역문")
	t.eq(_keys(m.search("draw")), [K_DRAW], "용어 term_id")
	t.eq(_keys(m.search("없는말")), [], "없음")


func test_filters(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	t.eq(_keys(m.search("", {"domain": "card"})), [K_ROCKET], "domain")
	t.eq(_keys(m.search("", {"locale": "en", "status": "approved"})), [K_ROCKET, K_CONFIRM], "approved")
	t.eq(_keys(m.search("", {"locale": "en", "status": "draft"})), [K_HAND], "draft")
	t.eq(_keys(m.search("", {"status": SheetModel.ST_NONE})), [K_OLD, K_DRAW], "미착수 (아무 로케일)")
	t.eq(_keys(m.search("", {"stale": true})), [K_HAND], "stale")
	t.eq(_keys(m.search("", {"unused": true})), [K_HAND, K_DRAW], "미사용 = active + 사용처 0 (deprecated 제외)")
	t.eq(_keys(m.search("", {"domain": "ui", "unused": true, "stale": true})), [K_HAND], "조합")
	# 용어집 위반 — 마지막 validate 의 W071 · W072 만
	t.eq(_keys(m.search("", {"glossary": true})), [], "validate 전에는 없음")
	m.set_issues([
		{"code": "W071", "level": "warn", "msg": "금지 표기", "file": "", "line": 0, "key": K_DRAW},
		{"code": "W072", "level": "warn", "msg": "표준 표기 없음", "file": "", "line": 0, "key": K_HAND},
		{"code": "E033", "level": "error", "msg": "자리표시자", "file": "", "line": 0, "key": K_CONFIRM},
	])
	t.eq(_keys(m.search("", {"glossary": true})), [K_HAND, K_DRAW], "용어집 위반")
	t.eq(m.orphans().size(), 1, "고아 목록")
	t.eq(String(m.orphans()[0]["text"]), "새 시즌")


func test_status_set_filter(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	var both := PackedStringArray([SheetModel.ST_DRAFT, SheetModel.ST_APPROVED])
	t.eq(_keys(m.search("", {"statuses": both})), [K_ROCKET, K_CONFIRM, K_HAND], "여러 상태 (OR)")
	t.eq(_keys(m.search("", {"statuses": PackedStringArray([SheetModel.ST_NONE])})), [K_OLD, K_DRAW], "미착수만")
	t.eq(_keys(m.search("", {"statuses": PackedStringArray()})), [], "고른 상태 없음 = 행 없음")
	t.eq(m.search("", {}).size(), 5, "statuses 없음 = 조건 없음")


func test_search_glossary(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	var ids := func(terms: Array) -> Array:
		var out: Array = []
		for g in terms:
			out.append(g["term_id"])
		out.sort()
		return out
	t.eq(ids.call(m.search_glossary("")), ["confirm", "draw", "hand", "mech"], "빈 검색 = 전부")
	t.eq(ids.call(m.search_glossary("드로우")), ["draw"], "금지 표기")
	t.eq(ids.call(m.search_glossary("ui.confirm")), ["confirm"], "연결 key 의 alias")
	t.eq(ids.call(m.search_glossary("번역 금지")), ["mech"], "note")
	t.eq(ids.call(m.search_glossary("", {"statuses": PackedStringArray([SheetModel.ST_APPROVED])})), ["confirm"], "상태 = 연결 key 기준")
	t.eq(ids.call(m.search_glossary("", {"statuses": PackedStringArray([SheetModel.ST_NONE])})), [], "key 없는 용어는 상태 필터에 안 걸린다")


func test_tag_completions(t: TestKit) -> void:
	var e: TextEdit = (load("res://addons/l10n_tool/sheet/tag_edit.gd") as GDScript).new()
	e.set("tags", PackedStringArray(["count", "name"]))
	e.set("offer_plural", true)
	e.set("find_label", "FIND")
	var labels := func(typed: String) -> Array:
		var out: Array = []
		for o in e.call("completions", typed):
			out.append(o["label"])
		return out
	t.eq(labels.call(""), ["{count}", "{name}", "{plural:name|…}", "FIND"], "{ 만 = 전부 + 스트링 찾기")
	t.eq(labels.call("n"), ["{name}", "FIND"], "앞부분 일치")
	t.eq(labels.call("PL"), ["{plural:name|…}", "FIND"], "대소문자 무시")
	t.eq(labels.call("plural:"), ["FIND"], "이미 다 친 항목은 뺀다")
	t.eq(labels.call("tx_"), ["FIND"], "{tx_ = 스트링 찾기만")
	t.eq(labels.call("tx_AB"), ["FIND"], "{tx_… 도 스트링 찾기만")
	# 용어집 낱말: {term_ 뒤로는 낱말 + 용어집 찾기, 고르면 key 참조
	e.set("terms", [{"id": "hand", "key": "tx_SVRFJDH55K", "text": "손"}, {"id": "draw", "key": "tx_6VVGYKXZSK", "text": "뽑기"}])
	e.set("find_term_label", "TERM")
	t.eq(labels.call(""), ["{count}", "{name}", "{plural:name|…}", "TERM", "FIND"], "{ 만 = 용어집에서 찾기도")
	t.eq(labels.call("te"), ["TERM", "FIND"], "term_ 앞부분")
	t.eq(labels.call("n"), ["{name}", "FIND"], "term_ 이 될 수 없으면 용어집 찾기 없음")
	t.eq(labels.call("term_"), ["term_hand  손", "term_draw  뽑기", "TERM"], "{term_ = 낱말 + 용어집 찾기")
	t.eq(labels.call("term_d"), ["term_draw  뽑기", "TERM"], "낱말 앞부분 일치")
	var picked: Array = e.call("completions", "term_h")
	t.eq(picked[0].get("key", ""), "tx_SVRFJDH55K", "낱말 = 연결 key")
	# 이름 행(offer_refs = false): 태그만, 용어집 · 스트링 찾기 없음
	e.set("offer_refs", false)
	t.eq(labels.call(""), ["{count}", "{name}", "{plural:name|…}"], "이름 = 참조 항목 없음")
	t.eq(labels.call("term_"), [], "이름 = 용어집 낱말 없음")
	t.eq(labels.call("tx_"), [], "이름 = 스트링 찾기 없음")
	e.free()


func test_detail(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	m.set_issues([{"code": "W071", "level": "warn", "msg": "금지 표기 드로우", "file": "", "line": 0, "key": K_DRAW}])
	t.eq(m.detail("tx_ZZZZZZZZZZ"), {}, "없는 key")
	var d: Dictionary = m.detail(K_ROCKET)
	t.eq(d["alias"], "card.pilot.6.name")
	t.eq(d["context"], "카드 이름")
	t.eq(d["max_len"], "10")
	t.eq(d["source"], "로켓 펀치")
	t.eq(d["usages"].size(), 2, "사용처")
	t.ok(not d.has("haystack"), "내부 필드 제외")
	var txt: String = m.detail_text(d)
	t.ok(txt.contains("[en] (approved) Rocket Punch"), "번역 줄: " + txt)
	d = m.detail(K_DRAW)
	t.eq(d["glossary"], ["draw"], "용어")
	t.eq(d["issues"].size(), 1, "걸린 검증 항목")
	t.ok(m.detail_text(d).contains("W071"), "본문에 W071")


func test_glossary(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	var terms: Array = m.glossary_terms()
	t.eq(terms.size(), 4)
	var by_id: Dictionary = {}
	for g in terms:
		by_id[g["term_id"]] = g
	t.eq(by_id["hand"]["forbidden"]["ko"], PackedStringArray(["손패", "핸드"]), "금지 표기")
	t.eq(by_id["confirm"]["texts"], {"ko": "확인", "en": "OK"}, "key 용어 → key 의 값")
	t.eq(by_id["mech"]["texts"]["en"], "메크", "dnt → 원문 표기")
	t.eq(m.keys_with_term("hand"), [K_HAND], "손 → 손이 가득 찼다")
	t.eq(m.keys_with_term("confirm"), [K_CONFIRM])
	t.eq(m.keys_with_term("mech"), [])


func test_no_index_and_empty_catalog(t: TestKit) -> void:
	var m: SheetModel = _model(t, false)
	t.ok(not m.has_usage_data(), "index 없음 → 사용처 없음 힌트")
	t.eq(m.rows.size(), 5, "catalog 행은 그대로")
	t.eq(m.orphans(), [])
	t.eq(m.row_of(K_ROCKET)["usages"], [])
	# 엔트리 0개(현재 실제 상태) · catalog 없음에서도 깨지지 않는다
	var empty: SheetModel = SheetModel.new()
	empty.setup(null, null, {})
	t.eq(empty.search("x", {"stale": true}), [])
	t.eq(empty.glossary_terms(), [])
	t.eq(empty.domains(), PackedStringArray())


func test_usage_action(t: TestKit) -> void:
	t.eq(SheetModel.usage_action({"file": "res://a/B.gd", "line": 7})["kind"], SheetModel.KIND_SCRIPT)
	t.eq(SheetModel.usage_action({"file": "res://a/B.tscn", "line": 3})["kind"], SheetModel.KIND_SCENE)
	t.eq(SheetModel.usage_action({"file": "res://a/B.tres", "line": 3})["kind"], SheetModel.KIND_RESOURCE)
	var a: Dictionary = SheetModel.usage_action({"file": "res://data/csv/cards.csv", "line": 2})
	t.eq([a["kind"], a["label"]], [SheetModel.KIND_COPY, "res://data/csv/cards.csv:2"], "데이터 CSV → 복사")


func test_scene_rows(t: TestKit) -> void:
	var m: SheetModel = _model(t)
	var root := Control.new()
	root.name = "Root"
	var title := Label.new()
	title.name = "Title"
	title.text = K_CONFIRM
	root.add_child(title)
	var box := VBoxContainer.new()
	box.name = "Box"
	root.add_child(box)
	var btn := Button.new()
	btn.name = "Go"
	btn.text = "plain"
	btn.tooltip_text = K_ROCKET
	box.add_child(btn)
	var edit := LineEdit.new()
	edit.name = "Edit"
	edit.placeholder_text = "tx_ZZZZZZZZZZ"
	box.add_child(edit)
	var draw := Label.new()
	draw.name = "Draw"
	draw.text = K_DRAW
	box.add_child(draw)
	var props: Array = m.config.scan_list("scene_text_props")
	var got: Array = SheetModel.scene_rows(root, props, m.catalog, "en", "tx_")
	var flat: Array = []
	for r in got:
		flat.append([r["path"], r["prop"], r["key"], r["alias"], r["text"], r["known"], r["missing"]])
	t.eq(flat, [
		["Title", "text", K_CONFIRM, "ui.confirm", "OK", true, false],
		["Box/Go", "tooltip_text", K_ROCKET, "card.pilot.6.name", "Rocket Punch", true, false],
		["Box/Edit", "placeholder_text", "tx_ZZZZZZZZZZ", "", "", false, true],
		["Box/Draw", "text", K_DRAW, "ui.draw_one", "", true, true],
	], "트리 순서 · 속성 · 번역")
	t.eq(SheetModel.scene_rows(root, props, m.catalog, "ko", "tx_")[0]["text"], "확인", "원문 로케일")
	t.eq(title.text, K_CONFIRM, "노드 속성은 그대로")
	t.eq(SheetModel.scene_rows(null, props, m.catalog, "en", "tx_"), [], "열린 씬 없음")
	root.free()


func test_sheet_scene_loads_headless(t: TestKit) -> void:
	t.ok(ResourceLoader.exists(SHEET_SCENE), "표 편집기 씬 있음")
	var ps: PackedScene = load(SHEET_SCENE)
	t.ok(ps != null and ps.can_instantiate(), "로드")
	var dock: Control = ps.instantiate()
	t.ok(dock != null and dock.has_method("setup"), "setup 있음")
	# 러너의 _initialize 안에서는 _ready(@onready) 가 돌지 않는다 — 스크립트가 묶는 %이름을 직접 확인.
	var src: String = FileAccess.get_file_as_string("res://addons/l10n_tool/sheet/l10n_sheet.gd")
	var re := RegEx.create_from_string("get_node\\(\"%([^\"]+)\"\\)|%([A-Z][A-Za-z0-9_]*)")
	var names: Dictionary = {}
	for m in re.search_all(src):
		names[m.get_string(1) if m.get_string(1) != "" else m.get_string(2)] = true
	t.ok(names.size() > 20, "고유 이름 수: " + str(names.size()))
	for n in names:
		t.ok(dock.get_node_or_null("%" + String(n)) != null, "씬에 %" + String(n))
	dock.free()
