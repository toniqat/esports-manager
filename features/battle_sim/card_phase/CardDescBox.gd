class_name CardDescBox
extends RefCounted

# 카드 한 장의 **설명판** — 이름 · 비용 · 키워드 · 설명문 · 키워드 풀이.
# 머리줄은 [작은 비용 리본] 이름 한 덩어리가 판 가운데에 선다. 판에는 테두리가 없다.
#
# **키워드는 설명문에 다시 적지 않는다.** 판이 이름 아래에 키워드 줄(소멸 ·
# 재배치 · 충전 N …)을 세우고, 키워드마다 한 줄 풀이를 단다 — 그래서 설명문에는
# 그 카드만의 효과만 남아 짧아진다. 풀이는 보통 판 맨 아래에 붙지만, 손패는 판
# 옆에 키워드마다 판 하나씩 따로 세운다(`build(..., with_notes = false)` +
# `build_keyword_panels`).
#
# 카드 앞면에서 설명문이 걷히면서(`Card.gd` 앞면 두 층) 그 글을 들 자리가 화면마다
# 필요해졌다: 손패는 가리킨 카드 옆(`CardPhaseManager`), 밴픽 시트와 메크 상세는
# 누른 카드 위다. 세 곳이 같은 판을 쓰도록 짓는 일만 여기 모은다 — **자리는
# 부르는 쪽이 정한다**(판의 크기는 내용이 정하므로 `build` 가 돌려준 `size` 를
# 보고 아랫변을 맞춘다).
#
# 두 벌의 색이 있다 — 인게임(어두운 전장 위) / 아웃게임(흰 배경, `OutgameTheme`).
# 아웃게임 화면이 인게임 색을 쓰면 흰 화면 한가운데에 검은 판이 뜨고, 그 반대면
# 전장 위에 흰 판이 뜬다.

const PAD := 14.0
const HEADER_H := 36.0
const GAP := 8.0
const NAME_FONT := 22
const COST_FONT := 22
## 머리줄 이름 왼쪽의 작은 비용 리본(`CostRibbon`).
const COST_RIBBON_SIZE := Vector2(26.0, 36.0)
const COST_RIBBON_GAP := 8.0
## 설명문 글자 크기 — 머리줄 이름(`NAME_FONT`)과 같다. 예전 18 은 판 제목보다
## 한참 작아 설명문이 각주처럼 읽혔다.
const DESC_FONT := 22
const KW_FONT := 18
const NOTE_FONT := 15
## 설명이 아무리 짧아도 판이 이 높이 아래로 줄지 않는다 — 한 줄짜리 카드에서
## 판이 띠처럼 납작해지면 카드마다 판 크기가 들쭉날쭉해 보인다.
const MIN_H := 110.0
## 속성 줄(대상 · 사거리 · 시전 범위) 높이. 지속시간은 설명문이 "3턴" 으로 적는다.
const ATTR_H := 30.0
const ATTR_SEP := "   "
## `CardData.target` → 속성 줄의 대상 글자.
const TARGET_LABELS := {
	"enemy": "적",
	"ally": "아군",
	"pilot": "아군 또는 적",
	"foe": "적 또는 포탑",
	"location": "타일",
	"turret_outer": "최외곽 포탑",
	"turret_any": "적 포탑",
}

## 설명문 계산식 `{식|전투 밖 문구}` — 전투 중에는 식의 값, 밖에서는 "(문구)".
## 식이 읽는 이름: `charge` = 카드 위 토큰 수, `chain` = 시전 파일럿의 [영혼 포식]
## 토큰 수(`MechSkillSystem.chain_rounds`). 예: `성장 +{charge*8|사용 횟수×8}%`.
## 설명문의 `\n` 두 글자는 줄바꿈이다(CSV 한 칸에 줄을 나누지 않으려고).
static var _formula_re: RegEx = null
## 전투 중에만 유효한 값 공급자 — `CardPhaseManager` 가 트리에 들어오면 걸고
## 나가면 풀린다(객체가 해제되면 `is_valid()` 도 false). `func(cd) -> Dictionary`.
static var live_vars: Callable = Callable()


