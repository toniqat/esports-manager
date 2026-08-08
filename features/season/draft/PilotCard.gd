class_name PilotCard
extends Button

# Single-pilot card used in the team draft grid. Builds its own children
# procedurally on first setup() so callers don't need to instance a .tscn.
# Fires `card_tapped(pilot_id)` on press; selection styling is driven by
# `set_selected()` from the parent view.

signal card_tapped(pilot_id: int)

const CARD_W: float = 200.0
const CARD_H: float = 175.0

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),   # TANK    blue
	Color(1.00, 0.55, 0.20),   # FIGHTER orange
	Color(0.75, 0.40, 1.00),   # ASSASSIN purple
	Color(0.30, 0.85, 0.45),   # SUPPORT green
	Color(1.00, 0.35, 0.35),   # SNIPER  red
]

const STAT_LABELS: Array = ["L", "M", "G", "T", "N"]
const STAT_COLOR: Color = Color(0.55, 0.85, 1.00)

var pilot: PlayerData = null

var _selected: bool = false
var _built: bool = false

var _name_lbl: Label
var _sub_lbl: Label
var _face_rect: TextureRect
var _stat_fills: Array = []   # Array[ColorRect] (5)
var _stat_value_lbls: Array = []  # Array[Label] (5)


func _team_short(team_id: int) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return "T%d" % team_id
	var meta: Array = gm.season_state.get("team_meta", [])
	if team_id < 0 or team_id >= meta.size():
		return "T%d" % team_id
	return String(meta[team_id]["short_name"])


func setup(p: PlayerData, sel: bool) -> void:
	pilot = p
	if not _built:
		_build()
		_built = true
	_refresh()
	set_selected(sel)


func set_selected(sel: bool) -> void:
	_selected = sel
	_apply_style()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	size               = Vector2(CARD_W, CARD_H)
	focus_mode         = Control.FOCUS_NONE
	clip_text          = true
	text               = ""

	pressed.connect(_on_pressed)

	_face_rect = TextureRect.new()
	_face_rect.position = Vector2(8, 6)
	_face_rect.size     = Vector2(48, 48)
	_face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face_rect)

	_name_lbl = UiHelpers.mk_label(self, "", 20, Color(1, 1, 1),
			Vector2(64, 6), Vector2(CARD_W - 72, 26))
	_name_lbl.add_theme_constant_override("outline_size", 2)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))

	_sub_lbl = UiHelpers.mk_label(self, "", 14, Color(0.85, 0.85, 0.9),
			Vector2(64, 34), Vector2(CARD_W - 72, 20))

	# 5 stat bars
	var bar_y_start: float = 60.0
	var bar_h: float       = 17.0
	for i in 5:
		var y := bar_y_start + i * bar_h
		UiHelpers.mk_label(self, STAT_LABELS[i], 12, Color(0.7, 0.7, 0.8),
				Vector2(8, y + 1), Vector2(14, 14))

		var bar_bg := ColorRect.new()
		bar_bg.color        = Color(0.10, 0.12, 0.18, 1.0)
		bar_bg.position     = Vector2(26, y + 3)
		bar_bg.size         = Vector2(132, 10)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar_bg)

		var bar_fill := ColorRect.new()
		bar_fill.color        = STAT_COLOR
		bar_fill.position     = Vector2(26, y + 3)
		bar_fill.size         = Vector2(0, 10)
		bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar_fill)
		_stat_fills.append(bar_fill)

		var v_lbl := UiHelpers.mk_label(self, "", 12, Color(0.95, 0.95, 1.0),
				Vector2(162, y), Vector2(30, 16), HORIZONTAL_ALIGNMENT_RIGHT)
		_stat_value_lbls.append(v_lbl)


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh() -> void:
	if pilot == null:
		_name_lbl.text = ""
		_sub_lbl.text  = ""
		_face_rect.texture = null
		return

	_name_lbl.text = pilot.name
	_face_rect.texture = PilotImages.face_for(pilot.id)

	var role_name: String = ROLE_NAMES[pilot.role] if pilot.role >= 0 and pilot.role < ROLE_NAMES.size() else "?"
	var role_col: Color = ROLE_COLORS[pilot.role] if pilot.role >= 0 and pilot.role < ROLE_COLORS.size() else Color(1, 1, 1)
	_sub_lbl.text = "%s • %s" % [role_name, _team_short(pilot.team_id)]
	_sub_lbl.add_theme_color_override("font_color", role_col)

	var stats: Array = [pilot.laning, pilot.mechanics, pilot.gamesense, pilot.teamfight, pilot.mental]
	for i in 5:
		var v: int = clamp(int(stats[i]), 0, 100)
		var fill: ColorRect = _stat_fills[i]
		fill.size.x = 132.0 * (float(v) / 100.0)
		_stat_value_lbls[i].text = str(v)


func _apply_style() -> void:
	var bg := StyleBoxFlat.new()
	bg.corner_radius_top_left     = 6
	bg.corner_radius_top_right    = 6
	bg.corner_radius_bottom_left  = 6
	bg.corner_radius_bottom_right = 6

	if _selected:
		bg.bg_color     = Color(0.20, 0.32, 0.55, 1.0)
		bg.border_color = Color(1.00, 0.85, 0.20, 1.0)
	else:
		bg.bg_color     = Color(0.13, 0.15, 0.22, 1.0)
		bg.border_color = Color(0.30, 0.32, 0.40, 1.0)
	bg.border_width_left   = 3
	bg.border_width_right  = 3
	bg.border_width_top    = 3
	bg.border_width_bottom = 3

	add_theme_stylebox_override("normal",   bg)
	add_theme_stylebox_override("hover",    bg)
	add_theme_stylebox_override("pressed",  bg)
	add_theme_stylebox_override("focus",    bg)
	add_theme_stylebox_override("disabled", bg)


func _on_pressed() -> void:
	if pilot != null:
		card_tapped.emit(pilot.id)
