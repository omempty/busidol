<#
관문 실행 단일 소스 — 로컬(검증실행.bat)과 CI(.github/workflows/verify.yml)가 같은 목록을 쓴다.
목록이 두 군데로 갈라지면 "로컬은 녹색, CI는 빨강"(또는 그 반대)이 생기므로 여기 한 곳에서만 정의한다.

사용: pwsh tools/dev/run_gates.ps1 -Godot <godot 콘솔 실행파일 경로>
#>
param(
    [Parameter(Mandatory = $true)][string]$Godot
)

$ErrorActionPreference = "Stop"
$proj = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# name          = 화면 표기
# args          = godot 인자 (@PROJ@ = 프로젝트 경로)
# fatal         = 비정상 종료 시 관문 실패로 볼 것인가
$gates = @(
    @{ name = "Import";              args = @("--headless", "--path", "@PROJ@", "--import");                                          fatal = $false }
    @{ name = "Validate";            args = @("--headless", "--path", "@PROJ@", "--script", "tools/validate.gd");                     fatal = $true }
    @{ name = "Smoke base";          args = @("--headless", "--path", "@PROJ@", "res://tests/smoke.tscn");                            fatal = $true }
    @{ name = "Smoke field";         args = @("--headless", "--path", "@PROJ@", "--quit-after", "900", "res://tests/smoke_field.tscn"); fatal = $true }
    @{ name = "Smoke battle";        args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_battle.tscn");                     fatal = $true }
    @{ name = "Smoke cutscene";      args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_cutscene.tscn");                   fatal = $true }
    @{ name = "Smoke dialogue";      args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_dialogue.tscn");                   fatal = $true }
    @{ name = "Smoke transitions";   args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_transitions.tscn");                fatal = $true }
    @{ name = "Smoke All-Floors events"; args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_all_floors_events.tscn"); fatal = $true }
    @{ name = "Smoke fx/portrait";   args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_fx.tscn");                        fatal = $true }
    @{ name = "Smoke battle input"; args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_battle_input.tscn");              fatal = $true }
    @{ name = "Smoke AI perception"; args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_ai_perception.tscn");             fatal = $true }
    @{ name = "SelfCheck";           args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_selfcheck.tscn");                  fatal = $true }
    @{ name = "Smoke choice";        args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_choice.tscn");                     fatal = $true }
    @{ name = "Smoke inventory";     args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_inventory.tscn");                  fatal = $true }
    @{ name = "Smoke credit room";   args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_credit_room.tscn");                fatal = $true }
    @{ name = "Script parse check";  args = @("--headless", "--path", "@PROJ@", "--script", "res://tools/check_scripts.gd");          fatal = $true }
    @{ name = "World audit";         args = @("--headless", "--path", "@PROJ@", "res://tools/audit/world_audit.tscn");                fatal = $true }
    # 연속 주행 — 새 게임 하나로 되돌리지 않고 걸어 본다. 앞의 관문들은 검사할 상태를
    # 손으로 세우므로(플래그 주입·층 순간이동) "앞이 열어야 뒤가 열리는" 순서를 못 본다.
    # 판정은 주행 자체의 퇴행만 본다: 한 걸음도 못 걷거나 층을 못 넘으면 실패.
    # 사문화 데이터 목록은 docs/05_status/01_autoplay.md 로 나온다(관문을 빨갛게 하지 않는다).
    # 요구 층수 2 → 5(2026-08-29). 잠긴 계단의 순서·재시도를 고친 뒤 주행이 한 판을
    # 완주한다(F1→F5→엔딩→타이틀, 실측 3회 연속 77초 안팎). 되돌아가면 여기가 빨개진다.
    @{ name = "Autoplay";            args = @("--headless", "--path", "@PROJ@", "res://tools/dev/autoplay.tscn", "--", "--seconds", "240", "--goals", "150", "--require-floors", "5", "--out", "user://autoplay_gate.md"); fatal = $true }
)

$total = $gates.Count + 2   # +2 = 내보내기 포함 규칙 · 원본 대조(python)
$i = 0
foreach ($g in $gates) {
    $i++
    Write-Host ("[{0}/{1}] {2}..." -f $i, $total, $g.name)
    $gargs = @($g.args | ForEach-Object { $_.Replace("@PROJ@", $proj) })
    & $Godot @gargs
    if ($LASTEXITCODE -ne 0 -and $g.fatal) {
        Write-Host ("*** FAIL *** {0} (exit {1})" -f $g.name, $LASTEXITCODE)
        exit 1
    }
}

$i++
Write-Host ("[{0}/{1}] Export pack rules..." -f $i, $total)
python (Join-Path $PSScriptRoot "export_check.py") $Godot
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Export pack rules"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Originals match..." -f $i, $total)
# 원본이 없는 환경(CI·협업자 PC)에서는 스스로 SKIP하고 0을 돌려준다.
python (Join-Path $PSScriptRoot "originals_check.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Originals match"
    exit 1
}

Write-Host ""
Write-Host "  ALL GATES PASSED"
exit 0
