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
# Numbers come from a **copy** of the Lv1 pool pilot: `RunRules.apply_level(max_level)`
# then `RunRules.apply_breakthrough(stage)` — the same two calls run start makes, so
# what this sheet shows is what the pilot brings into a run at that level.
#
# 레벨업: `ProfileManager.level_up_pilot` → `save_profile()` → `leveled_up` (the tab
# refreshes the cell, currency strip and toasts). The sheet rebuilds in place.

signal leveled_up(pilot_id: int, new_level: int)

const OVERLAY_LAYER: int = 20
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)

const SHEET_X: float = 24.0
const SHEET_TOP_GAP: float = 48.0
const SHEET_BOTTOM_GAP: float = 16.0
const PAD: float = 36.0
const FOOTER_BTN_H: float = 104.0
const STATUS_H: float = 40.0

const BUST_W: float = 230.0
const HERO_GAP: float = 28.0

const SECTION_FONT: int = 26
const SECTION_H: float = 44.0
const SECTION_GAP: float = 32.0

const STAT_COLS: int = 4
const STAT_GAP: float = 12.0
const STAT_H: float = 104.0
const STAT_NAMES: Array = ["전장 명중", "전장 회피", "교전 명중", "교전 회피", "공격 성장", "체력 성장"]

const BT_ROW_H: float = 76.0
const BT_ROW_GAP: float = 10.0
const BT_KIND_LABELS: Dictionary = {
	"stat_flat": "능력치", "salary_down": "샐러리",
	"stat_growth": "성장", "card_swap": "카드",
}

const CARD_GAP: float = 12.0

var _pm: Node = null
var _gm: Node = null
var _base: PlayerData = null      # Lv1 pool copy (never mutated)
var _root: Control = null
var _status_text: String = ""
var _status_ok: bool = false
var _scroll_keep: int = 0
var _levelup_btn: Button = null


func _init() -> void:
	layer = OVERLAY_LAYER


func open(p: PlayerData) -> void:
	_status_text = ""
	_scroll_keep = 0
	_base = p
	_rebuild()


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_levelup_btn = null


func is_open() -> bool:
	return _root != null and is_instance_valid(_root)


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


# ── Build ────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	if _pm == null:
		_pm = get_node("/root/ProfileManager")
		_gm = get_node("/root/GameManager")
	close()
	if _base == null:
		return
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	# Under a CanvasLayer anchors don't resolve — size explicitly.
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = vp
	dim.pressed.connect(close)
	_root.add_child(dim)
	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.size = vp
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	var top: float = ScreenMetrics.top_y() + SHEET_TOP_GAP
	var bottom: float = ScreenMetrics.bottom_y() - SHEET_BOTTOM_GAP
	var sheet_w: float = vp.x - SHEET_X * 2.0
	var sheet := Panel.new()
	sheet.position = Vector2(SHEET_X, top)
	sheet.size = Vector2(sheet_w, bottom - top)
	# STOP (Panel default): taps on the sheet's empty parts must not reach the dim.
	sheet.add_theme_stylebox_override("panel", OutgameTheme.card_style(28))
	_root.add_child(sheet)

	var inner_w: float = sheet_w - PAD * 2.0
	var btn_y: float = sheet.size.y - PAD * 0.75 - FOOTER_BTN_H
	var status_y: float = btn_y - 12.0 - STATUS_H
	var vs: Dictionary = OutgameTheme.add_vscroll(sheet, Vector2(PAD, PAD * 0.75),
			Vector2(inner_w, status_y - 12.0 - PAD * 0.75))
	var scroll: ScrollContainer = vs["scroll"]
	var body: Control = vs["body"]

	var max_lv: int = _pm.max_level_of(_base.id)
	var owned: bool = max_lv > 0
	var stage: int = _pm.breakthrough_of(_base.id) if owned else 0
	var fielded: PlayerData = fielded_copy(_base, max_lv, stage)

	var y: float = 0.0
	y = _build_hero(body, inner_w, y, fielded, owned, max_lv, stage)
	y = _build_stats(body, inner_w, y + SECTION_GAP, fielded, owned)
	y = _build_breakthrough(body, inner_w, y + SECTION_GAP, stage, owned)
	y = _build_cards(body, inner_w, y + SECTION_GAP, fielded)
	body.custom_minimum_size = Vector2(inner_w, y + 16.0)
	body.size = body.custom_minimum_size

	OutgameTheme.add_divider(sheet, Vector2(PAD, status_y - 6.0), inner_w)
	_build_footer(sheet, inner_w, status_y, btn_y, owned)
	if _scroll_keep > 0:
		scroll.set_deferred("scroll_vertical", _scroll_keep)
	scroll.get_v_scroll_bar().value_changed.connect(func(v: float) -> void:
		_scroll_keep = int(v))


