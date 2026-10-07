# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | Strategy points (전략 포인트) gauge — a **strategy octagon** (`StrategyIcon`, pointy top/bottom; the inline / cost-ribbon indicator is the flat-top pose), 8 faces = 1 point each, filled clockwise from the upper-right face; 9–16 fill a second, lighter lap (`OVERFLOW_LIGHTEN`), past 16 only the number grows. The player's one doubles as the "턴 넘기기" (End turn) button (flip = counter-clockwise lap) |
| `CardPileStack.gd` | CardPileStack | Deck (덱) / discard pile (버린 더미) — a stack of cards lying face-down, tilted away + card count |
| `PilotStrip.gd` | PilotStrip | 5-pilot (파일럿) strip (스트립) — **circular portrait (team-colour disc + a bust whose head pokes out above the disc, no rim) + a growth points (성장치) tab hanging below the disc**. The backplate is transparent. Two copies, top (enemy (적)) / bottom (ally (아군)). Pressing a portrait scales it up (`BattleRenderer.PRESS_SCALE`, like field markers). **Ally: short tap = skill popup, long press = detail panel. Enemy: tap / long press = detail panel.** Ally cells carry a round **skill badge** (`SkillBadge`) at the disc's lower right. Only a downed pilot's bust is dimmed (the disc stays). While a card is dragged the ally strip dims and drops (`HudBuilder.set_player_strip_dropped`) |
| `SkillBadge.gd` | SkillBadge | Round pilot-skill badge on an ally strip portrait — icon (dimmed icon-only when unusable), cooldown radial + turns left, segmented stack ring |
| `SkillPopup.gd` + `SkillPopup.tscn` + `SkillPopupCard.tscn` | SkillPopup | Skill popup above a tapped ally portrait — no dim / no border, rises + fades in (0.2s) / out (0.1s), cooldown as clock + turns, hold a card name → card + desc preview, **사용** (Use) button inside. **Scene-authored** (`SkillPopup.create()`): the scene holds the layer + outside-tap catcher, one `SkillPopupCard` (plate + arrow) is instanced per open |
| `ReservationChips.gd` | ReservationChips | **Reservation chips (예약 칩)** — card effects settled at a later step (next strategy points · next draw · kill bounty · ambush search) stacked above the ally donut as card art + value chips |
| `ObjectiveTimer.gd` | ObjectiveTimer | Objective (오브젝트) spawn clock — icon + turns remaining on either side of the enemy strip (left Herald (전령) / right Dragon (용)). **Pressing it opens the reward popup** |
| `ObjectiveRewardPopup.gd` | ObjectiveRewardPopup | Objective reward preview — pressing a clock shows the actual cards that objective grants |
| `PilotDetailPanel.gd` + `PilotDetailPanel.tscn` + `PilotDetailView.tscn` (+ 7 item scenes) | PilotDetailPanel | **Scene-authored** (`PilotDetailPanel.create()`; one `PilotDetailView` instanced per open). Pilot detail modal — left: 2 full-body arts (+ lasting effects at bottom-left) / right: header (growth points top-centre) + 3 tabs + a stat cell plate (full-width rows / rows of two half cells; every cell name is prefixed with a `CHIP_ICONS` icon, HP · attack values are followed by `(+N)` against the base value — + green / − red; presence only when a pilot skill raised it (`PilotSkillSystem.presence_delta`)). Pressing a cell opens a note plate on the left — the same look as the card description box (`CardDescBox.panel_style`: opaque · borderless · drop shadow below); the note is a `RichTextLabel`, so `{attack}` · `{engage}` become icons, and its height is measured from the rendered text (`_fill_note` + `get_content_height`). Presses that miss within `INFO_ZONE_PAD` (40) around the info column don't close it (`_info_zone`) + **pilot skill plate** (three separate plates) / **held-card fan at the same spot and width as the hand** (6 cards; cards that don't match the tab are dimmed) — pressing a card shows the same description box as the hand. No close button — tapping outside closes it. Open 0.2s / close 0.1s slide + fade |
| `MarkerTouch.gd` | MarkerTouch | Pressing a battlefield (전장) portrait — while held it grows to `PRESS_SCALE` and moves to the top (it stays on top after release); **long-press (0.45 s) opens the detail panel** |
| `KillFeed.gd` | KillFeed | Kill log — top-right, one line per kill (처치) / turret (포탑) demolition / objective capture. Kills during an engage (교전) are flushed together after the arena closes |
| `MvpView.gd` + `MvpView.tscn` | MvpView | **Scene-authored** (`MvpView.create()`). **Match MVP view** — full-screen dark card shown at match end **before** the victory/defeat panel: MVP's full-body art + name · side · position · K/D/A · key-metric line, "계속" (Continue). Also hosts the shared display strings (`display_name` · `role_label` · `kda_text` · `metric_text`) the result panel's MVP line uses. See "Match end — MVP view → result panel" below |

### Scenes and the dark theme (`docs/ui_scene_migration.md` §4 #13)
The battle UI is moving to `.tscn` like the outgame UI (same rules — `docs/ui_scene_migration.md` §3), on its
own dark Theme **`resources/BattleTheme.tres`** (palette · variation list: `resources/README.md` → BattleTheme).
Done: `MvpView`, `SkillPopup` (+ `SkillPopupCard` item scene), `PilotDetailPanel` (+ `PilotDetailView` and item
scenes). Still code-built: `HudBuilder` + `PilotStrip` — their colour constants already alias `BattleTheme`
(values unchanged). Scene ↔ code split for the converted ones:

| Scene owns | Code owns |
|---|---|
| `MvpView.tscn`: layer 60, `Root` (theme, taps) → `Dim` · `%SafeArea` → `Title`, `%ArtArea` (from 170 below the safe top to 530 above the safe bottom) → `%Glow` · `%ArtHolder` → `%Art` / `%Slab`(+`%FallbackLabel`), `Info` (`BattleGoldPanel`, 330 tall, 190 above the safe bottom, sides 60) → `%Name` · `%Side` · `%Kda` · `%Metric`, `%Continue` (40 above the safe bottom, 120 tall, sides 120) | safe-area offsets, side line variation (`MvpAllyLabel` / `MvpEnemyLabel`), art / slab size from the texture aspect and the area height (`_layout_art`, on `%ArtArea.resized` — `ART_MAX_H` 1000 / `ART_MAX_W` 900), glow colour (`BattleTheme.GLOW`), fade + rise (`%ArtHolder` offset 40 → 0) |
| `PilotDetailPanel.tscn`: `PilotDetailLayer` (13) → `%Root` (theme). `PilotDetailView.tscn` (per open): full-rect root (STOP) → `%Dim` (`BattleDimPanel`, the "outside"), `%ArtHolder` → `%ArtMech` · `%ArtPilot` (`PilotDetailArt.tscn`: `%Texture` / `%Slab` (`PilotDetailArtSlab`) + `%FallbackLabel` at 42%), `%InfoColumn` → `%FxGrid` (Grid 6 cols, sep 12, x 26, grows **up**), `%Column` (VBox sep 16 at (578, 362), width 496) → Header (`BattlePanel`: GrowthBox 48 / NameBox 52 / MechBox 32 → `%Growth` · `%Name` · `%Mech`), StatGroup → TabsMargin (22) → Tabs (HBox sep 8, 62) → `%TabIngame` · `%TabPilot` · `%TabMech`, StatPanel (`PilotDetailStatPlate`) → `%Chips` (VBox sep 10) · `%DeadGap` 12 · `%DeadBox` 30 → `%DeadLabel`, `%SkillPanel` (`BattlePanel`) → `%SkillTop` (`%SkillIconSlot` 92² · gap 18 · NameBox 40 → `%SkillName`, gap 4, `%SkillDescSlot`, `%SkillStatusGap` 8, `%SkillStatusBox` 30 → `%SkillStatus`), `%SkillUseGap` 16, `%SkillUse` 68, `%NoSkillBox` 32; `%CardFan`, `%CardFanHits`; `%InfoMenu` (backdrop, last = top). Items: `PilotDetailStatRow` (HBox sep 10) + `PilotDetailStatCell` (`BattleChipButton`, `%Icon` · `%Name` · `%Value` · `%Bonus`), `PilotDetailFxThumb` (`BattleFxButton`, text mode `%Short` · `%Value` / art mode `%Art` (rounded mask) · `%Band` (`PilotDetailFxBand`) · `%BandValue`), `PilotDetailCardBand` (empty look), `PilotDetailInfoMenu` (`PilotDetailMenuPanel`, min width 372 → `%Title` (36) · gap 8 · `%Rows` · `%NoteGap` 6 · `%Note` · `%NoteTail` 4) + `PilotDetailInfoRow` (36, key 42% / value 58% by anchors) | art size from the texture aspect + pivot + front / back pose and swap tween, `%FxGrid` bottom (= fan top − `FX_ABOVE_FAN_GAP`), chip rows per tab (`_chip_defs`), cell / thumb highlight (switch to `BattleChipButtonOn` / `BattleFxButtonOn`), tab on / off (`BattleTabOn` / `BattleTab`), bonus colour (`BattlePositiveLabel` / `BattleNegativeLabel`) and value right edge (bonus width), effect abbreviation colour (data), skill icon tile · rich description (code widgets into the slots), note text (`_fill_note`) + its measured height, info plate position · height (`_place_menu`, re-placed next frame after a body rebuild), card fan + bands (positions from the hand geometry), card description boxes (`CardDescBox`), open / close motion |
| `SkillPopup.tscn`: `Layer` (12) → `%Root` (theme) → `%Catcher` (top-wide). `SkillPopupCard.tscn`: full-rect root → `%Panel` (`BattlePopup`, min width 640) → VBox (sep 10): Head (72: `%IconSlot` · gap 16 · NameBox(top 16) → `%Name` · TypeSlot 110 → `%Type` / `%Cooldown`(`%Clock` · `%Turns`)), `%DescSlot`, `%StatusBox`(30) → `%Status`, `%UseGap`, `%Use` (68); `%Arrow` (Polygon2D, after the panel) | catcher height (= strip top), panel position (above the portrait, clamped by `SCREEN_MARGIN`) and height (`get_combined_minimum_size`), arrow polygon + colour (`BattleTheme.POPUP_BG`), icon tile (`SkillImages.make_icon_tile` → `%IconSlot`), rich description (`StrategyIcon.make_rich_label` → `%DescSlot`, height `rich_height`), name variation (`BattleSkillNameLabel` / "스킬 없음" `BattleKeyLabel`), card-name press preview (Card + `CardDescBox`, code) |

