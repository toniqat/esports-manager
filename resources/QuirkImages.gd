class_name QuirkImages
extends RefCounted

# Quirk (기벽) icon lookup. Same role as `SkillImages` — only this file knows
# where a quirk's picture comes from.
#
#   images/quirks/quirk_<English_Name>.png — LoL Arena augment icons (256²,
#       full-colour glyph in a round frame on transparent). Source: League of
#       Legends Wiki "Category:Arena_augment_icons"; file `<Name> ar augment.png`
#       became `quirk_<Name>.png` (spaces → underscores).
#
# The augment tier colour matches the quirk grade (`quirks.csv` `grade`):
# 0 일반 = Silver (grey), 1 희귀 = Gold (yellow), 2 영웅 = Prismatic (rainbow).
# Within a grade the glyph is picked by the quirk's effect (eye = hit, runner =
# evasion, sword = engage hit, shield = engage evasion, arrow = growth, …).
# One icon per quirk. Add a quirk → add a row here with an icon of its grade's
# tier (a missing id just returns null and the caller draws no icon).
#
# Never `load()` blindly — check `ResourceLoader.exists()` first (`MechImages`).

const DIR: String = "res://resources/images/quirks/"
## quirks.id → icon file name (without `quirk_` and `.png`).
const ICON: Dictionary = {
	# grade 0 — Silver
	1:  "Desecrator",              # field_hit
	2:  "Leg_Day",                 # field_eva
	3:  "Heavy_Hitter",            # engage_hit
	4:  "Numb_to_Pain",            # engage_eva
	5:  "Bravest_of_the_Brave",    # atk_growth
	6:  "Adamant",                 # hp_growth
	# grade 1 — Gold
	7:  "Deathtouch",              # field_hit + field_eva
	8:  "Twice_Thrice",            # engage_hit + engage_eva
	9:  "Undying_Guard",           # hp_growth + engage_eva
	10: "Firebrand",               # atk_growth + engage_hit
	11: "Flashy",                  # field_eva + engage_eva
	12: "Recursion",               # field_hit + engage_eva
	# grade 2 — Prismatic
	13: "Spirit_Link",             # main mech
	14: "Master_of_Duality",       # own role
	15: "Courage_of_the_Colossus", # tank mech
	16: "Mystic_Punch",            # assassin mech
	17: "Trueshot_Prodigy",        # marksman mech
	18: "Quantum_Computing",       # mastery tier
}


## Icon for a quirk id (`quirks.id`). null when unmapped or missing.
static func icon_for(quirk_id: int) -> Texture2D:
	var file: String = String(ICON.get(quirk_id, ""))
	if file.is_empty():
		return null
	var path: String = DIR + "quirk_" + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
