class_name ActorProbe
extends RefCounted
## 액터 프루브 — 배치·시트 배정·애니 커버리지.
##
## 실제 회귀 근거(2026-08-26): NpcEntity._ready()가 setup()보다 먼저 돌아 npc_id가
## 빈 문자열일 때 시트를 찾는 바람에 전원이 주인공 얼굴로 나왔다. 게임은 정상 부팅하고
## 스모크도 통과했다 — "어떤 시트가 실제로 붙었는가"를 아무도 보지 않았기 때문이다.

const FACINGS := [&"down", &"up", &"left", &"right"]
const PLAYER_SHEET_TAG := "player_"


## 전용 시트가 있는데도 폴백으로 떨어진 액터를 잡는다.
static func check_sheets(rep: AuditReport, npcs: Array, enemies: Array) -> void:
	for npc: NpcEntity in npcs:
		_check_one_sheet(rep, String(npc.npc_id), npc.sheet_path(), "NPC")
	for e: EnemyEntity in enemies:
		_check_one_sheet(rep, String(e.species_id), e.sheet_path(), "몬스터")
	if npcs.is_empty() and enemies.is_empty():
		rep.ok("시트 배정", "액터 없음")


static func _check_one_sheet(rep: AuditReport, id: String, used: String, kind: String) -> void:
	if id.is_empty():
		rep.fail("액터 id 없음", "%s의 id가 비었다(초기화 순서 의심)" % kind)
		return
	var own := SpriteSets.character_sheet(StringName(id), true)
	var own_path := str(own.get("sheet", ""))
	if own_path.is_empty():
		rep.warn("전용 시트 없음", "%s %s — 플레이스홀더 사용 중" % [kind, id])
		return
	if used != own_path:
		rep.fail("시트 오배정", "%s %s: 전용 시트가 있는데 %s 사용" % [kind, id, used.get_file()])


## 방향별 포즈가 실제로 해결되는가 — 옆을 보다 멈출 때 정면이 튀는 부류를 잡는다.
static func check_pose_coverage(rep: AuditReport, player: PlayerEntity, enemies: Array) -> void:
	_check_actor_poses(rep, "player", player.sprite.sprite_frames)
	var seen: Dictionary = {}
	for e: EnemyEntity in enemies:
		var id := String(e.species_id)
		if seen.has(id):
			continue
		seen[id] = true
		_check_actor_poses(rep, id, e.sprite.sprite_frames)


static func _check_actor_poses(rep: AuditReport, id: String, frames: SpriteFrames) -> void:
	if frames == null:
		rep.fail("애니 없음", id)
		return
	var substituted: Array[String] = []
	for f: StringName in FACINGS:
		var walk := SpriteSets.pose_anim(frames, f, true)
		if walk == &"":
			rep.fail("보행 포즈 없음", "%s %s" % [id, f])
			continue
		if not String(walk).ends_with(String(f)):
			rep.fail("방향 불일치", "%s walk_%s -> %s(다른 방향 프레임)" % [id, f, walk])
		var idle := SpriteSets.pose_anim(frames, f, false)
		if not String(idle).begins_with("idle_"):
			substituted.append(String(f))
	if substituted.is_empty():
		rep.ok("포즈 커버리지", "%s 4방향 idle 완비" % id)
	else:
		# 실패는 아니다 — walk 첫 프레임 대체가 정상 폴백 경로다. 시트 보강 후보로만 남긴다.
		rep.ok("포즈 대체", "%s idle 부재 %s → 같은 방향 walk 첫 프레임" % [id, substituted])


## 액터가 벽에 박혀 있거나 서로 겹쳐 있지 않은가.
static func check_placement(
	rep: AuditReport, rt: MapRuntime, player: PlayerEntity, npcs: Array, enemies: Array
) -> void:
	var bodies: Array = [{"id": "player", "cell": player.mover.grid_pos}]
	for npc: NpcEntity in npcs:
		bodies.append({"id": "NPC " + String(npc.npc_id), "cell": npc.cell})
	for e: EnemyEntity in enemies:
		bodies.append({"id": "몬스터 " + String(e.species_id), "cell": e.mover.grid_pos})

	for b: Dictionary in bodies:
		var cell: Vector2i = b["cell"]
		# NPC는 자기 몸을 차단으로 등록하므로 자기 자신은 통행 불가로 보인다 — 지형만 본다.
		for c in Placement.body_cells(cell):
			if not rt.definition.in_bounds(c):
				rep.fail("맵 밖 배치", "%s @%s" % [b["id"], cell])
				break
			if rt.definition.attr_at(c) == 1 and rt.definition.object_at(c) > 0:
				rep.fail("벽에 박힘", "%s @%s (셀 %s)" % [b["id"], cell, c])
				break

	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			if Placement.bodies_intersect(bodies[i]["cell"], bodies[j]["cell"]):
				rep.fail(
					"액터 겹침", "%s ↔ %s @%s" % [bodies[i]["id"], bodies[j]["id"], bodies[i]["cell"]]
				)
	rep.ok("액터 배치", "%d체 검사" % bodies.size())


## 몬스터가 플레이어 코앞에 스폰되지 않았는가 — 층 진입 즉시 전투로 끌려가는 사고.
static func check_spawn_distance(rep: AuditReport, player: PlayerEntity, enemies: Array) -> void:
	var p := player.mover.grid_pos
	for e: EnemyEntity in enemies:
		if Placement.bodies_touch(p, e.mover.grid_pos):
			rep.fail("스폰 즉시 접촉", "%s @%s (플레이어 %s)" % [e.species_id, e.mover.grid_pos, p])
	rep.ok("스폰 안전거리", "몬스터 %d체" % enemies.size())
