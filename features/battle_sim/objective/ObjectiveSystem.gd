class_name ObjectiveSystem
extends Node

# 전장 좌우 중립 칸에 정해진 턴마다 열리는 **오브젝트** — 좌측 전령, 우측 용.
#
# 정글 캠프가 "밟으면 먹는" 수입이라면 오브젝트는 **양 팀이 같은 순간에 같은
# 것을 두고 붙느냐 마느냐를 고르는** 사건이다. 그래서 이 모듈이 하는 일은
# 크게 셋이다.
#
#   1. **시계** — 각 오브젝트가 열리는 턴을 들고 있다가 그 턴이 오면 깨운다.
#      상단 패널의 적 스트립 양옆에 남은 턴 수가 찍히므로(`ui/ObjectiveTimer.gd`,
#      좌 전령 / 우 용) 양 팀 모두 언제 붙게 되는지를 미리 보고 움직일 수 있다.
#   2. **의사 결정** — 플레이어에게는 참여 / 미참여 두 버튼을, AI 에게는 머릿수
#      비교(+ 순위가 정하는 오판 확률)를 물어본다. 결정은 **동시에, 서로
#      모르는 채로** 내려진다.
#   3. **정산** — 양쪽 참여면 교전 무대, 한쪽만 참여면 무혈 획득, 아무도
#      참여하지 않으면 무산.
#
# `BattleSim._ready()` 가 자식으로 붙이고 `_bs.objective` 로 잡는다. 턴 진입점은
# `CardPhaseManager.do_battle_turn()` 하나뿐이다 — `simulate_turn()` 직후,
# 카드 경제와 작전 단계 판정보다 **앞**에 온다("차례와 상관없이 발생한다").


## 두 오브젝트. 값은 `_state` 의 인덱스이기도 하다.
enum Kind { HERALD = 0, DRAGON = 1 }

## 보상 카드의 cards.csv id. 둘 다 `pool = 0` 이라 스타터 덱에는 들어가지 않고
## 오직 여기서만 세상에 나온다.
const HERALD_CARD_ID: int = 32   # 전령 제압 — 보존 + 소멸, 최외곽 포탑에 피해(`turret_damage`)
const DRAGON_CARD_ID: int = 33   # 용 보상   — 소멸, 드로우 + 성장 효율 영구 가산(`growth_perm`)

## 이 오브젝트를 두고 싸우는 **포지션**. 사망한 파일럿은 참여할 수 없으므로,
## 한쪽이 죽어 있으면 그 팀은 그만큼 수적으로 불리한 채로 붙거나 물러나야 한다.
##
## 좌측(전령)은 3인, 우측(용)은 4인이다 — 우측 레인에 서포터와 스나이퍼 둘이
## 서기 때문이고, 그래서 용이 전령보다 큰 사건이다.
const HERALD_LANES: Array = [
	GameEnums.LanePosition.LEFT,
	GameEnums.LanePosition.CENTER,
	GameEnums.LanePosition.GUERRILLA,
]
const DRAGON_LANES: Array = [
	GameEnums.LanePosition.RIGHT,
	GameEnums.LanePosition.CENTER,
	GameEnums.LanePosition.GUERRILLA,
]

## 머릿수에서 빠지는 체력 비율. 이 아래인 파일럿은 무대에 서도 한두 대에
## 쓰러지므로 AI 는 그를 전력으로 세지 않는다(저HP 복귀선과 같은 비율로 둔다).
## 값은 data/csv/const.csv — ConstTable 로 읽는다.
static var AI_HEADCOUNT_HP_RATIO: float = ConstTable.num("OBJ_AI_HEADCOUNT_HP_RATIO")

## 오판 확률 — 수적 열세인데도 교전을 받아들일 확률. `match_ctx` 에
## `enemy_misjudge_chance` 가 없으면(단독 실행) 이 값. MatchFlow 가 리그 순위로
## `OBJ_MISJUDGE_MIN`(1위) ~ `OBJ_MISJUDGE_MAX`(꼴찌)를 매겨 넘긴다.
static var AI_MISJUDGE_DEFAULT: float = ConstTable.num("OBJ_AI_MISJUDGE_DEFAULT")

@onready var _bs: BattleSim = get_parent() as BattleSim

