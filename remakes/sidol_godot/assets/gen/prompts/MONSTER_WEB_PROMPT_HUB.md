# 👾 BSD 시돌이의 모험 — 몬스터 볼륨감 있는 SD JRPG 픽셀아트 웹 프롬프트 허브

> **웹 브라우저의 생성형 AI(ChatGPT-4o / Claude 3.5 Sonnet / Midjourney v6 / Gemini Web)** 에
> 복사-붙여넣기하여 **2.5~3등신 SD 체형 + 셀을 꽉 채우는 묵직한 볼륨감의 정통 16비트 JRPG 도트 스프라이트 시트**를 생성하는 가이드입니다.

## 📌 생성 및 납품 워크플로우 3단계
1. **프롬프트 복사**: 아래 원하는 몬스터의 `[한국어 프롬프트]`(ChatGPT/Claude) 또는 `[영문 프롬프트]`(Midjourney/DALL-E)를 복사합니다.
2. **참조 이미지 첨부**: 해당 몬스터 폴더(`assets/raw/llm/_batch/0830_1133/monsters__<id>/`)의 `grid_template.png`, `style_ref.png`, `subpalette.png`를 함께 첨부합니다.
3. **결과물 저장**: 다운로드한 PNG를 `assets/raw/llm/10_submitted/monsters/<id>_v1.png` 로 저장하면 심사 보드에 즉시 뜹니다.

---

### 👾 매드 아이 (mad_eye) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `320×512px` (5열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__mad_eye/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__mad_eye/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__mad_eye/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 매드 아이 (mad_eye) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 매드 아이. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **320×512px PNG** (셀 단위: 64×64px, 5열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 5프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 4프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster mad_eye, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (5 frames), Row 7: hurt (2 frames), Row 8: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 320×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/mad_eye_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/mad_eye_v1.png`

```
</details>

---

### 👾 디웜 (dworm) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `256×576px` (4열 × 9행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__dworm/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__dworm/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__dworm/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 디웜 (dworm) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 디웜. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **256×576px PNG** (셀 단위: 64×64px, 4열 × 9행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 4프레임 | attack 동작 프레임 |
| 6 | death | 4프레임 | death 동작 프레임 |
| 7 | burrow | 3프레임 | burrow 동작 프레임 |
| 8 | emerge | 3프레임 | emerge 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster dworm, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 9 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (4 frames), Row 7: death (4 frames), Row 8: burrow (3 frames), Row 9: emerge (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 256×576 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/dworm_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/dworm_v1.png`

```
</details>

---

### 👾 불거 (vulgar) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `256×512px` (4열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__vulgar/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__vulgar/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__vulgar/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 불거 (vulgar) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 불거. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **256×512px PNG** (셀 단위: 64×64px, 4열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 4프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 3프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster vulgar, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (4 frames), Row 7: hurt (2 frames), Row 8: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 256×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/vulgar_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/vulgar_v1.png`

```
</details>

---

### 👾 오지 (ozzy) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `256×512px` (4열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__ozzy/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__ozzy/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__ozzy/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 오지 (ozzy) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 오지. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **256×512px PNG** (셀 단위: 64×64px, 4열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 4프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 3프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster ozzy, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (4 frames), Row 7: hurt (2 frames), Row 8: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 256×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/ozzy_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/ozzy_v1.png`

```
</details>

---

### 👾 아이언 보크 (iron_voc) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `320×512px` (5열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__iron_voc/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__iron_voc/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__iron_voc/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 아이언 보크 (iron_voc) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 아이언 보크. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **320×512px PNG** (셀 단위: 64×64px, 5열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 5프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 4프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster iron_voc, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (5 frames), Row 7: hurt (2 frames), Row 8: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 320×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/iron_voc_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/iron_voc_v1.png`

