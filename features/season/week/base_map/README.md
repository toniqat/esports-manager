# Team base map (팀 부지 맵) (week/base_map)

The map drawn in the centre of the week screen on training days (`features/season/week/README.md`
"Training day: morning → afternoon"). Each team uses one map (`data/csv/teams.csv` `map_id`); my five
pilots stand on its spots.

| File | Role |
|---|---|
| `BaseMap.gd` | `class_name BaseMap extends Control`, shared by every map scene. `create(map_id)` (index into `SCENES`), `mount(map, holder)` (adds it at `DESIGN_SIZE`, centred horizontally on a plain-Control holder, re-centred on resize), `visible_rect()` (map-local part on screen), facility helpers `facility_spot_name(fid)` · `has_facility_spot(fid)` · `facility_point(fid)` · `facility_layer()` (`%Facilities`, null on the stadium) · `place_at_facility(node, fid, anchor)` (§16 research bubbles, `facility/README.md` "UI"), `spot_of_color(symbol)` (training colour → spot), `spot_of_facility(f)` (training facility: a spot name from `training_tiles.csv` `facility` or a colour symbol → spot), `spot_point(spot)`, `add_token(node)` / `clear_tokens()`, `place_tokens(entries)` (seating by `BaseMapSeating`, entries carry `portrait` / `ring` = outline + tail colour, default black), `token_state()` / `walk_from(prev, max_time, delay)` (walking), `set_hour` / `play_hour` / `is_animating` / `finish_animation` (lighting clock). F6 preview (as the week screen shows it, no facility bubbles): five random non-mob pilots' portraits on random spots, each round 5 / 3 / 1 / 4 / 2 of them sharing one spot (`_PREVIEW_CROWDS`, shows every polygon), then a walk + day-cycle demo loop |
| `BaseMapSeating.gd` | `class_name BaseMapSeating`, static: the map's own marker seating (`pick_seats`, `seat_distance`, `layout`) and outline-only look constants (`OUTLINE_W`, `outer_radius`), tail outline aimed so its tip lands on the point (`tail_outline`) — see "Pilot markers" below |
| `BaseMapLighting.gd` + `.gdshader` | `@tool class_name BaseMapLighting extends Control` (`Lighting` node of every map scene): time-of-day tint, sun, building normals and cast shadows — see "Time of day" below |
| `BaseMapBuilding.gd` | `@tool class_name BaseMapBuilding extends Polygon2D`: one building = its **roof** polygon + `height` (walls / footprint / shadow derived) |
| `BaseMapRoads.gd` | `@tool class_name BaseMapRoads extends Node2D` (`Roads` node): Line2D children → road graph, `route` (A*), `snap` — see "Roads and walking" below |
| `UI_Comp_BaseMap_<Name>.tscn` (10) | One map each: art + spot markers. `map_id` order = `SCENES` = the image numbering in `resources/images/base_map/` minus 2 (the indoor Schale maps 00 / 01 were deleted 2026-10, `teams.csv` `map_id` shifted down by 2) |
| `UI_Comp_BaseMap_Stadium.tscn` | **Weekend stadium** (not a team map, not in `SCENES`): `BaseMap.create_stadium()` (`STADIUM_SCENE`). Placeholder art = flat `ColorRect` `Art` (`editor_description = "TODO: stadium art …"`) + three `Zone_*` blocks; spots `Spot_TeamRoom` (Saturday prep) · `Spot_Booth` (Sunday match) · `Spot_Press` (Sunday press) · `Spot_W` · `Spot_Entrance` |

