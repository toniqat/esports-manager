# Week progress (시간 경과) (week)

The screen where the week passes **one day at a time, Monday to Sunday**. `Screen.WEEK` in
`SeasonHub`. Training days (Mon–Fri) show the **team base map** and run as **morning → afternoon → evening**.
The weekend carries the week's one player match: **Saturday morning** = stadium map + match prep
(ban/pick), **Sunday morning** = stadium map + the match, then the press conference, the afternoon
(visit) and the evening — see "Weekend (Sat · Sun)". Every afternoon is a **visit (방문, §15 D)**: tap a pilot →
집중 훈련 / 이야기 / 외출 (`VisitMenu`, "Afternoon visit" below).

| File | Role |
|---|---|
| `WeekProgressView.gd` | `class_name WeekProgressView extends Control` — the whole screen's logic. Binds `%` nodes, fills data, adds the list's item scenes, drives the training-day stages. Create with `WeekProgressView.create()` (`.new()` is an empty Control) |
| `UI_View_WeekProgressView.tscn` | The screen layout (tree below) |
| `base_map/` | `BaseMap` widget + one `UI_Comp_BaseMap_<Name>.tscn` per team base map (art + spot markers) + the weekend `UI_Comp_BaseMap_Stadium.tscn`. See `base_map/README.md` |
| `UI_Comp_WeekMapSection.tscn` | The map slot (fills `%MapPin`, full screen width): `%MapHolder` (plain Control) that receives the team's `BaseMap` / the stadium via `BaseMap.mount` (1200 × 761, centred, 60 px cropped each side). No caption and no facility research bubbles on this screen (both removed 2026-10; the hub keeps the bubbles) |
| `UI_Comp_WeekMapPilot.tscn` | One pilot token on the map, 92 × 92, **portrait only** (`%Portrait` slot 84 · `%Mask` black circle over the portrait; the stress / trust gauges moved to the pilot cards under the map 2026-10) · morning speech bubble `%Bubble` / `%BubbleText` + `%BubbleTail` · afternoon away chip `%Away` / `%Name` over the portrait top · rising result texts `%Floats` with the `%FloatLine` template · `%Hit` over the whole token · the portrait disc, black outline, tail and shadow are not in the scene — `BaseMap` draws them under the token, `base_map/README.md`). No name, no role badge |
| `UI_Comp_WeekMatchCard.tscn` | Item: one match of the match day (`%Tag` · `%Title` · `%Status` · `%Hint`) |
| `UI_Comp_WeekNoteCard.tscn` | Item: one-line placeholder card (`%Text`) |
| `UI_Comp_WeekIncidentCard.tscn` | Item: the day's incident (`%Portrait` slot · `%Head` · `%Line` · `%Hit`) |
| `UI_Comp_WeekAfternoonCard.tscn` | Item: 오후 before the visit — `PanelContainer` (Card, height = content) ─ Box VBox: Head · `%Hint` (only when nobody can be visited) · `%Coach` (coach points left / weekly grant). The "tap a pilot on the map …" instruction was removed 2026-10 |
| `VisitMenu.gd` | `class_name VisitMenu extends CanvasLayer` — the afternoon **visit (방문)** popup, two surfaces: the **menu** as a **speech bubble over the visited pilot's token** (only the options 집중 훈련 / 이야기 / 외출), and the **focus training modal** centred in the safe area over a dim (courses → result; the bubble hides, Back on the courses page returns to the bubble). `point_at(portrait, token)` gives the bubble's target; `_place_bubble` (every frame while the menu page is open, only on change) puts the bubble above the portrait with the tail down, else under the token with the tail flipped up, else on the roomier side clamped into the safe area (tail hidden if it would cover the token); x centred on the token, clamped into the safe area. The result page hosts an `EventResultPanel` (`show_result(state, notes)` takes the outcome's **note dicts**, right after they were applied: bars before → after + stat chips). Draws and emits only (`option_picked` · `course_picked` · `closed`); `create()`, `point_at` / `open_menu` / `show_courses` / `show_result`. F6 preview = the menu of my first visitable pilot (visit recorded in memory), centred, no tail; 집중 훈련 → courses → a real `finish_focus` result |
| `UI_View_VisitMenu.tscn` | Its scene (layer 20): `Root` full rect STOP (swallows other taps) → `%Bubble` (`VisitMenuBubble`, 840 wide): VBox sep 16 — `%Header` (`%Portrait` 80 · `%Name` · `%PilotLine` · `%Coach`) · `%Caption` · `%Options` (`%Focus` / `%Story` / `%Outing` `SelectableCardButton`s 104 high with title + note); `%Tail` (Node2D, `Edge` + `Fill` triangles); `%Modal` (hidden; `Dim` `DimPanel` + `%Safe` CenterContainer inset to the safe area → `Card` `PopupCard` 920 wide: `%ModalHeader` (courses page only: `%ModalPortrait` · `%ModalName` · `%ModalPilotLine` · `%ModalCoach`) · `%ModalCaption` · `%Courses` · `%EventResultPanel_Result` (`UI_Comp_EventResultPanel`) · `Buttons` (`%Back` · `%Confirm`)) |
| `UI_Comp_VisitCourseRow.tscn` | Item of the menu (no script): one focus course, 96 high (`%Name` · `%Stats` · `%Cost` · `%Reason`; picked = `SelectableCardButtonOn`) |
| `UI_Comp_WeekAfternoonDoneCard.tscn` | Item: 오후 summary after the action (`%Portrait` · `%Head` · `%Line`); also the morning talk's summary |
| `UI_Comp_WeekTalkCard.tscn` | Item: 오전 만남 before the talk (`%Hint` = only "nobody can be met"; the "tap a pilot on the map" instruction was removed 2026-10 · `%Pilot` (`%Portrait` · `%Name` · `%With` = joint-training partner or trust) · `%Talk`) |
| *(shared)* `../UI_Comp_SeasonPilotCard.tscn` | The five pilot cards of `%PilotRow` (`features/season/README.md` "Pilot card · detail sheet") |

The per-pilot training result cards (`WeekPilotCard` + `WeekStatCell`, six short-named stat columns) were deleted
(2026-10): the day's results now rise over the map portraits and the stress change sits on the pilot cards under the map.

The old evening card (`WeekEveningCard` with five `WeekEveningSlot` portraits and a `패스` button) was replaced by
the map + afternoon card; the slot scene and its `WeekEveningHighlight` variation were deleted.

**F6 preview** — run `UI_View_WeekProgressView.tscn` alone and it fills dummy data (`resources/UiPreview.gd`):
in-memory run on **Wednesday afternoon**, a preview-only `TrainingBoard` (`PreviewBoard` child, coach arrangement)
settles Mon–Wed, a pending incident is resolved with its first answer so no overlay covers the cards, the afternoon
is begun (away states rolled); tap a pilot to open the visit popup (live, in memory). Each base map scene has its own
F6 preview (one token per spot, named after it).

## Scene (`UI_View_WeekProgressView.tscn`)

```
WeekProgressView (Control, full rect, PASS, theme OutgameTheme.tres)
├ %Background   ColorRect BG — code: ScreenMetrics.extend_background (notch band)
└ %SafeArea     full rect — code: offset_bottom = −bottom inset (bottom edge = safe_h())
  ├ Rail        Panel `WeekRail` (dark pill, RAIL r48), x 24 … −24, y 26 … 122
  │ └ Row (HBox) ─ LeftPad (14)
  │              ─ %Days (HBox, expand) ─ Day0…Day6 (CenterContainer, equal share ≈ 143)
  │              │                         └ Chip (Panel 124×80, `WeekDayChip` / `WeekDayChipToday`)
  │              │                           └ Box (VBox, centred, sep −6) ─ NumRow (HBox, centred, sep 5):
  │              │                             DayTag (16, "DAY", key `season.week.rail_day`, today only) · Num (30)
  │              │                             ─ Abbr (14, MON … SUN)
  │              ─ RightPad (14)
  ├ %Phase (CaptionLabel 26, centred, x 40 … −40, y 134 … 170)  ← phase name only
  ├ Divider     y 182
  ├ %MapPin     full width, y 194 … 955 (761 = map height), hidden by default: fixed slot for the map (WeekMapSection)
  ├ %Scroll     x 40 … −40, y 1227 … −142 (= bar top − 14), anchors_preset −1 (grows right only); top set by code
  │ └ %List     VBox, separation 14 (card gap) — item scenes + %ListEnd (kept last = gap under the last card)
  ├ %PilotRow   HBox sep 12, x 40 … −40, y 969 … 1213 (= %MapPin bottom + 14, top-anchored): SeasonPilotCard_Pilot0..4
  │             (seat order), **always shown**. `_place_under_map` keeps row + list under the map (authored gap 14); with no
  │             map (`Stage.OFF`) both move up to %MapPin's top
  └ %Bar        HBox capsule row, sep 16, y −128 … −32, 40 side insets — code: `OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)`
    ├ %FloatingBarButton_Stage  BarDarkButton 28, ratio 1, mouse Ignore (a label: 오전 / 오후 / 저녁); hidden when the day has no stage
    └ %FloatingBarButton_Action BarPrimaryButton, ratio 2 (다음 / 확인 / 기자회견 / 주 마감 →); `BarDarkButton` for 경기 준비 / 경기 시작 + `fit_bar_button`
```

