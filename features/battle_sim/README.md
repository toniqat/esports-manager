# Feature: Battle Sim

## Purpose
Tactical battle simulator on a hex grid. Five pilot roles per team
(Tank, Fighter, Assassin, Support, Sniper) push down a 3-lane map flanked by
jungle. **BATTLE auto-progresses** in 1-minute (`AUTO_PLAY_INTERVAL`) ticks;
players intervene during the threshold-gated **작전 단계** (CARD_PHASE) to spend
작전 점수 on cards.

## Entry point
Normally entered from `scenes/MatchFlow.tscn` via `change_scene_to_file`.
Standalone launch of `BattleSim.tscn` also works — falls back to `ROLE_STATS`
defaults and a default jungle direction (LEFT).

## Match Context handoff
On `_ready()`, BattleSim reads `GameManager.match_ctx`:

| match_ctx field | Used by |
|---|---|
| `player_roster[i].assigned_mech` | `SimulationCore._stats_for()` → PilotData hp/atk |
| `player_roster[i].mechanics` | PilotData.hit (combat 명중률) |
| `player_roster[i].gamesense` | PilotData.evasion (combat 회피율) |
| `enemy_roster[i].assigned_mech` / stats | same, for team 1 |
| `jungle_start_dir` | PilotData.jungle_start_pref on the player-team assassin |
| `player_side` | `BattleSim.blue_team` via `seed_side_costs()` — 블루 진영의 전략 포인트 선점 + 선턴 |
| `active = false` | Triggers fallback to ROLE_STATS (no MatchFlow ran); 진영도 플레이어=블루로 떨어진다 |

---

## Module Architecture

BattleSim.gd is a **thin orchestrator** (`class_name BattleSim extends Node2D`). All logic lives in child modules. Each module has:
```gdscript
@onready var _bs: BattleSim = get_parent() as BattleSim
```
And accesses shared state via `_bs.pilots`, `_bs.turn_count`, etc.

### Child nodes (in scene order)
| Node | Type | Script | Purpose |
|---|---|---|---|
| SimulationCore | Node | `combat/SimulationCore.gd` | Turn loop, paired combat, movement, push, T1→jungle capture, win condition |
| RecallSystem   | Node | `combat/RecallSystem.gd`   | Instant HQ teleport at HP ≤ threshold; phase-end out-of-position recheck |
| Pathfinding    | Node | `combat/Pathfinding.gd`    | BFS + greedy fallback (hex distance) |
| BattleRenderer | Node2D | `rendering/BattleRenderer.gd` | HQ/turret HP bars + per-cell pilot rendering |
| CardPhaseManager | Node | `card_phase/CardPhaseManager.gd` | 작전 단계 turn flow, deck, fanned hand layout, phase-end gating |
| GambitPhaseManager | Node | `gambit/GambitPhaseManager.gd` | Auto role→lane mapping + launch (UI removed; pre-battle choices live in `features/match_flow/`) |
| EngagePhaseManager | Node | `engage/EngagePhaseManager.gd` | 전투 개시(engage) modal — **라운드 턴제 사이드뷰 벨트 교전** (`engage/TurnEngageSim.gd` 헤드리스 시뮬 + `engage/EngageArena.gd` 렌더러) triggered by `engage:N` / `duel` cards. Lazily added in `_ready()`. |
| HudBuilder     | Node | `ui/HudBuilder.gd`         | HUD construction; 전략 포인트 도넛 (`ui/CostDonut.gd`), **양 팀 파일럿 스트립** (`ui/PilotStrip.gd`, 상단 적 / 하단 아군), 우측 상단 **킬로그** (`ui/KillFeed.gd`), 적 스트립 양옆 **오브젝트 시계** (`ui/ObjectiveTimer.gd`) |
| ObjectiveSystem | Node | `objective/ObjectiveSystem.gd` | **오브젝트(전령 / 용)** — 좌우 중립 칸에서 정해진 턴마다 열리는 교전 사건. 시계 · 참여 결정 · 정산. 화면은 교전 모듈의 VS 화면과 무대를 빌려 쓴다. Lazily added in `_ready()` **after** config load. |
| PilotDetailPanel | Node | `ui/PilotDetailPanel.gd` | 파일럿 상세 모달 — 스트립의 얼굴을 누르면 열린다(작전 단계 한정). 머리글(이름 · 기체명 · 성장치)이 탭과 분리돼 늘 보이고, 탭이 바꾸는 것은 아래 상세 패널뿐이다. Lazily added in `_ready()`. |
| ObjectiveRewardPopup | Node | `ui/ObjectiveRewardPopup.gd` | 오브젝트 보상 미리보기 — 상단 패널의 시계를 누르면 그 오브젝트가 주는 카드를 실물로 띄운다. **전장을 붙잡지 않는다.** Lazily added in `_ready()`. |
| PilotSkillSystem | Node | `skill/PilotSkillSystem.gd` | **파일럿 스킬** — 선수마다 붙는 고유 능력(쿨타임 / 충전식 / 패시브). 상태 · 활성화 · 사건 훅 · 패시브 질의. Lazily added in `_ready()` **after** `build_starter_decks()` (짝을 로스터에서 찾고 백본 패시브가 덱을 만진다). `skill/README.md` 참조 |
| BattleLogger   | Node | `debug/BattleLogger.gd`    | Full action log (console + `user://battle_logs/`) and enemy cross-over detector. Lazily added in `_ready()` after pilots spawn; reachable as `_bs.blog`. |

Cross-module calls go through `_bs`:
```gdscript
_bs.sim_core.simulate_turn()
_bs.pathfinder.bfs_next_step(...)
_bs.renderer.queue_redraw()
```

---

## BattleSim.gd (thin orchestrator)

