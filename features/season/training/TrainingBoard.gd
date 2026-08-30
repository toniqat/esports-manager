class_name TrainingBoard
extends Node

# 주간 훈련판의 **머리 없는 본체**. 화면(TrainingView)은 이 노드에 배치를
# 물어보고 이 노드에 배치를 시킨다 — 판정과 정산이 화면에 흩어져 있으면
# "화면에 보이는 판"과 "실제로 적용되는 판"이 갈라진다.
#
# ── 판 ───────────────────────────────────────────────────────────────────────
# **5열(선수) × 5행(요일)**. 열은 `GameEnums.ROLE_DISPLAY_ORDER` 자리 순서
# (탑 · 정글 · 미드 · 원딜 · 서폿), 행은 월~금이다. 토·일은 판에 없다 —
# 그 이틀은 경기 주말이라 훈련이 아니다(예전 7일 격자의 금·토·일 MATCH 잠금이
# 하던 일을 판 크기 자체가 대신한다).
#
# ── 저장 ─────────────────────────────────────────────────────────────────────
# `season_state["training_board"]` = Array of `{tile, x, y}`.
# `x` = 선수 자리(0..4), `y` = 요일(0..4), `tile` = `training_tiles.id`.
# **빈 칸은 적지 않는다** — 정산할 때 기본 코스(`FILLER_TILE_ID`)가 자동으로
# 메우므로 "아무것도 안 놓은 판"과 "기본으로 도배한 판"이 같은 결과를 낸다.

const COLS: int = 5          # 선수
const ROWS: int = 5          # 월~금
const DAY_NAMES: Array = ["월", "화", "수", "목", "금"]

## 빈 칸을 메우는 기본 코스. 이 id 가 CSV 에 없으면 빈 칸은 그냥 0 이 된다.
const FILLER_TILE_ID: String = "T01"

## **EXP 는 스탯 포인트가 아니다** — 이만큼 모여야 스탯이 1 오른다. 그래야
## 타일 표에 세 자리 수를 적어도 스탯이 한 주에 백 단위로 튀지 않는다.
##
## 남은 나머지는 **주 안에서만** 이월된다(`season_state["training_exp_carry"]`,
## 아래 `apply_day_training`). 예전에는 그냥 버렸는데 — 정산이 주 1회였으므로
## 버려도 한 주에 한 번뿐이었다 — 정산이 요일 단위로 쪼개지면서 그러면
## 하루 30 EXP 짜리 판이 닷새 내내 매일 0 점이 되어 한 주에 한 점도 안 오른다.
## 통장은 주가 시작될 때 비우므로 주를 넘겨 쌓이지 않는다.
const EXP_PER_POINT: int = 40

@onready var _gm: Node = get_node("/root/GameManager")

var _tile_cache: Dictionary = {}     # tile_id → TrainingTile


# ── 타일 조회 ────────────────────────────────────────────────────────────────
## 인벤토리에 늘어놓을 타일 전부. CSV 순서(= 등급 순서)를 유지한다.
func all_tiles() -> Array:
	var out: Array = []
	for def in _gm.training_tiles:
		var t: TrainingTile = tile(String((def as Dictionary)["id"]))
		if t != null:
			out.append(t)
	return out


## id 로 타일 하나. 캐시하는 이유는 판을 한 번 정산할 때 같은 타일을 스물몇 번
## 물어보기 때문이다 — 매번 문법을 다시 파싱하면 정산이 통째로 파서가 된다.
func tile(tile_id: String) -> TrainingTile:
	if _tile_cache.has(tile_id):
		return _tile_cache[tile_id]
	var def: Dictionary = _gm.training_tile_def(tile_id)
	if def.is_empty():
		return null
	var t: TrainingTile = TrainingTile.from_def(def)
	_tile_cache[tile_id] = t
	return t


# ── 판 상태 ──────────────────────────────────────────────────────────────────
func board() -> Array:
	if not _gm.season_state.has("training_board"):
		_gm.season_state["training_board"] = []
	return _gm.season_state["training_board"]


func clear_board() -> void:
	_gm.season_state["training_board"] = []


