@echo off
chcp 65001 >nul 2>&1
title Godot 에디터
"%~dp0..\..\_shared\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --editor --path "%~dp0."
