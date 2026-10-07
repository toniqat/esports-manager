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
# **The layout lives in `CollectionDetailSheet.tscn`** (plus the item scenes
# `CollectionStatChip.tscn` · `CollectionBreakthroughRow.tscn`). This script makes no
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

const SCENE_PATH: String = "res://features/meta/collection/CollectionDetailSheet.tscn"
const STAT_CHIP_SCENE: PackedScene = preload("res://features/meta/collection/CollectionStatChip.tscn")
const BT_ROW_SCENE: PackedScene = preload("res://features/meta/collection/CollectionBreakthroughRow.tscn")

const STAT_NAMES: Array = ["전장 명중", "전장 회피", "교전 명중", "교전 회피", "공격 성장", "체력 성장"]
const BT_KIND_LABELS: Dictionary = {
	"stat_flat": "능력치", "salary_down": "샐러리",
	"stat_growth": "성장", "card_swap": "카드",
}

var _pm: Node = null
var _gm: Node = null
var _base: PlayerData = null      # Lv1 pool copy (never mutated)
var _fielded: PlayerData = null   # what the sheet shows (max level + breakthrough)
var _status_text: String = ""
var _status_ok: bool = false
var _art: TextureRect = null
var _badge: Panel = null
var _stat_chips: Array = []
var _cards_w: float = -1.0        # width the `%Cards` panels were built for


## 씬을 인스턴스한다. `CollectionDetailSheet.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> CollectionDetailSheet:
	return (load(SCENE_PATH) as PackedScene).instantiate() as CollectionDetailSheet


func _ready() -> void:
	_pm = get_node("/root/ProfileManager")
	_gm = get_node("/root/GameManager")
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	%LevelUp.pressed.connect(_on_level_up_pressed)
	# Sheet is STOP in the scene: taps on its empty parts must not reach the dim.
	var bust: Control = %Bust
	_art = PilotThumb.add_rounded_art(bust, Vector2.ZERO, bust.custom_minimum_size, 20)
	(%ExpTrack as Panel).add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 7))
	(%ExpFill as Panel).add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.ACCENT, 7))
	(%Bonus as Label).add_theme_color_override("font_color", OutgameTheme.POSITIVE)
	for i in PlayerData.STAT_KEYS.size() + 1:       # six stats + 종합
		var chip: Panel = STAT_CHIP_SCENE.instantiate()
		%StatGrid.add_child(chip)
		_stat_chips.append(chip)
	# CardDescBox measures its text at a fixed width — rebuild once the container knows it.
	(%Cards as Control).resized.connect(_on_cards_resized)


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
	_badge = PilotThumb.add_role_badge(%Bust, r, Vector2(10, 10))

	%Name.text = _base.name
	var seat: int = GameEnums.role_seat(r)
	var lane: String = String(TeamDraft.SLOT_NAMES[seat]) if seat < 5 else "?"
	# Same "lane · ROLE" words as `DraftDetailPanel` (the Korean role names repeat the lane).
	var role_name: String = String(DraftDetailPanel.ROLE_NAMES[r]) if r >= 0 and r < 5 else "?"
	%RoleLine.text = "%s · %s · 원소속 %s" % [lane, role_name, _team_short(_base.team_id)]
	(%RoleLine as Label).add_theme_color_override("font_color", role_col.darkened(0.1))

	# Chip row: rarity · 최대 Lv · 돌파 · 중복 (or 미보유).
	var chips: Control = %Chips
	_clear(chips)
	var pill: Panel = CollectionCell.add_rarity_pill(chips, _fielded.rarity, Vector2.ZERO, 44.0, 24)
	var cx: float = pill.size.x + 10.0
	if owned:
		var dupes: int = int(((_pm.profile["collection"] as Dictionary)
				.get(str(_base.id), {}) as Dictionary).get("dupes", 0))
		cx = _chip(chips, "최대 Lv %d" % max_lv, cx, OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT)
		cx = _chip(chips, "돌파 %d / %d" % [stage, RunRules.breakthrough_max()], cx,
				OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)
		_chip(chips, "중복 %d" % dupes, cx, OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT_SUB)
	else:
		_chip(chips, "미보유", cx, OutgameTheme.RAIL, OutgameTheme.TEXT_ON_FILL)

	%ExpBlock.visible = owned
	%UnownedBlock.visible = not owned
	if owned:
		_fill_exp(max_lv)

	# Salary at the shown level (breakthrough `salary_down` included).
	%SalaryTitle.text = "샐러리 (Lv %d 기준)" % _fielded.level
	%Salary.text = str(RunRules.salary_of(_fielded))
	%BonusRow.visible = _fielded.train_bonus_pct != 0
	%Bonus.text = "+%d%%" % _fielded.train_bonus_pct


