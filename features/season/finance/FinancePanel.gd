class_name FinancePanel
extends VBoxContainer

# Hub manage card 「재무」 + its `HubSheet` detail (contract: plan §11.2).
# `HubView`'s manage row draws `hub_summary`, a press calls `open(host)`.
#
# **The sheet body's layout lives in `UI_View_FinancePanel.tscn`** (+ item scenes
# `FinanceAmountRow` · `FinanceAllocRow` · `FinanceSpecialRow` · `FinanceHistoryRow`).
# `open` puts one instance into the sheet's `body`; this script only fills `%` nodes,
# shows / hides the optional lines, instances the list rows and wires the buttons. What
# stays in code is data colour: balance / net signs, axis fill colours, affordable or not.
# The sheet's scroll height follows this node's height (`resized`).
#
# Every change made inside the sheet (allocation step, facility upgrade, special buy)
# refills the same instance in place (`_fill`) — the sheet itself stays open, so the
# hub's `closed → refresh` hook (wired by `HubView`) still fires once at the end. Rows
# are reused, never freed while their button is emitting. Every tap target lives inside
# the sheet's `DragScroll` body, so they are plain `Button`s (taps survive; a vertical
# drag scrolls) — no `HSlider`, whose drag the scroll would swallow. Allocation is a
# −/+ stepper per axis instead.
#
# 특별 지출 (§14 T6): one row per `finance_specials.csv` entry with a two-step buy
# button (like the facility upgrade). Only one row can be armed at a time —
# `_special_armed` is that row's id.

const SCENE_PATH: String = "res://features/season/finance/UI_View_FinancePanel.tscn"
const ALLOC_ROW_SCENE: PackedScene = preload("res://features/season/finance/UI_Comp_FinanceAllocRow.tscn")
const SPECIAL_ROW_SCENE: PackedScene = preload("res://features/season/finance/UI_Comp_FinanceSpecialRow.tscn")
const HISTORY_ROW_SCENE: PackedScene = preload("res://features/season/finance/UI_Comp_FinanceHistoryRow.tscn")

const AXIS_COLORS: Dictionary = {
	"training": OutgameTheme.ACCENT,
	"facility": OutgameTheme.LINK,
	"welfare": OutgameTheme.POSITIVE,
}
const RECENT_ROWS: int = 6

var _sheet: HubSheet = null
var _state: Dictionary = {}
var _upgrade_armed: bool = false
var _special_armed: String = ""


## Card summary — `{title, value, sub, owner, alert}`.
static func hub_summary(state: Dictionary) -> Dictionary:
	var f: Dictionary = state.get("finance", {})
	if f.is_empty():
		return {"title": Loc.t(L.FINANCE_HUB_TITLE), "value": "—", "sub": "", "owner": "", "alert": false}
	var last: Dictionary = FinanceSystem.last_week(state)
	var sub: String = Loc.t(L.FINANCE_HUB_BEFORE_FIRST)
	if not last.is_empty():
		var net_s: String = FinanceSystem.fmt_signed(int(last.get("net", 0)))
		sub = Loc.t(L.FINANCE_HUB_LAST_WEEK_CUT if _hard_cut(last) else L.FINANCE_HUB_LAST_WEEK, {"net": net_s})
	return {
		"title": Loc.t(L.FINANCE_HUB_TITLE_LEVEL, {"level": FinanceSystem.facility_level(state)}),
		"value": FinanceSystem.fmt(FinanceSystem.balance(state)),
		"sub": sub,
		"owner": StaffSystem.owner_name(state, "finance"),
		"alert": FinanceSystem.is_low_balance(state) or FinanceSystem.penalty_weeks(state) > 0
				or (not last.is_empty() and _hard_cut(last)),
	}


## Instantiates the scene. `FinancePanel.new()` is an empty box — don't use it.
static func create() -> FinancePanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as FinancePanel


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, Loc.t(L.FINANCE_SHEET_TITLE))
	var gm: Node = host.get_node_or_null("/root/GameManager")
	var panel := create()
	sheet.body.add_child(panel)
	panel._bind(sheet, gm.season_state if gm != null else {})


