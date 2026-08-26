# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-27 (6차 세션 종료) · Phase 9 마감 트랙 진행 중

## 1. 현재 상태 한 줄 요약

Phase 0~9 기능은 사실상 갖춰졌고, 6차 세션은 **"만들어 놓고 연결되지 않은 것"을 찾아 잇는 일**을 했다.
새 관문 **`tools/audit/world_audit.tscn`(조립 검증)** 을 만들어 기존 4종 관문이 못 보던 층을 덮었고,
그 도구와 실측으로 **층별 난이도 부재 · 상자 전량 빈손 · 상점 미연결 · 무기/방어구/상태이상 사문화**를
찾아 전부 살렸다. 상세는 §3.5.

**다음은 결정이 필요한 것들**(폰트 선택 · 맵 고립 구역 판정 · quest 3종 컷신)과
**P3 출하 트랙**(export preset → l10n → CI). 마감 항목의 권위 목록은
[docs/03_plan/05_polish_roadmap.md](03_plan/05_polish_roadmap.md).

## 2. 다음 세션 첫 명령

```powershell
검증실행.bat                 # 관문 14단계 (마지막 = world_audit)
```

관문이 녹색이면 아래 순서로 본다:

| 문서 | 용도 |
|---|---|
| `docs/03_plan/05_polish_roadmap.md` | **마감 항목 권위 목록** — 무엇이 남았는지 |
| `docs/03_plan/06_parallel_briefs.md` | 다른 세션에 위탁할 때의 경계·전달 문서 |
| `tools/audit/known_issues.json` | 감사 보류 5건(원본 데이터 기인, 사유 기재) |
| `assets/gen/prompts/LLM_REQUEST_GUIDE.md` | 그래픽 LLM 사이클 |

## 3.5 6차 세션 (2026-08-26~27) — 조립 검증 층 신설 + 사문화 데이터 복구

### 신설: 월드 감사(`tools/audit/world_audit.tscn`)

기존 4종 관문이 **전부 녹색인데도** 조립 결함이 8건 살아 있었다. 각 관문이 보는 층이 달랐기 때문이다:

| 관문 | 보는 것 |
|---|---|
| `validate.gd` | 데이터 참조 — 파일·키·id가 존재하는가 |
| `self_check.gd` | 시스템 통합 — 로직 규약 |
| `smoke_*.tscn` | 시나리오 한 줄기 |
| `check_scripts.gd` | 파싱 |
| **`world_audit`(신설)** | **조립 결과 — 화면에 뭐가 서 있고 갈 수 있는가** |

전 층의 `field.tscn`을 실제로 세워 40틱 굴리며 검사한다: 렌더 정합 · 아틀라스 색0 키잉 ·
시트 오배정 · 포즈 커버리지 · 액터 겹침/벽 박힘 · 2×2 몸 도달성(문 통과 ±3 포함) ·
고립 구역 · 이동 규칙 · 전투/필드 UI 화면 이탈. 보류 목록(`known_issues.json`)으로
원본 데이터 기인 항목은 사유와 함께 [KNOWN]으로 강등해 관문이 상시 빨간불이 되지 않게 했다.

### 이 세션이 고친 결함 (전부 실측 근거)

**렌더·이동**
- 오브젝트 173종 **전량 미렌더** — TileSet에 지면 아틀라스만 싣고 `set_cell`은 소스 1을 지목. "투명벽"의 정체
- 오브젝트 아틀라스가 색0 키잉 이전 구판(불투명 순검정 44.6%) — 물건마다 검은 사각 배경
- 플레이어 보행 프레임 번쩍임 — 걸음 끝마다 `idle_down`으로 떨어졌다 되돌아옴. 방향별 폴백 + 걸음 박자 동기로 해소
- `front_cells()`가 좌/하만 한 칸 멀어(x−2·y+3) **왼쪽·아래 상자와 NPC를 조사할 수 없었다**
- **f4 전체 이동 불가** — `find_spawn`이 셀 하나만 검사해 2×2 몸이 벽에 반쯤 박힌 채 스폰
- 층 전환 시 이전 층 NPC·몬스터·트리거가 그대로 잔류
- 전 NPC가 주인공 얼굴 — `_ready()`가 `setup()`보다 먼저 돌아 `npc_id`가 빈 문자열일 때 시트 조회

**몬스터**
- 통행 판정이 점유 사전만 봐서 **벽·맵 밖을 자유 통과**, 행동 주기 게이트가 없어 **초당 60칸**
- 종 id가 `{ "id": "dworm", ... }` 통문자열(floors의 객체를 `str()`) → 시트·정의 전부 폴백
- 완성돼 있던 `SpeciesBrain`(dash/burrow/zigzag/ambusher/phaser)이 **한 번도 연결되지 않음**
- BURROW가 어그로 반경 없이 맵 반대편에서 순간이동해 회피 불가 전투를 걸었다
- **층별 난이도 부재** — `Database`가 전 종에 `ap15/hp[20,40]` 하드코딩. F5가 F0과 같은 강도

**아이템·전투**
- 59종 중 실제 작동 9종뿐. 무기 19종은 **장착 시스템 부재**, `cures`/`ap_buff`/`money_value`는 사용 경로 없음
- 상자 184덩어리가 **전부 빈손**. 매핑표(`legacy_ref` 150~184)는 있는데 게임이 안 썼고 11개가 개명 뒤 깨짐.
  MEET(198)·EMPTY(199) 109덩어리는 **조사 대상에서조차 제외**
- `ShopUI`가 어디서도 생성되지 않고 `shop` op은 데이터에만 존재 — 상점 도달 불가
- 상태이상 3종 중 2종 무효(`burn`·디버그 실드) — 효과 id를 kind로 그대로 넘겨 매칭 실패
- 난이도 프리셋 5배율 정의는 있고 **호출부 0건**
- `grant_skill` op 부재 + `player_combatant.skills` 죽은 하드코딩(이름도 틀림)
- 퀘스트 아이템 4종이 **중복 정의**(`ITEM_CURE_*` vs 이름 없는 `reagent_*`), 컷신은 스텁 쪽을 지급

### 이 세션이 새로 넣은 것

| 항목 | 내용 |
|---|---|
| 층별 난이도 | `monsters.json floor_stats` — 원작 `init_enemy()` 난수 테이블 이관. 종=정체성, 층=강도 |
| 방어구 9종 | 공대 소품 톤(실습 가운 DP8 → 실험용 외골격 DP110). `dp/4` 경감, 적 DP는 원작대로 미반영 |
| 전투 배경 | `BattleBackdrop` — 층별 색조 6종 + 접지 그림자. **원작에 전투 배경은 없었다**(M-R/I-V는 적 등장 일러스트, 포맷 명세 오독 정정) |
| 전투 결과 요약 | `BattleResultPanel` — EXP·소지금·레벨업 구간 HP/AP 합산 |
| 상태이상 표시 | `StatusChips` — 지속/방어/마비/공격/저항 + 잔여 턴 |
| 인카운터 조절(Q6) | 추적 경고 표식 + 몬스터 밀도 4단 + 진입 1.1초 유예 — **"현대 편의"로 결정됨** |
| 빠른 이동(Q5) | 계단 위 SPACE, 방문 층만(해금제), 착지 보정. 층 이름은 `data/maps/floors.json` |
| 아이템 사용 경로 | `ItemEffects` 단일 창구 — 필드/전투/획득 통합, `buff_attack`·`buff_status_resist` 신설 |
| 스킬 획득 기구 | `GameState.owned_skills` + `grant_skill` op + 메뉴 게이팅. `starting` 없으면 전부 개방(동작 불변) |
| 화면 설정(Q10) | 창모드·vsync + 난이도 선택 |
| UI 폰트 배선 | `src/autoload/ui_theme.gd` 3단 폴백 — `assets/fonts/ui_pixel.ttf`만 넣으면 적용 |
| HUD 재설계 | `hud_theme`/`hud_gauge`/`hud_slot_bar`/`interact_prompt` 분리, 미니맵 평면도화 |

