class_name MechMasteryRow
extends Control

# 메크 상세(`MechDetailPanel`)의 숙련도 한 줄 — 파일럿 이름 · 레벨 + 점수 · 보정(%) (§15 A).
# **모양의 정본은 `UI_Comp_MechMasteryRow.tscn`** (세 칸의 폭 비율 · 글자 크기). 이 스크립트는
# 글자와 데이터 색(누른 자리의 파일럿은 ▶ + 진하게, 레벨 색)만 넣는다. 흰 모달 위의 줄이다 —
# 글자 모양은 씬의 `BodyLabel`, 색은 흰 바탕 팔레트(`OutgameTheme`)에서 온다.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_Comp_MechMasteryRow.tscn"

const NAME_COLOR := OutgameTheme.TEXT_SUB
const CURRENT_COLOR := OutgameTheme.TEXT


static func create() -> MechMasteryRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechMasteryRow


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` — `{name, value, level, progress, bonus, current}` (BanPickController `_mastery_rows`).
func fill(row: Dictionary) -> void:
	var cur: bool = bool(row.get("current", false))
	var t: int = int(row.get("level", 0))
	var col: Color = CURRENT_COLOR if cur else NAME_COLOR
	var nm: Label = %PilotName
	nm.text = ("▶ " if cur else "   ") + String(row.get("name", ""))
	nm.add_theme_color_override("font_color", col)
	var tier: Label = %Tier
	tier.text = "%s (%d)" % [MechMastery.level_name(t), int(row.get("value", 0))]
	tier.add_theme_color_override("font_color", MechMastery.level_color(t))
	var bonus: Label = %Bonus
	bonus.text = String(row.get("bonus", ""))
	bonus.add_theme_color_override("font_color", col)


## F6 단독 실행 미리보기 — 누른 자리의 파일럿(▶ 진하게) 한 줄: `Lv3` · 점수 · 보정.
func _fill_preview() -> void:
	UiPreview.stage(self)
	fill({"name": "Seed", "value": 64, "level": 3, "progress": 0.2,
			"bonus": MechMastery.pct_text(3), "current": true})
