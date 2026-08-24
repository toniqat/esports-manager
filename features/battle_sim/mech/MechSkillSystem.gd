class_name MechSkillSystem
extends Node

# 메크 스킬 — **기체 한 대에 붙는 고유 능력.** 파일럿 스킬(`PilotSkillSystem`)이
# 선수에게 붙는 한 수라면 이쪽은 그 선수가 타고 있는 기체가 하는 일이고, 그래서
# 밴픽에서 기체를 고르는 순간 이미 절반이 정해진다.
#
# 두 표가 짝이다.
#   • `data/csv/mech_passives.csv` (15행) — 기체 21대 중 15대가 갖는 상시 능력.
#     `key` 가 런타임 분기 키이고 `KEY_*` 상수와 1:1 이다.
#   • `data/csv/mech_cards.csv` (64행) — 그 기체가 덱에 들고 오는 카드들.
#     카드 **효과**는 `CardPhaseManager` 가 절 문법으로 처리하고, 이 모듈은
#     그 카드들이 남기는 **상태와 사건 훅**만 맡는다.
#
# ─── 효과를 문법으로 만들지 않은 이유 (패시브 한정) ─────────────────────────
# 파일럿 스킬과 같은 판단이다. 패시브 15개는 전부 서로 다른 사건에 걸리므로
# (교전 개시 · 포탑 파괴 · 오브젝트 승리 · 명중 · 피해 수수) 절 문법을 만들어야
# 절이 15개 생길 뿐이다. `KEY_*` 를 grep 하면 그 패시브가 걸리는 자리가 전부
# 나온다.
#
# ─── 어디서 읽히는가 ─────────────────────────────────────────────────────────
# 패시브 보정은 **질의 함수로만** 내보내고 계산은 원래 하던 자리가 그대로 한다:
#   • `BattleSim.refresh_growth_stats` — `atk_mult` / `bulk_power_atk`
#   • `SimulationCore` 의 피해 계산     — `damage_taken_mult` / `consume_reactive_armor`
#   • `TurnEngageSim`                   — `engage_targets_all` / `overclock_extra_attack`
# 스탯을 직접 밀면 성장 재계산 한 번에 지워지기 때문이다 — 카드의 일시 공격력이
# `PilotData.atk_buff` 로 따로 사는 것과 같은 이유이고, 영구 몫은
# `PilotData.bonus_atk_flat` / `bonus_atk_mult` / `bonus_max_hp` 로 산다.

## 충전 · 지속 상태가 움직여 HUD 를 다시 그려야 할 때.
signal mech_state_changed

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── CSV `key` 값 ────────────────────────────────────────────────────────────
const KEY_BULK_POWER         := "bulk_power"          # 탱커 E — 최대 체력 → 공격력
const KEY_REACTIVE_PLATING   := "reactive_plating"    # 탱커 G — 교전 시 반응 장갑
const KEY_PAIN_PLEASURE      := "pain_pleasure"       # 탱커 N — 피해 수수 → 최대 체력
const KEY_VICTORY_REPORT     := "victory_report"      # 전사 D — 오브젝트 승리 → [승전보]
const KEY_DEMOLITION_ORDER   := "demolition_order"    # 전사 F — 오브젝트 승리 → [철거]
const KEY_EXECUTION_CHARGE   := "execution_charge"    # 전사 H — 처치/철거 → [처형]
const KEY_SOUL_HARVEST       := "soul_harvest"        # 전사 L — 피해 → 공격력·체력
const KEY_OVERCLOCK          := "overclock"           # 암살 P — 충전 → 교전 추가 공격
const KEY_ZEN_CHARGE         := "zen_charge"          # 암살 T — 카드 회전 → 광역 공격
const KEY_GUARDIAN_LINK      := "guardian_link"       # 지원 Q — 보호막 아군의 피해에 편승
const KEY_LAST_STAND         := "last_stand"          # 지원 V — 교전 1회 사망 방지
const KEY_VULNERABILITY_MARK := "vulnerability_mark"  # 원딜 A — 명중 → 취약
const KEY_MISSILE_STOCK      := "missile_stock"       # 원딜 C — 레인 포탑 파괴 → [미사일]
const KEY_BARRAGE            := "barrage"             # 원딜 I — 교전 공격이 전체 대상
const KEY_CALIBRATION        := "calibration"         # 원딜 J — 전장 명중 → 공격력 +1

