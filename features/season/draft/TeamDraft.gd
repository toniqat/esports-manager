class_name TeamDraft
extends Control

# Initial 5-pilot team selection. Each role 0..4 must be filled exactly once.
# Swaps preserve the invariant "every team has 5 pilots, one per role".

@onready var _gm: Node = get_node("/root/GameManager")

# ─── 슬롯 순서 (탑 · 정글 · 미드 · 원딜 · 서폿) ──────────────────────────────
# 화면의 다섯 칸은 **역할 고정**이고 그 순서는 `GameEnums.Role` 의 열거값 순서가
# 아니라 **MOBA 라인 순서**다 — 탑 → 정글 → 미드 → 원딜 → 서폿. 열거값 순서
# (TANK · FIGHTER · ASSASSIN · SUPPORT · SNIPER)를 그대로 쓰면 정글러가 세 번째,
# 서포터가 네 번째로 앉는데 그 배열은 플레이어가 아는 라인업과 대응하지 않는다.
# 인게임 파일럿 스트립이 같은 이유로 `HudBuilder.LANE_SEAT_ORDER` 를 따로 들고
# 있다 — 이쪽은 그 스트립이 아니라 **필터 버튼과 짝을 이루는** 표다.
const SLOT_ROLES: Array = [
	GameEnums.Role.TANK,      # 탑
	GameEnums.Role.ASSASSIN,  # 정글
	GameEnums.Role.FIGHTER,   # 미드
	GameEnums.Role.SNIPER,    # 원딜
	GameEnums.Role.SUPPORT,   # 서폿
]
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
	return p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental


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


# ─── 카드 후보 풀 (역할이 정한다) ────────────────────────────────────────────
# 파일럿 카드 3장의 **내역은 역할이 가르고**, 그 세 장이 어느 카드가 될지는
# 경기 시작 시 `CardPhaseManager._deal_team_deck` 이 표집한다. 그래서 드래프트
# 시점에 보여 줄 수 있는 것은 확정된 덱이 아니라 **후보 풀**이다 — 슬롯 구성은
# 지금 확정이고 어느 카드가 뽑힐지만 나중에 정해진다.
#
# 아래 표는 `CardPhaseManager._pilot_slots_for` 와 **같은 규칙**이다. 저쪽은
# `PilotData.is_guerrilla`(= 배정된 레인)를 보고 이쪽은 역할을 보는데, 레인이
# 역할에서 유도되므로(ASSASSIN → GUERRILLA) 답이 갈리지 않는다.
static func pilot_card_slots_for_role(role: int) -> Array:
	if role == GameEnums.Role.ASSASSIN:
		return [[CardData.CAT_JUNGLE, 2], [CardData.CAT_DRAW, 1]]
	if role == GameEnums.Role.SUPPORT:
		return [[CardData.CAT_LANE, 1], [CardData.CAT_DRAW, 2]]
	return [[CardData.CAT_LANE, 2], [CardData.CAT_DRAW, 1]]


## 이 역할의 파일럿이 받을 수 있는 **파일럿 카드 후보 전부**, 슬롯 순서대로.
## 랜덤 스타터 덱에 안 들어가는 행(`pool = 0`)과 시전자 제약(`scope`)에 걸리는
## 행은 실제 배분과 같은 자리에서 걸러 낸다 — 화면에 뜬 후보가 실제로는 못
## 받는 카드이면 그 목록은 거짓말이 된다.
func candidate_cards_for_role(role: int) -> Array:
	var is_jungler: bool = role == GameEnums.Role.ASSASSIN
	var out: Array = []
	var seen: Dictionary = {}
	for slot_raw in pilot_card_slots_for_role(role):
		var cat: String = String((slot_raw as Array)[0])
		for def_raw in _gm.card_pool_bs:
			var def: Dictionary = def_raw as Dictionary
			if int(def.get("pool", 1)) == 0:
				continue
			if String(def.get("card_type", "")) != CardData.TYPE_PILOT:
				continue
			var cd := CardData.from_def(def)
			if not cd.allowed_for_guerrilla(is_jungler):
				continue
			if not cd.fits_category(cat):
				continue
			if seen.has(cd.card_name):
				continue
			seen[cd.card_name] = true
			out.append(cd)
	return out


## 이 역할이 받는 슬롯 내역을 사람이 읽는 한 줄로. "라인전 2 · 드로우 1".
static func slot_summary_for_role(role: int) -> String:
	var parts: Array = []
	for slot_raw in pilot_card_slots_for_role(role):
		var slot: Array = slot_raw as Array
		parts.append("%s %d" % [cat_label(String(slot[0])), int(slot[1])])
	return " · ".join(parts)


static func cat_label(cat: String) -> String:
	match cat:
		CardData.CAT_LANE:   return "라인전"
		CardData.CAT_DRAW:   return "드로우"
		CardData.CAT_JUNGLE: return "정글"
	return cat


# ─── 파일럿 스킬 ─────────────────────────────────────────────────────────────
## 이 선수의 고유 스킬 행. 모브(스킬 없음)는 빈 Dictionary 를 돌려준다.
func skill_def_for(p: PlayerData) -> Dictionary:
	if p == null or p.skill_id < 0:
		return {}
	return _gm.skill_def(p.skill_id)


## 스킬 타입 표시명. CSV 의 `cooldown` / `charge` / `passive` 를 그대로 띄우면
## 화면에서 읽히지 않는다.
static func skill_type_label(t: String) -> String:
	match t:
		"cooldown": return "쿨타임"
		"charge":   return "충전식"
		"passive":  return "패시브"
	return t
