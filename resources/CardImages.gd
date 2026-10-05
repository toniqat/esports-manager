class_name CardImages
extends RefCounted

# 카드 한 장의 **일러스트 조회**. `PilotImages` / `MechImages` 와 같은 자리이고,
# 규칙도 같다 — 그림을 어디서 가져오는지는 이 파일 하나만 안다.
#
#   images/card/<이름>.png   — 그 카드 전용 아트(있으면 언제나 이쪽이 이긴다)
#   images/ground/deadlock_items/<타입>_<아이템>.png — `ITEM_ART` 가 카드 이름에 짝지은
#                              Deadlock 아이템 아이콘(효과가 비슷한 아이템으로 골랐다).
#                              접두사 `wpn_` / `spt_` / `vit_` 는 deadlock.wiki/Items 의
#                              Weapon / Spirit / Vitality 분류 — 카드 타입(`type_for`)의 근거다
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
## 카드 이름 → Deadlock 아이템 파일명(확장자 없이, 타입 접두사 포함). cards.csv + mech_cards.csv 107장 전부,
## 한 아이템은 한 카드에만 쓴다. 카드를 더하거나 이름을 바꾸면 여기도 고친다
## (빠지면 조용히 배경 5종으로 떨어진다).
const ITEM_ART: Dictionary = {
	"교전 개시": "wpn_Opening Rounds",
	"완벽한 기회": "vit_Cloak of Opportunity",
	"결투": "wpn_Point Blank",
	"전투 준비": "wpn_Active Reload",
	"정밀 이동": "wpn_Kinetic Dash",
	"찌르기": "wpn_Rapid Rounds",
	"정밀 공격": "wpn_Sharpshooter",
	"연속 공격": "wpn_Burst Fire",
	"전진": "wpn_Fleetfoot",
	"교환": "spt_Quicksilver Reload",
	"조정": "spt_Compress Cooldown",
	"임기응변": "spt_Focus Lens",
	"재빠른 사고": "spt_Rapid Recharge",
	"집중": "spt_Superior Cooldown",
	"사전 준비": "spt_Transcendent Cooldown",
	"아드레날린": "vit_Fury Trance",
	"계획 살인": "wpn_Headhunter",
	"복귀": "vit_Rescue Beam",
	"보호": "vit_Grit",
	"약탈": "spt_Spirit Snatch",
	"소극적인 태세": "vit_Battle Vest",
	"공격적인 라인전": "wpn_Close Quarters",
	"재고": "spt_Refresher",
	"완벽한 마무리": "vit_Eternal Gift",
	"계획 중시": "spt_Duration Extender",
	"과감한 정리": "wpn_Titanic Magazine",
	"솔로 퍼포먼스": "wpn_Glass Cannon",
	"정글 파밍": "wpn_Monster Rounds",
	"전령 제압": "spt_Tankbuster",
	"용 보상": "vit_Trophy Collector",
	"핫핸드": "wpn_Lucky Shot",
	"이동": "vit_Sprint Boots",
	"골드러시": "wpn_Intensifying Magazine",
	"몰입": "wpn_Berserker",
	"워밍업": "vit_Extra Stamina",
	"신중한 예산": "spt_Superior Duration",
	"성장 가속": "spt_Extra Charge",
	"대결": "vit_Shadow Strike",
	"매복": "wpn_Shadow Weave",
	"무모한 돌격": "vit_Return Fire",
	"자신감": "wpn_Headshot Booster",
	"맑은 정신": "vit_Dispel Magic",
	"준비 태세": "wpn_Capacitor",
	"천둥 폭풍": "spt_Lightning Scroll",
	"천공의 일격": "spt_Spirit Strike",
	"꿰뚫는 번개": "wpn_Tesla Bullets",
	"캐시": "spt_Golden Goose Egg",
	"스캐빈저": "spt_Decay",
	"로켓 펀치": "wpn_Crushing Fists",
	"미사일": "wpn_Alchemical Fire",
	"미사일 준비": "wpn_Extended Magazine",
	"정밀 폭격": "wpn_Split Shot",
	"전장 강타": "wpn_Ricochet",
	"계시": "spt_Mystic Reverb",
	"결속": "wpn_Heroic Aura",
	"락온": "wpn_Haunting Shot",
	"테러": "spt_Torment Pulse",
	"파괴": "spt_Mystic Burst",
	"승전보": "vit_Celestial Blessing",
	"돌격": "wpn_Melee Charge",
	"질주": "wpn_Recharging Rush",
	"철거": "wpn_Armor Piercer",
	"우세한 전장": "vit_Juggernaut",
	"격렬한 돌진": "vit_Unstoppable",
	"처형": "wpn_Crippling Headshot",
	"일격": "wpn_Swift Striker",
	"휩쓸기": "spt_Cold Front",
	"유령의 올가미": "vit_Phantom Strike",
	"전쟁의 사슬": "spt_Cursed Relic",
	"영혼 포식": "vit_Leech",
	"몸집 불리기": "vit_Colossus",
	"추적": "wpn_Hunter's Aura",
	"강습": "vit_Majestic Leap",
	"최첨단 보호": "vit_Reactive Barrier",
	"초고출력": "spt_Surge of Power",
	"개시": "spt_Arctic Blast",
	"주먹다짐": "vit_Rebuttal",
	"고통과 쾌감": "wpn_Blood Tribute",
	"제압 전투": "spt_Suppressor",
	"리부트": "spt_Omnicharge Signet",
	"단계 A": "spt_Mystic Vulnerability",
	"단계 B": "wpn_Spirit Rend",
	"단계 C": "spt_Boundless Spirit",
	"약자 멸시": "wpn_Stalker",
	"전격전": "vit_Electric Slippers",
	"즉발 베기": "wpn_Runed Gauntlets",
	"명상": "spt_Mystic Regeneration",
	"질풍": "vit_Warp Stone",
	"신속": "wpn_Frenzy",
	"최면": "spt_Slowing Hex",
	"매혹적인 침공": "spt_Vortex Web",
	"매혹": "vit_Siphon Bullets",
	"공격 명령": "vit_Healing Nova",
	"투자": "wpn_Cultist Sacrifice",
	"간보기": "wpn_Mystic Shot",
	"지원 보호": "vit_Guardian Ward",
	"수호": "vit_Divine Barrier",
	"강타": "spt_Knockdown",
	"탈진": "spt_Disarming Hex",
	"변덕": "spt_Unstable Concoction",
	"밸런스": "vit_Infuser",
	"파란 약": "spt_Improved Spirit",
	"붉은 가루": "vit_Extra Health",
	"녹색 병": "wpn_Hollow Point",
	"죽음의 손가락": "spt_Escalating Exposure",
	"확신": "spt_Mercurial Magnum",
	"사형 선고": "spt_Scourge",
}
## 카드 타입 — 아이템 파일명의 접두사. 이름판 색(`Card.TYPE_COLORS`)이 이것을 읽는다.
const TYPE_WEAPON: String = "wpn"
const TYPE_SPIRIT: String = "spt"
const TYPE_VITALITY: String = "vit"
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


## 이 카드의 타입(`TYPE_*`). `ITEM_ART` 에 없는 카드는 빈 문자열 — 호출자가 중립색을 쓴다.
## 전용 아트(`images/card/`)가 생겨도 타입은 짝지은 아이템을 따른다.
static func type_for(card_name: String) -> String:
	var item_name: String = ITEM_ART.get(card_name, "")
	var prefix: String = item_name.get_slice("_", 0)
	if prefix in [TYPE_WEAPON, TYPE_SPIRIT, TYPE_VITALITY]:
		return prefix
	return ""


## 이름 해시로 고른 배경 한 장. 전용 아트를 건너뛰고 배경만 필요할 때 쓴다.
static func ground_for(card_name: String) -> Texture2D:
	if GROUND_COUNT <= 0:
		return null
	var idx: int = absi(card_name.hash()) % GROUND_COUNT + 1
	var path: String = GROUND_DIR + "%d.png" % idx
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