# ─── 카드 자신에게 붙는 사건 훅 (`mech_cards.trigger`) ───────────────────────
## 적 포탑이 파괴될 때마다 이 카드를 덱에 한 장 만든다 (꿰뚫는 번개).
const TRIGGER_TURRET_KILL_DECK := "turret_kill_deck"
## 아군이든 적이든 누가 처치될 때마다 이 카드의 스택이 하나 오른다 (공격 명령).
const TRIGGER_DEATH_STACK := "death_stack"

# ─── 핸드 상주 카드 (`hand_passive:<key>`) ───────────────────────────────────
# 비용 -1 이라 낼 수 없고, **손패에 있는 것만으로** 일하는 네 장이다. 절이
# `hand_passive:<key>` 하나뿐이라 효과 체인을 타지 않고 여기서 직접 읽는다.
const HAND_CASH       := "cash"        # 원딜 B — 카드 사용마다 성장치 4%
const HAND_REVELATION := "revelation"  # 원딜 I — 카드 피해에 편승해 추가 공격
const HAND_CONTEMPT   := "contempt"    # 암살 R — 교전 시 약자 멸시 스택
const HAND_BALANCE    := "balance"     # 지원 U — 이 메크 카드의 성장치 비용 면제

# ─── 메크 카드 id (mech_cards.csv) ───────────────────────────────────────────
# 패시브와 훅이 **지목해서** 만드는 카드들. 전부 `count = 0` 이라 덱에는 이
# 경로로만 들어온다.
const CARD_PIERCING_BOLT := 3    # 꿰뚫는 번개 (덱, 포탑 파괴마다)
const CARD_MISSILE       := 7    # 미사일     (덱, 레인 포탑 파괴마다)
const CARD_VICTORY       := 16   # 승전보     (핸드, 오브젝트 승리)
const CARD_DEMOLISH      := 19   # 철거       (핸드, 오브젝트 승리)
const CARD_EXECUTE       := 22   # 처형       (핸드, 최대 충전)
const CARD_PAIN_PLEASURE := 35   # 고통과 쾌감 (덱, 자기 레인 포탑 파괴)

# ─── 튜닝 상수 ───────────────────────────────────────────────────────────────
## 취약 1당 받는 피해 배율 가산분.
const VULNERABLE_PER_STACK: float = 0.01
## 반응 장갑이 한 번에 깎아 내는 피해 비율.
const REACTIVE_ARMOR_CUT: float = 0.90
## 오버클럭 — 충전 1당 교전 추가 공격 확률.
const OVERCLOCK_PROC_PER_CHARGE: float = 0.01
## 캐시 — 카드 한 장을 낼 때마다 시전자가 버는 자기 성장치의 비율.
const CASH_RATE: float = 0.04
## `score_cost:N` 의 단위. **N = 100 이 성장치 1.00k** 다 — 시트의 "성장 점수 100"
## 은 게임 안의 `1.00k` 를 가리키고, 그 환산을 여기 한 곳에만 적어 둔다.
const SCORE_COST_UNIT: float = 0.01

# ─── 상태 ────────────────────────────────────────────────────────────────────
# PilotData → {
#   def:     Dictionary,   # mech_passives 행 (없으면 비어 있다)
#   key:     String,       # def.key 또는 ""
#   charge:  int,
#   max:     int,
# }
var _state: Dictionary = {}

## 이번 작전 단계에 **카드로** 피해를 입힌 적 명단. `PilotData 공격자 → Array`.
## [락온] 과 [신속] 이 "이번 단계에 때린 적들"을 다시 때리는 근거이고, 자기
## 작전 단계가 끝날 때 비운다.
var damaged_this_phase: Dictionary = {}

## 지금 이 아군이 **누구의 보호막**을 두르고 있는가. `PilotData 아군 → PilotData
## 메크`. 지원 Q(수호 연계)가 자기 보호막을 받은 아군의 공격에 편승할 때 읽는다.
var shield_source: Dictionary = {}

