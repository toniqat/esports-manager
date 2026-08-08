class_name EngageOverlay
extends Control

# 전투 개시 모달 오버레이.
# EngagePhaseManager 가 인스턴스를 만들어 _bs.canvas 의 자식으로 attach 하고
# setup() / show_attack() / show_round_banner() / show_dashboard() 를 호출한다.
# UI 만 담당; 게임 상태 변경은 모두 매니저 쪽에서 한다.

# ─── Layout constants ────────────────────────────────────────────────────────
const VP_W: float = 1080.0
const VP_H: float = 1920.0
const COL_GAP: float       = 60.0
const COL_W: float         = 460.0
const COL_TOP: float       = 220.0
const ROW_H: float         = 88.0
const ROW_GAP: float       = 12.0
const HP_BAR_H: float      = 14.0
const NAME_FONT_SIZE: int  = 26
const TITLE_FONT_SIZE: int = 40
const ROUND_FONT_SIZE: int = 56

const TEAM_COLORS := [
	Color(0.32, 0.62, 0.95),   # team 0 (player)
	Color(0.95, 0.40, 0.32),   # team 1 (enemy)
]
const ROW_BG       := Color(0.10, 0.12, 0.18, 0.92)
const ROW_BG_DEAD  := Color(0.18, 0.10, 0.10, 0.92)
const ROW_OUTLINE  := Color(1.0, 0.9, 0.4, 1.0)   # active attacker outline
const ROW_OUTLINE_TARGET := Color(0.95, 0.30, 0.30, 1.0)
const HP_BAR_BG    := Color(0.06, 0.06, 0.08, 1.0)
const HP_BAR_FILL  := Color(0.30, 0.85, 0.45, 1.0)
const SHIELD_FILL  := Color(0.85, 0.85, 0.30, 0.85)
const TITLE_COLOR  := Color(1.0, 0.95, 0.55, 1.0)

# ─── Refs ────────────────────────────────────────────────────────────────────
var _bs: BattleSim
var _team_pilots: Array = [[], []]
var _initiator_team: int = 0
var _rounds_total: int = 0
var _title_text: String = "전투 개시"
var _is_duel: bool = false

var _title_lbl: Label
var _round_lbl: Label
var _round_banner: Label
# Per-pilot row UI: row_data[pilot] = {row: Panel, name: Label, hp_bar: ColorRect,
#   hp_fill: ColorRect, shield_fill: ColorRect, outline: ColorRect}
var _row_data: Dictionary = {}
# Dashboard panel — built lazily in show_dashboard.
var _dashboard: Panel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks behind the modal
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Dim background.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)


# Called by EngagePhaseManager once participants are gathered. Builds the
# two-column roster view and the title.
func setup(bs: BattleSim, team0: Array, team1: Array,
		initiator_team: int, rounds_total: int,
		title_text: String = "전투 개시", is_duel: bool = false) -> void:
	_bs = bs
	_team_pilots[0] = team0
	_team_pilots[1] = team1
	_initiator_team = initiator_team
	_rounds_total = rounds_total
	_title_text = title_text
	_is_duel = is_duel
	_build_ui()


