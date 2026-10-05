# Combat Modules

All scripts extend `Node` and are children of the root `BattleSim` node.
Each module accesses shared state via `@onready var _bs: BattleSim = get_parent() as BattleSim`.

## Pathfinding.gd
BFS pathfinding with greedy fallback (hex grid).
- `bfs_next_step(from, to, forbidden_cells={}, greedy_fallback=true)` → Vector2i
  (`greedy_fallback = false` 면 길이 없을 때 `UNREACHABLE` 을 돌려준다 — 부르는 쪽이
  금지 집합을 풀고 다시 묻는 용도. 도달 판정은 bool 로 든다: 예전의
  `found == (-1,-1)` 센티널은 미드 칸 `(-1,-1)` 이 목표일 때 찾고도 못 찾은 것으로
  쳤다)
- `greedy(from, to, forbidden_cells={})` → Vector2i
- `neighbors(pos, forbidden_cells={})` → Array[Vector2i]

`forbidden_cells` is a Dictionary used as a set (only `.has()` is read). Neighbors
present in `forbidden_cells` are dropped during expansion. The starting cell is
never filtered, so a displaced pilot can always step out of an otherwise-forbidden
region. SimulationCore uses this to keep lane pilots out of jungle cells, and
`SimulationCore.jungle_step` uses it to keep **junglers out of enemy-owned jungle
cells whenever a path around exists** (see "Jungler roaming").

## RecallSystem.gd
**복귀 = 본진 귀환.** Two triggers, one shared path:

- **저HP 복귀** — at HP ≤ `RECALL_HP_THRESHOLD` the pilot goes home.
- **위치 이탈 복귀** — a card effect dropped the pilot on a jungle cell or on
  **another lane's corridor**.

Both call `return_to_hq(p, log_lines, reason)`, which snaps `grid_pos` to the
HQ, **restores HP to full**, clears `shield`, and resets `waypoint_idx` to 0.
`alive` is not touched: **the only thing that takes a pilot off the field is
death.** A recalled pilot is standing in its own HQ, in play, targetable, and
counted by every sweep in the sim.

**The cost of a recall is the walk back, not a heal timer.** `return_to_hq`
sets `PilotData.recall_hold`, and `resolve_movement` spends that flag to skip
the pilot for exactly one movement pass (logged as a `BLOCK`). So the pilot
stands at the HQ on the turn it recalls and starts walking its lane from
waypoint 0 **the next turn** — however low it dropped, the absence is however
many turns the walk to the front takes. The old model (leave the field, heal
`RECALL_HEAL_RATIO` per turn, return the turn after hitting full) is gone
together with that config key.

Because recalls never leave the field, `respawn_timer` and
`BattleSim.turns_until_return(p)` are now **death-only**. Anything that needs
"turns left" — the card lock overlay, BattleLogger's `dead:N` tag — still goes
through `turns_until_return` rather than reading the timer directly.

The 복귀 card (`recall_ally`, `CardPhaseManager._effect_recall_ally`) does the
same thing minus the hold: instant HQ teleport at full HP, free to walk out the
same turn.

- `process_recalls(log_lines)` — runs each BATTLE turn; called from
  `SimulationCore.simulate_turn()` before combat. Low-HP rule only.
- `process_phase_end_recalls(log_lines)` — runs at end of CARD_PHASE and at the
  end of the AI turn; applies the low-HP rule OR the out-of-position rule.
- `_is_out_of_position(p)` — jungler on enemy-owned jungle, lane pilot on any
  jungle cell, or lane pilot standing on another lane's corridor
  (`SimulationCore.lane_corridor`). The lane test requires **positive membership
  in a different lane**, never mere absence from its own: corridors are rebuilt
  with BFS, and a tie-break that differs by one cell from the route a pilot
  actually walked must never exile a correctly-positioned pilot. A deep jump
  along the pilot's *own* lane is legal by design — that is a split push.

## SimulationCore.gd
Main turn loop and all combat / movement / spawn logic. Each `simulate_turn`
counts as **1 minute** of in-game time.

### Turn loop (`simulate_turn`)
0. **`tick_growth_and_expiries`** — 턴 만료형 버프 회수 + 전원 스탯 재계산.
   턴의 맨 앞이라야 이번 턴의 교전이 갱신된 스탯으로 굴러간다. 아래
   "성장 / 라인전 스탯" 참조.
1. `process_respawns` — one sweep over everyone off the field, which now means
   the dead and only the dead: count `respawn_timer` down, return at own HQ at
   full HP when it hits 0.
2. Apply pending card-driven ATK buffs (existing flow).
3. `recall_sys.process_recalls` — HP ≤ threshold → home at full HP, holding
   still for this turn's movement pass.
4. **Same-cell engagement resolution** — see "Combat" section below. Fills
   `damage_map` / `turret_dmg` / `advance_set` / `retreat_set` / `engaged`
   from the pre-movement positions. Turret sieges are part of it: an attacker
   is a pilot **standing on** the enemy turret cell, so there is no separate
   adjacent-siege pass.
   Right after it, `_apply_lane_bonds` spreads any retreat to the pilot's
   lane-bond partners (see "Lane bond" below).
5. Apply collected pilot / turret damage. T1 destruction triggers
   `_on_t1_destroyed` (jungle capture). Any destroyed turret also frees the
   corresponding `Building` node from `BuildingLayer`.
6. **`resolve_movement`** — ONE pass that moves everybody: free movers and
   combat pushes together. See "Movement" below.
7. HQ damage: any pilot sitting on enemy HQ once any defender T2 is down.
8. `process_neutral_zone_captures` — junglers stepping on a neutral cell flip it.
9. **성장치 수입** — `award_frontline_income` + `process_jungle_camps`. 아래
   "성장치 수입" 참조. **이동과 점령이 다 끝난 뒤**라야 그 턴의 최종 자리로
   판정된다 — 전선까지 걸어 들어간 턴에는 그 턴부터 벌고, 밀려난 턴에는 못 번다.
10. `check_win_condition` — HQ HP ≤ 0 → game over.

**Damage is applied before movement, and movement is a single pass.** Both
matter. Damage first means a pilot killed this turn never moves and a turret
destroyed this turn is already gone for everybody's pathfinding — previously
free movement saw the pre-damage world and pushes saw the post-damage one.
A single movement pass is what makes the pass-through bug structurally
impossible; the two-pass split is described under "Movement".

### 성장 / 라인전 스탯 (`tick_growth_and_expiries`)
두 시스템이 **건드리는 스탯이 겹치지 않는다** — 성장은 `atk` / `max_hp`,
라인전 스탯은 `hit` / `evasion`.

**성장 — 시간이 아니라 성장치(`PilotData.score`)가 만든다.**
예전에는 이 훅이 살아 있는 파일럿마다 `GROWTH_PER_TURN` 을 누적했다. 그 설계에는
결함이 둘 있었고 둘 다 치명적이었다.
- 아무것도 안 해도 자란다 → 킬 · 포탑 · 파밍이 성장에 **아무 영향이 없다**.
- `atk` 와 `max_hp` 가 **같은 비율**로 자란다 → `atk / max_hp` 가 불변이라
  "몇 대 맞아야 죽는가"가 50턴이 지나도 1타도 안 줄어든다. 성장이 안 보인 게
  아니라 구조상 보일 수 없었다.

지금 성장은 전부 `BattleSim.refresh_growth_stats` 한 곳에서 성장치로부터
파생된다 — `GROWTH_PER_TURN` 은 game_config 에서 삭제됐다.
- **공격력이 체력의 4배 속도로 자란다**: `GROWTH_ATK_PER_SCORE`(2.0/24 =
  +8.33%p per 1k) vs `GROWTH_HP_PER_SCORE`(0.5/24 = +2.08%p per 1k). 성장치
  25k 에서 정확히 **atk ×3.0 / max_hp ×1.5**, 40k 에서 ×4.25 / ×1.81.
  이 비대칭 하나가 성장 체감의 전부다.
- 스탯은 매 턴 곱해 나가는 대신 `PilotData.base_atk` / `base_max_hp` 에서
  **다시 계산**한다 — 반올림이 반복되면 누적 오차가 성장률을 갉아먹는다.
  두 원본은 `PilotData._init` 이 채우므로 메크 스탯 주입(`_stats_for`)을 포함한
  모든 스폰 경로에서 비지 않는다.
- 최대 체력이 오른 만큼 현재 체력도 같이 올린다(`hp += new_max - max_hp`).
- 재계산은 **점수가 움직이는 그 순간**(`BattleSim.add_score`)에 돈다 — 턴 경계가
  아니라 그 자리라야 "킬을 땄더니 세졌다"가 한 박자로 읽힌다. 이 훅에 남은
  재계산은 **보험**이고, 실제로 하는 일은 배율 만료를 걷는 것이다.
- 그래서 카드가 거는 **일시** 공격력은 `atk` 가 아니라 `PilotData.atk_buff` 에
  얹어야 한다. 예전처럼 `atk += buff` 로 밀면 턴 한가운데(처치가 난 자리)의
  재계산이 가산분을 지우고, 턴 끝의 `atk -= buff` 가 원본을 깎아 버린다.
  `refresh_growth_stats` 가 `base × (1 + growth) + atk_buff` 로 마지막에 더한다.
- **죽어 있는 동안은 수입이 없으므로 성장도 멈춘다.** 누적치는 그대로 남아
  부활하면 죽기 전 성장을 들고 돌아온다.
- `growth_rate_mult` 는 이제 성장이 아니라 **성장치 적립**에 곱해진다(안전한
  파밍 턴 만료형 / 완벽한 마무리 작전 단계 만료형). 결과는 같고 배선이 한 겹
  준다. **같은 필드라 나중에 건 쪽이 덮어쓴다.** 후자의 해제는
  `clear_growth_until_phase(team)` 를 `CardPhaseManager` 가 그 팀의 다음 작전
  단계 진입 시 부른다.

**라인전 스탯** (`lane_stat_mod`, ±0.10) — `roll_hit` **하나에만** 걸린다.
전장 자동 교전과 공격 카드가 그 함수를 공유하므로 둘 다 반영되고, 교전 무대는
자기 확률 구간을 쓰므로 반영되지 않는다. 포탑 / HQ 피해는 명중 판정 자체가
없으므로 무관하다. 만료(`lane_stat_expire_turn`)는 성장 만료와 같은 훅에서
처리하며, **죽어 있어도 돈다** — 버프의 수명은 전장에 서 있는지와 무관하다.

