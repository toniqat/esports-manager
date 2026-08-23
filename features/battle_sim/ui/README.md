# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | 전략 포인트 ring gauge; the player's one doubles as the 턴 넘기기 button |
| `CardPileStack.gd` | CardPileStack | 덱 / 버린 더미 — 앞으로 누운 카드 뭉치 + 장수 |
| `PilotStrip.gd` | PilotStrip | 파일럿 5인 스트립 — 눈높이 초상화 + 체력 바 + 성장치. 상단(적) / 하단(아군) 두 벌, **양쪽 다 누르면 상세가 열린다**. 아군 칸에는 **파일럿 스킬 준비도 딤 + 숫자**가 얹힌다 |
| `ObjectiveTimer.gd` | ObjectiveTimer | 오브젝트 등장 시계 — 적 스트립 양옆에 아이콘 + 남은 턴(좌 전령 / 우 용). **누르면 보상 팝업이 열린다** |
| `ObjectiveRewardPopup.gd` | ObjectiveRewardPopup | 오브젝트 보상 미리보기 — 시계를 누르면 그 오브젝트가 주는 카드를 실물로 띄운다 |
| `PilotDetailPanel.gd` | PilotDetailPanel | 파일럿 상세 모달 — 좌 전신 아트 2장 / 우 머리글 + 탭 3개 + 스탯 칩 + 지속 효과 + 카드 + **파일럿 스킬 블록** |
| `KillFeed.gd` | KillFeed | 킬로그 — 우측 상단에 처치 / 포탑 철거를 한 줄씩. 교전 중 처치는 아레나가 닫힌 뒤 몰아서 |

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
- **Top panel** (y=0, h=132) — 시간 · 팀 점수 한 줄 + 그 아래 **적 파일럿
  스트립** + 그 양옆 **오브젝트 시계 두 칸**. Has an explicit opaque dark `StyleBoxFlat` so the AI hand peek
  behind it stays visually clipped regardless of theme. 아군 스트립은 여기가
  아니라 핸드 행 아래에 있다 — 아래 파일럿 스트립 절 참고.
- **Deck / Discard 카드 뭉치** (in the gutters either side of the card row) —
  `_bs.pile_deck` (left) and `_bs.pile_discard` (right), two `CardPileStack`
  controls. CardPhaseManager pushes the count on every draw / play and tweens
  it during a deck/discard reshuffle. Built by `_build_hand_indicators()`.
  **Both piles are also buttons**: a transparent flat `Button`
  (`_make_pile_button`) covers each one — `CardPileStack` sets itself to
  `MOUSE_FILTER_IGNORE` and takes no clicks of its own — and opens
  `CardPileViewer` on that pile. `_update_pile_buttons()` runs from
  `update_hud()` and gates both on `CardPhaseManager.can_browse_piles()`
  (작전 단계 only), fading the piles via `set_dimmed(true)` while disabled.
  See `card_phase/README.md` → Deck / Discard 목록 열람. The gutter is
  **not** `BS_HAND_AREA_MARGIN` —
  `BS_HAND_WIDTH_SCALE` widens the card row past it, so the gutter is derived
  as `min(BS_HAND_AREA_MARGIN, (screen_w − BS_HAND_WIDTH) / 2)` (89px at 1080)
  and the title font shrinks with it (22 → 20) so "Discard" still fits and no
  card ever overlaps a pile. The inset is **4px** (the old labels used 8) —
  the pile's width *is* the card's width, so it takes everything the gutter has.

  > **예전에는 이 자리가 `"Deck\n18"` 두 줄짜리 `Label` 하나였다.** 숫자는
  > 읽혔지만 더미가 물건으로 보이지 않아서, 손패에 들어오는 카드가 어디서
  > 오고 버린 카드가 어디로 가는지가 화면 어디에도 없었다. `lbl_deck_count` /
  > `lbl_discard_count` 는 그때 사라졌다.
- **전략 포인트 도넛 ×2** — `CostDonut` ring gauges in the **left-hand** gutter
  (see below). Built by `_build_cost_donuts()`.
- **아군 파일럿 스트립** (y 1766..1888) — 핸드 행 아래. 예전에는 여기가 비어
  있었다(하단 코스트 바와 사각 단계 넘기기 버튼이 사라진 자리). 바닥 ~32px 는
  아이폰 홈 바 / 시스템 제스처용으로 남긴다. `_build_player_strip()`.
  **그 뒤에 뒤판 `Panel` 한 장**(`PlayerStripBackdrop`, y 1756..1898)이 깔린다 —
  아래 파일럿 스트립 절의 "아군 스트립 뒤판" 참고.
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
`set_flip_allowed(in_card_phase and not modal_up)` where `modal_up` is
"Deck/Discard 열람 중 **or** 전투 개시 VS 확인 화면이 떠 있음" (turning it off
un-flips). Both clauses are load-bearing for the same reason: `CostDonut`
listens on `_input`, which runs ahead of GUI picking, so it stays tappable
straight through either dim. The VS screen matters because `game_phase` is
still CARD_PHASE while it is up — the arena has not opened yet, so
`in_card_phase` alone lets the donut through.
`set_end_enabled(can_end_card_phase())` — **작전 단계 내내 true** 이고, 배너 /
모달 / 돌진 연출처럼 지금 닫으면 무언가가 끊기는 상태에서만 false 다. 카드를
한 장도 내지 않고 넘겨도 된다(see `card_phase/README.md`). `set_locked(…)`
still exists on `CostDonut` but **nothing calls it any more** — targeting stopped
being modal, so there is no state that needs the flip blocked. The donut's y is
still derived from `CardTargetingOverlay.BTN_HAND_GAP + BTN_H` so it keeps the
same vertical band the 확인/취소 row occupies on the far side of the screen.

### 덱 / 버린 더미 뭉치 (`CardPileStack.gd`)
핸드 행 양옆 거터에 **앞으로 누운 카드 뭉치**를 그리는 `Control`. 뒷면이 위를
향한 카드가 겹쳐 쌓인 모양이고, 그 자체가 카운터이자 열람 버튼의 과녁이다.

**"누워 있다"는 두 가지가 만든다.** (1) 세로를 `FORESHORTEN`(0.55)만큼 눌러
카드의 220/160 비율을 죽이고, (2) **윗변을 아랫변보다 좁게**
(`TOP_EDGE_SCALE` 0.78) 그려 원근을 넣는다. 직사각형을 그냥 납작하게만 눌러
놓으면 누운 카드가 아니라 그냥 얇은 카드로 읽힌다. `FORESHORTEN` 은 0.42 로
시작했다가 0.55 로 올렸다 — 더 눕히면 맨 위 카드의 면이 숫자보다 얇아져
뒷면이 아니라 띠가 된다. 세로 자리는 핸드 행 높이(220px)만큼 있고 뭉치는
100px 도 안 쓰므로 아낄 이유가 없다.

**층은 위로 쌓인다.** 층이 올라갈수록 화면 **위쪽**으로 `LAYER_DY`(5.5px)씩
밀리므로 아래 카드들의 앞쪽 단면이 뭉치 **아래**로 삐져나오고, 위에서 비스듬히
내려다보는 자세가 된다. 맨 마지막에 그리는 층이 곧 맨 위 카드이고, 장수는 그
카드 뒷면 한가운데에 찍힌다(외곽선을 함께 깐다 — 아래 층의 밝은 단면과 겹치는
프레임이 있다). 제목("Deck" / "Discard")은 뭉치 아래 `Label` 자식이다.

