# 01. 시나리오 자료 인벤토리

> 원본 프로젝트에 시나리오 데이터가 **어디에, 어떤 상태로** 존재하는지의 전체 목록.
> 모든 한국어 텍스트는 조합형(Johab/cp1361) 인코딩 — UTF-8 변환 방법은 각주.

## 1. 자료 위치 요약

| 자료 | 파일 | 형식/인코딩 | 내용 | 게임 사용 여부 |
|---|---|---|---|---|
| 세계관 설정 (전체 스토리) | `HELP.TXT` (164행) | Johab 텍스트 | 발단~결말까지 완전한 줄거리, 건물 구조, 제작 의도("전하고 싶은 것") | **미로딩** — 순수 기획 문서 |
| 1층 에피소드 대본 | `PROLOG.CAP` (493행) | Johab 텍스트(CRLF) | 영화 대본 수준의 풀 시나리오. 승패 분기, 등장인물 대사 전문 | 미로딩 (오프닝은 event1()으로 축약 구현) |
| 2층 에피소드 대본 | `PROLOG2.CAP` (400행) | Johab + C 주석 혼합 | 2층 스토리 + TALK.H 발췌(기획 노트) | 미로딩 |
| 게임 내 대사 테이블 | `TALK.TXT` / `TALK.H` (~230항목) | Johab C 배열 | 실행 시 XMS 적재되는 실제 대사. 주석으로 장면 구분 | **사용됨** (32B 레코드) |
| 코드 내 하드코딩 대사·퀴즈 | `GOODITEM.C` L2092-2415 | 소스 문자열 | 크레딧룸 멤버 9명 좌표+대사, 퀴즈맨 O/X 10문항, 상점 대사 | **사용됨** |
| NPC 성격 설명 | TALK.TXT/GOODITEM.C 주석 | 소스 주석 | 교수별 성격 메모(남앵골: 술자리에서 말 잘함 등) | - |
| readme | `readme.TXT` | Johab 텍스트 | 동아리 연혁(BombMan '94/'95 → 본작), 제작자 코멘트 | 미로딩 |

**UTF-8 변환:** Python `open(f,'rb').read().decode('johab')` 또는
PowerShell `[System.Text.Encoding]::GetEncoding(1361).GetString($bytes)`.

## 2. 시나리오 관련 코드 위치

| 내용 | 위치 |
|---|---|
| 오프닝 컷신(여자 구출 이벤트) | GOODITEM.C `event1()` L1605-1692, 경로데이터 EVENT1.EVT |
| 교수 퀘스트 플래그 체인 | GOODITEM.C `Hong_P/Hwang_P/Nam_P/Na_P/Wkim_P/Gwon_P` L1693-1834, `Talk_Howa*` |
| 대사→NPC 매핑 switch | GOODITEM.C `Talk()` L1150-1202 |
| 크레딧룸(HP방) | GOODITEM.C `Run_Event_HP()` L2114-2200, 멤버 좌표 L2095 |
| 퀴즈맨 | GOODITEM.C `Quiz_Man/L_Good/R_Good/Quiz_Talk` L2222-2415 |
| 배회 NPC 대사(김밥아줌마 등) | EVENT.C `Talk_eventer()` L120-176 (**호출부 주석처리=미사용**) |

## 3. 원본 자료의 상태와 문제점

| # | 문제 | 상세 |
|---|---|---|
| S1 | **대본과 구현의 격차** | PROLOG 대본은 풍부한데 게임 오프닝은 대사 6줄짜리 event1()로 축소됨 |
| S2 | **후반부 부재** | 대본은 1~2층까지만 존재. HELP.TXT 결말(중앙통제실 바이러스)은 구현·대본 모두 없음 |
| S3 | 명시적 "2부" 계획 | TALK.TXT 말미 주석: "여기는 DEF약품에 대한 대화… 2부는 모두 모였을 때 합시다" — 약품 수집 후반부가 계획만 존재 |
| S4 | 설정 불일치 | 중앙통제실 층: HELP/TALK="5층" vs PROLOG2="3층" (HELP 기준 5층이 정설) |
| S5 | 약품 조합 수치 불일치 | 드래그 건전지 "10V"(TALK L40) vs "100V"(L249, L194) — 후반 주석(100V)이 정설 |
| S6 | 텍스트 오염 | PROLOG.CAP 일부 행이 다른 인코딩으로 재저장된 흔적(모음 깨짐) — 원문 복원 필요 |
| S7 | 대사 ID 하드코딩 | Talk_Window 호출마다 번호 리터럴 → 개편 시 추적 어려움 (개편안에서 해결) |

## 4. 시나리오 파이프라인 제안 (개편 작업용)

```
원본(Johab) ──decoder──► docs/04_scenario/*.md (사람이 읽고 편집)
                              │ 개편 집필
                              ▼
                     scenario.json (Godot DialogueTable)
                              │ 임포터
                              ▼
                     res://data/dialogue/*.tres
```

- 대사 원문은 절대 직접 수정하지 않고, 개편본은 새 테이블로 작성.
- `@t숫자` 참조 체계 유지 시 원문 추적 가능 (→ 03_redesign_proposal.md).