* **Scene owns**: every position / size, fonts (variations + size overrides), the rail pill (screen variation,
  no local StyleBoxes), button kinds of the afternoon card, the map section / token layout, sample texts. Spot
  positions are the `Spot_*` markers of each base map scene.
* **Code owns** (data / device dependent): the chip numbers / abbreviations, which chip is today (variation switch
  `WeekDayChip` ↔ `WeekDayChipToday`, its `DayTag` shown) and the chip text colours,
  the lead bars (role colour, incident = `NEGATIVE`) and the player's dark match card
  (`card_style(…, RAIL)`), status / role / trust / result colours, card heights (match 168 / 96), the round portraits (cards: drawn into the `%Portrait` slots with
  `OutgameTheme.add_round_portrait`; map tokens: battlefield markers drawn by `BaseMap` from the `portrait` / `ring` of each
  `place_tokens` entry — the others a black outline, the picked token an `ACCENT` outline and is scaled `MAP_PICKED_SCALE` 1.2 around its
  centre, drawn over the others), the black mask of a token whose pilot cannot be picked
  (`_token_dimmed`: `%Mask`), which base map scene is instanced (team data), where the tokens
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
│  15   16   17   18 [DAY 19] 20   21       │  ← top horizontal weekday rail: day inside the phase
│  MON  TUE  WED  THU   FRI   SAT  SUN      │    over the weekday abbreviation; today = amber + "DAY"
└──────────────────────────────────────────┘
                 프리시즌                       ← phase name, centred
 ──────────────────────────────────────────
