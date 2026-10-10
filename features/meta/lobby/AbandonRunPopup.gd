class_name AbandonRunPopup
extends CanvasLayer

# 진행 중인 런을 포기할지 묻는 모달 — 홈 탭의 둥근 X(새 게임)가 연다. 딤 위 흰 카드:
# 제목 · **그 런의 요약**(국면 · 날짜 · 팀 · 트로피 · 순위 · 마지막 저장 — 홈 탭 런 카드와 같은
# 줄, `HomeTab.run_texts`) · 경고 본문 · 취소 / 포기하고 정산(위험 색).
#
# **레이아웃 · 스타일의 정본은 `UI_View_AbandonRunPopup.tscn`** — 이 스크립트는 `%노드` 에
# 글을 넣고 시그널만 잇는다. 고정 문구(제목 · 본문 · 버튼)는 씬의 key 리터럴이다.
#
#   var p := AbandonRunPopup.create()
#   add_child(p)
#   p.confirmed.connect(...)
#   p.open(SaveSystem.read_run_meta())

signal confirmed
signal cancelled

const SCENE_PATH: String = "res://features/meta/lobby/UI_View_AbandonRunPopup.tscn"


## 씬을 인스턴스한다(닫힌 채). `AbandonRunPopup.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> AbandonRunPopup:
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as AbandonRunPopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%Cancel.pressed.connect(close)
	%Confirm.pressed.connect(_on_confirm)
	# 파괴적 확인의 감촉(ERROR)은 부르는 쪽이 결과를 보고 낸다 — 자동 배선까지 울리면 두 번 떤다.
	HapticUi.mute(%Confirm)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `meta` = `SaveSystem.read_run_meta()` (the run being abandoned).
func open(meta: Dictionary) -> void:
	var tx: Dictionary = HomeTab.run_texts(meta, get_node("/root/GameManager"))
	%Phase.text = tx["phase"]
	%Date.text = tx["date"]
	%Team.text = tx["team"]
	%Trophies.text = tx["trophies"]
	%Record.text = tx["record"]
	%SavedAt.text = tx["saved_at"]
	_fit_safe_area()
	visible = true


func close() -> void:
	if not is_open():
		return
	visible = false
	cancelled.emit()


func is_open() -> bool:
	return visible


## 카드는 `%SafeArea` 한가운데 — 그 칸을 안전 영역으로 줄여 노치 / 제스처 띠를 피한다.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


func _on_confirm() -> void:
	visible = false
	confirmed.emit()


## F6 단독 실행 미리보기 — 손으로 쓴 런 메타 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(confirmed)
	UiPreview.trace(cancelled)
	open({"phase": 2, "year": 2, "month": 3, "day": 14, "weekday": 5, "team_id": 3,
			"trophies": 1, "rank": 2, "wins": 7, "losses": 3, "saved_at": "2026-10-11 12:34"})
