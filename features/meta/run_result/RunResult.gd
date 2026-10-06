class_name RunResult
extends RefCounted

# 런 종료 정산 — 점수 · 재화 · 감독 EXP · 업적을 계산해 프로필에 쓰고 run.save 를
# 지운다. 계약: docs/outgame_dev_plan.md §10.3. 화면은 `RunResultScreen.gd`.
#
# 부르는 곳은 셋이다 — SeasonHub 의 ENDING("clear") / GAME_OVER("fail") 진입,
# 그리고 로비의 런 포기("abandon"). 셋 다 이 함수 하나를 거쳐야 점수 공식과
# 프로필 반영이 한 군데에만 산다.
#
# 수치는 전부 const.csv 의 `RUN_SCORE_*` · `RUN_CURRENCY_PER_SCORE` ·
# `RUN_MGR_EXP_PER_SCORE` 에서 읽는다 — 여기에도 문서에도 값을 적지 않는다.

const SCENE_PATH: String = "res://scenes/RunResult.tscn"

const OUTCOME_CLEAR: String = "clear"
const OUTCOME_FAIL: String = "fail"
const OUTCOME_ABANDON: String = "abandon"

## 캠페인 순서. `phase_reached` 는 이 배열에서 지금 페이즈의 자리(0 부터)다.
const CAMPAIGN_ORDER: Array = [
	GameEnums.SeasonPhase.PRESEASON,
	GameEnums.SeasonPhase.PRESEASON_INTL,
	GameEnums.SeasonPhase.MIDSEASON,
	GameEnums.SeasonPhase.MIDSEASON_INTL,
	GameEnums.SeasonPhase.REGULAR,
	GameEnums.SeasonPhase.REGULAR_INTL,
]

## 지나간 대회를 우승했을 때 그 대회에서 이긴 경기 수 — 대진표 모양이 정한다
## (튜닝값이 아니다). 플레이오프 = 4강 · 결승(`TournamentManager`),
## 국제대회 = 8강 · 4강 · 결승(`InternationalTournament`).
const PLAYOFF_ROUNDS: int = 2
const INTL_ROUNDS: int = 3

## 실수 곱을 내림할 때 `0.1 × 70 = 6.9999…` 같은 표현 오차로 1 이 깎이지 않게
## 더하는 아주 작은 값(튜닝값 아님).
const _FLOOR_EPS: float = 0.000001


## 지금 런(`GameManager.season_state`)을 정산한다. `outcome` = "clear" | "fail" | "abandon".
## 같은 런에 두 번 불려도 한 번만 정산한다(`season_state.run_over`) — 두 번째는
## 이미 만든 결과(`last_run_result`)를 그대로 돌려준다.
## 결과를 `GameManager.last_run_result` 에 두고 돌려준다.
static func settle_current_run(outcome: String) -> Dictionary:
	var gm: Node = _autoload("GameManager")
	if gm == null:
		push_error("RunResult: GameManager not found")
		return {}
	var state: Dictionary = gm.season_state
	if bool(state.get("run_over", false)):
		return gm.last_run_result
	if not (outcome in [OUTCOME_CLEAR, OUTCOME_FAIL, OUTCOME_ABANDON]):
		push_warning("RunResult: unknown outcome '%s' — settling as fail" % outcome)
		outcome = OUTCOME_FAIL
	# 자동 저장이 정산 뒤에 run.save 를 되살리지 않도록 가장 먼저 닫는다.
	state["run_over"] = true

	RunStats.finalize_phase(state, int(state.get("current_phase", 0)))

	var result: Dictionary = build_result(state, outcome, bool(gm.use_test_run))

	if not bool(result["test_run"]):
		var pm: Node = _autoload("ProfileManager")
		if pm == null:
			push_error("RunResult: ProfileManager not found — profile not updated")
		else:
			var perr: String = pm.apply_run_result(result)
			if perr != "":
				push_error("RunResult: apply_run_result failed — %s" % perr)
	# 테스트 런이면 `run_path()` 가 run_test.save 를 가리킨다 — 그 파일만 지운다.
	var derr: String = SaveSystem.delete_run()
	if derr != "":
		push_warning("RunResult: %s" % derr)

	gm.last_run_result = result
	return result


