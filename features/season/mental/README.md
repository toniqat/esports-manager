# mental/ — trust · stress · afternoon visit (focus training · story · outing) · incidents · press · true ending (M7, §15 D)

Contract: `docs/outgame_dev_plan.md` §11. State `season_state.trust` / `stress` / `outings` / `mental` / `pilot_mods`.
Tuning lives in `data/csv/const.csv` (`TRUST_*`, `STRESS_*`, `MENTAL_*`, `TRUE_ENDING_*`, §15 D `FOCUS_*` · `STORY_*` · `VISIT_*`) — no values here.
**Event data is authored in Draft** (`narrative/`, convention in `narrative/README.md`) and imported by
`addons/draft_import/` into `mental_events.csv` / `mental_texts.csv` / `data/l10n/src/mental.csv` (`mental.<event>.<id>`
rows) — do not hand-edit those any more, the next import overwrites them.
Event texts are l10n keys (`mental_texts.csv` → domain `mental`, D6). Display text is l10n keys (`mental` domain): code
keys use **4-segment** aliases `mental.ui.*` — a 3-segment `mental.x.y` matches the data rule `mental.{event_id}.{id}`
and gets no `L` constant. Mod clauses write `source = "mental:<event id>"` (`MOD_SOURCE_PREFIX`, an id — D7);
`MentalEvents.mod_source_text` shows the event kind (`term.activity.*` / `mental.ui.mod_source.incident`).

| File | Role |
|---|---|
| `MentalSystem.gd` | `class_name MentalSystem` (static). State + flow: run init, week reset, weekly limits, evening action (interview / outing / pass), incident roll + resolve, press session + resolve, outing training-EXP penalty, true-ending pilots. Every entry point takes the `season_state` dictionary (no autoloads → headless-testable). |
| `MentalEvents.gd` | `class_name MentalEvents` (static). `mental_events` + `mental_texts` tables (game.db) → parsed rows (texts as l10n keys); the `effects` / `cond` grammar; row selection (cond, manager type, weights); `apply_choice` (mental check + clauses + replies, keys / ids only); `outcome_view` · `note_texts` · `text` turn stored keys into display text (`Loc.t`, `{name}`). |
| `StressSystem.gd` | `class_name StressSystem` (static). Stress (Darkest Dungeon style): run init, clamp, shaken (위축) ratio, mood multipliers, roster-copy `apply_to` (MatchFlow), `snapshot` → `match_ctx.stress`, `record_match` ← `pending_match.stress`, training-day roll, interview / outing relief, display helpers (`mood_label`, `line`). The in-match part is `features/battle_sim/stress/`. |
| `VnDialogueView.gd` | `class_name VnDialogueView extends Control`: **visual-novel dialogue** for interviews, outings and incidents (full-body art, bottom speech bubble, dimmed centred choices, result panel). Drop-in for `MessengerView` on the week screen's evening dialog. See **VN dialogue (VnDialogueView)** below. |
| `UI_View_VnDialogue.tscn` | Its scene (layout owner): header, `%Stage` art box, `%Bubble`, `%Dim`, `%Overlay` with `%ChoiceList` · `%ResultPanel` · `%Hint`. Create with `VnDialogueView.create()`. |
| `UI_Comp_VnChoiceButton.tscn` | Item (no script): one answer — `%Button` (`VnDialogueChoiceButton`, 880 wide, at least 112 tall, autowrap) + `%Preview` line under it (check chance + effect directions). Code sets both texts + `pressed`. |
| `FocusTraining.gd` | `class_name FocusTraining` (static, §15 D). The visit option **집중 훈련**: course table (`COURSES`), `courses_view` / `refusal` / `cost_of`, `apply` (coach points → stat EXP through the training EXP bank, training EXP, awakening gauge, stress; 한계돌파 → `LimitBreak.complete`). Shared helpers the story clauses use: `add_stat_exp`, `add_training_exp`, `add_story_mastery`, `story_mech`. See "Afternoon visit (방문)". |
| `AfternoonAway.gd` | `class_name AfternoonAway` (static). Afternoon away states of a training day: stress self outing, else a chance of dorm rest, rolled once and recorded in `mental.days["<day>"].afternoon`; `started` · `begin` · `away_of` · `relief_of` · `can_request` · `any_request`. See "Afternoon away states". |
| `PilotMods.gd` | `class_name PilotMods` (static, base). Temporary per-pilot stat mods `[{pilot_id, stat, delta, weeks_left, source}]`; `weeks_left = -1` lasts until the next own match. `apply_to` is only ever called on a **roster copy** (MatchFlow). |

