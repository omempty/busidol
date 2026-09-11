# 19차 세션 인수인계 — 도구·AI·에셋 계약

> 작성: 2026-09-09. 브랜치 **`session19/tools-ai-assets`** 에 커밋 11개(그중 하나는 동시
> 진행 중이던 다른 세션의 것 — §4)로 올라가 있다.
> `main`은 건드리지 않았다 — 아래 §3을 읽고 판단한 뒤 `git merge --ff-only` 하면 된다.
>
> 관문은 `[19/24] Autoplay`를 뺀 23단계가 통과한다. Autoplay는 **간헐적으로 실패하고,
> 그 실패는 이 세션 이전부터 있었다**(§3에 측정값).

---

## 0. 한 줄씩

| # | 커밋 | 무엇 |
|---|---|---|
| 1 | `41cdce8` | **이 세션 것이 아님** — 시작 전부터 워킹트리에 있던 F1 정전·전자잠금 이벤트(18차→후속 세션 인계분)를 `HANDOFF_F1_EVENTS.md`를 근거로 묶어 커밋했다 |
| 2 | `d63ac18` | 셀 편집기 부동 이동·묶음 편집 + 타일셋 계약 정본 |
| 3 | `c59f2bb` | 소품 덧층(원본 맵 불변) |
| 4 | `a813fad` | 몬스터 크기 차등이 설치 메타에 반영되지 않던 것 |
| 5 | `901baac` | 이동 패턴 3종이 선언만 있고 안 돌던 것 + NPC 곁 스폰 배제 |
| 6 | `ceacd51` | 고정 NPC·워커 미세 동작을 정수 픽셀로 |
| 7 | `d894727` | 원작 이관 인물 7종 리마스터 의뢰 경로 |
| 8 | `5a28a67` | 웹 프롬프트 카테고리 분기 + 주인공 리터칭 정본화 + `docs/TOOLS.md` |
| 9 | `d1175a1` | 해제된 액터가 `face()` 타입 검사에서 죽던 것 |
| 10~ | (2026-09-09 이후) | 오토플레이 SKIP·만렙 20 연장·F3 대사 오배선·**F5 보스 막다른 길** — 백로그 §3.9/§3.10에 상태가 적혀 있다 |

**이번 세션이 반복해 만난 결함 유형은 하나다: 선언은 있는데 읽는 코드가 없다.**
이동 패턴 3종, 타일셋 계약, 인물 7종 계약, 몬스터 크기 차등, 주인공 의뢰 경로, NPC 방 배제 —
전부 "데이터·주석·enum에는 있는데 실제로는 안 도는" 상태였다. 그래서 이번에 고친 것마다
**그것을 재는 관문을 같이 붙였다**(§2).

---

## 1. 남은 일 — 우선순위 순

### 1.1 오토플레이 관문 (§3에서 이어짐)
`[19/24]`가 3~5회에 1~3회 실패한다. **기준선에서도 같은 지문으로 재현되므로 이 세션의
회귀가 아니다.** 다만 관문이 흔들리면 앞으로의 모든 작업이 그 아래 묻힌다 — 먼저 잡는 것을 권한다.

### 1.2 소품 — **그림만 남았다** (조사·차단 관문은 2026-09-09 완료)
- ~~**조사(SPACE)**~~ → 배선 완료(`ce8ea3c`). `PropsLayer.inspect_steps()` → `field._prop_in_front()`
  → `_start_inspect()`가 원작 마커와 같은 대사창을 연다. 우선순위는 트리거 → 계단 → NPC →
  워커 → 원작 마커 → 상자 → **소품**. `inspect.requires_flag`는 "그 플래그가 서야 그 대사를
  쓴다"로 규약 확정(안 서면 조사 대상에서 빠진다).
- ~~**통로 차단 관문**~~ → `PropsProbe.check_choke` + `Placement.blocks_cells()`로 완료(`00aef1a`).
  소품이 **실제로 막는 칸**만 놓고 묻는다(윗칸이 머리 위로 지나가는 모양을 과잉 판정하지 않게).
- **그림**: 여전히 미배선. `assets/spec/sprites/tileset_campus.json`은 생성 스펙일 뿐 obj 아틀라스
  인덱스가 없고, 타일 납품이 와야 정해진다. 붙일 자리는 `renderer.set_object(cell, id)`
  (`scenes/field.gd`가 열린 상자에 쓰는 그 함수). 그때까지 시각 단서는 조사 알약 + 몸 셀 하이라이트뿐이다.
- **덤으로 드러난 것**: 이벤트 두 개(`f1_sopo`·`f1_gas`)가 소품에서 4칸 떨어진 빈 좌표를 밟는
  구조였다. `zone` → `interact`로 바꿔 우편함·사물함 조사로 나게 했고, 어긋남은
  `PropsProbe.check_event_alignment`가 잰다.

### 1.3 대형 인물 스프라이트 — 범위 미확정
유저 요청("기존 시돌이를 비롯한 스프라이트 / 대형 인물 스프라이트를 원본 기반 리터칭")에서
**"대형 인물"이 무엇인지 확인이 안 끝났다.** 후보 둘:
- **전투 대형 컷**(`battle_cuts`, 셀 512) — 원작 320×200 전면 연출 프레임 **82장**이
  `assets/raw/llm/00_reference/{a1~a5,d1~d4,e1~e8,fire}`에 그대로 있어 **원본 기반 리터칭이
  바로 가능하다.** "원본 기반한채로"라는 표현에 가장 맞는다.
- **대화 초상**(`portraits`, 256×256 × 3표정) — 원작에 대응 그림이 없어 신규 창작이다.

전자라면 `export_player_remaster_package.py`·`export_character_remaster_packages.py`와 같은 결로
`export_battle_cut_remaster_packages.py`를 만들면 된다(공용 헬퍼는 이미 다 있다).

### 1.4 확인 대기 중인 결정들 — **2026-09-09 전부 확정**
- ~~**`sys_builder` 크기**~~ → **192px 유지**. 근거: `monster_anim_specs.json:990`의
  `is_final_boss: true`를 가진 **유일한 종**이고(5층 결전, 탄막 dodge_phase도 이 종 전용),
  192÷192 = **정확히 1.0** 배율이라 사다리(`install_delivery.py:63`)에 그대로 맞아 리샘플이 0이다.
  128로 낮추면 결전 보스가 다른 보스와 같은 크기가 된다. 의뢰문 크기 계산은 이미 192 기준으로
  고쳐져 있어(`export_monster_packages.py:181`) 추가 비용도 없다. **데이터 변경 없음.**
- ~~**`RANGED` 이동 패턴**~~ → **enum에서 제거**(`movement_pattern.gd`, 근거 주석 동봉).
  실측: 데이터 배정 **0건**, `preferred_distance`/`projectile_interval`을 읽는 코드 **0곳**,
  필드에 발사체 수단 자체가 없다(투사체는 `battle/dodge_phase.gd` 전용). 되살리려면 필드용
  투사체부터 만들어야 한다. `monster_anim_specs.json`의 crt_overseer는 아트 스펙이라 그대로 뒀고,
  층에 올리는 순간 `check_pattern_coverage`가 잡는다.
- ~~**`idle_anim: "squash"`**~~ → **계약을 `bob`/`none` 둘로 확정하고 배선했다.**
  데이터 11건을 `bob`으로 바꿨고(`npcs_f0~f4.json`), `field.gd`가 `NpcEntity.set_idle_anim()`으로
  넘기며, `ActorProbe.check_idle_anim_coverage`(world_audit)와 `smoke_field_test.gd` §5가
  다시 죽는 것을 막는다. 실측: world_audit `[ok] NPC 11명이 쓰는 1종 전부 구현됨`.
- **크기 정책**: 잡몹 64px / 주인공·NPC 85px / 보스 128px로 정리했고 유저가 "적당하다"고 했다.
  주인공만 비정수 배율(0.6667)인데 2/3은 3줄→2줄의 규칙적 축소라 도트는 고르게 떨어진다.

### 1.5 그릴 것 (다음 의뢰의 계약)
- **전용 시트 4장** — `dev1`·`dev2`·`lab_student`·`afterschool_student`(지금 주인공 얼굴을
  플레이스홀더로 쓴다). 128 셀 · 256×640 · 5행×2프레임. 이것만 채우면 world_audit WARN 4 → 0.
