class_name RunRoster
extends RefCounted

# ── AI 로스터 분배 (M1) — 계약: docs/outgame_dev_plan.md §10.1 · §10.2 ─────────
# 런 시작 때 내 5인을 뺀 나머지 선수를 **역할별로** 섞어 AI 팀들에 한 명씩
# 나눠 준다. 고른 팀의 원래 선수도 섞이는 쪽에 들어간다 — 원래 소속은 보지 않는다.
#
# 순수 함수만 둔다(노드 · 오토로드 · 전역 RNG 를 건드리지 않는다). 같은 입력과
# 같은 `run_seed` 면 언제나 같은 분배가 나온다 — 입력 배열의 순서와도 무관하다
# (역할별 후보를 id 순으로 정렬한 뒤 섞는다).
#
# 호출 순서(`GameManager.start_run`):
#   1. `assign(...)`      → {pilot_id: team_id} (내 5인 포함)
#   2. `apply(...)`       → 각 PlayerData.team_id 를 고친다
#   3. `build_rosters(...)` → team_rosters (팀마다 역할 순 pilot id 배열)


## 분배표를 만든다. 성공이면 `{"error": "", "teams": {pilot_id(int): team_id(int)}}`,
## 실패면 `{"error": String}` — 선수 수가 팀 × 역할과 맞지 않는 데이터에서도
## 멈추지 않고 이유를 돌려준다.
##   pilots           : Array[PlayerData] — 런의 리그 선수 전원
##   player_team_id   : 내 팀 id
##   player_pilot_ids : 내 5인 id(역할마다 한 명)
##   run_seed         : `season_state.run_seed`
##   team_count       : 리그 팀 수(팀 id 는 0 .. team_count-1)
static func assign(pilots: Array, player_team_id: int, player_pilot_ids: Array,
		run_seed: int, team_count: int) -> Dictionary:
	var role_count: int = GameEnums.Role.size()
	if pilots.size() != team_count * role_count:
		return {"error": Loc.t(L.RUN_SETUP_ROSTER_COUNT_MISMATCH,
				{"pilots": pilots.size(), "teams": team_count, "roles": role_count})}
	if player_team_id < 0 or player_team_id >= team_count:
		return {"error": Loc.t(L.UI_RUN_UNKNOWN_TEAM, {"id": player_team_id})}

	var mine: Dictionary = {}
	for raw in player_pilot_ids:
		mine[int(raw)] = true

	var ai_teams: Array = []
	for t in team_count:
		if t != player_team_id:
			ai_teams.append(t)

	# 역할별 후보(내 5인 제외)와 역할별 내 선수 수.
	var pool_by_role: Dictionary = {}
	var mine_by_role: Dictionary = {}
	for r in role_count:
		pool_by_role[r] = []
		mine_by_role[r] = 0
	var teams: Dictionary = {}
	for raw in pilots:
		var pd := raw as PlayerData
		if not pool_by_role.has(pd.role):
			return {"error": Loc.t(L.RUN_SETUP_ROSTER_UNKNOWN_ROLE, {"role": pd.role, "id": pd.id})}
		if mine.has(pd.id):
			mine_by_role[pd.role] = int(mine_by_role[pd.role]) + 1
			teams[pd.id] = player_team_id
		else:
			(pool_by_role[pd.role] as Array).append(pd.id)
	if teams.size() != mine.size():
		return {"error": Loc.t(L.RUN_SETUP_ROSTER_NOT_IN_LEAGUE)}

	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for r in role_count:
		if int(mine_by_role[r]) != 1:
			return {"error": Loc.t(L.RUN_SETUP_ROSTER_ROLE_COUNT, {"role": r, "n": int(mine_by_role[r])})}
		var ids: Array = pool_by_role[r]
		if ids.size() != ai_teams.size():
			return {"error": Loc.t(L.RUN_SETUP_ROSTER_POOL_MISMATCH,
					{"role": r, "n": ids.size(), "teams": ai_teams.size()})}
		ids.sort()
		_shuffle(ids, rng)
		for i in ids.size():
			teams[int(ids[i])] = int(ai_teams[i])
	return {"error": "", "teams": teams}


## 분배표대로 `team_id` 를 고친다. 표에 없는 선수는 그대로 둔다.
static func apply(pilots: Array, teams: Dictionary) -> void:
	for raw in pilots:
		var pd := raw as PlayerData
		if teams.has(pd.id):
			pd.team_id = int(teams[pd.id])


## `team_rosters` 모양 — team_id(int) → Array[int] pilot id, 팀 안은 역할 순.
static func build_rosters(pilots: Array, team_count: int) -> Dictionary:
	var by_team: Dictionary = {}
	for t in team_count:
		by_team[t] = []
	for raw in pilots:
		var pd := raw as PlayerData
		if by_team.has(pd.team_id):
			(by_team[pd.team_id] as Array).append(pd)
	var rosters: Dictionary = {}
	for t in team_count:
		var members: Array = by_team[t]
		members.sort_custom(func(a, b):
			var pa := a as PlayerData
			var pb := b as PlayerData
			if pa.role != pb.role:
				return pa.role < pb.role
			return pa.id < pb.id)
		var ids: Array = []
		for m in members:
			ids.append((m as PlayerData).id)
		rosters[t] = ids
	return rosters


# Fisher–Yates with the run's RNG — `Array.shuffle()` reads the global RNG and
# would break seed reproducibility.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
