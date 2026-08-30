# iOS 플러그인 배치 자리

Godot 의 iOS 익스포터가 **이 폴더를 읽어** 생성되는 Xcode 프로젝트에
정적 라이브러리를 링크한다. 처리는 Xcode 프로젝트 *생성* 단계에서 일어나므로
`export_project_only=true` + `xcodebuild` 인 우리 CI 파이프라인과 충돌하지 않는다.

## Haptics (미배치)

**아직 바이너리가 없다.** 들어올 것:

```
ios/plugins/haptics/
├── haptics.a          ← release
├── haptics.debug.a    ← debug
└── haptics.gdip
```

출처는 포크한 별도 저장소이고 태그를 밀면 macOS 러너가 구워 `ios-template-4.5.zip`
로 올린다(Godot 버전과 반드시 일치해야 한다 — 구식 `.gdip` 플러그인은 엔진
헤더에 컴파일 타임으로 묶인다).

배치한 뒤 **`export_presets.cfg` 에 `plugins/Haptics=true` 를 켜야 한다.**
안 켜면 빌드는 초록불인데 `Engine.has_singleton("Haptics")` 만 false 라,
`autoloads/Haptics.gd` 가 조용히 `Input.vibrate_handheld` 폴백으로 떨어진다
(경고는 한 번 찍힌다).

바이너리를 넣을 때 이 파일의 "미배치" 표시를 지울 것.
