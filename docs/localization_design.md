# 현지화(L10n) 구조 설계서

> 이 문서는 LLM(코딩 에이전트)이 이 프로젝트의 현지화 시스템을 **구현·유지보수·사용**할 때 따라야 하는 사양이다.
> 1차 독자는 LLM이지만 프로젝트 오너가 읽어도 이해되도록 쓴다.
> **MUST / MUST NOT / SHOULD** 는 RFC 2119 의미로 해석한다.
> 상태: **2차 이행 완료 (2026-10-07)** — 도구 §15 1~7단계, 데이터 CSV · 씬 · 코드 리터럴 이행 끝, 고아 0 · `strict.orphans = error`. 상세는 `addons/l10n_tool/README.md` · `data/l10n/README.md` · 각 폴더 README, 이 문서는 사양으로 남는다. 남은 일은 §0.6.

---

## 0. LLM 작업 규칙 (먼저 읽을 것)

1. 이 문서와 실제 코드가 다르면 **임의로 한쪽에 맞추지 말고** 차이를 보고하고 오너에게 확인받는다.
2. `data/l10n/generated/` 아래 파일은 **직접 수정하지 않는다(MUST NOT).** 항상 `build` 를 다시 실행한다.
3. key 를 **직접 지어내지 않는다(MUST NOT).** `new_key` · `new_keys` / `extract` 명령(또는 같은 규칙의 생성 함수)으로만 발급한다.
4. 문자열 CSV 를 고칠 때 **행 순서를 바꾸지 않고**, 새 행은 **파일 끝에 추가**한다. 정렬·재포맷·인코딩 변경 금지 (§12).
5. 번역의 `approved` 전환은 **오너가 명시적으로 지시할 때만** `approve` 명령으로 한다. LLM 은 번역을 `draft` 까지만 쓴다.
6. 코드에서 key 를 문자열 연결로 **동적으로 조립하지 않는다(MUST NOT)** (§10.1).
7. Godot 엔진 동작(임포트, `tr()`, 폴백, 이스케이프 처리 등)에 관한 서술은 작성 시점 기준이다. 구현 전에 **Godot 4.5 공식 문서나 실제 동작으로 확인**하고, 다르면 보고한다. 확인이 필요한 항목은 본문에 **(확인)** 으로 표시했다.
8. 작업 후 `build dev` 를 실행하고 `data/l10n/generated/report.md` 의 Error 가 0 인지 확인한다.
9. 표시용 텍스트(한국어·영어 리터럴)를 새로 코드나 씬에 쓰지 않는다. 먼저 key 를 발급한다.

---

## 0.5 확정 사항 (2026-10-07 오너 인터뷰)

본문과 이 표가 다르면 **이 표가 우선**한다. 본문 해당 절도 이 표에 맞춰 고쳤다.

| # | 항목 | 결정 |
|---|---|---|
| D1 | 1차 범위 | §15 1~6단계(도구) + §14 1순위 **데이터 CSV 이행**. 씬 · 코드 리터럴 이행(§14 2~6)은 다음 회차 |
| D2 | `[x]` 참조 | 특수 키워드(추적 · 반응 장갑 · 목표 · 현상금 · 기절 · 취약)와 카드 키워드(소멸 · 보존 …)는 `keyword` 도메인. `ref_domains = ["card", "keyword"]`. pilot_skill · mech_passive 설명문도 E034 검증 대상 |
| D3 | 이름 조회 | `card_by_name` · `card_costs_by_name` 같은 **표시 이름 조회는 id/key 기반으로 전면 교체** |
| D4 | 참조 해석 | `build` 가 `generated/refs.json`(문자열 key → 참조 key 목록, 등장 순서)을 만든다. 런타임은 텍스트 매칭 없이 key → (테이블, id) 로 찾는다. 커밋 대상 |
| D5 | data/csv 임포트 | `data/csv/.gdignore`. 기존 `*.translation` · `*.csv.import` 삭제 |
| D6 | mental_events | 정규화 — 대사 전용 테이블 `mental_texts.csv`(id, event_id, slot, choice, branch, seq, text_key — `order` 는 SQL 예약어라 `seq`). `lines` · `choices` 컬럼과 effects 의 `say:` 제거 |
| D7 | 세이브 | `season_state` 의 이름 사본 제거(id · key 만). 구 `run.save` 는 **폐기**(세이브 버전 올림). `profile.save` 는 유지 |
| D8 | 고유명사 | 모두 key 화, 언어별 표기(en 은 로마자 / 영문명) |
| D9 | en 번역 | 이행한 데이터 텍스트 전부 LLM 이 `draft` 로 채운다. approve 는 오너 |
| D10 | 언어 UI | 로비 홈 상단 설정 버튼 → `UI_View_SettingsPopup` |
| D11 | 최초 로케일 | profile 에 값이 없으면 **기기 언어**(`OS.get_locale_language()`), 미지원이면 `fallback_locale` |
| D12 | 씬 미리보기 | 서드파티 Translation Preview **미도입**. L10n 편집기(메인 화면 탭)에 자체 씬 미리보기(씬을 수정하지 않음) |
| D13 | CI | 이번엔 미연동 — CI 는 커밋된 dev 생성물로 export. **TODO**: 번역 완료 후 CI 에 `build release` 연동 (§15 표 아래) |
| D14 | 병렬 개발 | 같은 작업 트리 + 에이전트별 파일 소유 분리, 단계별 커밋 |
| D15 | 중복 텍스트 | 데이터 행마다 별도 key. 중복 · E036 후보는 보고서로 |
| D16 | 고아 검사 제외 | 로그 함수(`print` · `printerr` · `push_warning` · `push_error` · `assert`) 인자, 주석, `scan.ignore_paths`(디버그 · 치트 · 덤프). 나머지는 전부 검사 |
| D17 | 카드 도메인 | 파일럿 · 메크 카드를 **하나의 `card` 도메인**으로: `card.pilot.{id}.name` · `card.mech.{id}.name` |

## 0.6 남은 일 (2차 이행 후)

2차 이행(2026-10-07): 씬 · 코드 리터럴 → key 이행 완료(§14 2~6). active key 약 2,020개, 고아 0, `strict.orphans = error`
(새 한글 리터럴 · 씬 텍스트는 이제 `build` 를 막는다). 새로 발급한 key 의 en 은 모두 LLM `draft`.

- **en 번역 검수 · approve** — 전 key 가 `draft`. 오너가 검수 후 `approve`.
- **CI release 연동** — §15 아래 TODO (D13).
- **진단 로그 문자열** — `_bs.last_log` · `blog.log_event` / `log_block` 로 가는 전투 결과 문장(약 215줄)은 화면에 안 나와 `# l10n-ignore`. 다시 화면에 띄우면 key 가 필요하다. `blog.*` 를 `scan.log_funcs` 에 넣는 것도 후보.
- **English text the scanner cannot see** — a literal without Hangul is never an orphan, so new English-only
  display strings must be keyed by hand.

Done 2026-10-08: glossary warnings 0 (source `손패`/`드로우` fixed, `match_<loc>` regex column §4.5 · E074),
ban/pick role tags → `match.ban_pick.role.*` (English caps in every locale, owner decision), `MISS` →
`battle.popup.miss` (MISS in every locale), engage header name → player name + `battle.engage.lane.*`,
`hud.victory.play_again` ko 다시 하기, `_fx_short` Latin initials, `ui.button.prev` deprecated.

## 0.7 공유 어휘 (이행 기반)

코드 · 씬 리터럴 이행(§14 2~3) 전에 **여러 화면이 같이 쓰는 말**을 먼저 key 로 만들고 헬퍼를 두었다. feature 폴더를
이행할 때 같은 뜻의 key 를 새로 만들지 말고 아래를 쓴다. `ui.csv` · `term.csv` 에 행을 더하는 것은 기반 담당만 한다 —
빠진 공유 낱말은 보고한다. 표(`*_LABELS` · `STAT_*` · `ROLE_NAMES` · `DAY_*`)의 값은 이제 **`L.` key** 이므로
표 값을 화면에 그대로 찍지 말고 반드시 헬퍼를 부른다(그대로 찍으면 `tx_…` 가 보인다).

### 헬퍼 (static, 현재 로케일 문자열을 돌려준다)

