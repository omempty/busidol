class_name DodgePhase
extends Node2D
## 보스전 회피 페이즈 — 탄막슈팅풍 실시간 회피.
## 패턴 종류: radial/aimed/wall/spiral/laser_sweep/homing/rain/cross/ring_collapse/random_burst
## 조합 가능: 한 페이즈에 여러 패턴 동시 발사.
## (목록에 있던 bounce는 미구현 — 선언만 있고 _fire_pattern 분기가 없다.)
##
## 탄 스프라이트: 외부 무료팩(CC0)을 구운 것이 있으면 텍스처로 그리고,
## 없으면 기존 도형(원+흰심) 폴백. 판정 반경(r)은 그림과 무관하게 유지한다 —
## 그림이 바뀌어도 난이도가 바뀌면 안 된다. 굽는 도구: tools/dev/bake_external_bosses.py.

signal phase_complete(hit_count: int)

const PLAYER_HITBOX := 5.0
const ARENA := Rect2(48, 48, 384, 264)  ## 960×540 뷰포트 기준 (구 640×360 1.5배)
## 외부 탄 텍스처 — 파일이 없으면 폴백 도형으로 그린다(교체 가능성의 역방향).
const EXT_TEX_WARM := "res://assets/effects/ext_bullet_warm.png"
const EXT_TEX_COOL := "res://assets/effects/ext_bullet_cool.png"

var _ext_tex: Dictionary = {}


func _ready() -> void:
	for key: String in [EXT_TEX_WARM, EXT_TEX_COOL]:
		if ResourceLoader.exists(key):
			var tex: Texture2D = load(key)
			if tex != null:
				_ext_tex[key] = tex


var duration := 4.0
var elapsed := 0.0
var hit_count := 0
var active := false
var phase_config: Dictionary = {}

var _projectiles: Array[Dictionary] = []
var _lasers: Array[Dictionary] = []
var _player_pos := Vector2.ZERO
var _spawn_timers := {}  # pattern_id -> timer
var _spiral_angle := 0.0
var _laser_angle := 0.0
var _laser_sweep_dir := 1.0


func start(p_duration: float, p_config: Dictionary) -> void:
	duration = p_duration
	phase_config = p_config
	elapsed = 0.0
	hit_count = 0
	_projectiles.clear()
	_lasers.clear()
	_player_pos = Vector2(ARENA.position.x + ARENA.size.x / 2, ARENA.end.y - 24)
	_spawn_timers.clear()
	for pat in phase_config.get("patterns", []):
		var pid: String = str(pat.get("pattern_id", "p0"))
		_spawn_timers[pid] = float(pat.get("initial_delay", 0.3))
	active = true


func stop() -> void:
	active = false
	_projectiles.clear()
	_lasers.clear()


func _float_cfg(key: String, fallback: float) -> float:
	return float(phase_config.get(key, fallback))


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	if elapsed >= duration:
		active = false
		phase_complete.emit(hit_count)
		queue_redraw()
		return

	# 플레이어 이동 (실시간 방향키)
	var mv := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var speed := _float_cfg("player_speed", 220.0)
	_player_pos += mv * speed * delta
	_player_pos.x = clampf(
		_player_pos.x, ARENA.position.x + PLAYER_HITBOX, ARENA.end.x - PLAYER_HITBOX
	)
	_player_pos.y = clampf(
		_player_pos.y, ARENA.position.y + PLAYER_HITBOX, ARENA.end.y - PLAYER_HITBOX
	)

	# 패턴별 스폰 타이머
	for pat in phase_config.get("patterns", []):
		var pid: String = str(pat.get("pattern_id", "p0"))
		if not _spawn_timers.has(pid):
			_spawn_timers[pid] = float(pat.get("initial_delay", 0.3))
		_spawn_timers[pid] -= delta
		if _spawn_timers[pid] <= 0:
			_fire_pattern(pat)
			_spawn_timers[pid] = float(pat.get("interval", 0.5))

	_update_projectiles(delta)
	_update_lasers(delta)
	_check_collisions()
	queue_redraw()


func _fire_pattern(pat: Dictionary) -> void:
	var origin := Vector2(ARENA.position.x + ARENA.size.x / 2, ARENA.position.y + 20)
	match str(pat.get("type", "radial")):
		"radial":
			_fire_radial(origin, pat)
		"aimed":
			_fire_aimed(origin, pat)
		"wall":
			_fire_wall(pat)
		"spiral":
			_fire_spiral(origin, pat)
		"laser_sweep":
			_fire_laser_sweep(origin, pat)
		"homing":
			_fire_homing(origin, pat)
		"rain":
			_fire_rain(pat)
		"cross":
			_fire_cross(origin, pat)
		"ring_collapse":
			_fire_ring_collapse(pat)
		"random_burst":
			_fire_random_burst(pat)


