class_name HudTheme
## HUD/필드 오버레이 공용 팔레트·스타일박스 — 패널·게이지·칩이 한 규격을 쓰게 하는 단일 출처.
## UI 크롬 색은 게임 콘텐츠가 아니므로 소스 상수로 둔다(AGENTS.md 콘텐츠 하드코딩 금지 대상 아님).
## 근거: docs/02_design/04_uiux_modernization.md §1 — 어두운 반투명 카드 + 라운드 + 얇은 테두리.

const BG := Color(0.055, 0.065, 0.088, 0.9)
const BG_SUNKEN := Color(0.0, 0.0, 0.0, 0.45)
const BORDER := Color(1, 1, 1, 0.09)
const SHADOW := Color(0, 0, 0, 0.45)

const TEXT := Color(0.91, 0.93, 0.97)
const TEXT_MUTED := Color(0.62, 0.66, 0.74)
const TEXT_ON_ACCENT := Color(0.09, 0.08, 0.05)

const ACCENT := Color(0.99, 0.76, 0.31)  # 층 배지 · 골드
const HP_OK := Color(0.29, 0.84, 0.5)
const HP_WARN := Color(0.98, 0.75, 0.18)
const HP_LOW := Color(0.94, 0.38, 0.36)
const EXP := Color(0.4, 0.63, 0.96)
const EQUIPPED := Color(0.5, 0.85, 0.56)  # 장착 중 표시
const BREAK_ON := Color(1.0, 0.45, 0.2)  # 브레이크 성립 — 약점을 찔렀다는 신호
const TRACK := Color(1, 1, 1, 0.16)  # 게이지 빈 칸 — 어두운 카드 위에서도 형태가 남는다
const ROW_SELECTED := Color(1, 1, 1, 0.08)  # 목록에서 선택된 줄의 바탕

const HP_WARN_AT := 0.5
const HP_LOW_AT := 0.25


## 카드 배경 — 어두운 반투명 + 얇은 테두리 + 드롭섀도.
static func panel(radius: int = 10, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	return sb


## 게이지 홈(빈 부분) — 배경보다 더 어둡게 파인 느낌.
static func sunken(radius: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_SUNKEN
	sb.set_corner_radius_all(radius)
	return sb


## 게이지 채움 / 칩 배경.
static func fill(color: Color, radius: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


## 라운드 칩(층 배지·키캡) — 안쪽 여백 포함.
static func chip(color: Color, radius: int = 6, pad_x: int = 7, pad_y: int = 2) -> StyleBoxFlat:
	var sb := fill(color, radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## 제목 아래 얇은 구분선 — 모달 헤더와 본문을 가른다.
static func rule() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BORDER
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## 게이지 채움 위에 얹는 글자 — 초록/노랑/파랑 어디에 올라가도 읽히도록 검은 외곽선.
static func outlined_label(text: String, size: int, color: Color) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


## HP 비율 → 게이지 색. 절반/사분의 일에서 단계적으로 경고색.
## HP 단계 → 무늬 번호(HudGauge.Pattern과 같은 값). 색과 **같은 경계**를 쓴다 —
## 둘이 어긋나면 색은 빨간데 무늬는 주의로 보이는 자리가 생긴다.
static func hp_pattern(ratio: float) -> int:
	if ratio < HP_LOW_AT:
		return 2  # 교차 = 위험
	if ratio < HP_WARN_AT:
		return 1  # 사선 = 주의
	return 0


static func hp_color(ratio: float) -> Color:
	if ratio < HP_LOW_AT:
		return HP_LOW
	if ratio < HP_WARN_AT:
		return HP_WARN
	return HP_OK


## 화폐 표기 — 단위는 "온"(items.json의 100온/500온/1000온이 정본).
## HUD·전투 보상·상점이 같은 문자열을 쓰게 하는 단일 출처.
static func money(value: int) -> String:
	return String(TranslationServer.translate("UI_HUD_MONEY_UNIT")) % grouped(value)


## 천 단위 구분 — 자릿수가 커지는 수치의 가독성.
static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out
