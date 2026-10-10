class_name BattleRenderer
extends Node2D

@onready var _bs: BattleSim = get_parent() as BattleSim

# 대상 지정 카드를 끌고 있을 때, **찍을 수 있는 파일럿**의 마커가 도달하는 배율.
# 예전에는 1.06~1.14 사이를 오가는 펄스(EMPHASIS_PULSE_HZ)였는데, 드래그해서
# 얼굴 위에 놓는 조작에서는 크기가 계속 변하는 대상이 오히려 겨누기 어려웠다 —
# 지금은 **고정 목표값**이고, 거기에 닿기까지 `EMPHASIS_TWEEN_SEC` 동안 부드럽게
# 자란다(도달 후에는 미동도 없다). 나머지는 전부 딤드되므로 커진 얼굴만 남는다.
# 2.0 에서 **1.5** 로 낮췄다: 2배는 한 칸에 두세 명이 선 무리를 화면 밖까지
# 밀어낼 만큼 벌려 놓았고, 얼굴 하나가 옆 레인까지 침범해 어느 타일 이야기인지가
# 흐려졌다.
#
# **이 배율은 초상만이 아니라 배치도 탄다.** 한 칸에 두세 명이 서 있으면 커진
# 얼굴들이 서로를 덮어 어느 쪽을 눌렀는지 알 수 없게 되므로,
# `_build_pilot_render_layout` 이 **강조된 파일럿(과 그 바깥 링)의** 슬롯 벡터를
# 같은 배율로 벌린다 — 대상이 아닌 파일럿은 제자리다(`_pilot_spread`).
# (그리고 `_draw_arrow_to_tile` 이 그만큼 긴 화살표를 그린다).
const TARGET_EMPHASIS_SCALE: float = 1.5

## 강조가 켜지고 꺼지는 데 걸리는 시간(s). 1.0 ↔ TARGET_EMPHASIS_SCALE 전 구간을
## 이 시간에 선형으로 지난다.
##
## **왜 애니메이션인가.** 예전에는 배율이 즉시 튀었다 — 카드를 집는 순간 전장의
## 얼굴 서넛이 한 프레임 만에 1.5배로 부풀고 무리가 좌우로 벌어졌으므로, 무엇이
## 대상인지보다 화면이 흔들렸다는 인상이 먼저 왔다. 배치(육각 링의 반지름)
## 와 히트 반경(`pilot_marker_radius`)이 전부 이 한 값에서 나오므로, 여기를
## 보간하면 초상 · 간격 · 화살표 길이 · 클릭 반경이 **함께** 자란다.
##
## 0.15 → **0.05** 로 줄였다. 0.15초는 "즉시 튄다"는 인상은 지웠지만, 카드를 든
## 손이 이미 대상 위로 가 있는데 얼굴이 아직 자라는 중인 구간이 남았다 — 강조는
## 겨누기 **전에** 끝나 있어야 하는 신호다.
const EMPHASIS_TWEEN_SEC: float = 0.05

## PilotData → 지금 프레임의 강조 배율(1.0 ~ TARGET_EMPHASIS_SCALE). `_process`
## 가 매 프레임 목표값 쪽으로 밀고, 그리기 · 배치 · 히트 테스트가 전부 이 값을
## 읽는다. 살아 있는 파일럿만 담기므로 재시작으로 로스터가 바뀌어도 남지 않는다.
var _emphasis_now: Dictionary = {}

## 강조로 벌어진 무리를 화면 안에 넣을 때 가장자리에서 남기는 여백.
const SCREEN_EDGE_PAD: float = 6.0


# ─── 마커 글라이드 (초상화는 절대 순간이동하지 않는다) ───────────────────────
# **화면 위의 마커 좌표 하나가 통째로 보간된다.** 예전에는 칸 이동만 트윈하고
# (`PilotData.anim_move_t/dur`, 셀 중심끼리의 lerp) 슬롯 변화는 즉시 반영했는데,
# 슬롯 하나가 91px 이고 반대편으로 옮겨 앉으면 182px 라 **칸 사이 거리(140px)보다
# 큰 순간이동**이 매 턴 섞여 들어왔다. 옆 사람이 와서 비켜 앉는 파일럿은 아예
# 트윈이 걸리지 않아 그냥 튀었다.
#
# 지금은 마커 좌표를 **중심 + 슬롯 벡터**로 갈라 놓고 둘을 따로 민다:
#
#   center — 지나간 칸의 중심을 이은 **폴리라인**을 따라 간다. 그래서 2칸 이동
#            (정글러 move_range 2, 전진 카드 advance:N)이 중간 칸을 스쳐 지나가지
#             않고 실제로 밟은 대로 꺾인다. 경로는 `PilotData.anim_move_path`.
#   vec    — 타일 중심에서 슬롯까지의 변위. **각도는 중심 이동과 같은 박자로**
#            돌고(= 화살표 방향이 칸 이동과 동시에 바뀐다), **길이는 도착한 뒤에**
#            따라온다 — 붐비는 칸에 들어가느라 바깥 링으로 밀려날 때 이동 중에
#            화살표까지 늘어나면 무엇이 움직였는지가 흐려진다.
#
# 말풍선 꼬리는 이제 **언제나 `center` 를 가리킨다**. 초상이 실제로 미끄러지므로
# 꼬리도 같이 미끄러지면 되고, 예전의 관성 장치(`_arrow_hold` / `_arrow_settle_t` /
# `_arrow_vec_now` / `_lerp_polar`)는 통째로 삭제됐다 — 그것은 "초상은 출발 칸에
# 있는데 꼬리만 도착 칸을 가리킨다"를 가리려고 있던 것이다.

## 링(반지름)이 바뀔 때, 이동이 끝난 **뒤에** 길이가 따라오는 데 걸리는 시간(s).
## `BattleSim.ANIM_MOVE_DUR`(0.30) 과 합쳐도 턴 간격(0.5초)을 넘지 않아야 한다.
const MARKER_RADIUS_SETTLE_SEC: float = 0.15

## PilotData → 글라이드 상태. 스키마는 `_settled_glide` 참조.
var _glide: Dictionary = {}
## `_solve_slots` 의 마지막 답과 그 답을 낸 입력(`_slot_input_key`).
var _slot_key: Array = []
var _slot_solution: Dictionary = {}


# ─── 마커 위 플로팅 숫자 ─────────────────────────────────────────────────────
# 두 종류가 같은 배열을 쓴다 — 공격 카드의 **피해 수치**(붉은 `-N`, 0.30초)와
# 성장치가 크게 오른 순간의 **성장치 팝업**(소울 아이콘 + 흰 글자·굵은 검은 외곽선 `+1500`, 1.10초 — `fmt_score_gain`, k 로 접지 않는다). 각 항목은
#   {"pos": Vector2, "text": String, "color": Color, "t": float,
#    "delay": float, "dur": float, "rise": float, "icon": Texture2D|null}
# `icon` 이 있는 항목(성장치 팝업)은 글자 왼쪽에 아이콘을 붙이고 굵은 외곽선으로 그린다.
# 이고 `pos` 는 **띄운 순간의 마커 좌표를 그대로 고정**한다 — 대상이 그 사이
# 쓰러지거나 밀려나도 숫자가 따라다니지 않게 하기 위함.
#
# 수명과 높이가 **항목마다** 다른 이유: 피해 숫자는 연속 타격(0.32초 간격)
# 사이에 사라져야 같은 자리에 겹쳐 쌓이지 않고, 성장치는 반대로 한 박자
# 머물러 있어야 읽힌다. 둘이 한 얼굴 위에 동시에 떠도 성장치가 더 높이
# 뜨므로 서로를 덮지 않는다.
var _popups: Array = []

const POPUP_MISS_COLOR   := Color(0.78, 0.80, 0.86)
const POPUP_DAMAGE_COLOR := Color(1.00, 0.42, 0.36)
const POPUP_SHIELD_COLOR := Color(0.45, 0.85, 1.00)
const POPUP_FONT_SIZE_BASE := 26
## 성장치 팝업의 검은 외곽선 두께(px, DISPLAY_SCALE 이 곱해진다) — 피해 숫자의
## 4방향 2px 외곽선보다 굵다.
const SCORE_POPUP_OUTLINE_PX := 7.0
## 아이콘과 숫자 사이 간격(px, DISPLAY_SCALE 이 곱해진다).
const SCORE_POPUP_ICON_GAP := 4.0
## 아이콘 외곽선 두께(px, DISPLAY_SCALE 이 곱해진다). 글자 외곽선(지름 기준)의
## 절반쯤이 테두리 바깥으로 나오므로 그와 비슷한 굵기로 보이는 값.
const SCORE_POPUP_ICON_OUTLINE_PX := 3.0
## 성장치 팝업 크기 — **얻은 양이 클수록 크게.** 표시값(`fmt_score_gain`, 성장치
## × 1000) 기준으로 두 자리(< `SCORE_POPUP_SIZE_LO_AMOUNT`)면 최소 배율,
## `SCORE_POPUP_SIZE_HI_AMOUNT` 이상이면 최대 배율, 그 사이는 **로그 보간**이다
## — 83 과 980 이 한 자리 수만큼 다른 사건이라는 것이 크기에서 읽혀야 한다.
## 배율은 글자 · 아이콘 · 외곽선 · 간격에 함께 먹는다.
const SCORE_POPUP_SIZE_MIN := 0.75
const SCORE_POPUP_SIZE_MAX := 1.25
const SCORE_POPUP_SIZE_LO_AMOUNT := 100.0
const SCORE_POPUP_SIZE_HI_AMOUNT := 1000.0


# ─── 공격 카드 명중 파티클 ───────────────────────────────────────────────────
# 피격자 초상에서 사방으로 퍼지는 짧은 조각들. 팝업과 같은 구조다 —
# **좌표를 띄운 순간에 고정**하고(대상이 쓰러져 시신이 되든 다음 턴에 밀려나든
# 파티클이 따라다니지 않는다) 스스로 시간을 밀다 만료되면 사라진다.
#
# `_process` 가 팝업과 함께 굴리고 `_draw()` 맨 끝에서 팝업 **바로 앞에** 그린다:
# 조각이 숫자를 덮으면 방금 몇 대미지였는지가 안 읽힌다.
#
# 조각 수를 프레임마다 새로 뽑지 않고 **띄울 때 각도·거리·크기를 굳혀 배열에
# 담는다** — 매 프레임 `randf()` 를 다시 굴리면 퍼져 나가는 조각이 아니라
# 매 프레임 다른 자리에서 깜빡이는 점들이 된다.
var _bursts: Array = []

## 한 번의 명중이 뿌리는 조각 수.
const BURST_COUNT: int = 12
## 조각이 날아가는 시간(s). `BattleSim.ANIM_HIT_HOLD_SEC`(0.20) 안에 끝나야
## 연속 공격의 다음 타격이 앞 타격의 파편 위에 겹치지 않는다.
const BURST_DUR: float = 0.18
## 조각이 마커 반지름의 몇 배까지 날아가는가 — 안쪽 / 바깥쪽 경계.
const BURST_REACH_MIN: float = 0.9
const BURST_REACH_MAX: float = 1.9
## 조각 반지름(px, DISPLAY_SCALE 이 곱해진다).
const BURST_DOT_R: float = 4.6
const BURST_COLOR := Color(1.00, 0.86, 0.62)

# ─── 공격 카드 시전 빛 ───────────────────────────────────────────────────────
# 시전자 초상 위로 솟아오르는 하얀 빛. 파티클과 달리 **상태를 들고 있지 않다** —
# `PilotData.anim_cast_*` 를 `BattleSim.pilot_cast_progress` 로 물어 그 프레임의
# 모양을 만들 뿐이라, 시전자가 미끄러지면 빛도 함께 따라간다(시전 중에 움직일
# 일은 없지만, 좌표를 굳혀 두면 그때만 어긋난다).
## 빛기둥 하나의 폭(마커 지름 대비).
const CAST_BEAM_W_RATIO: float = 0.62
## 솟는 빛의 색. 알파는 진행도에 따라 깎인다.
const CAST_COLOR := Color(1.0, 1.0, 1.0)


# ─── HP 링 조각 (피해를 입은 만큼 제자리에서 커지며 사라진다) ───────────────
# 링은 `pilot.hp` / `.shield` 를 그대로 읽으므로 피해가 들어온 프레임에 그냥
# 짧아진다 — 얼마나 깎였는지가 한 프레임에 지나가 버린다. 그래서 **방금 잃은
# 구간**(HP · 보호막 각각)을 그 자리에서 키우며 투명하게 지운다(`draw_hp_chip`).
#
# 감지는 호출부가 아니라 여기서 한다(`_hp_seen` 과 지금 hp 를 비교) — 피해 경로가
# 전장 교전 · 공격 카드 · 포탑 · 교전 아레나 · 스킬로 흩어져 있어 한 곳에 걸면
# 나머지가 빠진다. 교전이 도는 동안은 감지를 미룬다: 아레나가 전장을 덮고 있어
# 아무도 못 보므로, 무대가 걷힌 뒤 깎인 총량이 한 조각으로 떨어진다(성장치
# 팝업의 `_score_popup_hold` 와 같은 이유).
## PilotData → 마지막으로 본 Vector2i(hp, shield).
var _hp_seen: Dictionary = {}
## {"p": PilotData, "segs": Array, "t": float} — segs 는 `hp_loss_segments` 의 결과.
var _hp_chips: Array = []
const HP_CHIP_DUR: float = 0.45
## 끝날 때 조각의 두께 · 호 길이 배율(조각 가운데 기준).
const HP_CHIP_SCALE: float = 1.45
## 끝날 때 조각이 바깥으로 밀려난 거리 — 초상 반지름 배율(교전 무대 초상처럼
## 큰 초상에서도 같은 비율로 날아간다).
const HP_CHIP_FLY: float = 0.45


# ─── 초상 누르기 (커지고 맨 위로) ───────────────────────────────────────────
# 전장 초상은 이웃 칸 마커와 겹치기도 한다. 누른 초상은 **누르는 동안
# `PRESS_SCALE` 로 커지고**, 떼면 크기만 돌아온다 — **맨 위 순서는 다른 초상을
# 누를 때까지 유지된다**(`_top_pilot`). 입력은 `ui/MarkerTouch.gd` 가 받는다.
#
# 이 배율은 **그리기만** 탄다(`_pilot_draw_scale`). 대상 지정 강조와 달리 배치
# (`_pilot_spread`)에는 들어가지 않는다 — 누를 때마다 이웃이 비켜 앉으면 방금
# 보려던 무리가 흔들린다.
const PRESS_SCALE: float = 1.3
const PRESS_TWEEN_SEC: float = 0.08
var _press_pilot: PilotData = null
var _top_pilot: PilotData = null
# 대상 지정 드래그 중 가리킨 파일럿(`CardTargetingOverlay.picked_pilot`) — 프레임마다
# `_draw()` 앞머리에서 갱신된다. 칸 순회에서 빠졌다가 딤 위에서 맨 마지막에 그려진다.
var _pick_top: PilotData = null
var _press_now: Dictionary = {}


func _process(delta: float) -> void:
	# 상시 갱신이 필요한 것은 셋이다 — 피해 수치 팝업, 켜지거나 꺼지는 중인 대상
	# 강조, 그리고 미끄러지는 중인 마커. 전부 멈춰 있으면 재draw 하지 않는다
	# (대상 지정 상태가 **바뀌는** 순간은 CardTargetingOverlay._request_redraw()
	#  가 따로 걷어찬다).
	var dirty: bool = _advance_popups(delta)
	if _advance_bursts(delta):
		dirty = true
	if _advance_emphasis(delta):
		dirty = true
	if _advance_press(delta):
		dirty = true
	if _advance_hp_chips(delta):
		dirty = true
	if _advance_banners(delta):
		dirty = true
	# 목표 자리를 먼저 훑어 새 글라이드를 띄운 다음 시간을 민다. BattleSim 은
	# 이동 타이머를 더 이상 들고 있지 않으므로 이 구간의 프레임은 여기서 만든다.
	_sync_glide(_solve_slots())
	if _advance_glide(delta):
		dirty = true
	if dirty:
		queue_redraw()


## 각 파일럿의 강조 배율을 목표값 쪽으로 `EMPHASIS_TWEEN_SEC` 페이스로 민다.
## 아직 움직이는 중이면 true(= 계속 다시 그려야 한다).
##
## 목표에 닿은 1.0 은 dict 에서 지운다 — 기본값이 1.0 이므로 남겨 둘 이유가 없고,
## 매 판 새 PilotData 가 들어오는 자리에 죽은 키가 쌓이지 않는다.
func _advance_emphasis(delta: float) -> bool:
	var step: float = (TARGET_EMPHASIS_SCALE - 1.0) \
			* (delta / maxf(0.0001, EMPHASIS_TWEEN_SEC))
	var moving: bool = false
	for raw in _bs.pilots:
		var p := raw as PilotData
		var want: float = _pilot_emphasis_target(p)
		var have: float = float(_emphasis_now.get(p, 1.0))
		if is_equal_approx(have, want):
			continue
		have = move_toward(have, want, step)
		moving = true
		if is_equal_approx(have, 1.0):
			_emphasis_now.erase(p)
		else:
			_emphasis_now[p] = have
	return moving


## 누른 초상의 배율을 `PRESS_SCALE` / 1.0 쪽으로 민다. 움직이는 중이면 true.
func _advance_press(delta: float) -> bool:
	var step: float = (PRESS_SCALE - 1.0) * (delta / maxf(0.0001, PRESS_TWEEN_SEC))
	var moving: bool = false
	if _press_pilot != null and not _press_now.has(_press_pilot):
		_press_now[_press_pilot] = 1.0
	for raw in _press_now.keys():
		var p := raw as PilotData
		var want: float = PRESS_SCALE if p == _press_pilot else 1.0
		var have: float = float(_press_now[p])
		if is_equal_approx(have, want):
			if want == 1.0:
				_press_now.erase(p)
			continue
		_press_now[p] = move_toward(have, want, step)
		moving = true
	return moving


## 초상을 눌렀다 — 커지기 시작하고 맨 위로 올라온다(뗀 뒤에도 맨 위는 남는다).
func press_marker(p: PilotData) -> void:
	_press_pilot = p
	_top_pilot = p
	queue_redraw()


## 손을 뗐다 — 크기만 돌아온다.
func release_marker() -> void:
	_press_pilot = null


## `pos` 아래의 초상(살아 있는 파일럿만). 맨 위 초상이 먼저 답하고, 나머지는
## 그려진 마커 중심이 가장 가까운 쪽이다 — 겹친 두 얼굴 중 뒤에 깔린 쪽의
## 드러난 부분을 누르면 대개 그쪽 중심이 더 가깝다.
func marker_at(pos: Vector2) -> PilotData:
	var markers: Dictionary = _pilot_render_layout
	if markers.is_empty():
		markers = pilot_marker_positions()
	if _top_pilot != null and markers.has(_top_pilot) and _top_pilot.alive:
		var top_r: float = marker_outer_radius(pilot_marker_radius(_top_pilot))
		if (markers[_top_pilot] as Vector2).distance_to(pos) <= top_r:
			return _top_pilot
	var best: PilotData = null
	var best_d: float = INF
	for raw in markers.keys():
		var p := raw as PilotData
		if not p.alive:
			continue
		var d: float = (markers[p] as Vector2).distance_to(pos)
		if d <= marker_outer_radius(pilot_marker_radius(p)) and d < best_d:
			best_d = d
			best = p
	return best


## HP 감소를 감지해 조각을 띄우고, 떠 있는 조각의 시간을 민다. 그릴 조각이
## 남아 있으면 true.
func _advance_hp_chips(delta: float) -> bool:
	var engage_busy: bool = _bs.engage_phase != null and _bs.engage_phase.is_active()
	if not engage_busy:
		for raw in _bs.pilots:
			var p := raw as PilotData
			var now := Vector2i(p.hp, p.shield)
			var seen: Vector2i = _hp_seen.get(p, now)
			if (now.x < seen.x or now.y < seen.y) and p.max_hp > 0:
				var segs: Array = hp_loss_segments(seen.x, seen.y, now.x, now.y, p.max_hp)
				if not segs.is_empty():
					_hp_chips.append({"p": p, "segs": segs, "t": 0.0})
			_hp_seen[p] = now
	if _hp_chips.is_empty():
		return false
	var keep: Array = []
	for raw in _hp_chips:
		var c: Dictionary = raw
		c["t"] = float(c["t"]) + delta
		if float(c["t"]) < HP_CHIP_DUR:
			keep.append(c)
	_hp_chips = keep
	return true


## Ticks every live popup and drops the expired ones. Returns true while at
## least one is still on screen so the caller keeps redrawing.
func _advance_popups(delta: float) -> bool:
	if _popups.is_empty():
		return false
	var keep: Array = []
	for raw in _popups:
		var e: Dictionary = raw
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < float(e["delay"]) + float(e["dur"]):
			keep.append(e)
	_popups = keep
	return true


