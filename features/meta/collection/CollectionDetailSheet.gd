class_name CollectionDetailSheet
extends CanvasLayer

# Pilot detail sheet of the lobby 컬렉션 tab (M10) — a full-screen modal (Pattern C,
# `docs/mobile_safe_area.md`): dim = whole viewport, sheet between `top_y()` and
# `bottom_y()`, the footer buttons end above the bottom gesture zone.
#
#   ┌ hero: bust · name · team · 등급 / 랭크 / 돌파 / Lv chips · EXP bar · salary ┐
#   │ 능력치 (current rank + level, delta vs the raw data)                       │  scrolls
#   │ 랭크 table (RunRules.rank_rows: reached / next / needs breakthrough)      │
#   │ 파일럿 카드 (after rank card swaps)                                        │
#   ├ status line (why an action is disabled / what just happened) ────────────┤
#   └ [닫기] [레벨업 · cost] [랭크업 · cost] ─────────────────────────────────────┘
#
# **The layout lives in `UI_View_CollectionDetailSheet.tscn`** (plus the item scenes
# `UI_Comp_CollectionStatChip.tscn` · `UI_Comp_CollectionRankRow.tscn`). This script makes no
# static nodes: it fills `%` nodes with text, shows / hides the optional blocks and
# wires signals. What stays in code is data: role / stars / reached tints, the chip
# pills (sized to their text), the EXP fill width, the bust art + role badge, the
# `CardDescBox` panels, and the safe-area offset of `%SafeArea`.
#
# Numbers come from a **copy** of the pool pilot (`fielded_copy`): `RunRules.apply_rank(rank)`
# then `RunRules.apply_level(level)` — the same calls run start makes, so what this sheet shows
# is what the pilot brings into a run today.
#
# 레벨업: `ProfileManager.level_up_pilot` → `save_profile()` → `leveled_up`.
# 랭크업: `ProfileManager.rank_up_pilot` (spends `rank_stone`, rank +1, level 0) →
# `save_profile()` → `ranked_up`. The tab refreshes the cell, summary, currency strip and
# toasts; the sheet refills in place.
#
# 쓰는 법:
#   var s := CollectionDetailSheet.create()
#   add_child(s)
#   s.leveled_up.connect(...)
#   s.ranked_up.connect(...)
#   s.open(pilot)

signal leveled_up(pilot_id: int, new_level: int)
signal ranked_up(pilot_id: int, new_rank: int)

const SCENE_PATH: String = "res://features/meta/collection/UI_View_CollectionDetailSheet.tscn"
const STAT_CHIP_SCENE: PackedScene = preload("res://features/meta/collection/UI_Comp_CollectionStatChip.tscn")
const RANK_ROW_SCENE: PackedScene = preload("res://features/meta/collection/UI_Comp_CollectionRankRow.tscn")

## Rank-row line templates by kind (`{n}` = row value). `card_swap` is built in `_row_desc`.
const ROW_DESC: Dictionary = {  # l10n-keys: breakthrough.kind.*
	"stat_flat": L.BREAKTHROUGH_KIND_STAT_FLAT, "salary_down": L.BREAKTHROUGH_KIND_SALARY_DOWN,
	"stat_growth": L.BREAKTHROUGH_KIND_STAT_GROWTH,
}
const ROW_KIND_LABELS: Dictionary = {  # l10n-keys: collection.bt_kind.*
	"stat_flat": L.COLLECTION_BT_KIND_STAT_FLAT, "salary_down": L.COLLECTION_BT_KIND_SALARY_DOWN,
	"stat_growth": L.COLLECTION_BT_KIND_STAT_GROWTH, "card_swap": L.COLLECTION_BT_KIND_CARD_SWAP,
}

var _pm: Node = null
var _gm: Node = null
var _base: PlayerData = null      # pool copy (never mutated)
var _fielded: PlayerData = null   # what the sheet shows (rank + level applied)
var _status_text: String = ""
var _status_ok: bool = false
var _art: TextureRect = null
var _badge: PositionBadge = null
var _stat_chips: Array = []
var _cards_w: float = -1.0        # width the `%Cards` panels were built for


