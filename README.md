# 부싯돌 컬렉션 (busidol)

> 1995년 대구대 전산과 게임동아리 **부싯돌**의 DOS 게임 원본 보존소 + Godot 리메이크 워크스페이스.
> 레이아웃 확정: 2026-08-24 (MANIFEST.sha256 해시 검증 완료)

## 구조

```
부싯돌시절\
├── _shared\      dosport 공용 패키지(johab/PCX/VOC/SPR) + 스키마 + 템플릿
├── originals\    ★원본 보존区 — 수정 금지 (MANIFEST.sha256 무결성)
│   ├── 1994_bombman_dos\      BOMB (BombMan '94)
│   ├── 1995_bombman_dos\      BOMB95 (BombMan '95)
│   └── 1995_sidol_bsd_dos\    BSD 시돌이의 모험
├── remakes\
│   └── sidol_godot\           ★진행 중 — Godot 4.x 리메이크
├── 게임실행.bat / 검증실행.bat / 에디터실행.bat
└── README.md
```

## 규칙

1. **originals/**: 읽기전용 — MANIFEST.sha256과 불일치 시 훼손
2. **경로**: 기계 경로 ASCII, 한국어 원명은 매니페스트 헤더가 공식 기록
3. **공용 vs 전용**: 포맷 도구(johab/PCX/VOC/PAL) → `_shared`, 프로젝트 변환기 → `remakes/*/tools/`
4. **새 포팅**: `_shared/templates/` 스캐폴드 → `remakes/<id>_godot` 생성

## 현재 진행

| 프로젝트 | 상태 | 상세 |
|---|---|---|
| **sidol_godot** | Phase 0~5 완료 · Phase 6~9 진행 중 | [문서](remakes/sidol_godot/docs/README.md) |
| bombman94_godot | 대기 | sidol 파이프라인 재사용 |
| bombman95_godot | 대기 | 〃 |

## sidol_godot 구현 상태

| 시스템 | 파일 | 상태 |
|---|---|---|
| 맵 로딩·렌더(원작 도트) | MapRenderer + tiles_original_32.png | ✅ |
| 그리드 이동·충돌(2×2 발판) | GridMover + PlayerEntity(원작 I.SPR 도트) | ✅ |
| 층 전환(F1↔…↔F0↔F5) | TransitionGate + transitions.json | ✅ |
| 문 통과(ATT==9 mapy±3) | TransitionGate._try_door | ✅ |
| 미니맵(M키 토글) | MinimapLayer | ✅ |
| NPC 배치·대화창(@t/@c 조회) | NpcEntity + DialogueBox + Database | ✅ |
| 몬스터 AI(BFS 추적+배회+분산) | AIBrain/WanderAI/ChaseAI/EnemyManager | ✅ |
| 인카운터→전투 씬 전환 | field.gd → BattleSceneController | ✅ |
| 전투 커맨드(공격/기술/방어/도망) | BattleSceneController | ✅ |
| 데미지 계산(속성 약점 ×1.5) | DamageCalculator | ✅ |
| 스킬 6종(SkillDef) | data/skills.json | ✅ |
| 상태이상(DoT/버프/마비) | StatusEffectDef + Combatant.tick_effects | ✅ |
| 인벤토리(add/remove/count) | Inventory + items.json 63종 | ✅ |
| 상점 UI | ShopUI(구매→소지금 차감→Inventory.add) | ✅ |
| 회피 페이즈(탄막 10패턴) | DodgePhase | ✅ 작성 |
| 크레딧룸 | credit_room.tscn/gd | ✅ 골격 |
| 난이도 상/중/하 | growth.json difficulty_presets | ✅ |

## 빠른 시작

```
게임실행.bat       더블클릭 → 필드에서 걷기·전투·대화 플레이
검증실행.bat       더블클릭 → import+validate+smoke 자동 검증
에디터실행.bat     Godot 에디터 열기
```
