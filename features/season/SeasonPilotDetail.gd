class_name SeasonPilotDetail
extends VBoxContainer

# Pilot detail during a run — opened by tapping a `SeasonPilotCard` (season hub roster, week
# screen bottom row). A `HubSheet` body (title = pilot name): the same card as header (not
# tappable) next to total / trust / outings / stress, then the six stats by their **full
# names** (`PlayerData.stat_label`, no short forms) with their one-line notes, equipped quirks
# (`QuirkSystem`) and this week's research mech (`MechMastery`).
#
# **Layout lives in `UI_View_SeasonPilotDetail.tscn`.** `open` puts one instance into the
# sheet's `body`; this script fills `%` nodes (quirk lines are duplicates of the hidden
# `%QuirkLine` template). The sheet's scroll height follows this node's height (`resized`).
# Read-only — filled once.

const SCENE_PATH: String = "res://features/season/UI_View_SeasonPilotDetail.tscn"

var _sheet: HubSheet = null


static func create() -> SeasonPilotDetail:
	return (load(SCENE_PATH) as PackedScene).instantiate() as SeasonPilotDetail


## Opens the sheet on `host` for my pilot `pilot_id` (no-op when the pilot is unknown).
static func open(host: Node, pilot_id: int) -> HubSheet:
	var state: Dictionary = host.get_node("/root/GameManager").season_state
	var pd: PlayerData = MentalEvents.pilot_of(state, pilot_id)
	if pd == null:
		return null
	var sheet := HubSheet.open_on(host, MentalEvents.pilot_name(state, pilot_id))
	var panel := create()
	sheet.body.add_child(panel)
	panel._bind(sheet, state, pd)
	return sheet


func _ready() -> void:
	resized.connect(_fit_sheet)
	if UiPreview.is_standalone(self):
		_fill_preview()


func _bind(sheet: HubSheet, state: Dictionary, pd: PlayerData) -> void:
	_sheet = sheet
	var pid: int = pd.id
	var card: SeasonPilotCard = %SeasonPilotCard_Head
	card.set_tappable(false)
	var trust: int = MentalSystem.trust(state, pid)
	var stress: int = StressSystem.value(state, pid)
	card.show_pilot(pid, pd.role, trust, stress)

	(%Total as Label).text = Loc.t(L.SEASON_PILOT_DETAIL_TOTAL, {"n": pd.stat_total()})
	var tl: Label = %Trust
	var level: int = MentalSystem.level_of_trust(trust)
	tl.text = Loc.t(L.SEASON_PILOT_DETAIL_TRUST,
			{"n": level, "pct": roundi(MentalSystem.progress_of_trust(trust) * 100.0)})
	tl.add_theme_color_override("font_color", HubView.trust_color(level))
	(%Outings as Label).text = Loc.t(L.SEASON_PILOT_DETAIL_OUTINGS, {"n": MentalSystem.outings(state, pid)})
	var mood: int = StressSystem.mood_of(state, pid)
	var ml: Label = %Mood
	ml.text = StressSystem.line(stress, mood)
	ml.theme_type_variation = &"NegativeLabel" if StressSystem.is_over(stress) else &"CaptionLabel"

	_fill_stats(pd)
	_fill_quirks(state, pid)
	_fill_research(state, pid)
	# §15 C — awakening gauge + card presets (`features/season/awakening/`).
	AwakeningPilotBlock.mount(%AwakeningSlot, state, pid)
	_fit_sheet()


func _fill_stats(pd: PlayerData) -> void:
	var rows: Array = (%Stats as Node).get_children()
	for i in rows.size():
		var row: Control = rows[i]
		row.visible = i < PlayerData.STAT_KEYS.size()
		if not row.visible:
			continue
		(row.get_node("Line/Name") as Label).text = PlayerData.stat_label(i)
		(row.get_node("Line/Value") as Label).text = "%d" % int(pd.get(PlayerData.STAT_KEYS[i]))
		(row.get_node("Note") as Label).text = PlayerData.stat_note(i)


func _fill_quirks(state: Dictionary, pid: int) -> void:
	var holder: Control = %Quirks
	var template: Label = %QuirkLine
	template.visible = false
	for c in holder.get_children():
		if c != template:
			holder.remove_child(c)
			c.queue_free()
	var ids: Array = QuirkSystem.quirks_of(state, pid) if QuirkSystem.is_enabled(state) else []
	(%QuirksEmpty as Control).visible = ids.is_empty()
	for raw in ids:
		var id: int = int(raw)
		var line: Label = template.duplicate() as Label
		var effect: String = QuirkSystem.effect_text(id)
		line.text = QuirkSystem.name_of(id) if effect == "" else "%s · %s" % [QuirkSystem.name_of(id), effect]
		var r: Dictionary = QuirkSystem.row(id)
		if not r.is_empty():
			line.add_theme_color_override("font_color", QuirkSystem.grade_color(int(r.get("grade", 0))))
		line.visible = true
		holder.add_child(line)


func _fill_research(state: Dictionary, pid: int) -> void:
	var rl: Label = %Research
	var mech: int = MechMastery.research_mech(state, pid) if MechMastery.is_enabled(state) else -1
	if mech < 0:
		rl.text = Loc.t(L.SEASON_PILOT_DETAIL_RESEARCH_NONE)
		rl.theme_type_variation = &"FaintLabel"
		return
	var v: int = MechMastery.value(state, pid, mech)
	var tier: int = MechMastery.tier_of(v)
	rl.text = Loc.t(L.SEASON_PILOT_DETAIL_RESEARCH, {"mech": MechMastery.mech_name(mech),
			"tier": MechMastery.tier_name(tier), "value": v, "max": MechMastery.max_value()})
	rl.add_theme_color_override("font_color", MechMastery.tier_color(tier))


## The sheet scrolls exactly this node's height (the scene's `Tail` is the bottom gap).
func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


## F6 단독 실행 미리보기 — 메모리 런의 내 팀 첫 선수(`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(state)
	if ids.is_empty():
		return
	_bind(null, state, MentalEvents.pilot_of(state, int(ids[0])))