## 씬을 인스턴스한다. `CollectionDetailSheet.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> CollectionDetailSheet:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as CollectionDetailSheet
	p.visible = false
	return p


func _ready() -> void:
	_pm = get_node("/root/ProfileManager")
	_gm = get_node("/root/GameManager")
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	%LevelUp.pressed.connect(_on_level_up_pressed)
	%RankUp.pressed.connect(_on_rank_up_pressed)
	# Sheet is STOP in the scene: taps on its empty parts must not reach the dim.
	var bust: Control = %Bust
	_art = PilotThumb.add_rounded_art(bust, Vector2.ZERO, bust.custom_minimum_size, 20)
	for i in PlayerData.STAT_KEYS.size() + 1:       # six stats + 종합
		var chip: Panel = STAT_CHIP_SCENE.instantiate()
		%StatGrid.add_child(chip)
		_stat_chips.append(chip)
	# CardDescBox measures its text at a fixed width — rebuild once the container knows it.
	(%Cards as Control).resized.connect(_on_cards_resized)
	if UiPreview.is_standalone(self):
		_fill_preview()


func open(p: PlayerData) -> void:
	_status_text = ""
	_base = p
	_fill()
	_fit_safe_area()
	(%Scroll as ScrollContainer).scroll_vertical = 0
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## The pilot as this profile fields it: rank rows 1..`rank` and Lv `level` applied — the same
## two calls run start makes (rank first, then level; both are delta-based).
static func fielded_copy(base: PlayerData, rank: int, level: int) -> PlayerData:
	var copy := base.duplicate() as PlayerData
	# Own array — `card_swap` writes into it, and the pool copy must stay untouched.
	copy.pilot_cards = base.pilot_cards.duplicate()
	if rank > 0:
		RunRules.apply_rank(copy, rank)
	RunRules.apply_level(copy, level)
	return copy


## The sheet sits between the safe lines; the scene's offsets on `Sheet` are the gaps.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill() -> void:
	if _base == null:
		return
	var pid: int = _base.id
	var rank: int = _pm.rank_of(pid)
	_fielded = fielded_copy(_base, rank, _pm.level_of(pid))
	_fill_hero(pid, rank)
	_fill_stats(rank)
	_fill_ranks(pid, rank)
	_fill_cards()
	_fill_footer(pid, rank)


func _fill_hero(pid: int, rank: int) -> void:
	var r: int = int(_base.role)
	var role_col: Color = OutgameTheme.ROLE_COLORS[r] if r >= 0 and r < 5 else OutgameTheme.NEUTRAL
	(%BustPlate as Panel).add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(role_col.lerp(OutgameTheme.SURFACE, 0.78), 20))
	var tex: Texture2D = PilotImages.bust_for(pid)
	_art.texture = tex if tex != null else PilotImages.face_for(pid)
	if _badge != null:
		_badge.free()
	_badge = PilotThumb.add_position_badge(%Bust, r, Vector2(10, 10))

	%Name.text = _base.name
	# The position is the badge on the bust (`PositionBadge`) — this line only names the home team.
	%RoleLine.text = Loc.t(L.RUN_SETUP_DRAFT_ORIGIN_TEAM, {"team": RunRules.team_short_name(_base.team_id)})

	# Chip row: 등급 stars · 랭크 n / max · 돌파 n / cap · Lv n / cap.
	var level: int = _pm.level_of(pid)
	var cap: int = _pm.level_cap_of(pid)
	var chips: Control = %Chips
	_clear(chips)
	var pill: Panel = CollectionCell.add_stars_pill(chips, _pm.stars_of(pid), Vector2.ZERO, 44.0, 24)
	var cx: float = pill.size.x + 10.0
	cx = _chip(chips, Loc.t(L.COLLECTION_DETAIL_CHIP_RANK, {"n": rank, "max": _pm.max_rank_of(pid)}),
			cx, OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT)
	cx = _chip(chips, Loc.t(L.COLLECTION_DETAIL_CHIP_BREAKTHROUGH,
			{"n": _pm.breakthrough_of(pid), "max": _pm.breakthrough_cap_of(pid)}), cx,
			OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)
	_chip(chips, "Lv %d / %d" % [level, cap], cx, OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)

	_fill_exp(pid, level)

	# Salary at the shown rank + level (rank `salary_down` rows included).
	%SalaryTitle.text = Loc.t(L.COLLECTION_DETAIL_SALARY_NOW, {"rank": rank, "level": level})
	%Salary.text = str(RunRules.salary_of(_fielded))
	%BonusRow.visible = _fielded.train_bonus_pct != 0
	%Bonus.text = "+%d%%" % _fielded.train_bonus_pct


