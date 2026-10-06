# Match Flow — Ban/Pick

## BanPickController.gd
`extends Node` — child of MatchFlow.

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
│ ▤ ▤ ▤ ▤ ▤      vertical scroll showing 3.5 rows │
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
the screen edge and back. Now it is right above where you choose (`PIPS_ROW_H` strip).
- A cell's colour is that move's side colour, and **the darker, the more current** (past moves about
  half · remaining moves nearly background).
- **The current cell thickens** (`PIP_H` 12 → `PIP_ACTIVE_H` 26, `PIP_GROW_SEC` tween) and holds
  **a ✕ icon for a ban, ✓ for a pick** in the centre — `ban_x.svg` / `pick_v.svg` in
  `resources/images/ui/banpick/` (white lines, laid directly over the cell colour).
- A **triangle** (`turn_arrow.svg`) attaches to the current cell — on my turn it sits **below** the
  cell pointing down (toward our team block) and bobs downward; on the opponent's turn it sits
  **above** pointing up (toward the opponent block) and bobs upward, by `TURN_ARROW_BOB_PX` with
  period `TURN_ARROW_BOB_SEC` (`_process`; a (1 − cos)/2 curve, so it slows at both ends and doesn't
  jump when the cell changes). Icon · triangle aren't per cell; a single set moves to the current
  cell (`_refresh_pips`).
- **Consecutive moves of the same action by the same team join into one capsule** (`_same_run` /
  `_seq_run` — in the current order table, the four double-picks). The capsule has no gaps inside and
  only its outer corners are rounded, and at each joint a `PIP_DIVIDER_W` (2px) background-colour
  **divider** stands so you can read how many moves it spans (dividers are attached after the cells —
  sibling order is draw order). If the current move is inside a capsule, **the whole capsule**
  thickens (thickening one cell alone makes a step). Within it, only the current cell has the dark
  colour + ✕/✓ icon + **pulse** (alpha 1 ↔ 1 − `PIP_PULSE_DEPTH` 0.38 with period `PIP_PULSE_SEC`
  0.9 s, `_process`), and the capsule's next move is one step darker than the remaining moves
  (`_seq_color` state 3).
- In the assignment step it is removed along with the pick pane.

### Turn banner
Each time a move passes, a **side-coloured band** sweeps across the screen centre — `내 차례 밴`
(My ban) / `상대 차례 밴` (Opponent's ban) / `내 차례 픽` (My pick) / `상대 차례 픽` (Opponent's
pick). Same shape as the in-game "당신의 차례" (Your turn) banner (spreads from the centre to both
sides → holds → fades, `BANNER_*`) and **does not block input**. It stands not on the board
(`_panel`) but on a sibling in the same canvas (`_banner_root`), so sheets attached later don't
cover it. If the next move arrives first, the previous banner is removed (`_banner_gen`).
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
during ban/pick** (`_build_team_block` attaches `_bind_slot_drag` to the ally block — swap if
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
`GRID_COLS` 5 columns, `GRID_VISIBLE_ROWS` **3.5 rows**. Being non-integer is the point — the fourth
row showing half cut is the only signal that "there's more below". Cell **width** comes from the
column count, **height** is derived by dividing the remaining vertical space by 3.5 (`_layout()`) —
so "3.5 rows" holds even on devices with different safe areas (안전 영역).

What goes in one cell: role-class tag · machine art · machine name · `HP / ATK / 존재감` (presence) ·
**passive name**. The passive is written right in the cell because picking a machine fixes one
passive along with it — if you had to open the sheet every time to see it, scanning 21 machines
would take 21 taps. Only the detailed description lives in the sheet.

A banned / picked machine has its whole cell covered by a slab with `BAN` / `BLUE` / `RED` stamped
in the centre (the colour changes too). It can still be tapped **to view**; only committing is
blocked.

**Thumbnails are baked** — the original mech art is 1024² uncompressed, so holding all 21 as is costs
88MB of VRAM. `_bake_thumbs()` shrinks them once to `THUMB_PX` (256), bakes them into
`ImageTexture`, and releases the original reference. Only the sheet uses the original full-body art,
and that's always just one machine.

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
- The left art cell has **only its width constant** (`SHEET_ART_W`); its height takes all the space
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
The whole board is pushed down with `ScreenMetrics.indent_to_safe_top()` and the top strip is filled
with `backfill_top()`. Every vertical coordinate is computed from `ScreenMetrics.safe_h()`
(`_layout()`), so there are no constants to fix one by one per device. Verification is done by
running in a window and faking insets with `ESM_SAFE_AREA` — it can't be done headless
(`docs/mobile_safe_area.md`).

### Mechs have a role, but assignment is still free
`mechs.role` is used by this screen's filter · data validation · **the opponent's auto-assignment**
(at each seat it puts a machine of the same role class as that player's role). Which machine the
player puts in which seat is still free.

---

## Grid scrolling — why mech cells are `MOUSE_FILTER_PASS`

The `Button` in `_build_mech_cell` has its filter **lowered to PASS** (default is STOP).
With STOP the mech grid doesn't scroll at all on phones — drag scrolling starts only when the mouse
press emulated from touch reaches the `ScrollContainer`, and STOP cuts that off; since the cells
cover the grid with no gaps, there's no spot that escapes. `_grid_content` being `IGNORE` is part of
the same chain (if the body were STOP, even pressing the empty space between cells would cut it
there). On desktop the wheel pierces STOP, so this defect isn't visible. Rules and how to verify:
**`docs/mobile_safe_area.md` §5**.
