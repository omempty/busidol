# 자동 주행 결과

**한 판을 이어서 자동으로 몰아 본 결과다.** 생성기: 자동 주행 도구
(`_godot_shared/godot/autoplay/autoplay_driver.gd` + 프로젝트 어댑터).

정적 검사와 단품 실행은 **순서와 누적 상태를 못 본다.** 앞이 열어야 뒤가
열리는 문, 두 번 찾아가야 넘어가는 대화가 그 사각지대다. 여기서는 새 판
하나로 시작해 되돌리지 않고 실제로 몰아 본다.

## 요약

| 항목 | 값 |
|---|---|
| 끝난 이유 | 예산 소진 (목표 150개) |
| 밟은 목표 | 150 |
| 다시 돈 바퀴 | 1 |
| 닿은 구역 | 6 / 6 |
| 걸음 | 6927 |
| 밟은 목표(누적) | 157 |
| 전투 | 74 |
| 연 상자 | 99 |
| 나눈 대화 | 7 |
| 쓰러져 되살린 횟수 | 0 |
| 지도 밝힌 칸 | f0 12372 · f1 11257 |

## 닿지 못한 구역

없음 — 전부 닿았다.

## 닿은 구역과 들어간 경위

| 구역 | 들어간 경위 |
|---|---|
| 0 | 계단 stairs_east_down |
| 1 | 주행 시작 |
| 2 | 계단 stairs_center_up_f1 |
| 3 | 계단 stairs_center_up_f2 |
| 4 | 계단 stairs_center_up_f3 |
| 5 | 계단 stairs_center_up_f4 |

## 막힌 자리

갈 수 있다고 본 곳인데 실제로는 못 갔다.