Fixed heights that look odd are deliberate pixel parity with the old code: the name row is a 40px label at
+16 in the 72px head, and the status row is a 30px box with the label anchored inside — the label's own minimum
(42 / 31 px at those fonts) must not grow the row. `PilotDetailView` does the same for every text row (header
48 / 52 / 32, dead line 30, skill name 40 / status 30, "스킬 없음" 32, note title 36): a fixed-height box with the
label anchored top-wide, so the label overflows downward exactly like the old clamped `size`. F6 previews:
`MvpView` (pilot 0's art, hand-made row), `SkillPopup` (hand-written cooldown skill via `_show`, no battle — use /
status refresh / card preview need one), `PilotDetailPanel` (spawns a standalone `BattleSim.tscn` beside it, gives
pilot 0 the first skill and opens it — tabs · cells · cards all work; standalone battles have no rosters, so the
pilot tab shows `—`). The `PilotDetail*` item scenes have no script — sample text is baked in.

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
  pilot strip by `ENEMY_BG_PAD` (10) on every side. **It is now transparent**
  (`StyleBoxEmpty` — the strip background was removed, see `STRIP_BACKDROP_NOTE` in
  `HudBuilder`); the node survives only as the counterpart `set_strip_visible` toggles. It
  used to be opaque and hid the top of the opponent's (상대) hand peek; now the top of the
  peek shows **behind** the portraits. The ally strip sits below the hand row — see the
  Pilot strip section below.
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
  and the count font is derived from it (`CardPileStack.setup()`) so no
  card ever overlaps a pile. The inset is **4px** (the old labels used 8) —
  the pile's width *is* the card's width, so it takes everything the gutter has.

  > **This spot used to be a single two-line `Label`, `"Deck\n18"`.** The number
  > was readable, but the pile didn't look like an object, so nowhere on screen showed
  > where cards entering the hand came from or where discarded cards went.
  > `lbl_deck_count` / `lbl_discard_count` disappeared then.
- **Strategy point donuts ×2** — `CostDonut` ring gauges in the **left-hand** gutter
  (see below). Built by `_build_cost_donuts()`.
- **Ally pilot strip** (y 1644..1888) — below the hand row. This used to be empty
  (where the bottom cost bar and the rectangular phase-skip button were removed). The
  bottom ~32px is left for the iPhone home bar / system gestures. `_build_player_strip()`.
  **One backplate `Panel` lies behind it** (`PlayerStripBackdrop`, y 1634..1898) —
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

### Reservation chips (`ReservationChips.gd`)
Stacked **above** the ally donut (screen-left x 8, width 150 — wider than the donut column).
One chip = rounded-rect card art (the card that placed the reservation,
`BattleSim.reserve_src`) + value. The values (`next_phase_strategy_p` · `next_phase_draw_p` ·
`kill_bounty_p` · `ambush_search_p`) are compared by a per-frame signature (the `_entries()` array, compared by value — no `str()`
per frame) and redrawn only
when they change, so a chip disappears on its own once it settles to 0. There is none on
the enemy side (below the enemy donut it would overlap the battlefield's top-left tiles).
The card art is drawn only via `_draw`, so it is uploaded to the GPU first with
`BattleSim.prime_texture` — otherwise it paints a white box (same problem as
`PilotImages.prime_into`).

### Strategy point donut (`CostDonut.gd`)
**Hand preview** (`set_preview(on, gain, value_after)`): while a hand card that changes
strategy points is pressed, the outer ring pulses, the amount to be added (`+4`) floats
above, and the centre number is printed in a changed colour as the result after paying the
cost, with the gauge filled to that value. During the preview `set_value` does not move the
gauge.

Both sides' operation points read out on a gauge in the **left-hand** gutter
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
- Fill runs clockwise face by face from the octagon's upper-right face; 9–16 points fill a
  second, lighter lap (`OVERFLOW_LIGHTEN`), and past 16 only the number grows.

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
it overlaps the bright edges of the layers below). **There is no title label** — a
"Deck" / "Discard" `Label` child used to sit below the stack but was deleted; the two piles
are told apart by their position, left / right of the hand. The stack (height at
`MAX_LAYERS`) stands at the vertical centre of the rect (`_base_y()`).

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
sitting on the face** rather than a pattern. The two piles' spots either side of the hand
already tell them apart, so there's no reason to separate them by colour too. The `accent`
argument and the `PILE_ACCENT_*` constants disappeared at the same time, and since the
title label went, `setup()` takes no arguments (only the number font is derived from the
gutter width).

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
| Enemy (`_enemy_strip`) | direct child of `_enemy_top_layer` (see "Top enemy UI layer" below), `ENEMY_STRIP_RECT` (25, 2, 1030×244) — **same size as the ally one** | disc diameter ≈127 | press for detail panel |
| Ally (`_player_strip`) | **below** the hand row, `PLAYER_STRIP_RECT` (25, 1644, 1030×244) | disc diameter ≈127 | press for detail panel |

**The portrait is 70% of the size derived from the cell** (`PilotStrip.PORTRAIT_SCALE`).
`setup` first lays out the unscaled layout (disc diameter = min(cell width − `CELL_GAP`,
height × 0.8)) to fix **the spacing between discs and the disc-centre height**, then shrinks
only the diameter — the spacing stays, so the whole row narrows and gathers at the strip's
horizontal centre (`_row_x`), and since the disc-centre height stays, alignment with the
objective clocks either side of the enemy strip (`OBJ_TIMER_Y`) is kept. The strip rect
itself doesn't change, so the chain below it (hand row · peek · kill log) stays too.

#### Circular portrait (current look)
Follows `deadlock-ex1.png` at the repo root (a Deadlock broadcast HUD). **Both strips are
twice their eye-band-era height** (enemy 100 → 200, ally 122 → 244), and one cell is:

- **Team-colour disc + bust** — one `ColorRect` with
  `resources/shaders/pilot_bust_mask.gdshader`. The bust is `PilotImages.strip_for` =
  `strip/N_strip.png` (256×320, transparent background, baked from the full art by
  `make_strip_crops.py` with the same face-template matching as the eye crops — mobs use
  `mob/strip`). The shader cuts **below the disc centre to the disc shape and above it only
  to the disc width**, so the head pokes out above the disc. The cell ratio is
  `PilotImages.STRIP_ASPECT` (0.8) and disc diameter = cell width. Without an image
  (standalone run / INTL) the disc is still drawn. **Source art with an opaque background**
  (some pilots) shows a rectangular protrusion above the disc — the source alpha isn't the
  figure's outline.
- **The disc rim was deleted** — the shader is passed `rim_width = 0` (at 0 the shader skips
  the ring entirely; a plain SDF would still leave a 1px line at the edge).
- **Growth points tab** — a rounded-rect `Panel` in the disc's team colour, attached
  **before** the disc: its top starts at the disc centre and is covered by the disc (bust),
  showing only `_pill_h()` below the disc's bottom edge — one piece hanging down from the
  disc, not a separate pill. The number sits only in the visible part, formatted by
  `PilotStrip.fmt_strip_score` — one decimal (`9.9k`), **integer from 10k up** (`12k`). The
  detail panel still uses `BattleSim.fmt_score`.
- **Skill badge** — round `SkillBadge` straddling the disc's lower-right edge (ally only).
  See "Pilot skill display" below. The old top-right number badge is gone.
- **Downed (off the battlefield)** — the shader `tint` greys out **only the bust**. The team
  disc stays, so an empty seat still reads as that team's. The turns until revival sit in the
  middle of the disc.
- **While a card is dragged** the ally strip darkens and drops by `STRIP_DRAG_DROP` (120),
  returning on release (`HudBuilder.set_player_strip_dropped`; the backplate stays). The old
  **caster neon** (`set_highlight` / `HudBuilder.set_strip_caster`) was deleted.
- **The HP bar was deleted** — HP is shown by the battlefield markers and the detail panel.

Making room: the ally strip kept its bottom (1888) and grew upward; the hand row
(`BattleSim.BS_HAND_CENTER.y`) went 1440 → **1370** and the battlefield
`BattleSim.FIELD_LIFT` 100 → **140** with it (so the confirm/cancel button row 1304..1360
doesn't touch the battlefield's bottom). On the enemy side `TOP_PANEL_H` went 148 → **248**
and the chain moved down 100px each (`AI_HAND_TOP_Y` 198, enemy donut bottom 427,
`KillFeed.FEED_TOP` 256, objective clock `OBJ_TIMER_Y` — the disc-centre height — 126, now
110 with the enemy strip at ally size). The history paragraphs below carry eye-band-era
values.

**The enemy strip is now the same size as the ally one** (1030×244) — the disc takes its
diameter from height, not cell width, so the five faces stand only within x ≈161..919 and
the objective clocks sit in the remaining side margins as before. Its bottom (246) was kept
the same as the old 806×200 and it grew 44px upward (y 46 → 2) — the chain below
`TOP_PANEL_H` stays put, and only the clocks followed the disc centre up, `OBJ_TIMER_Y`
126 → **110**. What follows is the earlier history.

**The enemy strip was (at one point) 66% of the ally one** and sat horizontally centred. Its
size changed four times: it started as a 730×84 shrunken version (portrait 130×54) — showing
the same faces at two very different sizes top and bottom meant neither who the opponent
was nor the opponent's growth points read as well as the ally side — so it was enlarged to
**exactly** the ally's 1030×122 (that's when the top panel grew 130 → **168** and the chain
below it moved down 38px). The reason for shrinking it again was space: when the objective
spawn clocks moved from the battlefield tiles up to this panel, **cells for icon + turn
count on either side of the strip** were needed (`ObjectiveTimer.gd`). Growth points were
still readable up to two digits, so the original purpose of "compare side by side with
mine" survived.

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

(Eye-band era) a cell was, top to bottom, **eye-level portrait → HP bar → growth point number**.

- **Eye-level portrait** — `PilotImages.eye_for(pilot_id)`. `eye/N_eye.png` is a
  **480×200 crop cut wide horizontally so both eyes show**, and the cell height was derived
  from that ratio (`EYE_ASPECT` = 2.4) — stretching to an arbitrary height distorts the
  face. With no image (standalone run / INTL) the backing `ColorRect` simply showed.
  The border was a team-coloured `Panel` frame; a downed pilot was darkened via `modulate`
  and the **number of turns until revival** was printed in a large font in the middle of
  the portrait.
- **HP bar** — **two `ColorRect`s** (backing + fill). **Do not use `ProgressBar`**: it
  computes a minimum size from the theme stylebox's content margins and pulls `size` up to
  it (about 24px with the default theme), so even when a 6–10px bar was requested it drew
  at 24px and overwrote the growth point label right below (confirmed by measurement (실측)).
  With a shield attached the fill turned yellow — the reason for not appending a segment
  to the bar is that at 6–10px it's too thin for the two sections to be distinguishable.