- **진짜 idle 행** — 전용 시트 8종의 `idle_down`이 `walk_down`의 **바이트 복사본**이다(실측).
  frame 0은 재사용 가능하므로 신규 작화 8장.
- **인물 7종 리마스터** — `assets/raw/llm/npcs/<id>/`에 의뢰 패키지가 이미 구워져 있다.
- **주인공 리터칭** — `assets/raw/llm/sprites/player_sidol/`에 구워져 있다(512×1024).
- **타일셋** — `python tools/convert/tileset_contract.py`가 배치를 찍어 준다(256×288).

---

## 2. 이번에 붙인 관문 — 이것들이 다시 죽는 걸 막는다

| 관문 | 무엇을 재나 | 어디 |
|---|---|---|
| `ActorProbe.check_pattern_coverage` | 데이터가 배정한 이동 패턴에 `decide()` 분기가 있는가 | world_audit |
| `ActorProbe.check_actor_clearance` | 고정 NPC와 몬스터의 이격(반경 8) | world_audit |
| `props_check.py` | 소품 스키마·정본 id·크기·맵 범위·겹침·원본 ATT·문 간섭 | run_gates `[22/24]` |
| `prompt_audit` 확장 | 주인공 정본(`assets/spec/sprites/*.json`)도 대조 + **(카테고리, id)로 색인** | `python tools/review/prompt_audit.py` |
| `test_sheet_ops` 68건 | 묶음 정렬·계측, align=none, 채움 비율, 행 단위 재배치 | run_gates `[24/24]` |
| `fixer_probe` 22+23건 | 셀 편집기 실조작(부동 이동·묶음·서버 왕복) | `python tools/review/fixer_probe.py --server` |
| `ActorProbe.check_idle_anim_coverage` | 데이터가 선언한 `idle_anim`에 실제 동작이 붙어 있는가 | world_audit |
| `PropsProbe.check_inspect_reach` | 앞에 설 자리가 없어 대사가 죽는 소품 | world_audit |
| `PropsProbe.check_event_alignment` | 플래그로 묶인 트리거와 소품의 자리 어긋남 | world_audit |
| `PropsProbe.check_choke` | 소품이 길을 끊는가(`Placement.blocks_cells`) | world_audit |
| `smoke_all_floors` §5 | **F5 보스전에 져도 게임이 계속되는가** — 패배 복귀 직후 auto 재발동 없음 / 콘솔 조사로 재도전 열림 / 승리 후 닫힘 | run_gates `[9/24]` |
| `ActorProbe.check_story_species_density` | `first_win_flag`를 매단 종의 정원이 밀도 4종 전부에서 확보되는가 | world_audit |
| `ActorProbe.check_story_species_spawned` | 그 종이 층에 **실제로** 서 있는가 | world_audit |
| `smoke_field` 밀도 검사 | 명단을 네 밀도로 실제로 뽑아 dworm 포함 여부 + 격파 후 「없음」=0마리 | run_gates `[4/24]` |

> `props_check.py` 행에 **플래그 사슬**이 더해졌다(`8c0d3e9`): 소품이 기대는 `open_flag`·
> `requires_flag`를 아무도 안 세우면 FAIL. 오타 한 글자로 소품이 영영 죽는 자리였다.

### 2.1 부정 시험을 꼭 같이 넣었다
정상만 보는 관문은 고장 나도 초록이다. 예: "묶음을 모르면 소품이 부서진다"(상자 폭 56 → 60),
"묶음을 모르면 계측이 중앙 이탈로 잡는다", props 부정 시험 10종.

조우 밀도 쪽도 부정 2종(정원 보장 제거 / 앞자리 확정 제거)으로 붉어지는 것을 확인했다.

F5 보스 재도전 시험도 부정 2종으로 붉어지는 것을 확인했다 — ①재도전 트리거를 지우면 "재도전이
열리지 않는다"가, ②연출용 auto에 `guard_flag`를 얹으면 "패배 복귀 직후 auto가 다시 발동했다 —
층을 떠날 수 없다"가 뜬다. ②는 백로그가 원래 적어 둔 처방이라, **부정 시험이 그 처방을 기각했다.**

### 2.2 측정이 실제로 결함을 잡은 사례 (이번 세션에서만 4건)
- 매복이 **위장 중에도 8칸 밖에서부터 경고 표식**을 띄우고 있었다(`HOMING_KINDS`).
- world_audit이 붙자마자 **워커가 몬스터에게 8칸까지 걸어간 것**을 잡았다 → 워커를 반경 대상에서 뺐다.
- `prompt_audit`을 주인공까지 확장하자마자 **내 첫 패키지의 행 표 형식 결함**을 잡았다.
- 그 확장이 **잠복해 있던 id 이름공간 충돌**(초상 `prof_chem` ↔ 시트 `prof_chem`)을 드러냈다.

### 2.3 도구 사용법은 `docs/TOOLS.md`가 정본
`.bat` 진입점 11개 · 파이프라인 · 셀 편집기 사용법 · 관문 24단계 표 · 소품 덧층.
손으로 쓴 허브 문서(`MONSTER_WEB_PROMPT_HUB.md` 등)는 "대체됨" 경고를 달고 틀린 수치를 걷어냈다.

### 2.4 도트에 쓰면 안 되는 것 (실측 근거)
셀 128을 `scale 0.6667`로 그려 화면 85.34px가 되는 구조에서:
- **스케일 스쿼시 불가** — ×1.035면 85행 중 **73행(86%)** 이 다른 원본 행을 집는다.
- **회전 불가** — 0.09rad이면 85px 스프라이트 윗변이 아랫변보다 **7.70px** 밀린다.
- 쓸 수 있는 것: **정수 px 오프셋**, 그리고 시트에 이미 있는 두 번째 walk 프레임.

---

## 3. 오토플레이 관문 — 다음 세션이 이어받을 것

### 무엇이 일어나는가
`[19/24] Autoplay`가 간헐적으로 exit 1이다. 판정은 `걸어서 닿은 층 ≥ 5`
(`tools/dev/autoplay.gd:185`, 값은 `driver.visited_regions.size()`이고 요약의 "층"과 같은 수다).

**실패 회차는 두 무리로 뚜렷이 갈린다** — 느린 것이 아니라 **초반에 막힌다**:

```
정상   걸음 5200~5900 / 층 6
실패   걸음 1766~2871 / 층 2
```

### 측정값 (전부 같은 명령: --seconds 240 --goals 150 --require-floors 5)

| 조건 | 결과 |
|---|---|
| HEAD 전부 적용 | 5회 중 **3회 실패** (2871·1766·1790 걸음 / 층 2) |
| 소품만 끔 | 3회 중 **1회 실패** (2868 / 층 2) |
| **기준선 `41cdce8`**(이 세션 변경 전) | 1회차 **실패**(1788 / 층 2) · 2회차 통과(6486 / 층 6) — 실패 지문이 HEAD와 일치 |

→ **소품은 원인이 아니고, 이 세션의 회귀도 아니다.** 기준선에서 같은 모양으로 재현된다.
(기준선 측정은 4회 예정 중 2회차까지 확인했다. 워크트리를 다시 만들어 이어서 재면 된다:
`git worktree add --detach <경로> 41cdce8`)

### 다음에 볼 곳
- 실패 회차의 **로그 꼬리**를 받아 어디서 멈추는지 본다(`--out user://autoplay_gate.md`가
  `docs/05_status/01_autoplay.md`로 나온다). 지금까지는 요약만 봤다.
- 층 2에서 못 넘어간다면 **계단·전이 게이트**(`src/map/transition_gate.gd`)와
  `autoplay_goals`의 목표 선택이 1차 후보다.
- 기록상 예전에는 한 판이 **77초 안팎에 완주**했는데 지금은 240초 예산을 다 쓴다.
  이 둔화 자체가 별도 조사 대상이다(기준선에도 있으므로 이 세션 것이 아니다).

### 별개로 고친 것
`autoplay_pilot.face()`가 안 쓰는 `player` 인자를 타입으로 받아, 전투·컷신 전환으로 해제된
액터가 넘어오면 **본문에 들어가기도 전에** 죽었다(`d1175a1`). 스크립트 오류는 0건이 됐지만
**위 실패와는 무관하다**(오류가 난 회차도 exit 0이었다).