| 헬퍼 | 반환 | key |
|---|---|---|
| `GameEnums.position_label(pos_key: String) -> String` | 포지션 이름 "탑" (모르는 키 "—") | `term.position.{top,jungle,mid,carry,support}` |
| `GameEnums.role_position_label(role: int) -> String` | `position_label(position_key(role))` | 〃 |
| `GameEnums.phase_label(phase: int) -> String` | 시즌 페이즈 이름 "프리시즌 국제대회" (모르는 값 "—") — 네 화면의 `PHASE_NAMES` 표 대신 | `term.phase.{preseason,preseason_intl,midseason,midseason_intl,regular,regular_intl}` |
| `GameEnums.rarity_label(tier: int) -> String` | 등급 0..4 일반 · 고급 · 희귀 · 영웅 · 전설 (양끝으로 자름). 기벽 3단(일반 · 희귀 · 영웅)은 0 · 2 · 3 으로 옮겨 부른다 | `term.rarity.{common,uncommon,rare,epic,legendary}` |
| `GameEnums.tag_label(tag_id: String)` · `GameEnums.tags_text(raw: String) -> String` | 스킬 · 패시브 성향 태그 — `keyword` 셀(`engage\|strategy`) → "교전, 전략 점수" | `term.tag.*` |
| `PlayerData.stat_label(i: int)` · `stat_short(i)` · `stat_note(i)` | 스탯 여섯(`STAT_KEYS` 순) 이름 · 약칭 · 한 줄 설명 (범위 밖 "") | `term.stat.<stat_key>.{name,short,note}` |
| `OutgameTheme.role_name(i: int)` | 메크 역할군 탱커 · 격투 · 암살 · 서폿 · 원딜 (`GameEnums.Role` 순) | `term.mech_role.{tank,fighter,assassin,support,sniper}` |
| `OutgameTheme.day_letter(i: int)` · `day_name(i)` | 요일 월(0) … 일(6) — 약칭 "월" / 이름 "월요일" (범위 밖 "") | `term.day.short.*` · `term.day.long.*` (`mon` … `sun`) |
| `CardData.category_label(cat: String)` (static) | 카드 분류 하나 "성장" (모르는 id 그대로). 카드 한 장의 목록은 인스턴스 `categories_text()` | `term.card_cat.*` |
| `CardData.scope_label(scope)` | "모든 포지션" / "탑 · 미드" | `term.position.all` + 위 |
| `RunRules.area_label(area)` | 감독 운영 영역 "훈련 편성" … | `term.area.{training,knowledge,analysis,finance}` |

### `ui` 도메인 — 뜻이 어디서나 같은 UI 낱말

| alias 묶음 | 내용 |
|---|---|
| `ui.button.*` | `confirm` 확인 · `cancel` 취소 · `close` 닫기 · `next` 다음 · `prev` 이전 · `back` 뒤로 · `buy` 구매 · `claim` 수령 · `exchange` 교환 · `continue` 계속 · `level_up` 레벨업 · `remove` 제거 · `reset` 재설정 · `use` 사용 · `to_lobby` 로비로 · `tap_to_continue` 화면을 눌러 계속 |
| `ui.word.*` | `none` 없음 · `all` 전체 · `current` 현재 · `locked` 잠김 · `unowned` 미보유 · `no_record` 기록 없음 · `max_level` 최고 레벨 · `time_left` 남은 시간 |
| `ui.message.max_level` | 최고 레벨입니다 |
| `ui.error.*` | `save_failed` "저장 실패: {error}" · `profile_save_failed` "프로필 저장 실패: {error}" · `not_enough_currency` "재화가 부족합니다 ({n} 필요)" |
| `ui.list_separator` | ", " — 목록 잇기 `Loc.t(L.UI_LIST_SEPARATOR).join(parts)`. `" · "` 같은 기호 구분자는 글자가 없어 key 가 아니다 |
| `ui.lineup.*` · `ui.run.*` · `ui.level_up.*` | `RunRules.validate_lineup` · `GameManager.start_run` · `ProfileManager.level_up_pilot` 오류 문장 (돌려줄 때 이미 번역됨) |

### `term` 도메인 — 게임 어휘 (뜻이 하나)

위 헬퍼의 key 들 + `term.position.all` 모든 포지션 · `term.phase.intl` 국제대회(특정 페이즈가 아닐 때) ·
`term.combat.{hp,max_hp,atk,shield,presence}` 체력 · 최대 체력 · 공격력 · 보호막 · 존재감 ·
`term.side.{ally,enemy}` 아군 · 적군 · `term.currency.levelup` 레벨업 재화 · `term.week.nth` "{n}주차" ·
`term.week.count` "{n}주" · `term.record.win_loss` "{win}승 {loss}패" · `term.person.{manager,staff}` 감독 · 스태프 ·
`term.card.{pilot_card,mech_card,deck}` 파일럿 카드 · 메크 카드 · 덱 ·
`term.activity.{training,press,interview,outing}` 훈련 · 기자회견 · 면담 · 외출.
단독 낱말로 쓸 때만 이 key 를 쓴다 — 문장 안에 든 같은 낱말은 그 문장의 key 하나로 쓴다(§6.1).

### `keyword.icon.*` — 설명문 아이콘 낱말 (표시하지 않는 매칭 표)

`StrategyIcon` · `KeywordIcon` 이 설명문에서 아이콘을 앞에 세울 낱말을 **현재 로케일 번역값**으로 찾는다.
번역값 = 그 언어 설명문의 표기, `|` = 다른 표기(en `kill|killed`), 대소문자 무시, 라틴 낱말은 낱말 경계(복수 `s` 포함).
지속시간은 `keyword.icon.duration_suffix`(ko "턴", en "turns|turn", 숫자와 사이 공백 하나 허용).
**en 설명문 표기를 바꾸면 이 표의 en 값도 같이 맞춘다.**

### 그 밖에

- 페이즈 이름: `HubView` · `LeagueView` · `PressConferenceView` · `WeekProgressView` 의 `PHASE_NAMES` 와 그것을 빌려 쓰는
  `HomeTab` · `RunResultScreen` · `EndingView` · `GameOverView` · `BracketView` · `IntlBracketView` 는 각 feature 이행 때
  `GameEnums.phase_label(phase)` 로 바꾼다(표를 없앤다).
- 특성 · 기벽 등급(`TraitSystem.RARITY_NAMES`, `QuirkSystem.GRADE_NAMES`)은 `GameEnums.rarity_label` 로 바꾼다.
- 포지션 배지 글자(`GameEnums.POSITION_ABBREVS`, TOP · JGL …)는 번역하지 않는다. Same for the ban/pick role badge
  `BanPickController.ROLE_INITIALS` (Tk · Fi …). Role tags (TANK …) are keys whose text is English in every locale.
- `build`/`write_strings` 뒤 헤드리스로 씬을 돌려 확인할 때는 먼저 `godot --headless --path . --import` 로 `strings_*.csv`
  를 다시 임포트한다 — 안 하면 새 key 가 `tx_…` 그대로 보인다.

---

## 1. 목표와 원칙

### 1.1 요구사항 → 해결책

| 요구사항 / 문제 | 해결책 |
|---|---|
| **용어집을 별도로 지정** | `glossary.csv` + 금지 표기 · 번역어 검증 (§4.5, §13) |
| **key · 값이 파편화되지 않음** | 도메인 파일 하나에 key · 메타 · **모든 언어**를 한 행으로 (§4.2). 원문 사본 컬럼 없음 |
| **사용처 조회(레퍼런스 뷰어)** | 스캐너가 만드는 `index.json` + L10n 편집기(메인 화면 탭), 줄 단위 이동 (§9, §11) |
| **엔진을 켜지 않고 수정** | 원본은 CSV — Excel / VS Code 로 편집. 반영은 다음 `build`(에디터 메뉴 또는 헤드리스) |
| key 이름을 바꾸면 번역 연결이 끊김 | 불변 GUID key + 바꿀 수 있는 alias (§3) |
| 원문을 고친 뒤 낡은 번역이 출시됨 | 원문 해시 기반 stale 감지 (§8) |
| 코드 / 씬 / 데이터 CSV 에 하드코딩된 텍스트 | 사용처 스캔으로 고아 텍스트 검출 + 일괄 추출 (§9, §14) |
| 번역 누락 시 GUID 가 화면에 노출 | dev 빌드 원문 채움, release 폴백 검증 (§7.3, §10.3) |

