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


## 고정 NPC·워커 곁에 몬스터가 서 있지 않은가.
##
## 왜 이 프루브가 필요한가 (2026-09-09 실측): "NPC가 사는 방은 비운다"는 규칙이
## EnemyManager에 있었는데 **아무도 그것을 재지 않았다.** 실제 배치는 액터 17명 중
## 12명이 복도에 서 있고 복도는 배제에서 빠지므로, f1·f2·f4·f5에서는 배제되는 칸이
## 0개였다 — 규칙이 4개 층에서 한 번도 안 걸린 채 반년을 지났다. 반경 배제를 더했으니
## 그것이 실제로 지켜지는지는 여기서 층마다 잰다.
## 워커는 빼고 잰다 — 배경 보행자는 정의상 몬스터 곁으로 걸어갈 수 있다.
static func check_actor_clearance(rep: AuditReport, npcs: Array, enemies: Array) -> void:
	var anchors: Array[Vector2i] = []
	for n: NpcEntity in npcs:
		anchors.append(n.cell)
	if anchors.is_empty() or enemies.is_empty():
		rep.ok("액터 이격", "액터 %d · 몬스터 %d — 잴 것 없음" % [anchors.size(), enemies.size()])
		return
	var worst := 9999
	var bad := 0
	for e: EnemyEntity in enemies:
		var best := 9999
		for a: Vector2i in anchors:
			var d := e.mover.grid_pos - a
			best = mini(best, maxi(absi(d.x), absi(d.y)))
		worst = mini(worst, best)
		if best <= EnemyManager.ACTOR_CLEAR_RADIUS:
			bad += 1
			rep.fail(
				"액터 곁 스폰",
				(
					"%s @%s — 가장 가까운 액터까지 %d칸(허용 >%d)"
					% [e.species_id, e.mover.grid_pos, best, EnemyManager.ACTOR_CLEAR_RADIUS]
				)
			)
	if bad == 0:
		rep.ok(
			"액터 이격",
			(
				"몬스터 %d체 · 액터 %d명 · 최근접 %d칸(반경 %d 초과여야)"
				% [enemies.size(), anchors.size(), worst, EnemyManager.ACTOR_CLEAR_RADIUS]
			)
		)


## 데이터가 배정한 이동 패턴이 **전부 실제로 구현돼 있는가.**
##
## 선언(enum·기본값·텔레그래프)만 있고 decide()에 분기가 없으면 그 종은 조용히 배회만
## 한다 — 화면상으로는 "가만히 안 있고 움직이니" 정상으로 보여서 눈으로는 절대 안 잡힌다.
## 실제로 PATROL·PULSE 두 패턴이 그 상태로 남아 있었다(2026-09-09).
## 데이터가 선언한 idle_anim에 **실제로 도는 동작이 붙어 있는가.**
##
## 왜 이 관문이 필요한가 (2026-09-09 실측): npcs_f*.json 5파일 11명 전원이
## `idle_anim: "squash"`를 달고 있었는데 그 키를 읽는 코드가 **0곳**이었다.
## 게임은 정상이고 관문도 초록이었다 — 선언한 연출이 실제로 도는지 아무도 재지 않았기 때문이다.
## 이동 패턴에서 PATROL·PULSE가 같은 방식으로 죽어 있던 것(MovementPattern 주석)과 같은 결이다.
static func check_idle_anim_coverage(rep: AuditReport) -> void:
	var seen: Dictionary = {}
	var bad: Array[String] = []
	var total := 0
	for floor_idx in range(0, 6):
		var path := "res://data/maps/npcs_f%d.json" % floor_idx
		if not FileAccess.file_exists(path):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) != TYPE_DICTIONARY:
			rep.fail("NPC 데이터 파손", path)
			continue
		for n: Dictionary in (raw as Dictionary).get("npcs", []):
			total += 1
			var name := str(n.get("idle_anim", NpcEntity.DEFAULT_IDLE_ANIM))
			seen[name] = int(seen.get(name, 0)) + 1
			if not NpcEntity.is_idle_anim_implemented(name):
				bad.append("%s (f%d %s)" % [name, floor_idx, str(n.get("id", "?"))])
	for b in bad:
		rep.fail("idle_anim 미구현", "%s — 읽는 코드가 없어 연출이 조용히 사라진다" % b)
	if bad.is_empty():
		rep.ok("idle_anim 계약", "NPC %d명이 쓰는 %d종 전부 구현됨" % [total, seen.size()])


