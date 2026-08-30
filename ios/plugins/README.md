# iOS 플러그인 배치 자리

Godot 의 iOS 익스포터가 **이 폴더를 읽어** 생성되는 Xcode 프로젝트에
정적 라이브러리를 링크한다. 처리는 Xcode 프로젝트 *생성* 단계에서 일어나므로
`export_project_only=true` + `xcodebuild` 인 우리 CI 파이프라인과 충돌하지 않는다.

## Haptics — **CI 가 굽는다. 저장소에 커밋하지 않는다**

바이너리는 `.gitignore` 에 걸려 있고, 매 iOS 빌드에서
`.github/workflows/ios-testbuild.yml` 이 만들어 여기에 놓는다:

```
ios/plugins/haptics/
├── haptics.release.a   ← --export-release 가 링크한다
├── haptics.debug.a     ← --export-debug 가 링크한다
└── haptics.gdip
```

**커밋하지 않는 이유는 버전 잠금이다.** 구식 `.gdip` 플러그인은 엔진 헤더에
**컴파일 타임으로** 묶이므로, `.a` 를 저장소에 박아 두면 워크플로의
`GODOT_VERSION` 을 올리는 순간 낡은 바이너리가 **조용히** 안 맞게 된다.
매번 그 버전의 헤더로 다시 구우면 그 사고가 구조적으로 불가능해진다.

### 파일 이름이 곧 규약이다

Godot 은 `.gdip` 의 `binary=` 가 가리키는 `haptics.a` 가 **그 자리에 있으면
그것만** 쓴다(익스포트 타입과 무관하게). 없으면 `haptics.release.a` 와
`haptics.debug.a` **짝**을 찾아 익스포트 타입에 맞는 쪽을 링크한다. 우리는
짝을 놓는다 — 정적 라이브러리가 엔진 심볼에 묶이므로 디버그 익스포트에
릴리스 플러그인을 링크할 이유가 없다. **`haptics.a` 라는 이름의 파일을 여기
두면 그 선택이 통째로 무력화된다.**

실측으로 확인했다(더미 `.a` 두 장을 넣고 윈도우에서 익스포트) —
`--export-debug` 는 `haptics.debug.a` 를, `--export-release` 는
`haptics.release.a` 를 집어 가고, 둘 다 목적지에서는
`<앱>/ios/plugins/haptics/**haptics.a**` 라는 한 이름이 된다.

### fork 는 업스트림의 사본이 아니다 — 감촉 표 전체를 바인딩한다

**업스트림 `kyoz/godot-haptics` 의 iOS 플러그인은 `light` / `medium` / `heavy`
셋만 바인딩한다.** `_bind_methods()` 에 그 셋뿐이고 나머지는 아예 구현이 없다.
그런데 `autoloads/Haptics.gd` 는 그보다 넓은 표를 전제로 쓰여 있어
`selection()` · `soft()` · `rigid()` · `notify_success/warning/error()` ·
`prepare()` · `is_supported()` · `impact(style, intensity)` 를 부른다 — **전부
없는 메서드**다.

없는 메서드를 부르면 GDScript 는 그 자리에서 런타임 에러를 내고 조용히 지나간다.
`_plugin != null` 이라 `Input.vibrate_handheld` 폴백조차 안 탄다. 그래서 나온
증상이 **"플러그인은 멀쩡히 링크됐는데 감촉의 3분의 2가 침묵"** 이었다 — 버튼은
누를 때(`LIGHT`)만 울고 뗄 때(`SOFT`)는 조용했고, 훈련 타일 드래그는 집기 ·
미리보기 · 놓기(`SELECT` · `SELECT` · `SOFT`) 세 박자가 통째로 없었으며,
경기 승패 · 오브젝트 획득 · 세이브 삭제 · 엔딩(`SUCCESS` / `WARNING` / `ERROR`)도
전부 침묵이었다. 위 게이트 셋은 그동안 내내 초록불이었다 — 그 셋이 보는 것은
"플러그인이 있는가"이지 "부를 수 있는가"가 아니기 때문이다.

그래서 fork 에서 나머지를 구현하고 바인딩했다. **fork 를 업스트림으로 되감으면
그 침묵이 그대로 돌아온다.** 함께 바뀐 것이 하나 더 있다 — **제너레이터를
프로세스 수명 동안 캐시한다**. 업스트림은 호출마다 `UIImpactFeedbackGenerator`
를 새로 만들고 버렸는데, `-prepare` 는 **그 인스턴스**의 탭틱 엔진을 데우는
것이라 같은 런루프 안에서 죽는 객체는 그 예열을 들고 사라진다. 누를 때 데워
둔 물건이 뗄 때 우는 물건과 같아야 `prepare()` 가 뜻을 갖는다.

**Android 쪽(`android/.../Haptics.java`)은 아직 셋뿐이다.** 지금 CI 가 굽는 것은
iOS 뿐이라 손대지 않았다 — 안드로이드를 내보내게 되면 그때 같은 표로 채워야 한다.

### 어떻게 구워지는가

