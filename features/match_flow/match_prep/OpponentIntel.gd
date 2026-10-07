class_name OpponentIntel
extends RefCounted

# ── Opponent intel (M5 analysis) — reveal rules as data ───────────────────────
# One builder for every screen that shows another team's roster: MatchFlow PREP
# and the league team detail sheet. Screens draw what this returns
# (`IntelView`), so the reveal rule lives in exactly one place.
#
# Reveal tier (`StaffSystem.analysis_tier`, thresholds `ANALYSIS_TIER_1..3`):
#   0  name + role only
#   1  + stats as ranges (`ANALYSIS_APPROX_STEP` wide buckets), total as "≈"
#   2  + exact stats + top-mastery mechs (`MechMastery.top_mechs`)
#   3  + the three fixed pilot cards (`GameManager.pilot_card_ids_for`)
# The player's own team is always FULL. Outside a season (MatchFlow run straight
# from the editor) everything is FULL too — there is no staff to ask.
#
# Interpretation: when analysis is delegated (`StaffSystem.is_delegated`), the
# result carries 1–2 short analyst lines (strongest lane, suggested ban). When
# the manager owns analysis the screen shows raw data only. The heuristic is
# deliberately simple — "reasonable", never optimal.

const TIER_NAME_ONLY: int = 0
const TIER_APPROX: int = 1
const TIER_MECHS: int = 2
const TIER_CARDS: int = 3
const FULL: int = TIER_CARDS

const TIER_LABELS: Array = [  # l10n-keys: match.intel.tier.*
	L.MATCH_INTEL_TIER_NAME_ONLY, L.MATCH_INTEL_TIER_APPROX, L.MATCH_INTEL_TIER_MECHS, L.MATCH_INTEL_TIER_FULL,
]

static var _mech_names: Dictionary = {}   # int mech id → l10n name key (`mechs.name_key`)
static var _mech_loaded: bool = false


# ── Tier ──────────────────────────────────────────────────────────────────────
## Reveal tier for a roster. `is_own` = the player's team (always FULL).
static func tier_for(state: Dictionary, is_own: bool) -> int:
	if is_own or not bool(state.get("active", false)):
		return FULL
	return clampi(StaffSystem.analysis_tier(state), TIER_NAME_ONLY, FULL)


## Effective analysis value needed for `tier` (0 for tier 0).
static func threshold_of(tier: int) -> int:
	if tier <= 0:
		return 0
	return ConstTable.int_of("ANALYSIS_TIER_%d" % clampi(tier, 1, 3))


# ── Roster lookup ─────────────────────────────────────────────────────────────
## Five `PlayerData` of a team in role order 0..4 — league teams (< 100) from
## `all_pilots`, INTL teams (>= 100) from `intl_pilots`. Same rule as
## `MatchFlow._team_roster`.
static func team_roster(state: Dictionary, team_id: int) -> Array:
	var pool: Array = state.get("intl_pilots", []) if team_id >= 100 \
			else state.get("all_pilots", [])
	var out: Array = []
	for r in 5:
		for raw in pool:
			var p := raw as PlayerData
			if p != null and p.team_id == team_id and p.role == r:
				out.append(p)
				break
	return out


# ── Builder ───────────────────────────────────────────────────────────────────
## → `{tier, tier_label, own, rows: [row], delegated, analyst, notes: [String],
##     analysis (effective value), next_need (value for the next tier, 0 at FULL)}`.
## A row (one per pilot, display order 탑 → 서폿):
##   `{pilot_id, name, role, role_label, show_stats, exact,
##     stats: [{label, text, value}], total_text,
##     show_mechs, mechs: [{mech_id, name, text}], show_cards, cards: [String]}`
## `value` is the exact stat for tier >= 2, the bucket midpoint at tier 1, -1 at 0.
static func build(state: Dictionary, roster: Array, is_own: bool) -> Dictionary:
	var tier: int = tier_for(state, is_own)
	var rows: Array = []
	var sorted: Array = roster.duplicate()
	sorted.sort_custom(func(a, b): return GameEnums.role_seat((a as PlayerData).role) \
			< GameEnums.role_seat((b as PlayerData).role))
	for raw in sorted:
		var p := raw as PlayerData
		if p != null:
			rows.append(_row_for(state, p, tier))
	var delegated: bool = not is_own and bool(state.get("active", false)) \
			and StaffSystem.is_delegated(state, "analysis")
	var out: Dictionary = {
		"tier": tier, "tier_label": Loc.t(String(TIER_LABELS[tier])), "own": is_own,  # l10n-dynamic: match.intel.tier.*
		"rows": rows, "delegated": delegated, "analyst": "", "notes": [],
		"analysis": StaffSystem.effective(state, "analysis") if bool(state.get("active", false)) else 0,
		"next_need": threshold_of(tier + 1) if tier < FULL else 0,
	}
	if delegated:
		out["analyst"] = analyst_label(state)
		out["notes"] = interpret(state, rows, tier)
	return out


