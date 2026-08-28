class_name EngageArena
extends Control

# 턴제 교전 아레나 — TurnEngageSim 의 상태를 그리기만 한다.
# 게임 상태 변경은 전부 시뮬레이터/매니저 쪽에서 일어난다.
#
# **탑뷰(쿼터뷰)**: 무대는 화면 가운데의 큰 밴드(`BAND_RECT`, 1032×1000) 하나고,
# 그 안은 위에서 내려다본 바닥면이다. **진영이 좌우를 나누지 않는다** — 자리를
# 정하는 것은 전장 타일이고(`TurnEngageSim._place_from_grid`), 바닥에 그려지는 납짝한
# 육각 윤곽이 그 타일들이다.
#
# 유닛 하나는 세 겹으로 그려진다 — **바닥에 누운 타원(정확한 지상 위치)** →
# **그 타원을 가리키는 손잡이 쉐기** → **떠 있는 원형 초상**. 사이드뷰 시절의
# 쉐기는 "오른쪽을 보는가 왼쪽을 보는가"를 말했지만, 탑뷰에서 읽혀야 하는 것은
# 방향이 아니라 **이 얼굴이 바닥 어느 지점에 서 있는가**다(초상은 발밑에서
# `UNIT_LIFT` 만큼 띄워져 있어 그대로는 자기 자리를 가리키지 못한다).
#
# 밴드 아래에는 교전 참가자 전원이 **한 줄**로 깔린다 — 아군 왼쪽 / 적군 오른쪽,
# 가운데 VS, **얼굴 위주 정사각 썸네일** 아래에 체력 바.
#
# 텍스트는 전부 Label 노드로 만든다(draw_string 은 한글 폴백 폰트를 태우기
# 어렵다). 그래픽은 세 개의 DrawProxy 노드가 나눠 그린다:
#
#   _clip (clip_contents=true, BAND_RECT)   ← 무대 밖은 여기서 잘린다
#     └ _world (position/scale = 카메라)     ← draw_world()  : 무대 좌표계
#   _hud    (풀스크린)                        ← draw_hud()    : 화면 좌표계
#   _roster (풀스크린)                        ← draw_roster() : 하단 썸네일 스트립
#
# 자기 자신(_draw)에 그리지 않는 이유: Control 은 자기 그림을 먼저 그리고 그
# 위에 자식을 그린다. 풀스크린 딜 ColorRect 가 자식이므로 자기 _draw 로 그린
# 무대는 딜 아래에 깔려 버린다. 딜보다 뒤에 붙은 프록시 노드에 그려야
# "무대 밖만 딜드"가 성립한다.
#
# 2026-08 이전의 **사이드뷰 벨트**(하늘 · 뒷벽 · 지평선을 그리고 팀색으로 좌우
# 절반을 틴트하던 납짝한 시네마 밴드, 세로로 긴 tall 크롭 스트립)는 여기서
# 대체됐다. `SKY_TOP` / `BACKWALL` / `HORIZON_LINE` / `SIDE_TINT_A` /
# `TURRET_BG_SCALE` 이 그때 함께 사라졌다.

## 화면 크기는 고정 상수가 아니라 런타임 값이다 — 스트레치가 `expand` 라
## 세로로 긴 기기에서는 높이가 1920 보다 커진다. 딜 · 루트가 뷰포트 전체를
## 덮지 않으면 그 차이만큼 화면 끝에 안 덮인 띄가 남는다.
## `docs/mobile_safe_area.md` 참고.

const TEAM_COLORS := [
	Color(0.32, 0.62, 0.95),   # team 0 (player)
	Color(0.95, 0.40, 0.32),   # team 1 (enemy)
]
const TITLE_COLOR   := Color(1.0, 0.95, 0.55, 1.0)
const TIME_COLOR    := Color(0.92, 0.96, 1.0, 1.0)
const TIME_LOW      := Color(1.0, 0.55, 0.40, 1.0)
const HP_BAR_BG     := Color(0.06, 0.06, 0.08, 1.0)
const HP_BAR_FILL   := Color(0.30, 0.85, 0.45, 1.0)
const HP_BAR_LOW    := Color(0.90, 0.55, 0.25, 1.0)
const SHIELD_FILL   := Color(0.85, 0.85, 0.30, 0.85)
## HP 바가 경고색으로 바뀌는 비율.
const LOW_HP_RATIO: float = 0.30

# ─── 무대 (밴드) ───────────────────────────────────────────────
## 교전 그래픽이 그려지는 유일한 사각형. 이 밖으로 나간 것은 잘린다.
##
## **사이드뷰 시절의 두 배**다(500 → 1000). 벨트는 깊이가 연출용이라 납짝해도
## 됐지만, 탑뷰의 세로는 **실제 거리**다 — 위 타일과 아래 타일이 같은 밴드에
## 들어가야 배치가 전장과 같은 모양으로 읽힌다. 높이를 벌어놓은 만큼 하단
## 스트립은 세로 300짜리 tall 크롭을 포기하고 **90×90 정사각 썸네일**로 내려앉는다.
const BAND_RECT := Rect2(24.0, 406.0, 1032.0, 1000.0)
const BAND_FRAME    := Color(0.45, 0.53, 0.72, 0.90)
## 무대 밖 화면(전장 · 핸드 행 등)을 덮는 딜.
const DIM_COLOR     := Color(0.0, 0.0, 0.0, 0.86)

# ─── 바닥면 ────────────────────────────────────────────────────
# 위(먼 쪽)에서 아래(가까운 쪽)로 갈수록 밝아진다 — 탑뷰라도 약간 누워 보는
# 쿼터뷰이므로 이 명도 기울기가 깊이를 만든다.
const GROUND_FAR    := Color(0.13, 0.15, 0.22, 1.0)
const GROUND_NEAR   := Color(0.24, 0.27, 0.36, 1.0)
## 바닥 격자 — 간격이 칸 피치의 절반이라 "이 무대에도 칸이 있다"가 읽힌다.
const FLOOR_LINE_COLOR := Color(0.55, 0.62, 0.80, 0.07)
## 무대 바깥 테두리.
const EDGE_COLOR    := Color(0.45, 0.53, 0.72, 0.35)
## 바닥면 밖으로 더 그려 두는 여백 — 카메라가 가장자리를 비출 때 빈칸이
## 생기지 않게 한다.
const BG_BLEED: float = 260.0

# ─── 카메라 ────────────────────────────────────────────────────
## 최대 확대 배율. 최소 배율은 "바닥면 전체가 밴드에 들어가는 배율"로 계산한다.
const CAM_MAX_ZOOM: float = 1.55
## 프레이밍 여백(무대 px). 세로 여백이 넘치게 넣어있는 것은 초상이 발밑에서
## `UNIT_LIFT` 만큼 띄어 있기 때문이다 — 그 높이를 안 두면 맨 윗줄 유닛의 얼굴이
## 밴드 위로 잘린다.
const CAM_PAD_X: float = 80.0
const CAM_PAD_Y: float = 130.0
## 지수 감쇠 추종 계수(1/s). 줌이 더 느린 이유는 유닛 하나가 잠깐 튀었다고
## 화면 배율이 출렁이면 멀미가 나기 때문.
const CAM_POS_RATE: float = 4.0
const CAM_ZOOM_RATE: float = 2.6

# ─── 화면 세로 앞커 ──────────────────────────────────────────────
# 제목 · 라운드 · 라운드 칸 · 차례 배너가 밴드 위에 차례로 쌓인다. 밴드가
# 두 배로 커지면서 이 네 줄이 전부 위로 올라왔다.
const TITLE_Y: float = 240.0
const ROUND_Y: float = 292.0
const PHASE_Y: float = 372.0