## 판 배경 — 테두리 없는 둥근 판. 아웃게임은 흰 판 + 그림자, 인게임은 어두운 판 +
## 아래로 흐릿한 드롭 섀도. 파일럿 상세 패널의 스탯 설명판도 이 판을 쓴다.
static func panel_style(light: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat
	if light:
		style = OutgameTheme.card_style(14)
		style.set_border_width_all(0)
	else:
		style = BattleTheme.desc_box()
	return style


## `cost_text` / `cost_color` 를 비워 두면 카드의 인쇄 비용(사용 불가면 `—`)을 찍는다.
## 손패는 할인 · 증세가 먹은 실제 비용을 넘긴다.
##
## `with_notes` 를 끄면 맨 아래 키워드 풀이를 빼고 짓는다 — 손패는 풀이를 판 옆
## 별도 판들(`build_keyword_panels`)에 세운다. `min_h` 는 판 높이의 하한(손패는 0 을
## 넘겨 판이 글 길이만큼만 선다).
##
## `live` 를 끄면 전투 중에도 계산식을 값이 아닌 식 문구로 적는다(`resolve_text`) —
## 파일럿 상세 패널의 보유 카드가 쓴다(지금 손에 든 카드가 아니라 값이 없다).
static func build(data: CardData, width: float, light: bool = false,
		cost_text: String = "", cost_color: Variant = null,
		with_notes: bool = true, min_h: float = MIN_H, live: bool = true) -> Panel:
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", panel_style(light))
	if data == null:
		box.size = Vector2(width, min_h)
		return box

	var name_col: Color = OutgameTheme.TEXT if light else Color(1.0, 0.95, 0.55)
	var desc_col: Color = OutgameTheme.TEXT_SUB if light else Color(0.92, 0.92, 0.92)
	var inner_w: float = width - PAD * 2.0

	if cost_text == "":
		cost_text = Card.UNPLAYABLE_COST_TEXT if not data.is_playable() else str(data.cost)
	var cost_col: Color = cost_color if cost_color is Color else Card.COST_COLOR_BASE

	# 머리줄 — [비용 리본] 이름, 한 덩어리로 판 가운데. 이름이 길면 이름만 잘린다.
	var name_room: float = inner_w - COST_RIBBON_SIZE.x - COST_RIBBON_GAP
	var name_w: float = minf(name_room, _text_width(data.card_name, NAME_FONT) + 2.0)
	var group_x: float = PAD + (inner_w - (COST_RIBBON_SIZE.x + COST_RIBBON_GAP + name_w)) * 0.5
	CostRibbon.make_badge(box,
			Rect2(Vector2(group_x, PAD + (HEADER_H - COST_RIBBON_SIZE.y) * 0.5),
					COST_RIBBON_SIZE),
			cost_text, COST_FONT, cost_col, CostRibbon.FILL, light)
	var name_lbl := UiHelpers.mk_label(box, data.card_name, NAME_FONT, name_col,
			Vector2(group_x + COST_RIBBON_SIZE.x + COST_RIBBON_GAP, PAD),
			Vector2(name_w, HEADER_H))
	name_lbl.clip_text = true
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 높이는 레이아웃 패스를 기다리지 않고 글꼴로 직접 잰다 — 판을 만든 그
	# 프레임에 자리를 정해야 하는데 autowrap 라벨의 최소 크기는 폭이 정해진
	# 뒤에야 나온다.
	var desc_y: float = PAD + HEADER_H + GAP
	var kws: Array = data.keyword_list()
	if not kws.is_empty():
		var tags: Array = []
		for kw in kws:
			tags.append(data.keyword_label(String(kw)))
		var tag_text: String = " · ".join(tags)
		var tag_h: float = _text_height(tag_text, inner_w, KW_FONT)
		var kw_lbl := UiHelpers.mk_label(box, tag_text, KW_FONT, _kw_color(light),
				Vector2(PAD, desc_y), Vector2(inner_w, tag_h))
		kw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kw_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		kw_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_y += tag_h + 4.0
	# 속성 줄 — 대상 · 사거리 · 시전 범위를 아이콘과 값으로.
	var attrs: Array = card_attributes(data)
	if not attrs.is_empty():
		# 좁은 판(손패 240px)에서는 줄이 접힌다 — 높이는 대역 문자열로 잰다.
		var attr_h: float = maxf(ATTR_H, _text_height(_attr_measure(attrs), inner_w, KW_FONT))
		var attr := _attr_label(attrs, light, target_info(data)["color"])
		attr.position = Vector2(PAD, desc_y)
		attr.size = Vector2(inner_w, attr_h)
		box.add_child(attr)
		desc_y += attr_h + 4.0
	# 설명문은 "전략 점수" · "비용" 앞에 아이콘이 서므로 RichTextLabel 이다.
	var desc_text: String = resolve_text(data, live)
	var desc_refs: Array = CardData.ref_entries(data.description_key)
	var desc_h: float = _text_height(StrategyIcon.measure_text(desc_text, desc_refs),
			inner_w, DESC_FONT)
	var tgt: Dictionary = target_info(data)
	var desc := StrategyIcon.make_rich_label(desc_text, DESC_FONT, desc_col,
			_kw_color(light), _knock_color(light), tgt["color"], tgt["key"],
			_special_color(light), desc_refs)
	desc.position = Vector2(PAD, desc_y)
	desc.size = Vector2(inner_w, desc_h)
	box.add_child(desc)

	# 키워드 풀이 — 키워드마다 한 줄. 설명문보다 작고 흐리게.
	var bottom: float = desc_y + desc_h
	# 카드 이름 특수 키워드는 풀이 줄 대신 그 카드의 설명판을 판 안에 끼운다.
	var notes: Array = _keyword_notes(data) if with_notes else []
	var lines: Array = []
	var specials: Array = []
	var refs: Array = []
	for n_raw in notes:
		var n: Dictionary = n_raw
		if n["card"] != null:
			refs.append(n["card"])
		elif n["special"]:
			specials.append(n)
		else:
			lines.append("%s: %s" % [n["title"], n["note"]])
	if not lines.is_empty():
		var note_text: String = "\n".join(lines)
		var note_h: float = _text_height(note_text, inner_w, NOTE_FONT)
		var note_lbl := _note_label(note_text, light)
		note_lbl.position = Vector2(PAD, bottom + GAP)
		note_lbl.size = Vector2(inner_w, note_h)
		box.add_child(note_lbl)
		bottom += GAP + note_h
	# 효과 용어 풀이 — 용어 앞에 그 아이콘이 서도록 설명문과 같은 RichTextLabel.
	for n_raw in specials:
		var n: Dictionary = n_raw
		var sp: String = "[%s]: %s" % [n["title"], n["note"]]
		var sp_refs: Array = [n["ref"]]
		var sp_h: float = _text_height(StrategyIcon.measure_text(sp, sp_refs), inner_w, NOTE_FONT)
		var sp_lbl := StrategyIcon.make_rich_label(sp, NOTE_FONT,
				OutgameTheme.TEXT_SUB if light else Color(0.70, 0.70, 0.74),
				_kw_color(light), _knock_color(light), KeywordIcon.TARGET_ANY_COLOR,
				KeywordIcon.TARGET, _special_color(light), sp_refs)
		sp_lbl.position = Vector2(PAD, bottom + GAP)
		sp_lbl.size = Vector2(inner_w, sp_h)
		box.add_child(sp_lbl)
		bottom += GAP + sp_h
	for ref in refs:
		var sub: Panel = build(ref as CardData, inner_w, light, "", null, false, 0.0, live)
		_tint_nested(sub, light)
		sub.position = Vector2(PAD, bottom + GAP)
		box.add_child(sub)
		bottom += GAP + sub.size.y

	box.size = Vector2(width, maxf(min_h, bottom + PAD))
	return box


## 키워드 풀이 판들 — 손패에서 설명판 옆에 따로 선다. **키워드 하나에 판 하나**
## (이름 한 줄(키워드 색) + 풀이)이고, 풀이가 있는 키워드 순서대로 돌려준다.
## 키워드가 둘이면 판도 둘이다 — 예전에는 한 판에 몰아 담아 어디까지가 어느
## 키워드의 풀이인지 경계가 흐렸다. 풀이가 하나도 없으면 빈 배열.
static func build_keyword_panels(data: CardData, width: float,
		light: bool = false, live: bool = true) -> Array[Panel]:
	var out: Array[Panel] = []
	if data == null:
		return out
	for n_raw in _keyword_notes(data):
		var n: Dictionary = n_raw
		if n["card"] != null:
			out.append(build(n["card"] as CardData, width, light, "", null, false, 0.0, live))
		else:
			out.append(_build_note_panel(String(n["title"]), String(n["note"]), width,
					light, n.get("ref", {}) as Dictionary))
	return out


## `special_ref` — 특수 키워드 풀이 판이면 그 참조(`CardData.ref_entries` 항목), 아니면 빈 값.
static func _build_note_panel(title_text: String, note: String, width: float,
		light: bool, special_ref: Dictionary = {}) -> Panel:
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", panel_style(light))
	var inner_w: float = width - PAD * 2.0
	var y: float = PAD
	if not special_ref.is_empty():
		# 특수 키워드 제목은 설명문과 같은 길로 — 아이콘 + 특수 키워드 색.
		var rt := StrategyIcon.make_rich_label("[%s]" % title_text, KW_FONT,
				_special_color(light), _kw_color(light), _knock_color(light),
				KeywordIcon.TARGET_ANY_COLOR, KeywordIcon.TARGET, _special_color(light),
				[special_ref])
		rt.position = Vector2(PAD, y)
		rt.size = Vector2(inner_w, float(KW_FONT) * 1.4)
		box.add_child(rt)
	else:
		var title := UiHelpers.mk_label(box, title_text, KW_FONT, _kw_color(light),
				Vector2(PAD, y), Vector2(inner_w, float(KW_FONT) * 1.4))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	y += float(KW_FONT) * 1.4
	var note_h: float = _text_height(note, inner_w, NOTE_FONT)
	var note_lbl := _note_label(note, light)
	note_lbl.position = Vector2(PAD, y)
	note_lbl.size = Vector2(inner_w, note_h)
	box.add_child(note_lbl)
	y += note_h
	box.size = Vector2(width, y + PAD)
	return box


## 풀이 판 목록 `[{title, note, special, card, ref}, ...]` — 풀이가 있는 키워드가 먼저,
## 그다음 설명문에 나온 순서대로 특수 키워드. `[x]` 는 **표시 글자가 아니라 설명 key 의
## 참조 key**(`special_terms` = `CardData.ref_entries`)로 푼다: 특수 키워드면 풀이 한 줄
## (`CardData.SPECIAL_NOTES`), 카드 이름이면 `card` 에 그 카드를 싣는다(찾지 못한 참조는
## 빠진다). 카드 이름이 자기 자신(같은 이름 key)이면 풀지 않는다(용어는 푼다 — [추적]).
static func _keyword_notes(data: CardData) -> Array:
	var out: Array = []
	for kw in data.keyword_list():
		var note: String = data.keyword_note(String(kw))
		if not note.is_empty():
			out.append({"title": data.keyword_label(String(kw)), "note": note,
					"special": false, "card": null, "ref": {}})
	for raw in special_terms(data):
		var ref: Dictionary = raw
		var sp: String = String(ref["special"])
		if CardData.SPECIAL_NOTES.has(sp):
			out.append({"title": String(ref["text"]),
					"note": Loc.t(String(CardData.SPECIAL_NOTES[sp])),  # l10n-dynamic: keyword.*.note
					"special": true, "card": null, "ref": ref})
		elif ref["card"] != null and String(ref["key"]) != data.name_key:
			out.append({"title": String(ref["text"]), "note": "", "special": true,
					"card": ref["card"], "ref": ref})
	return out


## 설명문의 `[x]` 참조(`CardData.ref_entries` 항목) — 나온 순서대로, 같은 key 는 한 번.
## 설명 key 가 없는 카드(손으로 만든 카드)는 빈 배열.
static func special_terms(data: CardData) -> Array:
	var out: Array = []
	if data == null:
		return out
	var seen: Dictionary = {}
	for raw in CardData.ref_entries(data.description_key):
		var ref: Dictionary = raw
		if seen.has(ref["key"]):
			continue
		seen[ref["key"]] = true
		out.append(ref)
	return out


## 판 안에 끼운 카드 설명판 — 바깥 판과 바탕이 같으면 경계가 안 보이므로 한 톤 띄운다.
static func _tint_nested(sub: Panel, light: bool) -> void:
	var st := (sub.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	st.bg_color = st.bg_color.darkened(0.05) if light else st.bg_color.lightened(0.07)
	st.shadow_size = 0
	sub.add_theme_stylebox_override("panel", st)


static func _special_color(light: bool) -> Color:
	return KeywordIcon.SPECIAL_COLOR_LIGHT if light else KeywordIcon.SPECIAL_COLOR_DARK


static func _kw_color(light: bool) -> Color:
	return OutgameTheme.ACCENT_TEXT if light else Color(0.55, 0.85, 1.0)


## 판 바탕색 — 필중 아이콘이 원 위의 활을 이 색으로 파낸다.
static func _knock_color(light: bool) -> Color:
	return OutgameTheme.SURFACE if light else Color(0.08, 0.08, 0.12)


## 설명문에 계산식을 채운 글 — `{식|문구}` 를 전투 중에는 값으로, 밖에서는
## "(문구)" 로 바꾸고 `\n` 을 줄바꿈으로 편다. 식을 못 풀면 문구 쪽으로 물러난다.
## `live` 를 끄면 전투 중에도 언제나 "(문구)" 쪽이다.
static func resolve_text(data: CardData, live: bool = true) -> String:
	if data == null:
		return ""
	var text: String = data.description.replace("\\n", "\n")
	if text.find("{") < 0:
		return text
	if _formula_re == null:
		_formula_re = RegEx.create_from_string("\\{([^{}|]+)\\|([^{}]+)\\}")
	var vars: Dictionary = {"charge": data.charge, "chain": 0}
	var in_battle: bool = live and live_vars.is_valid()
	if in_battle:
		vars.merge(live_vars.call(data) as Dictionary, true)
	var out: String = ""
	var last: int = 0
	for m in _formula_re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var shown: String = "(%s)" % m.get_string(2)
		if in_battle:
			var expr := Expression.new()
			if expr.parse(m.get_string(1), PackedStringArray(vars.keys())) == OK:
				var v: Variant = expr.execute(vars.values(), null, false)
				if not expr.has_execute_failed():
					shown = str(int(v))
		out += shown
		last = m.get_end()
	return out + text.substr(last)


## 카드가 겨누는 것 `{key, color, label}` — 속성 줄의 대상 항목과 설명문의 "대상"
## 아이콘이 같이 읽는다.
##   • 타일(`target = location`) — 육각 타일 아이콘. 효과가 `own_jungle` 이면 "아군
##     정글 타일"(초록), `steal_camp` 면 "적 정글 타일"(빨강), `ambush` 면 "정글 타일",
##     그 밖은 "타일"(회색). `turret_damage`(전령 제압)는 타일이 아니라 최외곽 적 포탑.
##   • 자신 — 범위형 시전자 카드, 또는 효과 절이 전부 `|self` 인 즉시 카드(몸집 불리기).
##   • 그 밖의 즉시 · 범위 카드는 대상이 없다(label 이 빈 글자).
static func target_info(data: CardData) -> Dictionary:
	var info := {"key": KeywordIcon.TARGET, "label": "",
			"color": KeywordIcon.target_color(data.target if data != null else "")}
	if data == null:
		return info
	if data.target == "location":
		if data.effect.begins_with("turret_damage"):
			info["label"] = TARGET_LABELS["turret_outer"]
			info["color"] = KeywordIcon.TARGET_ENEMY_COLOR
			return info
		info["key"] = KeywordIcon.TILE
		info["label"] = "타일"
		if data.effect.contains("own_jungle"):
			info["label"] = "아군 정글 타일"
			info["color"] = KeywordIcon.TARGET_ALLY_COLOR
		elif data.effect.contains("steal_camp"):
			info["label"] = "적 정글 타일"
			info["color"] = KeywordIcon.TARGET_ENEMY_COLOR
		elif data.effect.contains("ambush"):
			info["label"] = "정글 타일"
		return info
	if (data.cast_method == "range" and data.target == "caster") or _all_self(data):
		info["label"] = "자신"
	elif data.cast_method != "instant" and data.cast_method != "range":
		info["label"] = String(TARGET_LABELS.get(data.target, ""))
	return info


## 효과 절이 하나 이상이고 전부 `|self` 표지를 단 카드 — 자기 자신에게만 건다.
static func _all_self(data: CardData) -> bool:
	var clauses: PackedStringArray = data.effect.split(";", false)
	if clauses.is_empty():
		return false
	for c in clauses:
		if not "self" in (c as String).strip_edges().split("|"):
			return false
	return true


## 카드의 속성 `[[KeywordIcon 키, 값 글자], ...]` — 대상 · 사거리 · 시전 범위
## 순, 해당 없는 항목은 빠진다. 지속시간은 속성 줄에 없다 — 설명문이 "3턴 간
## 교전" 처럼 직접 적는다. 손패에서만 쓰는 카드(드로우 · 전략 점수)는
## 대개 빈 배열이라 줄 자체가 서지 않는다.
##   • 대상     — `target` (적 / 아군 / 적 또는 포탑 / 타일 / 자신 …)
##   • 사거리   — 대상 · 칸 지정 카드의 `cast_range` (99 이상 = 전장)
##   • 시전 범위 — `area` 컬럼과 효과의 `area` · `around_target` · `self_range`
##                 반경, 교전 절의 반경(기본 1) 중 가장 큰 값
static func card_attributes(data: CardData) -> Array:
	var out: Array = []
	if data == null:
		return out
	var tgt: Dictionary = target_info(data)
	if not String(tgt["label"]).is_empty():
		out.append([tgt["key"], tgt["label"]])
	if data.cast_method == "target" or data.cast_method == "location":
		var rng: String = "전장" if data.cast_range >= CardTargetingOverlay.UNLIMITED_RANGE \
				else str(data.cast_range)
		out.append([KeywordIcon.RANGE, rng])
	var radius: int = data.area
	for clause_raw in data.effect.split(";", false):
		var parts: PackedStringArray = (clause_raw as String).strip_edges().split("|", false)
		if parts.is_empty():
			continue
		if parts[0].split(":")[0].strip_edges() == "engage":
			radius = maxi(radius, 1)
		for i in range(1, parts.size()):
			var flag: PackedStringArray = parts[i].strip_edges().split(":")
			if flag.size() < 2:
				continue
			var fv: int = int(flag[1])
			if flag[0] in ["area", "around_target", "self_range"]:
				radius = maxi(radius, fv)
	if radius > 0:
		out.append([KeywordIcon.AREA, str(radius)])
	return out


## 속성 줄 — `[아이콘] 값` 덩어리를 가운데 정렬로 늘어놓는다.
static func _attr_label(attrs: Array, light: bool, target_col: Color) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.scroll_active = false
	rtl.clip_contents = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", KW_FONT)
	rtl.add_theme_color_override("default_color",
			OutgameTheme.TEXT if light else Color(0.92, 0.92, 0.92))
	var icon_px: int = int(round(float(KW_FONT) * 1.25))
	rtl.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	for i in attrs.size():
		var a: Array = attrs[i]
		if i > 0:
			rtl.add_text(ATTR_SEP)
		var tex: Texture2D = KeywordIcon.texture(String(a[0]), icon_px * 2,
				KeywordIcon.color_for(String(a[0]), _kw_color(light), target_col),
				_knock_color(light))
		if tex != null:
			rtl.add_image(tex, icon_px, icon_px, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		rtl.add_text(_attr_value(String(a[1])))
	rtl.pop()
	return rtl


## 항목 하나(아이콘 + 값)는 줄이 갈리지 않게 묶는다 — 공백은 줄 안 끊김 공백,
## 글자 사이는 `keep_words` 의 단어 결합자("2턴" 이 "2" / "턴" 으로 갈리지 않게).
static func _attr_value(value: String) -> String:
	return UiHelpers.keep_words(StrategyIcon.NBSP + value.replace(" ", StrategyIcon.NBSP))


## `_attr_label` 의 높이 측정용 대역 — 아이콘(글자 크기 × 1.25)과 그 옆 여백을
## 글자 세 개 폭으로 넉넉히 친다. 모자라게 재면 접힌 줄이 설명문을 덮는다.
static func _attr_measure(attrs: Array) -> String:
	var parts: Array = []
	for a in attrs:
		parts.append(UiHelpers.keep_words("000" + _attr_value(String((a as Array)[1]))))
	return ATTR_SEP.join(parts)


static func _note_label(text: String, light: bool) -> Label:
	var note_lbl := Label.new()
	note_lbl.text = UiHelpers.keep_words(text)
	note_lbl.add_theme_font_size_override("font_size", NOTE_FONT)
	note_lbl.add_theme_color_override("font_color",
			OutgameTheme.TEXT_SUB if light else Color(0.70, 0.70, 0.74))
	note_lbl.add_theme_constant_override("line_spacing", 0)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return note_lbl


## 카드 한 장(`card_rect`, 화면 좌표)에 판을 붙인다 — 기본은 아래, `prefer_above`
## 면 위이고, 그쪽에 자리가 없으면 반대쪽으로 넘어간다. 가로는 카드 중심에
## 맞추되 화면 밖으로 안 나간다. 판이 설 고정 자리가 없는 화면(찾기 · 더미 열람 ·
## 메크 상세)이 쓴다.
static func place_near(box: Control, card_rect: Rect2, screen: Vector2,
		prefer_above: bool = false, gap: float = 10.0) -> void:
	var x: float = clampf(card_rect.get_center().x - box.size.x * 0.5,
			8.0, maxf(8.0, screen.x - box.size.x - 8.0))
	var below: float = card_rect.end.y + gap
	var above: float = card_rect.position.y - gap - box.size.y
	var y: float
	if prefer_above:
		y = above if above >= 8.0 else below
	else:
		y = below if below + box.size.y <= screen.y - 8.0 else above
	box.position = Vector2(x, clampf(y, 8.0, maxf(8.0, screen.y - box.size.y - 8.0)))


static func _text_height(text: String, w: float, font_size: int) -> float:
	var f: Font = ThemeDB.fallback_font
	if f == null or text.is_empty():
		return float(font_size) * 1.4
	text = UiHelpers.keep_words(text)
	var brk: int = (TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			| TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_EDGE_SPACES)
	return ceilf(f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
			w, font_size, -1, brk).y) + 4.0


static func _text_width(text: String, font_size: int) -> float:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return float(font_size) * float(text.length())
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
