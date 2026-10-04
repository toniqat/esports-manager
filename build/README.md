# build/ — 빌드 산출물 자리

**이 폴더에서 커밋되는 파일은 이 README 하나다.** 나머지는 전부
`.gitignore` 가 막는다(`/build/*` + `!/build/README.md` — 디렉터리 자체를
무시하면 git 이 안으로 들어가지 않아 안쪽 예외가 안 먹으므로 `/build/` 가
아니라 `/build/*` 다).

여기는 **폰에 올릴 물건을 두는 자리**다. Sideloadly 가 집어 가는 곳이라
손이 닿는 유일한 폴더이고, 그래서 규칙이 하나 있다.

---

## 규칙 — CI 빌드를 돌렸으면 그 `.ipa` 를 여기로 내려받는다

아티팩트 링크만 알려 주고 끝내지 않는다. **그린을 확인한 직후 네 가지를 한다.**

1. **낡은 산출물을 지운다** — 이 폴더에 있던 예전 `.ipa` / `.pck`.
2. **새 `.ipa` 를 내려받는다** — 파일명에 **빌드한 커밋의 short SHA** 를 붙여
   `EsportsManager-debug-unsigned-<sha>.ipa`.
3. **무엇이 들어 있는지 한 줄 검산한다** (아래).
4. 그 결과까지 보고한다.

```powershell
$gh  = "C:\Program Files\GitHub CLI\gh.exe"   # PATH 에 없다 — 전체 경로로 부른다
$tmp = "$env:TEMP\ipa-dl"
& $gh run download <run-id> -R toniqat/esports-manager -D $tmp
$src = Get-ChildItem -Recurse $tmp -Filter *.ipa | Select-Object -First 1
$sha = git rev-parse --short HEAD
Move-Item $src.FullName "build\EsportsManager-debug-unsigned-$sha.ipa" -Force
Remove-Item -Recurse -Force $tmp
```

### 왜 SHA 를 붙이나

이 폴더에 낡은 빌드가 섞이면 **어느 것이 방금 만든 것인지 알 수 없다.**
실제로 한 번 겪었다 — 햅틱이 하나도 안 들어간 직전 커밋(`6a1508f`)의 `.ipa` 가
남아 있어 그걸 폰에 올릴 뻔했다. 날짜는 다운로드 시각이라 답이 되지 못하고,
"무엇이 들어 있나"에 답하는 것은 커밋뿐이다.

---

## 검산 — 이 `.ipa` 에 무엇이 들어 있나

`.ipa` 는 그냥 zip 이라 파이썬으로 열어 보면 된다. **맥도 `nm` 도 필요 없다** —
오히려 `nm` 은 100MB 대 바이너리에서 심볼을 놓친 전적이 있다(실측). 이름은
문자열 테이블에 평문으로 있으므로 바이트를 직접 훑는다.

```python
import zipfile
z = zipfile.ZipFile('build/EsportsManager-debug-unsigned-<sha>.ipa')
b   = z.read('Payload/EsportsManager.app/EsportsManager')      # 실행 바이너리
pck = z.read('Payload/EsportsManager.app/EsportsManager.pck')  # 게임 데이터

print('네이티브 햅틱:', all(n in b for n in [
    b'register_haptics_types',
    b'_OBJC_CLASS_$_UIImpactFeedbackGenerator',        # light / medium / heavy
    b'_OBJC_CLASS_$_UISelectionFeedbackGenerator',     # SELECT
    b'_OBJC_CLASS_$_UINotificationFeedbackGenerator',  # SUCCESS / WARNING / ERROR
]))
print('game.db:', b'data/game.db' in pck)   # 없으면 타이틀 화면부터 DB 오류로 죽는다
```