## "서지안 (분석가)" / "한서준 (어시스턴트 매니저)" / "감독".
static func analyst_label(state: Dictionary) -> String:
	var who: String = StaffSystem.owner_name(state, "analysis")
	match StaffSystem.owner(state, "analysis"):
		StaffSystem.OWNER_STAFF:
			return "%s (%s)" % [who, StaffSystem.job_label("analyst")]
		StaffSystem.OWNER_ASSISTANT:
			return "%s (%s)" % [who, StaffSystem.job_label("assistant")]
	return Loc.t(L.TERM_PERSON_MANAGER)


## Analyst lines — at most two. Strongest lane (by visible stat total) and a
## suggested ban (the highest-mastery mech on their side). Lower tiers say what
## they cannot see instead of guessing.
static func interpret(_state: Dictionary, rows: Array, tier: int) -> Array:
	if tier <= TIER_NAME_ONLY or rows.is_empty():
		return [Loc.t(L.MATCH_INTEL_NOTE_NO_DATA)]
	var lines: Array = []
	var best: Dictionary = {}
	var best_total: int = -1
	var weak: Dictionary = {}
	var weak_total: int = 1 << 30
	for raw in rows:
		var r: Dictionary = raw
		var t: int = _row_total(r)
		if t > best_total:
			best_total = t
			best = r
		if t < weak_total:
			weak_total = t
			weak = r
	if not best.is_empty():
		lines.append(Loc.t(L.MATCH_INTEL_NOTE_THREAT, {
			"role": best["role_label"], "name": best["name"], "stat": _top_stat_label(best)}))
	var ban: Dictionary = _suggested_ban(rows) if tier >= TIER_MECHS else {}
	if not ban.is_empty():
		lines.append(Loc.t(L.MATCH_INTEL_NOTE_BAN, {"mech": ban["mech"], "pilot": ban["pilot"]}))
	elif not weak.is_empty() and weak != best:
		lines.append(Loc.t(L.MATCH_INTEL_NOTE_WEAK, {"role": weak["role_label"], "name": weak["name"]}))
	return lines


# ── Internals ─────────────────────────────────────────────────────────────────
static func _row_for(state: Dictionary, p: PlayerData, tier: int) -> Dictionary:
	var role_label: String = GameEnums.role_position_label(p.role)
	var row: Dictionary = {
		"pilot_id": p.id, "name": p.name, "role": p.role, "role_label": role_label,
		"show_stats": tier >= TIER_APPROX, "exact": tier >= TIER_MECHS,
		"stats": [], "total_text": "?",
		"show_mechs": tier >= TIER_MECHS, "mechs": [],
		"show_cards": tier >= TIER_CARDS, "cards": [],
	}
	var step: int = maxi(1, ConstTable.int_of("ANALYSIS_APPROX_STEP"))
	var total: int = 0
	var stats: Array = []
	for i in PlayerData.STAT_KEYS.size():
		var v: int = int(p.get(String(PlayerData.STAT_KEYS[i])))
		total += v
		var cell: Dictionary = {"label": PlayerData.stat_short(i), "text": "?", "value": -1}
		if tier >= TIER_MECHS:
			cell["text"] = "%d" % v
			cell["value"] = v
		elif tier >= TIER_APPROX:
			var lo: int = v - posmod(v, step)
			cell["text"] = "%d~%d" % [lo, lo + step - 1]
			cell["value"] = lo + int(step * 0.5)
		stats.append(cell)
	row["stats"] = stats
	if tier >= TIER_MECHS:
		row["total_text"] = "%d" % total
	elif tier >= TIER_APPROX:
		var tstep: int = step * 2
		row["total_text"] = "≈%d" % (roundi(float(total) / float(tstep)) * tstep)
	if tier >= TIER_MECHS:
		row["mechs"] = _mechs_for(state, p)
	if tier >= TIER_CARDS:
		row["cards"] = _card_names_for(p)
	return row