### AGENTS.md 콘텐츠 하드코딩 위반 정리

- 상점 품목·가격 → `items.json price` + `data/shops.json`
- 상태이상 수치 → `skills.json status_effect_defs`
- 적 스탯 → `monsters.json floor_stats`

### 관문에 추가된 프루브

`validate.gd`: 상태이상 kind 유효성 · `legacy_ref` 대상 실재 · 아이템 획득 경로 · `grant_skill`/`starting` 유효성
`world_audit`: UI 화면 이탈(전투 3메뉴 + 필드 3패널) · 미매핑 상자 · 고립 구역 · 이동 규칙

## 3.9 다음 세션 연계 (6차 세션 종료 시점)

### 바로 착수 가능 (코드만, 결정 불요)

| 순위 | 항목 | 근거 |
|---|---|---|
| 1 | **`export_presets.cfg` 생성** | 빌드 자체가 불가능. 콘텐츠가 전량 `data/**.json`이라 프리셋의 파일 포함 규칙이 함정 — Windows 프리셋 하나로 빈 빌드 부팅 확인만 해 둬도 나중 하루를 아낀다 |
| 2 | **l10n 골격** | `tr()`·`TranslationServer` 사용 0건. 대사는 이미 `@t/@c` 키 체계라 UI 문자열만 모으면 된다 |
| 3 | f0 몬스터 정지 | 감사 WARN — sparker 1종만 스폰 + teleport 패턴이라 40틱 무이동 |
| 4 | 근거 없는 차단 셀 320~540/층 | 감사 WARN — 대부분 맵 하단 경계(y47~48). 판정 규칙 조정 여지 |

### 결정이 선행되어야 하는 것

| 항목 | 무엇을 정해야 하나 |
|---|---|
| **폰트** (P0-03) | 둥근모꼴 / Galmuri / NeoDunggeunmo 중 택1 + 라이선스 확인. `assets/fonts/ui_pixel.ttf`로 넣으면 코드 변경 없이 적용된다(배선 완료). 현재는 시스템 폴백(굴림체)이라 **배포 불가** |
| **맵 고립 구역** | f1~f4 상단 띠 ~1,428앵커가 봉인. 원작 그대로인가, `map_convert.py` 산물인가 |
| **quest 3종 컷신** | `ITEM_LIGHTER`(폭탄 점화) · `ITEM_DIPLOMA`(대학원생 이벤트) · `ITEM_APPROVAL`(권교수 심부름) — 지급 컷신이 없다. `validate.gd`가 상시 보고한다. **라이터를 `f1_blast` craft 재료로 넣으려면 지급처가 먼저** — 없이 넣으면 진행이 막힌다 |
| **성장 트리** | `skills.json`에 `starting: [...]`과 컷신 `grant_skill` 스텝을 넣으면 켜진다. 지금은 6종 전부 개방(동작 불변) |
| **`obj_id=173`** (f3 89셀·f4 2셀) | 원본 `OBJ.SPR` 보유 PC에서만 재추출 확인 가능 |

### 에셋 대기

- NPC 4종 시트 부재: `dev1` `dev2` `lab_student` `afterschool_student` (감사가 상시 WARN)
- 몬스터 4종(`c_bug`·`flying_thesis`·`null_pointer`·`rogue_vending`)은 6차 세션 중 시트가 들어왔다
- 4방향 idle 프레임 — 전 액터. 지금은 같은 방향 `walk` 첫 프레임으로 대체 중(정상 폴백)
- 포트레이트 16종 · 키아트 6종 패키지 준비 완료

### 병렬 작업 주의

6차 세션은 **한 작업 트리에서 세 레인이 동시에** 돌았다(엔진·오디오·스프라이트 생성).
충돌이 없었던 건 레인이 안 겹쳤기 때문이지 설계 덕이 아니다.
코드 레인을 둘 이상 돌릴 거면 `git worktree` 분리를 권한다.
위탁 시 경계·전달 문서는 [03_plan/06_parallel_briefs.md](03_plan/06_parallel_briefs.md).

### 이 세션의 교훈 (재발 방지)

**"데이터에 정의됐는데 코드가 안 쓰는 것"이 이 프로젝트의 지배적 결함 유형이다.**
난이도 프리셋·`legacy_ref`·`SpeciesBrain`·무기 `element`·상태이상 정의·`shop` op·
`grant_skill`·DP — 전부 만들어 두고 연결하지 않은 것들이었고, 관문 넷이 전부 녹색이었다.
새 기능을 얹기 전에 **기존 데이터의 참조 여부부터 확인**하는 편이 효율이 높다.
`validate.gd`에 넣은 프루브 4종이 이 유형을 상시 감시한다.

**`gdformat`은 딕셔너리 리터럴 안의 다중행 람다에서 파일을 망가뜨린다.**
`tools/audit/world_audit.gd`가 그 구조를 쓰다가 재포맷이 멱등하지 않게 되고,
헤더 독스트링이 본문 딕셔너리 한가운데로 32번 복제되며 180줄이 714줄이 됐다.
아직 커밋 전이라 `git checkout`으로도 못 살렸다 — 전면 재작성으로 복구했고,
지금은 문자열 목록 + `match`로 편 구조다(파일 상단에 경고 주석을 박아 뒀다).
**새 파일은 첫 커밋 전에 `gdformat --check`를 한 번 돌려 보고 진행할 것.**

### 6차 세션 커밋 (8/26~8/27)

| 커밋 | 레인 | 내용 |
|---|---|---|
| `01035f2` | 엔진 | 조립 검증 관문(world_audit) 신설 + 필드/몬스터 결함 복구 + 죽은 데이터 배선 |
| `7daf758` | 오디오 | BGM 6곡 재작곡 + SFX 12종 재합성 |
| `46771e8` | 스프라이트 | 신규 몬스터 4종 시트 + 몬스터 애니 스펙 전면 확장 |
| `39b02f4` | LLM 파이프라인 | 의뢰 패키지 공통화 + 그래픽 에이전트 프롬프트 + 몬스터 시트 검증기 |
| (본 커밋) | 문서 | 마감 로드맵 · 병렬 브리프 · 본 연계 기록 |

**세션 종료 시점 관문 상태** — 스모크 11종 통과 · `validate` 0 errors(획득 경로 없는
아이템 3종 경고는 위 「결정이 선행되어야 하는 것」 참조) · `check_scripts` broken=0 ·
`world_audit` FAIL 0 / WARN 21 · `gdformat --check` 94 files unchanged.

---

> 아래부터는 **이전 세션 이력**이다. 현재 작업 지시는 위 §3.9와
> [03_plan/05_polish_roadmap.md](03_plan/05_polish_roadmap.md)를 본다.

