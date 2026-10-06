# iOS test build — running on an iPhone without a Mac

Bake the `.ipa` on a macOS runner lent by GitHub Actions, then push it to the iPhone from a
Windows PC with **Sideloadly**. Not a single Mac is needed.

```
  Windows PC            GitHub Actions (macos-15)              iPhone
  ──────────            ─────────────────────────              ──────
  git push        ──▶   Godot --export-debug "iOS"
                        (generate Xcode project)
                          ↓
                        xcodebuild  CODE_SIGNING_ALLOWED=NO
                          ↓
                        Payload/EsportsManager.app → zip → .ipa
                          ↓
  download artifact ◀──   upload
  Sideloadly (signs with Apple ID) ──────────────────────▶  install
```

---

## Why it is shaped this way

**Signing is not done in CI.** You could put an Apple certificate and provisioning profile in
repo secrets, but that requires a paid developer account ($99/year). Signing with a free Apple
ID is done **locally by Sideloadly**, so CI only needs to produce and hand over an unsigned
`.app` — hence `CODE_SIGNING_ALLOWED=NO` in the workflow and zero secrets.

**An `.ipa` is not a special format.** A `.app` inside a single `Payload/` folder, zipped, is
an `.ipa`. That is exactly what the workflow's last step does.

**Godot is kept from calling xcodebuild itself.** `application/export_project_only=true` in
`export_presets.cfg` is that switch. Leaving it to Godot would mean passing signing settings
through Godot's preset, but we want signing fully off, so we take just the Xcode project and
run `xcodebuild` with our own flags.

---

## Running a build

### Option A — manual (recommended)

1. GitHub repo → **Actions** tab
2. On the left, select **iOS 테스트 빌드 (unsigned IPA)** (iOS test build)
3. On the right, **Run workflow** → leave `build_type` at `debug` and run
4. Done after 10–15 minutes (the first run takes longer, downloading the Godot editor + iOS templates)
5. At the bottom of the run page, under **Artifacts**, download
   `EsportsManager-ios-debug-unsigned-ipa`

### Option B — automatic

Runs automatically on push to the `main` branch (except commits that change only `.md` / `docs/`).

### Unpacking the download — it goes in `build/`

GitHub delivers artifacts **wrapped in one more zip layer**. Unzipping yields
`EsportsManager-debug-unsigned.ipa` — what goes into Sideloadly is **that `.ipa`**, not the
downloaded zip.

**Put that `.ipa` in the repo's `build/` folder** (gitignored, so it is not committed).
Append **the short SHA of the built commit** to the file name
(`EsportsManager-debug-unsigned-<sha>.ipa`) and **delete stale outputs** — if several builds
mix in that folder you can't tell which one was just built (an `.ipa` from the previous
commit, with none of the features in it, really did nearly get installed). The
`gh run download` command and the "what's inside this `.ipa`" check snippet:
**`build/README.md`**.

---

## Fast path — swap only the pck

**If only game code and assets changed, there is no need to run CI.** Just replace the `.pck`
inside the unsigned `.ipa` you already have with a freshly baked local one — 10–15 minutes
becomes a few seconds. Still no Mac needed; Godot on the Windows PC is enough.

The `.app` inside an `.ipa` splits into two parts. **Engine binary + `Info.plist` + icons**
are baked by xcodebuild, and **the whole game (`.pck`)** is baked by Godot. If only the latter
changed, there is no reason to rebuild the former.

### 1. Bake the pck

```bash
godot --headless --path <project path> --export-pack "iOS" build/EsportsManager.pck
```

`--export-pack` has **no** `--export-debug` / `--export-release` distinction — a pck is just
data and debug/release is decided by the engine binary, so it can go into an `.ipa` baked from
either template.

### 2. Replace the pck inside the ipa