---

## 4. 같은 트리에서 다른 세션이 동시에 돌고 있었다 — 주의

커밋 직후 작업 트리가 깨끗했는데(변경 0), 잠시 뒤 웹 프롬프트 41개와 `_remake.png` 3장이
바뀌어 있었다. 처음에는 "관문이 추적 파일을 말없이 바꾼다"고 의심했고
`export_check.py`·`spr_alpha_check.py`를 단독으로 돌려 봤지만 둘 다 아무것도 안 건드렸다.

**정체는 동시 작업이었다.** 브랜치에 내가 만들지 않은 커밋이 끼어 있다:

```
f76cfa7 feat(assets): 웹 캐릭터 프롬프트에 death 본체기준 정렬·투사체금지·리샘플금지 보강 + 31종 재생성
        omempty · 2026-09-09 13:19:35 · web_prompt.py + web/*.md 31개
```

즉 같은 워킹트리에서 다른 세션이 `web_prompt.py`를 고치고 재생성하고 있었다.

### 반드시 알아야 할 것 — 내가 그 변경을 한 번 되돌렸다

원인을 좁히는 과정에서 **`git checkout -- assets/`** 를 실행해 그때 워킹트리에 있던
`assets/` 변경을 버렸다. 그 시점에 다른 세션의 작업이 **아직 커밋 전이었다면 그것을 날린 것**이다.
결과적으로 `f76cfa7`이 남아 있으므로 웹 프롬프트 쪽은 복구된 것으로 보이지만,
**같이 사라졌던 `_remake.png` 3장**(`flying_thesis`·`null_pointer`·`rogue_vending`)은
그 커밋에 없다. 그쪽이 다른 세션의 산출물이었다면 되살려야 한다:

```
python tools/convert/install_delivery.py flying_thesis null_pointer rogue_vending
```

### 교훈
이 저장소는 **여러 세션이 같은 워킹트리를 공유**한다(18차 셀 편집기, F1 이벤트 후속 세션,
그리고 이번의 동시 세션). 내 것이 아닌 변경이 보인다고 `git checkout --`/`git restore` 로
버리지 마라 — 먼저 `git log`·`git stash list`로 누구 것인지 확인한다.

---

## 5. 정리하지 않은 것

- 기준선 비교용 워크트리를 만들어 뒀다면 지운다: `git worktree remove <경로>` / `git worktree prune`.
- `assets/raw/llm/**`은 gitignore라 커밋에 안 들어간다(의뢰 패키지는 각자 다시 구우면 된다).

---

## 6. 세션 종료 시점 인수인계 (2026-09-09 마감)

백로그 **§3.9 「게임을 끝낼 수 있는 자리 3곳」이 전부 해소**됐다. 셋 다 같은 모양이었다 —
**데이터·설정이 시나리오 사슬을 끊을 수 있는데 아무도 재지 않았다.**

| 자리 | 무엇이었나 | 어떻게 닫았나 | 관문 |
|---|---|---|---|
| F5 보스 2건 | `auto` 트리거의 `done_flag`가 컷신 **전에** 서서, 첫 패배로 승리 플래그가 영영 안 섰다 | 연출 `auto`는 그대로 두고 **소품 콘솔 위 `interact` 재도전**을 얹었다(`guard_flag`) | `smoke_all_floors` §5 |
| 조우 밀도 | `first_win_flag`를 매단 종이 밀도·무작위 추첨으로 사라졌다(「보통」에서도 32.8%) | **시나리오 종은 랜덤 조우가 아니다** — 정원·앞자리를 보장 | `ActorProbe` 2종 + `smoke_field` 밀도 검사 |
| F3 대사 오배선 | 메인 퀘스트 2개가 퀴즈 보기를 읊었다(12줄) | `@c347`~`@c358` 신설·화자 재배정 | (데이터 교체) |

### 이번 마감에서 배운 것 — **백로그의 처방을 그대로 믿지 마라**

두 건 다 백로그가 적어 둔 처방이 **부정 시험에서 기각**됐다.

- F5: 「`done_flag` → `guard_flag`(데이터 2줄)」 → **무한 재전투**가 된다. 패배 복귀는
  `change_scene_to_file(field.tscn)`이고 `load_for_floor`가 `_fired`를 비우는데
  `GameState.player_cell`은 그대로다 — 발동 자리에 선 채로 돌아온다.
- 밀도: 「①NONE 제거 ②플래그 대체 출처 ③방치」 → **셋 다 문제를 잘못 잡았다.** 재 보니
  NONE은 스펙트럼의 끝일 뿐이고 「보통」에서도 세 판에 한 판이 같은 상태였다.

처방을 쓰기 전에 **먼저 재는 것**이 두 번 다 정답을 바꿨다.

### 다음 세션이 이어받을 것 (우선순위 순)

