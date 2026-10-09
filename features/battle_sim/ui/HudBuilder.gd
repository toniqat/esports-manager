class_name HudBuilder
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# **HUD 의 노드 트리 · 자리 · 모양의 정본은 `UI_View_BattleHud.tscn` 이다** (+ 스트립
# `UI_Comp_PilotStrip.tscn` · 칸 `UI_Comp_PilotStripCell.tscn`). `build_ui()` 가 그 씬을 인스턴스해
# BattleSim 아래에 붙이고 `%이름` 노드를 묶는다. 이 스크립트가 정하는 것:
#   • 안전 영역 — 위 덩어리는 `top_offset()`, 아래 덩어리는 아래 인셋만큼 민다.
#   • 다른 모듈의 기하에서 나오는 자리 — 덱 / 버린 더미 뭉치(손패 행 · 거터),
#     전략 포인트 도넛(상대 손패 peek 아래끝 / 대상 지정 버튼 띠), 상대 손패 부채꼴.
#   • 데이터 색 — 차례 알림 띠(`TURN_BAR`)는 테마 변형 사본에 색만 넣는다.
#   • 상태 · 연출 — 갱신(`update_hud`), 드래그 중 비키기, 차례 알림 트윈, 결과 화면.
#
# 씬 안 **자식 순서가 곧 그리는 순서**다(`Canvas` 직속 — 시계 · 오브젝트 시계 · 아군
# 뒤판 · 아군 스트립 · 킬로그 · 뭉치 · 히트 버튼 · 도넛 · 예약 칩 · 미리보기 · 차례 알림).
# 다른 모듈이 그 뒤로 손패 카드 · 오버레이를 덧붙이고 `move_child` 로 끼워 넣으므로
# 순서를 바꾸면 손패가 스트립 뒤로 숨는 규칙(`player_strip_backdrop`) 등이 어긋난다.
const SCENE_PATH: String = "res://features/battle_sim/ui/UI_View_BattleHud.tscn"

# ── 안전 영역 오프셋 ─────────────────────────────────────────────────────────
# 아래의 모든 상수는 **1080×1920 디자인 화면**에 적힌 값 그대로이고, 실제 기기
# 대응은 그 값들을 건드리지 않고 **덩어리째 미는 것**으로 한다. 상단 패널 ↔
# 상대 손패 peek ↔ 적 도넛 ↔ 킬로그가 서로 픽셀 단위로 맞물려 있고(위 주석의
# "사슬"), 하단도 핸드 부채꼴 ↔ 카드 밑단 ↔ 아군 스트립이 마찬가지라, 상수를
# 하나씩 기기 대응으로 바꾸면 그 관계가 조용히 어긋난다. 스칼라 두 개면 관계는
# 전부 보존된다.
#
# 9:16 화면 · 인셋 0 이면 둘 다 0 이라 예전 배치와 한 픽셀도 다르지 않다.


## 상단 덩어리를 밀어 내리는 양 — 노치 / 다이나믹 아일랜드 / 상태 표시줄.
static func top_offset() -> float:
	return ScreenMetrics.top_y()


## 하단 덩어리를 밀어 내리는(음수면 올리는) 양 — 디자인 바닥(1920)과 실제
## 안전 바닥의 차. 화면이 길면 양수, 홈 인디케이터가 1920 안쪽을 파고들면
## 음수다.
static func bottom_offset() -> float:
	return ScreenMetrics.bottom_y() - ScreenMetrics.BASE_H

# ── 상단 패널 (시간 + 팀 점수 + 적 파일럿 스트립) ─────────────────────────────
# 예전에는 이 패널 하나가 열 명 전부를 84px 슬롯으로 담았다(아군 좌 / 점수 중앙 /
# 적 우). 지금은 **적 다섯만** 여기 있고, 아군 다섯은 핸드 행 아래로 내려갔다.
#
# 헤더 줄(y 4..38) 아래가 **스트립 띠**(y 46..127)이고 거기에 5px 를 더한 값이
# 이 높이다. 띠 안에서 적 스트립은 가운데 672px 만 쓰고, 남은 좌우 여백이
# **오브젝트 시계 두 칸**이다(`%ObjTimer0` · `%ObjTimer1`).
#
# **패널 높이는 내용이 정한다** — 헤더 + 스트립 띠 + 5px 여백, 그게 전부다.
# 예전 168 은 스트립이 아군과 같은 크기(1030×122)이던 시절의 값인데, 스트립이
# 60% 로 줄어든 뒤에도 그대로 남아 띠 아래에 27px 짜리 빈 칸이 붙어 있었다.
#
# 그 아래가 사슬이다 — 패널이 상대 핸드 peek 의 윗부분을 가리는 가림막이고,
# peek 카드 아래 끝에서 `DONUT_AI_HAND_GAP` 만큼 띄운 자리가 적 도넛이며, 그
# 도넛 아래가 곧 전장 픽셀 상단(y 369)이다. **패널 높이를 바꾸면
# `AI_HAND_TOP_Y`(= `TOP_PANEL_H − 50`) 와 `KillFeed.FEED_TOP`(= `TOP_PANEL_H
# + 8`) 을 같은 양만큼 함께 옮겨야 한다** — 전자를 두면 peek 이 패널 뒤로
# 통째로 숨거나(키울 때) 카드 윗부분이 그대로 드러나고(줄일 때), 후자를 두면
# 킬로그가 패널에서 떨어져 뜬다. 도넛은 `AI_HAND_TOP_Y` 에서 계산되므로 따로
# 만질 것이 없다.
#
# 132 로 줄면서 peek 이 82 로, 적 도넛 아래끝이 349 → 311 로 함께 올라왔다 —
# peek 이 드러나는 양(49px)은 그대로이고 전장 상단(369)까지의 여유만
# 20 → 58px 로 늘었다. 그 뒤 적 스트립이 20% 커지며 **148** 이 됐다(띠
# 46..143 + 5).
#
# **원형 초상 스트립으로 바뀌며 적 스트립 높이가 2배(100 → 200)가 되어 248** 이
# 됐고 사슬이 100px 씩 내려갔다 — peek 198, 적 도넛 아래끝 427, 킬로그 256.
# 도넛은 이제 전장 픽셀 상단(369)보다 아래로 내려오지만 화면 왼쪽 여백(x 9..121)
# 에 앉고, 육각 전장은 위쪽 꼭짓점이 가운데에만 있어 그 자리와 겹치지 않는다
# (실측 확인).
const TOP_PANEL_Y      := 0.0
const TOP_PANEL_H      := 248.0
# ── 씬이 갖는 자리 (`UI_View_BattleHud.tscn`, 1080×1920 디자인 값) ────────────────────
# 예전에 여기 있던 자리 상수(`ENEMY_STRIP_RECT` · `PLAYER_STRIP_RECT` · `OBJ_TIMER_*` ·
# `*_BG_PAD` · 시계 줄 · 성장치 폰트)는 씬 노드의 오프셋 · 테마 변형으로 옮겨 갔다.
# 값과 그 이유는 그대로다:
#
# • `%TimeLabel` (20, 4) 220×34 — 경과 시계 한 줄. **팀 합산 점수는 이 줄에서
#   삭제됐다**(아래 상단 chrome 주석).
# • `%EnemyPilotStrip` 1030×244, 가로 가운데, y 2..246 — **아군 스트립과 같은 크기**라
#   원 지름 · 흉상 · 성장치 배지가 위아래 똑같이 그려진다. 원은 칸 폭이 아니라 높이에서
#   지름이 정해지므로 실제 얼굴 다섯은 x ≈161..919 에만 서고, 그 바깥 좌우 여백에
#   오브젝트 시계가 앉는다. **아래끝(246)은 예전 806×200 시절과 같다** — 성장치 배지가
#   `TOP_PANEL_H` 바로 위에 서는 자리를 지키고 위로 자랐다. 그 아래 사슬(상대 핸드
#   peek · 적 도넛 · 킬로그)은 `TOP_PANEL_H` 에서 나오므로 그대로다. **성장치 폰트는
#   아군과 같다**(`PilotStripScoreLabel`) — 그 숫자는 내 것과 **나란히 견주라고** 있다.
# • `%EnemyStripBackdrop` — 적 스트립을 사방 10px 넓힌 판. **아군 뒤판과 같은 규칙**이지만
#   아래쪽만은 `TOP_PANEL_H` 에 맞춰 잘린다 — 그 아래 사슬이 전부 그 값에서 나오기 때문.
# • `%ObjTimer0` · `%ObjTimer1` 101×60, y 110, 좌우 26 — 스트립 양옆의 남은 여백.
#   **세로는 적 초상 원의 중심에 맞춘다**(원 중심 y ≈ 140). 한때는 스트립 띠 전체를
#   썼는데 — 아이콘이 클수록 곁눈으로 읽힌다는 이유였다 — 그러면 시계가 초상화보다
#   위아래로 튀어나와 가장 큰 물체가 되고, 정작 얼굴 쪽으로 가야 할 시선을 먼저
#   잡아챈다. 오른쪽은 오른쪽 끝에 앵커 — 예전의 `OBJ_TIMER_RIGHT_X = 953` 은 가로가
#   1080 보다 넓어질 수 있게 되면서 가운데 정렬을 깨뜨렸다.
# • `%PlayerPilotStrip` 1030×244, 화면 아래끝에서 276 위(1080×1920 에서 y 1644) —
#   원형 초상으로 바뀌며 높이가 2배(122 → 244)가 됐고, 바닥(1888)은 그대로 두고 위로
#   자랐다. 그만큼 핸드 행(`BattleSim.BS_HAND_CENTER.y`)도 1440 → **1370** 으로 70px
#   올렸다 — 최악 카드 밑단 ≈ 1633 이 뒤판 위끝(1634) 바로 위에 선다. (옛 값 y 1766 은
#   카드 밑단에서 계산해 나온 값이다 — 부채꼴 양 끝 카드가 가장 많이 처지고 호버 시
#   `Card.HOVER_SCALE` 로 커지므로. 아이폰 홈 바를 위해 바닥 ~32px 도 남긴다.)
# • `%PlayerStripBackdrop` — 아군 스트립을 사방 10px 넓힌 판(y 1634..1898).
#
# **STRIP_BACKDROP_NOTE — 두 스트립의 뒤판은 이제 투명하다**(`HudStripBackdrop`).
# 그래도 `Panel` 노드는 남긴다: 아군 뒤판은 `CardPhaseManager` 가 내 차례가
# 아닐 때 손패를 그 뒤로 내려보내는 z-order 기준이자 내려갈 깊이를 재는 자이고
# (`player_strip_backdrop[_top]`), 적 뒤판은 `set_strip_visible` 이 함께 숨기는
# 짝이다. 판이 투명해진 만큼 물러난 손패와 상대 핸드 peek 의 윗부분은 더 이상
# 가려지지 않고 초상화 **뒤로** 비친다(초상화는 여전히 그 위에 그려진다).

