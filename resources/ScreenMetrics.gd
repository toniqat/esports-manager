class_name ScreenMetrics
extends RefCounted

# ── 화면 안전 영역 (세이프 에어리어) ─────────────────────────────────────────
#
# **이 프로젝트의 모든 세로 좌표는 여기를 지나야 한다.**
#
# 디자인 기준 화면은 1080×1920 이지만 실제 기기는 그 비율이 아니다. 스트레치
# 모드가 `expand` 라서(project.godot) **좁은 축은 기준값 그대로 남고 넓은 축만
# 늘어난다** — 세로로 긴 폰이면 가로는 정확히 1080 이고 세로만 1920 보다
# 커지며, 태블릿처럼 4:3 에 가까우면 세로가 1920 이고 가로가 넓어진다. 즉
# **뷰포트는 절대 기준값보다 작아지지 않는다.** 그래서 기존의 x 좌표 리터럴
# (1080 기준)은 폰에서 한 픽셀도 어긋나지 않고, 손봐야 하는 것은 세로다.
#
# 그 위에 OS 가 못 쓰게 막는 띠가 얹힌다:
#   * 위 — 노치 / 다이나믹 아일랜드 / 상태 표시줄
#   * 아래 — 아이폰 홈 인디케이터, 안드로이드 제스처 바
#
# 아래쪽이 특히 중요하다. 그 자리는 **가려지는 것이 아니라 터치를 빼앗긴다** —
# 홈으로 나가는 스와이프가 우선하므로 버튼을 두면 눌리지 않는 버튼이 된다.
#
# ## 쓰는 법
#
#     var top    := ScreenMetrics.top_y()      # 첫 번째로 쓸 수 있는 y
#     var bottom := ScreenMetrics.bottom_y()   # 마지막으로 쓸 수 있는 y
#     btn.position.y = bottom - btn.size.y - 20.0
#
# 화면 전체를 덮는 딤은 안전 영역이 아니라 **뷰포트 전체**를 써야 한다
# (`viewport_size()`) — 딤이 노치 밑을 안 덮으면 그 띠만 밝게 남는다.
#
# ## 노드가 필요 없는 이유
#
# 창의 루트 뷰포트를 직접 읽는다. 스트레치 변환이 걸리는 것이 그 뷰포트이므로
# 어느 노드에서 물어도 같은 답이고, 따라서 정적 함수로 충분하다. **단
# `SubViewport` 안에서는 답이 다르다** — 이 프로젝트는 UI 를 SubViewport 에
# 넣지 않으므로 문제가 없지만, 넣게 되면 그쪽은 이 표를 쓰면 안 된다.

## 디자인 기준 해상도. project.godot 의 viewport_width / height 와 같아야 한다.
const BASE_W: float = 1080.0
const BASE_H: float = 1920.0

## **안드로이드에서만** 아래쪽에 깔아 두는 최소 여백 — 뷰포트 높이 대비 비율.
## iOS 에는 걸지 않는다(아래 `_compute_insets` 주석 참조).
##
## 0.04 는 아이폰 홈 인디케이터에서 왔다: 세로 화면에서 34pt 를 잡아먹고
## 기준 화면이 852pt 이므로 3.99% 다. 안드로이드 제스처 핸들도 이 안에 든다.
## **비율로 두는 이유**는 화면이 길수록 인디케이터가 차지하는 절대 픽셀도
## 커지기 때문이 아니라, 고정 픽셀로 두면 뷰포트가 늘어난 만큼 여백이 상대적
## 으로 얇아져 긴 화면일수록 아슬아슬해지기 때문이다.
const FALLBACK_BOTTOM_RATIO: float = 0.04

