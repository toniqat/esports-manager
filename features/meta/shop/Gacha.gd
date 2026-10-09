class_name Gacha
extends RefCounted

# ── Local gacha (M10) — pure rules + the one pull action ─────────────────────
# Contract: `docs/outgame_dev_plan.md` §12 (row E). Rules in `features/meta/shop/README.md`.
#
# - Rarity is rolled by `gacha_rates.csv` weights of the pool (`pilot` / `trait`), then one
#   item of that rarity uniformly: a **named** pilot (`players.is_mob = 0`) or a trait
#   (`traits.csv`). An empty rarity bucket falls back to the nearest non-empty one
#   (lower rarity first on a tie).
# - Pilots go through `ProfileManager.grant_pilot` (new / breakthrough / shard), traits
#   through `grant_trait` (new / material).
# - Cost per pull: one ticket of the pool (`gacha_ticket_pilot` / `gacha_ticket_trait`) while
#   any are left, the rest in outgame currency (`GACHA_PILOT_PRICE` / `GACHA_TRAIT_PRICE`).
#   A multi pull (`GACHA_MULTI_COUNT`) takes `GACHA_MULTI_DISCOUNT_PCT` off its currency part.
# - `pull` is the whole action: check → spend → roll → grant → save once.
#   `rng` is injectable so tests can seed it.

const POOL_PILOT: String = "pilot"
const POOL_TRAIT: String = "trait"

static var _rates: Dictionary = {}       # pool → Array[{rarity, weight}] (rarity order)
static var _pilots: Array = []           # Array[{id, name, role, rarity}] — named only, id order
static var _loaded: bool = false


# ── Table reads ──────────────────────────────────────────────────────────────
## `[{rarity, weight, pct}]` of a pool, rarity ascending. `pct` = weight share × 100.
static func rates(pool: String) -> Array:
	_ensure_loaded()
	var rows: Array = _rates.get(pool, [])
	var total: float = 0.0
	for r in rows:
		total += float((r as Dictionary)["weight"])
	var out: Array = []
	for r in rows:
		var d: Dictionary = r
		out.append({"rarity": int(d["rarity"]), "weight": float(d["weight"]),
				"pct": 0.0 if total <= 0.0 else float(d["weight"]) / total * 100.0})
	return out


## Named pilots `[{id, name_key, role, rarity}]` (id order; `pilot_name` for display).
static func named_pilots() -> Array:
	_ensure_loaded()
	return _pilots


static func pilot_row(pilot_id: int) -> Dictionary:
	for r in named_pilots():
		if int((r as Dictionary)["id"]) == pilot_id:
			return r
	return {}


## 네임드 선수 표시 이름 — 행에는 l10n key(`name_key`)만 있다. 없는 id 는 "?".
static func pilot_name(pilot_id: int) -> String:
	var key: String = String(pilot_row(pilot_id).get("name_key", ""))
	return "?" if key.is_empty() else Loc.t(key)  # l10n-dynamic: name.player.*


## Item ids of a pool at exactly `rarity`.
static func candidates(pool: String, rarity: int) -> Array:
	var out: Array = []
	if pool == POOL_PILOT:
		for r in named_pilots():
			if int((r as Dictionary)["rarity"]) == rarity:
				out.append(int((r as Dictionary)["id"]))
	else:
		for r in TraitSystem.rows():
			if int((r as Dictionary)["rarity"]) == rarity:
				out.append(int((r as Dictionary)["id"]))
	return out


## The rarity actually drawn from: `rarity` itself, else the nearest non-empty bucket
## (lower first on a tie). -1 when the pool is empty.
static func resolve_bucket(pool: String, rarity: int) -> int:
	if not candidates(pool, rarity).is_empty():
		return rarity
	for d in range(1, 8):
		if not candidates(pool, rarity - d).is_empty():
			return rarity - d
		if not candidates(pool, rarity + d).is_empty():
			return rarity + d
	return -1


# ── Rolls ────────────────────────────────────────────────────────────────────
static func roll_rarity(pool: String, rng: RandomNumberGenerator) -> int:
	var rows: Array = rates(pool)
	if rows.is_empty():
		return 0
	var weights := PackedFloat32Array()
	for r in rows:
		weights.append(float((r as Dictionary)["weight"]))
	var idx: int = rng.rand_weighted(weights)
	return int((rows[maxi(0, idx)] as Dictionary)["rarity"])


## One item id (pilot or trait). -1 when the pool is empty.
static func roll_item(pool: String, rng: RandomNumberGenerator) -> int:
	var bucket: int = resolve_bucket(pool, roll_rarity(pool, rng))
	if bucket < 0:
		return -1
	var ids: Array = candidates(pool, bucket)
	return int(ids[rng.randi_range(0, ids.size() - 1)])