func _add_proj(
	pos: Vector2,
	vel: Vector2,
	r: float = 4.0,
	color: Color = Color(1.0, 0.4, 0.3),
	homing_strength: float = 0.0,
	tex: String = ""
) -> void:
	_projectiles.append(
		{"pos": pos, "vel": vel, "r": r, "color": color, "homing": homing_strength, "tex": tex}
	)


# ---- 패턴 구현 ----


func _fire_radial(o: Vector2, pat: Dictionary) -> void:
	var count := int(pat.get("count", 8))
	var speed := float(pat.get("speed", 160))
	var offset := randf() * TAU
	for i in count:
		var ang := TAU * i / count + offset
		_add_proj(
			o,
			Vector2.from_angle(ang) * speed,
			4.0,
			Color(float(pat.get("cr", 1.0)), 0.4, 0.3),
			0.0,
			EXT_TEX_WARM
		)


func _fire_aimed(o: Vector2, pat: Dictionary) -> void:
	var speed := float(pat.get("speed", 220))
	var dir := (_player_pos - o).normalized()
	for i in int(pat.get("count", 1)):
		var spread := (
			deg_to_rad(float(pat.get("spread_deg", 0))) * (i - (int(pat.get("count", 1)) - 1) / 2.0)
		)
		_add_proj(o, dir.rotated(spread) * speed, 4.0, Color(1.0, 0.6, 0.2), 0.0, EXT_TEX_WARM)


func _fire_wall(pat: Dictionary) -> void:
	var speed := float(pat.get("speed", 120))
	var gap_ratio := float(pat.get("gap_ratio", 0.25))
	var gap_center := randf_range(ARENA.position.x + ARENA.size.x * 0.15, ARENA.end.x * 0.85)
	var gap_half := ARENA.size.x * gap_ratio / 2
	var y := ARENA.position.y
	var x := ARENA.position.x
	while x < ARENA.end.x:
		if not (gap_center - gap_half < x and x < gap_center + gap_half):
			_add_proj(
				Vector2(x, y), Vector2(0, speed), 4.0, Color(0.5, 0.7, 1.0), 0.0, EXT_TEX_COOL
			)
		x += 14.0


func _fire_spiral(o: Vector2, pat: Dictionary) -> void:
	var arms := int(pat.get("arms", 3))
	var speed := float(pat.get("speed", 140))
	_spiral_angle += deg_to_rad(float(pat.get("rotation_speed", 15)))
	for i in arms:
		var ang := _spiral_angle + TAU * i / arms
		_add_proj(o, Vector2.from_angle(ang) * speed, 3.5, Color(0.8, 0.4, 1.0), 0.0, EXT_TEX_COOL)


func _fire_laser_sweep(o: Vector2, pat: Dictionary) -> void:
	_laser_angle += deg_to_rad(float(pat.get("sweep_speed", 30))) * _laser_sweep_dir
	if absf(_laser_angle) > deg_to_rad(float(pat.get("max_angle", 60))):
		_laser_sweep_dir *= -1
	var length := ARENA.size.length()
	var dir := Vector2.from_angle(-PI / 2 + _laser_angle)
	_lasers.append(
		{
			"start": o,
			"dir": dir,
			"width": float(pat.get("width", 4)),
			"length": length,
			"life": float(pat.get("laser_duration", 0.12)),
			"color": Color(1.0, 0.2, 0.3, 0.8)
		}
	)


func _fire_homing(o: Vector2, pat: Dictionary) -> void:
	var speed := float(pat.get("speed", 100))
	var dir := (_player_pos - o).normalized()
	_add_proj(
		o,
		dir * speed,
		4.0,
		Color(1.0, 0.8, 0.0),
		float(pat.get("homing_strength", 2.0)),
		EXT_TEX_WARM
	)


func _fire_rain(pat: Dictionary) -> void:
	var speed := float(pat.get("speed", 150))
	var count := int(pat.get("count", 3))
	for i in count:
		var rx := randf_range(ARENA.position.x + 8, ARENA.end.x - 8)
		_add_proj(
			Vector2(rx, ARENA.position.y),
			Vector2(0, speed),
			3.0,
			Color(0.4, 0.8, 1.0),
			0.0,
			EXT_TEX_COOL
		)