func _build_hero(body: Control, w: float, y: float, fielded: PlayerData,
		owned: bool, max_lv: int, stage: int) -> float:
	var bust_h: float = BUST_W / PilotImages.BUST_ASPECT
	var r: int = int(_base.role)
	var role_col: Color = OutgameTheme.ROLE_COLORS[r] if r >= 0 and r < 5 else OutgameTheme.NEUTRAL
	var back := Panel.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = Vector2(0, y)
	back.size = Vector2(BUST_W, bust_h)
	back.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(role_col.lerp(OutgameTheme.SURFACE, 0.78), 20))
	body.add_child(back)
	var art: TextureRect = PilotThumb.add_rounded_art(body, Vector2(0, y),
			Vector2(BUST_W, bust_h), 20)
	var tex: Texture2D = PilotImages.bust_for(_base.id)
	art.texture = tex if tex != null else PilotImages.face_for(_base.id)
	if not owned:
		(art.get_parent() as Control).modulate = CollectionCell.UNOWNED_MODULATE
	PilotThumb.add_role_badge(body, r, Vector2(10, y + 10))

	var x: float = BUST_W + HERO_GAP
	var cw: float = w - x
	var name_lbl := UiHelpers.mk_label(body, _base.name, 52, OutgameTheme.TEXT,
			Vector2(x, y - 6.0), Vector2(cw, 66))
	name_lbl.clip_text = true
	var seat: int = GameEnums.role_seat(r)
	var lane: String = String(TeamDraft.SLOT_NAMES[seat]) if seat < 5 else "?"
	# Same "lane · ROLE" words as `DraftDetailPanel` (the Korean role names repeat the lane).
	var role_name: String = String(DraftDetailPanel.ROLE_NAMES[r]) if r >= 0 and r < 5 else "?"
	var sub := UiHelpers.mk_label(body, "%s · %s · 원소속 %s" % [lane, role_name, _team_short(_base.team_id)],
			24, role_col.darkened(0.1), Vector2(x, y + 62.0), Vector2(cw, 34))
	sub.clip_text = true

	# Chip row: rarity · 최대 Lv · 돌파 · 중복 (or 미보유).
	var cy: float = y + 112.0
	var pill: Panel = CollectionCell.add_rarity_pill(body, fielded.rarity, Vector2(x, cy), 44.0, 24)
	var cx: float = x + pill.size.x + 10.0
	if owned:
		var dupes: int = int(((_pm.profile["collection"] as Dictionary)
				.get(str(_base.id), {}) as Dictionary).get("dupes", 0))
		cx = _chip(body, "최대 Lv %d" % max_lv, cx, cy, OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT)
		cx = _chip(body, "돌파 %d / %d" % [stage, RunRules.breakthrough_max()], cx, cy,
				OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)
		_chip(body, "중복 %d" % dupes, cx, cy, OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT_SUB)
	else:
		_chip(body, "미보유", cx, cy, OutgameTheme.RAIL, OutgameTheme.TEXT_ON_FILL)

	var ey: float = cy + 76.0
	if owned:
		ey = _build_exp(body, x, cw, ey, max_lv)
	else:
		var l := UiHelpers.mk_label(body,
				"아직 보유하지 않은 선수입니다.\n상점의 선수 가챠나 파편 확정 구매로 영입합니다.",
				24, OutgameTheme.TEXT_SUB, Vector2(x, ey), Vector2(cw, 70))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ey += 84.0

	# Salary at the shown level (breakthrough `salary_down` included).
	ey += 14.0
	UiHelpers.mk_label(body, "샐러리 (Lv %d 기준)" % fielded.level, 22, OutgameTheme.TEXT_SUB,
			Vector2(x, ey), Vector2(cw * 0.6, 32))
	UiHelpers.mk_label(body, str(RunRules.salary_of(fielded)), 30, OutgameTheme.TEXT,
			Vector2(x, ey - 4.0), Vector2(cw, 40), HORIZONTAL_ALIGNMENT_RIGHT)
	ey += 44.0
	if fielded.train_bonus_pct != 0:
		UiHelpers.mk_label(body, "훈련 EXP 보너스 (돌파)", 22, OutgameTheme.TEXT_SUB,
				Vector2(x, ey), Vector2(cw * 0.6, 32))
		UiHelpers.mk_label(body, "+%d%%" % fielded.train_bonus_pct, 30, OutgameTheme.POSITIVE,
				Vector2(x, ey - 4.0), Vector2(cw, 40), HORIZONTAL_ALIGNMENT_RIGHT)
		ey += 44.0
	return maxf(y + bust_h, ey)


