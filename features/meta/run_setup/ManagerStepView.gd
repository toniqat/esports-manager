class_name ManagerStepView
extends Control

# Run setup step 3 — 감독 (Manager): pick the manager preset for this run (plan §12.0 /
# §12.2). Sits between 팀 and 편성 (`RunSetupScreen.STEPS`).
#
#   status line — "프리셋 n · 보너스 점수 +x" or the validation error (red)
#   scroll: preset chips → stats card (type · Lv · six stats) → TraitPickerView
#   bar: 뒤로 (1) / 다음 (2)
#
# **The layout is `ManagerStepView.tscn`** (status line, scroll, chips / stats card / traits
# slots, bottom bar). Construct with `ManagerStepView.create()`. Code fills the texts and
# rebuilds the shared-module content (`ManagerUi` chips + stat cells, `TraitPickerView`)
# into the slots.
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

const SCENE_PATH: String = "res://features/meta/run_setup/ManagerStepView.tscn"

## Chosen preset index (profile `presets`).
var preset_idx: int = -1

var _pm: Node
var _draft: Dictionary = {}
var _built: bool = false


static func create() -> ManagerStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerStepView


func _ready() -> void:
	if _built:
		return
	_built = true
	_pm = get_node("/root/ProfileManager")
	RunSetupScreen.fit_insets(%Safe, %Bar)
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	(%Back as Button).pressed.connect(func() -> void: back_requested.emit())
	(%Next as Button).pressed.connect(_on_next_pressed)
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


# ── Fill ─────────────────────────────────────────────────────────────────────
# The layout (status line, scroll, chips slot, stats card, traits slot, bar) is the scene.
# The chips, the six stat cells and the trait block are built by shared modules
# (`ManagerUi`, `TraitPickerView` — also used by the lobby 감독 tab) into their slots and
# rebuilt on every change; each slot's height is what that builder returns.
func _rebuild(status_override: String = "") -> void:
	var scroll: ScrollContainer = %Scroll
	var keep: int = scroll.scroll_vertical
	var chips: Control = %Chips
	var cells: Control = %Cells
	var traits: Control = %Traits
	for slot: Control in [chips, cells, traits]:
		for c in slot.get_children():
			slot.remove_child(c)
			c.queue_free()
	var prof: Dictionary = _pm.profile
	var w: float = chips.size.x if chips.size.x > 0.0 else ScreenMetrics.vp_w() - 48.0
	chips.custom_minimum_size.y = ManagerUi.add_preset_chips(chips, Vector2.ZERO, w, prof,
			preset_idx, _on_chip_pressed)

	# Stats card — type · level, the six stats this preset gives.
	var mgr: Dictionary = prof.get("manager", {})
	var trow: Dictionary = StaffSystem.manager_type_row(int(mgr.get("type", 0)))
	(%CardTitle as Label).text = "%s 감독 · Lv %d" % [String(trow.get("name", "감독")),
			ManagerProgress.level_of(prof)]
	var all_bonus: int = TraitSystem.sum_p1(selected_traits(), "manager_all")
	var note: Label = %CardNote
	if all_bonus != 0:
		note.text = "특성 보정 전체 %s" % ManagerUi.signed(all_bonus)
		note.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT)
	else:
		note.text = "전문화는 로비 감독 탭에서"
		note.remove_theme_color_override("font_color")
	var cells_w: float = cells.size.x if cells.size.x > 0.0 else w - 56.0
	cells.custom_minimum_size.y = ManagerUi.add_stat_cells(cells, Vector2.ZERO, cells_w,
			ManagerProgress.preset_stats(prof, _draft), ManagerProgress.base_stats(prof))

	var tv := TraitPickerView.new()
	traits.add_child(tv)
	traits.custom_minimum_size.y = tv.build(w, selected_traits(), _pm.owned_trait_ids(), [])
	tv.trait_pressed.connect(_on_trait_pressed)
	scroll.set_deferred("scroll_vertical", keep)
	_refresh_status(status_override)


func _refresh_status(override: String = "") -> void:
	var err: String = validation_error()
	(%Next as Button).disabled = err != ""
	var status: Label = %Status
	if override != "":
		status.text = override
		status.add_theme_color_override("font_color", OutgameTheme.NEGATIVE)
	elif err != "":
		status.text = err
		status.add_theme_color_override("font_color", OutgameTheme.NEGATIVE)
	else:
		var bonus: int = TraitSystem.bonus_points(selected_traits())
		status.text = "%s · 보너스 점수 %s · 특성을 바꾸면 이 프리셋에 바로 저장됩니다" % [
			ManagerUi.preset_name(preset_idx), ManagerUi.signed(bonus)]
		status.remove_theme_color_override("font_color")


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
