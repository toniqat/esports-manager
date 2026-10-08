# mental/ — trust · stress · interviews · outings · incidents · press · true ending (M7)

Contract: `docs/outgame_dev_plan.md` §11. State `season_state.trust` / `stress` / `outings` / `mental` / `pilot_mods`.
Tuning lives in `data/csv/const.csv` (`TRUST_*`, `STRESS_*`, `MENTAL_*`, `TRUE_ENDING_*`) — no values here.
Event texts are l10n keys (`mental_texts.csv` → domain `mental`, D6). Display text is l10n keys (`mental` domain): code
keys use **4-segment** aliases `mental.ui.*` — a 3-segment `mental.x.y` matches the data rule `mental.{event_id}.{id}`
and gets no `L` constant. Mod clauses write `source = "mental:<event id>"` (`MOD_SOURCE_PREFIX`, an id — D7);
`MentalEvents.mod_source_text` shows the event kind (`term.activity.*` / `mental.ui.mod_source.incident`).

| File | Role |
|---|---|
| `MentalSystem.gd` | `class_name MentalSystem` (static). State + flow: run init, week reset, weekly limits, evening action (interview / outing / pass), incident roll + resolve, press session + resolve, outing training-EXP penalty, true-ending pilots. Every entry point takes the `season_state` dictionary (no autoloads → headless-testable). |
| `MentalEvents.gd` | `class_name MentalEvents` (static). `mental_events` + `mental_texts` tables (game.db) → parsed rows (texts as l10n keys); the `effects` / `cond` grammar; row selection (cond, manager type, weights); `apply_choice` (mental check + clauses + replies, keys / ids only); `outcome_view` · `note_texts` · `text` turn stored keys into display text (`Loc.t`, `{name}`). |
| `StressSystem.gd` | `class_name StressSystem` (static). Stress (Darkest Dungeon style): run init, clamp, shaken (위축) ratio, mood multipliers, roster-copy `apply_to` (MatchFlow), `snapshot` → `match_ctx.stress`, `record_match` ← `pending_match.stress`, training-day roll, interview / outing relief, display helpers (`mood_label`, `line`). The in-match part is `features/battle_sim/stress/`. |
| `VnDialogueView.gd` | `class_name VnDialogueView extends Control`: **visual-novel dialogue** for interviews and outings (full-body art, bottom speech bubble, dimmed centred choices, result panel). Drop-in for `MessengerView` on the week screen's evening dialog. See **VN dialogue (VnDialogueView)** below. |
| `UI_View_VnDialogue.tscn` | Its scene (layout owner): header, `%Stage` art box, `%Bubble`, `%Dim`, `%Overlay` with `%ChoiceList` · `%ResultPanel` · `%Hint`. Create with `VnDialogueView.create()`. |
| `UI_Comp_VnChoiceButton.tscn` | Item (no script): one answer button (`VnDialogueChoiceButton`, 880 wide, at least 112 tall, autowrap, centred). Code sets text + `pressed`. |
| `AfternoonAway.gd` | `class_name AfternoonAway` (static). Afternoon away states of a training day: stress self outing, else a chance of dorm rest, rolled once and recorded in `mental.days["<day>"].afternoon`; `started` · `begin` · `away_of` · `relief_of` · `can_request` · `any_request`. See "Afternoon away states". |
| `PilotMods.gd` | `class_name PilotMods` (static, base). Temporary per-pilot stat mods `[{pilot_id, stat, delta, weeks_left, source}]`; `weeks_left = -1` lasts until the next own match. `apply_to` is only ever called on a **roster copy** (MatchFlow). |

The dialogue UI is `features/season/press/MessengerView.gd` (shared with the press conference);
the evening card + incident card live on the week screen (`features/season/week/`).

## Rules
- **Trust** `{"<pid>": int}` for my 5 pilots, clamped `[TRUST_MIN, TRUST_MAX]`, starts at `TRUST_START`.
  It affects **only** outing unlock (`TRUST_OUTING_MIN`) and the true ending — no match stat effect.
- **Evening** (Mon–Fri, one action per day): interview / outing / pass. Leaving the day without
  choosing records a pass. Manager-only — staff never interview or go out.
  - **No weekly count limits** (removed 2026-10): an interview is always possible; the only cap is
    one action per afternoon.
  - Outing: only with a pilot at trust ≥ `TRUST_OUTING_MIN`.
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

## Stress
`season_state.stress = {"<pid>": int}` for my 5 pilots, clamped `[0, STRESS_MAX]`, starts at `STRESS_START`
(old saves without the key read 0).
- **Rises**: each training day (every pilot trains; an empty cell is the basic course), `STRESS_TRAIN_MIN..MAX` (seeded per run · week · day ·
  pilot, `TrainingBoard.apply_day_training` row key `stress`; the training result itself is unchanged), and each
  death in a match, `STRESS_DEATH_MIN..MAX` (BattleSim, written back at match end).
