class_name ManagerStepView
extends Control

# Run setup step 3 — 감독 (Manager): pick the manager preset for this run (plan §12.0 /
# §12.2). Sits between 팀 and 편성 (`RunSetupScreen.STEPS`).
#
#   scroll (to the screen bottom, under the capsules): error line (red, only on an error) →
#   preset chips → stats card (Lv · six stats) → TraitPickerView
#   bar: 뒤로 (1) / 다음 (2)
#
# **The layout is `UI_View_ManagerStepView.tscn`** (scroll, error slot, chips / stats card / traits
# slots, bar shield, bar fade, bottom bar). Construct with `ManagerStepView.create()`. Code fills
# the texts, shows / hides the error line and the `manager_all` note, refills the shared scenes placed in it (`ManagerPresetChips` · `TraitPickerView`, from
# `features/meta/manager/`) and rebuilds the code-built stat cells (`ManagerUi.add_stat_cells`).
#
# - The **active preset is preselected** (the M1 "nothing preselected" rule is for
#   choice lists; a preset is a loadout you already built).
# - Traits can be swapped in place: `교체` opens the shared swap popup
#   (`TraitPickerView.open_swap`); a valid changed set comes back through `traits_applied` and is
#   written to the chosen preset and saved (= the preset itself is edited, like in the lobby
#   `감독` modal). A prestige preset can't be swapped; an invalid preset is never saved and `다음`
#   stays disabled with the reason shown.
# - Specialisation (stat allocation) is edited only in the lobby tab.

signal back_requested
signal next_requested

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_ManagerStepView.tscn"

## Chosen preset index (profile `presets`).
var preset_idx: int = -1

var _pm: Node
var _draft: Dictionary = {}
var _built: bool = false
## F6 미리보기 — 특성을 바꿔도 프로필을 저장하지 않는다(메모리 사본만 바뀐다).
var _preview: bool = false


static func create() -> ManagerStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerStepView


func _ready() -> void:
	if _built:
		return
	_built = true
	_pm = get_node("/root/ProfileManager")
	OutgameTheme.fit_bottom_bar(%Bar, %Safe)
	# The body runs to the screen bottom under the capsules (visible, not tappable).
	OutgameTheme.fit_bar_shield(%BarShield)
	(%Scroll as Control).offset_bottom = OutgameTheme.bottom_inset()
	(%BottomGap as Control).custom_minimum_size.y = OutgameTheme.bar_scroll_pad()
	OutgameTheme.fit_bar_scroll(%Scroll)
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	(%FloatingBarButton_Back as Button).pressed.connect(func() -> void: back_requested.emit())
	(%FloatingBarButton_Next as Button).pressed.connect(_on_next_pressed)
	(%ManagerPresetChips_Chips as ManagerPresetChips).chip_pressed.connect(_on_chip_pressed)
	var tv: TraitPickerView = %TraitPickerView_Traits
	tv.swap_requested.connect(_on_swap_requested)
	tv.traits_applied.connect(_on_traits_applied)
	select_preset(ManagerProgress.active_index(_pm.profile))
	if UiPreview.is_standalone(self):
		_fill_preview()


## Trait ids of the chosen preset (draft) — the lineup step's cap reads these.
func selected_traits() -> Array:
	var out: Array = []
	for raw in (_draft.get("traits", []) as Array):
		out.append(int(raw))
	return out


## "" when the chosen preset can start a run.
func validation_error() -> String:
	return ManagerProgress.validate_preset(_pm.profile, _draft, _pm.owned_trait_ids())


## The 팀 step's choice — shown as the banner strip at the top of the body (`RunSetupScreen`
## sets it on every entry to this step).
func set_team(team_id: int) -> void:
	(%RunTeamBanner_Team as RunTeamBanner).fill(team_id)


func select_preset(idx: int) -> void:
	preset_idx = clampi(idx, 0, maxi(0, ManagerProgress.presets(_pm.profile).size() - 1))
	_draft = ManagerProgress.preset_copy(_pm.profile, preset_idx)
	_rebuild()


