class_name KillFeed
extends Control

# 킬로그 — 화면 **우측 상단**(적 파일럿 스트립 바로 아래)에 처치와 포탑 철거를
# 한 줄씩 쌓아 보여 준다. 전장은 매 0.5초 자동으로 흐르고 교전은 오버레이가
# 화면을 통째로 덮으므로, **무슨 일이 일어났는지가 지나가고 나면 남는 곳이
# 없었다** — 팀 점수가 조금 벌어진 것 말고는.
#
# 한 줄의 생김새(왼쪽 → 오른쪽):
#
#     [ 막타 파일럿 (가로로 긴 눈높이 컷) ][어시][어시][ 칼 ][ 피해자 ]
#
#   • **막타**  — `PORTRAIT_W`(96) 짜리 가로로 긴 eye 컷. 이 줄의 주인이다.
#   • **어시스트** — 높이는 같고 폭만 1/3(`ASSIST_W`). 피해를 넣었지만 마지막
#     한 대는 넣지 못한 사람들이고, `PilotData.damage_credit` 에서 피해가 큰
#     순으로 최대 `MAX_ASSISTS` 명까지 온다(성장치 어시스트 배분과 같은 표다).
#   • **아이콘** — 처치는 교차한 칼, 포탑 철거와 오브젝트 획득은 파열 표시.
#   • **피해자** — 파일럿이면 같은 크기의 eye 컷, 포탑이면 포탑 실루엣 + `T1 좌`,
#     오브젝트면 전령 / 용 글리프 + 그 이름.
#
# **오브젝트 획득도 한 줄이다**(`push_objective`). 전령과 용은 결판이 나도
# 화면에 남는 것이 `last_log` 한 줄뿐이라, 정작 경기의 큰 갈림길이 팀 점수가
# 조금 벌어진 것 말고는 아무 자국도 남기지 않았다. 대표 자리에는 **정글러**가
# 서고(오브젝트는 정글의 사건이다) 같이 나온 나머지 참가자가 어시스트로
# 붙는다 — 처치 줄과 같은 문법이라 따로 읽는 법을 배울 것이 없다.
#
# 줄은 **위에서 밀고 들어온다** — 새 줄이 y=0 에 앉고 먼저 있던 줄들이 한 칸씩
# 아래로 내려가며, `MAX_ROWS` 를 넘긴 가장 오래된 줄이 아래로 밀려 사라진다.
# 각 줄은 `HOLD_SEC` 동안 온전히 있다가 `FADE_SEC` 동안 지워진다.
#
# **교전(ENGAGE) 중에 난 처치는 그 자리에서 뜨지 않는다** — 아레나가 화면을
# 덮고 있어 어차피 보이지 않고, 끝나고 나서 한 줄씩 나오는 편이 "그 교전에서
# 무슨 일이 있었나"를 한 번에 읽게 한다. `push_*` 가
# `EngagePhaseManager.is_active()` 를 보고 `_pending` 에 쌓아 두었다가, 결과
# 대시보드를 닫는 순간 `flush_pending()` 이 `FLUSH_STAGGER` 간격으로 풀어놓는다.
#
# 애니메이션은 트윈이 아니라 `_process` 한 곳에서 돈다 — 한 줄이 뜨는 동안 다음
# 줄이 들어오고 그 사이에 또 하나가 사라지는 것이 정상 동작이라, 노드마다 트윈을
# 쥐어 주면 서로의 y 를 덮어쓴다.

# ─── 자리 (screen coords) ────────────────────────────────────────────────────
## 피드 오른쪽 끝. 화면 오른쪽 가장자리에서 22px 물러난다.
const FEED_RIGHT: float = 1058.0
## 피드 위쪽 끝 — 상단 패널(`HudBuilder.TOP_PANEL_H` 148) 밑단에서 8px 아래.
## 패널 높이가 바뀌면 이 값도 함께 옮긴다(패널이 168 이던 시절엔 176, 132 이던
## 시절엔 140 이었다).
const FEED_TOP: float   = 156.0
## 줄 하나의 높이 = 초상화 높이.
const ROW_H: float      = 40.0
## 줄 사이 간격을 포함한 세로 피치.
const ROW_STEP: float   = 46.0
## 동시에 보이는 줄 수 상한. 4줄이면 아래끝이 y 334 — 전장 픽셀 상단(369) 위에서
## 멈춘다. 상단 패널이 168 이던 시절에는 354 로 아슬아슬했다.
const MAX_ROWS: int     = 4