- **네이티브 햅틱** — **넷 다** 있어야 한다. 앞의 둘만 보면 부족하다는 것을
  실제로 겪었다: 업스트림 플러그인이 impact 셋만 바인딩하는데 그 둘은 멀쩡히
  있어서, **감촉의 3분의 2가 폰에서 침묵인 채로 검산을 통과했다**(버튼 뗌 ·
  훈련 타일 드래그 · 경기 승패 · 오브젝트 획득이 전부 조용했다). 뒤의 두
  클래스를 부르는 코드는 이 빌드에 플러그인밖에 없으므로, 그 참조가 곧
  "impact 셋 말고 나머지도 들어왔다"의 증거다. 하나라도 없으면
  `ios/plugins/README.md`.
- **`data/game.db`** — 리소스가 아니라 `include_filter` 로만 pck 에 들어가므로,
  필터가 조용히 빗나가면 빌드는 초록불인데 게임이 멈춘다.

---

## 로컬(윈도우) 익스포트는 `.ipa` 를 만들지 못한다

`godot --export-debug "iOS" build/ios/…` 는 **Xcode 프로젝트와 pck 까지만**
만든다(`.ipa` 는 `xcodebuild` 가 필요하고 그것은 macOS 전용). 그 결과물은
`build/ios/` 에 쌓이며, 익스포트 옵션·플러그인 배선처럼 **macOS 없이 확인할 수
있는 것**을 25초 만에 검산하는 용도다. 폰에 올릴 물건은 언제나 CI 아티팩트다.

절차 · 제약 · Sideloadly 설치법은 **`docs/ios_testbuild.md`**.


## Detail moved from root CLAUDE.md

## iOS 테스트 빌드 (맥 없이)

`.github/workflows/ios-testbuild.yml` 가 GitHub 의 **macOS 러너**에서
`Godot --export-debug "iOS"` → `xcodebuild` → `Payload/*.app` → zip 을 돌려
**서명되지 않은 `.ipa`** 를 아티팩트로 올린다. 그걸 내려받아 윈도우 PC 에서
**Sideloadly** 로 아이폰에 밀어 넣는다 — 서명은 Sideloadly 가 무료 Apple ID 로
로컬에서 하므로 **CI 에 인증서도 시크릿도 없다**(`CODE_SIGNING_ALLOWED=NO`).
저장소가 public 이라 macOS 러너는 무료다. 절차 · 제약 · 실패 표는 **`docs/ios_testbuild.md`**.

### 빌드를 돌렸으면 `.ipa` 를 `build/` 로 내려받는다

**아티팩트 링크만 알려 주고 끝내지 않는다.** `build/` 가 Sideloadly 로 폰에
올릴 때 손이 닿는 유일한 폴더이므로, CI 그린을 확인한 직후 네 가지를 한다 —
(1) 그 폴더의 **낡은 `.ipa` / `.pck` 삭제**, (2) 새 `.ipa` 를
**`EsportsManager-debug-unsigned-<커밋 short SHA>.ipa`** 로 내려받기,
(3) 내용 검산(pck 안 `data/game.db`, 실행 바이너리 안
`register_haptics_types` + `OBJC_CLASS_$_UIImpactFeedbackGenerator`),
(4) 그 결과까지 보고.

**파일명에 SHA 를 붙이는 이유**는 낡은 빌드가 섞이면 어느 것이 방금 만든
것인지 알 수 없기 때문이다 — 실제로 햅틱이 하나도 안 들어간 직전 커밋의
`.ipa` 를 폰에 올릴 뻔했다. 날짜는 다운로드 시각이라 답이 되지 못한다.
명령과 검산 스니펫은 **`build/README.md`**.

**로컬(윈도우) 익스포트는 `.ipa` 를 만들지 못한다** — Xcode 프로젝트와 pck 까지만
나오고(`build/ios/`), 그것은 익스포트 옵션 · 플러그인 배선처럼 macOS 없이 확인할
수 있는 것을 25초에 검산하는 용도다. 폰에 올릴 물건은 언제나 CI 아티팩트다.

---

Godot 이 `xcodebuild` 를 직접 부르지 않는 것은 `export_presets.cfg` 의
`application/export_project_only=true` 때문이다 — 서명을 아예 끄고 싶으므로
Xcode 프로젝트만 받아 빌드 플래그를 우리가 쥐는다.