**두께 = 장수.** 보이는 층 수는 `ceil(count / CARDS_PER_LAYER)`(4장당 한 층),
상한 `MAX_LAYERS`(8). **바닥선은 고정이고 뭉치는 위로만 자란다** — 세로 중심을
고정하면 카드 한 장이 오갈 때마다 뭉치 전체가 아래위로 떨린다. 자리는 언제나
`MAX_LAYERS` 기준으로 잡아 둔다. `set_count()` 는 `float` 를 받는다:
`CardPhaseManager._animate_reshuffle_counts` 의 리셔플 트윈이 소수로 굴러들어
오므로 두께도 숫자와 같은 곡선으로 자라고 줄어든다. 0장이면 테두리만 남은 빈
슬롯 하나에 흐린 "0".

맨 위 카드 뒷면 색(`BACK_FILL` / `BACK_LINE`)은 `Card._apply_back_style` 와
같은 값이라 손패의 뒷면 카드와 같은 물건으로 읽힌다. **뒷면은 이 색 하나로
균일하게 칠한다** — 예전에는 면 안쪽으로 물러난 사다리꼴을 더미별 accent 색
(덱 보라 / 버린 더미 적갈, `HudBuilder.PILE_ACCENT_*`)으로 덧그렸는데, 뭉치가
작아 그 액자가 무늬가 아니라 **면에 얹힌 계조**로 읽혔다. 두 더미는 아래 제목
라벨이 이미 갈라 주므로 색으로 또 가를 이유가 없다. `accent` 인자와
`PILE_ACCENT_*` 상수는 그때 함께 사라졌고 `setup()` 은 `(title, font_size)` 다.

측정(1080폭, 거터 81px): 카드 한 장 61px · 8층 뭉치 99.5px · 숫자 폰트 27.

#### 오가는 카드 = 잔상 (`play_pop` / `play_land`)
숫자만 바뀌면 카드가 **더미에서 나왔다 / 더미로 들어갔다**가 화면에 남지 않는다.
그래서 뭉치는 맨 위 카드와 같은 모양의 **잔상** 한 장을 더 그린다 — 노드가
아니라 `_draw()` 안의 사다리꼴 하나라 레이아웃 · 입력 · z-order 에 아무 영향이
없고, 잔상은 뭉치보다 **뒤에 그리지 않는다**(가려지면 동작의 절반이 사라진다).

| | 방향 | 알파 | 부르는 곳 |
|---|---|---|---|
| `play_pop()` (덱) | 맨 위 카드에서 **위로** `GHOST_RISE_PX`(74px) | 1 → 0 | `CardPhaseManager._play_draw_intro` ⓪ |
| `play_land()` (버린 더미) | 그 높이에서 **아래로** 내려앉음 | 0 → 1 | `CardPhaseManager._notice_discard_gain` |

- 한 장이 도는 시간은 `GHOST_SEC`(0.26s). 잔상은 **여러 장이 동시에** 돌 수
  있어야 하므로(개시 5장 · 드로우:N · 버리기:N) 트윈이 아니라 `_ghosts` 배열 +
  `_process` 로 굴린다. 각 항목이 자기 `delay` 와 진행도를 들고 있어 서로를
  끊지 않는다. `play_burst(land, n, delay)` 가 `GHOST_STAGGER_SEC`(0.08s)씩
  밀어 넣는다.
- **드로우와의 이음매**: 왼쪽 진입은 잔상이 다 사라진 뒤가 아니라 알파가
  `GHOST_HANDOFF_ALPHA`(0.30) 만큼 남은 시점에 시작한다 — 완전히 사라진 뒤에
  시작하면 한 장이 두 번 나온 것처럼 끊겨 보인다. 그 시각은
  `CardPileStack.ghost_handoff_delay()`(= 0.182s) 한 곳에서 나온다.
- **버리기와의 이음매는 반대로 겹치지 않는다.** 착지 잔상은 손패 카드가 다
  떨어진 **뒤**(`CardPhaseManager.PILE_LAND_DELAY_SEC` = `Card.DISCARD_FADE_SEC`
  0.30s)에 출발한다 — 드로우는 한 장이 덱에서 손으로 이어 달리는 그림이라
  겹쳐야 하고, 버리기는 손에서 떨어진 카드가 더미에 **도착**하는 그림이라
  이어 붙여야 한다. 그리고 **숫자와 두께는 그 잔상이 다 내려앉은 뒤에 오른다**
  (`CardPhaseManager._discard_pending` / `_commit_discard_gain`) — 카드가 뭉치에
  닿는 순간과 더미가 두꺼워지는 순간이 같아진다.

### 파일럿 스트립 (`PilotStrip.gd`) — 상단 적 / 하단 아군
예전에는 열 명이 **전부 상단 패널 안에** 84px 슬롯으로 몰려 있었다(아군 좌 /
점수 중앙 / 적 우). 얼굴이 76px 정사각이라 누가 누구인지 읽히지 않았고, 두 팀이
같은 줄에 붙어 있어 어느 쪽이 내 팀인지도 한눈에 안 들어왔다. 지금은 두 벌로
갈라져 있다:

| 스트립 | 위치 | 크기 | 입력 |
|---|---|---|---|
| 적 (`_enemy_strip`) | 상단 패널의 자식, `ENEMY_STRIP_RECT`(137, 46, 806×97) | 초상화 145×60 | 눌러서 상세 패널 |
| 아군 (`_player_strip`) | 핸드 행 **아래**, `PLAYER_STRIP_RECT`(25, 1766, 1030×122) | 초상화 190×79 | 눌러서 상세 패널 |

**적 스트립은 아군의 66%** 이고 가로 가운데에 앉는다. 크기가 네 번 바뀐 자리다:
처음에는 730×84(초상화 130×54) 축소판이었고 — 같은 얼굴을 위아래에서 두 배 다른
크기로 보여 주니 상대가 누구인지도 상대 성장치도 아군만큼 읽히지 않았다 — 그래서
아군과 **똑같은** 1030×122 로 키웠다(상단 패널이 130 → **168** 로 커지고 그 아래
사슬이 38px 내려간 것이 그때다). 다시 줄인 이유는 자리다: 오브젝트 등장
시계가 전장 타일에서 이 패널로 올라오면서 **스트립 양옆에 아이콘 + 턴 수가 앉을
칸**이 필요해졌다(`ObjectiveTimer.gd`). 성장치는 그대로 두 자릿수까지 읽히므로
"내 것과 나란히 비교한다"는 원래 목적은 살아 있다.

그때의 60%(618×76, 초상화 108×45)는 얼굴이 누구인지 읽히는 하한을 밑돌았다.
지금 값은 **초상화만 10% 키운 것**이다 — 초상화 폭은 칸 폭에서 유도되므로
(`setup()` 이 `_cell_w − 16`) 키우는 길은 스트립 폭을 같은 비율로 미는 것뿐이고
(618 → **672**), 높이도 eye 비(2.4:1)를 따라 76 → **81** 로 함께 올라간다.
좌우 여백은 그만큼 줄어 시계 칸이 190 → **168** 이 됐고, 스트립 x 는 가운데
정렬을 유지해 231 → **204** 로 옮겼다.

**역할 태그는 초상화 높이에서 유도한다**(`ROLE_TAG_H_RATIO` 0.24 /
`ROLE_TAG_ASPECT` / `ROLE_TAG_FONT_RATIO` 0.74). 두 스트립의 초상화 크기가
달라졌으므로 고정 픽셀(30×19, 폰트 14)로 두면 작은 쪽에서 태그가 얼굴 절반을
덮는다. 비율은 큰 쪽의 원래 값에서 그대로 딴 것이라 **아군 스트립의 그림은 한
픽셀도 달라지지 않는다**.

