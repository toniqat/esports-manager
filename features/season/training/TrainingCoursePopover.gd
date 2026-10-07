class_name TrainingCoursePopover
extends Panel

# 코스 카드를 누르면 그 위에 뜨는 정보 팝오버 — 등급 · 이름 · 놓임/상한 · **EXP** ·
# **효과** (+ 전술이 모자라 잠긴 등급이면 그 이유 한 줄). 뒤의 둘은 타일 데이터에서
# 만들어진다(`exp_summary` / `effect_summary`) — 설명문 줄은 없다(`README.md`).
#
# **레이아웃의 정본은 `TrainingCoursePopover.tscn` 이다** (폭, 줄마다의 x · 폭 · 글꼴,
# 테두리 · 그림자). 코드가 정하는 것은 **높이**뿐이다: `Exp` · `Effect` · `Lock` 의 y 와
# 높이, 판 전체 높이를 글자에서 역산한다(`_text_height`). 컨테이너 자동 크기에 맡기면
# 자리를 잡는 프레임(`TrainingView._place_popover`)과 그리는 프레임이 어긋난다 —
# 줄바꿈 Label 의 최소 높이는 레이아웃이 한 번 돈 뒤에야 맞는다.
# 테두리 색은 등급 색(데이터)이라 씬의 `PopoverFrame` 을 복사해 바꾼다.

const SCENE_PATH: String = "res://features/season/training/TrainingCoursePopover.tscn"

## 글 덩어리 사이 간격과 판 아래 여백.
const LINE_GAP: float = 10.0
const PAD_BOTTOM: float = 16.0
## `Label` 이 줄 사이에 넣는 간격(기본 테마의 `line_spacing`). `_text_height` 가 이것을
## 되돌려 주지 않으면 여러 줄 글이 팝오버 아래로 넘친다.
const LINE_SPACING: float = 3.0


## 씬을 인스턴스한다. `TrainingCoursePopover.new()` 는 빈 Panel 이라 쓰지 않는다.
static func create() -> TrainingCoursePopover:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingCoursePopover


## 채우고 높이를 세운다. `lock` 이 비어 있지 않으면 놓임/상한 대신 잠금 이유 줄이 붙는다.
func fill(t: TrainingTile, cap_text: String, lock: String) -> void:
	var sty := (get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sty.border_color = t.grade_color()
	add_theme_stylebox_override(&"panel", sty)

	(%Title as Label).text = "[%s] %s" % [t.grade_name(), t.tile_name]
	var cap: Label = %Cap
	cap.text = "" if not lock.is_empty() else cap_text
	cap.add_theme_color_override(&"font_color", t.grade_color())

	var exp_lbl: Label = %Exp
	var y: float = exp_lbl.position.y
	y = _place_line(exp_lbl, t.exp_summary(), y, true)
	y = _place_line(%Effect, t.effect_summary(), y)
	y = _place_line(%Lock, lock, y)
	size = Vector2(size.x, y - LINE_GAP + PAD_BOTTOM)


## 한 줄 덩어리를 `y` 에 놓고 다음 덩어리의 y 를 돌려준다. 빈 글은 숨기고 자리를 안
## 먹는다 — `keep` 인 줄(EXP)만 비어도 자리(간격)를 지킨다.
func _place_line(lbl: Label, text: String, y: float, keep: bool = false) -> float:
	lbl.visible = keep or not text.is_empty()
	if not lbl.visible:
		return y
	lbl.text = text
	var h: float = _text_height(text, lbl.size.x, lbl.get_theme_font_size(&"font_size"))
	lbl.position = Vector2(lbl.position.x, y)
	lbl.size = Vector2(lbl.size.x, h)
	return y + h + LINE_GAP


## 줄바꿈된 글자가 실제로 차지하는 높이. **`Font.get_multiline_string_size` 를
## 그대로 믿으면 안 된다** — 그 함수는 글꼴 줄 높이만 더할 뿐 `Label` 이 줄
## 사이에 넣는 `line_spacing`(기본 3)을 세지 않아서, 두 줄짜리 글은 실측 49px
## 인데 46 이 돌아온다. 그 3px 이 팝오버 아래끝을 넘어 판 위로 삐져나오던 것이
## **설명이 패널을 넘어가던** 원인이다. 줄 수를 세어 그 몫을 되돌려 준다
## (실측: 1줄 23 · 2줄 49 · 3줄 75 로 `Label.get_minimum_size().y` 와 정확히 일치).
static func _text_height(text: String, width: float, font_size: int) -> float:
	if text.is_empty():
		return 0.0
	var font: Font = ThemeDB.fallback_font
	var one: float = maxf(1.0,
			font.get_string_size("가", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y)
	var total: float = font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	var lines: int = maxi(1, int(round(total / one)))
	return total + float(lines - 1) * LINE_SPACING