## [전쟁의 사슬] 이 읽는 라운드 수 = 그 파일럿의 영혼 포식 충전. 충전 자체는
## `_state` 에 살고 이 함수는 그 별칭이다 — 카드 설명문에 `{영혼 포식 충전 수}`
## 로 적혀 있어서, 읽는 자리가 하나임을 이름으로 못 박아 둔다.
func chain_rounds(p: PilotData) -> int:
	return charge_of(p)


# ─── 개시 ────────────────────────────────────────────────────────────────────
## 스폰과 덱 배분이 끝난 뒤 한 번. 파일럿마다 배정된 기체의 패시브 행을 붙이고,
## 게임 시작 충전(오버클럭 +20)을 심는다.
func init_for_match() -> void:
	_state.clear()
	damaged_this_phase.clear()
	shield_source.clear()
	var gm: Node = _bs.gm
	for raw in _bs.pilots:
		var p := raw as PilotData
		var def: Dictionary = {}
		if gm != null:
			var pd: PlayerData = _bs.player_data_for(p)
			if pd != null and pd.assigned_mech != null:
				def = gm.mech_passive_def(pd.assigned_mech.id)
		var entry: Dictionary = {
			"def": def,
			"key": String(def.get("key", "")),
			"charge": 0,
			"max": int(def.get("p2", 0)),
		}
		# 오버클럭만 게임 시작 충전을 갖는다 — p1 이 그 값이고, 다른 패시브의
		# p1 은 뜻이 달라서(취약 수치 · 반응 장갑 수 · 피해 비율) 여기서 일괄로
		# 심으면 안 된다.
		if entry["key"] == KEY_OVERCLOCK:
			entry["charge"] = int(def.get("p1", 0))
		_state[p] = entry
	mech_state_changed.emit()


func _entry(p: PilotData) -> Dictionary:
	return _state.get(p, {})


## 이 파일럿이 탄 기체의 패시브 키. 패시브가 없으면 빈 문자열.
func passive_key(p: PilotData) -> String:
	return String(_entry(p).get("key", ""))


## 이 파일럿의 패시브 행(이름 · 설명문 · 파라미터). 없으면 빈 Dictionary.
func passive_def(p: PilotData) -> Dictionary:
	return _entry(p).get("def", {}) as Dictionary


func has_passive(p: PilotData, key: String) -> bool:
	return passive_key(p) == key


func _param(p: PilotData, which: String, fallback: int) -> int:
	var def: Dictionary = passive_def(p)
	if def.is_empty():
		return fallback
	return int(def.get(which, fallback))


# ─── 충전 ────────────────────────────────────────────────────────────────────
func charge_of(p: PilotData) -> int:
	return int(_entry(p).get("charge", 0))


func max_charge_of(p: PilotData) -> int:
	return int(_entry(p).get("max", 0))


## 충전을 올리고(상한에서 멈춘다) 실제로 오른 양을 돌려준다. 상한에 **닿는
## 순간** 최대 충전 보상이 걸리는 패시브(처형 준비 · 무념)가 있어서, 그 판정은
## 이 한 곳에서만 한다 — 충전이 오르는 자리가 여럿이라 호출 측에 맡기면
## 조건 검사가 그 수만큼 복제된다.
func add_charge(p: PilotData, n: int) -> int:
	var e: Dictionary = _entry(p)
	if e.is_empty() or int(e.get("max", 0)) <= 0:
		return 0
	var before: int = int(e["charge"])
	var cap: int = int(e["max"])
	var after: int = clampi(before + n, 0, cap)
	e["charge"] = after
	if after != before:
		mech_state_changed.emit()
	if after >= cap and before < cap:
		_on_charge_full(p)
	return after - before


func spend_charge(p: PilotData, n: int) -> bool:
	var e: Dictionary = _entry(p)
	if e.is_empty() or int(e.get("charge", 0)) < n:
		return false
	e["charge"] = int(e["charge"]) - n
	mech_state_changed.emit()
	return true


