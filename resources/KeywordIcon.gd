class_name KeywordIcon
extends RefCounted

# 카드 설명의 **키워드 아이콘** — 사거리 · 대상 · 시전 범위 · 지속시간 · 교전 ·
# 공격 · 필중 · 이동 · 공격력 · 체력 · 성장 · 뽑기 · 버리기 · 보존 · 소지 중 ·
# 찾기 · 생성 · 보호막 · 회복 · 처치 · 버린 더미. 설명문 안의 낱말 앞에 끼우는 일은
# `StrategyIcon.fill_rich` 가 하고(전략 점수 · 비용 아이콘과 같은 길), 설명판의
# 속성 줄(`CardDescBox`)도 같은 텍스처를 쓴다.
#
# 모양은 64×64 viewBox 의 SVG 문자열이고, 런타임에 `Image.load_svg_from_string`
# 으로 굽는다 — 임포트 파일이 필요 없고 크기마다 선명하게 다시 굽는다. 색은
# **구울 때 박는다**(`{C}` = 아이콘 색, `{K}` = 판 바탕색). 필중의 원 배경 위
# 활은 판 바탕색으로 파내야 읽히는데, `add_image` 의 modulate 하나로는 두 색을
# 낼 수 없기 때문이다.

const RANGE := "range"
const TARGET := "target"
const AREA := "area"
const DURATION := "duration"
const ENGAGE := "engage"
const ATTACK := "attack"
const PIERCE := "pierce"
const MOVE := "move"
const ATK := "atk"
const HP := "hp"
const GROWTH := "growth"
const DRAW := "draw"
const DISCARD := "discard"
const PRESERVE := "preserve"
const HOLD := "hold"
const SEARCH := "search"
const CREATE := "create"
const SHIELD := "shield"
const HEAL := "heal"
const KILL := "kill"
const DISCARD_PILE := "discard_pile"
## 대상이 타일인 카드의 대상 아이콘 — 낱말로는 찾지 않고 `TARGET` 자리를 갈아 끼운다.
const TILE := "tile"
## 특수 키워드(`CardData.SPECIAL_NOTES`) 아이콘 — 낱말이 아니라 `[용어]` 조각에 붙는다.
const TRACK := "track"
const REACTIVE_ARMOR := "reactive_armor"
const MARK := "mark"
const BOUNTY := "bounty"
const STUN := "stun"
const VULNERABLE := "vulnerable"
## 쿨타임 — 시계. 낱말로는 찾지 않고 스킬 말풍선(`SkillPopup`)의 타입 자리에 선다.
const COOLDOWN := "cooldown"
## 파일럿 스탯 — 전장(육각 타일 바탕) / 교전(굵은 X 바탕) × 명중(목표) / 회피(발).
const FIELD_HIT := "field_hit"
const FIELD_EVA := "field_eva"
const ENGAGE_HIT := "engage_hit"
const ENGAGE_EVA := "engage_eva"
## 공격 성장 · 체력 성장 — `ATK`(칼) · `HP`(하트) 우측 하단에 위를 향한 짧고 굵은 화살표.
const ATK_GROWTH := "atk_growth"
const HP_GROWTH := "hp_growth"
## 존재감 — `TARGET` 상반신의 몸통 안에 `MARK`(목표)를 파낸다.
const PRESENCE := "presence"

## 판 색과 상관없이 늘 같은 색을 쓰는 아이콘 — 뽑기는 초록, 버리기는 빨강.
const DRAW_COLOR := Color(0.25, 0.78, 0.40)
const DISCARD_COLOR := Color(0.92, 0.30, 0.30)
## 대상 아이콘 색 — 카드가 겨누는 편(`target_color`): 아군 초록 · 적 빨강 · 둘 다 회색.
const TARGET_ALLY_COLOR := DRAW_COLOR
const TARGET_ENEMY_COLOR := DISCARD_COLOR
const TARGET_ANY_COLOR := Color(0.62, 0.62, 0.68)
## 특수 키워드(`[반응 장갑]` · `[락온]` …) 글자색 — 인게임 / 아웃게임 판.
const SPECIAL_COLOR_DARK := Color(0.80, 0.66, 1.0)
const SPECIAL_COLOR_LIGHT := Color(0.50, 0.28, 0.82)

