class_name TurnEngageSim
extends RefCounted

# 교전 시뮬레이터 (headless) — **사이드뷰 벨트 무대 + 라운드 기반 턴제**.
#
# 노드를 하나도 만들지 않고 상태만 굴리기 때문에 EngageArena(렌더러)와 완전히
# 분리되며, 헤드리스로도 돌릴 수 있다. EngagePhaseManager 가 매 프레임
# step(delta) 를 호출하고, EngageArena 는 units / turrets / projectiles /
# popups / 라운드 상태를 읽어 그리기만 한다.
#
# 좌표계: **탑뷰(쿼터뷰) 바닥면**이다. x = 가로, y = 깊이(위쪽이 멀고 아래쪽이
# 가깝다). 진영이 좌우를 나누지 않는다 — **자리를 정하는 것은 전장 타일이다**:
# 교전이 열린 칸을 무대 한가운데 두고, 각 파일럿이 밟고 있던 칸의 상대 육각
# 오프셋을 무대 좌표로 환산해 그 자리에 세운다(`_place_from_grid`). 그래서
# "윗타일에 둘 · 아랫타일에 둘 · 왼쪽 정글에 하나"가 무대에서도 그 모양으로
# 선다. 한 칸에 여럿이면 그 칸 구역 안에서 흩어지고, 팀0 은 그 칸의 왼쪽 반
# 팀1 은 오른쪽 반을 쓴다 — 칸을 벗어나지 않으면서 진영도 읽히게.
#
# 이 배치는 **연출이다.** 판정은 라운드마다 전원이 한 번씩 돌아가며 때리는
# 그대로이고, 시작 자리가 바꾸는 것은 접근 거리와 표적 선택의 거리항뿐이다.
#
# 2026-08 이전의 **사이드뷰 벨트**(팀0 왼쪽 · 팀1 오른쪽으로 마주 서고 역할이
# 앞줄 / 뒷줄을 정하던 평면 벨트)는 여기서 대체됐다. `facing_x`(좌우 부호 하나로
# 방향을 표현하던 것) · `_place_row` · `_row_x` · `FRONT_OFFSET` · `ROW_GAP` ·
# `DEPTH_MARGIN` · `KNOCK_VERTICAL_SCALE` 이 그때 함께 사라졌다.
#
# ─── 행동 모델: 라운드 · 한 명씩 ─────────────────────────────────────────────
# **한 라운드 안에서 모두가 정확히 한 번씩 행동한다.** 무대에는 언제나 단 한
# 명(`current_actor`)만 나와 있고, 그 한 차례(접근 → 공격 → 정착)가 끝나면
# 다음 순서로 넘어간다. 마지막 순서까지 돌면 라운드가 하나 오르고 **다시
# 시전자부터** 같은 순서를 돈다.
#
# `engage:N` 의 N 은 초가 아니라 **라운드 수**다. 예전의 ATB(메크 `speed` 스탯에
# 비례해 차오르는 게이지로 행동 빈도가 갈리던 실시간 모델)는 **삭제**됐고
# `speed` 스탯도 데이터에서 사라졌다 — 되살리지 말 것. 그 이전의 탑뷰 아레나도
# 마찬가지.
#
# 데미지는 PilotData 에 직접 적용된다 — 교전이 끝나면 전장 상태에 그대로
# 반영된다.

# ─── 라운드 / 종료 ───────────────────────────────────────────────────────────
## 결투(1:1)는 한 쪽이 처치될 때까지 — 다만 서로 못 잡고 버티는 조합(원거리
## 미러 등)이 있으므로 관전 페이싱용 라운드 상한을 둔다.
const DUEL_MAX_ROUNDS: int = 10

# ─── 무대 지오메트리 (아레나 좌표, 렌더러가 카메라로 화면에 맞춘다) ─────────
## 무대 바닥면의 크기. 유닛은 항상 이 안에 갇힌다 — 교전 중 이탈은 없다.
## EngageArena.BAND_RECT(1032×1000)와 거의 같은 비율이라 카메라 최소 배율에서
## 바닥면이 밴드에 통째로 들어간다. 여기를 키우면 그 배율이 떨어져 유닛이 잘게
## 보인다.
const STAGE_W: float = 1240.0
const STAGE_H: float = 1180.0

# ─── 전장 타일 → 무대 좌표 ──────────────────────────────────────────────────
# **교전 시작 위치는 전장에서 어느 칸에 서 있었는지가 정한다 — 다만 반영하는
# 것은 그 칸의 *방향*뿐이고 물리적 거리는 반영하지 않는다.** 윗타일에 둘 ·
# 아랫타일에 둘 · 왼쪽 정글에 정글러 하나였다면 무대에서도 그 모양이지만, 그
# 정글러가 여덟 칸 떨어져 있었는지 두 칸이었는지는 무대에서 거의 같아 보인다.
# 전장의 거리를 곧이곧대로 옮기면 오브젝트 교전처럼 참가자가 전장 곳곳에서
# 모이는 경우에 무리가 무대 네 귀퉁이로 흩어지고, `_fit_scale` 이 그것을 통째로
# 줄이느라 얼굴만 잘게 보인다 — 배치가 말해야 하는 것은 "누가 어느 쪽에서
# 왔는가"이지 "몇 칸이었는가"가 아니다.
#
# 아래 둘은 **한 칸이 무대에서 차지하는 거리의 기준**이고, 세로가 가로보다 짧은
# 것은 쿼터뷰라 깊이 방향이 눌려 보이기 때문이다(같은 이유로 바닥 마커도 납작한
# 타원이다).
const CELL_SPAN_X: float = 300.0
const CELL_SPAN_Y: float = 235.0
## 한 칸에 여럿이 설 때 그 칸 중심에서 흩어지는 반경.
const CELL_CLUSTER_RX: float = 106.0
const CELL_CLUSTER_RY: float = 60.0
## 한 칸의 인원이 둘을 넘을 때마다 위 반경에 얹는 비율.
const CELL_CLUSTER_CROWD: float = 0.07
## 자리마다 얹는 흐트러짐 — 완벽한 격자는 기계적으로 보인다.
const SLOT_JITTER_X: float = 24.0
const SLOT_JITTER_Y: float = 16.0
## 칸 오프셋의 **포화 곡선**(단위: 칸). 거리 d 칸인 참가자는 원점에서
## `CELL_REACH_MAX * d / (d + CELL_REACH_HALF)` 칸 떨어진 자리에 선다 — 방향은 한
## 치도 안 바뀌고 거리는 **순서만 남긴 채** 상한에 수렴한다(1칸 0.82 · 2칸 1.07 ·
## 3칸 1.19 · 5칸 1.31 · 10칸 1.42 · ∞ 1.55 = 465 / 364px).
##
## 예전에는 거리를 그대로 곱한 뒤 상한에서 **잘라 냈다**(`MAX_CELL_OFFSET_X/Y`
## 660 / 517, **삭제됨**). 그 방식은 세 칸 넘게 떨어진 참가자를 전부 같은 상한에
## 붙여 **순서는 사라지는데 무대는 최대로 벌어지는** 최악을 골랐다 — 오브젝트
## 교전에서 참가자들이 서로 화면 끝에 서 있던 것이 그것이다. 곡선은 그보다 낮은
## 상한으로 무대를 안 벌리면서, 그 안에서 d 가 커질수록 조금씩이나마 계속 멀어져
## 순서를 도리어 되살린다. **결속 / 추적으로 전장 반대편에서 끌려 들어온
## 참가자**가 배치 전체의 배율을 혼자 무너뜨리지 않는 것도 그대로다.
const CELL_REACH_MAX: float = 1.55
const CELL_REACH_HALF: float = 0.9
## 칸 오프셋 바운딩 박스가 이 여백 안에 들어가도록 배치를 통째로 줄인다.
const STAGE_FIT_MARGIN: float = 150.0

# ─── 바닥 마커 충돌 ─────────────────────────────────────────────────────────
# **발밑 타원이 곧 충돌 판정이다.** 화면에 그려지는 그 원(`EngageArena` 의
# `GROUND_RX/RY` 가 아래 두 상수를 그대로 읽는다)이 서로 파고들지 않으므로,
# 두 유닛이 바닥의 같은 지점에 겹쳐 선 그림이 나오지 않는다 — 탑뷰에서 "이
# 유닛이 어디에 서 있는가"를 말하는 것은 82px 떠 있는 초상이 아니라 이 원이라,
# 원이 겹치면 자리 자체가 안 읽힌다.
#
# 판정은 **정규화한 원 공간**에서 한다: y 를 `FOOT_ASPECT` 배로 늘리면 납작한
# 타원 둘이 반지름 `FOOT_RX` 인 원 둘이 되고, 그러면 겹침 판정도 밀어내는
# 방향도 원 하나로 풀린다(타원끼리의 최단 거리에는 닫힌 해가 없다). 밀어낸
# 뒤 y 를 다시 나누어 원래 공간으로 돌린다.
#
# 실제 거리로는 **나란히 서면 60px · 위아래로 서면 26px** 이 최소 간격이다.
# 근접 사거리(`MELEE_REACH` 88)보다 작으므로 **공격하러 붙는 동작과 다투지
# 않는다** — 이 판정이 실제로 일하는 자리는 개시 배치(한 칸에 몰린 무리)와
# 넉백으로 남을 떠밀린 자리 둘이다.
const FOOT_RX: float = 30.0
const FOOT_RY: float = 13.0
const FOOT_ASPECT: float = FOOT_RX / FOOT_RY
## 이완 횟수. **겹침은 한 프레임 안에 다 푼다** — 조금씩 나눠 밀면(이완 비율을
## 1 미만으로 두면) 넉백처럼 깊이 파고드는 한 방에서 몇 프레임 동안 원이 겹친
## 채로 그려진다(실측: 비율 0.5 · 3회에서 최악 7.7% 겹침). 밀린 쪽이 그 자리에서
## 곧장 비켜 주는 편이 도리어 "부딪혀서 밀렸다"로 읽힌다.
##
## 개시 배치는 열 명이 한 칸에 몰릴 수 있어(오브젝트 교전 · 같은 칸 5v5) 더
## 많이 돈다. 한 쌍씩 즉시 반영하는 가우스-자이델이라 한 회에 푼 쌍이 뒤 쌍에
## 다시 밀릴 수 있고, 그 사슬이 인원수만큼 길어지기 때문이다.
const SEPARATE_ITERS_PLACE: int = 16
const SEPARATE_ITERS_TICK: int = 6

