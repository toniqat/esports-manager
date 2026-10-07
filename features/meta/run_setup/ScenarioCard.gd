class_name ScenarioCard
extends Button

# 런 준비 1단계(`ScenarioStepView`)의 카드 한 장 — 이름 · 샐러리캡 칩 · 설명.
# **모양의 정본은 `ScenarioCard.tscn`.** 이 스크립트는 글자만 넣는다. 고른 / 안 고른
# 테두리는 `ChoiceListView._refresh` 가 칠한다.

const SCENE_PATH: String = "res://features/meta/run_setup/ScenarioCard.tscn"


static func create() -> ScenarioCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioCard


## `item` = `RunRules.scenarios()` 한 줄.
func fill(item: Dictionary) -> void:
	(%Name as Label).text = String(item.get("name", "?"))
	(%Cap as Label).text = "샐러리캡 %d" % int(item.get("salary_cap", 0))
	(%Desc as Label).text = String(item.get("desc", ""))