## EXP toward the next level **within the current rank** (`ProfileManager.pilot_exp_progress`:
## EXP into the current level / EXP the next level needs, `need` 0 at the level cap = full bar).
func _fill_exp(pid: int, level: int) -> void:
	var fill: Panel = %ExpFill
	var prog: Dictionary = _pm.pilot_exp_progress(pid)
	var into: int = int(prog.get("into", 0))
	var need: int = int(prog.get("need", 0))
	if need <= 0:
		%ExpValue.text = Loc.t(L.COLLECTION_DETAIL_EXP_AT_CAP, {"cap": _pm.level_cap_of(pid)})
		fill.visible = true
		fill.anchor_right = 1.0
		return
	%ExpValue.text = "%d / %d  →  Lv %d" % [into, need, level + 1]
	var ratio: float = clampf(float(into) / float(need), 0.0, 1.0)
	# The fill is anchored to the track: its right anchor is the ratio (min width in the scene).
	fill.visible = ratio > 0.0
	fill.anchor_right = ratio


func _fill_stats(rank: int) -> void:
	%StatsTitle.text = Loc.t(L.COLLECTION_DETAIL_STATS_TITLE_RANK,
			{"rank": rank, "level": _fielded.level})
	for i in _stat_chips.size():
		var chip: Panel = _stat_chips[i]
		var key: String
		var val: int
		var delta: int
		var is_total: bool = i == PlayerData.STAT_KEYS.size()
		if is_total:
			key = Loc.t(L.RUN_SETUP_STAT_TOTAL)
			val = _fielded.stat_total()
			delta = val - _base.stat_total()
		else:
			var sk: String = String(PlayerData.STAT_KEYS[i])
			key = PlayerData.stat_label(i)
			val = int(_fielded.get(sk))
			delta = val - int(_base.get(sk))
		chip.add_theme_stylebox_override("panel", OutgameTheme.card_style(16,
				OutgameTheme.ACCENT_DIM if is_total else OutgameTheme.SURFACE_SUNK))
		chip.get_node("%Key").text = key
		var value: Label = chip.get_node("%Value")
		value.text = str(val)
		value.theme_type_variation = &"AccentLabel" if is_total else &"BodyLabel"
		var dl: Label = chip.get_node("%Delta")
		dl.visible = delta != 0
		dl.text = "%+d" % delta
		dl.add_theme_color_override("font_color",
				OutgameTheme.POSITIVE if delta > 0 else OutgameTheme.NEGATIVE)
	%StatNote.visible = _fielded.stat_total() != _base.stat_total()