**양쪽 다 눌린다.** 적 파일럿도 아군과 같은 게이트(자기 작전 단계)에 같은 내용
(인게임 · 파일럿 · 메크)으로 열린다 — 상대 로스터는 이미 `match_ctx.enemy_roster`
로 들어와 있어 `BattleSim.player_data_for` 가 인덱스 5..9 로 그대로 찾아 준다.

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
- **성장치** — `BattleSim.fmt_score(p.score)` → `"24.9k"`(자릿수가 늘면 소수 자리를 줄인다: `1.00k` → `24.9k` → `125k`). **게이지가 아니라
  숫자다** — 상한이 없어 채울 바탕이 없다. 개시 `1.00k` 에서 50턴 `25.00k`,
  잘 큰 캐리는 `40.00k` 을 넘긴다. MOBA 중계의 골드 표시에 해당하고, **이 숫자가
  곧 그 파일럿의 공격력 배율**이다(25k = atk ×3.0) — 두 줄 위의 체력 바가 실제로
  길어지는 것과 같은 성장을 숫자 쪽에서 읽는 것이다. 적립 규칙은 `BattleSim` 의
  `SCORE_*` 절 참고.

칸 순서는 **전장을 왼쪽부터 오른쪽으로 훑은 순서**다 — **좌측 → 정글 → 중앙 →
우측 ×2**(`HudBuilder.LANE_SEAT_ORDER`). `LanePosition` 의 열거값 순서
(LEFT · CENTER · RIGHT · GUERRILLA)를 그대로 쓰면 정글러가 우측 라이너 **뒤**
다섯 번째 칸에 앉는데, 정글은 지도에서 좌우 레인 **사이**라 그 자리는 전장
어디와도 대응하지 않는다. 정렬은 **`_bs.pilots` 의 사본에** 한다 — 원본은 스폰 순서(= 역할 순서)를
유지해야 `BattleSim.player_data_for` 가 그 인덱스로 로스터를 찾을 수 있다.

**하단 스트립의 y(1766)는 카드 밑단에서 계산해 나온 값이다.** 부채꼴의 양 끝
카드는 가운데보다 21.4px 아래로 처지고(12장 기준) 호버/선택 시
`Card.HOVER_SCALE`(1.2)로 커지므로 최악의 경우 카드 밑단이 y ≈ 1763 까지
내려온다. 1724 에 두었더니 카드가 초상화 윗부분을 덮었다(실측 확인).

**아군 스트립 뒤판** — `PlayerStripBackdrop`, 스트립 영역을 `PLAYER_BG_PAD`
(10px) 만큼 사방으로 넓힌 짙은 `Panel` 한 장(y 1756..1898). 색과 테두리는 상단
패널과 같다. 적 스트립은 상단 패널 위에 앉아 있어 처음부터 받침이 있었지만,
아군 스트립은 맨 화면 위에 떠 있어 얼굴 · 체력 바 · 성장치 세 줄이 배경 없이
흩어져 보였다 — 특히 성장치 숫자는 받침이 없으면 어디까지가 한 파일럿의 칸인지가
읽히지 않는다. **`_build_player_strip()` 이 스트립보다 먼저 붙인다**(형제
z-order 가 곧 자식 인덱스라, 나중에 붙으면 판이 초상화를 덮는다) 그리고
**`set_strip_visible(0, on)` 이 스트립과 함께 숨긴다** — 상세 패널이 스트립만
치우면 빈 판이 딤 위에 덩그러니 남는다.

**입력 게이트**: `set_interactive_enabled(in_card_phase)` — 자기 작전 단계가
아니면 히트 버튼이 `disabled` 다. 히트 판정은 칸 전체를 덮는 투명 `Button` 이
가져간다(`Label` / `TextureRect` 는 클래스 기본이 `MOUSE_FILTER_IGNORE` 라
스스로 클릭을 받지 못한다).

### 오브젝트 시계 (`ObjectiveTimer.gd`) — 적 스트립 양옆
**아이콘 하나 + 남은 턴 수** 한 쌍짜리 `Control` 이 둘. 왼쪽이 전령(보랏빛 깃발),
오른쪽이 용(주홍 날개) — **전장에서 두 오브젝트가 서는 칸의 좌우와 같은 배치**라
자리가 곧 이름이다. 그래서 이름표가 없다.

- 상태는 `ObjectiveSystem.turns_until_cell(cell)` 하나에서만 온다. 갱신은
  `HudBuilder.update_hud` 가 `queue_redraw()` 를 부르는 것뿐이다.
- **아이콘은 이미지가 아니라 도형이다**(킬로그 글리프와 같은 방식). 좌표는 전부
  **64×64 기준**으로 적고 `ICON_SIZE / 64` 배율만 곱해 옮기므로, 크기를 바꿀 때
  숫자를 다시 짤 필요가 없다.
- **칸은 적 스트립이 남긴 여백이 정한다.** 스트립이 20% 커지면서 이 칸은
  168 → **101×60** 이 됐고, 시계 쪽은 그 폭에 맞춰 두 군데를 줄였다 —
  아이콘과 숫자 사이 간격 `ICON_TEXT_GAP` 10 → **4**, 그리고 숫자 옆의
  **"턴" 글자를 통째로 삭제**(`UNIT_FONT_SIZE` / `UNIT_COLOR` 함께 사라졌다).
  아이콘 옆에 붙은 숫자가 남은 턴 수 말고 무엇일 수는 없으므로 그 두 글자는
  숫자를 밀어내기만 했다. 얼굴이 먼저 읽혀야 하는 패널이라 자리를 다툴 때
  물러나는 쪽은 언제나 시계다.
- `ICON_SIZE` 는 **49** 그대로다. 한때는 아이콘 62 에 칸 높이가 스트립 띠
  전체(122)여서 — 클수록 곁눈으로 읽힌다는 이유였다 — 시계가 초상화보다
  위아래로 튀어나와 상단 패널에서 가장 큰 물체가 됐고, 정작 얼굴로 가야 할
  시선을 먼저 잡아챘다. 지금은 아이콘이 초상화(60px)보다 살짝 작고 세로
  가운데에 놓여 좌 시계 · 얼굴 다섯 · 우 시계가 한 줄로 읽힌다.
- **누를 수 있다.** `mouse_filter` 가 IGNORE → **STOP** 이 되고 `timer_pressed(kind)`
  를 쏜다. `HudBuilder._on_obj_timer_pressed` 가 받아
  `BattleSim.objective_reward.toggle(kind)` 를 부른다 — 같은 시계를 다시 누르면
  닫히므로 여는 손잡이가 곧 닫는 손잡이다.
- 용의 날개는 **꼭짓점 넷짜리 매끈한 삼각**이다. 처음에는 박쥐 날개처럼 아래에
  톱니를 넣었는데(꼭짓점 여덟) 그 크기로 줄이면 톱니가 뭉개져 **나뭇잎 한 장**으로
  보였다 — 이 크기에서 실루엣을 만드는 것은 디테일이 아니라 큰 삼각형 둘의
  각도다.
- 숫자는 남은 폭 한가운데에 놓는다(한 자리 ↔ 두 자리에서 자리가 흔들리지
  않게). 패널 배경이 짙어 얇은 글자는 묻히므로 검은 외곽선을 먼저 깐다.

한때 이 숫자는 **전장 타일 위**에 있었다(`BattleRenderer._draw_objectives`).
그 칸이 평범한 정글 칸으로 돌아오면서 캠프 아웃라인 · 점령 면 색 · 파일럿
초상화가 이미 그 칸을 쓰고 있었고, 글자 두 줄이 넷째 손님이 됐다.

### 오브젝트 보상 미리보기 (`ObjectiveRewardPopup.gd`)
시계를 누르면 열리는 **정보 팝업**. 자기 `CanvasLayer`(12)에 그린다.