## 배치 하나가 덮는 절대 칸들.
func cells_of(entry: Dictionary) -> Array:
	var t: TrainingTile = tile(String(entry.get("tile", "")))
	if t == null:
		return []
	var ox: int = int(entry.get("x", 0))
	var oy: int = int(entry.get("y", 0))
	var out: Array = []
	for c in t.cells:
		out.append(Vector2i(ox + (c as Vector2i).x, oy + (c as Vector2i).y))
	return out


## 칸 → 그 칸을 덮은 배치의 인덱스. 없으면 키가 없다. 판이 25칸뿐이라 매번
## 훑어도 되지만, 히트 테스트와 그리기가 같은 표를 읽어야 화면에 보이는 타일과
## 잡히는 타일이 갈라지지 않는다.
func occupancy() -> Dictionary:
	var occ: Dictionary = {}
	var b: Array = board()
	for i in b.size():
		for c in cells_of(b[i]):
			occ[c] = i
	return occ


## 그 등급이 판에 몇 장 올라가 있는가.
func placed_count_of_grade(grade: int) -> int:
	var n: int = 0
	for e in board():
		var t: TrainingTile = tile(String((e as Dictionary).get("tile", "")))
		if t != null and t.grade == grade:
			n += 1
	return n


## 그 타일을 지금 한 장 더 놓을 수 있는가 — **등급 상한만** 본다(자리는 별개).
## 타일은 몇 번이든 다시 쓸 수 있으므로(보유 수량이 없다) 이 상한 하나가
## "가장 센 타일로 도배"를 막는 유일한 장치다.
func grade_slot_free(t: TrainingTile, ignore_entry: int = -1) -> bool:
	if t == null:
		return false
	var limit: int = t.place_limit()
	if limit < 0:
		return true
	var n: int = 0
	var b: Array = board()
	for i in b.size():
		if i == ignore_entry:
			continue
		var other: TrainingTile = tile(String((b[i] as Dictionary).get("tile", "")))
		if other != null and other.grade == t.grade:
			n += 1
	return n < limit


## `origin` 에 그 타일을 놓을 수 있는가. `ignore_entry` 는 **자기 자신을 옮기는
## 중일 때** 그 배치를 없는 셈 치라는 뜻이다 — 안 그러면 한 칸 옆으로 미는
## 이동이 언제나 "겹친다"로 거절된다.
func can_place(t: TrainingTile, origin: Vector2i, ignore_entry: int = -1) -> bool:
	if t == null:
		return false
	if not grade_slot_free(t, ignore_entry):
		return false
	var occ: Dictionary = {}
	var b: Array = board()
	for i in b.size():
		if i == ignore_entry:
			continue
		for c in cells_of(b[i]):
			occ[c] = true
	for c2 in t.cells:
		var at := Vector2i(origin.x + (c2 as Vector2i).x, origin.y + (c2 as Vector2i).y)
		if at.x < 0 or at.x >= COLS or at.y < 0 or at.y >= ROWS:
			return false
		if occ.has(at):
			return false
	return true


## 놓는다. 놓였으면 그 배치의 인덱스, 못 놓으면 -1.
func place(tile_id: String, origin: Vector2i) -> int:
	var t: TrainingTile = tile(tile_id)
	if not can_place(t, origin):
		return -1
	var b: Array = board()
	b.append({"tile": tile_id, "x": origin.x, "y": origin.y})
	return b.size() - 1


## 그 칸을 덮은 배치를 걷어 낸다. 걷어 냈으면 그 배치 Dictionary, 없으면 빈 것.
func remove_at(cell: Vector2i) -> Dictionary:
	var b: Array = board()
	for i in range(b.size() - 1, -1, -1):
		if cell in cells_of(b[i]):
			var e: Dictionary = b[i]
			b.remove_at(i)
			return e
	return {}


func remove_entry(idx: int) -> Dictionary:
	var b: Array = board()
	if idx < 0 or idx >= b.size():
		return {}
	var e: Dictionary = b[idx]
	b.remove_at(idx)
	return e


