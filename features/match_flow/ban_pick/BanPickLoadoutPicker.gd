class_name BanPickLoadoutPicker
extends CanvasLayer

# §15 C — pre-match card preset picker. In the ban/pick assignment step (mechs can still be
# re-seated), pressing the start bar opens this popup when at least one of my pilots owns
# 2+ card presets (`PilotLoadout`): one row per such pilot (seat order) — round portrait,
# name · position, preset tabs ("기본" / "프리셋 n", starting on the active one) and the
# tab's three cards (`AwakeningCardCell`, "+" cards captioned). 확인 writes every choice with
# `PilotLoadout.set_active` (the run state, so the Saturday-prep split keeps it for Sunday) and
# emits `confirmed`; 취소 closes it and returns to the assignment. `MatchFlow._finalize_rosters`
# → `PilotLoadout.apply_to` then puts the active preset into the roster copies.
#
# Hook: `BanPickController._on_start_pressed` → `open_if_needed(self, roster, _finish)`.
# **Layout lives in `UI_View_BanPickLoadoutPicker.tscn`**; rows / tabs are duplicates of the
# hidden templates `%RowTemplate` / `%TabTemplate`.

signal confirmed
signal cancelled

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_View_BanPickLoadoutPicker.tscn"
const CARD_SCALE: float = 0.55

var _state: Dictionary = {}
var _choice: Dictionary = {}          # pid → preset index
var _rows: Dictionary = {}            # pid → row node


static func create() -> BanPickLoadoutPicker:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickLoadoutPicker


## My pilots of `roster` (Array[PlayerData], role order) with 2+ presets, seat order.
static func pilots_needing(state: Dictionary, roster: Array) -> Array:
	var out: Array = []
	if not bool(state.get("active", false)):
		return out
	for role in GameEnums.ROLE_DISPLAY_ORDER:
		var r: int = int(role)
		if r < 0 or r >= roster.size():
			continue
		var pd := roster[r] as PlayerData
		if pd != null and PilotLoadout.presets(state, pd.id).size() >= 2:
			out.append(pd)
	return out


## Opens the picker on `host` when `roster` has a pilot with 2+ presets and connects
## `on_confirm` to `confirmed`. False (nothing opened) otherwise — the caller goes on.
static func open_if_needed(host: Node, roster: Array, on_confirm: Callable) -> bool:
	var gm: Node = host.get_node_or_null("/root/GameManager")
	if gm == null or pilots_needing(gm.season_state, roster).is_empty():
		return false
	var picker := create()
	host.add_child(picker)
	picker.confirmed.connect(on_confirm)
	picker.open(roster)
	return true


func _ready() -> void:
	(%RowTemplate as Control).visible = false
	(%Cancel as Button).pressed.connect(_on_cancel)
	(%Confirm as Button).pressed.connect(_on_confirm)
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = -OutgameTheme.bottom_inset()
	if UiPreview.is_standalone(self):
		_fill_preview()


func open(roster: Array) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	_state = gm.season_state if gm != null else {}
	var holder: VBoxContainer = %Rows
	var template: Control = %RowTemplate
	for c in holder.get_children():
		if c != template:
			holder.remove_child(c)
			c.queue_free()
	_rows.clear()
	_choice.clear()
	for raw in pilots_needing(_state, roster):
		var pd := raw as PlayerData
		var row: Control = template.duplicate() as Control
		row.visible = true
		holder.add_child(row)
		_rows[pd.id] = row
		_choice[pd.id] = PilotLoadout.active(_state, pd.id)
		(row.find_child("Name", true, false) as Label).text = pd.name
		(row.find_child("Position", true, false) as Label).text = GameEnums.role_position_label(pd.role)
		var slot: Control = row.find_child("Portrait", true, false) as Control
		OutgameTheme.add_round_portrait(slot, PilotImages.circle_for(pd.id), Vector2.ZERO,
				slot.custom_minimum_size.x)
		_fill_row(pd.id)


func _fill_row(pid: int) -> void:
	var row: Control = _rows[pid]
	var tabs: HBoxContainer = row.find_child("Tabs", true, false) as HBoxContainer
	var tab_tpl: Button = row.find_child("TabTemplate", true, false) as Button
	tab_tpl.visible = false
	for c in tabs.get_children():
		if c != tab_tpl:
			tabs.remove_child(c)
			c.queue_free()
	var sel: int = int(_choice[pid])
	var all: Array = PilotLoadout.presets(_state, pid)
	for i in all.size():
		var b: Button = tab_tpl.duplicate() as Button
		b.visible = true
		b.text = AwakeningView.preset_label(i)
		b.theme_type_variation = &"SelectableTileOn" if i == sel else &"SelectableTile"
		b.pressed.connect(_on_tab.bind(pid, i))
		tabs.add_child(b)
	var cards: Control = row.find_child("Cards", true, false) as Control
	for c in cards.get_children():
		cards.remove_child(c)
		c.queue_free()
	for c in (all[sel] as Array):
		var cell := AwakeningCardCell.create()
		cards.add_child(cell)
		cell.set_card_scale(CARD_SCALE)
		cell.fill(int(c))
		(cell.get_node("%Hit") as Button).visible = false


func _on_tab(pid: int, idx: int) -> void:
	_choice[pid] = idx
	_fill_row(pid)


func _on_confirm() -> void:
	for pid in _choice:
		PilotLoadout.set_active(_state, int(pid), int(_choice[pid]))
	confirmed.emit()
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()


## F6 단독 실행 미리보기 — 메모리 런의 내 다섯 중 둘에게 추가 프리셋을 준 로스터.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.mute(%Confirm, self, "confirm")
	UiPreview.mute(%Cancel, self, "cancel")
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	if not s.has(PilotLoadout.STATE_KEY):
		Awakening.init_run(s)
		PilotLoadout.init_run(s)
	var roster: Array = []
	roster.resize(5)
	for raw in MentalSystem.my_pilot_ids(s):
		var pd: PlayerData = MentalEvents.pilot_of(s, int(raw))
		if pd != null and pd.role >= 0 and pd.role < 5:
			roster[pd.role] = pd
	for k in 2:
		var pid: int = int(MentalSystem.my_pilot_ids(s)[k])
		if PilotLoadout.presets(s, pid).size() < 2:
			var cands: Array = Awakening.preset_candidates(s, pid)
			if not cands.is_empty():
				PilotLoadout.add_preset(s, pid, cands[0])
	open(roster)
