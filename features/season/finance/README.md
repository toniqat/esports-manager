# finance/ — budget · facilities (M6)

Contract: `docs/outgame_dev_plan.md` §11. State `season_state.finance` (shape owned here).
Tuning values live only in `data/csv/const.csv` (`FINANCE_*`) and `data/csv/facilities.csv` —
this README names keys, never numbers.

| File | Role |
|---|---|
| `FinanceSystem.gd` | `class_name FinanceSystem` (static). Run init, week-end settlement, match bonus, allocation, facility upgrade, the three multipliers, number formatting (`fmt` / `fmt_signed`). |
| `FinancePanel.gd` | Hub manage card 「재무」 (`hub_summary`) + `HubSheet` detail (`open`). |

## Entry points (called by base-owned code)
| Caller | Call |
|---|---|
| `GameManager.start_run` | `init_run(state, team_id)` — balance `FINANCE_START_BALANCE`, facility level = team package `facility_level`, `sponsor_base` = `teams.budget`, default manual allocation. |
| `SeasonHub._consume_pending_match_result` | `record_match(state, pm, won)` — adds `FINANCE_MATCH_WIN` / `FINANCE_MATCH_LOSS` (× `FINANCE_TOURNAMENT_MULT` when `pm.source` is not `league`) to the week bonus. Guarded by `pm.finance_recorded`. |
| `SeasonHub._end_week` (first, before the calendar) | `settle_week(state)` → week summary; its `toast` is shown on the next HUB. |
| `TrainingBoard` / `MechMastery` / `MentalSystem` | `training_exp_mult` / `mastery_mult` / `incident_mult`. |

## `season_state.finance`
All numbers go through JSON on save, so every read is `int()` / `float()`-wrapped; a state
missing keys (pre-M6 save) is re-initialised lazily by `_fin`, keeping what was there.

| Key | Type | Meaning |
|---|---|---|
| `balance` | int ≥ 0 | Cash. **Never negative.** (fixed key) |
| `facility_level` | int 1..max | Current facility level (`facilities.csv`). (fixed key) |
| `facility_fund` | int ≥ 0 | Money earmarked for the next upgrade (facility allocation). |
| `sponsor_base` | int | Weekly sponsor income = `teams.budget`, snapshotted at run start. |
| `alloc` | `{training, facility, welfare}` int % | The manager's **manual** split (sum 100). Ignored while finance is delegated. |
| `effects` | `{training_pct, welfare_pct}` float % | Bonuses active **this week**, produced by last week's allocation. |
| `penalty_weeks` | int | Weeks left of the unpaid-training penalty. |
| `week_bonus` · `week_wins` · `week_losses` | int | Match bonus accrued since the last settlement (reset by `settle_week`). |
| `week_no` | int | Settlements done this run (history label "N주차"). |
| `history` | Array of entries | Last `FINANCE_HISTORY_WEEKS` settlements, oldest first. |

History entry (also what `settle_week` returns, plus `toast`):
`{week_no, phase, phase_week, sponsor, income_pct, bonus, wins, losses, income, salaries, upkeep,
expense, net, reserve, alloc{training, facility, welfare} (amounts), unpaid, balance, fund, level,
delegated, cuts: Array[String]}`.

## Week-end settlement (`settle_week`)
1. `income = round(sponsor_base × income_pct / 100) + week_bonus` (bonus may be negative).
2. `expense = StaffSystem.weekly_salary_total + upkeep` (current level).
3. `net = income − expense`. One penalty week is consumed.
4. **Surplus (`net ≥ 0`)**: `FINANCE_RESERVE_PCT` of it is added to the balance; the rest (the
   pool) is split by `allocation_shares` (each share floored, rounding remainder to the largest share):
   - training → spent; next week's `training_pct = FINANCE_TRAINING_MAX_PCT × min(1, spend / FINANCE_TRAINING_FULL_SPEND)`.
   - facility → added to `facility_fund`.
   - welfare → spent; next week's `welfare_pct = FINANCE_WELFARE_MAX_PCT × min(1, spend / FINANCE_WELFARE_FULL_SPEND)`.
   Spending past the "full" amount is wasted — that cap is what makes a hand-tuned split beat the auto split.
