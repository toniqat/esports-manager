class_name RunStats
extends RefCounted

# 경기 MVP · 페이즈 POM 집계 — `season_state.run_stats`. 계약:
# docs/outgame_dev_plan.md §10.1 · §10.4. 규칙은 `features/season/run_stats/README.md`.
#
# **순수 정적 함수만 있다** — 노드도 상태도 없고, 넘겨받은 사전만 고친다.
# BattleSim(경기 끝 MVP 고르기 · MVP 뷰)과 SeasonHub(경기 결과 소비 · 페이즈
# 전환) · RunResult(정산 때 지금 페이즈 닫기)가 같은 함수를 부르므로 지표가
# 갈라질 자리가 없다.
#
# `run_stats` 는 run.save(JSON)를 지나므로 **사전 키는 전부 문자열**이고, 값의
# 정수는 불러온 뒤 실수로 돌아와 있을 수 있다 — 읽을 때마다 `int()` /
# `float()` 로 되돌린다. 가중치는 data/csv/const.csv 의 `MVP_*` / `POM_*`.

static var MVP_KILL_MULT: float       = ConstTable.num("MVP_KILL_MULT")
static var MVP_ASSIST_MULT_SUP: float = ConstTable.num("MVP_ASSIST_MULT_SUP")
static var MVP_W_KDA: float           = ConstTable.num("MVP_W_KDA")
static var MVP_W_DMG: float           = ConstTable.num("MVP_W_DMG")
static var MVP_W_TANK: float          = ConstTable.num("MVP_W_TANK")
static var MVP_W_SUP_CARE: float      = ConstTable.num("MVP_W_SUP_CARE")
static var POM_W_MVP: float           = ConstTable.num("POM_W_MVP")
static var POM_W_SCORE: float         = ConstTable.num("POM_W_SCORE")


## 탑 — 다섯 자리 줄(`GameEnums.ROLE_DISPLAY_ORDER`)의 첫 자리 역할.
static func top_role() -> int:
	return int(GameEnums.ROLE_DISPLAY_ORDER[0])


## 서폿 — 같은 줄의 마지막 자리 역할.
static func support_role() -> int:
	return int(GameEnums.ROLE_DISPLAY_ORDER[GameEnums.ROLE_DISPLAY_ORDER.size() - 1])


## 경기 한 줄(`pilot_stats` 의 행)의 MVP 지표. d = max(데스, 1).
##   서폿            W_KDA·(k + ASSIST_MULT_SUP·a)/d + W_SUP_CARE·(care + taken)/d
##   그 밖(탑~원딜)   W_KDA·(KILL_MULT·k + a)/d + W_DMG·dmg/d   (+ 탑만 W_TANK·taken/d)
static func mvp_score(row: Dictionary) -> float:
	var k: float = float(row.get("k", 0))
	var a: float = float(row.get("a", 0))
	var d: float = maxf(float(row.get("d", 0)), 1.0)
	var dmg: float = float(row.get("dmg", 0))
	var taken: float = float(row.get("taken", 0))
	var care: float = float(row.get("care", 0))
	var role: int = int(row.get("role", -1))
	if role == support_role():
		return MVP_W_KDA * (k + MVP_ASSIST_MULT_SUP * a) / d \
				+ MVP_W_SUP_CARE * (care + taken) / d
	var score: float = MVP_W_KDA * (MVP_KILL_MULT * k + a) / d + MVP_W_DMG * dmg / d
	if role == top_role():
		score += MVP_W_TANK * taken / d
	return score


## `rows` 중 이긴 쪽(`side == winner_side`)에서 지표가 가장 높은 행의 **인덱스**.
## 동점이면 앞선 행(= 역할 순으로 먼저 놓인 선수)이 이긴다. 후보가 없으면 -1.
## MVP 뷰는 인덱스로 전장의 `PilotData` 를 되찾으므로 id 가 아니라 이것을 쓴다.
static func pick_mvp_index(rows: Array, winner_side: int) -> int:
	var best: int = -1
	var best_score: float = -INF
	for i in rows.size():
		if not (rows[i] is Dictionary):
			continue
		var row := rows[i] as Dictionary
		if int(row.get("side", -1)) != winner_side:
			continue
		var s: float = mvp_score(row)
		if s > best_score:
			best_score = s
			best = i
	return best


## 이긴 쪽 MVP 의 `pilot_id`. 후보가 없으면 -1.
static func pick_mvp(rows: Array, winner_side: int) -> int:
	var idx: int = pick_mvp_index(rows, winner_side)
	if idx < 0:
		return -1
	return int((rows[idx] as Dictionary).get("pilot_id", -1))


## `state.run_stats` 를 계약의 모양으로 채워 돌려준다(없는 칸만 만든다).
static func ensure(state: Dictionary) -> Dictionary:
	var rs: Variant = state.get("run_stats", null)
	if not (rs is Dictionary):
		rs = {}
		state["run_stats"] = rs
	var d := rs as Dictionary
	if not (d.get("matches", null) is Array):
		d["matches"] = []
	for key in ["mvp_count", "score_sum", "pom_by_phase"]:
		if not (d.get(key, null) is Dictionary):
			d[key] = {}
	# `wins` / `losses` 는 여기서 만들지 않는다 — 경기를 하나라도 센 뒤에만
	# 생긴다(`record_match`). RunResult 는 이 두 키가 **있을 때만** 정답으로 믿고,
	# 없으면(집계 이전 세이브) 일정에서 센다 — 빈 0 을 심으면 그 대체 경로가 막힌다.
	return d