## 안드로이드 10+ 제스처 내비게이션이 **뒤로 가기**로 가져가는 좌우 가장자리
## 폭(dp). 이 값은 `insets()` 에 **포함되지 않는다** — OS 가 안전 영역으로
## 보고하지도 않고, 여기서 빼 버리면 모든 안드로이드 기기에서 가로 48dp 를
## 그냥 버리게 된다. 가로 드래그가 여기서 **시작**되면 시스템이 가져간다는
## 경고용 수치이고, 소비자는 아래 `gesture_edge_w()` 하나뿐이다.
## 자세한 사정은 `docs/mobile_safe_area.md` 의 "좌우 가장자리" 절.
const GESTURE_EDGE_DP: float = 24.0

## 디버그 오버라이드를 읽는 환경 변수. `"좌,위,우,아래"` (뷰포트 단위).
## 예) `ESM_SAFE_AREA=0,150,0,90` — 윈도우에서 아이폰 인셋을 흉내 내 본다.
const ENV_OVERRIDE: String = "ESM_SAFE_AREA"

## 같은 프레임 안에서 수십 번 불리는 표라 캐시한다. 창 크기 / 뷰포트 크기가
## 바뀌면 키가 달라져 저절로 무효가 되므로 따로 지울 일이 없다.
static var _cache_key: Vector4i = Vector4i(-1, -1, -1, -1)
static var _cache_val: Vector4  = Vector4()


## 지금 뷰포트 크기 (스트레치가 먹은 뒤의 논리 좌표계).
static func viewport_size() -> Vector2:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return Vector2(BASE_W, BASE_H)
	return loop.root.get_visible_rect().size


static func vp_w() -> float:
	return viewport_size().x


static func vp_h() -> float:
	return viewport_size().y


## 안전 영역 인셋 — `(왼쪽, 위, 오른쪽, 아래)`, **뷰포트 단위**.
##
## `DisplayServer.get_display_safe_area()` 는 **네이티브 화면 픽셀**로 답하므로
## 그대로 쓰면 안 된다. 창 크기 대 뷰포트 크기의 비를 곱해 논리 좌표로 옮긴다.
static func insets() -> Vector4:
	var vp := viewport_size()
	var win := Vector2(DisplayServer.window_get_size())
	var key := Vector4i(int(vp.x), int(vp.y), int(win.x), int(win.y))
	if key == _cache_key:
		return _cache_val
	_cache_key = key
	_cache_val = _compute_insets(vp, win)
	return _cache_val


static func _compute_insets(vp: Vector2, win: Vector2) -> Vector4:
	var over: Variant = _override_insets()
	if over is Vector4:
		return over

	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4()

	var safe := DisplayServer.get_display_safe_area()
	var win_pos := Vector2(DisplayServer.window_get_position())
	# 헤드리스 / 데스크톱은 (0,0,0,0) 을 돌려준다 — 안전 영역이 없다는 뜻이
	# 아니라 물어볼 대상이 없다는 뜻이므로 "유효한 답"으로 취급하면 안 된다.
	var valid := safe.size.x > 0 and safe.size.y > 0
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if valid:
		l = maxf(0.0, float(safe.position.x) - win_pos.x)
		t = maxf(0.0, float(safe.position.y) - win_pos.y)
		r = maxf(0.0, (win_pos.x + win.x) - float(safe.position.x + safe.size.x))
		b = maxf(0.0, (win_pos.y + win.y) - float(safe.position.y + safe.size.y))
		# 네이티브 픽셀 → 뷰포트 단위.
		var sx := vp.x / win.x
		var sy := vp.y / win.y
		l *= sx
		r *= sx
		t *= sy
		b *= sy

	# **안드로이드에서만** 아래쪽에 하한을 건다.
	#
	# iOS 는 안전 영역을 UIView 에서 그대로 받아 오므로 믿는다 — 여기서 하한을
	# 걸면 홈 버튼 기기(아이폰 SE 계열, 아래 인셋이 정말 0)에서 화면 아래
	# 4% 를 근거 없이 버린다. 안드로이드는 제조사와 내비게이션 모드(제스처 /
	# 3버튼)에 따라 0 이 오는 경우가 실제로 있고, 그때 화면 맨 아래의 버튼은
	# 보이지만 **눌리지 않는다**. 공간을 조금 버리는 쪽이 못 누르는 버튼보다
	# 낫다는 판단이다.
	if OS.has_feature("android"):
		b = maxf(b, vp.y * FALLBACK_BOTTOM_RATIO)
	return Vector4(l, t, r, b)