## 오브젝트별 상태. `[{kind, cell, next_turn}]`, 인덱스 = Kind.
var _state: Array = []

## 오브젝트 하나가 결판날 때까지 켜져 있다 — 결정 창이 떠 있는 동안과 교전
## 무대가 도는 동안 모두 포함한다. `BattleSim._process` 가 이 값을 보고 BATTLE
## 자동 틱과 경기 시계를 멈춘다. 교전 무대는 `game_phase = ENGAGE` 로도 틱을
## 멈추지만, **결정 창이 떠 있는 동안은 여전히 BATTLE** 이라 그것만으로는
## 부족하다.
var _busy: bool = false


# ─── 수명 ────────────────────────────────────────────────────────────────────
## `BattleSim` 이 설정값을 읽은 **뒤에** 부른다 — 첫 등장 턴이 game_config 에서
## 오기 때문.
func init_objectives() -> void:
	_state = [
		{
			"kind": Kind.HERALD,
			"cell": SimulationCore.NEUTRAL_LEFT,
			"next_turn": _bs.OBJ_HERALD_FIRST_TURN,
		},
		{
			"kind": Kind.DRAGON,
			"cell": SimulationCore.NEUTRAL_RIGHT,
			"next_turn": _bs.OBJ_DRAGON_FIRST_TURN,
		},
	]
	_busy = false


func is_busy() -> bool:
	return _busy


# ─── 렌더러가 읽는 표시용 상태 ───────────────────────────────────────────────
## `cell` 위에 오브젝트가 있으면 그 `Kind`, 없으면 -1.
func kind_at_cell(cell: Vector2i) -> int:
	for raw in _state:
		if (raw as Dictionary)["cell"] == cell:
			return int((raw as Dictionary)["kind"])
	return -1


## `cell` 의 오브젝트가 열리기까지 남은 턴 수. 오브젝트 칸이 아니면 -1.
## 0 이면 이번 턴에 열린다(표시는 하지 않는다 — 그 자리에 결정 창이 뜬다).
func turns_until_cell(cell: Vector2i) -> int:
	for raw in _state:
		var st: Dictionary = raw as Dictionary
		if st["cell"] != cell:
			continue
		return maxi(0, int(st["next_turn"]) - _bs.turn_count)
	return -1


## 화면에 찍는 이름.
static func kind_name(kind: int) -> String:
	return "전령" if kind == Kind.HERALD else "용"


# ─── 턴 진입점 ───────────────────────────────────────────────────────────────
## 이번 턴에 열릴 오브젝트를 처리한다. `CardPhaseManager.do_battle_turn()` 이
## `simulate_turn()` 직후에 **await** 로 부른다.
##
## 둘이 같은 턴에 열리는지는 game_config 의 `OBJ_HERALD_FIRST_TURN` /
## `OBJ_DRAGON_FIRST_TURN` 과 그 뒤의 `OBJ_RESPAWN_TURNS` · `OBJ_RETRY_TURNS` 에
## 달렸고, 노브를 만지면 언제든 생길 수 있으므로 순서대로 하나씩 끝까지 처리한다 —
## 앞의 것이 끝나야 뒤의 것이 시작하므로 무대가 겹치지 않는다.
func process_turn() -> void:
	if _bs.game_over or _busy or _state.is_empty():
		return
	for raw in _state:
		var st: Dictionary = raw as Dictionary
		if _bs.turn_count < int(st["next_turn"]):
			continue
		await _resolve_objective(st)
		if _bs.game_over:
			return