## Floats `text` above `p`'s currently-drawn marker. `delay` staggers the
## members of a 연속 공격 chain so several numbers off the same swing don't
## stack on one pixel.
func spawn_pilot_popup(p: PilotData, text: String, color: Color,
		delay: float = 0.0, dur: float = -1.0, rise: float = -1.0,
		icon: Texture2D = null, size_scale: float = 1.0) -> void:
	if p == null:
		return
	var markers: Dictionary = _build_pilot_render_layout()
	var pos: Vector2 = markers[p] as Vector2 if markers.has(p) \
			else _bs.pilot_marker_pos_solo(p)
	_popups.append({
		"pos":   pos,
		"text":  text,
		"color": color,
		"t":     0.0,
		"delay": max(0.0, delay),
		"dur":   _bs.DMG_POPUP_DUR if dur <= 0.0 else dur,
		"rise":  _bs.DMG_POPUP_RISE_PX if rise <= 0.0 else rise,
		"icon":  icon,
		"scale": size_scale,
	})
	queue_redraw()


## 성장치가 오른 것을 그 파일럿 얼굴 위에 띄운다 — `+1.50k`. 진입점은
## `BattleSim._show_score_gain` / `flush_score_popups` 뿐이고, **무엇을 띄울지
## (어느 적립처를 보여 줄지)는 여기가 아니라 그쪽이 정한다.**
func spawn_score_popup(p: PilotData, amount: float) -> void:
	if amount <= 0.0:
		return
	spawn_pilot_popup(p, "+" + BattleSim.fmt_score_gain(amount),
			BattleSim.SCORE_POPUP_COLOR, 0.0,
			BattleSim.SCORE_POPUP_DUR, BattleSim.SCORE_POPUP_RISE_PX,
			BattleSim.SCORE_POPUP_ICON, score_popup_scale(amount))


## 성장치 팝업 배율 — `SCORE_POPUP_SIZE_*` 주석 참조. `amount` 는 성장치 단위
## (화면 숫자 = × 1000).
static func score_popup_scale(amount: float) -> float:
	var shown: float = amount * 1000.0
	var lo: float = SCORE_POPUP_SIZE_LO_AMOUNT
	var hi: float = SCORE_POPUP_SIZE_HI_AMOUNT
	var t: float = clampf(log(maxf(shown, lo) / lo) / log(hi / lo), 0.0, 1.0)
	return lerpf(SCORE_POPUP_SIZE_MIN, SCORE_POPUP_SIZE_MAX, t)


## Ticks every live burst and drops the expired ones. Same shape as
## `_advance_popups` — returns true while at least one is still on screen.
func _advance_bursts(delta: float) -> bool:
	if _bursts.is_empty():
		return false
	var keep: Array = []
	for raw in _bursts:
		var e: Dictionary = raw
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < BURST_DUR:
			keep.append(e)
	_bursts = keep
	return true


## 피격자 초상에서 조각이 퍼지는 연출을 띄운다. 진입점은
## `BattleSim.anim_pilot_impact` 하나이고, 그 함수를 부르는 것은 공격 카드
## (`CardPhaseManager._effect_attack`)뿐이다 — 전장 자동 교전은 예전대로
## 흔들림만 준다(매 턴 도는 피해까지 조각을 뿌리면 그게 곧 배경이 된다).
func spawn_pilot_burst(p: PilotData) -> void:
	if p == null:
		return
	var markers: Dictionary = _build_pilot_render_layout()
	var pos: Vector2 = markers[p] as Vector2 if markers.has(p) \
			else _bs.pilot_marker_pos_solo(p)
	var r: float = pilot_marker_radius(p)
	# 각도는 균등 분할 + 흔들기다. 완전 무작위로 뽑으면 열두 조각이 한쪽에
	# 뭉치는 프레임이 자주 나와 "퍼진다"가 아니라 "샌다"로 보인다.
	var shards: Array = []
	for i in BURST_COUNT:
		var ang: float = (float(i) / float(BURST_COUNT)) * TAU 				+ randf_range(-0.22, 0.22)
		shards.append({
			"dir":   Vector2(cos(ang), sin(ang)),
			"reach": r * randf_range(BURST_REACH_MIN, BURST_REACH_MAX),
			"size":  randf_range(0.6, 1.0),
		})
	_bursts.append({"pos": pos, "t": 0.0, "shards": shards})
	queue_redraw()


## 조각들. 바깥으로 감속하며 날아가고 뒷부분에서 흐려지며 작아진다.
func _draw_pilot_bursts() -> void:
	if _bursts.is_empty():
		return
	var dot_r: float = BURST_DOT_R * HexGrid.DISPLAY_SCALE
	for raw in _bursts:
		var e: Dictionary = raw
		var k: float = clampf(float(e["t"]) / BURST_DUR, 0.0, 1.0)
		var travel: float = 1.0 - pow(1.0 - k, 2.0)   # 감속
		var alpha: float = 1.0 if k < 0.45 else 1.0 - (k - 0.45) / 0.55
		var origin: Vector2 = e["pos"] as Vector2
		for raw_s in (e["shards"] as Array):
			var sh: Dictionary = raw_s
			var at: Vector2 = origin \
					+ (sh["dir"] as Vector2) * (float(sh["reach"]) * travel)
			draw_circle(at, dot_r * float(sh["size"]) * (1.0 - k * 0.55),
					_alpha_mul(BURST_COLOR, alpha))


## 시전자 초상 위로 솟는 하얀 빛. 마커 폭의 세로 기둥 하나가 위로 흐르며
## 옅어지고, 그 앞머리에 작은 원이 하나 떠오른다 — 기둥만 그리면 어디까지가
## 이번 프레임의 앞머리인지가 안 읽힌다.
func _draw_pilot_cast_fx() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		var k: float = _bs.pilot_cast_progress(p)
		if k < 0.0:
			continue
		if not _is_renderable(p):
			continue
		var pos: Vector2 = _pilot_marker_pos(p)
		var r: float = pilot_marker_radius(p)
		var rise: float = _bs.ANIM_CAST_RISE_PX * HexGrid.DISPLAY_SCALE * k
		var half_w: float = r * CAST_BEAM_W_RATIO
		# 알파는 앞머리에서 뒤로 갈수록, 그리고 진행도가 끝에 가까울수록 옅다.
		var fade: float = 1.0 - k * k
		var top: float = pos.y - r * 0.35 - rise
		draw_rect(Rect2(pos.x - half_w, top, half_w * 2.0,
				(pos.y + r * 0.45) - top),
				_alpha_mul(CAST_COLOR, 0.16 * fade))
		draw_rect(Rect2(pos.x - half_w * 0.42, top, half_w * 0.84,
				(pos.y + r * 0.45) - top),
				_alpha_mul(CAST_COLOR, 0.26 * fade))
		draw_circle(Vector2(pos.x, top), maxf(2.0, half_w * 0.5 * (1.0 - k * 0.4)),
				_alpha_mul(CAST_COLOR, 0.72 * fade))


## Drops every in-flight popup. Called on restart so numbers from the previous
## match don't float over the fresh board.
func clear_popups() -> void:
	_popups.clear()
	_bursts.clear()
	banners.clear()
	_hp_chips.clear()
	_hp_seen.clear()
	_press_now.clear()
	_press_pilot = null
	_top_pilot = null
	queue_redraw()


func _draw_pilot_popups() -> void:
	if _popups.is_empty():
		return
	var font := ThemeDB.fallback_font
	for raw in _popups:
		var e: Dictionary = raw
		var fsz: int = maxi(1, int(round(POPUP_FONT_SIZE_BASE * HexGrid.DISPLAY_SCALE
				* float(e.get("scale", 1.0)))))
		var local_t: float = float(e["t"]) - float(e["delay"])
		if local_t < 0.0:
			continue
		var k: float = clampf(local_t / float(e["dur"]), 0.0, 1.0)
		# 위로 갈수록 감속하며 떠오르고, 뒷부분에서만 흐려진다.
		var rise: float = float(e["rise"]) * (1.0 - pow(1.0 - k, 2.0))
		var alpha: float = 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
		var txt: String = String(e["text"])
		var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
		var icon := e.get("icon") as Texture2D
		if icon != null:
			_draw_icon_popup(font, fsz, txt, tsz, icon, e, rise, alpha)
			continue
		var base: Vector2 = (e["pos"] as Vector2) \
				+ Vector2(-tsz.x * 0.5, -PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE - rise)
		# 검은 외곽선 먼저 — 전장 타일 위에서도 숫자가 읽히도록.
		var outline := _alpha_mul(Color(0.0, 0.0, 0.0), alpha * 0.85)
		for ox in [-2.0, 2.0]:
			for oy in [-2.0, 2.0]:
				draw_string(font, base + Vector2(ox, oy), txt,
						HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, outline)
		draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
				_alpha_mul(e["color"] as Color, alpha))


## 아이콘 + 숫자 한 줄(성장치 팝업). 아이콘은 글자 높이에 맞춰 늘리고, 둘을 합친
## 폭의 가운데를 마커 위에 맞춘다. 글자는 굵은 검은 외곽선을 먼저 깐다.
func _draw_icon_popup(font: Font, fsz: int, txt: String, tsz: Vector2,
		icon: Texture2D, e: Dictionary, rise: float, alpha: float) -> void:
	var icon_sz: float = font.get_height(fsz)
	var k: float = float(e.get("scale", 1.0))
	var gap: float = SCORE_POPUP_ICON_GAP * HexGrid.DISPLAY_SCALE * k
	var total_w: float = icon_sz + gap + tsz.x
	var base: Vector2 = (e["pos"] as Vector2) \
			+ Vector2(-total_w * 0.5, -PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE - rise)
	# `base.y` 는 글자 기준선 — 줄 상단은 ascent 만큼 위다.
	var line_top: float = base.y - font.get_ascent(fsz)
	draw_outlined_icon(self, icon, Rect2(base.x, line_top, icon_sz, icon_sz),
			SCORE_POPUP_ICON_OUTLINE_PX * HexGrid.DISPLAY_SCALE * k, alpha)
	var text_at := Vector2(base.x + icon_sz + gap, base.y)
	var outline_px: int = maxi(1, int(round(SCORE_POPUP_OUTLINE_PX * HexGrid.DISPLAY_SCALE * k)))
	draw_string_outline(font, text_at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			outline_px, _alpha_mul(Color(0.0, 0.0, 0.0), alpha))
	draw_string(font, text_at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			_alpha_mul(e["color"] as Color, alpha))


func _draw() -> void:
	# **게이트는 페이즈가 아니라 "그릴 것이 있는가"다.** 예전에는 GAMBIT 이면
	# 통째로 건너뛰었는데, 정글 시작 선택이 그 GAMBIT 안으로 들어오면서 개시
	# 전에도 전장이 보여야 하게 됐다 — 어느 쪽 정글로 갈지는 정글 소유 · 캠프 ·
	# 우리 정글러의 자리를 보고 정하는 선택이다.
	if not _bs.field_ready:
		return
	# Recompute the per-cell pilot grouping once so _draw_pilot_groups and the
	# targeting dim overlay agree on where each pilot's marker landed within
	# its team's offset row above / below the tile.
	_pilot_render_layout = _build_pilot_render_layout()
	_pick_top = null
	if _bs.targeting_overlay != null:
		_pick_top = _bs.targeting_overlay.picked_pilot()
		if _pick_top != null and not _is_renderable(_pick_top):
			_pick_top = null
	_draw_field_outline()
	_draw_front_line_overlays()
	_draw_captured_tile_overlays()
	_draw_jungle_camps()
	_draw_jungle_pick_dim()
	_draw_jungle_start_zones()
	_draw_targeting_underlays()
	# Out-of-range tile dim is drawn BEFORE HQ/turret/pilot graphics so a
	# pilot marker that visually overlaps an adjacent out-of-range tile (the
	# marker is offset above/below its own tile) is not obscured by the dim.
	# The dim now goes up the moment a card is lifted in hand — selecting IS
	# targeting. is_visualizing() is false for INSTANT cards (no range to show),
	# so a 드로우 / 전략 점수 card leaves the battlefield untouched.
	var draw_dim: bool = _bs.targeting_overlay != null \
			and _bs.targeting_overlay.is_visualizing()
	if draw_dim:
		_draw_targeting_tile_dim(_undimmed_cells())
	_draw_hq_hp_bars()
	_draw_turret_hp_bars()
	# 손패 카드 시전자의 하얀 네온 — 마커 뒤에.
	_draw_card_preview_neon()
	_draw_pilot_groups()
	# 정글 시작 경로 중 **마커가 앉는 칸의 번호**만 마커 위에 배지로 — 그 칸이
	# 도착 턴인데, 다른 번호처럼
	# 칸 한가운데에 찍으면 정글러 얼굴이 통째로 덮는다.
	_draw_jungle_start_marker_badge()
	# Per-pilot dim is the only dim drawn ON TOP of pilot markers — only
	# applied to pilots whose own cell is INSIDE the in-range set (so they're
	# not already covered by tile dim). This prevents the double-dim where an
	# invalid pilot in an out-of-range cell got a tile dim hex AND a per-
	# marker disc stacked on each other.
	if draw_dim:
		_draw_targeting_pilot_dim()
	# 가리킨 대상의 초상 + 시안 링은 **딤 위에** — 이웃 칸 초상이나 그 딤 원판이
	# 대상 얼굴을 덮지 않는다(초상은 `_draw_pilot_groups` 에서 빠져 있다).
	_draw_pending_pick_highlight()
	# 손패 카드 효과 미리보기(경로 · 명중 예상 · 회복 · 고스트 · 영혼) — 딤 위에.
	_draw_card_preview_field()
	# 공격 카드 연출 두 겹 — 시전자 빛은 초상 위에, 피격 조각은 그 위에.
	_draw_pilot_cast_fx()
	_draw_pilot_bursts()
	# 피해 수치 / MISS 는 무엇에도 가려지면 안 되므로 맨 마지막.
	_draw_pilot_popups()
	_draw_buff_banners()


# ─── Per-frame pilot render layout cache ─────────────────────────────────────
# Built once per _draw() call so the per-pilot dim overlay can ask "where on
# screen is this pilot's marker?" without redoing the team-stack solve.
# Schema:
#   _pilot_render_layout = {
#     PilotData → Vector2 marker_pos (tile centre when solo, else offset)
#   }
var _pilot_render_layout: Dictionary = {}


## 정글 시작 선택 동안 **놓을 수 없는 칸을 전부 덮는다.** 이 화면에서 고를 수
## 있는 것은 우리 정글과 아직 아무도 안 잡은 중립 칸뿐이므로 레인 통로 · 포탑
## 칸 · HQ · **상대 소유 정글**은 지금 판단의 대상이 아니다.
##
## 밝게 남는 칸의 정의를 드롭 대상(`JungleStartOverlay.active_cells`)에서 그대로
## 가져오는 것이 요점이다: 놓을 수 있는 칸과 밝은 칸이 같은 목록에서 나온다.
##
## 캠프 아웃라인 **뒤**, 칸 강조 **앞**에 그린다 — 그 둘은 이 선택의 근거이자
## 안내라 딤 위에 남아야 한다.
func _draw_jungle_pick_dim() -> void:
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp == null or not jp.is_active():
		return
	_draw_targeting_tile_dim(jp.active_cells())


## 정글 시작 선택 동안 놓을 수 있는 칸을 칸 단위로 밝히고, 마커가 올라온(또는
## 고른) 칸을 금색으로 두른 뒤 **HQ 에서 그 칸까지 + 도착 뒤 6턴** 정글러가
## 걸어갈 길을 그린다(칸마다 몇 턴째인지).
##
## 캠프 아웃라인 **뒤에** 그린다(호출 순서가 곧 z-order다) — 이 강조는 잠깐
## 떴다 사라지는 안내이고, 그 밑의 소유 색과 캠프 테두리는 그 선택의 근거라
## 가려지면 안 된다. 그래서 채움은 옅고 테두리만 또렷하다. 경로는 마커 **밑**이다 —
## 끌고 있는 얼굴이 그 위로 지나가야 손이 무엇을 옮기는지가 읽힌다.
func _draw_jungle_start_zones() -> void:
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp == null or not jp.is_active():
		return
	var hg: HexGrid = _bs.hex_grid
	var hot: Vector2i = jp.highlight_cell()
	for c_raw in jp.active_cells().keys():
		var c := c_raw as Vector2i
		if c == hot:
			continue
		var pts := hg.hex_corners(_bs.cell_center(c))
		draw_colored_polygon(pts, JungleStartOverlay.ZONE_FILL)
		draw_polyline(_close_polygon(pts), JungleStartOverlay.ZONE_LINE, 3.0, true)
	if hot == JungleStartOverlay.NO_CELL:
		return
	# 고른 칸은 맨 나중에 — 이웃 칸의 초록 테두리가 금색 변을 덮지 않게.
	var hot_pts := hg.hex_corners(_bs.cell_center(hot))
	draw_colored_polygon(hot_pts, JungleStartOverlay.ZONE_FILL_HOT)
	draw_polyline(_close_polygon(hot_pts), JungleStartOverlay.ZONE_LINE_HOT, 5.0, true)
	_draw_jungle_start_path(jp)


## 정글 시작 경로. **시작 칸까지는 금색, 도착한 뒤의 걸음은 하늘색**이다 — 앞은
## 플레이어가 고른 길이고 뒤는 그 결과로 정글러가 스스로 도는 순회라, 같은 색이면
## 어디까지가 내가 정한 것인지가 안 읽힌다.
##
## 턴 번호는 **그 턴이 끝나는 칸**에만 찍는다(`move_range` 2 면 지나치는 칸에 같은
## 숫자가 두 번 찍히지 않게). 도착 뒤의 순회는 왔던 칸을 다시 지나는 일이 흔해서
## 한 칸에 번호가 여럿일 수 있다 — 그 칸은 원을 겹치지 않고 **한 알약에 "2·7"**
## 로 묶는다(따로 그리면 뒤 번호가 앞 번호를 덮어 2턴째가 사라진다).
##
## 마커가 앉는 칸(`highlight_cell`)의 번호만은 여기서 안 그리고 마커를 그린 뒤
## `_draw_jungle_start_marker_badge` 가 얼굴 오른쪽 아래에 배지로 얹는다.
func _draw_jungle_start_path(jp: JungleStartOverlay) -> void:
	var steps: Array = jp.path_cells()
	if steps.is_empty():
		return
	var prev: Vector2 = _bs.cell_center(jp.jungler().grid_pos)
	for raw in steps:
		var st: Dictionary = raw
		var c: Vector2 = _bs.cell_center(st["cell"] as Vector2i)
		var col: Color = JungleStartOverlay.PATH_LINE_AFTER if bool(st["after"]) \
				else JungleStartOverlay.PATH_LINE
		draw_line(prev, c, col, 6.0, true)
		draw_circle(c, 3.0, col)   # 꺾이는 마디를 메운다 — 두 선분의 끝이 각지게 벌어진다
		prev = c
	var labels: Dictionary = _jungle_path_labels(steps)
	var hot: Vector2i = jp.highlight_cell()
	for cell_raw in labels.keys():
		if cell_raw == hot:
			continue
		_draw_jungle_path_pill(_bs.cell_center(cell_raw as Vector2i), labels[cell_raw])


## 경로를 칸 → 그 칸의 방문들(`{turn, after}`, 방문 순서대로)로 묶는다.
## 턴이 끝나는 칸만 남긴다(`move_range` 2 면 지나치는 칸에는 번호가 없다).
func _jungle_path_labels(steps: Array) -> Dictionary:
	var labels: Dictionary = {}
	for i in steps.size():
		var st: Dictionary = steps[i]
		var last_of_turn: bool = i == steps.size() - 1 \
				or int((steps[i + 1] as Dictionary)["turn"]) != int(st["turn"])
		if not last_of_turn:
			continue
		var cell := st["cell"] as Vector2i
		if not labels.has(cell):
			labels[cell] = []
		(labels[cell] as Array).append(st)
	return labels


func _draw_jungle_start_marker_badge() -> void:
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp == null or not jp.is_active():
		return
	var hot: Vector2i = jp.highlight_cell()
	if hot == JungleStartOverlay.NO_CELL:
		return
	var labels: Dictionary = _jungle_path_labels(jp.path_cells())
	if not labels.has(hot):
		return
	var rad: float = pilot_marker_radius(jp.jungler())
	var at: Vector2 = jp.marker_pos(_bs.cell_center(hot)) + Vector2(rad, rad) * 0.78
	_draw_jungle_path_pill(at, labels[hot])


## 턴 번호 알약 하나. 한 칸에 방문이 여럿이면 "2·7" 로 묶고, 테두리 색은 **첫
## 방문**을 따른다(시작 칸까지의 길이면 금색, 순회에서 처음 밟으면 하늘색).
func _draw_jungle_path_pill(c: Vector2, visits: Array) -> void:
	var font: Font = ThemeDB.fallback_font
	var r: float = 17.0 * HexGrid.DISPLAY_SCALE
	var fsz: int = int(20.0 * HexGrid.DISPLAY_SCALE)
	var parts: PackedStringArray = []
	for v in visits:
		parts.append(str(int((v as Dictionary)["turn"])))
	var txt: String = "·".join(parts)
	var ring: Color = JungleStartOverlay.PATH_LINE_AFTER \
			if bool((visits[0] as Dictionary)["after"]) else JungleStartOverlay.PATH_LINE
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var half_w: float = maxf(r, tw * 0.5 + r * 0.55)
	var rect := Rect2(c.x - half_w, c.y - r, half_w * 2.0, r * 2.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = JungleStartOverlay.PATH_DOT
	sb.border_color = ring
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(r))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	draw_string(font, c + Vector2(-tw * 0.5, fsz * 0.36), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, JungleStartOverlay.PATH_TEXT)