```python
import zipfile

SRC, PCK, DST = "build/EsportsManager-debug-unsigned.ipa", "build/EsportsManager.pck", "build/새이름.ipa"
pck = open(PCK, "rb").read()

with zipfile.ZipFile(SRC) as zin, zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zout:
    for i in zin.infolist():
        out = zipfile.ZipInfo(i.filename, date_time=i.date_time)
        # These three lines are the key — external_attr in particular carries the engine binary's exec bit.
        out.compress_type, out.external_attr, out.create_system = i.compress_type, i.external_attr, i.create_system
        zout.writestr(out, pck if i.filename.endswith(".pck") else zin.read(i.filename))
```

(`새이름.ipa` = "new-name.ipa" — pick any output name.)

**`external_attr` must be carried over.** It holds the exec bit (`-rwxr-xr-x`) of
`Payload/*.app/EsportsManager`; if it is lost, Sideloadly installs fine but the app won't
launch. Rewriting the zip itself is safe — this `.ipa` is **unsigned**, so there is no
signature to break (signing happens locally anyway when Sideloadly installs).

After that it's the usual — put the new `.ipa` into Sideloadly.

### Changes this path doesn't cover

| What changed | Works with pck swap? | Why |
|---|---|---|
| GDScript, scenes, images, `data/game.db` | **Yes** | All inside the pck |
| Most `project.godot` settings | **Yes** | Go into `project.binary` inside the pck (e.g. `window/stretch/aspect`) |
| `window/handheld/orientation` | **No** | Baked into `Info.plist` at export time — outside the pck |
| Bundle ID / version / app icon | **No** | Same reason. The icon is baked separately into `Assets.car` |
| GDExtension (godot-sqlite) update | **No** | iOS **statically links** the xcframework into the app binary |
| Haptics native plugin | **No** | Same reason — the `.gdip` static library is also inside the app binary |
| Godot version bump | **No** | The engine binary is that version |

You can see for yourself that GDExtensions live outside the pck — there is not one `.dylib`
inside the `.app`, and the pck has no `addons/godot-sqlite/bin/*` entries (only the
`.gdextension` **text file** listing paths goes in).

### Check

`grep`-ing the pck for the string `data/game.db` only tells you "the path is written there".
To see whether the contents are empty, read **the size field of the file table**.

```python
import struct
f = open("build/EsportsManager.pck", "rb")
assert f.read(4) == b"GDPC"
f.seek(0x20); dir_off, = struct.unpack("<Q", f.read(8))   # in v3 the file table is at the end of the file
f.seek(dir_off); n, = struct.unpack("<I", f.read(4))
for _ in range(n):
    plen, = struct.unpack("<I", f.read(4))
    name = f.read(plen).rstrip(b"\x00").decode()
    off, size = struct.unpack("<QQ", f.read(16)); f.read(16); f.read(4)  # md5 + flags
    if "game.db" in name or name == "project.binary":
        print(size, name)
```

**Godot 4.5's pck is format v3, so the file table is at the end of the file.** The uint64 at
header offset `0x20` is its offset; reading right after the header like old v1/v2 gives you the
lie `files=0`.

Running a `--main-pack` smoke test with the local Windows engine produces an
`Identifier "SQLite" not declared` parse error — **this is normal**: the iOS export merely
dropped the Windows dll, and on the phone the statically linked xcframework fills that role.
This test can only confirm that the pck mounts and the main scene opens.

---

## Installing on the iPhone with Sideloadly

### What you need