# ─── 한 오브젝트의 결판 ──────────────────────────────────────────────────────
func _resolve_objective(st: Dictionary) -> void:
	_busy = true
	var kind: int = int(st["kind"])
	var label: String = kind_name(kind)
	var t0: Array = participants_for(kind, 0)
	var t1: Array = participants_for(kind, 1)
	# 용의 가호(파일럿 스킬)는 **용이 열리는 순간** 충전한다 — 이겼는지가
	# 아니라 나타났는지가 조건이라 결판보다 앞에 선다.
	if kind == Kind.DRAGON and _bs.skill != null:
		_bs.skill.on_dragon_spawned()
	_bs.blog.log_event("OBJ", "%s 등장 @%s — 아군 %d명 / 적군 %d명" % [
			label, str(st["cell"]), t0.size(), t1.size()])

	# 참가할 사람이 아예 없는 팀은 물어볼 것도 없다(전원 사망 / 전원 리스폰 중).
	var join0: bool = false
	var join1: bool = false
	if not t1.is_empty():
		join1 = _ai_wants_to_join(t1, t0)
	if not t0.is_empty():
		join0 = await _ask_player(kind, st["cell"], t0, t1)

	if join0 and join1:
		await _run_objective_engage(st, kind, t0, t1)
	elif join0 or join1:
		var winner: int = 0 if join0 else 1
		await _award_uncontested(st, kind, winner, t0, t1)
	else:
		_reschedule(st, _bs.OBJ_RETRY_TURNS)
		_bs.last_log = "[%s] 양 팀 미참여 — %d턴 후 재시도" % [label, _bs.OBJ_RETRY_TURNS]
		_bs.blog.log_event("OBJ", "%s 무산 (양 팀 미참여) — 다음 %d턴"
				% [label, int(st["next_turn"])])
	_busy = false
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


## 양 팀이 모두 참여 — 교전 무대로. 승패는 무대가 끝난 뒤 생존자로 가린다.
func _run_objective_engage(st: Dictionary, kind: int,
		t0: Array, t1: Array) -> void:
	var label: String = kind_name(kind)
	_bs.engage_phase.start_objective_engage(t0, t1, _bs.OBJ_ENGAGE_ROUNDS,
			label, _bs.blue_team, Callable(), st["cell"])
	if not _bs.engage_phase.is_active():
		# 무대가 열리지 않았다(참가자 부족 등) — 무산으로 접는다.
		_reschedule(st, _bs.OBJ_RETRY_TURNS)
		return
	# 종료 배너는 승패를 말해야 하는데 승패는 무대가 끝나야 알 수 있다. 배너는
	# 종료 판정 뒤 `END_HOLD_SEC` 동안 떠 있으므로, 그 사이에 갈아 끼우는 것이
	# 아니라 **판정 자체를 미리 걸어 둘 수 없다** — 대신 무대가 끝난 뒤
	# `last_log` 와 결과 창이 보상을 말한다.
	await _bs.engage_phase.engage_finished
	var winner: int = engage_winner(t0, t1)
	if winner < 0:
		_reschedule(st, _bs.OBJ_RESPAWN_TURNS)
		_bs.last_log = "[%s] 무승부 — 아무도 가져가지 못했다" % label
		_bs.blog.log_event("OBJ", "%s 무승부 — 다음 %d턴" % [label, int(st["next_turn"])])
		return
	await _grant_reward(kind, winner)
	_push_feed(kind, winner, t0 if winner == 0 else t1)
	# 고양감(파일럿 스킬)은 **싸워서 이겼을 때만** 충전한다 — 아무도 안 나와
	# 거저 가져간 경우(`_award_uncontested`)는 "전투에서 승리"가 아니다.
	if _bs.skill != null:
		_bs.skill.on_objective_won(winner)
	if _bs.mech_skill != null:
		_bs.mech_skill.on_objective_win(winner)
	_reschedule(st, _bs.OBJ_RESPAWN_TURNS)
	var side: String = "아군" if winner == 0 else "적군"
	_bs.last_log = "[%s] %s 획득 · %s" % [label, side, reward_text(kind)]
	_bs.blog.log_event("OBJ", "%s → team%d (교전 승리) · %s · 다음 %d턴"
			% [label, winner, reward_text(kind), int(st["next_turn"])])


