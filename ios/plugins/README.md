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
   가 있을 것.
2. **익스포트 결과 확인** — 생성된 Xcode 프로젝트 안에 플러그인 `.a` 가 있고
   그 안에 `register_haptics_types` 심볼이 있고 `project.pbxproj` 가 그것을
   참조할 것. **찾는 이름에 주의** — 익스포터는 고른 쪽을 `.gdip` 의
   `binary=` 이름, 곧 **`haptics.a`** 로 베껴 넣고 자리도 프로젝트 루트가 아니라
   `<앱>/ios/plugins/haptics/` 다. `haptics.release.a` 라는 이름으로 찾으면
   멀쩡한 빌드가 "플러그인 없음"으로 잡힌다(실측 — 첫 CI 실행이 여기서 섰다).
3. **최종 바이너리 보고** — `.app` 바이너리에서 심볼을 찾아 요약에 적는다
   (릴리스는 스트립될 수 있어 실패로 세우지는 않는다 — 하드 게이트는 1·2다).

1 이나 2 가 어긋나면 빌드가 그 자리에서 선다.

## 로컬(윈도우) 익스포트

플러그인 없이도 익스포트는 **통과한다** — Godot 이 `.gdip` 을 못 찾으면
`plugins/Haptics` 키를 무시할 뿐이다. 그 빌드를 폰에 올리면 폴백이 돌고
경고가 한 번 찍힌다. 실기에서 진짜 감촉을 보려면 CI 아티팩트를 쓴다
(`docs/ios_testbuild.md`).
