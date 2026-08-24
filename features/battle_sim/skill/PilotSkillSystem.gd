class_name PilotSkillSystem
extends Node

# 파일럿 스킬 — 선수 한 명에게 붙는 고유 능력. 카드가 **메크와 파일럿이 나눠
# 주는 공용 자원**이라면, 스킬은 그 선수가 아니면 낼 수 없는 한 수다.
#
# 표는 `data/csv/pilot_skills.csv`(25행)이고 짝은 `players.csv` 의 `skill_id`
# 가 들고 있다. 스킬은 **라인에 묶여 있어** 같은 역할의 파일럿에게만 붙는다
# (탑=TANK / 미드=FIGHTER / 정글=ASSASSIN / 서포터=SUPPORT / 원딜=SNIPER).
# 25개뿐이라 40명 중 15명(모브)은 스킬이 없다 — 그쪽은 초상화도 실루엣이다.
#
# ─── 세 가지 타입 ────────────────────────────────────────────────────────────
#   • 쿨타임(`cooldown`) — 쓰면 `p1` 턴 뒤에 다시 쓸 수 있다.
#   • 충전식(`charge`)  — 정해진 사건마다 충전이 쌓이고(최대 `p2`), 활성화에
#                          `p1` 충전을 소모한다.
#   • 패시브(`passive`) — 누를 수 없다. 상시 적용되거나 특정 사건에 자동으로
#                          걸린다. 충전을 쌓는 패시브도 있는데(퍼포먼스 · 축적 ·
#                          신예 · 몰아치기 · 전리품 수집가) 그 충전은 활성화의
#                          연료가 아니라 **효과의 세기** 자체다.
#
# ─── 효과를 문법으로 만들지 않은 이유 ───────────────────────────────────────
# 카드는 `draw:2;discard:2` 처럼 절을 조합해 쓰지만, 스킬 25개는 전부 서로 다른
# 사건에 걸린다(포탑 파괴 · 오브젝트 승리 · 처치 관여 · 공격 카드 명중 · 상대
# 라이너와의 비교 …). 절 문법을 만들어 봐야 절이 25개 생길 뿐이라, 여기서는
# CSV 의 `key` 로 갈라 쓴다 — 한 스킬을 고치려면 그 `KEY_*` 상수를 grep 하면
# 그 스킬이 걸리는 자리가 전부 나온다.
#
# ─── 어디서 읽히는가 ─────────────────────────────────────────────────────────
# 패시브 보정은 이 모듈이 **질의 함수**로만 내보내고, 실제 계산은 원래 하던 곳이
# 그대로 한다(`BattleSim.refresh_growth_stats` / `add_score`,
# `SimulationCore.roll_hit` / `_pilot_hit_damage`, `TurnEngageSim`). 스킬이
# 스탯을 직접 밀면 성장 재계산 한 번에 지워지기 때문이다 — 카드의 일시 공격력이
# `PilotData.atk_buff` 로 따로 사는 것과 같은 이유다.

## 스킬 상태가 바뀌어 HUD 를 다시 그려야 할 때.
signal skill_state_changed

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── CSV `key` 값 ────────────────────────────────────────────────────────────
const KEY_ROAM            := "roam"              # 미드 · 쿨타임
const KEY_HOLD_POSITION   := "hold_position"     # 미드 · 쿨타임
const KEY_PERFORMANCE     := "performance"       # 미드 · 패시브(충전)
const KEY_OPPORTUNIST     := "opportunist"       # 미드 · 패시브
const KEY_ACCUMULATE      := "accumulate"        # 미드 · 패시브(충전)
const KEY_OPS_PREP        := "ops_prep"          # 서포터 · 쿨타임
const KEY_SCHEME          := "scheme"            # 서포터 · 쿨타임
const KEY_RECALL_ORDER    := "recall_order"      # 서포터 · 쿨타임
const KEY_VETERAN         := "veteran"           # 서포터 · 패시브
const KEY_DRAGON_BLESSING := "dragon_blessing"   # 서포터 · 충전식
const KEY_HUNT_REWARD     := "hunt_reward"       # 원딜 · 패시브
const KEY_UNSTABLE_CANNON := "unstable_cannon"   # 원딜 · 패시브
const KEY_BACKBONE        := "backbone"          # 원딜 · 패시브
const KEY_ROOKIE          := "rookie"            # 원딜 · 패시브(충전)
const KEY_SURGE           := "surge"             # 원딜 · 패시브(충전)
const KEY_ELATION         := "elation"           # 정글 · 충전식
const KEY_FIERCE_BATTLE   := "fierce_battle"     # 정글 · 쿨타임
const KEY_BATTLE_ORDER    := "battle_order"      # 정글 · 쿨타임
const KEY_PLUNDERER       := "plunderer"         # 정글 · 충전식
const KEY_LOOT_COLLECTOR  := "loot_collector"    # 정글 · 패시브(충전)
const KEY_SIEGE           := "siege"             # 탑 · 충전식
const KEY_VERSATILE       := "versatile"         # 탑 · 패시브
const KEY_ADC_HUNTER      := "adc_hunter"        # 탑 · 패시브
const KEY_AGGRESSIVE_PUSH := "aggressive_push"   # 탑 · 쿨타임
const KEY_RIVALRY         := "rivalry"           # 탑 · 패시브

const TYPE_COOLDOWN := "cooldown"
const TYPE_CHARGE   := "charge"
const TYPE_PASSIVE  := "passive"

