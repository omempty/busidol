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
	base_seq: StringName, variants: Array, repeat_seq: Variant = null, record_seen: bool = true
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
	# **청취 기록은 여기(고르는 순간)에 남긴다 — 대화가 끝나는 순간이 아니다.**
	#
	# 미리보기(말풍선 장식 판단)는 기록 없이 골라야 한다 — 프롬프트가 매 프레임
	# 고르는데 그때마다 기록하면 앞에 서 있기만 해도 회차가 돌아가 버린다
	# (2026-09-11 실측: 첫 대화가 전문이 아니라 반복으로 열렸다).
	# 끝나는 순간(`DialogueBox.finished`)으로 옮기고 싶어지는 게 자연스럽지만 두 가지가 막는다.
	#  1. 카운터의 키는 **여기서 고른 chosen_seq(기준 시퀀스)**인데, finished가 실어 보내는 건
	#     실제로 재생된 시퀀스다. 순환 중이면 그건 repeat 풀의 항목(…_repeat_1)이라 서로 다르다.
	#     그대로 기록하면 기준 시퀀스의 seen_count가 1에서 멈춰 순환이 idx 0에 얼어붙는다.
	#     제대로 하려면 필드가 "어느 기준 시퀀스로 열었는지"를 따로 들고 다녀야 한다.
	#  2. 그렇게 옮겨도 "안 읽었는데 기록" 은 안 닫힌다. op 스텝이 0번이면 DialogueBox._load_step()이
	#     곧장 close()를 부르고, close()는 한 줄도 안 보여 준 채로 finished를 쏜다.
	# 즉 옮겨도 이득이 없고 회귀만 진다. 대신 **읽을 줄이 하나도 없는 시퀀스는 세지 않는다** —
	# 정확히 그 경우(빈 시퀀스, op 전용 시퀀스)만 예외로 판다. 필드도 빈 시퀀스면 대화를 열지 않고
	# 되돌아가므로(scenes/field.gd `_start_dialogue`), 그때 카운터만 오르던 어긋남도 같이 닫힌다.
	if _has_readable_line(chosen_seq) and record_seen:
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


## 그 시퀀스가 **화면에 한 줄이라도 띄우는가**. op 스텝은 대사가 아니라 명령이라
## (DialogueBox._load_step()이 close()하고 op_requested를 쏜다) 읽은 것으로 치지 않는다.
## 2026-09-06 실측: 현재 91개 시퀀스 전부 0번 스텝이 대사라 이 함수는 항상 true다 —
## 즉 지금 동작을 바꾸지 않는 방어선이고, op 전용 변형을 나중에 쓰게 될 때를 위한 것이다.
static func _has_readable_line(seq: StringName) -> bool:
	for s: Variant in Database.sequence(seq):
		if s is not Dictionary:
			continue
		var d: Dictionary = s
		if str(d.get("op", "")).is_empty() and not str(d.get("text", "")).is_empty():
			return true
	return false
