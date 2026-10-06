# Rendering Module

## BattleRenderer.gd
`extends Node2D` — child of BattleSim at position (0,0).

Owns all `_draw()` logic. BattleSim calls `renderer.queue_redraw()` whenever state changes.
Reads all state from `_bs` (the BattleSim parent).

### Draw pipeline (called from `_draw()`)
-1. `_draw_field_outline()` — **battlefield (전장) outline** (white 4px, `FIELD_OUTLINE_COLOR` /
   `FIELD_OUTLINE_WIDTH`). Treats every cell with a tile as one mass and draws **only the outer
   contour**: an edge is outer only when there is no valid cell across it (`_neighbor_across_edge`
   sentinel). The outer edges are joined vertex-to-vertex into closed loops (`_field_outline_loops`,
   vertex keys rounded to 0.1px) and drawn in one `draw_polyline` — individual `draw_line` calls leave
   notches at every 120° bend of a thick line. Drawn first so the capture fills · camp outlines sit on
   top. Inner edges where neighbours touch have no line, so **the tile PNG
   (`resources/images/tiles/hexa-tileset.png`, row 0, 4 hex types) also paints only the face with no
   border**, and is drawn 1.5px larger (61.5) than the real 60px radius so it overlaps its neighbours —
   drawn exactly to size, linear filtering shaves the edge alpha and leaves grey seams between cells
   (with 0.75px a measured (실측) 236/255 line remained).
