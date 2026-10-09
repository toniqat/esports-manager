# Match Flow — Ban/Pick

**표시 텍스트는 l10n key (`match` 도메인, `match.ban_pick.*` · `match.mech_detail.*` · scene keys `match.ban_pick_view.*` · `match.mech_detail_panel.*`; both BAN row labels use `match.ban_pick_view.ban_label`, the sheet's no-cards line uses `match.mech_detail_panel.no_cards`).** Mech passive descriptions (sheet and `MechDetailPanel`) go through `MechSkillSystem.passive_description(pas)`, which fills `{p1}` / `{p2}`. Item scenes whose text is all code-filled (`BanPickMechCell` · `MechSlot` · `Portrait` · `MechMasteryRow` · `MechQuirkRow`) carry `auto_translate_mode = 2` on the root. Role tab / sheet / mech detail role tags are keys `match.ban_pick.role.*` whose text is English caps (TANK …) **in every locale, ko included** — read via `MechDetailPanel.role_tag(r)` (`ROLE_TAGS`); the two-letter badge `BanPickController.ROLE_INITIALS` (Tk · Fi …) is an untranslated glyph like `GameEnums.POSITION_ABBREVS`. **텍스트는 l10n key — `Loc.t`** (mech passive / cards): passive name · description = `Loc.t(pas["name_key"] / ["description_key"])`; mech card rows build via `CardData.from_mech_def` (`BanPickController`, `BanPickSheetCard`, `MechCardCell`, `MechDetailPanel`).

## Files
| File | Role |
|---|---|
| `BanPickController.gd` | `extends Node`, child of MatchFlow. **Rules + state**: sequence, legality, AI, seat table, assignment, result. Fills / refreshes the screen scene, data colours (side · role · tier), drag handling, sheet content |
| `UI_View_BanPickView.tscn` / `.gd` | `class_name BanPickView` — **the screen** (one per `enter`, `BanPickView.create()` under `MatchFlow.canvas`). Binds nodes for the controller, `fit_safe_area()`, `fit_pane(cell_h)`, turn banner (`play_banner` / `clear_banner`) |
| `BanPickTeamBlock.gd` | Script on `%EnemyBlock` / `%PlayerBlock` (inline in the view scene): finds ban chips / mech slots / portraits / hint by name; `set_assign_layout(portrait_h)` |
| `UI_Comp_BanPickOrderRow.tscn` / `.gd` | The order strip, instanced as `%BanPickOrderRow_OrderRow` in `UI_View_BanPickView.tscn` (`create()` for other hosts). Scene: 64 tall, `%Pips` holder (full rect) · `%PipIcon` · `%TurnArrow`. Script: one `BanPickOrderPip` per move into `%Pips` (count = sequence), tween / pulse / triangle bob (`build`, `refresh`, `stop`, `_process`); static `same_run` / `seq_run` |
| `UI_Comp_BanPickOrderPip.tscn` | One order cell (no script): `Panel` (`BanPickOrderPip` variation, r6; code puts a copy of that box with squared capsule-inner corners and the side colour) + `Joint` (2px `SURFACE` `ColorRect` on its left edge, full height, shown inside a capsule) |
| `BanPickGrid.gd` | `@tool` Container on `%Grid`: float-exact grid (`columns`, `h_gap`, `v_gap`) — `GridContainer` lays out in whole pixels and the 191.6px cells drifted 0.6px per row |
| `UI_Comp_BanPickMechCell.tscn` / `.gd` | Grid cell (Button `SelectableTile`, `MOUSE_FILTER_PASS`), `create()` per mech; `setup(tex, initial, role_col)`, `set_highlight` (amber / side-colour border of variable width, derived in code from the variation's box), `set_pilot_dots(mine, enemy, mine_col, enemy_col, focus_mine, focus_enemy)` (pilot badges, section "Grid pilot badges") |
| `BanPickPilotDot.gd` | `class_name BanPickPilotDot` — `_draw` widget placed as nodes in the cell scene: a small round crop of the middle of the pilot's eye band (`PilotImages.eye_for`, `EYE_UV`) in a ring; `show_pilot(pid, side_col, focus)` (focus = accent ring 3px, full opacity; else side-colour ring 2px at `DIM_ALPHA`) |
| `UI_Comp_BanPickMechSlot.tscn` / `.gd` | Team mech slot (frame + art + name band + mastery / quirk tags, tap `Hit`); `setup(side_col, seat)` builds the per-instance frame style |
| `UI_Comp_BanPickPortrait.tscn` / `.gd` | Pilot portrait (back plate, face, side rim, `기벽 n` badge, tap `Hit`) |
| `UI_Comp_BanPickBanChip.tscn` / `.gd` | Ban chip (dimmed art + ✕) |
| `UI_Comp_BanPickSheetCard.tscn` / `.gd` | One card of the sheet's card row (card slot + tap button + count badge), `create()` per card |
| `UI_View_BanPickLoadoutPicker.tscn` / `BanPickLoadoutPicker.gd` | §15 C pre-match card preset picker (section "Card preset picker" below) |
| `MechDetailPanel.gd` / `.tscn` | Assign-step mech detail popup — white modal, same family as `DraftDetailPanel` (section "MechDetailPanel" below) |

**F6 standalone run (dummy data)** — every scene above with a script fills itself when run on its own
(`_fill_preview()` at the bottom of each script, helper `resources/UiPreview.gd`; nothing is saved):
- `BanPickView` — in-memory run (`UiPreview.ensure_run`) + next league opponent, a **preview-only
  `BanPickController`** attached to the scene via its `preview_view` field (production: always null →
  `_build_ui` creates the view under `MatchFlow.canvas` as before). Player turns are pressed as normal
  cell taps, the real AI answers (time scale ×4 meanwhile); it stops at the player's 4th pick (4 bans,
  3:3 picks) with a sheet open. Rosters are copies, so assignment never touches the run's pilots.
- `MechDetailPanel` — in-memory run, Overdrive opened from the seat of the pilot with the best mastery.
- `BanPickOrderRow` — the real sequence (`BanPickController.SEQUENCE`, side colours), move 4 (opponent pick inside a two-cell capsule) current.
- `BanPickMechCell` alone — Triumph cell opened in the sheet, three of my badges highlighted (my pick turn)
  and two dimmed enemy badges (real pilot ids).
- Item scenes (`MechSlot` · `Portrait` · `BanChip` · `SheetCard` · `MechCardCell` ·
  `MechMasteryRow` · `MechQuirkRow`) — hand-set values with real mech / pilot / card / quirk ids,
  filled the way `BanPickController` / `MechDetailPanel` fill them.

## Scene (`UI_View_BanPickView.tscn`) — what the scene owns vs. what code owns
```
BanPickView (Control full rect, theme = OutgameTheme.tres)
├ Background            BG ColorRect over the whole viewport (notch / home-indicator bands too)
├ %SafeArea             full rect, top / bottom offsets = device insets (fit_safe_area)
│ ├ %EnemyBlock         VBox anchored top (25 / 8): BanRow(44: SideLabel · BanLabel · BanPickBanChip_Chip0-1) · Gap 5 ·
│ │                     MechRow(160: BanPickMechSlot_Slot0-4, sep 14, centred) · Gap 2 · PortraitRow(80: BanPickPortrait_Pilot0-4)
│ ├ %PlayerBlock        mirrored, anchored bottom (−10), grows upward: PortraitRow · Gap 2 · MechRow ·
│ │                     AssignGap 2 + Hint 24 (assign only) · Gap 5 · BanRow
│ ├ %Band               between the blocks (offsets 309 / −311); hidden in the assign step
│ │ └ %Pane             full width, height + vertical centring from fit_pane
│ │   ├ PaneCard        Panel `Card`, 25px side margins
│ │   ├ Content         VBox (33 / 8 inset): %BanPickOrderRow_OrderRow(UI_Comp_BanPickOrderRow.tscn instance, 64) · %Tabs(58: Tab0-5 `SelectableTile`, font 20) · 10 · %Scroll/%Grid
│ │   ├ %SheetDim       dims the pane only
│ │   └ %Sheet          bottom sheet (bottom = grid bottom, height from fit_pane): SheetArt(+Placeholder) ·
│ │                     SheetName · SheetStats · SheetNoPassive / %SheetPassiveIcon (36² passive icon tile) · SheetPassiveHead · SheetPassiveDesc ·
│ │                     SheetCardsHeader · %SheetCardRow · SheetNoCards · SheetMastery(SheetRider · SheetIntel) ·
│ │                     SheetButtons(SheetClose · SheetConfirm)
│ ├ %StartButton        assign-step bottom bar (`BarPrimaryButton`, 128 tall; inset from OutgameTheme.fit_bottom_bar)
│ └ %DragGhost          (+ DragGhostArt) the slot under the finger
└ Banner                viewport-centred: %BannerBar · %BannerLabel (above everything, mouse-ignore)
```
- **Scene**: every position / size / gap / font size, label variations (`BodyLabel`, `CaptionLabel`,
  `OnFillLabel`, `TitleLabel`, `SubLabel`, `AccentLabel`, `FaintLabel`), `PrimaryButton` / `GhostButton`,
  `BarPrimaryButton` (start bar), `SelectableTile` (filter tabs, plain grid cell), `Card` for the pane,
  BanPick-only looks as screen variations (`resources/README.md` → Screen variations): the sheet with
  amber border (`BanPickSheetCard`), ban chip (`BanPickBanChipPanel`), drag ghost (`BanPickDragGhost`),
  slot frame (`BanPickMechSlotFrame`) and portrait rim (`BanPickPortraitRim`) — the last two get the side
  colour on a `variation_box` copy in `setup`. No local StyleBoxes. The `SideLabel`s keep their team-side colour from code (not a semantic
  `NegativeLabel` / `LinkLabel`).
- **Code**: device values (insets, grid height — `fit_*`; the start bar's inset via
  `OutgameTheme.fit_bottom_bar(start_button, safe_area)` in `BanPickView.fit_safe_area`), data colours
  (side colour of labels / rims / frames, role badge, mastery / quirk / analysis tag fills, slab tints),
  state looks (selected tab = switch `theme_type_variation` to `SelectableTileOn`; cell highlight and
  drop-target border = derived boxes, colour / width are data), texts, tweens (banner, order row,
  gather, enemy re-seat), instanced items whose count is data (mech cells, sheet cards, order-row cells).
- A node deleted from a scene stays deleted: tags, badges, hint and the role badge are bound with
  `get_node_or_null` and skipped when missing.
- `gui/common/snap_controls_to_pixels` rounds each Control's *local* position, so nested nodes can
  land ≤1px from where the old flat absolute layout put them (the sheet, the gathered assign blocks).
- Drag positions come from the event (`gui_input` position → canvas), not from
  `get_local_mouse_position()` — identical for real input, and scriptable with `push_input`.

## BanPickController.gd

Implements the LoL-international ban/pick (밴픽) draft against an AI opponent that
"fidgets" (만지작거린다) — see the Opponent AI section below.

### Sequence (14 actions)
Pattern: `B-B-P-PP-PP-P-B-B-PP-PP` — 4 bans + 10 picks total. Each side ends
with **2 bans + 5 picks**.

| # | Side | Kind |
|---|---|---|
| 0 | Blue | Ban |
| 1 | Red | Ban |
| 2 | Blue | Pick |
| 3 | Red | Pick |
| 4 | Red | Pick |
| 5 | Blue | Pick |
| 6 | Blue | Pick |
| 7 | Red | Pick |
| 8 | Blue | Ban |
| 9 | Red | Ban |
| 10 | Blue | Pick |
| 11 | Blue | Pick |
| 12 | Red | Pick |
| 13 | Red | Pick |

The constant `SEQUENCE` encodes this directly. `player_side` (BLUE or RED) is
passed in by MatchFlow — it is currently **always fixed to BLUE** (see the side section of
`match_flow/README.md`, "Side (`player_side`) — currently always BLUE").

---

## Screen

One vertical sheet is divided into three blocks: **top / middle / bottom**.

```
┌──────────────────────────────────────────┐ ← opponent team block
│ RED · Team 1                    BAN ✕ ▫  │
│ ▓▓  ▓▓  ▓▓  ▓▓  ▓▓   5 eye-level portraits │
│ name name name name name                 │
│ [mech][mech][pick3][pick4][pick5] pick slots │
├──────────────────────────────────────────┤ ← pick pane (one white card)
│            ▲  (bobs upward on opponent's turn) │
│ ▬▬[✕]▬▬▬▬▬▬▬▬▬▬▬  order row (14 cells)      │
│     ▼  (bobs downward on my turn)          │
│ [전체][TANK][FIGHTER][ASSASSIN][SUP][SNP] │
│ ▤ ▤ ▤ ▤ ▤    ← 5 columns                  │
│ ▤ ▤ ▤ ▤ ▤      vertical scroll showing 4.5 rows │
│ ▤ ▤ ▤ ▤ ▤                                │
│ ▤ ▤ ▤ ▤ ▤    (the fourth row is half cut) │
├──────────────────────────────────────────┤ ← ally team block (mirrored)
│ [mech][mech][pick3][pick4][pick5]         │
│ name name name name name                 │
│ ▓▓  ▓▓  ▓▓  ▓▓  ▓▓                        │
│ BLUE · Team 0                   BAN ✕ ▫  │
└──────────────────────────────────────────┘
```

(`[전체]` = All.)

### Colour — outgame white-background family
Background is `OutgameTheme.BG`, pick pane · sheet are shadowed white cards (`card_style`), empty
cells are `SURFACE_SUNK`, text is `TEXT` / `TEXT_SUB`, accent is amber (`ACCENT`) — the same table as
the season screens (hub · week progress (시간 경과) · standings). Only the side colours are kept
separately, one step darker than in-game, so they read on white (`BLUE_COLOR` / `RED_COLOR`). The old
dark board made this one screen look in-game, reading as "has the match already started?".

### Order row (14 cells) — top of the pick pane, right above the role-class filter
It used to be at the **very top** of the screen — to see whose turn it was, the eye had to travel to
the screen edge and back. Now it is right above where you choose (`%BanPickOrderRow_OrderRow`, 64px strip).
- A cell's colour is that move's side colour, and **the darker, the more current** (past moves about
  half · remaining moves nearly background).
- **The current cell thickens** (`PIP_H` 12 → `PIP_ACTIVE_H` 26, `PIP_GROW_SEC` tween) and holds
  **a ✕ icon for a ban, ✓ for a pick** in the centre — `ban_x.svg` / `pick_v.svg` in
  `resources/images/ui/banpick/` (white lines, laid directly over the cell colour).
- A **triangle** (`turn_arrow.svg`) attaches to the current cell — on my turn it sits **below** the
  cell pointing down (toward our team block) and bobs downward; on the opponent's turn it sits
  **above** pointing up (toward the opponent block) and bobs upward, by `TURN_ARROW_BOB_PX` with
  period `TURN_ARROW_BOB_SEC` (`BanPickOrderRow._process`; a (1 − cos)/2 curve, so it slows at both ends and doesn't
  jump when the cell changes). Icon · triangle aren't per cell; a single set moves to the current
  cell (`BanPickOrderRow.refresh`).
- **Consecutive moves of the same action by the same team join into one capsule** (`BanPickOrderRow.same_run` /
  `seq_run` — in the current order table, the four double-picks). The capsule has no gaps inside and
  only its outer corners are rounded, and at each joint a 2px background-colour **joint line** stands
  so you can read how many moves it spans — the `Joint` child of the later cell, anchored full height
  so it follows the cell's tween (drawn after that cell, before the next one). The current cell pulses
  with `self_modulate`, so its own joint line does not pulse with it. If the current move is inside a capsule, **the whole capsule**
  thickens (thickening one cell alone makes a step). Within it, only the current cell has the dark
  colour + ✕/✓ icon + **pulse** (alpha 1 ↔ 1 − `PIP_PULSE_DEPTH` 0.38 with period `PIP_PULSE_SEC`
  0.9 s, `_process`), and the capsule's next move is one step darker than the remaining moves
  (`seq_color` state 3).
- In the assignment step it is removed along with the pick pane.

### Turn banner
Each time a move passes, a **side-coloured band** sweeps across the screen centre — `내 차례 밴`
(My ban) / `상대 차례 밴` (Opponent's ban) / `내 차례 픽` (My pick) / `상대 차례 픽` (Opponent's
pick). Same shape as the in-game "당신의 차례" (Your turn) banner (spreads from the centre to both
sides → holds → fades, `BanPickView.BANNER_*`) and **does not block input**. It is the view's last child
(`Banner`, outside `%SafeArea`), so it draws over the sheet and the drag ghost. If the next move
arrives first, the previous banner is removed (`BanPickView._banner_gen`).
**It appears only when the turn passes or ban ↔ pick switches** — for a move where the same team
continues the same action (the capsule's second cell) the band doesn't reappear. What it would say
is the same as the move just before, and the order row's capsule already conveys the continuation.
The opponent's thinking time (the wait in `_maybe_run_ai`) is unchanged even without the band.

### Pilot portraits (top = enemy / bottom = ally)
The **same eye crop** as the battlefield (전장) strip (스트립) (`PilotImages.eye_for`, 480×200) — the
faces seen at the in-game top / bottom stand in the same places in ban/pick. Cell height is derived
from that ratio (`EYE_ASPECT` 2.4): stretching to an arbitrary height squashes faces.

> **Set `TextureRect.expand_mode` before `texture`.** With the default
> `EXPAND_KEEP_SIZE`, the texture size becomes the **minimum size** as is, so a `size` given
> afterwards gets pulled up — a 480×200 eye crop burst out of a 192×80 cell and covered the whole
> name·pick slots below it, and the 1024² mech art covered the entire sheet (both measured). All
> five `TextureRect` sites in this file keep that order.

### Pick slots = seat table (ally slots move even during ban/pick)
A mech slot's content is `_seat_mechs[side]` (seat → mech_id, -1 = empty seat), and a new pick sits
in **the first empty seat from the left**. **Ally slots can be dragged to another player's seat even
during ban/pick** (`_setup_team_block` attaches `_bind_slot_drag` to the ally block — swap if
occupied, move if empty). So an ally slot is "the machine of the player above it" from the start,
and the assignment step inherits that arrangement. A tap opens that machine's bottom sheet (commit
is locked). Opponent slots stay in pick order during ban/pick and are re-seated by position in the
assignment step (the assignment section of `match_flow/README.md`, "Assignment (inside the ban/pick
screen)"). The pick preview of what the opponent is hovering also sits in the first empty seat
(`_ai_hover_slot`).

The bottom block is the top block **in mirrored order** (picks → names → portraits → bans). The two
teams' pick slots face each other across the grid, so who took what so far reads as one row each
above and below the grid.

### Mech grid
5 columns (`%Grid.columns`), `BanPickView.GRID_VISIBLE_ROWS` **4.5 rows**. Being non-integer is the
point — the fifth row showing half cut is the only signal that "there's more below". The cell size is the cell
scene's (`UI_Comp_BanPickMechCell.tscn`: column width 191.6 × (square art + 36 badge strip) = 227.6); the **grid height** is 4.5 rows
of it, clamped to the band between the team blocks (`BanPickView.fit_pane`) — so cells stay square on
every safe area (안전 영역) and only the number of visible rows changes.

What goes in one cell: role-class badge (top-left) · machine art · **pilot badges** — my pilots who
ride it well in the strip under the art, the enemy's over the art's top-right (section "Grid pilot
badges"). No machine name, numbers or passive: the art is what you scan by, everything else is in
the sheet one tap away (name · stats · passive · cards).

A banned / picked machine has its whole cell covered by a slab with `BAN` / `BLUE` / `RED` stamped
in the centre (the colour changes too). It can still be tapped **to view**; only committing is
blocked.

**Thumbnails are pre-baked files** — the original mech art is 1024² uncompressed, so holding all 21
as is costs 88MB of VRAM. `MechImages.portrait_for` returns 256² portraits (`_mech_thumb` caches
them). Only the sheet uses the original full-body art, and that's always just one machine.

### Role-class filter
Six tabs `[전체][TANK][FIGHTER][ASSASSIN][SUPPORT][SNIPER]` (전체 = All) **filter the grid**. Filtered
cells are hidden **and their positions vacated** — leaving empty cells makes it unreadable how many
machines a role class has (`_apply_filter()` is the only place that reflows positions).

### Bottom sheet (1st tap select → 2nd tap commit)
Tapping a mech once raises a sheet over the grid showing that machine's **stats · passive (name ·
keyword · description) · card set**. Committing is the sheet's `밴 확정` (Confirm ban) / `픽 확정`
(Confirm pick) button, or **tapping the same mech once more**. The old way, where one tap committed
immediately, let a single mistake change the whole match in an irreversible choice.

- The sheet **opens even when it is not my turn** — peeking at what to pick next while the opponent
  deliberates is half of what a ban/pick screen does. In that case only the commit button is locked,
  with the reason written as `상대 차례` (Opponent's turn) / `선택 불가` (Unavailable).
- The dim covers **only the grid and filter tabs** — the top and bottom team blocks are the ban/pick
  situation so far and must stay visible while looking at the sheet (without knowing what's already
  gone you can't judge whether to pick this machine). Tapping the dim closes it.
- Cards are **the same node** as the hand (손패) (`Card.tscn`, `SHEET_CARD_SCALE` 0.9) — a separately
  drawn picture would give no way to confirm it's the same card that actually goes into the deck.
  `CardData` assembly goes through one place, `CardData.from_def()` (the same path as
  `DraftDetailPanel`). Call `add_child` **before** `setup` — `Card.gd`'s `@onready` references only
  resolve after entering the tree.
- **Tapping a card shows a description box above the card row** (`CardDescBox`, white box). The card
  face has no description, so this is where you read what that machine's cards do. Tapping the same
  card again closes it; tapping another card switches. The box briefly covers the passive
  description — the hand that tapped a card wants to see that card right now. The assignment step's
  `MechDetailPanel` follows the same rule (above the tapped card).
- The badge under a card is `count`. A card with `count = 0` is never in the deck from the start and
  only comes into the world when a passive or another card creates it, so it's labelled `생성 전용`
  (Generated only) — without writing that down, "why doesn't this card ever reach my hand" would be
  answered nowhere on screen.
- The left art cell has **only its width fixed** (scene `SheetArt`, 280); its height takes all the space
  left in the sheet and centres vertically within it — attaching the art to the top would leave a
  hole of 300px+ with nothing under it (square art can't grow except by widening).

### Entry (`enter`)
```gdscript
enter(all_mechs, player_side,
      player_roster, enemy_roster,        # Array[PlayerData] (sorted by role 0..4)
      player_team_name, enemy_team_name)  # String
```
Rosters and team names are used to build the top and bottom portrait rows. The last four have
defaults, so it still runs when BanPick is launched on its own (portrait spots become empty
backplates (뒤판)).

### Opponent AI — fidgeting
The opponent doesn't move right away (`_maybe_run_ai`). After the turn banner passes, it ranks the
**candidates actually worth picking** in that situation by score (`_ai_rank`), **hovers over** 0 to
`AI_HOVER_MAX_COUNT` (2) of the top `AI_CONSIDER_TOP` (5) in turn, then picks the #1 and commits.
Each hover lasts a random `AI_HOVER_MIN..MAX` (0.3–0.8 s).

Score — for a **pick**, a role class the own team doesn't have yet +3 (−2 if already present); for a
**ban**, a role class the opponent (= player) team doesn't have yet +2.5 (a ban that steals a seat
to be filled); a machine with a passive +1; plus jitter `randf() × 1.5`.
In a season run, mech mastery is added (see "Mech mastery" below): a pick gets
`MASTERY_AI_PICK_W × mastery / MASTERY_MAX` of the own pilot whose role matches the machine's role
class, a ban gets `MASTERY_AI_BAN_W × mastery / MASTERY_MAX` of the player's pilot of that role — so
the AI tends to pick its mains and ban the player's.

While hovering (`_ai_hover_id`), that grid cell wears a **thick border in the opponent's side
colour**, and the machine sits faintly (α 0.45) in the opponent team's **next slot** (pick slot for
a pick, ban chip for a ban) as a preview (`_ai_hover_slot`). If the move passed or the screen was
removed during the wait, it quietly lets go.

### Output
Emits `phase_finished({banned, player_picks, enemy_picks})` once index 14 is
reached. `player_picks` / `enemy_picks` are mapped from blue/red to the user's
perspective. Bans live in two sets: `_banned` (both teams combined) for legality checks and
`_side_bans[side]` for display — previously a single array was walked back through `SEQUENCE` to
infer whose ban each was, and that calculation was wrong.

### Screen fit (safe area)
Scene-based pattern B: `Background` covers the whole viewport, everything else lives in `%SafeArea`
whose top / bottom offsets are the device insets (`BanPickView.fit_safe_area`). The blocks anchor to
its edges, the pane fills the band between them (`fit_pane`) and the start bar reaches down through
the bottom inset — no per-device constants. Verification is done by
running in a window and faking insets with `ESM_SAFE_AREA` — it can't be done headless
(`docs/mobile_safe_area.md`).

### Mechs have a role, but assignment is still free
`mechs.role` is used by this screen's filter · data validation · **the opponent's auto-assignment**
(`_enemy_role_order`: a greedy pairing scored role match first, then the seat pilot's mastery with
the machine — so each seat gets a machine of its role class, the one that pilot rides best, and an
off-role leftover goes to whoever handles it best; without mastery it is the old role-then-pick-order
rule). Which machine the player puts in which seat is still free.

---

## Mech mastery (M4) and analysis markers

Active only in a season run (`MechMastery.is_enabled(season_state)`, read once per `enter` by
`_setup_mastery`); standalone MatchFlow shows none of it and the AI scores as before. Rules and
numbers live in `features/season/mastery/README.md` / `MASTERY_*` in const.csv.

| Where | What |
|---|---|
| Mech slots (`_refresh_slot_mastery`) | Top-left tag `<tier> <bonus>` (e.g. `능숙 +2`) filled with the tier colour — the pilot on that seat with that machine. **My slots always** (also during ban/pick, so dragging a slot shows the change at once); **enemy slots** only when analysis reveals mastery (`StaffSystem.analysis_tier >= 2`) and after the assign intro re-seats them by pilot (`_enemy_seated`). |
| Grid cells (`_refresh_cell_marks`) | Pilot badges (`BanPickPilotDot`) — see "Grid pilot badges" below. Taken cells show none. |
| Bottom sheet (`_fill_sheet_mastery`) | Under the art, left of the buttons: my natural rider's `name tier value (스탯 bonus)`, and the analysis line `상대 예상 픽 — pilot` (an enemy pilot's top-mastery machine, `_enemy_likely`, analysis tier ≥ 2). |
| `MechDetailPanel` | A `숙련도` block — that team's five pilots with this machine (tier · value · bonus), the tapped seat's pilot marked ▶ (`_mastery_rows`; enemy only with analysis tier ≥ 2). |

### Grid pilot badges
Computed once per `enter` (`_setup_adept`, mastery does not change during the draft) into
`_my_adept` / `_enemy_adept` (mech_id → pilot ids), drawn by `_refresh_cell_marks` on every refresh:
- **Mine** — under the art (where the name used to be): every one of my five pilots whose mastery
  with that mech is tier ≥ `ADEPT_TIER` (2 = 능숙), not only the natural rider; seat order, max 5.
- **Enemy** — over the art's top-right: the enemy's 능숙+ pilots, highest mastery first (ties by
  seat), max `ENEMY_DOTS_MAX` (2); only while analysis reveals mastery (`_show_enemy_likely`,
  `StaffSystem.analysis_tier >= 2`).
- **Highlight** — my pick turn → my badges (accent ring, full opacity), my ban turn → the enemy
  badges; otherwise (the other row / opponent's turns) side-colour ring, dimmed.
- Replaces the old cell tags: `예상 픽` / `추천 밴` (top-right) and my rider's tier (bottom-left) are
  gone, and so are the analyst's recommended bans (`_analyst_bans`, const `MASTERY_ANALYST_BANS`,
  keys `match.ban_pick.tag_expected_pick` · `intel_analyst_ban` deprecated). Banning an enemy main
  is still the natural mastery penalty — that pilot falls back to a lower-mastery machine.
- The AI is untouched: `_ai_rank` reads mastery directly (`MASTERY_AI_PICK_W` / `_BAN_W`).

## Quirks (§14 T1)
Active while `QuirkSystem.is_enabled(season_state)` (`_quirk_on`, set in `_setup_mastery`). **My
pilots only** — opponents have no quirks. Rules: `features/season/quirk/README.md`.

| Where | What |
|---|---|
| My portraits (`_refresh_portrait_quirk`) | Bottom-right pill `기벽 n`, filled with the pilot's highest quirk grade colour. |
| My mech slots (`_refresh_slot_quirk`) | Second tag under the mastery tag: `기벽 +N` = `QuirkSystem.bonus_total` of the seat's pilot with that mech (conditional quirks follow the mech, so dragging a slot updates it). Hidden at 0. |
| Bottom sheet (`_fill_sheet_mastery`) | The rider line gets `· 기벽 +N` next to the mastery stat bonus. |
| `MechDetailPanel` | A `기벽 — pilot n/slots (스탯 +N)` block for the tapped seat's pilot (`_quirk_rows`): name · grade, effect line; quirks whose condition fails with this mech are dimmed `(조건 미충족)`. |

The pilot detail popup (`DraftDetailPanel`, owned by `features/meta/run_setup/`) does not list
quirks yet.

---

## MechDetailPanel (`.tscn`)

The assignment step's mech detail popup. **Layout is owned by `UI_View_MechDetailPanel.tscn`**
(`docs/ui_scene_migration.md` §3); the script only binds `%` nodes, fills them and adds the
per-mech repeated rows. Created once with `MechDetailPanel.create()` (never `.new()` — that is an
empty layer); `open(m, mastery_rows, quirk_info)` refills and shows it, `close()` hides it (nodes are
reused). Scene root saved visible, `create()` hides it.

```
MechDetailPanel (CanvasLayer 20)
└ %Root (full rect, OutgameTheme.tres)
  ├ %Dim (flat Button, tap = close) · DimRect (Panel `DimPanel`)
  ├ %ArtPlaceholder (grey slab + %ArtName `SubLabel`, shown when no art) · %Art (TextureRect, keep-aspect box, screen coords)
  └ %SafeArea (full rect; offset_top = top inset, offset_bottom = −bottom inset — `_fit_safe_area`)
    ├ Backdrop (Panel `Card`; x 596..1056, top 150, bottom anchored to the safe bottom −180)
    ├ %Scroll (22px inside the backdrop) → Body (VBox)
    │   Header (%Name `HeadingLabel` 40 · %Sub `CaptionLabel`, role colour from code)
    │   StatsTitle `SubLabel` 24 · Stats (3 `SunkPanel` chips at thirds: Key `CaptionLabel` 19 · %HpValue %AtkValue %PresenceValue `BodyLabel` 34)
    │   %MasteryBlock (title + %MasteryRows ← UI_Comp_MechMasteryRow.tscn)
    │   %QuirkBlock (%QuirkTitle · %QuirkEmpty · %QuirkRows ← UI_Comp_MechQuirkRow.tscn)
    │   PassiveTitle · %NoPassive | %PassiveBox (PassiveRow 80: %PassiveTile 64² at (14, 4) ← `SkillImages.make_mech_icon_tile` · %PassiveName `AccentLabel` 30 · %PassiveKw `CaptionLabel` 19 at x 94 — same row as DraftDetailPanel's skill row; then %PassiveDesc `BodyLabel` 21)
    │   CardsTitle · %NoCards | %CardsBox (note `CaptionLabel` 18 · %CardGrid 3 cols ← UI_Comp_MechCardCell.tscn)
    └ %Close (`GhostButton`, 84 tall, bottom anchored to the safe bottom −80)
```

| File | Role |
|---|---|
| `MechDetailPanel.gd/.tscn` | The popup. Code-owned colour: role colour (`%Sub`, `OutgameTheme.ROLE_COLORS`) only; code-owned position: the `%SafeArea` insets |
| `MechMasteryRow.gd/.tscn` | One mastery row (name 46% · tier 32% · bonus 22%, `BodyLabel` 21); tier colour (`MechMastery.tier_color`, white palette) and ▶ row `TEXT` vs others `TEXT_SUB` from data |
| `MechQuirkRow.gd/.tscn` | One quirk: grade-coloured name (`QuirkSystem.grade_color`) + autowrapped effect (`CaptionLabel` 18, indent 14); inactive = name faded halfway to white, effect `TEXT_FAINT` |
| `MechCardCell.gd/.tscn` | One card cell: `Card.tscn` instance at 0.8, transparent `%Hit` (PASS — keeps drag scroll), count badge (`CaptionLabel` 17; `×n` `TEXT_SUB`, `생성 전용` `LINK`). `tapped(card)` → panel shows the white `CardDescBox` (`light`) above the card |

**White modal, same family as `DraftDetailPanel`** (`features/meta/run_setup/`) — the assign step
alternates pilot and mech taps, so both popups use the same pieces: `DimPanel` dim, `Card` backdrop at
the same x / top, `SunkPanel` stat chips, `HeadingLabel` name, `SubLabel` 24 section titles,
`AccentLabel` 30 skill / passive name, `GhostButton` close. No local StyleBoxes or colour overrides in
the scene. Differences kept on purpose: this backdrop has a fixed height (top 150, bottom anchored to the
safe area) where the pilot panel fits its content, and this panel follows the device safe area
(`%SafeArea`) — on a notched screen it starts `top inset` lower than the pilot panel.
Quirk effect lines are plain autowrapped labels now (the old code estimated line counts with the
fallback font and could overrun the panel edge).

---

## Grid scrolling — why mech cells are `MOUSE_FILTER_PASS`

The cell `Button` (`UI_Comp_BanPickMechCell.tscn`) has its filter **lowered to PASS** (default is STOP).
With STOP the mech grid doesn't scroll at all on phones — drag scrolling starts only when the mouse
press emulated from touch reaches the `ScrollContainer`, and STOP cuts that off; since the cells
cover the grid with no gaps, there's no spot that escapes. `%Grid` being `IGNORE` is part of
the same chain (if the body were STOP, even pressing the empty space between cells would cut it
there). On desktop the wheel pierces STOP, so this defect isn't visible. Rules and how to verify:
**`docs/mobile_safe_area.md` §5**.

## Card preset picker (§15 C, `BanPickLoadoutPicker`)
Pressing the assignment step's start bar (`_on_start_pressed`, the only hook in `BanPickController`) opens
`BanPickLoadoutPicker.open_if_needed(self, my roster, _finish)` when a season run is active and at least one of
my pilots owns 2+ card presets (`PilotLoadout`, `features/season/awakening/README.md`); otherwise `_finish`
runs as before. Mechs can still be re-seated: 취소 closes the popup and returns to the assignment. 확인 writes
each pilot's choice with `PilotLoadout.set_active` (run state — the Saturday prep split keeps it for Sunday)
and calls `_finish`; `MatchFlow._finalize_rosters` → `PilotLoadout.apply_to` puts the active preset on the
roster copies (fresh launch, Sunday resume and mid-match resume alike).
- Scene: CanvasLayer 20 (above the ban/pick canvas), `DimPanel`, `%SafeArea` (device insets), centred
  `PopupCard`: title · hint · `%Rows` (one duplicate of `%RowTemplate` per pilot, seat order: `SunkPanel` row —
  round portrait · name · position · preset tabs (`TabTemplate` duplicates, `SelectableTile` / `SelectableTileOn`,
  "기본" / "프리셋 n") · the tab's 3 cards as `AwakeningCardCell` at 0.55 (no tap; "+" cards captioned)) ·
  footer 취소 (`GhostButton`) / 확인 (`PrimaryButton`). Text: `awakening.picker.*`, `ui.button.*`.
- F6: in-memory run, two of my pilots get an extra preset; buttons only print.
