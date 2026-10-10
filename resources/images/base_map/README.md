# Team base map art (`resources/images/base_map/`)

Ten isometric area maps used by the week screen's team base map
(`features/season/week/base_map/`, one `UI_Comp_BaseMap_<Name>.tscn` per file). File name = `<NN>_<name>.png`;
the numbering is `BaseMap.SCENES` order, `map_id` = NN − 2 (00 / 01, the indoor Schale maps, were deleted 2026-10).

**Prototype placeholders only. These pictures are Blue Archive (Nexon) area maps, taken from the namu.wiki page
"블루 아카이브/스케쥴" (converted from webp to png). They must be replaced with our own art before any public
release (store build, public test, trailer, screenshots).**

| File | Source area |
|---|---|
| `02_gehenna.png` | 게헨나 중앙구 |
| `03_abydos.png` | 아비도스 본관 |
| `04_millennium.png` | 밀레니엄 학습관 |
| `05_trinity.png` | 트리니티 광장 구역 |
| `06_red_winter.png` | 붉은겨울 연방학원 |
| `07_hyakkiyako.png` | 백귀야행 중심부 |
| `08_du_shiratori.png` | D.U. 시라토리구 |
| `09_shanhaijing.png` | 산해경 중앙특구 |
| `10_haruhabara.png` | 하루하바라 전자상가 |
| `11_wild_hunt.png` | 와일드헌트 종합예술지구 |

All share one aspect ratio (about 1.58 : 1, most are 1024 × 650 or 1000 × 634, `07` is smaller); the map scenes
show them in `BaseMap.DESIGN_SIZE` with keep-aspect, so a replacement should keep that ratio (or the spot
markers need moving).
