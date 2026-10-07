class_name UiPreview
extends RefCounted

# 아웃게임 UI 씬 **단독 실행(F6) 미리보기** 도우미.
#
# 씬을 에디터에서 열고 "현재 씬 실행"을 누르면 그 씬이 `current_scene` 이 된다 —
# 실제 게임 흐름에서는 화면 · 팝업 · 아이템 씬이 항상 다른 씬(Lobby · Season ·
# MatchFlow …)의 자식이라 이 조건이 참이 되지 않는다. 그래서 각 스크립트는 `_ready`
# 끝에 한 줄만 둔다:
#
#     if UiPreview.is_standalone(self):
#         _fill_preview()
#
# `_fill_preview()` 는 그 스크립트의 **보통 API**(fill / open / refresh …)로 더미
# 데이터를 넣는다. 데이터 출처:
#   - 화면 · 패널 — `ensure_run()` 이 실제 game.db 로 메모리에만 런을 세운다(저장 없음).
#   - 아이템 씬 — 손으로 적은 값.
# 미리보기는 **아무것도 저장하지 않는다**(런 파일 · 프로필). 다른 화면으로 가는 버튼은
# 호스트(`SeasonHub` 등)가 없어 아무 일도 하지 않거나 `trace` 로 출력만 한다.

const _PAD: float = 40.0


## 이 노드가 에디터 "현재 씬 실행"(F6)으로 뜬 씬의 루트인가. 릴리스 빌드에서는 항상 false.
static func is_standalone(node: Node) -> bool:
	if not OS.is_debug_build() or not node.is_inside_tree():
		return false
	var tree: SceneTree = node.get_tree()
	# `current_scene` 은 루트에 붙은 **뒤에** 정해진다 — `_ready` 시점엔 아직 null 일 수 있어
	# "루트 바로 아래 + 소유자 없음 + 오토로드 아님" 으로도 본다.
	if tree.current_scene != null:
		return tree.current_scene == node
	return node.get_parent() == tree.root and node.owner == null \
			and not ProjectSettings.has_setting("autoload/" + String(node.name))


## 메모리에만 런을 하나 세운다(이미 있으면 그대로) → GameManager. 실패하면 null.
## `GameManager.init_season()` = 에디터에서 Season.tscn 을 바로 실행할 때와 같은 길.
static func ensure_run() -> Node:
	var gm: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("UiPreview: GameManager autoload 없음")
		return null
	gm.use_test_run = true
	if not bool(gm.season_state.get("active", false)):
		var err: String = gm.init_season()
		if err != "":
			push_error("UiPreview: init_season 실패 — " + err)
			return null
	return gm


## `host` 아래에 미리보기 전용 `LeagueManager` 를 붙이고, 이번 페이즈 일정을 깐 뒤
## `weeks` 주를 (플레이어 경기 포함) 무작위로 치른다 — 순위표 · 다음 경기 글이 차게.
## 이미 붙어 있으면 그것을 돌려준다. `ensure_run()` 뒤에 부른다.
static func ensure_league(host: Node, weeks: int = 2) -> LeagueManager:
	var lm := host.get_node_or_null("PreviewLeague") as LeagueManager
	if lm != null:
		return lm
	lm = LeagueManager.new()
	lm.name = "PreviewLeague"
	host.add_child(lm)
	lm.ensure_phase_scheduled()
	var s: Dictionary = host.get_node("/root/GameManager").season_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _w in weeks:
		for m in lm.matches_this_week():
			if bool(m["played"]):
				continue
			var a: int = int(m["team_a"])
			var b: int = int(m["team_b"])
			var winner: int = a if rng.randf() < 0.5 else b
			m["played"] = true
			m["winner"] = winner
			lm.record_result(a, b, winner)
		s["phase_week"] = int(s["phase_week"]) + 1
	return lm


