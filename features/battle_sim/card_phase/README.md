# Card Phase Module

## CardPhaseManager.gd
`extends Node` — child of BattleSim.

Manages the **작전 단계** (card draw / play overlay) that gates each battle turn.
The cost label is surfaced as "작전 점수" in the HUD; one tick of `simulate_turn`
is referred to as "1분".

### Turn flow
- `do_battle_turn()` — calls `_bs.sim_core.simulate_turn()`, accumulates 작전 점수,
  draws cards, enters CARD_PHASE when 점수 ≥ PHASE_THRESHOLD. After the AI
  draws, `_bs.hud.update_ai_hand_visuals()` reflows the face-down peek row
  under the score panel. It also re-runs `highlight_affordable_cards()` every
  tick so the 부활 countdown printed on each card face stays current.

### Hand overflow (BATTLE auto-draw only)
`MAX_HAND_SIZE` is **8**. The auto-draws that tick by while 작전 점수 climbs
back to `PHASE_THRESHOLD` — i.e. the stretch when it is *not* the player's turn
— always draw, even on a full hand, and `_trim_hand_overflow(is_player)` then
discards from the **front** of the hand (oldest first) until it is back at 8.
Both sides run the same rule; only the player side despawns card nodes and
relayouts. The old behaviour was to skip the draw when the hand was full, which
stalled the deck and left the same dead hand sitting there for the whole wait.

Cards drawn by a card effect **during** 작전 단계 are exempt — that is the
player's own turn, so the hand is allowed over the cap and nothing is thrown
away mid-turn. `_effect_draw` and `_on_search_overlay_complete` therefore carry
**no** `MAX_HAND_SIZE` guard (only an exhausted deck+discard stops them); the
first auto-draw after the turn ends is what trims the excess.
- `start_card_phase()` — transitions to CARD_PHASE, snapshots `card_phase_entry_cost`
  so the 턴 넘기기 face of the 전략 포인트 도넛 stays disabled until the
  player spends ≥ 1 점수.
  Awaits `HudBuilder.play_turn_announce(true)` so the "당신의 차례" banner
  sweeps in / holds / fades out before the player can interact; the player
  hand stays dimmed for that whole interval via `_apply_hand_dim_state()`.
- `can_end_card_phase()` → bool — true once `player_cost < card_phase_entry_cost`.
  Also blocked while `_player_turn_announce_in_progress`, while overlays own
  the screen, and while the AI play loop is in flight.
- `end_card_phase()` — sets `_ai_play_in_progress = true`, awaits
  `play_turn_announce(false)` (the "상대 차례" banner), then runs the AI
  card loop, runs `recall_sys.process_phase_end_recalls()`
  (HP threshold + out-of-position card-displaced pilots), returns to BATTLE.

### Hand dim driver
`_apply_hand_dim_state()` toggles `Card.set_dimmed(true|false)` on every
player hand node based on `_is_player_input_blocked() or game_phase != CARD_PHASE`.
That covers BATTLE auto-tick, the player turn-start banner, the AI run loop,
and any active modal overlay. `Card.set_dimmed(true)` darkens the modulate,
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
- `spawn_card_node(cd)` — instantiates a player Card.tscn into `_bs.canvas`. The
  AI hand is logical-only — no card backs are spawned for the enemy.
- `slot_position(index, total)` — returns the top-left viewport position for the
  card at `index` in a hand of size `total`. Spacing is
  `Card.CARD_W + BS_HAND_CARD_GAP` until the natural span exceeds
  `BS_HAND_WIDTH`; from then on it compresses uniformly so the hand always
  fits the fixed-width row centered on `BS_HAND_CENTER`. `hover_push_offset`
  is added to the X.
