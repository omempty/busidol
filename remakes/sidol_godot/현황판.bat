@echo off
chcp 65001 >nul 2>&1
title asset dashboard
cd /d %~dp0
rem Rebuild the static dashboard and open it. No server needed.
python tools\dev\make_dashboard.py
start "" "%~dp0현황판.html"
