# 02. 소스 코드 분석

## 1. 모듈 의존성 및 빌드 구조

```
RUN.BAT:  tcc -ml gooditem.c warmode.obj runxms.obj scroll.obj sed.lib

gooditem.c ──► #include "gooditem.h" ──► sed.h (라이브러리 헤더, 소스 미보유)
           └──► #include "event.c"   ← .c 파일 직접 include (안티패턴)
warmode.c  ──► #include "warmode.h"  ──► sed.h
runxms.c   ──► #include "xms.h"
scroll.c   ──► (inline asm 전용)
```

**구조적 문제점 (Godot 재설계에서 해결 대상):**

| # | 문제 | 위치 | Godot 해결책 |
|---|---|---|---|
| P1 | `.h`에 전역 변수 **정의** 포함 → 다중 include 시 중복 위험 | GOODITEM.H L137-148 (`v_Hong` 등) | 오토로드 싱글턴 `GameState`로 이관 |
| P2 | 같은 구조체가 파일마다 재정의 | `enemy_attribute`(GOODITEM.H/WARMODE.C), `flagWE_STRUCT`(2곳), `ITEM`(GOODITEM.H/WARMODE.C/ITEM.C) | 단일 `Resource` 클래스 |
| P3 | 아이템 데이터 중복·불일치 | WARMODE.H `ITEM_TABLE`(24종) vs GOODITEM.H `ITEM_STRUCT`(37종) | 단일 `ItemDB` 리소스 |
| P4 | `.c` 직접 include | GOODITEM.C L15 | Godot 노드/오토로드 분리 |
| P5 | 렌더링·입력·로직 혼재 | 모든 함수 | 노드 트리 + 컴포넌트 분리 |
| P6 | 매직 넘버 하드코딩 | 좌표(104,15), 계단 좌표, ATT 값 등 | 데이터 파일(Resource/JSON) 외부화 |

## 2. main() 게임 루프 (GOODITEM.C L62-192)

```
초기화:
  RunXms()               대사 문자열을 XMS에 적재
  TILE/OBJ/ATT = farmalloc(200*65)
  Vga_Plane / Multi_Key / Decode_Init / Load_Font
  Load_Spr: tile.spr(106), item.spr(38), num.spr(11),
            i.spr(159 캐릭터), eventer.spr(41), obj.spr(175)
  load_map("f1.map")     ← 시작은 1층 (f=1)
  init_item_flag / init_enemy
  Active_Page(2); Print_Main_Frame(); Print_Tile(); Pre_Event_Init()

메인 루프 (Alt+X까지):
  Delay(SPEED)
  Page_Copy(2→page); Print_Information()      상태 숫자 갱신
  Set_Clip(12,12,239,191)                     필드 영역 클리핑
  move_check_gate()                           문 통과 처리
  move_you()                                  주인공 이동+그리기
  ENTER → Menu_esc()                          메인 메뉴
  (mapx+x,mapy+y)==(104,15) && !flag1 → event1()   오프닝 컷신 1회
  SPACE → Talk() + 방향별 check_item()        대화/아이템 상자
  floor_move()==1 → init_enemy(), Event_Init() 층 이동 시 재생성
  move_enemy()                                필드 몬스터 AI
  move_eventer()                              배회 NPC AI
  Check_Quang()                               접촉 → WarMode() 전투
  Run_Eventers()                              방 진입 이벤트(HP방)
  View_Page 플립

종료: farfree, Free_Spr, Han_End, Text_Mode, XMS 해제
```

## 3. 파일별 상세

### 3.1 GOODITEM.C — 필드/시스템 전반

