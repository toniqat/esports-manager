class_name TraitHooks
extends Node

# In-game manager traits (M8, `docs/outgame_dev_plan.md` §12.3) — **player team only**.
#
# Reads `GameManager.match_ctx.traits = [{id, key, p1, p2}]` (written by
# `MatchFlow._launch_battle`; empty / missing in standalone runs) once, sums `p1`
# per `KEY_*`, and exposes **query functions only**. The computation stays where it
# already lives, with one small hook call each:
#   • `BattleSim.seed_side_costs`           — `open_cost_bonus()`
#   • `CardPhaseManager.do_battle_turn`     — `consume_auto_draw_count()` · `cost_tick_gain(turn)`
#   • `BattleSim.max_hand_size_for`         — `hand_size_delta()`
#   • `BattleSim.effective_cost_for`        — `first_card_cost_delta(is_player)`
#   • `CardPhaseManager._play_card_direct`  — `on_player_card_paid()` (+ snapshot / restore)
#   • `CardPhaseManager.start/end_card_phase` — `reset_phase()`
# The AI side never reads any of this. With no traits every query returns the
# neutral value, so the battle runs exactly as before.
#
# Built in `BattleSim._ready` **before** `_populate_from_data_loader()` so the
# opening strategy points (seeded there) can already see `open_cost`.

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── `traits.key` values (layer = ingame) ────────────────────────────────────
const KEY_OPEN_COST       := "open_cost"        # opening strategy points +p1
const KEY_FIRST_DRAW      := "first_draw"       # first automatic draw ±p1 cards (≥ 0)
const KEY_HAND_SIZE       := "hand_size"        # max hand size ±p1 (≥ HAND_SIZE_FLOOR)
const KEY_FIRST_CARD_COST := "first_card_cost"  # first card of each 작전 단계 ±p1 (≥ 0)
const KEY_COST_TICK       := "cost_tick"        # +p1 strategy points every p2 turns

## Lowest max hand size a trait can push the player to.
const HAND_SIZE_FLOOR := 1

## Short on-screen labels for traits that arrive without a table id (harness ctx).
const KEY_LABELS := {  # l10n-keys: battle.trait.label.*
	KEY_OPEN_COST: L.BATTLE_TRAIT_LABEL_OPEN_COST,
	KEY_FIRST_DRAW: L.BATTLE_TRAIT_LABEL_FIRST_DRAW,
	KEY_HAND_SIZE: L.BATTLE_TRAIT_LABEL_HAND_SIZE,
	KEY_FIRST_CARD_COST: L.BATTLE_TRAIT_LABEL_FIRST_CARD_COST,
	KEY_COST_TICK: L.BATTLE_TRAIT_LABEL_COST_TICK,
}

## Parsed traits as given (`[{id, key, p1, p2}]`) — the banner lists these.
var traits: Array = []
## `key → Σp1` for every additive key.
var _sums: Dictionary = {}
## `cost_tick` entries `[{p1, p2}]` — each ticks on its own period.
var _ticks: Array = []

# ─── Runtime state (reset per match via `reset_runtime`) ─────────────────────
## The first automatic draw of the match has happened.
var _first_draw_done: bool = false
## The player has already paid for a card in the current 작전 단계. Public:
## `CardPhaseManager` snapshots it so a cancelled play refunds the discount.
var first_card_used: bool = false


## The start-of-battle banner has been shown for this match.
var _banner_shown: bool = false


func _ready() -> void:
	load_from_ctx()


# Waits for the opening (GAMBIT → BATTLE) and shows the trait banner once.
# Processing switches itself off afterwards, so this costs nothing per frame.
func _process(_delta: float) -> void:
	if _banner_shown or not has_any():
		set_process(false)
		return
	if _bs == null or _bs.game_phase == GameEnums.BattlePhase.GAMBIT:
		return
	_banner_shown = true
	set_process(false)
	var banner := TraitBanner.new()
	banner.name = "TraitBanner"
	_bs.add_child(banner)
	banner.show_lines(display_lines())