### 성장치 수입 (`award_frontline_income` / `process_jungle_camps`)
성장이 성장치에서 나오므로, **성장치를 어디서 버는가가 곧 성장 설계**다.
적립처는 셋이고 둘이 여기 있다(셋째인 처치 현상금은 `BattleSim.mark_pilot_dead`).

**전선 — 레인 파일럿의 수입.** 레인마다 **양 팀의 살아 있는 최전방 포탑 사이**
(포탑 칸 포함)가 전선이고, 살아서 그 안에 서 있는 턴마다 0.50k 가 들어온다.
- 경계는 `_front_boundary_index(team, lane, order)` — 그 팀의 살아 있는 가장
  바깥 포탑(T1 → T2 순)이고, 둘 다 부서졌으면 통로 끝(그 팀 HQ 쪽)이다.
  **T1 이 부서지면 전선이 그 팀 쪽으로 넓어진다** — 밀어낸 만큼 벌 자리가 는다.
- 앞뒤 관계는 `lane_corridor_order(lane)` 이 답한다. 통로를 BFS 로 잇는 그
  자리에서 팀0 HQ 쪽부터 순번을 매겨 두고, **처음 밟았을 때만** 번호를 적어
  웨이포인트 사이를 되짚는 구간이 앞뒤를 뒤집지 못하게 한다.
- 포탑이 부서질 때마다 답이 바뀌므로 `front_line_cells(lane)` 은 **캐시하지
  않는다**. 레인 셋 × 수십 칸이라 비용이 없다.
- **HQ 에서 걸어 나오는 동안 · 저HP 복귀 뒤 다시 걸어가는 동안 · 죽어 있는
  동안은 한 푼도 안 들어온다.** 사망과 복귀의 진짜 비용이 여기 있고, 그래서
  사망에 점수 벌점을 따로 매기지 않는다.
- **정글러는 제외** — 정글러의 전선은 정글이다.

**정글 캠프 — 정글러의 수입.** 모든 **정글/중립 칸**에 캠프가 하나씩 있고
(`BattleSim.jungle_camps`, `셀 → ready_turn`), 밟으면 **0.98k** 를 먹고 그 칸은
**6턴** 뒤에나 다시 찬다. **좌우 중립 두 칸도 포함이다** — 전령 / 용이 그 좌표를
무대로 빌려 쓸 뿐 타일 규칙은 다른 정글 칸과 같다(`objective/README.md`).
- **캠프값이 라이너의 턴당 수입(0.50k)보다 큰 이유**: 캠프는 걸어가야 하고
  재생성을 기다려야 하므로, 캠프당 값이 같으면 정글러의 턴당 수입이 구조적으로
  낮다. 실측(50턴 · 포탑 무파괴 · 적 정글 미점령, 4회 평균)에서 재생성 4턴 ·
  캠프값 0.50k 일 때 정글러 18.4k / 라이너 평균 23.5k = **0.78배**였고, 0.65k 로
  올려 **0.98배**가 됐다. 역산은 `BattleSim.SCORE_JUNGLE_CAMP` 주석 참조.
- 한때 **1.15k** 였다 — 좌우 중립 두 칸이 오브젝트 전용 자리가 되어 캠프 칸이
  14 → 12 로 줄었을 때 그 몫(× 14/12)을 얹은 값이다. 두 칸이 다시 평범한 정글
  칸으로 돌아오면서 그 보정은 근거를 잃어 **0.98k 로 되돌렸다**.
- **재생성이 4턴 → 6턴으로 늦춰지면서 캠프값도 0.65k → 0.98k 로 함께 올렸다.**
  정글러 수입은 전량 캠프이고 획득 빈도가 재생성 주기에 반비례하므로, 주기를
  1.5배로 늘리면 값도 1.5배여야 같은 수입이 나온다. 늦춘 것은 **순회 리듬**이지
  정글러의 몫이 아니다 — 한 칸이 되살아나기를 더 오래 기다리는 대신 한 번 먹을
  때 더 크게 먹는다.
- 판정은 `camp_harvestable(cell, team)` 하나뿐이고 **렌더러도 같은 함수를
  읽는다** — 화면에 보이는 캠프와 실제로 먹히는 캠프가 어긋날 수 없다.
  소유권을 빼고 "지금 차 있는가"만 묻는 `camp_charged(cell)` 이 그 안쪽에
  들어 있고, 렌더러가 **적 소유 칸의 캠프**를 어두운 호박색 아웃라인으로 그릴
  때 쓴다(`rendering/README.md`).
- 먹을 수 있는 것은 **자기 팀 소유이거나 아직 중립인** 칸뿐이다. 적 정글을
  점령하면 돌 캠프가 늘어 라이너를 추월할 수 있다 — 정글 점령의 값이 여기 있다.
- **정산 함수는 `harvest_camp_under(p)` 하나다.** 턴 루프
  (`process_jungle_camps`)와 **정글러를 옮기는 카드**(`_effect_move` — 정밀
  이동 / 정글 파밍)가 같은 함수를 지난다. 카드 쪽이 그 자리에서 먹는 이유는
  박자다 — 턴 루프까지 기다리면 카드를 낸 순간과 수확 사이가 몇 초 벌어져
  "카드를 냈는데 아무 일도 안 일어난" 것으로 보이고, 그 사이 적 정글러가 같은
  칸을 밟으면 통째로 뺏긴다.
- **약탈(`steal_camp`)은 `steal_camp_point(cell, thief)` 로 그 칸의 캠프를
  원격으로 가로챈다** — 값도 재생성 시계도 밟아서 먹는 것과 같고, **소유권은
  건드리지 않는다**. 훔치는 것은 타일이 아니라 그 한 번의 수입이다.
- **적립은 `award_score` 를 지난다** — 곧 초상화 위에 `+0.98k` 팝업이 뜬다.
  정글러의 수입은 전부 캠프에서 나오는데 숫자가 스트립 구석에서 조용히 오르기만
  하면 "캠프를 먹었다"가 화면에 남지 않는다. 순회 리듬이 곧 정글러의 플레이이고,
  획득이 턴마다 열 명이 아니라 한 명에게 한 번씩만 일어나므로 배경이 되지도
  않는다(전선 체류는 반대라 여전히 조용한 `add_score` 다). 약탈도 같다.
- `process_neutral_zone_captures` **뒤**에 돈다: 방금 점령한 중립 칸의 캠프를
  그 턴에 바로 먹게 하기 위해서다.
- 정글러의 이동 목표도 이걸 따라간다 — `_jungle_goal_for` 는 아직 안 잡힌 중립
  칸 다음에 `_best_ready_camp` 을 보고, 먹고 나면 그 칸이 6턴
  비어 다음 캠프가 자연히 새 목표가 된다. **그 반복이 곧 순회**라 예전의
  sticky 로밍은 캠프가 하나도 안 찼을 때의 폴백으로만 남았다.
- **목표를 고르는 비용은 거리가 아니라 `거리 × JUNGLE_CAMP_STALE_PER_STEP −
  방치 턴 수`다.** 거리만 보면 정글러는 **자기 발밑 4칸에 갇힌다**: 한쪽 정글이
  4칸이라 재생성 주기가 그 칸 수에 가까우면 매 턴 한 칸이 되살아나고, 최단 거리 그리디는
  언제나 거리 1짜리 캠프를 찾아냈고, 반대쪽 정글은 개시부터 끝까지 캠프가 꽉 찬
  채 남았다(실측 60턴: 밟은 칸 **6개**, 오른쪽 정글 세 칸은 한 번도 안 밟음 —
  화면에는 "먹을 게 남은 칸을 두고 빈 칸만 도는" 것으로 보인다). 차 있는 채
  놀고 있는 캠프가 턴마다 조금씩 싸지면 방치된 쪽이 주기적으로 가장 싼 목표가
  되어 좌우를 오가는 순회가 된다(같은 60턴: 밟은 칸 **11개**, 캠프 획득
  53 → 45회 = 수입 85%. 그 15%가 순회의 이동 시간이다).
- 목표를 향해 **한 걸음 옮기면 그 목표의 비용은 반드시 더 내려간다**(거리 −1 =
  −3, 방치 +1 = −1, 합 −4). 다른 캠프는 같은 턴에 −1 밖에 안 싸지므로 가는 도중에
  목표가 뒤집혀 왕복하는 일이 없다 — 예전 sticky 로밍이 필요했던 이유가 그
  왕복이었다.
- **발밑의 캠프가 차 있으면 무조건 그 칸이 목표다.** 이동은
  `process_jungle_camps` 보다 앞에 오므로 가만히 있기만 하면 이번 턴에 먹는다 —
  방치 할인에 끌려 떠나면 그 한 턴을 통째로 버린다.

### Combat (`_resolve_cell`)
Combat happens **only between pilots in the same cell**. There is no
adjacent-cell engagement and no concept of attack range.

Junglers and lane pilots run on **separate engagement scopes**. Each cell is
split into `t{0,1}_lane` (non-junglers) and `t{0,1}_jung` (junglers); a jungler
will never engage a lane enemy and a lane pilot will never engage an enemy
jungler. `_has_engaging_enemy_at` enforces the same rule for movement so a
jungler crossing a lane cell does not freeze on a lane enemy and vice versa.

