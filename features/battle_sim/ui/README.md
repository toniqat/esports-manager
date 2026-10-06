# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | Strategy points (전략 포인트) ring gauge; the player's one doubles as the "턴 넘기기" (End turn) button |
| `CardPileStack.gd` | CardPileStack | Deck (덱) / discard pile (버린 더미) — a stack of cards lying face-down, tilted away + card count |
| `PilotStrip.gd` | PilotStrip | 5-pilot (파일럿) strip (스트립) — eye-level portrait (초상화) + HP (체력) bar + growth points (성장치). Two copies, top (enemy (적)) / bottom (ally (아군)); **pressing either opens the detail panel**. Ally cells also carry a **pilot skill readiness dim + number** |
| `ObjectiveTimer.gd` | ObjectiveTimer | Objective (오브젝트) spawn clock — icon + turns remaining on either side of the enemy strip (left Herald (전령) / right Dragon (용)). **Pressing it opens the reward popup** |
| `ObjectiveRewardPopup.gd` | ObjectiveRewardPopup | Objective reward preview — pressing a clock shows the actual cards that objective grants |
| `PilotDetailPanel.gd` | PilotDetailPanel | Pilot detail modal — left: 2 full-body arts (+ lasting effects at bottom-left) / right: header + 3 tabs + stat chips + **pilot skill block** / full-width bottom: **fan of held cards** |
| `MarkerTouch.gd` | MarkerTouch | Pressing a battlefield (전장) portrait — while held it grows to `PRESS_SCALE` and moves to the top (it stays on top after release); **long-press (0.45 s) opens the detail panel** |
| `KillFeed.gd` | KillFeed | Kill log — top-right, one line per kill (처치) / turret (포탑) demolition / objective capture. Kills during an engage (교전) are flushed together after the arena closes |
| `MvpView.gd` | MvpView | **Match MVP view** — full-screen dark card shown at match end **before** the victory/defeat panel: MVP's full-body art + name · side · position · K/D/A · key-metric line, "계속" (Continue). Also hosts the shared display strings (`display_name` · `role_label` · `kda_text` · `metric_text`) the result panel's MVP line uses. See "Match end — MVP view → result panel" below |

## HudBuilder.gd
`extends Node` — child of BattleSim.

Builds the battle HUD and updates it via `update_hud()` (per-turn) and
`update_time_label()` (every frame from `BattleSim._process`).

### `set_pregame_chrome_visible(on)` — HUD hidden before the opening (개시)
While the jungle start (정글 시작) choice (`gambit/JungleStartOverlay.gd`) is open,
**only the things that can't be used yet** hide — the deck / discard piles either side
of the hand (손패) row and their hit buttons, both strategy point donuts, and both
objective spawn clocks in the top panel. All three are spots that would show
something that doesn't exist yet as 0, and the hand area in particular is taken over
entirely by the junglers' portraits. **The pilot strips and the top panel stay** —
re-checking both teams' rosters just before the opening is part of what that screen
does. Everything is restored as-is when the overlay closes.

This is a **different function for a different reason** from `set_strip_visible(team, on)`
(called by the detail panel): that one clears what would sit on top of the dim; this
one clears what has no meaning yet.

### build_ui()
Creates UI inside `_bs.canvas` (a CanvasLayer added to BattleSim):

- **AI hand peek** — overlapping **fan** of face-down `Card.tscn` instances
  scaled to `AI_HAND_SCALE` (0.45). Built BEFORE the top panel so the panel
  z-orders above and clips the cards' top portion — only the bottom strip
  protrudes below the panel, just enough to convey hand size without revealing
  card data. Synced via `update_ai_hand_visuals()` from
  `CardPhaseManager.do_battle_turn`, `_effect_draw`, `_effect_discard`, and
  `_effect_exhaust_choice`. `pop_ai_hand_card_node()` reparents the rightmost
  back to `_bs.canvas` for `AiCardPlayer`'s fly-to-centre animation.

  **The fan is the player hand's fan flipped top-to-bottom.** Every card centre
  rides one circle whose pivot sits *above* the row, so θ=0 is the **lowest**
  point of the arc — the middle card protrudes furthest down past the panel and
  both ends curl back up under it. Per card *i* of *n*:

  | | |
  |---|---|
  | `θ_i` | `(i − (n−1)/2) · step` |
  | centre | `pivot + R·(sin θ, cos θ)` — note `+cos`, which is what inverts the arc |
  | tilt | `−θ_i` (mirrors the player fan's lean without standing the cards on their heads) |
  | pivot | `(540, AI_HAND_TOP_Y + CARD_H·AI_HAND_SCALE/2 − R)` |

  `AI_HAND_FAN_RADIUS` = 620, `AI_HAND_FAN_STEP_DEG` = 3.2, and
  `AI_HAND_FAN_MAX_SPREAD_DEG` = 28 caps the total angular width, so the row
  redistributes rather than growing — the same rule the player hand follows.
  Adjacent centres land `R·sin(step)` apart: **34.6 px against a 72 px card**
  (uncapped, ≤ 9 cards) tightening to 26.9 px at the 12-card end, i.e. always
  overlapping. Measured spans: 5 cards → 210 px, 8 → 313 px, 12 → 372 px, with
  the outermost card riding 3.9 / 11.6 / 18.3 px above the middle one.
  `position` is `centre − CARD_W,CARD_H/2` with **no scale correction** — a
  Control's visual centre is `position + pivot_offset`, invariant under both
  rotation and scale (see `card_phase/README.md`), and `pivot_offset` must be
  set explicitly or the cards rotate about their top-left corner.

  **`ai_hand_left_anchor()`** re-runs that same solve for index 0 of a hand one
  card **larger** than the current one, so it answers "where would the next
  leftmost AI card sit?". Its only consumer is the objective reward FX
  (`objective/ObjectiveRewardFx.gd`) — when the enemy takes Herald / Dragon, the reward
  cards fly into that point. The AI's *deck* is nowhere on screen, so the hand's
  left edge is the only coordinate that can say "this became theirs".

  **`pop_ai_hand_card_node()` does not reset rotation** — the popped card keeps
  the fan's `-θ`, and `AiCardPlayer._show_card_centre` tweens it to 0 during the
  fly-out. Without that the AI's played card stood at the centre of the screen
  visibly tilted, flipped over, and vanished still crooked.
- **Enemy strip backplate (뒤판)** (`_enemy_strip_bg`) — one plate that extends the enemy
  pilot strip by `ENEMY_BG_PAD` (10) on every side. **It is not a full-width panel**: the
  elapsed-time clock and the two objective clocks stand **outside** this plate with no
  background. Same colour / border as the ally strip backplate
  (`STRIP_BG_COLOR` / `STRIP_BG_BORDER`), and still opaque, so it acts as the screen
  that hides the top of the opponent's (상대) hand peek (the peek fan stands at the
  horizontal centre of the screen, so it fits entirely within the strip width). The ally
  strip sits below the hand row — see the Pilot strip section below.
- **Deck / Discard card piles** (in the gutters either side of the card row) —
  `_bs.pile_deck` (left) and `_bs.pile_discard` (right), two `CardPileStack`
  controls. CardPhaseManager pushes the count on every draw / play and tweens
  it during a deck/discard reshuffle. Built by `_build_hand_indicators()`.
  **Both piles are also buttons**: a transparent flat `Button`
  (`_make_pile_button`) covers each one — `CardPileStack` sets itself to
  `MOUSE_FILTER_IGNORE` and takes no clicks of its own — and opens
  `CardPileViewer` on that pile. `_update_pile_buttons()` runs from
  `update_hud()` and gates both on `CardPhaseManager.can_browse_piles()`
  (operation phase (작전 단계) only), fading the piles via `set_dimmed(true)` while disabled.
  See `card_phase/README.md` → Browsing the Deck / Discard lists. The gutter is
  **not** `BS_HAND_AREA_MARGIN` —
  `BS_HAND_WIDTH_SCALE` widens the card row past it, so the gutter is derived
  as `min(BS_HAND_AREA_MARGIN, (screen_w − BS_HAND_WIDTH) / 2)` (89px at 1080)
  and the title font shrinks with it (22 → 20) so "Discard" still fits and no
  card ever overlaps a pile. The inset is **4px** (the old labels used 8) —
  the pile's width *is* the card's width, so it takes everything the gutter has.

  > **This spot used to be a single two-line `Label`, `"Deck\n18"`.** The number
  > was readable, but the pile didn't look like an object, so nowhere on screen showed
  > where cards entering the hand came from or where discarded cards went.
  > `lbl_deck_count` / `lbl_discard_count` disappeared then.
- **Strategy point donuts ×2** — `CostDonut` ring gauges in the **left-hand** gutter
  (see below). Built by `_build_cost_donuts()`.
- **Ally pilot strip** (y 1766..1888) — below the hand row. This used to be empty
  (where the bottom cost bar and the rectangular phase-skip button were removed). The
  bottom ~32px is left for the iPhone home bar / system gestures. `_build_player_strip()`.
  **One backplate `Panel` lies behind it** (`PlayerStripBackdrop`, y 1756..1898) —
  see "Ally strip backplate" in the Pilot strip section below.
- **Victory panel** — Win/lose label + Play Again button.
- **Turn announcer** (built last, full-screen Control overlay) —
  `play_turn_announce(is_player)` sweeps a 110-px-tall coloured bar in
  from the centre with the message "당신의 차례" (Your turn) (blue) or "상대 차례"
  (Opponent's turn) (red), holds, then fades out. Awaitable; `CardPhaseManager.start_card_phase`
  blocks the player hand on the player banner, and
  `CardPhaseManager._run_ai_turn` runs the enemy banner **when the AI's own
  operation points (작전 점수) reach `PHASE_THRESHOLD`** — not when the player passes the turn.
  Passing the turn (`end_card_phase`) shows no banner at all. The on-screen
  battle log was removed; `_bs.last_log` is still updated by effect handlers
  but renders nowhere.

Buttons removed: **Next Turn**, **Auto Play** and the rectangular
**단계 넘기기** (Skip phase) button are all gone — BATTLE auto-ticks every
`AUTO_PLAY_INTERVAL` (0.5s) inside `BattleSim._process()`, and ending the
operation phase is now done by tapping the player's strategy point donut twice.

Connections:
- `cost_donut.end_turn_pressed` → `_bs.card_phase.end_card_phase` (the manager
  also re-checks `can_end_card_phase()` defensively)
- Play Again button → `_bs._on_restart_pressed`

### Strategy point donut (`CostDonut.gd`)
Both sides' operation points read out on a ring gauge in the **left-hand** gutter
(`x = BS_HAND_AREA_MARGIN / 2`, i.e. 65 on a 1080-wide screen). The donut column
and the targeting overlay's "확인" (Confirm) / "취소" (Cancel) row sit on **opposite** sides of the
screen: donuts left, buttons bottom-right.

| Donut | Position | Interactive |
|---|---|---|
| `_bs.cost_donut` (player, blue) | above the Deck counter, one button-band above the hand row → centre (65, 1294) | yes |
| `_bs.cost_donut_enemy` (enemy, red) | top-left, under the AI hand peek → centre (65, 255) | no |

Measured at 1080×1920: player (65, 1294), enemy (65, 255); the Deck label sits at
x=8 in the y-band 1440..1660, so the donut (x 9..121, y 1238..1350) clears it
vertically. The player donut's y is derived from `BS_HAND_CENTER.y`, so it moved
up with the hand row when the battlefield shrank to 90% — nothing here is a
literal.

- Ring is full at `PHASE_THRESHOLD` (game_config.csv); the number in the middle is the raw
  point total, so boost cards read as "a number above the threshold on a full ring".
- Fill sweeps clockwise from 12 o'clock (`START_ANGLE = -PI/2`).

**Player flip → "턴 넘기기"** (`CostDonut` owns the whole interaction):
1. tap the donut during the operation phase → the ring unwinds through empty and
   re-winds counter-clockwise (`_sweep` tweens `ratio*TAU → -TAU`) while the
   face swaps from the number to "턴 넘기기".
2. tap it again → `end_turn_pressed` fires (only while `set_end_enabled(true)`;
   a disabled face renders grey and swallows the press). `set_end_enabled`
   repaints the caption as well as the ring, independently of the value — so a
   state change that arms or disarms the button without moving the point total
   can't leave a white ring under a grey "턴 넘기기".
3. tap anywhere else → flips straight back to the point readout. That press is
   deliberately left unhandled so whatever was actually clicked still reacts.

Input runs through `CostDonut._input`, not `_gui_input`: hand cards call
`accept_event()`, so a `_gui_input`/`_unhandled_input` pair would never see the
outside tap. Presses landing inside the donut are consumed with
`set_input_as_handled()`.

State setters driven from `HudBuilder._update_cost_donuts()`:
`set_value(cost, PHASE_THRESHOLD)`,
`set_flip_allowed(in_card_phase and not modal_up)` where `modal_up` is
"Deck/Discard browsing (열람) is open **or** the battle-opening VS confirm screen is up" (turning it off
un-flips). Both clauses are load-bearing for the same reason: `CostDonut`
listens on `_input`, which runs ahead of GUI picking, so it stays tappable
straight through either dim. The VS screen matters because `game_phase` is
still CARD_PHASE while it is up — the arena has not opened yet, so
`in_card_phase` alone lets the donut through.
`set_end_enabled(can_end_card_phase())` — **true throughout the operation phase**, and false
only in states where closing now would cut something off, such as a banner / modal /
charge (돌진) animation. Passing without playing a single card is allowed
(see `card_phase/README.md`). `set_locked(…)`
still exists on `CostDonut` but **nothing calls it any more** — targeting stopped
being modal, so there is no state that needs the flip blocked. The donut's y is
still derived from `CardTargetingOverlay.BTN_HAND_GAP + BTN_H` so it keeps the
same vertical band the "확인"/"취소" row occupies on the far side of the screen.

### Deck / discard piles (`CardPileStack.gd`)
A `Control` that draws a **stack of cards lying down, tilted away** in the gutters either
side of the hand row. It looks like face-down cards piled on top of each other, and it is
itself both the counter and the target of the browse button.

**Two things make it "lie down".** (1) The height is squashed by `FORESHORTEN` (0.55),
killing the card's 220/160 ratio, and (2) the **top edge is drawn narrower than the
bottom edge** (`TOP_EDGE_SCALE` 0.78) to add perspective. A rectangle that is merely
flattened reads as a thin card, not a card lying down. `FORESHORTEN` started at 0.42 and
was raised to 0.55 — tilt it further and the top card's face gets thinner than the
number, so it becomes a band instead of a card back. There is vertical room equal to the
hand row height (220px) and the stack uses less than 100px, so there's no reason to
skimp.

**Layers stack upward.** Each higher layer shifts **up** the screen by `LAYER_DY` (5.5px),
so the front edges of the cards below poke out **under** the stack, giving a pose looked
down on obliquely from above. The last layer drawn is the top card, and the count is
printed in the middle of that card's back (with an outline underneath — in some frames
it overlaps the bright edges of the layers below). The title ("Deck" / "Discard") is a
`Label` child below the stack.

