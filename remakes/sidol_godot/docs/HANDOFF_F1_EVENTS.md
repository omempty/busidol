# F1 정전·전자잠금 이벤트 마무리 — 세션 인수인계

> 작성: 2026-09-08, 18차가 워킹트리에 남긴 F1 이벤트 작업을 이어받은 후속 세션.
> **커밋하지 않았다.** 아래 변경은 전부 워킹트리에만 있다.
> 이 문서는 `docs/HANDOFF.md`와 별개다(그쪽은 유저가 동시에 쓰는 중).

---

## 0. 한 줄 요약

18차의 F1 정전/전자잠금은 **거의 다 배선돼 있었고 실제로 돌았다.** 미완성이던 것은
① 보관함 트리거 좌표가 문 바로 밑이라 조사가 불가능했던 것 하나뿐이고, Autoplay 관문을
빨갛게 만든 진짜 원인은 **17차가 넣은 F2/F3/F4 반복 함정 트리거의 진행 차단**이었다.
셋 다 고쳤고 관문은 **물리 초당이 정상(240)일 때 6/6층 도달로 초록**이다(3판 재현).

---

## 1. 진단 — 무엇이 미완성이었나

### 1-1. `f1_blackout_cache` 좌표가 문 바로 아래였다 (진짜 사문화)

- 데이터: `data/maps/triggers_f1.json` — `f1_blackout_cache`, `cells: [[30,35]]`(수정 전)
- 읽는 코드: `src/map/trigger_system.gd:try_interact()` → `scenes/field.gd:295` 부근

자료실 문은 `(30,32)`·`(31,32)` 두 칸(ATT 9)이고, 문 통과는 **3칸 점프**다
(`src/map/transition_gate.gd:_try_door`). 즉 방에 들어서면 착지가 `(30,33)`이고,
보관함 `(30,35)`을 조사하기 좋은 앵커도 `(30,33)`이다.

그런데 조사하려면 그 칸을 **앞에 둬야** 하고, 통행 가능한 칸이면 도구도 사람도
「한 칸 물러섰다가 그쪽으로 걸어와 서는」 동작을 한다. `(30,33)`에서 위로 물러서는 순간
`_try_door`의 위쪽 검사(`anchor.y - 1 = 32`)가 먼저 걸려 **문이 발동해 방 밖 `(30,30)`으로
3칸 튕겨 나간다.** 그 자리에서 아래를 보면 전방 2칸은 문(`30,32`·`31,32`)이라
`try_interact`가 `(30,35)`에 영영 닿지 않는다.

실측 증거(수정 전 주행 보고서):

```
## 밟았는데 아무 일도 없었다
| f1 | 트리거(interact) | f1_blackout_cache | (30, 35) |
```

`cell_probe`로 방 안을 재 보니 `26..34 × 33..38`이 전부 ATT 0이고 `(27,38)`도 설 수 있고
조사도 된다. 대사(`@c121` "구석에서 방탄조끼를 찾았다")대로 **방 구석**으로 옮겼다.

### 1-2. 반복 zone 트리거가 매 틱 발동 → 진행 차단 (관문을 빨갛게 만든 주범)

- 데이터: `data/maps/triggers_f2.json` `f2_spark_zap` / `triggers_f3.json` `f3_fog_choke`
  / `triggers_f4.json` `f4_volt_zap` — 셋 다 `"once": false`, `done_flag` 없음(17차 백로그 §1.2)
- 코드: `src/map/trigger_system.gd:tick()` zone 분기 (수정 전에는 `_in_zone`만 보고 바로 `_fire`)

발동하면 컷신이 조작을 통째로 쥔다(`scenes/field.gd:_physics_process`가
`cutscene_player.is_running()`에서 `return`). 그래서 **그 칸에서 한 걸음도 못 나가고**
컷신이 끝난 다음 틱에 또 맞는다 — 사람이든 도구든 영영 갇힌다.

실측(수정 전 주행): F2 스파크칸 `(36,9)`에 올라선 뒤 **190초 동안 40걸음**, 그 뒤 모든 목표가
「걷다가 막혔다 — (36,9) 부근에서 한 걸음이 나가지 않았다」로 실패하고 F3~F5에 못 갔다.