## 정산 결과를 순수하게 계산한다(프로필 · 파일을 건드리지 않는다).
## 모양은 §10.3 에 화면용 표시 키(`team_name` · `scenario_name` · `pilots` ·
## `phases_cleared` · `breakdown` · `id`)를 더한 것.
static func build_result(state: Dictionary, outcome: String, test_run: bool) -> Dictionary:
	var run_setup: Dictionary = _dict(state.get("run_setup", {}))
	var run_stats: Dictionary = _dict(state.get("run_stats", {}))
	var team_id: int = int(state.get("player_team_id", run_setup.get("team_id", 0)))
	var scenario_id: int = int(run_setup.get("scenario", 0))

	var phase_reached: int = maxi(0, CAMPAIGN_ORDER.find(int(state.get("current_phase", 0))))
	# 점수는 **끝낸** 페이즈만 센다 — 지금 페이즈는 이번 런을 끝낸(진) 자리라
	# 실패 · 포기에서는 빠지고, 클리어(마지막 페이즈 우승)일 때만 들어간다.
	var phases_cleared: int = phase_reached + (1 if outcome == OUTCOME_CLEAR else 0)
	var record: Dictionary = player_record(state)
	var wins: int = int(record["wins"])
	var losses: int = int(record["losses"])
	var titles: int = count_titles(state)
	var cleared: bool = outcome == OUTCOME_CLEAR
	var bonus_points: int = 0   # 감독 특성 보너스 점수 — M8 에서 채운다.

	var breakdown: Dictionary = {
		"phase":  phases_cleared * ConstTable.int_of("RUN_SCORE_PER_PHASE"),
		"wins":   wins * ConstTable.int_of("RUN_SCORE_PER_WIN"),
		"titles": titles * ConstTable.int_of("RUN_SCORE_PER_TITLE"),
		"clear":  ConstTable.int_of("RUN_SCORE_CLEAR_BONUS") if cleared else 0,
		"bonus":  bonus_points,
	}
	var score: int = 0
	for k in breakdown.keys():
		score += int(breakdown[k])
	var currency: int = int(floor(score * ConstTable.num("RUN_CURRENCY_PER_SCORE") + _FLOOR_EPS))
	var manager_exp: int = int(floor(score * ConstTable.num("RUN_MGR_EXP_PER_SCORE") + _FLOOR_EPS))

	var mine: Array = my_pilot_ids(state)
	var mvp: Dictionary = {}
	var mvp_count: Dictionary = _dict(run_stats.get("mvp_count", {}))
	for ph in mvp_count.keys():
		var per: Dictionary = _dict(mvp_count[ph])
		for k in per.keys():
			var pid: int = int(k)
			if not (pid in mine):
				continue
			var key: String = str(pid)
			mvp[key] = int(mvp.get(key, 0)) + int(per[k])
	var pom: Dictionary = {}
	var pom_by_phase: Dictionary = _dict(run_stats.get("pom_by_phase", {}))
	for ph in pom_by_phase.keys():
		var pom_pid: int = int(pom_by_phase[ph])
		if pom_pid in mine:
			pom[str(int(ph))] = pom_pid
	var achievements: Dictionary = {}
	for pid in mine:
		var key: String = str(pid)
		var pom_n: int = 0
		for ph in pom.keys():
			if int(pom[ph]) == int(pid):
				pom_n += 1
		achievements[key] = {"mvp": int(mvp.get(key, 0)), "pom": pom_n}

	var at: String = _now_string()
	var result: Dictionary = {
		"outcome": outcome,
		"scenario": scenario_id,
		"team_id": team_id,
		"phase_reached": phase_reached,
		"wins": wins,
		"losses": losses,
		"titles": titles,
		"score": score,
		"bonus_points": bonus_points,
		"currency": {"outgame": currency},
		"manager_exp": manager_exp,
		"mvp": mvp,
		"pom": pom,
		"achievements": achievements,
		"test_run": test_run,
		"at": at,
		# ── 표시용 (계약 밖, 화면이 season_state 없이 그릴 수 있게) ──
		# 정산 한 번마다 다른 값 — 프로필이 같은 결과를 두 번 반영하지 않는 열쇠.
		"id": "%d-%s-%d" % [int(state.get("run_seed", 0)), at, Time.get_ticks_usec()],
		"phases_cleared": phases_cleared,
		"breakdown": breakdown,
		"team_name": _team_name(state, team_id),
		"scenario_name": String(RunRules.scenario(scenario_id).get("name", "")),
		"pilots": _pilot_rows(state, mine),
	}
	# M7 — true endings: run cleared + outings with that pilot ≥ `TRUE_ENDING_OUTINGS`.
	# Present **only on a clear** (`ProfileManager.apply_run_result` records them).
	if cleared:
		result["true_endings"] = MentalSystem.true_ending_pilots(state)
	return result


# ── 집계 ─────────────────────────────────────────────────────────────────────
## 내 팀 경기 승패. `run_stats.wins / losses` 가 있으면 그것이 정답이다(경기마다
## `RunStats.record_match` 가 센다). 없으면(그 집계 이전 세이브 등) 일정과
## 대진표에서 되짚는다 — `derive_record`.
static func player_record(state: Dictionary) -> Dictionary:
	var run_stats: Dictionary = _dict(state.get("run_stats", {}))
	if run_stats.has("wins") or run_stats.has("losses"):
		return {"wins": int(run_stats.get("wins", 0)), "losses": int(run_stats.get("losses", 0))}
	return derive_record(state)


