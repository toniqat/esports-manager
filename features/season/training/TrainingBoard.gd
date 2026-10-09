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
# **빈 칸은 적지 않는다** — 정산할 때 기본 코스(`filler_tile_id()`, 보유한 기초 훈련
# 단계)가 자동으로 메우므로 "아무것도 안 놓은 판"과 "기본으로 도배한 판"이 같은 결과를 낸다.
#
# ── 보유 ─────────────────────────────────────────────────────────────────────
# 코스는 보유 개수가 있는 아이템이다(`TrainingCourses`, `season_state["training_courses"]`).
# 한 타일은 보유한 장수만큼 판에 놓을 수 있다 — 등급별 상한 · 전술 해금은 없다.

const COLS: int = 5          # 선수
const ROWS: int = 5          # 하루씩 다섯 줄 (달력으로는 월~금)
## **`DAY_NAMES` 는 삭제됐다.** 판 옆에 요일 글자를 세우던 화면(`TrainingView`)이
## 그 표의 유일한 소비자였고, 일상 훈련이 되면서 그 글자가 사라졌다. 요일 이름이
## 필요한 자리는 시간 경과 화면 하나이고 그쪽은 `OutgameTheme.DAY_NAMES` 를 읽는다.


## **EXP 는 스탯 포인트가 아니다** — 이만큼 모여야 스탯이 1 오른다. 그래야
## 타일 표에 세 자리 수를 적어도 스탯이 한 주에 백 단위로 튀지 않는다.
##
## 남은 나머지는 **주 안에서만** 이월된다(`season_state["training_exp_carry"]`,
## 아래 `apply_day_training`). 예전에는 그냥 버렸는데 — 정산이 주 1회였으므로
## 버려도 한 주에 한 번뿐이었다 — 정산이 요일 단위로 쪼개지면서 그러면
## 하루 EXP 가 문턱에 못 미치는 판이 닷새 내내 매일 0 점이 되어 한 주에 한 점도 안 오른다.
## 통장은 주가 시작될 때 비우므로 주를 넘겨 쌓이지 않는다.
## 값은 data/csv/const.csv — ConstTable 로 읽는다.
static var EXP_PER_POINT: int = ConstTable.int_of("TRAINING_EXP_PER_POINT")

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


## The run's owned courses (one per line, at its owned level) — the inventory row.
func owned_tiles() -> Array:
	var out: Array = []
	for id in TrainingCourses.owned_tile_ids(_gm.season_state):
		var t: TrainingTile = tile(String(id))
		if t != null:
			out.append(t)
	return out


## Basic course at the owned level — fills every empty cell. If this id is
## missing from the CSV, empty cells give 0.
func filler_tile_id() -> String:
	return TrainingCourses.filler_tile_id(_gm.season_state)


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


## How many copies of this tile are on the board (`ignore_entry` = not counted).
func placed_count(t: TrainingTile, ignore_entry: int = -1) -> int:
	if t == null:
		return 0
	var n: int = 0
	var b: Array = board()
	for i in b.size():
		if i != ignore_entry and String((b[i] as Dictionary).get("tile", "")) == t.id:
			n += 1
	return n


## Copies of this tile the run owns. -1 = unlimited (the basic course).
func owned_count(t: TrainingTile) -> int:
	if t == null:
		return 0
	return TrainingCourses.owned_count(_gm.season_state, t.id)


# ── Staff stats (M3) ─────────────────────────────────────────────────────────
# Every staff-stat read on this board goes through these, which in turn
# go through `StaffSystem.effective` — the view, placement checks, settlement
# and auto-arrange all see the same numbers.

## The run state the board reads (the view uses it for `StaffSystem` labels).
func season_state() -> Dictionary:
	return _gm.season_state


## Effective manager/staff stat for this run (1..20).
func staff_stat(stat: String) -> int:
	return StaffSystem.effective(_gm.season_state, stat)


func training_stat() -> int:
	return staff_stat("training")


