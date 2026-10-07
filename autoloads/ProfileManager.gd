extends Node

# 계정(프로필) 상태 — 런과 무관하게 영구히 남는 진척.
# user://profile.save 하나에 JSON 으로 담는다(`docs/outgame_dev_plan.md` §4).
# 런 상태(season_state)는 여기 없다 — 그쪽은 SaveSystem 의 run.save.
#
# 오토로드라 class_name 을 달지 않는다. 접근은
#   get_node("/root/ProfileManager").profile
#
# 불러오기 규칙:
#   - 파일이 없으면 기본 프로필을 만들어 바로 쓴다.
#   - 깨졌거나(JSON 아님 / 객체 아님) 읽을 수 없으면 경고 후 원본을
#     profile.save.bak 으로 옮겨 두고 기본 프로필로 덮어쓴다.
#   - 읽은 값은 기본 프로필 위에 얹는다 — 새 버전에서 늘어난 최상위 키,
#     manager / currency 안의 빠진 키가 기본값으로 채워진다.
#
# M8~M10 (계획서 §12): 특성 보유 · 프리셋 · 감독 성장 · 재화 · 선수 성장 · 패스.
# 규칙은 순수 모듈이 갖고(`TraitSystem` · `ManagerProgress` · `PassSystem` · `RunRules`),
# 여기는 그 규칙을 프로필에 적용하는 얇은 API 다. **M8 이후의 변경 함수는 저장하지
# 않는다** — 화면이 한 번의 조작 끝에 `save_profile()` 을 부른다.

const PROFILE_PATH := "user://profile.save"
const PROFILE_BACKUP_PATH := "user://profile.save.bak"
const PROFILE_VERSION := 2

# 하위 키 하나까지 기본값으로 채우는 딕셔너리들.
const _NESTED_FILL_KEYS: Array = ["manager", "currency", "traits", "pass"]
# JSON 이 실수로 돌려주는 manager 의 정수 칸.
const _MANAGER_INT_KEYS: Array = ["type", "level", "exp", "prestige"]
# `runs`(런 기록)에 남기는 최대 줄 수 — 파일이 끝없이 자라지 않게 하는 보관 한도.
const RUNS_HISTORY_MAX: int = 50

var profile: Dictionary = {}
var _rarity_cache: Dictionary = {}   # int pilot_id → players.rarity


## 로케일은 **`_init` 에서** 정한다 — 엔진은 오토로드를 전부 인스턴스(`_init`)한 뒤에
## 트리에 붙이므로(`_ready`), 여기서 정하면 순서상 앞선 `GameManager._ready` 를 포함해
## 어떤 오토로드 · 씬이 글을 만들기 전이다. 프로필 전체 로드(`_ready`)는 ConstTable ·
## game.db 를 쓰므로 이 시점엔 `locale` 칸만 엿본다(설계서 D11 · §10.4).
func _init() -> void:
	Loc.set_locale(Loc.pick_initial_locale(_peek_saved_locale()))


func _ready() -> void:
	var err: String = load_profile()
	if err != "":
		push_warning("ProfileManager: %s" % err)
	var changed: bool = ensure_starter_collection()
	changed = ensure_default_traits() or changed
	if changed:
		save_profile()


# ── 컬렉션 (M1) ──────────────────────────────────────────────────────────────
## 컬렉션이 비어 있으면 `players.starter = 1` 인 선수들을 Lv1 로 지급한다.
## 무언가 지급했으면 true(호출자가 저장한다).
func ensure_starter_collection() -> bool:
	var col: Dictionary = profile["collection"]
	if not col.is_empty():
		return false
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("ProfileManager: cannot open game.db for starter pilots")
		return false
	db.query("SELECT id FROM players WHERE starter = 1 ORDER BY id")
	for row in db.query_result:
		col[str(int(row["id"]))] = _new_collection_entry()
	db.close_db()
	return not col.is_empty()


func _new_collection_entry() -> Dictionary:
	return {"owned": true, "max_level": 1, "breakthrough": 0, "dupes": 0, "exp": 0}


## 보유한 선수 id 목록(int, 오름차순).
func owned_pilot_ids() -> Array:
	var out: Array = []
	for k in (profile["collection"] as Dictionary).keys():
		var e: Dictionary = profile["collection"][k]
		if bool(e.get("owned", false)):
			out.append(int(k))
	out.sort()
	return out


