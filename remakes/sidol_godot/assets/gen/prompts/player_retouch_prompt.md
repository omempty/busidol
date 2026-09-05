# 주인공 시돌이(SIDOL) 스프라이트 시트 리터칭 & 스케일업 의뢰

## 역할
너는 1995년 DOS RPG의 원작 도트 스프라이트를 현대 명작 JRPG 톤으로 격상시키는
16비트 픽셀 아트 리터처러다. 원작의 캐릭터 콘셉트와 색채를 베이스로, **2.5~3등신 SD 클래식 JRPG 체형과 셀을 꽉 채우는 묵직한 볼륨감의 정통 도트 그래픽**으로 스케일업 및 리터칭한다.

## 캐릭터 콘셉트: 부싯돌 (SIDOL)
1995년 한국 공대 새내기 남학생. 활달하고 허둥대지만 의리파.
- **의상/외형**: 잿빛 공대 자켓 교복, 청바지, 흰 운동화, 손에 작은 부싯돌 조각.
- **체형/비율**: 2.5~3등신 SD 체형 (팔콤 『쯔바이!!』, 『악튜러스』 풍).
- **시점**: 탑다운 JRPG 3/4 쿼터뷰 시점.

## 화풍 & 픽셀 스타일 핵심 지침 (★최우선 적용★)
1. **2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 볼륨감**:
   - 큰 머리와 명확한 눈매/표정, 듬직하고 단단한 상체와 짤막하지만 안정감 있는 하체.
   - 기존 24×24px의 왜소한 빈 공간을 탈피하여, **셀 영역(실높이 약 80~88% 면적, 40~44px on 48×48 / 80~88px on 96×96 / 100~115px on 128×128)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 실루엣**.
2. **100% 순수 16비트 도트 픽셀 아트 (Pure Dot Matrix)**:
   - 3D 렌더, 벡터(SVG), 수채화, 일러스트 브러시 질감 절대 금지.
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E) 도트 테두리.
   - 색조 그림자: 단순 검정 대신 남보라(#3A285C) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트.

## 출력 규격 & 애니메이션 레이아웃
- **시트 규격**: **128×320px PNG** (셀 단위: 64×64px, 2열 × 5행) 또는 **256×640px PNG** (셀 단위: 128×128px, 2열 × 5행)
- 각 행 = 한 애니메이션, 좌→우가 2프레임 루프 순서:

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 2프레임 | 정면 2.5등신 씩씩한 발구름 보행 |
| 1 | walk_up | 2프레임 | 뒷모습 자켓 펄럭임 보행 |
| 2 | walk_left | 2프레임 | 좌향 2.5등신 팔다리 교차 보행 |
| 3 | walk_right | 2프레임 | 우향 2.5등신 팔다리 교차 보행 |
| 4 | idle_down | 2프레임 | 정면 대기 — 1px 미세 호흡 바운스 |

- 각 셀 내부에서 캐릭터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 6~10px)** 에 정렬하며, 셀 영역을 넉넉히 채운다.
- 배경: **완전 투명(alpha=0)** 또는 **단색 마젠타 #FF00FF**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG male student hero pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the cell with substantial presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 1995 Korean engineering college student hero Sidol with ash-grey jacket uniform, blue jeans, white sneakers, holding a tiny flint stone, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 2 columns by 5 rows on solid magenta #FF00FF background. Row 1: walk_down (2 frames), Row 2: walk_up (2 frames), Row 3: walk_left (2 frames), Row 4: walk_right (2 frames), Row 5: idle_down (2 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:2
```

---
## 납품 및 검증
- 결과 파일 저장 경로: `assets/raw/llm/10_submitted/sprites/player_sheet_v1.png`
- 검증 명령어: `python tools/convert/validate_retouch_sheet.py assets/raw/llm/10_submitted/sprites/player_sheet_v1.png`