Interview / outing / incident dialogues use `VnDialogueView`; the press conference keeps
`features/season/press/MessengerView.gd`. The evening card + incident card live on the week screen (`features/season/week/`).

## Rules
- **Trust** `{"<pid>": int}` for my 5 pilots, clamped `[TRUST_MIN, TRUST_MAX]` points, starts at `TRUST_START` (0).
  **Shown as a level** 1 .. `TRUST_LEVEL_MAX` (5) + progress toward the next: every `TRUST_PER_LEVEL` (25) points is one
  level, `TRUST_MAX` = top level with a full bar (`MentalSystem.trust_level` / `trust_progress`, pure helpers
  `level_of_trust` / `progress_of_trust`). Events still add and test **points** (`trust:+4`, `trust>=N`); result chips
  show the change as level progress (`MentalEvents.trust_delta_text`: +4 → `+16%`) and add a `trust_level` note when
  the level changes. It affects **only** outing unlock (level ≥ `TRUST_OUTING_LEVEL`) and the true ending — no match stat effect.
- **A training day** (Mon–Fri) has three halves after the morning training (`features/season/week/README.md`):
  **morning talk** (one pilot, no outing) → **afternoon** (interview / outing) → **evening** (forced incident).
  **Saturday** (after the stadium prep) and a plain weekend day have the **afternoon + evening** only (no
  training, so no morning talk); the **Sunday of a match** has the press conference, then the afternoon
  (visit) and the evening (§15 D). The afternoon / evening / incident entry points accept any weekday 0..6
  (`CalendarSystem.is_week_day`); the morning talk stays Mon–Fri.
- **Morning talk** (훈련 소감, one per morning, record `days["<day>"].talk`): opened by `begin_morning` when the
  training result FX ends; `begin_talk(state, day, pid)` / `finish_talk(state, day, choice)` / `pass_talk` (Next
  without a talk). A pilot who trained in the **same placed tile** that day (week log row `group`, joint training)
  comes along (`talk_partner`, one mate drawn when several): a `talk_pair` row is drawn first (cond on the picked
  pilot), else a `talk` row. In a pair talk every single-pilot clause (`trust` · `stress` · `pmod`,
  `MentalEvents.SINGLE_CLAUSES`) hits **both** pilots, and both get `STRESS_TALK_RELIEF`. Checks use the manager's
  own mental. `can_talk`: the morning is open, the afternoon has not started, no talk yet.
- **Afternoon = visit (방문, §15 D)** (every day that has an afternoon, one action per day; the record keeps
  its old name `evening`): see "Afternoon visit (방문)" below — visit one pilot, then 집중 훈련 / 이야기 / 외출.
  Leaving the afternoon without a visit records a pass. Manager-only — staff never visit.
  - **No weekly count limits** (removed 2026-10): a visit is always possible; the only cap is
    one action per afternoon (`AfternoonAway.can_request`: the day's record is still empty).
  - Outing: only with a pilot at trust level ≥ `TRUST_OUTING_LEVEL`.
    Effects: the row's clauses (trust +, `pmod:all:+N:-1` until next match) + `outings[pid] += 1` +
    stress relief `STRESS_OUTING_RELIEF + VISIT_OUTING_RELIEF_BONUS` +
    **next training day** EXP × `MENTAL_OUTING_EXP_MULT` for that pilot
    (`training_exp_mult(state, pid, day)`; `TrainingBoard` (M3) multiplies it; a Friday / Saturday /
    Sunday outing hits next Monday — stored as day `TRAINING_DAYS`, `end_week` carries it over).
    The true-ending count is unchanged.
  - Story / outing checks are judged with the manager's own mental.
- **Incidents** roll once per day when that day's **evening** starts (`begin_dusk`, marker
  `days["<day>"].dusk = true`; the week screen calls it on the afternoon's Next and skips the evening when nothing
  happens):
  chance `MENTAL_INCIDENT_CHANCE × FinanceSystem.incident_mult(state) × TraitSystem.run_pct_mult(state, "incident_pct")`,
  target = a random pilot of mine.
  A pending incident opens its dialog by itself and must be answered; checks use
  `StaffSystem.effective_for_incident(state)` (staff can cover).