# ─── 한 줄 안의 칸 ───────────────────────────────────────────────────────────
## eye 컷(480×200)의 가로:세로 비. 초상화 폭은 여기서 유도한다.
const EYE_ASPECT: float = 2.4
const PORTRAIT_W: float = ROW_H * EYE_ASPECT   # 96
## 어시스트 칸 — 높이는 같고 폭만 1/3.
const ASSIST_W: float   = PORTRAIT_W / 3.0     # 32
const ICON_W: float     = 32.0
const SLOT_GAP: float   = 4.0
## 5인 팀이라 어시스트는 최대 4명이다 — 상한을 명시해 폭 계산의 상수로 쓴다.
const MAX_ASSISTS: int  = 4

# ─── 타이밍 ──────────────────────────────────────────────────────────────────
## 줄이 온전한 알파로 머무는 시간.
const HOLD_SEC: float   = 4.0
## 그 뒤 지워지는 데 걸리는 시간.
const FADE_SEC: float   = 0.5
## 들어오는 연출 — 오른쪽에서 밀려 들어오며 나타난다.
const INTRO_SEC: float  = 0.18
const INTRO_SLIDE_PX: float = 44.0
## y 미끄러짐의 수렴 속도(1/초). 값이 클수록 딱딱 붙는다.
const SLIDE_LAMBDA: float = 18.0
## 교전 뒤 밀린 줄을 풀어놓는 간격.
const FLUSH_STAGGER: float = 0.25