- **Growth points** — `BattleSim.fmt_score(p.score)` → `"24.9k"` (decimal places drop as
  digits grow: `1.00k` → `24.9k` → `125k`). **It's a number, not a gauge** — there's no
  cap, so there's nothing to fill against. It opens at `SCORE_START` (const.csv) and climbs
  through the match, a well-fed carry well ahead of the rest. It corresponds to the gold display of a MOBA broadcast,
  and **this number drives that pilot's attack multiplier** (`GROWTH_ATK_PER_SCORE`, const.csv). For
  the accrual rules see the `SCORE_*` section of `BattleSim`.

Cell order is set by **role** — `GameEnums.ROLE_DISPLAY_ORDER` / `role_seat()`, the same
table as the outgame screens, i.e. the order you sweep the battlefield from left to right.
The old `HudBuilder.LANE_SEAT_ORDER` table (sorting by `PilotData.lane`) was deleted: two
pilots share the right lane, and the unstable `sort_custom` could swap them between runs.
Sorting is done **on a copy
of `_bs.pilots`** — the original must keep spawn order (= role order) so that
`BattleSim.player_data_for` can find the roster by that index.

**(Old value) the bottom strip's y (1766) was computed from the bottom edge of the cards** —
it is now 1644, with the hand row raised 70px to keep the same rule (worst card bottom
≈ 1633 < backplate top 1634). The cards at both ends of the fan sag 21.4px below the middle
(at 12 cards) and grow by `Card.HOVER_SCALE` (1.2) when hovered/selected, so in the worst
case the card's bottom edge came down to y ≈ 1763. At 1724 the cards covered the top of the
portraits (confirmed by measurement).

**Ally strip backplate** — `PlayerStripBackdrop`, one `Panel` that extends the strip area by
`PLAYER_BG_PAD` (10px) on every side (y 1634..1898). **It is now transparent** (background
removed) — but the node stays: it's the z-order reference `CardPhaseManager` sends the hand
**behind** when it isn't your turn, and the ruler for how far down it goes
(`player_strip_backdrop[_top]`). With the plate transparent, the retreated hand isn't hidden
but shows behind the portraits. (What follows is the reasoning from when it was opaque.) The
enemy strip sat on the top panel so it had backing from the start, but the ally strip
floated directly on the screen, so the three rows face · HP bar · growth points looked
scattered with no background — growth point numbers in particular, without backing, don't
show where one pilot's cell ends. **`_build_player_strip()` adds it before the strip**
(sibling z-order is child index, so if added later the plate covers the portraits) and
**`set_strip_visible(0, on)` hides it together with the strip** — if the detail panel
cleared only the strip, an empty plate would be left alone on top of the dim.

**Input gate**: `set_interactive_enabled(pilot_detail.can_open())` — outside the
operation phase · auto-run (BATTLE) (engage stage (교전 무대) · before the opening · match
over), the hit buttons are `disabled`. Hit testing is taken by a transparent `Button`
covering the whole cell (`Label` / `TextureRect` default to `MOUSE_FILTER_IGNORE` by
class, so they can't receive clicks themselves).

**Press / tap / long press** (`PilotStrip`, both strips):

| Gesture | Strip signal | Ally (`HudBuilder`) | Enemy |
|---|---|---|---|
| `button_down` | — | cell `holder` tweens to `BattleRenderer.PRESS_SCALE` around the disc centre, `z_index` 1 | same |
| held `MarkerTouch.LONG_PRESS_SEC` (finger still inside) | `pilot_long_pressed` | close popup → `PilotDetailPanel.open` (+ `MEDIUM` haptic) | detail panel |
| released inside before that | `pilot_tapped` | `SkillPopup.toggle` (same pilot closes, other pilot switches) | detail panel |

All of a cell's visuals live under one zero-size `holder` Control (pivot = disc
centre) so they scale together; the hit `Button`s stay unscaled. `BaseButton`
emits `pressed` before `button_up`, so the long-press flag is still set when the
release would become a tap. Disabling the button mid-hold cancels the press.