```
</details>

---

### 👾 헬캅 (hellcop) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `320×512px` (5열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__hellcop/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__hellcop/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__hellcop/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 헬캅 (hellcop) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 헬캅. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **320×512px PNG** (셀 단위: 64×64px, 5열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 5프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 4프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster hellcop, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (5 frames), Row 7: hurt (2 frames), Row 8: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 320×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/hellcop_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/hellcop_v1.png`

```
</details>

---

### 👾 오레이 (o_ray) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `384×512px` (6열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__o_ray/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__o_ray/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__o_ray/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 오레이 (o_ray) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 오레이. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **384×512px PNG** (셀 단위: 64×64px, 6열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 6프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 4프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster o_ray, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 6 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (6 frames), Row 7: hurt (2 frames), Row 8: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:1
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 384×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/o_ray_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/o_ray_v1.png`

```
</details>

---

### 👾 스파커 (sparker) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `320×512px` (5열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__sparker/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sparker/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sparker/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 스파커 (sparker) 
- **서식 구역**: 교내 서식 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  1995년 한국 공대 캠퍼스 호러 몬스터 스파커. 2.5~3등신 SD 비율과 128×128 셀을 꽉 채우는 묵직한 볼륨감을 지닌 16비트 레트로 JRPG 몬스터.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **320×512px PNG** (셀 단위: 64×64px, 5열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk_down | 4프레임 | walk_down 동작 프레임 |
| 1 | walk_up | 4프레임 | walk_up 동작 프레임 |
| 2 | walk_left | 4프레임 | walk_left 동작 프레임 |
| 3 | walk_right | 4프레임 | walk_right 동작 프레임 |
| 4 | idle_down | 2프레임 | idle_down 동작 프레임 |
| 5 | attack | 5프레임 | attack 동작 프레임 |
| 6 | hurt | 2프레임 | hurt 동작 프레임 |
| 7 | death | 3프레임 | death 동작 프레임 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), 16-bit retro JRPG monster sparker, super deformed 2.5 heads tall bulky proportions filling the cell frame, 1990s DOS campus horror style, detailed sprite sheet, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (5 frames), Row 7: hurt (2 frames), Row 8: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 320×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/sparker_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/sparker_v1.png`

```
</details>

---

### 👾 씨버그 (C Bug) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `192×336px` (4열 × 7행, 셀 48px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__c_bug/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__c_bug/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__c_bug/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 씨버그 (C Bug) 
- **서식 구역**: 지하 1층 및 2층 전산실 구석
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  128×128 셀을 넓게 채우는 2.5등신 두껍고 단단한 바퀴벌레 괴물. 묵직한 흑갈색 키틴질 등껍질에 C 구문 기호가 각인되어 있고, 굵은 6개 다리로 질주하며 턱으로 물어뜯는다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **192×336px PNG** (셀 단위: 48×48px, 4열 × 7행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0~3 | walk_4dir | 4방향 각 4프레임 | 6개 다리를 빠르게 움직이는 지네/바퀴벌레 고속 질주 |
| 4 | idle_down | 2프레임 | 더듬이를 씰룩거리며 턱을 딱딱거림 |
| 5 | attack | 4프레임 | 앞다리를 들고 턱으로 강력하게 물어뜯기 |
| 6 | hurt | 2프레임 | 등껍질에 금이 가며 초록 체액이 튐 |
| 7 | death | 3프레임 | 뒤집혀 다리를 바둥거리다 경직되어 소멸 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), wide bulky 2.5 heads tall mechanical cockroach beetle monster filling the cell frame, heavy dark chiton armor engraved with glowing C code syntax symbols, thick twitching antennae and scuttling legs, biting with heavy pincer jaws, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 7 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (3 frames), Row 7: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 192×336 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/c_bug_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/c_bug_v1.png`

