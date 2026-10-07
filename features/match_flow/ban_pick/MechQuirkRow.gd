class_name MechQuirkRow
extends VBoxContainer

# 메크 상세(`MechDetailPanel`)의 기벽 한 줄 — 등급 색 이름 · 등급, 그 아래 효과 문장.
# **모양의 정본은 `MechQuirkRow.tscn`** (글자 크기 · 들여쓰기 · 줄 간격). 효과 문장은
# 줄바꿈 Label 이라 길면 줄이 늘어난다. 조건이 이 기체에서 맞지 않는 기벽은 흐리게
# 그리고 `(조건 미충족)` 을 붙인다 — 색은 등급(데이터)이 정하므로 코드가 넣는다.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/MechQuirkRow.tscn"

const EFFECT_COLOR := Color(0.72, 0.74, 0.80)
const EFFECT_OFF_COLOR := Color(0.62, 0.66, 0.76)


static func create() -> MechQuirkRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechQuirkRow


## `row` — `{name, grade, effect, active}` (BanPickController `_quirk_rows`).
func fill(row: Dictionary) -> void:
	var on: bool = bool(row.get("active", true))
	var grade: int = int(row.get("grade", 0))
	var col: Color = QuirkSystem.grade_color(grade).lightened(0.35)
	var nm: Label = %QuirkName
	nm.text = "%s  · %s" % [String(row.get("name", "")), QuirkSystem.grade_name(grade)]
	nm.add_theme_color_override("font_color", col if on else col.darkened(0.35))
	var eff: Label = %Effect
	eff.text = String(row.get("effect", "")) + ("" if on else "  (조건 미충족)")
	eff.add_theme_color_override("font_color",
			EFFECT_COLOR if on else EFFECT_OFF_COLOR.darkened(0.25))