Per cell with at least one pilot:
- **Lane scope (lane pilots only)**:
  - **Pilot vs pilot** (`_resolve_pilot_combat`): teams paired 1:1 by ascending HP
    *for damage rolls*. Each pair rolls hit independently. Hit chance =
    `attacker.hit / (attacker.hit + defender.evasion)` (`roll_hit`, public —
    card attacks share it, see `card_phase/README.md`) — **battlefield-only**;
    the 교전 무대 remaps this into its own 80~100% band
    (`ENGAGE_HIT_MIN` / `ENGAGE_HIT_MAX`, see `engage/README.md`), and the two
    are tuned independently. **라인전 스탯**(`lane_stat_mod`)이 붙는 유일한
    지점도 여기다 — `lane_adjusted()` 가 공격자의 `hit` 과 방어자의 `evasion` 에
    각자 자기 배율을 곱한다.
    Damage per landed hit is `_pilot_hit_damage(attacker)` =
    `atk × BATTLE_PILOT_DMG_MULT` (game_config, **0.35**), rounded, floored at 1.
    That multiplier covers **only damage pilots take from battlefield
    engagement** — the same helper is used by the turret-siege defender rolls.
    Pilot → turret and pilot → HQ damage stay at raw `atk` (siege speed is match
    length), and attack cards / the engage arena run their own numbers. It exists
    because a single unmitigated hit could exceed the whole recall window: an
    atk-28 opponent against a max_hp-75 sniper takes 37% per hit, so the sniper
    fell from above the 20% recall line straight to 0 and **the low-HP recall had
    no interval to fire in**. Damage from successful
    hits is applied at step 4 of the loop and only affects paired pilots.
    Push, however, is decided **at the team level for the whole bracket**:
    - Tally unilateral-hit wins per team across all pairs.
    - Side with strictly more unilateral wins sweeps: **every** pilot of that
      side in the cell (including unpaired ones, e.g. the spare in a 2v1)
      advances, **every** opposing pilot in the cell retreats.
    - Tie (including 0-0) → no push.
    - Unpaired pilots take no damage this turn but ride the team push.
    - The *net* result on the board is that **the whole cell slides one tile
      toward the loser's HQ**: the losers retreat and the winners follow them
      in, so the fight continues next turn one cell further up the lane. That
      is the lane push. The follow-up is only cancelled when the loser has
      nowhere to retreat to, or when the tile ahead is an enemy turret — see
      "Movement" step 3.
  - **Pilot vs enemy turret** — a lane pilot **occupies** the same-lane enemy
    turret cell. Advancing into it is an ordinary move (nothing bounces it back
    at destination-selection time), so the sequence is *enter this turn, attack
    next turn*. There is exactly one entry point, `_resolve_turret_combat`,
    reached from `_resolve_cell` → `_resolve_lane_at_turret` whenever a lane
    pilot stands on an enemy turret cell — walked in, pushed in behind a beaten
    enemy, or dropped there by a card. `resolve_turret_sieges` /
    `_apply_sieges_for` (the old adjacent-siege pass) are **gone**.
    - Judgement (`_apply_turret_siege`), in this order:
      1. **Turret damage is unconditional** — same-lane attackers put their full
         `atk` into the turret **with no hit roll** (`BATTLE_PILOT_DMG_MULT` is
         pilot-damage only). A defender camping the tile does not shield it.
      2. **Then attackers and defenders trade hit rolls**, paired by ascending
         HP, both directions dealing the halved `_pilot_hit_damage`. Attackers
         used to deal *nothing* to defenders — their whole attack went into the
         turret — so a defender sitting on its turret beat on the attacker for
         free. Now the attacker grinds the turret *and* still rolls on whoever
         is standing on it.

      T2 is invulnerable while own-lane T1 is alive (`_turret_attackable`), and
      the pilot-vs-pilot exchange runs regardless of that (the attackers are
      still in the cell with the defenders). Turret
      destruction frees the matching `Building` node via
      `building_registry.unregister(b); b.queue_free()` so the visual disappears.
    - **Knockback needs a defender.** After the judgement the attackers go into
      `retreat_set` **only if a same-lane defender stands on the cell**, and then
      unconditionally — the defender's roll may miss and the attacker still
      falls back to the tile it came from. With no defender there is nobody to
      push the attacker out: it stays on the turret and grinds it every turn.
      The single exception is an **unattackable** turret (T2 behind a live T1):
      there is nothing to grind, so the attacker always retreats and can never
      be frozen on it by card displacement.
    - Everyone on the cell is `engaged`, so an attacker with no defender holds
      its ground instead of walking on, and a defender is pinned only for as
      long as attackers stand on its turret.
    - Net cadence: turret damage **every turn** when undefended, **every other
      turn** when defended (enter → hit + pushed out → re-enter).
    - Off-lane lane pilots (e.g. a RIGHT pilot pushed into a CENTER turret cell
      by card displacement) are bystanders to the turret. If both teams have
      off-lane pilots in the cell they fight each other as pilot-vs-pilot;
      otherwise they sit out the turn and rely on the next phase-end recall to
      pull them out of position.
    - Junglers in the same cell are excluded entirely — they neither attack
      nor defend turrets.
- **Jungle scope (junglers only)**: jungler vs jungler runs in parallel using
  the same `_resolve_pilot_combat` rules, contained to the cell's junglers.

Two enemies that approach each other on a lane collide in a shared cell, and
same-cell combat takes over on the following turn. `resolve_movement` guarantees
it: nobody can move through anybody.

Turrets do not attack pilots (the old retaliation logic has been removed).

### 수호 연계 편승 대기열 (`_guardian_rides`)

지원 Q(수호 연계)는 "이 메크의 보호막을 두른 아군이 피해를 주면 이 메크도 그
적을 친다". 전장 피해는 **판정(`_resolve_*` → `damage_map`)과 적용(HP 깎기)이
갈려 있으므로**, 편승 공격을 판정 자리에서 곧장 굴리면 안 된다 — 편승은
`CardPhaseManager.deal_simple_attack` 을 지나 **그 자리에서 HP 를 깎기** 때문에,
아직 적용되지 않은 이번 턴의 피해보다 먼저 상대를 눕히고 나머지 판정이 시체를
상대로 계속 굴러간다.

그래서 `_credit_pilot_damage` 는 (공격자, 피해자) 쌍을 `_guardian_rides` 에
**적어만 두고**, 파일럿 피해 적용 루프가 끝난 직후 `_flush_guardian_rides()` 가
한꺼번에 굴린다. 그때는 이번 턴에 쓰러진 사람이 이미 `alive == false` 라
`MechSkillSystem.on_shielded_ally_damage` 의 게이트가 그 둘을 걸러 낸다.
부르는 자리는 둘 — 턴 루프(`simulate_turn`)와 전진 카드 경로
(`_apply_card_damage`). 카드 공격은 판정과 적용이 갈려 있지 않으므로
`CardPhaseManager` 가 자기 피해 지점에서 곧장 부른다.

### Debug logging hooks
Every `grid_pos` mutation in this folder reports to `_bs.blog`
(`debug/BattleLogger.gd`) via `log_move(p, from, to, kind, note)`, and every
hold reports via `log_block(p, reason)`. `simulate_turn` stamps a `stage` name
before each pass so the log says which pass moved whom.
`_enemies_on_cell_str(p)` is a logging-only helper that names the enemies
standing on the pilot's cell right after a step. See
[`../debug/README.md`](../debug/README.md).

### Movement (`resolve_movement` — one simultaneous pass)

Free movement and combat pushes used to be two passes with damage application
between them, and neither looked at where it was sending a pilot. That let two
same-lane enemies trade cells inside one turn: an un-engaged pilot walked into
an enemy's cell, and that enemy — queued to advance from a fight it had just
won — pushed out into the cell just vacated. Both moves were individually legal,
so nothing caught it, and the pair passed through each other without engaging.
Confirmed twice by the cross detector in a 6-battle headless run before the fix,
zero times in 241 turns after it.

**There is now exactly one movement pass, and every pilot's intent is visible
inside it.**

1. **Intent** — every alive pilot gets one: `push-adv` / `push-ret` when combat
   decided one, *nothing at all* when it is in `engaged` without a push result
   (locked in melee), otherwise `free`. Push outranks `engaged`, matching the
   old two-pass behaviour. A pilot carrying `recall_hold` is skipped before any
   of that and the flag is cleared on the spot — that one skipped pass is the
   whole cost of a 본진 복귀, and clearing it here is what makes it exactly one.
2. **Lockstep rounds** — in each round, every still-moving pilot names its next
   cell against the *same* snapshot; conflicts are arbitrated; the survivors
   commit together. A `move_range` > 1 pilot takes part in more rounds, a push
   in exactly one. Because destinations are all chosen before any of them
   lands, nobody can walk into space another pilot is about to leave.
3. **Advance-over-a-stuck-enemy veto** (`_veto_advance_over_stuck_enemy`) —
   advance walks toward the *enemy* HQ and retreat walks toward the retreater's
   *own* HQ, and for the two sides of one fight those are **the same
   direction**, so both halves of a push name the same cell. That is intended:
   the winner follows the loser in and the lane moves one tile. This used to be
   inverted (`_veto_push_followthrough` cancelled the *advance* so the winner
   "held the ground"), and because the two destinations always coincide on a
   straight lane, a pilot that won its fight could never move forward — the
   loser drifted back and the line never advanced. The only thing vetoed now is
   an advance **over an enemy that is not leaving the cell** (`_stuck_enemy_on_cell`
   / `_is_leaving_cell`): nobody walks past a pilot still standing in the
   contested tile. Runs *after* head-on arbitration, since a move cancelled
   there turns that pilot into a stuck one. **An enemy turret cell is not a
   veto**: when the beaten side retreats onto its own turret the winner follows
   it in, and the siege takes over from that cell next turn.
4. **Head-on arbitration** (`_veto_head_on_exchanges`) — A aiming at B's cell
   while B aims at A's would be a pass-through. Vetoing *both* would leave them
   adjacent and deadlocked forever, so the higher-priority mover takes the step
   and the other holds: they finish in the same cell and fight next turn, which
   is what the engagement rules want. `_move_priority` = push (+10) over free,
   then team 0 (+1) as a deterministic tie-break — so the side that just won a
   fight keeps its advance. Cross-scope pairs (jungler vs laner) are skipped;
   they never engage, so sliding past each other is correct.
5. **Contact ends the turn** — after each round, any mover now sharing a cell
   with a same-scope enemy is deactivated and takes no further steps.
6. Animations fire once per pilot at the end, from the turn's original cell.

Destination helpers are pure — they compute a cell and never touch `grid_pos`,
so the resolver can veto a move after asking for it:
- `_desired_free_cell(p)` — holds (returns `p.grid_pos`) when a same-scope
  enemy already shares the cell. Otherwise defers to `_next_step_for(p)`, which
  may well name a same-lane enemy turret cell: the pilot walks onto it.