```
[풀스크린 딤 α 0.78 — 아무 데나 누르면 닫힌다]
└─ 판 560×내용 (화면 한가운데, 테두리 = 오브젝트 색)
     ├ 전령 / 용                    (40pt, 보랏빛 / 주홍)
     ├ N턴 뒤 등장                  (24pt)  ← ObjectiveSystem.turns_until_cell
     ├ 보상: [전령 제압] — …        (24pt)  ← ObjectiveSystem.reward_text
     ├ 보상 카드 한 장 (Card.tscn 원본 크기) + 여러 장이면 오른쪽에 ×N
     ├ 획득 즉시 손패로 / 덱에 섞여  (22pt)
     └ [닫기]
```

- **왜 있는가.** 오브젝트는 참여 / 미참여를 고르는 사건인데, 무엇을 주는지는
  결판이 임박한 그 턴에 뜨는 결정 창의 한 줄 말고는 볼 자리가 경기 내내 없었다.
  라인을 밀지 정글러를 붙일지는 보상의 값어치를 알아야 정해진다.
- **전장을 붙잡지 않는다.** `ObjectiveSystem` 의 참여 결정 창과 달리 순수
  정보이므로 `BattleSim._battle_tick_held()` 가 이 팝업을 읽지 않는다 — BATTLE
  자동 틱도 MM:SS 시계도 평소대로 흐른다. 대신 딤이 STOP 이라 뒤쪽 입력은 삼킨다.
- **카드는 진짜 `CardData` 다** — `CardPhaseManager.make_objective_card(id)` 가
  `cards.csv` 에서 그대로 집어 온다(보상 카드는 `pool = 0` 이라 이 경로로만
  세상에 나온다). 따로 그린 그림이면 실제로 손에 들어온 카드와 같은 것인지
  확인할 길이 없다. 카드에 시전자가 없으므로(`owner_pilot == null`) 초상화 자리는
  빈다 — 손패에서 보게 될 모습 그대로다.
- 카드가 DB 에서 안 나오면(`make_objective_card` → null) 자리에 한 줄 안내만
  세운다. 팝업 하나 때문에 매치를 세우지 않는다.

### 파일럿 상세 패널 (`PilotDetailPanel.gd`)
스트립의 얼굴(**아군 하단 / 적 상단 양쪽**)을 누르면 열리는 **모달**. 자기
`CanvasLayer`(13)에 그리므로 버리기(10) / 대상 지정(11) / 열람·교전(12) 위다.

```
[풀스크린 딤 α 0.88]
├─ 아트 2장 (ArtHolder) — 앞 / 뒤 두 자리를 파일럿과 메크가 나눠 갖는다
│    앞: 밝게, 가로 중심 ART_FRONT_CENTER_X(320), 높이 ART_H(1400)
│    뒤: +ART_BACK_SHIFT_PX(400) 오른쪽, ×ART_BACK_SCALE(0.90), ART_BACK_TINT 로 딤드
│    둘 다 아래끝이 ART_BOTTOM(2010) — 화면(1920)보다 아래라 **하단이 잘린다**
├─ 머리글 (자기 받침 Panel, y HDR_TOP 452 .. HDR_BOTTOM 562) — **탭과 분리, 늘 같은 내용**
│    파일럿명 (40pt) + 기체명 (22pt, 옆에 작게) ─────────  성장치 (40pt, 우측)
├─ 탭 3개  [인게임][파일럿][메크]  STAT_X 600, 폭 452/3, TAB_H 62, 위끝 = 머리글 아래끝
├─ 우: 상세 패널  STAT_X 600, STAT_W 452, STAT_TOP 650 (받침 Panel 이 내용 높이에 맞춰 자람)
│    ├ 스탯 칩 3열 × N행  (칩 141×92, 위 작게 이름 / 아래 크게 **최종 값**)
│    ├ (인게임 탭) 지속 효과 썸네일 한 줄 — 68×68, 걸려 있는 것만
│    ├ 카드 — Card.tscn ×0.80 = 128×176, 인게임 탭은 3열 2행(6장) / 나머지 탭은 3장
│    └ (인게임 탭) 파일럿 스킬 블록 — 이름 + 타입 배지 / 키워드 / 설명문 / 상태 / [사용]
└─ 하: [닫기]  받침 아래끝 + BTN_GAP_Y(24) — 탭마다 함께 내려온다
```

| 탭 | 앞에 선 아트 | 칩 | 그 아래 |
|---|---|---|---|
| 인게임 | 파일럿 | 체력 · 공격력 · 성장 · 명중 · 회피 · 존재감 | (사망 시) `부활까지 N턴` → **지속 효과** → **보유 카드 6장 (3×2)** |
| 파일럿 | 파일럿 | 라인전 · 메카닉 · 게임센스 · 한타 · 멘탈 | 파일럿 카드 3장 |
| 메크 | 메크 | 체력 · 공격력 · 존재감 | 메크 카드 3장 |

- **머리글은 탭과 분리돼 있다**(`_build_header_block`, `_build` 에서 **한 번만**
  돈다). 이름 · 기체명 · 성장치는 어느 탭을 보든 같은 파일럿의 것이므로 탭이
  바뀔 때마다 다시 세울 이유가 없다. 예전에는 이 줄이 본문 안에 있었고 메크
  탭에서 제목이 기체명으로 바뀌며 **파일럿 이름과 성장치가 화면에서 통째로
  사라졌다** — 지금 누가 열려 있는지가 탭에 따라 흔들린 셈이다. 탭이 바꾸는
  것은 그 아래 상세 패널 하나뿐이다.
- **기체명은 이름 옆에 작게, 늘 보인다.** 메크 탭까지 들어가야 알 수 있는 값이
  아니다. 이름과 기체명은 `HBoxContainer` 로 이어 붙인다 — 이름 길이가 파일럿마다
  다르고 폰트도 폴백을 타서 글자 폭을 손으로 재면 조용히 어긋난다.
- **인게임 탭은 카드 6장을 3열 2행으로 다 보여 준다**(파일럿 3 → 메크 3 순서라
  윗줄이 사람, 아랫줄이 기체다). 이 파일럿이 무엇을 들고 시작했는지는 한 화면에
  있어야 하는 정보인데, 예전처럼 두 탭에 3장씩 갈라 두면 여섯 장을 견주려면 탭을
  오가야 했다. 파일럿 / 메크 탭의 3장 줄은 그대로다 — 거기서는 그 탭 스탯 옆에
  붙은 "이 몸이 주는 카드" 라는 맥락이 있다.

- **스탯은 줄이 아니라 칩이다.** 예전에는 `키 ─ 값` 두 칸짜리 행이 세로로 열몇
  줄 이어졌는데, 그러면 (1) 어느 값이 중요한지가 순서 말고는 없었고 (2) 값 뒤에
  `(기본 160)` `(7턴)` `(기본 50 / 50)` 같은 괄호가 줄줄이 붙어 정작 **지금
  얼마인가**를 읽는 데 시간이 걸렸다. 지금은 칩 한 칸이 **최종 값 하나**만 크게
  들고 있다. `_row` / `_section` / `ROW_H` / `KEY_FRACTION` / `SECTION_GAP` 은
  그때 함께 **삭제됐다**.
#### 정보 패널 — 스탯 칩 · 지속 효과 · 카드가 나눠 쓰는 판 하나
셋 다 누르면 **정보 칼럼 왼쪽에** 같은 판(`MENU_W` 372)이 펼쳐진다. "지금 무엇을
보고 있는가"는 한 번에 하나여야 하는 질문이라, 판을 따로 두면 스탯 설명과 효과
설명이 동시에 떠서 어느 것이 방금 누른 것인지가 흐려진다. 왼쪽에 펼치는 이유는
둘이다 — 오른쪽은 화면 끝(1080)까지 28px 뿐이고, 누른 것 위에 겹쳐 띄우면 방금
누른 칩이 자기 설명에 가려진다.

**누를 수 있는 것은 전부 `_targets` 한 표에 모인다** — `key → {button, style, …}`.
키 접두사가 종류를 가른다.