## EXP towards the next **automatic** max-level raise (`add_pilot_exp` lifts the max
## level to `level_for_exp(exp)`; bought levels are never taken back).
func _build_exp(body: Control, x: float, w: float, y: float, max_lv: int) -> float:
	var exp_total: int = _pm.pilot_exp_of(_base.id)
	UiHelpers.mk_label(body, "선수 EXP", 22, OutgameTheme.TEXT_SUB,
			Vector2(x, y), Vector2(w * 0.5, 32))
	var at_max: bool = max_lv >= RunRules.max_level()
	var need: int = 0 if at_max else RunRules.exp_required(max_lv + 1)
	var line: String = "최대 레벨 도달 · 누적 %d" % exp_total if at_max \
			else "%d / %d  →  Lv %d" % [exp_total, need, max_lv + 1]
	UiHelpers.mk_label(body, line, 24, OutgameTheme.TEXT,
			Vector2(x, y), Vector2(w, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	var ratio: float = 1.0
	if not at_max:
		var from: int = RunRules.exp_required(max_lv)
		ratio = clampf(float(exp_total - from) / float(maxi(1, need - from)), 0.0, 1.0)
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = Vector2(x, y + 42.0)
	track.size = Vector2(w, 14)
	track.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 7))
	body.add_child(track)
	if ratio > 0.0:
		var fill := Panel.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.size = Vector2(maxf(14.0, w * ratio), 14)
		fill.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.ACCENT, 7))
		track.add_child(fill)
	return y + 70.0


