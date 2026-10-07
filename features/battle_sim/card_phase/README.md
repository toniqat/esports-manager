# Card Phase Module

**텍스트는 l10n key — `Loc.t`.** Card name / description come from `CardData.name_key` · `description_key` (`card.pilot|mech.{id}.name|desc`); `[x]` references resolve by key (`CardData.ref_entries`), card identity is `CardData.card_uid()` (art, effect sources, sort tie-break), mech rows build via `CardData.from_mech_def`. Term rules: `data/l10n/src/glossary.csv`.

| File | class_name | Role |
|---|---|---|
| `Card.gd` | Card | Visual node for a single card (카드) |
| `CardPhaseManager.gd` | CardPhaseManager | The whole operation phase (작전 단계) — deck (덱) / hand (손패) / card effects |
| `CardSelectOverlay.gd` | CardSelectOverlay | 버리기:N (Discard:N) / 보존:N (Keep:N) hand pick (drop onto the central zone) · 찾기:N (Search:N) / pick-1-of-3 boon grid pick |
| `CardTargetingOverlay.gd` | CardTargetingOverlay | Card drag = targeting overlay |
| `CardPileViewer.gd` | CardPileViewer | Browse (열람) the Deck / Discard lists (read-only) |
| `CardDragArrow.gd` | CardDragArrow | Aiming arrow linking card ↔ cursor (a chevron chain along a quadratic Bézier; only the last chevron at the cursor end is full size, the rest 75%) |
| `CardPlayPreview.gd` | CardPlayPreview | **Hand preview (손패 미리보기)** — pressing highlights the caster, dragging previews the effect (deck / discard pile chevrons · cards that will be discarded · search / keep icons + battlefield · puts preview state on the donut and cost ribbons). See the *Hand preview* section below |
| `AiCardPlayer.gd` | AiCardPlayer | AI card-play animation (centre card + description panel to its right — no keyword notes, `DESC_BOX_W` 340, top edge = card top) |
| `CardDescBox.gd` | CardDescBox | **Card description panel** — name · cost · keywords · description text · keyword notes. The card face has no description text, so every place that shows the text (panel beside the hand card · AI card · search/browse grid · ban/pick (밴픽) sheet · mech (메크) detail) builds it with this one class. **The panel has no border.** In-game panels cast a soft drop shadow downwards (`panel_style`, `DARK_SHADOW_*`; a panel nested inside a panel has its shadow turned off by `_tint_nested`). The header is one **[small cost ribbon] name** group centred in the panel (`CostRibbon.make_badge`, `COST_RIBBON_SIZE` 26×36). `build(data, width, light, cost_text, cost_color, with_notes, min_h)` measures the height directly from the font and returns it (`light` = outgame white panel); `with_notes = false` builds it without keyword notes — the hand puts the notes on separate panels from `build_keyword_panels`. `place_near` picks a spot above/below the card. Description notation rules: the **Description notation** section below. The text is resolved by `resolve_text(data)` (formulas `{expr|phrase}` and `\n`), then a `RichTextLabel` inlines an octagon indicator before every "전략 점수" (strategy points), a cost ribbon icon before every "비용" (cost) (strategy-point colour, no border), and a keyword icon before keyword words (`KeywordIcon.WORDS`) and "N턴" (N turns) (`resources/KeywordIcon.gd`, keyword colour — sky blue in-game / `ACCENT_TEXT` outgame; draw green · discard red · target in the colour of the side the card aims at) (`StrategyIcon.make_rich_label`; the detail panel's card text works the same; card names inside brackets get no icon). **Description font size (`DESC_FONT`) is 22, the same as the header name** (was 18). Below the keyword row sits an **attribute row** — `card_attributes(data)` lists `[icon] value` for **target** (`target` → enemy / ally / enemy or turret / tile / self …) · **range** (`cast_range` of target / cell cards, 99 or more = whole battlefield) · **cast area** (largest of the `area` column · the effect's `area` / `around_target` / `self_range` · engage radius) (**duration is not on the attribute row** — the text says it, e.g. "3턴 간 교전"); items that don't apply are left out (hand-only cards usually have no row at all). On the narrow hand panel (240) the row wraps, so its height is measured with a stand-in string (`_attr_measure`, icon = three characters). Korean wraps only at spaces (`UiHelpers.keep_words`) |


## Description notation (설명문 표기)

Rules that `description` in `cards.csv` · `mech_cards.csv` follows. Icons attach automatically from
words (`StrategyIcon._tokens`), so **write by the rules and the icons follow.**

- **Don't repeat what the attribute row says** — no preambles like "사거리 N 내 적 지정 —" /
  "전장 내 적 지정". Effects around the caster · target are **"범위 내 모든 적"** (all enemies in range;
  the radius is the attribute row's area value). "대상" used as a reference word (대상의 타일로 · 대상 체력) stays.
- **Target icon** = decided by `CardDescBox.target_info(data)` alone; the attribute row and the
  text's "대상" both read it. Pilots · turrets get a person icon (enemy · turret red, ally green, ally
  or enemy grey). **Tile targets (`target = location`) get a hex tile icon** — "아군 정글 타일" (green)
  if the effect is `own_jungle`, "적 정글 타일" (red) for `steal_camp`, "정글 타일" for `ambush`,
  otherwise "타일" (grey). An instant card whose clauses are all `|self` (몸집 불리기) has target
  "자신" (self). The attribute row states the target tile, so the text just says "이동".
- **HP**: "체력" · "최대 체력" both get the heart icon. Write changes as "최대 체력 +20" ·
  "공격력 +2" (not "20 증가").
- **Cost**: "비용 +1" · "비용 -1" · "비용 0" (word first, number after).
- **Attack**: once = "공격", several = "공격 2회". Sure hit is always the single unit
  **"필중 공격"** (one sure-hit icon).
- **Duration**: "3턴 간 교전", "10턴 동안 …" — an hourglass stands before "N턴".
- **Card counts**: "뽑기 2장" · "버리기 1장" · "찾기 1장" (draw green · discard red icon).
  Keep (보존) is a padlock.
- **찾기 = search the deck.** A bare "찾기" always means the deck, so "덱에서" is not written
  (`search:N` · `search_card` · `ambush_search` — "[미사일] 찾기 2장"). Only the non-deck source is
  spelled out: **"버린 더미에서 찾기"** (`search_discard`). The old "탐색" is gone. Magnifier icon.
