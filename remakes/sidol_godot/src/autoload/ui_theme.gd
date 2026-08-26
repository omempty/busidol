extends Node
## UI 폰트 단일 적용 지점 — 루트 Window에 Theme을 걸어 전 Control이 상속받게 한다.
##
## 04_uiux §2가 "픽셀 한글 폰트(DungGeunMo 계열)로 UI 통일"을 정했으나 미이행이었고,
## 32px 도트 위에 Godot 기본 산세리프가 얹혀 톤이 어긋났다.
##
## 폰트 파일을 저장소에 넣을 수 없는 사정(라이선스 확인 필요)이 있어 **3단 폴백**으로 짠다:
##   1) 번들 폰트  assets/fonts/ui_pixel.<ttf|otf|ttc|fnt>  ← 있으면 최우선
##   2) 시스템 폰트  PIXEL_FACES 중 설치된 것          ← 개발 PC 전용(배포본에선 못 믿는다)
##   3) Godot 기본                                     ← 아무것도 없을 때
## 파일만 1번 자리에 떨어뜨리면 코드 변경 없이 적용된다.

## 번들 폰트 탐색 경로 — 확장자 순서대로 본다.
const FONT_DIR := "res://assets/fonts/"
const FONT_STEM := "ui_pixel"
const FONT_EXTS: Array[String] = ["ttf", "otf", "ttc", "fnt", "font"]

## 시스템 폴백 후보 — 픽셀/비트맵 계열 한글 페이스. 앞에서부터 설치된 것을 쓴다.
## 굴림체·돋움체는 비트맵 힌팅이 있어 픽셀처럼 보이지만 MS 라이선스라
## **배포본에 담을 수 없다** — 개발 중 미리보기 용도로만 뒤쪽에 둔다.
const PIXEL_FACES: PackedStringArray = [
	"둥근모꼴",
	"DungGeunMo",
	"Galmuri11",
	"Galmuri9",
	"NeoDunggeunmo",
	"Neo둥근모",
	"GulimChe",
	"굴림체",
	"DotumChe",
	"돋움체",
]

const BASE_FONT_SIZE := 16

var source := &"default"  ## 실제로 무엇이 적용됐는지 — 감사·디버그용


func _ready() -> void:
	var font := _resolve_font()
	if font == null:
		print("[ui_theme] 폰트 없음 — Godot 기본 사용")
		return
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = BASE_FONT_SIZE
	get_tree().root.theme = theme
	print("[ui_theme] %s 적용" % source)


func _resolve_font() -> Font:
	var bundled := _load_bundled()
	if bundled != null:
		source = &"bundled"
		return bundled
	var sys := _load_system()
	if sys != null:
		source = &"system"
		return sys
	return null


func _load_bundled() -> Font:
	for ext: String in FONT_EXTS:
		var path := "%s%s.%s" % [FONT_DIR, FONT_STEM, ext]
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		if res is FontFile:
			return _make_crisp(res as FontFile)
		if res is Font:
			return res as Font
	return null


func _load_system() -> Font:
	var installed := OS.get_system_fonts()
	for face: String in PIXEL_FACES:
		if not installed.has(face):
			continue
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([face])
		_apply_crisp_flags(sf)
		return sf
	return null


## 픽셀 폰트는 보간이 들어가면 흐려진다 — 안티에일리어싱·힌팅·서브픽셀을 모두 끈다.
func _make_crisp(f: FontFile) -> FontFile:
	var dup: FontFile = f.duplicate()
	_apply_crisp_flags(dup)
	return dup


func _apply_crisp_flags(f: Font) -> void:
	f.set("antialiasing", TextServer.FONT_ANTIALIASING_NONE)
	f.set("hinting", TextServer.HINTING_NONE)
	f.set("subpixel_positioning", TextServer.SUBPIXEL_POSITIONING_DISABLED)
	f.set("multichannel_signed_distance_field", false)
