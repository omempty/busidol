extends RefCounted
## 자동 주행의 기록장 — 세어야 할 것과 보고서에 실을 표.
##
## 주행(autoplay)과 층 훑기(autoplay_sweep)가 **같은 표**를 쓴다. 표가 갈라지면 같은
## 결함이 도구마다 다른 이름으로 실려 무엇을 고쳤는지 대조가 안 된다.

var steps := 0
## 지나간 프로세스 프레임 수 — **주행이 느릴 때 CPU 탓인지 프레임 탓인지 가른다.**
## 걸음 하나에 프레임이 몇 장 드는지가 곧 주행 속도다.
var frames := 0
## 지나간 물리 프레임 수. 걸음은 물리 프레임에서 판정되므로 **이 수가 곧 걸을 수 있는
## 횟수의 상한**이다. 프로세스 프레임보다 훨씬 적으면 빨리 감기가 안 먹고 있는 것이다.
var physics_frames := 0
var scale_seen := 0.0  # 주행 시작 때 걸려 있던 Engine.time_scale
## 주행 내내 본 배율의 최솟값 — **누가 빨리 감기를 되돌려 놓았는지 잡는 자리다.**
## 시작값만 찍으면 중간에 1.0으로 덮여도 보고서는 30이라고 말한다.
var scale_min := 0.0
## 걸음 자체를 기다린 물리 프레임(step_to 안) — 전체와 비교하면 "걷느라 느린가,
## 걸음 사이가 느린가"가 갈린다.
var step_frames := 0
var still_frames := 0
var battles := 0
var revivals := 0
var dialogues := 0
var chests := 0

## 밟았는데 아무 일도 없었다 — 이 저장소의 주 결함(사문화 데이터) 탐지기.
var dead: Array[String] = []
## 지금 갈 수 없는 것. 키는 "층|목표id" — **닿으면 지운다.** 한 번 못 갔다고 남겨 두면
## 컷신 중이라 못 갔을 뿐인 것까지 "영영 못 감"으로 보고된다.
var unreachable: Dictionary = {}
## 데이터를 읽는 것만으로 드러나는 모순 — 주행 결과와 무관하게 참이다.
var data_notes: Dictionary = {}

var _seen: Dictionary = {}


func summary_rows() -> Array:
	return [
		"| 전투 | %d |" % battles,
		"| 연 상자 | %d |" % chests,
		"| 나눈 대화 | %d |" % dialogues,
		"| 쓰러져 되살린 횟수 | %d |" % revivals,
		"| 지도 밝힌 칸 | %s |" % _fog_row(),
	]


## 층별로 지도를 얼마나 밝혔나 — 안개 배선이 살아 있는지 **주행 끝에** 확인하는 자리.
## world_audit은 "층에 들어선 직후"만 본다. 걸어 다니며 실제로 느는지는 여기서만 보인다.
## 층당 13,000칸이므로 0이면 배선이 끊긴 것이고 13000이면 안개가 죽은 것이다.
func _fog_row() -> String:
	var parts: Array[String] = []
	for f: int in GameState.fog.floors_with_fog():
		parts.append("f%d %d" % [f, GameState.fog.seen_cells(f)])
	return "없음" if parts.is_empty() else " · ".join(parts)


func mark_dead(floor_no: int, kind: String, label: String, cell: Vector2i) -> void:
	var row := "| f%d | %s | %s | %s |" % [floor_no, kind, label, str(cell)]
	if _seen.has(row):
		return
	_seen[row] = true
	dead.append(row)


func mark_unreachable(
	floor_no: int, id: String, kind: String, label: String, cell: Vector2i
) -> void:
	unreachable["%d|%s" % [floor_no, id]] = (
		"| f%d | %s | %s | %s |" % [floor_no, kind, label, str(cell)]
	)


func mark_reachable(floor_no: int, id: String) -> void:
	unreachable.erase("%d|%s" % [floor_no, id])


## 두 도구가 함께 쓰는 꼬리 표들.
func sections() -> Array[String]:
	var lines: Array[String] = []
	lines.append("## 밟았는데 아무 일도 없었다")
	lines.append("")
	if dead.is_empty():
		lines.append("없음.")
	else:
		lines.append("**데이터에는 있는데 게임에는 없는 것들이다.** 도구가 실제로 그 앞에")
		lines.append("서서 조사했지만 플래그도 대사도 상자도 열리지 않았다.")
		lines.append("")
		lines.append("| 층 | 종류 | 이름 | 좌표 |")
		lines.append("|---|---|---|---|")
		lines.append_array(dead)
	lines.append("")

	lines.append("## 걸어서 닿을 수 없다")
	lines.append("")
	var keys: Array = unreachable.keys()
	keys.sort()
	if keys.is_empty():
		lines.append("없음.")
	else:
		lines.append("좌표는 적혀 있으나 **그 층을 마지막으로 훑었을 때** 걸어서 그 앞에")
		lines.append("설 수 없었던 것들이다(2×2 몸이 들어갈 앵커가 없거나 길이 끊겼다).")
		lines.append("")
		lines.append("| 층 | 종류 | 이름 | 좌표 |")
		lines.append("|---|---|---|---|")
		for key: Variant in keys:
			lines.append(String(unreachable[key]))
	lines.append("")

	lines.append("## 좌표가 애초에 조사 불가")
	lines.append("")
	var notes: Array = data_notes.keys()
	notes.sort()
	if notes.is_empty():
		lines.append("없음.")
	else:
		lines.append("데이터를 읽는 것만으로 드러나는 모순이다 — 주행 결과와 무관하게 참이다.")
		lines.append("")
		lines.append("| 층 | 이름 | 좌표 | 사유 |")
		lines.append("|---|---|---|---|")
		for note: Variant in notes:
			lines.append(String(note))
	lines.append("")
	return lines


func store(path: String, lines: Array[String], tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[%s] 보고서를 쓰지 못했다: %s" % [tag, path])
		return
	file.store_string("\n".join(lines))
	file.close()
	print("-> %s" % path)
