class_name StaffPanel
extends VBoxContainer

# Hub manage card 「스태프」 + its `HubSheet` detail. Contract: plan §11.2
# (`hub_summary` / `open`). Everything is read through `StaffSystem` — this file
# only fills the sheet.
#
# Card : delegated count (n/6), weakest area, assistant (or 감독) as owner,
#        alert dot while a negative temporary mod is active.
# Sheet: six stat rows (effective value, who covers it, manager vs staff
#        values — cover rule = max), active `staff_mods`, equipped manager
#        traits + bonus points (M8), staff list with job
#        and weekly salary, and the areas the manager handles personally.
#
# **The sheet body's layout lives in `StaffPanel.tscn`** (+ item scenes `StaffStatRow` ·
# `StaffTraitRow` · `StaffMemberRow`). `open` puts one instance into the sheet's `body`;
# this script fills `%` nodes, instances the list rows and applies data colours
# (lead-bar cards, bar fills, owner / mod / chip colours). The sheet's scroll height
# follows this node's height (`resized`). The sheet is read-only — filled once.

const SCENE_PATH: String = "res://features/season/staff/StaffPanel.tscn"
const STAT_ROW_SCENE: PackedScene = preload("res://features/season/staff/StaffStatRow.tscn")
const TRAIT_ROW_SCENE: PackedScene = preload("res://features/season/staff/StaffTraitRow.tscn")
const MEMBER_ROW_SCENE: PackedScene = preload("res://features/season/staff/StaffMemberRow.tscn")

## What the manager does by hand when a stat is not delegated.
const DIRECT_TASKS: Dictionary = {
	"training": "훈련판 편성을 직접 짭니다",
	"tactics": "전술 연구 — 훈련 등급 해금을 감독 값으로 엽니다",
	"knowledge": "메크 연구 지정을 직접 합니다",
	"mental": "선수 사건 대응을 감독 값으로 처리합니다",
	"analysis": "상대 분석 자료를 직접 해석합니다",
	"finance": "예산 배분 · 시설 관리를 직접 합니다",
}

var _sheet: HubSheet = null


## Card summary — `{title, value, sub, owner, alert}`.
static func hub_summary(state: Dictionary) -> Dictionary:
	var delegated: int = 0
	var weakest: String = ""
	var weakest_v: int = StaffSystem.STAT_MAX + 1
	for s in StaffSystem.STATS:
		if StaffSystem.is_delegated(state, s):
			delegated += 1
		var v: int = StaffSystem.effective(state, s)
		if v < weakest_v:
			weakest_v = v
			weakest = s
	var asst: Dictionary = StaffSystem.assistant(state)
	var alert: bool = false
	for raw in (state.get("staff_mods", []) as Array):
		if int((raw as Dictionary).get("delta", 0)) < 0:
			alert = true
	return {
		"title": "스태프",
		"value": "위임 %d/%d" % [delegated, StaffSystem.STATS.size()],
		"sub": "약점 %s %d" % [StaffSystem.STAT_LABELS.get(weakest, "—"), weakest_v],
		"owner": String(asst.get("name", "감독")),
		"alert": alert,
	}


## Instantiates the scene. `StaffPanel.new()` is an empty box — don't use it.
static func create() -> StaffPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as StaffPanel


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, "스태프")
	var panel := create()
	sheet.body.add_child(panel)
	panel._bind(sheet, host.get_node("/root/GameManager").season_state)


func _ready() -> void:
	resized.connect(_fit_sheet)


func _bind(sheet: HubSheet, state: Dictionary) -> void:
	_sheet = sheet
	_fill_stats(state)
	_fill_mods(state)
	_fill_traits(state)
	_fill_staff(state)
	_fill_direct(state)
	_fit_sheet()


## The sheet scrolls exactly this node's height (the scene's `Tail` is the bottom gap).
func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


# ── Sheet pieces ──────────────────────────────────────────────────────────────
func _fill_stats(state: Dictionary) -> void:
	var rows: Array = _rows(%StatRows, STAT_ROW_SCENE, StaffSystem.STATS.size())
	for i in rows.size():
		var row: Panel = rows[i]
		var s: String = String(StaffSystem.STATS[i])
		var delegated: bool = StaffSystem.owner(state, s) != StaffSystem.OWNER_MANAGER
		var col: Color = OutgameTheme.POSITIVE if delegated else OutgameTheme.ACCENT
		row.add_theme_stylebox_override(&"panel", OutgameTheme.lead_bar_style(col, 14))
		var eff: int = StaffSystem.effective(state, s)
		row.get_node("%Stat").text = String(StaffSystem.STAT_LABELS[s])
		row.get_node("%Value").text = "%d" % eff
		_set_fill(row.get_node("%Fill"), float(eff) / float(StaffSystem.STAT_MAX), col)
		var owner_l: Label = row.get_node("%Owner")
		owner_l.text = "담당 " + _owner_text(state, s)
		owner_l.add_theme_color_override("font_color",
				OutgameTheme.POSITIVE if delegated else OutgameTheme.ACCENT_TEXT)
		row.get_node("%Compare").text = _compare_text(state, s)


