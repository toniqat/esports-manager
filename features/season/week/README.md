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
| `WeekDayTrack.gd` | `class_name WeekDayTrack extends Control` — `_draw` widget of the day progress bar (`%DayTrack`): thin line + 7 circles at the centres of 7 equal cells, filled left → right up to `progress` (circle index, fractions while sliding), `today` = the larger circle with a white core; `dot_x(i)` |
| `WeekBannerStreak.gdshader` | Canvas shader on the top `%TeamBanner`: the right 30 % (`fade_from` 0.7) dissolves into transparency through coarse horizontal fBm streaks (the `ScenarioWipe` look, still). Uses the node-local vertex position, so it works on the banner's cropped `draw_texture_rect_region`; `rect_size` set by code |
| `base_map/` | `BaseMap` widget + one `UI_Comp_BaseMap_<Name>.tscn` per team base map (art + spot markers) + the weekend `UI_Comp_BaseMap_Stadium.tscn`. See `base_map/README.md` |
| `UI_Comp_WeekMapSection.tscn` | The map slot (fills `%MapPin`, full screen width): `%MapHolder` (plain Control) that receives the team's `BaseMap` / the stadium via `BaseMap.mount` (1200 × 761, centred, 60 px cropped each side). No caption and no facility research bubbles on this screen (both removed 2026-10; the hub keeps the bubbles) |
| `UI_Comp_WeekMapPilot.tscn` | One pilot token on the map, 92 × 92, **portrait only** (`%Portrait` slot 84 · `%Mask` black circle over the portrait; the stress / trust gauges moved to the pilot cards under the map 2026-10) · morning speech bubble `%Bubble` / `%BubbleText` + `%BubbleTail` · afternoon away chip `%Away` / `%Name` over the portrait top · rising result texts `%Floats` with the `%FloatLine` template · `%Hit` over the whole token · the portrait disc, black outline, tail and shadow are not in the scene — `BaseMap` draws them under the token, `base_map/README.md`). No name, no role badge |
| `WeekFade.gd` | `class_name WeekFade` (static): **fade through black** — `through(mid)` fades a full-screen black (own `CanvasLayer` 90 under the root, survives the view being hidden / rebuilt) in, runs `mid`, fades out; `clear_delay()` = seconds until the screen is clear (animations started in `mid` wait for it). Used for every dialog / awakening open and close, the visit result close and every move to the next half / day |
| `UI_Comp_WeekMatchCard.tscn` | Item: one match of the match day (`%Tag` · `%Title` · `%Status` · `%Hint`) |
| `UI_Comp_WeekNoteCard.tscn` | Item: one-line placeholder card (`%Text`) |
| `UI_Comp_WeekIncidentCard.tscn` | Item: the day's incident (`%Portrait` slot · `%Head` · `%Line` · `%Hit`) |
| `UI_Comp_WeekAfternoonCard.tscn` | Item: 오후 before the visit — `PanelContainer` (Card, height = content) ─ Box VBox: Head · `%Hint` (only when nobody can be visited) · `%Coach` (coach points left / weekly grant). The "tap a pilot on the map …" instruction was removed 2026-10 |
| `VisitMenu.gd` | `class_name VisitMenu extends CanvasLayer` — the afternoon **visit (방문)** popup (the morning talk bubble `open_talk` was deleted 2026-10 with the talk), two surfaces: the **menu** as a **speech bubble over the visited pilot's token** (only the options 집중 훈련 / 이야기 / 외출), and the **focus training modal** centred in the safe area over a dim (courses → result; the bubble hides, Back on the courses page returns to the bubble). `point_at(portrait, token)` gives the bubble's target; `_place_bubble` (every frame while the menu page is open, only on change) puts the bubble above the portrait with the tail down, else under the token with the tail flipped up, else on the roomier side clamped into the safe area (tail hidden if it would cover the token); x centred on the token, clamped into the safe area. The result page has no caption: its `EventResultPanel` comes first, the pilot portrait half over the card's top edge (no names). It hosts an `EventResultPanel` (`show_result(state, notes)` takes the outcome's **note dicts**, right after they were applied: bars before → after + stat chips). Draws and emits only (`option_picked` · `course_picked` · `closed`); `create()`, `point_at` / `open_menu` / `show_courses` / `show_result`. F6 preview = the menu of my first visitable pilot (visit recorded in memory), centred, no tail; 집중 훈련 → courses → a real `finish_focus` result |
| `UI_View_VisitMenu.tscn` | Its scene (layer 20): `Root` full rect STOP (swallows other taps) → `%Bubble` (`VisitMenuBubble`, 840 wide): VBox sep 16 — `%Header` (`%Portrait` 80 · `%Name` · `%PilotLine` · `%Coach`) · `%Caption` · `%Options` (`%Focus` / `%Story` / `%Outing` `SelectableCardButton`s; the talk page's `%Talk` button was deleted 104 high with title + note); `%Tail` (Node2D, `Edge` + `Fill` triangles); `%Modal` (hidden; `Dim` `DimPanel` + `%Safe` CenterContainer inset to the safe area → `Card` `PopupCard` 920 wide: `%ModalHeader` (courses page only: `%ModalPortrait` · `%ModalName` · `%ModalPilotLine` · `%ModalCoach`) · `%ModalCaption` · `%Courses` · `%EventResultPanel_Result` (`UI_Comp_EventResultPanel`) · `Buttons` (`%Back` · `%Confirm`)) |
| `UI_Comp_VisitCourseRow.tscn` | Item of the menu (no script): one focus course, 96 high (`%Name` · `%Stats` · `%Cost` · `%Reason`; picked = `SelectableCardButtonOn`) |
| `UI_Comp_WeekAfternoonDoneCard.tscn` | Item: 오후 summary after the action (`%Portrait` · `%Head` · `%Line`) |
| *(shared)* `../UI_Comp_SeasonPilotCard.tscn` | The five pilot cards of `%PilotRow` (`features/season/README.md` "Pilot card · detail sheet") |

The per-pilot training result cards (`WeekPilotCard` + `WeekStatCell`, six short-named stat columns) were deleted
(2026-10): the day's results now rise over the map portraits and the stress change sits on the pilot cards under the map.

The morning talk (훈련 소감) was deleted 2026-10 entirely — card, talk bubble, `Stage.TALK`, its skip warning and its
events (`features/season/mental/README.md`): the morning settles by itself and the afternoon follows the result FX.

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
  ├ TopBar      full width, y 16 … 128
  │ ├ %TeamBanner   TeamBanner (match_prep `_draw` widget) x 0 … 540 (= the screen centre on the 1080 design),
  │ │               my team's banner; material = WeekBannerStreak.gdshader (right 30 % streak dissolve, code)
  │ ├ %TeamLogo     TextureRect 88², x 28, centred on the bar
  │ └ Wallet (HBox, right, x −516 … −24, sep 12, align End)
  │   ├ %LobbyCurrencyPill_Budget  (meta/lobby pill scene, 240 × 64, mouse Ignore) icon team_budget.svg · team budget
  │   └ %LobbyCurrencyPill_Coach   (same, 240 × 64) icon coach_points.svg · coach points left this week
  ├ %DayTrack   WeekDayTrack, x 72 … −72, y 140 … 176: line + 7 circles (Mon → Sun)
  ├ %DayAbbrs   HBox, same x span, y 178 … 202: Day0…Day6 (CenterContainer, equal share) ─ Abbr (CaptionLabel 18,
  │             today BodyLabel; code-filled MON … SUN)
  ├ %DayBubble  Panel `WeekDayChipToday` (amber) 120 × 74 at y 216, x by code (centred under today's circle):
  │             BubbleTail (Polygon2D, tail up, ACCENT) · Box VBox ─ DayTag (16, key `season.week.rail_day` "DAY")
  │             · %DayNum (36, day inside the phase)
  ├ %Phase (CaptionLabel 26, centred, x 40 … −40, y 296 … 330)  ← phase name only
  ├ %TimeRow    x 40 … −40, y 326 … 398, clips: %TimePrev · %TimeNow · %TimeNext (TitleLabel 52, 320 wide, centre
  │             anchored, 300 apart; the sides scale 0.55 + alpha 0.45) — half of the day, see "Time row"
  ├ %MapPin     full width, centred on the safe area's height **+ 70** (anchors 0.5, −310 … 451 = 761 map height),
  │             hidden by default: fixed slot for the map (WeekMapSection)
  ├ %Scroll     x 40 … −40, y 410 … (centre − 324 = map top − 14), anchors_preset −1 (grows right only): the card
  │             list **above the map**
  │ └ %List     VBox, separation 14 (card gap) — item scenes + %ListEnd (kept last = gap under the last card)
  ├ %PilotBanner TeamBanner, full width (edge to edge), centre + 465 … 755: my team's banner as the strap behind the cards
  ├ %PilotRow   HBox sep 12, x 40 … −40, centre + 465 … 755 (map bottom + 14, 290 tall): SeasonPilotCard_Pilot0..4
  │             (seat order, `set_week_layout()`), **always shown**
  └ %Bar        HBox capsule row, sep 16, align End, y −128 … −32, 40 side insets — code: `OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)`
    └ %FloatingBarButton_Action BarPrimaryButton, 262 wide (40 % of the old 2/3 slot), shrink-end = right
                                (다음 / 확인 / 기자회견 / 주 마감 →); `BarDarkButton` for 경기 준비 / 경기 시작 + `fit_bar_button`
```

The old dark weekday rail (`Rail` · `%DayHighlight` · seven `WeekDayChip` chips with numbers) and the bar's stage
label (`%FloatingBarButton_Stage`, 오전 / 오후 / 저녁) were deleted 2026-10: the day bar + DAY bubble and the time row
say the same.

* **Scene owns**: every position / size, fonts (variations + size overrides), the DAY bubble (screen variation,
  no local StyleBoxes), button kinds of the afternoon card, the map section / token layout, sample texts. Spot
  positions are the `Spot_*` markers of each base map scene.
* **Code owns** (data / device dependent): the weekday abbreviations (today's in `BodyLabel`), the day bar's
  fill / today and the DAY bubble's x and number, the team banners / logo / pill values and the streak material,
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
[▓▓ LOGO  banner ▓▓░░ ]        [💵  12,300][📯     6]   ← team banner (to the centre) · budget · coach points
   ●━━━━━●━━━━━◉─────○─────○─────○─────○                ← day bar: filled up to today
  MON   TUE   WED   THU   FRI   SAT   SUN
              [DAY 3]                                   ← bubble under today, tail up
                 프리시즌                                ← phase name, centred
         오전      오후      저녁                        ← time row: previous (small) · NOW (big) · next (small)
  ▌(○) 오후                                             ← afternoon card, then incident (scroll, above the map)
[   team base map 1200 wide, five pilot tokens   ]     ← %MapPin; 60 px cropped each side
[▓▓▓[TOP][JGL][MID][ADC][SUP]▓▓▓]                      ← team banner strap + five pilot cards
                                     [   다음   ]
```

(Mockup uses in-game Korean text: "프리시즌" = Preseason, 오후 = afternoon,
`다음` = Next.)

* **Top bar** (`_refresh_top_bar`, every redraw): `%TeamBanner` / `%PilotBanner` = `TeamLogos.banner` + `TeamLogos.color`
  of `player_team_id`, `%TeamLogo` = `TeamLogos.texture`; budget = `FinanceSystem.fmt(FinanceSystem.balance)`,
  coach points = `StaffSystem.coach_points` (the afternoon card still shows `n / weekly grant`). The pills are the
  lobby wallet pill (`features/meta/lobby/UI_Comp_LobbyCurrencyPill.tscn`) with its `%Icon` replaced and mouse Ignore —
  no shop here. The streak material is made on first draw and gets `rect_size` on every resize (`_fit_streak`).
* **Day bar animation** (`_refresh_rail`, static `_rail_memory` = the last `{week, day}`): on a new day of the same week
  the fill runs from the last shown circle to today's and the DAY bubble slides with it (`RAIL_SLIDE` 0.55 s, after
  `WeekFade.clear_delay()`); other redraws place everything at once. Circles up to today are filled amber, later ones
  are white with a grey ring.
* **Time row** (`_refresh_time_row`, static `_half_memory`): `%TimeNow` = the half of the day (`_stage_half`: 오전 = the
  morning stages and the weekend stadium, 오후 = afternoon / press, 저녁 = evening), `%TimePrev` = the half before (hidden
  in the morning), `%TimeNext` = the half after (after 저녁 the next 오전). When the day moved on by one half (evening →
  next morning included) the row shifts left over `TIME_SHIFT`: the old previous slides out left and fades, the current
  shrinks into the previous slot and dims, the next grows into the centre, a new next fades in from the right.
* **Header** (below the bubble) — the **phase name only**, centred (`GameEnums.phase_label`).
* **Body** — the card list, vertical scroll (`%Scroll`, drag-scrolled by `DragScroll.attach` in `_ready`) between the
  time row and the map; the map sits 70 px under the safe area's centre (`%MapPin`), the pilot cards (`%PilotRow`) under it.
* **Bottom bar**: one short capsule at the right: `다음` (Next) on every stage, **`경기 준비`** (Match prep, Saturday
  stadium) / **`경기 시작`** (Start match, Sunday stadium) in the dark fill ("you are leaving this screen"), `기자회견`
  (Press conference, Sunday afternoon, `term.activity.press`), `주 마감 →` (End of week) on the Sunday evening,
  `확인` (OK) on a day without any stage.

## What each weekday does

| Weekday | What happens |
|---|---|
| 월~금 (Mon–Fri) | **Training days**: 오전 (training: settles by itself, results rise) → 오후 (afternoon) → 저녁 (evening incident), see "Training day: morning → afternoon → evening". The settlement is `TrainingBoard.apply_day_training(day)`, which settles that row of the board and actually raises player stats. |
| 토 (Sat) | **Prep day**: `STADIUM` (stadium map, "경기 준비" → MatchFlow PREP + BAN_PICK, picks stored) → `AFTERNOON` → `EVENING` on the team map, **no training**. Sunday's matches show as cards while the prep is open. |
| 일 (Sun) | **Match day** (`CalendarSystem.MATCH_DAY`): `STADIUM` ("경기 시작" → BattleSim with the Saturday picks) → standings → `PRESS` (stadium map, "기자회견") → `AFTERNOON` (team map, visit — the story is about the match) → `EVENING` (incident) → "주 마감 →". The day's matches show as cards. |

### Training day: morning → afternoon → evening (base map)

**Time passing on the map** (`_animate_map`, after every map build): each stage has an hour (`_stage_hour`: MORNING 8 ·
RESULT 9.5 · AFTERNOON 15 · EVENING 18.5 · STADIUM Sat 10 / Sun 13 · PRESS 16.5). The last drawn map is kept
in the static `_map_memory` (`{scene, day, stage, hour, tokens}`, survives the view being re-made per day). When the day
or the stage changed since then, the map's clock runs from the old hour to the new one (`STAGE_TIME` 1.4 s; a new day
runs through the night, `NIGHT_TIME` 2.8 s) and, on the same map scene, my pilots walk the roads from where they stood
(`BaseMap.walk_from`, keyed by pilot id; on a new day in the night's second half, `NIGHT_WALK_DELAY`). A redraw of the
same stage just sets the hour. A tap on the map while it moves skips to the end (`_input`). Lighting / roads:
`base_map/README.md` "Time of day", "Roads and walking".

A training day runs in four stages (`WeekProgressView.Stage`). The stage is **read from the records**, not
stored on its own (`_stage`), so re-entering the day (after a match, after a reload) lands on the same stage:

| Stage | Record | Map | Next (다음) |
|---|---|---|---|
| `MORNING` | no `week_day_log[day]` | each pilot on the spot of **that day's training facility** (`TrainingBoard.day_groups` `facility` → `BaseMap.spot_of_facility`: the tile's `facility` column, else the colour of its first cell that day, so a joint-training group shares one spot; no tile = basic course = neutral `W`); a **speech bubble** over the portrait names the training (`TrainingBoard.day_tile_names`). **Settles by itself** after `MORNING_HOLD` (1.2 s, + the clear delay of a fade, + `NIGHT_TIME` while the map still runs the night: `_hold_morning`, a ticket counter drops stale timers; nothing settles while a popup / awakening is open — its close redraws and re-arms the timer) | settles now (`_settle_day` → `apply_day_training`) |
| `RESULT` | `week_day_log[day]` set, no afternoon record | same spots, no bubble; **result FX** (`_play_result_fx`): per pilot, lines rise out of the portrait top and fade (`FX_RISE` / `FX_TIME`, `FX_STAGGER` between lines, `FX_PILOT_STAGGER` between pilots): stat ups by **full name** (`전장 명중 +1`, else `EXP +N`), `스트레스 ±N`, quirk events; the pilot cards' stress change pops (`pulse_note`). When the FX ends (`_finish_result_fx` → `_fx_done_day`) a queued awakening opens first, then the **afternoon starts by itself** through black (`_next_auto` → `Auto.AFTERNOON` → `AfternoonAway.begin`) | skips the rest of the FX (same `_finish_result_fx`) |
| `AFTERNOON` | `AfternoonAway.started`, no `dusk` | resting pilots on `Dorm`, pilots out alone on `Entrance`, **everyone else on a random spot** of the map (`_wander_spot`: `BaseMap.wander_spots` = every `Spot_*` but Dorm / Entrance — colour + facility markers, one per point; seeded by week key · day · pilot, so a reload / the evening keeps it; pilots walk there from the morning spots); anyone who cannot be visited is masked black and not tappable (`AfternoonAway.can_request`), except the pilot whose visit is under way (scaled up). Tap = visit (`VisitMenu`); once the visit is used every token is masked | evening (`_begin_evening`: pass if unused, `MentalSystem.begin_dusk` rolls the incident; **no incident and no limit-break event = straight to the next day**, except Sunday, which stops on its evening for "주 마감 →"); while a visit is still possible (`AfternoonAway.any_request`) a **warning** `ConfirmPopup` asks first, confirm = pass |
| `EVENING` | `MentalSystem.dusk_started` | afternoon positions (same seed), nobody tappable, every token masked; the limit-break event (§15 B) then the incident open by themselves | next day (`on_week_day_confirmed`) |

