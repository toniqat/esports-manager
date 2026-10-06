class_name TraitPickerView
extends Control

# Trait block shared by the lobby `감독` tab and the run setup `감독` step:
#
#   특성 ······································· 장착 n / TRAIT_SLOTS
#   ┌ 보너스 점수 +3  (제공 +x · 소모 −y)  — red when < 0 ┐
#   [slot] [slot] [slot] [slot]        ← tap an equipped slot = unequip
#   보유 특성 n — rows (tap = equip / unequip)
#   잠긴 특성 n — greyed rows + unlock condition (`ManagerUi.unlock_text`)
#
# It only draws and reports taps (`trait_pressed(id)`); the owner applies the rule
# (`ManagerProgress.toggle_trait`) and calls `build()` again. Lives inside the
# owner's `DragScroll` body, so every tap target is a `MOUSE_FILTER_PASS` Button.
# Positive traits consume bonus points, negative ones provide them (plan §12.0).

signal trait_pressed(trait_id: int)

const TITLE_H: float = 44.0
const GAUGE_H: float = 104.0
const SLOT_H: float = 112.0
const SLOT_GAP: float = 12.0
const SECTION_H: float = 44.0
const ROW_H: float = 112.0
const ROW_LOCKED_H: float = 140.0
const ROW_GAP: float = 10.0
const ROW_PAD: float = 24.0
const BADGE: float = 52.0


## Rebuilds the whole block for `width`. `equipped` / `owned` / `new_ids` are
## Array[int]. Returns (and sets) the block height.
func build(width: float, equipped: Array, owned: Array, new_ids: Array) -> float:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var y: float = 0.0

	var slots: int = TraitSystem.slot_count()
	UiHelpers.mk_label(self, "특성", 30, OutgameTheme.TEXT, Vector2(0, y), Vector2(width * 0.5, TITLE_H))
	UiHelpers.mk_label(self, "장착 %d / %d" % [equipped.size(), slots], 24,
			OutgameTheme.NEGATIVE if equipped.size() > slots else OutgameTheme.TEXT_SUB,
			Vector2(width * 0.5, y + 6.0), Vector2(width * 0.5, 34), HORIZONTAL_ALIGNMENT_RIGHT)
	y += TITLE_H + 8.0

	y += _build_gauge(Vector2(0, y), width, equipped) + 16.0
	y += _build_slots(Vector2(0, y), width, equipped, slots) + 24.0

	var owned_rows: Array = []
	var locked_rows: Array = []
	for raw in TraitSystem.rows():
		var r: Dictionary = raw
		if owned.has(int(r["id"])):
			owned_rows.append(r)
		else:
			locked_rows.append(r)
	# Owned: positives first, then negatives (each in id order) — the pick is
	# "what do I want" then "what do I pay with".
	owned_rows.sort_custom(func(a, b) -> bool:
		var pa: bool = String(a["polarity"]) == TraitSystem.POLARITY_POS
		var pb: bool = String(b["polarity"]) == TraitSystem.POLARITY_POS
		if pa != pb:
			return pa
		return int(a["id"]) < int(b["id"]))

	UiHelpers.mk_label(self, "보유 특성 %d — 눌러서 장착 / 해제" % owned_rows.size(), 24,
			OutgameTheme.TEXT_SUB, Vector2(4, y), Vector2(width, SECTION_H - 8.0))
	y += SECTION_H
	for r in owned_rows:
		var tid: int = int((r as Dictionary)["id"])
		y += _build_row(Vector2(0, y), width, r, equipped.has(tid), true, new_ids.has(tid)) + ROW_GAP
	if not locked_rows.is_empty():
		y += 14.0
		UiHelpers.mk_label(self, "잠긴 특성 %d" % locked_rows.size(), 24,
				OutgameTheme.TEXT_SUB, Vector2(4, y), Vector2(width, SECTION_H - 8.0))
		y += SECTION_H
		for r in locked_rows:
			y += _build_row(Vector2(0, y), width, r, false, false, false) + ROW_GAP
	y -= ROW_GAP
	size = Vector2(width, y)
	custom_minimum_size = size
	return y


