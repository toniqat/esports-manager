class_name ManagerStepView
extends Control

# Run setup step 3 — 감독 (Manager): pick the manager preset for this run (plan §12.0 /
# §12.2). Sits between 팀 and 편성 (`RunSetupScreen.STEPS`).
#
#   status line — "프리셋 n · 보너스 점수 +x" or the validation error (red)
#   scroll: preset chips → stats card (type · Lv · six stats) → TraitPickerView
#   bar: 뒤로 (1) / 다음 (2)
#
# - The **active preset is preselected** (the M1 "nothing preselected" rule is for
#   choice lists; a preset is a loadout you already built).
# - Traits can be swapped in place: edits go to a draft copy of the chosen preset;
#   whenever the draft is valid it is written back and the profile saved (= the
#   preset itself is edited, like in the lobby `감독` tab). An invalid draft (bonus < 0,
#   prestige preset) is never saved and `다음` stays disabled with the reason shown.
# - Specialisation (stat allocation) is edited only in the lobby tab.

signal back_requested
signal next_requested

const PAD_X: float = 24.0
const STATUS_H: float = 44.0
const LIST_BAR_GAP: float = 16.0
const CARD_PAD: float = 28.0

## Chosen preset index (profile `presets`).
var preset_idx: int = -1

var _pm: Node
var _draft: Dictionary = {}
var _scroll: ScrollContainer
var _body: Control
var _status: Label
var _next_btn: Button
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if _built:
		return
	_built = true
	_pm = get_node("/root/ProfileManager")
	_build()
	select_preset(ManagerProgress.active_index(_pm.profile))


## Trait ids of the chosen preset (draft) — the lineup step's cap reads these.
func selected_traits() -> Array:
	var out: Array = []
	for raw in (_draft.get("traits", []) as Array):
		out.append(int(raw))
	return out


## "" when the chosen preset can start a run.
func validation_error() -> String:
	return ManagerProgress.validate_preset(_pm.profile, _draft, _pm.owned_trait_ids())


func select_preset(idx: int) -> void:
	preset_idx = clampi(idx, 0, maxi(0, ManagerProgress.presets(_pm.profile).size() - 1))
	_draft = ManagerProgress.preset_copy(_pm.profile, preset_idx)
	_rebuild()


## Toggle a trait on the chosen preset (also the tap path). "" on success.
func toggle_trait(trait_id: int) -> String:
	if String(_draft.get("kind", "")) == ManagerProgress.KIND_PRESTIGE:
		return "프레스티지 프리셋 — 로비 감독 탭에서 재설정하세요"
	var err: String = ManagerProgress.toggle_trait(_draft, trait_id, _pm.owned_trait_ids())
	if err != "":
		return err
	if validation_error() == "":
		ManagerProgress.store_preset(_pm.profile, preset_idx, _draft)
		var serr: String = _pm.save_profile()
		if serr != "":
			err = "프로필 저장 실패: " + serr
	return err


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var top: float = RunSetupScreen.content_top()
	_status = UiHelpers.mk_label(self, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(PAD_X + 8.0, top), Vector2(ScreenMetrics.vp_w() - PAD_X * 2.0 - 16.0, STATUS_H))
	_status.clip_text = true
	var list_y: float = top + STATUS_H + 8.0
	var list_h: float = OutgameTheme.bottom_bar_top() - LIST_BAR_GAP - list_y
	var sv: Dictionary = OutgameTheme.add_vscroll(self, Vector2(0, list_y),
			Vector2(ScreenMetrics.vp_w(), list_h))
	_scroll = sv["scroll"]
	_body = sv["body"]
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "뒤로", "style": "ghost",   "font": 30, "weight": 1.0},
		{"text": "다음", "style": "primary", "font": 38, "weight": 2.0},
	])
	(bar[0] as Button).pressed.connect(func() -> void: back_requested.emit())
	_next_btn = bar[1]
	_next_btn.pressed.connect(_on_next_pressed)


func _rebuild(status_override: String = "") -> void:
	var keep: int = _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var prof: Dictionary = _pm.profile
	var w: float = ScreenMetrics.vp_w() - PAD_X * 2.0
	var y: float = 4.0
	y += ManagerUi.add_preset_chips(_body, Vector2(PAD_X, y), w, prof, preset_idx,
			_on_chip_pressed) + 24.0

	# Stats card — type · level, the six stats this preset gives.
	var card_h: float = 92.0 + ManagerUi.STAT_CELL_H + CARD_PAD
	var card: Panel = OutgameTheme.add_card(_body, Vector2(PAD_X, y), Vector2(w, card_h), 20)
	var mgr: Dictionary = prof.get("manager", {})
	var trow: Dictionary = StaffSystem.manager_type_row(int(mgr.get("type", 0)))
	UiHelpers.mk_label(card, "%s 감독 · Lv %d" % [String(trow.get("name", "감독")),
			ManagerProgress.level_of(prof)], 30, OutgameTheme.TEXT,
			Vector2(CARD_PAD, 22), Vector2(w - CARD_PAD * 2.0 - 260, 42))
	var all_bonus: int = TraitSystem.sum_p1(selected_traits(), "manager_all")
	var note: String = "특성 보정 전체 %s" % ManagerUi.signed(all_bonus) if all_bonus != 0 \
			else "전문화는 로비 감독 탭에서"
	UiHelpers.mk_label(card, note, 20, OutgameTheme.ACCENT_TEXT if all_bonus != 0
			else OutgameTheme.TEXT_FAINT, Vector2(w - CARD_PAD - 300, 30), Vector2(300, 30),
			HORIZONTAL_ALIGNMENT_RIGHT)
	ManagerUi.add_stat_cells(card, Vector2(CARD_PAD, 80), w - CARD_PAD * 2.0,
			ManagerProgress.preset_stats(prof, _draft), ManagerProgress.base_stats(prof))
	y += card_h + 28.0

	var tv := TraitPickerView.new()
	tv.position = Vector2(PAD_X, y)
	_body.add_child(tv)
	y += tv.build(w, selected_traits(), _pm.owned_trait_ids(), [])
	tv.trait_pressed.connect(_on_trait_pressed)
	_body.custom_minimum_size = Vector2(ScreenMetrics.vp_w(), y + 32.0)
	_scroll.set_deferred("scroll_vertical", keep)
	_refresh_status(status_override)


func _refresh_status(override: String = "") -> void:
	var err: String = validation_error()
	_next_btn.disabled = err != ""
	if override != "":
		_status.text = override
		_status.add_theme_color_override("font_color", OutgameTheme.NEGATIVE)
	elif err != "":
		_status.text = err
		_status.add_theme_color_override("font_color", OutgameTheme.NEGATIVE)
	else:
		var bonus: int = TraitSystem.bonus_points(selected_traits())
		_status.text = "%s · 보너스 점수 %s · 특성을 바꾸면 이 프리셋에 바로 저장됩니다" % [
			ManagerUi.preset_name(preset_idx), ManagerUi.signed(bonus)]
		_status.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)


# ── Input ────────────────────────────────────────────────────────────────────
func _on_chip_pressed(idx: int) -> void:
	if idx == preset_idx:
		return
	Haptics.play(Haptics.Kind.SELECT)
	select_preset(idx)


func _on_trait_pressed(trait_id: int) -> void:
	var err: String = toggle_trait(trait_id)
	if err != "":
		Haptics.play(Haptics.Kind.ERROR)
	else:
		Haptics.play(Haptics.Kind.SELECT)
	_rebuild(err)


func _on_next_pressed() -> void:
	if validation_error() != "":
		return
	next_requested.emit()
