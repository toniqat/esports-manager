class_name CardDescBox
extends RefCounted

# 카드 한 장의 **설명판** — 이름 · 비용 · 키워드 · 설명문 · 키워드 풀이.
#
# **키워드는 설명문에 다시 적지 않는다.** 판이 이름 아래에 키워드 줄(소멸 ·
# 재배치 · 충전 5 …)을 세우고, 맨 아래에 키워드마다 한 줄 풀이를 단다 — 그래서
# 설명문에는 그 카드만의 효과만 남아 짧아진다.
#
# 카드 앞면에서 설명문이 걷히면서(`Card.gd` 앞면 두 층) 그 글을 들 자리가 화면마다
# 필요해졌다: 손패는 가리킨 카드 위(`CardPhaseManager`), 밴픽 시트와 메크 상세는
# 누른 카드 위다. 세 곳이 같은 판을 쓰도록 짓는 일만 여기 모은다 — **자리는
# 부르는 쪽이 정한다**(판의 크기는 내용이 정하므로 `build` 가 돌려준 `size` 를
# 보고 아랫변을 맞춘다).
#
# 두 벌의 색이 있다 — 인게임(어두운 전장 위) / 아웃게임(흰 배경, `OutgameTheme`).
# 아웃게임 화면이 인게임 색을 쓰면 흰 화면 한가운데에 검은 판이 뜨고, 그 반대면
# 전장 위에 흰 판이 뜬다.

const PAD := 14.0
const HEADER_H := 32.0
const GAP := 8.0
const NAME_FONT := 22
const COST_FONT := 26
const DESC_FONT := 18
const KW_FONT := 18
const NOTE_FONT := 15
## 설명이 아무리 짧아도 판이 이 높이 아래로 줄지 않는다 — 한 줄짜리 카드에서
## 판이 띠처럼 납작해지면 카드마다 판 크기가 들쭉날쭉해 보인다.
const MIN_H := 110.0


## `cost_text` / `cost_color` 를 비워 두면 카드의 인쇄 비용(사용 불가면 `—`)을 찍는다.
## 손패는 할인 · 증세가 먹은 실제 비용을 넘긴다.
static func build(data: CardData, width: float, light: bool = false,
		cost_text: String = "", cost_color: Variant = null) -> Panel:
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat
	if light:
		style = OutgameTheme.card_style(14)
		style.border_color = OutgameTheme.ACCENT
		style.set_border_width_all(2)
	else:
		style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
		style.border_color = Color(0.95, 0.85, 0.45, 1.0)
		style.set_border_width_all(2)
		OutgameTheme.set_corner_radius(style, 12)
	box.add_theme_stylebox_override("panel", style)
	if data == null:
		box.size = Vector2(width, MIN_H)
		return box

	var name_col: Color = OutgameTheme.TEXT if light else Color(1.0, 0.95, 0.55)
	var desc_col: Color = OutgameTheme.TEXT_SUB if light else Color(0.92, 0.92, 0.92)
	var inner_w: float = width - PAD * 2.0

	if cost_text == "":
		cost_text = Card.UNPLAYABLE_COST_TEXT if not data.is_playable() else str(data.cost)
	var cost_col: Color = cost_color if cost_color is Color \
			else (OutgameTheme.ACCENT_TEXT if light else Card.COST_COLOR_BASE)

	var cost_lbl := UiHelpers.mk_label(box, cost_text, COST_FONT, cost_col,
			Vector2(PAD, PAD - 2.0), Vector2(inner_w, HEADER_H), HORIZONTAL_ALIGNMENT_RIGHT)
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := UiHelpers.mk_label(box, data.card_name, NAME_FONT, name_col,
			Vector2(PAD, PAD), Vector2(inner_w - 48.0, HEADER_H))
	name_lbl.clip_text = true
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
		var kw_col: Color = OutgameTheme.ACCENT_TEXT if light else Color(0.55, 0.85, 1.0)
		var kw_lbl := UiHelpers.mk_label(box, " · ".join(tags), KW_FONT, kw_col,
				Vector2(PAD, desc_y), Vector2(inner_w, float(KW_FONT) * 1.4))
		kw_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_y += float(KW_FONT) * 1.4 + 4.0
	var desc_h: float = _text_height(data.description, inner_w, DESC_FONT)
	var desc := Label.new()
	desc.text = data.description
	desc.add_theme_font_size_override("font_size", DESC_FONT)
	desc.add_theme_color_override("font_color", desc_col)
	desc.add_theme_constant_override("line_spacing", 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(PAD, desc_y)
	desc.size = Vector2(inner_w, desc_h)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)

	# 키워드 풀이 — 키워드마다 한 줄. 설명문보다 작고 흐리게.
	var bottom: float = desc_y + desc_h
	var notes: Array = []
	for kw in kws:
		var note: String = data.keyword_note(String(kw))
		if not note.is_empty():
			notes.append("%s: %s" % [data.keyword_label(String(kw)), note])
	if not notes.is_empty():
		var note_text: String = "\n".join(notes)
		var note_h: float = _text_height(note_text, inner_w, NOTE_FONT)
		var note_col: Color = OutgameTheme.TEXT_SUB if light else Color(0.70, 0.70, 0.74)
		var note_lbl := Label.new()
		note_lbl.text = note_text
		note_lbl.add_theme_font_size_override("font_size", NOTE_FONT)
		note_lbl.add_theme_color_override("font_color", note_col)
		note_lbl.add_theme_constant_override("line_spacing", 0)
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_lbl.position = Vector2(PAD, bottom + GAP)
		note_lbl.size = Vector2(inner_w, note_h)
		note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(note_lbl)
		bottom += GAP + note_h

	box.size = Vector2(width, maxf(MIN_H, bottom + PAD))
	return box


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
	var brk: int = (TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			| TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_EDGE_SPACES)
	return ceilf(f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
			w, font_size, -1, brk).y) + 4.0