# ── AI hand peek (below score panel) ─────────────────────────────────────────
# AI hand is shown as a fan of card-back nodes whose tops are tucked behind the
# score panel — only the bottom strip of each card protrudes, giving an "edge of
# the cards" look that conveys hand size.
#
# The fan is the player hand's fan **flipped top-to-bottom**: every card centre
# rides one circle whose pivot sits *above* the row, so the middle card reaches
# the lowest point of the arc (it protrudes furthest down past the panel) and
# both ends curl back up under it. Card tilt is the negated arc angle, which
# mirrors the player fan's lean without standing the cards on their heads.
#
# Geometry, per card i of n (θ measured from straight-down at the pivot):
#   θ_i    = (i − (n−1)/2) · step
#   centre = pivot + R·(sin θ, cos θ)          ← +cos, so θ=0 is the LOWEST point
#   tilt   = −θ_i
# Adjacent centres therefore sit R·sin(step) apart; at the values below that is
# ~34.6 px against a 72 px card, i.e. the cards overlap by a bit over half.
const AI_HAND_SCALE  := 0.45
## Top of the MIDDLE card; the rest ride higher. Tied to TOP_PANEL_H — the panel
## must hide the card's top 50 px so only the bottom ~49 px peeks out, so this is
## `TOP_PANEL_H − 50`. Move the panel and this moves with it.
const AI_HAND_TOP_Y  := 198.0
## Circle radius (px) the card centres ride. Larger = flatter arc.
const AI_HAND_FAN_RADIUS := 620.0
## Angular step (deg) per card. Sets the horizontal overlap via R·sin(step).
const AI_HAND_FAN_STEP_DEG := 3.2
## Hard cap on the fan's total angular width. Without it a full hand would swing
## its end cards so far up the arc that they vanish behind the score panel — at
## 28° the outermost card rides only R·(1−cos 14°) ≈ 18 px above the middle one.
const AI_HAND_FAN_MAX_SPREAD_DEG := 28.0

# ── 전략 포인트 도넛 (cost gauges) ────────────────────────────────────────────
# The old bottom cell-bar stack and the rectangular 단계 넘기기 button are gone.
# Both sides now read out on a ring gauge in the **left-hand** gutter (the
# targeting overlay's 확인 / 취소 row owns the bottom-right corner):
#   player — above the Deck counter, top-left of the hand row; tapping it
#            swaps in the 턴 넘기기 hold panel (CostDonut + TurnEndPanel).
#   enemy  — top-left of the screen, just under the AI hand peek.
const DONUT_FILL_PLAYER: Color = BattleTheme.TEAM_DONUT[0]
const DONUT_FILL_ENEMY: Color = BattleTheme.TEAM_DONUT[1]
## Vertical gap between the player donut and the targeting overlay's
## 취소 / 확인 button row, which itself hovers just above the hand row. Keeping
## the donut clear of that band means the two never overlap mid-targeting.
const DONUT_HAND_GAP    := 24.0
## Vertical gap between the AI hand peek's bottom edge and the enemy donut.
const DONUT_AI_HAND_GAP := 20.0
## Left edge of the 턴 넘기기 panel (`TurnEndPanel`) at rest — it stands where the
## player donut was, vertically centred on the donut.
const TURN_END_PANEL_LEFT := 12.0
# ── 파일럿 스트립 refs ────────────────────────────────────────────────────────
var _enemy_strip:  PilotStrip = null   # team 1, 화면 상단
var _player_strip: PilotStrip = null   # team 0, 핸드 행 아래
## 아군 스트립 뒤판. 스트립과 **함께** 숨어야 한다 — 상세 패널이 스트립만
## 치우면 빈 판이 딤 위에 덩그러니 남는다.
var _player_strip_bg: Panel = null
## 드래그 중 아군 스트립 하강(`set_player_strip_dropped`).
const STRIP_DRAG_DROP := 120.0
const STRIP_DRAG_DIM := BattleTheme.STRIP_DRAG_DIM
const STRIP_DRAG_TIME := 0.18
var _player_strip_rest_y: float = NAN
var _strip_drop_tween: Tween = null
## 상단 적 UI(적 스트립 + 뒤판 + 상대 손패 peek)만 담는 전용 층. 평소에는
## `_bs.canvas` 와 같은 층 번호(1)에 **바로 앞 형제**로 서서 캔버스의 모든 것
## (턴 배너 · 날아가는 상대 카드 · 킬로그)보다 뒤에 그려진다 — 예전에 캔버스
## 자식 목록 맨 앞에 있던 것과 같은 순서다. 카드를 전장 쪽으로 끌면
## (`set_enemy_top_raised`) 층째 위로 비켜 올라가며 어두워지고, 그동안은 층 번호를
## `ENEMY_TOP_RAISED_LAYER`(-1)로 내려 **전장 타일 · 파일럿 초상(루트 캔버스,
## 층 0) 아래**에 깔린다 — 겨누는 동안 화면의 우선순위는 전장이다.
var _enemy_top_layer: CanvasLayer = null
const ENEMY_TOP_LAYER := 1
const ENEMY_TOP_RAISED_LAYER := -1
## 올라가는 양 — 아군 스트립이 내려가는 양(`STRIP_DRAG_DROP`)과 같다.
const ENEMY_TOP_RAISE := STRIP_DRAG_DROP
var _enemy_top_tween: Tween = null
## 적 스트립 뒤판. 같은 이유로 스트립과 함께 숨는다. 예전에는 화면 가로를 통째로
## 덮는 상단 패널이 그 자리였다 — `_bind_top_panel` 주석 참조.
var _enemy_strip_bg: Panel = null
## 아군 도넛 위 예약 칩(`ReservationChips`).
var _reserve_chips: ReservationChips = null
## 적 스트립 좌우의 오브젝트 등장 시계 — 좌 전령 / 우 용.
var _obj_timers: Array = []           # Array[ObjectiveTimer]