# ─── 유닛 ────────────────────────────────────────────────────────────────────
const UNIT_RADIUS: float = 40.0
## 근접이 공격을 넣기 위해 좁혀야 하는 거리. UNIT_RADIUS 두 개(80)보다 살짝
## 커서 초상화가 겹치지 않고 붙는다.
const MELEE_REACH: float = 88.0
## 원거리 사거리. 실제 발사는 이 값의 RANGED_APPROACH_RATIO 안에서만 한다.
const RANGE_RANGED: float = 300.0
## "최대 사거리의 이 비율 안까지 들어간 다음 공격한다." 이미 그 안이면 더
## 접근하지 않고 제자리에서 쏜다.
const RANGED_APPROACH_RATIO: float = 0.9
## 돌진 이동 속도(px/s). 근접이 더 빠르게 파고든다.
##
## ATB 시절보다 **빠르게** 잡혀 있다. 그때는 10명이 동시에 움직여 한 사람의
## 접근이 느려도 무대가 비지 않았지만, 지금은 한 번에 한 명뿐이라 접근 시간이
## 곧 관전자가 기다리는 시간이다. 3라운드 5v5 가 약 17초에 끝나는 것이 여기서
## 나온다 — 느리게 잡으면 그대로 30초를 넘긴다.
const MOVE_SPEED_MELEE: float = 1600.0
const MOVE_SPEED_RANGED: float = 1250.0
## 넉백으로 밀려난 만큼 자기 자리(anchor_pos)로 되돌아오는 드리프트 속도 배율.
## **원위치 복귀가 아니다** — 앵커 자체가 마지막으로 공격한 자리로 갱신되므로
## 이 드리프트는 벨트 클램프 등으로 어긋난 잔차만 추스른다.
const SETTLE_SPEED_MULT: float = 0.85
## 접근 단계가 이 시간을 넘기면 이번 차례를 접는다(대상이 멀리 밀려나 있는 등의
## 교착 방지). 접는 자리가 곧 새 앵커다. 사이드뷰 벨트(깊이 400) 시절의 0.55 는
## 탑뷰 바닥면(1180)에서 **대각선 반대편의 적에게 닿지 못한다** — 그 차례가
## 통째로 "걸어가다 말았다"가 되므로 무대가 커진 만큼 함께 늘렸다.
const ADVANCE_MAX_SEC: float = 0.85
## 공격 모션을 붙잡는 시간. 이 동안 유닛은 대상 앞에 멈춰 서 있다.
## 원거리는 투사체 비행(최대 270px / PROJECTILE_SPEED ≈ 0.19초)이 끝나기를
## 기다려야 하므로 근접보다 길다.
const STRIKE_HOLD_MELEE: float = 0.20
const STRIKE_HOLD_RANGED: float = 0.26
## 한 차례가 끝나고 다음 순서로 넘어가기까지의 짧은 숨.
const ACTOR_GAP_SEC: float = 0.06
## 라운드 사이의 숨. 렌더러가 이 동안 라운드 배너를 띄운다.
const ROUND_GAP_SEC: float = 0.45
## 포탑이 사격 모션을 붙잡는 시간(포탑 차례의 길이).
const TURRET_FIRE_HOLD: float = 0.30
## 앵커에 도착한 것으로 치는 거리.
const HOME_EPSILON: float = 6.0
## 사거리 판정 여유(px). **없으면 근접이 두 번째 공격부터 영영 못 나간다.**
## `_tick_advance` 의 정지점은 `target.pos - dir * strike_dist()` 이고
## `_step_toward` 가 거기에 스냅하므로, 접근을 끝낸 유닛은 사거리 **딱 그
## 거리**에 선다. 그 자리에서 다시 잰 거리는 부동소수 오차로 88.0 바로 위에
## 떨어지기 일쑤라 `dist <= strike_dist()` 가 거짓이 되고, 유닛은 이미 도착한
## 정지점을 향해 0px 씩 "이동"하다가 `ADVANCE_MAX_SEC` 교착으로만 차례를
## 접는다 — 공격은 한 번도 성립하지 않는다.
const STRIKE_DIST_EPSILON: float = 0.5

# ─── 넉백 (피격 피드백 + 재접근 거리) ───────────────────────────────────────
## 명중 시 대상에게 실리는 초기 속도(px/s). 감쇠까지 합치면 근접 ≈ 47px,
## 원거리 ≈ 17px 밀려나고, 밀려난 자리가 그대로 새 앵커가 된다
## (`_apply_knockback`). 이 거리가 때린 쪽의 다음 차례 돌진 거리이기도 하다 —
## 0 으로 두면 근접이 사거리에 붙어 선 채 굳어 공격 모션이 사라진다.
const KNOCK_IMPULSE_MELEE: float = 420.0
const KNOCK_IMPULSE_RANGED: float = 150.0
## 넉백 속도의 지수 감쇠 계수(1/s).
const KNOCK_DAMP: float = 9.0
## 넉백 연출 타이머(렌더러 전용) 길이.
const KNOCK_FLASH_SEC: float = 0.22

# ─── 포탑 ────────────────────────────────────────────────────────────────────
# 전장과 달리 아레나의 포탑은 **파일럿을 공격한다**. 다만 사거리 원 개념은 없다 —
# 참가한 포탑은 아레나 전체를 사정권으로 본다. 참가 조건은 단 하나:
# **자기 팀 파일럿이 그 포탑 칸 위에 서 있을 때**. 즉 포탑 칸에 있는 적을
# 상대로 교전을 걸면 그 포탑이 방어에 가담한다.
#
# 포탑도 **라운드마다 한 번** 행동한다 — 파일럿 전원이 돌고 난 뒤, 시전자 팀
# 포탑부터 차례가 온다. 예전의 자기 ATB(TURRET_SPEED)는 삭제됐다.
#
# **포탑은 무대 참가자가 아니라 지형이다.** 탑뷰에서는 자기가 실제로 서 있는
# 칸(= 파일럿과 같은 `_cell_offset` 매핑) 위에 그대로 서고, 렌더러의 카메라
# 프레이밍에서는 여전히 빠진다(EngageArena._focus_positions) — 포탑을 프레임에
# 넣으면 무대 끝까지 담느라 배율이 떨어져 정작 싸우는 유닛이 잘게 보인다.
# 사이드뷰 시절의 "지평선 한 줄에 나란히"(TURRET_BACK_OFFSET / TURRET_BG_Y /
# TURRET_BG_STEP)는 그래서 삭제됐다 — 그 자리는 무대에 지평선이 있었기에
# 성립하던 것이고, 지금은 포탑도 파일럿과 같은 바닥면 위에 있다.
## 포탑 명중 굴림에 쓰는 고정 hit 스탯(포탑에는 hit 스탯이 없다).
const TURRET_HIT: int = 50

const PROJECTILE_SPEED: float = 1400.0

# ─── 명중 보정 ────────────────────────────────────────────────────────────
## 명중 확률 공식은 **전장과 공유한다** — `PilotData.hit_chance` 가 비율
## `hit/(hit+eva)` 을 80~100% 구간에 선형으로 엹는다(대등하면 90%).
## 다른 것은 **입력**이다 — 이 무대는 `engage_hit` / `engage_eva`(교전 명중 /
## 교전 회피)를 읽고, 전장(`SimulationCore.roll_hit`)은 `hit` / `evasion`을 읽는다.
## 그래서 같은 선수가 라인전과 한타에서 다를 수 있고, 그 둘을 가르는 것이
## 주간 훈련판이 주는 선택지다.
##
## 예전에는 구간과 공식이 이 파일에만 있었고(`ENGAGE_HIT_MIN` / `_MAX`, **삭제됨**)
## 전장은 비율을 그대로 확률로 썼다 — 같은 스탯 차이가 두 무대에서 전혀 다른
## 크기로 읽혔다.

## 유닛 상태. 이탈 / 후퇴 / **원위치 복귀** 상태는 없다 — 라운드가 끝날 때까지
## 아무도 벨트를 뜨지 못하고, 공격을 끝낸 유닛은 그 자리에 눌러앉는다.
##   IDLE    — 자기 차례가 아니다. 넉백 잔차만 추스른다.
##   ADVANCE — 자기 차례. 대상에게 접근. 사거리에 들면 STRIKE.
##   STRIKE  — 공격 판정 완료, 모션 홀드. 끝나면 그 자리를 앵커로 삼고 IDLE.
enum State { IDLE, ADVANCE, STRIKE, DEAD }

## 라운드 진행 상태. 렌더러가 헤더/배너에 쓴다.
##   ROUND_START — 라운드 배너를 띄우는 짧은 정지
##   ACTING      — current_actor 가 자기 차례를 수행 중
##   ACTOR_GAP   — 한 차례가 끝나고 다음 순서로 넘어가는 숨
##   DONE        — 종료 판정이 났다 (finished == true)
enum Flow { ROUND_START, ACTING, ACTOR_GAP, DONE }

## 팀 안에서의 행동 우선순위. 앞이 먼저 나간다 — 파고드는 역할이 먼저 열고
## 뒤에서 받아 치는 역할이 나중에 정리하는 순서다. 시전자는 이 순서를 무시하고
## 자기 팀 맨 앞으로 당겨진다.
const ROLE_ACT_ORDER: Array[int] = [
	GameEnums.Role.ASSASSIN,
	GameEnums.Role.FIGHTER,
	GameEnums.Role.TANK,
	GameEnums.Role.SNIPER,
	GameEnums.Role.SUPPORT,
]