func _ready() -> void:
	_clear(%Axes)
	_clear(%Specials)
	_clear(%History)
	(%Upgrade as Button).pressed.connect(_on_upgrade)
	(%UpgradeConfirm as Button).pressed.connect(_on_upgrade)
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


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill() -> void:
	var has_run: bool = not (_state.get("finance", {}) as Dictionary).is_empty()
	%Empty.visible = not has_run
	%Main.visible = has_run
	if not has_run:
		return
	_fill_header()
	_fill_last_week()
	_fill_allocation()
	_fill_facility()
	_fill_specials()
	_fill_history()


func _fill_header() -> void:
	var state: Dictionary = _state
	%Balance.text = FinanceSystem.fmt(FinanceSystem.balance(state))
	(%Balance as Label).add_theme_color_override("font_color",
			OutgameTheme.NEGATIVE if FinanceSystem.is_low_balance(state) else OutgameTheme.TEXT)
	%Fund.text = FinanceSystem.fmt(FinanceSystem.facility_fund(state))
	%OwnerLine.text = Loc.t(L.FINANCE_PANEL_OWNER_MANAGER)
	if StaffSystem.is_delegated(state, "finance"):
		%OwnerLine.text = Loc.t(L.FINANCE_PANEL_OWNER_STAFF, {"name": StaffSystem.owner_name(state, "finance")})
	var proj: Dictionary = FinanceSystem.projection(state)
	%Projection.text = Loc.t(L.FINANCE_PANEL_PROJECTION, {
			"net": FinanceSystem.fmt_signed(int(proj["net"])), "income": FinanceSystem.fmt(int(proj["income"])),
			"expense": FinanceSystem.fmt(int(proj["expense"]))})
	%LowBalance.visible = FinanceSystem.is_low_balance(state)
	%LowBalance.text = Loc.t(L.FINANCE_PANEL_LOW_BALANCE,
			{"amount": FinanceSystem.fmt(FinanceSystem.weekly_fixed_cost(state))})
	var pw: int = FinanceSystem.penalty_weeks(state)
	%Penalty.visible = pw > 0
	%Penalty.text = Loc.t(L.FINANCE_PANEL_PENALTY,
			{"weeks": pw, "pct": ConstTable.int_of("FINANCE_UNPAID_TRAIN_PENALTY_PCT")})


func _fill_last_week() -> void:
	var state: Dictionary = _state
	var last: Dictionary = FinanceSystem.last_week(state)
	%LastWeekEmpty.visible = last.is_empty()
	%LastWeek.visible = not last.is_empty()
	if last.is_empty():
		return
	_amount_row(%FinanceAmountRow_Sponsor, _sponsor_label(last, state), int(last.get("sponsor", 0)))
	_amount_row(%FinanceAmountRow_Bonus, Loc.t(L.FINANCE_PANEL_BONUS,
			{"win": int(last.get("wins", 0)), "loss": int(last.get("losses", 0))}), int(last.get("bonus", 0)))
	_amount_row(%FinanceAmountRow_Salaries, Loc.t(L.FINANCE_PANEL_SALARIES), -int(last.get("salaries", 0)))
	_amount_row(%FinanceAmountRow_Upkeep, _upkeep_label(last, state), -int(last.get("upkeep", 0)))
	var net: int = int(last.get("net", 0))
	%Net.text = FinanceSystem.fmt_signed(net)
	(%Net as Label).add_theme_color_override("font_color", _signed_color(net))
	%AllocLine.visible = net >= 0
	var a: Dictionary = last.get("alloc", {})
	%AllocLine.text = Loc.t(L.FINANCE_PANEL_ALLOC_LINE, {
			"reserve": FinanceSystem.fmt(int(last.get("reserve", 0))),
			"training": FinanceSystem.fmt(int(a.get("training", 0))),
			"facility": FinanceSystem.fmt(int(a.get("facility", 0))),
			"welfare": FinanceSystem.fmt(int(a.get("welfare", 0)))})
	var cuts: Array = []
	for cut in (last.get("cuts", []) as Array):
		cuts.append(Loc.t(L.FINANCE_PANEL_CUT_LINE, {"cut": FinanceSystem.cut_text(cut)}))
	_fill_lines(%Cuts, cuts)
	var sep: String = Loc.t(L.UI_LIST_SEPARATOR)
	var spend: int = int(last.get("special_spend", 0))
	%SpecialSpend.visible = spend > 0
	%SpecialSpend.text = Loc.t(L.FINANCE_PANEL_SPECIAL_SPEND, {"amount": FinanceSystem.fmt(spend),
			"names": sep.join(FinanceSystem.special_names(last.get("special_buys", [])))})
	var ended: Array = last.get("specials_expired", [])
	%SpecialsExpired.visible = not ended.is_empty()
	%SpecialsExpired.text = Loc.t(L.FINANCE_PANEL_SPECIALS_EXPIRED,
			{"names": sep.join(FinanceSystem.special_names(ended))})


