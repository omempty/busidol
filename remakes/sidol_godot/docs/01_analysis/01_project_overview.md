# 01. 프로젝트 개요

## 1. 기본 정보

| 항목 | 내용 |
|---|---|
| 게임명 | **BSD 시돌이의 모험** (BuSiDol: 부싯돌) |
| 장르 | 2D 탑뷰 필드 RPG + 턴제 전투 (스쿨 컨셉) |
| 제작 | 대구대학교 전산과 게임동아리 **부싯돌** (멤버 9명) |
| 제작 기간 | 1995.2 ~ 1995.4 (GOODITEM.C 헤더 코멘트 기준) |
| 플랫폼 | MS-DOS (16비트 리얼 모드) |
| 해상도 | VGA Mode 13h — **320×200, 256색 팔레트** |
| 타일 크기 | **12×12 px**, 필드 뷰포트 **19×15 타일** |

> 원본 `readme.TXT`에 따르면 동아리의 이전 작품 BombMan '94/'95를 잇는 후속작으로,
> "대구대 전산과 배경의 학교 RPG"이다. 스토리: 화공과 교수가 구해온 약품("드래그 앨린 알콜")을
> 찾아 캠퍼스 6개 층(건물)을 돌아다니며 교수·조교·학생들과 대화하고 괴물과 싸운다.

## 2. 원본 기술 스택

```
┌─────────────────────────────────────────────────────┐
│                  sidol.exe (게임 본체)                │
├──────────────┬──────────────┬───────────────────────┤
│ GOODITEM.C   │ WARMODE.C    │ RUNXMS.C + XMS.H      │
│ (필드/메인)   │ (전투 모드)   │ (XMS 확장메모리 대사관리)│
│ EVENT.C      │ SCROLL.C     │ EFF.C / WIN2.C        │
│ (배회 NPC)    │ (asm 스크롤)  │ (윈도우/페이드 이펙트)   │
├──────────────┴──────────────┴───────────────────────┤
│              sed.lib (외부 그래픽/사운드 라이브러리)     │
│  - sprites 자료형, Load_Spr/Put_Spr/Page 시스템       │
│  - Printf_Han 한글 폰트 출력, Multi_Key 키보드         │
│  - Sound Blaster VOC 재생, PC 스피커 sound()           │
├─────────────────────────────────────────────────────┤
│  Turbo C (tcc -ml 대형모델), inline 8086 어셈블리      │
│  DOS int 10h / VGA VRAM A000h 직접 접근               │
└─────────────────────────────────────────────────────┘
```

- **sed.lib**: 소스에 미포함(바이너리만 존재). 국내 게임 프로그래밍 서적(김종찬 외) 계열의
  그래픽 라이브러리로 추정. 소스 내 주석에 "김종찬의 '게임을 만들자'의 음향에디터 사용" 언급 있음.
  SPR 파일 매직 문자열은 `Sprites Data File Ver 3.05`.
- **더블 버퍼링**: VGA 하드웨어 페이지 0~3 사용 (`Active_Page`/`View_Page`/`Page_Copy`),
  `page` 전역 변수로 0/1 페이지 플립.
- **한글 출력**: `Printf_Han(..., NORMAL_FONT/BEAU_FONT, ...)` — 자체 한글 비트맵 폰트
  (`Load_Font("h","e")`). Godot에서는 일반 TTF/OTF 폰트로 대체.

## 3. 파일 구성 (원본 디렉터리)

### 3.1 소스 코드

| 파일 | 크기 | 역할 | 비고 |
|---|---|---|---|
| `GOODITEM.C` | 69 KB (~2,447행) | **main() 포함.** 필드 루프, 이동/충돌, 대화 분기, 상점, 아이템, 이펙트, 퀴즈, HP방 이벤트 | 사실상 모든 로직 집결 |
| `GOODITEM.H` | 12 KB | 맵/스프라이트 상수, 아이템 테이블, 적 구조체, 전역 변수 정의 | `.c`에서 include되어 전역 변수 중복 위험 |
| `WARMODE.C` | 24 KB (~1,224행) | 턴제 전투 전체 (메뉴/공격 애니/HP바/아이템 사용) | |
| `WARMODE.H` | 2.6 KB | 전투용 아이템 테이블(24종), 레벨표, 메뉴 문자열 | GOODITEM.H와 데이터 중복 |
| `EVENT.C` | 4.6 KB | 배회 NPC(eventer) 이동/초기화/대화 | `#include "event.c"` 방식으로 포함 |
| `ITEM.C` | 26 KB | 초기 버전 아이템 뷰어 데모 (자체 main() 보유) | **현재 빌드 미사용 (개발 유물)** |
| `MEDIT.C` | 14 KB | 맵 에디터 (TILE/OBJ/ATT 3레이어 + 이벤트 경로 편집) | 독립 실행 도구 |
| `RUNXMS.C` | 2.1 KB | talk.txt → XMS 32바이트 레코드 적재 | |
| `XMS.H` | 4.7 KB | XMS 드라이버 API 래퍼 | |
| `SCROLL.C` | 1.9 KB | inline asm 4방향 1픽셀 부드러운 스크롤 | VGA VRAM rep movsb |
| `EFF.C` / `WIN2.C` | 8.4 / 1.6 KB | 윈도우 색조 이펙트(`Window()` 중복 사본 존재) | WIN2.C는 사실상 데드코드 |
| `SCAP.C` | 3.9 KB | 12×12 스프라이트 화면 캡처 도구 | 개발 유틸리티 |
| `RUN.BAT` | - | 빌드: `tcc -ml gooditem.c warmode.obj runxms.obj scroll.obj sed.lib` | |