# ── Deck / Discard 카운터 히트 버튼 ───────────────────────────────────────────
# 뭉치 위에 얹힌 투명 버튼(`%DeckButton` · `%DiscardButton`). 누르면 CardPileViewer 가
# 그 더미의 카드를 목록으로 펼친다 (작전 단계 한정 — _update_pile_buttons 가 활성 상태를 관리).
var _btn_deck_view:    Button = null
var _btn_discard_view: Button = null

# ── Center labels ────────────────────────────────────────────────────────────
var _lbl_time: Label = null


# ── AI hand peek refs ────────────────────────────────────────────────────────
# `%AiHand` is the first child of `EnemyTopLayer`, so the strip backdrop and the
# enemy strip z-order above it (the backdrop used to visually clip the cards' top).
var _ai_hand_root:        Control = null
var _ai_card_back_nodes:  Array   = []   # Array<Card> — face-down cards

# ── Turn announcer refs ──────────────────────────────────────────────────────
# Centre-screen "당신의 차례 / 상대 차례" banner shown when CARD_PHASE starts
# (player) or before the AI's run_ai_plays loop (enemy). It is the canvas's last
# scene child, so it z-orders above every other HUD element including the AI hand.
var _turn_announce_root: Control = null
var _turn_bar: Panel = null
var _turn_label: Label = null
## 진행 중인 알림 회차 — 앞 알림이 끝나기 전에 새 알림이 오면 앞 것의 남은 단계가
## 같은 노드를 건드리지 않게 한다(예전에는 노드를 새로 만들어 앞 것을 지웠다).
var _announce_gen: int = 0
var _announce_tween: Tween = null


func build_ui() -> void:
	# 씬 하나에 층 셋(EnemyTopLayer · Canvas · VictoryLayer). 같은 층 번호(1)의
	# CanvasLayer 끼리는 형제 순서가 그리는 순서라, 씬에서 EnemyTopLayer 가 Canvas
	# **앞에** 서 있어 캔버스보다 뒤에 그려진다(`_enemy_top_layer` 주석).
	var root: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	_bs.add_child(root)
	_bs.canvas = root.get_node("%Canvas") as CanvasLayer
	_enemy_top_layer = root.get_node("%EnemyTopLayer") as CanvasLayer

	_bind_ai_hand_peek(root)
	_bind_top_panel(root)
	_bind_player_strip(root)
	_bind_kill_feed(root)
	_bind_hand_indicators(root)
	_bind_cost_donuts(root)
	_bind_victory_panel(root)
	# 손패 미리보기 — 자식 순서가 아니라 z_index 로 손패 위에 선다.
	_bs.card_preview = root.get_node("%CardPlayPreview") as CardPlayPreview
	_bs.card_preview.setup(_bs)
	_bind_turn_announcer(root)


## 위 덩어리(노치 아래로) / 아래 덩어리(홈 인디케이터 위로)를 세로로 민다 — 씬의
## 디자인 오프셋은 그대로 두고 양쪽 오프셋을 같은 양만큼.
static func _shift_y(c: Control, dy: float) -> void:
	c.offset_top += dy
	c.offset_bottom += dy


## 아래 앵커 노드를 미는 양. 씬은 화면 아래끝에 붙어 있으므로(뷰포트가 길어지면
## 이미 따라 내려간다) 남은 것은 아래 인셋뿐이다 — `bottom_offset()` 과 같은 결과.
static func _bottom_inset_shift() -> float:
	return ScreenMetrics.bottom_y() - ScreenMetrics.vp_h()


# ── Deck / Discard 카드 뭉치 ─────────────────────────────────────────────────
# Live in the BS_HAND_AREA_MARGIN gutters on either side of the hand row.
# The pile rect spans y=BS_HAND_CENTER.y .. y=BS_HAND_CENTER.y + Card.CARD_H,
# so we centre the piles vertically across that same band.
#
# 그 띠는 손패 카드의 **확대 전** 크기다. 손패는 `CardPhaseManager.HAND_CARD_SCALE`
# 만큼 크게 그려지지만 확대의 기준점이 카드 한가운데라 **띠의 중심은 그대로**이고,
# 뭉치가 맞추는 것은 높이가 아니라 그 중심이다 — 그래서 손패 배율을 만져도 이
# 자리는 손대지 않는다. 자리는 손패 행의 기하(`BattleSim`)에서 나오므로 씬이 아니라
# 여기서 정한다(씬의 자리는 1080×1920 미리보기 값).
#
# 예전에는 이 자리에 `"Deck\n18"` 두 줄 Label 하나였다. 지금은 같은 rect 안에
# **앞으로 누운 카드 뭉치**(`CardPileStack`)를 그린다 — 뒷면이 위를 향한 채
# 겹쳐 쌓이고, 두께가 실제 장수에 비례하며, 장수는 맨 위 카드 뒷면에 찍힌다.
## 목록을 열 수 없는 상태에서 뭉치에 씌우는 알파.
const PILE_LABEL_DIM_ALPHA      := 0.45
# 예전에는 뒷면 안쪽에 더미별 accent 무늬(덱 보라 / 버린 더미 적갈)를 덧그렸다.
# 뭉치가 작아 그 액자가 무늬가 아니라 면에 얹힌 계조로 읽혀 삭제했다. 뭉치 아래
# 제목 라벨("Deck" / "Discard")도 삭제됐다 — 두 더미는 손패 양옆 자리로 갈린다.
func _bind_hand_indicators(root: Node) -> void:
	var hand_y: float = _bs.BS_HAND_CENTER.y
	var hand_h: float = Card.CARD_H
	var screen_w := get_viewport().get_visible_rect().size.x
	# BS_HAND_WIDTH_SCALE widens the card row past the nominal margin, so the
	# real gutter is whatever is left beside the hand — never wider than the
	# nominal margin, and never overlapped by the outermost card.
	var margin: float = min(_bs.BS_HAND_AREA_MARGIN,
			(screen_w - _bs.BS_HAND_WIDTH) * 0.5)
	# Inset a few px so the pile doesn't kiss the screen edge. 예전 라벨은 8px
	# 씩 물러났는데, 뭉치는 폭이 곧 카드 크기라 4px 만 남기고 최대한 넓게 쓴다.
	var inset: float  = 4.0
	var w: float      = max(1.0, margin - inset * 2.0)
	_bs.pile_deck = _place_pile_stack(root.get_node("%CardPileDeck") as CardPileStack,
			Vector2(inset, hand_y), Vector2(w, hand_h))
	_bs.pile_discard = _place_pile_stack(root.get_node("%CardPileDiscard") as CardPileStack,
			Vector2(screen_w - margin + inset, hand_y), Vector2(w, hand_h))

	# 두 뭉치는 눌러서 해당 더미의 카드 목록을 펼치는 버튼이기도 하다.
	# `CardPileStack` 은 스스로 MOUSE_FILTER_IGNORE 라 클릭을 받지 못하므로,
	# 뭉치 rect 를 그대로 덮는 투명 Button 이 입력만 가져간다.
	_btn_deck_view = _place_pile_button(root.get_node("%DeckButton") as Button,
			_bs.pile_deck, CardPileViewer.Pile.DECK)
	_btn_discard_view = _place_pile_button(root.get_node("%DiscardButton") as Button,
			_bs.pile_discard, CardPileViewer.Pile.DISCARD)
	_update_pile_buttons()


