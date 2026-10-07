class_name MechQuirkRow
extends VBoxContainer

# 메크 상세(`MechDetailPanel`)의 기벽 한 줄 — 등급 색 이름 · 등급, 그 아래 효과 문장.
# **모양의 정본은 `UI_Comp_MechQuirkRow.tscn`** (글자 크기 · 들여쓰기 · 줄 간격). 효과 문장은
# 줄바꿈 Label 이라 길면 줄이 늘어난다. 조건이 이 기체에서 맞지 않는 기벽은 흐리게
# 그리고 `(조건 미충족)` 을 붙인다 — 색은 등급(데이터)이 정하므로 코드가 넣는다. 흰 모달 위라
# 등급 색(`QuirkSystem.GRADE_COLORS`, 흰 바탕용)을 그대로 쓰고, 흐린 줄은 바탕 쪽으로 옅게 한다.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_Comp_MechQuirkRow.tscn"

const EFFECT_COLOR := OutgameTheme.TEXT_SUB
const EFFECT_OFF_COLOR := OutgameTheme.TEXT_FAINT
## 조건 미충족 기벽 이름 — 등급 색을 흰 바탕 쪽으로 이만큼 옅게.
const OFF_FADE: float = 0.5


static func create() -> MechQuirkRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechQuirkRow


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` — `{name, grade, effect, active}` (BanPickController `_quirk_rows`).
func fill(row: Dictionary) -> void:
	var on: bool = bool(row.get("active", true))
	var grade: int = int(row.get("grade", 0))
	var col: Color = QuirkSystem.grade_color(grade)
	var nm: Label = %QuirkName
	nm.text = "%s  · %s" % [String(row.get("name", "")), QuirkSystem.grade_name(grade)]
	nm.add_theme_color_override("font_color", col if on else col.lerp(OutgameTheme.SURFACE, OFF_FADE))
	var eff: Label = %Effect
	var effect: String = String(row.get("effect", ""))
	eff.text = effect if on else Loc.t(L.MATCH_MECH_DETAIL_QUIRK_INACTIVE, {"effect": effect})
	eff.add_theme_color_override("font_color",
			EFFECT_COLOR if on else EFFECT_OFF_COLOR)


## F6 단독 실행 미리보기 — 실제 기벽 표의 희귀 기벽 `사냥꾼`(id 7) 한 줄, 조건 충족.
## 줄 모양은 `BanPickController._quirk_rows` 와 같다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var r: Dictionary = QuirkSystem.row(7)
	fill({"name": QuirkSystem.name_of(7), "grade": int(r.get("grade", 1)),
			"effect": QuirkSystem.effect_text(7, true), "active": true})
