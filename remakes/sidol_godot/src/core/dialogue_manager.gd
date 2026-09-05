class_name DialogueManager
extends RefCounted
## 게임 상태(GameState)와 연동되어 NPC 대사를 동적으로 결정하는 대화 관리자.
##
## 책임 분리 (SRP):
## - NpcEntity / WalkerEntity: 시각, 배회, 충돌 등 필드 액터 물리 연출 담당.
## - DialogueManager: 마일스톤 달성 여부 감지, 사건 직후 현장 체감 대사 vs 평시 90s 아이들 잡담 순환 판단.

const MILESTONES: Array[String] = [
	"Q_F1_START",
	"Q_F1_BLAST",
	"Q_F2_POSTER",
	"Q_F3_PALIN",
	"Q_F0_DISK",
	"Q_F4_BATTERY",
	"Q_F4_SACRIFICE",
	"Q_F5_BOSS_CURE",
	"Q_F5_AI_BATTLE",
	"Q_ENDING",
]


## 현재 달성된 가장 최신 스토리 마일스톤 플래그 반환
static func current_milestone() -> String:
	var latest := ""
	for m: String in MILESTONES:
		if GameState.has_flag(m):
			latest = m
	return latest


## NPC의 현재 대사 시퀀스를 결정 (진행 사건 반응 vs 아이들 잡담 순환)
##
## 1. 진행 상태 (Progressed Reaction):
##    스토리 마일스톤 달성 후 해당 마일스톤의 대사를 처음 들을 때 -> NPC의 주관적 현장 체감/유머 대사 출력.
## 2. 정체/아이들 상태 (Idle Chatter Pool):
##    해당 마일스톤 반응을 이미 들었거나 정체 중일 때 -> 90년대 대학가 밈/개그 대사를 신선하게 순환(cycling) 출력.
static func resolve_npc_sequence(
	_npc_id: StringName, base_seq: StringName, variants: Array, repeat_seq: Variant = null
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
		chosen_seq = StringName(str(d.get("sequence_id", "")))
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


## 특정 대사 시퀀스가 이미 청취되어 아이들 모드로 진입했는지 여부
static func is_idle(seq_id: StringName) -> bool:
	return GameState.get_sequence_seen_count(seq_id) > 0