# ── 정산 ─────────────────────────────────────────────────────────────────────
# 3단계다. (1) 칸마다 기본 EXP 를 깐다 — 빈 칸은 기본 코스로 메운다.
# (2) 절을 전부 훑어 **배율 표**와 **가산 표**를 따로 쌓는다. (3) 둘을 칸마다
# 적용해 선수별 합계를 낸다.
#
# 배율을 EXP 와 같은 패스에서 곱하지 않는 것이 요점이다 — 그러면 절이 도는
# 순서가 결과를 바꾼다("왼쪽 칸 ×0.5" 뒤에 "그 칸 +100" 이 오면 100 이 안 깎인다).
# 두 표를 다 모은 뒤 한 번에 적용하면 배치가 같으면 결과도 언제나 같다.
#
# 배율은 **곱해서 쌓인다**(120% 둘이면 144%) — 더하기로 쌓으면 증폭 타일 셋만
# 붙여 놓아도 배율이 선형으로 폭주한다.

## 판을 정산한 결과. `{seat: {stat: int}}` — seat 는 0..4 자리 번호이고 값은
## **EXP** 다(스탯 포인트가 아니다 — `EXP_PER_POINT` 로 나눠야 포인트가 된다).
## 한 주 전체(월~금 다섯 줄)의 합이다 — 훈련 계획 화면의 미리보기가 쓴다.
func compute_gains() -> Dictionary:
	return _fold_cells(cell_exp(), -1)


## 한 요일(판의 한 **줄**)만 정산한 결과. 같은 모양 `{seat: {stat: int}}`.
##
## **자기 줄만 다시 계산하지 않는다** — 절의 스코프는 요일을 넘나들므로
## (`day_next` · `day_prev_all` · `mate_all`) 수요일 타일이 목요일 칸에 건 배율은
## 목요일을 정산할 때 살아 있어야 한다. 그래서 칸 표는 **판 전체로 한 번** 만들고
## 접는 단계에서만 줄을 고른다 — 그러면 요일 다섯의 합이 `compute_gains()` 와
## 한 EXP 도 어긋날 수 없다.
func compute_day_gains(day: int) -> Dictionary:
	return _fold_cells(cell_exp(), day)


## 칸별 최종 EXP 표. `Vector2i(seat, day) → {stat: int}`.
func cell_exp() -> Dictionary:
	var base: Dictionary = {}      # Vector2i → {stat: int}
	var mult: Dictionary = {}      # Vector2i → float
	var bonus: Dictionary = {}     # Vector2i → {stat: int}
	for x in COLS:
		for y in ROWS:
			var c := Vector2i(x, y)
			base[c] = {}
			mult[c] = 1.0
			bonus[c] = {}

	# (1) 놓인 타일의 칸 EXP
	var covered: Dictionary = {}
	var b: Array = board()
	for e_raw in b:
		var e: Dictionary = e_raw
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null:
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		for i in t.cells.size():
			var at := Vector2i(ox + (t.cells[i] as Vector2i).x,
					oy + (t.cells[i] as Vector2i).y)
			if not base.has(at):
				continue
			covered[at] = true
			_add_stats(base[at], t.exp_of_cell(i))

	# 빈 칸은 기본 코스가 메운다 — "아무것도 안 놓은 판"과 "기본으로 도배한
	# 판"이 같은 결과를 내야 판을 비워 두는 것이 손해가 아니게 된다.
	var filler: TrainingTile = tile(FILLER_TILE_ID)
	if filler != null:
		for x2 in COLS:
			for y2 in ROWS:
				var c2 := Vector2i(x2, y2)
				if not covered.has(c2):
					_add_stats(base[c2], filler.exp_of_cell(0))

	# (2) 절 수집
	for e_raw2 in b:
		var e2: Dictionary = e_raw2
		var t2: TrainingTile = tile(String(e2.get("tile", "")))
		if t2 == null or t2.clauses.is_empty():
			continue
		var own: Array = cells_of(e2)
		for cl_raw in t2.clauses:
			var cl: Dictionary = cl_raw
			for c3 in _scope_cells(String(cl["scope"]), own):
				if not base.has(c3):
					continue
				if String(cl["kind"]) == "mult":
					mult[c3] = float(mult[c3]) * (float(int(cl["pct"])) / 100.0)
					continue
				var stat_key: String = String(cl["stat"])
				var amount: int = int(cl["amount"])
				if stat_key == "all":
					for sk in PlayerData.STAT_KEYS:
						_add_one(bonus[c3], String(sk), amount)
				else:
					_add_one(bonus[c3], stat_key, amount)

	# (3) 칸마다 배율 · 가산을 적용해 굳힌다. **반올림은 칸 단위로 한 번만**
	# 한다 — 여기서 굳혀 두어야 "요일 다섯의 합"과 "한 주 한 번"이 같은 수가 된다.
	var out: Dictionary = {}
	for seat in COLS:
		for day in ROWS:
			var c4 := Vector2i(seat, day)
			var m: float = maxf(0.0, float(mult[c4]))
			var cell_base: Dictionary = base[c4]
			var cell_bonus: Dictionary = bonus[c4]
			var acc: Dictionary = {}
			for sk3 in PlayerData.STAT_KEYS:
				var key: String = String(sk3)
				var v: float = float(int(cell_base.get(key, 0))) * m
				v += float(int(cell_bonus.get(key, 0)))
				acc[key] = int(round(v))
			out[c4] = acc
	return out