## 일정 · 대진표만으로 내 팀 승패를 센다.
##   1. 리그 — `match_schedule` 은 페이즈가 바뀌어도 쌓이므로 치른 내 경기를 전부 센다.
##   2. 지금 대회 — `current_tournament.bracket` 에서 치른 내 경기.
##   3. 지나간 대회 — 대진표는 페이즈 전환 때 지워진다. `phase_results` 로 우승한
##      대회만 라운드 수만큼 승으로 센다. 우승 못 한 지나간 대회는 어느 라운드에서
##      졌는지 알 수 없어 세지 않는다(하한값). 지금 대회와 같은 페이즈는 2 에서 셌다.
static func derive_record(state: Dictionary) -> Dictionary:
	var pid: int = int(state.get("player_team_id", 0))
	var wins: int = 0
	var losses: int = 0
	for m in (state.get("match_schedule", []) as Array):
		var md: Dictionary = _dict(m)
		var r: int = _match_outcome(md, pid)
		if r > 0:
			wins += 1
		elif r < 0:
			losses += 1

	var live_phase: int = -1
	var live_type: String = ""
	var t: Variant = state.get("current_tournament", null)
	if typeof(t) == TYPE_DICTIONARY:
		var td: Dictionary = t
		live_phase = int(td.get("phase_at_start", -1))
		live_type = String(td.get("type", ""))
		for m in (td.get("bracket", []) as Array):
			var r: int = _match_outcome(_dict(m), pid)
			if r > 0:
				wins += 1
			elif r < 0:
				losses += 1

	var pr: Dictionary = _dict(state.get("phase_results", {}))
	for k in pr.keys():
		var phase: int = int(k)
		var entry: Dictionary = _dict(pr[k])
		var is_intl: bool = entry.has("intl_champion")
		var live_same: bool = phase == live_phase \
				and live_type == ("INTL" if is_intl else "PLAYOFF")
		if live_same:
			continue
		if int(entry.get("champion", -1)) == pid:
			wins += PLAYOFF_ROUNDS
		if int(entry.get("intl_champion", -1)) == pid:
			wins += INTL_ROUNDS
	return {"wins": wins, "losses": losses}


## 우승한 대회 수 — 리그 페이즈 플레이오프(`champion`) + 국제대회(`intl_champion`).
static func count_titles(state: Dictionary) -> int:
	var pid: int = int(state.get("player_team_id", 0))
	var n: int = 0
	var pr: Dictionary = _dict(state.get("phase_results", {}))
	for k in pr.keys():
		var entry: Dictionary = _dict(pr[k])
		if int(entry.get("champion", -1)) == pid:
			n += 1
		if int(entry.get("intl_champion", -1)) == pid:
			n += 1
	return n


## 내 선수 5명 — `run_setup.pilot_ids`, 없으면(옛 세이브) 내 팀 로스터.
static func my_pilot_ids(state: Dictionary) -> Array:
	var out: Array = []
	var run_setup: Dictionary = _dict(state.get("run_setup", {}))
	for raw in (run_setup.get("pilot_ids", []) as Array):
		out.append(int(raw))
	if out.is_empty():
		var rosters: Dictionary = _dict(state.get("team_rosters", {}))
		var pid: int = int(state.get("player_team_id", 0))
		var roster: Variant = rosters.get(pid, rosters.get(str(pid), []))
		if typeof(roster) == TYPE_ARRAY:
			for raw in (roster as Array):
				out.append(int(raw))
	return out


# 치른 경기 하나에서 내 팀 결과. 1 = 승, -1 = 패, 0 = 내 경기 아님 / 안 치름.
static func _match_outcome(m: Dictionary, pid: int) -> int:
	if not bool(m.get("played", false)):
		return 0
	if int(m.get("team_a", -1)) != pid and int(m.get("team_b", -1)) != pid:
		return 0
	return 1 if int(m.get("winner", -1)) == pid else -1


# ── 표시용 ───────────────────────────────────────────────────────────────────
static func _team_name(state: Dictionary, team_id: int) -> String:
	var metas: Array = state.get("team_meta", [])
	for m in metas:
		var md: Dictionary = _dict(m)
		if int(md.get("id", -1)) == team_id:
			return String(md.get("name", ""))
	if team_id >= 0 and team_id < metas.size():
		return String(_dict(metas[team_id]).get("name", ""))
	return ""


# 내 선수 표시 행 `[{id, name, role}]`, 화면 자리 순(`GameEnums.role_seat`).
static func _pilot_rows(state: Dictionary, ids: Array) -> Array:
	var rows: Array = []
	for pid in ids:
		var row: Dictionary = {"id": int(pid), "name": "#%d" % int(pid), "role": -1}
		for p in (state.get("all_pilots", []) as Array):
			if p is PlayerData and (p as PlayerData).id == int(pid):
				row["name"] = (p as PlayerData).name
				row["role"] = (p as PlayerData).role
				break
		rows.append(row)
	rows.sort_custom(func(a, b):
		return GameEnums.role_seat(int(a["role"])) < GameEnums.role_seat(int(b["role"])))
	return rows


static func _now_string() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"],
	]


static func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _autoload(node_name: String) -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(node_name)
