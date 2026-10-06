class_name MasteryPanel
extends RefCounted

# Hub manage card 「메크 연구」 + its `HubSheet` (contract: plan §11.2 —
# `hub_summary` / `open`). The card summarises how many of my pilots have a
# weekly research mech; the sheet lists my five pilots (role display order) with
# their top mastery mechs and a chip row of their own-role mechs to pick the
# research mech from. When the knowledge area is delegated
# (`StaffSystem.is_delegated(state, "knowledge")`) a "코치에게 맡기기" button
# fills all five with the coach's plain rule (`MechMastery.auto_assign_all`).
# Each pilot card also lists that pilot's quirks (`QuirkSystem`, §14) with
# `n / slots`; research can turn up quirks at week close.

const ROW_H: float = 232.0
const ROW_GAP: float = 16.0
const PORTRAIT: float = 76.0
const CHIP_H: float = 92.0
const CHIP_GAP: float = 10.0
const ROW_PAD: float = 18.0
const AUTO_BTN_H: float = 84.0
## Quirk block under the mech chips (§14, T1): head line + one line per quirk.
const QUIRK_HEAD_H: float = 36.0
const QUIRK_LINE_H: float = 58.0


## Card summary — `{title, value, sub, owner, alert}`.
static func hub_summary(state: Dictionary) -> Dictionary:
	if not MechMastery.is_enabled(state):
		return {"title": "메크 연구", "value": "—", "sub": "런 밖", "owner": "", "alert": false}
	var pilots: Array = MechMastery.my_pilots(state)
	var missing: int = MechMastery.missing_research_count(state)
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	var per_week: int = 0
	if not pilots.is_empty():
		per_week = MechMastery.gain_preview(state, (pilots[0] as PlayerData).id,
				ConstTable.int_of("MASTERY_GAIN_RESEARCH"))
	var sub: String = "주간 연구 +%d" % per_week
	if missing > 0:
		sub = "빈 자리는 코치가 채움" if delegated else "연구 메크 미지정 %d명" % missing
	return {
		"title": "메크 연구",
		"value": "%d / %d 지정" % [pilots.size() - missing, pilots.size()],
		"sub": sub,
		"owner": StaffSystem.owner_name(state, "knowledge"),
		"alert": missing > 0 and not delegated,
	}


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, "메크 연구")
	var gm: Node = host.get_node_or_null("/root/GameManager")
	if gm == null:
		return
	_fill(sheet, gm.season_state)


# Rebuild after a tap — deferred, because the tapped button is part of the body
# being torn down and must not be freed while it is still emitting `pressed`.
static func _refill_deferred(sheet: HubSheet, state: Dictionary) -> void:
	(func() -> void:
		if is_instance_valid(sheet) and sheet.body != null:
			_fill(sheet, state)).call_deferred()