# ─── 튜닝 상수 ───────────────────────────────────────────────────────────────
## 후반 분기를 타는 패시브(노련함 · 불안정한 대포 · 백본)가 강해지는 턴.
const LATE_GAME_TURN: int = 50
## 퍼포먼스 — 충전 1당 이 파일럿의 모든 능력치 배율 가산분.
const PERFORMANCE_PER_CHARGE: float = 0.02
## 퍼포먼스 — 전투 이탈(사망) 시 잃는 충전.
const PERFORMANCE_DEATH_LOSS: int = 10
## 축적 — 충전 1당 성장 적립 배율 가산분.
const ACCUMULATE_PER_CHARGE: float = 0.01
## 몰아치기 — 충전 1당 전장 명중률 배율 가산분.
const SURGE_HIT_PER_CHARGE: float = 0.05
## 전리품 수집가 — 처치 관여한 적 역할 하나당 공격력 배율 가산분.
const LOOT_ATK_PER_CHARGE: float = 0.06
## 전리품 수집가 — 다섯 역할을 다 모았을 때 얹히는 추가 공격력 배율.
const LOOT_ATK_FULL_BONUS: float = 0.10
## 사냥의 보상 — 처치 관여 시 붙는 성장 적립 가산분과 그 지속 턴.
const HUNT_REWARD_RATE: float = 0.25
const HUNT_REWARD_TURNS: int = 15
## 위치 고정 — 지속 턴 / 성장 적립 가산 / 라인전 배율 가산.
const HOLD_TURNS: int = 20
const HOLD_GROWTH_RATE: float = 0.20
const HOLD_LANE_STAT: float = -0.20
## 노련함 — 전·후반 명중 배율 가산분과 회피 배율 가산분.
const VETERAN_HIT_EARLY: float = 0.10
const VETERAN_HIT_LATE: float = 0.20
const VETERAN_EVASION: float = -0.05
## 불안정한 대포 — 전·후반 주고받는 피해 배율 가산분(양방향에 같은 값을 쓴다).
const CANNON_EARLY: float = 0.10
const CANNON_LATE: float = 0.20
## 백본 — 후반 라인전 배율 가산분.
const BACKBONE_LANE_STAT: float = 0.20
## 만능 — 체력형/공격형 각각의 배율 가산분.
const VERSATILE_MULT: float = 0.20
## 원딜 사냥꾼 — 적 원딜을 노릴 때의 공격력 배율 가산분.
const ADC_HUNTER_ATK: float = 0.20
## 경쟁 심리 — 세 비교 항목 각각의 가산분.
const RIVALRY_GROWTH: float = 0.10
const RIVALRY_ATK: float = 0.10
const RIVALRY_HP: float = 0.10
## 전투 명령 — 이번 작전 단계의 전투 개시 비용 감소량과 라운드 증감.
const BATTLE_ORDER_DISCOUNT: int = 3
const BATTLE_ORDER_ROUNDS: int = -1
## 공성전 — 다음 전투 개시 카드에 얹는 라운드.
const SIEGE_ROUNDS: int = 3
## 기회주의자 — 교전 중 처치가 그 교전에 얹는 라운드.
const OPPORTUNIST_ROUNDS: int = 1
## 용의 가호 — 활성화 시의 전략 점수와 드로우 수.
const BLESSING_STRATEGY: int = 3
const BLESSING_DRAW: int = 2

# ─── 스킬이 만들어 주는 카드 (cards.csv id) ──────────────────────────────────
# 전부 `pool = 0` 이라 스타터 덱에는 들어가지 않는다. 손패에 놓는 것들은
# `휘발성`이 붙어 **안 쓰고 버려지면 그대로 사라진다** — 스킬은 카드를 주는
# 것이지 덱을 불리는 것이 아니다.
const CARD_ENGAGE_START: int = 1     # 전투 개시  (격전)
const CARD_ADVANCE: int     = 11     # 전진       (공격적인 전진)
const CARD_ADRENALINE: int  = 18     # 아드레날린 (고양감)
const CARD_RECALL: int      = 21     # 복귀       (복귀 명령)
const CARD_STEAL: int       = 23     # 약탈       (약탈자)
const CARD_HOT_HAND: int    = 34     # 핫핸드     (신예 — 덱에 생성)
const CARD_MOVE: int        = 35     # 이동       (배회)

## 배회가 값을 깎을 "이동 카드"의 판정 — effect chain 에 이 절이 있는 카드.
const MOVE_CLAUSE: String = "move"
## 격전이 덱에서 찾을 "전투 개시 카드"의 판정.
const ENGAGE_CLAUSE: String = "engage"

# ─── 상태 ────────────────────────────────────────────────────────────────────
# PilotData → {
#   def:          Dictionary,   # pilot_skills 행
#   charge:       int,
#   ready_turn:   int,          # 쿨타임: 이 턴부터 다시 쓸 수 있다
#   killed_roles: Dictionary,   # 전리품 수집가 — 처치 관여한 적 역할 집합
#   farm_until:   int,          # 사냥의 보상 만료 턴 (-1 = 없음)
#   hold_until:   int,          # 위치 고정 만료 턴 (-1 = 없음)
# }
var states: Dictionary = {}

# 팀 단위로 붙는 한시 효과. 인덱스는 팀 번호(0 / 1)다.
## 전투 명령 — 이번 작전 단계 동안 교전 라운드에 얹히는 값(음수).
var _phase_round_delta: Array[int] = [0, 0]
## 공성전 — **다음 한 장**의 전투 개시 카드에만 얹히는 라운드. 쓰면 0 이 된다.
var _next_engage_bonus: Array[int] = [0, 0]
## 기회주의자 — 지금 도는 교전에서 처치를 낸 파일럿들(PilotData → true).
var _engage_killers: Dictionary = {}


# ─── 수명 ────────────────────────────────────────────────────────────────────