Responsibilities:
- Declares all DB-driven config vars and **state vars** (pilots, turrets, neutral_zone_cells, game_phase, HUD refs, card state, `gambit_lanes`)
- Holds `@onready` refs to all child modules
- Public **coordinate helpers**: `cell_center(pos)`, `pilot_label(p)`, `role_stats_str(role)`
- **Lifecycle**: `_ready()`, `_process(delta)`
  - `_ready` calls `_gambit.auto_assign_lanes()` then `_gambit.launch_battle()` —
    no overlay, scene transitions straight into BATTLE.
  - `_process` auto-ticks `card_phase.do_battle_turn()` every `AUTO_PLAY_INTERVAL`
    seconds while `game_phase == BATTLE`. CARD_PHASE pauses the tick, and so does
    the 상대 차례 — that one runs *inside* BATTLE, so the guard also reads
    `_ai_turn_active()` (`card_phase.is_ai_turn_active()`). The same flag freezes
    `get_elapsed_ingame_seconds()`.
- **Button callbacks**: `_on_restart_pressed()` (the only manual entry point left).

---

## Data Classes (resources/)

| File | class_name | Description |
|---|---|---|
| `resources/PilotData.gd` | PilotData | role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx, **move_range**, **hit**, **evasion**, **jungle_start_pref**, **respawn_timer** (death-only off-field clock — see `BattleSim.turns_until_return`), **recall_hold** (본진 복귀한 턴의 이동 1회 스킵), **anim_move_path** (이번에 밟은 칸의 경로 — 렌더러가 읽고 비운다), **kills / deaths** (이번 매치 누적 — `mark_pilot_dead` 한 곳에서만 오르고, 경쟁 심리 스킬이 상대 라이너와 견주는 데 쓴다) |
| `resources/TurretData.gd` | TurretData | team, grid_pos, hp, tier, lane, alive |
| `resources/PlayerData.gd` | PlayerData | id, name, role, team_id, 5 stats (laning / mechanics / gamesense / teamfight / mental), `assigned_mech`, **`skill_id`** (pilot_skills.id, -1 = 없음), **`is_mob`** (실루엣 초상화 · 스킬 없음 · 드래프트 제외) |
| `resources/MechData.gd` | MechData | id, name, hp, atk, **presence** (4=melee/2=ranged; engage 무대의 타겟 어그로 가중치로만 사용). **`speed` 는 삭제됐다** — 교전이 라운드 턴제가 되면서 행동 빈도 개념이 사라졌다 |

---

## Enums (resources/GameEnums.gd)

| Enum | Values |
|---|---|
| `GameEnums.BattlePhase` | GAMBIT, CARD_PHASE, BATTLE, **ENGAGE** |
| `GameEnums.Role`        | TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER |
| `GameEnums.LanePosition`| LEFT=0, CENTER=1, RIGHT=2, GUERRILLA=3 |
| `GameEnums.Lane`        | NONE=-1, LEFT=0, CENTER=1, RIGHT=2 (waypoint/building lanes) |
| `GameEnums.JungleStartDir` | LEFT, RIGHT (assassin start preference) |

---

## Active Systems

### Combat
- Combat happens **only between pilots in the same cell** — there is no
  adjacent-cell engagement and no concept of attack range.
- Same-cell pilots are paired 1:1 (lowest HP first) and roll
  `hit / (hit + evasion)` independently each minute.
- **Junglers and lane pilots run on separate engagement scopes**: a jungler
  never fights a lane enemy, never deals damage to enemy turrets, and is
  never paired against attackers as a turret defender. Junglers only fight
  other junglers.
- One-sided hit → winner advances 1 cell, loser retreats 1 cell.
- Both hit / both miss → no movement.
- Damage accrues regardless of push.
- **Free movement and combat pushes resolve in one simultaneous pass**
  (`SimulationCore.resolve_movement`), so two same-scope enemies can never
  trade cells or move through each other. A pilot mid-move stops as soon as it
  shares a cell with a same-scope enemy; a head-on exchange is arbitrated so
  one side takes the cell and the two meet there. Cross-scope contacts
  (jungler vs lane pilot) are ignored, so a jungler crossing a lane never
  freezes on — or is blocked by — a lane enemy.
- **Pilots are not attacked by turrets.**
- **전진 = 라인 푸쉬, 그리고 포탑 칸에 실제로 올라선다.** A lane pilot whose next
  lane step is a same-lane enemy turret **occupies that cell** — free walk-ups,
  engagement winners following the losers in, and the 전진 card alike. There is
  no adjacent "step in and bounce out" siege any more; entering costs a turn and
  deals no damage.
- **A pilot standing on an enemy turret cell attacks it that turn, with no hit
  roll** — full `atk` straight into the turret (`_resolve_turret_combat`). Then:
  - a same-lane **defender on that cell** and the attacker **trade hit rolls**
    (paired by HP, halved `_pilot_hit_damage` both ways), and the attacker is
    pushed back to the tile it came from — **hit or miss, the knockback
    happens**;
  - **no defender → no knockback.** The attacker stays on the turret and grinds
    it every turn. An undefended turret simply falls.
  - The one extra bounce: an **unattackable** turret (T2 while its own-lane T1
    stands) never holds an attacker — nothing to grind, so it retreats. Only
    card displacement can put a pilot there.
- **농성 중인 수비자도 맞는다** — the turret takes its damage first and
  unconditionally, and *on top of that* the attacker rolls on the defender
  standing on it. Camping a turret used to be a free beating of the attacker
  (attackers dealt zero to defenders); now it is a mutual exchange. A defender is
  `engaged` only while attackers stand on its turret.
