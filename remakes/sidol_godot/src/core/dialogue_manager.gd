class_name DialogueManager
extends RefCounted
## 게임 상태(GameState)와 연동되어 NPC 대사를 동적으로 결정하는 대화 관리자.
##
## 책임 분리 (SRP):
## - NpcEntity / WalkerEntity: 시각, 배회, 충돌 등 필드 액터 물리 연출 담당.
## - DialogueManager: 사건 직후 현장 체감 대사 vs 평시 90s 아이들 잡담 순환 판단.
##
## 마일스톤 판정은 **데이터가 한다** — 배치 파일의 `sequence_variants[].requires_flag`가
## 조건이고 여기는 그것을 읽어 고르기만 한다. 코드에 마일스톤 목록을 또 두면 데이터와
## 갈라지므로 두지 않는다(2026-09-06에 쓰이지 않던 MILESTONES 상수를 걷어냈다).


## NPC의 현재 대사 시퀀스를 결정 (진행 사건 반응 vs 아이들 잡담 순환)
##
## 1. 진행 상태 (Progressed Reaction):
##    스토리 마일스톤 달성 후 해당 마일스톤의 대사를 처음 들을 때 -> NPC의 주관적 현장 체감/유머 대사 출력.
## 2. 정체/아이들 상태 (Idle Chatter Pool):
##    해당 마일스톤 반응을 이미 들었거나 정체 중일 때 -> 90년대 대학가 밈/개그 대사를 신선하게 순환(cycling) 출력.
static func resolve_npc_sequence(
	base_seq: StringName, variants: Array, repeat_seq: Variant = null
) -> StringName:
	var chosen_seq := base_seq
	var chosen_repeat: Variant = repeat_seq

	# 조건에 부합하는 가장 최신의 진행 마일스톤 변형 대사를 탐색 (먼저 맞는 것이 이김)
	for v: Variant in variants:
		if v is not Dictionary:
			continue
		var d: Dictionary = v
		if d.has("requires_flag"):
			if not GameState.has_all_flags(d.get("requires_flag")):
				continue
		# sequence_id가 비면 대사 없는 빈 시퀀스가 열린다 — 조건은 맞았어도 건너뛰고
		# 다음 변형(없으면 기본)으로 간다. SelfCheck가 참조 유효성을 따로 본다.
		var vid := StringName(str(d.get("sequence_id", "")))
		if vid.is_empty():
			push_warning("DialogueManager: sequence_id 없는 변형 — 건너뜀 (base=%s)" % base_seq)
			continue
		chosen_seq = vid
		chosen_repeat = d.get("repeat_sequence_id", null)
		break

	var seen_count := GameState.get_sequence_seen_count(chosen_seq)
	GameState.record_sequence_seen(chosen_seq)

	# 해당 상태를 이미 한 번 이상 들었고, 반복/아이들 대사 풀이 정의되어 있다면 아이들 밈 대사로 순환
	if seen_count > 0 and chosen_repeat != null:
		if chosen_repeat is Array:
			var arr: Array = chosen_repeat
			if not arr.is_empty():
				var idx := (seen_count - 1) % arr.size()
				return StringName(str(arr[idx]))
		elif not str(chosen_repeat).is_empty():
			return StringName(str(chosen_repeat))

	return chosen_seq