* **Map**: the team's base map (`RunRules.team_map_id(player_team_id)` = `teams.csv` `map_id` → `BaseMap.create`),
  pinned in `%MapPin` above the pilot cards and the scrolling list. Spots per colour group, the 1.2× scale / crop
  and the line-up of tokens sharing a spot: `base_map/README.md`. There is no caption over the map (the old `%Hint`
  "what Next does now" line was removed 2026-10) and no facility research bubbles (hub only).
* **Pilot cards under the map** (`%PilotRow`, every day, both halves): `SeasonPilotCard` × 5 in seat order (portrait in the 깨달음 level ring, the two stress · trust gauges, no role badge, no card background); each gauge shows
  **the day's change** (`SeasonPilotCard.set_day_deltas`: ring segment from the value before + `+N` stress / `+N%` trust (no brackets)
  under the value, nothing at 0; they pop when the result FX starts), and the portrait ring shows the day's level EXP as a
  light segment. `_day_delta(pid, kind)` (kind `stress` · `trust` · `tlexp`) = training row `stress` / `tlexp` + self-outing relief (stress) + `kind` / `<kind>_all` notes of the
  day's incident / afternoon (visit · evening) outcomes. Not counted (not in the day record): the Sunday press answer,
  the match's level EXP; `<kind>_all` notes are nominal (unclamped). Tap = `SeasonPilotDetail` sheet.
