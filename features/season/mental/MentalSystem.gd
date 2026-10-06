class_name MentalSystem
extends RefCounted

# ── 멘탈 — 신뢰도 · 면담 · 외출 · 사건 (M7) — STUB: 시그니처는 계약(계획서 §11.6),
# 몸통은 M7 작업이 채운다. `season_state.trust` / `.outings` / `.mental`.


## 런 시작 때 한 번 — 내 5인 신뢰도 초기값 등.
static func init_run(_state: Dictionary) -> void:
	pass


## 주 마감(`SeasonHub._end_week`) — 주간 면담 · 외출 한도 초기화 등.
static func end_week(_state: Dictionary) -> void:
	pass


## 그 선수의 그날 훈련 EXP 배율(외출 다음 날 피로 등). `TrainingBoard` 가 곱한다.
## `day` 는 0(월)..4(금).
static func training_exp_mult(_state: Dictionary, _pilot_id: int, _day: int) -> float:
	return 1.0


static func trust(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("trust", {}) as Dictionary).get(str(pilot_id), 0))


static func outings(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("outings", {}) as Dictionary).get(str(pilot_id), 0))


## 진엔딩을 본 선수 id 목록 — **런 클리어 정산 때만** 의미가 있다
## (조건: 외출 `TRUE_ENDING_OUTINGS` 회 이상 + 런 클리어). `RunResult` 가 부른다.
static func true_ending_pilots(_state: Dictionary) -> Array:
	return []