func _fill_allocation() -> void:
	var state: Dictionary = _state
	var delegated: bool = StaffSystem.is_delegated(state, "finance")
	%AllocIntro.text = Loc.t(L.FINANCE_PANEL_ALLOC_INTRO, {"pct": ConstTable.int_of("FINANCE_RESERVE_PCT")})
	%AllocDelegated.visible = delegated
	%AllocDelegated.text = Loc.t(L.FINANCE_PANEL_ALLOC_DELEGATED,
			{"name": StaffSystem.owner_name(state, "finance")})

	var shares: Dictionary = FinanceSystem.allocation_shares(state)
	var hints: Dictionary = {
		"training": Loc.t(L.FINANCE_PANEL_HINT_TRAINING, {
				"pct": ConstTable.int_of("FINANCE_TRAINING_MAX_PCT"),
				"amount": FinanceSystem.fmt(ConstTable.int_of("FINANCE_TRAINING_FULL_SPEND"))}),
		"facility": Loc.t(L.FINANCE_PANEL_HINT_FACILITY) \
				if not FinanceSystem.all_facilities_max(state) \
				else Loc.t(L.FINANCE_PANEL_HINT_FACILITY_MAX),
		"welfare": Loc.t(L.FINANCE_PANEL_HINT_WELFARE, {
				"pct": ConstTable.int_of("FINANCE_WELFARE_MAX_PCT"),
				"amount": FinanceSystem.fmt(ConstTable.int_of("FINANCE_WELFARE_FULL_SPEND"))}),
	}
	var rows: Array = _ensure_rows(%Axes, ALLOC_ROW_SCENE, FinanceSystem.AXES.size(), _wire_alloc_row)
	for i in rows.size():
		var row: Control = rows[i]
		var axis: String = String(FinanceSystem.AXES[i])
		row.set_meta(&"axis", axis)
		var pct: int = int(shares[axis])
		row.get_node("%Axis").text = FinanceSystem.axis_label(axis)
		row.get_node("%Pct").text = "%d%%" % pct
		row.get_node("%Hint").text = String(hints[axis])
		for n in ["%Minus", "%GapL", "%GapR", "%Plus"]:
			(row.get_node(n) as Control).visible = not delegated
		_set_fill(row.get_node("%Fill"), float(pct) / 100.0, AXIS_COLORS[axis])

	var eff: Dictionary = FinanceSystem.effects(state)
	%Effects.text = Loc.t(L.FINANCE_PANEL_EFFECTS, {"training": "%.1f" % float(eff["training_pct"]),
			"welfare": "%.1f" % float(eff["welfare_pct"])})


func _wire_alloc_row(row: Control) -> void:
	(row.get_node("%Minus") as Button).pressed.connect(_on_step.bind(row, -1))
	(row.get_node("%Plus") as Button).pressed.connect(_on_step.bind(row, 1))