## 달성 최대 레벨. 보유하지 않았으면 0.
func max_level_of(pilot_id: int) -> int:
	var e: Variant = (profile["collection"] as Dictionary).get(str(pilot_id), null)
	if typeof(e) != TYPE_DICTIONARY or not bool((e as Dictionary).get("owned", false)):
		return 0
	return maxi(1, int((e as Dictionary).get("max_level", 1)))


## `RunRules.validate_lineup` 의 `owned_max_levels` 모양 — {"<pilot_id>": max_level}.
func owned_max_levels() -> Dictionary:
	var out: Dictionary = {}
	for pid in owned_pilot_ids():
		out[str(pid)] = max_level_of(int(pid))
	return out


## M10 — 돌파 단계. 보유하지 않았으면 0.
func breakthrough_of(pilot_id: int) -> int:
	if max_level_of(pilot_id) <= 0:
		return 0
	return int((profile["collection"][str(pilot_id)] as Dictionary).get("breakthrough", 0))


## M10 — 보유 선수의 돌파 `{"<pilot_id>": stage}`(0 단계는 빠진다). 런 시작 · 편성 풀이 쓴다.
func owned_breakthroughs() -> Dictionary:
	var out: Dictionary = {}
	for pid in owned_pilot_ids():
		var st: int = breakthrough_of(int(pid))
		if st > 0:
			out[str(pid)] = st
	return out


## M10 — 선수 EXP(누적).
func pilot_exp_of(pilot_id: int) -> int:
	var e: Variant = (profile["collection"] as Dictionary).get(str(pilot_id), null)
	return int((e as Dictionary).get("exp", 0)) if typeof(e) == TYPE_DICTIONARY else 0


## M10 — 선수 획득(가챠 · 확정 구매). 미보유 → 새로 보유(Lv1). 보유 중 → 중복:
## 돌파 단계 +1(`BREAKTHROUGH_MAX` 까지), 그 뒤로는 선수 파편
## (`SHARD_PER_EXTRA_DUPE` × 등급). → `{result: "new"|"breakthrough"|"shard", stage, shards}`.
func grant_pilot(pilot_id: int) -> Dictionary:
	var col: Dictionary = profile["collection"]
	var key: String = str(pilot_id)
	if max_level_of(pilot_id) <= 0:
		var fresh: Dictionary = _new_collection_entry()
		var old: Variant = col.get(key, null)
		if typeof(old) == TYPE_DICTIONARY:
			fresh["exp"] = int((old as Dictionary).get("exp", 0))
		col[key] = fresh
		return {"result": "new", "stage": 0, "shards": 0}
	var e: Dictionary = col[key]
	e["dupes"] = int(e.get("dupes", 0)) + 1
	if int(e.get("breakthrough", 0)) < RunRules.breakthrough_max():
		e["breakthrough"] = int(e.get("breakthrough", 0)) + 1
		return {"result": "breakthrough", "stage": int(e["breakthrough"]), "shards": 0}
	var shards: int = maxi(1, ConstTable.int_of("SHARD_PER_EXTRA_DUPE") * maxi(1, pilot_rarity(pilot_id)))
	add_currency("pilot_shard", shards)
	return {"result": "shard", "stage": int(e["breakthrough"]), "shards": shards}


## M10 — 선수 EXP 를 더하고 최대 레벨을 EXP 표(`pilot_levels.exp_required`)까지
## 자동으로 올린다(내리지는 않는다). → `{from, to}`.
func add_pilot_exp(pilot_id: int, amount: int) -> Dictionary:
	var from_lv: int = max_level_of(pilot_id)
	if from_lv <= 0:
		return {"from": 0, "to": 0}
	var e: Dictionary = profile["collection"][str(pilot_id)]
	e["exp"] = int(e.get("exp", 0)) + maxi(0, amount)
	var to_lv: int = maxi(from_lv, mini(RunRules.max_level(), RunRules.level_for_exp(int(e["exp"]))))
	e["max_level"] = to_lv
	return {"from": from_lv, "to": to_lv}


## M10 — 최대 레벨 +1 에 드는 레벨업 재화. 올릴 수 없으면 -1.
func level_up_cost(pilot_id: int) -> int:
	var lv: int = max_level_of(pilot_id)
	if lv <= 0 or lv >= RunRules.max_level():
		return -1
	return RunRules.levelup_cost(lv + 1)