## 칸 표를 자리별로 접는다. `day < 0` 이면 다섯 줄 전부, 아니면 그 줄만.
static func _fold_cells(cells: Dictionary, day: int) -> Dictionary:
	var out: Dictionary = {}
	for seat in COLS:
		var acc: Dictionary = {}
		for sk in PlayerData.STAT_KEYS:
			acc[String(sk)] = 0
		for d in ROWS:
			if day >= 0 and d != day:
				continue
			var cell: Dictionary = cells.get(Vector2i(seat, d), {})
			for sk2 in PlayerData.STAT_KEYS:
				var key: String = String(sk2)
				acc[key] = int(acc[key]) + int(cell.get(key, 0))
		out[seat] = acc
	return out


## 이 타일을 `origin` 에 놓으면 **자기 칸 말고 어느 칸이 영향을 받는가.**
## 절 전부의 스코프를 합집합으로 모은다. 드래그 중 판에 노란 표시를 그리는
## 쪽(`TrainingView._draw_grid`)과 정산(`compute_gains`)이 **같은 `_scope_cells`
## 를 지나므로** 화면에 뜬 칸과 실제로 배율 · 가산을 받는 칸이 갈릴 수 없다.
## 절이 없는 타일은 빈 배열이라 표시 자체가 안 뜬다 — 남에게 아무 일도 안 하는
## 타일에 "영향 범위" 를 그리면 그 표시가 무엇을 뜻하는지가 흐려진다.
func affected_cells(t: TrainingTile, origin: Vector2i) -> Array:
	if t == null or t.clauses.is_empty():
		return []
	var own: Array = []
	for c_raw in t.cells:
		var c: Vector2i = c_raw
		own.append(Vector2i(origin.x + c.x, origin.y + c.y))
	var out: Dictionary = {}
	for cl_raw in t.clauses:
		var cl: Dictionary = cl_raw
		for c2 in _scope_cells(String(cl["scope"]), own):
			out[c2] = true
	return out.keys()


## 스코프 하나가 가리키는 칸들. **자기 타일이 덮은 칸은 어느 스코프에도 안
## 들어간다** — 배율이 자기 자신에게 걸리면 절이 아니라 그냥 EXP 를 그만큼 더
## 적으면 되는 값이고, 여러 칸 타일에서는 한 칸이 다른 칸에 배율을 걸어
## 배치와 무관한 자기 증폭이 생긴다.
func _scope_cells(scope: String, own: Array) -> Array:
	var own_set: Dictionary = {}
	for c in own:
		own_set[c] = true
	var out: Dictionary = {}
	for c_raw in own:
		var c: Vector2i = c_raw
		match scope:
			"self":
				out[c] = true
			"day_next":
				_put(out, Vector2i(c.x, c.y + 1), own_set)
			"day_prev":
				_put(out, Vector2i(c.x, c.y - 1), own_set)
			"day_all":
				for y in ROWS:
					_put(out, Vector2i(c.x, y), own_set)
			"day_prev_all":
				for y2 in range(0, c.y):
					_put(out, Vector2i(c.x, y2), own_set)
			"day_next_all":
				for y3 in range(c.y + 1, ROWS):
					_put(out, Vector2i(c.x, y3), own_set)
			"mate_left":
				_put(out, Vector2i(c.x - 1, c.y), own_set)
			"mate_right":
				_put(out, Vector2i(c.x + 1, c.y), own_set)
			"mate_all":
				for x in COLS:
					_put(out, Vector2i(x, c.y), own_set)
	return out.keys()


