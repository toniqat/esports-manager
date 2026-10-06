# Mobile screen support — safe area / aspect ratio / gesture zones

This document is the repo's single answer to **where UI may and may not be placed**. Read it
before building a new screen, and check against the "Checklist" below when done.

Three core propositions:

1. **Don't put per-device value tables in code.** Devices multiply every year, and with
   foldables · tablets a table can't keep up. Insets are **asked of the OS at runtime.**
2. **The bottom of the screen isn't covered — it steals touches.** The swipe to go home takes
   priority over the app, so a button placed there is **visible but not pressable.**
   The top notch, by contrast, only covers things, a much lighter problem.
3. **Margins are applied per screen, not per element.** Move only the title down and the body
   stays put, so the two overlap (the title screen's title really did slide under the save slot
   cards — the bug that prompted this document).

---

## 1. Aspect ratio — what `expand` does

`project.godot`:

```
window/size/viewport_width=1080
window/size/viewport_height=1920
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"      ← previously absent (= default keep)
```

`expand` in one line: **the narrow axis stays at the base value and only the wide axis grows.**
The scale is `min(screenW/1080, screenH/1920)`, and the leftover axis is stretched at that scale.

| Device form | Screen | Viewport | Meaning |
|---|---|---|---|
| 9:16 (base) | 1080×1920 | **1080×1920** | Design as-is |
| iPhone 15 Pro (9:19.5) | 1179×2556 | **1080×2341** | Width exactly 1080, only height grows |
| Galaxy S series (9:19.3) | 1080×2340 | **1080×2340** | 〃 |
| iPad (3:4) | 1536×2048 | **1440×1920** | Height 1920, width widens |

**So the viewport never gets smaller than the base value.** Two conclusions that matter in
practice.

* **On phones the width is always exactly 1080.** The `1080` width literals scattered through
  the code are off by not a single pixel on phones. What needs care is **height**.
  (To be exact on tablets too they'd need to become `ScreenMetrics.vp_w()` / `center_x()`; the
  list is under "Remaining work" below.)
* Tall phones get **roughly 400px of extra height.** How that slack is used is the placement
  convention in §3 below.

### Why the default `keep` was dropped

`keep` insists on 9:16 and fills the rest with black bars. On current phones about 200px each
is left black top and bottom. Coincidentally those bars **cover** the notch and home indicator,
so the safe area problem vanishes by itself, but at the cost of throwing away 17% of the
screen. We chose to use the whole screen, so we handle insets ourselves.

---

## 2. The four unusable bands

### Top — status bar / notch / Dynamic Island

**Covered.** Text placed here overlaps the clock·battery or is clipped by the island.
It can still be pressed.