## M10 — 레벨업 재화로 최대 레벨 +1. 성공이면 "".
func level_up_pilot(pilot_id: int) -> String:
	var cost: int = level_up_cost(pilot_id)
	if cost < 0:
		return "더 올릴 수 없습니다"
	if not spend_currency("levelup", cost):
		return "레벨업 재화가 부족합니다 (%d 필요)" % cost
	var e: Dictionary = profile["collection"][str(pilot_id)]
	e["max_level"] = int(e.get("max_level", 1)) + 1
	return ""


## `players.rarity` (캐시). 모르는 선수는 0.
func pilot_rarity(pilot_id: int) -> int:
	if _rarity_cache.is_empty():
		var db := SQLite.new()
		db.path = GameDb.path()
		db.verbosity_level = SQLite.QUIET
		if db.open_db():
			db.query("SELECT id, rarity FROM players")
			for row in db.query_result:
				_rarity_cache[int(row["id"])] = int(row["rarity"])
			db.close_db()
	return int(_rarity_cache.get(pilot_id, 0))



# ── 재화 (M10) ───────────────────────────────────────────────────────────────
## 재화 키는 `default_profile().currency` 의 여덟 개.
func currency_of(key: String) -> int:
	return int((profile["currency"] as Dictionary).get(key, 0))


func add_currency(key: String, amount: int) -> void:
	var cur: Dictionary = profile["currency"]
	cur[key] = maxi(0, int(cur.get(key, 0)) + amount)


## 모자라면 아무것도 하지 않고 false.
func spend_currency(key: String, amount: int) -> bool:
	if amount < 0 or currency_of(key) < amount:
		return false
	add_currency(key, -amount)
	return true


# ── 특성 (M8) ────────────────────────────────────────────────────────────────
## 보유 특성이 비어 있으면 `traits.default_owned = 1` 인 것을 지급한다. 지급했으면 true.
func ensure_default_traits() -> bool:
	var tr: Dictionary = profile["traits"]
	if not (tr.get("owned", []) as Array).is_empty():
		return false
	var ids: Array = TraitSystem.default_owned_ids()
	tr["owned"] = ids.duplicate()
	return not ids.is_empty()


func owned_trait_ids() -> Array:
	var out: Array = []
	for raw in ((profile["traits"] as Dictionary).get("owned", []) as Array):
		out.append(int(raw))
	return out


func owns_trait(trait_id: int) -> bool:
	return owned_trait_ids().has(trait_id)


## 특성 획득(해금 · 가챠 · 제작). 미보유 → 보유. 보유 중 → 특성 재료
## (`TRAIT_DUPE_MAT` × (등급 + 1)). → `{result: "new"|"material", amount}`.
func grant_trait(trait_id: int) -> Dictionary:
	var tr: Dictionary = profile["traits"]
	var owned: Array = tr.get("owned", [])
	if not owned_trait_ids().has(trait_id):
		owned.append(trait_id)
		tr["owned"] = owned
		return {"result": "new", "amount": 0}
	var rar: int = int(TraitSystem.row(trait_id).get("rarity", 0))
	var mat: int = maxi(1, ConstTable.int_of("TRAIT_DUPE_MAT") * (rar + 1))
	add_currency("trait_mat", mat)
	return {"result": "material", "amount": mat}