## EXP towards the next **automatic** max-level raise (`add_pilot_exp` lifts the max
## level to `level_for_exp(exp)`; bought levels are never taken back).
func _fill_exp(max_lv: int) -> void:
	var exp_total: int = _pm.pilot_exp_of(_base.id)
	var at_max: bool = max_lv >= RunRules.max_level()
	var need: int = 0 if at_max else RunRules.exp_required(max_lv + 1)
	%ExpValue.text = "최대 레벨 도달 · 누적 %d" % exp_total if at_max \
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
	var title: String = "능력치 · Lv %d" % _fielded.level
	if _fielded.breakthrough > 0:
		title += " · 돌파 %d 반영" % _fielded.breakthrough
	if not owned:
		title += " (영입 시)"
	%StatsTitle.text = title
	for i in _stat_chips.size():
		var chip: Panel = _stat_chips[i]
		var key: String
		var val: int
		var delta: int
		var is_total: bool = i == PlayerData.STAT_KEYS.size()
		if is_total:
			key = "종합"
			val = _fielded.stat_total()
			delta = val - _base.stat_total()
		else:
			var sk: String = String(PlayerData.STAT_KEYS[i])
			key = String(STAT_NAMES[i])
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
	%BtAfterLabel.text = "%d단계 이후의 중복은 선수 파편으로 바뀝니다" % RunRules.breakthrough_max()
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
		kind_lbl.text = String(BT_KIND_LABELS.get(kind, kind))
		kind_lbl.theme_type_variation = &"AccentLabel" if reached else &"CaptionLabel"
		var desc: Label = row.get_node("%Desc")
		desc.text = _bt_desc(r)
		desc.theme_type_variation = &"BodyLabel" if reached or is_next else &"SubLabel"
		var state: Label = row.get_node("%State")
		state.text = "달성" if reached else ("다음" if is_next else "")
		state.theme_type_variation = &"AccentLabel" if reached else &"CaptionLabel"


## Table desc; a `card_swap` row also names the new card ("… → 카드명").
func _bt_desc(r: Dictionary) -> String:
	var d: String = String(r.get("desc", ""))
	if String(r["kind"]) != "card_swap":
		return d
	var parts: PackedStringArray = String(r["value"]).split(":")
	if parts.size() != 2:
		return d
	var def: Dictionary = _gm.card_def(int(parts[1]))
	if def.is_empty():
		return d
	return "%s → %s" % [d, String(def.get("name", "?"))]


func _fill_cards() -> void:
	var swapped: bool = _fielded.pilot_cards != _base.pilot_cards
	%CardsTitle.text = "파일럿 카드" + (" · 돌파로 교체됨" if swapped else "")
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
		reason = "미보유 선수는 레벨업할 수 없습니다"
	elif cost < 0:
		reason = "최대 레벨입니다 (Lv %d)" % RunRules.max_level()
	elif have < cost:
		reason = "레벨업 재화가 부족합니다 (%d 필요 · 보유 %d)" % [cost, have]
	var line: String = _status_text if _status_text != "" else reason
	var st: Label = %Status
	if line == "":
		line = "레벨업 재화 %d 보유 · 최대 레벨 +1 = 런에서 고를 수 있는 레벨 +1" % have
		st.remove_theme_color_override("font_color")
	else:
		st.add_theme_color_override("font_color", OutgameTheme.POSITIVE
				if _status_text != "" and _status_ok else OutgameTheme.NEGATIVE)
	st.text = line
	var btn: Button = %LevelUp
	btn.text = "레벨업  ·  %d" % cost if cost >= 0 else "레벨업"
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
		_status_text = "Lv %d — 저장 실패: %s" % [lv, save_err]
		_status_ok = false
	else:
		_status_text = "최대 레벨 Lv %d 달성" % lv
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
	var teams: Array = RunRules.team_packages()
	if team_id < 0 or team_id >= teams.size():
		return "T%d" % team_id
	return String((teams[team_id] as Dictionary)["short_name"])
