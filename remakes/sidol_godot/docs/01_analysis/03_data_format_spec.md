# 03. 데이터 포맷 명세

> 모든 포맷은 실제 파일 헥사 덤프와 소스 코드로 검증함. 변환기 구현의 기준 문서.

## 1. 맵 파일 (.MAP)

- 대상: `F0.MAP` ~ `F5.MAP` (6개), `FF.MAP`(미사용)
- 크기: **39,000 bytes** = 13,000 × 3 (13,000 = MAX_MAPX 200 × MAX_MAPY 65)
- 구조: 단순 순차 배열, 헤더 없음

```
오프셋 0          : BYTE tile[65][200]   타일 인덱스 → TILE.SPR 스프라이트 번호
오프셋 13,000     : BYTE obj [65][200]   오브젝트 인덱스 → OBJ.SPR (0=없음)
오프셋 26,000     : BYTE att [65][200]   속성값 (아래 표)
```

근거: `load_map()`(GOODITEM.C L995)이 `size=200*65`씩 3회 fread.

### ATT 속성값 의미 (소스 역추적 결과)

| 값 | 의미 | 근거 |
|---|---|---|
| 0 | 통과 가능 | `move_you()` 충돌 체크 `ATT[..]==0 \|\| ==2` |
| 1 | 벽 / 개봉한 빈 상자 | 이동 불가. check_item()이 빈상자를 1로 기록 |
| 2 | 통과 가능 + 캐릭터 뒤 렌더(덮임) | move_you L402: ATT==2면 아래타일을 다시 그려 발 가림 처리 |
| 9 | 문 (통과 시 mapy±3 점프) | move_check_gate() |
| 10~14 | 방 식별 (Hak 학회장실 등) | What_Bang()/Run_Eventers |
| 15,20,...,75 | NPC방/교수실 식별 | SiDakRoom/HongRoom/... 정의(GOODITEM.H L48-82) |
| 16,21,26,31,36,41 | 교수 NPC ID (Hong/Howang/Nam/Quan/Kim/Na) | Talk() 분기 |
| 44 | 퀴즈맨 | Q_Man |
| 46,47,51,56,61,66,71,77,78 | 조교·식당·정보원 NPC | HangJo1~FELIN |
| 97/98 | 좌/우 장식인물 | pLEFT/pRIGHT |
| 110 | HP방 (크레딧룸) | HPbang |
| 150~184 | **아이템 상자** (ID-150 = ITEM_STRUCT 인덱스) | check_item() |
| 198 | MEET — 개봉 시 몬스터 출현 전투 | MEDIT convert() 흔적 |
| 199 | EMPTY — 빈 상자 메시지 | 〃 |

## 2. 스프라이트 파일 (.SPR) — ✅ 역공학 완료 (2026-08-24)

```
[매직 28B]  "Sprites Data File Ver 3.05\x1A" + 1B (버전/예약)
[팔레트 768B]  RGB 6bit ×256 (VGA DAC 값 — 사용 시 <<2)
[레코드 반복]
    u16 size      # 블록 길이 = 4 + 데이터 바이트 수
    u16 w, u16 h  # 치수
    data[size-4]  # PCX식 RLE: b<192 리터럴 / b>=192 → (b&0x3F) × 다음 바이트
                  # 단 size-4 == w*h 이면 무압축 저장
    ※ size=4,w=0,h=0 → 종료자
```

- 검증 방법: SED.H의 sprites 구조체(WORD size/int x,y) + 레코드 체인 EOF 정확 소진 +
  원작 Load_Spr 카운트 일치(TILE 105·OBJ 173·I 72·EVENTER 40 등).
- 일부 파일(HONG/HWANG/NAM/NA/WKIM 초상 등)은 단일 무압축 대형 레코드.
- 전량 추출본: `remakes/sidol_godot/assets/originals_ref/bmp_spr/`(62파일·935프레임 BMP+컨택트시트).

## 3. PCX (.PCX)