## `TournamentManager._bootstrap_playoff` 와 같은 모양의 4팀 플레이오프 대진표를 `s` 에 깔고
## 돌려준다 — 순위표 상위 넷(우리 팀이 없으면 4위 자리에 넣는다). 결과는 호출부가
## `TournamentManager.record_result` 로 적는다.
static func playoff_bracket(s: Dictionary, lm: LeagueManager) -> Array:
	var pid: int = int(s["player_team_id"])
	var top4: Array = []
	for row in lm.standings_ranked().slice(0, 4):
		top4.append(int(row["team_id"]))
	if not top4.has(pid):
		top4[3] = pid
	var pweek: int = int(s["phase_week"])
	var pairs: Array = [[top4[0], top4[3]], [top4[1], top4[2]], [-1, -1]]
	var b: Array = []
	for slot in 3:
		b.append({
			"slot": slot, "round": 1 if slot < 2 else 2,
			"phase_week": pweek if slot < 2 else pweek + 1,
			"team_a": int(pairs[slot][0]), "team_b": int(pairs[slot][1]),
			"year": int(s["year"]), "month": int(s["month"]), "day": int(s["day"]),
			"weekday": 0, "matchday": 0, "played": false, "winner": -1,
		})
	s["current_tournament"] = {
		"type": "PLAYOFF",
		"phase_at_start": int(s["current_phase"]),
		"stage": GameEnums.TournamentStage.PLAYOFF_SF,
		"bracket": b,
	}
	return b


## 바탕을 아웃게임 흰 종이로 칠하고, 화면보다 작은 아이템 씬(Control)은 화면 가운데로 옮긴다.
## 전체 화면(full rect) 씬 · CanvasLayer 는 위치를 건드리지 않는다.
static func stage(node: Node) -> void:
	RenderingServer.set_default_clear_color(OutgameTheme.BG)
	var c := node as Control
	if c == null:
		return
	var full_w: bool = is_equal_approx(c.anchor_right - c.anchor_left, 1.0)
	if full_w and is_equal_approx(c.anchor_bottom - c.anchor_top, 1.0):
		return
	if full_w:
		# 위끝 · 좌우로 펼친 루트(HubSheet 본문 VBox 등) — 가운데로 옮기면 오른쪽이 넘친다.
		# 좌우 여백만 준다.
		_inset.call_deferred(c)
		return
	_center.call_deferred(c)


static func _inset(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.offset_left = _PAD
	c.offset_right = -_PAD
	c.offset_top = maxf(c.offset_top, _PAD)


static func _center(c: Control) -> void:
	if not is_instance_valid(c):
		return
	var view: Vector2 = c.get_viewport_rect().size
	var sz: Vector2 = c.size
	# 폭이 0 인 컨테이너 루트(VBox 등)는 화면 폭에서 여백만 뺀 폭을 준다.
	if sz.x < 1.0:
		sz.x = view.x - _PAD * 2.0
		c.size = sz
	var pos: Vector2 = ((view - c.size) * 0.5).max(Vector2(_PAD, _PAD))
	# 화면 폭만 한 고정 크기 루트(로비 탭 등)는 왼쪽 끝에 붙인다.
	if c.size.x >= view.x - 1.0:
		pos.x = 0.0
	c.position = pos


## `btn` 에서 `owner_obj` 가 이은 누름 배선(저장 · 화면 이동 같은 행동)을 끊고 누름은 출력만
## 한다. 다른 배선(`HapticUi` 감촉)은 그대로 둔다.
static func mute(btn: BaseButton, owner_obj: Object, label: String) -> void:
	for c in btn.pressed.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_object() == owner_obj:
			btn.pressed.disconnect(cb)
	trace(btn.pressed, label)


## 시그널이 나가면 출력만 한다 — 미리보기에서 버튼이 "눌렸다"는 것만 확인하는 용도.
static func trace(sig: Signal, label: String = "") -> void:
	var tag: String = label if label != "" else String(sig.get_name())
	sig.connect(func(a = null, b = null, c = null, d = null) -> void:
		print("[UiPreview] %s %s" % [tag, str([a, b, c, d].filter(func(v): return v != null))]))