```
</details>

---

### 👾 플라잉 논문 (Flying Thesis) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `192×144px` (4열 × 3행, 셀 48px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__flying_thesis/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__flying_thesis/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__flying_thesis/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 플라잉 논문 (Flying Thesis) 
- **서식 구역**: 도서관 및 2~4층 복도
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  두툼하고 묵직한 하드커버 양피지 책 괴물. 128×128 셀 너비를 꽉 채우는 두꺼운 책 표지와 펄럭이는 다층 양피지 날개, 붉은 눈망울과 금박 리본을 달고 공중을 날아다니며 A4 종이 수리검을 날린다. 쓰러지면 붉은 F학점 도장이 찍힌다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **192×144px PNG** (셀 단위: 48×48px, 4열 × 3행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | walk/idle | 4프레임 | 두꺼운 양피지 책 날개를 펄럭이며 공중을 부유 |
| 1 | attack | 3프레임 | 몸을 급회전하며 날카로운 A4 종이 칼날 탄막 발사 |
| 2 | death | 3프레임 | 붉은 F학점 첨삭 도장이 쾅 찍히며 찢어진 종이 잔해로 분해 산화 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), wide bulky flying hardcover graduation thesis book monster filling the cell width, thick parchment paper pages flapping, gold foil spine, glowing red angry pixel eyes, shooting sharp paper shurikens, stamped with red F grade on death, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 3 rows on solid magenta #FF00FF background. Row 1: walk (4 frames), Row 2: attack (3 frames), Row 3: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:1
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 192×144 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/flying_thesis_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/flying_thesis_v1.png`

```
</details>

---

### 👾 널 포인터 (Null Pointer) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `256×512px` (4열 × 8행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__null_pointer/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__null_pointer/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__null_pointer/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 널 포인터 (Null Pointer) 
- **서식 구역**: 전산실 및 서버 랙 구역
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  2.5등신 묵직한 볼륨감의 남색 후드 로브를 두른 디지털 사신 유령 괴물. 로브 폭이 128×128 셀을 넓게 채우며, 얼굴 대신 0x00000000 이진 비트가 소용돌이치고 붉은 세그폴트 에너지 갈퀴를 휘두른다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **256×512px PNG** (셀 단위: 64×64px, 4열 × 8행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0~3 | walk_4dir | 4방향 각 4프레임 | 4방향 묵직한 유령 부유 이동 |
| 4 | idle_down | 2프레임 | 후드 안쪽 시안색 비트 깜빡임 대기 |
| 5 | attack | 4프레임 | 양손에서 붉은 세그폴트 에너지 갈퀴를 뻗어 할퀴기 |
| 6 | hurt | 2프레임 | 몸체 이진 비트가 깨지며 노란 글리치 발생 |
| 7 | death | 3프레임 | NULL 참조가 해제되며 비트가 사방으로 흩어져 소멸 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), bulky 2.5 heads tall digital reaper ghost monster in wide deep indigo hooded robe filling the cell, void face filled with floating cyan binary digits 0x0000, slashing with glowing red segmentation fault energy claws, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 4 columns by 8 rows on solid magenta #FF00FF background. Row 1: walk_down (4 frames), Row 2: walk_up (4 frames), Row 3: walk_left (4 frames), Row 4: walk_right (4 frames), Row 5: idle_down (2 frames), Row 6: attack (4 frames), Row 7: hurt (2 frames), Row 8: death (3 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 9:16
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 256×512 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/null_pointer_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/null_pointer_v1.png`