## 설명문 낱말 → 아이콘. **긴 낱말이 먼저다** — "공격력" 이 "공격" 보다 앞에 있어야
## 공격력 앞에 활이 서지 않는다(같은 자리에서 시작하면 긴 쪽이 이긴다).
## 특수 키워드 id(`CardData.SPECIAL_LABELS` 의 키) → 아이콘. `[이름]` 이 어느 특수 키워드인지는
## 표시 글자가 아니라 참조 key 로 정한다(`CardData.ref_entries`). 카드 이름 참조는 아이콘 없이 색만.
const SPECIAL_ICONS: Dictionary = {
	"track": TRACK,
	"reactive_armor": REACTIVE_ARMOR,
	"target": MARK,
	"bounty": BOUNTY,
	"stun": STUN,
	"vulnerable": VULNERABLE,
}

## "필중 공격" 은 한 덩어리 — 필중 아이콘 하나만 서고 "공격" 에 활이 또 붙지 않는다.
## 지속시간은 낱말이 아니라 "N턴" 꼴이라 `StrategyIcon._tokens` 가 따로 찾는다.
const WORDS: Array = [
	["전장 명중", FIELD_HIT],
	["전장 회피", FIELD_EVA],
	["교전 명중", ENGAGE_HIT],
	["교전 회피", ENGAGE_EVA],
	["필중 공격", PIERCE],
	["소지 중", HOLD],
	["버린 더미", DISCARD_PILE],
	["보호막", SHIELD],
	["최대 체력", HP],
	["버린 후", DISCARD],
	["공격력", ATK],
	["사거리", RANGE],
	["체력", HP],
	["성장", GROWTH],
	["필중", PIERCE],
	["공격", ATTACK],
	["교전", ENGAGE],
	["이동", MOVE],
	["대상", TARGET],
	["범위", AREA],
	["뽑기", DRAW],
	["버리기", DISCARD],
	["보존", PRESERVE],
	["찾기", SEARCH],
	["생성", CREATE],
	["회복", HEAL],
	["처치", KILL],
]

const _HEAD := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">"
const _STROKE := "fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\""

# 스탯 아이콘의 바탕 — 아이콘 색을 옅게(`fill-opacity`) 깔고 그 위에 안 아이콘을
# 진하게 얹는다. X 는 두 막대를 **한 path** 로 그려 겹친 가운데가 두 번 진해지지
# 않게 한다(불투명도는 도형마다 한 번 먹는다).
const _HEX_BG := "<polygon fill=\"{C}\" fill-opacity=\"0.34\" points=\"17,6 47,6 62,32 47,58 17,58 2,32\"/>"
const _X_BG := "<path fill=\"{C}\" fill-opacity=\"0.34\" d=\"M15.4 2.6 L61.4 48.6 L48.6 61.4 L2.6 15.4 Z M48.6 2.6 L61.4 15.4 L15.4 61.4 L2.6 48.6 Z\"/>"
# 안 아이콘 — 목표(원 + 십자, `MARK` 를 줄인 꼴) / 발(`TRACK` 발자국을 줄인 꼴).
const _HIT_INNER := "<g fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\"><circle cx=\"32\" cy=\"32\" r=\"14\"/><line x1=\"32\" y1=\"11\" x2=\"32\" y2=\"53\"/><line x1=\"11\" y1=\"32\" x2=\"53\" y2=\"32\"/></g>"
const _EVA_INNER := "<g fill=\"{C}\" transform=\"translate(9.6 10.9) scale(0.68)\"><path d=\"M31 25 C43 23 48 33 46 43 C44 53 38 61 29 61 C21 61 16 54 18 46 C20 38 20 27 31 25 Z\"/><ellipse cx=\"19\" cy=\"14\" rx=\"7\" ry=\"8\"/><ellipse cx=\"35\" cy=\"8\" rx=\"6\" ry=\"7\"/><ellipse cx=\"49\" cy=\"16\" rx=\"5.5\" ry=\"6.5\"/></g>"

