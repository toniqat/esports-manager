class_name TrainingTile
extends RefCounted

# 훈련판에 올리는 코스 타일 한 장. `data/csv/training_tiles.csv` 한 행이 여기서
# 타일 하나로 조립된다(`from_def`) — 문법 해석은 **이 파일에만** 있다.
#
# ── 판의 축 ──────────────────────────────────────────────────────────────────
# 판은 **5열(선수) × 5행(요일)** 이다. 화면 위에 선수 다섯이 가로로 서고 그
# 아래로 월~금 다섯 줄이 내려간다. 그래서:
#
#   * **한 열 = 한 선수의 한 주**   → `day_*` 스코프
#   * **한 행 = 같은 요일 다섯 명** → `mate_*` 스코프
#
# 원작(Esports Godfather)은 이 축이 **반대**다(행이 선수, 열이 교시). 그래서
# 원작 표의 "같은 행 전체"는 이 판의 `day_all` 이고 "같은 열 전체"는 `mate_all`
# 이다. 방향 이름을 상/하/좌/우가 아니라 **의미**로 지은 것이 그 때문이다 —
# `up_one` 이라고 적어 두면 판을 한 번 돌릴 때마다 절이 전부 거짓말이 된다.
#
# ── shape ────────────────────────────────────────────────────────────────────
# `/` 로 줄을 나눈 색 문자열. **한 줄 = 하루, 한 글자 = 선수 한 명**이다.
#   `W`      1칸
#   `WW`     같은 요일에 선수 둘
#   `W/W`    한 선수의 이틀
#   `CC/DD`  선수 둘 × 이틀
#   `WWWWW`  하루를 다섯 명이 통째로
#
# ── exp ──────────────────────────────────────────────────────────────────────
# `|` 로 이은 `스탯:값` 목록. `all:8` 은 여섯 스탯 전부 +8. **한 칸이 주는 값**
# 이므로 n칸 타일은 n배가 들어온다. 단 검정(`K`) 칸은 언제나 0 이다 — 그 칸을
# 차지한 선수는 그날 아무것도 얻지 않는 대신 타일이 주변에 배율을 뿌린다.
#
# ── effect ───────────────────────────────────────────────────────────────────
# `;` 로 이은 절 목록. 지금 있는 절은 둘이다.
#   `mult:<scope>:<pct>`        그 범위의 칸 EXP 를 pct% 로 곱한다(100 = 무변화)
#   `flat:<scope>:<stat>:<n>`   그 범위의 칸에 stat EXP 를 n 더한다
# scope 는 아래 `SCOPES`. 배율은 **곱해서 쌓인다**(120% 둘이면 144%) — 더하기로
# 쌓으면 증폭 타일 셋만 붙여 놓아도 배율이 선형으로 폭주한다.


## 색 기호 → 그 색이 주는 스탯. `PlayerData.STAT_KEYS` 와 **같은 순서**다.
## `K` 는 경험치가 없는 칸, `W` 는 색이 없는 올라운드 칸이라 여기 없다.
const COLOR_STATS: Dictionary = {
	"H": "field_hit",    # 노랑  전장 명중
	"E": "field_eva",    # 파랑  전장 회피
	"C": "engage_hit",   # 빨강  교전 명중
	"D": "engage_eva",   # 보라  교전 회피
	"A": "atk_growth",   # 주황  공격력 성장
	"P": "hp_growth",    # 초록  체력 성장
}

const COLOR_BLACK: String = "K"   # 경험치 0 — 증폭형 타일의 자기 칸
const COLOR_GRAY:  String = "W"   # 무속성 — 여섯 스탯을 고루 준다

## 화면에 쓰는 색. 검정 칸이 진짜 검정인 것은 "여긴 아무것도 안 준다"가
## 한눈에 읽혀야 하기 때문이다.
const COLOR_RGB: Dictionary = {
	"H": Color(0.93, 0.83, 0.41),
	"E": Color(0.52, 0.69, 0.94),
	"C": Color(0.96, 0.56, 0.56),
	"D": Color(0.71, 0.55, 0.99),
	"A": Color(0.98, 0.68, 0.36),
	"P": Color(0.53, 0.87, 0.65),
	"K": Color(0.34, 0.34, 0.38),
	"W": Color(0.80, 0.80, 0.84),
}

## 등급 이름과 색. `grade` 는 0=D … 4=S.
const GRADE_NAMES: Array = ["D", "C", "B", "A", "S"]
const GRADE_COLORS: Array = [
	Color(0.66, 0.70, 0.76),
	Color(0.52, 0.84, 0.62),
	Color(0.45, 0.72, 0.98),
	Color(0.80, 0.56, 0.99),
	Color(1.00, 0.79, 0.32),
]