| 키 | 무엇 | 제목 | 행(`_menu_rows`) | 설명(`_menu_note`) |
|---|---|---|---|---|
| `hp` `atk` `growth` … | 스탯 칩 | 칩 이름 | 기본값 · 증가분 · 최종 | 그 값이 뭘 가르는가 |
| `fx:lane` `fx:rate` `fx:perm` `fx:atk` `fx:shield` | 지속 효과 | 온전한 효과 이름 | 어디에 곱해지는가 · 남은 시간 · 최종값 | 규칙 한 줄 |
| `card:<slot>:<i>` | 카드 | 카드 이름 | 비용 · 종류 · 시전자 · 키워드 | **카드 설명문 그대로** |

- **뒤판이 클릭을 대신 전달한다**(`_on_menu_backdrop_input`). 뒤판은 여전히 전체
  화면 STOP 이지만, 예전처럼 무조건 닫지 않고 그 좌표에 있던 **대상 버튼 / 탭 /
  닫기**를 찾아 대신 눌러 준다. 예전에는 공격력 설명을 열어 둔 채 명중 칩을
  누르면 첫 클릭이 닫는 데 쓰여 **한 번 더** 눌러야 했다 — 스탯 여섯 개를
  훑는 동안 클릭이 두 배가 되고 화면이 열림↔닫힘을 반복해 깜빡였다. 정보 패널은
  서로 갈아타는 것이 기본 동작이다. 아무것도 없는 곳을 누르면 그때 닫힌다.
  좌표 판정이 단순한 이유는 `_menu_root` · `_body_root` · `_root` 가 모두 (0,0)
  에 놓인 전체 화면 `Control` 이라 버튼의 `position` 을 그대로 견주면 되기
  때문이다.
- **판 높이는 내용이 정한다** — 행 수 × `MENU_ROW_H` + 설명 글의 **실제** 높이
  (`_text_height`). 설명 높이를 잴 때 **줄바꿈 플래그를 Label 과 맞춰야 한다**:
  `get_multiline_string_size` 의 기본값은 `BREAK_MANDATORY | BREAK_WORD_BOUND`
  인데 라벨은 `AUTOWRAP_WORD_SMART`(= `BREAK_GRAPHEME_BOUND` 가 더 붙는다)라,
  기본값으로 재면 라벨이 한 줄 더 쓰는 경우가 생겨 마지막 줄이 판 밖으로 잘려
  나간다(실측: 두 줄로 재고 세 줄로 그렸다).
- **줄바꿈은 크기보다 먼저 켠다.** `Control.size` 의 세터는 요청값을 최소 크기로
  한 번 걷어 올리는데, 줄바꿈이 꺼진 `Label` 의 최소 폭은 **한 줄로 편 글자 전체
  폭**이다 — 그 상태로 332px 를 요청하면 라벨이 글자 폭 그대로 부풀고, 뒤늦게
  줄바꿈을 켜도 이미 커진 rect 는 줄지 않는다. 화면에서는 첫 줄이 판 밖으로
  삐져나가고 아랫줄이 잘린 것으로 보였다(실측 확인). `clip_text` 도 같은 이유로
  크기보다 먼저 켠다.
- **이름 칸은 42%**(`MENU_KEY_FRAC`), 나머지가 값 칸이다. 52% 이던 시절
  "다음 작전 단계까지" 같은 값이 159px 안에 안 들어가 **왼쪽부터 잘려 나갔다** —
  오른쪽 정렬 `Label` 은 넘치면 정렬을 포기하고 rect 왼쪽부터 그린다. 값 문구
  자체도 그때 짧아졌다(`작전 단계까지` / `레인 전용`).
- **탭이 아트의 앞뒤를 정한다**(`_apply_focus`). 메크 탭이면 기체가 앞, 그 밖에는
  사람이 앞. 예전의 **"전환" 버튼(파일럿 ↔ 메크 2단 토글)은 삭제됐다** — 정보가
  셋으로 갈리면서 2단 토글로는 어디에 무엇이 있는지 말할 수 없게 됐다.
  전환 트윈(`ART_SWAP_SEC` 0.22s)은 그대로다.
- **머리글 오른쪽의 큰 숫자는 성장치다.** 예전 부제(`역할 · 아군/적군 · 성장치`)는
  삭제됐다 — 역할과 진영은 방금 누른 초상화가 이미 말해 줬고, 성장치는 부제 끝에
  묻혀 있을 값이 아니라 이 파일럿을 읽는 첫 숫자다. `라인 / 위치` 행도 함께
  삭제됐다(전장의 초상화 자리가 이미 말해 준다). 머리글이 탭 밖으로 나오면서
  **메크 탭에서도 그대로 보인다** — 예전에는 그 탭에서 제목이 기체명이 되며
  숫자가 사라졌다.
- **아트는 화면 하단이 자른다.** 아래끝(`ART_BOTTOM`)이 화면 밖이라 다리
  아랫부분이 잘려 나간다. 예전의 `_knee_crop`(알파 실루엣 높이의
  `KNEE_FRACTION` 0.80 지점에서 `AtlasTexture.region` 으로 텍스처를 잘라 내던
  것)은 그래서 **삭제됐다** — 자르는 일은 이제 화면 가장자리가 하고, 어디서
  잘릴지는 `ART_H` 와 `ART_BOTTOM` 두 상수가 정한다.
- **크기는 높이로 정규화한다.** 전신 아트는 전부 세로 1024 에 인물이 꽉 차 있고
  가로만 572~756 으로 제각각이라, 폭으로 맞추면 인물 키가 이미지마다 달라진다.
  폭은 원본 비율에서 나오므로 `ART_H` 가 곧 화면을 얼마나 채우는가다 — 1400 이면
  폭 900~1030 이고, 더 키우면 뒤에 선 메크가 오른쪽으로 완전히 밀려 나간다.
- **뒤로 물러날 때 노드 크기는 그대로 두고 `scale` 만 줄인다.** `pivot_offset`
  이 노드의 **아래 가운데**라 작아져도 바닥선이 그대로다 — 두 아트가 같은 바닥에
  선 것처럼 읽히고, 전환 트윈이 `position` / `scale` / `modulate` 세 개만
  건드리면 된다.
- **메크 아트 30장이 다 들어와 있다.** `MechImages.full_for(mech.id)` 가
  `res://resources/images/mech/{id}_full.png` 를 찾는다. 파일럿 아트와 달리 폭이
  제각각이 아니라 **1024×1024 고정 캔버스**라 어느 기체든 패널에서 같은 폭을
  차지한다(높이 정규화가 뻗은 무기까지 폭으로 환산하는 것을 막는다). 출처와
  id ↔ 기체 대응표는 `resources/README.md`.
  파일이 없을 때의 폴백은 그대로 살아 있다 — 같은 자리에 옅은 실루엣 슬래브 +
  기체명 플레이스홀더가 선다. 슬래브 알파는 0.30 이다 — 올리면 화면 절반짜리
  밝은 사각형이 되어 정작 앞에 선 파일럿보다 눈에 띈다.
- **정보 블록은 아래쪽에 있다**(머리글 452 / 탭 562 / `STAT_TOP` **650**). 아트가 커지면서 화면 위쪽 절반이
  인물의 머리·상체 자리가 됐고, 스탯이 예전 자리(170)에 남으면 얼굴을 덮는다.
  글자 뒤에는 받침 `Panel`(α 0.86)을 깐다 — 아트가 이 자리까지 올라오므로 글자만
  얹으면 일러스트 위에서 읽히지 않는다. 켜진 탭은 **아래 테두리를 그리지 않아**
  받침과 한 몸으로 이어진다.