* **Moving on by itself** (`_next_auto` → `_run_auto`, always through black, `WeekFade`): once nothing is open or queued
  (dialog, visit popup, result FX, awakening, limit-break event, incident) — the result FX ended → afternoon; the
  visit settled (story / outing answered, focus result confirmed) → evening; the evening's events settled → next day
  (Mon–Sat; the Sunday keeps "주 마감 →"; not without the hub). Checked when a dialog / the visit result / an awakening
  closes (inside its closing fade) and after every redraw (`_open_pending`), so a reload on a finished half moves on too.
  **다음** stays as the skip (warning while an action is still possible) and also fades.
* **Fades** (`WeekFade.through`): every dialog (story, outing, limit break, incident) and the awakening view open
  and close through black; the moves to the next half / day too. The map's clock and walks, the day bar and the time row
  start under the black and run as it clears.
* A reload between the settlement and the afternoon lands on `RESULT`: the FX plays again, then the afternoon starts.
* **Autosave** (`_save` → `SeasonHub.autosave`): after the settlement, the afternoon, the incident roll, the visit (`visit`), a story / outing, a focus course (`focus`), an awakening / limit break and
  every answer — closing the game mid-week resumes on this screen at
  the same stage (`features/save_load/README.md`).
* **Afternoon away states** (rules and record: `features/season/mental/README.md` "Afternoon away states"):
  a stressed pilot may go out alone, otherwise any pilot may stay in the dorm by chance (rolled once, recorded).
  An empty training cell is the basic course, not a rest.
