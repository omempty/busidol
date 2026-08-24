# 에셋 뷰어 (assets/gen/viewers)

자체완결 단일 HTML(base64 내장) — 더블클릭으로 열람, 서버 불필요.

| 파일 | 용도 |
|---|---|
| `character_bible.html` | 캐릭터·포트레이트 바이블 열람(48매 내장) |
| `tile_viewer.html` | 타일셋 구성·멀티타일 커버리지 확인 |
| `retouch_compare.html` | **원본 vs 리터치 A/B 비교** ← Phase 8 시범 리뷰용 |
| `samples/` | 리터칭 쌍 PNG + 소스 무결성 베이스라인(SOURCES.sha256) |

## 리터칭 파이프라인 (retouch_compare 입력)

```
python tools/convert/sprite_retouch.py      # 원본 무결성 검증 후 samples/ 생성
python tools/convert/gen_compare_viewer.py  # samples -> retouch_compare.html 재생성
```

- 스타일 바이블 준수: 마스터 팔레트 잠금 / 5단 명암 밴딩 / 남보라 색조 그림자 /
  남색 1px 아웃라인 / 지오메트리 무변경
- 원본 보호: originals_ref 는 읽기 전용, SHA256 베이스라인 대조 실패 시 실행 중단.
  복원: `git checkout -- remakes/sidol_godot/assets/originals_ref`

## 기존 뷰어 개선 검토 (2026-08-24)

| 뷰어 | 상태 | 개선 필요 |
|---|---|---|
| character_bible | 양호 — 캐릭터별 포트레이트/토큰 열람 | 확대 컨트롤 없음, A/B 비교 없음 |
| tile_viewer | 양호 — 타일 호버 좌표·커버리지 표시 | 동일 |
| (공통) | 단일파일 규약 유지 | **재생성 스크립트 부재** — 수동 수정 이력이라 재현 불가. 신규 뷰어(retouch_compare)부터 제너레이터 방식으로 전환, 기존 2종도 다음 갱신 시 제너레이터화 권장 |

리터칭 채택/반려 판정은 본 페이지 리뷰 후 `assets/gen/report_*.md` 형식으로 기록.
채택 시에만 메인 개발 측이 `res://assets/sprites/` 로 패킹한다(경계 규칙).
