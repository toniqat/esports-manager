# awakening/ — 깨달음 (awakening) + pilot card loadouts (§15 C)

Contract: `docs/outgame_dev_plan.md` §15 (decisions §15.0 C, state §15.1, interfaces §15.2).

| File | Role |
|---|---|
| `Awakening.gd` | `class_name Awakening` (static). Gauge per pilot, queue of pending awakenings, training / match hooks. |
| `PilotLoadout.gd` | `class_name PilotLoadout` (static). Card presets per pilot (base + extras), active preset, roster-copy `apply_to`. |

*(Base stub — agent C fills this README with the rules, views and scenes.)*
