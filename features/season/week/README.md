# Week progress (시간 경과) (week)

The screen where the week passes **one day at a time, Monday to Sunday**. `Screen.WEEK` in
`SeasonHub`. Training days (Mon–Fri) show the **team base map** and run as **morning → afternoon**.

| File | Role |
|---|---|
| `WeekProgressView.gd` | `class_name WeekProgressView extends Control` — the whole screen's logic. Binds `%` nodes, fills data, adds the list's item scenes, drives the training-day stages. Create with `WeekProgressView.create()` (`.new()` is an empty Control) |
| `UI_View_WeekProgressView.tscn` | The screen layout (tree below) |
| `base_map/` | `BaseMap` widget + one `UI_Comp_BaseMap_<Name>.tscn` per team base map (art + spot markers). See `base_map/README.md` |
| `UI_Comp_WeekMapSection.tscn` | Item (training day, first): `%Hint` caption (what Next does now) + `%MapHolder` (CenterContainer) that receives the team's `BaseMap` |
| `UI_Comp_WeekMapPilot.tscn` | One pilot token on the map (`%Portrait` slot · morning speech bubble `%Bubble` / `%BubbleText` + `%BubbleTail` · afternoon away chip `%Away` / `%Name` · rising result texts `%Floats` with the `%FloatLine` template · `%Hit`). No name under the portrait |
| `UI_Comp_WeekMatchCard.tscn` | Item: one match of the match day (`%Tag` · `%Title` · `%Status` · `%Hint`) |
| `UI_Comp_WeekNoteCard.tscn` | Item: one-line placeholder card (`%Text`) |
| `UI_Comp_WeekIncidentCard.tscn` | Item: the day's incident (`%Portrait` slot · `%Head` · `%Line` · `%Hit`) |
| `UI_Comp_WeekAfternoonCard.tscn` | Item: 오후 before the action (`%Hint` (no pick) · `%Pilot` (`%Portrait` · `%Name` · `%Trust`) · `%Interview` / `%Outing`) |
| `UI_Comp_WeekAfternoonDoneCard.tscn` | Item: 오후 summary after the action (`%Portrait` · `%Head` · `%Line`) |
| *(shared)* `../UI_Comp_SeasonPilotCard.tscn` | The five pilot cards of `%PilotRow` (`features/season/README.md` "Pilot card · detail sheet") |

The per-pilot training result cards (`WeekPilotCard` + `WeekStatCell`, six short-named stat columns) were deleted
(2026-10): the day's results now rise over the map portraits and the stress change sits on the bottom cards.

The old evening card (`WeekEveningCard` with five `WeekEveningSlot` portraits and a `패스` button) was replaced by
the map + afternoon card; the slot scene and its `WeekEveningHighlight` variation were deleted.

**F6 preview** — run `UI_View_WeekProgressView.tscn` alone and it fills dummy data (`resources/UiPreview.gd`):
in-memory run on **Wednesday afternoon**, a preview-only `TrainingBoard` (`PreviewBoard` child, coach arrangement)
settles Mon–Wed, a pending incident is resolved with its first answer so no overlay covers the cards, the afternoon
is begun (away states rolled) and the first pilot that can be asked is picked. Each base map scene has its own
F6 preview (one token per spot, named after it).

## Scene (`UI_View_WeekProgressView.tscn`)

```
WeekProgressView (Control, full rect, PASS, theme OutgameTheme.tres)
├ %Background   ColorRect BG — code: ScreenMetrics.extend_background (notch band)
└ %SafeArea     full rect — code: offset_bottom = −bottom inset (bottom edge = safe_h())
  ├ Rail        Panel `WeekRail` (dark pill, RAIL r48), x 24 … −24, y 26 … 122
  │ └ Row (HBox) ─ WeekSlot(margin 12) ─ %WeekLabel (92 wide)
  │              ─ %Days (HBox, expand) ─ Day0…Day6 (CenterContainer, equal share)
  │              │                         └ Chip (Panel 72×72, `WeekDayChip` / `WeekDayChipToday`) └ Letter (30)
  │              ─ RightPad (14)
  ├ %Phase (CaptionLabel 24) · %Title (HeadingLabel 54)        ← left header
  ├ %DateSmall (CaptionLabel 24) · %DateBig (HeadingLabel 58)  ← right header, anchored right
  ├ Divider     y 346
  ├ %MapPin     x 40 … −40, y 372 … 1052, hidden by default: fixed slot for the base map (WeekMapSection) on training days
  ├ %Scroll     x 40 … −40, y 372 … −422 (= %PilotRow top − 14), anchors_preset −1 (grows right only);
  │             on training days code moves its top to %MapPin's bottom + the list gap, so the map never scrolls
  │ └ %List     VBox, separation 14 (card gap) — item scenes + %ListEnd (kept last = gap under the last card)
  ├ %PilotRow   HBox sep 12, x 40 … −40, y −408 … −152: SeasonPilotCard_Pilot0..4 (seat order), **always shown**
  └ %Bar        HBox bottom bar, y −128 … 0 — code: `OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)`
    ├ %Stage    BarGhostButton 28, ratio 1, mouse Ignore (a label: 오전 / 오후) + `BarSeparator`; hidden on match days
    └ %Action   BarPrimaryButton, ratio 2 (다음 / 확인 / 주 마감 →); `BarDarkButton` for 경기 시작 + `fit_bar_button`
```