- **Discard pile**: never "묘지" (버린 더미에서 찾기 · 버린 더미에서 뽑기). Icon: a pile of cards lying down.
- **생성** (create) only for making cards (손에 [락온] 생성) — shields · reactive armour are "부여" (grant).
- **보호막** (shield icon) · **회복** (heart) · **처치** (skull; "처치 관여" uses the same icon).
- **Terms** (손 · 소지 중 · 찾기 · 버린 더미 · 뽑기 · 턴 · 토큰 · 작전 단계 · 교전 … and their English): `data/l10n/src/glossary.csv` (validator W071 / W072).
- **Special keywords** `[name]`: words wrapped in brackets in the text. On screen they print **without
  brackets in the special keyword colour** (purple, `KeywordIcon.SPECIAL_COLOR_*`) and their gloss is not
  written in the text — the description panel adds a note panel (the hand: in the keyword panel column
  after the keyword panels; other panels: at the bottom). Two kinds:
  - **What a `[x]` is, is decided by key, not by text** (l10n D3 · D4): `CardDescBox.special_terms(data)` =
    `CardData.ref_entries(data.description_key)` — the description key's reference keys from
    `data/l10n/generated/refs.json` (`Loc.refs`), each `{key, text, special, card}`.
  - **Effect terms** — a `keyword` domain ref (`keyword.<id>.name`, `CardData.SPECIAL_LABELS` /
    `SPECIAL_NOTES`: track · reactive_armor · target · bounty · stun · vulnerable). A one-line note panel.
    A dedicated icon (`KeywordIcon.SPECIAL_ICONS`, keyed by id) precedes the term in the text · the panel
    title · the note line. For a new term, add `keyword.<id>.name` / `.note` keys (`new_key`), both tables
    (and `SPECIAL_ICONS` if it has an icon) and wrap it as `[term]` in the text.
  - **Card names** — a `card` domain ref. Instead of a note it raises **that card's
    description panel** (cost · name · keywords · text, `CardDescBox.build(ref, …, with_notes = false)` —
    expanded one level only). The card comes from `CardData.by_name_key(key)` (mech table, then pilot
    table, cached — `ui/SkillPopup.gd`'s card preview uses it too). A card's own name key is not expanded.
  - Particles attach directly to the bracket (`[목표]가`). No brackets inside formula phrases.
- **소지 중** (while held): a card that works while in hand starts with **"소지 중: …"** (open-palm
  icon). If it also has a use effect, split the line with `\n사용: …`.
- **Formulas** `{expr|phrase}`: in battle (`CardDescBox.live_vars` valid) the expression's value; outside
  (ban/pick · mech detail · draft) "(phrase)". Even in battle, `build(…, live = false)` /
  `resolve_text(cd, false)` gives "(phrase)" — the pilot detail panel's owned cards use it (not cards in
  hand, so there is no value). Expression names are `charge` (tokens on the card) and `chain` (the
  casting pilot's [영혼 포식] tokens, `CardPhaseManager.desc_live_vars`). In the phrase, use a word that
  fits the effect instead of "토큰" (사용 횟수 · 충전 횟수).
  Example: `소지 중: 성장 +{charge*8|사용 횟수×8}%`.

## CardPhaseManager.gd
`extends Node` — child of BattleSim.

Manages the **operation phase** (card draw / play overlay) that gates each battle turn.
The cost label is surfaced as "작전 점수" (operation points) in the HUD; one tick of `simulate_turn`
is referred to as "1분" (1 minute).

### Turn flow
- `do_battle_turn()` — calls `_bs.sim_core.simulate_turn()`, accumulates 작전 점수,
  draws cards, then hands the tick to whichever side's own 점수 (points) has reached
  `PHASE_THRESHOLD`. After the AI
  draws, `_bs.hud.update_ai_hand_visuals()` reflows the face-down peek row
  under the score panel. It also re-runs `highlight_affordable_cards()` every
  tick so the 부활 (respawn) countdown printed on each card face stays current.

#### Card economy gate (`ECONOMY_START_TURN`)
Strategy-point (전략 점수) recovery and auto-draw run **from turn `ECONOMY_START_TURN` (game_config.csv)**.
Before that the two counters do not tick at all, so the backlog of recovery does not
burst out all at once on the turn the gate opens. **There is no opening hand (개시 손패)** — the rule is that during that stretch both teams
have 0 cards in hand, hold only Blue's `BLUE_COST_HEAD_START` head start, and play pure laning.

The gate applies **only to the card economy**:

| Item | Gate |
|---|---|
| Blue head start (`BLUE_COST_HEAD_START`) | ❌ applied as-is on turn 0 |
| `COST_RECOVERY` / `CARD_DRAW_INTERVAL` | ✅ from `ECONOMY_START_TURN` |
| Growth (성장) (`GROWTH_PER_TURN`) | ❌ from turn 1 |

##### No recovery above the threshold
`COST_RECOVERY` is applied **only to a side whose own points are below `PHASE_THRESHOLD`**
(same rule for both teams). Points are a resource for waiting for your turn, not one to stockpile.
This pairs with the rule that the excess above the threshold is lost when passing the turn (`end_card_phase`)
— together they make **the threshold the effective cap on strategy points**. Only a card effect
(아드레날린 (Adrenaline)) can push points above it, and points raised that way are also cut back to the threshold
the moment that turn is passed.

`simulate_turn()` increments `turn_count` at its own start, so at the time the gate is checked
`turn_count` is **the number of the turn that just ended** (1-based). The counters are set to
`INTERVAL - 1` at the opening (개시), so they fire immediately on the first turn the gate opens.

**Measured (실측)** (standalone): every turn before `ECONOMY_START_TURN` sits completely frozen at
`cost_p = BLUE_COST_HEAD_START / 0 cards in hand`, and on the gate turn the first recovery + first draw land
together. After that recovery fires every `COST_RECOVERY_INTERVAL` turns and draw every `CARD_DRAW_INTERVAL`
turns, so **the first operation phase comes once Blue's points climb from the head start to `PHASE_THRESHOLD`**,
with one card in hand per draw tick by then. An earlier, shorter gate brought the first operation phase sooner,
and before the gate existed it came sooner still.

> **Standalone caveat**: running BattleSim.tscn directly without `match_ctx` uses `ROLE_STATS`
> defaults and the HQ **falls before the first operation phase** — the match ends before cards ever come into play, so
> to watch card flow via CLI, raise HQ HP or tick the counters manually.

#### Each side gets its turn on its own points
The two sides' turns are **independent**. `do_battle_turn` closes by asking
`_next_turn_side()` who gets this tick — `1` → `await _run_ai_turn()`,
`0` → `start_card_phase()`, `-1` → refresh the hand / HUD and keep ticking —
and stamps the answer into `_last_turn_side`.

The AI turn used to be bolted onto the end of the player's — `end_card_phase`
announced "상대 차례" (Opponent's turn) and ran the AI loop unconditionally, so passing the turn
flashed the banner even when the opponent was at 0 점 and did nothing. Now the
banner marks a real handover.

##### `_next_turn_side()` — Blue priority + alternation
Two lines decide it:

1. If only one side is ready, that side.
2. If both sides are ready, **the side that did not take the previous turn**; if nobody has taken
   one yet, **Blue** (`BattleSim.blue_team`).

Line 2 carries two separate jobs.

**Blue first on equal points.** At the opening `_last_turn_side == -1`, so Blue
always takes the first turn. Normally Blue's points head start (`BattleSim.BLUE_COST_HEAD_START`,
see Opening state below) alone gets Blue to the threshold first, but this rule handles the tiebreak when both sides
reach it again on the same tick after spending points on cards.

**Starvation prevention.** The old code prevented starvation here by checking the AI **unconditionally first**:
a player who played only free cards and passed the turn would still have
`player_cost >= PHASE_THRESHOLD` on the next tick, re-enter their own phase, and could starve the AI
forever that way. Flipping to Blue priority removes that defence, so the alternation
rule takes its place — the side that just took a turn cannot take another until the opponent
has taken one. If the opponent is below the threshold there is no one to alternate with, so consecutive entry
is still allowed (rule 1). `_last_turn_side` is this rule's only state, which `build_starter_decks`
resets to -1 every new match.

**Readiness is now the same for both sides** — points must be at or above the threshold and **there must be at least one
playable card in hand** (`_player_turn_ready` / `_ai_turn_ready`). The player
side additionally has the pass lock (below) on top.

Previously only the player entered on points alone. When all five allies (아군) were down, every card
in hand was locked by caster (시전자) death (`respawn_turns_for`) while points sat at the threshold,
so each time the auto-draw changed the hand the pass lock was released and "당신의 차례" (Your turn)
just opened and closed every 0.5 s — the only thing you could do on that turn was pass it.

`_player_turn_ready` asks `is_playable()` separately because `card_is_playable`
only compares cost: a **cost -1** (unusable) card passes that check since `-1 > player_cost`
is false (`ai_can_play` has the same line for the same reason).

**Discarding over the hand cap still runs** — that is done by BATTLE's auto-draw
regardless of whose turn it is, and cycling the deck is the purpose of that rule.

##### Pass lock (`_player_pass_lock`)
The player-side readiness check has one more condition — **a turn you just passed does not come
straight back.**

When the condition for passing the turn was "play at least one card", that rule itself guaranteed
"after passing, points drop below the threshold". Now you can pass without playing a single card
and only the excess above the threshold is cut, so right after passing the points sit exactly at the threshold —
under rule 1 alone, "당신의 차례" would pop up again on the next tick (0.5 s). So
`end_card_phase` sets the lock, and there are only two places that release it.

| Release point | Why |
|---|---|
| Auto-draw in `do_battle_turn` (when a card actually arrived) | If the hand changed, there may now be something to play |
| End of `_run_ai_turn` | The opponent had a turn = the match moved |

`start_card_phase` also wipes it once more on entry (so the next pass starts with a clean
lock). A new match is reset by `build_starter_decks`.
While locked, BATTLE flows as usual; only in the extreme where both deck and discard are dry does
the player's turn never open — at that point recovery is also stopped, so nothing would change
anyway.

### Opening state (side + empty hand)
- **Blue takes the first turn.** `BattleSim.blue_team` (0 = player team) is
  derived from `match_ctx.player_side`, and `BattleSim.seed_side_costs()` seeds that team's
  operation points with `BLUE_COST_HEAD_START` (game_config.csv). COST_RECOVERY gives both teams the same amount on the same
  tick, so that gap is preserved and Blue always reaches the threshold
  first. It is the compensation for banning/picking last in ban/pick — currently `MatchFlow` always fixes the player
  to BLUE.
- **There is no opening hand — both teams start with empty hands.** `build_starter_decks`
  ends by shuffling the deck and emptying the hands with `_clear_hands()`, and hands fill only
  through BATTLE auto-draw, which runs from `ECONOMY_START_TURN` (game_config.csv). Previously
  `INITIAL_HAND_SIZE` cards were dealt up front by `_deal_initial_hands()` so the first turn met a hand full
  to the cap; now the opposite is the rule — every turn before the gate is laning with no cards
  at all, and the hand at the first operation phase holds only what the auto-draw has delivered since. The `INITIAL_HAND_SIZE` key and
  `_deal_initial_hands()` were deleted together.
- **Manager traits (M8, player only)** shift three of these: `open_cost` is added in
  `seed_side_costs`, `first_draw` changes how many cards the match's **first** auto-draw takes
  (`TraitHooks.consume_auto_draw_count()`, never below 0), and `cost_tick` adds strategy points
  every p2 turns after `ECONOMY_START_TURN` inside the same economy gate (same "not above the
  threshold" rule as `COST_RECOVERY`). See `../trait/README.md`.

### Hand overflow (BATTLE auto-draw only)
The cap is `MAX_HAND_SIZE` (game_config.csv), read through `BattleSim.max_hand_size_for(is_player)`
— the player's cap takes the `hand_size` trait (floor 1), the AI's never does. The auto-draws that tick by while 작전 점수 climbs
back to `PHASE_THRESHOLD` — i.e. the stretch when it is *not* the player's turn
— always draw, even on a full hand, and `_trim_hand_overflow(is_player)` then
discards from the **front** of the hand (oldest first) until it is back at the cap.
Both sides run the same rule; only the player side despawns card nodes and
relayouts. The old behaviour was to skip the draw when the hand was full, which
stalled the deck and left the same dead hand sitting there for the whole wait.

Cards drawn by a card effect **during** 작전 단계 are exempt — that is the
player's own turn, so the hand is allowed over the cap and nothing is thrown
away mid-turn. `_effect_draw` and `_on_search_overlay_complete` therefore carry
**no** `MAX_HAND_SIZE` guard (only an exhausted deck+discard stops them); the
first auto-draw after the turn ends is what trims the excess.

**There are two kinds of keep (보존) — with different lifetimes.**

| | 계획 중시 (Prioritize the Plan) (`preserve:N` effect) | `보존` keyword (`keyword` column) |
|---|---|---|
| Where it lives | `BattleSim.preserved_cards_p/ai` list | The card itself (`CardData.has_keyword`) |
| Lifetime | **Until the start of that team's next operation phase** | Permanent |
| What it blocks | Over-cap auto-discard **only** | **All discards** |
| Cards that carry it | (any card in hand, chosen) | [전령 제압] (Herald Subdued) (objective (오브젝트) reward) |

`_trim_hand_overflow` skips both. **Forced** discards from card effects
(재고 (Reconsider) / 완벽한 마무리 (Perfect Finish) / 과감한 정리 (Bold Cleanup) / 솔로 퍼포먼스 (Solo Performance) / 버리기:N) ignore 계획 중시's
keep, but **they cannot break through the `보존` keyword either** — all four forced discards
filter the hand through `_discardable(hand)`, and the player's discard modal also
rejects it in `add_card_to_discard` and sets `target_count` to **the number of discardable cards**
(setting it to the hand size would create a modal whose confirm button is locked forever).
An objective reward that drops once per match must not vanish to a single 재고. The loop is an index
scan rather than `pop_front()` so it does not stop when a kept card sits at the front of the hand, and
even in the extreme where the whole hand is kept (impossible in practice, since there are at most 2) no infinite loop occurs.
`_prune_preserved` removes entries that have left the hand on every trim, preventing ghost references.

#### Maximum hand size — verified limit (T5, `HAND_CARD_SCALE` 0.96)
- **Resting cap = 12.** `MAX_HAND_SIZE` (10) + the only positive `hand_size` trait
  (`traits.csv` id 12 넓은 손, +2). A preset can't equip the same trait twice
  (`TraitSystem.validate_equip`), so 12 is the most the auto-draw trim ever leaves.
  `first_draw` (+1) only changes the first auto-draw count; the same tick's trim still
  cuts back to the cap.
- **Transient overshoot is possible** mid-turn: effect draws carry no cap guard, so e.g.
  `draw:2` (net +1) or 과감한 정리 (discard 3, draw 5, net +1) can push a 12-card hand to
  13–15+ until the next auto-draw trims. Bounded only by deck size + strategy points.
- **Measured** (throwaway harness: forced hand via `draw_card` + `spawn_card_node`,
  trait read through `match_ctx.traits` → `TraitHooks.load_from_ctx`, input injected with
  `Viewport.push_input`; windowed at 9:16, 9:19.5 + `ESM_SAFE_AREA=0,162,0,90`, and 3:4):

  | hand | spacing | push | rest bounds x | worst neighbour strip while focused |
  |---|---|---|---|---|
  | 10 | 83.2 | 41.0 | 77..1003 | 44.0px |
  | 12 | 68.0 | 56.1 | 77..1003 | **25.5px** (focus 9 → 10) |
  | 14 | 57.6 | 66.6 | 77..1003 | 12.7px |
  | 15 | 53.5 | 70.7 | 77..1003 | 7.7px |

  (Phone widths, 1080 viewport — identical at 9:16 and 9:19.5. At 3:4 the viewport is
  1440 wide, `BS_HAND_WIDTH` 1298: 12 cards = spacing 104, push 28, strip ≥ 32 — all pass.)

  At every size: row inside the safe area (bottom 1616 / 1946 vs safe bottom 1920 / 2250,
  above the ally strip backdrop), max tilt 6.72°, fresh hover at every band centre picks
  its own card, ±2px at every band edge picks the side's card, slow (3px/2 frames) and fast
  (14px/frame) sweeps visit every card in order with no cascade, every neighbour of a
  focused card is still reachable, and press → drag to the drop zone → return works from
  every index (card returns to its own slot, 0.0px error). The 14→12 trim (`_trim_hand_overflow`, cap 12) keeps nodes and
  data in sync. Draw-preview chevrons (+2 on the deck pile) render with the hand lowered.
- **Known soft spot**: the neighbour on the *anchored-end* side of a focus near the row's end
  only gets `ramp` (e.g. 0.75) of the push, so its exposed strip drops below
  `BS_HAND_HOVER_MIN_STRIP` (32): 25.5px at 12, ~8px at a 15-card overshoot. It stays
  reachable (and is trivially reached by moving focus from the far side), so nothing was
  changed; revisit if touch testing on device finds it too thin.
- The 12-card figures quoted elsewhere in this README predate the 0.96 scale (spacing 64.5,
  28px strip, row 89..991); the table above is the current measurement.
- `start_card_phase()` — transitions to CARD_PHASE and clears
  `_player_pass_lock` (your own turn opening is itself what it means for the lock to be released).
  Awaits `HudBuilder.play_turn_announce(true)` so the "당신의 차례" banner
  sweeps in / holds / fades out before the player can interact; the player
  hand stays dimmed for that whole interval via `_apply_hand_dim_state()`.
- `can_end_card_phase()` → bool — **you can pass your own turn at any time.** You need not
  play a single card, nor spend a single point. The remaining false conditions are
  all just "closing now would cut something off midway":
  `_player_turn_announce_in_progress`, modal overlays (discard·search / pile browse /
  battle-start VS confirm), the AI play loop, and an attack card's hit (명중) animation
  (`_attack_anim_active` — if the phase closes mid-animation, the cast glow and particles
  stay on screen while BATTLE resumes).

  **History of the rule.** The first gate was `player_cost < card_phase_entry_cost` (a points
  snapshot at entry), and it deadlocked the phase entirely: a good share of the cards are free
  (임기응변 (Improvise) / 정밀 이동 (Precise Move) / 복귀 (Return to Base) / 집중 (Focus) …) and 조정 (Adjust) actually *raises* the total,
  so a hand whose playable cards were all free could never bring points down and the pass-turn face
  never activated — and since BATTLE stops during the operation phase, no new cards arrived either.
  So it changed to **"must have played at least one card"** (`cards_played_this_phase > 0`),
  and only a hand with nothing playable was let through via the `_has_any_playable_card()` escape hatch.
  Now that exception has swallowed the rule —
  it is actually common to have points above the threshold but nothing playable, or nothing you want to use right now, and
  forcing "play something" makes players dump any card as if discarding it. `cards_played_this_phase` and
  `_has_any_playable_card()` were **deleted** together.
- `end_card_phase()` — the player's turn only: drops the selection, runs
  `recall_sys.process_phase_end_recalls()` (HP threshold + out-of-position
  card-displaced pilots) and returns to BATTLE. Also zeroes `kill_bounty_p` —
  계획 살인 (Planned Kill)'s reservation only lives for the phase that placed it. At the moment of passing,
  three things happen together.

  1. **Excess above the threshold is lost** — `player_cost` is cut to exactly `PHASE_THRESHOLD`
     (the amount lost is logged). It is the price of passing without using the turn, and pairs with
     the rule that recovery stops above the threshold.
  2. **Pass lock** — sets `_player_pass_lock` (section above).
  3. **If the opponent is above the threshold, the opponent's turn starts on the spot** — if `_ai_turn_ready()` is true,
     it stamps `_last_turn_side = 1` and does `await _run_ai_turn()`. It does not wait for the next BATTLE
     tick and is independent of my points (my turn just ended).
     It asks `_ai_turn_ready()` rather than looking only at points so as not to show a do-nothing
     "상대 차례" banner. **Passing itself still has no
     banner** — if a banner appears, it means the opponent actually acts.

  Because of this last clause `end_card_phase` is a **coroutine**. `CostDonut.
  end_turn_pressed` can stay connected as-is (signals accept coroutine handlers),
  and the 완벽한 마무리 path in `_finalize_pending_play` also calls it without `await`.
- The same loss rule applies at the end of the AI turn (`_run_ai_turn`) — `ai_cost` is likewise
  cut to the threshold, and the player's pass lock is released right there.

#### Operation-phase entry settlement (`_apply_phase_entry_carryovers`)
The deferred effects are settled all at once at **the moment their team next enters the operation phase**.
For the player, `start_card_phase` calls it; for the AI, `_run_ai_turn`.

| State | Card | Settlement |
|---|---|---|
| `preserved_cards_*` | 계획 중시 | Cleared entirely — the keep survives only one BATTLE stretch |
| `next_phase_strategy_*` | 아드레날린 | Added to operation points (may be negative, floored with `maxi(0, …)`) |
| `growth_until_phase` | 완벽한 마무리 | `SimulationCore.clear_growth_until_phase(team)` resets the whole team's growth multiplier to 1.0 |
| `ambush_hold` | 매복 (Ambush) | Releases that team's pilots' ambush |
| `next_phase_draw_*` | 준비 태세 (Readiness) | Draws that many — since it is already inside that side's operation phase, 신중한 예산 (Careful Budget) cards drawn this way become free |
| `ambush_search_*` | 매복 | Searches the deck for the caster's engage card (교전 카드) |

When the operation phase **closes**, `_clear_phase_free(is_player)` clears 신중한 예산's "0 this phase"
(at the end of `end_card_phase` / `_run_ai_turn`).

### Opponent's turn (`_run_ai_turn`)
- `_ai_turn_ready()` — `ai_cost >= PHASE_THRESHOLD` **and** at least one card
  in `ai_hand` the AI can pay for, tested with the same
  `effective_cost_for(cd, false) <= ai_cost` filter
  `AiCardPlayer.run_ai_plays` uses. The second half is what keeps the banner
  honest: an AI sitting on a full score
  with an empty or unaffordable hand would otherwise re-announce "상대 차례"
  every tick and play nothing. Because the filter matches, a turn that starts
  always consumes at least one card, so the condition can't hold twice in a row
  without a draw in between.
- `_run_ai_turn()` — sets `_ai_play_in_progress`, awaits
  `play_turn_announce(false)` (the "상대 차례" banner), awaits
  `AiCardPlayer.run_ai_plays()`, then runs the same
  `process_phase_end_recalls()` sweep the player's turn gets.
  **It never changes `game_phase`** — the AI turn runs *inside* BATTLE.
- `is_ai_turn_active()` — public read of `_ai_play_in_progress`. Because
  `game_phase` stays BATTLE, every "is the sim running?" check has to consult
  it too: `BattleSim._process` holds the auto-tick, and
  `get_elapsed_ingame_seconds` freezes the MM:SS clock. `do_battle_turn` also
  early-returns on the flag as a backstop.
- An AI `engage` / `duel` card opens the arena from BATTLE, so
  `EngagePhaseManager` restores **the phase it captured on entry**
  (`_phase_before`) instead of hard-coding CARD_PHASE — otherwise the field
  would be stranded in 작전 단계 once the AI's turn ended.

### Hand dim driver
`_apply_hand_dim_state()` toggles `Card.set_dimmed(true|false)` on every
player hand node based on `_is_player_input_blocked() or game_phase != CARD_PHASE`.
That covers BATTLE auto-tick, the player turn-start banner, the AI run loop,
any active modal overlay, and the attack hit animation (공격 명중 연출) (`_attack_anim_active`). `Card.set_dimmed(true)` darkens the modulate,
suppresses hover brighten, and ignores `_gui_input` clicks; `set_dimmed(false)`
restores `Color.WHITE`. `highlight_affordable_cards()` always tail-calls
`_apply_hand_dim_state()` so every overlay-close path that funnels through it
re-evaluates the dim state.

### Card management
- `build_starter_decks()` — 10-card decks built from `cards` table; calls
  `update_deck_discard_labels()` to seed the visible counters.
- `draw_card(is_player)` → CardData — pops from deck. If the deck is empty it
  shuffles the discard pile back in *first*. For the player, draws update the
  Deck / Discard labels: a normal draw snaps; a reshuffle draw kicks off a
  parallel tween (`_animate_reshuffle_counts`) that drains the discard count
  to 0 while the deck count grows over `BS_RESHUFFLE_TWEEN_DUR` (~0.55s).
- `spawn_card_node(cd, at_left = false, animate = true)` — instantiates a player
  Card.tscn into `_bs.canvas`. The AI hand is logical-only — no card backs are
  spawned for the enemy. `animate` runs the draw intro (드로우 인트로) below.

#### Draw intro (the path a drawn card takes into the hand)
A drawn card does not just appear in its slot. **One card rises off the deck stack (뭉치)
and fades → appears face-down from off-screen left → flies to a point above the right end
of the hand (where the new card will sit) → flips there to reveal its face → settles
into the slot.** Each of the beats answers a different question: where did it come from (deck stack →
left) → where does it sit (right end of the row) → what is it (the revealed face).

| Beat | Owner | Time |
|---|---|---|
| Rises off the deck stack and fades | `_play_draw_intro` ⓪, `CardPileStack.play_pop()` | `GHOST_SEC` **0.26s** (hand-off at **0.182s**) |
| Off-screen left → above the right end | `_play_draw_intro` ①, `Card.tween_to` | `DRAW_FLY_SEC` **0.28s** |
| Flip | `Card.play_flip_reveal()` | `Card.FLIP_HALF_SEC` × 2 = **0.18s** |
| Settle | `_play_draw_intro` ③ → `relayout_hand` | `BS_HAND_SPRING_DURATION` 0.18s |

- **⓪ and ① overlap.** The entry from the left starts not after the ghost has fully faded but when its alpha
  has `CardPileStack.GHOST_HANDOFF_ALPHA` (0.30) left
  (`CardPileStack.ghost_handoff_delay()` = 0.182s) — starting after it has fully
  faded makes one card look like it came out twice, a visible stutter. If the stack does not
  exist yet (`pile_deck == null`, the opening deal (개시 배분) before the HUD is built) this beat is skipped
  entirely. The ghost itself: `ui/README.md` → Cards coming and going = ghosts.
- **Start point** `_draw_entry_position()` = `(-CARD_W - DRAW_ENTRY_PAD_PX, BS_HAND_CENTER.y)`
  — one more card width out, so it doesn't poke into the screen on the first frame.
- **The flip point is `DRAW_FLIP_LIFT_PX` (78px) above the final slot.** Flipping
  inside the row hides half of it behind the neighbour cards, and the final "settle" would not
  remain as a visible motion.
- **The flight curve is `EASE_IN_OUT` / `TRANS_SINE`.** It used to be `EASE_OUT` / `TRANS_CUBIC`,
  a front-loaded deceleration curve that covered 77% of 1200px in 0.10s, so "it came from
  the left" didn't read (measured (실측)). A symmetric curve keeps the crossing visible.
- **The flight reuses `Card.tween_to` (= `_active_tween`).** It must be a tween the card itself holds
  so `begin_discard_fx` can clear it — the over-cap trim discards
  **the oldest card**, which may still be in flight, and a surviving
  flight tween would drag the falling card back up toward the hand.
- **`Card.intro_active` temporarily removes that card from the hand's membership**:
  `relayout_hand` skips it (the intro owns its position), and `Card.set_hovered` and
  `_grabbable_card_at` reject it (it is not a grabbable card yet). The rest of
  the hand **narrows to make room for the new card** immediately at spawn and waits — `relayout_hand`
  already ran with the total count.
- **The flip is a 2D fake that folds `scale.x` down to 0 and back open**; the front/back swap happens on the frame where the
  width is 0. While it turns, `Card._flip_active` is set and
  `_refresh_float_state` lets go of `scale` — fighting over the same property as the
  hover enlargement would freeze the card flat.
- **When several cards are drawn in the same frame** (5 at opening / `draw:N` / restock) their start times
  are staggered by `DRAW_STAGGER_SEC` (0.07s). Without it the five fly exactly on top of each other and look like
  one card. The offset is measured by `_draw_intro_active` (number of intros in progress).
- **Each beat waits on a `SceneTreeTimer`, not on the tween's `finished`.** If the card is
  freed midway (restart / snapshot rollback / over-cap trim) that tween's `finished`
  never arrives, and the coroutine hangs holding the counter. Before every beat it
  re-asks `_intro_alive(node)`.
- **Two callers turn the intro off**: the `at_left` return (precise move — a card coming back
  to the left, so a flight to the right end would be wrong even in direction) and
  `_restore_from_snapshot` (a cancel rollback rebuilds the whole hand, so
  running the effect would make the entire restored hand look freshly drawn).
- **Measured** (headless): right after spawn `intro_active = true` · `face_up = false` ·
  `position = (-300, 1440)`; at intro end `face_up = true` · `scale = (1,1)`;
  after settling, offset from the slot **0.00px** / rotation error **0.0000**.

#### Discard effect (`Card.begin_discard_fx`)
A card leaving the hand to be discarded goes **straight down the screen Y axis only, regardless of its fan tilt**,
fading as it goes (`DISCARD_DROP_PX` **150px** / `DISCARD_FADE_SEC` 0.30s), and once it is all the way
down it `queue_free`s itself. This is the opposite of the lift (`PRESS_LIFT`), which rides the card's own up
axis — a discarded card is not pulled out of the hand but falls down, so
riding the tilt would make only the tilted cards slide sideways and the row would look messy.
(The parent is a `CanvasLayer` with no rotation, so adding to `position.y` is a pure
screen-Y move.)

- **The drop curve is `EASE_OUT`** — it snaps down the moment it leaves the hand, then
  slowly comes to rest below. It used to be `EASE_IN`: sluggish at first, fast at the end,
  which made the moment the card **breaks away** from the hand the blurriest and the
  fastest part was when it vanished, putting the weight of "discarded" at the end. The fade (`modulate`) is still
  `EASE_IN`, so the card finishes erasing where it came to rest at the bottom.
- **A ghost lands on the discard pile from the opposite direction too** — one card appears coming down
  onto the stack from above (`CardPileStack.play_land`). **It starts only after the hand card's
  drop has finished**: `PILE_LAND_DELAY_SEC` is tied to `Card.DISCARD_FADE_SEC` (0.30s)
  so the two effects don't overlap but join end to end — so it reads as **one motion** of a single card
  falling from the hand into the pile. The old 0.16s had the pile receive the card while it was
  still half-way down, so the same card was in two places at once.
  **It is called from one place, `_notice_discard_gain()`**: code that adds cards to the discard pile
  lives in seven places (card play / 버리기:N (discard:N) / over-cap trim / 과감한 정리 (Bold Cleanup) …),
  so instead of calling it from all of them, `update_deck_discard_labels` **notices that the count went
  up** — all seven pass through there anyway (if the number doesn't change, the screen doesn't
  change either), and shrinking cases like a reshuffle have a negative delta and are filtered out automatically. Ghosts spawned
  at once are capped at `PILE_LAND_MAX_GHOSTS` (3) — any more just overlap into
  a smear. **Exhaust (`exhaust`, 소멸) does not go to the discard pile, so it has no ghost** —
  basing this on the count rather than on `play_discard_fx` is exactly what makes that rule.
- **The number and the thickness rise only after the ghost has landed.** `_discard_pending` holds "cards that are in
  the array but not on screen yet", and the displayed value is always
  `array size − _discard_pending`. `_commit_discard_gain(n, wait)` clears that amount
  after `PILE_LAND_DELAY_SEC + (count−1)×GHOST_STAGGER_SEC + GHOST_SEC`,
  raising the number and the stack thickness together — the moment the card **touches** the stack and
  the moment the pile thickens coincide. The wait is a `SceneTreeTimer`, not a tween
  (same reason as the draw intro: the coroutine doesn't hang if the node disappears midway).
  - **A delta of 0 does not touch the settlement.** `update_deck_discard_labels` is mostly called as
    a plain refresh with delta 0 (draw / hand relayout / HUD refresh …), so
    resetting `_discard_pending` to 0 there would wipe the whole delay in one refresh and the number would rise
    before the ghost even landed (a bug caught by measurement during implementation). It is reset to 0
    **only when the count shrank (reshuffle)**, and `_animate_reshuffle_counts` also
    re-captures `_discard_seen` / `_discard_pending` at its start.
  - **Measured** (headless): right after adding 1 card to the array, `displayed` unchanged · `pending 1`
    → still unchanged at 0.30s → at 0.65s `displayed 1.0` · `pending 0`.
- The single entry point is `CardPhaseManager.play_discard_fx(node)`, and **the node must already be
  removed from `player_card_nodes` before the call** — if during the 0.3s the effect
  runs layout · hover · hit bands still counted that card as part of the hand, the remaining cards
  couldn't fill the gap. `_despawn_player_card_node` calls them in erase → play
  order.
- It is started only after killing every in-progress layout / hover / shadow / flip tween.
  If a tween fighting over the same `position` · `modulate` survived, the card would be
  dragged back up to its spot.
- **The centre row of 버리기:N (discard:N) goes down with the same effect.** `CardSelectOverlay._commit_discard`
  first detaches `to_discard_nodes` from the list (otherwise `_teardown` would free them
  on the spot) and hands them one at a time to `play_discard_fx`. **The cancel path is
  the exception** — `_on_cancel_pressed` → `_teardown` still frees immediately and
  `_restore_from_snapshot` rebuilds the hand. A card that wasn't discarded has no reason
  to fall.
- **Measured** (headless, back when the drop distance was 260px): removed from the array immediately while the node stays
  alive → at 0.15s `dy = +37.2px` · `dx = 0.00` · `rot_delta = 0.0000` ·
  `alpha = 0.73` → freed by 0.45s. The distance is now **150px** —
  a card vanishing just below the hand reads as "discarded" better than one sliding
  far off the bottom of the screen.
- **The fan is one circle.** Every card centre rides a circle of radius
  `BS_HAND_FAN_RADIUS` (3200px) whose pivot sits directly *below* the row, and
  both readings of the fan come off it: a card's tilt is its angle on the circle
  (`_fan_angle`), its vertical offset is how far the circle has dropped from its
  apex at that angle (`_fan_arc_drop`). The apex is the middle of the row, so
  **the centre card is the highest and the hand curves down toward both ends** —
  a hand held from underneath, not a valley. Measured at 12 cards: the
  outermost cards tilt ±6.7° and hang 21.4px below the middle pair; a 5-card
  hand splays ±6.2° / 18.5px (its spacing is uncompressed, so it's just as wide).
  Shrink the radius for a deeper curve.
  > The 12-card figures quoted throughout this section are a **large-hand sample**,
  > not the cap — the cap is `MAX_HAND_SIZE` (game_config.csv), and with the opening hand (개시 손패) gone the hand
  > only reaches it mid-match (an operation phase (작전 단계) draw can overshoot it until the
  > next auto-draw trims). They're kept as the measured worst case: every layout
  > quantity here is monotonic in hand size, so a larger sample bounds a smaller hand and re-measuring
  > would only move the numbers slightly. The 8-card figures also quoted
  > below are just a mid-size sample, not the cap.
##### Hand card scale (`HAND_CARD_SCALE` 0.96)
**Cards in the hand are drawn at their own scale, separate from `Card.CARD_W/H` (160×220) — 153.6×211.2** (1.2 → 0.96, 20% smaller). The
card spec itself isn't enlarged because a dozen-odd screens read that constant — the ban/pick (밴픽) sheet · pile browse · pilot detail
popup and more (enlarging it would throw off those screens' grids
wholesale). So only the hand has its own scale, and the two helpers `hand_card_w()` / `hand_card_h()`
answer "the visible size".

**Layout coordinates don't ride the scale.** The card's `pivot_offset` is its centre, so
multiplying the scale onto `position` (= top-left before scaling) **does not move the centre** — so
"centre = position + CARD_W/2" in `slot_position` / `_apply_hit_bands`, and
"half the card is hidden behind the strip backplate" in `hand_drop_offset()`, didn't change by a single character.
Only three places need to know the scale — **those that measure the visible width**:

| Place | What it measures |
|---|---|
| `slot_spacing` | non-overlapping spacing / compression limit |
| `_hover_push_amount` | how far the focus card covers its neighbours |
| `grow_x/y` in `_fit_hit_layer` | margin outside the slot rect = `HAND_CARD_SCALE × HOVER_SCALE − 1` |

The measured figures below are from when the scale was 1.2 (not re-measured after shrinking to 0.96):
4 cards spacing 204 · row 138..942, 12 cards spacing 64.5 · row 89..991, the hit layer matching the hovered
card's visual rect **exactly**. In the 1.2× days the same scale also applied to `AiCardPlayer`'s centre card (`SCALE_BIG` 1.35 → **1.62**,
`SCALE_SMALL` 0.85 → **1.02**) and to `CardSelectOverlay`'s discard-pick row
— the latter is **the same node** lifted straight out of the hand, so it still follows `HAND_CARD_SCALE`
as-is. `AiCardPlayer`'s two constants and `ObjectiveRewardFx.CARD_SCALE` (1.35)
are hard-coded and were **left unchanged** when the hand shrank to 0.96 (a card floated in the centre to be read
must be bigger than the hand — still true).

- `slot_spacing(total)` — uniform centre-to-centre spacing.
  `hand_card_w() + BS_HAND_CARD_GAP` until the natural span exceeds
  `BS_HAND_WIDTH`; from then on it compresses so the row always fits the
  fixed-width slot (204px up to 4 cards → 64.5px at 12).
- `slot_center_dx(index, total)` — signed distance from
  the middle of the row to the card's centre. Everything else (X slot, tilt, arc
  drop) is derived from this one number, so the three can never disagree.
  **There is no push-free variant.** A card has exactly one slot; the focus
  card's own push is 0 by construction, so the lifted-card poses read the same
  slot as everyone else (see Hand focus below).
- `slot_position(index, total)` — top-left viewport
  position: `BS_HAND_CENTER + (dx, _fan_arc_drop(dx))`. `BS_HAND_CENTER.x` is
  set in `BattleSim._ready` to *the top-left a centred card would take*
  (`viewport_cx − CARD_W/2`), which is why a centre-to-centre `dx` adds to it
  directly. Resting row for ≥8 cards: x=89..991.
- `slot_rotation(index, total)` — `_fan_angle` of the
  same `dx`. Cards pivot around their own centre (`pivot_offset` set in
  `spawn_card_node`), so the slot X positions are unaffected.

##### Hand focus — who does the row spread around?
- `_push_focus_card()` — **the single home of that question**: the *dragged*
  card if there is one, else the card under the cursor. A dragged card is the
  hand's focus in exactly the same way a hovered one is, so it opens the row the
  same way and keeps it open while the cursor walks out over the battlefield.
  Every other guard reads this one accessor instead of testing `_drag_card`
  itself. `_hovered_hand_card()` supplies the cursor half — a `_hovered_card`
  fast path validated against `Card.is_hovered()` and the hand array, so a freed
  card or a hover that arrived while a modal owned the screen can't leave the
  row stuck open.
- `hover_push_offset(index, total)` / `_hover_push_amount(total)` — the spread
  that keeps the focus card's 1.2× enlargement from covering its neighbours.
  **The hand's overall width never changes.** The two outermost cards are
  anchors and hold still; everything between them slides away from the focus by
  `_hover_push_amount` scaled by a falloff that reaches exactly 0 at the end of
  its own side, so the row doesn't grow — it *redistributes*. Each side ramps
  against its own distance to the end of the row, so an off-centre focus still
  pushes both of its neighbours nearly the full amount.
  `ramp = 1 − (steps / steps_to_end) ^ BS_HAND_HOVER_FALLOFF_POW` (2.0): the
  squared curve holds the near neighbours close to full push and concentrates
  the give-way in the outer cards, rather than bleeding it evenly across the
  block (a linear ramp would rob the immediate neighbours, which is exactly the
  clearance a packed hand needs most). The amount itself is *solved*, not fixed:
  the focus card covers `hand_card_w() × HOVER_SCALE / 2` = 115.2px to either
  side, so its neighbour's centre has to sit that + `BS_HAND_HOVER_MIN_STRIP`
  (32) = 147.2px away
  to leave a clickable sliver. The resting spacing pays part of that and pays
  less the more cards the hand holds, so the push is the shortfall — **it grows
  with the hand size**: `BS_HAND_HOVER_PUSH` (28px) floor up to 8 cards, 60.5px
  at 12 cards. No edge clamp is needed, since anchored ends can't reach
  the screen edge. Measured at 12 cards with the focus in the middle: the row
  spans 89..831 whether open or closed, the two neighbours take ∓58.9 / ±58.1px,
  the falloff runs 58.9 → 53.8 → 45.4 → 33.6 → 18.5 → 0, and the tightest
  adjacent gap anywhere in the row is 45.7px — nothing crosses.
- `relayout_hand(nodes, skip = null)` — tweens every card to its
  `slot_position` / `slot_rotation`, then records the focus it laid out for in
  `_reflow_focus`.
- **A hover reflow lays out the incoming focus card too** — `_apply_hand_reflow`
  skips only `_drag_card` (whose held pose `_begin_drag` owns), never the
  hovered card. The hovered card's slot under the *new* focus is its resting slot
  (own push = 0), but it is almost never already sitting there: the *previous*
  focus had pushed it aside. Skipping it left it stranded at that stale offset,
  so a card hovered right after its neighbour sat displaced by up to a full push
  (+26.9px at 8 cards, +59.8px at 12 cards) and then slid sideways on its
  way up when clicked — the same card hovered with no prior focus did neither.
  Skipping was safe for `scale` (`tween_to` doesn't touch it) but never for
  `position`. Verified: hovering B directly and hovering B right after A now
  agree to 0.0px, as do selecting B along either path, selecting a card while
  another is already selected, and clicking in the same frame as the hover
  (before the deferred reflow has run).
- **Never tween `global_position` on a Card.** `Control.global_position` is the
  *rotated-and-scaled top-left corner*: the getter returns
  `position + pivot − R·S·pivot` and the setter inverts that with whatever
  rotation/scale the node holds at the instant of the write. With hover scaling
  in play, the same slot value written at scale 1.2 lands ~15px right and ~22px
  below the same value written at scale 1.0 — which is what made the lifted card
  drift up-right and the deselected card sink under its slot row.
  `Card.tween_to` converts the viewport-space slot through
  `Card.layout_position_from_global()` and tweens plain `position` instead; a
  card's visual centre is always `position + pivot_offset`, invariant under both
  rotation and scale.
- `update_deck_discard_labels()` / `_refresh_count_labels()` — snap the visible
  Deck count to `player_deck.size()`; the Discard count lags by
  `_discard_pending` until its landing ghost (착지 잔상) lands (see Discard effect). The counts go into the
  two `CardPileStack` stacks (`_bs.pile_deck` / `_bs.pile_discard`) as **floats**,
  so during a reshuffle tween the stack's thickness rides the same curve the
  number does. See `ui/README.md` → Deck / discard piles.
- `highlight_affordable_cards()` — re-reads every visible card's playability:
  `set_affordable(eff <= player_cost)`, `set_respawn_turns(respawn_turns_for(cd))`,
  and `update_displayed_cost(eff)`. Tail-calls `_apply_hand_dim_state()` and
  `_refresh_play_allowed()`, so every path that funnels through it also
  re-evaluates the hand dim and the drop gate.
- `respawn_turns_for(cd)` / `card_is_playable(cd)` — the two playability
  questions. `respawn_turns_for` returns 0 while the caster (시전자) is alive and
  **at least 1** while they are down (never 0 for a dead pilot, so the card
  can't flicker back to playable on the tick the timer hits 0).
  `card_is_playable` = caster alive **and** affordable **and**
  `card_has_valid_targets`.

### Card interaction (hover → drag → drop)
- Hand row: cards span ~y=1370..1590 at-rest (was 1440 until the pilot strip doubled in height) (CARD_H=220), centred on the
  viewport. The row moved up 60px when the battlefield shrank to 90%
  (`HexGrid.DISPLAY_SCALE` 1.5 → 1.35 put the field's bottom edge at 1351
  instead of 1406), which keeps the ~90px gap between the field and the cards.
  Everything positioned off `BS_HAND_CENTER.y` — the 전략 포인트 (strategy point) donut, the
  Deck / Discard counters, the hit layer — followed it automatically; there are
  no literals to chase. (The 확인 / 취소 (Confirm / Cancel) row used to sit in that band too; it is
  gone, but `CardTargetingOverlay.BTN_H` / `BTN_HAND_GAP` still reserve the gap
  so the donut doesn't land on the cards' top edge.)
  `BS_HAND_AREA_MARGIN` (130px) on each side is reserved for the
  Deck / Discard piles (뭉치) and shrinks the inner `BS_HAND_WIDTH`, which is
  then widened by `BS_HAND_WIDTH_SCALE` (1.10) → **902px** on a 1080-wide
  screen (row spans x=89..991). That eats into the pile gutters, so
  `HudBuilder._bind_hand_indicators` derives its gutter from the real hand
  edge instead of `BS_HAND_AREA_MARGIN` and scales the title font down to fit
  (130→89px gutter, font 22→20; the pile itself is 81px wide after a 4px inset).
- **Floating shadow** (`Card._build_shadow` / `_refresh_float_state`): every
  player card owns a `DropShadow` Panel parked at child index 0, so it draws
  under `CardBack` / `CardFront` and inherits the card's fan rotation and
  hover scale for free. The gap between card and shadow encodes height:
  `SHADOW_REST_OFFSET` (10px down, tight `shadow_size` 6, alpha 0.50) for a
  card resting near the table, `SHADOW_HOVER_OFFSET` (24px, blur 26, alpha
  0.36) while hovered, `SHADOW_SELECTED_OFFSET` (32px, blur 32, alpha 0.32)
  while lifted — **or aiming**: `is_dragging` reads as "highest of all" for both
  the shadow and the 1.2× scale, so a card whose aiming arrow (조준 화살표) has followed the
  cursor out over the battlefield keeps its raised look even though the cursor
  is no longer over any hover band. The slab's own `bg_color` alpha also drops from 0.8 → 0.55
  on the blurred states so a high shadow reads as a soft pool, not a black
  rectangle trailing the card. Non-player cards (AI hand peek, search (찾기) grid)
  keep the shadow hidden — `setup()` gates `_shadow.visible` on
  `is_player_card`.
- **Hover** (`on_card_hovered` / `on_card_unhovered`, driven by the hand hit
  layer — see Hand hit layer (핸드 히트 레이어) below): face-up player cards
  brighten via a `modulate` tween and scale up to `Card.HOVER_SCALE` (1.2×)
  around their own centre, coming "closer to the screen" — the shadow drops
  to its hover pose at the same time. All three reactions run on
  `HOVER_EASE` / `HOVER_TRANS` (cubic `EASE_OUT` — quick jump, slow settle)
  over `HOVER_TWEEN_DURATION` 0.04s / `SHADOW_TWEEN_DURATION` 0.05s. The
  hovered card is also
  moved to the **top of the scene-tree** so it draws above its neighbours; on
  unhover the canonical hand order is restored. Moving the cursor from one card
  to another re-spreads the row around the new one every time. While a card is
  being dragged the hover has no effect on the layout — not through a
  special-case guard, but because `_push_focus_card()` keeps answering the
  dragged card, so `_apply_hand_reflow` finds nothing changed and no-ops (the
  `_hovered_card` pointer is still tracked throughout, ahead of every guard, so
  the row is correct the instant the drag ends). `Card.tween_to` treats
  its `target_scale` argument as the *layout* scale (`_base_scale`) and leaves
  `scale` **entirely alone** unless that layout scale actually changes (no
  caller changes it today). `scale` therefore has exactly one owner —
  `_refresh_float_state`. Two tweens racing over it is what used to strand a
  hovered card at 1.0: a relayout firing mid-hover captured the hover factor
  from a transient `_is_hovered` and killed the hover tween on its way past.
- **Grab** (`_on_hit_layer_gui_input` press → `_begin_drag` once the cursor
  passes `DRAG_THRESHOLD_PX`). A press on its own records `_press_card` and does
  nothing else — **a click that never moves is not an action.** When the drag
  does fire, a targeting (대상 지정) card pops out by `Card.PRESS_LIFT` (40px) **along its
  own up-axis while keeping its fan rotation** —
  `slot + Vector2(0, -PRESS_LIFT).rotated(slot_rotation(...))`, so a card on the
  left half of the fan travels up-left and one on the right half travels
  up-right: straight out of the fan, the way a card is drawn from a real hand,
  never plain screen-up-and-right. Sideways travel is
  `PRESS_LIFT × sin(fan angle)` = ±4.6px on the outermost card of a 12-card hand;
  tighten `BS_HAND_FAN_RADIUS` if the splay should read more strongly.
  (A card with no target leaves the row entirely instead — see Drag and drop.)
  **Grabbing makes the card the row's focus, so `_begin_drag` reflows the whole
  row around it before posing the lift** — the neighbours give way exactly as
  they would on a hover, and because the focus card's own push is 0, its pushed
  slot *is* its resting slot: lift and drop are exact opposites with no
  push-free special case anywhere.

  > This is the fix for a real bug (it predates the drag-only rewrite, and the
  > same reasoning still applies). The lifted pose used to be computed
  > *push-free* while the row on screen was still spread around whichever card
  > the cursor had opened it with — hover reflow is deferred to idle, so a grab
  > landing in the same frame as the `mouse_entered` posed the card off a layout
  > that had not happened yet. The card visibly slid sideways on the way up
  > (toward the first-hovered card, ~48–60px in a 12-card hand). Reflowing
  > inside the grab closes the gap: both orderings end at the same layout.

  The grab also pins the card to the top of the hand (via the
  `relayout_hand` → `_reorder_hand_nodes` pass), flips `Card.set_dragging(true)`
  (→ 1.2× + tallest shadow, held even once the cursor leaves the row), and
  refreshes the description box. `_pose_selected_card(card)` owns the lifted
  pose. On release, `_end_drag` reflows the **whole** row, the released card
  included (it does *not* skip it): one pass places every card off the same
  focus state, so the returning card can't land on a slot that disagrees with
  the row it's landing in. If the cursor is still on it, it stays enlarged and
  becomes the focus, so its neighbours hold the spread they already had — the
  card just comes straight back down.
- **Hand z-order** (`_reorder_hand_nodes`): canonical order is oldest-lowest /
  newest-on-top, then the **dragged card — or, failing that, the card under the
  cursor — is raised above all of them**. That last clause is what keeps a
  hovered card above its right-hand neighbours right after a drop, when the
  canonical order alone would bury it.
- **Hover reflow is deferred and coalesced** (`_queue_hand_reflow` →
  `_apply_hand_reflow`). This is not optional polish — `move_child` re-runs
  mouse picking and makes the engine emit `mouse_entered` / `mouse_exited`
  **synchronously, from inside the move**, so reflowing straight out of a hover
  signal re-enters itself, trips
  `Parent node is busy setting up children, move_child() failed`, and strands
  half-killed tweens (a hovered card stuck at scale 1.0, its neighbour frozen
  at 0.98). Three guards keep it settled:
  1. `_hand_reflow_queued` + `call_deferred` — the exit on the old card and the
     enter on the new one arrive in the same frame and collapse into one pass
     that runs at idle, outside the locked move.
  2. `_reflow_focus` — a pass whose focus card matches the layout already on
     screen returns without touching anything, so the enter/exit churn a
     reorder provokes can't loop forever. This doubles as the "the dragged card
     outranks the cursor" rule: with a card in hand the focus never moves, so
     hovering around reflows nothing.
  3. `_reordering` + an "already sorted?" check in `_reorder_hand_nodes` — a
     reorder that would change nothing moves no children at all.

  Verified by sweeping a synthetic cursor across all 8 cards in both directions
  (140 samples): exactly one hovered card per frame, always at scale 1.2 and
  always topmost, every other card at 1.0, zero engine errors.
- **Description box** (`_refresh_description_box` / `_show_description_box`):
  a `CardDescBox` panel **right beside the focused (enlarged) card**, portrait
  like a card — `DESC_BOX_W` 240 wide, `DESC_BOX_GAP` (20) from the card; its
  height follows the text with no lower bound (`CardDescBox.build(..., min_h = 0)`
  — the old floor of the enlarged card's height was dropped).
  Side: card centre at or right of the screen middle → panel on the card's
  **left**; left of the middle → on its **right**. Top edge = the enlarged
  card's top, pushed up only if the panel would leave the screen
  (`_desc_box_y`). The card rect comes from `slot_position` + centre pivot, not
  from the live node (which may still be tweening).
  Keyword notes go in **one panel per keyword** (`_keyword_boxes`,
  `CardDescBox.build_keyword_panels`, `KEYWORD_BOX_W` 210), stacked top-down
  (`KEYWORD_BOX_STACK_GAP` 10) in a column on the far side of the description
  panel; if that side has no room the column flips to the card's other side.
  (Keyword notes used to share one panel — two keywords now make two panels.)
  Header row: [small cost ribbon with the effective cost — white / green / red
  mirroring the card's ribbon] + name, centred; then keyword tags, then the
  description.
  **While a card is dragged** the keyword panels go away and the description
  panel alone sticks to the dragged card's **left** (`_desc_follows_drag`,
  `_start_desc_follow`, `_follow_drag_desc` from `_process`). Its spot is
  recomputed every frame from the card's live transform (bounding box of the
  four transformed corners, so scale and tilt count): right edge =
  card left − `DESC_BOX_GAP`, top = card top (clamped on screen); if there is
  no room on the left it flips to the card's right. Hover → drag on the same
  card keeps the panel (no rebuild) and only kills its rise tween; a drag that
  misses rebuilds it with the keyword panels back. (It used to slide to the
  top corner of the hand when the hand lowered — `_reflow_description_box` ·
  `DESC_MOVE_TIME`, **deleted**.)
  **The panels cover neighbouring cards visually but never take a touch** —
  they live on their own `CanvasLayer` (`DESC_LAYER` 2) above the hand canvas
  (layer 1), so they always draw over the cards (on the same canvas
  `_reorder_hand_nodes` would raise cards above them), and they are
  `MOUSE_FILTER_IGNORE` down to every child, so a press over them lands on the
  `HandHitLayer` band underneath and picks that card (the panels then move next
  to it).
  **Animation**: the panel is opaque; it rises `DESC_ANIM_RISE` (24) from below
  while fading in (`DESC_ANIM_IN_TIME` 0.2s) and sinks the same distance while
  fading out (`DESC_ANIM_OUT_TIME` 0.1s) before being freed (`_animate_desc_in` /
  `_animate_desc_out`) — when focus moves, the old panel sinks while the new one rises.
  **The card face carries no description text, so this panel is the only place to read text in the hand.**
  > It used to be a wide panel centred just above the hand (`DESC_BOX_W` 640), and
    before that pinned to the top of the screen (`DESC_BOX_TOP` 142) — the eye had
    to travel up and down between looking at the card and reading its text.
  - **It opens on hover.** Which card it shows is the same question as which
    card the row spreads around, so it reads `_push_focus_card()` — the card
    being dragged if there is one, else the card under the cursor. It is
    refreshed from `_apply_hand_reflow` (before that function's early-out, so a
    hover that doesn't move the row still updates the box), from `_begin_drag`
    / `_end_drag` / `deselect_current_card`, and from `_apply_hand_dim_state`
    (a dimmed hand has no focus to describe). `_desc_card` tracks what is on
    screen so an unchanged focus rebuilds nothing.
  - **Why it sits beside the card again.** An early version (320×220, beside the
    lifted card) blocked the dragging cursor's path; the wide box above the row
    fixed that but made the eye travel. Now the panel stays beside the focused
    card on hover and, during a drag, follows the card on its **left** (see above).
  - **The panel has no buttons at all.** It is a read-out, not a control surface:
    playing a card is a drop, and so is picking one for `버리기:N` (Discard:N). The 카드 내기 (Play card)
    button went with the 확인 (Confirm) row, and the 버리기 (Discard) button went with the selection
    state that used to make it reachable.
- **Dragging a card *is* the targeting step** (`_begin_drag` →
  `targeting_overlay.start_card_selection`): pulling a card out of the row
  immediately dims everything that is not a legal drop target and grows the
  ones that are (over `BattleRenderer.EMPHASIS_TWEEN_SEC`, **0.05s** — the
  emphasis has to be finished *before* the cursor reaches the target, not still
  growing under it). Nothing is spent until the drop — see the Targeting section.

#### Drag and drop (the **only** way to pick up a card)
**There is no card-selected state.** Clicking a card does nothing — only when you hold and
move more than `DRAG_THRESHOLD_PX` (10px) does the card leave the hand, and that moment is
the start of the targeting step. On release, that state vanishes entirely, whether the drop
landed or missed.

> **There used to be an intermediate "selected" state.** A click lifted the card and left
> targeting on, and you then had to drag it or click elsewhere to clear it. The interaction was
> split in two (click→drag / click→click to clear), and since a drop was the only way to play a
> card anyway, the intermediate state did nothing. `_selected_card` · `_select_card` ·
> `Card.is_selected` · `Card.card_clicked` · the outside-click deselect in
> `CardPhaseManager._unhandled_input` were all removed then. Only the **name** `deselect_current_card()`
> remains; what it does now is "forcibly tear down any in-progress drag and targeting", and
> that is exactly what its callers (phase end / restart / engage arena open / discard hide)
> want.

**The dragged card's pose depends on whether it has a target.**

| `targeting_kind` | Card while dragged | Aiming arrow | Drop point |
|---|---|---|---|
| `pilot` | **Stays in the hand** (`Card.PRESS_LIFT` lift, fan tilt kept) | ✅ | On a valid pilot marker, grown to 1.5× |
| `location` | 〃 | ✅ | On a green valid cell |
| `preview` / `none` | **Follows the cursor** (`Card.follow_cursor`, tilt straightens to 0) | ❌ | Screen-centre **drop zone** |
| During a 버리기:N (Discard:N) pick | 〃 | ❌ | Central **discard zone** |

- **Why a targeting card stays in place**: if the card flew around stuck to the cursor, it would
  cover the very target it is aiming at — the enlarged pilot portrait / green valid cell — with its
  own body, so at the moment of release you couldn't see what it was over. Instead a
  **chain of chevrons runs along a quadratic Bézier from the card's top edge to the cursor**
  (`CardDragArrow.gd`, section below).
- **Why a card with no target follows the cursor**: with nothing to aim at, there is nothing to
  hide. The interaction becomes setting the held card down in a zone, and no arrow is needed.
  `Card.begin_free_drag()` straightens the fan tilt to 0 over `FREE_DRAG_STRAIGHTEN_SEC` (0.10s)
  to give a "drawn out of the hand and held" pose.
- **The original slot stays empty.** `relayout_hand` skips the `is_dragging` card, so the
  remaining cards keep their slots and the row does not close up over the missing card.
  A missed drop returns straight to that slot (measured error 0.00px).

**A missed drop only sends the card back to its slot.** Neither cost nor card is touched before
confirmation, so there is no state to roll back in the first place. (`_end_drag` updates the cursor
position via `_update_hover_at(p)` before the reflow — so it unwinds to the correct focus.)

- **All input is handled by the single hand hit layer.** The control that received the press holds
  Godot's mouse focus until release, so even when the cursor leaves the layer (over the battlefield),
  motion and release keep arriving at that layer. Thanks to that, the battlefield side has no wiring
  at all for receiving drags. The pressed card is recorded via `_grabbable_card_at(p)`, which
  previews exactly the gates `_begin_drag` will apply (is it the operation phase (작전 단계) / is input not
  blocked / does the card really exist in the hand) — a press that cannot become a drag
  is never recorded at all.
- **Dragging into the central field zone moves the hand out of the way**
  (`_drag_lowers_hand`) — **not when the drag starts**, but the moment the cursor rises above the
  bottom edge of the drop zone (`drop_zone_rect`; y 1344 on 1080×1920)
  (`_cursor_reached_field` → `_set_drag_reached_field`, state in `_drag_reached_field`). Only the
  bottom edge is checked, not "inside the zone": targeting cards aim up to the top rows of the
  battlefield above the zone, and if the hand rose back there the screen would lurch mid-aim.
  When the cursor comes back below that edge (towards the hand), hand · strip return. At the same
  moment **the top enemy strip · opponent hand slide up, darken and drop under the battlefield
  layer** (`HudBuilder.set_enemy_top_raised`, `ui/README.md` "Top enemy UI layer"). Once in the
  zone, the hand minus the dragged card moves down by `hand_drop_offset()` (the same depth as when
  it is not my turn), and the allied strip darkens and drops `STRIP_DRAG_DROP` (120)
  (`HudBuilder.set_player_strip_dropped`). A targeting card **stays in its original lifted hand
  pose** (`_card_rest_slot` subtracts the drag drop) — only the rest of the hand goes down. On drop or
  cancel (`_end_drag` / `_cancel_drag`) `_drag_card` empties, so the next layout restores the hand and
  the same call restores the strip. It does not lower during a 버리기:N pick. Z-order is unchanged
  (cards don't hide behind the strip — that happens only when it is not my turn).
  The **caster neon on the bottom strip portrait was deleted** (`PilotStrip.set_highlight` /
  `HudBuilder.set_strip_caster` removed) — the neon on the battlefield marker
  (`CardPlayPreview.neon_pilot`) remains.
- **Drop zone** (`drop_zone_rect`) — `DROP_ZONE_H_RATIO` (0.40) of the screen height, centred on the
  screen's vertical middle; full width horizontally. On 1080×1920: `(0, 576) 1080×768`.
  **It is not drawn when playing a card** — the old "여기에 놓아 사용" (Drop here to use) band was
  deleted, and the rect is only used for the drop test of cards with no target. It shows on screen
  **only during a 버리기:N pick** ("여기에 놓아 버리기"). The hint text sits **above** the zone
  (`DROP_ZONE_LABEL_TOP`) — the middle of the zone is the middle of the battlefield, where the text
  would overlap the tiles. When the cursor enters the zone, its fill and border
  brighten (`_set_drop_zone_hot`).
- **The same zone is used during a 버리기:N pick.** `drop_zone_rect()` ignores the mode and
  always returns the same rect, and the row where picked cards line up also comes from that rect's
  centre (`CardSelectOverlay.to_discard_center_y()`). Only the text changes to "여기에 놓아 버리기" (Drop here to discard),
  and the targeting overlay is not turned on at all (`_begin_drag`). Confirmation is, as before,
  the overlay's confirm button — the drop only goes as far as "move it to the cards to discard".
  > Discard alone used to use a separate band, `DISCARD_ZONE_H`
    (440px), centred on `TO_DISCARD_CENTER_Y` (700). **The same interaction (drag a card and drop it)
    had a different drop spot depending on what it did**, so you had to re-aim every time between
    playing and discarding, and the row of picked cards and the zone's centre didn't match either.
    Both constants were deleted together.
  > **At that point the zone node is raised to canvas child index 1.** Normally it is 0 (rearmost),
  > but in discard mode `CardSelectOverlay._battle_dim` occupies 0, so left as is the zone would
  > go **under** the dim and be pressed out of sight entirely.
- **There is one confirmation path.** A drop carries only the target into
  `CardTargetingOverlay.confirm_with(target)`, which passes the
  `_play_allowed` gate and calls `_on_selection_confirm` — cost deduction /
  card consumption / effect chain all live after that. During a drag the target under the cursor is
  pre-marked via `preview_drag_target` and a cyan ring follows it. **That `pending_pick`
  is a pure preview** — releasing without a valid drop just makes it vanish.
  `_end_drag` keeps `_drag_card` alive until `_try_drop_play` finishes:
  the confirm callback returns synchronously and uses that reference to find the card.
- **Contract on the `Card` side**: `set_dragging(true)` locks **only the pose** — even when the cursor
  leaves the hand and hover drops, the 1.2× enlargement and the tallest shadow are kept (needed because
  the hit layer's hover bookkeeping no longer speaks for this card). On entry it kills
  any layout tween in progress, so `_begin_drag` immediately re-establishes the pose
  (`_pose_selected_card` or `begin_free_drag`) — otherwise the card freezes
  partway up. On exit it also calls `set_hovered(false)`, because a card moved to the discard
  row is no longer caught by `_update_hover_at`'s hand traversal and would
  stay stuck at 1.2×.
- Every path that tears down a drag (`deselect_current_card` / `end_card_phase` /
  `build_starter_decks` / `_despawn_player_card_node`) goes through `_cancel_drag()`,
  so an in-progress drag cannot survive a phase transition or restart.
- **Measured** (headless, synthetic input after forcing entry into the operation phase):
  - **Click only** — `is_dragging_card() = false`, overlay `mode = NONE`, hand size
    unchanged. There really is no selected state.
  - **Dragging a targeting card** — overlay `mode = PILOT` (or LOCATION), arrow
    node visible, drop zone **not shown**, card leaves its slot by only 24–27px (the lift).
  - **Dragging a card with no target** — overlay `mode = INSTANT`, arrow **not shown**,
    card moves 774–856px from its slot (tracking the cursor). (The drop zone is no longer drawn.)
  - **Reaching the field zone** (window 810×1440, synthetic drag) — start dragging inside the hand
    (y ≈ 1340): `_drag_reached_field = false`, hand · strip in place. Cursor to (540, 700): `true`,
    hand · allied strip lowered, `EnemyTopLayer` layer −1 · offset (0, −120). Cursor back to
    (540, 1500): `false`, layer 1 · offset 0.
  - **Missed drop** — hand size · operation points both unchanged, card returns to its own slot
    with error **0.00px** / rotation error **0.0000**.
  - **Drop on the drop zone** — hand −1 · points −cost · overlay `mode = NONE`.
  - **Drop on the discard zone** — hand −1 · `to_discard` +1; on a miss both unchanged;
    after filling 2 cards, the overlay's confirm settles normally.

##### Aiming arrow geometry (`CardDragArrow.gd`)
Chevrons laid out along a single quadratic Bézier.

| Point | Where |
|---|---|
| `p0` (start) | A point buried `ARROW_TUCK_PX` (42px) **inside the card** from the card's top edge |
| `p1` (control) | From `p0` along **the card's own up-axis** by `(distance to cursor·`BOW_RATIO` 0.55)`, clamped between `BOW_MIN` (40) and `BOW_MAX` (300) |
| `p2` (end) | The cursor |

- **Why the start point is buried inside the card**: the arrow node is **child index 0** of `_bs.canvas`
  (= behind the hand cards and every HUD widget), so its start is hidden by the card.
  That makes the arrow read as if it extends from **under** the card. The card is
  raised to the end of the child list by `_reorder_hand_nodes` every time, so this ordering holds.
  The drop zone also uses index 0, but the two **never show at the same time** (arrow = targeting
  card, drop zone = everything else).
- **Why the control point lies on the card's up-axis**: a card tilted in the fan shoots its arrow
  in its tilt direction. When the cursor is below the card, the dot product is negative, so it is
  clamped to `BOW_MIN` and **does not form a loop**.
- **The arrow is a chain of chevrons, not a continuous ribbon.** The head chevron
  (`CHEVRON_WIDTH` 7, arm length `CHEVRON_LEN` 16 · half-width `CHEVRON_HALF` 17) and the chevrons
  behind it are placed one every `CHEVRON_SPACING` (30) of curve length. **The tip of the last chevron
  touches the cursor** and placement runs back towards the card from there, so the chain always ends at
  the cursor. Each chevron faces the local curve tangent (positions come from a cumulative-length table
  over `SAMPLES` 48 pieces). The dark outline (`OUTLINE_PAD`) is laid down for **all** chevrons first,
  then the main colour on top — alternating per chevron would let a neighbour's outline cover the main
  colour. It used to be a continuous ribbon, thin at the card end (`WIDTH_START` 6) and thick at the
  head end (`WIDTH_END` 14), plus a big triangular head (**deleted**).
- **The head reads by size.** Only the last chevron at the cursor end is full size; the trailing ones
  are `TRAIL_SCALE` (0.75)× (arm length · half-width · stroke · outline all). The chain is one colour
  with no animation — the old flowing light band (`GLOW_*`, `COLOR_*_DIM`, `_process` redraw) was
  **deleted**. It redraws only when `aim()` is called.
- **The colour says whether dropping now would play it** — normally `COLOR_BASE` (gold, same family
  as the drop zone); over a valid target/cell, `COLOR_HOT` (cyan, same family as the targeting ring).
  The decision is just the bool returned from what `_update_drop_feedback` was already computing, so
  the arrow colour and the cyan ring can't disagree.
- **Outside-click deselect was deleted** (`CardPhaseManager._unhandled_input` in its entirety).
  With no selected state to clear, there's no reason to listen — the card is already back in its
  slot the moment you release.
- `deselect_current_card()` is a forced-cleanup function that survives in name only: it tears down any
  in-progress drag and targeting and lays the row back down. `end_card_phase()` / `build_starter_decks()`
  / `_despawn_player_card_node()` / `EngagePhaseManager` / `CardSelectOverlay`'s
  hide call it, so a dragged card cannot survive a phase transition or restart.
- `apply_card_effect(cd, is_player)` → String log message

### Hand preview (손패 미리보기, `CardPlayPreview`)
The moment a hand card is **pressed**, its caster is highlighted (white neon behind the battlefield
marker); once **dragging starts**, "what happens if this card is used" is drawn in advance. Drop or
cancel clears all of it — what actually happened is shown by each effect's own FX (draw intro ·
discard FX · hit FX · buff banner).

It is wired into only five places in `CardPhaseManager`: press (`_on_hit_layer_gui_input` →
`show_caster`), drag start (`_begin_drag` → `begin`), target update
(`_update_drop_feedback` → `set_target`), drop / click end (`_end_drag` /
`_finish_press` → `clear`), forced teardown (`_cancel_drag` → `clear`). It is not turned on during a
discard pick.

`_compute_spec` walks the effect chain (`effect_clauses`) to decide what to show. Conditional clauses
after `on_hit` / `on_miss` are skipped, since their outcome can't be known in advance. Hand questions
("the right N cards") are asked of **the hand minus the dragged card** — the card leaves the hand the
moment it goes out.

| Clause | Where | What |
|---|---|---|
| `draw` · `discard_hand_draw` · `draw_discarded` | Above the deck pile | 3 upward-flowing chevrons + `+N` |
| `search` · `search_card` | Above the deck pile | Magnifier + count (`search_discard`: above the discard pile) |
| `draw_discard` | Above the discard pile | Upward-flowing chevrons + `+N` |
| `discard` (chosen discard) | Above the discard pile | Downward-flowing chevrons + `-N` |
| `discard_hand` · `discard_hand_draw` · `discard_right` · `discard_left` · `discard_other_pilots` | **On those cards** | Red dim + a downward chevron at the card centre (cards with the keep keyword excluded by the same rule as each effect) |
| `preserve` | Centred above the hand row | Padlock + `보존 N` |
| `strategy` · `discard_other_pilots\|strategy_each` | Strategy point donut | Highlight + **the amount to be added** above it + centre number = **the result after paying the cost** (colour change, reflected in the gauge) — `CostDonut.set_preview` |
| `cost_reduce_hand` · `cost_reduce_engage` | Affected hand cards | The cost ribbon pulses with the new value (green) — `Card.set_cost_preview` |
| `cost_reduce_draw_phase` · `draw_discard\|cost_reduce` | On the deck pile | `비용 -N` tag |
| `move` · `ambush` | Battlefield | **One translucent ghost portrait in the middle of the aimed tile** (no path · no dotted line; no growth shown even over a jungle camp). The old per-cell BFS path + chevrons + arrival ring were deleted |
| `attack` (picked enemy) | Target marker | Blinking HP segment to be lost (shield first) + `명중 N%` · `-damage` (`처치` if lethal) |
| `shield_pct` · `shield_atk` · `heal_pct` · `recall_ally` | Target marker | Blinking HP (green) / shield (cyan) segment to be gained + value |
| `recall_ally` · `retreat_turret` | Battlefield | Translucent ghost portrait at the destination + path (dotted for recall) |
| `steal_camp` | Battlefield | Soul trail from camp → caster + `+SCORE_JUNGLE_CAMP` |

Next-phase reservations (`strategy_next_phase` · `draw_next_phase` · `strategy_on_kill` ·
`ambush_search`) get no preview; instead a **reservation chip stays after casting**
(`ui/ReservationChips.gd`; the source card is recorded into `BattleSim.reserve_src` by `_note_reserve`).

The numbers go through **the same functions** as the real resolution: hit chance via
`SimulationCore.hit_chance_of` (the very probability `roll_hit` rolls), damage via
`estimate_attack_damage` (same multipliers as `_apply_attack_damage`, no state change). Made public
for the preview: `flag_int` · `discardable` · `nearest_own_turret_cell` (formerly `_`-prefixed).

#### Buff banner (after the cast is confirmed)
When a clause that puts an effect on a pilot actually runs, a banner appears above that pilot's
battlefield portrait (rounded-square card art on the left + card name on the right, 1.9s). The single
entry point is `_apply_single_effect` — after running the clause through `_dispatch_single_effect`,
`_announce_buff` picks the subject via `BUFF_CLAUSE_SUBJECT` (clause → caster / target / subject / team).
A card that puts two clauses on the same pilot still shows one banner (`_banner_seen`). Player and AI
take the same path. Drawing is `BattleRenderer.spawn_buff_banner`.

Slot effects (single overwriting slots — laning · accrual multiplier · evasion · ambush · shield) record
the source card into `PilotData.fx_src` via `_note_fx_src` (shields: `_bs.grant_shield(...)` followed by
`_note_fx_src(...)`). It is used only so the detail panel's lasting-effect thumbnail can show that
card's illustration.

### Per-pilot decks (mech cards + 3 fixed pilot cards)
- `build_starter_decks()` — for each pilot on each side, deals a `CardData` copy
  per card and tags each with that pilot as caster (시전자) (`owner_pilot`). All 5
  stacks shuffle into the team deck. Player and AI sides build identically; the
  AI hand is logical-only but its cards still carry an enemy-pilot owner.
- **Mech cards (메크 카드) are not drawn; they come with the mech.** The assigned mech's card list
  (`mech_cards.csv`) expanded by `count` is the whole of that pilot's mech cards, and
  the number differs per mech, so the deck size varies with the lineup. `_mech_card_defs_for(p)`
  returns that mech's rows.
- **The 3 pilot cards (파일럿 카드) are fixed per player (선수)** (`_pilot_cards_for(p, pool)`). They are not
  re-rolled every match — the same player always brings the same 3 cards.
  - The source is the **`pilot_cards`** column of `players.csv` / `intl_players.csv` (card ids joined
    with `|`) → `PlayerData.pilot_cards`. `GameManager.pilot_card_ids_for(pd)` is the single
    source of the answer, and the run-setup draft detail popup (`meta/run_setup/DraftDetailPanel`) calls the same
    function to show the same 3 cards.
  - If that cell is empty or broken (missing id · a card the position blocks), the shortfall is
    filled from the **position slot table** (`data/csv/pilot_card_slots.csv`). Each position has three
    slots, and each slot is a list of card categories (`card_cat`) — it picks one `pool = 1` card that
    shares at least one category and whose `scope` allows that position (the same card is never
    held twice; `excl_group` is respected). The roll uses a `RandomNumberGenerator` **seeded with the
    player id**, so the same player gets the same answer however many times it is asked
    (`GameManager.roll_pilot_card_ids`).
  - A standalone run without player data seeds the same table with team · role.
    With neither GameManager nor the DB, it takes 3 random cards from the pool that passed only the position filter.
  - The current CSV values were filled by rolling the slot table once. **To re-roll, clear that
    cell** (empty cell = seeded roll).
- **The old "shared mech cards" (공용 메크 카드) are gone.** The `card_type = mech` rows in cards.csv
  (전투 개시 (Start Battle) · 공격 (Attack) · 필중 (Sure Hit) …) all became pilot cards, and the `MECH_CARDS_PER_PILOT` fallback and
  the per-role slot table (`_pilot_slots_for` — jungle (정글) 2 + draw 1 …) were deleted along with them.
  A standalone-run deck with no mech contains only pilot cards.
- **Mech cards with `count = 0` are still listed in the allocation table.** They don't go into the deck
  (승전보 (Victory Report) · 철거 (Demolish) · 처형 (Execute) · 락온 (Lock-on) · 고통과 쾌감 (Pain and Pleasure) · 단계 B/C (Stage B/C) — they appear only when a passive or another card
  creates them), but the detail panel's mech tab is the place that shows "what this mech does",
  so if conditional-only cards were missing there you would read only half the mech.
- **The allocation table stays in `BattleSim.starter_cards`** — `PilotData →
  {"mech": [CardData …], "pilot": [CardData ×3]}`. It records **the very copies** that `_deal_one()` puts
  into the deck, so values stamped only on the copies (the `self_cost` cost increase of 정밀 이동 (Precise Move) ·
  골드러시 (Gold Rush), 골드러시's token) also show through the table. Its only consumer is
  the detail panel's pilot / mech tabs (`ui/PilotDetailPanel.gd`), and this is **why it does not
  reverse-derive** the list by scanning hand · deck · discard pile: an exhausted (`exhaust`) card is in none
  of the three piles, so reverse-derivation would silently drop it from the list. `build_starter_decks`
  `clear()`s the table every new match.
- `make_card_copy(src)` — copies every CSV column (including `card_id` / `scope` /
  `pool` / `card_type` / `card_cat`) AND `owner_pilot`. Use this any time you need a
  deck-safe duplicate.

### Charge (power a card stores inside itself)
**Charge (충전) is a keyword; what charge fills is tokens (토큰).** A card with the `충전` keyword (`keyword =
charge`) raises its own token count (`CardData.charge`) by one **every time it enters the hand**
(cap `charge_max` — the same column in both CSVs), and when used, all stored tokens are spent at once
and it returns to 0. Four cards use it now — 미사일 (Missile) · 전장 강타 (Battlefield Smash) · 약자 멸시 (Scorn the Weak)
· **성장 가속 (Growth Acceleration) (pilot card)** — each with its own `charge_max`. 공격 명령 (Attack Order) dropped charge and moved to **being generated into the hand on every kill**
instead. Screen · card text · skill text all use this term ("토큰 +1" (Token +1),
"토큰 N개를 소모하여" (spending N tokens)) — the internal counters of skills · mech passives are also tokens on screen.

**Tokens are not filled only by charge.** [골드러시] is not a charge card; each use raises its own token
via a `token:N` clause — since it is not a charge card, use does not clear it and it keeps
stacking for the whole game (`_burn_charge` burns only charge cards).

- The only place it rises is the hand-entry hook **`_on_enter_hand(cd, is_player)`** —
  `add_card_to_hand()` · `draw_card()` · search (찾기) confirm · return from rearrangement all pass through it.
  The hook calls `CardData.gain_charge()` and also sets the [신중한 예산] (Careful Budget) indicator.
- There is one place it burns: `_burn_charge(cd)` — runs once when the card leaves the hand, and
  records the burned count in **`_charge_spent`**. It is per card rather than per clause because
  "사용 시 모든 충전을 소모" (spend all charge on use) is independent of the number of effects, and the value lives on the
  manager rather than the card because `charge` is already 0 at that point (the effect chain
  runs over several frames because of overlays).
- The effect-side flag is **`|charge`**. `attack:N|area:N|charge` (미사일) hits each target
  as many times as the charge, and `attack:N|random|charge` (전장 강타) picks **charge + 1**
  random targets (the +1 is a constant term, so it fires once even at 0 charge).
- On screen it is `Card.refresh_charge_badge()` — the `N/M` badge at the card's **bottom right**
  (`CardData.shows_tokens()` — charge cards show `토큰/상한` (tokens/cap), 골드러시 shows the token count only).
  The top right is used by the caster portrait ribbon, the top left by the cost ribbon.

> **It used to be `스택` (stack)** — identical cards merged into one card in the hand and
> `stack_count` held how many there were. The merged representation had the advantage of not touching hand size · cap trimming ·
> the fan · hit bands, but it cost two things:
> every time it went down to a pile it had to be scattered back into single cards (otherwise one reshuffle shrinks
> the deck's card count), and the power cap was `count` itself, so one card type bloated the deck by several cards.
> Charge removes both with a single copy per card in `count`. `stacks_with` / `stack_count` /
> `last_draw_merged` / `refresh_stack_badge` were deleted at that time.

### Cost -1 (unplayable cards)
`cost = -1` is not a value but **a mark that the card cannot be played** (캐시 (Cash) · 계시 (Revelation) · 약자 멸시 ·
밸런스 (Balance) · 자신감 (Confidence) · 맑은 정신 (Clear Mind) — they work just by being held in hand). `CardData.is_playable()` is that check and
three places read it — `Card._apply_data` / `update_displayed_cost` print `—` in the cost slot instead of a
number (no discount or increase applied on top), `highlight_affordable_cards` locks it as unaffordable regardless of
points, and `_begin_drag` refuses the drag itself. **But it can be dragged during a discard (버리기)
pick**: a card you can't play is not a card you can't discard.
- Card front layout — **the front is two layers, from the top: art → nameplate (이름판)**, and on top of them
  the cost ribbon sits at the top left and the caster portrait (초상) ribbon (리본) at the top-right corner. **The card has no description text** —
  for the hand it is the description panel beside the focused card; for a card the AI played, the description panel to the right of that card
  (no keyword notes, `AiCardPlayer`); for search · selection grids and pile browsing (열람), the description panel beside the pointed-at or pressed
  card; for the ban/pick (밴픽) sheet and mech detail, the description panel above the pressed card (all
  `CardDescBox`). The description panel that crammed up to 128 characters at 8pt into 160×220 was never really
  text meant to be read anyway; the art took that space, so the card is recognizable **by its picture**.
  The two layers use **absolute coordinates** (the card is fixed at 160×220, same values as `scenes/Card.tscn`).
  **The card has no border** — the two layers split and fill the card rect with no gap,
  and the `CardFront` panel itself is `StyleBoxEmpty` (a panel laid underneath would show its blurry
  edge through the clipped corners). The cost-coloured background and the yellow 'playable' border were removed —
  an unplayable card reads by the single unplayable slab.
  - **Art** (`ArtFrame` + `Art`, 0..160 × 0..184 = `NAME_TOP`, to the card edge).
    The image comes from `CardImages.art_for(card_name)` — `images/card/<이름>.png` (<이름> = name) if it
    exists, otherwise the Deadlock item icon paired by `CardImages.ITEM_ART`
    (`images/ground/deadlock_items/`, all 96 now), and if not in the table either, one of the five
    `images/ground/N.png` **chosen by name hash**.
    **The two top corners are clipped by `resources/shaders/rounded_top_mask.gdshader` to match the card
    corner (`CARD_RADIUS` 10)** — coverage is computed with a rounded-rect SDF so the
    curve blurs over 1 screen px (`fwidth`; it follows hover enlargement too), so there is no
    stair-stepping. The mask measures in node-local pixels (`VERTEX`), not UV —
    `STRETCH_KEEP_ASPECT_COVERED` draws only part of the texture, so the UV does not cover the rect.
    The bottom edge is not blurred (a dark line would appear at the seam with the nameplate).
    `clip_children` is not used: it takes a back buffer per card and its edges are stair-stepped.
    Only when there is no image at all does `ArtFrame` draw a dark background (`ART_BACK_COLOR`).
    > Previously only the top 1/3 (`ART_H` 74) was art, and below it came one name line + the description panel.
    > After that the frame sat 5px in from the border (`ART_INSET`) and the cost-coloured background surrounded the image.
  - **Nameplate** (`NamePlate` + `NameLabel`, 0..160 × 184..220, `NAME_PLATE_H` 36).
    Name text is `NAME_FONT_SIZE` 23 (was 15); a name wider than the label (148px)
    steps down to fit via `_fit_name_font_size` (floor `NAME_FONT_MIN` 14).
    Full width along the card's bottom, a plate with no border filled only with the **item type colour** (`Card.TYPE_COLORS`);
    its two bottom corners are the card's corners. The type is answered by `CardImages.type_for`
    from the icon filename prefix — `wpn` weapon `#A86A22` · `spt` spirit `#7E4FB0` ·
    `vit` vitality `#5A8A16` (deadlock.wiki colours darkened so white text stays readable); cards with no
    type use `NAME_PLATE_NEUTRAL_COLOR`.
  - **Top-left cost ribbon** (`CostBadge` + `CostLabel`, `COST_RIBBON_RECT`
    (10, -3, 38×73)). Its top edge pokes `COST_RIBBON_POKE` (3px) above the card's top edge (the bottom
    edge · number slot are unchanged from the old (10, 0, 38×70)); a **tall right trapezoid** hanging down
    from the card's top edge (`CostRibbon`) — only the bottom edge is slanted, so the bottom-left reaches
    lower and the bottom-right is slightly shorter. A big number (`COST_FONT_SIZE` 32) in the top band
    (`COST_NUMBER_H` 50). **Opaque white fill with a dark number** (`CostRibbon.INK`, no outline), and a
    drop shadow below the bottom edge like the caster portrait ribbon (`CostRibbon.SHADOW_*`). No border
    and no inner icon (a strategy-point octagon was tried and removed). The ribbon starts inside the
    card's rounded corner, so it stays within the card. In the scene it is a `CardFront` child, but at
    runtime it is moved to the root's last child so it draws above the unplayable slab · keep border ·
    portrait ribbon. The hand is a fan where cards overlap by more than half (the right card covers the
    left one), so **the top left is the only corner always visible on each card**. The ribbon fill is
    `COST_BADGE_FILL_COLOR` (= `CostRibbon.FILL`, white). The number colours `COST_COLOR_BASE` /
    `_REDUCED` / `_INCREASED` are dark ink · deep green · deep red for a white background (the
    description panel's header ribbon uses the same three).
    > It used to be a 42px octagon sticking out of the card corner at (-9, -9).
    `Card.update_displayed_cost(eff)` repaints the number — base colour if it matches,
    green if discounted (사전 준비 (Preparation) / 전투 준비 (Battle Prep) / 집중 (Focus) / 신중한 예산 / 맑은 정신),
    red if increased (`cost_inc_phase`; no card in the current pool has that clause). **The cost increase of 정밀 이동 ·
    골드러시 is not a modifier** — `self_cost:N` raises the card's own `cost`,
    so a returned card is printed at its new price in the base colour. `CardPhaseManager.highlight_affordable_cards` calls it
    for every visible card so the cost modifiers and the card display never disagree.
    **The ribbon sits above the slab**, so `_refresh_block_overlay` dims it directly with
    `COST_BADGE_BLOCKED_TINT` — otherwise only the cost would stay bright on a locked card.
  - **Top-right corner = caster portrait ribbon** (`OwnerRibbon`). A **right triangle** whose two legs
    (`RIBBON_LEG` 60) lie along the card's top and right edges, with the pilot cropped inside it
    so both eyes show. There is no hypotenuse border; a shadow falls only below
    the hypotenuse (node height = `RIBBON_LEG + RIBBON_SHADOW_PAD`).
    **It is a PNG baked per pilot, not runtime masking** —
    `PilotImages.ribbon_for(owner.pilot_id)` (`pilot/ribbon/N_ribbon.png`,
    `make_ribbon_crops.py`). The triangle · rounded card corner · anti-aliasing · shadow are
    all in the image, so Card holds just one plain `TextureRect`. With a mask
    shader, every hand card would get a `ShaderMaterial`, costing first-use
    pipeline compilation · batch breaking on mobile, plus SDF math for the hypotenuse · rounded-corner AA
    on top — small but not zero, so baking was chosen.
    If you change the size, update `Card.RIBBON_*` and the script's `LEG` / `SHADOW_PAD` together
    and re-bake.
    **Drawn only in the hand** (`is_player_card`) — in places that show "the cards this mech gives",
    like the detail panel · pile browse · ban/pick · draft, there is no caster or it is
    meaningless, and the opponent hand peek is face-down so there is nothing to draw. It sits **below**
    the unplayable slab, so on a locked card the face dims too.
    > **The overlap is an accepted trade-off.** Past 7 cards in hand, the right card covers at least the
      right 1/3 of the left card, so the ribbon is fully visible only on the rightmost card and the pointed-at card (the row
      spreads apart). This undoes the earlier move to a round top-left portrait, which was made for exactly that
      reason (user decision, 2026-10).
    > Even earlier, the caster's face (`PilotImages.face_for`) **filled the whole card
      body**, and the same face was laid on every card display outside the hand too (detail panel · browse · ban/pick),
      repeating "whose card is this" regardless of context.
  - **Bottom right of the art, just above the nameplate**: token badge `N/M` / `N`
    (`CHARGE_BADGE_SIZE` 52×30). Hidden for cards that don't use tokens. It sits above the nameplate
    so it doesn't cover the name.
  - **Unplayable dim** (`BlockOverlay`): a `Panel` at the **end** of the child
    list — above `CardFront`, so it darkens the art, portrait, name, cost and
    description together — filled `BLOCKED_OVERLAY_COLOR` (black α 0.58) with
    the card's own 10 px corner radius. It goes up for either of two reasons,
    tracked independently and merged by `_refresh_block_overlay()`:
    `set_affordable(false)` (can't pay) or `set_respawn_turns(n > 0)`
    (caster awaiting respawn). `set_affordable` no longer repaints the card body grey
    — the grey panel sat *under* the portrait, which stayed bright and read as
    playable. The card has no border any more, so the slab is the only cue.
  - **Respawn countdown** (`RespawnCountdown`): a `Label` next to the slab,
    `RESPAWN_FONT_SIZE` 76 with a 10 px outline, showing the turns left until
    the caster comes back. Visible only while `set_respawn_turns(n)` is
    non-zero. `Card.is_playable()` returns false whenever either reason holds.
    Both nodes must be `MOUSE_FILTER_IGNORE` — see the filter note below.
  - **No role badge.** Role is conveyed by the owner portrait badge.

#### Hand raise/lower — when it is not my turn, the hand pulls back
**Outside my operation phase (작전 단계), the hand drops toward the bottom of the screen and hides behind the ally (아군) pilot strip (스트립).**
About half of each card is hidden by the strip backplate (뒤판), and when my turn (차례) comes it rises straight back up.

- The condition is just `_hand_is_lowered()` = `game_phase != CARD_PHASE`. The key point is that it is **narrower**
  than the dim condition (`_apply_hand_dim_state`) — during brief input-blocked stretches inside my turn (hit (명중) FX ·
  modal pick · turn banner) the hand only darkens and does not drop. If it dropped then too, the hand would go up and
  down on every modal.
- **Position**: `hand_drop_offset()` is added to `slot_position()`. The value is not a constant;
  it is back-calculated from the strip backplate — `_bs.hud.player_strip_backdrop_top()
  − Card.CARD_H × 0.5 − BS_HAND_CENTER.y`. Both already include the safe area (안전 영역) offset,
  so "about half hidden" holds regardless of device (**206px** at 1080×1920).
- **z-order** is changed by `_reorder_hand_nodes()`. Dropping alone leaves the cards drawn
  **over** the strip panel, not hidden, so it takes that panel (`player_strip_backdrop()`)
  as a marker and inserts the cards one by one **right before** it, moving the whole batch below the panel.
  If a card was after the marker, removing it leaves the marker index unchanged, so it goes at that index;
  if it was before, the marker shifts back one, so it goes one slot earlier. The reverse (my turn)
  is the end of the child list, as before. The early-exit check (`sorted`) is also recomputed
  on that basis, so repeated calls don't touch the tree.
- **Shadow**: `Card.set_lowered()` switches it to `SHADOW_FAR_*` (offset 1×4, blur 3,
  spread 0.98). **A short shadow hugging the card = far from the camera** is the
  whole effect — on my turn it returns to the usual three stages rest / hover / drag.
  In the lowered state there is neither hover nor drag, so the four branches never conflict.
- **The hit layer drops too** (`_fit_hit_layer` applies `hand_drop_offset()`).
  Otherwise it would swallow clicks on the battlefield (전장) where there are no cards.

#### Hand hit layer — draw order must not decide hit-testing
Player hand cards do **not** pick the mouse. `spawn_card_node` runs
`_set_subtree_mouse_ignore(node)` over the card and every descendant, and one
transparent `Control` (`HandHitLayer`, built by `_fit_hit_layer`) sits over the
whole row and routes hover and clicks itself.

Letting each card claim its own rect is what made a packed hand unclickable.
The cards overlap far more than they are wide — 160px cards on a 67.5px stride
at 12 cards — and the focus card is drawn on top at 1.2×, so it ate the
only pixels its right-hand neighbour had left. Measured across every focus
position of a 12-card hand: the card immediately right of the hovered one kept
**5–17px**, and **0px** with card 8 focused — that neighbour could not be
hovered at all, which is why moving the cursor one card to the right appeared to
do nothing or to skip a card. Every other card kept 40–110px, so the damage was
specific to the right-hand neighbour: the fan overlaps rightward, so each card's
only exposed strip is its left edge, and that is exactly the strip the enlarged
focus card covers.

- `_apply_hit_bands(total)` — cuts the row into `_hit_bands[i]`, one
  viewport-space `[left, right]` per card, at the **midpoints between
  neighbouring card centres**. They tile the row exactly (no overlap to fight
  over, no gap to fall through), so every card owns ~`slot_spacing` px no matter
  who is drawn over it. The two end cards extend their band out to their own
  edge so the ends of the row stay clickable. Runs from `relayout_hand`, so the
  bands always match the layout that is on screen.
- `_hand_card_at(p)` — band lookup plus **one hysteresis rule: the focus card
  holds the cursor while it is anywhere on its enlarged face.** Without it the
  hand walks away from the cursor: hovering a card re-spreads the row, which
  slides the bands under a stationary cursor, which hands the hover to the next
  card along, which re-spreads again. That cascade was real and measured — one
  step from card 0 toward card 1 ran the focus 0 → 2 → 4 → 6 → 8 → 10 → 11.
- `_on_hit_layer_gui_input` — the hand's whole pointer story lives here: motion
  drives `_update_hover_at` (or the drag, once the press has passed
  `DRAG_THRESHOLD_PX`), a press just records `_grabbable_card_at(p)` in
  `_press_card`, and the release goes to `_finish_press` — which resolves the
  drop if a drag ever started and **does nothing at all otherwise**.
  `accept_event()` on both press and release keeps them out of
  `CardTargetingOverlay`'s battlefield press handler.
  **The layer keeps Godot's mouse focus while the button is held**, so motion
  and release keep arriving after the cursor has left its rect — that is the
  whole mechanism behind dragging a card out over the battlefield, and it is why
  no other node needs drag wiring.
- `Card.set_hovered(bool)` is the hover entry point. `_on_mouse_entered` /
  `_on_mouse_exited` still forward to it for the AI peek row and the search grid,
  which are flat and don't overlap.
- The layer is sized to the band the cards already occupy (row span + hover
  enlargement, plus the lift only while a card is being dragged), so it can't swallow
  anything the cards weren't covering. It clears the player strategy point (전략 포인트) donut
  (bottom 1350 vs layer top 1378). The description box no longer competes with
  it at all — it moved to the top of the screen and is `MOUSE_FILTER_IGNORE`.

Verified at both hand sizes: 0 sweep mismatches, 0 bad neighbour steps, and the
worst reachable strip anywhere is **28px at 12 cards** (was 0px) / **73px at 8
cards**.

#### Every decorative child in Card.tscn must be IGNORE or PASS
Hover and click both live on the `Card` root (`mouse_entered` / `_gui_input`).
Any descendant left on `MOUSE_FILTER_STOP` swallows the mouse over its own rect,
punching an invisible hole in the card: the cursor sits visibly on the card and
nothing happens. `HeaderRow` shipped that way (a plain `Control` — the default
is STOP) and killed hover across its 30px band, 36px on screen once the card is
hover-scaled, ≈13% of the card height just under the top edge.

Godot's per-class defaults are why this is easy to miss: `Container` subclasses
(`MarginContainer`, `VBoxContainer`, `CenterContainer`) default to **PASS** and
`Label` to **IGNORE**, so those are fine untouched — but plain `Control`,
`Panel`, `TextureRect`, `ColorRect` and friends default to **STOP** and must be
set to `mouse_filter = 2` explicitly. `CardBack`, `CardFront`, `HeaderRow` and
`OwnerFace` all carry that override. Verified: 218 sample points down and up the
full card rect, 0 dead.

**For hand cards, PASS is not good enough either** — hence
`_set_subtree_mouse_ignore`. A PASS control is still *returned by picking*; it
only forwards the event to its parent afterwards. So Card.tscn's
`MarginContainer` / `VBoxContainer` / `CenterContainer`, which are PASS by class
default, kept answering for the card's whole rect: the hit layer underneath
never saw a single event, and because Godot also walks a mouse-enter up the
parent chain, the Card still lit up — which reads exactly like the hit layer
working and made this a slow one to find. Same defaults as above, opposite
direction.

### cards.csv columns — `scope` / `pool` / `card_type` / `card_cat` / `excl_group` / `charge_max`
All flow `cards.csv` → `addons/csv_to_db/csv_to_db.gd` (SCHEMAS + TABLE_DEFS) →
`GameManager.card_pool_bs` → `CardData.from_def`. **Adding a column means running
Project → Tools → Rebuild game.db**; until then `GameManager` reads them with
defaults so an older game.db still loads.

| Column | Values | Meaning |
|---|---|---|
| `scope` | list of positions | **Caster (시전자) constraint — which positions may hold the card.** `any` alone = all five positions, `lane` alone = top · mid · carry · support (탑 · 미드 · 원딜 · 서폿); otherwise `jungle` / `top` / `mid` / `carry` / `support` joined with `\|` (`top\|mid\|carry` …). Expansion is done only by `CardData.positions_of`; if it contains only unknown tokens it is read as all five. Role → position key is `GameEnums.position_key(role)`. Checked when choosing fixed pilot (파일럿) cards (카드). |
| `pool`  | `1` / `0` | `0` = not a pilot card candidate (결투 (Duel) · 전령 제압 (Herald Subdued) · 용 보상 (Dragon Reward) · 핫핸드 (Hot Hand) · 이동 (Move) — cards produced by objective (오브젝트) rewards and skills). |
| `card_type` | `pilot` | **Every row in cards.csv is a pilot card.** `mech` is stamped only on cards built from `mech_cards.csv` (`make_mech_card`). |
| `card_cat` | list of categories | Card category — several joined with `\|` (`growth` 성장 (growth) · `engage` 교전 (engage) · `ambush` 매복 (ambush) · `attack` 공격 (attack) · `defense` 방어 (defense) · `utility` 유틸리티 (utility) · `draw` 뽑기 (draw) · `jungle` 정글 (jungle) · `lane` 라인전 (laning)). The slot table's columns pick candidates by this value. Grant-only cards use `-`. |
| `excl_group` | empty string / group name | **Mutually exclusive group.** Among cards with the same value, a pilot holds **only one**. No card uses it now (the `laning` pair disappeared when 안전한 파밍 (Safe Farming) turned into 소극적인 태세 (Passive Stance)). |
| `charge_max` | integer | Charge (충전) cap. Read only for cards with the `charge` keyword (성장 가속 (Growth Acceleration)). |

The `keyword` column is a **`|`-separated list** (`exhaust` / `preserve` / `volatile` /
`charge` / **`reposition`**). Checks must always go through
`CardData.has_keyword(kw)`. **Keywords are not repeated in the description text** — the description box (`CardDescBox`) draws a keyword
line under the name, and at the very bottom a one-line explanation per keyword (`CardData.keyword_label` /
`keyword_note`). That is why lead-ins such as "소멸." (Exhaust.) · "충전. 내 핸드에
들어올 때 충전 +1 (최대 N)." (Charge. When it enters my hand, Charge +1 (max N).) were stripped from the description text of both CSVs.

#### Categories of the current 43 rows
| Category | Cards |
|---|---|
| 교전 (engage) | 교전 개시 (Engage Start) · 완벽한 기회 (Perfect Opportunity) · 대결 (Showdown) · 결투 (`pool=0`) |
| 매복 (ambush) | 매복 (Ambush) |
| 공격 (attack) | 찌르기 (Jab) · 정밀 공격 (Precise Attack) · 연속 공격 (Combo Attack) · 무모한 돌격 (Reckless Charge) |
| 방어 (defense) | 보호 (Protect) · 소극적인 태세 |
| 성장 (growth) | 골드러시 (Gold Rush) · 몰입 (Immersion) · 워밍업 (Warm-up) · 신중한 예산 (Careful Budget) · 성장 가속 |
| 유틸리티 (utility) | 복귀 (Return to Base) · 자신감 (Confidence) · 맑은 정신 (Clear Mind) · 준비 태세 (Readiness) |
| 뽑기 (draw) | 교환 (Exchange) · 조정 (Adjust) · 임기응변 (Improvise) · 재빠른 사고 (Quick Thinking) · 집중 (Focus) · 사전 준비 (Preparation) · 아드레날린 (Adrenaline) · 계획 살인 (Planned Kill) · 재고 (Reconsider) · 완벽한 마무리 (Perfect Finish) · 계획 중시 (Prioritize the Plan) · 과감한 정리 (Bold Cleanup) · 솔로 퍼포먼스 (Solo Performance) · 핫핸드(`pool=0`) |
| 정글 (jungle) | 전투 준비 (Battle Prep) · 정밀 이동 (Precise Move) · 약탈 (Plunder) · 정글 파밍 (Jungle Farming) |
| 라인전 (laning) | 전진 (Advance) · 공격적인 라인전 (Aggressive Laning) |
| `-` (grant-only) | 전령 제압 · 용 보상 · 이동 |

**The four that were renamed** — 교전 개시 (← 전투 개시 (Start Battle), id 1) · 찌르기 (← 공격 (Attack), id 7) · 정밀
공격 (← 필중 (Sure Hit), id 8, effect still sure-hit) · 소극적인 태세 (← 안전한 파밍, id 24, effect also
replaced). To avoid name clashes, three new cards were renamed from the plan doc — **몰입** (← 집중력 (Concentration),
clashes with `집중` id 16), **성장 가속** (← 성장 집중 (Growth Focus)), **자신감** (← 고양감 (Elation), clashes with pilot skill
[고양감]). ids are unchanged, so saves · the distribution table · skills' card-id constants don't break
— only the names and the art table (`CardImages.ITEM_ART`) keys changed.

**The two objective reward cards have no caster** (`owner_pilot == null`) — the team earned
them, not any one pilot, and attaching a caster would lock the reward entirely while that pilot
is down. So they skip the `scope` check too and come out only via
`CardPhaseManager.grant_cards_to_hand` / `grant_cards_to_deck`.
With no range origin, target computation reads `caster == null` as **"the whole battlefield (전장) is in range"**
(`compute_valid_pilot_targets` / `compute_valid_location_targets` /
`CardTargetingOverlay.start_card_selection`). Only engage (PREVIEW) is the exception and requires a
caster — because it gathers participants around the caster's cell. Full rules in
`objective/README.md`.

**Two cards with similar names**: **재빠른 사고** (id 15, `draw:N`) and **과감한 정리**
(id 29, `discard_right:N;draw:N`) are different cards.

### Pilot card additions — hand-resident · operation phase · ambush
- **Hand-resident pilot cards** (`hand_passive:<key>`). Mech-side (메크) resident cards (캐시 (Cash) · 계시 (Revelation) …) are
  read by `MechSkillSystem`, but the three below are read by `CardPhaseManager`; the place that computes the value
  asks through the orchestrator.

  | Card | Where it is asked | Function |
  |---|---|---|
  | 골드러시 — growth +`GOLD_RUSH_GROWTH_PER_TOKEN` per token (토큰) (const.csv `CARD_GOLD_RUSH_GROWTH_PER_TOKEN`) | `BattleSim.add_score` (adds to accrual multiplier) | `hand_growth_add(p)` |
  | 자신감 — battlefield hit (명중) +`CONFIDENCE_HIT_BONUS` (const.csv `CARD_CONFIDENCE_HIT_BONUS`) | `SimulationCore.roll_hit` (attacker hit multiplier) | `hand_hit_add(p)` |
  | 맑은 정신 — cost cut by `CLEAR_MIND_COST_CUT` for the cards on both sides (const.csv `CARD_CLEAR_MIND_COST_CUT`) | `BattleSim.effective_cost_for` | `hand_neighbor_discount(cd, is_player)` |

  All three count **only cards in that pilot's hand (손패)** (multiple copies of the same card add up). 맑은 정신
  looks at hand **position**, so both the moment the AI measures cost (`run_ai_plays` — before removing from hand) and
  the moment the player plays (`_play_card_direct` — before removing) look at that position.
- **자신감 is not repositioned** — the old "move to the leftmost slot of the hand on surviving an engage"
  (`on_engage_end` · `_reposition_in_hand`) and its `reposition` keyword on 자신감 were deleted.
- **신중한 예산** (`free_in_phase` marker clause) — if the card enters the hand **during that side's operation phase (작전 단계)**
  (`_on_enter_hand` → `_side_in_phase`: player = CARD_PHASE, AI = its own turn
  `_ai_play_in_progress`), `CardData.free_this_phase` is set and `effective_cost_for` answers
  0. When that side's operation phase closes, `_clear_phase_free(is_player)` sweeps the hand · deck (덱) ·
  discard (버리기) pile and clears it. BATTLE's auto-draw is not an operation phase, so it doesn't apply
  — in practice draws · searches (찾기) during the operation phase and 준비 태세's phase-start draw make this card
  free.
- **매복** — the `ambush` clause moves the caster to a **jungle tile** within its `cast_range` (`compute_ambush_targets`,
  any owner, staying in place included) and sets `PilotData.ambush_hold`. Meanwhile
  `SimulationCore.resolve_movement` excludes that pilot from movement (pushes don't move it either) and
  `RecallSystem.process_phase_end_recalls` skips its out-of-position check. It is released in the entry settlement of that team's next
  operation phase (also released by death · return-to-base (복귀) to base (본진) · the 복귀 card), and at the same
  point an `ambush_search:N` reservation searches the deck for **that caster's engage card** (`is_engage_card` —
  an `engage` or `duel` clause) (it is targeted, so there is no modal). A lane pilot still standing in the
  jungle after the ambush is released is recalled (귀환) as usual for being out of position at the end of that operation phase.

### Effect chain encoding (cards.csv `effect` column)
The DB column is a `;`-separated chain of clauses. Each clause is
`name[:value][|flag[:value]]…`. Examples:
- `draw:N;discard:N`            — two clauses run in order
- `attack:N|pierce`             — one clause + one modifier flag
- `engage:N|exclude_lane`       — engage with lane-exclusion modifier
                                 (parsed and honoured, but no card in the pool
                                  carries it since 교전 (Engage) was removed)

`apply_card_effect()` parses the chain, dispatches each clause through
`_apply_single_effect`, and returns one log line of the form
`<시전자> [<카드명>] · <효과 요약>, <효과 요약>…` (`<caster> [<card name>] · <effect summary>, <effect summary>…`).

### Effect handlers
> **Note on the "opens CardTargetingOverlay …" wording below**: the target is
> now resolved *before* the effect chain runs — picking happens the moment the
> card is lifted in hand, and the handler receives the already-chosen
> `selected_target`. Read those cells as "this card's `targeting_kind` is
> PILOT / LOCATION / PREVIEW", not as "the handler opens a modal".

| name | Implemented | Behaviour |
|---|---|---|
| `draw:N` | yes | Pull N from deck (reshuffles discard if empty); spawns visual node for the player |
| `search:N` | yes | **Player**: opens CardSelectOverlay search grid — pick exactly N from the deck via 확인 (Confirm). **AI**: same as `draw:N` (random top-of-deck). |
| `discard:N` | yes | **Player**: opens CardSelectOverlay discard pick — **drag** exactly N cards onto the centred 버리기 구역 (discard zone), then press 확인 to commit. The played 버리기 (Discard) card is non-cancellable (no 버리기 취소 (Cancel discard) button). **AI**: random N from hand. |
| `strategy:N` | yes | +N 작전 점수 (operation points) to playing side |
| `attack:N` | yes | **Player**: opens CardTargetingOverlay PILOT mode — battle tiles dim, valid enemy pilots ringed, click an enemy to commit. **AI**: random valid pilot (range-aware). **Rolls `SimulationCore.roll_hit` (`hit/(hit+evasion)`, the same roll the battlefield uses) — a miss deals nothing.** Damage on a hit = `caster.atk × N`; 보호막 (shield) absorbs first. `pierce` (필중, sure hit) skips the roll; `repeat` (연속 공격) re-rolls the same attack after every landed hit, stopping on a miss, on the target's death, or at `MAX_ATTACK_REPEATS` (const.csv `CARD_MAX_ATTACK_REPEATS`). `min_range:N` filters out pilots closer than N (parsed, but no card in the pool carries it since 저격 (Snipe) was removed). **Every swing floats its verdict over the target** via `BattleRenderer.spawn_pilot_popup`: `MISS` on a miss, `-N` on a hit, `흡수` (Absorbed) when 보호막 ate the whole hit (the handler returns HP damage, so that case would otherwise read `-0`). **Each strike gets a hit FX (cast flash → shards + shake) and this clause `await`s it** — see the *Attack hit FX* section below. **The flags decide the target set** (`_resolve_attack_victims`): `\|all` every enemy on the battlefield / `\|random` random / `\|self_range:N` radius around the caster / `\|area:N` radius around the **picked enemy** / `\|around_target:N` radius around the **picked ally** ([공격 명령] (Attack Order)) / `\|damaged` enemies hit this phase / `\|line` lane corridor / `\|turret_only` the designated turret (포탑). `around_target` exists separately from `area` because of the origin's team — when `picked` was an ally, the default form's "the one designated enemy" fallbacks all failed the team check and picked **some unrelated enemy** (the long-lived [공격 명령] bug). |
| `shield_pct:N` | yes | **Player**: PILOT mode → click an ally; gains shield = N% of max_hp. **AI**: random ally. Cleared on 본진 복귀 (return to base). Granted through `BattleSim.grant_shield` with the caster as source (`shield_atk` too) and `heal_pct` heals through `BattleSim.apply_heal` — the caster earns match-stat **care** for what it absorbs / heals on other allies (`combat/README.md` "Match stats"). |
| `recall_ally` | yes | **Player**: PILOT mode → click an ally; teleports to HQ at full HP, shield reset, waypoint reset. **AI**: random ally. |
| `exhaust_choice:N` | yes (random) | Random N from hand → removed (소멸, exhaust). Parsed and honoured, but no card in the pool carries it since 차선책 (Plan B) was removed. |
| `engage:N` | yes | **Player**: dragging it opens CardTargetingOverlay PREVIEW mode (caster cell + its engage area highlighted); dropping it in the centre drop zone **submits** the card, which puts up the VS 개시 확인 화면 (opening (개시) confirmation screen) (`engage/EngageIntro.gd`) — 확인 launches the arena, 취소 (Cancel) rolls the whole play back via `_on_overlay_cancel`. **AI**: same flow via AiCardPlayer. `exclude_lane` flag propagates. **N is the number of rounds (라운드) as-is** — within one round every participant acts once, one at a time, in turn (the old "N × 3 seconds" conversion was deleted). **This clause awaits `engage_finished` until the stage (무대) closes** — because later clauses ask about the engage result ([우세한 전장] (Dominant Battlefield)'s `gen_hand:19\|per_kill`, [단계 B] (Phase B)'s `phase_b`). Without waiting, those two would settle before the first round even runs, i.e. at a point where the kill count is always 0. On return it puts **the number of kills the caster scored in this engage** into `_last_attack_kills`, so `per_kill` asks the same question unchanged without knowing the clause type (a downed caster = 0 — "if it survives"). |
| `duel` | yes | **Player**: PILOT mode → click an enemy in range; opens the turn-based arena restricted to caster + target with the round counter running up instead of a budget, ends on first KO — there is no disengage, so unless someone is KO'd it runs up to the `DUEL_MAX_ROUNDS` cap (const.csv `ENGAGE_DUEL_MAX_ROUNDS`). **AI**: random enemy in range. Routes through `EngagePhaseManager.start_duel`. **결투 (id 3) is `pool = 0`** — fully implemented but no longer dealt at random; it is reserved as a future mech-unique card. |
| `steal_camp:N` | yes | 약탈 — **remotely steals one filled camp (캠프) from a jungle cell owned by the enemy.** **Player**: LOCATION mode over `compute_steal_camp_targets` — every jungle cell owned by the enemy team **whose camp is filled**, ignoring range (`cast_range` is unlimited). Settlement is only `SimulationCore.steal_camp_point`, and both the value (`SCORE_JUNGLE_CAMP`) and the respawn clock (`JUNGLE_CAMP_RESPAWN_TURNS`) are **the same as eating it by stepping on it** — one card buys "one step on it" regardless of distance. **Ownership does not change.** `N` is not read (a placeholder value). **AI**: random valid cell. It used to be the **점령** (Capture) card — it flipped enemy jungle cells adjacent to allied jungle to its own colour for N turns and `temp_zone_overrides` reverted them on expiry; that wiring and `process_temp_zone_expiries` were deleted together. |
| `move` | yes | **Player**: LOCATION mode → click any cell in `cast_range` (jungle cells included; the lane-pilot displacement recall pulls them back at phase end if needed). **AI**: random valid cell. Caster's `grid_pos` snaps to the picked cell and `BattleSim.anim_pilot_move` plays the tween. Decorators on the same chain (`self_cost:N`, `cost_reduce_engage:N`) run separately; 재배치 (reposition) is the `reposition` keyword, resolved at disposal. |
| `self_cost:N` | yes | Raises the `cost` of **that copy** of the card currently resolving by N (permanent, cumulative). Reposition cards (정밀 이동 · 골드러시) carry it — if a card returned to hand went out again at the same cost the AI loop would never end, so this clause is the cap. The old `return_left:N` (one clause doing return-to-hand + cost increase) was split into **the reposition keyword + this clause**. |
| `cost_reduce_engage:N` | yes | One-shot pending discount on the side's next engage card. Stored on `_bs.engage_discount_p/ai`; consumed in `_play_card_direct` / `AiCardPlayer.run_ai_plays`. |
| `cost_reduce_hand:N` | yes | Mutates every card currently in hand — `cost = max(0, cost - N)`. The played card is already gone from hand by the time this fires. |
| `cost_reduce_draw_phase:N` | yes | Phase-bound draw discount; `draw_card` mutates each drawn `CardData.cost` while `_bs.phase_draw_discount_*` is active. Reset on `start_card_phase`. |
| `cost_inc_phase:N` | yes | Phase-bound additive cost bump on every card play during this 작전 단계. Stored on `_bs.phase_cost_inc_*`; consumed by `effective_cost_for`. Reset on `start_card_phase`. **No card in the pool carries it** — 정밀 이동 used to, but its increase is now self-only (`self_cost:N`). The clause is parsed and honoured, so any future card can take it. |
| `advance:N` | yes | Caster runs `N` mini-ticks of lane push through `SimulationCore.advance_pilot`. Each tick resolves combat at the caster's cell as usual **but forces the push result: the caster's side always wins the cell** (damage rolls are untouched — only who gets pushed is fixed). The caster **plus every same-cell, same-scope ally** steps forward and every same-cell enemy is pushed back one cell. If the next cell is a **same-lane enemy turret** the group holds one tile short and sieges it instead (turret takes `atk`, defenders on the turret cell roll back at the attackers, no knockback) — the siege waits a tick when the group just pushed an enemy onto that cell. A caster already standing on an enemy turret cell hits it and falls back one tile; that is the only way 전진 ever moves backwards. |
| `strategy_on_kill:N` | yes | 계획 살인 — **prepaid reservation**. When the card is played it plants `_bs.kill_bounty_p/ai = N`; when `BattleSim.mark_pilot_dead` sees an opposing-team pilot die, it pays out once and consumes it to 0. There is no third faction on the battlefield, so "the team opposite the dead pilot" suffices as the killer — no killer argument was added to `mark_pilot_dead`. Playing two in the same phase leaves only the larger one (the bounty covers one kill). Unused amounts vanish at `end_card_phase` / end of `_run_ai_turn`. |
| `lane_stat:N\|turns:T` | yes | 공격적인 라인전 — caster's `lane_stat_mod = N/100`, `lane_stat_expire_turn = turn_count + T`. **Battlefield hit roll only**: `SimulationCore.roll_hit` multiplies the attacker's `hit` and the defender's `evasion` by each one's own multiplier. Does not touch `atk` / `max_hp` (those belong to growth). Applying it twice to the same pilot **overwrites**. |
| `growth:N\|turns:T` | yes | 신중한 예산 · 성장 가속 · 소극적인 태세 — sets the caster's growth (성장) **gain multiplier** to `1 + N/100`. It is a multiple of the growth rate, not an amount added to the rate itself (+N% scales the per-turn rate by `1 + N/100`). Expiry is checked every turn by `SimulationCore.tick_growth_and_expiries`. With **`\|charge`**, N is multiplied by **the number of tokens burned** (성장 가속: its `growth` N per token; with 0 tokens nothing happens). It is an effect that overwrites one slot, so the later one wins. |
| `growth_until_phase:N` | yes | 완벽한 마무리 — raises the growth gain multiplier of **every member of the caster's team** to `1 + N/100` and sets `growth_until_phase`. `_apply_phase_entry_carryovers` clears it when that team enters its next operation phase. Uses the same field as `growth:N`, so the later one wins. |
| `growth_perm:N` | yes | [용 보상] — **permanently accumulates** N%p onto the growth accrual multiplier of **one designated allied pilot**. No expiry, no removal. It does not go into the `growth_rate_mult` used by the two clauses above (a slot they overwrite) but into a separate field `PilotData.growth_rate_bonus` — in the slot, eating the Dragon (용) several times would stop at a single Dragon's worth and a single laning card afterwards would wipe it. This clause is the **only** source of Dragon growth (the old `OBJ_DRAGON_GROWTH_PCT` game_config key was deleted). The final multiplier is combined in `BattleSim.add_score` as `growth_rate_mult + growth_rate_bonus`. **A card with no picked target applies it to the caster itself** — [핫핸드] is that case (an untargeted `instant` card, so `picked` is always null). The display reads the **per-card ledger** (`PilotData.persistent_fx`), not the total slot — see the *Persistent-effect ledger* section below. **Player**: PILOT mode (`target=ally`, unlimited `cast_range` — no caster, so the whole battlefield). **AI**: random ally. |
| `turret_damage:N` | yes | [전령 제압] — N damage to the turret on the picked cell **with no hit roll**. Valid targets are `compute_turret_damage_targets` → `SimulationCore.outermost_enemy_turrets(team)`: only **the first living enemy turret met when scanning each lane T1 → T2** (no sniping inner turrets; in a lane whose T1 has fallen, T2 inherits the spot so there is still somewhere to use it late game). Application reuses `SimulationCore.apply_card_turret_damage` → the battlefield's `_apply_card_damage` as-is, so the shake FX · kill log · `Building` node release · jungle gain on T1 destruction happen in one place only. **Doubled if unopposed**: if there is not a single enemy pilot on that lane's front line (전선) (`SimulationCore.front_line_cells` — between both teams' front-most turrets, the same set as the gold outline on screen), damage is doubled. The Herald (전령) is an event of pushing into a lane, so if an undefended lane and a lane held by five were worth the same, "when and where to use it" would vanish. **Growth points (성장치) are split evenly among allies in that lane** (`_award_turret_damage_to_lane`; the right lane has two, sniper · supporter, so half each) — the Herald is a team reward with no caster, so the usual attribution path (`apply_card_turret_damage` → `score_turret_damage(attacker, …)`) reaches no one, and the ones who held that lane while pushing own the siege. Value per point is `SCORE_TURRET_FULL / TURRET_HP`, the same as a turret ground down on foot. **Player**: LOCATION mode. **AI**: random valid cell. |
| `discard_hand` | yes | First clause of 완벽한 마무리 — discard the whole hand. **Ignores** keep (보존). |
| `discard_hand_draw` | yes | 재고 — discard the whole hand and draw again **as many as were discarded**. Hand size stays the same, only its contents change (if deck + discard run dry, only as many as could be drawn). |
| `discard_right:N` | yes | 과감한 정리 — discard N cards from the **right** of the hand (the most recently entered side). `hand.pop_back()` × N. |
| `discard_other_pilots\|strategy_each:M` | yes | 솔로 퍼포먼스 — discards every hand card with `owner_pilot != caster` and gives +M strategy points per card. With no caster it cannot tell "own cards", so it does nothing (prevents wiping the whole hand by accident). |
| `preserve:N` | yes | 계획 중시 — **Player**: `CardSelectOverlay.start_preserve` — like discard, drag N cards from the hand onto the central zone to pick them (on confirm the picked cards return to their original hand slots). **AI**: random N cards from hand. Picks go onto `BattleSim.preserved_cards_p/ai` and are protected only from `_trim_hand_overflow` — forced discards ignore it. Cleared entirely on entering the next operation phase. |
| `strategy_next_phase:N` | yes | Back clause of 아드레날린 (cost 0, front clause `strategy:N`) — `_bs.next_phase_strategy_p/ai += N` (may be negative). Settled on entering the next operation phase; points don't drop below 0. |
| `end_phase` | yes | Last clause of 완벽한 마무리 — **does not close the phase here.** While the chain runs the card floats outside the hand, so closing now would shut the door before exhaust / discard routing. It only sets the `_end_phase_requested` flag, and **Player**: the tail of `_finalize_pending_play`, **AI**: `AiCardPlayer`'s play loop (**after** waiting for the engage arena) picks it up via `consume_end_phase_request()`. |
| `move\|own_jungle` | yes | 정글 파밍 — `compute_valid_location_targets` branches to `compute_own_jungle_targets` and narrows valid cells to **jungle cells owned by the caster's team**. As with 약탈, `cast_range` (unlimited) is ignored — bounded by range, camps on the far side of the jungle would never be reachable. The cell it stands on is excluded. The ownership check reads `neutral_zone_cells` directly, so cells the jungler captured by stepping on them and cells handed over as a T1-destruction reward become targets right away. **AI**: `_ai_pick_target` uses the same function, so it follows along. |
| `phase_b` | yes | Back clause of [단계 B] — **the result of the immediately preceding `engage` clause** decides the next card. If the caster downed an enemy, [단계 C] (Phase C) (id 40) goes into the deck, otherwise [단계 A] (Phase A) (id 38). The kill count is answered by `EngagePhaseManager.last_engage_kills` (it runs after the stage is cleared, so it reads the copy `_last_stats`, not `_sim`). If a boon [베타] (Beta) reservation exists it is consumed here for its token bonus (`PHASE_BOON_BETA_CHARGE`). |
| `phase_c` | yes | Back clause of [단계 C] — **pick 1 of 3 boons**. **Player**: `_process_pending_chain` intercepts this clause and spreads three boon cards with `CardSelectOverlay.start_choice` (same grid as search, **no cancel** — the card has already gone out and the earlier clauses have already run). **AI**: `_effect_phase_c_auto` picks at random. Both paths converge on the single function `register_phase_boon`. The boon [감마] (Gamma) settlement happens **before picking the new boon** — reverse the order and the 감마 just picked would feed back on the spot. |
| `token:N` | yes | N tokens on the card currently resolving ([골드러시]). It is not a Charge card, so they don't disappear on use. |
| `atk_pct:N` | yes | Caster attack multiplier **permanent** +N% (`bonus_atk_mult`, cumulative) — 몰입 · 워밍업. Ledger kind `FX_ATK_PCT`. |
| `hp_pct:N` | yes | Caster max HP (체력) multiplier **permanent** +N% (`bonus_max_hp_mult`, cumulative) — 워밍업. `refresh_growth_stats` multiplies it into growth HP, and current HP rises by the increase. Ledger kind `FX_HP_PCT`. |
| `eva_buff:N\|turns:T` | yes | 소극적인 태세 — N% multiplier on the caster's **battlefield evasion** only (`eva_card_mod`, expiry `eva_card_expire_turn`). `roll_hit` multiplies it into the defender's evasion. Overwrites. |
| `retreat_turret` | yes | 소극적인 태세 — caster moves to the **nearest allied turret** cell. A living turret in its own lane first, else another lane, else base. Blocked by position-lock skills. |
| `ambush` | yes | 매복 — LOCATION (`compute_ambush_targets`: jungle tiles in range). Move + `ambush_hold`. See the *Pilot card additions* section above. |
| `ambush_search:N` | yes | Back clause of 매복 — reserves a search for N of the caster's engage cards on entering the next operation phase (`BattleSim.ambush_search_p/ai`). |
| `retaliate:N` | yes | 무모한 돌격 — the designated enemy hits the caster **N times**. Each rolls the battlefield hit roll (unlike 주먹다짐 (Brawl)'s sure-hit counter). The preceding `attack:N` is one N× damage hit as usual. |
| `draw_next_phase:N` | yes | 준비 태세 — draw N on entering the next operation phase (`BattleSim.next_phase_draw_p/ai`). The accompanying `strategy_next_phase:N` uses the same ledger as 아드레날린's back clause. |
| `free_in_phase` | yes | **Marker** of 신중한 예산 — nothing happens when played; the enter-hand hook reads it. |
| `hand_passive:<key>` | yes | Hand-resident marker — `gold_rush` / `confidence` / `clear_mind` (pilot cards, read by this manager) and `cash` / `revelation` / `contempt` / `balance` (mech cards, `MechSkillSystem`). 골드러시 is a playable card, so `token` · `self_cost` follow this clause. |

#### Persistent-effect ledger (`PilotData.persistent_fx`)
The four clauses `growth_perm` / `growth_eff` / `max_hp` / `atk_add` add their values onto **total slots**
(`growth_rate_bonus` / `bonus_max_hp` / `bonus_atk_flat`) —
because the growth recalculation (`BattleSim.refresh_growth_stats`) must read from one place
only. But then, if the detail panel read only that number, [용 보상] and [핫핸드] would be lumped into one cell
showing only their summed value, and what had already been eaten would vanish from that one cell.

So **right after** pushing the value, the four clauses write one more line into the ledger with
`_log_persistent_fx(target, kind, amount)`. The source is the card resolving at that moment (`_current_card.card_name`), so
no clause function has to drag the name along as an argument, and entries are
merged by `(card, kind)`, so using the same card twice grows the value on one line.

**The total slots do the computing; only the display reads the ledger.** Shares not in the ledger (mech passives
that push `bonus_*` directly — 영혼 수확 (Soul Harvest) · 조준 보정 (Aim Assist) …) get their own cell in the detail panel as the
**remainder** = total minus ledger — detailed display rules in the `ui/README.md`
"Lasting effect thumbnails" section.

#### Effective cost & affordability
`BattleSim.effective_cost_for(cd, is_player)` is the single source of truth
for "what does this card cost right now?". It applies `phase_cost_inc_*`
(additive) and the one-shot `engage_discount_*` (only when the card has
an `engage` clause), clamped at 0. The affordability highlight in
`highlight_affordable_cards`, the drop gate (`card_is_playable` →
`set_play_allowed`), the cost subtraction in `_play_card_direct`, and
`AiCardPlayer.run_ai_plays` all consult this helper so the four cost-modifier
effects stay in sync.

The `first_card_cost` manager trait (player only) also lives here:
`TraitHooks.first_card_cost_delta(is_player)` is added before the 0 clamp while
`TraitHooks.first_card_used` is false. `_play_card_direct` sets it after paying
(`on_player_card_paid`) and stores the old value in the snapshot as
`trait_first_used`, so `_restore_from_snapshot` (every cancel path) gives the
discount back. `start_card_phase` **and** `end_card_phase` reset it — so during
BATTLE the hand already shows the next phase's first-card price and the
turn-ready check agrees with it.

### Exhaust (소멸) / reposition (재배치) routing
`_dispose_used_card(cd, is_player)` runs after every play and routes the card
three ways, **reposition first**:
- `cd.is_reposition_card()` (`reposition` keyword, **재배치**) → back to the
  **leftmost slot of the hand** (정밀 이동 · 골드러시). Never reaches the discard
  pile and is never 소멸.
- `cd.has_keyword("exhaust")` → removed permanently (소멸). **Use the helper,
  not a string comparison** — `keyword` can carry several values joined with `|`.
- anything else → `send_to_discard(cd, discard)` (below)

`_dispose_used_card` is also **the only signal that a card was actually played**
— the pilot skill `on_card_played` hook (퍼포먼스 (Performance)'s tokens) hangs off it. Every path
that leaves the hand passes through this function, so player cards and AI cards are counted
on the same beat.

#### Volatile (휘발성, `volatile`) — the only exit for discards
Every discarded card passes through the single **`send_to_discard(cd, discard)`** (over-cap
trimming · the 버리기:N modal · 재고 · 완벽한 마무리 · 과감한 정리 · 솔로 퍼포먼스 ·
`_dispose_used_card`, seven call sites). A card carrying `KW_VOLATILE` doesn't land on the pile but
**vanishes on the spot**, and the function returns `false`.

**Exhaust and volatile are different things.** Exhaust vanishes **when used**; volatile vanishes **when
discarded without being used**. Cards that pilot skills create in the hand (이동 · 복귀 · 교전
개시 · 아드레날린 · 약탈) carry both, so a skill grants a card **without
bloating the deck** — see `../skill/README.md`.

Callers only remove the card from the hand and pass it to this function. Removing the card node
(`_despawn_player_card_node`) is needed either way, so it is not done here.

#### Reposition (`reposition` keyword — move to the leftmost slot of the hand)
`_return_card_to_hand_left(cd, is_player)`:

- **Cost is not raised here.** The same card's `self_cost:N` clause already raised that
  copy's `cost` inside the chain. `cd` is the caster-only copy that `build_starter_decks` cut with `make_card_copy`,
  so the increase stays on that one card only and **accumulates on every use**
  (정밀 이동 · 골드러시 each climb by their `self_cost` N per play).
- It passes through the enter-hand hook (`_on_enter_hand`).
- Player side: `player_hand.insert(0, cd)` + `spawn_card_node(cd, true)`.
  The `at_left` flag puts the node at the **head** of `player_card_nodes`;
  `relayout_hand` derives every slot from the array index, so that one flag is
  the whole "맨 왼쪽" (leftmost) rule. The two arrays must be inserted at the same end.
- AI side: `ai_hand.insert(0, cd)` + `HudBuilder.update_ai_hand_visuals()`.
- **No `MAX_HAND_SIZE` guard.** The card left the hand and came back, so the
  hand can't grow past where it started.
- The returned card sits at index 0, which is exactly where `_trim_hand_overflow`
  pops from — so once its accumulated cost makes it dead weight, the first
  BATTLE auto-draw that overfills the hand discards it.

> **A playable reposition card must get more expensive on every use (`self_cost`).**
> `AiCardPlayer.run_ai_plays` loops while it can afford *something* in
> `ai_hand`; a card that returns to hand at an unchanged cost would never leave the
> affordable set and the loop would never terminate. Keep that property if
> another card ever takes the keyword.

> **`uses` no longer decides anything.** The rule used to be "`uses > 0` →
> decrement `remaining_uses`, remove at 0", but the `uses` values in `cards.csv`
> let **every** non-exhaust card be played only once, so a single play destroyed it — 전투 개시
> included. The deck never cycled: it only shrank, the discard pile only ever
> filled from 버리기 clauses, and the reshuffle path in `draw_card` was
> effectively dead. `CardData.remaining_uses` is gone; the `uses` column is
> still loaded and copied (it stays available for a future "N charges then
> 소멸" mechanic) but nothing reads it.

Note that the five `exhaust` cards (조정 / 임기응변 / 재빠른 사고 / 집중 /
아드레날린) carry a larger `uses` value in the CSV. That has never meant anything — the
keyword check has always fired first, so they are 소멸 on their first play.

### Attack hit FX (`attack:N`)
Playing an attack card makes things happen **on both portraits (초상) at once** — white light rises from the
caster (시전자) portrait, and on the target's portrait fragments scatter in every direction while the portrait
shakes violently. One strike is two beats:

| Beat | Owner | Time |
|---|---|---|
| Cast (light) | `BattleSim.anim_pilot_cast(caster)` | `ANIM_CAST_DUR` **0.12s** |
| Hit (fragments + shake + popup) | `BattleSim.anim_pilot_impact(target)` + `_effect_attack` | `ANIM_HIT_HOLD_SEC` **0.20s** |

- **The total FX time of one strike is the sum of the two, 0.32s** — tuned to the same length as the lunge
  era, so a full chain of repeated attacks (`repeat`, capped at `MAX_ATTACK_REPEATS` ← const.csv `CARD_MAX_ATTACK_REPEATS`) still takes as long as it used to.
  **When touching either value, also adjust so `DMG_POPUP_DUR` (0.30) stays shorter than the sum** —
  otherwise the numbers of consecutive hits stack on the same spot (popup coordinates are fixed at the
  moment the popup spawns).
- **The cast light runs first, regardless of hit or miss.** A missed attack was still fired, and
  the `MISS` popup appears in the next slot (a missed strike has no fragments, only the hold).
- **The shake on the receiving side is far more violent than in battlefield (전장) engage (교전)** —
  `_apply_attack_damage` passes `ANIM_SHAKE_CARD_DUR` (0.26s) /
  `ANIM_SHAKE_CARD_AMP_PX` (20px) to `anim_pilot_shake` (battlefield default is 0.18s / 6px). Unlike engage
  damage, which goes back and forth automatically every turn (턴), a card hit is a single blow the player just chose,
  so shaking it at the same strength reads as if the card did nothing. The strength is
  carried by `PilotData.anim_shake_amp`, and the oscillation count grows with the duration
  (fixed frequency) — details in `rendering/README.md`.
- **Only the shake lives inside `_apply_attack_damage`.** The fragments (`spawn_pilot_burst`) are
  spawned by `_effect_attack` — the former is the **same damage entry point** as battlefield auto engage and
  pilot (파일럿) skill blows, so spawning fragments there would attach particles to damage that isn't
  from a card. If damage that runs every turn also spawned fragments, they would simply become the background.
- **Turrets (포탑) get no fragments.** `_impact_anchor` returns null for `TurretData`, and
  `anim_pilot_impact` keeps only the hold — turrets have their own hit FX
  (`BattleSim.anim_turret_hit`, shake + red flash).
- **Repeated attacks (`repeat`) repeat the two beats per hit.** 1 hit 0.32s, 2 hits
  0.64s, and so on up to the `MAX_ATTACK_REPEATS` cap. Since popups no longer overlap, `DMG_POPUP_STAGGER` is
  used only when no FX is attached (legacy cards with no caster).
- **The next card can only be played after the FX finishes.** `_attack_anim_active` is wired into both
  `_is_player_input_blocked()` (hand (손패) dim + click block) and `can_end_card_phase()`
  (turn-pass lock). `_set_attack_anim_active` calls `_apply_hand_dim_state()` + `hud.update_hud()` on both
  edges to wake up the state already shown
  on screen.
- **The AI uses the same FX.** So the single `await` in `_effect_attack` turns
  `_apply_single_effect` → `_process_pending_chain` / `apply_card_effect` →
  `apply_and_dispose_ai_card` → `AiCardPlayer.run_ai_plays` into a chain of coroutines.
  In all four, the call is either the last statement or received with `await`, so the order never
  goes out of sync. Clauses with no FX return their value on the spot, so no wait is attached.
- `_process_pending_chain` re-checks `_pending_play.is_empty()` after the await
  — a cancel path may have cleared the board while the FX was running.
- Death / return-to-base (복귀) / revive clear the cast light with `anim_pilot_cast_clear` —
  light left over a corpse reads as still firing something.
- Renderer-side wiring is in `rendering/README.md` — `_draw_pilot_cast_fx` (light pillar) and
  `_draw_pilot_bursts` (fragments).

#### The old **lunge (돌진, body slam)** — do not revive
It was three beats: the caster portrait **actually dove into** the target portrait (`ANIM_LUNGE_IN_DUR`) and came
back floating (`ANIM_LUNGE_OUT_DUR`). Because the FX moved the portrait, it needed three
supporting mechanisms, all of which are now deleted:

- **Direction calculation** — the distance had to be measured using the drawn markers from
  `BattleRenderer.pilot_marker_positions()`. Measuring from tile centres made the direction fully
  reversed when lunging at an enemy (적) in the same cell (markers are pushed up for enemies / down for allies (아군)).
- **Draw order** — `BattleRenderer._lunging_cells_last` had to defer the lunging cell to the very
  end. Otherwise the diving face would hide behind the target cell.
- **Displacement cleanup** — `anim_pilot_lunge_clear` on every death / return-to-base / revive.

Now both portraits stay in place with only effects layered on top, so none of the three is needed.
Deleted names: `BattleSim.anim_pilot_lunge` / `anim_pilot_lunge_return` /
`anim_pilot_lunge_clear` / `pilot_lunge_offset`, `ANIM_LUNGE_IN_DUR` /
`ANIM_LUNGE_OUT_DUR` / `ANIM_LUNGE_HOP_PX` / `ANIM_LUNGE_OVERLAP`,
`PilotData.anim_lunge_phase` / `anim_lunge_t` / `anim_lunge_dur` /
`anim_lunge_vec`, `BattleRenderer._lunging_cells_last`,
`CardPhaseManager._lunge_anchor` (→ only the name survives, as `_impact_anchor`).

### Targeting (CardTargetingOverlay)
- `CardTargetingOverlay.gd` — sibling of `CardPhaseManager`. **It owns no nodes
  at all now.** It used to hold a CanvasLayer at layer 11 for the PREVIEW left/right
  team panels; those moved to the post-submit VS screen (`engage/EngageIntro.gd`),
  and the 확인 / 취소 (Confirm / Cancel) buttons had already gone, so the layer went with them. What is
  left is pure state that `BattleRenderer` reads.
- **There is no modal step any more.** `Mode` is now just "what kind of card is
  being dragged": `NONE / INSTANT / PILOT / LOCATION / PREVIEW`. One entry
  point, `start_card_selection(cd, on_confirm)`, is called from
  `CardPhaseManager._begin_drag` the moment a card leaves the row;
  `clear_selection()` runs from `_end_drag` / `deselect_current_card`. The
  targeting state therefore lives exactly as long as the drag does — 턴 넘기기 (End turn)
  stays live, and `_is_player_input_blocked()` / `can_end_card_phase()` never
  consult this overlay.
- **The 확인 / 취소 buttons are deleted — the only way to play a card is drag and drop.**
  There used to be a two-beat path — (1) tap a target to set `pending_pick`, (2) press Confirm at the bottom right
  to commit — existing **alongside** the drag; it was just a second control doing the same
  thing, and it permanently occupied a button row at the bottom of the screen. Now:
  - **Dropping** the card onto a target (or onto the drop zone for a targetless card) is the only commit.
  - **Missed drop = cancel** — the card returns to its slot and the overlay turns off.
  - Deleted: `_btn_confirm` / `_btn_cancel` / `_build_buttons` / `_make_btn` /
    `_btn_top_y` / `_on_confirm_pressed` / `_on_cancel_pressed` /
    `_refresh_confirm_disabled` / `BTN_W` / `BTN_SIDE_MARGIN` /
    `CONFIRM_BTN_GAP`, and `CardPhaseManager._on_selection_cancel`.
    The `on_cancel` argument of `start_card_selection` disappeared too.
  - **Only `BTN_H` (56) / `BTN_HAND_GAP` (10) are kept.** `HudBuilder` uses these two to
    set the vertical position of the strategy point donut; if the donut sat directly against the hand row it would overlap
    the top edge of the cards. What those values mean now is not a button but an **empty band**.
- **Nothing is spent until the drop.** Cost deduction, card destruction and the
  effect chain all happen in `_play_card_direct(card, pre_target)`, which the
  overlay's confirm callback (`_on_selection_confirm`) invokes with the already
  resolved target. That removed the whole targeting-cancel refund path.
  (The snapshot/refund machinery still exists for 버리기 / 찾기 (discard / search) clauses, which
  mutate state mid-chain.)
- **Drop gating**: `set_play_allowed(bool)` carries
  `CardPhaseManager.card_is_playable(cd)` (cost + caster alive + valid target) into
  the overlay; `confirm_with(target)` refuses unless `_play_allowed` **and**
  `has_required_pick()`. `has_required_pick()` is true immediately for PREVIEW /
  INSTANT and only after `pending_pick` is set for PILOT / LOCATION.
  `highlight_affordable_cards()` → `_refresh_play_allowed()` re-pushes the
  verdict, so a caster killed by an engage earlier in the same phase makes the
  lifted card undroppable. `_on_selection_confirm` re-checks `card_is_playable`
  rather than trusting that gate.
- **Battlefield clicks are swallowed** in PILOT / LOCATION mode, and they do
  nothing else. `_unhandled_input` calls
  `get_viewport().set_input_as_handled()` unconditionally. This is now belt and
  braces rather than load-bearing: the targeting state only exists during a
  drag, and the hand hit layer holds the mouse for the whole gesture, so a stray
  battlefield press can't arrive mid-aim in the first place. It stays because
  the cost is one line and the failure it guards against (a press leaking into
  whatever else listens on unhandled input) is silent.
- **Pending pick** is now **drag-preview only**: while a drag is in flight,
  hovering a valid pilot or cell stores it via `preview_drag_target`, and
  `BattleRenderer._draw_pending_pick_highlight()` paints a cyan ring on that
  marker (or a thicker cyan outline on that cell) so the player can see what
  letting go would commit. The ring's radius follows the (animated) 1.5× target
  emphasis so it hugs the enlarged marker. Releasing without a valid pick drops
  it along with the drag.
- **Drop entry points** (the three public functions the drag uses): `hit_test_pilot_at(pos)` /
  `hit_test_cell_at(pos)` run the hit test matching the mode and return a value **only for a valid
  target**, and `confirm_with(target)` takes the commit path
  (`_play_allowed` gate → `_teardown` → confirm callback). On failure it returns false and
  the caller returns the card to the hand.
- **The caster (`card_caster`) is never dimmed in any mode.** It is filled in for every mode and
  that is its only job (the first line of `should_dim_pilot`) — dim means "you can't
  drop here", which makes no sense for the one firing the card, and under LOCATION's
  "dim every pilot" rule the very pilot about to move was the darkest thing on screen.
  **It is not an emphasis target either, though** — growing is the signal "you can drop here", so the
  caster grows via `valid_pilots` only when it is itself a valid target of that card (for
  `target=ally` cards like 보호 (Protect) / 복귀 (Return to Base) the distance is 0, so `compute_valid_pilot_targets`
  includes the caster itself).
- Driven by `CardData.cast_method` / `target` fields (see `targeting_kind`).
  **The display rule is just one: "only droppable places are lit"** — detailed table in
  `rendering/README.md` *Targeting dim + emphasis*:
  - `cast_method == "target"` (target=enemy/ally/pilot) → **PILOT** mode.
    **Tiles outside the caster's range are dimmed** (no dim when range is unlimited). `valid_pilots`
    stay bright, enlarged by `TARGET_EMPHASIS_SCALE` (**1.5**) (and a group in the same cell
    spreads left/right so they don't overlap), and the remaining pilots are
    dimmed per marker. The visible markers are the drop points.
    Range honours `cd.cast_range` and the `min_range:N` flag.
    `target=pilot` (매혹) accepts pilots of both teams (it used to catch allies only).
    **While a target is pointed at**, only the pilots that card's effect would reach (`pick_pilots`)
    stay enlarged and **bright** — the other valid targets shrink back to normal size and are
    **dimmed**. Tiles, too, light only the **effect area** instead of the range (`pick_bright_cells()` =
    `pick_cells` + the target cell; a single-target card with no area = the target cell alone); the rest
    is dimmed and the area cells are painted yellow. The pointed-at portrait (`picked_pilot()`) is redrawn
    **on top of the dim** (`BattleRenderer._pick_top`). Moving off restores every valid target's
    enlargement. Rule table: `rendering/README.md` *Targeting dim + emphasis*; area computation:
    `CardPhaseManager.compute_pick_affected`.
  - `cast_method == "location"` → **LOCATION** mode. Only `valid_cells` stay bright with a green
    fill + outline, **cells outside the range are dimmed**, and every pilot **except the caster and
    (for `foe` cards) the enemies on valid cells** is dimmed — on a `foe` card those enemies grow like a
    PILOT card's valid targets.
  - **`cast_range ≥ CardTargetingOverlay.UNLIMITED_RANGE` (99) = range ignored**
    (복귀 / 보호 / 약탈 (Plunder) / 정글 파밍 (Jungle Farming) / 강습). `range_unlimited` → `is_in_range_cell`
    is true for every cell, so there is no tile dim.
  - `cast_method == "range" and target == "caster"` → **PREVIEW** mode
    (engage cards only; 전진 (Advance) is target=enemy, so it fires immediately instead of PREVIEW).
    The cells within the engage radius (`compute_engage_area` with `engage_radius(cd)` = the engage
    clause's `self_range`, default 1) show a soft yellow fill with full outline
    and the participants inside it are emphasised; cells outside the engage area
    get the black out-of-range dim. There is no separate target to pick, so dropping it on the **screen-centre
    drop zone** sends it out immediately → `_play_card_direct(card, null)`.
    > **The participant roster is not here.** When a card was picked, two vertical
    > team panels used to pop up on the screen's left/right listing the participating pilots. Now that roster is shown
    > **after the card is submitted** by the VS screen in `engage/EngageIntro.gd` — the reason is in
    > the *Opening confirmation screen* (개시 확인 화면) section of `engage/README.md`.
  - anything else → **INSTANT**. No caster, no range, nothing painted on the
    battlefield (`is_visualizing()` is false, so BattleRenderer skips the dim
    entirely); the card is dropped on the drop zone rect, which is not drawn.
- Hit-testing:
  - **PILOT mode** uses `_hit_test_pilot`, which aims at the pilot's **drawn**
    marker: it reads `BattleRenderer.pilot_marker_positions()` — a fresh run of
    the same per-cell stack solve `_draw()` uses — and picks the valid pilot
    whose marker is closest to the drop point, within `hex_size * 0.85`. A drop
    that lands on no marker but inside a pilot's own tile still resolves, ranked
    by marker distance, so releasing over the tile itself keeps working.
    (`hit_test_pilot_at` / `hit_test_cell_at` are its only consumers — the battlefield
    click path is gone.)
    > This is the fix for a real bug. The probes used to be the tile centre and
    > `BattleSim.pilot_marker_pos_solo`, both of which depend only on
    > `grid_pos` — so every pilot sharing a cell had the *same* probe point and
    > the first one in `valid_pilots` (the leftmost drawn portrait) won every
    > click, whichever face the player tapped. Now every renderable pilot
    > gets a slot, so the fallback (`pilot_marker_pos_solo` → the renderer's
    > `pilot_marker_pos_fallback`) is effectively never hit.
  - **LOCATION mode checks portraits first, then the cell.** `hit_test_cell_at`
    runs the same marker probe (`_hit_test_marker`, no tile fallback) over
    `_location_marker_candidates()` — for `foe` cards (적 또는 포탑) only the
    enemies on valid cells (`target_pilots`), for other location cards anyone
    alive on a valid cell — and a hit resolves to **that pilot's `grid_pos`**.
    Only on a miss does the cell-centred `_hit_test_cell` run (turrets, empty
    cells). Portraits float above (team 1) / below (team 0) their tile and
    spread further when emphasised, so the old cell-only probe made 천공의 일격 ·
    로켓 펀치 · 일격 miss when dropped on the enemy's face — you had to aim at the
    tile underneath. The PICK_STICKY_SCALE hysteresis also covers this path via
    `_marker_pick` (the pilot whose portrait produced the held cell).
- The strategy point donut is **no longer locked** while a card is selected — with
  the modal gone there is nothing to protect: 턴 넘기기 during a selection just
  ends the phase, and `end_card_phase` opens with `deselect_current_card()`
  which tears the overlay down.

### AI card play animation (AiCardPlayer)
- `AiCardPlayer.gd` — sibling of `CardPhaseManager`, runs the AI's hand
  one card at a time inside `_run_ai_turn()`'s `await` chain.
- Each play pops the rightmost card-back from the AI hand peek
  (`HudBuilder.pop_ai_hand_card_node()`), reparents it onto `_bs.canvas`
  preserving world position+scale, then tweens it from the hand row to
  viewport centre (`540, 760`) over `FLY_FROM_HAND_SEC` while still
  showing the back. A snap-flip (`scale.x → 0` then `→ SCALE_BIG`) swaps
  to the played card's face via `setup(cd, false, true)`. Holds for
  `SHOW_DURATION_SEC`, fades + scales back out, queue_free.
- When the AI hand peek is empty (rare — stray plays after wholesale
  hand wipes), it falls back to the legacy "spawn fresh card at centre"
  fade-in animation.
- After the visual completes, `apply_and_dispose_ai_card(pick)` runs the
  effect chain. `engage` / `duel` cards route through
  `EngagePhaseManager.start_engage()` / `start_duel()`; the loop gates on
  `engage_phase.is_active()` (not on the effect chain, so 결투 (Duel) is covered
  too) and `await`s the `engage_finished` signal so the arena fully
  resolves before the next AI play starts.
- The loop then checks `card_phase.consume_end_phase_request()` and breaks if
  the card carried `end_phase` (완벽한 마무리 (Perfect Finish)). The check sits **after** the
  arena await on purpose — breaking first would close 상대 차례 (Opponent's turn) with the
  engage the card just opened still on screen.
- **Card selection is not random but priority-scored** (`_pick_best_card` /
  `_score_card`). The goal is not a strong AI but an AI that **visibly spins its wheels less** —
  attack cards with no enemy in range, or heals cast on full-HP allies, used to pop out at random,
  turning the opponent's turn into a stretch where only the centre animation ran and nothing
  happened. There are four rules.
  - **Exclude if unplayable** — `CardPhaseManager.ai_can_play` checks affordability ·
    caster alive · `CardData.is_playable()` together. The last one is new:
    `effective_cost_for` doesn't clamp results below 0, so a **cost -1
    (unusable)** card read as "0 cost" — without that one line the AI just burns 캐시 (Cash) ·
    계시 (Revelation) · 약자 멸시 (Scorn the Weak) · 밸런스 (Balance). `_ai_turn_ready` reads the same
    function too (if only one side passes, you get a turn where only the banner shows and no card
    goes out).
  - **Exclude if there is no target to pick** — if `card_needs_target` is true but
    `ai_target_for` is null, the card drops out of the candidates.
  - **Clause names set the score** (`CLAUSE_WEIGHT`). If one card carries several clauses,
    **the highest clause** is that card's character — 간보기 (Probe) is
    `attack;on_hit;engage;on_miss;strategy`, but what that card does is attack, not
    strategy points. Heal · shield cards have `_support_bias` look at the situation:
    if the most-wounded ally is above `SUPPORT_HP_RATIO`, it is pushed back by
    `SUPPORT_IDLE_PENALTY` (not blocked — it might be the only thing in hand).
  - **Cost is a penalty, ties are broken by jitter** — `COST_PENALTY` (per point) plays cheap
    cards first so more cards go out per turn, and without `JITTER`
    the same hand would go out in the same order every time and the opponent's turn would read as mechanical.
  All of these (`CLAUSE_WEIGHT_DEFAULT` · `SUPPORT_HP_RATIO` · `SUPPORT_IDLE_PENALTY` · `COST_PENALTY` · `JITTER`)
  now live in const.csv under `AI_CARD_<name>`.
- **`MAX_PLAYS_PER_TURN`** (const.csv `AI_CARD_MAX_PLAYS_PER_TURN`) caps one AI turn. The loop's real exit is "no
  playable card left", but a card that costs nothing and *rotates* the hand
  can defer that forever — 재고 (Reconsider) (free, discards the whole hand and draws the same
  number back) re-draws itself until deck + discard run dry. The cap is a structural
  backstop, not a balance knob; a normal hand never reaches it.
- `_ai_play_in_progress` blocks re-entry of `_run_ai_turn`, holds the BATTLE
  auto-tick (via `is_ai_turn_active()`) and disables the donut's 턴 넘기기
  face (via `can_end_card_phase`). It also gates `_grabbable_card_at` /
  `_begin_drag` / `on_card_hovered` so the player can't grab a card or pop the
  description box mid-AI animation.

### Discard (버리기) / search (찾기) / keep (보존) / 3-way boon pick (강화 3택) modal pick (player only)
- `CardSelectOverlay.gd` (sibling of `CardPhaseManager`, instantiated from
  `BattleSim._ready` once the HUD canvas exists). Owns one
  `CanvasLayer` (`layer = 10`) and rebuilds its UI on every `start_*()`.
  AI plays bypass this overlay and keep the synchronous `apply_card_effect`
  path (random discard, search aliased to draw, 강화 3택 picked at random).
- **`Mode.CHOICE` — 강화 3택 (phase C / 단계 C).** This mode picks **an option**,
  not a card. The grid and the pick rules are the same as SEARCH; only three things differ.
  - What it lays out is not a pile but **display-only cards built by the caller**
    (`CardPhaseManager.build_phase_boon_cards` — their cost is -1, so the cost slot shows
    `—` instead of a number: these are options to choose, not cards to play). The chosen card
    goes into no pile; all that remains is the reservation carried over by reading
    `phase_boon:<key>`.
  - **No sorting by name** (`_build_search_grid(source, false)`) — 알파 (Alpha) ·
    베타 (Beta) · 감마 (Gamma) is an ordered list; re-sorting by name would give 감마 ·
    베타 · 알파, out of step with the order in the card's description text.
  - **No cancel button** — by this point the card has already been played and the earlier
    clause (`gen_deck:38`) has already run. No cancel is offered when there is nowhere to go back to.
- **Async chain pattern** in `CardPhaseManager._play_card_direct`:
  1. Snapshot `player_hand` / `player_deck` / `player_discard` /
     `player_cost` BEFORE deducting cost or removing the played card. Stored
     on `_pending_play.snapshot`.
  2. `_process_pending_chain()` walks `_pending_play.clauses` via
     `pop_front`. Synchronous clauses dispatch through `_apply_single_effect`
     and append a log line. `discard:N` / `search:N` / `preserve:N` parks the
     remaining clauses on `_pending_play` and starts the overlay, returning
     early.
  3. The overlay's complete callback (`_on_discard_overlay_complete` /
     `_on_search_overlay_complete` / `_on_preserve_overlay_complete`) writes
     the picks to the discard pile, the hand, or the preserve list
     respectively, then calls `_process_pending_chain()` again to continue the
     chain.
  4. When the chain drains, `_finalize_pending_play()` disposes the played
     card (use count (사용 횟수) / exhaust (소멸) routing) and writes the combined log line.
- **Cancel = full refund** (`_on_overlay_cancel` → `_restore_from_snapshot`):
  drops any in-flight drag, frees every player card node, restores
  hand/deck/discard/cost from the snapshot verbatim, and respawns nodes for
  every CardData now back in `player_hand`. This rolls back even prior
  clauses in a chain (e.g. cancelling 교환 (Exchange) returns the drawn cards to the
  deck along with refunding the 교환 card itself). The snapshot also carries
  `engage_discount_p` and the **preserve list**, and the restore clears any
  `end_phase` request the cancelled card had raised.
- **Discard mode UI** (`Mode.DISCARD`):
  - **Battle dim** = `ColorRect` covering y=0..BS_HAND_CENTER.y, parented
    into `_bs.canvas` and moved to child position 0 so HUD + hand still
    draw on top of it.
  - **The pick is a drag.** The hand stays live; dragging a card into the **centre zone**
    and dropping it moves that card to the to-discard set
    (`CardPhaseManager._try_drop_play` → `add_card_to_discard`). The zone is
    **the same `drop_zone_rect()` as when playing a card**; only the caption changes, to "여기에 놓아 버리기" (Drop here to discard).
    The targeting overlay never turns on in this mode at all.
    > It used to be two beats: **select** a card, then press the "버리기" (Discard) button that
    > appeared in the description box. Once the selection state itself was removed (see the
    > *Drag and drop* section above) that button had nowhere to live, and every action that
    > takes a card out of the hand was unified into a single drag.
  - Picked cards are laid out in a centered fan (`to_discard_center_y()` =
    the shared drop zone's centre, fan width = `BS_HAND_WIDTH`, same spacing
    rules as the hand row).
  - **Pressing a picked card returns it to the hand** (`remove_card_from_discard`).
    The card itself doesn't take the mouse, same as in the hand (`MOUSE_FILTER_IGNORE`),
    so one transparent `Button` (`UnpickHit`) is laid over the card to catch the click — the
    same trick the search grid uses. It returns to **the index it left from**
    (`_to_discard_slots`): appending it instead would teleport an un-picked card to the right
    end of the hand, reading as "newly drawn" rather than "undone". The button is detached with
    **`remove_child` before `queue_free`** — otherwise the button lingers until the end of that
    frame and the un-pick runs once more on a node already removed from the list.
    > There used to be no way to undo a pick (it was nailed down with `mouse_filter = IGNORE`),
      so a wrongly picked card had to be carried all the way to the confirm button.
  - **No auto-commit and no cancel (of the card itself).** A 버리기:N card is
    non-cancellable:
    the only top-right button is **확인** (Confirm), disabled until exactly
    `target_count` cards are in the to-discard fan. `target_count` is
    clamped to `min(N, hand.size())`. Pressing 확인 is the sole exit.
  - Bottom-left **숨김** (Hide) (toggles `hidden_state`; relabels to **표시** (Show) while
    hidden, drops any in-flight drag on press) is still available so the player
    can peek at the battle before committing.
- **Search mode UI** (`Mode.SEARCH`):
  - **Full dim** covers the whole viewport on the high-priority overlay
    layer, dimming both battle and hand.
  - `ScrollContainer` at (`SEARCH_GRID_SIDE_PAD`, 220) holds a 5-column
    layout of all `player_deck` cards, **sorted by card name** via
    `_sorted_for_display()` (ties broken by cost) — the live `player_deck`
    order is the draw order, and laying the grid out in it would turn the
    tutor screen into a "what comes next" table. The sort runs on a duplicate;
    picks are `CardData` references, so display order never affects the commit
    (`_on_search_overlay_complete` erases by identity). `CardPileViewer` sorts
    the same way. Cards are spawned with
    `is_player_card=false` so `Card._on_mouse_entered` short-circuits and
    its hover-brighten tween doesn't fight the `SELECTED_TINT` modulate; a
    transparent flat `Button` child captures clicks ahead of `Card._gui_input`.
  - Bottom-left **숨김**, bottom-right **찾기 취소** (Cancel search), **확인** to its left.
    확인 stays disabled until exactly `target_count` cards are selected
    (`target_count = min(N, deck.size())`); on commit, picks move from
    `player_deck` to `player_hand` (capped at `MAX_HAND_SIZE`) and visual
    nodes spawn via `spawn_card_node`.
- **Preserve mode UI** (`Mode.PRESERVE`, 계획 중시 (Prioritize the Plan) · the 계략 (Scheme) skill): **the same
  hand pick as discard** (`is_hand_pick_mode()` = DISCARD or PRESERVE). The hand stays live; dragging a
  card onto the central zone ("여기에 놓아 보존", Drop here to keep) moves it into the picked row
  (`add_card_to_pick`), and pressing it sends it back to its slot (`remove_card_from_pick`).
  Three differences from discard:
  - **확인** (Confirm) (`_commit_preserve`) puts the picked cards back into their original hand indices
    **in reverse pick order** (`_return_all_picks_to_hand`) and returns the picks — the keep mark is set
    by the callback (`_on_preserve_overlay_complete` / 계략's `_on_scheme_picked`).
  - There is a **보존 취소** (Cancel keep) button. It first returns the picked cards to the hand, then
    calls the cancel callback — 계략 has no snapshot restore, so without returning them `_teardown`
    would free the card nodes left in the row and those cards would vanish.
  - Cards with the `보존` keyword can be picked (only discard refuses them).
  > It used to spread the hand **as a second copy in the search grid** — picking from cards already in
  > hand covered the whole screen with another list. The grid (`_is_grid_mode()`) is now used only by
  > SEARCH · CHOICE.
- **Keep marker (보존 표시)**: `Card.set_preserved(true)` draws a cyan `PreserveMark` border
  (`draw_center = false`, so it doesn't darken the card). Driven from
  `highlight_affordable_cards`, which reads `_bs.preserved_cards_p`. It is
  deliberately *not* part of `_refresh_block_overlay`'s dim logic — keep (보존) is a
  guarantee, not a restriction, so the card stays bright. The cost badge sits
  **above** the border: `_build_block_overlay` reparents `CostBadge` out of
  `CardFront` to the root's last child, so the cyan stroke never covers the
  cost number. `_sync_face_visibility` toggles it together with `CardFront`.
- **Phase-end gate**: `can_end_card_phase()` returns false while
  `card_select_overlay.is_active()` so the player can't 턴 넘기기 (End turn) their
  way out of an unfinished pick.

### Deck / discard pile browse (CardPileViewer)
`CardPileViewer.gd` — sibling of `CardPhaseManager`, created in
`BattleSim._ready()` and owning a `CanvasLayer` at **layer 12** (above the
discard/search overlay's 10 and the targeting overlay's 11, so a list opened over
either of them covers both).

- **Entry point**: the two hand-row piles (뭉치). `HudBuilder._bind_hand_indicators`
  lays a transparent flat `Button` over each `CardPileStack`
  (`%DeckButton` · `%DiscardButton` in `ui/UI_View_BattleHud.tscn`, placed by `_place_pile_button`) — the pile sets itself to `MOUSE_FILTER_IGNORE` and
  can't take a click itself — and the press calls
  `CardPileViewer.open(Pile.DECK | Pile.DISCARD)`.
- **When it opens**: `CardPhaseManager.can_browse_piles()` — operation phase (작전 단계) only, and
  not while the turn banner, the AI's play loop, a discard/search overlay or the
  engage arena owns the screen. `HudBuilder._update_pile_buttons()` (called from
  `update_hud`) disables both buttons and dims both piles
  (`CardPileStack.set_dimmed(true)`) whenever the answer is no, so "you can't
  open this right now" is visible rather than a dead tap.
- **Contents**: the same 5-column `ScrollContainer` grid the search overlay uses,
  **sorted by card name** (`_sorted_cards()`, ties broken by cost) on a
  *duplicate* — the live pile order is never touched, and the deck's real draw
  order is never revealed. Cards are spawned `is_player_card = false` +
  `MOUSE_FILTER_IGNORE`: nothing in the list is selectable. An empty pile shows
  "비어 있음" (Empty) instead of a grid.
- **Exits**: the 닫기 (Close) button (same bottom-right band as 확인/취소 (Confirm/Cancel)) or a press
  anywhere on the dim.
- **What it locks while open.** Three gates read `is_active()`, because the
  overlay's dim alone is not enough:
  `_is_player_input_blocked()` (hand dims and stops taking clicks),
  `can_end_card_phase()` and `HudBuilder._update_cost_donuts`'s
  `set_flip_allowed` — `CostDonut` listens on `_input`, which runs **before**
  GUI picking, so a tap on the donut would otherwise flip and end the turn
  straight through the dim. `open()` / `close()` call
  `highlight_affordable_cards()` (which tail-calls `_apply_hand_dim_state()`)
  and `hud.update_hud()` so all three re-evaluate on both edges.
- Browse **cannot be opened during a drag** (the counter buttons sit beside the hand row, and the
  drag holds the pointer). Conversely, while it is open the hand input is blocked entirely
  (`_is_player_input_blocked`), so a drag never even starts. There used to be a rule that "a
  selected card stays selected while browsing"; it went away together with the selection
  state itself.

---

## Card grid scroll (search / discard / pile browse)

The scroll body `inner` of `CardSelectOverlay._build_search_grid` and `CardPileViewer._build_grid`
is **`MOUSE_FILTER_IGNORE`**, and the search grid's transparent
pick button (`hit` in `_attach_search_pick_overlay`) is **`MOUSE_FILTER_PASS`**.
If both were the default (STOP), the grid would not scroll on a phone — Godot's drag scroll
only starts when the mouse press emulated from touch bubbles up to the `ScrollContainer`,
and STOP cuts that propagation. The card nodes themselves were already IGNORE and were
fine; what blocked it was the two layers above/below them. On desktop the engine makes an
exception that lets the wheel pass through STOP, so this defect never shows. Rules and how to verify:
**`docs/mobile_safe_area.md` §5**.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Opening hand (none) | **Both teams start with an empty hand.** `build_starter_decks` ends by shuffling the deck and emptying the hand with `_clear_hands()`; the hand fills only through the BATTLE auto-draw, which runs from `ECONOMY_START_TURN` (game_config.csv) — every turn before it is a pure laning phase with no cards at all. It used to pre-deal `INITIAL_HAND_SIZE` (game_config) cards via `_deal_initial_hands()` so the first turn started with a hand full to the cap; that key and that function **have been deleted**. Measured: the first operation phase comes only after the gate opens and Blue's points climb from the head start to `PHASE_THRESHOLD`. |
| Opponent's turn (AI turn) | **Each team gets turns from its own operation points.** **The readiness check is now the same for both sides** — points must be above the threshold **and there must be at least one playable card in hand** (`_player_turn_ready` / `_ai_turn_ready`). It used to be that only the player entered on points alone: when all allies died, the whole hand was locked by caster death, yet the points still sat on the threshold, so every time the auto-draw changed the hand, "당신의 차례" (Your turn) just opened and closed (the only thing you could do on that turn was pass). Discarding over the hand cap still runs regardless of whose turn it is — cycling the deck is the purpose of that rule. `_player_turn_ready` asks `is_playable()` separately because `card_is_playable` only compares cost (cost -1 passes, since `-1 > player_cost` is false). The moment the player passes, **if the opponent is already above the threshold (+ holds a playable card), the opponent's turn starts right there** — without waiting for the next BATTLE tick, and regardless of my points (`_ai_turn_ready()` → `await _run_ai_turn()` at the end of `end_card_phase`). If the opponent is below the threshold, it goes straight back to BATTLE with no banner, as before. Otherwise the AI turn also fires on a BATTLE tick via `CardPhaseManager._run_ai_turn()` when `ai_cost ≥ PHASE_THRESHOLD` **and** a playable card is in hand, and the "상대 차례" (Opponent's turn) banner appears only then (it used to appear every time even when the opponent had 0 points and did nothing). **When both sides are ready at the same time, `_next_turn_side()` arbitrates — if nobody has taken a turn yet, blue; after that, it alternates to whichever side did not take the previous one.** This spot used to **always check the AI first** to prevent starvation (a player who played only free cards and passed would still be above the threshold on the next tick, re-enter their own phase, and could starve the AI forever); now that it is flipped to blue-first, the alternation rule provides that protection instead — the side that just took a turn cannot take another until the opponent has taken one. The opposite starvation (points full but no playable card, so only the banner pops every tick) is prevented by `_ai_turn_ready()` using **the same affordability filter** as `AiCardPlayer`. At the end of the AI turn, the same return-to-base sweep (`process_phase_end_recalls`) as the player turn also runs. |
| Stage chain (단계 A → B → C) | **The only place where one card decides its own next state.** It is the card set of Assassin P (Overdrive): [단계 A] (Stage A) puts [단계 B] (Stage B) into the deck, and the **result of the engage** that [단계 B] opens decides the next card — if it took down an enemy, [단계 C] (Stage C); otherwise [단계 A] again. **For that to work, the `engage` clause must wait until the stage closes**: that is why `CardPhaseManager._effect_engage` now awaits `engage_finished`, and the same change also fixes `gen_hand:19\|per_kill` of [우세한 전장] (Dominant Battlefield) ("교전에서 생존할 시 처치한 적 수만큼" — "if you survive the engage, as many as enemies killed") — previously both were settled before the first round even ran, i.e. at a point where the kill count was always 0. The engage scorecard must still answer after the stage is cleared, so it is kept as a copy in `EngagePhaseManager._last_stats` (`_sim` is discarded when the dashboard closes). [단계 C] offers a **choice of 3 boons** (Alpha = the next [단계 A] puts [단계 B] into the hand / Beta = +`PHASE_BOON_BETA_CHARGE` Charge on the next [단계 B] / Gamma = +`PHASE_BOON_GAMMA_RATE` growth points on the next [단계 C]; both in const.csv as `MECH_PHASE_BOON_*`); that reservation is one per pilot and is used **only on the next one**. The player picks with `CardSelectOverlay`'s `CHOICE` mode (same grid as search, **no name sort**, **no cancel** — the card has already been played) and the AI picks at random, but both converge on the single function `register_phase_boon` so the rules do not diverge. Gamma is settled **before picking the new boon** — if the order were reversed, the Gamma just picked would feed back on the spot. |
| Charge (`charge`) | **Charge (충전) is the keyword; what fills up is the token (토큰).** A Charge card gains 1 token (`CardData.charge`) **each time it enters the hand** (cap `charge_max`, same column in both CSVs); when used, all accumulated tokens are spent at once and it resets to 0. The only place it rises is the hand-entry hook `_on_enter_hand`; the only place it burns is `_burn_charge(cd)` (the burned count is `_charge_spent`). The effect-side flag is **`\|charge`** — used by 미사일 (Missile) · 전장 강타 (Battlefield Smash) · 성장 가속 (Growth Acceleration) (`growth:N\|turns:T\|charge`). On screen it is the `N/M` badge at the card's bottom right. Cards that use it — 미사일 · 전장 강타 · 약자 멸시 (Scorn the Weak) · 성장 가속, each capped by its own `charge_max`. 골드러시 (Gold Rush) is not a Charge card, but it stacks tokens with `token:N` and its badge shows only the count. The old `스택` (stack) has been deleted. |
| Attack order (created in hand on each kill) | **Not Charge — the card itself is created.** It is the card of Support-A (mech 18) and carries `trigger = death_hand`, so **whenever anyone falls**, ally or enemy, one copy is created in the hand of the pilot whose mech brings that card (`MechSkillSystem._grant_death_cards`). **Its target radius is `attack:N|around_target:N`** — every enemy within that radius of the chosen **ally**. Geometrically the same as `|area:N`, but the origin is an ally, not an enemy, so `_resolve_attack_victims` has a separate branch for it: without that branch, `picked` is an ally, so all of the base form's "the one chosen enemy" fallbacks failed the team check and only **one unrelated enemy** got hit. The check is `_owns_trigger_card`, which reads the allocation table (`starter_cards`), so the answer is the same whether the card is currently in hand, in a pile, or already exhausted — the hook is **a property of the mech**, not of where one card happens to be. It has `소멸` (exhaust), so it disappears when used; with no kills it does not even stay in the deck. It used to be a `death_stack` hook that **raised the stack of that card in hand**; when stacks became Charge, the rule was unified so Charge comes only from hand entry, and "a kill is an order" moved to granting a card. |
| Cost -1 (unplayable) | **A card that cannot be played.** Used by four cards that work just by being held in hand (캐시 (Cash) · 계시 (Revelation) · 약자 멸시 · 밸런스 (Balance)). The cost slot shows `—` instead of a number, `highlight_affordable_cards` locks it as unaffordable so the slab covers it, and `_begin_drag` refuses the drag itself — if you could drag out a card with nowhere to drop, all that remains is a pointless motion that snaps back every time. **But it can be dragged during a discard pick**: being unplayable does not mean it cannot be discarded. Do not confuse with 0 cost — 0 means it can be played for free; -1 means it cannot be played. **Cost -1 gets neither discounts nor surcharges**: `BattleSim.effective_cost_for` returns -1 as is (it used to pass through `max(0, …)` and become 0, so every place that did not check `is_playable()` read it as a "free card"), and `_effect_cost_reduce_hand` (사전 준비, Preparation) and `draw_card`'s focus discount also skip this card. The effect grammar is a single `hand_passive:<key>` line; the actual behaviour is read directly by `MechSkillSystem` scanning the hand (clauses run when the card **is played**, so they cannot carry it). |
| Keep keyword | A card with `보존` (Keep) (`preserve` in `keyword`) **is never hit by any discard** — not the automatic over-cap discard (`_trim_hand_overflow`), not the four forced discards (재고 (Reconsider) / 완벽한 마무리 (Perfect Finish) / 과감한 정리 (Bold Cleanup) / 솔로 퍼포먼스 (Solo Performance)), and not the discard:N modal. Every forced discard goes through `_discardable(hand)`; the modal rejects it in `add_card_to_discard` and sets `target_count` to **the number of discardable cards** (setting it to the hand size would make a modal whose confirm button is locked forever). It **differs in lifetime and in what it blocks** from 계획 중시 (Prioritize the Plan), which lasts one operation phase (`preserve:N` effect, `BattleSim.preserved_cards_*` lists) — that one blocks only the over-cap discard and is released at the next operation phase. The on-screen display (cyan outline) is the same for both: to the player, both kinds of keep mean one thing, "this card will not be discarded". |
| Operation phase (CARD_PHASE) | Triggered at `player_cost ≥ PHASE_THRESHOLD`. Operation points are read out on the 전략 포인트 (Strategy points) donut gauges — **both in the screen's left gutter** (player: top-left of the hand row = above the Deck counter; enemy: top-left = below the opponent hand peek). Tapping the player donut flips it into a circular 턴 넘기기 (End turn) button — **you can pass at any time, even without playing a single card** (it is locked only in states where closing now would cut something off, such as a banner / modal / charge animation). The rule changed twice: "you must spend at least 1 operation point" → a good share of the cards are free, so a hand of only free cards never reduced points and could never pass, so it became "play at least one card" (`cards_played_this_phase`); now even that has been removed — being above the threshold with nothing playable in hand is common, and forcing it makes you play any card as if discarding it. `cards_played_this_phase` and `_has_any_playable_card()` **were deleted** together. Tapping elsewhere flips it back. |
| The price of passing (excess burned · pass lock) | In exchange for being able to pass without playing a card, three rules apply (same for both teams). (1) **Excess over the threshold burns** — the moment you give up the turn, points are cut to exactly `PHASE_THRESHOLD` (game_config.csv) (at the end of `end_card_phase` / `_run_ai_turn`; the burned amount is logged). (2) **No recovery above the threshold** — `COST_RECOVERY` is applied **only to a side whose points are below** the threshold (`do_battle_turn`). Together these make the threshold the effective cap on strategy points, and points pushed above it by a card effect (아드레날린, Adrenaline) are also cut when you pass. (3) **Pass lock** (`CardPhaseManager._player_pass_lock`) — even right after passing, the points are still sitting on the threshold, so left alone **my turn would reopen on the next tick (0.5 s)**. So the side that passed counts as not ready in `_next_turn_side()` **until the auto-draw changes its hand or the opponent takes a turn once**. Meanwhile BATTLE runs as usual. |
| Card drag = targeting | **The moment you drag a card out is the targeting step** — a click alone does nothing (see the 'Card drag and drop' entry below). There is no "카드 내기" (Play card) button in the description box and no confirm / cancel buttons at the screen's bottom right — **the only way to play a card is drag and drop**, and as soon as the card leaves the hand, **every place it cannot be dropped is dimmed**. The dim rule depends on the mode: **PILOT dims all tiles** (tiles are not targets) and leaves only valid target pilots bright, **enlarged 1.5×** (`BattleRenderer.TARGET_EMPHASIS_SCALE`, lowered from the former 2.0 — 2× pushed groups off screen and faces spilled into the neighbouring lane), dimming the remaining pilots. **What grows is not just the portrait but the layout** — when two or three stand on one tile, the enlarged faces cover each other and cannot be aimed at, so `_build_pilot_render_layout` widens the **radius** of that tile's hex ring by the same factor — the ring definition (`지름 + 여백`, diameter + margin) is itself the non-overlap condition, so multiplying by the factor keeps the condition, and the arrows get longer by as much as the faces move away from the tile. **Slot assignment itself ignores the emphasis** (overlap is checked on pre-emphasis coordinates) — if it included the emphasis, the battlefield slots would be re-solved every time you pick up a card and the layout would look reshuffled wholesale. If a widened group goes off screen, `_clamp_group_on_screen` translates the whole tile to bring it on screen. The hit radius also comes from `BattleRenderer.pilot_marker_radius(p)`, so it covers the enlarged face outline. **Scaling up/down does not pop instantly; it is interpolated over `BattleRenderer.EMPHASIS_TWEEN_SEC` (**0.05 s**)** — if three or four faces swell and the group spreads in a single frame, the impression that the screen jolted comes before what the target is. The former 0.15 s removed that impression, but left a window where the hand holding the card was already over the target while the face was still growing — emphasis is a signal that must be done **before** you aim. The target value (`_pilot_emphasis_target`) and the current value (`_pilot_emphasis_scale`) are separate, and drawing, layout and hit radius all read the latter in one place, so the three stay in sync even mid-interpolation. Once reached, it does not move at all — this is different from the old pulse. **LOCATION leaves only valid cells green** and dims the remaining cells and **every pilot** (the yellow range fill and the `range_unlimited` special case were deleted — even with unlimited range, only reachable tiles are bright). **But the caster is never dimmed in any mode** (`CardTargetingOverlay.card_caster`) — "you can't drop here" makes no sense for the one casting the card. It is not an emphasis target either, so the caster grows only when it is a valid target of its own card (`target=ally` like protect / return-to-base). **Until confirmation, no cost is deducted and the card stays in hand, so there is nothing to undo** — **if the drag is dropped off target, the card returns to its place and the overlay turns off.** The targeting state has exactly the same lifetime as the drag, so there is no concept of 'escaping' at all (releasing ends it). It is not modal, so pass turn stays live. **The overlay now owns no nodes at all** — when PREVIEW's left/right team panels moved to the VS screen after submission, that CanvasLayer disappeared too. |
| Card drag and drop | **Dragging and dropping a card is the only way to pick one up.** **The card selection state has been deleted** — clicking does nothing; the card leaves the hand only once you press and move more than `DRAG_THRESHOLD_PX` (10px). It used to be that clicking lifted the card and left targeting on, so you had to drag again or click elsewhere to release — the controls were split in two (click→drag / click→click to release), and since a drop was the only path to play a card anyway, the intermediate state did nothing. `_selected_card` / `_select_card` / `Card.is_selected` / `Card.card_clicked` / click-outside-to-release all disappeared then, and `deselect_current_card()` survives only in name, meaning 'forcibly tear down the in-progress drag and targeting'. **The dragged card's pose depends on whether it has a target.** (1) **Targeted cards (PILOT / LOCATION) stay in the hand** — they keep the fan tilt in the lift pose (`Card.PRESS_LIFT`), and a **quadratic Bézier aiming arrow** (`card_phase/CardDragArrow.gd`) runs **from the card's top edge to the cursor**. If the card flew around stuck to the cursor, its own body would cover the target you are aiming at (enlarged portrait / green valid cell), hiding what it is over at the very moment you drop. The arrow node is **child index 0** of `_bs.canvas` (behind the cards) and its start point is buried `ARROW_TUCK_PX` (42px) into the card, so the arrow reads as extending from **under** the card. The control point lies on **the card's own up axis**, so a tilted card shoots along its tilt, and when the cursor is below the card it is clamped by `BOW_MIN` so it does not loop. The colour says whether dropping now would play it — gold normally, cyan over a valid target/cell. (2) **Untargeted cards follow the cursor** (`Card.follow_cursor`) — there is no target to aim at, so nothing to hide, and `Card.begin_free_drag()` straightens the fan tilt to 0 over `FREE_DRAG_STRAIGHTEN_SEC` (0.10 s) to make a 'pulled out of the hand' pose. For these cards the drop zone is the signal instead of an arrow. **Either way, the original slot stays empty** — `relayout_hand` skips `is_dragging` cards, so the remaining cards hold their places, and a missed drop returns to that spot with 0.00px error. Where you drop is what it does: **targeted cards onto the target** (enlarged pilot portrait / green valid cell), **untargeted cards onto the screen-centre drop zone** (`CardPhaseManager.drop_zone_rect` — 40% of screen height centred vertically, full width), and **during a discard:N pick, the same central zone** — `drop_zone_rect()` ignores the mode and always returns the same rect, and the row where picked cards line up also comes from its centre (`CardSelectOverlay.to_discard_center_y()`). Only the text changes to "여기에 놓아 버리기" (Drop here to discard), and at that time the zone node is raised to canvas child index **1** (index 0 is taken by the discard dim, so leaving it would press the zone under the dim). Previously only discard used a separate band of `DISCARD_ZONE_H` (440px) centred at `TO_DISCARD_CENTER_Y` (700), so **the same gesture had a different drop spot depending on what it did**, and you had to re-aim each time between playing and discarding (both constants were deleted together). **Pressing a picked card returns it to the hand** (`CardSelectOverlay.remove_card_from_discard`) — a transparent button (`UnpickHit`) laid over the card takes that click, and it returns to **the index it left from** (appending it would teleport the undone card to the hand's right end so it reads as "newly drawn" rather than "undone"). **On a miss the card just returns to its place; cost and card are unchanged.** Confirmation has only one path, `CardTargetingOverlay.confirm_with` → `_on_selection_confirm`, so cost deduction / card consumption / effect chain never exist in two copies (`_end_drag` keeps `_drag_card` alive until that callback returns synchronously). All input is received by a single `HandHitLayer` — the control holding the button keeps mouse focus, so motion/release keep arriving even when the cursor leaves onto the battlefield, and the battlefield side has no drag wiring. |
| Draw animation (the path a card takes into the hand) | A drawn card does not just appear in its slot — **first a card rises out of the deck pile and fades** (`CardPileStack.play_pop`, the "Cards moving between piles" entry above — the next beat takes over at 0.182 s, when 30% alpha remains), **appears face-down from outside the screen's left edge** (`_draw_entry_position`), **flies to above the hand's right end (where the new card will sit)** (`DRAW_FLY_SEC` 0.28 s, `EASE_IN_OUT`/`SINE` — a front-heavy deceleration curve covered 77% of the 1200px in 0.1 s, so "it came from the left" did not read), **flips there** (`Card.play_flip_reveal`, `FLIP_HALF_SEC` 0.09 s ×2, folding `scale.x` to 0 and back, swapping front/back on the zero-width frame), and **settles into its slot** (`relayout_hand`). The flip point is `DRAW_FLIP_LIFT_PX` (78px) above the slot — flipping inside the row would have neighbouring cards hide half of it, and the settle would not remain as a visible motion. While the animation runs, `Card.intro_active` removes that card from hand membership, so **layout · hover · grab all pass it by** (the rest of the hand has already narrowed to make room for the new card and waits). The flight uses `Card.tween_to` (= `_active_tween`) — it must be a tween held by the card itself so the discard animation can tear it down, since over-cap cleanup discards **the oldest card** (= possibly one still in flight). If several arrive in the same frame, each departs `DRAW_STAGGER_SEC` (0.07 s) later. Each beat waits on a timer, not the tween's `finished` — if the card is freed midway, that signal never arrives. **Two places turn the intro off**: precision move's return to the hand's left (`at_left`, the direction would be wrong) and `_restore_from_snapshot` (a cancel rollback would look like a new hand). |
| Discard animation | A card leaving the hand to be discarded goes straight down **along the screen Y axis only, regardless of fan tilt**, while fading out (`Card.DISCARD_DROP_PX` **150px** / `DISCARD_FADE_SEC` 0.30 s — vanishing just below the hand reads as "discarded" better than travelling far off the bottom of the screen. **The fall curve is `EASE_OUT`** — it snaps down the moment it leaves the hand, then slowly comes to rest below. The former `EASE_IN` was faintest at the moment of falling away and fastest when it had almost vanished, putting the weight at the end), and when it finishes falling it `queue_free`s itself. **Only after that fall ends does the discard pile receive the card** — `CardPileStack.play_land` starts after `PILE_LAND_DELAY_SEC` (= `Card.DISCARD_FADE_SEC` 0.30 s), so the two animations chain without overlapping (the former 0.16 s had the pile receive it while the card was still falling, so the same card was in two places), and **the count and pile thickness rise only after that landing afterimage has fully settled** (`CardPhaseManager._discard_pending` / `_commit_discard_gain` — the displayed value is always `배열 크기 − pending` = array size − pending). A plain refresh with delta 0 does not touch the settlement — pushing pending there would wipe out the whole delay in one refresh — this is the opposite of the lift (`PRESS_LIFT`), which rides the card's own up axis (a discarded card is falling, not being drawn, so riding the tilt would make only tilted cards drift sideways). The single entry point is `CardPhaseManager.play_discard_fx(node)`, and **the node must already be removed from `player_card_nodes` before calling it** — if layout · hover · hit band counted that card as in hand for those 0.3 s, the remaining cards could not fill the gap. Any in-progress layout / hover / shadow / flip tweens are all killed before starting. **Cards lined up in the screen centre by discard:N also go down with the same animation on confirm** (`CardSelectOverlay._commit_discard` detaches `to_discard_nodes` from the list first and then hands them over — otherwise `_teardown` frees them on the spot). **Cancel is the exception** — a card that was not discarded has no reason to fall, so it is freed immediately and the snapshot rebuilds the hand. |
| Card face (art · name · cost ribbon · portrait) | **From the top, the face has two layers: art → nameplate**, with the cost ribbon on the top left. **There is no description text on the card** — the text is carried per screen by the `card_phase/CardDescBox.gd` description panel (hand = portrait panel beside the pointed-at card · card played by the AI = right of the centre card (no keyword notes) · search/select grid and pile browse = beside the hovered or pressed card · ban/pick sheet and mech detail = above the pressed card). The description plate that crammed up to 128 characters into 160×220 at 8pt (`DescPlate` / `_fit_desc_font_size`, **deleted**) was not lettering meant to be read; the art took over that space, so the card is recognised **by its picture**. **The art is everything above the nameplate** (y 0..184, to the card's edge — the two top corners are cut with anti-aliasing by the `rounded_top_mask` shader), and the image comes from `CardImages.art_for(카드 이름)` (card name) — without dedicated art it is the Deadlock item icon paired by `CardImages.ITEM_ART` (`images/ground/deadlock_items/`, an item with a similar effect), and if not in that table either, one of the five images in `images/ground/` **chosen by name hash**, so the same card always gets the same picture. The card has no border (cost-coloured background · yellow border deleted). The **nameplate** is a plate filling the full width of the card's bottom band (y 184..220) with just the item type colour (weapon · spirit · vitality), and there is no shadow at its boundary with the art (the former `ArtShadow` strip deleted). A Charge card's `N/M` badge sits at the bottom right of the art just above it. **The cost is printed on a tall right-trapezoid ribbon hanging inside the card's top-left corner** (`CostBadge`, `COST_RIBBON_RECT`; the Panel stylebox is left empty and its `draw` signal draws `CostRibbon.draw` + `StrategyIcon.draw_indicator`) — the hand is a fan where cards overlap by more than half (the right card covers the left one), so **the top-left corner is the only corner always visible on each card**, which is why the cost goes there. The ribbon draws above the unplayable slab, so **it is dimmed separately** (`COST_BADGE_BLOCKED_TINT`) — otherwise only the cost would stay bright on a locked card. The caster portrait ribbon (top-right corner, see *Card front layout*) is drawn **only in the hand** (`Card.is_player_card` — the detail panel · pile browse · ban/pick · draft have no caster or it is meaningless, and the opponent hand peek is face-down). Even earlier, the face (`face_for`) **filled the whole body**, taking the illustration's place. |
| Hand lowering / raising (when it is not my turn) | **When it is not my operation phase, the hand retreats down the screen and hides behind the ally pilot strip.** About half of each card is hidden by the strip backplate, and when my turn comes it rises back up. The condition is just `_hand_is_lowered()` = `game_phase != CARD_PHASE`, which is **narrower** than the dim (`_apply_hand_dim_state`) — during windows inside my turn where input is briefly blocked (hit animation · modal pick · turn banner), the hand only darkens and does not lower (if it lowered then too, the hand would bob up and down with every modal). **The position** is added to `slot_position()` by `hand_drop_offset()`, derived not from a constant but back-computed from the strip backplate (`hud.player_strip_backdrop_top() − Card.CARD_H × 0.5 − BS_HAND_CENTER.y`) — both values already include the safe-area offset, so "about half hidden" holds regardless of device (**206px** at 1080×1920). **z-order** is changed by `_reorder_hand_nodes()`: lowering alone leaves the cards hanging **over** the plate, not hidden, so it takes the strip backplate as a marker and inserts the cards one by one into the slots right before it, pushing the whole bunch under the plate (on my turn, they go to the end of the child list as before). **The shadow** is switched by `Card.set_lowered()` to `SHADOW_FAR_*` (offset 1×4 · blur 3 · spread 0.98) — **a short shadow hugging the card = far from the camera** is the whole of this effect, and on my turn it returns to the usual three levels rest / hover / drag. The hit layer rides the same offset (`_fit_hit_layer`), so it does not swallow battlefield clicks where there are no cards. |
| Card description panel | A portrait panel like a card, **`DESC_BOX_GAP` (20) beside the pointed-at (enlarged) card** (`CardPhaseManager.DESC_BOX_W` 240; **the text sets the height** — no lower bound, `CardDescBox.build(..., min_h = 0)`; the old floor of the enlarged card's height was deleted). **Dragging a card drops the keyword panels and the description panel alone sticks to the dragged card's left** (`_desc_follows_drag` / `_follow_drag_desc`, positioned every frame from the card's live transform — right edge = card left − `DESC_BOX_GAP`, top = card top; with no room on the left it goes to the card's right). It used to slide to the top corner of the hand when the hand lowered (`_reflow_description_box` · `DESC_MOVE_TIME`, **deleted**). Card centre at or right of the screen middle → panel on the card's left; left of the middle → on its right. Keyword notes are separate panels further out (`_keyword_boxes`, `KEYWORD_BOX_W` 210, one per keyword), flipping to the card's other side if there is no room outside. The panels **cover neighbouring hand cards visually but never block touches** — they live on a dedicated `CanvasLayer` (`DESC_LAYER` 2) above the hand canvas (layer 1), so they always draw over the cards (on the same canvas `_reorder_hand_nodes` would raise cards to the end of the child list and over the panel), and the panels and all their children are `MOUSE_FILTER_IGNORE`, so pressing there lets `HandHitLayer` pick the card underneath. The card face has no description text, so this is **the only place to read text in the hand**. It used to be a wide panel centred just above the hand (640), and before that fixed at the top of the screen (`DESC_BOX_TOP` 142, **deleted**). **It appears on hover alone** — which card to show is the same question as hand focus, so a single `_push_focus_card()` (dragged card > hover) answers it. The panel is opaque; it rises `DESC_ANIM_RISE` (24) from below while fading in and sinks the same distance while fading out before being freed (in `DESC_ANIM_IN_TIME` 0.2s · out `DESC_ANIM_OUT_TIME` 0.1s, `_animate_desc_in` / `_animate_desc_out` — when focus moves, the old panel sinks while the new one rises). **There are no buttons at all** — playing a card is a drop, and so are the 버리기:N · 보존:N picks. |
| Attack card hit roll | `attack:N` cards roll **the same hit check** as the battlefield (전장): `SimulationCore.roll_hit` (`hit/(hit+evasion)`). On a miss the damage is 0 and the log records "빗나감" (Miss). `pierce` (sure hit) skips the roll. `repeat` (consecutive attack) re-rolls the same attack **after every hit**, continuing until it misses or the target goes down; the cap that prevents infinite loops is `CardPhaseManager.MAX_ATTACK_REPEATS` (const.csv `CARD_MAX_ATTACK_REPEATS`). **Every hit gets a hit animation, and `_effect_attack` `await`s it** (see the "Attack hit animation" row below). |
| Hand cap | `MAX_HAND_SIZE` (game_config.csv). The automatic draw that runs **when it is not my turn** (while operation points refill) always draws, even with a full hand, and sends the overflow to discard **oldest card first** (same for both teams), **skipping cards kept by 계획 중시 (Prioritize the Plan)**. Previously the draw was skipped, so the deck never cycled and the hand stayed frozen. In contrast, **cards drawn by a card effect during my own turn are not discarded even above the cap**; the first automatic draw after the turn ends cleans them up. When the deck runs out, the whole discard is reshuffled back into the deck, as before (`draw_card`). |
| Card caster (시전자) restriction (`scope`) | `scope` in `cards.csv` sets which **positions** may own the card: `any` alone = all, `lane` alone = top · mid · carry (원딜) · support, otherwise a `\|` list of `jungle` / `top` / `mid` / `carry` / `support`. The check runs when picking fixed pilot cards (`GameManager.pilot_card_ids_for` / `roll_pilot_card_ids`) and in the fallback pool (`_pool_for_pilot`). Expansion is done by `CardData.positions_of` alone. |
| Card categories / fixed pilot cards (`card_cat` · `pilot_card_slots`) | cards.csv contains **only pilot cards** (`card_type = pilot`). `card_cat` is a multi-value category list separated by `\|` (성장 (Growth) · 교전 (Engage) · 매복 (Ambush) · 공격 (Attack) · 방어 (Defense) · 유틸리티 (Utility) · 뽑기 (Draw) · 정글 (Jungle) · 라인전 (Laning)). The 3 pilot cards are **fixed per player** (`players.pilot_cards`); if empty, they are drawn deterministically from `pilot_card_slots.csv` (three slots per position, each slot a category list) using the player id as the seed. The allocation is recorded in `BattleSim.starter_cards`, which the detail panel reads. See the *Per-pilot decks* section above. |
| 3 deferred effects (settled on operation phase entry) | `CardPhaseManager._apply_phase_entry_carryovers(is_player)` settles them all at once **when that team next enters its operation phase (작전 단계)**. (1) Clears the **계획 중시** keep list (`BattleSim.preserved_cards_p/ai`); a keep survives only one BATTLE segment. (2) Adds **아드레날린** (Adrenaline)'s `next_phase_strategy_*` (its negative `strategy_next_phase` clause) to the points (never below 0). (3) Resets **완벽한 마무리** (Perfect Finish)'s team growth multiplier to 1.0. Meanwhile, the **계획 살인** (Planned Kill) reservation (`kill_bounty_*`) vanishes when that phase ends (`end_card_phase` / end of the AI turn). |
| 계획 중시 (keep) | Keep protects **only against the automatic over-cap discard (`_trim_hand_overflow`)**. Forced discards by card effects (재고 (Reconsider) / 완벽한 마무리 / 과감한 정리 (Bold Cleanup) / 솔로 퍼포먼스 (Solo Performance)) ignore keep. The player picks like a discard, **by dragging cards out of the hand and dropping them** (`CardSelectOverlay.start_preserve`); on confirm the picked cards return to their original hand slots. The overlay only returns the picks; `CardPhaseManager` does the registration. The marker is a cyan border on `Card` (`PreserveMark`) and does not darken the card (keep is a guarantee, not a restriction). |
| 계획 살인 (kill bounty) | **Prepaid reservation.** When the card is played it plants `BattleSim.kill_bounty_p/ai`; `mark_pilot_dead`, **the single point every death passes through**, pays it once to the **opposite team** of the fallen pilot and consumes it to 0. There is no third faction on the battlefield, so no killer argument is passed. If two are played in the same phase, only the larger one remains. |
| 완벽한 마무리 (`end_phase`) | This clause **does not close the phase on the spot.** While the effect chain runs, the card floats outside the hand, so closing now would shut the door before exhaust / discard routing. It only sets the `_end_phase_requested` flag; **for the player, the tail of `_finalize_pending_play`**, and **for the AI, the `AiCardPlayer` play loop** (**after** waiting for the engage arena), pick it up via `consume_end_phase_request()`. |
| AI card selection (priority scoring) | **The AI plays not a random playable card but the single highest-scoring one** (`AiCardPlayer._pick_best_card`). The goal is not a strong AI but one that **visibly spins its wheels less**: previously attack cards with no enemy in range, or heals on full-HP allies, popped out at random, so the opponent's turn became a stretch where only the centre animation ran and nothing happened. Four rules: (1) **Drop unplayable cards** (`CardPhaseManager.ai_can_play`: affordable · caster alive · `CardData.is_playable()`. The last one is new: `effective_cost_for` does not clamp the result below 0, so **cost -1** (unusable) cards read as "0 cost", and the AI just burned 캐시 (Cash) · 계시 (Revelation) · 약자 멸시 (Scorn the Weak) · 밸런스 (Balance). `_ai_turn_ready` reads the same function). (2) **Drop cards with no valid target.** (3) **The clause name sets the score** (`CLAUSE_WEIGHT`; if a card has several clauses, the highest one is the card's character, e.g. 간보기 (Probe) is an attack card, not a strategy-point card. Heal · shield are deprioritized when the most-wounded ally is above `SUPPORT_HP_RATIO`, const.csv `AI_CARD_SUPPORT_HP_RATIO`). (4) **Cost is a penalty; ties are broken by jitter** (without jitter the same hand plays out in the same order every time, and the opponent's turn reads as mechanical). |
| AI plays-per-turn cap | `AiCardPlayer.MAX_PLAYS_PER_TURN` (const.csv `AI_CARD_MAX_PLAYS_PER_TURN`). The loop's real exit condition is "no playable card left", but cards that cycle the hand without spending cost, like **재고** (free, discards the whole hand and draws the same number again), can postpone that condition until deck + discard run dry. This is a backstop that breaks a structural loop, not a balance knob. |
| Volatile (`volatile`) | **When discarded, the card vanishes on the spot instead of going to the discard pile.** Carried by cards that pilot skills create directly in the hand (배회 (Roam)'s [이동] (Move), 복귀 명령 (Return Order)'s [복귀] (Return to Base), 격전 (Fierce Battle)'s [전투 개시] (Start Battle), 고양감 (Elation)'s [아드레날린] (Adrenaline), 약탈자 (Raider)'s [약탈] (Plunder)). **It pairs with exhaust but is not the same thing**: exhaust vanishes **when used**, volatile vanishes **when discarded unused**, so with both a skill-granted card never bloats the deck either way. The check passes through **one place, `CardPhaseManager.send_to_discard(cd, discard)`**: every discard path (over-cap trim · discard:N modal · 재고 · 완벽한 마무리 · 과감한 정리 · 솔로 퍼포먼스 · `_dispose_used_card`, seven sites) calls that function, so the rule lives in one place only. |
| Mutual exclusion (`excl_group`) | Cards with the same `excl_group` value can be owned **only one per pilot**; the fixed-card roll (`roll_pilot_card_ids`) enforces it. No card uses it now (the 안전한 파밍 (Safe Farming) ↔ 공격적인 라인전 (Aggressive Laning) pair is gone). |
| Excluded from random pool (`pool = 0`) | Cards with `pool = 0` are filtered out by `_build_pool_from_db` and never enter a random starter deck. **결투 (Duel) (id 3)** is the first case: its implementation and effect handling are fully alive, but it is granted to no one; it is kept as a slot to convert into a specific mech's unique card. |
| Reposition (`reposition`) | **Moves to the far left of the hand.** Playable cards (정밀 이동 (Precise Move) · 골드러시 (Gold Rush)) return to the far left of the hand instead of discard after use, and the same card's `self_cost:N` raises that copy's cost each use (the cap for the AI loop). Routing is `_dispose_used_card`. |
| Card exhaust rule | **Exhaust is decided solely by the `exhaust` keyword.** The `keyword` column is a **`|`-separated list**, so the check must go through `CardData.has_keyword("exhaust")`; a whole-string comparison silently turns exhaust off the moment a second keyword is added (전령 제압 (Herald Subdued) = `exhaust\|preserve`). Everything except return-to-hand cards goes to discard. Previously a card with `uses > 0` vanished once its uses ran out, but the `uses` values in `cards.csv` allowed almost every non-exhaust card only a single use, so **most cards, including 전투 개시, exhausted after a single play**: the deck never cycled and only shrank over the match, and the discard filled only with discard-effect cards. `CardData.remaining_uses` was deleted; the `uses` column is loaded but read by nobody (a slot kept for a future "exhaust after N uses"). |
| Browsing the Deck / Discard lists | **Pressing the Deck / Discard piles** on either side of the hand row spreads that pile's cards in the same 5-column list as the search grid (`card_phase/CardPileViewer.gd`, read-only). **Sorted by name, ascending**, because showing the real deck order would reveal the next draw; the search (`search:N`) grid sorts by the same rule. It can be opened **only during the operation phase** (`CardPhaseManager.can_browse_piles()`); when it can't be opened, the button is disabled and the pile is dimmed. While it is open, hand input · ending the turn · donut flip are all locked; in particular `CostDonut` listens via `_input`, so the dim alone doesn't block it, and `set_flip_allowed` is turned off separately. Close with the close button or by clicking the dim. |
| Unusable card display | Not enough mana / caster waiting to respawn is shown with **a translucent slab covering the whole card** (`Card.BlockOverlay`); greying only the card background left the pilot illustration on top bright, so it read as a usable card. If the caster is down, **the number of turns until respawn** is stamped on top in a large font at the card's centre, and the confirm button is disabled meanwhile. |
| Hand card scale | **Cards in the hand are drawn larger than `Card.CARD_W/H` (160×220): `CardPhaseManager.HAND_CARD_SCALE` (1.2) → 192×264.** The card size itself is not enlarged because that constant is read by a dozen-odd screens, from the ban/pick (밴픽) sheet · pile browser · pilot detail popup (enlarging it would throw all those grids off). **Layout coordinates don't take the scale**: `pivot_offset` is the card's centre, so multiplying `position` (top-left before scaling) by the scale **does not move the centre**; hence slot coordinates · hit-band centre computation · hand lowering (`hand_drop_offset`) didn't change a single character. The only places that know the scale are **the three that measure visible width** (spacing compression in `slot_spacing`, occlusion computation in `_hover_push_amount`, and `grow_x/y` = `HAND_CARD_SCALE × HOVER_SCALE − 1` in `_fit_hit_layer`). The same 1.2× also applies to **cards the opponent plays** (`AiCardPlayer.SCALE_BIG` 1.35 → **1.62** / `SCALE_SMALL` 0.85 → **1.02**) and to **the discard pick row** (`CardSelectOverlay._layout_to_discard_row`: it is the same node lifted straight out of the hand, so resetting to 1.0 would shrink it when picked and grow it when undone), and `ObjectiveRewardFx.CARD_SCALE` went up together from 1.05 → **1.35** (a card floated in the centre to be read must be larger than the hand). Measured (실측): 4 cards spacing 204 · row 138..942; 12 cards spacing 64.5 · row 89..991; the card's bottom edge is 59px (hover 33px) from the ally (아군) strip's backplate (뒤판). |
| Hand layout | Row top is `BS_HAND_CENTER.y` = **1370** (raised 70px from 1440 when the allied pilot strip doubled in height with round portraits). The earlier **1440** had moved up 60px to match the battlefield shrinking to 90% and its bottom rising 55px, keeping a ~90px gap between the card tops and the battlefield's bottom edge. The confirm/cancel row · strategy point donut · Deck/Discard counters · hit layer are all back-derived from this value, so they follow along. Row is `BS_HAND_WIDTH` = (viewport − 2×`BS_HAND_AREA_MARGIN`) × `BS_HAND_WIDTH_SCALE` (1.10) = 902px wide; the Deck/Discard labels re-derive their gutter from the real hand edge. **The fan is one circle**: every card centre rides a circle of radius `BS_HAND_FAN_RADIUS` (3200px) pivoted *below* the row, so tilt and vertical offset always agree and **the middle card is the highest while both ends curve down** (12-card hand: ±6.7°, ends hanging 21.4px below the middle). A plain click does nothing at all — see Drag and drop (카드 드래그 앤 드롭). Each player card casts a `DropShadow` child whose offset/blur grows with height — rest 10px → hover 24px → dragged 32px. **The row spreads around one "focus" card — `_push_focus_card()` = the card being dragged, else the hovered one** — so grabbing a card opens the hand exactly as hovering it does. Focus scales the card to `Card.HOVER_SCALE` (1.2×, cubic EASE_OUT in 0.04s) and slides its neighbours away by `_hover_push_amount` — solved from the coverage it must prevent (96px enlarged half-width + `BS_HAND_HOVER_MIN_STRIP` 32px clickable sliver − the row's own spacing), so **it grows with the hand size**: `BS_HAND_HOVER_PUSH` 28px floor up to 8 cards → 60.5px at 12 cards. **The hand's width is fixed**: the two end cards are anchors, and the push ramps to exactly 0 at them via `1 − (steps/steps_to_end)^BS_HAND_HOVER_FALLOFF_POW` (2.0, so near neighbours keep nearly the full push) — the row redistributes rather than growing. Dragging a targeted (대상 지정) card lifts it by `Card.PRESS_LIFT` **along its own up-axis, keeping its fan rotation** (±4.6px sideways at the ends of a 12-card hand); `_begin_drag` reflows the whole row around it first, and since the focus card's own push is 0 there is no push-free slot variant — lift and drop are exact opposites. `_reorder_hand_nodes` raises the dragged — else hovered — card above all others. A hover reflow lays out the **incoming focus card too** — only the *dragged* card is skipped — otherwise it stays stranded at the push the previous focus gave it. **Hand cards don't pick the mouse**: `spawn_card_node` sets the whole card subtree to `MOUSE_FILTER_IGNORE` (PASS is not enough — a PASS container is still returned by picking) and one `HandHitLayer` Control over the row routes hover/clicks by cursor x, using bands cut at the midpoints between card centres, with the focus card holding the cursor while it's on its enlarged face. Rect picking let the focus card cover its right-hand neighbour down to 0–17px. Hover reflows are **deferred + coalesced** (`move_child` re-fires mouse_entered/exited synchronously — see card_phase/README.md), and `scale` is owned solely by `Card._refresh_float_state`. Card layout tweens `position`, never `global_position` (the latter is scale-coupled — see card_phase/README.md). |
| Attack hit animation | **Playing an attack card makes things happen on two portraits (초상) at once**: **white light rises** from the caster's portrait, and on the target's portrait **fragments burst outward** while the portrait **shakes violently**. One hit is two beats: **cast** (`BattleSim.anim_pilot_cast`, `ANIM_CAST_DUR` **0.12s**. A marker-wide white pillar rises `ANIM_CAST_RISE_PX` 54px while fading, with a circle at its head. **It always runs first, hit or miss**: a missed attack was still fired) → **impact** (`anim_pilot_impact`, `ANIM_HIT_HOLD_SEC` **0.20s**. `BattleRenderer.spawn_pilot_burst` scatters `BURST_COUNT` 12 fragments at evenly divided angles ±0.22rad and flies them with deceleration over `BURST_DUR` 0.18s; **angle · distance · size are fixed into an array at spawn time**. Re-rolling `randf()` every frame turns a spreading burst into dots blinking in a different place each frame. **The target's shake is far more violent than in battlefield auto-combat**: `ANIM_SHAKE_CARD_DUR` 0.26s / `ANIM_SHAKE_CARD_AMP_PX` **20px** vs the battlefield default 0.18s / 6px. Intensity is carried via `PilotData.anim_shake_amp`, and the renderer **keeps the frequency fixed and makes the number of oscillations proportional to the duration**; fixing the oscillation count would turn "shake longer" into "shake slower" and the violence would be lost). **Only the shake lives inside `_apply_attack_damage`; the fragments are spawned by `_effect_attack`**: the former is the same damage entry point as battlefield auto-combat · a pilot skill's hit, so spawning fragments there would attach particles to the damage that runs every turn, and they would become background noise. **Turrets get no fragments** (they have no portrait; turrets have their own `anim_turret_hit`). **The total animation time of one hit is the sum of the two values, 0.32s**: consecutive attack (`repeat`, up to `MAX_ATTACK_REPEATS` hits) repeats both beats per hit, so the worst case is that many × 0.32s, during which the hand and ending the turn are both locked. `DMG_POPUP_DUR` (**0.30**) must be shorter than that sum; if longer, numbers from consecutive hits stack in the same spot (popup coordinates are fixed at spawn). **The next card can be played only after the animation finishes**: `CardPhaseManager._attack_anim_active` locks both the hand dim (`_is_player_input_blocked`) and ending the turn (`can_end_card_phase`). **AI attacks use the same animation**: the single `await` in `_effect_attack` turns `_apply_single_effect` → `_process_pending_chain` / `apply_card_effect` → `apply_and_dispose_ai_card` → `AiCardPlayer.run_ai_plays` into a chain of coroutines. Death / return-to-base (복귀) / respawn clear the light via `anim_pilot_cast_clear`. **It used to be a lunge (body slam)**: three beats where the caster's portrait **actually dug into** the target's portrait (`ANIM_LUNGE_IN_DUR`) and came back while floating (`ANIM_LUNGE_OUT_DUR`). Because it moved the portrait, it needed three supporting mechanisms, all now deleted: (1) direction had to be measured from the drawn markers of `pilot_marker_positions()` (measuring from tile centres reversed the direction when lunging at an enemy in the same cell), (2) `BattleRenderer._lunging_cells_last` drew that cell last so the lunging face didn't hide behind the target cell, and (3) every death · return-to-base · respawn had to clear the offset with `anim_pilot_lunge_clear`. Now both portraits stay in place with only effects layered on top, so none of the three is needed: **do not bring them back**. Deleted names: `anim_pilot_lunge` / `anim_pilot_lunge_return` / `anim_pilot_lunge_clear` / `pilot_lunge_offset`, the four `ANIM_LUNGE_*`, the four `PilotData.anim_lunge_*` (→ replaced by `anim_cast_t` / `anim_cast_dur`), `_lunging_cells_last`. |
| Opponent cards come out standing upright | `AiCardPlayer._show_card_centre`, which flies a card the AI played to the screen centre, **also straightens its rotation to 0**. The drawn card still carries the tilt the opponent's fan gave it (`rotation = -theta` in `HudBuilder._layout_ai_hand`), and `pop_ai_hand_card_node()` preserves only position and scale, so without straightening it flipped and vanished **standing askew** in the middle of the screen. A card pulled from the hand standing upright is the same rule as the player's free drag (`Card.begin_free_drag` straightens the tilt over `FREE_DRAG_STRAIGHTEN_SEC`). |
| Damage number display | **Attack cards (`attack:N`) only.** For each roll, `-N` / `MISS` / `흡수` (Absorbed; when the shield ate it all) floats up over the target marker and fades (`BattleRenderer.spawn_pilot_popup`). In a consecutive attack each hit carries the whole lunge animation (0.32s), so popups never overlap (`DMG_POPUP_DUR` 0.30 < 0.32); `DMG_POPUP_STAGGER` remains only for cases with no animation (legacy cards with no caster). Coordinates are fixed at spawn, so the number plays to the end even if the target goes down. Battlefield auto-combat keeps just the shake, as before. |
