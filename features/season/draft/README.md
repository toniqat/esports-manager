# Team Draft

Initial campaign step: the player picks one pilot (파일럿) per role (5 total) from
the **25 named pilots (네임드 25인)** pool. The displaced pilot from team-0 swaps with the picked
pilot's prior team — every team always has exactly one pilot per role.

**The screen is an Uma Musume–style character pick.** The lower half is a scrolling grid of
character thumbnails, above it one row of role filters, and above that the **upper-body
illustrations** of the 5 picks stand side by side. The old fixed 5-column (role) × 5-row (rank)
grid had to cram 25 people onto one screen and could not grow its cells, so faces were 48px and
"who am I picking" could only be read from name tags — with a scrolling grid, cell size is freed
from the head count.

## The screen toggles between two modes — PICK ↔ CONFIRM
**PICK** is the picture above; the bottom bar's **"다음"** (Next) (enabled only when all five
slots are filled) moves to **CONFIRM**. During the transition **the pick pane (filter row + grid +
backplate (뒤판)) slides off the bottom of the screen and the 5-pick block drops to the vertical
centre of the screen** — both moves run in one tween (`MODE_ANIM_SEC` 0.38 s, cubic in-out), and
"뒤로" (Back) runs the reverse. The pick pane is attached before the bottom bar, so the exiting
grid hides behind the bar. While the animation runs (`_busy`), all input is ignored.

CONFIRM's primary action is **"게임 시작"** (Start game) (formerly "드래프트 확정" (Confirm draft)).
Team formation is the last outgame screen and the campaign starts after it, so the screen isn't
simply swapped — **fade to black (0.30 s) → fake loading (0.50 s, `LOADING` + bar) → fade in
(0.35 s)** (`_play_launch_transition` → shared `resources/SceneFade.gd`). The cover is **a
`CanvasLayer` (layer 100) attached to root**, so it survives after the draft is hidden (the
ban/pick (밴픽) → battlefield transition uses the same helper). `validate_draft` runs **before the
fade** (a confirm that would be rejected doesn't cover the screen), and `apply_draft` · closing the
detail popup · `goto(HUB)` (= autosave right after the draft) run **at the moment the screen is
fully covered** (`_commit_draft`).

**The 5-pick block lives in the local coordinates of one Control, `_slot_row`.** That way CONFIRM
can push just that node's y to move the whole block. The pick pane is gathered under one Control,
`_pick_root`, for the same reason.

## Things removed from the screen
- **The title ("TEAM DRAFT") and head count ("내 팀 N/5" (My team N/5))** — the five slots filling
  up already answers that.
- **The three lines of role-class name · pilot name · overall stat in a thumbnail cell** — that
  space shrank to a single **role-class badge at top left** (the **same badge** as the ban/pick mech
  grid), and the cell became square so the face fills it.
- **The position text above the illustration (탑 (Top) · 정글 (Jungle) …) and the name below it** —
  the role is shown by the **role-class badge at the illustration's top left** (the same
  `PilotThumb.add_role_badge` as the grid thumbnails; **it stands even on an empty slot** — the badge
  says which role the empty slot is for), and the name lives in the detail popup.
- **The `역할 · 원소속` (role · original team) line under the illustration** and **the pilot skill
  panel at the bottom** — the detail popup carries both entirely. Laying summaries across a picking
  screen makes people read the summaries instead of looking at the faces.

**Where the detail popup opens moved from the name cell to the illustration itself.** Previously
the name cell below did that job because "tapping the illustration would be confused with the tap
that empties the slot", but the only way to empty a slot is **tapping the same thumbnail again in
the grid**, so the upper cell never had a competing tap. It is now the same gesture as tapping a
pilot face in-game to open details. The name cell stays a plain Label.

**The 15 mob pilots (모브 파일럿) do not appear in the grid.** `pilot_skills.csv` has only 25
entries, so 15 of the 40 have no unique skill (`players.is_mob = 1`), and their portraits are
silhouette (실루엣) cut-ins of "nameless players" — they are not draft targets but background
filling AI team head counts, and you still meet them as enemies. `get_pool_grid()` is the only
place that filter lives.

