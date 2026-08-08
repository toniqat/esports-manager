# Module: Engage (전투 개시)

## Purpose
Turn-based combat triggered by `engage:N` / `duel` card effects during the
작전 단계. While the battlefield uses cell-based same-cell pairing,
**전투(engage)** is a separate full-screen modal where participants take
attack turns in sequence over **N rounds**.

## Files
| File | Purpose |
|---|---|
| `EngagePhaseManager.gd` | `class_name EngagePhaseManager extends Node` — orchestrator. Gathers participants, runs the turn loop with `await`, mediates between game state and overlay. Emits `engage_finished` once the dashboard's 확인 closes the modal. Two entry points: `start_engage(caster, rounds, exclude_lane, on_done)` for the engage cards and `start_duel(caster, target, on_done)` for the 결투 card (1:1 to first KO, round counter / banner suppressed). `resolve_silent()` is kept around for any future synchronous batch-resolution caller but is no longer used by the card phase. |
| `EngageOverlay.gd` | `class_name EngageOverlay extends Control` — full-screen modal: two team columns with HP bars, round banner, attack-by-attack damage popups, and the post-combat dashboard with `확인` button. `setup()` accepts an optional `title_text` ("결투" for duels) and `is_duel` flag (hides the round counter label). |

The manager is added as a child of `BattleSim` from `BattleSim._ready()` and
held on `_bs.engage_phase`. The manager owns its own dedicated `CanvasLayer`
(`ENGAGE_OVERLAY_LAYER = 12`, built lazily in `_ready()`) and parents
`EngageOverlay` there. That layer sits above the HUD canvas (layer 1),
`CardSelectOverlay` (layer 10), and `CardTargetingOverlay` (layer 11), so
the engage modal + post-combat dashboard always draw above the hand row
and any leftover targeting UI. The overlay's built-in 0.65-alpha dim
covers the rest of the screen for the duration of the modal, including
the dashboard step where the 확인 button dismisses it.

## Trigger flow
1. Player plays an engage card (`engage:3`, `engage:4`, `engage:3|exclude_lane`)
   or the 결투 card (`duel`).
2. `CardPhaseManager._effect_engage()` → `EngagePhaseManager.start_engage(...)`,
   or `CardPhaseManager._effect_duel()` → `EngagePhaseManager.start_duel(...)`.
3. Manager flips `_bs.game_phase` to `GameEnums.BattlePhase.ENGAGE`. Auto-tick
   pauses (it only runs during `BATTLE`); card hover/click and "단계 넘기기"
   are blocked because they all check for `phase == CARD_PHASE`.
4. Manager opens `EngageOverlay`, builds the participant list UI, then
   resolves rounds via `await`-driven steps. Duels skip the round banner
   and the inter-round delay so the 1:1 fight reads as a single sequence.
5. After all rounds OR one team eliminated → dashboard shows. Duel mode
   exits as soon as either side hits 0 alive (the `_rounds_total = 99` cap
   never matters in practice).
6. `확인` button → manager closes overlay, sets `phase = CARD_PHASE`, calls
   `on_done` (CardPhaseManager refreshes affordable highlights / HUD).

## Participant gathering
Caster cell + 6 neighbor cells (radius-1 hex). Caster is always included.
Both teams' alive pilots in any of those 7 cells participate. Junglers and
lane pilots may face off across normal engagement-scope rules — engage
explicitly bridges them.

### `exclude_lane` flag (card 4 — 교전)
Filters out lane pilots that are currently on their lane (i.e., not in a
jungle/neutral cell). Junglers stay in. Lane pilots displaced into a jungle
cell by a card effect (e.g., `move`) also stay in. The design intent is to
let players move an ally jungler / displaced ally lane pilot into the area
to set up a 2:1 unilateral engage on a single enemy jungler.

```gdscript
# inclusion rule under exclude_lane:
p.is_guerrilla OR _bs.neutral_zone_cells.has(p.grid_pos)
```

## Combat resolution
- **Round structure**: initiator team attacks first (caster's team), then
  the other team. Each pilot attacks once per round.
- **Order within a side**: `presence` DESC, ties broken by random shuffle.
  Rebuilt at the start of each round (so dead pilots drop off).
- **Target selection**: weighted random over alive enemy participants;
  weight = `presence`.
- **Damage**: `hit / (hit + evasion)` roll. On hit, damage = attacker.atk;
  shield absorbs first, HP next. KO → `alive = false` and
  `respawn_timer = RESPAWN_TURNS` (same as a battlefield kill).
- **End conditions**: rounds complete OR one side has 0 alive participants.

## Stats tracked for the dashboard
Per-pilot dict, keyed by PilotData instance:
```gdscript
{ "dealt": int, "taken": int, "kills": int }
```
Damage values count `shield_absorbed + hp_dmg` (the actual amount removed
from the target). Misses do not contribute.

## AI engage path (modal, synchronised)
AI plays now route through the same `start_engage()` modal as the player —
`AiCardPlayer.run_ai_plays()` pulls each affordable card, presents a centred
card animation, applies its effect, and (when an `engage:N` clause fires)
`await`s the new `engage_finished` signal before continuing to the next play
so back-to-back AI cards don't stomp each other's modals.

The legacy `resolve_silent(caster, rounds, exclude_lane)` helper is still on
the manager for any future synchronous batch-resolution callers but is no
longer invoked by the card phase.

## Presence stat
`presence` was added to `mechs.csv` (and the `mechs` table schema). Default
fallback when no mech is assigned (standalone BattleSim launch): 4 for
melee roles (TANK / FIGHTER / ASSASSIN), 2 for ranged (SUPPORT / SNIPER).
The value flows: `mechs.csv → MechData.presence → SimulationCore._stats_for
→ PilotData.presence`. Engage is currently the only consumer.
