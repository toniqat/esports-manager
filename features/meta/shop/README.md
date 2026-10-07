# Shop · Pass (M10)

Lobby `상점` / `패스` tabs — local gacha, shard purchases, trait crafting, currency exchange,
free weekly pass. Contract: `docs/outgame_dev_plan.md` §12 (row E). Tab contract:
`features/meta/lobby/LobbyScreen.gd` header.

## Files
| File | Class | Role |
|---|---|---|
| `Gacha.gd` | `class_name Gacha extends RefCounted` (static) | Gacha rules + the one pull action: rates (`gacha_rates.csv`), named-pilot / trait buckets, rarity roll, cost, `pull(pm, pool, count, rng, save)` |
| `ShopCatalog.gd` | `class_name ShopCatalog extends RefCounted` (static) | Fixed-price actions: shard purchase, trait craft, outgame → levelup exchange, premium → tickets, dev premium grant. Do not save |
| `PassSystem.gd` | `class_name PassSystem extends RefCounted` (static) | Weekly pass rules over the profile dict: ISO-week reset (device clock, local time), exp → level, overflow → outgame currency, `pass_rewards.csv`, `claim` / `claim_all` |
| `ShopTab.gd` | `class_name ShopTab extends Control` | 상점 tab — segmented control (선수 영입 · 특성 연구 · 파편 상점 · 특성 제작 · 교환소), no action bar |
| `PassTab.gd` | `class_name PassTab extends Control` | 패스 tab — header (week · reset countdown · level · exp bar) + 25 reward rows, action bar `모두 수령` |
| `ShopPopup.gd` · `ShopPopup.tscn` | `class_name ShopPopup extends CanvasLayer` | Modal for both tabs: gacha / purchase **reveal** cards and the **rates** table — see **ShopPopup scene** below. Also owns `rarity_color` (delegates to `TraitUi.rarity_color` — one rarity palette for both pools), `currency_label` (`CURRENCY_LABELS`), `wrap_label` |
| `ShopRevealItem.gd` · `ShopRevealItem.tscn` | `class_name ShopRevealItem extends Panel` | One reveal card (168 × 300 tile) — `show_result(e)` fills it and paints the rarity / result colours |
| `ShopRateRow.tscn` | *(no script)* | One rates-table row (divider · rarity chip · % · count · per-item %), filled by `ShopPopup.open_rates` |

## ShopPopup scene
Layout is authored in the `.tscn` files (`docs/ui_scene_migration.md`); scripts only bind `%` nodes.
Create with `ShopPopup.create()` (`ShopPopup.new()` is an empty layer). Open / close toggles `visible`;
the nodes are reused, items from the previous open are removed and re-instanced.
```
ShopPopup (CanvasLayer 20 — 씬은 visible 로 저장, `create()` 가 숨김)
└ Root (full rect, theme = OutgameTheme.tres)
  ├ %Dim        flat Button — tap outside the card = close
  ├ DimRect     Panel `DimPanel`
  └ %SafeArea   CenterContainer — top / bottom offsets = safe area (code)
    └ Card      PanelContainer `PopupCardWide` (padding 40 — 5 result cards don't fit `PopupCard`'s 48), min width 980 (STOP)
      └ VBox    ─ %Title `TitleLabel` · Gap · %Grid · %Rates · Gap · %Ok `PrimaryButton`
                  %Grid  GridContainer (14 / 14), ShopRevealItem × n, columns = min(n, 5)
                  %Rates VBox ─ Head (4 `CaptionLabel` columns) · %RateRows (ShopRateRow × rarity)
                                · Gap · %Note `CaptionLabel` (wrap) · Tail
```
- **Scene owns**: sizes, gaps, column widths (270 · 225 · 207 · 198), fonts, card / button / dim styles
  (theme variations), item tile layout.
- **Code owns**: texts, grid column count, instancing items, the safe-area offsets, and every
  **data-driven colour** — reveal card border + band (rarity), trait mark (`POSITIVE` / `NEGATIVE`),
  result tag chip (NEW / 돌파 / 파편 / 재료), rates chip (rarity). White text on those fills is the
  `OnFillLabel` variation in the item scenes (the tag text colour stays code — it depends on the tag).

## Gacha rules (`Gacha`)
- Pools `pilot` / `trait`. Rarity is rolled by the pool's `gacha_rates.csv` weights
  (`RandomNumberGenerator.rand_weighted`), then one item of that rarity uniformly:
  - pilot = a **named** pilot (`players.is_mob = 0`) with that `players.rarity`;
  - trait = a `traits.csv` row with that `rarity`.
  An empty rarity bucket falls back to the nearest non-empty one (lower first on a tie) —
  `resolve_bucket`. Rates popup shows per-rarity %, item count and per-item %.
