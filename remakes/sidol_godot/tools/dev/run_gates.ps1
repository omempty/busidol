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

$total = $gates.Count + 11  # +11 = 내보내기 · 원본 대조 · SPR 알파 · 시트 연산 · 자동보정 계획 · 지적 면제 · 설치 시트 · 웹 프롬프트 · 초상 배선 · 심사보드 · 소품 덧층(python)
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

$i++
Write-Host ("[{0}/{1}] Props overlay..." -f $i, $total)
# 소품은 원본 맵 3층에 못 쓰고 덧층(data/maps/props_f*.json)으로만 얹는다. 여기서 보는 것은
# 스키마·정본 id·크기·맵 범위·겹침·원본 ATT다. 통로 차단(도달 가능성)은 Placement가 정본이라
# GDScript 쪽 관문이 본다 — 파이썬으로 옮기면 같은 규칙이 두 벌이 된다.
python (Join-Path $PSScriptRoot "props_check.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Props overlay"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] SPR sprite alpha..." -f $i, $total)
# 원작 SPR 파생 에셋(캐릭터 시트 15 · 아이템 아이콘 35 · obj 아틀라스 · 주인공 시트)이
# "지금 원작에서 다시 구운 것"과 픽셀 단위로 같은가. 2026-09-07에 RGB 순검정 사후 키잉과
# flood-fill 배경 제거가 외곽선 204,932px를 지운 사고가 있었다(원작 팔레트의 검정 인덱스는
# 0 하나가 아니라 9개 — 0과 224~231). 구멍 개수 같은 간접 지표는 원작 데이터와 구별이 안 돼
# 여기서는 원본 재굽기 대조만 쓴다. 원본 없으면 스스로 SKIP.
python (Join-Path $PSScriptRoot "spr_alpha_check.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** SPR sprite alpha"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Sheet ops..." -f $i, $total)
# 시트 픽셀 연산(sheet_ops.py)의 실측 시험. 이 규칙은 검증기·설치기·셀 편집기가 함께
# 쓰는 정본이라 조용히 어긋나면 "편집기는 깨끗한데 관문은 반려"가 난다.
# 부정 시험(일부러 어긋난 시트로 계측이 빨개지는지)까지 포함한다.
python (Join-Path $PSScriptRoot "..\convert\test_sheet_ops.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Sheet ops"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Autofix plan..." -f $i, $total)
# 검증기 지적 -> 자동보정 계획(autofix_plan.py)의 표. 여기가 틀리면 편집기가
# **고칠 수 없는 지적에 연산을 돌려 그림을 깎는다**(실측: 소프트 알파 시트에
# quantize를 돌려 내용 -12%, 없던 정렬 ERR 2건). 부정 시험까지 포함한다.
python (Join-Path $PSScriptRoot "..\convert\test_autofix_plan.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Autofix plan"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Waivers..." -f $i, $total)
# 지적 면제(FORCE OK). 관문에 구멍을 내는 기능이라 **무엇을 면제할 수 없는가**를 잰다 —
# 크기·스펙·빈 칸을 넘기면 설치와 재생이 실제로 깨진다. 사유 없이 걸리는지도 본다.
python (Join-Path $PSScriptRoot "..\convert\test_waivers.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Waivers"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Installed sheets..." -f $i, $total)
# **게임이 읽는 그림**이 **게임이 읽는 계약**과 맞는가. 납품 검증기는 10_submitted에만
# 돌아서, 설치 뒤에 어긋난 것을 아무도 못 봤다(실측: 11종 중 3종이 낡은 산출물이었고
# null_pointer는 11프레임이 하단 정렬을 어긴 채 게임에 들어가 있었다).
python (Join-Path $PSScriptRoot "installed_sheets_check.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Installed sheets"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Web prompt..." -f $i, $total)
# 프롬프트가 스펙의 값을 **실제로 읽는가**. 화면 표시 크기(cell.w)는 스펙에 있었는데
# 설치기만 읽고 프롬프트는 안 읽었다 — 그래서 19종 중 12종이 절반으로 줄어드는데도
# 전부에게 같은 크기를 지시했다. 프롬프트와 설치기의 배율이 갈라지면 여기서 걸린다.
python (Join-Path $PSScriptRoot "..\convert\test_web_prompt.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Web prompt"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Portrait speakers..." -f $i, $total)
# 설치된 초상이 **화자 이름과 이어져 있는가**. 스펙의 name만 보던 조회기 때문에
# npc_tutor_dumb(name '화공과 조교')이 대사 화자 '멍청 조교'와 안 이어져, 초상이
# 설치돼 있는데도 12줄 내내 조용히 안 떴다(유저 신고).
python (Join-Path $PSScriptRoot "portrait_speakers_check.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Portrait speakers"
    exit 1
}

$i++
Write-Host ("[{0}/{1}] Review board..." -f $i, $total)
# 심사보드를 서버째 띄워 브라우저로 눌러 본다(삭제). 코드를 읽어서는 멀쩡한데 실제로는
# 안 되는 것처럼 보이던 자리다 — 목록 재읽기가 3.9초 걸려 카드가 남아 있었고, 서버를
# 재시작하지 않으면 옛 프로세스가 "알 수 없는 액션"을 돌려줬다. playwright가 없으면 건너뛴다.
python (Join-Path $PSScriptRoot "..eviewoard_probe.py")
if ($LASTEXITCODE -ne 0) {
    Write-Host "*** FAIL *** Review board"
    exit 1
}

Write-Host ""
Write-Host "  ALL GATES PASSED"
exit 0
