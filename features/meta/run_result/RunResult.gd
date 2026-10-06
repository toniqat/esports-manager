class_name RunResult
extends RefCounted

# 런 종료 정산 — 점수 · 재화 · 감독 EXP · 업적을 계산해 프로필에 쓰고 run.save 를
# 지운다. 계약: docs/outgame_dev_plan.md §10.3.

const SCENE_PATH: String = "res://scenes/RunResult.tscn"


## 지금 런(`GameManager.season_state`)을 정산한다. `outcome` = "clear" | "fail" | "abandon".
## 같은 런에 두 번 불려도 한 번만 정산한다(`season_state.run_over`).
## 결과를 `GameManager.last_run_result` 에 두고 돌려준다.
##
## (기반 커밋의 자리표시 — RunResult 작업이 구현한다.)
static func settle_current_run(outcome: String) -> Dictionary:
	var gm: Node = (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager")
	gm.season_state["run_over"] = true
	gm.last_run_result = {"outcome": outcome}
	return gm.last_run_result