| 구역 | 목표 | 종류 | 증상 |
|---|---|---|---|
| 0 | f0_disk@180,53 | 트리거(zone) | 걷다가 막혔다 — (180, 52) 부근에서 한 걸음이 나가지 않았다 |
| 4 | f4_cache@145,50 | 트리거(interact) | 걷다가 막혔다 — (99, 54) 부근에서 한 걸음이 나가지 않았다 |
| 4 | afterschool_student | NPC | 걷다가 막혔다 — (99, 53) 부근에서 한 걸음이 나가지 않았다 |
| 4 | stairs_center_down | 계단 | 걷다가 막혔다 — (93, 46) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_warn@103,23 | 트리거(zone) | 걷다가 막혔다 — (102, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@99,23 | 트리거(zone) | 걷다가 막혔다 — (102, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@97,23 | 트리거(zone) | 걷다가 막혔다 — (99, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@99,23 | 트리거(zone) | 걷다가 막혔다 — (101, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@97,23 | 트리거(zone) | 걷다가 막혔다 — (98, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_allin@98,18 | 트리거(zone) | 걷다가 막혔다 — (99, 22) 부근에서 한 걸음이 나가지 않았다 |
| 3 | lab_student | NPC | 걷다가 막혔다 — (99, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@99,23 | 트리거(zone) | 걷다가 막혔다 — (101, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_fog_choke@97,23 | 트리거(zone) | 걷다가 막혔다 — (100, 23) 부근에서 한 걸음이 나가지 않았다 |
| 3 | f3_quiz_gate@125,21 | 트리거(zone) | 걷다가 막혔다 — (98, 23) 부근에서 한 걸음이 나가지 않았다 |

## 밟은 목표 (순서대로)

| 구역 | 목표 | 종류 | 이름 |
|---|---|---|---|
| 1 | stairs_east_down | 계단 | f1 → f0 |
| 0 | cafeteria_girl | NPC | 식당 아가씨 |
| 0 | guard_idle | NPC | 수위 아저씨 |
| 0 | librarian | NPC | 지하 사서 |
| 0 | chest@143,29 | 상자 | ATT 198 |
| 0 | chest@135,21 | 상자 | ATT 198 |
| 0 | chest@122,3 | 상자 | ATT 184 |
| 0 | chest@165,2 | 상자 | ATT 198 |
| 0 | chest@184,16 | 상자 | ATT 184 |
| 0 | chest@188,16 | 상자 | ATT 185 |
| 0 | chest@192,16 | 상자 | ATT 184 |
| 0 | chest@196,16 | 상자 | ATT 185 |
| 0 | chest@196,18 | 상자 | ATT 184 |
| 0 | chest@196,20 | 상자 | ATT 185 |
| 0 | chest@196,22 | 상자 | ATT 184 |
| 0 | chest@196,24 | 상자 | ATT 198 |
| 0 | chest@192,18 | 상자 | ATT 185 |
| 0 | chest@192,20 | 상자 | ATT 184 |
| 0 | chest@192,22 | 상자 | ATT 185 |
| 0 | chest@192,24 | 상자 | ATT 186 |
| 0 | chest@188,18 | 상자 | ATT 184 |
| 0 | chest@188,20 | 상자 | ATT 185 |
| 0 | chest@188,22 | 상자 | ATT 172 |
| 0 | chest@188,24 | 상자 | ATT 184 |
| 0 | chest@196,60 | 상자 | ATT 198 |
| 0 | chest@115,60 | 상자 | ATT 198 |
| 0 | chest@111,6 | 상자 | ATT 199 |
| 0 | chest@111,2 | 상자 | ATT 198 |
| 0 | chest@86,8 | 상자 | ATT 199 |
| 0 | chest@82,8 | 상자 | ATT 150 |
| 0 | chest@80,8 | 상자 | ATT 184 |
| 0 | chest@41,11 | 상자 | ATT 199 |
| 0 | chest@39,11 | 상자 | ATT 184 |
| 0 | chest@38,2 | 상자 | ATT 199 |
| 0 | chest@27,11 | 상자 | ATT 184 |
| 0 | chest@28,20 | 상자 | ATT 199 |
| 0 | chest@4,20 | 상자 | ATT 150 |
| 0 | chest@2,20 | 상자 | ATT 184 |
| 0 | chest@6,11 | 상자 | ATT 199 |
| 0 | chest@4,11 | 상자 | ATT 186 |
| 0 | chest@2,11 | 상자 | ATT 150 |
| 0 | chest@4,3 | 상자 | ATT 199 |
| 0 | chest@2,3 | 상자 | ATT 184 |
| 0 | chest@39,20 | 상자 | ATT 199 |
| 0 | chest@14,60 | 상자 | ATT 186 |
| 0 | chest@26,43 | 상자 | ATT 186 |
| 0 | chest@28,43 | 상자 | ATT 184 |
| 0 | chest@84,46 | 상자 | ATT 198 |
| 0 | chest@87,39 | 상자 | ATT 198 |
| 0 | stairs_east_up_f0 | 계단 | f0 → f1 |
| 1 | tutor_dumb | NPC | 멍청 조교 |
| 1 | chest@23,13 | 상자 | ATT 199 |
| 1 | chest@23,11 | 상자 | ATT 199 |
| 1 | chest@19,35 | 상자 | ATT 150 |
| 1 | chest@19,40 | 상자 | ATT 199 |
| 1 | chest@10,41 | 상자 | ATT 152 |
| 1 | chest@10,43 | 상자 | ATT 199 |
| 1 | chest@33,45 | 상자 | ATT 156 |
| 1 | chest@69,43 | 상자 | ATT 159 |
| 1 | chest@69,45 | 상자 | ATT 198 |
| 1 | chest@106,18 | 상자 | ATT 199 |
| 1 | chest@135,58 | 상자 | ATT 172 |
| 1 | chest@151,52 | 상자 | ATT 199 |
| 1 | chest@155,52 | 상자 | ATT 199 |
| 1 | chest@155,54 | 상자 | ATT 171 |
| 1 | chest@155,56 | 상자 | ATT 198 |
| 1 | f1_sopo@163,18 | 트리거(zone) | f1_sopo |
| 1 | f1_power@190,26 | 트리거(interact) | f1_power |
| 1 | f1_gas@12,32 | 트리거(zone) | f1_gas |
| 1 | f1_blast@100,63 | 트리거(interact) | f1_blast |
| 1 | stairs_center_up_f1 | 계단 | f1 → f2 |
| 2 | f2_poster@100,63 | 트리거(interact) | f2_poster |
| 2 | f2_spark_warn@36,9 | 트리거(zone) | f2_spark_warn |
| 2 | f2_spark_zap@36,9 | 트리거(zone) | f2_spark_zap |
| 2 | f2_spark_zap@37,9 | 트리거(zone) | f2_spark_zap |
| 2 | f2_cache@3,4 | 트리거(interact) | f2_cache |
| 2 | f2_spark_zap@36,9 | 트리거(zone) | f2_spark_zap |
| 2 | f2_poster@100,63 | 트리거(interact) | f2_poster |
| 2 | f2_hp_room@195,20 | 트리거(zone) | f2_hp_room |
| 2 | f2_poster@100,63 | 트리거(interact) | f2_poster |
| 2 | stairs_center_up_f2 | 계단 | f2 → f3 |
| 3 | stairs_center_up_f3 | 계단 | f3 → f4 |
| 4 | f4_sacrifice@100,63 | 트리거(interact) | f4_sacrifice |
| 4 | stairs_center_up_f4 | 계단 | f4 → f5 |
| 5 | f5_sw3_hint@56,40 | 트리거(interact) | f5_sw3_hint |
| 5 | f5_sw2_hint@50,40 | 트리거(interact) | f5_sw2_hint |
| 5 | f5_sw1@44,40 | 트리거(interact) | f5_sw1 |
| 5 | f5_sw2_ok@50,40 | 트리거(interact) | f5_sw2_ok |
| 5 | stairs_center_down | 계단 | f5 → f4 |
| 4 | f4_battery_gate@100,58 | 트리거(zone) | f4_battery_gate |
| 4 | f4_volt_warn@100,56 | 트리거(zone) | f4_volt_warn |
| 4 | f4_volt_zap@100,55 | 트리거(zone) | f4_volt_zap |
| 4 | f4_volt_zap@100,54 | 트리거(zone) | f4_volt_zap |
| 4 | f4_volt_zap@99,54 | 트리거(zone) | f4_volt_zap |
| 4 | f4_volt_zap@99,55 | 트리거(zone) | f4_volt_zap |
| 4 | chest@132,60 | 상자 | ATT 199 |
| 4 | f4_cache@145,50 | 트리거(interact) | f4_cache |
| 4 | afterschool_student | NPC | 잔류생 |
| 4 | chest@17,10 | 상자 | ATT 198 |
| 4 | f4_cache@145,50 | 트리거(interact) | f4_cache |
| 4 | chest@144,60 | 상자 | ATT 198 |
| 4 | f4_cache@145,50 | 트리거(interact) | f4_cache |
| 4 | chest@166,58 | 상자 | ATT 199 |
| 4 | chest@164,21 | 상자 | ATT 199 |
| 4 | chest@164,19 | 상자 | ATT 199 |
| 4 | chest@160,21 | 상자 | ATT 199 |
| 4 | chest@155,22 | 상자 | ATT 199 |
| 4 | chest@133,22 | 상자 | ATT 199 |
| 4 | chest@125,22 | 상자 | ATT 198 |
| 4 | chest@133,14 | 상자 | ATT 172 |
| 4 | chest@169,22 | 상자 | ATT 198 |
| 4 | chest@183,31 | 상자 | ATT 198 |
| 4 | chest@191,57 | 상자 | ATT 198 |
| 4 | chest@186,60 | 상자 | ATT 198 |
| 4 | chest@113,60 | 상자 | ATT 198 |
| 4 | chest@70,45 | 상자 | ATT 173 |
| 4 | chest@63,45 | 상자 | ATT 198 |
| 4 | chest@52,45 | 상자 | ATT 172 |
| 4 | chest@33,45 | 상자 | ATT 198 |
| 4 | chest@45,45 | 상자 | ATT 198 |
| 4 | chest@24,39 | 상자 | ATT 171 |
| 4 | chest@4,45 | 상자 | ATT 199 |
| 4 | chest@14,45 | 상자 | ATT 198 |
| 4 | chest@1,10 | 상자 | ATT 198 |
| 4 | chest@17,4 | 상자 | ATT 198 |
| 4 | chest@72,8 | 상자 | ATT 199 |
| 4 | stairs_east_up_f4 | 계단 | f4 → f5 |
| 5 | f5_sw3_ok@56,40 | 트리거(interact) | f5_sw3_ok |
| 5 | f5_cache@50,44 | 트리거(interact) | f5_cache |
| 5 | stairs_east_down | 계단 | f5 → f4 |
| 4 | stairs_east_down | 계단 | f4 → f3 |
| 3 | f3_fog_choke@101,23 | 트리거(zone) | f3_fog_choke |
| 3 | f3_fog_choke@103,23 | 트리거(zone) | f3_fog_choke |
| 3 | prof_chem | NPC | 화공과 교수 |
| 3 | f3_drag@111,19 | 트리거(zone) | f3_drag |
| 3 | chest@83,58 | 상자 | ATT 198 |
| 3 | chest@61,42 | 상자 | ATT 199 |
| 3 | f3_allin@98,18 | 트리거(zone) | f3_allin |
| 3 | f3_fog_choke@99,23 | 트리거(zone) | f3_fog_choke |
| 3 | f3_fog_choke@97,23 | 트리거(zone) | f3_fog_choke |
| 3 | chest@83,58 | 상자 | ATT 198 |
| 3 | lab_student | NPC | 랩실생도 |
| 3 | chest@161,57 | 상자 | ATT 198 |
| 3 | f3_quiz_gate@125,21 | 트리거(zone) | f3_quiz_gate |
| 3 | lab_student | NPC | 랩실생도 |
| 3 | chest@186,28 | 상자 | ATT 199 |
| 3 | chest@185,19 | 상자 | ATT 198 |
| 3 | chest@193,28 | 상자 | ATT 198 |
| 3 | chest@159,60 | 상자 | ATT 198 |
| 3 | chest@147,54 | 상자 | ATT 198 |
| 3 | chest@147,57 | 상자 | ATT 198 |
| 3 | chest@83,58 | 상자 | ATT 198 |
| 3 | chest@51,42 | 상자 | ATT 161 |
| 3 | chest@83,58 | 상자 | ATT 198 |
| 3 | chest@30,45 | 상자 | ATT 163 |
| 3 | chest@17,45 | 상자 | ATT 198 |
| 3 | chest@11,45 | 상자 | ATT 198 |

## 밟았는데 아무 일도 없었다

**데이터에는 있는데 게임에는 없는 것들이다.** 도구가 실제로 그 앞에
서서 조사했지만 플래그도 대사도 상자도 열리지 않았다.

| 층 | 종류 | 이름 | 좌표 |
|---|---|---|---|
| f2 | 트리거(interact) | f2_poster | (100, 63) |
| f2 | 트리거(zone) | f2_spark_zap | (36, 9) |
| f4 | 트리거(interact) | f4_cache | (145, 50) |
| f3 | 상자 | ATT 198 | (83, 58) |
| f3 | NPC | 랩실생도 | (158, 22) |

## 걸어서 닿을 수 없다

좌표는 적혀 있으나 **그 층을 마지막으로 훑었을 때** 걸어서 그 앞에
설 수 없었던 것들이다(2×2 몸이 들어갈 앵커가 없거나 길이 끊겼다).

| 층 | 종류 | 이름 | 좌표 |
|---|---|---|---|
| f0 | 상자 | ATT 198 | (115, 44) |
| f0 | 상자 | ATT 185 | (184, 18) |
| f0 | 상자 | ATT 184 | (184, 20) |
| f0 | 상자 | ATT 184 | (184, 22) |
| f0 | 상자 | ATT 186 | (184, 24) |
| f0 | 상자 | ATT 186 | (2, 23) |
| f0 | 상자 | ATT 184 | (2, 32) |
| f0 | 상자 | ATT 199 | (4, 23) |
| f0 | 상자 | ATT 150 | (40, 2) |
| f0 | 상자 | ATT 199 | (42, 2) |
| f2 | 상자 | ATT 157 | (158, 16) |
| f2 | 상자 | ATT 198 | (158, 18) |
| f3 | 상자 | ATT 172 | (1, 4) |
| f3 | 상자 | ATT 198 | (106, 22) |
| f3 | 상자 | ATT 172 | (109, 54) |
| f3 | 상자 | ATT 198 | (109, 57) |
| f3 | 상자 | ATT 173 | (132, 22) |
| f3 | 상자 | ATT 198 | (150, 22) |
| f3 | 상자 | ATT 171 | (166, 60) |
| f3 | 상자 | ATT 172 | (190, 19) |
| f3 | 상자 | ATT 172 | (67, 10) |
| f3 | 상자 | ATT 199 | (93, 22) |
| f4 | 상자 | ATT 164 | (1, 4) |
| f4 | 상자 | ATT 198 | (103, 15) |
| f4 | 상자 | ATT 198 | (125, 14) |
| f4 | 상자 | ATT 172 | (160, 17) |
| f4 | 상자 | ATT 199 | (160, 19) |
| f4 | 상자 | ATT 198 | (29, 2) |
| f4 | 상자 | ATT 198 | (35, 2) |
| f4 | 상자 | ATT 199 | (47, 2) |
| f4 | 상자 | ATT 172 | (51, 2) |
| f4 | 상자 | ATT 199 | (76, 8) |

## 좌표가 애초에 조사 불가

없음.