## 3. 진행 중: 스프라이트 LLM 리터치/생성 (유저 주도)

**확정 워크플로우**: 추출(extract_sprites.py, 완료) → LLM 의뢰(프롬프트 패키지
gen/prompts/ 참조) → 납품을 assets/raw/llm/10_submitted/ 저장 → **재가공 스크립트**
(마젠타 키잉·스펙 그리드 컷팅·검증 → 20_processed/) → 유저 리뷰 채택 → 패킹.

**다음 세션 할 일 (순서대로)**:
1. ~~**process_llm_sheet.py 구현**~~ ✅ **완료(8/25 3차 세션)** — 마젠타 키잉
   (sprite_retouch.key_magenta 재사용) + 스펙 그리드 컷팅 + 빈 셀 제외 프레임
   검출 + 표준 규격 검증(_standard.md 임계값) → `20_processed/<캐릭터>/`에
   프레임 PNG + processed_sheet.png + report.json 기록.
   사용: `python tools/convert/process_llm_sheet.py <납품.png> [--spec 스펙.json]`
   (스펙 미지정 시 assets/spec/sprites/<캐릭터>.json 자동 탐색).
   합성 시트 3종(정상/프레임누락/그리드불일치)으로 통과·반려 경로 검증 완료.
   첫 실제 납품을 보고 임계값 미세조정 필요할 수 있음.
2. **LLM 재요청** — 1차 납품은 반려됨(마젠타 배경, 그리드 5행→7행, 재창작).
   교훈: 원작은 24×24 도트였다(셀 64는 패딩 컨테이너) + 표준 규격은
   `_standard.md`(셀 128×128) — 프롬프트에 명시 후 재요청.
   참조자료: `assets/raw/llm/00_reference/` (8/25 3차 세션에 재생성됨 —
   62그룹, gitignored 임시区).
3. 납품 수령 → `10_submitted/<캐릭터>_v<n>.png` 저장 → process_llm_sheet.py
   실행 → 리포트 유저 보고 → 뷰어 검수 → 채택 시 패킹.
4. 스타일 방향: **표준 규격 확정 = assets/spec/sprites/_standard.md**
   (셀 128×128, 세로형 0.6:1, SD 머리:몸 1:1.2, 프레임 가변 최소2/walk 4 권장,
   idle 4방향 2프레임). 유저가 생성 시트 비율 채택 의사 표시함.

### 스프라이트/화면 관련 확정 사항 (8/25 2차 세션 추가)

- **아트 모드 시스템**: SettingsManager.art_mode(LEGACY/REMAKE) + SpriteSets 리졸버.
  컨벤션 `assets/sprites/<id>_original.*`(레거시) / `<id>_remake.*`(신규), 부재 세트 자동
  폴백 — 신규 시트 미착용 상태에서도 게임 동작. 부팅 화면에서 ←/→ 선택(Enter/Z 시작).
- **레거시 시트 표준**: 원작 24×24 도트를 4배 nearest 베이크(96px) → 표준 셀 128 배치,
  scale ⅔ 메타로 실효 64px = 타일 2.0배(원작 비율). 캐릭터가 바닥 타일보다
  작던 역전 해소. 재생성: `tools/dev/make_player_original_sheet.py`.
- **발 앵커 공식**: `offset.y = TILE_PX/scale − cell_h/2` (SpriteSets.foot_offset).
  scale≠1 시트에서 발 침하 방지 — 리메이크 시트(scale≠1) 투입 시에도 면역.
- **원작 SPR 색0 = 투명**: parse_spr(spr_extract.py)가 팔레트 전색을 불투명으로
  방출해 도트에 검은 배경이 붙던 것 수정(원작 blit 색0 스킵 재현). 불투명 56.2%→33.4%.
- **뷰포트 960×540**: 타일 30×16.9 가시(원작 26.7×16.7과 체감 동일 — 캐릭터
  화면높이 11.9% ≈ 원작 12%). 전투 좌표 보정: 메뉴(800,380)·적열(600+i*100,180)·
  회피 아레나 Rect2(48,48,384,264)·미니게임 패널 중앙.
- **전투 렌더 픽스**: BattleUI 배경 ColorRect가 layer 20에서 월드 스프라이트를
  덮던 문제(하위 CanvasLayer -1로 분리) · 적 텍스처 폴백(스테일 .import 대응) ·
  적 이름에 species 딕셔너리 원문 노출(id만 추출).

### 스프라이트 관련 확정 사항 (이번 세션)

- **셀 128×128 / 캐릭터 세로형(~0.6:1, 실높이 ~110px) 채택** — 스펙 갱신 완료
  (player_sidol.json: cell 128×128, scale 0.75, idle 4방향, 프레임 가변 최소 2)
- **런타임 수용 코드 완비**: player_entity/battle_presenter 가 cell_w/cell_h(비정형)
  + scale 메타 + 방향별 idle(폴백 idle_down) 지원. 필드 스모크 PASS.
- **마젠타 키잉 허용**: LLM이 투명 처리 못 하면 #FF00FF 단색 배경으로 납품 받고
  파이프라인이 누끼(sprite_retouch.key_magenta). 단 혼색/AA 금지를 프롬프트에 명시.
- **palette_master.json 함정**(재발 방지): DEFAULT.PAL 기본 VGA DAC(raw768, 6비트) —
  첫 16색=EGA색, 8비트 스케일 없이 쓰면 검정화. 리터치는 **원본 자체 팔레트** 스냅이 정답.
- **원작 검정=투명 문제**: 원작 엔진이 색0 스킵이라 스프라이트 내부 검정이 배경과
  연결되면 뚫림. heal_pinholes(밀폐 복원+핀홀 봉합) 넣었으나 불완전 —
  원본 코드 blit 방식 확인이 근본 해법(HANDOFF 구판 §3 기록 참조).

### 기타 미해결 (우선순위 낮음)

| ID | 내용 |
|---|---|
| B1 | ~~빈 폴더 껍데기 삭제~~ ✅ 해소(8/25 확인 — 이미 부재) |
| B2 | gdformat/pre-commit 미설정 |
| B3 | ~~DialogueBox 스킵 visible_characters 음수 방지~~ ✅ 해소(8/25 재검증 — 현행 코드에서 음수 경로 없음) |
| — | battle_scene_controller ~305행(상한 초과 소폭) UI 분리는 완료, 추가 분리 여지 |

## 4. Phase 8 남은 작업

