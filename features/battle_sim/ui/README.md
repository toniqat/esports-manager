# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | 전략 포인트 ring gauge; the player's one doubles as the 턴 넘기기 button |

## HudBuilder.gd
`extends Node` — child of BattleSim.

Builds the battle HUD and updates it via `update_hud()` (per-turn) and
`update_time_label()` (every frame from `BattleSim._process`).

### build_ui()
Creates UI inside `_bs.canvas` (a CanvasLayer added to BattleSim):

- **AI hand peek** — row of face-down `Card.tscn` instances scaled to
  `AI_HAND_SCALE` (0.45) sitting at `AI_HAND_TOP_Y` (80 px). Built BEFORE
  the top panel so the panel z-orders above and clips the cards' top
  portion — only the bottom ~50 px protrude below the panel, just enough
  to convey hand size without revealing card data. Synced via
  `update_ai_hand_visuals()` from `CardPhaseManager.do_battle_turn`,
  `_effect_draw`, `_effect_discard`, and `_effect_exhaust_choice`.
  `pop_ai_hand_card_node()` reparents the rightmost back to `_bs.canvas`
  for `AiCardPlayer`'s fly-to-centre animation.
- **Top panel** (y=10, h=120) — Pilot status board with **all 10 pilots**:
  5 player slots on the LEFT, center column (time + total score), 5 enemy
  slots on the RIGHT. Has an explicit opaque dark `StyleBoxFlat` so the AI
  hand peek behind it stays visually clipped regardless of theme.
- **Hand indicators** (in the gutters either side of the card row) —
  `lbl_deck_count` (left, "Deck\n10") and `lbl_discard_count` (right,
  "Discard\n0"). CardPhaseManager updates the text on every draw / play and
  tweens the counts during a deck/discard reshuffle. Built by
  `_build_hand_indicators()`. The gutter is **not** `BS_HAND_AREA_MARGIN` —
  `BS_HAND_WIDTH_SCALE` widens the card row past it, so the gutter is derived
  as `min(BS_HAND_AREA_MARGIN, (screen_w − BS_HAND_WIDTH) / 2)` (89px at 1080)
  and the font shrinks with it (22 → 20) so "Discard" still fits and no card
  ever overlaps a label.
- **전략 포인트 도넛 ×2** — `CostDonut` ring gauges in the right-hand gutter
  (see below). Built by `_build_cost_donuts()`.
- **Bottom strip** (y≈1790..1920) — empty. The old dual cost bars and the
  rectangular 단계 넘기기 button that used to live here are gone; the bottom
  40 px stay reserved for the iPhone home-bar / system gestures either way.
- **Victory panel** — Win/lose label + Play Again button.
- **Turn announcer** (built last, full-screen Control overlay) —
  `play_turn_announce(is_player)` sweeps a 110-px-tall coloured bar in
  from the centre with the message "당신의 차례" (blue) or "상대 차례"
  (red), holds, then fades out. Awaitable; `CardPhaseManager.start_card_phase`
  blocks the player hand on the player banner, `end_card_phase` runs the
  enemy banner before any AI plays unfold. The on-screen battle log was
  removed; `_bs.last_log` is still updated by effect handlers but renders
  nowhere.

Buttons removed: **Next Turn**, **Auto Play** and the rectangular
**단계 넘기기** button are all gone — BATTLE auto-ticks every
`AUTO_PLAY_INTERVAL` (0.5s) inside `BattleSim._process()`, and ending the
작전 단계 is now done by tapping the player's 전략 포인트 donut twice.

Connections:
- `cost_donut.end_turn_pressed` → `_bs.card_phase.end_card_phase` (the manager
  also re-checks `can_end_card_phase()` defensively)
- Play Again button → `_bs._on_restart_pressed`

### 전략 포인트 도넛 (`CostDonut.gd`)
Both sides' 작전 점수 read out on a ring gauge in the right-hand gutter
(`x = screen_w − BS_HAND_AREA_MARGIN / 2`, i.e. 1015 on a 1080-wide screen):

| Donut | Position | Interactive |
|---|---|---|
| `_bs.cost_donut` (player, blue) | above the Discard counter, clear of the targeting overlay's 취소/확인 row → centre (1015, 1354) | yes |
| `_bs.cost_donut_enemy` (enemy, red) | top-right, under the AI hand peek → centre (1015, 255) | no |