## Can one more copy of this tile go on the board (owned copies left)?
## Used by the view to lock inventory cards — placement position is separate.
func can_take_more(t: TrainingTile, ignore_entry: int = -1) -> bool:
	var owned: int = owned_count(t)
	if owned == TrainingCourses.UNLIMITED:
		return true
	return placed_count(t, ignore_entry) < owned


## `origin` 에 그 타일을 놓을 수 있는가. `ignore_entry` 는 **자기 자신을 옮기는
## 중일 때** 그 배치를 없는 셈 치라는 뜻이다 — 안 그러면 한 칸 옆으로 미는
## 이동이 언제나 "겹친다"로 거절된다.
func can_place(t: TrainingTile, origin: Vector2i, ignore_entry: int = -1) -> bool:
	if t == null:
		return false
	if not can_take_more(t, ignore_entry):
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
# 순서가 결과를 바꾼다("왼쪽 칸 배율" 뒤에 "그 칸 가산" 이 오면 가산분이 안 깎인다).
# 두 표를 다 모은 뒤 한 번에 적용하면 배치가 같으면 결과도 언제나 같다.
#
# 배율은 **곱해서 쌓인다**(두 배율이 겹치면 곱) — 더하기로 쌓으면 증폭 타일 셋만
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
	var filler: TrainingTile = tile(filler_tile_id())
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
	# The outside multipliers (training stat × finance × mental, `exp_mult_table`)
	# are applied here too, before that single rounding — this is the **only**
	# place they meet, so preview (`compute_gains` → `projected_stats`) and day
	# settlement (`compute_day_gains` → `apply_day_training`) cannot disagree.
	var outer: Dictionary = exp_mult_table()
	var out: Dictionary = {}
	for seat in COLS:
		for day in ROWS:
			var c4 := Vector2i(seat, day)
			var m: float = maxf(0.0, float(mult[c4]))
			var om: float = float(outer.get(c4, 1.0))
			var cell_base: Dictionary = base[c4]
			var cell_bonus: Dictionary = bonus[c4]
			var acc: Dictionary = {}
			for sk3 in PlayerData.STAT_KEYS:
				var key: String = String(sk3)
				var v: float = float(int(cell_base.get(key, 0))) * m
				v += float(int(cell_bonus.get(key, 0)))
				acc[key] = int(round(v * om))
			out[c4] = acc
	return out


## Outside EXP multiplier per cell, `Vector2i(seat, day) → float`:
## training-stat mult (`TrainingTile.training_exp_mult`) ×
## `FinanceSystem.training_exp_mult(state)` ×
## `MentalSystem.training_exp_mult(state, pilot_id, day)` (plan §11.3) ×
## trait `train_exp_pct` (`TraitSystem.run_pct_mult`, M8) ×
## the pilot's rank-row `PlayerData.train_bonus_pct` (`stat_growth`, `RunRules.apply_rank`).
## Seats without a pilot get the shared part only.
func exp_mult_table() -> Dictionary:
	var state: Dictionary = _gm.season_state
	var shared: float = TrainingTile.training_exp_mult(training_stat()) \
			* FinanceSystem.training_exp_mult(state) \
			* TraitSystem.run_pct_mult(state, "train_exp_pct")
	var pilots: Array = player_pilots_by_seat()
	var out: Dictionary = {}
	for seat in COLS:
		var p: PlayerData = pilots[seat]
		var pilot_mult: float = 1.0
		if p != null:
			pilot_mult = maxf(0.0, 1.0 + float(p.train_bonus_pct) / 100.0)
		for day in ROWS:
			var m: float = shared
			if p != null:
				m *= pilot_mult * MentalSystem.training_exp_mult(state, int(p.id), day)
			out[Vector2i(seat, day)] = m
	return out


