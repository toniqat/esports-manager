extends Node

# Manual mech-to-player assignment for the player team.
# Enemy team is auto-assigned (shuffled) since the user doesn't manage them.
# Mechs have no role — any of the 5 picks can go to any player slot.

signal phase_finished(result: Dictionary)

const ROLE_NAMES_KR := ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]

@onready var _mf: MatchFlow = get_parent() as MatchFlow

var _player_roster: Array = []   # Array[PlayerData] sorted by role 0..4
var _player_mechs:  Array = []   # Array[MechData] (5 picks)
var _enemy_roster:  Array = []
var _enemy_mechs:   Array = []

# slot_idx (0..4) → mech_id(int) or -1
var _slot_to_mech: Array = [-1, -1, -1, -1, -1]
var _selected_mech_id: int = -1

# UI
var _panel: Panel
var _mech_buttons:  Dictionary = {}  # mech_id → Button
var _slot_buttons:  Array = []       # slot_idx → Button
var _btn_confirm: Button
var _lbl_status:  Label


func enter(player_roster: Array, player_mechs: Array,
		enemy_roster: Array, enemy_mechs: Array) -> void:
	_player_roster = player_roster
	_player_mechs  = player_mechs
	_enemy_roster  = enemy_roster
	_enemy_mechs   = enemy_mechs
	_slot_to_mech  = [-1, -1, -1, -1, -1]
	_selected_mech_id = -1

	# Auto-assign enemy team (shuffle picks → roster slots)
	var shuffled := enemy_mechs.duplicate()
	shuffled.shuffle()
	for i in range(min(5, enemy_roster.size(), shuffled.size())):
		(enemy_roster[i] as PlayerData).assigned_mech = shuffled[i] as MechData

	_build_ui()
	_refresh_ui()


# ── UI build ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.13, 1.0)
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)

	UiHelpers.mk_label(_panel, "ASSIGN MECHS TO PLAYERS", 44, Color(1.0, 0.85, 0.2),
			Vector2(0.0, 30.0), Vector2(1080.0, 60.0), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(_panel, "Tap a mech, then tap a player slot. Tap an assigned slot to clear.",
			22, Color(0.65, 0.65, 0.65),
			Vector2(0.0, 100.0), Vector2(1080.0, 30.0), HORIZONTAL_ALIGNMENT_CENTER)

	# Picked mechs row
	UiHelpers.mk_label(_panel, "Your Picks:", 26, Color(0.55, 0.75, 1.0),
			Vector2(40.0, 150.0), Vector2(400.0, 30.0))
	for i in range(_player_mechs.size()):
		var m := _player_mechs[i] as MechData
		var btn := Button.new()
		btn.text = "%s\nHP %d  ATK %d\nSPD %d" % [m.name, m.hp, m.atk, m.speed]
		btn.add_theme_font_size_override("font_size", 18)
		btn.position = Vector2(40.0 + i * 204.0, 195.0)
		btn.size     = Vector2(196.0, 170.0)
		btn.pressed.connect(_on_mech_pressed.bind(m.id))
		_panel.add_child(btn)
		_mech_buttons[m.id] = btn

	# Player slots (5 rows)
	UiHelpers.mk_label(_panel, "Your Roster:", 26, Color(0.55, 0.75, 1.0),
			Vector2(40.0, 405.0), Vector2(400.0, 30.0))
	var slot_y0 := 450.0
	var slot_h  := 200.0
	var slot_gap := 18.0
	for i in range(5):
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 22)
		btn.position = Vector2(40.0, slot_y0 + i * (slot_h + slot_gap))
		btn.size     = Vector2(1000.0, slot_h)
		btn.alignment    = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon  = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var p: PlayerData = _player_roster[i]
		if p != null:
			btn.icon = PilotImages.face_for(p.id)
		btn.pressed.connect(_on_slot_pressed.bind(i))
		_panel.add_child(btn)
		_slot_buttons.append(btn)

	# Status + confirm
	_lbl_status = UiHelpers.mk_label(_panel, "", 24, Color(1.0, 1.0, 0.9),
			Vector2(0.0, 1610.0), Vector2(1080.0, 40.0), HORIZONTAL_ALIGNMENT_CENTER)
	_btn_confirm = Button.new()
	_btn_confirm.text     = "Confirm Assignment"
	_btn_confirm.position = Vector2(290.0, 1670.0)
	_btn_confirm.size     = Vector2(500.0, 100.0)
	_btn_confirm.add_theme_font_size_override("font_size", 32)
	_btn_confirm.disabled = true
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	_panel.add_child(_btn_confirm)