### 1.2 원칙

- **원본은 CSV, Godot 이 읽는 것은 생성물.** 사람과 LLM 은 `data/l10n/src/` 의 CSV 만 편집한다.
- **한 문자열 = 한 행.** 원문 · 모든 번역 · 상태 · 메모가 같은 행에 있다. 같은 값을 두 곳에 적지 않는다.
- **규칙은 검증기가 지킨다.** 사람의 주의력에 기대는 규칙은 모두 검증 항목(§13)으로 만든다.
- **기존 파이프라인에 붙인다.** `data/csv` → game.db 흐름과 `Project → Tools` 메뉴를 그대로 쓰고, 문자열만 l10n 으로 옮긴다.

### 1.3 범위 밖 (§16 에 확장 방향만 기록)

음성(VO) · PO 파이프라인 · 언어별 복수 규칙(`tr_n`) · 외부 번역 플랫폼 연동.

---

## 2. 디렉터리 구조

```
res://
├─ addons/
│  ├─ csv_to_db/                    # 기존. Rebuild game.db — 끝에 l10n build dev 를 호출 (§7.1)
│  ├─ l10n_tool/                    # 신규. 에디터 플러그인
│  │  ├─ plugin.cfg · plugin.gd     # 메뉴 · 메인 화면 탭 등록만 (얇게)
│  │  ├─ core/                      # RefCounted — csv_io, keygen, hasher, tokens, builder,
│  │  │                             #   validator, scanner, extractor (헤드리스 실행 가능)
│  │  ├─ sheet/                     # L10n 편집기 — 메인 화면 탭 (§11.1)
│  │  ├─ tests/                     # 샘플 CSV + 기대 결과
│  │  └─ README.md
│  (translation_preview 미도입 — D12, §11.2)
├─ data/
│  ├─ csv/                          # 기존 게임 데이터. 텍스트 컬럼은 key 를 담게 된다 (§6)
│  └─ l10n/
│     ├─ README.md
│     ├─ config.json                # §2.2
│     ├─ src/                       # ★ 편집 대상 원본
│     │  ├─ .gdignore
│     │  ├─ glossary.csv            # 용어집 (§4.5)
│     │  ├─ ui.csv                  # 도메인별 문자열 (§4.2)
│     │  ├─ card.csv
│     │  └─ ...
│     └─ generated/                 # ★ 생성물. 직접 수정 금지
│        ├─ strings_ko.csv          # Godot 임포트용 (헤더 keys,ko)
│        ├─ strings_en.csv
│        ├─ L.gd                    # alias → key 상수
│        ├─ index.json              # 카탈로그 + 사용처 인덱스
│        └─ report.md               # 검증 결과
└─ resources/
   └─ Loc.gd                        # 런타임 헬퍼 Loc.t() (§10.2)
```

- **`.gdignore`:** Godot 은 프로젝트 안의 `.csv` 를 기본으로 번역 파일로 임포트한다. 원본에는 메타 컬럼이 있으므로 임포트하면 안 된다. 도구는 `FileAccess` 로 `res://data/l10n/src/…` 를 직접 읽는다(에디터 · 헤드리스에서 동작 **(확인)**). 원본은 게임 실행에 필요 없으므로 export 에 포함되지 않아도 된다.
- **기존 `data/csv` 도 같은 문제가 있다.** 지금 모든 데이터 CSV 가 `csv_translation` 으로 임포트되어 쓸모없는 `.translation` 파일이 생겨 있다. 1단계(§15)에서 `data/csv/` 에도 `.gdignore` 를 두고(csv_to_db 는 `FileAccess` 로 읽으므로 영향 없음 **(확인)**) 생성된 `*.translation` · `*.csv.import` 를 지운다.
- 구현 시 루트 `CLAUDE.md` 의 Feature folders 표에 `data/l10n/` · `addons/l10n_tool/` 행을, Docs 표에 이 문서를 추가한다.

### 2.1 도메인 목록 (초안)

| 도메인 | 내용 |
|---|---|
| `ui` | 공통 버튼 · 팝업 · 시스템 메시지 |
| `lobby` · `run_setup` · `season` · `match` · `battle` | 화면 묶음별 UI 문구 (feature 폴더 대분류와 맞춘다) |
| `card` · `keyword` · `pilot_skill` · `mech_passive` · `trait` · `quirk` · `finance` · `training` · `scenario` · `manager` · `breakthrough` | 데이터 테이블 텍스트 (§6). `card` = 파일럿 + 메크 카드 (D17), `keyword` = 카드 · 특수 키워드 (D2) |
| `mental` | 멘탈 이벤트 대사 · 선택지 · 반응 (`mental_texts.csv`, D6) |
| `name` | 고유명사 — 팀 · 파일럿 · 메크 이름 |
| `press` | 기자회견 문장 |

도메인 추가는 자유지만, 한 도메인 파일이 2천 행을 넘으면 나누는 것을 검토한다.

### 2.2 `data/l10n/config.json`

```json
{
  "source_locale": "ko",
  "locales": ["ko", "en"],
  "fallback_locale": "en",
  "key_prefix": "tx_",
  "strict": { "orphans": "warn" },
  "tokens": {
    "josa_tags": ["eul", "eun", "i", "wa"],
    "ref_domains": ["card", "keyword"],
    "bbcode_tags": ["b", "i", "u", "s", "color", "font_size", "url", "img", "center"]
  },
  "scan": {
    "include_ext": [".gd", ".tscn", ".tres"],
    "exclude_dirs": ["res://addons/", "res://data/l10n/", "res://.godot/"],
    "scene_text_props": ["text", "placeholder_text", "tooltip_text", "title"],
    "ignore_paths": []
  },
  "data_columns": [
    { "csv": "cards.csv", "id": "id", "column": "name_key", "domain": "card", "alias": "card.pilot.{id}.name" },
    { "csv": "cards.csv", "id": "id", "column": "description_key", "domain": "card", "alias": "card.pilot.{id}.desc" }
  ]
}
```

- 로케일 코드는 Godot 표기(`ko`, `en`, `ja`, `zh_CN`).
- `josa_tags` 는 `StrategyIcon.JOSA` 의 키와 같아야 한다 — 검증기가 둘을 비교한다(E004).
- `strict.orphans` : `warn` 은 이행 기간(§14), 이행이 끝나면 `error` 로 올린다.
- `data_columns` 의 전체 목록은 이행 단계(§14)에서 채운다.

---

## 3. key 설계

한 문자열은 세 가지 식별 정보를 갖는다.

| 항목 | 예시 | 규칙 |
|---|---|---|
| **key** | `tx_7KQ2M9XA4P` | 불변. 런타임 조회와 모든 연결에 쓰는 유일한 ID |
| **domain** | `card` | 원본 CSV 파일명 |
| **alias** | `card.mech.6.name` · `lobby.start_button` | 사람이 읽는 이름. 바꿀 수 있다 |

### 3.1 key 형식

- `key_prefix` + Crockford Base32 대문자 10자. 정규식 `^tx_[0-9A-HJKMNP-TV-Z]{10}$` (혼동되는 `I L O U` 제외).
- `Crypto.generate_random_bytes()` 로 50비트 이상을 만든다.
- 발급 시 모든 원본의 기존 key(deprecated 포함)와 중복을 검사한다.
- 접두사 `tx_` 는 스캔에서 오탐 없이 key 를 찾기 위한 것이다. 바꾸지 않는다.
- 발급된 key 는 **삭제 · 재사용하지 않는다.** 쓰지 않으면 `deprecated` 로 둔다.

### 3.2 alias 형식

- 정규식 `^[a-z][a-z0-9_]*(\.[a-z0-9_*]+)+$` — 단, `*` 는 §9.3 패턴에서만 쓰고 실제 alias 에는 쓰지 않는다.
- **첫 세그먼트 = domain.** 프로젝트 전체에서 유일.
- 데이터 테이블 행은 `data_columns.alias` 규칙으로 정해진다(`card.{id}.name`) — id 가 바뀌지 않으므로 alias 도 고정된다.
- alias 를 바꿔도 key 는 그대로라 번역은 유지된다. 코드는 `L` 상수 이름이 바뀌어 파싱 오류로 드러난다.

---