- `hover_push_offset(index, total)` — the spread that keeps a hovered card's
  1.2× enlargement from covering its neighbours. Cards left of the hovered one
  slide left, cards right of it slide right, ramping linearly from the full
  `BS_HAND_HOVER_PUSH` (28px) on the immediate neighbour down to **exactly 0 on
  the outermost card of each side** — so the row's edges never move and the hand
  keeps its width. The hovered card itself stays put. Verified for 8 cards with
  index 2 hovered: `[0, −28, 0, +28, +21, +14, +7, 0]`, span unchanged at 902px.
  `_hovered_hand_card()` resolves which card that is — a `_hovered_card` fast
  path validated against `Card.is_hovered()` and the hand array, so a freed card
  or a hover that arrived while a modal owned the screen can't leave the row
  stuck open.
- `slot_rotation(index, total)` — the hand's shallow fan. Card `index` is
  rotated `(index − (total−1)/2) × BS_HAND_FAN_STEP_DEG` (0.8° per step,
  declared on `BattleSim`), so a 12-card hand splays only ±4.4°. Cards pivot
  around their own centre (`pivot_offset` set in `spawn_card_node`), so the
  slot X positions are unaffected.
- `relayout_hand(nodes, skip = null)` — tweens every card to its
  `slot_position` / `slot_rotation`.
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
- `update_deck_discard_labels()` / `_refresh_count_labels()` — snap visible
  counts to current player_deck / player_discard sizes.
- `highlight_affordable_cards()` — re-reads every visible card's playability:
  `set_affordable(eff <= player_cost)`, `set_respawn_turns(respawn_turns_for(cd))`,
  and `update_displayed_cost(eff)`. Tail-calls `_apply_hand_dim_state()` and
  `_refresh_confirm_button()`, so every path that funnels through it also
  re-evaluates the hand dim and the 확인 button.
