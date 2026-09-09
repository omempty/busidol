# 셀 편집기 18차 세션 인수인계 (2026-09-08)

`tools/review/sprite_fixer.html` + `tools/convert/sheet_ops.py` + `tools/review/review_server.py`.
**전부 워킹트리에 있고 커밋하지 않았다.** 같은 트리에서 F1 이벤트 작업이 병행됐으니
커밋할 때 파일을 갈라서 묶어라(아래 §6).

메모리 정본: `C:/Users/user/.claude/projects/D--Game-busidol/memory/cell-editor-contract-is-everything.md`

---

## 1. 이번에 한 것

### 헤더 정리 (요청 1)
한 줄에 섞여 있던 도구/브러시/보기/저장을 두 줄로 갈랐다.

- 1줄 = 문서: `파일`(카테고리·파일·**계약**·열기·원본복구) | 상태·배지 | `저장`
- 2줄 = 편집: `도구` | `브러시` | `편집`(되돌리기) | `보기`
- 아이콘 12종을 `<symbol>` 하나에 모아 `<use>`로 꽂았다(`currentColor` → 눌린 도구에서 같이 밝아진다).
- **`main{height:calc(100vh - 47px)}`의 매직넘버를 없앴다** — body를 flex 기둥으로 세웠다.
  실측: 1600px 헤더 82 / main 818, 1100px 헤더 118 / main 682, 둘 다 페이지 스크롤 0.

### 자동 보정·픽셀풍 (요청 2)
픽셀 규칙은 규약대로 전부 `sheet_ops.py`(정본)에 있고 편집기는 왕복만 한다.

| 새 연산 | 하는 일 |
|---|---|
| `key_background` / `autokey` | 가장자리에서 배경색·허용오차를 스스로 재고 **색이 아니라 연결성**으로 지운다. 그림 안쪽의 흰자·하이라이트가 안 뚫린다. 칸에 갇힌 배경은 셀 경계도 씨앗으로 쓰되 **그림이 덮은 경계선은 뺀다** |
| `pixelize` | 블록 **최빈색**(평균색이 아니다 — 평균은 원본에 없던 중간색을 만든다). 레벨은 셀 크기의 약수로 당긴다 |
| `refit` | **행별 재배치**. 생성 모델이 행마다 다른 간격으로 그려 온 시트를 계약 격자에 다시 앉힌다. 공통 축척 하나 |
| `autoprep` | 파일을 여는 순간 크기+배경만 맞춘다(그림을 지우는 연산은 안 넣는다). 되돌리기 가능 |
| `detail_ratio` / `suggest_pixel_level` | '너무 세밀한가'를 재서 계측 패널에 띄운다 |