# ─── 색 ──────────────────────────────────────────────────────────────────────
const ROW_BG        := Color(0.05, 0.05, 0.08, 0.72)
const TEAM_RIM      := [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
const SLOT_BG       := Color(0.12, 0.13, 0.19)
const ICON_DARK     := Color(0.0, 0.0, 0.0, 0.85)
const KILL_ICON     := Color(0.96, 0.96, 1.0)
const TURRET_ICON   := Color(1.0, 0.72, 0.30)
const TURRET_LABEL  := Color(0.88, 0.88, 0.92)
## 포탑 줄의 레인 표기. `LANE_NAMES` 는 "Left/Center/Right" 라 좁은 칸에 넣기엔
## 길다 — 한 글자로 줄인다.
const LANE_SHORT: Array = ["좌", "중", "우", "정"]

var _bs: BattleSim = null
var _rows: Array = []      # Array[Row] — index 0 이 가장 새 줄(맨 위)
## 상한을 넘겨 밀려난 줄. **`_rows` 와 따로 든다** — 자리 계산(`_reflow`)에서는
## 빠져야 하지만 페이드는 계속 돌아야 하고, 한쪽에만 있으면 둘 중 하나가 깨진다
## (실측: `_rows` 에서 빼기만 했더니 밀려난 줄이 그 자리에 영원히 굳었다).
var _fading: Array = []    # Array[Row]
var _pending: Array = []   # Array[Dictionary] — 교전 중에 밀린 줄
var _flush_left: float = -1.0


func setup(bs: BattleSim) -> void:
	_bs = bs
	position = Vector2(FEED_RIGHT - feed_width(), FEED_TOP)
	size = Vector2(feed_width(), float(MAX_ROWS) * ROW_STEP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


## 가장 넓은 줄(어시스트 상한을 채운 처치)의 폭. 모든 줄은 이 폭 안에서
## **오른쪽 정렬**되므로 피해자 칸은 어시스트가 몇이든 언제나 같은 자리에 온다.
static func feed_width() -> float:
	return PORTRAIT_W + float(MAX_ASSISTS) * (ASSIST_W + SLOT_GAP) \
			+ SLOT_GAP + ICON_W + SLOT_GAP + PORTRAIT_W


# ─── 적립 ────────────────────────────────────────────────────────────────────
## 파일럿 처치 한 건. `assists` 는 막타를 뺀 가담자(피해 큰 순).
func push_kill(killer: PilotData, victim: PilotData, assists: Array) -> void:
	if victim == null:
		return
	_submit({"turret": null, "killer": killer, "victim": victim,
			"assists": assists.slice(0, MAX_ASSISTS)})


## 포탑 철거 한 건. 어시스트 개념이 없다 — 마지막 한 대를 넣은 파일럿뿐이다
## (`SimulationCore._last_turret_hitter`).
func push_turret(destroyer: PilotData, turret: TurretData) -> void:
	if turret == null:
		return
	_submit({"turret": turret, "killer": destroyer, "victim": null,
			"assists": []})


## 오브젝트(전령 / 용) 획득 한 건. `main` 은 대표(정글러 우선, 없으면 참가자
## 중 첫 사람), `assists` 는 같이 나온 나머지 참가자들. `team` 은 가져간 팀 —
## 오브젝트 칸의 테두리 색이 그 팀색이 된다.
##
## 명단은 **참여를 고른 시점의 참가자**다. 그 뒤 교전에서 쓰러진 사람도 그대로
## 남는다 — 오브젝트를 가져오는 데 쓴 몸이 곧 기여다.
func push_objective(kind: int, main: PilotData, assists: Array,
		team: int) -> void:
	_submit({"turret": null, "victim": null, "objective": kind, "team": team,
			"killer": main, "assists": assists.slice(0, MAX_ASSISTS)})


func _submit(rec: Dictionary) -> void:
	# 교전이 도는 동안은 아레나가 화면을 덮고 있다 — 지금 띄워 봐야 아무도
	# 못 본다. 끝나고 `flush_pending()` 이 한 줄씩 풀어놓는다.
	if _bs != null and _bs.engage_phase != null and _bs.engage_phase.is_active():
		_pending.append(rec)
		return
	_spawn_row(rec)


## 교전이 닫히는 순간 `EngagePhaseManager._on_dashboard_confirmed` 가 부른다.
## 첫 줄은 즉시, 나머지는 `FLUSH_STAGGER` 간격으로 이어 나온다.
func flush_pending() -> void:
	if _pending.is_empty():
		return
	_spawn_row(_pending.pop_front() as Dictionary)
	_flush_left = FLUSH_STAGGER if not _pending.is_empty() else -1.0


# ─── 줄 생성 / 구동 ──────────────────────────────────────────────────────────
func _spawn_row(rec: Dictionary) -> void:
	var row := Row.new()
	add_child(row)
	row.build(rec)
	# 새 줄이 맨 위(y 0)에 앉고, 먼저 있던 줄들이 한 칸씩 내려간다.
	row.y_now = -ROW_STEP * 0.35
	_rows.insert(0, row)
	_reflow()
	while _rows.size() > MAX_ROWS:
		var old := _rows.pop_back() as Row
		# 상한을 넘겨 밀려난 줄은 그 자리에서 지우지 않고 **아래로 밀어내며**
		# 페이드시킨다 — 툭 사라지면 방금 무엇이 있었는지가 지워진다.
		old.age = maxf(old.age, HOLD_SEC)
		old.y_target = float(MAX_ROWS) * ROW_STEP
		_fading.append(old)


func _reflow() -> void:
	for i in _rows.size():
		(_rows[i] as Row).y_target = float(i) * ROW_STEP


func _process(delta: float) -> void:
	if _flush_left >= 0.0:
		_flush_left -= delta
		if _flush_left <= 0.0:
			if _pending.is_empty():
				_flush_left = -1.0
			else:
				_spawn_row(_pending.pop_front() as Dictionary)
				_flush_left = FLUSH_STAGGER if not _pending.is_empty() else -1.0
	# 밀려난 줄도 같이 굴린다 — 자리만 `_rows` 밖일 뿐 페이드는 진행 중이다.
	_reap(_fading, delta)
	if _reap(_rows, delta):
		_reflow()


## `list` 의 줄들을 한 프레임 굴리고 수명이 다한 것을 걷어 낸다.
## 하나라도 걷어 냈으면 true(= 자리를 다시 잡아야 한다).
func _reap(list: Array, delta: float) -> bool:
	var dead: Array = []
	for raw in list:
		var row := raw as Row
		if not row.advance(delta):
			dead.append(row)
	if dead.is_empty():
		return false
	for raw in dead:
		var row := raw as Row
		list.erase(row)
		row.queue_free()
	return true


# ─── 한 줄 ───────────────────────────────────────────────────────────────────
# 초상화는 자식 `TextureRect`(eye 컷은 노드 경로라 prime 이 필요 없다), 아이콘과
# 포탑 실루엣은 자식 `Glyph` 다. **줄 자신의 `_draw` 에 그리면 안 된다** —
# Control 의 `_draw` 는 자식보다 **먼저** 나가므로 줄 배경(반투명)과 포탑 칸
# 슬래브(불투명) 밑에 깔린다. 실측: 칼은 흐려지고 포탑 실루엣은 아예 안 보였다.
class Row extends Control:
	var age: float = 0.0
	var intro_t: float = 0.0
	var y_now: float = 0.0
	var y_target: float = 0.0

	func build(rec: Dictionary) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var assists: Array = rec["assists"] as Array
		var turret := rec["turret"] as TurretData
		var killer := rec["killer"] as PilotData
		var is_turret: bool = turret != null
		# -1 = 오브젝트 줄이 아니다. 그 밖에는 `ObjectiveSystem.Kind`.
		var objective: int = int(rec.get("objective", -1))
		var is_obj: bool = objective >= 0

		var w: float = KillFeed.PORTRAIT_W \
				+ float(assists.size()) * (KillFeed.ASSIST_W + KillFeed.SLOT_GAP) \
				+ KillFeed.SLOT_GAP + KillFeed.ICON_W + KillFeed.SLOT_GAP \
				+ KillFeed.PORTRAIT_W
		size = Vector2(w, KillFeed.ROW_H)
		# 오른쪽 정렬 — 피해자 칸이 어시스트 수와 무관하게 같은 x 에 온다.
		position = Vector2(KillFeed.feed_width() - w, 0.0)

		var bg := ColorRect.new()
		bg.position = Vector2.ZERO
		bg.size = size
		bg.color = KillFeed.ROW_BG
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

		# 막타를 넣은 쪽의 팀색. 막타 파일럿이 없으면(로그가 놓친 경우) 피해자의
		# 반대 팀으로 친다 — 전장에는 제3세력이 없다.
		var killer_team: int = 0
		if killer != null:
			killer_team = killer.team
		elif is_obj:
			killer_team = int(rec["team"])
		elif is_turret:
			killer_team = 1 - turret.team
		else:
			killer_team = 1 - (rec["victim"] as PilotData).team

		var x: float = 0.0
		_add_portrait(x, KillFeed.PORTRAIT_W, killer, killer_team)
		x += KillFeed.PORTRAIT_W + KillFeed.SLOT_GAP
		for raw in assists:
			var a := raw as PilotData
			_add_portrait(x, KillFeed.ASSIST_W, a, a.team)
			x += KillFeed.ASSIST_W + KillFeed.SLOT_GAP

		var icon_kind: int = Glyph.Kind.SWORDS
		var icon_col: Color = KillFeed.KILL_ICON
		if is_turret:
			icon_kind = Glyph.Kind.BURST
			icon_col = KillFeed.TURRET_ICON
		elif is_obj:
			icon_kind = Glyph.Kind.BURST
			icon_col = ObjectiveTimer.kind_color(objective)
		_add_glyph(Vector2(x, 0.0), Vector2(KillFeed.ICON_W, KillFeed.ROW_H),
				icon_kind, icon_col)
		x += KillFeed.ICON_W + KillFeed.SLOT_GAP

		if is_obj:
			_add_objective_slot(x, objective, killer_team)
		elif is_turret:
			var slot := Rect2(x, 0.0, KillFeed.PORTRAIT_W, KillFeed.ROW_H)
			var slab := ColorRect.new()
			slab.position = slot.position
			slab.size = slot.size
			slab.color = KillFeed.SLOT_BG
			slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(slab)
			_add_glyph(Vector2(x + 2.0, 0.0), Vector2(38.0, KillFeed.ROW_H),
					Glyph.Kind.TURRET, KillFeed.TEAM_RIM[clampi(turret.team, 0, 1)])
			_add_rim(slot.position, slot.size, turret.team)
			var lane_tag: String = "?"
			if turret.lane >= 0 and turret.lane < KillFeed.LANE_SHORT.size():
				lane_tag = String(KillFeed.LANE_SHORT[turret.lane])
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 17)
			lbl.add_theme_color_override("font_color", KillFeed.TURRET_LABEL)
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			lbl.add_theme_constant_override("outline_size", 4)
			lbl.text = "T%d %s" % [turret.tier, lane_tag]
			lbl.clip_text = true
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.position = Vector2(x + 36.0, 0.0)
			lbl.size = Vector2(KillFeed.PORTRAIT_W - 44.0, KillFeed.ROW_H)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(lbl)
		else:
			var victim := rec["victim"] as PilotData
			_add_portrait(x, KillFeed.PORTRAIT_W, victim, victim.team)

		modulate = Color(1, 1, 1, 0)

	## 줄 오른쪽 끝의 오브젝트 칸 — 포탑 칸과 같은 문법(슬래브 + 글리프 +
	## 이름)이다. 글리프는 상단 패널의 등장 시계와 **같은 static 함수**가
	## 그리므로 두 자리의 용이 다른 그림이 될 수 없다.
	func _add_objective_slot(x: float, kind: int, team: int) -> void:
		var slot := Rect2(x, 0.0, KillFeed.PORTRAIT_W, KillFeed.ROW_H)
		var slab := ColorRect.new()
		slab.position = slot.position
		slab.size = slot.size
		slab.color = KillFeed.SLOT_BG
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slab)
		var g := ObjGlyph.new()
		g.position = Vector2(x + 3.0, 0.0)
		g.size = Vector2(KillFeed.ROW_H, KillFeed.ROW_H)
		g.kind = kind
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)
		_add_rim(slot.position, slot.size, team)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", KillFeed.TURRET_LABEL)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.text = ObjectiveSystem.kind_name(kind)
		lbl.clip_text = true
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(x + 40.0, 0.0)
		lbl.size = Vector2(KillFeed.PORTRAIT_W - 48.0, KillFeed.ROW_H)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)


	func _add_portrait(x: float, w: float, p: PilotData, team: int) -> void:
		var at := Vector2(x, 0.0)
		var of_size := Vector2(w, KillFeed.ROW_H)
		# 뒤판 — 이미지가 없는 파일럿(단독 실행 / INTL id ≥ 100)의 폴백.
		var bg := ColorRect.new()
		bg.position = at
		bg.size = of_size
		bg.color = KillFeed.SLOT_BG
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		if p != null:
			var eye := TextureRect.new()
			eye.position = at
			eye.size = of_size
			eye.texture = PilotImages.eye_for(p.pilot_id)
			eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(eye)
		_add_rim(at, of_size, team)

	func _add_rim(at: Vector2, of_size: Vector2, team: int) -> void:
		var rim := Panel.new()
		rim.position = at
		rim.size = of_size
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = KillFeed.TEAM_RIM[clampi(team, 0, 1)]
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.border_width_left = 2
		sb.border_width_right = 2
		rim.add_theme_stylebox_override("panel", sb)
		add_child(rim)

	## 한 프레임 진행. 아직 살아 있으면 true.
	func advance(delta: float) -> bool:
		age += delta
		intro_t = minf(intro_t + delta, KillFeed.INTRO_SEC)
		var intro: float = intro_t / KillFeed.INTRO_SEC
		# smoothstep — 들어오는 순간이 가장 빠르고 자리에서 멎는다.
		var eased: float = intro * intro * (3.0 - 2.0 * intro)
		y_now = lerpf(y_now, y_target, 1.0 - exp(-KillFeed.SLIDE_LAMBDA * delta))
		var alpha: float = eased
		if age > KillFeed.HOLD_SEC:
			alpha = minf(alpha,
					1.0 - (age - KillFeed.HOLD_SEC) / KillFeed.FADE_SEC)
		if alpha <= 0.0:
			return false
		position = Vector2(KillFeed.feed_width() - size.x
				+ (1.0 - eased) * KillFeed.INTRO_SLIDE_PX, y_now)
		modulate = Color(1, 1, 1, alpha)
		return true

	func _add_glyph(at: Vector2, of_size: Vector2, kind: int, col: Color) -> void:
		var g := Glyph.new()
		g.position = at
		g.size = of_size
		g.kind = kind
		g.col = col
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)