**All five seats of team 0 (the player's starting team) are named pilots.** `apply_draft`'s swap
must only happen between named pilots so per-team named counts are not shaken by the draft — of the
25 named pilots, 5 are on team 0 and the other 20 are spread 2–3 each over the 7 AI teams
(`data/csv/players.csv`).

## Files
| File | Role |
|---|---|
| `TeamDraft.gd`        | `class_name TeamDraft extends Control` — data layer. Owns `validate_draft()`, `apply_draft()`, `get_pool_grid()`, and two tables the screen also reads — **slot order** (`SLOT_ROLES` / `SLOT_NAMES` / `slot_of_role`), **skill lookup** (`skill_def_for` / `skill_type_label`). The four card candidate-pool helpers were deleted — see the section below. Builds `TeamDraftView` lazily via `ensure_view()` (called by `SeasonHub` after `init_season`). |
| `TeamDraftView.gd`    | `class_name TeamDraftView extends Control` — procedural UI (5-pick illustration row + filter row + scrolling thumbnail grid + bottom skill panel/confirm button). Lives as a child of the `TeamDraft` node. |
| `PilotThumb.gd`       | `class_name PilotThumb extends Button` — one grid cell. **Square (200×200), and a single face crop plus a top-left role-class badge is all it has.** When selected: gold border + top-right check badge. Emits `thumb_tapped(pilot_id)`. Two static helpers shared with the top illustrations — `add_rounded_art` (**rounded-rectangle mask**: a `Panel` drawing a rounded `StyleBoxFlat` + `clip_children = CLIP_CHILDREN_ONLY`. The mask radius is the cell radius minus the inner padding, so the curve is concentric with the border — `clip_contents` only clips to a rectangle) · `add_role_badge`. |
| `DraftDetailPanel.gd` | `class_name DraftDetailPanel extends CanvasLayer` — **pilot detail popup**. Left full-body art / right scrolling info panel (6 stat chips → pilot skill. **The backing height is set by the content**). `open(p: PlayerData)` **takes just one argument** — see the "Shared by two screens" section below. |

`PilotCard.gd` / `PilotCard.tscn` were **deleted** — the old grid card that stacked five stat bars
in a 200×175 cell; `PilotThumb` replaces it.

## The five slots are role-fixed
Slot order is not the enum order of `GameEnums.Role` but **MOBA lane order** —
탑 Top (TANK) · 정글 Jungle (ASSASSIN) · 미드 Mid (FIGHTER) · 원딜 ADC (SNIPER) · 서폿 Support (SUPPORT),
in the single table `TeamDraft.SLOT_ROLES`. Using enum order as-is seats the jungler third and the
support fourth, which doesn't match the lineup players know
(the in-game pilot strip (스트립) keeps its own `HudBuilder.LANE_SEAT_ORDER` for the same reason).

**The filter buttons and the five upper slots read the same table**, so their order can't diverge —
filter `i = 0` is "전체" (All) (-1), followed by `SLOT_ROLES[i - 1]`.

Free order (first-come 5 slots) wasn't used because `validate_draft` enforces "exactly 1 per role".
With free order the screen would allow combinations that are first rejected at the confirm
button — rules should be visible while picking.

## DraftDetailPanel — shared by two screens
This popup is **the only place in the outgame to inspect a single pilot**. It opens from two
places — this screen (the upper-body illustration of a picked slot) and **the assignment step of
ban/pick** (both teams' pilot portraits (초상화), `features/match_flow/ban_pick/`). So it does not
require a `TeamDraft` instance: all it needs is one `PlayerData` and the `GameManager` autoload.

That escape **deleted** `TeamDraft.skill_def_for` — with the bottom skill panel gone, the popup
became the only consumer, and the popup reads `GameManager.skill_def()` directly.
The same escape had made `candidate_cards_for_role` **static** taking the card pool as an argument,
but the candidate-card section itself was removed and that function went with it — see below.

## Upper-body illustration (shoulders–face) — `PilotImages.bust_for`
Uses an `AtlasTexture` crop of the **upper part** of `tall/N_tall.png` (210×700, head–thigh)
(`PilotImages.BUST_REGION` = `Rect2(18, 0, 174, 351)`). The point is not cropping directly from the
`full` art — full art has a different figure scale per pilot, making the five faces vary in size,
whereas `tall` is a cut whose scale was already unified by finding the face rectangle via template
matching, so cropping from it makes the five faces the same size
(see `resources/images/pilot/make_tall_crops.py`).

**The crop moved to `PilotImages`** (formerly `TeamDraftView.BUST_REGION`) — once the ban/pick
assignment step started using the same crop, two screens each holding their own `Rect2` would mean
fixing just one makes the face sizes diverge.

The region ratio (174 : 351 = `PilotImages.BUST_ASPECT` 0.496) matches the cell ratio (204 : 412 =
0.495), so there is no stretching — change only one of them and faces get squashed.

## 3 pilot cards — fixed per player, so shown again
At the very bottom of the detail popup is a **"파일럿 카드"** (Pilot cards) section
(`DraftDetailPanel._build_pilot_cards`). It stacks that player's fixed 3 cards
(`GameManager.pilot_card_ids_for(pd)`) top-down as description boxes
(`CardDescBox.build(cd, w, light = true)`) — name · cost · keyword line · description · keyword
glossary all fit on one box, so no grid of card nodes is needed.

**This section is now a basis for decisions.** Back when pilot cards were sampled at match start,
all the draft could show was the per-role **candidate pool**, and that list was identical for
anyone picked in the same role, so the whole section was removed. Now cards are fixed per player
(`players.pilot_cards`; if empty, a draw seeded by the player id), so the 3 cards seen here are
exactly the 3 you hold in-game, and they differ per player even within the same role.

What was deleted back then — `DraftDetailPanel`'s `_build_card_sections` / `_cards_in_cat` /
`_build_card_grid`, and `TeamDraft`'s four candidate-pool helpers (`pilot_card_slots_for_role` /
`candidate_cards_for_role` / `slot_summary_for_role` / `cat_label`) — is not revived. The single
source of cards is `GameManager.pilot_card_ids_for`.

**The backing height now follows the content.** When the card grid existed, the right panel was
always full, so a fixed `PANEL_TOP` ~ `PANEL_BOTTOM` sufficed; with only stat chips and one skill
paragraph left, the bottom half became an empty white board. Now only the top is pinned and the
bottom edge rises to fit the content (if it overflows it stops at `PANEL_BOTTOM` and scrolling takes
over from there), and **the close button follows that bottom edge** — the same rule as the in-game
detail panel's `_reposition_close`.

## UI flow
1. `SeasonHub._show_draft()` calls `TeamDraft.ensure_view()` then sets `TeamDraft.visible = true`.
2. `TeamDraftView` instantiates one `PilotThumb` per pool entry, laid out 5 columns wide inside a `ScrollContainer`. Grid order is overall stat descending within slot order. Mobs were already filtered out by `get_pool_grid()`.
3. The filter buttons (전체/탑/정글/미드/원딜/서폿 = All/Top/Jungle/Mid/ADC/Support) run `_reflow_grid()` — **only visible cells get re-positioned**. Leaving hidden cells in place and just turning off `visible` leaves holes that break the 5-column layout.
4. Tapping a thumbnail seats that pilot in **their own role's slot**. Tapping the same person in the same slot again empties it; tapping someone else replaces.
5. Tapping the **upper-body illustration** of a filled slot opens `DraftDetailPanel`. That slot is a `Button` and **must not be `flat`** — a flat button ignores the stylebox entirely, so an empty slot's border and background vanish and only the "선택 없음" (None selected) text floats in mid-air (measured).
6. **"다음"** (Next) is enabled only when all five slots are filled; pressing it moves to CONFIRM mode (the pick pane disappears and the 5 picks drop to the centre). "뒤로" (Back) does the reverse.
7. **"드래프트 확정"** (Confirm draft) re-sorts `_picks` into **role order** (`GameEnums.Role`) before passing them to `apply_draft()` — `validate_draft` ignores order, but passing the screen's slot order straight through would make what this list is ordered by differ per call site.
8. Confirm → `TeamDraft.apply_draft()` rewires team rosters → **`_detail.close()`** → `SeasonHub.goto(Screen.HUB)`. The popup is a `CanvasLayer`, so it doesn't follow the parent Control's `visible` — moving on with it open leaves the dim on screen.

## Layout (1080×1920 portrait)
**Stacked bottom to top** — the grid hangs from the bottom bar (`grid_y()`), and the filter
(`filter_y()`) and 5 picks (`pick_row_y()`) sit above it in turn. The grid is **3.5 rows of
thumbnails** (`GRID_VISIBLE_ROWS`, height 724) and the 5 picks came down by as much as it shrank —
the half-cut row itself says "there is more below".

`_slot_row` is **just the one row of illustrations** (204×412 button ×5, gap 12, x0 = 6). The image
is inset inside the role-colour border (3px), trimmed by the rounded mask, with the role-class badge
at top left.

Screen coordinates (safe inset 0 · 9:16 measured):

| Y range     | Block |
|---|---|
| 520..932    | `_slot_row` (PICK mode) — `filter_y() − 32 − 412` |
| 964..1028   | 6 filter buttons (x0 24, total width 1032) |
| 1056..1780  | Thumbnail grid backplate + `ScrollContainer` (5 cols × `PilotThumb` 200×200, 3.5 rows) |
| Bottom bar  | PICK = "다음" full width. CONFIRM = "뒤로" (1) + "게임 시작" (2) |
| **754..1166** | CONFIRM mode `_slot_row` — screen vertical centre (`confirm_row_y()`) |

Every y is derived back from `OutgameTheme.bottom_bar_top()`, not a constant — the bottom buttons
are the lowest touch targets on this screen and border the home indicator / gesture bar.

The detail popup (`DraftDetailPanel`) stands on its own `CanvasLayer` (layer 20):
left full-body art (height 1400, bottom edge 2010, centre x 300) / right info panel
(x 596, w 460, y 150..1740, inside is a `ScrollContainer`) / close (1756..1840).
The close button **requires an opaque style** — that spot overlaps the draft screen's "드래프트
확정" button, and the default Button theme is translucent, so that text showed through under the
dim and the two labels read as overlapping in one cell.

---

## Grid scrolling — `DragScroll`

The grid is **scrolled by `DragScroll`** (`resources/DragScroll.gd`). The engine's touch drag did
not scroll at all with a desktop mouse, and on phones it got tangled with taps on thumbnails,
leading to "it doesn't scroll" reports. `DragScroll` takes mouse and touch through the same path,
judges a scroll once a 14px threshold is crossed, and **at that moment cancels the press on the
thumbnail that was held** — a hand meaning to scroll doesn't pick a pilot. The thumbnails'
`MOUSE_FILTER_PASS` is still required (the press must reach the scroll for the judgement to start).
The detail popup's info scroll works the same way.