## 충전이 상한에 닿은 그 순간. 두 패시브만 여기에 반응한다.
func _on_charge_full(p: PilotData) -> void:
	match passive_key(p):
		KEY_EXECUTION_CHARGE:
			# 처형 준비 — 핸드에 [처형] 한 장. 이미 들고 있으면 더 만들지
			# 않는다(보존 키워드라 안 버려지고 쌓이기만 한다).
			if not _hand_has_card(p, CARD_EXECUTE):
				_grant_card_to_hand(p, CARD_EXECUTE)
		KEY_ZEN_CHARGE:
			# 무념 — 충전을 전부 태워 사거리 1 내 모든 적을 친다. 카드가 아니라
			# 패시브가 직접 때리는 유일한 자리다.
			spend_charge(p, max_charge_of(p))
			_zen_sweep(p)


# ─── 패시브 질의 (계산은 원래 하던 자리가 한다) ──────────────────────────────
## 기체가 얹는 공격력 **배율**. 지금은 어느 패시브도 배율로 밀지 않으므로 언제나
## 1.0 이지만, 호출 자리(`BattleSim.refresh_growth_stats`)를 미리 열어 둔다 —
## 나중에 배율형 패시브가 생겼을 때 스탯 재계산 식을 다시 손대지 않기 위해서다.
func atk_mult(_p: PilotData) -> float:
	return 1.0


## 과적재(탱커 E) — **최대 체력 `p1` 마다 공격력 +1.** 체력에서 파생되는 값이라
## 최대 체력이 확정된 뒤에 더해져야 하고, 그래서 배율이 아니라 가산으로 돌려준다.
func bulk_power_atk(p: PilotData, final_max_hp: int) -> int:
	if not has_passive(p, KEY_BULK_POWER):
		return 0
	var per: int = maxi(1, _param(p, "p1", 10))
	return int(final_max_hp / per)


## `victim` 이 `attacker` 에게 받는 피해에 곱해지는 배율. 셋이 합쳐진다 —
## 취약(1당 +1%) · 죽음의 손가락(+25%) · 목표(그 시전자에게만 +15%).
##
## **합산이지 곱셈이 아니다.** 셋 다 "받는 피해 +N%" 라는 같은 문장이고, 곱으로
## 쌓으면 취약 100 에 죽음의 손가락이 겹친 순간 배율이 2.5 를 넘어 한 대에
## 정리되는 구간이 생긴다.
func damage_taken_mult(victim: PilotData, attacker: PilotData = null) -> float:
	if victim == null:
		return 1.0
	var m: float = 1.0
	m += float(victim.vulnerable) * VULNERABLE_PER_STACK
	m += victim.damage_taken_bonus
	if attacker != null and victim.marked_by == attacker:
		m += victim.marked_bonus
	return maxf(0.0, m)


## 반응 장갑 한 겹을 태운다. 태웠으면 true — 호출 측은 그 타격의 피해를
## `REACTIVE_ARMOR_CUT` 만큼 깎는다. **보호막보다 먼저** 걸려야 한다: 90% 를
## 깎고 남은 10% 를 보호막이 받는 순서라야 두 방어가 겹쳐 읽힌다.
func consume_reactive_armor(victim: PilotData) -> bool:
	if victim == null or victim.reactive_armor <= 0:
		return false
	victim.reactive_armor -= 1
	mech_state_changed.emit()
	return true


## 전탄 발사(원딜 I) — 교전 중 이 파일럿의 공격이 적 전원을 대상으로 하는가.
func engage_targets_all(p: PilotData) -> bool:
	return has_passive(p, KEY_BARRAGE)


## 오버클럭(암살 P) — 교전에서 피해를 준 직후 굴린다. true 면 한 번 더 때리고
## 충전 절반이 날아간다(소모는 여기서 한다 — 성공한 굴림만 대가를 치른다).
func overclock_extra_attack(p: PilotData) -> bool:
	if not has_passive(p, KEY_OVERCLOCK):
		return false
	var c: int = charge_of(p)
	if c <= 0:
		return false
	if randf() >= float(c) * OVERCLOCK_PROC_PER_CHARGE:
		return false
	spend_charge(p, c / 2)
	return true


