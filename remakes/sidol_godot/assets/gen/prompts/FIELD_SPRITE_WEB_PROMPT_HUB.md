> ## ⚠️ 이 문서는 대체되었다 → `python tools/convert/web_prompt.py`
>
> 손으로 쓴 허브라 정본과 갈라진다. 같은 계열 문서인
> [`MONSTER_WEB_PROMPT_HUB.md`](MONSTER_WEB_PROMPT_HUB.md)에서 실제로 그 사고가 났다
> (`mad_eye`를 `320×512(셀 64)`로 적었으나 정본은 `640×1024(셀 128)` — 그대로 그린
> 납품이 크기 위반으로 자동 반려됐다). **NPC 4종의 수치는 여기 적지 않고 정본에서 뽑는다:**
>
> ```
> python tools/convert/web_prompt.py npcs dev1     # dev2 · lab_student · afterschool_student도 같은 자리
> ```
>
> 2026-09-09 실측으로는 NPC 4종이 전부 **256×640px · 셀 128 · 2열 × 5행**
> (0~3행 walk_down/up/left/right 각 2칸 · 4행 idle_down 2칸)이다.
> 이 값은 **바뀔 수 있으니 그리기 직전에 위 명령으로 다시 확인하라.**
>
> - 공통 규약: [`WEB_PROMPT_COMMON.md`](WEB_PROMPT_COMMON.md) — 대화 맨 앞에 한 번
> - 시트 상세: [`web/npcs__<id>.md`](web/)
> - 사용법 전반: [`docs/TOOLS.md`](../../../docs/TOOLS.md)
>
> 아래 본문은 **콘셉트 서술과 화풍 지침 참고용**으로 남긴다.

# 🏃 BSD 시돌이의 모험 — 필드 스프라이트 (주인공 & NPC) 웹 프롬프트 허브

> **웹 브라우저의 생성형 AI(ChatGPT-4o / Claude 3.5 Sonnet / Midjourney v6 / Gemini Web)** 에
> 복사-붙여넣기하여 **2.5~3등신 SD 체형 + 셀을 꽉 채우는 볼륨감의 정통 16비트 JRPG 도트 캐릭터 시트**를 생성/리터칭하는 가이드입니다.

---

## 📌 공통 핵심 화풍 지침 (★최우선 적용★)

`markdown
[화풍 & 픽셀 스타일 핵심 지침]
1. ★ 2.5~3등신 SD 클래식 JRPG 체형 + 셀을 꽉 채우는 묵직한 볼륨감:
   - 팔콤 『쯔바이!!(Zwei!!)』, 『악튜러스』, 『나르실리온』 계열의 고전 명작 JRPG 캐릭터 도트 화풍.
   - 2.5~3등신 SD 체형 비율을 유지하되, 128×128px 셀의 가로/세로 영역(약 75~88% 면적, 실높이 100~115px, 폭 75~95px)을 묵직하고 밀도 있게 꽉 채우는 볼륨감 있는 바디 실루엣.
   - 왜소하거나 얇지 않고 큼직한 머리와 명확한 표정, 듬직한 상체와 안정감 있는 하체.
2. ★ 100% 순수 16비트 도트 픽셀 아트 (Pure Dot Matrix):
   - 3D CGI 렌더링, 벡터 그래픽(SVG), 수채화, 일러스트 브러시 질감 절대 금지!
   - 캔버스 확대 시 각진 픽셀 도트(Pixel Grid)가 한 땀 한 땀 뚜렷하게 보이는 정통 도트 그래픽.
   - 안티에일리어싱(AA), 블러, 부드러운 그라데이션 금지 ➔ 색당 4~6단계의 계단식 밴딩과 체커보드 디더링으로 명암 표현.
   - 1px 다크 아웃라인: 순수 블랙 대신 짙은 남색(#0A082E) 도트 테두리.
   - 색조 그림자: 단순 검정 대신 남보라(#3A285C) 계열의 깊이 있는 색조 그림자 적용.
   - 고유색: 24~48색 양자화 도트 팔레트.
   - 배경: 완전 투명(alpha=0) 또는 단색 마젠타 #FF00FF.
`

---

## 🏃 캐릭터별 웹 프롬프트 바로가기

### 1. 🧑‍🎓 주인공: 부싯돌 (SIDOL)
- **콘셉트**: 1995년 한국 공대 새내기 남학생. 잿빛 자켓 교복, 청바지, 흰 운동화, 손에 쥔 부싯돌.
- **규격 정본**: `assets/spec/sprites/player_sidol.json` — **셀 128 · 4열 × 8행 = 512×1024**
  (walk 4방향 × 4프레임 + idle 4방향 × 2프레임).

  2026-09-09에 정리했다. 그전에는 선언이 셋으로 갈라져 있었고 그중 둘이 틀렸다:
  낡은 `player_retouch_prompt.md`(2열 × 5행)와 `export_player_gen_package.py`
  독스트링(셀 64 · 256×512)이다. 굽던 생성기 둘은 지웠다 —
  하나는 **실행하면 죽었고**(`int(spec["cell"])`에 딕셔너리), 하나는 틀린 계약을 찍어 냈다.

- **의뢰 패키지 만들기**:
  ```
  python tools/convert/export_player_remaster_package.py
    -> assets/raw/llm/sprites/player_sidol/ (prompt.md + 원판 + 원작 프레임 8장 + 격자 + 서브팔레트)
  ```
  **신규 창작이 아니라 리터칭** 계약이다. `python tools/review/prompt_audit.py` 가
  이 패키지의 선언 숫자를 정본 스펙과 대조한다(108건 FAIL 0 · WARN 0 실측).

---

### 2. 💻 HP실 개발자 1 (dev1)
- **콘셉트**: 헐렁한 티셔츠, 헝클어진 머리, 3.5인치 플로피 디스켓과 캔커피를 든 밤샘 게임 개발자.
- **폴더 경로**: assets/raw/llm/_batch/0830_1133/npcs__dev1/

---

### 3. 🎨 HP실 개발자 2 (dev2)
- **콘셉트**: 둥근 안경, 소매를 걷은 셔츠, 방안지 모눈종이와 도트 스케치북을 든 그래픽 담당 여학생.
- **폴더 경로**: assets/raw/llm/_batch/0830_1133/npcs__dev2/

---

### 4. 🧪 화공과 실습생 (lab_student)
- **콘셉트**: 이마에 보안경을 걸치고 흰 실험 가운과 삼각 플라스크 시약병을 든 학생.
- **폴더 경로**: assets/raw/llm/_batch/0830_1133/npcs__lab_student/

---

### 5. 📚 야간 자습생 (afterschool_student)
- **콘셉트**: 두꺼운 전공서적을 끌어안고 뿔테 안경과 멜빵바지 차림으로 헐레벌떡 뛰어가는 야간 학생.
- **폴더 경로**: assets/raw/llm/_batch/0830_1133/npcs__afterschool_student/