func _fill_facility() -> void:
	var state: Dictionary = _state
	var lvl: int = FinanceSystem.facility_level(state)
	var top: int = FinanceSystem.max_level()
	%FacilityTitle.text = Loc.t(L.FINANCE_PANEL_FACILITY_TITLE, {"level": lvl, "max": top})
	%FacNow.text = Loc.t(L.FINANCE_PANEL_FAC_NOW, {"effects": _facility_effects(FinanceSystem.facility_row(lvl))})
	%FacNext.visible = lvl < top
	%FacCost.visible = lvl < top
	if lvl < top:
		%FacNext.text = Loc.t(L.FINANCE_PANEL_FAC_NEXT,
				{"effects": _facility_effects(FinanceSystem.facility_row(lvl + 1))})
		%FacCost.text = Loc.t(L.FINANCE_PANEL_FAC_COST, {
				"cost": FinanceSystem.fmt(FinanceSystem.upgrade_cost(state)),
				"available": FinanceSystem.fmt(FinanceSystem.upgrade_funds(state))})
	var why: String = FinanceSystem.upgrade_block_reason(state)
	var cost: String = FinanceSystem.fmt(FinanceSystem.upgrade_cost(state))
	%Upgrade.visible = why == "" and not _upgrade_armed
	%Upgrade.text = Loc.t(L.FINANCE_PANEL_UPGRADE, {"level": lvl + 1})
	%UpgradeConfirm.visible = why == "" and _upgrade_armed
	%UpgradeConfirm.text = Loc.t(L.FINANCE_PANEL_UPGRADE_CONFIRM, {"cost": cost})
	%UpgradeBlocked.visible = why != ""
	var short: bool = FinanceSystem.upgrade_funds(state) < FinanceSystem.upgrade_cost(state)
	if lvl >= top:
		%UpgradeBlocked.text = Loc.t(L.UI_MESSAGE_MAX_LEVEL)
	elif short:
		%UpgradeBlocked.text = Loc.t(L.FINANCE_PANEL_UPGRADE_SHORT, {"amount": cost})
	else:
		%UpgradeBlocked.text = why
	var lines: Array = []
	for raw in FinanceSystem.upkeep_breakdown(state):
		var e: Dictionary = raw
		lines.append(Loc.t(L.FINANCE_PANEL_UPKEEP_LINE, {"name": FacilitySystem.facility_name(String(e["fid"])),
				"level": int(e["level"]), "amount": FinanceSystem.fmt(int(e["upkeep"]))}))
	_fill_lines(%Upkeeps, lines)


# 특별 지출 — running specials, then every row with its two-step buy button
# (disabled with the reason from `FinanceSystem.special_block_reason`).
func _fill_specials() -> void:
	var state: Dictionary = _state
	%SpecIntro.text = Loc.t(L.FINANCE_PANEL_SPEC_INTRO, {"n": maxi(1, ConstTable.int_of("FSPEC_MAX_ACTIVE"))})
	var running: Array = []
	for raw in FinanceSystem.active_specials(state):
		var e: Dictionary = raw
		running.append(Loc.t(L.FINANCE_PANEL_RUNNING, {"name": FinanceSystem.special_name(String(e.get("id", ""))),
				"effect": FinanceSystem.special_effect_text(e), "weeks": int(e.get("weeks_left", 0))}))
	_fill_lines(%Running, running)
	%RunningGap.visible = not running.is_empty()

	var specs: Array = FinanceSystem.special_rows()
	var rows: Array = _ensure_rows(%Specials, SPECIAL_ROW_SCENE, specs.size(), _wire_special_row)
	for i in rows.size():
		var row: Control = rows[i]
		var spec: Dictionary = specs[i]
		var sid: String = String(spec["id"])
		row.set_meta(&"special_id", sid)
		var cost: int = int(spec["cost"])
		var why: String = FinanceSystem.special_block_reason(state, sid)
		var name_l: Label = row.get_node("%Name")
		name_l.text = FinanceSystem.special_name(sid)
		name_l.add_theme_color_override("font_color", OutgameTheme.TEXT if why == "" else OutgameTheme.TEXT_SUB)
		var eff_l: Label = row.get_node("%Effect")
		eff_l.text = Loc.t(L.FINANCE_PANEL_SPEC_EFFECT,
				{"effect": FinanceSystem.special_effect_text(spec), "weeks": int(spec["weeks"])})
		eff_l.add_theme_color_override("font_color",
				OutgameTheme.ACCENT_TEXT if why == "" else OutgameTheme.TEXT_FAINT)
		var buy: Button = row.get_node("%Buy")
		buy.visible = why == "" and _special_armed != sid
		buy.text = Loc.t(L.FINANCE_PANEL_CONTRACT_FREE) if cost <= 0 \
				else Loc.t(L.FINANCE_PANEL_BUY, {"price": "−" + FinanceSystem.fmt(cost)})
		(row.get_node("%Confirm") as Button).visible = why == "" and _special_armed == sid
		var blocked: Button = row.get_node("%Blocked")
		blocked.visible = why != ""
		blocked.text = why
		row.get_node("%Desc").text = FinanceSystem.special_desc(sid)