static func check_pattern_coverage(rep: AuditReport) -> void:
	var missing: Array[String] = []
	var seen := {}
	for floor_idx in range(0, 6):
		for sp: Dictionary in Database.encounter_species(floor_idx):
			var name := str(sp.get("pattern", "wander"))
			if seen.has(name):
				continue
			seen[name] = true
			if not MovementPattern.is_implemented(name):
				missing.append("%s (f%d %s)" % [name, floor_idx, str(sp.get("id", "?"))])
	for m in missing:
		rep.fail("이동 패턴 미구현", "%s — decide()에 분기가 없어 배회로 떨어진다" % m)
	if missing.is_empty():
		rep.ok("이동 패턴 구현", "데이터가 쓰는 %d종 전부 구현됨" % seen.size())


## 시나리오 종이 **설정 한 칸으로 사라지지 않는가** — 밀도 4종 전부에서 자리를 받는가.
##
## dworm의 `first_win_flag`(Q_F1_START)는 필드 몬스터가 세우는 유일한 시나리오 플래그이고,
## 그것이 없으면 f1_sopo·f1_gas가 잠겨 **1층에서 게임이 끝난다**. 밀도 「없음」은 스폰을 0으로
## 만들었고, 「보통」이어도 명단이 종을 무작위로 뽑아 dworm이 빠질 수 있었다(백로그 §3.9.1).
## 정본은 `EnemyManager.effective_cap()` 하나다 — 여기서 그것을 직접 불러 잰다.
static func check_story_species_density(rep: AuditReport) -> void:
	var saved: int = SettingsManager.encounter_density
	var bad: Array[String] = []
	var checked := 0
	for floor_idx in range(0, 6):
		var species := Database.encounter_species(floor_idx)
		var pending := EnemyManager.pending_story_species(species)
		if pending.is_empty():
			continue
		var base := int(Database.encounter_table(floor_idx).get("count", 0))
		for d in [
			SettingsManager.EncounterDensity.NONE,
			SettingsManager.EncounterDensity.LOW,
			SettingsManager.EncounterDensity.NORMAL,
			SettingsManager.EncounterDensity.HIGH,
		]:
			checked += 1
			SettingsManager.encounter_density = d
			var cap := EnemyManager.effective_cap(base, pending.size())
			if cap < pending.size():
				bad.append("f%d 밀도 %d — 정원 %d < 시나리오 종 %d" % [floor_idx, d, cap, pending.size()])
	SettingsManager.encounter_density = saved
	for b in bad:
		rep.fail("시나리오 종이 밀도에 지워진다", "%s — 첫 격파 플래그가 영영 안 서서 진행이 끊긴다" % b)
	if bad.is_empty() and checked > 0:
		rep.ok("시나리오 종 정원", "밀도 4종 × %d건 전부 자리를 받는다" % (checked / 4))


## 그 층에 **실제로** 서 있는가 — 계산이 맞아도 명단에서 빠지면 소용이 없다.
## world_audit이 층마다 세운 뒤 부르므로, 무작위 명단이 시나리오 종을 빠뜨리면 여기서 붉어진다.
static func check_story_species_spawned(rep: AuditReport, floor_no: int, enemies: Array) -> void:
	var pending := EnemyManager.pending_story_species(Database.encounter_species(floor_no))
	if pending.is_empty():
		return
	var on_field := {}
	for e: Variant in enemies:
		if e != null and "species_id" in e:
			on_field[str(e.species_id)] = true
	var missing: Array[String] = []
	for spec: Dictionary in pending:
		if not on_field.has(str(spec["id"])):
			missing.append("%s(%s)" % [str(spec["id"]), str(spec.get("first_win_flag", ""))])
	for m in missing:
		rep.fail("시나리오 종이 층에 없다", "(f%d) %s — 잡을 수가 없어 그 플래그를 요구하는 사건이 통째로 잠긴다" % [floor_no, m])
	if missing.is_empty():
		rep.ok("시나리오 종 배치", "(f%d) %d종 전부 층에 서 있다" % [floor_no, pending.size()])
