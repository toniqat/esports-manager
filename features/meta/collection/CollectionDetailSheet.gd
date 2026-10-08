class_name CollectionDetailSheet
extends CanvasLayer

# Pilot detail sheet of the lobby 컬렉션 tab (M10) — a full-screen modal (Pattern C,
# `docs/mobile_safe_area.md`): dim = whole viewport, sheet between `top_y()` and
# `bottom_y()`, the footer buttons end above the bottom gesture zone.
#
#   ┌ hero: bust · name · role · rarity / Lv / 돌파 / 중복 chips · EXP bar · salary ┐
#   │ 능력치 (max level + breakthrough, delta vs Lv1)                             │  scrolls
#   │ 돌파 table (5 stages, reached highlighted, card_swap names the card)       │
#   │ 파일럿 카드 (after breakthrough swaps)                                      │
#   ├ status line (why 레벨업 is disabled / what just happened) ─────────────────┤
#   └ [닫기] [레벨업 · cost] ──────────────────────────────────────────────────────┘
#
# **The layout lives in `UI_View_CollectionDetailSheet.tscn`** (plus the item scenes
# `UI_Comp_CollectionStatChip.tscn` · `UI_Comp_CollectionBreakthroughRow.tscn`). This script makes no
# static nodes: it fills `%` nodes with text, shows / hides the optional blocks and
# wires signals. What stays in code is data: role / rarity / reached tints, the chip
# pills (sized to their text), the EXP fill width, the bust art + role badge, the
# `CardDescBox` panels, and the safe-area offset of `%SafeArea`.
#
# Numbers come from a **copy** of the Lv1 pool pilot: `RunRules.apply_level(max_level)`
# then `RunRules.apply_breakthrough(stage)` — the same two calls run start makes, so
# what this sheet shows is what the pilot brings into a run at that level.
#
# 레벨업: `ProfileManager.level_up_pilot` → `save_profile()` → `leveled_up` (the tab
# refreshes the cell, currency strip and toasts). The sheet refills in place.
#
# 쓰는 법:
#   var s := CollectionDetailSheet.create()
#   add_child(s)
#   s.leveled_up.connect(...)
#   s.open(pilot)

signal leveled_up(pilot_id: int, new_level: int)

const SCENE_PATH: String = "res://features/meta/collection/UI_View_CollectionDetailSheet.tscn"
const STAT_CHIP_SCENE: PackedScene = preload("res://features/meta/collection/UI_Comp_CollectionStatChip.tscn")
const BT_ROW_SCENE: PackedScene = preload("res://features/meta/collection/UI_Comp_CollectionBreakthroughRow.tscn")

## Breakthrough line templates by kind (`{n}` = row value). `card_swap` is built in `_bt_desc`.
const BT_DESC: Dictionary = {  # l10n-keys: breakthrough.kind.*
	"stat_flat": L.BREAKTHROUGH_KIND_STAT_FLAT, "salary_down": L.BREAKTHROUGH_KIND_SALARY_DOWN,
	"stat_growth": L.BREAKTHROUGH_KIND_STAT_GROWTH,
}
const BT_KIND_LABELS: Dictionary = {  # l10n-keys: collection.bt_kind.*
	"stat_flat": L.COLLECTION_BT_KIND_STAT_FLAT, "salary_down": L.COLLECTION_BT_KIND_SALARY_DOWN,
	"stat_growth": L.COLLECTION_BT_KIND_STAT_GROWTH, "card_swap": L.COLLECTION_BT_KIND_CARD_SWAP,
}

var _pm: Node = null
var _gm: Node = null
var _base: PlayerData = null      # Lv1 pool copy (never mutated)
var _fielded: PlayerData = null   # what the sheet shows (max level + breakthrough)
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


## The pilot as this profile would field it: Lv `max_level`, breakthrough applied.
## Unowned → Lv1, no breakthrough.
static func fielded_copy(base: PlayerData, max_level: int, stage: int) -> PlayerData:
	var copy := base.duplicate() as PlayerData
	# Own array — `card_swap` writes into it, and the pool copy must stay Lv1 / stage 0.
	copy.pilot_cards = base.pilot_cards.duplicate()
	RunRules.apply_level(copy, maxi(1, max_level))
	if stage > 0:
		RunRules.apply_breakthrough(copy, stage)
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
	var max_lv: int = _pm.max_level_of(_base.id)
	var owned: bool = max_lv > 0
	var stage: int = _pm.breakthrough_of(_base.id) if owned else 0
	_fielded = fielded_copy(_base, max_lv, stage)
	_fill_hero(owned, max_lv, stage)
	_fill_stats(owned)
	_fill_breakthrough(stage, owned)
	_fill_cards()
	_fill_footer(owned)