# `setup()` 은 size 에서 폰트 크기와 자리를 유도하므로 **size 를 넣은 뒤**에
# 불러야 한다.
func _place_pile_stack(pile: CardPileStack,
		at: Vector2, of_size: Vector2) -> CardPileStack:
	pile.position = at
	pile.size     = of_size
	pile.setup()
	return pile


# 뭉치 위에 얹는 투명 히트 버튼(씬에서 flat + alpha 0) — 뭉치의 생김새는
# 그대로 두고 클릭만 가로챈다.
func _place_pile_button(b: Button, anchor: Control, which: int) -> Button:
	b.position = anchor.position
	b.size = anchor.size
	b.pressed.connect(func() -> void: _on_pile_button_pressed(which))
	return b


func _on_pile_button_pressed(which: int) -> void:
	if _bs.card_pile_viewer == null:
		return
	if _bs.card_phase == null or not _bs.card_phase.can_browse_piles():
		return
	_bs.card_pile_viewer.open(which)


# 열람이 불가능한 상태(BATTLE 진행 중, 상대 차례, 다른 오버레이 활성)에서는
# 버튼을 비활성화하고 뭉치를 흐리게 해 "지금은 못 연다"를 보여 준다.
func _update_pile_buttons() -> void:
	var can: bool = _bs.card_phase != null and _bs.card_phase.can_browse_piles()
	if _btn_deck_view != null:
		_btn_deck_view.disabled = not can
	if _btn_discard_view != null:
		_btn_discard_view.disabled = not can
	if _bs.pile_deck != null:
		_bs.pile_deck.set_dimmed(not can)
	if _bs.pile_discard != null:
		_bs.pile_discard.set_dimmed(not can)


# ── 상단 chrome: 경과 시계 + 적 파일럿 스트립(뒤판) + 오브젝트 시계 둘 ───────
#
# **예전에는 화면 가로를 통째로 덮는 패널 한 장이었다.** 그 판이 헤더 줄과 적
# 스트립과 오브젝트 시계를 다 담고 있어서, 좌우 끝의 시계가 스트립과 같은 판
# 위에 얹힌 것으로 읽혔다 — 시계는 스트립의 일부가 아니라 전장의 사건을
# 세는 별개의 물건이다. 지금은 **아군 스트립과 같은 규칙**으로, 뒤판이
# 초상화 다섯 칸만 감싸고(`%EnemyStripBackdrop`) 시계 둘과 경과 시계는 그 바깥에
# 배경 없이 선다(`Canvas` 직속 — 뒤판을 옮겨도 따라오지 않는다).
#
# 뒤판은 **이제 투명하다**(스트립 배경 삭제 — `STRIP_BACKDROP_NOTE`). 예전에는
# 상대 핸드 peek 의 윗부분을 가리는 가림막이었지만 지금은 peek 윗부분이 초상화
# 뒤로 비친다. 그 아래 사슬(적 도넛 · 킬로그)은 `TOP_PANEL_H` 에서 나오므로 그대로다.
#
# **팀 합산 점수(`12.4k - 9.8k`)는 삭제됐다** — 같은 수를 스트립의 다섯 칸이
# 이미 낱개로 보여 주고 있고, 합계는 어느 쪽이 이기고 있는지를 한 줄로 말해
# 주는 대신 정작 누가 크고 있는지를 가렸다. `TOTAL_SCORE_FONT` 와
# `_lbl_total_score` 는 그때 함께 사라졌다.
func _bind_top_panel(root: Node) -> void:
	var top: float = top_offset()
	_enemy_strip_bg = root.get_node("%EnemyStripBackdrop") as Panel
	_shift_y(_enemy_strip_bg, top)

	# 경과 시계 — 왼쪽 끝, 배경 없이 외곽선으로 읽힘을 지킨다(`HudClockLabel`).
	_lbl_time = root.get_node("%TimeLabel") as Label
	_shift_y(_lbl_time, top)

	# 적 스트립도 **눌러서 상세 패널을 연다** — 아군과 같은 게이트(작전 단계),
	# 같은 내용(인게임 · 파일럿 · 메크). 상대 로스터는 이미 `match_ctx.enemy_roster`
	# 로 들어와 있어 `BattleSim.player_data_for` 가 그대로 찾아 준다.
	# 뒤판보다 **뒤에**(씬 자식 순서) 있어야 판이 얼굴을 덮지 않는다.
	_enemy_strip = root.get_node("%EnemyPilotStrip") as PilotStrip
	_shift_y(_enemy_strip, top)
	_enemy_strip.setup(_bs, 1)
	# 적은 탭 / 꾹 누르기 모두 상세 패널(스킬 말풍선은 아군만).
	_enemy_strip.pilot_tapped.connect(_on_pilot_strip_pressed)
	_enemy_strip.pilot_long_pressed.connect(_on_pilot_strip_pressed)

	# 오브젝트 등장 시계 — 스트립 **바깥** 좌우. 전령이 왼쪽 · 용이 오른쪽인 것은
	# 전장에서 두 오브젝트가 서는 칸의 좌우와 같다.
	_obj_timers.clear()
	for spec in [[ObjectiveSystem.Kind.HERALD, "%ObjTimer0"],
			[ObjectiveSystem.Kind.DRAGON, "%ObjTimer1"]]:
		var timer := root.get_node(String(spec[1])) as ObjectiveTimer
		_shift_y(timer, top)
		timer.setup(_bs, int(spec[0]))
		# 누르면 그 오브젝트의 보상 카드를 실물로 띄운다. 회피할 수 있는
		# 사건이므로 무엇을 주는지는 결판 전에 볼 수 있어야 한다.
		timer.timer_pressed.connect(_on_obj_timer_pressed)
		_obj_timers.append(timer)


