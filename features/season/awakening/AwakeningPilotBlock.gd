class_name AwakeningPilotBlock
extends VBoxContainer

# Awakening gauge + card presets of one of my pilots — the section `SeasonPilotDetail` mounts
# into its `%AwakeningSlot` (`mount`). Gauge = `Awakening.gauge` / AWAKEN_THRESHOLD as a
# track + fill bar with the value, plus a "pending" line while an awakening is queued.
# Presets = one line per preset (`PilotLoadout.presets`): its name ("기본" / "프리셋 n"), the
# "출전" chip on the active one, and its three cards as name chips — an upgraded "+" card
# uses the accent chip.
#
# **Layout lives in `UI_Comp_AwakeningPilotBlock.tscn`.** Preset lines and card chips are
# duplicates of the hidden templates `%PresetLineTemplate` / `%CardChipTemplate`.

const SCENE_PATH: String = "res://features/season/awakening/UI_Comp_AwakeningPilotBlock.tscn"


static func create() -> AwakeningPilotBlock:
	return (load(SCENE_PATH) as PackedScene).instantiate() as AwakeningPilotBlock


## Clears `holder` and puts a filled block for pilot `pid` into it.
static func mount(holder: Control, state: Dictionary, pid: int) -> AwakeningPilotBlock:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var block := create()
	holder.add_child(block)
	block.show_pilot(state, pid)
	return block


func _ready() -> void:
	(%PresetLineTemplate as Control).visible = false
	(%CardChipTemplate as Control).visible = false
	if UiPreview.is_standalone(self):
		_fill_preview()


func show_pilot(state: Dictionary, pid: int) -> void:
	var g: int = Awakening.gauge(state, pid)
	var cap: int = Awakening.threshold()
	(%GaugeText as Label).text = Loc.t(L.AWAKENING_DETAIL_GAUGE, {"n": g, "max": cap})
	var fill: Control = %GaugeFill
	fill.anchor_right = clampf(float(g) / float(cap), 0.0, 1.0)
	fill.offset_right = 0.0
	(%Pending as Control).visible = Awakening.pending_count(state, pid) > 0
	_fill_presets(state, pid)


func _fill_presets(state: Dictionary, pid: int) -> void:
	var holder: VBoxContainer = %Presets
	var template: Control = %PresetLineTemplate
	for c in holder.get_children():
		if c != template:
			holder.remove_child(c)
			c.queue_free()
	var gm: Node = get_node_or_null("/root/GameManager")
	var all: Array = PilotLoadout.presets(state, pid)
	var act: int = PilotLoadout.active(state, pid)
	for i in all.size():
		var line: Control = template.duplicate() as Control
		line.visible = true
		holder.add_child(line)
		(line.find_child("Name", true, false) as Label).text = AwakeningView.preset_label(i)
		(line.find_child("ActiveChip", true, false) as Control).visible = i == act and all.size() > 1
		var chips: Control = line.find_child("Chips", true, false) as Control
		for c in (all[i] as Array):
			var def: Dictionary = gm.card_def(int(c)) if gm != null else {}
			if def.is_empty():
				continue
			var card_name: String = Loc.t(String(def["name_key"]))  # l10n-dynamic: card.pilot.*.name
			chips.add_child(_chip(card_name, PilotLoadout.is_upgraded(int(c))))


func _chip(text: String, upgraded: bool) -> Control:
	var chip: PanelContainer = (%CardChipTemplate as PanelContainer).duplicate() as PanelContainer
	chip.visible = true
	chip.theme_type_variation = &"AccentChip" if upgraded else &"SurfaceChip"
	(chip.find_child("Text", true, false) as Label).text = text
	return chip


## F6 단독 실행 미리보기 — 메모리 런의 내 첫 선수: 게이지 70, 강화 카드 한 장, 추가 프리셋 하나.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	if not s.has(Awakening.KEY_GAUGE):
		Awakening.init_run(s)
		PilotLoadout.init_run(s)
	var pid: int = int(MentalSystem.my_pilot_ids(s)[0])
	Awakening.add_gauge(s, pid, 70, "preview")
	var base: Array = PilotLoadout.preset(s, pid, 0)
	PilotLoadout.upgrade_card(s, pid, 0, int(base[0]))
	var cands: Array = Awakening.preset_candidates(s, pid)
	if not cands.is_empty():
		PilotLoadout.add_preset(s, pid, cands[0])
	show_pilot(s, pid)