- `_next_step_for(p)` — raw goal + BFS, ignoring occupancy:
  - Jungler → `_jungle_goal_for(p)` (best ready camp, else a **sticky** roam
    target — see "Jungler roaming" below).
  - **Every lane pilot → `current_waypoint(p)`, with no exceptions.** There is
    no defensive behaviour: a pilot does not turn around because its own turret
    is being hit. Pilots leave their HQ, walk their lane, and run into the enemy
    laner — that collision *is* the design. (An earlier SUPPORT fall-back that
    hugged the forward own turret when its same-lane SNIPER was down has been
    removed. It also had to be careful never to skip the `current_waypoint`
    call, since that call is what advances `waypoint_idx` — a trap that no
    longer exists now that there is only one goal.)
- `_desired_push_advance_cell(p)` — toward the lane goal (jungle goal for
  junglers). Nothing filters enemy turret cells out any more: a push win lands
  the winner **on** the turret, which is where the siege happens. (The old
  `_bounce_off_enemy_turret`, which turned such a step into a hold and paired
  with the adjacent-siege pass, is gone.)
- `_desired_push_retreat_cell(p)` — toward own HQ for lane pilots, toward the
  nearest own-captured cell for junglers. Never blocked by a turret —
  retreating away from one is always allowed. `_rollback_waypoint(p)` runs
  after the commit. **This is the same physical direction as the winner's
  advance** — read the two helpers as a pair: they are what makes a won fight
  slide the whole cell one tile up the lane.
- All pathfinding calls pass `_movement_forbidden_for(p)` to `bfs_next_step`:
  - Junglers receive `{}` (no restrictions).
  - Lane pilots receive jungle/neutral cells **plus alive enemy turret cells in
    lanes other than their own**. The same-lane enemy turret stays reachable —
    BFS must be willing to name it as the next step, because the pilot is meant
    to stand on it and besiege from there. This
    also stops e.g. right-lane pilots from routing through the still-alive
    center T2 cell on their way to the enemy HQ after their own turrets fall.
  - The forbidden dict is rebuilt fresh per call — `_bs.neutral_zone_cells` is
    never mutated.

### Lane bond (`lane_bond_partners` / `_apply_lane_bonds` / `_enforce_lane_bonds`)
**Lane pilots of the same team assigned to the same lane are bonded.** Today
only the bottom duo (SNIPER + SUPPORT on RIGHT) qualifies. The check reads
`lane`, not role, so a future lane reassignment carries the bond with it.
Junglers are never bonded.

- **Only while standing on the same cell.** Once separated (recall, death),
  each moves on its own; the bond resumes when they share a cell again. Because
  of that, a bond group is always a full clique inside one cell, so one pilot's
  partner list is the whole group minus itself.
- **Retreat wins.** `_apply_lane_bonds(advance_set, retreat_set)` runs right
  after cell resolution. It runs in both `simulate_turn` and `_advance_tick`.
  If one pilot got a retreat verdict, it moves the partner from advance to
  retreat. The typical case is the turret cell: the turret defender hits only
  the carry, and the support is dragged back with them. Before this change the
  support stayed on the turret cell and kept grinding.
- **Advance only together.** `_enforce_lane_bonds(wants)` runs inside each
  lockstep round, after both vetoes. If any member has no surviving ADVANCE
  want, every member's advance is cancelled. If any member has a surviving
  RETREAT want, a vetoed partner is re-enabled toward the same destination.
- **Not bonded:** free walking, card / skill movement, and low-HP or card
  recall (`RecallSystem`, `_effect_move`, …). Those move only their target; the
  bond code never runs on those paths.
- Bond events log under `BOND`. There is no on-screen indicator (decided
  2026-10-03).

### Lane corridors (`lane_corridor` / `lane_corridor_count`)
The per-lane set of cells the lane actually runs through, built once by
BFS-chaining that lane's waypoints with jungle cells forbidden, then cached in
`_lane_corridors`. Team 1's path is team 0's reversed, so the cell *set* is
shared and there is one entry per lane. Note `LANE_NAMES` also counts a
GUERRILLA slot — iterate with `lane_corridor_count()`, not `LANE_NAMES.size()`.

Its only consumer is `RecallSystem._is_out_of_position`, which asks "did a card
drop this lane pilot on somebody else's lane?".
- `current_waypoint(p)` — auto-advances `waypoint_idx` when pilot stands on the
  current waypoint cell. Safe to call more than once per turn (idempotent while
  `grid_pos` is unchanged), which the lockstep rounds rely on.

**What this does NOT prevent**: two enemies on *different* lanes standing one
cell apart and walking to different cells, ending with their lane-axis order
flipped. They never share a cell or an edge, and same-cell-only combat has no
zone of control, so neither could have engaged the other — most visible at an
HQ cell, where a recalled defender heads out down its own lane while an
attacker from another lane steps onto the HQ. The cross detector deliberately
ignores cross-lane pairs for this reason.

### Jungle / neutral zones
The map starts with both jungles already captured. Coordinates use the
TileMap negative-coord system:

| Owner   | Cells |
|---------|-------|
| Team 0  | (-2,0), (-2,-1), (-3,0), (0,0), (0,-1), (1,0) |
| Team 1  | (-2,-3), (-2,-2), (-3,-2), (0,-3), (0,-2), (1,-2) |
| Neutral | (-3,-1), (1,-1) — uncaptured at start, up for grabs |

- `init_neutral_zones()` — paints the initial owner of each cell.
- `process_neutral_zone_captures()` — a jungler standing alone on a neutral
  cell (no enemy in same cell) flips it to their team.

#### 좌우 중립 칸 = 오브젝트 무대, 그러나 **평범한 정글 칸**
`(-3,-1)` 과 `(1,-1)` 은 전령 / 용이 서는 자리이지만 **타일 규칙은 다른 정글
칸과 한 글자도 다르지 않다**: 캠프가 서고(`init_jungle_camps`), 정글러가 밟아
점령하고(`process_neutral_zone_captures`), 순회 목표가 되고, 사이드 T1 파괴의
**측면 중립 탈취 분기**(`_on_t1_destroyed`)로 주인이 바뀐다.

한때는 **상시 중립**이었다 — 캠프도 점령도 없는 오브젝트 전용 자리. 그때는
`is_objective_cell()` 이 그 판정이었고 `_nearest_uncaptured_neutral()` 은 판정이
영원히 참이 되므로 함수째 삭제됐었다. 두 칸이 정글로 돌아오면서 셋 다 되살아
났고, `is_objective_cell` 은 이제 없다. 오브젝트 쪽은 그 좌표를 **무대로 빌려
쓸 뿐**이라 타일 상태를 읽지도 쓰지도 않는다 — 남은 턴 수 표시도 타일이 아니라
상단 패널로 옮겨 갔다(`ui/ObjectiveTimer.gd`). 자세한 내용은
`objective/README.md`.

#### Jungler roaming (`_jungle_goal_for`)
**맨 먼저는 개시 전에 고른 시작 칸**(`PilotData.jungle_start_cell`, 정글 시작
오버레이가 새긴다)이다 — 그 화면이 그린 경로가 실제 걸음이어야 하므로 도달할
때까지 다른 무엇보다 앞선다. 도달하거나 그 칸이 상대 것이 되면 비우고 아래
순서로 넘어간다. 단독 실행에서는 비어 있다. 이 함수를 그대로 앞으로 굴려 정글러의 걸음을 예측하는 것이 `predict_jungle_path(p, turns)` 다(정글 시작 화면의 경로 — 상태를 잠깐 밀었다 되돌린다. 우리 정글러 혼자 걷는다고 보는 단순 예상 루트라 상대 정글러와의 충돌은 계산하지 않는다. `gambit/README.md`).

**한 걸음은 `jungle_step(p, goal)` 이 정한다 — 같은 거리라면 상대 소유 정글 칸을
피해 간다.** 정글러에게는 금지 칸이 없어 언제나 최단 거리였고, 최단 경로가 여럿이면
이웃을 훑는 순서(위쪽 먼저)가 길을 정해 팀0 정글러가 좌우 중립을 오갈 때 상대 정글을
가로질렀다(`(-3,-1)` → `(-2,-2)` → `(-1,-2)` → `(0,-2)` → `(1,-1)`, 넷 중 둘이 상대
칸). 지금은 상대 소유 정글 칸(목표 칸 자체는 빼고)을 막고 먼저 묻고, 길이 없을 때만
막지 않고 묻는다. 실측: 놓을 수 있는 8칸 모두 예상 경로에 상대 칸 0, 40턴 동안 상대
정글 체류 0턴, 같은 경로가 `(-2,-1)` → `(-1,-1)` → `(0,-1)` → `(1,-1)` 로 바뀌었다.
턴 루프의 세 자리(`_next_step_for` · 밀어붙이기 전진 · 후퇴)와 예측
(`predict_jungle_path`)이 모두 이 함수를 지난다.

그 다음, 아직 아무도 점령하지 않은 중립 칸이 **1순위**다(`_nearest_uncaptured_neutral`,
밴픽에서 고른 `jungle_start_pref` 가 좌우 순서를 정한다) — 밟는 것만으로 지도
한 칸이 우리 것이 되고 그 칸의 캠프까지 딸려 온다. 그 다음이 the best ready camp
(`_best_ready_camp`). With no camp charged the jungler
roams to a **sticky** target parked on `PilotData.jungle_roam_target`, and the
target is only recomputed when it has been reached, was never set, or has
stopped belonging to the jungler's team (a lost T1 can flip a jungle cell). The
replacement is `_farthest_captured_cell(grid_pos, own_captured)` — the
own-captured cell farthest from where the jungler is standing *at that moment*.