```
</details>

---

### 👾 로그 벤딩 (Rogue Vending) 
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `320×384px` (5열 × 4행, 셀 64px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__rogue_vending/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__rogue_vending/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__rogue_vending/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 로그 벤딩 (Rogue Vending) 
- **서식 구역**: 학생회관 로비 및 층별 휴게실
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  128×128 셀을 묵직하고 단단하게 꽉 채우는 2.5등신 빨간색 캔 음료 자판기 미믹 괴물. 듬직한 사각 섀시에 음료들이 진열되어 있고, 투출구가 덜컥 열리면 날카로운 금속 이빨과 붉은 눈망울이 드러나며 캔 음료를 연사한다. 쓰러지면 파란색 캔 1개가 딸깍 사출된다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **320×384px PNG** (셀 단위: 64×96px, 5열 × 4행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 2프레임 | 단단하고 묵직한 무해 자판기 위장 상태 |
| 1 | awaken | 3프레임 | 음료 투출구가 덜컥 열리며 날카로운 금속 이빨과 노란 눈 개방 |
| 2 | attack | 5프레임 | 입에서 캔 음료를 연발 기관총처럼 사격 |
| 3 | death | 4프레임 | 섀시가 찌그러지며 붕괴 후 완벽한 파란 캔 1개 딸깍 사출 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), solid bulky red retro beverage vending machine mimic monster filling the 128x128 cell width and height, front display showing miniature soda cans, opening jagged metal teeth mouth from dispensing slot, firing projectile soda cans like a machine gun, popping out one blue soda can, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 4 rows on solid magenta #FF00FF background. Row 1: idle (2 frames), Row 2: awaken (3 frames), Row 3: attack (5 frames), Row 4: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:1
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 320×384 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/rogue_vending_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/rogue_vending_v1.png`