func _fill_hero(owned: bool, max_lv: int, stage: int) -> void:
	var r: int = int(_base.role)
	var role_col: Color = OutgameTheme.ROLE_COLORS[r] if r >= 0 and r < 5 else OutgameTheme.NEUTRAL
	(%BustPlate as Panel).add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(role_col.lerp(OutgameTheme.SURFACE, 0.78), 20))
	var tex: Texture2D = PilotImages.bust_for(_base.id)
	_art.texture = tex if tex != null else PilotImages.face_for(_base.id)
	(_art.get_parent() as Control).modulate = Color.WHITE if owned else CollectionCell.UNOWNED_MODULATE
	if _badge != null:
		_badge.free()
	_badge = PilotThumb.add_position_badge(%Bust, r, Vector2(10, 10))

	%Name.text = _base.name
	# The position is the badge on the bust (`PositionBadge`) — this line only names the home team.
	%RoleLine.text = Loc.t(L.RUN_SETUP_DRAFT_ORIGIN_TEAM, {"team": _team_short(_base.team_id)})

	# Chip row: rarity · 최대 Lv · 돌파 · 중복 (or 미보유).
	var chips: Control = %Chips
	_clear(chips)
	var pill: Panel = CollectionCell.add_rarity_pill(chips, _fielded.rarity, Vector2.ZERO, 44.0, 24)
	var cx: float = pill.size.x + 10.0
	if owned:
		var dupes: int = int(((_pm.profile["collection"] as Dictionary)
				.get(str(_base.id), {}) as Dictionary).get("dupes", 0))
		cx = _chip(chips, Loc.t(L.COLLECTION_DETAIL_CHIP_MAX_LEVEL, {"level": max_lv}), cx, OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT)
		cx = _chip(chips, Loc.t(L.COLLECTION_DETAIL_CHIP_BREAKTHROUGH,
				{"n": stage, "max": RunRules.breakthrough_max()}), cx,
				OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)
		_chip(chips, Loc.t(L.COLLECTION_DETAIL_CHIP_DUPES, {"n": dupes}), cx, OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT_SUB)
	else:
		_chip(chips, Loc.t(L.UI_WORD_UNOWNED), cx, OutgameTheme.RAIL, OutgameTheme.TEXT_ON_FILL)

	%ExpBlock.visible = owned
	%UnownedBlock.visible = not owned
	if owned:
		_fill_exp(max_lv)

	# Salary at the shown level (breakthrough `salary_down` included).
	%SalaryTitle.text = Loc.t(L.COLLECTION_DETAIL_SALARY_AT_LEVEL, {"level": _fielded.level})
	%Salary.text = str(RunRules.salary_of(_fielded))
	%BonusRow.visible = _fielded.train_bonus_pct != 0
	%Bonus.text = "+%d%%" % _fielded.train_bonus_pct


## EXP towards the next **automatic** max-level raise (`add_pilot_exp` lifts the max
## level to `level_for_exp(exp)`; bought levels are never taken back).
func _fill_exp(max_lv: int) -> void:
	var exp_total: int = _pm.pilot_exp_of(_base.id)
	var at_max: bool = max_lv >= RunRules.max_level()
	var need: int = 0 if at_max else RunRules.exp_required(max_lv + 1)
	%ExpValue.text = Loc.t(L.COLLECTION_DETAIL_EXP_MAXED, {"exp": exp_total}) if at_max \
			else "%d / %d  →  Lv %d" % [exp_total, need, max_lv + 1]
	var ratio: float = 1.0
	if not at_max:
		var from: int = RunRules.exp_required(max_lv)
		ratio = clampf(float(exp_total - from) / float(maxi(1, need - from)), 0.0, 1.0)
	# The fill is anchored to the track: its right anchor is the ratio (min width in the scene).
	var fill: Panel = %ExpFill
	fill.visible = ratio > 0.0
	fill.anchor_right = ratio


func _fill_stats(owned: bool) -> void:
	# Unowned pilots are shown at stage 0, so the unowned and breakthrough titles never meet.
	var title: String
	if not owned:
		title = Loc.t(L.COLLECTION_DETAIL_STATS_TITLE_UNOWNED, {"level": _fielded.level})
	elif _fielded.breakthrough > 0:
		title = Loc.t(L.COLLECTION_DETAIL_STATS_TITLE_BT,
				{"level": _fielded.level, "bt": _fielded.breakthrough})
	else:
		title = Loc.t(L.COLLECTION_DETAIL_STATS_TITLE, {"level": _fielded.level})
	%StatsTitle.text = title
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