# 성장 화살표 — 우측 하단, 위를 향한 짧고 굵은 화살표. 판 바탕색 테두리를 먼저
# 깔아 칼 · 하트와 맞닿는 자리를 끊는다.
const _GROWTH_ARROW_PTS := "51,35 63,48 56.5,48 56.5,63 45.5,63 45.5,48 39,48"
const _GROWTH_ARROW := "<polygon fill=\"{K}\" stroke=\"{K}\" stroke-width=\"7\" stroke-linejoin=\"round\" points=\"" + _GROWTH_ARROW_PTS + "\"/><polygon fill=\"{C}\" points=\"" + _GROWTH_ARROW_PTS + "\"/>"
const _ATK_BODY := "<g fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><line x1=\"56\" y1=\"8\" x2=\"24\" y2=\"40\"/><line x1=\"14\" y1=\"32\" x2=\"32\" y2=\"50\"/><line x1=\"20\" y1=\"44\" x2=\"10\" y2=\"54\"/></g><circle cx=\"8\" cy=\"56\" r=\"5\" fill=\"{C}\"/>"
const _HP_BODY := "<path fill=\"{C}\" d=\"M32 58 C12 44 4 32 6 21 C8 10 22 6 32 17 C42 6 56 10 58 21 C60 32 52 44 32 58 Z\"/>"

