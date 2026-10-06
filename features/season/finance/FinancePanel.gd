class_name FinancePanel
extends RefCounted

# Hub manage card 「재무」 + its `HubSheet` detail (contract: plan §11.2).
# `HubView`'s manage row draws `hub_summary`, a press calls `open(host)`.
#
# The sheet is rebuilt in place (`_render`) after every change made inside it
# (allocation step, facility upgrade) — the sheet itself stays open, so the
# hub's `closed → refresh` hook (wired by `HubView`) still fires once at the end.
# Every tap target lives inside the sheet's `DragScroll` body, so they are plain
# `Button`s (taps survive; a vertical drag scrolls) — no `HSlider`, whose drag
# the scroll would swallow. Allocation is a −/+ stepper per axis instead.
#
# 특별 지출 (§14 T6): one row per `finance_specials.csv` entry with a two-step
# buy button (like the facility upgrade). Only one row can be armed at a time —
# `_render`'s `special_armed` is that row's id.

const ROW_H: float = 42.0
const SECTION_GAP: float = 36.0
const AXIS_COLORS: Dictionary = {
	"training": OutgameTheme.ACCENT,
	"facility": OutgameTheme.LINK,
	"welfare": OutgameTheme.POSITIVE,
}
const RECENT_ROWS: int = 6
const SCROLLBAR_PAD: float = 24.0


## Card summary — `{title, value, sub, owner, alert}`.
static func hub_summary(state: Dictionary) -> Dictionary:
	var f: Dictionary = state.get("finance", {})
	if f.is_empty():
		return {"title": "재무", "value": "—", "sub": "", "owner": "", "alert": false}
	var last: Dictionary = FinanceSystem.last_week(state)
	var sub: String = "첫 정산 전"
	if not last.is_empty():
		sub = "지난 주 %s" % FinanceSystem.fmt_signed(int(last.get("net", 0)))
		if _hard_cut(last):
			sub += " · 삭감"
	return {
		"title": "재무 · 시설 Lv%d" % FinanceSystem.facility_level(state),
		"value": FinanceSystem.fmt(FinanceSystem.balance(state)),
		"sub": sub,
		"owner": StaffSystem.owner_name(state, "finance"),
		"alert": FinanceSystem.is_low_balance(state) or FinanceSystem.penalty_weeks(state) > 0
				or (not last.is_empty() and _hard_cut(last)),
	}


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, "재무 · 시설")
	var gm: Node = host.get_node_or_null("/root/GameManager")
	var state: Dictionary = gm.season_state if gm != null else {}
	_render(sheet, state, false)


# ── Sheet ────────────────────────────────────────────────────────────────────
static func _render(sheet: HubSheet, state: Dictionary, upgrade_armed: bool,
		special_armed: String = "") -> void:
	var body: Control = sheet.body
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	# Keep right-aligned figures clear of the scroll bar.
	var w: float = sheet.body_w() - SCROLLBAR_PAD
	if (state.get("finance", {}) as Dictionary).is_empty():
		_lbl(body, "진행 중인 런이 없습니다", 28, OutgameTheme.TEXT_SUB, Vector2(0, 0), Vector2(w, 40))
		sheet.set_body_height(60)
		return
	var y: float = 0.0
	y = _build_header(body, state, w, y)
	y = _build_last_week(body, state, w, y + SECTION_GAP)
	y = _build_allocation(sheet, state, w, y + SECTION_GAP)
	y = _build_facility(sheet, state, w, y + SECTION_GAP, upgrade_armed)
	y = _build_specials(sheet, state, w, y + SECTION_GAP, special_armed)
	y = _build_history(body, state, w, y + SECTION_GAP)
	sheet.set_body_height(y + 24.0)