## 4. 데이터 스키마 (CSV)

### 4.1 공통 형식

- 인코딩 **UTF-8 (BOM 허용)**. 파서는 BOM 을 떼고 읽고, 쓸 때 **기존 파일의 BOM 유무와 줄바꿈(CRLF/LF)을 보존**한다.
- 쉼표 구분, RFC 4180 따옴표 규칙(`"` → `""`).
- 첫 행은 헤더. **컬럼은 헤더 이름으로 찾고** 위치에 의존하지 않는다.
- 셀 안 줄바꿈은 **리터럴 `\n` 두 글자**로 쓴다 — 기존 데이터 CSV(`pilot_skills.description` 등)와 같은 규칙.
- Excel 에서는 반드시 "CSV UTF-8" 로 저장한다. 다른 인코딩은 E002.

### 4.2 도메인 파일 `data/l10n/src/<domain>.csv`

한 행 = 한 문자열. 원문과 모든 번역 언어가 같은 행에 있다.

| 컬럼 | 필수 | 설명 |
|---|---|---|
| `key` | ✔ | §3.1 |
| `alias` | ✔ | §3.2 |
| `status` | ✔ | `active` / `deprecated` |
| `context` |  | 번역자용 설명 — 어디에 뜨는지, 누가 말하는지, 톤 |
| `max_len` |  | UI 최대 글자 수 (정수, 로케일 공통) |
| `note` |  | 자유 메모 |
| `<source_locale>` | ✔ | 원문 (`ko`) |
| `<loc>` |  | 번역문. 비어 있으면 미번역 |
| `<loc>_status` |  | `draft` / `approved`. 비어 있으면 미착수 |
| `<loc>_hash` | 자동 | 이 번역의 기준이 된 원문 해시 (§8) |

- `<loc>` 3컬럼 묶음은 `config.locales` 의 원문 외 언어마다 하나씩 있다. 언어 추가는 `add_locale` 명령이 모든 도메인 파일에 컬럼을 붙인다.
- 원문에는 승인 단계가 없다. 원문은 고치는 즉시 유효하고, 바뀐 사실은 해시로 번역 쪽에서 드러난다(§8).

예시:

```csv
key,alias,status,context,max_len,note,ko,en,en_status,en_hash
tx_7KQ2M9XA4P,card.mech.6.name,active,메크 카드 이름,10,,로켓 펀치,Rocket Punch,approved,3f9a1c02
tx_B3PZ8RW1MC,card.mech.6.desc,active,카드 설명 패널,,,"공격. 명중 시 전략 점수 +{p1}, [캐시] 찾기","Attack. On hit, strategy +{p1}, search [Cache]",draft,a81e44d0
tx_Q9M2HX7ZK1,lobby.start_button,active,로비 시작 버튼,8,,새 시즌,,,
```

### 4.3 해시 규칙

- 정규화: `\r\n` → `\n` 만 한다. **앞뒤 공백은 자르지 않는다.**
- UTF-8 바이트의 SHA-1 → 소문자 hex 앞 8자. GDScript: `text.sha1_text().substr(0, 8)`.
- 유니코드 정규화(NFC)는 하지 않는다 — GDScript 에 정규화 API 가 없어 구현이 둘로 갈린다. 대신 분해된 한글 자모(U+1100–U+11FF)가 들어간 셀을 W003 으로 잡는다. 구현은 GDScript 하나뿐이다.

### 4.4 생성물 `generated/strings_<locale>.csv`

- 헤더 `keys,<locale>`, 로케일당 한 파일. **포함 조건(§7.3)을 만족하는 행만** 쓴다 — 빈 셀을 만들지 않는다.
- 원문 로케일 파일(`strings_ko.csv`)도 만든다 — key 가 GUID 라 원문도 번역 테이블이 필요하다.
- `\n` 은 리터럴 그대로 쓴다. Godot CSV 번역 임포터가 이를 개행으로 해석하는지 **(확인)** — 해석하지 않아도 `Loc.t()` 가 변환한다(§10.2). 씬에 직접 넣는 key 는 여러 줄 문장을 피한다.

### 4.5 용어집 `data/l10n/src/glossary.csv`

| 컬럼 | 필수 | 설명 |
|---|---|---|
| `term_id` | ✔ | `^[a-z][a-z0-9_]*$` — 사람이 짓는다 (런타임에 쓰지 않으므로 GUID 불필요) |
| `key` |  | 이 용어를 화면에 표시하는 문자열 key. 있으면 **각 언어 값은 그 key 에서 읽고** 아래 언어 컬럼은 비운다 (값 중복 금지, E072) |
| `<loc>` |  | 용어의 언어별 표준 표기 (`key` 가 없을 때) |
| `forbidden_<loc>` |  | 쓰면 안 되는 표기, `\|` 구분 (예: ko `손패\|핸드`) |
| `dnt` |  | `1` = 번역 금지 — 모든 언어에서 원문 표기 그대로 |
| `note` |  | 정의 · 사용 예 |
| `match_<loc>` |  | Regex (case-insensitive) that finds the term in `<loc>` text, replacing the substring rule for W072 and the index/editor term list — excludes word-internal hits (`(?<![가-힣])턴` skips 어시스턴트). Bad pattern = E074 |

예시 — 현재 `data/README.md` cards 행에 흩어져 있는 표기 규칙을 그대로 옮긴다:

```csv
term_id,key,ko,en,forbidden_ko,forbidden_en,dnt,note
hand,,손,hand,손패|핸드,,,카드를 들고 있는 곳
draw,,뽑기,draw,드로우,,,덱에서 카드를 가져오기
discard,,버린 더미,discard pile,묘지,graveyard,,
turn,,턴,turn,라운드,round,,
engage,tx_7ZKD3M1QWE,,,,,,교전 — 표시 문자열의 key 를 따른다
```

- 용어집은 검증 · 조회 전용 데이터다. 런타임에 읽지 않는다.
- 이행이 끝나면 `data/README.md` · `card_phase/README.md` 의 표기 규칙은 이 파일을 가리키는 한 줄로 바꾼다.

---

## 5. 텍스트 토큰 문법

문자열 안의 특수 표기는 네 종류이며 언어마다 규칙이 다르다.

| 종류 | 형식 | 규칙 | 검증 |
|---|---|---|---|
| **값 자리표시자** | `{name}` · `{p1}` (`{` + 소문자 식별자 + `}`, 조사 태그 이름 제외) | 원문과 모든 번역의 **집합이 같아야** 한다. 순서는 자유 | E033 |
| **조사 태그** | `{eul}` `{eun}` `{i}` `{wa}` | **원문 로케일(ko)에만** 허용. 런타임에 `StrategyIcon.resolve_josa` 가 처리 | E035 |
| **카드 참조** | `[카드 이름]` (괄호 안이 `bbcode_tags` 가 아님) | 원문의 `[x]` 는 `ref_domains` 의 원문 이름 중 하나여야 하고, 번역문에는 **같은 key 의 그 언어 이름**이 `[ ]` 로 들어가야 한다 | E034 |
| **줄바꿈** | 리터럴 `\n` | 자유 | — |

- 값 자리표시자에 들어갈 이름 · 숫자에 조사가 붙으면 ko 원문은 `{name}{i}` 처럼 태그를 쓴다. 다른 언어는 태그 없이 문장을 짠다.
- 카드 참조는 이름 문자열로 남긴다(Excel 에서 읽히도록). 검증기가 이름 → key 를 역으로 찾아 번역 쌍을 맞춘다. 원문 이름이 둘 이상의 key 와 같으면 E036.
- BBCode 는 현재 데이터에 없다. 쓰게 되면 원문과 번역의 태그 짝이 맞아야 한다(W034).

---

## 6. 데이터 테이블 연동 (`data/csv` → game.db)

카드 · 스킬 · 특성 · 시설 · 이름 같은 텍스트는 지금 `data/csv/*.csv` 의 텍스트 컬럼에 한국어로 들어 있고, csv_to_db 가 game.db 로 옮긴다. 이행 후:

- 데이터 CSV 의 텍스트 컬럼은 **key 컬럼으로 바뀐다**(`name` → `name_key`, 값 = `tx_…`). 텍스트 자체는 l10n 도메인 파일에만 있다.
- 매핑은 `config.data_columns` 가 정의한다: 어느 CSV 의 어느 컬럼이 어느 도메인 · alias 규칙에 대응하는지.
- csv_to_db 는 key 컬럼을 그대로 game.db 에 넣는다. 화면 코드는 `Loc.t(row.name_key)` 로 표시한다(§10.1 동적 key 주석 필요).
- 검증기는 `data_columns` 의 모든 셀이 존재하는 key 인지, alias 가 규칙(`card.{id}.name`)과 맞는지 본다(E041, E042).
- 스캐너는 `data_columns` 셀을 `kind=data` 사용처로 기록한다 — L10n 편집기 사용처에서 "card.csv" 로 보인다.
- 데이터 CSV 를 Excel 로 볼 때 이름이 key 로만 보이는 불편은 L10n 편집기(§11.1)와 alias 규칙으로 해결한다. 데이터 CSV 에 텍스트 사본 컬럼을 두지 않는다(파편화 금지).
- **런타임 키로 쓰이는 이름 문자열은 없어야 한다.** 이름으로 행을 찾는 코드가 있으면 이행 전에 id 조회로 바꾼다.

### 6.1 코드가 조립하는 문장

`TrainingTile.exp_summary()` · `effect_summary()` · `SCOPE_LABELS` 처럼 데이터에서 문장을 만드는 코드는:

- 문장 틀을 key 로 둔다: `training.effect.mult` = `"{scope} 경험치 +{pct}%"`.
- 라벨 표는 key 상수 딕셔너리로 바꾼다(§10.1 패턴).
- 문자열을 `+` 로 이어 붙여 문장을 만들지 않는다 — 어순이 다른 언어에서 깨진다. 항목을 나열할 때만 `list_separator` key(예: `", "`)로 잇는다.

---

## 7. 생성 파이프라인

### 7.1 명령

`Project → Tools → L10n` 메뉴와 L10n 편집기 버튼으로 제공하고, 같은 로직을 헤드리스(`godot --headless --script`)로도 부를 수 있게 한다 — csv_to_db 와 같은 구조(로직은 `core/` 의 RefCounted, `plugin.gd` 는 메뉴 등록만).

| 명령 | 동작 |
|---|---|
| `new_key <domain> <alias> <text> [context]` | key 발급 → `<domain>.csv` 끝에 `status=active` 행 추가 |
| `new_keys <json> [--out=<json>]` | 일괄 발급. 입력 = `[{"domain","alias","ko","context"?,"max_len"?,"note"?,"en"?}…]`(원문은 `source_locale` 이름, 번역 로케일은 선택 → draft + 해시). **전부 검사한 뒤**(alias 형식 · 첫 세그먼트 · `L` 상수 충돌 · 알 수 없는 필드 · 빈 원문 · Excel 잠금) 하나라도 틀리면 아무것도 바꾸지 않는다. 이미 있는 alias 는 원문이 같으면 그 key 재사용(`reused`), 다르면 오류. 도메인 파일이 없으면 표준 헤더로 만든다. 출력 = `alias → key`, `--out` = `[{alias, key, domain, status}]` |
| `extract data [csv…]` · `extract scenes <domain> <경로…> [--dry]` · `extract code [경로…] [--out=<json>]` | 고아 텍스트 일괄 처리 (§14) |
| `write_l` · `write_strings [dev\|release]` | 검증 관문 없이 `L.gd` / `strings_<loc>.csv` 하나만 다시 쓴다 — 병렬 이행 중 다른 작업의 Error 가 `build` 를 막을 때. 원본 읽기 오류(E001 · E002 · E003)가 있으면 거부 |
| `sync` | 번역 텍스트가 있는데 `<loc>_hash` 가 비어 있으면 현재 원문 해시를 기록하고 `<loc>_status=draft` 로 둔다 |
| `approve <locale> <keys…>` | `<loc>_status=approved`, `<loc>_hash=hash(현재 원문)`. **오너 지시 시에만** |
| `add_locale <locale>` | 모든 도메인 파일에 `<loc>` · `<loc>_status` · `<loc>_hash` 컬럼을 끝에 추가, config 갱신 |
| `rename_alias <old> <new>` | alias 변경 + `L.gd` 재생성 + 코드의 `L.OLD` 사용처 치환 |
| `scan` | 사용처 스캔 → `index.json` |
| `validate` | 검증만 → `report.md` |
| `build [dev\|release]` | `sync` → `validate` → (Error 0 이면) 생성물 작성 → `scan` |

- **Rebuild game.db 는 끝에 `build dev` 를 호출한다** — 데이터 CSV 의 key 컬럼과 l10n 원본이 항상 함께 검증되도록.

### 7.2 생성물

1. **`strings_<locale>.csv`** — §4.4. 생성기는 프로젝트 설정 `internationalization/locale/translations` 에 임포트된 번역 리소스가 등록돼 있는지 보고, 없으면 등록한다.
2. **`L.gd`**

   ```gdscript
   # 자동 생성 파일. 직접 수정 금지. (l10n_tool build)
   class_name L

   const UI_CONFIRM := "tx_C4RT8NW2HJ"
   const LOBBY_START_BUTTON := "tx_Q9M2HX7ZK1"
   ```

   - 상수 이름 = alias 대문자, `.` → `_`. 겹치면 E013. deprecated 는 `## @deprecated` 주석을 붙여 남긴다.
   - 데이터 테이블 alias(`data_columns`)는 코드가 상수로 부르지 않으므로 상수를 만들지 않는다.
3. **`refs.json`** — 설명문 `[x]` 참조 해석 결과 (D4). `{ "<문자열 key>": ["<참조 key>", …] }` — 원문의 `[x]` 등장 순서. `ref_domains` 의 key 만 들어간다. 커밋한다.
4. **`index.json`** — §9.4. 5. **`report.md`** — §13.

### 7.3 빌드 모드별 포함 조건

| 빌드 | 원문 | 번역 |
|---|---|---|
| `dev` | `deprecated` 포함 전부 (참조 깨짐 방지) | 텍스트가 있으면 전부 (stale 포함). **비어 있으면 원문을 넣는다** — 개발 중 화면에 `tx_…` 가 뜨지 않도록 |
| `release` | `active` 만 | `approved` 이면서 stale 아님. 비면 Godot 폴백(§10.3) |

### 7.4 버전 관리

- `generated/strings_*.csv` · `L.gd` · `refs.json` 은 프로젝트를 열 때 필요하므로 **커밋한다.** Godot 이 임포트해서 만드는 `*.translation` 은 `.gitignore` 한다(열 때 · CI `--import` 때 다시 만든다). 커밋되는 것은 항상 `dev` 결과다 — `release` 는 export 직전에만 실행하고 커밋하지 않는다.
- `index.json` · `report.md` 는 `.gitignore` 한다.
- 생성물 머지 충돌은 **수동으로 풀지 말고** 원본을 머지한 뒤 `build` 로 다시 만든다.

---

## 8. 번역 상태와 stale

| `<loc>_status` | 텍스트 | 의미 |
|---|---|---|
| (빈 값) | 비어 있음 | 미착수 |
| `draft` | 있음 | 번역됨, 검수 전 (LLM 번역은 항상 여기까지) |
| `approved` | 있음 | 오너 확정 |

- **stale** (저장하지 않는 파생 상태): `<loc>_hash ≠ hash(현재 원문)`. 원문을 고치면 그 행의 모든 번역이 stale 이 된다.
- stale 해소: 번역을 확인 · 수정한 뒤 `approve` 하면 해시가 갱신된다. 확인했는데 번역을 바꿀 필요가 없을 때도 `approve` 로 해시만 갱신한다.
- `report.md` 상단 진행표:

  ```
  | locale | total | 미착수 | draft | approved | stale | 진행률 |
  ```

  진행률 = (approved − stale) / active 원문 수.

---

## 9. 사용처 추적

### 9.1 목적

key 마다 **어느 파일 몇 번째 줄**에서 쓰이는지 역인덱스를 만든다. 미사용 key, deprecated key 의 잔존 사용, 고아 텍스트, 추적 불가 동적 key 를 찾는다. `.gd` · `.tscn` · `.tres` · CSV 가 모두 텍스트 파일이라 텍스트 스캔으로 충분하다.

### 9.2 스캔 규칙