# Builds (or rebuilds after a change) the whole sheet body.
static func _fill(sheet: HubSheet, state: Dictionary) -> void:
	var body: Control = sheet.body
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var w: float = sheet.body_w()
	if not MechMastery.is_enabled(state):
		UiHelpers.mk_label(body, "진행 중인 런이 없다", 28, OutgameTheme.TEXT_SUB,
				Vector2(0, 0), Vector2(w, 40))
		sheet.set_body_height(60)
		return

	var y: float = 0.0
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	var head := UiHelpers.mk_label(body, "담당: %s   ·   지식 %d" % [
			StaffSystem.owner_name(state, "knowledge"),
			StaffSystem.effective(state, "knowledge")],
			26, OutgameTheme.ACCENT_TEXT, Vector2(0, y), Vector2(w * 0.62, 36))
	head.clip_text = true
	var any_pid: int = (MechMastery.my_pilots(state)[0] as PlayerData).id \
			if not MechMastery.my_pilots(state).is_empty() else -1
	UiHelpers.mk_label(body, "획득 배율 ×%.2f" % MechMastery.gain_mult(state, any_pid),
			24, OutgameTheme.TEXT, Vector2(w * 0.62, y), Vector2(w * 0.38, 36),
			HORIZONTAL_ALIGNMENT_RIGHT)
	y += 42.0
	var legend: Array = []
	for t in MechMastery.TIER_COUNT:
		legend.append("%s %s" % [MechMastery.tier_name(t), MechMastery.bonus_text(t)])
	UiHelpers.mk_label(body, "등급 보정 (스탯 6종)   " + "  ·  ".join(legend),
			21, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30)).clip_text = true
	y += 32.0
	UiHelpers.mk_label(body, "주 마감마다 연구 메크 +%d  ·  경기에 탄 메크 +%d  (배율 전)" % [
			ConstTable.int_of("MASTERY_GAIN_RESEARCH"), ConstTable.int_of("MASTERY_GAIN_MATCH")],
			21, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30)).clip_text = true
	y += 42.0

	if delegated:
		var auto := Button.new()
		auto.text = "코치에게 맡기기"
		auto.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(auto, 28)
		auto.position = Vector2(0, y)
		auto.size = Vector2(w, AUTO_BTN_H)
		auto.pressed.connect(func() -> void:
			MechMastery.auto_assign_all(state)
			_refill_deferred(sheet, state))
		body.add_child(auto)
		y += AUTO_BTN_H + ROW_GAP
	else:
		UiHelpers.mk_label(body, "메크 코치가 없다 — 선수마다 직접 연구 메크를 고른다", 21,
				OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30)).clip_text = true
		y += 40.0

	if QuirkSystem.is_enabled(state):
		var odds: Array = QuirkSystem.grade_odds(state)
		var parts: Array = []
		for g in QuirkSystem.GRADE_COUNT:
			parts.append("%s %d%%" % [QuirkSystem.grade_name(g), roundi(float(odds[g]))])
		UiHelpers.mk_label(body, "기벽 — 연구 메크가 있으면 주 마감 %d%% 확률로 획득  ·  %s" % [
				ConstTable.int_of("QUIRK_RESEARCH_CHANCE"), "  ".join(parts)],
				21, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30)).clip_text = true
		y += 40.0

	for raw in MechMastery.my_pilots(state):
		var row_h: float = ROW_H + _quirk_block_h(state, (raw as PlayerData).id)
		_build_pilot_row(sheet, state, raw as PlayerData, y, w, row_h)
		y += row_h + ROW_GAP
	sheet.set_body_height(y)


# ── Quirks (§14, T1) — under the mech chips of each pilot card ───────────────
## Extra card height for the quirk block (0 outside a run).
static func _quirk_block_h(state: Dictionary, pilot_id: int) -> float:
	if not QuirkSystem.is_enabled(state):
		return 0.0
	var n: int = QuirkSystem.quirks_of(state, pilot_id).size()
	return QUIRK_HEAD_H + float(maxi(1, n)) * QUIRK_LINE_H + 6.0


## "기벽 n/slots" head, then one line per quirk: grade pill · name · effect.
static func _build_quirk_block(card: Panel, state: Dictionary, pd: PlayerData,
		y: float, w: float) -> void:
	var ids: Array = QuirkSystem.quirks_of(state, pd.id)
	var slots: int = QuirkSystem.slots_of(state, pd.id)
	var inner_w: float = w - ROW_PAD * 2.0
	OutgameTheme.add_divider(card, Vector2(ROW_PAD, y), inner_w)
	UiHelpers.mk_label(card, "기벽  %d / %d" % [ids.size(), slots], 22, OutgameTheme.TEXT,
			Vector2(ROW_PAD, y + 4.0), Vector2(inner_w * 0.5, 30))
	UiHelpers.mk_label(card, "최대 %d칸" % QuirkSystem.max_slots(), 19, OutgameTheme.TEXT_FAINT,
			Vector2(ROW_PAD + inner_w * 0.5, y + 6.0), Vector2(inner_w * 0.5, 28),
			HORIZONTAL_ALIGNMENT_RIGHT)
	var ly: float = y + QUIRK_HEAD_H
	if ids.is_empty():
		UiHelpers.mk_label(card, "없음 — 기벽 훈련 타일 · 메크 연구로 얻는다", 20,
				OutgameTheme.TEXT_SUB, Vector2(ROW_PAD, ly + 8.0), Vector2(inner_w, 30)).clip_text = true
		return
	for id in ids:
		var r: Dictionary = QuirkSystem.row(int(id))
		if r.is_empty():
			continue
		var g: int = int(r["grade"])
		OutgameTheme.add_chip(card, QuirkSystem.grade_name(g), Vector2(ROW_PAD, ly + 4.0),
				Vector2(64.0, 26.0), QuirkSystem.grade_color(g), OutgameTheme.TEXT_ON_FILL, 17)
		var nm := UiHelpers.mk_label(card, String(r["name"]), 22, QuirkSystem.grade_color(g),
				Vector2(ROW_PAD + 74.0, ly + 1.0), Vector2(inner_w - 74.0, 30))
		nm.clip_text = true
		var eff := UiHelpers.mk_label(card, QuirkSystem.effect_text(int(id)), 18,
				OutgameTheme.TEXT_SUB, Vector2(ROW_PAD + 74.0, ly + 29.0),
				Vector2(inner_w - 74.0, 26))
		eff.clip_text = true
		ly += QUIRK_LINE_H


