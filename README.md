# 부싯돌 컬렉션 (부싯돌시절)

> 1995년 대구대 전산과 게임동아리 **부싯돌**의 DOS 게임 원본 보존소 + Godot 리메이크 워크스페이스.
> 레이아웃 확정일: 2026-08-24 (원본 이동은 MANIFEST.sha256으로 해시 검증 완료)

## 구조

```
부싯돌시절\
├── _shared\      공용 도구·스키마·템플릿 (모든 리메이크 재사용)   ← Phase 0에서 채움
├── originals\    ★원본 보존区 — 내용 수정 영구 금지 (MANIFEST.sha256 참조)
│   ├── 1994_bombman_dos\      원명: BOMB     (BombMan '94)
│   ├── 1995_bombman_dos\      원명: BOMB95   (BombMan '95)
│   └── 1995_sidol_bsd_dos\    원명: BSD 시돌이의 모험
├── remakes\
│   └── sidol_godot\           진행 중 — docs\(설계문서) 참조
└── README.md                 이 파일
```

## 규칙

1. **originals/**: 읽기전용. 각 폴더의 `MANIFEST.sha256`과 해시가 다르면 훼손된 것.
2. **기계 경로는 ASCII**, 한국어 원명은 위 대조표와 각 매니페스트 헤더가 공식 기록.
3. **공용 vs 전용**: 포맷 수준 도구(johab/PCX/VOC/PAL/SPR probe/Validator/Schema)는 `_shared`,
   프로젝트 데이터 구조 의존 변환기는 각 remake의 `tools/`.
4. **새 포팅 절차**: `_shared/templates/` 스캐폴드 → `remakes/<id>_godot` 생성 → docs 작성 → Phase 0.

## 현재 진행

| 프로젝트 | 상태 |
|---|---|
| sidol_godot | 설계 완료(docs 18종) — Phase 0 대기 (`remakes/sidol_godot/docs/03_plan/01_roadmap.md`) |
| bombman94 / bombman95 | 대기 (sidol 포팅에서 검증된 파이프라인 재사용) |

> 비고: 빈 폴더 `BSD 시돌이의 모험\`(원본 이동 후 껍데기)는 세션 종료 후 삭제하면 됨 —
> 세션 호스트 프로세스의 작업 디렉터리로 잠겨 있어 지금은 제거 불가.