## Rank table, one row per rank (`rank_rows` can hold several data rows per rank — one line
## each). Reached (rank ≤ current) = amber row + 달성; next (current + 1, unlocked) = 다음;
## above the max rank = dimmed + 돌파 필요.
func _fill_ranks(pid: int, rank: int) -> void:
	var rows_box: Control = %RankRows
	_clear(rows_box)
	var groups: Dictionary = {}       # int rank → Array[Dictionary] (data order)
	var order: Array = []
	for raw in RunRules.rank_rows(pid):
		var rr: int = int((raw as Dictionary)["rank"])
		if not groups.has(rr):
			groups[rr] = []
			order.append(rr)
		(groups[rr] as Array).append(raw)
	order.sort()
	var max_rank: int = _pm.max_rank_of(pid)
	%RankEmpty.visible = order.is_empty()
	%RankAfter.visible = not order.is_empty()
	%RankAfterLabel.text = Loc.t(L.COLLECTION_DETAIL_RANK_AFTER, {"cap": _pm.breakthrough_cap_of(pid)})
	for rr in order:
		var reached: bool = rr <= rank
		var locked: bool = rr > max_rank
		var is_next: bool = rr == rank + 1 and not locked
		var kinds: PackedStringArray = []
		var descs: PackedStringArray = []
		for raw in groups[rr]:
			var r: Dictionary = raw
			var kind: String = String(r["kind"])
			kinds.append(Loc.t(String(ROW_KIND_LABELS[kind])) if ROW_KIND_LABELS.has(kind) else kind)  # l10n-dynamic: collection.bt_kind.*
			descs.append(_row_desc(r))
		var row: Panel = RANK_ROW_SCENE.instantiate()
		row.custom_minimum_size.y = 44.0 + 32.0 * float(descs.size())
		rows_box.add_child(row)
		row.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if reached else (OutgameTheme.SURFACE_SUNK if locked else OutgameTheme.SURFACE),
				14, OutgameTheme.ACCENT if reached else OutgameTheme.BORDER, 2))
		(row.get_node("%Disc") as Panel).add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT if reached else (OutgameTheme.SURFACE if locked else OutgameTheme.SURFACE_SUNK), 24))
		var num: Label = row.get_node("%Num")
		num.text = str(rr)
		num.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL if reached
				else (OutgameTheme.TEXT_FAINT if locked else OutgameTheme.TEXT_SUB))
		var kind_lbl: Label = row.get_node("%Kind")
		kind_lbl.text = "\n".join(kinds)
		kind_lbl.theme_type_variation = &"AccentLabel" if reached \
				else (&"FaintLabel" if locked else &"CaptionLabel")
		var desc: Label = row.get_node("%Desc")
		desc.text = "\n".join(descs)
		desc.theme_type_variation = &"BodyLabel" if reached or is_next else &"SubLabel"
		var state: Label = row.get_node("%State")
		if reached:
			state.text = Loc.t(L.COLLECTION_DETAIL_BT_REACHED)
		elif is_next:
			state.text = Loc.t(L.COLLECTION_DETAIL_BT_NEXT)
		elif locked:
			state.text = Loc.t(L.COLLECTION_DETAIL_RANK_LOCKED)
		else:
			state.text = ""
		state.theme_type_variation = &"AccentLabel" if reached \
				else (&"FaintLabel" if locked else &"CaptionLabel")


## Rank-row line from the kind template + `value`; a `card_swap` row also names the new
## card ("… → 카드명"). Numbers come only from the data row, never from the text.
func _row_desc(r: Dictionary) -> String:
	var kind: String = String(r["kind"])
	var v: String = String(r["value"])
	if kind != "card_swap":
		return Loc.t(String(ROW_DESC[kind]), {"n": v}) if ROW_DESC.has(kind) else v  # l10n-dynamic: breakthrough.kind.*
	var parts: PackedStringArray = v.split(":")
	if parts.size() != 2:
		return v
	var d: String = Loc.t(L.BREAKTHROUGH_KIND_CARD_SWAP, {"slot": int(parts[0]) + 1})
	var def: Dictionary = _gm.card_def(int(parts[1]))
	if def.is_empty():
		return d
	return "%s → %s" % [d, Loc.t(String(def.get("name_key", "")))]  # l10n-dynamic: card.pilot.*.name


func _fill_cards() -> void:
	var swapped: bool = _fielded.pilot_cards != _base.pilot_cards
	%CardsTitle.text = Loc.t(L.COLLECTION_DETAIL_CARDS_TITLE_SWAPPED_RANK) if swapped \
			else Loc.t(L.TERM_CARD_PILOT_CARD)
	var box_parent: Control = %Cards
	_clear(box_parent)
	# Before the first layout pass the width is 0 — `_on_cards_resized` builds them then.
	_cards_w = box_parent.size.x
	if _cards_w <= 0.0:
		return
	for raw in _gm.pilot_card_ids_for(_fielded):
		var def: Dictionary = _gm.card_def(int(raw))
		if def.is_empty():
			continue
		var box := CardDescBox.build(CardData.from_def(def), _cards_w, true)
		box.custom_minimum_size = box.size
		box_parent.add_child(box)


