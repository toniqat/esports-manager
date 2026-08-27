# Match Flow — Ban/Pick

## BanPickController.gd
`extends Node` — child of MatchFlow.

Implements the LoL-international ban/pick draft against a random AI opponent.

### Sequence (14 actions)
Pattern: `B-B-P-PP-PP-P-B-B-PP-PP` — 4 bans + 10 picks total. Each side ends
with **2 bans + 5 picks**.

| # | Side | Kind |
|---|---|---|
| 0 | Blue | Ban |
| 1 | Red | Ban |
| 2 | Blue | Pick |
| 3 | Red | Pick |
| 4 | Red | Pick |
| 5 | Blue | Pick |
| 6 | Blue | Pick |
| 7 | Red | Pick |
| 8 | Blue | Ban |
| 9 | Red | Ban |
| 10 | Blue | Pick |
| 11 | Blue | Pick |
| 12 | Red | Pick |
| 13 | Red | Pick |

The constant `SEQUENCE` encodes this directly. `player_side` (BLUE or RED) is
passed in by MatchFlow — 지금은 **항상 BLUE 로 고정**이다(`match_flow/README.md`
의 진영 절 참조).

---

## 화면

세로 한 장을 **위 / 가운데 / 아래** 세 덩이로 나눈다.

```
┌──────────────────────────────────────────┐
│ ▪▪▪▪▪▪▪▪▪▪▪▪▪▪   순서 표시 (14칸)          │
│      BLUE 픽 — 내 차례  (7 / 14)          │
├──────────────────────────────────────────┤ ← 상대 팀 블록
│ RED · Team 1                    BAN ✕ ▫  │
│ ▓▓  ▓▓  ▓▓  ▓▓  ▓▓   눈높이 초상화 5인      │
│ 이름 이름 이름 이름 이름                    │
│ [메크][메크][픽3][픽4][픽5]  픽 슬롯        │
├──────────────────────────────────────────┤
│ [전체][TANK][FIGHTER][ASSASSIN][SUP][SNP] │
│ ▤ ▤ ▤ ▤ ▤    ← 5열                       │
│ ▤ ▤ ▤ ▤ ▤      3.5줄이 보이는 수직 스크롤    │
│ ▤ ▤ ▤ ▤ ▤                                │
│ ▤ ▤ ▤ ▤ ▤    (넷째 줄은 반쯤 잘린다)         │
├──────────────────────────────────────────┤ ← 아군 팀 블록 (거울)
│ [메크][메크][픽3][픽4][픽5]                 │
│ 이름 이름 이름 이름 이름                    │
│ ▓▓  ▓▓  ▓▓  ▓▓  ▓▓                        │
│ BLUE · Team 0                   BAN ✕ ▫  │
└──────────────────────────────────────────┘
```

### 파일럿 초상화 (위 = 적 / 아래 = 아군)
전장 스트립과 **같은 eye 크롭**(`PilotImages.eye_for`, 480×200)이다 — 인게임
상단 / 하단에서 보던 얼굴이 밴픽에서도 같은 자리에 선다. 칸 높이는 그 비율
(`EYE_ASPECT` 2.4)에서 유도한다: 임의 높이로 늘리면 얼굴이 찌그러진다.

> **`TextureRect.expand_mode` 를 `texture` 보다 먼저 준다.** 기본
> `EXPAND_KEEP_SIZE` 에서는 텍스처 크기가 그대로 **최소 크기**가 되어, 그 뒤에
> 준 `size` 가 위로 잡아당겨진다 — 480×200 짜리 eye 크롭이 192×80 칸을 뚫고
> 나와 아래 이름·픽 슬롯을 통째로 덮었고, 1024² 메크 아트는 시트 전체를
> 가렸다(둘 다 실측). 이 파일의 `TextureRect` 다섯 자리가 전부 그 순서를 지킨다.