# ── Costs ────────────────────────────────────────────────────────────────────
static func ticket_key(pool: String) -> String:
	return "gacha_ticket_pilot" if pool == POOL_PILOT else "gacha_ticket_trait"


static func unit_price(pool: String) -> int:
	return maxi(0, ConstTable.int_of("GACHA_PILOT_PRICE" if pool == POOL_PILOT else "GACHA_TRAIT_PRICE"))


static func multi_count() -> int:
	return maxi(2, ConstTable.int_of("GACHA_MULTI_COUNT"))


## `{tickets, currency}` that `count` pulls cost with `tickets_owned` tickets in hand.
static func cost_of(pool: String, count: int, tickets_owned: int) -> Dictionary:
	var use_tickets: int = clampi(tickets_owned, 0, count)
	var paid: int = count - use_tickets
	var currency: int = paid * unit_price(pool)
	if count >= multi_count() and paid > 0:
		var disc: int = clampi(ConstTable.int_of("GACHA_MULTI_DISCOUNT_PCT"), 0, 100)
		currency = int(ceil(float(currency) * float(100 - disc) / 100.0))
	return {"tickets": use_tickets, "currency": currency}


## "" when `pm` (ProfileManager) can afford `count` pulls.
static func check(pm: Node, pool: String, count: int) -> String:
	if count <= 0:
		return Loc.t(L.SHOP_GACHA_BAD_COUNT)
	if resolve_bucket(pool, 0) < 0:
		return Loc.t(L.SHOP_GACHA_NO_ITEMS)
	var c: Dictionary = cost_of(pool, count, int(pm.currency_of(ticket_key(pool))))
	if int(pm.currency_of("outgame")) < int(c["currency"]):
		return Loc.t(L.UI_ERROR_NOT_ENOUGH_CURRENCY, {"n": int(c["currency"])})
	return ""


# ── The pull action ──────────────────────────────────────────────────────────
## Spends, rolls `count` items, grants them and saves once (`save`). Result:
## `{error, cost: {tickets, currency}, results: [entry], save_error}` where an entry is
## `{pool, id, rarity, result, stage, shards, rank_stone, amount}` (`result` = grant result:
## new / breakthrough / shard for pilots, new / material for traits; pilot `rarity` = stars).
## Sum the `rank_stone` of the results with `rank_stone_total`.
## On error nothing is spent and `results` is empty.
static func pull(pm: Node, pool: String, count: int,
		rng: RandomNumberGenerator = null, save: bool = true) -> Dictionary:
	var out: Dictionary = {"error": "", "cost": {"tickets": 0, "currency": 0},
			"results": [], "save_error": ""}
	var err: String = check(pm, pool, count)
	if err != "":
		out["error"] = err
		return out
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var cost: Dictionary = cost_of(pool, count, int(pm.currency_of(ticket_key(pool))))
	pm.spend_currency(ticket_key(pool), int(cost["tickets"]))
	pm.spend_currency("outgame", int(cost["currency"]))
	out["cost"] = cost
	var results: Array = []
	for i in count:
		var id: int = roll_item(pool, rng)
		if id < 0:
			continue
		var g: Dictionary
		var rar: int
		if pool == POOL_PILOT:
			g = pm.grant_pilot(id)
			rar = int(pilot_row(id).get("rarity", 0))
		else:
			g = pm.grant_trait(id)
			rar = int(TraitSystem.row(id).get("rarity", 0))
		results.append({
			"pool": pool, "id": id, "rarity": rar, "result": String(g.get("result", "")),
			"stage": int(g.get("stage", 0)), "shards": int(g.get("shards", 0)),
			"rank_stone": int(g.get("rank_stone", 0)), "amount": int(g.get("amount", 0)),
		})
	out["results"] = results
	if save:
		out["save_error"] = String(pm.save_profile())
	return out


# ── Loading ──────────────────────────────────────────────────────────────────
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("Gacha: cannot open game.db")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='gacha_rates'")
	if not db.query_result.is_empty():
		db.query("SELECT pool, rarity, weight FROM gacha_rates ORDER BY pool, rarity")
		for r in db.query_result:
			var pool: String = String(r["pool"])
			if not _rates.has(pool):
				_rates[pool] = []
			(_rates[pool] as Array).append({"rarity": int(r["rarity"]), "weight": float(r["weight"])})
	db.query("SELECT id, name_key, role, rarity FROM players WHERE is_mob = 0 ORDER BY id")
	for r in db.query_result:
		_pilots.append({"id": int(r["id"]), "name_key": String(r["name_key"]),
				"role": int(r["role"]), "rarity": int(r["rarity"])})
	db.close_db()


## Σ `rank_stone` over pull / purchase results (capped-breakthrough dupes pay rank stones).
static func rank_stone_total(results: Array) -> int:
	var n: int = 0
	for raw in results:
		n += int((raw as Dictionary).get("rank_stone", 0))
	return n
