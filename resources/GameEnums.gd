class_name GameEnums
extends RefCounted

enum Phase { DRAW, PLAYER_ACTION, AI_ACTION }

enum Role  { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }
enum Lane  { LEFT = 0, CENTER = 1, RIGHT = 2, GUERRILLA = 3 }
enum BattlePhase { GAMBIT, CARD_PHASE, BATTLE }
enum RecallState { NONE, RETREATING, CHANNELING }