1. **`Q_F2_FIGHTER` 공회전** — 트리거·플래그·대사가 전부 없고, 보상 [연속 펀치]는 이미 시작 스킬이다(§3.9.3).
2. **`choice` op 실질 0** — 러너와 `tests/smoke_choice.tscn`은 이미 있다. 데이터만으로 3곳 추가 가능(§3.10 #3).
3. **`@c420`이 정의 없이 참조된다**(`f4_sacrifice.json`) · **`@c441` 피카츄 시대 오류** · **`@t` 재작성 15개**(원문 복원 or 규칙 개정 — 판단 필요).
4. **`@c230`이 F3 이벤트를 "2층"이라 안내한다**(§3.9.4).
5. **선행 사슬 미구현** — `quests_v2.json`이 규정한 F0 디스켓 → F4 배터리 → F4 희생이 트리거 `requires_flag`에 없다(§3.9.3).
6. **Memory Archive 명세** — 기존 `credits.json.ending_cards` + `scenes/credit_room.gd`의 확장으로 쓴다.
   조각을 매달 그릇은 이번에 생긴 **소품 `inspect`**다(`memory_id` 필드 한 칸). 실측 공백:
   F5 상자 0개 · `choice` 실질 0 · F4 대사 12줄(F1은 54줄).
7. **소품 그림 미배선** — `renderer.set_object(cell, id)`에 붙일 자리는 있는데 obj 아틀라스 인덱스가
   없다. 그때까지 소품은 **보이지 않고 막기만 한다** — F5 콘솔 둘도 같은 상태다(§1.2).

### 주의 — 사생활
`https://github.com/omempty/busidol`는 **공개 저장소**이고 `credits.json`에 실명 9명 + 일화가
이미 들어 있다. 1995년 실사진을 도입한다면 `assets/private/`(gitignore)에 두고 배포 zip에만
싣는 것을 권한다.

---

# 19차 세션 — 후반부 (2026-09-09 밤)

> 같은 브랜치 `session19/tools-ai-assets`에 **커밋 12개**를 더 올렸다(`9276434` ~ `0c3f5ea`).
> 시작은 "셀 편집기가 멀쩡한 그림을 반려한다"는 신고 하나였는데, 파고들자 **같은 뿌리의
> 결함이 층층이** 나왔다 — 선언은 있는데 읽는 코드가 없거나, 두 곳이 서로 다른 잣대를
> 쓰거나, 만든 것을 아무도 다시 재지 않는 자리들이다.

## A. 한 줄씩

| 커밋 | 무엇 |
|---|---|
| `9276434` | 흩어진 소멸 프레임을 **파편 기준**으로 재 멀쩡한 그림을 반려했다 → 정렬 기준을 `dc.align_anchor` 하나로. 겸사겸사 게임에 **낡은 시트**가 들어 있던 것을 발견 |
| `d6ee660` | 프롬프트가 **화면 표시 크기를 한 번도 말하지 않았다**(31종 중 24종이 절반으로 축소되는데 전부에게 같은 지시) |
| `271609c` | 행 단위로는 못 맞추던 그림을 **사각 영역으로 집어 칸에 앉히기** |
| `bd103da` | [행 재배치]를 눌러도 안 맞았다 — 옆 프레임 몇 px이 상자를 부풀렸다 |
| `a8d2d00` | 그림이 시트 폭을 안 채우면 프레임 배정이 통째로 어긋났다 |
| `d3f2ecd` | 심사보드 **버전 삭제** + 칸 내용 축소 3종 |
| `22d4146` | **ESC가 무조건 메뉴로** 갔다(자식 순서 의존) · 초상이 이름 불일치로 안 떴다 · 잡몹 크기 원복 |
| `8580574` `0c3f5ea` | git에 든 **초상 9종이 낡아** 있었다(prof_mo 등 5종은 13~16색 플레이스홀더) |
| `646db72` | **내가 게임을 깨뜨렸다** — CanvasLayer에 없는 함수. + 심사보드 실조작 시험 |
| `2b7c57a` | 셀 편집기 우측 패널 **탭 6개** + 탐색기에서 열기 |
| `a569f62` | 초상 **표정 2·3칸이 사문화**였다 + refit이 멀쩡한 시트를 키워서 깨뜨렸다 |

## B. 되풀이된 결함의 모양

이 세션에서 **다섯 번** 같은 모양이 나왔다. 다음 세션도 이것부터 의심할 것.

1. **잣대가 두 벌** — 검증기는 본체 덩어리로, 편집기 계측·정렬 스냅·refit은 전체 bbox로
   쟀다. 같은 파일에 계측은 "이상 없음", 검증기는 `[ERR]`. 자동보정을 눌러도 판정이 안
   바뀌는 무한루프까지 났다. → `dc.align_anchor` 하나로 모았다.
2. **선언은 있는데 안 읽는다** — 스펙의 `cell.w`(화면 크기)를 설치기만 읽고 프롬프트는
   안 읽었다. 초상 스펙의 `name`과 대사 화자가 달라 초상이 조용히 안 떴다.
   초상 표정 3칸이 그려져 있는데 대사가 `expr`을 안 써 0번 칸만 나왔다.
3. **만든 뒤 다시 재지 않는다** — 승인되면 `20_processed`는 갱신되는데 **설치가 자동으로
   따라가지 않는다**. 시트 3종·초상 9종이 낡은 채로 게임에 들어 있었다.
4. **문법 검사는 컴파일 검사가 아니다** — `gdformat`은 통과했는데 게임은 안 켜졌다.
5. **고친 것을 사람 눈으로 안 본다** — 브라우저·게임을 실제로 켜서야 드러난 것이 셋이다.

## C. 지금 상태 (실측)

    test_sheet_ops        통과 77
    test_autofix_plan     통과 21
    test_waivers          통과 18
    test_web_prompt       통과 5
    installed_sheets      통과   (게임이 읽는 시트 11종)
    portrait_speakers     통과   (설치 초상 17개 / 화자 20종 중 초상 뜨는 화자 5종)
    fixer_check           통과
    fixer_probe           통과 31 (브라우저 실드래그)
    board_probe           통과 7  (심사보드 실조작)
    smoke_portrait        PASS
    smoke_dialogue        PASS
    field.tscn 기동        SCRIPT ERROR 0건
    autoplay 120초         걸음 3196 / 층 6 / 전투 39 / 상자 27 / 대사 5 / 사망복구 0

관문은 이제 **31단계**다(Godot 씬 20 + python 11). 목록 정본은 여전히 `run_gates.ps1`.

## D. 자동 배치(refit) — 전 납품 스윕이 정본 검증법

세 번 고쳤고 두 번 되돌렸다. 마지막에 **납품본 28개 전체에 돌려 ERR 증감을 표로 뽑는
스윕**을 하고서야 회귀를 잡았다(o_ray_v1이 0 → 30건). 앞으로 refit을 손대면 반드시
같은 스윕을 돌릴 것 — 두 시트만 보고 판단하면 다른 데가 깨진다.

    최종: 시트 28개 · 좋아짐 17 · 나빠짐 0 · 그대로 11
      dworm_v1 8→1 · flask_titan_v3 28→3 · null_pointer_v3 12→9 · o_ray_v1 0→0

세 가지 규칙이 지금의 refit을 만든다(전부 시험으로 못박음):
- 앉히는 기준은 **본체**(`align_anchor`) — 잔조각이 본체를 밀어내면 안 된다
- 프레임은 **가로로 겹치는 덩어리 묶음**, 폭 상한 1.4칸 — 밴드로 자르면 옆 프레임이 섞인다
- **기본값으로는 키우지 않는다** — 키우면 본체·그림자 간격까지 늘어나 정렬이 깨진다

## E. 남은 것 — 사람 판단이 필요하다

1. **초상 별칭**: 확실한 1건(`npc_tutor_dumb ← 멍청 조교`)만 넣었다. 모교수(괴물)·복사기
   앞에 막힌 조교·전자과 조교·단역 워커 2종은 **누구의 얼굴인지가 연출 판단**이라 비웠다.
2. **초상 표정**: 본문이 명확한 14곳만 붙였다. 나머지는 연출.
3. **초상 낡음 검사 없음**: `installed_sheets_check`는 `assets/sprites`만 본다. 이번에 초상
   9종이 낡은 것이 그래서 안 잡혔다. 초상까지 확장하는 것이 다음 과제.
4. **flying_thesis_v5**: 아직 심사 대기(36702색·전체 소프트 알파). 20_processed에 13색
   채택본이 있어 급하지 않다. 새 프롬프트로 받은 v6는 **PASS**였다(48색·반투명 0%).
5. **유저가 아직 눈으로 못 본 것**: ① 멍청 조교 첫 대사에서 당황한 표정 칸이 뜨는가
   ② 대화창 → 로그창 → ESC로 로그만 닫히는가. 헤드리스는 통과했으나 사람 확인 전이다.

## F. 새 도구 · 새 기능 (쓰는 법)

- **셀 편집기 탭** — 📝 의뢰문 / 🔍 검증 / 🧹 시트 전체 / 🎯 배치 / ✏️ 그리기 / 📜 기록
- **영역으로 집어 옮기기** — 선택 도구(V)에서 **그냥 드래그** → 집힘. 드래그·방향키로 이동,
  Enter 확정 / Esc 취소. `[선택 칸에 앉히기]`가 계약 정렬 자리로 보낸다.
  (Shift+드래그는 예전대로 사각 지우기)
- **축소 3종** — 선택 영역 / 선택 칸 내용 / 전 칸 내용. 격자는 유지한다.
- **지적 자동보정** — 검증 지적 중 **기계가 고칠 수 있는 것만** 돌린다. 계획은 서버가
  `tools/convert/autofix_plan.py`로 짠다(편집기에 표를 두면 두 벌이 되어 갈라진다).
- **지적 면제(FORCE OK)** — 지적 하나씩, 사유 필수, 키는 에셋 id라 다음 버전에서도 유지.
  크기·스펙·빈 칸은 면제 불가. 기록은 `data/asset_waivers.json`(git 추적).
- **탐색기에서 열기** — 외부 툴로 손보려고 지금 파일을 선택된 채로 띄운다.
- **심사보드 🗑️ 삭제** — 그 버전의 png + 피드백 md만. `20_processed`는 남긴다.
  **서버 코드라 심사 서버를 재시작해야 동작한다.**
- **보드 자동 갱신** — 창이 다시 앞으로 오면 다시 읽는다(F5 불필요).

## G. 이번에 확인된 사실 몇 가지

- **`flask_titan_v3`는 셀 편집기 3단계로 합격한다**: `[행 재배치]` → `[D] 복제 ×2`
  (walk c5·attack c7이 실제로 비어 있다) → `[색 양자화 48]` → `PASS`(ERR 28 → 0).
- **새 프롬프트가 실제로 먹혔다**: flying_thesis v5(36702색·반투명 100%·FAIL 3건) →
  v6(48색·반투명 0%·**PASS**). c_bug v4도 47색·PASS.
- **48색은 캐릭터에 넉넉하다**: 원작 실측 캐릭터 9~37색(중앙값 19) · 얼굴 27~35 · 아이콘
  4~20. 부족한 것은 소품·타일셋(원작 131~138)인데 그 납품 경로가 아직 없다.
- **몬스터 화면 크기**: 잡몹 85px · 보스 128px · sys_builder 192px
  (`SCALE_MIN = 0.6667`로 아래쪽만 원복 — 전면 원복이 아니다).

---

## H. 추가분 (2026-09-10 오후 세션) — 전투 재미 · 유입 NPC · 이펙트

> 같은 브랜치(`session19/tools-ai-assets`)에서 이어진 작업. **아직 커밋 안 됨** —
> 아래 변경분 전부 워킹 트리에 있다. 관문은 전부 통과(import 0 · validate 0 ·
> smoke·smoke_field·smoke_battle·smoke_f1_events PASS).

### H.1 전투 재미 (평타 연타 100% 승률 처방)
- **강타**: 전 종 `monsters.json` `heavy`{chance 0.10~0.20, mult 1.6~2.4} —
  모으기 턴(텔레그래프+CHARGE 팝+경고) → 다음 턴 발산. 대응=가드·격파·**브레이크(소멸)**.
  판정 `roll_heavy`(순수) · 연출 `try_heavy_charge`/`unleash_heavy` · 계측은
  `BattleController.enemy_turn`. 브레이크 턴 감소도 여기로 일원화(sim 영구 브레이크 수정).
- **철벽**: `bulwark.normal_mult`(iron_voc 0.5 · null_pointer 0.45) — 약점·브레이크
  아닌 타격만 감쇄. `Database` 패스스루에 `heavy`·`bulwark` 추가(안 하면 0% — special과 같은 함정).
- **재측정**(평타만·가드 없음, 층당 200): f4 승률 90% · f5 94.5%. 매운맛은 도전 난이도 담당.
  수치는 `docs/02_design/08_battle_rules.md` §7·§11에 실측 표로 갱신됨.
- **대형 컷 정교화**(WARMODE.C 대조): 스윙 종료 150→130(팔만 나오던 원인), flurry 20회,
  회피 b/c 구조 분리, 볼트 비행 중 적 퇴장, 딤 0.86+레터박스, z-order(빔이 딤 위로),
  컷 중 작은 주인공 숨김.
- **이펙트**: `src/battle/battle_fx_materials.gd` 신설 — 가산 블렌드·수명 색곡선·
  방사 글로우·피격 백열. 파티클·잔상·원작 FX·베기 아크에 적용.

### H.2 필드 편의
- **층간 휴식(회복소)**: `data/cutscenes/rest_entry.json` + `recover` op(컷신) +
  f0~f5 계단 착지 `fX_rest` zone 트리거. 전투 후 복귀 좌표에선 발동 안 함.
  HUD 갱신은 `state_changed.emit` 필수(빠뜨리면 게이지가 안 움직인다).
- **워커 기능**: `tint` 지원(스프라이트만) · `enabled` 킬스위치 ·
  **괴물 회피+느낌표**(반경 5, 적 추적 경고와 같은 칩). `EnemyManager.living_cells()` 추가.
- **적 워프 먼지**: `EnemyManager.enemy_warped` 시그널 → `FieldFx.enemy_warp_puff`.
  D웜 순간이동이 버그로 보이던 것(burrow 연출 미재생)의 처방.
- **세이브 슬롯 크래시 가드**: `save_slot_list.gd`의 `get_viewport()` null 가드.

### H.3 유입 NPC (B급 오마주 — "잘못 워프된 자들")
| 층 | id | 시트 | 비고 |
|---|---|---|---|
| f1 | 방랑 자판기 | rogue_vending 재사용+tint | 로그 벤딩과 구분 대사. **벽 앞(x116, 벽 y24-25)** |
| f1 | 전직 경비 | guard_idle 재사용+tint | |
| f1 | 미아 모험가 | lost_squire (Conrad, CC-BY-SA, 32px native ×2) | 문워크 교정済 |
| f2 | 길 잃은 오크 | lost_orc (AntumDeluge Orcs, CC-BY 3.0, 48x64 1:1) | 적 오인 개그 |
| f2 | 납치 공주 | lost_princess (Cabbit+AntumDeluge Gypsy, CC-BY 3.0, 48x64) | 오크와 듀오 |

- 대사 상황분기: f1 워커 2명에 `sequence_variants`(Q_F1_BLAST / Q_F1_BLACKOUT) 추가.
  DialogueManager가 플래그를 보고 고른다. f2 오크·공주는 다음 세션.
- **크레딧 표기済**(`data/credits.json` staff_roll). 시트 메타 `source`에 라이선스 명시.
- **외부 리소스 폴더 규약**: `assets/raw/inflow/` — 파일명=id, 같은 이름 `.txt`=출처.
  미아 모험가 원본(Conrad)·슬라임 팩이 여기 있다.

### H.4 발주서 (판타지 파티 4대장 — 납품 대기)
`assets/gen/prompts/web/npcs__party_hero.md` · `__party_mage.md` · `__party_dwarf.md` ·
`__party_elf.md` — 512×1024·8행(4방향 걷기4+대기2)·무기 금지. 납품되면 워커 배선.

### H.5 외부 사이트 검토 결과
- **Kenney**: 탈락 — Roguelike Characters는 16px 부속품(조립 필요)이라 규격 미달.
- **CraftPix**: 계정 가입 필요(자동 다운 불가) + 벡터풍 톤. `Tiny Schoolgirl` 팩만 육안 후보.
- **OGA 48px+ 라인 채택**(오크·공주 실증). 최소 규격: **네이티브 32px 이상 + 정수배만**.

### H.6 다음 세션 할 것
1. **슬라임 팩 활용** — `assets/raw/inflow/craftpix-net-788364-free-slime-mobs-pixel-art-top-down-sprite-pack`(Slime1~3,
   Walk 512×256·Idle 384×256 — **셀 레이아웃 실측 먼저**). 제안: 미아 파티의 펫 워커
   ("미아 슬라임") 또는 f0 적. 크롤링 아님(사용자 제공분).
2. **오크·공주 상황분기 대사**(f2 플래그).
3. **방랑 자판기 판매 기능** 여부 결정(현재 말만 검).
4. 4대장 납품 시 배선.
5. **커밋** — 이 세션 변경분이 전부 미커밋이다.
6. 실플레이 피드백(사용자 실행 중) 반영.

---

## I. 전투 연출·턴 시스템 보완 (2026-09-11)

> 계기: 유저 신고 둘 — "시돌이가 주먹 찌르기에 팔만 보이고 몸통이 안 보인다",
> "DWORM이 입에서 뿜는 빔이 DWORM 컷과 오버레이 시 위치가 안 맞는다".
> 겸사 "다른 전투 애니도 검토 + 전투 턴 방식(공격/방어…)을 현대 턴제 트렌드로
> 검토·보완" 요청. 아래는 그 결과다.

### I.1 핵심 규명 — 원작 `RPut_Spr` 4번째 인자는 **좌우 반전**이다

원작 엔진 함수 원본은 저장소에 없지만 호출부가 의미를 확정한다:

- `WARMODE.C:278` — `EnemyAvoid()`가 **마드아이(e1)의 4번 프레임만** `flag=1`로 그린다.
  e1의 4·5번 프레임은 서로 **반대를 향해** 저장돼 있어(육안 확인) 한 장을 뒤집어야 같은
  방향이 된다. `flag=0`이면 안 뒤집힌다.
- 주인공 공격 3종만 `flag=1`이다 — `AttackAni1`(:306) · `AttackAni2`(:327) ·
  `AttackAni3`(:344·:353). 회피(`MAvoid1/2/3`)·적·배경은 전부 `flag=0`.
- 그래서 `a1/a3/a5`는 파일에 **왼쪽을 향해** 저장돼 있다. 리메이크는 그 반전을 빼먹어
  시돌이가 적 반대쪽을 때렸고, x=130까지 미는 동안 몸통이 화면 오른쪽 밖으로 나가
  **팔만 남았다**(몸통이 프레임 왼쪽으로 가므로 반전하면 130에서도 남는다).

### I.2 고친 것

| # | 무엇 | 파일 |
|---|---|---|
| 1 | **주인공 공격 컷 좌우 반전** — `_make_origin_cut_sprite(..., flip)` + `_play_origin_cut_anim`이 공격 3종에 `flip=true`. 회피·자세·적은 그대로(원작 `flag=0`) | `src/battle/battle_presenter.gd` |
| 2 | **DWORM 빔을 시돌이 쪽(왼쪽)으로** — 원작 `:613`은 오른쪽(`i=-100..200`), `:607` 섬광은 (0,0) 고정이라 적이 오른쪽에 있는 구도에서 빔이 반대로 나가고 종마다 노즐과 어긋났다. 종별 `shot{dir,flip,muzzle}`을 메타에 굽고 그 노즐에 섬광을 맞춘다 | `tools/dev/bake_battle_sheets.py` · `battle_presenter.gd` |
| 3 | **볼트 조기 노출 제거** — 섬광 대기 0.3초 동안 볼트가 화면 왼쪽 끝에 미리 떠 있었다. 원작은 `:613` 루프에서 처음 그린다 | `battle_presenter.gd` |
| 4 | **적 공격 자세 홀드** — 시트 attack 행은 0.33초라, 빔이 나갈 때쯤 적이 **대치 자세로 돌아가** 노즐이 옮겨갔다(빔 어긋남의 진짜 원인). `play_anim(hold)` + `end_enemy_action()` | `battle_presenter.gd` · `battle_enemy_phase.gd` |
| 5 | **이중 배속 나눗셈 제거** — `enemy_attack_beat()`가 배속을 나눈 값을 `_cut_beat()`이 또 나눠, 배속 2배에서 적이 돌진 86% 지점에서 발사했다 | `battle_presenter.gd` |
| 6 | **방어·도구·도망 실패·마비 턴의 턴 마무리** — `_end_player_defend`가 `turn_count`를 안 올리고 `set_turn_text`도 안 해 배너가 적 턴 글자로 남고 턴 수가 안 올랐다(+턴 기력도 못 받음). `_open_player_turn()` 하나로 공유 | `src/battle/battle_scene_controller.gd` |

### I.3 검증 (실측)

- 캡처 도구로 눈으로 확인: 주먹은 적을 향해 찌르고 몸통이 화면에 남는다 ·
  DWORM 섬광이 노즐에 붙고 빔이 시돌이 쪽으로 날아간다 · 섬광 동안 볼트가 안 보인다.
- `godot --headless --path . --script tools/import_all.gd` → `done(stub) - 0 errors`
- `godot --headless --path . --script tools/validate.gd` → `done - 0 errors`
- `res://tests/smoke.tscn` PASS · `smoke_battle.tscn` PASS · `smoke_battle_input.tscn` PASS
- `assets/sprites/*_battle.json`에 `shot` 추가(mad_eye·vulgar·dworm·ozzy·o_ray).
  `iron_voc`·`hellcop`은 근접만이라 `shot` 없음(원작 `:601` 발사 종 아님).

### I.4 남긴 것 (다음 세션)

1. **마드아이 hurt 4번 프레임 반전** — 원작은 `:278`에서 e1 frame4만 `flag=1`로 그린다.
   리메이크 hurt 행은 [4,5]를 교대 재생하는데 프레임별 반전이 없다(2차원이라 행 단위
   flip으로는 안 됨). 영향은 마드아이 피격 1프레임뿐 — 우선순위 낮음.
2. **나머지 발사 종의 노즐 좌표 재확인** — `bake_battle_sheets.py`의 `SHOT_MUZZLE`은
   dworm만 손으로 잡았고(vulgar·ozzy·o_ray·mad_eye는 공격 프레임 내용 bbox 중심).
   실플레이에서 어긋나면 그 종의 노즐 좌표를 실측해 넣으면 된다(런타임 코드는 안 고친다).
3. **전투 턴 시스템** — `08_battle_rules.md`와 코드는 대체로 일치했다(기력 수입/소비·
   방어 반감·아이템 턴 소비·브레이크·강타·철벽·도망 확률 상승 모두 구현됨). 이번에
   찾은 건 I.2#6(턴 마무리 누락) 하나뿐이다. 미검토로 남긴 후보: 스킬 메뉴 피해 미리보기,
   상태이상 배지, 브레이크 게이지 상시 표시. 실플레이 피드백을 받아 정한다.
4. **임시 캡처·도구 정리** — `tools/dev/tmp_async_shots.gd`·`.tscn`과 `user://` 캡처,
   `%TEMP%\opencode\sidol_inspect`(합성 대조 PNG)는 **삭제했다**. `battle_anim_shots`와
   `battle_anim` `user://` 폴더는 원래 있던 도구라 남긴다(단 산출물은 임시다).

---

## J. 전투 후속 4건 + 전투 현대 RPG 감사 (2026-09-11)

> 계기: 유저 후속 — "연속 펀치에 양팔만 보이고 몸통이 사라진다"(재발),
> "DWorm 빔 위치 수정 반영 확인 + 턴제 수행 확인 + LOSE 보이스가 승리와 같은지",
> "전투가 현대 턴 RPG처럼 잘 구성됐는지(재미·긴장·연출)".

### J.1 원인 — flurry는 팔 오버레이라 몸통 없이 띄우면 팔만 남는다

I.1의 스윙 반전 수정과 다른 버그였다. `origin_player.png` row3(flurry) 실측:
col0은 몸통(좌 4042 + 우 5467px), **col1·col2는 팔 낱장**(각 ~3500px, 높이 48px).
`_origin_cut_flurry`가 1·2번만 교대하므로 몸통이 사라지고 팔만 남는다 —
"몇 번 시도하는데 가끔"인 것은 스킬 대형컷이 swing/flurry/rise 중 무작위라
flurry가 걸릴 때만 터지기 때문이다. 합성 대조(col0+col1/col2)하면 온전한 몸통+팔.
원작이 몸통 위에 팔을 얹어 그리던 자리다.

### J.2 고친 것

| # | 무엇 | 파일 |
|---|---|---|
| 1 | **flurry 합성** — 몸통 스프라이트는 col0 고정, 팔 오버레이 한 장을 같은 자리에 겹쳐 1·2번만 교대·동시 페이드·함께 해제 | `src/battle/battle_presenter.gd` |
| 2 | **볼트 반전 누락** — 혜성(`origin_bolt`)이 머리 오른쪽인 채 왼쪽으로 날아 거꾸로 갔다(섬광만 뒤집혀 있었다). `flip_h=true` + 발사점도 반전된 머리(`320−133=187`) 기준 | `battle_presenter.gd` |
| 3 | **승패 동음 해소** — 원본부터 `WIN=DEAD=DOMANG.VOC`(sha256 `c4f6af…` 동일)라 LOSE가 승리와 같은 소리였다. 원작 샘플은 고증으로 유지하고 결과별 징글(`RESULT_JINGLES` — 승 상승·패 하강·도망)을 겹친다 | `src/battle/battle_scene_controller.gd` |
| 4 | **DoT 틱 무표시** — `_tick_effects()`가 `tick_effects()` 반환을 버려 화상·부식이 조용히 깎였다. 숫자 팝 + `UI_BLOG_DOT_TICK` 로그 | `battle_scene_controller.gd` · `data/l10n/ui.csv` |
| 5 | **스킬 위력 표기** — 메뉴에 코스트·WEAK!만 있어 "쓸까 모을까" 근거가 반쪽이었다. `UI_BATTLE_SKILL_POWER`(power>0만) 꼬리표 | `src/ui/battle_ui.gd` · `ui.csv` |

DWorm 노즐 반영 확인: `dworm_battle.json` `shot.muzzle=[148,62]`가 적환(빨간 링)
실측 중심(148.49, 61.76)과 일치. 반전·종점 고정·볼트 숨김·이중 배속 제거도 코드에 있다.
턴제는 정상(교대+턴 공유 마무리, §I.2#6 이후) — `smoke_battle` 2턴째 공격 유효가 지킨다.

### J.3 검증 (실측)

- `validate` → `done - 0 errors` (신규 키 2건 양방향 대조 포함)
- `smoke.tscn` PASS · `smoke_battle.tscn` PASS · `smoke_battle_input.tscn` PASS ·
  `talk_convert --check` 정상
- `08_battle_rules.md` 갱신: §2 위력 표기 · §4 DoT 틱 표시 · §5 승패 징글 · §9 flurry 합성+볼트 반전

### J.3b 마비·턴 직관 피드백 (유저 질문 "마비·턴 변경이 눈에 보이는가")

> 점검 결과: 칩(종류+잔여턴)·배너(TURN N/적 턴)·로그·커맨드 개폐는 있다.
> 실제 구멍은 **적 마비가 걸려도 아무 일도 안 일어났다** — `has_paralysis()` 호출부가
> 아군 1곳뿐이라 아크 방전 칩만 뜨고 적은 계속 때렸다. 마비 스프라이트 표현도 없었다.

| # | 무엇 | 파일 |
|---|---|---|
| 6 | **적 마비 스킵** — 실전(`_resolve_turn`)에 `NUMB!` 팝+방전+로그, 계측(`enemy_turn`)에 `{"skipped":"paralysis"}`. 브레이크와 달리 모으기는 유지(카운터는 브레이크 자리) | `battle_scene_controller.gd` · `battle_controller.gd` |
| 7 | **마비 스프라이트 표현** — 아군 턴 상실 시 주인공에 방전 스파크(문구·로그만으론 "왜 쉬지"가 된다) | `battle_scene_controller.gd` |
| 8 | **지속 통일** — `skills.json` 마비 `turns: 3`→2. 3이면 적이 두 턴 연속 쉰다("정확히 한 턴" 위반, §7 관문 수학과도 어긋남) | `data/skills.json` · `data/l10n/ui.csv`(`UI_BLOG_ENEMY_PARALYZED`) |

턴 전환은 배너+로그+메뉴로 충분해 손대지 않았다. `08_battle_rules.md` §4 갱신.
검증: `validate` 0 errors · `smoke_battle` PASS(§7 마비 관문 포함) · `smoke_battle_input` PASS.

### J.4 남긴 것 (다음 세션)
1. I.4#1(마드아이 hurt 4번 반전)·I.4#2(나머지 종 노즐 실측)는 그대로 — 우선순위 낮음.
2. I.4#3 후보 중 스킬 미리보기 1건 해소(위력 표기). 상태이상 배지는 이미 있음(`StatusChips`),
   브레이크 게이지는 상시 표시 중(`_break_bars`) — 후보 소진.
3. 에셋 게이트(`player_battle`·대형컷 5종·보스 2종 대형시트)는 코드로 메울 게 아니라 의뢰 추적(`asset_status`) 유지.
4. **커밋** — §I 미커밋분 + §J 전부. 다음 세션은 미납품 에셋 입고 시 배선·실플레이 피드백 반영.

---

## K. 잔여 원작 대조 (2026-09-11)

### K.1 마드아이 hurt 반전 + 노즐 실측

I.4#1·I.4#2(§J.4#1)의 해소다. 둘 다 "원작 대조가 남긴 자리"라 한 묶음으로 했다.

**원작 근거** — `WARMODE.C:278` `EnemyAvoid()`:

```
if ( SprNum == 0 && sprnum == 4 ) RPut_Spr(i,0,&S[sprnum],1);
else  RPut_Spr(i,0,&S[sprnum],0);
```

마드아이(`SprNum 0` = e1)의 4번 프레임만 `flag=1`(좌우 반전)로 그린다. e1의 4·5번
프레임은 서로 반대를 향해 저장돼 있어 한 장을 뒤집어야 같은 방향이 된다.
리메이크 hurt 행은 원작 프레임 [4, 5]를 col0·col1에 이어 붙여 교대 재생하므로
**col0(=4번)만** 뒤집어야 한다. 행 단위 flip으로는 안 되는 2차원 자리다.

**hurt flip 구현** (`tools/dev/bake_battle_sheets.py` · `src/battle/battle_presenter.gd` ·
`assets/sprites/mad_eye_battle.json`):

- 베이커 상수 `HURT_FRAME_FLIP = {"mad_eye": [True, False]}`(`SHOT_MUZZLE` 근처).
  `bake()`가 적 시트 hurt 행 메타에 `"frame_flip"`을 싣는다(해당 종만 — 다른 종·다른 행은 없음).
- `mad_eye_battle.json` hurt 애니에 `"frame_flip": [true, false]` 손 추가(들여쓰기 1칸 유지,
  PNG 그대로). 베이크 출력(`json.dumps` indent=1)과 바이트 대조済 — 다시 구워도 diff 0.
- `play_anim()`이 메타 애니의 `frame_flip`을 `_anim_playing` 항목에 싣고,
  `_advance_anims()`가 항목에 비어 있지 않은 `frame_flip`이 있으면 표시 프레임 idx에 맞춰
  `spr.flip_h`를 갱신한다(`_apply_anim_frame_flip` 신설 — 루프/홀드/종료 경로와 충돌 없음).
- hurt는 `play_enemy_anim`이 flip을 안 건드리는 경로라 `_advance_anims`에서만 뒤집으면 된다.
  종료 시 flip 복원은 기존 `end_enemy_action` 담당(마드아이 hurt는 col1=false에서 끝나
  자연히 false로 닫힌다).

**노즐 실측** — 공격 프레임은 각 `*_battle.png`의 row 2(0-base) col 0
(셀 320×200 자리 `(0,400)-(320,600)`). PIL로 뽑아 `%TEMP%\opencode\`에 마커 포함 2배 크롭
(`nozzle_<종>_marked_2x.png` + 손끝·동공 줌 2종)을 저장하고 눈으로 검증했다.
좌표는 반전 전(저장 방향) 기준이다.

형태 대조 먼저: vulgar·ozzy·o_ray 공격 프레임은 **같은 그림**이다 —
원작 `E2·E4·E7 frame3 md5 `3606cf48…` 동일` + 베이크 시트 알파 마스크 md5
`492bf3ae…` 3종 동일(색상 변주만 다름). 그래서 3종은 같은 좌표를 쓴다.

| 종 | muzzle(반전 전) | 선정 근거 |
|---|---|---|
| mad_eye | [139, 79] | 동공(검은 구멍) 중심. 연결요소 분석: 동공 덩어리 362px(x128~148·y68~89) 중심 (138.54, 78.62) → 반올림. 윗눈꺼풀 외곽선(296px)은 제외. flip=false라 눈이 이미 왼쪽을 본다 |
| vulgar | [194, 61] | 내민 손 중지 끝. 손색(밝은 살색) 최우측 픽셀 (194,61~62). 붉은 화염 후광(최우측 x=208)은 몸이 아니라 제외 — dworm의 빨간 링 중심을 잡던 기준과 같은 자리 |
| ozzy | [194, 61] | vulgar와 바이트 동일 → 같은 좌표 |
| o_ray | [194, 61] | vulgar와 바이트 동일 → 같은 좌표 |
| dworm | [148, 62] | 기존값 유지. 빨간 링 중심 실측 (148.49, 61.76)과 일치 확인 |

폴백(bbox 중심)과 비교하면 mad_eye [127,102]→[139,79](몸통 중심에서 동공으로 12·23px 이동),
vulgar 계열 [127,101]→[194,61](몸통 중심에서 손끝으로 67·40px 이동) — 구 폴백이 빔을
몸통 한가운데서 쏘게 하던 어긋남이다. 런타임 코드는 손대지 않았다(좌표만 메타로).

**변경 파일** — `tools/dev/bake_battle_sheets.py`(`SHOT_MUZZLE` 4종 추가 + `HURT_FRAME_FLIP`
신설·`bake()` 배선) · `src/battle/battle_presenter.gd`(`play_anim` 싣기 +
`_apply_anim_frame_flip` 신설 + `_advance_anims` 호출 1줄, 주석 2줄) ·
`assets/sprites/{mad_eye,vulgar,ozzy,o_ray}_battle.json`(muzzle + mad_eye hurt `frame_flip`).
PNG·다른 종·다른 행은 그대로.

**검증 (실측)**:

- `gdformat --check src/battle/battle_presenter.gd` → `1 file would be left unchanged`
- `godot --headless --path . --script tools/validate.gd` → `done - 0 errors`
- `godot --headless --path . res://tests/smoke_battle.tscn` → `PASS`
  (`_tick_effects` string-formatting ERROR 3건은 J차 신규 키 3종이 stale `.translation`
  (09-10 빌드)에 걸린 것으로, 본 변경과 무관·테스트 PASS. 손대지 않았다.)
  → **정정(메인, 09-11)**: `--import`로 `.translation` 재빌드 후 ERROR 0건·PASS 확인.
  stale 번역이 `tr()`을 키 그대로 돌려 `%` 연산이 터지던 것이다. garc 무시 금지 —
  ERROR는 ERROR다.

### K.2 밸런스 재측정 (2026-09-11, 층당 200회)

- 결과: 전 층 평균턴 Δ≤0.1·연전 Δ≤0.5판·f4 승률 90→91.5(3전투분, 시행 노이즈).
  **§7 표 갱신 불필요** — "평타 연전 3~4판이면 위험" 그대로 성립.
- f0 특이 1건(에러 아님): 모으기 23회 중 발산 0회 — 3.2턴 단기전에 격파·브레이크로
  모으기가 소멸되는 구조적 결과. f1~f5 발산 정상.
- 실측 로그: `%TEMP%\opencode\battle_sim_200.txt`(2,479B).

### K.3 장식NPC 생동감 트릭 (2026-09-11, 유저 질문)

> 전제 정정: 고정 NPC는 이미 호흡·몸짓·둘러보기·배회·접근응시·프롬프트를 갖고 있다.
> 진짜 구멍은 (1) 외부 3인방(lost_orc·princess·f1 squire)이 말 걸리는 워커인데
> 개그 2줄+반복 1줄·무기능이라 존재감이 없고, (2) 스케일·회전은 리샘플 실측상
> 금지라(0.6667 배율) 정수 오프셋 외에 몸을 건드릴 수단이 없다는 것이다.

| # | 꼼수 | 파일 |
|---|---|---|
| 1 | **말풍선**(→K.5에서 `…`/`?`로 어휘 분리, 빨강 `!`는 괴물 전용 유지) — 첫 조우 1회 + 플래그로 새 대사가 생기면 1회(세션 한정 기록). UI 텍스트라 리샘플 없음 | `src/entities/emote_bubble.gd`(신설) · `scenes/field.gd` |
| 2 | **주목** — 3칸 안 NPC가 idle 중에 플레이어를 본다(look 타이머 갱신, 대화·배회 제외) | `npc_entity.gd` `notice()` · `field.gd` |
| 3 | **발먼지** — 배회 착지에 `step_landed` 시그널 → `FieldFx.step_puff` (무음 미끄럼이 유령처럼 보이던 자리) | `npc_entity.gd` · `field_fx.gd` · `field.gd` |

- 검증: `gdformat --check` 4파일 unchanged · `validate` 0 errors · `smoke_f1_events` PASS.
- 남긴 것: 외부 3인방에 깃발분기·힌트기능 부여는 시나리오 작업(대사+`sequence_variants`),
  말풍선 `?`·`...`는 호출 1줄이면 열리는 자리(`EmoteBubble.pop`).

### K.4 고정인물 대사 반복 (2026-09-11, 유저 질문)

> 원인 둘. (1) 동일 대사: 홍교수(@t48~51)≒남교수(@t54~57) 첫 4줄이 원작 TALK.TXT부터
> 복붙으로 같다 — 변환 버그가 아니라 원작 그대로. 남교수를 듣고 홍교수 심화갈래를
> 열면 같은 4줄이 또 나온다. (2) 단조 반복: 변형·반복풀이 없는 마커(21·26·75·78 등)는
> 매 방문 같은 전문을 재생한다(황교수 23줄 통암송이 대표).
> 처방: 원문 불변 유지 + 재방문만 1줄 리메이크 대사로. 체인-안전한 4곳만
> `repeat_after: 2` — 21→@c683·26→@c684·75→@c685·78→@c686(`dialogue.json` @c683~686 신설).
> 16(talk_hong_deep)·56(talk_howa_done)·71/77(보상 갈래)은 반복 갈래가 사슬을 깨서 제외.
> 주의: `talk_convert.py` 쓰기 모드는 `dialogue.json`을 @t만으로 덮어써 @c 283개를
> 날린다 — --check만 쓸 것.
> 검증: `validate` 0 errors(신규 키 대조 포함) · `smoke_f1_events` PASS.

### K.5 맵아트 최소 움직임 (2026-09-11, 유저 질문 "위치는 고수하고 타일만 교체")

> 확인: 지도는 ground/object/attr 3층, 인물은 object층 2×2 클러스터(obj 121~148).
> 위치 고정 + `TileMapLayer.set_cell` 실시간 교체가 된다. 데이터 파일은 안 건드린다
> (원본 바이트 일치 관문과 무관 — 교체는 런타임에만 산다).

| # | 무엇 | 상태 |
|---|---|---|
| 1 | **말풍선 어휘 분리** — 빨강 `!`는 괴물 위험 전용 유지, 대화는 `…`(첫 조우)+`?`(새 정보). 셀 앵커(`_emote_anchor`)로 맵아트 대화점(ATT)에도 띄운다 | 구현·PASS |
| 2 | **`MapTileAnimator`** — `data/maps/tile_anim.json` 표대로 오브젝트 타일 교대. 해시 위상, steady-state 난수 없음, 빈 표=no-op | 기반 구현·PASS(표 비어 있음) |
| 3 | 교대 아트(눈감은 머리 등 obj 셀) | 미납품 — `_wanted`에 발주 자리 기록 |

- `MapRenderer.swap_object_tile` — 그려진 층에만 얹는다(없는 층에 찍으면 허공).
- `TalkTargets.talk_count`·`branch_key` 신설(말풍선 판단용).
- 검증: `gdformat` unchanged · `validate` 0 errors · `smoke_f1_events` PASS.

### K.6 잡담 은행 (2026-09-11, 유저 질문 "대사 늘리기·인터넷·제네레이터")

> 결론: 인터넷 스크랩은 무리수(출처·저작권·톤 불명 + 오프라인 게임).
> 슬롯형 템플릿도 무리수에 가까움(한국어 조사 때문에 빈칸 채우기는 어미가 깨짐).
> **풀 회전형은 무리수 아님** — 완성문을 역할별로 묶어 count로 돌리면 문법이 안 깨지고,
> 파이프라인도 키 참조 그대로라 손댈 곳이 없다.

- `data/chatter.json` 신설(역할 3종·12줄: 교수 속담 5·학생 4·조교 3 — 자작+민속, @c687~698).
- `src/map/chatter_bank.gd` 신설 — `lines_for(역할, 횟수)` 2줄 회전(실측: prof/2→689·690, /3→690·691).
- `talk_targets.gd` 3순위 갈래: 반복 차례가 아니면 + 기본 갈래 + 2회차부터만. 변형·반복·플래그에 손대지 않음.
- `chatter_role` 13곳(16·21·26·31·36·41·44·46·47·71·75·77·78). 56 제외(1회차 후 기본 갈래에 영영 안 닿는 죽은 설정이 되므로).
- `validate` 잡담 참조 검사 추가(역할 풀이 가리키는 키가 dialogue.json에 있어야 함).
- 검증: `gdformat` unchanged · `validate` 0 errors · `talk_convert --check` 정상 ·
  `smoke_f1_events` PASS(ChatterBank 신규 class_name은 `--import`로 캐시 갱신 필요했음).
- NPC 액터(dialogue_sequences 2줄 풀) 확장은 미착수 — 데이터에 역할 키가 없어 같은 기구를 못 얹는다.

### K.7 NPC 반복키 잔여 (2026-09-11)

> 감사 스크립트 출력 오판 1건 정정: 반복키 없음 7명이라 했으나 grep·원본 대조 결과
> 진짜 없음은 `prof_chem` 1명뿐이었다(나머지는 키가 있고 시퀀스도 있다).
> 교훈: 감사 스크립트 출력은 원본 1건을 뜯어보기 전에는 결론이 아니다.

- `prof_chem`에 `prof_chem_repeat` 신설·배선(@c701, op 금지 — 스킬·플래그 중복 방지).
  덤으로 깃발 전 2회차 전문+op 재발사도 막힌다.
- 1줄 반복 6곳을 2연째와 교대: dev2(@c700)·orc(@c702)·princess(@c703)·squire(@c704)·
  vending(@c705)·exguard(@c706). tutor는 기존 2줄이라 손대지 않음.
- 작업 중 중복 키 2건(tutor_sample_repeat·f2_dev2_repeat)을 내가 만들었다가 즉시 제거 —
  추가 전 `count` 확인을 생략한 탓이다.
- 검증: 전수 대조(배치 참조 시퀀스 누락 0·신규 @c 전원 사용처 있음·고아 @c699 삭제) ·
  `validate` 0 errors · `smoke_f1_events` PASS.
