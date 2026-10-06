class_name PilotMods
extends RefCounted

# ── 선수 일시 보정 (M7 사건 · 외출 등) ─────────────────────────────────────────
# `season_state.pilot_mods` = `[{pilot_id, stat, delta, weeks_left, source}]`.
# - `stat` 은 `PlayerData.STAT_KEYS` 하나 또는 `"all"`(여섯 스탯 모두).
# - `weeks_left` > 0 = 주 마감마다 1 줄어 0 이면 사라진다. **-1 = 다음 경기까지**
#   (내 경기 결과를 소비할 때 `consume_match` 가 지운다).
#
# 보정은 **원본 선수에 쓰지 않는다** — 경기에 나가는 로스터 **사본**에만 얹는다
# (`MatchFlow` 가 사본을 만들 때 `apply_to`). 원본에 쓰면 훈련 성장과 섞여
# 보정이 끝나도 되돌릴 수 없다.


static func add(state: Dictionary, pilot_id: int, stat: String, delta: int,
		weeks: int, source: String = "") -> void:
	if delta == 0 or weeks == 0 or (stat != "all" and not PlayerData.STAT_KEYS.has(stat)):
		return
	var mods: Array = state.get("pilot_mods", [])
	mods.append({"pilot_id": pilot_id, "stat": stat, "delta": delta,
			"weeks_left": weeks, "source": source})
	state["pilot_mods"] = mods


## 이 선수에게 지금 걸린 보정 합 `{stat: delta}`(`all` 은 여섯으로 풀어 더한다).
static func of(state: Dictionary, pilot_id: int) -> Dictionary:
	var out: Dictionary = {}
	for raw in (state.get("pilot_mods", []) as Array):
		var m: Dictionary = raw
		if int(m.get("pilot_id", -1)) != pilot_id:
			continue
		var d: int = int(m.get("delta", 0))
		var stat: String = String(m.get("stat", ""))
		var keys: Array = PlayerData.STAT_KEYS if stat == "all" else [stat]
		for k in keys:
			out[k] = int(out.get(k, 0)) + d
	return out


## `pd` 에 보정을 얹는다 — **반드시 사본에** 부를 것. 하한은 `PlayerData.STAT_MIN`.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	var mods: Dictionary = of(state, pd.id)
	for k in mods.keys():
		pd.set(k, maxi(PlayerData.STAT_MIN, int(pd.get(k)) + int(mods[k])))


## 주 마감(`SeasonHub._end_week`)에 한 번.
static func decay_week(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("pilot_mods", []) as Array):
		var m: Dictionary = (raw as Dictionary).duplicate()
		var w: int = int(m.get("weeks_left", 0))
		if w < 0:
			kept.append(m)
			continue
		m["weeks_left"] = w - 1
		if w - 1 > 0:
			kept.append(m)
	state["pilot_mods"] = kept


## 내 경기 결과를 소비한 직후 한 번 — "다음 경기까지"(-1) 보정을 지운다.
static func consume_match(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("pilot_mods", []) as Array):
		if int((raw as Dictionary).get("weeks_left", 0)) != -1:
			kept.append(raw)
	state["pilot_mods"] = kept