**Hiding the strip cancels the press** (`PilotStrip._notification` →
`_cancel_press`). A long press opens the detail panel, which hides the pressed
team's strip *while the finger is still down*, so the release never reaches the
`Button`: it stayed internally "pressed" (next touch fired no `button_down`) and
`_long_fired` stayed set (that touch's `pressed` was rejected as a tap) — the
first touch after closing the panel was swallowed. On hide the strip resets its
hold state and flips each enabled button `disabled` true→false, the only way to
clear `BaseButton`'s internal press. Only reproducible through the touch path
(`Input.parse_input_event(InputEventScreenTouch)`); mouse `push_input` hides it.

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
│    only those currently applied. No title. Bottom edge attached at fan top − 36; grows **upward**
├─ header (own plate, y HDR_TOP 362 .. HDR_BOTTOM 546) — **separate from tabs, always the same content**
│                     growth points (40pt, centred)
│    pilot name (40pt)
│    mech name  (24pt, line below)
├─ (PANEL_GAP 16)
├─ 3 tabs  [인게임][파일럿][메크] (In-game / Pilot / Mech)  STAT_X 600, width 452/3, TAB_H 62, top 562
├─ right: stat plate  STAT_X 600, STAT_W 452, STAT_TOP 650 (plate grows to fit content height)
│    └ stat cells — small plates on the plate, row height 56 · gap 10. One cell per row = full width,
│      two = half each. Inside a cell: name on the left (22pt) / right-aligned **final value** (28pt)
├─ (PANEL_GAP 16)
├─ (in-game tab) pilot skill plate — its own plate, no title row
│    [icon tile 92² (`SkillImages.make_icon_tile`, soft shadow)]  name
│                                                  description (`StrategyIcon` rich text — keywords · card cost icons · line breaks · particles)
│                                                  one status line (cooldown left / tokens — omitted when "사용 가능" (ready))
│    [               사용 (Use)               ]  (none for passives)
└─ **held-card fan** — same spot (`BS_HAND_CENTER`) · width (`BS_HAND_WIDTH`) · size (×0.96) ·
     tilt · hover · drop shadow as the hand. All 6 cards, no title, spreads slightly only on open
```

- **There is no close button.** The dim (`_dim`) is "outside" — plates · text · art are all
  IGNORE, so pressing anywhere other than a tab · cell · lasting effect · card band · Use
  button lands on the dim and closes the panel **on release** (`_on_dim_input`; closing on
  press would leak the release event to the hand below). **Near the card fan**
  (`_card_zone` — the fan span + `FAN_ZONE_PAD` 24 around it) is the exception — a press in
  the gap between overlapping cards or on a dimmed card mustn't close the screen. With an
  info plate (cell note) open, pressing empty space closes only the plate
  (`_on_menu_backdrop_input`).
- **Open / close motion** — on open the art holder slides in from `ART_SLIDE_PX` (48) to
  the left, the info group (`_ui_root` = header · tabs · body) rises from `UI_SLIDE_PX` (56)
  below, fading in with the dim (`OPEN_SEC` 0.2). On close it's reversed — art out to the
  left, info group down — fading out (`CLOSE_SEC` 0.1). **State clears at the moment of
  `close()`** — `is_active()` is false immediately, so the turn hold releases at once, and
  the departing tree switches its input to IGNORE (`_ignore_input_recursive`) and is freed
  when the tween ends.
- **Pilot skill plate** — the type badge (cooldown / charge-type / passive), keyword tags and
  the "파일럿 스킬" (Pilot skill) title row were deleted. The status line drops out when a
  cooldown skill is ready (the Use button lighting up says the same thing), so the plate
  height changes — `refresh()` compares `_skill_status_shown` with the current answer
  (`_skill_status_visible`) and rebuilds the body if they differ.

| Tab | Art in front | Stat rows | Below that | Live cards in the fan |
|---|---|---|---|---|
| 인게임 (In-game) | pilot | HP (`current / max`) · attack · presence (each full width) / battlefield hit \| battlefield evasion / engage hit \| engage evasion | (when dead) `부활까지 N턴` (N turns to revival) → **pilot skill** | all 6 |
| 파일럿 (Pilot) | pilot | battlefield hit \| battlefield evasion / engage hit \| engage evasion / attack growth \| HP growth | — | pilot cards only (mech cards dimmed) |
| 메크 (Mech) | mech | HP (`current / max`) · attack · presence — **same values as in-game** | — | mech cards only (pilot cards dimmed) |

- **Growth points sit top-centre of the header** (`HDR_GROWTH_H` 48). It used to be a 170px
  cell to the right of the name row, and the in-game tab had a separate `성장 +N%` chip
  (attack growth) — that chip and its menu were **deleted** (the attack / HP growth
  coefficients are on the pilot tab). With one more row, `HDR_TOP` went 408 → **362**.
- **The header is separate from the tabs** (`_fill_header`, runs **only once** in
  `_build`). Name · mech name · growth points belong to the same pilot whichever tab you
  view, so there's no reason to rebuild them on every tab change. This line used to be
  inside the body, and on the mech tab the title changed to the mech name, so **the pilot
  name and growth points vanished from the screen entirely** — in effect, who was open
  wobbled with the tab. The only thing a tab changes is the detail panel below it.
- **The mech name is small on the line below the name, always visible.** It's not a value
  you should have to go into the mech tab to learn. **It used to be appended to the right
  of the name with an `HBoxContainer`**, and since the line's start point was the name's
  width, the mech name started at a different x for each pilot. Stacking two lines makes the
  start point always the same and removes the need to measure text width, so the container
  itself disappeared (each line uses `clip_text`). Fitting two lines raised `HDR_TOP`
  452 → 424, and separating the three plates raised it another `PANEL_GAP` (16) to
  **408 .. 546** — the tab bar (562) is pinned, so it could only go upward (now 362, above).
- **Every tab shows all 6 cards** (pilot 3 → mech 3 order, so the left half of the fan is the
  person and the right half the machine). On the pilot / mech tabs **only that tab's cards
  are live and the rest are dimmed** (`Card.set_dimmed`) and don't respond (they get no band
  button). The pilot / mech tabs used to re-seat only their 3 cards in the same spot.

- **One stat cell = one small plate sitting on the stat plate** (`_make_chip`) — the name on
  the left and **one final value** right-aligned. Base value · increase only appear when you
  press the cell (info panel). Row layout is set by `_chip_defs` as `[[cell], [cell, cell], …]`
  — one cell is full width, two are half each (paired values such as hit | evasion). The old
  3-column chips (141×92, name on top / large value below, `_value_font_size` shrinking the
  font by character count) were deleted, as was the even older `key ─ value` row list
  (`_row` / `_section` / `ROW_H` / `KEY_FRACTION`).
#### Info panel — one plate shared by stat cells · lasting effects · cards
Pressing any of these opens the same plate (`MENU_W` 372) **to the left of the info
column**. "What am I looking at now" must be one thing at a time; with separate plates, a
stat explanation and an effect explanation would show at once and blur which one you just
pressed. There are two reasons for opening to the left — on the right there are only 28px
to the screen edge (1080), and overlaying it on the pressed item would hide the cell you
just pressed under its own explanation.

The vertical position is **the same height as the pressed item**. **Cards don't use this
plate** — the hand-style description box from "Held cards" below stands inside the same
`_menu_root` (backdrop routing · exclusivity are still shared).

**Everything pressable is collected in one table, `_targets`** — `key → {button, style, …}`.
The key prefix distinguishes the kind.

| Key | What | Title | Rows (`_menu_rows`) | Note (`_menu_note`) |
|---|---|---|---|---|
| `hp` `atk` `hit` … | stat cell | cell name | base value · increase · final | what that value decides |
| `fx:lane` `fx:rate` `fx:atk` `fx:shield` | lasting effect (slot) | full effect name | where it multiplies · time remaining · final value | one-line rule |
| `fx:src:<종류>\|<카드>` `fx:rest:<종류>` | lasting effect (per card · remainder) | card name / kind name | this effect · time remaining · **total for that kind** · final value | one-line rule |
| `card:<i>` | card (live ones only) | — | — | **the same description box as the hand** (`_build_card_desc`) — not the plate |

- **The backdrop forwards clicks** (`_on_menu_backdrop_input`). The backdrop is still a
  full-screen STOP, but instead of closing unconditionally as before, it finds the **target
  button / tab** at that coordinate and presses it on your behalf. Previously, with
  the attack explanation open, pressing the hit cell spent the first click on closing, so
  you had to press **once more** — while skimming six stats the clicks doubled and the
  screen flickered between open↔closed. Switching between items is the info panel's default
  behaviour. Pressing an empty spot closes it then. The backdrop (`%InfoMenu`) is a full-screen
  `Control` at (0,0), so the press position is global — each button's **global rect** is tested
  (cells and tabs sit inside containers now).
- **Plate height is set by content** — the plate (`PilotDetailInfoMenu.tscn`) is a container:
  title 36 + gap 8 + rows × 36 + (note: 6 + text + 4), padding from `PilotDetailMenuPanel`. The note
  (`%Note`, wrapping `AUTOWRAP_WORD_SMART` set in the scene) gets its width first, then its **rendered**
  height (`get_content_height`) becomes its minimum height — measuring with a font call instead
  (`get_multiline_string_size`, default break flags) once had the label use one more line than
  measured. The plate is placed in `_place_menu` (x = left of the column, y = the pressed item's
  layout y − 16, clamped to the screen) and placed once more on the next frame, because after a
  body rebuild the new cells are only sorted by their containers at the end of the frame.
- **The name cell is 42%** (`PilotDetailInfoRow` anchors), the rest is the value cell. Back at 52%,
  values like "다음 작전 단계까지" (until the next operation phase) didn't fit in 159px and
  **were clipped from the left** — a right-aligned `Label` that overflows gives up alignment
  and draws from the rect's left. The value wording itself got shorter then too
  (`작전 단계까지` / `레인 전용`).
- **The tab decides which art is front and back** (`_apply_focus`). On the mech tab the
  machine is in front; otherwise the person is. The old **"전환" (Switch) button (pilot ↔
  mech two-state toggle) was deleted** — once the info split into three, a two-state toggle
  could no longer say what was where. The switch tween (`ART_SWAP_SEC` 0.22s) remains.
- **The large number at the top centre of the header is growth points.** The old subtitle
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
- **The info block is at the bottom** (header 362 / tabs 562 / `STAT_TOP` **650**). As the
  art grew, the upper half of the screen became the place for the figure's head·upper body,
  and stats left in their old spot (170) would cover the face. A backing `Panel` (α 0.86) is
  laid behind the text — the art comes up to this area, so text alone would be unreadable
  over the illustration. The active tab **doesn't draw its bottom border**, so it joins the
  backing as one piece.
#### Held cards — same spot · same fan as the hand (`_build_card_fan`)
- **Drawn and moving exactly like the hand.** The same node (`_bs.CARD_SCENE`) is set up with
  `setup(cd, true, …)` (the same `is_player_card` as hand cards — caster ribbon · **drop
  shadow** · hover brighten/enlarge all come along), with only input taken out via
  `MOUSE_FILTER_IGNORE`. Size is `CardPhaseManager.HAND_CARD_SCALE` (0.96, 154×211).
- **The spot matches the hand too** — horizontal centre `BS_HAND_CENTER.x + CARD_W/2` (screen
  centre), row height `BS_HAND_CENTER.y` (+ arc sag; the safe-area offset is already folded
  in), spacing by the `CardPhaseManager.slot_spacing` rule (start at the non-overlapping width
  `cw + BS_HAND_CARD_GAP`, compress evenly past `BS_HAND_WIDTH`) — 6 cards fill the hand width.
  Tilt · sag ride the same circle (`BS_HAND_FAN_RADIUS`). It used to stand in the lower-right
  band under the info column (`FAN_X` / `FAN_W`) with a "보유 카드" (Held cards) title row
  above — both deleted (as were `FAN_SIZE_VS_HAND` / `FAN_EDGE_INSET` / `FAN_DROP_RESERVE` /
  `FAN_BOTTOM_PAD` / `FAN_TITLE_*`, and the old full-width ×1.60 fan with `FAN_LIFT_PX`). The
  hand showing through behind the dim at the same spot is intended.
- **Card nodes are built only once, on open.** `%CardFan` / `%CardFanHits` hang off `%InfoColumn`
  and live apart from the body (chip rows · effect grid · skill plate); tab switches · body rebuilds rebuild **only the
  dims and input bands** via `_rebuild_fan_hits` (card keys are re-registered right after
  `_targets` is cleared). The spread-out motion (dx × `FAN_SPREAD_FROM` 0.55 → in place,
  `FAN_SPREAD_SEC` 0.24) also runs only on open.
- **Cards that don't match the tab are dimmed · unresponsive** — `_fan_card_active(i)`
  (in-game = all, pilot tab = `pilot` slot, mech tab = `mech` slot). A dimmed card has no
  band button and `_fan_keys[i]` is `""`. Pressing that spot is taken by `_card_zone` and
  nothing happens.
- **Hover / press = the hand's focus.** The pointed card (band `mouse_entered`), or failing
  that the card whose description box is open, is the focus (`_fan_focus`). The focus card
  grows by `HOVER_SCALE`, brightens and comes to the front via `Card.set_hovered(true)`; the
  rest step aside by the same formula as the hand's `hover_push_offset` (ends pinned,
  `BS_HAND_HOVER_FALLOFF_POW` falloff) (`_fan_push`). The tween matches the hand too. enter /
  exit arrive back to back in one frame, so `_queue_fan_relayout` gathers them deferred.
- **Input is taken by bands, not card rects.** The visible width of card i (its own left edge
  to the next card's left edge) is one button (same calculation as the hand's
  `_apply_hit_bands`). Bands are **fixed at the resting positions** — if the bands followed
  the cards stepping aside, the band under the cursor would change and the focus would jitter.
- **Pressing a card shows the same description box as pointing at it in the hand**
  (`_build_card_desc`) — `CardDescBox.build(cd, CardPhaseManager.DESC_BOX_W, …,
  with_notes = false)` + a side plate per keyword (`build_keyword_panels`, `KEYWORD_BOX_W`),
  placed by the same rule as the hand's `_desc_box_spots` (right beside the enlarged card ·
  top-aligned, on the left if the card is past the screen centre, keyword plates further
  out), with the same entrance motion (`DESC_ANIM_*`). The old info-plate rows for cost ·
  type · category · position · keywords · tokens (`_card_rows`) were **deleted**.
  **Formulas show as wording, not values** — it is built with `live = false`, so
  `{charge*8|사용 횟수×8}` prints as `(사용 횟수×8)` even mid-match
  (`CardDescBox.resolve_text`). The box has no values, so `refresh()` doesn't rebuild it (that
  would replay the entrance motion on every update).
- **The card list comes from the `BattleSim.starter_cards` table** — it is **not**
  reconstructed by scanning hand · deck · discard pile. An exhausted (`exhaust`) card is in
  none of the three piles, so a reconstruction would silently drop it from the list, but
  "what this pilot came in holding" is a fact that doesn't change during the match. The table
  is written once when `CardPhaseManager._deal_team_deck` goes through the deck — see
  `card_phase/README.md`.
#### Lasting effect thumbnails (in-game tab) — bottom-left of the illustration
**When the source card is known, the cell is that card's illustration** — the art is cut to a
rounded rect filling the cell (`shaders/rounded_rect_mask.gdshader`) and the value sits on a
black band at the bottom (`_make_fx_thumb`, art mode of `PilotDetailFxThumb`). The source is answered by the per-card
ledger's `src`, or for slot effects by `PilotData.fx_src` (`CardPhaseManager._note_fx_src`).
Only cells with an unknown source (remainders · laning applied by a skill, etc.) stay as the
two-character abbreviation cells described below.

**Not in the info column but at the bottom-left of the screen**, right above the card fan
(`%FxGrid`: from x 26, six cells per row, 12 apart). In a 68×68 cell, the top is a
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
- **Rows grow upward** (`%FxGrid` grows up; its bottom is pinned at `_fx_bottom_y()`). Letting
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
  "how many are on". With none at all, nothing is drawn.
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

#### Other rules
- **Shield attaches to the HP value, not a separate cell** — the cell shows only `159 / 322`,
  and `보호막 +30` (Shield +30) is inside the HP menu. A shield isn't a number read on its own
  but "how many more hits can it take now", and that answer only comes when placed beside HP.
- **The hit / evasion cells are values after the laning stat is applied.** What
  공격적인 라인전 pushes is not the `PilotData.hit` / `evasion` fields but **a multiplier at resolution
  time** (`lane_stat_mod`), so printing the raw fields would leave this value unmoved by even
  1 after playing the card. It goes through **the same function** as resolution
  (`SimulationCore.lane_adjusted`), tying the on-screen number and the number actually in play
  together, and the base value and multiplier are written in the menu (the line exists only
  when a multiplier is applied).
- **Outgame stats (pilot tab) don't change during a match** — they only rise through training.
  So the menu's `인게임 증가` (in-game increase) row is always `없음` (none).
- **`refresh()` doesn't rebuild the tree (as long as the lasting effect composition is
  unchanged)** (on every `update_hud`, right after `close_if_phase_left`). It fixes only the
  cell value labels · growth points · the text of the open panel — rebuilding wholesale would
  instantiate the card nodes **on every update** and make the pressed cell's highlight
  flicker each time. `_rebuild_body()` runs only when the tab changes (or the effect set /
  status-line visibility changes): it refills the chip rows and the effect grid and shows / hides
  the dead line and skill plate. Old rows only given `queue_free` would still draw this frame and
  the text overlaps, so **`remove_child` first** (`_clear_children`). Neither the art nor its front/back pose is touched.
- **`clip_text = true` is mandatory on value labels.** A right-aligned `Label` whose text is
  wider than its rect gives up alignment and draws from the rect's left, so it **overflows to
  the right and off the screen** (measured: "아웃게임 데이터 없음" (No outgame data) was cut off
  outside the screen).
- **Every plate, box and label is `MOUSE_FILTER_IGNORE`** — only cells · tabs · effect thumbs ·
  card bands · the Use button take input, so a press on a plate falls through to `%Dim` (and is then
  kept open by `_info_zone`). z-order is the view's child order: dim / arts / info column (effect
  grid · column · card fan · card bands) / `%InfoMenu` last = topmost.
- Outgame stats are looked up with `BattleSim.player_data_for(pilot)` — it maps the index in
  the `pilots` array (0..4 = team 0, 5..9 = team 1) directly onto `match_ctx`'s two rosters, so
  **reordering `pilots` misaligns names and stats**. Standalone runs or INTL pilots → null →
  cell values `—`. Enemy pilots opening is also thanks to this mapping.
- While open, **only the strip of the pressed team is hidden**
  (`HudBuilder.set_strip_visible(team, on)`). If only the strip remained above the dim, what you
  are looking at would blur; putting it below the dim darkens the face you just pressed and
  breaks the link. The other team's strip is left alone — it's just covered by the dim, and
  removing it would make what disappeared more confusing.
- **The view is full-rect by anchors** — a full-rect `Control` under a `CanvasLayer` resolves to the
  viewport (the old "size stays 0" comment was a code-build ordering problem, `docs/ui_scene_migration.md` §2),
  so dim · art holder · info column cover tall screens without `ScreenMetrics.viewport_size()`. The info
  column itself stays at the old absolute design coordinates (pattern C, `docs/mobile_safe_area.md` §7);
  only the card fan and the effect grid follow the safe bottom (`BS_HAND_CENTER`).
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
the elapsed clock stand outside it with no background. The three clocks are direct children
of `_bs.canvas` (CanvasLayer); the enemy strip · its backplate · the opponent hand peek live
on a dedicated layer, `_enemy_top_layer` (next section).

#### Top enemy UI layer (`_enemy_top_layer`) — moves up out of the way while a card is dragged
The enemy strip (`_enemy_strip`) · backplate (`_enemy_strip_bg`) · opponent hand peek
(`_ai_hand_root`) live on a **dedicated CanvasLayer** named `EnemyTopLayer`. Normally it has
the same layer number, 1, as `_bs.canvas` and stands **right before the canvas** in
BattleSim's child list — among CanvasLayers with the same layer number, sibling order is draw
order, so everything on the canvas (turn banner · flying opponent cards · kill log) draws
above it. That's the same order as when these three were at the front of the canvas's child
list.

When a dragged card reaches the screen-centre drop range (`CardPhaseManager._drag_lowers_hand`
— the same condition that lowers the ally strip), `set_enemy_top_raised(true)` tweens the
layer's `offset.y` to `-ENEMY_TOP_RAISE` (= `STRIP_DRAG_DROP` 120) and dims the three with
`STRIP_DRAG_DIM` — the mirror of the ally `set_player_strip_dropped`. **While raised the layer
number is `ENEMY_TOP_RAISED_LAYER` (-1)**, so it lies **under** the battlefield tiles · pilot
portraits (root canvas, layer 0) — while aiming, the battlefield has screen priority. On the
way back the layer is restored to 1 only after the tween ends (restoring it mid-way would pop
the still-displaced plate above the battlefield portraits). The three clocks · the enemy donut
don't move — they don't overlap the battlefield.

> `pop_ai_hand_card_node` moves the face-down card to the canvas keeping its
> `global_position`. The layer `offset` isn't part of that value, so calling it while the layer
> is raised would be off by 120px — but opponent cards are only played on the opponent's turn,
> when there's no drag.

`TOP_PANEL_Y` 0 / `TOP_PANEL_H` **248** (raised from 148 when the circular portraits doubled
the enemy strip height) remain and serve as **the reference coordinate for the chain
below**. The enemy strip is now full width (1030, same as the ally one) but its five discs
only occupy the middle, and **the side margins are the two objective clock cells**
(`OBJ_TIMER_LEFT_X` 26, the right one worked back from the viewport width, each 101×60,
vertically centred on the disc centre `OBJ_TIMER_Y` 110).

The enemy strip grew twice: 618 → 672 (portrait +10%) → **806** (another +20%, portrait
145×60). Only at that size do faces tell who is who, and growth points can be compared side
by side with mine. The clock cells shrank by that much, 190 → 168 → **101**, and on the clock
side the icon·number gap and the "턴" text were removed to fit that width — when fighting for
space, the clock always gives way.

And below it is the chain (values in this paragraph are from the 148 era; each is now
+100): the panel was the screen that hid the top of the opponent's hand peek
(`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = 98, now **198**; only 49px of the cards' bottom pokes
out — the strip is transparent now, so the peek's top shows behind the portraits), the spot
offset by `DONUT_AI_HAND_GAP` from the bottom of the peek cards is the enemy donut (bottom
y 327, now **427**), and below that is the top of the battlefield pixels.
**If you change the panel height, move `AI_HAND_TOP_Y` and `KillFeed.FEED_TOP`
(= `TOP_PANEL_H + 8`) by the same amount together** — leave the former and the peek either
hides entirely behind the panel (when growing) or exposes the cards' tops (when shrinking);
leave the latter and the kill log floats detached from the panel. The donut is computed from
`AI_HAND_TOP_Y`, so there's nothing to touch separately.
It shrank 168 → 132, then became 148 when the strip grew (the chain moving down by the same
16px: peek 98 / donut 327 / kill log 156), then **248** with the circular portraits. The band
between the enemy donut and the battlefield used to hold the card description box; the
description box now stands beside the pointed hand card.

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
of the screen (8px below the top panel's bottom edge, y **256** = `TOP_PANEL_H` + 8). The
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
- With 4 lines the bottom stopped at y 334, above the top of the battlefield pixels (369),
  when `TOP_PANEL_H` was 148; with the circular-portrait chain (+100) it is ≈ **434**.
  Raising `MAX_ROWS` / `ROW_STEP` covers more of the battlefield.

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
  by team and role, pushes each five into its `PilotStrip`, gates **both** strips'
  hit buttons on `PilotDetailPanel.can_open()`, closes the skill popup if needed, then lets
  `PilotDetailPanel.close_if_phase_left()` close the modal if the phase moved on
  and `PilotDetailPanel.refresh()` re-write the cell values of one that survived
  (labels only — the node tree is rebuilt on tab switch, never on refresh).
- Calls `update_time_label()` (also called every frame from `_process`).

### update_time_label() (per-frame)
Pulls `_bs.get_elapsed_ingame_seconds()` and formats as `%02d:%02d`. Called
from `BattleSim._process` every frame so the clock visibly ticks even when no
HUD-state event fires.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.


---

## Pilot skill display (`SkillBadge` + `SkillPopup` + `PilotDetailPanel` block)

A unique ability attached to each player. The rules and the list of 25 are in
`../skill/README.md`; what's written here is only **how it appears on screen**.

### Strip — skill badge (`SkillBadge.gd`)
Ally strip only (the enemy cells build no badge). Diameter = disc ×
`PilotStrip.SKILL_BADGE_RATIO` (0.40); centre = disc centre + `SKILL_BADGE_OFFSET`
(0.80, 0.62) × radius — lower right, clear of the score tab hanging below.
It lives in the cell `holder`, so it scales with the press zoom.

Everything is `_draw` except the centre number (a child `Label`):

| Layer | Rule |
|---|---|
| Background | dark disc `BG_COLOR` — **never dimmed** |
| Icon | `SkillImages.icon_for(key)`, `ICON_LIT`; when unusable drawn `ICON_DIM` (icon only) |
| Cooldown | lit sector grows **clockwise from 12 o'clock** by `PilotSkillSystem.progress(p)`, rest dimmed; centre = turns left, hidden when ready |
| Stacks (charge, token passives) | ring split into `max_charge_of(p)` segments, filled = `charge_of(p)`. If max > `STACK_SEGMENT_MAX` (10: 축적 100 · 퍼포먼스 25 · 신예 15) → one continuous arc + stack count in the centre |
| No stacks | thin `TEAM_RIM` outline |

The sector is not a shader: the fan polygon is intersected with the icon square
(`Geometry2D.intersect_polygons`) and drawn with texture UVs, lit and dim halves
separately so the seam never double-blends.

**Dim rule = resources, not turn** (`PilotStrip._apply_skill_state`): cooldown →
`progress`; charge → lit iff `is_ready`; passive → always lit. A downed pilot is
fully dimmed. The opponent's turn does not dim a ready skill — the 사용 (Use) button's
`can_activate` handles that gate.

Refresh path: `HudBuilder.update_hud` → `_update_pilot_strips` →
`PilotStrip.refresh()`, plus `PilotSkillSystem.skill_state_changed` → `update_hud`
(connected in `BattleSim._ready`, covering state changes outside battlefield ticks —
objective spawn · kill involvement · turret destruction).

### Strip — skill popup (`SkillPopup.gd`)
Short tap on an ally portrait. Own `CanvasLayer` 12 (below the detail panel's 13).
**No dim, no border**; short downward shadow (`SHADOW_SIZE` 6, `SHADOW_OFFSET`
(0, 6)). A 640px panel sits above the portrait, its bottom edge `ARROW_H` +
`ARROW_GAP` above the head top (`PilotStrip.anchor_for`), x clamped to the screen
with `SCREEN_MARGIN`; a panel-coloured triangle below it points at the portrait
(added after the panel so the panel shadow does not cover it).
**Open**: panel + arrow (`_body`) rise `RISE_PX` and fade in over `OPEN_SEC` 0.2s.
**Close**: state clears at once, `_body` sinks and fades out over `CLOSE_SEC` 0.1s,
then that `SkillPopupCard` instance is freed (inputs ignored meanwhile; a new card for another pilot can rise at the same time). Content:
icon tile · name · type at the right — **cooldown = clock icon
(`KeywordIcon.COOLDOWN`) + reuse turns (`p1`)**, else 충전식 (charge-type) / 패시브 (passive) text · rich description (same
`StrategyIcon` path and `PilotDetailPanel.SKILL_*` styling as the detail panel) ·
status line (hidden for a ready cooldown) · full-width **사용** (`SKILL_USE_H`,
none for passives, enabled by `can_activate`). Using the skill closes the popup
first, then calls `activate`.

Closing: outside tap · same portrait again · 사용 · detail panel opens
(`HudBuilder._on_pilot_strip_pressed`, `set_strip_visible(0, false)`) · card drag
lowers the strip (`set_player_strip_dropped(true)`) · `close_if_phase_left`
(gate = `PilotDetailPanel.can_open`, from `_update_pilot_strips`, which also
calls `refresh()` for the status / button).

**Card-name press preview.** The description is built with `card_meta = true`, so
each `[card]` name (cost ribbon + name) is a meta span. While a finger holds one,
that card (`Card.tscn` × `PREVIEW_SCALE` 1.25) appears with its bottom
`PREVIEW_LIFT` above the press point and a `CardDescBox` (`PREVIEW_DESC_W` 300) to
its right (left if no room); the pair rises `PREVIEW_RISE_PX` + fades in 0.2s,
and on release sinks + fades out 0.1s. RichTextLabel only reports metas via hover
(`meta_hover_started`) or on release (`meta_clicked`), and a touch has no motion
before the press — so on press `_nudge_hover` pushes one `InputEventMouseMotion`
at that point (deferred) to make the label resolve the meta under the finger.
The card is looked up by name (`CardDescBox.card_by_name`).

Outside-tap handling: a transparent `MOUSE_FILTER_STOP` catcher covers the screen
**only down to the ally strip's top**, so that tap is swallowed (the hand / field
does not react). Strip cells stay reachable for re-tap / switch / long press.
Presses inside the strip band that hit no cell are caught in `_input` and close
the popup without being consumed. Does not hold the battle tick.

### Detail panel — pilot skill plate (in-game tab)
> **Older layout below** — the current plate (no title row, no type badge / keyword line,
> icon tile + name + rich description + status line + 사용) is described in the
> "Pilot detail panel" section above. The rationale still holds.

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
| Pilot display (strips ×2) | **Now circular portraits** (team-colour disc + a bust poking out above it + a growth-point tab below the disc, no HP bar — see "Circular portrait" above). What follows is eye-band-era history. Five pilots each form one cell in three rows, **eye-level portrait → HP bar → growth point number** (growth points correspond to the gold display of a MOBA broadcast, rising from `SCORE_START` (const.csv) at the opening through the match), and the five cells stand side by side horizontally (`ui/PilotStrip.gd`). **The enemy team is at the very top of the screen** (`ENEMY_STRIP_RECT` 137,46,806×100 — **78% of the ally strip**, horizontally centred, **with one backplate `Panel` behind it**), **allies are below the hand row** (`PLAYER_STRIP_RECT` 25,1766,1030×122, **with one backplate `Panel` behind it** — see the row below) — previously all ten were crammed into 84px square slots on both sides of the top panel, so you could tell neither who was who nor which side was your team. The portrait is `PilotImages.eye_for` = **`eye/N_eye.png` (480×200, a band cut horizontally so both eyes show)** and the cell height is derived from that ratio (`EYE_ASPECT` 2.4) — stretching to an arbitrary height distorts the face. The HP bar is **two `ColorRect`s**: `ProgressBar` computes a minimum size from the theme content margins and pulls `size` up to around 24px, so even when a 6–10px bar was requested it overwrote the growth point label below (confirmed by measurement). With a shield the fill turns yellow (the reason for not appending a segment is that it's too thin for two sections to be distinguishable). A downed pilot's portrait darkens and **the number of turns until revival** is printed large in the middle. The bottom strip's y (1766) is **a value computed from the cards' bottom edge** — the cards at both ends of the fan sag 21.4px below the middle and grow 1.2× on hover, coming down to a worst case of y≈1763 (back when the hand row was at 1500). Now that the hand has moved up to 1440 the worst case is y≈1703, so the slack grew to 63px, but the strip is attached to the screen bottom (1888) with no room to go lower, so it stays. **Cell order is set by `GameEnums.ROLE_DISPLAY_ORDER` — tank → assassin → fighter → sniper → supporter**, i.e. the order you sweep the battlefield from the left (left → jungle → centre → right ×2), and **the same table as the outgame screens** (season hub roster · training grid · ban/pick (밴픽) screen · draft slots). Using the `Role` enum order as-is (TANK · FIGHTER · ASSASSIN · SUPPORT · SNIPER) seats the jungler third and the ADC fifth, an arrangement that corresponds neither to the map nor to the lineup the player knows. Previously a separate `HudBuilder.LANE_SEAT_ORDER` table here sorted **by `PilotData.lane`** (**deleted**), but two pilots sit in the right lane (sniper · supporter) and lane couldn't order those two — `sort_custom` is not a stable sort, so the order of the two with the same lane could wobble between runs. Sorting by role uniquely determines all five seats. Sorting is done on a **copy** of `_bs.pilots` — the original must keep spawn order (= role order) so `BattleSim.player_data_for` can find the roster by that index. **The enemy strip's size changed four times.** At first it was a 730×84 shrunken version (portrait 130×54), but showing the same faces at two very different sizes top and bottom meant neither who the opponent was nor the opponent's growth points read as well as the ally side (that number exists to be compared side by side with mine), so it was enlarged to **exactly** the ally's 1030×122 — at that time `HudBuilder.TOP_PANEL_H` grew 130 → **168** and the whole chain below moved down 38px (`AI_HAND_TOP_Y` 80 → **118** = `TOP_PANEL_H − 50` → enemy donut bottom 311 → **349**, battlefield pixel top 369, so 20px of slack). After that it was shrunk to **60% (618×76)** and centred — because when the objective spawn clocks moved from the battlefield tiles to this panel, **cells for icon + turn count on either side of the strip** were needed. But at that size the 108×45 portrait fell below the minimum for telling who is who. Portrait width is derived from cell width (`_cell_w − 16` in `PilotStrip.setup`), so the only way to enlarge it is to push the strip width, and it was **pushed twice** — 618 → **672** (portrait +10%), then 672 → **806** (+20%, portrait 145×60). Height follows the eye ratio (2.4:1) up 76 → 81 → **97**, and to keep horizontal centring x is pushed left 231 → 204 → **137**. The side margins shrank, so the clock cells went 190×122 → 168×49 → **101×60** (`OBJ_TIMER_LEFT_X` 26 / `OBJ_TIMER_RIGHT_X` 953) — on the clock side the icon·number gap was cut to 4 and the "턴" text was removed to fit that width (`ui/ObjectiveTimer.gd`). This is a panel where faces must read first, so when fighting for space the clock always gives way. **The panel height is now set by content** — `TOP_PANEL_H` went 168 → 132 → **148** (header 4..38 + strip band 46..143 + 5px), and the chain below (`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = **98**, enemy donut bottom **327**, `KillFeed.FEED_TOP` = `TOP_PANEL_H + 8` = **156**) moves along with it, leaving **42px** of slack to the battlefield top (369). The old 168 was a leftover from when the strip was the same size as the ally one, creating a 27px empty cell below the band. **The growth point font is now the same on both strips** (`ENEMY_SCORE_FONT` = `PLAYER_SCORE_FONT` = 20, formerly 14) — the ally portraits are bigger, but that number exists to be compared side by side with mine, so different sizes would give the two numbers read on the same line different weight. Faces may be small; numbers may not. **The role tag (single letter `T` / `F` at the portrait's bottom-left) was deleted** — the strip's seat order itself already is the role, so it said the same thing twice and just covered the bottom of the face (the three `ROLE_TAG_*` constants and the two nodes `tag_bg` / `role_lbl` disappeared together). **And the full-width top panel disappeared** — see the row below. |
| Top chrome (enemy strip backplate + elapsed clock + objective clocks) | **Previously one panel covering the full screen width** (`TOP_PANEL_H` 148) held the header row, the enemy strip and the objective clocks. That made the clocks at both ends read as sitting on the same plate as the strip, but the clocks aren't part of the strip; they're a separate object counting battlefield events. Now, **by the same rule as the ally strip**, the backplate (`_enemy_strip_bg`) wraps only the five portrait cells, extended by `ENEMY_BG_PAD` (10), and **the elapsed clock and the two objective clocks stand outside it with no background** (all three direct children of `_bs.canvas`). `TOP_PANEL_H` remains as a constant and serves as **the reference coordinate for the chain below** — the backplate starts at `ENEMY_STRIP_RECT.y − 10` (36) and ends at `TOP_PANEL_H` (148), so neither the amount hiding the opponent hand peek (`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = 98) nor the enemy donut (327) nor the kill log (`FEED_TOP` = 156) moved by a single pixel. The peek fan stands at the horizontal centre of the screen, so it fits entirely within the strip width (x 127..953) and still acts as a screen. **The team total score (`12.4k - 9.8k`) was deleted** — the strip's five cells already showed the same numbers individually, and the total, while telling in one line which side is winning, hid **who** is actually growing (`TOTAL_SCORE_FONT` / `_lbl_total_score` deleted together; `BattleSim.team_score()` remains without a consumer). The elapsed clock has no backing, so a black outline keeps it readable, and since `UiHelpers.mk_label` takes a `Control` parent whereas the canvas is a `CanvasLayer`, the `Label` is created directly. |
| Ally strip backplate | (**History — the backplate is now transparent and the strip sits at y 1644**, see "Ally strip backplate" above.) **One dark `Panel`** behind the bottom ally strip (`PlayerStripBackdrop`, the strip area extended by `HudBuilder.PLAYER_BG_PAD` 10px each side, y 1756..1898). Colour·border match the top panel, so the top and bottom strips read as sitting on the same plate. The enemy strip sits on the top panel so it had backing from the start, but the ally strip floated directly on the screen, so the three rows face · HP bar · growth points looked scattered with no background — growth point numbers in particular don't show where one pilot's cell ends without backing. **`_build_player_strip` adds it before the strip** (sibling z-order is child index, so if added later the plate covers the portraits) and **`set_strip_visible(0, on)` hides it together with the strip** (if the detail panel cleared only the strip, an empty plate would remain on top of the dim). |
| Objective spawn clocks (either side of the strip) | One pair of **one icon + turns remaining** in each of the enemy strip's side margins (`ui/ObjectiveTimer.gd`, each 101×60). **Left is Herald (purple flag) · right is Dragon (vermilion wings)**, and that left/right matches the left/right of the cells where the two objectives stand on the battlefield — position is the name, so there are no name labels. When the enemy strip grew 20% this cell shrank 168 → 101px, and accordingly the icon·number gap became 10 → **4** and **the "턴" text next to the number was deleted** (`UNIT_FONT_SIZE` / `UNIT_COLOR` disappeared with it) — a number stuck next to the icon can't be anything other than turns remaining, so that text only pushed the number away. `ICON_SIZE` stays 49 and is vertically centred (number font 32). **Pressing shows that objective's reward cards as real cards** — `mouse_filter` went IGNORE → STOP, and when it fires `timer_pressed(kind)`, `HudBuilder` calls `BattleSim.objective_reward.toggle(kind)` (pressing the same clock again closes it). At one point the icon was 62 and the cell height was the whole strip band (122) — on the grounds that bigger reads better in peripheral vision — so the clocks stuck out above and below the portraits, became the biggest object in the top panel, and grabbed the gaze that should go to the faces first. Aligning bottom·top edges to the portraits makes left clock · five faces · right clock read as one row. State comes only from `ObjectiveSystem.turns_until_cell(cell)` and updating is only `HudBuilder.update_hud`'s `queue_redraw()`. **Icons are shapes, not images** (same approach as the kill log glyphs): all coordinates are written on a 64×64 basis and only multiplied by `ICON_SIZE / 64`, so changing size doesn't require redoing the numbers. Dragon's wings are **smooth four-vertex triangles**; the original serrated bat wings (eight vertices) mushed together at this size and looked like **a single leaf** — at this size what makes the silhouette is not detail but the angle of two big triangles. |
| Kill log (kills / turret demolition / objective capture) | Stacks one line at a time at the **top-right** of the screen (8px below the top panel's bottom, y **156** = `TOP_PANEL_H` + 8) (`ui/KillFeed.gd`). The battlefield flows on its own every 0.5 s and engages cover the screen with an overlay, so **once something happened, there was nowhere it remained** — apart from the team score widening a bit. A line is, from the left, `[막타 96px][어시 32px ×0..4][아이콘 32px][피해자 96px]` (last hit / assist / icon / victim), all eye cuts (`PilotImages.eye_for`), and **the whole line is right-aligned**, so however many assists, the victim cell lands at the same x. Icons: kill = crossed swords, turret demolition = burst, and the victim spot gets the turret silhouette + `T1 좌`. **There are three feed sources** — `BattleSim.mark_pilot_dead` (→ `_push_kill_feed`), `score_turret_kill(killer, td)`, and **objective capture** (`ObjectiveSystem._push_feed` → `KillFeed.push_objective`). An objective line's **representative is the jungler** (for both Herald and Dragon both teams' junglers are always participants, and running objectives is the jungle's job itself — `_feed_order`). If the jungler couldn't come, the first of the remaining participants stands there and the rest attach as assists; the list is **the participants at the time participation was chosen**, so someone downed in the subsequent engage stays. **An uncontested capture also gets a line** — a free take where nobody showed up is precisely the case where nothing happens on screen. The rightmost cell gets the Herald / Dragon glyph and name, and that picture is drawn by **the same static function** as the top panel spawn clock (`ObjectiveTimer.draw_kind_glyph`). The two feed sources for kill lines are unchanged — the former must run **before** `_payout_kill_bounty` (that payout empties `PilotData.damage_credit`, the source of the assist list). So the faces shown on screen and the faces that received growth points can't diverge. If the last hitter arrives as null (`_last_hitter` is cleared every turn), the person who dealt the most damage takes that seat. **Kills during an engage don't show on the spot** — the arena covers the screen so they wouldn't be seen anyway, so it checks `is_active()` and stacks them in `_pending`, and `EngagePhaseManager._on_dashboard_confirmed`, which closes the result dashboard, calls `flush_pending()` to release them in a burst at `FLUSH_STAGGER` (0.25 s) intervals. Lines **push in from the top** (the new line at y 0, the rest one slot down), are erased over `FADE_SEC` (0.5 s) after `HOLD_SEC` (4 s), and the oldest line beyond `MAX_ROWS` (4) is pushed down and fades — a pushed-out line is **moved to `_fading`**, not left in `_rows` (it must drop out of slot calculation while its fade keeps running; just removing it from `_rows` froze that line on screen forever — measured). With 4 lines the bottom stops at y **334**, above the top of the battlefield pixels (369) (when the top panel was 168 it was a close call at 354). **The icon is a child `Glyph` node, not the line's `_draw`** — a Control's `_draw` is emitted before its children, so it would lie beneath the line background (translucent) and the turret cell slab (opaque) (the swords were faded and the turret silhouette didn't show at all). |
| Pilot detail panel | (**Old record — the "Pilot detail panel" section above is authoritative**: growth points top-centre of the header, stats as full / half-width cell rows, held cards = 6 at the hand's spot · width, card descriptions use the hand description box, no close button.) A modal that opens when you press a face on a strip **during your own operation phase** (`ui/PilotDetailPanel.gd`, its own `CanvasLayer` 13 — above discard 10 / targeting 11 / browse·engage 12). **Both the ally bottom strip and the enemy top strip are pressable** — enemies open through the same gate with the same content (down to the 6 dealt cards), and the opponent roster has already come in as `match_ctx.enemy_roster`, so `BattleSim.player_data_for` finds it directly at indices 5..9. The screen is dimmed black α 0.88 and **only the strip of the pressed team is hidden** (left above the dim it blurs what you're looking at; put below the dim the face you just pressed darkens. The other team is just covered by the dim, so it's left alone). **On the left, two full-body arts** stand overlapping (pilot / mech), and the right is **header + three tabs + detail panel**. **The header is separate from the tabs** (`HDR_TOP` **424** .. `HDR_BOTTOM` 562, on its own backing) — **pilot name / the mech name small on the line below / growth points on the right**; it belongs to the same pilot whichever tab you view, so it isn't rebuilt when tabs change (`_build_header_block` runs only once in `_build`). Previously this line was inside the body, so **on the mech tab the title changed to the mech name and the pilot name and growth points vanished from the screen entirely** — in effect, who was open wobbled with the tab. The mech name being always visible is for the same reason (it isn't a value you should have to go into the mech tab to learn). **The mech name moved from the right of the name down to the line below** — it used to be appended with an `HBoxContainer`, but since the line's start point was the name's width, the mech name started at a different x per pilot (where to look for the mech name wobbled per pilot). Stacking two lines makes the start point always the same and removes the need to measure text width, so the container itself disappeared. `HDR_TOP` moving up by the two extra lines is because `HDR_BOTTOM` is the top edge of the tab bar and is pinned. The only thing a tab changes is the detail panel below — **In-game** (HP · attack · growth · battlefield/engage hit · evasion · presence, a `부활까지 N턴` line when dead, then immediately below it the **pilot skill block**) / **Pilot** (six player stats = `PlayerData`) / **Mech** (HP · attack · presence). The tab also decides which art is front and back (on the mech tab the machine is in front) — the old **"전환" (Switch) button was deleted**. **Lasting effects and held cards both live outside the info column** — effects at **the bottom-left of the illustration** (from x 26, right above the card row), cards in **a fan across the full width of the screen bottom**. **Lasting effect thumbnails** (68×68, in-game tab only) show **only what's currently applied to this pilot**, and past six cells the row folds **upward** (folding downward would land the second row on the cards); **the title ("지속 효과") was deleted** — putting an underlined section title on top of cells standing alone in a screen corner makes the title stand out more than the cells, and with no effects applied nothing is drawn at all (the old one-liner "걸려 있는 효과 없음" was a sentence that only made sense with a title). The reason for moving it was competition for space — inside the column it ate 116px and pushed the whole chain below (card row · skill block · close button), while the bottom-left of the screen held only the art's legs and the dim, so it was empty. Three kinds are mixed — **(1) the four slot effects** (`fx:lane` laning stat / `fx:rate` accrual multiplier / `fx:atk` temporary attack / `fx:shield` shield) have cards overwriting each other in one slot, so the kind name is the cell name; **(2) per-card lasting effects** (`fx:src:<kind>|<card name>`) are one cell per line of the `PilotData.persistent_fx` ledger (the abbreviation is the first two characters of the card name — `용 보상` → `용보`); **(3) the remainder** (`fx:rest:<kind>`) is the total minus the ledger (the share mech passives push directly into `bonus_*`, so the source can't be named by a card name). Previously (2) was also lumped by attribute, so **one `fx:perm` cell meant both [용 보상] and [핫핸드]**, and [붉은 가루] · [녹색 병], which live in `bonus_max_hp` / `bonus_atk_flat`, **weren't shown at all** — they are values living in separate fields so the growth recalculation doesn't wipe them, so they weren't carried on any chip. **Computation is still done by the total slots; only the display reads the ledger** (the ledger is written in one place, `CardPhaseManager._log_persistent_fx`, and the source is the card running at that moment) — the growth recalculation must read from one place only. Laying out inactive cells in grey would force you to count "how many are on", and with none at all it's the single line `걸려 있는 효과 없음`. There are no icon assets, so **the two-character abbreviation is the icon** and the full name is carried by the title of the panel opened by pressing it. There were two reasons chips alone weren't enough — when the hit chip says 55, whether that's due to a card or just how it is only showed when you pressed the chip, and effects **not carried on any chip, like the accrual multiplier**, had no place to be seen at all. The team-level 계획 살인 reservation isn't here (the same thumbnail would show on all five and blur whose it is). **Stat chips · lasting effects · cards all share one info panel** (one `_targets` table; the key prefix distinguishes the kind — none = chip, `fx:` = effect, `card:` = card). The plate opens to the left of the info column **at the same height as the pressed item**, with **only `card:` as an exception, lifted to sit above the card row title** — cards are at the bottom of the screen, so the same rule would point on top of the card just pressed, and the plate would cover that card entirely. "What am I looking at now" must be one thing at a time, so separate plates would show two at once and blur what you just pressed. **Pressing a card shows that card's cost · type · caster restriction and description in that panel** — the text written on the card node is shrunk to ×0.80, so it's not meant to be read. **The backdrop forwards clicks** (`_on_menu_backdrop_input`) — it's still a full-screen STOP, but it finds the target button / tab / close at that coordinate and presses it on your behalf, so **pressing another stat with the panel open switches straight to it**. Previously the first click was spent on closing so you had to press once more, and while skimming six stats the clicks doubled and the screen flickered between open↔closed. Pressing an empty spot closes it then. **Stats are chips, not rows**: one rounded rectangle cell (141×92, 3 columns) with a small name on top and only **one final value**, large, below; the base value · increase · expiry turn are in **the context menu that opens to the left when the chip is pressed** (`_menu_rows`, e.g. HP = base N / growth +N% (+N) / max N / current N / shield +N). Previously `key ─ value` rows ran a dozen or so lines with `(기본 N)` `(N턴)` brackets trailing the values, so reading "what it is now" took time — `_row` / `_section` / `ROW_H` / `KEY_FRACTION` were deleted at the same time. **The big number right of the title is growth points** (the old `역할 · 아군/적군 · 성장치` subtitle and `라인 / 위치` row were deleted — role and side were already told by the portrait just pressed), and **it isn't attached on the mech tab** (that title is the mech name, which isn't the owner of the number on the right). **Shield is not in the HP value but inside the HP menu**, and **the hit / evasion chips are values after the laning stat is applied** (`SimulationCore.lane_adjusted` — passed through the same function as resolution. What cards push isn't the `hit` / `evasion` fields but the resolution-time multiplier `lane_stat_mod`, so printing the raw fields would leave the value unmoved by even 1 after playing 공격적인 라인전). **The big number on the growth chip is attack growth**, and max HP growth · accrual multiplier are in the menu — the two grow differently (`GROWTH_ATK_PER_SCORE` vs `GROWTH_HP_PER_SCORE`, const.csv), and it's different from the `적립 배율` that cards push. **Held cards stand in the same fan as the hand across the full width of the screen bottom** — `Card.tscn` **×1.60 = 256×352** (**2×** the grid-era 0.80 = 128×176); the in-game tab has 6 (pilot 3 → mech 3 order, so the left half is the person and the right half the machine), and the pilot / mech tabs put that tab's cards in the same spot. **It used to be a 3-column grid inside the info column**: the cells were confined to the column (width 452) so they couldn't get bigger, and there's no way to keep the grid and double the size (3 columns would be 800px, overshooting the column by 348px · the right side of the screen by 146px, and 2 rows would put the panel bottom at ≈1700 → 2052, off screen). The fan **overlaps** the cards, so it fits the same count in the same width while doubling the size per card. The geometry follows the same rule as the hand (card **centres** ride a circle below the row), and the side margin `FAN_MARGIN` (52) and bottom slack `FAN_DROP_RESERVE` (44) accommodate not half the width but **the outer corner of the tilted card** — the ends tilt close to 9°, so the tall card goes 27px further out than half its width (at margin 24 both ends were clipped by 3px — measured). **Input is taken not by the card rect but by the band where the card is visible** (its own left edge ~ the next card's left edge) — covering rects as-is on overlapping cards would let the right neighbour's button hide this card's visible face entirely — and a card whose info panel is open rises by `FAN_LIFT_PX` (30) and is pulled to the front (the grid-era border highlight was deleted because it would wrap the band rather than the card). The list comes from the `BattleSim.starter_cards` table — reconstructing by scanning hand·deck·discard pile would silently drop exhausted (`exhaust`) cards. While open, `refresh()` rewrites **only the chip value labels and the open menu's text** on every `update_hud` (rebuilding the tree would instantiate card nodes on every update). **Close** follows the backing's bottom edge — content height differs per tab (in-game ~360 / pilot ~600), so at a fixed y the button alone floats in the middle of the screen on short tabs. **`clip_text = true` is mandatory** on value labels — a right-aligned `Label` whose text is wider than its rect gives up alignment and draws from the rect's left, so it **overflows to the right and off the screen** (confirmed by measurement). Leaving the operation phase force-closes it via `close_if_phase_left()` — if BATTLE flowed with it open, the battlefield would roll on behind the dim. |
| Detail panel's two arts (pilot ↔ mech) | The two arts share the front and back slots. **Front** = bright, horizontal centre `ART_FRONT_CENTER_X` (320). **Back** = pushed right by `ART_BACK_SHIFT_PX` (400px), shrunk by `ART_BACK_SCALE` (0.90), and dimmed with `ART_BACK_TINT` (translucent black) — a pose of "standing behind, slightly to the right, half overlapping". **The tab decides front and back** (`_apply_focus` — on the mech tab the machine is in front, otherwise the person; a `ART_SWAP_SEC` 0.22 s tween changes position · dim · z-order all at once). The old **"전환" button (two-state toggle) was deleted** — once the info split into three, a two-state toggle could no longer say what was where. **The bottom of the screen crops the art** — the bottom edge (`ART_BOTTOM` 2010) is outside the screen (1920), so the lower legs are cut off, and the old knee crop (`_knee_crop` / `KNEE_FRACTION`, which cut the texture via `AtlasTexture.region` at 80% of the alpha silhouette height) was **deleted**. **Size is normalised by height (`ART_H` 1400)** — every full-body art has the figure filling a height of 1024 with only widths of 572–756, so fitting by width would make figure heights vary. When stepping back, the node size stays and **only `scale`** shrinks: `pivot_offset` is the **bottom centre**, so the baseline stays put as it shrinks and the two read as standing on the same floor. **All 30 mech art slots are filled** — `MechImages.full_for(mech.id)` looks up `res://resources/images/mech/{id}_full.png` (if missing, `ResourceLoader.exists` quietly gives null → a faint α 0.30 silhouette slab + mech-name placeholder). Pilot arts are 1024 tall with widths varying 572–756, but **mech arts are a fixed 1024×1024 canvas** — mech renders have swords·wings extending sideways so the bounding box ratio reaches 1.5, and height normalisation converting that width as-is would spread to twice the screen width. So size was also matched by **opaque pixel area** rather than bounding box, to even out the apparent size of the body. Source (24 Gundam Evolution mech renders) and the id ↔ mech table are in `resources/README.md`. **The info block moved down** (`STAT_TOP` 170 → 640 → **650**, header at 452, tabs at 562) — because as the art grew the upper half of the screen became the place for the figure's head·upper body; behind the text a backing `Panel` (α 0.86) is laid to fit the content height. **The close button follows the backing's bottom edge** (`_reposition_close`) — its position changes only at the moment a tab is pressed, and `refresh()` doesn't touch the backing, so the button doesn't jitter with the numbers. The old fixed y (1424) left just the button floating in the middle of the screen on the in-game tab. |
| Deck / discard piles | The Deck / Discard in the gutters either side of the hand row are drawn as **stacks of cards lying down, tilted away** (`ui/CardPileStack.gd`) — card backs face up, piled on each other, with the edges of the cards below poking out beneath the stack. Previously it was a single two-line Label, `"Deck\n18"`: the number was readable but the pile **didn't look like an object**, so nothing on screen showed where cards came from or went. Two things make it look lying down — the height is squashed by `FORESHORTEN` (0.55), and the **top edge is drawn narrower than the bottom edge** (`TOP_EDGE_SCALE` 0.78) to add perspective. **Thickness is the count** (one layer per 4 cards, capped at 8 layers). **The baseline is fixed and it only grows upward** — fixing the vertical centre makes the stack jitter up and down every time a card comes or goes. The count is printed in the middle of the top card's back (no title label below the stack any more). The count comes in as a `float`, so during the reshuffle tween the thickness rides the same curve. At 0 cards, an empty slot with only its border. **The back is painted uniformly in one colour, the same as `Card._apply_back_style`** — it used to overdraw a per-pile accent trapezoid inside the face (deck purple / discard reddish-brown), but the stack is small, so that frame read as **a gradient sitting on the face** rather than a pattern, and their spots either side of the hand already tell the two piles apart. |
| Cards coming and going on the piles (ghosts) | If only the number changes, nothing on screen shows a card **came out of / went into** the pile. So the stack draws one more **ghost** shaped like the top card (a single trapezoid inside `_draw()` — not a node, so no effect on layout · input · z-order). **The deck's ghost rises by `GHOST_RISE_PX` (74px) and vanishes** (`play_pop`, on draw), and **the discard pile's ghost settles down from that height and appears** (`play_land`, on discard). One card takes `GHOST_SEC` (0.26 s), and several must be able to run at once, so they're driven by a `_ghosts` array + `_process` rather than tweens. **The two seams follow opposite rules**: the draw's entry from the left (`_play_draw_intro` ①) starts not after the ghost has fully vanished but when `GHOST_HANDOFF_ALPHA` (0.30) of its alpha remains (0.182 s), so they **overlap** (starting after it fully vanishes looks choppy, as if one card came out twice). Conversely the discard's landing ghost departs **after** the hand card has finished falling (0.30 s), so they **join end to end** — a draw is a picture of one card running on from deck to hand, while a discard is a picture of a card that left the hand arriving at the pile. The landing side is called by **noticing the count increase in one place** (`CardPhaseManager._notice_discard_gain` ← `update_deck_discard_labels`): there are seven places in code where the discard pile receives cards, but only one place where the number changes, and shrinking cases like a reshuffle have a negative delta so they're filtered out automatically. **Exhaust (`exhaust`) doesn't go to the discard pile, so there's no ghost either.** |
| Screen fit (safe area) | **The HUD constants stay as the 1080×1920 design values and the top/bottom blocks are shifted by two scalars** — `HudBuilder.top_offset()` (= `ScreenMetrics.top_y()`) and `HudBuilder.bottom_offset()` (= `ScreenMetrics.bottom_y() − 1920`). Top panel ↔ opponent hand peek ↔ enemy donut ↔ kill log interlock pixel by pixel, and at the bottom so do hand fan ↔ card bottom edge ↔ ally strip, so adapting constants one by one per device quietly breaks those relationships. `BattleSim.BS_HAND_CENTER.y` also takes the same `bottom_offset()` in `_ready`, so the hand ↔ strip spacing stays the same on every device. The stretch is **`expand`**, so on a phone the width is exactly 1080 and only the height extends (with zero insets · 9:16 both offsets are 0, so the layout doesn't differ by a single pixel from before — measured). Full-screen dims must use `ScreenMetrics.viewport_size()`, not a `1920` literal. Conventions · per-device values · desktop verification are in **`docs/mobile_safe_area.md`**. |
| Opponent hand layout | The opponent hand is also an overlapping **fan**, shaped as the player hand **flipped top-to-bottom**: the circle's centre is *above* the cards, so θ=0 is the lowest point of the arc, and therefore **the middle card protrudes furthest down below the panel while both ends curl back up**. Tilt is `−θ` (mirroring the player fan's left/right lean). With `HudBuilder.AI_HAND_FAN_RADIUS` 620 / `AI_HAND_FAN_STEP_DEG` 3.2 / `AI_HAND_FAN_MAX_SPREAD_DEG` 28, the centre spacing between cards narrows from 34.6px (overlapping more than half of a 72px card) down to 26.9px at 12 cards. The detailed formula is in `ui/README.md`. |