## Mech-mastery EXP per cell, `Vector2i(seat, day) → int` — only cells covered by
## a mastery (`M`) cell of a placed tile. Raw amounts: clauses and the stat-EXP
## multipliers do not touch them (`MechMastery` applies its own multipliers).
func cell_mastery() -> Dictionary:
	var out: Dictionary = {}
	for e_raw in board():
		var e: Dictionary = e_raw
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null or not t.has_mastery():
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		for i in t.cells.size():
			var amount: int = t.mastery_of_cell(i)
			if amount <= 0:
				continue
			var at := Vector2i(ox + (t.cells[i] as Vector2i).x, oy + (t.cells[i] as Vector2i).y)
			if at.x < 0 or at.x >= COLS or at.y < 0 or at.y >= ROWS:
				continue
			out[at] = int(out.get(at, 0)) + amount
	return out


## Mastery EXP folded per seat, `{seat: int}`. `day < 0` = the whole week.
func compute_mastery(day: int = -1) -> Dictionary:
	var cells: Dictionary = cell_mastery()
	var out: Dictionary = {}
	for seat in COLS:
		var total: int = 0
		for d in ROWS:
			if day >= 0 and d != day:
				continue
			total += int(cells.get(Vector2i(seat, d), 0))
		out[seat] = total
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
# 쪼개면서 생기는 유일한 함정이 **나머지**다. `EXP_PER_POINT` 가 스탯 1 인데 요일마다
# 따로 나누면 문턱에 못 미치는 하루치가 다섯 번(주간 합이면 몇 점이 되는 양)이
# 매일 0점이 되어 한 주에 한 점도 안 오른다. 그래서 나머지를 버리지 않고 `season_state["training_exp_carry"]`
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
## Also `mastery` (mastery EXP sent to the research mech) and `quirk` — the
## quirk ops run on that pilot today, `[{kind, result, id?, from?, to?, slots?}]`
## (empty array when none; `_apply_quirk_ops`).
##
## `carry` 를 줄에 실어 보내는 것은 화면 때문이다 — 기초 코스만 깔린 판에서는
## 하루 EXP 가 `EXP_PER_POINT` 에 못 미쳐 월~목이 전부 `+0` 으로 보이고 금요일에
## 한꺼번에 오른다. 그날 아무 일도 안 일어난 것처럼 보이면
## 요일별 정산이 하는 일이 화면에 없는 셈이라, 오른 포인트가 0 인 칸은
## `carry / EXP_PER_POINT` 로 "다음 한 점까지"를 보여 준다.
##
## 스탯에는 **상한이 없다** — `PlayerData.STAT_MIN` 하한만 지킨다. 명중 넷은
## 비율로 읽히고(`PilotData.hit_chance`) 성장 계수 둘은 배율이라, 100 을 넘겨도
## 계산이 무너지지 않는다.
func apply_day_training(day: int) -> Array:
	var gains: Dictionary = compute_day_gains(day)
	var mastery: Dictionary = compute_mastery(day)
	var quirk_ops: Dictionary = day_quirk_ops(day)
	var pilots: Array = player_pilots_by_seat()
	var carry: Dictionary = exp_carry()
	var colors: Dictionary = day_colors(day)
	var groups: Dictionary = day_groups(day)
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
		# Mastery cells of this day go to the pilot's research mech (M4 owns
		# what happens there — multipliers, no-research-mech handling).
		var mastery_exp: int = int(mastery.get(seat, 0))
		if mastery_exp > 0:
			MechMastery.add_training_exp(_gm.season_state, int(p.id), mastery_exp)
		rows.append({
			"pilot_id": int(p.id), "role": int(p.role),
			"seat": seat, "before": before, "after": snapshot(p),
			"ups": ups, "exp": exp, "carry": pocket.duplicate(),
			"mastery": mastery_exp,
			"quirk": _apply_quirk_ops(int(p.id), quirk_ops.get(seat, [])),
			# Training result is fixed; every pilot trains (an empty cell = the basic
			# course), so every pilot gains stress.
			"stress": StressSystem.on_training_day(_gm.season_state, int(p.id), day),
			# Colour symbol of the cell; an empty cell is the basic course's colour.
			# The week screen's base map stands the pilot on that colour's spot.
			"color": String(colors.get(seat, filler_color())),
			# Placed tile the cell belongs to (-1 = basic course) and its facility: pilots in
			# the same group trained together (joint training, mental `talk_pair`).
			"group": int((groups.get(seat, {}) as Dictionary).get("group", -1)),
			"facility": String((groups.get(seat, {}) as Dictionary).get("facility", "")),
		})
	# §15 — the run-only training level and the awakening gauge read the day's rows.
	TrainingLevel.on_training_day(_gm.season_state, rows)
	Awakening.on_training_day(_gm.season_state, rows)
	return rows


