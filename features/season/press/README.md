# Press conference (기자회견) (press)

A **messenger screen** that opens once right before the week starts. `Screen.PRESS` in `SeasonHub`.

```
HubView "이번 주 시작 →"  →  PRESS  →  (pick an answer)  →  TRAINING
```

("이번 주 시작 →" = Start this week.)

| File | Role |
|---|---|
| `PressConferenceView.gd` | `class_name PressConferenceView extends Control` — the screen: draws this week's `MentalSystem.press_session` in a `MessengerView`, applies the answer with `MentalSystem.resolve_press`, then `SeasonHub.on_press_finished()` |
| `PressConferenceView.tscn` | The screen scene: root (theme `OutgameTheme.tres`, PASS) + one `MessengerView.tscn` instance `%Messenger` whose `outcome_hint` is set in the scene (`화면을 눌러 계속`). Created by `SeasonHub` with `PressConferenceView.create()` |
| `MessengerView.gd` | `class_name MessengerView extends Control` — **shared messenger dialogue** (press conference here; interview / outing / incident overlays on the week screen). Create with `MessengerView.create()` (`.new()` is an empty Control). API: `open(sub, title, portrait, lines, choices)` → signal `choice_picked(idx)` → `show_result(outcome)` / `show_outcome(reply_lines, notes, verdict)` → signal `closed`. `reveal_all()` shows every remaining line + the choices at once (previews / harnesses). `@export outcome_hint` = bottom hint after the outcome. Line grammar: plain = left speaker, `>text` = manager (right), `*text` = narration (see `features/season/mental/README.md`). |
| `MessengerView.tscn` | The **frame** (below): header, scroll, `%Log` column, `%Answers` block, hint |
| `MessengerNpcBubble.tscn` / `.gd` | Item — one line of the other side (left): portrait slot (`%Portrait` + `%Glyph`), tail (`%Wedge`), white bubble (`%Bubble` → `Pad` → `%Text`). `create()` + `setup(text, portrait, with_portrait)` — follow-up lines hide portrait + tail but keep their columns |
| `MessengerPlayerBubble.tscn` / `.gd` | Item — one manager line (right): amber `%Bubble` + tail. `create()` + `setup(text)` |
| `MessengerNarration.tscn` | Item (no script) — centred `*narration` line; code sets `%Text` |
| `MessengerNoteChip.tscn` / `.gd` | Item — centred effect / verdict pill. `create()` + `setup(text, good)`; scene = good look (`AccentChip` + `AccentLabel`), bad = `variation_box("AccentChip")` copy with `SURFACE_SUNK` + `CaptionLabel` |
| `MessengerAnswerButton.tscn` | Item (no script) — one answer choice (`GhostButton` 26, 640 wide, ≥ 96 tall, right-aligned, autowrap); code sets text + `pressed` |
| `MessengerWedge.gd` | `@tool` `_draw` widget — bubble tail. `@export point_left`, `@export_node_path bubble` (tail colour = that bubble's `panel` stylebox fill); the base overlaps the bubble by `OVERLAP` 1 px |
| `MessengerReporterGlyph.gd` | `@tool` `_draw` widget — reporter microphone placeholder over the portrait slot (no portrait texture) |

**F6 preview** — both scenes fill dummy data when run alone (`resources/UiPreview.gd`), all lines revealed
at once with `MessengerView.reveal_all()` (preview / harness API) so the answers show:
`PressConferenceView` = this week's real question of an in-memory run; `MessengerView` = a hand-written
conference (reporter · narration · manager lines, three answers; picking one shows sample result chips).
The item scenes preview alone too: `MessengerNpcBubble` (mic portrait + 3-line bubble), `MessengerPlayerBubble`
(2-line answer), `MessengerNoteChip` (failed-check chip); the script-less items show their baked sample text.

### `MessengerView.tscn` — what the scene owns / what code owns

```
MessengerView (Control, full rect, STOP, theme OutgameTheme.tres)
├ %Background   Panel "ScreenBackground", full rect — code: ScreenMetrics.extend_background (notch band)
└ %SafeArea     full rect — code: offset_bottom = −bottom inset (bottom edge = safe_h())
  ├ %Sub        CaptionLabel 24, clip            y 36
  ├ %Title      HeadingLabel                      y 72
  ├ Divider     HSeparator "Divider"              y 160
  ├ %Scroll     ScrollContainer PASS, y 190 → bottom −64, anchors_preset −1 (grows right only)
  │ └ %Body     VBox PASS, separation 0, min width 1080 (code: = viewport width)
  │   ├ %Log    VBox separation 0 — code appends item scenes (one per line, each owns its gap below)
  │   └ %Answers  MarginContainer (top 10 · right 40 · bottom 14), hidden unless choosing
  │     └ %AnswerList  VBox separation 14 — code adds MessengerAnswerButtons
  └ %Hint       FaintLabel, centred, bottom −50 … −22 (grows down to its 31 px min height)
```

* **Scene** (frame + item scenes): positions, margins, bubble widths (NPC 700 · manager 640 · answers 640),
  paddings (26 / 20), gaps (bubble 18, note 10, answers 14), fonts (variations), sample texts.
  **Heights come from the containers** (wrapped text), no pixel maths.
  **Code**: device insets, which item to append per line, the tap state machine, `DragScroll.attach(%Scroll)`,
  the round portrait (`OutgameTheme.add_round_portrait` into `%Portrait`), the failed-note tint.
* Item layout (1080 wide): NPC = margin left 40 · portrait column 96 · gap 8 · tail column 18
  (margin top 26) · bubble 700 → bubble x 162, tail drawn from x 145. Manager = row aligned right,
  margin right 22 · tail column 18 (margin top 24) → bubble 400 … 1040, tail from 1039.
  Tail columns are `z_index` 1 so the tail covers the bubble border where they join.
* **Bubble looks are stand-ins** until the messenger variations exist in `OutgameTheme`:
  NPC bubble `SelectableCard` (r18, 2 px border; was r22, 1 px), manager bubble `ProgressFill`
  (r7; was r22). Both have no padding — the `Pad` MarginContainer holds it, so swapping in
  the dedicated variations is a name change only.
* `%Scroll` and `%Hint` use `anchors_preset = -1` on purpose: a preset re-applies its grow
  directions on load, so the overflowing log would shift left by half the scroll bar and the
  hint (min height 31 > 28) would grow upward. Keep them custom when editing.

## Screen

```
프리시즌 · 3주차 · e스포츠 데일리 기자
기자회견
────────────────────────────────────────
 (○) ◀ 주말 경기 상대가 만만치 않다는 평이 많습니다.
     ◀ 솔직히, 이길 자신 있으십니까?

                        저희 선수들을 믿습니다. ▶
                  쉽지 않겠지만 준비한 게 있습니다. ▶
                       질문이 좀 무례하시네요. ▶
                    화면을 눌러 계속
```

(Mockup uses the in-game Korean text: header "Preseason · Week 3 · e-sports Daily reporter" /
"Press conference"; reporter: "Many say your weekend opponent is tough. / Honestly, are you
confident you'll win?"; answers: "I trust our players." / "It won't be easy, but we have
something prepared." / "That question is a bit rude."; hint "Tap the screen to continue".)

* **Left = reporter.** Round portrait (초상화) (`OutgameTheme.add_round_portrait`) + a white speech
  bubble with a **wedge** pointing at that portrait. From the second consecutive line by the same
  reporter on, the portrait and wedge are not repeated.
* **Right = player.** Amber fill + white text; the wedge points right.
* Reporter lines appear **one at a time**. Tapping anywhere on the screen appends the next line
  (bottom hint is `화면을 눌러 계속` (Tap the screen to continue)); once all are shown, the answer
  choices appear at bottom right (`답변을 고르세요` (Choose an answer)).
* Picking one appends that answer as a player bubble, applies it (`MentalSystem.resolve_press`),
  and shows the effects as centred chips (plus a `멘탈 판정 성공 / 실패` chip when the entry rolls a
  check). The hint becomes `화면을 눌러 계속`; the next tap goes to the training plan via
  `SeasonHub.on_press_finished()` — the player must be able to read what the answer did.

## Data (M7)

Questions are `mental_events.csv` rows of kind `press` (grammar: `features/season/mental/README.md`).
The `@` line is the outlet shown in the header (`… · <outlet> 기자`). One question per week,
drawn by `MentalSystem.press_session` (seeded per run + week, kept in `season_state.mental.press`) —
reopening the screen in the same week shows the same question and a second answer is not applied.
Generic questions move whole-team trust (`trust_all`) or add a temporary manager-stat mod (`smod`);
`mention=mvp|worst` questions name a pilot from the last own match and move that pilot's trust.

Reporter portrait: still the microphone drawn by `MessengerReporterGlyph` (`%Glyph` in `MessengerNpcBubble`) (passed as
`portrait = null`). When reporter art exists, pass the texture to `open()`.

## Implementation notes (all in `MessengerView`)

* **The bubble tail is a dedicated childless `_draw` widget** (`MessengerWedge`) in its own column
  next to the bubble, not inside it — a Control's `_draw` runs **before** its children (inside the
  bubble it would be under the text), and a container would lay it out over the text.
* **Taps are received by the screen itself (`gui_input`), but on *release*, not on press.**
  The `DragScroll` that `OutgameTheme.add_vscroll` attaches swallows **presses** inside the scroll
  with `accept_event()` (so it doesn't double up with the engine's touch drag). Back when it reacted
  to presses, taps over the whole bubble area therefore never reached the screen, and **reporter
  lines stopped at the first line** (measured: before the fix, two taps gave `_shown` 1 → 1; after
  the fix 1 → 2 → answers). Releases are not swallowed, so they bubble up the **parent chain** from
  the scroll that holds mouse focus — hence the scroll and the board must be `MOUSE_FILTER_PASS`
  (with STOP the chain breaks there), and drag-scroll gestures are filtered out via `_drag.moved`
  so they don't count as taps. Presses outside the scroll (header) come straight to the screen, so
  they are flagged with `_press_outside_scroll` to avoid reading the previous scroll's `moved` value.
  A tap board laid down as a sibling is useless — input propagates only upward, never sideways.
  Answer `Button`s still fire their own `pressed` even when lowered to PASS (by `DragScroll`'s
  sweep) — **but because they are PASS, that same release then bubbles on to the view's
  `gui_input`.** Taken as a tap it would close the outcome in the same instant (measured with
  injected clicks: the overlay was freed by the answer tap). `_picked_frame` ignores taps from the
  frame the answer was picked in.
* **The view is a scene whose root is saved full-rect** (anchors 0..1, offsets 0). It used to be
  built with `.new()`, where `set_anchors_preset` alone kept the 0×0 rect — the background never
  painted and the STOP hit area was empty (measured: the week overlay showed the week screen
  through it). `MessengerView.create()` gives the full rect from the scene; never `.new()` it.
* The root is `MOUSE_FILTER_STOP`, so a copy laid over another screen (the week screen's
  interview / incident overlay) blocks everything underneath, including that screen's bottom bar.
* Line heights come from the containers (autowrapped `Label` in fixed-width bubbles). Scroll to the
  bottom waits one frame (the new item is laid out at the end of the frame) and sets the scroll to
  the bar's `max_value` (clamped to the end). A standalone item root (F6) first grows to the height
  of its text at width 0 and does not shrink — the bubble previews `reset_size()` a frame later.
* `PressConferenceView.ensure_view()` re-opens the messenger every time (`_restart`) with this
  week's session. `_built` guards only the skeleton.
* The messenger never indents itself — the owning screen calls `ScreenMetrics.indent_to_safe_top`;
  the messenger's `%Background` is extended into the notch band (`ScreenMetrics.extend_background`)
  and `%SafeArea` ends on the safe bottom, so the bottom hint sits at `safe_h() - 50`. All colours
  come from `OutgameTheme` variations (code only for the failed-note tint copy).