| 순서 | 작업 | 상태 |
|---|---|---|
| 0 | 스프라이트 LLM 워크플로우 첫 사이클 완주 (주인공) | **진행 중** |
| 1 | BGM/SFX 실제 파일 생성 -> assets/audio/ 배치 | 스펙 21종 준비 |
| 2 | 도트/타일/포트레이트 AI 배치 확산 (주인공 패턴 복제) | 대기 |
| 3 | 이벤트 데이터 채우기 — q_*_gate 플래그 흐름 | Phase 9 병행 |

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 |
|---|---|
| **공용 프레임워크** | src/battle, src/cutscene, src/map/trigger_system, src/ui(미니게임·DialogueBox·BattleUI), _shared 도구+schemas+**스프라이트 표준/LLM 워크플로우** |
| **게임 데이터** | data/**, assets/spec/**, gen/prompts/** |
| **게임 전용 로직** | 씬 조립, 성장, 보스 하이브리드 |

### Phase 9 착공 (8/25 3차 세션)

**완료 — Q1 세이브/설정 코어 루프 전체**:

- **SaveManager 실구현**: `user://save_auto.json` + `user://save_slot_1..3.json`
  (사람이 읽는 JSON, version 필드). 스냅샷 = 층/플레이어 좌표/스탯/인벤/플래그/
  상자 오버라이드. 오토세이브는 전투 승리 측에서 `request_autosave()` → 필드 진입 시
  `consume_autosave()`(좌표 확정 보장). 층 전환은 게이트에서 도착 좌표로 즉시 기록.
- **SettingsManager 실구현**: 볼륨 4버스(Master/BGM/SFX/Voice)·연출속도·아트모드 →
  `user://settings.json`. 변경 UI가 즉시 적용+저장, 기동 시 버스에 자동 반영.
- **UI 3종 신규**: `src/ui/save_slot_list.gd`(SAVE/LOAD 모드, 타이틀·일시정지 공용),
  `src/ui/settings_panel.gd`(공용), `src/ui/pause_menu.gd`(필드 Esc — 계속/세이브/
  로드/설정/타이틀). 트리 pause 중 입력 유지 위해 오디오 매니저 ALWAYS 모드.
- **타이틀 개편**(scenes/main.gd): 새 게임/계속하기/설정/종료 + 아트모드 ←→ 퀵선택 유지.
- **상자 오버라이드 완비**: 선언만 있던 GameState.chest_overrides가 실제 기록·적용·
  직렬화된다(field._apply_chest_overrides — 로드/재구축 공용).
- **tests/smoke_save.tscn 신규**: 저장→변형→복원 라운드트립 + 메타 + 오토 요청 흐름.

### Phase 9 잔여 완료 + 디버그 도구 (8/25 3차 세션 후반)

- **버그 수정(trigger_system.gd)**: `_consumed()`가 `done_flag`를 검사하지 않아
  F1 재방문마다 오프닝 컷신이 재발동됨(데이터 파일 주석의 규약과 불일치하는
  구현 누락 — Phase 7 잠복 버그). done_flag 스킵 구현으로 해소.
  이 버그가 smoke_dialogue 상시 실패·smoke_transitions 플레키의 근원이었다.
- **smoke_dialogue 재작성**: 프롤로그 플래그 프리셋(smoke_field 동일 패턴) +
  물리 프레임 동기 입력 홀드(`_press_until`) + 감시자 타이머. 정상 PASS.
- **부팅 인트로**(scenes/boot_intro): DOS 가짜 부팅 타이핑 → 타이틀 전환,
  아무 키 스킵. project.godot main_scene 변경.
- **조작 도움말**(src/ui/help_panel.gd): 타이틀·일시정지 양쪽에서 접근.
- **진행 기록 Q3**(data/quests_v2.json + src/ui/quest_log_panel.gd): 마스터
  시나리오 §3 구역명 준용한 14개 마일스톤 플래그 달성 뷰. 일시정지 메뉴에서.
- **접근성 Q9**(SettingsManager.TextSize): 본문 글자 크기 3단 — DialogueBox
  폰트/패널 높이에 스케일 반영, settings.json 영속.
- **디버그 패널**(src/ui/debug_panel.gd, F10 — 디버그 빌드 한정):
  층 이동(transitions.json 앵커 역산)·수치 변경·아이템 지급·전투 강제
  (species+bosses 데이터 구동)·플래그 토글·SelfCheck 실행.
- **SelfCheck 자가검증**(src/core/self_check.gd + tests/smoke_selfcheck.tscn):
  통합 지점 회귀 프루브 7종 — 전층 맵 로드/NPC 시퀀스 참조/트리거 참조/
  적 정의 커버리지/세이브 라운드트립/**done_flag 스킵 규약(8/25 버그 회귀 방지)**/
  인벤 불변식. 게이트로 승격 — 검증실행.bat에 편성.
- **검증 결과**: import·validate 0오류, 스모크 8종 + 부팅인트로/타이틀 헤드리스
  부팅 전부 exit 0.

**P9 잔여**: 시나리오 데이터 완충(퀘스트 상세 목표·대사 보강 — 시나리오 작업) ·
Steam/Itch 패키징·CI(외부 계정·익스포트 템플릿 필요 — 로컬 검증 불가로 보류).

### 기존 결함 종결 (8/25)

| ID | 내용 | 결론 |
|---|---|---|
| — | smoke_dialogue 실패 | ✅ 근원=done_flag 미검사 버그. 규약 구현+테스트 재작성으로 PASS |
| — | smoke_transitions 최초 1회 실패 | ✅ 동일 근원 추정 — 규약 구현 후 연속 PASS |

### 디버그 스윕 결과 (8/25 3차 세션 — 통합 스윕 프로그램 실행)

전층 텔레포트 실부팅(F0~F5)·전 적 ID 강제 전투(species 15종+보스)·수치 변경→전투
반영을 프로그램으로 스윕 → **fails=0**, 단 아래 발견:

- **[해소] 전투 적 텍스처 ERROR 스팸**: battle_presenter가 임포트 불가한
  originals_ref 원본 bmp를 매 전투 로드 시도(스테일 .import로 exists=true).
  플레이스홀더 전용 경로로 정리 — 리메이크 아트 확정 시 교체.
- **[완충] 착지 셀 보정**: find_spawn이 저장/착지 좌표가 막혔으면 최인접 통행 셀로
  나선 보정(f0처럼 데이터가 어긋나도 진입은 보장).
- **[해소·8/25 후반] f0 계단 착지 불일치**: 원인은 변환기가 아니라 **transitions.json
  데이터** — center 계단 guard가 F0를 포함했으나 원본 F0.MAP 대조 결과 지하는
  **동측(east) 계단만 연결**(center 앵커/착지가 F0에서 벽, east는 서립·착지 모두
  통행). center_up/down guard에서 F0 쌍 제외로 해소, SelfCheck 착지 프루브
  warn 소멸. 시나리오 비선형 경로(F1→2→3→F0→4→5)와 무모순 — 지하 물리 연결은
  F0↔F1(east)뿐.
- 참고: f2/f3에서 알 수 없는 오브젝트 메타 id=173 경고(맵 렌더 폴백 동작,
  표면상 무해 — 원작 OBJ id 테이블 미등록분).

### WP-1 완료 + WP-6 시나리오 LLM 브리프 (8/25 3차 세션)

**WP-1 (퀘스트 플래그 체인 정합화) 완료·커밋됨**:
- quests_v2.json v2 = 마스터 §4.2 메인 18 + 서브(후일담) 3, 총 21종(id·zone·name·
  description·reward·requires). SelfCheck `_check_quest_flags()`(선행 누락·순환)
  상시 가동.
- **플래그 캐노니컬 정렬**: 컷신 5종(set_flags/craft.flag)+트리거 5곳(done_flag)+
  스모크 5종이 구 이름(q_f4_battery 등)→quests_v2 신 이름(Q_F4_BATTERY 등)으로
  일원화. 잔존 구플래그 0건 확인.
- **스모크 헹 근원 수정**: 몬스터 접촉→change_scene으로 테스트 루트가 트리에서
  이탈 → get_tree() null 좀비(quit 불가). field/dialogue/transitions 3종에
  enemy_manager 즉시 해제 패치 + 모든 게이트 실행은 `--quit-after` 병행 권장.