func _build_ui() -> void:
	_title_lbl = _make_label(_title_text, TITLE_FONT_SIZE, TITLE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	_title_lbl.position = Vector2(0, 100)
	_title_lbl.size = Vector2(VP_W, 56)
	add_child(_title_lbl)

	_round_lbl = _make_label("0 / %d 라운드" % _rounds_total, 28,
			Color(0.92, 0.92, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	_round_lbl.position = Vector2(0, 160)
	_round_lbl.size = Vector2(VP_W, 36)
	# 결투 hides the round counter — fight runs to first KO.
	_round_lbl.visible = not _is_duel
	add_child(_round_lbl)

	# Initiator marker on the column header.
	var col_x: Array = [
		(VP_W - COL_W * 2.0 - COL_GAP) * 0.5,
		(VP_W - COL_W * 2.0 - COL_GAP) * 0.5 + COL_W + COL_GAP,
	]
	for t in range(2):
		var hdr_text: String = "팀 0" if t == 0 else "팀 1"
		if t == _initiator_team:
			hdr_text += "  (시전)"
		var hdr := _make_label(hdr_text, 24, TEAM_COLORS[t],
				HORIZONTAL_ALIGNMENT_CENTER)
		hdr.position = Vector2(col_x[t], COL_TOP - 36)
		hdr.size = Vector2(COL_W, 30)
		add_child(hdr)

	for t in range(2):
		var pilots: Array = _team_pilots[t]
		for i in pilots.size():
			var p := pilots[i] as PilotData
			_build_row(p, col_x[t], COL_TOP + float(i) * (ROW_H + ROW_GAP), t)

	# Round banner (hidden by default; flashed via show_round_banner).
	_round_banner = _make_label("", ROUND_FONT_SIZE,
			Color(1.0, 0.95, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_round_banner.position = Vector2(0, VP_H * 0.5 - 60)
	_round_banner.size = Vector2(VP_W, 80)
	_round_banner.visible = false
	add_child(_round_banner)


func _build_row(p: PilotData, x: float, y: float, team: int) -> void:
	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(COL_W, ROW_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# Outline rect (drawn behind the inner content via a sibling ColorRect).
	var outline := ColorRect.new()
	outline.position = Vector2(x - 4, y - 4)
	outline.size = Vector2(COL_W + 8, ROW_H + 8)
	outline.color = Color(0, 0, 0, 0)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outline)
	# Move the outline below the panel so it acts like a frame.
	move_child(outline, panel.get_index())

	# Pilot label "TANK0  (HP 220/220)" — name on left, HP text on right.
	var name_lbl := _make_label(_pilot_text(p), NAME_FONT_SIZE,
			TEAM_COLORS[team], HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(14, 8)
	name_lbl.size = Vector2(COL_W - 28, 32)
	panel.add_child(name_lbl)

	# Presence chip on the right side of the name row.
	var pres_lbl := _make_label("존재감 %d" % p.presence, 16,
			Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	pres_lbl.position = Vector2(14, 8)
	pres_lbl.size = Vector2(COL_W - 28, 24)
	panel.add_child(pres_lbl)

	# HP bar background.
	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(14, ROW_H - HP_BAR_H - 12)
	hp_bg.size = Vector2(COL_W - 28, HP_BAR_H)
	hp_bg.color = HP_BAR_BG
	panel.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.position = hp_bg.position
	hp_fill.size = Vector2(hp_bg.size.x * _hp_ratio(p), HP_BAR_H)
	hp_fill.color = HP_BAR_FILL
	panel.add_child(hp_fill)
	var shield_fill := ColorRect.new()
	shield_fill.position = Vector2(hp_bg.position.x + hp_fill.size.x, hp_bg.position.y)
	shield_fill.size = Vector2(0.0, HP_BAR_H)
	shield_fill.color = SHIELD_FILL
	panel.add_child(shield_fill)

	_row_data[p] = {
		"row": panel,
		"name": name_lbl,
		"hp_bg": hp_bg,
		"hp_fill": hp_fill,
		"shield_fill": shield_fill,
		"outline": outline,
		"team": team,
	}


# ─── Public API used by EngagePhaseManager ──────────────────────────────────
func show_round_banner(round_idx: int, rounds_total: int) -> void:
	if _round_lbl != null:
		_round_lbl.text = "%d / %d 라운드" % [round_idx, rounds_total]
	if _round_banner == null:
		return
	_round_banner.text = "라운드 %d" % round_idx
	_round_banner.visible = true
	_round_banner.modulate = Color(1, 1, 1, 1)
	# Fade out across the round-delay window so the next attack starts on a
	# clean canvas.
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(_round_banner, "modulate",
			Color(1, 1, 1, 0), 0.3)


func show_attack(attacker: PilotData, target: PilotData,
		did_hit: bool, dmg: int, killed: bool) -> void:
	# Highlight attacker outline (yellow), target outline (red).
	_set_outline(attacker, ROW_OUTLINE)
	_set_outline(target,   ROW_OUTLINE_TARGET)
	_refresh_row(target)  # HP/shield update immediately
	if killed:
		_mark_dead(target)
	# Damage / miss popup near the target row.
	_spawn_damage_popup(target, did_hit, dmg, killed)
	# Clear outlines after a short hold so the next attack's highlight is clean.
	var tw := create_tween()
	tw.tween_interval(0.30)
	tw.tween_callback(Callable(self, "_clear_outline").bind(attacker))
	tw.tween_callback(Callable(self, "_clear_outline").bind(target))


func show_dashboard(team0: Array, team1: Array, stats: Dictionary,
		on_confirm: Callable) -> void:
	# Hide the round banner so it doesn't bleed into the dashboard.
	if _round_banner != null:
		_round_banner.visible = false

	_dashboard = Panel.new()
	var DASH_W := 940.0
	var DASH_H := 1240.0
	_dashboard.position = Vector2((VP_W - DASH_W) * 0.5, (VP_H - DASH_H) * 0.5)
	_dashboard.size = Vector2(DASH_W, DASH_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	sb.border_color = Color(1.0, 0.9, 0.4, 1.0)
	sb.border_width_top    = 3
	sb.border_width_bottom = 3
	sb.border_width_left   = 3
	sb.border_width_right  = 3
	sb.corner_radius_top_left     = 16
	sb.corner_radius_top_right    = 16
	sb.corner_radius_bottom_left  = 16
	sb.corner_radius_bottom_right = 16
	_dashboard.add_theme_stylebox_override("panel", sb)
	add_child(_dashboard)

	var title := _make_label("전투 결과", TITLE_FONT_SIZE,
			TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 24)
	title.size = Vector2(DASH_W, 56)
	_dashboard.add_child(title)

	# Column header row.
	var hdr_y: float = 96.0
	_dashboard_header_row(hdr_y, DASH_W)

	var y: float = hdr_y + 40.0
	for t in range(2):
		var team_pilots: Array = team0 if t == 0 else team1
		var team_lbl := _make_label("팀 %d" % t, 22, TEAM_COLORS[t],
				HORIZONTAL_ALIGNMENT_LEFT)
		team_lbl.position = Vector2(28, y)
		team_lbl.size = Vector2(DASH_W - 56, 28)
		_dashboard.add_child(team_lbl)
		y += 32.0
		for raw in team_pilots:
			var p := raw as PilotData
			var s: Dictionary = stats.get(p, {"dealt": 0, "taken": 0, "kills": 0})
			_dashboard_row(p, s, y, DASH_W)
			y += 36.0
		y += 16.0

	var btn := Button.new()
	btn.text = "확인"
	btn.add_theme_font_size_override("font_size", 28)
	btn.position = Vector2((DASH_W - 240.0) * 0.5, DASH_H - 96.0)
	btn.size = Vector2(240, 64)
	btn.pressed.connect(on_confirm)
	_dashboard.add_child(btn)


# ─── Helpers ─────────────────────────────────────────────────────────────────
func _make_label(text: String, font_size: int, color: Color,
		halign: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _pilot_text(p: PilotData) -> String:
	return "%s  HP %d/%d" % [_bs.pilot_label(p), p.hp, p.max_hp]


func _hp_ratio(p: PilotData) -> float:
	if p.max_hp <= 0:
		return 0.0
	return clamp(float(p.hp) / float(p.max_hp), 0.0, 1.0)


func _refresh_row(p: PilotData) -> void:
	var row: Dictionary = _row_data.get(p, {})
	if row.is_empty():
		return
	(row["name"] as Label).text = _pilot_text(p)
	var bg := row["hp_bg"] as ColorRect
	var fill := row["hp_fill"] as ColorRect
	var shield_fill := row["shield_fill"] as ColorRect
	var ratio: float = _hp_ratio(p)
	var fill_w: float = bg.size.x * ratio
	# Tween the HP bar smoothly.
	var tw := create_tween()
	tw.tween_property(fill, "size:x", fill_w, 0.20)
	# Shield is rendered to the right of the HP fill.
	var shield_w: float = 0.0
	if p.shield > 0 and p.max_hp > 0:
		shield_w = bg.size.x * clamp(float(p.shield) / float(p.max_hp), 0.0, 1.0)
	shield_fill.position = Vector2(bg.position.x + fill_w, bg.position.y)
	shield_fill.size = Vector2(shield_w, bg.size.y)


func _mark_dead(p: PilotData) -> void:
	var row: Dictionary = _row_data.get(p, {})
	if row.is_empty():
		return
	var panel := row["row"] as Panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG_DEAD
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	(row["name"] as Label).text = "%s  (KO)" % _bs.pilot_label(p)


func _set_outline(p: PilotData, color: Color) -> void:
	var row: Dictionary = _row_data.get(p, {})
	if row.is_empty():
		return
	(row["outline"] as ColorRect).color = color


func _clear_outline(p: PilotData) -> void:
	var row: Dictionary = _row_data.get(p, {})
	if row.is_empty():
		return
	(row["outline"] as ColorRect).color = Color(0, 0, 0, 0)


# Float-up "-DMG" or "MISS" label spawned over the target row.
func _spawn_damage_popup(target: PilotData, did_hit: bool,
		dmg: int, killed: bool) -> void:
	var row: Dictionary = _row_data.get(target, {})
	if row.is_empty():
		return
	var panel := row["row"] as Panel
	var lbl := _make_label("", 36,
			Color(1, 0.4, 0.4) if did_hit else Color(0.85, 0.85, 0.85),
			HORIZONTAL_ALIGNMENT_CENTER)
	if did_hit:
		lbl.text = ("-%d  KO!" % dmg) if killed else ("-%d" % dmg)
		lbl.add_theme_color_override("font_color",
				Color(1, 0.85, 0.30) if killed else Color(1, 0.4, 0.4))
	else:
		lbl.text = "MISS"
	lbl.size = Vector2(panel.size.x, 50)
	lbl.position = Vector2(panel.position.x, panel.position.y - 6)
	add_child(lbl)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y",
			lbl.position.y - 50.0, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))


func _dashboard_header_row(y: float, dash_w: float) -> void:
	var cols := [
		{"text": "파일럿", "x": 28.0,  "w": 240.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
		{"text": "준 딜량",  "x": 270.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"text": "받은 딜량","x": 470.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"text": "처치",   "x": 670.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]
	for c in cols:
		var lbl := _make_label(String(c["text"]), 20,
				Color(0.8, 0.8, 0.8), int(c["align"]))
		lbl.position = Vector2(float(c["x"]), y)
		lbl.size = Vector2(float(c["w"]), 28)
		_dashboard.add_child(lbl)


func _dashboard_row(p: PilotData, s: Dictionary, y: float, dash_w: float) -> void:
	var team_color: Color = TEAM_COLORS[p.team]
	var name_lbl := _make_label("%s  (HP %d/%d)" % [_bs.pilot_label(p), p.hp, p.max_hp],
			20, team_color, HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(28, y)
	name_lbl.size = Vector2(240, 28)
	_dashboard.add_child(name_lbl)

	_dashboard.add_child(_stat_cell(int(s["dealt"]), 270.0, y, 200.0))
	_dashboard.add_child(_stat_cell(int(s["taken"]), 470.0, y, 200.0))
	_dashboard.add_child(_stat_cell(int(s["kills"]), 670.0, y, 200.0))

	if not p.alive:
		name_lbl.modulate = Color(0.7, 0.5, 0.5)


func _stat_cell(value: int, x: float, y: float, w: float) -> Label:
	var lbl := _make_label(str(value), 22,
			Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, 28)
	return lbl