# ─── 유닛 ────────────────────────────────────────────────────────────────────
class EUnit extends RefCounted:
	var pilot: PilotData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	## 지금 이 유닛이 서 있기로 한 자리. 개전 시엔 진형 슬롯이고, 그 뒤로는
	## **마지막으로 공격을 끝낸 자리**(_settle) 또는 **넉백으로 밀려난 자리**
	## (_apply_knockback)로 갱신된다 — 원위치 복귀가 없으므로.
	## 타겟 거리 계산의 기준점.
	var anchor_pos: Vector2 = Vector2.ZERO
	var is_melee: bool = true
	## 적 뒷줄(원거리)을 우선으로 노리는가. 암살자만 true.
	var dives_backline: bool = false
	## 파일럿 스킬이 강제하는 **첫 공격**의 표적 역할(GameEnums.Role). -1 = 없음.
	## 원딜 사냥꾼 하나가 쓴다 — 그 한 번이 지나면 `skill_focus_used` 가 켜져
	## 평소 표적 규칙으로 돌아간다.
	var skill_focus_role: int = -1
	var skill_focus_used: bool = false
	## 이번 차례의 표적을 **약자 멸시**가 정했는가. 스택은 그때만 소모된다 —
	## 다른 규칙이 고른 표적에까지 값을 물리면 스택이 겨눔과 무관하게 마른다.
	var atk_range: float = 0.0
	var move_speed: float = 0.0

	var state: int = State.IDLE
	var target: EUnit = null
	## 현재 행동(ADVANCE/STRIKE) 경과 시간.
	var act_t: float = 0.0
	## 넉백 잔여 속도.
	var knock_vel: Vector2 = Vector2.ZERO
	## 바라보는 방향(단위 벡터). 탑뷰라 **모든 방향**에 의미가 있다 — 좌우
	## 부호 하나(`facing_x`)로 표현하던 사이드뷰 시절과 다른 점이다.
	var facing: Vector2 = Vector2.RIGHT
	## [강습]으로 적진 한가운데에 낙하한 유닛인가. 렌더러가 바닥 마커를 겹링으로
	## 그려 "여기로 떨어졌다"를 남긴다.
	var dropped_in: bool = false
	## 피격 플래시 잔여 시간(렌더러 전용).
	var hit_flash: float = 0.0
	## 공격 모션 잔여 시간(렌더러 전용).
	var swing_t: float = 0.0

	func is_active() -> bool:
		return state != State.DEAD

	func hp_ratio() -> float:
		if pilot == null or pilot.max_hp <= 0:
			return 0.0
		return clampf(float(pilot.hp) / float(pilot.max_hp), 0.0, 1.0)

	## 이번 행동에서 공격이 성립하는 거리.
	func strike_dist() -> float:
		return MELEE_REACH if is_melee else atk_range * RANGED_APPROACH_RATIO

	## 행동 중(= 지금 나와서 때리는 중)인가. 렌더러가 강조 표시에 쓴다.
	func is_acting() -> bool:
		return state == State.ADVANCE or state == State.STRIKE


# ─── 아레나에 등장하는 포탑 ──────────────────────────────────────────────────
class ETurret extends RefCounted:
	var data: TurretData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	var atk: int = 0
	## 사격 모션 잔여 시간(렌더러 전용).
	var fire_t: float = 0.0
	## 마지막 사격 대상 — 렌더러가 사격선을 그릴 때 쓴다.
	var last_target: EUnit = null

	func is_active() -> bool:
		return data != null and data.alive


# ─── 상태 (EngageArena 가 읽는다) ────────────────────────────────────────────
var units: Array = []          # Array[EUnit]
var turrets: Array = []        # Array[ETurret]
var projectiles: Array = []    # Array[Dictionary] {from,to,t,dur,team,is_turret}
var popups: Array = []         # Array[Dictionary] {pos,text,color} — 렌더러가 소비 후 비운다
var stats: Dictionary = {}     # PilotData → {dealt,taken,kills}

## 1-based 진행 라운드. 개시 직후부터 1 이다.
var round_index: int = 1
## 카드가 정한 라운드 수. 결투는 DUEL_MAX_ROUNDS.
var total_rounds: int = 1
## 지금 무대에 나와 있는 행동자 (EUnit 또는 ETurret 또는 null).
var current_actor = null
var flow: int = Flow.ROUND_START
var finished: bool = false
var initiator_team: int = 0
var is_duel: bool = false
## 순수 관전 경과 시간(초). 페이싱 계측용 — 종료 판정에는 쓰지 않는다.
var elapsed: float = 0.0

## 라운드마다 반복되는 행동 순서. 개시 시 한 번 정하고 그 뒤로 바뀌지 않는다 —
## "매번 시전자의 순서로 시작"이 성립하는 근거. 죽은 행동자는 건너뛴다.
var _order: Array = []
var _order_idx: int = -1
## ROUND_START / ACTOR_GAP 의 잔여 시간.
var _gap_left: float = 0.0

var _bs: BattleSim = null
var _origin_cell: Vector2i = Vector2i.ZERO
## 시전자가 있는 교전인가(= 카드가 연 교전인가). 오브젝트 교전은 false 이고,
## 그때는 포탑이 한 기도 가담하지 않는다 — `_build_turrets` 참조.
var _has_caster: bool = false


# 유닛이 돌아다닐 수 있는 바닥면. 렌더러의 최소 카메라 배율도 여기서 나온다.
static func ground_rect() -> Rect2:
	return Rect2(0.0, 0.0, STAGE_W, STAGE_H)


## 카메라가 비출 수 있는 최대 범위 — 바닥면을 사방으로 조금 넓힌 것. 여백이
## 필요한 이유는 초상화가 발밑에서 `EngageArena.UNIT_LIFT` 만큼 떠 있어서다:
## 바닥면 딱 그만큼만 열어 두면 맨 윗줄에 선 유닛의 얼굴이 잘린다.
const STAGE_MARGIN: float = 130.0

static func stage_rect() -> Rect2:
	return ground_rect().grow(STAGE_MARGIN)


# 참가자 목록을 받아 벨트를 구성한다.
#   `caster` — 시전자. 매 라운드 **첫 번째로** 행동한다. **null 이어도 된다** —
#              오브젝트 교전(전령 / 용)은 카드가 아니라 타이머가 여는 것이라
#              시전자가 없다. 그때는 순서가 역할 우선순위만으로 정해지고
#              선공 팀은 `first_team` 이 정한다.
#   `team0/1` — 참가 PilotData 배열.
#   `rounds` — 라운드 수. 결투는 DUEL_MAX_ROUNDS 를 넘긴다.
#   `first_team` — 선공 팀. -1 이면 시전자의 팀(시전자도 없으면 팀0).
#   `origin` — 무대 한가운데에 놓을 전장 칸. 기본값(-999,-999)이면 시전자 칸.
#              [돌격] · [강습] 처럼 무대가 시전자가 아닌 **지정한 적** 주변에서
#              열리는 카드는 여기에 그 칸을 넣는다 — 그래야 화면 한가운데가
#              실제로 교전이 열린 자리가 된다.
#   `drop_in` — [강습]. 시전자만 타일 위치를 무시하고 적 진영 한가운데에 낙하.
#
# **`setup` 은 무대를 세우기만 한다.** 실제로 싸움이 시작되는 것은 `begin()`
# 이고, 둘이 갈라져 있는 것은 개시 확인 화면(VS)이 **같은 시뮬레이터를 미리
# 만들어 그림만 보여 주기** 때문이다: 거기서 취소하면 아무 일도 일어나지
# 않아야 하는데 약자 멸시의 개시 타격(`_contempt_opening`)은 피해를 넣고
# 충전을 태운다. 그래서 상태를 바꾸는 것은 전부 `begin()` 쪽에 있다.
func setup(bs: BattleSim, caster: PilotData, team0: Array, team1: Array,
		rounds: int, duel: bool, first_team: int = -1,
		origin: Vector2i = Vector2i(-999, -999), drop_in: bool = false) -> void:
	_bs = bs
	if origin != Vector2i(-999, -999):
		_origin_cell = origin
	else:
		_origin_cell = caster.grid_pos if caster != null else Vector2i.ZERO
	_has_caster = caster != null
	if first_team >= 0:
		initiator_team = first_team
	else:
		initiator_team = caster.team if caster != null else 0
	is_duel = duel
	total_rounds = max(1, rounds)

	_build_units(caster, team0, team1)
	_build_turrets()
	# 배치는 유닛과 포탑이 **둘 다** 만들어진 뒤에 한 번에 한다 — 둘이 같은
	# 칸→무대 매핑을 쓰고, 축소 배율도 둘의 칸을 함께 보고 정해지기 때문이다.
	_place_from_grid()
	if drop_in:
		_apply_drop_in(caster)
	# 겹침 정리는 **낙하까지 끝난 뒤**다 — [강습]의 시전자는 적 진형 한가운데,
	# 곧 이미 누가 서 있는 자리로 떨어지므로 그 한 명이야말로 밀어내야 한다.
	_separate_units(SEPARATE_ITERS_PLACE)
	_face_initial()
	_build_order(caster)

	round_index = 1
	_order_idx = -1
	flow = Flow.ROUND_START
	_gap_left = ROUND_GAP_SEC


## 개시 — 여기부터 상태가 바뀐다. 호출 측(`EngagePhaseManager._begin`)은 메크 ·
## 파일럿 스킬의 교전 개시 훅을 **먼저** 돌린 뒤에 부른다(약자 멸시의 충전이
## 그 훅에서 채워진다).
func begin() -> void:
	_contempt_opening()
	round_index = 1
	_order_idx = -1
	flow = Flow.ROUND_START
	_gap_left = ROUND_GAP_SEC
	finished = false
	elapsed = 0.0


