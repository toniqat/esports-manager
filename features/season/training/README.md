# Daily training (일상 훈련) (tile placement board)

Players' training is planned by **slotting course tiles into a 5-column (player) × 5-row (one per
day) board**. It ports the routine training board of the original game (Esports Godfather). The
analysis doc of the original's 87 tiles was deleted; it remains in `docs/routine.md` at git
`bc52878`.

**Each board row is labelled with its weekday (월 화 수 목 금) on the left.** An earlier version
removed these labels (the five rows were meant to read as a routine, not a timetable), but the board
is settled **one row per weekday** (`apply_day_training`, run by the week-progress screen
(시간 경과 화면, `features/season/week/`)), and day-scoped clauses (`day_next` · `day_prev_all` …)
only make sense if you can see which row is which day — so they are back. The labels are **scene
text** (`DayLabels` in `UI_View_TrainingView.tscn`, the shared `term.day.short.*` keys behind
`OutgameTheme.DAY_LETTERS`; no script touches them), and an equally wide **empty right gutter**
mirrors the label column so the board stays horizontally centred. The word "주간" (weekly) is still
not shown on this screen.

## Files
| File | Role |
|---|---|
| `TrainingTile.gd` | `class_name TrainingTile` — one CSV row = one tile. **Grammar parsing lives only here** (shape · colour · EXP · effect clauses · quirk ops). Also owns the colour table · grade table and the training-stat EXP multiplier (`training_exp_mult`, see "Training stat — per facility" below). `line` = the tile's upgrade line. |
| `TrainingCourses.gd` | `class_name TrainingCourses` — static, **the run's owned courses** (`season_state["training_courses"]`): `new_inventory` · `inventory` · `owned_count` · `owned_tile_ids` · `filler_tile_id` · `grant` (upgrade rule — called by the training facilities' research, `TrainingResearch.on_complete`) · `grant_all` (previews). See "Owned courses" below. |
| `TrainingBoard.gd` | `class_name TrainingBoard` — headless board. Per-facility training stat (`facility_stat` / `facility_exp_mult` / `cell_facilities` / `shared_exp_mult` / `cell_team_mult`), ownership (`owned_tiles` / `owned_count` / `placed_count` / `can_take_more` / `filler_tile_id`), placement checks (`can_place` / `place` / `remove_at`), settlement (`cell_exp` / `exp_mult_table` / `compute_gains` / `compute_day_gains`), quirk ops (`day_quirk_ops`), per-day cell colours (`day_colors`, read by the week screen's base map) and training names (`day_tile_names`, empty cell = basic course; the week screen's morning speech bubbles), **weekday application** (`apply_day_training`), preview (`projected_stats`), auto-arrange (`auto_arrange`), week-progress reset (`reset_week_progress`). The `TrainingBoard` node in Season.tscn. |
| `TrainingView.gd` · `UI_View_TrainingView.tscn` | Planning screen — staff line + 5 portraits + 5×5 board + horizontally scrolling course cards + bottom bar ("판 비우기" · "코치 추천" · "훈련 확정"). Drag & drop. **The frame is the scene** (see "Scene tree" below); the script binds `%` nodes, fills data, applies the safe-area insets, and owns the drawn board + drag & drop. Created with `TrainingView.create()` (`SeasonHub._ensure_training_view`). Layout · reading conventions are in "Screen layout" below. |
| `TrainingLevel.gd` | `class_name TrainingLevel` — static, **run-only 깨달음 레벨** 1..`TLEVEL_MAX` + its EXP bar (`season_state.training_level`): level-ups queue awakenings, even levels lock the bar, old-save migration. See "깨달음 레벨 · limit break" below. |
| `LimitBreak.gd` | `class_name LimitBreak` — static, **limit break (한계돌파)**: due-event check, VN session dict, goal pool / offer / pick, goal judging on my matches, `complete` (stats up, bar unlocked, level unchanged), result notes. See below. |
| `LimitBreakDemo.gd` · `UI_View_LimitBreakDemo.tscn` | `class_name LimitBreakDemo` — **dev harness, F6 only** (never instanced by the game): plays the limit-break dialogue in a `VnDialogueView` on an in-memory run with exactly the calls the week screen uses (`play(state, day)`). |
| `UI_Comp_TrainingThumb.tscn` | One portrait column header (frame · face · per-pilot `EXP ×r` chip · §15 `LvN` training-level chip (`%LevelChip`, top-left) · `%Hit` tap target). No script — `TrainingView._bind_thumbs` sets the role border colour and wires `%Hit` → `SeasonPilotDetail.open` (pilot detail sheet, `features/season/README.md`); five instances sit in `UI_View_TrainingView.tscn`. |
| `TrainingCourseCard.gd` · `.tscn` | `class_name TrainingCourseCard` — one course card of the inventory row (grade band · placed/owned · shape well · name). `fill(tile, cap, locked)`, `set_selected(selected, locked)`; the shape miniature is drawn into `%Mini` (`_draw_mini`). |
| `TrainingCoursePopover.gd` · `.tscn` | `class_name TrainingCoursePopover` — the info popover over a selected card. `fill(tile, cap)` sets the text and **derives the height from the text** (`_text_height`); `TrainingView._place_popover` positions it. |

**F6 preview** — each scene with a script fills dummy data when run alone (`resources/UiPreview.gd`);
`UI_View_LimitBreakDemo` = the first pilot's bar filled on Monday, then the limit-break dialogue (pick a goal → reply → result chip):
`TrainingView` = in-memory run + preview-only `TrainingBoard` child, two copies of every course (`TrainingCourses.grant_all`), coach auto-arrange, third course card
selected with its popover; `TrainingCourseCard` / `TrainingCoursePopover` = hand-written grade-3 tiles
(card selected; popover).

## 깨달음 레벨 · limit break (§15 B + C merged — `TrainingLevel` · `LimitBreak`)
Contract: `docs/outgame_dev_plan.md` §15.0 "2026-10-09 decision" (overrides §15.0 B / C) / §15.1. Numbers are
the `TLEVEL_*` / `LIMIT_BREAK_*` / `LEVEL_EXP_PER_AWAKEN` keys of `data/csv/const.csv` — this README names keys
only. Run-only: nothing reaches the profile. The code name stays `TrainingLevel`; the screen calls it 깨달음 레벨.

**Rules** — one level per pilot, Lv1 at run start, bar = `TLEVEL_EXP_<level>`:
- A full bar = **level + 1 at once** and **one awakening queued** (`Awakening.queue` → the week screen opens
  `AwakeningView`, `features/season/awakening/README.md`). EXP past the bar carries into the next one.
- **Reaching an even level below the cap locks the bar** (`awaiting_break`): EXP stops (the rest of that add is
  lost) until the limit break succeeds — then all six stats + `LIMIT_BREAK_STAT_GAIN` and the bar opens; the
  level stays (`break_done`). The bar after it is the same level's `TLEVEL_EXP_<level>`.
- Lv `TLEVEL_MAX` = no EXP, no awakening, no limit break.

