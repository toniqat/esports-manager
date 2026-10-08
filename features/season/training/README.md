# Daily training (일상 훈련) (tile placement board)

Players' training is planned by **slotting course tiles into a 5-column (player) × 5-row (one per
day) board**. It ports the routine training board of the original game (Esports Godfather). The
analysis doc of the original's 87 tiles was deleted; it remains in `docs/routine.md` at git
`bc52878`.

**The word "주간" (weekly) and weekday (요일) labels were removed from the screen.** The board still
has five rows and is still settled one day at a time (`apply_day_training`), but what you plan here
is not a week's timetable but the **daily routine** of five players — writing Mon · Tue · Wed on each
row makes those five cells read like calendar appointments and pulls the eye away from what this
screen actually asks (who gets what, and how much). The order of the rows (top to bottom) already
expresses sequence. `TrainingBoard.DAY_NAMES` was the only consumer of that text, so it **was deleted
too** — the only place that needs weekday names is the **week-progress screen (시간 경과 화면)**
(`features/season/week/`), which has always read `OutgameTheme.DAY_NAMES`.

## Files
| File | Role |
|---|---|
| `TrainingTile.gd` | `class_name TrainingTile` — one CSV row = one tile. **Grammar parsing lives only here** (shape · colour · EXP · mastery · effect clauses · quirk ops). Also owns the colour table · grade table and the **staff-stat lookups** (grade unlock from tactics, per-grade placement limit and EXP multiplier from training — see "Manager / staff stats" below). |
| `TrainingBoard.gd` | `class_name TrainingBoard` — headless board. Staff stats (`training_stat` / `tactics_stat` / `limit_of` / `is_unlocked` / `can_take_more`), placement checks (`can_place` / `place` / `remove_at`), settlement (`cell_exp` / `exp_mult_table` / `compute_gains` / `compute_day_gains`), mastery (`cell_mastery` / `compute_mastery`), quirk ops (`day_quirk_ops`), per-day cell colours (`day_colors`, read by the week screen's base map), **weekday application** (`apply_day_training`), preview (`projected_stats`), auto-arrange (`auto_arrange`), week-progress reset (`reset_week_progress`). The `TrainingBoard` node in Season.tscn. |
| `TrainingView.gd` · `UI_View_TrainingView.tscn` | Planning screen — staff line + 5 portraits + 5×5 board + horizontally scrolling course cards + bottom bar ("판 비우기" · "코치 추천" · "훈련 확정"). Drag & drop. **The frame is the scene** (see "Scene tree" below); the script binds `%` nodes, fills data, applies the safe-area insets, and owns the drawn board + drag & drop. Created with `TrainingView.create()` (`SeasonHub._ensure_training_view`). Layout · reading conventions are in "Screen layout" below. |
| `UI_Comp_TrainingThumb.tscn` | One portrait column header (frame · face · per-pilot `EXP ×r` chip). No script — `TrainingView._bind_thumbs` sets the role border colour; five instances sit in `UI_View_TrainingView.tscn`. |
| `TrainingCourseCard.gd` · `.tscn` | `class_name TrainingCourseCard` — one course card of the inventory row (grade band · cap · shape well · name · lock chip). `fill(tile, cap, grade_locked, locked, lock_reason)`, `set_selected(selected, locked)`; the shape miniature is drawn into `%Mini` (`_draw_mini`). |
| `TrainingCoursePopover.gd` · `.tscn` | `class_name TrainingCoursePopover` — the info popover over a selected card. `fill(tile, cap, lock)` sets the text and **derives the height from the text** (`_text_height`); `TrainingView._place_popover` positions it. |

**F6 preview** — each scene with a script fills dummy data when run alone (`resources/UiPreview.gd`):
`TrainingView` = in-memory run + preview-only `TrainingBoard` child, coach auto-arrange, third course card
selected with its popover; `TrainingCourseCard` / `TrainingCoursePopover` = hand-written grade-3 tiles
(card selected; popover with a lock line).

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
**Weekday names are not written beside the board** (see intro above) — `월` … `금` in the diagram
explain the data axis; they are not text shown on screen.

The original has this axis **reversed** (rows are players, columns are periods). That's why effect
scope names are by **meaning** (`day_*` / `mate_*`), not up/down/left/right — written as directions,
every clause would become a lie each time the board is rotated.

## `data/csv/training_tiles.csv`
| Column | Meaning |
|---|---|
| `id` | `T01` … (text PK) |
| `grade` | 0=D 1=C 2=B 3=A 4=S |
| `shape` | Colour string with rows separated by `/`. **One row = one day, one character = one player.** `W`=1 cell, `WW`=two on the same weekday, `W/W`=one player for two days, `CC/DD`=two × two days, `WWWWW`=one day for all five |
| `exp` | `stat:value` joined by `\|`. `all:N` = all six stats. **Value given per cell**, so an n-cell tile gives n times. `mastery:N` = mech-mastery EXP per mastery (`M`) cell (see "Mastery tiles") |
| `effect` | Clauses joined by `;` |

**There is no `description` column.** There used to be one, and the info popover printed it
verbatim, but those sentences were hand-transcriptions of the `effect` clauses, so editing a clause's
number made only the description silently lie. Both lines of the popover are now built from tile
data — `TrainingTile.exp_summary()` (EXP) and `effect_summary()` (effect).

**l10n (design §6.1).** The tile name is a key: `training_tiles.name_key` (`training.tile.{id}.name`) →
`TrainingTile.name_key`; `tile_name` is a read-only computed property (`Loc.t(name_key)`). Both summaries are
built from **template keys**, never `+` concatenation: `training.exp.none` · `.quirk_day` · `.mastery {n}` ·
`.all {n}` · `.stat {stat} {n}` (items joined by `training.list_sep`, EXP + mastery lines by a newline), and
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
| `M` | Teal | **Mastery** — 0 stat EXP; yields `mastery:N` mech-mastery EXP instead |
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

1. Lay down base EXP per cell. Empty cells are filled by the basic course (`FILLER_TILE_ID` = T01),
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
`Array[{pilot_id, role, seat, before, after, ups, exp, carry, mastery, quirk, stress, color}]` (no name — saved in the run file; screens use `GameManager.pilot_name(pilot_id)`, l10n D7)
(`mastery` = mech-mastery EXP handed to `MechMastery.add_training_exp` that day, M3;
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

**Staff line (M3).** Right under the title one centred line says who covers the two stats this
screen depends on and their effective value — `훈련: 강민호 코치 17 · 전술: 감독 6`
(`TrainingView._owner_text`: `StaffSystem.owner_name` + `코치` / `어시스턴트` suffix + `effective`).
The right end of the "훈련 코스" label row says what that means for the courses —
`훈련 효과 ×N · 사용 가능 X 등급까지` (`_refresh_staff`). The board area (`BoardArea`) starts below the staff line.
`×N` is the **team-wide** EXP multiplier — training stat × `FinanceSystem.training_exp_mult` × trait
`train_exp_pct` (`_shared_parts`, the same calls `TrainingBoard.exp_mult_table` multiplies). When
finance or traits move it, the breakdown follows in parentheses (`(스태프 ×a · 재무 ×b · 특성 ×c)`,
parts at ×1.00 left out). Per-pilot parts (breakthrough `train_bonus_pct`) show as a green
`EXP ×r` chip on that pilot's portrait — `r` = the pilot's best day in `exp_mult_table` ÷ the
team-wide value, so it reads straight from what settlement multiplies (`_refresh_exp_chips`).

**There is one horizontal baseline — the board is centred.** The board sits at the screen centre (100..980 on
1080) as part of the centre-anchored `Block` (portrait row + board), so the portraits can't drift off
their columns; the drop preview is drawn in board-local coordinates. Previously the board's left
edge was a constant (`GRID_X` 80) with a weekday text column **inside** it, pushing the board's right
edge off screen (1102 > 1080) — when the weekday column was removed entirely, that trap went with it
(`DAY_GUTTER` / `_day_x` deleted).

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
│ │ └ Block        centre-anchored 880 × 965.83
│ │   ├ %Thumbs    HBox (sep 6, inset 3) ─ TrainingThumb_Thumb0..4 = UI_Comp_TrainingThumb.tscn
│ │   └ %Grid      880 × 880 at the bottom of Block — drawn in code, STOP, drop target
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
`TrainingCourseShapeWell` · `TrainingCourseLockChip` · `TrainingCoursePopoverFrame` — and the bar separators.
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
Cells are **square** (`CELL` 176) — a colour patch is "one player's day", so if cells were flat and
wide, multi-cell tile shapes (2×2 · 1×3 · 5×1) would read distorted on the board.

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

From the top, one card is a **grade band** (22% grade-colour fill + grade letter + `놓임/상한`
(placed/limit)) → **shape miniature in a sunken box** (cells up to 26px) → **name** (up to two
lines). No description or EXP summary — when skimming to choose, you compare names and shapes.

**Tapping a card shows an info popover above it** (`_select_card` → `TrainingCoursePopover.fill` →
`_place_popover`) — four items: grade · name · placed/limit · **EXP summary** · **effect summary**.
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
75, matching `Label.get_minimum_size().y` exactly). **Locked cards (those that hit the grade limit)
can still be selected** — being unable to place it and being unable to see what it is are different
things. The popover swallows clicks itself and **closes on that click**: otherwise the card beneath
gets pressed instead, so the popover just opened closes on the spot or switches to the neighbouring
course (the popover covers two or so cards, so this always happens).

## Placement constraint — per-grade count limits
Tiles **can be reused any number of times** (there is no owned quantity). So the per-grade
placement limit is the **only** mechanism that prevents "plaster the board with the strongest
tile". D is always unlimited (it is the filler course). The C/B/A/S limits are no longer a fixed
table — they come from the effective **training** stat (next section). Each inventory card shows
`놓임/상한`, and cards of a grade that hit its limit are locked.

## Manager / staff stats (M3)
Contract: `docs/outgame_dev_plan.md` §11. Both stats are read only through
`StaffSystem.effective(state, stat)` (manager + temporary mods, assistant, or the dedicated coach —
whichever is highest), via `TrainingBoard.training_stat()` / `tactics_stat()`. The lookups that
turn a stat into a rule live in `TrainingTile` (static, so they take the stat as an argument). All
numbers are in `data/csv/const.csv` — this README names keys only.

| Stat | Rule | Keys |
|---|---|---|
| **Tactics** | Highest usable grade. D always; C/B/A/S unlock at their thresholds (`TrainingTile.max_unlocked_grade` / `grade_unlocked` / `required_tactics`). `can_place` refuses a locked grade. | `TACTICS_GRADE_C/B/A/S` |
| **Training** | Per-grade placement limit = top-tier limit × tier percentage (rounded, at least 1). The stat picks the tier (`TrainingTile.limit_tier`). `TrainingTile.place_limit_for(grade, stat)`. | `TRAINING_STAT_LIMIT_C/B/A/S`, `TRAINING_STAT_TIER_2/3`, `TRAINING_STAT_LIMIT_PCT_1/2/3` |
| **Training** | Tile EXP multiplier `1 + (stat − pivot) × step` (`TrainingTile.training_exp_mult`). | `TRAINING_STAT_EXP_PIVOT`, `TRAINING_STAT_EXP_STEP` |

Thresholds are placeholders tuned so a manager alone (no coach, starting manager stats) gets D·C
and the lowest limit tier, and a good dedicated coach reaches A/S and the top tier.

**Locked-grade cards are still shown** — a dark chip on the shape well says what they need
(`전술 N 필요`), the content fades, and the info popover adds one red line
(`%Lock`, `NegativeLabel` 16: `전술 N 필요 (지금 전술 M)`). Like limit-locked cards they can be selected but not picked up
(`TrainingView._card_locked` = `not TrainingBoard.can_take_more(t)`).

### Where the EXP multipliers meet
Final cell EXP = (tile EXP × clause multipliers + clause additions) × **outside multiplier**, rounded
once per cell in `TrainingBoard.cell_exp()` step 3. The outside multiplier per cell comes from
`exp_mult_table()`:

```
training-stat mult × FinanceSystem.training_exp_mult(state) × MentalSystem.training_exp_mult(state, pilot_id, day)
  × TraitSystem.run_pct_mult(state, "train_exp_pct")        (M8 manager traits, whole board)
  × (1 + PlayerData.train_bonus_pct / 100)                    (M10 breakthrough, that pilot's column only)
```

This is the single place they are multiplied (plan §11.3). Preview (`compute_gains` →
`projected_stats`) and day settlement (`compute_day_gains` → `apply_day_training`) both read
`cell_exp()`, so they cannot disagree (verified headless: the sum of the five settled days equals
the week preview, and stats after five days equal `projected_stats`).

## Mastery tiles (colour `M`, M3)
An `M` cell gives **no stat EXP** (like `K`) — instead each `M` cell yields `mastery:N` mech-mastery
EXP (`TrainingTile.per_cell_mastery` / `mastery_of_cell`). Rows in `training_tiles.csv` are ordinary
tiles with an `M` shape, e.g. `M` (one day) and `M/M` (one pilot, two days).

- **Raw amounts.** Clauses (`mult` / `flat`) and the outside multipliers above do **not** touch
  mastery EXP; `MechMastery` applies its own knowledge / facility multipliers (plan §11.3).
- `TrainingBoard.cell_mastery()` → `Vector2i(seat, day) → int`; `compute_mastery(day)` folds per seat.
- **Settlement**: `apply_day_training(day)` calls
  `MechMastery.add_training_exp(state, pilot_id, amount)` for each seat with mastery that day (the
  research mech is M4's business) and adds `mastery` to that seat's row.
- Display: the popover's EXP line is `TrainingTile.exp_summary()`, which appends
  `메크 숙련도 +N (연구 메크)` for mastery tiles.

## Quirk tiles (colour `Q`, §14 T1)
A `Q` cell gives **no stat EXP** (like `K` / `M`); the tile's quirk clauses act on the pilot of that
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
  pilot). They compete with stat tiles for the per-grade placement limit and for the day itself.
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
never does (it gives less in total than the all-stat filler), so a C-only team got nothing but `T02`.

1. Clear the board. `coach_needs()` ranks each pilot's six stats by **deficit against the role
   average** (every pilot of that role in `all_pilots`; ties keep `PlayerData.STAT_KEYS` order) and
   keeps the top `COACH_WEAK_RANK`.
2. Walk unlocked grades from the highest down to C (D is the filler). Inside a grade:
   - **focus pass** — up to `COACH_FOCUS_PCT`% of the grade limit (rounded up) goes to **focused**
     tiles (`is_focused_tile`: trains fewer than six stats). Pilots take turns (fewest reinforced
     stats first, then the largest deficit, then seat); each turn aims at that pilot's weakest stat
     not yet reinforced that some tile trains, and picks the tile + origin covering that pilot's
     column with the **largest gain in that stat for that pilot** (ties: earliest day, then leftmost).
     A tile with a downside clause (e.g. `mult:day_prev_all:50`) is thereby placed where the
     downside costs least;
   - **broad pass** — the rest of the limit goes to broad tiles (all-stat / amplifiers) by the M3
     rule: first day-then-seat position that raises `board_total_exp`;
   - whatever the broad pass could not use goes back to the focus pass.
3. One more broad sweep over all grades (an amplifier placed before what it amplifies gets a
   second chance).

**Never auto-placed** (`coach_may_use`): mastery tiles (`M` cells / `mastery:N`) and any tile whose
raw `effect` has a clause kind other than `mult` / `flat` (e.g. T1's `quirk:*`) — what to research and
which quirk to chase are separate decisions. Keys: `COACH_FOCUS_PCT`, `COACH_WEAK_RANK`.

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
captions). The effect-line part labels in `TrainingView._shared_parts` are keys translated in `_effect_text`;
the staff line translates `StaffSystem.STAT_LABELS` through `Loc.t` (staff module's table).
