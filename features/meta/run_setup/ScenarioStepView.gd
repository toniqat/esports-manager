class_name ScenarioStepView
extends ChoiceListView

# 런 준비 1단계 — **시나리오**(`RunRules.scenarios()`, `scenarios.csv`).
# 카드(`ScenarioCard.tscn`) = 이름 · 샐러리캡 · 설명. 샐러리캡은 편성 단계의 게이지가 그대로 읽는다.
# 화면은 `ScenarioStepView.tscn` (`ChoiceListView.tscn` 상속).

const SCENE_PATH: String = "res://features/meta/run_setup/ScenarioStepView.tscn"


static func create() -> ScenarioStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioStepView


func _items() -> Array:
	return RunRules.scenarios()


func _hint_text() -> String:
	return "시나리오가 샐러리캡을 정합니다 — 다섯 선수의 샐러리 합이 캡을 넘으면 시작할 수 없습니다."


func _make_card(item: Dictionary) -> Button:
	var card := ScenarioCard.create()
	card.fill(item)
	return card