- Turret damage cadence follows from the above: **every turn** on an undefended
  turret, **every other turn** on a defended one (enter → hit + get pushed out →
  re-enter).
- Off-lane lane pilots in a turret cell ignore the turret entirely; if both
  teams have off-lane lane pilots there they may still fight each other as
  pilot-vs-pilot. Junglers are always spectators at turret cells. T2 is
  invulnerable while its own-lane T1 stands.
- When a turret is destroyed, the matching `Building` node in
  `BattleField/BuildingLayer` is unregistered and `queue_free`'d so the
  sprite disappears from the field.

### Recall / Respawn
- **복귀 = 본진 귀환.** Two triggers, one path (`RecallSystem.return_to_hq`):
  HP ≤ `RECALL_HP_THRESHOLD`, **or** a card effect that dropped the pilot on a
  jungle cell / on **another lane's corridor**.
- **복귀는 전장을 비우지 않는다.** The pilot lands in its own HQ **at full HP**
  on the spot, `alive` untouched — a pilot only ever leaves the field by dying.
  The cost is the walk back: `return_to_hq` sets `PilotData.recall_hold`, and
  the next `resolve_movement` spends it to hold the pilot still for exactly one
  pass, so it starts down its lane from waypoint 0 **the following turn**.
- The old model — leave the field, heal `RECALL_HEAL_RATIO` of `max_hp` per
  turn, come back the turn after hitting full — is gone, and so is that
  game_config key.
- A deep jump along the pilot's **own** lane is legal, however far into enemy
  territory it lands. That is a split push, not a displacement.
- The 복귀 (`recall_ally`) card is the same teleport minus the hold: instant
  full-HP HQ landing, free to walk out the same turn.
- **Only the dead are off the field** (`alive = false`), so `respawn_timer` and
  **`BattleSim.turns_until_return(p)`** are death-only clocks. Anything needing
  "turns left" still calls the helper rather than reading the timer.
- **Respawn length scales with match time**: `BattleSim.respawn_turns_now()` =
  `RESPAWN_TURNS` (game_config, default **5**) + `turn_count / 10`. An early
  death costs 5 turns, a late one grows with the clock. The DB value used to be
  a flat 16, which meant one death in the opening minutes erased the whole
  laning phase. **`BattleSim.mark_pilot_dead(p)` is the only place a pilot
  dies** — battlefield combat, 전진, 공격 카드 and the engage arena all funnel
  through it, so the scaling and the 전사 연출 can never be wired into one path
  and forgotten in another. It is also where **계획 살인** pays out: the
  reserved `kill_bounty_p/ai` goes to the *opposite* team of the pilot who
  fell (`_award_kill_bounty`). No killer argument was added — the battlefield
  has no third faction, so "the other team did it" is exact.
- During CARD_PHASE the recall check is paused; it runs again at end of phase
  via `process_phase_end_recalls`.

### Lanes / movement
- Pilots follow waypoint lane paths (Left / Center / Right) loaded from `BattleField/WaypointLayer`.
- The old "minion line" / "lane strength" concept is gone. Lane pilots simply
  step toward `current_waypoint(p)` each minute.
- **Lane pilots are forbidden from entering jungle/neutral cells AND alive
  enemy off-lane turret cells.** Pathfinding receives the union of the
  jungle-cell set and every alive enemy turret in a lane other than the
  pilot's own. Same-lane enemy turret cells remain reachable — BFS has to be
  willing to name one as the next step, since that is exactly what the siege
  check reads. This prevents e.g. right-lane pilots from being routed through
  the still-alive center T2 cell after their own-lane turrets fall.
- **There is no defensive behaviour.** A lane pilot's goal is always
  `current_waypoint(p)`; nobody turns around because an own turret is under
  attack. Pilots leave their HQ, follow their lane, and run into the enemy
  laner — that collision is the design. (The old SUPPORT fall-back that hugged
  the forward own turret while its same-lane SNIPER was down is removed.)
- Junglers move freely (no forbidden cells) — they can transit through lane
  cells when crossing between own-captured jungle clusters, but they never
  engage in lane combat or attack turrets along the way.
- TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT→RIGHT, SNIPER→RIGHT.

### Jungle
- Map starts with both jungles fully captured. `(-3,-1)` and `(1,-1)` are
  **permanently neutral** — they are the 오브젝트 자리(전령 / 용), not camps.
  See 오브젝트 below.
- Junglers do not push lanes. They roam own-captured cells harvesting camps.
- Jungler-vs-jungler combat in a contested cell uses the same hit/evasion roll.
  A loser is pushed to the nearest own-captured jungle cell.
