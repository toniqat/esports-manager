class_name ManagerTypePopup
extends CanvasLayer

# First-lobby modal: pick the manager type (운영형 / 실전형) — plan §11.0 (M3).
#
# Shown by `LobbyScreen` while `ProfileManager.manager_type_chosen()` is false.
# **It cannot be dismissed without choosing**: the dim swallows taps but does not
# close, and there is no cancel button. The only way out is picking an option and
# pressing confirm, which emits `chosen(type_id)` — the lobby saves it through
# `ProfileManager.set_manager_type`. Changing it later is a prestige (M9) thing,
# and the popup says so in one line.
#
# Options come from `StaffSystem.manager_types()` (`manager_types.csv`): name,
# description and the six stats (1..20) in `StaffSystem.STATS` order.
#
# **Prestige mode** (M9, `open(true, current_type)`): opened by the lobby `감독` tab
# after the prestige confirm. Same option cards, but the title / body talk about
# prestige, the current type carries a "현재" chip, and it *is* dismissible — a dim tap
# or the ghost `취소` emits `cancelled` (nothing changes). Confirm emits `chosen`.
#
# Layout follows `ConfirmPopup` (pattern C of `docs/mobile_safe_area.md`): dim =
# whole viewport, white card centred in the safe area so its button stays above
# the gesture zone.

signal chosen(type_id: int)
signal cancelled

const OVERLAY_LAYER: int = 20
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)
const CARD_W: float = 920.0
const CARD_PAD: float = 48.0
const TITLE_H: float = 52.0
const SUB_H: float = 66.0       # two wrapped lines
const NOTE_H: float = 32.0
const OPT_H: float = 268.0
const OPT_GAP: float = 20.0
const OPT_PAD: float = 28.0
const BTN_H: float = 112.0
const BTN_GAP: float = 20.0

var _root: Control = null
var _types: Array = []
var _selected: int = -1
var _options: Array = []        # Panel per type, same order as `_types`
var _confirm_btn: Button = null
var _prestige_mode: bool = false
var _current_type: int = -1


func _init() -> void:
	layer = OVERLAY_LAYER


## `prestige_mode` = M9 re-selection (dismissible); `current_type` gets a "현재" chip.
func open(prestige_mode: bool = false, current_type: int = -1) -> void:
	close()
	_prestige_mode = prestige_mode
	_current_type = current_type
	_types = StaffSystem.manager_types()
	_selected = -1
	_build()


func close() -> void:
	if is_open():
		_root.queue_free()
	_root = null
	_options.clear()
	_confirm_btn = null


func is_open() -> bool:
	return _root != null and is_instance_valid(_root)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	# A Control under a CanvasLayer doesn't resolve anchor presets — size it.
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow; closes only in prestige mode
	add_child(_root)
	if _prestige_mode:
		_root.gui_input.connect(_on_dim_input)

	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.position = Vector2.ZERO
	dim_rect.size = vp
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	var n: int = _types.size()
	var inner_w: float = CARD_W - CARD_PAD * 2.0
	var opts_h: float = float(n) * OPT_H + float(maxi(0, n - 1)) * OPT_GAP
	var card_h: float = CARD_PAD + TITLE_H + 12.0 + SUB_H + NOTE_H + 24.0 + opts_h \
			+ 36.0 + BTN_H + CARD_PAD
	var top: float = ScreenMetrics.top_y()
	var avail: float = ScreenMetrics.bottom_y() - top
	var card_pos := Vector2(ScreenMetrics.center_x() - CARD_W * 0.5,
			top + maxf(0.0, (avail - card_h) * 0.5))
	var card: Panel = OutgameTheme.add_card(_root, card_pos, Vector2(CARD_W, card_h), 24)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var y: float = CARD_PAD
	UiHelpers.mk_label(card, "프레스티지 — 감독 유형 재선택" if _prestige_mode else "감독 유형 선택",
			36, OutgameTheme.TEXT, Vector2(CARD_PAD, y), Vector2(inner_w, TITLE_H))
	y += TITLE_H + 12.0
	var sub_text: String = "첫 런을 시작하기 전에 감독 유형을 고르세요. 스태프가 없는 영역은 감독 스탯으로 운영합니다."
	if _prestige_mode:
		sub_text = "새 감독 유형을 고르면 프레스티지가 끝납니다. 같은 유형을 다시 골라도 됩니다."
	var sub := UiHelpers.mk_label(card, sub_text,
			22, OutgameTheme.TEXT_SUB, Vector2(CARD_PAD, y), Vector2(inner_w, SUB_H))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	y += SUB_H
	UiHelpers.mk_label(card, "Lv1 · 스탯 제거가 초기화됩니다." if _prestige_mode
			else "이후 변경은 프레스티지로만 가능합니다.", 22,
			OutgameTheme.ACCENT_TEXT, Vector2(CARD_PAD, y), Vector2(inner_w, NOTE_H))
	y += NOTE_H + 24.0

	for i in n:
		_options.append(_build_option(card, _types[i], i, Vector2(CARD_PAD, y), inner_w))
		y += OPT_H + OPT_GAP
	y += 36.0 - OPT_GAP

	var confirm_x: float = CARD_PAD
	var confirm_w: float = inner_w
	if _prestige_mode:
		# Dismissible: ghost cancel on the left, 1 : 2 like `ConfirmPopup`.
		var cancel_w: float = floorf((inner_w - BTN_GAP) / 3.0)
		var cancel_btn := Button.new()
		cancel_btn.text = "취소"
		cancel_btn.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(cancel_btn, 30)
		cancel_btn.position = Vector2(CARD_PAD, y)
		cancel_btn.size = Vector2(cancel_w, BTN_H)
		cancel_btn.pressed.connect(cancel)
		card.add_child(cancel_btn)
		confirm_x = CARD_PAD + cancel_w + BTN_GAP
		confirm_w = inner_w - cancel_w - BTN_GAP
	_confirm_btn = Button.new()
	_confirm_btn.text = "유형을 고르세요"
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_primary_button(_confirm_btn, 30)
	_confirm_btn.position = Vector2(confirm_x, y)
	_confirm_btn.size = Vector2(confirm_w, BTN_H)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	card.add_child(_confirm_btn)