func _put(out: Dictionary, c: Vector2i, own_set: Dictionary) -> void:
	if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
		return
	if own_set.has(c):
		return
	out[c] = true


static func _add_stats(acc: Dictionary, add: Dictionary) -> void:
	for k in add.keys():
		_add_one(acc, String(k), int(add[k]))


static func _add_one(acc: Dictionary, key: String, amount: int) -> void:
	acc[key] = int(acc.get(key, 0)) + amount


# ── 적용 ─────────────────────────────────────────────────────────────────────
# **훈련은 요일 단위로 먹는다.** 예전에는 `apply_week_training()` 한 번이 한 주를
# 통째로 정산했는데, 시간 경과 화면이 "그날 무슨 일이 있었는가"를 요일마다
# 물으면서 정산도 요일로 쪼개졌다.
#
# 쪼개면서 생기는 유일한 함정이 **나머지**다. EXP 40 이 스탯 1 인데 요일마다
# 따로 나누면 하루 30 씩 다섯 번(=150, 주간이면 3점)이 매일 0점이 되어 한 주에
# 한 점도 안 오른다. 그래서 나머지를 버리지 않고 `season_state["training_exp_carry"]`
# 에 얹어 다음 날로 넘긴다 — 그러면 다섯 날의 합이 한 주 한 번과 정확히 같다.
# 통장은 **주가 시작될 때 비운다**(`reset_week_progress`) — 주를 넘겨 쌓이면
# 판을 비워 둔 주가 지난주 나머지로 스탯을 올린다.

## 나머지 EXP 통장. `{seat(int): {stat: int}}`.
func exp_carry() -> Dictionary:
	if not _gm.season_state.has("training_exp_carry"):
		_gm.season_state["training_exp_carry"] = {}
	return _gm.season_state["training_exp_carry"]


## 하루치 훈련을 플레이어 팀에 실제로 먹인다. `day` 는 0..4(월~금).
## 시간 경과 화면이 읽는 줄 목록을 돌려준다 — 자리 순서(탑 · 정글 · 미드 ·
## 원딜 · 서폿)대로 늘어선 `Array[{pilot_id, name, role, seat, before, after,
## ups, exp, carry}]`. `ups` 는 이번 날 실제로 오른 포인트, `exp` 는 그날 번
## EXP, `carry` 는 정산 **뒤에** 통장에 남은 나머지다.
##
## `carry` 를 줄에 실어 보내는 것은 화면 때문이다 — 기초 코스만 깔린 판에서는
## 하루 EXP 가 40 에 못 미쳐 월~목이 전부 `+0` 으로 보이고 금요일에 한꺼번에
## 오른다(실측: 5일에 스탯 총합 +6). 그날 아무 일도 안 일어난 것처럼 보이면
## 요일별 정산이 하는 일이 화면에 없는 셈이라, 오른 포인트가 0 인 칸은
## `carry / EXP_PER_POINT` 로 "다음 한 점까지"를 보여 준다.
##
## 스탯에는 **상한이 없다** — `PlayerData.STAT_MIN` 하한만 지킨다. 명중 넷은
## 비율로 읽히고(`PilotData.hit_chance`) 성장 계수 둘은 배율이라, 100 을 넘겨도
## 계산이 무너지지 않는다.
func apply_day_training(day: int) -> Array:
	var gains: Dictionary = compute_day_gains(day)
	var pilots: Array = player_pilots_by_seat()
	var carry: Dictionary = exp_carry()
	var rows: Array = []
	for seat in COLS:
		var p: PlayerData = pilots[seat]
		if p == null:
			continue
		var before: Dictionary = snapshot(p)
		var g: Dictionary = gains.get(seat, {})
		var pocket: Dictionary = carry.get(seat, {})
		var ups: Dictionary = {}
		var exp: Dictionary = {}
		for sk in PlayerData.STAT_KEYS:
			var key: String = String(sk)
			var earned: int = int(g.get(key, 0))
			var total: int = int(pocket.get(key, 0)) + earned
			@warning_ignore("integer_division")
			var up: int = total / EXP_PER_POINT
			pocket[key] = total - up * EXP_PER_POINT
			exp[key] = earned
			ups[key] = up
			if up != 0:
				p.set(key, maxi(PlayerData.STAT_MIN, int(p.get(key)) + up))
		carry[seat] = pocket
		rows.append({
			"pilot_id": int(p.id), "name": p.name, "role": int(p.role),
			"seat": seat, "before": before, "after": snapshot(p),
			"ups": ups, "exp": exp, "carry": pocket.duplicate(),
		})
	return rows


