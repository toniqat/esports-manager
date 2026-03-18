class_name HudBuilder
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func build_ui() -> void:
	_bs.canvas = CanvasLayer.new()
	_bs.add_child(_bs.canvas)

	# ── Top panel ──────────────────────────────────────────────────────────────
	var tp := Panel.new()
	tp.position = Vector2(0.0, 0.0)
	tp.size = Vector2(1080.0, 120.0)
	_bs.canvas.add_child(tp)

	_bs.lbl_enemy_hq = Label.new()
	_bs.lbl_enemy_hq.text = "Enemy HQ: %d / %d" % [_bs.HQ_MAX_HP, _bs.HQ_MAX_HP]
	_bs.lbl_enemy_hq.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_bs.lbl_enemy_hq.add_theme_font_size_override("font_size", 28)
	_bs.lbl_enemy_hq.position = Vector2(20.0, 10.0)
	_bs.lbl_enemy_hq.size     = Vector2(600.0, 50.0)
	tp.add_child(_bs.lbl_enemy_hq)

	_bs.lbl_turn = Label.new()
	_bs.lbl_turn.text = "Turn: 0"
	_bs.lbl_turn.add_theme_font_size_override("font_size", 28)
	_bs.lbl_turn.position = Vector2(780.0, 10.0)
	_bs.lbl_turn.size     = Vector2(260.0, 50.0)
	tp.add_child(_bs.lbl_turn)

	# ── Bottom panel ───────────────────────────────────────────────────────────
	var bp := Panel.new()
	bp.position = Vector2(0.0, 1650.0)
	bp.size     = Vector2(1080.0, 270.0)
	_bs.canvas.add_child(bp)

	_bs.lbl_player_hq = Label.new()
	_bs.lbl_player_hq.text = "Your HQ: %d / %d" % [_bs.HQ_MAX_HP, _bs.HQ_MAX_HP]
	_bs.lbl_player_hq.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	_bs.lbl_player_hq.add_theme_font_size_override("font_size", 28)
	_bs.lbl_player_hq.position = Vector2(20.0, 10.0)
	_bs.lbl_player_hq.size     = Vector2(600.0, 50.0)
	bp.add_child(_bs.lbl_player_hq)

	_bs.btn_next = Button.new()
	_bs.btn_next.text = "Next Turn"
	_bs.btn_next.position = Vector2(20.0, 65.0)
	_bs.btn_next.size     = Vector2(220.0, 70.0)
	_bs.btn_next.add_theme_font_size_override("font_size", 26)
	_bs.btn_next.pressed.connect(_bs._on_next_turn_pressed)
	bp.add_child(_bs.btn_next)

	_bs._btn_auto = Button.new()
	_bs._btn_auto.text = "Auto Play ▶"
	_bs._btn_auto.position = Vector2(260.0, 65.0)
	_bs._btn_auto.size     = Vector2(260.0, 70.0)
	_bs._btn_auto.add_theme_font_size_override("font_size", 26)
	_bs._btn_auto.pressed.connect(_bs._on_auto_play_pressed)
	bp.add_child(_bs._btn_auto)

	_bs.lbl_log = Label.new()
	_bs.lbl_log.add_theme_font_size_override("font_size", 22)
	_bs.lbl_log.position = Vector2(20.0, 150.0)
	_bs.lbl_log.size     = Vector2(1040.0, 40.0)
	bp.add_child(_bs.lbl_log)

	# Card phase widgets — top-right of bottom panel
	_bs.lbl_cost_bs = Label.new()
	_bs.lbl_cost_bs.text = "Cost: 0"
	_bs.lbl_cost_bs.add_theme_font_size_override("font_size", 26)
	_bs.lbl_cost_bs.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_bs.lbl_cost_bs.position              = Vector2(700.0, 10.0)
	_bs.lbl_cost_bs.size                  = Vector2(360.0, 44.0)
	_bs.lbl_cost_bs.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	bp.add_child(_bs.lbl_cost_bs)

	_bs.btn_end_card_phase = Button.new()
	_bs.btn_end_card_phase.text = "End Phase"
	_bs.btn_end_card_phase.position = Vector2(700.0, 60.0)
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


func update_hud() -> void:
	_bs.lbl_enemy_hq.text  = "Enemy HQ: %d / %d"  % [_bs.enemy_hq_hp,  _bs.HQ_MAX_HP]
	_bs.lbl_player_hq.text = "Your HQ: %d / %d"   % [_bs.player_hq_hp, _bs.HQ_MAX_HP]
	_bs.lbl_turn.text      = "Turn: %d"            % _bs.turn_count
	_bs.lbl_log.text       = _bs.last_log
	if _bs.lbl_cost_bs:
		_bs.lbl_cost_bs.text = "Cost: %d" % _bs._player_cost
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	_bs.btn_next.visible = _bs.game_phase == GameEnums.BattlePhase.BATTLE
	_bs._btn_auto.visible = _bs.game_phase == GameEnums.BattlePhase.BATTLE
	if _bs.btn_end_card_phase:
		_bs.btn_end_card_phase.visible = in_card_phase


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
