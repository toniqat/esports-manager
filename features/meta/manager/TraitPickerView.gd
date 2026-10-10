class_name TraitPickerView
extends VBoxContainer

# Trait block shared by the lobby `감독` modal (`ManagerTab`) and the run setup `감독` step:
#
#   특성 (보너스 점수 +3) ························· [교체]   pill turns red when < 0
#   [card][card][card][card][card]   ← equipped only, 5 per row; tap = effect tooltip
#
# **The layout is `UI_Comp_TraitPickerView.tscn`** (+ `UI_Comp_TraitCard.tscn` items, a
# `TraitTooltip` and a `TraitSwapPopup` instance). Hosts place an instance, call `fill()` on every
# change and connect the signals once:
# - `swap_requested` — 교체 tapped; the host checks its own rule (a prestige preset is read-only)
#   and calls `open_swap()`, which opens the swap popup on the last `fill()` lists;
# - `traits_applied(traits)` — the popup closed with a valid, changed set; the host stores + saves.
# There is no equip-count limit — bonus points (≥ 0) are the only cap (plan §12.0).

signal swap_requested
signal traits_applied(traits: Array)

const SCENE_PATH: String = "res://features/meta/manager/UI_Comp_TraitPickerView.tscn"
const CARD_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_TraitCard.tscn")

var _equipped: Array = []
var _owned: Array = []
var _new_ids: Array = []


static func create() -> TraitPickerView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TraitPickerView


## Owned trait ids, positives first then negatives (each in id order) — the pick is
## "what do I want" then "what do I pay with". Shared with `TraitSwapPopup`.
static func sort_owned(owned: Array) -> Array:
	var out: Array = []
	for raw in owned:
		if not TraitSystem.row(int(raw)).is_empty():
			out.append(int(raw))
	out.sort_custom(func(a: int, b: int) -> bool:
		var pa: bool = String(TraitSystem.row(a)["polarity"]) == TraitSystem.POLARITY_POS
		var pb: bool = String(TraitSystem.row(b)["polarity"]) == TraitSystem.POLARITY_POS
		if pa != pb:
			return pa
		return a < b)
	return out


func _ready() -> void:
	%Swap.pressed.connect(func() -> void: swap_requested.emit())
	(%TraitSwapPopup_Swap as TraitSwapPopup).applied.connect(func(t: Array) -> void: traits_applied.emit(t))
	for c in %Cards.get_children():
		_wire(c as TraitCard)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Refills the whole block. `equipped` / `owned` / `new_ids` are Array[int].
func fill(equipped: Array, owned: Array, new_ids: Array) -> void:
	_equipped = equipped.duplicate()
	_owned = owned.duplicate()
	_new_ids = new_ids.duplicate()
	_fill_bonus(equipped)
	var grid: Control = %Cards
	while grid.get_child_count() < equipped.size():
		var c: TraitCard = CARD_SCENE.instantiate()
		grid.add_child(c)
		_wire(c)
	while grid.get_child_count() > equipped.size():
		var extra: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(extra)
		extra.queue_free()
	for i in equipped.size():
		var tid: int = int(equipped[i])
		(grid.get_child(i) as TraitCard).fill(tid, false, new_ids.has(tid))
	grid.visible = not equipped.is_empty()
	(%Empty as Control).visible = equipped.is_empty()


## Opens the swap popup on the lists of the last `fill()`.
func open_swap() -> void:
	(%TraitTooltip_Tip as TraitTooltip).hide_tip()
	(%TraitSwapPopup_Swap as TraitSwapPopup).open(_equipped, _owned, _new_ids)


func _wire(card: TraitCard) -> void:
	card.pressed.connect(func() -> void:
		Haptics.play(Haptics.Kind.SELECT)
		(%TraitTooltip_Tip as TraitTooltip).show_for(card, card.trait_id))


## The bonus points of the equipped set in the head pill — red pill + text below 0.
func _fill_bonus(equipped: Array) -> void:
	var bonus: int = TraitSystem.bonus_points(equipped)
	(%BonusPill as Control).theme_type_variation = \
			&"TraitPickerBonusPillBad" if bonus < 0 else &"TraitPickerBonusPill"
	var bl: Label = %BonusText
	bl.text = Loc.t(L.MANAGER_TRAIT_PICKER_BONUS_PILL, {"n": ManagerUi.signed(bonus)})
	if bonus < 0:
		bl.theme_type_variation = &"NegativeLabel"
	elif bonus > 0:
		bl.theme_type_variation = &"PositiveLabel"
	else:
		bl.theme_type_variation = &"CaptionLabel"


## F6 단독 실행 미리보기 — 손으로 적은 장착 · 보유 목록 (`resources/UiPreview.gd`):
## 긍정 2 · 부정 1 장착, NEW 하나. 교체 → 교체 팝업, 적용하면 다시 채운다(저장 없음).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var owned: Array = [1, 2, 3, 6, 11, 15, 16, 23]
	fill([1, 3, 15], owned, [2])
	swap_requested.connect(open_swap)
	traits_applied.connect(func(t: Array) -> void: fill(t, owned, [2]))