**Thickness = count.** Visible layer count is `ceil(count / CARDS_PER_LAYER)` (one layer
per 4 cards), capped at `MAX_LAYERS` (8). **The baseline is fixed and the stack only
grows upward** — if the vertical centre were fixed, the whole stack would jitter up and
down every time a card came or went. The space is always reserved for `MAX_LAYERS`.
`set_count()` takes a `float`: the reshuffle tween in
`CardPhaseManager._animate_reshuffle_counts` rolls in fractional values, so the thickness
grows and shrinks on the same curve as the number. At 0 cards, one empty slot with only
its border remains, with a faint "0".

The top card's back colour (`BACK_FILL` / `BACK_LINE`) is the same value as
`Card._apply_back_style`, so it reads as the same object as the face-down cards in hand.
**The back is painted uniformly in this one colour** — it used to overdraw an inset
trapezoid in a per-pile accent colour (deck purple / discard reddish-brown,
`HudBuilder.PILE_ACCENT_*`), but the stack is small, so that frame read as **a gradient
sitting on the face** rather than a pattern. The title labels below already tell the two
piles apart, so there's no reason to separate them by colour too. The `accent` argument
and the `PILE_ACCENT_*` constants disappeared at the same time; `setup()` is
`(title, font_size)`.

Measured (1080 wide, 81px gutter): one card 61px · 8-layer stack 99.5px · number font 27.

#### Cards coming and going = ghosts (`play_pop` / `play_land`)
If only the number changes, nothing on screen shows that a card **came out of the pile /
went into the pile**. So the stack draws one more **ghost** shaped like the top card — it
is not a node but a single trapezoid inside `_draw()`, so it has no effect on layout ·
input · z-order, and the ghost is **not drawn behind** the stack (if it's hidden, half the
motion disappears).

| | Direction | Alpha | Called from |
|---|---|---|---|
| `play_pop()` (deck) | **up** from the top card by `GHOST_RISE_PX` (74px) | 1 → 0 | `CardPhaseManager._play_draw_intro` ⓪ |
| `play_land()` (discard pile) | settles **down** from that height | 0 → 1 | `CardPhaseManager._notice_discard_gain` |

- One card takes `GHOST_SEC` (0.26s). Ghosts must be able to run **several at once**
  (opening (개시) 5 cards · draw:N · discard:N), so they're driven by a `_ghosts` array +
  `_process` rather than tweens. Each entry carries its own `delay` and progress so they
  don't cut each other off. `play_burst(land, n, delay)` pushes them in
  `GHOST_STAGGER_SEC` (0.08s) apart.
- **Seam with the draw**: the entry from the left starts not after the ghost has fully
  vanished but when `GHOST_HANDOFF_ALPHA` (0.30) of its alpha remains — starting after it
  fully vanishes makes it look choppy, as if one card came out twice. That moment comes
  from one place, `CardPileStack.ghost_handoff_delay()` (= 0.182s).
- **The seam with discard, conversely, does not overlap.** The landing ghost departs
  **after** the hand card has finished falling (`CardPhaseManager.PILE_LAND_DELAY_SEC` =
  `Card.DISCARD_FADE_SEC` 0.30s) — a draw is a picture of one card running on from deck to
  hand, so they must overlap; a discard is a picture of a card that left the hand
  **arriving** at the pile, so they must be joined end to end. And **the number and
  thickness rise only after that ghost has fully settled**
  (`CardPhaseManager._discard_pending` / `_commit_discard_gain`) — the moment the card
  touches the stack and the moment the pile gets thicker coincide.

### Pilot strip (`PilotStrip.gd`) — enemy on top / ally at bottom
All ten used to be crammed **inside the top panel** in 84px slots (ally left / score
centre / enemy right). Faces were 76px squares so you couldn't tell who was who, and the
two teams sat on the same row, so which one was your team wasn't obvious at a glance.
Now it's split into two copies:

| Strip | Position | Size | Input |
|---|---|---|---|
| Enemy (`_enemy_strip`) | direct child of the canvas, `ENEMY_STRIP_RECT` (137, 46, 806×100) | portrait 145×60 | press for detail panel |
| Ally (`_player_strip`) | **below** the hand row, `PLAYER_STRIP_RECT` (25, 1766, 1030×122) | portrait 190×79 | press for detail panel |

**The enemy strip is 66% of the ally one** and sits horizontally centred. Its size has
changed four times: it started as a 730×84 shrunken version (portrait 130×54) — showing
the same faces at two very different sizes top and bottom meant neither who the opponent
was nor the opponent's growth points read as well as the ally side — so it was enlarged to
**exactly** the ally's 1030×122 (that's when the top panel grew 130 → **168** and the chain
below it moved down 38px). The reason for shrinking it again is space: when the objective
spawn clocks moved from the battlefield tiles up to this panel, **cells for icon + turn
count on either side of the strip** were needed (`ObjectiveTimer.gd`). Growth points are
still readable up to two digits, so the original purpose of "compare side by side with
mine" survives.

The 60% of that time (618×76, portrait 108×45) fell below the minimum at which you can
tell whose face it is. The current value **enlarges only the portrait by 10%** — portrait
width is derived from cell width (`setup()` uses `_cell_w − 16`), so the only way to
enlarge it is to push the strip width by the same ratio (618 → **672**), and the height
follows the eye ratio (2.4:1) up from 76 → **81** too. The side margins shrank by that
amount so the clock cells went 190 → **168**, and the strip x moved 231 → **204** to stay
centred.

**The growth point font is the same on both strips** (`ENEMY_SCORE_FONT` =
`PLAYER_SCORE_FONT` = 20). The ally portraits are bigger, but that number exists **to be
compared side by side with mine**, so different sizes would give the two numbers read on
the same line different weight — faces may be small, numbers may not. The old 14 was a
value derived from cell width back when the strip was shrunk to 60%.

**The role tag was deleted.** It was a cell that printed a single letter `T` / `F` / `A`
on a dark plate at the portrait's bottom-left, but **the strip's seat order itself
already is the role** (`GameEnums.ROLE_DISPLAY_ORDER` — 탑 · 정글 · 미드 · 원딜 · 서폿
(top · jungle · mid · ADC · support), the same table as the outgame screens). It said the
same thing twice and just covered the bottom of the face. To bring it back, restore the
three `ROLE_TAG_*` constants and the two nodes `tag_bg` / `role_lbl` in `_build_cell`
together.

**Both sides are pressable.** Enemy pilots open through the same gate as allies
(`PilotDetailPanel.can_open`) with the same content (in-game · pilot · mech (메크)) — the
opponent roster has already come in as `match_ctx.enemy_roster`, so
`BattleSim.player_data_for` finds it directly at indices 5..9.

A cell is, top to bottom, **eye-level portrait → HP bar → growth point number**.

- **Eye-level portrait** — `PilotImages.eye_for(pilot_id)`. `eye/N_eye.png` is a
  **480×200 crop cut wide horizontally so both eyes show**, and the cell height is derived
  from that ratio (`EYE_ASPECT` = 2.4) — stretching to an arbitrary height distorts the
  face. With no image (standalone run / INTL) the backing `ColorRect` simply shows.
  The border is a team-coloured `Panel` frame; a downed pilot is darkened via `modulate`
  and the **number of turns until revival** is printed in a large font in the middle of
  the portrait.
- **HP bar** — **two `ColorRect`s** (backing + fill). **Do not use `ProgressBar`**: it
  computes a minimum size from the theme stylebox's content margins and pulls `size` up to
  it (about 24px with the default theme), so even when a 6–10px bar was requested it drew
  at 24px and overwrote the growth point label right below (confirmed by measurement (실측)).
  When a shield is attached the fill turns yellow — the reason for not appending a segment
  to the bar is that at 6–10px it's too thin for the two sections to be distinguishable.
- **Growth points** — `BattleSim.fmt_score(p.score)` → `"24.9k"` (decimal places drop as
  digits grow: `1.00k` → `24.9k` → `125k`). **It's a number, not a gauge** — there's no
  cap, so there's nothing to fill against. It opens at `SCORE_START` (const.csv) and climbs
  through the match, a well-fed carry well ahead of the rest. It corresponds to the gold display of a MOBA broadcast,
  and **this number drives that pilot's attack multiplier** (`GROWTH_ATK_PER_SCORE`, const.csv) — it reads, on the
  number side, the same growth that makes the HP bar two rows up actually get longer. For
  the accrual rules see the `SCORE_*` section of `BattleSim`.

Cell order is **the order you sweep the battlefield from left to right** — **left →
jungle → centre → right ×2** (`HudBuilder.LANE_SEAT_ORDER`). Using the `LanePosition` enum
order as-is (LEFT · CENTER · RIGHT · GUERRILLA) seats the jungler in the fifth cell
**after** the right laner, but the jungle lies **between** the left and right lanes on the
map, so that seat corresponds to nowhere on the battlefield. Sorting is done **on a copy
of `_bs.pilots`** — the original must keep spawn order (= role order) so that
`BattleSim.player_data_for` can find the roster by that index.

**The bottom strip's y (1766) is computed from the bottom edge of the cards.** The cards
at both ends of the fan sag 21.4px below the middle (at 12 cards) and grow by
`Card.HOVER_SCALE` (1.2) when hovered/selected, so in the worst case the card's bottom edge
comes down to y ≈ 1763. At 1724 the cards covered the top of the portraits (confirmed by
measurement).

**Ally strip backplate** — `PlayerStripBackdrop`, one dark `Panel` that extends the strip
area by `PLAYER_BG_PAD` (10px) on every side (y 1756..1898). Colour and border match the
top panel. The enemy strip sits on the top panel so it had backing from the start, but the
ally strip floated directly on the screen, so the three rows face · HP bar · growth points
looked scattered with no background — growth point numbers in particular, without backing,
don't show where one pilot's cell ends. **`_build_player_strip()` adds it before the
strip** (sibling z-order is child index, so if added later the plate covers the portraits)
and **`set_strip_visible(0, on)` hides it together with the strip** — if the detail panel
cleared only the strip, an empty plate would be left alone on top of the dim.

