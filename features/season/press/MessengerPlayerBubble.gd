class_name MessengerPlayerBubble
extends MarginContainer

# One manager line (right) in `MessengerView`'s log: amber bubble + tail pointing right.
#
# **Layout lives in `MessengerPlayerBubble.tscn`** — right margin, gap below, bubble width /
# padding, the tail's offset. Height follows the wrapped text. This script only fills the text.
# Create with `MessengerPlayerBubble.create()`.

const SCENE_PATH: String = "res://features/season/press/MessengerPlayerBubble.tscn"


static func create() -> MessengerPlayerBubble:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MessengerPlayerBubble


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


func setup(text: String) -> void:
	%Text.text = text


## F6 단독 실행 미리보기 — 두 줄로 감기는 감독 답 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	setup("쉽지 않겠지만 준비한 게 있습니다. 경기 날 보여 드리겠습니다, 기대하셔도 좋습니다.")