- **닫기 버튼은 받침 아래끝에 붙어 다닌다**(`_reposition_close`). 탭마다 내용
  높이가 달라(인게임 ~360 / 파일럿 ~600) 한 자리에 못 박아 두면 짧은 탭에서
  버튼만 화면 한가운데에 떠 있다 — 예전의 고정 `BTN_Y`(1424)가 그랬다. 자리가
  바뀌는 것은 **탭을 누른 순간**뿐이고 `refresh()` 는 받침을 건드리지 않으므로
  버튼이 숫자를 따라 위아래로 떨지 않는다.
- **카드는 손패와 같은 노드다** — `_bs.CARD_SCENE.instantiate()` 를
  `CARD_VIEW_SCALE`(0.80)로 줄여 세운다(128×176 ×3 + 간격 16 ×2 = 416 ≤ 452,
  인게임 탭은 같은 격자를 2행으로 쓴다).
  다른 그림으로 그리면 "이 카드가 그 카드"라는 연결이 끊긴다. `setup(cd, false,
  true)` + `MOUSE_FILTER_IGNORE` 라 `Card._refresh_float_state`(= `scale` 의
  주인)가 영영 돌지 않고, 그래서 여기서 준 축소가 그대로 남는다.
- **카드 목록은 `BattleSim.starter_cards` 표에서 온다** — 손패 · 덱 · 버린 더미를
  훑어 역산하지 **않는다**. 소멸(`exhaust`)한 카드는 세 더미 어디에도 없어서
  역산하면 목록에서 조용히 사라지는데, "이 파일럿이 무엇을 들고 들어왔는가"는
  경기 중에 변하지 않는 사실이다. 표는 `CardPhaseManager._deal_team_deck` 이
  덱을 돌 때 한 번 적는다 — `card_phase/README.md` 참조.
#### 지속 효과 썸네일 (인게임 탭)
스탯 칩 **바로 아래** 한 줄. 68×68 칸에 위는 두 글자 약칭(효과별 색), 아래는 지금
값. 아이콘 에셋이 없으므로 **글자가 곧 아이콘**이고, 온전한 이름은 눌러서 여는
정보 패널의 제목이 들고 있다.

| 키 | 뜨는 조건 | 약칭 | 출처 |
|---|---|---|---|
| `fx:lane` | `lane_stat_mod != 0` | 라인 | 공격적인 라인전(+) / 안전한 파밍(−) |
| `fx:rate` | `growth_rate_mult != 1` | 적립 | 안전한 파밍(+10%) / 완벽한 마무리(+25%) |
| `fx:perm` | `growth_rate_bonus != 0` | 영구 | 용 보상 (누적, 만료 없음) |
| `fx:atk` | `atk_buff != 0` | 공격 | 전투 준비 등 임시 공격력 |
| `fx:shield` | `shield > 0` | 보호 | 보호 카드 |

- **걸려 있는 것만 뜬다.** 꺼져 있는 칸을 회색으로 늘어놓으면 "몇 개가 켜져
  있는가"를 도리어 세어야 한다. 하나도 없으면 `걸려 있는 효과 없음` 한 줄.
- **왜 칩만으로는 안 되는가.** 명중 칩이 55 라고 할 때 그 값이 라인전 카드 때문인지
  원래 그런지는 칩을 눌러야 나오고, **적립 배율처럼 어느 칩에도 안 실리는** 효과는
  아예 볼 자리가 없었다.
- **팀 단위 효과(계획 살인 예약)는 여기 없다.** 파일럿의 것이 아니라 팀의 것이라
  다섯 명 모두에게 같은 썸네일이 떠 무엇이 누구 것인지가 흐려진다.
- **구성이 달라졌을 때만 본문을 다시 세운다** — `refresh()` 가 `_fx_signature()`
  (키 목록)를 지난 값과 견준다. 값만 바뀌었으면 라벨 갱신으로 끝나야 열어 둔
  정보 패널이 안 닫히고 카드 노드도 다시 인스턴스화되지 않는다. 다시 세운
  뒤에는 열려 있던 키의 **새 버튼**에 강조를 다시 입힌다(옛 버튼은 free 됐다) —
  그 키 자체가 없어졌으면 패널을 닫는다.

#### 카드
- **카드 노드 위에 투명 `Button` 을 한 장 덮는다.** `Card` 는 손패에서 호버 ·
  드래그 배선을 스스로 쥐고 있는 노드라 여기서 입력을 직접 받게 하면 그 기계가
  함께 깨어난다. 버튼은 카드와 정확히 같은 자리를 덮으므로 눌리는 곳과 보이는
  곳이 어긋나지 않는다.
- **누르면 카드 설명이 정보 패널에 뜬다.** 카드 노드에 적힌 글씨는 ×0.80 으로
  줄어 있어 읽으라고 있는 것이 아니다.

- **보호막은 별도 칩이 아니라 체력 값에 붙는다** — 칩에는 `159 / 322` 만 적히고
  `보호막 +30` 은 체력 메뉴 안에 있다. 보호막은 그 자체로 읽는 숫자가 아니라
  "지금 몇 대 더 버티는가"이고, 그 답은 체력과 나란히 놓여야 나온다.
- **명중 / 회피 칩은 라인전 스탯이 먹은 값이다.** 안전한 파밍 / 공격적인
  라인전이 미는 것은 `PilotData.hit` / `evasion` 필드가 아니라 **판정 시점의
  배율**(`lane_stat_mod`)이라, 원본 필드를 그대로 찍으면 카드를 내도 이 값이
  1 도 움직이지 않는다. 판정과 **같은 함수**(`SimulationCore.lane_adjusted`)를
  통과시켜 화면의 숫자와 실제로 굴러가는 숫자를 하나로 묶고, 기본값과 배율은
  메뉴에 적는다(배율이 걸려 있을 때만 그 줄이 생긴다).
- **`성장` 칩의 큰 숫자는 공격력 성장이고, 최대 체력 성장은 메뉴 안에 있다.**
  둘은 4배 차이로 **다르게** 자라므로(`GROWTH_ATK_PER_SCORE` vs
  `GROWTH_HP_PER_SCORE`) 한 칸에 한 숫자만 세울 때 큰 쪽을 세운다. 이 값은
  성장치에서 파생된 것이고, 카드가 미는 `적립 배율`(`growth_rate_mult`)과는
  **다른 것**이다 — 이름이 비슷해 헷갈리기 쉬운 자리라 메뉴에서 둘을 나란히 둔다.
- **아웃게임 스탯(파일럿 탭)은 경기 중에 변하지 않는다** — 훈련으로만 오른다.
  그래서 메뉴의 `인게임 증가` 행이 언제나 `없음` 이다.
- **칩 값의 폰트는 글자 수가 정한다**(`_value_font_size`, 4자 이하 38 → 10자 이상
  22). 칩 폭이 141px 뿐이라 `159 / 322` 를 가장 큰 폰트로 두면 잘린다 —
  자르느니 한 단계 줄이는 편이 읽힌다.
- **`refresh()` 는 (지속 효과 구성이 그대로인 한) 트리를 다시 세우지 않는다**
  (`update_hud` 마다, `close_if_phase_left` 바로 뒤). 칩 값 라벨 · 성장치 ·
  열려 있는 패널의 글자만 고친다 — 통째로 다시 세우면 카드 노드 셋이 **매 갱신마다** 인스턴스화되고
  눌러 둔 칩의 강조도 그때마다 깜빡인다. 탭이 바뀔 때만 `_rebuild_body()` 가
  돈다. 헌 블록은 `queue_free` 만 걸면 이번 프레임까지 그려져 글자가 겹치므로
  **`remove_child` 를 먼저** 한다. 아트와 앞뒤 자세는 어느 쪽도 건드리지 않는다.
- **값 라벨에는 `clip_text = true` 가 필수다.** 오른쪽 정렬 `Label` 은 글자가
  rect 보다 넓으면 정렬을 포기하고 rect 왼쪽부터 그려서 **오른쪽으로 넘쳐 화면을
  벗어난다**(실측: "아웃게임 데이터 없음" 이 화면 밖에서 잘렸다).