## One selectable option: name + description on top, the six stats below.
func _build_option(card: Control, row: Dictionary, idx: int, pos: Vector2,
		w: float) -> Panel:
	var opt := Panel.new()
	opt.position = pos
	opt.size = Vector2(w, OPT_H)
	opt.mouse_filter = Control.MOUSE_FILTER_STOP
	opt.add_theme_stylebox_override("panel", _option_style(false))
	opt.gui_input.connect(_on_option_input.bind(idx))
	card.add_child(opt)

	var inner: float = w - OPT_PAD * 2.0
	UiHelpers.mk_label(opt, String(row.get("name", "")), 32, OutgameTheme.TEXT,
			Vector2(OPT_PAD, 20), Vector2(inner, 44))
	if _prestige_mode and int(row.get("id", -1)) == _current_type:
		OutgameTheme.add_chip(opt, "현재", Vector2(w - OPT_PAD - 90.0, 24), Vector2(90, 36),
				OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT_SUB, 20)
	var desc := UiHelpers.mk_label(opt, String(row.get("desc", "")), 21,
			OutgameTheme.TEXT_SUB, Vector2(OPT_PAD, 68), Vector2(inner, 60))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Six stats in one row — label above, value below.
	var stats: Dictionary = row.get("stats", {})
	var cell_w: float = inner / float(StaffSystem.STATS.size())
	for i in StaffSystem.STATS.size():
		var key: String = String(StaffSystem.STATS[i])
		var x: float = OPT_PAD + float(i) * cell_w
		var cell: Panel = OutgameTheme.add_card(opt, Vector2(x + 4.0, 140),
				Vector2(cell_w - 8.0, 104), 12)
		cell.add_theme_stylebox_override("panel",
				OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 12))
		UiHelpers.mk_label(cell, String(StaffSystem.STAT_LABELS.get(key, key)), 20,
				OutgameTheme.TEXT_SUB, Vector2(0, 10), Vector2(cell_w - 8.0, 28),
				HORIZONTAL_ALIGNMENT_CENTER)
		UiHelpers.mk_label(cell, str(int(stats.get(key, StaffSystem.STAT_MIN))), 36,
				OutgameTheme.TEXT, Vector2(0, 44), Vector2(cell_w - 8.0, 48),
				HORIZONTAL_ALIGNMENT_CENTER)

	for child in opt.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return opt


static func _option_style(selected: bool) -> StyleBoxFlat:
	if selected:
		return OutgameTheme.flat_style(OutgameTheme.ACCENT_DIM, 16, OutgameTheme.ACCENT, 4)
	return OutgameTheme.flat_style(OutgameTheme.SURFACE, 16, OutgameTheme.BORDER_STRONG, 2)


# ── Input ────────────────────────────────────────────────────────────────────
func _on_option_input(event: InputEvent, idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	select(idx)


## Selects option `idx` (also used by headless checks).
func select(idx: int) -> void:
	if idx < 0 or idx >= _types.size():
		return
	if idx != _selected:
		Haptics.play(Haptics.Kind.SELECT)
	_selected = idx
	for i in _options.size():
		(_options[i] as Panel).add_theme_stylebox_override("panel", _option_style(i == idx))
	if _confirm_btn != null:
		_confirm_btn.disabled = false
		_confirm_btn.text = ("%s 감독으로 프레스티지" if _prestige_mode else "%s 감독으로 시작") \
				% String((_types[idx] as Dictionary).get("name", ""))


func _on_confirm() -> void:
	if _selected < 0 or _selected >= _types.size():
		return
	var type_id: int = int((_types[_selected] as Dictionary).get("id", 0))
	close()
	chosen.emit(type_id)


## Prestige mode only — closes without choosing.
func cancel() -> void:
	if not _prestige_mode or not is_open():
		return
	close()
	cancelled.emit()


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		cancel()
