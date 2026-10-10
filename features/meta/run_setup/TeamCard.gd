class_name TeamCard
extends Button

# One card of run-setup step 2 (`TeamStepView`) — the team banner as background, logo + short name
# (big) + full name top-left, and two stat cards bottom-right (budget, facility level), each an icon
# in a radial ring. **The look lives in `UI_Comp_TeamCard.tscn`.** This script only fills data: the
# banner / logo textures and fallback colour (`TeamLogos`), the names, the two values and the ring
# ratios (budget / highest budget in the table, facility level / `FacilitySystem.max_level()`).
# Selected / not (variation `SelectableCardButton` / `...On`) is picked by `ChoiceListView._refresh`.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_TeamCard.tscn"


static func create() -> TeamCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `item` = one row of `RunRules.team_packages()`, `max_budget` = the table's highest budget (ring base).
func fill(item: Dictionary, max_budget: int) -> void:
	var team_id: int = int(item.get("id", 0))
	(%BannerFill as ColorRect).color = TeamLogos.color(team_id)
	var banner: TextureRect = %Banner
	banner.texture = TeamLogos.banner(team_id)
	banner.visible = banner.texture != null
	(%Logo as TextureRect).texture = TeamLogos.texture(team_id)
	(%Name as Label).text = Loc.t(String(item.get("name_key", "")))  # l10n-dynamic: name.team.*.name
	(%ShortName as Label).text = Loc.t(String(item.get("short_name_key", "")))  # l10n-dynamic: name.team.*.short

	var budget: int = int(item.get("budget", 0))
	(%BudgetValue as Label).text = Loc.grouped(budget)
	(%BudgetRing as Range).value = clampf(float(budget) / float(maxi(1, max_budget)), 0.0, 1.0)
	var lvl: int = int(item.get("facility_level", 0))
	(%FacilityValue as Label).text = Loc.t(L.RUN_SETUP_LEVEL_N, {"n": lvl})
	(%FacilityRing as Range).value = clampf(float(lvl) / float(maxi(1, FacilitySystem.max_level())), 0.0, 1.0)


## F6 standalone preview — one selected card, hand-written values (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	# Names are the real keys of teams.csv row id 3 (`name.team.3.*`).
	fill({"id": 3, "name_key": "tx_JPFZTZPR02", "short_name_key": "tx_P7M9CVHBZ4", "budget": 700,
		"facility_level": 2}, 1000)
	theme_type_variation = &"SelectableCardButtonOn"