## (Re)reads `match_ctx.traits`. Only an active match (MatchFlow ran) carries
## traits — a stale ctx from an earlier match never leaks into a standalone run.
func load_from_ctx() -> void:
	traits.clear()
	_sums.clear()
	_ticks.clear()
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or not bool(gm.match_ctx.get("active", false)):
		reset_runtime()
		return
	for raw in gm.match_ctx.get("traits", []):
		if not (raw is Dictionary):
			continue
		var t: Dictionary = raw
		var key: String = String(t.get("key", ""))
		var p1: int = int(t.get("p1", 0))
		var p2: int = int(t.get("p2", 0))
		traits.append({"id": int(t.get("id", -1)), "key": key, "p1": p1, "p2": p2})
		if key == KEY_COST_TICK:
			if p2 > 0 and p1 != 0:
				_ticks.append({"p1": p1, "p2": p2})
		else:
			_sums[key] = int(_sums.get(key, 0)) + p1
	reset_runtime()


## Per-match runtime state back to the opening (also used by the restart button).
func reset_runtime() -> void:
	_first_draw_done = false
	first_card_used = false
	_banner_shown = false
	set_process(has_any())


func has_any() -> bool:
	return not traits.is_empty()


func sum_of(key: String) -> int:
	return int(_sums.get(key, 0))


# ─── Queries ─────────────────────────────────────────────────────────────────
## Extra opening strategy points for the player (`seed_side_costs`).
func open_cost_bonus() -> int:
	return sum_of(KEY_OPEN_COST)


## How many cards the player's automatic draw takes **this time**. The first call
## of the match returns `1 + Σfirst_draw` (never below 0), every later call 1.
func consume_auto_draw_count() -> int:
	if _first_draw_done:
		return 1
	_first_draw_done = true
	var n: int = maxi(0, 1 + sum_of(KEY_FIRST_DRAW))
	if n != 1 and _bs != null and _bs.blog != null:
		_bs.blog.log_event("TRAIT", "첫 자동 드로우 %d장" % n)  # l10n-ignore
	return n


## Player max-hand-size offset (BattleSim applies the floor).
func hand_size_delta() -> int:
	return sum_of(KEY_HAND_SIZE)


## Cost offset for the player's first card of the current 작전 단계. 0 for the
## AI, once a card has been paid for, or without the trait.
func first_card_cost_delta(is_player: bool) -> int:
	if not is_player or first_card_used:
		return 0
	return sum_of(KEY_FIRST_CARD_COST)


## Player paid for a card — later cards in this phase are priced normally.
func on_player_card_paid() -> void:
	first_card_used = true


## New / closed player 작전 단계 — the next card is "first" again.
func reset_phase() -> void:
	first_card_used = false


## Strategy points the player gains on BATTLE turn `turn` (the turn just
## finished, 1-based). Ticks fire at `ECONOMY_START_TURN + k·p2` for k ≥ 1.
func cost_tick_gain(turn: int) -> int:
	if _ticks.is_empty() or _bs == null:
		return 0
	var since: int = turn - _bs.ECONOMY_START_TURN
	if since <= 0:
		return 0
	var gain: int = 0
	for raw in _ticks:
		var e: Dictionary = raw
		if since % int(e["p2"]) == 0:
			gain += int(e["p1"])
	return gain


# ─── Display ─────────────────────────────────────────────────────────────────
## One line per trait — table name + filled description when the id is known,
## otherwise a key-based fallback.
func display_lines() -> Array:
	var out: Array = []
	for raw in traits:
		var t: Dictionary = raw
		var tid: int = int(t["id"])
		var r: Dictionary = TraitSystem.row(tid) if tid >= 0 else {}
		if not r.is_empty():
			out.append("%s · %s" % [TraitSystem.name_of(tid), TraitSystem.desc_of(tid)])
			continue
		var key: String = String(t["key"])
		if key == KEY_COST_TICK:
			out.append(Loc.t(L.BATTLE_TRAIT_COST_TICK_LINE,
					{"turns": int(t["p2"]), "delta": "%+d" % int(t["p1"])}))
			continue
		var label: String = key
		if KEY_LABELS.has(key):
			label = Loc.t(KEY_LABELS[key])  # l10n-dynamic: battle.trait.label.*
		out.append("%s %+d" % [label, int(t["p1"])])
	return out
