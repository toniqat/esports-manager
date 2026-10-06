# Meta (outgame lobby)

Everything **outside a run**: the lobby, and later run setup, run result,
collection, manager, traits and shop. Plan: `docs/outgame_dev_plan.md`
(folder layout §2.2, milestones §3).

Two layers of state (plan §2.1):
- **Profile** — permanent, `ProfileManager` autoload → `user://profile.save` (`autoloads/README.md`).
- **Run** — `GameManager.season_state` → `user://run.save` (`features/save_load/README.md`).

## Submodules
| Folder | Status | Role |
|---|---|---|
| `lobby/` | M0 ✅ | Project entry (`scenes/Lobby.tscn`): continue / new run, abandon confirm → `lobby/README.md` |
| `run_setup/` | M1 | scenario → team → manager preset → 5-pilot lineup (salary cap) |
| `run_result/` | M2 | run-end settlement (score, currency, manager EXP, unlocks) |
| `collection/` · `manager/` · `traits/` · `shop/` | M8–M10 | profile screens |

Only folders that exist are real; the rest are created when their milestone starts.

## Flow (M0)
```
Lobby ── 이어하기 ──▶ load_run ──▶ MatchFlow.tscn (match_resume) / Season.tscn
  └──── 새 런 ──(run exists → ConfirmPopup → delete_run)──▶ reset_season_state ──▶ Season.tscn (DRAFT)
Ending / GameOver ── delete_run ──▶ 로비로 (Lobby.tscn) / 다시 시작 (Season.tscn)
```
