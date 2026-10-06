class_name RunStats
extends RefCounted

# 경기 MVP · 페이즈 POM 집계 — `season_state.run_stats`. 계약:
# docs/outgame_dev_plan.md §10.4.
#
# (기반 커밋의 자리표시 — MVP/POM 작업이 구현한다.)


## 내 경기 하나의 결과(`pending_match.pilot_stats`)를 받아 MVP 를 뽑고 집계한다.
static func record_match(_state: Dictionary, _pending_match: Dictionary) -> void:
	pass


## 페이즈 하나를 닫는다 — 그 페이즈 POM 을 뽑아 `run_stats.pom_by_phase` 에 적는다.
## 이미 닫힌 페이즈면 아무 일도 없다.
static func finalize_phase(_state: Dictionary, _phase: int) -> void:
	pass
