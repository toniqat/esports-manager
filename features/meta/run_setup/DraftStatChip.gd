class_name DraftStatChip
extends PanelContainer

# 파일럿 상세(`DraftDetailPanel`)의 스탯 칩 한 칸 — 위에 스탯 이름, 아래에 값.
# **모양의 정본은 `UI_Comp_DraftStatChip.tscn`** (`SunkPanel` 변형 · 글자 크기 · 위치).
# 이 스크립트는 글자를 넣고, "종합" 칸이면 값 글자를 `AccentLabel` 변형으로 바꿀 뿐이다.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_DraftStatChip.tscn"


static func create() -> DraftStatChip:
	return (load(SCENE_PATH) as PackedScene).instantiate() as DraftStatChip


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `is_total` = 마지막 "종합" 칸 — 값만 앰버 글자로 강조한다.
func fill(key: String, value: String, is_total: bool) -> void:
	%Key.text = key
	var v: Label = %Value
	v.text = value
	v.theme_type_variation = &"AccentLabel" if is_total else &"BodyLabel"


## F6 단독 실행 미리보기 — "종합" 칸(앰버 값) (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	fill("종합", "514", true)