func _refresh_ui() -> void:
	# Mech buttons: highlight selected, dim assigned
	for id in _mech_buttons.keys():
		var btn := _mech_buttons[id] as Button
		var assigned_to_slot := _slot_to_mech.find(int(id))
		if assigned_to_slot != -1:
			btn.modulate = Color(0.45, 0.65, 1.0).darkened(0.3)
			btn.disabled = true
		elif int(id) == _selected_mech_id:
			btn.modulate = Color(1.0, 1.0, 0.4)
			btn.disabled = false
		else:
			btn.modulate = Color(1, 1, 1)
			btn.disabled = false

	# Slot buttons: show role + assigned mech
	for i in range(5):
		var p: PlayerData = _player_roster[i]
		var slot_btn := _slot_buttons[i] as Button
		var mech_id: int = _slot_to_mech[i]
		var role_name: String = ROLE_NAMES_KR[p.role] if p.role >= 0 and p.role < ROLE_NAMES_KR.size() else "?"
		if mech_id == -1:
			slot_btn.text = "[%s]  %s\n— empty slot —" % [role_name, p.name]
			slot_btn.modulate = Color(0.7, 0.7, 0.75)
		else:
			var m := _find_mech(mech_id)
			slot_btn.text = "[%s]  %s\nMech: %s   HP %d  ATK %d  SPD %d" % \
					[role_name, p.name, m.name, m.hp, m.atk, m.speed]
			slot_btn.modulate = Color(0.55, 0.85, 0.55)

	# Status + confirm gate
	var filled: int = _slot_to_mech.count(-1)
	if filled == 0:
		_lbl_status.text = "All 5 slots assigned — ready to confirm."
		_btn_confirm.disabled = false
	else:
		var msg := ""
		if _selected_mech_id != -1:
			var sm := _find_mech(_selected_mech_id)
			msg = "%s selected — pick a slot.   " % sm.name
		_lbl_status.text = "%s%d slot(s) still empty." % [msg, filled]
		_btn_confirm.disabled = true


# ── Click handling ───────────────────────────────────────────────────────────
func _on_mech_pressed(mech_id: int) -> void:
	# Toggle selection
	if _selected_mech_id == int(mech_id):
		_selected_mech_id = -1
	else:
		_selected_mech_id = int(mech_id)
	_refresh_ui()


func _on_slot_pressed(slot_idx: int) -> void:
	# If slot already has a mech, clear it
	if _slot_to_mech[slot_idx] != -1:
		_slot_to_mech[slot_idx] = -1
		_refresh_ui()
		return
	# Otherwise, assign the selected mech (if any)
	if _selected_mech_id == -1:
		return
	# Sanity: mech can't already be in another slot (button is disabled in that case)
	if _slot_to_mech.find(_selected_mech_id) != -1:
		return
	_slot_to_mech[slot_idx] = _selected_mech_id
	_selected_mech_id = -1
	_refresh_ui()


func _on_confirm_pressed() -> void:
	# Apply assignments to PlayerData.assigned_mech
	for i in range(5):
		var mech_id: int = _slot_to_mech[i]
		var m := _find_mech(mech_id)
		(_player_roster[i] as PlayerData).assigned_mech = m
	_panel.queue_free()
	_panel = null
	_mech_buttons.clear()
	_slot_buttons.clear()
	phase_finished.emit({
		"player_roster": _player_roster,
		"enemy_roster":  _enemy_roster,
	})


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_mech(id: int) -> MechData:
	for m_raw in _player_mechs:
		var m := m_raw as MechData
		if m.id == id: return m
	return null


