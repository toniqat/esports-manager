class_name ManagerUi
extends RefCounted

# Shared building blocks of the lobby `감독` tab (`ManagerTab`) and the run setup
# `감독` step (`run_setup/ManagerStepView`): preset names, the read-only six-stat
# row, preset numerals, stat icons and the text of a trait unlock condition (plan §12.4 grammar).
# The preset capsule is the `UI_Comp_ManagerPresetChips.tscn` scene; the trait block is
# `UI_Comp_TraitPickerView.tscn`.
# Pure UI helpers — rules stay in `ManagerProgress` / `TraitSystem`.

const STAT_CELL_H: float = 120.0


const ROMAN: Array = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const STAT_ICON_DIR: String = "res://resources/images/ui/manager/stat_%s.svg"


## "프리셋 III" — the numeral is the one the preset capsule shows.
static func preset_name(idx: int) -> String:
	return Loc.t(L.MANAGER_PRESET_NAME, {"n": roman(idx + 1)})


## 1 → "I" … 10 → "X" (`PRESET_MAX_COUNT` = 10); past the table the plain number.
static func roman(n: int) -> String:
	return String(ROMAN[n - 1]) if n >= 1 and n <= ROMAN.size() else str(n)


## White glyph of a manager stat (`StaffSystem.STATS` key) — tint it with `self_modulate`.
static func stat_icon(stat: String) -> Texture2D:
	var path: String = STAT_ICON_DIR % stat
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


# ── Read-only stats ──────────────────────────────────────────────────────────
## Six cells (`StaffSystem.STATS` order): stat icon + label, value, and the specialisation part
## (`value − base`, just "+n") under it. Returns the height.
static func add_stat_cells(parent: Control, pos: Vector2, width: float,
		stats: Dictionary, base: Dictionary) -> float:
	var n: int = StaffSystem.STATS.size()
	var cell_w: float = width / float(n)
	for i in n:
		var key: String = String(StaffSystem.STATS[i])
		var cell := Panel.new()
		cell.add_theme_stylebox_override("panel",
				OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 12))
		cell.position = pos + Vector2(float(i) * cell_w + 4.0, 0)
		cell.size = Vector2(cell_w - 8.0, STAT_CELL_H)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cell)
		# Head row: icon (white glyph tinted like the label) + stat name, centred together.
		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_theme_constant_override("separation", 4)
		head.position = Vector2(0, 8)
		head.size = Vector2(cell_w - 8.0, 28)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(head)
		var icon := TextureRect.new()
		icon.texture = stat_icon(key)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.self_modulate = OutgameTheme.TEXT_SUB
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(icon)
		var name_lbl := Label.new()
		name_lbl.text = StaffSystem.stat_label(key)
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(name_lbl)
		var v: int = int(stats.get(key, StaffSystem.STAT_MIN))
		var spec: int = v - int(base.get(key, v))
		UiHelpers.mk_label(cell, str(v), 38,
				OutgameTheme.ACCENT_TEXT if spec > 0 else OutgameTheme.TEXT,
				Vector2(0, 36), Vector2(cell_w - 8.0, 48), HORIZONTAL_ALIGNMENT_CENTER)
		if spec > 0:
			UiHelpers.mk_label(cell, signed(spec), 18, OutgameTheme.ACCENT_TEXT,
					Vector2(0, 86), Vector2(cell_w - 8.0, 24), HORIZONTAL_ALIGNMENT_CENTER)
	return STAT_CELL_H


# ── Bonus points ─────────────────────────────────────────────────────────────
static func signed(n: int) -> String:
	return ("+%d" % n) if n > 0 else str(n)


## "보너스 점수 +3" colour: red < 0, green > 0, grey 0.
static func bonus_color(bonus: int) -> Color:
	if bonus < 0:
		return OutgameTheme.NEGATIVE
	return OutgameTheme.POSITIVE if bonus > 0 else OutgameTheme.TEXT_SUB


# ── Unlock condition text (plan §12.4) ───────────────────────────────────────
## `traits.unlock` → readable text (current locale). Empty = obtained only from gacha / crafting.
## Unknown tokens fall back to the raw string so a new condition is never hidden.
static func unlock_text(cond: String) -> String:
	var c: String = cond.strip_edges()
	if c == "":
		return Loc.t(L.MANAGER_UNLOCK_GACHA)
	var parts: PackedStringArray = c.split(":", false, 1)
	var key: String = parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	var n: int = int(arg)
	match key:
		"clear":                 return Loc.t(L.MANAGER_UNLOCK_CLEAR)
		"true_ending":           return Loc.t(L.MANAGER_UNLOCK_TRUE_ENDING)
		"wins":                  return Loc.t(L.MANAGER_UNLOCK_WINS, {"n": n})
		"titles":                return Loc.t(L.MANAGER_UNLOCK_TITLES, {"n": n})
		"phase":                 return Loc.t(L.MANAGER_UNLOCK_PHASE, {"n": n})
		"win_streak":            return Loc.t(L.MANAGER_UNLOCK_WIN_STREAK, {"n": n})
		"outings":               return Loc.t(L.MANAGER_UNLOCK_OUTINGS, {"n": n})
		"mvp":                   return Loc.t(L.MANAGER_UNLOCK_MVP, {"n": n})
		"finance_manual_profit": return Loc.t(L.MANAGER_UNLOCK_FINANCE_MANUAL_PROFIT, {"n": n})
		"runs":                  return Loc.t(L.MANAGER_UNLOCK_RUNS, {"n": n})
		"team":                  return Loc.t(L.MANAGER_UNLOCK_TEAM, {"team": _team_name(n)})
		"bonus":                 return Loc.t(L.MANAGER_UNLOCK_BONUS, {"n": n})
	return c


static func _team_name(team_id: int) -> String:
	return RunRules.team_name(team_id)