```
</details>

---

### 👾 하수구 킹 (Sewer King) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1024×640px` (8열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__sewer_king/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sewer_king/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sewer_king/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 하수구 킹 (Sewer King) 👑 [보스]
- **서식 구역**: 지하 1층 배수 펌프실 오수 처리조
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  지하 오폐수에서 돌연변이를 일으킨 2.5등신 묵직하고 거대한 슬러지 왕 보스. 128×128 셀의 좌우를 꽉 채우는 뚱뚱하고 굵은 진흙 덩어리 몸통에 녹슨 쇠파이프 왕관을 쓰고, 녹슨 공업용 밸브 렌치를 휘두르며 오염된 산성 폐수를 뿜어낸다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1024×640px PNG** (셀 단위: 128×128px, 8열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 진흙 슬러지 몸통을 출렁이며 녹슨 파이프 왕관을 고쳐 씀 |
| 1 | walk | 6프레임 | 바닥에 오염수를 흘리며 육중하게 기어가는 보행 |
| 2 | attack | 8프레임 | 거대 밸브 렌치 강타 + 부식성 폐수 구토 탄막 방출 |
| 3 | hurt | 3프레임 | 진흙 슬러지가 튀며 움찔하는 피격 |
| 4 | death | 6프레임 | 왕관이 벗겨져 떨어지고 슬러지가 바닥 배수구로 흘러내려 소멸 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), heavy bulky 2.5 heads tall sewer sludge king boss filling the frame, wide plump toxic slime body covered in dark campus waste debris, wearing heavy rusted steel pipe crown, holding massive rusty brass valve wrench, spitting acidic sewage vomit, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (6 frames), Row 3: attack (8 frames), Row 4: hurt (3 frames), Row 5: death (6 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 16:9
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1024×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/sewer_king_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/sewer_king_v1.png`

```
</details>

---

### 👾 홀 머더 (Hall Mother) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1024×640px` (8열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__hall_mother/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__hall_mother/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__hall_mother/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 홀 머더 (Hall Mother) 👑 [보스]
- **서식 구역**: 1층 학생회관 대강당 중앙 무대
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  대강당의 붉은 벨벳 커튼과 무대 조명이 융합된 2.5등신 풍성하고 위압적인 무대 유령 보스. 128×128 셀 폭을 가득 채우는 풍성한 붉은 벨벳 드레스 자락을 나풀거리며 무대 위를 부유하고, 머리 뒤로 대형 할로겐 조명 후광이 빛나며 스포트라이트 섬광과 하울링 음파를 발산한다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1024×640px PNG** (셀 단위: 128×128px, 8열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 풍성한 붉은 벨벳 커튼 자락을 펄럭이며 공중 부유 |
| 1 | walk | 6프레임 | 무대 위를 미끄러지듯 유영하는 이동 |
| 2 | attack | 8프레임 | 마이크를 치켜들고 초음파 하울링 스크림 + 스포트라이트 레이저 폭격 |
| 3 | hurt | 3프레임 | 조명 전구가 깜빡이며 벨벳 자락이 찢어짐 |
| 4 | death | 6프레임 | 조명이 펑 터지며 암전되고 붉은 커튼이 무대 바닥으로 낙하 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), voluminous 2.5 heads tall theatrical ghost mother boss made of wide billowing crimson velvet stage curtains filling the cell width, glowing halogen stage spotlight halo behind head, brass microphone stand scepter, floating gracefully emitting blinding spotlights and acoustic screams, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (6 frames), Row 3: attack (8 frames), Row 4: hurt (3 frames), Row 5: death (6 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 16:9
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1024×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/hall_mother_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/hall_mother_v1.png`

```
</details>

---

### 👾 CRT 오버시어 (CRT Overseer) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1024×640px` (8열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__crt_overseer/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__crt_overseer/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__crt_overseer/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: CRT 오버시어 (CRT Overseer) 👑 [보스]
- **서식 구역**: 2층 전산 실습실 중앙 제어 데스크
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  구형 CRT 모니터들이 굵은 케이블 덩굴로 빽빽하게 엮여 128×128 셀을 가득 채우는 2.5등신 군체 보스. 메인 중앙 모니터에 거대한 녹색 디지털 눈동자가 노려보고, 주변의 보조 모니터들이 굵직한 케이블로 뻗어나와 음극선관 전자총 레이저를 발사한다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1024×640px PNG** (셀 단위: 128×128px, 8열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 중앙 녹색 인광 눈동자가 좌우를 주시하며 주변 모니터 부유 |
| 1 | walk | 6프레임 | 케이블 촉수를 짚으며 공중을 부유 이동 |
| 2 | attack | 8프레임 | 전체 모니터에서 녹색 전자빔 레이저 집중 일제 사격 |
| 3 | hurt | 3프레임 | 모니터 유리에 방사형 금이 가며 화면 노이즈 발생 |
| 4 | death | 6프레임 | 유리 브라운관이 펑 폭발하고 케이블 더미로 추락 소멸 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), dense cluster boss monster of vintage beige CRT computer monitors connected by thick black video cables filling the frame, glowing green phosphor eye on central screen, firing scanning cathode-ray electron beam lasers, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (6 frames), Row 3: attack (8 frames), Row 4: hurt (3 frames), Row 5: death (6 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 16:9
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1024×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/crt_overseer_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/crt_overseer_v1.png`

```
</details>

---

### 👾 플라스크 타이탄 (Flask Titan) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1024×640px` (8열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__flask_titan/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__flask_titan/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__flask_titan/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 플라스크 타이탄 (Flask Titan) 👑 [보스]
- **서식 구역**: 3층 화학공학과 실험실 (화학 약품 보관 구역)
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  삼각 플라스크와 둥근 바닥 플라스크들이 융합되어 128×128 셀을 묵직하게 꽉 채우는 2.5등신 거대 화학 골렘 보스. 두껍고 묵직한 강화 유리 몸통 안통으로 보글보글 끓어오르는 맹독성 에메랄드 그린과 바이올렛 화학 액체가 찰랑이고, 굵직한 코르크 마개 관절과 배기 유리관에서 쉭쉭 화학 증기를 뿜어낸다. 커다랗고 육중한 플라스크 주먹을 내리찍고 산성 액체와 부식성 가스를 분사한다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1024×640px PNG** (셀 단위: 128×128px, 8열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 묵직한 플라스크 내부에서 화학 액체와 기포가 끓어오르며 호흡 |
| 1 | walk | 6프레임 | 굵은 유리 다리로 쿵쾅거리며 액체를 출렁이는 육중한 보행 |
| 2 | attack | 8프레임 | 거대한 플라스크 주먹 내려찍기 + 산성 화학 증기 폭발 분사 |
| 3 | hurt | 3프레임 | 몸체 유리에 미세한 크랙 발생 및 산성 액체 튐 |
| 4 | death | 6프레임 | 유리 플라스크가 완전히 파열되며 유독 액체 범람 및 증기 폭발 산화 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), massive bulky 2.5 heads tall chemical golem boss fused with heavy laboratory glass chemistry flasks filling the frame, heavy glass torso bubbling with toxic emerald green and acidic purple boiling liquid inside, thick cork stopper joints and steaming glass condenser chimneys, heavy glass fists splashing acid vapor, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (6 frames), Row 3: attack (8 frames), Row 4: hurt (3 frames), Row 5: death (6 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 16:9
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1024×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/flask_titan_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/flask_titan_v1.png`

```
</details>

---

### 👾 볼트 와이럼 (Volt Wyrm) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1024×640px` (8열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__volt_wyrm/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__volt_wyrm/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__volt_wyrm/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 볼트 와이럼 (Volt Wyrm) 👑 [보스]
- **서식 구역**: 4층 전자공학과 메인 배전실 / 고전압 실험실
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  수백 가닥의 굵은 산업용 고전압 전선, 동축 케이블, 콘센트 플러그가 똬리를 틀어 128×128 셀을 가득 메우는 2.5등신 전기 용 보스. 큼직하고 각진 머리에 황동 플러그 단자가 날카로운 송곳니 역할을 하며, 굵고 두꺼운 전선 몸통 사이로 노란색/시안색 고전압 스파크 아크가 파지직 방전된다. 바닥을 지그재그로 기어오며 10,000볼트 번개 브레스를 뿜어낸다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1024×640px PNG** (셀 단위: 128×128px, 8열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 두꺼운 전선 몸통을 꿈틀거리며 노란 전기 아크 방전 |
| 1 | walk | 6프레임 | 지그재그로 바닥을 기어가며 굵은 전선 케이블 파동 |
| 2 | attack | 8프레임 | 플러그 송곳니 개방 + 10,000V 고전압 번개 브레스 방출 |
| 3 | hurt | 3프레임 | 피복이 벗겨지며 합선 불꽃과 검은 연기 발생 |
| 4 | death | 6프레임 | 전기 단락 대폭발 후 힘을 잃고 흩어진 잔류 전선 더미로 붕괴 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), massive bulky 2.5 heads tall mechanical electric dragon wyrm boss composed of thick bundled high-voltage industrial power cables filling the frame, heavy outlet plug dragon head with sharp brass prong fangs, crackling neon yellow and cyan lightning electrical arcs surging through heavy copper cables, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (6 frames), Row 3: attack (8 frames), Row 4: hurt (3 frames), Row 5: death (6 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 16:9
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1024×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/volt_wyrm_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/volt_wyrm_v1.png`

```
</details>

---

### 👾 모교수 괴물 (Professor Monster - Mutation) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `640×640px` (5열 × 5행, 셀 128px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__professor_monster/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__professor_monster/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__professor_monster/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: 모교수 괴물 (Professor Monster - Mutation) 👑 [보스]
- **서식 구역**: 5층 대학원 연구동 제1연구실 (씬 5-1 제압전)
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  연구실의 광기에 잠식되어 128×128 셀을 위압적으로 채우는 2.5등신 변이 교수 보스. 큼직한 머리에 찢어진 하얀 연구원 실험복, 비틀린 넥타이와 금이 간 반사 안경 너머로 번뜩이는 붉은 눈. 굵고 날카로운 분필 칼날 손톱을 휘둘러 칠판을 긁는 듯한 살인적인 충격파를 발생시킨다. 제압당하면 인간성을 되찾으며 무릎을 꿇는다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **640×640px PNG** (셀 단위: 128×128px, 5열 × 5행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 비틀거리는 자세로 거칠게 숨을 몰아쉬는 기괴한 대기 |
| 1 | walk | 4프레임 | 한쪽 다리를 끌며 위압적으로 성큼성큼 다가오는 보행 |
| 2 | attack | 5프레임 | 분필 손톱으로 공기를 가르며 날카로운 분필 가루 충격파 궤적 방출 |
| 3 | hurt | 2프레임 | 안경이 비틀거리며 피격 충격으로 휘청임 |
| 4 | death | 4프레임 | 손에서 연구 교안을 떨어뜨리고 무릎을 꿇으며 변이가 풀리는 제압 모션 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), bulky 2.5 heads tall mutated university professor boss monster filling the frame, tattered white research lab coat, oversized head with crooked necktie, shattered reflective eyeglasses with glowing red eyes, elongated chalk blade monster claws scratching shockwaves in air, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 5 columns by 5 rows on solid magenta #FF00FF background. Row 1: idle (4 frames), Row 2: walk (4 frames), Row 3: attack (5 frames), Row 4: hurt (2 frames), Row 5: death (4 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:1
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 640×640 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/professor_monster_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/professor_monster_v1.png`

```
</details>

---

### 👾 SYS_BUILDER.EXE (최종 시스템 빌더 보스) 👑 [보스]
- **스타일**: 2.5~3등신 SD 클래식 JRPG 도트 픽셀아트 (셀 75~88% 꽉 채우는 볼륨감)
- **규격**: `1536×1152px` (8열 × 6행, 셀 192px)
- **폴더 경로**: [`assets/raw/llm/_batch/0830_1133/monsters__sys_builder/`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sys_builder/)
- **전용 웹 프롬프트 파일**: [`웹붙여넣기.md`](file:///D:/Game/busidol/remakes/sidol_godot/assets/raw/llm/_batch/0830_1133/monsters__sys_builder/%EC%9B%B9%EB%B6%99%EC%97%AC%EB%84%A3%EA%B8%B0.md)

<details>
<summary>📋 [클릭하여 볼륨감 있는 SD 픽셀아트 웹 프롬프트 펼치기]</summary>

```markdown
[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[화풍 & 픽셀 스타일 핵심 지침 — ★최우선 적용★]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 몬스터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, **128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~118px, 폭 80~112px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣**.
   - 얇거나 왜소하지 않고 굵직한 덩치감과 그로테스크한 존재감을 가진 몬스터 디자인.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Pixel Art / Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩(Color Ramping)과 격자 체커보드 디더링(Bayer Dithering)으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E / #10082E) 또는 짙은 암갈색 도트 테두리.
   - 색조 그림자: 단순 검정 음영 대신 남보라(#3A285C / #251840) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트 (90년대 DOS 팔레트 베이스의 따뜻하고 선명한 JRPG 채도).
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF (혼색·반투명·안티에일리어싱 금지).

## 👾 대상 몬스터: SYS_BUILDER.EXE (최종 시스템 빌더 보스) 👑 [보스]
- **서식 구역**: 5층 전산 서버실 메인프레임 심장부 (최종 결전)
- **디자인 콘셉트 & 볼륨감 있는 실루엣**:
  캠퍼스 제어 시스템이 실체화한 2.5등신 거대 중장갑 메인프레임 보스. 192×192 대형 셀을 묵직하게 채우는 서버 랙 캐비닛, 점멸하는 LED 어레이, 거대한 백업 테이프 릴과 굵직한 리본 케이블 유압 팔이 결합된 거대 시스템 구조체. CRT 화면에 FATAL ERROR를 띄우며 컴파일 레이저를 전방위로 난사한다.

## 📐 출력 규격 (그리드 계약 — 엄격 준수)
- **시트 캔버스 크기**: **1536×1152px PNG** (셀 단위: 192×192px, 8열 × 6행) — 크기 정확 일치
- **행별 애니메이션 프레임 배치** (좌 ➔ 우가 재생 순서):

| 행 | 애니메이션 이름 | 프레임 수 | 세부 동작 묘사 |
|:---:|:---:|:---:|:---|
| 0 | idle | 4프레임 | 서버 LED가 주기적으로 점멸하며 테이프 릴 회전 대기 |
| 1 | walk | 4프레임 | 유압 케이블 리프트로 육중하게 쿵쾅거리며 위치 이동 |
| 2 | attack | 8프레임 | CRT 화면에 FATAL ERROR 점멸 + 전방위 컴파일 레이저 일제 사격 |
| 3 | hurt | 3프레임 | 서버 섀시에서 불꽃이 튀며 패널이 찌그러짐 |
| 4 | death | 6프레임 | 시스템 종료 블루스크린 출력 후 연쇄 폭발 및 섀시 다운 |

- 프레임 수는 행별로 정확히 배치하고, **남는 빈 셀은 완전 투명(alpha=0)** 으로 둔다.
- 각 셀 내부에서 몬스터는 **가로 중앙(Center), 세로 바닥(Bottom 접지 여백 8~14px)** 에 정렬하며, 셀 영역을 넉넉히 채우도록 그린다.
- 프레임 간 캐릭터의 머리 크기, 팔레트 색상, 볼륨감 일관성을 엄격히 유지한다.
- 배경: **마젠타 #FF00FF 단색** 또는 **완전 투명 PNG**.

---

## 🌐 Midjourney / DALL-E / 영문 생성기 복사용 프롬프트
```text
16-bit retro JRPG monster pixel art sprite sheet, super deformed 2.5 heads tall bulky proportions filling the 128x128 cell with substantial volume and presence (Zwei / Arcturus / Narsillion 1990s retro sprite style), massive heavy mainframe system builder core boss monster filling the cell frame, industrial 1990s server rack cabinets, blinking amber LED arrays, central CRT terminal face displaying fatal crash errors, heavy magnetic tape reels and chunky ribbon cable mechanical arms, authentic chunky dot matrix pixel art, crisp 1px dark indigo pixel outline #0A082E, 4-6 tone discrete color step banding, classic dithered shading, vibrant retro JRPG color palette. Complete animation sprite sheet grid in 8 columns by 6 rows on solid magenta #FF00FF background. Row 1: idle_phase1 (4 frames), Row 2: idle_phase2 (6 frames), Row 3: idle_phase3 (8 frames), Row 4: attack (8 frames), Row 5: hurt (3 frames), Row 6: death (8 frames). Pure pixel art asset, perfect uniform grid, no antialiasing, no vector graphics, no 3d render, no smooth gradients, no blur, no text, no watermark --ar 1:1
```

---
## 💡 사람용 사용법 (웹 LLM에 복사할 때)

1. **ChatGPT-4o / Claude 3.5 Sonnet / Gemini Web** 채팅창에 위 본문을 **그대로 복사하여 붙여넣습니다**.
2. 같은 폴더에서 아래 이미지를 함께 첨부합니다:
   - `1. grid_template.png` — 정확한 1536×1152 규격의 캔버스 템플릿
   - `2. style_ref.png` — 기존 게임 도트 화풍/정렬 기준
   - `3. subpalette.png` — 권장 컬러 팔레트 스왑치
   - `4. orig_enemy_1.png` — 원작/참조 콘셉트 이미지
3. 생성된 이미지를 다운로드하여 아래 경로에 저장합니다:
   - **저장 경로**: `assets/raw/llm/10_submitted/monsters/sys_builder_v1.png` (재납품 시 _v2, _v3)
4. 검증 명령어: `python tools/convert/validate_monster_sheet.py assets/raw/llm/10_submitted/monsters/sys_builder_v1.png`

```
</details>

---
