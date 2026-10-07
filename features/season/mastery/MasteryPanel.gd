class_name MasteryPanel
extends VBoxContainer

# Hub manage card 「메크 연구」 + its `HubSheet` (contract: plan §11.2 —
# `hub_summary` / `open`). The card summarises how many of my pilots have a
# weekly research mech; the sheet lists my five pilots (role display order) with
# their top mastery mechs and a chip row of their own-role mechs to pick the
# research mech from. When the knowledge area is delegated
# (`StaffSystem.is_delegated(state, "knowledge")`) a "코치에게 맡기기" button
# fills all five with the coach's plain rule (`MechMastery.auto_assign_all`).
# Each pilot card also lists that pilot's quirks (`QuirkSystem`, §14) with
# `n / slots`; research can turn up quirks at week close.
#
# **The sheet body's layout lives in `UI_View_MasteryPanel.tscn`** (+ item scenes
# `MasteryPilotRow` · `MasteryMechChip` · `MasteryQuirkLine`). `open` puts one instance
# into the sheet's `body`; this script fills `%` nodes, instances the rows and applies
# data: research colour, chip variation (research mech = `PrimaryButton`), tier / grade
# colours, the round portrait (`_draw` widget, added into `%Portrait`). A tap refills the
# same instance in place; rows and chips are reused, so a chip is never freed while it
# is emitting `pressed`. The sheet's scroll height follows this node's height.

const SCENE_PATH: String = "res://features/season/mastery/UI_View_MasteryPanel.tscn"
const PILOT_ROW_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryPilotRow.tscn")
const CHIP_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryMechChip.tscn")
const QUIRK_LINE_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryQuirkLine.tscn")

var _sheet: HubSheet = null
var _state: Dictionary = {}


## Card summary — `{title, value, sub, owner, alert}`.
static func hub_summary(state: Dictionary) -> Dictionary:
	if not MechMastery.is_enabled(state):
		return {"title": Loc.t(L.MASTERY_HUB_TITLE), "value": "—", "sub": Loc.t(L.MASTERY_HUB_NO_RUN),
				"owner": "", "alert": false}
	var pilots: Array = MechMastery.my_pilots(state)
	var missing: int = MechMastery.missing_research_count(state)
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	var per_week: int = 0
	if not pilots.is_empty():
		per_week = MechMastery.gain_preview(state, (pilots[0] as PlayerData).id,
				ConstTable.int_of("MASTERY_GAIN_RESEARCH"))
	var sub: String = Loc.t(L.MASTERY_HUB_WEEKLY_GAIN, {"n": per_week})
	if missing > 0:
		sub = Loc.t(L.MASTERY_HUB_COACH_FILLS) if delegated else Loc.t(L.MASTERY_HUB_MISSING, {"n": missing})
	return {
		"title": Loc.t(L.MASTERY_HUB_TITLE),
		"value": Loc.t(L.MASTERY_HUB_ASSIGNED, {"n": pilots.size() - missing, "total": pilots.size()}),
		"sub": sub,
		"owner": StaffSystem.owner_name(state, "knowledge"),
		"alert": missing > 0 and not delegated,
	}


## Instantiates the scene. `MasteryPanel.new()` is an empty box — don't use it.
static func create() -> MasteryPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MasteryPanel


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, Loc.t(L.MASTERY_HUB_TITLE))
	var gm: Node = host.get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var panel := create()
	sheet.body.add_child(panel)
	panel._bind(sheet, gm.season_state)


func _ready() -> void:
	for c in (%Pilots as Node).get_children():   # scene sample = preview only
		%Pilots.remove_child(c)
		c.queue_free()
	(%Auto as Button).pressed.connect(_on_auto)
	resized.connect(_fit_sheet)
	if UiPreview.is_standalone(self):
		_fill_preview()


func _bind(sheet: HubSheet, state: Dictionary) -> void:
	_sheet = sheet
	_state = state
	_fill()
	_fit_sheet()


## The sheet scrolls exactly this node's height (the scene's `Tail` is the bottom gap).
func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