API (UI reads these): `level` · `has_level` · `exp_of` (0 while locked) · `exp_need` · `need_for_level` ·
`progress` (0..1, 1 when locked / max) · `is_max` · `is_capped` (locked or max) · `awaiting_break` (locked, limit
break due) · `is_lock_level(lv)` · `add_exp(state, pid, amount, source := "")` → applied EXP · `exp_of_awaken(points)`
(old gauge points → EXP) · `break_done` (LimitBreak only) · `chip_text`.

**State** — `season_state.training_level = {"<pid>": entry}` for my five pilots (string keys, JSON round trip via
`SaveSystem`; a run saved before §15 gets Lv1 entries on first read, `TrainingLevel.ensure`):
```
entry = {"v": 2, "level": 1..TLEVEL_MAX, "exp": int (inside the level),
         "broken": bool,                                 # limit break of this even level done (bar open)
         "offer": [goal id ×LIMIT_BREAK_OFFER],          # drawn once per limit break, kept until a pick
         "goal":  {} | {"id", "since_match", "set_week", "set_day", "recs": [match record…]},
         "event_week": MentalSystem.week_key, "event_day": 0..6 (-1 = none),   # when the even level was reached
         "event": "" | Draft dialogue row id (mental_events, kind limit_break),
         "note":  {} | {"pilot_id", "level", "goal", "source": "goal"|"focus", "gain", "week", "day", "seen"}}
match record = {"k", "d", "a", "obj" (objectives within LIMIT_BREAK_OBJ_TURN), "mvp",
                "top_kills", "top_score", "top_turret", "top_care"}   # last LIMIT_BREAK_WINDOW kept
```

**Old saves** (`TrainingLevel._migrate`, once per entry without `"v": 2`, on the first `ensure`): the level number
is kept; an even level counts as already broken (`broken = true`); a **full bar** (the old "limit break due")
becomes a level-up — level + 1, empty bar, one awakening queued — and landing on an even level locks it and keeps
the old `goal` / `offer` / `event` / event stamp as that level's limit break (landing on an odd level clears them).
The old awakening gauge `season_state.awakening` is dropped (points not converted; queued awakenings stay).

**EXP sources** — `add_exp` is the single entry point:
- training: `apply_day_training` → `TrainingLevel.on_training_day(state, rows)`: the sum of the row's `exp` (stat
  EXP earned that day; stat growth itself unchanged); writes the applied EXP back as `row.tlexp` and the levels
  gained as `row.level_up` (week screen day deltas);
- visit focus training / story `tlexp:N` / `train_bonus` clauses (`FocusTraining.add_training_exp`, `tlexp` note);
- old awakening sources, × `LEVEL_EXP_PER_AWAKEN` per point: matches (`Awakening.on_match`, `AWAKEN_MATCH_*`,
  applied EXP in `pending_match.level_exp_gains`), story / incident `awaken:+N` clauses, focus training
  `FOCUS_AWAKEN`.
Reaching an even level stamps `event_week` / `event_day` = this week, `season_state.week_day`.

**Limit-break event** — `LimitBreak.pending_event(state, day)` returns the first pilot (seat order) whose bar is
locked at an even level, who has no goal yet, and who reached that level on `day` or earlier (an earlier week counts:
"the next evening the week screen reaches"); -1 = none. It keeps returning that pilot until the dialogue is
answered (`choose_goal`), then the next due pilot. Lv `TLEVEL_MAX` = no EXP, no event.

**Dialogue** — `session(state, pid)` → `{kind: "limit_break", event, pilot_id, partner_id: -1, tag, sub, title,
lines, choices, previews}` (the `MentalSystem.session_view` shape + `sub` / `title` for `VnDialogueView.open`).
- **Lines** are authored in **Draft** (`narrative/`, kind `limit_break`, flows `LB01` (cond `tlevel=2`, the first
  lock) and `LB02` (`tlevel>=4`, "stuck again" — covers the locks at 4 · 6 · 8); convention in `narrative/README.md`) and imported like every mental event.
  `event_row(state, pid)` draws one row among those whose cond holds (`MentalEvents.cond_ok`, new cond token
  `tlevel`), weighted and seeded, and keeps its id in `entry.event` until the limit break completes. Lines =
  that row's `line` texts (`MentalEvents.text`, markers `*` / `>` kept). The flow's Select has **one
  placeholder option** (never shown); its replies are the pilot's **closing reply** after the pick.
- **Choices** are UI text, not Draft: the 3 offered goal names with live numbers (`training.limit_break.goal.*`,
  placeholders `{n}` window · `{kda}` `LIMIT_BREAK_KDA` · `{turn}` `LIMIT_BREAK_OBJ_TURN` · `{need}`
  `LIMIT_BREAK_OBJ_NEED`); previews = "달성 시 모든 스탯 +gain · 깨달음 레벨 막대 다시 열림".
- `choose_goal(state, pid, idx)` stores the goal and returns the `show_result` view (`{checked: false, ok: true,
  say: [closing reply lines], notes: ["새 목표: …"]}`); idempotent. No Draft row imported → no lines / reply,
  the choices still work.
- Draws (offer, dialogue row) are seeded by `run_seed` · pilot · level · purpose, like `MentalSystem._seed`.

Week-screen call sequence (agent D, `WeekProgressView` evening, before the incident; `LimitBreakDemo.play`
is the reference):
```
var pid := LimitBreak.pending_event(state, day)     # -1 → go on to the incident
var v := LimitBreak.session(state, pid)
vn.open(v.sub, v.title, pid, v.lines, v.choices, "", v.previews)
vn.choice_picked → vn.show_result(LimitBreak.choose_goal(state, pid, idx))
vn.closed → pending_event again (next due pilot), then the incident
```

**Goal pool** (`LimitBreak.GOALS`, position filter by `GameEnums.Role`; window = `LIMIT_BREAK_WINDOW`, MVP
`LIMIT_BREAK_WINDOW_MVP`):

| id | Goal | Who |
|---|---|---|
| `kda` | window sum `(k + a) / max(d, 1)` ≥ `LIMIT_BREAK_KDA` | all |
| `kills` | kills rank 1 in the game, each match | not support |
| `obj` | objectives taken by turn `LIMIT_BREAK_OBJ_TURN`, window sum ≥ `LIMIT_BREAK_OBJ_NEED` | jungle, mid |
| `mvp` | match MVP (`pending_match.mvp_pilot_id`) | all |
| `score` | score earned rank 1, each match | not support |
| `turret` | turret damage rank 1, each match | not support, not jungle |
| `care` | `care` (shield absorbed + healing) rank 1, each match | support |

"Rank 1 in the game" = the highest value among all ten `pilot_stats` rows (both teams); **ties count as rank 1**,
but a value of 0 is never rank 1 (a game where nobody scored does not hand out the goal). Counters:
`features/battle_sim/combat/README.md` "Match stats".