func _on_obj_timer_pressed(kind: int) -> void:
	if _bs.objective_reward != null:
		_bs.objective_reward.toggle(kind)


# ── 하단 아군 스트립 ─────────────────────────────────────────────────────────
# 핸드 행 아래. 누르면 파일럿 상세 패널이 열린다 — 다만 **자기 작전 단계에만**
# 눌린다(`_update_pilot_strips` 가 버튼 활성 상태를 관리). 씬에서 뒤판이 스트립
# **앞에** 선다 — 형제 z-order 가 곧 자식 인덱스라, 뒤에 서면 판이 초상화를 덮는다.
func _bind_player_strip(root: Node) -> void:
	var dy: float = _bottom_inset_shift()
	_player_strip_bg = root.get_node("%PlayerStripBackdrop") as Panel
	_shift_y(_player_strip_bg, dy)
	_player_strip = root.get_node("%PlayerPilotStrip") as PilotStrip
	_shift_y(_player_strip, dy)
	_player_strip.setup(_bs, 0)
	# 아군 — 짧은 탭 = 스킬 말풍선(`SkillPopup`), 꾹 누르기 = 상세 패널.
	_player_strip.pilot_tapped.connect(_on_player_strip_tapped)
	_player_strip.pilot_long_pressed.connect(_on_pilot_strip_pressed)


## 아군 스트립 노드 — `SkillPopup` 이 스트립 높이의 누름이 칸인지 묻는다.
func player_strip() -> PilotStrip:
	return _player_strip


## 아군 초상 짧은 탭 — 그 초상 머리 위에 스킬 말풍선. 같은 초상이면 닫힌다.
func _on_player_strip_tapped(p: PilotData) -> void:
	if _bs.skill_popup == null or _player_strip == null:
		return
	var anchor: Variant = _player_strip.anchor_for(p)
	if anchor == null:
		return
	_bs.skill_popup.toggle(p, anchor as Vector2, _player_strip.global_position.y)


# ── 킬로그 ───────────────────────────────────────────────────────────────────
# 적 스트립 바로 아래, 화면 우측. 자리는 `KillFeed.setup` 이 정한다. **씬에서
# 시계 · 스트립보다 뒤에 선다** — 형제 z-order 가 곧 자식 인덱스다.
func _bind_kill_feed(root: Node) -> void:
	_bs.kill_feed = root.get_node("%KillFeed") as KillFeed
	_bs.kill_feed.setup(_bs)


func _on_pilot_strip_pressed(p: PilotData) -> void:
	if _bs.pilot_detail == null:
		return
	if not _bs.pilot_detail.can_open():
		return
	if _bs.skill_popup != null:
		_bs.skill_popup.close()
	_bs.pilot_detail.open(p)


## 아군 스트립 뒤판 노드. `CardPhaseManager` 가 두 가지로 읽는다 — 내 차례가
## 아닐 때 손패 카드를 **이 판보다 뒤로** 내려보낼 기준 노드이고(형제 z-order 가
## 곧 자식 인덱스다 — 그래서 `_bs.canvas` 의 직속 자식이다), 카드가 얼마나
## 내려가야 절반쯤 가려지는지를 재는 자다.
func player_strip_backdrop() -> Panel:
	return _player_strip_bg


## 그 뒤판의 위쪽 끝(y). 세이프 에어리어 오프셋이 이미 먹은 실제 좌표다.
## (HUD 를 세우기 전에는 안전 바닥 — 손패는 그 전에 깔리지 않는다.)
func player_strip_backdrop_top() -> float:
	if _player_strip_bg != null and is_instance_valid(_player_strip_bg):
		return _player_strip_bg.position.y
	return ScreenMetrics.bottom_y()


## 개시 전(정글 시작 선택) 동안 **지금 쓸 수 없는 HUD 를 걷는다** — 손패 행
## 양옆의 덱 / 버린 더미 뭉치(와 그 히트 버튼), 전략 포인트 도넛 둘, 상단
## 패널의 오브젝트 등장 시계 둘. 셋 다 아직 존재하지 않는 것을 0 으로 보여
## 주는 자리이고, 특히 손패 자리는 정글러 초상화가 통째로 쓴다.
##
## **파일럿 스트립과 상단 패널은 남는다** — 개시 직전에 양 팀 로스터를 다시
## 확인하는 것은 이 화면이 하는 일의 일부다.
func set_pregame_chrome_visible(on: bool) -> void:
	for node in [_bs.pile_deck, _bs.pile_discard, _btn_deck_view,
			_btn_discard_view, _bs.cost_donut, _bs.cost_donut_enemy, _reserve_chips]:
		var c := node as CanvasItem
		if c != null:
			c.visible = on
	for raw in _obj_timers:
		var t := raw as CanvasItem
		if t != null:
			t.visible = on


