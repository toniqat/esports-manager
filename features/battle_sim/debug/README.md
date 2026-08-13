# Debug Module

| File | class_name | Role |
|---|---|---|
| `BattleLogger.gd` | BattleLogger | Full battle action log + enemy cross-over detector |

## BattleLogger.gd
`extends Node` — child of BattleSim, created and bound in `BattleSim._ready()`
**after** `_gambit.launch_battle()` so its header can dump the spawned roster.
Reachable from every module as `_bs.blog`.

### Output
Both at once:
- **console** — every line prefixed `[BLOG] ` so it greps cleanly out of the
  Godot output panel / a headless stdout capture.
- **file** — `user://battle_logs/battle_<YYYY-MM-DD_HH-MM-SS>.log`. The
  absolute path is printed in the header's second line. On Windows that is
  `C:/Users/<you>/AppData/Roaming/Godot/app_userdata/EsportsManager/battle_logs/`.

Three switches on the instance: `enabled` (kills everything), `echo_to_console`,
`write_to_file`. All default to `true` — this is a debugging build aid, so turn
`enabled` off in `BattleSim._ready()` if the console noise gets in the way.

### Line format
```
[T0006][4-freemove][MOVE  ] Su1  (2, -3) → (2, -2)  [free] axis 6→5  (step 1/1, enemies on dest: Sn0)
 turn    stage        cat
```
`stage` is set by `SimulationCore` as it walks the turn, so every line says
which pass of the tick produced it:

| stage | what runs |
|---|---|
| `turn-open` / `turn-close` | before / after position snapshots |
| `1-respawn` | `process_respawns` |
| `2-recall` | `RecallSystem.process_recalls` |
| `3-engage` | `_resolve_cell` per occupied cell — `CELL`, `FIGHT`, `SETS` |
| `4-damage` | damage/turret application, deaths |
| `5-move` | `resolve_movement` — free moves *and* pushes, `kind` says which |
| `6-hq` | HQ chip damage |
| `7-zones` | neutral capture + 약탈 expiry |
| `card-phase` / `phase-end` / `card-adv` | 작전 단계 entry, exit, 전진 card |

Categories: `TURN SNAP CELL FIGHT SETS MOVE BLOCK DMG DEATH TURRET HQ ZONE
CARD PHASE ENGAGE !!SWAP !!CROSS`.

Every `MOVE` line carries `enemies on dest:` — who was already standing on the
destination cell at the moment of the step. That field is what makes a
pass-through visible: the mover records the enemy it walked into, and the
enemy's own push line a stage later shows it leaving.

### Cross-over detector
`end_turn()` diffs the turn-open snapshot against the live positions and reports
two same-scope enemies (both lane pilots, or both junglers — a jungler passing
a laner is by design) that traded places:

- **`!!SWAP`** — `A` ended exactly where `B` started and vice versa. Always
  reported, at any distance.
- **`!!CROSS`** — the pair is **on the same lane**, their order along the lane
  axis flipped, they stayed within `NEAR_DIST` (2) of each other at both ends of
  the turn, and they did not finish in the same cell. The axis is
  `hex_distance(PLAYER_HQ_POS, cell)`, which is monotonic along every lane path.

Both clamps on `!!CROSS` are load-bearing. The axis alone makes two pilots on
opposite side lanes trade ranks constantly, and **cross-lane pairs are not a bug
at all**: with same-cell-only combat there is no zone of control, so two enemies
one cell apart on different lanes legitimately walk to different cells and end
up on opposite sides of each other. The most common instance is at an HQ cell,
where a recalled defender heads out down its own lane as an attacker from
another lane steps onto the HQ. Junglers both carry `LanePosition.GUERRILLA`,
so the same-lane clamp keeps jungler-vs-jungler pairs in scope.

Pilots that died or respawned during the turn are skipped so the HQ teleport
doesn't register as a crossing. Each report is followed by `trace` lines
replaying every recorded move of the two pilots in stage order.

### What it found

**1 — pass-through on the two-pass movement split** *(fixed)*. An un-engaged
pilot walked into an enemy's cell, and that enemy pushed out into the cell just
vacated, so the pair traded places without engaging. Two `!!SWAP`s in a
6-battle headless run. Fixed by collapsing free movement and push movement into
the single lockstep pass `resolve_movement`; zero reports in 241 turns
afterwards.

**2 — 밀어내도 라인이 밀리지 않던 문제** *(fixed)*. Not a cross-detector hit —
this one is only visible by reading `MOVE` lines side by side, which is exactly
what the per-stage log is for. A push looks like this, and it is **correct**:

```
[T0006][5-move][MOVE] T0  (-4, -2) → (-4, -1)  [push-ret]  (enemies on dest: T1)
[T0006][5-move][MOVE] T1  (-4, -2) → (-4, -1)  [push-adv]  (enemies on dest: T0)
```

Winner and loser land on the same cell because advance heads for the enemy HQ
and retreat heads for the retreater's own HQ — the same direction — so the pair
slides one tile up the lane and fights again there. For a while this was read as
a bug and `_veto_push_followthrough` cancelled the *advance* so the loser was
"expelled" and the winner held the cell. On a straight lane those two
destinations **always** coincide, so the winner of a fight could then never move
forward at all: the line never pushed. The veto now only fires when the loser
cannot retreat (`_veto_advance_over_stuck_enemy`), and reads

```
[T0006][5-move][BLOCK] T1  @(-4, -2) halted — push-advance held — T0 가 (-4, -2) 에서 밀려나지 못했다
```

A push that stops because the tile ahead is an enemy turret logs the siege
bounce instead (`공성 — … 적 포탑 칸에 진입 후 한 칸 후퇴`).

Details for both in [`../combat/README.md`](../combat/README.md) → "Movement".