- **Falls**: a finished interview / outing relieves `STRESS_INTERVIEW_RELIEF` / `STRESS_OUTING_RELIEF` (note
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
  "days": {"<day 0..4>": {
      "evening":  {action: "interview"|"outing"|"pass", pilot_id, event, choice (-1 = open), outcome{}},
      "incident": {} (rolled, none) | {event, pilot_id, choice (-1 = pending), outcome{}}
  }},
  "fatigue": {"<pid>": day},        # training day whose EXP is cut (≥5 = next week, shifted by end_week)
  "press": {week, event, pilot_id, choice, outcome{}},
}
```
`outcome` = `{checked, ok, chance, pilot_id, say: [text_key], notes: [note dict]}` — **no display text is saved**
(D7): note dicts are `{type: trust|trust_all|stress|stress_all|pmod|pmod_all|smod|outing, pid?, stat?, delta?, weeks?, count?}`.
`MentalEvents.outcome_view(state, outcome)` → `{checked, ok, chance, say: [String], notes: [String]}` for
`MessengerView.show_result`; `MentalEvents.note_texts(state, notes)` for the week-screen summary chips.
A note whose stat is `all` reads `training.stat.all` ("모든 파일럿 능력치", shared with the training tiles).
`end_week` resets `week` / counters / `days` and shifts `fatigue`; `_week()` also resets when the key changes.

## `mental_events.csv` + `mental_texts.csv` grammar
`mental_events` columns: `id, kind, manager_type, stage, cond, effects, weight` — no text.
`mental_texts` columns: `id, event_id, slot, choice, branch, seq, text_key` (D6) — one row per text,
`text_key` = l10n key (domain `mental`, alias `mental.<event>.<id>`; edit the Korean in
`data/l10n/src/mental.csv`, not here). Ids: `<event>_L<seq>` · `<event>_C<choice>` · `<event>_C<choice>_S<seq>`.

- `kind` — `interview` / `outing` / `incident` / `press`.
- `manager_type` — -1 any, 0 운영형 (m), 1 실전형 (f). Rows for the other type never appear;
  rows for the run's type weigh × `MENTAL_TYPE_WEIGHT_MULT`. Outings pick **strictly** by stage:
  a typed row for the stage beats the generic one.
- `stage` — outing number 1..N (`outings + 1`; past the last written stage the highest repeats), else 0.
- `weight` — draw weight (int ≥ 0).
- text slot `line` (by `seq`) — the text's first char is its marker: plain = the other side (left
  bubble with portrait), `>text` = manager (right bubble), `*text` = centred narration, `@text` = tag
  (press outlet / incident name, used in headers, not drawn as a bubble — `MentalSystem.session_view`
  reads it after translation, so **translations keep the marker**). `{name}` → target pilot name in
  every slot (`Loc.t(key, {"name": …})`, josa tags like `{name}{eun}` resolve after it).
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
`true_ending_pilots` · `my_pilot_ids` · `outing_unlocked` / `can_outing` · `evening` / `evening_done` / `begin_evening(state, day, action, pid)` /
`finish_evening(state, day, choice)` · `ensure_incident` / `incident_pending` / `incident_session` /
`resolve_incident` · `press_session` / `resolve_press` · `session_view(state, session)` → `{kind, event, pilot_id, tag, lines, choices}` (translated text).

## VN dialogue (VnDialogueView)

Interviews and outings play as a **visual novel**: the pilot's full-body illustration in the
centre, one line at a time in a speech bubble at the bottom, a tap advances. The press conference
and incidents keep `MessengerView` (`features/season/press/`).

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
| `open(sub: String, title: String, pilot_id: int, lines: Array, choices: Array, speaker: String = "") -> void` | Fresh dialogue. `pilot_id` picks the art (`-1` or no art → placeholder slab with the name). `speaker` = the pilot's name plate, `""` → `title` |
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

**Line markers** (same grammar as above): plain = pilot (name plate = pilot name, amber
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

The evening dialog switches to `VnDialogueView`; incidents stay on `MessengerView`.

```gdscript
var _overlay: Control = null          # VnDialogueView (evening) / MessengerView (incident), null when closed

func _open_overlay(kind: String, sub: String, title: String, pid: int, view: Dictionary) -> void:
	_overlay_kind = kind
	if kind == "evening":
		var vn := VnDialogueView.create()
		_overlay = vn
		add_child(vn)
		vn.choice_picked.connect(_on_overlay_choice)
		vn.closed.connect(_on_overlay_closed)
		vn.open(sub, title, pid, view["lines"], view["choices"])
		return
	var msg := MessengerView.create()
	_overlay = msg
	add_child(msg)
	msg.choice_picked.connect(_on_overlay_choice)
	msg.closed.connect(_on_overlay_closed)
	msg.open(sub, title, PilotImages.circle_for(pid), view["lines"], view["choices"])


func _on_overlay_choice(idx: int) -> void:
	var s: Dictionary = _gm.season_state
	var out: Dictionary
	if _overlay_kind == "incident":
		out = MentalSystem.resolve_incident(s, _day, idx)
	else:
		out = MentalSystem.finish_evening(s, _day, idx)
	var ov: Dictionary = MentalEvents.outcome_view(s, out)
	if _overlay is VnDialogueView:
		(_overlay as VnDialogueView).show_result(ov)
	elif _overlay is MessengerView:
		(_overlay as MessengerView).show_result(ov)
```
`_on_overlay_closed` and the `_overlay != null` guards stay as they are. Also update the week
README line that says the evening dialog is a `MessengerView`.