**Judging** — `LimitBreak.record_match(state, pending_match)` (SeasonHub, after `RunStats.record_match`;
idempotent via `pending_match.limit_break_recorded`): for every pilot with a goal who played (a `side == 0` row),
append that match's record, keep the last `LIMIT_BREAK_WINDOW`, and when the window is full and meets the goal
(**sliding window** — an early bad match drops out) call `complete(state, pid, "goal")`. A match the pilot did
not play is skipped (no reset). Progress text: `goal_text` = "목표 — {goal} ({progress})", progress = trailing
rank-1 streak `n/2`, objective sum `n/3`, MVP `0/1`, or the window KDA `KDA 2.5 / 4`.

**Completion** — `complete(state, pid, source := "focus")` (goal met, or the visit's 한계돌파 focus training, D):
`TrainingLevel.break_done` (bar unlocked, EXP 0, **level unchanged**), goal / offer cleared, every one of the six
stats of the run pilot (`season_state.all_pilots`) `+ LIMIT_BREAK_STAT_GAIN`. Returns the **result note** (`level` =
the unchanged level) and keeps it in `entry.note` (`seen: false`); `unseen_notes(state)` / `mark_note_seen(state,
pid)` / `note_text(state, note)` ("{name} 한계돌파 성공 · 깨달음 레벨 Lv2 · 모든 스탯 +3") let the week screen / hub
announce it once. No-op ({}) when no limit break is due. SeasonHub judges goals **before** the match's level EXP
lands, so a goal met in that match unlocks the bar first.

**Display** — training-board portraits: `LvN` chip (dark rail, **accent** while the bar is locked / its goal
open, `TrainingView._refresh_level_chips`); hub / week card: the same chip on `SeasonPilotCard`; detail sheet:
level, EXP bar, goal line (`features/season/README.md` "Pilot card · detail sheet").

## Board axes
```
        탑    정글   미드   원딜   서폿      ← column = one player's week
  월  [    ][    ][    ][    ][    ]
  화  [    ][    ][    ][    ][    ]   ← row = the five players on the same weekday
  수  [    ][    ][    ][    ][    ]
  목  [    ][    ][    ][    ][    ]
  금  [    ][    ][    ][    ][    ]
```
(Columns: Top · Jungle · Mid · ADC · Support; rows: Mon–Fri.)

Column order is `GameEnums.ROLE_DISPLAY_ORDER` (the same table as the battlefield strip · hub roster
· ban/pick). **Sat·Sun are not on the board** — those two days are the match weekend, not training,
and the board size itself now does what the old 7-day grid's Fri·Sat·Sun MATCH lock used to do.
The `월` … `금` row labels in the diagram **are shown on screen** — a 60px label column left of the
board (`DayLabels`), with a matching 60px empty gutter on the right (see intro and "Screen layout").

The original has this axis **reversed** (rows are players, columns are periods). That's why effect
scope names are by **meaning** (`day_*` / `mate_*`), not up/down/left/right — written as directions,
every clause would become a lie each time the board is rotated.

## `data/csv/training_tiles.csv`
| Column | Meaning |
|---|---|
| `id` | `T01` … (text PK) |
| `grade` | 0=D 1=C 2=B 3=A 4=S |
| `line` | Optional upgrade line (`basic`, `field_hit`, `field_eva`, `engage_hit`, `engage_eva`, `atk_growth`, `hp_growth`). Empty = the tile is its own line. Levels of one line differ by `grade` and **must keep the same shape** (an upgrade rewrites placed tiles in place). Names carry the level as a Roman numeral (`기초 훈련 I` … `IV`, `사격 훈련 I` … `III`) |
| `shape` | Colour string with rows separated by `/`. **One row = one day, one character = one player.** `W`=1 cell, `WW`=two on the same weekday, `W/W`=one player for two days, `CC/DD`=two × two days, `WWWWW`=one day for all five |
| `exp` | `stat:value` joined by `\|`. `all:N` = all six stats. **Value given per cell**, so an n-cell tile gives n times |
| `effect` | Clauses joined by `;` |
| `facility` | Optional base-map spot where the course is held (`H E C D G M Q W`, `features/season/week/base_map/README.md`). Empty = the colour of the course's first cell on that day. Every pilot in one placed tile on a day stands there (joint training) |

**There is no `description` column.** There used to be one, and the info popover printed it
verbatim, but those sentences were hand-transcriptions of the `effect` clauses, so editing a clause's
number made only the description silently lie. Both lines of the popover are now built from tile
data — `TrainingTile.exp_summary()` (EXP) and `effect_summary()` (effect).

**l10n (design §6.1).** The tile name is a key: `training_tiles.name_key` (`training.tile.{id}.name`) →
`TrainingTile.name_key`; `tile_name` is a read-only computed property (`Loc.t(name_key)`). Both summaries are
built from **template keys**, never `+` concatenation: `training.exp.none` · `.quirk_day` ·
`.all {n}` · `.stat {stat} {n}` (items joined by `training.list_sep`), and
`training.effect.mult {scope} {pct}` · `.flat {scope} {stat} {amount}` · `.quirk {op}` (one line each) with
`training.stat.all`, `SCOPE_LABELS` (`training.scope.*`) and `QUIRK_OP_LABELS` (`training.quirk_op.*`) as
key-constant tables. Stat names still come from `PlayerData.STAT_LABELS`.

### Colour ↔ stat
Same order as `PlayerData.STAT_KEYS`.

| Symbol | Colour | Stat |
|---|---|---|
| `H` | Yellow | Battlefield (전장) hit (명중) `field_hit` |
| `E` | Blue | Battlefield evasion `field_eva` |
| `C` | Red | Engage (교전) hit `engage_hit` |
| `D` | Purple | Engage evasion `engage_eva` |
| `A` | Orange | Attack growth `atk_growth` |
| `P` | Green | HP growth `hp_growth` |
| `K` | Black | **0 EXP** — the self cell of an amplifier tile |
| `Q` | Pink | **Quirk** — 0 stat EXP; the tile's `quirk:*` clauses act on this cell's pilot (see "Quirk tiles") |
| `W` | Grey | Neutral — all six stats evenly |

Colour is currently only a display pairing with `exp`, but it is kept as the hook for the original's
conditional effects ("defence +40 per red in the same column") — `TrainingTile.cell_colors` already
holds per-cell colours, so only one clause needs adding.

### Effect clauses
```
mult:<scope>:<pct>            multiply cell EXP in that scope by pct% (100 = no change)
flat:<scope>:<stat>:<n>       add n stat EXP to cells in that scope
quirk:gain|reroll|slot        no scope — acts on the pilot of each Q cell (see "Quirk tiles")
```
| scope | Meaning |
|---|---|
| `self` | Own cell |
| `day_next` / `day_prev` | That player's next day / previous day, one cell |
| `day_all` | That player's whole week |
| `day_prev_all` / `day_next_all` | All of that player's earlier days / remaining days |
| `mate_left` / `mate_right` | The neighbouring player's same weekday |
| `mate_all` | All other players on that weekday |

On-screen wording comes from the single table `TrainingTile.SCOPE_LABELS` — scope → l10n key
(`training.scope.*`, e.g. `day_next` → "다음 날" (Next day), `mate_all` → "같은 날 다른 선수" (Other players, same day)). For the same reason
as clause names, it is written by **meaning, not direction** — rotate the board once and "the cell
above" becomes a lie.
`mult` shows the **difference** on screen (`<pct>` → `+(<pct> − 100)%`): since 100 is no change, what directly
answers "what does this clause change" is the difference from 100, not the raw pct.

**Cells covered by the tile itself are in no scope.** A clause that multiplies the tile itself is
just a value you could write as more EXP, and with multi-cell tiles one cell would multiply another,
creating self-amplification unrelated to placement.

## Settlement (`cell_exp` → `compute_gains` / `compute_day_gains`)
Three stages, and the key design point is that **order doesn't change the result**.

1. Lay down base EXP per cell. Empty cells are filled by the basic course at the owned level
   (`filler_tile_id()` → `TrainingCourses.filler_tile_id`, T01 · T02 · T22 · T23 = 기초 훈련 I~IV),
   so **"a board with nothing placed" and "a board plastered with basics" give the same result**.
2. Scan all clauses, building a **multiplier table** and an **additive table** separately.
   Multipliers stack multiplicatively (two multipliers a% and b% → a×b) — stacking additively would run away with
   just three amplifier tiles.
3. Apply both to each cell at once to **fix per-cell EXP** (`cell_exp`,
   `Vector2i(seat, day) → {stat: int}`). Multiplying in the same pass would make clause order change
   the result ("left cell ×m" followed by "that cell +n" leaves the n uncut).
   **Rounding also happens here, once per cell.**

Folding comes after that. `compute_gains()` sums all five rows per seat, `compute_day_gains(day)`
sums only that row. **Not recomputing just your own row** is the point — clause scopes cross weekdays
(`day_next` · `day_prev_all` · `mate_all`), so a multiplier that a Wednesday tile put on a Thursday
cell must still be alive when Thursday is settled. Building the cell table once for the whole board
and splitting only the folding means **the sum of the five weekdays cannot differ from a single
weekly settlement by even one EXP** (verified headless).

### EXP and the leftover bank
**EXP is not stat points** — a stat rises by 1 only once `EXP_PER_POINT` (const.csv `TRAINING_EXP_PER_POINT`) accumulates.
An empty board gives only a trickle per player per week; focusing courses on one stat is how a stat climbs fast.

Leftovers **carry over only within the week** (`season_state["training_exp_carry"]`,
`seat → {stat: remaining EXP}`). They used to be simply discarded — with settlement once a week,
discarding happened only once per week — but once settlement was split per weekday, that would make a
board earning less than `EXP_PER_POINT` per day score 0 every day for five days and gain not a single point all week. The bank
is emptied at the start of the week (`reset_week_progress`) — if it accumulated across weeks, a week
with an empty board would raise stats from last week's leftovers.

## Application (`apply_day_training(day)`)
**Training is applied per weekday.** The old `apply_week_training()` was deleted — once the
week-progress screen (`features/season/week/`) started asking "what happened that day" for each
weekday, settlement was split per day too.

It returns the row list that screen reads — in seat order,
`Array[{pilot_id, role, seat, before, after, ups, exp, carry, quirk, stress, color, group, facility}]`
(`group` = board entry index of the cell's tile, -1 = basic course — pilots sharing it **trained together**
that day, the morning talk's `talk_pair`; `facility` = `day_groups(day)`, the week map's spot) (no name — saved in the run file; screens use `GameManager.pilot_name(pilot_id)`, l10n D7)
(no `mastery` any more — the `M` tiles were removed in §16, readers default it to 0;
`quirk` = quirk ops run on that pilot that day, `[{kind, result, id?, from?, to?, slots?}]`, empty
array when none — see "Quirk tiles";
`stress` = stress that pilot gained that day, `StressSystem.on_training_day` (every pilot, an empty cell is the
basic course), `features/season/mental/README.md` "Stress";
`color` = the colour symbol of that pilot's cell that day (`day_colors(day)`; an empty cell gives the basic
course's colour, `filler_color()`): the week screen stands the pilot on that colour's spot of the team base map,
`features/season/week/README.md`).
`ups` is the points actually gained that day, `exp` the EXP earned that day, `carry` the remainder
left in the bank after settlement (the screen shows "until the next point" as `carry/EXP_PER_POINT`).

The guard against applying twice is **on the screen side** — it stores the result in
`season_state["week_day_log"][day]` and doesn't call again if one exists
(`WeekProgressView._settle_day`, run by the morning's Next on the week screen). There really is a path that returns to the same weekday
after playing a match.

## Screen layout

Four vertical blocks — **five portraits → 5×5 board → one row of course cards → bottom action bar (하단 액션 바)**.

**Staff line (§16).** Right under the title one centred line names each training facility's occupant
and training stat — `훈련장 — 전장 강민호 17 · 교전 감독 6 · 성장 없음 1`
(`TrainingView._owner_text`: `FacilitySystem.occupant_name` / `stat_value`, short facility labels
`training.view.fac_short.*`). The right end of the "훈련 코스" label row says what that means for the
courses — `훈련 효과 전장 ×a · 교전 ×b · 성장 ×c` (`_refresh_staff` → `_effect_text`): each value is that
facility's multiplier (`TrainingBoard.facility_exp_mult`) × the shared parts (`FinanceSystem.training_exp_mult`
× trait `train_exp_pct`, `_shared_parts` = `TrainingBoard.shared_exp_mult`); when a shared part moves it,
`(재무 ×b · 특성 ×c)` follows (parts at ×1.00 left out). The board area (`BoardArea`) starts below the staff
line. Per-pilot parts (breakthrough `train_bonus_pct`) show as a green `EXP ×r` chip on that pilot's
portrait — `r` = the pilot's best day of `exp_mult_table` ÷ `cell_team_mult` (the same cell's team-wide
value), so it reads straight from what settlement multiplies (`_refresh_exp_chips`).

