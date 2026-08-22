# UI Module

| File | class_name | Role |
|---|---|---|
| `HudBuilder.gd` | HudBuilder | Builds and updates the whole battle HUD |
| `CostDonut.gd`  | CostDonut  | 전략 포인트 ring gauge; the player's one doubles as the 턴 넘기기 button |
| `CardPileStack.gd` | CardPileStack | 덱 / 버린 더미 — 앞으로 누운 카드 뭉치 + 장수 |
| `PilotStrip.gd` | PilotStrip | 파일럿 5인 스트립 — 눈높이 초상화 + 체력 바 + 성장치. 상단(적) / 하단(아군) 두 벌, **양쪽 다 누르면 상세가 열린다** |
| `PilotDetailPanel.gd` | PilotDetailPanel | 파일럿 상세 모달 — 좌 전신 아트 2장(파일럿 ↔ 메크 전환) / 우 스탯 |
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
- **Top panel** (y=0, h=130) — 시간 · 팀 점수 한 줄 + 그 아래 **적 파일럿
  스트립**. Has an explicit opaque dark `StyleBoxFlat` so the AI hand peek
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
| 적 (`_enemy_strip`) | 상단 패널의 자식, `ENEMY_STRIP_RECT`(25, 42, 1030×122) | 초상화 190×79 | 눌러서 상세 패널 |
| 아군 (`_player_strip`) | 핸드 행 **아래**, `PLAYER_STRIP_RECT`(25, 1766, 1030×122) | 초상화 190×79 | 눌러서 상세 패널 |

**두 스트립은 이제 크기가 같다.** 적 쪽은 730×84(초상화 130×54)짜리 축소판이었는데,
같은 얼굴을 위아래에서 두 배 다른 크기로 보여 주니 상대가 누구인지가 아군만큼
읽히지 않았고 상대 성장치도 눈에 안 들어왔다 — 그 숫자는 내 것과 **나란히
비교하라고** 있는 것이다. 폭을 1030 으로 맞추면서 상단 패널이 130 → **168** 로
커졌고, 그 아래 사슬(상대 핸드 peek → 적 도넛)이 통째로 38px 내려갔다.

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

**입력 게이트**: `set_interactive_enabled(in_card_phase)` — 자기 작전 단계가
아니면 히트 버튼이 `disabled` 다. 히트 판정은 칸 전체를 덮는 투명 `Button` 이
가져간다(`Label` / `TextureRect` 는 클래스 기본이 `MOUSE_FILTER_IGNORE` 라
스스로 클릭을 받지 못한다).

### 파일럿 상세 패널 (`PilotDetailPanel.gd`)
스트립의 얼굴(**아군 하단 / 적 상단 양쪽**)을 누르면 열리는 **모달**. 자기
`CanvasLayer`(13)에 그리므로 버리기(10) / 대상 지정(11) / 열람·교전(12) 위다.

```
[풀스크린 딤 α 0.88]
├─ 아트 2장 (ArtHolder) — 앞 / 뒤 두 자리를 파일럿과 메크가 나눠 갖는다
│    앞: 밝게, 가로 중심 ART_FRONT_CENTER_X(320), 높이 ART_H(1400)
│    뒤: +ART_BACK_SHIFT_PX(400) 오른쪽, ×ART_BACK_SCALE(0.90), ART_BACK_TINT 로 딤드
│    둘 다 아래끝이 ART_BOTTOM(2010) — 화면(1920)보다 아래라 **하단이 잘린다**
├─ 우: 스탯   STAT_X 600, STAT_W 452, STAT_TOP 640 (받침 Panel 이 내용 높이에 맞춰 자람)
│    앞이 파일럿이면 — 인게임(체력 / 공격력 / 성장 / 명중·회피 / [일시 효과] / 라인)
│                    + 파일럿(라인전 · 메카닉 · 게임센스 · 한타 · 멘탈)
│    앞이 메크면   — 메크(기체명 / 체력 / 공격력 / 존재감)
└─ 하: [전환] [닫기]  y 1424 — 전환은 정보 블록의 **왼쪽 아래**
```

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
  건드리면 된다(`ART_SWAP_SEC` 0.22s).
- **전환 버튼이 앞뒤를 맞바꾼다** (`_on_swap_pressed`): 앞자리 · 뒷자리 · 딤 ·
  z-order(형제 순서) · 우측 스탯 블록이 한꺼번에 바뀐다. 스탯은 절 구성이 아예
  달라서 통째로 다시 세운다 — 헌 블록은 `queue_free` 만 걸면 이번 프레임까지
  그려져 글자가 겹치므로 **`remove_child` 를 먼저** 한다.
