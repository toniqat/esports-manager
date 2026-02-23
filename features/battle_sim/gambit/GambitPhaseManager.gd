class_name GambitPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func build_gambit_ui() -> void:
	_bs._panel_gambit = Panel.new()
	_bs._panel_gambit.position = Vector2(0.0, 0.0)
	_bs._panel_gambit.size     = Vector2(1080.0, 1920.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.12, 0.97)
	_bs._panel_gambit.add_theme_stylebox_override("panel", bg)
	_bs._canvas.add_child(_bs._panel_gambit)

	_mk_label(_bs._panel_gambit, "GAMBIT PHASE", 52, Color(1.0, 0.85, 0.2),
			Vector2(0.0, 60.0), Vector2(1080.0, 70.0), HORIZONTAL_ALIGNMENT_CENTER)
	_mk_label(_bs._panel_gambit,
			"Assign 5 Pilots to lanes  •  Max 2 per lane  •  Exactly 1 Guerrilla",
			22, Color(0.65, 0.65, 0.65),
			Vector2(0.0, 145.0), Vector2(1080.0, 35.0), HORIZONTAL_ALIGNMENT_CENTER)
	_mk_label(_bs._panel_gambit, "SELECT PILOT:", 24, Color(0.8, 0.8, 0.8),
			Vector2(40.0, 200.0), Vector2(300.0, 35.0))

	var roles: Array = [
		GameEnums.Role.TANK, GameEnums.Role.FIGHTER, GameEnums.Role.ASSASSIN,
		GameEnums.Role.SUPPORT, GameEnums.Role.SNIPER,
	]
	for i in range(5):
		var btn := Button.new()
		btn.text = "%s\n%s" % [_bs.ROLE_FULL_NAMES[roles[i]], _bs.role_stats_str(roles[i])]
		btn.position = Vector2(40.0 + i * 203.0, 245.0)
		btn.size     = Vector2(188.0, 120.0)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(on_gambit_pilot_selected.bind(i))
		_bs._panel_gambit.add_child(btn)
		_bs._gambit_pilot_btns.append(btn)

	_mk_label(_bs._panel_gambit, "ASSIGN TO LANE:", 24, Color(0.8, 0.8, 0.8),
			Vector2(40.0, 385.0), Vector2(400.0, 35.0))

	var slot_colors: Array = [
		Color(0.1, 0.3, 0.85),
		Color(0.1, 0.55, 0.2),
		Color(0.55, 0.1, 0.5),
		Color(0.7, 0.45, 0.0),
	]
	for slot in range(4):
		var sp := Panel.new()
		sp.position = Vector2(40.0, 430.0 + slot * 168.0)
		sp.size     = Vector2(1000.0, 150.0)
		var sty := StyleBoxFlat.new()
		sty.bg_color              = slot_colors[slot].darkened(0.55)
		sty.border_color          = slot_colors[slot]
		sty.border_width_left     = 3
		sty.border_width_right    = 3
		sty.border_width_top      = 3
		sty.border_width_bottom   = 3
		sty.corner_radius_top_left     = 8
		sty.corner_radius_top_right    = 8
		sty.corner_radius_bottom_left  = 8
		sty.corner_radius_bottom_right = 8
		sp.add_theme_stylebox_override("panel", sty)
		_bs._panel_gambit.add_child(sp)

		_mk_label(sp, "%s (max %d)" % [_bs.LANE_NAMES[slot].to_upper(), _bs.LANE_MAX[slot]],
				26, slot_colors[slot].lightened(0.4), Vector2(15.0, 10.0), Vector2(280.0, 40.0))

		var al := Label.new()
		al.text = "(empty)"
		al.add_theme_font_size_override("font_size", 22)
		al.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		al.position = Vector2(15.0, 60.0)
		al.size     = Vector2(650.0, 35.0)
		sp.add_child(al)
		_bs._gambit_slot_labels.append(al)

		var ab := Button.new()
		ab.text = "Assign Here"
		ab.position = Vector2(760.0, 45.0)
		ab.size     = Vector2(220.0, 60.0)
		ab.add_theme_font_size_override("font_size", 22)
		ab.pressed.connect(on_gambit_slot_pressed.bind(slot))
		sp.add_child(ab)

	_bs._lbl_gambit_status = Label.new()
	_bs._lbl_gambit_status.text = "Click a pilot to select, then click a lane to assign."
	_bs._lbl_gambit_status.add_theme_font_size_override("font_size", 24)
	_bs._lbl_gambit_status.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	_bs._lbl_gambit_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs._lbl_gambit_status.position = Vector2(0.0, 1100.0)
	_bs._lbl_gambit_status.size     = Vector2(1080.0, 45.0)
	_bs._panel_gambit.add_child(_bs._lbl_gambit_status)

	var btn_auto := Button.new()
	btn_auto.text = "Auto-Assign (Random)"
	btn_auto.position = Vector2(290.0, 1160.0)
	btn_auto.size     = Vector2(500.0, 80.0)
	btn_auto.add_theme_font_size_override("font_size", 28)
	btn_auto.pressed.connect(on_gambit_auto_assign_pressed)
	_bs._panel_gambit.add_child(btn_auto)

	_bs._btn_launch = Button.new()
	_bs._btn_launch.text     = "Launch Battle"
	_bs._btn_launch.position = Vector2(290.0, 1260.0)
	_bs._btn_launch.size     = Vector2(500.0, 100.0)
	_bs._btn_launch.add_theme_font_size_override("font_size", 36)
	_bs._btn_launch.disabled = true
	_bs._btn_launch.pressed.connect(on_launch_battle_pressed)
	_bs._panel_gambit.add_child(_bs._btn_launch)


