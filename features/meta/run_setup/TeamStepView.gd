class_name TeamStepView
extends ChoiceListView

# 런 준비 2단계 — **팀 패키지**(`RunRules.team_packages()`, `teams.csv`) 8장.
# 카드(`UI_Comp_TeamCard.tscn`) = 팀명 · 약칭 · 예산(막대) · 시설 레벨 · "직접 해야 하는 일" · 설명.
# 화면은 `UI_View_TeamStepView.tscn` (`UI_View_ChoiceListView.tscn` 상속).
#
# **예산이 높을수록 쉽다** — 안내 줄과 예산 막대가 그 말을 한다. 막대 길이는
# 표의 최고 예산 대비 비율이라 난이도 문턱 같은 숫자를 코드에 두지 않는다.
# M1 은 표시 · 스냅샷만 한다 — 예산 · 시설 · 직접 영역의 효과는 M3 / M6.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_TeamStepView.tscn"

var _max_budget: int = 1


static func create() -> TeamStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamStepView


func _items() -> Array:
	var items: Array = RunRules.team_packages()
	_max_budget = 1
	for raw in items:
		_max_budget = maxi(_max_budget, int((raw as Dictionary).get("budget", 0)))
	return items


func _hint_text() -> String:
	return "예산이 높을수록 쉽습니다 — 스태프가 많아 직접 해야 하는 일이 적습니다."


func _make_card(item: Dictionary) -> Button:
	var card := TeamCard.create()
	card.fill(item, _max_budget)
	return card