| `map_id` | Scene | Art |
|---|---|---|
| 0 | `UI_Comp_BaseMap_Gehenna` | `02_gehenna.png` |
| 1 | `UI_Comp_BaseMap_Abydos` | `03_abydos.png` |
| 2 | `UI_Comp_BaseMap_Millennium` | `04_millennium.png` |
| 3 | `UI_Comp_BaseMap_Trinity` | `05_trinity.png` |
| 4 | `UI_Comp_BaseMap_RedWinter` | `06_red_winter.png` |
| 5 | `UI_Comp_BaseMap_Hyakkiyako` | `07_hyakkiyako.png` |
| 6 | `UI_Comp_BaseMap_DuShiratori` | `08_du_shiratori.png` |
| 7 | `UI_Comp_BaseMap_Shanhaijing` | `09_shanhaijing.png` |
| 8 | `UI_Comp_BaseMap_Haruhabara` | `10_haruhabara.png` |
| 9 | `UI_Comp_BaseMap_WildHunt` | `11_wild_hunt.png` |

Which team uses which map is data only (`teams.csv` `map_id`, read by `RunRules.team_map_id`); the current
assignment is in that CSV. Maps 6 (DuShiratori) and 7 (Shanhaijing) are not assigned to a team yet.

## Scene (`UI_Comp_BaseMap_<Name>.tscn`)

## Size and scale (1.2×, 2026-10)

The art was authored in a 1000 × 634 frame (`ART_BASE_SIZE`); every map scene is now **1.2× that**
(`MAP_SCALE`, `DESIGN_SIZE` = 1200 × 761): root size, art rect, every `Spot_*` marker (and the stadium's
`Zone_*` blocks) were multiplied by 1.2 in the scenes, so `spot_point` / `facility_point` / `size` are
already in scaled map pixels. **Overlays are not scaled** — pilot tokens and research bubbles keep their pixel
size, only their positions follow the spots.

The map is wider than the 1080 phone screen: hosts mount it with `BaseMap.mount` on a screen-centred plain
`Control` (a container would take the 1200 minimum width and widen the page), so 60 px are cropped on each
side (none on a viewport ≥ 1200 wide, e.g. a tablet). `visible_rect()` = the map-local rect on screen
(x 60 … 1140 on a phone); anything that must stay visible (tokens, bubbles) should clamp to it.
Hosts: week screen `%MapPin` (full width), hub `%MapHolder` (Body x 30 … −30, still screen-centred).

Every spot is on screen (screen x after the crop, 1080 wide, all ≥ 46 px from an edge):

| Map | Token spots (screen x) | Facility spots (screen x) |
|---|---|---|
| Abydos | 68 … 971 | 72 … 924 |
| DuShiratori | 163 … 877 | 216 … 852 |
| Gehenna | 92 … 995 | 90 … 972 |
| Haruhabara | 216 … 900 | 288 … 888 |
| Hyakkiyako | 194 … 900 | 192 … 804 |
| Millennium | 114 … 972 | 114 … 972 |
| RedWinter | 156 … 924 | 156 … 900 |
| Shanhaijing | 72 … 972 | 264 … 960 |
| Trinity | 233 … 936 | 228 … 924 |
| WildHunt | 228 … 840 | 228 … 834 |
| Stadium | 168 … 912 | — |

Markers are clamped into `visible_rect()`.

```
BaseMap_<Name> (Control DESIGN_SIZE 1200 × 761, mouse Ignore, script BaseMap.gd)
├ Art      TextureRect full rect, keep aspect centred (the PNG)
├ Spots    Control full rect
│ ├ Spot_H · Spot_E · Spot_C · Spot_D · Spot_G · Spot_M · Spot_Q · Spot_W   (Marker2D)
│ ├ Spot_Dorm · Spot_Entrance                                               (Marker2D)
│ └ Spot_Fac_TrainField · _TrainEngage · _TrainGrowth · _Intel · _MechLab · _Front · _Personnel (Marker2D, §16)
├ Lighting   BaseMapLighting full rect, mouse Ignore (right after Art; on the stadium after Art's Zone_* children)
├ Spots ...
├ %Facilities  Control full rect, mouse Ignore: code adds the facility research bubbles (ResearchBubble)
├ %Tokens  Control full rect, mouse Ignore: code adds the pilot tokens
├ Buildings  Node2D, hidden at runtime ─ BaseMapBuilding × N   (every team map; not the stadium)
└ Roads      BaseMapRoads, hidden at runtime ─ Line2D × N      (every team map; not the stadium)
```