Typical values (**for reference only — don't write them in code**):

| Device | Top inset (portrait) | This project's viewport units |
|---|---|---|
| iPhone SE series (home button) | 20pt | ~58 |
| iPhone X – 14 (notch) | 44pt | ~120 |
| iPhone 14 Pro / 15 and later (Dynamic Island) | 59pt | **~162** |
| Android status bar | ~24dp | ~65–110 |
| Android cutout | Varies by manufacturer | — |

Converting pt → viewport units means multiplying by `1080 / screenWidth(pt)`. iPhone 15 Pro is
393pt wide, so 59pt × (1080/393) ≈ 162.

### Bottom — home indicator / gesture bar

**Steals touches.** The most important zone in this document.

| Device | Bottom inset (portrait) | Viewport units |
|---|---|---|
| iPhone (all models with a home indicator) | 34pt | **~90–93** |
| iPhone SE series | 0 | 0 |
| Android gesture navigation | ~24dp | ~65–90 |
| Android 3-button navigation | 0 if the bar is outside the window | 0 |

### Left/right — Android back gesture

Android 10+ gesture navigation takes **about 24dp on each side edge** for the "back" swipe.
**The OS does not report this as safe area** — if it did, every Android device would have to
give up 48dp of width.

So it is **not included** in `ScreenMetrics.insets()` either. Instead
`ScreenMetrics.gesture_edge_w()` answers only as a warning line. Rule:

> **A horizontal drag that starts at the edge** may be eaten by the system. Taps are fine.

In this game the only affected spots are **the cards at both ends of the hand (손패) fan**. The
root fix is Android's `setSystemGestureExclusionRects`, but Godot doesn't expose it, so for now
it stays a **known limitation** (§7).

### Others — folding screens / multi-window

This project is `window/handheld/orientation=1` (portrait locked) and does not assume
multi-window. If the window size changes on a foldable the viewport changes too, but current UI
computes positions **once at build time**, so it doesn't relayout (§7).

---

## 3. This repo's conventions

All screen coordinates pass through **`resources/ScreenMetrics.gd`**. It is a collection of
static functions, so no node is needed (it reads the window's root viewport directly).

```gdscript
ScreenMetrics.viewport_size()   # current viewport (after stretch)
ScreenMetrics.vp_w() / vp_h()
ScreenMetrics.insets()          # (left, top, right, bottom) — viewport units
ScreenMetrics.top_y()           # first usable y
ScreenMetrics.bottom_y()        # last usable y  ← bottom edge for touch targets
ScreenMetrics.safe_h()          # safe area height (pattern B below only)
ScreenMetrics.center_x()        # instead of hardcoded 540
ScreenMetrics.gesture_edge_w()  # Android back-gesture edge (warning line)
```

There are **only three** placement patterns. New UI must belong to one of them.

### Pattern A — in-game HUD: shift whole blocks

The constants in `features/battle_sim/ui/HudBuilder.gd` stay **at the 1080×1920 design
values**, and two scalars shift the top/bottom blocks wholesale.

```gdscript
HudBuilder.top_offset()      # = ScreenMetrics.top_y()
HudBuilder.bottom_offset()   # = ScreenMetrics.bottom_y() − 1920
```

Top panel ↔ opponent hand peek ↔ enemy donut ↔ kill log interlock pixel by pixel
(the "chain" in the HudBuilder header), and the bottom is the same with hand fan ↔ card bottom
edge ↔ ally strip. **Adapting constants one by one per device silently breaks those
relations.** Two scalars preserve them all.

`BattleSim.BS_HAND_CENTER.y` also rides the same `bottom_offset()` in `_ready` — so the
hand ↔ strip gap is the same on every device.

### Pattern B — outgame screens: shift the whole screen down and hang from the bottom

Season / MatchFlow / title screens draw with absolute coordinates in one full-screen Control.
The first line of the build function shifts the whole screen down.

```gdscript
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)      # or (_panel)
	...
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenMetrics.extend_background(bg)          # only the background covers the notch area
```

The shift is done with **`offset_top`**, not `position` — the anchors overwrite `position` of a
full-screen-anchored Control on the next layout.

**Inside a shifted screen, don't use `bottom_y()`.** It is in viewport coordinates, so the
shift amount gets added twice. The local coordinate bottom is **`safe_h()`**.

```gdscript
# bottom action bar — if the design screen left 80px to the bottom
var y: float = ScreenMetrics.safe_h() - 80.0 - h
```

Why background handling has two branches: if the background is a **child `ColorRect`**,
just stretch it upward with `extend_background(bg)` (all season views); if the background is
**the panel's own StyleBox**, the panel can't be stretched (stretching moves the inner
coordinate system too), so `backfill_top(_panel, color)` lays a single band as the first child
(the 4 MatchFlow screens).

> The notch area is **a place not to use**, not **a place to leave empty**. If the background
> retreats too, that band alone stays the engine's default background colour and the screen
> looks cut off.

### Pattern C — full-screen modal: dim = viewport, content = absolute coordinates

Engage stage (교전 무대) · pilot (파일럿) detail · card picker · pile browse · reward FX.

```gdscript
dim.size = ScreenMetrics.viewport_size()   # always the whole viewport
```

**If the dim doesn't cover the whole viewport, an uncovered band remains at the screen edge.**
The old `Vector2(1080, 1920)` literal was exactly that bug. Content may stay at absolute
coordinates (see §7 "Remaining work"); only buttons attached to the bottom of the screen hang
from `bottom_y()`.

---

## 4. New UI checklist

- [ ] **Does no touch target's bottom edge go past `ScreenMetrics.bottom_y()`?**
      If it does, it's visible but not pressable.
- [ ] Do titles · status displays start below `ScreenMetrics.top_y()`?
- [ ] Does the background cover the whole screen, **not** just the safe area?
- [ ] Is the full-screen dim `viewport_size()` (not a `1920` literal)?
- [ ] When centring vertically, is it based on the viewport / safe area, not
      `1920 * 0.5`?
- [ ] Inside pattern B screens, did you use `safe_h()` instead of `bottom_y()`?
- [ ] Does no horizontal drag start at the screen edge (Android)?
- [ ] **Are tap targets placed inside a `ScrollContainer` `MOUSE_FILTER_PASS`?**
      (§5). If STOP, scrolling on that screen dies completely on the phone.

---

## 5. Scrolling — making it roll under a finger

There's a trap where a `ScrollContainer` that works fine on desktop **doesn't move at all, only
on the phone**. The cause is neither aspect ratio nor safe area but **input propagation**.

> **Outgame scrolling currently doesn't use the engine path** — `resources/DragScroll.gd`
> receives mouse and (emulated) touch through one path and scrolls directly, cancelling the
> pressed button the moment the threshold is crossed. How to attach it and its conventions: the
> `DragScroll.gd` section of `resources/README.md`. Below is the record of why the engine path
> died; rule (1), that tap targets must be PASS, is still needed for `DragScroll` (the press
> must reach the scroll for detection to start — `DragScroll` itself demotes STOP below the
> scroll to PASS). What you get dragging with a desktop mouse is what you get on the phone.

### Why it dies

Godot's drag scrolling turns on when `DisplayServer.is_touchscreen_available()` is true, but
what that implementation reads is not touch events but **mouse press / motion emulated from
touch** (`emulate_mouse_from_touch`, on by default). That is, the `ScrollContainer` must
**receive that press directly** for the drag to start.

But `Control`'s default `mouse_filter` is `STOP`, and **STOP cuts off parent propagation of mouse
events**. If grid cells are `Button`s (STOP by default) or the body `Control` holding the cells
is left at default, then the moment a finger starts on top of them the `ScrollContainer` never
sees the press. Since cells cover the scroll area without gaps, **it won't roll wherever you put
your finger.**

The reason it doesn't show on desktop is **the wheel** — the engine makes an exception so the
wheel punches through STOP up to the parent, so it scrolls fine with a mouse.

### Rules

1. **Tap targets inside a scroll are `MOUSE_FILTER_PASS`.** PASS receives the event itself and
   also passes it to the parent — taps still work, and when a drag starts the engine cancels
   that press by itself (measured: 0 misfires even with only 10px of movement).
2. **Body `Control`s that aren't tap targets are `IGNORE`.** The scroll body must be excluded
   from hit testing entirely so the `ScrollContainer` receives presses on empty spots directly.
   It's easy to forget that a plain `Control.new()` is STOP.
3. **Tap tolerance is `gui/common/default_scroll_deadzone`.** At the engine default of 0, a
   finger wobbling just a few px makes that gesture count as a scroll and the tap disappears
   (measured: 9px wobble → 26px scroll + button not fired). This repo uses **24** (viewport
   pixels, about 9pt on an iPhone at 1080 width). Scrolling itself loses nothing — movement
   after the threshold is reflected in full.

### Verifying on desktop

Rolling with the wheel is **not** verification (it always succeeds due to the exception above).
Turning on `Input.set_emulate_touch_from_mouse(true)` makes `is_touchscreen_available()` true on
desktop too, taking **the same path** as the phone. Then feed `InputEventScreenTouch` →
`ScreenDrag` ×N → `ScreenTouch(released)` via `Input.parse_input_event()` and see whether
`scroll_vertical` moves (`parse_input_event` goes through the stretch transform, so give
coordinates in **window** coordinates).

Caution: on tall phones (9:19.5) some screens fit everything so the scroll range is exactly 0
(the draft grid is like that). Verification must be done on the **9:16 side** to reproduce.

---

## 6. Verifying on desktop

Insets can be **simulated** without a device. `ScreenMetrics` reads an override — env var
`ESM_SAFE_AREA="좌,위,우,아래"` (left,top,right,bottom; viewport units) or the user argument
`-- --safe-area=0,162,0,90`.

Simulate device form with the window ratio (`--resolution`). The viewport is stretched even if
the window is small, so only the ratio needs to match.

```bash
# 9:16 base — must not differ by a single pixel from before
godot.exe --path <proj> --resolution 540x960 res://scenes/Lobby.tscn

# iPhone 15 Pro form (9:19.5) + Dynamic Island + home indicator
ESM_SAFE_AREA=0,162,0,90 \
godot.exe --path <proj> --resolution 540x1170 res://scenes/Lobby.tscn
```

For screenshots, the simplest way is to launch windowed without `--headless` and save from
inside the game (`await RenderingServer.frame_post_draw` → `get_viewport()
.get_texture().get_image().save_png(...)`).

**Headless can't be used for this verification** — the dummy display server ignores
`--resolution` and reports the window size as 1920×1920 (measured). Always launch windowed.

### Measured (after wiring)

`ESM_SAFE_AREA=0,162,0,90`, window 540×1170 → viewport 1080×2340, safe area
y 162..2250.

| Item | 9:16 · inset 0 | Tall screen · with insets |
|---|---|---|
| Top panel | y 0 .. 248 | y 162 .. 410 |
| Ally strip backplate bottom edge | 1898 (22 to the bottom) | 2228 (**22** to the safe bottom) |
| Hand row y | 1370 | 1700 |
| Kill log top edge | 256 | 418 |
| Draft bottom bar | 1702 .. 1900 | 2032 .. 2230 |
| Draft thumbnail grid height | 950 | **1280** (one more row visible) |
| Card picker hide button bottom edge | 1886 | 2216 |

The 9:16 column is **exactly the same as before wiring.** The point of this design is that with
0 insets both offsets are 0, so the old layout comes out unchanged.

---

## 7. Known limitations / remaining work

Knowing what is **not fixed** matters more than what is.

1. **Pattern C modals' vertical layout is pinned to the top.** The engage stage · pilot detail ·
   draft detail are drawn to fill 1920 in height, so with a 2340 viewport there's an empty band
   of about 400px at the bottom. **It's not a functional problem** (content ends at 2010 and the
   safe bottom is 2250, so nothing falls into the gesture zone).
   To fix, give each modal a `_content` node separate from the dim and position it with
   `ScreenMetrics.design_offset()` — that helper already exists.
2. **Several horizontal `1080` literals remain.** On phones the viewport width is exactly 1080
   so they're harmless; **only on tablets** centring goes off.
   Targets are the `(1080.0 - w) / 2.0` forms in season views and the fixed column coordinates
   in `BanPickController` · `PilotDetailPanel`.
3. **No relayout when the window size changes.** Positions are computed once when the screen is
   built. Portrait-locked + full-screen means no problem on real devices, but folding/unfolding
   a foldable or Android multi-window breaks it. If needed, hook a rebuild to
   `get_viewport().size_changed`.
4. **The app can't reclaim the Android back-gesture zone** (§2).
5. **`ScreenMetrics` reads the root viewport.** If UI is ever placed inside a `SubViewport`,
   this table must not be used there.
6. **A floor on the bottom inset (4% of viewport height) applies only on Android.** iOS trusts
   the OS value as-is — a floor there would throw away the bottom 4% of the screen for no reason
   on home-button devices (where the bottom inset really is 0).

---

## 8. Primary sources

Look only when you need to check device tables directly. Code must still ask the OS.

| What | Where |
|---|---|
| iOS safe area · home indicator · Dynamic Island | Apple *Human Interface Guidelines* → Layout |
| Android display cutout · edge-to-edge insets · gesture navigation | Android Developers → *Display cutout*, *Edge-to-edge*, *Gesture navigation* |
| Godot-side API | `DisplayServer.get_display_safe_area()`, `DisplayServer.get_display_cutouts()` (Android only), `ProjectSettings` → `display/window/stretch/*` |

Godot has **no** built-in node like `SafeAreaContainer`. `resources/ScreenMetrics.gd` fills
that gap.
