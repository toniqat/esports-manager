# iOS 테스트 빌드 — 맥 없이 아이폰에서 돌리기

GitHub Actions 가 빌려주는 macOS 러너에서 `.ipa` 를 굽고, 윈도우 PC 에서
**Sideloadly** 로 아이폰에 밀어 넣는다. 맥은 한 대도 필요 없다.

```
  Windows PC            GitHub Actions (macos-15)              iPhone
  ──────────            ─────────────────────────              ──────
  git push        ──▶   Godot --export-debug "iOS"
                        (Xcode 프로젝트 생성)
                          ↓
                        xcodebuild  CODE_SIGNING_ALLOWED=NO
                          ↓
                        Payload/EsportsManager.app → zip → .ipa
                          ↓
  아티팩트 내려받기 ◀──   업로드
  Sideloadly (Apple ID 로 서명) ─────────────────────────▶  설치
```

---

## 왜 이런 모양인가

**서명을 CI 에서 하지 않는다.** 애플 인증서와 프로비저닝 프로파일을 저장소
시크릿에 넣는 길도 있지만, 그건 유료 개발자 계정($99/년)이 있어야 하는 이야기다.
무료 Apple ID 로 서명하는 일은 **Sideloadly 가 로컬에서** 해 주므로, CI 는
서명되지 않은 `.app` 을 만들어 넘기기만 하면 된다 — 그래서 워크플로에
`CODE_SIGNING_ALLOWED=NO` 가 들어가 있고 시크릿이 하나도 없다.

**`.ipa` 는 특별한 포맷이 아니다.** `Payload/` 폴더 하나에 `.app` 을 넣고 zip 한
것이 곧 `.ipa` 다. 워크플로 마지막 단계가 하는 일이 정확히 그것이다.

**Godot 이 xcodebuild 를 직접 부르지 않게 했다.** `export_presets.cfg` 의
`application/export_project_only=true` 가 그 스위치다. Godot 에게 맡기면 서명
설정을 Godot 쪽 프리셋으로 넘겨야 하는데, 우리는 서명을 아예 끄고 싶으므로
Xcode 프로젝트만 받아서 `xcodebuild` 를 우리 플래그로 돌린다.

---

## 빌드 돌리기

### 방법 A — 수동 (권장)

1. GitHub 저장소 → **Actions** 탭
2. 왼쪽에서 **iOS 테스트 빌드 (unsigned IPA)** 선택
3. 오른쪽 **Run workflow** → `build_type` 을 `debug` 로 두고 실행
4. 10~15분 뒤(첫 실행은 Godot 에디터 + iOS 템플릿을 받느라 더 걸린다) 완료
5. 실행 페이지 맨 아래 **Artifacts** 에서
   `EsportsManager-ios-debug-unsigned-ipa` 를 내려받는다

### 방법 B — 자동

`main` 브랜치에 push 하면 자동으로 돈다 (`.md` / `docs/` 만 바뀐 커밋은 제외).

### 내려받은 파일 풀기

GitHub 은 아티팩트를 **zip 으로 한 겹 더 싸서** 준다. 압축을 풀면
`EsportsManager-debug-unsigned.ipa` 가 나온다 — Sideloadly 에 넣을 것은 **그
`.ipa`** 이지 내려받은 zip 이 아니다.

---

## 빠른 길 — pck 만 갈아 끼우기

**게임 코드와 에셋만 바뀌었다면 CI 를 돌릴 필요가 없다.** 이미 손에 있는
unsigned `.ipa` 안의 `.pck` 만 로컬에서 구운 새 것으로 바꿔 치면 된다 — 10~15분이
몇 초가 된다. 맥은 여전히 필요 없고, 윈도우 PC 의 Godot 하나면 끝난다.

`.ipa` 안의 `.app` 은 크게 둘로 나뉜다. **엔진 바이너리 + `Info.plist` + 아이콘**은
xcodebuild 가 굽는 것이고, **게임 전체(`.pck`)** 는 Godot 이 굽는 것이다. 뒤쪽만
바뀌었다면 앞쪽을 다시 만들 이유가 없다.

### 1. pck 굽기

```bash
godot --headless --path <프로젝트 경로> --export-pack "iOS" build/EsportsManager.pck
```

