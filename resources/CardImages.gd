class_name CardImages
extends RefCounted

# 카드 한 장의 **일러스트 조회**. `PilotImages` / `MechImages` 와 같은 자리이고,
# 규칙도 같다 — 그림을 어디서 가져오는지는 이 파일 하나만 안다.
#
#   images/card/<이름>.png   — 그 카드 전용 아트(있으면 언제나 이쪽이 이긴다)
#   images/ground/deadlock_items/<아이템>.png — `ITEM_ART` 가 카드 이름에 짝지은
#                              Deadlock 아이템 아이콘(효과가 비슷한 아이템으로 골랐다)
#   images/ground/N.png      — 위 둘 다 없는 카드(표에 없는 새 카드)가 나눠 쓰는 **배경 5종**
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
const ITEM_DIR: String = "res://resources/images/ground/deadlock_items/"
## 카드 이름 → Deadlock 아이템 파일명(확장자 없이). cards.csv + mech_cards.csv 96장 전부,
## 한 아이템은 한 카드에만 쓴다. 카드를 더하거나 이름을 바꾸면 여기도 고친다
## (빠지면 조용히 배경 5종으로 떨어진다).
const ITEM_ART: Dictionary = {
	"전투 개시": "Opening Rounds",
	"완벽한 기회": "Cloak of Opportunity",
	"결투": "Point Blank",
	"전투 준비": "Active Reload",
	"정밀 이동": "Kinetic Dash",
	"공격": "Rapid Rounds",
	"필중": "Sharpshooter",
	"연속 공격": "Burst Fire",
	"전진": "Fleetfoot",
	"교환": "Quicksilver Reload",
	"조정": "Compress Cooldown",
	"임기응변": "Focus Lens",
	"재빠른 사고": "Rapid Recharge",
	"집중": "Superior Cooldown",
	"사전 준비": "Transcendent Cooldown",
	"아드레날린": "Fury Trance",
	"계획 살인": "Headhunter",
	"복귀": "Rescue Beam",
	"보호": "Grit",
	"약탈": "Spirit Snatch",
	"안전한 파밍": "Battle Vest",
	"공격적인 라인전": "Close Quarters",
	"재고": "Refresher",
	"완벽한 마무리": "Eternal Gift",
	"계획 중시": "Duration Extender",
	"과감한 정리": "Titanic Magazine",
	"솔로 퍼포먼스": "Glass Cannon",
	"정글 파밍": "Monster Rounds",
	"전령 제압": "Tankbuster",
	"용 보상": "Trophy Collector",
	"핫핸드": "Lucky Shot",
	"이동": "Sprint Boots",
	"천둥 폭풍": "Lightning Scroll",
	"천공의 일격": "Spirit Strike",
	"꿰뚫는 번개": "Tesla Bullets",
	"캐시": "Golden Goose Egg",
	"스캐빈저": "Decay",
	"로켓 펀치": "Crushing Fists",
	"미사일": "Alchemical Fire",
	"미사일 준비": "Extended Magazine",
	"정밀 폭격": "Split Shot",
	"전장 강타": "Ricochet",
	"계시": "Mystic Reverb",
	"결속": "Heroic Aura",
	"락온": "Haunting Shot",
	"테러": "Torment Pulse",
	"파괴": "Mystic Burst",
	"승전보": "Celestial Blessing",
	"돌격": "Melee Charge",
	"질주": "Recharging Rush",
	"철거": "Armor Piercer",
	"우세한 전장": "Juggernaut",
	"격렬한 돌진": "Unstoppable",
	"처형": "Crippling Headshot",
	"일격": "Swift Striker",
	"휩쓸기": "Cold Front",
	"유령의 올가미": "Phantom Strike",
	"전쟁의 사슬": "Cursed Relic",
	"영혼 포식": "Leech",
	"몸집 불리기": "Colossus",
	"추적": "Hunter's Aura",
	"강습": "Majestic Leap",
	"최첨단 보호": "Reactive Barrier",
	"초고출력": "Surge of Power",
	"개시": "Arctic Blast",
	"주먹다짐": "Rebuttal",
	"고통과 쾌감": "Blood Tribute",
	"제압 전투": "Suppressor",
	"리부트": "Omnicharge Signet",
	"단계 A": "Mystic Vulnerability",
	"단계 B": "Spirit Rend",
	"단계 C": "Boundless Spirit",
	"약자 멸시": "Stalker",
	"전격전": "Electric Slippers",
	"즉발 베기": "Runed Gauntlets",
	"명상": "Mystic Regeneration",
	"질풍": "Warp Stone",
	"신속": "Frenzy",
	"최면": "Slowing Hex",
	"매혹적인 침공": "Vortex Web",
	"매혹": "Siphon Bullets",
	"공격 명령": "Healing Nova",
	"투자": "Cultist Sacrifice",
	"간보기": "Mystic Shot",
	"지원 보호": "Guardian Ward",
	"수호": "Divine Barrier",
	"강타": "Knockdown",
	"탈진": "Disarming Hex",
	"변덕": "Unstable Concoction",
	"밸런스": "Infuser",
	"파란 약": "Improved Spirit",
	"붉은 가루": "Extra Health",
	"녹색 병": "Hollow Point",
	"죽음의 손가락": "Escalating Exposure",
	"확신": "Mercurial Magnum",
	"사형 선고": "Scourge",
}
## `images/ground/` 에 들어 있는 배경 장수. 파일을 더하면 이 수만 올린다.
const GROUND_COUNT: int = 5


## 이 카드가 걸칠 아트. 전용 아트 → 아이템 아이콘 → 이름으로 고른 배경 순으로 찾고,
## 둘 다 없으면 null(호출자는 그때 빈 자리를 그대로 둔다).
static func art_for(card_name: String) -> Texture2D:
	if card_name.is_empty():
		return null
	var own: String = CARD_DIR + card_name + ".png"
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	var item: Texture2D = item_for(card_name)
	if item != null:
		return item
	return ground_for(card_name)


## `ITEM_ART` 가 이 카드에 짝지은 아이템 아이콘. 표에 없거나 파일이 없으면 null.
static func item_for(card_name: String) -> Texture2D:
	var item_name: String = ITEM_ART.get(card_name, "")
	if item_name.is_empty():
		return null
	var path: String = ITEM_DIR + item_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 이름 해시로 고른 배경 한 장. 전용 아트를 건너뛰고 배경만 필요할 때 쓴다.
static func ground_for(card_name: String) -> Texture2D:
	if GROUND_COUNT <= 0:
		return null
	var idx: int = absi(card_name.hash()) % GROUND_COUNT + 1
	var path: String = GROUND_DIR + "%d.png" % idx
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
