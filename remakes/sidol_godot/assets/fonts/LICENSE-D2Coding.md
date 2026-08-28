# `ui_main.ttf` — D2Coding 라이선스 고지

`ui_main.ttf`는 **D2Coding**(NHN)이며, 파일의 `name` 테이블에서 그대로 읽은 값은 아래와 같다.

| 항목 | 값 |
|---|---|
| 원본 파일명 | `D2Coding-Ver1.3.2-20180524.ttf` |
| Copyright (name id 0) | `Copyright (c) 2015-2016 NHN Corporation. All rights reserved. Font designed by FONTRIX Inc.` |
| License (name id 13) | `This Font Software is licensed under the SIL Open Font License, Version 1.1.` |
| License URL (name id 14) | `http://dev.naver.com/wiki/nanumfont/index.php/OpenFontLicense` |

폰트 자체는 수정하지 않았다. 파일 이름만 `ui_main.ttf`로 바꿨다
(`UiTheme`가 이 이름으로 찾는다). OFL의 Reserved Font Name 조항은 **폰트 내부 이름**에
적용되며 파일명 변경과는 무관하다 — 내부 이름은 그대로 `D2Coding`이다.

## ⚠ 배포 전에 해야 할 일

SIL Open Font License 1.1은 **라이선스 전문을 함께 배포할 것**을 요구한다.
이 파일은 고지일 뿐 전문이 아니다. 배포(빌드 배포·릴리스) 전에 위 URL 또는
D2Coding 공식 배포처에서 `OFL.txt` 전문을 받아 이 폴더에 `OFL.txt`로 넣을 것.

> 전문을 기억에 의존해 옮겨 적지 않았다. 라이선스 문서는 한 글자가 달라도 의미가 달라진다.

## 왜 이 폰트인가

- **OFL이라 게임에 번들할 수 있다.** 이전에는 시스템에 설치된 **굴림체**로 폴백하고 있었는데
  (부팅 로그 `[ui_theme] system 적용`), Microsoft 폰트라 배포본에 담을 수 없었다.
  즉 개발 PC에서 보이던 글꼴이 배포본에서는 재현되지 않는 상태였다.
- 고정폭이라 HP `50 / 176`, 소지금 `4,820온`처럼 **자릿수가 계속 바뀌는 HUD 수치**가
  좌우로 흔들리지 않는다.
- 전산과·DOS 소재(엔딩의 `C:\SIDOL> RUN.BAT` 콘솔 연출)와 터미널 고정폭의 톤이 맞는다.

## 더 나은 선택지

`04_uiux §2`가 요구한 것은 **픽셀 한글 폰트**이고, 32px 도트와 완전히 맞는 건 그것뿐이다.
OFL 픽셀 한글 폰트(Galmuri 계열 등)를 구해 `assets/fonts/ui_pixel.ttf`로 넣으면
**코드 변경 없이** 그쪽이 우선 적용된다(`UiTheme.FONT_STEMS` 순서). 그때 이 파일은
대체하거나 함께 두면 된다.
