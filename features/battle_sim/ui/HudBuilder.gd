class_name HudBuilder
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ── Role → icon background color ──────────────────────────────────────────────
const ROLE_COLORS := [
	Color(0.2, 0.4, 0.9),   # TANK
	Color(0.9, 0.5, 0.1),   # FIGHTER
	Color(0.6, 0.1, 0.8),   # ASSASSIN
	Color(0.1, 0.7, 0.3),   # SUPPORT
	Color(0.8, 0.2, 0.1),   # SNIPER
]

# ── Board layout constants ─────────────────────────────────────────────────────
const SLOT_W      := 192.0
const SLOT_GAP    := 8.0
# Centres 5 slots horizontally across 1080px with equal side margins (~44px each).
const BOARD_LEFT  := (1080.0 - 5.0 * SLOT_W - 4.0 * SLOT_GAP) * 0.5
const ICON_SIZE   := 60.0
const BAR_H       := 22.0
const BOARD_PAD_Y := 8.0   # inner top padding inside each board panel

# ── Pilot slot refs (internal to HudBuilder) ──────────────────────────────────
var _enemy_slots:  Array = []   # [{icon_bg, icon_lbl, bar, dead_lbl}, …] team 1
var _allied_slots: Array = []   # [{icon_bg, icon_lbl, bar, dead_lbl}, …] team 0


func build_ui() -> void:
	_bs.canvas = CanvasLayer.new()
	_bs.add_child(_bs.canvas)

	# ── Top board — enemy pilots ───────────────────────────────────────────────
	var tp := Panel.new()
	tp.position = Vector2(0.0, 150.0)
	tp.size     = Vector2(1080.0, 110.0)
	_bs.canvas.add_child(tp)
	_enemy_slots = _build_board(tp)

	# ── Bottom panel — allied pilots + controls ────────────────────────────────
	var bp := Panel.new()
	bp.position = Vector2(0.0, 1530.0)
	bp.size     = Vector2(1080.0, 270.0)
	_bs.canvas.add_child(bp)

	# Allied pilot board sits at top of the bottom panel.
	_allied_slots = _build_board(bp)

	# Controls start below the pilot board (board bottom ≈ BOARD_PAD_Y + ICON_SIZE + 4 + BAR_H = 94px).
	const CTRL_Y := 104.0

	_bs.btn_next = Button.new()
	_bs.btn_next.text = "Next Turn"
	_bs.btn_next.position = Vector2(20.0, CTRL_Y)
	_bs.btn_next.size     = Vector2(220.0, 70.0)
	_bs.btn_next.add_theme_font_size_override("font_size", 26)
	_bs.btn_next.pressed.connect(_bs._on_next_turn_pressed)
	bp.add_child(_bs.btn_next)

	_bs._btn_auto = Button.new()
	_bs._btn_auto.text = "Auto Play ▶"
	_bs._btn_auto.position = Vector2(260.0, CTRL_Y)
	_bs._btn_auto.size     = Vector2(260.0, 70.0)
	_bs._btn_auto.add_theme_font_size_override("font_size", 26)
	_bs._btn_auto.pressed.connect(_bs._on_auto_play_pressed)
	bp.add_child(_bs._btn_auto)

	_bs.lbl_log = Label.new()
	_bs.lbl_log.add_theme_font_size_override("font_size", 22)
	_bs.lbl_log.position = Vector2(20.0, CTRL_Y + 80.0)
	_bs.lbl_log.size     = Vector2(1040.0, 40.0)
	bp.add_child(_bs.lbl_log)

	# Card phase widgets (right side of bottom panel, same row as buttons)
	_bs.lbl_cost_bs = Label.new()
	_bs.lbl_cost_bs.text = "Cost: 0"
	_bs.lbl_cost_bs.add_theme_font_size_override("font_size", 26)
	_bs.lbl_cost_bs.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_bs.lbl_cost_bs.position             = Vector2(700.0, CTRL_Y)
	_bs.lbl_cost_bs.size                 = Vector2(360.0, 44.0)
	_bs.lbl_cost_bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bp.add_child(_bs.lbl_cost_bs)

	_bs.btn_end_card_phase = Button.new()
	_bs.btn_end_card_phase.text = "End Phase"
	_bs.btn_end_card_phase.position = Vector2(700.0, CTRL_Y)
	_bs.btn_end_card_phase.size     = Vector2(360.0, 70.0)
	_bs.btn_end_card_phase.add_theme_font_size_override("font_size", 26)
	_bs.btn_end_card_phase.pressed.connect(_bs._card_phase.end_card_phase)
	_bs.btn_end_card_phase.visible  = false
	bp.add_child(_bs.btn_end_card_phase)

	# ── Victory panel ──────────────────────────────────────────────────────────
	_bs._panel_victory = Panel.new()
	_bs._panel_victory.position = Vector2(190.0, 760.0)
	_bs._panel_victory.size     = Vector2(700.0, 400.0)
	_bs._panel_victory.visible  = false
	_bs.canvas.add_child(_bs._panel_victory)

	_bs.lbl_victory = Label.new()
	_bs.lbl_victory.add_theme_font_size_override("font_size", 48)
	_bs.lbl_victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs.lbl_victory.position = Vector2(0.0, 80.0)
	_bs.lbl_victory.size     = Vector2(700.0, 80.0)
	_bs._panel_victory.add_child(_bs.lbl_victory)

	var rb := Button.new()
	rb.text = "Play Again"
	rb.position = Vector2(200.0, 240.0)
	rb.size     = Vector2(300.0, 80.0)
	rb.add_theme_font_size_override("font_size", 32)
	rb.pressed.connect(_bs._on_restart_pressed)
	_bs._panel_victory.add_child(rb)


