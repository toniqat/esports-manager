class_name ManagerPresetChips
extends GridContainer

# Preset chips of the lobby `감독` tab (`ManagerTab`) and the run setup `감독` step
# (`run_setup/ManagerStepView`): one `ManagerPresetChip.tscn` per profile preset.
# Chip = name + status line: ● 사용 중 (active) / 재설정 필요 (prestige kind) / 특성 n.
# The selected chip gets the amber frame (`SelectableCardButtonOn`).
#
# **The layout is `ManagerPresetChips.tscn`** (5-column grid, gap 12) + the chip item scene.
# Hosts place an instance of the scene, call `fill()` on every change and connect
# `chip_pressed` once. The grid sizes itself — no width / height bookkeeping in the host.

signal chip_pressed(idx: int)

const SCENE_PATH: String = "res://features/meta/manager/ManagerPresetChips.tscn"
const CHIP_SCENE: PackedScene = preload("res://features/meta/manager/ManagerPresetChip.tscn")


static func create() -> ManagerPresetChips:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerPresetChips


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## One chip per `ManagerProgress.presets(profile)`; `selected` gets the amber frame.
func fill(profile: Dictionary, selected: int) -> void:
	var ps: Array = ManagerProgress.presets(profile)
	var active: int = ManagerProgress.active_index(profile)
	while get_child_count() < ps.size():
		var chip: Button = CHIP_SCENE.instantiate()
		chip.pressed.connect(func() -> void: chip_pressed.emit(chip.get_index()))
		add_child(chip)
	while get_child_count() > ps.size():
		var extra: Node = get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()
	for i in ps.size():
		var p: Dictionary = ps[i]
		var chip: Button = get_child(i)
		var on: bool = i == selected
		chip.theme_type_variation = &"SelectableCardButtonOn" if on else &"SelectableCardButton"
		var name_lbl: Label = chip.get_node("%Name")
		name_lbl.text = ManagerUi.preset_name(i)
		name_lbl.theme_type_variation = &"BodyLabel" if on else &"SubLabel"
		var st: Label = chip.get_node("%Status")
		if String(p.get("kind", ManagerProgress.KIND_NORMAL)) == ManagerProgress.KIND_PRESTIGE:
			st.text = "재설정 필요"
			st.theme_type_variation = &"NegativeLabel"
		elif i == active:
			st.text = "● 사용 중"
			st.theme_type_variation = &"AccentLabel"
		else:
			st.text = "특성 %d" % (p.get("traits", []) as Array).size()
			st.theme_type_variation = &"FaintLabel"


## F6 단독 실행 미리보기 — 실제 프로필(`ProfileManager`)의 프리셋, 사용 중 프리셋 선택
## (`resources/UiPreview.gd`). 칩을 누르면 고른 칸만 옮긴다(저장 없음).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var prof: Dictionary = get_node("/root/ProfileManager").profile
	fill(prof, ManagerProgress.active_index(prof))
	chip_pressed.connect(func(idx: int) -> void: fill(prof, idx))
