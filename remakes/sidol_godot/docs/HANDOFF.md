# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-25 · Phase 8 진행 중(오디오 인프라+리터칭 시범) · 세션 종료 시점

## 1. 현재 상태 한 줄 요약

Phase 0~7 완료 + **Phase 8 부분 완료**(AudioManager 실구현·버스, Validator 오디오/
스펙 검사, DOSBox 포터블화). **스프라이트 시범 리터칭 진행 중 — 미해결 이슈 1건**
(아래 §3 최상단).

## 2. 다음 세션 첫 명령

```bash
# 리뷰 뷰어 (유저 리뷰 대기 중)
start remakes\sidol_godot\assets\gen\viewers\character_bible.html
start remakes\sidol_godot\assets\gen\viewers\retouch_compare.html

# 검증 관문 6단계
remakes\sidol_godot\검증실행.bat
```

## 3. ⚠️ 최우선 미해결: 리터치 투명 영역이 캐릭터에 침범

**현상**: 리터치본에서 캐릭터 내부(눈·입·몸통 틈)가 투명하게 뚫려 보임.
**확인된 사실**(진단 완료):
- e1 프레임: 경계 100% 순수 검정(0,0,0), 검정 58,070px 중 57,747px가 배경 제거됨,
  밀폐 잔존 불과 323px -> 스프라이트 내부 검정이 배경과 실제로 연결되어 있음.
- 원작 엔진이 색상 0=투명 취급이라 이미지 자체에는 정답 마스크가 없음.
- 적용한 완화(불충분): 밀폐 컴포넌트 복원 + 반경2/75% 핀홀 봉합 (`heal_pinholes`).
**다음 세션 후보 해법 (순서대로 검토 권장)**:
1. **원본 코드에서 blit 방식 확인** — originals/1995_sidol_bsd_dos 의 스프라이트
   드로잉 루틴(XOR? mask plane? 색0 스킵?)을 확인하면 정답 마스크 규칙이 나옴.
   원작도 색0 스킵이면 게임 화면에서도 해당 부위는 뚫려 보였던 것이므로
   **리터치가 아니라 원작 그대로가 정답**일 수 있음(유저 판정 필요).
2. **최대 배경 컴포넌트만 제거**: border flood를 "가장 큰 컴포넌트 1개"로 제한해
   나머지 검정은 불투명 유지.
3. **수동 마스크 툴**: 뷰어에 붓으로 투명/불투명 지정 → JSON 저장(소규모라 현실적).
4. 장기: 리터치는 참조용으로 두고 캐릭터는 AI 재생성 파이프라인(spec 계약)으로.

## 4. Phase 8 남은 작업

| 순서 | 작업 | 상태 |
|---|---|---|
| 0 | 위 리터치 투명 이슈 해결 + 유저 리뷰 채택/반려 | **미해결** |
| 1 | BGM/SFX 실제 파일 생성(AI) -> assets/audio/ 에 배치 | 스펙 21종 준비됨 |
| 2 | AudioManager LUFS/루프 품질 검수 | 코드 준비됨 |
| 3 | 도트/타일 AI 생성 배치(spec->Validator 게이트->패킹) | 스펙 존재 |
| 4 | portraits/keyart 배치 | 스펙 존재 |

### P7~P8에서 완결된 플레이 흐름 (검증용 체인)

```
F1 진입 → opening(@c101~106) → [시나리오] → F2 HP실(q_f2_hp_gate)→크레딧룸
F3 퀴즈맨(q_f3_quiz_gate)→quiz_paline→퀴즈→팰린→craft→해독제(Q_F3_CURE_DONE)
F4 회로(q_f4_battery_gate)→battery_puzzle→10,000V(Q_F4_BATTERY)
F5 보스(q_f5_boss_gate)→SYS_BUILDER 결전→승리(q_f5_ai_battle_won)
→ epilogue(@c601~605)→크레딧룸 엔딩(Q_ENDING)
```
※ 중간 게이트 플래그(q_*_gate)는 아직 수동/이벤트 미연결 — Phase 9 시나리오 반영 시 채움.

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리가 포팅 재활용 단위다 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 | bombman94/95 에서 |
|---|---|---|
| **공용 프레임워크** | `src/battle`(BattleController/DamageCalculator/ChoreographyRunner/BattlePresenter/BattleUI), `src/cutscene`, `src/map/trigger_system.gd`, `src/ui`(DialogueBox/QuizMinigame/BatteryCircuit), `_shared` 도구+schemas | **그대로 이식** |
| **게임 데이터** | `data/**` | 전면 교체(원작 변환기만 작성) |
| **게임 전용 로직** | field/battle/credit_room 조립, 성장, 보스 하이브리드 | 부분 재작성 |

### 구현 노트 (P8 세션 추가)

- **리터칭 파이프라인**(`tools/convert/sprite_retouch.py`): 소스 SHA256 베이스라인
  무결성 게이트(originals_ref 987파일, 위반 시 중단+복원 안내) / 원본 자체 팔레트 스냅 /
  5단 명암+남보라 색조 그림자 / 남색 아웃라인 / heal_pinholes(불충분, §3 참고).
- **⚠️ palette_master.json 함정**: DEFAULT.PAL 기본 VGA DAC(raw768, 6비트) 그대로라
  처음 16색=EGA색, 나머지=어두운 램프. 여기로 스냅하면 EGA풍 붕괴(실제 발생).
  또 6비트 값이라 8비트 변환(×255//63) 없이 쓰면 거의 검정. 소비부 주의 or
  8비트 변환본(palette_master_rgb.json) 별도 생성 권장.
- **뷰어**: character_bible.html 하단에 리터치 비교 섹션 주입(마커 블록, 재실행 안전),
  retouch_compare.html = A/B·나란히·스와이프·배경토글. 모두 제너레이터로 재생성
  (`tools/convert/gen_compare_viewer.py`, `gen_character_retouch.py`).
- **Validator 확장**: 오디오 ID 교차검증(cutscenes sfx/bgm op, battle_moves audio),
  minigames 구조 검사, change_scene 경로, sprite spec(kind 분기). 현재 0오류.
- **AudioManager 실구현**: Master/BGM/SFX/Voice 버스(default_bus_layout.tres 신설),
  assets/audio/<kind>/<id>.ogg|wav 규약, 시맨틱 루프, SFX 풀, 부재 시 스킵.
  필드 bgm_field / 전투 bgm_boss(boss 구분) / 인카운터·상자 SFX 배선 완료.
- **DOSBox**: run_sidol.bat 절대경로 제거(레포 상대 경로 conf 생성),
  캡처는 assets/raw/dosbox_capture(gitignored).

## 4. 알려진 미해결

| ID | 내용 | 우선순위 |
|---|---|---|
| B1 | 빈 폴더 `BSD 시돌이의 모험\` 껍데기 삭제 (세션 CWD 잠김) | 낮음 |
| B2 | gdformat/pre-commit 설정 파일 미생성 | 낮음 |
| B3 | DialogueBox 스킵 시 visible_characters 음수 방지 | 낮음 |

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
