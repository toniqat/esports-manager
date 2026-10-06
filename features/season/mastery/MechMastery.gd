class_name MechMastery
extends RefCounted

# ── 메크 숙련도 (M4) — STUB: 시그니처는 계약(계획서 §11.4), 몸통은 M4 작업이 채운다 ──
# `season_state.mech_mastery` = `{"<pilot_id>": {"<mech_id>": int}}`(런 한정).
# `season_state.mastery_research` = `{"<pilot_id>": mech_id}`(주간 연구 메크).
# 이 스텁은 "숙련도 없음"과 같게 동작한다(보정 0, 획득 무시).


## 런 시작 때 한 번 — 모든 선수(리그 40 + INTL 20)의 초기 숙련도.
static func init_run(_state: Dictionary) -> void:
	pass


## 숙련도 값 0..`MASTERY_MAX`. 기록이 없으면 0.
static func value(_state: Dictionary, _pilot_id: int, _mech_id: int) -> int:
	return 0


## 숙련도 등급 0..3 (미숙 / 보통 / 능숙 / 마스터).
static func tier_of(_value: int) -> int:
	return 0


## 등급 이름.
static func tier_name(t: int) -> String:
	return ["미숙", "보통", "능숙", "마스터"][clampi(t, 0, 3)]


## 그 메크를 탈 때 선수 스탯 6종 **각각**에 더할 고정치(음수 가능).
static func stat_bonus(_state: Dictionary, _pilot_id: int, _mech_id: int) -> int:
	return 0


## 숙련도 상위 메크 `[{mech_id, value}]`, 높은 순, 최대 n.
static func top_mechs(_state: Dictionary, _pilot_id: int, _n: int = 3) -> Array:
	return []


## 숙련도를 직접 올린다(배율 미적용 원값 — 배율은 호출 쪽 규칙에 따라 이 안에서 건다).
static func gain(_state: Dictionary, _pilot_id: int, _mech_id: int, _amount: int) -> void:
	pass


## 그 선수의 주간 연구 메크(-1 = 미지정).
static func research_mech(_state: Dictionary, _pilot_id: int) -> int:
	return -1


## 훈련판의 숙련도 타일(색 `M`)이 그날 정산에서 낸 숙련도 EXP — 연구 메크로 간다.
## `TrainingBoard.apply_day_training` 이 부른다.
static func add_training_exp(_state: Dictionary, _pilot_id: int, _amount: int) -> void:
	pass


## 내 경기 결과를 소비할 때 한 번(`SeasonHub._consume_pending_match_result`).
## `pending_match.assigned_mechs` = `{"<pilot_id>": mech_id}`(양 팀 10명, MatchFlow 가 적는다).
static func record_match(_state: Dictionary, _pending_match: Dictionary) -> void:
	pass


## 주 마감(`SeasonHub._end_week`) — 연구 메크 주간 획득 등.
static func settle_week(_state: Dictionary) -> void:
	pass