- Ring is full at `PHASE_THRESHOLD` (8); the number in the middle is the raw
  point total, so boost cards read as "9 on a full ring".
- Fill sweeps clockwise from 12 o'clock (`START_ANGLE = -PI/2`).

**Player flip → 턴 넘기기** (`CostDonut` owns the whole interaction):
1. tap the donut during 작전 단계 → the ring unwinds through empty and
   re-winds counter-clockwise (`_sweep` tweens `ratio*TAU → -TAU`) while the
   face swaps from the number to "턴 넘기기".
2. tap it again → `end_turn_pressed` fires (only while `set_end_enabled(true)`;
   a disabled face renders grey and swallows the press).
3. tap anywhere else → flips straight back to the point readout. That press is
   deliberately left unhandled so whatever was actually clicked still reacts.

Input runs through `CostDonut._input`, not `_gui_input`: hand cards call
`accept_event()`, so a `_gui_input`/`_unhandled_input` pair would never see the
outside tap. Presses landing inside the donut are consumed with
`set_input_as_handled()`.

State setters driven from `HudBuilder._update_cost_donuts()`:
`set_value(cost, PHASE_THRESHOLD)`, `set_flip_allowed(in_card_phase)` (turning
it off un-flips), `set_end_enabled(can_end_card_phase())`.
`set_locked(true/false)` is called by `CardTargetingOverlay` while a targeting
modal owns the screen — the readout stays visible but the flip is blocked.

### Pilot Slots (top panel, both teams)
Each slot has a **face portrait** with a **horizontal HP bar directly under
it** and a **score label below the bar**. Layout per slot (84×108 inside the
top panel):
- **Face portrait** — `TextureRect` driven by `PilotImages.face_for(pilot.pilot_id)`
  (76×76 px). Sits on top of a role-coloured `ColorRect` fallback that shows
  through when no face image is available (standalone runs, INTL pilots
  without art). The face is `STRETCH_KEEP_ASPECT_COVERED`. The role
  abbreviation (T/F/A/S/Sn) is overlaid in the bottom-left corner with a black
  outline so it's still readable against the photo. Dead pilots desaturate
  the face via `modulate` (and the fallback bg goes greyscale).
- **Horizontal HP bar** — `ProgressBar` with `fill_mode = FILL_BEGIN_TO_END`,
  76×6 px, sits 2 px below the face.
- **Score label** — placeholder `"1.0k"` for now (real scoring system TBD).

Slots are sorted left-to-right by `LanePosition` (LEFT → CENTER → RIGHT →
GUERRILLA). Empty slots (before pilots spawn) are hidden.

Role colors: TANK=blue, FIGHTER=orange, ASSASSIN=purple, SUPPORT=green, SNIPER=red.

### Center column (time + total score)
Sits between the player and enemy pilot blocks (~220 px wide).
- **Time label** — small (`font_size=18`), top of the center column. Format
  `MM:SS` from `_bs.get_elapsed_ingame_seconds()`. **Hours not shown — minutes
  may exceed 60.** Seconds tick smoothly in real-time during BATTLE (1 turn =
  0.5 real seconds = 60 in-game seconds, so the clock runs ~120× wall time).
  Frozen during CARD_PHASE / game-over.
- **Total score label** — large (`font_size=28`), placeholder `"1.0k - 1.0k"`.

### update_hud() (per-turn)
- Calls `_update_cost_donuts(in_card_phase)` — pushes both sides' 작전 점수
  into their ring gauges and gates the player donut's flip / 턴 넘기기 press
  on `game_phase == CARD_PHASE` and `card_phase.can_end_card_phase()`.
- Calls `_update_pilot_boards()` which re-sorts `_bs.pilots` by team and lane,
  then calls `_apply_slots()` for both player and enemy slot arrays.
- Calls `update_time_label()` (also called every frame from `_process`).

### update_time_label() (per-frame)
Pulls `_bs.get_elapsed_ingame_seconds()` and formats as `%02d:%02d`. Called
from `BattleSim._process` every frame so the clock visibly ticks even when no
HUD-state event fires.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.