`--export-pack` 에는 `--export-debug` / `--export-release` 같은 구분이 **없다** —
pck 는 데이터일 뿐이고 debug/release 를 가르는 것은 엔진 바이너리 쪽이라, 어느
템플릿으로 구운 `.ipa` 에 넣어도 된다.

### 2. ipa 안의 pck 교체

```python
import zipfile

SRC, PCK, DST = "build/EsportsManager-debug-unsigned.ipa", "build/EsportsManager.pck", "build/새이름.ipa"
pck = open(PCK, "rb").read()

with zipfile.ZipFile(SRC) as zin, zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zout:
    for i in zin.infolist():
        out = zipfile.ZipInfo(i.filename, date_time=i.date_time)
        # 이 세 줄이 핵심이다 — 특히 external_attr 에 엔진 바이너리의 실행 비트가 들어 있다.
        out.compress_type, out.external_attr, out.create_system = i.compress_type, i.external_attr, i.create_system
        zout.writestr(out, pck if i.filename.endswith(".pck") else zin.read(i.filename))
```

**`external_attr` 를 반드시 옮겨야 한다.** 거기에 `Payload/*.app/EsportsManager` 의
실행 비트(`-rwxr-xr-x`)가 들어 있고, 그게 날아가면 Sideloadly 는 멀쩡히 설치하는데
앱만 안 뜬다. zip 을 다시 쓰는 것 자체는 안전하다 — 이 `.ipa` 는 **서명이 없으므로**
깨질 서명이 없다(서명은 어차피 Sideloadly 가 설치할 때 로컬에서 한다).

그 다음은 평소와 같다 — 새 `.ipa` 를 Sideloadly 에 넣는다.

### 이 길이 통하지 않는 변경

| 바꾼 것 | pck 교체로 되나 | 왜 |
|---|---|---|
| GDScript, 씬, 이미지, `data/game.db` | **된다** | 전부 pck 안에 있다 |
| 대부분의 `project.godot` 설정 | **된다** | pck 안 `project.binary` 로 들어간다 (예: `window/stretch/aspect`) |
| `window/handheld/orientation` | **안 된다** | 익스포트 시점에 `Info.plist` 로 구워진다 — pck 밖이다 |
| 번들 ID / 버전 / 앱 아이콘 | **안 된다** | 같은 이유. 아이콘은 `Assets.car` 로 따로 구워진다 |
| GDExtension(godot-sqlite) 갱신 | **안 된다** | iOS 는 xcframework 를 **앱 바이너리에 정적 링크**한다 |
| 햅틱 네이티브 플러그인 | **안 된다** | 같은 이유 — `.gdip` 정적 라이브러리도 앱 바이너리 안이다 |
| Godot 버전 업 | **안 된다** | 엔진 바이너리가 곧 그 버전이다 |

GDExtension 이 pck 밖에 산다는 것은 눈으로 확인할 수 있다 — `.app` 안에 `.dylib`
이 하나도 없고, pck 안에도 `addons/godot-sqlite/bin/*` 항목이 없다(경로 목록을 담은
`.gdextension` **텍스트 파일만** 들어간다).

### 검산

`grep` 으로 pck 안에서 `data/game.db` 문자열을 찾는 것은 "경로가 적혀 있다"까지만
말해 준다. 내용이 비었는지까지 보려면 **파일 테이블의 크기 필드**를 읽어야 한다.

```python
import struct
f = open("build/EsportsManager.pck", "rb")
assert f.read(4) == b"GDPC"
f.seek(0x20); dir_off, = struct.unpack("<Q", f.read(8))   # v3 는 파일 테이블이 파일 끝에 있다
f.seek(dir_off); n, = struct.unpack("<I", f.read(4))
for _ in range(n):
    plen, = struct.unpack("<I", f.read(4))
    name = f.read(plen).rstrip(b"\x00").decode()
    off, size = struct.unpack("<QQ", f.read(16)); f.read(16); f.read(4)  # md5 + flags
    if "game.db" in name or name == "project.binary":
        print(size, name)
```

**Godot 4.5 의 pck 는 포맷 v3 라 파일 테이블이 파일 끝에 있다.** 헤더 `0x20`
위치의 uint64 가 그 오프셋이고, 옛 v1/v2 처럼 헤더 바로 뒤에서 읽으면 `files=0`
이라는 거짓말을 얻는다.