* **Spots are markers you drag in the editor.** A marker's position (map-local) is where a token's portrait
  centre stands. `spot_point` falls back to `Spot_W`, then to the map centre, when a marker is missing.
* **Spot per colour group** (`COLOR_SPOTS`, the colour table of `features/season/training/README.md`):
  `H` field accuracy · `E` field evasion · `C` engage accuracy · `D` engage evasion · `G` growth (`A` attack and
  `P` HP share it) · `M` mastery · `Q` quirk · `W` neutral (`W`, the amplifier's black `K`, and a cell with no
  tile = basic course). `Dorm` / `Entrance` are the afternoon away spots (resting / out alone,
  `features/season/mental/README.md` "Afternoon away states").
* **Pilot markers** (2026-10: own seating, no longer the battlefield's row rule — only my five pilots are on the
  map, so there are no team sides). A spot is one point — the road point nearest its marker (`Roads`), else the marker.
  Seating (`BaseMapSeating.pick_seats`, spots in entry order, greedy):
  * **1 pilot** → portrait straight above the point at `SINGLE_DIST` (diameter + `MARKER_GAP` = 91, the old first-row look).
  * **2–5 pilots** → a regular polygon centred on the point: 2 = left / right, 3 = triangle, 4 = square, 5 = pentagon.
    Seat 0 is at the top (even counts: the top edge is flat, so 2 is left / right and 4 a square), the rest clockwise,
    seat order = entry order (the week screen passes TOP → SUP). Radius = the smallest that keeps neighbouring portraits
    `MARKER_GAP` apart (chord = 2 × (`MARKER_RADIUS` + `OUTLINE_W`) + gap), but at least `outer + MIN_TAIL` (18) so every
    tail stays visible: ≈ 66 / 66 / 71 / 86 px for 2 / 3 / 4 / 5. All tails point at the point and meet there.
  * A layout that touches portraits or tails of spots placed before is rotated (`ROTATIONS_DEG` 0, ±15, ±30, ±45),
    then grown (`GROWS` ×1.2, ×1.45); none clean = the plain layout anyway. Seats are clamped into `visible_rect`
    (inset by the marker radius) before the test. `token_state` / `walk_from` are unchanged — a seat is just `vec`.
* **Look** (map only — the battlefield keeps its team / HP ring): portrait `MARKER_RADIUS` = `PilotMarker.FIELD_RADIUS`
  (42.5) with a white backing, a `OUTLINE_W` (= `PilotMarker.MARKER_OUTLINE_W`, 5 px) outline, and a **solid tail**, both
  in the entry's `ring` colour — **default black**; the week screen passes `OutgameTheme.ACCENT` for the picked pilot
  (same thickness, accent colour). No team-blue ring or tail. Shadows use `PilotMarker.draw_shadow` with the smaller
  outline radius (`outer`). Drawn on `%Tokens` (its `draw` signal → `_draw_markers`, under the token children) in three
  passes — shadows → tails → portraits; a raised token (`z_index` > 0, the picked pilot) draws its disc last.
* Spot positions were first placed by eye on plausible buildings of each picture; tune them in the editor.
* **Facility spots** (`Spot_Fac_*`, names = `facility_defs.csv` `spot`, team maps only — the stadium has none and no
  `%Facilities` layer): the tail tip of that facility's research bubble (body ~104 × 124 above it). They were placed
  so no two bubbles overlap (|dx| ≥ 108 or |dy| ≥ 120); a bubble near the top edge is clamped down over its spot.
* The week screen instances the map with `BaseMap.create`, names it `BaseMap_Team` and mounts it on
  `WeekMapSection` `%MapHolder` (`BaseMap.mount`). On the weekend `STADIUM` / `PRESS` stages it instances
  `BaseMap.create_stadium()` instead (`BaseMap_Stadium`) and stands all five pilots on
  `SPOT_TEAM_ROOM` (Saturday) / `SPOT_BOOTH` (Sunday morning) / `SPOT_PRESS` (Sunday afternoon).