- **Press** (once per week, **Sunday afternoon after the match**): one `press` row per week. Rows with `mention=mvp|worst`
  target the last own match's MVP (if mine) / my lowest MVP-metric pilot (`run_stats.matches`);
  generic rows move whole-team trust or add a temporary manager-stat mod (`StaffSystem.add_mod`).
  **Result pools**: rows whose cond has a `last=win` / `last=loss` token are the result pool, the rest the
  general pool; the result pool is drawn with chance `PRESS_RESULT_POOL_CHANCE` (an empty pool falls back
  to the other) — `is_result_press(row)`. Checks use the manager's own mental.
- **True ending** = run **clear** + outings with that pilot ≥ `TRUE_ENDING_OUTINGS`.
  `true_ending_pilots(state)` → `RunResult` puts `result.true_endings` on a clear only →
  `ProfileManager.apply_run_result` records `achievements[pid].true_ending`.
- **Determinism / idempotency**: draws and checks are seeded from
  `hash([run_seed, week_key, day, purpose, extra])` (`week_key = "<phase>-<phase_week>"`), so a
  reload never rerolls. Every action is recorded **before** its dialog opens and settled at most
  once — `finish_evening` / `resolve_incident` / `resolve_press` return the stored outcome on a
  second call. Re-entering a weekday (after a Sat match, after load) redraws from the record.

## Stress
`season_state.stress = {"<pid>": int}` for my 5 pilots, clamped `[0, STRESS_MAX]`, starts at `STRESS_START`
(old saves without the key read 0).
- **Rises**: each training day (every pilot trains; an empty cell is the basic course), `STRESS_TRAIN_MIN..MAX` (seeded per run · week · day ·
  pilot, `TrainingBoard.apply_day_training` row key `stress`; the training result itself is unchanged), and each
  death in a match, `STRESS_DEATH_MIN..MAX` (BattleSim, written back at match end).
- **Falls**: a finished interview / outing / morning talk relieves `STRESS_INTERVIEW_RELIEF` / `STRESS_OUTING_RELIEF` / `STRESS_TALK_RELIEF` (pair talk: both pilots; `StressSystem.relief_amount`) (note
  `{type: stress}` in the outcome), plus any `stress:` / `stress_all:` clause of the chosen answer. No natural decay.
- **Shaken (위축)**: stress ≥ `STRESS_THRESHOLD` outside a match. The 6 pilot stats drop by one
  `STRESS_SHAKEN_STAT_PER_STEP` per full `STRESS_SHAKEN_STEP` over the threshold (the maximum stress is the
  largest drop). Applied **last** in `MatchFlow._finalize_rosters` on the roster copy; persists across matches
  until stress falls under the threshold.
- **Test (각성 / 패닉)**: a pilot that enters a match **below** the threshold and crosses it there is tested once:
  `STRESS_AWAKEN_CHANCE` awaken (stats × (1 + `STRESS_AWAKEN_STAT`)), else panic (× (1 − `STRESS_PANIC_STAT`)),
  until the match ends. A shaken pilot is never tested, and a tested pilot is not shaken in that match
  (the roster copy was built before the match). See `features/battle_sim/stress/README.md`.
