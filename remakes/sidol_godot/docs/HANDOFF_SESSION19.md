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
