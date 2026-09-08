@echo off
chcp 65001 >nul 2>&1
title sprite cell fixer
cd /d %~dp0
rem Cell editor standalone launcher. Korean text is kept out of this .bat on purpose:
rem cmd reads batch files in the OEM codepage and multibyte chars break if/goto parsing.
rem All logic lives in tools\review\fixer_launch.ps1 (UTF-8 BOM).
rem   usage: cell-editor.bat [category] [file.png]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\review\fixer_launch.ps1" -Cat "%~1" -File "%~2"
if errorlevel 1 pause