## 전장 외곽선 — 타일이 있는 칸 전체를 **한 덩어리**로 보고 그 바깥 윤곽만
## 긋는다. 한 변을 긋는 조건은 하나, 그 변 너머에 유효한 칸이 없을 것
## (`_neighbor_across_edge` 가 센티널을 돌려준다). 이웃끼리 맞닿은 변에는 선이
## 없어 타일이 이어져 보인다 — 그래서 타일 PNG(`hexa-tileset.png` 0행)도 테두리
## 없이 면만 칠하고 1.5px 크게 그려 이웃과 겹치게 했다(경계 솔기 방지).
##
## 변을 낱개 `draw_line` 으로 그으면 굵은 선의 120° 꺾임마다 이가 빠지므로,
## 바깥 변들을 꼭짓점으로 이어 닫힌 고리로 만든 뒤 `draw_polyline` 한 번에
## 그린다. 맨 먼저 그려 점령 면 · 캠프 테두리가 그 위에 얹힌다.
const FIELD_OUTLINE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FIELD_OUTLINE_WIDTH: float = 4.0

func _draw_field_outline() -> void:
	for loop in _field_outline_loops():
		draw_polyline(loop, FIELD_OUTLINE_COLOR, FIELD_OUTLINE_WIDTH, true)


## 바깥 변을 이어 붙인 닫힌 고리들(첫 점이 끝에 한 번 더 들어간다).
## 꼭짓점은 서로 다른 칸 중심에서 계산돼 부동소수 오차가 있으므로 0.1px 로
## 반올림한 키로 잇는다.
func _field_outline_loops() -> Array:
	var hg: HexGrid = _bs.hex_grid
	var next_of: Dictionary = {}   # 시작점 키 → 끝점
	var start_of: Dictionary = {}  # 시작점 키 → 시작점
	for raw in _bs.tiles_layer.get_used_cells():
		var cell := raw as Vector2i
		var center := _bs.cell_center(cell)
		var pts := hg.hex_corners(center)
		for i in range(6):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % 6]
			if _neighbor_across_edge(cell, center, (a + b) * 0.5).x != -9999:
				continue    # 안쪽 변 — 이웃과 이어진다
			# hex_corners 는 화면에서 시계방향이라 바깥 변도 모두 같은 방향으로
			# 감긴다 → 한 변의 끝점이 곧 다음 변의 시작점이다.
			next_of[_outline_key(a)] = b
			start_of[_outline_key(a)] = a
	var loops: Array = []
	while not next_of.is_empty():
		var k0: Vector2i = next_of.keys()[0]
		var loop := PackedVector2Array([start_of[k0]])
		var k := k0
		while next_of.has(k):
			var nxt: Vector2 = next_of[k]
			next_of.erase(k)
			loop.append(nxt)
			k = _outline_key(nxt)
		loops.append(loop)
	return loops


func _outline_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))


# Captured jungle/neutral tiles use saturated team-coloured atlas tiles. We
# overlay a translucent white polygon on owned cells so the team identity
# still reads but the tile no longer competes with pilot markers / HP bars.
func _draw_captured_tile_overlays() -> void:
	var hg: HexGrid = _bs.hex_grid
	for raw_cell in _bs.neutral_zone_cells.keys():
		var cell := raw_cell as Vector2i
		var owner_id: int = int(_bs.neutral_zone_cells[cell])
		if owner_id < 0:
			continue
		var center := _bs.cell_center(cell)
		var pts := hg.hex_corners(center)
		draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.55))


# ─── 전선 / 정글 캠프 (성장치 수입이 나오는 자리) ────────────────────────────
## 전선 = 그 레인에서 양 팀의 살아 있는 최전방 포탑 **사이**. 레인 파일럿은 이
## 안에 살아서 서 있는 턴에만 성장치를 번다(`SimulationCore.award_frontline_income`).
##
## 화면에 그리는 이유는 하나다 — 수입이 위치에서 나오는데 그 위치가 안 보이면
## 플레이어는 자기가 왜 뒤처지는지 알 수 없다. 얇은 테두리로만 표시해 타일 색
## (정글 점령)과 경쟁하지 않게 한다.
const FRONT_LINE_COLOR: Color = Color(0.98, 0.86, 0.42, 0.30)
const FRONT_LINE_WIDTH: float = 2.0
## 캠프 아웃라인 — **차 있는 캠프가 있는 타일의 테두리**를 그린다.
##
## 예전에는 칸 한가운데에 작은 마름모를 찍었다(우리 것 = 꽉 찬 초록, 적 것 =
## 속 빈 초록). 마름모는 그 칸 **안**의 물건이라 정글러 초상화와 자리를 다퉜고,
## 캠프가 서너 칸 이어져 있어도 점 셋으로 흩어져 "이쪽 정글이 통째로 남아 있다"
## 가 한눈에 안 들어왔다. 테두리는 타일 자체를 가리키므로 초상화와 겹칠 일이
## 없고, **인접한 캠프끼리는 사이 변을 그리지 않아** 여러 칸이 하나의 덩어리로
## 이어져 보인다(아래 `_draw_jungle_camps`).
##
## **색은 소유를 가르지 않는다 — 차 있으면 밝은 노랑, 그게 전부다.** 한때는
## 적 소유 칸의 캠프를 어두운 호박색(`CAMP_LINE_ENEMY_COLOR`, 삭제됨)으로 따로
## 그렸는데, 그 색이 "비어 있음"과 구분되지 않아 정작 화면에서 읽히는 것은
## 소유가 아니라 밝기였다. 소유는 이미 타일 자체가 팀색으로 말하고 있으므로
## 테두리는 **지금 이 칸에 성장 포인트가 남아 있는가** 하나만 말하면 된다.
const CAMP_LINE_COLOR: Color = Color(1.00, 0.90, 0.28, 0.98)
const CAMP_LINE_WIDTH: float = 3.0
## 캠프를 다 먹어 **비어 있는** 정글/중립 칸에 덧씌우는 그늘. 테두리가 사라지는
## 것만으로는 "여긴 아직 안 먹었다"와 "여긴 방금 먹었다"가 같은 그림이 된다 —
## 밝기 한 단계를 내려 두면 정글러가 어디로 돌아야 하는지가 색만으로 읽힌다.
## 재생성(`JUNGLE_CAMP_RESPAWN_TURNS`(const.csv) 턴)이 돌면 그늘이 걷히고 노란 테두리가 돌아온다.
const CAMP_SPENT_TINT: Color = Color(0.0, 0.0, 0.05, 0.34)

func _draw_front_line_overlays() -> void:
	if _bs.sim_core == null or _bs.turrets.is_empty():
		return
	var hg: HexGrid = _bs.hex_grid
	for lane in _bs.sim_core.lane_corridor_count():
		for raw in _bs.sim_core.front_line_cells(lane).keys():
			var pts := hg.hex_corners(_bs.cell_center(raw as Vector2i))
			pts.append(pts[0])
			draw_polyline(pts, FRONT_LINE_COLOR, FRONT_LINE_WIDTH)


## 차 있는 캠프가 서 있는 정글 타일의 **테두리**를 그린다.
##
## 한 변을 그리는 조건은 하나다 — 그 변 너머의 이웃 칸이 **같은 부류의 캠프가
## 아닐 것**. 그래서 캠프 두 칸이 붙어 있으면 맞닿은 변이 양쪽에서 다 빠져
## 바깥 윤곽만 남고, 정글 한쪽이 통째로 차 있으면 그 덩어리 전체가 하나의
## 테두리로 읽힌다. 부류(우리 것 / 적 것)가 다르면 사이 변을 그린다 — 색이
## 다른 두 덩어리가 경계 없이 붙어 있으면 어디까지가 어느 쪽인지 알 수 없다.
##
## 변 ↔ 이웃 대응은 **표가 아니라 기하로 푼다**: 변의 중점이 중심에서 뻗는
## 방향과 이웃 칸 중심 방향을 맞춰 본다. 육각 오프셋 좌표는 홀/짝 열마다 이웃
## 오프셋이 달라(이 저장소가 이미 부호 버그로 한 번 앓았다) 손으로 적은 표가
## 조용히 틀리기 쉬운 자리다.
##
## 판정은 시뮬레이터와 같은 함수(`camp_harvestable` / `camp_charged`)를 지나므로
## 보이는 캠프와 먹히는 캠프가 어긋날 수 없다.
func _draw_jungle_camps() -> void:
	if _bs.sim_core == null:
		return
	# 차 있는 칸 / 빈 칸을 한 번에 가른다. 소유는 보지 않는다 — 테두리는
	# "성장 포인트가 남아 있는가" 하나만 말한다.
	var charged: Dictionary = {}   # Vector2i → true
	var spent: Array = []
	for raw in _bs.jungle_camps.keys():
		var cell := raw as Vector2i
		if _bs.sim_core.camp_charged(cell):
			charged[cell] = true
		else:
			spent.append(cell)

	# 빈 칸부터 — 그늘은 테두리보다 아래에 깔려야 한다(이웃한 차 있는 칸의
	# 테두리가 그늘에 먹히지 않게).
	for raw in spent:
		var cell := raw as Vector2i
		draw_colored_polygon(_bs.hex_grid.hex_corners(_bs.cell_center(cell)),
				CAMP_SPENT_TINT)

	for raw in charged.keys():
		var cell := raw as Vector2i
		var center := _bs.cell_center(cell)
		var pts := _bs.hex_grid.hex_corners(center)
		for i in range(6):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % 6]
			var across := _neighbor_across_edge(cell, center, (a + b) * 0.5)
			if charged.has(across):
				continue    # 같은 덩어리의 안쪽 변 — 이어 붙는다
			draw_line(a, b, CAMP_LINE_COLOR, CAMP_LINE_WIDTH)


## `cell` 의 어느 변(중점 `edge_mid`) 너머에 있는 이웃 칸. 없으면 (-9999,-9999).
## 이웃 여섯 중 중심 방향이 그 변과 가장 잘 맞는 것을 고른다.
func _neighbor_across_edge(cell: Vector2i, center: Vector2,
		edge_mid: Vector2) -> Vector2i:
	var want := (edge_mid - center).normalized()
	for raw in _bs.hex_grid.get_neighbors(cell.x, cell.y):
		var nb := raw as Vector2i
		var dir := (_bs.cell_center(nb) - center).normalized()
		if dir.dot(want) > 0.99:
			return nb
	return Vector2i(-9999, -9999)


func _draw_pilot_groups() -> void:
	var by_cell := _group_pilots_by_render_cell()

	# 칸 순회 순서는 Dictionary 순서 그대로다. 예전에는 돌진(몸통 박치기) 중인
	# 칸을 맨 마지막으로 미뤘는데(`_lunging_cells_last`, 삭제됨), 그 연출이
	# 시전자 초상을 대상 칸 위로 실제로 옮겼기 때문이다 — 지금은 초상이 제자리에
	# 있고 이펙트만 얹히므로 미룰 칸이 없다.
	# **타일 중앙 배지(`x3` / `2v1`)는 삭제됐다.** 한 칸에 선 사람이 몇인지는
	# 육각 링의 초상화가 낱개로 이미 말하고 있고(전원이 자기 슬롯을 받는다 —
	# 오버플로가 없다), 그 위에 숫자를 하나 더 얹으면 칸 한가운데를 차지해
	# 캠프 아웃라인 · 점령 면 색과 자리를 다퉜다. `_draw_cell_badge` 는 그때
	# 함께 사라졌다.
	#
	# **전장 전체를 세 겹으로 깐다 — 그림자 → 꼬리(화살표) → 초상.** 칸마다
	# 꼬리 + 초상을 한 번에 그리면 나중에 그린 칸의 꼬리가 먼저 그린 칸의 얼굴을
	# 덮었다. 꼬리는 어느 자리에 앉은 누구의 것이든 **모든 초상 밑**이다.
	# 맨 위 초상(`_top_pilot`)과 대상 지정 중 가리킨 초상(`_pick_top`)도 꼬리는
	# 여기서 함께 깔리고, 원판 그림자 + 초상만 나중에(맨 끝 / 딤 위) 올라온다.
	var radius: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	var all: Array = []
	for pos in by_cell.keys():
		all.append_array(by_cell[pos] as Array)
	for raw in all:
		var p := raw as PilotData
		var lifted: bool = p == _top_pilot or p == _pick_top
		_draw_marker_shadow(p, radius,
				PilotMarker.ShadowPart.TAIL if lifted else PilotMarker.ShadowPart.FULL)
	for raw in all:
		_draw_pilot_tail(raw as PilotData, radius)
	for raw in all:
		if raw != _top_pilot and raw != _pick_top:
			_draw_pilot_marker(raw as PilotData, radius)
	# **맨 위 초상**(마지막으로 누른 것)은 맨 끝에 원판 그림자째 다시 그려진다 —
	# 이웃 칸 마커에 가려져 있던 얼굴이 위로 올라온다(꼬리는 위에서 이미 깔렸다).
	var top := _top_pilot
	if top != null and top != _pick_top and _is_renderable(top) \
			and not _hidden_during_jungle_pick(top):
		_draw_marker_shadow(top, radius, PilotMarker.ShadowPart.DISC)
		_draw_pilot_marker(top, radius)


# Group renderable pilots by their *render* cell (not grid_pos): a pilot in
# recall fade-out is drawn at the cell they came from, so they don't crowd the
# HQ layout until the fade-in phase starts.
#
# **두 팀이 한 배열에 담긴다.** 초상화가 앉는 6슬롯은 셀 하나가 팀 구분 없이
# 공유하기 때문이다 — 기본 방향은 팀마다 반대쪽(팀0 S / 팀1 N)이라 출발점은
# 부딪히지 않지만, 겹침을 피해 **시계방향으로 도는 순간** 한 팀의 블록이 다른
# 팀의 슬롯 위로 넘어갈 수 있다. 한 표에서 같이 풀어야 그 자리를 서로 안다.
#
# 배열 순서는 `_bs.pilots` 순서(= 스폰 순서)다. 슬롯 배정이 순서에 의존하는
# 그리디라, 여기가 프레임마다 흔들리면 배치가 통째로 떨린다.
func _group_pilots_by_render_cell() -> Dictionary:
	var by_cell: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not _is_renderable(p):
			continue
		if _hidden_during_jungle_pick(p):
			continue
		var rcell := _render_cell(p)
		if not by_cell.has(rcell):
			by_cell[rcell] = []
		(by_cell[rcell] as Array).append(p)
	return by_cell


## 정글 시작 선택 동안 **전장에서 치워지는 파일럿.** 그 화면이 묻는 것은
## "우리 정글러가 어느 쪽에서 시작하는가" 하나이고, 나머지 아홉 명은 전원이
## 아직 자기 HQ 에 몰려 서 있어 두 덩어리로 뭉친 초상화가 정글 소유 · 캠프 ·
## 딤을 가릴 뿐이다. **정글러만 남는다** — 지금 옮기는 것이 저 사람이라는
## 사실은 화면에 있어야 한다.
##
## 자리 배정(`_solve_slots`)도 같은 목록을 읽으므로 숨은 사람은 슬롯을 잡지
## 않는다 — 안 보이는 마커 때문에 정글러가 링 바깥으로 밀리면 안 된다.
func _hidden_during_jungle_pick(p: PilotData) -> bool:
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp == null or not jp.is_active():
		return false
	return p != jp.jungler()


# Builds the PilotData → Vector2 marker_pos lookup shared by the drawing pass,
# the dim overlay and the targeting hit test.
#
# 세 걸음이다 — **자리를 푼다**(`_solve_slots`, 순수) → **글라이드를 맞춘다**
# (`_sync_glide`, 목표가 바뀐 파일럿에게 새 보간을 띄운다) → **지금 프레임의
# 좌표를 낸다**(`_compose_positions`, 강조 배율과 화면 클램프를 얹는다).
# 시간을 미는 것은 `_process` 의 `_advance_glide` 뿐이므로, 이 함수를 한 프레임에
# 여러 번 불러도(그리기 · 히트 테스트 · 파티클 좌표) 답이 흔들리지 않는다.
func _build_pilot_render_layout() -> Dictionary:
	var solution := _solve_slots()
	_sync_glide(solution)
	return _compose_positions(solution)


# PilotData → {"cell": Vector2i, "vec": 타일 중심에서의 변위, "ring": 몇 번째
# 겹인가, "grp": 같은 가로 줄 번호(육각 링 폴백은 -1)}. 모든 렌더 가능한 파일럿이
# 자기 자리를 받는다 — `+N` 오버플로 원은 사라졌다.
#
# **먼저 가로 줄로 앉힌다**(`_row_blocks` → `_pick_row_seats`): 팀 블록이 타일
# 아래(팀0) / 위(팀1)에 한 줄로 나란히 선다(HQ 칸도 예외 없음). 줄이 세 겹
# 어디에도 안 들어갈 때만 아래의 육각 링 배치로 떨어진다.
#
# 배정은 **전장 전체를 한 번에 훑는 그리디**이되, 낱개가 아니라 **블록 단위**다:
# 같은 칸에서 기본 방향이 같은 파일럿들(= 같은 팀)은 한 덩어리로 묶여 자리표의
# **연속된 창(window)** 을 통째로 차지하고, 막히면 창째 한 칸 옆으로 미끄러진다
# (`_pick_block_slots`). 낱개 그리디였을 때는 A·B 가 나란히 선 칸에서 A 의 자리만
# 막히면 A 가 B 를 뛰어넘어 반대쪽에 앉아, 두 얼굴의 좌우가 뒤바뀌었다.
#
# 겹침 판정이 **다른 칸의 마커까지** 본다는 것은 그대로다 — 위아래로 붙은 두 칸이
# 서로를 향한 슬롯을 고르는 일(= 초상화가 겹치는 유일한 구조적 원인)이 없다.
#
# **답은 입력이 바뀔 때만 다시 푼다.** 이 함수는 `_process` 에서 매 프레임, 그리고
# `_draw` · 히트 테스트 · 팝업 좌표에서 또 불리는데, 순수 함수라 입력
# (`_slot_input_key`)이 같으면 답도 같다. 전부 멈춰 있는 대부분의 프레임에서
# 정렬 · 그리디 · 꼬리 보정을 통째로 건너뛴다. 돌려준 표는 공유되므로 호출자는
# 고치지 않는다(지금 읽기만 한다).
func _solve_slots() -> Dictionary:
	var key := _slot_input_key()
	if key == _slot_key:
		return _slot_solution
	_slot_key = key
	_slot_solution = _solve_slots_fresh()
	return _slot_solution


## `_solve_slots` 가 읽는 입력 전부 — 슬롯을 받는 파일럿(스폰 순서) · 그 렌더 칸 ·
## 팀 · 레인, 그리고 칸 → 화면 좌표 변환(원점 칸 하나의 좌표로 대신한다).
func _slot_input_key() -> Array:
	var key: Array = [_bs.cell_center(Vector2i.ZERO)]
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not _is_renderable(p) or _hidden_during_jungle_pick(p):
			continue
		key.append(p)
		key.append(_render_cell(p))
		key.append(p.team)
		key.append(p.lane)
	return key


