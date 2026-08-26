@echo off
chcp 65001 >nul 2>&1
title LLM 납품 심사
cd /d %~dp0
start "review-server" /min cmd /c "python tools\review\review_server.py 8643"
timeout /t 1 >nul
start "" "http://127.0.0.1:8643/tools/review/review_board.html"
