class_name ShadowBlob
extends Sprite2D
## 발밑 타원 그림자 — 정적 생성 텍스처(클래스 단위 캐시).
## 동적 조명(LightOccluder2D 등)은 G-ART 원작 감성과 충돌해 불사 — 저비용 깊이 표현.

const SIZE := Vector2i(28, 10)
const MAX_ALPHA := 0.35

static var _cache: Dictionary = {}  # max_alpha -> ImageTexture


## 액터 노드 발밑(논리 바닥 = 로컬 y + TILE_PX)에 부착한다.
static func attach(actor: Node2D, foot_y: float = MapDefinition.TILE_PX) -> void:
	var blob := ShadowBlob.new()
	blob.texture = shadow_texture()
	blob.position = Vector2(0, foot_y - 3.0)
	blob.z_index = 14  # 맵 위, 액터(z 15) 아래
	actor.add_child(blob)


## 발밑 그림자 텍스처. max_alpha로 세기를 고른다 —
## 필드는 밝은 타일 위라 옅어도 읽히지만, 전투는 어두운 바닥이라 더 진해야 보인다.
static func shadow_texture(max_alpha: float = MAX_ALPHA) -> ImageTexture:
	var key := snappedf(max_alpha, 0.05)
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var cx := (SIZE.x - 1) / 2.0
	var cy := (SIZE.y - 1) / 2.0
	for y in SIZE.y:
		for x in SIZE.x:
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= 1.0:
				var a := key * clampf((1.0 - d) / 0.25, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
