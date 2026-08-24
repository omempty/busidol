@echo off
chcp 65001 >nul 2>&1
title 검증 관문
set GODOT="%~dp0..\..\_shared\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
set PROJ="%~dp0."

echo [1/4] Import...
%GODOT% --headless --path %PROJ% --import 2>nul

echo [2/4] Validate...
%GODOT% --headless --path %PROJ% --script tools/validate.gd 2>nul

echo [3/4] Smoke base...
%GODOT% --headless --path %PROJ% res://tests/smoke.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo [4/4] Smoke field...
%GODOT% --headless --path %PROJ% --quit-after 900 res://tests/smoke_field.tscn 2>nul
if %errorlevel% neq 0 goto :fail

echo.
echo   ALL GATES PASSED ✓
goto :eof

:fail
echo.
echo *** FAIL ***
pause
