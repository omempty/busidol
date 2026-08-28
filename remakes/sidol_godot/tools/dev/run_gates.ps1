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
    @{ name = "Smoke fx/portrait";   args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_fx.tscn");                        fatal = $true }
    @{ name = "Smoke battle input"; args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_battle_input.tscn");              fatal = $true }
    @{ name = "SelfCheck";           args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_selfcheck.tscn");                  fatal = $true }
    @{ name = "Smoke choice";        args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_choice.tscn");                     fatal = $true }
    @{ name = "Smoke inventory";     args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_inventory.tscn");                  fatal = $true }
    @{ name = "Smoke credit room";   args = @("--headless", "--path", "@PROJ@", "res://tests/smoke_credit_room.tscn");                fatal = $true }
    @{ name = "Script parse check";  args = @("--headless", "--path", "@PROJ@", "--script", "res://tools/check_scripts.gd");          fatal = $true }
    @{ name = "World audit";         args = @("--headless", "--path", "@PROJ@", "res://tools/audit/world_audit.tscn");                fatal = $true }
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
