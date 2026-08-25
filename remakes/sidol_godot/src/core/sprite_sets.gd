class_name SpriteSets
## 아트 모드별 스프라이트 시트 경로 결정 단일 창구.
## 컨벤션: assets/sprites/<id>_original.* = 레거시(원작 도트) · <id>_remake.* = 신규 세트.
## 설정(SettingsManager.art_mode) 우선, 파일 부재 시 반대 세트로 폴백 —
## 신규 시트 미착용 상태에서도 게임 동작을 보장한다.
## 셀 크기·프레임 수·비율은 시트별 메타 JSON이 자기기술하므로 두 세트 규격이 달라도 무관.
## 근거: docs/02_design/04_uiux_modernization.md §2 (렌더 px ↔ 논리 그리드 분리).

const SPRITE_DIR := "res://assets/sprites/"
const LEGACY_TAG := "original"
const REMAKE_TAG := "remake"


## 캐릭터 시트 경로 조회 — {"sheet": String, "meta": String}. 부재 시 빈 문자열.
## quiet=true면 부재를 오류로 기록하지 않는다(선행 조회 용도).
static func character_sheet(asset_id: StringName, quiet := false) -> Dictionary:
	var order: Array[String] = [LEGACY_TAG, REMAKE_TAG]
	if SettingsManager.art_mode == SettingsManager.ArtMode.REMAKE:
		order = [REMAKE_TAG, LEGACY_TAG]
	for tag in order:
		var sheet := "%s%s_%s.png" % [SPRITE_DIR, asset_id, tag]
		if ResourceLoader.exists(sheet):
			return {
				"sheet": sheet,
				"meta": "%s%s_%s.json" % [SPRITE_DIR, asset_id, tag],
			}
	if not quiet:
		push_error("SpriteSets: '%s' 시트 없음 — %s/%s 태그 모두 부재" % [asset_id, order[0], order[1]])
	return {"sheet": "", "meta": ""}


## 발바닥 앵커 보정 offset.y — 중앙 앵커 스프라이트가 scale≠1일 때도
## 발끝이 논리 바닥(2×2 발판 하단 = TILE_PX)에 닿게 한다.
## 도출: 바닥 = 위치 + scale×(offset.y + cell_h/2) ⇒ offset.y = TILE_PX/scale − cell_h/2
## scale=1이면 0(구 시트 64셀 호환), 메타 파싱 실패 시 빈 Dictionary → 0.
static func foot_offset(meta: Dictionary) -> float:
	if meta.is_empty():
		return 0.0
	var s := float(meta.get("scale", 1.0))
	if s <= 0.0:
		return 0.0
	var ch := float(meta.get("cell_h", meta.get("cell", 64)))
	return float(MapDefinition.TILE_PX) / s - ch / 2.0
