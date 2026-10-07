class_name SettingsPopup
extends CanvasLayer

# 설정 모달 (현지화 설계서 D10 · §10.4) — 로비 홈 탭 오른쪽 위 `설정` 버튼이 연다.
# 지금 내용은 언어 고르기 하나: `L.LOCALES` 한 줄에 버튼 하나, 각 언어 이름은 그 언어 자체
# 표기(`settings.locale.<code>` — 모든 로케일에서 같은 글)다.
#
# **이 팝업은 고르기만 한다** — 저장(`ProfileManager.set_locale`)과 현재 씬 다시 로드는
# 연 쪽(`HomeTab._on_locale_chosen`)이 `locale_chosen` 을 받아 한다. 지금 언어를 다시
# 누르면 신호 없이 닫힌다.
#
# **레이아웃의 정본은 `UI_View_SettingsPopup.tscn`** — 고정 글(제목 · 머리글 · 안내 · 닫기)은
# 씬에 key 리터럴로 있고 Control 자동 번역이 바꾼다. 코드는 언어 버튼 개수 · 글 · 선택
# 변형(`SelectableCardButton` ↔ `SelectableCardButtonOn`)과 안전 영역만 정한다.
#
# 쓰는 법:
#   var p := SettingsPopup.create()
#   add_child(p)
#   p.locale_chosen.connect(...)
#   p.open()

signal locale_chosen(code: String)
signal closed

const SCENE_PATH: String = "res://features/meta/lobby/UI_View_SettingsPopup.tscn"
const LANGUAGE_BUTTON_SCENE: String = "res://features/meta/lobby/UI_Comp_SettingsLanguageButton.tscn"

## 로케일 코드 → 그 언어 자체 표기 key. `L.LOCALES` 에 언어를 더하면 여기도 한 줄 더한다.
const LOCALE_NAMES: Dictionary = {   # l10n-keys: settings.locale.*
	"ko": L.SETTINGS_LOCALE_KO,
	"en": L.SETTINGS_LOCALE_EN,
}


## 씬을 인스턴스한다. `SettingsPopup.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> SettingsPopup:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as SettingsPopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	if UiPreview.is_standalone(self):
		_fill_preview()


func open() -> void:
	_sync_languages()
	_fit_safe_area()
	visible = true


func close() -> void:
	if not is_open():
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## 언어 버튼을 `L.LOCALES` 수에 맞춘다(씬의 미리보기 인스턴스를 다시 쓰고, 모자라면
## 아이템 씬을 더 만들고, 남으면 지운다). 지금 로케일 버튼이 선택 변형.
func _sync_languages() -> void:
	var box: Control = %Languages
	var items: Array = box.get_children()
	while items.size() > L.LOCALES.size():
		var extra: Node = items.pop_back()
		box.remove_child(extra)
		extra.queue_free()
	while items.size() < L.LOCALES.size():
		var item: Node = (load(LANGUAGE_BUTTON_SCENE) as PackedScene).instantiate()
		box.add_child(item)
		items.append(item)
	var current: String = TranslationServer.get_locale()
	for i in items.size():
		var code: String = L.LOCALES[i]
		var b: Button = items[i]
		b.text = Loc.t(String(LOCALE_NAMES.get(code, L.SETTINGS_LOCALE_EN)))   # l10n-dynamic: settings.locale.*
		b.theme_type_variation = &"SelectableCardButtonOn" if code == current \
				else &"SelectableCardButton"
		for c in b.pressed.get_connections():
			b.pressed.disconnect(c["callable"])
		b.pressed.connect(_on_language_pressed.bind(code))


func _on_language_pressed(code: String) -> void:
	if code == TranslationServer.get_locale():
		close()
		return
	visible = false
	locale_chosen.emit(code)


## 카드는 `%SafeArea`(CenterContainer) 한가운데 선다 — 노치 밑 / 제스처 띠 위로 버튼이
## 내려가지 않게 그 칸을 안전 영역으로 줄인다(`ConfirmPopup` 과 같은 틀).
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## F6 단독 실행 미리보기 — 실제 `L.LOCALES` 로 열고, 고르기 · 닫기는 출력만 한다
## (저장 · 씬 다시 로드는 연 쪽 몫이라 여기선 일어나지 않는다).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(locale_chosen)
	UiPreview.trace(closed)
	open()