# Fills (or refills after a tap) the whole sheet body.
func _fill() -> void:
	var state: Dictionary = _state
	var enabled: bool = MechMastery.is_enabled(state)
	%Empty.visible = not enabled
	%Main.visible = enabled
	if not enabled:
		return
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	%Head.text = Loc.t(L.MASTERY_PANEL_HEAD, {"name": StaffSystem.owner_name(state, "knowledge"),
			"value": StaffSystem.effective(state, "knowledge")})
	var pilots: Array = MechMastery.my_pilots(state)
	var any_pid: int = (pilots[0] as PlayerData).id if not pilots.is_empty() else -1
	%Gain.text = Loc.t(L.MASTERY_PANEL_GAIN, {"mult": "%.2f" % MechMastery.gain_mult(state, any_pid)})
	var legend: Array = []
	for t in MechMastery.TIER_COUNT:
		legend.append("%s %s" % [MechMastery.tier_name(t), MechMastery.bonus_text(t)])
	%Legend.text = Loc.t(L.MASTERY_PANEL_LEGEND, {"tiers": "  ·  ".join(legend)})
	%Rules.text = Loc.t(L.MASTERY_PANEL_RULES, {"research": ConstTable.int_of("MASTERY_GAIN_RESEARCH"),
			"match": ConstTable.int_of("MASTERY_GAIN_MATCH")})
	%Auto.visible = delegated
	%AutoGap.visible = delegated
	%NoCoach.visible = not delegated

	var quirks_on: bool = QuirkSystem.is_enabled(state)
	%QuirkOdds.visible = quirks_on
	if quirks_on:
		var odds: Array = QuirkSystem.grade_odds(state)
		var parts: Array = []
		for g in QuirkSystem.GRADE_COUNT:
			parts.append("%s %d%%" % [QuirkSystem.grade_name(g), roundi(float(odds[g]))])
		%QuirkOdds.text = Loc.t(L.MASTERY_PANEL_QUIRK_ODDS, {
				"pct": ConstTable.int_of("QUIRK_RESEARCH_CHANCE"), "odds": "  ".join(parts)})

	var rows: Array = _ensure(%Pilots, PILOT_ROW_SCENE, pilots.size())
	for i in rows.size():
		_fill_pilot_row(rows[i], pilots[i] as PlayerData, delegated, quirks_on)


func _fill_pilot_row(row: Panel, pd: PlayerData, delegated: bool, quirks_on: bool) -> void:
	var state: Dictionary = _state
	var portrait: Control = row.get_node("%Portrait")
	if row.get_meta(&"pilot_id", -1) != pd.id:
		row.set_meta(&"pilot_id", pd.id)
		for c in portrait.get_children():
			c.queue_free()
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pd.id), Vector2.ZERO,
				portrait.size.x, OutgameTheme.ROLE_COLORS[clampi(pd.role, 0, 4)])
	row.get_node("%Name").text = pd.name
	var research: int = MechMastery.research_mech(state, pd.id)
	var res_l: Label = row.get_node("%Research")
	res_l.text = Loc.t(L.MASTERY_PANEL_RESEARCH, {"mech": MechMastery.mech_name(research)})
	var res_col: Color = OutgameTheme.ACCENT_TEXT
	if research < 0:
		# Delegated: the coach fills it at week close — not an error.
		res_l.text = Loc.t(L.MASTERY_PANEL_RESEARCH_COACH) if delegated else Loc.t(L.MASTERY_PANEL_RESEARCH_NONE)
		res_col = OutgameTheme.TEXT_SUB if delegated else OutgameTheme.NEGATIVE
	res_l.add_theme_color_override("font_color", res_col)
	var tops: Array = []
	for e in MechMastery.top_mechs(state, pd.id, 3):
		var v: int = int(e["value"])
		tops.append("%s %s %d" % [MechMastery.mech_name(int(e["mech_id"])),
				MechMastery.tier_name(MechMastery.tier_of(v)), v])
	(row.get_node("%PositionBadge_Position") as PositionBadge).set_role(int(pd.role))
	row.get_node("%TopMechs").text = Loc.t(L.MASTERY_PANEL_TOP_MECHS, {"list": "  ·  ".join(tops)})

	# Own-role mech chips — tap to set the research mech (tap the selected one to clear).
	var mechs: Array = MechMastery.mechs_of_role(pd.role)
	var chips: Array = _ensure(row.get_node("%Chips"), CHIP_SCENE, mechs.size(), _wire_chip)
	for i in chips.size():
		var chip: Button = chips[i]
		var mid: int = int((mechs[i] as Dictionary)["id"])
		var v: int = MechMastery.value(state, pd.id, mid)
		var t: int = MechMastery.tier_of(v)
		chip.set_meta(&"pilot_id", pd.id)
		chip.set_meta(&"mech_id", mid)
		chip.text = "%s\n%s %d" % [MechMastery.mech_name(mid), MechMastery.tier_name(t), v]
		chip.theme_type_variation = &"PrimaryButton" if mid == research else &"GhostButton"
		(chip.get_node("%TierBar") as ColorRect).color = MechMastery.tier_color(t)

	(row.get_node("%Quirks") as Control).visible = quirks_on
	if quirks_on:
		_fill_quirks(row, pd)
	# Card height = content + its top / bottom pads (the scene's `%Content` offsets).
	var content: Control = row.get_node("%Content")
	var pad_bottom: float = _card_pad_bottom(row, content)
	row.custom_minimum_size.y = content.offset_top + content.get_combined_minimum_size().y + pad_bottom