> 이건 18차 작업과 무관한 **기존(17차) 결함**이다. 다만 이걸 안 고치면
> F1 정전을 아무리 고쳐도 관문은 계속 빨갛다.

### 1-3. 정전 런타임 상태가 판을 넘어 산다

- 코드: `src/map/floor_lighting.gd:60` `static var _blackout := {}`

세이브에 안 싣기로 한 것은 의도가 맞는데(HANDOFF §3.25 ②) **아무도 지우지 않는다.**
정전 중에 한 판을 끝내고 새로 시작하면 다음 판 F1이 어두운 채로 서고, 그 판에는
`Q_F1_BLACKOUT`이 없어 분전반 트리거(`requires_flag`)가 열리지 않는다 → **끌 수 없는 정전**.

### 1-4. 곁가지 3건

| 무엇 | 어디 | 왜 |
|---|---|---|
| 프롤로그 대기에 손이 없다 | `tools/dev/autoplay.gd:autoplay_begin` | 드라이버 시계(`_watchdog`)는 `autoplay_begin` **뒤에** 돈다. 오프닝 6줄을 넘겨 줄 손이 없어 3000프레임 상한에 걸려 강제 종료 — 예산 240초 중 **24초가 첫 화면에서 증발**했다(보고서 「진행 정지 · f1 (9,9)」, (9,9)는 `field.gd:5 SPAWN_DEFAULT`) |
| 번개 섬광이 0×0 | `src/map/field_fx.gd:lightning_flash` | `set_anchors_preset`은 오프셋을 지금 크기(0×0)에 맞춰 남긴다 → 전체화면 앵커를 줘도 한 픽셀도 안 뜬다 |
| 주석 줄바꿈 합선 | `src/cutscene/cutscene_player.gd:13` | 18차가 냈다고 자백한 것과 같은 종류가 하나 더 남아 있었다 |

### 1-5. 진단해 보니 **멀쩡했던 것들**(오해 방지)

- `blackout` op 배선(`cutscene_player` → `field.set_blackout` → `FloorLighting`/`FogOfWar`) — 정상.
- `locks_f1.json` → `TransitionGate._load_locks/_door_locked/eject_cell_for` — 정상.
  정전 중 문 통과 `(30,30)→(30,33)`이 주행에서 실제로 일어났다.
- `f1_blackout_sopo`/`f1_blackout_gas` OR 쌍, `f1_power` 분전반(190,26), 배터리 퍼즐 —
  전부 실제 주행에서 발동했다(`Q_F1_BLACKOUT +40`, `Q_F1_POWER +60` 보너스 로그 확인).
- `minigame_battery` op은 이미 구현돼 있었고 autoplay 파일럿도 손이 있다.

---

## 2. 고친 것 (워킹트리에만, 커밋 없음)

이번 세션이 만진 파일 (18차가 남긴 것 위에 얹었다):

| 파일 | 무엇을 | 왜 |
|---|---|---|
| `data/maps/triggers_f1.json` | `f1_blackout_cache` cells `(30,35)` → **`(27,38)`** + `_comment`에 사유 | 1-1. 문 바로 밑은 조사 앵커가 문 판정에 먹힌다 |
| `src/map/trigger_system.gd` | `INVALID_CELL`(:32) · `_fired_cell`(:38) 도입, `tick()` zone 분기(:76~82)를 **「앵커가 바뀌었을 때만 재발동」**으로. `_rearmed`/`cooldown_sec`는 폐기 | 1-2. 움직이려면 조작권이 있어야 하므로 배속과 무관하게 탈출이 보장된다 |
| `src/map/floor_lighting.gd` | `clear_blackout()` 신설(:85) | 1-3 |
| `src/autoload/game_state.gd` | `reset()`에서 `FloorLighting.clear_blackout()`(:284) | 새 게임 대칭 |
| `src/autoload/save_manager.gd` | `load_slot()`에서 같은 호출(:161) | 불러오기 대칭 |
| `src/map/field_fx.gd` | `set_anchors_preset` → `set_anchors_and_offsets_preset`(:43), `for i` → `for _i` | 1-4 |
| `src/cutscene/cutscene_player.gd` | 머리 주석 줄바꿈 복구(:13) | 1-4 |
| `tools/dev/autoplay.gd` | `_settle_boot()` 신설(:644)·`autoplay_begin`에서 사용(:205) | 1-4. 프롤로그를 눌러 넘긴다 |
| `tools/validate.gd` | `_validate_map_locks()`(:237~) 신설 + 호출(:55), 트리거 `cooldown_sec` 금지(:227) | 새 데이터 계약에 프루브를 같이 넣는 저장소 관례 |
| `docs/HANDOFF.md` | §3.25에 「⑤ 마무리」 절 + §2.7에 7·8행 추가 | **주의: 유저가 동시에 쓰는 파일이라고 나중에 통보받았다.** 내 삽입은 바이트 단위(append)라 기존 내용은 안 지웠고 397행 CR CR LF도 보존했다(`git diff --stat` 129줄). 필요 없으면 그 부분만 지우면 된다 |