**WP-6 착수 전 필독(시나리오 LLM 브리프)**:
1. 범위: (a) SelfCheck `_check_sequence_text_refs()` 추가 — sequences의 step.text가
   '@'로 시작하면 dialogue.json 키 존재 필수(FAIL 티어), run_all 배열 등록.
   (b) cafeteria_girl_shop의 `@c001` 단참조 수정 — @c001 신설 한 줄(D1 톤 준수)
   또는 기존 키 재지정. 프루브 통과가 규준.
2. **미사용 @c13개(@c317~@c328) 삭제 금지** — WP-3 S3-2 재료 피크드 대사 예약분.
3. **플래그 규칙(WP-1 확정)**: set_flags/craft.flag/done_flag/requires_flag는
   quests_v2.json 21종 id만 사용. 목록 밖 내부 게이트 마커(q_f2_hp_gate,
   q_f3_quiz_gate, q_f4_battery_gate, q_f5_boss_gate, q_f5_ai_battle_won)는
   유지 허용. 새 플래그는 quests_v2에 먼저 추가.
4. 검증: `--quit-after` 포함 실행 필수(아니면 좀비 프로세스 위험). 예:
   `%GODOT% --headless --path . --quit-after 3600 res://tests/smoke_selfcheck.tscn`
5. 커밋: 자기 경로만 스테이징(data/** 중 자기 파일, self_check.gd 프루브부).
   originals/** 접근 금지, 기존 테스트 삭제 금지.

### WP-2 시나리오 LLM 브리프 (8/25 3차 세션 — WP-6 커밋 9ee427d 이후 유효)

1. 스키마: npcs_f<N>.json = {"schema_version":1, "_comment", "floor":N,
   "npcs":[{id,name,pos:[x,y],sequence_id,tint:[r,g,b]}]} — pos는 앵커 셀(1셀 점유),
   통행 불가 시 로더가 인접 보정하되 정확한 셀 지정 권장. 파일이 없는 층(F0/F2~F5)은
   신규 생성.
2. 배치 과제: (a) 미배치 시퀀스 4종 착지 — npc_girl_rescue→F2(S2-2 실습실),
   guard_idle/nothing_man→F0 또는 F2, cafeteria_girl_shop→F0 식당(@c001 화자).
   (b) 구역 상주 NPC 신설 — F2 개발자 2명·F3 랩실 생도·F4 잔류생·지하 사서
   (마스터 §2.1 프로필 준수, D1 톤).
3. @c 번호 규약(신규): F0=@c002~, F2=@c201~. 기존 구역 연번 유지
   (F1=@c1xx, F3=@c3xx, F4=@c4xx, F5=@c5xx, 엔딩=@c6xx). 신규 텍스트는 전부 새 @c.
4. 경계: 플래그 세팅(Q_F2_FIGHTER 등)은 WP-3 트리거/컷신에서 처리 — WP-2는
   배치+시퀀스+@c만. sequences의 step.text는 '@'키(dialogue.json 등록 필수,
   WP-6 프루브가 FAIL로 걸름) 또는 직접 문자열.
5. 검증: validate.gd + smoke_selfcheck(NPC 프루브·참조 무결성 프루브) PASS 필수.
   실행 시 --quit-after 3600 병행.
6. 커밋: 자기 파일만(npcs_f*.json, dialogue.json/@c, dialogue_sequences.json).

### WP-3 시나리오 LLM 브리프 (8/25 — WP-2 커밋 227edf5 이후 유효)

목표: 마스터 §3 씬을 zone/interact 트리거 + 소형 컷신(set_flags/grant_item/craft/
start_battle/dialogue 조합)으로 데이터화. **작성 가능 도구는 기존 CutscenePlayer op
범위 내**(fade/sfx/dialogue/set_flags/start_battle/grant_item/craft/change_scene/
shake/wait).

체크리스트(각 항목 = 트리거 행 1개 + 컷신 1개):
1. S1-3 교무실(F1 zone): 컷신 dialogue(@c 신설 F1=@c107~) + set_flags Q_F1_SOPO
   → 괴물전투는 신규 몬스터 부재로 기존 species 재활용(e계열) or 무전투 연출 중 선택.
2. 창고(F1 zone): set_flags Q_F1_GAS + @c 신설.
3. 폭파 조합(F1 interact, 교무실 인근): craft op — requires는 items.json 실제 id
   확인 후 사용(부싯돌/휘발유/라이터 계열), flag=Q_F1_BLAST.
4. S2-3 포스터(F2 interact): set_flags Q_F2_POSTER + @c 신설(F2=@c204~).
5. S3-2 재료 발굴(F3 zone ×2): grant_item reagent_drag/reagent_allin 각 1 +
   set_flags Q_F3_DRAG/Q_F3_ALLIN + D6 재활용 대사 @c317~@c328 소비.
   (팔린은 quiz_paline이 이미 Q_F3_PALIN 세팅 — 중복 금지)
6. B-1/B-2 지하(F0 zone+interact): 서고 입장 연출, 발굴 grant_item(공디스켓/C서적 —
   items.json id 확인) + set_flags Q_F0_DISK.
7. S4-2 희생(F4 interact): 레버 연출 @c405~ + set_flags Q_F4_SACRIFICE.

규칙·주의:
- 트리거 스키마: {"id","type":"zone|interact","cells":[[x,y]...],"once":true,
  "done_flag","action":{"cutscene":"..."}} — done_flag는 quests_v2 id만.
  requires_flag는 기존 게이트 마커만(q_f*_gate 등).
- pos/cells는 통행 셀로 직접 지정(검증 스크립트가 벽 위 배치를 FAIL 처리한다 —
  WP-2에서 3건 적발했음).
- 새 컷신 파일명: data/cutscenes/<이벤트_id>.json, id 필드 일치.
- 검증: validate + smoke_selfcheck + smoke_field/dialogue PASS(--quit-after 병행).

**엔진 협업 백로그(시나리오 LLM 작업 불가 — 메인 개발 영역)**:
- F2→F3 계단 requires_flag: 현 구조는 층 기반 guard라 방향별 잠금 불가 —
  엔진 확장 또는 계단 앞 zone 안내 컷신으로 우회(본 WP에선 미구현 허용).
- 종별 첫 격파 플래그(Q_F1_START의 DWORM 의미론) — pending_encounter에
  on_win_flag 전달 확장 필요. 현재는 오프닝 완료 시점으로 근사됨(HANDOFF 기록).
- Q_F5_BOSS_CURE(모교수 제압·투약) 전용 연출/보스 미창작 — 스코프 협의 필요.

### WP-5 시나리오 LLM 브리프 (8/25 — 선택지 op 계약 확정본)

역할 분담: 시나리오 LLM = 원문 이식+선택지 데이터 / 메인 개발 = CutscenePlayer
`choice` op 스파이크(진행 중). **아래 계약을 벗어난 형태로 쓰지 말 것.**

1. **@c 원문 등록(dialogue.json)** — 마스터 §3 원문을 그대로(불변):
   - `@c516`~`@c525`: 씬 5-3 대립 대본 10줄(순서 보존)
   - `@c526`~`@c530`: 씬 5-4 피니시 대사 5줄
   - `@c606`~`@c610`: E-1 후일담 잔여 5줄(수위/완종/삼룡/부싯돌/해피엔딩)
   - 선택지 옵션 변주 1줄: `@c531`(B안 답변 — "불씨가 남아 있으니까." 톤)
2. **boss_sys_builder.json 확장** — 현재 [sfx,shake,dialogue,start_battle]에서
   dialogue와 start_battle 사이에 삽입:
   - `dialogue` op: @c516~@c519 (포맷 위협 대립 전반)
   - `choice` op(계약): `{"op":"choice","args":{"options":[
       {"text":"@c520","steps":[{"op":"dialogue","steps":[
         {"speaker":"부싯돌","text":"@c520"}]}]},
       {"text":"@c531","steps":[{"op":"dialogue","steps":[
         {"speaker":"부싯돌","text":"@c531"}]}]}]}}`
     — 두 옵션 모두 수렴(단일 엔딩 유지). 플래그 부여 없음(연출용 선택).
   - `dialogue` op: @c521~@c525 (SYS_BUILDER 반응 + 포맷 개시)
   - `start_battle` 유지.
3. **epilogue.json 앞단 확장** — 5-4 피니시(@c526~@c530 dialogue)를 기존
   @c601 대화 앞에 삽입(승리 직후 퇴장 대사 → E-1 → E-2 흐름).
   E-1 잔여 @c606~@c610도 dialogue 스텝에 추가.
4. **E-2 CRT 메타 엔딩 텍스트**: SYSTEM REPORT 블록은 엔진 연출(메인 개발)이
   렌더링하므로 데이터화 불요 — 수정 금지.
5. 검증: validate + smoke_selfcheck + **tools/viewer.html 정합성 탭 FAIL 0 확인**
   (뷰어실행.bat). 커밋은 자기 파일만(dialogue.json, cutscenes 2종).

### WP-7 시나리오 LLM 브리프 — Q_F5_BOSS_CURE「30분의 침묵」 (8/25 4차 세션)

**권위**: 마스터 §[5층] 씬 5-1 (`@c501`~`@c506`) · **성격**: 원문 이식 + 연출
데이터화. 자유 창작은 @c 잔여 키 보강 대사에 한함.

**현황 갭(8/25 4차 세션 실측)**:
1. `dialogue.json`에 `@c501`~`@c506` 부재(`@c507`부터 존재) — 씬 5-1 대사 0%
2. 모교수 괴물 보스 정의 부재(`bosses`는 `sys_builder`만)
3. `triggers_f5.json`이 `q_f5_boss_gate` → SYS_BUILDER **직행** — 씬 5-1 공백
4. **`q_f5_boss_gate` 세터가 리포지토리 어디에도 없음(죽은 게이트)** — F5 보스
   이벤트 자체가 미발화. F4 희생 컷신이 단 1줄(`@c407`)로 끝나며 게이트를
   세팅하지 않음

**데이터 계약 (파일별)**:

| 파일 | 변경 |
|---|---|
| `data/dialogue.json` | `@c501`~`@c506` 신설 — 마스터 씬 5-1 대본 원문 이식. 마스터 표기 4줄 → 6키 분할은 화자·동작 전환 단위로 자유(D12). `@c505~506`은 모교수 각성 후 개그/메타 보강 대사(톤: 진지60/메타20/개그20) |
| `data/monsters.json` | `bosses.professor_monster` 신설 — 가이드: display_name "모교수 괴물", ap 20 / dp 6 / hp_range [90,120], exp [60,90] / money [300,480](sys_builder의 60%), dodge_phase 미채택(D14) |
| `data/cutscenes/f5_professor.json` | 신설 — shake+sfx 도입, dialogue(@c501~@c502), `start_battle{enemies:["professor_monster"], on_win_flag:"q_f5_prof_won"}` |
| `data/cutscenes/f5_cure.json` | 신설 — fade_in + `craft{requires:{antibiotic_x:1}, grant:{}, flag:"Q_F5_BOSS_CURE"}`(투약=소모, D13-A안) + dialogue(@c503~@c506) |
| `data/cutscenes/f4_sacrifice.json` | 말미에 `set_flags{args:{q_f5_boss_gate:true}}` 추가 — 죽은 게이트 부활(D15). 희생→해독제 확보→F5 진입 서사와 정합 |
| `data/maps/triggers_f5.json` | 재구성: ① `f5_professor_intro`(auto, requires q_f5_boss_gate, done q_f5_prof_intro_seen → f5_professor) ② `f5_cure_stage`(auto, requires q_f5_prof_won, done Q_F5_BOSS_CURE → f5_cure) ③ 기존 `f5_boss_intro`의 requires_flag를 `Q_F5_BOSS_CURE`로 교체 |

**결정 사항(D12~D15)**:
- **D12** @c 배분: 화자/동작 전환 단위 자유 분할 허용, 6키 전부 소진
- **D13** 해독제 소모: craft op 우회(A안, 코드 변경 없음). antibiotic_x 부족 시
  플래그 미세팅 = 진행 정지 — f5_cure 도입부에 "해독제가 필요하다" 안내 대사를
  넣어 재진입 시 판정 재시도하게 하고, 부족 사례는 디버그 패널 지급으로 복구(문서화)
- **D14** dodge_phase: 미채택 — 회피 페이즈는 최종보스(SYS_BUILDER) 고유 연출로 유지
- **D15** q_f5_boss_gate 세팅 위치: f4_sacrifice 컷신 종료 시점(F4 희생 = 5층 개방 서사)

**검증**: validate 0오류 + smoke_selfcheck(트리거 참조·플래그 체인 프루브가
신규 컷신/플래그 전수 커버) + 검증실행.bat 13단계. 커밋 소유권: dialogue.json,
monsters.json, cutscenes 2종 신설+f4_sacrifice, triggers_f4/f5.

### 다음 세션 연계 (8/25 3차 세션 종료 시점) — ✅ 전 소화됨(4차 세션)

**시나리오 데이터 완충 상태**: WP-1~6 전부 완료·검증·커밋. WP-5까지 포함해
마스터 §3 전 씬이 데이터로 존재한다. 시나리오 LLM 워크플로우 임무 완료 —
추가 위탁 작업 없음(다음은 엔진 백로그와 Phase 9 잔여).

**choice op 스파이크 완료**: CutscenePlayer `choice`(선택 강제·수렴형, ChoiceUI
내부 클래스) + tests/smoke_choice(입력 시뮬레이션 PASS). 검증실행.bat 10단계.
뷰어도 choice 스텝 표시 지원.

**남은 엔진 백로그 (우선순위순 — 다음 세션 착수 후보)**:

1. **F2→F3 계단 잠금(순수 데이터 해법 확정·미적용)**: center_up/east_up을
   guard 단위로 분할 — {guard 1-1, requires 없음}, {guard 2-2,
   requires_flag=Q_F2_POSTER}, {guard 3-4, 없음}. TransitionGate는 행 단위
   continue라 다중 행 무충돌. smoke_transitions에 Q_F2_POSTER 프리셋 추가 필요.
2. **Q_F1_START 의미론 정밀화**: 현재 오프닝 시청=세팅(근사). 정밀화 절차 —
   monsters.json dworm에 first_win_flag 필드 + field._trigger_encounter가
   get_enemy_def에서 전달 + f1_opening done_flag를 내부 마커 q_f1_opening_seen으로
   교체 + smoke_field/dialogue/selfcheck 프리셋 갱신.
3. **Q_F5_BOSS_CURE**: 모교수 괴물·제압·투약 연출 미창작 — 신규 보스 데이터 필요.
   스코프 협의 전까지 Q_F5_AI_BATTLE 직행 상태.
4. Q_HP_ALL "전원 대화" 판정 / Q_QUIZ_ALL 10문항 메타 — 현재 근사 세터 운영
   (hp_room_visit·quiz_paline). 정밀화는 신규 메커니즘 필요.
5. Godot features=4.3 → 4.7 승격 검토(로컬 4.7.2 — 에디터 저장 시 재변경 방지).
6. B2 gdformat/pre-commit(낮음).

**뷰어**: `뷰어실행.bat`(HTTP 모드 권장) 또는 tools/viewer.html 직접 열기
(파일 모드 — data 폴더 선택). 맵 오버레이·퀘스트 체인·시퀀스·컷신·정합성 대시보드.
choice 스텝 표시 지원.

**검증**: 검증실행.bat 10단계(마지막 = smoke_choice). 개별 실행 시 --quit-after
병행 필수.

### 5차 세션 (8/26) — 스프라이트 이관·LLM 패키지·전투 재미·심사 보드 (종료 시점)

**원작 리소스 이관 (정책 ①원작 있음→리마스터, LLM 불필요)**:
- **필드 몬스터 8종 + NPC 7종 시트** — 원본 GOODITEM.C `eye[i].mode=8*(i%8+1)` 근거로
  I.SPR 블록 1~8=몬스터 8종, EVENTER 블록 0~4=NPC 5인(여학생/유령 블록 2명 공유·tint 변별).
  `tools/convert/migrate_original_sheets.py` — 24px 도트 4배 nearest 베이크 → 표준 셀 128
  (player_original 동일 레시피). EnemyEntity가 SpriteSets 경유로 종별 시트 사용(폴백 유지),
  전투 프리젠터도 적을 종별 시트로 렌더(랜덤색 사각형 폐지, 미정착 종만 폴백).
- **아이템 아이콘 24종** — items.json `legacy_ref`(ATT 150+ 영구 매핑) = ITEM.SPR 35프레임 1:1,
  현행 존속 24종만 이관(`migrate_item_icons.py` → assets/icons/). ItemIcons.texture() 창구 신설,
  HUD 6슬롯·인벤토리가 실아이콘 우선(부재 시 색상+글리프 폴백).

**LLM 의뢰 패키지 생성기 3종 + 납품 검증기** (유저가 이미지 LLM에 투입할 준비 완료):
- 포트레이트 16종(`export_portrait_packages.py` — 컷신 전경/크롭 초상 자동 분기,
  원본 첨부+신원 유지 재창작 계약), 키아트 6종(`export_keyart_packages.py`),
  신규 몬스터 11종(`export_monster_packages.py` — placeholder계약 종, 그리드 계약 자동 산출).
  → assets/raw/llm/{portraits,keyart,monsters}/
- `validate_submission.py` — 포트레이트(768×256 3셀)/키아트(1920×1080) 자동 판정 게이트.
  합성 픽스처 7종 양방향 검증 + 부정 테스트로 게이트 실효 확인.
- 스펙 보강: monster_anim_specs.json에 null_pointer(사용 중 스펙 부재)·professor_monster 신설.

**전투 재미 확장 (현대 RPG 트렌드 반영)**:
- **약점→브레이크** — monsters.json species 섹션(14종 약점: 기계=electric·백로그 EMP 근거,
  종이/유기질=fire). 약점 히트 ×1.5+WEAK! 팝 → 2회 누적 BREAK(행동불가 1턴+받는 피해 ×1.5).
  기존 skill_hit weaknesses `[]` 하드코딩(README ✅와 불일치하던 미연결) 해소.
- **타이밍 버튼** — TimingRing(수축 링, sweet zone 후반 40% 입력) ×1.2, skills.json timing
  섹션 구동(공격·단일 스킬만).
- **전투 idle** — 플레이어·적 스프라이트 2프레임 순환(정지 1프레임 해소).
- **자동 검증** — smoke_battle 섹션 5: 약점 판정/배율·브레이크 발동/증폭·타이밍 보너스를
  시드 고정 결정론 검증. 부정 테스트(배율 제거 시 FAIL)로 게이트 실효 확인.

**검증**: validate 0오류 · 스모크 10종 전부 PASS · check_scripts broken=0.

**후반 작업 (동일 세션 계속 — 전부 커밋·푸시됨)**:
- **브레이크 게이지 시각화** — 적 스탯 UI에 ASCII 핍(`[#-]`, 약점 보유 종만), BREAK 시 적색.
- **보스 텔레그래프** — dodge_phase.telegraph 코드(screen_static_full_1s 등)를
  `BattlePresenter.play_telegraph`가 해석(지속시간 접미·flash/shake 토큰),
  "!! 이상 신호 감지 !!" 배너 후 회피 페이즈.
- **전투 배속** — `SettingsManager.battle_speed_factor()`(NORMAL 1/FAST 2/SKIP 6) →
  안무 러너 delta·트윈·히트스톱 적용(타이밍 링은 입력 공정성상 제외).
- **전투 중 도구 사용** — 커맨드 5종 확장, hp_restore 소모품 메뉴·회복 팝·인벤 차감.
- **아이템 DB 빈 로드 실버그 수정** — load_array(최상위 배열 전용)로 객체 래핑된
  items.json을 읽어 **아이템 DB가 항상 공백**이었음(UI 폴백이 은폐). load_dict로 수정.
  자동 테스트(도구 섹션)가 적발 — 자동화 실효 사례.
- **battle_scene_controller 분리** — 406→296행. BattleSetup(스킬/적 구성)·
  BattleEnemyPhase(일반공격/회피 시퀀스)·BattleRewards(보상) 추출, 스킬 효과 부여는
  BattleController로, 타이밍 판정은 TimingRing.window_for로 이동.
- **dead code 정리** — faithful_mode·speed_multiplier 제거(난이도 프리셋 자체 미와결
  실측 — get_difficulty_mult 호출부 0건. DP 반영은 프리셋 실착 시 과제).
- **LLM 납품 심사 보드** — `심사실행.bat` → tools/review/(stdlib 서버+보드).
  카드=원본|납품|앵커 3열+검증 배지, 승인=20_processed(스프라이트는 그리드 컷팅 겸용),
  반려=재요청 패키지 자동 생성(_feedback/<cat>/<file>.md = 원본 의뢰문+유저 사유+
  검증 결과+v<n+1> 지시, 파일은 _rejected), 전체 승인/반려 배치. 가짜 납품 2건으로
  전 경로 실사.
- **LLM_REQUEST_GUIDE.md** — 타 PC 세션용 원페이지 가이드(클론→패키지 재생성→의뢰
  첨부물 표→납품 규약→심사 루프→패킹 인계). assets/raw는 gitignored라 클론 시
  패키지 재생성 명령이 첫 단계.

**남은 작업 갱신 (우선순위순 — 5차 세션 종료 시점)**:
1. **LLM 납품 수령 사이클(유저)** — 패키지 33종 생성 완료, 가이드 문서 있음.
   납품→심사 보드→채택분 패킹 요청.
2. **Windows export preset** — export_presets.cfg 부재 실측(8/26). data/**.json 포함
   조기 검증 필요(빌드 함정 예방).
3. battle_presenter 354행(상한 초과) — 팝/플래시 계열 추가 분리 여지.
   scene controller는 296행으로 상한 준수(5차 세션 분리 완료).
4. 루트 정크(`[godot.exe` 0바이트) 삭제 — README 구조도는 5차 세션에 수정함.
5. Mac/Linux export 프리셋 + headless 검증 CI(외부 계정 필요 — 보류 유지).
6. 전투 후보(미구현): 스킬 획득 흐름(grant_skill 실제 플레이 반영), 상태이상 아이콘화.

### 다음 세션 연계 (8/25 4차 세션 종료 시점)

**4차 세션 결과(전부 커밋됨, origin 대비 8+커밋 — push 보류 중)**:

1. **필드 이동 불가 근본 수정**: GridMover가 트리 밖 노드라 create_tween 실패
   → 첫 보행 후 영구 잠금(부수로 enabled 미검사·Gate 판정 레이스도 수정).
   transition_gate은 process_physics_priority -10 선처리.
2. **엔진 백로그 전량 소화**: F2→F3 계단 잠금(transitions guard 3분할,
   Q_F2_POSTER 게이트) / Q_F1_START 정밀화(dworm first_win_flag +
   내부 마커 q_f1_opening_seen) / Q_HP_ALL·Q_QUIZ_ALL 정밀 판정
   (크레딧룸 멤버 전원 확인·메타퀴즈 오답 0) / Godot features 4.7 승격 /
   B2 gdformat+pre-commit 도입(전체 포맷 적용).
3. **WP-7**: Q_F5_BOSS_CURE「30분의 침묵」데이터화 — professor_monster 보스,
   f5_professor/f5_cure 컷신, triggers_f5 4단 계층, 죽어 있던
   q_f5_boss_gate 부활(f4_sacrifice가 세팅).
4. **UI 현대화**: HUD 재작성(HP/EXP 게이지, growth.json 산출 상한, 아이템
   슬롯 6칸), InventoryPanel 신규(I키), ItemIcons 플레이스홀더.
5. **오디오 실음원**: tools/dev/make_audio.py(numpy 합성) — SFX 21종 WAV,
   BGM 6곡 OGG(스펙 duration/bpm 준수). 엔진은 공용 라이브러리에서 임포트.
6. **공용화**: `D:\Game\_godot_shared` 신설(git) — chipwave.py,
   check_scripts.gd, headless_check.bat, json_util.gd,
   audio_manager_template.gd. snow_frost_war/LodeRunner도 채택·저장소화.

**검증 인프라 현황**: 검증실행.bat **13단계**(임포트→validate→smoke 10종→
check_scripts). SelfCheck 프루브 11종. pre-commit 훅(gdformat --check) 활성.

**남은 작업 (우선순위순)**:
1. ~~전투 보상 하드코딩 제거 + 레벨업 반영~~ ✅ 4차 세션 후반 완료
   (monsters.json 범위 보상, grant_exp 레벨업, SelfCheck 성장 프루브)
2. ~~CRT/DOS 메타 엔딩 연출~~ ✅ 완료(ending_console, 크레딧룸 종료 분기)
3. ~~설정 패널 조작법·접근성 통합~~ ✅ 완료(흔들림 토글+조작법 행,
   SettingsManager.screen_shake 영속화, shake 2곳 가드)
4. Windows export preset 조기 검증(data/**.json 포함 확인 — 빌드 함정 예방)
5. 패키징 export 프리셋(Mac/Linux) + headless 검증 CI
6. 에셋: NPC 스프라이트 LLM 사이클(코드 폴백 완비), 아이템 아이콘 실도트

**공용 라이브러리**: `D:\Game\_godot_shared`(로컬 git, 원격 미연결 —
GitHub 저장소 생성 후 `git remote add origin` 필요).
snow_frost_war/LodeRunner git 저장소화 완료(Lode는 AudioManager 마이그레이션까지).

### 구현 노트 (P8 세션 추가)

- **LLM 워크플로우**: extract_sprites.py(numpy 벡터화 flood-fill, 935프레임 수십 초,
  중복 제거, 컨택트 시트는 표준 128 셀 + 마젠타 배경) — 00_reference는 gitignored
  임시区, 스크립트로 재생성 가능.
- **validate_retouch_sheet.py**: 납품 자동 판정(크기/투명도/마젠타/도트 bbox/편차).
- **export_player_sheet.py(리터칭용) / export_player_gen_package.py(신규 생성용)**:
  원판+주석+프롬프트 md 생성. 프롬프트에 "실제 도트 크기/오프셋/마젠타 규칙/그리드
  무변경" 명시 — 누락이 1차 반려 원인.
- **오디오**: AudioManager 실구현(버스/루프/SFX풀), 필드·전투 BGM 배선,
  spec sfx 21종. 실제 음원 파일은 미생성(부재 시 조용히 스킵).
- **DOSBox**: run_sidol.bat 레포 상대경로 conf 생성, 캡처 assets/raw/dosbox_capture.

## 4. 알려진 미해결

| ID | 내용 | 우선순위 |
|---|---|---|
| B1 | ~~빈 폴더 `BSD 시돌이의 모험\` 껍데기 삭제~~ ✅ 해소(8/25 — 이미 부재) | — |
| B2 | gdformat/pre-commit 설정 파일 미생성 | 낮음 |
| B3 | ~~DialogueBox 스킵 시 visible_characters 음수 방지~~ ✅ 해소(8/25 재검증) | — |
| — | 로컬 Godot 4.7 vs 저장소 features=4.3 — 버전 승격 여부 결정 필요(미결정 시 임포트마다 project.godot 재변경) | 중간 |
| — | `_shared/schemas/{sprite_spec,audio_spec,event_cutscene}.json` 등 5종이 커밋 미포함 상태로 로컬 존재 — 데이터 `$schema` 참조 대상, 업스트림 커밋 누락 의심 | 중간 |

## 5. 핵심 설계 결정 이력

| 결정 | 근거 문서 |
|---|---|
| G-ART = B안(32px 타일, 64px 캐릭터) | roadmap 게이트 표 + 04_uiux §2 |
| G-SCOPE 확정: 단일 엔딩+후일담 카드 3종 | 마스터 시나리오 §1 |
| 몬스터 AI: BFS 추적+배회+분산 (원작 패턴표 폐기) | 01_oop_redesign §5 |
| 대사 ID: @t(원문 불변)+@c(신규, 구역별 대역) | 마스터 부록 A |
| 에셋 공급: 원작 리마스터 우선, AI 생성은 일러스트만 | 07_ai_asset_pipeline |
| 보스전: 턴제+회피 페이즈 하이브리드 | 05_toolchain §5.3 |

## 6. 주요 파일 빠른 참조

| 찾는 것 | 경로 |
|---|---|
| 프로젝트 설정 | project.godot |
| 맵 데이터 | data/maps/f*.json |
| 아이템 DB | data/items.json (63종) |
| 스킬 DB | data/skills.json (6종) |
| 인카운터 테이블 | data/monsters.json |
| 성장 곡선+난이도 | data/growth.json |
| 대사 테이블 | data/dialogue.json (@t229항목) |
| NPC 배치 | data/maps/npcs_f*.json |
| 계단/게이트 | data/maps/transitions.json |
| AI 코딩 규칙 | AGENTS.md |
