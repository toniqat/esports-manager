# Card Phase Module

| File | class_name | Role |
|---|---|---|
| `Card.gd` | Card | 카드 한 장의 시각 노드 |
| `CardPhaseManager.gd` | CardPhaseManager | 작전 단계 전체 — 덱 / 핸드 / 카드 효과 |
| `CardSelectOverlay.gd` | CardSelectOverlay | 버리기:N / 찾기:N / 보존:N 모달 픽 |
| `CardTargetingOverlay.gd` | CardTargetingOverlay | 카드 선택 = 대상 지정 오버레이 |
| `CardPileViewer.gd` | CardPileViewer | Deck / Discard 목록 열람 (읽기 전용) |
| `AiCardPlayer.gd` | AiCardPlayer | AI 카드 사용 애니메이션 |

## CardPhaseManager.gd
`extends Node` — child of BattleSim.

Manages the **작전 단계** (card draw / play overlay) that gates each battle turn.
The cost label is surfaced as "작전 점수" in the HUD; one tick of `simulate_turn`
is referred to as "1분".

### Turn flow
- `do_battle_turn()` — calls `_bs.sim_core.simulate_turn()`, accumulates 작전 점수,
  draws cards, then hands the tick to whichever side's own 점수 has reached
  `PHASE_THRESHOLD`. After the AI
  draws, `_bs.hud.update_ai_hand_visuals()` reflows the face-down peek row
  under the score panel. It also re-runs `highlight_affordable_cards()` every
  tick so the 부활 countdown printed on each card face stays current.

#### 카드 경제 게이트 (`ECONOMY_START_TURN`)
전략 점수 회복과 자동 드로우는 **`ECONOMY_START_TURN`(game_config, 4)턴부터**
돈다. 그 전에는 두 카운터를 아예 굴리지 않으므로 게이트가 열리는 턴에 밀린
회복이 한꺼번에 터지지도 않는다. 초반 몇 턴은 개시 손패 5장과 블루 선점 1점만
들고 순수 라인전으로 보내라는 규칙이다.

게이트가 걸리는 것은 **카드 경제뿐**이다:

| 항목 | 게이트 |
|---|---|
| 개시 손패 (`INITIAL_HAND_SIZE`) · 블루 선점 (`BLUE_COST_HEAD_START`) | ❌ 0턴에 그대로 들어간다 |
| `COST_RECOVERY` / `CARD_DRAW_INTERVAL` | ✅ `ECONOMY_START_TURN` 부터 |
| 성장 (`GROWTH_PER_TURN`) | ❌ 1턴부터 |

`simulate_turn()` 이 자기 초입에서 `turn_count` 를 올리므로 게이트를 보는 시점의
`turn_count` 는 **방금 끝난 턴의 번호**(1-based)다. 카운터는 개시 시
`INTERVAL - 1` 로 놓여 있어 게이트가 열리는 첫 턴에 곧바로 발동한다.

**실측** (standalone, PHASE_THRESHOLD 8 · COST_RECOVERY_INTERVAL 2 · 블루 선점 1):
첫 작전 단계가 **16턴**에 `player 8 / ai 7` 로 열린다 — 회복이 4·6·8·10·12·14·16턴에
7회. 게이트 이전에는 13턴이었다.

#### 두 쪽이 각자 자기 점수로 턴을 갖는다
The two sides' turns are **independent**. `do_battle_turn` closes by asking
`_next_turn_side()` who gets this tick — `1` → `await _run_ai_turn()`,
`0` → `start_card_phase()`, `-1` → refresh the hand / HUD and keep ticking —
and stamps the answer into `_last_turn_side`.

The AI turn used to be bolted onto the end of the player's — `end_card_phase`
announced "상대 차례" and ran the AI loop unconditionally, so passing the turn
flashed the banner even when the opponent was at 0 점 and did nothing. Now the
banner marks a real handover.

##### `_next_turn_side()` — 블루 우선 + 교대
Two lines decide it:

1. 한 쪽만 준비됐으면 그 쪽.
2. 양쪽 다 준비됐으면 **직전에 차례를 잡지 않은 쪽**, 아직 아무도 잡은 적이
   없으면 **블루**(`BattleSim.blue_team`).

Line 2 carries two separate jobs.

**같은 점수면 블루 먼저.** 개시 시점에는 `_last_turn_side == -1` 이라 블루가
무조건 선을 잡는다. 보통은 블루의 점수 선점(`BattleSim.BLUE_COST_HEAD_START`,
아래 개시 상태)만으로 블루가 문턱에 먼저 닿지만, 카드로 점수를 쓴 뒤 양쪽이
같은 틱에 다시 닿는 경우의 타이브레이크는 이 규칙이 맡는다.

**굶주림 방지.** 예전 코드는 여기서 AI 를 **무조건 먼저** 검사해 굶주림을
막았다: 0코스트 카드만 내고 턴을 넘긴 플레이어는 다음 틱에도
`player_cost >= PHASE_THRESHOLD` 라 자기 단계에 재진입하고, 그렇게 AI 를 영원히
굶길 수 있었기 때문이다. 블루 우선으로 뒤집으면 그 방어가 사라지므로 교대
규칙이 그 자리를 대신한다 — 방금 차례를 잡은 쪽은 상대가 한 번 잡기 전까지
다시 잡지 못한다. 상대가 문턱 아래면 교대할 상대가 없으므로 연속 진입은 그대로
허용된다(규칙 1). `_last_turn_side` 는 `build_starter_decks` 가 새 판마다 -1 로
되돌리는 이 규칙의 유일한 상태다.

준비 판정이 비대칭인 것은 기존 동작 그대로다: AI 는 낼 수 있는 카드가 손에
있어야 준비된 것으로 치고(`_ai_turn_ready`), 플레이어는 점수만 차면 진입한다 —
낼 게 없는 손은 `can_end_card_phase` 의 탈출구가 통과시킨다.

### 개시 상태 (진영 + 개시 손패)
- **블루가 선을 잡는다.** `BattleSim.blue_team` (0 = 플레이어 팀) 은
  `match_ctx.player_side` 에서 유도되고, `BattleSim.seed_side_costs()` 가 그 팀의
  작전 점수를 `BLUE_COST_HEAD_START`(1) 로 심는다. COST_RECOVERY 는 양 팀에 같은
  틱에 같은 양이 들어가므로 그 차이는 그대로 유지되고, 블루가 항상 문턱에 먼저
  닿는다. 밴픽에서 후밴/후픽을 하는 대가다 — 지금은 `MatchFlow` 가 플레이어를
  항상 BLUE 로 고정한다.
- **개시 손패는 `INITIAL_HAND_SIZE`(5)장**. `build_starter_decks` 가 덱을 섞은
  직후 `_deal_initial_hands()` 로 양 팀에 돌린다. 이게 없으면 양 팀 다 빈 손으로
  시작해 첫 차례까지 자동 드로우만으로 손이 차므로, 첫 작전 단계를 상한에 한참
  못 미치는 손으로 맞게 된다. 실측: 개시 5장 + 13틱까지의 자동 드로우 7회 =
  **첫 차례에 정확히 12장**(= `MAX_HAND_SIZE`).

### Hand overflow (BATTLE auto-draw only)
`MAX_HAND_SIZE` is **12**. The auto-draws that tick by while 작전 점수 climbs
back to `PHASE_THRESHOLD` — i.e. the stretch when it is *not* the player's turn
— always draw, even on a full hand, and `_trim_hand_overflow(is_player)` then
discards from the **front** of the hand (oldest first) until it is back at 12.
Both sides run the same rule; only the player side despawns card nodes and
relayouts. The old behaviour was to skip the draw when the hand was full, which
stalled the deck and left the same dead hand sitting there for the whole wait.

Cards drawn by a card effect **during** 작전 단계 are exempt — that is the
player's own turn, so the hand is allowed over the cap and nothing is thrown
away mid-turn. `_effect_draw` and `_on_search_overlay_complete` therefore carry
**no** `MAX_HAND_SIZE` guard (only an exhausted deck+discard stops them); the
first auto-draw after the turn ends is what trims the excess.

**계획 중시의 보존은 이 트림에서만 의미가 있다.** `BattleSim.preserved_cards_p/ai`
에 올라간 카드는 `_trim_hand_overflow` 가 건너뛴다 — 그게 `preserve:N` 의 유일한
효과다. 카드 효과에 의한 **강제** 버리기(재고 / 완벽한 마무리 / 과감한 정리 /
솔로 퍼포먼스)는 보존을 보지 않는다. 루프가 `pop_front()` 가 아니라 인덱스
스캔인 것은 보존 카드가 손패 앞쪽에 있어도 멈추지 않기 위해서이고, 손패가 통째로
보존되는 극단(최대 2장이라 실제로는 불가능)에서도 무한 루프가 나지 않는다.
`_prune_preserved` 가 매 트림마다 손패를 떠난 항목을 걷어 유령 참조를 막는다.
- `start_card_phase()` — transitions to CARD_PHASE, resets
  `_bs.cards_played_this_phase` so the 턴 넘기기 face of the 전략 포인트 도넛
  starts disabled for the new turn.
  Awaits `HudBuilder.play_turn_announce(true)` so the "당신의 차례" banner
  sweeps in / holds / fades out before the player can interact; the player
  hand stays dimmed for that whole interval via `_apply_hand_dim_state()`.
