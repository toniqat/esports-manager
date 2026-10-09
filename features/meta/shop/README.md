# Shop · Pass (M10)

Lobby `상점` / `패스` tabs — local gacha, shard purchases, trait crafting, currency exchange,
free weekly pass. Contract: `docs/outgame_dev_plan.md` §12 (row E). Tab contract:
`features/meta/lobby/LobbyScreen.gd` header.

표시 텍스트는 l10n key (`shop` 도메인 + 공유 `ui.*` · `term.*`) — rule messages (`Gacha.check`, `ShopCatalog`, `PassSystem.claim`)
are returned already translated (`Loc.t`, never stored); tier names via `ShopPopup.tier_label(pool, tier)` (pilots =
stars `GameEnums.star_label`, traits = `GameEnums.rarity_label`), colours via `tier_color` (`star_color` maps ★1..★3 onto the
shared palette's uncommon · rare · legendary). Scene nodes the scripts
fill carry `auto_translate_mode = 2` (on the root of the fully code-filled item scenes); fixed captions are key literals.
Currency names inside sentences are `{tx_…}` references to `term.currency.*` / `term.currency.levelup`
(one place to rename a currency); the gacha 보유 선수 line uses `term.pilot.owned`.

## Files
| File | Class | Role |
|---|---|---|
| `Gacha.gd` | `class_name Gacha extends RefCounted` (static) | Gacha rules + the one pull action: rates (`gacha_rates.csv`), named-pilot / trait buckets (`named_pilots` rows carry `name_key`; `pilot_name(id)` = `Loc.t`), tier roll, cost, `pull(pm, pool, count, rng, save)`, `rank_stone_total(results)` |
| `ShopCatalog.gd` | `class_name ShopCatalog extends RefCounted` (static) | Fixed-price actions: shard purchase, trait craft, outgame → levelup / rank stone exchange, premium → tickets, dev premium grant. Do not save |
| `PassSystem.gd` | `class_name PassSystem extends RefCounted` (static) | Weekly pass rules over the profile dict: ISO-week reset (device clock, local time), exp → level, overflow → outgame currency, `pass_rewards.csv`, `claim` / `claim_all` |
| `ShopTab.gd` · `UI_View_ShopTab.tscn` | `class_name ShopTab extends Control` | 상점 tab — segmented control (선수 영입 · 특성 연구 · 파편 상점 · 특성 제작 · 교환소), no action bar — see **ShopTab · PassTab scenes** below |
| `UI_Comp_ShopRateChip.tscn` · `UI_Comp_ShopShardRow.tscn` · `UI_Comp_ShopCraftRow.tscn` · `UI_Comp_ShopExchangeRow.tscn` | *(no script)* | ShopTab items: banner rate pill · 파편 상점 row (`%PositionBadge_Position` = `PositionBadge`) · 특성 제작 row · 교환소 row, filled by `ShopTab` |
| `PassTab.gd` · `UI_View_PassTab.tscn` | `class_name PassTab extends Control` | 패스 tab — header (week · reset countdown · level · exp bar) + 25 reward rows, action bar `모두 수령` |
| `UI_Comp_PassRow.tscn` | *(no script)* | One pass level row (Lv chip · reward · `수령` button or status), filled by `PassTab` |
| `ShopPopup.gd` · `UI_View_ShopPopup.tscn` | `class_name ShopPopup extends CanvasLayer` | Modal for both tabs: gacha / purchase **reveal** cards and the **rates** table — see **ShopPopup scene** below. Also owns `rarity_color` (delegates to `TraitUi.rarity_color` — one rarity palette for both pools), `star_color` / `tier_label` / `tier_color` (pilots by stars, traits by rarity), `currency_label` (`CURRENCY_LABELS` = l10n keys `term.currency.*` · `term.currency.levelup` · `term.currency.rank_stone`, translated on read), `wrap_label` |
| `ShopRevealItem.gd` · `UI_Comp_ShopRevealItem.tscn` | `class_name ShopRevealItem extends Panel` | One reveal card (168 × 300 tile) — `show_result(e)` fills it and paints the rarity / result colours |
| `UI_Comp_ShopRateRow.tscn` | *(no script)* | One rates-table row (divider · rarity chip · % · count · per-item %), filled by `ShopPopup.open_rates` |

## F6 preview (standalone run)
Every scripted scene here (`ShopTab`, `PassTab`, `ShopPopup`, `ShopRevealItem`) shows dummy data when run on its own (editor "Run Current Scene") — `_ready` →
`UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script
(`resources/UiPreview.gd`). Nothing is saved: buttons that would save the profile are re-wired
to only print (`UiPreview.mute`).
- `ShopTab` — real profile, 선수 영입 section; pulls open the reveal popup with fake results (no
  profile change), every list-row `%Buy` and the dev grant only print.
- `PassTab` — real profile's week (week roll-over in memory only); `수령` only prints.
- `ShopPopup` — a 10-pull reveal (NEW · 돌파 · 파편 · 재료). `ShopRevealItem` — one 돌파 2 card.

## ShopPopup scene
Layout is authored in the `.tscn` files (`docs/ui_scene_migration.md`); scripts only bind `%` nodes.
Create with `ShopPopup.create()` (`ShopPopup.new()` is an empty layer). Open / close toggles `visible`;
the nodes are reused, items from the previous open are removed and re-instanced.
```
ShopPopup (CanvasLayer 20 — 씬은 visible 로 저장, `create()` 가 숨김)
└ Root (full rect, theme = OutgameTheme.tres)
  ├ %Dim        flat Button — tap outside the card = close
  ├ DimRect     Panel `DimPanel`
  └ %SafeArea   Control (full rect) — top / bottom offsets = safe area (code)
    └ %Center   CenterContainer (full rect, offsets 40 / −40 = margin from the safe edges)
      └ %Card   PanelContainer `PopupCardWide` (padding 40 — 5 result cards don't fit `PopupCard`'s 48), min width 980 (STOP)
        └ VBox  ─ %Title `TitleLabel` · Gap · %Scroll · Gap · %Ok `PrimaryButton`
                  %Scroll ScrollContainer (horizontal off, + DragScroll) → %Body VBox ─ %Grid · %Rates
                  %Grid  GridContainer (14 / 14), ShopRevealItem × n, columns = min(n, 5)
                  %Rates VBox ─ Head (4 `CaptionLabel` columns) · %RateRows (ShopRateRow × rarity)
                                · Gap · %Note `CaptionLabel` (wrap) · Tail
```
- **Tall content scrolls, the frame doesn't** (`_fit_body`): the card is centred in `%Center` while it fits;
  `%Scroll`'s min height = the body's height, capped at `%Center`'s height (from its anchors / offsets) minus
  everything else on the card. Past the cap only the reveal grid / rates table scrolls — title and `%Ok` stay
  fixed, `%Ok` stays above the gesture zone. Re-fit on every open and whenever `%Card`'s minimum size changes
  (wrapped labels settle after the first layout pass) — one deferred refit per frame. When the scroll bar shows,
  the card widens by its width (the rates columns already fill the card). Normal data (1 / 5 / 10 pulls, both
  rate tables) never reaches the cap — pixel-identical to the old `CenterContainer` frame.
- **Scene owns**: sizes, gaps, column widths (270 · 225 · 207 · 198), fonts, card / button / dim styles
  (theme variations), item tile layout.
- **Code owns**: texts, grid column count, instancing items, the safe-area offsets, `%Scroll`'s height, and every
  **data-driven colour** — reveal card border + band (rarity), trait mark (`POSITIVE` / `NEGATIVE`),
  result tag chip (NEW / 돌파 / 파편 / 재료), rates chip (rarity). White text on those fills is the
  `OnFillLabel` variation in the item scenes (the tag text colour stays code — it depends on the tag).

## ShopTab · PassTab scenes
Created by `LobbyScreen._make_tab` with `ShopTab.create()` / `PassTab.create()` (`.new()` is an empty
Control). The host sets the tab's position / size (`content_rect`), then `setup(host)`. Both roots
carry `theme = OutgameTheme.tres`. Rows are re-instanced on every fill; the shells are reused.
```
ShopTab (Control)
├ Segments   Panel `SunkPanel` ─ Pad (4) ─ Row (HBox, sep 8) ─ %SegPilot · %SegTrait · %SegShard · %SegCraft · %SegExchange
└ Body       (top 124)
  ├ %GachaView  Margin (40 / 8 top) ─ VBox
  │   ├ %Banner  Panel (290, tinted card — style is code) ─ Pad ─ VBox
  │   │          Head (%BannerTitle `OnFillLabel` 52 · %RatesButton `TextButton`, white text)
  │   │          · %BannerSub (wrap) · %RateChips (HBox ← ShopRateChip × rarity)
  │   ├ Holdings Panel `Card` (120) — 3 cells anchored at thirds: %TicketLabel/Value · %MoneyLabel/Value · %OwnedLabel/Value
  │   ├ Pulls    HBox (150, sep 20) ─ %PullOne `GhostButton` · %PullMulti `PrimaryButton`
  │   └ %Note    `CaptionLabel` (wrap, centred)
  └ %ListView   VBox ─ Head (%HeadTitle · %HeadSub) · %Scroll ─ ScrollPad (40 / 8 / 40 / 28) ─ VBox (sep 12)
                ├ %Rows   (VBox, sep 12 ← ShopShardRow / ShopCraftRow / ShopExchangeRow)
                └ %DevRow (교환소 only — 개발용 premium grant: DevTitle `NegativeLabel` 30, %DevGrant `GhostButton`)
PassTab (Control) ─ VBox
├ HeadPad (40) ─ Head Panel `PopupCard` (330) ─ Pad (36 / 26 / 36 / 16) ─ VBox
│   TopRow (Title `TitleLabel` 40 · %Week) · LevelRow (%Level `AccentLabel` 56 · %MaxLevel · %Exp)
│   · Track `ProgressTrack` ─ %Fill `ProgressFill` (anchor_right = exp ratio) · %Info (wrap)
└ %Scroll ─ ScrollPad (40 / 8 / 40 / 18) ─ %Rows (VBox, sep 10 ← PassRow × PASS_MAX_LEVEL)
```
- **Scene owns**: every size / gap / margin, fonts, button kinds, fixed texts (segment labels,
  dev-row note), the row tiles (children placed by offset inside the fixed-height tiles), the
  white outlined row panel / sunk dev panel (screen variations `ShopRowPanel` — shared by the three
  `Shop*Row` scenes — and `ShopDevRowPanel`), the gacha banner `ShopBannerCard` (code puts the pool colour
  on a `variation_box` copy); the rate pill
  `ShopRateChip` is a `SurfaceChip` PanelContainer (152×44, centred label).
- **Code owns**: texts from data, enabled / disabled states, instancing rows and chips, the selected
  segment (variation `GhostButton` + `ACCENT_TEXT` vs `TextButton`), scroll positions (per shop section;
  pass jumps to the first claimable level), and every **data colour** — banner tint per pool, rarity
  chips / rate-pill text, trait +/− mark, the round pilot portrait (a `_draw` widget added into
  `%FaceSlot`), pass row fill / border / Lv chip / reward & status text by claim state.
- Scrolls use `vertical_scroll_mode = Never` (the bar was never visible; it also keeps the row width
  — an `Auto` bar would narrow the content by its width) and `DragScroll` for touch drag.
- **A node missing from these scenes was deleted on purpose** — don't re-create it in code.

## Gacha rules (`Gacha`)
- Pools `pilot` / `trait`. A tier is rolled by the pool's `gacha_rates.csv` weights
  (`RandomNumberGenerator.rand_weighted`), then one item of that tier uniformly:
  - pilot = a **named** pilot (`players.is_mob = 0`) with those **stars** (`players.rarity` ★1..★3);
  - trait = a `traits.csv` row with that `rarity`.
  An empty rarity bucket falls back to the nearest non-empty one (lower first on a tie) —
  `resolve_bucket`. Rates popup shows per-rarity %, item count and per-item %.
- Grant: pilots → `ProfileManager.grant_pilot` (new = rank = stars → breakthrough 1..RANK_MAX − stars
  (max rank +1 each) → shards `SHARD_PER_EXTRA_DUPE` × stars **plus** rank stones
  `RANK_STONE_PER_EXTRA_DUPE` × stars); traits → `grant_trait` (new → material
  `TRAIT_DUPE_MAT` × (rarity + 1)). The reveal tag of a capped dupe shows the shards; the stones of a
  pull / purchase are summed (`rank_stone_total`) into one `shop.tab.toast_rank_stone` toast.
- Cost (`cost_of`): one pool ticket (`gacha_ticket_pilot` / `gacha_ticket_trait`) per pull while
  any are left, the rest in outgame currency at `GACHA_PILOT_PRICE` / `GACHA_TRAIT_PRICE`.
  A multi pull (`GACHA_MULTI_COUNT`) takes `GACHA_MULTI_DISCOUNT_PCT` off its currency part
  (rounded up). Not affordable → error, nothing spent.
- `pull` = check → spend → roll → grant → **one** `save_profile()` (`save=false` for tests).
  `rng` is injectable (seeded tests). Result `{error, cost, results: [{pool, id, rarity, result,
  stage, shards, rank_stone, amount}], save_error}` feeds `ShopPopup.open_reveal` (pilot `rarity` = stars).

## Shop sections (`ShopTab` + `ShopCatalog`)
- **선수 영입 / 특성 연구** — banner (rate chips, `확률 보기` → rates popup), holdings
  (tickets · outgame · owned count), `1회` (ghost) / `N회` (primary) buttons showing the exact
  cost, disabled when unaffordable. Reveal tags: NEW / 돌파 n / 파편 +n / 재료 +n.
- **파편 상점** — every named pilot, stars desc (star chip). Price `SHOP_SHARD_PRICE_R1..R3` by
  stars in `pilot_shard` → `grant_pilot` (new, or dupe → breakthrough). Status `돌파 n/cap` (cap =
  `breakthrough_cap_of`). Not sold once the breakthrough is at its cap (`돌파 완료` — the dupe would only
  become shards again).
- **특성 제작** — every trait; `traits.craft_cost` in `trait_mat` → `grant_trait`.
  `craft_cost = 0` = `제작 불가`; owned = `보유 중` (disabled — crafting it would only refund material).
- **교환소** — `SHOP_LEVELUP_EXCHANGE_COST` outgame → `SHOP_LEVELUP_EXCHANGE_GAIN` levelup;
  `SHOP_RANK_STONE_EXCHANGE_COST` outgame → `SHOP_RANK_STONE_EXCHANGE_GAIN` 승급석 (`rank_stone`, the pilot
  rank-up currency — `ShopCatalog.exchange_rank_stone`);
  `SHOP_PILOT_TICKET_PREMIUM` / `SHOP_TRAIT_TICKET_PREMIUM` premium → `SHOP_TICKET_EXCHANGE_GAIN` tickets (`ticket_exchange_gain()`, shown as `{gain}` in the row text and the `shop.tab.toast_ticket` toast); and a clearly
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
`SHOP_SHARD_PRICE_R1..R3` · `SHOP_LEVELUP_EXCHANGE_COST` · `SHOP_LEVELUP_EXCHANGE_GAIN` ·
`SHOP_RANK_STONE_EXCHANGE_COST` · `SHOP_RANK_STONE_EXCHANGE_GAIN` ·
`SHOP_PILOT_TICKET_PREMIUM` · `SHOP_TRAIT_TICKET_PREMIUM` · `SHOP_TICKET_EXCHANGE_GAIN` · `SHOP_DEV_PREMIUM_GRANT`
(+ read: `PASS_*`, `RANK_MAX`, `SHARD_PER_EXTRA_DUPE`, `RANK_STONE_PER_EXTRA_DUPE`, `TRAIT_DUPE_MAT`).
Pass rewards (`pass_rewards.csv`) include some `rank_stone` levels.