**There is one horizontal baseline — the board is centred.** `Block` is centre-anchored and 880 wide
(100..980 on 1080): a **60px weekday label column** (`DayLabels`, 100..160) + the **760px board**
(`%Grid`, 5 × `CELL` 152, 160..920) + a **60px empty right gutter** (920..980) of the same width as the
labels, so the board itself sits at the screen centre. The portrait row is in the same `Block`, inset
by the same 60px on both sides, so the portraits can't drift off their columns. `%Grid` is a separate
node starting at the board's left edge, so drawing, hit testing, the drop preview and the drag preview
all stay **board-local** — the label column never enters the `CELL` maths. (A much older version put
the weekday text **inside** the board's coordinate space with a constant left edge, `GRID_X` 80, which
pushed the board's right edge off screen (1102 > 1080); the labels are now a sibling column in the
scene, and the cell shrank from 176 to 152 to make room inside the same 880px block.)

**There is also one vertical baseline, stacked bottom to top.** `Inventory` is anchored to the bottom of
`%SafeArea`, hanging the course list 24px above the bottom action bar, and `BoardArea` (the room between the
staff line and the course label row) centre-anchors `Block`, which **splits the remaining space evenly above
and below the board**. The list is one row of cards (236px), so there's plenty of
room above it; attaching everything to the top leaves the bottom of the screen pointlessly empty, and
attaching it to the bottom opens a gap between the title and the board. The portrait row is the
board's header, so both live in `Block` — portraits at its top, the board 15px below them —
if the two moved independently, column headers would drift away from their columns.