- `can_end_card_phase()` → bool — true once **`cards_played_this_phase > 0`**,
  i.e. the player has resolved at least one card this 작전 단계.
  `_has_any_playable_card()` is a second escape hatch: a hand with nothing
  playable at all (every card unaffordable, 시전자 down, or no legal target)
  passes straight through, because BATTLE is paused during 작전 단계 so the
  hand can never change on its own.
  Also blocked while `_player_turn_announce_in_progress`, while overlays own
  the screen, and while the AI play loop is in flight.

  **Why plays and not points.** The gate used to be
  `player_cost < card_phase_entry_cost` (a cost snapshot taken on entry), which
  deadlocked the phase outright: 9 of the 28 cards cost 0 (임기응변 / 정밀 이동 /
  복귀 / 집중 …) and 조정 *raises* the total, so a hand whose only playable
  cards were free could never lower the cost, the 턴 넘기기 face never enabled,
  and nothing could unstick it — BATTLE does not tick during 작전 단계, so no
  new card ever arrives. Counting resolved plays keeps the "do something on
  your turn" intent without the trap. `card_phase_entry_cost` is gone.
- The counter is bumped in `_finalize_pending_play()`, not `_play_card_direct()`,
  so a card rolled back out of a 버리기 / 찾기 overlay (`_on_overlay_cancel`
  restores the pre-play snapshot) doesn't unlock 턴 넘기기 on a play that never
  happened. AI plays never touch it — `_pending_play.is_player` gates the bump.
- `end_card_phase()` — the player's turn only: drops the selection, runs
  `recall_sys.process_phase_end_recalls()` (HP threshold + out-of-position
  card-displaced pilots) and returns to BATTLE. **No banner, no AI plays** —
  it is fully synchronous now. The opponent takes its turn on its own schedule
  (see 상대 차례 below). Also zeroes `kill_bounty_p` — 계획 살인's reservation
  only lives for the phase that placed it.

#### 작전 단계 진입 정산 (`_apply_phase_entry_carryovers`)
지연 효과 셋이 자기 팀의 **다음 작전 단계 진입 시점**에 한꺼번에 정산된다.
플레이어는 `start_card_phase`, AI 는 `_run_ai_turn` 이 부른다.

| 상태 | 카드 | 정산 |
|---|---|---|
| `preserved_cards_*` | 계획 중시 | 통째로 비운다 — 보존은 BATTLE 구간 한 번만 버틴다 |
| `next_phase_strategy_*` | 아드레날린 | 작전 점수에 더한다(음수 가능, `maxi(0, …)` 로 바닥 고정) |
| `growth_until_phase` | 완벽한 마무리 | `SimulationCore.clear_growth_until_phase(team)` 가 팀 전원의 성장 배율을 1.0 으로 되돌린다 |

### 상대 차례 (`_run_ai_turn`)
- `_ai_turn_ready()` — `ai_cost >= PHASE_THRESHOLD` **and** at least one card
  in `ai_hand` the AI can pay for, tested with the same
  `effective_cost_for(cd, false) <= ai_cost` filter
  `AiCardPlayer.run_ai_plays` uses. The second half is the mirror of the
  player's `_has_any_playable_card` escape hatch: an AI sitting on a full score
  with an empty or unaffordable hand would otherwise re-announce "상대 차례"
  every tick and play nothing. Because the filter matches, a turn that starts
  always consumes at least one card, so the condition can't hold twice in a row
  without a draw in between.
- `_run_ai_turn()` — sets `_ai_play_in_progress`, awaits
  `play_turn_announce(false)` (the "상대 차례" banner), awaits
  `AiCardPlayer.run_ai_plays()`, then runs the same
  `process_phase_end_recalls()` sweep the player's turn gets.
  **It never changes `game_phase`** — the AI turn runs *inside* BATTLE.
- `is_ai_turn_active()` — public read of `_ai_play_in_progress`. Because
  `game_phase` stays BATTLE, every "is the sim running?" check has to consult
  it too: `BattleSim._process` holds the auto-tick, and
  `get_elapsed_ingame_seconds` freezes the MM:SS clock. `do_battle_turn` also
  early-returns on the flag as a backstop.
- An AI `engage` / `duel` card opens the arena from BATTLE, so
  `EngagePhaseManager` restores **the phase it captured on entry**
  (`_phase_before`) instead of hard-coding CARD_PHASE — otherwise the field
  would be stranded in 작전 단계 once the AI's turn ended.

### Hand dim driver
`_apply_hand_dim_state()` toggles `Card.set_dimmed(true|false)` on every
player hand node based on `_is_player_input_blocked() or game_phase != CARD_PHASE`.
That covers BATTLE auto-tick, the player turn-start banner, the AI run loop,
and any active modal overlay. `Card.set_dimmed(true)` darkens the modulate,
suppresses hover brighten, and ignores `_gui_input` clicks; `set_dimmed(false)`
restores `Color.WHITE`. `highlight_affordable_cards()` always tail-calls
`_apply_hand_dim_state()` so every overlay-close path that funnels through it
re-evaluates the dim state.

### Card management
- `build_starter_decks()` — 10-card decks built from `cards` table; calls
  `update_deck_discard_labels()` to seed the visible counters.
- `draw_card(is_player)` → CardData — pops from deck. If the deck is empty it
  shuffles the discard pile back in *first*. For the player, draws update the
  Deck / Discard labels: a normal draw snaps; a reshuffle draw kicks off a
  parallel tween (`_animate_reshuffle_counts`) that drains the discard count
  to 0 while the deck count grows over `BS_RESHUFFLE_TWEEN_DUR` (~0.55s).
- `spawn_card_node(cd)` — instantiates a player Card.tscn into `_bs.canvas`. The
  AI hand is logical-only — no card backs are spawned for the enemy.
- **The fan is one circle.** Every card centre rides a circle of radius
  `BS_HAND_FAN_RADIUS` (3200px) whose pivot sits directly *below* the row, and
  both readings of the fan come off it: a card's tilt is its angle on the circle
  (`_fan_angle`), its vertical offset is how far the circle has dropped from its
  apex at that angle (`_fan_arc_drop`). The apex is the middle of the row, so
  **the centre card is the highest and the hand curves down toward both ends** —
  a hand held from underneath, not a valley. Measured at 12 cards: the
  outermost cards tilt ±6.7° and hang 21.4px below the middle pair; a 5-card
  hand splays ±6.2° / 18.5px (its spacing is uncompressed, so it's just as wide).
  Shrink the radius for a deeper curve.
  > The 12-card figures quoted throughout this section are the **live** worst
  > case again: `MAX_HAND_SIZE` is 12, and the 개시 손패 rule puts a full 12 in
  > hand on the very first 작전 단계. (They were measured at 12, then spent a
  > while as a hypothetical while the cap sat at 8.) The 8-card figures also
  > quoted below are just a mid-size sample, not the cap.
- `slot_spacing(total)` — uniform centre-to-centre spacing.
  `Card.CARD_W + BS_HAND_CARD_GAP` until the natural span exceeds
  `BS_HAND_WIDTH`; from then on it compresses so the row always fits the
  fixed-width slot (172px up to 5 cards → 67.5px at 12).
- `slot_center_dx(index, total)` — signed distance from
  the middle of the row to the card's centre. Everything else (X slot, tilt, arc
  drop) is derived from this one number, so the three can never disagree.
  **There is no push-free variant.** A card has exactly one slot; the focus
  card's own push is 0 by construction, so the lifted-card poses read the same
  slot as everyone else (see 핸드 포커스 below).
- `slot_position(index, total)` — top-left viewport
  position: `BS_HAND_CENTER + (dx, _fan_arc_drop(dx))`. `BS_HAND_CENTER.x` is
  set in `BattleSim._ready` to *the top-left a centred card would take*
  (`viewport_cx − CARD_W/2`), which is why a centre-to-centre `dx` adds to it
  directly. Resting row for ≥8 cards: x=89..991.
- `slot_rotation(index, total)` — `_fan_angle` of the
  same `dx`. Cards pivot around their own centre (`pivot_offset` set in
  `spawn_card_node`), so the slot X positions are unaffected.

##### 핸드 포커스 — who does the row spread around?
- `_push_focus_card()` — **the single home of that question**: the *selected*
  card if there is one, else the card under the cursor. A selected card is the
  hand's focus in exactly the same way a hovered one is, so it opens the row the
  same way and keeps it open while the cursor walks over to the description box.
  Every other guard reads this one accessor instead of testing `_selected_card`
  itself. `_hovered_hand_card()` supplies the cursor half — a `_hovered_card`
  fast path validated against `Card.is_hovered()` and the hand array, so a freed
  card or a hover that arrived while a modal owned the screen can't leave the
  row stuck open.
- `hover_push_offset(index, total)` / `_hover_push_amount(total)` — the spread
  that keeps the focus card's 1.2× enlargement from covering its neighbours.
  **The hand's overall width never changes.** The two outermost cards are
  anchors and hold still; everything between them slides away from the focus by
  `_hover_push_amount` scaled by a falloff that reaches exactly 0 at the end of
  its own side, so the row doesn't grow — it *redistributes*. Each side ramps
  against its own distance to the end of the row, so an off-centre focus still
  pushes both of its neighbours nearly the full amount.
  `ramp = 1 − (steps / steps_to_end) ^ BS_HAND_HOVER_FALLOFF_POW` (2.0): the
  squared curve holds the near neighbours close to full push and concentrates
  the give-way in the outer cards, rather than bleeding it evenly across the
  block (a linear ramp would rob the immediate neighbours, which is exactly the
  clearance a packed hand needs most). The amount itself is *solved*, not fixed:
  the focus card covers `CARD_W × HOVER_SCALE / 2` = 96px to either side, so its
  neighbour's centre has to sit 96 + `BS_HAND_HOVER_MIN_STRIP` (32) = 128px away
  to leave a clickable sliver. The resting spacing pays part of that and pays
  less the more cards the hand holds, so the push is the shortfall — **it grows
  with the hand size**: `BS_HAND_HOVER_PUSH` (28px) floor up to 8 cards, 60.5px
  at 12 cards. No edge clamp is needed, since anchored ends can't reach
  the screen edge. Measured at 12 cards with the focus in the middle: the row
  spans 89..831 whether open or closed, the two neighbours take ∓58.9 / ±58.1px,
  the falloff runs 58.9 → 53.8 → 45.4 → 33.6 → 18.5 → 0, and the tightest
  adjacent gap anywhere in the row is 45.7px — nothing crosses.
