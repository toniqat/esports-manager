# mental/ — trust · interviews · outings · incidents · press · true ending (M7)

Contract: `docs/outgame_dev_plan.md` §11. State `season_state.trust` / `outings` / `mental` / `pilot_mods`.
Tuning lives in `data/csv/const.csv` (`TRUST_*`, `MENTAL_*`, `TRUE_ENDING_*`) — no values here.

| File | Role |
|---|---|
| `MentalSystem.gd` | `class_name MentalSystem` (static). State + flow: run init, week reset, weekly limits, evening action (interview / outing / pass), incident roll + resolve, press session + resolve, outing training-EXP penalty, true-ending pilots. Every entry point takes the `season_state` dictionary (no autoloads → headless-testable). |
| `MentalEvents.gd` | `class_name MentalEvents` (static). `mental_events` table (game.db) → parsed rows; the `lines` / `effects` / `cond` grammar; row selection (cond, manager type, weights); `apply_choice` (mental check + clauses). |
| `PilotMods.gd` | `class_name PilotMods` (static, base). Temporary per-pilot stat mods `[{pilot_id, stat, delta, weeks_left, source}]`; `weeks_left = -1` lasts until the next own match. `apply_to` is only ever called on a **roster copy** (MatchFlow). |

The dialogue UI is `features/season/press/MessengerView.gd` (shared with the press conference);
the evening card + incident card live on the week screen (`features/season/week/`).

## Rules
- **Trust** `{"<pid>": int}` for my 5 pilots, clamped `[TRUST_MIN, TRUST_MAX]`, starts at `TRUST_START`.
  It affects **only** outing unlock (`TRUST_OUTING_MIN`) and the true ending — no match stat effect.
- **Evening** (Mon–Fri, one action per day): interview / outing / pass. Leaving the day without
  choosing records a pass. Manager-only — staff never interview or go out.
  - Interviews per week = `MENTAL_INTERVIEWS_BASE + manager mental / MENTAL_INTERVIEWS_PER_STAT`
    (capped `MENTAL_INTERVIEWS_MAX`), manager mental = `StaffSystem.manager_value(state, "mental")`.
  - Outing: `MENTAL_OUTINGS_PER_WEEK` per week, only with a pilot at trust ≥ `TRUST_OUTING_MIN`.
    Effects: the row's clauses (trust +, `pmod:all:+N:-1` until next match) + `outings[pid] += 1` +
    **next training day** EXP × `MENTAL_OUTING_EXP_MULT` for that pilot
    (`training_exp_mult(state, pid, day)`; `TrainingBoard` (M3) multiplies it; a Friday outing
    hits next Monday — `end_week` carries it over).
  - Interview / outing checks are judged with the manager's own mental.
- **Incidents** roll once per Mon–Fri when the week screen first shows that day:
  chance `MENTAL_INCIDENT_CHANCE × FinanceSystem.incident_mult(state) × TraitSystem.run_pct_mult(state, "incident_pct")`,
  target = a random pilot of mine.
  A pending incident opens its dialog by itself and must be answered; checks use
  `StaffSystem.effective_for_incident(state)` (staff can cover).
- **Press** (once per week before training): one `press` row per week. Rows with `mention=mvp|worst`
  target the last own match's MVP (if mine) / my lowest MVP-metric pilot (`run_stats.matches`);
  generic rows move whole-team trust or add a temporary manager-stat mod (`StaffSystem.add_mod`).
  Checks use the manager's own mental.
- **True ending** = run **clear** + outings with that pilot ≥ `TRUE_ENDING_OUTINGS`.
  `true_ending_pilots(state)` → `RunResult` puts `result.true_endings` on a clear only →
  `ProfileManager.apply_run_result` records `achievements[pid].true_ending`.
- **Determinism / idempotency**: draws and checks are seeded from
  `hash([run_seed, week_key, day, purpose, extra])` (`week_key = "<phase>-<phase_week>"`), so a
  reload never rerolls. Every action is recorded **before** its dialog opens and settled at most
  once — `finish_evening` / `resolve_incident` / `resolve_press` return the stored outcome on a
  second call. Re-entering a weekday (after a Sat match, after load) redraws from the record.