# ─── 하단 초상화 스트립 ────────────────────────────────────────
# **아군 왼쪽 / 적군 오른쪽**, 한 줄에 열 명이 마주 선다 (5v5 면 IIIII vs IIIII).
# 무대에서 팀0 이 언제나 왼쪽에 서므로 스트립도 같은 좌우를 쓴다.
#
# 초상화는 **얼굴 위주 정사각 썸네일**(`PilotImages.face_for`, 256×256)이다.
# 사이드뷰 시절에는 세로로 긴 전신 크롭(90×300)이었는데, 밴드가 두 배로 커지면서
# 그 길이가 들어갈 자리가 없어졌다. 얼굴만 남기는 편이 자리를 덜 먹고 — 스트립이
# 답해야 하는 질문은 "누구인가 · 얼마나 성한가" 둘뿐이라 몸은 무대가 보여 준다.
const STRIP_LEFT: float = 24.0
const STRIP_WIDTH: float = 1032.0
## 두 팀 사이의 홈 — 여기에 "VS" 가 앉는다. 양 팀은 **이 홈에 붙어서** 바깥으로
## 늘어서므로, 인원이 5명 미만이어도 가운데가 비지 않고 "마주 선" 그림이 남는다.
const STRIP_MID_GAP: float = 68.0
## 초상화 사이 간격.
const STRIP_CELL_GAP: float = 8.0
## 초상화 한 칸 — **정사각**이다. 폭은 STRIP_WIDTH 에 정확히 들어맞는 값이고
## (5×90 + 4×8 = 482, 482×2 + 68 = 1032), 높이는 face 크롭이 256×256 정사각이므로
## 같은 값이어야 얼굴이 찌그러지지 않는다.
const STRIP_PORTRAIT_W: float = 90.0
const STRIP_PORTRAIT_H: float = 90.0
## 팀 이름 줄 / 초상화 윗변. 밴드 밑단(1406) 바로 아래에 붙는다.
const STRIP_HEADER_Y: float = 1416.0
const STRIP_TOP: float = 1450.0
const STRIP_HP_W: float = 90.0
const STRIP_HP_H: float = 14.0
## 초상화 아래 체력 바까지의 간격.
const STRIP_HP_GAP: float = 8.0
## 지금 차례를 가진 유닛의 테두리 두께 / 평소 테두리 두께.
const STRIP_RIM_ACT: float = 4.0
const STRIP_RIM_IDLE: float = 2.0
## 체력 바 밑의 **두 번째 줄**. 교전 중에는 비어 있고, 결과 화면에서 이 교전으로
## 번 성장치가 여기 앉는다. 예전에는 역할 이름(`T0` / `F1`)이 상시로 찍혔는데,
## 그 표는 초상화가 이미 말하고 있는 것을 90px 칸에 한 번 더 적을 뿐이었다.
## 개시 확인 화면(EngageIntro)은 이 줄 밑단에서 부제목과 버튼 자리를 잰다.
const STRIP_SUB_Y: float = STRIP_TOP + STRIP_PORTRAIT_H + STRIP_HP_GAP \
		+ STRIP_HP_H + 4.0
const STRIP_BOTTOM: float = STRIP_SUB_Y + 24.0

# ─── 포탑(지형) ──────────────────────────────────────────────────
## 받침 반지름(바닥에 누운 타원). 파일럿 발밑 타원보다 크게 잡아 구조물로 읽히게 한다.
const TURRET_BASE_R := Vector2(48.0, 19.0)
## 포신 · 포격 투사체가 나가는 높이. 탑뷰라 높이는 연출뿐이다.
const TURRET_LIFT: float = 30.0
## 탑신 색 — 바닥보다 **밝게** 잡아야 바닥 위에 선 구조물로 읽힌다.
const TURRET_BODY_COLOR := Color(0.17, 0.19, 0.27, 1.0)

# ─── 유닛 연출 ────────────────────────────────────────────────
## 초상화 원의 중심은 발밑(pos)에서 이만큼 위에 뜼다. 사이드뷰 시절(42)보다
## 훨씬 높은 것은 그 사이에 **바닥을 가리키는 쉐기**가 들어야 하기 때문이다.
const UNIT_LIFT: float = 82.0
## 바닥 위치 표식 — 누운 원(쿼터뷰라 납짝하다).
const GROUND_RX: float = 30.0
const GROUND_RY: float = 13.0
## 초상화 → 바닥 원을 잇는 쉐기의 윗변 반폭.
const PIN_HALF_W: float = 10.0
## 행동 중(돌진/타격) 유닛에 두르는 강조 링.
const ACT_RING_COLOR := Color(1.0, 0.92, 0.55, 0.85)
## [강습] 낙하 지점에 남는 겹링.
const DROP_RING_COLOR := Color(1.0, 0.85, 0.45, 0.75)
## 시신의 밝기 — 알파가 아니라 **곱하는 명도**다. 투명하게 두면 뒤에 선 유닛이
## 시신을 뚫고 비쳐 겹친 자리에서 누가 살아 있는지가 안 읽힌다.
const DEAD_DIM: float = 0.32

# ─── 결과 화면 (준 피해 막대) ──────────────────────────────────────────────
# 결과는 **패널이 아니다** — 무대(밴드)만 걷고, 교전 내내 서 있던 초상화
# 스트립을 그 자리에 그대로 둔 채 각자가 넣은 피해를 막대로 위에 세운다.
# 화면이 갈아 끼워지는 대신 무대만 사라지므로 "방금 저 얼굴이 한 일"이
# 자기 얼굴 위에 그대로 자란다.
const RES_BAR_W: float = 62.0
## 막대 밑변 — 초상화 윗변 바로 위. 여기서 위로 자란다.
const RES_BAR_BOTTOM: float = STRIP_TOP - 8.0
## 표시 구간. 최소 높이는 "0 은 아니지만 이 교전에서 가장 적게 넣었다"이고,
## 최대는 밴드가 서 있던 자리를 거의 다 쓴다.
const RES_BAR_MIN_H: float = 28.0
const RES_BAR_MAX_H: float = 560.0
## 막대가 자랄 자리(0 피해도 밑동은 남는다) / 처치 배지 높이.
const RES_BAR_STUB_H: float = 6.0
const RES_KILL_H: float = 26.0
const RES_BAR_BG := Color(0.13, 0.15, 0.22, 0.85)
## 결과 화면의 딤 — 무대가 걷힌 뒤라 **더 어둡다**. 교전 중에는 밴드가 화면
## 한가운데를 덮고 있어 0.86 으로도 전장이 안 읽혔지만, 그 밴드가 사라지면
## 그 자리로 격자와 초상화가 그대로 올라와 막대와 자리를 다툰다.
const RES_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.945)

## 결과 한 줄의 세 가지. 판정은 매니저가 하고(오브젝트 교전인지를 아는 것이
## 그쪽이다) 이 중 하나를 넘겨 받는다 — 문자열을 여기 두는 것은 그 글자에
## 무슨 색을 입힐지가 이 화면의 일이기 때문이다.
const RESULT_WIN: String     = "승리"
const RESULT_LOSE: String    = "패배"
const RESULT_NEUTRAL: String = "교전 결과"
const RESULT_WIN_COLOR     := Color(1.00, 0.90, 0.45)
const RESULT_LOSE_COLOR    := Color(1.00, 0.48, 0.42)
const RESULT_NEUTRAL_COLOR := Color(0.86, 0.88, 0.94)

var _bs: BattleSim = null
var _sim: TurnEngageSim = null
var _is_duel: bool = false

## 무대 노드 — _ready 에서 만든다.
var _clip: Control = null
var _world: DrawProxy = null
var _hud: DrawProxy = null
var _roster: DrawProxy = null

## 카메라 상태 (벨트 좌표계 기준).
var _cam_center: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.0
var _cam_target_center: Vector2 = Vector2.ZERO
var _cam_target_zoom: float = 1.0
var _cam_min_zoom: float = 1.0