# ── 런 정산 (M2) ─────────────────────────────────────────────────────────────
## 정산 결과를 프로필에 반영하고 저장한다. `result` 모양은
## `docs/outgame_dev_plan.md` §10.3. 성공이면 "".
##
##
## 쓰는 것: `currency.outgame` += 재화, `manager.exp` += 감독 EXP(레벨업은 M9),
## `achievements[pid].mvp / .pom` += 이번 런 횟수(내 선수만, 없던 선수는 새 칸),
## `runs` 맨 뒤에 한 줄(`RUNS_HISTORY_MAX` 를 넘으면 오래된 것부터 버린다).
## 같은 결과(`result.id`)가 이미 `runs` 에 있으면 아무것도 하지 않는다 — 정산이
## 두 번 불려도 재화가 두 번 붙지 않게.
func apply_run_result(result: Dictionary) -> String:
	var run_id: String = String(result.get("id", ""))
	var runs: Array = profile["runs"]
	if run_id != "":
		for r in runs:
			if typeof(r) == TYPE_DICTIONARY and String((r as Dictionary).get("id", "")) == run_id:
				return ""

	# M10 — every currency the result pays (`outgame`, `levelup`, …).
	var gained: Dictionary = result.get("currency", {})
	for ck in gained.keys():
		add_currency(String(ck), maxi(0, int(gained[ck])))
	# M9 — manager exp → level-ups (removal points follow the level).
	var delta: Dictionary = {}
	delta["manager"] = ManagerProgress.add_exp(profile, int(result.get("manager_exp", 0)))
	# M10 — pilot exp (my five) → automatic max-level ups.
	var pilot_delta: Dictionary = {}
	var pexp: Dictionary = result.get("pilot_exp", {})
	for pk in pexp.keys():
		var d: Dictionary = add_pilot_exp(int(pk), int(pexp[pk]))
		if int(d["to"]) > int(d["from"]):
			pilot_delta[str(int(pk))] = d
	delta["pilots"] = pilot_delta
	# M10 — weekly pass exp.
	delta["pass"] = PassSystem.add_exp(profile, int(result.get("pass_exp", 0)))
	# M8 — traits unlocked by this run (`TraitSystem.evaluate_unlocks`).
	var new_traits: Array = []
	var tr: Dictionary = profile["traits"]
	var pending: Array = tr.get("unlocked_pending", [])
	for raw in (result.get("unlocked_traits", []) as Array):
		var tid: int = int(raw)
		if owns_trait(tid):
			continue
		grant_trait(tid)
		new_traits.append(tid)
		if not pending.has(tid):
			pending.append(tid)
	tr["unlocked_pending"] = pending
	delta["traits"] = new_traits
	result["profile_delta"] = delta

	var ach: Dictionary = profile["achievements"]
	var run_ach: Dictionary = result.get("achievements", {})
	for k in run_ach.keys():
		var add: Dictionary = run_ach[k]
		var add_mvp: int = int(add.get("mvp", 0))
		var add_pom: int = int(add.get("pom", 0))
		if add_mvp <= 0 and add_pom <= 0:
			continue
		var key: String = str(int(k))
		var e: Dictionary = ach.get(key, {"pom": 0, "mvp": 0, "true_ending": false})
		e["mvp"] = int(e.get("mvp", 0)) + add_mvp
		e["pom"] = int(e.get("pom", 0)) + add_pom
		if not e.has("true_ending"):
			e["true_ending"] = false
		ach[key] = e

	# M7 — 진엔딩(런 클리어 + 외출 조건)을 본 선수. 한 번 켜지면 꺼지지 않는다.
	for raw_pid in (result.get("true_endings", []) as Array):
		var tkey: String = str(int(raw_pid))
		var te: Dictionary = ach.get(tkey, {"pom": 0, "mvp": 0, "true_ending": false})
		te["true_ending"] = true
		ach[tkey] = te

	runs.append({
		"id": run_id,
		"scenario": int(result.get("scenario", 0)),
		"team": int(result.get("team_id", 0)),
		"score": int(result.get("score", 0)),
		"result": "clear" if String(result.get("outcome", "")) == "clear" else "fail",
		"phase_reached": int(result.get("phase_reached", 0)),
		"at": String(result.get("at", "")),
	})
	while runs.size() > RUNS_HISTORY_MAX:
		runs.pop_front()
	return save_profile()


# ── 감독 (M3) ────────────────────────────────────────────────────────────────
## 감독 타입(`manager_types.id`)을 정하고 저장한다. 첫 로비의 타입 선택 팝업이
## 부른다 — 이후 바꾸는 길은 프레스티지(M9)뿐.
func set_manager_type(type_id: int) -> String:
	var mgr: Dictionary = profile["manager"]
	mgr["type"] = type_id
	mgr["type_chosen"] = true
	return save_profile()


func manager_type_chosen() -> bool:
	return bool((profile["manager"] as Dictionary).get("type_chosen", false))