## 약자 멸시(암살 R) — **1라운드가 돌기 전에** 터지는 선제 타격. 손패에 든
## [약자 멸시]의 충전을 통째로 태우고, 태운 수만큼 **체력이 가장 적은 적**을
## 공격력 `CONTEMPT_DMG_MULT` 로 때린다.
##
## 순서가 중요하다: `_build_units` 뒤라야 무대에 선 유닛과 그 자리가 정해져 있고
## (팝업 좌표가 거기서 나온다), 라운드 루프 앞이라야 "교전을 시작하면"이 된다.
## 오버클럭은 태우지 않는다(`allow_extra = false`) — 개시 타격이 다시 추가 공격을
## 굴리면 카드 한 장이 교전을 혼자 끝낼 수 있다.
func _contempt_opening() -> void:
	var mech: MechSkillSystem = _bs.mech_skill
	if mech == null:
		return
	for raw in units:
		var u := raw as EUnit
		var n: int = mech.take_contempt_charges(u.pilot)
		if n <= 0:
			continue
		popups.append({"pos": u.pos, "text": "약자 멸시 x%d" % n,
				"color": Color(1.0, 0.72, 0.35)})
		for _i in n:
			var weak: EUnit = _weakest_enemy(u)
			if weak == null:
				break
			_strike_one(u, weak, false, CONTEMPT_DMG_MULT)


# ─── 구성 ────────────────────────────────────────────────────────────────────
# 유닛만 만든다 — **자리는 `_place_from_grid` 가 전장 타일에서 가져온다.**
# 사이드뷰 시절에는 여기서 역할이 앞줄 / 뒷줄을 갈랐는데(근접 앞 · 원거리 뒤),
# 탑뷰에서는 그 줄이 곰 거짓말이 된다: 화면에 보이는 자리가 전장의 자리와 아무
# 관계가 없으면 "위쪽 타일에 둘, 아래쪽 타일에 둘"을 보고 교전을 걸 이유가 사라진다.
func _build_units(_caster: PilotData, team0: Array, team1: Array) -> void:
	units.clear()
	stats.clear()
	for t in range(2):
		for raw in (team0 if t == 0 else team1):
			var p := raw as PilotData
			if p == null or not p.alive:
				continue
			units.append(_make_unit(p))
			# `score0` 는 교전 **개시 시점**의 성장치 — 결과 대시보드가 이 값과
			# 지금 값의 차를 "성장" 행으로 보여 준다.
			stats[p] = {"dealt": 0, "taken": 0, "kills": 0, "score0": p.score}


func _make_unit(p: PilotData) -> EUnit:
	var u := EUnit.new()
	u.pilot = p
	u.team = p.team
	u.is_melee = _is_melee_role(p.role)
	u.dives_backline = (p.role == GameEnums.Role.ASSASSIN)
	# 원딜 사냥꾼(파일럿 스킬)이 강제하는 첫 표적. 스킬이 없으면 -1 이라
	# `_pick_target` 이 평소 규칙으로 흐른다.
	u.skill_focus_role = _bs.skill.engage_focus_role(p) if _bs.skill != null else -1
	u.atk_range = MELEE_REACH if u.is_melee else RANGE_RANGED
	u.move_speed = MOVE_SPEED_MELEE if u.is_melee else MOVE_SPEED_RANGED
	u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	return u


## 라운드마다 반복되는 행동 순서를 만든다.
##
## **상황 기반 — 팀 교대 + 팀 내 역할 고정.** 시전자 팀부터 한 명, 상대 팀에서
## 한 명씩 번갈아 나간다. 팀 안의 순서는 `ROLE_ACT_ORDER` 로 고정하되 **시전자는
## 자기 팀 맨 앞으로 당겨진다** — 교전을 연 쪽이 선공한다는 것이 전투 개시
## 카드의 값이다.
##
## 포탑은 파일럿 전원이 돈 **뒤** 시전자 팀 포탑부터 차례를 갖는다. 유닛 벨트에
## 섞어 넣지 않는 이유는 포탑이 무대 참가자가 아니라 배경 지형이라서다 —
## 카메라도 포탑을 프레이밍하지 않으므로 파일럿 사이에 끼우면 화면 밖에서
## 포격만 날아오는 침묵 구간이 생긴다.
##
## 순서는 개시 시 한 번만 정한다. 죽은 행동자는 `_advance_order` 가 건너뛰므로
## 라운드가 흘러도 살아 있는 사람의 상대 순서는 바뀌지 않는다.
func _build_order(caster: PilotData) -> void:
	_order.clear()
	var first: int = initiator_team
	var second: int = 1 - first
	var by_team: Array = [_role_sorted(first, caster), _role_sorted(second, caster)]
	var n: int = max((by_team[0] as Array).size(), (by_team[1] as Array).size())
	for i in n:
		if i < (by_team[0] as Array).size():
			_order.append((by_team[0] as Array)[i])
		if i < (by_team[1] as Array).size():
			_order.append((by_team[1] as Array)[i])
	for t in [first, second]:
		for raw in turrets:
			var et := raw as ETurret
			if et.team == t:
				_order.append(et)


## 한 팀의 유닛을 역할 우선순위로 정렬한다. `caster` 가 이 팀이면 맨 앞으로.
func _role_sorted(team: int, caster: PilotData) -> Array:
	var out: Array = []
	for raw in units:
		var u := raw as EUnit
		if u.team == team:
			out.append(u)
	out.sort_custom(func(a, b) -> bool:
		return _role_rank((a as EUnit).pilot.role) < _role_rank((b as EUnit).pilot.role))
	for i in out.size():
		if (out[i] as EUnit).pilot == caster:
			var u: EUnit = out.pop_at(i)
			out.insert(0, u)
			break
	return out


static func _role_rank(role: int) -> int:
	var idx: int = ROLE_ACT_ORDER.find(role)
	return ROLE_ACT_ORDER.size() if idx < 0 else idx


# ─── 타일 기반 배치 ─────────────────────────────────────────────────
# **무대의 자리는 전장의 자리다.** 교전이 열린 칸(`_origin_cell`)을 무대 한가운데
# 두고, 참가자와 가담 포탑이 밟고 있는 칸의 **상대 육각 오프셋**을 무대 좌표로
# 환산해 세운다. 진영으로 좌우를 가르지 않는 것이 요점이다 — 같은 칸에서 붙은 두
# 팀은 무대에서도 한 칸에 섞여 서고, 위 타일에 둘 · 아래 타일에 둘이었다면 무대에서도
# 위 둘 · 아래 둘이다.
#
# 이 자리는 **개시 시점의 앵커**일 뿐이다 — 첫 공격을 끝내는 순간부터 앵커는
# 그때그때 서 있는 자리로 갱신된다(`_settle`).
func _place_from_grid() -> void:
	var by_cell: Dictionary = {}          # Vector2i -> Array[EUnit]
	for raw in units:
		var u := raw as EUnit
		if not by_cell.has(u.pilot.grid_pos):
			by_cell[u.pilot.grid_pos] = []
		(by_cell[u.pilot.grid_pos] as Array).append(u)

	# 1) 칸마다 무대 오프셋. 포탑 칸도 같은 표에 넣는다 — 축소 배율은 화면에
	#    들어가야 하는 것 **전부**를 보고 정해져야 한다.
	var offs: Dictionary = {}             # Vector2i -> Vector2
	for cell in by_cell:
		offs[cell] = _cell_offset(cell)
	for raw in turrets:
		var et := raw as ETurret
		var tc: Vector2i = et.data.grid_pos
		if not offs.has(tc):
			offs[tc] = _cell_offset(tc)

	# 2) 오프셋을 **바운딩 박스 중심**으로 옮긴다. 무대 한가운데에 놓아야 하는
	#    것은 교전이 열린 칸이 아니라 참가자들이 만든 덩어리다 — 열린 칸을
	#    중심으로 못박으면 그 칸이 무리의 끝일 때(무대를 지정한 적 쪽으로 옮기는
	#    [돌격] · [강습], 또는 오브젝트 칸에서 열리는 교전) 무대 절반이 통째로
	#    빈다. 옮겨도 **상대 위치는 한 픽셀도 안 바뀐다** — 배치가 말하는 것은
	#    그것뿐이므로 잃는 정보가 없다.
	_recentre(offs)

	# 3) 전부 무대 안에 들어가도록 통째로 줄인다. 같은 이유로 배율이 줄어도
	#    "위 둘 / 아래 둘 / 왼쪽 하나"는 그대로 읽힌다.
	var fit: float = _fit_scale(offs.values())
	var centre := Vector2(STAGE_W * 0.5, STAGE_H * 0.5)
	for cell in offs.keys():
		offs[cell] = centre + (offs[cell] as Vector2) * fit

	# 4) 칸 안의 자리. **칸 윤곽은 그리지 않는다** — 거리를 방향으로만 압축한
	#    지금은 무대의 한 칸이 전장의 한 칸과 같은 크기가 아니라, 바닥에 육각을
	#    그려 두면 그것이 도리어 거짓 축척을 말한다.
	for cell in by_cell:
		_seat_cell(by_cell[cell] as Array, offs[cell] as Vector2, fit)

	# 5) 포탑은 자기 칸 위에 그대로 선다.
	for raw in turrets:
		var et2 := raw as ETurret
		et2.pos = _clamp_to_ground(offs[et2.data.grid_pos] as Vector2)


## 오프셋 표를 자기 바운딩 박스 중심 기준으로 옮긴다(제자리 수정).
static func _recentre(offs: Dictionary) -> void:
	if offs.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for cell in offs:
		var o: Vector2 = offs[cell]
		mn = Vector2(minf(mn.x, o.x), minf(mn.y, o.y))
		mx = Vector2(maxf(mx.x, o.x), maxf(mx.y, o.y))
	var mid: Vector2 = (mn + mx) * 0.5
	for cell in offs.keys():
		offs[cell] = (offs[cell] as Vector2) - mid


