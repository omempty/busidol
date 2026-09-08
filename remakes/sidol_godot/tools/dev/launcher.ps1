#Requires -Version 5.1
<#
  통합 런처 — 흩어진 개별 실행기(*.bat / tools/**)를 번호 메뉴 하나로 호출한다.
  각 도구의 실제 로직은 건드리지 않고(단일 소스 원칙 유지) 여기서 路만 튼다.
  실행: repo 루트의 통합실행.bat, 또는
        powershell -ExecutionPolicy Bypass -File tools/dev/launcher.ps1
#>
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$GODOT_DIR = Resolve-Path (Join-Path $ROOT "..\\..\\_shared\\tools\\godot") -ErrorAction SilentlyContinue
if ($GODOT_DIR) { $GODOT_DIR = $GODOT_DIR.Path }

function Test-Port([int]$Port) {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect("127.0.0.1", $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(400)
    $c.Close()
    return $ok
  } catch { return $false }
}

function Ensure-Server([int]$Port, [string]$Title, [string]$Command) {
  if (Test-Port $Port) { Write-Host "  (서버 이미 실행 중 :$Port)" -ForegroundColor DarkGray; return }
  Start-Process cmd -ArgumentList "/c", "title $Title && $Command" -WindowStyle Minimized -WorkingDirectory $ROOT
  Start-Sleep -Milliseconds 900
}

function Open-Url([string]$Url) { Start-Process $Url }

function Run-Py([string]$RelScript, [string]$Args = "") {
  $cmd = "python `"$ROOT\\$RelScript`" $Args"
  Write-Host "▶ $cmd" -ForegroundColor Cyan
  Start-Process cmd -ArgumentList "/k", "cd /d `"$ROOT`" && $cmd" -WorkingDirectory $ROOT
}

# --- 메뉴 항목별 동작 -------------------------------------------------------
function Menu-Review {
  Ensure-Server 8643 "review-server" "python tools\\review\\review_server.py 8643"
  Open-Url "http://127.0.0.1:8643/tools/review/review_board.html"
}

function Menu-Fixer {
  $cat = (Read-Host "  카테고리 [monsters]").Trim()
  if (-not $cat) { $cat = "monsters" }
  $file = (Read-Host "  파일명 (예: c_bug_v3.png)").Trim()
  if (-not $file) { Write-Host "  파일명을 입력해야 한다." -ForegroundColor Yellow; return }
  Ensure-Server 8643 "review-server" "python tools\\review\\review_server.py 8643"
  $u = "http://127.0.0.1:8643/tools/review/sprite_fixer.html?cat=$([uri]::EscapeDataString($cat))&file=$([uri]::EscapeDataString($file))"
  Open-Url $u
}

function Menu-Gates {
  $godot = if ($GODOT_DIR) { Join-Path $GODOT_DIR "Godot_v4.7.2-stable_win64_console.exe" } else { "godot" }
  & (Join-Path $ROOT "tools\\dev\\run_gates.ps1") -Godot $godot
  Read-Host "  [Enter] 계속"
}

function Menu-Dashboard {
  python (Join-Path $ROOT "tools\\dev\\make_dashboard.py")
  Open-Url (Join-Path $ROOT "현황판.html")
}

function Menu-Intake {
  $extra = Read-Host "  추가 인자 (없으면 Enter)"
  Run-Py "tools\\convert\\intake.py" $extra
}

function Menu-Request {
  $cat = (Read-Host "  카테고리 (portraits/keyart/monsters/…)").Trim()
  $id = (Read-Host "  ID (비우면 전체)").Trim()
  & (Join-Path $ROOT "tools\\dev\\make_requests.ps1") -Category $cat -Id $id
  Read-Host "  [Enter] 계속"
}

function Menu-Pack {
  $extra = Read-Host "  포장 인자 (예: monsters c_bug)"
  Run-Py "tools\\dev\\pack_request.py" $extra
}

function Menu-Viewer {
  Ensure-Server 8642 "viewer-server" "python -m http.server 8642 --bind 127.0.0.1"
  Open-Url "http://127.0.0.1:8642/tools/viewer.html"
}

function Menu-AssetStatus {
  python (Join-Path $ROOT "tools\\dev\\asset_status.py")
  Read-Host "  [Enter] 계속"
}

function Menu-Game {
  $exe = if ($GODOT_DIR) { Join-Path $GODOT_DIR "Godot_v4.7.2-stable_win64.exe" } else { "godot" }
  Start-Process $exe -ArgumentList "--path", $ROOT, "res://scenes/field.tscn"
}

function Menu-Editor {
  $exe = if ($GODOT_DIR) { Join-Path $GODOT_DIR "Godot_v4.7.2-stable_win64_console.exe" } else { "godot" }
  Start-Process $exe -ArgumentList "--editor", "--path", $ROOT
}

$ITEMS = @(
  @{ Key = "1";  Name = "심사 보드 (납품 승인/반려)";      Act = { Menu-Review } },
  @{ Key = "2";  Name = "셀 편집기 (파일 직접 지정)";      Act = { Menu-Fixer } },
  @{ Key = "3";  Name = "검증 관문 (import+validate+smoke)"; Act = { Menu-Gates } },
  @{ Key = "4";  Name = "현황판 (다시 만들고 열기)";        Act = { Menu-Dashboard } },
  @{ Key = "5";  Name = "납품 처리 (intake 일괄 승인)";     Act = { Menu-Intake } },
  @{ Key = "6";  Name = "의뢰 생성 (LLM 패키지)";           Act = { Menu-Request } },
  @{ Key = "7";  Name = "묶음 포장 (의뢰 번들)";            Act = { Menu-Pack } },
  @{ Key = "8";  Name = "총괄 뷰어";                       Act = { Menu-Viewer } },
  @{ Key = "9";  Name = "에셋 공백 현황";                   Act = { Menu-AssetStatus } },
  @{ Key = "10"; Name = "게임 실행";                       Act = { Menu-Game } },
  @{ Key = "11"; Name = "Godot 에디터";                    Act = { Menu-Editor } }
)

while ($true) {
  Write-Host ""
  Write-Host "=== BSD 시돌이 리메이크 — 통합 실행기 ===" -ForegroundColor Green
  foreach ($it in $ITEMS) { Write-Host ("  [{0}] {1}" -f $it.Key.PadLeft(2), $it.Name) }
  Write-Host "  [ 0] 종료"
  $sel = (Read-Host "  번호").Trim()
  if ($sel -eq "0" -or $sel -eq "q") { break }
  $hit = $ITEMS | Where-Object { $_.Key -eq $sel } | Select-Object -First 1
  if (-not $hit) { Write-Host "  없는 번호다." -ForegroundColor Yellow; continue }
  try { & $hit.Act } catch { Write-Host "  오류: $_" -ForegroundColor Red; Read-Host "  [Enter] 계속" }
}