## Replace the chosen preset's trait set (the swap popup's result). "" on success.
func set_traits(traits: Array) -> String:
	if String(_draft.get("kind", "")) == ManagerProgress.KIND_PRESTIGE:
		return Loc.t(L.RUN_SETUP_MANAGER_PRESTIGE_LOCKED)
	_draft["traits"] = traits.duplicate()
	var err: String = ""
	if validation_error() == "" and not _preview:
		ManagerProgress.store_preset(_pm.profile, preset_idx, _draft)
		var serr: String = _pm.save_profile()
		if serr != "":
			err = Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr})
	return err


# ── Fill ─────────────────────────────────────────────────────────────────────
# The layout (error slot, scroll, chips, stats card, traits, bar) is the scene. The chips
# and the trait block are shared scenes (also in the lobby 감독 tab) refilled on every change;
# the six stat cells are built by `ManagerUi.add_stat_cells` into `%Cells` (height it returns).
func _rebuild(status_override: String = "") -> void:
	var scroll: ScrollContainer = %Scroll
	var keep: int = scroll.scroll_vertical
	var cells: Control = %Cells
	for c in cells.get_children():
		cells.remove_child(c)
		c.queue_free()
	var prof: Dictionary = _pm.profile
	(%ManagerPresetChips_Chips as ManagerPresetChips).fill(prof, preset_idx)

	# Stats card — level (no manager type here), the six stats this preset gives.
	(%CardTitle as Label).text = Loc.t(L.RUN_SETUP_LEVEL_N, {"n": ManagerProgress.level_of(prof)})
	var all_bonus: int = TraitSystem.sum_p1(selected_traits(), "manager_all")
	var note: Label = %CardNote
	note.visible = all_bonus != 0
	if all_bonus != 0:
		note.text = Loc.t(L.RUN_SETUP_MANAGER_ALL_BONUS, {"value": ManagerUi.signed(all_bonus)})
	var cells_w: float = cells.size.x if cells.size.x > 0.0 else ScreenMetrics.vp_w() - 48.0 - 56.0
	cells.custom_minimum_size.y = ManagerUi.add_stat_cells(cells, Vector2.ZERO, cells_w,
			ManagerProgress.preset_stats(prof, _draft), ManagerProgress.base_stats(prof))

	(%TraitPickerView_Traits as TraitPickerView).fill(selected_traits(), _pm.owned_trait_ids(), [])
	scroll.set_deferred("scroll_vertical", keep)
	_refresh_status(status_override)


func _refresh_status(override: String = "") -> void:
	var err: String = validation_error()
	(%FloatingBarButton_Next as Button).disabled = err != ""
	# Red error line only — nothing is shown while the preset is fine (the body starts higher).
	var shown: String = override if override != "" else err
	(%Status as Label).text = shown
	(%StatusPad as Control).visible = shown != ""


# ── Input ────────────────────────────────────────────────────────────────────
func _on_chip_pressed(idx: int) -> void:
	if idx == preset_idx:
		return
	Haptics.play(Haptics.Kind.SELECT)
	select_preset(idx)


func _on_swap_requested() -> void:
	if String(_draft.get("kind", "")) == ManagerProgress.KIND_PRESTIGE:
		Haptics.play(Haptics.Kind.ERROR)
		_refresh_status(Loc.t(L.RUN_SETUP_MANAGER_PRESTIGE_LOCKED))
		return
	(%TraitPickerView_Traits as TraitPickerView).open_swap()


func _on_traits_applied(traits: Array) -> void:
	var err: String = set_traits(traits)
	Haptics.play(Haptics.Kind.ERROR if err != "" else Haptics.Kind.SUCCESS)
	_rebuild(err)


func _on_next_pressed() -> void:
	if validation_error() != "":
		return
	next_requested.emit()


## F6 단독 실행 미리보기 — 실제 프로필(`ProfileManager`)의 활성 프리셋이 이미 골라져
## 있다 (`resources/UiPreview.gd`). 특성 탭은 화면 사본만 바꾸고 저장하지 않는다.
func _fill_preview() -> void:
	_preview = true
	UiPreview.stage(self)
	UiPreview.trace(back_requested)
	UiPreview.trace(next_requested)
	set_team(3)