원본은 `toniqat/godot-haptics-upstream-fork`(upstream `kyoz/godot-haptics`)이고
헤더는 `kyoz/godot-ios-extracted-headers` 의 `extracted_headers_godot_<버전>.zip`
이다. 워크플로는 업스트림의 `scripts/ios/generate_static_library.sh` 를 쓰지
**않는다** — 그 스크립트는 armv7 과 x86_64 시뮬레이터까지 굽고 lipo 로 묶는데,
armv7 은 Xcode 14 에서 사라졌고 시뮬레이터 슬라이스는 사이드로드하는 실기
빌드에 쓸모가 없다. 필요한 것은 arm64 하나라 `scons` 를 직접 부른다.
배포 타깃도 10.0 → 12.0 으로 올려 둔다(원본 값은 지금 Xcode 가 받는 범위 밖).

캐시 키는 `GODOT_VERSION` + 플러그인 소스 SHA 다 — 둘 중 어느 쪽이 움직여도
낡은 `.a` 를 재사용하면 안 된다.

### 폴백을 막는 것은 문서가 아니라 CI 다

`export_presets.cfg` 의 `plugins/Haptics=true` 는 켜져 있다. 그런데 `.gdip` 이
안 읽히면 Godot 은 **아무 말 없이 그냥 넘어가고**, 그 조합이 정확히 "빌드는
초록불인데 폰에서는 `Input.vibrate_handheld` 폴백" 이다. 그래서 워크플로에
게이트를 셋 뒀다:

1. **플러그인 확인** — 세 파일이 있고, `lipo -info` 가 arm64 라 답하고,
   `nm` 이 `register_haptics_types` 심볼을 찾고, preset 에 `plugins/Haptics=true`
   가 있을 것. **그리고 `Haptics.gd` 가 부르는 메서드 이름이 전부 아카이브 안에
   있을 것** — `bind_method` 에 넘긴 이름은 문자열 리터럴이라 `__cstring` 에
   평문으로 남는다. 이 검사가 없으면 "플러그인은 있는데 절반이 바인딩 안 됨"이
   초록불로 지나간다(실제로 지나갔다 — 위 절).
2. **익스포트 결과 확인** — 생성된 Xcode 프로젝트 안에 플러그인 `.a` 가 있고,
   그 안에 `register_haptics_types` 심볼이 있고, **그것이 링크 단계에 들어가
   있을 것**. **찾는 이름에 주의** — 익스포터는 고른 쪽을 `.gdip` 의
   `binary=` 이름, 곧 **`haptics.a`** 로 베껴 넣고 자리도 프로젝트 루트가 아니라
   `<앱>/ios/plugins/haptics/` 다. `haptics.release.a` 라는 이름으로 찾으면
   멀쩡한 빌드가 "플러그인 없음"으로 잡힌다(실측 — 첫 CI 실행이 여기서 섰다).

   **그리고 "pbxproj 에 haptics 문자열이 있다"로는 부족하다.** pbxproj 는
   `PBXFileReference`(그런 파일이 있다)와 `PBXBuildFile`(그것을 빌드에 쓴다)을
   따로 두고, **실제로 링크되는 것은 후자가 `PBXFrameworksBuildPhase` 의
   files 목록에 들어 있을 때뿐**이다. 워크플로는 UUID 를 두 번 타고 들어가
   그 목록에서 확인한다.
3. **최종 바이너리 확인** — `.app` 실행 바이너리 안에
   `register_haptics_types` 와 `OBJC_CLASS_$_UIImpactFeedbackGenerator` 와
   `OBJC_CLASS_$_UISelectionFeedbackGenerator` 와
   `OBJC_CLASS_$_UINotificationFeedbackGenerator` 가 **넷 다** 있을 것. 뒤의 둘을
   부르는 코드는 이 빌드에 플러그인 말고 없으므로, 그 참조가 곧 "impact 셋 말고
   나머지도 실제로 링크됐다"의 증거다 — 낡은 캐시가 끼어들면 여기서 걸린다. 1·2 가 통과해도 여기서 떨어질 수 있다: **정적 아카이브의
   멤버는 참조하는 심볼이 있을 때만 끌려 들어오므로**, 링크 단계에 `.a` 가
   있어도 Godot 이 만든 초기화 코드가 빠지면 통째로 데드 스트립된다. 그 경우가
   정확히 "빌드 초록불 + 폰에서는 폴백" 이라, 이 검사가 마지막 자물쇠다.

   **`nm` 은 쓰지 않는다.** 103MB 짜리 이 바이너리에서 `nm -a` 와 `nm -mu` 가
   두 심볼을 다 놓쳤다(실측 — 아티팩트를 내려받아 바이트를 훑으니 둘 다 있었다).
   이름은 문자열 테이블에 평문으로 들어 있으므로 `grep -a` 로 직접 본다.

셋 중 하나라도 어긋나면 빌드가 그 자리에서 선다.

## 로컬(윈도우) 익스포트

플러그인 없이도 익스포트는 **통과한다** — Godot 이 `.gdip` 을 못 찾으면
`plugins/Haptics` 키를 무시할 뿐이다. 그 빌드를 폰에 올리면 폴백이 돌고
경고가 한 번 찍힌다. 실기에서 진짜 감촉을 보려면 CI 아티팩트를 쓴다
(`docs/ios_testbuild.md`).