### 3.2 데이터 / 리소스

| 유형 | 파일 | 용도 |
|---|---|---|
| 맵 | `F0.MAP`~`F5.MAP` (39,000B ×6), `FF.MAP`(미사용 추정) | 건물 1~6층. TILE+OBJ+ATT 3레이어 |
| 스프라이트 | `TILE.SPR`(106장), `I.SPR`(주인공/필드몬스터 159장), `OBJ.SPR`(175장), `ITEM.SPR`, `EVENTER.SPR`, `E1~E5.SPR`(전투 몬스터), `A*.SPR/D*.SPR`(전투 연출), `MENU.SPR` 등 | sed.lib 전용 포맷 |
| 이미지 | `TEST_F.PCX`(UI 프레임), `STORE.PCX`(상점), `HP.PCX`(크레딧룸), `EFFECT.PCX` 등 | 표준 256색 PCX |
| 음성 | `D1.VOC`, `DEAD.VOC`, `WIN.VOC`, `DOMANG.VOC`, `DOOR.VOC` 등 | Creative VOC (Sound Blaster) |
| 대사 | `TALK.TXT`/`TALK.H` (johab 인코딩, ~230 라인 배열) | 번호 인덱스 대사 테이블 |
| 이벤트 | `EVENT1.EVT` (600B = int[100]×3), `EVENT1.SPR` | 오프닝 컷신 경로 데이터 |
| 텍스트 | `PROLOG.CAP`, `PROLOG2.CAP` (johab), `HELP.TXT`, `readme.TXT` | 프롤로그/도움말 |
| 팔레트 | `DEFAULT.PAL`, `DP.PAL` | VGA 팔레트 덤프 |
| 실행 | `sidol.exe`, `sidol.PIF` | 완성 빌드 |
| 보관 | `보존/BSD.ARJ` | ARJ 압축 백업 |

## 4. 인코딩 주의사항 (중요)

모든 한국어 텍스트(C 소스 주석·문자열, TALK.TXT, PROLOG.CAP)는
**완성형 CP949(EUC-KR)가 아니라 조합형(KSSM/Johab 계열) 코드**로 저장되어 있다.

- 검증: `GOODITEM.C`의 "부싯돌" 바이트가 `A6 81 AF B5 95 A9` — Johab(cp1361)으로 디코딩 성공 확인.
- 변환 방법:
  ```python
  text = open('TALK.TXT', 'rb').read().decode('johab')   # Python
  ```
  ```powershell
  [System.Text.Encoding]::GetEncoding(1361).GetString($bytes)
  ```
- **Godot 마이그레이션 시 반드시 UTF-8로 변환**할 것 (→ [03_data_migration.md](../02_design/03_data_migration.md)).

## 5. 현재 코드베이스 상태 요약

| 구분 | 내용 |
|---|---|
| 완성도 | 필드 이동/대화/전투/아이템/상점/이벤트 플레이 가능. `sidol.exe` 존재 |
| **미구현** | **세이브/로드** (`io()`가 안내 문구만 출력), **레벨업 처리**(exp 누적만, LEVELsruct 표 미연동), 전투 중 음악 설정(WMUSIC) 일부 |
| 데드코드 | `ITEM.C`(구버전), `FF.MAP`, `Talk_eventer()` 호출부 주석처리, `WIN2.C` |
| 코드 품질 | 전역 변수 다수, `.h`에 전역 변수 정의(다중 include 시 중복), 구조체 3곳 재정의, 함수 프로토타입 불일치 |
