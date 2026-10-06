class_name IntelView
extends RefCounted

# Draws an `OpponentIntel.build()` result on white outgame paper. Shared by the
# MatchFlow PREP screen and the league team detail sheet, so both read the same
# reveal rule the same way. Every function places children at absolute
# coordinates under `parent` and returns the height it used.

const ROW_GAP: float = 10.0
const ROW_BASE_H: float = 104.0
const LINE_H: float = 34.0
const PORTRAIT: float = 76.0


## Header line: tier chip + what the next tier needs. Nothing for the own team.
static func add_tier_header(parent: Control, pos: Vector2, w: float, intel: Dictionary) -> float:
	if bool(intel.get("own", false)):
		return 0.0
	var tier: int = int(intel["tier"])
	var chip_text: String = "분석 %d단계 · %s" % [tier, intel["tier_label"]]
	var chip_w: float = 36.0 + chip_text.length() * 16.0
	var full: bool = tier >= OpponentIntel.FULL
	OutgameTheme.add_chip(parent, chip_text, pos, Vector2(chip_w, 40),
			OutgameTheme.ACCENT_DIM if full else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if full else OutgameTheme.TEXT, 20)
	if not full:
		var need: int = int(intel.get("next_need", 0))
		UiHelpers.mk_label(parent, "내 분석 %d · 다음 단계 %d 필요" % [int(intel.get("analysis", 0)), need],
				18, OutgameTheme.TEXT_SUB,
				Vector2(pos.x + chip_w + 14.0, pos.y + 8.0), Vector2(w - chip_w - 14.0, 26))
	return 52.0


## Analyst note. Delegated → amber card with the analyst's lines; manager-owned
## → one faint line saying the reading is the player's job. Own team → nothing.
static func add_analyst_note(parent: Control, pos: Vector2, w: float, intel: Dictionary) -> float:
	if bool(intel.get("own", false)):
		return 0.0
	if not bool(intel.get("delegated", false)):
		UiHelpers.mk_label(parent, "분석 담당 없음 — 데이터만 보입니다. 해석은 감독이 직접.",
				20, OutgameTheme.TEXT_SUB, pos, Vector2(w, 30))
		return 40.0
	var card := Panel.new()
	card.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.ACCENT_DIM, 14))
	card.position = pos
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	UiHelpers.mk_label(card, "분석 · %s" % intel["analyst"], 20, OutgameTheme.ACCENT_TEXT,
			Vector2(20, 12), Vector2(w - 40, 28))
	var y: float = 46.0
	for raw in (intel.get("notes", []) as Array):
		var l := UiHelpers.mk_label(card, UiHelpers.keep_words(String(raw)), 22,
				OutgameTheme.TEXT, Vector2(20, y), Vector2(w - 40, 30))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var lines: int = maxi(1, l.get_line_count())
		l.size.y = 30.0 * lines
		y += 30.0 * lines + 4.0
	card.size = Vector2(w, y + 10.0)
	return card.size.y + ROW_GAP


## Five pilot rows. Returns the total height.
static func add_rows(parent: Control, pos: Vector2, w: float, intel: Dictionary) -> float:
	var y: float = pos.y
	for raw in (intel.get("rows", []) as Array):
		y += add_pilot_row(parent, Vector2(pos.x, y), w, raw) + ROW_GAP
	return y - pos.y


## One pilot row: portrait · role · name · total, six stat cells, then the
## mech line (tier >= 2) and the card line (tier 3).
static func add_pilot_row(parent: Control, pos: Vector2, w: float, row: Dictionary) -> float:
	var role: int = int(row["role"])
	var role_col: Color = OutgameTheme.ROLE_COLORS[clampi(role, 0, 4)]
	var h: float = ROW_BASE_H
	if bool(row["show_mechs"]):
		h += LINE_H
	if bool(row["show_cards"]):
		h += LINE_H
	if h > ROW_BASE_H:
		h += 8.0

	var card := Panel.new()
	card.add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(role_col, 14))
	card.position = pos
	card.size = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)

	OutgameTheme.add_round_portrait(card, PilotImages.face_for(int(row["pilot_id"])),
			Vector2(18, (ROW_BASE_H - PORTRAIT) * 0.5), PORTRAIT, role_col)

	var stats_x: float = maxf(330.0, w * 0.40)
	var name_w: float = stats_x - 116.0
	UiHelpers.mk_label(card, String(row["role_label"]), 18, role_col,
			Vector2(108, 10), Vector2(name_w, 24))
	var nm := UiHelpers.mk_label(card, String(row["name"]), 26, OutgameTheme.TEXT,
			Vector2(108, 32), Vector2(name_w, 34))
	nm.clip_text = true
	UiHelpers.mk_label(card, "합계 %s" % row["total_text"], 18,
			OutgameTheme.TEXT_SUB if bool(row["show_stats"]) else OutgameTheme.TEXT_FAINT,
			Vector2(108, 68), Vector2(name_w, 24))

	var stats: Array = row["stats"]
	var n: int = maxi(1, stats.size())
	var cell_w: float = (w - stats_x - 14.0) / float(n)
	var exact: bool = bool(row["exact"])
	var shown: bool = bool(row["show_stats"])
	for i in stats.size():
		var c: Dictionary = stats[i]
		var x: float = stats_x + i * cell_w
		UiHelpers.mk_label(card, String(c["label"]), 16, OutgameTheme.TEXT_SUB,
				Vector2(x, 18), Vector2(cell_w, 22), HORIZONTAL_ALIGNMENT_CENTER)
		var font: int = 28 if exact else (19 if shown else 26)
		UiHelpers.mk_label(card, String(c["text"]), font,
				OutgameTheme.TEXT if shown else OutgameTheme.TEXT_FAINT,
				Vector2(x, 44), Vector2(cell_w, 36), HORIZONTAL_ALIGNMENT_CENTER)

	var y: float = ROW_BASE_H - 4.0
	if bool(row["show_mechs"]):
		var parts: Array = []
		for raw in (row["mechs"] as Array):
			parts.append(String((raw as Dictionary)["text"]))
		_add_line(card, "주력 메크", " · ".join(parts) if not parts.is_empty() else "정보 없음",
				Vector2(18, y), w - 36)
		y += LINE_H
	if bool(row["show_cards"]):
		var names: Array = row["cards"]
		_add_line(card, "파일럿 카드", " · ".join(names) if not names.is_empty() else "정보 없음",
				Vector2(18, y), w - 36)
	return h


static func _add_line(card: Control, head: String, body: String, pos: Vector2, w: float) -> void:
	UiHelpers.mk_label(card, head, 18, OutgameTheme.TEXT_SUB, pos + Vector2(0, 4), Vector2(130, 26))
	var l := UiHelpers.mk_label(card, body, 21, OutgameTheme.TEXT,
			pos + Vector2(134, 0), Vector2(w - 134, 30))
	l.clip_text = true
