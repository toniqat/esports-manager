# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | 전략 포인트 ring gauge; the player's one doubles as the 턴 넘기기 button |
| `PilotStrip.gd` | PilotStrip | 파일럿 5인 스트립 — 눈높이 초상화 + 체력 바 + 성장치. 상단(적) / 하단(아군) 두 벌 |
| `PilotDetailPanel.gd` | PilotDetailPanel | 파일럿 상세 모달 — 좌 전신 아트 / 우 아웃게임·인게임·메크 스탯 |

## HudBuilder.gd
`extends Node` — child of BattleSim.

Builds the battle HUD and updates it via `update_hud()` (per-turn) and
`update_time_label()` (every frame from `BattleSim._process`).

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
- **Top panel** (y=0, h=130) — 시간 · 팀 점수 한 줄 + 그 아래 **적 파일럿
  스트립**. Has an explicit opaque dark `StyleBoxFlat` so the AI hand peek
  behind it stays visually clipped regardless of theme. 아군 스트립은 여기가
  아니라 핸드 행 아래에 있다 — 아래 파일럿 스트립 절 참고.
- **Hand indicators** (in the gutters either side of the card row) —
  `lbl_deck_count` (left, "Deck\n10") and `lbl_discard_count` (right,
  "Discard\n0"). CardPhaseManager updates the text on every draw / play and
  tweens the counts during a deck/discard reshuffle. Built by
  `_build_hand_indicators()`. **Both counters are also buttons**: a transparent
  flat `Button` (`_make_pile_button`) covers each label — a `Label` is
  `MOUSE_FILTER_IGNORE` by class default and takes no clicks of its own — and
  opens `CardPileViewer` on that pile. `_update_pile_buttons()` runs from
  `update_hud()` and gates both on `CardPhaseManager.can_browse_piles()`
  (작전 단계 only), fading the labels to `PILE_LABEL_DIM_ALPHA` while disabled.
  See `card_phase/README.md` → Deck / Discard 목록 열람. The gutter is
  **not** `BS_HAND_AREA_MARGIN` —
  `BS_HAND_WIDTH_SCALE` widens the card row past it, so the gutter is derived
  as `min(BS_HAND_AREA_MARGIN, (screen_w − BS_HAND_WIDTH) / 2)` (89px at 1080)
  and the font shrinks with it (22 → 20) so "Discard" still fits and no card
  ever overlaps a label.
- **전략 포인트 도넛 ×2** — `CostDonut` ring gauges in the **left-hand** gutter
  (see below). Built by `_build_cost_donuts()`.
- **아군 파일럿 스트립** (y 1766..1888) — 핸드 행 아래. 예전에는 여기가 비어
  있었다(하단 코스트 바와 사각 단계 넘기기 버튼이 사라진 자리). 바닥 ~32px 는
  아이폰 홈 바 / 시스템 제스처용으로 남긴다. `_build_player_strip()`.
- **Victory panel** — Win/lose label + Play Again button.
- **Turn announcer** (built last, full-screen Control overlay) —
  `play_turn_announce(is_player)` sweeps a 110-px-tall coloured bar in
  from the centre with the message "당신의 차례" (blue) or "상대 차례"
  (red), holds, then fades out. Awaitable; `CardPhaseManager.start_card_phase`
  blocks the player hand on the player banner, and
  `CardPhaseManager._run_ai_turn` runs the enemy banner **when the AI's own
  작전 점수 reaches `PHASE_THRESHOLD`** — not when the player passes the turn.
  Passing the turn (`end_card_phase`) shows no banner at all. The on-screen
  battle log was removed; `_bs.last_log` is still updated by effect handlers
  but renders nowhere.

Buttons removed: **Next Turn**, **Auto Play** and the rectangular
**단계 넘기기** button are all gone — BATTLE auto-ticks every
`AUTO_PLAY_INTERVAL` (0.5s) inside `BattleSim._process()`, and ending the
작전 단계 is now done by tapping the player's 전략 포인트 donut twice.

