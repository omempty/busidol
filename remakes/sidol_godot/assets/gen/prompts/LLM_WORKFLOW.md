# LLM 스프라이트 워크플로우 (임시 작업 폴더 계약)

> 이 폴더(assets/raw/llm/)는 gitignored 임시 작업区다. 버전 관리 대상은
> 최종 채택 후 `res://assets/sprites/` 로 패킹된 것만.

## 시나리오

```
[1] 추출   tools/convert/extract_sprites.py
           originals_ref/bmp_spr (935프레임) -> 00_reference/
           (배경 제거 투명 PNG 프레임 단위 + 그룹별 컨택트 시트)

[2] 의뢰   00_reference/ 이미지 + gen/prompts/*_prompt.md 를 그래픽 LLM에 첨부
           -> 신규/리터치 시트 수신

[3] 납품   받은 파일을 그대로 10_submitted/ 에 저장 (파일명 규약: <캐릭터>_v<n>.png)

[4] 재가공 tools/convert/process_llm_sheet.py 10_submitted/<파일>
           마젠타 키잉 -> 스펙 그리드 컷팅 -> 프레임 검출 -> 검증
           -> 20_processed/<캐릭터>/ (프레임 PNG + 시트 + 리포트)

[5] 패킹   유저 리뷰 채택 시 메인 개발이 30_packed/ 경유로
           res://assets/sprites/<캐릭터>.png + <캐릭터>.json (cell_w/cell_h/scale/애니 메타) 배포
```

## 폴더

| 폴더 | 내용 | 비고 |
|---|---|---|
| `00_reference/` | 원작 추출본(투명 PNG + 컨택트 시트) | LLM 첨부용, 언제든 재생성 |
| `10_submitted/` | LLM 납품 원본(마젠타 배경) | 손대지 않고 보관 |
| `20_processed/` | 키잉·컷팅·검증 완료 프레임 | 뷰어 검수 대상 |
| `30_packed/` | 게임 반입 준비 완료 | 채택분만 |

## 규칙

- 납품 검증(validate_retouch_sheet 또는 process_llm_sheet 내장 검사) 미통과분은
  20_processed 로 넘어가지 않는다.
- 30_packed -> res://assets 복사는 메인 개발(에이전트)만 수행한다(경계 규칙).
- 이 폴더는 임시라 언제든 삭제 가능 — 00_reference는 스크립트로 재생성된다.
