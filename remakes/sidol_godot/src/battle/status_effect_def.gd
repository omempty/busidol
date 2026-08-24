class_name StatusEffectDef
extends Resource
## 상태이상/버프 정의 — 턴 종료 시 틱 처리.

@export var kind: StringName       # &"dot" / &"buff_damage_taken" / &"paralysis"
@export var turns: int = 3
@export var magnitude: int = 0     # dot=턴당 피해, buff=경감 비율(%), paralysis=0