18차가 남긴 파일들(`locks_f1.json`, `f1_blackout/f1_power/f1_cache.json`,
`transition_gate.gd`, `floor_lighting.gd`, `fog_of_war.gd`, `scenes/field.gd`,
`quests_v2/growth/dialogue*/npcs_f1/walkers_f1`)은 **지우지 않고 그대로 살렸다.**

### 새 프루브의 음성 시험 (판별력 확인)

일부러 깨뜨려 3건 전부 빨개지는 것을 확인한 뒤 되돌렸다(사본으로 복원, `git checkout` 안 씀):

```
ERROR: [validate] triggers_f2.json/f2_spark_zap 반복 zone인데 cooldown_sec<=0 — 매 틱 발동은 진행 차단
ERROR: [validate] maps/locks_f1.json/f1_elec_lock door 두 칸이 가로로 안 붙었다: (30, 32) (30, 33)
ERROR: [validate] maps/locks_f1.json/f1_elec_lock exit가 interior 안이다 — 갇힘 탈출이 제자리걸음이 된다
[validate] done - 3 errors
```

(첫 줄의 `cooldown_sec` 검사는 그 뒤 설계를 바꾸면서 **「사문화 키가 적혀 있으면 실패」**로
성격이 바뀌었다. 지금 코드에 남은 것은 후자다.)

---

## 3. 관문 실측

### 3-1. Autoplay — 전/후 (같은 명령, 같은 인자)

```
godot --headless --path . res://tools/dev/autoplay.tscn -- \
      --seconds 240 --goals 150 --require-floors 5 --out user://autoplay_gate.md
```

**전 (수정 전, 18차가 남긴 상태 그대로):**

```
=== 자동 주행 끝: 예산 소진 (250초) ===
경과 249.6초 / 걸음 초당 11.3
프레임 30498(초당 122) / 물리 59908(초당 240) / 배율 120(최저 6.00) / 틱 240
걸음당 물리 21.2 = 걸음대기 2.5 + 정지대기 0.1 + 나머지 18.6
걸음 2832 / 층 3 / 전투 20 / 상자 54 / 대사 4 / 사망복구 0
ERROR: [autoplay] 걸어서 닿은 층 3 < 요구 5 — 층 전환이 막혔다
```

같은 보고서의 결정적 두 줄:

```
| 2 | f2_spark_zap@37,9 | 트리거(zone) | 걷다가 막혔다 — (36, 9) 부근에서 한 걸음이 나가지 않았다
| f1 | 트리거(interact) | f1_blackout_cache | (30, 35)      ← 밟았는데 아무 일도 없었다
```

**후 (5판 연속 측정):**

| 판 | 물리 초당 | 걸음 | 걸음 초당 | 닿은 층 | 판정 |
|---|---|---|---|---|---|
| #1 | 240 | 6606 | 42.9 | **6 / 6** | PASS (목표 150 완수, 153.9초) |
| #2 | 32 | 1728 | 7.2 | 2 / 6 | FAIL — 속도 |
| #3 | 72 | 2895 | 12.1 | 2 / 6 | FAIL — 속도 |
| #4 | 240 | 7223 | 42.6 | **6 / 6** | PASS (목표 150 완수, 169.5초) |
| #5 | 236 | 6918 | 33.7 | **6 / 6** | PASS (목표 150 완수, 205.0초) |