## "감독" / "어시스턴트 매니저 한서준" / "훈련 코치 강민호".
static func _owner_text(state: Dictionary, s: String) -> String:
	match StaffSystem.owner(state, s):
		StaffSystem.OWNER_ASSISTANT:
			return "%s %s" % [StaffSystem.JOB_LABELS["assistant"], StaffSystem.owner_name(state, s)]
		StaffSystem.OWNER_STAFF:
			var st: Dictionary = StaffSystem.staff_for(state, s)
			return "%s %s" % [StaffSystem.JOB_LABELS.get(String(st.get("job", "")), "스태프"),
					String(st.get("name", "—"))]
	return "감독 (직접)"


## "감독 6 (+2) · 어시 14 · 분석가 16" — every candidate of the cover rule.
static func _compare_text(state: Dictionary, s: String) -> String:
	var parts: Array = []
	var mod: int = StaffSystem.mod_total(state, s)
	var mgr: String = "감독 %d" % StaffSystem.manager_value(state, s)
	if mod != 0:
		mgr += " (%+d)" % mod
	parts.append(mgr)
	var asst: Dictionary = StaffSystem.assistant(state)
	if not asst.is_empty():
		parts.append("어시 %d" % int((asst.get("stats", {}) as Dictionary).get(s, 0)))
	var st: Dictionary = StaffSystem.staff_for(state, s)
	if not st.is_empty():
		parts.append("%s %d" % [StaffSystem.JOB_LABELS.get(String(st.get("job", "")), "스태프"),
				int((st.get("stats", {}) as Dictionary).get(s, 0))])
	return " · ".join(parts)


func _fill_mods(state: Dictionary) -> void:
	var mods: Array = state.get("staff_mods", [])
	%ModsEmpty.visible = mods.is_empty()
	%ModsTail.visible = not mods.is_empty()
	var texts: Array = []
	var colors: Array = []
	for raw in mods:
		var m: Dictionary = raw
		var delta: int = int(m.get("delta", 0))
		var src: String = String(m.get("source", ""))
		var text: String = "%s %+d · 남은 %d주" % [
			StaffSystem.STAT_LABELS.get(String(m.get("stat", "")), "?"), delta,
			int(m.get("weeks_left", 0))]
		if src != "":
			text += " · " + src
		texts.append(text)
		colors.append(OutgameTheme.POSITIVE if delta > 0 else OutgameTheme.NEGATIVE)
	var lines: Array = _lines(%Mods, texts)
	for i in lines.size():
		(lines[i] as Label).add_theme_color_override("font_color", colors[i])


## Equipped manager traits of the run (M8, `run_setup.traits`) — name, rarity,
## +/- polarity and the filled-in description. Lead bar green = "+", red = "-".
func _fill_traits(state: Dictionary) -> void:
	%TraitsSub.text = "보너스 점수 %d · 장착 %d/%d" % [
			int((state.get("run_setup", {}) as Dictionary).get("bonus_points", 0)),
			TraitSystem.run_traits(state).size(), TraitSystem.slot_count()]
	var ids: Array = []
	for raw in TraitSystem.run_traits(state):
		if not TraitSystem.row(int(raw)).is_empty():
			ids.append(int(raw))
	%TraitsEmpty.visible = ids.is_empty()
	%TraitsTail.visible = not ids.is_empty()
	var rows: Array = _rows(%Traits, TRAIT_ROW_SCENE, ids.size())
	for i in rows.size():
		var row: Panel = rows[i]
		var tid: int = ids[i]
		var r: Dictionary = TraitSystem.row(tid)
		var pos: bool = TraitSystem.is_positive(tid)
		var sign_color: Color = OutgameTheme.POSITIVE if pos else OutgameTheme.NEGATIVE
		row.add_theme_stylebox_override(&"panel", OutgameTheme.lead_bar_style(sign_color, 12))
		_chip(row.get_node("%Sign"), "+" if pos else "−", sign_color)
		row.get_node("%Name").text = String(r.get("name", ""))
		row.get_node("%Desc").text = TraitSystem.desc_of(tid)
		var rarity: int = int(r.get("rarity", 0))
		_chip(row.get_node("%Rarity"), TraitSystem.rarity_name(rarity), TraitUi.rarity_color(rarity))