**Input gate**: `set_interactive_enabled(pilot_detail.can_open())` — outside the
operation phase · auto-run (BATTLE) (engage stage (교전 무대) · before the opening · match
over), the hit buttons are `disabled`. Hit testing is taken by a transparent `Button`
covering the whole cell (`Label` / `TextureRect` default to `MOUSE_FILTER_IGNORE` by
class, so they can't receive clicks themselves).

### Objective clocks (`ObjectiveTimer.gd`) — either side of the enemy strip
Two `Control`s, each a pair of **one icon + turns remaining**. Left is Herald (purple flag),
right is Dragon (vermilion wings) — **the same left/right arrangement as the cells where
the two objectives stand on the battlefield**, so the position is the name. That's why
there are no name labels.

- State comes only from `ObjectiveSystem.turns_until_cell(cell)`. Updating is just
  `HudBuilder.update_hud` calling `queue_redraw()`.
- **Icons are shapes, not images** (same approach as the kill log glyphs). All
  coordinates are written **on a 64×64 basis** and moved by multiplying only by
  `ICON_SIZE / 64`, so changing the size doesn't require redoing the numbers.
- **The cell is set by the margin the enemy strip leaves.** When the strip grew 20%, this
  cell became 168 → **101×60**, and the clock was trimmed in two places to fit that width —
  the icon-to-number gap `ICON_TEXT_GAP` 10 → **4**, and the **"턴" (turn) text next to the
  number was deleted entirely** (`UNIT_FONT_SIZE` / `UNIT_COLOR` disappeared with it). A
  number stuck next to the icon can't be anything other than turns remaining, so that text
  only pushed the number away. This is a panel where faces must read first, so when
  fighting for space, the clock always gives way.
- `ICON_SIZE` stays **49**. At one point the icon was 62 and the cell height was the whole
  strip band (122) — on the grounds that bigger reads better in peripheral vision — so the
  clocks stuck out above and below the portraits, became the biggest object in the top
  panel, and grabbed the gaze that should go to the faces first. Now the icon is slightly
  smaller than the portrait (60px) and vertically centred, so left clock · five faces ·
  right clock read as one row.
- **It can be pressed.** `mouse_filter` went IGNORE → **STOP** and it fires
  `timer_pressed(kind)`. `HudBuilder._on_obj_timer_pressed` receives it and calls
  `BattleSim.objective_reward.toggle(kind)` — pressing the same clock again closes it, so
  the handle that opens is also the handle that closes.
- Dragon's wings are **smooth four-vertex triangles**. At first they had serrations
  underneath like bat wings (eight vertices), but shrunk to that size the serrations mushed
  together and looked like **a single leaf** — at this size what makes the silhouette is
  not detail but the angle of two big triangles.
- The number is placed in the middle of the remaining width (so its position doesn't
  wobble between one and two digits). The panel background is dark and thin text gets
  buried, so a black outline is laid down first.

This number was once **on the battlefield tile** (`BattleRenderer._draw_objectives`).
When that cell went back to being an ordinary jungle cell, the camp outline · capture fill
colour · pilot portraits were already using it, and two lines of text became a fourth
guest.

### Objective reward preview (`ObjectiveRewardPopup.gd`)
An **info popup** that opens when a clock is pressed. Drawn on its own `CanvasLayer` (12).

```
[full-screen dim α 0.78 — tap anywhere to close]
└─ plate 560×content (centre of screen, border = objective colour)
     ├ 전령 / 용                    (40pt, purple / vermilion)
     ├ N턴 뒤 등장                  (24pt)  ← ObjectiveSystem.turns_until_cell   ("spawns in N turns")
     ├ 보상: [전령 제압] — …        (24pt)  ← ObjectiveSystem.reward_text        ("Reward: [Herald Subdued] — …")
     ├ one reward card (Card.tscn at native size) + ×N on the right if several
     ├ 획득 즉시 손패로 / 덱에 섞여  (22pt)   ("straight into hand on capture / shuffled into deck")
     └ [닫기]   (Close)
```

- **Why it exists.** An objective is an event where you choose to participate / not
  participate, but what it gives was nowhere to be seen throughout the match, except one
  line in the decision window that pops up on the turn the showdown is imminent. Whether to
  push the lane or send the jungler depends on knowing what the reward is worth.
- **It doesn't hold the battlefield.** Unlike `ObjectiveSystem`'s participation decision
  window it's pure information, so `BattleSim._battle_tick_held()` does not read this
  popup — the BATTLE auto-tick and the MM:SS clock keep running as usual. Instead the dim
  is STOP, so it swallows input behind it.
- **The card is a real `CardData`** — `CardPhaseManager.make_objective_card(id)` takes it
  straight from `cards.csv` (reward cards are `pool = 0`, so this is the only path by which
  they come into the world). A separately drawn picture would give no way to confirm it's
  the same thing as the card that actually lands in hand. The card has no caster (시전자)
  (`owner_pilot == null`), so the portrait spot is empty — exactly how it'll look in hand.
- If the card doesn't come out of the DB (`make_objective_card` → null), only a one-line
  notice stands in its place. A single popup doesn't stop the match.

### Pilot detail panel (`PilotDetailPanel.gd`)
A **modal** that opens when you press a face on a strip (**both ally bottom / enemy top**).
It draws on its own `CanvasLayer` (13), so it sits above discard (10) / targeting (11) /
browse·engage (12).

```
[full-screen dim α 0.88]
├─ 2 arts (ArtHolder) — pilot and mech share the two slots front / back
│    front: bright, horizontal centre ART_FRONT_CENTER_X(320), height ART_H(1400)
│    back: +ART_BACK_SHIFT_PX(400) to the right, ×ART_BACK_SCALE(0.90), dimmed with ART_BACK_TINT
│    both have their bottom at ART_BOTTOM(2010) — below the screen (1920), so **the bottom is cut off**
├─ (in-game tab) lasting effect thumbnails — **bottom-left of the illustration**, from x 26, 68×68,
│    only those currently applied. No title. Bottom edge attached to the card row title; grows **upward**
├─ header (own backing Panel, y HDR_TOP 424 .. HDR_BOTTOM 562) — **separate from tabs, always the same content**
│    pilot name (40pt) ─────────────────────────────────  growth points (40pt, right)
│    mech name    (24pt, line below)
├─ 3 tabs  [인게임][파일럿][메크] (In-game / Pilot / Mech)  STAT_X 600, width 452/3, TAB_H 62, top = header bottom
├─ right: detail panel  STAT_X 600, STAT_W 452, STAT_TOP 650 (backing Panel grows to fit content height)
│    ├ stat chips 3 columns × N rows  (chip 141×92, small name on top / large **final value** below)
│    └ (in-game tab) pilot skill block — name + type badge / keywords / description / state / [사용] (Use)
├─ bottom: [닫기] (Close)  backing bottom + BTN_GAP_Y(24) — moves down with each tab
└─ full width at screen bottom: **fan of held cards** — Card.tscn ×1.60 = 256×352,
     one title line (centred) + the same fan as the hand. With 6 cards: spacing 144 · ends ±8.6°
```

| Tab | Art in front | Chips | Below that | Bottom fan |
|---|---|---|---|---|
| 인게임 (In-game) | pilot | HP · attack · growth · battlefield/engage hit (명중) · evasion · presence (체력 · 공격력 · 성장 · 전장/교전 명중 · 회피 · 존재감) | (when dead) `부활까지 N턴` → **pilot skill** | **all 6 held cards** |
| 파일럿 (Pilot) | pilot | six player (선수) stats | — | 3 pilot cards |
| 메크 (Mech) | mech | HP · attack · presence (체력 · 공격력 · 존재감) | — | mech cards (2–7 per mech) |

- **The header is separate from the tabs** (`_build_header_block`, runs **only once** in
  `_build`). Name · mech name · growth points belong to the same pilot whichever tab you
  view, so there's no reason to rebuild them on every tab change. This line used to be
  inside the body, and on the mech tab the title changed to the mech name, so **the pilot
  name and growth points vanished from the screen entirely** — in effect, who was open
  wobbled with the tab. The only thing a tab changes is the detail panel below it.
- **The mech name is small on the line below the name, always visible.** It's not a value
  you should have to go into the mech tab to learn. **It used to be appended to the right
  of the name with an `HBoxContainer`**, and since the line's start point was the name's
  width, the mech name started at a different x for each pilot — in effect, where to look
  for the mech name wobbled per pilot. Stacking two lines makes the start point always the
  same and removes the need to measure text width, so the container itself disappeared
  (each line uses `clip_text`). To fit two lines `HDR_TOP` went up 452 → **424** —
  `HDR_BOTTOM` (562) is the top edge of the tab bar and is pinned, so the extra height
  could only go upward.
- **The in-game tab shows all 6 cards** (pilot 3 → mech 3 order, so the left half of the
  fan is the person and the right half is the machine). What this pilot started holding is
  information that must be on one screen; splitting 3 cards each across two tabs as before
  meant switching tabs to compare the six. The pilot / mech tabs also put that tab's cards
  in the same spot.

- **Stats are chips, not rows.** It used to be two-cell `key ─ value` rows running a dozen
  or so lines down, which meant (1) nothing but order said which value mattered and (2)
  brackets like `(기본 N)` `(N턴)` `(기본 N / N)` (base N / N turns / base N / N)
  trailed behind the values, so reading **what it is right now** took time. Now one chip
  carries just **one final value**, large. `_row` / `_section` / `ROW_H` / `KEY_FRACTION` /
  `SECTION_GAP` were **deleted** at the same time.
#### Info panel — one plate shared by stat chips · lasting effects · cards
Pressing any of the three opens the same plate (`MENU_W` 372) **to the left of the info
column**. "What am I looking at now" must be one thing at a time; with separate plates, a
stat explanation and an effect explanation would show at once and blur which one you just
pressed. There are two reasons for opening to the left — on the right there are only 28px
to the screen edge (1080), and overlaying it on the pressed item would hide the chip you
just pressed under its own explanation.

The vertical position is **the same height as the pressed item**, with `card:` keys as the
only exception. Chips and effects are on the left side of the column · screen, so that rule
points to the empty space beside them, but cards are in the fan at the bottom of the screen,
so the same rule points **on top of the card you just pressed** — the plate covers that card
entirely. So for cards it is lifted to sit above the card row title (`MENU_CARD_GAP_Y` 14).
x stays on the left, so it doesn't cover the close button at bottom-right.

**Everything pressable is collected in one table, `_targets`** — `key → {button, style, …}`.
The key prefix distinguishes the kind.

| Key | What | Title | Rows (`_menu_rows`) | Note (`_menu_note`) |
|---|---|---|---|---|
| `hp` `atk` `growth` … | stat chip | chip name | base value · increase · final | what that value decides |
| `fx:lane` `fx:rate` `fx:atk` `fx:shield` | lasting effect (slot) | full effect name | where it multiplies · time remaining · final value | one-line rule |
| `fx:src:<종류>\|<카드>` `fx:rest:<종류>` | lasting effect (per card · remainder) | card name / kind name | this effect · time remaining · **total for that kind** · final value | one-line rule |
| `card:<slot>:<i>` | card | card name | cost · type · category · position · keywords · tokens (category/position only for pilot cards, tokens only for cards that use them) | **the card's description text verbatim** |

- **The backdrop forwards clicks** (`_on_menu_backdrop_input`). The backdrop is still a
  full-screen STOP, but instead of closing unconditionally as before, it finds the **target
  button / tab / close** at that coordinate and presses it on your behalf. Previously, with
  the attack explanation open, pressing the hit chip spent the first click on closing, so
  you had to press **once more** — while skimming six stats the clicks doubled and the
  screen flickered between open↔closed. Switching between items is the info panel's default
  behaviour. Pressing an empty spot closes it then. Coordinate testing is simple because
  `_menu_root` · `_body_root` · `_root` are all full-screen `Control`s placed at (0,0), so
  the buttons' `position` can be compared as-is.
- **Plate height is set by content** — row count × `MENU_ROW_H` + the **actual** height of
  the note text (`_text_height`). When measuring the note height **the line-break flags must
  match the Label**: `get_multiline_string_size` defaults to
  `BREAK_MANDATORY | BREAK_WORD_BOUND`, but the label is `AUTOWRAP_WORD_SMART` (which adds
  `BREAK_GRAPHEME_BOUND`), so measuring with the default sometimes has the label use one more
  line and the last line is clipped outside the plate (measured: measured as two lines, drew
  three).
- **Turn on wrapping before setting size.** The `Control.size` setter clamps the request up
  to the minimum size once, and the minimum width of a `Label` with wrapping off is **the
  full width of the text laid out on one line** — requesting 332px in that state inflates the
  label to the text width, and turning wrapping on afterwards doesn't shrink the already
  enlarged rect. On screen the first line stuck out of the plate and the lower lines looked
  clipped (confirmed by measurement). `clip_text` is also turned on before size for the same
  reason.
- **The name cell is 42%** (`MENU_KEY_FRAC`), the rest is the value cell. Back at 52%,
  values like "다음 작전 단계까지" (until the next operation phase) didn't fit in 159px and
  **were clipped from the left** — a right-aligned `Label` that overflows gives up alignment
  and draws from the rect's left. The value wording itself got shorter then too
  (`작전 단계까지` / `레인 전용`).
- **The tab decides which art is front and back** (`_apply_focus`). On the mech tab the
  machine is in front; otherwise the person is. The old **"전환" (Switch) button (pilot ↔
  mech two-state toggle) was deleted** — once the info split into three, a two-state toggle
  could no longer say what was where. The switch tween (`ART_SWAP_SEC` 0.22s) remains.
- **The large number on the right of the header is growth points.** The old subtitle
  (`역할 · 아군/적군 · 성장치`) was deleted — role and side are already told by the portrait
  you just pressed, and growth points aren't a value to bury at the end of a subtitle but
  the first number by which you read this pilot. The `라인 / 위치` row was deleted too (the
  portrait's spot on the battlefield already says it). Since the header moved out of the
  tabs **it stays visible on the mech tab too** — previously on that tab the title became
  the mech name and the number disappeared.
- **The bottom of the screen crops the art.** The bottom edge (`ART_BOTTOM`) is off-screen,
  so the lower legs are cut off. The old `_knee_crop` (which cut the texture via
  `AtlasTexture.region` at `KNEE_FRACTION` 0.80 of the alpha silhouette height) was
  therefore **deleted** — cropping is now done by the screen edge, and where it cuts is
  decided by two constants, `ART_H` and `ART_BOTTOM`.
- **Size is normalised by height.** Every full-body art has the figure filling a height of
  1024, with only widths varying 572–756, so fitting by width would make the figure's height
  differ per image. Width comes from the source ratio, so `ART_H` is how much of the screen
  it fills — at 1400 the width is 900–1030, and any bigger pushes the mech standing behind
  completely off to the right.
- **When stepping back, the node size stays and only `scale` shrinks.** `pivot_offset` is
  the node's **bottom centre**, so the baseline stays put as it shrinks — the two arts read
  as standing on the same floor, and the switch tween only has to touch three things:
  `position` / `scale` / `modulate`.
- **All 30 mech arts are in.** `MechImages.full_for(mech.id)` looks up
  `res://resources/images/mech/{id}_full.png`. Unlike the pilot arts, widths don't vary —
  it's a **fixed 1024×1024 canvas**, so every mech takes the same width in the panel (it
  stops height normalisation from converting an outstretched weapon into width). Source and
  the id ↔ mech table are in `resources/README.md`.
  The fallback for a missing file is still alive — a faint silhouette slab + mech-name
  placeholder stands in the same spot. The slab alpha is 0.30 — raise it and it becomes a
  bright half-screen rectangle that stands out more than the pilot actually in front.
- **The info block is at the bottom** (header 452 / tabs 562 / `STAT_TOP` **650**). As the
  art grew, the upper half of the screen became the place for the figure's head·upper body,
  and stats left in their old spot (170) would cover the face. A backing `Panel` (α 0.86) is
  laid behind the text — the art comes up to this area, so text alone would be unreadable
  over the illustration. The active tab **doesn't draw its bottom border**, so it joins the
  backing as one piece.
- **The close button follows the backing's bottom edge** (`_reposition_close`). Content
  height differs per tab (in-game ~360 / pilot ~600), so pinning it in one place leaves just
  the button floating in the middle of the screen on short tabs — that's what the old fixed
  `BTN_Y` (1424) did. Its position changes only **at the moment a tab is pressed**, and
  `refresh()` doesn't touch the backing, so the button doesn't jitter up and down with the
  numbers.
#### Held cards — the same fan as the hand, full width at screen bottom (`_build_card_fan`)
- **The cards are the same nodes as the hand** — `_bs.CARD_SCENE.instantiate()` set up at
  `CARD_VIEW_SCALE` (**1.60**) = **256×352**. Drawing a different picture would break the
  link "this card is that card". With `setup(cd, false, true)` + `MOUSE_FILTER_IGNORE`,
  `Card._refresh_float_state` (= the owner of `scale`) never runs, so the scale given here
  stays as-is.
- **It used to be a 3-column grid inside the info column at scale 0.80 (128×176).** The
  cells were confined to the column (width 452) so they couldn't get bigger than that, and
  description text at that size was a pattern, not something to read. There's no way to
  keep the grid and double the size — 3 columns would be 800px, overshooting the column by
  348px · the right side of the screen by 146px, and 2 rows would also run off the screen
  vertically (panel bottom ≈1700 → 2052). **A fan overlaps the cards**, so it fits the same
  number of cards in the same width while doubling the size per card. Moving it down to the
  bottom of the screen is the same calculation — fanning 6 cards inside the column width
  (452) gives a 26px spacing, so only the cost circles show. `CARD_GAP` / `CARD_ROW_GAP` /
  `CARD_SECTION_H` / `CARD_GRID_COLS` were **deleted** at the same time.
- **The geometry follows the same rule as the hand's fan**: card **centres** ride a circle
  placed below the row (`FAN_RADIUS` 2400), so tilt and vertical sag always agree; the
  middle card is highest and both ends curl down. The node's `pivot_offset` is the exact
  centre, so changing scale doesn't move the centre (anchoring at top-left makes the fan
  drift down-right every time the scale is touched).
