class_name ScenarioCard
extends Button

# 런 준비 1단계(`ScenarioStepView`)의 카드 한 장 — 이름 · 샐러리캡 칩 · 설명.
# **모양의 정본은 `UI_Comp_ScenarioCard.tscn`.** 이 스크립트는 글자만 넣는다. 고른 / 안 고른
# 판(변형 `SelectableCardButton` / `...On`)은 `ChoiceListView._refresh` 가 고른다.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_ScenarioCard.tscn"


static func create() -> ScenarioCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `item` = `RunRules.scenarios()` 한 줄.
func fill(item: Dictionary) -> void:
	(%Name as Label).text = Loc.t(String(item.get("name_key", "")))  # l10n-dynamic: scenario.*.name
	(%Cap as Label).text = "샐러리캡 %d" % int(item.get("salary_cap", 0))
	(%Desc as Label).text = Loc.t(String(item.get("desc_key", "")))  # l10n-dynamic: scenario.*.desc


## F6 단독 실행 미리보기 — 고른 카드 한 장, 시나리오 1 의 key + 손으로 적은 캡 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	fill({"id": 1, "name_key": "tx_WHEYGN2VQZ", "salary_cap": 240, "desc_key": "tx_4H2VGDNYW7"})
	theme_type_variation = &"SelectableCardButtonOn"
