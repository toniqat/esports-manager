class_name TraitSwapPopup
extends CanvasLayer

# 특성 교체 modal — opened by `TraitPickerView`'s 교체 button (lobby 감독 modal · run setup 감독 step).
#
#   ┌ 특성 교체                                         ┐  sheet drops from the top edge
#   │ 보너스 점수 +3 ·························· rule line │  red when the set's bonus < 0
#   │ 장착한 특성 n   [card][card]…   (5 per row)        │
#   │ 보유 특성 n     [card][card]…   (equipped = amber)  │
#   └───────────────────────────────────────────────────┘
#                                             ( X 닫기 )   floating close capsule
#
# A card tap opens `TraitTooltip` (effect text) with 장착 / 해제; the action toggles the trait on
# the popup's own copy (`ManagerProgress.toggle_trait` — no count limit, only bonus points cap a
# set). Closing (capsule / dim):
# - bonus ≥ 0 and the set changed → `applied(traits)`; the host stores + saves it;
# - bonus < 0 → danger confirm "버리고 닫기" (cancel = keep editing) — an invalid set is never applied;
# - unchanged → just closes. `closed` fires every time the popup goes away.
#
# Layout lives in `UI_View_TraitSwapPopup.tscn`; build with `create()`. A CanvasLayer (20) so it sits
# above both hosts; the tooltip (25) and the discard confirm (30) stack above it.

signal applied(traits: Array)
signal closed

const SCENE_PATH: String = "res://features/meta/manager/UI_View_TraitSwapPopup.tscn"
const CARD_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_TraitCard.tscn")

var _traits: Array = []
var _orig: Array = []
var _owned: Array = []
var _new_ids: Array = []
var _sheet_rest: float = 0.0
var _anim: Tween
var _confirm: ConfirmPopup = null


static func create() -> TraitSwapPopup:
	var p: TraitSwapPopup = (load(SCENE_PATH) as PackedScene).instantiate()
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(request_close)
	%FloatingCloseButton_Close.pressed.connect(request_close)
	(%TraitTooltip_Tip as TraitTooltip).action_pressed.connect(_toggle)
	for grid in [%EquippedGrid, %OwnedGrid]:
		for c in (grid as Node).get_children():
			_wire(c as TraitCard)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `equipped` / `owned` / `new_ids` = Array[int]; the popup edits its own copy.
func open(equipped: Array, owned: Array, new_ids: Array = []) -> void:
	_traits = _ints(equipped)
	_orig = _traits.duplicate()
	_owned = _ints(owned)
	_new_ids = _ints(new_ids)
	_fit_safe_area()
	_fill()
	(%Scroll as ScrollContainer).scroll_vertical = 0
	visible = true
	_anim = UiHelpers.slide_top_sheet(self, _anim, %Root, %Sheet, _sheet_rest, true)


func is_open() -> bool:
	return visible


## Capsule / dim. Applies a valid changed set, asks before dropping an invalid one.
func request_close() -> void:
	if not visible:
		return
	(%TraitTooltip_Tip as TraitTooltip).hide_tip()
	if _traits == _orig:
		_close()
	elif TraitSystem.bonus_points(_traits) < 0:
		Haptics.play(Haptics.Kind.WARNING)
		_open_discard_confirm()
	else:
		applied.emit(_traits.duplicate())
		_close()


func _close() -> void:
	_anim = UiHelpers.slide_top_sheet(self, _anim, %Root, %Sheet, _sheet_rest, false,
			func() -> void: visible = false)
	closed.emit()


func _open_discard_confirm() -> void:
	if _confirm == null:
		_confirm = ConfirmPopup.create()
		add_child(_confirm)
		_confirm.layer = 30
		_confirm.confirmed.connect(_close)
	_confirm.open(Loc.t(L.MANAGER_TRAIT_SWAP_BAD_TITLE), Loc.t(L.MANAGER_TRAIT_SWAP_BAD_BODY),
			Loc.t(L.MANAGER_TRAIT_SWAP_KEEP_EDITING), Loc.t(L.MANAGER_TRAIT_SWAP_DISCARD), true)


