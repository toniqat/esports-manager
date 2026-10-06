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
| `run_setup/` | M1 ✅ | Run setup (`scenes/RunSetup.tscn`): scenario → team → 5-pilot lineup (levels · salary cap) → `GameManager.start_run` → `Season.tscn`. Manager-preset step slots in later (M3/M9) → `run_setup/README.md` |
| `run_result/` | M2 | Run-end settlement (`RunResult.settle_current_run`: score, currency, manager EXP, MVP/POM achievements → profile) + result screen `scenes/RunResult.tscn` → `run_result/README.md` |
| `traits/` | M8 | `TraitSystem` — trait table, bonus points, run-time effect reads, unlocks → `traits/README.md` |
| `manager/` | M9 | `ManagerProgress` (levels, removal / specialisation, presets, prestige) + lobby `감독` tab → `manager/README.md` |
| `collection/` | M10 | Lobby `컬렉션` tab — pilots, levels, breakthroughs → `collection/README.md` |
| `shop/` | M10 | `PassSystem` + lobby `상점` / `패스` tabs (gacha, shards, crafting, pass) → `shop/README.md` |

The lobby is a **tab host** (홈 · 컬렉션 · 감독 · 상점 · 패스) — tab contract in `lobby/README.md`.

## Flow (M2)
```
Lobby ── 이어하기 ──▶ load_run ──▶ MatchFlow.tscn (match_resume) / Season.tscn (HUB)
  └──── 새 런 ── no run ──▶ reset_season_state ──▶ RunSetup.tscn
                 run exists → ConfirmPopup → load_run → settle_current_run("abandon")
                                            ──▶ RunResult.tscn ── 새 런 ──▶ RunSetup.tscn
                 (run file unreadable → delete_run ──▶ RunSetup.tscn, no settlement)
RunSetup: 시나리오 ─▶ 팀 ─▶ 편성 (PICK ↔ CONFIRM) ── 게임 시작 ──▶ GameManager.start_run(run_setup)
  ├── "" ──▶ Season.tscn (HUB, autosave: run_start)
  ├── error ──▶ stays on 편성, error in the gauge line
  └── 뒤로 on 시나리오 ──▶ Lobby.tscn
Season ENDING / GAME_OVER ── settle_current_run("clear" / "fail") ──▶ RunResult.tscn ── 로비로 ──▶ Lobby.tscn
```
Settlement writes the profile (unless test run) and deletes the run file — see `run_result/README.md`.
Season has no DRAFT screen — it always opens at HUB (`features/season/README.md` "Entry point").
