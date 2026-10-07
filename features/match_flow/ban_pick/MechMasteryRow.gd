class_name MechMasteryRow
extends Control

# 메크 상세(`MechDetailPanel`)의 숙련도 한 줄 — 파일럿 이름 · 등급 + 값 · 보정.
# **모양의 정본은 `MechMasteryRow.tscn`** (세 칸의 폭 비율 · 글자 크기). 이 스크립트는
# 글자와 데이터 색(누른 자리의 파일럿은 ▶ + 밝게, 등급 색)만 넣는다.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/MechMasteryRow.tscn"

const NAME_COLOR := Color(0.72, 0.74, 0.80)
const CURRENT_COLOR := Color(0.96, 0.96, 0.98)


static func create() -> MechMasteryRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechMasteryRow


## `row` — `{name, value, tier, bonus, current}` (BanPickController `_mastery_rows`).
func fill(row: Dictionary) -> void:
	var cur: bool = bool(row.get("current", false))
	var t: int = int(row.get("tier", 0))
	var col: Color = CURRENT_COLOR if cur else NAME_COLOR
	var nm: Label = %PilotName
	nm.text = ("▶ " if cur else "   ") + String(row.get("name", ""))
	nm.add_theme_color_override("font_color", col)
	var tier: Label = %Tier
	tier.text = "%s %d" % [MechMastery.tier_name(t), int(row.get("value", 0))]
	tier.add_theme_color_override("font_color", MechMastery.tier_color(t).lightened(0.25))
	var bonus: Label = %Bonus
	bonus.text = String(row.get("bonus", ""))
	bonus.add_theme_color_override("font_color", col)
