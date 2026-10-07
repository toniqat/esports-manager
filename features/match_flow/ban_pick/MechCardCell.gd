class_name MechCardCell
extends Control

# 메크 상세(`MechDetailPanel`)의 카드 격자 한 칸 — 축소한 카드(`scenes/Card.tscn`
# 인스턴스) · 투명 누름 버튼 · 장수 배지.
# **모양의 정본은 `MechCardCell.tscn`** (축소율 0.8 · 칸 크기 · 배지 위치).
#
# 누름 버튼은 **PASS** 다 — 정보 패널은 스크롤 안이라 STOP 이면 터치 드래그
# 스크롤이 끊긴다. 누르면 `tapped(card)` 로 알리고, 설명판은 패널이 띄운다.

signal tapped(card: Card)

const SCENE_PATH: String = "res://features/match_flow/ban_pick/MechCardCell.tscn"

const BADGE_COLOR := Color(0.92, 0.94, 1.0)
const BADGE_SPAWN_COLOR := Color(0.62, 0.70, 0.92)


static func create() -> MechCardCell:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechCardCell


func _ready() -> void:
	%Hit.pressed.connect(func() -> void: tapped.emit(%Card as Card))


## `def` — 메크 카드 행(`GameManager.mech_cards_for`). 트리에 들어간 **뒤에** 부른다 —
## Card.gd 의 @onready 참조는 트리에 들어간 뒤에야 풀린다.
func fill(def: Dictionary) -> void:
	(%Card as Card).setup(CardData.from_def(def), false, true)
	# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
	# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
	# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
	var cnt: int = int(def.get("count", 0))
	var badge: Label = %Badge
	badge.text = ("×%d" % cnt) if cnt > 0 else "생성 전용"
	badge.add_theme_color_override("font_color", BADGE_COLOR if cnt > 0 else BADGE_SPAWN_COLOR)
