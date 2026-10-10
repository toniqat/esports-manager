class_name TraitCard
extends Button

# One manager trait as a card — `TraitPickerView` (equipped grid) and `TraitSwapPopup`
# (equipped / owned grids). Thumb = rounded square in the rarity colour (`TraitUi.rarity_color`)
# with the trait's icon from `resources/images/skill/` (`SkillImages.trait_icon_for`); the bonus
# score sits in the thumb's bottom-right plate ("−3" = consumes, "+2" = provides; colour =
# polarity); name below. The effect text is not on the card — hosts open `TraitTooltip` on tap.
#
# Layout lives in `UI_Comp_TraitCard.tscn`; build with `create()`. Fill with `fill()`.

const SCENE_PATH: String = "res://features/meta/manager/UI_Comp_TraitCard.tscn"

var trait_id: int = 0


static func create() -> TraitCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TraitCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `marked` = amber frame (equipped, in the swap popup); `is_new` = NEW chip.
func fill(tid: int, marked: bool = false, is_new: bool = false) -> void:
	trait_id = tid
	var r: Dictionary = TraitSystem.row(tid)
	var thumb := OutgameTheme.variation_box(&"TraitCardThumb")
	thumb.bg_color = TraitUi.rarity_color(int(r.get("rarity", 0)))
	(%Thumb as Panel).add_theme_stylebox_override("panel", thumb)
	(%Icon as TextureRect).texture = SkillImages.trait_icon_for(tid)
	var score: Label = %ScoreText
	score.text = score_text(r)
	score.add_theme_color_override("font_color", score_color(r))
	(%Name as Label).text = TraitSystem.name_of(tid)
	(%New as Control).visible = is_new
	theme_type_variation = &"TraitCardOn" if marked else &"TraitCard"


## "−3" for a "+" trait (consumes bonus points), "+2" for a "−" trait (provides them).
static func score_text(r: Dictionary) -> String:
	var c: int = int(r.get("bonus_cost", 0))
	return ("−%d" % c) if _is_pos(r) else ("+%d" % c)


## Polarity colour, lifted so it reads on the dark score plate.
static func score_color(r: Dictionary) -> Color:
	return (OutgameTheme.POSITIVE if _is_pos(r) else OutgameTheme.NEGATIVE).lightened(0.3)


static func _is_pos(r: Dictionary) -> bool:
	return String(r.get("polarity", TraitSystem.POLARITY_POS)) == TraitSystem.POLARITY_POS


## F6 단독 실행 미리보기 — 특성 2번(고급 · 긍정), NEW 표시.
func _fill_preview() -> void:
	UiPreview.stage(self)
	fill(2, false, true)
