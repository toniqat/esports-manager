# Gambit Phase Module

표시 텍스트는 l10n key (`battle.jungle_start.*`).

Owns the pre-opening (개시) stage (`BattlePhase.GAMBIT`). There are two files.

| File | Role |
|---|---|
| `GambitPhaseManager.gd`  | `extends Node` — scene child of BattleSim. Fixed lane assignment + battlefield setup + opening |
| `JungleStartOverlay.gd`  | `class_name JungleStartOverlay extends Node` — overlay where the player picks the **jungle start (정글 시작) cell** by dragging the jungler marker on the battlefield (전장). Lazy-added |

The in-game lane assignment overlay has been **deleted** — the role fixes the lane, and that
slot was taken over by the ban/pick (밴픽) screen (`features/match_flow/ban_pick/`).

---

## GambitPhaseManager.gd

### Role → Lane mapping (constant `ROLE_TO_LANE`)
| Role | Lane |
|---|---|
| TANK | LEFT |
| FIGHTER | CENTER |
| ASSASSIN | GUERRILLA |
| SUPPORT | RIGHT |
| SNIPER | RIGHT |

LANE_MAX (from `lane_config.csv`) tolerates this distribution: 1 LEFT, 1 CENTER,
2 RIGHT, 1 GUERRILLA = 5 pilots.

### Opening flow — the old `launch_battle()` split into three
```
launch_battle()
 ├ prepare_field()        builds the whole battlefield → BattleSim.field_ready = true
 ├ _open_jungle_start()   if match_ctx.active, opens the overlay → stops here
 └ begin_battle()         game_phase = BATTLE  (only when the overlay did not open)
```

- `prepare_field()` — `spawn_pilots_with_lanes` / `spawn_turrets` /
  `init_neutral_zones` / `init_jungle_camps`. **It does not open the battle.** Instead it
  sets `BattleSim.field_ready`, which is the only gate of
  `BattleRenderer._draw` (section below).
- `_open_jungle_start()` — opens **only when `match_ctx.active`**. In a standalone run
  (running BattleSim.tscn directly / headless verification) there is nobody to ask, so it goes
  straight to BATTLE — **putting a wait-for-human step here would stall headless verification
  entirely.**
- `begin_battle()` — the **only place** where `game_phase` becomes BATTLE.

`auto_assign_lanes()` and `launch_battle()` run in two places: `BattleSim._ready()` and
`_on_restart_pressed()`. After `launch_battle()`, `_ready()` continues as before with
deck distribution · pilot/mech skills · logger wiring — the battlefield is already fully
built and **only the BATTLE tick is deferred**, so the chain below it is independent of the overlay.

---

## JungleStartOverlay.gd — jungle start cell

### What is visible
The battlefield is already fully built (pilots · turrets (포탑) · jungle ownership · camps). The HUD
hides **only what cannot be used right now** (`HudBuilder.set_pregame_chrome_visible(false)`) — the deck /
discard piles, the two strategy-point donuts, the two objective spawn clocks. **The pilot strips and
the top chrome remain**.

**The battlefield collapses down to just this screen's question** (`BattleRenderer`):

- **Every cell you cannot drop on is dimmed** (`_draw_jungle_pick_dim`) — non-jungle cells,
  and **opponent-owned jungle cells**. The cells left bright are `active_cells()` (jungle / neutral cells
  that are **owned by our team or not yet taken by anyone**), and the drop check reads the same list,
  so droppable cells and bright cells can never diverge.
- Droppable cells get a light green fill + green border; the cell the marker is over / the chosen cell gets a
  darker fill + **thick gold border** (`_draw_jungle_start_zones`, behind the camp outline).
- **Only the allied jungler's portrait remains on the battlefield** (`_hidden_during_jungle_pick`).
  Slot assignment (`_solve_slots`) reads the same list, so hidden pilots do not take slots.

### Controls — drag the jungler marker on the battlefield directly
You grab **the allied jungler marker itself**, standing at HQ. During this screen the marker is drawn
**without a speech-bubble tail** (it has no tile to point at yet), and its position is decided by the
overlay — `marker_pos(default)`: while dragging, under the finger (keeps `_grab_offset`, the offset between
the grab point and the marker center, so it does not jump on grab); if a cell is chosen, the center of that
cell; otherwise the HQ slot the renderer solved. The grab hit test is the drawn radius
(`pilot_marker_radius`) × `GRAB_RADIUS_MULT` (1.35).

The drop target is **one cell** (`_cell_under`: the nearest droppable cell within `hex_size` of the marker
center). While dragging, the path is redrawn each time the cell under the marker changes
(`_draw_jungle_start_path`) — **from HQ to that cell (gold) + the walk for `AFTER_TURNS` (6) turns after
arrival (sky blue)**. If arrival takes 2 turns, it goes up to turn 8. A number pill stands on each cell where a
turn ends; if the route passes a visited cell again, they are grouped in one pill as `2·7`. The number for the
cell the marker sits on is not at the cell center but a **badge at the bottom right of the face**
(`_draw_jungle_start_marker_badge`, after the marker is drawn) — otherwise the arrival turn would be covered
by the face.