func _solve_slots_fresh() -> Dictionary:
	var out: Dictionary = {}
	var by_cell := _group_pilots_by_render_cell()
	var cells: Array = by_cell.keys()
	# 순회 순서가 곧 우선순위(먼저 도는 칸이 자기 기본 방향을 지킨다)이므로
	# 좌표로 정렬한다 — Dictionary 순서에 맡기면 같은 상황에서 프레임마다 다른
	# 칸이 양보하게 되어 배치가 떨린다.
	cells.sort_custom(_compare_cells)
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	# 이미 자리를 잡은 마커의 **강조 이전** 좌표. 슬롯 배정을 강조 배율과 무관하게
	# 두기 위한 것이다 — 강조까지 반영하면 카드를 집을 때마다 전장의 슬롯이 새로
	# 풀려 배치가 통째로 다시 섞인 것처럼 보인다.
	var placed: Array = []
	# 블록마다 `{"pilots", "center", "v", "cap", "bias", "row": 가로 줄이면 true,
	# "seats": [{"vec", "ring", "row"}]}` — 꼬리 겹침 보정(`_repair_arrow_overlaps`)이
	# 가로 줄 블록을 다시 앉힐 수 있도록 그리디가 끝날 때까지 결과를 모아 둔다.
	var entries: Array = []
	for raw_cell in cells:
		var cell := raw_cell as Vector2i
		var tile_center := _bs.cell_center(cell)
		var used: Dictionary = {}
		for raw_block in _row_blocks(by_cell[cell] as Array):
			var block: Dictionary = raw_block
			var members: Array = block["pilots"] as Array
			var v: float = float(block["v"])
			var bias: int = _block_seat_bias(members)
			var entry: Dictionary = {"pilots": members, "cell": cell, "center": tile_center,
					"v": v, "cap": int(block["cap"]), "bias": bias, "row": true}
			var seats: Array = _pick_row_seats(tile_center, members.size(), v,
					int(block["cap"]), bias, base_r, placed)
			if seats.is_empty():
				# 줄이 어디에도 안 들어가면 예전 육각 링 배치로 떨어진다.
				entry["row"] = false
				for raw_slot in _pick_block_slots(tile_center, 3 if v > 0.0 else 0,
						bias, members.size(), base_r, used, placed):
					var slot: int = int(raw_slot)
					used[slot] = true
					seats.append({"vec": _slot_offset(slot, base_r),
							"ring": floori(float(slot) / 6.0), "row": -1})
			for raw_seat in seats:
				placed.append(tile_center + ((raw_seat as Dictionary)["vec"] as Vector2))
			entry["seats"] = seats
			entries.append(entry)
	_repair_arrow_overlaps(entries, base_r)
	# 가로 줄 하나마다 붙는 번호 — `_pilot_spread` 가 같은 줄을 한 배율로 벌린다.
	var next_grp: int = 0
	for raw_entry in entries:
		var entry: Dictionary = raw_entry
		var members: Array = entry["pilots"] as Array
		var seats: Array = entry["seats"] as Array
		var grp_of_row: Dictionary = {}
		for i in range(members.size()):
			var seat: Dictionary = seats[i]
			var grp: int = -1
			var row_i: int = int(seat["row"])
			if row_i >= 0:
				if not grp_of_row.has(row_i):
					grp_of_row[row_i] = next_grp
					next_grp += 1
				grp = int(grp_of_row[row_i])
			out[members[i]] = {"cell": entry["cell"], "vec": seat["vec"] as Vector2,
					"ring": int(seat["ring"]), "grp": grp}
	return out


## **초상이 남의 꼬리를 덮으면 그 초상이 비켜 앉는다.** 그리디는 초상끼리의 겹침만
## 보므로, 위아래로 붙은 두 칸에서 먼저 앉은 쪽(위 칸 아군의 S)을 피해 뒤에 온
## 쪽(아래 칸 적)이 옆으로 비켜 앉으면 그 꼬리가 대각선으로 먼저 앉은 초상 밑을
## 지나간다 — 꼬리가 가려져 적이 어느 칸에 있는지가 사라진다.
##
## 그래서 그리디가 끝난 뒤 블록을 배정 순서대로 한 번 훑으며, 구성원 중 하나라도
## **다른 블록의 꼬리**에 닿은 가로 줄 블록을 `strict` 판정(초상 ↔ 초상, 초상 ↔
## 꼬리, 내 꼬리 ↔ 남의 초상)으로 다시 앉힌다. 깨끗한 자리가 없으면 그대로 둔다.
## 다시 앉은 블록은 다른 누구의 꼬리 · 초상과도 닿지 않으므로 새 겹침을 만들지
## 않는다. 같은 블록 안(뒷줄 꼬리가 앞줄 밑을 지나는 것)은 보지 않는다.
##
## **보정은 옆으로만 옮긴다 — 원래 줄보다 바깥으로는 나가지 않는다.** 꼬리 옆면이
## 이웃 초상 테두리에 몇 px 덮이는 것보다, 깨끗한 자리를 찾아 두세 줄 바깥으로
## 날아가 꼬리가 화면 끝까지 늘어나는 쪽이 훨씬 나쁘다. 예전에는 줄 제한이
## 없어서, 양옆 2차 타워보다 반 줄 낮은 중앙 2차 타워의 초상이 양옆 꼬리에 살짝
## 닿는다는 이유만으로 ring 2(타일에서 지름 × 3)까지 밀려났다.
func _repair_arrow_overlaps(entries: Array, r: float) -> void:
	PilotMarker.repair_arrow_overlaps(entries, r)


## 블록의 초상 중심과 꼬리 외곽 다각형(강조 이전, 배율 1)을 두 배열에 덧붙인다.
func _collect_block_shapes(e: Dictionary, r: float, discs: Array, arrows: Array) -> void:
	PilotMarker.collect_block_shapes(e, r, discs, arrows)


func _disc_hits_arrows(pos: Vector2, outer: float, arrows: Array) -> bool:
	return PilotMarker.disc_hits_arrows(pos, outer, arrows)


## 점에서 볼록 다각형까지의 거리 — 안에 있으면 0.
func _point_polygon_distance(pt: Vector2, poly: PackedVector2Array) -> float:
	return PilotMarker.point_polygon_distance(pt, poly)


## 한 칸의 블록을 **가로 줄 배치 단위**로 나눈다. 각 항목은
## `{"pilots": Array, "v": +1(타일 아래) / -1(타일 위), "cap": 한 줄 정원}`.
##
## 모든 칸이 같다: 팀0 = 아래, 팀1 = 위, 한 줄 3명(넘치면 다음 줄). 예전의 **아군
## 홈 구역 예외**(아군 HQ 와 거기 붙은 아군 포탑 칸에서는 아군도 위로 올리던
## `_is_home_zone` / `HOME_TOP_CAP`)는 삭제됐다 — 아군은 HQ 에서도 아래가 우선이다.
func _row_blocks(pilots: Array) -> Array:
	var out: Array = []
	for raw in _slot_blocks(pilots):
		var b: Dictionary = raw
		out.append({"pilots": b["pilots"], "v": 1.0 if int(b["dir"]) == 3 else -1.0,
				"cap": ROW_CAP})
	return out


## 블록 `n` 명이 앉을 **가로 줄** 자리들(구성원 순서 = 왼쪽부터). 각 항목은
## `{"vec": 타일 중심에서의 변위, "ring": 타일에서 몇 번째 줄인가, "row": 블록 안 줄 번호}`.
##
## 줄은 `cap` 명씩 끊는다(보통 3 → 4명이면 3+1, 5명이면 3+2). 첫 줄이 타일에서
## `지름 + 여백`(= 육각 링 0번 반지름) 만큼 떨어진 곳에 가운데 정렬로 서고, 다음
## 줄은 그만큼 더 바깥이다. 이웃 칸 마커와 겹치면 (1) **줄째 좌우로 반 칸씩** 밀어
## 보고(레인 쏠림 쪽 먼저, `_block_seat_bias`), (2) 그래도 막히면 **한 줄 더
## 바깥**에서 같은 순서로 다시 본다. `SLOT_RINGS` 줄을 다 봐도 막히면 빈 배열 —
## 호출자가 육각 링 배치(`_pick_block_slots`)로 떨어진다.
##
## `strict` 이면 꼬리까지 본다(`_seat_crosses_arrows`) — 꼬리 겹침 보정
## (`_repair_arrow_overlaps`)이 다시 앉힐 때만 쓴다. `ring_limit` 은 볼 바깥 줄
## 수의 상한이다 — 보정은 원래 줄까지만 본다.
func _pick_row_seats(tile_center: Vector2, n: int, v: float, cap: int, bias: int,
		r: float, placed: Array, arrows: Array = [], strict: bool = false,
		ring_limit: int = SLOT_RINGS) -> Array:
	return PilotMarker.pick_row_seats(tile_center, n, v, cap, bias, r, placed, arrows,
			strict, ring_limit)


## 이 자리의 초상이 남의 꼬리에 닿거나, 이 자리에서 뻗을 꼬리가 남의 초상에
## 닿는가. 초상은 HP 링 · 외곽선까지 친 바깥 반지름으로 잰다.
func _seat_crosses_arrows(tile_center: Vector2, vec: Vector2, r: float,
		placed: Array, arrows: Array) -> bool:
	return PilotMarker.seat_crosses_arrows(tile_center, vec, r, placed, arrows)


## 한 칸의 파일럿을 **기본 방향이 같은 블록**으로 묶는다. 블록은 한 덩어리로
## 자리를 받는 단위다 — 구성원은 자리표 위의 연속된 창에 왼쪽부터 순서대로
## 앉으므로(`_pick_block_slots`), 창이 어디로 밀려도 좌우 순서가 유지된다.
##
## 블록 순서는 **첫 등장 순**(= `_bs.pilots` 스폰 순서)이라 프레임마다 흔들리지
## 않는다. 기본 방향은 팀이 정하므로(팀0 S / 팀1 N) **한 칸의 블록은 최대 둘**,
## 곧 팀별로 하나씩이다 — 같은 팀은 언제나 한 덩어리로 나란히 앉는다.
func _slot_blocks(pilots: Array) -> Array:
	var order: Array = []
	var by_dir: Dictionary = {}
	for raw in pilots:
		var p := raw as PilotData
		var d: int = pilot_display_dir_index(p)
		if not by_dir.has(d):
			by_dir[d] = []
			order.append(d)
		(by_dir[d] as Array).append(p)
	var out: Array = []
	for d in order:
		out.append({"dir": int(d), "pilots": by_dir[d] as Array})
	return out


## 블록 `n` 명이 앉을 슬롯들(**자리표 왼쪽부터** 순서대로). 블록은 자리표
## (`SEAT_ROW_*`)의 **연속된 `n` 칸 = 창(window)** 을 통째로 차지한다. 그 창이
## 막혀 있으면 **창을 통째로 한 칸 옆으로 밀어** 다시 본다 — 그래서 나란히 선
## A·B 는 왼쪽이 막히면 **둘 다 오른쪽으로**, 오른쪽이 막히면 **둘 다 왼쪽으로**
## 비켜 앉고, 좌우 순서가 뒤집히지 않는다.
##
## 창 후보의 순서는 `_seat_windows`(자기 절반을 지키는 창 → 기본 방향에 가까운 창
## → 왼쪽 창)이고, 한 링의 창이 전부 막히면 **블록째** 바깥 링으로 나간다 — 링
## 경계에서 갈라져 두 겹에 걸쳐 앉지 않게 하기 위함이다.
##
## **예전에는 우선순위 순으로 빈자리를 하나씩 주웠다.** 막힌 자리를 건너뛰기만
## 하므로 블록이 끊기는 것은 물론, A 의 자리만 막히면 A 가 B 를 뛰어넘어 반대쪽
## 끝에 앉아 두 얼굴의 좌우가 뒤바뀌었다(그 앞은 각도 기준 시계방향 회전이었고,
## 그것은 아래 진영을 타일 위로 끌고 갔다 — `SEAT_ROW_DOWN` 주석).
##
## 세 링의 창이 다 막히거나 `n` 이 자리표보다 크면 한 명씩 따로 찾기(`_pick_slot`)로
## 떨어진다 — 나란히 서는 것보다 그려지는 것이 먼저다.
func _pick_block_slots(tile_center: Vector2, base_dir: int, bias: int, n: int,
		r: float, used: Dictionary, placed: Array) -> Array:
	var row: Array = _seat_row(base_dir)
	if n <= row.size():
		for ring in range(SLOT_RINGS):
			for raw_win in _seat_windows(n, bias):
				var start: int = int(raw_win)
				var cand: Array = []
				var ok: bool = true
				for k in range(n):
					var slot: int = ring * 6 + int(row[start + k])
					if used.has(slot) \
							or _slot_collides(tile_center + _slot_offset(slot, r), r, placed):
						ok = false
						break
					cand.append(slot)
				if ok:
					return cand
	var fallback: Array = []
	var local_used: Dictionary = used.duplicate()
	var local_placed: Array = placed.duplicate()
	for _k in range(n):
		var slot: int = _pick_slot(tile_center, base_dir, bias, r, local_used, local_placed)
		local_used[slot] = true
		local_placed.append(tile_center + _slot_offset(slot, r))
		fallback.append(slot)
	return fallback


## 이 블록이 자리표에서 **어느 쪽으로 쏠려 앉는가**: 오른쪽 +1 / 왼쪽 -1 / 없음 0.
##
## 기본 방향(= 팀)만으로는 좌우가 안 갈린다 — 자리표의 동률은 언제나 왼쪽 창이
## 가져갔고, 그래서 **모든 블록이 왼쪽으로 쏠렸다**. 우측 레인은 서포터 + 스나이퍼
## 둘이 한 칸에 서는 일이 잦은데, 그 2인 창이 왼쪽(팀0 이면 `SW S`)에 앉는 바람에
## 왼쪽 이웃 칸을 지나는 정글러 마커와 부딪혀 블록이 통째로 밀려나곤 했다 —
## 화면에서는 두 초상화가 이유 없이 돌아 앉는 것으로 보인다.
##
## 그래서 **레인이 곧 쏠리는 방향**이다: 우측 레인은 오른쪽(팀0 `S SE` / 팀1
## `N NE`), 좌측 레인은 왼쪽(`S SW` / `N NW`), 가운데 레인과 정글러는 쏠림 없음.
## 레인이 서로 다른 파일럿이 한 블록에 섞이면(같은 팀 정글러 + 라이너처럼)
## 방향을 정할 근거가 없으므로 0 으로 떨어진다.
##
## 쏠림은 **동률을 가르는 자리에만** 들어간다(`_compare_seat_windows`) — 자기
## 절반을 지키는 것도, 기본 방향에서 덜 비켜나는 것도 여전히 먼저다. 그래서
## 혼자 선 파일럿은 레인과 무관하게 한가운데(팀0 `S`)에 앉고, 그 자리가 막혔을
## 때 어느 쪽으로 비켜 앉는지만 레인이 정한다.
func _block_seat_bias(members: Array) -> int:
	var bias: int = 0
	for raw in members:
		var b: int = _lane_seat_bias((raw as PilotData).lane)
		if b == 0 or (bias != 0 and b != bias):
			return 0
		bias = b
	return bias


func _lane_seat_bias(lane: int) -> int:
	match lane:
		GameEnums.LanePosition.RIGHT: return 1
		GameEnums.LanePosition.LEFT:  return -1
		_:                            return 0


## 이 기본 방향(= 팀)의 자리표. 팀0 은 타일 아래를, 팀1 은 타일 위를 지난다.
func _seat_row(base_dir: int) -> Array:
	return SEAT_ROW_UP if base_dir == 0 else SEAT_ROW_DOWN


## `n` 명짜리 블록이 앉을 **창의 시작 칸** 후보를 좋은 순서대로. 창은 자리표의
## 연속된 `n` 칸이므로 어느 창을 골라도 구성원의 좌우 순서는 그대로다.
##
## 순서를 매기는 기준은 셋이다:
## 1. **자기 절반(가운데 세 자리)을 벗어난 인원이 적을수록** — 아래 진영이 타일
##    위에 앉는 것보다 나쁜 것은 없다.
## 2. **창의 중심이 기본 방향에 가까울수록** — 같은 조건이면 한가운데에서 덜
##    비켜난 쪽. 이것이 "한 칸씩 미끄러진다"를 만드는 항이다.
## 3. **블록이 쏠리는 쪽 창일수록**(`bias`) — 우측 레인이면 오른쪽 창, 좌측 레인
##    이면 왼쪽 창. 쏠림이 없는 블록(가운데 레인 · 정글러)은 예전처럼 왼쪽 창이
##    남은 동률을 가져간다. 자세한 이유는 `_block_seat_bias`.
func _seat_windows(n: int, bias: int = 0) -> Array:
	var scored: Array = []
	for start in range(0, 7 - n):
		var off: int = 0
		for k in range(n):
			var seat: int = start + k
			if seat < SEAT_HALF_MIN or seat > SEAT_HALF_MAX:
				off += 1
		var center: float = float(start) + float(n - 1) * 0.5
		scored.append({"start": start, "off": off, "d": absf(center - float(SEAT_BASE))})
	scored.sort_custom(_compare_seat_windows.bind(bias))
	var out: Array = []
	for raw in scored:
		out.append(int((raw as Dictionary)["start"]))
	return out


func _compare_seat_windows(a: Dictionary, b: Dictionary, bias: int) -> bool:
	if int(a["off"]) != int(b["off"]):
		return int(a["off"]) < int(b["off"])
	if not is_equal_approx(float(a["d"]), float(b["d"])):
		return float(a["d"]) < float(b["d"])
	if bias > 0:
		return int(a["start"]) > int(b["start"])
	return int(a["start"]) < int(b["start"])