# Builds 5 pilot slots inside `parent`, starting at BOARD_PAD_Y from the top.
# Returns an Array of slot Dictionaries.
func _build_board(parent: Control) -> Array:
	var slots := []
	for i in range(5):
		var sx := BOARD_LEFT + i * (SLOT_W + SLOT_GAP)
		slots.append(_build_slot(parent, sx, BOARD_PAD_Y))
	return slots


func _build_slot(parent: Control, x: float, y: float) -> Dictionary:
	var icon_x := x + (SLOT_W - ICON_SIZE) * 0.5

	var icon_bg := ColorRect.new()
	icon_bg.position = Vector2(icon_x, y)
	icon_bg.size     = Vector2(ICON_SIZE, ICON_SIZE)
	icon_bg.color    = Color(0.3, 0.3, 0.3)
	icon_bg.visible  = false
	parent.add_child(icon_bg)

	var icon_lbl := Label.new()
	icon_lbl.text = ""
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.add_theme_color_override("font_color", Color.WHITE)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(icon_x, y)
	icon_lbl.size     = Vector2(ICON_SIZE, ICON_SIZE)
	icon_lbl.visible  = false
	parent.add_child(icon_lbl)

	var bar := ProgressBar.new()
	bar.position        = Vector2(x, y + ICON_SIZE + 4.0)
	bar.size            = Vector2(SLOT_W, BAR_H)
	bar.min_value       = 0.0
	bar.max_value       = 100.0
	bar.value           = 0.0
	bar.show_percentage = false
	bar.visible         = false
	parent.add_child(bar)

	var dead_lbl := Label.new()
	dead_lbl.text = "DEAD"
	dead_lbl.add_theme_font_size_override("font_size", 14)
	dead_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_lbl.position = Vector2(x, y + ICON_SIZE + 4.0)
	dead_lbl.size     = Vector2(SLOT_W, BAR_H)
	dead_lbl.visible  = false
	parent.add_child(dead_lbl)

	return {"icon_bg": icon_bg, "icon_lbl": icon_lbl, "bar": bar, "dead_lbl": dead_lbl}


func update_hud() -> void:
	_bs.lbl_log.text = _bs.last_log
	if _bs.lbl_cost_bs:
		_bs.lbl_cost_bs.text = "Cost: %d" % _bs._player_cost
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	_bs.btn_next.visible  = _bs.game_phase == GameEnums.BattlePhase.BATTLE
	_bs._btn_auto.visible = _bs.game_phase == GameEnums.BattlePhase.BATTLE
	if _bs.btn_end_card_phase:
		_bs.btn_end_card_phase.visible = in_card_phase
	_update_pilot_boards()


func _update_pilot_boards() -> void:
	var team0: Array = []
	var team1: Array = []
	for p in _bs.pilots:
		var pd := p as PilotData
		if pd.team == 0:
			team0.append(pd)
		else:
			team1.append(pd)
	# Sort by LanePosition (LEFT=0, CENTER=1, RIGHT=2, GUERRILLA=3).
	team0.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.lane < b.lane)
	team1.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.lane < b.lane)
	_apply_slots(_allied_slots, team0)
	_apply_slots(_enemy_slots, team1)


func _apply_slots(slots: Array, sorted_pilots: Array) -> void:
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if i >= sorted_pilots.size():
			slot.icon_bg.visible  = false
			slot.icon_lbl.visible = false
			slot.bar.visible      = false
			slot.dead_lbl.visible = false
			continue

		var pd: PilotData = sorted_pilots[i]
		var role_color: Color = ROLE_COLORS[pd.role] if pd.role < ROLE_COLORS.size() \
				else Color(0.5, 0.5, 0.5)

		slot.icon_bg.visible  = true
		slot.icon_lbl.visible = true
		slot.bar.visible      = true
		slot.icon_lbl.text    = _bs.ROLE_NAMES[pd.role] if pd.role < _bs.ROLE_NAMES.size() else "?"

		if pd.alive:
			slot.icon_bg.color    = role_color
			slot.bar.value        = float(pd.hp) / float(pd.max_hp) * 100.0
			slot.dead_lbl.visible = false
		else:
			# Luminance-based grayscale so the desaturated shape is still visible.
			var lum := role_color.r * 0.299 + role_color.g * 0.587 + role_color.b * 0.114
			slot.icon_bg.color    = Color(lum, lum, lum)
			slot.bar.value        = 0.0
			slot.dead_lbl.visible = true


func mk_label(parent: Control, text: String, font_size: int, color: Color,
		pos: Vector2, sz: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size     = sz
	l.horizontal_alignment = align as HorizontalAlignment
	parent.add_child(l)
	return l