## 불굴(지원 V) — 이 교전에서 아직 한 번도 안 쓴 사망 방지가 남아 있는가.
## 실제 소모는 `consume_last_stand`.
func last_stand_available(p: PilotData) -> bool:
	if p == null or not _last_stand_team.has(p.team):
		return false
	return not _last_stand_used.has(p)


func consume_last_stand(p: PilotData) -> void:
	_last_stand_used[p] = true


## 이번 교전에 불굴이 걸린 팀들과 이미 소모한 파일럿. 교전 개시마다 새로 잡는다.
var _last_stand_team: Dictionary = {}
var _last_stand_used: Dictionary = {}


# ─── 사건 훅 ─────────────────────────────────────────────────────────────────
## 카드 한 장이 실제로 나갔다. `CardPhaseManager._dispose_used_card` 가 부른다.
func on_card_played(cd: CardData, is_player: bool) -> void:
	if cd == null:
		return
	var caster: PilotData = cd.owner_pilot
	# 무념(암살 T) — 카드를 **쓰든 버리든** 충전이 오른다.
	if caster != null and has_passive(caster, KEY_ZEN_CHARGE):
		add_charge(caster, 1)
	# 캐시(원딜 B) — 손패에 [캐시] 를 들고 있는 파일럿은 아무 카드나 나갈 때마다
	# 자기 성장치의 4% 를 번다. 카드를 **낸 사람**이 아니라 캐시를 **들고 있는
	# 사람**이 버는 것이라 손패 전체를 훑는다.
	_payout_cash(is_player)


## 카드 한 장이 버려졌다. 무념만 반응한다.
func on_card_discarded(cd: CardData, _is_player: bool) -> void:
	if cd == null or cd.owner_pilot == null:
		return
	if has_passive(cd.owner_pilot, KEY_ZEN_CHARGE):
		add_charge(cd.owner_pilot, 1)


## **카드 공격**이 한 대 명중했다. 전장 자동 교전은 부르지 않는다 — 취약 각인도
## 조준 보정도 "공격 명중"이 곧 플레이어가 고른 한 방인 카드 쪽 사건이다.
func on_card_attack_hit(attacker: PilotData, target: PilotData, dealt: int) -> void:
	if attacker == null:
		return
	match passive_key(attacker):
		KEY_VULNERABILITY_MARK:
			if target != null:
				target.vulnerable += _param(attacker, "p1", 10)
		KEY_CALIBRATION:
			attacker.bonus_atk_flat += _param(attacker, "p1", 1)
			_bs.refresh_growth_stats(attacker)
		KEY_SOUL_HARVEST:
			_soul_harvest_gain(attacker)
	if target != null:
		var bag: Array = damaged_this_phase.get(attacker, []) as Array
		if not bag.has(target):
			bag.append(target)
		damaged_this_phase[attacker] = bag
	on_damage_dealt(attacker, dealt)
	on_damage_taken(target, dealt)
	mech_state_changed.emit()


## 교전 무대에서 한 대 넣었다. 영혼 수확과 고통과 쾌감이 여기에도 걸린다.
func on_engage_damage(attacker: PilotData, target: PilotData, dealt: int) -> void:
	if attacker != null and has_passive(attacker, KEY_SOUL_HARVEST):
		_soul_harvest_gain(attacker)
	on_damage_dealt(attacker, dealt)
	on_damage_taken(target, dealt)


## 고통과 쾌감(탱커 N) — 주고받은 피해의 `p1`% 만큼 최대 체력이 는다.
func on_damage_dealt(attacker: PilotData, amount: int) -> void:
	if attacker == null or amount <= 0:
		return
	if not has_passive(attacker, KEY_PAIN_PLEASURE):
		return
	attacker.bonus_max_hp += int(float(amount) * float(_param(attacker, "p1", 20)) / 100.0)
	_bs.refresh_growth_stats(attacker)


func on_damage_taken(victim: PilotData, amount: int) -> void:
	if victim == null or amount <= 0:
		return
	if not has_passive(victim, KEY_PAIN_PLEASURE):
		return
	victim.bonus_max_hp += int(float(amount) * float(_param(victim, "p1", 20)) / 100.0)
	_bs.refresh_growth_stats(victim)