func default_profile() -> Dictionary:
	return {
		"version": PROFILE_VERSION,
		# 고른 언어의 로케일 코드(`L.LOCALES` 중 하나). "" = 고른 적 없음 → 기기 언어(D11).
		"locale": "",
		# pilot_id(String) → {owned, max_level, breakthrough, dupes}
		"collection": {},
		"manager": {
			"type": 0,
			# 감독 타입을 고른 적이 있는가 — 첫 로비가 타입 선택 팝업을 띄우는 근거(M3).
			"type_chosen": false,
			"level": 1,
			"exp": 0,
			"prestige": 0,
			"last_prestige_season": "",
			# M9 — permanent removals per stat (until prestige) — `ManagerProgress`.
			"removed": {},
			"alloc": {
				"training": 0, "tactics": 0, "knowledge": 0,
				"mental": 0, "analysis": 0, "finance": 0,
			},
		},
		# M8 — owned trait ids, ids unlocked but not yet seen on the manager screen.
		"traits": {"owned": [], "unlocked_pending": []},
		# M9 — presets `{kind: normal|prestige, alloc: {stat: int}, traits: [id]}`.
		"presets": _default_presets(),
		"active_preset": 0,
		"currency": {
			"outgame": 0, "levelup": 0,
			"gacha_ticket_pilot": 0, "gacha_ticket_trait": 0,
			"trait_mat": 0, "cosmetic": 0, "premium": 0, "pilot_shard": 0,
		},
		# M10 — weekly pass `{week_id, exp, claimed: [level], overflow}` — `PassSystem`.
		"pass": {"week_id": "", "exp": 0, "claimed": [], "overflow": 0},
		# pilot_id(String) → {pom, mvp, true_ending}
		"achievements": {},
		# Array of {scenario, team, score, result, phase_reached, at}
		"runs": [],
	}


func _default_presets() -> Array:
	var out: Array = []
	for i in maxi(1, ConstTable.int_of("PRESET_BASE_COUNT")):
		out.append(ManagerProgress.new_preset())
	return out


# ── 언어 (l10n M5) ──────────────────────────────────────────────────────────
## 저장된 로케일 코드. "" = 고른 적 없음.
func saved_locale() -> String:
	return String(profile.get("locale", ""))


## 언어를 바꾸고 **바로 저장한다**(설정 팝업의 한 번 조작). 성공이면 "".
## 화면 텍스트 갱신은 부르는 쪽이 현재 씬을 다시 로드해서 한다(§10.4).
func set_locale(code: String) -> String:
	if not L.LOCALES.has(code):
		return "unsupported locale '%s'" % code
	Loc.set_locale(code)
	profile["locale"] = code
	return save_profile()


# profile.save 의 `locale` 칸만 읽는다(없음 · 깨짐 → ""). `_init` 전용 — 깨진 파일
# 처리(.bak)는 `_ready` 의 `load_profile` 몫이다.
func _peek_saved_locale() -> String:
	if not FileAccess.file_exists(PROFILE_PATH):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var v: Variant = (parsed as Dictionary).get("locale", "")
	return String(v) if typeof(v) == TYPE_STRING else ""


# 디스크에서 프로필을 읽어 `profile` 에 싣는다. 성공이면 "" — 파일이 없거나
# 깨져 기본값으로 갈아 끼운 경우에도 `profile` 은 항상 쓸 수 있는 상태가 된다.
func load_profile() -> String:
	if not FileAccess.file_exists(PROFILE_PATH):
		profile = default_profile()
		return save_profile()
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return _reset_corrupt("cannot open (err=%d)" % FileAccess.get_open_error())
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _reset_corrupt("not a JSON object")
	profile = _merge_over_defaults(parsed)
	return ""


# 지금 `profile` 을 디스크에 쓴다. 성공이면 "".
func save_profile() -> String:
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		return "cannot open %s for write (err=%d)" % [PROFILE_PATH, FileAccess.get_open_error()]
	f.store_string(JSON.stringify(profile))
	f.close()
	return ""


# 깨진 원본은 .bak 으로 옮겨 두고(조용히 덮어쓰지 않는다) 기본 프로필로 새로 쓴다.
func _reset_corrupt(why: String) -> String:
	push_warning("ProfileManager: %s %s — backing up to %s and resetting"
		% [PROFILE_PATH, why, PROFILE_BACKUP_PATH])
	DirAccess.copy_absolute(PROFILE_PATH, PROFILE_BACKUP_PATH)
	profile = default_profile()
	return save_profile()


