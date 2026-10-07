class_name ConfirmPopup
extends CanvasLayer

# 되돌릴 수 없는 행동 앞에서 한 번 더 묻는 모달. 화면 전체를 딤으로 덮어
# 뒤의 화면 입력을 막고, 가운데에 흰 카드 한 장(제목 · 본문 · 버튼 둘)을 띄운다.
#
# **두 번 누르기 버튼 대신 모달이다** — 런 포기처럼 진행 기록이 통째로 사라지는
# 행동은 "무엇이 사라지는가"를 글로 읽힌 뒤에 고르게 해야 한다. 같은 버튼을
# 두 번 누르는 방식은 그 설명을 담을 자리가 없다.
#
# **레이아웃의 정본은 `UI_View_ConfirmPopup.tscn` 이다.** 이 스크립트는 노드를 만들지
# 않고 `%이름` 노드에 글을 넣고 시그널만 잇는다 — 크기 · 색 · 간격은 에디터에서
# 고친다. 색 · 스타일박스는 `Root` 에 붙은 공용 테마(`resources/OutgameTheme.tres`)의
# 변형(`PopupCard` · `TitleLabel` · `SubLabel` · `GhostButton` · `PrimaryButton` · `DimPanel`)이
# 정한다. 코드가 정하는 것은 둘뿐: 안전 영역(`%SafeArea` 의 위아래 여백, 기기마다
# 다르다)과 `danger` 일 때 확인 버튼을 `DangerButton` 변형으로 바꾸는 것.
#
# 쓰는 법:
#   var p := ConfirmPopup.create()
#   add_child(p)
#   p.confirmed.connect(...)
#   p.open("제목", "본문", "취소", "확인", true)

signal confirmed
signal cancelled

const SCENE_PATH: String = "res://features/meta/lobby/UI_View_ConfirmPopup.tscn"


## 씬을 인스턴스한다. `ConfirmPopup.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> ConfirmPopup:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as ConfirmPopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%Cancel.pressed.connect(close)
	%Confirm.pressed.connect(_on_confirm)
	# 카드 위 누름은 딤까지 내려가 팝업을 닫으면 안 된다 — Card 는 씬에서 STOP.
	if UiPreview.is_standalone(self):
		_fill_preview()


## 팝업을 연다. `danger` 면 확인 버튼이 앰버 대신 빨간 색면이 된다 —
## 지우는 행동이 "다음으로 가는" 주 행동과 같은 색이면 안 된다.
func open(title: String, body: String, cancel_text: String,
		confirm_text: String, danger: bool = false) -> void:
	%Title.text = title
	%Body.text = body
	%Cancel.text = cancel_text
	%Confirm.text = confirm_text
	_apply_danger(danger)
	_fit_safe_area()
	visible = true


func close() -> void:
	if not is_open():
		return
	visible = false
	cancelled.emit()


func is_open() -> bool:
	return visible


## 카드는 `%SafeArea`(CenterContainer) 한가운데 선다. 그 칸을 안전 영역으로
## 줄여 노치 밑 / 제스처 띠 위로 버튼이 내려가지 않게 한다.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## 색은 테마 변형을 갈아 끼워 바꾼다 — 테마의 스타일박스는 모든 씬이 공유하므로
## 고쳐 쓰지 않는다. 글자 크기 override 는 노드에 있어 변형과 함께 유지된다.
func _apply_danger(danger: bool) -> void:
	var btn: Button = %Confirm
	btn.theme_type_variation = &"DangerButton" if danger else &"PrimaryButton"
	# 파괴적 확인의 감촉(ERROR)은 부르는 쪽이 결과를 보고 낸다 — 자동 배선까지
	# 울리면 한 누름에 두 번 떤다.
	if danger:
		HapticUi.mute(btn)
	else:
		HapticUi.kind(btn, HapticUi.up_kind)
		HapticUi.down_kind_for(btn, HapticUi.down_kind)


func _on_confirm() -> void:
	visible = false
	confirmed.emit()


## F6 단독 실행 미리보기 — 런 포기 확인(위험 버튼)으로 연다 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(confirmed)
	UiPreview.trace(cancelled)
	open(Loc.t(L.LOBBY_HOME_ABANDON_TITLE), Loc.t(L.LOBBY_HOME_ABANDON_BODY),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.LOBBY_HOME_ABANDON_CONFIRM), true)