# 지금 프레임의 마커 좌표 표. 글라이드가 낸 **중심 + 슬롯 벡터**에 파일럿별 강조
# 배율(`_pilot_spread`)을 곱하고 화면 밖으로 나간 벌어진 마커들을 통째로 밀어 넣는다.
#
# 배율을 타일 중심이 아니라 **글라이드 중심**에 걸어야 한다는 것이 요점이다 —
# 칸을 건너는 중인 파일럿을 도착 타일 기준으로 부풀리면 아직 도착하지도 않은
# 지점을 축으로 튕겨 나간다.
func _compose_positions(solution: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var by_cell: Dictionary = {}
	for raw in solution.keys():
		var cell := (solution[raw] as Dictionary)["cell"] as Vector2i
		if not by_cell.has(cell):
			by_cell[cell] = []
		(by_cell[cell] as Array).append(raw)
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	for raw_cell in by_cell.keys():
		var pilots: Array = by_cell[raw_cell] as Array
		var spread: Dictionary = _pilot_spread(pilots, solution)
		# 벌어진(배율 > 1) 마커만 한 덩어리로 화면 안에 밀어 넣는다 — 제자리인
		# 마커까지 같이 밀면 대상이 아닌 적 초상이 함께 끌려간다.
		var moved: Array = []
		var moved_pos: Array = []
		var max_em: float = 1.0
		for raw in pilots:
			var g: Dictionary = _glide[raw]
			var em: float = float(spread[raw])
			var pos: Vector2 = (g["center"] as Vector2) + (g["vec"] as Vector2) * em
			if em > 1.0:
				moved.append(raw)
				moved_pos.append(pos)
				max_em = maxf(max_em, em)
			else:
				out[raw] = pos
		moved_pos = _clamp_group_on_screen(moved_pos, base_r * max_em)
		for i in range(moved.size()):
			out[moved[i]] = moved_pos[i] as Vector2
	return out


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


# ─── 마커 글라이드 ───────────────────────────────────────────────────────────

## 목표(칸 + 슬롯)가 바뀐 파일럿에게 새 보간을 띄운다. **시간은 여기서 흐르지
## 않는다** — 미는 것은 `_advance_glide` 하나뿐이라, 한 프레임에 이 함수가 몇 번
## 불려도(그리기 · 히트 테스트 · 팝업) 연출이 되감기지 않는다.
func _sync_glide(solution: Dictionary) -> void:
	for raw in solution.keys():
		var p := raw as PilotData
		var e: Dictionary = solution[p]
		var cell := e["cell"] as Vector2i
		var center := _bs.cell_center(cell)
		var vec: Vector2 = e["vec"] as Vector2
		if not _glide.has(p):
			_glide[p] = _settled_glide(cell, center, vec)
			continue
		var g: Dictionary = _glide[p]
		if (g["cell"] as Vector2i) == cell and (g["to_vec"] as Vector2).is_equal_approx(vec):
			continue
		# 순간이동이 **맞는** 경우 — 복귀 / 부활은 페이드가 자리 이동을 덮고,
		# 시신은 쓰러진 칸에 붙박여 있어야 한다. 미끄러뜨리면 사라지는 몸이
		# 화면을 가로지른다.
		if p.anim_recall_phase != 0 or p.anim_death_phase != 0:
			_glide[p] = _settled_glide(cell, center, vec)
			continue
		var from_center: Vector2 = g["center"] as Vector2
		var from_vec: Vector2 = g["vec"] as Vector2
		var path := PackedVector2Array()
		if (g["cell"] as Vector2i) != cell:
			path = _screen_path(p, cell)
		if path.is_empty():
			path.append(center)
		# 출발점은 **지금 실제로 그려지고 있는 중심**이다 — 이전 글라이드가 아직
		# 안 끝났으면 기록된 출발 칸으로 되감기는 대신 그 자리에서 이어 간다.
		# 한 점짜리(= 이번 이동 경로가 없던 순간이동)는 그 점이 **도착점**이므로
		# 덮어쓰지 않고 앞에 붙인다 — 덮으면 마커가 출발 칸에 붙박인다.
		if path.size() < 2:
			path.insert(0, from_center)
		else:
			path[0] = from_center
		# 길이(= 링)가 바뀌는 경우에만 도착 후 정착 구간을 단다.
		var settle: float = 0.0
		if not is_equal_approx(from_vec.length(), vec.length()):
			settle = MARKER_RADIUS_SETTLE_SEC
		var ng: Dictionary = {
			"cell":     cell,
			"path":     path,
			"from_vec": from_vec,
			"to_vec":   vec,
			"t":        0.0,
			"move_dur": _bs.ANIM_MOVE_DUR,
			"total":    _bs.ANIM_MOVE_DUR + settle,
			"center":   from_center,
			"vec":      from_vec,
		}
		_eval_glide(ng)
		_glide[p] = ng
	# 전장을 뜬 파일럿(사망 퇴장, 재시작으로 갈린 로스터)의 상태는 버린다.
	for raw in _glide.keys():
		if not solution.has(raw):
			_glide.erase(raw)


## 아무 데도 가지 않는(= 이미 도착해 있는) 상태.
func _settled_glide(cell: Vector2i, center: Vector2, vec: Vector2) -> Dictionary:
	return {
		"cell":     cell,
		"path":     PackedVector2Array([center]),
		"from_vec": vec,
		"to_vec":   vec,
		"t":        0.0,
		"move_dur": _bs.ANIM_MOVE_DUR,
		"total":    0.0,
		"center":   center,
		"vec":      vec,
	}


## `p` 가 이번에 실제로 밟은 칸들의 화면 좌표. `PilotData.anim_move_path` 가
## 도착 칸까지 이어져 있으면 그대로 쓰고(2칸 이동이 꺾여서 간다), 아니면
## 출발 → 도착 두 점짜리 직선으로 떨어진다(카드 순간이동, 밀림 등).
##
## **읽으면서 비운다.** 그래야 같은 프레임의 뒤이은 걸음은 이어 붙고(전진 카드의
## N틱), 다음 턴의 이동은 빈 배열에서 새 경로로 시작한다.
func _screen_path(p: PilotData, to_cell: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cells: Array[Vector2i] = p.anim_move_path
	if cells.size() >= 2 and cells[cells.size() - 1] == to_cell:
		for c in cells:
			out.append(_bs.cell_center(c))
	p.anim_move_path.clear()
	if out.is_empty():
		out.append(_bs.cell_center(to_cell))
	return out


## 모든 글라이드의 시계를 민다. 아직 움직이는 것이 하나라도 있으면 true.
func _advance_glide(delta: float) -> bool:
	var moving: bool = false
	for raw in _glide.keys():
		var g: Dictionary = _glide[raw]
		var total: float = float(g["total"])
		if float(g["t"]) >= total:
			continue
		g["t"] = minf(float(g["t"]) + delta, total)
		_eval_glide(g)
		moving = true
	return moving


## 지금 시각의 중심 · 슬롯 벡터를 `g` 에 적어 넣는다.
##
## **중심과 각도는 같은 박자, 길이만 뒤에 온다.** 링이 그대로면 길이 보간은
## 항등이라 화살표 길이가 이동 내내 한 픽셀도 변하지 않고(꼬리가 초상에 매달려
## 통째로 미끄러진다), 붐비는 칸으로 들어가 바깥 링으로 밀려날 때만 도착 후
## `MARKER_RADIUS_SETTLE_SEC` 동안 늘어난다.
func _eval_glide(g: Dictionary) -> void:
	var move_dur: float = maxf(0.0001, float(g["move_dur"]))
	var t: float = float(g["t"])
	var te: float = clampf(t / move_dur, 0.0, 1.0)
	# **smoothstep — 양 끝에서 정지한다.** 예전 이동 트윈은 ease-out cubic 이었고
	# (슬롯은 어차피 튀었으니 출발이 급해도 티가 덜 났다) 그 곡선은 60fps 첫
	# 프레임에 이미 거리의 15%(≈25px)를 지나간다 — 순간이동을 없애려는 연출이
	# 출발할 때마다 한 번 튀는 셈이었다. 실측: 첫 프레임 24.98px → 1.1px.
	te = te * te * (3.0 - 2.0 * te)
	g["center"] = _polyline_lerp(g["path"] as PackedVector2Array, te)
	var a: Vector2 = g["from_vec"] as Vector2
	var b: Vector2 = g["to_vec"] as Vector2
	# 각도는 **짧은 쪽으로** 돈다. 끝점을 직선 lerp 하면 두 벡터 사이를 가로지르며
	# 마커가 타일 중심 쪽으로 파고들었다 나와, 회전이 아니라 흔들림으로 읽힌다.
	var ang: float = a.angle() + wrapf(b.angle() - a.angle(), -PI, PI) * te
	var tr: float = 1.0
	if float(g["total"]) > float(g["move_dur"]):
		tr = clampf((t - float(g["move_dur"])) / MARKER_RADIUS_SETTLE_SEC, 0.0, 1.0)
		tr = 1.0 - pow(1.0 - tr, 3.0)
	g["vec"] = Vector2.from_angle(ang) * lerpf(a.length(), b.length(), tr)


## 폴리라인 위를 **호 길이 비율**로 훑는다. 구간 개수로 나누면 칸마다 속도가
## 달라지지는 않지만(육각 이웃 간 거리는 모두 같다) 출발점만 바꿔 끼운 경로에서
## 첫 구간이 짧아지므로, 거리로 재는 편이 어느 경우에도 등속이다.
func _polyline_lerp(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or t <= 0.0:
		return pts[0]
	if t >= 1.0:
		return pts[pts.size() - 1]
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total < 0.001:
		return pts[0]
	var want: float = total * t
	var acc: float = 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if acc + seg >= want:
			return pts[i - 1].lerp(pts[i], (want - acc) / maxf(0.0001, seg))
		acc += seg
	return pts[pts.size() - 1]


## 이 파일럿의 말풍선 꼬리가 가리킬 점 — 글라이드 중인 **타일 중심**이다. 이동
## 중에는 아직 출발 칸 근처에 있으므로, 꼬리가 도착 칸을 먼저 가리키며 늘어나는
## 일이 없다(초상과 함께 미끄러진다).
func _marker_center(p: PilotData) -> Vector2:
	if _glide.has(p):
		return (_glide[p] as Dictionary)["center"] as Vector2
	return _bs.cell_center(_render_cell(p))


func _draw_hq_hp_bars() -> void:
	var enemy_locked  := not _bs.sim_core.any_t2_destroyed(1)
	var player_locked := not _bs.sim_core.any_t2_destroyed(0)
	if not player_locked:
		_draw_hq_hp_bar(_bs.PLAYER_HQ_POS, _bs.player_hq_hp)
	if not enemy_locked:
		_draw_hq_hp_bar(_bs.ENEMY_HQ_POS, _bs.enemy_hq_hp)


func _draw_hq_hp_bar(pos: Vector2i, hp: int) -> void:
	var center := _bs.cell_center(pos)
	var s: float = HexGrid.DISPLAY_SCALE
	var bw := 60.0 * s; var bh := 8.0 * s
	var bx := center.x - bw * 0.5; var by_ := center.y + 16.0 * s
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(bx, by_, bw * float(hp) / float(_bs.HQ_MAX_HP), bh), Color(0.2, 0.9, 0.2))


func _draw_turret_hp_bars() -> void:
	for t in _bs.turrets:
		_draw_turret_hp_bar(t as TurretData)


func _draw_turret_hp_bar(td: TurretData) -> void:
	if not td.alive:
		return
	if td.tier == 2 and _bs.sim_core.t1_alive_in_lane(td.team, td.lane):
		return
	# 피격 중에는 HP 바도 스프라이트와 **같은 오프셋**으로 흔들린다 — 둘이
	# 어긋나면 바만 제자리에 붙어 있어 연출이 겉돈다.
	var center := _bs.cell_center(td.grid_pos) + _bs.turret_hit_offset(td)
	var hg: HexGrid = _bs.hex_grid
	var bw: float = hg.hex_size * 1.1; var bh: float = 6.0 * HexGrid.DISPLAY_SCALE
	var bx: float = center.x - bw * 0.5; var by_: float = center.y - hg.hex_height * 0.38
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(bx, by_, bw * float(td.hp) / float(td.max_hp), bh),
			Color(0.92, 0.68, 0.1))


# ─── Pilot rendering ─────────────────────────────────────────────────────────
# 초상화는 언제나 타일 **바깥**에 앉고, 뒤에서 타일 중심을 가리키는 팀 색 삼각형
# (말풍선 꼬리)이 어느 칸 이야기인지를 말한다. 앉을 자리는 타일을 둘러싼 육각
# 6슬롯이고, 그 중 어느 슬롯을 고르는지는 아래 두 절이 정한다.

# Pilot dimensions track HexGrid.DISPLAY_SCALE so they stay proportional to
# tile size. Base values are calibrated against the unscaled (1.0x) hex.
const PILOT_RADIUS_BASE := 31.5

## 마커(초상 + HP 링 + 꼬리)의 외곽 — 전부 px, 강조 배율은 타지 않는다.
## HP 링 두께와 초상 가장자리에서 링까지의 틈.
const HP_RING_W = PilotMarker.HP_RING_W
const HP_RING_GAP = PilotMarker.HP_RING_GAP
## 굵은 검은 외곽선 — HP 링 바깥과 화살표 둘레가 **같은 두께**를 쓴다.
const MARKER_OUTLINE_W = PilotMarker.MARKER_OUTLINE_W
## HP 링 25 단위 구분선 — 외곽선 두께의 절반.
const HP_TICK_W = PilotMarker.HP_TICK_W
## 마커 팀색(HP 링 · 꼬리) — 교전 무대 초상의 HP 링도 이 색을 쓴다.
const TEAM_RING_COLORS = PilotMarker.TEAM_RING_COLORS
## HP 링 구분선 간격(HP).
const HP_TICK_STEP = PilotMarker.HP_TICK_STEP
## 보호막 — HP 링 위에 **추가 체력처럼** 이어 붙는 밝은 회색 구간.
const SHIELD_RING_COLOR = PilotMarker.SHIELD_RING_COLOR
## 화살표 폭 배율 — 예전 폭(`clamp(반지름 × 0.9, 10, 18)`)의 90%.
const ARROW_WIDTH_SCALE = PilotMarker.ARROW_WIDTH_SCALE
## 뾰족한 외곽선 끝이 채움 끝보다 앞으로 나가는 최대 거리(px).
const ARROW_TIP_MITER_MAX = PilotMarker.ARROW_TIP_MITER_MAX
## 초상 + 화살표 아래로 떨어지는 그림자.
const MARKER_SHADOW_OFFSET = PilotMarker.MARKER_SHADOW_OFFSET
const MARKER_SHADOW_COLOR = PilotMarker.MARKER_SHADOW_COLOR

## 초상화가 앉을 수 있는 6방향 — 육각 이웃과 정확히 같은 방향이고, 배열 순서가
## **시계방향**(화면 기준 y 아래)이다.
## 인덱스: 0=N 1=NE 2=SE 3=S 4=SW 5=NW.
const HEX_DIRS: Array[Vector2] = [
	Vector2( 0.0,       -1.0),   # N
	Vector2( 0.8660254, -0.5),   # NE
	Vector2( 0.8660254,  0.5),   # SE
	Vector2( 0.0,        1.0),   # S
	Vector2(-0.8660254,  0.5),   # SW
	Vector2(-0.8660254, -0.5),   # NW
]

## 한 링의 여섯 자리를 **왼쪽에서 오른쪽으로** 늘어놓은 자리표(HEX_DIRS 인덱스).
## 가운데 세 자리(인덱스 1·2·3)가 그 팀의 **절반**이고, 한가운데(`SEAT_BASE` = 2)가
## 기본 방향이다. 팀0 은 타일 **아래**를, 팀1 은 타일 **위**를 지나며 왼쪽에서
## 오른쪽으로 훑는 순서다:
##
##     팀0(아래 진영)   NW   SW  [S]  SE   NE   N
##     팀1(위 진영)     SW   NW  [N]  NE   SE   S
##
## 두 표 모두 육각 링을 한 방향으로 감은 것이라(팀0 은 반시계, 팀1 은 시계),
## **자리표에서 연속인 칸은 링에서도 연속인 자리**다 — 블록이 창(window) 하나로
## 앉으면 화면에서도 끊김 없이 나란히 선다.
##
## 링을 좌우가 아니라 **각도**로 도는 방식(기본 방향에서 시계방향 회전, 또는
## 좌우 번갈아 벌리기)은 전부 삭제됐다. 그 순서로는 자리가 하나 막혔을 때 블록의
## 한 명만 반대편으로 건너뛰어, 비켜 앉은 것이 아니라 **자리를 맞바꾼 것**으로
## 읽혔다 — 지금은 블록이 통째로 한 칸 미끄러진다(`_pick_block_slots`).
const SEAT_ROW_DOWN: Array[int] = [5, 4, 3, 2, 1, 0]   # 팀0: NW SW [S] SE NE N
const SEAT_ROW_UP:   Array[int] = [4, 5, 0, 1, 2, 3]   # 팀1: SW NW [N] NE SE S

## 자리표에서 기본 방향이 앉는 칸. 좌우 각 2칸이 여기서 뻗어 나간다.
const SEAT_BASE := 2

## 자리표에서 **자기 절반**인 구간(둘 다 포함). 이 밖은 위/아래가 뒤집히는 자리라
## 창을 고를 때 감점된다.
const SEAT_HALF_MIN := 1
const SEAT_HALF_MAX := 3

## 초상화 사이에 남기는 최소 여백(px). 링 반지름과 충돌 판정이 같은 값에서
## 나오므로 둘이 어긋날 수 없다.
const MARKER_GAP = PilotMarker.MARKER_GAP

## 몇 겹까지 링을 만들 것인가. 한 링이 6자리이므로 3겹 = 18자리 — 5v5 전원이 한
## 칸에 몰려도(10명) 남는다. 이 위로는 겹치더라도 자리를 준다.
const SLOT_RINGS = PilotMarker.SLOT_RINGS

## 가로 줄 배치(`_pick_row_seats`)에서 보통 칸의 한 줄 정원. 넷부터는 다음 줄.
const ROW_CAP = PilotMarker.ROW_CAP



# PilotData → 슬롯 벡터에 곱할 배율. **파일럿마다 다르다**: 자기 강조 배율과
# 같은 칸 **안쪽 링**에 앉은 파일럿들의 강조 배율 중 큰 값이다.
#
# 예전에는 칸 전원(양 팀)에 그 칸의 최대 배율을 곱했다 — 아군만 대상인 카드를
# 들어도 같은 칸 적 초상(기본 자리 N)이 크기는 그대로인 채 위로 밀려났다.
#
# 같은 링 이웃끼리는 겹치지 않는다: 60° 간격이라 한쪽만 1.5배여도 중심 거리가
# √(1.5² + 1 − 1.5)·d ≈ 1.32d 이고, 필요한 거리는 (1.5r + r) ≈ 1.2d 다
# (d = 링 반지름 = 2r + MARKER_GAP). 반면 **안쪽 링이 커지면 바깥 링을 덮는다**
# (같은 방향이면 1.5d 와 2d 사이가 0.5d 뿐) — 그래서 바깥 링은 안쪽의 배율을
# 물려받아 함께 밀려난다.
#
# **가로 줄은 줄째 같은 배율이다**(`"grp"` 이 같은 파일럿끼리). 줄 이웃은 60°
# 링이 아니라 수평으로 d 간격이라, 한 명만 1.5배로 밀면 옆 사람과 ≈101px 로
# 붙어(필요 ≈106px) 얼굴이 살짝 겹친다 — 줄 전체를 같이 벌리면 간격도 1.5배다.
func _pilot_spread(pilots: Array, solution: Dictionary) -> Dictionary:
	var ring_of: Dictionary = {}
	var grp_of: Dictionary = {}
	for raw in pilots:
		var e: Dictionary = solution[raw]
		ring_of[raw] = int(e["ring"])
		grp_of[raw] = int(e["grp"])
	var out: Dictionary = {}
	for raw in pilots:
		var em: float = _pilot_emphasis_scale(raw as PilotData)
		var ring: int = int(ring_of[raw])
		var grp: int = int(grp_of[raw])
		for other in pilots:
			if int(ring_of[other]) < ring \
					or (grp >= 0 and int(grp_of[other]) == grp):
				em = maxf(em, _pilot_emphasis_scale(other as PilotData))
		out[raw] = em
	return out


## 링 `ring`(0부터)의 반지름. **이웃 슬롯이 60° 간격이므로 반지름 d 인 링에서
## 이웃 슬롯 사이 거리는 정확히 d 다** — 그래서 지름 + 여백을 그대로 반지름으로
## 쓰면 한 링 안의 초상화가 서로 닿지 않는다. 바깥 링은 그 배수라 반지름 방향
## 으로도 같은 간격이 확보된다.
func _ring_radius(ring: int, r: float) -> float:
	return (r * 2.0 + MARKER_GAP) * float(ring + 1)


## 슬롯 번호(= ring * 6 + 방향 인덱스) → 타일 중심에서의 변위.
func _slot_offset(slot: int, r: float) -> Vector2:
	@warning_ignore("integer_division")
	var ring: int = slot / 6
	return HEX_DIRS[slot % 6] * _ring_radius(ring, r)


## 이 파일럿이 앉을 슬롯. 혼자 앉는 것은 **1인짜리 창**이므로 블록과 같은 표를
## 쓴다 — `_seat_windows(1, bias)` 가 자리표를 기본 방향부터 좌우로 번갈아 훑는
## 순서를 돌려준다(팀0 · 쏠림 없음이면 S → SW → SE → NW → NE → N, 우측 레인이면
## 좌우가 뒤집혀 S → SE → SW → NE → NW → N). 거기서 (1) 같은 칸에서 아직 안 쓴
## 자리이고 (2) 이미 놓인 어떤 마커와도 겹치지 않는 첫 자리를 잡는다. 안쪽 링 6자리를
## 다 돌면 그대로 바깥 링으로 나간다 — 그만큼 타일에서 멀어지고 화살표가 길어져,
## 붐비는 칸일수록 "어느 타일인지"가 화살표로 읽힌다.
##
## 겹침 판정이 **다른 칸의 마커까지** 본다는 것이 요점이다: 위아래로 붙은 두 칸이
## 서로를 향한 슬롯(위 칸의 S, 아래 칸의 N)을 고르면 초상화 두 개가 그 사이에서
## 정면으로 겹치는데, 이것이 전장에서 얼굴이 가려지는 유일한 구조적 원인이었다.
## 그 자리를 피해 **어디로 비켜 앉는가**를 정하는 것이 위 순서다.
func _pick_slot(tile_center: Vector2, base_dir: int, bias: int, r: float,
		used: Dictionary, placed: Array) -> int:
	var row: Array = _seat_row(base_dir)
	var seats: Array = _seat_windows(1, bias)
	for ring in range(SLOT_RINGS):
		for raw_seat in seats:
			var slot: int = ring * 6 + int(row[int(raw_seat)])
			if used.has(slot):
				continue
			if _slot_collides(tile_center + _slot_offset(slot, r), r, placed):
				continue
			return slot
	# 사방이 막혔으면 겹치더라도 빈 슬롯을 준다 — 그리지 않는 것보다 낫다.
	for ring in range(SLOT_RINGS):
		for raw_seat in seats:
			var slot: int = ring * 6 + int(row[int(raw_seat)])
			if not used.has(slot):
				return slot
	return base_dir


func _slot_collides(pos: Vector2, r: float, placed: Array) -> bool:
	return PilotMarker.slot_collides(pos, r, placed)


# ─── 초상화가 앉는 기본 방향 ─────────────────────────────────────────────────
# **팀이 정한다** — 아래 진영(팀0)은 타일 아래(S), 위 진영(팀1)은 타일 위(N).
# 화면에서 자기 HQ 가 있는 쪽이 곧 자기 자리라, 어느 칸을 보든 아래줄이 내 팀이고
# 윗줄이 상대 팀이다. 여기서 겹치는 경우는 배정 쪽이 자리표(`SEAT_ROW_*`)를
# **좌우로 미끄러뜨려** 푼다(`_pick_block_slots` / `_pick_slot`) — 기본 방향은
# 자리표 한가운데이고, 그 **절반**(팀0 이면 아래 SW·S·SE, 팀1 이면 위 NW·N·NE)이
# 다 막히기 전에는 반대쪽으로 넘어가지 않는다.
#
# **삭제된 것 — 이동 방향 기반 배치.** 예전에는 "가려는 쪽을 비우고 지나온 쪽에
# 선다"며 레인 파일럿은 다음 웨이포인트 방향의 반대, 정글러는 `prev_grid_pos` 에서
# 온 방향의 반대에 앉혔다(`_pilot_travel_dir` / `_peek_waypoint` /
# `_nearest_dir_index`, 커밋 64bec06). 같은 레인 같은 구간이면 정렬은 맞았지만
# **같은 팀이 구간마다 다른 쪽에 앉아**(1차 포탑 전 왼쪽 아래 → 그 뒤 아래 →
# 적 포탑 뒤 오른쪽 아래) 화면에서 팀을 위/아래로 읽는 기준이 사라졌다.
# 되살리지 말 것. `PilotData.prev_grid_pos` 도 그때 함께 삭제됐다.

## `p` 의 기본 슬롯 방향(HEX_DIRS 인덱스). 공개 — BattleSim 의 대체 좌표 계산이
## 같은 답을 써야 한다.
func pilot_display_dir_index(p: PilotData) -> int:
	return 3 if p.team == 0 else 0   # 팀0 = S(아래), 팀1 = N(위)


# 무리 **전체를 통째로 밀어** 화면 안에 넣는다.
#
# 강조로 벌어진 가장자리 레인의 2~3인 무리는 그대로 두면 화면 밖으로 잘려 나가는
# 데, 잘린 얼굴은 볼 수도 누를 수도 놓을 수도 없다. 마커를 하나씩 따로 밀면
# 애써 벌려 놓은 간격이 도로 무너져 다시 겹치므로 **평행 이동**이어야 한다.
# 화살표는 여전히 각자 자기 타일을 가리키므로 누가 어느 칸에 있는지는 유지된다.
# 무리가 화면보다 넓은 극단에서는 왼쪽/위쪽 가장자리에 붙인다.
func _clamp_group_on_screen(positions: Array, draw_r: float) -> Array:
	if positions.is_empty():
		return positions
	var vp: Vector2 = get_viewport_rect().size
	var pad: float = draw_r + SCREEN_EDGE_PAD
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for raw in positions:
		var v := raw as Vector2
		min_p = Vector2(minf(min_p.x, v.x), minf(min_p.y, v.y))
		max_p = Vector2(maxf(max_p.x, v.x), maxf(max_p.y, v.y))
	var shift := Vector2.ZERO
	if max_p.x + pad > vp.x:
		shift.x = vp.x - pad - max_p.x
	if min_p.x + shift.x - pad < 0.0:
		shift.x = pad - min_p.x
	if max_p.y + pad > vp.y:
		shift.y = vp.y - pad - max_p.y
	if min_p.y + shift.y - pad < 0.0:
		shift.y = pad - min_p.y
	if shift == Vector2.ZERO:
		return positions
	var out: Array = []
	for raw in positions:
		out.append((raw as Vector2) + shift)
	return out


# 마커 색 — 쓰러진 파일럿은 팀 색까지 함께 죽여 딤드로 읽히게 한다. 초상 자체의
# 딤은 _draw_pilot_circle 이 같은 배율로 건다.
func _marker_color(pilot: PilotData) -> Color:
	var team_color: Color = TEAM_RING_COLORS[1 if pilot.team == 1 else 0]
	if pilot.anim_death_phase != 0:
		return team_color * _bs.ANIM_DEATH_TINT
	return team_color


# 파일럿 한 명의 말풍선 꼬리(화살표). 초상과 따로 그리는 이유는
# `_draw_pilot_groups` — 전장의 모든 꼬리가 모든 초상보다 먼저 깔린다.
func _draw_pilot_tail(pilot: PilotData, radius: float) -> void:
	var anim_off := _pilot_anim_offset(pilot)
	var pos := _pilot_marker_pos(pilot) + anim_off
	# 화살표 배율은 **그 파일럿 자신의** 강조다(무리 전체가 아니라):
	# 한 무리 안에 강조 대상과 아닌 사람이 섞이면 초상 크기가 서로
	# 다르고, 화살표는 자기 초상 바깥에서 시작해야 한다.
	# 끝점은 **글라이드 중인 타일 중심**이다 — 초상이 실제로 미끄러지므로
	# 꼬리도 같은 박자로 따라간다. 링이 그대로면 이동 내내 길이가 한 픽셀도
	# 변하지 않고, 바깥 링으로 밀려날 때만 도착 후에 늘어난다(`_eval_glide`).
	# 정글 시작 선택 동안의 아군 정글러는 **끌리는 물건**이다 — 자리는
	# 오버레이가 정하고(손가락 밑 / 고른 칸 / HQ), 가리킬 타일이 아직 없으니
	# 말풍선 꼬리도 없다.
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp != null and jp.is_active() and pilot == jp.jungler():
		return
	# **연출 오프셋(복귀 · 전사 상승, 피격 흔들림)은 끝점에도 똑같이 얹는다.**
	# 초상만 떠오르고 끝점이 타일에 남으면 꼬리가 상승 거리만큼 늘어났다 —
	# 화살표는 초상에 붙은 채 통째로 따라가고, 타일을 다시 겨누는 것은
	# 턴 이동(글라이드)뿐이다.
	_draw_arrow_to_tile(pos, _marker_center(pilot) + anim_off,
			radius, _marker_color(pilot), _pilot_anim_alpha(pilot),
			_pilot_draw_scale(pilot))


# 파일럿 한 명의 마커 본체 — 초상 · HP 링, 그리고 그 위의 HP 조각.
# 꼬리는 `_draw_pilot_tail` 이 먼저 깔아 둔다.
func _draw_pilot_marker(pilot: PilotData, radius: float) -> void:
	var pos := _pilot_marker_pos(pilot) + _pilot_anim_offset(pilot)
	var alpha := _pilot_anim_alpha(pilot)
	var marker_color := _marker_color(pilot)
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp != null and jp.is_active() and pilot == jp.jungler():
		_draw_pilot_circle(pilot, jp.marker_pos(pos), radius, marker_color, alpha)
		return
	_draw_pilot_circle(pilot, pos, radius, marker_color, alpha)
	_draw_hp_chips(pilot, pos, radius * _pilot_draw_scale(pilot), marker_color, alpha)


# 방금 잃은 HP · 보호막 구간 — 링의 빈자리에서 바깥으로 튀어 나가며 확대 + 페이드(`draw_hp_chip`).
func _draw_hp_chips(pilot: PilotData, pos: Vector2, draw_radius: float,
		color: Color, alpha: float) -> void:
	for raw in _hp_chips:
		var c: Dictionary = raw
		if c["p"] != pilot:
			continue
		var k: float = clampf(float(c["t"]) / HP_CHIP_DUR, 0.0, 1.0)
		for seg in c["segs"]:
			draw_hp_chip(self, pos, draw_radius, seg as Array, color, k, alpha)


## 그림자 가장자리의 흐림 폭(px)과 겹 수. 실루엣을 `-폭/2 … +폭/2` 로 깎고
## 부풀린 겹을 같은 알파로 포개면 안쪽일수록 겹이 많이 쌓여 진하고 바깥으로
## 갈수록 옅어진다 — 셰이더 없이 만드는 그라데이션 테두리다.
const MARKER_SHADOW_BLUR = PilotMarker.MARKER_SHADOW_BLUR
const MARKER_SHADOW_LAYERS = PilotMarker.MARKER_SHADOW_LAYERS

## Marker geometry · drawing · seating live in `PilotMarker` (resources/), shared with the
## team base map; the functions below keep their old names and delegate to it.
## `PilotMarker.ShadowPart`: a lifted portrait lays its tail part (TAIL) with the tails
## and its disc part (DISC) later with itself.

# 초상 + 화살표 실루엣을 합친 한 덩어리를 아래로 밀어 반투명 검정으로 깐다.
# 둘을 따로 깔면 겹친 부분만 두 배로 진해지므로 `merge_polygons` 로 합친다.
# 자리 · 연출 오프셋 · 꼬리 끝점은 `_draw_pilot_marker` 의 본 그리기와 같은 식이다.
# 가장자리는 `MARKER_SHADOW_LAYERS` 겹으로 흐린다 — 한가운데가 겹 전부가 쌓인
# 자리라 그 합이 `MARKER_SHADOW_COLOR.a` 가 되도록 겹 하나의 알파를 역산한다.
func _draw_marker_shadow(pilot: PilotData, radius: float,
		part: PilotMarker.ShadowPart = PilotMarker.ShadowPart.FULL) -> void:
	var anim_off := _pilot_anim_offset(pilot)
	var pos := _pilot_marker_pos(pilot) + anim_off
	var alpha := _pilot_anim_alpha(pilot)
	var em: float = _pilot_draw_scale(pilot)
	var arrow := PackedVector2Array()
	var jp: JungleStartOverlay = _bs.jungle_pick
	if jp != null and jp.is_active() and pilot == jp.jungler():
		pos = jp.marker_pos(pos)
	else:
		arrow = _arrow_outline_polygon(pos, _marker_center(pilot) + anim_off, radius, em)
	PilotMarker.draw_shadow(self, pos, radius * em, arrow, alpha, part)



# ─── Animation helpers ───────────────────────────────────────────────────────

## A pilot is drawn while they are alive **or** while the 전사 연출 (dim → fade
## + rise at the cell they fell on) is still playing. That animation runs after
## `alive` has already flipped to false, which is exactly why this is not a
## plain `p.alive` test — without it a killed pilot vanished on the same frame
## the damage landed. 복귀 연출은 여기 걸릴 일이 없다: 복귀한 파일럿은 전장을
## 뜨지 않으므로 계속 `alive` 다.
func _is_renderable(p: PilotData) -> bool:
	return p.alive or p.anim_death_phase != 0


# Render cell: where this pilot should be drawn this frame. During recall
# phase 1 (fade-out) the pilot still appears at the cell they came from even
# though grid_pos has already been snapped to HQ. During phase 2 (fade-in)
# the pilot is drawn at their HQ even if the sim has already advanced them
# away — phase 2 is the "arrive at HQ" descent and must visually anchor there.
# A pilot playing the 전사 연출 stays on the cell they fell on.
func _render_cell(p: PilotData) -> Vector2i:
	if p.anim_recall_phase == 1:
		return p.anim_recall_orig
	if p.anim_recall_phase == 2:
		return _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	if p.anim_death_phase != 0:
		return p.anim_death_cell
	return p.grid_pos


# Per-pilot pixel offset combining recall rise/descend, 전사 상승, 그리고
# 피격 흔들림. **칸 이동은 여기 없다** — 마커 좌표 자체가 글라이드로 미끄러지므로
# (`_sync_glide` / `_eval_glide`) 여기서 한 번 더 얹으면 두 벌이 된다.
func _pilot_anim_offset(p: PilotData) -> Vector2:
	var off := Vector2.ZERO
	if p.anim_death_phase == 2:
		# 전사 2단계 — 시신이 투명해지며 위로 떠오른다.
		var td: float = clamp(p.anim_death_t / p.anim_death_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_DEATH_RISE_PX * td
		return off
	if p.anim_death_phase == 1:
		return off   # 딤드 대기 중에는 제자리
	if p.anim_recall_phase == 1:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_RECALL_RISE_PX * t
	elif p.anim_recall_phase == 2:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_RECALL_RISE_PX * (1.0 - t)
	if p.anim_shake_dur > 0.0:
		var t: float = clamp(p.anim_shake_t / p.anim_shake_dur, 0.0, 1.0)
		# 진폭은 흔들림을 건 쪽이 정한다(전장 교전 6px / 공격 카드 20px).
		# 0 은 `anim_shake_amp` 가 붙기 전에 만들어진 상태이므로 기본값으로 읽는다.
		var base_amp: float = p.anim_shake_amp
		if base_amp <= 0.0:
			base_amp = _bs.ANIM_SHAKE_AMP_PX
		var amp: float = base_amp * (1.0 - t)
		# **주파수는 고정, 진동 수가 지속시간을 따라간다.** 진동 수를 4회로
		# 고정하면 길게 흔들라는 지시가 "느리게 흔들라"가 되어 격렬함이 사라진다.
		var cycles: float = 4.0 * (p.anim_shake_dur / _bs.ANIM_SHAKE_DUR)
		off.x += sin(t * TAU * cycles) * amp
	return off


func _pilot_anim_alpha(p: PilotData) -> float:
	var alpha: float = 1.0
	if p.anim_death_phase == 1:
		return 1.0
	if p.anim_death_phase == 2:
		return 1.0 - clamp(p.anim_death_t / p.anim_death_dur, 0.0, 1.0)
	if p.anim_recall_phase == 1:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		alpha = 1.0 - t
	elif p.anim_recall_phase == 2:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		alpha = t
	# Targeting overlay dim is now applied as a separate black overlay in
	# _draw_targeting_dim_overlay (RGB darken instead of alpha fade), so the
	# pilot drawing itself uses only the recall-fade alpha here.
	return alpha


# Targeting underlays — the paint that marks **what can be dropped on**.
#
# 딤과 강조의 규칙이 모드마다 다르고, 그 규칙의 한쪽 절반이 여기다
# (나머지 절반은 _undimmed_cells / _draw_targeting_pilot_dim /
#  _pilot_emphasis_scale).
#
#   • PILOT    — 타일은 칠하지 않는다. 사거리는 **딤으로** 말한다: 시전자에서
#                cast_range 밖의 타일만 어두워진다(`_undimmed_cells`, 무제한
#                사거리면 아무것도 안 어두워진다). 노란 채움은 겨눌 얼굴을 가린다.
#   • LOCATION — 유효 셀을 초록으로 칠한다. 사거리 밖 타일은 딤.
#   • PREVIEW  — 교전 영역(시전자 교전 반경)을 노랗게. 여기서는 영역 자체가
#                카드가 말하는 내용이다.
#   • 대상을 가리킨 동안(PILOT / LOCATION) — 그 카드 효과의 범위
#                (`pick_cells`: 교전 반경 · 범위 공격 반경)를 같은 노란 영역으로.
func _draw_targeting_underlays() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or not to.is_visualizing():
		return
	var hg: HexGrid = _bs.hex_grid
	if to.mode == CardTargetingOverlay.Mode.PREVIEW:
		for raw in to.area_cells.keys():
			var c := raw as Vector2i
			var pts := hg.hex_corners(_bs.cell_center(c))
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.30, 0.22))
			draw_polyline(_close_polygon(pts),
					Color(1.0, 0.85, 0.30, 0.85), 3.0, true)
	elif to.mode == CardTargetingOverlay.Mode.LOCATION:
		for raw in to.valid_cells.keys():
			var c := raw as Vector2i
			var pts := hg.hex_corners(_bs.cell_center(c))
			draw_colored_polygon(pts, Color(0.30, 0.85, 0.45, 0.25))
			draw_polyline(_close_polygon(pts),
					Color(0.30, 0.85, 0.45, 0.95), 3.0, true)
	if to.mode != CardTargetingOverlay.Mode.PREVIEW:
		for raw in to.pick_cells.keys():
			var c := raw as Vector2i
			var pts := hg.hex_corners(_bs.cell_center(c))
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.30, 0.18))
			draw_polyline(_close_polygon(pts),
					Color(1.0, 0.85, 0.30, 0.75), 2.5, true)


