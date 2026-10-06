# Press conference (기자회견) (press)

A **messenger screen** that opens once right before the week starts. `Screen.PRESS` in `SeasonHub`.

```
HubView "이번 주 시작 →"  →  PRESS  →  (pick an answer)  →  TRAINING
```

("이번 주 시작 →" = Start this week.)

| File | Role |
|---|---|
| `PressConferenceView.gd` | `class_name PressConferenceView extends Control` — the whole screen |

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
* Picking one appends that answer as a player bubble and **0.7 s later** goes to the training plan
  screen via `SeasonHub.on_press_finished()`. Moving on immediately would make the just-picked
  answer vanish before it ever shows on screen.

## Currently only a skeleton

Lines · choices are placeholder data hard-coded in `_SCRIPT_POOL`, and the rule for choosing a
script is just `phase_week % pool size`. Answers change no state
(`_on_answer_picked` only `print`s the chosen index).

Three places to hook in:

1. **Line pool as a table** — create a table such as `data/csv/press_lines.csv` and choose by
   phase · standing · last match result.
2. **Answer effects** — move state such as team morale / player condition / reputation.
   `_on_answer_picked(idx, text)` is the entry point.
3. **Reporter portrait** — currently a microphone shape drawn by `_draw_reporter_glyph`.
   When real art exists, pass it as the second argument of `add_round_portrait` and delete just
   that one child `Control`.

## Implementation notes

* **The bubble tail is drawn by a dedicated `Control` with no children** (`_add_wedge`).
  A Control's `_draw` runs **before** its children, so putting it inside the bubble `Panel` would
  put it under the text.
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
  sweep), and while answers are showing, `_show_answers` ignores screen taps.
* The height of wrapped text is not measured by standing up a `Label`; **the font is asked
  directly** (`_text_block_height`) — a label just created for measuring has size 0 in that frame.
* `ensure_view()` **opens a fresh conference every time** (`_restart`). `_built` guards only the
  skeleton — the same conference must not appear to carry over from week to week.
* All colours come from `OutgameTheme`; layout uses `ScreenMetrics.indent_to_safe_top` +
  `OutgameTheme.add_background` (which internally calls `extend_background`).