| kind | 대상 · 패턴 (개념) | 처리 |
|---|---|---|
| `literal` | 모든 대상 파일의 `tx_[0-9A-HJKMNP-TV-Z]{10}` | 사용처 기록 |
| `const` | `.gd` 의 `\bL\.([A-Z][A-Z0-9_]*)` | 상수 → key 로 바꿔 기록. 없는 상수면 E051 |
| `data` | `config.data_columns` 의 셀 | 사용처 기록 (`file` = CSV, `line` = 행) |
| `dynamic` | `# l10n-dynamic: <alias 패턴>` 이 붙은 줄 | 패턴에 맞는 모든 key 에 기록 |
| `orphan_scene` | `.tscn`/`.tres` 의 `scene_text_props` 값이 key 가 아니고 글자를 포함 | W052 (strict 시 E052) |
| `orphan_code` | `.gd` 의 한글 포함 문자열 리터럴, 또는 `tr()` · `Loc.t()` 의 첫 인자가 key 아닌 리터럴 | W053 (strict 시 E053) |
| `dynamic_bare` | `tr()` · `Loc.t()` 의 첫 인자가 리터럴도 `L.` 상수도 아니고 주석도 없음 | W054 |
| `preview_leak` | 씬 텍스트가 어떤 key 의 **번역문과 정확히 일치** | E057 — 미리보기 플러그인이 번역문을 씬에 저장한 흔적 (§11.2) |

- `# l10n-ignore` 를 붙인 줄과 `scan.ignore_paths` 는 고아 검사에서 뺀다(디버그 UI, 치트 메뉴 등).
- **씬 노드의 `auto_translate_mode = 2`(`AUTO_TRANSLATE_MODE_DISABLED`)는 "이 텍스트는 스크립트가 채운다"는 표시**다 — 그 노드의 값은 `orphan_scene`(W052/E052) · `preview_leak`(E057) 대상이 아니고 `extract scenes` 도 건너뛴다. 씬에 WYSIWYG 미리보기용 자리표시 텍스트를 남기되 런타임에 코드가 `Loc.t()` 로 덮어쓰는 노드에 쓴다. Godot 4.5 는 기본값(INHERIT 0)이 아닐 때만 노드 섹션에 `auto_translate_mode = <n>` 줄을 저장하고(ALWAYS 1 · DISABLED 2), INHERIT 는 부모 값을 따른다. 스캐너는 **같은 파일 안에서** 부모 경로를 따라 올라가 처음 만난 명시 값을 쓴다(자식이 1 로 되돌리면 다시 검사 대상). 파일에 없는 조상(인스턴스한 씬 내부 노드의 부모)은 건너뛰고, 끝까지 없으면 번역 대상으로 본다 — 인스턴스를 놓은 쪽에서 DISABLED 로 둔 것은 하위 씬 파일 검사에 전해지지 않는다(하위 씬 자체에 표시한다).
- 씬 값은 Godot 의 `.tscn` 문자열 표기(`\\` · `\"` 만 이스케이프, 줄바꿈은 그대로)를 앞에서부터 풀어 비교한다(`String.c_unescape` 는 `\\n` 을 줄바꿈으로 잘못 푼다).
- `orphan_scene` 항목은 index.json 에 `prop` · `node`(루트 기준 노드 경로)도 담는다.
- `UiPreview` 의 `_fill_preview()` 더미 데이터는 고아 검사 대상이다 — 더미라도 표시 문구면 key 를 쓰고, 순수 더미 값(가짜 이름 · 숫자)은 함수 단위로 `# l10n-ignore` 한다.

### 9.3 동적 key 패턴

```gdscript
const SCOPE_LABELS := {            # l10n-keys: training.scope.*
	"all": L.TRAINING_SCOPE_ALL,
	"role": L.TRAINING_SCOPE_ROLE,
}
label.text = Loc.t(SCOPE_LABELS[scope])         # l10n-dynamic: training.scope.*
name_label.text = Loc.t(card.name_key)          # l10n-dynamic: card.*.name
```

alias 패턴의 `*` 는 세그먼트 하나에 맞는다.

### 9.4 `index.json`

```json
{
  "generated_at": "2026-10-07T12:00:00Z",
  "keys": {
    "tx_7KQ2M9XA4P": {
      "alias": "card.mech.6.name",
      "domain": "card",
      "status": "active",
      "source": { "text": "로켓 펀치", "hash": "3f9a1c02" },
      "translations": { "en": { "text": "Rocket Punch", "status": "approved", "stale": false } },
      "glossary": ["engage"],
      "usages": [
        { "file": "res://data/csv/mech_cards.csv", "line": 7, "kind": "data" },
        { "file": "res://features/battle_sim/card_phase/CardView.gd", "line": 42, "kind": "dynamic" }
      ]
    }
  },
  "orphans": [ { "file": "res://features/meta/lobby/Lobby.gd", "line": 31, "kind": "orphan_code", "text": "새 시즌" } ],
  "dynamic_bare": [ { "file": "res://features/season/HubView.gd", "line": 18 } ]
}
```

---

## 10. 코드 작성 규칙과 런타임

### 10.1 코드 규칙 (LLM 이 게임 코드를 쓸 때)

- 코드의 텍스트는 **항상 `Loc.t(L.X)`** 로 쓴다. 데이터 행의 텍스트는 `Loc.t(row.xxx_key)` + `# l10n-dynamic` 주석.
- 씬에 고정 텍스트를 넣을 때는 `text` 에 key 리터럴(`tx_…`)을 넣는다. Control 의 자동 번역(`auto_translate_mode`)이 기본값(상속 → 켜짐)인지 확인한다.
- `tr("tx_" + id)` 같은 **문자열 조립 금지.** 상수 딕셔너리 + `# l10n-keys` / `# l10n-dynamic` 주석.
- 세이브(`run.save`, `profile.save`)에는 **표시 문자열을 저장하지 않는다** — id 나 key 만 저장하고 표시할 때 변환한다. 이행 때 `season_state` (예: `team_meta`)에 이름이 복사돼 있는지 점검한다.

### 10.2 `Loc.t(key, params := {})` — `resources/Loc.gd`

모든 코드 텍스트가 거치는 단일 경로:

1. `TranslationServer.translate(key)`
2. `params` 로 값 자리표시자 치환 (`String.format`)
3. `\n` 리터럴 → 개행, 조사 태그 처리 (`StrategyIcon.resolve_josa` — 원문 로케일이 아니면 태그가 없으므로 그대로 통과)

조사는 자리표시자를 채운 **뒤에** 처리해야 이름 받침을 볼 수 있다. 현재 `resolve_josa` 를 직접 부르는 곳은 `Loc.t` 로 바꾼다.

### 10.3 폴백

- 프로젝트 설정 `internationalization/locale/fallback` = `config.fallback_locale` (`en`).
- Godot 은 현재 로케일에 번역이 없으면 폴백 로케일을, 거기도 없으면 **key 를 그대로** 돌려준다 **(확인)**.
- dev 빌드는 빈 번역을 원문으로 채우므로(§7.3) key 가 보이지 않는다. 개발 중 `tx_…` 가 보이면 생성물 등록 누락이다.
- release 빌드는 사용 중인 모든 active key 에 대해 `fallback_locale` 번역이 approved · 비-stale 이어야 한다(E061).

### 10.4 언어 전환

- 언어 선택은 로비(아웃게임)에서만 한다. 바꾸면 `TranslationServer.set_locale()` 후 **현재 씬을 다시 로드**한다 — 코드가 채운 텍스트를 화면마다 갱신하는 처리(`NOTIFICATION_TRANSLATION_CHANGED`)는 만들지 않는다.
- 선택한 언어는 `profile.save` 에 로케일 코드로 저장한다.

### 10.5 폰트 · 길이

- `ja` · `zh_*` 를 추가하기 전에 `OutgameTheme` · `BattleTheme` 의 기본 폰트에 CJK 폴백 폰트를 붙인다. 언어 추가 체크리스트 항목이다.
- UI 길이 점검은 `max_len`(W035) + Godot 내장 의사 현지화(Pseudolocalization)를 쓴다. 원문이 한글이라 악센트 치환은 효과가 없고, 괄호 · 길이 늘리기만 의미가 있다 — 괄호가 없는 텍스트 = `tr()` 을 안 거친 텍스트.

---

## 11. 에디터 도구