## 한 칸의 무대 오프셋(무대 중심 기준). **방향은 전장 그대로, 거리는 포화 곡선으로
## 압축한다.** 육각 화면 좌표의 차를 칸 피치로 나눠 "칸 단위 벡터"를 만들고 — 육각
## 오프셋 좌표는 홀/짝 열마다 이웃 규칙이 달라 손으로 적은 표가 조용히 틀리기 쉬운
## 자리라, 격자 자신이 이미 답을 아는 `hex_to_screen` 을 그대로 지난다 — 그 **단위
## 방향만** 남긴 뒤 길이를 `CELL_REACH_*` 곡선으로 다시 매긴다. 마지막에
## `CELL_SPAN_*` 을 성분별로 곱하는 것이 쿼터뷰의 세로 압축이다.
func _cell_offset(cell: Vector2i) -> Vector2:
	var g: HexGrid = _bs.hex_grid if _bs != null else null
	if g == null or g.hex_size <= 0.0 or g.hex_height <= 0.0:
		return Vector2.ZERO
	var d: Vector2 = g.hex_to_screen(cell.x, cell.y) \
			- g.hex_to_screen(_origin_cell.x, _origin_cell.y)
	# 칸 피치로 나눈 "칸 단위" 벡터. 교전이 열린 칸 자신은 여기서 끝난다.
	var n := Vector2(d.x / (g.hex_size * 1.5), d.y / g.hex_height)
	var dist: float = n.length()
	if dist < 0.001:
		return Vector2.ZERO
	var dir: Vector2 = n / dist
	var reach: float = CELL_REACH_MAX * dist / (dist + CELL_REACH_HALF)
	return Vector2(dir.x * reach * CELL_SPAN_X, dir.y * reach * CELL_SPAN_Y)


## 오프셋 바운딩 박스를 무대 안(여백 포함)으로 밀어 넣는 균일 축소 배율.
static func _fit_scale(offsets: Array) -> float:
	var mx: float = 0.0
	var my: float = 0.0
	for raw in offsets:
		var o := raw as Vector2
		mx = maxf(mx, absf(o.x))
		my = maxf(my, absf(o.y))
	var lim_x: float = STAGE_W * 0.5 - STAGE_FIT_MARGIN
	var lim_y: float = STAGE_H * 0.5 - STAGE_FIT_MARGIN
	var s: float = 1.0
	if mx > lim_x:
		s = minf(s, lim_x / mx)
	if my > lim_y:
		s = minf(s, lim_y / my)
	return s


## 한 칸 안의 자리. 혼자면 칸 한가운데, 여러이면 **팀0 은 왼쪽 반원 · 팀1 은 오른쪽
## 반원**으로 나누어 앉는다 — 칸을 벗어나지 않으면서 어느 쪽이 내 팀인지가 읽힌다.
## 팀을 통째로 좌우로 가르는 것과는 다르다: 가르는 단위가 무대 전체가 아니라
## **칸 하나**라, 타일 배치는 그대로 남는다.
func _seat_cell(row: Array, at: Vector2, fit: float) -> void:
	var n: int = row.size()
	if n == 0:
		return
	if n == 1:
		var only := row[0] as EUnit
		only.anchor_pos = _clamp_to_ground(at + _slot_jitter(fit))
		only.pos = only.anchor_pos
		return
	var side: Array = [[], []]
	for raw in row:
		(side[(raw as EUnit).team] as Array).append(raw)
	# 붐비는 칸은 반원을 조금 넓힌다 — 초상화 지름이 UNIT_RADIUS×2(80)라 한 팀
	# 셋 이상이 기본 반경에 서면 얼굴이 서로를 덮는다. 넓혀도 칸 윤곽을 크게
	# 벗어나지는 않고, 그 정도 겹침은 "한 타일에 몰려 있다"로 읽혀야 맞다.
	var crowd: float = 1.0 + CELL_CLUSTER_CROWD * float(maxi(0, n - 2))
	var rx: float = CELL_CLUSTER_RX * fit * crowd
	var ry: float = CELL_CLUSTER_RY * fit * crowd
	for t in range(2):
		var arc: Array = side[t]
		var m: int = arc.size()
		# 팀0 = 왼쪽(각도 PI 중심) · 팀1 = 오른쪽(각도 0 중심) 반원.
		var base: float = PI if t == 0 else 0.0
		for i in m:
			var f: float = 0.5 if m == 1 else float(i) / float(m - 1)
			var a: float = base + (f - 0.5) * PI * 0.92
			var u := arc[i] as EUnit
			u.anchor_pos = _clamp_to_ground(at
					+ Vector2(cos(a) * rx, sin(a) * ry) + _slot_jitter(fit))
			u.pos = u.anchor_pos


func _slot_jitter(fit: float) -> Vector2:
	return Vector2(randf_range(-SLOT_JITTER_X, SLOT_JITTER_X),
			randf_range(-SLOT_JITTER_Y, SLOT_JITTER_Y)) * fit


## [강습] — 시전자만 자기 타일을 무시하고 **적 진영 한가운데에 낙하**한다.
## 카드 문안에는 적혀 있지 않지만 그것이 이 카드의 그림이다(공중에서 떨어져 그대로
## 전장에 투입된다). 배치 연출이지 판정 변경이 아니다 — 라운드마다 돌아가며 한 번씩
## 때리는 것은 그대로다. 바뀌는 것은 접근 거리와, 그 거리를 보는 표적 선택의
## 가중뿐이다.
func _apply_drop_in(caster: PilotData) -> void:
	if caster == null:
		return
	var u: EUnit = _unit_for(caster)
	if u == null:
		return
	var sum := Vector2.ZERO
	var n: int = 0
	for raw in units:
		var e := raw as EUnit
		if e.team != u.team:
			sum += e.pos
			n += 1
	if n == 0:
		return
	u.anchor_pos = _clamp_to_ground(sum / float(n))
	u.pos = u.anchor_pos
	u.dropped_in = true


## 개시 시점의 시선 — 적 무리 쪽을 본다. 사이드뷰에서는 팀이 곰 방향이라 이럴
## 필요가 없었지만(팀0 은 언제나 오른쪽), 탑뷰에서는 적이 어느 쪽에 있는지가 칸
## 배치마다 다르다.
func _face_initial() -> void:
	for raw in units:
		var u := raw as EUnit
		var sum := Vector2.ZERO
		var n: int = 0
		for other in units:
			var e := other as EUnit
			if e.team != u.team:
				sum += e.pos
				n += 1
		if n > 0:
			_face_toward(u, sum / float(n) - u.pos)


# 포탑 참가 규칙: **적이 걸어온 교전에서만**, 그리고 **참가 파일럿이 자기 팀
# 포탑 칸 위에 서 있을 때만** 그 포탑이 가담한다. 즉 포탑은 "허깅하고 있는 우리
# 편에게 적이 교전을 강제했을 때" 방어에 나서는 것이지, 우리가 그 자리에서 먼저
# 교전을 열 때 따라 나오는 화력이 아니다. 포탑 칸에 눌러앉아 카드로 교전을
# 여는 쪽이 포탑까지 끼고 싸우면 그 칸이 일방적인 안전지대가 된다.
#
# 그래서 걸러 내는 자리가 둘이다.
#   1. **오브젝트 교전(전령 / 용)에는 어느 팀 포탑도 안 낀다** — 시전자가 없는
#      교전이라 "누가 걸었는가"가 없고, 무대도 중립 칸에서 열린다.
#   2. **시전자 팀의 포탑은 빠진다** — 교전을 연 쪽이 곧 강제한 쪽이다.
#
# 가담한 포탑에 사거리 개념은 없다 — 아레나 전체를 사정권으로 본다.
# 자리는 파일럿과 같은 **자기 칸 위**다(`_place_from_grid`).
func _build_turrets() -> void:
	turrets.clear()
	if not _has_caster:
		return                       # 오브젝트 교전 — 포탑은 가담하지 않는다.
	# 참가자가 밟고 있는 셀 집합을 팀별로 모은다.
	var occupied: Array = [{}, {}]   # occupied[team][Vector2i] = true
	for raw in units:
		var u := raw as EUnit
		(occupied[u.team] as Dictionary)[u.pilot.grid_pos] = true

	for raw in _bs.turrets:
		var t := raw as TurretData
		if t == null or not t.alive:
			continue
		if t.team == initiator_team:
			continue                 # 교전을 건 쪽의 포탑은 가담하지 않는다.
		if not (occupied[t.team] as Dictionary).has(t.grid_pos):
			continue
		var et := ETurret.new()
		et.data = t
		et.team = t.team
		et.atk = max(1, t.atk)
		turrets.append(et)
	# 자리는 `_place_from_grid` 가 준다 — 포탑도 파일럿과 같은 칸→무대 매핑을
	# 지난다. 가담 조건 자체가 "우리 편이 그 포탑 칸에 서 있다"이므로, 그 칸에
	# 그려 두면 포탑과 허깅하는 아군이 자연히 같은 자리에 선다.


static func _is_melee_role(role: int) -> bool:
	return role == GameEnums.Role.TANK \
			or role == GameEnums.Role.FIGHTER \
			or role == GameEnums.Role.ASSASSIN


# ─── 메인 스텝 ───────────────────────────────────────────────────────────────
# 무대에는 언제나 한 명만 나와 있다. 나머지는 넉백 잔차만 추스르고, 연출
# 타이머(피격 플래시 / 공격 모션)만 흐른다.
func step(dt: float) -> void:
	if finished:
		return
	elapsed += dt
	_tick_passive(dt)
	_update_projectiles(dt)

	match flow:
		Flow.ROUND_START, Flow.ACTOR_GAP:
			_gap_left -= dt
			if _gap_left <= 0.0:
				_advance_order()
		Flow.ACTING:
			_tick_actor(dt)

	# 겹침 정리는 **한 프레임의 맨 끝**이다 — 접근 이동(`_tick_actor`)보다 뒤라야
	# 그 프레임에 실제로 그려지는 자리가 정리된 자리가 된다.
	_separate_units(SEPARATE_ITERS_TICK)


# 종료 판정이 난 뒤의 유예(EngagePhaseManager.END_HOLD_SEC) 동안 굴리는 스텝.
# 전투는 완전히 멈춘 상태에서 날아가던 투사체를 착탄시키고 피격 플래시 /
# 공격 모션 / 넉백만 마저 감쇠시킨다. `round_index` 는 건드리지 않으므로
# 대시보드에 찍히는 라운드 수는 실제로 싸운 라운드 수 그대로다.
func step_afterglow(dt: float) -> void:
	_tick_passive(dt)
	for raw in turrets:
		var t := raw as ETurret
		t.fire_t = max(0.0, t.fire_t - dt)
	_update_projectiles(dt)
	_separate_units(SEPARATE_ITERS_TICK)