## The layer is not under the lobby's notch indent: the sheet covers the notch band, its content
## starts below it, and it stops 16 px above the floating close capsule.
func _fit_safe_area() -> void:
	(%Content as Control).offset_top = ScreenMetrics.top_y()
	var close_top: float = UiHelpers.place_floating_close(%FloatingCloseButton_Close)
	var sheet: Control = %Sheet
	sheet.offset_bottom = close_top - 16.0
	_sheet_rest = sheet.offset_top


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill() -> void:
	var bonus: int = TraitSystem.bonus_points(_traits)
	var bad: bool = bonus < 0
	(%Gauge as Control).theme_type_variation = &"TraitPickerGaugeBad" if bad else &"TraitPickerGauge"
	var bl: Label = %Bonus
	bl.text = ManagerUi.signed(bonus)
	bl.theme_type_variation = &"NegativeLabel" if bonus < 0 \
			else (&"PositiveLabel" if bonus > 0 else &"CaptionLabel")
	var rule: Label = %Rule
	rule.text = Loc.t(L.MANAGER_TRAIT_PICKER_RULE_BAD) if bad else Loc.t(L.MANAGER_TRAIT_PICKER_RULE_OK)
	rule.theme_type_variation = &"NegativeLabel" if bad else &"FaintLabel"

	(%EquippedTitle as Label).text = Loc.t(L.MANAGER_TRAIT_SWAP_EQUIPPED_TITLE, {"n": _traits.size()})
	(%EquippedEmpty as Control).visible = _traits.is_empty()
	_sync_cards(%EquippedGrid, _traits, false)
	var owned_sorted: Array = TraitPickerView.sort_owned(_owned)
	(%OwnedTitle as Label).text = Loc.t(L.MANAGER_TRAIT_SWAP_OWNED_TITLE, {"n": owned_sorted.size()})
	_sync_cards(%OwnedGrid, owned_sorted, true)


## Reuses the grid's cards (the scene's previews first), instantiates / frees the rest.
func _sync_cards(grid: Control, ids: Array, mark_equipped: bool) -> void:
	while grid.get_child_count() < ids.size():
		var c: TraitCard = CARD_SCENE.instantiate()
		grid.add_child(c)
		_wire(c)
	while grid.get_child_count() > ids.size():
		var extra: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(extra)
		extra.queue_free()
	for i in ids.size():
		var tid: int = int(ids[i])
		(grid.get_child(i) as TraitCard).fill(tid, mark_equipped and _traits.has(tid), _new_ids.has(tid))


func _wire(card: TraitCard) -> void:
	card.pressed.connect(func() -> void: _on_card(card))


func _on_card(card: TraitCard) -> void:
	if (%DragScroll as DragScroll).moved:
		return
	Haptics.play(Haptics.Kind.SELECT)
	var on: bool = _traits.has(card.trait_id)
	(%TraitTooltip_Tip as TraitTooltip).show_for(card, card.trait_id,
			Loc.t(L.MANAGER_TRAIT_SWAP_UNEQUIP if on else L.MANAGER_TRAIT_SWAP_EQUIP), not on)


func _toggle(tid: int) -> void:
	var p: Dictionary = {"traits": _traits}
	var err: String = ManagerProgress.toggle_trait(p, tid, _owned)
	if err != "":
		Haptics.play(Haptics.Kind.ERROR)
		return
	_traits = _ints(p["traits"])
	Haptics.play(Haptics.Kind.SELECT)
	_fill()


static func _ints(a: Array) -> Array:
	var out: Array = []
	for raw in a:
		out.append(int(raw))
	return out


## F6 단독 실행 미리보기 — 손으로 적은 장착 · 보유 목록, NEW 하나. 닫으면 적용 / 닫힘만 출력.
func _fill_preview() -> void:
	UiPreview.trace(applied)
	UiPreview.trace(closed)
	open([1, 3, 15], [1, 2, 3, 6, 11, 15, 16, 23], [2])