0. `_draw_front_line_overlays()` + `_draw_captured_tile_overlays()` +
   `_draw_jungle_camps()` — overlays **where growth-point (성장치) income comes from** on the tiles.
   The front line (전선) is a thin gold **outline** (per lane, between both teams' living foremost turrets (포탑);
   `SimulationCore.front_line_cells`), and a camp (캠프) is that cell's **tile outline**.
   Income comes from position, and if that position isn't visible you can't tell why you're falling
   behind, so it's drawn. Captured jungle tiles already paint the face, so both are shown as outlines only
   so the colours don't compete, and the camp check goes through **the same function** as the simulator
   (`camp_charged(cell)`), so the visible camps and the camps that get eaten can never disagree.

   **The outline does not distinguish ownership — if charged, it's bright yellow, and that's all**
   (`CAMP_LINE_COLOR`, independent of ownership). At one time camps on enemy-owned cells were drawn
   separately in dark amber (`CAMP_LINE_ENEMY_COLOR`, **deleted**), but that colour couldn't be told
   apart from "empty", so what read on screen was brightness, not ownership. The tile face already says
   ownership in team colour, so the outline only needs to say one thing: **does this cell still have
   growth points left right now**.

   **Empty cells get a shade** (`CAMP_SPENT_TINT`, black α 0.34, drawn **before** the outlines so it
   doesn't eat the lines of neighbouring charged cells). The outline merely vanishing makes "not eaten
   yet" and "just eaten" the same picture — dropping one step of brightness lets you read from colour
   alone where the jungler should go, and when respawn (`JUNGLE_CAMP_RESPAWN_TURNS`, const.csv) runs, the shade lifts and the yellow
   outline returns.

   **Camp outlines join into masses.** There is one condition for drawing an edge — the neighbour across
   that edge must **not be a charged camp**. So when two camp cells touch, the shared edge drops out on
   both sides and only the outer contour remains, and if one side of the jungle is fully charged, that
   whole mass reads as a single outline. With a single colour, `_camp_mark_kind` (ours 1 / enemy's 2)
   was **deleted** as well.

   **Edge ↔ neighbour mapping is solved geometrically, not with a table** (`_neighbor_across_edge`):
   it matches the direction from the centre to the edge midpoint against the direction to the neighbour
   cell centre. Hex offset coordinates have different neighbour offsets for odd/even columns (this repo
   already suffered once from a sign bug — `hex_grid_coords`), so a hand-written table is an easy place
   to be silently wrong. Headless check: on all 14 camp cells, the six edges map **one-to-one** to the six
   neighbours.

   It used to put a small **diamond** in the middle of the cell (ours = filled, enemy's = hollow). A
   diamond is an object *inside* the cell, so it competed for space with the jungler's portrait (초상화), and even
   when three or four camps were connected they scattered into three dots, so "this side's jungle is
   entirely left" didn't read at a glance.

   **`_draw_objectives()` was deleted.** It was the section that printed the objective name and remaining
   turns on the two left/right neutral cells. When those two cells went back to being ordinary jungle
   cells (camp outline · capture fill colour · portraits already use that cell), the two lines of text
   became a fourth guest. The clock moved to the top panel — `ui/ObjectiveTimer.gd` (left Herald (전령) /
   right Dragon (용)). `_draw_centered_text` lost its only consumer and was removed with it.

   **`_draw_cell_badge()` was also deleted.** It was the section that printed `x3` / `2v1` in the middle
   of the tile when several stood on one cell. Since everyone got their own hex slot (no overflow), the
   portraits already told the headcount individually, and that badge took the middle of a cell that had
   just returned to jungle, competing with the camp outline · capture fill colour.

   **The jungle start (정글 시작) pick dim (`_draw_jungle_pick_dim`) was added.** While `JungleStartOverlay` is
   open before the opening (개시), it **covers every cell you can't drop on** (non-jungle cells + **opponent-owned
   jungle**) — the definition of the cells left bright is taken directly from the drop targets
   (`JungleStartOverlay.active_cells`), so droppable cells and bright cells come from the same list.
   Drawn **after** the camp outlines and **before** the cell highlights. The cell highlight
   (`_draw_jungle_start_zones`) is green for every droppable cell, gold for the cell under the marker /
   the chosen cell, and on top of that the **path** from HQ to that cell
   (`_draw_jungle_start_path`, gold up to the start cell + sky blue for the 6 turns after arrival, a number pill on each cell where a turn ends — only the number of the cell the marker sits on is drawn after the marker by `_draw_jungle_start_marker_badge` as a badge at the bottom right of the face) is laid
   under the marker. During that window the allied (아군) jungler is drawn **at the position the overlay decides**
   (`JungleStartOverlay.marker_pos` — under the finger / chosen cell / HQ slot) **with no
   tail** (`_draw_pilot_cell`). In the same
   window **only the jungler's battlefield portrait remains**
   (`_hidden_during_jungle_pick` — the other nine are still crowded at their HQs, and faces bunched
   into two clumps would only hide jungle ownership · camps · the dim). Seat assignment
   (`_solve_slots`) reads the same list, so hidden people don't take a slot.
1. `_draw_hq_hp_bars()` — green HP bar under each HQ once any T2 in their team is destroyed
2. `_draw_turret_hp_bars()` — yellow HP bar above each living turret (T2 hidden while own-lane T1 alive). While being hit it shakes along by `BattleSim.turret_hit_offset(td)` — the turret sprite (`Building` node) isn't drawn by the renderer but shaken directly by BattleSim, so if only the bar stayed put the two would drift apart.
3. Per-cell pilot rendering via `_draw_pilot_cell()` — pilots render OUTSIDE the tile, on a hex ring of 6 slots around it, with a team-coloured triangle behind them whose apex points to the tile centre (speech-bubble tail). **Seats are not solved here** — `_build_pilot_render_layout()` at the top of `_draw()` assigns the whole battlefield at once, and the dim overlay · hit testing · FX coordinates all read the same table
4. `_draw_pilot_popups()` — damage number / MISS · growth-point popup floating text, drawn **last** so nothing covers it

The minion / lane-line / minion-progress visualizations were removed alongside
the minion concept. Tile background colouring (lane vs jungle vs neutral) is
owned by the TileMapLayer in `BattleField.tscn`, not by the renderer.

### Where portraits sit — horizontal rows first (`_row_blocks` → `_pick_row_seats`)
`_solve_slots()` first seats team blocks **in a single horizontal row below (team 0) / above (team 1)
the tile**. Both the row spacing and the distance from the tile are `d = diameter + MARKER_GAP`
(= hex ring 0 radius, 91px), so faces don't touch either within a row or between rows.

| Headcount (same team, one cell) | Seats |
|---|---|
| 1 / 2 / 3 | One row below (enemy above), centred (2 = x ±45.5) |
| 4 / 5 | A row of 3 + 1 / 2 in the outer row (`ROW_CAP` 3) |

- **No exception for the HQ cell either.** The allied HQ cell and the allied turret cells adjacent
  to it (`_is_home_zone`) used to raise every allied portrait above the tile (`HOME_TOP_CAP` 5);
  that rule was **deleted** — allies prefer below on every cell.
- **If it overlaps a neighbouring cell's markers**, (1) try shifting the whole row **left/right by half
  a cell (d/2)** (0 → ½ → −½ → 1 → −1, first direction toward the lane bias `_block_seat_bias` — left if
  no bias), (2) if still blocked, try again in the same order **one row further out** (2d, 3d from the
  tile). If all three layers (`SLOT_RINGS`) are blocked, it **falls back to the hex ring layout** below —
  that section's window · seat-chart rules are now used only in this fallback.
- **Portraits also avoid other people's tails** (`_repair_arrow_overlaps`). The greedy overlap check only
  looks at portrait vs portrait, so when an enemy on the lower cell stepped aside (−d, up d) to avoid an
  ally (S) on the upper cell, its tail passed diagonally **under** the allied portrait and was hidden. So
  after the greedy pass, blocks are swept once in assignment order, and any horizontal-row block whose
  member portraits (`marker_outer_radius`, including HP ring · outline) touch **another block's tail
  outline** (`_arrow_outline_polygon`) is re-seated with the `strict` check — portrait ↔ portrait,
  portrait ↔ others' tails, **my tail ↔ others' portraits** (`_seat_crosses_arrows`). The order is the
  same row candidate order as above, and if there's no clean seat it is left as-is. The one that moves
  is **the portrait covering the tail** (measured: upper cell 1 ally + 2 enemies, lower cell 1 enemy →
  enemy stays at (−91, +49), the ally moves from S to **bottom right (+45.5, +91)** — even with a left
  lane bias, the left is blocked by an enemy portrait). Within the same block (a back-row tail passing
  under the front row) and hex-ring-fallback blocks are not corrected.
  **The repair never moves a block further out than its original row** (`_pick_row_seats(..., ring_limit)`
  gets the original ring + 1 — it only slides left/right within the same row). Without that limit the
  portrait at the **centre tier-2 tower** (half a row lower than the two side tier-2 towers; the greedy
  pass had seated it fine at ring 0) flew out to ring 2 (273px from the tile) because it grazed the side
  tails by a few px, stretching its tail to the top of the screen. A tail side slightly covered is far
  better.
- A solution entry is `{"cell", "vec" (offset from tile centre), "ring" (which layer),
  "grp" (same horizontal row number, -1 for fallback)}`. The old `"slot"` integer is gone, and the
  glide starts a new interpolation based on whether `to_vec` changed.
- Emphasis (`_pilot_spread`) spreads **the same row (grp) by one factor** — row neighbours are d apart
  horizontally, so pushing just one person by 1.5× slightly overlaps the neighbour at ≈101px (≈106px
  needed).

### Fallback — 6 hex slots around the tile
`_build_pilot_render_layout()` assigns **the whole battlefield at once**. Seats lie on rings extending
in 6 directions from the tile centre (`HEX_DIRS` = same directions as hex neighbours, array order is
**clockwise** on screen N→NE→SE→S→SW→NW), with radius `_ring_radius()`:

```
ring_radius(ring) = (지름 + MARKER_GAP) × (ring + 1)      # (diameter + MARKER_GAP); 91px, 182px, 273px
```

**Neighbouring slots are 60° apart, so on a ring of radius d the distance between neighbouring slots is
exactly d** — so using diameter + gap directly as the radius means portraits within one ring never
touch, and the outer rings are multiples of it, so the same spacing holds radially too.
`SLOT_RINGS` (3) = 18 seats, so even if all 5v5 (10 pilots) crowd onto one cell there are spares.

**The six seats are laid out as one left→right row, not by angle** (`SEAT_ROW_DOWN` /
`SEAT_ROW_UP`). The middle three seats are that team's **half**, and the very middle (`SEAT_BASE` = 2)
is the base direction:

```
팀0(아래 진영)   NW   SW  [S]  SE   NE   N     # team 0 (bottom side)
팀1(위 진영)     SW   NW  [N]  NE   SE   S     # team 1 (top side)
```

Both are the hex ring wound in one direction (team 0 counter-clockwise / team 1 clockwise), so **seats
that are consecutive in the seat chart are consecutive on the ring too** — a block seated in one window
stands side by side on screen without gaps. The point where the seat chart is cut per team is that
team's worst seat (N for team 0, S for team 1).

**The unit of assignment is a block, not an individual.** Within one cell, pilots with **the same base
direction** (= same team) are grouped into one mass (`_slot_blocks`) and take **`n` consecutive seats of
the seat chart = a window** as a whole:

1. Pick the **base direction** — see the *Base direction* section below. The team decides it (team 0 S / team 1 N).
2. Scan window candidates in order of preference (`_seat_windows`) and take a window that (a) uses seats
   not yet used in the same cell and (b) **does not overlap any marker already placed**. If blocked,
   **shift the whole window one seat sideways** and try again.
3. If every window on that ring is blocked, the **whole block** moves to the outer ring (it doesn't split
   at the ring boundary and sit across two layers). It moves that much farther from the tile and the
   arrow gets longer, so the more crowded the cell, the more the arrow says "which tile".
4. If all three rings have no room, it falls back to finding seats one by one (`_pick_slot` — a
   one-person window, so it uses the same chart) — being drawn comes before standing side by side.

The order of window candidates (`_seat_windows`) is ranked by three keys: **(1) fewer members outside
their own half → (2) window centre closer to the base direction → (3) windows on the side the block
leans toward.** (1) keeps "the bottom side stays below", (2) produces "slide one seat at a time when
blocked", and (3) is a deterministic tiebreak for remaining ties.

**The direction of (3) is set by the lane** (`_block_seat_bias`) — right-lane blocks prefer the
**right** window, left-lane blocks the **left** window, and centre lane · jungler · mixed-lane blocks
have no bias (= left, as before). It used to have no direction, so **every block leaned left**; the
right lane often has two, supporter + sniper, on one cell, and that 2-person window sat on the left
(`SW S` for team 0), so **it collided with the jungler marker passing through the left neighbouring cell
and the whole block got pushed out** — on screen the two portraits looked like they turned around for
no reason. Now the right-lane pair sits at team 0 `S SE` / team 1 `N NE` (measured: fixed throughout
laning, kept even when both teams stand on the same cell), and the left-lane pair at `SW S` / `NW N`.
The bias enters **only in the tiebreak slot**, so a pilot standing alone sits in the middle (team 0 `S`)
regardless of lane, and the lane only decides which way it steps aside when that seat is blocked
(right lane x1: S blocked → **SE**; before it was SW).

**Why windows — a block must step aside as a whole.** With the approach of picking empty seats one by
one in priority order, when **only A's seat** of side-by-side A·B was blocked, A jumped over B to the
opposite end — it read not as stepping aside but as **swapping seats**, and the block sometimes got cut
in the middle. Now A·B slide one seat together as a window, keeping both left-right order and adjacency.
The generation before that (clockwise rotation by angle) additionally dragged the bottom side **above**
the tile — see the *search order* passage above.

Blocks split **only when base directions differ**, and the team decides the direction, so **a cell has
at most two blocks — one per team**. The same team always sits side by side as one mass. Block order is
first-appearance order (= `_bs.pilots` spawn order), so it doesn't jitter frame to frame.

The key point is that (b) **also looks at markers on other cells**. Neighbouring tile centres are only
140px apart while the portrait diameter is 85px, so if two vertically adjacent cells pick slots facing
each other (S of the upper cell, N of the lower cell), the two faces overlap head-on between them — this
was the only structural cause of faces being hidden on the battlefield, happening every time lanes
clashed. Now the later cell sits one seat off clockwise.

Iteration order is the priority (the cell visited first keeps its base direction), so cells are
**sorted by coordinate** (`_compare_cells`), and within a cell the `_bs.pilots` order (spawn order) is
used — left to Dictionary order, a different cell would yield each frame in the same situation and the
layout would jitter.

**A cell's 6 slots are shared by both teams.** That's why `_group_pilots_by_render_cell()` puts both
teams in one array — base directions are opposite per team (team 0 S / team 1 N), so the starting points
don't collide, but if a window gets pushed out of its own half (blocked) or there are more members than
a half (four or more on one cell), one team's block can spill onto the other team's slots. They have to
be solved together in one table to know each other's seats.

**The `+N` overflow circle was deleted.** Every renderable pilot gets its own slot, and from the 7th on
they sit on the outer ring (removed together with `_draw_overflow_circle`).

**No solo exception**: a pilot alone in a cell is laid out exactly like a
stacked one — offset outward with the speech-bubble arrow pointing back at the
tile. The arrow is therefore always present, so the tile a pilot occupies reads
the same whether the cell is contested or not. (The earlier `is_solo` centring +
`_has_crowded_neighbor` override were removed.)

#### Base direction — set by the team (bottom side below / top side above)
`pilot_display_dir_index` is one line: **team 0 = S (below the tile), team 1 = N (above the tile)**.
The side of the screen where your HQ is is your seat, so on any cell **the bottom row is my team, the
top row is the opponent (상대) team**. No exceptions for lanes or junglers.

The base direction is only **the middle of the seat chart**; if that seat is already taken or overlaps
a neighbouring cell's markers, the assignment procedure above **slides the window left/right** to find
a free seat. So when two vertically adjacent cells face each other (team 0's S on the upper cell and
team 1's N on the lower cell come within 42px), the later one steps aside first within its own half.

Measured (calling `_pick_block_slots` directly, tile_center 500,500 · base_r 42.53 · ring0 91.05.
Results are in **seat chart order from the left** = block member order):

| Situation | Result |
|---|---|
| No obstruction | team 0 x1 **S** / x2 **SW S** / x3 **SW S SE** / x5 **NW SW S SE NE**, team 1 x3 **NW N NE** |
| team 0 x2, left (SW) blocked by a neighbouring cell's marker | **S SE** — both one seat right |
| team 0 x2, right (S) blocked | **NW SW** — both one seat left |
| team 1 x2, NW blocked / N blocked | **N NE** / **SW NW** (mirror of the same rule) |
| team 0 x3, SW blocked / SE blocked | **S SE NE** / **NW SW S** — all three slide together |
| team 0 x1, S blocked → S+SW blocked → entire bottom half blocked | **SW** → **SE** → **NW** (the only time it crosses to the top) |
| team 1 x1, N + NW blocked | **NE** |
| Upper cell team 0 (S) ↔ lower cell team 1, 140px apart | The lower cell's N·NW·NE all overlap at 78.9px, so x1 = **SW**, x2 = **SE S**. This is the case where the top half is physically fully blocked |
| 10 on one cell | team 0 block on the inner ring NW·SW·S·SE·NE, team 1 block on the outer ring SW·NW·N·NE·SE |

**Deleted — movement-direction-based placement.** It used to "clear the side you're heading to and
stand on the side you came from": lane pilots sat opposite the next waypoint direction
(`_peek_waypoint`), junglers opposite the direction they came from via `PilotData.prev_grid_pos`
(`_pilot_travel_dir` → `_nearest_dir_index`). Alignment within the same lane and segment was right, but
**the same team sat on different sides per segment** (for the right lane: bottom left before the T1
turret → then below → bottom right after the enemy T1 turret), so there was no basis at all for reading
teams as top/bottom on screen. The three functions and `PilotData.prev_grid_pos` (+ 4 update sites in
BattleSim) were removed together — if it ever needs reviving, see commit 64bec06.

Each pilot draws its own arrow (`_draw_arrow_to_tile`) — the tip is the
**glide-interpolated tile centre** (`_marker_center`), so the tail slides with
the portrait instead of pointing at the destination first (next section).

**FX offsets are applied to the tail tip too** (`_pilot_anim_offset` — return-to-base (복귀) rise /
descent, death rise, hit shake). Previously only the portrait rose while the tip stayed at the tile
centre, so the tail **stretched** by the rise distance. Now the tail stays attached to the portrait and
follows as a whole, with length · direction unchanged, and the only thing that re-aims the tail at the
tile is **turn movement (glide)**.

### HP ring — shield as extra HP (`draw_hp_ring`, static)
One full turn of the ring = `hp_ring_span` = `max(max_hp, hp + shield)`. On the empty ring (dark
backing), HP (team colour `TEAM_RING_COLORS`) is followed directly by **shield (`SHIELD_RING_COLOR`,
light grey)** on the same ring at the same thickness, and the `HP_TICK_STEP` (25) dividers continue at
the same spacing through the shield portion. When HP + shield exceeds max HP, that sum becomes one full
turn and the HP portion gets correspondingly shorter (the shield is never clipped off the ring). The old
cyan shield band outside the ring was deleted. **The engage stage portraits (`EngageArena._draw_unit`)
are drawn with this same static function** — the single source that keeps the two screens' rings from
diverging. The card-preview blink (`attack` / `restore`) uses the same ring layout too
(`_draw_ring_blink`).

### HP ring chips — the lost portion grows in place and fades
The ring reads `pilot.hp` / `.shield` directly and simply gets shorter on the frame damage lands, so
**the portion just lost** is erased in place (`_advance_hp_chips` / `_draw_hp_chips` → static
`hp_loss_segments` / `draw_hp_chip`). Detection is done by the renderer comparing `_hp_seen` (last seen
`Vector2i(hp, shield)`) with the current values — damage paths (battlefield fights · attack cards ·
turrets · arena · skills) are scattered, so hooking the call sites would miss some. Segments are measured
on **the ring layout before the loss**, giving up to two chips: HP `[hp1, hp0]` and shield
`[hp0 + sh1, hp0 + sh0]` (light grey). Chips **do not fly outward** — the ring radius stays put, and only
thickness and arc angle grow about the chip's middle over `HP_CHIP_DUR` (0.45s) up to `HP_CHIP_SCALE`
(1.45×, ease-out) while fading with alpha `1 − k²`. The HP chip colour is a brightened team colour + one
black outline. **Battlefield-side detection is deferred while the engage stage is up** — the stage
portraits pop the same chips themselves (`EngageArena._advance_hp_chips`), and after the stage lifts the
total lost on the battlefield marker drops as one chip. `clear_popups()` (restart) clears them too.

### Pressing a portrait — grows and goes on top (`press_marker` / `release_marker` / `marker_at`)
Input is `ui/MarkerTouch.gd`. A pressed portrait grows to `PRESS_SCALE` (1.3) over `PRESS_TWEEN_SEC`
(0.08s) and returns on release. **The top one (`_top_pilot`) stays on top until another portrait is
pressed** — `_draw_pilot_cell` skips that pilot and `_draw_pilot_groups` redraws it, shadow included,
at the end. So a face that was buried under a neighbouring cell's marker comes up on top, and its
shadow falls over the neighbour so the stacking reads.

The scale affects **drawing only**: `_pilot_draw_scale` = targeting emphasis × press — read by the
portrait · tail · shadow · `pilot_marker_radius` (hit radius). Layout (`_pilot_spread`) reads only
emphasis — if neighbours stepped aside on every press, the group you were trying to look at would shake.
`marker_at(pos)` checks the top portrait first; otherwise it's the living pilot whose drawn marker centre
is closest (pressing the exposed part of the buried one of two overlapping faces usually lands closer to
that one's centre).

### Marker glide — portraits don't teleport
**The single on-screen marker coordinate is interpolated as a whole.** Previously only cell movement
was tweened (`PilotData.anim_move_t/dur`, lerp between cell centres) and **slot changes were applied
instantly**. One slot is 91px, moving to the opposite side is 182px, so **teleports larger than the
distance between cells (140px)** got mixed in every turn, and a pilot who merely stepped aside because
someone arrived next to it got no tween at all and just jumped.

Now the marker coordinate is split into **centre + slot vector** and the two are pushed separately
(`_sync_glide` → `_eval_glide`, state in the `_glide` dict):

| Component | What | When |
|---|---|---|
| `center` | Traverses the **polyline** through the cell centres passed, by arc-length ratio | `BattleSim.ANIM_MOVE_DUR` (0.30s), smoothstep |
| **Angle** of `vec` | Slot direction. Turns the short way | **Same beat** as above |
| **Length** of `vec` | Ring (radius) | **After arrival**, `MARKER_RADIUS_SETTLE_SEC` (0.15s), ease-out cubic |

- **It bends along the path.** `PilotData.anim_move_path` brings the cells actually stepped on this time
  (`SimulationCore.resolve_movement` appends per lockstep round, and advance cards have
  `anim_pilot_move` chain the same frame's steps). So a `move_range` 2 move and `advance:N` don't cut past
  the middle cells — measured: the midpoint of a 3-cell path deviates **121.5px** from the straight-line
  midpoint. The renderer **clears** the path as soon as it reads it (`_screen_path`); otherwise the next
  turn's movement would rewind to the old start.
- **The angle turning on the same beat as the centre is what "the arrow turns together with cell
  movement" means.** If the ring is unchanged, the length interpolation is the identity, so the arrow
  length doesn't change by a single pixel throughout the move and the tail hangs on the portrait and
  slides as a whole. Only when **pushed to an outer ring** on entering a crowded cell does it lengthen
  after arrival — if the length also changed mid-move, what moved would blur.
- **The curve is smoothstep** — it stops at both ends. The old move tween's ease-out cubic was a choice
  from when slots jumped anyway, so an abrupt start was less noticeable, but that curve already covers
  15% of the distance (measured **24.98px**) on the first frame at 60fps — FX meant to remove teleporting
  was jumping once at every start. After switching to smoothstep, the first-frame displacement is
  **0.5~0.7px**, and one move flows over 40 frames.
- **Where teleporting is right, it snaps** — for return-to-base / respawn (`anim_recall_phase != 0`) the
  fade covers the position change, and on death (`anim_death_phase != 0`) the body must stay pinned to
  the cell where it fell. Gliding would send a vanishing body across the screen.
- `_sync_glide` discards the state of pilots dropped from the layout (death exit, roster replaced by
  restart).

The only thing that advances time is `_advance_glide` in `_process`. So no matter how many times
`_build_pilot_render_layout()` is called in one frame (draw · hit test · particle coordinates · popups),
the FX doesn't rewind. `BattleSim` no longer holds a move timer, so the renderer also kicks the redraws
in this window.

**Deleted — arrow inertia machinery.** `_arrow_hold` / `_arrow_settle_t` /
`_arrow_vec_now` / `_arrow_frozen` / `_arrow_aim_point` / `_advance_arrow_settle` /
`_prune_arrow_state` / `_lerp_polar` / `ARROW_SETTLE_SEC` are all gone. That was machinery that froze
the tail during movement to hide "the portrait is on the start cell but only the tail points at the
destination cell"; now the portrait actually slides, so the tail can simply follow.

#### Arrow length is derived from distance
The tip of `_draw_arrow_to_tile` is **always just short of the tile centre**
(`dist - tip_inset`). It used to be derived from the marker radius (radius + 24px), but markers on an
outer ring are twice as far from the tile, so with that length only a short triangle remained in mid-air
and which cell it was about disappeared. Deriving it from distance makes the arrow longer the farther
away it is, so "sits a bit farther away, but the cell it points at is clear" holds. It does not stab past
the centre — if it did, it would read as pointing at the next cell.

#### Targeting emphasis also affects layout (`em`)
`_compose_positions` multiplies **a per-pilot factor** (`_pilot_spread` = the max of its own
`_pilot_emphasis_scale` and the factors of the **inner-ring** pilots on the same cell, i.e. 1.0 or
`TARGET_EMPHASIS_SCALE` **1.5**) into that pilot's slot vector. Enlarging only the portrait breaks two
things at once:

1. **Sideways overlap.** If only the diameter grows while the spacing stays, the faces of two or three
   people on one cell cover each other, and at exactly the moment you need to aim, you can't tell who's who.
2. **The arrow disappears.** When the marker grows, the portrait swallows up to the tile centre and the
   arrow is completely buried behind the portrait — of all pilots, only on the emphasised (= being aimed
   at right now) one.

The ring radius as a whole becomes `em` times larger, so **spacing and distance widen together at
once** — the ring definition (`diameter + gap`) is itself the non-overlap condition, so multiplying by
`em` keeps that condition (85.05 × 1.5 = 127.6 needed vs 91 × 1.5 = 136.5 available), and the amount the
group backs outward is exactly the room for the arrow to lengthen. The arrow tip is derived from distance
anyway (section above), so there's nothing extra to scale.

**Non-emphasised pilots stay put.** Previously every pilot on the cell (both teams) was multiplied by
that cell's max factor (`_group_emphasis`, deleted), so even holding an ally-only card pushed the enemy
portrait on the same cell (base seat N) upward with its size unchanged. Neighbours on the same ring don't
overlap even when mixed — they're 60° apart, so with only one side at 1.5× the centre distance is
√1.75 × 91 ≈ 120px vs a required 1.5r + r ≈ 106px. **When the inner ring grows it covers the outer ring**
(in the same direction only 0.5d separates 1.5d and 2d), so only the outer ring inherits the inner
ring's factor. The screen clamp (`_clamp_group_on_screen`) also pushes **only markers with factor > 1**
as one mass.

**Slot assignment itself ignores `em`.** The overlap check runs on pre-emphasis coordinates, and `em`
is multiplied into the radius only after assignment — if emphasis were included, the battlefield's slots
would be re-solved every time you pick up a card, and the layout would look entirely reshuffled.

**The glide also ignores `em`.** What is interpolated is the pre-emphasis centre + slot vector, and `em`
is multiplied on top every frame — so while the emphasis fully grows in `EMPHASIS_TWEEN_SEC` (0.05s),
the 0.30s glide doesn't intrude and make it sluggish. The axis of multiplication is **the glide
centre**, not the tile centre: inflating a pilot mid-crossing about the destination tile would fling it
out about a point it hasn't even reached yet.

**If it goes off-screen, the whole cell is pushed back in** (`_clamp_group_on_screen`; all of both teams
on one cell are one group). Left alone, a 2~3-person group on an edge lane spread by emphasis gets
clipped off-screen, and a clipped face can be neither pressed nor dropped on. Pushing markers
individually would collapse the hard-won spacing and overlap them again, so it's a **parallel
translation**. Each arrow still points at its own tile, so who is on which cell is preserved. Measured
(1080×1920, `SCREEN_EDGE_PAD` 6, back when the factor was 2.0): a 3-person group at tile centre x=950 at
`em=2` folds from a natural width of 617..1283 → **495.6..1074**, and the group at x=120 sticks to the
left edge at 6px. Now that the factor is down to 1.5, folding itself is much rarer — half the reason this
section exists was to get rid of that folding.

Radius is FIXED per pilot (`PILOT_RADIUS_BASE = 31.5` × `HexGrid.DISPLAY_SCALE`
= 42.5px at draw time, so it tracks tile size) regardless of how many pilots
share the cell — circles do not shrink for multi-pilot stacks. What a crowded cell
absorbs is not size but **distance**: past 6 they go to the outer ring, and the
arrow gets that much longer. HQ HP bars and cell badges are also scaled by
`HexGrid.DISPLAY_SCALE` to stay proportional to the bigger tiles.
(Tiles themselves now use `HexGrid.FIELD_SCALE` = 90% of `DISPLAY_SCALE`, so
portraits are relatively larger than the tiles they sit on — the field shrank,
the portraits did not.)

(`PILOT_FONT_SIZE_BASE` was a leftover from when a role letter was printed inside the slot, and was
**deleted** when portraits came to fill the whole slot.)

HP is shown as a circular progress ring hugging the outside of every pilot's
circle (radius + 3 px, 4 px wide). The dark backing ring traces the full
circumference; the green fill ring sweeps clockwise from the top
(`-PI/2`) by `hp / max_hp`. Because each ring sits on its owner's circle, the
old "solo only" gate is gone — every drawn pilot has its own HP ring. The
guerrilla dash ring is pushed out to radius + 9 px so it stays clear of the HP
ring.

### Coordinate helpers
All drawing uses `_bs.cell_center(pos)` which dispatches to `hex_grid.hex_to_screen()`.

### Pilot animation rendering
`BattleSim` mutates per-pilot animation timers on `PilotData`
(`anim_move_*`, `anim_shake_*`, `anim_recall_*`); the renderer just reads
them each `_draw()`:

- **`_is_renderable(p)`** — the grouping gate. A pilot is drawn while `alive`
  **or** while an off-field animation is still playing: the death FX (전사 연출)
  (`anim_death_phase != 0`) and the fade-out half of a low-HP recall (저HP 귀환)
  (`anim_recall_phase == 1`). This is deliberately not a plain `p.alive` test —
  both states flip `alive` to false *before* their animation runs, and the old
  gate made a killed pilot vanish on the same frame the damage landed.
- `_render_cell(p)` — returns `anim_recall_orig` while a pilot is in recall
  fade-out, `anim_death_cell` while the death FX plays, otherwise `grid_pos`.
  Pilots are grouped/team-laid-out by this so a recalling pilot is drawn at the
  cell they came from until they fully fade out, then "appears" at HQ for the
  descent fade-in, and a fallen pilot stays on the cell they fell on.
- `_pilot_anim_offset(p)` — sums recall rise/descend (`ANIM_RECALL_RISE_PX`),
  death rise (`ANIM_DEATH_RISE_PX`, phase 2 only) and damage shake (decaying
  `sin` jitter). **Attack card FX is not here** — neither the cast light nor the hit shards move the
  portrait; they are only drawn on top of it (the *Attack card hit FX* section below). The old
  lunge (`BattleSim.pilot_lunge_offset`) used to be added here as one term.
  **Cell movement is not here** — the marker coordinate itself slides via the glide (the
  *Marker glide* section above), so adding it here again would double it.
- **The hit shake strength is set by whoever shakes** — it comes in via `PilotData.anim_shake_amp`
  (battlefield auto fight `ANIM_SHAKE_AMP_PX` **6px** / attack card hit
  `ANIM_SHAKE_CARD_AMP_PX` **20px**). When the renderer read a single constant, only one of the two
  could be right. **The frequency is fixed and the number of oscillations follows the duration**
  (`cycles = 4 × dur / ANIM_SHAKE_DUR`) — if the oscillation count were fixed at 4, an instruction to
  shake longer would become "shake slower", and the violence would actually vanish. Measured: battlefield
  6px → max 5.63px · 4 cycles, card 20px → max 19.13px · 5.8 cycles.
- `_pilot_anim_alpha(p)` — 1.0 → 0 during recall phase 1 **and** death phase 2,
  0 → 1.0 during recall phase 2 (and respawn fade-in). Multiplied into every
  per-pilot draw call (circle, ring, role text, HP ring, speech-bubble arrow)
  via `_alpha_mul`.
- **Death tint** — while `anim_death_phase != 0` the team colour and the
  portrait are both multiplied by `BattleSim.ANIM_DEATH_TINT`, so the fallen
  pilot reads as dimmed rather than merely faded. Phase 1 holds at full alpha
  (waits while dimmed), phase 2 fades it out while it rises.

Note that a pilot mid-death
still occupies a layout slot, so a fallen body shifts the living pilots in its
cell for the ~1.45s the animation runs; `pilot_marker_positions()` reads the
same solve, so hit-testing never disagrees with what is on screen.

**A white circle is laid behind the portrait** (`_draw_pilot_circle`). Some `*_circle.png` files have
transparency even inside the circle (measured: some of the 40 images have alpha holes inside the circle),
so drawn as-is the tile colour behind shows through the face — on captured jungle tiles the pilot got
tinted the same colour as the tile. The circle art itself is **inscribed** in the square, so a
`draw_circle` of the same radius fits exactly, shrunk by 1px so no white rim pokes out past the
anti-aliased edge. Its colour takes **the same** tint·alpha as the portrait (death dim / return-to-base
fade), so the background never stays bright on its own.

**Marker exterior — black disc · outline · pointed tail · shadow.** Behind the portrait's white circle, a **black disc** covering out to the marker's outermost edge (`marker_outer_radius` = portrait + `HP_RING_GAP` + `HP_RING_W` + `MARKER_OUTLINE_W`) is laid first — the tile doesn't show through the gap between portrait and ring, and the disc's outer band becomes the HP ring's thick black outline as-is. The tail (`_arrow_fill_polygon`) is a triangle with a **pointed tip** (width = `ARROW_WIDTH_SCALE` 90% of the old `clamp(radius × 0.9, 10, 18)`), and under it lies a black triangle inflated by the same thickness (`MARKER_OUTLINE_W`) **with sharp corners kept** (`_arrow_outline_polygon`) — the two share axis · length via `_arrow_axis`. An exact miter tip extends without bound as the angle narrows (long tails), so the outline tip sticks out only up to `ARROW_TIP_MITER_MAX` (10px) past the fill tip, and the black rim near the tip thins accordingly. The old round tip (`ARROW_TIP_ROUND` + `_offset_round`'s `JOIN_ROUND`) was deleted. The tail is drawn **before** the disc, so the outline around the circle isn't hidden or broken by the tail. HP 25-unit dividers are `HP_TICK_W` (half the outline). The shadow (`_draw_marker_shadow`) merges the disc + tail outline into one mass with `merge_polygons`, pushes it down by `MARKER_SHADOW_OFFSET`, and paints it translucent black; the shadows of everyone on a cell are laid before the markers. **The edge is soft** — the silhouette is shrunk and inflated with `offset_polygon` into `MARKER_SHADOW_LAYERS` (7) layers between `-MARKER_SHADOW_BLUR/2 … +MARKER_SHADOW_BLUR/2` (16px) and stacked with the same alpha. Inner areas pile up more layers and are darker, fading outward as a gradient, and one layer's alpha is derived as `1 − (1 − a)^(1/N)` so that the sum at the very centre (all layers) equals `MARKER_SHADOW_COLOR.a`. The targeting dim disc uses the same `marker_outer_radius`.

**Cell iteration order is plain `Dictionary` order.** It used to defer cells with a lunge (body slam) in
progress to the very end (`_lunging_cells_last`, **deleted**), because that FX actually moved the
caster's (시전자) portrait onto the target cell — if the target cell was drawn later, the face that dove in hid
behind it. Now the portrait stays in place and only effects are drawn on top, so there are no cells to
defer.

### Hand-card preview (battlefield) · buff banners
`card_phase/CardPlayPreview.gd` decides what to draw (`neon_pilot()` / `field_spec()`) and the renderer
only draws it. While a preview is up, that side's `_process` kicks this renderer every frame, and the
animation clock is also that side's (`anim_time()`).

- `_draw_card_preview_neon()` — **before `_draw_pilot_groups`**. Layered circle glow + white ring
  (white neon) behind the caster marker. Untargeted cards show only this (no dim).
- `_draw_card_preview_field()` — **after the target dim, before the cast light**. `ghost` (a
  translucent portrait at the destination cell's **marker seat** — offset from the cell centre by as much
  as the current marker is — plus path / dotted line. Move cards use `line = false` and stand **only the
  ghost at the centre of the aimed tile**; the old `move_path` cell path + chevrons + arrival ring were
  deleted), `soul` (quadratic Bézier from camp → caster, control point perpendicular, soul icons flowing
  along it), `attack` (the portion of the HP ring about to be cut · shield first, `명중 N%` (Hit N%) ·
  `-damage`), `restore` (HP green / shield grey portion about to fill — measured on the post-apply ring
  layout).
- **Buff banner** `spawn_buff_banner(p, card)` — one line above the marker: rounded-rect card art
  (`draw_textured_rounded_rect` — one `draw_colored_polygon` call on a rounded polygon with UVs) + card
  name. 1.9s; banners on the same pilot stack upward. Drawn last, after `_draw_pilot_popups`. The art is
  uploaded to the GPU first via `BattleSim.prime_texture`.

### Attack card hit FX
One hit of an attack card (`attack:N`) draws on two portraits at once. Both are at the **very end** of
`_draw()`, right before the damage number popups — they must sit on top of the markers but must not
cover the numbers.

**Cast light** (`_draw_pilot_cast_fx`) — a white pillar rising above the caster's portrait.
`BattleSim.pilot_cast_progress(p)` gives that frame's progress (0..1), and height
(`ANIM_CAST_RISE_PX` 54px × k) · width (`CAST_BEAM_W_RATIO` 0.62 of the marker diameter) · alpha
(1 − k²) all come from that one value. **It holds no state** — it asks `PilotData.anim_cast_*` every
frame, so if the caster slides, the light follows. Two pillars (a wide faint one + a narrow strong one)
get one head circle on top; with pillars alone, you can't read how far this frame's head reaches.

**Hit shards** (`spawn_pilot_burst` / `_draw_pilot_bursts`) — `BURST_COUNT` (12) small circles spread
out in all directions from the hit pilot's portrait. **Same structure** as the popups: the coordinate is
fixed at spawn time (shards don't follow the target whether it becomes a corpse or gets pushed) and
`_advance_bursts` advances time in `_process`. Angles are an even split + jitter (`±0.22rad`), and
distance·size are **set once at spawn and stored in an array** — re-rolling `randf()` every frame would
turn spreading shards into dots blinking in different places each frame. `BURST_DUR` (0.18s) must be
shorter than `BattleSim.ANIM_HIT_HOLD_SEC` (0.20s) so the next hit of a multi-hit attack doesn't overlap
the previous hit's debris. `clear_popups()` also clears shards on restart.

### Damage number popup (`spawn_pilot_popup`)
Floating text exclusive to attack cards (`attack:N`). `CardPhaseManager._effect_attack` calls it once per
roll — **MISS** on a miss, **-N** on a hit (명중), **흡수** (Absorbed) if the shield absorbed it all. Colours
are `POPUP_MISS_COLOR` / `POPUP_DAMAGE_COLOR` / `POPUP_SHIELD_COLOR`.

- The coordinate **stays fixed at the marker position at spawn time**. Even if the target falls or is
  pushed in the meantime, the number doesn't follow (and the number plays to the end even after the
  target is gone).
- It rises, decelerating, by `DMG_POPUP_RISE_PX` (46px) over `BattleSim.DMG_POPUP_DUR` (**0.30s**) and
  fades only in the last 40%. This value **must be shorter than one hit's hit FX length (0.32s)** —
  if longer, the numbers of a multi-hit attack stack up in the same place.
- **`DMG_POPUP_STAGGER` (0.18s) is now barely used.** Since each hit got FX running the full two beats
  of cast → hit (0.32s), the popups of a multi-hit attack can't overlap each other in the first place.
  The delay remains only where no FX is attached (legacy cards with no caster).
- `_advance_popups(delta)` runs in `_process`, drops expired entries, and keeps calling `queue_redraw()`
  while any are alive. Restart is `clear_popups()`.
- **Lifetime and height differ per entry** (`dur` / `rise` keys). Defaults are the damage number ones
  above; only the growth-point popup passes its own values — next section.

### Growth-point popup (`spawn_score_popup`)
At the moment growth points rise **by a large amount at once**, a soul icon + white text (thick black outline) `+N.NNk` rises above that pilot's face.
It uses the same array and the same draw path as damage numbers, with only the constants differing —
`BattleSim.SCORE_POPUP_DUR` (**1.10s**) / `SCORE_POPUP_RISE_PX` (**72px**) /
`SCORE_POPUP_COLOR` (white — thick black outline `SCORE_POPUP_OUTLINE_PX`, soul icon on the left `SCORE_POPUP_ICON` = `DeadlockSoulsTurq-28x.png`, stretched to the text height with a black outline `SCORE_POPUP_ICON_OUTLINE_PX` — the static `draw_outlined_icon` lays a black-tinted copy in 8 directions and covers it with the original. The engage result growth line uses the same function). Damage numbers must vanish between consecutive hits (0.32s apart)
so they don't overlap, while growth points, conversely, must linger a beat to be readable. Even if both
appear on one face at once, the growth popup rises higher, so they don't cover each other.

**Size follows the amount gained** (`score_popup_scale(amount)` → the popup entry's `scale`). On the
on-screen number (growth points × 1000), **below 100 (two digits) is the minimum 0.75×**, **1000 and up
is the maximum 1.25×**, with log interpolation in between (300 ≈ 1.0×). It started at 0.5 / 1.5×, but
the range was too wide, so the gap from the original size was halved on both ends. The factor applies
to font size · icon (follows the text height) · text / icon outline · icon spacing together. Constants:
`BattleRenderer.SCORE_POPUP_SIZE_MIN/MAX` · `SCORE_POPUP_SIZE_LO/HI_AMOUNT`. So a single turret hit's
growth pops up small, and a jungle camp · kill bounty pops up large.

**The renderer doesn't decide what to show** — only `BattleSim._show_score_gain` /
`flush_score_popups` call this function, and rules like excluding dead pilots · holding during an
engage · summing the engage total all live there (the "Growth-point popup" section of
`features/battle_sim/README.md`).

### Targeting dim + emphasis (range dimmed · effect area bright)
**The dim goes up the moment you drag a card out of the hand.** Previously out-of-range tiles darkened
only when modal targeting opened (`is_active()`), but now dragging itself is targeting, so the
`draw_dim` condition in `_draw()` is just `targeting_overlay.is_visualizing()`. `is_visualizing()` is
true only for PILOT / LOCATION / PREVIEW, so holding an INSTANT card with no range concept (draw /
strategy points etc.) doesn't darken the battlefield at all.

**The tile dim states range — tiles outside the caster's `cast_range` darken.** The painting side
(`_draw_targeting_underlays`) and the dim-exempting side (`_undimmed_cells`) look at the same set:

| Mode | Tiles that stay bright (`_undimmed_cells`) | Paint |
|---|---|---|
| PILOT | `is_in_range_cell` — inside the caster's range (whole battlefield if unlimited) + `pick_cells` | None |
| LOCATION | In range + `valid_cells` + `pick_cells` | Green fill + outline on valid cells |
| PREVIEW | `area_cells` (the caster's engage radius `self_range`, 1 if none) | Yellow fill + outline |
| INSTANT | Everything (no dim at all) | None |
| While a target is pointed at (PILOT / LOCATION) | **Effect area only** — `pick_bright_cells()` (`pick_cells` + target cell; single-target cards with no area get just the target cell). The range is dimmed again | Yellow fill + outline on area cells |

> Previously PILOT **dimmed every tile** and LOCATION kept only valid cells bright, so a card's range
> showed nowhere on screen (range dim restored at the user's request). PREVIEW's area was also hard-coded
> to radius 1, so [우세한 전장] (Dominant Battlefield, 3) · [개시] (Start Battle) · [제압 전투] (Suppression
> Fight, 2) were drawn narrower than the actual engage roster — now `CardPhaseManager.engage_radius(cd)`.

**Enlargement (emphasis) is decided by `CardTargetingOverlay.is_emphasized` alone** (`_pilot_emphasis_target`):
- While nothing is pointed at — `target_pilots` (PILOT: valid targets in range / LOCATION `foe` cards:
  enemies on valid cells / PREVIEW: engage participants) grow 1.5×.
- While a target is pointed at — only `pick_pilots` grow, and the other valid targets return to normal
  size. `pick_pilots` = the target + the pilots the card's effect will reach
  (`CardPhaseManager.compute_pick_affected`: engage `at_target` roster · enemies within `area` /
  `around_target` / `self_range` radius · measured from the destination cell after a move clause).
  Example: [강습] (Assault) — while dragging, every enemy on the battlefield; pointing at one enemy, every
  engage participant within radius 1 of that cell (including the caster diving in).
- Leaving the target returns to the first stage.
- So the pick doesn't flicker when other portraits shrink and the stacking layout on the cell shifts, an
  already-pointed pilot stays picked within marker radius × `PICK_STICKY_SCALE` (1.35)
  (`CardTargetingOverlay._hit_test_pilot`).

Pilot dimming is decided by `should_dim_pilot` — for PILOT / LOCATION, pilots in neither
`target_pilots` nor `pick_pilots` (**while a target is pointed at, everyone outside `pick_pilots`** —
other valid targets are dimmed too); for PREVIEW, non-participants.

**The pointed-at target's portrait is on top.** At the start of the frame `_draw()` stores
`CardTargetingOverlay.picked_pilot()` (PILOT's `pending_pick`; for LOCATION, the pilot picked via its
portrait while it stands on that cell) in `_pick_top`; that portrait is skipped by the cell pass
(`_draw_pilot_cell`) and the `_top_pilot` redraw, and `_draw_pending_pick_highlight` redraws it, shadow
included, **after the pilot dim discs** (the cyan ring above it, the LOCATION cell outline below it).
Neither a neighbouring cell's portrait nor its dim disc covers the target's face. **The caster
(`card_caster`) is never dimmed in any mode** — the dim means "you can't drop here", which doesn't apply
to the one firing the card. **But it isn't emphasised either**: the caster grows only when it is itself
a valid target of that card (`target=ally` cards like protect / return-to-base) or falls inside the
effect area.

### Pilot marker positions — `pilot_marker_positions()`
Every frame `_draw()` builds a `PilotData → Vector2` marker position table via
`_build_pilot_render_layout()` and shares it with the dim overlay. That function has three steps —
**solve the seats** (`_solve_slots`, pure) → **sync the glide** (`_sync_glide`) → **output this frame's
coordinates** (`_compose_positions`, applying the emphasis factor and screen clamp). Time doesn't flow
here, so the answer doesn't waver even if called several times per frame. The **public** wrapper that
returns the same thing is `pilot_marker_positions()`, and `CardTargetingOverlay._hit_test_pilot` uses
it — when several stand on one cell each is drawn in a different slot, so a position computed from
`grid_pos` alone (tile centre / `pilot_marker_pos_solo`) can't tell who was pressed (the leftmost pilot
was always picked). Moreover the slots are decided by a greedy sweep over the whole battlefield, so
**solving one cell on its own doesn't give the same answer** — this one table is the only answer.

For pilots not in the table (layout hasn't run even once yet, or not a render target), the fallback is
**`pilot_marker_pos_fallback(p)`** — it treats the pilot as standing alone on its cell and seats it on
the first ring in the base direction. `BattleSim.pilot_marker_pos_solo` now simply forwards to this
function (it used to carry its own copy of the "enemy above / ally below" rule, and when the direction
rule changed the two answers diverged).

Targetable pilot markers grow by the factor `_pilot_emphasis_scale(p)` returns — the target value is
**`TARGET_EMPHASIS_SCALE` (1.5)**, and it **grows over `EMPHASIS_TWEEN_SEC` (0.05s) rather than jumping
immediately** (and the layout spreads along with it so the group on the same cell doesn't overlap — the
*Targeting emphasis also affects layout* section above).
Emphasis targets by mode:
- **PILOT**: every pilot in `valid_pilots`
- **PREVIEW**: `preview_participants`
- **`pending_pick` is no exception** — a cyan ring is attached on top to distinguish it, and if it were
  reset to 1.0 only here, faces would grow and shrink as you drag a card past them. The cyan ring's
  radius also takes the same factor and sits outside the enlarged marker.

The drawn radius comes from **`pilot_marker_radius(p)`** alone (public —
`CardTargetingOverlay._hit_test_pilot` uses it as the click radius, and the cyan ring and dim disc read
the same value). An emphasised portrait (31.5 × 1.35 × 1.5 = **63.8px**) is close to the tile radius
(`hex_size * 0.85` = 68.9px), so if hit testing measured with a fixed constant, pressing the outer rim of
the face might not catch the target (when the factor was 2.0 it clearly exceeded at 85px). However the
fallback "missed the marker but inside its own tile" is based on tile size regardless of emphasis —
widening it by the enlarged portrait would suck in clicks meant for the neighbouring cell.

#### Emphasis interpolation (`EMPHASIS_TWEEN_SEC` 0.05s)
The question is split in two:
- **`_pilot_emphasis_target(p)`** — is this pilot a target that can be picked *right now*.
  Either 1.0 or `TARGET_EMPHASIS_SCALE`, i.e. a step function.
- **`_pilot_emphasis_scale(p)`** — the factor actually used this frame.
  Read from the `_emphasis_now` dict, and `_advance_emphasis(delta)` pushes it toward the target every
  frame with `move_toward` (paced so the whole range takes 0.05s — 0.15s left a window where the hand
  holding the card was already over the target while the face was still growing). It stops on the frame
  it reaches the target, and entries whose value returned to 1.0 are erased from the dict — the default
  is 1.0 so there's no reason to keep them, and dead keys don't pile up where a new `PilotData` comes in
  every match.

**Drawing · layout · hit radius all read the one `_pilot_emphasis_scale`**, so the three don't drift
apart even mid-interpolation — as the face grows the group spacing widens, the arrow pointing at the
tile lengthens, and the click radius grows together. Measured (synthetic input): after drag start the
radius rises smoothly 42.53 → 63.79px, and on release returns at the same pace.

> **Why it must not jump instantly.** The moment you picked up a card, three or four faces on the
> battlefield ballooned to 1.5× in one frame and the groups spread sideways. The impression "the screen
> shook" came before what the target was.

> **That doesn't make it a pulse, though.** The sin scaling between 1.06~1.14 was deleted — don't revive
> it. For a drag-and-drop-onto-a-face interaction, a target whose size *keeps* changing was actually
> harder to aim at. The current value **doesn't budge once reached**. The `_emphasis_time` /
> `EMPHASIS_PULSE_*` constants went away with it.

There are three continuous redraws in `_process` — **damage number popups**, **emphasis turning on or
off**, and **markers mid-slide** (`_advance_glide`). If all are at rest, `queue_redraw()` is not called —
the moment the targeting state **changes**, `CardTargetingOverlay._request_redraw()` kicks it separately.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Battlefield portrait layout (horizontal rows → 6-slot hex fallback) | **Now seated in horizontal rows first** — a same-team block sits below the tile (enemies above) in one row of up to 3 (overflow to the outer row), and on the allied HQ · allied turret cells adjacent to the HQ, one row above of up to 5 → the "horizontal rows first" section above. The hex ring layout below is used only when the rows are blocked. Portraits sit on a **hex ring surrounding** the tile — 6 directions (N/NE/SE/S/SW/NW) × 3 layers (radius 91 / 182 / 273px); neighbouring slots are 60° apart, so on a ring of radius d the distance between neighbours is exactly d, and using `diameter + gap` directly as the radius means faces within one ring never touch. **The base direction is set by the team — bottom side (team 0) = below the tile (S), top side (team 1) = above the tile (N)**. No exceptions for lanes or junglers, so on any cell the bottom row is my team and the top row is the opponent team. **The old movement-direction-based placement ("clear the side you're heading to, stand on the side you came from" — lane pilots opposite the next waypoint, junglers opposite the direction they came from via `prev_grid_pos`) was deleted**: alignment within the same lane and segment was right, but **the same team sat on different sides per segment** (for the right lane: bottom left before the T1 turret → then below → bottom right after the enemy T1 turret), so the basis for reading teams as top/bottom disappeared. `_pilot_travel_dir` / `_peek_waypoint` / `_nearest_dir_index` / `PilotData.prev_grid_pos` were removed at that time (to revive, commit 64bec06). **The six seats are laid out as one left→right row, not by angle** (`BattleRenderer.SEAT_ROW_DOWN` / `SEAT_ROW_UP` — team 0 `NW SW [S] SE NE N`, team 1 `SW NW [N] NE SE S`). The middle three seats are that team's **half**, the very middle is the base direction, and both are the ring wound in one direction, so seats consecutive in the seat chart are consecutive on the ring too. **Seats are decided per block, not individually** — pilots on one cell with the same base direction (= same team) are grouped into one mass that takes **n consecutive seats of the chart = a window** as a whole, and that window is checked for (a) seats unused on the same cell and (b) **no overlap with any marker already placed**. If blocked, **the whole window is shifted one seat sideways** and checked again — so side-by-side A·B step aside **both to the right when the left is covered, both to the left when the right is covered**, and the left-right order never flips (measured team 0 x2: default `SW S` → SW blocked `S SE` → S blocked `NW SW`; x3 also slides all three together). Window candidate order is **(1) fewer members outside their own half → (2) window centre closer to the base direction → (3) the side the block leans toward**, so team 0 uses up the bottom half (SW·S·SE) and team 1 the top half (NW·N·NE) before crossing to the other side. **The direction of (3) is set by the lane** (`BattleRenderer._block_seat_bias`) — **right lane leans right** (team 0 `S SE` / team 1 `N NE`), **left lane leans left** (`SW S` / `NW N`), and centre lane · jungler · mixed-lane blocks have no bias (= left, as before). It used to have no direction, so **every block leaned left**; the right lane often has two, supporter + sniper, on one cell, and that 2-person window sat on the left (`SW S`), so **it collided with the jungler marker passing through the left neighbouring cell and the whole block got pushed out** — on screen the two portraits looked like they turned around for no reason (measured: now fixed at team 0 `S SE` / team 1 `N NE` throughout laning, kept even when both teams stand on the same cell). The bias enters **only in the tiebreak slot**, so a pilot standing alone sits in the middle regardless of lane, and the lane only decides which side it steps aside to when that seat is blocked (measured team 0 x1: S blocked → SW with no bias · **SE** if right lane; only when all three bottom seats are blocked does it go to NW). If every window on that ring is blocked, the **whole block** moves to the outer ring — the arrow lengthens by the distance gained so which cell it is keeps reading (the arrow tip is **derived from distance**, not the marker radius, so it always reaches just short of the tile centre). The key point is that (b) also looks at other cells' markers: neighbouring tile centres are 140px apart while the portrait diameter is 85px, so when two vertically adjacent cells picked slots facing each other the two faces overlapped head-on — that was the only structural cause of faces being hidden on the battlefield, and now the later cell steps aside (measured: the lower cell's team 1 meeting the upper cell's team 0 S has N·NW·NE all overlapping at 78.9px, so x1 = SW, x2 is pushed to `SE S` — the case where the top half is physically fully blocked). **A cell's 6 slots are shared by both teams** — base directions are opposite per team so the starting points don't collide, but if a window is pushed out of its own half or one team has four or more, it can sit on the other team's slots. Assignment is a greedy sweep over the whole battlefield in coordinate order, so **solving one cell alone doesn't give the same answer** — the single `pilot_marker_positions()` table is the only answer. The `+N` overflow circle was deleted (everyone gets their own slot). **The headcount badge in the middle of the tile (`x3` / `2v1`) was also deleted** (`BattleRenderer._draw_cell_badge`) — the portraits already tell the headcount individually, and that badge took the middle of a cell that had returned to jungle, competing with the camp outline · capture fill colour. **Why group into windows**: with the approach of picking empty seats one by one in priority order, when only A's seat was blocked A jumped over B to the opposite end, reading not as stepping aside but as **swapping seats**, and the block sometimes got cut in the middle. The generation before that (**clockwise rotation by angle**) additionally dragged team 0 up S → SW → **NW → N** when even one seat was blocked, destroying the very reading rule "bottom row is my team, top row is the opponent" — revive neither. Only when all three rings' windows are blocked does it fall back to seat-by-seat search (a one-person window, so it uses the same chart). **Portraits never teleport under any circumstances** — the "Marker glide" entry below. The speech-bubble tail always points at **the tile centre being glided**, so it slides on the same beat as the portrait, and the old arrow inertia machinery (`_arrow_aim_point` / `ARROW_SETTLE_SEC` / `_lerp_polar`) was deleted entirely — it was a screen that froze only the tail back when portraits jumped. |
| Marker glide (movement FX) | **The single on-screen marker coordinate is interpolated as a whole** (`BattleRenderer._glide`). Previously only cell movement was tweened (`PilotData.anim_move_t/dur`) and **slot changes were applied instantly**; one slot is 91px · the opposite side 182px, so **teleports larger than the distance between cells (140px)** got mixed in every turn, and a pilot who merely stepped aside because someone arrived next to it had no tween at all. Now the coordinate is split into **centre + slot vector** and three things are pushed separately — the **centre** along the polyline of the cells actually stepped on this time (`PilotData.anim_move_path`) over `ANIM_MOVE_DUR` (0.30s), the **slot angle** on the **same beat** (= the arrow direction turns together with cell movement), and only the **slot length (ring)** **after arrival** over `MARKER_RADIUS_SETTLE_SEC` (0.15s). If the ring is unchanged, the length interpolation is the identity, so the arrow length doesn't change by a single pixel throughout the move, and it lengthens after arrival only when entering a crowded cell pushes it to an outer ring. **It bends along the path** — a `move_range` 2 move and `advance:N` don't cut past the middle cells (measured: the midpoint of a 3-cell path deviates 121.5px from the straight-line midpoint). The curve is **smoothstep** — the old ease-out cubic covered 15% of the distance (measured 24.98px) on the first frame at 60fps and jumped once at every start (now 0.5~0.7px). **Where teleporting is right, it snaps**: for return-to-base / respawn the fade covers the position change, and a dead body must stay pinned to the cell where it fell. The only thing advancing time is `_advance_glide` in `_process`, so no matter how many times per frame the layout table is queried, the FX doesn't rewind. |
| Targeting with several pilots on one cell | The PILOT hit test looks at **the marker positions actually drawn** (`BattleRenderer.pilot_marker_positions()`, the same solve as `_draw()`), not `grid_pos`. It used to measure from the tile centre / `pilot_marker_pos_solo`, so all pilots on the same cell had the same coordinate and pressing any face picked **the leftmost pilot**. A click that misses the markers is still caught if inside its own tile, but sorted by marker distance. |
| Camp outline (growth-point display) | A charged camp is shown as **that jungle tile's outline** (`BattleRenderer._draw_jungle_camps`). **The colour doesn't distinguish ownership — if charged, bright yellow (`CAMP_LINE_COLOR`), and that's all.** At one time camps on enemy-owned cells were drawn separately in dark amber (`CAMP_LINE_ENEMY_COLOR`, **deleted**), but that colour couldn't be told apart from "empty", so what read on screen was brightness, not ownership — the tile face already says ownership in team colour, so the outline only needs to say one thing: **does this cell still have growth points left right now** (`_camp_mark_kind` deleted too). **Empty jungle cells get a shade** (`CAMP_SPENT_TINT`, black α 0.34, drawn **before** the outlines so it doesn't eat neighbouring charged cells' lines) — with no outline alone, "not eaten yet" and "just eaten" are the same picture; dropping one step of brightness lets you read from colour alone where the jungler should go. **There is one condition for drawing an edge — the neighbour across it must not be a charged camp.** So when two camp cells touch, the shared edge drops out on both sides and **only the outer contour remains**, and if one side of the jungle is fully charged, that whole mass reads as a single outline. **Edge ↔ neighbour mapping is solved geometrically, not with a table** (`_neighbor_across_edge`: matches the edge midpoint direction against the neighbour centre direction) — hex offset coordinates have different neighbour offsets for odd/even columns, an easy place for a hand-written table to be silently wrong (this repo has already suffered from a sign bug). Headless check: on all 14 camp cells, the six edges map one-to-one to the six neighbours. The old **diamond** in the middle of the cell competed for space with the jungler's portrait, and even when three or four camps were connected they scattered into three dots, so "this side's jungle is entirely left" didn't read at a glance. |
| Turret hit FX | When a surviving turret takes damage, `BattleSim.anim_turret_hit(td)` runs FX that **shakes it left/right and flashes red** for 0.26s (`ANIM_TURRET_HIT_DUR`) (excluding the destroying hit — the sprite vanishes on the spot). The turret art isn't drawn by the renderer but is a `Building` node under `BattleField/BuildingLayer`, so `BattleSim._apply_turret_hit_visual` shakes that node's `position` / `modulate` directly (base position cached per cell in `_turret_home_pos`, restored on the last frame and on restart). `BattleRenderer` only reads `BattleSim.turret_hit_offset(td)` and shakes **the HP bar by the same offset**. |
| Battlefield pilot marker | The portrait (`PilotImages.circle_for` = `circle/N_circle.png`) is a **circle inscribed** in a square, and `BattleRenderer._draw_pilot_circle` **lays a white circle behind it**. Some of the 40 images have alpha holes **even inside** the circle, so drawn as-is the tile colour behind showed through the face — especially on captured jungle tiles, the pilot got tinted the same colour as the tile. The radius is 1px smaller than the drawn radius so no white rim pokes out past the anti-aliased edge, and the colour takes **the same** tint · alpha as the portrait (death dim / return-to-base fade), so the background never stays bright on its own. |
| Death FX | A fallen pilot **stays dimmed on the spot for 1s** (`ANIM_DEATH_HOLD_DUR`), then over 0.45s fades out and rises off the battlefield. `alive` is already false, so it's pure UI — `BattleRenderer._is_renderable()` uses `anim_death_phase != 0` alongside being alive as the draw condition. The body also occupies a cell layout slot, so for those 1.45s the living pilots on the same cell are pushed (hit testing reads the same solve, so they don't disagree). |
| Growth-point popup (over battlefield portraits) | Only at the moment growth points rise **by a large amount at once**, a soul icon + white text (thick black outline) `+N.NNk` rises above that pilot's face (`BattleRenderer.spawn_score_popup`, `SCORE_POPUP_DUR` **1.10s** · `SCORE_POPUP_RISE_PX` **72px** — floats longer · higher than the damage number's 0.30s / 46px, so even two at once on one face don't overlap). There are five places it appears — **turret damage** (a per-hit share of `SCORE_TURRET_FULL`, split by HP removed) · **kill bounty** (last hit and assists each) · **engage total** (merged into one per participant after the stage closes) · **jungle camp** (`SCORE_JUNGLE_CAMP` whether eaten by stepping on it or intercepted by a raid, `SimulationCore.harvest_camp_under` / `steal_camp_point`) · **[캐시] (Cash) interest** (`MECH_CASH_RATE` of the holder's growth points every time a card is played, `MechSkillSystem._payout_cash`). **Only front-line presence is excluded** — if numbers popped over ten faces every turn, they'd become the background and bury the one big event. Jungle camps are the opposite: the patrol rhythm is the jungler's play, yet that beat wasn't on screen, and the gain happens once to one person rather than to ten every turn, so it doesn't become background. [캐시] is the same: without a trace, holding that card in hand and not holding it are indistinguishable on screen. The wiring is one layer: `add_score`, which silently accrues, and `award_score`, which attaches a popup, are split, so **which accrual sources show on screen reads from the call site**, and `add_score` returns the **actual increase** after the floor and accrual multiplier, so the popup shows the value that went in, not the requested value. There are two cases where it's not shown — **dead pilots** (the body leaves the battlefield after 1.45s, and assists come in even after the assister died, so this is a path that actually triggers), and **while an engage is running** (the arena covers the screen so nobody sees it, and popup coordinates are fixed at the marker position at spawn time, so by the time the stage clears they'd be floating in the wrong place). The latter piles up in `BattleSim._score_popup_hold` and is released as one per pilot by `flush_score_popups()` in `EngagePhaseManager._on_dashboard_confirmed` — same place and same reason as the kill feed's `_pending`. |
