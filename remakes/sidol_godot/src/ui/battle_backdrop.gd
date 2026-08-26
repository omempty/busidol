class_name BattleBackdrop
extends CanvasLayer
## 전투 배경 — 벽면 + 지평선 + 원근 바닥.
##
## 원작에는 전투 배경이 없었다(검은 화면 위에 스프라이트만). `M-R-*.PCX`·`I-V-*.PCX`는
## 배경이 아니라 **적 등장 일러스트**다 — 포맷 명세의 "전투 배경 추정"은 오독이었다.
## 그래서 이식이 아니라 설계다. 목표는 둘:
##   1) 캐릭터가 허공에 뜬 것처럼 보이지 않게 **바닥면**을 준다
##   2) 층마다 색조를 바꿔 "지금 어디서 싸우는가"를 배경이 말하게 한다
##
## 도트 아트와 톤을 맞추기 위해 그라데이션 대신 **단색 밴딩 + 1px 라인**만 쓴다.
## 액터 배치(BattlePresenter: 플레이어 y=220, 적 y=180)를 고려해 지평선을 그 사이에 둔다.

## 지평선 y — **모든 액터의 머리 위**여야 한다. 액터 사이에 두면 걸레받이 선이
## 몸통을 가로질러 오히려 어색해진다(적 스프라이트 상단 ≈ y116, BattlePresenter y=180 중심).
## 벽이 좁고 바닥이 넓은 구도는 JRPG 전투 화면의 표준이기도 하다.
const HORIZON := 108.0
const SKIRTING := 6.0  # 걸레받이 두께
const FLOOR_LINES := 9
const WALL_PANELS := 8  # 벽 세로 패널 라인 — 실내감
const VIEW := Vector2(960, 540)

## 층별 색조 — (벽, 바닥, 강조). 마스터 시나리오 §1.2의 층 톤 곡선을 따른다.
## UI 크롬이라 소스 상수로 둔다(HudTheme과 같은 취급).
const FLOOR_TINTS := {
	0: [Color(0.13, 0.11, 0.10), Color(0.19, 0.16, 0.13), Color(0.44, 0.33, 0.22)],
	1: [Color(0.16, 0.11, 0.09), Color(0.22, 0.15, 0.12), Color(0.62, 0.34, 0.16)],
	2: [Color(0.09, 0.13, 0.16), Color(0.12, 0.18, 0.22), Color(0.29, 0.55, 0.62)],
	3: [Color(0.09, 0.14, 0.11), Color(0.12, 0.19, 0.15), Color(0.33, 0.58, 0.38)],
	4: [Color(0.12, 0.10, 0.18), Color(0.16, 0.14, 0.24), Color(0.48, 0.40, 0.76)],
	5: [Color(0.15, 0.09, 0.11), Color(0.20, 0.12, 0.14), Color(0.68, 0.26, 0.26)],
}
const FALLBACK_TINT := [Color(0.10, 0.10, 0.14), Color(0.14, 0.14, 0.19), Color(0.40, 0.40, 0.52)]


func build(floor_no: int) -> void:
	# 전용 하위 레이어(-1) — 이 배경이 월드 스프라이트(BattlePresenter, layer 0)를 덮으면 안 된다.
	layer = -1
	var tint: Array = FLOOR_TINTS.get(floor_no, FALLBACK_TINT)
	var wall: Color = tint[0]
	var floor_color: Color = tint[1]
	var accent: Color = tint[2]

	# 벽 — 위로 갈수록 어두운 3밴드. 그라데이션 대신 밴딩으로 도트 톤 유지.
	for i in 3:
		var band := ColorRect.new()
		band.color = wall.darkened(0.18 * float(2 - i))
		band.position = Vector2(0, HORIZON / 3.0 * float(i))
		band.size = Vector2(VIEW.x, HORIZON / 3.0 + 1.0)
		add_child(band)

	# 벽 세로 패널 라인 — 밋밋한 단색 벽에 실내 구조를 준다.
	for i in range(1, WALL_PANELS):
		var post := ColorRect.new()
		post.color = Color(accent, 0.10)
		post.position = Vector2(VIEW.x / float(WALL_PANELS) * float(i), 0)
		post.size = Vector2(1, HORIZON - SKIRTING)
		add_child(post)

	# 바닥
	var ground := ColorRect.new()
	ground.color = floor_color
	ground.position = Vector2(0, HORIZON)
	ground.size = Vector2(VIEW.x, VIEW.y - HORIZON)
	add_child(ground)

	# 걸레받이 — 벽과 바닥이 만나는 선. 여기가 있어야 액터가 바닥에 선 것으로 읽힌다.
	var skirt := ColorRect.new()
	skirt.color = accent.darkened(0.35)
	skirt.position = Vector2(0, HORIZON - SKIRTING)
	skirt.size = Vector2(VIEW.x, SKIRTING)
	add_child(skirt)

	_build_floor_lines(accent)


## 바닥 가로선 — 아래로 갈수록 간격이 벌어지고 옅어진다(원근).
## 세로 수렴선은 도트 해상도에서 계단이 심해 쓰지 않는다.
func _build_floor_lines(accent: Color) -> void:
	var depth := VIEW.y - HORIZON
	for i in range(1, FLOOR_LINES + 1):
		var t := float(i) / float(FLOOR_LINES)
		var line := ColorRect.new()
		line.color = Color(accent, 0.30 * (1.0 - t * 0.55))
		line.position = Vector2(0, HORIZON + depth * t * t)
		line.size = Vector2(VIEW.x, 1.0)
		add_child(line)