### 11.1 L10n 편집기 (`addons/l10n_tool/sheet/`)

> 2026-10-08: 오른쪽 조회 도크를 없애고 메인 화면 `L10n` 탭 하나로 합쳤다 — 탭: 키(§11.3 표) · 용어집 · 고아 텍스트 · 씬 미리보기 · 로그.
> 아래 1~ 항목은 그 탭들이 그대로 지킨다.

데이터는 `index.json` 과 원본 CSV. **읽기 위주** — 텍스트 편집은 §11.3 표 편집기(또는 CSV).

1. **검색:** key · alias · 원문 · 모든 번역문 · 용어집 term 의 부분 문자열.
2. **필터:** domain, 로케일별 status, stale, 미사용, 고아 텍스트, 용어집 위반.
3. **상세 패널:** alias, context, max_len, 원문 · 모든 번역과 상태 · stale, 걸린 용어집 항목, 사용처 목록.
4. **사용처 이동:** 더블클릭 → 스크립트는 해당 줄, 씬은 씬 열기, 데이터 CSV 는 파일 경로 · 행 번호를 복사.
5. **용어집 탭:** term 별 표준 표기 · 금지 표기 · 그 용어가 들어간 key 목록.
6. **버튼:** `new_key`, `sync`, `validate`, `build dev`, `scan`. `approve` 는 확인 대화상자를 띄운다(사람 전용).

### 11.2 씬 미리보기 — 자체 구현 (D12)

씬에 key(`tx_…`)가 들어가면 에디터 화면이 key 로 도배된다. 서드파티 Translation Preview 는 노드 `text` 를 번역문으로 바꿨다가 되돌리는 방식이라 번역문이 씬에 저장되는 누수 위험이 있어 **도입하지 않는다.**

- L10n 편집기의 **씬 미리보기 탭**: 현재 편집 중인 씬의 노드를 훑어 `scene_text_props` 값이 key 인 노드를 `노드 경로 · key · alias · 선택 로케일 번역문` 표로 보여 준다. 행을 누르면 그 노드를 선택한다.
- 노드의 속성은 **절대 쓰지 않는다** — 씬 파일이 바뀌지 않으므로 누수가 생기지 않는다.
- 검증기의 `preview_leak`(E057)은 그대로 둔다 — 씬 텍스트가 번역문과 같으면(손으로 붙여 넣은 경우) 잡는다. `validate --fix-preview-leak` 은 번역문 → key 가 하나로 정해지는 경우 key 로 되돌린다.
- `UiPreview` 의 F6 단독 실행은 런타임이므로 번역된 텍스트가 그대로 보인다.

### 11.3 표 편집기 (`addons/l10n_tool/sheet/`)

에디터 메인 화면 `L10n` 탭(UI 는 에디터 언어 ko / en). 한 행 = key, 열 = alias · 원문 · 언어별 번역(상태 = 셀 앞 색 점:
미착수 빨강 · draft 노랑 · approved 초록 · stale 주황). "모든 언어" 는 번역 열만, 언어를 고르면("언어: en") 그 열 +
context · max_len · note — 스프레드시트처럼 셀을 바로 고친다. 쓰기는 파사드 `cmd_edit` 하나(디스크 재읽기 → 전부 검사 → 저장, §12 와 같은 Excel 잠금 규칙).
번역 수정은 draft(§0.5 — approve 는 키 탭 `승인…` 메뉴, 오너만), 원문 수정은 번역을 stale 로 만든다. 저장만 하고 `build dev` 는 따로.
alias 변경(`rename_alias`) · status(active/deprecated)는 편집 대상이 아니다.
사용처(`index.json`)는 아래 목록 · 행 우클릭 메뉴로 이동한다 — 코드 줄 · 씬은 Godot 안, 데이터 · 원본 CSV 는 외부 편집기의 그 줄.
사용처마다 그 파일이 나오는 게임 화면(`screen_map.gd`)과 사용 줄 미리보기를 보여 준다. 게임 화면에서 거꾸로 찾을 땐
개발 빌드의 key 표시 모드(`autoloads/L10nKeyMode.gd`, Ctrl+Alt+K / `--l10n-keys`) — 모든 텍스트가 alias 로 보인다.

---

## 12. 동시 편집 정책

### 12.1 충돌 상황

1. 오너가 Excel 로 CSV 를 열어 둔 상태에서 LLM 에이전트가 같은 파일을 수정 → 한쪽 변경이 덮어써진다.
2. Git 브랜치 머지 (기능 브랜치에서 문구 추가 · 메인에서 번역 갱신).
3. 여러 PC 에서 작업 후 동기화.

### 12.2 대응

| 대응 | 효과 |
|---|---|
| 도메인별 파일 | 서로 다른 화면 · 데이터 작업은 다른 파일을 건드린다 |
| 랜덤 GUID key | 브랜치마다 새 key 를 발급해도 충돌 없음 (순번 ID 금지) |
| **새 행은 끝에 추가, 정렬 · 재포맷 금지** | diff 최소화, 서로 다른 행 수정은 자동 머지 |
| 생성물은 재생성으로만 해결 | 생성물 충돌을 사람이 풀 필요 없음 |

- 모든 언어가 한 행에 있으므로, **같은 key 의 서로 다른 언어를 두 브랜치에서 동시에 고치면 행 단위 충돌**이 난다. 이것은 파편화를 피한 대가로 받아들이고, 아래 규칙으로 푼다.

### 12.3 LLM 에이전트 편집 규칙

- 편집 전에 같은 폴더에 Excel 잠금 파일(`~$…`)이 있으면 **쓰지 않고** 오너에게 파일을 닫아 달라고 요청한다.
- 파일 전체를 다시 쓰지 않고 **필요한 행 · 셀만** 바꾼다. 재직렬화가 불가피하면 BOM · 줄바꿈 · 따옴표 스타일 · 컬럼 순서를 원본과 같게 유지한다(도구의 `csv_io` 를 쓴다).
- 작업 보고에 수정한 파일과 행 수를 적는다.
- CSV 머지 충돌은 **key 행 단위**로 푼다: 양쪽이 추가한 서로 다른 key 행은 둘 다 유지, 같은 key 행이 양쪽에서 바뀌었으면 **셀 단위로 합치고**(서로 다른 컬럼이면 둘 다 반영), 같은 셀이 다르면 오너에게 확인한다.

---

## 13. 검증 규칙

`validate` 가 실행하고 `report.md` 에 코드 · 파일 · 줄 · key 와 함께 쓴다. **Error 가 하나라도 있으면 `build` 는 생성물을 쓰지 않는다.**

| 코드 | 수준 | 조건 |
|---|---|---|
| E001 | Error | CSV 파싱 실패 (따옴표 불일치 등) |
| E002 | Error | UTF-8 이 아닌 인코딩 |
| E003 | Error | 필수 컬럼 누락 / 알 수 없는 status 값 / `config.locales` 와 컬럼 불일치 |
| E004 | Error | `tokens.josa_tags` ≠ `StrategyIcon.JOSA` 키 |
| W003 | Warn | 분해된 한글 자모(U+1100–U+11FF) 포함 |
| E010 | Error | key 형식 위반 |
| E011 | Error | key 중복 (전체 원본) |
| E012 | Error | alias 형식 위반 / 첫 세그먼트 ≠ domain / alias 중복 |
| E013 | Error | `L` 상수 이름 충돌 |
| E031 | Error | 번역 `approved` 인데 `<loc>_hash` 비어 있음 (수동 승인) |
| W031 | Warn | stale 번역 |
| W032 | Warn | 번역 텍스트가 없는데 `<loc>_status` 가 있음 |
| E033 | Error | 원문과 번역의 값 자리표시자 집합 불일치 |
| E034 | Error | 카드 참조 `[x]` 가 참조 도메인 이름에 없음 / 번역문의 참조가 그 key 의 번역 이름과 다름 |
| E035 | Error | 원문 외 로케일에 조사 태그 |
| E036 | Error | 참조 도메인에 같은 원문 이름의 key 가 둘 이상 |
| W034 | Warn | BBCode 태그 짝 불일치 |
| W035 | Warn | `max_len` 초과 (로케일별) |
| E041 | Error | `data_columns` 셀이 존재하지 않는 key |
| E042 | Error | `data_columns` key 의 alias 가 규칙(`card.{id}.name`)과 다름 |
| E051 | Error | 존재하지 않는 `L.` 상수 사용 |
| W052 / E052 | Warn → Error | 씬 · 리소스 고아 텍스트 (`strict.orphans`) |
| W053 / E053 | Warn → Error | 코드 고아 텍스트 (`strict.orphans`) |
| W054 | Warn | 주석 없는 동적 key |
| E055 | Error | deprecated key 가 사용 중 |
| W056 | Warn | active key 인데 사용처 0 |
| E057 | Error | 미리보기 누수 — 씬 텍스트가 어떤 key 의 번역문과 일치 |
| E061 | Error | (release) 사용 중인 key 의 `fallback_locale` 번역이 approved · 비-stale 이 아님 |
| W071 | Warn | 원문 · 번역문에 용어집 금지 표기 |
| W072 | Warn | 원문에 용어가 있는데 번역문에 그 언어 표준 표기가 없음 (`dnt` 용어는 원문 표기) |
| E072 | Error | 용어집 행에 `key` 와 언어 컬럼 값이 함께 있음 / `key` 가 존재하지 않음 |
| E073 | Error | 용어집 `term_id` 중복 · 형식 위반 |
| E074 | Error | 용어집 `match_<loc>` 정규식 컴파일 실패 |

