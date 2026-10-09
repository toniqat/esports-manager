# Run balance — score · currency · EXP (T2)

Reverse-solves the run-settlement constants (`RUN_*` · `PASS_*` in `data/csv/const.csv`,
`data/csv/pilot_levels.csv` EXP column, `data/csv/manager_levels.csv`) from a headless run
simulation, against the targets fixed in `docs/outgame_dev_plan.md` §14.0. The formulas
themselves live in `features/meta/run_result/RunResult.gd` (README: same folder); the tool is
`features/meta/run_result/sim/` (README section "Run simulator").

Measured 2026-10-07 on commit `e75f47d` + this change. Numbers here are a **snapshot** —
`const.csv` is the source of truth; re-run the sim after changing the season structure,
the AI quick-sim, or the score formula.

## 1. Method
1. `RunSim.tscn` plays whole runs through the real code: `GameManager.start_run` → live
   `Season.tscn` → coach training board (`TrainingBoard.auto_arrange`, applied Mon–Fri) →
   Sat / Sun player match + that day's AI matches → `SeasonHub._end_week` (finance / mastery /
   mental close, calendar tick, playoff / INTL bootstrap) → until the hub's own run-end
   handler fires (playoff cut missed, playoff / INTL loss, or REGULAR_INTL title).
   Settlement = `RunStats.finalize_phase` + `RunResult.build_result` (pure). No user:// writes.
2. **Match outcomes.** Player matches skip MatchFlow / BattleSim and use the AI quick-sim
   coin (`InternationalTournament.team_avg_stat` ratio, the same one AI-vs-AI matches use),
   with the player's side multiplied by **`edge`**. `edge` = 1 means "plays exactly like the
   AI"; the real player gains over that from ban / pick, mech assignment and card play, so
   `edge` is the free parameter that stands in for skill. Stat rows are zero (as in the
   MatchFlow cheat result); the match MVP is a random pilot of the winning side.
3. One per-run CSV of raw counts (phases cleared, wins, titles, matches, pilot EXP) per batch.
   Every score / reward term is linear in those counts, so the constants were solved offline
   on the raw counts and then confirmed by an in-engine batch with the final values (§5).

### Assumptions
- Setup: random team (0..7), random scenario, one random **starter** pilot per role, all
  **Lv1**, test run → **no manager traits** (`bonus_points` = 0, so `RUN_SCORE_PER_BONUS` is
  not exercised and was left as is).
- Not simulated: press answers, mental incidents / evening sessions, finance / staff
  decisions, match mastery. None of them feeds the score directly.
- **Reference player = `edge` 4.0** — the edge whose mean phase reached is in the plan's
  "average run reaches phase 1~2" band (mean 1.47, median 1; see §2).
- **"Average run"** (the unit every target is written in) = a run that **ends at phase 1 or 2**
  (fails in PRESEASON_INTL or MIDSEASON), pooled over all batches (570 runs). This is the
  literal reading of §14.0 "평균 런(페이즈 1~2 도달)". Its score is almost independent of
  `edge` (it is fixed by the phase reached), which makes it a stable anchor. The expected run
  of the edge-4 player is larger (clears pull the mean up) — see §4 for both bases.
- **Pilot EXP target** — "a regularly used pilot" = a pilot in the lineup every run; EXP only
  (the levelup currency is a second, independent route — §3).

## 2. Measured distributions (current code, 200 runs per edge)
Phase reached (share of runs that **ended** there; C = clear):

| edge | 0 | 1 | 2 | 3 | 4 | 5 | C | mean reached | median | wins | matches | weeks |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.0 | 81.0% | 15.5% | 3.5% | 0 | 0 | 0 | 0 | 0.23 | 0 | 4.6 | 8.7 | 5.5 |
| 1.5 | 70.5% | 22.0% | 5.0% | 2.0% | 0 | 0 | 0.5% | 0.41 | 0 | 6.4 | 10.2 | 6.6 |
| 2.0 | 59.0% | 25.5% | 6.5% | 5.5% | 0.5% | 2.0% | 1.0% | 0.72 | 0 | 8.9 | 12.5 | 8.2 |
| 3.0 | 46.0% | 29.0% | 13.0% | 4.0% | 3.0% | 2.0% | 3.0% | 1.04 | 1 | 12.1 | 15.6 | 10.3 |
| **4.0** | 38.5% | 29.5% | 8.0% | 7.5% | 3.5% | 4.0% | 9.0% | **1.47** | 1 | 15.8 | 19.0 | 12.6 |
| 5.0 | 33.0% | 27.0% | 10.0% | 9.0% | 3.5% | 6.0% | 11.5% | 1.75 | 1 | 18.5 | 21.4 | 14.2 |
| 50 (60 runs) | 1.7% | 5.0% | 0 | 5.0% | 3.3% | 3.3% | 81.7% | 4.58 | 5 | 45.3 | 46.1 | 30.4 |