### Scene tree (`UI_View_TrainingView.tscn`, §4 #11 of `docs/ui_scene_migration.md`)
```
TrainingView (Control, full rect, PASS, theme = OutgameTheme.tres)  — script: TrainingView.gd
├ %Background      ColorRect BG — code stretches it up into the notch band (extend_background)
├ %SafeArea        Control full rect — code: offset_bottom = −bottom inset
│ ├ Title          TitleLabel 34, centred, y 8..52
│ ├ %StaffLine     SubLabel 22, centred, x 40..−40, y 54..84
│ ├ BoardArea      Control, y 96 .. −436 (= course label row − 16)
│ │ └ Block        centre-anchored 880 × 835.83 (= 60 labels + 760 board + 60 empty gutter)
│ │   ├ %Thumbs    HBox (sep 6, inset 60 + 3 each side) ─ TrainingThumb_Thumb0..4 = UI_Comp_TrainingThumb.tscn (146 × 60.83)
│ │   ├ %Grid      760 × 760 at the bottom of Block, x 60..−60 — drawn in code, STOP, drop target
│ │   └ DayLabels  VBox sep 0, x 0..60, bottom 760 ─ Day0..4 SubLabel 26, 152 tall, centred, text = term.day.short.mon … fri keys
│ └ Inventory      bottom-anchored, x 40..−40, y −420 .. −152
│   ├ CourseLabel  SubLabel 22 "훈련 코스"
│   ├ %EffectLine  AccentLabel 20, right-aligned, 860 wide (overlaps the label row on purpose)
│   └ %CourseScroll  ScrollContainer (h: never-show bar, v: disabled), y 32..
│     └ %CourseRow   HBox sep 14 — code fills TrainingCourseCard × N + a 24px tail pad
└ %Bar             HBox sep 0, bottom-anchored, height 128 (+ bottom inset, code)
  ├ %ClearButton   BarGhostButton 28, ratio 1 ─ Sep (BarSeparator Panel, 2px at its right edge)
  ├ %AutoButton    BarGhostButton 28, ratio 1 ─ Sep  (hidden unless training is delegated)
  └ %ConfirmButton BarPrimaryButton 34, ratio 2
```
**Scene owns**: every position / size / font size, variations — including the training-only screen
variations `TrainingThumbFrame` · `TrainingThumbExpChip` · `TrainingCourseCardFrame` · `TrainingCourseGradeBand` ·
`TrainingCourseShapeWell` · `TrainingCoursePopoverFrame` — and the bar separators.
**Code owns**: data colours (role border on each thumb, grade colour on card frame · band · grade letter ·
popover border · cap, POSITIVE / NEGATIVE on the EXP chip, the selected-card look), the safe-area insets
(`indent_to_safe_top` on the view, `extend_background`, and `OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)` —
`%SafeArea.offset_bottom`, `%Bar.offset_top`, each bar button's `content_margin_bottom += inset`), the drawn
board (`_draw_grid`), the shape miniature (`TrainingCourseCard._draw_mini`), the drag preview
(`_make_drag_preview`, built per drag), and the popover height (derived from text).
Theme styleboxes are never mutated in place — code colours a copy (`OutgameTheme.variation_box`).
No local StyleBoxes (`resources/README.md` → Screen variations).

### Five portraits (column headers)
The **same horizontal portrait (초상화)** as the in-game pilot strip (`PilotImages.eye_for`, 480×200
band), and the cell height comes from that ratio (2.4:1) — stretching to an arbitrary height squashes
faces. **Not tappable, no name · role text**: the only question this row answers is "whose week is
this column", so the face is the answer and the border colour is the role.

This row used to be **tappable**, with an **expected-change row** below it showing the selected
player's six stats as `before→after`. Once the portraits became pure headers there was no subject to
select, and that information is shown after "훈련 확정" by the **week-progress screen**
(`features/season/week/`), per weekday, five players × six stats. The single weekly summary
(`TrainingResultView`) that used to fill that role was deleted when settlement was split per weekday.

### Board (`_draw_grid`)
Cells are **square** (`CELL` 152, was 176 before the weekday label column + right gutter took 2 × 60px
of the 880px block) — a colour patch is "one player's day", so if cells were flat and
wide, multi-cell tile shapes (2×2 · 1×3 · 5×1) would read distorted on the board. The scene sizes
follow `CELL`: `%Grid` 760 × 760, each `DayLabels` row 152 tall, portrait 146 wide (+ 6 gap) × 60.83
(2.4:1).

**Empty cells are not drawn. The background is just one vertical line per player**
(`COLUMN_LINE_W` / `COLUMN_LINE_COLOR` — running through the column centre for the board's height).
It used to lay down twenty-five cells as `SURFACE_SUNK` fills + `BORDER` outlines, but that made a
board with nothing placed look already full, and placed tiles got buried in that grid. The lines run
**under** tiles, so a tile sits on top and covers its line — placed and empty spots are distinguished
by one thing: "is the line visible".

**The tile body is a rounded rectangle** (`TILE_RADIUS` 20). One function, `_tile_cell_box`, owns the
geometry, and the rule is single — **on an edge touching a neighbouring cell of the same tile, drop
the padding (`CELL_PAD`), the border (`TILE_EDGE`), and the corner rounding**. So multi-cell tiles
join into one mass with no dividers between cells, and rounding applies **only at corners where two
outward edges meet**, making the whole mass a single rounded rectangle. It's the same rule the
battlefield's camp outline uses (draw only when the neighbour beyond that edge is not the same tile).
Colour is **the colour of the cell that edge belongs to**, so [합숙 스크림] (Training-camp Scrim),
red on top and purple below, reads as top/bottom-different from its outline alone.

**Inside a tile, cell boundaries leave only the middle segment of the seam** (`_draw_tile_seams`,
`SEAM_LEN` 32 × `SEAM_W` 2, α `SEAM_ALPHA` 0.45). Each seam is treated as **one continuous line**
with a short segment stamped at its midpoint — so for 2×2 both vertical · horizontal seams are cut
at the tile centre into **a small cross**, 2 cells wide gives **a small vertical dash** in the
middle, and 5 cells wide ([전지 훈련] (Field Training Camp)) leaves its four seams as short vertical
dashes each in its own place. Drawing the lines all the way reads as "the tile breaks here", making
one tile look like several — exactly what the old way of drawing the inner seams in full did.

The only text left on a tile is **its name**, sitting in the centre of the area the tile covers. The
EXP summary was removed here — the board's question is "what was placed where", and the numbers live
in the inventory's info popover.

**Geometry is read in three places, so it must live in one function** — the board
(`_draw_tile_body`), the drop preview on the board, and the cursor-following preview
(`_make_drag_preview` + `_add_preview_seams`). All three go through `_tile_cell_box`, so rounded
corners and seam segments land in the same spots: if the preview and the placed result differ in
shape, it isn't a preview.

### Course inventory + info popover
**The list is a horizontal scroll of one row of upright cards** (card 168×236, gap 14, 5½ cards on
screen — the half-cut card itself says "more to the side", and the scrollbar is hidden). It used to be
a **vertical** scroll of 4 across × 2.5 rows, but with the board right above the list, "drag a card up
onto the board" and "scroll the list up" were the same gesture — in practice every drag starting on a
card was eaten as a tile pickup and the list never scrolled at all.

**Now the direction of the first movement decides** (`DragScroll.attach(_inv_scroll, true, true)`):
the moment the 14px threshold is crossed, **horizontal means scroll, vertical means pick up that
card's tile.** The decision is made once, so the meaning doesn't change if the finger drifts
diagonally afterwards. A vertical decision arrives via `cross_drag_started`, and the screen opens the
drag itself with `force_drag(data, preview)` (`_on_inv_cross_drag`) — with `set_drag_forwarding` on
the cards, the engine starts a drag after just 10px, getting ahead of the direction decision. The drop
side (board) still uses the built-in path. Which card is picked up is `_inv_press_tile`, recorded by
`_on_card_input` at the moment of the press. Locked cards can't be picked up (they can be selected).

The row shows **only owned courses** (`TrainingBoard.owned_tiles`, one card per line at its owned
level). From the top, one card is a **grade band** (22% grade-colour fill + grade letter + `놓임/보유`
(placed/owned, `∞` for the basic course)) → **shape miniature in a sunken box** (cells up to 26px) → **name** (up to two
lines). No description or EXP summary — when skimming to choose, you compare names and shapes.

**Tapping a card shows an info popover above it** (`_select_card` → `TrainingCoursePopover.fill` →
`_place_popover`) — four items: grade · name · placed/owned · **EXP summary** · **effect summary**.
No description line (see the CSV section above). EXP uses full stat names, not abbreviations
(`전장 회피 +N` (Battlefield evasion +N), not `전회 +N`) — it's 348px wide and the only question
here is "what does this course raise", so there's no reason to make readers decode. It appears
**above** the card, centred (the cards are one row, so the side spots belong to other cards), is
pulled back in if it would go off screen, and hides along with its card when that card is scrolled
out. A release after scrolling is not a tap (`DragScroll.moved`). The popover is a separate board
living **outside** the scroll (inside, it would be clipped to the scroll width), so `_place_popover`
follows when the scroll moves. Height is derived from the text (`TrainingCoursePopover._text_height`) —
the popover must be placed in the same frame it opens, and container auto-sizing (an autowrapped
`Label`'s minimum height) is only right after a layout pass, so the layout frame and the draw frame
would disagree. **That height must not use `Font.get_multiline_string_size` as is**: it only
adds the font's line height and doesn't count the `line_spacing` (default theme 3) that `Label` puts
between lines, so two-line text measured at 49px comes back as 46. Those 3px poking past the
popover's bottom edge onto the board were the cause of **the description overflowing the panel** —
`_text_height` counts the lines and adds that share back (measured 1 line 23 · 2 lines 49 · 3 lines
75, matching `Label.get_minimum_size().y` exactly). **Locked cards (every owned copy already placed)
can still be selected** — being unable to place it and being unable to see what it is are different
things. The popover swallows clicks itself and **closes on that click**: otherwise the card beneath
gets pressed instead, so the popover just opened closes on the spot or switches to the neighbouring
course (the popover covers two or so cards, so this always happens).

## Owned courses (`TrainingCourses`)
Courses are **items with a count**. A tile can go on the board as many times as the run owns it
(`TrainingBoard.can_take_more` = placed < owned); there is no per-grade limit and no tactics
unlock any more. Inventory cards show `놓임/보유`, and a card whose copies are all placed is locked.

- **State**: `season_state["training_courses"]` = `{line: {"tile": tile_id, "count": int}}`
  (string keys, JSON round-trip via `SaveSystem._courses_in`). `count` -1 = unlimited.
- **New run** (`GameManager.init_season` → `TrainingCourses.new_inventory`): **Basic Training I only**.
  A run saved before ownership gets the same on first read (`TrainingCourses.inventory`).
- **Basic line** (`basic`, 기초 훈련 I~IV = D/C/B/A, all-stat +8 / +12 / +14 / +16 per cell): unlimited,
  and the owned level is also what **fills every empty cell** — upgrading it raises the whole board.
  The coach never places it (an empty cell already is it).
- **Upgrade rule** (`grant(state, tile_id, n)`): a line is owned at one level; every copy counts as the
  highest grade acquired. A higher level replaces the lower one (copies on the board are rewritten in
  place); a lower level adds a copy at the owned level — own 사격 훈련 II ×1, gain 사격 훈련 I →
  사격 훈련 II ×2. Stat lines (사격 · 회피 기동 · 근접 교전 · 반응 · 화력 증강 · 내구 단련) are
  I / II / III = C / B / A, single-stat +44 / +52 / +58 per cell.
- **Acquisition = research (§16).** The three training facilities research courses
  (`features/season/facility/research/TrainingResearch.gd`, rows in `data/csv/research.csv`, rules in
  `features/season/facility/README.md` "TrainingResearch"): each completion is `grant(state, p1, 1)`.
  Higher grades need a higher facility level (`min_level`); a row is blocked once its line is owned at a
  higher grade (basic: this grade or higher). Every non-basic-I tile is granted by exactly one row.
  The F6 preview still uses `grant_all`. 한계 돌파 (old T13) was removed.

## Training stat — per facility (§16)
Contract: `docs/outgame_dev_plan.md` §16 (decision 3). There is no single team training stat any more:
**a cell's EXP is multiplied by the training stat of the facility that owns the course line trained in that
cell** — `FacilitySystem.stat_value(state, fid)` (the occupant's training stat; nobody seated → `STAT_MIN`).
Which facility owns a line is data: the training facility whose research rows grant it
(`TrainingResearch.facility_of_tile` / `facility_of_line`, built from `research.csv`):

| Facility | Lines (colours) |
|---|---|
| `train_field` 전장 훈련장 | 사격 (`H`) · 회피 기동 (`E`) |
| `train_engage` 교전 훈련장 | 근접 교전 (`C`) · 반응 (`D`) · 합숙 스크림 (`CC/DD`) |
| `train_growth` 성장 훈련장 | 화력 증강 (`A`) · 내구 단련 (`P`) · **the basic course** (every empty cell) · quirk tiles · amplifier / misc tiles |

**Decision**: the basic course (Basic Training I is granted by no row) and any tile no research row grants
fall back to `TrainingResearch.DEFAULT_FACILITY` = `train_growth` — the facility that researches Basic
Training II~IV, so the whole basic line is consistently its. Note the growth facility has no auto-seat at run
start (`FacilitySystem.JOB_FACILITY`), so empty cells train at `STAT_MIN` until someone is seated there.

`TrainingBoard.cell_facilities()` maps each cell to its facility (placed tile, else the basic course);
`cell_team_mult()` = that facility's `facility_exp_mult` × `shared_exp_mult()` (finance × trait);
`exp_mult_table()` multiplies the per-pilot parts on top. Numbers are in `data/csv/const.csv` — this README
names keys only.

| Stat | Rule | Keys |
|---|---|---|
| **Training** (per facility) | Tile EXP multiplier `1 + (stat − pivot) × step` (`TrainingTile.training_exp_mult`, via `TrainingResearch.exp_mult(state, fid)`). | `TRAINING_STAT_EXP_PIVOT`, `TRAINING_STAT_EXP_STEP` |

The `코치 추천` slot still follows `StaffSystem.is_delegated(state, "training")` (the best occupant of the
training facilities is staff).

Cards whose owned copies are all placed fade; they can be selected but not picked up
(`TrainingView._card_locked` = `not TrainingBoard.can_take_more(t)`).

### Where the EXP multipliers meet
Final cell EXP = (tile EXP × clause multipliers + clause additions) × **outside multiplier**, rounded
once per cell in `TrainingBoard.cell_exp()` step 3. The outside multiplier per cell comes from
`exp_mult_table()`:

```
facility training-stat mult (that cell's course) × FinanceSystem.training_exp_mult(state) × MentalSystem.training_exp_mult(state, pilot_id, day)
  × TraitSystem.run_pct_mult(state, "train_exp_pct")        (M8 manager traits, whole board)
  × (1 + PlayerData.train_bonus_pct / 100)                    (M10 breakthrough, that pilot's column only)
```

This is the single place they are multiplied (plan §11.3). Preview (`compute_gains` →
`projected_stats`) and day settlement (`compute_day_gains` → `apply_day_training`) both read
`cell_exp()`, so they cannot disagree (verified headless: the sum of the five settled days equals
the week preview, and stats after five days equal `projected_stats`).

## Mastery tiles — removed (§16)
The `M` (mech-mastery) tiles T16 / T17, colour `M`, the `mastery:N` EXP clause, `cell_mastery` /
`compute_mastery` and the `MechMastery.add_training_exp` call in `apply_day_training` were removed: mech
mastery now comes from the mech lab's research (`features/season/facility/`, agent D). The base map's `M`
spot stays (other content may stand there).

## Quirk tiles (colour `Q`, §14 T1)
A `Q` cell gives **no stat EXP** (like `K`); the tile's quirk clauses act on the pilot of that
cell on that cell's day — so a tile costs those training days. Parsing lives in `TrainingTile`
(`quirk_ops`, kept out of `clauses` so EXP settlement never sees them; `is_quirk_cell(i)`,
`has_quirk()`); `effect_summary()` adds one `훈련한 선수: …` line per op.

| Clause | Effect (`QuirkSystem`, rules in `features/season/quirk/README.md`) |
|---|---|
| `quirk:gain` | `gain_random` — a random quirk into an empty quirk slot (`full` = nothing) |
| `quirk:reroll` | `reroll` — redraw every equipped quirk |
| `quirk:slot` | `add_slot` — +1 quirk slot (up to `QUIRK_SLOTS_MAX`) |

- **Settlement**: `day_quirk_ops(day)` collects the ops of the `Q` cells on that row (`{seat: [op]}`,
  order slot → reroll → gain so a new slot can be filled the same day); `apply_day_training` runs
  them through `_apply_quirk_ops` **once per pilot per settled day** and writes the row's `quirk`.
  A pilot has one cell per day, so a multi-day tile acts once per `Q` day — `Q/K` acts once.
- Tiles (placeholders): `T18 기벽 발굴` (C, `Q`, gain) · `T19 기벽 재조정` (B, `Q`, reroll) ·
  `T20 동반 발굴` (B, `QQ`, gain for two pilots) · `T21 잠재력 개방` (A, `Q/K`, slot — two days of one
  pilot). They compete with stat tiles for the day itself.
- Auto-arrange never places them (`coach_may_use` rejects any non-`mult`/`flat` clause — see below).

## Auto-arrange — "코치 추천" (M3, reworked §14 T6)
When training is **delegated** (`StaffSystem.is_delegated(state, "training")` — a coach or the
assistant covers it), the bottom bar shows a third slot `코치 추천` between `판 비우기` and
`훈련 확정`; when the manager owns training the slot is hidden and `%Bar` (an HBox with stretch
ratios) re-splits the remaining two by ratio. Pressing it calls `TrainingBoard.auto_arrange()`, and the
player can edit the result as usual.

It is **per-pilot weak-stat reinforcement + grade balance** — still a **plain rule, not an
optimiser** (plan §11.0 / §14.0 — no bonus either way), and deterministic (fixed tie-breaks, no RNG).
The M3 version only asked "does this raise the board's total EXP", which a focused single-stat tile
never does (it gives less in total than the all-stat filler), so a C-only team got nothing but the
old all-stat `W/W` C tile.

1. Clear the board. `coach_needs()` ranks each pilot's six stats by **deficit against the role
   average** (every pilot of that role in `all_pilots`; ties keep `PlayerData.STAT_KEYS` order) and
   keeps the top `COACH_WEAK_RANK`.
2. Walk the **owned** courses grade by grade, highest first. Inside a grade:
   - **focus pass** — the owned copies of **focused**
     tiles (`is_focused_tile`: trains fewer than six stats). Pilots take turns (fewest reinforced
     stats first, then the largest deficit, then seat); each turn aims at that pilot's weakest stat
     not yet reinforced that some tile trains, and picks the tile + origin covering that pilot's
     column with the **largest gain in that stat for that pilot** (ties: earliest day, then leftmost).
     A tile with a downside clause is thereby placed where the downside costs least;
   - **broad pass** — the owned copies of broad tiles (all-stat / amplifiers) by the M3
     rule: first day-then-seat position that raises `board_total_exp`.
3. One more broad sweep over all grades (an amplifier placed before what it amplifies gets a
   second chance).

**Never auto-placed** (`coach_may_use`): the basic course (an empty cell already is it) and any tile whose
raw `effect` has a clause kind other than `mult` / `flat` (e.g. T1's `quirk:*`) — which quirk to chase is
a separate decision. Only owned copies are placed (`can_place`), so with
just Basic Training I the coach places nothing. Key: `COACH_WEAK_RANK`.

## Drag & drop (`TrainingView`)
Uses Godot's built-in drag (`set_drag_forwarding`). There are two origins.

* **Inventory card** → place new. **Only when dragged vertically** (horizontal is list scroll), and it
  is opened via `force_drag`, not the built-in path (see the inventory section above). Where on the
  card you grabbed is ignored.
* **Tile on the board** → move. **It is removed from the board the moment it is picked up**
  (otherwise a move one cell over is rejected as "overlaps itself"). If the drop fails,
  `NOTIFICATION_DRAG_END` restores it to its original spot; on success `_grid_drop` deletes the
  restore copy (otherwise the tile duplicates).

### The cursor is always at the tile's centre
A dragged tile follows **with its own centre on the cursor**, and whichever cell that centre is
nearest to is where it lands (`_origin_for` — centre-align → round → clamp into the board). Preview
and the green cells on the board come from **the same single function**, so the shape under your
finger and where it actually lands can't diverge. Why clamp is needed: the 5-cell [전지 훈련] can only
have x = 0, and trying to drop a 2-cell tile at the centre of the leftmost column points its centre
off the board — without clamping there would be spots you could never place on.

**The preview node has two layers because of the engine.** The viewport **overwrites** the node passed
to `set_drag_preview` with `set_position(mouse position)` every frame — an offset written on that node
vanishes with no error or warning, and its top-left corner sticks to the cursor. So the outer `root`
yields its position to the engine, and the actual drawing is held by its **child**, shifted by
`-ext × CELL / 2`. The old code didn't know this and shifted `root` itself, so **the preview appeared
with its top-left stuck to the cursor while the drop went in relative to the grabbed cell** — the
shown spot and the landing spot differed.

### Area-of-effect display (yellow cells)
**Dragging a tile that has clauses lights up in yellow the cells it reaches** — the cells that would
receive its multiplier · addition if dropped where the cursor points now, and they disappear at the
moment of the drop (when `_drag_tile` empties). The list comes from
`TrainingBoard.affected_cells(t, origin)`, and that function **goes through the same `_scope_cells` as
settlement (`compute_gains`)**, so the cells shown and the cells actually affected can't diverge.

Three reading conventions. **(1) Tiles without clauses show nothing** — drawing an "area of effect"
for a tile that does nothing to others blurs what the display means.
**(2) Own cells are excluded** — the drop preview (green / red) already speaks for that spot, and
the display is laid **before** the preview so on overlapping cells the preview covers it.
**(3) It shows even where placement is impossible** — being unable to place and not seeing what it
touches are different things, and moving around while watching this display is how you choose a spot
for an amplifier tile.

Colour **points with an outline rather than filling the cell** (`AFFECT_FILL` α 0.16 +
`AFFECT_LINE`) — a dense fill would erase what colour the already-placed tile in that cell was, and
seeing what an amplifier tile lands on is the whole reason to look at this display.

**A tap (a press without movement) does something different from a drag** — tapping a tile on the
board removes it, and tapping an inventory card **selects it and shows the info popover**. The
built-in drag starts only when the cursor moves, so a plain press-and-release is caught separately by
`_gui_input`.

### Feel — pick up · click per cell · drop
Neither inventory cards nor the board are `BaseButton`, so `HapticUi`'s auto-wiring doesn't reach
them. So this screen calls `Haptics.play(...)` directly, and **one placement opens and closes as
pick up → cell crossing → drop.**

| Event | Where | Haptic |
|---|---|---|
| Pick up a tile | `_begin_drag` | `SELECT` |
| Preview **snaps to a placeable cell** | `_grid_can_drop` | `LIGHT` |
| Tile locks onto the board | `_grid_drop` | `SOFT` |
| Tap a tile on the board to remove it | `_on_grid_input` | `LIGHT` |

**The preview buzzes every time it crosses a cell.** Dragging across the board gives a tick per cell,
click-click-click, and each tick means "crossed one cell" — because the preview moves **locked to
cells**, not in free coordinates, this becomes a signal rather than vibration (it fires only when
`origin != _hover_cell` changes, not every frame). **Unplaceable spots are silent** — that silence
means "doesn't fit here", and the red preview already says so. It used to look only at the single
`ok and not _hover_ok` transition, so no matter how much you swept across the board it buzzed only
once. **Removal is lighter than drop** because it is an undoing hand, not a committing one.

The board is **one `Control`, not twenty-five nodes** (`_draw_grid`) — cells · placed tiles · drop
preview are drawn in one place, and hit testing and drawing read the same `occupancy()` table, so the
visible tiles and the grabbable tiles can't diverge.

## Save
`season_state["training_board"]` = `Array of {tile: String, x: int, y: int}`
(`x` = player seat 0..4, `y` = weekday 0..4). **Empty cells are not stored.**
When a week ends, `SeasonHub.on_proceed_to_next_week` clears the board via `reset_for_new_week()` —
it isn't pre-filled with basic courses because empty cells are already settled as basic courses, and
keeping it empty makes "what I placed this week" visible at a glance.

## Stats (six kinds, `PlayerData`)
The only table is `PlayerData.STAT_KEYS` / `STAT_LABELS` / `STAT_SHORT` / `STAT_NOTES`, and both
screens in this folder read it too. **Minimum 1, no maximum** — keeps growing past 100.
Details in the "Player stats (six)" entry of `features/battle_sim/combat/README.md` "Active Systems" (moved there from root `CLAUDE.md`).

## Bottom action bar
With training delegated the bar is `판 비우기` (1) · `코치 추천` (1) · `훈련 확정` (2); otherwise the
middle slot is hidden and the two below share the bar as described (see "Auto-arrange").
"판 비우기" (Clear board) (1) and "훈련 확정" (Confirm training) (2) **split the bottom section 2:1** —
edge to edge left to right, bottom flush to the safe line, square corners. Conventions and pitfalls
are in the "Bottom action bar" section of `resources/README.md`; this screen knows one special thing —
**the course list hangs from this bar's top edge** (`Inventory` is anchored to the bottom of `%SafeArea`, whose
bottom is the bar's top), so adjusting the bar makes both the list and the board follow automatically.
The bar is an HBox in the scene (ratios 1 : 1 : 2), not `OutgameTheme.add_bottom_bar`; the bar-only
look is the scene's `BarGhostButton` / `BarPrimaryButton` variations (square corners) and the inset is
`OutgameTheme.fit_bottom_bar`. The confirm button used to float at screen
centre at 460×104, with "판 비우기" small to its left.

### `TrainingType` enum removed (moved from root CLAUDE.md)

**`TrainingType` was deleted** — when daily training changed from "one training type per day" to the
tile placement board, the very concept of a type went away. What one cell on one day is now is
answered by `training_tiles.id`.

## Not yet ported from the original

The original's analysis (`docs/routine.md` at git `bc52878`) has the numbers and source text — revive
that doc when adding these.
* **Conditional** — adds per count of a colour in the same column·row (escape training · spectating · study summary …). `cell_colors` is the hook.
* **Corrective** — picks the lowest / highest stat to raise (weakness fix · power up).
* **Great success** — +50%, tiles that raise or block its chance (`resultCannotBeVerygood`).
* **SS grade · non-rectangular (hole `.`) tiles · column-1-only tiles · amplifier materials · part-time job (training points)**.

## Localization
Screen text is l10n keys (`training` domain: `training.view.*` code templates, `training.training_view.*` scene
captions, `training.level.*` training-level chip / detail rows, `training.pilot_detail.title` (the detail sheet's
section title, a scene literal in `features/season/UI_View_SeasonPilotDetail.tscn`), `training.limit_break.*` the
limit-break header · goal choices · previews · progress · notes). The limit-break **dialogue lines** are Draft
events (kind `limit_break`, domain `mental`, see "Training level · limit break"). The effect-line part labels in `TrainingView._shared_parts` are keys translated in `_effect_text`;
the staff / effect lines use `training.view.staff_line` · `.fac_owner` · `.fac_short.<fid>` · `.fac_mult` ·
`.effect_fac` · `.effect_fac_breakdown` (`TrainingView.FAC_SHORT`).