## Colour symbol of the basic course (`filler_tile_id`) that fills empty cells.
func filler_color() -> String:
	var t: TrainingTile = tile(filler_tile_id())
	return String(t.cell_colors[0]) if t != null and not t.cell_colors.is_empty() else ""


## Colour symbol (`TrainingTile.cell_colors`) of each placed cell on row `day`,
## `{seat: String}`; seats without a tile that day are missing (they get the basic
## course). The week screen reads it before the day is settled (morning spots).
func day_colors(day: int) -> Dictionary:
	var out: Dictionary = {}
	for e_raw in board():
		var e: Dictionary = e_raw
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null:
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		for i in t.cells.size():
			var c: Vector2i = t.cells[i]
			if oy + c.y == day and i < t.cell_colors.size():
				out[ox + c.x] = String(t.cell_colors[i])
	return out


## Placed tile of each seat on row `day`: `{seat: {group, facility}}` — `group` = the
## board entry index (seats sharing it train **together** that day: joint training),
## `facility` = the tile's `facility` column, else the colour symbol of the tile's first
## cell on that row (so a joint group shares one spot). Seats on the basic course are missing.
func day_groups(day: int) -> Dictionary:
	var out: Dictionary = {}
	var entries: Array = board()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null:
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		var lead: String = t.facility
		for k in t.cells.size():
			var c: Vector2i = t.cells[k]
			if oy + c.y != day:
				continue
			if lead == "" and k < t.cell_colors.size():
				lead = String(t.cell_colors[k])
			out[ox + c.x] = {"group": i, "facility": lead}
	return out


## Display name of the training each seat does on row `day`, `{seat: String}` for every
## seat `0..COLS-1` — the placed tile's name, or the basic course (`filler_tile_id`) for an
## empty cell. The week screen shows it in the morning bubble over each pilot on the map.
func day_tile_names(day: int) -> Dictionary:
	var out: Dictionary = {}
	for e_raw in board():
		var e: Dictionary = e_raw
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null:
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		for c in t.cells:
			if oy + (c as Vector2i).y == day:
				out[ox + (c as Vector2i).x] = t.tile_name
	var filler: TrainingTile = tile(filler_tile_id())
	for seat in COLS:
		if not out.has(seat):
			out[seat] = filler.tile_name if filler != null else ""
	return out


# ── Quirk tiles (§14, T1) ────────────────────────────────────────────────────
## Quirk ops of the `Q` cells settled on `day`, `{seat: [op]}` in
## `TrainingTile.QUIRK_OPS` order. A seat has one cell per day, so each pilot
## gets a tile's ops at most once per settled day.
func day_quirk_ops(day: int) -> Dictionary:
	var out: Dictionary = {}
	for e_raw in board():
		var e: Dictionary = e_raw
		var t: TrainingTile = tile(String(e.get("tile", "")))
		if t == null or not t.has_quirk():
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		for i in t.cells.size():
			if not t.is_quirk_cell(i):
				continue
			var at := Vector2i(ox + (t.cells[i] as Vector2i).x, oy + (t.cells[i] as Vector2i).y)
			if at.y != day or at.x < 0 or at.x >= COLS:
				continue
			var ops: Array = out.get(at.x, [])
			for op in t.quirk_ops:
				if not ops.has(op):
					ops.append(op)
			out[at.x] = ops
	return out


