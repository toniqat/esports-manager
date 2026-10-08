# data/l10n/ — 현지화 원본과 생성물

사양: **`docs/localization_design.md`** (확정 사항 §0.5 우선). 도구: `addons/l10n_tool/README.md`.

| 경로 | 내용 | 편집 |
|---|---|---|
| `config.json` | 로케일 · key 접두사 · 토큰 · 스캔 · `data_columns`(데이터 CSV 컬럼 ↔ 도메인 · alias 규칙) | 사람 · LLM |
| `src/<domain>.csv` | 도메인별 문자열 — 한 행 = key · alias · status · context · max_len · note · ko · `<loc>` · `<loc>_status` · `<loc>_hash` | **편집 대상.** 에디터 메인 화면 **`L10n` 탭(표 편집기)** 이 가장 쉽다. Excel 은 "CSV UTF-8" 로 저장. 새 행은 끝에, 정렬 · 재포맷 금지 |
| `src/glossary.csv` | 용어집 (§4.5) — optional `match_<loc>` column = regex that finds the term in that locale (excludes word-internal hits, e.g. `(?<![가-힣])턴`) | 사람 · LLM |
| `generated/` | `strings_<loc>.csv` · `L.gd` · `refs.json`(커밋) · `index.json` · `report.md` · `extract_report.md` · `extract_code*.json`(gitignore) | **직접 수정 금지** — `build dev` 로 다시 만든다 |

## 공유 도메인

`ui.csv`(어디서나 같은 UI 낱말 · 공용 오류 문장) · `term.csv`(게임 어휘 — 포지션 · 페이즈 · 스탯 · 요일 · 등급 …) ·
`keyword.csv` 의 `keyword.icon.*`(설명문 아이콘 낱말 매칭 표)는 기반 담당이 소유한다. 목록과 헬퍼는 설계서 §0.7.

## 규칙 요약

- 공유 낱말은 문장 안에 `{tx_KEY}` 로 참조한다(build 가 같은 로케일 텍스트로 펼침, 언어마다 선택). 합치기 · 참조는 주체와 뜻이 같을 때만(설계서 D18 · D19).
- 바뀔 수 있는 수치는 문장에 적지 않는다: 카드 `{effect 이름}`, 튜닝 값 `{const_key 소문자}`(`_pct` · `_abs` · `_signed`), 데이터 값은 호출부 params(D20). 표시 텍스트에 em dash 금지(D21).
- 원본 셀 일괄 수정은 CLI `edit <json>`, 번역 초안 일괄은 `set_tr`.
- key 는 지어내지 않는다 — `new_key` · `new_keys`(일괄) / `extract` 로만 발급.
- LLM 번역은 `draft` 까지. `approve` 는 오너 지시 시에만.
- 작업 후 `build dev` → `generated/report.md` Error 0 확인.
- 생성물 머지 충돌은 원본을 머지한 뒤 `build` 로 다시 만든다.