func _fire_cross(o: Vector2, pat: Dictionary) -> void:
	var speed := float(pat.get("speed", 130))
	var angle_offset := deg_to_rad(float(pat.get("angle_offset", 0)))
	for i in 4:
		var ang := angle_offset + PI / 2 * i
		_add_proj(o, Vector2.from_angle(ang) * speed, 4.5, Color(1.0, 0.9, 0.3), 0.0, EXT_TEX_WARM)


func _fire_ring_collapse(pat: Dictionary) -> void:
	var target := _player_pos
	var radius := float(pat.get("radius", 60))
	var count := int(pat.get("count", 10))
	var speed := float(pat.get("speed", 80))
	for i in count:
		var ang := TAU * i / count
		var pos := target + Vector2.from_angle(ang) * radius
		var dir := (target - pos).normalized()
		_add_proj(pos, dir * speed, 3.5, Color(0.8, 0.3, 1.0), 0.0, EXT_TEX_COOL)


func _fire_random_burst(pat: Dictionary) -> void:
	var count := int(pat.get("count", 4))
	var speed_range: Array = pat.get("speed_range", [80, 180])
	for i in count:
		var px := randf_range(ARENA.position.x, ARENA.end.x)
		var py := randf_range(ARENA.position.y, ARENA.position.y + 40)
		var ang := randf_range(PI * 0.25, PI * 0.75)
		var spd := randf_range(float(speed_range[0]), float(speed_range[1]))
		_add_proj(
			Vector2(px, py),
			Vector2.from_angle(ang) * spd,
			3.0,
			Color(randf_range(0.5, 1.0), randf_range(0.3, 0.6), 1.0),
			0.0,
			EXT_TEX_COOL
		)


# ---- 업데이트 ----


func _update_projectiles(delta: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var h: float = float(p.get("homing", 0))
		if h > 0:
			var to_player: Vector2 = (_player_pos - (p["pos"] as Vector2)).normalized()
			p["vel"] = (p["vel"] as Vector2).lerp(
				to_player * (p["vel"] as Vector2).length(), h * delta
			)
		p["pos"] = p["pos"] + p["vel"] * delta
		if not ARENA.grow(16).has_point(p["pos"]):
			_projectiles.remove_at(i)


func _update_lasers(delta: float) -> void:
	for i in range(_lasers.size() - 1, -1, -1):
		var l: Dictionary = _lasers[i]
		l["life"] = float(l["life"]) - delta
		if float(l["life"]) <= 0:
			_lasers.remove_at(i)


func _check_collisions() -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		if p["pos"].distance_to(_player_pos) < PLAYER_HITBOX + float(p["r"]):
			hit_count += 1
			_projectiles.remove_at(i)


func _draw() -> void:
	if not active:
		return
	draw_rect(ARENA, Color(0.04, 0.04, 0.09, 0.9))
	draw_rect(ARENA, Color(0.25, 0.25, 0.45), false, 1.0)

	# 레이저
	for l in _lasers:
		var end_point: Vector2 = l["start"] + l["dir"] * float(l["length"])
		draw_line(l["start"], end_point, l["color"], float(l["width"]))

	# 탄막 — 외부 텍스처가 있으면 그걸 쓰고, 없으면 도형 폴백.
	for p in _projectiles:
		var tex: Texture2D = _ext_tex.get(str(p.get("tex", "")), null)
		if tex != null:
			# 화면상 지름이 판정 지름(r*2)과 같게 — 16px 링이 r=4탄 자리에 그대로 들어간다.
			var s := float(p["r"]) * 2.0 / maxf(maxf(tex.get_width(), tex.get_height()), 1.0)
			draw_set_transform(p["pos"], 0.0, Vector2.ONE * s)
			draw_texture(tex, -Vector2(tex.get_width(), tex.get_height()) * 0.5)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(p["pos"], float(p["r"]), p["color"])
			draw_circle(p["pos"], float(p["r"]) * 0.5, Color(1, 1, 1, 0.6))

	# 플레이어 히트박스
	draw_circle(_player_pos, PLAYER_HITBOX, Color(0.3, 1.0, 0.5))
	draw_arc(_player_pos, PLAYER_HITBOX + 2, 0, TAU, 16, Color(0.3, 1.0, 0.5, 0.4), 1)

	# 남은 시간 바
	var remain := clampf(1.0 - elapsed / duration, 0.0, 1.0)
	var bar_w := ARENA.size.x * remain
	draw_rect(
		Rect2(ARENA.position.x, ARENA.end.y + 4, bar_w, 3),
		Color(0.3, 1.0, 0.5) if remain > 0.3 else Color(1.0, 0.3, 0.2)
	)

	# 히트 카운터
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(ARENA.position.x + 4, ARENA.end.y + 18),
		"HIT %d" % hit_count,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1, 0.5, 0.3)
	)
