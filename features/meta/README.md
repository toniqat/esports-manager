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
| `run_result/` | M2 | Run-end settlement (`RunResult.settle_current_run`: score, currency, manager EXP, MVP/POM achievements → profile) + result screen `scenes/RunResult.tscn` → `run_result/README.md` |
| `collection/` · `manager/` · `traits/` · `shop/` | M8–M10 | profile screens |

Only folders that exist are real; the rest are created when their milestone starts.

## Flow (M2)
```
Lobby ── 이어하기 ──▶ load_run ──▶ MatchFlow.tscn (match_resume) / Season.tscn
  └──── 새 런 ── no run ──▶ reset_season_state ──▶ RunSetup.tscn
                 run exists → ConfirmPopup → load_run → settle_current_run("abandon")
                                            ──▶ RunResult.tscn ── 새 런 ──▶ RunSetup.tscn
                 (run file unreadable → delete_run ──▶ RunSetup.tscn, no settlement)
Season ENDING / GAME_OVER ── settle_current_run("clear" / "fail") ──▶ RunResult.tscn ── 로비로 ──▶ Lobby.tscn
```
Settlement writes the profile (unless test run) and deletes the run file — see `run_result/README.md`.