## Runs the ops on one pilot through `QuirkSystem` and returns the row's
## `quirk` list `[{kind, result, id?, from?, to?, slots?}]` (empty when nothing ran).
func _apply_quirk_ops(pilot_id: int, ops: Array) -> Array:
	var out: Array = []
	var state: Dictionary = _gm.season_state
	if ops.is_empty() or not QuirkSystem.is_enabled(state):
		return out
	for op_raw in ops:
		var op: String = String(op_raw)
		var r: Dictionary = {}
		match op:
			"slot":
				r = QuirkSystem.add_slot(state, pilot_id)
			"reroll":
				r = QuirkSystem.reroll(state, pilot_id)
			"gain":
				r = QuirkSystem.gain_random(state, pilot_id)
			_:
				continue
		var rec: Dictionary = r.duplicate(true)
		rec["kind"] = op
		out.append(rec)
	return out


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


# ── Auto-arrange ("코치 추천", M3 · §14 T6) ─────────────────────────────────
# Shown only when training is delegated (`StaffSystem.is_delegated`). It is a
# **plain rule, not an optimiser** (plan §11.0 / §14.0 — no manual bonus either
# way), and deterministic (no randomness, fixed tie-breaks):
#   1. clear the board; rank each pilot's stats by **deficit against the role
#      average** (`coach_needs` — every pilot of that role in `all_pilots`);
#   2. walk the owned courses grade by grade, highest first. Inside a grade:
#      a. focus pass — every owned copy of the **focused** tiles (fewer than six
#         stats) goes to the neediest pilots, one pilot per turn, each copy
#         aimed at that pilot's weakest not-yet-reinforced stat among the top
#         `COACH_WEAK_RANK`, at the position that raises that pilot's EXP in
#         that stat the most;
#      b. broad pass — the owned copies of broad tiles (all-stat / amplifiers)
#         by the old rule: first day-then-seat position that raises the board's
#         total EXP (`board_total_exp`);
#   3. one more broad sweep over all grades — amplifiers placed before the
#      tiles they amplify get a second chance.
# Only owned copies are placed (`can_place` → `can_take_more`). Never
# auto-placed: the basic course (it is what an empty cell already is), mastery
# (`M`) tiles and any tile whose effect has a clause other than `mult` / `flat`
# (quirk tiles, T1) — those are separate decisions.

## Rebuilds the board with the coach's arrangement. Returns the tiles placed.
func auto_arrange() -> int:
	clear_board()
	var top: int = TrainingTile.GRADE_NAMES.size() - 1
	var needs: Dictionary = coach_needs()
	var reinforced: Dictionary = {}     # seat → {stat: true}
	var placed: int = 0
	for g in range(top, -1, -1):
		var pool: Array = _coach_pool(g)
		if pool.is_empty():
			continue
		placed += _coach_focus_pass(pool, needs, reinforced)
		placed += _coach_broad_pass(pool)
	for g2 in range(top, -1, -1):
		placed += _coach_broad_pass(_coach_pool(g2))
	return placed


## Coach's view of each pilot: `{seat: {stats: Array[stat], deficit: float}}` —
## the six stats ordered by deficit against the role average (largest first; ties
## keep `STAT_KEYS` order), cut to the top `COACH_WEAK_RANK`; `deficit` = the
## largest one (turn order). Seats without a pilot are absent.
func coach_needs() -> Dictionary:
	var pilots: Array = player_pilots_by_seat()
	var avg: Dictionary = _role_stat_avgs()
	var rank_n: int = clampi(ConstTable.int_of("COACH_WEAK_RANK"), 1, PlayerData.STAT_KEYS.size())
	var out: Dictionary = {}
	for seat in COLS:
		var p: PlayerData = pilots[seat]
		if p == null:
			continue
		var role_avg: Dictionary = avg.get(int(p.role), {})
		var rows: Array = []
		for i in PlayerData.STAT_KEYS.size():
			var key: String = String(PlayerData.STAT_KEYS[i])
			var deficit: float = float(role_avg.get(key, 0.0)) - float(int(p.get(key)))
			rows.append({"stat": key, "deficit": deficit, "i": i})
		rows.sort_custom(func(x, y):
			if not is_equal_approx(float(x["deficit"]), float(y["deficit"])):
				return float(x["deficit"]) > float(y["deficit"])
			return int(x["i"]) < int(y["i"]))
		var ranked: Array = []
		for r in rows.slice(0, rank_n):
			ranked.append(String((r as Dictionary)["stat"]))
		out[seat] = {"stats": ranked, "deficit": float((rows[0] as Dictionary)["deficit"])}
	return out


