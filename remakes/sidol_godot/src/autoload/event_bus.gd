extends Node
## 전역 시그널 허브 — 컴포넌트 간 직접 참조 금지, 이 버스로만 통신 (02_design/01 §6).
##
## **쓰이지 않는 시그널은 두지 않는다.** 2026-08-28 정리: encounter_started·skill_granted·
## map_changed는 emit·connect가 각 0곳이라 제거했다. "나중에 쓸 것 같아서" 미리 선언해 두면
## 이 저장소의 지배적 결함(정의는 있는데 아무도 안 읽는 것)을 스스로 만드는 셈이다.
## 필요해지는 시점에 **구독처와 함께** 추가한다.

signal battle_finished(result: StringName)  # &"win" | &"lose" | &"flee"
signal item_obtained(item_id: StringName)  # 발신: field 상자 개봉(구독처는 아직 없음)
signal dialogue_finished(sequence_id: StringName)
signal floor_changed(floor_index: int)
