class_name MessengerPlayerBubble
extends MarginContainer

# One manager line (right) in `MessengerView`'s log: amber bubble + tail pointing right.
#
# **Layout lives in `UI_Comp_MessengerPlayerBubble.tscn`** — right margin, gap below, bubble width /
# padding, the tail's offset. Height follows the wrapped text. This script only fills the text.
# Create with `MessengerPlayerBubble.create()`.

const SCENE_PATH: String = "res://features/season/press/UI_Comp_MessengerPlayerBubble.tscn"


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
	# 홀로 선 루트는 첫 배치(줄바꿈 글 폭 0 → 아주 긴 높이)만큼 커진 채 줄지 않는다 —
	# 한 프레임 뒤 최소 크기로 되돌린다(로그 안에서는 VBox 가 매번 크기를 정한다).
	_shrink_preview.call_deferred()
	setup(Loc.t(L.PRESS_PREVIEW_PLAYER_LONG))


func _shrink_preview() -> void:
	await get_tree().process_frame
	reset_size()