func _build_stats(body: Control, w: float, y: float, fielded: PlayerData, owned: bool) -> float:
	var title: String = "능력치 · Lv %d" % fielded.level
	if fielded.breakthrough > 0:
		title += " · 돌파 %d 반영" % fielded.breakthrough
	if not owned:
		title += " (영입 시)"
	y = _section(body, w, y, title)
	var chip_w: float = (w - STAT_GAP * float(STAT_COLS - 1)) / float(STAT_COLS)
	var n: int = PlayerData.STAT_KEYS.size() + 1       # six stats + 종합
	for i in n:
		var col: int = i % STAT_COLS
		var row: int = floori(float(i) / float(STAT_COLS))
		var at := Vector2(float(col) * (chip_w + STAT_GAP), y + float(row) * (STAT_H + STAT_GAP))
		var key: String
		var val: int
		var delta: int
		var is_total: bool = i == PlayerData.STAT_KEYS.size()
		if is_total:
			key = "종합"
			val = fielded.stat_total()
			delta = val - _base.stat_total()
		else:
			var sk: String = String(PlayerData.STAT_KEYS[i])
			key = String(STAT_NAMES[i])
			val = int(fielded.get(sk))
			delta = val - int(_base.get(sk))
		var chip: Panel = OutgameTheme.add_card(body, at, Vector2(chip_w, STAT_H), 16,
				OutgameTheme.ACCENT_DIM if is_total else OutgameTheme.SURFACE_SUNK)
		UiHelpers.mk_label(chip, key, 20, OutgameTheme.TEXT_SUB,
				Vector2(16, 12), Vector2(chip_w - 32.0, 28))
		UiHelpers.mk_label(chip, str(val), 38,
				OutgameTheme.ACCENT_TEXT if is_total else OutgameTheme.TEXT,
				Vector2(16, 44), Vector2(chip_w - 32.0, 48))
		if delta != 0:
			UiHelpers.mk_label(chip, "%+d" % delta, 22,
					OutgameTheme.POSITIVE if delta > 0 else OutgameTheme.NEGATIVE,
					Vector2(16, 56), Vector2(chip_w - 32.0, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	var rows: int = ceili(float(n) / float(STAT_COLS))
	y += float(rows) * STAT_H + float(rows - 1) * STAT_GAP
	if fielded.stat_total() == _base.stat_total():
		return y
	var note := UiHelpers.mk_label(body, "초록 숫자 = Lv1 · 돌파 전 대비", 20, OutgameTheme.TEXT_FAINT,
			Vector2(0, y + 8.0), Vector2(w, 28), HORIZONTAL_ALIGNMENT_RIGHT)
	note.clip_text = true
	return y + 36.0


func _build_breakthrough(body: Control, w: float, y: float, stage: int, owned: bool) -> float:
	y = _section(body, w, y, "돌파 — 중복 영입마다 한 단계")
	var rows: Array = RunRules.breakthrough_rows(_base.id)
	if rows.is_empty():
		UiHelpers.mk_label(body, "돌파 표 없음", 22, OutgameTheme.TEXT_FAINT,
				Vector2(0, y), Vector2(w, 32))
		return y + 36.0
	for raw in rows:
		var r: Dictionary = raw
		var st: int = int(r["stage"])
		var reached: bool = owned and st <= stage
		var is_next: bool = owned and st == stage + 1
		var row := Panel.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.position = Vector2(0, y)
		row.size = Vector2(w, BT_ROW_H)
		row.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if reached else OutgameTheme.SURFACE,
				14, OutgameTheme.ACCENT if reached else OutgameTheme.BORDER, 2))
		body.add_child(row)
		# Stage disc.
		var disc := Panel.new()
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.position = Vector2(16, (BT_ROW_H - 48.0) * 0.5)
		disc.size = Vector2(48, 48)
		disc.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT if reached else OutgameTheme.SURFACE_SUNK, 24))
		row.add_child(disc)
		var num := UiHelpers.mk_label(disc, str(st), 24,
				OutgameTheme.TEXT_ON_FILL if reached else OutgameTheme.TEXT_SUB,
				Vector2.ZERO, Vector2(48, 48), HORIZONTAL_ALIGNMENT_CENTER)
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var kind: String = String(r["kind"])
		var kind_lbl := UiHelpers.mk_label(row, String(BT_KIND_LABELS.get(kind, kind)), 20,
				OutgameTheme.ACCENT_TEXT if reached else OutgameTheme.TEXT_SUB,
				Vector2(80, 0), Vector2(80, BT_ROW_H))
		kind_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var status_w: float = 120.0
		var desc := UiHelpers.mk_label(row, _bt_desc(r), 24,
				OutgameTheme.TEXT if reached or is_next else OutgameTheme.TEXT_SUB,
				Vector2(164, 0), Vector2(w - 164.0 - status_w - 16.0, BT_ROW_H))
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc.clip_text = true
		var status: String = "달성" if reached else ("다음" if is_next else "")
		if status != "":
			var s := UiHelpers.mk_label(row, status, 22,
					OutgameTheme.ACCENT_TEXT if reached else OutgameTheme.TEXT_SUB,
					Vector2(w - status_w - 16.0, 0), Vector2(status_w, BT_ROW_H),
					HORIZONTAL_ALIGNMENT_RIGHT)
			s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		y += BT_ROW_H + BT_ROW_GAP
	var after := UiHelpers.mk_label(body,
			"%d단계 이후의 중복은 선수 파편으로 바뀝니다" % RunRules.breakthrough_max(),
			20, OutgameTheme.TEXT_FAINT, Vector2(0, y), Vector2(w, 28), HORIZONTAL_ALIGNMENT_RIGHT)
	after.clip_text = true
	return y + 32.0


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