## `ESM_SAFE_AREA` 환경 변수 또는 `-- --safe-area=l,t,r,b` 사용자 인자.
## 둘 다 없으면 `null`. 데스크톱에서 기기 인셋을 흉내 내 보는 유일한 방법이다.
static func _override_insets() -> Variant:
	var raw := OS.get_environment(ENV_OVERRIDE)
	if raw.is_empty():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--safe-area="):
				raw = a.substr("--safe-area=".length())
				break
	if raw.is_empty():
		return null
	var parts := raw.split(",", false)
	if parts.size() != 4:
		push_warning("ScreenMetrics: %s 는 'l,t,r,b' 네 값이어야 한다 — 무시한다: %s"
				% [ENV_OVERRIDE, raw])
		return null
	return Vector4(float(parts[0]), float(parts[1]),
			float(parts[2]), float(parts[3]))


## 뷰포트 좌표계에서의 안전 영역 사각형.
static func safe_rect() -> Rect2:
	var vp := viewport_size()
	var i := insets()
	return Rect2(Vector2(i.x, i.y),
			Vector2(maxf(1.0, vp.x - i.x - i.z), maxf(1.0, vp.y - i.y - i.w)))


## 위에서부터 처음으로 UI 를 놓아도 되는 y.
static func top_y() -> float:
	return insets().y


## 아래에서부터 마지막으로 UI 를 놓아도 되는 y. **터치 대상의 아래끝은 이
## 값을 넘으면 안 된다** — 넘으면 눌리지 않는 버튼이 된다.
static func bottom_y() -> float:
	return viewport_size().y - insets().w


static func left_x() -> float:
	return insets().x


static func right_x() -> float:
	return viewport_size().x - insets().z


## 가로 가운데. 하드코딩된 `1080.0 * 0.5` 를 대신한다 — 태블릿에서는 뷰포트가
## 1080 보다 넓어져 그 리터럴이 가운데가 아니게 된다.
static func center_x() -> float:
	return viewport_size().x * 0.5


## 배경판처럼 **안전 영역이 아니라 화면 전체**를 덮어야 하는 자식을, 부모가
## `indent_to_safe_top()` 으로 내려간 만큼 도로 위로 늘린다.
##
## 노치 · 다이나믹 아일랜드 자리는 "쓰면 안 되는 곳"이지 "비워 둘 곳"이 아니다.
## 배경까지 물러나면 그 띠만 엔진 기본 배경색으로 남아 화면이 잘린 것처럼
## 보인다 — 실제로 타이틀 화면 위쪽에 회색 띠가 생겼다.
##
## 전체 화면 앵커가 걸린 자식에만 쓴다(부모의 위끝에서 `top_y()` 만큼 위로).
static func extend_background(c: Control) -> void:
	if c != null:
		c.offset_top = -top_y()


## `indent_to_safe_top()` 으로 내린 **불투명한 전체 화면 판**이 비워 둔 위쪽
## 띠(노치 자리)를 같은 색으로 메운다.
##
## 판 자신을 위로 늘리면 안쪽 좌표계가 함께 움직여 내용이 도로 노치 밑으로
## 들어간다. 그래서 판은 그대로 두고 **판의 첫 자식**으로 띠 한 장을 깐다 —
## 첫 자식이라 다른 내용보다 뒤에 그려지고, 판과 함께 사라진다.
static func backfill_top(panel: Control, color: Color) -> void:
	var t: float = top_y()
	if panel == null or t <= 0.0:
		return
	var r := ColorRect.new()
	r.name = "SafeTopBackfill"
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(0.0, -t)
	r.size = Vector2(viewport_size().x, t)
	panel.add_child(r)
	panel.move_child(r, 0)