At AI parity (edge 1) 81% of runs die in PRESEASON: making the top 4 of 8 and then winning
SF + F is ≈ 0.5 × 0.25. A full campaign is 36 weeks and 36 player matches (one a week; consts below were tuned for the old 50 — retune pending).

Edge 4.0, pooled 600 runs (`e4.0` + two verification batches), per end class:

| ended at | share | wins | titles | matches | pilot EXP / pilot | score (before) | score (after) |
|---|---|---|---|---|---|---|---|
| phase 0 | 34.0% | 5.9 | 0 | 8.3 | 125 | 59 | 59 |
| phase 1 | 33.0% | 8.8 | 1 | 11.0 | 172 | 388 | 388 |
| phase 2 | 9.7% | 23.1 | 2 | 27.5 | 437 | 831 | 831 |
| phase 3 | 7.7% | 25.5 | 3 | 29.8 | 477 | 1155 | 1155 |
| phase 4 | 5.3% | 40.3 | 4 | 46.3 | 745 | 1603 | 1603 |
| phase 5 | 3.2% | 42.5 | 5 | 48.9 | 787 | 1925 | 1925 |
| clear | 7.2% | 44.8 | 6 | 50.0 | 814 | 2748 | 2398 |

Note `titles == phases_cleared` on every run (each cleared phase *is* a title), so
`RUN_SCORE_PER_PHASE` and `RUN_SCORE_PER_TITLE` act as one per-phase value; only their sum matters.

## 3. Solving
Average run (pooled, 570 runs ending at phase 1–2): **score ≈ 487**, pilot EXP ≈ 228 per pilot.
Clear runs (121 across edges ≥ 3): 6 phases + 6 titles + ≈ 47 wins.

| target (§14.0) | equation | result |
|---|---|---|
| clear ≈ 5 × average | 6·(PHASE + TITLE) + 47·WIN + CLEAR = 5 · 487 | keep PHASE / WIN / TITLE, `RUN_SCORE_CLEAR_BONUS` = 150 |
| average run ≈ 1 pilot pull | 487 · `RUN_CURRENCY_PER_SCORE` = `GACHA_PILOT_PRICE` | 0.21 |
| manager Lv25 ≈ 40 runs | 40 · 487 · `RUN_MGR_EXP_PER_SCORE` = `manager_levels`[25] | 0.84 (curve kept) |
| pass 25 ≈ 7 runs / week | 7 · 487 · `PASS_EXP_PER_SCORE` = 24 · `PASS_EXP_PER_LEVEL` | 0.71 (per level kept) |
| pilot max Lv ≈ 15 runs | 15 · 228 = `pilot_levels`[max].exp_required | curve × 1.0625 |

Secondary values (no explicit target, kept proportional):
- `RUN_LEVELUP_PER_SCORE` — an average run pays ≈ one mid-curve level-up (≈ 30, the Lv4→5
  cost); the sum of `levelup_cost` to the max level is 440, so the currency route alone also
  maxes one pilot in ≈ 15 runs — the same pace as the EXP route.
- `PASS_OVERFLOW_OUTGAME` — pass EXP past Lv25 converts to outgame currency; scaled so the
  overflow stays worth ≈ 40% of the run's own currency, the same ratio as before.
- `manager_levels.csv` was **not** reshaped: with the new rate an average run is ≈ 409 EXP,
  i.e. Lv3 after one run, ≈ Lv7 after 5, ≈ Lv17 after 20, Lv25 after 40 — a reasonable curve.