# `{role: {stat: float}}` — average of every pilot of that role in the run pool.
func _role_stat_avgs() -> Dictionary:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for raw in (_gm.season_state.get("all_pilots", []) as Array):
		var p := raw as PlayerData
		if p == null:
			continue
		var role: int = int(p.role)
		if not sums.has(role):
			sums[role] = {}
			counts[role] = 0
		counts[role] = int(counts[role]) + 1
		for sk in PlayerData.STAT_KEYS:
			var key: String = String(sk)
			sums[role][key] = float((sums[role] as Dictionary).get(key, 0.0)) + float(int(p.get(key)))
	var out: Dictionary = {}
	for role2 in sums.keys():
		var n: float = maxf(1.0, float(counts[role2]))
		var row: Dictionary = {}
		for key2 in (sums[role2] as Dictionary).keys():
			row[key2] = float(sums[role2][key2]) / n
		out[role2] = row
	return out


# Owned tiles of grade `g` the coach may use, in a fixed order (bigger shapes
# first, then id).
func _coach_pool(g: int) -> Array:
	var pool: Array = []
	for t_raw in owned_tiles():
		var t: TrainingTile = t_raw
		if t.grade == g and coach_may_use(t):
			pool.append(t)
	pool.sort_custom(_auto_order)
	return pool


## The basic course, mastery tiles and tiles carrying any effect clause other
## than `mult` / `flat` (e.g. T1's `quirk:*`) are never auto-placed. Reads the raw CSV effect so a
## clause kind `TrainingTile` does not parse still counts.
func coach_may_use(t: TrainingTile) -> bool:
	if t == null or t.has_mastery() or t.cell_colors.has(TrainingTile.COLOR_MASTERY):
		return false
	if TrainingCourses.is_basic(t.id):
		return false
	var raw: String = String(_gm.training_tile_def(t.id).get("effect", ""))
	for part in raw.split(";", false):
		var kind: String = String(part).strip_edges().get_slice(":", 0)
		if kind != "" and kind != "mult" and kind != "flat":
			return false
	return true


## A focused tile trains fewer than six stats.
static func is_focused_tile(t: TrainingTile) -> bool:
	return not t.per_cell_exp.is_empty() and t.per_cell_exp.size() < PlayerData.STAT_KEYS.size()


static func _auto_order(a: TrainingTile, b: TrainingTile) -> bool:
	if a.size_cells() != b.size_cells():
		return a.size_cells() > b.size_cells()
	return a.id < b.id


# Focus pass: the owned focused tiles of `pool`, one per pilot per round, until
# no copy fits. Pilots take turns fewest-reinforced first, then the largest
# deficit, then seat. Returns the tiles placed.
func _coach_focus_pass(pool: Array, needs: Dictionary, reinforced: Dictionary) -> int:
	var focused: Array = []
	for t_raw in pool:
		if is_focused_tile(t_raw):
			focused.append(t_raw)
	if focused.is_empty() or needs.is_empty():
		return 0
	var placed: int = 0
	var progress: bool = true
	while progress:
		progress = false
		for seat in _coach_seat_order(needs, reinforced):
			if _coach_reinforce(int(seat), focused, needs, reinforced):
				placed += 1
				progress = true
	return placed


# Seats in turn order: fewest reinforced stats first, then the largest top
# deficit, then seat.
func _coach_seat_order(needs: Dictionary, reinforced: Dictionary) -> Array:
	var seats: Array = needs.keys()
	seats.sort_custom(func(a, b):
		var na: int = (reinforced.get(a, {}) as Dictionary).size()
		var nb: int = (reinforced.get(b, {}) as Dictionary).size()
		if na != nb:
			return na < nb
		var da: float = float((needs[a] as Dictionary)["deficit"])
		var db: float = float((needs[b] as Dictionary)["deficit"])
		if not is_equal_approx(da, db):
			return da > db
		return int(a) < int(b))
	return seats