* **Scene owns**: every position / size, fonts (variations + size overrides), the rail pill (screen variation,
  no local StyleBoxes), button kinds of the afternoon card, the map section / token layout, sample texts. Spot
  positions are the `Spot_*` markers of each base map scene.
* **Code owns** (data / device dependent): which chip is today (variation switch
  `WeekDayChip` ↔ `WeekDayChipToday`) and the day-letter colours,
  the lead bars (role colour, incident = `NEGATIVE`) and the player's dark match card
  (`card_style(…, RAIL)`), status / role / trust / result colours, card heights (match 168 / 96), the round portraits (drawn into the `%Portrait` slots with
  `OutgameTheme.add_round_portrait`; a picked afternoon pilot gets an `ACCENT` ring), the dim of a token whose
  pilot cannot be asked (`MAP_DIM` modulate), which base map scene is instanced (team data), where the tokens
  stand (`BaseMap.place_tokens`), the bottom-bar variation switch and the safe-area insets. Fixed colours
  are variations: a pending incident's `%Line` switches to
  `NegativeLabel` (size 21 kept); the afternoon card's `%Trust` switches to `AccentLabel` once the outing is unlocked.
* Rising result lines are duplicates of each token's hidden `%FloatLine` template.
* `%List` is pinned to the scroll's **anchored** width (cards run under the scroll bar, as the
  code-built list did). Read from the anchors, not `size` — an overflowing scroll grows by its bar.
* Card roots are `Panel`s using the `Card` variation (the variation is defined for
  PanelContainer; a Panel just takes its `panel` box and ignores the padding) — children are
  placed with anchors like the old code's card-local coordinates.

## Screen

```
┌──────────────────────────────────────────┐
│ 1주  월  화  수  목 [금]  토  일            │  ← top horizontal weekday rail
└──────────────────────────────────────────┘
  프리시즌 · 3주차                  1년 12월
  금요일                                5
 ──────────────────────────────────────────
  오후 · 선수를 눌러 면담이나 외출을 요청하세요
  [  team base map, five pilot tokens   ]   ← pinned (%MapPin), does not scroll
  ▌(○) 오후                                  ← afternoon card, then incident (scroll)
  [TOP][JGL][MID][ADC][SUP]                  ← %PilotRow: five pilot cards, always shown
 [  오후  ][            다음            ]
```

(Mockup uses in-game Korean text: `1주` = Week 1, 월화수목금토일 = Mon–Sun, "프리시즌 · 3주차" =
Preseason · Week 3, "1년 12월" = Year 1, December, "금요일" = Friday, 오후 = afternoon, 면담 / 외출 =
meeting / outing, `다음` = Next.)

* **Top horizontal rail** — on a dark pill spanning the full screen width, `N주` (Week N) at the
  left end, then seven weekday (요일) chips spaced evenly **left → right**. **Only the current
  weekday's chip is filled amber.** Past days have white text, remaining days dim text — that
  contrast lets you read "how many days left" from the rail alone. It used to be a **left vertical
  column** (exactly as in the reference design), but the rail took 152 px of width, squeezing the
  card's six stat cells, and weekdays flowing top-to-bottom clashed with how calendars are read.
* **Header** (below the rail) — on the left, phase · week number and a large weekday name; on the
  right, `1년 12월` (Year 1, December) and a large number for that day's **day of month (日)**. The
  date is built by adding the weekday offset to that week's Monday
  (`season_state.year/month/day`) (`_date_of_day`; it can cross a month, so it goes through
  `CalendarSystem.DAYS_IN_MONTH`).
* **Body** — the card list, vertical scroll (`%Scroll`, drag-scrolled by `DragScroll.attach` in `_ready`).
  On a training day the team base map sits pinned above it (`%MapPin`) and the list starts under the map.
