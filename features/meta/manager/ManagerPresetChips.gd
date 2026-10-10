class_name ManagerPresetChips
extends HBoxContainer

# Preset capsule of the lobby `감독` modal (`ManagerTab`) and the run setup `감독` step
# (`run_setup/ManagerStepView`): a dark pill, right-aligned in its row, with one cell per profile
# preset captioned by a Roman numeral (I, II, … — `ManagerUi.roman`). A white selector pill slides
# under the chosen cell (same look as the lobby nav). A prestige preset that still needs a reset
# shows its numeral in red.
#
# **The layout is `UI_Comp_ManagerPresetChips.tscn`** (+ the cell scene `UI_Comp_ManagerPresetChip.tscn`).
# Hosts place an instance, call `fill()` on every change and connect `chip_pressed` once. The
# capsule sizes itself (cells × `CELL_W`) — no width / height bookkeeping in the host.

signal chip_pressed(idx: int)

const SCENE_PATH: String = "res://features/meta/manager/UI_Comp_ManagerPresetChips.tscn"
const CHIP_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_ManagerPresetChip.tscn")

const CELL_W: float = 96.0
const CELL_H: float = 72.0
const PAD: float = 8.0          # capsule edge → cells (scene `%Cells` offsets)
const SLIDE_SEC: float = 0.22

var _selected: int = -1
var _anim: Tween


static func create() -> ManagerPresetChips:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerPresetChips


func _ready() -> void:
	# The scene's preview cells get the same tap wiring as code-made ones.
	for c in %Cells.get_children():
		_wire(c as Button)
	if UiPreview.is_standalone(self):
		_fill_preview()


## One cell per `ManagerProgress.presets(profile)`; `selected` sits on the selector pill.
func fill(profile: Dictionary, selected: int) -> void:
	var ps: Array = ManagerProgress.presets(profile)
	var cells: Control = %Cells
	while cells.get_child_count() < ps.size():
		var cell: Button = CHIP_SCENE.instantiate()
		cells.add_child(cell)
		_wire(cell)
	while cells.get_child_count() > ps.size():
		var extra: Node = cells.get_child(cells.get_child_count() - 1)
		cells.remove_child(extra)
		extra.queue_free()
	(%Capsule as Control).custom_minimum_size = Vector2(ps.size() * CELL_W + PAD * 2.0, CELL_H + PAD * 2.0)
	for i in ps.size():
		var cell: Button = cells.get_child(i)
		cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
		cell.text = ManagerUi.roman(i + 1)
		cell.theme_type_variation = &"ManagerPresetCellOn" if i == selected else &"ManagerPresetCell"
		if String((ps[i] as Dictionary).get("kind", ManagerProgress.KIND_NORMAL)) == ManagerProgress.KIND_PRESTIGE:
			for c in OutgameTheme.BUTTON_FONT_COLORS:
				cell.add_theme_color_override(c, OutgameTheme.NEGATIVE)
		else:
			for c in OutgameTheme.BUTTON_FONT_COLORS:
				cell.remove_theme_color_override(c)
	_move_selector(selected, _selected >= 0 and selected != _selected and is_visible_in_tree())
	_selected = selected


func _wire(cell: Button) -> void:
	cell.pressed.connect(func() -> void: chip_pressed.emit(cell.get_index()))


## Cell `i` sits at PAD + i × CELL_W inside the capsule (separation 0) — no layout pass needed.
func _move_selector(i: int, animate: bool) -> void:
	var sel: Panel = %Selector
	sel.visible = i >= 0
	if i < 0:
		return
	sel.size = Vector2(CELL_W, CELL_H)
	var to := Vector2(PAD + i * CELL_W, PAD)
	if _anim != null:
		_anim.kill()
	if not animate:
		sel.position = to
		return
	_anim = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim.tween_property(sel, "position", to, SLIDE_SEC)


## F6 단독 실행 미리보기 — 실제 프로필(`ProfileManager`)의 프리셋, 사용 중 프리셋 선택
## (`resources/UiPreview.gd`). 칸을 누르면 선택 알약만 옮긴다(저장 없음).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var prof: Dictionary = get_node("/root/ProfileManager").profile
	fill(prof, ManagerProgress.active_index(prof))
	chip_pressed.connect(func(idx: int) -> void: fill(prof, idx))
