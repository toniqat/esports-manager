class_name TeamStepView
extends ChoiceListView

# Run setup step 2 — the 8 **team packages** (`RunRules.team_packages()`, `teams.csv`).
# Card (`UI_Comp_TeamCard.tscn`) = team banner, logo · short / full name, budget · facility ring cards.
# Screen = `UI_View_TeamStepView.tscn` (inherits `UI_View_ChoiceListView.tscn`).
#
# **Higher budget = easier** — the hint line and the budget ring say so. The ring ratio is relative
# to the table's highest budget, so no difficulty threshold lives in code.
# M1 only shows / snapshots — budget, facility and manual-area effects are M3 / M6.

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
	return Loc.t(L.RUN_SETUP_TEAM_HINT)


func _make_card(item: Dictionary) -> Button:
	var card := TeamCard.create()
	card.fill(item, _max_budget)
	return card