* Old saves with a morning-talk record (`days["<day>"].talk`) ignore it: `RESULT` replays the FX, then the afternoon.

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

### Mon–Fri: 오후 (afternoon) card + incident card (M7)

Rules and state are in `features/season/mental/README.md` (`MentalSystem`); this screen only draws
records and forwards taps. On a training day the list order is **(pinned map) → afternoon → incident**.

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
  a visit menu / afternoon dialog left open → a queued **awakening** (§15 C) → at the evening the
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
* **Awakening** (`_open_awakening`): after every redraw (morning settlement once its result FX has ended — before the afternoon, every
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

The afternoon action, the incident and the afternoon away states follow the same rule with their own
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
keys are `season.week.stage.*` (time row) · `season.week.map.*` · `season.week.afternoon_*` · `season.week.skip.*`;
weekend: `season.week.btn_match_prep` · `season.week.hint_prep` · `season.week.hint_match_ready`; the press button
reuses `term.activity.press`; day bar: `season.week.rail_day` (scene, the bubble's "DAY") · `term.day.abbr.*`). The
pills show numbers only (no text). **Deleted 2026-10** (rows removed): the morning talk's `season.week.talk_*` ·
`season.week.sub_talk` · `season.week.skip_talk.*` (and `mental.ui.mod_source.talk`); earlier: `season.week.map_hint.*`
(the map caption), `season.week.date`, `season.week.day_count`, `season.week.afternoon_pick` / `talk_pick`.
Bubble texts are training tile names (data). Deprecated 2026-10:
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