- 용어 매칭(W071 · W072)은 1차로 **부분 문자열 일치**로 한다. Implemented extension: a glossary row's `match_<loc>` regex replaces the substring rule for standard-form presence (W072); forbidden forms (W071) stay substring.

---

## 14. 이행 계획 (기존 텍스트 → l10n)

현재 `.gd` 에 한글 문자열 리터럴 약 2,100개, `.tscn` 100여 개 파일에 한글 텍스트, 데이터 CSV 텍스트 컬럼이 있다. `new_key` 로 하나씩 옮기지 않고 `extract` 로 일괄 처리한다.

| 순서 | 대상 | 방법 |
|---|---|---|
| 1 | 데이터 CSV (`data_columns`) | `extract data` — 각 셀의 텍스트로 key 발급 → 도메인 파일에 행 추가 → 데이터 CSV 셀을 key 로 치환 → 로더 · 화면 코드를 `Loc.t(row.xxx_key)` 로 수정. **컬럼 이름 변경(`name` → `name_key`)은 csv_to_db `SCHEMAS` 와 로더도 함께** |
| 2 | 씬 (`.tscn` · `.tres`) | `extract scenes <domain> <경로…> [--dry]` — scanner 가 고아(`orphan_scene`)로 보는 `scene_text_props` 값마다 key 를 발급하고 **그 값 바이트만** key 로 바꾼다(BOM · 줄바꿈 · 나머지 그대로, 원문 ko 만, 두 번 돌려도 같다). alias = `<domain>.<scene>.<node>[.<prop>]` — scene = 파일 이름에서 `UI_View_` · `UI_Comp_` 를 뗀 snake_case(`UI_View_BattleHud.tscn` → `battle_hud`), node = 노드 이름 snake_case(`.tres` 는 `resource` · `sub_<id>`), `.<prop>` 는 prop 이 `text` 가 아닐 때만. 충돌하면 `<부모>_<노드>` → `<노드>_2`, `_3` … 순(파일 이름 순 → 파일 안 순서라 결정적). context = `<파일 이름> <노드 경로> <prop>`; 같은 alias 가 원문 · context 까지 같으면 그 key 를 재사용한다(씬만 되돌린 경우). 스크립트가 덮어쓰는 자리표시 노드는 먼저 `auto_translate_mode = 2` 로 표시해 둔다(§9.2) |
| 3 | 코드 (`.gd`) | `extract code [경로…] [--out=<json>]` 은 **작업 목록만** 만든다(기본 `generated/extract_code.json`, gitignore) — 파일마다 scanner 의 `orphan_code` `{line, text}`. **본문과 다름(오케스트레이터 승인)**: 코드 문자열의 alias 는 자동으로 짓지 않고, 이행하는 LLM 이 문맥을 보고 정해 `new_keys` 로 한 번에 발급한 뒤 파일 단위로 `Loc.t(L.X, {...})` 로 바꾼다 — 포맷 문자열 · 연결 · 조사 처리가 섞여 자동 치환이 위험하다. 병렬 작업이면 `--out` 으로 작업자마다 파일을 나눈다 |
| 4 | 문장 조립 코드 | §6.1 패턴으로 수동 이행 |
| 5 | 세이브 | `season_state` 등에 표시 문자열이 저장되는 곳을 id · key 로 교체 |
| 6 | 마감 | 고아 0 → `strict.orphans` 를 `error` 로. 용어 규칙이 적힌 README 들을 `glossary.csv` 참조로 교체 |

- 같은 텍스트가 여러 곳에 있으면 `extract` 는 **문맥이 다르면 key 를 따로**, 같은 의미면 하나로 묶는다. 기계적으로 판단할 수 없으므로 `extract` 는 중복 텍스트 목록을 보고서로 내고, 묶을지는 오너가 정한다.
- 이행은 feature 폴더 단위로 나눠 커밋한다. 폴더를 하나 마칠 때마다 그 폴더 README 에 "텍스트는 l10n key" 를 적는다.

---

## 15. 구현 단계와 완료 기준

| 단계 | 범위 | 완료 기준 |
|---|---|---|
| 1 | `data/csv` 임포트 정리, `csv_io` · `keygen` · `hasher` · config, `new_key`, `add_locale` | 쓸모없는 `.translation` 0개, BOM · CRLF 보존 왕복 테스트 통과, 1만 개 발급 시 중복 0 |
| 2 | `validate` — 데이터 · 토큰 · 용어집 규칙 (E0xx, W03x, W07x), `report.md` | 샘플 데이터의 의도적 오류가 모두 검출됨 |
| 3 | `build dev/release`, `L.gd`, `strings_*.csv`, 프로젝트 설정 등록, `Loc.gd`, Rebuild game.db 연동 | 게임에서 로케일 전환 시 텍스트가 바뀜, release 에서 미승인 번역이 폴백으로 표시됨 |
| 4 | `sync` · `approve`, stale 계산, 진행표 | 원문 수정 시 해당 번역이 stale 로 표시됨 |
| 5 | `scan` · `index.json` · 사용처 검증 (E05x · W05x · E057) | 샘플 프로젝트의 사용처가 줄 번호까지 정확함 |
| 6 | 조회 도크 + 자체 씬 미리보기 (D12) — 2026-10 L10n 편집기로 통합 | 검색 · 필터 · 사용처 이동 · 용어집 탭 동작, 씬 미리보기가 씬 파일을 바꾸지 않음, 씬 텍스트 누수가 E057 로 잡힘 |
| 7 | `extract` (§14) 와 이행 | 고아 0, `strict.orphans = error` |

각 단계는 `addons/l10n_tool/tests/` 에 샘플 CSV 와 기대 결과를 두고 헤드리스로 실행되는 테스트를 함께 쓴다.

**TODO (D13) — CI release 연동:** 코드 · 씬 이행과 en 번역 approve 가 끝나면 `.github/workflows/ios-testbuild.yml` 의 export 앞에 헤드리스 `build release`(Error 시 실패)를 넣는다. 그 전까지 CI 는 커밋된 dev 생성물로 export 한다.

---

## 16. 향후 확장 (현재 범위 아님)

- **PO 출력** — 외부 번역자 · 번역 플랫폼에 맡길 때, 언어별 복수형(`tr_n`)이 필요할 때. 원본은 계속 CSV 이고 PO 는 생성물로만 만든다. 매핑: `msgctxt` = alias, `msgid` = 원문, `msgstr` = 번역, `#.` 주석에 key · context · max_len · 용어. 돌아온 번역은 `import_po` 로 key 기준 반영하고 `draft` 로 둔다. 이를 위해 alias · context 를 지금부터 유지한다.
- **번역가용 내보내기** — 한 언어만 담은 CSV 를 내보내고(`export <locale>`) 받은 파일을 key 기준으로 다시 합치는(`import <locale>`) 명령. 원본 구조는 바꾸지 않는다.
- **음성(VO)** — 도입 시 `vo_status` · `vo_hash` 컬럼(로케일별)과 `res://vo/<locale>/<key>.ogg` 규칙을 추가한다.