# Cyan ring / outline on the clicked-but-not-yet-confirmed target so the
# player can see what 확인 will commit. Drawn AFTER the per-pilot dim, together
# with the picked portrait itself, so the target always sits on top.
func _draw_pending_pick_highlight() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or to.pending_pick == null:
		return
	var hg: HexGrid = _bs.hex_grid
	# LOCATION 의 칸 외곽선은 초상 **밑에** — 그 칸에 선 대상 초상을 선이 긋지 않게.
	if to.mode == CardTargetingOverlay.Mode.LOCATION:
		var c := to.pending_pick as Vector2i
		var pts := hg.hex_corners(_bs.cell_center(c))
		draw_polyline(_close_polygon(pts),
				Color(0.30, 0.95, 1.0, 0.95), 5.0, true)
	if _pick_top != null and not _hidden_during_jungle_pick(_pick_top):
		var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
		_draw_marker_shadow(_pick_top, base_r, PilotMarker.ShadowPart.DISC)
		_draw_pilot_marker(_pick_top, base_r)
	if to.mode == CardTargetingOverlay.Mode.PILOT:
		var picked := to.pending_pick as PilotData
		if picked != null and picked.alive:
			var pos := _pilot_marker_pos(picked)
			# 강조 배율만큼 커진 마커 **바깥**에 링이 걸리도록 같은 배율을 탄다.
			var radius: float = pilot_marker_radius(picked) + 10.0
			draw_arc(pos, radius, 0.0, TAU, 36,
					Color(0.30, 0.95, 1.0, 0.95), 4.0)


# The cells that stay bright while a 대상 지정 카드 is lifted — everything else
# takes the black dim. The mirror image of _draw_targeting_underlays: whatever
# gets painted there is exactly what is spared here.
#
# **PILOT / LOCATION 은 시전자 사거리 안의 칸**이다(`is_in_range_cell` — 무제한
# 사거리면 전장 전체) + 유효 셀 + 가리킨 대상의 효과 범위. 예전에는 PILOT 이
# 빈 집합(타일 전부 딤)이라 카드의 사거리가 화면 어디에도 보이지 않았다.
func _undimmed_cells() -> Dictionary:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	var out: Dictionary = {}
	if to == null:
		return out
	match to.mode:
		CardTargetingOverlay.Mode.PREVIEW:
			for raw in to.area_cells.keys():
				out[raw as Vector2i] = true
		CardTargetingOverlay.Mode.PILOT, CardTargetingOverlay.Mode.LOCATION:
			# 대상을 가리킨 동안은 사거리가 아니라 **효과 범위**가 밝다 — 범위 칸 +
			# 대상 칸(범위 없는 단일 대상 카드는 대상 칸 하나).
			if to.pending_pick != null:
				return to.pick_bright_cells()
			for raw in _bs.tiles_layer.get_used_cells():
				var c := raw as Vector2i
				if to.is_in_range_cell(c):
					out[c] = true
			for raw in to.valid_cells.keys():
				out[raw as Vector2i] = true
			for raw in to.pick_cells.keys():
				out[raw as Vector2i] = true
	return out


# Tile dim. Drawn BEFORE pilots / HQ bars so an offset pilot marker that
# visually intrudes into an adjacent dimmed tile is not covered by that
# neighbour's dim — the marker's own dim (if any) is a separate disc drawn
# after the pilots.
func _draw_targeting_tile_dim(bright_cells: Dictionary) -> void:
	var hg: HexGrid = _bs.hex_grid
	var dim_color := Color(0.0, 0.0, 0.0, 0.60)
	for raw in _bs.tiles_layer.get_used_cells():
		var c := raw as Vector2i
		if bright_cells.has(c):
			continue
		var ctr := _bs.cell_center(c)
		var pts := hg.hex_corners(ctr)
		draw_colored_polygon(pts, dim_color)


# Per-pilot marker dim. Drawn AFTER pilot circles so the dim sits on top of
# the marker. Applied to every invalid pilot regardless of whether their tile
# is in-range — pilot markers are offset above/below their tile, so a marker
# whose own cell is dimmed can still bleed onto an adjacent in-range tile and
# read as "bright" without this per-marker disc. The marker is drawn ON TOP
# of the tile dim, so the disc dims only the marker; the underlying tile dim
# already darkens the tile area beneath it without doubling up on the marker.
func _draw_targeting_pilot_dim() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null:
		return
	var dim_color := Color(0.0, 0.0, 0.0, 0.60)
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if not to.should_dim_pilot(p):
			continue
		var marker_pos := _pilot_marker_pos(p)
		# Cover the HP ring outside the portrait too — slightly larger than
		# the portrait radius. 딤드 대상은 강조 대상이 아니므로 배율은 사실상
		# 1.0 이지만, 반지름은 그리는 쪽과 같은 한 곳에서 받아 온다.
		draw_circle(marker_pos, marker_outer_radius(pilot_marker_radius(p)), dim_color)


# Rendered marker position for the pilot — reads the cached layout built in
# _draw(). 지금은 렌더 가능한 파일럿이 모두 슬롯을 받으므로 이 폴백은 레이아웃이
# 아직 한 번도 안 돌았을 때(첫 프레임 이전)나 렌더 대상이 아닌 파일럿을 물었을
# 때만 걸린다.
func _pilot_marker_pos(p: PilotData) -> Vector2:
	if _pilot_render_layout.has(p):
		return _pilot_render_layout[p] as Vector2
	return pilot_marker_pos_fallback(p)


## 레이아웃 표에 없는 파일럿의 **대체** 마커 좌표 — 자기 칸에 혼자 선 것으로 치고
## 기본 방향(팀0 = 아래 / 팀1 = 위)의 첫 링에 앉힌다. 공개인 이유는 `BattleSim` 과
## `CardTargetingOverlay` 의 폴백 경로가 같은 답을 써야 하기 때문이다.
func pilot_marker_pos_fallback(p: PilotData) -> Vector2:
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	var cell := _render_cell(p)
	var dir: int = pilot_display_dir_index(p)
	return _bs.cell_center(cell) + _slot_offset(dir, base_r)


## Fresh `PilotData → Vector2` marker map — the same per-cell stack solve
## `_draw()` runs. Public because CardTargetingOverlay's PILOT hit test needs
## the *drawn* marker of each pilot: several pilots sharing a cell each get
## their own slot, and aiming at the tile centre instead can only ever resolve
## to one of them. Rebuilt on call (10 pilots) so a click never reads a layout
## from before the last move.
func pilot_marker_positions() -> Dictionary:
	return _build_pilot_render_layout()


## 지금 실제로 그려지는 마커 반지름 — 대상 지정 강조 배율이 반영된 값.
## `CardTargetingOverlay._hit_test_pilot` 이 클릭 반경을 여기서 받는다: 강조로
## 2배가 된 초상은 타일 반지름보다 커서, 고정 상수로 재면 얼굴 바깥 테두리를
## 눌렀을 때 대상이 잡히지 않는다.
func pilot_marker_radius(p: PilotData) -> float:
	return PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE * _pilot_draw_scale(p)


## 초상 반지름 → 마커 맨 바깥(HP 링 바깥의 검은 외곽선 끝) 반지름. 뒤 원판 ·
## 그림자 · 딤 원판이 전부 이 값을 쓴다.
static func marker_outer_radius(draw_radius: float) -> float:
	return PilotMarker.outer_radius(draw_radius)