func _fill_breakthrough(stage: int, owned: bool) -> void:
	var rows_box: Control = %BtRows
	_clear(rows_box)
	var rows: Array = RunRules.breakthrough_rows(_base.id)
	%BtEmpty.visible = rows.is_empty()
	%BtAfter.visible = not rows.is_empty()
	%BtAfterLabel.text = Loc.t(L.COLLECTION_DETAIL_BT_AFTER, {"n": RunRules.breakthrough_max()})
	for raw in rows:
		var r: Dictionary = raw
		var st: int = int(r["stage"])
		var reached: bool = owned and st <= stage
		var is_next: bool = owned and st == stage + 1
		var row: Panel = BT_ROW_SCENE.instantiate()
		rows_box.add_child(row)
		row.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if reached else OutgameTheme.SURFACE,
				14, OutgameTheme.ACCENT if reached else OutgameTheme.BORDER, 2))
		(row.get_node("%Disc") as Panel).add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT if reached else OutgameTheme.SURFACE_SUNK, 24))
		var num: Label = row.get_node("%Num")
		num.text = str(st)
		num.add_theme_color_override("font_color",
				OutgameTheme.TEXT_ON_FILL if reached else OutgameTheme.TEXT_SUB)
		var kind: String = String(r["kind"])
		var kind_lbl: Label = row.get_node("%Kind")
		kind_lbl.text = Loc.t(String(BT_KIND_LABELS[kind])) if BT_KIND_LABELS.has(kind) else kind  # l10n-dynamic: collection.bt_kind.*
		kind_lbl.theme_type_variation = &"AccentLabel" if reached else &"CaptionLabel"
		var desc: Label = row.get_node("%Desc")
		desc.text = _bt_desc(r)
		desc.theme_type_variation = &"BodyLabel" if reached or is_next else &"SubLabel"
		var state: Label = row.get_node("%State")
		state.text = Loc.t(L.COLLECTION_DETAIL_BT_REACHED) if reached \
				else (Loc.t(L.COLLECTION_DETAIL_BT_NEXT) if is_next else "")
		state.theme_type_variation = &"AccentLabel" if reached else &"CaptionLabel"


## Breakthrough line from the kind template + `value`; a `card_swap` row also names the new
## card ("… → 카드명"). Numbers come only from the data row, never from the text.
func _bt_desc(r: Dictionary) -> String:
	var kind: String = String(r["kind"])
	var v: String = String(r["value"])
	if kind != "card_swap":
		return Loc.t(String(BT_DESC[kind]), {"n": v}) if BT_DESC.has(kind) else v  # l10n-dynamic: breakthrough.kind.*
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
	%CardsTitle.text = Loc.t(L.COLLECTION_DETAIL_CARDS_TITLE_SWAPPED) if swapped \
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


func _fill_footer(owned: bool) -> void:
	var cost: int = _pm.level_up_cost(_base.id) if owned else -1
	var have: int = _pm.currency_of("levelup")
	var reason: String = ""
	if not owned:
		reason = Loc.t(L.COLLECTION_DETAIL_CANNOT_UNOWNED)
	elif cost < 0:
		reason = Loc.t(L.COLLECTION_DETAIL_AT_MAX_LEVEL, {"level": RunRules.max_level()})
	elif have < cost:
		reason = Loc.t(L.COLLECTION_DETAIL_NOT_ENOUGH, {"cost": cost, "have": have})
	var line: String = _status_text if _status_text != "" else reason
	var st: Label = %Status
	if line == "":
		line = Loc.t(L.COLLECTION_DETAIL_STATUS_HINT, {"have": have})
		st.remove_theme_color_override("font_color")
	else:
		st.add_theme_color_override("font_color", OutgameTheme.POSITIVE
				if _status_text != "" and _status_ok else OutgameTheme.NEGATIVE)
	st.text = line
	var btn: Button = %LevelUp
	btn.text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_COST, {"cost": cost}) if cost >= 0 \
			else Loc.t(L.UI_BUTTON_LEVEL_UP)
	btn.disabled = reason != ""


func _on_level_up_pressed() -> void:
	var pid: int = _base.id
	var err: String = _pm.level_up_pilot(pid)
	if err != "":
		_status_text = err
		_status_ok = false
		Haptics.play(Haptics.Kind.ERROR)
		_fill()
		return
	var save_err: String = _pm.save_profile()
	var lv: int = _pm.max_level_of(pid)
	if save_err != "":
		_status_text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_SAVE_FAILED, {"level": lv, "error": save_err})
		_status_ok = false
	else:
		_status_text = Loc.t(L.COLLECTION_DETAIL_LEVEL_UP_DONE, {"level": lv})
		_status_ok = true
	Haptics.play(Haptics.Kind.SUCCESS)
	_fill()            # in place — the scroll position stays
	leveled_up.emit(pid, lv)


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


func _team_short(team_id: int) -> String:
	return RunRules.team_short_name(team_id)


## F6 단독 실행 미리보기 — 실제 프로필에서 가장 많이 키운 보유 선수(없으면 풀의 첫 선수)로
## 연다 (`resources/UiPreview.gd`). 레벨업은 프로필을 저장하므로 누름을 출력만 하게 끊는다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.mute(%LevelUp, self, "레벨업")
	UiPreview.trace(leveled_up)
	var data: Dictionary = _gm.load_match_data()
	if data.has("error"):
		push_error("CollectionDetailSheet 미리보기: " + String(data["error"]))
		return
	var pick: PlayerData = null
	var best: int = -1
	for raw in data["players"]:
		var pd := raw as PlayerData
		if pd == null or pd.is_mob:
			continue
		var score: int = _pm.breakthrough_of(pd.id) * 100 + _pm.max_level_of(pd.id)
		if score > best:
			best = score
			pick = pd
	if pick != null:
		open(pick)