## 한쪽만 참여 — 전투 없이 그 팀이 가져간다. 결과 창을 한 번 띄운다(플레이어가
## 물러난 경우에도 무엇을 내줬는지는 봐야 한다).
func _award_uncontested(st: Dictionary, kind: int, winner: int,
		t0: Array, t1: Array) -> void:
	var label: String = kind_name(kind)
	# 무혈 획득도 킬로그에 오른다 — 아무도 안 나와 거저 가져간 것이야말로
	# 그 순간 화면에 아무 일도 일어나지 않는 경우라, 자국이 더 필요하다.
	_push_feed(kind, winner, t0 if winner == 0 else t1)
	if _bs.mech_skill != null:
		_bs.mech_skill.on_objective_win(winner)
	_reschedule(st, _bs.OBJ_RESPAWN_TURNS)
	var side: String = "아군" if winner == 0 else "적군"
	_bs.last_log = "[%s] %s 무혈 획득 · %s" % [label, side, reward_text(kind)]
	_bs.blog.log_event("OBJ", "%s → team%d (무혈) · %s · 다음 %d턴"
			% [label, winner, reward_text(kind), int(st["next_turn"])])
	# 플레이어가 결정에 참여하지 않았다면(참가 가능한 파일럿이 아무도 없었다)
	# 알림 창도 띄우지 않는다 — 고른 적 없는 결과에 확인을 누르게 할 이유가 없다.
	#
	# **지급(과 그 연출)은 이 창을 닫은 뒤에 온다** — 알림 위에 보상 카드가
	# 겹쳐 날아다니면 어느 쪽을 보라는 화면인지가 흐려진다.
	if not t0.is_empty():
		_bs.engage_phase.prepare_sim(null, t0, t1, _bs.OBJ_ENGAGE_ROUNDS,
				false, _bs.blue_team, st["cell"])
		await _bs.engage_phase.prompt_engage(t0, t1, _bs.OBJ_ENGAGE_ROUNDS,
				"%s — %s 무혈 획득" % [label, side], false,
				"확인", "", reward_text(kind))
	await _grant_reward(kind, winner)


## 이번 교전의 승자. **생존 인원 수 → 동률이면 잔여 HP 비율 합**.
## 둘 다 같으면 -1(무승부, 아무도 가져가지 못한다).
##
## 비율 합을 쓰는 이유는 체력 총량이 역할마다 크게 다르기 때문이다 — 탱커와
## 스나이퍼의 체력을 절대값으로 더하면 "탱커가 살아 있는 쪽"이 언제나
## 이긴다. 비율이면 각자 자기 몫만큼만 낸다.
## **결과 화면도 이 함수를 읽는다** — 무대가 닫히기 전에 뜨는 승리 / 패배
## 글자와 실제로 보상을 가져가는 팀이 갈릴 수 없어야 한다(둘 사이에 상태가
## 바뀌지 않으므로 같은 답이 나온다).
func engage_winner(t0: Array, t1: Array) -> int:
	var alive0: int = _alive_count(t0)
	var alive1: int = _alive_count(t1)
	if alive0 != alive1:
		return 0 if alive0 > alive1 else 1
	var r0: float = _hp_ratio_sum(t0)
	var r1: float = _hp_ratio_sum(t1)
	if absf(r0 - r1) > 0.001:
		return 0 if r0 > r1 else 1
	return -1


# ─── 참가자 ──────────────────────────────────────────────────────────────────
## `kind` 오브젝트에 `team` 이 내보낼 수 있는 파일럿들 — 포지션이 맞고 **살아
## 있는** 사람뿐이다. 사망자는 참여할 수 없으므로 그만큼 수적으로 밀린다.
##
## 이 함수 하나가 결정 창의 명단과 실제 무대에 오르는 명단을 함께 정한다.
func participants_for(kind: int, team: int) -> Array:
	var lanes: Array = HERALD_LANES if kind == Kind.HERALD else DRAGON_LANES
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != team:
			continue
		if not lanes.has(p.lane):
			continue
		# 위치 고정(파일럿 스킬)을 건 파일럿은 오브젝트에 못 낀다 — 그 스킬이
		# 파는 것이 "라인에 눌러앉아 파밍만 한다"이므로 여기 나오면 대가가 없다.
		if _bs.skill != null and _bs.skill.blocks_objective(p):
			continue
		out.append(p)
	return out


# ─── 의사 결정 ───────────────────────────────────────────────────────────────
## 플레이어에게 참여 / 미참여를 묻는다. VS 화면을 그대로 재사용하되 버튼 문구만
## 바뀐다 — 명단을 보고 두 갈래 중 하나를 고르는 결정이라 화면의 모양이 같다.
##
## **상대의 결정은 보여 주지 않는다.** AI 는 이 창이 뜨기 전에 이미 결정을
## 내렸지만, 그것을 알려 주면 "적이 물러났으니 나도 그냥 먹으면 된다"가 되어
## 결정이 아니라 확인 절차가 된다.
func _ask_player(kind: int, cell: Vector2i, t0: Array, t1: Array) -> bool:
	var label: String = kind_name(kind)
	var title: String = "%s 등장 — 전투에 참여하시겠습니까?" % label
	# 무대를 먼저 세운다 — 오브젝트 칸을 한가운데 두면 참가자들이 지금 서 있는
	# 타일이 그대로 배치가 된다. 누가 어디서 달려오는지를 보고 참여를 정하는
	# 것이 이 창의 질문이므로 명단만으로는 부족하다. 선공은 무대와 같은 블루다.
	_bs.engage_phase.prepare_sim(null, t0, t1, _bs.OBJ_ENGAGE_ROUNDS, false,
			_bs.blue_team, cell)
	return await _bs.engage_phase.prompt_engage(t0, t1, _bs.OBJ_ENGAGE_ROUNDS,
			title, true, "참여", "미참여", reward_text(kind))