Prediction is done by `path_cells()` → **`SimulationCore.predict_jungle_path`**. It temporarily writes the
start cell onto the jungler, **rolls the real `_jungle_goal_for` forward, then restores** — it pushes the turn
count · jungler position · jungle ownership · camp clocks in the same order as the turn loop (turn increment →
move → neutral capture → camp harvest), so neutral capture and the camp circuit after arrival come out exactly
per the real rules. Instead of `_set_zone_cell` (which changes tilemap colours) it only edits the tables, and
restores both tables by writing back into the same Dictionary objects. A turn spent standing still also counts
as one turn. The result is cached per cell (`_path_cache_cell`).

**It is a simple expected route — it assumes our jungler walks alone.** The opponent jungler's walk ·
neutral pre-emption · jungler-vs-jungler engages (교전) are **intentionally not computed** (user decision). At one
point it also rolled the opponent jungler and cut off with `!` on contact, but then the path revealed the
opponent's start direction. So in games where the opponent takes the same side's neutral first or meets us on the
way, the real walk diverges from that point. Headless measurement (실측): in a game where the opponent went the
other way, the predicted 10 cells (arrival 4 + 6) matched the walk of the first 10 turns after opening.

**Dropping is only a selection, not the opening.** On drop that cell is taken, the marker sits on that cell,
and the guide text in the hand (손패) area turns into a "전투 시작" (Start battle) button. A miss returns the
marker to where it was — to the already chosen cell if there is one, otherwise to HQ.

"전투 시작" → `start_pressed` → `GambitPhaseManager._on_jungle_start_pressed`:
`commit()` writes the chosen cell to **`PilotData.jungle_start_cell`** and the side the cell belongs to
(`LEFT_CELLS` / `RIGHT_CELLS`) to `jungle_start_pref`; the manager also writes the direction to
`match_ctx["jungle_start_dir"]`, then calls `begin_battle()`. The jungler
**starts from HQ** and walks with that cell as its first goal (the first branch of
`SimulationCore._jungle_goal_for` — cleared when reached or when the cell becomes the opponent's). At the
moment of opening the overlay's override disappears and the marker returns to its HQ slot.

Input is received via `gui_input` by a single full-screen `Control` (`_root`, MOUSE_FILTER_STOP) — the pressed
Control keeps mouse focus, so motion / release keep coming here wherever the cursor goes (same structure as
hand drag). The coordinate transform is also the same as the hand — `_root.get_global_transform_with_canvas() * local`
is the viewport coordinate, the same space as the battlefield coordinates of `BattleSim.cell_center()`.

Haptics: grab `SELECT` · `LIGHT` each time it enters a droppable cell (the marker snaps to cells as it moves, so
it buzzes per cell) · cell decided `MEDIUM`.

Previously a **separate circular portrait (초상화) placed in the hand area** (diameter 150) was dragged onto the
left / right jungle **groups** (7 cells each) to pick only a direction — the dragged image and the jungler on the
battlefield were split in two, and the opponent's jungle was lit as well.

### The renderer gate changed from phase to `field_ready`
`BattleRenderer._draw()` used to skip entirely when `game_phase == GAMBIT`. Since the jungle start
choice moved inside that GAMBIT, **the battlefield must be visible even before the opening**, so the gate
changed from "what phase is it now" to "is there anything to draw" (`BattleSim.field_ready`).

### Why here
This choice used to be a **separate screen** in `features/match_flow/jungle_start/`.
It showed only two buttons "← LEFT / RIGHT →" without a single pixel of the battlefield, and
without seeing what each side's jungle holds and where our jungler stands, the choice was no
different from a coin toss. That folder has been deleted.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Gambit Phase (pre-opening) | **The role fixes the lane** (TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT) — the old in-game assignment overlay was deleted and its slot was taken by the ban/pick screen. The only choice left in this stage is the **jungle start direction** (next row). `GambitPhaseManager.launch_battle()` is split into three — `prepare_field()` (builds pilots · turrets · jungle ownership · camps and turns on `BattleSim.field_ready`) → jungle start overlay (when entered from a match) → `begin_battle()` (the only place `game_phase = BATTLE` happens). |
| Jungle start (in-game) | **Drag the allied jungler marker on the battlefield directly onto a start cell** (`gambit/JungleStartOverlay.gd`, only when `match_ctx.active` — a standalone run opens straight away with the default LEFT, and headless verification takes that path). The HUD hides only what cannot be used now (deck / discard piles · the two donuts · the two objective clocks), the battlefield **dims undroppable cells (non-jungle cells + opponent-owned jungle)**, and only the allied jungler's portrait remains. That jungler is drawn at HQ **without a tail**; while it is grabbed and dragged, the droppable cell under the marker is ringed in gold and the **HQ → that cell + 6-turn path after arrival is drawn with turn numbers** (`SimulationCore.predict_jungle_path`, a simple expected route that rolls the real goal selection forward — collisions with the opponent jungler are not computed). Dropping is only a selection, not the opening — the marker sits on that cell and "전투 시작" (Start battle) appears in the hand area. Confirming writes `PilotData.jungle_start_cell` (first goal) · `jungle_start_pref` (that cell's side) · `match_ctx.jungle_start_dir` and opens BATTLE. The jungler walks there from HQ. **The gate of `BattleRenderer._draw` is `BattleSim.field_ready`, not the phase** — the battlefield must be visible even before the opening. Previously a separate circular portrait in the hand area was dragged onto the left / right jungle groups to pick only a direction, and before that it was a separate screen in `match_flow/jungle_start/`. |