- **The margin is set by the tilted corner.** `FAN_MARGIN` (52) accommodates not half the
  card width but **the outer bottom corner of the tilted card** — the ends tilt close to 9°,
  so the tall card goes 27px further out than half its width (with a margin of 24, both ends
  were clipped by 3px — measured). Below, for the same reason, `FAN_DROP_RESERVE` (44) = arc
  sag 27 + corner protrusion 17. The top edge (`_fan_top_y`) is obtained by subtracting those
  two and `FAN_BOTTOM_PAD` (26) from the screen bottom — hard-coding a constant would make the
  fan overflow or float off the screen whenever the scale is touched (**1498** at 1080×1920).
- **Input is taken by bands, not card rects.** Of overlapping cards the later one stands in
  front, so the width of card i that's actually visible runs from its own left edge to **the
  next card's left edge**, and that width becomes one button as-is (the same problem as the
  hand's `_apply_hit_bands`, same calculation). Cards go in `CardFan`, buttons in
  `CardFanHits` **attached after** it, so the buttons always get the pick on top, and the
  z-order among cards only shifts inside `CardFan`.
- **A card whose info panel is open is pulled forward out of the fan** — it rises by
  `FAN_LIFT_PX` (30) and moves to the end of the sibling order (= frontmost). In the grid days
  the button got a border, but in the fan the buttons are bands rather than card rects, so a
  border would wrap a strip rather than the card. `FAN_TITLE_GAP` (64) must be larger than
  `FAN_LIFT_PX` so the raised card doesn't push up into the title.
- **The card list comes from the `BattleSim.starter_cards` table** — it is **not**
  reconstructed by scanning hand · deck · discard pile. An exhausted (`exhaust`) card is in
  none of the three piles, so a reconstruction would silently drop it from the list, but
  "what this pilot came in holding" is a fact that doesn't change during the match. The table
  is written once when `CardPhaseManager._deal_team_deck` goes through the deck — see
  `card_phase/README.md`.
#### Lasting effect thumbnails (in-game tab) — bottom-left of the illustration
**Not in the info column but at the bottom-left of the screen**, right above the card fan
(from `FX_LEFT_X` 26, six cells within `FX_ROW_W` 520). In a 68×68 cell, the top is a
two-character abbreviation (colour per effect) and the bottom is the current value. There
are no icon assets, so **the text is the icon**, and the full name is carried by the title
of the info panel opened by pressing it.

- **It used to sit inside the column, between the stat chips and the cards.** It ate 116px
  there, and the chain below (card row · skill block · close button) was pushed down by that
  much so the in-game tab touched the bottom of the screen. The bottom-left of the screen
  holds only the art's legs and the dim, so it's an empty spot, and moving it lets chips ↔
  skill follow directly in the column.
- **The title ("지속 효과" (Lasting effects)) was deleted.** Inside the column it needed a
  label to separate it from the blocks above and below, but putting an underlined section
  title on top of 68px cells standing alone in a screen corner makes the title stand out more
  than the cells. With no effects applied it **draws nothing** — the old one-liner "걸려 있는
  효과 없음" (No active effects) was a sentence that only made sense with a title.
- **Rows grow upward** (`_build_effect_thumbs` works back from `_fx_bottom_y()`). Letting
  them grow downward makes the second row land right on top of the card fan.

Three kinds are mixed.

**(1) Slot effects** — ones where cards overwrite each other in one slot. Asking for the
source has only one answer, so the kind name is the cell name.

| Key | Shown when | Abbrev. | Source |
|---|---|---|---|
| `fx:lane` | `lane_stat_mod != 0` | 라인 (Lane) | 공격적인 라인전 (Aggressive Laning) (+), skills |
| `fx:rate` | `growth_rate_mult != 1` | 적립 (Accrual) | 신중한 예산 (Careful Budget) · 성장 가속 (Growth Acceleration) (per token) · 소극적인 태세 (Passive Stance) / 완벽한 마무리 (Perfect Finish) — amounts are each card's cards.csv clause |
| `fx:eva` | `eva_card_mod != 0` | 회피 (Evasion) | 소극적인 태세 (battlefield evasion bonus for its clause's turn count, cards.csv) |
| `fx:ambush` | `ambush_hold` | 매복 (Ambush) | 매복 (Ambush) (no movement until the next operation phase) |
| `fx:atk` | `atk_buff != 0` | 공격 (Attack) | temporary attack such as 전투 준비 (Battle Prep) |
| `fx:shield` | `shield > 0` | 보호 (Protect) | 보호 (Protect) cards |

**(2) Per-card lasting effects** — one line of the `PilotData.persistent_fx` ledger is one
cell. There are five ledger kinds — `growth_rate` (accrual %) / `max_hp` / `atk` (value) /
**`atk_pct` / `hp_pct`** (multiplier %, [몰입] (Immersion) · [워밍업] (Warm-up)). Multiplier
kinds are printed as % via `FX_PCT_KINDS`, and the remainder cells are also built by the same
rule from `bonus_atk_mult` / `bonus_max_hp_mult` minus the ledger (영혼 수확 (Soul Harvest)'s
attack % is now visible).
The key is `fx:src:<kind>|<card name>` and the abbreviation is the first two characters of
the card name (excluding spaces: `용 보상` → `용보`). This side used to be lumped by attribute
too, so **one `fx:perm` cell meant both [용 보상] (Dragon Reward) and [핫핸드] (Hot Hand)**,
and [붉은 가루] (Red Powder) · [녹색 병] (Green Bottle), which live in `bonus_max_hp` /
`bonus_atk_flat`, **weren't shown at all** — they are values living in separate fields so
the growth recalculation doesn't wipe them, so they weren't carried on any chip.

| Kind (`PilotData.FX_*`) | Total slot | Cards currently using this kind |
|---|---|---|
| `growth_rate` | `growth_rate_bonus` | 용 보상 · 핫핸드 (`growth_perm`) · 파란 약 (Blue Pill) (`growth_eff`) |
| `max_hp` | `bonus_max_hp` | 붉은 가루 · 몸집 불리기 (Bulk Up) (`max_hp`) |
| `atk` | `bonus_atk_flat` | 녹색 병 (`atk_add`) |

**Computation is still done by the total slots; only the display reads the ledger** — the
growth recalculation (`BattleSim.refresh_growth_stats`) must read from one place only. The
ledger is written in one place, `CardPhaseManager._log_persistent_fx`, and the source is the
card running at that moment (`_current_card`), so there's no need to drag the name through
every clause function as an argument.

**(3) Remainder** (`fx:rest:<kind>`) — the total minus the ledger. It's the share that mech
passives push directly into `bonus_*` (영혼 수확 · 조준 보정 (Aim Assist) …), so the
source can't be named by a card name. If the total slot and the ledger disagree the screen
would quietly lie, so the leftover share isn't hidden.

- **Only applied effects show.** Laying out inactive cells in grey would force you to count
  "how many are on". With none at all, the single line `걸려 있는 효과 없음`.
- **Why chips alone aren't enough.** If the hit chip says 55, whether that's due to a laning
  card or just how it is only shows when you press the chip, and effects that **aren't
  carried on any chip, like the accrual multiplier**, had no place to be seen at all.
- **Team-level effects (계획 살인 (Planned Kill) reservation) aren't here.** They belong to
  the team, not the pilot, so the same thumbnail would show on all five and blur whose is
  what.
- **The body is rebuilt only when the composition changes** — `refresh()` compares
  `_fx_signature()` (the key list) with the previous value. If only values changed it must
  end with a label update, so an open info panel doesn't close and card nodes aren't
  re-instantiated. After a rebuild, the highlight is re-applied to the **new button** of the
  key that was open (the old button has been freed) — if that key itself is gone, the panel
  closes.

#### Cards
- **A transparent `Button` is laid over the card node.** `Card` is a node that holds its own
  hover · drag wiring in the hand, so letting it take input directly here would wake that
  machinery too. The button covers exactly the same spot as the card, so where you press and
  what you see don't diverge.
- **Pressing shows the card description in the info panel.** The text written on the card
  node is shrunk to ×0.80, so it's not meant to be read.

- **Shield attaches to the HP value, not a separate chip** — the chip shows only `159 / 322`,
  and `보호막 +30` (Shield +30) is inside the HP menu. A shield isn't a number read on its own
  but "how many more hits can it take now", and that answer only comes when placed beside HP.
- **The hit / evasion chips are values after the laning stat is applied.** What
  공격적인 라인전 pushes is not the `PilotData.hit` / `evasion` fields but **a multiplier at resolution
  time** (`lane_stat_mod`), so printing the raw fields would leave this value unmoved by even
  1 after playing the card. It goes through **the same function** as resolution
  (`SimulationCore.lane_adjusted`), tying the on-screen number and the number actually in play
  together, and the base value and multiplier are written in the menu (the line exists only
  when a multiplier is applied).
- **The big number on the `성장` (Growth) chip is attack growth; max HP growth is inside the
  menu.** The two grow **differently** (`GROWTH_ATK_PER_SCORE` vs
  `GROWTH_HP_PER_SCORE`, const.csv — attack grows faster), so when one cell gets only one number, the bigger one is shown. This
  value is derived from growth points and is **different** from the `적립 배율` (accrual
  multiplier) (`growth_rate_mult`) that cards push — the names are similar and easy to confuse,
  so the menu puts the two side by side.
- **Outgame stats (pilot tab) don't change during a match** — they only rise through training.
  So the menu's `인게임 증가` (in-game increase) row is always `없음` (none).
- **Chip value font is set by character count** (`_value_font_size`, ≤4 chars 38 → ≥10 chars
  22). A chip is only 141px wide, so `159 / 322` in the largest font would be clipped — better
  to drop one size than to clip.
- **`refresh()` doesn't rebuild the tree (as long as the lasting effect composition is
  unchanged)** (on every `update_hud`, right after `close_if_phase_left`). It fixes only the
  chip value labels · growth points · the text of the open panel — rebuilding wholesale would
  instantiate three card nodes **on every update** and make the pressed chip's highlight
  flicker each time. `_rebuild_body()` runs only when the tab changes. If the old block is only
  given `queue_free`, it still draws this frame and the text overlaps, so **`remove_child`
  first**. Neither the art nor its front/back pose is touched.