func _fill_staff(state: Dictionary) -> void:
	%StaffSub.text = "주급 합계 %d" % StaffSystem.weekly_salary_total(state)
	var staff: Array = (state.get("run_setup", {}) as Dictionary).get("staff", [])
	%StaffEmpty.visible = staff.is_empty()
	%MembersTail.visible = not staff.is_empty()
	var rows: Array = _rows(%Members, MEMBER_ROW_SCENE, staff.size())
	for i in rows.size():
		var row: Control = rows[i]
		var e: Dictionary = staff[i]
		var job: String = String(e.get("job", ""))
		row.get_node("%Name").text = String(e.get("name", "—"))
		row.get_node("%Job").text = "%s · %s" % [StaffSystem.JOB_LABELS.get(job, job), _best_stats_text(e)]
		row.get_node("%Salary").text = "주급 %d" % int(e.get("salary", 0))


## A dedicated staff shows their field; the assistant shows the top two stats.
static func _best_stats_text(e: Dictionary) -> String:
	var stats: Dictionary = e.get("stats", {})
	var field: String = String(StaffSystem.JOB_STAT.get(String(e.get("job", "")), ""))
	if field != "":
		return "%s %d" % [StaffSystem.STAT_LABELS[field], int(stats.get(field, 0))]
	var keys: Array = StaffSystem.STATS.duplicate()
	keys.sort_custom(func(a, b): return int(stats.get(a, 0)) > int(stats.get(b, 0)))
	return "%s %d · %s %d" % [StaffSystem.STAT_LABELS[keys[0]], int(stats.get(keys[0], 0)),
			StaffSystem.STAT_LABELS[keys[1]], int(stats.get(keys[1], 0))]


func _fill_direct(state: Dictionary) -> void:
	var lines: Array = []
	for s in StaffSystem.STATS:
		if not StaffSystem.is_delegated(state, s):
			lines.append(UiHelpers.keep_words("· %s — %s (감독 %d)" % [StaffSystem.STAT_LABELS[s],
					DIRECT_TASKS[s], StaffSystem.manager_value(state, s)]))
	# Interviews and outings always read the manager's own mental, delegated or not.
	lines.append(UiHelpers.keep_words("· 면담 · 외출 — 언제나 감독이 직접 (멘탈 %d)" % \
			StaffSystem.manager_value(state, "mental")))
	_lines(%Direct, lines)


# ── Helpers ──────────────────────────────────────────────────────────────────
## Fills a pill (`Panel` + centred label child) — fill colour is data; radius = half height
## like `OutgameTheme.add_chip`.
static func _chip(chip: Panel, text: String, bg: Color) -> void:
	chip.add_theme_stylebox_override(&"panel", OutgameTheme.flat_style(bg, int(chip.size.y * 0.5)))
	(chip.get_child(0) as Label).text = text


## Stat bar fill: width = ratio of the track (anchor), colour = data.
static func _set_fill(fill: Panel, ratio: float, col: Color) -> void:
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.visible = ratio > 0.0
	var sb := fill.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	sb.bg_color = col
	fill.add_theme_stylebox_override(&"panel", sb)


## Replaces the scene's sample rows with `n` fresh instances (the sheet fills once).
static func _rows(list: Node, scene: PackedScene, n: int) -> Array:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for i in n:
		list.add_child(scene.instantiate())
	(list as CanvasItem).visible = n > 0
	return list.get_children()


## Template-line lists: the scene's first Label is the template, duplicated per text;
## the list hides when empty. Returns the labels in use.
static func _lines(list: Node, texts: Array) -> Array:
	if list.get_child_count() == 0:
		return []
	var tpl: Label = list.get_child(0)
	for i in range(list.get_child_count() - 1, 0, -1):
		var extra: Node = list.get_child(i)
		list.remove_child(extra)
		extra.queue_free()
	for i in range(1, texts.size()):
		list.add_child(tpl.duplicate())
	for i in texts.size():
		(list.get_child(i) as Label).text = String(texts[i])
	(list as CanvasItem).visible = not texts.is_empty()
	return list.get_children().slice(0, texts.size())
