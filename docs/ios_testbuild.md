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
| `.xcodeproj 를 찾지 못했다` | Godot 익스포트 단계가 실패했다 — 그 위 단계 로그를 볼 것 |
| `pck 안에 data/game.db 가 없다` | `include_filter` 가 빗나갔다 |
| 폰에서 앱이 켜지자마자 닫힌다 | 서명 만료(7일) 또는 신뢰 설정 미완료 → 재설치 + 기기 관리에서 신뢰 |
| Sideloadly 가 폰을 못 잡는다 | Microsoft Store 판 iTunes 가 깔려 있다 — Apple 사이트 버전으로 교체 |
| `Unable to install... 0xE8008015` | 무료 계정 앱 3개 한도 초과 — 다른 사이드로드 앱을 지운다 |

### 안드로이드도 같이 만들고 싶으면

`godot-sqlite` 는 `android.*.arm64/x86_64` 바이너리도 이미 들고 있고
`db_path()` 도 플랫폼을 가리지 않으므로, 안드로이드는 macOS 러너가 필요 없다
(`ubuntu-latest` + `android.zip` 템플릿 + 키스토어). 이 워크플로를 복사해
`xcodebuild` 단계만 걷어 내면 된다.