## 누가 쓰러졌다. `BattleSim.mark_pilot_dead` 가 파일럿 스킬 바로 뒤에 부른다.
func on_kill(victim: PilotData, killer: PilotData) -> void:
	if killer != null and has_passive(killer, KEY_EXECUTION_CHARGE):
		add_charge(killer, 1)
	# [공격 명령] — 아군이든 적이든 누가 죽으면 그 카드의 스택이 오른다.
	_bump_death_stacks()
	# 쓰러진 파일럿에게 걸려 있던 지속 상태는 전장을 떠나며 함께 걷힌다.
	if victim != null:
		clear_field_effects(victim)


## 포탑 하나가 무너졌다. `BattleSim.score_turret_kill` 이 부른다 —
## `killer` 는 철거한 쪽, `td` 는 무너진 포탑이다.
func on_turret_destroyed(killer: PilotData, td: TurretData = null) -> void:
	if killer != null and has_passive(killer, KEY_EXECUTION_CHARGE):
		add_charge(killer, 1)
	# 꿰뚫는 번개 — 적 포탑이 무너질 때마다 그 팀 덱에 한 장.
	if killer != null:
		_grant_trigger_cards(killer.team, TRIGGER_TURRET_KILL_DECK, CARD_PIERCING_BOLT)
	if td == null:
		return
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.lane != td.lane:
			continue
		match passive_key(p):
			KEY_MISSILE_STOCK:
				# 미사일 적재(원딜 C) — **자신 레인의** 포탑이라면 어느 팀
				# 것이든 무너질 때마다 덱에 [미사일] 한 장. 밀리는 쪽도
				# 미는 쪽도 탄약이 는다.
				_grant_card_to_deck(p, CARD_MISSILE)
			KEY_PAIN_PLEASURE:
				# 고통과 쾌감(탱커 N) — 자기 레인 포탑을 **자기가** 부쉈을 때만.
				if p == killer:
					_grant_card_to_deck(p, CARD_PAIN_PLEASURE)


## 용 / 전령 싸움을 한 팀이 가져갔다. `ObjectiveSystem` 이 정산 직후 부른다.
func on_objective_win(team: int) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team != team:
			continue
		match passive_key(p):
			KEY_VICTORY_REPORT:  _grant_card_to_hand(p, CARD_VICTORY)
			KEY_DEMOLITION_ORDER: _grant_card_to_hand(p, CARD_DEMOLISH)


## 교전 무대가 열렸다. 참가자 명단이 확정된 직후 `EngagePhaseManager` 가 부른다.
## 여기서 켜지는 것은 **그 교전 한 번**짜리 상태다.
func on_engage_start(participants: Array) -> void:
	_last_stand_team.clear()
	_last_stand_used.clear()
	for raw in participants:
		var p := raw as PilotData
		match passive_key(p):
			KEY_REACTIVE_PLATING:
				p.reactive_armor += _param(p, "p1", 2)
			KEY_LAST_STAND:
				# 불굴은 **팀 전체**에 걸린다 — 이 기체가 참가한 교전이면
				# 그 팀 아군 모두가 한 번씩 버틴다.
				_last_stand_team[p.team] = true
		# 약자 멸시(암살 R) — 손패에 들고 있는 장수만큼 교전용 스택을 심는다.
		var contempt: int = hand_passive_stacks(p, HAND_CONTEMPT)
		if contempt > 0:
			p.set_meta("contempt_stacks", contempt)
	mech_state_changed.emit()


