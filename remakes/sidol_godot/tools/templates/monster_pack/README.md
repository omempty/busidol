# 몬스터 팩 템플릿 — 새 몬스터 추가 가이드

> 새 몬스터 1종을 추가하려면 아래 3개 파일만 작성하면 된다.
> 코드 수정 0건. Validator가 자동 검증.

## 필요 파일

| 파일 | 위치 | 설명 |
|---|---|---|
| `enemy_def.json` | `data/enemies/` | 스탯·AI 타입·드랍 |
| `battle_move_*.json` | `data/battle_moves/` | 공격·피격·사망 안무 |
| `intro_cutscene.json` (선택) | `data/cutscenes/` | 등장 연출 |

## 1. EnemyDef

```json
{
  "id": "my_monster",
  "display_name": "내 괴물",
  "element": "fire",
  "weaknesses": ["electric"],
  "stats_by_floor": {
    "0": {"hp": [20,30], "ap": [10,15], "dp": [5,8],  "exp": [3,5],  "money": [50,100]},
    "default": {"hp": [40,60], "ap": [20,35], "dp": [10,20], "exp": [10,20], "money": [100,300]}
  },
  "choreography_id": "battle_move_my_monster",
  "sprite_ref": "assets/raw/sprites/my_monster/sheet_v1.png"
}
```

## 2. 전투 안무

```json
{
  "id": "battle_move_my_monster",
  "side": "enemy",
  "length": 1.0,
  "channels": {
    "sprite": [{ "t": 0.0, "actor": "self", "anim": "attack", "pos": [80, 0] }],
    "fx":     [{ "t": 0.6, "effect": "hit_spark", "at": "target_center" }],
    "audio":  [{ "t": 0.0, "sfx": "atk_roar" }, { "t": 0.6, "sfx": "impact" }],
    "logic":  [{ "t": 0.6, "apply_damage": true }]
  }
}
```

## 3. 인카운터 컷신 (선택)

```json
{
  "id": "encounter_my_monster",
  "steps": [
    { "op": "shake", "power": 4, "time": 0.5 },
    { "op": "dialogue", "seq": "@c999" },
    { "op": "start_battle", "enemy": "my_monster" }
  ]
}
```

## 4. 등록

`data/monsters.json`의 해당 층 `species` 배열에 id 추가:
```json
"f2": { "species": ["mad_eye", "my_monster"], "count": 4 }
```
