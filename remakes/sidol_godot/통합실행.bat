@echo off
rem Unified launcher - ASCII only (cmd parses .bat in OEM codepage).
rem Real menu lives in tools\dev\launcher.ps1 (PowerShell handles UTF-8).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dev\launcher.ps1"
