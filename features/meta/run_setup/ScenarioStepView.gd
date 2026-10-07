class_name ScenarioStepView
extends ChoiceListView

# 런 준비 1단계 — **시나리오**(`RunRules.scenarios()`, `scenarios.csv`).
# 카드(`UI_Comp_ScenarioCard.tscn`) = 이름 · 샐러리캡 · 설명. 샐러리캡은 편성 단계의 게이지가 그대로 읽는다.
# 화면은 `UI_View_ScenarioStepView.tscn` (`UI_View_ChoiceListView.tscn` 상속).

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_ScenarioStepView.tscn"


static func create() -> ScenarioStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioStepView


func _items() -> Array:
	return RunRules.scenarios()


func _hint_text() -> String:
	return Loc.t(L.RUN_SETUP_SCENARIO_HINT)


func _make_card(item: Dictionary) -> Button:
	var card := ScenarioCard.create()
	card.fill(item)
	return card
