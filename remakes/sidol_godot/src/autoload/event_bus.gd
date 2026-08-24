extends Node
## 전역 시그널 허브 — 컴포넌트 간 직접 참조 금지, 이 버스로만 통신 (02_design/01 §6).

signal encounter_started(enemy_id: StringName)
signal battle_finished(result: StringName)  # &"win" | &"lose" | &"flee"
signal item_obtained(item_id: StringName)
signal skill_granted(skill_id: StringName)
signal dialogue_finished(sequence_id: StringName)
signal map_changed(cell: Vector2i)
signal floor_changed(floor_index: int)