## `season_state.mental` shape (string keys; numbers may load back as floats — always `int()`)
```
{
  "week": "<phase>-<phase_week>",   # week the fields below belong to ("" after end_week)
  "interviews_used": int, "outings_used": int,
  "days": {"<day 0..4>": {
      "evening":  {action: "interview"|"outing"|"pass", pilot_id, event, choice (-1 = open), outcome{}},
      "incident": {} (rolled, none) | {event, pilot_id, choice (-1 = pending), outcome{}}
  }},
  "fatigue": {"<pid>": day},        # training day whose EXP is cut (≥5 = next week, shifted by end_week)
  "press": {week, event, pilot_id, choice, outcome{}},
}
```
`outcome` = `{checked, ok, chance, say: [String], notes: [String]}` (notes are the player-facing effect chips).
`end_week` resets `week` / counters / `days` and shifts `fatigue`; `_week()` also resets when the key changes.

## `mental_events.csv` grammar
Columns: `id, kind, manager_type, stage, cond, lines, choices, effects, weight`.

- `kind` — `interview` / `outing` / `incident` / `press`.
- `manager_type` — -1 any, 0 운영형 (m), 1 실전형 (f). Rows for the other type never appear;
  rows for the run's type weigh × `MENTAL_TYPE_WEIGHT_MULT`. Outings pick **strictly** by stage:
  a typed row for the stage beats the generic one.
- `stage` — outing number 1..N (`outings + 1`; past the last written stage the highest repeats), else 0.
- `weight` — draw weight (int ≥ 0).
- `lines` — `|`-joined. Plain = the other side (left bubble with portrait), `>text` = manager
  (right bubble), `*text` = centred narration, `@text` = tag (press outlet / incident name, used in
  headers, not drawn as a bubble). `{name}` → target pilot name (also in `choices` and `say:`).
- `choices` — `|`-joined manager answers (2–3).
- `effects` — `|`-joined, **one entry per choice**; clauses inside an entry joined with `;`.

### Clause vocabulary
| Clause | Effect |
|---|---|
| `trust:+N` | target pilot trust ± N |
| `trust_all:+N` | all my 5 pilots' trust ± N |
| `pmod:<stat\|all>:<delta>:<weeks>` | target pilot temporary stat mod (`PilotMods.add`); `weeks = -1` = until next own match |
| `pmod_all:<stat\|all>:<delta>:<weeks>` | same for all my pilots |
| `smod:<stat>:<delta>:<weeks>` | temporary manager-stat mod (`StaffSystem.add_mod`, `stat` ∈ `StaffSystem.STATS`, weeks > 0) |
| `say:<text>` | reply line (left bubble) after the answer |
| `chk:<±N>` | adjusts this entry's check chance by N percentage points |
| `ok>…` / `ng>…` | prefix: clause applies only on a passed / failed mental check. An entry with any gated clause rolls one check: chance = `MENTAL_CHECK_BASE + (judge − MENTAL_CHECK_PIVOT) × MENTAL_CHECK_PER_POINT + chk`, clamped `[MENTAL_CHECK_MIN, MENTAL_CHECK_MAX]`. |

`<stat>` for pilots = `PlayerData.STAT_KEYS` or `all`. Bad clauses parse as `invalid`
(skipped) and are reported by `MentalEvents.lint()`.

### Cond vocabulary (`;`-joined, all must hold)
| Token | Holds when |
|---|---|
| `trust>=N` / `trust<N` / `trust=N` | target pilot's trust |
| `outings>=N` / `outings<N` | target pilot's outing count |
| `role=N` | target pilot's `GameEnums.Role` |
| `week>=N` / `week<N` | `phase_week` |
| `last=win` / `last=loss` | last own match result (`run_stats.matches`) |
| `mention=mvp` / `mention=worst` | press only — picks the target (last match MVP if mine / my lowest MVP metric); row skipped when none |

- **Trait `trust_gain`** (M8): `add_trust` adjusts only a rise — `max(0, delta + Σp1)` — so a
  rise never becomes a loss; drops pass through untouched.

## API (static, `state` = `season_state`)
`init_run` · `end_week` · `training_exp_mult(state, pid, day)` · `trust` · `outings` · `add_trust` ·
`true_ending_pilots` · `my_pilot_ids` · `interviews_per_week` / `interviews_left` / `outings_left` /
`outing_unlocked` / `can_interview` / `can_outing` · `evening` / `evening_done` / `begin_evening(state, day, action, pid)` /
`finish_evening(state, day, choice)` · `ensure_incident` / `incident_pending` / `incident_session` /
`resolve_incident` · `press_session` / `resolve_press` · `session_view(state, session)` → `{kind, event, pilot_id, tag, lines, choices}`.
