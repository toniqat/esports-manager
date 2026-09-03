class_name TeamDraft
extends Control

# Initial 5-pilot team selection. Each role 0..4 must be filled exactly once.
# Swaps preserve the invariant "every team has 5 pilots, one per role".

@onready var _gm: Node = get_node("/root/GameManager")

# ─── 슬롯 순서 (탑 · 정글 · 미드 · 원딜 · 서폿) ──────────────────────────────
# 화면의 다섯 칸은 **역할 고정**이고 그 순서는 `GameEnums.ROLE_DISPLAY_ORDER`
# 하나에서 온다 — 인게임 파일럿 스트립도, 밴픽 화면의 양 팀 블록도, 시즌 허브
# 로스터도 같은 표를 읽는다. 예전에는 화면마다 자기 순서를 들고 있어서 같은
# 다섯 명이 화면마다 다른 자리에 앉았다.
const SLOT_ROLES: Array = GameEnums.ROLE_DISPLAY_ORDER
const SLOT_NAMES: Array = ["탑", "정글", "미드", "원딜", "서폿"]

## 역할 → 화면 슬롯 인덱스. `SLOT_ROLES` 의 역인덱스이며, 썸네일을 눌렀을 때
## 그 파일럿이 어느 칸에 앉는지를 정하는 유일한 답이다.
static func slot_of_role(role: int) -> int:
	return SLOT_ROLES.find(role)



var _view: TeamDraftView = null


# Called by SeasonHub right before showing the draft screen, after
# init_season() has populated the pilot pool. Idempotent.
func ensure_view() -> void:
	if _view != null:
		return
	_view = TeamDraftView.new()
	add_child(_view)


# Pool layout for the draft grid: 5 roles × 5 candidates, ranked by total stats
# (descending) inside each role. Returns Array of
# {pilot: PlayerData, role: int, rank: int}.
#
# **모브 파일럿은 빠진다.** 스킬이 25개뿐이라 40명 중 15명은 고유 스킬이 없고,
# 그쪽은 초상화도 실루엣인 "이름 없는 선수"다 — 플레이어가 뽑을 대상이 아니라
# AI 팀의 머릿수를 채우는 배경이다. 적으로는 여전히 만난다.
#
# 그래서 격자가 8행에서 5행으로 줄었고, 팀 0(플레이어 시작 팀)은 다섯 자리가
# 전부 네임드다 — `apply_draft` 의 맞교환이 네임드끼리만 일어나야 팀별 네임드
# 수가 드래프트로 흔들리지 않는다.
func get_pool_grid() -> Array:
	var pool: Array = _gm.season_state["all_pilots"]
	var by_role: Dictionary = {0: [], 1: [], 2: [], 3: [], 4: []}
	for p_raw in pool:
		var p := p_raw as PlayerData
		if p.is_mob:
			continue
		by_role[int(p.role)].append(p)
	var entries: Array = []
	for r in 5:
		var arr: Array = by_role[r]
		arr.sort_custom(_compare_by_stats)
		for i in arr.size():
			entries.append({"pilot": arr[i], "role": r, "rank": i})
	return entries


func _compare_by_stats(a: PlayerData, b: PlayerData) -> bool:
	return _total_stats(a) > _total_stats(b)


func _total_stats(p: PlayerData) -> int:
	return p.stat_total()


# Validate a draft selection: 5 pilot ids, one per role 0..4, all distinct,
# all present in the pool. Returns "" on success, or an error string.
func validate_draft(pilot_ids: Array) -> String:
	if pilot_ids.size() != 5:
		return "Must pick exactly 5 pilots (got %d)" % pilot_ids.size()
	var pool: Array = _gm.season_state["all_pilots"]
	var by_id: Dictionary = {}
	for p in pool:
		by_id[p.id] = p
	var seen_roles: Dictionary = {}
	for pid in pilot_ids:
		if not by_id.has(pid):
			return "Unknown pilot id: %s" % str(pid)
		var r: int = int(by_id[pid].role)
		if seen_roles.has(r):
			return "Duplicate role %d" % r
		seen_roles[r] = true
	return ""


# Apply a validated draft. For each picked pilot p (from team t_p), swap
# the team-0 pilot of the same role with p, sending the displaced pilot
# back to team t_p. Returns "" on success or error string.
func apply_draft(pilot_ids: Array) -> String:
	var err := validate_draft(pilot_ids)
	if err != "":
		return err

	var pool: Array = _gm.season_state["all_pilots"]
	var by_id: Dictionary = {}
	for p in pool:
		by_id[p.id] = p

	# Map role -> current team-0 pilot id for fast lookup
	var team0_by_role: Dictionary = {}
	for p in pool:
		if p.team_id == 0:
			team0_by_role[p.role] = p.id

	for pid in pilot_ids:
		var picked: PlayerData = by_id[pid]
		if picked.team_id == 0:
			continue   # already on team 0
		var displaced_id: int = team0_by_role[picked.role]
		var displaced: PlayerData = by_id[displaced_id]
		var src_team: int = picked.team_id
		picked.team_id = 0
		displaced.team_id = src_team

	_rebuild_rosters_from_pool()
	return ""


func _rebuild_rosters_from_pool() -> void:
	var rosters: Dictionary = {}
	for t in _gm.TEAM_COUNT:
		rosters[t] = []
	for p in _gm.season_state["all_pilots"]:
		rosters[p.team_id].append(p.id)
	_gm.season_state["team_rosters"] = rosters


# ─── 카드 후보 풀 — **삭제됨** ────────────────────────────────────────────────
# `pilot_card_slots_for_role` / `candidate_cards_for_role` / `slot_summary_for_role`
# / `cat_label` 넷이 여기 있었고, 유일한 소비자는 `DraftDetailPanel` 의 "받게 될
# 파일럿 카드" 절이었다. 그 절이 없어지며(후보는 역할이 정하는 것이라 선수를
# 고르는 판단에 들어가지 않고, 실제 3장은 경기 시작 시 표집된다) 넷 다 함께
# 사라졌다. **배분 규칙의 원본은 `CardPhaseManager._pilot_slots_for` 다** —
# 여기 있던 표는 그것을 역할 기준으로 옮겨 적은 사본이었으므로, 되살릴 일이
# 생기면 사본을 다시 만들지 말고 그쪽을 부를 것.


# ─── 파일럿 스킬 ─────────────────────────────────────────────────────────────
## 스킬 타입 표시명. CSV 의 `cooldown` / `charge` / `passive` 를 그대로 띄우면
## 화면에서 읽히지 않는다.
static func skill_type_label(t: String) -> String:
	match t:
		"cooldown": return "쿨타임"
		"charge":   return "충전식"
		"passive":  return "패시브"
	return t