## 이번 판을 그대로 돌렸을 때의 예상 최종 스탯. 화면의 미리보기가 쓴다 —
## 요일 정산(`apply_day_training`)과 **같은 칸 표**(`cell_exp`)를 지나므로
## 미리 본 수치와 한 주 동안 실제로 오르는 수치가 갈릴 수 없다 — 다만
## 나머지 EXP 통장 때문에 **주 중간에는** 이보다 덜 올라 있을 수 있다.
##
## `gains` 를 인자로 받는 것은 다섯 자리를 그리는 동안 판을 다섯 번 다시
## 정산하지 않기 위해서다 — 화면이 한 번 계산해 다섯 번 나눠 쓴다.
func projected_stats(p: PlayerData, seat: int, gains: Dictionary) -> Dictionary:
	var stats: Dictionary = snapshot(p)
	var g: Dictionary = gains.get(seat, {})
	for sk in PlayerData.STAT_KEYS:
		var key: String = String(sk)
		@warning_ignore("integer_division")
		var up: int = int(g.get(key, 0)) / EXP_PER_POINT
		stats[key] = maxi(PlayerData.STAT_MIN, int(stats[key]) + up)
	return stats


static func snapshot(p: PlayerData) -> Dictionary:
	var d: Dictionary = {}
	for sk in PlayerData.STAT_KEYS:
		d[String(sk)] = int(p.get(String(sk)))
	return d


## 플레이어 팀 다섯 명을 **화면 자리 순서**(탑 · 정글 · 미드 · 원딜 · 서폿)로.
## 판의 열 번호가 곧 이 인덱스다 — 화면 · 정산 · 적용이 같은 표를 쓰지 않으면
## 엉뚱한 선수의 훈련이 바뀐다.
func player_pilots_by_seat() -> Array:
	var pool: Array = _gm.season_state["all_pilots"]
	var pid: int = int(_gm.season_state["player_team_id"])
	var by_seat: Array = [null, null, null, null, null]
	for raw in pool:
		var p := raw as PlayerData
		if p.team_id == pid and p.role >= 0 and p.role < 5:
			by_seat[GameEnums.role_seat(int(p.role))] = p
	return by_seat


## 한 주가 끝나면 판을 비운다. 예전 `TrainingScheduler.refill_player_team_defaults`
## 자리 — 기본 코스로 미리 채우지 않는 것은 빈 칸이 이미 기본 코스로 정산되기
## 때문이고, 비어 있어야 "이번 주에 내가 놓은 것"이 한눈에 보인다.
func reset_for_new_week() -> void:
	clear_board()
	reset_week_progress()


## 주 진행 상태(요일 커서 · 요일별 결과 기록 · 나머지 EXP 통장)를 비운다.
## 훈련 확정으로 새 주가 시작될 때와 주가 끝날 때 둘 다 지난다 — 통장이 주를
## 넘어가면 판을 비워 둔 주가 지난주 나머지로 스탯을 올린다.
func reset_week_progress() -> void:
	_gm.season_state["training_exp_carry"] = {}
	_gm.season_state["week_day"] = -1
	_gm.season_state["week_day_log"] = {}
