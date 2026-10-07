class_name BanPickPortrait
extends Control

# One **pilot portrait** of a team block (`BanPickTeamBlock`): a sunk back plate (shows as-is
# when there is no image — INTL teams / standalone run), the face crop, a side-coloured rim,
# the `기벽 n` badge (my pilots, season run) and a transparent tap button (assign step only).
#
# **Layout lives in `UI_Comp_BanPickPortrait.tscn`.** The crop is data: an eye band during ban/pick,
# the bust once the assign step makes the portrait row tall (`BanPickController`). The rim
# colour is the side colour and the badge fill the quirk grade colour, so both StyleBoxes are
# built here / by the controller.

var back: ColorRect = null
var face: TextureRect = null
var rim: Panel = null
## `기벽 n` pill (bottom-right). Optional — deleting it hides the quirk badge.
var quirk_badge: Panel = null
var quirk_label: Label = null
var hit: Button = null


func _ready() -> void:
	back = %Back
	face = %Face
	rim = %Rim
	quirk_badge = get_node_or_null("%QuirkBadge") as Panel
	quirk_label = get_node_or_null("%QuirkLabel") as Label
	hit = %Hit
	if UiPreview.is_standalone(self):
		_fill_preview()


## Side colour of the rim — shape = theme variation `BanPickPortraitRim` (2px, transparent fill).
func setup(side_col: Color) -> void:
	var sb := OutgameTheme.variation_box(&"BanPickPortraitRim")
	sb.border_color = side_col
	rim.add_theme_stylebox_override("panel", sb)


## F6 단독 실행 미리보기 — 아군(BLUE) 파일럿 Seed(id 7) 의 눈높이 크롭 + `기벽 2`
## 배지(영웅 등급 색). 채우는 법은 `BanPickController._setup_team_block` /
## `_refresh_portrait_quirk` 와 같다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(hit.pressed, "portrait tapped")
	setup(Color(0.20, 0.45, 0.92))
	face.texture = PilotImages.eye_for(7)
	if quirk_badge != null:
		quirk_badge.visible = true
		quirk_badge.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				QuirkSystem.grade_color(2), int(quirk_badge.size.y * 0.5)))
		if quirk_label != null:
			quirk_label.text = Loc.t(L.MATCH_BAN_PICK_QUIRK_COUNT, {"n": 2})