# 아이콘별 SVG 본문(머리 · 꼬리 제외).
const _BODIES := {
	# 가로 양방향 화살표 + 양 끝 세로 바.
	RANGE: "<g " + _STROKE + "><line x1=\"6\" y1=\"16\" x2=\"6\" y2=\"48\"/><line x1=\"58\" y1=\"16\" x2=\"58\" y2=\"48\"/><line x1=\"14\" y1=\"32\" x2=\"50\" y2=\"32\"/><polyline points=\"23,23 14,32 23,41\"/><polyline points=\"41,23 50,32 41,41\"/></g>",
	# 사람 상반신 — 머리 + 어깨.
	TARGET: "<g fill=\"{C}\"><circle cx=\"32\" cy=\"19\" r=\"13\"/><path d=\"M7 60 C7 44 18 36 32 36 C46 36 57 44 57 60 Z\"/></g>",
	# 아이소메트릭 마름모 타일 4장 — 상 · 하 · 좌 · 우.
	AREA: "<g fill=\"{C}\"><polygon points=\"32,9 45,16 32,23 19,16\"/><polygon points=\"32,41 45,48 32,55 19,48\"/><polygon points=\"16,25 29,32 16,39 3,32\"/><polygon points=\"48,25 61,32 48,39 35,32\"/></g>",
	# 모래시계 — 위아래 받침 + 유리 + 아래에 쌓인 모래.
	DURATION: "<g " + _STROKE + "><line x1=\"12\" y1=\"7\" x2=\"52\" y2=\"7\"/><line x1=\"12\" y1=\"57\" x2=\"52\" y2=\"57\"/><path d=\"M18 7 C18 22 28 27 32 32 C36 37 46 42 46 57 M46 7 C46 22 36 27 32 32 C28 37 18 42 18 57\"/></g><polygon fill=\"{C}\" points=\"22,55 42,55 32,44\"/>",
	# 엇갈린 칼 두 자루.
	ENGAGE: "<g " + _STROKE + "><line x1=\"10\" y1=\"8\" x2=\"44\" y2=\"42\"/><line x1=\"36\" y1=\"50\" x2=\"52\" y2=\"34\"/><line x1=\"46\" y1=\"46\" x2=\"56\" y2=\"56\"/><line x1=\"54\" y1=\"8\" x2=\"20\" y2=\"42\"/><line x1=\"12\" y1=\"34\" x2=\"28\" y2=\"50\"/><line x1=\"18\" y1=\"46\" x2=\"8\" y2=\"56\"/></g>",
	# 오른쪽을 겨눈 활 — 시위가 가운데, 활대가 그 조금 오른쪽으로 휘고, 화살이
	# 시위를 지나 오른쪽을 향한다.
	ATTACK: "<g " + _STROKE + "><path d=\"M30 6 Q60 32 30 58\"/><line x1=\"30\" y1=\"6\" x2=\"30\" y2=\"58\" stroke-width=\"3\"/><line x1=\"6\" y1=\"32\" x2=\"56\" y2=\"32\"/><polyline points=\"47,23 57,32 47,41\"/></g>",
	# 원 배경 위의 같은 활 — 판 바탕색으로 파낸다.
	PIERCE: "<circle cx=\"32\" cy=\"32\" r=\"31\" fill=\"{C}\"/><g fill=\"none\" stroke=\"{K}\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M29 13 Q53 32 29 51\"/><line x1=\"29\" y1=\"13\" x2=\"29\" y2=\"51\" stroke-width=\"2.5\"/><line x1=\"11\" y1=\"32\" x2=\"51\" y2=\"32\"/><polyline points=\"44,25 52,32 44,39\"/></g>",
	# 왼쪽에서 오른쪽으로 가는 화살표.
	MOVE: "<g fill=\"none\" stroke=\"{C}\" stroke-width=\"7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><line x1=\"8\" y1=\"32\" x2=\"54\" y2=\"32\"/><polyline points=\"38,16 55,32 38,48\"/></g>",
	# 칼 한 자루.
	ATK: _ATK_BODY,
	# 하트.
	HP: _HP_BODY,
	# 새싹 — 줄기 + 잎 두 장.
	GROWTH: "<line x1=\"32\" y1=\"58\" x2=\"32\" y2=\"30\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\"/><path fill=\"{C}\" d=\"M30 38 C16 39 6 30 6 16 C20 15 30 24 30 38 Z\"/><path fill=\"{C}\" d=\"M34 31 C34 17 44 8 59 8 C59 22 49 31 34 31 Z\"/>",
	# 뽑기 — 채운 카드(둥근 세로 직사각형)에 위에서 카드 가운데로 꽂히는 화살표.
	# 카드 밖 화살은 아이콘 색, 카드 안 화살은 판 바탕색으로 파낸다.
	DRAW: "<rect x=\"16\" y=\"24\" width=\"32\" height=\"38\" rx=\"6\" fill=\"{C}\"/><line x1=\"32\" y1=\"3\" x2=\"32\" y2=\"24\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\"/><g fill=\"none\" stroke=\"{K}\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><line x1=\"32\" y1=\"26\" x2=\"32\" y2=\"44\"/><polyline points=\"23,35 32,44 41,35\"/></g>",
	# 버리기 — 뽑기의 반대. 화살이 카드 안에서 출발해 카드 아래로 빠져나간다.
	DISCARD: "<rect x=\"16\" y=\"2\" width=\"32\" height=\"38\" rx=\"6\" fill=\"{C}\"/><line x1=\"32\" y1=\"12\" x2=\"32\" y2=\"40\" stroke=\"{K}\" stroke-width=\"6\" stroke-linecap=\"round\"/><g fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><line x1=\"32\" y1=\"40\" x2=\"32\" y2=\"60\"/><polyline points=\"23,51 32,60 41,51\"/></g>",
	# 보존 — 자물쇠. 몸통의 열쇠 구멍은 판 바탕색.
	PRESERVE: "<path d=\"M20 30 V21 C20 6 44 6 44 21 V30\" fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\"/><rect x=\"11\" y=\"28\" width=\"42\" height=\"32\" rx=\"6\" fill=\"{C}\"/><circle cx=\"32\" cy=\"41\" r=\"5\" fill=\"{K}\"/><rect x=\"30\" y=\"42\" width=\"4\" height=\"10\" rx=\"2\" fill=\"{K}\"/>",
	# 소지 중 — 손바닥을 보인 오른손. 손가락 넷은 곧게 위로, 엄지는 오른쪽으로.
	HOLD: "<g stroke=\"{C}\" stroke-width=\"7\" stroke-linecap=\"round\"><line x1=\"14\" y1=\"40\" x2=\"14\" y2=\"18\"/><line x1=\"23\" y1=\"40\" x2=\"23\" y2=\"9\"/><line x1=\"32\" y1=\"40\" x2=\"32\" y2=\"6\"/><line x1=\"41\" y1=\"40\" x2=\"41\" y2=\"11\"/><line x1=\"44\" y1=\"48\" x2=\"57\" y2=\"32\"/></g><path fill=\"{C}\" d=\"M10.5 32 H44.5 V48 C44.5 56 39 61 31 61 H24 C16 61 10.5 56 10.5 48 Z\"/>",
	# 타일 — 전장과 같은 평평한 윗변의 육각형.
	TILE: "<polygon fill=\"{C}\" points=\"17,6 47,6 62,32 47,58 17,58 2,32\"/>",
	# 찾기 — 돋보기.
	SEARCH: "<g fill=\"none\" stroke=\"{C}\" stroke-linecap=\"round\"><circle cx=\"26\" cy=\"26\" r=\"17\" stroke-width=\"6\"/><line x1=\"39\" y1=\"39\" x2=\"57\" y2=\"57\" stroke-width=\"9\"/></g>",
	# 생성 — 채운 카드 + 그 오른쪽의 더하기.
	CREATE: "<rect x=\"4\" y=\"9\" width=\"30\" height=\"46\" rx=\"6\" fill=\"{C}\"/><g stroke=\"{C}\" stroke-width=\"7\" stroke-linecap=\"round\"><line x1=\"50\" y1=\"22\" x2=\"50\" y2=\"46\"/><line x1=\"38\" y1=\"34\" x2=\"62\" y2=\"34\"/></g>",
	# 보호막 — 방패.
	SHIELD: "<path fill=\"{C}\" d=\"M32 4 L56 12 V30 C56 46 46 55 32 61 C18 55 8 46 8 30 V12 Z\"/>",
	# 회복 — 하트에서 더하기 모양을 파낸다.
	HEAL: "<path fill=\"{C}\" d=\"M32 58 C12 44 4 32 6 21 C8 10 22 6 32 17 C42 6 56 10 58 21 C60 32 52 44 32 58 Z\"/><g stroke=\"{K}\" stroke-width=\"6\" stroke-linecap=\"round\"><line x1=\"32\" y1=\"23\" x2=\"32\" y2=\"43\"/><line x1=\"22\" y1=\"33\" x2=\"42\" y2=\"33\"/></g>",
	# 처치 · 처치 관여 — 해골. 눈 · 코 · 이빨은 판 바탕색.
	KILL: "<circle cx=\"32\" cy=\"27\" r=\"23\" fill=\"{C}\"/><rect x=\"19\" y=\"38\" width=\"26\" height=\"21\" rx=\"5\" fill=\"{C}\"/><g fill=\"{K}\"><circle cx=\"23\" cy=\"28\" r=\"6.5\"/><circle cx=\"41\" cy=\"28\" r=\"6.5\"/><polygon points=\"32,35 28,42 36,42\"/></g><g stroke=\"{K}\" stroke-width=\"3\"><line x1=\"27\" y1=\"50\" x2=\"27\" y2=\"59\"/><line x1=\"32\" y1=\"50\" x2=\"32\" y2=\"59\"/><line x1=\"37\" y1=\"50\" x2=\"37\" y2=\"59\"/></g>",
	# 버린 더미 — 눕혀 쌓은 카드 세 장(옆에서 본 두께), 장마다 조금씩 엇갈린다.
	DISCARD_PILE: "<g fill=\"{C}\"><rect x=\"6\" y=\"46\" width=\"52\" height=\"11\" rx=\"4\"/><rect x=\"10\" y=\"32\" width=\"50\" height=\"11\" rx=\"4\"/><rect x=\"4\" y=\"18\" width=\"50\" height=\"11\" rx=\"4\"/></g>",
	# 추적 — 발자국 하나: 발바닥 + 간격을 넓게 둔 발가락 셋.
	TRACK: "<path fill=\"{C}\" d=\"M31 25 C43 23 48 33 46 43 C44 53 38 61 29 61 C21 61 16 54 18 46 C20 38 20 27 31 25 Z\"/><g fill=\"{C}\"><ellipse cx=\"19\" cy=\"14\" rx=\"7\" ry=\"8\"/><ellipse cx=\"35\" cy=\"8\" rx=\"6\" ry=\"7\"/><ellipse cx=\"49\" cy=\"16\" rx=\"5.5\" ry=\"6.5\"/></g>",
	# 반응 장갑 — 둥근 정사각 장갑판, 좌상 → 우하 굵은 홈 + 우상 · 좌하 리벳.
	REACTIVE_ARMOR: "<rect x=\"8\" y=\"8\" width=\"48\" height=\"48\" rx=\"8\" fill=\"{C}\"/><line x1=\"18\" y1=\"18\" x2=\"46\" y2=\"46\" stroke=\"{K}\" stroke-width=\"9\" stroke-linecap=\"round\"/><g fill=\"{K}\"><circle cx=\"46\" cy=\"18\" r=\"4.5\"/><circle cx=\"18\" cy=\"46\" r=\"4.5\"/></g>",
	# 목표 — 원 + 그 위를 지나는 십자.
	MARK: "<g fill=\"none\" stroke=\"{C}\" stroke-width=\"6\" stroke-linecap=\"round\"><circle cx=\"32\" cy=\"32\" r=\"21\"/><line x1=\"32\" y1=\"4\" x2=\"32\" y2=\"60\"/><line x1=\"4\" y1=\"32\" x2=\"60\" y2=\"32\"/></g>",
	# 현상금 — 동전 세 닢. 가운데 닢은 오른쪽으로 밀렸고 맨 위 닢만 윗면 · 조금 더 두껍다.
	BOUNTY: "<path fill=\"{C}\" stroke=\"{K}\" stroke-width=\"4.5\" d=\"M8 43 v10 a24 8 0 0 0 48 0 v-10 Z\"/><path fill=\"{C}\" stroke=\"{K}\" stroke-width=\"4.5\" d=\"M13 31 v10 a24 8 0 0 0 48 0 v-10 Z\"/><path fill=\"{C}\" stroke=\"{K}\" stroke-width=\"4.5\" d=\"M8 18 v12 a24 8 0 0 0 48 0 v-12 Z\"/><ellipse cx=\"32\" cy=\"18\" rx=\"24\" ry=\"8\" fill=\"{C}\" stroke=\"{K}\" stroke-width=\"4.5\"/>",
	# 기절 — 가늘게 시작해 왼쪽 아래에서 굵어졌다 다시 가늘어지는 고리 + 끝의 별.
	STUN: "<path fill=\"{C}\" d=\"M27.2 24.9 L24.5 25.7 L21.8 26.7 L19.3 27.9 L17.0 29.1 L14.8 30.5 L12.8 31.9 L11.1 33.4 L9.7 35.0 L8.5 36.5 L7.7 37.9 L7.1 39.3 L6.9 40.5 L6.8 41.5 L7.0 42.4 L7.3 43.1 L7.7 43.7 L8.3 44.4 L9.1 45.0 L10.1 45.6 L11.4 46.3 L12.9 46.9 L14.6 47.4 L16.6 47.8 L18.8 48.1 L21.1 48.3 L23.5 48.3 L26.1 48.3 L28.7 48.0 L31.3 47.7 L33.9 47.2 L36.5 46.6 L39.0 45.9 L41.4 45.1 L43.7 44.1 L45.8 43.1 L47.7 42.0 L49.4 40.9 L51.0 39.7 L52.2 38.6 L53.3 37.4 L54.1 36.2 L54.6 35.0 L55.0 33.8 L55.1 32.6 L54.9 31.3 L54.4 30.1 L53.5 28.8 L52.4 27.6 L53.1 26.6 L54.6 27.7 L55.9 29.0 L56.9 30.4 L57.7 32.0 L58.2 33.8 L58.2 35.6 L58.0 37.6 L57.3 39.6 L56.3 41.6 L55.0 43.5 L53.4 45.4 L51.5 47.1 L49.4 48.8 L47.0 50.4 L44.5 51.8 L41.7 53.1 L38.9 54.3 L35.9 55.2 L32.9 56.0 L29.8 56.6 L26.8 57.0 L23.7 57.2 L20.7 57.2 L17.8 57.0 L15.0 56.6 L12.3 56.0 L9.8 55.1 L7.5 54.0 L5.4 52.7 L3.5 51.2 L2.0 49.4 L0.9 47.3 L0.1 45.2 L-0.1 42.9 L0.1 40.7 L0.8 38.6 L1.8 36.7 L3.1 34.8 L4.7 33.2 L6.5 31.6 L8.6 30.2 L10.8 28.9 L13.2 27.7 L15.8 26.6 L18.5 25.7 L21.2 24.9 L24.1 24.3 L27.0 23.7 Z\"/><polygon fill=\"{C}\" points=\"51.0,10.0 54.1,18.3 62.9,18.6 55.9,24.1 58.3,32.6 51.0,27.7 43.7,32.6 46.1,24.1 39.1,18.6 47.9,18.3\"/>",
	# 쿨타임 — 시계: 테두리 원 + 12시 바늘 + 3시 쪽 짧은 바늘.
	COOLDOWN: "<circle cx=\"32\" cy=\"33\" r=\"26\" fill=\"none\" stroke=\"{C}\" stroke-width=\"6\"/><g " + _STROKE + "><line x1=\"32\" y1=\"33\" x2=\"32\" y2=\"16\"/><line x1=\"32\" y1=\"33\" x2=\"44\" y2=\"39\"/></g>",
	# 전장 명중 · 회피 — 육각 타일 바탕 + 목표 / 발.
	FIELD_HIT: _HEX_BG + _HIT_INNER,
	FIELD_EVA: _HEX_BG + _EVA_INNER,
	# 교전 명중 · 회피 — 굵은 X 바탕 + 같은 안 아이콘.
	ENGAGE_HIT: _X_BG + _HIT_INNER,
	ENGAGE_EVA: _X_BG + _EVA_INNER,
	# 공격 성장 · 체력 성장 — 칼 / 하트 + 우측 하단 성장 화살표.
	ATK_GROWTH: _ATK_BODY + _GROWTH_ARROW,
	HP_GROWTH: _HP_BODY + _GROWTH_ARROW,
	# 존재감 — 머리 + 넓은 몸통, 몸통 가운데에 목표(원 + 십자)를 판 바탕색으로 파낸다.
	PRESENCE: "<g fill=\"{C}\"><circle cx=\"32\" cy=\"14\" r=\"11\"/><path d=\"M4 62 C4 41 16 29 32 29 C48 29 60 41 60 62 Z\"/></g><g fill=\"none\" stroke=\"{K}\" stroke-width=\"4\" stroke-linecap=\"round\"><circle cx=\"32\" cy=\"47\" r=\"8.5\"/><line x1=\"32\" y1=\"35\" x2=\"32\" y2=\"59\"/><line x1=\"20\" y1=\"47\" x2=\"44\" y2=\"47\"/></g>",
	# 취약 — 보호막과 같은 방패에 금이 갔다.
	VULNERABLE: "<path fill=\"{C}\" d=\"M32 4 L56 12 V30 C56 46 46 55 32 61 C18 55 8 46 8 30 V12 Z\"/><polyline fill=\"none\" stroke=\"{K}\" stroke-width=\"6.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"35,5 28,20 37,29 27,42 33,53 31,61\"/>",
}

