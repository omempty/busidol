@echo off
chcp 65001 >nul 2>&1
title request batch
cd /d %~dp0
rem Pack a self-contained request bundle to hand to an image LLM.
python tools\dev\pack_request.py %*
pause