### 계약 연결 (요청 3~5)
- `GET /api/fixer/assets` — 계약 있는 에셋 37종 목록.
- `GET /api/fixer/contract?...&asset=` — **파일명 대신 지정한 에셋으로** 계약을 찾는다.
- 헤더 **[계약] 드롭다운**. 로컬 그림을 열 때 이미 걸린 계약을 유지한다.
- `contractSize()` — 계약 유무를 `cell`이 아니라 `size`로 판단(keyart는 cell 0인데 size가 있다).
- `toast()` — 기록(#log)이 우측 패널 맨 아래라 안 보이던 문제. 실패·경고는 화면 위에 뜬다.
- 저장: 로컬 파일이라도 계약이 붙었으면 **다음 버전으로 저장**이 된다.
  `next_file`은 **디스크의 최대 버전 + 1**(예전엔 열어 둔 파일명에서 뽑아 v4가 있는데 v2로 떨어졌다).

---

## 2. 이번에 잡은 결함 (전부 재현 후 수정)

1. **[크기 자동 조절] 버튼이 죽어 있었다** — `data-op`만 있고 `OPS`에 처리기가 없었다(직전 커밋부터).
   이 저장소 지배적 결함(사문화)이 UI에서 난 자리.
2. **keyart는 자동 조절이 통째로 건너뛰어졌다** — `autosize`가 `cols*cell`만 봤다.
   계측의 `sizeOk`도 같은 실수라 **틀린 크기가 초록으로 보였다**.
3. **웹 챗에서 받은 파일은 계약이 하나도 안 잡혔다** — 크기·격자·정렬이 한꺼번에 멎는다.
4. **저장이 조용히 거부됐다** — 로컬 파일이면 무조건 막고 안 보이는 기록에만 찍었다.
5. **저장 버튼 아이콘이 사라졌다** — `btn.textContent = "저장 중…"`이 SVG를 지웠다.
6. **`fixer_save`가 기존 파일을 덮을 수 있었다** — 이제 이름이 겹치면 번호를 올린다.

---

## 3. 새로 만든 검사 도구 (이게 이번 세션의 남는 자산이다)

**이 PC에 playwright(chromium)가 이미 깔려 있다.** 그동안 "브라우저 확장이 없어 못 눌러
봤다"로 검증이 비어 있었는데, 그럴 필요가 없었다.

```
py tools/review/fixer_check.py          # 정적: 태그 균형 · id 배선 · data-op↔OPS · 아이콘 · node --check
py tools/review/fixer_probe.py          # 실조작: 진짜 마우스 드래그(지우개·연필·되돌리기·단축키)
py tools/review/fixer_probe.py --server # 위 + review_server를 빈 포트에 띄워 왕복 전부
py tools/convert/test_sheet_ops.py      # 픽셀 규칙 실측(부정 시험 포함)
```

마지막 실측: `fixer_check 통과` / `test_sheet_ops 통과 43 실패 0` / `fixer_probe --server OK 25 실패 0`.

`fixer_check.py`는 **[크기 자동 조절]이 죽어 있던 그 결함**을 잡도록 만들었고,
일부러 배선을 빼서 빨개지는 것까지 확인했다(부정 시험).

---

## 4. 다음 세션이 이어받을 것

1. **유저가 실제로 저장까지 해 봐야 한다.** 마지막 상태에서 브라우저 새로고침(Ctrl+F5)만
   하고 세션이 끝났다. 순서: `셀편집기.bat monsters` → 그림 드롭 →
   [계약] 플라잉 논문 → [행별 재배치] → [다음 버전으로 저장](`flying_thesis_v5.png`).
   **검증 FAIL이 뜨면 그 내용부터 받아라** — 알림에 앞 4줄이 붙는다.
2. **축소 화질.** 1456→512는 2.8배 축소인데 NEAREST라 도트가 거칠다. `refit`도 NEAREST다.
   블록 최빈색 축소(비정수 배율)를 붙일지 결정할 것 — `pixelize`의 최빈색 machinery는 이미 있다.
3. **`refit`을 `autoprep`(열 때 자동 보정)에 넣을지.** 지금은 명시적 버튼이다.
   자동으로 돌리면 결과는 더 낫지만 여는 순간 그림이 재배치돼 놀랄 수 있어 보류했다.
   넣는다면 "선언한 프레임이 전부 비어 있지 않을 때만"이라는 안전장치를 함께.
4. **문서.** `docs/02_design/05_toolchain_editors.md`에 셀 편집기 항목이 아예 없다
   (`sprite_fixer`를 언급하는 문서는 HANDOFF.md뿐). 새 연산 5종과 [계약] 흐름을 적을 것.
5. **관문 편입.** `fixer_check`/`fixer_probe`/`test_sheet_ops`를 `tools/run_gates.ps1`에
   넣을지 결정. 관문 정본은 run_gates.ps1이다.

---

## 5. 함정 (같은 데 빠지지 말 것)

- **Bash 툴 heredoc이 백슬래시를 한 겹 먹는다.** 파이썬 소스 안의 `"\\n"`가 `"\n"`(진짜 개행)이 되어 패치 스크립트가 세 번 깨졌다. 이 문서를 쓰면서도 같은 자리에서 한 번 더 걸렸다.
  `BS = chr(92)`로 조립하거나 Write 툴을 쓸 것. (메모리 `windows-bat-ps1-encoding-traps`에 이미 있다.)
- **파이썬 도구에 `sys.stdout.reconfigure(encoding="utf-8")`를 넣어라.** 없으면 em대시 하나에 죽는다.
- **셀편집기.bat은 이미 떠 있는 서버를 재사용한다.** 서버 코드를 고쳤으면 `review-server` 창을
  닫고 다시 실행해야 한다. 옛 서버면 편집기가 "서버가 옛 버전이라 [계약] 목록을 못 받았다"고 띄운다.
- **판정 기준을 alpha로 잡지 말 것.** 배경이 불투명한 시트에서는 alpha로 '그렸는가'를 못 가른다.
  fixer_probe의 되돌리기 시험이 이것 때문에 한 번 거짓 실패했다.
- **`.row`는 flex라 `<b>`가 한 줄을 차지한다.** 힌트 문장은 `<span>` 하나로 묶어라.

---

## 6. 커밋할 때 (워킹트리가 두 작업으로 섞여 있다)

**셀 편집기 쪽 (이 문서):**
```
tools/review/sprite_fixer.html
tools/review/review_server.py
tools/convert/sheet_ops.py
tools/convert/test_sheet_ops.py
tools/review/fixer_check.py      (신규)
tools/review/fixer_probe.py      (신규)
docs/HANDOFF_CELL_EDITOR.md      (신규, 이 문서)
```

**F1 이벤트 쪽 (별도 작업 — `docs/HANDOFF_F1_EVENTS.md` 참조):**
`data/**`, `src/**`, `scenes/**`, `tools/validate.gd`, `tools/dev/autoplay.gd`,
`data/cutscenes/f1_*.json`, `data/maps/locks_f1.json`, `docs/HANDOFF.md`, 그 밖 docs.

**어느 쪽도 아닌 것(이전 세션에서 넘어온 미커밋):**
`assets/spec/portraits/member_*.json`, `tools/review/prompt_audit.py`.

Autoplay 관문이 빨간 것(걸어서 닿은 층 2 < 요구 5)은 **F1 이벤트 작업 쪽 소관**이다.
셀 편집기 변경과 무관하다.
