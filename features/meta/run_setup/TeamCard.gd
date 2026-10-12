class_name TeamCard
extends Button

# One card of the team step's 3-column grid (`TeamStepView`) — the team banner as background, the
# logo centred at the top, short name (big) + full name under it, and budget · facility level small
# along the bottom (icon + value each). **The look lives in `UI_Comp_TeamCard.tscn`.** This script
# only fills data: the banner / logo textures and fallback colour (`TeamLogos`), the names, the two values.
# Selected / not (variation `SelectableCardButton` / `...On`) is picked by `ChoiceListView._refresh`.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_TeamCard.tscn"


static func create() -> TeamCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamCard


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `item` = one row of `RunRules.team_packages()`.
func fill(item: Dictionary) -> void:
	var team_id: int = int(item.get("id", 0))
	(%BannerFill as ColorRect).color = TeamLogos.color(team_id)
	var banner: TextureRect = %Banner
	banner.texture = TeamLogos.banner(team_id)
	banner.visible = banner.texture != null
	(%Logo as TextureRect).texture = TeamLogos.texture(team_id)
	(%Name as Label).text = Loc.t(String(item.get("name_key", "")))  # l10n-dynamic: name.team.*.name
	(%ShortName as Label).text = Loc.t(String(item.get("short_name_key", "")))  # l10n-dynamic: name.team.*.short

	(%BudgetValue as Label).text = Loc.grouped(int(item.get("budget", 0)))
	(%FacilityValue as Label).text = Loc.t(L.RUN_SETUP_LEVEL_N, {"n": int(item.get("facility_level", 0))})


## F6 standalone preview — one selected card, hand-written values (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	# Names are the real keys of teams.csv row id 3 (`name.team.3.*`).
	fill({"id": 3, "name_key": "tx_JPFZTZPR02", "short_name_key": "tx_P7M9CVHBZ4", "budget": 700,
		"facility_level": 2})
	theme_type_variation = &"SelectableCardButtonOn"
