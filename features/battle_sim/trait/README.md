# Trait — manager in-game traits (M8)

표시 텍스트는 l10n key (`battle.trait_banner.*`, `battle.trait.*` — `TraitHooks.KEY_LABELS` values are keys).

In-game half of the manager traits (`docs/outgame_dev_plan.md` §12.3). The outgame
half (equip, unlocks, `run_mod`) lives in `features/meta/traits/`. **My team only** —
the AI never has traits.

## Files
| File | Class | Role |
|---|---|---|
| `TraitHooks.gd` | `TraitHooks` (Node, `_bs.trait_hooks`) | Parses `match_ctx.traits` into `KEY_*` sums, exposes query functions, holds the tiny per-match runtime state (first draw done, first card of the phase used) |
| `TraitBanner.gd` | `TraitBanner` (CanvasLayer) | "감독 특성" card shown once at the opening (GAMBIT → BATTLE), fades out after ~3.7s, never takes input; white `BattleTheme.gold_box()` plate, amber title, dark lines |

## Input
`GameManager.match_ctx.traits = [{id, key, p1, p2}]`, written by
`MatchFlow._launch_battle` (`TraitSystem.ingame_traits`). Read **only when
`match_ctx.active`** — a standalone run (or a stale ctx) has no traits. Same key
twice → `p1` summed; each `cost_tick` entry ticks on its own `p2`.

## Lifecycle
- Built in `BattleSim._ready` **before** `_populate_from_data_loader()`, because the
  opening strategy points are seeded inside it (`seed_side_costs`). `_ready` reads the ctx.
- `reset_runtime()` — per-match state back to the opening; `_on_restart_pressed` calls it.
- `_process` waits for `game_phase != GAMBIT`, spawns the banner once, then turns itself off
  (it never runs without traits).

## Keys → hook sites
The computation stays where it already lived; each site makes one query.

| key | Query | Hook site | Effect |
|---|---|---|---|
| `open_cost` | `open_cost_bonus()` | `BattleSim.seed_side_costs` | `player_cost += Σp1` at the opening (on top of the blue head start) |
| `first_draw` | `consume_auto_draw_count()` | `CardPhaseManager.do_battle_turn` (auto-draw) | first auto-draw of the match takes `max(0, 1 + Σp1)` cards; later draws 1 |
| `hand_size` | `hand_size_delta()` | `BattleSim.max_hand_size_for(is_player)` → `_trim_hand_overflow` | player cap `max(1, MAX_HAND_SIZE + Σp1)` |
| `first_card_cost` | `first_card_cost_delta(is_player)` | `BattleSim.effective_cost_for` (single cost funnel) | first card of each 작전 단계 costs `±Σp1` (0 floor via the funnel's clamp) |
| `cost_tick` | `cost_tick_gain(turn)` | `CardPhaseManager.do_battle_turn` (economy gate) | `+p1` at turns `ECONOMY_START_TURN + k·p2` (k ≥ 1), only while `player_cost < PHASE_THRESHOLD` (same rule as `COST_RECOVERY`) |

### `first_card_cost` bookkeeping
- `first_card_used` flips in `_play_card_direct` right after the cost is paid
  (`on_player_card_paid`).
- The play snapshot stores it as `trait_first_used`; `_restore_from_snapshot` (every
  cancel path — discard / search / keep picks, engage VS cancel) puts it back,
  so a refunded first card is still "first".
- `reset_phase()` runs in `start_card_phase` **and** `end_card_phase`, so during BATTLE the hand
  shows the next phase's first-card price and `_player_turn_ready` sees the same number.
- Cards that are `free_this_phase` or cost -1 return early from the funnel and are never touched.

## Display
`display_lines()` — `"<name> · <desc>"` from `TraitSystem.row(id)` / `desc_of(id)`, or a
key-based fallback when the id is unknown (hand-made ctx). `TraitBanner` sits at 30 % of the
viewport height, centred, layer 3 (above the card description layer, below modals) — inside the
battlefield, clear of the top chrome and the bottom gesture zone, so no safe-area offset.

## Tuning
No const keys — every number comes from `traits.csv` (`p1` / `p2`). Banner timings are
local constants in `TraitBanner.gd`.