func _wire_special_row(row: Control) -> void:
	(row.get_node("%Buy") as Button).pressed.connect(_on_special.bind(row, false))
	(row.get_node("%Confirm") as Button).pressed.connect(_on_special.bind(row, true))


func _fill_history() -> void:
	var hist: Array = FinanceSystem.history(_state)
	%HistEmpty.visible = hist.is_empty()
	var shown: Array = []
	for i in range(hist.size() - 1, -1, -1):
		if shown.size() >= RECENT_ROWS:
			break
		shown.append(hist[i])
	var rows: Array = _ensure_rows(%History, HISTORY_ROW_SCENE, shown.size(), Callable())
	for i in rows.size():
		var row: Control = rows[i]
		var e: Dictionary = shown[i]
		var net: int = int(e.get("net", 0))
		row.get_node("%Week").text = Loc.t(L.TERM_WEEK_NTH, {"n": int(e.get("week_no", 0))})
		var net_l: Label = row.get_node("%Net")
		net_l.text = FinanceSystem.fmt_signed(net)
		net_l.add_theme_color_override("font_color", _signed_color(net))
		row.get_node("%Balance").text = Loc.t(L.FINANCE_PANEL_HIST_BALANCE,
				{"amount": FinanceSystem.fmt(int(e.get("balance", 0)))})
		var cut: Label = row.get_node("%Cut")
		cut.visible = _hard_cut(e)


# ── Handlers ─────────────────────────────────────────────────────────────────
func _on_step(row: Control, dir: int) -> void:
	if FinanceSystem.nudge_allocation(_state, String(row.get_meta(&"axis", "")), dir):
		_rearm(false, "")


func _on_upgrade() -> void:
	if not _upgrade_armed:
		_rearm(true, "")
		return
	# A refusal needs no message — the refill shows the button's reason.
	FinanceSystem.upgrade_facility(_state)
	_rearm(false, "")


func _on_special(row: Control, armed: bool) -> void:
	var sid: String = String(row.get_meta(&"special_id", ""))
	if not armed:
		_rearm(false, sid)
		return
	# Same as the upgrade: a refusal shows up as the refilled button's reason.
	FinanceSystem.buy_special(_state, sid)
	_rearm(false, "")


func _rearm(upgrade_armed: bool, special_armed: String) -> void:
	_upgrade_armed = upgrade_armed
	_special_armed = special_armed
	_fill()


# ── Helpers ──────────────────────────────────────────────────────────────────
# A week whose cuts go beyond "no allocation this week" — fund raid,
# downgrade, or training penalty.
static func _hard_cut(entry: Dictionary) -> bool:
	return (entry.get("cuts", []) as Array).size() > 1 or int(entry.get("unpaid", 0)) > 0