## 발밑 타원(= 화면의 바닥 원)이 서로 파고들지 않도록 밀어낸다. 위 "바닥 마커
## 충돌" 절이 판정 공간을, 이 함수가 이완을 맡는다.
##
## **앵커도 같이 민다.** 앵커를 제자리에 두면 IDLE 의 복원 드리프트
## (`move_speed × SETTLE_SPEED_MULT`)가 밀어낸 만큼을 곧장 되돌려, 겹친 두
## 유닛이 밀고 당기며 그 자리에서 떤다 — `_apply_knockback` 이 앵커를 함께
## 옮기는 것과 같은 이유다. 이 모듈에는 원위치 복귀가 없고, **밀려난 자리가
## 곧 새 자리**다.
##
## **시신은 밀리지 않는다.** 쓰러진 자리에 그대로 남고 산 유닛만 그 밖으로
## 밀려난다(시신도 바닥 원을 그대로 갖고 있으므로 판정에서 빼면 산 유닛이
## 시신 위에 겹쳐 선다). 둘 다 시신이면 아무 일도 하지 않는다.
##
## 이완은 **한 쌍씩 즉시 반영**하는 가우스-자이델이라 벽(`_clamp_to_ground`)에
## 몰린 유닛이 못 밀린 만큼을 다음 쌍이 이어받는다.
func _separate_units(iters: int) -> void:
	var n: int = units.size()
	if n < 2:
		return
	var min_d: float = FOOT_RX * 2.0
	for _pass in iters:
		var moved: bool = false
		for i in range(n - 1):
			var a := units[i] as EUnit
			for j in range(i + 1, n):
				var b := units[j] as EUnit
				var a_live: bool = a.is_active()
				var b_live: bool = b.is_active()
				if not a_live and not b_live:
					continue
				# 타원 → 원. y 만 늘리면 두 마커가 같은 반지름의 원이 된다.
				var d := Vector2(b.pos.x - a.pos.x,
						(b.pos.y - a.pos.y) * FOOT_ASPECT)
				var dist: float = d.length()
				if dist >= min_d:
					continue
				var dir: Vector2
				if dist < 0.001:
					# 정확히 같은 자리 — 밀어낼 방향이 없으므로 팀으로 가른다
					# (`_seat_cell` 의 "팀0 은 왼쪽"과 같은 규칙).
					dir = Vector2(-1.0 if a.team == 0 else 1.0, 0.0)
				else:
					dir = d / dist
				# 한쪽이 시신이면 산 쪽이 겹친 양을 혼자 진다.
				var share_a: float = 0.5
				if not a_live:
					share_a = 0.0
				elif not b_live:
					share_a = 1.0
				var push: float = min_d - dist
				var off := Vector2(dir.x, dir.y / FOOT_ASPECT) * push
				_shift_unit(a, -off * share_a)
				_shift_unit(b, off * (1.0 - share_a))
				moved = true
		if not moved:
			return


## 유닛 하나를 밀되 앵커를 **실제로 밀린 만큼** 함께 옮긴다 —
## `_clamp_to_ground` 가 벽에서 잘라 낸 몫까지 앵커에 반영해야 벽에 붙은 유닛의
## 앵커가 바닥면 밖으로 새지 않는다.
func _shift_unit(u: EUnit, off: Vector2) -> void:
	if off.length_squared() < 0.000001:
		return
	var before: Vector2 = u.pos
	u.pos = _clamp_to_ground(u.pos + off)
	u.anchor_pos = _clamp_to_ground(u.anchor_pos + (u.pos - before))


## 차례와 무관하게 매 프레임 흐르는 것들 — 연출 타이머, 넉백, 앵커 잔차 복원.
func _tick_passive(dt: float) -> void:
	for raw in units:
		var u := raw as EUnit
		u.hit_flash = max(0.0, u.hit_flash - dt)
		u.swing_t = max(0.0, u.swing_t - dt)
		if u.state == State.DEAD:
			continue
		if not u.pilot.alive:
			u.state = State.DEAD
			continue
		_apply_knockback(u, dt)
		if u.state == State.IDLE:
			_step_toward(u, u.anchor_pos, u.move_speed * SETTLE_SPEED_MULT, dt)
	for raw in turrets:
		var t := raw as ETurret
		t.fire_t = max(0.0, t.fire_t - dt)


## 다음 행동자에게 차례를 넘긴다. 죽은 행동자는 건너뛰고, 순서 끝에 닿으면
## 라운드를 하나 올려 **다시 시전자부터** 시작한다.
func _advance_order() -> void:
	if _check_end():
		return
	while true:
		_order_idx += 1
		if _order_idx >= _order.size():
			# 한 라운드 종료.
			if round_index >= total_rounds:
				# 기회주의자(파일럿 스킬) — 이 교전에서 처치를 낸 파일럿이
				# 그 스킬을 갖고 있으면 라운드가 한 번 늘어난다. 한 교전에
				# 한 번뿐이라 `_opportunist_used` 로 잠근다.
				var extra: int = 0
				if not _opportunist_used and _bs.skill != null:
					extra = _bs.skill.engage_bonus_rounds_from_kills()
				if extra > 0:
					_opportunist_used = true
					total_rounds += extra
				else:
					_finish()
					return
			round_index += 1
			_order_idx = -1
			current_actor = null
			flow = Flow.ROUND_START
			_gap_left = ROUND_GAP_SEC
			return
		var actor = _order[_order_idx]
		if not actor.is_active():
			continue
		if actor is ETurret:
			_begin_turret_turn(actor as ETurret)
			return
		var u := actor as EUnit
		# 기절([강타]) — 이번 차례를 통째로 건너뛰고 남은 라운드가 하나 준다.
		# 순서 배열에서 빼지는 않으므로 살아 있는 사람들의 상대 순서는 그대로다.
		if _bs.mech_skill != null and _bs.mech_skill.consume_stun_turn(u.pilot):
			popups.append({"pos": u.pos, "text": "기절",
					"color": Color(0.70, 0.85, 1.0)})
			continue
		var t := _pick_target(u)
		if t == null:
			continue                # 때릴 상대가 없다 — 이번 차례는 그냥 넘긴다.
		current_actor = u
		u.target = t
		u.state = State.ADVANCE
		u.act_t = 0.0
		flow = Flow.ACTING
		return


## 지금 나와 있는 행동자의 한 차례를 굴린다.
func _tick_actor(dt: float) -> void:
	if current_actor == null:
		_end_actor_turn()
		return
	if current_actor is ETurret:
		var t := current_actor as ETurret
		if t.fire_t <= 0.0:
			_end_actor_turn()
		return
	var u := current_actor as EUnit
	if u.state == State.DEAD:
		_end_actor_turn()
		return
	match u.state:
		State.ADVANCE:
			_tick_advance(u, dt)
		State.STRIKE:
			_tick_strike(u, dt)
		_:
			_end_actor_turn()


func _end_actor_turn() -> void:
	if current_actor is EUnit:
		_settle(current_actor as EUnit)
	current_actor = null
	if _check_end():
		return
	flow = Flow.ACTOR_GAP
	_gap_left = ACTOR_GAP_SEC


# 접근 — 사거리에 들 때까지 붙는다. 근접은 MELEE_REACH, 원거리는 최대 사거리의
# RANGED_APPROACH_RATIO(90%). 이미 그 안이면 곧장 공격한다.
func _tick_advance(u: EUnit, dt: float) -> void:
	u.act_t += dt
	if u.target == null or not u.target.is_active():
		u.target = _pick_target(u)
		if u.target == null:
			_end_actor_turn()
			return
	var to_target: Vector2 = u.target.pos - u.pos
	var dist: float = to_target.length()
	_face_toward(u, to_target)

	if dist <= u.strike_dist() + STRIKE_DIST_EPSILON:
		_resolve_attack(u, u.target)
		u.state = State.STRIKE
		u.act_t = 0.0
		return
	if u.act_t >= ADVANCE_MAX_SEC:
		_end_actor_turn()         # 교착 — 이번 차례는 접고 여기 눌러앉는다.
		return

	# 대상 바로 앞(사거리 끝)까지만 파고든다.
	var stop: Vector2 = u.target.pos - (to_target / max(0.001, dist)) * u.strike_dist()
	_step_toward(u, stop, u.move_speed, dt)


# 타격 모션 홀드 — 이 동안은 대상 앞에 멈춰 서 있는다. 홀드가 끝나도 원위치로
# 돌아가지 않는다.
func _tick_strike(u: EUnit, dt: float) -> void:
	u.act_t += dt
	var hold: float = STRIKE_HOLD_MELEE if u.is_melee else STRIKE_HOLD_RANGED
	if u.act_t >= hold:
		_end_actor_turn()


# 한 차례를 끝내고 **지금 서 있는 자리에 눌러앉는다**. 이 자리가 새 앵커이므로
# 다음 타겟 거리도, 넉백 복원 목표도 여기서 다시 잰다.
func _settle(u: EUnit) -> void:
	if u.state != State.DEAD:
		u.state = State.IDLE
	u.target = null
	u.act_t = 0.0
	u.anchor_pos = u.pos


# 종료는 두 가지뿐이다 — 라운드 소진과 한 쪽 전멸. 둘 다 그 프레임에 finished 가
# 서고, 대시보드는 매니저의 유예 시간만큼 늦게 뜬다.
func _check_end() -> bool:
	if finished:
		return true
	if active_count(0) == 0 or active_count(1) == 0:
		_finish()
		return true
	return false


func _finish() -> void:
	finished = true
	flow = Flow.DONE
	current_actor = null


func active_count(team: int) -> int:
	var n := 0
	for raw in units:
		var u := raw as EUnit
		if u.team == team and u.is_active():
			n += 1
	return n