# Top-mastery mechs. Until mastery data exists (empty `top_mechs`), fall back to
# the pilot's main mechs (`players.main_mechs`) without a grade.
static func _mechs_for(state: Dictionary, p: PlayerData) -> Array:
	var n: int = maxi(1, ConstTable.int_of("ANALYSIS_TOP_MECHS"))
	var out: Array = []
	for raw in MechMastery.top_mechs(state, p.id, n):
		var e: Dictionary = raw
		var mid: int = int(e.get("mech_id", -1))
		var val: int = int(e.get("value", 0))
		out.append({"mech_id": mid, "value": val, "name": mech_name(mid),
				"text": "%s %s" % [mech_name(mid), MechMastery.tier_name(MechMastery.tier_of(val))]})
	if out.is_empty():
		for raw in p.main_mechs:
			if out.size() >= n:
				break
			var mid: int = int(raw)
			out.append({"mech_id": mid, "value": -1, "name": mech_name(mid),
					"text": Loc.t(L.MATCH_INTEL_MECH_MAIN, {"mech": mech_name(mid)})})
	return out


static func _card_names_for(p: PlayerData) -> Array:
	var gm: Node = _gm()
	if gm == null:
		return []
	var out: Array = []
	for raw in gm.pilot_card_ids_for(p):
		var def: Dictionary = gm.card_def(int(raw))
		if not def.is_empty():
			out.append(Loc.t(String(def.get("name_key", ""))))  # l10n-dynamic: card.pilot.*.name
	return out


static func _row_total(r: Dictionary) -> int:
	var t: int = 0
	for raw in (r["stats"] as Array):
		t += maxi(0, int((raw as Dictionary)["value"]))
	return t


static func _top_stat_label(r: Dictionary) -> String:
	var best_i: int = 0
	var best_v: int = -1
	var stats: Array = r["stats"]
	for i in stats.size():
		var v: int = int((stats[i] as Dictionary)["value"])
		if v > best_v:
			best_v = v
			best_i = i
	return PlayerData.stat_label(best_i)


# Highest-mastery mech on their side; ties (and the no-mastery fallback) go to
# the first main mech of the strongest pilot.
static func _suggested_ban(rows: Array) -> Dictionary:
	var pick: Dictionary = {}
	var pick_val: int = -2
	var pick_total: int = -1
	for raw in rows:
		var r: Dictionary = raw
		var mechs: Array = r["mechs"]
		if mechs.is_empty():
			continue
		var m: Dictionary = mechs[0]
		var v: int = int(m.get("value", -1))
		var t: int = _row_total(r)
		if v > pick_val or (v == pick_val and t > pick_total):
			pick_val = v
			pick_total = t
			pick = {"mech": String(m["name"]), "pilot": "%s %s" % [r["role_label"], r["name"]]}
	return pick


static func mech_name(mech_id: int) -> String:
	if not _mech_loaded:
		_mech_loaded = true
		var db := SQLite.new()
		db.path = GameDb.path()
		db.verbosity_level = SQLite.QUIET
		if db.open_db():
			db.query("SELECT id, name_key FROM mechs")
			for row in db.query_result:
				_mech_names[int(row["id"])] = String(row["name_key"])
			db.close_db()
	if not _mech_names.has(mech_id):
		return Loc.t(L.MATCH_INTEL_MECH_FALLBACK, {"id": mech_id})
	return Loc.t(String(_mech_names[mech_id]))  # l10n-dynamic: name.mech.*


static func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameManager")