[   team base map 1200 wide, five pilot tokens   ]  ← pinned (%MapPin), does not scroll; 60 px cropped each side
  [TOP][JGL][MID][ADC][SUP]                  ← %PilotRow: five pilot cards, always shown, right under the map
  ▌(○) 오후                                  ← afternoon card, then incident (scroll, down to the bar)
 [  오후  ][            다음            ]
```

(Mockup uses in-game Korean text: "프리시즌" = Preseason, 오후 = afternoon,
`다음` = Next.)

* **Top horizontal rail** — on a dark pill spanning the full screen width, seven weekday (요일) chips
  spaced evenly **left → right** (the old `N주` label at the left end was removed 2026-10). Each chip shows
  **that weekday's day number inside the phase** (`CalendarSystem.day_in_phase` of today − today's weekday + the
  chip's weekday) with the English abbreviation `MON` … `SUN` under it (`WeekProgressView.day_abbr`, keys
  `term.day.abbr.*`). **Only the current weekday's chip is filled amber** and adds a small `DAY` left of its number. Past days have white text, remaining days dim text — that
  contrast lets you read "how many days left" from the rail alone. It used to be a **left vertical
  column** (exactly as in the reference design), but the rail took 152 px of width, squeezing the
  card's six stat cells, and weekdays flowing top-to-bottom clashed with how calendars are read.
* **Header** (below the rail) — the **phase name only**, centred (`GameEnums.phase_label`). The old centred
  `DAY N` / weekday block (`%DayCount` / `%DayAbbr`, key `season.week.day_count`) was folded into the rail 2026-10.
  No calendar date (year / month / day of month) any more — removed 2026-10 with the
  week number, the weekday title and `_date_of_day`.
* **Body** — the card list, vertical scroll (`%Scroll`, drag-scrolled by `DragScroll.attach` in `_ready`).
  On a training day the team base map sits pinned above it (`%MapPin`), then the pilot cards (`%PilotRow`), then the list.
* **Bottom bar**: stage label (left: `오전` / `오후` / `저녁`) + the action (right): `다음` (Next) on every
  stage, **`경기 준비`** (Match prep, Saturday stadium) / **`경기 시작`** (Start match, Sunday stadium) in the
  dark fill ("you are leaving this screen"), `기자회견` (Press conference, Sunday afternoon,
  `term.activity.press`), `주 마감 →` (End of week) on the Sunday evening. A day without any stage shows
  `확인` (OK) full width.

## What each weekday does

| Weekday | What happens |
|---|---|
| 월~금 (Mon–Fri) | **Training days**: 오전 (training, then the morning talk) → 오후 (afternoon) → 저녁 (evening incident), see "Training day: morning → afternoon → evening". The morning's Next runs `TrainingBoard.apply_day_training(day)`, which settles that row of the board and actually raises player stats. |
| 토 (Sat) | **Prep day**: `STADIUM` (stadium map, "경기 준비" → MatchFlow PREP + BAN_PICK, picks stored) → `AFTERNOON` → `EVENING` on the team map, **no training, no morning talk**. Sunday's matches show as cards while the prep is open. |
| 일 (Sun) | **Match day** (`CalendarSystem.MATCH_DAY`): `STADIUM` ("경기 시작" → BattleSim with the Saturday picks) → standings → `PRESS` (stadium map, "기자회견") → `AFTERNOON` (team map, visit — the story is about the match) → `EVENING` (incident) → "주 마감 →". The day's matches show as cards. |

### Training day: morning → afternoon → evening (base map)

A training day runs in five stages (`WeekProgressView.Stage`). The stage is **read from the records**, not
stored on its own (`_stage`), so re-entering the day (after a match, after a reload) lands on the same stage:

| Stage | Record | Map | Next (다음) |
|---|---|---|---|
| `MORNING` | no `week_day_log[day]` | each pilot on the spot of **that day's training facility** (`TrainingBoard.day_groups` `facility` → `BaseMap.spot_of_facility`: the tile's `facility` column, else the colour of its first cell that day, so a joint-training group shares one spot; no tile = basic course = neutral `W`); a **speech bubble** over the portrait names the training (`TrainingBoard.day_tile_names`) | settles the day (`_settle_day` → `apply_day_training`) |
| `RESULT` | `week_day_log[day]` set, no talk record | same spots, no bubble; **result FX** (`_play_result_fx`): per pilot, lines rise out of the portrait top and fade (`FX_RISE` / `FX_TIME`, `FX_STAGGER` between lines, `FX_PILOT_STAGGER` between pilots): stat ups by **full name** (`전장 명중 +1`, else `EXP +N`), `스트레스 ±N`, quirk events; the pilot cards' stress change pops (`pulse_note`). When the FX ends the morning talk **opens by itself** (`_finish_result_fx` → `MentalSystem.begin_morning`) | skips the rest of the FX (same `_finish_result_fx`) |
| `TALK` | `MentalSystem.morning_started`, no afternoon record | same spots; pilots that can be met are tappable (`MentalSystem.can_talk`), the picked one is scaled up; once the talk is used **every** token is masked black. Pick one → `%Talk` on the talk card → morning talk dialog (joint training: the partner comes along) | afternoon (`_begin_afternoon`: `pass_talk` + `AfternoonAway.begin`); while a talk is still possible a **warning** asks first |
| `AFTERNOON` | `AfternoonAway.started`, no `dusk` | resting pilots on `Dorm`, pilots out alone on `Entrance`; anyone who cannot be visited is masked black and not tappable (`AfternoonAway.can_request`), except the pilot whose visit is under way (scaled up). Tap = visit (`VisitMenu`); once the visit is used every token is masked | evening (`_begin_evening`: pass if unused, `MentalSystem.begin_dusk` rolls the incident; **no incident and no limit-break event = straight to the next day**, except Sunday, which stops on its evening for "주 마감 →"); while a visit is still possible (`AfternoonAway.any_request`) a **warning** `ConfirmPopup` asks first, confirm = pass |
| `EVENING` | `MentalSystem.dusk_started` | afternoon positions, nobody tappable, every token masked; the limit-break event (§15 B) then the incident open by themselves | next day (`on_week_day_confirmed`) |

* **Map**: the team's base map (`RunRules.team_map_id(player_team_id)` = `teams.csv` `map_id` → `BaseMap.create`),
  pinned in `%MapPin` above the pilot cards and the scrolling list. Spots per colour group, the 1.2× scale / crop
  and the line-up of tokens sharing a spot: `base_map/README.md`. There is no caption over the map (the old `%Hint`
  "what Next does now" line was removed 2026-10) and no facility research bubbles (hub only).
* **Pilot cards under the map** (`%PilotRow`, every day, both halves): `SeasonPilotCard` × 5 in seat order (portrait in the 깨달음 level ring, the two stress · trust gauges, no role badge, no card background); each gauge shows
  **the day's change** (`SeasonPilotCard.set_day_deltas`: ring segment from the value before + `(+N)` stress / `(+N%)` trust
  under the value, nothing at 0; they pop when the result FX starts), and the portrait ring shows the day's level EXP as a
  light segment. `_day_delta(pid, kind)` (kind `stress` · `trust` · `tlexp`) = training row `stress` / `tlexp` + self-outing relief (stress) + `kind` / `<kind>_all` notes of the
  day's talk / incident / afternoon (visit · evening) outcomes. Not counted (not in the day record): the Sunday press answer,
  the match's level EXP; `<kind>_all` notes are nominal (unclamped). Tap = `SeasonPilotDetail` sheet.
* A reload between the settlement and the afternoon lands on `RESULT`: the FX plays again, then the afternoon starts.
* **Autosave** (`_save` → `SeasonHub.autosave`): after the settlement, the talk opening, the afternoon, the incident roll,
  opening a talk, the visit (`visit`), a story / outing, a focus course (`focus`), an awakening / limit break and
  every answer — closing the game mid-week resumes on this screen at
  the same stage (`features/save_load/README.md`).
* **Afternoon away states** (rules and record: `features/season/mental/README.md` "Afternoon away states"):
  a stressed pilot may go out alone, otherwise any pilot may stay in the dorm by chance (rolled once, recorded).
  An empty training cell is the basic course, not a rest.
* The bottom bar's left slot names the half (`오전` for `MORNING` / `RESULT` / `TALK`, `오후` for `AFTERNOON`, `저녁` for `EVENING`).
* Old saves that reached the afternoon before the morning talk existed simply skip it (`_stage` checks the
  afternoon record first). The map pick (`_sel_pid`) is dropped when the stage changes (`_sel_stage`).

### Weekend (Sat · Sun)

The stages are read from the records like the training days (`_stage` → `_weekend_stage`), so a reload
lands on the same spot:

| Day | Stage | Record | Map | Action |
|---|---|---|---|---|
| Sat | `STADIUM` | `SeasonHub.needs_match_prep(5)`: a player match this Sunday, no `pending_match.picks` | stadium, pilots in the team room (`SPOT_TEAM_ROOM`) | **경기 준비** → `SeasonHub.on_week_day_match_prep` (MatchFlow split mode) |
| Sat | `AFTERNOON` → `EVENING` | `AfternoonAway` / dusk records (opened by itself, `_advance_weekend`) | team map, everyone on `W` (no training), away spots | as on a training day |
| Sun | `STADIUM` | `has_player_match_on_day(6)` | stadium, pilots on the stage booths (`SPOT_BOOTH`) | **경기 시작** → `SeasonHub.on_week_day_match_start` (picks → BattleSim) |
| Sun | `PRESS` | `SeasonHub.press_pending()`: my match of the week played, press unanswered | stadium, press room (`SPOT_PRESS`) | **기자회견** → `SeasonHub.open_press` (the standings' 확인 opens it directly) |
| Sun | `AFTERNOON` | after the press `_advance_weekend` runs `AfternoonAway.begin` (§15 D) | team map | visit as on a training day; **다음** → evening |
| Sun | `EVENING` | `_begin_evening` → `MentalSystem.begin_dusk` (incident roll) | team map | **주 마감 →** (a limit-break event / an incident opens by itself first) |

* A weekend day **without a player match** runs `AFTERNOON` → `EVENING` only (opened by itself).
* `_advance_weekend` (called by `refresh`) records + saves the automatic step (`afternoon`). Old saves whose match
  Sunday already rolled its evening stay in the evening.
* Match card hint (my match): Saturday `season.week.hint_prep`, Sunday with picks
  `season.week.hint_match_ready`, Sunday without picks (old save) `season.week.hint_start`.

### Training results
### Match card

Lists every match of that match day (Sunday; on Saturday while the prep is open, Sunday's matches), with **the player's match on top** in a dark fill
(the rest are white cards at half height). Two sources — the bracket if a tournament is running,
otherwise the league schedule (`_matches_on_day`). The status cell is `예정` (Scheduled) /
`승` (Win) / `패` (Loss) / `<팀> 승` (<team> wins).

### Mon–Fri: 오전 만남 (talk) card + 오후 (afternoon) card + incident card (M7)

Rules and state are in `features/season/mental/README.md` (`MentalSystem`); this screen only draws
records and forwards taps. On a training day the list order is **(pinned map) → talk / afternoon → incident**.

* **오전 만남** (`TALK` only): tap a pilot on the map, then `만남` on the talk card. `%With` names the joint-training
  partner who comes along (`MentalSystem.talk_partner`, amber) or shows trust. After the talk the card collapses to a
  summary (`AfternoonDoneCard`). A talk left open by a reload reopens itself (`_talk_open`).
* **Incident** — rolled when the evening starts (`_begin_evening` → `MentalSystem.begin_dusk`, once per weekday,
  seeded). A pending incident opens its dialog **by itself** (`_open_incident`, deferred); the card (red lead
  bar) shows `사건: <name> · <pilot>` and either `눌러서 대응하기` (reopens the dialog) or the effect notes once resolved.
* **오후 = visit (방문, §15 D)** (`AFTERNOON` only) — see "Afternoon visit" below. The afternoon card says how to
  visit and shows the week's coach points (`StaffSystem.coach_points` / `coach_points_grant`). After the visit the
  card collapses to a one-line summary (`오후: <name> 집중 훈련 · <course>` / `오후: <name>와 이야기` / `오후: <name> 외출`)
  with the effect notes. Pressing Next without a visit records a **pass** (after the warning when a visit was still
  possible). The record keeps its old name `evening`, so saves stay compatible.
* **Dialog overlay**: story / outing / limit-break event / incident open a `VnDialogueView` (visual-novel dialogue,
  `features/season/mental/README.md`; an incident's title is its `@tag`, the name plate the pilot), as the
  last child of this screen (`_overlay`, opened only through `_open_overlay`); its STOP root blocks the list and the bottom bar until it
  closes, then the screen `refresh()`es. An afternoon dialog left open by a reload (record with `choice = -1`)
  reopens itself with the same event.
* **What opens by itself** (`_open_pending`, deferred after every `refresh`, one at a time, `_busy()` blocks the rest):
  a talk / visit menu / afternoon dialog left open → a queued **awakening** (§15 C) → at the evening the
  **limit-break event** (§15 B) → the incident.

### Afternoon visit (방문, §15 D)
Rules and records: `features/season/mental/README.md` "Afternoon visit (방문)".
1. Tap a pilot on the base map — always that pilot (tokens never overlap, there is no picker).
2. `_start_visit` → `MentalSystem.begin_visit` records the visit **before** the menu opens, saves (`visit`), and the
   menu bubble (pointing at the scaled-up token) shows 집중 훈련 (greyed out when the points are short) / 이야기 (what today's story is about) /
   외출 (greyed out under `TRUST_OUTING_LEVEL`, the note says why). There is no way out of the menu but an option.
3. 집중 훈련 → the bubble hides and the **focus training modal** opens centred on screen over a dim: courses page
   (pick a row, then the confirm button; 뒤로 → back to the bubble) → `MentalSystem.finish_focus` → result page in the
   same modal (`EventResultPanel`: the pilot's training EXP / awakening / stress bars + stat chips, coach points in
   the team block) → 확인 → redraw. 이야기 / 외출 → `begin_evening` → the VN dialogue.
4. A reload with the menu or the courses modal open (`MentalSystem.visit_open`) reopens the menu bubble (no course is
   stored before the confirm); once the course is confirmed the visit is settled and nothing reopens.

### Awakening and limit break (§15 B · C integration)
* **Awakening** (`_open_awakening`): after every redraw (morning settlement once its result FX has ended, every
  dialog / visit result, the return from a match) `Awakening.next_pending(state)` ≥ 0 opens C's `AwakeningView`
  (`create()` → `add_child` → `open(pid)`, waits for `closed`, saves `awakening`, redraws → polls again). The class
  is looked up by name (`ProjectSettings.get_global_class_list`), so a tree without it simply skips.
* **Limit break** (`_open_limit_break`): when the evening has started and `LimitBreak.pending_event(state, day)` ≥ 0,
  `LimitBreak.session(state, pid)` (a `session_view`-shaped dict) plays in the shared `VnDialogueView` (overlay kind
  `limit_break`, sub `season.week.sub_limit_break`); the answer goes to `LimitBreak.choose_goal`, whose return is the
  outcome view for `show_result`. Its close redraws, and the incident follows.

## Never settle twice

A weekday's result is kept in `season_state["week_day_log"][day]`, and **if it already exists it is
not settled again** (`_settle_day`, run by the morning's Next). The screen is rebuilt on the same day
after MatchFlow / BattleSim and after a reload —

```
WEEK Sat  →  경기 준비  →  MatchFlow PREP → BAN_PICK  →  picks stored  →  re-enter Season  →  WEEK Sat (afternoon)
WEEK Sun  →  경기 시작  →  MatchFlow LAUNCH → BattleSim  →  re-enter Season
        →  SeasonHub applies the result + settles that match day's AI matches  →  STANDINGS
        →  확인  →  PRESS  →  WEEK Sun (evening)  →  주 마감 →