- T1 destruction triggers per-lane "취약지점" (vuln cell) flips. The vuln
  cells per team/lane live in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` in
  `combat/SimulationCore.gd`: side lanes have 1 vuln cell, mid has 2 (the
  flanking cells). When a team's same-lane T1 falls, two branches in priority:
  (1) **Restoration** — if any of the capturer's own same-lane vuln cells are
  owned by the loser, those flip back to the capturer and nothing else moves.
  (2) **Default** — the loser's same-lane vuln cell(s) flip to the capturer.
  **The old side-neutral override is gone**: `(-3,-1)`/`(1,-1)` can never be
  owned by anyone now, so that branch could never fire.

### 오브젝트 (전령 / 용)
좌우 중립 칸에서 **정해진 턴마다 열리는 교전 사건**. 전체 규칙 · 노브 · 보상
카드는 `objective/README.md`. 요약:

- **좌측 = 전령(12턴 첫 등장, 참가 3인: LEFT/CENTER/JUNGLE)**,
  **우측 = 용(15턴, 참가 4인: RIGHT×2/CENTER/JUNGLE)**. 결판 후 15턴,
  양 팀 미참여로 무산되면 10턴 뒤 재시도. 남은 턴 수는 타일 위에 상시 표시.
- **차례와 상관없이 발생한다** — `CardPhaseManager.do_battle_turn()` 이
  `simulate_turn()` 직후, 카드 경제보다 **앞**에서 `await` 한다.
- **회피할 수 있다.** 플레이어는 참여 / 미참여 두 버튼(VS 화면 재사용), AI 는
  양 팀 참가자의 `(hp+shield)×atk` 합으로 승률을 내 0.45 미만이면 물러난다.
  한쪽만 참여하면 전투 없이 그쪽이 가져가고, 양쪽이면 4라운드 교전
  (`EngagePhaseManager.start_objective_engage`) 뒤 **생존 인원 → 잔여 HP 비율
  합**으로 승자를 가린다. 사망한 파일럿은 참여 불가라 그만큼 불리하다.
- **보상** — 전령: [전령 제압](0코, 보존+소멸) 1장을 손패로. 최외곽 적 포탑에
  피해 8. 용: [용 보상](0코, 소멸) 5장을 덱에 섞어 넣는다. 드로우 1 + 지정한
  아군의 성장 적립 배율 **영구** +10%(`PilotData.growth_rate_bonus`, 누적).
  두 카드 모두 `pool = 0` 이고 **시전자가 없다**(`owner_pilot == null`).
- **오브젝트는 그 좌표를 무대로 빌려 쓸 뿐, 두 칸은 평범한 정글 칸이다** —
  캠프가 서고, 정글러가 밟아 점령하고, 사이드 T1 파괴로 주인이 바뀐다. 한때는
  상시 중립이라 캠프 칸이 14 → 12 로 줄었고 그만큼 `SCORE_JUNGLE_CAMP` 이
  0.98 → 1.15 로 올라 있었는데, 두 칸이 돌아오면서 **0.98 로 되돌렸다**.
- 남은 턴 수는 **상단 패널**의 `ui/ObjectiveTimer.gd` 두 칸에 상시 표시된다
  (적 스트립 양옆, 좌 전령 / 우 용). 전장 타일 위에 찍던 절
  (`BattleRenderer._draw_objectives`)은 삭제됐다.

### Card Phase (작전 단계)
- Triggered when `player_cost >= PHASE_THRESHOLD`.
- **개시 상태는 진영이 정한다.** `BattleSim.blue_team` (match_ctx.player_side
  에서 유도; MatchFlow 는 지금 플레이어를 항상 BLUE 로 고정) 쪽이
  `BLUE_COST_HEAD_START`(1) 만큼 전략 포인트를 선점한 채 시작하므로 문턱에 먼저
  닿는다 — 밴픽에서 후밴/후픽을 하는 대가다. **개시 손패는 없다** — 양 팀 다
  0장으로 시작하고, 손패는 `ECONOMY_START_TURN`(10)부터 도는 자동 드로우로만
  찬다. 실측 기준 첫 작전 단계는 **22턴 · 손패 7장**이고 상한
  `MAX_HAND_SIZE` 는 **10**이다.
- Ending the phase goes through the player's 전략 포인트 도넛: tap it once to
  flip it into a circular 턴 넘기기 button, tap again to end. **카드를 한 장도
  내지 않아도 넘길 수 있다** — 면이 회색으로 잠기는 것은 배너 / 모달 / 돌진
  연출처럼 지금 닫으면 무언가가 끊기는 상태뿐이다.
  Tapping anywhere else flips it back to the point readout.
- Phase end re-runs recalls (HP threshold + out-of-position card displacement)
  and drops straight back to BATTLE. 그때 **문턱을 넘은 전략 점수는 소멸하고**
  (`player_cost` = `PHASE_THRESHOLD`), 넘긴 쪽은 손패가 바뀌거나 상대가 한 번
  차례를 갖기 전까지 다시 차례를 받지 못한다(패스 잠금). 상대가 이미 문턱 위
  라면 다음 틱을 기다리지 않고 **그 자리에서 상대 차례로 넘어간다**. 짝이 되는
  규칙이 하나 더 있다 — **문턱 위에서는 `COST_RECOVERY` 가 들어오지 않는다**
  (양 팀 동일). 셋이 합쳐 전략 점수의 실질 상한이 문턱이 된다.
- **The AI's turn is its own**, no longer stapled to the player's phase end:
  it fires from the BATTLE tick when `ai_cost >= PHASE_THRESHOLD` *and* the AI
  holds a card it can pay for, and only then does the "상대 차례" banner show.
  It runs inside BATTLE with the auto-tick held, then runs the same recall
  sweep. When **both** sides are over the threshold on the same tick,
  `CardPhaseManager._next_turn_side()` arbitrates: 블루 먼저, 그 다음부터는
  직전에 잡지 않은 쪽이 잡는 **교대**. 교대가 굶주림 방지를 맡으므로 예전의
  "AI 를 무조건 먼저 검사한다" 규칙은 사라졌다.
  See [`card_phase/README.md`](card_phase/README.md).

### Engage (전투 개시) — 사이드뷰 벨트 교전 (라운드 턴제)
Card-driven sub-phase: `engage:N` opens a **turn-based side-view belt stage**
(관전 전용 — no player input). On close it returns to the phase that opened it —
CARD_PHASE for a player card, BATTLE for an AI card played during 상대 차례 —
see [`engage/README.md`](engage/README.md) for details. Key contract:
- Participants = pilots in radius-1 hex from caster (caster cell + 6 neighbors).
  `exclude_lane` drops lane pilots still on their lane row; junglers and
  displaced-into-jungle lane pilots stay in. Still supported end-to-end, but
  the only card that used it (교전, id 4) has been removed from the pool.
- **`engage:N` 의 N 은 라운드 수다** (engage:3 = 3라운드). 예전의
  "N × 3초" 환산은 삭제됐다. `duel` 은 첫 처치까지 돌고 `DUEL_MAX_ROUNDS`(10)
  상한만 둔다.
- **한 라운드 = 참가자 전원이 정확히 한 번씩 행동.** 무대에는 언제나 **한 명만**
  나와 있고(`current_actor`), 그 한 차례(접근 → 공격 → 정착)가 끝나면 다음
  순서로 넘어간다. 순서 끝에 닿으면 라운드가 오르고 **다시 시전자부터**.
- **행동 순서는 개시 시 한 번 정해지고 매 라운드 반복된다** — 시전자 팀부터
  한 명씩 **팀 교대**, 팀 안에서는 **역할 고정**(암살자 → 격투가 → 탱커 →
  스나이퍼 → 서포터), 단 **시전자는 자기 팀 맨 앞으로 당겨진다**. 포탑은 파일럿
  전원이 돈 뒤 시전자 팀 포탑부터 한 번씩. 죽은 행동자는 건너뛴다.
- **메크 `speed` 스탯은 삭제됐다** — 라운드마다 전원이 한 번씩 행동하므로 행동
  빈도를 가르는 스탯이 없다. `game_config.TURRET_SPEED` 도 함께 사라졌다.
- **전장 셀 위치는 배치에 반영되지 않는다.** 무대는 팀0 왼쪽 / 팀1 오른쪽으로
  마주 선 평면 벨트이고, 자리는 역할이 정한다 — 근접은 앞줄, 원거리는 뒷줄.
- 근접은 밀착(88px)까지, 원거리는 **최대 사거리의 90%**(270px)까지 파고든 다음
  때린다. 사거리 판정에는 `STRIKE_DIST_EPSILON` 여유가 붙는다 — 없으면 사거리에
  딱 맞춰 선 유닛이 부동소수 오차로 판정을 통과하지 못해 공격이 아예 성립하지
  않는다. **원위치 복귀는 없다** — 공격을 끝낸 자리가 새 앵커다. 명중하면 대상이
  넉백되고 **밀려난 자리도 새 앵커가 된다**(피해에는 얹히지 않고 위치와 재접근
  거리만 바꾼다).
- **교전 중 이탈은 없다** — 아무도 무대를 뜰 수 없다. 종료는 라운드 소진 또는
  한 쪽 전멸뿐. 빈사(HP<30%)여도 후퇴하지 않는다.
- **종료 → 대시보드 사이에 `EngagePhaseManager.END_HOLD_SEC`(2.0초) 유예**가
  있다. 마지막 처치가 결과창에 먹히지 않도록 전투만 멈춘 무대를 2초 더
  보여 주고(잔여 연출은 `TurnEngageSim.step_afterglow`), 상단에 종료
  사유 배너(`적군 전멸` / `N라운드 완료` …)를 띄운다. 유예 동안 `round_index` 는
  멈추므로 대시보드의 라운드 수는 실제로 싸운 라운드 수 그대로다.
- **암살자는 적 뒷줄(원거리)을 우선 타겟으로 삼는다** (`DIVE_FOCUS`). 이
  분기가 없으면 앞줄이 더 가깝고 존재감도 두 배라 원거리 메크가 교전 내내
  한 대도 맞지 않는다 — 실측으로 확인된 구멍이다.
- **포탑은 사거리 존이 아니라 참가자다**: **적이 걸어온 교전에서** 참가 파일럿이
  자기 팀 포탑 칸 위에 서 있으면 그 포탑이 가담해 **라운드마다 한 번 적 파일럿을
  공격한다** (사거리 제한 없음, 명중 판정은 굴린다). 무대에서 포탑 HP 는 깎이지
  않는다. **가담하지 않는 경우가 둘** — **시전자 팀의 포탑**(교전을 연 쪽이 곧
  강제한 쪽이다. 포탑 칸에 눌러앉아 카드로 교전을 여는 쪽이 포탑까지 끼면 그
  칸이 일방적인 안전지대가 된다)과 **오브젝트 교전**(시전자가 없어 "누가
  걸었는가"가 없고 무대도 중립 칸에서 열린다) — `engage/README.md` 의 포탑 절.
- Damage (atk 1회분 + shield-first) matches the battlefield, but **명중률은
  별개**: 교전은 전장 확률 `base` 를 **80~100% 구간**으로 리맵한다
  (`ENGAGE_HIT_MIN` 0.80 / `ENGAGE_HIT_MAX` 1.00 → 스탯이 대등하면 90%).
  KO routes through `BattleSim.mark_pilot_dead(victim, killer)`, so an arena kill
  gets the same scaled respawn timer (`respawn_turns_now()`) and the same
  성장치 정산 a battlefield kill does. `grid_pos` is never modified by an engage.
- 화면은 가로로 납작한 **시네마 밴드** 하나(1032×500)와 그 **아래 참가자
  초상화 + 체력 바 스트립**으로 구성된다. 상단 헤더는 **라운드 카운터
  (`라운드 2 / 3`) + 라운드 칸 + "누구의 차례"** 두 줄이다(실시간 시절의 남은
  시간 바는 삭제). Dashboard shows per-pilot dealt / taken / kills before resuming.
- 실측(헤드리스 5v5 ×8, engage:3): **13.3초 · 처치 1.0건**. ATB 시절(9초에
  처치 2.75건)보다 훨씬 온건하다 — 라운드마다 한 명이 한 번씩만 때리므로
  3라운드 = 최대 30타다.

### 성장치 (파일럿 점수) — 성장 통화
파일럿마다 **개시 1.00k** 에서 시작해 경기 내내 누적되는 **성장 통화**. MOBA 의
골드에 해당한다. 파일럿 스트립의 체력 바 아래에 숫자로 찍히고, 상단 중앙의 팀
점수는 그 팀 다섯 명의 **합산**이다(개시 `5.00k - 5.00k`). 상한이 없으므로
게이지가 아니라 숫자다.

**`PilotData.growth` 는 이 값에서 파생된다** — 예전에는 둘이 완전히 무관해서
(성장은 시간 경과, 성장치는 표시용 기록) 킬을 따도 포탑을 밀어도 스탯이 1도
변하지 않았다. 환산과 그 이유는 `combat/README.md` 의 "성장 / 라인전 스탯".

| 적립처 | 값 | 누가 |
|---|---|---|
| 전선 체류 (턴당) | `SCORE_FRONTLINE_PER_TURN` **0.50k** | 레인 파일럿 |
| 정글 캠프 1개 | `SCORE_JUNGLE_CAMP` **0.98k** (6턴 리스폰) | 정글러 |
| 처치 — 라스트힛 | `SCORE_KILL_BASE` **1.5k** + 앞선 격차 × **20%** | 전원 |
| 처치 — 어시스트 | 현상금 × **50%** × (내 피해 / 총 피해) | 전원 |
| 포탑 피해 | `SCORE_TURRET_FULL` **1.0k** ÷ `TURRET_HP` = **0.0625k / 1피해** | 레인 파일럿 |

**포탑의 몫은 철거가 아니라 노동에 붙는다.** 예전에는 철거하는 순간 마지막 한
대를 넣은 파일럿이 1.0k 를 통째로 받았는데(`SCORE_TURRET_KILL`), 그러면 여덟 턴
동안 밀어붙인 파일럿과 마지막 2 를 넣은 파일럿의 몫이 같았고 반쯤 갈아 놓고
죽은 사람은 한 푼도 못 받았다. 지금은 **깎아 낸 체력 1점당**으로 쪼개져 있어
(`BattleSim.score_turret_damage`) 실제로 민 만큼 나눠 갖는다 — 한 기를 통째로
갈아 내면 총액은 예전과 정확히 같은 1.0k 다(체력 16 · 고정 피해 2 → 한 대에
0.13k, 여덟 대에 1.0k). 오버킬은 잘라 낸다: 체력 2 짜리 포탑에 셋이 6 을 몰아
넣어도 나가는 것은 2 점어치다. 적립 지점은 둘 — 턴 전투의
`SimulationCore._credit_turret_damage` 와 카드 피해의 `apply_card_turret_damage`.
`score_turret_kill` 은 이제 킬로그 한 줄과 사건 훅만 담당한다.

**빠진 것들이 요점이다.** HQ **피해**는 여전히 점수를 주지 않는다(HQ 가 깎이는
것은 이미 승리에 가까워지는 것이다). 파일럿 피해도 그 자리에서는 점수가 아니라
장부에 적힐 뿐이다(`SCORE_PER_PILOT_DMG` / `_HQ_DMG` 삭제). **사망 벌점도
없다**(`SCORE_DEATH` 삭제) —
벌점은 죽어 있는 동안 전선 수입과 캠프가 통째로 멈추는 것이고, 그게 리스폰 턴
수에 비례하는 진짜 비용이다. 같은 손해를 두 번 매길 이유가 없다.

**어시스트 = 따라잡기 장치.** 현상금이 "피해자가 처치자 팀 평균보다 앞선 만큼"
에 비례하므로, 10k 앞선 에이스를 잡으면 3.5k / 20k 앞서면 5.5k 가 나온다. 뒤처진
팀도 한 번의 좋은 교전으로 따라붙을 수 있고, 앞선 쪽이 손해 보지는 않는다.

상수는 전부 `BattleSim` 의 `SCORE_*` 절에 모여 있고, 모든 변동은
`BattleSim.add_score` 한 곳을 지난다 — 하한(`SCORE_MIN` 0.10k), 적립 배율
(`growth_rate_mult`), 스탯 재계산을 한 자리에서만 처리하기 위해서다.

**피해 귀속의 배선**: 피해는 곧장 점수가 되지 않는다. `BattleSim.record_pilot_damage`
가 **피해자의 장부**(`PilotData.damage_credit`, `공격자 → [(턴, 그 턴의 피해)]`)에
적어 두고, 그 대상이 실제로 쓰러질 때 `_payout_kill_bounty` 가 라스트힛과
어시스트에게 나눠 준 뒤 장부를 비운다. 전장 자동 교전 · 공격 카드 · 교전 무대가
전부 그 한 지점을 지나므로 표가 하나다.

**처치 관여는 `SCORE_ASSIST_WINDOW_TURNS`(15턴) 짜리 창이다.** 기록마다 턴
도장이 함께 찍히고(같은 턴의 피해는 한 항목으로 합쳐진다), 그보다 오래된 항목은
어시스트 배분에서도 **분모에서도** 빠진다 — 20턴 전에 한 대 긁어 놓은 것이 지금
난 처치에 지분을 갖는 것은 관여가 아니고, 만료분이 분모에 남아 있으면 정작 지금
잡은 사람들의 몫이 조용히 깎인다. 판정은 `BattleSim.live_damage_credit(victim)`
**한 함수**뿐이고 읽는 김에 만료된 항목을 실제로 지운다. 세 소비자(현상금 배분 ·
킬로그 명단 · `PilotSkillSystem.on_kill` 의 처치 관여 훅)가 모두 그 함수를 읽으므로
화면에 뜬 얼굴과 점수를 받은 얼굴이 갈릴 수 없다 — `damage_credit` 을 직접 훑는
코드가 있으면 그 순간 규칙이 둘이 된다.

**라스트힛이 누구인가**는 별개 문제다: 전장 피해는 판정 단계(`_resolve_*` 가
`damage_map` 에 양만 쌓는다)와 적용 단계(그걸 소진하며 HP 를 깎는다)로 갈라져
있고, 적용 단계에는 **누가 때렸는지가 남아 있지 않다**. 그래서 `SimulationCore`
가 `_credit_pilot_damage` / `_credit_turret_damage` 에서 "마지막으로 이 대상을
때린 자"를 `_last_hitter` / `_last_turret_hitter` 에 적어 두고, 적용 단계가
그것을 `mark_pilot_dead(victim, killer)` / `score_turret_kill(killer, td)` 에 넘긴다. 두
dict 는 **매 턴과 매 전진 카드 시작 시 비운다** — 턴을 넘겨 살아남으면 엉뚱한
사람에게 처치가 붙는다. 교전 무대와 공격 카드는 공격자를 손에 들고 있으므로 이
우회가 필요 없다.

**킬로그도 이 표를 그대로 읽는다** — `mark_pilot_dead` 안에서 정산
(`_payout_kill_bounty`)보다 **먼저** `_push_kill_feed` 가 돌아 막타 + 어시스트
명단을 `ui/KillFeed.gd` 에 넘긴다(정산이 `damage_credit` 을 비우기 때문). 그래서
화면 우측 상단에 뜬 얼굴과 성장치를 받은 얼굴이 어긋날 수 없다. 포탑 철거는
`score_turret_kill` 이, 오브젝트 획득은 `ObjectiveSystem._push_feed` 가 같은
피드에 넘긴다 — 자세한 내용은 `ui/README.md` 의 "킬로그" 절.

### 성장치 팝업 (전장 초상화 위)
성장치가 **한 번에 크게** 오르는 순간에만 그 파일럿 얼굴 위로 금색 `+1.50k` 가
떠오른다(`BattleRenderer.spawn_score_popup`, 1.10초 · 72px). 숫자가 스트립 칸에서
조용히 바뀌기만 하면 "방금 그 한 방이 무슨 값이었나"가 화면에 남지 않는다.

| 뜨는 자리 | 계기 |
|---|---|
| 포탑 피해 | `score_turret_damage` — 한 대마다 (지금 설정 0.13k) |
| 처치 현상금 | 막타와 어시스트 각각 (`_payout_kill_bounty`) |
| 교전 총액 | 무대가 닫힌 뒤 참가자마다 **한 장으로 합쳐** |

전선 체류(턴당 0.50k)와 정글 캠프는 **뺐다** — 매 턴 열 명의 얼굴 위에서 숫자가
튀면 그게 곧 배경이 되어 정작 큰 한 건이 묻힌다.

배선은 한 겹이다: 조용히 적립만 하는 `add_score` 와, 거기에 팝업을 붙인
`award_score` 가 갈라져 있고 **어느 적립처가 화면에 뜨는지가 호출부에서 읽힌다**.
`add_score` 는 이제 하한과 적립 배율이 먹은 **실제 증가분**을 돌려주므로 팝업에는
요청한 값이 아니라 들어간 값이 뜬다.

두 가지는 띄우지 않는다. **죽어 있는 파일럿** — 시신은 1.45초 뒤 전장을 뜨고
그 뒤에 뜬 숫자는 아무 얼굴 위에도 서 있지 않다(어시스트는 자기가 죽은 뒤에도
들어오므로 실제로 걸리는 경로다). 그리고 **교전이 도는 동안** — 아레나가 화면을
덮고 있어 아무도 못 보고, 팝업 좌표는 띄운 순간의 마커 자리에 고정되므로 무대가
치워질 때쯤엔 엉뚱한 곳에 떠 있다. 그 사이의 적립은 `BattleSim._score_popup_hold`
에 쌓였다가 `EngagePhaseManager._on_dashboard_confirmed` 가 부르는
`flush_score_popups()` 에서 **파일럿당 한 장**으로 풀린다(킬로그의 `_pending` 과
같은 자리, 같은 이유).

### Action logging (`debug/BattleLogger.gd`)
Every turn writes a full transcript to the console **and** to
`user://battle_logs/battle_<timestamp>.log`: before/after position snapshots,
per-cell engagement brackets, the engaged / advance / retreat sets, every
`grid_pos` mutation tagged with the sim pass that caused it, damage, deaths,
turret HP, HQ chip, jungle captures and card plays. `end_turn()` also diffs the
snapshots and flags `!!SWAP` / `!!CROSS` when two same-lane enemies trade
places without engaging. Defaults to on — flip `blog.enabled` in
`BattleSim._ready()` to silence it. Full format in
[`debug/README.md`](debug/README.md); the pass-through bug it surfaced (and the
single-pass movement rewrite that fixed it) is written up in
[`combat/README.md`](combat/README.md).