## 내 경기 하나의 결과를 집계한다. `SeasonHub._consume_pending_match_result` 가
## 결과를 받는 그 자리에서 **한 번** 부른다(`pending_match["stats_recorded"]` 로
## 두 번째 호출은 무위다).
##
## 승패는 `winner_side`(0 = 내 팀)에서 센다. `pilot_stats` 가 없으면(옛 저장 등)
## 승패와 빈 경기 한 줄만 남는다. MVP 는 BattleSim 이 적은 `mvp_pilot_id` 를
## 믿고, 없으면 같은 규칙(`pick_mvp`)으로 여기서 뽑는다.
static func record_match(state: Dictionary, pending_match: Dictionary) -> void:
	if bool(pending_match.get("stats_recorded", false)):
		return
	var winner_side: int = int(pending_match.get("winner_side", -1))
	if winner_side < 0:
		return
	pending_match["stats_recorded"] = true
	var rs: Dictionary = ensure(state)
	var phase_key: String = str(int(state.get("current_phase", 0)))
	var won: bool = winner_side == 0
	rs["wins"] = int(rs.get("wins", 0)) + (1 if won else 0)
	rs["losses"] = int(rs.get("losses", 0)) + (0 if won else 1)

	var rows_v: Variant = pending_match.get("pilot_stats", [])
	var rows: Array = rows_v if rows_v is Array else []
	var mvp: int = int(pending_match.get("mvp_pilot_id", -1))
	if mvp < 0 and not rows.is_empty():
		mvp = pick_mvp(rows, winner_side)

	var scores: Dictionary = {}
	var sums: Dictionary = _sub(rs["score_sum"] as Dictionary, phase_key)
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		var pid: int = int(row.get("pilot_id", -1))
		if pid < 0:
			continue
		var key: String = str(pid)
		var s: float = mvp_score(row)
		scores[key] = s
		sums[key] = float(sums.get(key, 0.0)) + s
	if mvp >= 0:
		var counts: Dictionary = _sub(rs["mvp_count"] as Dictionary, phase_key)
		counts[str(mvp)] = int(counts.get(str(mvp), 0)) + 1

	(rs["matches"] as Array).append({
		"phase": int(phase_key), "won": won, "mvp": mvp, "scores": scores,
	})


## 페이즈 하나를 닫는다 — 그 페이즈 POM 을 뽑아 `run_stats.pom_by_phase` 에 적는다.
## 후보는 그 페이즈에 지표가 기록된 모든 선수(양 팀)이고, 점수는
## `POM_W_MVP·(그 페이즈 MVP 횟수) + POM_W_SCORE·(그 페이즈 MVP 지표 합)`.
## 동점이면 MVP 횟수가 많은 쪽, 그래도 같으면 id 가 작은 쪽.
##
## 이미 닫힌 페이즈 · 경기가 없던 페이즈는 아무 일도 없다(그래서 페이즈 전환 훅과
## 정산이 같은 페이즈를 두 번 닫아도 된다).
static func finalize_phase(state: Dictionary, phase: int) -> void:
	var rs: Dictionary = ensure(state)
	var phase_key: String = str(phase)
	var pom: Dictionary = rs["pom_by_phase"] as Dictionary
	if pom.has(phase_key):
		return
	var sums_v: Variant = (rs["score_sum"] as Dictionary).get(phase_key, {})
	var counts_v: Variant = (rs["mvp_count"] as Dictionary).get(phase_key, {})
	var sums: Dictionary = sums_v if sums_v is Dictionary else {}
	var counts: Dictionary = counts_v if counts_v is Dictionary else {}
	var candidates: Dictionary = {}
	for key in sums.keys():
		candidates[str(key)] = true
	for key in counts.keys():
		candidates[str(key)] = true
	if candidates.is_empty():
		return
	var best_pid: int = -1
	var best_score: float = -INF
	var best_mvps: int = -1
	for key in candidates.keys():
		var pid: int = int(key)
		var mvps: int = int(counts.get(key, 0))
		var s: float = POM_W_MVP * float(mvps) + POM_W_SCORE * float(sums.get(key, 0.0))
		var better: bool = s > best_score \
				or (is_equal_approx(s, best_score) and (mvps > best_mvps
					or (mvps == best_mvps and pid < best_pid)))
		if best_pid < 0 or better:
			best_pid = pid
			best_score = s
			best_mvps = mvps
	pom[phase_key] = best_pid


## `parent[key]` 사전(없으면 만들어 넣는다).
static func _sub(parent: Dictionary, key: String) -> Dictionary:
	var d: Variant = parent.get(key, null)
	if not (d is Dictionary):
		d = {}
		parent[key] = d
	return d as Dictionary