func refresh_gambit_ui() -> void:
	var roles: Array = [
		GameEnums.Role.TANK, GameEnums.Role.FIGHTER, GameEnums.Role.ASSASSIN,
		GameEnums.Role.SUPPORT, GameEnums.Role.SNIPER,
	]
	for i in range(5):
		var btn: Button = _bs._gambit_pilot_btns[i]
		var lid: int    = _bs._gambit_lanes[i]
		var suffix      := "\n→ %s" % _bs.LANE_NAMES[lid] if lid != -1 else ""
		btn.text = "%s\n%s%s" % [_bs.ROLE_FULL_NAMES[roles[i]], _bs.role_stats_str(roles[i]), suffix]
		if i == _bs._gambit_selected:
			btn.modulate = Color(1.0, 1.0, 0.25)
		elif lid != -1:
			btn.modulate = Color(0.55, 0.8, 0.55)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)

	for slot in range(4):
		var names: Array = []
		for i in range(5):
			if _bs._gambit_lanes[i] == slot:
				names.append(_bs.ROLE_FULL_NAMES[roles[i]])
		(_bs._gambit_slot_labels[slot] as Label).text = \
				" | ".join(names) if not names.is_empty() else "(empty)"

	var all_done: bool = _bs._gambit_lanes.all(func(l): return l != -1)
	_bs._btn_launch.disabled = not all_done
	if all_done:
		_bs._lbl_gambit_status.text = "All pilots assigned!  Ready to launch."
	elif _bs._gambit_selected != -1:
		_bs._lbl_gambit_status.text = "Pilot selected — choose a lane."
	else:
		_bs._lbl_gambit_status.text = "%d pilot(s) still need a lane." % _bs._gambit_lanes.count(-1)


func on_gambit_pilot_selected(idx: int) -> void:
	_bs._gambit_selected = -1 if _bs._gambit_selected == idx else idx
	refresh_gambit_ui()


func on_gambit_slot_pressed(slot: int) -> void:
	if _bs._gambit_selected == -1:
		_bs._lbl_gambit_status.text = "Select a pilot first!"
		return
	var count := 0
	for i in range(5):
		if i != _bs._gambit_selected and _bs._gambit_lanes[i] == slot:
			count += 1
	if count >= _bs.LANE_MAX[slot]:
		_bs._lbl_gambit_status.text = "%s lane is full!" % _bs.LANE_NAMES[slot]
		return
	_bs._gambit_lanes[_bs._gambit_selected] = slot
	_bs._gambit_selected = -1
	refresh_gambit_ui()


func on_gambit_auto_assign_pressed() -> void:
	var base_lanes: Array = [GameEnums.Lane.LEFT, GameEnums.Lane.CENTER, GameEnums.Lane.RIGHT]
	var extra: int = base_lanes[randi() % 3]
	var assignment: Array = [
		GameEnums.Lane.LEFT, GameEnums.Lane.CENTER, GameEnums.Lane.RIGHT,
		extra, GameEnums.Lane.GUERRILLA,
	]
	assignment.shuffle()
	_bs._gambit_lanes    = assignment
	_bs._gambit_selected = -1
	refresh_gambit_ui()


func on_launch_battle_pressed() -> void:
	_bs._panel_gambit.visible = false
	_bs._minions = []
	_bs._sim_core.spawn_pilots_with_lanes()
	_bs._sim_core.spawn_turrets()
	_bs._sim_core.init_neutral_zones()
	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()


func _mk_label(parent: Control, text: String, font_size: int, color: Color,
		pos: Vector2, sz: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size     = sz
	l.horizontal_alignment = align
	parent.add_child(l)
	return l