## 한 팀의 작전 단계가 끝났다. 단계 수명짜리 상태를 여기서 걷는다.
func on_phase_end(is_player: bool) -> void:
	var team: int = 0 if is_player else 1
	# 취약 각인은 "이번 작전 단계 동안" 이므로 각인을 **찍은 쪽**의 단계가 닫힐 때
	# 걷힌다. 지우는 대상은 **상대 팀만**이다 — 양 팀이 모두 원딜 A 를 골랐을 때
	# 전장의 취약을 통째로 비우면 내 단계가 끝나는 것만으로 상대가 내 팀에 찍어
	# 둔 각인까지 지워진다.
	var has_mark: bool = false
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team == team:
			if has_passive(p, KEY_VULNERABILITY_MARK):
				has_mark = true
			damaged_this_phase.erase(p)
		else:
			# 탈진은 **당한 쪽**의 단계가 끝날 때 풀린다.
			p.engage_locked = false
	if has_mark:
		for raw in _bs.pilots:
			var p2 := raw as PilotData
			if p2.team != team:
				p2.vulnerable = 0
	mech_state_changed.emit()


## 파일럿이 전장을 떠났다(사망 · 본진 복귀). "전장 이탈까지" 로 적힌 상태가
## 여기서 끊긴다 — `RecallSystem.return_to_hq` 와 `on_kill` 이 부른다.
func clear_field_effects(p: PilotData) -> void:
	if p == null:
		return
	p.vulnerable = 0
	p.reactive_armor = 0
	p.damage_taken_bonus = 0.0
	p.marked_by = null
	p.marked_bonus = 0.0
	p.tracked_by.clear()
	p.engage_link = null
	p.stun_charge = false
	p.stunned_rounds = 0
	shield_source.erase(p)


## 매 턴 정산 — 만료 턴이 지난 지속 효과를 걷는다. `SimulationCore` 의 만료
## 스윕이 부른다.
func tick_expiries(turn: int) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		var kept: Array = []
		for entry_raw in p.tracked_by:
			var entry: Dictionary = entry_raw as Dictionary
			if int(entry.get("expire_turn", -1)) > turn:
				kept.append(entry)
		p.tracked_by = kept
		if p.growth_link_expire_turn >= 0 and p.growth_link_expire_turn <= turn:
			p.growth_link_to = null
			p.growth_link_expire_turn = -1


# ─── 핸드 상주 카드 ──────────────────────────────────────────────────────────
## 이 파일럿이 손패에 들고 있는 `hand_passive:<key>` 카드의 **총 장수**(스택 포함).
## 0 이면 안 들고 있는 것이다.
func hand_passive_stacks(p: PilotData, key: String) -> int:
	if p == null:
		return 0
	var hand: Array = _bs.player_hand if p.team == 0 else _bs.ai_hand
	var total: int = 0
	for raw in hand:
		var cd := raw as CardData
		if cd.owner_pilot == p and cd.effect.begins_with("hand_passive:" + key):
			total += cd.stack_count
	return total


## 밸런스(지원 U) — 이 카드의 성장치 비용이 면제되는가. 같은 기체의 다른 카드에만
## 걸리므로 `mech_id` 로 가른다.
func score_cost_waived(cd: CardData) -> bool:
	if cd == null or cd.owner_pilot == null or cd.mech_id < 0:
		return false
	var hand: Array = _bs.player_hand if cd.owner_pilot.team == 0 else _bs.ai_hand
	for raw in hand:
		var other := raw as CardData
		if other == cd or other.mech_id != cd.mech_id:
			continue
		if other.effect.begins_with("hand_passive:" + HAND_BALANCE):
			return true
	return false


## 캐시 — 카드가 한 장 나갈 때마다 그 팀의 [캐시] 보유자들이 자기 성장치의
## `CASH_RATE` 를 번다.
func _payout_cash(is_player: bool) -> void:
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	for raw in hand:
		var cd := raw as CardData
		if not cd.effect.begins_with("hand_passive:" + HAND_CASH):
			continue
		var owner: PilotData = cd.owner_pilot
		if owner == null:
			continue
		_bs.add_score(owner, owner.score * CASH_RATE)


## 계시(원딜 I) — 적이 **카드로** 피해를 입을 때마다 계시 보유자가 그 적을 친다.
## 자기 자신이 낸 공격은 제외한다(무한 연쇄를 막는 유일한 장치다).
func on_card_damage_for_revelation(target: PilotData, source: PilotData) -> void:
	if target == null or not target.alive:
		return
	var hand: Array = _bs.player_hand if source != null and source.team == 0 else _bs.ai_hand
	for raw in hand.duplicate():
		var cd := raw as CardData
		if not cd.effect.begins_with("hand_passive:" + HAND_REVELATION):
			continue
		var owner: PilotData = cd.owner_pilot
		if owner == null or owner == source or not owner.alive:
			continue
		if _bs.card_phase != null:
			_bs.card_phase.deal_simple_attack(owner, target, 1)


