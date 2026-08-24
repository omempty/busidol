@echo off
rem BSD 시돌이의 모험 - DOSBox 원클릭 실행 (스크린샷: Ctrl+F5)
rem 캡처 저장: remakes\sidol_godot\assets\raw\dosbox_capture (gitignored)
set REPO=%~dp0..\..
set CONF=%TEMP%\sidol_portable.conf
> "%CONF%" (
  echo [sdl]
  echo output=surface
  echo [dosbox]
  echo machine=svga_s3
  echo captures=%REPO%\remakes\sidol_godot\assets\raw\dosbox_capture
  echo [cpu]
  echo core=normal
  echo cycles=fixed 20000
  echo [sblaster]
  echo sbtype=sb16
  echo sbbase=220
  echo irq=7
  echo dma=1
  echo [autoexec]
  echo mount c "%REPO%\originals\1995_sidol_bsd_dos"
  echo c:
  echo sidol.exe
  echo exit
)
if not exist "%REPO%\remakes\sidol_godot\assets\raw\dosbox_capture" mkdir "%REPO%\remakes\sidol_godot\assets\raw\dosbox_capture"
start "" "C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe" -conf "%CONF%"