### 픽 슬롯 = 파일럿이 아니라 픽 순서
**배정은 ASSIGN 단계**라 이 시점에 어느 파일럿이 어느 메크를 타는지는 아직
정해지지 않았다. 그래서 픽 슬롯은 초상화와 짝지어지지 않고 **픽 순서대로
왼쪽부터** 채워진다 — "우리 팀이 가져간 다섯 대"라는 뜻이지 "이 선수의 기체"
라는 뜻이 아니다. 칸에는 기체 썸네일 · 기체명 · **패시브 이름**이 들어간다.

아래 블록은 위 블록을 **거울로 뒤집은 순서**(픽 → 이름 → 초상화 → 밴)다. 두
팀의 픽 슬롯이 격자를 사이에 두고 마주 보므로 지금까지 어느 쪽이 뭘 가져갔나가
격자 위아래 한 줄씩으로 읽힌다.

### 메크 격자
`GRID_COLS` 5열, `GRID_VISIBLE_ROWS` **3.5줄**. 정수가 아닌 것이 요점이다 —
넷째 줄이 반쯤 잘려 보이는 것이 "아래로 더 있다"는 유일한 신호다. 칸 **폭**은
열 수가, **높이**는 남은 세로 공간에서 3.5로 나눠 역산한다(`_layout()`) — 그래야
안전 영역이 다른 기기에서도 "3.5줄"이 지켜진다.

한 칸에 들어가는 것: 역할군 태그 · 기체 아트 · 기체명 · `HP / ATK / 존재감` ·
**패시브 이름**. 패시브를 칸에 그대로 적는 이유는 기체를 고르는 순간 패시브
하나가 함께 정해지기 때문이다 — 그걸 보려고 매번 시트를 열어야 하면 21대를
훑는 데 탭이 21번 든다. 자세한 설명문만 시트가 들고 있다.

밴 / 픽된 기체는 칸 전체가 슬래브로 덮이고 한가운데에 `BAN` / `BLUE` / `RED`
가 찍힌다(색도 함께 바뀐다). 여전히 눌러서 **볼 수는** 있고 확정만 막힌다.

**썸네일은 구워서 쓴다** — 원본 메크 아트는 1024² 무압축이라 21대를 그대로
들고 있으면 VRAM 88MB 다. `_bake_thumbs()` 가 `THUMB_PX`(256) 로 한 번 줄여
`ImageTexture` 로 굽고 원본 참조를 놓아 준다. 시트만 원본 전신 아트를 쓰고,
그건 언제나 한 대뿐이다.

### 역할군 필터
`[전체][TANK][FIGHTER][ASSASSIN][SUPPORT][SNIPER]` 여섯 탭이 **격자를 걸러
낸다**. 걸러진 칸은 숨기고 **자리도 비운다** — 빈 칸을 남기면 그 역할군에 몇
대가 있는지가 안 읽힌다(`_apply_filter()` 가 유일하게 자리를 흘려 놓는 곳).

### 하단 시트 (1탭 선택 → 2탭 확정)
메크를 한 번 누르면 격자 위로 시트가 올라와 그 기체의 **스탯 · 패시브(이름 ·
키워드 · 설명문) · 카드 셋**을 보여 준다. 확정은 시트의 `밴 확정` / `픽 확정`
버튼이거나 **같은 메크를 한 번 더 누르는 것**이다. 한 번 누르면 곧장 나가던
예전 방식은 되돌릴 수 없는 선택에서 실수 한 번이 경기를 통째로 바꿨다.

- 시트는 **내 차례가 아닐 때도 열린다** — 상대가 고민하는 동안 다음에 뭘 고를지
  들여다보는 것이 밴픽 화면이 하는 일의 절반이다. 그때는 확정 버튼만 잠기고
  `상대 차례` / `선택 불가` 로 이유를 적는다.
- 딤은 **격자와 필터 탭만** 덮는다 — 위아래 팀 블록은 지금까지의 밴픽 상황이라
  시트를 보는 동안에도 보여야 한다(무엇이 이미 나갔는지 모르면 이 기체를 고를지
  판단할 수 없다). 딤을 누르면 닫힌다.