## **한 주에 몇 장까지 놓을 수 있는가.** 타일은 몇 번이든 다시 쓸 수 있어
## (보유 수량이 없다) 이 상한 하나가 "가장 센 타일로 도배"를 막는 유일한
## 장치다 — 등급이 오를수록 판에 들어갈 자리가 줄어든다. D 는 빈 칸을 메우는
## 기본 코스라 제한이 없다(-1).
const GRADE_PLACE_LIMIT: Array = [-1, 8, 4, 2, 1]

## 효과 범위. 전부 **그 타일이 덮은 칸을 기준으로** 센다.
##   self          — 자기 칸(기본. 절에 안 적어도 자기 칸 EXP 는 언제나 들어간다)
##   day_next      — 그 선수의 다음 날 한 칸
##   day_prev      — 그 선수의 전날 한 칸
##   day_all       — 그 선수의 한 주 전체
##   day_prev_all  — 그 선수의 앞선 날 전부
##   day_next_all  — 그 선수의 남은 날 전부
##   mate_left     — 왼쪽 선수의 같은 요일
##   mate_right    — 오른쪽 선수의 같은 요일
##   mate_all      — 그 요일의 다른 선수 전부
const SCOPES: Array = [
	"self", "day_next", "day_prev", "day_all", "day_prev_all", "day_next_all",
	"mate_left", "mate_right", "mate_all",
]

## 스코프를 사람 말로. 절 문법과 **같은 이유로** 방향(위/아래/왼쪽)이 아니라
## 의미로 적는다 — 판을 한 번 돌리면 방향 이름이 전부 거짓말이 된다.
## `effect_summary()` 가 이 표 하나만 읽으므로 절을 늘려도 문구가 갈라지지 않는다.
const SCOPE_LABELS: Dictionary = {
	"self":         "자기 칸",
	"day_next":     "다음 날",
	"day_prev":     "전날",
	"day_all":      "그 선수의 한 주",
	"day_prev_all": "앞선 날 전부",
	"day_next_all": "남은 날 전부",
	"mate_left":    "왼쪽 선수 같은 날",
	"mate_right":   "오른쪽 선수 같은 날",
	"mate_all":     "같은 날 다른 선수",
}

var id: String = ""
var tile_name: String = ""
var grade: int = 0

## 이 타일이 덮는 칸의 상대 좌표. `Vector2i(dx, dy)` — dx = 선수(열) 오프셋,
## dy = 요일(행) 오프셋. 언제나 (0,0) 을 포함하도록 정규화돼 있다.
var cells: Array = []                 # Array[Vector2i]
## 같은 순서로 그 칸의 색 기호.
var cell_colors: Array = []           # Array[String]
## 칸 하나가 주는 EXP. `{stat_key: int}` — 검정 칸에는 안 들어간다.
var per_cell_exp: Dictionary = {}
## 효과 절. `{kind, scope, pct}` 또는 `{kind, scope, stat, amount}`.
var clauses: Array = []


## CSV / DB 한 행을 타일 하나로. **static 인 것이 요점이다** — 인벤토리 목록,
## 판 계산, 결과 화면이 전부 이 한 함수를 지나므로 문법이 갈라질 수 없다.
static func from_def(def: Dictionary) -> TrainingTile:
	var t := TrainingTile.new()
	t.id          = String(def.get("id", ""))
	t.tile_name   = String(def.get("name", ""))
	t.grade       = int(def.get("grade", 0))
	t._parse_shape(String(def.get("shape", "W")))
	t._parse_exp(String(def.get("exp", "")))
	t._parse_effect(String(def.get("effect", "")))
	return t


func _parse_shape(shape: String) -> void:
	cells.clear()
	cell_colors.clear()
	var rows: PackedStringArray = shape.strip_edges().split("/", false)
	for y in rows.size():
		var row: String = String(rows[y]).strip_edges()
		for x in row.length():
			var ch: String = row[x].to_upper()
			cells.append(Vector2i(x, y))
			cell_colors.append(ch)
	if cells.is_empty():
		cells.append(Vector2i.ZERO)
		cell_colors.append(COLOR_GRAY)


func _parse_exp(raw: String) -> void:
	per_cell_exp.clear()
	for part in raw.split("|", false):
		var kv: PackedStringArray = String(part).strip_edges().split(":", false)
		if kv.size() != 2:
			continue
		var key: String = String(kv[0]).strip_edges()
		var amount: int = int(String(kv[1]))
		if key == "all":
			for stat_key in PlayerData.STAT_KEYS:
				per_cell_exp[String(stat_key)] = amount
		elif key in PlayerData.STAT_KEYS:
			per_cell_exp[key] = amount


