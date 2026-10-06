class_name StaffPanel
extends RefCounted

# Hub manage card 「스태프」 + its `HubSheet` detail. Contract: plan §11.2
# (`hub_summary` / `open`). Everything is read through `StaffSystem` — this file
# only draws.
#
# Card : delegated count (n/6), weakest area, assistant (or 감독) as owner,
#        alert dot while a negative temporary mod is active.
# Sheet: six stat rows (effective value, who covers it, manager vs staff
#        values — cover rule = max), active `staff_mods`, equipped manager
#        traits + bonus points (M8), staff list with job
#        and weekly salary, and the areas the manager handles personally.

## What the manager does by hand when a stat is not delegated.
const DIRECT_TASKS: Dictionary = {
	"training": "훈련판 편성을 직접 짭니다",
	"tactics": "전술 연구 — 훈련 등급 해금을 감독 값으로 엽니다",
	"knowledge": "메크 연구 지정을 직접 합니다",
	"mental": "선수 사건 대응을 감독 값으로 처리합니다",
	"analysis": "상대 분석 자료를 직접 해석합니다",
	"finance": "예산 배분 · 시설 관리를 직접 합니다",
}

const ROW_H: float = 116.0
const GAP: float = 10.0


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


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, "스태프")
	var state: Dictionary = host.get_node("/root/GameManager").season_state
	var body: Control = sheet.body
	var w: float = sheet.body_w() - 16.0   # leave room for the scroll bar
	var y: float = 0.0

	y = _section(body, y, w, "능력치", "유효값 = 감독(보정 포함) · 어시스턴트 · 전담 스태프 중 최댓값")
	for s in StaffSystem.STATS:
		y += _stat_row(body, Vector2(0, y), w, state, s) + GAP

	y += 14.0
	y = _section(body, y, w, "일시 보정", "")
	y = _mods_block(body, y, w, state)

	y += 14.0
	y = _section(body, y, w, "장착 특성", "보너스 점수 %d · 장착 %d/%d" % [
			int((state.get("run_setup", {}) as Dictionary).get("bonus_points", 0)),
			TraitSystem.run_traits(state).size(), TraitSystem.slot_count()])
	y = _traits_block(body, y, w, state)

	y += 14.0
	y = _section(body, y, w, "스태프", "주급 합계 %d" % StaffSystem.weekly_salary_total(state))
	y = _staff_block(body, y, w, state)

	y += 14.0
	y = _section(body, y, w, "직접 해야 하는 일", "")
	y = _direct_block(body, y, w, state)
	sheet.set_body_height(y + 20.0)


# ── Sheet pieces ──────────────────────────────────────────────────────────────
static func _section(body: Control, y: float, w: float, title: String, sub: String) -> float:
	UiHelpers.mk_label(body, title, 28, OutgameTheme.TEXT, Vector2(0, y), Vector2(w, 38))
	if sub != "":
		UiHelpers.mk_label(body, sub, 18, OutgameTheme.TEXT_SUB,
				Vector2(0, y + 40), Vector2(w, 26))
		return y + 76.0
	return y + 48.0


