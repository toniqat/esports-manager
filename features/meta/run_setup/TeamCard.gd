class_name TeamCard
extends Button

# 런 준비 2단계(`TeamStepView`)의 카드 한 장 — 팀명 · 약칭 · 예산(막대) · 시설 레벨 ·
# "직접 해야 하는 일" · 설명. **모양의 정본은 `TeamCard.tscn`.** 이 스크립트는 글자,
# 예산 막대 길이(최고 예산 대비 — 데이터), "없음" 이면 초록 변형 `PositiveLabel` 만 넣는다.
# 고른 / 안 고른 판(변형 `SelectableCardButton` / `...On`)은 `ChoiceListView._refresh` 가 고른다.

const SCENE_PATH: String = "res://features/meta/run_setup/TeamCard.tscn"


static func create() -> TeamCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `item` = `RunRules.team_packages()` 한 줄, `max_budget` = 표의 최고 예산(막대 기준).
func fill(item: Dictionary, max_budget: int) -> void:
	(%Name as Label).text = String(item.get("name", "?"))
	(%ShortName as Label).text = String(item.get("short_name", ""))
	var budget: int = int(item.get("budget", 0))
	(%Budget as Label).text = "예산 %d" % budget
	(%Facility as Label).text = "시설 Lv %d" % int(item.get("facility_level", 0))
	(%Fill as Control).anchor_right = clampf(float(budget) / float(maxi(1, max_budget)), 0.0, 1.0)

	# 직접 해야 하는 일 — 비어 있으면 "없음"(초록).
	var labels: Array = []
	for area in item.get("manual_areas", []):
		labels.append(RunRules.area_label(String(area)))
	var manual: Label = %Manual
	if labels.is_empty():
		manual.text = "없음"
		manual.theme_type_variation = &"PositiveLabel"
	else:
		manual.text = " · ".join(PackedStringArray(labels))
		manual.theme_type_variation = &"BodyLabel"
	(%Desc as Label).text = String(item.get("desc", ""))


## F6 단독 실행 미리보기 — 고른 카드 한 장, 손으로 적은 값 (`resources/UiPreview.gd`).
## "직접 해야 하는 일" 의 영역 키는 `RunRules.area_label` 이 읽는 실제 키를 쓴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	fill({"id": 3, "name": "블루 팔콘스", "short_name": "BFC", "budget": 70,
		"facility_level": 2, "manual_areas": ["training", "analysis"],
		"desc": "중위권 구단 — 스태프가 절반뿐이라 훈련 배치를 직접 챙겨야 합니다."}, 100)
	theme_type_variation = &"SelectableCardButtonOn"