## AI 의 참여 판단. **전력 차이(체력 · 공격력 · 성장치)는 보지 않고 머릿수만
## 센다** — 수적 열세일 때만 물러나고, 같거나 많으면 붙는다. 체력이
## `AI_HEADCOUNT_HP_RATIO` 미만인 파일럿은 양 팀 모두 머릿수에서 뺀다.
##
## 물러나야 할 때도 `enemy_misjudge_chance` 확률로 **오판**해 받아들인다 —
## 하위권 팀일수록 자주(`OBJ_MISJUDGE_MAX` 까지), 상위권일수록 드물게(`OBJ_MISJUDGE_MIN` 까지).
##
## 상대가 아무도 못 나오는 상황이면 무조건 참여한다(공짜 보상).
func _ai_wants_to_join(mine: Array, theirs: Array) -> bool:
	if theirs.is_empty():
		return true
	var n_mine: int = _headcount(mine)
	var n_theirs: int = _headcount(theirs)
	if n_mine >= n_theirs:
		_bs.blog.log_event("OBJ", "AI 머릿수 %d vs %d → 참여" % [n_mine, n_theirs])
		return true
	var chance: float = _misjudge_chance()
	var misjudged: bool = randf() < chance
	_bs.blog.log_event("OBJ", "AI 머릿수 %d vs %d (열세) · 오판 %.0f%% → %s"
			% [n_mine, n_theirs, chance * 100.0,
				"오판, 참여" if misjudged else "미참여"])
	return misjudged


func _headcount(group: Array) -> int:
	var n: int = 0
	for raw in group:
		var p := raw as PilotData
		if not p.alive or p.max_hp <= 0:
			continue
		if float(p.hp) / float(p.max_hp) >= AI_HEADCOUNT_HP_RATIO:
			n += 1
	return n


func _misjudge_chance() -> float:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or not bool(gm.match_ctx.get("active", false)):
		return AI_MISJUDGE_DEFAULT
	return float(gm.match_ctx.get("enemy_misjudge_chance", AI_MISJUDGE_DEFAULT))


func _alive_count(group: Array) -> int:
	var n: int = 0
	for raw in group:
		if (raw as PilotData).alive:
			n += 1
	return n


func _hp_ratio_sum(group: Array) -> float:
	var total: float = 0.0
	for raw in group:
		var p := raw as PilotData
		if not p.alive or p.max_hp <= 0:
			continue
		total += float(p.hp) / float(p.max_hp)
	return total


# ─── 보상 ────────────────────────────────────────────────────────────────────
## 화면과 로그에 함께 쓰는 보상 한 줄.
func reward_text(kind: int) -> String:
	if kind == Kind.HERALD:
		return "보상: [전령 제압] — 최외곽 적 포탑에 피해 %d" % _card_clause_int(HERALD_CARD_ID, "turret_damage")
	return "보상: [용 보상] ×%d 를 덱에 추가" % _bs.OBJ_DRAGON_CARD_COUNT


## 카드 `effect` 에서 절 하나의 수치를 읽는다(`turret_damage:N` → N). 보상 안내가
## 카드 효과와 따로 놀지 않도록 **카드 행이 유일한 원본**이다 — 예전의
## `OBJ_HERALD_TURRET_DMG`(game_config)는 그래서 삭제됐다. 절이 없으면 0.
func _card_clause_int(card_id: int, clause: String) -> int:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return 0
	var def: Dictionary = gm.card_def(card_id)
	for part in String(def.get("effect", "")).split(";", false):
		var kv: PackedStringArray = (part as String).strip_edges().split(":")
		if kv.size() >= 2 and kv[0] == clause:
			return int(kv[1])
	return 0