- **`_body_root` 의 `MOUSE_FILTER_IGNORE` 는 그 노드만 뺀다** — 자식 칩 · 효과 ·
  카드 버튼은 그대로 눌린다. z-order 는 `_root` 의 자식 순서다: 0 딤 / 1 아트 /
  2 본문 / 3~5 머리글(받침 · 이름 행 · 성장치) / 6~8 탭 / 9 닫기 / (열려 있으면)
  정보 패널이 맨 뒤 = 맨 위.
- 아웃게임 스탯은 `BattleSim.player_data_for(pilot)` 로 찾는다 — `pilots` 배열의
  인덱스(0..4 = 팀0, 5..9 = 팀1)를 `match_ctx` 의 두 로스터에 그대로 대응시키는
  방식이라 **`pilots` 를 재정렬하면 이름과 스탯이 어긋난다**. 단독 실행이나
  INTL 파일럿은 null → 칩 값이 `—`. 적 파일럿이 열리는 것도 이 대응 덕이다.
- 열려 있는 동안 **누른 쪽 팀의 스트립만 숨긴다**(`HudBuilder.set_strip_visible(team, on)`).
  딤 위로 스트립만 남으면 지금 무엇을 보고 있는지가 흐려지고, 딤 아래로 넣으면
  방금 누른 얼굴이 어두워져 연결이 끊긴다. 반대 팀 스트립은 그대로 둔다 —
  딤에 가려질 뿐이고, 치우면 무엇이 사라졌는지가 더 헷갈린다.
- `_root` 에 **앵커 프리셋을 걸지 않는다.** `CanvasLayer` 아래의 `Control` 은
  full-rect 앵커를 해석해 줄 부모 rect 가 없어 크기가 0 으로 남고, 프리셋만
  걸어 두면 "`_ready` 뒤에 size 가 덮어써진다"는 경고가 남는다. 크기는 명시한다.
- **작전 단계를 벗어나면 강제로 닫힌다**(`close_if_phase_left`, `update_hud`
  마다 호출). 열어 둔 채 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.

### 상단 패널 (시간 + 팀 점수 + 오브젝트 시계 + 적 스트립)
`TOP_PANEL_Y` 0 / `TOP_PANEL_H` **148**. 헤더 줄(y 4..38) 아래가 스트립 띠
(y 46..143)이고 거기에 5px 를 더한 값이 패널 높이다 — **패널 높이는 내용이
정한다.** 띠 안에서 적 스트립은 가운데 806px 를 쓰고, **남은 좌우 여백이 오브젝트
시계 두 칸**이다(`OBJ_TIMER_LEFT_X` 26 / `OBJ_TIMER_RIGHT_X` 953, 각 101×60 —
세로는 적 초상화 띠와 정확히 같다).

적 스트립은 두 번 커졌다: 618 → 672(초상화 +10%) → **806**(다시 +20%, 초상화
145×60). 얼굴이 그 크기에서야 누가 누구인지 읽히고, 성장치도 내 것과 나란히
비교할 수 있다. 그만큼 시계 칸이 190 → 168 → **101** 로 줄었고, 시계 쪽에서
아이콘·숫자 간격과 "턴" 글자를 지워 그 폭에 맞췄다 — 자리를 다툴 때 물러나는
쪽은 언제나 시계다.

그리고 그 아래가 사슬이다: 이 패널이 상대 핸드 peek 의 윗부분을 가리는
가림막이고(`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50` = **98**, 카드 아래 49px 만
삐져나온다), peek 카드 아래 끝(y 197)에서 `DONUT_AI_HAND_GAP` 만큼 띄운 자리가
적 도넛(아래 끝 y **327**)이며, 그 아래가 전장 픽셀 상단(y **369**)이다.
**패널 높이를 바꾸면 `AI_HAND_TOP_Y` 와 `KillFeed.FEED_TOP`(= `TOP_PANEL_H + 8`)
을 같은 양만큼 함께 옮겨야 한다** — 전자를 두면 peek 이 패널 뒤로 통째로 숨거나
(키울 때) 카드 윗부분이 그대로 드러나고(줄일 때), 후자를 두면 킬로그가 패널에서
떨어져 뜬다. 도넛은 `AI_HAND_TOP_Y` 에서 계산되므로 따로 만질 것이 없다.
168 → 132 로 줄었다가 스트립이 커지며 **148** 이 됐고, 사슬도 같은 16px 씩
내려갔다(peek 98 / 도넛 327 / 킬로그 156). 전장까지의 여유는 **42px** 이고, 그
사이의 빈 띠를 **카드 설명 상자**가 쓴다 — `CardPhaseManager.DESC_BOX_TOP`.

- **시간 라벨** — 좌측(x 20), `font_size` 18. `MM:SS` (`get_elapsed_ingame_seconds`).
  **시는 표시하지 않으므로 분이 60을 넘을 수 있다.** BATTLE 중에는 실시간으로
  초가 흐르고(1턴 = 0.5초 = 인게임 60초, 즉 벽시계의 약 120배), CARD_PHASE /
  게임오버에는 멈춘다.
- **팀 점수** — 가운데, `font_size` 26. `팀0 합산 - 팀1 합산`
  (`BattleSim.team_score`). 5명 × 1.00k 로 시작하므로 개시값은 `5.00k - 5.00k`.
  죽어 있는 파일럿의 점수도 합산에 들어간다(점수는 전장에 서 있는지와 무관한
  누적 기록이다).

### 킬로그 (`KillFeed.gd`)
화면 **우측 상단**(상단 패널 밑단에서 8px 아래, y **156** = `TOP_PANEL_H` + 8)에 처치와 포탑 철거를 한
줄씩 쌓는다. 전장은 0.5초마다 저 혼자 흐르고 교전은 오버레이가 화면을 덮으므로,
**무슨 일이 일어났는지가 지나가고 나면 남는 곳이 없었다** — 팀 점수가 조금
벌어진 것 말고는.

한 줄은 왼쪽부터 `[막타][어시][어시][아이콘][피해자]` 이고, 모든 줄은
`feed_width()` 안에서 **오른쪽 정렬**된다 — 어시스트가 몇이든 피해자 칸이 언제나
같은 x 에 온다.

| 칸 | 폭 | 내용 |
|---|---|---|
| 막타 | `PORTRAIT_W` 96 | 가로로 긴 eye 컷. 이 줄의 주인 |
| 어시스트 ×0..4 | `ASSIST_W` 32 (= 1/3) | 높이는 같고 폭만 1/3 |
| 아이콘 | `ICON_W` 32 | 처치 = 교차한 칼, 포탑 철거 = 파열 |
| 피해자 | 96 | 파일럿이면 eye 컷, 포탑이면 실루엣 + `T1 좌` |

- **적립처는 두 곳뿐이다** — `BattleSim.mark_pilot_dead`(→ `_push_kill_feed`)와
  `BattleSim.score_turret_kill`. 전자는 **`_payout_kill_bounty` 보다 먼저**
  불려야 한다: 어시스트 명단이 `PilotData.damage_credit` 에서 나오는데 그 정산이
  장부를 비운다. 그래서 화면에 뜬 얼굴과 성장치를 받은 얼굴이 같은 표에서 나온다.
- **막타가 null 인 경로가 있다** — `SimulationCore._last_hitter` 는 매 턴 비워지므로
  타이밍에 따라 비어 들어온다. 그때는 가장 많이 때린 사람을 막타 자리에 세운다.
