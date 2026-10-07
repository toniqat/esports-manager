# build/ — where build outputs go

**The only committed file in this folder is this README.** Everything else is blocked by
`.gitignore` (`/build/*` + `!/build/README.md` — if the directory itself were ignored, git
would not descend into it and the inner exception would not apply, so it is `/build/*`, not
`/build/`).

This is **where things to install on the phone go**. It is where Sideloadly picks files up, the
only folder you touch by hand, so there is one rule.

---

## Rule — after running a CI build, download its `.ipa` here

Don't stop at sharing the artifact link. **Right after confirming green, do four things.**

1. **Delete stale outputs** — old `.ipa` / `.pck` files in this folder.
2. **Download both new `.ipa`s** (every run bakes `debug` and `release`) — append **the short
   SHA of the built commit** to each file name:
   `EsportsManager-debug-unsigned-<sha>.ipa`, `EsportsManager-release-unsigned-<sha>.ipa`.
   Install **release** to judge performance (heat, frame rate); debug is for logs / debugger.
3. **Do a one-line check of what's inside** (below).
4. Report including that result.

```powershell
$gh  = "C:\Program Files\GitHub CLI\gh.exe"   # not on PATH — call by full path
$tmp = "$env:TEMP\ipa-dl"
& $gh run download <run-id> -R toniqat/esports-manager -D $tmp
$sha = git rev-parse --short HEAD
# EsportsManager-<debug|release>-unsigned.ipa → same name + -<sha>
Get-ChildItem -Recurse $tmp -Filter *.ipa | ForEach-Object {
    Move-Item $_.FullName ("build\" + $_.BaseName + "-$sha.ipa") -Force
}
Remove-Item -Recurse -Force $tmp
```

### Why append the SHA

If stale builds mix into this folder, **you can't tell which one was just built.**
This actually happened once — the `.ipa` of the previous commit (`6a1508f`), which had no
haptics at all, was still here and nearly got installed on the phone. The date is the download
time so it doesn't answer the question; only the commit answers "what's inside".

---

## Check — what's inside this `.ipa`

An `.ipa` is just a zip, so open it with Python. **No Mac or `nm` needed** — in fact `nm` has
a record of missing symbols in a ~100MB binary (measured). Names sit in plain text in the
string table, so scan the bytes directly.

```python
import zipfile
z = zipfile.ZipFile('build/EsportsManager-debug-unsigned-<sha>.ipa')
b   = z.read('Payload/EsportsManager.app/EsportsManager')      # executable binary
pck = z.read('Payload/EsportsManager.app/EsportsManager.pck')  # game data

print('네이티브 햅틱:', all(n in b for n in [
    b'register_haptics_types',
    b'_OBJC_CLASS_$_UIImpactFeedbackGenerator',        # light / medium / heavy
    b'_OBJC_CLASS_$_UISelectionFeedbackGenerator',     # SELECT
    b'_OBJC_CLASS_$_UINotificationFeedbackGenerator',  # SUCCESS / WARNING / ERROR
]))
print('game.db:', b'data/game.db' in pck)   # if missing, it dies with a DB error from the title screen
```

(`'네이티브 햅틱:'` = "Native haptics:" — printed label.)

- **Native haptics** — **all four** must be present. Checking only the first two was proven
  insufficient: the upstream plugin binds only the three impact styles, and those two were
  present, so **two-thirds of the feel was silent on the phone yet passed the check**
  (button release · training tile drag · match win/loss · objective capture were all silent).
  In this build only the plugin calls the last two classes, so their references are the proof
  that "more than the three impact styles got in". If any is missing, see
  `ios/plugins/README.md`.
- **`data/game.db`** — it is not a resource and enters the pck only via `include_filter`, so
  if the filter silently misses, the build is green but the game stops.

---

## A local (Windows) export cannot produce an `.ipa`

`godot --export-debug "iOS" build/ios/…` produces **only the Xcode project and the pck**
(an `.ipa` needs `xcodebuild`, which is macOS-only). Those outputs pile up in `build/ios/` and
are for checking, in 25 seconds, **things that can be verified without macOS** such as export
options · plugin wiring. What goes on the phone is always the CI artifact.

Procedure · constraints · Sideloadly install steps: **`docs/ios_testbuild.md`**.


## Detail moved from root CLAUDE.md

## iOS test build (without a Mac)

`.github/workflows/ios-testbuild.yml` runs, on GitHub's **macOS runner**, one job per build type
(`debug` and `release` in parallel), `Godot --export-debug|--export-release "iOS"` → `xcodebuild` → `Payload/*.app` → zip and uploads an
**unsigned `.ipa`** as an artifact. Download it and push it to the iPhone with **Sideloadly**
on the Windows PC — Sideloadly signs locally with a free Apple ID, so **CI has no certificates
or secrets** (`CODE_SIGNING_ALLOWED=NO`). The repo is public, so the macOS runner is free.
Procedure · constraints · failure table: **`docs/ios_testbuild.md`**.

### After running a build, download the `.ipa` into `build/`

**Don't stop at sharing the artifact link.** `build/` is the only folder you touch when
installing to the phone with Sideloadly, so right after confirming CI green do four things —
(1) **delete the stale `.ipa` / `.pck`** in that folder, (2) download the new `.ipa`s as
**`EsportsManager-<debug|release>-unsigned-<commit short SHA>.ipa`**,
(3) check the contents (`data/game.db` inside the pck,
`register_haptics_types` + `OBJC_CLASS_$_UIImpactFeedbackGenerator` inside the executable),
(4) report including that result.

**The reason for the SHA in the file name** is that when stale builds mix in, you can't tell
which one was just built — an `.ipa` from the previous commit, with no haptics at all, really
did nearly get installed on the phone. The date is the download time, so it doesn't answer.
Commands and check snippet: **`build/README.md`**.

**A local (Windows) export cannot produce an `.ipa`** — it yields only the Xcode project and
the pck (`build/ios/`), which are for checking, in 25 seconds, things verifiable without macOS
such as export options · plugin wiring. What goes on the phone is always the CI artifact.

---

Godot does not call `xcodebuild` itself because of
`application/export_project_only=true` in `export_presets.cfg` — we want signing fully off,
so we take only the Xcode project and keep control of the build flags ourselves.