## 카드를 끄는 동안 아군 스트립을 **어둡게 하고 아래로 내린다**
## (`CardPhaseManager._drag_lowers_hand`) — 손패와 함께 비켜 전장을 비운다.
## `false` 면 제자리 · 제 밝기로 돌아온다. 뒤판(`_player_strip_bg`)은 움직이지
## 않는다 — 손패가 내려갈 깊이(`hand_drop_offset`)를 재는 자라 같이 움직이면
## 트윈 도중에 손패 목표가 흔들린다.
func set_player_strip_dropped(on: bool) -> void:
	if _player_strip == null or not is_instance_valid(_player_strip):
		return
	if is_nan(_player_strip_rest_y):
		_player_strip_rest_y = _player_strip.position.y
	# 스트립이 내려가면 말풍선 화살표가 허공을 가리킨다.
	if on and _bs.skill_popup != null:
		_bs.skill_popup.close()
	if _strip_drop_tween != null and _strip_drop_tween.is_valid():
		_strip_drop_tween.kill()
	_strip_drop_tween = _bs.create_tween().set_parallel()
	_strip_drop_tween.tween_property(_player_strip, "position:y",
			_player_strip_rest_y + (STRIP_DRAG_DROP if on else 0.0),
			STRIP_DRAG_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_strip_drop_tween.tween_property(_player_strip, "modulate",
			STRIP_DRAG_DIM if on else Color.WHITE, STRIP_DRAG_TIME)


## 카드를 전장 쪽으로 끄는 동안 상단 적 UI(적 스트립 · 상대 손패)를 **위로
## 비켜 올리고 어둡게** 한다 — 아군 쪽 `set_player_strip_dropped` 의 거울이다
## (`CardPhaseManager._drag_lowers_hand`). 올라가 있는 동안은 층째 전장 아래로
## 깔린다(`_enemy_top_layer` 주석). 돌아올 때는 제자리에 닿은 뒤에 층을 올린다
## — 중간에 올리면 아직 비켜 있는 판이 전장 초상 위로 튀어 오른다.
func set_enemy_top_raised(on: bool) -> void:
	if _enemy_top_layer == null or not is_instance_valid(_enemy_top_layer):
		return
	if _enemy_top_tween != null and _enemy_top_tween.is_valid():
		_enemy_top_tween.kill()
	if on:
		_enemy_top_layer.layer = ENEMY_TOP_RAISED_LAYER
	_enemy_top_tween = _bs.create_tween().set_parallel()
	_enemy_top_tween.tween_property(_enemy_top_layer, "offset:y",
			-ENEMY_TOP_RAISE if on else 0.0,
			STRIP_DRAG_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for node in _enemy_top_layer.get_children():
		var ci := node as CanvasItem
		if ci != null:
			_enemy_top_tween.tween_property(ci, "modulate",
					STRIP_DRAG_DIM if on else Color.WHITE, STRIP_DRAG_TIME)
	if not on:
		_enemy_top_tween.chain().tween_callback(func() -> void:
			_enemy_top_layer.layer = ENEMY_TOP_LAYER)


## 상세 패널이 열려 있는 동안 **그 파일럿이 속한 팀의 스트립**을 치운다 — 딤 위에
## 남으면 지금 무엇을 보고 있는지가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이
## 어두워진다. 반대 팀 스트립은 그대로 둔다(딤에 가려질 뿐이고, 치우면 화면에서
## 무엇이 사라졌는지가 더 헷갈린다).
func set_strip_visible(team: int, on: bool) -> void:
	var strip: PilotStrip = _player_strip if team == 0 else _enemy_strip
	if strip != null:
		strip.visible = on
	if team == 0 and not on and _bs.skill_popup != null:
		_bs.skill_popup.close()
	# 뒤판도 함께 숨긴다 — 스트립만 치우면 빈 판이 딤 위에 남는다. 두 스트립이
	# 각자 자기 뒤판을 가지므로 규칙이 위아래 같다.
	var bg: Panel = _player_strip_bg if team == 0 else _enemy_strip_bg
	if bg != null:
		bg.visible = on


# AI hand peek — row of face-down card backs whose tops hide behind the score
# panel. update_ai_hand_visuals() syncs the visible count to `_bs.ai_hand`.
func _bind_ai_hand_peek(root: Node) -> void:
	_ai_hand_root = root.get_node("%AiHand") as Control
	# 루트를 통째로 내리면 안쪽 부채꼴 좌표(`AI_HAND_TOP_Y` 기반)를 손대지 않고
	# 노치 아래로 옮겨진다.
	_shift_y(_ai_hand_root, top_offset())


# Sync `_ai_card_back_nodes` count with `_bs.ai_hand.size()` and reflow.
# Called from CardPhaseManager.do_battle_turn() after the AI draws, and from
# pop_ai_hand_card_node() after AiCardPlayer pulls a card out for the
# centre animation.
func update_ai_hand_visuals() -> void:
	if _ai_hand_root == null:
		return
	var n: int = _bs.ai_hand.size()
	while _ai_card_back_nodes.size() < n:
		var card := _bs.CARD_SCENE.instantiate() as Card
		card.scale = Vector2(AI_HAND_SCALE, AI_HAND_SCALE)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# add_child BEFORE setup — Card.gd's @onready refs only resolve after
		# the node enters the tree; setup() touches card_back/card_front.
		_ai_hand_root.add_child(card)
		card.setup(null, false, false)  # face-down card back
		# Belt-and-braces: card sub-controls also non-interactive.
		for child in card.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ai_card_back_nodes.append(card)
	while _ai_card_back_nodes.size() > n:
		var node := _ai_card_back_nodes.pop_back() as Card
		if is_instance_valid(node):
			node.queue_free()
	_layout_ai_hand()


# Pops the rightmost card-back from the AI hand visuals and reparents it
# to `_bs.canvas` (preserving world position and scale), so AiCardPlayer can
# fly it freely to the centre of the screen. Returns null if the hand is
# already empty.
func pop_ai_hand_card_node() -> Card:
	if _ai_card_back_nodes.is_empty():
		return null
	var card := _ai_card_back_nodes.pop_back() as Card
	_layout_ai_hand()
	if not is_instance_valid(card):
		return null
	var world_pos: Vector2  = card.global_position
	var world_scale: Vector2 = card.scale
	var parent := card.get_parent()
	if parent != null:
		parent.remove_child(card)
	_bs.canvas.add_child(card)
	card.global_position = world_pos
	card.scale = world_scale
	return card


## 상대 손패의 **왼쪽 끝** 자리(뷰포트 좌표, 카드 좌상단 기준). 지금 손패보다
## 한 장 많은 부채꼴로 재므로, 여기로 날아온 카드가 실제로 앉을 자리와 맞는다.
##
## 쓰는 곳은 오브젝트 보상 연출(`objective/ObjectiveRewardFx.gd`) 하나다 —
## 적이 전령 / 용을 가져갔을 때 보상 카드가 빨려 들어가는 지점. 상대의 덱은
## 화면에 없으므로 손패 자리가 "상대 것이 됐다"를 말하는 유일한 좌표다.
func ai_hand_left_anchor() -> Vector2:
	var n: int = maxi(1, _ai_card_back_nodes.size() + 1)
	var step_deg: float = AI_HAND_FAN_STEP_DEG
	if n > 1:
		step_deg = min(step_deg, AI_HAND_FAN_MAX_SPREAD_DEG / float(n - 1))
	var half_card := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	# `_ai_hand_root` 가 `top_offset()` 만큼 내려가 있으므로 로컬 → 뷰포트 변환에
	# 그 값을 더한다. 이 함수만 뷰포트 좌표를 약속한다(`_layout_ai_hand` 는 로컬).
	var mid_center_y: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE * 0.5 			+ top_offset()
	var pivot := Vector2(ScreenMetrics.center_x(), mid_center_y - AI_HAND_FAN_RADIUS)
	var theta: float = deg_to_rad(-float(n - 1) * 0.5 * step_deg)
	var centre: Vector2 = pivot + Vector2(sin(theta), cos(theta)) * AI_HAND_FAN_RADIUS
	return centre - half_card


# Lays the AI card backs out on the inverted fan described above. The step
# angle shrinks once the hand is wide enough to hit AI_HAND_FAN_MAX_SPREAD_DEG,
# so the row redistributes instead of growing — the same "fixed width, tighter
# overlap" rule the player hand follows.
func _layout_ai_hand() -> void:
	var n: int = _ai_card_back_nodes.size()
	if n == 0:
		return
	var step_deg: float = AI_HAND_FAN_STEP_DEG
	if n > 1:
		step_deg = min(step_deg, AI_HAND_FAN_MAX_SPREAD_DEG / float(n - 1))
	# The pivot sits directly above the middle card by exactly one radius, so
	# θ=0 lands that card's centre at AI_HAND_TOP_Y + half its scaled height.
	var half_card := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	var mid_center_y: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE * 0.5
	var pivot := Vector2(ScreenMetrics.center_x(), mid_center_y - AI_HAND_FAN_RADIUS)
	for i in n:
		var card := _ai_card_back_nodes[i] as Card
		var theta: float = deg_to_rad((float(i) - float(n - 1) * 0.5) * step_deg)
		var centre: Vector2 = pivot \
				+ Vector2(sin(theta), cos(theta)) * AI_HAND_FAN_RADIUS
		# Rotation and scale both pivot around `pivot_offset`, and a Control's
		# visual centre is `position + pivot_offset` — unscaled, unrotated (see
		# card_phase/README.md). So the top-left we want is centre − half_card,
		# with no scale correction.
		card.pivot_offset = half_card
		card.rotation = -theta
		card.position = centre - half_card


# ── Turn announcer ───────────────────────────────────────────────────────────
# A horizontal bar that sweeps in from the centre with the message
# "당신의 차례" / "상대 차례", holds briefly, then fades out. Caller awaits
# play_turn_announce(...) so input gating can re-enable on completion.
# The bar (`%TurnBar`, 110 tall, vertically centred) and the label (`%TurnLabel`)
# live in the scene. The bar is a white plate with a side-coloured line above and
# below — that colour is data (`TURN_BAR[team]`) put into the `border_color` of a copy
# of the `HudTurnBar` theme box; the label takes the side text colour (`SIDE_TEXT[team]`).
const TURN_ANNOUNCE_IN_DUR       := 0.32
const TURN_ANNOUNCE_HOLD_DUR     := 0.55
const TURN_ANNOUNCE_OUT_DUR      := 0.32
const TURN_ANNOUNCE_PLAYER_COLOR: Color = BattleTheme.TURN_BAR[0]
const TURN_ANNOUNCE_ENEMY_COLOR: Color = BattleTheme.TURN_BAR[1]

func _bind_turn_announcer(root: Node) -> void:
	_turn_announce_root = root.get_node("%TurnAnnounce") as Control
	_turn_bar = root.get_node("%TurnBar") as Panel
	_turn_label = root.get_node("%TurnLabel") as Label
	_turn_announce_root.visible = false


# Plays the centre-screen turn banner. `is_player == true` shows "당신의 차례"
# in blue; false shows "상대 차례" in red. Awaits the full sweep-in / hold /
# fade-out cycle so the caller can use it as a gate.
func play_turn_announce(is_player: bool) -> void:
	if _turn_announce_root == null:
		return
	_announce_gen += 1
	var gen: int = _announce_gen
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	var sb := BattleTheme.variation_box(&"HudTurnBar")
	sb.border_color = TURN_ANNOUNCE_PLAYER_COLOR if is_player else TURN_ANNOUNCE_ENEMY_COLOR
	_turn_bar.add_theme_stylebox_override("panel", sb)
	_turn_label.add_theme_color_override("font_color",
			BattleTheme.SIDE_TEXT[0 if is_player else 1] as Color)
	_turn_label.text = Loc.t(L.HUD_TURN_PLAYER if is_player else L.HUD_TURN_ENEMY)
	# 띠는 화면 가운데의 폭 0 에서 좌우로 펼쳐진다 — 높이 · 세로 자리는 씬 값.
	var vp := ScreenMetrics.viewport_size()
	var bar_h: float = _turn_bar.size.y
	_turn_bar.modulate = Color.WHITE
	_turn_bar.position = Vector2(vp.x * 0.5, _turn_bar.position.y)
	_turn_bar.size = Vector2(0.0, bar_h)
	_turn_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	_turn_announce_root.visible = true

	var tw_in := _bs.create_tween().set_parallel()
	_announce_tween = tw_in
	tw_in.tween_property(_turn_bar, "size", Vector2(vp.x, bar_h),
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(_turn_bar, "position:x", 0.0,
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(_turn_label, "modulate", Color.WHITE,
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw_in.finished

	await _bs.get_tree().create_timer(TURN_ANNOUNCE_HOLD_DUR).timeout

	# 그사이 새 알림이 시작됐으면 띠는 그쪽 것이다 — 손대지 않고 끝낸다.
	if gen != _announce_gen:
		return
	var tw_out := _bs.create_tween().set_parallel()
	_announce_tween = tw_out
	tw_out.tween_property(_turn_bar, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw_out.tween_property(_turn_label, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await tw_out.finished

	if gen == _announce_gen:
		_turn_announce_root.visible = false


# 전략 포인트 도넛 두 개를 화면 **좌측** 거터에 놓는다. 대상 지정 확인/취소
# 버튼이 우하단으로 옮겨 갔으므로 도넛 열은 반대편(좌측)을 차지한다. 중심은 다른
# 모듈의 기하(상대 손패 peek · 대상 지정 버튼 띠 · 손패 행)에서 나오므로 여기서 정한다.
#  - player: 핸드 좌측 상단 (Deck 카운터 바로 위). 탭하면 도넛이 왼쪽으로 빠지고
#    턴 넘기기 판(꾹 눌러 넘기기)이 들어오며, 바깥을 누르면 다시 도넛으로 돌아온다.
#  - enemy: 화면 좌측 상단 (상대 핸드 peek 바로 아래). 표시 전용.
func _bind_cost_donuts(root: Node) -> void:
	var cx: float = _bs.BS_HAND_AREA_MARGIN * 0.5

	_bs.cost_donut_enemy = root.get_node("%CostDonutEnemy") as CostDonut
	_bs.cost_donut_enemy.fill_color = DONUT_FILL_ENEMY
	_bs.cost_donut_enemy.interactive = false
	var ai_hand_bottom: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE
	_bs.cost_donut_enemy.set_center(Vector2(cx, top_offset()
			+ ai_hand_bottom + DONUT_AI_HAND_GAP + CostDonut.RADIUS))

	_bs.cost_donut = root.get_node("%CostDonutPlayer") as CostDonut
	_bs.cost_donut.fill_color = DONUT_FILL_PLAYER
	_bs.cost_donut.interactive = true
	var targeting_btn_band: float = CardTargetingOverlay.BTN_HAND_GAP \
			+ CardTargetingOverlay.BTN_H
	_bs.cost_donut.set_center(Vector2(cx, _bs.BS_HAND_CENTER.y
			- targeting_btn_band - DONUT_HAND_GAP - CostDonut.RADIUS))
	_bs.cost_donut.end_turn_pressed.connect(_bs.card_phase.end_card_phase)
	# 판이 열려 있는 동안 손패가 다음 작전 단계 전에 버려질 카드를 표시한다.
	_bs.cost_donut.turn_end_toggled.connect(
			func(_open: bool) -> void: _bs.card_phase.refresh_doom_marks())
	# 턴 넘기기 판 — 도넛을 탭하면 도넛 자리에 왼쪽에서 밀려 들어온다(`TurnEndPanel`).
	var turn_end := root.get_node("%TurnEndPanel_Player") as TurnEndPanel
	turn_end.place(TURN_END_PANEL_LEFT, _bs.cost_donut.rest_center().y)
	_bs.cost_donut.attach_turn_end_panel(turn_end)

	# 예약 칩 — 아군 도넛 위로 쌓인다(`ReservationChips`). 적 쪽은 두지 않는다:
	# 적 도넛 아래는 전장 왼쪽 위 타일과 겹치고, 상대의 예약은 킬로그 · 결과로
	# 드러난다.
	_reserve_chips = root.get_node("%ReservationChipsP") as ReservationChips
	_reserve_chips.setup(_bs, true, _bs.cost_donut.rest_center())


## 결과 화면 — `VictoryLayer`(층 50: HUD 캔버스와 전장 위, MVP 뷰
## `MvpView.OVERLAY_LAYER` 아래)의 `%VictoryPanel`(불투명 `BattleGoldModal`, 700×520,
## 화면 가운데)과 그 뒤 전체 화면 딤(`%VictoryBackdrop`). 예전에는 HUD 캔버스에 같이
## 있어서 반투명 판 너머로 전장 타일 · 마커가 비쳤고, 판 밖의 HUD 띠 · 마커가 결과
## 화면과 같은 밝기로 경쟁했다. MVP 한 줄(`%MvpRow`: 원형 초상 + 이름 + K/D/A)은
## `BattleSim.end_match` 가 `set_victory_mvp` 로 채운다.
var _victory_mvp_row: Control = null


## 결과 화면의 MVP 한 줄을 채운다. `p` 가 null 이면(이긴 팀이 비어 있는 기묘한
## 경우) 줄을 숨긴다.
func set_victory_mvp(p: PilotData, row: Dictionary) -> void:
	if _victory_mvp_row == null:
		return
	_victory_mvp_row.visible = p != null
	if p == null:
		return
	var tex: Texture2D = PilotImages.circle_for(MvpView.portrait_id(p))
	var portrait := _victory_mvp_row.get_node("%MvpPortrait") as TextureRect
	portrait.texture = tex
	portrait.visible = tex != null
	(_victory_mvp_row.get_node("%MvpName") as Label).text = MvpView.display_name(_bs, p)
	(_victory_mvp_row.get_node("%PositionBadge_MvpPosition") as PositionBadge).set_role(p.role)
	(_victory_mvp_row.get_node("%MvpKda") as Label).text = MvpView.kda_text(row)


func _bind_victory_panel(root: Node) -> void:
	_bs.panel_victory = root.get_node("%VictoryPanel") as Panel
	_bs.lbl_victory = root.get_node("%VictoryLabel") as Label
	_bs.lbl_victory.text = ""
	_victory_mvp_row = root.get_node("%MvpRow") as Control
	_victory_mvp_row.visible = false

	# 딤은 판의 표시 여부를 그대로 따른다 — `panel_victory.visible` 을 켜고 끄는 자리
	# (`BattleSim.end_match` / `_on_mvp_view_closed` / `_on_restart_pressed`)는 그대로다.
	var backdrop := root.get_node("%VictoryBackdrop") as Control
	_bs.panel_victory.visibility_changed.connect(
			func() -> void: backdrop.visible = _bs.panel_victory.visible)
	_bs.panel_victory.visible = false
	backdrop.visible = false

	# Standalone runs replay the same battle; Season-driven runs return to the
	# campaign hub so LeagueManager can record the result.
	var season_mode: bool = _bs.gm.season_state.get("pending_match", null) != null
	var rb := root.get_node("%VictoryButton") as Button
	rb.text = Loc.t(L.HUD_VICTORY_NEXT if season_mode else L.HUD_VICTORY_PLAY_AGAIN)
	if season_mode:
		rb.pressed.connect(_bs._on_return_to_season_pressed)
	else:
		rb.pressed.connect(_bs._on_restart_pressed)


func update_hud() -> void:
	# Battle log is no longer surfaced on screen; `_bs.last_log` is still
	# updated by effect handlers for diagnostics but renders nowhere.
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	_update_cost_donuts(in_card_phase)
	_update_pile_buttons()
	_update_pilot_strips()
	update_time_label()


# The ring is full at PHASE_THRESHOLD; the number in the middle is the raw
# point total, so boost cards read as "more than PHASE_THRESHOLD on a full ring".
# The player donut only accepts the flip → 턴 넘기기 during 작전 단계.
func _update_cost_donuts(in_card_phase: bool) -> void:
	# 100% 표시는 `PHASE_THRESHOLD`(game_config) 하나만 따른다 — 로드 전에는 0 이고
	# `CostDonut.set_value` 가 분모를 1 이상으로 묶는다.
	var maxv: int = _bs.PHASE_THRESHOLD
	if _bs.cost_donut_enemy != null:
		_bs.cost_donut_enemy.set_value(_bs.ai_cost, maxv)
	if _bs.cost_donut != null:
		# Deck / Discard 목록이 열려 있으면 플립도 막는다 — CostDonut._input 은
		# GUI 픽보다 먼저 돌아 열람 딤을 뚫고 눌린다. 전투 개시 VS 확인 화면도
		# 같은 이유로 막는다: 그 화면이 떠 있는 동안 game_phase 는 아직
		# CARD_PHASE 라, 딤만으로는 도넛이 눌리는 것을 못 막는다.
		var modal_up: bool = (_bs.card_pile_viewer != null
					and _bs.card_pile_viewer.is_active()) \
				or (_bs.engage_phase != null and _bs.engage_phase.is_intro_active())
		_bs.cost_donut.set_value(_bs.player_cost, maxv)
		_bs.cost_donut.set_flip_allowed(in_card_phase and not modal_up)
		_bs.cost_donut.set_end_enabled(in_card_phase
				and _bs.card_phase.can_end_card_phase())


# Smooth in-game timer — driven by turn_count + auto_play_timer fraction.
# Called every frame from BattleSim._process so the seconds tick visibly.
func update_time_label() -> void:
	if _lbl_time == null:
		return
	var sec_total: int = _bs.get_elapsed_ingame_seconds()
	@warning_ignore("integer_division")
	var mm: int = sec_total / 60
	var ss: int = sec_total % 60
	_lbl_time.text = "%02d:%02d" % [mm, ss]


## 스트립의 자리 순서는 **역할**이 정한다 — `GameEnums.ROLE_DISPLAY_ORDER`
## (탑 · 정글 · 미드 · 원딜 · 서폿), 곧 전장을 왼쪽부터 오른쪽으로 훑은 순서
## (좌측 → 정글 → 중앙 → 우측 ×2)다. 예전에는 여기 `LANE_SEAT_ORDER` 표를 따로
## 두고 `PilotData.lane` 으로 정렬했는데, **우측 레인에는 두 명이 앉아 있어**
## (스나이퍼 · 서포터) 그 둘의 순서를 lane 이 가르지 못했다 — `sort_custom` 은
## 안정 정렬이 아니므로 같은 lane 두 명의 앞뒤가 실행마다 흔들릴 수 있었다.
## 역할로 정렬하면 다섯 자리가 전부 유일하게 정해지고, **아웃게임 화면들과도
## 같은 표 하나를 읽는다**(시즌 허브 로스터 · 훈련 격자 · 밴픽 화면).
static func _lane_seat_less(a: PilotData, b: PilotData) -> bool:
	return GameEnums.role_seat(a.role) < GameEnums.role_seat(b.role)


# 두 스트립 + 팀 합산 점수 갱신, 그리고 상세 패널의 단계 게이트.
#
# `_bs.pilots` 는 스폰 순서(= 역할 순서)를 그대로 유지해야 한다
# (`BattleSim.player_data_for` 가 그 인덱스로 로스터를 찾는다). 그래서 여기서는
# **사본을 정렬**한다 — 원본을 sort_custom 하면 아웃게임 스탯이 엉뚱한
# 파일럿에게 붙는다.
func _update_pilot_strips() -> void:
	# 스트립 버튼은 상세 패널을 열 수 있을 때만 산다 — 작전 단계 + 자동 진행.
	var can_open: bool = _bs.pilot_detail != null and _bs.pilot_detail.can_open()
	var team0: Array = []
	var team1: Array = []
	for p in _bs.pilots:
		var pd := p as PilotData
		(team0 if pd.team == 0 else team1).append(pd)
	team0.sort_custom(_lane_seat_less)
	team1.sort_custom(_lane_seat_less)
	if _player_strip != null:
		_player_strip.set_pilots(team0)
		_player_strip.set_interactive_enabled(can_open)
	if _enemy_strip != null:
		_enemy_strip.set_pilots(team1)
		_enemy_strip.set_interactive_enabled(can_open)
	if _bs.skill_popup != null:
		_bs.skill_popup.close_if_phase_left()
		_bs.skill_popup.refresh()
	for raw in _obj_timers:
		(raw as ObjectiveTimer).queue_redraw()
	if _bs.pilot_detail != null:
		_bs.pilot_detail.close_if_phase_left()
		# 닫히지 않고 살아남았다면 스탯을 지금 값으로 다시 세운다 — 카드가
		# 건 라인전 스탯 / 성장 획득 배율이 그 자리에서 읽혀야 한다.
		_bs.pilot_detail.refresh()