## "Sponsor income (facility ×1.10 · modifier ×1.05)" — the facility percent of that week plus
## every other sponsor multiplier (`FinanceSystem.income_mult`: traits, finance stat, specials).
## The ledger entry's own `income_mult` wins when it records one; else the current value.
static func _sponsor_label(last: Dictionary, state: Dictionary) -> String:
	var fac: String = "%.2f" % (float(last.get("income_pct", 100)) / 100.0)
	var m: float = float(last.get("income_mult", FinanceSystem.income_mult(state)))
	if absf(m - 1.0) >= 0.005:
		return Loc.t(L.FINANCE_PANEL_SPONSOR_MULT, {"facility": fac, "mult": "%.2f" % m})
	return Loc.t(L.FINANCE_PANEL_SPONSOR, {"facility": fac})


## "Facility upkeep (modifier ×0.90)" — `FinanceSystem.upkeep_mult` when it moves the upkeep.
static func _upkeep_label(last: Dictionary, state: Dictionary) -> String:
	var m: float = float(last.get("upkeep_mult", FinanceSystem.upkeep_mult(state)))
	if absf(m - 1.0) >= 0.005:
		return Loc.t(L.FINANCE_PANEL_UPKEEP_MULT, {"mult": "%.2f" % m})
	return Loc.t(L.FINANCE_PANEL_UPKEEP)


static func _facility_effects(row: Dictionary) -> String:
	return Loc.t(L.FINANCE_PANEL_FAC_EFFECTS, {
			"train": "%.2f" % (float(row.get("train_exp_pct", 100)) / 100.0),
			"mastery": "%.2f" % (float(row.get("mastery_pct", 100)) / 100.0),
			"incident": "%.2f" % (float(row.get("incident_pct", 100)) / 100.0),
			"income": "%.2f" % (float(row.get("income_pct", 100)) / 100.0)})


static func _amount_row(row: Node, label_text: String, amount: int) -> void:
	if row == null:
		return
	row.get_node("%Label").text = label_text
	row.get_node("%Amount").text = FinanceSystem.fmt_signed(amount)


static func _signed_color(n: int) -> Color:
	if n > 0:
		return OutgameTheme.POSITIVE
	if n < 0:
		return OutgameTheme.NEGATIVE
	return OutgameTheme.NEUTRAL


## Share bar fill: width = ratio of the track (anchor), colour = data.
static func _set_fill(fill: Panel, ratio: float, col: Color) -> void:
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.visible = ratio > 0.0
	var sb := fill.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	sb.bg_color = col
	fill.add_theme_stylebox_override(&"panel", sb)


## The scene's sample rows are previews only — drop them before the first fill.
static func _clear(list: Node) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


## Keeps exactly `n` rows in `list` (instancing missing ones, wiring them once with `wire`)
## and returns them. Existing rows are reused, so a row whose button is emitting survives.
static func _ensure_rows(list: Node, scene: PackedScene, n: int, wire: Callable) -> Array:
	while list.get_child_count() > n:
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	while list.get_child_count() < n:
		var row: Node = scene.instantiate()
		list.add_child(row)
		if wire.is_valid():
			wire.call(row)
	return list.get_children()


## Template-line lists (`%Cuts`, `%Running`): the scene's first Label is the template,
## duplicated per text; the list hides when empty.
static func _fill_lines(list: Node, texts: Array) -> void:
	if list == null or list.get_child_count() == 0:
		return
	while list.get_child_count() > maxi(1, texts.size()):
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	var tpl: Label = list.get_child(0)
	while list.get_child_count() < texts.size():
		list.add_child(tpl.duplicate())
	for i in texts.size():
		(list.get_child(i) as Label).text = String(texts[i])
	(list as CanvasItem).visible = not texts.is_empty()


## F6 단독 실행 미리보기 — 메모리 런으로 두 주를 정산해 지난 주 · 최근 기록이 찬
## 시트 본문(`resources/UiPreview.gd`). 시트 없이 서므로 높이 맞추기는 건너뛴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	for _w in 2:
		FinanceSystem.settle_week(state)
	_bind(null, state)
