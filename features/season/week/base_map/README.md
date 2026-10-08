# Team base map (팀 부지 맵) (week/base_map)

The map drawn in the centre of the week screen on training days (`features/season/week/README.md`
"Training day: morning → afternoon"). Each team uses one map (`data/csv/teams.csv` `map_id`); my five
pilots stand on its spots.

| File | Role |
|---|---|
| `BaseMap.gd` | `class_name BaseMap extends Control`, shared by every map scene. `create(map_id)` (index into `SCENES`), `spot_of_color(symbol)` (training colour → spot), `spot_of_facility(f)` (training facility: a spot name from `training_tiles.csv` `facility` or a colour symbol → spot), `spot_point(spot)`, `add_token(node)` / `clear_tokens()`, `place_tokens(entries)` (fan-out + separation + clamp). F6 preview: one token per spot named after it, three on `W` to show the fan-out |
| `UI_Comp_BaseMap_<Name>.tscn` (12) | One map each: art + spot markers. `map_id` order = `SCENES` = the image numbering in `resources/images/base_map/` |

| `map_id` | Scene | Art |
|---|---|---|
| 0 | `UI_Comp_BaseMap_SchaleOffice` | `00_schale_office.png` |
| 1 | `UI_Comp_BaseMap_SchaleDorm` | `01_schale_dorm.png` |
| 2 | `UI_Comp_BaseMap_Gehenna` | `02_gehenna.png` |
| 3 | `UI_Comp_BaseMap_Abydos` | `03_abydos.png` |
| 4 | `UI_Comp_BaseMap_Millennium` | `04_millennium.png` |
| 5 | `UI_Comp_BaseMap_Trinity` | `05_trinity.png` |
| 6 | `UI_Comp_BaseMap_RedWinter` | `06_red_winter.png` |
| 7 | `UI_Comp_BaseMap_Hyakkiyako` | `07_hyakkiyako.png` |
| 8 | `UI_Comp_BaseMap_DuShiratori` | `08_du_shiratori.png` |
| 9 | `UI_Comp_BaseMap_Shanhaijing` | `09_shanhaijing.png` |
| 10 | `UI_Comp_BaseMap_Haruhabara` | `10_haruhabara.png` |
| 11 | `UI_Comp_BaseMap_WildHunt` | `11_wild_hunt.png` |

Which team uses which map is data only (`teams.csv` `map_id`, read by `RunRules.team_map_id`); the current
assignment is in that CSV. Maps 0, 1, 8, 9 are not assigned to a team yet.

## Scene (`UI_Comp_BaseMap_<Name>.tscn`)

```
BaseMap_<Name> (Control DESIGN_SIZE, mouse Ignore, script BaseMap.gd)
├ Art      TextureRect full rect, keep aspect centred (the PNG)
├ Spots    Control full rect
│ ├ Spot_H · Spot_E · Spot_C · Spot_D · Spot_G · Spot_M · Spot_Q · Spot_W   (Marker2D)
│ └ Spot_Dorm · Spot_Entrance                                               (Marker2D)
└ %Tokens  Control full rect, mouse Ignore: code adds the pilot tokens
```

* **Spots are markers you drag in the editor.** A marker's position (map-local) is where a token's portrait
  centre stands. `spot_point` falls back to `Spot_W`, then to the map centre, when a marker is missing.
* **Spot per colour group** (`COLOR_SPOTS`, the colour table of `features/season/training/README.md`):
  `H` field accuracy · `E` field evasion · `C` engage accuracy · `D` engage evasion · `G` growth (`A` attack and
  `P` HP share it) · `M` mastery · `Q` quirk · `W` neutral (`W`, the amplifier's black `K`, and a cell with no
  tile = basic course). `Dorm` / `Entrance` are the afternoon away spots (resting / out alone,
  `features/season/mental/README.md` "Afternoon away states").
* **No overlap**: tokens sharing a spot fan out in rows of `TOKENS_PER_ROW`, a `TOKEN_STEP` apart, centred on
  the spot. Tokens of different spots that land too close are pushed apart along the axis of least overlap
  (`_separate`, `TOKEN_STEP` = footprint), then everything is clamped inside the map. So spots may sit near
  each other; tokens simply step aside.
* Spot positions were first placed by eye on plausible buildings of each picture; tune them in the editor.
* The week screen instances the map with `BaseMap.create`, names it `BaseMap_Team` and adds it to
  `WeekMapSection` `%MapHolder`.
