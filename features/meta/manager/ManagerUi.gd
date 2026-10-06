class_name ManagerUi
extends RefCounted

# Shared building blocks of the lobby `감독` tab (`ManagerTab`) and the run setup
# `감독` step (`run_setup/ManagerStepView`): preset chips, the read-only six-stat
# row and the Korean text of a trait unlock condition (plan §12.4 grammar).
# Pure UI helpers — rules stay in `ManagerProgress` / `TraitSystem`.

const CHIP_COLS: int = 5
const CHIP_H: float = 104.0
const CHIP_GAP: float = 12.0
const STAT_CELL_H: float = 120.0


static func preset_name(idx: int) -> String:
	return "프리셋 %d" % (idx + 1)


# ── Preset chips ─────────────────────────────────────────────────────────────
## One chip per preset (CHIP_COLS per row). `on_pressed(idx)` fires on tap.
## Chip = name + status line: 사용 중 (active) / 재설정 필요 (prestige kind) /
## 특성 n. `selected` gets the amber frame. Returns the block height.
static func add_preset_chips(parent: Control, pos: Vector2, width: float,
		profile: Dictionary, selected: int, on_pressed: Callable) -> float:
	var ps: Array = ManagerProgress.presets(profile)
	var active: int = ManagerProgress.active_index(profile)
	var chip_w: float = (width - CHIP_GAP * float(CHIP_COLS - 1)) / float(CHIP_COLS)
	var rows: int = int(ceil(float(ps.size()) / float(CHIP_COLS)))
	for i in ps.size():
		var p: Dictionary = ps[i]
		var col: int = i % CHIP_COLS
		var row: int = floori(float(i) / float(CHIP_COLS))
		var b := Button.new()
		b.text = ""
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.position = pos + Vector2(float(col) * (chip_w + CHIP_GAP), float(row) * (CHIP_H + CHIP_GAP))
		b.size = Vector2(chip_w, CHIP_H)
		var on: bool = i == selected
		var sty := OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if on else OutgameTheme.SURFACE, 16,
				OutgameTheme.ACCENT if on else OutgameTheme.BORDER, 4 if on else 2)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, sty)
		b.pressed.connect(on_pressed.bind(i))
		parent.add_child(b)
		var name_lbl := UiHelpers.mk_label(b, preset_name(i), 26,
				OutgameTheme.TEXT if on else OutgameTheme.TEXT_SUB,
				Vector2(0, 14), Vector2(chip_w, 36), HORIZONTAL_ALIGNMENT_CENTER)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var status: String = "특성 %d" % (p.get("traits", []) as Array).size()
		var col_s: Color = OutgameTheme.TEXT_FAINT
		if String(p.get("kind", ManagerProgress.KIND_NORMAL)) == ManagerProgress.KIND_PRESTIGE:
			status = "재설정 필요"
			col_s = OutgameTheme.NEGATIVE
		elif i == active:
			status = "● 사용 중"
			col_s = OutgameTheme.ACCENT_TEXT
		var st_lbl := UiHelpers.mk_label(b, status, 20, col_s,
				Vector2(0, 56), Vector2(chip_w, 30), HORIZONTAL_ALIGNMENT_CENTER)
		st_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return float(rows) * CHIP_H + float(maxi(0, rows - 1)) * CHIP_GAP


# ── Read-only stats ──────────────────────────────────────────────────────────
## Six cells (`StaffSystem.STATS` order): label, value, and the specialisation part
## (`value − base`, "+n") under it. Returns the height.
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
		UiHelpers.mk_label(cell, String(StaffSystem.STAT_LABELS.get(key, key)), 20,
				OutgameTheme.TEXT_SUB, Vector2(0, 8), Vector2(cell_w - 8.0, 28),
				HORIZONTAL_ALIGNMENT_CENTER)
		var v: int = int(stats.get(key, StaffSystem.STAT_MIN))
		var spec: int = v - int(base.get(key, v))
		UiHelpers.mk_label(cell, str(v), 38,
				OutgameTheme.ACCENT_TEXT if spec > 0 else OutgameTheme.TEXT,
				Vector2(0, 36), Vector2(cell_w - 8.0, 48), HORIZONTAL_ALIGNMENT_CENTER)
		if spec > 0:
			UiHelpers.mk_label(cell, "전문화 +%d" % spec, 16, OutgameTheme.ACCENT_TEXT,
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
## `traits.unlock` → readable Korean. Empty = obtained only from gacha / crafting.
## Unknown tokens fall back to the raw string so a new condition is never hidden.
static func unlock_text(cond: String) -> String:
	var c: String = cond.strip_edges()
	if c == "":
		return "특성 가챠 · 제작으로 획득"
	var parts: PackedStringArray = c.split(":", false, 1)
	var key: String = parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	var n: int = int(arg)
	match key:
		"clear":                 return "런 클리어 (최종 국제전 우승)"
		"true_ending":           return "진엔딩 달성"
		"wins":                  return "한 런에서 %d승" % n
		"titles":                return "한 런에서 우승 %d회" % n
		"phase":                 return "한 런에서 페이즈 %d개 통과" % n
		"win_streak":            return "한 런에서 %d연승" % n
		"outings":               return "한 선수와 외출 %d회 (한 런)" % n
		"mvp":                   return "한 런에서 내 선수 MVP %d회" % n
		"finance_manual_profit": return "감독이 직접 관리해 흑자 %d주 (한 런)" % n
		"runs":                  return "런 %d회 완료" % n
		"team":                  return "%s 팀으로 한 페이즈 이상 마치기" % _team_name(n)
		"bonus":                 return "보너스 점수 %d 이상으로 한 페이즈 이상 마치기" % n
	return c


static func _team_name(team_id: int) -> String:
	for raw in RunRules.team_packages():
		var t: Dictionary = raw
		if int(t.get("id", -1)) == team_id:
			return String(t.get("name", "팀 %d" % team_id))
	return "팀 %d" % team_id