static func _stat_row(body: Control, pos: Vector2, w: float, state: Dictionary, s: String) -> float:
	var owner: String = StaffSystem.owner(state, s)
	var delegated: bool = owner != StaffSystem.OWNER_MANAGER
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(
			OutgameTheme.POSITIVE if delegated else OutgameTheme.ACCENT, 14))
	card.position = pos
	card.size = Vector2(w, ROW_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(card)

	var eff: int = StaffSystem.effective(state, s)
	UiHelpers.mk_label(card, String(StaffSystem.STAT_LABELS[s]), 26, OutgameTheme.TEXT,
			Vector2(22, 12), Vector2(110, 34))
	UiHelpers.mk_label(card, "%d" % eff, 44, OutgameTheme.TEXT,
			Vector2(22, 48), Vector2(110, 52))

	# Value bar 1..20.
	var bar_x: float = 140.0
	var bar_w: float = w - bar_x - 22.0
	var track := ColorRect.new()
	track.color = OutgameTheme.SURFACE_SUNK
	track.position = Vector2(bar_x, 24)
	track.size = Vector2(bar_w, 10)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	var fill := ColorRect.new()
	fill.color = OutgameTheme.POSITIVE if delegated else OutgameTheme.ACCENT
	fill.position = track.position
	fill.size = Vector2(bar_w * float(eff) / float(StaffSystem.STAT_MAX), 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	UiHelpers.mk_label(card, "담당 " + _owner_text(state, s), 21,
			OutgameTheme.POSITIVE if delegated else OutgameTheme.ACCENT_TEXT,
			Vector2(bar_x, 42), Vector2(bar_w, 30))
	UiHelpers.mk_label(card, _compare_text(state, s), 18, OutgameTheme.TEXT_SUB,
			Vector2(bar_x, 76), Vector2(bar_w, 26))
	return ROW_H


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


static func _mods_block(body: Control, y: float, w: float, state: Dictionary) -> float:
	var mods: Array = state.get("staff_mods", [])
	if mods.is_empty():
		UiHelpers.mk_label(body, "걸린 보정 없음", 22, OutgameTheme.TEXT_FAINT,
				Vector2(0, y), Vector2(w, 32))
		return y + 40.0
	for raw in mods:
		var m: Dictionary = raw
		var delta: int = int(m.get("delta", 0))
		var src: String = String(m.get("source", ""))
		var text: String = "%s %+d · 남은 %d주" % [
			StaffSystem.STAT_LABELS.get(String(m.get("stat", "")), "?"), delta,
			int(m.get("weeks_left", 0))]
		if src != "":
			text += " · " + src
		UiHelpers.mk_label(body, text, 22,
				OutgameTheme.POSITIVE if delta > 0 else OutgameTheme.NEGATIVE,
				Vector2(0, y), Vector2(w, 32))
		y += 38.0
	return y + 4.0


## Equipped manager traits of the run (M8, `run_setup.traits`) — name, rarity,
## +/- polarity and the filled-in description. Lead bar green = "+", red = "-".
static func _traits_block(body: Control, y: float, w: float, state: Dictionary) -> float:
	var ids: Array = TraitSystem.run_traits(state)
	if ids.is_empty():
		UiHelpers.mk_label(body, "장착한 특성 없음", 22, OutgameTheme.TEXT_FAINT,
				Vector2(0, y), Vector2(w, 32))
		return y + 40.0
	var row_h: float = 84.0
	for raw in ids:
		var tid: int = int(raw)
		var r: Dictionary = TraitSystem.row(tid)
		if r.is_empty():
			continue
		var pos: bool = TraitSystem.is_positive(tid)
		var sign_color: Color = OutgameTheme.POSITIVE if pos else OutgameTheme.NEGATIVE
		var card := Panel.new()
		card.add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(sign_color, 12))
		card.position = Vector2(0, y)
		card.size = Vector2(w, row_h)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(card)
		OutgameTheme.add_chip(card, "+" if pos else "−", Vector2(22, 22), Vector2(40, 40),
				sign_color, OutgameTheme.TEXT_ON_FILL, 24)
		UiHelpers.mk_label(card, String(r.get("name", "")), 24, OutgameTheme.TEXT,
				Vector2(78, 8), Vector2(w - 260, 32))
		UiHelpers.mk_label(card, TraitSystem.desc_of(tid), 18, OutgameTheme.TEXT_SUB,
				Vector2(78, 44), Vector2(w - 260, 26))
		TraitUi.add_rarity_chip(card, int(r.get("rarity", 0)),
				Vector2(w - 150, 22), Vector2(128, 38), 18)
		y += row_h + 8.0
	return y + 4.0


static func _staff_block(body: Control, y: float, w: float, state: Dictionary) -> float:
	var staff: Array = (state.get("run_setup", {}) as Dictionary).get("staff", [])
	if staff.is_empty():
		UiHelpers.mk_label(body, "고용된 스태프 없음 — 모든 영역을 감독이 맡습니다", 22,
				OutgameTheme.TEXT_FAINT, Vector2(0, y), Vector2(w, 32))
		return y + 40.0
	var row_h: float = 76.0
	for raw in staff:
		var e: Dictionary = raw
		var card: Panel = OutgameTheme.add_card(body, Vector2(0, y), Vector2(w, row_h), 12)
		var job: String = String(e.get("job", ""))
		UiHelpers.mk_label(card, String(e.get("name", "—")), 24, OutgameTheme.TEXT,
				Vector2(20, 8), Vector2(w * 0.45, 32))
		UiHelpers.mk_label(card, "%s · %s" % [StaffSystem.JOB_LABELS.get(job, job), _best_stats_text(e)],
				18, OutgameTheme.TEXT_SUB, Vector2(20, 42), Vector2(w - 220, 26))
		UiHelpers.mk_label(card, "주급 %d" % int(e.get("salary", 0)), 22, OutgameTheme.TEXT,
				Vector2(w - 200, 22), Vector2(180, 32), HORIZONTAL_ALIGNMENT_RIGHT)
		y += row_h + 8.0
	return y + 4.0


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


static func _direct_block(body: Control, y: float, w: float, state: Dictionary) -> float:
	var lines: Array = []
	for s in StaffSystem.STATS:
		if not StaffSystem.is_delegated(state, s):
			lines.append("%s — %s (감독 %d)" % [StaffSystem.STAT_LABELS[s], DIRECT_TASKS[s],
					StaffSystem.manager_value(state, s)])
	# Interviews and outings always read the manager's own mental, delegated or not.
	lines.append("면담 · 외출 — 언제나 감독이 직접 (멘탈 %d)" % StaffSystem.manager_value(state, "mental"))
	for t in lines:
		var l := UiHelpers.mk_label(body, UiHelpers.keep_words("· " + String(t)), 22,
				OutgameTheme.TEXT, Vector2(0, y), Vector2(w, 32))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var n: int = maxi(1, l.get_line_count())
		l.size.y = 32.0 * n
		y += 32.0 * n + 6.0
	return y
