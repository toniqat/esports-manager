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

const PROFILE_PATH := "user://profile.save"
const PROFILE_BACKUP_PATH := "user://profile.save.bak"
const PROFILE_VERSION := 1

# 하위 키 하나까지 기본값으로 채우는 딕셔너리들.
const _NESTED_FILL_KEYS: Array = ["manager", "currency", "traits", "pass"]
# JSON 이 실수로 돌려주는 manager 의 정수 칸.
const _MANAGER_INT_KEYS: Array = ["type", "level", "exp", "prestige"]

var profile: Dictionary = {}


func _ready() -> void:
	var err: String = load_profile()
	if err != "":
		push_warning("ProfileManager: %s" % err)


func default_profile() -> Dictionary:
	return {
		"version": PROFILE_VERSION,
		# pilot_id(String) → {owned, max_level, breakthrough, dupes}
		"collection": {},
		"manager": {
			"type": 0,
			"level": 1,
			"exp": 0,
			"prestige": 0,
			"last_prestige_season": "",
			"alloc": {
				"training": 0, "tactics": 0, "knowledge": 0,
				"mental": 0, "analysis": 0, "finance": 0,
			},
		},
		"traits": {"owned": [], "unlocked_pending": []},
		"presets": [{"kind": "normal", "alloc": {}, "traits": []}],
		"active_preset": 0,
		"currency": {
			"outgame": 0, "levelup": 0,
			"gacha_ticket_pilot": 0, "gacha_ticket_trait": 0,
			"trait_mat": 0, "cosmetic": 0, "premium": 0, "pilot_shard": 0,
		},
		"pass": {"week_id": "", "exp": 0, "claimed": []},
		# pilot_id(String) → {pom, mvp, true_ending}
		"achievements": {},
		# Array of {scenario, team, score, result, phase_reached, at}
		"runs": [],
	}


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
	# alloc 는 한 단계 더 안쪽이지만 전문화 축이 늘어날 자리라 같이 채운다.
	var alloc: Dictionary = (default_profile()["manager"] as Dictionary)["alloc"]
	var src_alloc: Variant = mgr.get("alloc", null)
	if typeof(src_alloc) == TYPE_DICTIONARY:
		for ak in (src_alloc as Dictionary).keys():
			alloc[String(ak)] = int((src_alloc as Dictionary)[ak])
	mgr["alloc"] = alloc
	var cur: Dictionary = out["currency"]
	for ck in cur.keys():
		cur[ck] = int(cur[ck])
	var pass_d: Dictionary = out["pass"]
	pass_d["exp"] = int(pass_d.get("exp", 0))
	return out


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
