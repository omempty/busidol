@echo off
chcp 65001 >nul 2>&1
title delivery intake
cd /d %~dp0
rem Validate + adopt + install everything sitting in 10_submitted (or --from <dir>).
python tools\convert\intake.py %*
pause