- **메크 아트 30장이 다 들어와 있다.** `MechImages.full_for(mech.id)` 가
  `res://resources/images/mech/{id}_full.png` 를 찾는다. 파일럿 아트와 달리 폭이
  제각각이 아니라 **1024×1024 고정 캔버스**라 어느 기체든 패널에서 같은 폭을
  차지한다(높이 정규화가 뻗은 무기까지 폭으로 환산하는 것을 막는다). 출처와
  id ↔ 기체 대응표는 `resources/README.md`.
  파일이 없을 때의 폴백은 그대로 살아 있다 — 같은 자리에 옅은 실루엣 슬래브 +
  기체명 플레이스홀더가 선다. 슬래브 알파는 0.30 이다 — 올리면 화면 절반짜리
  밝은 사각형이 되어 정작 앞에 선 파일럿보다 눈에 띈다.
- **정보 블록은 아래로 내려왔다**(STAT_TOP 170 → 640). 아트가 커지면서 화면 위쪽
  절반이 인물의 머리·상체 자리가 됐고, 스탯이 예전 자리에 남으면 얼굴을 덮는다.
  글자 뒤에는 받침 `Panel`(α 0.86)을 깐다 — 아트가 이 자리까지 올라오므로 글자만
  얹으면 일러스트 위에서 읽히지 않는다.
- **버튼 행의 y 는 고정이다.** 받침 높이를 따라가게 두면 메크 쪽 스탯이 훨씬
  짧아 전환/닫기가 위아래로 튄다.
- **보호막은 별도 행이 아니라 체력 뒤에 `(+N)` 으로 붙는다** — `120 (+30) / 200`.
  보호막은 그 자체로 읽는 숫자가 아니라 "지금 몇 대 더 버티는가"이고, 그 답은
  체력과 나란히 놓여야 나온다. 0 이면 괄호를 아예 안 적는다(빈 괄호는 노이즈다).
  예전의 `보호막` 행은 그래서 **삭제됐다** — 같은 정보를 두 번 두지 않는다.
- **명중 / 회피는 라인전 스탯이 먹은 값으로 적는다.** 안전한 파밍 / 공격적인
  라인전이 미는 것은 `PilotData.hit` / `evasion` 필드가 아니라 **판정 시점의
  배율**(`lane_stat_mod`)이라, 원본 필드를 그대로 찍으면 카드를 내도 이 줄이
  1 도 움직이지 않는다 — 화면에 "반영되지 않는" 것으로 보이는 원인이었다.
  판정과 **같은 함수**(`SimulationCore.lane_adjusted`)를 통과시켜 화면의 숫자와
  실제로 굴러가는 숫자를 하나로 묶고, 배율이 걸려 있을 때만 뒤에
  `(기본 50 / 50)` 을 덧붙인다.
- **카드가 건 일시 효과는 걸려 있을 때만 줄이 생긴다** — `라인전 스탯`
  (`lane_stat_mod`, `-10%  (7턴)`)과 `성장 획득`(`growth_rate_mult`,
  `+10%  (7턴)` / 완벽한 마무리는 `(작전 단계까지)`). 남은 수명은
  `_remain_txt(expire_turn, until_phase)` 한 곳이 만든다. 늘 `없음` 이라고
  적어 두면 정작 걸렸을 때 눈에 띄지 않으므로 **없으면 줄도 없다** — 받침
  `Panel` 이 내용 높이에 맞춰 자라므로 줄 수가 변해도 레이아웃이 깨지지 않는다.
- **`성장` 행은 공격력과 최대 체력을 함께 적는다**(`공 +46% · 체 +11%`). 둘은
  4배 차이로 **다르게** 자라므로(`GROWTH_ATK_PER_SCORE` vs `GROWTH_HP_PER_SCORE`)
  한쪽만 적으면 다른 쪽이 안 자란 것처럼 읽힌다. 이 행은 성장치에서 파생된
  값이고, 카드가 미는 `성장 획득` 배율과는 **다른 것**이다 — 이름이 비슷해
  헷갈리기 쉬운 자리라 둘을 나란히 둔다.
- **`refresh()` 가 열려 있는 패널의 스탯을 지금 값으로 다시 세운다**
  (`update_hud` 마다, `close_if_phase_left` 바로 뒤). 패널은 모달이라 열려 있는
  사이에 카드가 나가지는 않지만, 값이 바뀌는 자리는 전부 `update_hud` 를
  지나므로 이 한 줄이 "화면의 숫자는 언제나 지금 값"을 보장한다. 아트와 앞뒤
  자세는 건드리지 않는다 — 전환 트윈이 끊긴다.
- **값 라벨에는 `clip_text = true` 가 필수다.** 오른쪽 정렬 `Label` 은 글자가
  rect 보다 넓으면 정렬을 포기하고 rect 왼쪽부터 그려서 **오른쪽으로 넘쳐 화면을
  벗어난다**(실측: "아웃게임 데이터 없음" 이 화면 밖에서 잘렸다).
- 아웃게임 스탯은 `BattleSim.player_data_for(pilot)` 로 찾는다 — `pilots` 배열의
  인덱스(0..4 = 팀0, 5..9 = 팀1)를 `match_ctx` 의 두 로스터에 그대로 대응시키는
  방식이라 **`pilots` 를 재정렬하면 이름과 스탯이 어긋난다**. 단독 실행이나
  INTL 파일럿은 null → "데이터 없음". 적 파일럿이 열리는 것도 이 대응 덕이다.