- Display: `SeasonPilotCard` (hub roster · week bottom row: stress line + mood / that day's delta), `SeasonPilotDetail` sheet,
  battle strip / detail panel (`stress/README.md`). Keys `mental.ui.stress.*` (value, mood names; `day` deprecated).
  Shared words for stress / moods are not in `term.*` yet (only the base owner adds there).

## Afternoon visit (방문, §15 D)
The old afternoon "면담" is the **visit**. The week screen (`features/season/week/` — `VisitMenu`) asks; this
folder records and applies.
1. **Visit** — tap a pilot on the base map (several pilots who can be visited on one spot → a small picker).
   `MentalSystem.begin_visit(state, day, pid)` records `{action: "visit", pilot_id, choice: -1}` **before the
   menu opens** (the afternoon's one action is spent; reload reopens the menu, `visit_open(state, day)`).
2. **Menu** — three options:
   - **집중 훈련** → a course → `finish_focus(state, day, course)` (`FocusTraining.apply`) → record
     `{action: "focus", course, choice: 0, outcome}`. Costs coach points (`StaffSystem.coach_points`,
     `FOCUS_COST`, 한계돌파 `FOCUS_COST_LIMIT_BREAK`).
   - **이야기** → `begin_evening(state, day, "story", pid)` draws a story row → the VN dialogue →
     `finish_evening` (relief `STRESS_INTERVIEW_RELIEF`). Record `action: "story"`.
   - **외출** → `begin_evening(state, day, "outing", pid)` (trust gate as before).
- **Courses** (`FocusTraining.COURSES`): 공격성 `field_hit + engage_hit` · 신중함 `field_eva + engage_eva` ·
  운영력 `field_hit + field_eva` · 전투력 `engage_hit + engage_eva` · 성장력 `atk_growth + hp_growth` — each stat
  gets `FOCUS_STAT_EXP` stat EXP through the training board's rule (the week's leftover bank
  `training_exp_carry[seat]`, `TRAINING_EXP_PER_POINT` EXP = 1 point), the sum counts as training EXP
  (`TrainingLevel.add_exp`); plus `FOCUS_AWAKEN` awakening gauge (`Awakening.add_gauge`) and `FOCUS_STRESS` stress.
  **한계돌파** (listed only while `LimitBreak.goal_active`) calls `LimitBreak.complete` instead of the stat EXP.
- **Story pools** (`story_kinds_for(state, day)`, the first pool with a row for the pilot wins):
  Mon–Fri `story` (about that morning's training: the answer pair `train_bonus:std` + stress vs `stress_train:-2`);
  Saturday with the ban/pick stored (`pending_match.picks`) `story_sat` (`mastery:+N` on that pilot's ban/pick mech);
  Sunday after my match (`mental.last_match` of this week) `story_sun` (conds `last` · `mvp` · `kda` · `kills` ·
  `deaths`); the old `interview` rows are always the fallback (a plain weekend day uses only them).
- **Last match** (`record_match`, `SeasonHub._consume_pending_match_result`): `mental.last_match =
  {week, won, mvp, lines: {"<pid>": {k, d, a}}}` (my pilots), read by `last_match_of` / `match_line`.

## Afternoon away states
The week screen splits each Mon–Fri into morning (training) and afternoon (the evening action, now shown as
오후). When the afternoon starts (`AfternoonAway.begin(state, day)`, called by the week screen's Next
after the morning settlement), some of my pilots are away and cannot be asked for an interview / outing:
1. **Self outing (혼자 외출)**: a pilot with stress ≥ `STRESS_SELF_OUTING_MIN` rolls
   `STRESS_SELF_OUTING_CHANCE`; on a hit the pilot goes out alone (entrance spot) and stress drops by
   `STRESS_SELF_OUTING_RELIEF` (`StressSystem.add`, the applied delta is recorded).
2. **Dorm (숙소 휴식)**: otherwise every pilot rolls `AFTERNOON_DORM_CHANCE`; on a hit the pilot stays in the dorm
   (dorm spot, dimmed). No stress change. An empty training cell does not matter: it is the basic course.
- **Determinism**: two draws per pilot in a fixed order (self outing, dorm), seeded from
  `hash([run_seed, week_key, day, "afternoon_away", pid])`, and the
  whole result is recorded before it is shown. `begin` on a day that already has a record returns it untouched,
  so re-entering the day or reloading never rerolls or relieves twice.
- **Record**: `mental.days["<day>"].afternoon = {"away": {"<pid>": "dorm"|"self_outing"}, "relief": {"<pid>": int}}`
  (string keys; read values with `int()` / `String()`). It sits in the weekday record (`MentalSystem.day_record`,
  public accessor of `_day`), so `end_week` / a new week key clears it with the rest. Old saves have no
  `afternoon` key: that day simply has not reached the afternoon yet.
- **Who can be asked** (`can_request(state, day, pid)`): the afternoon has started, the day's evening action is
  not done and the pilot is not away (an interview is always possible). `any_request` = some pilot can
  (the week screen warns before Next skips the afternoon). The interview / outing itself is the unchanged
  evening flow (`begin_evening` / `finish_evening`, record key `evening`).
- Spots on the team base map (dorm / entrance): `features/season/week/base_map/README.md`.

## `season_state.mental` shape (string keys; numbers may load back as floats — always `int()`)
```
{
  "week": "<phase>-<phase_week>",   # week the fields below belong to ("" after end_week)
  # (old saves may still carry "interviews_used" / "outings_used": ignored, no longer written)
  "days": {"<day 0..6>": {
      "evening":  {action: "visit"|"focus"|"story"|"outing"|"pass" ("interview" = old saves), pilot_id, event,
                  course (focus only), choice (-1 = open), outcome{}},
      "incident": {} (rolled, none) | {event, pilot_id, choice (-1 = pending), outcome{}},
      "talk":     {} (morning open, nothing chosen) | {action: "talk"|"pass", pilot_id, partner_id (-1 = alone),
                  event, choice (-1 = open), outcome{}},
      "dusk":     true once the evening started (the incident is rolled then),
      "afternoon": {...}  (AfternoonAway, below)
  }},
  "fatigue": {"<pid>": day},        # training day whose EXP is cut (≥5 = next week, shifted by end_week)
  "press": {week, event, pilot_id, choice, outcome{}},
  "last_match": {week, won, mvp, lines: {"<pid>": {k, d, a}}},   # §15 D Sunday story (kept over week ends)
}
```
`outcome` = `{checked, ok, chance, pilot_id, partner_id, say: [text_key], notes: [note dict]}` — **no display text is saved**
(D7): note dicts are `{type: trust|trust_all|trust_level|stress|stress_all|pmod|pmod_all|smod|outing, pid?, stat?, delta?, weeks?, count?}`;
§15 D adds `stat_up {pid, stat, delta}` · `stat_exp {pid, delta}` · `tlexp {pid, delta}` (0 = bar full) ·
`awaken {pid, delta}` · `mastery {pid, mech, delta}` · `limit_break {pid, level}` · `coach {delta}` (keys `mental.ui.note.*`).
A focus training outcome has the same shape (`checked: false`) plus `course`.
`MentalEvents.outcome_view(state, outcome)` → `{checked, ok, chance, say: [String], notes: [String]}` for
`MessengerView.show_result`; `MentalEvents.note_texts(state, notes)` for the week-screen summary chips.
A note whose stat is `all` reads `training.stat.all` ("모든 파일럿 능력치", shared with the training tiles).
`end_week` resets `week` / counters / `days` and shifts `fatigue`; `_week()` also resets when the key changes.

## `mental_events.csv` + `mental_texts.csv` grammar
`mental_events` columns: `id, kind, manager_type, stage, cond, effects, weight` — no text.
`mental_texts` columns: `id, event_id, slot, choice, branch, seq, text_key` (D6) — one row per text,
`text_key` = l10n key (domain `mental`, alias `mental.<event>.<id>`; edit the Korean in
`data/l10n/src/mental.csv`, not here). Ids: `<event>_L<seq>` · `<event>_C<choice>` · `<event>_C<choice>_S<seq>`.

- `kind` — `interview` / `outing` / `incident` / `press` / `talk` (morning talk) / `talk_pair` (morning talk with
  the joint-training partner) / `story` · `story_sat` · `story_sun` (afternoon visit 이야기, §15 D; `interview` = their fallback).
- `manager_type` — -1 any, 0 운영형 (m), 1 실전형 (f). Rows for the other type never appear;
  rows for the run's type weigh × `MENTAL_TYPE_WEIGHT_MULT`. Outings pick **strictly** by stage:
  a typed row for the stage beats the generic one.
- `stage` — outing number 1..N (`outings + 1`; past the last written stage the highest repeats), else 0.
- `weight` — draw weight (int ≥ 0).
- text slot `line` (by `seq`) — the text's first char is its marker: plain = the other side (left
  bubble with portrait), `>text` = manager (right bubble), `*text` = centred narration, `&text` = the
  `talk_pair` partner, `@text` = tag
  (press outlet / incident name, used in headers, not drawn as a bubble — `MentalSystem.session_view`
  reads it after translation, so **translations keep the marker**). `{name}` → target pilot name,
  `{name2}` → the `talk_pair` partner, in every slot (`Loc.t(key, {"name": …})`, josa tags like `{name}{eun}` resolve after it).
- text slot `choice` — manager answer `choice` (0-based; 2–3 per event).
- text slot `say` — reply line (left bubble) after answer `choice`, in `seq` order; `branch` `ok` / `ng` =
  only on a passed / failed check (like the clause gates), empty = always. A gated reply makes the
  entry roll a check just like a gated clause.
- `effects` — `|`-joined, **one entry per choice**; clauses inside an entry joined with `;`.

### Clause vocabulary
| Clause | Effect |
|---|---|
| `trust:+N` | target pilot trust ± N |
| `trust_all:+N` | all my 5 pilots' trust ± N |
| `stress:+N` | target pilot stress ± N (`StressSystem.add`, clamped) |
| `stress_all:+N` | all my 5 pilots' stress ± N |
| `pmod:<stat\|all>:<delta>:<weeks>` | target pilot temporary stat mod (`PilotMods.add`); `weeks = -1` = until next own match |
| `pmod_all:<stat\|all>:<delta>:<weeks>` | same for all my pilots |
| `smod:<stat>:<delta>:<weeks>` | temporary manager-stat mod (`StaffSystem.add_mod`, `stat` ∈ `StaffSystem.STATS`, weeks > 0) |
| `awaken:+N` | target pilot awakening gauge + N (`Awakening.add_gauge`, §15 C) — stories, incidents |
| `tlexp:+N` | target pilot training EXP + N (`TrainingLevel.add_exp`; a full bar adds nothing, note says so) |
| `mastery:+N` | mastery + N on the target's story mech (`FocusTraining.story_mech`: Saturday ban/pick mech, else research mech, else the coach's pick; `MechMastery.gain`) |
| `train_bonus:std` / `train_bonus:N` | today's stat EXP of the target again × `STORY_TRAIN_BONUS_PCT` % (`std`) or N %, through the leftover bank (`FocusTraining.add_stat_exp`, also training EXP). No training row today = nothing |
| `stress_train:<±N>` | target stress + N × the stress today's training gave it (`-2` = relieve it twice over). No training row = nothing |
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
| `train=X` / `train=X,Y` | the target's training cell colour today (week log row `color`; basic course = `W`) is one of them (`MentalEvents.today_row`, day = `season_state.week_day`) |
| `ups>=N` / `ups<N` | stat points the target gained in today's training |
| `stress>=N` / `stress<N` | the target's current stress |
| `mvp=yes` / `mvp=no` | the target was / was not the MVP of my last match (`mental.last_match`) |
| `kda>=N` · `kills>=N` · `deaths>=N` (and `<`, `=`) | the target's line in my last match: `(k + a) / max(d, 1)` floored · kills · deaths; no line = false |
| `tlevel=N` / `tlevel>=N` / `tlevel<N` | the target's run training level (`TrainingLevel.level`, §15 B) |

Kind `limit_break` (§15 B) rows hold only the limit-break **dialogue lines**; `LimitBreak` draws and plays them
(never `MentalSystem`) — `features/season/training/README.md` "Training level · limit break".

- **Trait `trust_gain`** (M8): `add_trust` adjusts only a rise — `max(0, delta + Σp1)` — so a
  rise never becomes a loss; drops pass through untouched.

## Choice preview (확률 + 방향)
Every answer of an interview / outing / incident / morning talk / press question shows a preview line under its button
(`session_view(...).previews[i]`): the mental check chance when the answer rolls one (judge = `judge_for(kind)`:
staff cover for incidents, else the manager's mental) and the **direction** of each effect, never the number:
`성공 58% · 신뢰↑` or, when pass and fail differ, `성공 58% · 성공: 신뢰↑ / 실패: 신뢰↓`.
`MentalEvents.choice_preview(state, row, idx, judge)` sums the clause deltas per label for the passed and the failed
world (`preview_label`: 신뢰 · 팀 신뢰 · 스트레스 · 팀 스트레스 · stat name · 팀 <stat> · 감독 <stat>; §15 D: 깨달음 ·
훈련 EXP · 숙련 · 능력치 EXP (`train_bonus`), and `stress_train` adds to 스트레스 as N × today's training stress of the
target — `choice_preview(…, pilot_id)`), `preview_text`
formats them (keys `mental.ui.preview.*`). The activity's own stress relief is the same for every answer and is left
out. The press conference shows the same line under its answers (`MessengerView.open(..., previews)`, judge = manager).

## API (static, `state` = `season_state`)
`init_run` · `end_week` · `training_exp_mult(state, pid, day)` · `trust` · `trust_level` · `trust_progress` · `outings` · `add_trust` ·
`true_ending_pilots` · `my_pilot_ids` · `outing_unlocked` / `can_outing` · `evening` / `evening_done` / `begin_evening(state, day, action, pid)` /
`finish_evening(state, day, choice)` · `begin_morning` / `morning_started` / `talk` / `talk_done` / `can_talk` /
`talk_partner` / `begin_talk(state, day, pid)` / `finish_talk(state, day, choice)` / `pass_talk` ·
`begin_visit(state, day, pid)` / `visit_open` / `finish_focus(state, day, course)` / `story_kinds_for(state, day)` ·
`record_match(state, pending_match)` / `last_match_of` / `match_line(state, pid)` · `begin_dusk` /
`dusk_started` · `ensure_incident` / `incident_pending` / `incident_session` /
`resolve_incident` · `press_session` / `resolve_press` · `judge_for(state, kind)` ·
`session_view(state, session)` → `{kind, event, pilot_id, partner_id, tag, lines, choices, previews}` (translated text).

## VN dialogue (VnDialogueView)

Interviews, outings and incidents play as a **visual novel**: the pilot's full-body illustration in the
centre, one line at a time in a speech bubble at the bottom, a tap advances. The press conference
keeps `MessengerView` (`features/season/press/`).

```
월요일 저녁 · 면담                  ← %Sub (caption)
Evelyn                              ← %Title (heading)
        ( full-body art )           ← %Art = PilotImages.full_for(pilot_id), %Slab if null
┌[Evelyn]───────────────────────┐   ← %NamePlate: pilot amber / manager dark / hidden for narration
│ 감독님, 잠깐 시간 괜찮으세요?   │   ← %Text, typed out; a tap while typing shows it whole
└───────────────────────────────┘
          화면을 눌러 계속           ← %Hint (above the dim)
```

(Mockup text: header "Monday evening · Interview", pilot "Evelyn", line "Coach, got a minute?",
hint "Tap the screen to continue".)

**API** (same signals / methods as `MessengerView`, only `open` differs):

| Member | Meaning |
|---|---|
| `static create() -> VnDialogueView` | Instantiates `UI_View_VnDialogue.tscn` (never `.new()`) |
| `open(sub: String, title: String, pilot_id: int, lines: Array, choices: Array, speaker: String = "", previews: Array = [], partner_id: int = -1, partner_name: String = "") -> void` | Fresh dialogue. `pilot_id` picks the art (`-1` or no art → placeholder slab with the name). `speaker` = the pilot's name plate, `""` → `title`. `previews[i]` = the line under answer i. `partner_*` = the joint-training partner who speaks the `&` lines |
| `signal choice_picked(idx: int)` | An answer was tapped. The owner applies it and calls `show_result` (same frame or later; the view waits) |
| `show_result(outcome_view: Dictionary) -> void` | `MentalEvents.outcome_view(state, outcome)` → `{checked, ok, say, notes}` (display text) |
| `signal closed` | The final tap on the result; the owner frees the view |
| `is_open() -> bool` · `reveal_all() -> void` | Still running · jump to the choices (previews / harnesses) |
| `@export outcome_hint` | Bottom hint key once the result shows (default `press.messenger.hint_close`) |

**Flow**: lines (one per tap) → choices: `%Dim` fades in, `%ChoiceList` lists the answers
vertically in the screen centre → `choice_picked` → the picked answer plays as a manager line,
then the `say` replies (one per tap) → `%ResultPanel` over the dim: mental check verdict
(`press.messenger.check_pass` / `check_fail`, only when `checked`) + one `MessengerNoteChip` per
note (trust, stat mods, outing …) → tap → `closed`. No notes and no check → no panel, the next
tap closes. No choices → the tap after the last line closes.

**Choices**: `UI_Comp_VnChoiceButton.tscn` is a VBox — `%Button` (the answer) and `%Preview` under it
(`OnFillLabel`, hidden when empty).

**Line markers** (same grammar as above): `&text` = the partner (the art switches to the partner's, partner name
plate; the next plain line switches back); plain = pilot (name plate = pilot name, amber
`VnDialogueNamePlate`), `>text` = manager (name plate `term.person.manager`, dark
`VnDialogueNamePlateMine`, the art dims to `ART_LISTEN_MODULATE`), `*text` = narration (no plate,
`SubLabel` text), `@text` = tag (header only, skipped). Empty lines are skipped.

**Input**: the root is STOP (blocks the week screen and its bottom bar) and reads taps on
**release** in `gui_input`; every child but the answer buttons ignores the mouse. `_picked_frame`
ignores the release of the answer tap. Presentation timings (`TYPE_CHARS_PER_SEC`, `FADE_SEC`) are
script constants, like `MvpView`.

**Safe area**: like `MessengerView` the view never indents itself (the week screen already sits on
the safe top). Code extends `%Background` and `%Dim` into the notch band and lifts `%SafeArea` /
`%Overlay` by the bottom inset, so the bubble and hint stay above the gesture zone.

**Looks** (`OutgameTheme._add_screen_variations`, listed in `resources/README.md`):
`VnDialogueBubble` (Card r28, padding 0, the scene's `Pad` pads), `VnDialogueNamePlate` ·
`VnDialogueNamePlateMine` (AccentChip, `ACCENT` / `RAIL`), `VnDialogueArtSlab` (SunkPanel),
`VnDialogueChoiceButton` (GhostButton + padding). Dim = shared `DimPanel`, result = `PopupCard`.

**l10n**: new key `mental.ui.vn.result_title` (result panel title, scene text). Reused:
`ui.button.tap_to_continue`, `press.messenger.pick_answer` / `hint_close` / `check_pass` /
`check_fail`, `term.person.manager`. Scene placeholders the script overwrites are `auto_translate_mode = 2`.

**F6 preview**: a real interview of an in-memory run (`UiPreview.ensure_run`, my first pilot,
`MentalSystem.begin_evening`); picking an answer runs `finish_evening` and shows the real result.

### Wiring (coordinator: `features/season/week/WeekProgressView.gd`)

`_overlay: VnDialogueView` serves the morning talk, the afternoon dialog (story / outing), the limit-break event
(§15 B) and the incident (`_overlay_kind` `talk` / `evening` / `limit_break` / `incident`; a limit-break answer goes
to `LimitBreak.choose_goal`, which returns the outcome view itself). `_open_overlay(kind, sub, title,
pid, view, speaker = "")`: evening → title = pilot name; incident → title = the event's `@tag`, `speaker` = pilot
name (sub `season.week.sub_incident`). `_on_overlay_choice` resolves by `_overlay_kind`
(`resolve_incident` / `finish_evening`) and calls `show_result(MentalEvents.outcome_view(state, out))`.
