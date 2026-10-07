class_name MessengerNoteChip
extends MarginContainer

# One centred effect / verdict chip under the outcome in `MessengerView` (`팀 신뢰 +3`,
# `멘탈 판정 실패`).
#
# **Layout lives in `UI_Comp_MessengerNoteChip.tscn`** — pill height, padding, gap below; the chip is as
# wide as its text. The scene shows the good look (`AccentChip` + `AccentLabel`); a bad note
# (failed check) is a sunk pill with grey text: `%Chip` switches to the
# `MessengerNoteChipMuted` variation and the label to `CaptionLabel`.
# Create with `MessengerNoteChip.create()`.

const SCENE_PATH: String = "res://features/season/press/UI_Comp_MessengerNoteChip.tscn"


static func create() -> MessengerNoteChip:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MessengerNoteChip


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `good` = gain / passed check (amber tint); false = failed check (sunk grey).
func setup(text: String, good: bool) -> void:
	%Text.text = text
	if good:
		return
	%Chip.theme_type_variation = &"MessengerNoteChipMuted"
	%Text.theme_type_variation = &"CaptionLabel"


## F6 단독 실행 미리보기 — 실패 판정 칩 (좋은 칩은 씬 기본 모양) (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	setup("멘탈 판정 실패", false)
