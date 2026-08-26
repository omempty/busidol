class_name ItemIcons
## 아이템 아이콘 단일 창구 — 현재는 kind별 색상 플레이스홀더(첫 글자 표시).
## 실제 아이콘 에셋 착지 시 이 파일의 조회 함수만 교체하면 UI 전파 없이 반영된다.
## kind 데이터 출처: data/items.json (weapon/consumable/quest/material/magic_substitute/money)

const KIND_COLORS := {
	&"weapon": Color(0.85, 0.36, 0.32),
	&"consumable": Color(0.36, 0.78, 0.45),
	&"quest": Color(0.9, 0.72, 0.28),
	&"material": Color(0.4, 0.62, 0.9),
	&"magic_substitute": Color(0.66, 0.45, 0.88),
	&"money": Color(1.0, 0.84, 0.35),
}
const FALLBACK_COLOR := Color(0.55, 0.55, 0.6)
const ICON_DIR := "res://assets/icons/"


## 실제 아이콘 텍스처 — assets/icons/<id>.png(원작 ITEM.SPR 이관분).
## 부재 시 null — 호출부는 색상+글리프 폴백을 유지한다.
static func texture(item_def: Dictionary) -> Texture2D:
	var id := str(item_def.get("id", ""))
	if id.is_empty():
		return null
	var path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func kind_color(kind: StringName) -> Color:
	return KIND_COLORS.get(kind, FALLBACK_COLOR)


## 슬롯 약자 — name_ko 첫 글자(한글 우선), 없으면 id 이니셜.
static func glyph(item_def: Dictionary) -> String:
	var ko := str(item_def.get("name_ko", ""))
	if not ko.is_empty():
		return ko.substr(0, 1)
	var en := str(item_def.get("id", "?"))
	return en.substr(0, 1).to_upper()
