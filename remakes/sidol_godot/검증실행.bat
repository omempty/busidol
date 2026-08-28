@echo off
chcp 65001 >nul 2>&1
title 검증 관문
rem 관문 목록의 단일 소스는 tools\dev\run_gates.ps1 — CI(.github/workflows/verify.yml)도 같은 파일을 쓴다.
set GODOT_EXE=%~dp0..\..\_shared\tools\godot\Godot_v4.7.2-stable_win64_console.exe

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dev\run_gates.ps1" -Godot "%GODOT_EXE%"
if %errorlevel% neq 0 goto :fail
goto :eof

:fail
echo.
echo *** FAIL ***
pause
