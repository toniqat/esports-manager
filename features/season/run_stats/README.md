# Run Stats — match MVP · phase POM

Contract: `docs/outgame_dev_plan.md` §10.1 ("경기 MVP" · "MVP 지표" · "페이즈 POM") and §10.4.
Weights are the `MVP_*` / `POM_*` keys of `data/csv/const.csv` (read with `ConstTable`) —
no values in this doc.

| File | class_name | Role |
|---|---|---|
| `RunStats.gd` | RunStats | **Static, pure** (no nodes, no state) — MVP metric, MVP pick, per-run aggregation into `season_state.run_stats`, phase POM |

## Callers
| Who | Call | When |
|---|---|---|
| `BattleSim.end_match` | `pick_mvp_index(rows, winner_side)` | match end — writes `pending_match.mvp_pilot_id`, opens the MVP view (`features/battle_sim/ui/README.md`) |
| `MvpView` | `top_role()` / `support_role()` | picks which metric line to show |
| `SeasonHub._consume_pending_match_result` | `record_match(state, pending_match)` | once per player match, **before** the result is applied to the schedule |
| `SeasonHub._on_phase_changed_close_pom` | `finalize_phase(state, new_phase - 1)` | `CalendarSystem.phase_changed` |
| `RunResult.settle_current_run` | `finalize_phase(state, current_phase)` | run settlement |

## MVP metric — `mvp_score(row) -> float`
Row = one `pending_match.pilot_stats` entry (`k d a dmg taken care role`; how each is counted:
`features/battle_sim/combat/README.md` "Match stats"). `d = max(d, 1)`.

- **Support** (last seat of `GameEnums.ROLE_DISPLAY_ORDER`):
  `MVP_W_KDA·(k + MVP_ASSIST_MULT_SUP·a)/d + MVP_W_SUP_CARE·(care + taken)/d`
- **Everyone else**: `MVP_W_KDA·(MVP_KILL_MULT·k + a)/d + MVP_W_DMG·dmg/d`,
  and **top** (first seat) adds `MVP_W_TANK·taken/d`.

`pick_mvp_index(rows, winner_side)` — best score among rows with `side == winner_side`
(ties → earlier row = earlier role seat in `pilots` order); -1 if none.
`pick_mvp` returns that row's `pilot_id`.

## `season_state.run_stats` (all dictionary keys are Strings — it goes through JSON)
```
{ "matches": [ {"phase": int, "won": bool, "mvp": pilot_id, "scores": {"<pid>": float}} ],
  "mvp_count": {"<phase>": {"<pid>": int}},
  "score_sum": {"<phase>": {"<pid>": float}},
  "pom_by_phase": {"<phase>": pilot_id},
  "wins": int, "losses": int }
```
- `record_match` — phase = `state.current_phase`; wins / losses from `winner_side` (0 = my team);
  every row's score goes into `matches[].scores` and `score_sum[phase]` (both teams); MVP from
  `mvp_pilot_id`, or `pick_mvp` if missing. Marks `pending_match.stats_recorded`, so a second
  call is a no-op. A payload without `pilot_stats` still counts the win / loss.
- **`wins` / `losses` appear only once a match has been recorded** — `ensure()` doesn't create
  them, because `RunResult` trusts these keys only when present and otherwise counts the
  schedule (older saves).
- `finalize_phase` — candidates = every pid with an entry in that phase's `score_sum` /
  `mvp_count` (either team); POM = max `POM_W_MVP·mvp_count + POM_W_SCORE·score_sum`
  (ties → more MVPs, then lower id). Already-closed phase or phase with no matches → no-op.
- Values read back from JSON may be floats — every read goes through `int()` / `float()`.

## Verification (headless, `extends SceneTree` script outside the repo)
Formula per role, `d = 0` ≡ `d = 1`, pick from winner side only, record idempotence, missing
`mvp_pilot_id` / `pilot_stats`, POM = argmax after a `JSON.stringify` / `parse` round trip,
finalize idempotence, empty-phase no-op, String keys survive JSON.
