class_name CardImages
extends RefCounted

# 카드 한 장의 **일러스트 조회**. `PilotImages` / `MechImages` 와 같은 자리이고,
# 규칙도 같다 — 그림을 어디서 가져오는지는 이 파일 하나만 안다.
#
#   images/card/<이름>.png   — 그 카드 전용 아트(있으면 언제나 이쪽이 이긴다)
#   images/ground/N.png      — 전용 아트가 없는 카드가 나눠 쓰는 **배경 5종**
#
# **배경은 카드 이름으로 고른다**(`card_name.hash()`). 무작위로 고르면 같은 카드가
# 뽑을 때마다 다른 그림을 달고 나와 "이 그림이 이 카드"라는 연결이 서지 않고,
# 순번으로 고르면 손패에 들어온 순서가 그림을 정해 같은 카드가 자리마다 달라진다.
# 이름 해시는 실행과 무관하게 같은 답을 주므로, 전용 아트가 채워지기 전까지도
# 카드 한 장이 자기 그림을 계속 들고 다닌다.
#
# **`load()` 를 그냥 부르지 않는다** — 파일이 없으면 Godot 이 에러를 뱉으며 null 을
# 돌려주므로 `ResourceLoader.exists()` 로 먼저 묻는다(`MechImages` 와 같은 이유).

const CARD_DIR: String = "res://resources/images/card/"
const GROUND_DIR: String = "res://resources/images/ground/"
## `images/ground/` 에 들어 있는 배경 장수. 파일을 더하면 이 수만 올린다.
const GROUND_COUNT: int = 5


## 이 카드가 걸칠 아트. 전용 아트 → 이름으로 고른 배경 순으로 찾고,
## 둘 다 없으면 null(호출자는 그때 빈 자리를 그대로 둔다).
static func art_for(card_name: String) -> Texture2D:
	if card_name.is_empty():
		return null
	var own: String = CARD_DIR + card_name + ".png"
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	return ground_for(card_name)


## 이름 해시로 고른 배경 한 장. 전용 아트를 건너뛰고 배경만 필요할 때 쓴다.
static func ground_for(card_name: String) -> Texture2D:
	if GROUND_COUNT <= 0:
		return null
	var idx: int = absi(card_name.hash()) % GROUND_COUNT + 1
	var path: String = GROUND_DIR + "%d.png" % idx
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
