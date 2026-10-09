class_name StaffThumb
extends Button

# One person as a thumbnail card — portrait (`StaffImages`), name, a sub line and a value line.
# Shared by the facility occupant picker (`facility/OccupantPicker`) and the personnel office
# grids. **Layout lives in `UI_Comp_StaffThumb.tscn`**; the whole card is the tap target
# (`pressed`). `who` = `"manager"` or a staff id string, kept as metadata for the caller.

const SCENE_PATH: String = "res://features/season/staff/UI_Comp_StaffThumb.tscn"

## `"manager"` / staff id string of the person shown ("" before `show_person`).
var who: String = ""


## Instantiates the scene. `StaffThumb.new()` is an empty button — don't use it.
static func create() -> StaffThumb:
	return (load(SCENE_PATH) as PackedScene).instantiate() as StaffThumb


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## Fills the card. `sub_bad` paints the sub line red (a block reason); `on` = selected look.
func show_person(person: String, display_name: String, sub: String, value: String,
		on: bool = false, sub_bad: bool = false) -> void:
	who = person
	(%Portrait as TextureRect).texture = StaffImages.portrait(person)
	%Name.text = display_name
	var sub_l: Label = %Sub
	sub_l.text = sub
	sub_l.visible = sub != ""
	if sub_bad:
		sub_l.add_theme_color_override(&"font_color", OutgameTheme.NEGATIVE)
	else:
		sub_l.remove_theme_color_override(&"font_color")
	var value_l: Label = %Value
	value_l.text = value
	value_l.visible = value != ""
	set_on(on)


func set_on(on: bool) -> void:
	theme_type_variation = &"SelectableCardButtonOn" if on else &"SelectableCardButton"


## F6 단독 실행 미리보기 — 감독 카드(선택된 모양).
func _fill_preview() -> void:
	UiPreview.stage(self)
	show_person(StaffImages.MANAGER, Loc.t(L.TERM_PERSON_MANAGER), "", "16", true)