* **Bottom bar**: training day: `오전` / `오후` (stage label, left) + `다음` (Next, amber, right). Match day:
  the label is hidden and the button takes the full width: `확인` (OK), on Sunday `주 마감 →` (End of
  week); if the player still has a match that day, **`경기 시작`** (Start match) (dark fill, "you are
  leaving this screen").

## What each weekday does

| Weekday | What happens |
|---|---|
| 월~금 (Mon–Fri) | **Training days**, split into 오전 (morning) and 오후 (afternoon), see "Training day: morning → afternoon". The morning's Next runs `TrainingBoard.apply_day_training(day)`, which settles that row of the board and actually raises player stats. |
| 토 · 일 (Sat · Sun) | **Match days (경기일)** (`CalendarSystem.MATCH_DAYS` — Sat = match day 0, Sun = match day 1). That day's scheduled matches show up as cards. |

### Training day: morning → afternoon (base map)

A training day runs in three stages (`WeekProgressView.Stage`). The stage is **read from the records**, not
stored on its own (`_stage`), so re-entering the day (after a match, after a reload) lands on the same stage:

| Stage | Record | Map | Next (다음) |
|---|---|---|---|
| `MORNING` | no `week_day_log[day]` | each pilot on the spot of **that day's training colour** (`TrainingBoard.day_colors`; no tile = basic course = neutral `W`); a **speech bubble** over the portrait names the training (`TrainingBoard.day_tile_names`) | settles the day (`_settle_day` → `apply_day_training`) |
| `RESULT` | `week_day_log[day]` set, no afternoon record | same spots, no bubble; **result FX** (`_play_result_fx`): per pilot, lines rise out of the portrait top and fade (`FX_RISE` / `FX_TIME`, `FX_STAGGER` between lines, `FX_PILOT_STAGGER` between pilots): stat ups by **full name** (`전장 명중 +1`, else `EXP +N`), `스트레스 ±N`, mech mastery, quirk events; the bottom cards' stress change pops (`pulse_note`). When the FX ends the afternoon **starts by itself** (`_finish_result_fx` → `AfternoonAway.begin`) | skips the rest of the FX (same `_finish_result_fx`) |
| `AFTERNOON` | `AfternoonAway.started` | resting pilots on `Dorm`, pilots out alone on `Entrance`; anyone who cannot be asked is dimmed and not tappable (`AfternoonAway.can_request`) | next day (`on_week_day_confirmed`); while an action is still possible (`AfternoonAway.any_request`) a **warning** `ConfirmPopup` asks first, confirm = pass |

* **Map**: the team's base map (`RunRules.team_map_id(player_team_id)` = `teams.csv` `map_id` → `BaseMap.create`),
  pinned in `%MapPin` above the scrolling list. Spots per colour group and the fan-out of tokens sharing a spot: `base_map/README.md`.
  The caption above it (`%Hint`) says what Next does in this stage.
* **Bottom pilot cards** (`%PilotRow`, every day, both halves): `SeasonPilotCard` × 5 in seat order; the note line is
  **the day's stress change** (`_day_stress_delta` = training row `stress` + self-outing relief + `stress` notes of the
  day's incident / afternoon outcomes), red `+N` / green `-N`, hidden at 0. Tap = `SeasonPilotDetail` sheet.
* A reload between the settlement and the afternoon lands on `RESULT`: the FX plays again, then the afternoon starts.
* **Afternoon away states** (rules and record: `features/season/mental/README.md` "Afternoon away states"):
  a stressed pilot may go out alone, otherwise any pilot may stay in the dorm by chance (rolled once, recorded).
  An empty training cell is the basic course, not a rest.
* The bottom bar's left slot names the half (`오전` for `MORNING` / `RESULT`, `오후` for `AFTERNOON`).

### Training results

No per-pilot result cards any more (see the file table). What the old card showed now lives in the RESULT FX
lines (`_result_lines`): stat points that rose (full stat names), else the EXP earned; the stress change;
mech mastery (`숙련 +N · <mech>`, the same steps as `MechMastery.add_training_exp`, `_mastery_text`); quirk
events (`_quirk_lines`: gain / reroll amber, slot green, no-op results faint). Current stat values are in the
pilot detail sheet (tap a bottom card).

### Match card

Lists every match of that match day, with **the player's match on top** in a dark fill
(the rest are white cards at half height). Two sources — the bracket if a tournament is running,
otherwise the league schedule (`_matches_on_day`). The status cell is `예정` (Scheduled) /
`승` (Win) / `패` (Loss) / `<팀> 승` (<team> wins).

### Mon–Fri: incident card + 오후 (afternoon) card (M7)

Rules and state are in `features/season/mental/README.md` (`MentalSystem`); this screen only draws
records and forwards taps. On a training day the list order is **(pinned map) → afternoon → incident**.

* **Incident** — `refresh()` calls `MentalSystem.ensure_incident(state, day)` (rolled once per weekday,
  seeded). A pending incident opens its dialog **by itself** (`_open_incident`, deferred); the card (red lead
  bar) shows `사건: <name> · <pilot>` and either `눌러서 대응하기` (reopens the dialog) or the effect notes once resolved.
* **오후** (`AFTERNOON` only): tap an available pilot on the map (amber ring), then `면담` / `외출` on the
  afternoon card. **No weekly count limits** (removed 2026-10): an interview is always possible, an outing needs
  trust ≥ `TRUST_OUTING_MIN` (the disabled button reads `외출 (신뢰 N↑)`). Without a pick the card says how
  to pick (or that nothing is possible today). After the action the card collapses to a one-line summary with the effect notes.
  Pressing Next without an action records a **pass** (after the warning when an action was still possible).
  The record keeps its old name `evening` (`MentalSystem.begin_evening` / `finish_evening`), so saves stay compatible.
* **Dialog overlay**: interview / outing / incident open a `VnDialogueView` (visual-novel dialogue,
  `features/season/mental/README.md`; an incident's title is its `@tag`, the name plate the pilot), as the
  last child of this screen (`_overlay`, opened only through `_open_overlay`); its STOP root blocks the list and the bottom bar until it
  closes, then the screen `refresh()`es. An afternoon dialog left open by a reload (record with `choice = -1`)
  reopens itself with the same event.

## Never settle twice

A weekday's result is kept in `season_state["week_day_log"][day]`, and **if it already exists it is
not settled again** (`_settle_day`, run by the morning's Next). There really is a path that returns to the same
weekday after playing a match —

```
WEEK Sat  →  경기 시작  →  MatchFlow → BattleSim  →  re-enter Season
        →  SeasonHub applies the result + settles that match day's AI matches  →  STANDINGS
        →  확인  →  WEEK Sat (that match is now played, so the button is "확인" again)
        →  확인  →  WEEK Sun
```

There are three pieces of week-progress state (all in `season_state`, all saved).

| Key | Meaning |
|---|---|
| `week_day` | The weekday currently shown, 0..6. **-1 means the week has not been opened yet** — the hub · press conference (기자회견) · training plan stretch is all -1, and that value decides whether the standings' "확인" returns to the week or to the hub (`SeasonHub.on_standings_confirmed`). |
| `week_day_log` | `day(int) → Array[row]` (rows keep `pilot_id` only — the pilot card name is `GameManager.pilot_name(pilot_id)`; row key `color` = that day's cell colour, an empty cell = the basic course's colour). Integer keys, so on load it goes through `_int_keyed_dict_in` — otherwise `log[3]` returns an empty array forever and the same weekday's training is applied twice. |
| `training_exp_carry` | The leftover-EXP bank. See the `TrainingBoard` entry. |

All three are cleared by `TrainingBoard.reset_week_progress()`, which runs in two places:
**training confirm** (`SeasonHub.on_training_confirmed`) and **week end** (`reset_for_new_week`).

The M7 afternoon action, the incident and the afternoon away states follow the same rule with their own
record, `season_state.mental.days["<day>"]` (`MentalSystem`; `AfternoonAway` keeps `afternoon` there): the
incident and the away states are rolled once and the afternoon dialog's event is stored before it opens, so
re-entering the weekday (after a match, after load) redraws from the record and never rerolls or re-applies.
`MentalSystem.end_week` clears it.

## Exchanges with SeasonHub

| Direction | Functions |
|---|---|
| Screen → hub | `has_player_match_on_day(day)` · `opponent_name_on_day(day)` · `on_week_day_match_start()` · `on_week_day_confirmed()` |
| Hub → screen | `ensure_view()` (on every routing) |

`on_week_day_confirmed()` sweeps up that day's AI matches **before moving on**
(`_resolve_ai_for_matchday`) — even when the player has no match that day and just moves on, that
day's league must still run, so the next standings shown match the date.

## Localization
Display text is l10n keys (`season` domain, `season.week.*` · `season.week_*` scene keys; the map / afternoon
keys are `season.week.stage.*` · `season.week.map_hint.*` · `season.week.map.*` · `season.week.afternoon_*` ·
`season.week.skip.*` · `season.week.sub_*_pm`). Bubble texts are training tile names (data). Deprecated 2026-10:
`season.week.evening_limits` · `season.week.interview_week_done` · `season.week.outing_week_done` (weekly limits removed),
`mental.ui.stress.day` (old training card). Item scenes whose every label is code-filled set
`auto_translate_mode = 2` on their root; `UI_View_WeekProgressView.tscn` and `UI_Comp_WeekAfternoonCard.tscn` set it
per label (the afternoon card's head is a key, and it is instanced under the screen, so the screen root must not
disable translation). The old `season.week_evening_card.*` · `season.week.evening_*` · `season.week.sub_interview` /
`sub_outing` keys are `deprecated`.
