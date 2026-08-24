@echo off
chcp 65001 >nul 2>&1
title BSD 시돌이의 모험 - 리메이크
echo ==========================================
echo   BSD 시돌이의 모험 — Godot 리메이크
echo ==========================================
echo.
echo   조작: 방향키 이동 | SPACE 확인 | ENTER 메뉴 | ESC 취소
echo   M: 미니맵 토글
echo.

"%~dp0..\..\_shared\tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." res://scenes/field.tscn

if %errorlevel% neq 0 (
    echo.
    echo [오류] exit code: %errorlevel%
    pause
)