- **`clip_text = true` is mandatory on value labels.** A right-aligned `Label` whose text is
  wider than its rect gives up alignment and draws from the rect's left, so it **overflows to
  the right and off the screen** (measured: "아웃게임 데이터 없음" (No outgame data) was cut off
  outside the screen).
- **`MOUSE_FILTER_IGNORE` on `_body_root` excludes only that node** — child chip · effect ·
  card buttons are still pressable. z-order is `_root`'s child order: 0 dim / 1 art / 2 body /
  3–5 header (backing · name row · growth points) / 6–8 tabs / 9 close / (if open) the info
  panel last = topmost.
- Outgame stats are looked up with `BattleSim.player_data_for(pilot)` — it maps the index in
  the `pilots` array (0..4 = team 0, 5..9 = team 1) directly onto `match_ctx`'s two rosters, so
  **reordering `pilots` misaligns names and stats**. Standalone runs or INTL pilots → null →
  chip values `—`. Enemy pilots opening is also thanks to this mapping.
- While open, **only the strip of the pressed team is hidden**
  (`HudBuilder.set_strip_visible(team, on)`). If only the strip remained above the dim, what you
  are looking at would blur; putting it below the dim darkens the face you just pressed and
  breaks the link. The other team's strip is left alone — it's just covered by the dim, and
  removing it would make what disappeared more confusing.
- **No anchor preset on `_root`.** A `Control` under a `CanvasLayer` has no parent rect to
  resolve full-rect anchors against, so its size stays 0, and setting only the preset leaves a
  warning that "size is overwritten after `_ready`". The size is set explicitly.
- **The open condition is `can_open()` alone** — operation phase **or auto-run (BATTLE)**, with
  no engage stage and the match not over. The strip buttons and battlefield portrait long-press
  (`MarkerTouch`) read the same answer. It used to be only your own operation phase.
- **Opening during BATTLE pauses the turn** — `BattleSim._battle_tick_held` checks
  `is_active()`. If the battlefield kept rolling behind the dim, the numbers you're reading would
  go stale (the clock stops too).
- If the state moves to one where it can't be open, it's force-closed (`close_if_phase_left`, on
  every `update_hud`).

### Pressing a battlefield portrait (`MarkerTouch.gd`)
It's `_unhandled_input`, so **only battlefield taps** not consumed by the GUI (hand · strips ·
buttons) arrive. It ignores input while a card is held (targeting) or another modal · jungle
start · engage stage is up (`_accepting`).

| Action | Result | Haptic |
|---|---|---|
| press | the portrait picked by `renderer.marker_at` grows to `PRESS_SCALE` (1.3) and goes **to the top** | `SELECT` |
| release / moved ≥ `MOVE_CANCEL_PX` (28) | only the size returns — **top order is kept until another portrait is pressed** | — |
| held `LONG_PRESS_SEC` (0.45) | size restored and `PilotDetailPanel.open` (when `can_open`) | `MEDIUM` |

Touch is also emulated as mouse, so one press arrives as two events, but press / release are
handled purely as state transitions, so the second one does nothing. The drawing side (scale ·
top order) is in `rendering/README.md`.

### Top chrome (elapsed clock + enemy strip backplate + two objective clocks)
**It used to be one panel covering the full screen width.** That plate held the header
row, the enemy strip and the objective clocks, so the clocks at the left and right ends read
as sitting on the same plate as the strip — but the clocks aren't part of the strip; they are
a separate object counting battlefield events. Now, **by the same rule as the ally strip**,
the backplate wraps only the five portrait cells (`_enemy_strip_bg`) and the two clocks and
the elapsed clock stand outside it with no background. All three are direct children of
`_bs.canvas` (CanvasLayer).

`TOP_PANEL_Y` 0 / `TOP_PANEL_H` **148** remain and serve as **the reference coordinate for
the chain below** — the backplate starts at `ENEMY_STRIP_RECT.y − 10` (= 36) and ends at
`TOP_PANEL_H` (148), so the amount of peek it hides doesn't differ by a single pixel from
before. The enemy strip uses the middle 806px, and **the side margins are the two objective
clock cells** (`OBJ_TIMER_LEFT_X` 26, the right one worked back from the viewport width, each
101×60 — vertically exactly the same as the enemy portrait band).

The enemy strip grew twice: 618 → 672 (portrait +10%) → **806** (another +20%, portrait
145×60). Only at that size do faces tell who is who, and growth points can be compared side
by side with mine. The clock cells shrank by that much, 190 → 168 → **101**, and on the clock
side the icon·number gap and the "턴" text were removed to fit that width — when fighting for
space, the clock always gives way.

