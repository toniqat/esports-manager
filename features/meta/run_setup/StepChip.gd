class_name StepChip
extends Panel

# 런 준비 머리글(`RunSetupScreen` `%Header`)의 단계 알약 한 칸 — `1  시나리오`.
# **모양의 정본은 `StepChip.tscn`** (높이 · 글자 크기 · 가운데 정렬). 칸 수와 글자는
# `RunSetupScreen.STEPS` 표가, 색(지난 / 지금 / 남은 단계)은 상태가 정하므로 코드가 넣는다.
# 알약 모양은 테마 변형 `StepChipPanel` (반지름 = 높이/2).

const SCENE_PATH: String = "res://features/meta/run_setup/StepChip.tscn"


static func create() -> StepChip:
	return (load(SCENE_PATH) as PackedScene).instantiate() as StepChip


func set_text(text: String) -> void:
	(%Text as Label).text = text


## 지난 단계 = 옅은 앰버, 지금 = 앰버 색면, 남은 단계 = 흰 판 + 테두리.
func paint(bg: Color, fg: Color, border: Variant) -> void:
	var sb := OutgameTheme.variation_box(&"StepChipPanel")
	sb.bg_color = bg
	sb.set_border_width_all(1 if border is Color else 0)
	if border is Color:
		sb.border_color = border
	add_theme_stylebox_override("panel", sb)
	(%Text as Label).add_theme_color_override("font_color", fg)