static func _build_pilot_row(sheet: HubSheet, state: Dictionary, pd: PlayerData,
		y: float, w: float, row_h: float = ROW_H) -> void:
	var card: Panel = OutgameTheme.add_card(sheet.body, Vector2(0, y), Vector2(w, row_h), 16)
	if row_h > ROW_H:
		_build_quirk_block(card, state, pd, ROW_H - 6.0, w)
	var inner_w: float = w - ROW_PAD * 2.0
	OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pd.id),
			Vector2(ROW_PAD, ROW_PAD), PORTRAIT,
			OutgameTheme.ROLE_COLORS[clampi(pd.role, 0, 4)])
	var tx: float = ROW_PAD + PORTRAIT + 16.0
	var name_lbl := UiHelpers.mk_label(card, pd.name, 30, OutgameTheme.TEXT,
			Vector2(tx, ROW_PAD - 4.0), Vector2(inner_w * 0.5, 40))
	name_lbl.clip_text = true
	var research: int = MechMastery.research_mech(state, pd.id)
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	var res_txt: String = "연구: " + MechMastery.mech_name(research)
	var res_col: Color = OutgameTheme.ACCENT_TEXT
	if research < 0:
		# Delegated: the coach fills it at week close — not an error.
		res_txt = "주 마감에 코치가 지정" if delegated else "연구 미지정"
		res_col = OutgameTheme.TEXT_SUB if delegated else OutgameTheme.NEGATIVE
	UiHelpers.mk_label(card, res_txt, 24, res_col,
			Vector2(w * 0.5, ROW_PAD), Vector2(w * 0.5 - ROW_PAD, 34),
			HORIZONTAL_ALIGNMENT_RIGHT).clip_text = true

	var tops: Array = []
	for e in MechMastery.top_mechs(state, pd.id, 3):
		var v: int = int(e["value"])
		tops.append("%s %s %d" % [MechMastery.mech_name(int(e["mech_id"])),
				MechMastery.tier_name(MechMastery.tier_of(v)), v])
	var top_lbl := UiHelpers.mk_label(card, "%s  ·  숙련 상위  %s" % [
			String(OutgameTheme.ROLE_NAMES[clampi(pd.role, 0, 4)]), "  ·  ".join(tops)],
			20, OutgameTheme.TEXT_SUB, Vector2(tx, ROW_PAD + 40.0),
			Vector2(w - tx - ROW_PAD, 30))
	top_lbl.clip_text = true

	# Own-role mech chips — tap to set the research mech (tap the selected one to clear).
	var mechs: Array = MechMastery.mechs_of_role(pd.role)
	var n: int = maxi(1, mechs.size())
	var cw: float = (inner_w - CHIP_GAP * float(n - 1)) / float(n)
	var cy: float = ROW_PAD + PORTRAIT + 24.0
	for i in mechs.size():
		var mid: int = int((mechs[i] as Dictionary)["id"])
		var v: int = MechMastery.value(state, pd.id, mid)
		var t: int = MechMastery.tier_of(v)
		var chip := Button.new()
		chip.text = "%s\n%s %d" % [MechMastery.mech_name(mid), MechMastery.tier_name(t), v]
		chip.focus_mode = Control.FOCUS_NONE
		chip.clip_text = true
		if mid == research:
			OutgameTheme.style_primary_button(chip, 20)
		else:
			OutgameTheme.style_ghost_button(chip, 20)
		chip.position = Vector2(ROW_PAD + float(i) * (cw + CHIP_GAP), cy)
		chip.size = Vector2(cw, CHIP_H)
		var pid: int = pd.id
		chip.pressed.connect(func() -> void:
			MechMastery.set_research(state, pid,
					-1 if MechMastery.research_mech(state, pid) == mid else mid)
			_refill_deferred(sheet, state))
		card.add_child(chip)
		# Tier colour bar along the chip's bottom edge.
		var bar := ColorRect.new()
		bar.color = MechMastery.tier_color(t)
		bar.position = Vector2(10.0, CHIP_H - 8.0)
		bar.size = Vector2(cw - 20.0, 4.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(bar)
