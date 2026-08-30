extends Node

## 버튼의 햅틱을 **한 곳에서** 배선한다.
##
## 이 프로젝트에는 눌리는 것이 백 개가 넘고(화면 버튼 · 초상화 위에 얹은 투명
## 히트 버튼 · 필터 칩 · 딤 뒤판) 그 전부에 손으로 `Haptics.play(...)` 를 적으면
## 새로 만드는 버튼마다 빠뜨릴 자리가 하나씩 생긴다. 그래서 규칙을 뒤집는다 —
## **트리에 들어오는 모든 `BaseButton` 은 기본으로 감촉을 낸다**(`node_added`
## 하나가 그 자리다). 예외를 적는 쪽이 규칙을 적는 쪽보다 짧다.
##
## ## 한 번 누르면 두 박자가 온다
##
## | 사건 | 기본 감촉 | 무엇을 말하는가 |
## |---|---|---|
## | `button_down` (손가락이 닿음) | `SOFT` | **뭉툭하게** — 닿았다 |
## | `pressed` (손가락을 뗌 = 활성화) | `RIGID` | **딱 끊기게** — 눌렸다 |
##
## 예전에는 `pressed` 한 박자뿐이었고 그 세기가 버튼마다 달랐다(주요 버튼
## MEDIUM · 탭 SELECT …). 그런데 감촉이 뗄 때만 오면 **누른 순간에는 아무 일도
## 안 일어난다** — 화면이 바뀌기 전까지 눌렸는지 확인할 길이 없다. 지금은 닿는
## 순간 물렁한 한 겹이 먼저 오고, 손을 뗄 때 **딱딱하게 끊기는** 톡이 그것을
## 닫는다. **두 박자의 순서는 한 번 뒤집혔다** — 예전에는 닿음이 `LIGHT`,
## 뗌이 `SOFT` 였다(가벼운 톡 → 뭉툭한 마감). 지금은 그 반대로, 무른 것이
## 먼저 오고 단단한 것이 닫는다: 딸깍이는 실물 버튼처럼 **끝이 또렷한 쪽이
## 활성화**를 맡아야 눌렸다는 사실이 손에 남는다.
##
## **세기 표는 그때 함께 폐기됐다.** 버튼은 종류와 무관하게 같은 두 박자를 낸다 —
## 무게를 감촉으로 나누던 자리(`OutgameTheme` 의 버튼 스타일 넷, 밴픽 필터 칩,
## 확정 버튼들)에서 `kind()` 호출이 전부 사라졌다. 확정인지 탭 전환인지는
## 화면이 말하는 것이고, 손에 오는 감촉이 화면마다 흔들리면 그것이 도리어
## 잡음이었다.
##
## **누름 박자는 취소될 수 있다.** 눌렀다가 손가락을 밖으로 빼면 `pressed` 가
## 안 오므로 뗌 박자가 없다 — 무른 한 겹만 남고 딱딱한 닫음이 없는 것이 곧
## "아무 일도 일어나지 않았다"이다. 그래서 또렷한 쪽을 뗄 때에 둔다.
##
## `button_down` 에는 `Haptics.prepare()` 도 함께 붙는다: 손가락이 닿은 순간부터
## 떼는 순간까지가 정확히 탭틱 엔진을 깨울 여유이고, 그 여유가 닫는 박자를
## 제때 오게 한다.
##
## ## 예외를 적는 법
##
## ```gdscript
## HapticUi.mute(btn)                            # 같은 누름에 다른 데서 이미 낸다
## HapticUi.kind(btn, Haptics.Kind.MEDIUM)       # 이 버튼만 뗄 때를 다르게
## HapticUi.down_kind_for(btn, HapticUi.NONE)    # 이 버튼만 누름 박자를 뺀다
## ```
##
## 종류는 **누를 때 읽으므로** 이 함수들을 `add_child` 앞에 부르든 뒤에 부르든
## 같다. 자동 배선은 노드가 트리에 들어오는 순간 한 번만 걸린다.
##
## 데스크톱에서는 `Haptics` 가 통째로 no-op 이므로 이 층도 조용하다.

## `kind()` / `down_kind_for()` 에 넘기면 그 박자를 내지 않는다.
const NONE := -1

const _META_UP := "haptic_kind"
const _META_DOWN := "haptic_down_kind"
const _META_BOUND := "haptic_bound"

## 손가락이 **닿을 때** 나는 감촉. 닿았다는 사실만 알리는 무른 한 겹이다.
## `Haptics` 는 오토로드라 상수 초기화 시점에는 없다 — `_ready` 에서 채운다.
var down_kind: int = NONE

## 손가락을 **뗄 때**(= 활성화) 나는 감촉. 딱 끊기며 닫는 한 톡이다.
var up_kind: int = NONE

## 이 층 전체를 끈다. `Haptics.enabled` 와는 다른 노브다 — 그쪽은 게임 전체,
## 이쪽은 "버튼 자동 배선"만이다.
var enabled: bool = true


func _ready() -> void:
	down_kind = Haptics.Kind.SOFT
	up_kind = Haptics.Kind.RIGID
	get_tree().node_added.connect(_on_node_added)


## 이 버튼이 **뗄 때** 낼 감촉을 정한다. `Haptics.Kind.*` 또는 `HapticUi.NONE`.
func kind(btn: Object, k: int) -> void:
	if btn != null and is_instance_valid(btn):
		btn.set_meta(_META_UP, k)


## 이 버튼이 **누를 때** 낼 감촉을 정한다. `Haptics.Kind.*` 또는 `HapticUi.NONE`.
func down_kind_for(btn: Object, k: int) -> void:
	if btn != null and is_instance_valid(btn):
		btn.set_meta(_META_DOWN, k)


## 이 버튼은 **두 박자 다** 내지 않는다 — 같은 누름에 대해 다른 자리가 이미
## 내고 있을 때(두 번 눌러야 지워지는 삭제 버튼처럼).
func mute(btn: Object) -> void:
	kind(btn, NONE)
	down_kind_for(btn, NONE)


func _on_node_added(node: Node) -> void:
	var btn := node as BaseButton
	if btn == null:
		return
	# 노드는 떼었다 다시 붙을 수 있고 그때 `node_added` 가 한 번 더 온다 —
	# 도장을 찍어 두 번 물리지 않게 한다(두 번 물면 한 번 눌러 두 번 울린다).
	if btn.has_meta(_META_BOUND):
		return
	btn.set_meta(_META_BOUND, true)
	btn.button_down.connect(_on_button_down.bind(btn))
	btn.pressed.connect(_on_button_pressed.bind(btn))


func _on_button_down(btn: BaseButton) -> void:
	if not enabled:
		return
	# 손가락이 닿는 순간 탭틱 엔진을 깨운다. 세션 첫 감촉은 안 그러면 눈에 띄게
	# 늦게 오고, 누르기 시작한 시점과 떼는 시점 사이가 정확히 그 여유다 —
	# 그 여유가 딱 끊기는 닫음을 제때 오게 한다.
	Haptics.prepare()
	_play_for(btn, _META_DOWN, down_kind)


func _on_button_pressed(btn: BaseButton) -> void:
	if not enabled:
		return
	_play_for(btn, _META_UP, up_kind)


func _play_for(btn: BaseButton, meta: String, fallback: int) -> void:
	if not is_instance_valid(btn):
		return
	var k: int = int(btn.get_meta(meta, fallback))
	if k == NONE:
		return
	Haptics.play(k)