- 표준 ZSoft PCX (헤더 `0A 05 01 08`, 320×200, 256색) — EFFECT.PCX 덤프로 확인.
- 변환: ImageMagick / Python PIL → PNG. Godot 직접 임포트는 불가하므로 사전 변환 필요.
- 주요 파일: TEST_F.PCX(필드 UI 프레임), STORE.PCX(상점 배경), HP.PCX(크레딧룸),
  FACE*.PCX(대화 얼굴), READY*.PCX, I-V-*.PCX/M-R-*.PCX/M_E_*.PCX/V-*.PCX(**적 등장 일러스트** — 2026-08-26 실물 확인.
  검은 화면 위 단일 적 그림이며 전투 배경이 아니다. **원작 전투에는 배경이 없었다** —
  리메이크의 전투 배경은 이식이 아니라 신규 설계다(src/ui/battle_backdrop.gd).

## 4. 사운드 (.VOC)

- Creative Voice File (`Creative Voice File\x1A\x1A` 매직 확인).
- Sound Blaster DSP로 재생 (Voice_Say/Wait_Voc). 용도:
  - 전투 보이스: D1.VOC, DEAD.VOC, WIN.VOC, DOMANG.VOC, SMILE3.VOC
  - 문 효과: DOOR.VOC
- 변환: `ffmpeg -i in.voc out.wav` (또는 sox). Godot 임포트 후 AudioStreamWAV.
- PC 스피커 효과음(sound_box/play_music)은 파일이 아니라 **주파수/딜레이 정수 배열**로
  소스에 하드코딩(GOODITEM.C L1134-1146, L1465-1479) → WAV로 렌더링하거나
  AudioStreamGenerator로 재합성 (→ 03_data_migration.md §5).

## 5. 이벤트 경로 (.EVT)

```
EVENT1.EVT = 600 bytes = int16[100] offx + int16[100] offy + int16[100] dir
리틀 엔디안. -1은 종료 마커. dir: 1=up? 2=down? 3=left 4=right (eUP..eRIGHT 상수)
```
근거: event1()(GOODITEM.C L1605)이 `fread(offx,2*100)...` 3회 읽어 컷신 카메라/캐릭터 경로로 사용.

## 6. 대사 데이터 (TALK.TXT / TALK.H)

```c
char *message[] = { "시돌!...", "화공과 교수님이 찾으셨다.", ... };   // johab 인코딩
```

- TALK.TXT(파일)와 TALK.H(같은 내용의 헤더) 병존 — 실행 시 TXT를 XMS에 적재.
- **배열 인덱스 = 대사 ID**: `Talk_Window("[화공과 교수]", 0, 4)` = 0번부터 4줄.
- 각 레코드는 XMS에서 32바이트 고정 길이(널 종료, 잘림 가능) → 원문이 32자 초과분은 게임에서 잘렸을 수 있음. 변환 시 TALK.TXT 원문 우선.
- 주석에 등장인물/장면 구분이 있으므로 변환기가 주석을 메타데이터로 보존 권장.

## 7. 기타

| 파일 | 형식 | 내용 |
|---|---|---|
| PROLOG.CAP / PROLOG2.CAP | johab 텍스트(CRLF) | 오프닝/페이드인 안내 스토리 텍스트. 게임 내 미로딩(외부 자료) |
| DEFAULT.PAL / DP.PAL | VGA DAC 덤프 추정(768B) | 팔레트. PNG 변환 시 적용 필요 |
| DESC.SDI | ASCII | Screen Thief 캡처 유틸 설명서 (게임 데이터 아님) |
| SED.DEM | ? | sed 라이브러리 데모 |
| HELP.TXT | johab 텍스트 | 게임 세계관/조작법 (메뉴 help()는 하드코딩 문자열 사용, 이 파일은 미로딩) |

## 8. 팔레트 인덱스 의존 코드 (Godot 대체 대상)

원작은 **색상을 팔레트 인덱스 산술**로 처리한다. Godot(RGBA)에서는 의미가 다르므로 재해석 필요:

| 원본 코드 | 동작 | Godot 대체 |
|---|---|---|
| `Window()` 색 인덱스 증가(L641-686) | 창 영역을 어둡게(인덱스+1~4) | 반투명 ColorRect / Theme |
| `Effect_Fade_Out_Black()` | 인덱스++ 반복 → 검정 페이드 | Tween modulate |
| `Effect_Color(mode 0~3)` Gray/Sky/Pink/Magenta | 인덱스 리매핑으로 색조 변경 | CanvasItem 셰이더(hue shift) |
| `Print_Information_Sub` NUM[] 스프라이트 | 8자리 숫자 스프라이트 렌더 | Label + Bitmap Font |