- Windows PC + **[Sideloadly](https://sideloadly.io/)** (free)
- **iTunes** (the version from Apple's site — the Microsoft Store version does not work)
  and **iCloud** (also the Apple site version). Sideloadly uses the drivers·libraries these
  two install.
- Lightning/USB-C cable, Apple ID

### Steps

1. Connect the iPhone via USB and tap Trust on the phone's **"이 컴퓨터를 신뢰하시겠습니까?"**
   (Trust This Computer?) prompt.
2. Launch Sideloadly → check that the phone shows up under **iDevice** at the top
3. Drag the `.ipa` into the middle of the window
4. Enter the Apple ID in the **Apple Account** field → **Start**
5. Enter the password and 2FA code (the plain Apple ID password, not an app-specific password)
6. When installation finishes, an icon appears on the phone's home screen.
7. **Trust must be set before the first launch**:
   설정 → 일반 → **VPN 및 기기 관리** → my Apple ID → **신뢰**
   (Settings → General → VPN & Device Management → my Apple ID → Trust)
8. Launch the app

### Free-account signing constraints (important)

| Constraint | Details |
|---|---|
| **7 days** | The signature expires after 7 days. If the app won't launch, **reinstall** with Sideloadly (data is kept, but to be sure see the save location below). |
| **3 apps** | Up to 3 apps can be sideloaded at once per Apple ID. |
| **10 App IDs/week** | Changing the bundle ID repeatedly hits the 10-per-week limit — **keep `com.toniqat.esportsmanager` fixed**. |
| **Reinstall automation** | Sideloadly's *Sideload with Wi-Fi* + PC resident option can set up automatic renewal. |

If renewing expiry is a hassle, a paid developer account ($99/year) gives one-year signatures,
and at that point signing directly in CI and uploading to TestFlight is better — a change on
the order of adding an `-exportArchive` step to this workflow.

---

## What this setup touched

| File | Role |
|---|---|
| `.github/workflows/ios-testbuild.yml` | The whole build pipeline |
| `export_presets.cfg` | iOS export preset (bundle ID, icon, `export_project_only`, `include_filter`) |
| `resources/images/appicon_1024.png` | App icon 1024×1024 (currently the default Godot icon baked from `icon.svg` — to replace it, just overwrite this file) |
| `resources/GameDb.gd` | `GameDb.path()` / `_extract_to_user()` — item below (moved here from `GameManager`) |
| `autoloads/GameManager.gd` | `db_path()` — now just delegates to `GameDb.path()` |
| `features/battle_sim/data/DataLoader.gd` | Uses `GameManager.db_path()` for the same reason |
| `project.godot` | `textures/vram_compression/import_etc2_astc=true` — item below |
| `resources/images/splash_blank.png` | 8×8 transparent PNG that removes the Godot logo from the launch screen — item below |

### `res://data/game.db` → `user://data/game.db`

SQLite must open **a real file on disk**. In the editor `res://` is a real folder, so it just
opens, but in an exported build `res://` lives inside the `.pck` and SQLite cannot open that
path — built untouched, the iPhone build would have stopped at the title screen with a DB error.

So `GameDb.path()` (`resources/GameDb.gd`) splits the path by runtime environment.
It used to live in `GameManager` (`db_path()` / `_extract_db_to_user()`); it moved to a static
class because `ConstTable` needs the DB during `static var` initialisation, possibly before
autoloads exist. `GameManager.db_path()` remains and delegates to it.

- Editor: `res://data/game.db` as-is (CSV→DB rebuilds must take effect immediately)
- Device: **extract once** the DB inside the pck to `user://data/game.db`, then open that copy

**It overwrites on every run.** The DB is read-only at runtime (saves live separately as
`user://saves/*.save` JSON) and only 96KB, so simply copying is always better than a cache
invalidation mechanism that compares what changed — it becomes structurally impossible for an
old build's `game.db` to remain in `user://` after installing a new build.

`data/game.db` is **not a resource**, so by default it is not packed into the pck.
`include_filter="data/game.db"` in `export_presets.cfg` is what includes it, and the
workflow's packaging step actually searches for that string inside the `pck` to confirm — if
the filter silently misses, you get a combination where the build is green but the game dies.

---

### `import_etc2_astc` — if this is off, export dies **silently**

```
rendering/textures/vram_compression/import_etc2_astc=true
```

iOS and Android require this setting, but **its default is false**. When off, Godot refuses
to export yet prints **not a single character** of the reason:

```
ERROR: Cannot export project with preset "iOS" due to configuration errors:
                                          ← this part is completely empty
```

In the editor UI the export window reports it in a separate dialog, but in the headless CLI
that message is not put into `r_error`, leaving only an empty line. Digging through preset
options never reveals the cause, so it's faster to memorize **empty message = this setting**.

Turning it on changes no tracked `.import` files — ETC2/ASTC variants are baked only inside
`.godot/imported/`, which is gitignored. Import time and `.godot/` size grow instead.

### Screen orientation — a leftover Godot 3 string **builds landscape**

```
window/handheld/orientation=1        # 1 = Portrait
```

In Godot 4 this setting is an **integer enum**
(`Landscape,Portrait,Reverse Landscape,Reverse Portrait,Sensor Landscape,Sensor Portrait,Sensor`).
But this project still had the Godot 3-era string `"portrait"`, which Godot 4 could not parse,
so it fell back to **default 0 = Landscape**. That is why the first build's `Info.plist` had
`UIInterfaceOrientationLandscapeLeft` baked in.

It doesn't show in the editor since that's a desktop window — this kind of bug **only appears
on device**, and opening the built `.ipa`'s `Info.plist` once is the only way to check:

```python
import zipfile, plistlib
z = zipfile.ZipFile("EsportsManager-debug-unsigned.ipa")
d = plistlib.loads(z.read("Payload/EsportsManager.app/Info.plist"))
print(d["CFBundleIdentifier"], d["UISupportedInterfaceOrientations"])
```

### Godot splash — the launch screen **can't be removed, only replaced**

Launching the app on the phone shows the Godot logo twice. They are different things, so they
are turned off differently.

| What | When it shows | How to turn off |
|---|---|---|
| **iOS launch screen** | Right after tapping the icon, while the app process starts | Can't — Apple requires this screen and Godot always bakes `Launch Screen.storyboard`. You can only choose **what it contains** |
| **Engine boot splash** | After the app starts, while loading the first scene | `application/boot_splash/show_image=false` |

So three lines are in the `[application]` section of `project.godot`:

```
boot_splash/bg_color=Color(0, 0, 0, 1)
boot_splash/show_image=false
boot_splash/image="res://resources/images/splash_blank.png"
```

- `show_image=false` turns off **only the engine splash**.
- `image` is **read by the launch screen** — Godot 4.5's iOS exporter **doesn't look at**
  `show_image` at all (`editor/export/editor_export_platform_apple_embedded.cpp`) and bakes
  `boot_splash/image` into `Images.xcassets/SplashImage.imageset/splash@2x·@3x.png`.
  If empty it falls back to **the Godot logo built into the engine** — which is why turning off
  only `show_image` leaves the logo on the launch screen. So an 8×8 **fully transparent** PNG
  (`resources/images/splash_blank.png`, 70 bytes) is wired in.
- `bg_color` becomes the storyboard's background colour (unless
  `storyboard/use_custom_bg_color` is on). Transparent image + black background = **one black
  frame**, and that black continues into the engine splash background so the colour never
  breaks up to the title screen.

To add real splash art later, overwrite `splash_blank.png`; to use a different image on iOS
only, fill **both** `storyboard/custom_image@2x` and `@3x` in `export_presets.cfg` (filling just
one is ignored). Display mode is `storyboard/image_scale_mode`
(`0=로고와 동일 · 1=Center · 2=Scale to Fit · 3=Scale to Fill · 4=Scale`; 로고와 동일 = same as logo).

Check — after exporting, confirm the baked splash is not the logo (no Mac needed:
with `export_project_only=true`, the Xcode project is produced even on Windows):

```bash
godot --headless --path . --export-debug "iOS" /tmp/ios/EsportsManager.ipa
ls -la /tmp/ios/EsportsManager/Images.xcassets/SplashImage.imageset/
# 14779 bytes if it's the Godot logo, 85 bytes if it's ours
grep -o '<color key="backgroundColor"[^/]*' "/tmp/ios/EsportsManager/Launch Screen.storyboard"
```

---

---

## Haptics native plugin — how to tell whether the fallback is running

`autoloads/Haptics.gd` **does not crash** without the plugin — it silently degrades to
`Input.vibrate_handheld` and prints a warning once. Convenient design, but it has a cost:
**the build is always green**, and finding out why the feel on the phone is flat means reading
logs. So the verdict was moved to CI.

- The binary is **not committed**. `.github/workflows/ios-testbuild.yml` compiles
  `toniqat/godot-haptics-upstream-fork` on every build against that Godot version's extracted
  headers and places it in `ios/plugins/haptics/` (arm64, cache key = version + source SHA).
- **Three gates** prevent the fallback — (1) the three files exist + `lipo -info` arm64 +
  `register_haptics_types` in `nm` + `plugins/Haptics=true` in the preset,
  (2) the exported `.a` must be in the **Frameworks link phase**
  (checked by following the UUID twice: `PBXFileReference` → `PBXBuildFile` → link phase
  — the string "haptics" appearing in the pbxproj guarantees nothing),
  (3) **inside the final `.app` binary**, both `register_haptics_types` and
  `OBJC_CLASS_$_UIImpactFeedbackGenerator` must be present — static archive members are pulled
  in only when a symbol references them, so the plugin can pass 1·2 and still be dead-stripped
  wholesale. If any of the three fails, the build stops right there.
- The **"햅틱"** (Haptics) line in the job summary (Actions → that run → Summary) reports the result.

**An export produced locally on Windows has no plugin** — when Godot can't find the `.gdip`, it
simply ignores the `plugins/Haptics` key. So always use the CI artifact when checking feel on a
real device. The same goes for the "swap only the pck" fast path above — the plugin is outside
the pck (inside the app binary), so a pck swap never brings it in.

Detailed conventions (why the file names are `haptics.release.a` / `haptics.debug.a`):
`ios/plugins/README.md`.

## When something needs fixing

### After bumping the Godot version

Edit only the two lines at the top of `.github/workflows/ios-testbuild.yml`.

```yaml
GODOT_VERSION: "4.5"
GODOT_RELEASE: "stable"
```

It must be **the same version** as the editor that opened the project — otherwise it fails
with an export template version mismatch.

### Bundle ID / version number

In `export_presets.cfg`:

```
application/bundle_identifier="com.toniqat.esportsmanager"
application/short_version="0.1"
application/version="0.1"
```

Changing the bundle ID makes it **a different app** on the iPhone, so saves don't carry over,
and it also uses one of the free account's 10-per-week App IDs.

### Common failures and causes

| Symptom | Cause |
|---|---|
| `No export template found at .../ios.zip` | `GODOT_VERSION` / `GODOT_RELEASE` don't match the release tag |
| Text after `due to configuration errors:` is **empty** | `textures/vram_compression/import_etc2_astc` in `project.godot` got turned off — item above |
| `.xcodeproj 를 찾지 못했다` (could not find .xcodeproj) | The Godot export step failed — check the log of the step above it |
| Export log ends with `libc++abi: Pure virtual function called!` + `exit 134` | **The export finished and Godot crashed on exit** (`[ DONE ] export` is above it). The workflow now checks whether `.xcodeproj` was produced, not the exit code, and continues leaving only a warning |
| `pck 안에 data/game.db 가 없다` (data/game.db not in pck) | `include_filter` missed |
| The game launches **landscape** on the phone | `window/handheld/orientation` reverted to a string — item above |
| Swapped the pck but **orientation · icon · bundle ID** didn't change | Those three are baked into `Info.plist` / `Assets.car` and live outside the pck — bake a new ipa via CI |
| The app closes right after launching on the phone | Signature expired (7 days) or trust not set → reinstall + trust in Device Management |
| Sideloadly can't find the phone | The Microsoft Store edition of iTunes is installed — replace it with the Apple site version |
| `Unable to install... 0xE8008015` | Free account's 3-app limit exceeded — delete another sideloaded app |

### If you also want to build Android

`godot-sqlite` already ships `android.*.arm64/x86_64` binaries and `GameDb.path()` is
platform-agnostic, so Android needs no macOS runner
(`ubuntu-latest` + `android.zip` template + keystore). Copy this workflow and strip out only
the `xcodebuild` step.