Connections:
- `cost_donut.end_turn_pressed` → `_bs.card_phase.end_card_phase` (the manager
  also re-checks `can_end_card_phase()` defensively)
- Play Again button → `_bs._on_restart_pressed`

### 전략 포인트 도넛 (`CostDonut.gd`)
Both sides' 작전 점수 read out on a ring gauge in the **left-hand** gutter
(`x = BS_HAND_AREA_MARGIN / 2`, i.e. 65 on a 1080-wide screen). The donut column
and the targeting overlay's 확인 / 취소 row sit on **opposite** sides of the
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

- Ring is full at `PHASE_THRESHOLD` (8); the number in the middle is the raw
  point total, so boost cards read as "9 on a full ring".
- Fill sweeps clockwise from 12 o'clock (`START_ANGLE = -PI/2`).

**Player flip → 턴 넘기기** (`CostDonut` owns the whole interaction):
1. tap the donut during 작전 단계 → the ring unwinds through empty and
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
`set_end_enabled(can_end_card_phase())` — **작전 단계 내내 true** 이고, 배너 /
모달 / 돌진 연출처럼 지금 닫으면 무언가가 끊기는 상태에서만 false 다. 카드를
한 장도 내지 않고 넘겨도 된다(see `card_phase/README.md`). `set_locked(…)`
`set_flip_allowed(in_card_phase and not card_pile_viewer.is_active())` (turning
it off un-flips — the pile-viewer clause is load-bearing because `CostDonut`
listens on `_input`, which runs ahead of GUI picking and would otherwise be
still exists on `CostDonut` but **nothing calls it any more** — targeting stopped
being modal, so there is no state that needs the flip blocked. The donut's y is
still derived from `CardTargetingOverlay.BTN_HAND_GAP + BTN_H` so it keeps the
same vertical band the 확인/취소 row occupies on the far side of the screen.

### 파일럿 스트립 (`PilotStrip.gd`) — 상단 적 / 하단 아군
예전에는 열 명이 **전부 상단 패널 안에** 84px 슬롯으로 몰려 있었다(아군 좌 /
점수 중앙 / 적 우). 얼굴이 76px 정사각이라 누가 누구인지 읽히지 않았고, 두 팀이
같은 줄에 붙어 있어 어느 쪽이 내 팀인지도 한눈에 안 들어왔다. 지금은 두 벌로
갈라져 있다:

| 스트립 | 위치 | 크기 | 입력 |
|---|---|---|---|
| 적 (`_enemy_strip`) | 상단 패널의 자식, `ENEMY_STRIP_RECT`(175, 42, 730×84) | 초상화 130×54 | 없음 |
| 아군 (`_player_strip`) | 핸드 행 **아래**, `PLAYER_STRIP_RECT`(25, 1766, 1030×122) | 초상화 190×79 | 눌러서 상세 패널 |

한 칸의 구성은 위에서 아래로 **눈높이 초상화 → 체력 바 → 성장치 숫자**다.

- **눈높이 초상화** — `PilotImages.eye_for(pilot_id)`. `eye/N_eye.png` 는
  **양 눈이 보이게 가로로 길게 자른 480×200 크롭**이고, 칸 높이는 그 비율
  (`EYE_ASPECT` = 2.4)에서 유도한다 — 임의 높이로 늘리면 얼굴이 찌그러진다.
  이미지가 없으면(단독 실행 / INTL) 뒤판 `ColorRect` 가 그대로 보인다.
  테두리는 팀색 `Panel` 프레임이고, 쓰러진 파일럿은 `modulate` 로 어두워지며
  **부활까지 남은 턴 수**가 초상화 한가운데 큰 폰트로 찍힌다.
- **역할 태그** — 초상화 좌하단. **어두운 받침(`tag_bg`) 위에** 흰 글자 +
  검은 외곽선이다. 외곽선만으로는 검은 머리카락 위에서 한 글자 태그(T / F)가
  거의 보이지 않았다.
- **체력 바** — **`ColorRect` 두 장**(뒤판 + 채움)이다. **`ProgressBar` 를 쓰면
  안 된다**: 테마 스타일박스의 컨텐트 마진에서 최소 크기를 계산해 `size` 를
  거기까지 끌어올리므로(기본 테마 약 24px), 6~10px 짜리 바를 요청해도 24px 로
  그려져 바로 아래의 성장치 라벨을 덮어썼다(실측 확인). 보호막이 붙어 있으면
  채움이 노란색으로 바뀐다 — 바를 이어 붙이지 않는 이유는 6~10px 로 얇아 두
  구간이 구분되지 않아서다.
- **성장치** — `BattleSim.fmt_score(p.score)` → `"1.00k"`. **게이지가 아니라
  숫자다** — 상한이 없어 채울 바탕이 없다. 적립 규칙은 `BattleSim` 의 `SCORE_*`
  절 참고.

칸은 `LanePosition`(LEFT → CENTER → RIGHT → GUERRILLA) 순으로 정렬된다.
정렬은 **`_bs.pilots` 의 사본에** 한다 — 원본은 스폰 순서(= 역할 순서)를
유지해야 `BattleSim.player_data_for` 가 그 인덱스로 로스터를 찾을 수 있다.

**하단 스트립의 y(1766)는 카드 밑단에서 계산해 나온 값이다.** 부채꼴의 양 끝
카드는 가운데보다 21.4px 아래로 처지고(12장 기준) 호버/선택 시
`Card.HOVER_SCALE`(1.2)로 커지므로 최악의 경우 카드 밑단이 y ≈ 1763 까지
내려온다. 1724 에 두었더니 카드가 초상화 윗부분을 덮었다(실측 확인).

**입력 게이트**: `set_interactive_enabled(in_card_phase)` — 자기 작전 단계가
아니면 히트 버튼이 `disabled` 다. 히트 판정은 칸 전체를 덮는 투명 `Button` 이
가져간다(`Label` / `TextureRect` 는 클래스 기본이 `MOUSE_FILTER_IGNORE` 라
스스로 클릭을 받지 못한다).

### 파일럿 상세 패널 (`PilotDetailPanel.gd`)
하단 아군 스트립의 얼굴을 누르면 열리는 **모달**. 자기 `CanvasLayer`(13)에
그리므로 버리기(10) / 대상 지정(11) / 열람·교전(12) 위다.

```
[풀스크린 딤 α 0.88]
├─ 좌: 전신 아트  ART_RECT(24, 196, 610×900)
├─ 우: 스탯 3절   STAT_X 656, STAT_W 400
│    인게임 — 체력 / 공격력(기본 대비) / 성장 / 명중·회피 / 보호막 / 라인
│    파일럿 — 라인전 · 메카닉 · 게임센스 · 한타 · 멘탈 (PlayerData)
│    메크   — 기체명 / 체력 / 공격력 / 존재감 (MechData; speed 는 삭제됨)
└─ 하: 닫기 버튼 (y 1620)
```

- **전신 아트는 무릎 언저리에서 자른다.** `_knee_crop` 이 `Image.get_used_rect()`
  으로 **불투명 영역(= 캐릭터 실루엣)** 을 재고 그 높이의 `KNEE_FRACTION`(0.80)
  까지만 `AtlasTexture.region` 으로 남긴다(이미지를 새로 만들지 않는다).
  고정 픽셀로 자르면 인물 크기와 여백이 이미지마다 달라 누구는 허리에서,
  누구는 발목에서 잘린다. 40장 실측 결과 0.80 은 **무릎~발목 사이**에 떨어지고,
  소품(무기 · 떠 있는 오브젝트)이 실루엣을 넓히는 파일럿은 전신이 다 들어온다 —
  "이미지마다 다르다"가 의도된 동작이다.
- `stretch_mode` 는 **`STRETCH_KEEP_ASPECT`**(좌상단 정렬)다. `CENTERED` 는 칸이
  아트보다 세로로 길어서 인물이 칸 한가운데로 내려앉아 위아래로 빈칸이 생기고,
  `COVERED` 는 칸을 채우느라 좌우를 잘라 팔이 사라진다.
- **값 라벨에는 `clip_text = true` 가 필수다.** 오른쪽 정렬 `Label` 은 글자가
  rect 보다 넓으면 정렬을 포기하고 rect 왼쪽부터 그려서 **오른쪽으로 넘쳐 화면을
  벗어난다**(실측: "아웃게임 데이터 없음" 이 화면 밖에서 잘렸다).
- 아웃게임 스탯은 `BattleSim.player_data_for(pilot)` 로 찾는다 — `pilots` 배열의
  인덱스(0..4 = 팀0, 5..9 = 팀1)를 `match_ctx` 의 두 로스터에 그대로 대응시키는
  방식이라 **`pilots` 를 재정렬하면 이름과 스탯이 어긋난다**. 단독 실행이나
  INTL 파일럿은 null → "데이터 없음".
- 열려 있는 동안 **아군 스트립은 숨긴다**(`HudBuilder.set_player_strip_visible`).
  딤 위로 스트립만 남으면 지금 무엇을 보고 있는지가 흐려지고, 딤 아래로 넣으면
  방금 누른 얼굴이 어두워져 연결이 끊긴다.
- **작전 단계를 벗어나면 강제로 닫힌다**(`close_if_phase_left`, `update_hud`
  마다 호출). 열어 둔 채 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.

### 상단 패널 (시간 + 팀 점수 + 적 스트립)
`TOP_PANEL_Y` 0 / `TOP_PANEL_H` **130**. 높이는 협상 불가에 가깝다: 이 패널이
상대 핸드 peek 의 윗부분을 가리는 가림막이고, peek 카드 아래 끝(y 179)에서
`DONUT_AI_HAND_GAP` 만큼 띄운 자리가 적 도넛(아래 끝 y 311)이며, 그 바로 아래가
전장 픽셀 상단(y **369** — 전장이 90%로 줄기 전에는 314였다)이다. 패널을 키우면
그 사슬이 통째로 밀려 도넛이 전장을 덮는다. 그 사이의 빈 띠(y 142~292)를
**카드 설명 상자**가 쓴다 — `CardPhaseManager.DESC_BOX_TOP`.

- **시간 라벨** — 좌측(x 20), `font_size` 18. `MM:SS` (`get_elapsed_ingame_seconds`).
  **시는 표시하지 않으므로 분이 60을 넘을 수 있다.** BATTLE 중에는 실시간으로
  초가 흐르고(1턴 = 0.5초 = 인게임 60초, 즉 벽시계의 약 120배), CARD_PHASE /
  게임오버에는 멈춘다.
- **팀 점수** — 가운데, `font_size` 26. `팀0 합산 - 팀1 합산`
  (`BattleSim.team_score`). 5명 × 1.00k 로 시작하므로 개시값은 `5.00k - 5.00k`.
  죽어 있는 파일럿의 점수도 합산에 들어간다(점수는 전장에 서 있는지와 무관한
  누적 기록이다).

### update_hud() (per-turn)
- Calls `_update_cost_donuts(in_card_phase)` — pushes both sides' 작전 점수
  into their ring gauges and gates the player donut's flip / 턴 넘기기 press
  on `game_phase == CARD_PHASE` and `card_phase.can_end_card_phase()`.
- Calls `_update_pilot_strips(in_card_phase)` — sorts a **copy** of `_bs.pilots`
  by team and lane, pushes each five into its `PilotStrip`, gates the player
  strip's hit buttons on 작전 단계, refreshes the team-score label, and lets
  `PilotDetailPanel.close_if_phase_left()` close the modal if the phase moved on.
- Calls `update_time_label()` (also called every frame from `_process`).

### update_time_label() (per-frame)
Pulls `_bs.get_elapsed_ingame_seconds()` and formats as `%02d:%02d`. Called
from `BattleSim._process` every frame so the clock visibly ticks even when no
HUD-state event fires.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.
