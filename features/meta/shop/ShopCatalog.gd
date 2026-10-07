class_name ShopCatalog
extends RefCounted

# ── Fixed-price shop actions (M10) — shard purchase, trait craft, exchanges ───
# Pure rules over the ProfileManager node (`pm`). Every action returns "" on success
# (or an error message and changes nothing). **They do not save** — the shop screen
# calls `save_profile()` once after a successful action (§12.1 rule).
#
# - Shard shop: a named pilot for `SHOP_SHARD_PRICE_R<rarity>` pilot shards →
#   `grant_pilot` (new, or a dupe → breakthrough). Not sold once the breakthrough is maxed
#   (the dupe would only turn back into shards).
# - Trait craft: `traits.craft_cost` trait materials → `grant_trait`. 0 = not craftable;
#   owned traits are not craftable (a dupe would only turn back into material).
# - Exchanges: `SHOP_LEVELUP_EXCHANGE_COST` outgame → `SHOP_LEVELUP_EXCHANGE_GAIN` levelup;
#   `SHOP_PILOT_TICKET_PREMIUM` / `SHOP_TRAIT_TICKET_PREMIUM` premium → one gacha ticket.
# - Dev: `SHOP_DEV_PREMIUM_GRANT` premium for free (premium is a local number, §12.0).


# ── Shard shop ───────────────────────────────────────────────────────────────
## Shard price of a named pilot (by `players.rarity`). -1 when not sold.
static func shard_price(pilot_id: int) -> int:
	var row: Dictionary = Gacha.pilot_row(pilot_id)
	if row.is_empty():
		return -1
	var rar: int = clampi(int(row["rarity"]), 1, 4)
	return maxi(0, ConstTable.int_of("SHOP_SHARD_PRICE_R%d" % rar))


## "" when the pilot can be bought now (ignoring the price), else why not.
static func shard_block_reason(pm: Node, pilot_id: int) -> String:
	if shard_price(pilot_id) < 0:
		return Loc.t(L.SHOP_CATALOG_NOT_SOLD)
	if int(pm.max_level_of(pilot_id)) > 0 \
			and int(pm.breakthrough_of(pilot_id)) >= RunRules.breakthrough_max():
		return Loc.t(L.SHOP_CATALOG_BT_COMPLETE)
	return ""


## Buys a pilot with shards. `grant` receives the `grant_pilot` result.
static func buy_pilot(pm: Node, pilot_id: int, grant: Dictionary = {}) -> String:
	var why: String = shard_block_reason(pm, pilot_id)
	if why != "":
		return why
	var price: int = shard_price(pilot_id)
	if not pm.spend_currency("pilot_shard", price):
		return Loc.t(L.SHOP_CATALOG_NOT_ENOUGH_SHARDS, {"n": price})
	grant.merge(pm.grant_pilot(pilot_id), true)
	return ""


# ── Trait craft ──────────────────────────────────────────────────────────────
static func craft_cost(trait_id: int) -> int:
	return int(TraitSystem.row(trait_id).get("craft_cost", 0))


static func craft_block_reason(pm: Node, trait_id: int) -> String:
	if TraitSystem.row(trait_id).is_empty() or craft_cost(trait_id) <= 0:
		return Loc.t(L.SHOP_CATALOG_CANNOT_CRAFT)
	if pm.owns_trait(trait_id):
		return Loc.t(L.SHOP_CATALOG_OWNED)
	return ""


static func craft_trait(pm: Node, trait_id: int) -> String:
	var why: String = craft_block_reason(pm, trait_id)
	if why != "":
		return why
	var cost: int = craft_cost(trait_id)
	if not pm.spend_currency("trait_mat", cost):
		return Loc.t(L.SHOP_CATALOG_NOT_ENOUGH_MAT, {"n": cost})
	pm.grant_trait(trait_id)
	return ""


# ── Exchanges ────────────────────────────────────────────────────────────────
static func levelup_exchange_cost() -> int:
	return maxi(1, ConstTable.int_of("SHOP_LEVELUP_EXCHANGE_COST"))


static func levelup_exchange_gain() -> int:
	return maxi(1, ConstTable.int_of("SHOP_LEVELUP_EXCHANGE_GAIN"))


static func exchange_levelup(pm: Node) -> String:
	var cost: int = levelup_exchange_cost()
	if not pm.spend_currency("outgame", cost):
		return Loc.t(L.UI_ERROR_NOT_ENOUGH_CURRENCY, {"n": cost})
	pm.add_currency("levelup", levelup_exchange_gain())
	return ""


static func ticket_premium_price(pool: String) -> int:
	return maxi(1, ConstTable.int_of("SHOP_PILOT_TICKET_PREMIUM" if pool == Gacha.POOL_PILOT
			else "SHOP_TRAIT_TICKET_PREMIUM"))


static func buy_ticket(pm: Node, pool: String) -> String:
	var price: int = ticket_premium_price(pool)
	if not pm.spend_currency("premium", price):
		return Loc.t(L.SHOP_CATALOG_NOT_ENOUGH_PREMIUM, {"n": price})
	pm.add_currency(Gacha.ticket_key(pool), 1)
	return ""


static func dev_premium_grant() -> int:
	return maxi(1, ConstTable.int_of("SHOP_DEV_PREMIUM_GRANT"))


static func dev_add_premium(pm: Node) -> String:
	pm.add_currency("premium", dev_premium_grant())
	return ""
