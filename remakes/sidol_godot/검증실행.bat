@echo off
chcp 65001 >nul 2>&1
title 검증 관문
set GODOT="%~dp0..\..\_shared\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
set PROJ="%~dp0."

echo [1/13] Import...
%GODOT% --headless --path %PROJ% --import 2>nul

echo [2/13] Validate...
%GODOT% --headless --path %PROJ% --script tools/validate.gd 2>nul

echo [3/13] Smoke base...
%GODOT% --headless --path %PROJ% res://tests/smoke.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [4/13] Smoke field...
%GODOT% --headless --path %PROJ% --quit-after 900 res://tests/smoke_field.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [5/13] Smoke battle...
%GODOT% --headless --path %PROJ% res://tests/smoke_battle.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [6/13] Smoke cutscene...
%GODOT% --headless --path %PROJ% res://tests/smoke_cutscene.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [7/13] Smoke dialogue...
%GODOT% --headless --path %PROJ% res://tests/smoke_dialogue.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [8/13] Smoke transitions...
%GODOT% --headless --path %PROJ% res://tests/smoke_transitions.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [9/13] SelfCheck...
%GODOT% --headless --path %PROJ% res://tests/smoke_selfcheck.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [10/13] Smoke choice...
%GODOT% --headless --path %PROJ% res://tests/smoke_choice.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [11/13] Smoke inventory...
%GODOT% --headless --path %PROJ% res://tests/smoke_inventory.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [12/13] Smoke credit room...
%GODOT% --headless --path %PROJ% res://tests/smoke_credit_room.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo.
echo [13/13] Script parse check...
%GODOT% --headless --path %PROJ% --script res://tools/check_scripts.gd 2>nul
if %errorlevel% neq 0 goto :fail

echo   ALL GATES PASSED ✓
goto :eof

:fail
echo.
echo *** FAIL ***
pause