```

There are three pieces of week-progress state (all in `season_state`, all saved).

| Key | Meaning |
|---|---|
| `week_day` | The weekday currently shown, 0..6. **-1 means the week has not been opened yet** — the hub · press conference (기자회견) · training plan stretch is all -1, and that value decides whether the standings' "확인" returns to the week or to the hub (`SeasonHub.on_standings_confirmed`). |
| `week_day_log` | `day(int) → Array[row]` (rows keep `pilot_id` only — the pilot card name is `GameManager.pilot_name(pilot_id)`; row key `color` = that day's cell colour, an empty cell = the basic course's colour). Integer keys, so on load it goes through `_int_keyed_dict_in` — otherwise `log[3]` returns an empty array forever and the same weekday's training is applied twice. |
| `training_exp_carry` | The leftover-EXP bank. See the `TrainingBoard` entry. |

All three are cleared by `TrainingBoard.reset_week_progress()`, which runs in two places:
**training confirm** (`SeasonHub.on_training_confirmed`) and **week end** (`reset_for_new_week`).

The M7 morning talk, the afternoon action, the incident and the afternoon away states follow the same rule with their own
record, `season_state.mental.days["<day>"]` (`MentalSystem`; `AfternoonAway` keeps `afternoon` there): the
incident and the away states are rolled once and the afternoon dialog's event is stored before it opens, so
re-entering the weekday (after a match, after load) redraws from the record and never rerolls or re-applies.
`MentalSystem.end_week` clears it.

## Exchanges with SeasonHub

| Direction | Functions |
|---|---|
| Screen → hub | `has_player_match_on_day(day)` · `needs_match_prep(day)` · `match_picks_ready()` · `press_pending()` · `player_result_this_week()` · `opponent_name_on_day(day)` · `on_week_day_match_prep()` · `on_week_day_match_start()` · `open_press()` · `on_week_day_confirmed()` |
| Hub → screen | `ensure_view()` (on every routing) |

`on_week_day_confirmed()` sweeps up that day's AI matches **before moving on**
(`_resolve_ai_for_matchday`) — even when the player has no match that day and just moves on, that
day's league must still run, so the next standings shown match the date.

## Localization
Display text is l10n keys (`season` domain, `season.week.*` · `season.week_*` scene keys; the map / afternoon
keys are `season.week.stage.*` · `season.week.map.*` · `season.week.afternoon_*` ·
`season.week.skip.*` · `season.week.skip_talk.*` · `season.week.talk_*` · `season.week.talk_card.head` (scene) ·
`season.week.sub_talk` · `season.week.sub_*_pm`; weekend: `season.week.btn_match_prep` · `season.week.hint_prep` ·
`season.week.hint_match_ready`; the press button reuses `term.activity.press`; rail: `season.week.rail_day` (scene, today's "DAY") ·
`term.day.abbr.*`). Deleted 2026-10 (rows removed): `season.week.map_hint.*` (11, the map caption),
`season.week.date` (the `N년 N월` header), `season.week.day_count` (the `DAY N` header block),
`season.week.afternoon_pick` / `season.week.talk_pick` (the "tap a pilot on the map" card hints). Bubble texts are training tile names (data). Deprecated 2026-10:
`season.week.evening_limits` · `season.week.interview_week_done` · `season.week.outing_week_done` (weekly limits removed),
`mental.ui.stress.day` (old training card). Item scenes whose every label is code-filled set
`auto_translate_mode = 2` on their root; `UI_View_WeekProgressView.tscn` and `UI_Comp_WeekAfternoonCard.tscn` set it
per label (the afternoon card's head is a key, and it is instanced under the screen, so the screen root must not
disable translation). The old `season.week_evening_card.*` · `season.week.evening_*` · `season.week.sub_interview` /
`sub_outing` keys are `deprecated`.
§15 D: the afternoon texts say 방문 (visit) instead of 면담; new `season.week.afternoon_focus` / `afternoon_story` /
`afternoon_coach` · `season.week.sub_story_pm` · `season.week.sub_limit_break`; deprecated `season.week.slot_trust` ·
`season.week.outing_need_trust` (the afternoon card lost its pilot / buttons). The visit popup's texts are
`mental.ui.visit.*` (mental domain); `VisitMenu` and its item scenes are all code-filled (`auto_translate_mode = 2` on the root).
