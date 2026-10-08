# stress/ — in-match stress, awaken / panic test

The match half of pilot stress. Rules, tuning and the season state are in
`features/season/mental/` (`StressSystem`, README "Stress"); values in `data/csv/const.csv` `STRESS_*`.

| File | Role |
|---|---|
| `StressEvents.gd` | `class_name StressEvents extends Node` — BattleSim child module (`_bs.stress`), lazily added at the end of `BattleSim._ready()` (needs spawned pilots for `player_data_for`). Holds my pilots' stress / mood for this match, the test queue and the open view. |
| `StressEventView.gd` · `UI_View_StressEvent.tscn` | `class_name StressEventView extends CanvasLayer` (layer 55: above the HUD, below the MVP view). One test: top-centre toast, full-body art rising on a dim, result word + effect line, tap to continue. Built with `StressEventView.create()`. F6 = preview pilot 0, panic. |

## Flow
1. `init_for_match()` reads `match_ctx.stress` (`{"<pid>": int}`, written by `MatchFlow._finalize_rosters` via
   `StressSystem.snapshot`) for **team 0** pilots that have a persona. A pilot entering at or over the threshold
   starts **shaken** (`Mood.SHAKEN`, its stats were already cut on the roster copy) and is never tested.
   Standalone runs (`match_ctx.active = false`) track nobody.
2. `BattleSim.mark_pilot_dead` → `on_death(p)` (every death path: battlefield, cards, engage stage). Adds
   `STRESS_DEATH_MIN..MAX` (clamped). A pilot still at `Mood.NONE` that is now over the threshold is tested
   **now** (`STRESS_AWAKEN_CHANCE` → `AWAKEN`, else `PANIC`) and queued; the view opens deferred, after the
   current step finishes.
3. **The match stops immediately** while `is_busy()` (view open or queue not empty):
   `BattleSim._battle_tick_held` (auto tick + clock), `EngagePhaseManager._process` (stage steps, also breaks out
   of the step loop right after the death), `AiCardPlayer.run_ai_plays` (`await wait_idle()` after each card).
   The player's card phase is blocked by the view's full-rect input.
4. View sequence: toast `battle.stress.toast` → art → result (`revealed` → `_apply_mood`: hit / evasion of both
   stages × mood multiplier, growth multipliers rebuilt from the scaled `PlayerData` growth stats, then
   `refresh_growth_stats`) → tap → `closed` → next queued test, or `idle`.
5. `BattleSim.end_match` writes `pending_match.stress = final_values()` (`{"<pid>": int}`), then `abort()` drops
   any unshown test. `SeasonHub` → `StressSystem.record_match`. Awaken / panic are not saved.

## Display
- Strip cell `%Mood` (`ui/UI_Comp_PilotStripCell.tscn`, above the disc): mood word, variation from
  `StressEvents.mood_variation` (`StressMood{Awaken,Panic,Shaken}Label`), hidden at `Mood.NONE` / for enemies.
- Detail panel header `%StressBox` / `%Stress` (`ui/UI_View_PilotDetailView.tscn`): `StressSystem.line`, hidden for
  pilots without stress.
- Theme variations: `BattleTheme._add_stress_variations` (`StressEventAwakenLabel` · `StressEventPanicLabel` ·
  `StressMood*Label`), colours `BattleTheme.STRESS_*`.
- Text keys: `battle.stress.toast` · `battle.stress.effect.{awaken,panic}` (const placeholders), mood names
  `mental.ui.stress.mood.*`.
