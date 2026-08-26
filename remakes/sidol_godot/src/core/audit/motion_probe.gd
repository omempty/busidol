class_name MotionProbe
extends RefCounted
## 이동 프루브 — 실제로 몇 틱 굴려 보고 액터가 규칙을 지키는지 본다.
##
## 실제 회귀 근거(2026-08-26): EnemyManager의 통행 판정이 점유 사전만 봐서
## 몬스터가 벽과 맵 밖을 자유로이 통과했고, 행동 주기 게이트가 없어 매 물리 프레임
## 순간이동해 초당 60칸을 갔다. 정적 검사로는 잡을 수 없는 부류 — 굴려 봐야 보인다.

## 한 틱에 허용되는 최대 이동(셀). 워프 패턴(BURROW/TELEPORT)은 설계된 예외지만
## 무제한은 아니다 — EnemyManager.MAX_WARP까지만 허용한다.
const MAX_STEP := 1


## 스냅샷: 몬스터별 {cell, species}
static func snapshot(enemies: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: EnemyEntity in enemies:
		if is_instance_valid(e):
			out.append({"id": String(e.species_id), "cell": e.mover.grid_pos, "ref": e})
	return out


## 이번 틱에서 규칙 위반이 있었는가.
## warp_species: 순간이동이 설계인 종 · phase_species: 벽 통과가 설계인 종.
static func check_tick(
	rep: AuditReport,
	rt: MapRuntime,
	before: Array[Dictionary],
	warp_species: Dictionary,
	phase_species: Dictionary
) -> void:
	for b: Dictionary in before:
		var e: EnemyEntity = b["ref"]
		if not is_instance_valid(e):
			continue
		var from: Vector2i = b["cell"]
		var to: Vector2i = e.mover.grid_pos
		var d := to - from
		var dist := absi(d.x) + absi(d.y)
		if dist > MAX_STEP:
			if not warp_species.has(b["id"]):
				rep.fail("한 틱 과다 이동", "%s %s -> %s (%d셀)" % [b["id"], from, to, dist])
			elif dist > EnemyManager.MAX_WARP:
				rep.fail("워프 거리 초과", "%s %s -> %s (%d셀)" % [b["id"], from, to, dist])
		if not Placement.body_fits(rt, to) and not phase_species.has(b["id"]):
			rep.fail("지형 침범", "%s 몸이 통행 불가 셀에 있음 @%s" % [b["id"], to])
		if not rt.definition.in_bounds(to):
			rep.fail("맵 밖 이탈", "%s @%s" % [b["id"], to])


## 시뮬레이션 전체 결과 — 몬스터가 아예 안 움직였다면 그것도 이상이다.
## 워프 종이 플레이어 몸에 맞닿는 자리로 착지하면 회피 불가 전투가 된다.
static func check_warp_landing(
	rep: AuditReport, before: Array[Dictionary], player_cell: Vector2i, warp_species: Dictionary
) -> void:
	for b: Dictionary in before:
		var e: EnemyEntity = b["ref"]
		if not is_instance_valid(e) or not warp_species.has(b["id"]):
			continue
		var moved: int = (
			absi(e.mover.grid_pos.x - b["cell"].x) + absi(e.mover.grid_pos.y - b["cell"].y)
		)
		if moved > MAX_STEP and Placement.bodies_touch(player_cell, e.mover.grid_pos):
			rep.fail("워프 즉시 접촉", "%s가 플레이어에 맞닿게 출현 @%s" % [b["id"], e.mover.grid_pos])


static func check_activity(rep: AuditReport, moved: int, ticks: int, enemies: int) -> void:
	if enemies == 0:
		rep.ok("몬스터 활동", "이 층 몬스터 없음")
		return
	if moved == 0:
		rep.warn("몬스터 정지", "%d틱 동안 아무도 움직이지 않음(AI/주기 점검)" % ticks)
	else:
		rep.ok("몬스터 활동", "%d틱 동안 %d회 이동" % [ticks, moved])


## 접촉 판정이 대칭인가 — 원작의 x±1·y±2 비대칭 회귀 방지.
static func check_contact_symmetry(rep: AuditReport) -> void:
	var origin := Vector2i.ZERO
	var cases := {
		"오른쪽 맞닿음": Vector2i(2, 0),
		"왼쪽 맞닿음": Vector2i(-2, 0),
		"아래 맞닿음": Vector2i(0, 2),
		"위 맞닿음": Vector2i(0, -2),
	}
	for name: String in cases:
		if not Placement.bodies_touch(origin, cases[name]):
			rep.fail("접촉 비대칭", "%s(%s)가 접촉으로 판정되지 않음" % [name, cases[name]])
	# 모서리만 스치는 배치는 접촉이 아니다 — 대각선으로 빠져나갈 여지를 남긴다.
	if Placement.bodies_touch(origin, Vector2i(2, 2)):
		rep.fail("접촉 과판정", "모서리만 스친 (2,2)를 접촉으로 판정")
	if Placement.bodies_touch(origin, Vector2i(3, 0)):
		rep.fail("접촉 과판정", "한 칸 떨어진 (3,0)을 접촉으로 판정")
	rep.ok("접촉 판정", "4방향 대칭 · 모서리/이격 제외")