초록 판 원문(#1):

```
=== 자동 주행 끝: 예산 소진 (목표 150개) ===
경과 153.9초 / 걸음 초당 42.9
프레임 14672(초당 95) / 물리 36935(초당 240) / 배율 120(최저 6.00) / 틱 240
걸음 6606 / 층 6 / 전투 58 / 상자 104 / 대사 7 / 사망복구 0
```

```
## 닿지 못한 구역
없음 — 전부 닿았다.

## 닿은 구역과 들어간 경위
| 0 | 계단 stairs_east_down |
| 1 | 주행 시작 |
| 2 | 계단 stairs_center_up_f1 |
| 3 | 계단 stairs_center_up_f2 |
| 4 | 계단 stairs_center_up_f3 |
| 5 | 계단 stairs_center_up_f4 |
```

정전 사슬이 실제로 도는 것도 같은 보고서에서 확인된다(다른 판, 정전 중에 자료실을 먼저 들른 순서):

```
| 1 | f1_gas@12,32              | 트리거(zone)     | f1_gas |
| 1 | f1_blackout_cache@27,38   | 트리거(interact) | f1_blackout_cache |   ← 이제 발동한다
| 1 | f1_sopo@163,18            | 트리거(zone)     | f1_sopo |
| 1 | f1_power@190,26           | 트리거(interact) | f1_power |
| 1 | f1_blast@100,63           | 트리거(interact) | f1_blast |
| 1 | stairs_center_up_f1       | 계단             | f1 → f2 |
```

### 3-2. 개별 관문

```
[validate] done - 0 errors
[check_scripts] done broken=0
[world_audit] done - FAIL 0 / WARN 4
```

f2 층 훑기(`autoplay_sweep --floors 2`)도 돌렸다 — 스파크칸을 지나고도
「막힌 자리」 0건, 걸음 1731 / 전투 14 / 상자 33으로 완주했다(수정 전에는 여기서 갇혔다).

### 3-3. 전체 관문 스위트 — **완주 못 했다**

```
powershell -File tools/dev/run_gates.ps1 -Godot <godot>
```

```
[1/23] Import...        …  [18/23] World audit...
[world_audit] done - FAIL 0 / WARN 4
[19/23] Autoplay...
=== 자동 주행 끝: 예산 소진 (240초) ===
경과 240.0초 / 걸음 초당 7.4
프레임 2310(초당 10) / 물리 11536(초당 48) / 배율 120(최저 6.00) / 틱 240
걸음 1783 / 층 2 / 전투 17 / 상자 45 / 대사 3 / 사망복구 0
*** FAIL *** Autoplay (exit 1)
```

**1~18단계는 전부 통과**했고 19단계 Autoplay에서 멈췄다 — 물리 초당 48(정상 240)인
느린 판이었다. 스위트가 거기서 종료돼 **20~23단계(export-pack·원본 대조·SPR 알파·sheet_ops)는
안 돌았다.** 다음 세션이 반드시 다시 돌려야 한다.

---

## 4. 아직 안 끝난 것 (다음 세션이 이어받을 순서)

1. **전체 관문 스위트 재실행.** 20~23단계가 한 번도 안 돌았다.
   `tools/convert/sheet_ops.py`/`test_sheet_ops.py`는 유저가 동시에 편집 중이라
   23단계가 그 영향으로 빨갈 수 있다 — 유저 작업이 끝난 뒤 돌릴 것.
2. **Autoplay를 「물리 초당 240」인 판에서 한 번 더 확인**해 스위트 전체 초록을 실측으로 남길 것.
   (240이 아니면 코드 문제가 아니다 — §5 참조.)
3. `gdformat --check` — 이번 세션은 **새 .gd 파일을 만들지 않았고** 기존 파일만 편집했다.
   그래도 커밋 전에 한 번 돌리는 것이 저장소 관례다(`gdformat` 미설치라 못 돌렸다).
4. **`f4_cache` 사문화** — 주행 보고서에 「밟았는데 아무 일도 없었다 · f4 (145,50)」이
   세 판 연속 나온다. 18차/이번 작업과 무관한 기존 결함. 손대지 않았다.
5. `docs/03_plan/03_content_backlog.md` §1.3의 "world_audit 정전 프루브"는 여전히 미착수.
6. `docs/HANDOFF.md`에 넣은 「⑤ 마무리」 절이 유저 편집과 겹치는지 확인(§2 표 마지막 줄 참고).

---

## 5. 확신 없는 것 / 함정 (여기서 헤맸다)

### 5-1. 첫 진단은 틀렸다 — "F1 잠금이 길을 막았다"가 아니다

의뢰문의 가설(전자잠금이 위층 길을 막는다)은 **틀렸다.** 잠금은 본선과 무관한 방(R63)
하나이고 실제로 잘 돌았다. 관문을 빨갛게 한 것은 **F2 스파크 함정**이었다.
보고서의 「막힌 자리」 표에 같은 좌표 `(36,9)`가 40줄 반복된 것이 결정적 단서였다 —
**증상 좌표가 한 곳으로 수렴하면 그 자리가 범인이다.**

### 5-2. 초 단위 쿨다운은 배속에서 무너진다 (한 번 틀렸다)

처음엔 `cooldown_sec` 1.0초 재무장으로 고쳤고 validate 프루브까지 붙였는데
**주행은 그대로 갇혔다.** 이유: 주행은 `Engine.time_scale=120`이고 컷신 중에는
`triggers.tick`이 아예 안 불린다(field가 `is_running()`에서 return). 그래서 쿨다운이 재는
「자유 시간」 1초는 물리 두 틱(스케일 델타 0.5초/틱)뿐이고, 도구가 키를 누를 프레임이
오기 전에 재무장이 끝난다. **시간으로 재면 배속에 따라 안전선이 흔들린다.**
지금 코드는 「앵커가 바뀌었는가」로 잰다 — 움직이려면 조작권이 필요하므로 배속 불변이다.

### 5-3. 빨간 Autoplay를 코드 탓하기 전에 「물리 초당」을 볼 것

같은 코드로 240 / 236 / 72 / 48 / 32가 다 나왔다. 240인 판은 전부 6층 초록,
그 아래는 전부 2층 빨강 — **완전 상관**이다. 그리고 이번엔 CPU 부하가 아니었다:
느린 판에서도 Godot은 코어 하나의 14%밖에 안 썼고 전체 CPU는 5~8%였다
(`Get-Counter '\Processor(_Total)\% Processor Time'` 실측). 즉 **CPU가 아니라 입출력/스케줄링**
쪽에서 잠자고 있었다. 같은 워킹트리에서 다른 세션이 이미지 작업을 하고 있었다.
원인을 끝까지 못 짚었다 — **이건 확신 없는 부분이다.**

### 5-4. 주행은 `Q_F1_START`(dworm 첫 승리)에 걸려 판마다 흔들린다

`data/monsters.json` f1 로스터 5종 중 dworm을 **이겨야** 튜토리얼 게이트가 열린다.
한 판(측정 #2 계열)은 f1에서 1100걸음을 걷고도 dworm 승리를 못 얻어 f1에 갇혔다.
막힌 것이 아니라 **확률**이다. 예산이 넉넉하면(=물리 240) 문제되지 않았다.

### 5-5. `f2_spark_zap`이 보고서의 「밟았는데 아무 일도 없었다」에 남는다

고친 뒤에도 남는다. 이건 결함이 아니라 **겹침 아티팩트**다 — `f2_spark_warn`과
`f2_spark_zap`이 같은 칸을 쓰므로, 도구가 warn 목표로 그 칸에 선 사이 zap이 이미
발동해 버리고, 그 다음 zap 목표를 「밟았을」 때는 앵커가 그대로라 재발동하지 않는다.
관문 판정에는 영향 없다(보고서 내용으로는 실패시키지 않는다).

### 5-6. 손대지 않은 것

- `tools/review/**`, `tools/convert/sheet_ops.py`, `tools/convert/test_sheet_ops.py` — 유저 작업 중.
- `tools/lib/autoplay_driver.gd`(공용 뼈대) — 고치고 싶은 자리가 있었지만
  (목표가 다 소진되면 비싼 BFS를 재실행하며 헛돈다) 공용이라 손대지 않고
  어댑터(`autoplay.gd`) 쪽으로만 고쳤다.
- `data/maps/triggers_f2/f3/f4.json` — 반복 함정의 `_comment`가 "매 틱 맞는다"로 남아 있지만
  규칙을 코드(`trigger_system.gd`)로 옮겼으므로 데이터는 안 건드렸다.