로컬 윈도우 엔진으로 `--main-pack` 스모크 테스트를 돌리면
`Identifier "SQLite" not declared` 파스 에러가 나는데 **이건 정상이다** — iOS
익스포트가 windows dll 을 뺐을 뿐이고, 폰에서는 그 자리를 정적 링크된
xcframework 가 채운다. 이 테스트로는 pck 가 마운트되고 메인 씬이 열리는 것까지만
확인할 수 있다.

---

## Sideloadly 로 아이폰에 설치

### 준비물

- Windows PC + **[Sideloadly](https://sideloadly.io/)** (무료)
- **iTunes** (Apple 사이트에서 받은 버전 — Microsoft Store 버전은 안 된다)
  와 **iCloud** (역시 Apple 사이트 버전). Sideloadly 가 이 둘이 깔아 주는
  드라이버·라이브러리를 쓴다.
- 라이트닝/USB-C 케이블, Apple ID

### 절차

1. 아이폰을 USB 로 연결하고, 폰에 뜨는 **"이 컴퓨터를 신뢰하시겠습니까?"** 에
   신뢰를 누른다.
2. Sideloadly 실행 → 상단 **iDevice** 에 폰이 잡히는지 확인
3. `.ipa` 를 창 가운데로 드래그
4. **Apple Account** 칸에 Apple ID 입력 → **Start**
5. 비밀번호, 2단계 인증 코드 입력 (앱 암호가 아니라 그냥 Apple ID 비밀번호)
6. 설치가 끝나면 폰 홈 화면에 아이콘이 생긴다.
7. **첫 실행 전에 신뢰 설정이 필요하다**:
   설정 → 일반 → **VPN 및 기기 관리** → 내 Apple ID → **신뢰**
8. 앱 실행

### 무료 계정 서명의 제약 (중요)

| 제약 | 내용 |
|---|---|
| **7일** | 서명이 7일 뒤 만료된다. 앱이 실행되지 않으면 Sideloadly 로 **다시 설치**하면 된다(데이터는 유지되지만, 확실히 하려면 아래 세이브 위치 참고). |
| **앱 3개** | 한 Apple ID 로 동시에 사이드로드해 둘 수 있는 앱이 3개까지. |
| **App ID 10개/주** | 번들 ID 를 자꾸 바꾸면 주당 10개 한도에 걸린다 — `com.toniqat.esportsmanager` 를 **고정해서 쓸 것**. |
| **재설치 자동화** | Sideloadly 의 *Sideload with Wi-Fi* + PC 상주 옵션으로 자동 갱신을 걸 수 있다. |

만료 갱신이 귀찮으면 유료 개발자 계정($99/년)에서는 서명이 1년 가고, 그때는
CI 에서 바로 서명해 TestFlight 로 올리는 쪽이 낫다 — 이 워크플로에
`-exportArchive` 단계를 붙이는 정도의 변경이다.

---

## 이 세팅이 건드린 것들

| 파일 | 역할 |
|---|---|
| `.github/workflows/ios-testbuild.yml` | 빌드 파이프라인 전체 |
| `export_presets.cfg` | iOS 익스포트 프리셋 (번들 ID, 아이콘, `export_project_only`, `include_filter`) |
| `resources/images/appicon_1024.png` | 앱 아이콘 1024×1024 (지금은 `icon.svg` 를 구워 낸 기본 Godot 아이콘 — 갈아 끼우려면 이 파일만 덮어쓰면 된다) |
| `autoloads/GameManager.gd` | `db_path()` / `_extract_db_to_user()` — 아래 항목 |
| `features/battle_sim/data/DataLoader.gd` | 같은 이유로 `GameManager.db_path()` 를 쓴다 |
| `project.godot` | `textures/vram_compression/import_etc2_astc=true` — 아래 항목 |
| `resources/images/splash_blank.png` | 런치 스크린에서 Godot 로고를 걷어 내는 8×8 투명 PNG — 아래 항목 |

### `res://data/game.db` → `user://data/game.db`

SQLite 는 **디스크 위의 진짜 파일**을 열어야 한다. 에디터에서는 `res://` 가
그대로 실제 폴더라 그냥 열리지만, 익스포트한 빌드에서는 `res://` 가 `.pck`
안으로 들어가 SQLite 가 그 경로를 열지 못한다 — 손대지 않고 빌드했다면
아이폰에서 타이틀 화면부터 DB 오류로 멈췄을 자리다.

그래서 `GameManager.db_path()` 가 실행 환경을 보고 경로를 가른다.

- 에디터: `res://data/game.db` 그대로 (CSV→DB 재빌드가 곧바로 반영돼야 하므로)
- 기기: pck 안의 DB 를 `user://data/game.db` 로 **한 번 꺼낸 뒤** 그 사본을 연다

**매 실행마다 덮어쓴다.** DB 는 런타임에 읽기 전용이고(세이브는
`user://saves/*.save` JSON 으로 따로 산다) 96KB 뿐이라, 뭐가 바뀌었는지 비교하는
캐시 무효화 장치를 두는 것보다 그냥 복사하는 쪽이 언제나 옳다 — 새 빌드를 깔아
섰는데 옛 빌드의 `game.db` 가 `user://` 에 남아 있는 사고가 구조적으로 불가능해진다.

`data/game.db` 는 **리소스가 아니므로** 그냥 두면 pck 에 안 들어간다.
`export_presets.cfg` 의 `include_filter="data/game.db"` 가 그걸 넣는 자리이고,
워크플로의 포장 단계가 `pck` 안에서 그 문자열을 실제로 찾아 확인한다 — 필터가
조용히 빗나가면 빌드는 초록불인데 게임만 죽는 조합이 나오기 때문이다.

---

### `import_etc2_astc` — 이게 꺼져 있으면 익스포트가 **말없이** 죽는다

```
rendering/textures/vram_compression/import_etc2_astc=true
```

iOS 와 안드로이드는 이 설정을 요구하는데 **기본값이 false** 다. 꺼져 있으면
Godot 은 익스포트를 거부하면서도 이유를 **한 글자도 찍지 않는다**:

```
ERROR: Cannot export project with preset "iOS" due to configuration errors:
                                          ← 여기가 통째로 비어 있다
```

에디터 UI 에서는 익스포트 창이 이걸 별도 대화상자로 알려 주지만, 헤드리스
CLI 에서는 그 메시지가 `r_error` 에 안 실려 빈 줄만 남는다. 프리셋 옵션을
아무리 뒤져 봐도 원인이 안 나오는 자리라, **빈 메시지 = 이 설정**으로 외워 두는 편이 빠르다.

켜도 추적되는 `.import` 파일은 하나도 안 바뀐다 — ETC2/ASTC 변종은
`.godot/imported/` 안에만 구워지고 그건 gitignore 대상이다. 대신 임포트 시간과
`.godot/` 용량이 늘어난다.

### 화면 방향 — Godot 3 문자열이 남아 있으면 **가로로 빌드된다**

```
window/handheld/orientation=1        # 1 = Portrait
```

Godot 4 에서 이 설정은 **정수 enum** 이다
(`Landscape,Portrait,Reverse Landscape,Reverse Portrait,Sensor Landscape,Sensor Portrait,Sensor`).
그런데 이 프로젝트에는 Godot 3 시절의 문자열 `"portrait"` 가 남아 있었고,
Godot 4 는 그걸 해석하지 못해 **기본값 0 = Landscape** 로 떨어뜨렸다. 첫 빌드의
`Info.plist` 에 `UIInterfaceOrientationLandscapeLeft` 가 박힌 이유다.

에디터에서는 데스크톱 창이라 티가 안 난다 — **기기에서만 드러나는** 종류의
버그라, 빌드된 `.ipa` 의 `Info.plist` 를 한 번 열어 보는 것이 유일한 확인법이다:

```python
import zipfile, plistlib
z = zipfile.ZipFile("EsportsManager-debug-unsigned.ipa")
d = plistlib.loads(z.read("Payload/EsportsManager.app/Info.plist"))
print(d["CFBundleIdentifier"], d["UISupportedInterfaceOrientations"])
```

### Godot 스플래시 — 런치 스크린은 **지울 수 없고 갈아 끼운다**

폰에서 앱을 켜면 Godot 로고가 두 번 지나간다. 서로 다른 물건이라 끄는 법도 다르다.

| 무엇 | 언제 보이나 | 끄는 법 |
|---|---|---|
| **iOS 런치 스크린** | 아이콘을 탭한 직후, 앱 프로세스가 뜨는 동안 | 끌 수 없다 — 애플이 요구하는 화면이고 Godot 은 언제나 `Launch Screen.storyboard` 를 굽는다. **무엇을 담을지만** 정할 수 있다 |
| **엔진 부트 스플래시** | 앱이 뜬 뒤 첫 씬을 로드하는 동안 | `application/boot_splash/show_image=false` |

그래서 `project.godot` 의 `[application]` 절에 세 줄이 들어가 있다:

```
boot_splash/bg_color=Color(0, 0, 0, 1)
boot_splash/show_image=false
boot_splash/image="res://resources/images/splash_blank.png"
```

- `show_image=false` 는 **엔진 스플래시만** 끈다.
- `image` 는 **런치 스크린이 읽는다** — Godot 4.5 의 iOS 익스포터는
  `show_image` 를 **아예 보지 않고**(`editor/export/editor_export_platform_apple_embedded.cpp`)
  `boot_splash/image` 를 `Images.xcassets/SplashImage.imageset/splash@2x·@3x.png` 로 굽는다.
  비어 있으면 **엔진에 내장된 Godot 로고**로 폴백한다 — `show_image` 만 꺼 두면
  런치 스크린에는 로고가 그대로 남는 이유다. 그래서 8×8 **완전 투명** PNG
  (`resources/images/splash_blank.png`, 70바이트)를 물려 둔다.
- `bg_color` 는 스토리보드의 배경색이 된다(`storyboard/use_custom_bg_color` 를
  켜지 않는 한). 투명 이미지 + 검정 배경 = **검정 한 장**이고, 그 검정이 엔진
  스플래시 배경과 이어져 타이틀 화면까지 색이 끊기지 않는다.

나중에 진짜 스플래시 아트를 넣고 싶으면 `splash_blank.png` 를 덮어쓰거나,
iOS 에만 다른 그림을 쓰고 싶으면 `export_presets.cfg` 에
`storyboard/custom_image@2x` 와 `@3x` 를 **둘 다** 채운다(하나만 채우면 무시된다).
표시 방식은 `storyboard/image_scale_mode`
(`0=로고와 동일 · 1=Center · 2=Scale to Fit · 3=Scale to Fill · 4=Scale`).

검산 — 익스포트한 뒤 구워진 스플래시가 로고가 아닌지 본다(맥이 없어도 된다:
`export_project_only=true` 라 Xcode 프로젝트까지는 윈도우에서도 만들어진다):

```bash
godot --headless --path . --export-debug "iOS" /tmp/ios/EsportsManager.ipa
ls -la /tmp/ios/EsportsManager/Images.xcassets/SplashImage.imageset/
# Godot 로고면 14779바이트, 우리 것이면 85바이트
grep -o '<color key="backgroundColor"[^/]*' "/tmp/ios/EsportsManager/Launch Screen.storyboard"
```

---

---

## 햅틱 네이티브 플러그인 — 폴백이 도는지 어떻게 아는가

`autoloads/Haptics.gd` 는 플러그인이 없어도 **죽지 않는다** — `Input.vibrate_handheld`
로 조용히 내려앉고 경고를 한 번 찍을 뿐이다. 편한 설계지만 그 대가가 있다:
**빌드는 언제나 초록불**이고, 폰에서 감촉이 밋밋한 이유를 찾으려면 로그를 봐야
한다. 그래서 판정을 CI 로 옮겼다.

- 바이너리는 **커밋하지 않는다**. `.github/workflows/ios-testbuild.yml` 이 매
  빌드에서 `toniqat/godot-haptics-upstream-fork` 를 그 Godot 버전의 추출 헤더로
  컴파일해 `ios/plugins/haptics/` 에 놓는다(arm64, 캐시 키 = 버전 + 소스 SHA).
- **게이트 셋**이 폴백을 막는다 — (1) 세 파일 존재 + `lipo -info` arm64 +
  `nm` 에 `register_haptics_types` + preset 의 `plugins/Haptics=true`,
  (2) 익스포트된 `.a` 가 **Frameworks 링크 단계**에 들어갔을 것
  (UUID 를 `PBXFileReference` → `PBXBuildFile` → 링크 단계로 두 번 타고 확인한다
  — pbxproj 에 "haptics" 문자열이 있다는 것만으로는 아무것도 보장되지 않는다),
  (3) **최종 `.app` 바이너리 안**에 `register_haptics_types` 와
  `OBJC_CLASS_$_UIImpactFeedbackGenerator` 가 둘 다 있을 것 — 정적 아카이브의
  멤버는 참조하는 심볼이 있을 때만 끌려 들어오므로 1·2 를 통과하고도 통째로
  데드 스트립될 수 있다. 셋 중 하나라도 어긋나면 빌드가 그 자리에서 선다.
- 잡 요약(Actions → 그 실행 → Summary)의 **"햅틱"** 줄이 결과를 말해 준다.

**윈도우에서 로컬로 뽑은 익스포트에는 플러그인이 없다** — Godot 이 `.gdip` 을
못 찾으면 `plugins/Haptics` 키를 그냥 무시한다. 그러니 실기에서 감촉을 볼 때는
반드시 CI 아티팩트를 쓴다. 위의 "pck 만 갈아 끼우기" 빠른 길도 마찬가지다 —
플러그인은 pck 밖(앱 바이너리 안)이라 pck 교체로는 절대 안 들어온다.

자세한 규약(파일 이름이 왜 `haptics.release.a` / `haptics.debug.a` 인지)은
`ios/plugins/README.md`.

## 손볼 일이 생기면

### Godot 버전을 올렸을 때

`.github/workflows/ios-testbuild.yml` 상단의 두 줄만 고친다.

```yaml
GODOT_VERSION: "4.5"
GODOT_RELEASE: "stable"
```

프로젝트를 연 에디터와 **같은 버전**이어야 한다 — 다르면 익스포트 템플릿
버전 불일치로 실패한다.

### 번들 ID / 버전 번호

`export_presets.cfg` 의

```
application/bundle_identifier="com.toniqat.esportsmanager"
application/short_version="0.1"
application/version="0.1"
```

번들 ID 를 바꾸면 아이폰에서는 **다른 앱**이 되어 세이브가 딸려 오지 않고,
무료 계정의 주당 App ID 10개 한도도 하나 먹는다.

### 흔한 실패와 원인

| 증상 | 원인 |
|---|---|
| `No export template found at .../ios.zip` | `GODOT_VERSION` / `GODOT_RELEASE` 가 릴리스 태그와 안 맞는다 |
| `due to configuration errors:` 뒤가 **비어 있다** | `project.godot` 의 `textures/vram_compression/import_etc2_astc` 가 꺼졌다 — 아래 항목 |
| `.xcodeproj 를 찾지 못했다` | Godot 익스포트 단계가 실패했다 — 그 위 단계 로그를 볼 것 |
| `pck 안에 data/game.db 가 없다` | `include_filter` 가 빗나갔다 |
| 폰에서 게임이 **가로로** 뜬다 | `window/handheld/orientation` 이 문자열로 되돌아갔다 — 위 항목 |
| pck 를 갈아 끼웠는데 **화면 방향 · 아이콘 · 번들 ID** 가 그대로다 | 그 셋은 `Info.plist` / `Assets.car` 에 구워져 pck 밖에 산다 — CI 로 ipa 를 새로 굽는다 |
| 폰에서 앱이 켜지자마자 닫힌다 | 서명 만료(7일) 또는 신뢰 설정 미완료 → 재설치 + 기기 관리에서 신뢰 |
| Sideloadly 가 폰을 못 잡는다 | Microsoft Store 판 iTunes 가 깔려 있다 — Apple 사이트 버전으로 교체 |
| `Unable to install... 0xE8008015` | 무료 계정 앱 3개 한도 초과 — 다른 사이드로드 앱을 지운다 |

### 안드로이드도 같이 만들고 싶으면

`godot-sqlite` 는 `android.*.arm64/x86_64` 바이너리도 이미 들고 있고
`db_path()` 도 플랫폼을 가리지 않으므로, 안드로이드는 macOS 러너가 필요 없다
(`ubuntu-latest` + `android.zip` 템플릿 + 키스토어). 이 워크플로를 복사해
`xcodebuild` 단계만 걷어 내면 된다.