## 전령은 카드 한 장을 **손패로 곧장**(보존 키워드라 버려지지 않는다), 용은
## 카드 다섯 장을 **덱에 섞어서**. 둘의 차이가 곧 두 오브젝트의 성격이다 —
## 전령은 지금 당장 쓸 한 방, 용은 경기 내내 천천히 도는 성장 이득.
##
## **지급보다 연출이 먼저다**(`objective/ObjectiveRewardFx.gd`) — 보상 카드를
## 화면 한가운데에 펼쳐 보여 준 뒤 들어갈 자리로 날려 보내고, 그 비행이 끝난
## 자리에서 실제로 넣는다. 순서를 뒤집으면 연출이 도는 동안 이미 손패에 같은
## 카드가 서 있어 한 장이 두 군데에 보인다. 그래서 이 함수는 코루틴이고,
## 부르는 두 곳(`_run_objective_engage` / `_award_uncontested`)이 await 한다.
func _grant_reward(kind: int, team: int) -> void:
	var is_player: bool = team == 0
	# 오브젝트는 양 팀이 같은 자리로 모이는 약속이라 결과가 어느 쪽으로 갔는지가
	# 곧 사건이다 — 여기만 승/패를 감촉으로 가른다.
	Haptics.play(Haptics.Kind.SUCCESS if is_player else Haptics.Kind.WARNING)
	var to_deck: bool = kind != Kind.HERALD
	var card_id: int = HERALD_CARD_ID if kind == Kind.HERALD else DRAGON_CARD_ID
	var count: int = 1 if kind == Kind.HERALD else int(_bs.OBJ_DRAGON_CARD_COUNT)
	if _bs.objective_fx != null:
		await _bs.objective_fx.play(card_id, is_player, count, to_deck)
	if to_deck:
		_bs.card_phase.grant_cards_to_deck(card_id, is_player, count)
	else:
		# 연출이 카드를 손패 **맨 왼쪽**으로 날려 보내고 끝나므로 삽입도 그 자리다.
		_bs.card_phase.grant_cards_to_hand(card_id, is_player, count, true)


# ─── 킬로그 ──────────────────────────────────────────────────────────────────
## 오브젝트 획득 한 줄. **대표는 정글러**다 — 전령도 용도 양 팀 정글러가 언제나
## 참가자이고 오브젝트를 도는 것 자체가 정글의 일이라, 한 얼굴로 "누가
## 가져갔나"를 말해야 한다면 그 자리는 정글러다. 정글러가 못 나왔으면(사망 ·
## 위치 고정 스킬) 남은 참가자 중 첫 사람이 그 자리에 서고, 나머지는 전부
## 어시스트로 붙는다.
##
## 명단은 **참여를 고른 팀의 참가자**다(`participants_for` 가 준 그 배열).
## 교전 중에 쓰러진 사람도 그대로 남는다.
func _push_feed(kind: int, winner: int, group: Array) -> void:
	if _bs.kill_feed == null:
		return
	var ordered: Array = _feed_order(group)
	if ordered.is_empty():
		_bs.kill_feed.push_objective(kind, null, [], winner)
		return
	_bs.kill_feed.push_objective(kind, ordered[0] as PilotData,
			ordered.slice(1), winner)


## 정글러를 맨 앞으로 당긴 참가자 순서. 나머지는 `participants_for` 가 준
## 순서(= 스폰 순서) 그대로다.
func _feed_order(group: Array) -> Array:
	var out: Array = []
	for raw in group:
		if (raw as PilotData).lane == GameEnums.LanePosition.GUERRILLA:
			out.append(raw)
	for raw in group:
		if (raw as PilotData).lane != GameEnums.LanePosition.GUERRILLA:
			out.append(raw)
	return out


# ─── 시계 ────────────────────────────────────────────────────────────────────
## 다음 등장 턴을 **지금 턴 기준**으로 다시 찍는다. 결판이 났으면
## `OBJ_RESPAWN_TURNS`, 양 팀 미참여로 무산됐으면 더 짧은 `OBJ_RETRY_TURNS`.
func _reschedule(st: Dictionary, delay: int) -> void:
	st["next_turn"] = _bs.turn_count + maxi(1, delay)