func _step_toward(u: EUnit, to: Vector2, speed: float, dt: float) -> bool:
	var off: Vector2 = to - u.pos
	var d: float = off.length()
	if d <= HOME_EPSILON:
		u.pos = _clamp_to_ground(to)
		return true
	var step_len: float = speed * dt
	if step_len >= d:
		u.pos = _clamp_to_ground(to)
		return true
	u.pos = _clamp_to_ground(u.pos + off / d * step_len)
	return false


## 바라보는 방향을 갱신한다. 탑뷰라 방향은 **백터 통째**다 — 사이드뷰 시절의
## 좌우 부호 하나(`facing_x`)로는 위아래로 마주 선 둘을 구분할 수 없다.
func _face_toward(u: EUnit, dir: Vector2) -> void:
	if dir.length_squared() > 1.0:
		u.facing = dir.normalized()


# 넉백 속도를 적용하고 지수 감쇠시킨다. 상태와 무관하게 매 프레임 돈다.
#
# **밀려난 만큼 앵커도 같이 민다.** 앵커를 제자리에 두면 IDLE 의 복원 드리프트
# (`move_speed × SETTLE_SPEED_MULT`)가 넉백 초기 속도보다 빨라서 맞은 유닛이
# **맞은 그 프레임 안에** 앵커로 되돌아간다 — `_step_toward` 는 6px 안이면
# 목표로 스냅하므로 잔차조차 남지 않는다. 즉 넉백이 화면에 **전혀 보이지
# 않았다**. 앵커를 함께 옮기면 밀린 자리가 그대로 새 자리가 되고, 그래서
#   ① 넉백이 실제로 보이고,
#   ② 때린 쪽은 다음 차례에 그 거리를 다시 좁혀야 한다.
# ②가 없으면 근접은 첫 접근 이후 영원히 `MELEE_REACH` 에 붙어 선 채라
# `_tick_advance` 가 매번 같은 프레임에 STRIKE 로 넘어가 **공격 모션이 통째로
# 사라진다**. "밀려난 자리가 새 자리"는 `_settle()` 의 "공격을 끝낸 자리가 새
# 자리"와 같은 규칙이다 — 이 모듈에는 원위치 복귀가 없다.
func _apply_knockback(u: EUnit, dt: float) -> void:
	if u.knock_vel.length_squared() < 1.0:
		u.knock_vel = Vector2.ZERO
		return
	var before: Vector2 = u.pos
	u.pos = _clamp_to_ground(u.pos + u.knock_vel * dt)
	u.anchor_pos = _clamp_to_ground(u.anchor_pos + (u.pos - before))
	u.knock_vel = u.knock_vel.lerp(Vector2.ZERO, 1.0 - exp(-KNOCK_DAMP * dt))


# 타겟 선정 — 거리 기반이되 존재감이 높은 쪽을 선호하고(어그로 가중),
# 아군이 이미 때리고 있는 적과 빈사인 적에 가산점을 준다. 집중 사격 항목이
# 없으면 모두가 각자 제일 가까운 적만 때려서 딜이 흩어지고 처치가 나오지
# 않는다 — 실제 MOBA 교전의 포커스를 흉내 내는 부분.
#
# 턴제에서는 무대에 한 명만 나와 있으므로 "아군이 이미 물고 있는 적"은 이번
# 라운드에서 **아군이 마지막으로 노린 적**을 뜻한다(`_last_focus`). 그래서
# 라운드 안에서 딜이 한 명에게 모인다.
const FOCUS_BONUS: float = 0.78     # 같은 팀이 이미 노린 적에게 곱해지는 계수
const FOCUS_BONUS_FLOOR: float = 0.45
const LOW_HP_FOCUS: float = 0.6     # 빈사(35% 미만) 적 마무리 가중
## 암살자가 적 뒷줄(원거리)에 주는 가중. 낮을수록 더 집요하게 파고든다.
const DIVE_FOCUS: float = 0.40
## 약자 멸시의 개시 타격에 곱해지는 공격력 배율 (카드 문안의 "공격력 50%").
const CONTEMPT_DMG_MULT: float = 0.5

## 팀별 이번 라운드의 집중 대상 → 몇 명이 노렸는가. 라운드가 넘어가도 그대로
## 두는 이유는 집중 사격이 라운드 경계에서 끊기면 처치가 거의 나오지 않기
## 때문이다(실시간 시절에는 동시 행동이 이 역할을 했다).
var _focus_count: Dictionary = {}   # EUnit → int

## 기회주의자의 라운드 연장을 이 교전에서 이미 썼는가.
var _opportunist_used: bool = false

func _pick_target(u: EUnit) -> EUnit:
	# 원딜 사냥꾼(파일럿 스킬) — 아직 안 쓴 첫 공격은 적 원딜이 살아 있는 한
	# 반드시 그쪽으로 간다. 거리도 존재감도 보지 않는다.
	if u.skill_focus_role >= 0 and not u.skill_focus_used:
		for raw in units:
			var e := raw as EUnit
			if e.team != u.team and e.is_active() 					and e.pilot.role == u.skill_focus_role:
				_focus_count[e] = int(_focus_count.get(e, 0)) + 1
				return e
	var best: EUnit = null
	var best_score: float = INF
	for raw in units:
		var e := raw as EUnit
		if e.team == u.team or not e.is_active():
			continue
		var d: float = u.anchor_pos.distance_to(e.pos)
		var score: float
		if u.dives_backline:
			# 암살자는 존재감 어그로를 무시하고 **뒷줄을 노린다**. 이 분기가
			# 없으면 앞줄이 더 가깝고 존재감까지 두 배(4 vs 2)라 원거리 메크가
			# 교전 내내 단 한 대도 맞지 않는다 — 실측으로 확인된 구멍이다.
			score = d * (DIVE_FOCUS if not e.is_melee else 1.0)
		else:
			score = d / float(max(1, e.pilot.presence))
		if e.hp_ratio() < 0.35:
			score *= LOW_HP_FOCUS
		var n: int = int(_focus_count.get(e, 0))
		if n > 0:
			score *= maxf(FOCUS_BONUS_FLOOR, pow(FOCUS_BONUS, float(n)))
		if score < best_score:
			best_score = score
			best = e
	if best != null:
		_focus_count[best] = int(_focus_count.get(best, 0)) + 1
	return best


## 아직 살아 있는 적 유닛 전부. 전탄 발사가 한 차례에 훑는 명단이다.
func _living_enemies(u: EUnit) -> Array:
	var out: Array = []
	for raw in units:
		var e := raw as EUnit
		if e.team != u.team and e.is_active():
			out.append(e)
	return out


## 남은 체력이 가장 적은 적. 비율이 아니라 **절대값**이다 — 약자 멸시는
## "체력이 가장 적은 적"이라 적혀 있고, 비율로 읽으면 최대 체력이 큰 탱커가
## 반피만 되어도 표적이 되어 "약자"라는 말과 어긋난다.
func _weakest_enemy(u: EUnit) -> EUnit:
	var best: EUnit = null
	for raw in _living_enemies(u):
		var e := raw as EUnit
		if best == null or e.pilot.hp < best.pilot.hp:
			best = e
	return best


## 이 PilotData 를 들고 무대에 서 있는 유닛. 피해 계산이 팝업을 띄울 자리를
## 되찾을 때만 쓴다(`_apply_damage` 는 PilotData 만 들고 있다).
func _unit_for(p: PilotData) -> EUnit:
	for raw in units:
		var u := raw as EUnit
		if u.pilot == p:
			return u
	return null


# ─── 전투 해상도 ─────────────────────────────────────────────────────────────
# 데미지는 전장과 동일(명중 시 dmg = atk, 보호막부터 흡수)하지만 **명중률만은
# 전장과 별개**다 — `_hit_chance` 가 80~100% 구간으로 리맵한 확률을 준다.
func _resolve_attack(u: EUnit, target: EUnit) -> void:
	u.swing_t = 0.22
	var mech: MechSkillSystem = _bs.mech_skill
	# 전탄 발사(원딜 I) — 이 한 차례의 공격이 **적 전원**에게 간다. 대가는
	# 기체 공격력 절반이고 그건 데이터(mechs.csv atk 12)에 이미 들어가 있다.
	var victims: Array = [target]
	if mech != null and mech.engage_targets_all(u.pilot):
		var all_foes: Array = _living_enemies(u)
		if not all_foes.is_empty():
			victims = all_foes
	for raw in victims:
		_strike_one(u, raw as EUnit)


