class_name BattleLogger
extends Node

## 전투 시뮬레이션 **행동 로그**. BattleSim 의 자식으로 `_ready()` 에서 붙는다.
##
## 목적은 두 가지다:
##   1. 한 턴 안에서 일어난 **모든** 상태 변화(리스폰 · 리콜 · 교전 판정 ·
##      데미지 · 사망 · 자유 이동(스텝 단위) · 푸시 · 포탑 · 정글 점령 ·
##      HQ 타격 · 카드 사용)를 시간 순서대로 남긴다.
##   2. 턴 시작/끝 스냅샷을 비교해 **적 파일럿끼리 서로를 통과해 버리는
##      교차(cross-over)** 를 자동으로 잡아낸다.
##
## 교차 판정은 "팀0 HQ 로부터의 hex 거리"를 레인 축으로 삼는다. 턴 시작 시
## A 가 B 보다 팀0 HQ 쪽에 있었는데 턴이 끝난 뒤 반대가 되었고, 그러면서
## 둘이 같은 칸에 있지도 않다면 = 서로를 통과한 것이다.
##
## 출력은 콘솔(print)과 `user://battle_logs/battle_<timestamp>.log` 파일 양쪽.
## 실제 경로는 Godot 콘솔 첫 줄에 절대 경로로 찍힌다.

const LOG_DIR := "user://battle_logs"

## 로그 자체를 끄는 스위치. 끄면 모든 메서드가 즉시 반환한다.
var enabled: bool = true
## 콘솔(print) 미러링.
var echo_to_console: bool = true
## user:// 파일 기록.
var write_to_file: bool = true

var _bs: BattleSim = null
var _file: FileAccess = null
var _abs_path: String = ""

## 턴 시작 시점의 파일럿 좌표 스냅샷. PilotData → Vector2i
var _turn_start_pos: Dictionary = {}
## 이번 턴에 기록된 이동 내역. {pilot, from, to, stage, note}
var _turn_moves: Array = []
## 현재 시뮬레이션 단계 태그 — 모든 로그 줄에 함께 찍힌다.
var _stage: String = "init"
## 교차가 감지된 누적 횟수 (요약용).
var cross_events: int = 0


func bind(bs: BattleSim) -> void:
	_bs = bs
	_open_file()
	_write_header()


func _exit_tree() -> void:
	close()


func close() -> void:
	if _file != null:
		_file.store_line("=== log closed (cross events: %d) ===" % cross_events)
		_file.flush()
		_file.close()
		_file = null


# ─── File plumbing ───────────────────────────────────────────────────────────