### Pilot Animations (UI-only, additive on top of logical state)
Pilot logical state (grid_pos, hp, alive…) updates instantly when the sim
ticks; the renderer reads animation timers from `PilotData` to soften the
visual transitions. All durations fit inside the 0.5s `AUTO_PLAY_INTERVAL`.

| Trigger | Site | Visual |
|---|---|---|
| Combat damage (전장 자동 교전) | `SimulationCore` damage_map apply | `anim_pilot_shake(p)` → `ANIM_SHAKE_DUR` 0.18s / `ANIM_SHAKE_AMP_PX` 6px horizontal jitter (decaying) |
| 공격 카드 명중 | `CardPhaseManager._apply_attack_damage` | same call with `ANIM_SHAKE_CARD_DUR` 0.26s / `ANIM_SHAKE_CARD_AMP_PX` **20px** — 매 턴 자동으로 오가는 교전 피해와 달리 카드 명중은 플레이어가 방금 고른 한 방이라 훨씬 격렬하게 흔든다. 주파수는 같으므로 진동 수가 4 → 5.8회로 함께 는다 |
| Movement (free + push advance + push retreat) | `resolve_movement` (once per pilot per turn) | `anim_pilot_move_path(p, path)` → 렌더러가 **실제로 밟은 칸의 폴리라인**을 따라 0.30s smoothstep 으로 미끄러뜨린다 (`BattleRenderer._glide`). 슬롯이 바뀌기만 해도 같은 글라이드가 걸린다 — 초상화는 어떤 경우에도 순간이동하지 않는다 |
| 카드 이동 / 전진 (`move`, `advance:N`) | `SimulationCore._step_pilot` | `anim_pilot_move(p, orig)` — 같은 프레임의 걸음은 **경로에 이어 붙는다**, 그래서 `advance:3` 이 세 칸을 순서대로 걷는다 |
| Recall — 저HP / 위치 이탈 | `RecallSystem.return_to_hq` | `anim_pilot_recall(p, orig)` → 0.20s fade-out + rise at `orig`, then 0.25s fade-in + descend at HQ. Both halves always play — the pilot never leaves the field, and it is holding still that turn, so the fade-in stays anchored at the HQ |
| Recall — 복귀 카드 | `CardPhaseManager._effect_recall_ally` | same `anim_pilot_recall(p, orig)` sequence |
| Respawn (사망 후 부활) | `SimulationCore.process_respawns` | `anim_pilot_respawn` → fade-in + descend at HQ only (skip phase 1); also clears any leftover 전사 연출 |
| 사망 | `BattleSim.mark_pilot_dead` | `anim_pilot_death` → `ANIM_DEATH_HOLD_DUR` (1.0s) dimmed-in-place at the cell they fell on, then `ANIM_DEATH_FADE_DUR` (0.45s) fading out while rising `ANIM_DEATH_RISE_PX`, then off the field |
| 공격 카드 명중 / 빗나감 | `CardPhaseManager._effect_attack` | `BattleRenderer.spawn_pilot_popup` → `-N` / `MISS` / `흡수` floating over the target's marker |
| 포탑 피격 | `SimulationCore` turret_dmg apply (`simulate_turn` + `_apply_card_damage`), survivors only | `anim_turret_hit(td)` → `ANIM_TURRET_HIT_DUR` (0.26s) of decaying horizontal jitter (`ANIM_TURRET_HIT_AMP_PX` 9px) plus an `ANIM_TURRET_HIT_TINT` red flash fading back to white |

