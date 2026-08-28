@echo off
chcp 65001 >nul 2>&1
title LLM request packages
rem Logic lives in tools\dev\make_requests.ps1
rem cmd parses .bat in the OEM codepage, so Korean text inside a UTF-8 .bat
rem shifts byte offsets and breaks if/goto. Keep this file ASCII-only.
rem Usage: [category] [id]   e.g. portraits prof_mo
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dev\make_requests.ps1" -Category "%~1" -Id "%~2"
pause
