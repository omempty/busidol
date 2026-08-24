class_name SkillDef
extends Resource
## 스킬 정의 — 마스터 시나리오 §2.2 성장 트리 6종.
## 획득은 이벤트 op grant_skill로만 수행.

@export var id: StringName
@export var display_key: StringName          ## l10n 키
@export var element: StringName              # "physical"/"fire"/"electric"/"none"
@export var targeting: StringName            # "single" / "all_enemies" / "self"
@export var power: int = 10                  # DamageCalculator 기준값
@export var mp_cost: int = 0
@export var status_effects: Array[StringName] = []   # 부착 효과 id 목록
@export var choreography_id: StringName      # battle_moves 안무 매핑