And below it is the chain: this panel is the screen that hides the top of the opponent's
hand peek (`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = **98**, only 49px of the cards' bottom pokes
out), the spot offset by `DONUT_AI_HAND_GAP` from the bottom of the peek cards (y 197) is the
enemy donut (bottom y **327**), and below that is the top of the battlefield pixels
(y **369**).
**If you change the panel height, move `AI_HAND_TOP_Y` and `KillFeed.FEED_TOP`
(= `TOP_PANEL_H + 8`) by the same amount together** — leave the former and the peek either
hides entirely behind the panel (when growing) or exposes the cards' tops (when shrinking);
leave the latter and the kill log floats detached from the panel. The donut is computed from
`AI_HAND_TOP_Y`, so there's nothing to touch separately.
It shrank 168 → 132, then became **148** when the strip grew, and the chain also moved down
by the same 16px (peek 98 / donut 327 / kill log 156). The slack to the battlefield is
**42px**, and the empty band in between is used by the **card description box** —
`CardPhaseManager.DESC_BOX_TOP`.

- **Time label** — left (x 20), `font_size` 18. **There's no backing**, so a black outline
  (4px) keeps it readable. `UiHelpers.mk_label` takes a `Control` parent but the canvas is a
  `CanvasLayer`, so here the `Label` is created directly — previously the full-width panel was
  that `Control`. `MM:SS` (`get_elapsed_ingame_seconds`).
  **Hours aren't shown, so minutes can exceed 60.** During BATTLE seconds flow in real time
  (1 turn = 0.5 s = 60 in-game seconds, i.e. about 120× the wall clock); during CARD_PHASE /
  game over it stops.
- **The team total score was deleted.** It was the row printing `12.4k - 9.8k` in the middle,
  but the strip's five cells already showed the same numbers individually, and the total, while
  telling in one line which side is winning, hid **who** is actually growing.
  `TOTAL_SCORE_FONT` and `_lbl_total_score` disappeared at the same time.
  `BattleSim.team_score()` lost its consumer but remains as a function.

### Kill log (`KillFeed.gd`)
Stacks kills · turret demolitions · objective captures one line at a time at the **top-right**
of the screen (8px below the top panel's bottom edge, y **156** = `TOP_PANEL_H` + 8). The
battlefield flows on its own every 0.5 s and engages cover the screen with an overlay, so
**once something happened, there was nowhere it remained** — apart from the team score
widening a bit.

A line is, from the left, `[막타][어시][어시][아이콘][피해자]` (last hit / assist / assist / icon /
victim), and every line is **right-aligned** within `feed_width()` — however many assists, the
victim cell always lands at the same x.

| Cell | Width | Content |
|---|---|---|
| Last hit (막타) | `PORTRAIT_W` 96 | wide eye cut. The owner of this line |
| Assist ×0..4 | `ASSIST_W` 32 (= 1/3) | same height, only 1/3 width |
| Icon | `ICON_W` 32 | kill = crossed swords, turret demolition·objective capture = burst |
| Victim (피해자) | 96 | eye cut for a pilot; for a turret, silhouette + `T1 좌`; for an objective, glyph + `용` / `전령` |

- **There are three feed sources** — `BattleSim.mark_pilot_dead` (→ `_push_kill_feed`),
  `BattleSim.score_turret_kill`, and `ObjectiveSystem._push_feed` (→ `push_objective`). The
  first must be called **before `_payout_kill_bounty`**: the assist list comes from
  `PilotData.damage_credit`, and that payout empties the ledger. So the faces shown on screen
  and the faces that received growth points come from the same table (that table is built by
  one function, `BattleSim.live_damage_credit`, which filters out expired entries).
- **The representative of an objective line is the jungler** — for both Herald and Dragon the
  junglers of both teams are always participants, and running objectives is the jungle's job
  itself, so if one face must say "who took it", that seat is the jungler's
  (`ObjectiveSystem._feed_order`). If the jungler couldn't come (dead · position-locking skill)
  the first of the remaining participants stands there, and everyone else attaches as assists.
  The list is **the participants at the time participation was chosen**, so someone downed in
  the subsequent engage still stays, and **an uncontested capture also gets a line** — a free
  take where nobody showed up is precisely the case where nothing happens on screen, so it
  needs a trace even more.
- **The Herald / Dragon pictures are drawn by `ObjectiveTimer`'s static functions**
  (`draw_kind_glyph` / `kind_color`, 64×64 normalised coordinates). It's **the same function**
  as the spawn clock in the top panel, so the Dragon in the two spots can't become different
  pictures. The kill log node is `ObjGlyph`; the reason it's separate from `Glyph` is the
  coordinate system, not the drawing method.
- **There's a path where the last hitter is null** — `SimulationCore._last_hitter` is cleared
  every turn, so depending on timing it arrives empty. In that case the person who dealt the
  most damage takes the last-hit seat.
- **Kills during an engage are held back** — `_submit` checks `EngagePhaseManager.is_active()`
  and stacks them in `_pending`, and `_on_dashboard_confirmed`, which closes the result
  dashboard, calls `flush_pending()` to release them at `FLUSH_STAGGER` (0.25 s) intervals.
  Showing them while the arena covers the screen means nobody sees them.
- **Lines push in from the top** — the new line at y 0, the rest one slot down each. After
  `HOLD_SEC` 4 s they're erased over `FADE_SEC` 0.5 s, and the oldest line beyond `MAX_ROWS`
  (4) is pushed down and fades. A pushed-out line is **moved to `_fading`**, not left in
  `_rows` — it must drop out of slot calculation but its fade must keep running (measured: just
  removing it from `_rows` froze that line on screen forever).
- **The icon is a child `Glyph` node, not the line's `_draw`.** A Control's `_draw` is emitted
  **before** its children, so it would lie beneath the line background (translucent) and the
  turret cell slab (opaque) — in measurement the swords were faded and the turret silhouette
  didn't show at all.
- With 4 lines the bottom stops at y **334**, **above the top of the battlefield pixels
  (369)** (when the top panel was 168 it was a close call at 354). Raising `MAX_ROWS` /
  `ROW_STEP` much covers the battlefield.

### Match end — MVP view → result panel (`MvpView.gd` + `_build_victory_panel`)
Flow (owner: `BattleSim.end_match(winner_side)`, called once from
`SimulationCore.check_win_condition`):

1. The win/loss haptic plays (`SUCCESS` / `ERROR`, unchanged) and the match stats are frozen
   (`BattleSim.build_pilot_stats`, see `combat/README.md` "Match stats").
2. **MVP** = winning team's best `RunStats.mvp_score(row)` (`RunStats.pick_mvp_index`). The
   view is a `CanvasLayer` at `MvpView.OVERLAY_LAYER` (above every other overlay): dimmed
   background → "MATCH MVP" title → **full-body art** (`PilotImages.full_for(p.pilot_id)` — mobs get
   the silhouette cut automatically; no image (INTL / unknown id) → a placeholder slab with the
   role name) → info panel (name · `아군`/`상대 팀` · position label · K / D / A · key metric line)
   → full-width "계속" button. The metric line follows the MVP formula's terms: support =
   care + damage taken, top = damage dealt + taken, others = damage dealt.
3. "계속" (or a tap anywhere after `TAP_ARM_SEC`, so the tap that ended the match can't skip it)
   → `closed` → `BattleSim._on_mvp_view_closed` frees the view and shows `panel_victory`.
4. The result panel (`panel_victory`) is taller now (`VICTORY_PANEL_SIZE`) and carries an
   **MVP line** (`HudBuilder.set_victory_mvp`): circle portrait + name + position · K/D/A.
   It lives on **its own CanvasLayer** (`VICTORY_LAYER` — above the HUD canvas, below
   `MvpView.OVERLAY_LAYER`) over a full-screen dim (`VICTORY_BACKDROP_COLOR`, blocks input) that
   follows the panel's visibility, and the panel itself is opaque. It used to sit on the HUD
   canvas with a translucent fill, so battlefield tiles · markers showed through the panel and
   the HUD strips · markers around it stayed at full brightness.

Every coordinate is inside `ScreenMetrics` (title from `top_y()`, button stacked up from
`bottom_y()` — clear of the bottom gesture band, `docs/mobile_safe_area.md`); the art height
is whatever is left between title and info panel. Standalone runs show the same view from live
stats; "Play Again" (`_on_restart_pressed`) frees any open view.

### update_hud() (per-turn)
- Calls `_update_cost_donuts(in_card_phase)` — pushes both sides' operation points
  into their ring gauges and gates the player donut's flip / "턴 넘기기" press
  on `game_phase == CARD_PHASE` and `card_phase.can_end_card_phase()`.
- Calls `_update_pilot_strips(in_card_phase)` — sorts a **copy** of `_bs.pilots`
  by team and lane, pushes each five into its `PilotStrip`, gates **both** strips'
  hit buttons on the operation phase, refreshes the team-score label, then lets
  `PilotDetailPanel.close_if_phase_left()` close the modal if the phase moved on
  and `PilotDetailPanel.refresh()` re-write the chip values of one that survived
  (labels only — the node tree is rebuilt on tab switch, never on refresh).
- Calls `update_time_label()` (also called every frame from `_process`).

### update_time_label() (per-frame)
Pulls `_bs.get_elapsed_ingame_seconds()` and formats as `%02d:%02d`. Called
from `BattleSim._process` every frame so the clock visibly ticks even when no
HUD-state event fires.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.


---

## Pilot skill display (`PilotStrip` dim + `PilotDetailPanel` block)

A unique ability attached to each player. The rules and the list of 25 are in
`../skill/README.md`; what's written here is only **how it appears on screen**.

### Strip — readiness wipe + number
**The portrait is darkened by default and brightens from the left as the skill gets ready.**
The fill ratio is answered by one function, `PilotSkillSystem.progress(p)` — for cooldowns
it's the elapsed ratio, for charge-type skills the ratio against the Charge (충전) needed to
activate, and **for passives it's always 1.0** (they can't be pressed but always apply, so
"not ready yet" doesn't exist).

The implementation **pushes the left edge** of one dim (`SKILL_DIM`, black α 0.55):

```
filled = progress(p)
dim.position.x = px + _portrait_w * filled
dim.size.x     = _portrait_w * (1 - filled)
```

The reason it's not done by laying a rectangle on the bright side is the 100% case — layering
leaves one coat even when full, while narrowing brings the width to 0 so the portrait returns
to **exactly its original colour**.

The dim is attached after `eye` · **before** `rim` (sibling z-order = child index). The team
colour border must stay above the dim so which team it is doesn't fade with readiness.

The number is a small cell at the portrait's **top-right** (`SKILL_BADGE_W_RATIO` 0.28 ×
`SKILL_BADGE_H_RATIO` 0.42, black backing α 0.55), answered by `badge_text(p)` — for a
cooldown, **turns remaining** (blank when ready); for charge-type skills and passives that
stack Charge, **the Charge count**; otherwise blank. The colour says "can it be pressed now"
(gold `SKILL_BADGE_READY` / slate blue `SKILL_BADGE_WAIT`).

**It shows only on the ally strip** (`_apply_skill_state` returns immediately if
`_team != 0`). Only allies can press skills, and darkening the enemy cells too would make the
opponent's faces look faded regardless of skills. Cell size differs between the two strips,
so the badge cell is also sized **by portrait ratio** — the same reason the role tag did so
(fixed pixels would cover the face on the smaller one).

Updating has only one path: `HudBuilder.update_hud` → `_update_pilot_strips` →
`PilotStrip.refresh()`. To cover paths where state changes independently of battlefield ticks
(objective spawn · kill involvement · turret destruction), `PilotSkillSystem.skill_state_changed`
is connected directly to `update_hud` (`BattleSim._ready`).

### Detail panel — below the card row in the in-game tab
A skill is a different kind of resource from cards, so it isn't mixed into the card grid but
has its own block. There was also the option of slotting it into the lasting effect
thumbnails as one cell, but then knowing "can I use it now" would take one more press on the
thumbnail — a skill exists to be pressed, so its button must be visible right away.

```
파일럿 스킬 ──────────────────────────                      ("Pilot skill")
공성전 (30pt, gold)                충전식 (20pt, right)      (skill name "Siege" / type "Charge-type")
포탑 파괴, 전투 개시 (19pt, faint)                           (keywords: turret destroyed, battle start)
충전 5로 시작. 포탑 파괴 시 +1 충전 (최대 5) / 활성화: …   ← auto wrap  (description)
충전 0 / 5 · 사용에 5 충전                                  ← green when ready  (state: "Charge 0 / 5 · 5 Charge to use")
[            사용            ]   width STAT_W, height 68     ("Use")
```

* **The badge is only one word, the type.** Adding keywords would exceed 38% width on long
  skills and the right alignment would be clipped from the left — a right-aligned `Label`
  gives up alignment when it overflows and draws from the rect's left (the same trap as
  `godot_control_sizing_traps`). Keywords moved down to their own line, small and faint.
* The description height is obtained by **asking the font** (`Font.get_multiline_string_size`).
  Estimating from character count is off by a line or two with mixed Korean/English text, so
  the button below overlaps or floats.
* **Passives have no button** — a disabled button on something that can't be pressed reads as
  "something that will be pressable someday". `_skill_use_btn` stays null.
* `refresh()` rewrites **only the state line and button enabled state**
  (`_refresh_skill_block`). Rebuilding the tree would instantiate card nodes on every update —
  the same rule as the other update paths of this panel.
* **Using it closes the panel.** The result shows up in the hand · battlefield · strips, and
  with the dim covering them it looks like nothing happened; skills that open their own overlay,
  like 계략 (Scheme) (`CardSelectOverlay`, layer 10), would sit behind this panel (layer 13) and
  not be visible at all.

---

## Screen fit (safe area)

`HudBuilder`'s coordinate constants are **the 1080×1920 design values as-is**, and device
adaptation is done **by shifting whole blocks** without touching those values.

| Scalar | Value | What it shifts |
|---|---|---|
| `HudBuilder.top_offset()` | `ScreenMetrics.top_y()` | top panel · opponent hand peek root · enemy donut · `KillFeed` |
| `HudBuilder.bottom_offset()` | `ScreenMetrics.bottom_y() − 1920` | ally strip (+backplate) · `BattleSim.BS_HAND_CENTER.y` (→ deck/discard · player donut · dim all follow) |

The reason not to fix constants one by one is the "chain" from the head of this file — top
panel ↔ peek ↔ donut ↔ kill log interlock pixel by pixel, so moving just one quietly breaks
the relationship. Two scalars preserve all relationships, and **with zero insets both values
are 0, so the layout doesn't differ by a single pixel from before** (measured).

Horizontal comes from `ScreenMetrics.vp_w()` / `center_x()` — the enemy strip and objective
clocks re-centre to the viewport width, and the clock's right cell is worked back from the
left margin (the old `OBJ_TIMER_RIGHT_X = 953` was deleted).

Full-screen dims (`CardSelectOverlay` · `PilotDetailPanel` · `CardPileViewer` …) must use
`ScreenMetrics.viewport_size()`. A `Vector2(1080, 1920)` literal leaves an uncovered band at
the bottom on tall screens.

Detailed conventions · per-device values · desktop verification: **`docs/mobile_safe_area.md`**


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Pilot display (strips ×2) | Five pilots each form one cell in three rows, **eye-level portrait → HP bar → growth point number** (growth points correspond to the gold display of a MOBA broadcast, rising from `SCORE_START` (const.csv) at the opening through the match), and the five cells stand side by side horizontally (`ui/PilotStrip.gd`). **The enemy team is at the very top of the screen** (`ENEMY_STRIP_RECT` 137,46,806×100 — **78% of the ally strip**, horizontally centred, **with one backplate `Panel` behind it**), **allies are below the hand row** (`PLAYER_STRIP_RECT` 25,1766,1030×122, **with one backplate `Panel` behind it** — see the row below) — previously all ten were crammed into 84px square slots on both sides of the top panel, so you could tell neither who was who nor which side was your team. The portrait is `PilotImages.eye_for` = **`eye/N_eye.png` (480×200, a band cut horizontally so both eyes show)** and the cell height is derived from that ratio (`EYE_ASPECT` 2.4) — stretching to an arbitrary height distorts the face. The HP bar is **two `ColorRect`s**: `ProgressBar` computes a minimum size from the theme content margins and pulls `size` up to around 24px, so even when a 6–10px bar was requested it overwrote the growth point label below (confirmed by measurement). With a shield the fill turns yellow (the reason for not appending a segment is that it's too thin for two sections to be distinguishable). A downed pilot's portrait darkens and **the number of turns until revival** is printed large in the middle. The bottom strip's y (1766) is **a value computed from the cards' bottom edge** — the cards at both ends of the fan sag 21.4px below the middle and grow 1.2× on hover, coming down to a worst case of y≈1763 (back when the hand row was at 1500). Now that the hand has moved up to 1440 the worst case is y≈1703, so the slack grew to 63px, but the strip is attached to the screen bottom (1888) with no room to go lower, so it stays. **Cell order is set by `GameEnums.ROLE_DISPLAY_ORDER` — tank → assassin → fighter → sniper → supporter**, i.e. the order you sweep the battlefield from the left (left → jungle → centre → right ×2), and **the same table as the outgame screens** (season hub roster · training grid · ban/pick (밴픽) screen · draft slots). Using the `Role` enum order as-is (TANK · FIGHTER · ASSASSIN · SUPPORT · SNIPER) seats the jungler third and the ADC fifth, an arrangement that corresponds neither to the map nor to the lineup the player knows. Previously a separate `HudBuilder.LANE_SEAT_ORDER` table here sorted **by `PilotData.lane`** (**deleted**), but two pilots sit in the right lane (sniper · supporter) and lane couldn't order those two — `sort_custom` is not a stable sort, so the order of the two with the same lane could wobble between runs. Sorting by role uniquely determines all five seats. Sorting is done on a **copy** of `_bs.pilots` — the original must keep spawn order (= role order) so `BattleSim.player_data_for` can find the roster by that index. **The enemy strip's size changed four times.** At first it was a 730×84 shrunken version (portrait 130×54), but showing the same faces at two very different sizes top and bottom meant neither who the opponent was nor the opponent's growth points read as well as the ally side (that number exists to be compared side by side with mine), so it was enlarged to **exactly** the ally's 1030×122 — at that time `HudBuilder.TOP_PANEL_H` grew 130 → **168** and the whole chain below moved down 38px (`AI_HAND_TOP_Y` 80 → **118** = `TOP_PANEL_H − 50` → enemy donut bottom 311 → **349**, battlefield pixel top 369, so 20px of slack). After that it was shrunk to **60% (618×76)** and centred — because when the objective spawn clocks moved from the battlefield tiles to this panel, **cells for icon + turn count on either side of the strip** were needed. But at that size the 108×45 portrait fell below the minimum for telling who is who. Portrait width is derived from cell width (`_cell_w − 16` in `PilotStrip.setup`), so the only way to enlarge it is to push the strip width, and it was **pushed twice** — 618 → **672** (portrait +10%), then 672 → **806** (+20%, portrait 145×60). Height follows the eye ratio (2.4:1) up 76 → 81 → **97**, and to keep horizontal centring x is pushed left 231 → 204 → **137**. The side margins shrank, so the clock cells went 190×122 → 168×49 → **101×60** (`OBJ_TIMER_LEFT_X` 26 / `OBJ_TIMER_RIGHT_X` 953) — on the clock side the icon·number gap was cut to 4 and the "턴" text was removed to fit that width (`ui/ObjectiveTimer.gd`). This is a panel where faces must read first, so when fighting for space the clock always gives way. **The panel height is now set by content** — `TOP_PANEL_H` went 168 → 132 → **148** (header 4..38 + strip band 46..143 + 5px), and the chain below (`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = **98**, enemy donut bottom **327**, `KillFeed.FEED_TOP` = `TOP_PANEL_H + 8` = **156**) moves along with it, leaving **42px** of slack to the battlefield top (369). The old 168 was a leftover from when the strip was the same size as the ally one, creating a 27px empty cell below the band. **The growth point font is now the same on both strips** (`ENEMY_SCORE_FONT` = `PLAYER_SCORE_FONT` = 20, formerly 14) — the ally portraits are bigger, but that number exists to be compared side by side with mine, so different sizes would give the two numbers read on the same line different weight. Faces may be small; numbers may not. **The role tag (single letter `T` / `F` at the portrait's bottom-left) was deleted** — the strip's seat order itself already is the role, so it said the same thing twice and just covered the bottom of the face (the three `ROLE_TAG_*` constants and the two nodes `tag_bg` / `role_lbl` disappeared together). **And the full-width top panel disappeared** — see the row below. |
| Top chrome (enemy strip backplate + elapsed clock + objective clocks) | **Previously one panel covering the full screen width** (`TOP_PANEL_H` 148) held the header row, the enemy strip and the objective clocks. That made the clocks at both ends read as sitting on the same plate as the strip, but the clocks aren't part of the strip; they're a separate object counting battlefield events. Now, **by the same rule as the ally strip**, the backplate (`_enemy_strip_bg`) wraps only the five portrait cells, extended by `ENEMY_BG_PAD` (10), and **the elapsed clock and the two objective clocks stand outside it with no background** (all three direct children of `_bs.canvas`). `TOP_PANEL_H` remains as a constant and serves as **the reference coordinate for the chain below** — the backplate starts at `ENEMY_STRIP_RECT.y − 10` (36) and ends at `TOP_PANEL_H` (148), so neither the amount hiding the opponent hand peek (`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = 98) nor the enemy donut (327) nor the kill log (`FEED_TOP` = 156) moved by a single pixel. The peek fan stands at the horizontal centre of the screen, so it fits entirely within the strip width (x 127..953) and still acts as a screen. **The team total score (`12.4k - 9.8k`) was deleted** — the strip's five cells already showed the same numbers individually, and the total, while telling in one line which side is winning, hid **who** is actually growing (`TOTAL_SCORE_FONT` / `_lbl_total_score` deleted together; `BattleSim.team_score()` remains without a consumer). The elapsed clock has no backing, so a black outline keeps it readable, and since `UiHelpers.mk_label` takes a `Control` parent whereas the canvas is a `CanvasLayer`, the `Label` is created directly. |
| Ally strip backplate | **One dark `Panel`** behind the bottom ally strip (`PlayerStripBackdrop`, the strip area extended by `HudBuilder.PLAYER_BG_PAD` 10px each side, y 1756..1898). Colour·border match the top panel, so the top and bottom strips read as sitting on the same plate. The enemy strip sits on the top panel so it had backing from the start, but the ally strip floated directly on the screen, so the three rows face · HP bar · growth points looked scattered with no background — growth point numbers in particular don't show where one pilot's cell ends without backing. **`_build_player_strip` adds it before the strip** (sibling z-order is child index, so if added later the plate covers the portraits) and **`set_strip_visible(0, on)` hides it together with the strip** (if the detail panel cleared only the strip, an empty plate would remain on top of the dim). |
| Objective spawn clocks (either side of the strip) | One pair of **one icon + turns remaining** in each of the enemy strip's side margins (`ui/ObjectiveTimer.gd`, each 101×60). **Left is Herald (purple flag) · right is Dragon (vermilion wings)**, and that left/right matches the left/right of the cells where the two objectives stand on the battlefield — position is the name, so there are no name labels. When the enemy strip grew 20% this cell shrank 168 → 101px, and accordingly the icon·number gap became 10 → **4** and **the "턴" text next to the number was deleted** (`UNIT_FONT_SIZE` / `UNIT_COLOR` disappeared with it) — a number stuck next to the icon can't be anything other than turns remaining, so that text only pushed the number away. `ICON_SIZE` stays 49 and is vertically centred (number font 32). **Pressing shows that objective's reward cards as real cards** — `mouse_filter` went IGNORE → STOP, and when it fires `timer_pressed(kind)`, `HudBuilder` calls `BattleSim.objective_reward.toggle(kind)` (pressing the same clock again closes it). At one point the icon was 62 and the cell height was the whole strip band (122) — on the grounds that bigger reads better in peripheral vision — so the clocks stuck out above and below the portraits, became the biggest object in the top panel, and grabbed the gaze that should go to the faces first. Aligning bottom·top edges to the portraits makes left clock · five faces · right clock read as one row. State comes only from `ObjectiveSystem.turns_until_cell(cell)` and updating is only `HudBuilder.update_hud`'s `queue_redraw()`. **Icons are shapes, not images** (same approach as the kill log glyphs): all coordinates are written on a 64×64 basis and only multiplied by `ICON_SIZE / 64`, so changing size doesn't require redoing the numbers. Dragon's wings are **smooth four-vertex triangles**; the original serrated bat wings (eight vertices) mushed together at this size and looked like **a single leaf** — at this size what makes the silhouette is not detail but the angle of two big triangles. |
| Kill log (kills / turret demolition / objective capture) | Stacks one line at a time at the **top-right** of the screen (8px below the top panel's bottom, y **156** = `TOP_PANEL_H` + 8) (`ui/KillFeed.gd`). The battlefield flows on its own every 0.5 s and engages cover the screen with an overlay, so **once something happened, there was nowhere it remained** — apart from the team score widening a bit. A line is, from the left, `[막타 96px][어시 32px ×0..4][아이콘 32px][피해자 96px]` (last hit / assist / icon / victim), all eye cuts (`PilotImages.eye_for`), and **the whole line is right-aligned**, so however many assists, the victim cell lands at the same x. Icons: kill = crossed swords, turret demolition = burst, and the victim spot gets the turret silhouette + `T1 좌`. **There are three feed sources** — `BattleSim.mark_pilot_dead` (→ `_push_kill_feed`), `score_turret_kill(killer, td)`, and **objective capture** (`ObjectiveSystem._push_feed` → `KillFeed.push_objective`). An objective line's **representative is the jungler** (for both Herald and Dragon both teams' junglers are always participants, and running objectives is the jungle's job itself — `_feed_order`). If the jungler couldn't come, the first of the remaining participants stands there and the rest attach as assists; the list is **the participants at the time participation was chosen**, so someone downed in the subsequent engage stays. **An uncontested capture also gets a line** — a free take where nobody showed up is precisely the case where nothing happens on screen. The rightmost cell gets the Herald / Dragon glyph and name, and that picture is drawn by **the same static function** as the top panel spawn clock (`ObjectiveTimer.draw_kind_glyph`). The two feed sources for kill lines are unchanged — the former must run **before** `_payout_kill_bounty` (that payout empties `PilotData.damage_credit`, the source of the assist list). So the faces shown on screen and the faces that received growth points can't diverge. If the last hitter arrives as null (`_last_hitter` is cleared every turn), the person who dealt the most damage takes that seat. **Kills during an engage don't show on the spot** — the arena covers the screen so they wouldn't be seen anyway, so it checks `is_active()` and stacks them in `_pending`, and `EngagePhaseManager._on_dashboard_confirmed`, which closes the result dashboard, calls `flush_pending()` to release them in a burst at `FLUSH_STAGGER` (0.25 s) intervals. Lines **push in from the top** (the new line at y 0, the rest one slot down), are erased over `FADE_SEC` (0.5 s) after `HOLD_SEC` (4 s), and the oldest line beyond `MAX_ROWS` (4) is pushed down and fades — a pushed-out line is **moved to `_fading`**, not left in `_rows` (it must drop out of slot calculation while its fade keeps running; just removing it from `_rows` froze that line on screen forever — measured). With 4 lines the bottom stops at y **334**, above the top of the battlefield pixels (369) (when the top panel was 168 it was a close call at 354). **The icon is a child `Glyph` node, not the line's `_draw`** — a Control's `_draw` is emitted before its children, so it would lie beneath the line background (translucent) and the turret cell slab (opaque) (the swords were faded and the turret silhouette didn't show at all). |
| Pilot detail panel | A modal that opens when you press a face on a strip **during your own operation phase** (`ui/PilotDetailPanel.gd`, its own `CanvasLayer` 13 — above discard 10 / targeting 11 / browse·engage 12). **Both the ally bottom strip and the enemy top strip are pressable** — enemies open through the same gate with the same content (down to the 6 dealt cards), and the opponent roster has already come in as `match_ctx.enemy_roster`, so `BattleSim.player_data_for` finds it directly at indices 5..9. The screen is dimmed black α 0.88 and **only the strip of the pressed team is hidden** (left above the dim it blurs what you're looking at; put below the dim the face you just pressed darkens. The other team is just covered by the dim, so it's left alone). **On the left, two full-body arts** stand overlapping (pilot / mech), and the right is **header + three tabs + detail panel**. **The header is separate from the tabs** (`HDR_TOP` **424** .. `HDR_BOTTOM` 562, on its own backing) — **pilot name / the mech name small on the line below / growth points on the right**; it belongs to the same pilot whichever tab you view, so it isn't rebuilt when tabs change (`_build_header_block` runs only once in `_build`). Previously this line was inside the body, so **on the mech tab the title changed to the mech name and the pilot name and growth points vanished from the screen entirely** — in effect, who was open wobbled with the tab. The mech name being always visible is for the same reason (it isn't a value you should have to go into the mech tab to learn). **The mech name moved from the right of the name down to the line below** — it used to be appended with an `HBoxContainer`, but since the line's start point was the name's width, the mech name started at a different x per pilot (where to look for the mech name wobbled per pilot). Stacking two lines makes the start point always the same and removes the need to measure text width, so the container itself disappeared. `HDR_TOP` moving up by the two extra lines is because `HDR_BOTTOM` is the top edge of the tab bar and is pinned. The only thing a tab changes is the detail panel below — **In-game** (HP · attack · growth · battlefield/engage hit · evasion · presence, a `부활까지 N턴` line when dead, then immediately below it the **pilot skill block**) / **Pilot** (six player stats = `PlayerData`) / **Mech** (HP · attack · presence). The tab also decides which art is front and back (on the mech tab the machine is in front) — the old **"전환" (Switch) button was deleted**. **Lasting effects and held cards both live outside the info column** — effects at **the bottom-left of the illustration** (from x 26, right above the card row), cards in **a fan across the full width of the screen bottom**. **Lasting effect thumbnails** (68×68, in-game tab only) show **only what's currently applied to this pilot**, and past six cells the row folds **upward** (folding downward would land the second row on the cards); **the title ("지속 효과") was deleted** — putting an underlined section title on top of cells standing alone in a screen corner makes the title stand out more than the cells, and with no effects applied nothing is drawn at all (the old one-liner "걸려 있는 효과 없음" was a sentence that only made sense with a title). The reason for moving it was competition for space — inside the column it ate 116px and pushed the whole chain below (card row · skill block · close button), while the bottom-left of the screen held only the art's legs and the dim, so it was empty. Three kinds are mixed — **(1) the four slot effects** (`fx:lane` laning stat / `fx:rate` accrual multiplier / `fx:atk` temporary attack / `fx:shield` shield) have cards overwriting each other in one slot, so the kind name is the cell name; **(2) per-card lasting effects** (`fx:src:<kind>|<card name>`) are one cell per line of the `PilotData.persistent_fx` ledger (the abbreviation is the first two characters of the card name — `용 보상` → `용보`); **(3) the remainder** (`fx:rest:<kind>`) is the total minus the ledger (the share mech passives push directly into `bonus_*`, so the source can't be named by a card name). Previously (2) was also lumped by attribute, so **one `fx:perm` cell meant both [용 보상] and [핫핸드]**, and [붉은 가루] · [녹색 병], which live in `bonus_max_hp` / `bonus_atk_flat`, **weren't shown at all** — they are values living in separate fields so the growth recalculation doesn't wipe them, so they weren't carried on any chip. **Computation is still done by the total slots; only the display reads the ledger** (the ledger is written in one place, `CardPhaseManager._log_persistent_fx`, and the source is the card running at that moment) — the growth recalculation must read from one place only. Laying out inactive cells in grey would force you to count "how many are on", and with none at all it's the single line `걸려 있는 효과 없음`. There are no icon assets, so **the two-character abbreviation is the icon** and the full name is carried by the title of the panel opened by pressing it. There were two reasons chips alone weren't enough — when the hit chip says 55, whether that's due to a card or just how it is only showed when you pressed the chip, and effects **not carried on any chip, like the accrual multiplier**, had no place to be seen at all. The team-level 계획 살인 reservation isn't here (the same thumbnail would show on all five and blur whose it is). **Stat chips · lasting effects · cards all share one info panel** (one `_targets` table; the key prefix distinguishes the kind — none = chip, `fx:` = effect, `card:` = card). The plate opens to the left of the info column **at the same height as the pressed item**, with **only `card:` as an exception, lifted to sit above the card row title** — cards are at the bottom of the screen, so the same rule would point on top of the card just pressed, and the plate would cover that card entirely. "What am I looking at now" must be one thing at a time, so separate plates would show two at once and blur what you just pressed. **Pressing a card shows that card's cost · type · caster restriction and description in that panel** — the text written on the card node is shrunk to ×0.80, so it's not meant to be read. **The backdrop forwards clicks** (`_on_menu_backdrop_input`) — it's still a full-screen STOP, but it finds the target button / tab / close at that coordinate and presses it on your behalf, so **pressing another stat with the panel open switches straight to it**. Previously the first click was spent on closing so you had to press once more, and while skimming six stats the clicks doubled and the screen flickered between open↔closed. Pressing an empty spot closes it then. **Stats are chips, not rows**: one rounded rectangle cell (141×92, 3 columns) with a small name on top and only **one final value**, large, below; the base value · increase · expiry turn are in **the context menu that opens to the left when the chip is pressed** (`_menu_rows`, e.g. HP = base N / growth +N% (+N) / max N / current N / shield +N). Previously `key ─ value` rows ran a dozen or so lines with `(기본 N)` `(N턴)` brackets trailing the values, so reading "what it is now" took time — `_row` / `_section` / `ROW_H` / `KEY_FRACTION` were deleted at the same time. **The big number right of the title is growth points** (the old `역할 · 아군/적군 · 성장치` subtitle and `라인 / 위치` row were deleted — role and side were already told by the portrait just pressed), and **it isn't attached on the mech tab** (that title is the mech name, which isn't the owner of the number on the right). **Shield is not in the HP value but inside the HP menu**, and **the hit / evasion chips are values after the laning stat is applied** (`SimulationCore.lane_adjusted` — passed through the same function as resolution. What cards push isn't the `hit` / `evasion` fields but the resolution-time multiplier `lane_stat_mod`, so printing the raw fields would leave the value unmoved by even 1 after playing 공격적인 라인전). **The big number on the growth chip is attack growth**, and max HP growth · accrual multiplier are in the menu — the two grow differently (`GROWTH_ATK_PER_SCORE` vs `GROWTH_HP_PER_SCORE`, const.csv), and it's different from the `적립 배율` that cards push. **Held cards stand in the same fan as the hand across the full width of the screen bottom** — `Card.tscn` **×1.60 = 256×352** (**2×** the grid-era 0.80 = 128×176); the in-game tab has 6 (pilot 3 → mech 3 order, so the left half is the person and the right half the machine), and the pilot / mech tabs put that tab's cards in the same spot. **It used to be a 3-column grid inside the info column**: the cells were confined to the column (width 452) so they couldn't get bigger, and there's no way to keep the grid and double the size (3 columns would be 800px, overshooting the column by 348px · the right side of the screen by 146px, and 2 rows would put the panel bottom at ≈1700 → 2052, off screen). The fan **overlaps** the cards, so it fits the same count in the same width while doubling the size per card. The geometry follows the same rule as the hand (card **centres** ride a circle below the row), and the side margin `FAN_MARGIN` (52) and bottom slack `FAN_DROP_RESERVE` (44) accommodate not half the width but **the outer corner of the tilted card** — the ends tilt close to 9°, so the tall card goes 27px further out than half its width (at margin 24 both ends were clipped by 3px — measured). **Input is taken not by the card rect but by the band where the card is visible** (its own left edge ~ the next card's left edge) — covering rects as-is on overlapping cards would let the right neighbour's button hide this card's visible face entirely — and a card whose info panel is open rises by `FAN_LIFT_PX` (30) and is pulled to the front (the grid-era border highlight was deleted because it would wrap the band rather than the card). The list comes from the `BattleSim.starter_cards` table — reconstructing by scanning hand·deck·discard pile would silently drop exhausted (`exhaust`) cards. While open, `refresh()` rewrites **only the chip value labels and the open menu's text** on every `update_hud` (rebuilding the tree would instantiate card nodes on every update). **Close** follows the backing's bottom edge — content height differs per tab (in-game ~360 / pilot ~600), so at a fixed y the button alone floats in the middle of the screen on short tabs. **`clip_text = true` is mandatory** on value labels — a right-aligned `Label` whose text is wider than its rect gives up alignment and draws from the rect's left, so it **overflows to the right and off the screen** (confirmed by measurement). Leaving the operation phase force-closes it via `close_if_phase_left()` — if BATTLE flowed with it open, the battlefield would roll on behind the dim. |
| Detail panel's two arts (pilot ↔ mech) | The two arts share the front and back slots. **Front** = bright, horizontal centre `ART_FRONT_CENTER_X` (320). **Back** = pushed right by `ART_BACK_SHIFT_PX` (400px), shrunk by `ART_BACK_SCALE` (0.90), and dimmed with `ART_BACK_TINT` (translucent black) — a pose of "standing behind, slightly to the right, half overlapping". **The tab decides front and back** (`_apply_focus` — on the mech tab the machine is in front, otherwise the person; a `ART_SWAP_SEC` 0.22 s tween changes position · dim · z-order all at once). The old **"전환" button (two-state toggle) was deleted** — once the info split into three, a two-state toggle could no longer say what was where. **The bottom of the screen crops the art** — the bottom edge (`ART_BOTTOM` 2010) is outside the screen (1920), so the lower legs are cut off, and the old knee crop (`_knee_crop` / `KNEE_FRACTION`, which cut the texture via `AtlasTexture.region` at 80% of the alpha silhouette height) was **deleted**. **Size is normalised by height (`ART_H` 1400)** — every full-body art has the figure filling a height of 1024 with only widths of 572–756, so fitting by width would make figure heights vary. When stepping back, the node size stays and **only `scale`** shrinks: `pivot_offset` is the **bottom centre**, so the baseline stays put as it shrinks and the two read as standing on the same floor. **All 30 mech art slots are filled** — `MechImages.full_for(mech.id)` looks up `res://resources/images/mech/{id}_full.png` (if missing, `ResourceLoader.exists` quietly gives null → a faint α 0.30 silhouette slab + mech-name placeholder). Pilot arts are 1024 tall with widths varying 572–756, but **mech arts are a fixed 1024×1024 canvas** — mech renders have swords·wings extending sideways so the bounding box ratio reaches 1.5, and height normalisation converting that width as-is would spread to twice the screen width. So size was also matched by **opaque pixel area** rather than bounding box, to even out the apparent size of the body. Source (24 Gundam Evolution mech renders) and the id ↔ mech table are in `resources/README.md`. **The info block moved down** (`STAT_TOP` 170 → 640 → **650**, header at 452, tabs at 562) — because as the art grew the upper half of the screen became the place for the figure's head·upper body; behind the text a backing `Panel` (α 0.86) is laid to fit the content height. **The close button follows the backing's bottom edge** (`_reposition_close`) — its position changes only at the moment a tab is pressed, and `refresh()` doesn't touch the backing, so the button doesn't jitter with the numbers. The old fixed y (1424) left just the button floating in the middle of the screen on the in-game tab. |
| Deck / discard piles | The Deck / Discard in the gutters either side of the hand row are drawn as **stacks of cards lying down, tilted away** (`ui/CardPileStack.gd`) — card backs face up, piled on each other, with the edges of the cards below poking out beneath the stack. Previously it was a single two-line Label, `"Deck\n18"`: the number was readable but the pile **didn't look like an object**, so nothing on screen showed where cards came from or went. Two things make it look lying down — the height is squashed by `FORESHORTEN` (0.55), and the **top edge is drawn narrower than the bottom edge** (`TOP_EDGE_SCALE` 0.78) to add perspective. **Thickness is the count** (one layer per 4 cards, capped at 8 layers). **The baseline is fixed and it only grows upward** — fixing the vertical centre makes the stack jitter up and down every time a card comes or goes. The count is printed in the middle of the top card's back and the title is attached below the stack. The count comes in as a `float`, so during the reshuffle tween the thickness rides the same curve. At 0 cards, an empty slot with only its border. **The back is painted uniformly in one colour, the same as `Card._apply_back_style`** — it used to overdraw a per-pile accent trapezoid inside the face (deck purple / discard reddish-brown), but the stack is small, so that frame read as **a gradient sitting on the face** rather than a pattern, and the title labels below already tell the two piles apart. |
| Cards coming and going on the piles (ghosts) | If only the number changes, nothing on screen shows a card **came out of / went into** the pile. So the stack draws one more **ghost** shaped like the top card (a single trapezoid inside `_draw()` — not a node, so no effect on layout · input · z-order). **The deck's ghost rises by `GHOST_RISE_PX` (74px) and vanishes** (`play_pop`, on draw), and **the discard pile's ghost settles down from that height and appears** (`play_land`, on discard). One card takes `GHOST_SEC` (0.26 s), and several must be able to run at once, so they're driven by a `_ghosts` array + `_process` rather than tweens. **The two seams follow opposite rules**: the draw's entry from the left (`_play_draw_intro` ①) starts not after the ghost has fully vanished but when `GHOST_HANDOFF_ALPHA` (0.30) of its alpha remains (0.182 s), so they **overlap** (starting after it fully vanishes looks choppy, as if one card came out twice). Conversely the discard's landing ghost departs **after** the hand card has finished falling (0.30 s), so they **join end to end** — a draw is a picture of one card running on from deck to hand, while a discard is a picture of a card that left the hand arriving at the pile. The landing side is called by **noticing the count increase in one place** (`CardPhaseManager._notice_discard_gain` ← `update_deck_discard_labels`): there are seven places in code where the discard pile receives cards, but only one place where the number changes, and shrinking cases like a reshuffle have a negative delta so they're filtered out automatically. **Exhaust (`exhaust`) doesn't go to the discard pile, so there's no ghost either.** |
| Screen fit (safe area) | **The HUD constants stay as the 1080×1920 design values and the top/bottom blocks are shifted by two scalars** — `HudBuilder.top_offset()` (= `ScreenMetrics.top_y()`) and `HudBuilder.bottom_offset()` (= `ScreenMetrics.bottom_y() − 1920`). Top panel ↔ opponent hand peek ↔ enemy donut ↔ kill log interlock pixel by pixel, and at the bottom so do hand fan ↔ card bottom edge ↔ ally strip, so adapting constants one by one per device quietly breaks those relationships. `BattleSim.BS_HAND_CENTER.y` also takes the same `bottom_offset()` in `_ready`, so the hand ↔ strip spacing stays the same on every device. The stretch is **`expand`**, so on a phone the width is exactly 1080 and only the height extends (with zero insets · 9:16 both offsets are 0, so the layout doesn't differ by a single pixel from before — measured). Full-screen dims must use `ScreenMetrics.viewport_size()`, not a `1920` literal. Conventions · per-device values · desktop verification are in **`docs/mobile_safe_area.md`**. |
| Opponent hand layout | The opponent hand is also an overlapping **fan**, shaped as the player hand **flipped top-to-bottom**: the circle's centre is *above* the cards, so θ=0 is the lowest point of the arc, and therefore **the middle card protrudes furthest down below the panel while both ends curl back up**. Tilt is `−θ` (mirroring the player fan's left/right lean). With `HudBuilder.AI_HAND_FAN_RADIUS` 620 / `AI_HAND_FAN_STEP_DEG` 3.2 / `AI_HAND_FAN_MAX_SPREAD_DEG` 28, the centre spacing between cards narrows from 34.6px (overlapping more than half of a 72px card) down to 26.9px at 12 cards. The detailed formula is in `ui/README.md`. |