| 함수 | 위치 | 역할 |
|---|---|---|
| `main()` | L62 | 게임 루프 (위 참조) |
| `move_you()` | L343 | 4방향 이동, 충돌 판정(ATT 0/2만 통과), 스크롤 트리거(x==4/12, y==4/9에서 mapx/mapy 변경), 8방향 스프라이트(mode 0~7) 토글 |
| `UpScroll`~`RightScroll()` | L416-487 | asm 스크롤 후 새로 드러난 1줄 타일만 다시 그림 |
| `load_map()` | L995 | MAP 파일에서 TILE/OBJ/ATT 순서로 size(13,000)바이트씩 3회 fread |
| `floor_move()` / `walk_floor()` | L1319-1387 | 고정 좌표 4곳의 계단: (100,63)↓+3타일, (103,63)↓-3, (169,60)↓+8, (177,60)↓-8. 층 애니 후 `f` 증감, 새 맵 로드 |
| `move_check_gate()` | L1396 | 발밑 ATT==9(문) 감지 → 문 오브젝트 그리고 `mapy±3` 점프 |
| `Check_Quang()` | L527 | 적과 x±1,y±2 범위 접촉 → `WarMode(page, i, &We, &eye)` 호출. 결과 무관하게 exp/money 가산, 적 사망처리 |
| `Talk()` | L1150 | 캐릭터 전방 2셀의 ATT 값으로 NPC 식별 → NPC별 Talk_* 함수 분기 (~20개) |
| `Talk_Window(name,num,linenum)` | L603 | 대사창 렌더: XMS에서 num부터 linenum개의 32B 레코드를 읽어 3줄씩 표시 |
| `check_item(itemm,flag)` | L1022 | 상자 개봉: item_flag 기록, ATT→1(빈상자), OBJ→153/154 교체. MEET이면 전투, EMPTY면 "비어있음", DON1~3이면 돈 획득, 나머지 SaveItem |
| `SaveItem()/Viewer()` | L1988/2002 | 인벤토리 `view[50]`(att,num) 추가/스크롤 UI |
| `store()` | L915 | 음식점: 라면/카레/만두/김밥/우유/쇠주 (가격 100~600, HP+5~20) |
| `Menu_esc()/io()/help()/gitar()` | L1481~ | 메인메뉴(도움말/아이템/io/기타), io는 **안내문만 출력(세이브 미구현)**, gitar는 지도보기/속도(ALPHA)/음악 설정 |
| `map_view()` | L2202 | TILE 값을 색으로 하는 미니맵 |
| `Quiz_Man()/L_Good/R_Good/Quiz_Talk` | L2222-2415 | O/X 퀴즈 10문제 (하드코딩 배열) |
| `Run_Event_HP()/What_Bang()` | L2073/2087 | ATT로 현재 방 확인 → HP방 진입 시 크레딧 화면(멤버 9명 좌표+대사) |
| `event1()` | L1605 | 오프닝 컷신: EVENT1.EVT 경로 따라 여자 등장→이동→대화→전투(WarMode 강제 호출) |
| `Hong_P/Hwang_P/Nam_P/Na_P/Wkim_P/Gwon_P` | L1693-1834 | 교수 NPC 대면 연출(얼굴 클로즈업 Get_Image/Put_Image + 대사). v_Hong/v_Nam 등 플래그로 퀘스트 체인 |
| 사운드 | L1132/1469 | `sound_box`(PC스피커 효과음 3종), `play_music`(주파수 시퀀스 3곡) |

### 3.2 WARMODE.C — 전투

| 함수 | 역할 |
|---|---|
| `WarMode(page,SprNumber,WE,EYE)` | 전투 진입: ME/EN 초기화 → `Animation()` 루프 → 결과 보이스(win/dead/domang.voc) → 복귀 |
| `Animation()` | 메인 턴 루프: `MeMove()`(플레이어 행동) → `BackW()`(배경/입장 그래픽) → `EnemyAttack()` |
| `MeMove()/MenuReturn()` | 전투 메뉴 5항목: 공격/도구(ItemViewer+ItemEat)/상태(PrintScore)/설정(PrintEffect: WVISUAL·WSOUND·WMUSIC)/도망 |
| `DeadEnemy()/EnemyAttack()` | 데미지 계산: 플레이어 `(Ap+random(10))/4`, 적 `(Power+random(10))/6`. HP<=0 처리 |
| `MyAttackAni/EnemyAttackAni/MyAvoid` | 격투게임 패러디 연출 (a1/a3/a5, d1/d2/d3, e1-e8.spr, fire.spr). 페이지 복사+수평 이동 반복 |
| `BarInfo()` | 양측 HP바 (50px, CL_Bar 비율) |
| `ItemEat()` | 장착 아이템 해제→신규 장착, ITEM_TABLE 수치를 ME에 가산감산 |
| `InitStruct/ReturnStruct` | `We` 전역 ↔ `ME` 전역 복사 (구조체 불일치 완충) |