static var _tex_cache: Dictionary = {}


## 아이콘 `key` 를 칠할 색 — 뽑기 · 버리기는 고정색, 대상은 `target_color`(카드가
## 겨누는 편), 나머지는 판의 키워드 색 `base`.
static func color_for(key: String, base: Color, target_color: Color) -> Color:
	match key:
		DRAW:
			return DRAW_COLOR
		DISCARD:
			return DISCARD_COLOR
		TARGET, TILE:
			return target_color
	return base


## `CardData.target` → 대상 아이콘 색. 적(포탑 포함)은 빨강, 아군은 초록, 그 밖
## (아군 또는 적 · 타일 · 자신 · 손)은 회색.
static func target_color(target: String) -> Color:
	match target:
		"enemy", "foe", "turret_outer", "turret_any":
			return TARGET_ENEMY_COLOR
		"ally":
			return TARGET_ALLY_COLOR
	return TARGET_ANY_COLOR


## `key` 아이콘을 `px` 정사각형으로 구운 텍스처. `color` 가 아이콘 색, `knock` 은
## 필중처럼 면 위를 파내는 아이콘이 쓰는 판 바탕색.
static func texture(key: String, px: int, color: Color,
		knock: Color = Color(0.08, 0.08, 0.12)) -> Texture2D:
	var ck: String = "%s:%d:%s:%s" % [key, px, color.to_html(), knock.to_html()]
	if _tex_cache.has(ck):
		return _tex_cache[ck] as Texture2D
	var body: String = String(_BODIES.get(key, ""))
	if body.is_empty():
		return null
	var svg: String = _HEAD + body.replace("{C}", "#" + color.to_html(false)) \
			.replace("{K}", "#" + knock.to_html(false)) + "</svg>"
	var img := Image.new()
	if img.load_svg_from_string(svg, float(px) / 64.0) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[ck] = tex
	return tex