# 지금 프레임의 강조 배율 — `_advance_emphasis` 가 목표값으로 밀고 있는 값이다.
# 그리기 · 배치 · 히트 반경이 전부 여기를 읽으므로 셋이 어긋날 수 없다.
func _pilot_emphasis_scale(p: PilotData) -> float:
	return float(_emphasis_now.get(p, 1.0))


# 실제로 그리는 배율 — 대상 지정 강조 × 누르기. 배치는 강조만 읽는다
# (`_pilot_emphasis_scale`); 초상 · 꼬리 · 그림자 · 히트 반경은 이 값을 읽는다.
func _pilot_draw_scale(p: PilotData) -> float:
	return _pilot_emphasis_scale(p) * float(_press_now.get(p, 1.0))


# 이 파일럿을 **지금 키울 것인가** — 보간의 목표값(1.0 또는
# TARGET_EMPHASIS_SCALE). 규칙은 `CardTargetingOverlay.is_emphasized` 하나다:
# 아무것도 가리키지 않은 동안은 사거리 안의 유효 대상, 대상을 가리킨 동안은
# 그 카드 효과가 닿을 파일럿(대상 + 범위 안 교전 참가자 / 피격자)만.
# 가리킨 대상 자신은 커진 채로 남고 시안 링이 그 위에 따로 붙는다.
func _pilot_emphasis_target(p: PilotData) -> float:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null:
		return 1.0
	return TARGET_EMPHASIS_SCALE if to.is_emphasized(p) else 1.0


func _circle_polygon(center: Vector2, r: float, n: int) -> PackedVector2Array:
	return PilotMarker.circle_polygon(center, r, n)


func _close_polygon(pts: PackedVector2Array) -> PackedVector2Array:
	return PilotMarker.close_polygon(pts)


## 텍스처를 검은 외곽선과 함께 그린다 — 같은 텍스처를 검은색으로 물들여
## (modulate 는 곱셈이라 알파 모양만 남는다) 둘레 8방향으로 `outline_px` 만큼
## 밀어 깐 뒤 원본을 덮는다. `ci` 가 그리기 상태일 때(_draw / draw 시그널)만
## 부를 것. 성장치 팝업과 교전 결과의 성장 줄이 같이 쓴다.
static func draw_outlined_icon(ci: CanvasItem, tex: Texture2D, rect: Rect2,
		outline_px: float, alpha: float = 1.0) -> void:
	var shadow := Color(0.0, 0.0, 0.0, alpha)
	for i in 8:
		var ang: float = float(i) / 8.0 * TAU
		var off := Vector2(cos(ang), sin(ang)) * outline_px
		ci.draw_texture_rect(tex, Rect2(rect.position + off, rect.size), false, shadow)
	ci.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, alpha))


