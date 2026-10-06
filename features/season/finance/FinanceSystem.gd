class_name FinanceSystem
extends RefCounted

# ── 재무 · 시설 (M6) — STUB: 시그니처는 계약(계획서 §11.5), 몸통은 M6 작업이 채운다 ──
# `season_state.finance` 의 모양은 이 파일이 소유한다. 다른 기능은 아래 함수만
# 부른다 — 배율 넷은 이 스텁에서 1.0(효과 없음)이다.


## 런 시작 때 한 번(`GameManager.start_run`) — 시작 잔고 · 시설 레벨 · 배분 기본값.
static func init_run(_state: Dictionary, _team_id: int) -> void:
	pass


## 주 마감(`SeasonHub._end_week`, 달력이 넘어가기 전) — 수입 − 지출 정산.
## 돌려주는 것은 그 주 요약(허브 토스트용) `{income, expense, net, balance, cuts: Array[String]}`.
static func settle_week(_state: Dictionary) -> Dictionary:
	return {}


## 내 경기 결과를 소비할 때 한 번 — 성적 보너스 적립.
static func record_match(_state: Dictionary, _pending_match: Dictionary, _won: bool) -> void:
	pass


static func balance(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("balance", 0))


## 지금 시설 레벨 1..5. 런 상태가 없으면 1.
static func facility_level(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("facility_level", 1))


## 훈련 EXP 배율(시설 · 훈련 배분 · 파산 삭감 반영). `TrainingBoard` 가 곱한다.
static func training_exp_mult(_state: Dictionary) -> float:
	return 1.0


## 메크 숙련도 획득 배율(시설). `MechMastery` 가 곱한다.
static func mastery_mult(_state: Dictionary) -> float:
	return 1.0


## 사건 발생 확률 배율(시설 · 복지 배분). `MentalSystem` 이 곱한다.
static func incident_mult(_state: Dictionary) -> float:
	return 1.0