- `respawn_turns_for(cd)` / `card_is_playable(cd)` — the two playability
  questions. `respawn_turns_for` returns 0 while the 시전자 is alive and
  **at least 1** while they are down (never 0 for a dead pilot, so the card
  can't flicker back to playable on the tick the timer hits 0).
  `card_is_playable` = 시전자 alive **and** affordable **and**
  `card_has_valid_targets`.

### Card interaction (click-to-select + description box)
- Hand row: cards span ~y=1500..1720 at-rest (CARD_H=220), centred on the
  viewport. `BS_HAND_AREA_MARGIN` (130px) on each side is reserved for the
  Deck / Discard count labels and shrinks the inner `BS_HAND_WIDTH`, which is
  then widened by `BS_HAND_WIDTH_SCALE` (1.10) → **902px** on a 1080-wide
  screen (row spans x=89..991). That eats into the label gutters, so
  `HudBuilder._build_hand_indicators` derives its gutter from the real hand
  edge instead of `BS_HAND_AREA_MARGIN` and scales the label font down to fit
  (130→89px gutter, font 22→20).
- **Floating shadow** (`Card._build_shadow` / `_refresh_float_state`): every
  player card owns a `DropShadow` Panel parked at child index 0, so it draws
  under `CardBack` / `CardFront` and inherits the card's fan rotation and
  hover scale for free. The gap between card and shadow encodes height:
  `SHADOW_REST_OFFSET` (10px down, tight `shadow_size` 6, alpha 0.50) for a
  card resting near the table, `SHADOW_HOVER_OFFSET` (24px, blur 26, alpha
  0.36) while hovered, `SHADOW_SELECTED_OFFSET` (32px, blur 32, alpha 0.32)
  while lifted. The slab's own `bg_color` alpha also drops from 0.8 → 0.55
  on the blurred states so a high shadow reads as a soft pool, not a black
  rectangle trailing the card. Non-player cards (AI hand peek, 찾기 grid)
  keep the shadow hidden — `setup()` gates `_shadow.visible` on
  `is_player_card`.
- **Hover** (`on_card_hovered` / `on_card_unhovered`): face-up player cards
  brighten via a `modulate` tween and scale up to `Card.HOVER_SCALE` (1.2×)
  around their own centre, coming "closer to the screen" — the shadow drops
  to its hover pose at the same time. All three reactions run on
  `HOVER_EASE` / `HOVER_TRANS` (cubic `EASE_OUT` — quick jump, slow settle)
  over `HOVER_TWEEN_DURATION` 0.04s / `SHADOW_TWEEN_DURATION` 0.05s. The
  hovered card is also
  moved to the **top of the scene-tree** so it draws above its neighbours; on
  unhover the canonical hand order is restored. Hover reflow is
  suppressed while a card is selected so the lifted card stays on top (the
  `_hovered_card` pointer is still tracked in that state, ahead of the guards,
  so the row is correct the moment the selection drops). `Card.tween_to` treats
  its `target_scale` argument as the *layout* scale (`_base_scale`) and leaves
  `scale` **entirely alone** unless that layout scale actually changes (no
  caller changes it today). `scale` therefore has exactly one owner —
  `_refresh_float_state`. Two tweens racing over it is what used to strand a
  hovered card at 1.0: a relayout firing mid-hover captured the hover factor
  from a transient `_is_hovered` and killed the hover tween on its way past.
- **Select** (`on_card_clicked` → `_select_card`): pressing a card pops it out
  by `Card.PRESS_LIFT` (40px) **along its own up-axis while keeping its fan
  rotation** — `slot + Vector2(0, -PRESS_LIFT).rotated(slot_rotation(...))`, so
  a card on the left half of the fan travels up-left and one on the right half
  travels up-right, like a card drawn out of a real fan. Sideways travel is
  `PRESS_LIFT × sin(fan angle)`, i.e. ±1.1px in a 5-card hand and ±3.1px in a
  12-card hand at the current `BS_HAND_FAN_STEP_DEG` of 0.8° — raise that
  constant if the splay should read more strongly. It also pins to the top of the
  hand, flips `Card.set_selected(true)` (→ tallest shadow), and spawns the
  description box. The other cards stay in their slots — the gap where the
  selected card sat remains visible. **Re-clicking the selected card
  deselects it** (same path as an outside click; blocked only while a 전투
  개시 PREVIEW is pending, which must be resolved through the overlay's 취소
  button). Clicking a different card swaps the selection — the previous one
  drops back into its slot via `_return_selected_to_slot`, which also clears
  the selected shadow pose. `deselect_current_card` reflows the **whole** row
  (not just the dropped card): if the cursor is still on it, it stays enlarged,
  so its neighbours have to spread exactly as they do on a fresh hover.
- **Hand z-order** (`_reorder_hand_nodes`): canonical order is oldest-lowest /
  newest-on-top, then the **selected card — or, failing that, the card under the
  cursor — is raised above all of them**. That last clause is what keeps a
  hovered card above its right-hand neighbours right after a deselect, when the
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
  2. `_reflow_hover` — a pass whose hovered card matches the layout already on
     screen returns without touching anything, so the enter/exit churn a
     reorder provokes can't loop forever.
  3. `_reordering` + an "already sorted?" check in `_reorder_hand_nodes` — a
     reorder that would change nothing moves no children at all.

  Verified by sweeping a synthetic cursor across all 8 cards in both directions
  (140 samples): exactly one hovered card per frame, always at scale 1.2 and
  always topmost, every other card at 1.0, zero engine errors.
- **Description box** (`_show_description_box`): a `Panel` placed on either
  side of the lifted card (`DESC_BOX_W` × `DESC_BOX_H` = 320×220 px,
  `DESC_BOX_GAP` = 12 px). The side with more screen space wins; the box is
  clamped to the viewport. Contents: header row with card name on the left
  and the effective cost number on the right (white / green / red mirroring
  the card's top-left cost, no 시전자 tag) and the full description.
  **There is no 카드 내기 button** — playing a card is the 확인 button that
  `CardTargetingOverlay` parks at the bottom-left, so the commit action lives
  in one place whether or not the card needs a target. The only button this
  box still owns is **버리기**, shown while a 버리기:N pick overlay is active
  (`_in_discard_pick_mode()`), which is not a card play at all.
- **Selecting a card *is* the targeting step** (`_select_card` →
  `targeting_overlay.start_card_selection`): lifting a card immediately dims
  the out-of-range tiles, marks the legal targets, and raises the
  확인 / 취소 row. Nothing is spent until 확인 — see the 대상 지정 section.
- **Outside-click dismiss** (`_unhandled_input`): any mouse press / screen
  touch that lands outside the card, the description panel, and the buttons
  calls `deselect_current_card()`. Card.`_gui_input` calls `accept_event()` so
  the same press that selects a card never doubles back to deselect it;
  `Panel` and `Button` consume their own events via `MOUSE_FILTER_STOP`.
  **PILOT / LOCATION selections never reach this handler** — the overlay marks
  every battlefield press handled (see 대상 지정 below).
- `deselect_current_card()` is also called from `end_card_phase()` and
  `build_starter_decks()` so the lifted-card / description-box state never
  leaks across phase transitions or game restarts.
- `apply_card_effect(cd, is_player)` → String log message

### Per-pilot decks (시전자 rule)
- `build_starter_decks()` — for each pilot on each side, draws
  `CARDS_PER_PILOT` (= 6) random `CardData` copies from the DB pool and tags
  each with that pilot as 시전자 (`owner_pilot`). All 5 stacks shuffle into
  the team deck. Player and AI sides build identically; AI hand is logical-only
  but its cards still carry an enemy-pilot owner.
- `make_card_copy(src)` — copies every CSV column AND `owner_pilot`. Use this
  any time you need a deck-safe duplicate.
- Card front layout:
  - **Top-left**: 작전 점수 (cost) label, large outlined text on the
    cost-coloured card body. `Card.update_displayed_cost(eff)` recolours the
    number — white when matched, green when reduced by an active modifier
    (사전 준비 / 전투 준비 / 집중), red when increased (정밀 이동).
    `CardPhaseManager.highlight_affordable_cards` calls it for every visible
    card so the four cost-modifier effects stay in sync with the card art.
  - **Top-center**: card name (auto-truncates with `clip_text`).
  - **Center / body**: **owner face image** filling the card
    (`PilotImages.face_for(owner.pilot_id)`, 140×170 `TextureRect` inside a
    `CenterContainer`, `STRETCH_KEEP_ASPECT_COVERED`). Empty when no face is
    available — the cost-coloured panel shows through.
  - **Unplayable dim** (`BlockOverlay`): a `Panel` at the **end** of the child
    list — above `CardFront`, so it darkens the owner face, name and cost
    together — filled `BLOCKED_OVERLAY_COLOR` (black α 0.58) with the card's
    own 10 px corner radius. It goes up for either of two reasons, tracked
    independently and merged by `_refresh_block_overlay()`:
    `set_affordable(false)` (can't pay) or `set_respawn_turns(n > 0)`
    (시전자 부활 대기). `set_affordable` no longer repaints the card body grey
    — the grey panel sat *under* the portrait, which stayed bright and read as
    playable; only the border colour still shifts as a secondary cue.
  - **Respawn countdown** (`RespawnCountdown`): a `Label` next to the slab,
    `RESPAWN_FONT_SIZE` 76 with a 10 px outline, showing the turns left until
    the 시전자 comes back. Visible only while `set_respawn_turns(n)` is
    non-zero. `Card.is_playable()` returns false whenever either reason holds.
    Both nodes must be `MOUSE_FILTER_IGNORE` — see the filter note below.
  - **No description on the card itself.** The full description is surfaced
    only in the side description box that appears when the player selects
    the card (`_show_description_box`).
  - **No role badge.** Role is conveyed solely by the owner face image; the
    description box still surfaces "시전자 <Role><team>" in the header line.

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

### Effect chain encoding (cards.csv `effect` column)
The DB column is a `;`-separated chain of clauses. Each clause is
`name[:value][|flag[:value]]…`. Examples:
- `draw:2;discard:2`            — two clauses run in order
- `attack:1|pierce|min_range:2` — one clause + two modifier flags
- `engage:3|exclude_lane`       — engage with lane-exclusion modifier

`apply_card_effect()` parses the chain, dispatches each clause through
`_apply_single_effect`, and returns one log line of the form
`<시전자> [<카드명>] · <효과 요약>, <효과 요약>…`.

### Effect handlers
> **Note on the "opens CardTargetingOverlay …" wording below**: the target is
> now resolved *before* the effect chain runs — picking happens the moment the
> card is lifted in hand, and the handler receives the already-chosen
> `selected_target`. Read those cells as "this card's `targeting_kind` is
> PILOT / LOCATION / PREVIEW", not as "the handler opens a modal".

| name | Implemented | Behaviour |
|---|---|---|
| `draw:N` | yes | Pull N from deck (reshuffles discard if empty); spawns visual node for the player |
| `search:N` | yes | **Player**: opens CardSelectOverlay search grid — pick exactly N from the deck via 확인. **AI**: same as `draw:N` (random top-of-deck). |
| `discard:N` | yes | **Player**: opens CardSelectOverlay discard pick — pick exactly N via the desc-box "버리기" button, then press 확인 to commit. The played 버리기 card is non-cancellable (no 버리기 취소 button). **AI**: random N from hand. |
| `strategy:N` | yes | +N 작전 점수 to playing side |
| `attack:N` | yes | **Player**: opens CardTargetingOverlay PILOT mode — battle tiles dim, valid enemy pilots ringed, click an enemy to commit. **AI**: random valid pilot (range-aware). Damage = `caster.atk × N`. `pierce` flag annotates 필중; `min_range:N` filters out pilots closer than N. 보호막 absorbs first. |
| `shield_pct:N` | yes | **Player**: PILOT mode → click an ally; gains shield = N% of max_hp. **AI**: random ally. Cleared on 본진 복귀. |
| `recall_ally` | yes | **Player**: PILOT mode → click an ally; teleports to HQ at full HP, shield reset, waypoint reset. **AI**: random ally. |
| `exhaust_choice:N` | yes (random) | Random N from hand → removed (소멸) |
| `engage:N` | yes | **Player**: opens CardTargetingOverlay PREVIEW mode — caster cell + 6 neighbours highlighted, side panel lists participants, 확인 launches the engage modal. **AI**: same modal flow via AiCardPlayer (no longer silent). `exclude_lane` flag propagates. |
| `duel` | yes | **Player**: PILOT mode → click an enemy in range; opens an engage modal restricted to caster + target with the round counter hidden, runs to first KO. **AI**: random enemy in range. Routes through `EngagePhaseManager.start_duel`. |
| `capture_jungle:N` | yes | **Player**: LOCATION mode restricted to enemy-owned jungle/neutral cells in range; flips the picked cell to caster's team for N turns. **AI**: random valid cell. SimulationCore.process_temp_zone_expiries restores the previous owner once `turn_count >= expires_turn`. |
| `move` | yes | **Player**: LOCATION mode → click any cell in `cast_range` (jungle cells included; the lane-pilot displacement recall pulls them back at phase end if needed). **AI**: random valid cell. Caster's `grid_pos` snaps to the picked cell and `BattleSim.anim_pilot_move` plays the tween. `return_left` / `cost_inc_phase` decorators on the same chain run separately. |
| `cost_reduce_engage:N` | yes | One-shot pending discount on the side's next engage card. Stored on `_bs.engage_discount_p/ai`; consumed in `_play_card_direct` / `AiCardPlayer.run_ai_plays`. |
| `cost_reduce_hand:N` | yes | Mutates every card currently in hand — `cost = max(0, cost - N)`. The played card is already gone from hand by the time this fires. |
| `cost_reduce_draw_phase:N` | yes | Phase-bound draw discount; `draw_card` mutates each drawn `CardData.cost` while `_bs.phase_draw_discount_*` is active. Reset on `start_card_phase`. |
| `cost_inc_phase:N` | yes | Phase-bound additive cost bump on every card play during this 작전 단계. Stored on `_bs.phase_cost_inc_*`; consumed by `effective_cost_for`. Reset on `start_card_phase`. |
| `advance:N` | yes | Caster runs `N` mini-ticks of lane-push action through `SimulationCore.advance_pilot`: at each step, resolves combat at the caster's current cell (pilot-vs-pilot or same-lane turret damage) and then either pushes/retreats the caster from the result or steps them one cell along their lane if uncontested. Other pilots in the cell take damage but don't move — the card advances one pilot, not the whole team. |
| `strategy_on_kill` | log only | Stub — emits 예약 log line until the supporting system lands. |

#### Effective cost & affordability
`BattleSim.effective_cost_for(cd, is_player)` is the single source of truth
for "what does this card cost right now?". It applies `phase_cost_inc_*`
(additive) and the one-shot `engage_discount_*` (only when the card has
an `engage` clause), clamped at 0. The affordability highlight in
`highlight_affordable_cards`, the description-box "카드 내기" enable check,
the cost subtraction in `_play_card_direct`, and `AiCardPlayer.run_ai_plays`
all consult this helper so the four cost-modifier effects stay in sync.

### 사용 횟수 / 소멸 routing
`_dispose_used_card(cd, is_player)` runs after every play:
- `keyword == "exhaust"` → removed permanently (소멸)
- `uses > 0` → decrement `remaining_uses`; remove when it hits 0
- `uses == 0` (unlimited) or remaining > 0 → returns to discard pile

### 대상 지정 (CardTargetingOverlay)
- `CardTargetingOverlay.gd` — sibling of `CardPhaseManager`, owns a CanvasLayer
  at layer 11 (above the search/discard overlay's layer 10) that hosts the
  확인 / 취소 buttons plus PREVIEW 모드의 좌/우 팀 패널.
- **There is no modal step any more.** `Mode` is now just "what kind of card is
  lifted in hand": `NONE / INSTANT / PILOT / LOCATION / PREVIEW`. One entry
  point, `start_card_selection(cd, on_confirm, on_cancel)`, is called from
  `CardPhaseManager._select_card` the moment a card is lifted; `clear_selection()`
  runs from `deselect_current_card`. The hand and 턴 넘기기 stay live throughout
  — the player can switch to a different card mid-pick, and
  `_is_player_input_blocked()` / `can_end_card_phase()` no longer consult this
  overlay at all.
- **Nothing is spent until 확인.** Cost deduction, card destruction and the
  effect chain all happen in `_play_card_direct(card, pre_target)`, which the
  overlay's confirm callback (`_on_selection_confirm`) invokes with the already
  resolved target. That removed the whole targeting-cancel refund path — 취소
  is now just `deselect_current_card()`. (The snapshot/refund machinery still
  exists for 버리기 / 찾기 clauses, which mutate state mid-chain.)
- **Confirm gating**: `set_play_allowed(bool)` carries
  `CardPhaseManager.card_is_playable(cd)` (cost + 시전자 생존 + 유효 대상) into
  the overlay; the button's `disabled` is `not (play_allowed and
  has_required_pick())`. `has_required_pick()` is true immediately for PREVIEW /
  INSTANT and only after `pending_pick` is set for PILOT / LOCATION.
  `highlight_affordable_cards()` re-pushes the verdict, so a 시전자 killed by an
  engage earlier in the same phase disables 확인 on the lifted card.
  `_on_selection_confirm` re-checks `card_is_playable` rather than trusting the
  button state.
- **Buttons live at the bottom-left**, just above the Deck counter:
  확인 at `(BTN_SIDE_MARGIN, BS_HAND_CENTER.y − BTN_HAND_GAP − BTN_H)` =
  (24, 1434), 취소 one `BTN_W + CONFIRM_BTN_GAP` to its right at (216, 1434).
  They used to sit at the top-**right** of the hand row; `HudBuilder` still
  derives the 전략 포인트 도넛's y from `BTN_HAND_GAP + BTN_H`, so the donut
  keeps clearing the button band.
- **Battlefield clicks are swallowed** in PILOT / LOCATION mode — hit *or*
  miss. `_unhandled_input` calls `get_viewport().set_input_as_handled()`
  unconditionally, because `CardPhaseManager._unhandled_input` would otherwise
  read a tap a few px off a pilot marker as "clicked outside" and drop the
  selection along with the pick. The overlay is added to `BattleSim` after
  `CardPhaseManager` and unhandled input walks the tree back-to-front, so it
  gets first refusal. Exits are 취소, a re-click on the card, or selecting a
  different card.
- **Pending pick**: a click on a valid pilot or cell stores it as
  `pending_pick`. `BattleRenderer._draw_pending_pick_highlight()` paints a cyan
  ring on the picked pilot marker (or a thicker cyan outline on the picked
  cell) so the player can confirm or pick a different valid target.
- Driven by `CardData.cast_method` / `target` fields (see `targeting_kind`):
  - `cast_method == "target"` (target=enemy/ally/pilot) → **PILOT** mode.
    BattleRenderer paints a soft yellow fill on every cell within
    `cast_range` and a black overlay on every cell outside it. Pilots not in
    `valid_pilots` get a per-marker black overlay. There is no per-pilot
    ring on the tile — the visible pilot marker IS the click target.
    Range honours `cd.cast_range` and the `min_range:N` flag (저격).
  - `cast_method == "location"` → **LOCATION** mode. Same yellow range fill
    + black out-of-range dim as PILOT. Valid cells (subset, e.g. 약탈's
    enemy-jungle filter) get an extra green outline. All pilots dim via
    BattleRenderer's per-marker dim.
  - `cast_method == "range" and target == "caster"` → **PREVIEW** mode
    (engage cards only; 전진은 target=enemy 라 PREVIEW 가 아니라 즉시 발동).
    The caster cell and 6 neighbours show a soft yellow fill with full outline.
    Two side panels — **좌측 = 아군 팀, 우측 = 적군 팀** — list each
    alive participant with the pilot face image (`PilotImages.face_for`),
    role/팀 라벨, HP 텍스트, HP 프로그레스 바. 카드를 고른 즉시 패널이
    뜨고, 따로 찍을 대상이 없으므로 확인은 처음부터 활성이다. 확인 →
    `_play_card_direct(card, null)` 가 비용 차감 / 카드 파괴 / effect chain
    실행을 한꺼번에 수행한다. Cells outside the engage area also get the
    black out-of-range dim.
  - anything else → **INSTANT**. No caster, no range, nothing painted on the
    battlefield (`is_visualizing()` is false, so BattleRenderer skips the dim
    entirely) — only the 확인 / 취소 row appears.
- Hit-testing:
  - **PILOT mode** uses `_hit_test_pilot` — for each valid pilot it probes
    both the tile centre and the team-direction marker offset position
    (returned by `BattleSim.pilot_marker_pos_solo`) and picks the closest
    pilot whose marker is within `hex_size * 0.85` of the click.
  - **LOCATION mode** keeps the cell-centred hit test (`_hit_test_cell`).
- The 전략 포인트 도넛 is **no longer locked** while a card is selected — with
  the modal gone there is nothing to protect: 턴 넘기기 during a selection just
  ends the phase, and `end_card_phase` opens with `deselect_current_card()`
  which tears the overlay down.

### AI 카드 사용 애니메이션 (AiCardPlayer)
- `AiCardPlayer.gd` — sibling of `CardPhaseManager`, runs the AI's hand
  one card at a time inside `end_card_phase()`'s `await` chain.
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
  effect chain. `engage` cards now route through
  `EngagePhaseManager.start_engage()` (no longer `resolve_silent`); the
  loop `await`s the new `engage_finished` signal so the modal fully
  resolves before the next AI play starts.
- `_ai_play_in_progress` blocks re-entry of `end_card_phase` and disables
  the donut's 턴 넘기기 face (via `can_end_card_phase`). It also gates
  `on_card_clicked` / `on_card_hovered` so the player can't pop the
  description box mid-AI animation.

### 버리기 / 찾기 modal pick (player only)
- `CardSelectOverlay.gd` (sibling of `CardPhaseManager`, instantiated from
  `BattleSim._ready` once the HUD canvas exists). Owns one
  `CanvasLayer` (`layer = 10`) and rebuilds its UI on every `start_*()`.
  AI plays bypass this overlay and keep the synchronous `apply_card_effect`
  path (random discard, search aliased to draw).
- **Async chain pattern** in `CardPhaseManager._play_card_direct`:
  1. Snapshot `player_hand` / `player_deck` / `player_discard` /
     `player_cost` BEFORE deducting cost or removing the played card. Stored
     on `_pending_play.snapshot`.
  2. `_process_pending_chain()` walks `_pending_play.clauses` via
     `pop_front`. Synchronous clauses dispatch through `_apply_single_effect`
     and append a log line. `discard:N` / `search:N` parks the remaining
     clauses on `_pending_play` and starts the overlay, returning early.
  3. The overlay's complete callback (`_on_discard_overlay_complete` /
     `_on_search_overlay_complete`) writes the picks to the discard pile or
     hand respectively, then calls `_process_pending_chain()` again to
     continue the chain.
  4. When the chain drains, `_finalize_pending_play()` disposes the played
     card (사용 횟수 / 소멸 routing) and writes the combined log line.
- **Cancel = full refund** (`_on_overlay_cancel` → `_restore_from_snapshot`):
  freezes any active selection, frees every player card node, restores
  hand/deck/discard/cost from the snapshot verbatim, and respawns nodes for
  every CardData now back in `player_hand`. This rolls back even prior
  clauses in a chain (e.g. cancelling 교환 returns the 2 drawn cards to the
  deck along with refunding the 교환 card itself).
- **Discard mode UI** (`Mode.DISCARD`):
  - **Battle dim** = `ColorRect` covering y=0..BS_HAND_CENTER.y, parented
    into `_bs.canvas` and moved to child position 0 so HUD + hand still
    draw on top of it.
  - Hand stays clickable; clicking a card opens the standard description
    box, but `_show_description_box` swaps the action button to "버리기"
    while `card_select_overlay.can_pick_for_discard()` is true.
  - Picked cards are reparented to a centered fan above the dim
    (`TO_DISCARD_CENTER_Y = 700`, fan width = `BS_HAND_WIDTH`, same spacing
    rules as the hand row). Once parked there their `mouse_filter` is set
    to `IGNORE` so the fan can't be re-clicked while the player commits.
  - **No auto-commit and no cancel.** A 버리기:N card is non-cancellable:
    the only top-right button is **확인**, disabled until exactly
    `target_count` cards are in the to-discard fan. `target_count` is
    clamped to `min(N, hand.size())`. Pressing 확인 is the sole exit.
  - Bottom-left **숨김** (toggles `hidden_state`; relabels to **표시** while
    hidden, drops any active card selection on press) is still available
    so the player can peek at the battle before committing.
- **Search mode UI** (`Mode.SEARCH`):
  - **Full dim** covers the whole viewport on the high-priority overlay
    layer, dimming both battle and hand.
  - `ScrollContainer` at (`SEARCH_GRID_SIDE_PAD`, 220) holds a 5-column
    layout of all `player_deck` cards. Cards are spawned with
    `is_player_card=false` so `Card._on_mouse_entered` short-circuits and
    its hover-brighten tween doesn't fight the `SELECTED_TINT` modulate; a
    transparent flat `Button` child captures clicks ahead of `Card._gui_input`.
  - Bottom-left **숨김**, bottom-right **찾기 취소**, **확인** to its left.
    확인 stays disabled until exactly `target_count` cards are selected
    (`target_count = min(N, deck.size())`); on commit, picks move from
    `player_deck` to `player_hand` (capped at `MAX_HAND_SIZE`) and visual
    nodes spawn via `spawn_card_node`.
- **Phase-end gate**: `can_end_card_phase()` returns false while
  `card_select_overlay.is_active()` so the player can't 단계 넘기기 their
  way out of an unfinished pick.