`BattleSim._process` runs `_advance_pilot_animations(delta)` **and**
`_advance_turret_animations(delta)` every frame (both, never short-circuited)
and calls `renderer.queue_redraw()` while any timer is active. Constants live on
`BattleSim`: `ANIM_MOVE_DUR`, `ANIM_SHAKE_DUR`, `ANIM_SHAKE_AMP_PX`,
`ANIM_SHAKE_CARD_DUR`, `ANIM_SHAKE_CARD_AMP_PX`,
`ANIM_RECALL_FADE_OUT_DUR`, `ANIM_RECALL_FADE_IN_DUR`, `ANIM_RECALL_RISE_PX`,
`ANIM_DEATH_HOLD_DUR`, `ANIM_DEATH_FADE_DUR`, `ANIM_DEATH_RISE_PX`,
`ANIM_DEATH_TINT`, the turret trio `ANIM_TURRET_HIT_DUR` /
`ANIM_TURRET_HIT_AMP_PX` / `ANIM_TURRET_HIT_TINT`, and the popup trio
`DMG_POPUP_DUR` / `DMG_POPUP_RISE_PX` / `DMG_POPUP_STAGGER`.

**포탑 연출만 렌더러 밖에 있다.** A turret's sprite is a `Building` node under
`BattleField/BuildingLayer`, not something `BattleRenderer._draw()` paints, so
`BattleSim._apply_turret_hit_visual` writes the shake/flash straight onto that
node's `position` / `modulate` (base position cached per cell in
`_turret_home_pos`, restored on the last frame and on restart via
`_clear_turret_hit_visuals`). The renderer only mirrors the same offset onto the
turret HP bar by reading `BattleSim.turret_hit_offset(td)`.