## 한 대상에게 들어가는 타격 한 번. `_resolve_attack` 이 대상 집합을 정하고
## 이 함수가 그 하나하나를 굴린다 — 전탄 발사는 같은 차례에 이 함수를 여러 번
## 부르는 것이고, 오버클럭은 같은 대상에게 한 번 더 부르는 것이다.
##
## `allow_extra` 가 false 면 오버클럭이 걸리지 않는다. 추가 공격이 다시 추가
## 공격을 굴리면 확률에 따라 한 차례가 무한히 늘어난다.
func _strike_one(u: EUnit, target: EUnit, allow_extra: bool = true,
		dmg_mult: float = 1.0) -> void:
	if target == null or not target.is_active():
		return
	if not u.is_melee:
		projectiles.append({
			"from": u.pos, "to": target.pos, "t": 0.0,
			"dur": max(0.05, u.pos.distance_to(target.pos) / PROJECTILE_SPEED),
			"team": u.team, "is_turret": false,
		})

	var a: PilotData = u.pilot
	var d: PilotData = target.pilot
	if randf() >= _hit_chance(a.engage_hit, d.engage_eva):
		popups.append({"pos": target.pos, "text": "MISS",
				"color": Color(0.85, 0.85, 0.85)})
		return

	# 파일럿 스킬의 피해 배율 — 불안정한 대포(양방향)와 원딜 사냥꾼의 첫 공격
	# 보너스. 전장과 같은 질의 함수를 쓰므로 두 무대의 규칙이 갈라지지 않는다.
	var raw_dmg: float = float(max(1, a.atk)) * dmg_mult
	if _bs.skill != null:
		raw_dmg *= _bs.skill.damage_out_mult(a) * _bs.skill.damage_in_mult(d)
	if u.skill_focus_role >= 0 and not u.skill_focus_used:
		if d.role == u.skill_focus_role and _bs.skill != null:
			raw_dmg *= _bs.skill.engage_focus_atk_mult(a)
		u.skill_focus_used = true
	var dealt := _apply_damage(d, maxi(1, roundi(raw_dmg)))
	target.hit_flash = KNOCK_FLASH_SEC
	_apply_knock(u.pos, target,
			KNOCK_IMPULSE_MELEE if u.is_melee else KNOCK_IMPULSE_RANGED)
	(stats[a] as Dictionary)["dealt"] = int(stats[a]["dealt"]) + dealt
	(stats[d] as Dictionary)["taken"] = int(stats[d]["taken"]) + dealt
	# 성장치(점수) — 준 피해와 처치는 전장과 같은 지점을 지난다. 피해는 곧장
	# 점수가 되는 대신 피해자의 장부에 쌓였다가 처치 시 어시스트로 정산된다.
	_bs.record_pilot_damage(a, d, dealt)
	# 메크 쪽 교전 피해 훅 — 영혼 수확(전사 L)과 고통과 쾌감(탱커 N)이 무대
	# 위에서도 걸린다. 전장·카드와 같은 함수를 지나므로 규칙이 갈라지지 않는다.
	var mech: MechSkillSystem = _bs.mech_skill
	if mech != null:
		mech.on_engage_damage(a, d, dealt)
		# 강타([강타] 카드) — 때린 쪽이 장전돼 있으면 맞은 적이 다음 차례를
		# 통째로 잃는다. 같은 적에게 두 번은 걸리지 않는다.
		if mech.try_stun(a, d):
			popups.append({"pos": target.pos, "text": "기절!",
					"color": Color(0.70, 0.85, 1.0)})
	if d.hp <= 0:
		_kill(target, a)
		(stats[a] as Dictionary)["kills"] = int(stats[a]["kills"]) + 1
		popups.append({"pos": target.pos, "text": "-%d  KO!" % dealt,
				"color": Color(1.0, 0.85, 0.30)})
	else:
		popups.append({"pos": target.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.45, 0.45)})
	# 오버클럭(암살 P) — 교전 피해 직후 굴린다. 성공하면 **같은 대상에게**
	# 한 번 더 때리고 충전 절반이 날아간다(소모는 질의 함수가 한다).
	if allow_extra and mech != null and target.is_active() \
			and mech.overclock_extra_attack(a):
		popups.append({"pos": u.pos, "text": "오버클럭",
				"color": Color(0.65, 0.95, 1.0)})
		_strike_one(u, target, false)


# 넉백 — 공격자로부터 **멀어지는 그 방향 그대로** 민다. 사이드뷰 시절에는
# 세로 성분을 `KNOCK_VERTICAL_SCALE` 로 눌러 거의 수평으로만 밀었는데(벨트에서
# 세로는 원근 표현일 뿐 전술적 의미가 없었다), 탑뷰에서는 세로도 실제 거리라
# 누르면 위아래로 선 두 사람 사이에서만 넉백이 사라진다.
func _apply_knock(from: Vector2, target: EUnit, impulse: float) -> void:
	var dir: Vector2 = target.pos - from
	if dir.length_squared() < 0.001:
		dir = Vector2(1.0 if target.team == 1 else -1.0, 0.0)
	target.knock_vel += dir.normalized() * impulse


# 교전 명중 확률. 공식 자체는 `PilotData.hit_chance` 가 소유하고(전장과
# 공유한다) 이 래퍼는 그것을 **교전 스탯으로** 부른다는 사실만 말한다.
static func _hit_chance(hit: int, evasion: int) -> float:
	return PilotData.hit_chance(hit, evasion)


func _apply_damage(d: PilotData, amount: int) -> int:
	var dmg := amount
	var absorbed := 0
	if d.shield > 0:
		absorbed = min(d.shield, dmg)
		d.shield -= absorbed
		dmg -= absorbed
	var hp_dmg := 0
	if dmg > 0:
		hp_dmg = min(dmg, d.hp)
		d.hp = max(0, d.hp - dmg)
	# 불굴(지원 V) — 이 교전에서 **팀 전원이 한 번씩**, 체력 1 아래로 내려가지
	# 않는다. 판정을 여기 두는 이유는 포탑 사격도 같은 함수를 지나기 때문이다 —
	# 파일럿 공격에만 걸면 포탑 한 방에 죽는 구멍이 남는다.
	if d.hp <= 0 and _bs.mech_skill != null \
			and _bs.mech_skill.last_stand_available(d):
		_bs.mech_skill.consume_last_stand(d)
		d.hp = 1
		hp_dmg = maxi(0, hp_dmg - 1)   # 실제로 깎인 만큼만 센다
		var u: EUnit = _unit_for(d)
		if u != null:
			popups.append({"pos": u.pos, "text": "불굴!",
					"color": Color(1.0, 0.92, 0.55)})
	return absorbed + hp_dmg


func _kill(target: EUnit, killer: PilotData) -> void:
	# 전장과 같은 사망 경로를 탄다 — 리스폰 턴 스케일링(`respawn_turns_now`)과
	# 성장치 정산이 아레나 처치에도 그대로 걸린다.
	_bs.mark_pilot_dead(target.pilot, killer)
	target.state = State.DEAD
	target.target = null
	target.knock_vel = Vector2.ZERO


# ─── 포탑 차례 ───────────────────────────────────────────────────────────────
# 전장에서는 포탑이 파일럿을 때리지 않지만, 교전에 가담한 포탑은 때린다.
# 사거리 제한은 없으므로 아레나에 적이 하나라도 살아 있으면 반드시 대상을 찾는다.
# 대상은 **포탑에서 가장 가까운 적** — 자기 진영 깊숙이 파고든 유닛이 먼저 맞는다.
func _begin_turret_turn(t: ETurret) -> void:
	var victim: EUnit = _turret_target(t)
	if victim == null:
		t.last_target = null
		_advance_order()          # 때릴 상대가 없으면 차례를 넘긴다.
		return
	current_actor = t
	flow = Flow.ACTING
	t.last_target = victim
	t.fire_t = TURRET_FIRE_HOLD
	projectiles.append({
		"from": t.pos, "to": victim.pos, "t": 0.0,
		"dur": max(0.05, t.pos.distance_to(victim.pos) / PROJECTILE_SPEED),
		"team": t.team, "is_turret": true,
	})
	# 포탑도 명중 판정을 굴린다 — hit 스탯이 없으므로 TURRET_HIT 를 쓴다.
	if randf() >= _hit_chance(TURRET_HIT, victim.pilot.engage_eva):
		popups.append({"pos": victim.pos, "text": "MISS",
				"color": Color(0.85, 0.85, 0.85)})
		return
	var dealt := _apply_damage(victim.pilot, t.atk)
	victim.hit_flash = KNOCK_FLASH_SEC
	_apply_knock(t.pos, victim, KNOCK_IMPULSE_RANGED)
	if stats.has(victim.pilot):
		(stats[victim.pilot] as Dictionary)["taken"] = \
				int(stats[victim.pilot]["taken"]) + dealt
	if victim.pilot.hp <= 0:
		# 포탑 처치는 어느 파일럿에게도 성장치가 귀속되지 않는다.
		_kill(victim, null)
		popups.append({"pos": victim.pos, "text": "-%d  포탑 처치" % dealt,
				"color": Color(1.0, 0.6, 0.25)})
	else:
		popups.append({"pos": victim.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.72, 0.30)})


func _turret_target(t: ETurret) -> EUnit:
	var best: EUnit = null
	var best_d: float = INF
	for raw in units:
		var u := raw as EUnit
		if u.team == t.team or not u.is_active():
			continue
		var d: float = u.pos.distance_to(t.pos)
		if d < best_d:
			best_d = d
			best = u
	return best


# ─── 보조 ────────────────────────────────────────────────────────────────────
func _update_projectiles(dt: float) -> void:
	var keep: Array = []
	for raw in projectiles:
		var p: Dictionary = raw
		p["t"] = float(p["t"]) + dt
		if float(p["t"]) < float(p["dur"]):
			keep.append(p)
	projectiles = keep


# 교전이 끝날 때까지 아무도 바닥면 밖으로 나갈 수 없다.
func _clamp_to_ground(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, UNIT_RADIUS, STAGE_W - UNIT_RADIUS),
		clampf(p.y, UNIT_RADIUS, STAGE_H - UNIT_RADIUS))


## 이 무대가 **바로 그 명단 · 그 라운드 수**로 세워졌는가.
##
## 개시 확인 화면(VS)이 미리 세운 무대를 그대로 써도 되는지를 `EngagePhaseManager._begin`
## 이 여기로 묻는다. 프롬프트를 띄우고도 교전이 안 열리는 경로(미참여 · 무혈
## 획득 알림)가 있어 지난 무대가 남을 수 있기 때문이고, 명단이 하나라도 다르면
## 그것은 **다른 교전**이다.
func matches(t0: Array, t1: Array, rounds: int) -> bool:
	if total_rounds != max(1, rounds):
		return false
	var want: Dictionary = {}
	for raw in t0 + t1:
		var p := raw as PilotData
		if p != null and p.alive:
			want[p] = true
	if want.size() != units.size():
		return false
	for raw in units:
		if not want.has((raw as EUnit).pilot):
			return false
	return true


## 지금 무대에 나와 있는 행동자의 표시 이름. 렌더러가 헤더에 쓴다.
func actor_label() -> String:
	if current_actor == null:
		return ""
	if current_actor is ETurret:
		var t := current_actor as ETurret
		return "포탑 T%d [%s]" % [t.data.tier, _bs.LANE_NAMES[t.data.lane]]
	return _bs.pilot_label((current_actor as EUnit).pilot)


func units_of(team: int) -> Array:
	var out: Array = []
	for raw in units:
		if (raw as EUnit).team == team:
			out.append(raw)
	return out