func _open_file() -> void:
	if not write_to_file:
		return
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	# ':' is illegal in Windows filenames, so flatten the ISO timestamp.
	var stamp: String = Time.get_datetime_string_from_system(false, true) \
			.replace(":", "-").replace(" ", "_")
	var path: String = "%s/battle_%s.log" % [LOG_DIR, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("BattleLogger: could not open %s (err %d)"
				% [path, FileAccess.get_open_error()])
		write_to_file = false
		return
	_abs_path = ProjectSettings.globalize_path(path)


func _write_header() -> void:
	_raw("=== BattleSim action log ===")
	if _abs_path != "":
		_raw("file: %s" % _abs_path)
	_raw("started: %s" % Time.get_datetime_string_from_system())
	if _bs == null:
		return
	_raw("HQ  team0=%s  team1=%s" % [str(_bs.PLAYER_HQ_POS), str(_bs.ENEMY_HQ_POS)])
	for raw in _bs.pilots:
		var p := raw as PilotData
		_raw("roster %-4s lane=%-8s guerrilla=%s hp=%d atk=%d hit=%d eva=%d move=%d @%s"
				% [_bs.pilot_label(p), _lane_name(p), str(p.is_guerrilla),
					p.max_hp, p.atk, p.hit, p.evasion, p.move_range,
					str(p.grid_pos)])
	_raw("----------------------------------------------------------------")


# `print` + file, with no turn/stage decoration. Used for headers only.
func _raw(text: String) -> void:
	if not enabled:
		return
	if echo_to_console:
		print("[BLOG] " + text)
	if _file != null:
		_file.store_line(text)


# ─── Public logging API ──────────────────────────────────────────────────────

## 현재 단계 태그를 바꾼다. 이후 모든 줄에 `[stage]` 로 붙는다.
func stage(name_tag: String) -> void:
	_stage = name_tag


## 한 줄 기록. `cat` 은 grep 하기 좋은 짧은 카테고리 (MOVE / DMG / PUSH …).
func log_event(cat: String, text: String) -> void:
	if not enabled:
		return
	var turn: int = _bs.turn_count if _bs != null else 0
	var line: String = "[T%04d][%-9s][%-6s] %s" % [turn, _stage, cat, text]
	if echo_to_console:
		print("[BLOG] " + line)
	if _file != null:
		_file.store_line(line)


## 좌표가 바뀐 모든 지점에서 호출한다. `stage_tag` 가 비면 현재 단계를 쓴다.
func log_move(p: PilotData, from_cell: Vector2i, to_cell: Vector2i,
		kind: String, note: String = "") -> void:
	if not enabled or p == null:
		return
	_turn_moves.append({
		"pilot": p, "from": from_cell, "to": to_cell,
		"kind": kind, "stage": _stage,
	})
	var suffix: String = ("  (%s)" % note) if note != "" else ""
	log_event("MOVE", "%-4s %s → %s  [%s] axis %d→%d%s" % [
			_bs.pilot_label(p), str(from_cell), str(to_cell), kind,
			_axis(from_cell), _axis(to_cell), suffix])


## 이동이 막혔을 때(적과 같은 칸 / 적 포탑 / 경로 없음) 그 사유를 남긴다.
func log_block(p: PilotData, reason: String) -> void:
	if not enabled or p == null:
		return
	log_event("BLOCK", "%-4s @%s halted — %s"
			% [_bs.pilot_label(p), str(p.grid_pos), reason])


# ─── Turn boundaries ─────────────────────────────────────────────────────────

func begin_turn() -> void:
	if not enabled or _bs == null:
		return
	_turn_start_pos.clear()
	_turn_moves.clear()
	_stage = "turn-open"
	_raw("")
	log_event("TURN", "──────── turn %d begin ────────" % _bs.turn_count)
	for raw in _bs.pilots:
		var p := raw as PilotData
		_turn_start_pos[p] = p.grid_pos
	log_event("SNAP", "before: " + _positions_line())


func end_turn() -> void:
	if not enabled or _bs == null:
		return
	_stage = "turn-close"
	log_event("SNAP", "after : " + _positions_line())
	_detect_crossings()
	log_event("TURN", "──────── turn %d end ──────────" % _bs.turn_count)
	if _file != null:
		_file.flush()


# ─── Cross-over detection ────────────────────────────────────────────────────
# Two same-scope enemies "crossed" when the sign of their lane-axis difference
# flipped over the turn *and* they did not end up sharing a cell. The axis is
# hex distance to team-0's HQ, so a smaller value means "further toward team 0".
#
# The axis alone is far too loose on its own — two pilots on opposite side lanes
# routinely trade axis ranks without ever being near each other. So a report also
# requires **proximity**: they must have been within NEAR_DIST at the start and
# still within it at the end. A strict positional exchange (A ends where B began
# and vice versa) is always reported regardless of distance.
const NEAR_DIST := 2
func _detect_crossings() -> void:
	var team0: Array = []
	var team1: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not _turn_start_pos.has(p):
			continue
		if p.team == 0: team0.append(p)
		else: team1.append(p)

	for raw_a in team0:
		var a := raw_a as PilotData
		for raw_b in team1:
			var b := raw_b as PilotData
			# Junglers and lane pilots never engage each other, so they are
			# *supposed* to pass through. Only same-scope pairs are a bug.
			if a.is_guerrilla != b.is_guerrilla:
				continue
			var a0: Vector2i = _turn_start_pos[a]
			var b0: Vector2i = _turn_start_pos[b]
			var a1: Vector2i = a.grid_pos
			var b1: Vector2i = b.grid_pos
			if a0 == a1 and b0 == b1:
				continue
			# Either pilot dead / respawned this turn → their teleport is not a
			# crossing; skip so the HQ snap doesn't spam false positives.
			if not a.alive or not b.alive:
				continue
			if a1 == b1:
				continue   # ended in the same cell = they met, not crossed
			var swapped: bool = (a0 == b1 and b0 == a1)
			if not swapped:
				# The lane axis only orders pilots that share a lane. Two enemies
				# on *different* lanes slide past each other one cell apart all
				# the time — most visibly at an HQ cell, where a recalled
				# defender walks out down its own lane while an attacker from
				# another lane steps onto the HQ. Same-cell-only combat has no
				# zone of control, so neither could have engaged the other: that
				# is the design, not a pass-through. Junglers both carry
				# LanePosition.GUERRILLA, so this also keeps jungler pairs in.
				if a.lane != b.lane:
					continue
				var hg := _bs.hex_grid as HexGrid
				if hg.hex_distance(a0, b0) > NEAR_DIST:
					continue
				if hg.hex_distance(a1, b1) > NEAR_DIST:
					continue
			var d0: int = _axis(a0) - _axis(b0)
			var d1: int = _axis(a1) - _axis(b1)
			if d0 == 0 or d1 == 0:
				continue
			if (d0 > 0) == (d1 > 0):
				continue
			cross_events += 1
			var kind: String = "SWAP" if swapped else "CROSS"
			log_event("!!" + kind, "%s %-4s %s→%s  vs  %-4s %s→%s"
					% [kind, _bs.pilot_label(a), str(a0), str(a1),
						_bs.pilot_label(b), str(b0), str(b1)])
			_dump_pair_moves(a, b)


# Replays this turn's recorded moves for the two pilots involved in a crossing,
# so the log shows exactly which stage moved whom in which order.
func _dump_pair_moves(a: PilotData, b: PilotData) -> void:
	var idx: int = 0
	for raw in _turn_moves:
		var m: Dictionary = raw as Dictionary
		var p := m["pilot"] as PilotData
		if p != a and p != b:
			continue
		log_event("  trace", "#%d %-9s %-4s %s → %s [%s]" % [
				idx, m["stage"], _bs.pilot_label(p),
				str(m["from"]), str(m["to"]), m["kind"]])
		idx += 1


# ─── Helpers ─────────────────────────────────────────────────────────────────

# Lane axis coordinate: hex distance from team-0's HQ. Monotonic along every
# lane path, so comparing two pilots' values tells you who is further up-lane.
func _axis(cell: Vector2i) -> int:
	if _bs == null or _bs.hex_grid == null:
		return 0
	return _bs.hex_grid.hex_distance(_bs.PLAYER_HQ_POS, cell)


func _lane_name(p: PilotData) -> String:
	if p.is_guerrilla:
		return "JUNGLE"
	if p.lane >= 0 and p.lane < _bs.LANE_NAMES.size():
		return str(_bs.LANE_NAMES[p.lane])
	return "?"


func _positions_line() -> String:
	var parts: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		var tag: String = "%s@%s" % [_bs.pilot_label(p), str(p.grid_pos)]
		if not p.alive:
			# 전장을 비우는 사유는 사망뿐. 남은 턴 수는 타이머를 직접 읽지 말고
			# 헬퍼를 거친다.
			tag += "(dead:%d)" % _bs.turns_until_return(p)
		else:
			tag += "(hp%d" % p.hp
			if p.shield > 0:
				tag += "+s%d" % p.shield
			if p.recall_hold:
				tag += ",복귀대기"
			tag += ")"
		parts.append(tag)
	return " ".join(parts)