- 카드는 손패와 **같은 노드**(`Card.tscn`, `SHEET_CARD_SCALE` 0.9)다 — 따로 그린
  그림이면 실제로 덱에 들어갈 카드와 같은 것인지 확인할 길이 없다. `CardData`
  조립은 `CardData.from_def()` 한 곳을 지난다(`DraftDetailPanel` 과 같은 경로).
  `add_child` 를 `setup` 보다 **먼저** 부를 것 — `Card.gd` 의 `@onready` 참조는
  트리에 들어간 뒤에야 풀린다.
- 카드 밑의 배지는 `count` 다. `count = 0` 인 카드는 덱에 처음부터 들어가지 않고
  패시브나 다른 카드가 만들어 줄 때만 세상에 나오므로 `생성 전용` 이라 적는다 —
  그 사정을 적어 두지 않으면 "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
- 왼쪽 아트 칸은 **폭만 상수**(`SHEET_ART_W`)이고 높이는 시트에서 남는 만큼을
  통째로 쓴 뒤 그 안에서 세로 가운데 정렬한다 — 아트를 위에 붙이면 그 밑에
  아무것도 없는 구멍이 300px 넘게 남는다(정사각 아트라 폭을 늘리는 것 말고는
  커지지 않는다).

### 진입 (`enter`)
```gdscript
enter(all_mechs, player_side,
      player_roster, enemy_roster,        # Array[PlayerData] (역할 0..4 정렬)
      player_team_name, enemy_team_name)  # String
```
로스터와 팀명은 위아래 초상화 줄을 세우는 데 쓰인다. 뒤 네 개는 기본값이
있으므로 BanPick 만 따로 띄우는 경우에도 돌아간다(초상화 자리는 빈 뒤판).

### Opponent AI
Simple: when `SEQUENCE[_action_idx][0] != _player_side`, after a 0.45 s delay
the AI picks/bans a random legal mech.

### Output
Emits `phase_finished({banned, player_picks, enemy_picks})` once index 14 is
reached. `player_picks` / `enemy_picks` are mapped from blue/red to the user's
perspective. 밴은 합법성 판정용 `_banned`(양 팀 합본)와 표시용
`_side_bans[side]` 두 벌로 산다 — 예전에는 한 배열에서 `SEQUENCE` 를 되짚어
어느 쪽 밴인지 역산했고 그 계산이 틀려 있었다.

### 화면 대응 (세이프 에어리어)
판째 `ScreenMetrics.indent_to_safe_top()` 로 내리고 `backfill_top()` 으로 위쪽
띠를 메운다. 세로 좌표는 전부 `ScreenMetrics.safe_h()` 에서 계산해 나오므로
(`_layout()`) 상수를 하나씩 기기 대응으로 고칠 자리가 없다. 검증은 창으로 띄워
`ESM_SAFE_AREA` 로 인셋을 흉내 낸다 — 헤드리스로는 못 한다
(`docs/mobile_safe_area.md`).

### Mechs have a role, but assignment is still free
`mechs.role` 은 이 화면의 필터와 데이터 검증에 쓰인다. 어느 슬롯에 어느 기체를
앉힐지는 여전히 ASSIGN 이 자유롭게 정한다.

---

## 격자 스크롤 — 메크 칸이 `MOUSE_FILTER_PASS` 인 이유

`_build_mech_cell` 의 `Button` 은 필터를 **PASS 로 내려 둔다**(기본값 STOP).
STOP 이면 폰에서 메크 격자가 전혀 안 굴러간다 — 드래그 스크롤은 터치에서
에뮬레이트된 마우스 press 가 `ScrollContainer` 까지 올라와야 시작되는데
STOP 이 그걸 끊기 때문이고, 칸이 격자를 빈틈없이 덮으므로 예외 자리가 없다.
`_grid_content` 가 `IGNORE` 인 것도 같은 사슬의 일부다(몸통이 STOP 이면 칸
사이 빈 자리를 눌러도 거기서 끊긴다). 데스크톱은 휠이 STOP 을 뚫어서 이
결함이 안 보인다. 규칙과 검증법은 **`docs/mobile_safe_area.md` §5**.