* The F6 preview of any map scene shows five random pilots (portraits, `PilotImages.circle_for`, no mobs) on random `Spot_*` markers (not `Spot_Fac_*`), the first 5 / 3 / 1 / 4 / 2 of them on one shared spot per round, no facility bubbles.

## Time of day (`Lighting`, `BaseMapLighting`)

* `hour` 0 … 24 (inspector-scrubbable in the editor, it is `@tool`). The sun rises at `SUNRISE` 6, sets at `SUNSET` 19,
  peaks at `MAX_SUN_ELEVATION_DEG`; its ground azimuth sweeps 180° centred on `noon_azimuth_deg` (Gehenna 70 = noon
  shadows fall left, like the art's baked ones). The whole map takes `TINT_KEYS` (dawn / day / sunset / night blue).
* Code adds (no owner → never saved) `Lit` = a copy of `Art` drawn with `BaseMapLighting.gdshader`, and two SubViewports
  at `RES_SCALE` 0.5: `NormalView` (world normals, ground = up) and `ShadowView` (cast shadows white, building faces masked
  black, so shadows only lie on the ground). The lighting is **relative** to the baked art: the ground keeps its
  brightness, walls brighten / darken with the sun (`normal_strength`), shadows darken (`shadow_strength`); both fade out at night.
  A non-picture `Art` (the stadium ColorRect) gets the material itself at runtime → tint only.
* **Projection**: `cam_azimuth_deg` 45 / `cam_elevation_deg` 25 = the art's camera; it converts a wall edge's screen
  direction into its ground normal and the sun's ground direction into the shadow's screen direction.
  Shadow length is capped at `MAX_SHADOW_RATIO` × height (low sun).
* **Buildings** (`BaseMapBuilding`, a Polygon2D): draw the polygon on the **roof** as seen on the art, set `height` = wall
  height in screen px. Walls = the roof edges facing down on screen, hung `height` down; footprint = roof moved down
  `height`; shadow = convex hull of the footprint and the footprint pushed along the sun. The editor draws the derived walls
  (blue) and footprint (dashed yellow); `Lighting` re-reads the shapes every 0.4 s in the editor. A non-box building = several
  nodes (a tower on a wing). **Overlaps follow the scene order**: buildings are drawn (editor and the normal / face-mask
  views) in `Buildings` child order, a later sibling over an earlier one — a wall hidden by a roof in front gets that
  roof's lighting. Put buildings in front further down; the 9 drafted maps start sorted back to front (footprint bottom). All 10 team maps' shapes were **drafted by eye** (2026-10; Gehenna by hand, the other 9 from zoomed grids) — to be refined.
* API: `BaseMap.set_hour(h)`, `play_hour(from, to, time)` (to past 24 = through the night), `is_animating()`, `finish_animation()`.
  The hub map has no clock driver and stays at the default `hour` 12.

## Roads and walking (`Roads`, `BaseMapRoads`)

* Draw `Line2D` children of `Roads` along the roads (`closed = true` for a loop). Points closer than `SNAP` (12) merge,
  a line end on another line joins it (T), crossing lines join at the crossing. Editor dots: green = junction,
  red = dead end. Every team map's roads were **drafted by eye** (2026-10; all token spots ≤ 40 px from a road, one connected graph per map) — to be redrawn by hand. The stadium has none (straight-line walks).
* `walk_from(prev_state, max_time, delay)`: every placed token whose key is in `prev_state` (`token_state()` of the same
  map, key → `{ground, vec}`) walks the A* route from its old point to its new one at `WALK_SPEED` (300 px/s, at least
  `WALK_MIN_TIME`, at most `max_time`); like the battlefield glide, the seat offset `vec` blends on the way (portraits may
  cross mid-walk). Without roads: straight line.
* F6 preview of a map scene: a demo loop — every 3.5 s each pilot walks to a new random spot and the clock moves through
  8 → 11 → 15 → 18.5 → (night) → 8.
