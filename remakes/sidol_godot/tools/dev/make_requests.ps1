<#
그래픽 의뢰 패키지 생성 — 카테고리 선택 + 현황 출력.

로직을 .bat이 아니라 여기 두는 이유: cmd는 배치 파일을 OEM 코드페이지로 파싱하는데
파일이 UTF-8이면 한글에서 바이트 위치가 어긋나 `if`/`goto`가 깨진다(실측).
`검증실행.bat` → `run_gates.ps1`과 같은 구조로, .bat은 ASCII 실행기만 남긴다.

사용:
  pwsh tools/dev/make_requests.ps1                      # 메뉴
  pwsh tools/dev/make_requests.ps1 -Category portraits  # 그 카테고리 전량
  pwsh tools/dev/make_requests.ps1 -Category portraits -Id prof_mo   # 한 건만
#>
param(
    [string]$Category = "",
    [string]$Id = ""
)

$ErrorActionPreference = "Stop"
$proj = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $proj
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 카테고리 → 생성기. 순서는 지금 비어 있는 정도(보스 > 아이콘 > NPC > 초상 > 키아트)를 따른다.
$gens = [ordered]@{
    "monsters"  = @{ script = "tools/convert/export_monster_packages.py";   label = "몬스터·보스" }
    "remaster"  = @{ script = "tools/convert/export_monster_remaster_packages.py"; label = "원작 몬스터 리마스터" }
    "items"     = @{ script = "tools/convert/export_item_icon_packages.py"; label = "아이템 아이콘" }
    "npcs"      = @{ script = "tools/convert/export_npc_packages.py";       label = "필드 NPC" }
    "portraits" = @{ script = "tools/convert/export_portrait_packages.py";  label = "대화 초상" }
    "keyart"    = @{ script = "tools/convert/export_keyart_packages.py";    label = "컷신 키아트" }
    "effects"   = @{ script = "tools/convert/export_effect_packages.py";    label = "전투 이펙트" }
    "battle_cuts" = @{ script = "tools/convert/export_battle_cut_packages.py"; label = "전투 대형 컷" }
    "battle_actors" = @{ script = "tools/convert/export_battle_actor_packages.py"; label = "전투 SD 시트" }
}

function Show-Status {
    python tools/dev/asset_status.py
}

if (-not $Category) {
    Write-Host ""
    Write-Host "  어떤 의뢰 패키지를 만들까요"
    Write-Host ""
    $i = 1
    foreach ($k in $gens.Keys) {
        Write-Host ("   {0}. {1,-12} {2}" -f $i, $gens[$k].label, $k)
        $i++
    }
    Write-Host ("   {0}. 전부" -f $i)
    Write-Host "   0. 현황만 보기"
    Write-Host ""
    $pick = Read-Host "번호 입력"
    if ($pick -eq "0") { Show-Status; return }
    $keys = @($gens.Keys)
    if ([int]$pick -ge 1 -and [int]$pick -le $keys.Count) {
        $Category = $keys[[int]$pick - 1]
    } elseif ([int]$pick -eq ($keys.Count + 1)) {
        $Category = "all"
    } else {
        Write-Host "알 수 없는 선택: $pick"
        return
    }
}

$targets = if ($Category -eq "all") { @($gens.Keys) } else { @($Category) }
foreach ($cat in $targets) {
    if (-not $gens.Contains($cat)) {
        Write-Host "알 수 없는 카테고리: $cat  (가능: $($gens.Keys -join ', '), all)"
        return
    }
    Write-Host ""
    Write-Host ("== {0} ({1})" -f $gens[$cat].label, $cat)
    if ($Id) { python $gens[$cat].script $Id } else { python $gens[$cat].script }
}

Write-Host ""
Write-Host "  패키지 위치  assets\raw\llm\<카테고리>\<id>\prompt.md"
Write-Host "  그림 LLM에는 prompt.md 전문 + 그 폴더 이미지 전부 + 카테고리 루트 palette_swatch.png 만 준다"
Write-Host "  요약 참조    assets\gen\prompts\PROMPTING_QUICKGUIDE.md"
Write-Host ""
Show-Status