The target used to be recomputed from scratch every turn, which is the same
coin flipped repeatedly: one step toward the far side makes the side just left
the farthest one, so the jungler turned around. In a logged battle A0 rode
`(-1,0) ↔ (-1,-1)` from turn 31 to the end of the match — and those are
**mid-lane** cells on the corridor between the two jungles, so it read as the
jungler loitering in front of its own mid T1 while the enemy sieged it. With a
sticky target the jungler completes the tour and comes to rest only on a jungle
cell; lane cells are crossed, never idled on. It still does not engage lane
pilots or turrets — see "Engagement scopes".
- `_on_t1_destroyed(td, log_lines)` — two priority branches keyed off
  per-lane "취약지점" (vulnerable cell) sets in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}`.
  A vulnerable point is the jungle cell in a team's own territory closest to
  enemy territory along that lane: side lanes have 1 cell, mid has 2 flanking
  cells. When a team's same-lane T1 falls:
    1. **Restoration (all lanes)** — if any of the *capturer's* own same-lane
       vuln cells are currently owned by the loser, those cells flip back to
       the capturer and nothing on the loser's side is taken.
    2. **Default capture** — the loser's same-lane vuln cell(s) flip to the
       capturer. Side lanes flip 1 cell, mid flips both flanking cells.

  The old **side-neutral override** (side-lane T1 grabbing `(-3,-1)`/`(1,-1)`
  when the loser owned it) is deleted: those cells are permanently neutral now,
  so the condition could never be true.

### Spawning
- `spawn_pilots_with_lanes()` — builds 5 player + 5 enemy `PilotData` using
  `GambitPhaseManager.ROLE_TO_LANE`. Stats come from `_stats_for(...)`.
- `_stats_for(...)` — when match_ctx is active, pulls hp/atk/presence from
  the assigned mech and everything else from the **선수 스탯 6종**:
  `field_hit`/`field_eva` → `hit`/`evasion`, `engage_hit`/`engage_eva` →
  the engage-arena pair, `atk_growth`/`hp_growth` → `atk_growth_mult` /
  `hp_growth_mult` (via `PlayerData.growth_mult`). Otherwise falls back to
  `ROLE_STATS` defaults with every stat at 50 / every multiplier at 1.0.
- `_pilot_id_from_roster(ctx_active, roster, idx, fallback_id)` — used to
  populate `pilot.pilot_id` (the portrait lookup key). Returns
  `roster[idx].id` only when ctx is active AND the id is inside the regular
  pool (`0..PilotImages.POOL_SIZE-1`). Otherwise returns `fallback_id`
  (player-side: `idx` 0..4; enemy-side: `5 + idx` 5..9). This guarantees
  every pilot — standalone runs, INTL matches with ids ≥ 100, malformed
  rosters — still gets a valid id so `PilotImages.face_for` /
  `PilotImages.circle_for` resolve to a real portrait instead of falling
  back to the placeholder colored disc.
- The assassin (GUERRILLA) gets `jungle_start_pref` from `match_ctx.jungle_start_dir`
  (player team) or randomly (enemy team).
- `spawn_turrets()` — reads from `FieldLoader.turret_pos`, falls back to
  hardcoded coordinates.

### Card-driven lane push (`advance_pilot` / `_advance_tick`)
Public entry point used by the 전진 (advance:N) card. Runs `N` mini-ticks; one
tick = `_advance_tick`, which pushes the lane one cell. It reuses the turn
loop's helpers (`_resolve_cell`, `_desired_push_*_cell`, `_apply_turret_siege`)
and changes exactly one thing about them: **the caster's side is declared the
winner of its cell.**

Order inside a tick — the same order `simulate_turn` uses, and it matters:

1. **`_resolve_cell` on the caster's cell** — damage rolls run untouched, so
   the caster can still get hit hard on the way in.
2. **Forced judgement** — every member of the caster's *group* (the caster plus
   every alive same-team, **same-scope** pilot on that cell,
   `_same_scope_allies_at`) is moved into `advance_set`, and every same-scope
   enemy on the cell (`_same_scope_enemies_at`) into `retreat_set`, whatever the
   dice said. Reading the unilateral-hit tally instead meant a bad roll turned
   the 전진 card into a retreat card — the caster walked back toward its own HQ.
   The exception is a caster **already standing on a same-lane enemy turret
   cell**: the turret rule wins, and it now splits by defender —
   - **defender on the cell** → the group hits the turret and falls back one
     tile. That is the only backwards move 전진 can produce.
   - **no defender** → the group hits the turret and **holds the cell** (in
     neither set). It keeps the turret pinned instead of walking off it.

   A caster that is a jungler, or on an *off-lane* enemy turret cell, ignores the
   turret entirely and advances as usual.
3. **`_apply_card_damage`** — pilots (보호막 first) then turrets, with T1
   destruction firing `_on_t1_destroyed`, exactly as step 5 of `simulate_turn`.
   A caster that died here stops the tick before anything moves.
4. **Movement** — enemies are pushed out first so the group has somewhere to
   land, then the group steps (`_step_pilot`). If an enemy could **not** be
   pushed (nowhere to retreat) the group holds: nobody walks past a pilot that
   is still standing in the contested cell.

Because the group and the pushed enemies move in the same physical direction,
the group normally lands on the cell the loser was just expelled to and the two
meet again one cell further up the lane — that is the lane push. In front of a
turret the loser ends up **on** the turret cell and the group follows it in;
the siege then runs from that cell on the next tick or turn. There is no
adjacent siege — a tick that only moves the group onto the turret deals no
turret damage.

Skips `process_respawns` / `process_neutral_zone_captures` and does **not**
bump `turn_count`. Win condition
is rechecked at the end so a turret-destruction kill via 전진 resolves
immediately.

### Misc helpers
- `t1_alive_in_lane`, `any_t2_destroyed`, `has_enemy_turret_at`
- `process_respawns`
- `check_win_condition`

### Animation hooks (UI-only side-effects)
SimulationCore and RecallSystem call back into `BattleSim` after mutating
logical state so the renderer can soften the transition:

- `resolve_movement` accumulates each mover's **path** (`m["path"]`, one cell
  appended per committed lockstep round) and calls
  `_bs.anim_pilot_move_path(p, path)` once at the end for every pilot that
  actually moved. 렌더러는 그 폴리라인을 따라 초상화를 미끄러뜨리므로
  `move_range` 2 짜리 이동이 중간 칸을 스쳐 지나가지 않고 **꺾여서** 간다.
  `advance_pilot` 은 미니틱마다 `_step_pilot` → `_bs.anim_pilot_move(p, orig)`
  를 부르고, 같은 프레임의 걸음은 그쪽에서 같은 경로에 이어 붙는다.
- The damage_map application loop calls `_bs.anim_pilot_shake(p)` for surviving
  pilots that took damage > 0 — **인자 없는 기본 세기**(0.18s / 6px)다. 공격
  카드는 같은 함수에 자기 상수(`ANIM_SHAKE_CARD_*`, 0.26s / 20px)를 넘겨 훨씬
  격렬하게 흔든다.
- The `turret_dmg` application loop calls `_bs.anim_turret_hit(td)` for turrets
  that took damage > 0 **and survived** — both in `simulate_turn` step 5 and in
  `_apply_card_damage`. A killing blow is skipped: the `Building` node is freed
  on the same line, so there would be nothing left to shake.
- `process_respawns` calls `_bs.anim_pilot_respawn(p)` after returning a **dead**
  pilot to HQ; that call also clears any leftover 전사 연출.
- `RecallSystem.return_to_hq` calls `_bs.anim_pilot_recall(p, orig_pos)` after
  snapping `grid_pos` to HQ — visuals fade out at `orig_pos`, then fade in at
  HQ. Both halves always play now (there is no "stay hidden for N turns" split
  any more), and the pilot is standing still that turn anyway, so the fade-in
  is anchored at the HQ for its whole duration.
- Every death goes through `_bs.mark_pilot_dead(p)`, which stamps the scaled
  respawn timer and starts `anim_pilot_death` — dimmed in place for
  `ANIM_DEATH_HOLD_DUR`, then fading upward off the field.

Logical state is unaffected: the sim never reads animation fields on
`PilotData`. Animation timing constants live on `BattleSim`.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| 정글 캠프 값 | 캠프가 서는 칸은 **14칸**(정글 12 + 좌우 중립 2)이고 `BattleSim.SCORE_JUNGLE_CAMP` 은 **0.98k** 다. 한때 중립 두 칸이 오브젝트 전용 자리가 되어 12칸으로 줄었을 때 그 몫(× 14/12)을 얹은 1.15 였는데, 두 칸이 정글로 돌아오면서 되돌렸다 — 전령 / 용은 캠프를 밀어낸 적이 없으므로 되돌려 줄 몫도 없다. |
| 전선 (前線) — 레인 파일럿의 수입원 | 레인마다 **양 팀의 살아 있는 최전방 포탑 사이**(포탑 칸 포함)가 전선이고, 레인 파일럿은 **살아서 그 안에 서 있는 턴마다** `SCORE_FRONTLINE_PER_TURN`(0.50k)을 번다(`SimulationCore.award_frontline_income`, 턴 루프 8단계 — 이동과 점령이 모두 끝난 **그 턴의 최종 자리**로 판정한다). 외곽(T1)이 부서지면 그 팀 쪽 경계가 T2 로, T2 마저 부서지면 통로 끝(HQ 쪽)으로 물러나 **전선이 넓어진다** — 밀어낸 만큼 벌 자리가 늘어난다. 판정은 `front_line_cells(lane)` 이 매 턴 새로 만든다(포탑이 부서질 때마다 바뀌므로 캐시하지 않는다; 레인 셋 × 수십 칸이라 비용이 없다). 앞뒤 관계는 `lane_corridor_order(lane)` — 통로를 만드는 그 자리에서 팀0 HQ 쪽부터 번호를 매겨 둔 표이고, 처음 밟았을 때만 번호를 적어 되짚는 구간이 앞뒤를 뒤집지 않는다. **HQ 에서 걸어 나오는 동안, 저HP 복귀 뒤 다시 걸어가는 동안, 죽어 있는 동안은 한 푼도 안 들어온다** — 사망과 복귀의 진짜 비용이 여기 있다. **정글러는 제외**(정글러의 전선은 정글이다). 화면에는 전선 셀 테두리가 얇은 금색으로 그려진다(`BattleRenderer._draw_front_line_overlays`) — 수입이 위치에서 나오는데 그 위치가 안 보이면 왜 뒤처지는지 알 수 없기 때문이고, 타일 색(정글 점령)과 경쟁하지 않게 테두리로만 표시한다. |
| 정글 캠프 — 정글러의 수입원 | **모든 정글/중립 칸에 캠프가 하나씩** 있고(`BattleSim.jungle_camps`, `셀 → ready_turn`), 개시 시점에는 전부 차 있다(`SimulationCore.init_jungle_camps`, `init_neutral_zones` 바로 뒤). 정글러가 **차 있는 캠프** 위에 서면 `SCORE_JUNGLE_CAMP`(**0.98k**)를 먹고 그 칸은 `JUNGLE_CAMP_RESPAWN_TURNS`(**6턴**) 뒤에나 다시 찬다 — 그래서 정글러는 한자리에 머물 수 없고 **계속 순회**해야 라이너의 턴당 수입과 같아진다(자리 지키기와 순회의 비용 차이가 그대로 남는다). **캠프값은 실측에서 역산한 값이다** — 기준선은 "50턴 · 포탑 무파괴 · 적 정글 미점령"(포탑을 불사로 만들어 T1 파괴 보상과 전선 확장을 둘 다 없앤 헤드리스 4회 평균)이고, 재생성 4턴 · 캠프값 0.50k 에서 정글러 18.4k / 라이너 평균 23.5k = **0.78배**였다. 정글러 수입은 전부 캠프(50턴에 약 35회)이므로 필요한 배수는 22.45/17.375 = 1.29 → 0.50 × 1.29 ≈ 0.65(적용 후 실측 0.91~1.07배, 평균 0.98). **재생성이 4턴 → 6턴으로 늦춰지면서 캠프값도 ×1.5 인 0.98k 로 함께 올렸다** — 획득 빈도가 주기에 반비례하므로 그래야 수입이 유지된다. 늦춘 것은 **순회 리듬**이지 정글러의 몫이 아니다(한 칸을 더 오래 기다리는 대신 한 번에 더 크게 먹는다). 적 정글 점령은 그 위에 얹히는 가속이고, 이 상수는 **점령이 없는 하한선**을 라이너와 나란히 놓을 뿐이다. 먹을 수 있는 것은 **자기 팀 소유이거나 아직 중립인** 칸의 캠프뿐이므로, 적 정글을 점령하면(중립 칸 선점 / T1 파괴 보상) 돌 캠프가 늘어 라이너를 추월할 수 있다 — 이것이 정글 점령의 값이다. 판정은 `camp_harvestable(cell, team)` 한 함수이고 **렌더러도 같은 함수를 읽으므로**(그 칸의 **타일 테두리**를 노란 아웃라인으로 두른다) 보이는 캠프와 먹히는 캠프가 어긋날 수 없다. **적 소유 칸의 캠프도 화면에 있다** — 같은 아웃라인을 어두운 호박색(`BattleRenderer.CAMP_LINE_ENEMY_COLOR`)으로 둘러 "있지만 지금 우리 것은 아니다"를 색 하나로 가른다. 소유권을 빼고 "지금 차 있는가"만 묻는 `SimulationCore.camp_charged(cell)` 이 그 판정이며, 뺏을 값어치가 지금 있는지가 안 보이면 약탈이 판단의 대상이 되지 못한다. **아웃라인은 인접한 같은 부류끼리 이어 붙는다** — 아래 "캠프 아웃라인" 항목. 예전에는 칸 한가운데의 작은 **마름모**였다(우리 것 = 꽉 참 / 적 것 = 속 빔). **정산 함수는 `harvest_camp_under(p)` 하나**이고 턴 루프(`process_jungle_camps`)와 **정글러를 옮기는 카드**가 같이 지난다 — 카드로 캠프 위에 내려앉으면 턴 루프를 기다리지 않고 **그 자리에서** 먹는다(아래 "이동 카드" 항목). 정산은 `process_neutral_zone_captures` **뒤**에 돈다 — 방금 점령한 중립 칸의 캠프를 그 턴에 바로 먹게 하기 위해서다. |
| 이동 카드 = 즉시 캠프 수확 | 정글러를 옮기는 카드(**정밀 이동 / 정글 파밍**, `_effect_move`)가 **차 있는 캠프 위에 내려앉으면 그 자리에서 먹는다** — 턴 루프의 `process_jungle_camps` 를 기다리지 않는다. 진입점은 `SimulationCore.harvest_camp_under(p)` 하나이므로 값도 재생성 시계도 밟아서 먹는 것과 같고, 로그와 카드 결과 문구에 `· 캠프 +0.98k` 가 붙는다. 기다리게 두면 카드를 낸 순간과 수확 사이가 몇 초 벌어져 "카드를 냈는데 아무 일도 안 일어난" 것으로 보였고, 그 사이 적 정글러가 같은 칸을 밟으면 통째로 뺏겼다. |
| 약탈 (`steal_camp`) | **적 소유 정글 칸의 차 있는 캠프 하나를 원격으로 가로챈다** — 시전자가 `SCORE_JUNGLE_CAMP`(0.98k)를 받고 그 칸은 6턴 재생성으로 들어간다(`SimulationCore.steal_camp_point`). **타일 주인은 바뀌지 않는다**: 훔치는 것은 땅이 아니라 그 한 번의 수입이고, 그래서 적 정글러는 다음 재생성까지 그 칸을 빈손으로 지나간다. 유효 대상은 **적 팀 소유 + 캠프가 차 있는 정글 셀 전부**이며 사거리를 보지 않는다(`compute_steal_camp_targets`, `cast_range` 99) — 비어 있는 칸은 애초에 고를 수 없으므로 헛치기가 없고, 어느 칸에 값이 남아 있는지는 화면의 캠프 아웃라인이 이미 말해 준다. 예전에는 **점령** 카드였다(`capture_jungle:10` — 아군 정글과 인접한 적 정글 셀을 10턴 동안 자기 색으로 뒤집고 `temp_zone_overrides` 가 만료 시 되돌렸다). 그 배선과 `SimulationCore.process_temp_zone_expiries` / `set_zone_cell` 는 함께 **삭제됐다**. |
| 선수 스탯 (여섯 종) | **선수 한 명이 들고 있는 값은 여섯뿐이고 여섯 다 전투 계산의 입력이다.** `PlayerData` 가 표(`STAT_KEYS` / `STAT_LABELS` / `STAT_SHORT` / `STAT_NOTES`)를 소유하고 모든 화면이 그것을 읽는다 — 예전에는 화면마다 자기 배열을 들고 있었다. **하한 1, 상한 없다** — 일상 훈련으로 100 을 넘겨 계속 자란다(그래서 명중을 비율로 읽는다. 아래 항목). ① **전장 명중 `field_hit`** / ② **전장 회피 `field_eva`** → `PilotData.hit` / `evasion` → `SimulationCore.roll_hit`(전장 자동 교전 + 공격 카드). ③ **교전 명중 `engage_hit`** / ④ **교전 회피 `engage_eva`** → `PilotData.engage_hit` / `engage_eva` → `TurnEngageSim`. 전장과 **따로 사는 것**이 요점이다 — 같은 선수가 라인전에서 강한 것과 한타에서 강한 것은 다른 일이고, 그 둘을 가르는 것이 훈련판의 선택지가 된다. ⑤ **공격력 성장 계수 `atk_growth`** / ⑥ **체력 성장 계수 `hp_growth`** → `PilotData.atk_growth_mult` / `hp_growth_mult` → `BattleSim.refresh_growth_stats` 가 `GROWTH_ATK_PER_SCORE` / `GROWTH_HP_PER_SCORE` 에 곱한다. 배율의 기준점은 `PlayerData.GROWTH_STAT_BASE` = **80** 이고 그 값에서 ×1.0 = 지금 밸런스 그대로다 — 50 이 아닌 것은 실측이다(`players.csv` 40명 평균 78.2 / 네임드 85). 50 으로 두면 개시부터 전원이 ×1.56 이라 아무도 안 건드린 밸런스가 56% 밀린다. **성장 계수는 스탯을 직접 밀지 않는다** — 스탯을 밀면 성장 재계산 한 번에 지워지고, 훈련이 바꾸는 것은 개시 스탯이 아니라 경기가 흘러가는 기울기다. **예전 다섯 종(`laning` / `mechanics` / `gamesense` / `teamfight` / `mental`)은 삭제됐다** — 인게임에서 실제로 읽히는 것은 `mechanics`(→hit) 와 `gamesense`(→evasion) 둘뿐이었고 나머지 셋은 전력 합산에만 쓰였다. 전력 합산은 `PlayerData.stat_total()` / `stat_avg()` 한 쌍으로 모였다(예전에는 다섯 필드를 손으로 더한 식이 여덟 군데에 흩어져 있었다). |
| 명중 판정 (80~100% 리맵) | **전장과 교전이 같은 공식을 쓴다** — `PilotData.hit_chance(hit, eva)` = `HIT_MIN + (HIT_MAX − HIT_MIN) × hit/(hit+eva)`, 곧 `0.80 + 0.20 × 비율`. 대등하면 90%, 한쪽으로 완전히 기울어야 80% / 100% 에 닿는다(실측: 100 vs 50 → 93.3%, 200 vs 50 → 96.0%, 1 vs 300 → 80.1%). 다른 것은 **입력뿐**이다 — 전장은 `hit`/`evasion`, 교전은 `engage_hit`/`engage_eva`. **예전에는 전장이 비율을 그대로 확률로 썼고(대등 = 50%) 교전만 이 리맵을 했다**(`TurnEngageSim.ENGAGE_HIT_MIN` / `_MAX`, **삭제됨**) — 같은 스탯 차이가 두 무대에서 전혀 다른 크기로 읽혔고, 스탯 상한이 없어진 지금은 격차가 벌어지면 한 팀이 사실상 아무것도 못 맞히는 경기가 난다. **파급: 전장 라인전의 피해 처리량이 대략 1.8배가 됐다**(대등한 상대끼리 50% → 90%). `BATTLE_PILOT_DMG_MULT`(0.35)는 손대지 않았으므로 한 대는 여전히 2~9 지만, "라인전만으로는 사람이 죽지 않는다"는 예전 성질은 약해진다 — 성장치 곡선을 다시 재려면 그 상수가 첫 번째 노브다. **거리 계수 자리는 비워 뒀다** — `hit_chance` 의 세 번째 인자 `range_mult` 가 항상 1.0 이다. 전장은 지금 같은 칸 교전뿐이라 거리라는 개념이 없고, 사거리 규칙이 생기면 호출부가 그 인자에 계수를 실어 보내면 된다(공식 자체는 안 건드린다). **라인전 스탯과 스킬 배율은 이 공식에 들어가기 전 스탯에 먼저 곱해진다** — 확률을 직접 밀면 구간 밖으로 나가거나 상한에 막혀 배율이 조용히 사라진다. |
| 라인전 스탯 | **`hit` / `evasion` 전용** 배율(±10%)이며 `SimulationCore.roll_hit` **한 곳에서만** 곱해진다 — 공격자의 `hit` 과 방어자의 `evasion` 에 각자 자기 배율이 붙는다. `atk` / `max_hp` 는 성장이 담당하므로 여기서 건드리지 않는다. `roll_hit` 은 전장 자동 교전과 공격 카드가 공유하므로 둘 다 반영되고, **교전 무대는 반영되지 않는다**(공식은 같지만 입력이 `engage_hit`/`engage_eva` 이고 이 배율은 `roll_hit` 안에서만 곱해진다). 같은 파일럿에 두 번 걸면 **덮어쓴다**(합산 아님) — 3종 풀에서 2장 뽑는 구조상 합산을 허용하면 +20~30% 가 그냥 운으로 굴러 나온다. **공격적인 라인전**(+10%). 예전의 안전한 파밍(−10% + 적립 +10%)은 **소극적인 태세**로 바뀌었다 — 라인전 스탯을 건드리지 않고 **전장 회피에만** +20%(`PilotData.eva_card_mod`)를 건다. `roll_hit` 은 그 위에 카드 쪽 배율을 둘 더 곱한다: 공격자 명중 × (1 + `CardPhaseManager.hand_hit_add` — 손에 든 [자신감] 장당 +15%), 방어자 회피 × (1 + `eva_card_mod`). |
| 매복 고정 (`ambush_hold`) | [매복] 카드가 세우는 플래그. `resolve_movement` 가 그 파일럿을 **이동 후보에서 통째로 뺀다**(자유이동도 밀기 결과도 없다 — `recall_hold` 바로 뒤의 검사). `RecallSystem.process_phase_end_recalls` 도 위치 이탈 판정을 건너뛴다(레인 파일럿이 정글 칸에 있는 것이 매복의 요점이다). 그 팀의 다음 작전 단계 진입 정산, 사망(`mark_pilot_dead`), 본진 복귀(`return_to_hq`), 복귀 카드, 후퇴 카드가 푼다. 풀린 뒤에도 정글에 남은 레인 파일럿은 그 작전 단계 끝에 평소처럼 위치 이탈로 귀환된다. |
| 이동 해석 (단일 패스) | 자유이동과 교전 푸시는 **하나의 패스**(`SimulationCore.resolve_movement`)에서 **락스텝**으로 해석된다 — 한 라운드 안의 모든 파일럿이 같은 스냅샷을 보고 목적지를 정한 뒤 동시에 커밋하므로, 같은 스코프의 적끼리 자리를 맞바꾸거나 서로를 통과하는 일이 구조적으로 불가능하다. 한 라운드에서 중재되는 충돌은 둘이다. (1) **버티는 적 지나치기** — 전진은 적 HQ 쪽, 후퇴는 자기 HQ 쪽이라 방향이 같으므로 **승자는 밀려난 패자를 따라 들어간다**(= 라인이 한 턴에 한 칸 밀린다). 예전엔 두 목적지가 겹치면 전진 쪽을 취소해 "패자만 쫓겨나고 승자는 그 칸을 지킨다" 였는데, 일직선 레인에서는 목적지가 **항상** 겹쳐서 교전에 이겨도 승자가 영영 한 칸도 나아가지 못했다. 지금은 적이 밀려날 곳이 없어 그 칸에 **남을 때만** 전진을 취소한다(`_veto_advance_over_stuck_enemy`) — 서 있는 적을 스쳐 지나가지 않기 위해서다. 적 포탑 칸은 막지 않는다 — 패자가 자기 포탑 칸으로 밀려나면 승자도 거기까지 따라 들어가고, 그 칸에서 공성이 시작된다. (2) **정면 충돌**(서로의 칸을 노림)은 **푸시 > 자유이동, 동률이면 팀0** 우선순위로 한쪽이 그 칸을 차지하고 다른 쪽이 멈춰 **같은 칸에서 만나** 다음 턴에 교전한다. 데미지 적용은 이동보다 **앞**에 온다(이번 턴에 죽은 파일럿은 움직이지 않는다). |
| Combat | **Same-cell only** — no adjacent-cell engagement, no attack range. Lane pilots paired 1:1 by HP against enemy lane pilots; each rolls `PilotData.hit_chance(hit, evasion)`(= 비율을 80~100% 에 리맵, 대등하면 90%) for damage — 이 판정에 **라인전 스탯**이 곱해진다(위 항목). **명중 1회 피해 = `atk × BATTLE_PILOT_DMG_MULT`**(game_config, 0.35 — 반올림, 최소 1). 이 배율은 **파일럿이 받는 전장 피해 전용**이다: 파일럿→포탑 / 파일럿→HQ 는 `atk` 를 아예 안 읽고 `PILOT_STRUCTURE_DMG` 고정값을 쓰며(위 "Turret Combat" 항목), 공격 카드와 교전 무대도 각자 계산을 쓴다. 원본 `atk` 로는 한 대가 복귀 구간보다 컸다 — atk 28 상대 vs max_hp 75 스나이퍼는 1타가 최대 체력의 37% 라 20% 복귀선 위에서 곧장 0 으로 떨어졌고, 저HP 복귀가 발동할 구간 자체가 없었다. **Push is team-level**: tally unilateral wins per team across all pairs in the cell; the side with strictly more unilateral wins sweeps — every pilot of that side in the cell (including unpaired pilots in e.g. 2v1) advances, every opposing pilot retreats. Tie/0-0 → no push. Advance and retreat point the **same way** (enemy HQ vs own HQ), so the winners **follow the losers into the next cell** — 교전 칸 전체가 패자 HQ 쪽으로 한 칸 미끄러지고 다음 턴에 거기서 다시 붙는다. 이것이 라인 푸시다. 전진이 취소되는 경우는 **패자가 밀려날 곳이 없어 그 칸에 남을 때** 하나뿐이다 — 앞 칸이 적 포탑이어도 승자는 그 칸까지 따라 들어간다(포탑 공성은 그 다음 턴). `_move_pilot` aborts further multi-step movement only when a *same-scope* enemy enters the cell (jungler-vs-jungler or lane-vs-lane); cross-scope contacts never freeze movement. |
| 라인 결속 (바텀 듀오) | **같은 팀 · 같은 레인에 배정된 라이너끼리는 결속돼 있다**(지금은 우측 레인 스나이퍼 + 서포터뿐. 판정이 역할이 아니라 `lane` 이라 레인 배정이 바뀌면 따라간다. 정글러는 제외). **같은 칸에 함께 서 있을 때만** 작동하고, 하는 일은 교전 결과 이동(푸시 · 포탑 수비자 피격 넉백)을 묶음 단위로 맞추는 것 하나다 — **밀림이 이긴다**: 한 명이라도 후퇴 판정이면 파트너도 후퇴하고(포탑 칸에서 원딜만 맞아도 서포터까지 물러난다), 전진은 묶음 전원이 갈 수 있을 때만 한다. **카드 · 스킬 · 저HP 복귀 이동은 대상만 움직인다**(결속 코드가 그 경로를 지나지 않는다). 자유 이동도 묶지 않는다. 화면 표시는 없다(로그 `BOND` 만). `SimulationCore.lane_bond_partners` / `_apply_lane_bonds`(판정 직후, 턴 전투 + 전진 카드) / `_enforce_lane_bonds`(이동 라운드 안). 자세한 내용은 `combat/README.md` 의 "Lane bond". |
| Engagement scopes | Junglers and lane pilots run on **separate engagement brackets**. A jungler never engages an enemy lane pilot, never deals turret damage, and is never paired against attackers as a turret defender. Lane pilots ignore enemy junglers in the same cell. |
| Turret Combat (포탑 칸 점거) | **Only same-lane lane pilots interact with a turret** (e.g. a RIGHT-lane pilot cannot damage a CENTER turret). 전진하는 레인 파일럿은 같은 레인 적 포탑 칸에 **실제로 올라선다** — 그냥 걸어 올라가든, 교전에서 이겨 밀려나는 적을 따라 들어가든, 전진 카드로 들어가든 같다(예전의 "발만 들였다 빼는" 인접 공성 `resolve_turret_sieges` / `_bounce_off_enemy_turret` 은 삭제). **진입한 턴에는 피해가 없다.** 그 칸에 서서 맞는 **다음 턴**에 `_resolve_turret_combat` 이 돌아 **명중 판정 없이** `PILOT_STRUCTURE_DMG`(game_config, **2**)를 포탑에 넣는다. **`atk` 비례가 아니라 고정값이다** — 성장이 공격력을 ×3 까지 밀어 올리는 지금 `atk` 전량을 그대로 넣으면 후반 포탑이 한 턴에 녹아 경기 길이가 성장에 반비례해 무너진다. 구조물이 빨리 무너지는 이유는 공격력이 커져서가 아니라 **수비수가 저HP 복귀·사망으로 전장을 비웠기 때문**이어야 한다. 포탑 체력 `TURRET_HP` 는 **24** 라 무방비면 **12턴**, 수비가 붙으면 24턴에 철거된다(예전 16 에서 1.5배가 됐다 — 전령 제압의 8 피해가 포탑 절반이던 것을 1/3 로 낮추고 공성이 한 박자 더 걸리게 하는 값이다). **적이 그 칸에서 농성 중이어도 포탑 피해는 반드시 들어간다** — 수비자는 포탑을 가려 주지 못한다. 포탑 피해를 넣은 **다음**, 같은 레인 공격자와 수비자가 **서로 명중 판정을 굴려**(HP 오름차순 1:1 페어링, 양쪽 다 `_pilot_hit_damage`) 피해를 주고받는다. 예전엔 "공격은 전부 포탑으로 간다"며 **공격자가 수비자에게 0 피해**였고, 그래서 포탑에 눌러앉은 수비자는 공격자를 일방적으로 두들길 수 있었다. **포탑을 때렸다고 물러나지 않는다** — 넉백은 **포탑 칸 수비자의 공격이 명중한 공격자만** 직전 칸으로 민다(`_apply_turret_siege` 가 맞은 공격자 집합을 돌려준다). 수비자가 빗나갔거나, 짝이 없어 아무도 노리지 않았거나(2v1 의 남는 한 명), 수비자가 아예 없으면 공격자는 그 자리에 눌러앉아 **매 턴** 포탑을 갈아 낸다. 예전에는 수비자가 있기만 하면 명중 여부와 무관하게 공격자 전원이 물러났다(`_same_lane_defenders_at` 삭제). 예외는 **때릴 수 없는 포탑**(같은 레인 T1 이 살아 있는 T2)뿐 — 갈아 낼 게 없으니 무조건 물러난다(파일럿끼리의 판정은 그래도 굴린다). 결과적으로 포탑 피해는 무방비면 매 턴, 수비가 붙으면 수비자의 명중률(대등하면 90%)만큼 2턴에 1회(진입 → 타격 후 밀려남 → 재진입)에 가깝고 빗나간 턴마다 한 번 더 갈아 낸다. **HQ 도 같은 고정 피해**를 받는다(`HQ_MAX_HP` **40** → 1인 무방비 20턴 / 5인이면 4턴 — HQ 는 1.5배 대상이 아니다). 오프레인 파일럿은 포탑을 무시하고, 양 팀 오프레인끼리는 여전히 파일럿 교전을 한다. **Turrets do NOT attack pilots. Junglers do NOT attack/defend turrets.** T2 는 같은 레인 T1 이 살아 있는 동안 무적. 포탑 파괴 시 `Building` 노드도 해제해 스프라이트가 사라진다. |
| 전진 카드 (`advance:N`) | 카드 한 장이 **라인을 N 칸 밀어 올린다**. 미니틱 하나가 `SimulationCore._advance_tick` 이고, 전장 규칙을 그대로 쓰되 판정 하나만 강제한다 — **전진을 낸 쪽은 그 칸의 교전에서 무조건 이긴 것으로 친다**(피해 판정은 평소대로 굴리므로 맞을 건 맞는다. 밀리는 쪽만 고정). 그래서 **시전자와 같은 칸·같은 스코프의 아군이 함께 한 칸 전진하고, 같은 칸의 적은 함께 한 칸 밀려난다**. 예전엔 (1) 일방 명중 우세를 그대로 읽어 주사위가 나쁘면 시전자가 자기 HQ 쪽으로 물러났고(= 전진 카드가 후퇴 카드였다), (2) "카드는 한 명만 움직인다"며 진 적을 제자리에 두고 시전자만 옆을 스쳐 갔다. 다음 칸이 **같은 레인 적 포탑**이면 무리는 전장 규칙 그대로 **그 칸에 올라선다**(그 틱에는 포탑 피해 없음). 밀려날 곳이 없어 적이 칸에 남으면 무리도 전진하지 않는다. 시전 시점에 **이미 같은 레인 적 포탑 칸 위**라면 포탑 규칙이 이긴다 — 포탑에 무판정 피해를 넣고, **그 칸 수비자의 공격에 맞은 사람만** 한 칸 후퇴(**전진이 뒤로 가는 유일한 경우**), 나머지는 물러나지 않고 제자리에서 계속 갈아 낸다. |
| Recall / Respawn | **복귀 = 본진 귀환.** 두 가지 사유가 `RecallSystem.return_to_hq` 한 경로로 들어온다 — (1) HP ≤ `RECALL_HP_THRESHOLD`(20%), (2) 이동 카드가 파일럿을 **정글이나 다른 레인의 통로**에 떨어뜨린 위치 이탈. **복귀는 전장을 비우지 않는다** — 그 턴에 곧장 자기 HQ 에 **만피로** 서고 `alive` 는 계속 true 다. 파일럿이 전장에서 사라지는 사유는 **사망뿐**. 대신 복귀한 턴에는 움직이지 않고(`PilotData.recall_hold` → `resolve_movement` 가 이동 패스 1회를 걸러 내며 플래그를 소비), **다음 턴부터** 웨이포인트 0 부터 자기 레인을 다시 걸어 나간다. 즉 복귀 비용은 회복 대기가 아니라 **HQ 에서 전선까지 다시 걸어가는 시간**이고, 그 시간이 곧 **성장치 수입이 끊긴 시간**이다(위 "전선" 항목) — 사망도 마찬가지라 리스폰 턴 수(경기 후반일수록 길어진다)가 그대로 성장 손실로 환산된다. 그래서 사망에 점수 벌점을 따로 매기지 않는다. **자기 레인 위라면 아무리 깊어도 위치 이탈이 아니다** — 스플릿 푸시는 살려 둔 설계다. 복귀 카드(`recall_ally`)는 여기에 대기 없이 즉시 HQ + 만피. 전장을 비우는 것은 사망뿐이므로 `respawn_timer` 와 **`BattleSim.turns_until_return(p)`** 은 **사망 전용 시계**다 — "남은 턴 수"가 필요한 곳(카드 잠금 표시, 로그 `dead:N`)은 여전히 헬퍼를 거친다. **리스폰 턴 수는 경기 시간에 따라 늘어난다** — `BattleSim.respawn_turns_now()` = `RESPAWN_TURNS`(game_config, 5) + `turn_count / 10`. 사망은 **오직** `BattleSim.mark_pilot_dead(p)` 한 곳을 지난다(전장 교전 / 전진 / 공격 카드 / 교전 무대 공통). |
| Jungle (initial) | Both jungles start fully captured, **`(-3,-1)` 와 `(1,-1)` 두 칸만 중립으로 남는다**. 그 둘은 전령 / 용이 서는 자리이기도 하지만 **타일 규칙은 다른 정글 칸과 한 글자도 다르지 않다** — 캠프가 서고, 정글러가 밟아 점령하고, 순회 목표가 되고, 사이드 T1 파괴의 측면 중립 탈취 분기로 주인이 바뀐다. 한때는 **상시 중립**(오브젝트 전용)이라 셋 다 막혀 있었고 `is_objective_cell` / `_nearest_uncaptured_neutral` 이 그 판정이었는데, 두 칸이 정글로 돌아오며 전자는 삭제되고 후자는 되살아났다. **목표 선택의 1순위는 아직 아무도 안 잡은 중립 칸**(`_nearest_uncaptured_neutral`, `jungle_start_pref` 가 좌우 순서를 정한다)이고 그 다음이 차 있는 캠프다. **Lane pilots are forbidden from entering any jungle/neutral cell** — Pathfinding receives `_bs.neutral_zone_cells` as the forbidden set for non-junglers. **중립이 다 잡히고 나면 목표는 지금 먹을 수 있는 캠프**(`_best_ready_camp`)다 — 정글러의 수입이 전부 캠프에서 나오므로 캠프가 곧 목표이고, 먹고 나면 그 칸이 4턴 비어 다음 캠프가 자연히 새 목표가 된다. 그 반복이 곧 순회다(위 "정글 캠프" 항목). **그 캠프를 고르는 비용은 거리가 아니라 `거리 × JUNGLE_CAMP_STALE_PER_STEP(3) − 방치 턴 수`다.** 거리만 보면 정글러는 **자기 발밑 4칸에 갇힌다** — 한쪽 정글이 4칸이고 재생성이 4턴이라 매 턴 정확히 한 칸이 되살아나므로 최단 거리 그리디는 언제나 거리 1짜리 캠프를 찾아냈고, 반대쪽 정글은 개시부터 끝까지 캠프가 꽉 찬 채 남았다(실측 60턴: 밟은 칸 **6개**, 오른쪽 정글 세 칸은 한 번도 안 밟음). 화면에는 "먹을 게 남은 칸을 두고 빈 칸만 도는" 것으로 보인다. 차 있는 채 놀고 있는 캠프가 턴마다 조금씩 싸지면 방치된 쪽이 주기적으로 가장 싼 목표가 되어 좌우를 오가는 순회가 된다(같은 60턴: 밟은 칸 **11개**, 캠프 획득 53 → 45회 = 수입 85%. 그 15%가 순회의 이동 시간이고, 그 대가로 정글 전체가 돌아간다). 목표를 향해 한 걸음 옮기면 그 목표의 비용은 반드시 더 내려가므로(−4, 다른 캠프는 −1) 가는 도중에 목표가 뒤집혀 왕복하는 일이 없다. **발밑의 캠프가 차 있으면 무조건 그 칸이 목표다** — 이동이 정산보다 앞에 오므로 가만히 있기만 하면 이번 턴에 먹는다. 캠프가 하나도 안 차 있을 때만 예전의 **sticky** 로밍(`PilotData.jungle_roam_target`, 도달할 때까지 유지)으로 떨어진다 — 매 턴 "가장 먼 아군 칸"을 다시 고르면 한 걸음 옮기는 순간 방금 떠나온 쪽이 가장 멀어져 *미드 레인* 통로 두 칸을 왕복했다. |
| T1 → Jungle | T1 destroyed in lane L → priority branches off per-lane 취약지점 sets `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` (side lanes 1 cell, mid 2 flanking cells). (1) **Restoration**: if any of capturer's own same-lane vuln cells are loser-owned, restore them, nothing else flips. (2) **Side-neutral override (L/R only)**: if `(-3,-1)`/`(1,-1)` is loser-owned, capturer takes that neutral instead of loser's vuln. (3) **Default**: loser's same-lane vuln cell(s) flip to capturer. Mid has no neutral override. |
| 3-Lane System | Waypoint paths from HQ → side waypoints → enemy HQ. The old minion / lane-strength concept is **removed**. |
| 수비 개념 없음 | 레인 파일럿의 목표는 **언제나** `current_waypoint(p)` 하나다. 아군 포탑이 맞고 있다고 돌아오는 행동은 존재하지 않는다 — 파일럿은 자기 HQ 에서 출발해 레인 길을 따라가고, 그러다 상대 라이너와 마주치는 것이 설계다. (같은 레인 스나이퍼가 죽으면 서포터가 아군 최전방 포탑을 껴안던 `_supporter_should_fall_back` / `_own_forward_turret_cell` 은 삭제됐다.) |
| 레인 통로 (`lane_corridor`) | 레인별 실제 통과 셀 집합. 그 레인의 웨이포인트를 정글 금지로 BFS 연결해 **한 번만** 만들고 캐시한다(팀1 경로는 팀0 의 역순이라 셀 집합은 공유). 유일한 소비자는 `RecallSystem._is_out_of_position` — "이동 카드가 이 레인 파일럿을 **남의 레인**에 떨어뜨렸나". 판정은 반드시 **다른 레인에 속함**을 확인하지, 자기 레인에 없음만으로 판정하지 않는다: BFS 타이브레이크가 실제 걸어간 경로와 한 칸 어긋나도 멀쩡한 파일럿을 추방하면 안 되기 때문. `LANE_NAMES` 에는 GUERRILLA 칸도 있으니 순회는 `lane_corridor_count()` 로 한다. |