static func _build_header(body: Control, state: Dictionary, w: float, y: float) -> float:
	var half: float = w * 0.5
	_lbl(body, "잔고", 24, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(half, 30))
	_lbl(body, "시설 적립금", 24, OutgameTheme.TEXT_SUB, Vector2(half, y), Vector2(half, 30),
			HORIZONTAL_ALIGNMENT_RIGHT)
	var bal_col: Color = OutgameTheme.NEGATIVE if FinanceSystem.is_low_balance(state) else OutgameTheme.TEXT
	_lbl(body, FinanceSystem.fmt(FinanceSystem.balance(state)), 60, bal_col,
			Vector2(0, y + 32), Vector2(half, 72))
	_lbl(body, FinanceSystem.fmt(FinanceSystem.facility_fund(state)), 44, OutgameTheme.LINK,
			Vector2(half, y + 46), Vector2(half, 56), HORIZONTAL_ALIGNMENT_RIGHT)
	y += 116.0

	var who: String = StaffSystem.owner_name(state, "finance")
	var owner_line: String = "담당: 감독 — 흑자 배분을 직접 정합니다"
	if StaffSystem.is_delegated(state, "finance"):
		owner_line = "담당: %s — 흑자를 자동으로 배분합니다" % who
	_lbl(body, owner_line, 24, OutgameTheme.ACCENT_TEXT, Vector2(0, y), Vector2(w, 32))
	y += 40.0

	var proj: Dictionary = FinanceSystem.projection(state)
	_lbl(body, "이번 주 예상 수지 %s  (수입 %s · 지출 %s, 보너스 포함)" % [
			FinanceSystem.fmt_signed(int(proj["net"])), FinanceSystem.fmt(int(proj["income"])),
			FinanceSystem.fmt(int(proj["expense"]))],
			22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
	y += 36.0

	if FinanceSystem.is_low_balance(state):
		_lbl(body, "잔고가 한 주 고정 지출(%s)보다 적습니다 — 적자가 나면 강제 삭감" % \
				FinanceSystem.fmt(FinanceSystem.weekly_fixed_cost(state)),
				22, OutgameTheme.NEGATIVE, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	var pw: int = FinanceSystem.penalty_weeks(state)
	if pw > 0:
		_lbl(body, "훈련 지원 삭감 중 — %d주 남음 (훈련 EXP −%d%%)" % [
				pw, ConstTable.int_of("FINANCE_UNPAID_TRAIN_PENALTY_PCT")],
				22, OutgameTheme.NEGATIVE, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	return y


static func _build_last_week(body: Control, state: Dictionary, w: float, y: float) -> float:
	y = _section(body, "지난 주 정산", w, y)
	var last: Dictionary = FinanceSystem.last_week(state)
	if last.is_empty():
		_lbl(body, "아직 정산 기록이 없습니다 — 일요일 주 마감에 정산됩니다", 22,
				OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		return y + 36.0
	y = _amount_row(body, _sponsor_label(last, state), int(last.get("sponsor", 0)), w, y)
	y = _amount_row(body, "성적 보너스 (%d승 %d패)" % [int(last.get("wins", 0)), int(last.get("losses", 0))],
			int(last.get("bonus", 0)), w, y)
	y = _amount_row(body, "스태프 연봉", -int(last.get("salaries", 0)), w, y)
	y = _amount_row(body, _upkeep_label(last, state), -int(last.get("upkeep", 0)), w, y)
	OutgameTheme.add_divider(body, Vector2(0, y + 4), w)
	y += 12.0
	var net: int = int(last.get("net", 0))
	_lbl(body, "순수지", 28, OutgameTheme.TEXT, Vector2(0, y), Vector2(w * 0.6, ROW_H))
	_lbl(body, FinanceSystem.fmt_signed(net), 30, _signed_color(net),
			Vector2(w * 0.4, y), Vector2(w * 0.6, ROW_H), HORIZONTAL_ALIGNMENT_RIGHT)
	y += ROW_H + 4.0
	if net >= 0:
		var a: Dictionary = last.get("alloc", {})
		_lbl(body, "→ 잔고 적립 %s · 훈련 %s · 시설 적립 %s · 복지 %s" % [
				FinanceSystem.fmt(int(last.get("reserve", 0))), FinanceSystem.fmt(int(a.get("training", 0))),
				FinanceSystem.fmt(int(a.get("facility", 0))), FinanceSystem.fmt(int(a.get("welfare", 0)))],
				22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	for cut in (last.get("cuts", []) as Array):
		_lbl(body, "삭감 · " + String(cut), 22, OutgameTheme.NEGATIVE, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	var spend: int = int(last.get("special_spend", 0))
	if spend > 0:
		_lbl(body, "특별 지출 −%s (구매 즉시 잔고에서 차감 · %s)" % [FinanceSystem.fmt(spend),
				", ".join(PackedStringArray(last.get("special_buys", [])))],
				22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	var ended: Array = last.get("specials_expired", [])
	if not ended.is_empty():
		_lbl(body, "특별 지출 만료 · " + ", ".join(PackedStringArray(ended)), 22,
				OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	return y


static func _build_allocation(sheet: HubSheet, state: Dictionary, w: float, y: float) -> float:
	var body: Control = sheet.body
	y = _section(body, "흑자 배분", w, y)
	var delegated: bool = StaffSystem.is_delegated(state, "finance")
	var intro: String = "흑자의 %d%%는 잔고에 남고, 나머지를 세 곳에 나눕니다. 효과는 다음 한 주." % \
			ConstTable.int_of("FINANCE_RESERVE_PCT")
	_lbl(body, intro, 22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
	y += 36.0
	if delegated:
		_lbl(body, "%s 담당 — 자동 균등 배분 (무난하지만 최적은 아닙니다)" % \
				StaffSystem.owner_name(state, "finance"),
				22, OutgameTheme.ACCENT_TEXT, Vector2(0, y), Vector2(w, 30))
		y += 38.0

	var shares: Dictionary = FinanceSystem.allocation_shares(state)
	var hints: Dictionary = {
		"training": "다음 주 훈련 EXP 최대 +%d%% (주 %s 지출에서 최대)" % [
				ConstTable.int_of("FINANCE_TRAINING_MAX_PCT"),
				FinanceSystem.fmt(ConstTable.int_of("FINANCE_TRAINING_FULL_SPEND"))],
		"facility": "업그레이드 자금으로 모읍니다 · 적자 때 비상금" \
				if FinanceSystem.facility_level(state) < FinanceSystem.max_level() \
				else "최고 레벨 — 적자 때 비상금으로만 쓰입니다",
		"welfare": "다음 주 사건 확률 최대 −%d%% (주 %s 지출에서 최대)" % [
				ConstTable.int_of("FINANCE_WELFARE_MAX_PCT"),
				FinanceSystem.fmt(ConstTable.int_of("FINANCE_WELFARE_FULL_SPEND"))],
	}
	var btn_w: float = 84.0
	var btn_h: float = 64.0
	var label_w: float = 150.0
	var pct_w: float = 90.0
	for axis in FinanceSystem.AXES:
		var pct: int = int(shares[axis])
		_lbl(body, String(FinanceSystem.AXIS_LABELS[axis]), 28, OutgameTheme.TEXT,
				Vector2(0, y + 10), Vector2(label_w, 44))
		var bar_x: float = label_w
		var bar_w: float = w - label_w - pct_w - (0.0 if delegated else (btn_w * 2.0 + 24.0))
		if not delegated:
			bar_x = label_w + btn_w + 12.0
			var minus := _step_button(body, "−", Vector2(label_w, y), Vector2(btn_w, btn_h))
			minus.pressed.connect(_on_step.bind(sheet, state, String(axis), -1))
			var plus := _step_button(body, "+", Vector2(bar_x + bar_w + 12.0, y), Vector2(btn_w, btn_h))
			plus.pressed.connect(_on_step.bind(sheet, state, String(axis), 1))
		var track := ColorRect.new()
		track.color = OutgameTheme.SURFACE_SUNK
		track.position = Vector2(bar_x, y + 22)
		track.size = Vector2(bar_w, 20)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(track)
		var fill := ColorRect.new()
		fill.color = AXIS_COLORS[axis]
		fill.position = track.position
		fill.size = Vector2(bar_w * float(pct) / 100.0, 20)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(fill)
		_lbl(body, "%d%%" % pct, 28, OutgameTheme.TEXT, Vector2(w - pct_w, y + 10),
				Vector2(pct_w, 44), HORIZONTAL_ALIGNMENT_RIGHT)
		y += btn_h + 4.0
		_lbl(body, String(hints[axis]), 20, OutgameTheme.TEXT_SUB, Vector2(label_w, y),
				Vector2(w - label_w, 26))
		y += 38.0

	var eff: Dictionary = FinanceSystem.effects(state)
	_lbl(body, "이번 주 적용 중: 훈련 EXP +%.1f%% · 사건 확률 −%.1f%%" % [
			float(eff["training_pct"]), float(eff["welfare_pct"])],
			22, OutgameTheme.ACCENT_TEXT, Vector2(0, y), Vector2(w, 30))
	return y + 36.0


static func _build_facility(sheet: HubSheet, state: Dictionary, w: float, y: float,
		upgrade_armed: bool) -> float:
	var body: Control = sheet.body
	var lvl: int = FinanceSystem.facility_level(state)
	var top: int = FinanceSystem.max_level()
	y = _section(body, "시설  Lv %d / %d" % [lvl, top], w, y)
	_lbl(body, "지금  " + _facility_effects(FinanceSystem.facility_row(lvl)), 22, OutgameTheme.TEXT,
			Vector2(0, y), Vector2(w, 30))
	y += 36.0
	if lvl < top:
		_lbl(body, "다음  " + _facility_effects(FinanceSystem.facility_row(lvl + 1)), 22,
				OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		y += 36.0
		var cost: int = FinanceSystem.upgrade_cost(state)
		_lbl(body, "비용 %s — 시설 적립금 먼저, 모자라면 잔고 (가용 %s)" % [
				FinanceSystem.fmt(cost), FinanceSystem.fmt(FinanceSystem.upgrade_funds(state))],
				22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		y += 40.0
	var why: String = FinanceSystem.upgrade_block_reason(state)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	if why == "":
		btn.text = ("한 번 더 눌러 확정 (−%s)" % FinanceSystem.fmt(FinanceSystem.upgrade_cost(state))) \
				if upgrade_armed else "시설 업그레이드 → Lv %d" % (lvl + 1)
		if upgrade_armed:
			OutgameTheme.style_dark_button(btn, 30)
		else:
			OutgameTheme.style_primary_button(btn, 30)
		btn.pressed.connect(_on_upgrade.bind(sheet, state, upgrade_armed))
	else:
		btn.text = "최고 레벨입니다" if lvl >= top else "자금 부족 — %s 필요" % \
				FinanceSystem.fmt(FinanceSystem.upgrade_cost(state))
		btn.disabled = true
		OutgameTheme.style_ghost_button(btn, 28)
	btn.position = Vector2(0, y)
	btn.size = Vector2(w, 96)
	body.add_child(btn)
	return y + 96.0


# 특별 지출 — running specials, then every row with its two-step buy button
# (disabled with the reason from `FinanceSystem.special_block_reason`).
static func _build_specials(sheet: HubSheet, state: Dictionary, w: float, y: float,
		armed: String) -> float:
	var body: Control = sheet.body
	y = _section(body, "특별 지출", w, y)
	_lbl(body, "잔고에서 바로 냅니다 · 효과는 정해진 주 수 동안 (동시 %d건까지)" % \
			maxi(1, ConstTable.int_of("FSPEC_MAX_ACTIVE")),
			22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
	y += 38.0
	var running: Array = FinanceSystem.active_specials(state)
	for raw in running:
		var e: Dictionary = raw
		_lbl(body, "진행 중 · %s — %s · %d주 남음" % [String(e.get("name", "")),
				FinanceSystem.special_effect_text(e), int(e.get("weeks_left", 0))],
				22, OutgameTheme.POSITIVE, Vector2(0, y), Vector2(w, 30))
		y += 34.0
	if not running.is_empty():
		y += 8.0
	var btn_w: float = 300.0
	var text_w: float = w - btn_w - 16.0
	for raw2 in FinanceSystem.special_rows():
		var row: Dictionary = raw2
		var sid: String = String(row["id"])
		var cost: int = int(row["cost"])
		var why: String = FinanceSystem.special_block_reason(state, sid)
		var name_col: Color = OutgameTheme.TEXT if why == "" else OutgameTheme.TEXT_SUB
		_lbl(body, String(row["name"]), 28, name_col, Vector2(0, y), Vector2(text_w, 38))
		_lbl(body, "%s · %d주" % [FinanceSystem.special_effect_text(row), int(row["weeks"])],
				22, OutgameTheme.ACCENT_TEXT if why == "" else OutgameTheme.TEXT_FAINT,
				Vector2(0, y + 40), Vector2(text_w, 30))
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		var price: String = "무료" if cost <= 0 else "−" + FinanceSystem.fmt(cost)
		if why == "":
			if armed == sid:
				btn.text = "한 번 더 눌러 확정"
				OutgameTheme.style_dark_button(btn, 24)
			else:
				btn.text = "%s  %s" % ["계약" if cost <= 0 else "구매", price]
				OutgameTheme.style_primary_button(btn, 26)
			btn.pressed.connect(_on_special.bind(sheet, state, sid, armed == sid))
		else:
			btn.text = why
			btn.disabled = true
			OutgameTheme.style_ghost_button(btn, 20)
		btn.position = Vector2(w - btn_w, y)
		btn.size = Vector2(btn_w, 72)
		body.add_child(btn)
		var desc := _lbl(body, String(row["desc"]), 20, OutgameTheme.TEXT_SUB,
				Vector2(0, y + 76), Vector2(w, 28))
		desc.clip_text = true
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		y += 116.0
	return y


static func _build_history(body: Control, state: Dictionary, w: float, y: float) -> float:
	y = _section(body, "최근 기록", w, y)
	var hist: Array = FinanceSystem.history(state)
	if hist.is_empty():
		_lbl(body, "기록 없음", 22, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 30))
		return y + 36.0
	var shown: int = 0
	for i in range(hist.size() - 1, -1, -1):
		if shown >= RECENT_ROWS:
			break
		var e: Dictionary = hist[i]
		var net: int = int(e.get("net", 0))
		_lbl(body, "%d주차" % int(e.get("week_no", 0)), 24, OutgameTheme.TEXT_SUB,
				Vector2(0, y), Vector2(w * 0.25, 34))
		_lbl(body, FinanceSystem.fmt_signed(net), 24, _signed_color(net),
				Vector2(w * 0.25, y), Vector2(w * 0.25, 34), HORIZONTAL_ALIGNMENT_RIGHT)
		_lbl(body, "잔고 %s" % FinanceSystem.fmt(int(e.get("balance", 0))), 24, OutgameTheme.TEXT,
				Vector2(w * 0.5, y), Vector2(w * 0.32, 34), HORIZONTAL_ALIGNMENT_RIGHT)
		if _hard_cut(e):
			_lbl(body, "삭감", 22, OutgameTheme.NEGATIVE, Vector2(w * 0.84, y),
					Vector2(w * 0.16, 34), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 38.0
		shown += 1
	return y


# ── Handlers ─────────────────────────────────────────────────────────────────
static func _on_step(sheet: HubSheet, state: Dictionary, axis: String, dir: int) -> void:
	if FinanceSystem.nudge_allocation(state, axis, dir):
		_render(sheet, state, false)


static func _on_upgrade(sheet: HubSheet, state: Dictionary, armed: bool) -> void:
	if not armed:
		_render(sheet, state, true)
		return
	# A refusal needs no message — the re-render shows the button's reason.
	FinanceSystem.upgrade_facility(state)
	_render(sheet, state, false)


static func _on_special(sheet: HubSheet, state: Dictionary, special_id: String, armed: bool) -> void:
	if not armed:
		_render(sheet, state, false, special_id)
		return
	# Same as the upgrade: a refusal shows up as the re-rendered button's reason.
	FinanceSystem.buy_special(state, special_id)
	_render(sheet, state, false)


# ── Helpers ──────────────────────────────────────────────────────────────────
# A week whose cuts go beyond "no allocation this week" — fund raid,
# downgrade, or training penalty.
static func _hard_cut(entry: Dictionary) -> bool:
	return (entry.get("cuts", []) as Array).size() > 1 or int(entry.get("unpaid", 0)) > 0


## "스폰서 수입 (시설 ×1.10 · 보정 ×1.05)" — the facility percent of that week plus every
## other sponsor multiplier (`FinanceSystem.income_mult`: traits, finance stat, specials).
## The ledger entry's own `income_mult` wins when it records one; else the current value.
static func _sponsor_label(last: Dictionary, state: Dictionary) -> String:
	var txt: String = "스폰서 수입 (시설 ×%.2f" % (float(last.get("income_pct", 100)) / 100.0)
	var m: float = float(last.get("income_mult", FinanceSystem.income_mult(state)))
	if absf(m - 1.0) >= 0.005:
		txt += " · 보정 ×%.2f" % m
	return txt + ")"


## "시설 유지비 (보정 ×0.90)" — `FinanceSystem.upkeep_mult` when it moves the upkeep.
static func _upkeep_label(last: Dictionary, state: Dictionary) -> String:
	var m: float = float(last.get("upkeep_mult", FinanceSystem.upkeep_mult(state)))
	if absf(m - 1.0) >= 0.005:
		return "시설 유지비 (보정 ×%.2f)" % m
	return "시설 유지비"


static func _facility_effects(row: Dictionary) -> String:
	return "훈련 ×%.2f · 숙련도 ×%.2f · 사건 ×%.2f · 수입 ×%.2f · 유지비 %s" % [
			float(row.get("train_exp_pct", 100)) / 100.0, float(row.get("mastery_pct", 100)) / 100.0,
			float(row.get("incident_pct", 100)) / 100.0, float(row.get("income_pct", 100)) / 100.0,
			FinanceSystem.fmt(int(row.get("upkeep", 0)))]


static func _section(body: Control, title: String, w: float, y: float) -> float:
	_lbl(body, title, 30, OutgameTheme.TEXT, Vector2(0, y), Vector2(w, 40))
	OutgameTheme.add_divider(body, Vector2(0, y + 46), w)
	return y + 58.0


static func _amount_row(body: Control, label_text: String, amount: int, w: float, y: float) -> float:
	_lbl(body, label_text, 24, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w * 0.7, ROW_H))
	_lbl(body, FinanceSystem.fmt_signed(amount), 26, OutgameTheme.TEXT,
			Vector2(w * 0.5, y), Vector2(w * 0.5, ROW_H), HORIZONTAL_ALIGNMENT_RIGHT)
	return y + ROW_H


static func _signed_color(n: int) -> Color:
	if n > 0:
		return OutgameTheme.POSITIVE
	if n < 0:
		return OutgameTheme.NEGATIVE
	return OutgameTheme.NEUTRAL


static func _step_button(body: Control, text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_ghost_button(b, 34)
	b.position = pos
	b.size = sz
	body.add_child(b)
	return b


static func _lbl(parent: Control, text: String, font_size: int, color: Color, pos: Vector2,
		sz: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = UiHelpers.mk_label(parent, text, font_size, color, pos, sz, align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