## 안전 영역의 높이. **`indent_to_safe_top()` 로 내려놓은 화면의 "바닥"** 이
## 그 로컬 좌표계에서 갖는 y 이기도 하다 — 그 화면 안에서 하단 액션 바를 놓을
## 때 `bottom_y()` 가 아니라 이 값을 써야 한다(`bottom_y()` 는 뷰포트 좌표라
## 내려놓은 만큼 두 번 더해진다).
static func safe_h() -> float:
	var i := insets()
	return maxf(1.0, viewport_size().y - i.y - i.w)


## 전체 화면 Control 하나를 통째로 안전 영역 위끝까지 내린다.
##
## **화면의 상단 여백은 요소마다 따로 주는 것이 아니라 화면째 내려야 한다.**
## 제목만 내리면 그 아래 본문은 제자리에 남아 둘이 겹친다(실제로 타이틀 화면의
## 제목이 세이브 슬롯 카드 밑으로 들어갔다).
##
## 미는 수단은 `position` 이 아니라 **`offset_top`** 이다 — 전체 화면 앵커가
## 걸린 Control 의 `position` 은 다음 레이아웃 때 앵커가 덮어쓴다. 앵커가
## 풀리지 않는 자리(CanvasLayer 바로 아래)에서는 `offset_top` 이 곧 위치라
## 같은 한 줄이 양쪽에 다 맞는다.
static func indent_to_safe_top(c: Control) -> void:
	if c != null:
		c.offset_top = top_y()


## 1080×1920 으로 그려진 **화면 한 장**을 지금 뷰포트에 얹을 때 세로로 밀 양.
##
## 전체 화면 모달처럼 세로 1920 을 통째로 쓰도록 구성된 화면에 쓴다. 안전 영역
## 안에서 가운데로 놓되 위아래 어느 쪽으로도 삐져나가지 않게 잡아 둔다 —
## 상수를 하나씩 기기 대응으로 고치는 대신 **상자째 미는 것**이라 그 화면 안의
## 픽셀 관계가 통째로 보존된다.
##
## 안전 영역이 1920 보다 좁으면(= 담을 수 없으면) 위를 맞추고 아래를 포기한다.
## 위쪽에는 대개 제목이 있고 아래쪽에는 여백이 있으므로, 잘려야 한다면 아래가
## 잘리는 편이 낫다.
static func design_offset_y() -> float:
	var i := insets()
	var vp := viewport_size()
	var lo: float = i.y
	var hi: float = vp.y - i.w - BASE_H
	if hi < lo:
		return lo
	return clampf((vp.y - BASE_H) * 0.5, lo, hi)


## 위와 같되 가로. 폰에서는 뷰포트 가로가 정확히 1080 이라 언제나 0 이고,
## 태블릿처럼 넓은 화면에서만 값이 생긴다.
static func design_offset_x() -> float:
	var i := insets()
	var vp := viewport_size()
	var lo: float = i.x
	var hi: float = vp.x - i.z - BASE_W
	if hi < lo:
		return lo
	return clampf((vp.x - BASE_W) * 0.5, lo, hi)


static func design_offset() -> Vector2:
	return Vector2(design_offset_x(), design_offset_y())


## 안드로이드 뒤로 가기 제스처가 가져가는 좌우 가장자리 폭(뷰포트 단위).
## 인셋이 아니라 **경고선**이다 — 여기서 시작하는 가로 드래그는 시스템에
## 먹힐 수 있다. 안드로이드가 아니면 0.
static func gesture_edge_w() -> float:
	if not OS.has_feature("android"):
		return 0.0
	var vp := viewport_size()
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0:
		return 0.0
	# dp → 네이티브 픽셀은 dpi/160 이다 (`screen_get_scale()` 은 안드로이드에서
	# 1.0 을 돌려주는 기기가 있어 못 쓴다).
	var density := maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	return GESTURE_EDGE_DP * density * (vp.x / win.x)
