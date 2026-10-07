class_name MessengerNpcBubble
extends MarginContainer

# One line of the other side (left) in `MessengerView`'s log: round portrait · tail · white bubble.
#
# **Layout lives in `UI_Comp_MessengerNpcBubble.tscn`** — margins (left edge, gap below), the portrait
# slot width, the tail's offset and the bubble width / padding. The bubble's height follows the
# wrapped text (container layout); the portrait (96) may hang below a short bubble, as before.
# This script only fills the text and decides whether this line shows the portrait + tail
# (the first line after another speaker). Create with `MessengerNpcBubble.create()`.

const SCENE_PATH: String = "res://features/season/press/UI_Comp_MessengerNpcBubble.tscn"


static func create() -> MessengerNpcBubble:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MessengerNpcBubble


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `with_portrait` = false for a follow-up line by the same speaker (no portrait, no tail — the
## slots keep their width so the bubbles line up). `portrait` null → reporter microphone glyph.
func setup(text: String, portrait: Texture2D, with_portrait: bool) -> void:
	%Text.text = text
	var slot: Control = %Portrait
	slot.visible = with_portrait
	%Glyph.visible = with_portrait and portrait == null
	%Wedge.visible = with_portrait
	if with_portrait:
		OutgameTheme.add_round_portrait(slot, portrait, Vector2.ZERO, slot.size.x,
				OutgameTheme.BORDER)


## F6 단독 실행 미리보기 — 기자 마이크 초상 + 꼬리, 두 줄로 감기는 말풍선
## (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	# 홀로 선 루트는 첫 배치(줄바꿈 글 폭 0 → 아주 긴 높이)만큼 커진 채 줄지 않는다 —
	# 한 프레임 뒤 최소 크기로 되돌린다(로그 안에서는 VBox 가 매번 크기를 정한다).
	_shrink_preview.call_deferred()
	setup(Loc.t(L.PRESS_PREVIEW_NPC_LONG),
			null, true)


func _shrink_preview() -> void:
	await get_tree().process_frame
	reset_size()