### Values before → after
| key / table | before | after |
|---|---|---|
| `RUN_SCORE_PER_PHASE` | 100 | 100 |
| `RUN_SCORE_PER_WIN` | 10 | 10 |
| `RUN_SCORE_PER_TITLE` | 200 | 200 |
| `RUN_SCORE_CLEAR_BONUS` | 500 | **150** |
| `RUN_SCORE_PER_BONUS` | 5 | 5 (not exercised — no traits in test runs) |
| `RUN_CURRENCY_PER_SCORE` | 0.10 | **0.21** |
| `RUN_MGR_EXP_PER_SCORE` | 0.50 | **0.84** |
| `RUN_LEVELUP_PER_SCORE` | 0.02 | **0.062** |
| `PASS_EXP_PER_SCORE` | 0.20 | **0.71** |
| `PASS_EXP_PER_LEVEL` | 100 | 100 |
| `PASS_OVERFLOW_OUTGAME` | 20 | **12** |
| `pilot_levels.exp_required` Lv2..10 | 100 · 250 · 450 · 700 · 1000 · 1400 · 1900 · 2500 · 3200 | **110 · 270 · 480 · 740 · 1060 · 1490 · 2020 · 2660 · 3400** |
| `manager_levels.csv` | 0 … 16200 | unchanged |

## 4. Targets before → after
"Average run" basis (the solve basis) and the edge-4 player's **expected** run (all 600 runs,
clears included) for comparison:

| target | goal | before (avg run) | **after (avg run)** | after (edge-4 expected run) |
|---|---|---|---|---|
| outgame per run / pilot pull | ≈ 1 | 0.49 | **1.02** | 1.33 |
| runs to manager Lv25 | ≈ 40 | 66.6 | **39.7** | 30.4 |
| runs to pass Lv25 | ≈ 7 | 24.6 | **7.0** | 5.3 |
| clear score / average score | ≈ 5 | 5.69 | **4.97** | 3.8 |
| runs to pilot max Lv (EXP only) | ≈ 15 | 14.0 | **14.9** | 11.3 |
| levelup currency per run | — | 9.3 | 29.7 | 38.9 |

The two bases differ by the clear / deep-run tail: a player at the reference skill earns
≈ 1.3× the "average run" per run. If the targets are meant as the expected pace of a typical
player instead, divide `RUN_CURRENCY_PER_SCORE` · `RUN_MGR_EXP_PER_SCORE` ·
`PASS_EXP_PER_SCORE` by ≈ 1.3 — the sim prints both bases.

## 5. In-engine confirmation
Final values, `game.db` rebuilt, edge 4.0, 200 runs (seeds 31 + 32, mean phase reached 1.53,
10 clears at 2399 points). This sample's 83 average runs lean slightly more to phase 2
(score 514 vs the pooled 487), hence the slightly faster figures — within sampling noise.

| | avg run | all |
|---|---|---|
| outgame / pilot pull | 1.07 | 1.35 |
| runs to manager Lv25 | 37.5 | 29.9 |
| runs to pass Lv25 | 6.6 | 5.2 |
| runs to pilot Lv10 | 13.9 | 11.0 |

## 6. Re-running
PowerShell 5.1, repo root (≈ 3–6 s per run; the hub views log image-load noise headlessly):
```
& "D:\Projects\Godot Project\godot.exe" --headless --path . res://features/meta/run_result/sim/RunSim.tscn -- --runs=200 --edge=4 --seed=1 "--out=$env:TEMP\t2_runs.csv" | Select-String "=== RunSim" -Context 0,45
```
Args: `--runs` · `--edge` · `--seed` · `--level` · `--team` · `--scenario` · `--no-coach` ·
`--out`. Change CSV values → **Rebuild game.db** first (`data/README.md`). Several batches can
run in parallel (separate processes); per-run time grows slowly within one process, so prefer
2 × 100 over 1 × 200 when waiting matters.

## 7. Known gaps
- The player-skill model is a single multiplier; real outcomes depend on cards / bans and on
  pilot levels (all Lv1 here — a profile with levelled pilots plays at a higher effective edge).
- Trait bonus points are not simulated (`RUN_SCORE_PER_BONUS` unchanged).
- Phase 2 → 3 is a cliff in wins (MIDSEASON has a 14-match league), which is why a phase-2
  run is worth ≈ 2× a phase-1 run; the score keeps that shape on purpose (wins count).