## `%Cards` got a different width than the panels were measured for (first layout,
## rotation) — rebuild them at the real width.
func _on_cards_resized() -> void:
	if _fielded != null and not is_equal_approx((%Cards as Control).size.x, _cards_w):
		_fill_cards()


## Buttons + status line. Below the level cap only 레벨업 can be enabled, at the cap only
## 랭크업 (`rank_up_block_reason` = "" — rank < max rank and enough `rank_stone`). The status
## line shows the last action's result, else why the relevant action is blocked, else a hint.
func _fill_footer(pid: int, rank: int) -> void:
	var owned: bool = _pm.owns_pilot(pid)
	var level: int = _pm.level_of(pid)
	var cap: int = _pm.level_cap_of(pid)
	var at_cap: bool = owned and level >= cap
	var lv_cost: int = _pm.level_up_cost(pid) if owned else -1
	var lv_have: int = _pm.currency_of("levelup")
	var lv_reason: String = ""
	if not owned:
		lv_reason = Loc.t(L.COLLECTION_DETAIL_CANNOT_UNOWNED)
	elif at_cap or lv_cost < 0:
		lv_reason = Loc.t(L.COLLECTION_DETAIL_AT_LEVEL_CAP, {"cap": cap})
	elif lv_have < lv_cost:
		lv_reason = Loc.t(L.COLLECTION_DETAIL_NOT_ENOUGH, {"cost": lv_cost, "have": lv_have})
	var rk_cost: int = _pm.rank_up_cost(pid) if owned else -1
	var rk_reason: String = _pm.rank_up_block_reason(pid) if owned else lv_reason

	# Status: last action → the blocking reason of the action that matters now → a hint.
	var line: String = _status_text
	var bad: bool = not _status_ok
	if line == "":
		bad = false
		if not at_cap:
			line = lv_reason if lv_reason != "" \
					else Loc.t(L.COLLECTION_DETAIL_STATUS_HINT_LEVEL, {"have": lv_have, "cap": cap})
			bad = lv_reason != ""
		elif rank >= RunRules.rank_max():
			line = Loc.t(L.COLLECTION_DETAIL_FULLY_GROWN, {"rank": rank, "cap": cap})
		elif rk_reason != "":
			line = rk_reason
			bad = true
		else:
			line = Loc.t(L.COLLECTION_DETAIL_STATUS_HINT_RANK,
					{"have": _pm.currency_of("rank_stone"), "cost": rk_cost})
	var st: Label = %Status
	if line != "" and (bad or _status_text != ""):
		st.add_theme_color_override("font_color", OutgameTheme.NEGATIVE if bad else OutgameTheme.POSITIVE)
	else:
		st.remove_theme_color_override("font_color")
	st.text = line

	var lv_btn: Button = %LevelUp
	lv_btn.text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_COST, {"cost": lv_cost}) if lv_cost >= 0 \
			else Loc.t(L.UI_BUTTON_LEVEL_UP)
	lv_btn.disabled = lv_reason != ""
	var rk_btn: Button = %RankUp
	rk_btn.text = Loc.t(L.COLLECTION_DETAIL_RANK_UP_COST, {"cost": rk_cost}) if rk_cost > 0 \
			else Loc.t(L.COLLECTION_DETAIL_RANK_UP_BUTTON)
	rk_btn.disabled = not at_cap or rk_reason != ""


func _on_level_up_pressed() -> void:
	var pid: int = _base.id
	var err: String = _pm.level_up_pilot(pid)
	if err != "":
		_fail(err)
		return
	var lv: int = _pm.level_of(pid)
	var save_err: String = _pm.save_profile()
	if save_err != "":
		_status_text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_SAVE_FAILED, {"level": lv, "error": save_err})
		_status_ok = false
	else:
		_status_text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_REACHED, {"level": lv})
		_status_ok = true
	Haptics.play(Haptics.Kind.SUCCESS)
	_fill()            # in place — the scroll position stays
	leveled_up.emit(pid, lv)


