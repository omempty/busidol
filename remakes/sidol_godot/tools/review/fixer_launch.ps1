#Requires -Version 5.1
<#
  셀 편집기 단독 실행기 — 심사 보드를 거치지 않고 sprite_fixer.html을 바로 띄운다.

  왜: 편집기는 서버(review_server.py)의 계약 API 위에서만 제대로 돈다(격자·정렬·검증).
  그래서 "그냥 html을 더블클릭"은 반쪽짜리다. 이 스크립트가 서버 기동 여부를 확인하고
  없을 때만 띄운 뒤 편집기 URL을 연다 — 이미 떠 있으면 중복 기동하지 않는다.

  로직을 .bat이 아니라 .ps1에 두는 것은 이 저장소 관례다: cmd가 배치 파일을 OEM
  코드페이지로 읽어 한글이 든 .bat은 if/goto 해석이 어긋난다(검증실행.bat → run_gates.ps1).
  이 파일은 한글 문자열이 있으므로 반드시 **UTF-8 BOM**으로 저장한다(PS 5.1은 BOM 없는
  UTF-8을 cp949로 읽는다).

  실행:
    셀편집기.bat                         파일 선택기가 뜬다
    셀편집기.bat monsters                해당 카테고리로 선택기를 연다
    셀편집기.bat monsters c_bug_v3.png   그 파일을 바로 연다
#>
[CmdletBinding()]
param(
  [string]$Cat = "",
  [string]$File = "",
  [int]$Port = 8643
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Test-Port([int]$P) {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect("127.0.0.1", $P, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(400)
    $c.Close()
    return $ok
  } catch { return $false }
}

if (Test-Port $Port) {
  Write-Host "서버 이미 실행 중 (:$Port)" -ForegroundColor DarkGray
} else {
  Write-Host "심사 서버 기동 중… (:$Port)" -ForegroundColor Cyan
  Start-Process cmd -ArgumentList "/c", "title review-server && python tools\review\review_server.py $Port" `
                    -WindowStyle Minimized -WorkingDirectory $ROOT
  # 포트가 열릴 때까지 기다린다 — 고정 sleep은 느린 PC에서 빈 페이지를 연다.
  $ready = $false
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 300
    if (Test-Port $Port) { $ready = $true; break }
  }
  if (-not $ready) {
    Write-Host "서버가 응답하지 않는다. python이 PATH에 있는지, 포트 $Port 가 비었는지 확인하라." -ForegroundColor Yellow
    Write-Host "수동 확인: python tools\review\review_server.py $Port" -ForegroundColor Yellow
    Read-Host "  [Enter] 그래도 열기"
  }
}

$url = "http://127.0.0.1:$Port/tools/review/sprite_fixer.html"
$q = @()
if ($Cat)  { $q += "cat=$([uri]::EscapeDataString($Cat))" }
if ($File) { $q += "file=$([uri]::EscapeDataString($File))" }
if ($q.Count) { $url += "?" + ($q -join "&") }

Write-Host "열기: $url" -ForegroundColor Green
if (-not $File) {
  Write-Host "  파일 인자가 없으니 편집기 안에서 고르면 된다(카테고리·검색·썸네일)." -ForegroundColor DarkGray
  Write-Host "  디스크의 PNG는 [파일 열기]·드래그&드롭·Ctrl+V로도 연다." -ForegroundColor DarkGray
}
Start-Process $url