- `relayout_hand(nodes, skip = null)` — tweens every card to its
  `slot_position` / `slot_rotation`, then records the focus it laid out for in
  `_reflow_focus`.
- **A hover reflow lays out the incoming focus card too** — `_apply_hand_reflow`
  skips only `_selected_card` (whose lifted pose `_select_card` owns), never the
  hovered card. The hovered card's slot under the *new* focus is its resting slot
  (own push = 0), but it is almost never already sitting there: the *previous*
  focus had pushed it aside. Skipping it left it stranded at that stale offset,
  so a card hovered right after its neighbour sat displaced by up to a full push
  (+26.9px at 8 cards, +59.8px at 12 cards) and then slid sideways on its
  way up when clicked — the same card hovered with no prior focus did neither.
  Skipping was safe for `scale` (`tween_to` doesn't touch it) but never for
  `position`. Verified: hovering B directly and hovering B right after A now
  agree to 0.0px, as do selecting B along either path, selecting a card while
  another is already selected, and clicking in the same frame as the hover
  (before the deferred reflow has run).
- **Never tween `global_position` on a Card.** `Control.global_position` is the
  *rotated-and-scaled top-left corner*: the getter returns
  `position + pivot − R·S·pivot` and the setter inverts that with whatever
  rotation/scale the node holds at the instant of the write. With hover scaling
  in play, the same slot value written at scale 1.2 lands ~15px right and ~22px
  below the same value written at scale 1.0 — which is what made the lifted card
  drift up-right and the deselected card sink under its slot row.
  `Card.tween_to` converts the viewport-space slot through
  `Card.layout_position_from_global()` and tweens plain `position` instead; a
  card's visual centre is always `position + pivot_offset`, invariant under both
  rotation and scale.
- `update_deck_discard_labels()` / `_refresh_count_labels()` — snap visible
  counts to current player_deck / player_discard sizes.
- `highlight_affordable_cards()` — re-reads every visible card's playability:
  `set_affordable(eff <= player_cost)`, `set_respawn_turns(respawn_turns_for(cd))`,
  and `update_displayed_cost(eff)`. Tail-calls `_apply_hand_dim_state()` and
  `_refresh_confirm_button()`, so every path that funnels through it also
  re-evaluates the hand dim and the 확인 button.
- `respawn_turns_for(cd)` / `card_is_playable(cd)` — the two playability
  questions. `respawn_turns_for` returns 0 while the 시전자 is alive and
  **at least 1** while they are down (never 0 for a dead pilot, so the card
  can't flicker back to playable on the tick the timer hits 0).
  `card_is_playable` = 시전자 alive **and** affordable **and**
  `card_has_valid_targets`.

### Card interaction (click-to-select + description box)
- Hand row: cards span ~y=1500..1720 at-rest (CARD_H=220), centred on the
  viewport. `BS_HAND_AREA_MARGIN` (130px) on each side is reserved for the
  Deck / Discard count labels and shrinks the inner `BS_HAND_WIDTH`, which is
  then widened by `BS_HAND_WIDTH_SCALE` (1.10) → **902px** on a 1080-wide
  screen (row spans x=89..991). That eats into the label gutters, so
  `HudBuilder._build_hand_indicators` derives its gutter from the real hand
  edge instead of `BS_HAND_AREA_MARGIN` and scales the label font down to fit
  (130→89px gutter, font 22→20).
- **Floating shadow** (`Card._build_shadow` / `_refresh_float_state`): every
  player card owns a `DropShadow` Panel parked at child index 0, so it draws
  under `CardBack` / `CardFront` and inherits the card's fan rotation and
  hover scale for free. The gap between card and shadow encodes height:
  `SHADOW_REST_OFFSET` (10px down, tight `shadow_size` 6, alpha 0.50) for a
  card resting near the table, `SHADOW_HOVER_OFFSET` (24px, blur 26, alpha
  0.36) while hovered, `SHADOW_SELECTED_OFFSET` (32px, blur 32, alpha 0.32)
  while lifted. The slab's own `bg_color` alpha also drops from 0.8 → 0.55
  on the blurred states so a high shadow reads as a soft pool, not a black
  rectangle trailing the card. Non-player cards (AI hand peek, 찾기 grid)
  keep the shadow hidden — `setup()` gates `_shadow.visible` on
  `is_player_card`.
- **Hover** (`on_card_hovered` / `on_card_unhovered`, driven by the hand hit
  layer — see 핸드 히트 레이어 below): face-up player cards
  brighten via a `modulate` tween and scale up to `Card.HOVER_SCALE` (1.2×)
  around their own centre, coming "closer to the screen" — the shadow drops
  to its hover pose at the same time. All three reactions run on
  `HOVER_EASE` / `HOVER_TRANS` (cubic `EASE_OUT` — quick jump, slow settle)
  over `HOVER_TWEEN_DURATION` 0.04s / `SHADOW_TWEEN_DURATION` 0.05s. The
  hovered card is also
  moved to the **top of the scene-tree** so it draws above its neighbours; on
  unhover the canonical hand order is restored. Moving the cursor from one card
  to another re-spreads the row around the new one every time. While a card is
  selected the hover has no effect on the layout — not through a special-case
  guard, but because `_push_focus_card()` keeps answering the selected card, so
  `_apply_hand_reflow` finds nothing changed and no-ops (the `_hovered_card`
  pointer is still tracked throughout, ahead of every guard, so the row is
  correct the instant the selection drops). `Card.tween_to` treats
  its `target_scale` argument as the *layout* scale (`_base_scale`) and leaves
  `scale` **entirely alone** unless that layout scale actually changes (no
  caller changes it today). `scale` therefore has exactly one owner —
  `_refresh_float_state`. Two tweens racing over it is what used to strand a
  hovered card at 1.0: a relayout firing mid-hover captured the hover factor
  from a transient `_is_hovered` and killed the hover tween on its way past.
- **Select** (`on_card_clicked` → `_select_card`): pressing a card pops it out
  by `Card.PRESS_LIFT` (40px) **along its own up-axis while keeping its fan
  rotation** — `slot + Vector2(0, -PRESS_LIFT).rotated(slot_rotation(...))`, so
  a card on the left half of the fan travels up-left and one on the right half
  travels up-right: straight out of the fan, the way a card is drawn from a real
  hand, never plain screen-up-and-right. Sideways travel is
  `PRESS_LIFT × sin(fan angle)` = ±4.6px on the outermost card of a 12-card hand;
  tighten `BS_HAND_FAN_RADIUS` if the splay should read more strongly.
  **Selecting makes the card the row's focus, so `_select_card` reflows the whole
  row around it before posing the lift** — the neighbours give way exactly as they
  would on a hover, and because the focus card's own push is 0, its pushed slot
  *is* its resting slot: lift and drop are exact opposites with no push-free
  special case anywhere. `_select_card` and `_show_description_box` read that one
  slot.

  > This is the fix for a real bug. The lifted pose used to be computed
  > *push-free* while the row on screen was still spread around whichever card
  > the cursor had opened it with — hover reflow is deferred to idle, so a click
  > landing in the same frame as the `mouse_entered` posed the card off a layout
  > that had not happened yet. The card visibly slid sideways on the way up
  > (toward the first-hovered card, ~48–60px in a 12-card hand), and since
  > deselect reflowed off the *new* focus, the sideways travel never came back —
  > the card only dropped vertically. Reflowing inside `_select_card` closes the
  > gap: both orderings end at the same layout.

  Selecting also pins the card to the top of the hand (via the
  `relayout_hand` → `_reorder_hand_nodes` pass), flips `Card.set_selected(true)`
  (→ tallest shadow), and spawns the description box.
  **Re-clicking the selected card deselects it** (same path as
  an outside click; blocked only while a 전투 개시 PREVIEW is pending, which must
  be resolved through the overlay's 취소 button). Clicking a different card swaps
  the selection — the previous one is dropped out of its lifted pose and re-seated
  by that same row-wide reflow, now spread around the new focus.
  `deselect_current_card` reflows the **whole** row, the dropped card included
  (it does *not* skip it): one pass places every card off the same focus state,
  so the returning card can't land on a slot that disagrees with the row it's
  landing in. If the cursor is still on it, it stays enlarged and becomes the
  focus, so its neighbours hold the spread they already had — the card just
  comes straight back down.
- **Hand z-order** (`_reorder_hand_nodes`): canonical order is oldest-lowest /
  newest-on-top, then the **selected card — or, failing that, the card under the
  cursor — is raised above all of them**. That last clause is what keeps a
  hovered card above its right-hand neighbours right after a deselect, when the
  canonical order alone would bury it.
- **Hover reflow is deferred and coalesced** (`_queue_hand_reflow` →
  `_apply_hand_reflow`). This is not optional polish — `move_child` re-runs
  mouse picking and makes the engine emit `mouse_entered` / `mouse_exited`
  **synchronously, from inside the move**, so reflowing straight out of a hover
  signal re-enters itself, trips
  `Parent node is busy setting up children, move_child() failed`, and strands
  half-killed tweens (a hovered card stuck at scale 1.0, its neighbour frozen
  at 0.98). Three guards keep it settled:
  1. `_hand_reflow_queued` + `call_deferred` — the exit on the old card and the
     enter on the new one arrive in the same frame and collapse into one pass
     that runs at idle, outside the locked move.
  2. `_reflow_focus` — a pass whose focus card matches the layout already on
     screen returns without touching anything, so the enter/exit churn a
     reorder provokes can't loop forever. This doubles as the "selection
     outranks the cursor" rule: with a card selected the focus never moves, so
     hovering around reflows nothing.
  3. `_reordering` + an "already sorted?" check in `_reorder_hand_nodes` — a
     reorder that would change nothing moves no children at all.

  Verified by sweeping a synthetic cursor across all 8 cards in both directions
  (140 samples): exactly one hovered card per frame, always at scale 1.2 and
  always topmost, every other card at 1.0, zero engine errors.
- **Description box** (`_show_description_box`): a `Panel` placed on either
  side of the lifted card (`DESC_BOX_W` × `DESC_BOX_H` = 320×220 px,
  `DESC_BOX_GAP` = 12 px). The side with more screen space wins; the box is
  clamped to the viewport. Contents: header row with card name on the left
  and the effective cost number on the right (white / green / red mirroring
  the card's top-left cost, no 시전자 tag) and the full description.
  **There is no 카드 내기 button** — playing a card is the 확인 button that
  `CardTargetingOverlay` parks at the bottom-right, so the commit action lives
  in one place whether or not the card needs a target. The only button this
  box still owns is **버리기**, shown while a 버리기:N pick overlay is active
  (`_in_discard_pick_mode()`), which is not a card play at all.
- **Selecting a card *is* the targeting step** (`_select_card` →
  `targeting_overlay.start_card_selection`): lifting a card immediately dims
  the out-of-range tiles, marks the legal targets, and raises the
  확인 / 취소 row. Nothing is spent until 확인 — see the 대상 지정 section.
- **Outside-click dismiss** (`_unhandled_input`): any mouse press / screen
  touch that lands outside the card, the description panel, and the buttons
  calls `deselect_current_card()`. Card.`_gui_input` calls `accept_event()` so
  the same press that selects a card never doubles back to deselect it;
  `Panel` and `Button` consume their own events via `MOUSE_FILTER_STOP`.
  **PILOT / LOCATION selections never reach this handler** — the overlay marks
  every battlefield press handled (see 대상 지정 below).
- `deselect_current_card()` is also called from `end_card_phase()` and
  `build_starter_decks()` so the lifted-card / description-box state never
  leaks across phase transitions or game restarts.
- `apply_card_effect(cd, is_player)` → String log message

### Per-pilot decks (시전자 rule + 슬롯 구성)
- `build_starter_decks()` — for each pilot on each side, deals 6 `CardData`
  copies from the DB pool and tags each with that pilot as 시전자
  (`owner_pilot`). All 5 stacks shuffle into the team deck: **5 × 6 = 30장**.
  Player and AI sides build identically; the AI hand is logical-only but its
  cards still carry an enemy-pilot owner.
- **6장은 메크 3 + 파일럿 3으로 갈린다**, 그리고 파일럿 3장의 내역은 역할이
  정한다. `_pilot_slots_for(p)` 가 그 표다:

  | 역할 | 판정 | 메크 | 파일럿 3장 |
  |---|---|---|---|
  | 암살자(정글러) | `is_guerrilla` | 3 | `jungle` 2 + `draw` 1 |
  | 서포터 | `role == Role.SUPPORT` | 3 | `lane` 1 + `draw` 2 |
  | 탱커 / 격투가 / 스나이퍼 | 나머지 | 3 | `lane` 2 + `draw` 1 |

- **각 슬롯은 중복 없이(without replacement) 뽑는다** (`_sample`). 라인전 풀이
  3종인데 슬롯이 2장을 요구하므로, 예전의 중복 허용 랜덤이면 같은 카드 두 장이
  나오는 쪽이 더 흔했다. 풀이 요구 장수보다 작으면 그때만 중복으로 폴백하고,
  카테고리 풀이 아예 비면 그 파일럿의 scope 필터 통과분 전체로 폴백한다 —
  덱 크기 30은 CSV 오타로 깨져서는 안 되는 불변식이다.
- **`pool = 0` cards never enter the random pool.** `_build_pool_from_db()`
  drops them while copying `GameManager.card_pool_bs`. 결투 is the first one:
  it still exists in the DB and every effect handler still supports it, but
  nothing hands it out — it is slated to become a mech-unique card. (If the
  filter were ever to empty the pool entirely the unfiltered list is used, so a
  mis-tagged CSV can't produce a deckless match.)
- **두 필터가 겹쳐 있고 답하는 질문이 다르다.**
  - `scope` = **누가 가질 수 있는가**. `_pool_for_pilot(pool, p)` 가 슬롯 뽑기
    **앞에서** 한 번 거른다: 정글러는 `any` + `jungle`(약탈 …), 레인 파일럿은
    `any` + `lane`(전진 …). Filtering at *deal* time rather than at play time is
    the whole point — a card's 시전자 never changes after the deal, so a lane
    card in a jungler's deck would just sit in hand permanently locked with no
    way for the player to act on it. Unknown `scope` strings read as
    unrestricted (`CardData.allowed_for_guerrilla`).
  - `card_cat` = **어느 슬롯을 채우는가**. 위 표의 라인전 / 드로우 / 정글 분류.
- **`card_cat = common` 은 라인전 슬롯과 정글 슬롯 양쪽 후보다**
  (`CardData.fits_category`). 지금은 **복귀(id 21)** 하나뿐이다: 설계상 라인전
  카드지만 정글러도 뽑을 수 있어야 한다 — 정글러가 복귀를 못 받으면 HP 회복
  수단이 자동 복귀(HP 20%)뿐이 되기 때문. `scope` 는 `any` 라 두 필터가 서로를
  막지 않는다.
- `make_card_copy(src)` — copies every CSV column (including `scope` / `pool` /
  `card_type` / `card_cat`) AND `owner_pilot`. Use this any time you need a
  deck-safe duplicate.

**실측** (standalone 1판, 양 팀): 30/30장, 파일럿마다 mech 3 + 파일럿 3,
서포터만 draw 2, 정글러만 jungle 슬롯 2(= `jungle` 2 또는 `jungle` 1 + `common` 1),
같은 파일럿이 같은 카드를 두 장 가진 사례 0.
- Card front layout:
  - **Top-left**: 작전 점수 (cost) label, large outlined text on the
    cost-coloured card body. `Card.update_displayed_cost(eff)` recolours the
    number — white when matched, green when reduced by an active modifier
    (사전 준비 / 전투 준비 / 집중), red when increased (`cost_inc_phase`, which
    no card in the pool currently carries). **정밀 이동's +1 is not a modifier** —
    `return_left:1` writes it into the card's own `cost`, so the returned card
    reads white at its new, genuinely higher price.
    `CardPhaseManager.highlight_affordable_cards` calls it for every visible
    card so the cost-modifier effects stay in sync with the card art.
  - **Top-center**: card name (auto-truncates with `clip_text`).
  - **Center / body**: **owner face image** filling the card
    (`PilotImages.face_for(owner.pilot_id)`, 140×170 `TextureRect` inside a
    `CenterContainer`, `STRETCH_KEEP_ASPECT_COVERED`). Empty when no face is
    available — the cost-coloured panel shows through.
  - **Unplayable dim** (`BlockOverlay`): a `Panel` at the **end** of the child
    list — above `CardFront`, so it darkens the owner face, name and cost
    together — filled `BLOCKED_OVERLAY_COLOR` (black α 0.58) with the card's
    own 10 px corner radius. It goes up for either of two reasons, tracked
    independently and merged by `_refresh_block_overlay()`:
    `set_affordable(false)` (can't pay) or `set_respawn_turns(n > 0)`
    (시전자 부활 대기). `set_affordable` no longer repaints the card body grey
    — the grey panel sat *under* the portrait, which stayed bright and read as
    playable; only the border colour still shifts as a secondary cue.
  - **Respawn countdown** (`RespawnCountdown`): a `Label` next to the slab,
    `RESPAWN_FONT_SIZE` 76 with a 10 px outline, showing the turns left until
    the 시전자 comes back. Visible only while `set_respawn_turns(n)` is
    non-zero. `Card.is_playable()` returns false whenever either reason holds.
    Both nodes must be `MOUSE_FILTER_IGNORE` — see the filter note below.
  - **No description on the card itself.** The full description is surfaced
    only in the side description box that appears when the player selects
    the card (`_show_description_box`).
  - **No role badge.** Role is conveyed solely by the owner face image; the
    description box still surfaces "시전자 <Role><team>" in the header line.

#### 핸드 히트 레이어 — draw order must not decide hit-testing
Player hand cards do **not** pick the mouse. `spawn_card_node` runs
`_set_subtree_mouse_ignore(node)` over the card and every descendant, and one
transparent `Control` (`HandHitLayer`, built by `_fit_hit_layer`) sits over the
whole row and routes hover and clicks itself.

Letting each card claim its own rect is what made a packed hand unclickable.
The cards overlap far more than they are wide — 160px cards on a 67.5px stride
at 12 cards — and the focus card is drawn on top at 1.2×, so it ate the
only pixels its right-hand neighbour had left. Measured across every focus
position of a 12-card hand: the card immediately right of the hovered one kept
**5–17px**, and **0px** with card 8 focused — that neighbour could not be
hovered at all, which is why moving the cursor one card to the right appeared to
do nothing or to skip a card. Every other card kept 40–110px, so the damage was
specific to the right-hand neighbour: the fan overlaps rightward, so each card's
only exposed strip is its left edge, and that is exactly the strip the enlarged
focus card covers.

- `_apply_hit_bands(total)` — cuts the row into `_hit_bands[i]`, one
  viewport-space `[left, right]` per card, at the **midpoints between
  neighbouring card centres**. They tile the row exactly (no overlap to fight
  over, no gap to fall through), so every card owns ~`slot_spacing` px no matter
  who is drawn over it. The two end cards extend their band out to their own
  edge so the ends of the row stay clickable. Runs from `relayout_hand`, so the
  bands always match the layout that is on screen.
- `_hand_card_at(p)` — band lookup plus **one hysteresis rule: the focus card
  holds the cursor while it is anywhere on its enlarged face.** Without it the
  hand walks away from the cursor: hovering a card re-spreads the row, which
  slides the bands under a stationary cursor, which hands the hover to the next
  card along, which re-spreads again. That cascade was real and measured — one
  step from card 0 toward card 1 ran the focus 0 → 2 → 4 → 6 → 8 → 10 → 11.
- `_on_hit_layer_gui_input` — motion drives `_update_hover_at`; a press routes
  to `on_card_clicked`, or to `deselect_current_card()` when it lands on the
  layer's padding rather than a card. `accept_event()` keeps that press out of
  the outside-click handler, exactly as `Card._gui_input` used to.
- `Card.set_hovered(bool)` is the hover entry point. `_on_mouse_entered` /
  `_on_mouse_exited` still forward to it for the AI peek row and the 찾기 grid,
  which are flat and don't overlap.
- The layer is sized to the band the cards already occupy (row span + hover
  enlargement, plus the lift only while a card is selected), so it can't swallow
  anything the cards weren't covering. It clears the player 전략 포인트 도넛
  (bottom 1410 vs layer top 1438) and sits below the description box, which is
  added to the canvas later and so still out-picks it.

Verified at both hand sizes: 0 sweep mismatches, 0 bad neighbour steps, the play
button still fires through the description box, and the worst reachable strip
anywhere is **28px at 12 cards** (was 0px) / **73px at 8 cards**.

#### Every decorative child in Card.tscn must be IGNORE or PASS
Hover and click both live on the `Card` root (`mouse_entered` / `_gui_input`).
Any descendant left on `MOUSE_FILTER_STOP` swallows the mouse over its own rect,
punching an invisible hole in the card: the cursor sits visibly on the card and
nothing happens. `HeaderRow` shipped that way (a plain `Control` — the default
is STOP) and killed hover across its 30px band, 36px on screen once the card is
hover-scaled, ≈13% of the card height just under the top edge.

Godot's per-class defaults are why this is easy to miss: `Container` subclasses
(`MarginContainer`, `VBoxContainer`, `CenterContainer`) default to **PASS** and
`Label` to **IGNORE**, so those are fine untouched — but plain `Control`,
`Panel`, `TextureRect`, `ColorRect` and friends default to **STOP** and must be
set to `mouse_filter = 2` explicitly. `CardBack`, `CardFront`, `HeaderRow` and
`OwnerFace` all carry that override. Verified: 218 sample points down and up the
full card rect, 0 dead.

**For hand cards, PASS is not good enough either** — hence
`_set_subtree_mouse_ignore`. A PASS control is still *returned by picking*; it
only forwards the event to its parent afterwards. So Card.tscn's
`MarginContainer` / `VBoxContainer` / `CenterContainer`, which are PASS by class
default, kept answering for the card's whole rect: the hit layer underneath
never saw a single event, and because Godot also walks a mouse-enter up the
parent chain, the Card still lit up — which reads exactly like the hit layer
working and made this a slow one to find. Same defaults as above, opposite
direction.

### cards.csv 컬럼 — `scope` / `pool` / `card_type` / `card_cat`
Four columns drive who gets a card, which deck slot it fills, and whether it is
dealt at all. All flow `cards.csv` → `addons/csv_to_db/csv_to_db.gd`
(SCHEMAS + TABLE_DEFS) → `GameManager.card_pool_bs` → `CardData`. **Adding a
column means running Project → Tools → Rebuild game.db**; until then
`GameManager` reads them with defaults (`any` / `1` / `mech` / `-`) so an older
game.db still loads.

| Column | Values | Meaning |
|---|---|---|
| `scope` | `any` / `lane` / `jungle` | 시전자 제약 — **누가 가질 수 있는가**. `lane` = 레인 파일럿만 (전진), `jungle` = 정글러만 (약탈 / 정글 파밍 / 전투 준비 / 정밀 이동), `any` = 제약 없음. Enforced once, at deal time. |
| `pool`  | `1` / `0` | `0` = 랜덤 스타터 덱에 절대 들어가지 않음 (결투). |
| `card_type` | `mech` / `pilot` | 덱 구성의 1차 분류. 파일럿마다 `mech` 3장 + `pilot` 3장. |
| `card_cat` | `-` / `lane` / `draw` / `jungle` / `common` | 파일럿 카드의 슬롯 분류. 메크 카드는 `-`. `common` 은 라인전 슬롯과 정글 슬롯 **양쪽** 후보(복귀 하나뿐). |

#### 현재 28행의 분포
| 분류 | 장수 | 카드 |
|---|---|---|
| `mech` | 9 (풀 대상 8) | 전투 개시 · 완벽한 기회 · 결투(`pool=0`) · 공격 · 필중 · 연속 공격 · 전진 · 보호 · 약탈 |
| `pilot` / `lane` | 2 | 안전한 파밍 · 공격적인 라인전 |
| `pilot` / `common` | 1 | 복귀 |
| `pilot` / `draw` | 13 | 교환 · 조정 · 임기응변 · 재빠른 사고 · 집중 · 사전 준비 · 아드레날린 · 계획 살인 · 재고 · 완벽한 마무리 · 계획 중시 · 과감한 정리 · 솔로 퍼포먼스 |
| `pilot` / `jungle` | 3 | 정글 파밍 · 전투 준비 · 정밀 이동 |

**이름이 비슷한 두 장**: **재빠른 사고**(id 15, `draw:2`)와 **과감한 정리**
(id 29, `discard_right:3;draw:5`)는 다른 카드다. 후자는 계획서의 "재빠른 생각"을
이름 충돌 때문에 개명한 것이다.

**scope 재배치의 파급** (의도된 것):
- 전투 준비 / 정밀 이동이 `jungle` 이 되면서 **레인 파일럿은 이동 카드를 전혀
  갖지 못한다.** 위치 조작 수단은 전진(advance)뿐. `RecallSystem._is_out_of_position`
  (이동 카드가 레인 파일럿을 남의 레인에 떨궜을 때의 강제 복귀)은 이제 발동할 수
  없는 경로지만, 향후 레인 이동 카드가 생길 자리로 코드를 남겨 둔다.
- 복귀는 `scope = any` 를 유지하고 `card_cat = common` 으로 두 슬롯에 걸쳐 있다 —
  정글러의 복귀 수단을 없애지 않기 위한 선택.

### Effect chain encoding (cards.csv `effect` column)
The DB column is a `;`-separated chain of clauses. Each clause is
`name[:value][|flag[:value]]…`. Examples:
- `draw:2;discard:2`            — two clauses run in order
- `attack:1|pierce`             — one clause + one modifier flag
- `engage:3|exclude_lane`       — engage with lane-exclusion modifier
                                 (parsed and honoured, but no card in the pool
                                  carries it since 교전 was removed)

`apply_card_effect()` parses the chain, dispatches each clause through
`_apply_single_effect`, and returns one log line of the form
`<시전자> [<카드명>] · <효과 요약>, <효과 요약>…`.

### Effect handlers
> **Note on the "opens CardTargetingOverlay …" wording below**: the target is
> now resolved *before* the effect chain runs — picking happens the moment the
> card is lifted in hand, and the handler receives the already-chosen
> `selected_target`. Read those cells as "this card's `targeting_kind` is
> PILOT / LOCATION / PREVIEW", not as "the handler opens a modal".

| name | Implemented | Behaviour |
|---|---|---|
| `draw:N` | yes | Pull N from deck (reshuffles discard if empty); spawns visual node for the player |
| `search:N` | yes | **Player**: opens CardSelectOverlay search grid — pick exactly N from the deck via 확인. **AI**: same as `draw:N` (random top-of-deck). |
| `discard:N` | yes | **Player**: opens CardSelectOverlay discard pick — pick exactly N via the desc-box "버리기" button, then press 확인 to commit. The played 버리기 card is non-cancellable (no 버리기 취소 button). **AI**: random N from hand. |
| `strategy:N` | yes | +N 작전 점수 to playing side |
| `attack:N` | yes | **Player**: opens CardTargetingOverlay PILOT mode — battle tiles dim, valid enemy pilots ringed, click an enemy to commit. **AI**: random valid pilot (range-aware). **Rolls `SimulationCore.roll_hit` (`hit/(hit+evasion)`, the same roll the battlefield uses) — a miss deals nothing.** Damage on a hit = `caster.atk × N`; 보호막 absorbs first. `pierce` (필중) skips the roll; `repeat` (연속 공격) re-rolls the same attack after every landed hit, stopping on a miss, on the target's death, or at `MAX_ATTACK_REPEATS` (5). `min_range:N` filters out pilots closer than N (parsed, but no card in the pool carries it since 저격 was removed). **Every swing floats its verdict over the target** via `BattleRenderer.spawn_pilot_popup`: `MISS` on a miss, `-N` on a hit, `흡수` when 보호막 ate the whole hit (the handler returns HP damage, so that case would otherwise read `-0`). 연속 공격 staggers its popups by `DMG_POPUP_STAGGER`. |
| `shield_pct:N` | yes | **Player**: PILOT mode → click an ally; gains shield = N% of max_hp. **AI**: random ally. Cleared on 본진 복귀. |
| `recall_ally` | yes | **Player**: PILOT mode → click an ally; teleports to HQ at full HP, shield reset, waypoint reset. **AI**: random ally. |
| `exhaust_choice:N` | yes (random) | Random N from hand → removed (소멸). Parsed and honoured, but no card in the pool carries it since 차선책 was removed. |
| `engage:N` | yes | **Player**: opens CardTargetingOverlay PREVIEW mode — caster cell + 6 neighbours highlighted, side panel lists participants, 확인 launches the engage arena. **AI**: same flow via AiCardPlayer. `exclude_lane` flag propagates. **N 은 라운드 수 그대로다** — `engage:3` = 3라운드이고, 한 라운드 안에서 참가자 전원이 한 명씩 차례대로 한 번 행동한다(예전의 "N × 3초" 환산은 삭제). |
| `duel` | yes | **Player**: PILOT mode → click an enemy in range; opens the turn-based arena restricted to caster + target with the round counter running up instead of a budget, ends on first KO — 이탈이 없으므로 KO 아니면 `DUEL_MAX_ROUNDS`(10라운드) 상한까지 간다. **AI**: random enemy in range. Routes through `EngagePhaseManager.start_duel`. **결투 (id 3) is `pool = 0`** — fully implemented but no longer dealt at random; it is reserved as a future mech-unique card. |
| `capture_jungle:N` | yes | **Player**: LOCATION mode over `compute_capture_jungle_targets` — **enemy-owned jungle cells adjacent to a cell the caster's team already owns**, anywhere on the map (`cast_range` 99 = 사거리 무시). Flips the picked cell to the caster's team for N turns, so each play pushes the jungle border one cell further. **AI**: random valid cell. SimulationCore.process_temp_zone_expiries restores the previous owner once `turn_count >= expires_turn`. |
| `move` | yes | **Player**: LOCATION mode → click any cell in `cast_range` (jungle cells included; the lane-pilot displacement recall pulls them back at phase end if needed). **AI**: random valid cell. Caster's `grid_pos` snaps to the picked cell and `BattleSim.anim_pilot_move` plays the tween. Decorators on the same chain (`return_left:N`, `cost_reduce_engage:N`) run separately. |
| `return_left[:N]` | yes | Decorator, **resolved at disposal time, not in the chain** — the card is out of hand while the chain runs, so `_apply_single_effect` only writes the log line and `_dispose_used_card` does the work. Sends the played card back to the **leftmost slot of the hand** instead of the discard pile and raises **that copy's own** `cost` by N, cumulatively. See 손패 복귀 below. Carried by 정밀 이동 (`move;return_left:1`). |
| `cost_reduce_engage:N` | yes | One-shot pending discount on the side's next engage card. Stored on `_bs.engage_discount_p/ai`; consumed in `_play_card_direct` / `AiCardPlayer.run_ai_plays`. |
| `cost_reduce_hand:N` | yes | Mutates every card currently in hand — `cost = max(0, cost - N)`. The played card is already gone from hand by the time this fires. |
| `cost_reduce_draw_phase:N` | yes | Phase-bound draw discount; `draw_card` mutates each drawn `CardData.cost` while `_bs.phase_draw_discount_*` is active. Reset on `start_card_phase`. |
| `cost_inc_phase:N` | yes | Phase-bound additive cost bump on every card play during this 작전 단계. Stored on `_bs.phase_cost_inc_*`; consumed by `effective_cost_for`. Reset on `start_card_phase`. **No card in the pool carries it** — 정밀 이동 used to, but its +1 is now self-only (`return_left:1`). The clause is parsed and honoured, so any future card can take it. |
| `advance:N` | yes | Caster runs `N` mini-ticks of lane push through `SimulationCore.advance_pilot`. Each tick resolves combat at the caster's cell as usual **but forces the push result: the caster's side always wins the cell** (damage rolls are untouched — only who gets pushed is fixed). The caster **plus every same-cell, same-scope ally** steps forward and every same-cell enemy is pushed back one cell. If the next cell is a **same-lane enemy turret** the group holds one tile short and sieges it instead (turret takes `atk`, defenders on the turret cell roll back at the attackers, no knockback) — the siege waits a tick when the group just pushed an enemy onto that cell. A caster already standing on an enemy turret cell hits it and falls back one tile; that is the only way 전진 ever moves backwards. |
| `strategy_on_kill:N` | yes | 계획 살인 — **선불 예약형**. 카드를 낸 시점에 `_bs.kill_bounty_p/ai = N` 을 심고, `BattleSim.mark_pilot_dead` 가 상대 팀 파일럿의 사망을 볼 때 한 번 지급하고 0으로 소모한다. 전장에 제3세력이 없으므로 처치자는 "죽은 파일럿의 반대 팀"으로 충분하다 — `mark_pilot_dead` 에 처치자 인자를 추가하지 않았다. 같은 단계에 두 장을 내면 큰 쪽 하나만 남는다(현상금은 처치 한 번분). 미사용분은 `end_card_phase` / `_run_ai_turn` 종료 시 사라진다. |
| `lane_stat:N\|turns:T` | yes | 안전한 파밍 / 공격적인 라인전 — 시전자의 `lane_stat_mod = N/100`, `lane_stat_expire_turn = turn_count + T`. **전장 명중 판정 전용**: `SimulationCore.roll_hit` 이 공격자의 `hit` 과 방어자의 `evasion` 에 각자 자기 배율을 곱한다. `atk` / `max_hp` 는 건드리지 않는다(그쪽은 성장 담당). 같은 파일럿에 두 번 걸면 **덮어쓴다** — 합산이면 3종 풀에서 2장 뽑는 구조상 +20~30% 가 운으로 굴러 나온다. |
| `growth:N\|turns:T` | yes | 안전한 파밍 — 시전자의 성장 **획득 배율**을 `1 + N/100` 로. 성장률 자체가 아니라 그 배수다(+10% → 턴당 +1%p 가 +1.1%p). 만료는 `SimulationCore.tick_growth_and_expiries` 가 매 턴 확인. |
| `growth_until_phase:N` | yes | 완벽한 마무리 — 시전자 **팀 전원**의 성장 획득 배율을 `1 + N/100` 로 올리고 `growth_until_phase` 를 세운다. 그 팀의 다음 작전 단계 진입 시 `_apply_phase_entry_carryovers` 가 걷는다. `growth:N` 과 같은 필드를 쓰므로 나중에 건 쪽이 이긴다. |
| `discard_hand` | yes | 완벽한 마무리의 첫 절 — 손패 전부 discard. 보존을 **무시한다**. |
| `discard_hand_draw` | yes | 재고 — 손패 전부 버리고 **버린 장수만큼** 다시 뽑는다. 손패 크기는 그대로고 내용만 갈린다(덱+discard 가 마르면 뽑은 만큼만). |
| `discard_right:N` | yes | 과감한 정리 — 손패 **오른쪽**(가장 최근에 들어온 쪽) N장을 discard. `hand.pop_back()` × N. |
| `discard_other_pilots\|strategy_each:M` | yes | 솔로 퍼포먼스 — `owner_pilot != caster` 인 손패 카드를 전부 버리고 장당 전략 점수 +M. 시전자가 없으면 "본인 카드"를 가릴 수 없으므로 아무것도 하지 않는다(손패 전멸 사고 방지). |
| `preserve:N` | yes | 계획 중시 — **Player**: `CardSelectOverlay.start_preserve` 가 찾기와 같은 그리드로 **손패**를 펼쳐 N장을 고르게 한다(카드는 손패에서 빠지지 않는다). **AI**: 손패에서 무작위 N장. 픽은 `BattleSim.preserved_cards_p/ai` 에 올라가 `_trim_hand_overflow` 로부터만 보호된다 — 강제 버리기는 무시한다. 다음 작전 단계 진입 시 통째로 해제. |
| `strategy_next_phase:N` | yes | 아드레날린의 뒷절 — `_bs.next_phase_strategy_p/ai += N`(음수 가능). 다음 작전 단계 진입 시 정산되고 점수는 0 아래로 안 내려간다. |
| `end_phase` | yes | 완벽한 마무리의 마지막 절 — **여기서 단계를 닫지 않는다.** 체인이 도는 동안 카드는 손패 밖에 떠 있어서, 지금 닫으면 소멸 / discard 라우팅 전에 문이 닫힌다. `_end_phase_requested` 플래그만 세우고, **Player**: `_finalize_pending_play` 말미가, **AI**: `AiCardPlayer` 의 플레이 루프가(교전 아레나를 기다린 **뒤**에) `consume_end_phase_request()` 로 받아 간다. |
| `move\|own_jungle` | yes | 정글 파밍 — `compute_valid_location_targets` 가 `compute_own_jungle_targets` 로 분기해 유효 셀을 **시전자 팀이 소유한 정글 셀**로 좁힌다. 약탈과 마찬가지로 `cast_range`(99)는 무시 — 사거리로 묶으면 정글 반대편 캠프가 영영 닿지 않는다. 제자리 셀은 뺀다. 소유 판정이 `neutral_zone_cells` 를 직접 읽으므로 약탈의 임시 점령도 자동 반영된다. **AI**: `_ai_pick_target` 이 같은 함수를 쓰므로 그대로 따라간다. |

#### Effective cost & affordability
`BattleSim.effective_cost_for(cd, is_player)` is the single source of truth
for "what does this card cost right now?". It applies `phase_cost_inc_*`
(additive) and the one-shot `engage_discount_*` (only when the card has
an `engage` clause), clamped at 0. The affordability highlight in
`highlight_affordable_cards`, the description-box "카드 내기" enable check,
the cost subtraction in `_play_card_direct`, and `AiCardPlayer.run_ai_plays`
all consult this helper so the four cost-modifier effects stay in sync.

### 소멸 / 손패 복귀 routing
`_dispose_used_card(cd, is_player)` runs after every play and routes the card
three ways, **손패 복귀 first**:
- a `return_left[:N]` clause → back to the **leftmost slot of the hand**
  (정밀 이동). Never reaches the discard pile and is never 소멸.
- `keyword == "exhaust"` → removed permanently (소멸)
- anything else → returns to the discard pile

#### 손패 복귀 (`return_left[:N]`)
`_return_left_bump(cd)` re-parses the played card's effect chain and returns the
clause's value, or `-1` when the clause is absent. A hit routes into
`_return_card_to_hand_left(cd, is_player, bump)`:

- **`cd.cost += bump`, and it sticks.** `cd` is the 시전자-tagged copy
  `build_starter_decks` minted with `make_card_copy`, so the bump lands on that
  one physical card and **accumulates across plays** (정밀 이동: 0 → 1 → 2 …).
  No other card is touched — this is deliberately *not* `cost_inc_phase`, which
  taxes every card played in the 작전 단계. 정밀 이동 carries only
  `move;return_left:1` now.
- Player side: `player_hand.insert(0, cd)` + `spawn_card_node(cd, true)`.
  The `at_left` flag puts the node at the **head** of `player_card_nodes`;
  `relayout_hand` derives every slot from the array index, so that one flag is
  the whole "맨 왼쪽" rule. The two arrays must be inserted at the same end.
- AI side: `ai_hand.insert(0, cd)` + `HudBuilder.update_ai_hand_visuals()`,
  which re-adds a card back to match the hand count. Safe to call here because
  `AiCardPlayer` has already finished (and freed) its fly-to-centre node by the
  time `apply_and_dispose_ai_card` runs.
- **No `MAX_HAND_SIZE` guard.** The card left the hand and came back, so the
  hand can't grow past where it started; and a card that arrives during the
  side's own turn is exempt from the cap by the rule above (Hand overflow).
- The returned card sits at index 0, which is exactly where `_trim_hand_overflow`
  pops from — so once its accumulated cost makes it dead weight, the first
  BATTLE auto-draw that overfills the hand discards it. That is the intended
  self-limiting end state, not a leak.

> **A `return_left` card must raise its own cost (or already cost > 0).**
> `AiCardPlayer.run_ai_plays` loops while it can afford *something* in
> `ai_hand`; a 0-cost card that returns to hand at 0 cost would never leave the
> affordable set and the loop would never terminate. `return_left:1` on a
> 0-cost 정밀 이동 escalates 0 → 1 → 2 …, so the AI's 작전 점수 bounds the
> chain. Keep that property if another card ever takes this clause.

> **`uses` no longer decides anything.** The rule used to be "`uses > 0` →
> decrement `remaining_uses`, remove at 0", but `cards.csv` gives **every**
> non-exhaust card `uses = 1`, so a single play destroyed it — 전투 개시
> included. The deck never cycled: it only shrank, the discard pile only ever
> filled from 버리기 clauses, and the reshuffle path in `draw_card` was
> effectively dead. `CardData.remaining_uses` is gone; the `uses` column is
> still loaded and copied (it stays available for a future "N charges then
> 소멸" mechanic) but nothing reads it.

Note that the five `exhaust` cards (조정 / 임기응변 / 재빠른 사고 / 집중 /
아드레날린) carry `uses = 3` in the CSV. That has never meant anything — the
keyword check has always fired first, so they are 소멸 on their first play.

### 대상 지정 (CardTargetingOverlay)
- `CardTargetingOverlay.gd` — sibling of `CardPhaseManager`, owns a CanvasLayer
  at layer 11 (above the search/discard overlay's layer 10) that hosts the
  확인 / 취소 buttons plus PREVIEW 모드의 좌/우 팀 패널.
- **There is no modal step any more.** `Mode` is now just "what kind of card is
  lifted in hand": `NONE / INSTANT / PILOT / LOCATION / PREVIEW`. One entry
  point, `start_card_selection(cd, on_confirm, on_cancel)`, is called from
  `CardPhaseManager._select_card` the moment a card is lifted; `clear_selection()`
  runs from `deselect_current_card`. The hand and 턴 넘기기 stay live throughout
  — the player can switch to a different card mid-pick, and
  `_is_player_input_blocked()` / `can_end_card_phase()` no longer consult this
  overlay at all.
- **Nothing is spent until 확인.** Cost deduction, card destruction and the
  effect chain all happen in `_play_card_direct(card, pre_target)`, which the
  overlay's confirm callback (`_on_selection_confirm`) invokes with the already
  resolved target. That removed the whole targeting-cancel refund path — 취소
  is now just `deselect_current_card()`. (The snapshot/refund machinery still
  exists for 버리기 / 찾기 clauses, which mutate state mid-chain.)
- **Confirm gating**: `set_play_allowed(bool)` carries
  `CardPhaseManager.card_is_playable(cd)` (cost + 시전자 생존 + 유효 대상) into
  the overlay; the button's `disabled` is `not (play_allowed and
  has_required_pick())`. `has_required_pick()` is true immediately for PREVIEW /
  INSTANT and only after `pending_pick` is set for PILOT / LOCATION.
  `highlight_affordable_cards()` re-pushes the verdict, so a 시전자 killed by an
  engage earlier in the same phase disables 확인 on the lifted card.
  `_on_selection_confirm` re-checks `card_is_playable` rather than trusting the
  button state.
- **Buttons live at the bottom-right**, just above the Discard counter, and are
  laid out by counting back from the right edge (`_screen_w()`), matching
  `CardSelectOverlay`'s order of 확인 then 취소:
  취소 at `(screen_w − BTN_SIDE_MARGIN − BTN_W, BS_HAND_CENTER.y − BTN_HAND_GAP
  − BTN_H)` = (876, 1434), 확인 one `BTN_W + CONFIRM_BTN_GAP` to its **left** at
  (684, 1434). The 전략 포인트 도넛 column now owns the opposite (left) gutter;
  `HudBuilder` still derives the donut's y from `BTN_HAND_GAP + BTN_H` so both
  sit in the same horizontal band.
- **Battlefield clicks are swallowed** in PILOT / LOCATION mode — hit *or*
  miss. `_unhandled_input` calls `get_viewport().set_input_as_handled()`
  unconditionally, because `CardPhaseManager._unhandled_input` would otherwise
  read a tap a few px off a pilot marker as "clicked outside" and drop the
  selection along with the pick. The overlay is added to `BattleSim` after
  `CardPhaseManager` and unhandled input walks the tree back-to-front, so it
  gets first refusal. Exits are 취소, a re-click on the card, or selecting a
  different card.
- **Pending pick**: a click on a valid pilot or cell stores it as
  `pending_pick`. `BattleRenderer._draw_pending_pick_highlight()` paints a cyan
  ring on the picked pilot marker (or a thicker cyan outline on the picked
  cell) so the player can confirm or pick a different valid target.
- Driven by `CardData.cast_method` / `target` fields (see `targeting_kind`):
  - `cast_method == "target"` (target=enemy/ally/pilot) → **PILOT** mode.
    BattleRenderer paints a soft yellow fill on every cell within
    `cast_range` and a black overlay on every cell outside it. Pilots not in
    `valid_pilots` get a per-marker black overlay. There is no per-pilot
    ring on the tile — the visible pilot marker IS the click target.
    Range honours `cd.cast_range` and the `min_range:N` flag.
  - `cast_method == "location"` → **LOCATION** mode. Same yellow range fill
    + black out-of-range dim as PILOT. Valid cells (subset, e.g. 약탈's
    enemy-jungle-adjacent-to-own filter) get an extra green outline. All pilots
    dim via BattleRenderer's per-marker dim.
  - **`cast_range ≥ CardTargetingOverlay.UNLIMITED_RANGE` (99) = 사거리 무시**
    (복귀 / 보호 / 약탈). `range_unlimited` goes up, `is_in_range_cell` answers
    true everywhere, and BattleRenderer draws **neither the yellow fill nor the
    out-of-range dim** — flooding the whole battlefield yellow just buried the
    thing the player actually has to read (the green valid cells / the
    undimmed pilot markers).
  - `cast_method == "range" and target == "caster"` → **PREVIEW** mode
    (engage cards only; 전진은 target=enemy 라 PREVIEW 가 아니라 즉시 발동).
    The caster cell and 6 neighbours show a soft yellow fill with full outline.
    Two side panels — **좌측 = 아군 팀, 우측 = 적군 팀** — list each
    alive participant with the pilot face image (`PilotImages.face_for`),
    role/팀 라벨, HP 텍스트, HP 프로그레스 바. 카드를 고른 즉시 패널이
    뜨고, 따로 찍을 대상이 없으므로 확인은 처음부터 활성이다. 확인 →
    `_play_card_direct(card, null)` 가 비용 차감 / 카드 파괴 / effect chain
    실행을 한꺼번에 수행한다. Cells outside the engage area also get the
    black out-of-range dim.
  - anything else → **INSTANT**. No caster, no range, nothing painted on the
    battlefield (`is_visualizing()` is false, so BattleRenderer skips the dim
    entirely) — only the 확인 / 취소 row appears.
- Hit-testing:
  - **PILOT mode** uses `_hit_test_pilot`, which aims at the pilot's **drawn**
    marker: it reads `BattleRenderer.pilot_marker_positions()` — a fresh run of
    the same per-cell stack solve `_draw()` uses — and picks the valid pilot
    whose marker is closest to the click, within `hex_size * 0.85`. A click that
    lands on no marker but inside a pilot's own tile still resolves, ranked by
    marker distance, so tapping the tile itself keeps working.
    > This is the fix for a real bug. The probes used to be the tile centre and
    > `BattleSim.pilot_marker_pos_solo`, both of which depend only on
    > `grid_pos` — so every pilot sharing a cell had the *same* probe point and
    > the first one in `valid_pilots` (the leftmost drawn portrait) won every
    > click, whichever face the player tapped. Pilots with no drawn slot (the
    > `>5` overflow circle) still fall back to the solo offset.
  - **LOCATION mode** keeps the cell-centred hit test (`_hit_test_cell`).
- The 전략 포인트 도넛 is **no longer locked** while a card is selected — with
  the modal gone there is nothing to protect: 턴 넘기기 during a selection just
  ends the phase, and `end_card_phase` opens with `deselect_current_card()`
  which tears the overlay down.

### AI 카드 사용 애니메이션 (AiCardPlayer)
- `AiCardPlayer.gd` — sibling of `CardPhaseManager`, runs the AI's hand
  one card at a time inside `_run_ai_turn()`'s `await` chain.
- Each play pops the rightmost card-back from the AI hand peek
  (`HudBuilder.pop_ai_hand_card_node()`), reparents it onto `_bs.canvas`
  preserving world position+scale, then tweens it from the hand row to
  viewport centre (`540, 760`) over `FLY_FROM_HAND_SEC` while still
  showing the back. A snap-flip (`scale.x → 0` then `→ SCALE_BIG`) swaps
  to the played card's face via `setup(cd, false, true)`. Holds for
  `SHOW_DURATION_SEC`, fades + scales back out, queue_free.
- When the AI hand peek is empty (rare — stray plays after wholesale
  hand wipes), it falls back to the legacy "spawn fresh card at centre"
  fade-in animation.
- After the visual completes, `apply_and_dispose_ai_card(pick)` runs the
  effect chain. `engage` / `duel` cards route through
  `EngagePhaseManager.start_engage()` / `start_duel()`; the loop gates on
  `engage_phase.is_active()` (not on the effect chain, so 결투 is covered
  too) and `await`s the `engage_finished` signal so the arena fully
  resolves before the next AI play starts.
- The loop then checks `card_phase.consume_end_phase_request()` and breaks if
  the card carried `end_phase` (완벽한 마무리). The check sits **after** the
  arena await on purpose — breaking first would close 상대 차례 with the
  engage the card just opened still on screen.
- **`MAX_PLAYS_PER_TURN` (12)** caps one AI turn. The loop's real exit is "no
  affordable card left", but a card that costs nothing and *rotates* the hand
  can defer that forever — 재고 (비용 0, 손패를 전부 버리고 같은 수를 다시
  뽑는다) re-draws itself until deck + discard run dry. The cap is a structural
  backstop, not a balance knob; a normal hand never reaches it.
- `_ai_play_in_progress` blocks re-entry of `_run_ai_turn`, holds the BATTLE
  auto-tick (via `is_ai_turn_active()`) and disables the donut's 턴 넘기기
  face (via `can_end_card_phase`). It also gates `on_card_clicked` /
  `on_card_hovered` so the player can't pop the description box mid-AI
  animation.

### 버리기 / 찾기 / 보존 modal pick (player only)
- `CardSelectOverlay.gd` (sibling of `CardPhaseManager`, instantiated from
  `BattleSim._ready` once the HUD canvas exists). Owns one
  `CanvasLayer` (`layer = 10`) and rebuilds its UI on every `start_*()`.
  AI plays bypass this overlay and keep the synchronous `apply_card_effect`
  path (random discard, search aliased to draw).
- **Async chain pattern** in `CardPhaseManager._play_card_direct`:
  1. Snapshot `player_hand` / `player_deck` / `player_discard` /
     `player_cost` BEFORE deducting cost or removing the played card. Stored
     on `_pending_play.snapshot`.
  2. `_process_pending_chain()` walks `_pending_play.clauses` via
     `pop_front`. Synchronous clauses dispatch through `_apply_single_effect`
     and append a log line. `discard:N` / `search:N` / `preserve:N` parks the
     remaining clauses on `_pending_play` and starts the overlay, returning
     early.
  3. The overlay's complete callback (`_on_discard_overlay_complete` /
     `_on_search_overlay_complete` / `_on_preserve_overlay_complete`) writes
     the picks to the discard pile, the hand, or the preserve list
     respectively, then calls `_process_pending_chain()` again to continue the
     chain.
  4. When the chain drains, `_finalize_pending_play()` disposes the played
     card (사용 횟수 / 소멸 routing) and writes the combined log line.
- **Cancel = full refund** (`_on_overlay_cancel` → `_restore_from_snapshot`):
  freezes any active selection, frees every player card node, restores
  hand/deck/discard/cost from the snapshot verbatim, and respawns nodes for
  every CardData now back in `player_hand`. This rolls back even prior
  clauses in a chain (e.g. cancelling 교환 returns the 2 drawn cards to the
  deck along with refunding the 교환 card itself). The snapshot also carries
  `engage_discount_p` and the **preserve list**, and the restore clears any
  `end_phase` request the cancelled card had raised.
- **Discard mode UI** (`Mode.DISCARD`):
  - **Battle dim** = `ColorRect` covering y=0..BS_HAND_CENTER.y, parented
    into `_bs.canvas` and moved to child position 0 so HUD + hand still
    draw on top of it.
  - Hand stays clickable; clicking a card opens the standard description
    box, but `_show_description_box` swaps the action button to "버리기"
    while `card_select_overlay.can_pick_for_discard()` is true.
  - Picked cards are reparented to a centered fan above the dim
    (`TO_DISCARD_CENTER_Y = 700`, fan width = `BS_HAND_WIDTH`, same spacing
    rules as the hand row). Once parked there their `mouse_filter` is set
    to `IGNORE` so the fan can't be re-clicked while the player commits.
  - **No auto-commit and no cancel.** A 버리기:N card is non-cancellable:
    the only top-right button is **확인**, disabled until exactly
    `target_count` cards are in the to-discard fan. `target_count` is
    clamped to `min(N, hand.size())`. Pressing 확인 is the sole exit.
  - Bottom-left **숨김** (toggles `hidden_state`; relabels to **표시** while
    hidden, drops any active card selection on press) is still available
    so the player can peek at the battle before committing.
- **Search mode UI** (`Mode.SEARCH`):
  - **Full dim** covers the whole viewport on the high-priority overlay
    layer, dimming both battle and hand.
  - `ScrollContainer` at (`SEARCH_GRID_SIDE_PAD`, 220) holds a 5-column
    layout of all `player_deck` cards, **sorted by card name** via
    `_sorted_for_display()` (ties broken by cost) — the live `player_deck`
    order is the draw order, and laying the grid out in it would turn the
    tutor screen into a "what comes next" table. The sort runs on a duplicate;
    picks are `CardData` references, so display order never affects the commit
    (`_on_search_overlay_complete` erases by identity). `CardPileViewer` sorts
    the same way. Cards are spawned with
    `is_player_card=false` so `Card._on_mouse_entered` short-circuits and
    its hover-brighten tween doesn't fight the `SELECTED_TINT` modulate; a
    transparent flat `Button` child captures clicks ahead of `Card._gui_input`.
  - Bottom-left **숨김**, bottom-right **찾기 취소**, **확인** to its left.
    확인 stays disabled until exactly `target_count` cards are selected
    (`target_count = min(N, deck.size())`); on commit, picks move from
    `player_deck` to `player_hand` (capped at `MAX_HAND_SIZE`) and visual
    nodes spawn via `spawn_card_node`.
- **Preserve mode UI** (`Mode.PRESERVE`, 계획 중시): the **same grid**, differing
  in exactly two places — `_build_search_grid(_bs.player_hand)` sources the
  **hand** instead of the deck, and the cancel button reads **보존 취소**. That
  sharing is safe because neither mode mutates a pile itself: the overlay only
  returns picks and the caller decides what they mean (SEARCH moves them into
  the hand, PRESERVE only marks them). DISCARD is the odd one out — it pulls
  picked cards out of the live hand as they are chosen, which is why it keeps
  its own UI. `_is_grid_mode()` is the shared discriminator.
- **보존 표시**: `Card.set_preserved(true)` draws a cyan `PreserveMark` border
  (`draw_center = false`, so it doesn't darken the card). Driven from
  `highlight_affordable_cards`, which reads `_bs.preserved_cards_p`. It is
  deliberately *not* part of `_refresh_block_overlay`'s dim logic — 보존 is a
  guarantee, not a restriction, so the card stays bright.
- **Phase-end gate**: `can_end_card_phase()` returns false while
  `card_select_overlay.is_active()` so the player can't 턴 넘기기 their
  way out of an unfinished pick.

### Deck / Discard 목록 열람 (CardPileViewer)
`CardPileViewer.gd` — sibling of `CardPhaseManager`, created in
`BattleSim._ready()` and owning a `CanvasLayer` at **layer 12** (above the
버리기/찾기 overlay's 10 and the targeting overlay's 11, so a list opened over
either of them covers both).

- **Entry point**: the two hand-row counters. `HudBuilder._build_hand_indicators`
  lays a transparent flat `Button` over each `Deck` / `Discard` label
  (`_make_pile_button`) — a `Label` is `MOUSE_FILTER_IGNORE` by class default
  and can't take a click itself — and the press calls
  `CardPileViewer.open(Pile.DECK | Pile.DISCARD)`.
- **When it opens**: `CardPhaseManager.can_browse_piles()` — 작전 단계 only, and
  not while the turn banner, the AI's play loop, a 버리기/찾기 overlay or the
  engage arena owns the screen. `HudBuilder._update_pile_buttons()` (called from
  `update_hud`) disables both buttons and fades the labels to
  `PILE_LABEL_DIM_ALPHA` whenever the answer is no, so "you can't open this
  right now" is visible rather than a dead tap.
- **Contents**: the same 5-column `ScrollContainer` grid the 찾기 overlay uses,
  **sorted by card name** (`_sorted_cards()`, ties broken by cost) on a
  *duplicate* — the live pile order is never touched, and the deck's real draw
  order is never revealed. Cards are spawned `is_player_card = false` +
  `MOUSE_FILTER_IGNORE`: nothing in the list is selectable. An empty pile shows
  "비어 있음" instead of a grid.
- **Exits**: the 닫기 button (same bottom-right band as 확인/취소) or a press
  anywhere on the dim.
- **What it locks while open.** Three gates read `is_active()`, because the
  overlay's dim alone is not enough:
  `_is_player_input_blocked()` (hand dims and stops taking clicks),
  `can_end_card_phase()` and `HudBuilder._update_cost_donuts`'s
  `set_flip_allowed` — `CostDonut` listens on `_input`, which runs **before**
  GUI picking, so a tap on the donut would otherwise flip and end the turn
  straight through the dim. `open()` / `close()` call
  `highlight_affordable_cards()` (which tail-calls `_apply_hand_dim_state()`)
  and `hud.update_hud()` so all three re-evaluate on both edges.
- A card selected in hand **stays selected** through a browse — peeking at what
  is left in the deck before committing is the point, and the targeting
  overlay's 확인/취소 row simply sits under the dim until the list closes.
