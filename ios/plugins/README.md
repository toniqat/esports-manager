# Where iOS plugins go

Godot's iOS exporter **reads this folder** and links static libraries into the Xcode project it
generates. This happens at the Xcode project *generation* step, so it doesn't conflict with our
CI pipeline of `export_project_only=true` + `xcodebuild`.

## Haptics — **built by CI. Not committed to the repo**

The binaries are caught by `.gitignore`; on every iOS build
`.github/workflows/ios-testbuild.yml` builds them and places them here:

```
ios/plugins/haptics/
├── haptics.release.a   ← linked by --export-release
├── haptics.debug.a     ← linked by --export-debug
└── haptics.gdip
```

**The reason for not committing is version lock.** Old-style `.gdip` plugins are bound to the
engine headers **at compile time**, so if a `.a` were pinned in the repo, the moment the
workflow's `GODOT_VERSION` is bumped the stale binary would **silently** stop matching.
Rebuilding every time against that version's headers makes that accident structurally impossible.

### The file names are the convention

If the `haptics.a` that the `.gdip`'s `binary=` points to **exists in place, Godot uses only
that** (regardless of export type). If not, it looks for the **pair** `haptics.release.a` and
`haptics.debug.a` and links the one matching the export type. We ship the pair — a static
library is bound to engine symbols, so there's no reason to link a release plugin into a debug
export. **Putting a file named `haptics.a` here disables that selection entirely.**

Confirmed by measurement (put two dummy `.a` files in and exported on Windows) —
`--export-debug` picks `haptics.debug.a`, `--export-release` picks
`haptics.release.a`, and both end up under one name at the destination:
`<앱>/ios/plugins/haptics/**haptics.a**` (`<앱>` = `<app>`).

### The fork is not a copy of upstream — it binds the whole feel table

**Upstream `kyoz/godot-haptics`'s iOS plugin binds only three: `light` / `medium` / `heavy`.**
`_bind_methods()` has just those three and the rest have no implementation at all.
But `autoloads/Haptics.gd` is written assuming a wider table and calls
`selection()` · `soft()` · `rigid()` · `notify_success/warning/error()` ·
`prepare()` · `is_supported()` · `impact(style, intensity)` — **all nonexistent methods**.

Calling a nonexistent method makes GDScript throw a runtime error on the spot and silently move
on. Since `_plugin != null`, it doesn't even take the `Input.vibrate_handheld` fallback. The
resulting symptom was **"the plugin linked fine but two-thirds of the feel was silent"** —
buttons buzzed only on press (`LIGHT`) and were silent on release (`SOFT`), training tile drag
was missing all three beats of pick up · preview · drop (`SELECT` · `SELECT` · `SOFT`), and
match win/loss · objective capture · save delete · ending (`SUCCESS` / `WARNING` / `ERROR`) were
all silent. The three gates below were green the whole time — what they check is "is the plugin
there", not "can it be called".

So the rest was implemented and bound in the fork. **Rewinding the fork to upstream brings that
silence right back.** One more thing changed with it — **generators are cached for the process
lifetime**. Upstream created and discarded a `UIImpactFeedbackGenerator` per call, but
`-prepare` warms the Taptic Engine of **that instance**, so an object that dies within the same
run loop takes its warm-up with it. `prepare()` only means something if the object warmed on
press is the same object that buzzes on release.

**The Android side (`android/.../Haptics.java`) still has only three.** CI currently builds only
iOS, so it was left alone — if Android is ever exported, it must be filled in with the same table.

### How it is built

The source is `toniqat/godot-haptics-upstream-fork` (upstream `kyoz/godot-haptics`), and the
headers are `extracted_headers_godot_<버전>.zip` (`<버전>` = `<version>`) from
`kyoz/godot-ios-extracted-headers`. The workflow does **not** use upstream's
`scripts/ios/generate_static_library.sh` — that script also builds armv7 and the x86_64
simulator and lipos them together, but armv7 disappeared in Xcode 14 and simulator slices are
useless for a sideloaded real-device build. Only arm64 is needed, so `scons` is called directly.
The deployment target is also raised 10.0 → 12.0 (the original value is outside the range current
Xcode accepts).

The cache key is `GODOT_VERSION` + plugin source SHA — if either moves, a stale `.a` must not be
reused.

### What blocks the fallback is CI, not documentation

`plugins/Haptics=true` in `export_presets.cfg` is on. But if the `.gdip` isn't read, Godot
**just moves on without a word**, and that combination is exactly "build green, but
`Input.vibrate_handheld` fallback on the phone". So the workflow has three gates:

1. **Plugin check** — the three files exist, `lipo -info` answers arm64,
   `nm` finds the `register_haptics_types` symbol, and the preset has `plugins/Haptics=true`.
   **Also, every method name `Haptics.gd` calls must be inside the archive** — names passed to
   `bind_method` are string literals, so they remain in plain text in `__cstring`. Without this
   check, "plugin present but half unbound" passes green (it actually did — section above).
2. **Export result check** — the plugin `.a` is inside the generated Xcode project, it contains
   the `register_haptics_types` symbol, and **it is in the link phase**. **Mind the name you
   search for** — the exporter copies the chosen one in under the `.gdip`'s `binary=` name, i.e.
   **`haptics.a`**, and the location is `<앱>/ios/plugins/haptics/`, not the project root.
   Searching for the name `haptics.release.a` flags a healthy build as "no plugin" (measured —
   the first CI run stopped here).

   **And "the string haptics is in the pbxproj" is not enough.** The pbxproj keeps
   `PBXFileReference` (such a file exists) and `PBXBuildFile` (it's used in the build)
   separately, and **it is actually linked only when the latter is in the files list of
   `PBXFrameworksBuildPhase`**. The workflow follows the UUID twice and checks in that list.
3. **Final binary check** — inside the `.app` executable,
   `register_haptics_types`, `OBJC_CLASS_$_UIImpactFeedbackGenerator`,
   `OBJC_CLASS_$_UISelectionFeedbackGenerator`, and
   `OBJC_CLASS_$_UINotificationFeedbackGenerator` must **all four** be present. In this build
   nothing but the plugin calls the last two, so their references are the proof that "more than
   the three impact styles was actually linked" — a stale cache sneaking in gets caught here.
   It can fail here even if 1·2 pass: **static archive members are pulled in only when a symbol
   references them**, so even with the `.a` in the link phase, if Godot's generated init code
   drops out, it's dead-stripped wholesale. That case is exactly "build green + fallback on the
   phone", so this check is the last lock.

   **`nm` is not used.** On this 103MB binary, `nm -a` and `nm -mu` both missed both symbols
   (measured — downloading the artifact and scanning the bytes showed both were there).
   The names are in plain text in the string table, so look directly with `grep -a`.

If any of the three fails, the build stops right there.

## Local (Windows) export

Export **passes** even without the plugin — when Godot can't find the `.gdip`, it just ignores
the `plugins/Haptics` key. Installing that build on the phone runs the fallback and prints a
warning once. To feel the real haptics on a device, use the CI artifact
(`docs/ios_testbuild.md`).