- Grant: pilots → `ProfileManager.grant_pilot` (new → breakthrough 1..`BREAKTHROUGH_MAX` →
  shards `SHARD_PER_EXTRA_DUPE` × rarity); traits → `grant_trait` (new → material
  `TRAIT_DUPE_MAT` × (rarity + 1)).
- Cost (`cost_of`): one pool ticket (`gacha_ticket_pilot` / `gacha_ticket_trait`) per pull while
  any are left, the rest in outgame currency at `GACHA_PILOT_PRICE` / `GACHA_TRAIT_PRICE`.
  A multi pull (`GACHA_MULTI_COUNT`) takes `GACHA_MULTI_DISCOUNT_PCT` off its currency part
  (rounded up). Not affordable → error, nothing spent.
- `pull` = check → spend → roll → grant → **one** `save_profile()` (`save=false` for tests).
  `rng` is injectable (seeded tests). Result `{error, cost, results: [{pool, id, rarity, result,
  stage, shards, amount}], save_error}` feeds `ShopPopup.open_reveal`.

## Shop sections (`ShopTab` + `ShopCatalog`)
- **선수 영입 / 특성 연구** — banner (rate chips, `확률 보기` → rates popup), holdings
  (tickets · outgame · owned count), `1회` (ghost) / `N회` (primary) buttons showing the exact
  cost, disabled when unaffordable. Reveal tags: NEW / 돌파 n / 파편 +n / 재료 +n.
- **파편 상점** — every named pilot, rarity desc. Price `SHOP_SHARD_PRICE_R1..R4` by
  `players.rarity` in `pilot_shard` → `grant_pilot` (new, or dupe → breakthrough). Not sold once
  the breakthrough is maxed (`돌파 완료` — the dupe would only become shards again).
- **특성 제작** — every trait; `traits.craft_cost` in `trait_mat` → `grant_trait`.
  `craft_cost = 0` = `제작 불가`; owned = `보유 중` (disabled — crafting it would only refund material).
- **교환소** — `SHOP_LEVELUP_EXCHANGE_COST` outgame → `SHOP_LEVELUP_EXCHANGE_GAIN` levelup;
  `SHOP_PILOT_TICKET_PREMIUM` / `SHOP_TRAIT_TICKET_PREMIUM` premium → 1 ticket; and a clearly
  labelled **개발용** row "유료 재화 +`SHOP_DEV_PREMIUM_GRANT` (개발용)" (premium is a local
  number only, §12.0).
- After any purchase: `save_profile()` once, `host.refresh_currency()`, `host.refresh_badges()`,
  redraw (scroll position kept per section). Errors → red host toast.
- Scroll rows: row panels IGNORE, row buttons PASS (`docs/mobile_safe_area.md` §5).

## Pass rules (`PassSystem` + `PassTab`)
- Exp from run settlement (`RunResult`: score × `PASS_EXP_PER_SCORE`); level = 1 + exp /
  `PASS_EXP_PER_LEVEL`, capped at `PASS_MAX_LEVEL` (level 1 is reached at 0 exp); exp past the cap
  converts to outgame currency (`PASS_OVERFLOW_OUTGAME` per level's worth) inside `add_exp`.
- Week = ISO week of the **device clock in local time** (`week_id_now` → `local_unix_now`); the
  reset is Monday 00:00 local, `seconds_until_reset()` drives the countdown.
- `claim(profile, level)`: `ensure_week` first; refused when out of range, not reached, already
  claimed or rewardless; otherwise adds the reward to `profile.currency` and appends the level to
  `claimed`. "" on success. `claimable_levels` / `claim_all` (→ `{count, gained}`) /
  `level_progress` (→ `{into, need}`) are helpers. Mutators do not save.
- Tab: `on_shown` runs `ensure_week` (saves when the week turned) and scrolls to the first
  claimable / current level. Rows: reached + unclaimed = amber row + `수령`; claimed = `수령 완료`;
  not reached = `잠김`. `모두 수령` is disabled when nothing is claimable. Each claim saves once and
  refreshes the host currency strip.

## Const keys
`GACHA_PILOT_PRICE` · `GACHA_TRAIT_PRICE` · `GACHA_MULTI_COUNT` · `GACHA_MULTI_DISCOUNT_PCT` ·
`SHOP_SHARD_PRICE_R1..R4` · `SHOP_LEVELUP_EXCHANGE_COST` · `SHOP_LEVELUP_EXCHANGE_GAIN` ·
`SHOP_PILOT_TICKET_PREMIUM` · `SHOP_TRAIT_TICKET_PREMIUM` · `SHOP_DEV_PREMIUM_GRANT`
(+ read: `PASS_*`, `BREAKTHROUGH_MAX`, `SHARD_PER_EXTRA_DUPE`, `TRAIT_DUPE_MAT`).