## 라운드 표시 ("라운드 2 / 3"). 결투는 라운드 예산이 없으므로 진행 라운드만.
var _round_lbl: Label = null
## 지금 누구 차례인가 / 종료 사유 배너.
var _phase_lbl: Label = null
## 종료 유예 동안 상단에 띄우는 배너(빈 문자열 = 아직 전투 중).
var _end_banner: String = ""
## 상단 제목. 교전 중에는 카드 이름 / 오브젝트 이름이고, 결과 화면에서는
## 승리 · 패배 · 교전 결과로 갈아 끼운다.
var _title_lbl: Label = null
## 팀 이름 두 줄("아군" / "적군"). 결과 화면에서는 그 자리를 막대가 쓰므로 걷는다.
var _headers: Array = []
## 결과 화면인가 — 무대가 걷히고 스트립이 성적표가 된 상태.
var _result_mode: bool = false
## 결과 막대의 표시 구간 — 이 교전의 준 피해 최소 · 최대. 절대 스케일을 쓰면
## 소규모 교전은 열 개가 다 밑동만 남고 대규모 교전은 다 천장에 붙는다.
var _res_lo: float = 0.0
var _res_hi: float = 0.0
## 풀스크린 딜. 미리보기 모드에서는 입력을 통과시켜야 한다 — 그 위에
## 개시 확인 화면의 버튼이 앉기 때문.
var _dim: ColorRect = null
## 미리보기 — 개시 확인 화면(VS)이 같은 무대를 **정지 화면**으로 보여 준다.
## 그때는 `_process` 가 돌지 않고(시뮬레이터도 아직 `begin()` 전이다) 입력도
## 가로채지 않는다.
var _preview: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤쪽 입력 차단
	# 크기를 직접 박는다. CanvasLayer 밑의 Control 은 PRESET_FULL_RECT 만으로는
	# 사이즈가 잡히지 않아 (0,0) 으로 남는다 — 그러면 자식 ColorRect 의
	# 풀스크린 앵커도 0 이 되어 딤이 아예 안 그려지고, MOUSE_FILTER_STOP 도
	# 뒤쪽 입력을 못 막는다. 아레나 UI 는 어차피 1080×1920 절대 좌표계다.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())

	# 1) 풀스크린 딤 — 무대 밖(전장 · 핸드 행)을 눌러 준다.
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	# 2) 무대 — clip_contents 가 이 사각형 밖을 전부 잘라 낸다.
	_clip = Control.new()
	_clip.name = "ArenaBand"
	_clip.position = BAND_RECT.position
	_clip.size = BAND_RECT.size
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	# 3) 월드 — position/scale 이 곧 카메라 변환. 데미지 팝업도 여기 자식으로
	#    붙어서 카메라를 따라 움직이고 무대 밖에서 함께 잘린다.
	_world = DrawProxy.new()
	_world.name = "BeltWorld"
	_world.draw_fn = Callable(self, "draw_world")
	_clip.add_child(_world)

	# 4) 화면 좌표계 그래픽 — 무대 테두리 · 남은 시간 바.
	_hud = DrawProxy.new()
	_hud.name = "ArenaHud"
	_hud.draw_fn = Callable(self, "draw_hud")
	_hud.position = Vector2.ZERO
	add_child(_hud)

	# 5) 하단 초상화 스트립 — 초상화 · 체력 바(이름만 Label).
	_roster = DrawProxy.new()
	_roster.name = "RosterStrip"
	_roster.draw_fn = Callable(self, "draw_roster")
	_roster.position = Vector2.ZERO
	add_child(_roster)

	var ground := TurnEngageSim.ground_rect()
	_cam_min_zoom = minf(BAND_RECT.size.x / ground.size.x,
			BAND_RECT.size.y / ground.size.y)
	_cam_center = ground.get_center()
	_cam_target_center = _cam_center
	_cam_zoom = _cam_min_zoom
	_cam_target_zoom = _cam_min_zoom


## `preview` — 개시 확인 화면이 쓰는 정지 모드. 시뮬레이터는 자리만 잡힌
## 채 아직 `begin()` 전이므로 라운드도 피해도 없다. 무대를 이때 보여 주는
## 이유는 하나다 — **시작 포지션을 보고 교전을 열지 말지 정하라는 것**이
## 이 화면의 질문이기 때문이고, 그러려면 명단만으로는 부족하다.
func setup(bs: BattleSim, sim: TurnEngageSim, title_text: String,
		is_duel: bool, preview: bool = false) -> void:
	_bs = bs
	_sim = sim
	_is_duel = is_duel
	_preview = preview
	if preview:
		# 버튼은 이 노드 밖(EngageIntro)에 있다 — 딜과 루트가 클릭을 샯으면
		# 확인 / 취소가 눌리지 않는다.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _dim != null:
			_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui(title_text)
	# 첫 프레임은 보간 없이 딜 맞춰 잡는다 — 무대 중앙에서 스르르 밀려오는
	# 연출은 교전 시작 순간을 놓치게 만든다.
	_update_camera(0.0, true)
	if preview:
		# 정지 화면이다 — 단 한 번만 그린다.
		_refresh_header()
		_world.queue_redraw()
		_hud.queue_redraw()
		_roster.queue_redraw()
		set_process(false)
		return
	set_process(true)


## 미리보기 모드에서 차례 배너 자리에 넣을 한 줄. "지금 누구 차례인가"는
## 아직 아무도 움직이지 않은 화면에서 답할 수 없는 질문이다.
func set_hint(text: String) -> void:
	if _phase_lbl != null:
		_phase_lbl.text = text