func _build_cards(body: Control, w: float, y: float, fielded: PlayerData) -> float:
	var swapped: bool = fielded.pilot_cards != _base.pilot_cards
	y = _section(body, w, y, "파일럿 카드" + (" · 돌파로 교체됨" if swapped else ""))
	var placed: int = 0
	for raw in _gm.pilot_card_ids_for(fielded):
		var def: Dictionary = _gm.card_def(int(raw))
		if def.is_empty():
			continue
		if placed > 0:
			y += CARD_GAP
		var box := CardDescBox.build(CardData.from_def(def), w, true)
		box.position = Vector2(0, y)
		body.add_child(box)
		y += box.size.y
		placed += 1
	return y


func _build_footer(sheet: Control, w: float, status_y: float, btn_y: float, owned: bool) -> void:
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
	var col: Color = OutgameTheme.POSITIVE if _status_text != "" and _status_ok \
			else (OutgameTheme.NEGATIVE if line != "" else OutgameTheme.TEXT_SUB)
	if line == "":
		line = "레벨업 재화 %d 보유 · 최대 레벨 +1 = 런에서 고를 수 있는 레벨 +1" % have
	var st := UiHelpers.mk_label(sheet, line, 22, col, Vector2(PAD, status_y),
			Vector2(w, STATUS_H), HORIZONTAL_ALIGNMENT_CENTER)
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.clip_text = true

	var close_w: float = floorf((w - 16.0) / 3.0)
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_ghost_button(close_btn, 30)
	close_btn.position = Vector2(PAD, btn_y)
	close_btn.size = Vector2(close_w, FOOTER_BTN_H)
	close_btn.pressed.connect(close)
	sheet.add_child(close_btn)

	_levelup_btn = Button.new()
	_levelup_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_primary_button(_levelup_btn, 32)
	_levelup_btn.text = "레벨업  ·  %d" % cost if cost >= 0 else "레벨업"
	_levelup_btn.disabled = reason != ""
	_levelup_btn.position = Vector2(PAD + close_w + 16.0, btn_y)
	_levelup_btn.size = Vector2(w - close_w - 16.0, FOOTER_BTN_H)
	_levelup_btn.pressed.connect(_on_level_up_pressed)
	sheet.add_child(_levelup_btn)


func _on_level_up_pressed() -> void:
	var pid: int = _base.id
	var err: String = _pm.level_up_pilot(pid)
	if err != "":
		_status_text = err
		_status_ok = false
		Haptics.play(Haptics.Kind.ERROR)
		_rebuild()
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
	_rebuild()
	leveled_up.emit(pid, lv)


# ── Pieces ───────────────────────────────────────────────────────────────────
func _section(body: Control, w: float, y: float, title: String) -> float:
	var lbl := UiHelpers.mk_label(body, title, SECTION_FONT, OutgameTheme.TEXT,
			Vector2(0, y), Vector2(w, SECTION_H))
	lbl.clip_text = true
	OutgameTheme.add_divider(body, Vector2(0, y + SECTION_H + 2.0), w)
	return y + SECTION_H + 14.0


## A pill sized to its text; returns the x after it (+ gap).
func _chip(body: Control, text: String, x: float, y: float, bg: Color, fg: Color) -> float:
	var w: float = 32.0 + 15.0 * float(text.length())
	OutgameTheme.add_chip(body, text, Vector2(x, y), Vector2(w, 44), bg, fg, 22)
	return x + w + 10.0


func _team_short(team_id: int) -> String:
	var teams: Array = RunRules.team_packages()
	if team_id < 0 or team_id >= teams.size():
		return "T%d" % team_id
	return String((teams[team_id] as Dictionary)["short_name"])