# 읽은 값을 기본 프로필 위에 얹는다. 최상위는 키 단위로 덮고, 자주 늘어날
# 하위 딕셔너리(_NESTED_FILL_KEYS)는 한 단계 안쪽까지 빠진 키를 채운다.
# 타입이 다른 값(예: manager 자리에 배열)은 버리고 기본값을 쓴다.
func _merge_over_defaults(loaded: Dictionary) -> Dictionary:
	var out: Dictionary = default_profile()
	for k in loaded.keys():
		var key: String = String(k)
		if out.has(key) and typeof(out[key]) != typeof(loaded[k]) \
				and not (_is_number(out[key]) and _is_number(loaded[k])):
			continue
		if key in _NESTED_FILL_KEYS:
			var merged: Dictionary = out[key]
			var src: Dictionary = loaded[k]
			for sk in src.keys():
				merged[String(sk)] = src[sk]
			out[key] = merged
		else:
			out[key] = loaded[k]

	# JSON 은 수를 전부 실수로 돌려준다 — 정수 칸을 되돌린다.
	out["version"] = int(out["version"])
	out["active_preset"] = int(out["active_preset"])
	var mgr: Dictionary = out["manager"]
	for mk in _MANAGER_INT_KEYS:
		mgr[mk] = int(mgr.get(mk, 0))
	mgr["type_chosen"] = bool(mgr.get("type_chosen", false))
	# alloc 는 한 단계 더 안쪽이지만 전문화 축이 늘어날 자리라 같이 채운다.
	var alloc: Dictionary = (default_profile()["manager"] as Dictionary)["alloc"]
	var src_alloc: Variant = mgr.get("alloc", null)
	if typeof(src_alloc) == TYPE_DICTIONARY:
		for ak in (src_alloc as Dictionary).keys():
			alloc[String(ak)] = int((src_alloc as Dictionary)[ak])
	mgr["alloc"] = alloc
	var removed_d: Dictionary = {}
	var src_rm: Variant = mgr.get("removed", null)
	if typeof(src_rm) == TYPE_DICTIONARY:
		for rk in (src_rm as Dictionary).keys():
			removed_d[String(rk)] = int((src_rm as Dictionary)[rk])
	mgr["removed"] = removed_d
	var cur: Dictionary = out["currency"]
	for ck in cur.keys():
		cur[ck] = int(cur[ck])
	var pass_d: Dictionary = out["pass"]
	pass_d["exp"] = int(pass_d.get("exp", 0))
	pass_d["overflow"] = int(pass_d.get("overflow", 0))
	pass_d["claimed"] = _int_array(pass_d.get("claimed", []))
	# M8 — trait ids back to int.
	var tr: Dictionary = out["traits"]
	tr["owned"] = _int_array(tr.get("owned", []))
	tr["unlocked_pending"] = _int_array(tr.get("unlocked_pending", []))
	# M9 — presets: normalise each, pad up to PRESET_BASE_COUNT (v1 had one).
	var presets: Array = []
	var src_ps: Variant = out.get("presets", [])
	if typeof(src_ps) == TYPE_ARRAY:
		for raw in (src_ps as Array):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = ManagerProgress.new_preset(
					String((raw as Dictionary).get("kind", ManagerProgress.KIND_NORMAL)))
			var src_a: Variant = (raw as Dictionary).get("alloc", {})
			if typeof(src_a) == TYPE_DICTIONARY:
				for ak2 in (src_a as Dictionary).keys():
					if (p["alloc"] as Dictionary).has(String(ak2)):
						p["alloc"][String(ak2)] = int((src_a as Dictionary)[ak2])
			p["traits"] = _int_array((raw as Dictionary).get("traits", []))
			presets.append(p)
	while presets.size() < maxi(1, ConstTable.int_of("PRESET_BASE_COUNT")):
		presets.append(ManagerProgress.new_preset())
	out["presets"] = presets
	out["active_preset"] = clampi(int(out["active_preset"]), 0, presets.size() - 1)
	# M10 — collection entries: ints, `exp` added.
	var col: Dictionary = out["collection"]
	for pk in col.keys():
		var e: Variant = col[pk]
		if typeof(e) != TYPE_DICTIONARY:
			col.erase(pk)
			continue
		var ed: Dictionary = e
		for ik in ["max_level", "breakthrough", "dupes", "exp"]:
			ed[ik] = int(ed.get(ik, 1 if ik == "max_level" else 0))
		ed["owned"] = bool(ed.get("owned", false))
	out["version"] = PROFILE_VERSION
	return out


func _int_array(v: Variant) -> Array:
	var out_a: Array = []
	if typeof(v) == TYPE_ARRAY:
		for raw in (v as Array):
			out_a.append(int(raw))
	return out_a


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