## 새 매치의 스킬 상태를 세운다. `BattleSim` 이 파일럿을 스폰한 **뒤** 부른다 —
## 짝을 `player_data_for` 로 찾으므로 로스터가 이미 붙어 있어야 한다.
func init_for_match() -> void:
	states.clear()
	_phase_round_delta = [0, 0]
	_next_engage_bonus = [0, 0]
	_engage_killers.clear()
	var gm: Node = _bs.gm
	if gm == null:
		return
	for raw in _bs.pilots:
		var p := raw as PilotData
		var pd: PlayerData = _bs.player_data_for(p)
		if pd == null or pd.skill_id < 0:
			continue
		var sdef: Dictionary = gm.skill_def(pd.skill_id)
		if sdef.is_empty():
			continue
		var st: Dictionary = {
			"def": sdef, "charge": 0, "ready_turn": 0,
			"killed_roles": {}, "farm_until": -1, "hold_until": -1,
		}
		# 공성전만 충전이 찬 채 시작한다(CSV 설명문의 "충전 5로 시작").
		if String(sdef["key"]) == KEY_SIEGE:
			st["charge"] = int(sdef["p2"])
		states[p] = st
	_apply_match_start_passives()
	skill_state_changed.emit()


## 게임 시작에 한 번만 도는 패시브. 지금은 백본 하나뿐이다 — 그 선수의 카드를
## 통째로 버린 더미로 보내 초반을 그 파일럿의 카드 없이 시작한다. 덱에서 빼는
## 것이 아니라 **순서를 뒤로 미는** 것이라 소멸이 아니라 discard 다(리셔플에
## 다시 섞여 들어온다).
func _apply_match_start_passives() -> void:
	for raw in states.keys():
		var p := raw as PilotData
		if _key_of(p) != KEY_BACKBONE:
			continue
		var is_player: bool = p.team == 0
		var deck: Array    = _bs.player_deck    if is_player else _bs.ai_deck
		var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
		var moved: int = 0
		for cd_raw in deck.duplicate():
			var cd := cd_raw as CardData
			if cd.owner_pilot == p:
				deck.erase(cd)
				discard.append(cd)
				moved += 1
		if moved > 0 and _bs.card_phase != null:
			_bs.card_phase.update_deck_discard_labels()
			_log(p, "게임 시작 — 카드 %d장을 버린 더미로" % moved)


# ─── 조회 ────────────────────────────────────────────────────────────────────

func has_skill(p: PilotData) -> bool:
	return states.has(p)


func def_for(p: PilotData) -> Dictionary:
	var st: Dictionary = states.get(p, {})
	return st.get("def", {}) if not st.is_empty() else {}


func skill_name(p: PilotData) -> String:
	return String(def_for(p).get("name", ""))


func skill_type(p: PilotData) -> String:
	return String(def_for(p).get("type", ""))


func skill_description(p: PilotData) -> String:
	return String(def_for(p).get("description", ""))


func skill_keyword(p: PilotData) -> String:
	return String(def_for(p).get("keyword", ""))


func _key_of(p: PilotData) -> String:
	return String(def_for(p).get("key", ""))


func charge_of(p: PilotData) -> int:
	var st: Dictionary = states.get(p, {})
	return int(st.get("charge", 0)) if not st.is_empty() else 0


func max_charge_of(p: PilotData) -> int:
	return int(def_for(p).get("p2", 0))


## 쿨타임이 끝나기까지 남은 턴 수. 쿨타임 스킬이 아니거나 이미 준비됐으면 0.
func cooldown_left(p: PilotData) -> int:
	var st: Dictionary = states.get(p, {})
	if st.is_empty() or skill_type(p) != TYPE_COOLDOWN:
		return 0
	return maxi(0, int(st["ready_turn"]) - _bs.turn_count)


## 지금 이 스킬을 **누를 수 있는가**(자원 기준). 화면 게이트(작전 단계인가,
## 내 팀인가)는 `can_activate` 가 따로 본다.
func is_ready(p: PilotData) -> bool:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return false
	match skill_type(p):
		TYPE_COOLDOWN: return cooldown_left(p) <= 0
		TYPE_CHARGE:   return int(st["charge"]) >= int(st["def"]["p1"])
		_:             return false


