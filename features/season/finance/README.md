# finance/ — budget · facilities (M6)

Contract: `docs/outgame_dev_plan.md` §11 (M6) and §14 (T6 — finance stat, special spending).
State `season_state.finance` (shape owned here). Tuning values live only in `data/csv/const.csv`
(`FINANCE_*` · `FINANCE_STAT_*` · `FSPEC_*`), `data/csv/facilities.csv` and
`data/csv/finance_specials.csv` — this README names keys, never numbers.

| File | Role |
|---|---|
| `FinanceSystem.gd` | `class_name FinanceSystem` (static). Run init, week-end settlement, match bonus, allocation, facility upgrade, `income_mult` / `upkeep_mult` / `salary_cost` (traits × finance stat × specials), the three outside multipliers, special spending (rows, block reasons, buy, week tick), number formatting (`fmt` / `fmt_signed`). |
| `FinancePanel.gd` + `UI_View_FinancePanel.tscn` | Hub manage card 「재무」 (static `hub_summary`) + the `HubSheet` body (static `open` → `create()` → added to `sheet.body`), incl. the 특별 지출 section. Layout lives in the scene (see "Sheet scene" below). The 지난 주 정산 sponsor / upkeep labels show `보정 ×m` from `income_mult` / `upkeep_mult` (the entry's own value if recorded, else the current one; hidden at ×1.00) — `_sponsor_label` / `_upkeep_label`. |
| `UI_Comp_FinanceAmountRow.tscn` · `UI_Comp_FinanceAllocRow.tscn` · `UI_Comp_FinanceSpecialRow.tscn` · `UI_Comp_FinanceHistoryRow.tscn` | Item scenes of the sheet (no script): a 지난 주 정산 line · one 흑자 배분 axis · one 특별 지출 row · one 최근 기록 line. |

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
| `manual_profit_weeks` | int | Settled weeks with `net ≥ 0` while `StaffSystem.owner(state, "finance") == "manager"` — trait unlock `finance_manual_profit:N` (M8). Read via `manual_profit_weeks(state)`. |
| `specials` | Array of `{id, name, kind, p1, p2, weeks_left, cost, bought_week}` | Running special spending (§14). Params are a snapshot of the CSV row at purchase (p1 / p2 stay strings). `weeks_left` loses one per `settle_week`; the entry is dropped at 0. |
| `week_special_spend` · `week_special_buys` | int · Array[String] | Spent on specials since the last settlement and the names bought (history / toast), reset by `settle_week`. |
| `history` | Array of entries | Last `FINANCE_HISTORY_WEEKS` settlements, oldest first. |

History entry (also what `settle_week` returns, plus `toast`):
`{week_no, phase, phase_week, sponsor, income_pct, trait_income_pct, trait_upkeep_pct, finance_stat, income_mult, upkeep_mult,
special_income_pct, special_upkeep_pct, special_salary_pct, specials: Array[id] (running during the week),
special_spend, special_buys: Array[name], specials_expired: Array[name], bonus, wins, losses, income, salaries, upkeep,
expense, net, reserve, alloc{training, facility, welfare} (amounts), unpaid, balance, fund, level,
delegated, cuts: Array[String]}`.

## Week-end settlement (`settle_week`)
1. `income = sponsor_income(state, level) + week_bonus` (bonus may be negative), where
   `sponsor_income = round(sponsor_base × income_pct / 100 × income_mult(state))`.
2. `expense = salary_cost(state) + upkeep_cost(state, level)`, where
   `upkeep_cost = round(facility upkeep × upkeep_mult(state))` and
   `salary_cost = round(StaffSystem.weekly_salary_total × (1 + special_pct(salary) / 100))`.
   `projection()` / `weekly_fixed_cost()` call the same helpers, so the panel and the settlement agree.
   The history entry's `income_pct` stays the facility percent; the trait sums are `trait_income_pct` / `trait_upkeep_pct`,
   the finance stat used is `finance_stat`, the special sums `special_*_pct`.

### `income_mult` / `upkeep_mult` — the single sponsor × / upkeep × the UI reads
| Function | Formula |
|---|---|
| `income_mult` | `TraitSystem.run_pct_mult(income_pct) × finance_stat_income_mult × (1 + special_pct(income)/100)` |
| `upkeep_mult` | `TraitSystem.run_pct_mult(upkeep_pct) × finance_stat_upkeep_mult × (1 + special_pct(upkeep)/100)` |
| `finance_stat_income_mult` | `1 + (F − FINANCE_STAT_PIVOT) × FINANCE_STAT_INCOME_STEP / 100` (floored at 0) |
| `finance_stat_upkeep_mult` | `max(FINANCE_STAT_UPKEEP_MULT_MIN, 1 − (F − FINANCE_STAT_PIVOT) × FINANCE_STAT_UPKEEP_STEP / 100)` |

`F = StaffSystem.effective(state, "finance")` — the **cover rule** value (manager + mods, assistant, finance
staff, whichever is highest), so it is continuous: a good finance staffer earns more and pays less, a weak
manager running finance alone pays a little extra. Who decides the allocation (`is_delegated`) is separate.
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
| `training_exp_mult` | `train_exp_pct/100 × (1 + effects.training_pct/100) × (1 + special_pct(train)/100) × (penalty ? 1 − FINANCE_UNPAID_TRAIN_PENALTY_PCT/100 : 1)` |
| `mastery_mult` | `mastery_pct/100` |
| `incident_mult` | `max(FINANCE_INCIDENT_MULT_MIN, incident_pct/100 × (1 − effects.welfare_pct/100) × (1 + special_pct(incident)/100))` |

## Special spending (특별 지출, §14 T6)
The sink for surplus balance, and the low-budget tools M6 left for later. Rows live in
`data/csv/finance_specials.csv` (`id, name, kind, cost, p1, p2, weeks, cond, desc`, Korean names / desc).
Bought from the sheet, **paid from the balance at once** (not part of the week's `net`), effect for
`weeks` settlements.

| `kind` | `p1` | `p2` | Effect |
|---|---|---|---|
| `coach_hire` | stat key (`StaffSystem.STATS`) | delta | `StaffSystem.add_mod(state, p1, p2, weeks, "특별 지출 · <name>")` — lifts the **manager's** value; decayed by `StaffSystem.decay_mods` on the same cadence |
| `camp` | train EXP % | — | `special_pct(train)` |
| `sponsor_deal` | income % | train EXP % (downside, may be 0) | `special_pct(income)`, `special_pct(train)` |
| `upkeep_delay` | upkeep % | incident % (downside) | `special_pct(upkeep)`, `special_pct(incident)` |
| `salary_cut` | salary % | train EXP % (downside) | `special_pct(salary)`, `special_pct(train)` |

`special_pct(state, axis)` sums `p1` / `p2` of running entries per `SPECIAL_AXES`. Kinds map to the low-budget
tools of the plan: `sponsor_deal` (sponsor deals), `upkeep_delay` (maintenance delay), `salary_cut` (salary
renegotiation); `coach_hire` / `camp` / the expensive `sponsor_deal` rows are the rich-team sinks.

**Condition** (`cond`, clauses joined by `&`, all must hold; `special_cond_reason`): `facility_min:N`,
`facility_max:N`, `sponsor_max:N` (team `sponsor_base`), `balance_max:N`, `last_wins_min:N` (wins in the last
settled week). An unknown clause blocks the row (`조건 오류`).

**Block reasons** (`special_block_reason`, in order — the button shows the first): unknown row · already running
(`진행 중 — n주 남음`, one entry per id) · `FSPEC_MAX_ACTIVE` running · condition unmet · no effect
(`coach_hire` whose lifted manager value would not beat the current cover — `coach_hire_gain`; `salary_cut`
with no staff salaries; `upkeep_delay` with no upkeep) · balance < cost.

**Week end**: `settle_week` computes everything with the running specials, then `_tick_specials` lowers
`weeks_left` and drops finished ones; their names go to `specials_expired` and the toast
(`… · 특별 지출 N · 만료: <names>`).

## UI
- **Hub card**: title `재무 · 시설 LvN`, value = balance, sub = last week's net (`· 삭감` after a hard cut,
  `첫 정산 전` before the first one), owner badge = `StaffSystem.owner_name(state, "finance")`. Alert dot when
  balance < one week of fixed cost (`is_low_balance`), a training penalty is running, or last week had a hard cut.
- **Sheet** (`HubSheet` body = one `FinancePanel` instance, refilled in place after every change): balance + fund, owner line, this week's
  projection (`projection`), warnings; 지난 주 정산 (income / expense lines, net, where the surplus went,
  cut lines, special spend / expiries); 흑자 배분 (bars, steppers when manual, active effects); 시설 (current /
  next level effects, cost, upgrade button); 특별 지출 (running entries, then one row per CSV row: name,
  effect line `special_effect_text` · weeks, desc, and a two-step button — `구매 −N` / `계약 무료` →
  「한 번 더 눌러 확정」 → buy; disabled with the block reason); 최근 기록 (latest `RECENT_ROWS` weeks).
  Only one special row is armed at a time (`_special_armed`; the facility button's `_upgrade_armed`).
- **F6 preview** — run `UI_View_FinancePanel.tscn` alone and it fills dummy data (`resources/UiPreview.gd`):
  in-memory run with two `settle_week`s (last week + history rows), bound without a sheet.
- **Sheet scene** (`UI_View_FinancePanel.tscn`, root `VBoxContainer` top-wide 24 short of the body width — scroll-bar
  room; theme `OutgameTheme.tres`). The sheet's scroll height follows the root's height (`resized` →
  `set_body_height`), so the scene's `Tail` spacer is the bottom gap.
  ```
  FinancePanel (VBox)
  ├ %Empty            no run (hidden)
  └ %Main (VBox)
    ├ Header (116)    BalanceCaption · %Balance (colour = low balance) | FundCaption · %Fund
    ├ %OwnerLine · %Projection · %LowBalance · %Penalty
    ├ LastWeekSection (Title · Divider · Gap) · %LastWeekEmpty
    ├ %LastWeek       %FinanceAmountRow_Sponsor %FinanceAmountRow_Bonus %FinanceAmountRow_Salaries %FinanceAmountRow_Upkeep · Divider · NetRow (%Net)
    │                 · %AllocLine · %Cuts (template line) · %SpecialSpend · %SpecialsExpired
    ├ AllocSection · %AllocIntro · %AllocDelegated · %Axes (FinanceAllocRow ×3) · %Effects
    ├ FacilitySection (%FacilityTitle) · %FacNow · %FacNext · %FacCost
    │                 · %Upgrade (Primary) / %UpgradeConfirm (Dark) / %UpgradeBlocked (Ghost, disabled)
    ├ SpecialsSection · %SpecIntro · %Running (template line) · %RunningGap · %Specials (FinanceSpecialRow)
    ├ HistorySection · %HistEmpty · %History (FinanceHistoryRow)
    └ Tail
  ```
  Code owns: texts, which optional lines / buttons show, data colours (balance / net / history signs,
  affordable or not, axis fill colours),
  the share-bar fill width (`anchor_right`). List rows are reused across refills (`_ensure_rows`), so a
  tapped button is never freed while emitting; the scene's sample rows are dropped in `_ready`.
  Template-line lists (`%Cuts`, `%Running`) duplicate their first `Label`. Fixed-colour lines are scene
  variations: `%Fund` `LinkLabel` 44, `%LowBalance` · `%Penalty` · `%Cuts` line · history `%Cut` `NegativeLabel` 22,
  `%Running` line `PositiveLabel` 22.
- The sponsor × text in 지난 주 정산 is owned by §14 T3 (it reads `income_mult`).
