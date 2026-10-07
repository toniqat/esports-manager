class_name BanPickBanChip
extends Panel

# One **ban chip** of a team block's ban row — a small square mech portrait (dimmed by
# `BAN_TINT`) with a red ✕. Empty = only the frame. Layout + style in `UI_Comp_BanPickBanChip.tscn`;
# `BanPickController._refresh_side_block` sets the texture / ✕ (and the AI's faint preview).

var art: TextureRect = null
var x_label: Label = null


func _ready() -> void:
	art = %Art
	x_label = %XLabel
	if UiPreview.is_standalone(self):
		_fill_preview()


## F6 단독 실행 미리보기 — 밴된 칩 한 개(Wrecker, 흐린 그림 + ✕). 채우는 법은
## `BanPickController._refresh_side_block` 과 같다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	art.modulate = Color(0.42, 0.42, 0.46, 1.0)
	art.texture = MechImages.portrait_for(7)
	x_label.text = "✕"