func _build_ui(title_text: String) -> void:
	_title_lbl = _make_label(title_text, 40, TITLE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	_title_lbl.position = Vector2(0, TITLE_Y)
	_title_lbl.size = Vector2(ScreenMetrics.vp_w(), 56)
	add_child(_title_lbl)

	_round_lbl = _make_label("", 46, TIME_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_round_lbl.position = Vector2(0, ROUND_Y)
	_round_lbl.size = Vector2(ScreenMetrics.vp_w(), 56)
	add_child(_round_lbl)

	_phase_lbl = _make_label("", 24, Color(0.85, 0.85, 0.9),
			HORIZONTAL_ALIGNMENT_CENTER)
	_phase_lbl.position = Vector2(0, PHASE_Y)
	_phase_lbl.size = Vector2(ScreenMetrics.vp_w(), 32)
	add_child(_phase_lbl)

	var centre_x: float = STRIP_LEFT + STRIP_WIDTH * 0.5
	var vs := _make_label("VS", 30, TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	vs.position = Vector2(centre_x - STRIP_MID_GAP * 0.5,
			STRIP_TOP + STRIP_PORTRAIT_H * 0.5 - 20.0)
	vs.size = Vector2(STRIP_MID_GAP, 40)
	add_child(vs)

	for t in range(2):
		var team_units: Array = _sim.units_of(t)
		# 팀 이름은 그 팀 초상화 무리 **위**에 온다 — 좌우가 곧 팀이므로
		# 라벨도 그 자리에 있어야 한다.
		var hdr := _make_label("아군" if t == 0 else "적군", 24, TEAM_COLORS[t],
				HORIZONTAL_ALIGNMENT_CENTER)
		var group_w: float = _strip_group_width(team_units.size())
		hdr.position = Vector2(
				(centre_x - STRIP_MID_GAP * 0.5 - group_w) if t == 0
						else (centre_x + STRIP_MID_GAP * 0.5),
				STRIP_HEADER_Y)
		hdr.size = Vector2(group_w, 30)
		add_child(hdr)
		_headers.append(hdr)


## 초상화 n 개가 차지하는 가로 폭(간격 포함).
static func _strip_group_width(count: int) -> float:
	if count <= 0:
		return 0.0
	return float(count) * STRIP_PORTRAIT_W + float(count - 1) * STRIP_CELL_GAP


## 한 참가자 칸의 중심 x. **두 팀 다 가운데 홈에 붙어** 바깥으로 늘어선다 —
## 팀0 은 홈 왼쪽에서 왼쪽으로, 팀1 은 홈 오른쪽에서 오른쪽으로. 인원이 5명
## 미만이면 바깥쪽이 비고 가운데는 언제나 차 있다.
static func _strip_cell_x(team: int, count: int, idx: int) -> float:
	var step: float = STRIP_PORTRAIT_W + STRIP_CELL_GAP
	var centre: float = STRIP_LEFT + STRIP_WIDTH * 0.5
	if team == 0:
		return centre - STRIP_MID_GAP * 0.5 \
				- float(count - 1 - idx) * step - STRIP_PORTRAIT_W * 0.5
	return centre + STRIP_MID_GAP * 0.5 \
			+ float(idx) * step + STRIP_PORTRAIT_W * 0.5


func _process(delta: float) -> void:
	if _sim == null or _preview:
		return
	_refresh_header()
	_update_camera(delta, false)
	_drain_popups()
	_world.queue_redraw()
	_hud.queue_redraw()
	_roster.queue_redraw()


# ─── 카메라 ──────────────────────────────────────────────────────────────────
# 생존(= 미처치) 유닛 전원을 담는 바운딩 박스를 프레이밍한다. **포탑은 넣지
# 않는다** — 포탑은 무대 참가자가 아니라 배경 지형이고, 프레임에 넣으면 벨트
# 양 끝까지 담느라 배율이 떨어져 정작 싸우는 유닛이 잘게 보인다.
# 무대 밖은 보여 주지 않는다 — _clamp_cam_center 가 뷰를 stage_rect(벨트 +
# 포탑이 선 배경 지형) 안에 가둔다.
func _update_camera(delta: float, snap: bool) -> void:
	var pts := _focus_positions()
	if not pts.is_empty():
		var mn: Vector2 = pts[0]
		var mx: Vector2 = pts[0]
		for raw in pts:
			var p: Vector2 = raw
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var pad := Vector2(TurnEngageSim.UNIT_RADIUS + CAM_PAD_X,
				TurnEngageSim.UNIT_RADIUS + CAM_PAD_Y)
		mn -= pad
		mx += pad
		var span: Vector2 = mx - mn
		_cam_target_zoom = clampf(minf(
					BAND_RECT.size.x / maxf(1.0, span.x),
					BAND_RECT.size.y / maxf(1.0, span.y)),
				_cam_min_zoom, CAM_MAX_ZOOM)
		_cam_target_center = (mn + mx) * 0.5
	# 유닛이 하나도 안 남았으면 마지막 타겟을 그대로 유지한다(화면이 튀지 않게).

	if snap:
		_cam_zoom = _cam_target_zoom
		_cam_center = _cam_target_center
	else:
		_cam_zoom = lerpf(_cam_zoom, _cam_target_zoom,
				1.0 - exp(-CAM_ZOOM_RATE * delta))
		_cam_center = _cam_center.lerp(_cam_target_center,
				1.0 - exp(-CAM_POS_RATE * delta))
	# 줌이 보간 중이어도 매 프레임 다시 가둔다 — 축소되는 동안 벨트 밖이
	# 잠깐 노출되는 것을 막는다.
	_cam_center = _clamp_cam_center(_cam_center, _cam_zoom)

	_world.scale = Vector2(_cam_zoom, _cam_zoom)
	_world.position = BAND_RECT.size * 0.5 - _cam_center * _cam_zoom


# 프레이밍 대상은 생존 유닛의 **발밑과 얼굴** 둘 다다 — 발밑만 넣으면 맨
# 윗줄의 얼굴이 밴드 위로 잘린다(사이드뷰 시절에는 뜼는 높이가 42 뿐이라
# 여백으로 덮였고, 지금은 82 다). **포탑은 넣지 않는다** — 무대 참가자가
# 아니라 지형이고, 프레임에 넣으면 무대 끝까지 담느라 배율이 떨어진다.
func _focus_positions() -> Array:
	var out: Array = []
	for raw in _sim.units:
		var u := raw as TurnEngageSim.EUnit
		if u.is_active():
			out.append(u.pos)
			out.append(u.pos - Vector2(0.0, UNIT_LIFT))
	return out


# 뷰가 무대 밖(= 그려진 것이 없는 곳)을 비추지 않도록 카메라 중심을 가둔다.
# 기준은 ground_rect 가 아니라 stage_rect — 초상이 발밑에서 UNIT_LIFT 만큼 띄어
# 있어 바닥면 딱 그만큼만 열어 두면 맨 윗줄 유닛의 얼굴이 잘린다. 뷰가 무대보다
# 넓은 축(= 최소 배율 근처)은 그냥 중앙에 고정한다.
static func _clamp_cam_center(c: Vector2, zoom: float) -> Vector2:
	var half: Vector2 = BAND_RECT.size / (2.0 * maxf(0.01, zoom))
	var stage := TurnEngageSim.stage_rect()
	var bc: Vector2 = stage.get_center()
	var bh: Vector2 = stage.size * 0.5
	var out := c
	if half.x >= bh.x:
		out.x = bc.x
	else:
		out.x = clampf(c.x, bc.x - bh.x + half.x, bc.x + bh.x - half.x)
	if half.y >= bh.y:
		out.y = bc.y
	else:
		out.y = clampf(c.y, bc.y - bh.y + half.y, bc.y + bh.y - half.y)
	return out


# 헤더는 두 줄이다 — 위는 라운드 카운터, 아래는 "지금 누구 차례인가".
# 실시간 시절의 남은 시간(MM:SS.s)은 라운드 개념에 의미가 없어 삭제됐다.
func _refresh_header() -> void:
	if _round_lbl != null:
		if _is_duel:
			_round_lbl.text = "라운드 %d" % _sim.round_index
			_round_lbl.add_theme_color_override("font_color", TIME_COLOR)
		else:
			_round_lbl.text = "라운드 %d / %d" % [_sim.round_index, _sim.total_rounds]
			_round_lbl.add_theme_color_override("font_color",
					TIME_LOW if _sim.round_index >= _sim.total_rounds else TIME_COLOR)
	if _phase_lbl == null or _preview:
		return
	if _end_banner != "":
		_phase_lbl.text = _end_banner
	elif _sim.finished:
		_phase_lbl.text = "교전 종료"
	elif _sim.flow == TurnEngageSim.Flow.ROUND_START:
		_phase_lbl.text = "라운드 %d 시작" % _sim.round_index
	else:
		var who: String = _sim.actor_label()
		_phase_lbl.text = "" if who == "" else "%s 의 차례" % who


# 매니저가 종료 판정 직후(대시보드가 뜨기 END_HOLD_SEC 전에) 부른다.
# 상태 라벨을 종료 사유 배너로 승격시키고 한 번 튕겨 준다 — 유예 시간 자체가
# "지금 뭔가 끝났다"를 알아채라는 연출이므로 시선을 한 번 끌어 줘야 한다.
func mark_engage_over(reason: String) -> void:
	_end_banner = reason
	if _phase_lbl == null:
		return
	_phase_lbl.text = reason
	_phase_lbl.add_theme_font_size_override("font_size", 30)
	_phase_lbl.add_theme_color_override("font_color", TITLE_COLOR)
	_phase_lbl.size = Vector2(ScreenMetrics.vp_w(), 40)
	_phase_lbl.pivot_offset = _phase_lbl.size * 0.5
	var tw := create_tween()
	tw.tween_property(_phase_lbl, "scale", Vector2(1.18, 1.18), 0.12) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(_phase_lbl, "scale", Vector2.ONE, 0.18) \
			.set_ease(Tween.EASE_IN_OUT)




# 시뮬레이터가 쌓아 둔 데미지 팝업을 Label 로 꺼내 띄우고 큐를 비운다.
func _drain_popups() -> void:
	for raw in _sim.popups:
		var e: Dictionary = raw
		_spawn_popup(e["pos"], String(e["text"]), e["color"])
	_sim.popups.clear()


# 팝업은 _world 의 자식(= 벨트 좌표계)이다. 카메라를 따라 움직이고 무대 밖에서
# 잘린다. 대신 월드 스케일까지 같이 먹으므로 글자 크기가 배율에 휘둘리지
# 않도록 1/zoom 을 되먹여 화면상 크기를 고정한다.
func _spawn_popup(at: Vector2, text: String, color: Color) -> void:
	var lbl := _make_label(text, 30, color, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size = Vector2(240, 40)
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2.ONE / maxf(0.01, _cam_zoom)
	lbl.position = Vector2(at.x - 120.0,
			at.y - UNIT_LIFT - TurnEngageSim.UNIT_RADIUS - 76.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(lbl)
	var rise: float = 54.0 / maxf(0.01, _cam_zoom)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", lbl.position.y - rise, 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))


# ─── 무대 렌더링 (벨트 좌표계 · _world 에 그린다) ────────────────────────────
func draw_world(c: CanvasItem) -> void:
	if _sim == null:
		return
	_draw_backdrop(c)
	_draw_floor(c)
	_draw_turrets(c)
	_draw_projectiles(c)
	_draw_units(c)


# 먼 배경 — 바닥면을 사방으로 `BG_BLEED` 만큼 더 그려 둔다. 카메라가 가장자리를
# 비출 때 빈칸이 생기지 않게 하는 것이 전부다. 사이드뷰 시절의 하늘 · 뒷벽 ·
# 지평선은 사라졌다 — 위에서 내려다보는 화면에는 수평선이 없다.
func _draw_backdrop(c: CanvasItem) -> void:
	var g := TurnEngageSim.ground_rect().grow(BG_BLEED)
	_draw_vgradient(c, g, GROUND_FAR, GROUND_NEAR, 14)


# 바닥 — 격자 + 무대 경계. **참가자가 밟고 있던 전장 칸의 육각 윤곽은 그리지
# 않는다**: 시작 자리가 타일의 *방향*만 반영하고 거리는 포화 곡선으로 압축된
# 지금(`TurnEngageSim._cell_offset`), 무대의 한 칸은 전장의 한 칸과 같은 크기가
# 아니다 — 육각을 그려 두면 그 그림이 있지도 않은 축척을 말하고, 유닛이 자기
# 칸 밖에 서 있는 것처럼 보인다. 배치가 무작위가 아님을 말하는 것은 이제 칸
# 윤곽이 아니라 **방향**이다(왼쪽 정글에서 온 정글러는 왼쪽에 선다).
func _draw_floor(c: CanvasItem) -> void:
	var g := TurnEngageSim.ground_rect()
	var step_x: float = TurnEngageSim.CELL_SPAN_X * 0.5
	var step_y: float = TurnEngageSim.CELL_SPAN_Y * 0.5
	var x: float = 0.0
	while x <= g.size.x + 0.5:
		c.draw_line(Vector2(x, -BG_BLEED), Vector2(x, g.size.y + BG_BLEED),
				FLOOR_LINE_COLOR, 1.5)
		x += step_x
	var y: float = 0.0
	while y <= g.size.y + 0.5:
		c.draw_line(Vector2(-BG_BLEED, y), Vector2(g.size.x + BG_BLEED, y),
				FLOOR_LINE_COLOR, 1.5)
		y += step_y
	c.draw_rect(g, EDGE_COLOR, false, 3.0)


static func _draw_vgradient(c: CanvasItem, rect: Rect2, top: Color,
		bottom: Color, steps: int) -> void:
	var n: int = max(1, steps)
	var band_h: float = rect.size.y / float(n)
	for i in n:
		var f: float = float(i) / float(max(1, n - 1))
		c.draw_rect(Rect2(rect.position.x, rect.position.y + band_h * float(i),
				rect.size.x, band_h + 1.0), top.lerp(bottom, f), true)


# 참가 포탑 — **무대 참가자가 아니라 지형**이다. 시뮬레이터가 자기 칸 위에
# 세우고(파일럿과 같은 칸→무대 매핑), 여기서는 유닛보다 먼저(= 뒤에) 그린다.
# 사거리원은 없다(사거리 제한 없음).
func _draw_turrets(c: CanvasItem) -> void:
	for raw in _sim.turrets:
		var t := raw as TurnEngageSim.ETurret
		var col: Color = TEAM_COLORS[t.team]
		var base: Vector2 = t.pos
		# 받침 — 바닥에 누운 타원 두 겹.
		_draw_ellipse(c, base + Vector2(0.0, 6.0),
				TURRET_BASE_R + Vector2(5.0, 3.0), Color(0, 0, 0, 0.34))
		_draw_ellipse(c, base, TURRET_BASE_R, TURRET_BODY_COLOR)
		_draw_ellipse_outline(c, base, TURRET_BASE_R,
				Color(col.r, col.g, col.b, 0.85), 3.0)
		# 탑신 — 위에서 본 육각 실루에을 살짝 띄워 놓는다.
		var top: Vector2 = base - Vector2(0.0, TURRET_LIFT)
		var body := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 + PI / 6.0
			body.append(top + Vector2(cos(a) * 26.0, sin(a) * 15.0))
		c.draw_colored_polygon(body, TURRET_BODY_COLOR)
		var outline := body.duplicate()
		outline.append(body[0])
		c.draw_polyline(outline, Color(col.r, col.g, col.b, 0.9), 3.0)
		# 포신 — 마지막으로 쌀 대상 쪽을 향한다. 대상이 없으면 무대 안쪽.
		var aim := Vector2(1.0 if t.team == 0 else -1.0, 0.0)
		if t.last_target != null:
			var d: Vector2 = t.last_target.pos - base
			if d.length_squared() > 1.0:
				aim = d.normalized()
		var tip: Vector2 = top + aim * 46.0
		c.draw_line(top, tip, Color(col.r, col.g, col.b, 0.9), 7.0)
		c.draw_circle(top, 11.0, Color(col.r, col.g, col.b, 0.9))
		# 사격 순간 — 총구 섬광.
		if t.fire_t > 0.0:
			var f: float = clampf(t.fire_t / 0.25, 0.0, 1.0)
			c.draw_circle(tip, 16.0 * f, Color(1.0, 0.85, 0.45, 0.85 * f))


func _draw_projectiles(c: CanvasItem) -> void:
	for raw in _sim.projectiles:
		var p: Dictionary = raw
		var f: float = clampf(float(p["t"]) / max(0.001, float(p["dur"])), 0.0, 1.0)
		var from: Vector2 = _shot_origin(p)
		var to: Vector2 = _shot_impact(p)
		var at: Vector2 = from.lerp(to, f)
		var col: Color = TEAM_COLORS[int(p["team"])]
		if bool(p["is_turret"]):
			col = Color(1.0, 0.72, 0.30)
			c.draw_line(from.lerp(to, max(0.0, f - 0.22)), at,
					col * Color(1, 1, 1, 0.55), 3.0)
			c.draw_circle(at, 9.0, col)
		else:
			c.draw_line(from.lerp(to, max(0.0, f - 0.18)), at,
					col * Color(1, 1, 1, 0.5), 2.5)
			c.draw_circle(at, 6.0, col)


# 투사체 좌표는 시뮬레이터가 발밑 기준으로 넘긴다 — 그림에서는 몸통 높이로
# 띄워야 발에서 발로 날아가는 그림이 되지 않는다.
static func _shot_origin(p: Dictionary) -> Vector2:
	var from: Vector2 = p["from"]
	if bool(p["is_turret"]):
		# 포탑의 포신 높이 — _draw_turrets 와 같은 값이라야 포격선이
		# 포신에서 출발한다.
		return from + Vector2(0.0, -TURRET_LIFT)
	return from + Vector2(0.0, -UNIT_LIFT)


static func _shot_impact(p: Dictionary) -> Vector2:
	return (p["to"] as Vector2) + Vector2(0.0, -UNIT_LIFT)


# 탑뷰라 **깊이(y) 순으로 정렬**해서 그린다 — 아래쪽(가까운) 유닛이 위에 겹친다.
# 시뮬레이터의 units 배열 순서는 팀별이라 그대로 그리면 원근이 깨진다.
func _draw_units(c: CanvasItem) -> void:
	var order: Array = _sim.units.duplicate()
	order.sort_custom(func(a, b):
		return (a as TurnEngageSim.EUnit).pos.y \
				< (b as TurnEngageSim.EUnit).pos.y)
	for raw in order:
		_draw_unit(c, raw as TurnEngageSim.EUnit)


# 유닛 하나는 **세 겹**이다 — 바닥에 누운 원(지상 위치) → 그 원을 가리키는
# 쉐기 → 떠 있는 원형 초상. 사이드뷰 시절에는 초상 옆에 "바라보는 좌우"를
# 가리키는 쉐기가 붙었는데, 탑뷰에서 읽혀야 하는 것은 방향이 아니라 **이 얼굴이
# 바닥 어느 지점에 서 있는가**다: 초상이 UNIT_LIFT 만큼 띄어 있으므로 그대로는
# 자기 자리를 가리키지 못하고, 바닥 원과 쉐기가 그 둘을 이어 준다.
func _draw_unit(c: CanvasItem, u: TurnEngageSim.EUnit) -> void:
	var dead: bool = (u.state == TurnEngageSim.State.DEAD)
	# 시신은 **투명해지지 않고 어두워진다** — 알파를 내리면 무대에서 겹쳐 선
	# 뒤 유닛이 시신을 뚫고 비쳐 둘 중 무엇을 보고 있는지가 흐려진다(탑뷰라
	# 겹침이 잦다). 밝기만 눌러 두면 시신이 불투명한 한 덩어리로 남는다.
	var dim: float = DEAD_DIM if dead else 1.0
	var col: Color = TEAM_COLORS[u.team]
	if dead:
		col = Color(col.r * DEAD_DIM, col.g * DEAD_DIM, col.b * DEAD_DIM)
	var r: float = TurnEngageSim.UNIT_RADIUS
	var body: Vector2 = u.pos + Vector2(0.0, -UNIT_LIFT)
	var gr := Vector2(GROUND_RX, GROUND_RY)

	# ① 바닥 위치 표식 — 그림자 → 면 → 테두리.
	_draw_ellipse(c, u.pos + Vector2(0.0, 4.0), gr + Vector2(5.0, 3.0),
			Color(0, 0, 0, 0.38))
	_draw_ellipse(c, u.pos, gr, Color(col.r, col.g, col.b, 0.30))
	_draw_ellipse_outline(c, u.pos, gr,
			Color(col.r, col.g, col.b, 0.95), 3.0)
	# [강습] 낙하 지점은 겹링으로 남긴다 — 이 한 명은 자기 타일이 아니라
	# 적 한가운데에 서 있고, 그게 이 카드의 값이다.
	if u.dropped_in and not dead:
		_draw_ellipse_outline(c, u.pos, gr + Vector2(11.0, 7.0),
				DROP_RING_COLOR, 2.0)

	# ② 쉐기 — 초상 밑변에서 바닥 원 윗변까지.
	var w_top: float = body.y + r + 3.0
	var w_bot: float = u.pos.y - GROUND_RY - 2.0
	if w_bot > w_top:
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(u.pos.x - PIN_HALF_W, w_top),
			Vector2(u.pos.x + PIN_HALF_W, w_top),
			Vector2(u.pos.x, w_bot),
		]), Color(col.r, col.g, col.b, 0.90))

	# ③ 행동 중 강조 — 지금 무대에 나와 있는 한 명.
	if not dead and u.is_acting():
		c.draw_arc(body, r + 10.0, 0.0, TAU, 40,
				Color(ACT_RING_COLOR.r, ACT_RING_COLOR.g, ACT_RING_COLOR.b,
						0.55), 4.0)

	# ④ 초상. 시신에는 **불투명한 받침 원**을 먼저 깐다 — `circle` 컷 일부는
	# 원 안쪽에 알파 구멍이 있어(전장 마커가 흰 원을 까는 것과 같은 이유)
	# 받침이 없으면 밝기를 눌러 놓아도 그 구멍으로 뒤 유닛이 비친다.
	if dead:
		c.draw_circle(body, r, Color(0.06, 0.07, 0.10, 1.0))
	var portrait: Texture2D = PilotImages.circle_for(u.pilot.pilot_id)
	if portrait != null:
		c.draw_texture_rect(portrait,
				Rect2(body - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, Color(dim, dim, dim, 1.0))
	else:
		c.draw_circle(body, r, col)

	# 팀색 테두리 — 빈사면 붉게 맥동한다.
	var rim: Color = col
	if not dead and u.hp_ratio() < LOW_HP_RATIO:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		rim = col.lerp(Color(1.0, 0.35, 0.30), 0.35 + 0.45 * pulse)
	c.draw_arc(body, r + 3.0, 0.0, TAU, 40, Color(rim.r, rim.g, rim.b, 1.0), 5.0)

	# ⑤ 피격 플래시.
	if u.hit_flash > 0.0:
		var k: float = u.hit_flash / TurnEngageSim.KNOCK_FLASH_SEC
		c.draw_circle(body, r + 6.0, Color(1.0, 0.35, 0.35, 0.45 * k))

	# ⑥ 공격 모션 — 근접은 휘두르는 호, 원거리는 총구 섬광. 방향은 `facing`
	# 백터에서 온다 — 좌우 부호 하나로는 위아래로 마주 선 둘을 구분할 수 없다.
	if u.swing_t > 0.0:
		var sw: float = clampf(u.swing_t / 0.22, 0.0, 1.0)
		var ang: float = u.facing.angle()
		if u.is_melee:
			c.draw_arc(body, r + 18.0, ang - 0.7, ang + 0.7, 18,
					Color(1.0, 0.95, 0.6, 0.85 * sw), 6.0)
		else:
			c.draw_circle(body + u.facing * (r + 10.0), 13.0 * sw,
					Color(1.0, 0.9, 0.55, 0.8 * sw))


static func _draw_ellipse(c: CanvasItem, at: Vector2, radii: Vector2,
		col: Color) -> void:
	c.draw_colored_polygon(_ellipse_points(at, radii), col)


static func _draw_ellipse_outline(c: CanvasItem, at: Vector2, radii: Vector2,
		col: Color, width: float) -> void:
	var pts := _ellipse_points(at, radii)
	var line := pts.duplicate()
	line.append(pts[0])
	c.draw_polyline(line, col, width)


static func _ellipse_points(at: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		pts.append(at + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


# ─── 화면 좌표계 렌더링 (_hud 에 그린다) ─────────────────────────────────────
func draw_hud(c: CanvasItem) -> void:
	if _sim == null:
		return
	# 무대 테두리 — "여기까지가 무대, 밖은 잘려 있다"를 명시한다.
	c.draw_rect(BAND_RECT.grow(2.0), Color(0.0, 0.0, 0.0, 0.55), false, 6.0)
	c.draw_rect(BAND_RECT, BAND_FRAME, false, 2.0)
	_draw_round_pips(c)


const ROUND_BAR_W: float = 560.0
const ROUND_BAR_H: float = 12.0
const ROUND_BAR_Y: float = 350.0
## 라운드 칸 사이 간격.
const ROUND_PIP_GAP: float = 6.0
## 이 개수를 넘으면 칸으로 나누는 대신 연속 바로 그린다 — 칸이 실처럼 가늘어져
## 오히려 몇 라운드인지 안 읽힌다. 결투(상한 10라운드)가 여기 걸린다.
const ROUND_PIP_MAX: int = 8

# 남은 시간 바를 대체한 **라운드 칸 표시**. 라운드 하나가 칸 하나이고, 지금
# 라운드까지 채워진다. 결투처럼 라운드 예산이 의미 없는 경우는 그리지 않는다.
func _draw_round_pips(c: CanvasItem) -> void:
	if _is_duel:
		return
	var x0: float = (ScreenMetrics.vp_w() - ROUND_BAR_W) * 0.5
	c.draw_rect(Rect2(x0, ROUND_BAR_Y, ROUND_BAR_W, ROUND_BAR_H),
			Color(0.10, 0.11, 0.16, 0.95), true)
	var n: int = max(1, _sim.total_rounds)
	var done: int = clampi(_sim.round_index, 0, n)
	if n <= ROUND_PIP_MAX:
		var pip_w: float = (ROUND_BAR_W - ROUND_PIP_GAP * float(n - 1)) / float(n)
		for i in n:
			var px: float = x0 + (pip_w + ROUND_PIP_GAP) * float(i)
			c.draw_rect(Rect2(px, ROUND_BAR_Y, pip_w, ROUND_BAR_H),
					Color(0.45, 0.80, 0.95) if i < done
							else Color(0.20, 0.23, 0.32, 0.95), true)
	else:
		c.draw_rect(Rect2(x0, ROUND_BAR_Y,
				ROUND_BAR_W * float(done) / float(n), ROUND_BAR_H),
				Color(0.45, 0.80, 0.95), true)
	c.draw_rect(Rect2(x0, ROUND_BAR_Y, ROUND_BAR_W, ROUND_BAR_H),
			Color(0.4, 0.45, 0.6, 0.8), false, 1.5)


# ─── 하단 초상화 스트립 (_roster 에 그린다) ──────────────────────────────────
# 교전 참가자 전원이 **한 줄**에 선다 — 아군 왼쪽 / 적군 오른쪽, 가운데는 VS.
# 초상화 아래에 체력 바(+보호막)가 붙는다.
func draw_roster(c: CanvasItem) -> void:
	if _sim == null:
		return
	for t in range(2):
		var team_units: Array = _sim.units_of(t)
		for i in team_units.size():
			var u := team_units[i] as TurnEngageSim.EUnit
			var cx: float = _strip_cell_x(t, team_units.size(), i)
			# 막대는 초상화 **위**로 자라므로 먼저 그린다 — 겹칠 일은 없지만
			# 순서가 곧 "초상화에서 뻗어 나온 것"이라는 읽기다.
			if _result_mode:
				_draw_result_bar(c, u, cx)
			_draw_roster_cell(c, u, cx, STRIP_TOP)


func _draw_roster_cell(c: CanvasItem, u: TurnEngageSim.EUnit, cx: float,
		y: float) -> void:
	var p: PilotData = u.pilot
	var dead: bool = (u.state == TurnEngageSim.State.DEAD)
	var alpha: float = 0.35 if dead else 1.0
	var col: Color = TEAM_COLORS[u.team]
	var rect := Rect2(cx - STRIP_PORTRAIT_W * 0.5, y,
			STRIP_PORTRAIT_W, STRIP_PORTRAIT_H)

	# 초상 뒤판 — 죽으면 붉게 가라앉는다. 얼굴 크롭은 모브 실루엣처럼 알파가
	# 뚫리는 경우가 있어 뒤판이 없으면 딤드된 화면이 그대로 비친다.
	c.draw_rect(rect,
			Color(0.18, 0.09, 0.09, 0.95) if dead else Color(0.09, 0.11, 0.17, 0.95),
			true)

	# 얼굴 위주 **정사각** 썸네일(256×256). 칸도 정사각이라 비율이 안 깨진다.
	var portrait: Texture2D = PilotImages.face_for(p.pilot_id)
	if portrait != null:
		c.draw_texture_rect(portrait, rect, false, Color(1, 1, 1, alpha))
	else:
		c.draw_rect(rect, Color(col.r, col.g, col.b, alpha * 0.5), true)

	# 테두리 — 행동 중이면 금색으로 굵어진다(무대에 나와 있는 그 유닛이다).
	var acting: bool = not dead and u.is_acting()
	var rim: Color = ACT_RING_COLOR if acting else col
	c.draw_rect(rect, Color(rim.r, rim.g, rim.b, alpha), false,
			STRIP_RIM_ACT if acting else STRIP_RIM_IDLE)

	# 체력 바 — 초상화 바로 아래.
	var bar_x: float = cx - STRIP_HP_W * 0.5
	var bar_y: float = y + STRIP_PORTRAIT_H + STRIP_HP_GAP
	c.draw_rect(Rect2(bar_x, bar_y, STRIP_HP_W, STRIP_HP_H), HP_BAR_BG, true)
	var ratio: float = u.hp_ratio()
	var fill_w: float = STRIP_HP_W * ratio
	c.draw_rect(Rect2(bar_x, bar_y, fill_w, STRIP_HP_H),
			HP_BAR_FILL if ratio >= LOW_HP_RATIO else HP_BAR_LOW, true)
	# 보호막은 남은 체력 바 오른쪽에 이어 붙인다.
	if p.shield > 0 and p.max_hp > 0:
		var shield_w: float = STRIP_HP_W * clampf(
				float(p.shield) / float(p.max_hp), 0.0, 1.0)
		c.draw_rect(Rect2(bar_x + fill_w, bar_y, shield_w, STRIP_HP_H),
				SHIELD_FILL, true)
	c.draw_rect(Rect2(bar_x, bar_y, STRIP_HP_W, STRIP_HP_H),
			Color(0.4, 0.45, 0.6, 0.8), false, 1.5)


# ─── 결과 화면 ──────────────────────────────────────────
# **패널도 팝업도 아니다.** 무대(밴드) · 무대 테두리 · 라운드 칸 · 차례 배너를
# 걷어 내고, 교전 내내 서 있던 초상화 스트립만 그 자리에 남긴 채 딤드된 배경
# 위에서 그대로 성적표가 된다. 한 칸이 위에서부터 답하는 것은 —
#
#   준 피해(숫자) → 막대(안쪽 밑단에 처치 수) → 초상 → 남은 체력 → 번 성장치
#
# **받은 피해는 없앴다.** 교전이 끝난 뒤 되짚는 질문은 "누가 얼마나 해냈나"
# 하나이고, 맞은 양은 바로 밑의 남은 체력 바가 이미 그림으로 말하고 있다.
# 총 성장치도 없앴다 — 여기서 묻는 것은 총액이 아니라 **이 교전의 몫**이고,
# 총액은 전장 스트립과 파일럿 상세가 상시로 들고 있다.
#
# `result_text` 는 승리 / 패배 / 교전 결과 — 판정은 매니저가 한다(오브젝트
# 교전인지, 그 판정을 누가 들고 있는지를 아는 것이 그쪽이다).
func show_dashboard(result_text: String, on_confirm: Callable) -> void:
	set_process(false)
	_result_mode = true
	_clip.visible = false
	_hud.visible = false
	if _dim != null:
		_dim.color = RES_DIM_COLOR
	if _round_lbl != null:
		_round_lbl.visible = false
	if _phase_lbl != null:
		_phase_lbl.visible = false
	# 팀 이름 두 줄은 막대가 자리를 물려받는다 — 좌우와 색이 이미 팀을 말한다.
	for raw in _headers:
		(raw as Label).visible = false
	if _title_lbl != null:
		_title_lbl.text = result_text
		_title_lbl.add_theme_color_override("font_color",
				_result_color(result_text))
	_measure_dealt_range()
	_build_result_labels()
	_build_confirm_button(on_confirm)
	_roster.queue_redraw()


static func _result_color(text: String) -> Color:
	if text == RESULT_WIN:
		return RESULT_WIN_COLOR
	if text == RESULT_LOSE:
		return RESULT_LOSE_COLOR
	return RESULT_NEUTRAL_COLOR


## 막대 높이의 기준 — **이 교전에서 실제로 나온** 준 피해의 최소 · 최대.
## 절대 스케일을 쓰면 소규모 교전은 열 칸이 다 밑동만 남고 후반 교전은 다
## 천장에 붙어, 어느 쪽에서도 "누가 더 넣었나"가 안 읽힌다.
func _measure_dealt_range() -> void:
	_res_lo = 0.0
	_res_hi = 0.0
	var first: bool = true
	for raw in _sim.units:
		var v: float = _dealt_of((raw as TurnEngageSim.EUnit).pilot)
		if first:
			_res_lo = v
			_res_hi = v
			first = false
		else:
			_res_lo = minf(_res_lo, v)
			_res_hi = maxf(_res_hi, v)
	# 전원이 사실상 같은 값이면 기준선을 0 으로 내린다 — 안 그러면 "다 같이 많이
	# 넣은" 교전이 다 같이 밑동만 남은 그림이 된다.
	if _res_hi - _res_lo < 1.0:
		_res_lo = 0.0


func _dealt_of(p: PilotData) -> float:
	var s: Dictionary = _sim.stats.get(p, {})
	return float(s.get("dealt", 0))


## 준 피해 → 막대 높이. 0 은 밑동만 남기고, 그 위는 [최소, 최대] 를
## [RES_BAR_MIN_H, RES_BAR_MAX_H] 구간으로 편다.
func _bar_height(dealt: float) -> float:
	if dealt <= 0.0 or _res_hi <= 0.0:
		return RES_BAR_STUB_H
	var span: float = _res_hi - _res_lo
	var t: float = 1.0 if span <= 0.0 else clampf((dealt - _res_lo) / span, 0.0, 1.0)
	return RES_BAR_MIN_H + (RES_BAR_MAX_H - RES_BAR_MIN_H) * t


## 막대 한 칸 — 초상화 위로 자라는 준 피해량. 뒤판(최대 높이까지의 빈 기둥)은
## 깔지 않는다: 열 칸이 다 천장까지 회색이면 막대의 길이보다 그 기둥이 먼저
## 읽힌다. 시신의 막대는 어둡게 하지 않는다 — 죽기 전에 넣은 것도 넣은 것이다.
func _draw_result_bar(c: CanvasItem, u: TurnEngageSim.EUnit, cx: float) -> void:
	var h: float = _bar_height(_dealt_of(u.pilot))
	var r := Rect2(cx - RES_BAR_W * 0.5, RES_BAR_BOTTOM - h, RES_BAR_W, h)
	var col: Color = TEAM_COLORS[u.team]
	c.draw_rect(r, RES_BAR_BG, true)
	c.draw_rect(r, Color(col.r * 0.62, col.g * 0.62, col.b * 0.62, 0.95), true)
	c.draw_rect(r, col, false, 2.0)


func _build_result_labels() -> void:
	for t in range(2):
		var team_units: Array = _sim.units_of(t)
		for i in team_units.size():
			var u := team_units[i] as TurnEngageSim.EUnit
			var cx: float = _strip_cell_x(t, team_units.size(), i)
			var h: float = _bar_height(_dealt_of(u.pilot))
			# ① 막대 위 — 준 피해.
			var dmg := _make_label(fmt_damage(_dealt_of(u.pilot)), 24,
					Color(0.96, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
			dmg.position = Vector2(cx - STRIP_PORTRAIT_W * 0.5,
					RES_BAR_BOTTOM - h - 32.0)
			dmg.size = Vector2(STRIP_PORTRAIT_W, 30)
			add_child(dmg)
			# ② 막대 안쪽 밑단 — 처치 수. **0 은 적지 않는다**: 열 칸에 늘어선
			#    0 은 읽을 것 없는 자리를 채울 뿐이고, 없음이 곧 0 이다.
			var s: Dictionary = _sim.stats.get(u.pilot, {})
			var kills: int = int(s.get("kills", 0))
			if kills > 0 and h >= RES_KILL_H:
				var kl := _make_label("처치 %d" % kills, 17,
						Color(1.0, 0.95, 0.70), HORIZONTAL_ALIGNMENT_CENTER)
				kl.position = Vector2(cx - RES_BAR_W * 0.5,
						RES_BAR_BOTTOM - RES_KILL_H)
				kl.size = Vector2(RES_BAR_W, RES_KILL_H)
				add_child(kl)
			# ③ 체력 바 밑 — 이 교전에서 번 성장치.
			add_child(_growth_label(u.pilot, cx))


## 성장 줄 — `+2.15k`. 못 벌었으면 `—` 한 글자다(0.00k 은 자릿수만 차지한다).
func _growth_label(p: PilotData, cx: float) -> Label:
	var s: Dictionary = _sim.stats.get(p, {})
	var delta: float = p.score - float(s.get("score0", p.score))
	var gained: bool = delta > 0.005
	var text: String = ("+" + BattleSim.fmt_score(delta)) if gained else "—"
	var lbl := _make_label(text, 20,
			GROWTH_GAIN_COLOR if gained else GROWTH_FLAT_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	lbl.position = Vector2(cx - STRIP_PORTRAIT_W * 0.5, STRIP_SUB_Y)
	lbl.size = Vector2(STRIP_PORTRAIT_W, 24)
	# 가운데 정렬 Label 은 글자가 rect 보다 넓으면 정렬을 포기하고 옆 칸을
	# 침범한다 — 90px 칸에서는 clip 이 필수다.
	lbl.clip_text = true
	return lbl


## 확인 — 성장 줄 밑에 한 칸 띄우고 놓는다.
func _build_confirm_button(on_confirm: Callable) -> void:
	var btn := Button.new()
	btn.text = "확인"
	btn.add_theme_font_size_override("font_size", 28)
	btn.size = Vector2(RES_BTN_W, RES_BTN_H)
	btn.position = Vector2((ScreenMetrics.vp_w() - RES_BTN_W) * 0.5, RES_BTN_Y)
	btn.pressed.connect(on_confirm)
	add_child(btn)


## 막대 위 숫자 — 네 자리부터 `1.2k` 로 접는다. 칸이 62px 뿐이라 자릿수가 곧
## 길이가 되어, 큰 값 한 칸만 유난히 넓어지는 것을 막는다.
static func fmt_damage(v: float) -> String:
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


## 성장 줄의 색 — 이번 교전에서 번 성장치는 금색, 못 벌었으면 회색.
const GROWTH_GAIN_COLOR: Color = Color(1.0, 0.84, 0.36)
const GROWTH_FLAT_COLOR: Color = Color(0.62, 0.64, 0.70)
## 확인 버튼.
const RES_BTN_W: float = 260.0
const RES_BTN_H: float = 72.0
const RES_BTN_Y: float = STRIP_BOTTOM + 30.0


# ─── 보조 ────────────────────────────────────────────────────────────────────
func _make_label(text: String, font_size: int, color: Color,
		halign: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


# _draw 를 바깥으로 위임하기만 하는 껍데기 노드. draw_* 는 그 CanvasItem 이
# 그리기 상태일 때만 유효하므로, 아레나가 draw_fn 안에서 이 노드를 받아
# c.draw_*() 로 그린다.
#
# Control 이 아니라 Node2D 인 이유: Control 은 매 DRAW 통지마다 자기 크기로
# custom_rect 를 다시 박는다. 크기 0 인 Control 은 빈 사각형으로 컬링되어
# _draw 안의 그림이 통째로 사라진다. Node2D 는 실제 그린 커맨드에서 rect 를
# 잡으므로 카메라 변환 아래에서도 안전하다.
class DrawProxy extends Node2D:
	var draw_fn: Callable = Callable()

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)
