# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → PREP → BAN_PICK → LAUNCH (change_scene → BattleSim)
```

**Two enum values only hold their place — `ASSIGN` and `JUNGLE_START`.**

- **Mech (메크) assignment** moved inside the ban/pick (밴픽) screen (see the BAN_PICK section below),
  and `assign/AssignController.gd` was deleted.
- **Jungle start (정글 시작) direction** **moved inside BattleSim**
  (`features/battle_sim/gambit/JungleStartOverlay.gd`). Which jungle (left or right) to go to is a
  choice made by looking at jungle ownership · camps · our jungler's position, but the old
  `jungle_start/JungleStartController.gd` showed not a single pixel of the battlefield (전장) and
  just stood up two buttons, "← LEFT / RIGHT →" — choosing on that screen was no different from a
  coin toss. That folder was deleted.

The two enum values remain for save compatibility (`match_resume.phase`).

PREP is the pre-match scouting sheet (white outgame paper) — opponent on top, own team below.
**How much of the opponent is visible follows the analysis reveal tier** (M5 — name/role → stat
ranges → exact stats + top mechs → pilot cards; own team always full), with an analyst note when
analysis is delegated. Details: `match_prep/README.md`. Pressing "경기 시작" (Start match) advances
to BAN_PICK and triggers the pre-ban-pick autosave.

Entry point: `scenes/MatchFlow.tscn`. Resume saves skip PREP and jump
directly to BAN_PICK (or LAUNCH for post-gambit saves) since the player
already committed when the save was written. On `LAUNCH`,
`GameManager.match_ctx` is populated and the scene transitions to `BattleSim.tscn`.

---

## Module Architecture

`MatchFlow.gd` is a thin orchestrator (`class_name MatchFlow extends Node2D`).
Three child controllers each build their own UI on `enter()` and emit
`phase_finished(result)` when done:

| Node | Script | Responsibility |
|---|---|---|
| MatchPrepController | `match_prep/MatchPrepController.gd` | Pre-match scouting sheet — opponent (analysis reveal tier) + own roster. "경기 시작" → BAN_PICK. |
| BanPickController | `ban_pick/BanPickController.gd` | LoL-international ban/pick (4 bans + 10 picks) with random AI, **plus the mech assignment that follows on the same screen**. See the two sections below |

The two detail popups opened by the assignment step are sibling files of the controller:

| File | Purpose |
|---|---|
| `ban_pick/MechDetailPanel.gd` · `.tscn` | `class_name MechDetailPanel extends CanvasLayer` — mech detail (left full-body art / right 3 stat chips → passive → mech card grid / bottom close), white modal like `DraftDetailPanel`. Scene-owned layout, `MechDetailPanel.create()` once then `open(m, mastery_rows, quirk_info)` — `ban_pick/README.md` "MechDetailPanel" |
| `meta/run_setup/DraftDetailPanel.gd` | Pilot detail — **reuses the very same popup as the draft screen** (`DraftDetailPanel.create()` once, then `open(p: PlayerData)` is all it takes to open) |

Unlike the other two, `BanPickController.enter()` **also receives the rosters and team names** —
because the ban/pick screen stands both teams' pilot portraits (초상화) at top/bottom, and once the
14 moves are done it writes the assignments directly into those rosters.

---

## BAN_PICK screen

One vertical sheet is divided into three blocks: **top / middle / bottom**.

```
top     2 ban chips → 5 mech slots → 5 pilot portraits      (opponent team)
middle  pick pane = role-class filter tabs + mech grid (square cells, 4.5-row scroll)
bottom  5 pilot portraits → 5 mech slots → 2 ban chips      (ally, mirrored)
```

- **Mech slots are twice as tall as pilot slots** (`MECH_H_RATIO`) — pilots are an eye-level band
  (2.4:1) and therefore flat, mechs are square portraits, so at the same width the mech must take
  double the height for each image to sit at its own ratio.
- Thanks to the **mirrored layout**, pilot faces always come on the inside (battlefield side) and
  mechs on the outside.
- **The screen uses the outgame white-background family** (`OutgameTheme`) — the background is a
  pale grey and only the pick pane is a single shadowed white card, so one board separates "this is
  where you choose" from "this is both teams' situation". It used to be a dark board.
- **A grid cell is just a square portrait + one name line below.** A role-class badge (a rounded
  rectangle filled with the role colour + two white letters `Tk/As/Fi/Sn/Su`) sits at top left.
  Each cell used to carry two more lines, `HP · ATK · 존재감` (presence) and the passive name, but
  on a screen for scanning twenty-one mechs, making people read five lines per cell defeats
  **recognising by picture** — numbers and passive descriptions are carried entirely by the bottom
  sheet opened with one tap.
- Portraits are **pre-baked 256² square cuts** from `MechImages.portrait_for()`.
  The old "shrink and bake full-body art to grid size at runtime" (`_bake_thumbs` / `THUMB_PX`) was
  deleted.
- **The order of the five slots is `GameEnums.ROLE_DISPLAY_ORDER`** (Top · Jungle · Mid · ADC ·
  Support). That's why pilot portraits carry no name tag or role tag — the seat is the role, and the
  in-game strip (스트립) stands in the same order.
- **The progress row (14 chips) sits at the very top of the pick pane, right above the role-class
  filter** (formerly at the very top of the screen). The chips are now thicker and hold ban ✕ /
  pick ✓ icons (SVG), and below them (my turn) or above them (opponent's turn) a triangle points
  toward that team, slowly bobbing. Each time a move passes, a **turn banner** (`내 차례 밴` (My ban)
  / `상대 차례 픽` (Opponent's pick) …) sweeps across the screen centre.
- **The opponent fidgets** — it picks up 0–2 plausible candidates for 0.3–0.8 s each (cell border +
  preview in the opponent team's next slot) before committing to one. Details in
  `ban_pick/README.md`.

Controls are still **1 tap = select (opens the bottom sheet), 2nd tap on the same mech = commit**,
and the sheet opens even when it is not my turn (only the commit button is locked).

---

## Assignment (inside the ban/pick screen)

**Ally mech slots can be dragged around even during ban/pick.** A slot's content is not pick order
but a seat table (`_seat_mechs[side]`, seat → mech_id, -1 = empty seat), and a new pick sits in the
first empty seat from the left. Dropping a slot on another seat swaps if occupied, moves if empty —
during ban/pick, the mech slot right under the eye-level portrait is "this player's machine". A tap
opens that machine's bottom sheet (it's already taken, so commit is locked).

When the 14 moves are done, **the screen is not switched** — `_enter_assign_mode()` removes the pick
pane (tabs + grid + backing board + order row), stands a **"게임 시작" (Start game) bar**
(`OutgameTheme.add_bottom_bar`) in the bottom section, then rebuilds the ally block:

```
5 pilot upper-body illustrations  (`PilotImages.bust_for` — same crop · same ratio as the
                                   draft screen's picked slots)
5 mech slots                      (draggable, in the seats arranged during ban/pick)
"드래그 드롭으로 메크-파일럿 지정 변경"   (bottom right of the mech row, 17pt)
2 ban chips
```

("드래그 드롭으로 메크-파일럿 지정 변경" = "Drag and drop to change mech–pilot assignment".)

**Pilots on top, mechs below.** Assignment decides "what does this person ride", and the subject of
that sentence must be on top so scanning one slot vertically reads as one sentence. Mechs used to be
on top — a layout meant to keep the dragging finger from hiding "which pilot seat" below it — but
then the object came before the subject and what the five slots decide read backwards. Now that
portraits have grown into upper-body illustrations, the slots are much larger than a finger can
cover, so that concern is gone.

Portrait height is derived from width — `portrait_w / PilotImages.BUST_ASPECT`
(`_lay["assign_portrait_h"]`). The old square `faces` crop was deleted. Which crop to use **is
decided by the slot ratio** (`_build_pilot_portrait`): flat and wide → eye-level band (ban/pick
step), tall → upper-body illustration (assignment step).

**Dragging a mech slot onto another slot swaps the two** (`_swap_assign`). It changes only on drop;
anything that doesn't cross `DRAG_THRESHOLD_PX` (8px) is a **tap** and opens that slot's mech
detail. While dragging, the original slot stays as a ghost (α 0.35) and the slot under the cursor
gets a thick gold border. Input is received by one `gui_input` attached to each slot — the pressed
control keeps mouse focus, so motion / release keep coming even when the cursor leaves the slot.

**Entry animation** (`_play_assign_intro`) — the two team blocks **gather at the screen centre (the
vertical centre of the body above the bottom bar)** into the vacated pick pane area (`GATHER_SEC`,
`_lay["gather_*_y"]`), then **the opponent's mech slots move over to the player seats matching their
positions** (`_enemy_role_order` → `_play_enemy_reassign`). The opponent's assignment seats, at each
seat, a machine of the same role class as that player's role, and seats with no matching machine are
filled with the remaining ones in pick order — the old random shuffle was deleted. The move animation
actually slides the slot nodes, then puts them back and swaps the seat table (tap buttons and refresh
rely on the premise that a slot node is always at its own seat). **"게임 시작" stays locked until the
animation ends** — moving on before the reassignment would make the seen assignment and the actual
one diverge. The opponent block is not rebuilt (the picture that stood throughout ban/pick must stay
as is so "what did they pick" doesn't have to be read twice).

### Detail popups in the assignment step (both teams are tappable)
- **Pilot portrait** → `DraftDetailPanel` (the same popup as the draft screen)
- **Mech portrait** → `MechDetailPanel` (in a season run it also lists that team's mech mastery with
  the mech — the enemy only with analysis tier ≥ 2; see `ban_pick/README.md` "Mech mastery")

Assignment is done by looking at stats, and without a place to see them there's nothing to do but
leave pick order as is. **It differs from the in-game detail panel** — no in-game tabs
(HP (체력) · attack · lasting effects), and pilot and mech are not overlaid on one screen: the match
hasn't started, so in-game state doesn't exist yet, and the question being asked is one side only,
"this person" or "this machine". The two popups never show at once
(`_close_detail_panels`) — two stacked dims make the rear one darken over the front one.

Tap wiring is a **transparent Button** laid over each slot, enabled only on entering assignment
(`_set_block_tappable`). **Ally mech slots alone are the exception** and don't enable that button —
their taps are also received by the drag wiring (`_on_slot_input`), so enabling the button would let
it take the press and the drag would never start.

"게임 시작" calls `_finish()`, where for **both teams** the seat → role conversion
(one layer of `ROLE_DISPLAY_ORDER`, `_write_assignment`) fills `PlayerData.assigned_mech`, then the
rosters are passed as-is via `phase_finished`. **The roster array itself keeps role 0..4 order** —
`MatchFlow._roster_mech_ids`'s resume snapshot assumes that order.
Both popups are also closed here — they're `CanvasLayer`s, so freeing `_panel` doesn't take them
along, and moving on with one open leaves its dim on top of BattleSim.

Each controller accesses the orchestrator via:
```gdscript
@onready var _mf: MatchFlow = get_parent() as MatchFlow
```
UI panels parent to `_mf.canvas` (the CanvasLayer in MatchFlow.tscn).

---

## MatchFlow.gd

State machine with phases from `GameEnums.MatchPhase`. Loads `players` and `mechs`
tables on entry via `GameManager.load_match_data()`. On the final `LAUNCH` phase
populates:

```gdscript
GameManager.match_ctx = {
	"active": true,
	"player_roster": Array[PlayerData],   # 5 players sorted by role 0..4, assigned_mech set
	"enemy_roster":  Array[PlayerData],
	"jungle_start_dir": int (LEFT|RIGHT),
	"player_side":   int (BLUE|RED),
	"banned_mech_ids": Array[int],
	"all_mechs":      Array[MechData],
	"enemy_misjudge_chance": float,       # objective misjudge chance (OBJ_MISJUDGE_MIN..OBJ_MISJUDGE_MAX)
}
```

`enemy_misjudge_chance` is set by `_launch_battle()` via `_misjudge_chance_for(enemy_team_id)` —
linear from the opponent's league rank 1st `OBJ_MISJUDGE_MIN` → last `OBJ_MISJUDGE_MAX` (const.csv; ties broken by team average stats,
international tournament (국제대회) external teams `OBJ_MISJUDGE_MIN`, outside a season the midpoint of the two). The resume path also
goes through `_launch_battle()`, so it isn't saved separately. It is read by
`objective/ObjectiveSystem._ai_wants_to_join`.

`BattleSim.gd` reads `match_ctx.active` to decide whether to inject mech stats
into pilots; otherwise it falls back to `ROLE_STATS` defaults.

### Match rosters are copies (M4)
`_team_roster(team_id)` returns **copies** of the season pilots (`_copy_pilot` =
`PlayerData.duplicate()` + fresh `pilot_cards` / `main_mechs` arrays, `assigned_mech` cleared),
built once per team id and cached in `_roster_cache` — PREP, BAN_PICK, the resume path and the cheat
menu all see the same five objects. Ban/pick writes `assigned_mech` onto these copies, and
`season_state.all_pilots` / `intl_pilots` are **never** written by a match (plan §11.3).

Once mechs are assigned — `_on_ban_pick_finished` (before the post-ban-pick autosave) or
`_resume_at_launch` — `_finalize_rosters(p_roster, e_roster)` runs once (`_rosters_finalized`):
1. `PilotMods.apply_to(state, copy)` — the run's temporary pilot mods (M7 incidents / outings).
2. `MechMastery.apply_to(state, copy)` — the mech mastery tier bonus on all six stats
   (`features/season/mastery/README.md`).
3. `QuirkSystem.apply_to(state, copy)` — my pilots' quirk stat bonuses with the assigned mech
   (opponents have none; `features/season/quirk/README.md`).
4. `pending_match.assigned_mechs = {"<pilot_id>": mech_id}` for both teams (10 entries) —
   `SeasonHub` hands it to `MechMastery.record_match` when the result is consumed.

Standalone MatchFlow (no active season) skips all of them; BattleSim never knows mastery or quirks exist.

### Side (`player_side`) — currently always BLUE
`player_side` is one value that decides ban/pick order and in-game priority **at the same time**:

| Side | Ban/pick | In-game |
|---|---|---|
| RED  | First ban / first pick | — |
| BLUE | Second ban / second pick | Strategy points `BLUE_COST_HEAD_START` head start + first turn on equal score |

The fresh-entry path of `_ready()` used to draw this value at random every match, but it now **always
fixes the player to `DraftSide.BLUE`** — pinned to one side until the two axes (ban/pick advantage /
in-game advantage) are balanced. To revive it, revert just that one line; the flow below and
`BattleSim.seed_side_costs()` already read `match_ctx.player_side` directly to decide the side. The
resume path restores the saved `player_side` as is, so it is unaffected by this pin.

---

## Data flow into BattleSim
- `PlayerData.assigned_mech.hp/atk` → `PilotData` stats via
  `SimulationCore._stats_for()`
- `match_ctx.jungle_start_dir` → `PilotData.jungle_start_pref` (assassin only),
  consumed by `SimulationCore._nearest_uncaptured_neutral()` for zone preference

---

## Files

| File | Purpose |
|---|---|
| `MatchFlow.gd` | State machine orchestrator |
| `match_prep/MatchPrepController.gd` · `MatchPrepView.gd/.tscn` | Pre-match scouting sheet (analysis reveal) — controller + scene-owned screen |
| `match_prep/OpponentIntel.gd` · `IntelView.gd` | Reveal rule builder + its drawer, shared with the league team detail — `match_prep/README.md` |
| `ban_pick/BanPickController.gd` | Ban/Pick + mech assignment rules / state — fills and drives the screen scene |
| `ban_pick/BanPickView.tscn` (+ item scenes) | The ban/pick screen layout — both teams' portraits + mech grid + bottom detail sheet + drag ghost (`ban_pick/README.md` "Scene") |
| `ban_pick/MechDetailPanel.gd/.tscn` (+ `MechMasteryRow` · `MechQuirkRow` · `MechCardCell` item scenes) | Mech detail popup for the assignment step |
| `MatchCheatMenu.gd/.tscn` · `MatchCheatItem.tscn` | Editor-only cheat menu (top left) — see "Cheat menu" below |

---

## Cheat menu (editor runs only)
For run testing. `MatchFlow._setup_cheats()` creates a `MatchCheatMenu` (`CanvasLayer`, layer 50 —
above the detail popups, below `SceneFade`) **only when `OS.has_feature("editor")` and the match came
from a season (`pending_match` exists)** — exported builds and standalone MatchFlow never see it.

- Created with `MatchCheatMenu.create()`. **Layout is owned by `MatchCheatMenu.tscn`**: `Root` (theme) →
  `%Menu` (VBox, 16px from the safe corner — code adds the left / top insets) → `%Toggle`
  (`DarkButton`, 150×64, 24pt, α 0.85) + `%List` (VBox, gap 10) of `MatchCheatItem.tscn`
  (`GhostButton`, 300×72, 26pt). The two items saved in `%List` are editor previews; `set_actions`
  clears them.
- A `CHEAT` button sits at the top left of the safe area; tapping it unfolds the cheat buttons below.
- The menu doesn't know what to offer — `MatchFlow._refresh_cheats()` swaps the list on every
  `_enter_phase` (`set_actions([{label, call}])`; an empty list hides the menu). Add cheats for
  other phases there.
- **PREP · BAN_PICK**: `즉시 승리 (MVP 아군 탑)` (Instant win) / `즉시 패배 (MVP 상대 탑)` (Instant loss)
  → `_cheat_finish(winner_side)` writes `pending_match` in the same shape as `BattleSim.end_match`
  (`winner_side`, `pilot_stats` = ten all-zero rows, `mvp_pilot_id` = the winning team's top via
  `RunStats.top_role()`), clears `match_resume`, and fades to `Season.tscn` — SeasonHub settles it
  through the normal post-match path (RunStats, standings / bracket, post-match autosave).
- One press locks the menu (the list is cleared) so a double tap can't fire during the fade.
- **F6 standalone run** of `MatchCheatMenu.tscn` shows dummy data (the two PREP · BAN_PICK cheats,
  list unfolded; pressing only prints) — `_fill_preview()` at the bottom of the script,
  helper `resources/UiPreview.gd`.

---

## Save hooks
`MatchFlow.gd` owns two of the four campaign autosave triggers (the other
two live in `SeasonHub`):

- **Pre-ban-pick** — fires in `_on_prep_finished()` when the player
  presses "경기 시작" on the PREP dashboard. Writes
  `season_state.match_resume = {phase: BAN_PICK, player_side, ...empty
  arrays}`. Skipped when running MatchFlow standalone (no `pending_match`).
- **Post-ban-pick** — fires in `_on_ban_pick_finished()` right after assignment
  completes, before `_launch_battle` scene-changes to BattleSim. The jungle direction used
  to come in here too and this save lived in `_on_jungle_finished()`, but once that choice moved
  to BattleSim the save point was pulled one step earlier — resume replays the battle from scratch
  anyway, so the jungle direction is asked again then
  (the snapshot's `jungle_start_dir` is the default LEFT, for the opponent jungler and fallback).
  Writes the full match snapshot:
  `{phase: LAUNCH, player_side, banned_mech_ids, player_picked_mech_ids,
  enemy_picked_mech_ids, player_assigned_mech_ids, enemy_assigned_mech_ids,
  jungle_start_dir}`. The mech-id arrays are 5-entry, role-sorted (0..4) so
  resume can re-attach `assigned_mech` to each PlayerData.

### Resume entry
`_ready()` reads `season_state.match_resume`. Non-null → skip PREP (the
player already committed when the save was written) and:
- `phase == BAN_PICK` → restore `player_side` and `_enter_phase(BAN_PICK)`.
- `phase == LAUNCH` → `_resume_at_launch(resume)` rebuilds `match_ctx`
  from the resume payload (rosters via `_team_roster()`, mechs via
  `_find_mech()`) and scene-changes to BattleSim immediately. No UI
  controllers run — the jungle start screen is opened by BattleSim, so that one question
  comes up again even on resume.

`match_resume` is cleared in-memory on consumption; on disk it's only
overwritten by the next post-ban-pick or post-week save. Closing mid-battle
keeps the disk save at the post-ban-pick snapshot, so the resume path
replays the battle from scratch with the same locked-in picks.

---

## Screen fit (safe area)

Both controller screens are **scene-based** — no full-screen `Panel` pushed below the notch any more:

- **PREP** — `MatchPrepView.tscn`: its `Paper` covers the whole viewport and only its `%Safe` child is
  offset by the insets in code; the bottom-anchored `%Start` bar extends into the bottom inset
  (`match_prep/README.md`).
- **BAN_PICK** — `ban_pick/BanPickView.tscn`: its `Background` covers the whole viewport and
  everything else sits in `%SafeArea`, a full-rect Control whose top / bottom offsets are the device
  insets (`BanPickView.fit_safe_area`). The team blocks are anchored to its top / bottom and the pick
  pane height comes from the band left between them (`fit_pane`) — so on any screen the grid cells
  stay square and only the number of visible rows changes.
- **Modals** — `MechDetailPanel` (dim = viewport, panel + close in `%SafeArea` whose offsets are the
  device insets) and `MatchCheatMenu` (code adds the left / top insets).

Details: **`docs/mobile_safe_area.md`**


## Detail moved from root CLAUDE.md

### Match Flow → Battle Sim handoff
`MatchFlow` populates `GameManager.match_ctx` (player_roster, enemy_roster,
jungle_start_dir, banned_mech_ids, …) then changes scene to BattleSim **behind
the fake loading cover** — `SceneFade.change_scene` (fade to black 0.30 s → `LOADING` bar
0.50 s → fade in 0.35 s, the same transition as the draft's "게임 시작" (Start game)). The
cover is a `CanvasLayer` on the tree root so it survives the scene swap, and
BattleSim's heavy `_ready` runs behind it. Resume-at-LAUNCH goes through the
same `_launch_battle`, so it fades too.
`BattleSim.spawn_pilots_with_lanes()` injects each `PlayerData.assigned_mech`'s
hp/atk into `PilotData`. If `match_ctx.active` is false (running BattleSim
standalone), it falls back to `ROLE_STATS` defaults.
