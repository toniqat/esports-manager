class_name ConstTable
extends RefCounted

# ── 튜닝 상수 테이블 (`data/csv/const.csv` → game.db `const`) ──────────
# 스크립트에 박혀 있던 게임플레이 튜닝값(교전 무대 속도 · 스킬 배율 · AI 가중치 …)을
# 데이터로 뺀 자리. 값을 바꿀 때는 **CSV 만 고치고 Rebuild game.db** 를 돌린다 —
# 스크립트도 README 도 손대지 않는다. 그래서 문서와 주석은 값을 적지 않고 키
# 이름만 가리킨다(값이 두 군데 살면 반드시 한쪽이 거짓말을 하게 된다).
#
# 소비 방식 — 스크립트는 예전 `const` 이름을 `static var` 로 바꿔 한 번만 읽는다:
#   static var MOVE_SPEED_MELEE: float = ConstTable.num("ENGAGE_MOVE_SPEED_MELEE")
# 그래서 외부 호출부(`TurnEngageSim.MOVE_SPEED_MELEE`)는 그대로 돈다.
#
# 처음 읽힐 때 DB 를 한 번 열어 테이블 전체를 캐시한다. `static var` 초기화는
# 오토로드보다 먼저 일어날 수 있으므로 경로는 `GameDb.path()` 에서 직접 받는다.
# 키가 없으면 push_error 후 0 을 돌려준다 — 조용히 넘어가지 않도록.

static var _values: Dictionary = {}
static var _loaded: bool = false


static func num(key: String) -> float:
	_ensure_loaded()
	if not _values.has(key):
		push_error("ConstTable: const.csv 에 '%s' 키가 없다 — CSV 에 행을 넣고 Rebuild game.db 를 돌릴 것." % key)
		return 0.0
	return float(_values[key])


static func int_of(key: String) -> int:
	return int(round(num(key)))


static func has(key: String) -> bool:
	_ensure_loaded()
	return _values.has(key)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("ConstTable: %s 를 열 수 없다." % db.path)
		return
	db.query("SELECT key, value FROM const")
	for row in db.query_result:
		_values[str(row["key"])] = str(row["value"]).to_float()
	db.close_db()
	if _values.is_empty():
		push_error("ConstTable: const 테이블이 비어 있거나 없다 — Rebuild game.db 를 돌릴 것.")