func _on_rank_up_pressed() -> void:
	var pid: int = _base.id
	var err: String = _pm.rank_up_pilot(pid)
	if err != "":
		_fail(err)
		return
	var rank: int = _pm.rank_of(pid)
	var save_err: String = _pm.save_profile()
	if save_err != "":
		_status_text = Loc.t(L.COLLECTION_DETAIL_RANK_UP_SAVE_FAILED, {"rank": rank, "error": save_err})
		_status_ok = false
	else:
		_status_text = Loc.t(L.COLLECTION_DETAIL_RANK_UP_DONE,
				{"rank": rank, "cap": _pm.level_cap_of(pid)})
		_status_ok = true
	Haptics.play(Haptics.Kind.SUCCESS)
	_fill()
	ranked_up.emit(pid, rank)


func _fail(err: String) -> void:
	_status_text = err
	_status_ok = false
	Haptics.play(Haptics.Kind.ERROR)
	_fill()


# ── Pieces ───────────────────────────────────────────────────────────────────
## A pill sized to its text; returns the x after it (+ gap).
func _chip(parent: Control, text: String, x: float, bg: Color, fg: Color) -> float:
	var w: float = 32.0 + 15.0 * float(text.length())
	OutgameTheme.add_chip(parent, text, Vector2(x, 0.0), Vector2(w, 44), bg, fg, 22)
	return x + w + 10.0


## Frees code-made children right away (not `queue_free`) so the container re-lays
## out without them in the same frame.
func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


## 미리보기 전용 — **메모리 프로필만** 손본다(저장하지 않는다; 미리보기는 저장 버튼을 끊는다).
## 풀에서 등급이 가장 높은 선수(동률이면 id 작은 쪽)를 보유시키고(없으면 영입) 중복 1회 → 돌파 1
## (★3 이면 ★★★ + 흐린 ★), 레벨 상한까지 레벨업, 승급석을 채워 랭크업 가능 상태로 만든다
## (랭크 표의 달성 · 다음 · 돌파 필요가 한 번에 보인다). 그 id 를 돌려준다(풀이 비면 -1).
static func preview_stage_pilots(pm: Node, pool: Array) -> int:  # l10n-ignore
	var ready_id: int = -1
	for raw in pool:
		var pd := raw as PlayerData
		if pd != null and (ready_id < 0 or pm.stars_of(pd.id) > pm.stars_of(ready_id)):
			ready_id = pd.id
	if ready_id < 0:
		return -1
	if not pm.owns_pilot(ready_id):
		pm.grant_pilot(ready_id)
	if pm.breakthrough_of(ready_id) == 0 and pm.breakthrough_cap_of(ready_id) > 0:
		pm.grant_pilot(ready_id)
	var guard: int = 0
	while pm.level_of(ready_id) < pm.level_cap_of(ready_id) and guard < 100:
		pm.add_currency("levelup", maxi(0, pm.level_up_cost(ready_id)))
		if pm.level_up_pilot(ready_id) != "":
			break
		guard += 1
	pm.add_currency("rank_stone", maxi(0, pm.rank_up_cost(ready_id)))
	return ready_id


## F6 단독 실행 미리보기 — 실제 프로필(메모리에서만 손봄, `preview_stage_pilots`)의 랭크업 준비된
## 선수로 연다 (`resources/UiPreview.gd`). 두 버튼은 프로필을 저장하므로 누름을 출력만 하게 끊는다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.mute(%LevelUp, self, "레벨업")
	UiPreview.mute(%RankUp, self, "랭크업")
	UiPreview.trace(leveled_up)
	UiPreview.trace(ranked_up)
	var data: Dictionary = _gm.load_match_data()
	if data.has("error"):
		push_error("CollectionDetailSheet 미리보기: " + String(data["error"]))
		return
	var pool: Array = []
	for raw in data["players"]:
		var pd := raw as PlayerData
		if pd != null and not pd.is_mob:
			pool.append(pd)
	var pick_id: int = preview_stage_pilots(_pm, pool)
	for pd in pool:
		if (pd as PlayerData).id == pick_id:
			open(pd)
			return
	if not pool.is_empty():
		open(pool[0])