## Bottom pad of a pilot card = the scene's card height minus `%Content`'s bottom edge, read
## once from the unfilled instance (saved in meta so later refills reuse it).
static func _card_pad_bottom(row: Control, content: Control) -> float:
	if not row.has_meta(&"pad_bottom"):
		row.set_meta(&"pad_bottom", row.custom_minimum_size.y - content.offset_bottom)
	return float(row.get_meta(&"pad_bottom"))


## "기벽 n/slots" head, then one line per quirk: grade pill · name · effect.
func _fill_quirks(row: Control, pd: PlayerData) -> void:
	var state: Dictionary = _state
	var ids: Array = []
	for id in QuirkSystem.quirks_of(state, pd.id):
		if not QuirkSystem.row(int(id)).is_empty():
			ids.append(int(id))
	row.get_node("%Count").text = Loc.t(L.MASTERY_PANEL_QUIRK_COUNT, {
			"n": QuirkSystem.quirks_of(state, pd.id).size(), "slots": QuirkSystem.slots_of(state, pd.id)})
	row.get_node("%Max").text = Loc.t(L.MASTERY_PANEL_QUIRK_MAX, {"n": QuirkSystem.max_slots()})
	(row.get_node("%QuirkEmpty") as Control).visible = QuirkSystem.quirks_of(state, pd.id).is_empty()
	var lines: Array = _ensure(row.get_node("%Lines"), QUIRK_LINE_SCENE, ids.size())
	for i in lines.size():
		var line: Control = lines[i]
		var r: Dictionary = QuirkSystem.row(ids[i])
		var g: int = int(r["grade"])
		var col: Color = QuirkSystem.grade_color(g)
		var pill: Panel = line.get_node("%Grade")
		pill.add_theme_stylebox_override(&"panel", OutgameTheme.flat_style(col, int(pill.size.y * 0.5)))
		(pill.get_child(0) as Label).text = QuirkSystem.grade_name(g)
		var nm: Label = line.get_node("%Name")
		nm.text = QuirkSystem.name_of(ids[i])
		nm.add_theme_color_override("font_color", col)
		line.get_node("%Effect").text = QuirkSystem.effect_text(ids[i])


func _wire_chip(chip: Button) -> void:
	chip.pressed.connect(_on_chip.bind(chip))


# ── Handlers ─────────────────────────────────────────────────────────────────
func _on_chip(chip: Button) -> void:
	var pid: int = int(chip.get_meta(&"pilot_id", -1))
	var mid: int = int(chip.get_meta(&"mech_id", -1))
	MechMastery.set_research(_state, pid, -1 if MechMastery.research_mech(_state, pid) == mid else mid)
	_fill()


func _on_auto() -> void:
	MechMastery.auto_assign_all(_state)
	_fill()


## Keeps exactly `n` children in `list` (instancing missing ones, wiring them once with
## `wire`) and returns them. The scene's sample children count as reusable rows.
static func _ensure(list: Node, scene: PackedScene, n: int, wire: Callable = Callable()) -> Array:
	while list.get_child_count() > n:
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	for c in list.get_children():
		if wire.is_valid() and not c.has_meta(&"wired"):
			c.set_meta(&"wired", true)
			wire.call(c)
	while list.get_child_count() < n:
		var c: Node = scene.instantiate()
		list.add_child(c)
		if wire.is_valid():
			c.set_meta(&"wired", true)
			wire.call(c)
	return list.get_children()


## F6 단독 실행 미리보기 — 메모리 런에서 연구 메크를 자동으로 고르고 몇 주 마감을
## 돌려 숙련도가 쌓인 시트 본문(`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	MechMastery.auto_assign_all(state)
	for _w in 4:
		MechMastery.settle_week(state)
	_bind(null, state)
