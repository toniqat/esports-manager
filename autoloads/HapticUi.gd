extends Node

## 버튼의 햅틱을 **한 곳에서** 배선한다.
##
## 이 프로젝트에는 눌리는 것이 백 개가 넘고(화면 버튼 · 초상화 위에 얹은 투명
## 히트 버튼 · 필터 칩 · 딤 뒤판) 그 전부에 손으로 `Haptics.play(...)` 를 적으면
## 새로 만드는 버튼마다 빠뜨릴 자리가 하나씩 생긴다. 그래서 규칙을 뒤집는다 —
## **트리에 들어오는 모든 `BaseButton` 은 기본으로 감촉을 낸다**(`node_added`
## 하나가 그 자리다). 예외를 적는 쪽이 규칙을 적는 쪽보다 짧다.
##
## 세기를 바꾸거나 끄고 싶으면 버튼을 만드는 자리에서 한 줄:
##
## ```gdscript
## HapticUi.kind(btn, Haptics.Kind.MEDIUM)   # 확정 · 커밋 동작
## HapticUi.kind(btn, Haptics.Kind.SELECT)   # 값이 바뀔 뿐인 것 — 탭 · 필터
## HapticUi.mute(btn)                        # 같은 누름에 다른 데서 이미 낸다
## ```
##
## **감촉은 `pressed`(= 활성화) 에 붙는다. `button_down` 이 아니다** — 눌렀다가
## 손가락을 밖으로 빼면 아무 일도 안 일어나는데 감촉만 남으면 거짓말이 된다.
## `button_down` 에는 대신 `Haptics.prepare()` 가 붙는다: 손가락이 닿은 순간부터
## 떼는 순간까지가 정확히 탭틱 엔진을 깨울 여유다.
##
## 종류는 **누를 때 읽으므로** `kind()` 를 `add_child` 앞에 부르든 뒤에 부르든
## 같다. 자동 배선은 노드가 트리에 들어오는 순간 한 번만 걸린다.
##
## 데스크톱에서는 `Haptics` 가 통째로 no-op 이므로 이 층도 조용하다.

## `kind()` 에 넘기면 그 버튼만 감촉을 내지 않는다.
const NONE := -1

const _META := "haptic_kind"
const _META_BOUND := "haptic_bound"

## 종류를 안 적은 버튼이 내는 감촉. 눌렀다는 사실만 알리는 가장 작은 단위다.
## `Haptics` 는 오토로드라 상수 초기화 시점에는 없다 — `_ready` 에서 채운다.
var default_kind: int = NONE

## 이 층 전체를 끈다. `Haptics.enabled` 와는 다른 노브다 — 그쪽은 게임 전체,
## 이쪽은 "버튼 자동 배선"만이다.
var enabled: bool = true


func _ready() -> void:
	default_kind = Haptics.Kind.LIGHT
	get_tree().node_added.connect(_on_node_added)


## 이 버튼이 낼 감촉을 정한다. `Haptics.Kind.*` 또는 `HapticUi.NONE`.
func kind(btn: Object, k: int) -> void:
	if btn != null and is_instance_valid(btn):
		btn.set_meta(_META, k)


## 이 버튼은 감촉을 내지 않는다 — 같은 누름에 대해 다른 자리가 이미 내고 있을 때.
func mute(btn: Object) -> void:
	kind(btn, NONE)


func _on_node_added(node: Node) -> void:
	var btn := node as BaseButton
	if btn == null:
		return
	# 노드는 떼었다 다시 붙을 수 있고 그때 `node_added` 가 한 번 더 온다 —
	# 도장을 찍어 두 번 물리지 않게 한다(두 번 물면 한 번 눌러 두 번 울린다).
	if btn.has_meta(_META_BOUND):
		return
	btn.set_meta(_META_BOUND, true)
	btn.pressed.connect(_on_button_pressed.bind(btn))
	# 손가락이 닿는 순간 탭틱 엔진을 깨운다. 세션 첫 감촉은 안 그러면 눈에 띄게
	# 늦게 오고, 누르기 시작한 시점과 활성화 시점 사이가 정확히 그 여유다.
	btn.button_down.connect(_on_button_down)


func _on_button_down() -> void:
	if enabled:
		Haptics.prepare()


func _on_button_pressed(btn: BaseButton) -> void:
	if not enabled:
		return
	if not is_instance_valid(btn):
		return
	var k: int = int(btn.get_meta(_META, default_kind))
	if k == NONE:
		return
	Haptics.play(k)
