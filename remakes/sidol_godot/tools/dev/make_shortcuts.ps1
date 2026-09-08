#Requires -Version 5.1
<#
  단축아이콘 생성 — repo 루트의 *.bat 실행기를 바로가기(.lnk)로 만든다.
  기본 출력: repo 루트의 바로가기\ 폴더. -Desktop 을 주면 바탕화면에 만든다.
  실행: powershell -ExecutionPolicy Bypass -File tools/dev/make_shortcuts.ps1
  삭제: 같은 명령에 -Remove (출력 폴더의 시돌이 바로가기만 지운다)
#>
param([switch]$Remove, [switch]$Desktop)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Desktop) { $OUTDIR = [Environment]::GetFolderPath("Desktop") }
else { $OUTDIR = Join-Path $ROOT "바로가기" }
if (-not (Test-Path $OUTDIR)) { New-Item -ItemType Directory $OUTDIR | Out-Null }
$PREFIX = "시돌이 "

$TARGETS = @(
  @{ Bat = "통합실행.bat"; Name = "통합 실행기"; Icon = $null },
  @{ Bat = "심사실행.bat"; Name = "심사 보드";   Icon = $null },
  @{ Bat = "현황판.bat";   Name = "현황판";       Icon = $null },
  @{ Bat = "납품처리.bat"; Name = "납품 처리";   Icon = $null },
  @{ Bat = "의뢰생성.bat"; Name = "의뢰 생성";   Icon = $null },
  @{ Bat = "묶음포장.bat"; Name = "묶음 포장";   Icon = $null },
  @{ Bat = "뷰어실행.bat"; Name = "총괄 뷰어";   Icon = $null },
  @{ Bat = "검증실행.bat"; Name = "검증 관문";   Icon = $null },
  @{ Bat = "게임실행.bat"; Name = "게임 실행";   Icon = $null },
  @{ Bat = "에디터실행.bat"; Name = "Godot 에디터"; Icon = $null }
)

$shell = New-Object -ComObject WScript.Shell
foreach ($t in $TARGETS) {
  $lnk = Join-Path $OUTDIR ($PREFIX + $t.Name + ".lnk")
  if ($Remove) {
    if (Test-Path $lnk) { Remove-Item $lnk; Write-Host "삭제: $lnk" }
    continue
  }
  $batPath = Join-Path $ROOT $t.Bat
  if (-not (Test-Path $batPath)) { Write-Host "없음: $batPath" -ForegroundColor Yellow; continue }
  $sc = $shell.CreateShortcut($lnk)
  $sc.TargetPath = $batPath
  $sc.WorkingDirectory = $ROOT
  $sc.Description = "BSD 시돌이 리메이크 — $($t.Name)"
  if ($t.Icon -and (Test-Path $t.Icon)) { $sc.IconLocation = $t.Icon }
  $sc.Save()
  Write-Host "생성: $lnk"
}
Write-Host "완료. '$OUTDIR' 폴더의 '$PREFIX…' 바로가기를 눌러 바로 실행."
if ($Remove) { Write-Host "(삭제 모드였음.)" }