# ── Pieces ───────────────────────────────────────────────────────────────────
func _build_gauge(pos: Vector2, width: float, equipped: Array) -> float:
	var provided: int = 0
	var consumed: int = 0
	for raw in equipped:
		var r: Dictionary = TraitSystem.row(int(raw))
		if r.is_empty():
			continue
		if String(r["polarity"]) == TraitSystem.POLARITY_POS:
			consumed += int(r["bonus_cost"])
		else:
			provided += int(r["bonus_cost"])
	var bonus: int = TraitSystem.bonus_points(equipped)
	var bad: bool = bonus < 0
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			OutgameTheme.NEGATIVE.lightened(0.88) if bad else OutgameTheme.SURFACE, 16,
			OutgameTheme.NEGATIVE if bad else OutgameTheme.BORDER, 3 if bad else 1))
	card.position = pos
	card.size = Vector2(width, GAUGE_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	UiHelpers.mk_label(card, "보너스 점수", 24, OutgameTheme.TEXT_SUB,
			Vector2(ROW_PAD, 12), Vector2(260, 32))
	UiHelpers.mk_label(card, ManagerUi.signed(bonus), 40, ManagerUi.bonus_color(bonus),
			Vector2(ROW_PAD, 38), Vector2(200, 58))
	var note: String = "부정 특성 제공 +%d · 긍정 특성 소모 −%d" % [provided, consumed]
	UiHelpers.mk_label(card, note, 22, OutgameTheme.TEXT_SUB,
			Vector2(260, 14), Vector2(width - 260 - ROW_PAD, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	var rule: String = "0 미만이면 저장 · 사용할 수 없습니다" if bad \
			else "남는 점수는 런 점수에 더해집니다"
	UiHelpers.mk_label(card, rule, 22, OutgameTheme.NEGATIVE if bad else OutgameTheme.TEXT_FAINT,
			Vector2(260, 50), Vector2(width - 260 - ROW_PAD, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	return GAUGE_H


func _build_slots(pos: Vector2, width: float, equipped: Array, slots: int) -> float:
	var n: int = maxi(slots, equipped.size())
	var w: float = (width - SLOT_GAP * float(n - 1)) / float(n)
	for i in n:
		var p := pos + Vector2(float(i) * (w + SLOT_GAP), 0)
		if i >= equipped.size():
			var empty := Panel.new()
			empty.add_theme_stylebox_override("panel",
					OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 14, OutgameTheme.BORDER, 1))
			empty.position = p
			empty.size = Vector2(w, SLOT_H)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(empty)
			var l := UiHelpers.mk_label(empty, "빈 칸", 22, OutgameTheme.TEXT_FAINT,
					Vector2.ZERO, Vector2(w, SLOT_H), HORIZONTAL_ALIGNMENT_CENTER)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			continue
		var tid: int = int(equipped[i])
		var r: Dictionary = TraitSystem.row(tid)
		var pos_pol: bool = String(r.get("polarity", "+")) == TraitSystem.POLARITY_POS
		var b := _tap_button(p, Vector2(w, SLOT_H), OutgameTheme.flat_style(
				OutgameTheme.SURFACE, 14, OutgameTheme.BORDER_STRONG if i < slots
				else OutgameTheme.NEGATIVE, 2))
		b.pressed.connect(func() -> void: trait_pressed.emit(tid))
		var strip := ColorRect.new()
		strip.color = _pol_color(pos_pol)
		strip.position = Vector2(2, 14)
		strip.size = Vector2(6, SLOT_H - 28.0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(strip)
		var name_lbl := UiHelpers.mk_label(b, String(r.get("name", "?")), 24, OutgameTheme.TEXT,
				Vector2(16, 16), Vector2(w - 24, 34), HORIZONTAL_ALIGNMENT_CENTER)
		name_lbl.clip_text = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost := UiHelpers.mk_label(b, _cost_text(r), 20, _pol_color(pos_pol),
				Vector2(16, 58), Vector2(w - 24, 30), HORIZONTAL_ALIGNMENT_CENTER)
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return SLOT_H


func _build_row(pos: Vector2, width: float, r: Dictionary, on: bool, is_owned: bool,
		is_new: bool) -> float:
	var tid: int = int(r["id"])
	var h: float = ROW_H if is_owned else ROW_LOCKED_H
	var pos_pol: bool = String(r["polarity"]) == TraitSystem.POLARITY_POS
	var sty: StyleBoxFlat
	if on:
		sty = OutgameTheme.flat_style(OutgameTheme.ACCENT_DIM, 16, OutgameTheme.ACCENT, 3)
	elif is_owned:
		sty = OutgameTheme.flat_style(OutgameTheme.SURFACE, 16, OutgameTheme.BORDER, 1)
	else:
		sty = OutgameTheme.flat_style(OutgameTheme.BG, 16, OutgameTheme.BORDER, 1)
	var b := _tap_button(pos, Vector2(width, h), sty)
	b.pressed.connect(func() -> void: trait_pressed.emit(tid))

	var fg: Color = OutgameTheme.TEXT if is_owned else OutgameTheme.TEXT_FAINT
	var sub: Color = OutgameTheme.TEXT_SUB if is_owned else OutgameTheme.TEXT_FAINT
	# Polarity badge.
	var badge := Panel.new()
	badge.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			_pol_color(pos_pol) if is_owned else OutgameTheme.BORDER_STRONG, int(BADGE * 0.5)))
	badge.position = Vector2(ROW_PAD, 24)
	badge.size = Vector2(BADGE, BADGE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(badge)
	var sign_lbl := UiHelpers.mk_label(badge, "+" if pos_pol else "−", 34, OutgameTheme.TEXT_ON_FILL,
			Vector2(0, -2), Vector2(BADGE, BADGE), HORIZONTAL_ALIGNMENT_CENTER)
	sign_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var x: float = ROW_PAD + BADGE + 20.0
	var right_w: float = 210.0
	var text_w: float = width - x - right_w - ROW_PAD
	var name_lbl := UiHelpers.mk_label(b, String(r["name"]), 28, fg, Vector2(x, 14), Vector2(240, 40))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Measured with the font directly — a Label outside the tree may not resolve its theme.
	var name_w: float = minf(240.0, ThemeDB.fallback_font.get_string_size(
			String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x)
	var cx: float = x + name_w + 14.0
	_chip(b, TraitSystem.rarity_name(int(r["rarity"])), Vector2(cx, 20), 78,
			TraitUi.rarity_color(int(r["rarity"])), OutgameTheme.TEXT_ON_FILL)
	cx += 90.0
	_chip(b, "아웃게임" if String(r["layer"]) == TraitSystem.LAYER_OUTGAME else "인게임",
			Vector2(cx, 20), 96, OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT_SUB)
	cx += 108.0
	if is_new:
		_chip(b, "NEW", Vector2(cx, 20), 70, OutgameTheme.NEGATIVE, OutgameTheme.TEXT_ON_FILL)
	var desc := UiHelpers.mk_label(b, TraitSystem.desc_of(tid), 22, sub,
			Vector2(x, 60), Vector2(text_w, 32))
	desc.clip_text = true
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_owned:
		var un := UiHelpers.mk_label(b, "해금 조건 · " +ManagerUi.unlock_text(String(r["unlock"])), 22,
				OutgameTheme.ACCENT_TEXT, Vector2(x, 96), Vector2(width - x - ROW_PAD, 32))
		un.clip_text = true
		un.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cost := UiHelpers.mk_label(b, _cost_text(r), 22, _pol_color(pos_pol) if is_owned else sub,
			Vector2(width - right_w - ROW_PAD, 18), Vector2(right_w, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		_chip(b, "장착 중", Vector2(width - ROW_PAD - 110.0, 58), 110,
				OutgameTheme.ACCENT, OutgameTheme.TEXT_ON_FILL)
	return h


func _tap_button(pos: Vector2, sz: Vector2, sty: StyleBoxFlat) -> Button:
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.position = pos
	b.size = sz
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sty)
	add_child(b)
	return b


func _chip(parent: Control, text: String, pos: Vector2, w: float, bg: Color, fg: Color) -> void:
	var p: Panel = OutgameTheme.add_chip(parent, text, pos, Vector2(w, 32), bg, fg, 18)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _cost_text(r: Dictionary) -> String:
	var c: int = int(r.get("bonus_cost", 0))
	if String(r.get("polarity", "+")) == TraitSystem.POLARITY_POS:
		return "보너스 −%d" % c
	return "보너스 +%d" % c


static func _pol_color(positive: bool) -> Color:
	return OutgameTheme.POSITIVE if positive else OutgameTheme.NEGATIVE