- 열려 있는 동안 **누른 쪽 팀의 스트립만 숨긴다**(`HudBuilder.set_strip_visible(team, on)`).
  딤 위로 스트립만 남으면 지금 무엇을 보고 있는지가 흐려지고, 딤 아래로 넣으면
  방금 누른 얼굴이 어두워져 연결이 끊긴다. 반대 팀 스트립은 그대로 둔다 —
  딤에 가려질 뿐이고, 치우면 무엇이 사라졌는지가 더 헷갈린다.
- `_root` 에 **앵커 프리셋을 걸지 않는다.** `CanvasLayer` 아래의 `Control` 은
  full-rect 앵커를 해석해 줄 부모 rect 가 없어 크기가 0 으로 남고, 프리셋만
  걸어 두면 "`_ready` 뒤에 size 가 덮어써진다"는 경고가 남는다. 크기는 명시한다.
- **작전 단계를 벗어나면 강제로 닫힌다**(`close_if_phase_left`, `update_hud`
  마다 호출). 열어 둔 채 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.

### 상단 패널 (시간 + 팀 점수 + 적 스트립)
`TOP_PANEL_Y` 0 / `TOP_PANEL_H` **168**. **높이는 적 스트립이 정한다** — 헤더
줄(y 4..38) 아래 `ENEMY_STRIP_RECT`(42..164)가 앉고 거기에 4px 를 더한 값이다.
그리고 그 아래가 사슬이다: 이 패널이 상대 핸드 peek 의 윗부분을 가리는
가림막이고(`AI_HAND_TOP_Y` = `TOP_PANEL_H − 50`, 카드 아래 49px 만 삐져나온다),
peek 카드 아래 끝(y 217)에서 `DONUT_AI_HAND_GAP` 만큼 띄운 자리가 적 도넛(아래
끝 y **349**)이며, 그 바로 아래가 전장 픽셀 상단(y **369**)이다. **패널을 키우면
`AI_HAND_TOP_Y` 도 같은 양만큼 내려야 한다** — 안 그러면 peek 이 패널 뒤로 통째로
숨는다. 예전 130 은 적 스트립이 축소판이던 시절의 값이고, 지금 도넛과 전장 사이
여유는 **20px 뿐이다** — 더 키우려면 peek 이 보이는 양이나 `DONUT_AI_HAND_GAP` 을
깎아야 한다. 그 사이의 빈 띠를 **카드 설명 상자**가 쓴다 —
`CardPhaseManager.DESC_BOX_TOP`.

- **시간 라벨** — 좌측(x 20), `font_size` 18. `MM:SS` (`get_elapsed_ingame_seconds`).
  **시는 표시하지 않으므로 분이 60을 넘을 수 있다.** BATTLE 중에는 실시간으로
  초가 흐르고(1턴 = 0.5초 = 인게임 60초, 즉 벽시계의 약 120배), CARD_PHASE /
  게임오버에는 멈춘다.
- **팀 점수** — 가운데, `font_size` 26. `팀0 합산 - 팀1 합산`
  (`BattleSim.team_score`). 5명 × 1.00k 로 시작하므로 개시값은 `5.00k - 5.00k`.
  죽어 있는 파일럿의 점수도 합산에 들어간다(점수는 전장에 서 있는지와 무관한
  누적 기록이다).

### 킬로그 (`KillFeed.gd`)
화면 **우측 상단**(적 스트립 밑단에서 8px 아래, y 176)에 처치와 포탑 철거를 한
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
- 4줄이면 아래끝이 y 354 로 **전장 픽셀 상단(369) 바로 위**에서 멈춘다.
  `MAX_ROWS` / `ROW_STEP` 을 키우면 전장을 덮는다.

### update_hud() (per-turn)
- Calls `_update_cost_donuts(in_card_phase)` — pushes both sides' 작전 점수
  into their ring gauges and gates the player donut's flip / 턴 넘기기 press
  on `game_phase == CARD_PHASE` and `card_phase.can_end_card_phase()`.
- Calls `_update_pilot_strips(in_card_phase)` — sorts a **copy** of `_bs.pilots`
  by team and lane, pushes each five into its `PilotStrip`, gates **both** strips'
  hit buttons on 작전 단계, refreshes the team-score label, then lets
  `PilotDetailPanel.close_if_phase_left()` close the modal if the phase moved on
  and `PilotDetailPanel.refresh()` re-seat the stat rows of one that survived.
- Calls `update_time_label()` (also called every frame from `_process`).

### update_time_label() (per-frame)
Pulls `_bs.get_elapsed_ingame_seconds()` and formats as `%02d:%02d`. Called
from `BattleSim._process` every frame so the clock visibly ticks even when no
HUD-state event fires.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.