# ─── 오브젝트 글리프 한 개 ───────────────────────────────────────────────────
# 전령 / 용 그림은 `ObjectiveTimer` 가 static 으로 들고 있다 — 여기서는 자기
# rect 에 맞춰 한 번 부를 뿐이다. `Glyph` 와 따로 두는 이유는 그리는 방식이
# 아니라 **좌표계**가 달라서다(저쪽은 64×64 정규 좌표, 이쪽은 rect 중심).
class ObjGlyph extends Control:
	var kind: int = 0

	func _draw() -> void:
		var s: float = minf(size.x, size.y) - 4.0
		ObjectiveTimer.draw_kind_glyph(self, kind,
				Vector2((size.x - s) * 0.5, (size.y - s) * 0.5), s,
				ObjectiveTimer.kind_color(kind))


# ─── 아이콘 한 개 ────────────────────────────────────────────────────────────
# 자기 rect 안에 도형 하나를 그리는 것이 전부인 노드. 줄의 자식이라 배경 위에
# 얹히고, 부모의 `modulate` 를 그대로 타므로 페이드도 같이 걸린다.
class Glyph extends Control:
	enum Kind { SWORDS, BURST, TURRET }

	var kind: int = Kind.SWORDS
	var col: Color = Color.WHITE

	func _draw() -> void:
		match kind:
			Kind.SWORDS: _draw_swords(size * 0.5)
			Kind.BURST:  _draw_burst(size * 0.5)
			Kind.TURRET: _draw_turret()

	# 교차한 칼. 어두운 획을 먼저 깔고 그 위에 밝은 획을 얹어, 밝은 초상화
	# 옆에서도 형태가 남게 한다.
	func _draw_swords(c: Vector2) -> void:
		var r: float = 11.0
		var a0: Vector2 = c + Vector2(-r, r)
		var a1: Vector2 = c + Vector2(r, -r)
		var b0: Vector2 = c + Vector2(-r, -r)
		var b1: Vector2 = c + Vector2(r, r)
		draw_line(a0, a1, KillFeed.ICON_DARK, 8.0, true)
		draw_line(b0, b1, KillFeed.ICON_DARK, 8.0, true)
		draw_line(a0, a1, col, 3.5, true)
		draw_line(b0, b1, col, 3.5, true)
		# 손잡이 — 아래쪽 두 끝에 짧은 획을 얹어 X 가 아니라 칼로 읽히게 한다.
		draw_line(a0 + Vector2(-3.0, -3.0), a0 + Vector2(3.0, 3.0), col, 3.0, true)
		draw_line(b1 + Vector2(3.0, -3.0), b1 + Vector2(-3.0, 3.0), col, 3.0, true)

	func _draw_burst(c: Vector2) -> void:
		for i in 8:
			var ang: float = TAU * float(i) / 8.0
			var dir := Vector2(cos(ang), sin(ang))
			var inner: float = 5.0
			var outer: float = 13.0 if i % 2 == 0 else 9.0
			draw_line(c + dir * inner, c + dir * outer,
					KillFeed.ICON_DARK, 7.0, true)
			draw_line(c + dir * inner, c + dir * outer, col, 3.0, true)
		draw_circle(c, 4.0, col)

	# 포탑 실루엣 — 자기 rect 안에 세운다(옆은 `T1 좌` 라벨 자리).
	func _draw_turret() -> void:
		var cx: float = size.x * 0.5
		var base_y: float = size.y - 7.0
		var top_y: float  = 7.0
		# 몸통 — 아래가 넓고 위가 좁은 사다리꼴.
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 9.0, base_y), Vector2(cx + 9.0, base_y),
			Vector2(cx + 6.0, top_y + 8.0), Vector2(cx - 6.0, top_y + 8.0),
		]), col)
		# 총안 — 위에 얹힌 넓은 관.
		draw_rect(Rect2(cx - 10.0, top_y + 2.0, 20.0, 6.0), col)
		draw_rect(Rect2(cx - 2.5, top_y - 4.0, 5.0, 7.0), col)
