class_name ScenarioCard
extends Button

# 런 준비 1단계(`ScenarioStepView`)의 카드 한 장 — 이름 · 샐러리캡 칩 · 설명.
# **모양의 정본은 `ScenarioCard.tscn`.** 이 스크립트는 글자만 넣는다. 고른 / 안 고른
# 판(변형 `SelectableCardButton` / `...On`)은 `ChoiceListView._refresh` 가 고른다.

const SCENE_PATH: String = "res://features/meta/run_setup/ScenarioCard.tscn"


static func create() -> ScenarioCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `item` = `RunRules.scenarios()` 한 줄.
func fill(item: Dictionary) -> void:
	(%Name as Label).text = String(item.get("name", "?"))
	(%Cap as Label).text = "샐러리캡 %d" % int(item.get("salary_cap", 0))
	(%Desc as Label).text = String(item.get("desc", ""))


## F6 단독 실행 미리보기 — 고른 카드 한 장, 손으로 적은 값 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	fill({"id": 1, "name": "도전자의 시즌", "salary_cap": 240,
		"desc": "샐러리캡이 빠듯합니다 — 스타 한 명을 앉히면 나머지 넷은 신인으로 채워야 합니다."})
	theme_type_variation = &"SelectableCardButtonOn"
