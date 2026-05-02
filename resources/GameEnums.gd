class_name GameEnums
extends RefCounted

enum Phase { DRAW, PLAYER_ACTION, AI_ACTION }

enum Role  { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }
enum LanePosition  { LEFT = 0, CENTER = 1, RIGHT = 2, GUERRILLA = 3 }
enum BattlePhase { GAMBIT, CARD_PHASE, BATTLE }
enum RecallState { NONE, RETREATING, CHANNELING }
enum TowerLevel { HQ, LEVEL_2, LEVEL_1 }
enum Lane { NONE = -1, LEFT = 0, CENTER = 1, RIGHT = 2 }

# Match flow (out-of-battle) phases
enum MatchPhase { LOAD, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }
enum JungleStartDir { LEFT = 0, RIGHT = 1 }
enum DraftSide { BLUE = 0, RED = 1 }