func _alpha_mul(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


# 마커에서 자기 타일을 가리키는 말풍선 꼬리. `aim_point` 는 **글라이드 중인 타일
# 중심**(`_marker_center`)이다 — 이동 중에는 초상과 함께 미끄러지므로 꼬리가
# 초상보다 먼저 도착 칸을 가리키며 늘어나는 일이 없다.
#
# `em` 은 그 파일럿의 강조 배율이다. 초상이 커지면 화살표는 **더 바깥에서
# 시작해서 더 길게** 뻗어야 한다 — 시작점을 base 반지름에 두면 2배로 커진 초상이
# 화살표를 통째로 덮어 버린다(강조 대상, 즉 지금 겨누고 있는 파일럿에서만
# 사라지므로 하필 가장 필요한 순간에 사라진다). 길이도 같은 배율을 타되 타일
# 중심은 넘지 않는다.
func _draw_arrow_to_tile(circle_pos: Vector2, aim_point: Vector2,
		radius: float, color: Color, alpha: float = 1.0,
		em: float = 1.0) -> void:
	PilotMarker.draw_arrow(self, circle_pos, aim_point, radius, color, alpha, em)


# 꼬리의 축 — `{"dir", "perp", "apex_len", "base_len", "base_half"}`(채움 기준).
# 비어 있으면 그릴 꼬리가 없다(초상이 타일에 너무 붙었다).
#
# **끝은 언제나 타일 중심 바로 앞이다.** 예전에는 마커 반지름에서 길이를
# 뽑았는데(반지름 + 24px), 7명째부터 바깥 링에 앉는 마커는 타일에서 두 배로
# 멀어져 그 길이로는 허공에 짧은 삼각형만 남고 어느 칸 이야기인지가 사라진다.
# 거리에서 역산하면 멀어진 만큼 화살표가 길어져 "약간 멀어져 앉되 가리키는
# 칸은 분명하다"가 성립한다. 중심을 찔러 넘어가지는 않는다 — 넘어가면 옆 칸을
# 가리키는 것처럼 읽힌다.
func _arrow_axis(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> Dictionary:
	return PilotMarker.arrow_axis(circle_pos, aim_point, radius, em)


# 꼬리 채움 — 끝이 **뾰족한** 삼각형. 비어 있으면 그릴 꼬리가 없다.
func _arrow_fill_polygon(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> PackedVector2Array:
	return PilotMarker.arrow_fill_polygon(circle_pos, aim_point, radius, em)


# 꼬리 외곽(검은 판) — 채움을 `MARKER_OUTLINE_W` 만큼 **모서리를 세운 채** 부풀린
# 삼각형이다. 그림자와 자리 배정의 꼬리 겹침 판정도 이 모양을 쓴다.
#
# 예전에는 채움을 둥근 모서리로 부풀려(`JOIN_ROUND`) 끝이 뭉툭했다. 정확한 마이터
# 끝은 꼬리가 길수록(각이 좁을수록) 한없이 뻗으므로 채움 끝에서
# `ARROW_TIP_MITER_MAX` 까지만 내민다 — 그만큼 끝 근처의 검은 테가 가늘어져
# 오히려 더 뾰족하게 읽힌다.
func _arrow_outline_polygon(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> PackedVector2Array:
	return PilotMarker.arrow_outline_polygon(circle_pos, aim_point, radius, em)


func _draw_pilot_circle(pilot: PilotData, pos: Vector2, radius: float,
		color: Color, alpha: float = 1.0) -> void:
	# 찍을 수 있는 대상은 베이스 반지름에 TARGET_EMPHASIS_SCALE 을 곱해 크게
	# 그린다 — 나머지는 전부 딤드되므로 커진 얼굴만 남는다.
	var draw_radius: float = radius * _pilot_draw_scale(pilot)
	# Pilot portrait fills the slot. The team-colour HP ring (drawn outside the
	# portrait) is now the sole faction marker — the previous ring directly on
	# the portrait edge has been removed to avoid the double outline.
	var portrait: Texture2D = PilotImages.circle_for(pilot.pilot_id)
	# 쓰러진 파일럿의 초상은 마커 색과 같은 배율로 어두워진다.
	var portrait_tint: Color = _bs.ANIM_DEATH_TINT if pilot.anim_death_phase != 0 \
			else Color.WHITE
	# **초상 뒤의 흰 원.** `*_circle.png` 는 원 안쪽에도 투명한 부분이 있는 것이
	# 섞여 있어(실측: 40장 중 일부), 그대로 그리면 뒤의 타일 색이 얼굴을 뚫고
	# 비친다 — 특히 점령된 정글 타일 위에서 파일럿이 타일과 같은 색으로 물든다.
	# 원 그림 자체가 정사각형에 내접해 있으므로 같은 반지름의 원이 정확히 맞고,
	# 1px 줄여 안티에일리어싱된 가장자리 바깥으로 흰 테가 삐져나오지 않게 한다.
	# 딤/페이드는 초상과 같은 tint·alpha 를 타므로 배경만 밝게 남는 일은 없다.
	# **마커 뒤 검은 원판** — 초상 · HP 링 · 외곽선을 한 장으로 받친다. 초상과
	# 링 사이 틈이나 반투명한 가장자리로 타일 색이 비치지 않고, 이 원판의 바깥
	# 띠가 그대로 HP 링의 굵은 검은 외곽선이 된다(꼬리보다 나중에 그려지므로
	# 꼬리에 가려지지 않는다). 사망 딤 / 복귀 페이드는 alpha 로 함께 탄다.
	PilotMarker.draw_disc(self, pos, draw_radius, portrait, portrait_tint, color, alpha)
	draw_hp_ring(self, pos, draw_radius, pilot.hp, pilot.shield, pilot.max_hp,
			color, alpha)



# ─── HP 링 (전장 마커와 교전 무대 초상이 함께 쓴다) ──────────────────────────
# 링 한 바퀴 = `hp_ring_span` — 보호막은 **추가 체력**처럼 남은 HP 바로 뒤에
# 밝은 회색으로 이어 붙는다. HP + 보호막이 최대 체력을 넘으면 그 합이 한 바퀴가
# 되어(HP 구간이 그만큼 짧아진다) 보호막이 링 밖으로 잘리지 않는다.
# `EngageArena` 가 같은 함수로 무대 초상을 그리므로 두 화면의 링이 갈라지지 않는다.

## 링 한 바퀴가 나타내는 HP — max(최대 체력, HP + 보호막).
static func hp_ring_span(hp: int, shield: int, max_hp: int) -> float:
	return PilotMarker.hp_ring_span(hp, shield, max_hp)


## 초상 반지름 `draw_radius` 바깥에 붙는 링의 중심 반지름.
static func hp_ring_radius(draw_radius: float) -> float:
	return PilotMarker.hp_ring_radius(draw_radius)


static func _amul(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


## 빈 링(어두운 바탕) → HP(팀색) → 보호막(밝은 회색) → `HP_TICK_STEP` 구분선.
## 구분선은 보호막 구간까지 같은 간격으로 이어진다 — 보호막도 HP 와 같은 단위다.
static func draw_hp_ring(c: CanvasItem, pos: Vector2, draw_radius: float,
		hp: int, shield: int, max_hp: int, color: Color, alpha: float) -> void:
	PilotMarker.draw_hp_ring(c, pos, draw_radius, hp, shield, max_hp, color, alpha)


## 방금 잃은 구간들 — **잃기 전** 링 배치 기준의 비율. HP 조각은 `[hp1, hp0]`,
## 보호막 조각은 옛 보호막 구간의 바깥 끝 `[hp0 + sh1, hp0 + sh0]` 이다.
## 원소는 `[from, to, is_shield]`.
static func hp_loss_segments(hp0: int, sh0: int, hp1: int, sh1: int,
		max_hp: int) -> Array:
	var out: Array = []
	var span: float = hp_ring_span(hp0, sh0, max_hp)
	hp0 = maxi(hp0, 0)
	hp1 = maxi(hp1, 0)
	if hp1 < hp0:
		out.append([float(hp1) / span, float(hp0) / span, false])
	if sh1 < sh0:
		out.append([float(hp0 + maxi(sh1, 0)) / span, float(hp0 + sh0) / span, true])
	return out


## HP 조각 하나 — **바깥으로 튀어 나가며** 커지고 사라진다. 링 반지름이
## `draw_radius * HP_CHIP_FLY` 만큼 easeOutCubic 으로 밀려나고, 두께와 호의
## 각도는 조각의 가운데를 기준으로 커진다. `k` 는 0..1 진행도. 검은 외곽을
## 한 겹 깔아 밝은 바탕에서도 읽힌다.
static func draw_hp_chip(c: CanvasItem, pos: Vector2, draw_radius: float,
		seg: Array, color: Color, k: float, alpha: float) -> void:
	var grow: float = 1.0 - pow(1.0 - k, 3.0)          # ease-out
	var s: float = lerpf(1.0, HP_CHIP_SCALE, grow)
	var a: float = alpha * (1.0 - k * k)               # 끝으로 갈수록 빨리 사라진다
	var f0: float = float(seg[0])
	var f1: float = float(seg[1])
	var mid: float = (f0 + f1) * 0.5
	var half: float = minf((f1 - f0) * 0.5 * s, 0.5)
	var start_a: float = -PI * 0.5
	var a0: float = start_a + TAU * (mid - half)
	var a1: float = start_a + TAU * (mid + half)
	var ring_r: float = hp_ring_radius(draw_radius) + draw_radius * HP_CHIP_FLY * grow
	var w: float = HP_RING_W * s
	var n: int = maxi(4, int(36.0 * half * 2.0))
	var fill: Color = SHIELD_RING_COLOR if bool(seg[2]) else color.lightened(0.35)
	c.draw_arc(pos, ring_r, a0, a1, n, _amul(Color(0.0, 0.0, 0.0), a * 0.8),
			w + MARKER_OUTLINE_W)
	c.draw_arc(pos, ring_r, a0, a1, n, _amul(fill, a), w)


# ─── 손패 카드 미리보기 (전장 쪽) ────────────────────────────────────────────
# `CardPlayPreview` 가 무엇을 그릴지 정하고(`field_spec` / `neon_pilot`) 여기는
# 전장 좌표로 그리기만 한다. 미리보기가 떠 있는 동안 그쪽 `_process` 가 매 프레임
# 이 렌더러를 걷어차므로 애니메이션 시계도 그쪽 것(`anim_time`)을 쓴다.

const NEON_COLOR := Color(1.0, 1.0, 1.0)
const PREVIEW_PATH_COLOR := Color(1.0, 1.0, 1.0)
const PREVIEW_HEAL_COLOR := Color(0.40, 1.00, 0.50)
const PREVIEW_SHIELD_COLOR := Color(0.45, 0.85, 1.00)
const PREVIEW_DMG_COLOR := Color(1.00, 0.30, 0.25)
const PREVIEW_FONT_BASE := 24


func _preview() -> CardPlayPreview:
	var cp: CardPlayPreview = _bs.card_preview
	if cp == null or not cp.is_active():
		return null
	return cp


## 시전자 하얀 네온 — 마커 **뒤에** 깐다(`_draw_pilot_groups` 앞). 바깥으로
## 갈수록 옅은 겹 원이 번짐을 만들고, 맨 안쪽에 또렷한 흰 링 하나.
func _draw_card_preview_neon() -> void:
	var cp: CardPlayPreview = _preview()
	if cp == null:
		return
	var p: PilotData = cp.neon_pilot()
	if p == null or not _is_renderable(p):
		return
	var pos: Vector2 = _pilot_marker_pos(p) + _pilot_anim_offset(p)
	var outer: float = marker_outer_radius(pilot_marker_radius(p))
	var pulse: float = 0.5 + 0.5 * sin(cp.anim_time() * TAU * 1.2)
	var spread: float = 22.0 * HexGrid.DISPLAY_SCALE
	for i in 7:
		var k: float = float(i) / 6.0
		draw_circle(pos, outer + 2.0 + k * spread,
				_alpha_mul(NEON_COLOR, (0.34 - k * 0.045) * (0.6 + 0.4 * pulse)))
	draw_arc(pos, outer + 2.5, 0.0, TAU, 48, _alpha_mul(NEON_COLOR, 0.95),
			3.5 * HexGrid.DISPLAY_SCALE, true)


## 효과 미리보기 — 마커 위에 얹히는 것들. 대상 딤보다 **뒤에** 그려 어둡게
## 눌리지 않는다.
func _draw_card_preview_field() -> void:
	var cp: CardPlayPreview = _preview()
	if cp == null:
		return
	var spec: Dictionary = cp.field_spec()
	if spec.is_empty():
		return
	var t: float = cp.anim_time()
	if spec.has("ghost"):
		_draw_preview_ghost(spec["ghost"] as Dictionary, t)
	if spec.has("soul"):
		_draw_preview_soul(spec["soul"] as Dictionary, t)
	if spec.has("attack"):
		_draw_preview_attack(spec["attack"] as Dictionary, t)
	if spec.has("restore"):
		_draw_preview_restore(spec["restore"] as Dictionary, t)


## 타일 단위 이동 경로 — 칸 중심을 잇는 선 위에 칸마다 chevron 하나, 빛이
## 출발점에서 도착점 쪽으로 흐른다. 도착 칸에는 링.
func _draw_preview_path(cells: Array, t: float, ring_at_end: bool) -> void:
	if cells.size() < 2:
		return
	var pts := PackedVector2Array()
	for raw in cells:
		pts.append(_bs.cell_center(raw as Vector2i))
	var s: float = HexGrid.DISPLAY_SCALE
	draw_polyline(pts, Color(0, 0, 0, 0.75), 16.0 * s, true)
	draw_polyline(pts, _alpha_mul(PREVIEW_PATH_COLOR, 0.9), 8.0 * s, true)
	var steps: int = pts.size() - 1
	var head: float = fposmod(t * 2.2, float(steps) + 1.0)
	for i in steps:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var mid: Vector2 = a.lerp(b, 0.55)
		var dir: Vector2 = (b - a).normalized()
		# 흐르는 빛 — 앞머리에 가까운 칸일수록 밝다.
		var d: float = absf(head - float(i) - 0.5)
		var glow: float = clampf(1.0 - d * 0.8, 0.35, 1.0)
		_draw_field_chevron(mid, dir, 22.0 * s, _alpha_mul(PREVIEW_PATH_COLOR, glow))
	if ring_at_end:
		var end: Vector2 = pts[pts.size() - 1]
		var pulse: float = 0.5 + 0.5 * sin(t * TAU * 1.4)
		draw_arc(end, (24.0 + 4.0 * pulse) * s, 0.0, TAU, 40, Color(0, 0, 0, 0.75),
				13.0 * s, true)
		draw_arc(end, (24.0 + 4.0 * pulse) * s, 0.0, TAU, 40, PREVIEW_PATH_COLOR,
				7.0 * s, true)


func _draw_field_chevron(c: Vector2, dir: Vector2, half: float, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	var tip: Vector2 = c + dir * half * 0.6
	var pts := PackedVector2Array([
		tip - dir * half + n * half,
		tip,
		tip - dir * half - n * half,
	])
	draw_polyline(pts, Color(0, 0, 0, 0.85 * col.a), 15.0 * HexGrid.DISPLAY_SCALE, true)
	draw_polyline(pts, col, 8.0 * HexGrid.DISPLAY_SCALE, true)


## 이동 · 복귀 · 후퇴 — 도착 칸에 반투명 초상(고스트)과, 지금 자리에서 그곳까지의
## 경로. 경로 칸이 없으면(복귀 = 순간이동) 점선 하나로 잇고, `line = false`
## (이동 카드)면 고스트만 세운다.
func _draw_preview_ghost(g: Dictionary, t: float) -> void:
	var p := g["pilot"] as PilotData
	if p == null:
		return
	var to: Vector2i = g["to"]
	var path: Array = g.get("path", []) as Array
	# 고스트는 도착 칸의 **마커가 앉을 자리**에 선다 — 지금 마커가 자기 칸 중심에서
	# 떨어져 있는 만큼 그대로 옮긴다. 칸 중심에 그리면 이웃 칸으로 늘어진 지금
	# 마커와 겹치는 일이 생긴다.
	# 단 이동 카드(`line = false`)는 **겨눈 타일 한가운데**에 세운다 — 지금 마커의
	# 오프셋을 물려받으면 고스트가 커서가 가리킨 타일이 아니라 이웃 타일에 앉는다.
	var seat: Vector2 = _pilot_marker_pos(p) - _bs.cell_center(_render_cell(p))
	if not bool(g.get("line", true)):
		seat = Vector2.ZERO
	var dest: Vector2 = _bs.cell_center(to) + seat
	if path.size() >= 2:
		_draw_preview_path(path, t, false)
	elif bool(g.get("line", true)):
		var from: Vector2 = _pilot_marker_pos(p)
		var seg: float = 14.0 * HexGrid.DISPLAY_SCALE
		var total: float = from.distance_to(dest)
		var off: float = fposmod(t * 40.0, seg * 2.0)
		var d: float = -seg + off
		while d < total:
			var a: Vector2 = from.lerp(dest, clampf(d / total, 0.0, 1.0))
			var b: Vector2 = from.lerp(dest, clampf((d + seg) / total, 0.0, 1.0))
			draw_line(a, b, Color(0, 0, 0, 0.75), 13.0 * HexGrid.DISPLAY_SCALE)
			draw_line(a, b, PREVIEW_PATH_COLOR, 7.0 * HexGrid.DISPLAY_SCALE)
			d += seg * 2.0
	var r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	var pulse: float = 0.5 + 0.5 * sin(t * TAU)
	var alpha: float = 0.55 + 0.2 * pulse
	draw_circle(dest, r + 4.0, Color(0, 0, 0, alpha * 0.8))
	var portrait: Texture2D = PilotImages.circle_for(p.pilot_id)
	if portrait != null:
		draw_texture_rect(portrait, Rect2(dest - Vector2(r, r), Vector2(r, r) * 2.0),
				false, Color(1, 1, 1, alpha))
	else:
		draw_circle(dest, r, Color(1, 1, 1, alpha))
	draw_arc(dest, r + 3.0, 0.0, TAU, 40, Color(0, 0, 0, 0.8),
			10.0 * HexGrid.DISPLAY_SCALE, true)
	draw_arc(dest, r + 3.0, 0.0, TAU, 40, PREVIEW_PATH_COLOR,
			5.0 * HexGrid.DISPLAY_SCALE, true)


## 약탈 · 정글 파밍 — 캠프 칸에서 시전자 쪽으로 영혼이 날아가는 궤적과 얻을
## 성장치. 내려앉은 칸에서 먹는 경우(`at_dest`)는 그 칸 위에서 영혼이 솟는다.
func _draw_preview_soul(sd: Dictionary, t: float) -> void:
	var p := sd["pilot"] as PilotData
	var cell: Vector2i = sd["cell"]
	var amount: float = float(sd["amount"])
	var from: Vector2 = _bs.cell_center(cell)
	var to: Vector2 = from + Vector2(0.0, -60.0 * HexGrid.DISPLAY_SCALE)
	if not bool(sd.get("at_dest", false)) and p != null:
		to = _pilot_marker_pos(p)
	# 제어점은 출발→도착의 **수직** 방향으로 민다 — 위쪽으로만 밀면 위아래로 선
	# 두 점 사이에서 곡선이 직선으로 무너진다.
	var span: Vector2 = to - from
	var bend := Vector2(-span.y, span.x).normalized() * maxf(60.0 * HexGrid.DISPLAY_SCALE,
			span.length() * 0.35)
	if bend.y > 0.0:
		bend = -bend
	var ctrl: Vector2 = from.lerp(to, 0.5) + bend
	var pts := PackedVector2Array()
	for i in 21:
		var k: float = float(i) / 20.0
		pts.append(from.lerp(ctrl, k).lerp(ctrl.lerp(to, k), k))
	draw_polyline(pts, Color(0, 0, 0, 0.45), 7.0 * HexGrid.DISPLAY_SCALE, true)
	draw_polyline(pts, Color(0.55, 1.0, 0.92, 0.7), 3.0 * HexGrid.DISPLAY_SCALE, true)
	var icon: Texture2D = BattleSim.SCORE_POPUP_ICON
	var isz: float = 30.0 * HexGrid.DISPLAY_SCALE
	var k2: float = fposmod(t * 0.8, 1.0)
	var at: Vector2 = from.lerp(ctrl, k2).lerp(ctrl.lerp(to, k2), k2)
	if icon != null:
		draw_outlined_icon(self, icon, Rect2(at - Vector2(isz, isz) * 0.5,
				Vector2(isz, isz)), 3.0 * HexGrid.DISPLAY_SCALE,
				clampf(minf(k2, 1.0 - k2) * 5.0, 0.0, 1.0))
	_draw_preview_text(to + Vector2(0.0, -PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE - 8.0),
			"+" + BattleSim.fmt_score_gain(amount), BattleSim.SCORE_POPUP_COLOR)


## 공격 예상 — 대상 HP 링에서 **깎일 구간이 깜빡이고**, 마커 위에 명중률과 피해.
## 보호막이 먼저 받는 몫은 보호막 링에서 깜빡인다.
func _draw_preview_attack(a: Dictionary, t: float) -> void:
	var p := a["pilot"] as PilotData
	if p == null or not _is_renderable(p) or p.max_hp <= 0:
		return
	var pos: Vector2 = _pilot_marker_pos(p) + _pilot_anim_offset(p)
	var draw_r: float = pilot_marker_radius(p)
	var dmg: int = int(a["damage"])
	var shield_loss: int = mini(p.shield, dmg)
	var hp_loss: int = mini(p.hp, dmg - shield_loss)
	var blink: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * TAU * 2.4))
	# 깎일 구간 = 지금 링 배치에서 잃을 HP · 보호막 구간(`hp_loss_segments`).
	for raw in hp_loss_segments(p.hp, p.shield, p.hp - hp_loss,
			p.shield - shield_loss, p.max_hp):
		_draw_ring_blink(pos, draw_r, raw as Array, Color(1, 1, 1), blink, HP_RING_W + 1.0)
	var lethal: bool = hp_loss >= p.hp
	var top: Vector2 = pos + Vector2(0.0, -marker_outer_radius(draw_r) - 6.0)
	var chance: float = float(a["chance"])
	var dmg_txt: String = Loc.t(L.BATTLE_RENDERER_PREVIEW_KILL, {"n": dmg}) if lethal else ("-%d" % dmg)
	_draw_preview_text(top, dmg_txt, PREVIEW_DMG_COLOR)
	var fsz: int = int(round(PREVIEW_FONT_BASE * HexGrid.DISPLAY_SCALE))
	var hit_txt: String = Loc.t(L.BATTLE_RENDERER_PREVIEW_HIT_REPEAT
			if bool(a.get("repeat", false)) else L.BATTLE_RENDERER_PREVIEW_HIT,
			{"pct": roundi(chance * 100.0)})
	_draw_preview_text(top + Vector2(0.0, -float(fsz) - 4.0), hit_txt,
			Color(1.0, 0.95, 0.75))


## 회복 · 보호막 예상 — 차오를 구간이 HP 링(초록) / 보호막 링(시안)에서 깜빡이고
## 마커 위에 더해질 값.
func _draw_preview_restore(rd: Dictionary, t: float) -> void:
	var p := rd["pilot"] as PilotData
	if p == null or not _is_renderable(p) or p.max_hp <= 0:
		return
	var pos: Vector2 = _pilot_marker_pos(p) + _pilot_anim_offset(p)
	var draw_r: float = pilot_marker_radius(p)
	var heal: int = mini(int(rd.get("heal", 0)), p.max_hp - p.hp)
	var shield: int = int(rd.get("shield", 0))
	var blink: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * TAU * 2.0))
	# 차오를 구간은 **적용 뒤의** 링 배치로 잰다 — 보호막이 최대 체력을 넘겨
	# 한 바퀴가 늘어나는 경우에도 더해질 몫이 링 안에 들어온다.
	var hp1: int = p.hp + heal
	var sh1: int = p.shield + shield
	var span: float = hp_ring_span(hp1, sh1, p.max_hp)
	if heal > 0:
		_draw_ring_blink(pos, draw_r, [float(p.hp) / span, float(hp1) / span],
				PREVIEW_HEAL_COLOR, blink, HP_RING_W)
	if shield > 0:
		_draw_ring_blink(pos, draw_r,
				[float(hp1 + p.shield) / span, float(hp1 + sh1) / span],
				SHIELD_RING_COLOR, blink, HP_RING_W)
	var top: Vector2 = pos + Vector2(0.0, -marker_outer_radius(draw_r) - 6.0)
	var fsz: int = int(round(PREVIEW_FONT_BASE * HexGrid.DISPLAY_SCALE))
	if heal > 0:
		_draw_preview_text(top, "+%d" % heal, PREVIEW_HEAL_COLOR)
		top.y -= float(fsz) + 4.0
	if shield > 0:
		_draw_preview_text(top, Loc.t(L.BATTLE_RENDERER_PREVIEW_SHIELD, {"n": shield}),
				PREVIEW_SHIELD_COLOR)


## 미리보기 깜빡임 — HP 링 위의 `[from, to]` 구간(링 한 바퀴 대비 비율).
func _draw_ring_blink(pos: Vector2, draw_r: float, seg: Array, col: Color,
		blink: float, width: float) -> void:
	var f0: float = clampf(float(seg[0]), 0.0, 1.0)
	var f1: float = clampf(float(seg[1]), 0.0, 1.0)
	if f1 <= f0:
		return
	var start_a: float = -PI * 0.5
	draw_arc(pos, hp_ring_radius(draw_r), start_a + TAU * f0, start_a + TAU * f1,
			maxi(4, int(36.0 * (f1 - f0))), _alpha_mul(col, blink), width)


## 가운데 정렬, 굵은 검은 외곽선. `bottom_center` 는 기준선 가운데.
func _draw_preview_text(bottom_center: Vector2, txt: String, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var fsz: int = int(round(PREVIEW_FONT_BASE * HexGrid.DISPLAY_SCALE))
	var tsz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	var at := Vector2(bottom_center.x - tsz.x * 0.5, bottom_center.y)
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			maxi(2, int(round(6.0 * HexGrid.DISPLAY_SCALE))), Color(0, 0, 0, 0.9))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)


# ─── 효과 배너 (카드 버프 · 조건부 패시브 발동) ──────────────────────────────
# 파일럿에게 효과가 **실제로 걸린 순간** 그 파일럿의 초상 위에 한 줄짜리 배너가
# 뜬다 — 왼쪽은 둥근 사각형 칩(카드 아트, 또는 어두운 칩 위의 스킬 / 패시브
# 글리프), 오른쪽은 이름. **판은 없다**: 전장 위에 떠 있으므로 밝은 글자 +
# `BattleTheme.OUTLINE` 외곽선만으로 읽히게 한다.
#
# 진입점은 셋이다.
#   • `spawn_buff_banner(p, card)`       — 대상에게 효과를 거는 카드
#     (`CardPhaseManager._announce_buff`), 손패 상주 카드(약자 멸시 · 계시)
#   • `spawn_skill_banner(p)`            — 조건부 파일럿 스킬 발동 (`PilotSkillSystem`)
#   • `spawn_mech_passive_banner(p, key)` — 조건부 메크 패시브 발동 (`MechSkillSystem`)
# 같은 파일럿 · 같은 `key` 의 배너가 아직 떠 있으면 새로 쌓지 않고 그 배너의
# 수명만 늘린다(`BANNER_REFRESH_HOLD`) — 피해 한 대마다 걸리는 패시브(고통과 쾌감 ·
# 영혼 수확)가 배너 탑을 쌓지 않게 하는 장치다.
#
# 목록(`banners`)은 이 렌더러 하나가 들고 시간도 여기서 민다. 교전 무대가 열려
# 있는 동안에는 전장 쪽은 그리지 않고 `EngageArena` 가 같은 목록을 읽어 무대
# 초상 위에 그린다(`draw_banner` 공용) — 교전 중에 걸린 패시브도 같은 배너다.

const BANNER_DUR: float = 1.9
const BANNER_FADE_IN: float = 0.15
const BANNER_FADE_OUT: float = 0.35
## 같은 배너가 다시 걸렸을 때 그 순간부터 더 떠 있는 시간.
const BANNER_REFRESH_HOLD: float = 1.2
const BANNER_RISE_PX: float = 14.0
const BANNER_ART: float = 40.0
const BANNER_GAP: float = 8.0
const BANNER_STACK_GAP: float = 6.0
const BANNER_FONT: int = 24
const BANNER_TEXT := Color(1.0, 0.96, 0.84)
## 글리프 칩(흰 글리프)의 바탕 — 카드 아트는 바탕 없이 그 자체가 칩이다.
const BANNER_GLYPH_BG := Color(0.10, 0.11, 0.16, 0.92)
const BANNER_GLYPH_INSET: float = 0.16
## 칩 둘레의 어두운 테 — 글자 외곽선과 같은 역할(밝은 타일 위에서도 칩 경계가 읽힌다).
const BANNER_CHIP_RIM: float = 2.0
## 활성 배너 `{p, tex, glyph, title, key, t, dur, stack}`. `EngageArena` 가 읽는다.
var banners: Array = []


func spawn_buff_banner(p: PilotData, cd: CardData, key: String = "") -> void:
	if p == null or cd == null:
		return
	_push_banner(p, CardImages.art_for(cd.card_uid()), false, cd.card_name, key)


## 조건부 파일럿 스킬이 발동했다 — 그 파일럿 자신의 스킬 아이콘 + 이름.
func spawn_skill_banner(p: PilotData) -> void:
	if p == null or _bs == null or _bs.skill == null or not _bs.skill.has_skill(p):
		return
	var key: String = String(_bs.skill.def_for(p).get("key", ""))
	_push_banner(p, SkillImages.icon_for(key), true, _bs.skill.skill_name(p),
			"skill:" + key)


## 조건부 메크 패시브가 발동했다. `passive_key` 를 비우면 `p` 자신의 패시브이고,
## 주면 그 패시브다 — 불굴처럼 **남의 패시브**가 이 파일럿에게 걸리는 경우.
func spawn_mech_passive_banner(p: PilotData, passive_key: String = "") -> void:
	if p == null:
		return
	var def: Dictionary = _mech_passive_row(p, passive_key)
	if def.is_empty():
		return
	var key: String = String(def.get("key", ""))
	var title: String = Loc.t(String(def.get("name_key", "")))  # l10n-dynamic: mech_passive.*.name
	_push_banner(p, SkillImages.mech_icon_for(key), true, title, "mech:" + key)


func _mech_passive_row(p: PilotData, passive_key: String) -> Dictionary:
	if _bs == null:
		return {}
	if _bs.mech_skill != null:
		var own: Dictionary = _bs.mech_skill.passive_def(p)
		if passive_key.is_empty() or String(own.get("key", "")) == passive_key:
			return own
	if passive_key.is_empty() or _bs.gm == null:
		return {}
	for raw in (_bs.gm.mech_passives as Dictionary).values():
		var row: Dictionary = raw
		if String(row.get("key", "")) == passive_key:
			return row
	return {}


## 지금 떠 있는 배너 목록(읽기 전용으로 쓴다). 교전 무대가 자기 초상 위에 그린다.
func active_banners() -> Array:
	return banners


## 구조물(포탑 · 본진) **칸 위** 배너 — 강화 전령(`ObjectiveSystem._grant_empowered_herald`)이
## 때리는 자리마다 하나. 파일럿 배너와 같은 모양(`draw_banner`)이고 자리만 칸 위다.
## 항목은 `p = null` + `cell` — 교전 무대(`EngageArena`)는 파일럿으로 짝을 찾으므로
## 이 배너를 건너뛴다.
func spawn_cell_banner(cell: Vector2i, tex: Texture2D, title: String) -> void:
	var stack: int = 0
	for raw in banners:
		var e: Dictionary = raw
		if e.has("cell") and e["cell"] == cell:
			stack += 1
	if tex != null and _bs != null:
		_bs.prime_texture(tex)
	banners.append({
		"p": null,
		"cell": cell,
		"tex": tex,
		"glyph": false,
		"title": title,
		"key": "",
		"t": 0.0,
		"dur": BANNER_DUR,
		"stack": stack,
	})
	queue_redraw()


## 칸 위에 뜨는 피해 숫자(강화 전령의 포탑 · 본진 피해). 파일럿 숫자보다 크고 오래
## 떠 있다 — 구조물에는 초상이 없어 숫자가 그 자리의 유일한 표시다.
const CELL_POPUP_DUR: float = 0.9
const CELL_POPUP_SCALE: float = 1.3

func spawn_cell_popup(cell: Vector2i, text: String, color: Color) -> void:
	if _bs == null:
		return
	_popups.append({
		"pos":   _bs.cell_center(cell),
		"text":  text,
		"color": color,
		"t":     0.0,
		"delay": 0.0,
		"dur":   CELL_POPUP_DUR,
		"rise":  _bs.DMG_POPUP_RISE_PX,
		"icon":  null,
		"scale": CELL_POPUP_SCALE,
	})
	queue_redraw()


func _push_banner(p: PilotData, tex: Texture2D, glyph: bool, title: String,
		key: String) -> void:
	if not key.is_empty():
		for raw in banners:
			var e: Dictionary = raw
			if e["p"] == p and String(e["key"]) == key:
				e["dur"] = maxf(float(e["dur"]), float(e["t"]) + BANNER_REFRESH_HOLD)
				queue_redraw()
				return
	# 같은 파일럿 위에 이미 떠 있는 배너 수만큼 한 줄씩 위로 쌓는다.
	var stack: int = 0
	for raw in banners:
		if (raw as Dictionary)["p"] == p:
			stack += 1
	if tex != null and _bs != null:
		_bs.prime_texture(tex)
	banners.append({
		"p": p,
		"tex": tex,
		"glyph": glyph,
		"title": title,
		"key": key,
		"t": 0.0,
		"dur": BANNER_DUR,
		"stack": stack,
	})
	queue_redraw()


func _advance_banners(delta: float) -> bool:
	if banners.is_empty():
		return false
	var keep: Array = []
	for raw in banners:
		var e: Dictionary = raw
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < float(e["dur"]):
			keep.append(e)
	banners = keep
	return true


func _draw_buff_banners() -> void:
	if banners.is_empty():
		return
	# 교전 무대가 열려 있으면 배너는 무대 초상 위에 뜬다(`EngageArena`).
	if _bs != null and _bs.engage_phase != null and _bs.engage_phase.is_active():
		return
	var s: float = HexGrid.DISPLAY_SCALE
	for raw in banners:
		var e: Dictionary = raw
		if e.has("cell"):
			# 칸 배너 — 밑변이 구조물 HP 바(`_draw_turret_hp_bar`) 바로 위.
			var c: Vector2 = _bs.cell_center(e["cell"] as Vector2i)
			var hg: HexGrid = _bs.hex_grid
			draw_banner(self, e, Vector2(c.x, c.y - hg.hex_height * 0.38 - 8.0 * s), s)
			continue
		var p := e["p"] as PilotData
		if p == null or not _is_renderable(p):
			continue
		var pos: Vector2 = _pilot_marker_pos(p) + _pilot_anim_offset(p)
		var base := Vector2(pos.x,
				pos.y - marker_outer_radius(pilot_marker_radius(p)) - 8.0 * s)
		draw_banner(self, e, base, s)


## 배너 한 줄. `base` = 배너 밑변의 가운데(초상 바로 위), `s` = 화면 배율.
## 쌓임 · 떠오름 · 페이드는 `e` 의 값으로 여기서 계산한다 — 전장과 교전 무대가
## 같은 함수를 부르므로 두 자리의 배너가 갈라지지 않는다.
static func draw_banner(ci: CanvasItem, e: Dictionary, base: Vector2, s: float) -> void:
	var t: float = float(e["t"])
	var dur: float = float(e["dur"])
	var alpha: float = clampf(t / BANNER_FADE_IN, 0.0, 1.0)
	if t > dur - BANNER_FADE_OUT:
		alpha = minf(alpha, clampf((dur - t) / BANNER_FADE_OUT, 0.0, 1.0))
	if alpha <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var fsz: int = int(round(BANNER_FONT * s))
	var title: String = String(e["title"])
	var tsz: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	var art: float = BANNER_ART * s
	var gap: float = BANNER_GAP * s
	var w: float = art + gap + tsz.x
	var rise: float = BANNER_RISE_PX * s * (1.0 - pow(1.0 - clampf(t / BANNER_DUR, 0.0, 1.0), 2.0))
	var bottom: float = base.y - float(int(e["stack"])) * (art + BANNER_STACK_GAP * s) - rise
	var art_rect := Rect2(base.x - w * 0.5, bottom - art, art, art)
	var radius: float = 8.0 * s
	# 칩 둘레의 어두운 테 → 칩.
	var rim: float = BANNER_CHIP_RIM * s
	var oc: Color = BattleTheme.OUTLINE
	ci.draw_colored_polygon(rounded_rect_points(art_rect.grow(rim), radius + rim),
			Color(oc.r, oc.g, oc.b, oc.a * alpha))
	var tex := e["tex"] as Texture2D
	if bool(e["glyph"]):
		ci.draw_colored_polygon(rounded_rect_points(art_rect, radius),
				Color(BANNER_GLYPH_BG.r, BANNER_GLYPH_BG.g, BANNER_GLYPH_BG.b,
						BANNER_GLYPH_BG.a * alpha))
		if tex != null:
			ci.draw_texture_rect(tex, art_rect.grow(-art * BANNER_GLYPH_INSET), false,
					Color(1, 1, 1, alpha))
	elif tex != null:
		draw_textured_rounded_rect(ci, tex, art_rect, radius, Color(1, 1, 1, alpha))
	else:
		ci.draw_colored_polygon(rounded_rect_points(art_rect, radius),
				Color(0.25, 0.25, 0.32, alpha))
	# 이름 — 판 없이 외곽선만.
	var text_at := Vector2(art_rect.end.x + gap,
			art_rect.position.y + art * 0.5 + font.get_ascent(fsz) * 0.5 - 2.0 * s)
	ci.draw_string_outline(font, text_at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			maxi(2, int(round(float(BattleTheme.OUTLINE_SIZE) * s))),
			Color(oc.r, oc.g, oc.b, oc.a * alpha))
	ci.draw_string(font, text_at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			Color(BANNER_TEXT.r, BANNER_TEXT.g, BANNER_TEXT.b, alpha))


## 텍스처를 **둥근 사각형**으로 깎아 그린다 — 셰이더 없이, 둥근 모서리 폴리곤에
## 같은 모양의 UV 를 입혀 `draw_colored_polygon` 한 번으로. 배너 · 예약 칩이 쓴다.
static func draw_textured_rounded_rect(ci: CanvasItem, tex: Texture2D, rect: Rect2,
		radius: float, modulate: Color = Color.WHITE) -> void:
	var pts := rounded_rect_points(rect, radius)
	var uvs := PackedVector2Array()
	for pt in pts:
		uvs.append((pt - rect.position) / rect.size)
	ci.draw_colored_polygon(pts, modulate, uvs, tex)


static func rounded_rect_points(rect: Rect2, radius: float, seg: int = 5) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var out := PackedVector2Array()
	var corners: Array = [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for raw in corners:
		var c: Vector2 = raw[0]
		var a0: float = raw[1]
		for i in seg + 1:
			var a: float = a0 + (PI * 0.5) * float(i) / float(seg)
			out.append(c + Vector2(cos(a), sin(a)) * r)
	return out