func _parse_effect(raw: String) -> void:
	clauses.clear()
	for part in raw.split(";", false):
		var bits: PackedStringArray = String(part).strip_edges().split(":", false)
		if bits.size() < 3:
			continue
		var kind: String = String(bits[0]).strip_edges()
		var scope: String = String(bits[1]).strip_edges()
		if not scope in SCOPES:
			continue
		if kind == "mult" and bits.size() >= 3:
			clauses.append({"kind": "mult", "scope": scope, "pct": int(String(bits[2]))})
		elif kind == "flat" and bits.size() >= 4:
			var stat_key: String = String(bits[2]).strip_edges()
			if stat_key == "all" or stat_key in PlayerData.STAT_KEYS:
				clauses.append({"kind": "flat", "scope": scope,
						"stat": stat_key, "amount": int(String(bits[3]))})


# ── 조회 ─────────────────────────────────────────────────────────────────────
func size_cells() -> int:
	return cells.size()


## 모양의 가로 / 세로 칸 수.
func extent() -> Vector2i:
	var w: int = 0
	var h: int = 0
	for c in cells:
		w = maxi(w, (c as Vector2i).x + 1)
		h = maxi(h, (c as Vector2i).y + 1)
	return Vector2i(w, h)


## 이 타일이 한 주에 몇 장까지 놓이는가. -1 = 무제한.
func place_limit() -> int:
	if grade < 0 or grade >= GRADE_PLACE_LIMIT.size():
		return -1
	return int(GRADE_PLACE_LIMIT[grade])


func grade_name() -> String:
	return String(GRADE_NAMES[clampi(grade, 0, GRADE_NAMES.size() - 1)])


func grade_color() -> Color:
	return GRADE_COLORS[clampi(grade, 0, GRADE_COLORS.size() - 1)]


static func color_of(symbol: String) -> Color:
	return COLOR_RGB.get(symbol, COLOR_RGB[COLOR_GRAY])


## 칸 하나가 실제로 주는 EXP. 검정 칸은 통째로 0 이다.
func exp_of_cell(cell_idx: int) -> Dictionary:
	if cell_idx < 0 or cell_idx >= cell_colors.size():
		return {}
	if String(cell_colors[cell_idx]) == COLOR_BLACK:
		return {}
	return per_cell_exp


## 정보 팝오버에 적는 한 줄 요약 — "전 스탯 +8" / "전장 회피 +44".
## **약칭이 아니라 온전한 이름**(`STAT_LABELS`)을 쓴다: 카드가 아니라 눌러서
## 여는 팝오버라 폭이 348px 이고, 여기서 답해야 하는 질문이 "이 코스가 무엇을
## 올리는가" 하나뿐이라 `전회` 를 다시 풀어 읽을 이유가 없다.
func exp_summary() -> String:
	if per_cell_exp.is_empty():
		return "경험치 없음"
	if per_cell_exp.size() == PlayerData.STAT_KEYS.size():
		var uniform: bool = true
		var first: int = int(per_cell_exp[String(PlayerData.STAT_KEYS[0])])
		for k in per_cell_exp.keys():
			if int(per_cell_exp[k]) != first:
				uniform = false
				break
		if uniform:
			return "전 스탯 +%d" % first
	var parts: Array = []
	for i in PlayerData.STAT_KEYS.size():
		var key: String = String(PlayerData.STAT_KEYS[i])
		if per_cell_exp.has(key):
			parts.append("%s +%d" % [String(PlayerData.STAT_LABELS[i]),
					int(per_cell_exp[key])])
	return " · ".join(parts)


## 효과 절을 사람 말 한 줄씩으로. **문장을 절에서 만드는 것이 요점이다** —
## 예전에는 이 설명이 `training_tiles.csv` 의 `description` 에 손으로 적혀
## 있어서, 절의 숫자를 고치면 카드 설명만 조용히 거짓말이 됐다(그 컬럼은
## 그래서 삭제됐다). 절이 없는 타일은 빈 문자열이라 부르는 쪽이 줄을 건너뛴다.
func effect_summary() -> String:
	var parts: Array = []
	for cl_raw in clauses:
		var cl: Dictionary = cl_raw
		var scope_label: String = String(
				SCOPE_LABELS.get(String(cl["scope"]), String(cl["scope"])))
		if String(cl["kind"]) == "mult":
			# 100 이 무변화이므로 화면에는 **차이**를 적는다 — "115%" 보다
			# "+15%" 가 그 절이 무엇을 바꾸는지에 곧장 답한다.
			parts.append("%s 훈련 효과 %+d%%" % [scope_label, int(cl["pct"]) - 100])
			continue
		var stat_key: String = String(cl["stat"])
		var stat_label: String = "전 스탯"
		if stat_key != "all":
			var i: int = PlayerData.STAT_KEYS.find(stat_key)
			if i >= 0:
				stat_label = String(PlayerData.STAT_LABELS[i])
		parts.append("%s %s %+d" % [scope_label, stat_label, int(cl["amount"])])
	return "
".join(parts)
