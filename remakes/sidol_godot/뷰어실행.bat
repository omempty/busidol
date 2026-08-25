@echo off
chcp 65001 >nul 2>&1
title 총괄 뷰어
cd /d %~dp0
start "viewer-server" /min cmd /c "python -m http.server 8642 --bind 127.0.0.1"
timeout /t 1 >nul
start "" "http://127.0.0.1:8642/tools/viewer.html"