- **교전 중 처치는 보류된다** — `_submit` 이 `EngagePhaseManager.is_active()` 를
  보고 `_pending` 에 쌓고, 결과 대시보드를 닫는 `_on_dashboard_confirmed` 가
  `flush_pending()` 을 불러 `FLUSH_STAGGER`(0.25초) 간격으로 풀어놓는다. 아레나가
  화면을 덮고 있는 동안 띄워 봐야 아무도 못 본다.
- **줄은 위에서 밀고 들어온다** — 새 줄이 y 0, 나머지가 한 칸씩 아래로. `HOLD_SEC`
  4초 뒤 `FADE_SEC` 0.5초에 걸쳐 지워지고, `MAX_ROWS`(4)를 넘긴 가장 오래된 줄은
  아래로 밀려나며 페이드한다. 밀려난 줄은 `_rows` 가 아니라 **`_fading` 으로
  옮긴다** — 자리 계산에서는 빠져야 하지만 페이드는 계속 돌아야 한다(실측: `_rows`
  에서 빼기만 했더니 그 줄이 화면에 영원히 굳었다).
- **아이콘은 줄의 `_draw` 가 아니라 자식 `Glyph` 노드다.** Control 의 `_draw` 는
  자식보다 **먼저** 나가므로 줄 배경(반투명)과 포탑 칸 슬래브(불투명) 밑에 깔린다
  — 실측에서 칼은 흐려지고 포탑 실루엣은 아예 보이지 않았다.
- 4줄이면 아래끝이 y **334** 로 **전장 픽셀 상단(369) 위**에서 멈춘다(상단
  패널이 168 이던 시절에는 354 로 아슬아슬했다). `MAX_ROWS` / `ROW_STEP` 을
  많이 키우면 전장을 덮는다.

### update_hud() (per-turn)
- Calls `_update_cost_donuts(in_card_phase)` — pushes both sides' 작전 점수
  into their ring gauges and gates the player donut's flip / 턴 넘기기 press
  on `game_phase == CARD_PHASE` and `card_phase.can_end_card_phase()`.
- Calls `_update_pilot_strips(in_card_phase)` — sorts a **copy** of `_bs.pilots`
  by team and lane, pushes each five into its `PilotStrip`, gates **both** strips'
  hit buttons on 작전 단계, refreshes the team-score label, then lets
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

## 파일럿 스킬 표시 (`PilotStrip` 딤 + `PilotDetailPanel` 블록)

선수마다 붙는 고유 능력. 규칙과 25개 목록은 `../skill/README.md` 에 있고,
여기 적는 것은 **화면에 어떻게 나타나는가**뿐이다.

### 스트립 — 준비도 와이프 + 숫자
**초상화는 기본적으로 어둡게 덮여 있고, 스킬이 준비되는 만큼 왼쪽부터 밝아진다.**
채움 비율은 `PilotSkillSystem.progress(p)` 하나가 답한다 — 쿨타임은 경과 비율,
충전식은 활성화에 드는 충전 대비 비율, **패시브는 언제나 1.0**(누를 수 없는 대신
상시 적용이라 "아직 안 됐다"가 성립하지 않는다).

구현은 딤 한 장(`SKILL_DIM`, 검정 α 0.55)의 **왼쪽 끝을 밀어내는** 것이다:

```
filled = progress(p)
dim.position.x = px + _portrait_w * filled
dim.size.x     = _portrait_w * (1 - filled)
```

밝은 쪽에 사각형을 얹는 방식이 아닌 이유는 100% 에서다 — 얹으면 채움이 꽉 차도
한 겹이 남지만, 좁히면 폭이 0 이 되어 초상화가 **원래 색 그대로**가 된다.

딤은 `eye` 다음 · `rim` **앞**에 붙인다(형제 z-order = 자식 인덱스). 팀색
테두리가 딤 위에 남아야 어느 팀인지가 준비도에 따라 흐려지지 않는다.

숫자는 초상화 **오른쪽 위**의 작은 칸(`SKILL_BADGE_W_RATIO` 0.28 ×
`SKILL_BADGE_H_RATIO` 0.42, 검정 받침 α 0.55)이고 `badge_text(p)` 가 답한다 —
쿨타임이면 **남은 턴**(준비되면 빈칸), 충전식과 충전을 쌓는 패시브면 **충전 수**,
그 밖에는 빈칸이다. 색이 "지금 누를 수 있는가"를 말한다(금색 `SKILL_BADGE_READY`
/ 회청색 `SKILL_BADGE_WAIT`).

**아군 스트립에만 뜬다**(`_team != 0` 이면 `_apply_skill_state` 가 곧장 돌아온다).
스킬은 아군만 누를 수 있고, 적 칸까지 어둡게 덮으면 상대 얼굴이 스킬과 무관하게
흐려 보인다. 칸 크기가 두 스트립에서 다르므로 배지 칸도 **초상화 비율**로 잡는다
— 역할 태그가 그렇게 하는 것과 같은 이유다(고정 픽셀이면 작은 쪽에서 얼굴을
덮는다).

갱신은 `HudBuilder.update_hud` → `_update_pilot_strips` → `PilotStrip.refresh()`
경로 하나뿐이다. 전장 틱과 무관하게 상태가 바뀌는 경로(오브젝트 등장 · 처치
관여 · 포탑 파괴)를 덮으려고 `PilotSkillSystem.skill_state_changed` 가
`update_hud` 에 직접 연결돼 있다(`BattleSim._ready`).

### 상세 패널 — 인게임 탭 카드 줄 아래
스킬은 카드와 다른 종류의 자원이라 카드 격자에 섞지 않고 자기 블록을 갖는다.
지속 효과 썸네일에 한 칸으로 끼워 넣는 길도 있었지만, 그러면 "지금 쓸 수
있는가"를 알려면 썸네일을 한 번 더 눌러야 한다 — 스킬은 누르라고 있는 것이므로
버튼이 바로 보여야 한다.

```
파일럿 스킬 ──────────────────────────
공성전 (30pt, 금색)                충전식 (20pt, 우측)
포탑 파괴, 전투 개시 (19pt, 흐리게)
충전 5로 시작. 포탑 파괴 시 +1 충전 (최대 5) / 활성화: …   ← 자동 줄바꿈
충전 0 / 5 · 사용에 5 충전                                  ← 준비되면 초록
[            사용            ]   폭 STAT_W, 높이 68
```

* **배지는 타입 한 단어만**이다. 키워드까지 붙이면 긴 스킬에서 38% 폭을 넘겨
  오른쪽 정렬이 왼쪽부터 잘려 나간다 — 우측 정렬 `Label` 은 넘칠 때 정렬을
  포기하고 rect 왼쪽부터 그리기 때문이다(`godot_control_sizing_traps` 와 같은
  함정). 키워드는 자기 줄에 작고 흐리게 내려왔다.
* 설명문 높이는 **폰트에게 물어** 잡는다(`Font.get_multiline_string_size`).
  글자 수로 어림하면 한글/영문 혼용에서 한두 줄씩 어긋나 아래 버튼이 겹치거나
  뜬다.
* **패시브에는 버튼이 없다** — 누를 수 없는 것에 비활성 버튼을 두면 "언젠가는
  눌리는 것"으로 읽힌다. `_skill_use_btn` 이 null 로 남는다.
* `refresh()` 는 **상태 줄과 버튼 활성만** 다시 쓴다(`_refresh_skill_block`).
  트리를 다시 세우면 카드 노드가 매 갱신마다 인스턴스화된다 — 이 패널의 다른
  갱신 경로와 같은 규칙이다.
* **사용하면 패널이 닫힌다.** 결과가 손패 · 전장 · 스트립에 나타나는데 딤이 그
  위를 덮고 있으면 아무 일도 안 일어난 것처럼 보이고, 계략처럼 자기 오버레이
  (`CardSelectOverlay`, 레이어 10)를 여는 스킬은 이 패널(레이어 13) 뒤에 깔려
  아예 보이지 않는다.
