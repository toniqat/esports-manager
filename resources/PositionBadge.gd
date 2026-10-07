class_name PositionBadge
extends PanelContainer

# **포지션 배지**(`TOP` · `JGL` · `MID` · `ADC` · `SUP`) — 파일럿의 포지션을 보여 주는 자리는
# 아웃게임(편성 썸네일 · 허브 로스터 · 주간 카드 · 런 결과 …)이든 전투(MVP 화면 · 승리 패널)든
# 전부 이 배지 한 장을 쓴다. 화면마다 글자("탱커" · "미드" · "Tk")로 따로 적으면 같은 선수가
# 화면마다 다른 이름으로 불린다.
#
# **모양의 정본은 `UI_Comp_PositionBadge.tscn`** — 루트에 `OutgameTheme.tres` 를 직접 붙여서 다크 전투
# 화면 안에서도 같은 모양으로 선다. 크기는 글자에 맞춰 자란다(알약 변형 `PositionBadgePanel`의
# 여백). 색(역할 색 `OutgameTheme.ROLE_COLORS`)과 글자(`GameEnums.POSITION_ABBREVS`)는 역할이
# 정하는 데이터라 `set_role` 이 넣는다. 글자 크기는 놓는 자리가 `text_size` 로 정한다.

const SCENE_PATH: String = "res://resources/UI_Comp_PositionBadge.tscn"

## 글자 크기(px) — 놓는 자리의 씬이 정한다.
@export var text_size: int = 18:
	set(v):
		text_size = v
		if is_node_ready():
			_apply_text_size()


static func create() -> PositionBadge:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PositionBadge


## 역할(`GameEnums.Role`) → 약칭. 알 수 없는 역할이면 빈 문자열.
static func abbrev(role: int) -> String:
	return String(GameEnums.POSITION_ABBREVS.get(GameEnums.position_key(role), ""))


func _ready() -> void:
	_apply_text_size()
	if UiPreview.is_standalone(self):
		_fill_preview()


## 역할 색 · 약칭을 입힌다. 알 수 없는 역할이면 false (배지는 숨는다).
func set_role(role: int) -> bool:
	var txt: String = abbrev(role)
	if txt == "" or role >= OutgameTheme.ROLE_COLORS.size():
		visible = false
		return false
	visible = true
	var sb := OutgameTheme.variation_box(&"PositionBadgePanel")
	sb.bg_color = (OutgameTheme.ROLE_COLORS[role] as Color).darkened(0.15)
	add_theme_stylebox_override("panel", sb)
	(%Text as Label).text = txt
	return true


## 글자 크기를 넣고, 글자 칸 폭을 다섯 약칭 중 가장 넓은 것에 맞춘다 — 배지 폭이 포지션마다
## 같아야 배지 뒤에 오는 글이 줄마다 같은 자리에서 시작한다.
func _apply_text_size() -> void:
	var lbl: Label = %Text
	lbl.add_theme_font_size_override("font_size", text_size)
	var font: Font = lbl.get_theme_font("font")
	var widest: float = 0.0
	for t: String in GameEnums.POSITION_ABBREVS.values():
		widest = maxf(widest, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x)
	lbl.custom_minimum_size.x = ceilf(widest)


## F6 단독 실행 미리보기 — 정글(`JGL`) 배지 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	set_role(GameEnums.Role.ASSASSIN)