**발견된 결함/특이사항:**
- `InitStruct()`에서 `ME.MaxHp` 초기화가 주석 처리됨(L797) → `MEHURRY` 계산이 쓰레기값 기반.
- 승패와 무관하게 exp/money가 지급됨(Check_Quang의 3분기 동일).
- 도망 선택(case 4)은 항상 성공.
- 레벨업 로직 부재: `We.exp`만 누적, `ME_LEVEL[ME.Level]`은 level=0으로 고정 사용.

### 3.3 EVENT.C — 배회 NPC

- 층별로 1명(`eve_start=f-1`) 활성. `EVE_PATTERN[5][40]` 웨이포인트.
- `Event_Init()`: 층 이동 시 (80+rnd20, 27+rnd16) 랜덤 배치.
- `move_eventer()`: 패턴 이동 + 화면 내 CPut_Spr.
- `Talk_eventer()`: 김밥아줌마/수위/가수/꺼벙이/썰렁이 대사 — **호출부가 주석 처리되어 미사용**(GOODITEM.C L166).

### 3.4 MEDIT.C — 맵 에디터 (독립 도구)

- 3레이어(TILE/OBJ/ATT) 페인팅, 타일 팔레트 선택, 스탬프 복사, EVT(offx/offy/dir int[100]) 저장.
- `convert()`: ATT 182→198(MEET), 183→199(EMPTY) 마이그레이션 흔적.
- Godot에서는 **커스텀 에디터 플러그인 또는 Tiled 호환 파이프라인으로 대체** 권장.

### 3.5 RUNXMS.C + XMS.H — 대사 저장소

- `Talk2Xms()`: talk.txt에서 `"..."` 내용만 추출해 **32바이트 고정 길이 레코드**로 XMS 순차 적재.
- `Talk_Window()`가 `XM2CM(handle, ...)`으로 레코드 번호 조회.
- 의미: **TALK.TXT의 문자열 순서가 곧 대사 ID**. Godot 변환 시 JSON 배열 인덱스와 1:1 매핑 유지 가능.

### 3.6 SCROLL.C / EFF.C / WIN2.C / SCAP.C

- SCROLL.C: VGA VRAM(A000h) `rep movsb` 1px 스크롤 4종. Godot의 Camera2D가 완전히 대체.
- EFF.C/WIN2.C: 팔레트 인덱스 조작으로 창 색조/페이드아웃 구현. Godot에서는 ColorRect+셰이더/Theme로 대체. WIN2.C는 중복 사본.
- SCAP.C: 12×12 영역을 스프라이트 파일로 캡처하는 개발 도구 → SPR 포맷 역공학 시 참고 자료.

## 4. 전역 변수 목록 (재설계 시 소속 결정)

| 변수 | 정의 | 용도 | Godot 귀속 |
|---|---|---|---|
| `page` | GOODITEM.H | 더블버퍼 플립 | 삭제 (엔진 처리) |
| `x,y,mapx,mapy` | GOODITEM.H | 플레이어 로컬/카메라 좌표 | `PlayerEntity.grid_pos` + `Camera2D` |
| `mode` | GOODITEM.H | 캐릭터 방향 프레임(0-7) | PlayerEntity 애니메이션 상태 |
| `f` | GOODITEM.H | 현재 층(0-5) | `GameState.current_floor` |
| `We` | GOODITEM.H | 플레이어 스탯(level/exp/hp/ap/money) | `GameState.player_stats` |
| `eye[MAX_EYE]` | GOODITEM.H | 필드 몬스터 8체 | EnemyEntity 씬 인스턴스 |
| `eventer[MAX_EVE]` | GOODITEM.H | 배회 NPC | NpcEntity 씬 인스턴스 |
| `item_flag[6][45]` | GOODITEM.H | 층별 상자 개봉 여부 | `GameState.chest_flags` (세이브 대상) |
| `view[50], inum` | GOODITEM.H | 인벤토리 | `Inventory` 클래스 |
| `v_Hong, v_Howa, ...` | GOODITEM.H | 퀘스트/NPC 플래그 | `GameFlags` Dictionary |
| `TILE/OBJ/ATT` | GOODITEM.H | 맵 버퍼 far 포인터 | TileMapLayer ×3 + custom data |
| `tile/spt/obj/item/...` | GOODITEM.H | 스프라이트 배열 | SpriteFrames/AtlasTexture |
| `WVISUAL/WSOUND/WMUSIC` | WARMODE.C | 전투 연출 옵션 | `SettingsManager` |
