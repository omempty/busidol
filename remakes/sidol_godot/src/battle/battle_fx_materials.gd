class_name BattleFxMaterials
extends RefCounted
## 전투 이펙트 공용 재질 — 가산 블렌드·수명 그라디언트·방사 글로우.
##
## 지금까지 전투 파티클은 전부 일반 블렌딩+단색이었다. 불·번개·섬광이
## "흰 점들의 집합"으로 보여 종을 가르는 색이 묻혔다. 엔진이 주는 것을 쓴다:
##   CanvasItemMaterial(ADD) — 겹칠수록 밝아지는 발광. 불·번개·잔상·섬광용.
##   CPUParticles2D.color_ramp — 수명에 따른 색·알파 곡선(노랑→주황→소멸).
##   GradientTexture2D(방사) — 아트 없이 만드는 글로우 스프라이트. 임팩트 핵용.
## 재질·텍스처는 정적 캐시로 돌려쓴다 — 매 타격마다 새로 만들면
## 그리기 상태 변경이 늘어 느려진다.

static var _add_mat: CanvasItemMaterial = null
## 글로우 캐시 — 색 키 → 방사 텍스처. 색이 몇 종 없으므로 사전 하나로 충분하다.
static var _glow_tex: Dictionary = {}


## 가산 발광 재질(공유) — 불·번개·섬광·잔상은 이것 하나로 통일한다.
static func additive() -> CanvasItemMaterial:
	if _add_mat == null or not is_instance_valid(_add_mat):
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## 불꽃 수명 곡선 — 흰핵 → 노랑 → 주황 → 투명. color_ramp에 바로 꽂는다.
static func fire_ramp() -> Gradient:
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.96, 0.75, 1.0))
	gr.set_offset(0, 0.0)
	gr.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	gr.set_offset(1, 1.0)
	gr.add_point(0.45, Color(1.0, 0.55, 0.1, 0.9))
	return gr


## 전격 수명 곡선 — 흰핵 → 하늘 → 투명.
static func volt_ramp() -> Gradient:
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gr.set_offset(0, 0.0)
	gr.set_color(1, Color(0.2, 0.6, 1.0, 0.0))
	gr.set_offset(1, 1.0)
	gr.add_point(0.4, Color(0.45, 0.9, 1.0, 0.9))
	return gr


## 타격 스파크 수명 곡선 — 백열 → 앰버 → 투명.
static func spark_ramp() -> Gradient:
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 1.0, 0.95, 1.0))
	gr.set_offset(0, 0.0)
	gr.set_color(1, Color(1.0, 0.6, 0.1, 0.0))
	gr.set_offset(1, 1.0)
	gr.add_point(0.5, Color(1.0, 0.88, 0.3, 0.95))
	return gr


## 방사 글로우 텍스처(공유) — 중심 흰핵 → 지정색 → 투명 외곽.
static func glow_texture(edge: Color) -> GradientTexture2D:
	var key := "%d_%d_%d" % [int(edge.r * 255.0), int(edge.g * 255.0), int(edge.b * 255.0)]
	if _glow_tex.has(key):
		return _glow_tex[key]
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gr.set_offset(0, 0.0)
	gr.set_color(1, Color(edge.r, edge.g, edge.b, 0.0))
	gr.set_offset(1, 1.0)
	gr.add_point(0.35, Color(1.0, 1.0, 1.0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = gr
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_glow_tex[key] = tex
	return tex


## 임팩트 글로우 한 방 — 커졌다 사라지는 발광. 트윈이 끝나면 스스로 걷힌다.
## root: BattlePresenter._root 같은 Node2D. 호출부는 위치·색·크기만 정한다.
static func spawn_glow(
	root: Node2D, at: Vector2, edge: Color, start_px: float, end_px: float, dur: float, z_index: int
) -> void:
	if root == null:
		return
	var spr := Sprite2D.new()
	spr.texture = glow_texture(edge)
	spr.material = additive()
	spr.position = at
	spr.scale = Vector2.ONE * (maxf(start_px, 1.0) / 64.0)
	spr.z_index = z_index
	root.add_child(spr)
	var tw := spr.create_tween().set_parallel(true)
	(
		tw
		. tween_property(spr, "scale", Vector2.ONE * (maxf(end_px, 1.0) / 64.0), dur)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(spr, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(spr.queue_free)
