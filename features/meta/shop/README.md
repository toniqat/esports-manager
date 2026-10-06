# Shop · Pass (M10)

Lobby `상점` / `패스` tabs — local gacha, shard purchases, trait crafting, currency exchange,
free weekly pass. Contract: `docs/outgame_dev_plan.md` §12.

## Files
| File | Class | Role |
|---|---|---|
| `PassSystem.gd` | `class_name PassSystem extends RefCounted` (static) | Weekly pass rules over the profile dict: ISO-week reset (device clock), exp → level, overflow → outgame currency, `pass_rewards.csv` |
| `ShopTab.gd` | `class_name ShopTab extends Control` | Lobby tab (stub in the base commit) |
| `PassTab.gd` | `class_name PassTab extends Control` | Lobby tab (stub in the base commit) |