# One focused tile for `seat`: the weakest stat not yet reinforced that some
# tile in `focused` trains, at the best position. Returns true if placed.
func _coach_reinforce(seat: int, focused: Array, needs: Dictionary, reinforced: Dictionary) -> bool:
	var done: Dictionary = reinforced.get(seat, {})
	for stat_raw in ((needs.get(seat, {}) as Dictionary).get("stats", []) as Array):
		var stat: String = String(stat_raw)
		if done.has(stat):
			continue
		var best: Dictionary = {}
		for t_raw in focused:
			var t: TrainingTile = t_raw
			if not t.per_cell_exp.has(stat):
				continue
			var cand: Dictionary = _coach_best_spot(t, seat, stat)
			if not cand.is_empty() and (best.is_empty() or int(cand["gain"]) > int(best["gain"])):
				best = cand
		if best.is_empty():
			continue
		if place(String(best["tile"]), best["origin"]) < 0:
			continue
		done[stat] = true
		reinforced[seat] = done
		return true
	return false


# Best legal origin for `t` that covers `seat`'s column: the largest gain in
# `stat` EXP for that seat (ties → earliest day, then leftmost). {} if no
# position gains anything.
func _coach_best_spot(t: TrainingTile, seat: int, stat: String) -> Dictionary:
	var before: int = _seat_stat_exp(seat, stat)
	var best: Dictionary = {}
	for y in ROWS:
		var tried: Dictionary = {}
		for c_raw in t.cells:
			var o := Vector2i(seat - (c_raw as Vector2i).x, y - (c_raw as Vector2i).y)
			if tried.has(o) or not can_place(t, o):
				continue
			tried[o] = true
			var idx: int = place(t.id, o)
			if idx < 0:
				continue
			var gain: int = _seat_stat_exp(seat, stat) - before
			remove_entry(idx)
			if gain <= 0:
				continue
			if best.is_empty() or gain > int(best["gain"]) \
					or (gain == int(best["gain"]) and (o.y < (best["origin"] as Vector2i).y
					or (o.y == (best["origin"] as Vector2i).y and o.x < (best["origin"] as Vector2i).x))):
				best = {"tile": t.id, "origin": o, "gain": gain}
	return best


# Week EXP of one stat for one seat on the current board.
func _seat_stat_exp(seat: int, stat: String) -> int:
	return int((compute_gains().get(seat, {}) as Dictionary).get(stat, 0))


# Broad pass (the M3 rule): round-robin over the pool's non-focused tiles, one
# copy per turn, each at the first position that raises the board total EXP.
func _coach_broad_pass(pool: Array) -> int:
	var broad: Array = []
	for t_raw in pool:
		if not is_focused_tile(t_raw):
			broad.append(t_raw)
	var placed: int = 0
	var progress: bool = true
	while progress:
		progress = false
		for t2_raw in broad:
			var t2: TrainingTile = t2_raw
			if not can_take_more(t2):
				continue
			if _auto_place_one(t2):
				placed += 1
				progress = true
	return placed


func _auto_place_one(t: TrainingTile) -> bool:
	var before: int = board_total_exp()
	for y in ROWS:
		for x in COLS:
			var o := Vector2i(x, y)
			if not can_place(t, o):
				continue
			var idx: int = place(t.id, o)
			if idx < 0:
				continue
			if board_total_exp() > before:
				return true
			remove_entry(idx)
	return false


## Sum of every stat EXP over the whole board (all seats, all days).
func board_total_exp() -> int:
	var total: int = 0
	var cells: Dictionary = cell_exp()
	for c in cells.keys():
		for v in (cells[c] as Dictionary).values():
			total += int(v)
	return total


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