`BattleRenderer` decides *whether* to draw a pilot with `_is_renderable(p)`
(alive, or mid-death, or mid-recall-fade-out — the last two run after `alive`
is already false), groups them by `_render_cell(p)` (`anim_recall_orig` during
fade-out, `anim_death_cell` during the 전사 연출, otherwise `grid_pos`) and
applies per-pilot pixel offset and alpha via `_pilot_anim_offset` /
`_pilot_anim_alpha`.

**이동만은 렌더러가 통째로 소유한다.** `BattleSim` 은 이동 타이머를 들고 있지
않고(`anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` 는 삭제됐다),
`PilotData.anim_move_path` 에 **밟은 칸의 경로**만 남긴다. 마커 좌표의 보간과
그동안의 재draw 는 `BattleRenderer._glide` 가 맡는다 — 자세한 규칙(폴리라인,
각도와 길이의 박자 분리, 스냅하는 경우)은 [`rendering/README.md`](rendering/README.md)
의 *마커 글라이드* 절.

---

## Dependencies

- `resources/GameEnums.gd` — shared enums
- `resources/PilotData.gd`, `TurretData.gd` — data classes
- `autoloads/GameManager.gd` — match_ctx + cards table loader
- `scenes/Card.tscn` (script: `features/battle_sim/card_phase/Card.gd`) — card visual node
- `scenes/BattleField.tscn` — TileMapLayer + Building/Waypoint child scenes
