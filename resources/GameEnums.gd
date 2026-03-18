class_name GameEnums
extends RefCounted

enum Phase { DRAW, PLAYER_ACTION, AI_ACTION }

enum Role  { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }
enum LanePosition  { LEFT = 0, CENTER = 1, RIGHT = 2, GUERRILLA = 3 }
enum BattlePhase { GAMBIT, CARD_PHASE, BATTLE }
enum RecallState { NONE, RETREATING, CHANNELING }
enum TowerLevel { HQ, LEVEL_2, LEVEL_1 }
enum Lane { NONE = -1, LEFT = 0, CENTER = 1, RIGHT = 2 }