5. **Deficit (`net < 0`)** — the bankruptcy rule below.
6. History entry appended (trimmed), week bonus counters reset, toast built
   (`재무 정산 ±N · 잔고 B`, or `재무 적자 −N · 긴급 삭감 K건 — 재무 카드 확인` when a hard cut happened).

### Bankruptcy rule — the balance never goes negative
Applied in order until the shortfall `need = −net` is covered:
1. **Allocation stops** — no surplus, so training / welfare support for next week is zero
   (cut line `훈련 · 복지 지원 중단`; this one alone is not a "hard" cut).
2. **Balance** pays as much as it can (not a cut).
3. **Facility fund** is raided (`시설 적립금 N 전용`).
4. Anything still unpaid is written off with **one forced cut**:
   - level > 1 → **facility downgrade by one level** (`시설 LvA → LvB 강등 (미납 N)`) — lower upkeep from next week;
   - level 1 → **training penalty**: `penalty_weeks = FINANCE_UNPAID_PENALTY_WEEKS`, training EXP
     × (1 − `FINANCE_UNPAID_TRAIN_PENALTY_PCT`) while it lasts (`훈련 지원 삭감 n주`).
   The written-off amount is recorded as `unpaid`.

A "hard cut" (steps 3–4) lights the hub card alert and marks the history row 「삭감」.

## Allocation — delegated vs manual
- `StaffSystem.is_delegated(state, "finance")` → **auto**: even thirds (training gets the odd percent);
  at max facility level it is half training / half welfare (nothing left to save for). Decent, not optimal
  (it can overshoot the "full" spends or under-fund the cheaper axis). The sheet says who handles it.
- Manager owns finance → **manual**: −/+ steppers per axis, `FINANCE_ALLOC_STEP_PCT` per tap, sum always 100.
  `+` takes from the largest other axis (then the next); `−` hands the freed share to the facility fund
  (or to training when lowering the fund). Default manual split = `DEFAULT_ALLOC`.
- Steppers instead of `HSlider`: the sheet body sits under `DragScroll`, which swallows horizontal drags.

## Facilities
- Effects per level (`facilities.csv`, percent, 100 = neutral): `train_exp_pct`, `mastery_pct`,
  `incident_pct`, `income_pct`; weekly `upkeep`; `upgrade_cost` = cost to reach the next level (0 at max).
- **Upgrade** from the sheet (two-step button: press → 「한 번 더 눌러 확정」 → press). Paid from
  `facility_fund` first, then `balance`; refused (button disabled with the reason) at max level or when
  fund + balance < cost. Takes effect immediately (multipliers, upkeep at the next settlement).
- Start level = team package `facility_level`.

## Multipliers
| Function | Formula |
|---|---|
| `training_exp_mult` | `train_exp_pct/100 × (1 + effects.training_pct/100) × (penalty ? 1 − FINANCE_UNPAID_TRAIN_PENALTY_PCT/100 : 1)` |
| `mastery_mult` | `mastery_pct/100` |
| `incident_mult` | `max(FINANCE_INCIDENT_MULT_MIN, incident_pct/100 × (1 − effects.welfare_pct/100))` |

## UI
- **Hub card**: title `재무 · 시설 LvN`, value = balance, sub = last week's net (`· 삭감` after a hard cut,
  `첫 정산 전` before the first one), owner badge = `StaffSystem.owner_name(state, "finance")`. Alert dot when
  balance < one week of fixed cost (`is_low_balance`), a training penalty is running, or last week had a hard cut.
- **Sheet** (`HubSheet`, rebuilt in place after every change): balance + fund, owner line, this week's
  projection (`projection`), warnings; 지난 주 정산 (income / expense lines, net, where the surplus went,
  cut lines); 흑자 배분 (bars, steppers when manual, active effects); 시설 (current / next level effects,
  cost, upgrade button); 최근 기록 (latest `RECENT_ROWS` weeks).

## Out of scope (later)
Low-budget tools — sponsor deals, maintenance delay, salary renegotiation. A rich team at max level
accumulates balance with nothing to spend it on yet; those tools are the intended sink.