## 초상화 밝기 와이프의 채움 비율 0..1 — "얼마나 준비됐는가".
##
## **패시브는 언제나 1.0** 이다: 누를 수 없는 대신 상시 적용이라 "아직 안 됐다"가
## 성립하지 않는다. 충전을 쌓는 패시브의 충전 수는 초상화 옆 숫자가 말한다.
func progress(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 1.0
	match skill_type(p):
		TYPE_COOLDOWN:
			var total: int = maxi(1, int(st["def"]["p1"]))
			return clampf(1.0 - float(cooldown_left(p)) / float(total), 0.0, 1.0)
		TYPE_CHARGE:
			var need: int = maxi(1, int(st["def"]["p1"]))
			return clampf(float(st["charge"]) / float(need), 0.0, 1.0)
		_:
			return 1.0


## 초상화 오른쪽에 찍히는 숫자. 빈 문자열이면 아무것도 안 찍는다.
## 쿨타임은 **남은 턴**(준비되면 빈칸), 충전은 **충전 수**다.
func badge_text(p: PilotData) -> String:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return ""
	match skill_type(p):
		TYPE_COOLDOWN:
			var left: int = cooldown_left(p)
			return "" if left <= 0 else str(left)
		TYPE_CHARGE:
			return str(int(st["charge"]))
		_:
			# 충전을 쌓는 패시브만 숫자를 갖는다(퍼포먼스 · 축적 · 신예 …).
			return str(int(st["charge"])) if int(st["def"]["p2"]) > 0 else ""


## 상세 패널이 쓰는 한 줄 상태 문구.
func status_text(p: PilotData) -> String:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return "스킬 없음"
	var d: Dictionary = st["def"]
	match skill_type(p):
		TYPE_COOLDOWN:
			var left: int = cooldown_left(p)
			return "사용 가능" if left <= 0 else "재사용까지 %d턴" % left
		TYPE_CHARGE:
			return "충전 %d / %d · 사용에 %d 충전" % [
					int(st["charge"]), int(d["p2"]), int(d["p1"])]
		_:
			if int(d["p2"]) > 0:
				return "패시브 · 충전 %d / %d" % [int(st["charge"]), int(d["p2"])]
			return "패시브 · 상시 적용"


## 지금 이 파일럿의 스킬을 실제로 누를 수 있는가 — 화면 게이트까지 포함한다.
## **아군 · 자기 작전 단계 · 살아 있음** 셋이 전부 참이어야 한다. AI 팀은
## 패시브와 충전만 굴러가고 활성화는 하지 않는다(첫 버전의 의도된 한계).
func can_activate(p: PilotData) -> bool:
	if p == null or not p.alive or p.team != 0:
		return false
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return false
	if _bs.card_phase != null and _bs.card_phase.is_ai_turn_active():
		return false
	if skill_type(p) == TYPE_PASSIVE:
		return false
	return is_ready(p)


# ─── 활성화 ──────────────────────────────────────────────────────────────────

## 스킬을 발동한다. 성공하면 사람이 읽을 결과 문구, 못 쓰면 빈 문자열.
##
## 자원 소모(쿨타임 시작 / 충전 차감)는 **효과가 성공했을 때만** 한다 — 손패가
## 꽉 찼거나 카드 표가 비어 아무 일도 못 일어난 발동으로 쿨타임을 먹으면
## 플레이어가 잃은 것을 되돌릴 방법이 없다.
func activate(p: PilotData) -> String:
	if not can_activate(p):
		return ""
	var msg: String = _run_activation(p)
	if msg.is_empty():
		return ""
	var st: Dictionary = states[p]
	match skill_type(p):
		TYPE_COOLDOWN:
			st["ready_turn"] = _bs.turn_count + int(st["def"]["p1"])
		TYPE_CHARGE:
			st["charge"] = maxi(0, int(st["charge"]) - int(st["def"]["p1"]))
	_log(p, msg)
	skill_state_changed.emit()
	if _bs.hud != null:
		_bs.hud.update_hud()
	return msg


func _run_activation(p: PilotData) -> String:
	match _key_of(p):
		KEY_ROAM:            return _act_roam(p)
		KEY_HOLD_POSITION:   return _act_hold_position(p)
		KEY_OPS_PREP:        return _act_ops_prep(p)
		KEY_SCHEME:          return _act_scheme(p)
		KEY_RECALL_ORDER:    return _grant_volatile(p, CARD_RECALL, "복귀")
		KEY_DRAGON_BLESSING: return _act_dragon_blessing(p)
		KEY_ELATION:         return _grant_volatile(p, CARD_ADRENALINE, "아드레날린")
		KEY_FIERCE_BATTLE:   return _act_fierce_battle(p)
		KEY_BATTLE_ORDER:    return _act_battle_order(p)
		KEY_PLUNDERER:       return _grant_volatile(p, CARD_STEAL, "약탈")
		KEY_SIEGE:           return _act_siege(p)
		KEY_AGGRESSIVE_PUSH: return _grant_volatile(p, CARD_ADVANCE, "전진")
		_:                   return ""


## 배회 — 손패의 가장 싼 이동 카드를 0코로 만든다. 이동 카드가 없으면 대신
## 휘발성 [이동] 한 장을 손에 쥐여 준다. 어느 쪽이든 "지금 움직일 수 있게 된다"가
## 스킬의 값이고, 미드가 로밍을 나가는 유일한 수단이다.
func _act_roam(p: PilotData) -> String:
	var cheapest: CardData = null
	for raw in _bs.player_hand:
		var cd := raw as CardData
		if not _has_clause(cd, MOVE_CLAUSE):
			continue
		if cheapest == null or cd.cost < cheapest.cost:
			cheapest = cd
	if cheapest == null:
		return _grant_volatile(p, CARD_MOVE, "이동")
	if cheapest.cost <= 0:
		# 이미 0코라 깎을 것이 없다 — 쿨타임만 먹고 끝나지 않도록 카드를 준다.
		return _grant_volatile(p, CARD_MOVE, "이동")
	cheapest.cost = 0
	_refresh_hand()
	return "[%s] 비용 0" % cheapest.card_name


## 위치 고정 — 20턴 동안 성장 적립이 오르고 라인전이 내려가며, 그동안 이 파일럿은
## 이동 카드의 대상이 될 수 없고 오브젝트에도 못 낀다. 라인에 눌러앉아 파밍만
## 하겠다는 선언이다.
func _act_hold_position(p: PilotData) -> String:
	states[p]["hold_until"] = _bs.turn_count + HOLD_TURNS
	_bs.refresh_growth_stats(p)
	return "%d턴 간 위치 고정" % HOLD_TURNS


## 작전 준비 — 이번 작전 단계의 모든 카드 비용 -1. `phase_cost_inc` 는
## `BattleSim.effective_cost_for` 가 읽는 단계 세금이라 음수로 밀면 그대로
## 할인이 된다(0 미만으로는 안 내려간다 — 그쪽도 같은 함수가 막는다).
func _act_ops_prep(p: PilotData) -> String:
	_bs.phase_cost_inc_p -= 1
	_refresh_hand()
	return "이번 작전 단계 모든 카드 비용 −1"


## 계략 — 손패 한 장에 보존을 건다. 고르는 화면은 계획 중시(`preserve:N`)와
## 같은 그리드를 그대로 쓴다. **취소는 아무것도 소모하지 않는다** — 오버레이가
## 취소로 닫히면 `activate` 가 빈 문자열을 받아 쿨타임도 안 돈다.
func _act_scheme(p: PilotData) -> String:
	if _bs.player_hand.is_empty():
		return ""
	if _bs.card_select_overlay == null:
		return ""
	_bs.card_select_overlay.start_preserve(1,
			_on_scheme_picked, _on_scheme_cancelled)
	return "손패 1장에 보존"


func _on_scheme_picked(picks: Array) -> void:
	for raw in picks:
		var cd := raw as CardData
		if not _bs.preserved_cards_p.has(cd):
			_bs.preserved_cards_p.append(cd)
	_refresh_hand()


func _on_scheme_cancelled() -> void:
	# 고르지 않고 닫았다 — 보존도 안 걸리고 쿨타임도 이미 돌았다. 오버레이를
	# 여는 시점에 쿨타임을 먹이지 않으려면 여기서 되돌려야 하는데, 그러려면
	# 어느 파일럿이 열었는지를 들고 있어야 한다. 지금은 취소해도 스킬은
	# 소모된 것으로 둔다 — 그리드가 열린 순간 이미 "썼다"이기 때문이다.
	_refresh_hand()


## 용의 가호 — 충전을 태워 전략 점수와 드로우로 바꾼다.
func _act_dragon_blessing(p: PilotData) -> String:
	_bs.player_cost += BLESSING_STRATEGY
	var drew: int = 0
	if _bs.card_phase != null:
		for _i in BLESSING_DRAW:
			var cd := _bs.card_phase.draw_card(true)
			if cd == null:
				break
			_bs.card_phase.spawn_card_node(cd)
			drew += 1
		_refresh_hand()
	return "전략 점수 +%d · 드로우 %d" % [BLESSING_STRATEGY, drew]


## 격전 — 덱에서 **자기 것인** 전투 개시 카드를 한 장 끌어온다. 없으면 대신
## 휘발성 [전투 개시] 를 만들어 준다. 정글러가 원할 때 싸움을 열 수 있게 하는
## 것이 요점이라, 덱 사정 때문에 아무 일도 안 일어나서는 안 된다.
func _act_fierce_battle(p: PilotData) -> String:
	var found: CardData = null
	for raw in _bs.player_deck:
		var cd := raw as CardData
		if cd.owner_pilot == p and _has_clause(cd, ENGAGE_CLAUSE):
			found = cd
			break
	if found == null:
		return _grant_volatile(p, CARD_ENGAGE_START, "전투 개시")
	_bs.player_deck.erase(found)
	_bs.player_hand.append(found)
	if _bs.card_phase != null:
		_bs.card_phase.spawn_card_node(found)
		_bs.card_phase.update_deck_discard_labels()
	_refresh_hand()
	return "[%s] 드로우" % found.card_name


## 전투 명령 — 이번 작전 단계 동안 전투 개시 카드가 싸지고 라운드가 하나 줄어든다.
## 비용 쪽은 카드가 이미 쓰는 `engage_discount` 슬롯을 그대로 밀고(전투 준비와
## 같은 자리라 합산된다), 라운드 쪽만 이 모듈이 들고 있다.
func _act_battle_order(p: PilotData) -> String:
	_bs.engage_discount_p += BATTLE_ORDER_DISCOUNT
	_phase_round_delta[0] += BATTLE_ORDER_ROUNDS
	_refresh_hand()
	return "전투 개시 비용 −%d · 라운드 %+d" % [
			BATTLE_ORDER_DISCOUNT, BATTLE_ORDER_ROUNDS]


## 공성전 — 충전 다섯을 태워 **다음 한 장**의 전투 개시 카드에 라운드를 얹는다.
## 단계가 아니라 카드 한 장에 붙으므로 언제 쓸지가 곧 선택이다.
func _act_siege(p: PilotData) -> String:
	_next_engage_bonus[0] += SIEGE_ROUNDS
	return "다음 전투 개시 라운드 +%d" % SIEGE_ROUNDS


## 스킬이 만들어 주는 손패 카드 한 장. `휘발성`을 덧붙여 안 쓰고 버려지면
## 사라지게 한다 — 그러지 않으면 스킬이 매번 덱을 한 장씩 불린다.
func _grant_volatile(p: PilotData, card_id: int, label: String) -> String:
	if _bs.card_phase == null:
		return ""
	var cd: CardData = _bs.card_phase.make_objective_card(card_id)
	if cd == null:
		return ""
	cd.owner_pilot = p
	cd.keyword = _with_keywords(cd.keyword,
			[CardData.KW_EXHAUST, CardData.KW_VOLATILE])
	_bs.player_hand.append(cd)
	_bs.card_phase.spawn_card_node(cd)
	_refresh_hand()
	return "[%s] 생성 (소멸 · 휘발성)" % label


## `raw` 에 없는 키워드만 골라 `|` 로 이어 붙인다.
func _with_keywords(raw: String, extra: Array) -> String:
	var parts: Array = []
	for chunk in raw.split("|", false):
		var s: String = (chunk as String).strip_edges()
		if not s.is_empty() and not parts.has(s):
			parts.append(s)
	for kw_raw in extra:
		var kw: String = String(kw_raw)
		if not parts.has(kw):
			parts.append(kw)
	return "|".join(parts)


func _has_clause(cd: CardData, clause: String) -> bool:
	if cd == null:
		return false
	for raw in cd.effect.split(";", false):
		var head: String = (raw as String).strip_edges().split("|", false)[0]
		var colon: int = head.find(":")
		if (head.substr(0, colon) if colon >= 0 else head) == clause:
			return true
	return false


func _refresh_hand() -> void:
	if _bs.card_phase == null:
		return
	_bs.card_phase.relayout_hand(_bs.player_card_nodes)
	_bs.card_phase.highlight_affordable_cards()


func _log(p: PilotData, msg: String) -> void:
	if _bs.blog != null:
		_bs.blog.log_event("SKILL", "%-4s [%s] %s" % [
				_bs.pilot_label(p), skill_name(p), msg])


# ─── 사건 훅 ─────────────────────────────────────────────────────────────────
# 전부 "그 일이 실제로 일어나는 한 곳"에서 불린다. 여기 없는 스킬은 그 사건에
# 관심이 없다는 뜻이다.

## 매 턴 한 번. `SimulationCore.simulate_turn` 말미가 부른다.
func on_turn_advanced() -> void:
	if states.is_empty():
		return
	var dirty: bool = false
	for raw in states.keys():
		var p := raw as PilotData
		var st: Dictionary = states[p]
		match _key_of(p):
			# 축적 / 신예 — 살아 있든 죽어 있든 매 턴 찬다. 신예는 만충에서
			# [핫핸드] 를 덱에 낳고 충전을 비워 다시 쌓기 시작한다.
			KEY_ACCUMULATE, KEY_ROOKIE:
				var cap: int = int(st["def"]["p2"])
				if int(st["charge"]) < cap:
					st["charge"] = int(st["charge"]) + 1
					dirty = true
					if _key_of(p) == KEY_ACCUMULATE:
						pass   # 성장 적립은 add_score 가 그때그때 읽는다
				if _key_of(p) == KEY_ROOKIE and int(st["charge"]) >= cap:
					_spawn_hot_hand(p)
					st["charge"] = 0
		# 만료형 두 개를 걷는다.
		if int(st["farm_until"]) >= 0 and _bs.turn_count >= int(st["farm_until"]):
			st["farm_until"] = -1
			dirty = true
		if int(st["hold_until"]) >= 0 and _bs.turn_count >= int(st["hold_until"]):
			st["hold_until"] = -1
			_bs.refresh_growth_stats(p)
			dirty = true
	# 후반 분기를 타는 패시브들은 그 경계 턴에 스탯이 실제로 바뀐다.
	if _bs.turn_count == LATE_GAME_TURN:
		for raw in states.keys():
			_bs.refresh_growth_stats(raw as PilotData)
		dirty = true
	if dirty:
		skill_state_changed.emit()


## 신예의 [핫핸드] — 손패가 아니라 **덱**에 섞어 넣는다. 손에 바로 꽂으면 매
## 15턴마다 손패가 한 장씩 밀려 상한 정리를 유발한다.
func _spawn_hot_hand(p: PilotData) -> void:
	if _bs.card_phase == null:
		return
	var cd: CardData = _bs.card_phase.make_objective_card(CARD_HOT_HAND)
	if cd == null:
		return
	cd.owner_pilot = p
	var deck: Array = _bs.player_deck if p.team == 0 else _bs.ai_deck
	deck.append(cd)
	deck.shuffle()
	_bs.card_phase.update_deck_discard_labels()
	_log(p, "[핫핸드] 를 덱에 생성")


## 카드 한 장이 실제로 나갔을 때. 퍼포먼스가 이 박자로 충전한다.
func on_card_played(cd: CardData, _is_player: bool) -> void:
	if cd == null or cd.owner_pilot == null:
		return
	var p: PilotData = cd.owner_pilot
	if _key_of(p) != KEY_PERFORMANCE:
		return
	var st: Dictionary = states[p]
	var cap: int = int(st["def"]["p2"])
	if int(st["charge"]) >= cap:
		return
	st["charge"] = int(st["charge"]) + 1
	_bs.refresh_growth_stats(p)
	skill_state_changed.emit()


## 공격 카드가 명중했을 때. 몰아치기가 이 박자로 충전한다.
func on_attack_hit(caster: PilotData) -> void:
	if caster == null or _key_of(caster) != KEY_SURGE:
		return
	var st: Dictionary = states[caster]
	var cap: int = int(st["def"]["p2"])
	if int(st["charge"]) < cap:
		st["charge"] = int(st["charge"]) + 1
		skill_state_changed.emit()


## 작전 단계가 닫힐 때. 몰아치기 충전이 여기서 비워지고, 전투 명령의 단계 효과도
## 함께 걷힌다.
func on_phase_end(is_player: bool) -> void:
	var team: int = 0 if is_player else 1
	_phase_round_delta[team] = 0
	for raw in states.keys():
		var p := raw as PilotData
		if p.team != team or _key_of(p) != KEY_SURGE:
			continue
		if int(states[p]["charge"]) != 0:
			states[p]["charge"] = 0
	skill_state_changed.emit()


## 처치 한 건. `BattleSim.mark_pilot_dead` 가 **현상금 정산보다 먼저** 부른다 —
## 어시스트 명단의 출처인 `victim.damage_credit` 이 그 정산에서 비워지기 때문이다
## (킬로그가 같은 이유로 같은 자리에 있다).
func on_kill(victim: PilotData, killer: PilotData) -> void:
	if victim == null:
		return
	# 처치 관여 = 막타 + 이번 생에 피해를 넣은 모든 적 파일럿.
	var involved: Dictionary = {}
	if killer != null and killer.team != victim.team:
		involved[killer] = true
	# **만료를 지난 피해는 관여가 아니다** — 현상금 배분과 킬로그가 읽는 그
	# 표(`BattleSim.live_damage_credit`)를 여기서도 그대로 읽는다.
	for raw in _bs.live_damage_credit(victim).keys():
		var a := raw as PilotData
		if a != null and a.team != victim.team:
			involved[a] = true
	for raw in involved.keys():
		var p := raw as PilotData
		if not states.has(p):
			continue
		var st: Dictionary = states[p]
		match _key_of(p):
			KEY_HUNT_REWARD:
				st["farm_until"] = _bs.turn_count + HUNT_REWARD_TURNS
			KEY_PLUNDERER:
				st["charge"] = mini(int(st["def"]["p2"]), int(st["charge"]) + 1)
			KEY_LOOT_COLLECTOR:
				var roles: Dictionary = st["killed_roles"]
				if not roles.has(victim.role) \
						and roles.size() < int(st["def"]["p2"]):
					roles[victim.role] = true
					st["charge"] = roles.size()
					_bs.refresh_growth_stats(p)
	# 기회주의자 — 교전이 도는 중의 처치만 라운드를 연장한다.
	if killer != null and _bs.engage_phase != null \
			and _bs.engage_phase.is_active():
		_engage_killers[killer] = true
	# 퍼포먼스 — 쓰러진 쪽이 충전을 잃는다.
	if states.has(victim) and _key_of(victim) == KEY_PERFORMANCE:
		var vs: Dictionary = states[victim]
		vs["charge"] = maxi(0, int(vs["charge"]) - PERFORMANCE_DEATH_LOSS)
		_bs.refresh_growth_stats(victim)
	# 신예 — 전투 이탈 시 충전 초기화.
	if states.has(victim) and _key_of(victim) == KEY_ROOKIE:
		states[victim]["charge"] = 0
	skill_state_changed.emit()


## 포탑 하나가 무너졌을 때. 공성전이 이 박자로 충전한다.
func on_turret_destroyed(killer: PilotData) -> void:
	if killer == null or _key_of(killer) != KEY_SIEGE:
		return
	var st: Dictionary = states[killer]
	st["charge"] = mini(int(st["def"]["p2"]), int(st["charge"]) + 1)
	skill_state_changed.emit()


## 용이 전장에 나타났을 때. 용의 가호가 이 박자로 충전한다.
func on_dragon_spawned() -> void:
	for raw in states.keys():
		var p := raw as PilotData
		if _key_of(p) != KEY_DRAGON_BLESSING:
			continue
		var st: Dictionary = states[p]
		st["charge"] = mini(int(st["def"]["p2"]), int(st["charge"]) + 1)
	skill_state_changed.emit()


## 오브젝트(전령 / 용) 한 건의 승자가 정해졌을 때. 고양감이 이 박자로 충전한다.
func on_objective_won(winner_team: int) -> void:
	for raw in states.keys():
		var p := raw as PilotData
		if p.team != winner_team or _key_of(p) != KEY_ELATION:
			continue
		var st: Dictionary = states[p]
		st["charge"] = mini(int(st["def"]["p2"]), int(st["charge"]) + 1)
	skill_state_changed.emit()


## 교전 무대가 열릴 때 / 닫힐 때 — 기회주의자의 처치 장부를 새로 연다.
func on_engage_started() -> void:
	_engage_killers.clear()


# ─── 패시브 질의 ─────────────────────────────────────────────────────────────
# 아래 함수들은 **읽기 전용**이다. 계산은 원래 하던 자리가 그대로 하고, 여기서는
# "그 자리에 얼마를 얹을 것인가"만 답한다.

func _late() -> bool:
	return _bs.turn_count >= LATE_GAME_TURN


## `BattleSim.add_score` 가 곱하는 적립 배율에 얹히는 가산분.
func growth_rate_add(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 0.0
	var add: float = 0.0
	match _key_of(p):
		KEY_ACCUMULATE:
			add += float(int(st["charge"])) * ACCUMULATE_PER_CHARGE
		KEY_HUNT_REWARD:
			if int(st["farm_until"]) >= 0:
				add += HUNT_REWARD_RATE
		KEY_HOLD_POSITION:
			if int(st["hold_until"]) >= 0:
				add += HOLD_GROWTH_RATE
		KEY_RIVALRY:
			if _rival_behind_score(p):
				add += RIVALRY_GROWTH
	return add


## `BattleSim.refresh_growth_stats` 가 `base_atk` 에 곱하는 배율.
func atk_mult(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 1.0
	var m: float = 1.0
	match _key_of(p):
		KEY_PERFORMANCE:
			m += float(int(st["charge"])) * PERFORMANCE_PER_CHARGE
		KEY_LOOT_COLLECTOR:
			var c: int = int(st["charge"])
			m += float(c) * LOOT_ATK_PER_CHARGE
			if c >= int(st["def"]["p2"]):
				m += LOOT_ATK_FULL_BONUS
		KEY_VERSATILE:
			if not _is_hp_archetype(p):
				m += VERSATILE_MULT
		KEY_RIVALRY:
			if _rival_behind_kills(p):
				m += RIVALRY_ATK
	return m


## `BattleSim.refresh_growth_stats` 가 `base_max_hp` 에 곱하는 배율.
func hp_mult(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 1.0
	var m: float = 1.0
	match _key_of(p):
		KEY_PERFORMANCE:
			m += float(int(st["charge"])) * PERFORMANCE_PER_CHARGE
		KEY_VERSATILE:
			if _is_hp_archetype(p):
				m += VERSATILE_MULT
		KEY_RIVALRY:
			if _rival_ahead_deaths(p):
				m += RIVALRY_HP
	return m


## `SimulationCore.roll_hit` 이 공격자의 `hit` 에 곱하는 배율.
func hit_mult(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 1.0
	var m: float = 1.0
	match _key_of(p):
		KEY_VETERAN:
			m += VETERAN_HIT_LATE if _late() else VETERAN_HIT_EARLY
		KEY_SURGE:
			m += float(int(st["charge"])) * SURGE_HIT_PER_CHARGE
		KEY_PERFORMANCE:
			m += float(int(st["charge"])) * PERFORMANCE_PER_CHARGE
	return m


## `SimulationCore.roll_hit` 이 방어자의 `evasion` 에 곱하는 배율.
func evasion_mult(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 1.0
	var m: float = 1.0
	match _key_of(p):
		KEY_VETERAN:
			m += VETERAN_EVASION
		KEY_PERFORMANCE:
			m += float(int(st["charge"])) * PERFORMANCE_PER_CHARGE
	return m


## 이 파일럿이 **주는** 피해에 곱하는 배율.
func damage_out_mult(p: PilotData) -> float:
	if _key_of(p) != KEY_UNSTABLE_CANNON:
		return 1.0
	return 1.0 + (CANNON_LATE if _late() else CANNON_EARLY)


## 이 파일럿이 **받는** 피해에 곱하는 배율.
func damage_in_mult(p: PilotData) -> float:
	if _key_of(p) != KEY_UNSTABLE_CANNON:
		return 1.0
	return 1.0 + (CANNON_LATE if _late() else CANNON_EARLY)


## `SimulationCore.lane_adjusted` 의 라인전 배율에 얹히는 가산분.
func lane_stat_add(p: PilotData) -> float:
	var st: Dictionary = states.get(p, {})
	if st.is_empty():
		return 0.0
	match _key_of(p):
		KEY_BACKBONE:
			return BACKBONE_LANE_STAT if _late() else 0.0
		KEY_HOLD_POSITION:
			return HOLD_LANE_STAT if int(st["hold_until"]) >= 0 else 0.0
	return 0.0


## 존재감(교전 표적 가중치) 증감. 만능만 건드린다.
func presence_delta(p: PilotData) -> int:
	if _key_of(p) != KEY_VERSATILE:
		return 0
	return 1 if _is_hp_archetype(p) else -1


## 위치 고정이 걸린 파일럿은 이동 카드의 대상이 될 수 없다.
func blocks_move(p: PilotData) -> bool:
	var st: Dictionary = states.get(p, {})
	if st.is_empty() or _key_of(p) != KEY_HOLD_POSITION:
		return false
	return int(st["hold_until"]) >= 0


## 위치 고정이 걸린 파일럿은 오브젝트 교전에 참여하지 않는다.
func blocks_objective(p: PilotData) -> bool:
	return blocks_move(p)


## 교전 라운드 보정 — 전투 명령(단계)과 공성전(다음 한 장)의 합.
## `consume` 이 true 면 공성전 몫을 여기서 소모한다(교전이 실제로 열릴 때).
func engage_round_delta(team: int, consume: bool = false) -> int:
	var d: int = _phase_round_delta[team] + _next_engage_bonus[team]
	if consume:
		_next_engage_bonus[team] = 0
	return d


## 기회주의자 — 이번 교전에서 처치를 낸 파일럿이 이 스킬을 갖고 있으면 라운드가
## 하나 늘어난다. `TurnEngageSim` 이 라운드 경계마다 묻는다.
func engage_bonus_rounds_from_kills() -> int:
	for raw in _engage_killers.keys():
		var p := raw as PilotData
		if _key_of(p) == KEY_OPPORTUNIST:
			return OPPORTUNIST_ROUNDS
	return 0


## 원딜 사냥꾼 — 교전에서 이 파일럿이 우선해 노려야 할 적 역할. -1 = 제약 없음.
## 첫 공격 한 번만 강제되므로 `used` 를 켜서 그 뒤로는 평소 표적 규칙으로 돌아간다.
func engage_focus_role(p: PilotData) -> int:
	if _key_of(p) != KEY_ADC_HUNTER:
		return -1
	return GameEnums.Role.SNIPER


## 원딜 사냥꾼이 그 첫 공격에 얹는 공격력 배율.
func engage_focus_atk_mult(p: PilotData) -> float:
	return 1.0 + ADC_HUNTER_ATK if _key_of(p) == KEY_ADC_HUNTER else 1.0


# ─── 판정 도우미 ─────────────────────────────────────────────────────────────

## 만능 — 이 파일럿의 메크가 **체력형**인가. mechs.csv 는 id 구간이 곧
## 아키타입이다(탱커 0–5 / 격투 6–11 / 암살 12–17 / 서포터 18–23 /
## 스나이퍼 24–29). 생값 비교(max_hp vs atk)로는 갈리지 않는다 — 체력은 200대,
## 공격력은 10대라 어떤 메크를 태워도 언제나 체력이 크다.
const MECH_ATK_ARCHETYPE_RANGES: Array = [[12, 17], [24, 29]]

func _is_hp_archetype(p: PilotData) -> bool:
	var pd: PlayerData = _bs.player_data_for(p)
	if pd == null or pd.assigned_mech == null:
		# 메크가 없으면(단독 실행) 근접/원거리를 존재감으로 가른다.
		return p.presence >= 4
	var mid: int = pd.assigned_mech.id
	for raw in MECH_ATK_ARCHETYPE_RANGES:
		var lo: int = int((raw as Array)[0])
		var hi: int = int((raw as Array)[1])
		if mid >= lo and mid <= hi:
			return false
	return true


## 경쟁 심리 — 상대 팀의 **같은 레인** 파일럿. 정글러는 정글러끼리 본다.
func _rival_of(p: PilotData) -> PilotData:
	for raw in _bs.pilots:
		var q := raw as PilotData
		if q.team != p.team and q.lane == p.lane \
				and q.is_guerrilla == p.is_guerrilla:
			return q
	return null


func _rival_behind_score(p: PilotData) -> bool:
	var q: PilotData = _rival_of(p)
	return q != null and p.score < q.score


func _rival_behind_kills(p: PilotData) -> bool:
	var q: PilotData = _rival_of(p)
	return q != null and p.kills < q.kills


func _rival_ahead_deaths(p: PilotData) -> bool:
	var q: PilotData = _rival_of(p)
	return q != null and p.deaths > q.deaths