# ─── 카드 생성 헬퍼 ──────────────────────────────────────────────────────────
func _hand_has_card(p: PilotData, card_id: int) -> bool:
	var hand: Array = _bs.player_hand if p.team == 0 else _bs.ai_hand
	for raw in hand:
		if (raw as CardData).mech_card_id == card_id:
			return true
	return false


func _grant_card_to_hand(p: PilotData, card_id: int) -> void:
	if _bs.card_phase == null:
		return
	var cd: CardData = _bs.card_phase.make_mech_card_by_id(card_id, p)
	if cd == null:
		return
	_bs.card_phase.add_card_to_hand(cd, p.team == 0)


func _grant_card_to_deck(p: PilotData, card_id: int) -> void:
	if _bs.card_phase == null:
		return
	var cd: CardData = _bs.card_phase.make_mech_card_by_id(card_id, p)
	if cd == null:
		return
	var deck: Array = _bs.player_deck if p.team == 0 else _bs.ai_deck
	deck.append(cd)
	deck.shuffle()
	_bs.card_phase.update_deck_discard_labels()


## `trigger` 훅이 걸린 카드를 **그 카드를 실제로 들고 있는 파일럿에게만** 준다.
## 훅은 카드에 붙어 있으므로, 그 카드를 가진 사람이 팀에 없으면 아무 일도 없다.
func _grant_trigger_cards(team: int, trigger: String, card_id: int) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team != team:
			continue
		if not _owns_trigger_card(p, trigger):
			continue
		_grant_card_to_deck(p, card_id)


## 이 파일럿의 기체가 그 훅을 단 카드를 들고 오는가. 배분 표(`starter_cards`)를
## 읽으므로 지금 손패/덱/더미 어디에 있든, 심지어 소멸했어도 답이 같다 — 훅은
## **기체의 성질**이지 그 카드 한 장의 소재가 아니다.
func _owns_trigger_card(p: PilotData, trigger: String) -> bool:
	var record: Dictionary = _bs.starter_cards.get(p, {})
	for raw in (record.get("mech", []) as Array):
		if (raw as CardData).trigger == trigger:
			return true
	return false


## [공격 명령] — 손패에 있는 것의 스택을 올린다. 없으면 아무 일도 없다
## (덱에 있는 카드의 스택을 미리 올려 두면 뽑는 순간 몇 장인지가 불투명해진다).
func _bump_death_stacks() -> void:
	for team in 2:
		var hand: Array = _bs.player_hand if team == 0 else _bs.ai_hand
		for raw in hand:
			var cd := raw as CardData
			if cd.trigger != TRIGGER_DEATH_STACK:
				continue
			cd.stack_count += 1
			if team == 0 and _bs.card_phase != null:
				_bs.card_phase.refresh_stack_node(cd)


# ─── 패시브 개별 구현 ────────────────────────────────────────────────────────
## 영혼 수확(전사 L) — 한 대 넣을 때마다 공격력 `p1`% + 최대 체력 `p2`.
func _soul_harvest_gain(p: PilotData) -> void:
	p.bonus_atk_mult += float(_param(p, "p1", 1)) / 100.0
	p.bonus_max_hp   += _param(p, "p2", 5)
	_bs.refresh_growth_stats(p)


## 무념(암살 T) 최대 충전 — 사거리 1 내 모든 적을 한 번씩 친다.
func _zen_sweep(p: PilotData) -> void:
	if _bs.card_phase == null or not p.alive:
		return
	for raw in _bs.pilots:
		var t := raw as PilotData
		if not t.alive or t.team == p.team:
			continue
		if _bs.hex_grid.hex_distance(p.grid_pos, t.grid_pos) > 1:
			continue
		_bs.card_phase.deal_simple_attack(p, t, 1)
