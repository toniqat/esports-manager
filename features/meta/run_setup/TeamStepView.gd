class_name TeamStepView
extends ChoiceListView

# Run setup step 1 — the 8 **team packages** (`RunRules.team_packages()`, `teams.csv`) as a
# 3-column card grid. Card (`UI_Comp_TeamCard.tscn`) = team banner, logo · short / full name, budget ·
# facility level small. Screen = `UI_View_TeamStepView.tscn` (inherits `UI_View_ChoiceListView.tscn`).
# The tapped team shows on `RunSetupScreen`'s fixed top banner (`selection_changed`).
#
# **Higher budget = easier** — the hint line says so.
# M1 only shows / snapshots — budget, facility and manual-area effects are M3 / M6.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_TeamStepView.tscn"

static func create() -> TeamStepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamStepView


func _items() -> Array:
	return RunRules.team_packages()


func _hint_text() -> String:
	return Loc.t(L.RUN_SETUP_TEAM_HINT)


func _make_card(item: Dictionary) -> Button:
	var card := TeamCard.create()
	card.fill(item)
	return card
