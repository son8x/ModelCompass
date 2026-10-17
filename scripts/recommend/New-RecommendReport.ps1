#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Đề xuất model xKiro nên gắn ⭐ theo NHÓM (free/L/B/A/S) và theo MỤC ĐÍCH
    (reasoning/code/analysis/writing/vision/omni/translate/fast/lecture/bulk/flagship).
    PHA 1: CHỈ BÁO CÁO (mặc định). PHA 2: -Apply ghi ⭐ vào name (backup + validate).

.DESCRIPTION
    Tầng 3 (orchestrator) của đề xuất ⭐. Nạp 2 thư viện cùng nhóm:
      - Get-ModelCandidates.ps1  (tầng 1) — dựng danh sách ứng viên từ config + catalog.
      - Resolve-StarRules.ps1    (tầng 2) — áp rule → chọn ⭐ theo nhóm & mục đích.
    Rồi in bảng đề xuất + DIFF so với ⭐ hiện có trong config.

    Nguồn "khả năng" model: catalog xKiro KHÔNG có metadata (name/modality rỗng, created=1) nên
    tầng 2 dùng heuristic tên/id + BẢNG TRA TAY scripts/recommend/model-capabilities.json.
    Giá/context lấy từ docs/catalogs/xkiro.json. Pool = model ĐANG CÓ trong config (đã probe)
    → không đề xuất model chết.

    MẶC ĐỊNH CHỈ IN BÁO CÁO. -Report ghi thêm Markdown vào reports/. -Apply ghi ⭐ vào config.

.PARAMETER ConfigPath
    File config dev. Mặc định: configs/development/opencode.jsonc.

.PARAMETER CatalogPath
    Catalog xKiro. Mặc định: docs/catalogs/xkiro.json.

.PARAMETER CapabilitiesPath
    Bảng tra khả năng tay. Mặc định: scripts/recommend/model-capabilities.json.

.PARAMETER Provider
    Provider xKiro xét. Mặc định: cả 1-xkiro-free và 2-xkiro-max.

.PARAMETER Report
    Ghi báo cáo Markdown vào reports/recommend-<timestamp>.md.

.PARAMETER Apply
    GHI ⭐ vào name trong config (Pha 2). Mặc định KHÔNG ghi — chỉ báo cáo diff.
    Tự backup config (configs\development\.backup) rồi validate.

.PARAMETER SkipValidation
    Với -Apply: bỏ qua validate sau khi ghi (không khuyến khích).

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function (dùng cho test dot-source), không chạy.

.EXAMPLE
    pwsh scripts/recommend/New-RecommendReport.ps1
    pwsh scripts/recommend/New-RecommendReport.ps1 -Report
    pwsh scripts/recommend/New-RecommendReport.ps1 -Apply
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$CatalogPath,
    [string]$CapabilitiesPath,
    [string[]]$Provider,
    [switch]$Report,
    [switch]$Apply,
    [switch]$SkipValidation,
    [switch]$SkipRun
)
Set-StrictMode -Version Latest

# Chụp cờ TRƯỚC khi dot-source (quirk PowerShell: script con cùng tên param ghi đè biến).
$repSkipRun      = [bool]$SkipRun
$repConfigPath   = $ConfigPath
$repCatalogPath  = $CatalogPath
$repCapPath      = $CapabilitiesPath
$repProvider     = @($Provider)
$repReport       = [bool]$Report
$repApply        = [bool]$Apply
$repSkipVal      = [bool]$SkipValidation

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
# Format-Price (Compare-Prices) + Resolve-TierFromName / Resolve-TierFromPrice (Update-XKiroModels).
. (Get-ScriptPath 'Update-XKiroModels.ps1') -SkipRun
# Tầng 1 + tầng 2 (thư viện thuần, không có param nên không ghi đè biến).
. (Join-Path $PSScriptRoot 'Get-ModelCandidates.ps1')
. (Join-Path $PSScriptRoot 'Resolve-StarRules.ps1')

# Khôi phục cờ sau dot-source.
$SkipRun          = $repSkipRun
$ConfigPath       = $repConfigPath
$CatalogPath      = $repCatalogPath
$CapabilitiesPath = $repCapPath
$Provider         = $repProvider
$Report           = $repReport
$Apply            = $repApply
$SkipValidation   = $repSkipVal

# ═══════════════════════════════════════════════════════════════
# Hàm thuần của tầng 3 (diff + định dạng)
# ═══════════════════════════════════════════════════════════════

function Compare-RecommendationToConfig {
    <#
    .SYNOPSIS
        So đề xuất với ⭐ hiện tại trong config → các dòng có thay đổi.
        Action: 'THÊM ⭐' | 'GỠ ⭐' | 'giữ'. THUẦN.
    #>
    param($ConfigModels, $RecommendationMap)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($cm in @($ConfigModels)) {
        $has = Test-ModelHasStar $cm.Name
        $key = Get-RecommendationKey -Provider $cm.Provider -ModelId $cm.Id
        $proposed = $RecommendationMap.ContainsKey($key)
        if (-not $has -and -not $proposed) { continue }
        $action = if ($has -and $proposed) { 'giữ' } elseif ($proposed) { 'THÊM ⭐' } else { 'GỠ ⭐' }
        $rows.Add([pscustomobject]@{
            Key      = $key
            Id       = $cm.Id
            Provider = $cm.Provider
            Action   = $action
        })
    }
    return @($rows)
}

function Format-RecommendPrice {
    <# Giá input hiển thị: 'free' cho nhóm free / thiếu giá, còn lại '$<price>'. THUẦN. #>
    param($Candidate)
    if ($Candidate.Group -eq 'free' -or $null -eq $Candidate.In) { return 'free' }
    return ('$' + (Format-Price $Candidate.In))
}

function New-RecommendReportLines {
    <#
    .SYNOPSIS
        Sinh nội dung Markdown báo cáo đề xuất ⭐. THUẦN (không I/O).
        Dùng chung cho cả Pha 1 (-Report) lẫn Pha 2 (-Apply -Report).
    #>
    param($ConfigPath, $Capabilities, $Rows, $Adds, $Drops, $Date = $null)
    if ($null -eq $Date) { $Date = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# ModelCompass — Đề xuất ⭐ xKiro')
    $lines.Add('')
    $lines.Add("Ngày: $Date")
    $lines.Add('')
    $lines.Add("Config: ``$ConfigPath``")
    $lines.Add('')
    if (@($Capabilities.Unsupported).Count -gt 0) {
        $lines.Add("> xKiro KHÔNG có mục đích: $(@($Capabilities.Unsupported) -join ', ')")
        $lines.Add('')
    }
    $lines.Add('## ⭐ Theo nhóm')
    $lines.Add('')
    $lines.Add('| Nhóm | Model | Giá in | Nguồn |')
    $lines.Add('|---|---|---|---|')
    foreach ($r in @($Rows | Where-Object { $_.Kind -eq 'group' })) {
        $lines.Add("| $($r.Key) | ``$($r.Candidate.Id)`` | $(Format-RecommendPrice $r.Candidate) | $($r.Source) |")
    }
    $lines.Add('')
    $lines.Add('## ⭐ Theo mục đích')
    $lines.Add('')
    $lines.Add('| Mục đích | Scope | Model | Giá in | Nguồn |')
    $lines.Add('|---|---|---|---|---|')
    foreach ($r in @($Rows | Where-Object { $_.Kind -eq 'purpose' })) {
        $lines.Add("| $($r.Key) | $($r.Scope) | ``$($r.Candidate.Id)`` | $(Format-RecommendPrice $r.Candidate) | $($r.Source) |")
    }
    $lines.Add('')
    $lines.Add('## Thay đổi so với ⭐ hiện tại')
    $lines.Add('')
    if (@($Adds).Count -gt 0) { $lines.Add('**THÊM ⭐:** ' + ((@($Adds) | ForEach-Object { "``$($_.Id)``" }) -join ', ')); $lines.Add('') }
    if (@($Drops).Count -gt 0) { $lines.Add('**GỠ ⭐:** ' + ((@($Drops) | ForEach-Object { "``$($_.Id)``" }) -join ', ')); $lines.Add('') }
    if (@($Adds).Count -eq 0 -and @($Drops).Count -eq 0) { $lines.Add('_Không thay đổi — đề xuất trùng ⭐ hiện tại._'); $lines.Add('') }
    return @($lines)
}

function Save-RecommendReportFile {
    <# Ghi mảng dòng Markdown vào reports/recommend-<timestamp>.md; trả đường dẫn file. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Lines)
    $reportDir = Join-Path $RepoRoot 'reports'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $file = Join-Path $reportDir ("recommend-" + (Get-Timestamp) + ".md")
    @($Lines) | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Update-StarInConfigRaw {
    <#
    .SYNOPSIS
        Sinh TEXT config mới: gắn/gỡ ⭐ đầu `name` của từng model theo Targets. THUẦN (không I/O).
        Chỉ sửa dòng `"<id>": { "name": "...", ... }` trong ĐÚNG provider — giữ nguyên comment,
        indent, thứ tự, các khoá khác (release_date...), tránh 2 model trùng id ở 2 provider.
        Targets: mảng @{ Provider; ModelId; Star [bool] }.
    #>
    param([string]$Raw, $Targets)
    $newline = if ($Raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Raw -split "`r?`n")) { $lines.Add($l) }

    $want = @{}
    foreach ($t in @($Targets)) { $want[(Get-RecommendationKey -Provider $t.Provider -ModelId $t.ModelId)] = [bool]$t.Star }

    foreach ($pk in @(@($Targets) | ForEach-Object { $_.Provider } | Select-Object -Unique)) {
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^\s*"' + [regex]::Escape($pk) + '"\s*:\s*\{')) { $start = $i; break }
        }
        if ($start -lt 0) { continue }

        $depth = 0; $end = $lines.Count - 1
        for ($i = $start; $i -lt $lines.Count; $i++) {
            $depth += ([regex]::Matches($lines[$i], '\{')).Count
            $depth -= ([regex]::Matches($lines[$i], '\}')).Count
            if ($i -gt $start -and $depth -le 0) { $end = $i; break }
        }

        for ($i = $start + 1; $i -lt $end; $i++) {
            $m = [regex]::Match($lines[$i], '^\s*"([^"]+)"\s*:\s*\{.*"name"\s*:\s*"')
            if (-not $m.Success) { continue }
            $id = $m.Groups[1].Value
            $key = Get-RecommendationKey -Provider $pk -ModelId $id
            if (-not $want.ContainsKey($key)) { continue }

            $nm = [regex]::Match($lines[$i], '"name"\s*:\s*"((?:[^"\\]|\\.)*)"')
            if (-not $nm.Success) { continue }
            $cur = $nm.Groups[1].Value
            $new = if ($want[$key]) { Set-StarInName $cur } else { Remove-StarInName $cur }
            if ($new -eq $cur) { continue }
            $escaped = $new -replace '\\', '\\' -replace '"', '\"'
            # Dùng MatchEvaluator để trả về literal — tránh .NET hiểu `$0`/`$3` trong
            # replacement thành group ref (làm hỏng name chứa giá `$X/$Y`).
            $literal = '"name": "' + $escaped + '"'
            $rx = [regex]::new('"name"\s*:\s*"(?:[^"\\]|\\.)*"')
            $evaluator = { param($mm) $literal }.GetNewClosure()
            $lines[$i] = $rx.Replace($lines[$i], $evaluator, 1)
        }
    }
    return ($lines -join $newline)
}

if ($SkipRun) { return }

# ═══════════════════════════════════════════════════════════════
# Chạy chính (Pha 1: chỉ báo cáo · Pha 2: -Apply ghi)
# ═══════════════════════════════════════════════════════════════

$repo = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath))   { $ConfigPath = Join-Path $repo 'configs\development\opencode.jsonc' }
if ([string]::IsNullOrWhiteSpace($CatalogPath))  { $CatalogPath = Join-Path $repo 'docs\catalogs\xkiro.json' }
if ([string]::IsNullOrWhiteSpace($CapabilitiesPath)) { $CapabilitiesPath = Join-Path $PSScriptRoot 'model-capabilities.json' }

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy config: $ConfigPath"; exit 2
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy catalog: $CatalogPath"; exit 2
}

$selected = @('1-xkiro-free', '2-xkiro-max')
if ($Provider -and @($Provider).Count -gt 0) {
    $selected = @($Provider | Where-Object { $_ -in @('1-xkiro-free', '2-xkiro-max') })
    if ($selected.Count -eq 0) { Write-Fail 'Provider không hợp lệ (chỉ hỗ trợ 1-xkiro-free, 2-xkiro-max).'; exit 2 }
}

$mode = if ($Apply) { 'Pha 2 — GHI config' } else { 'Pha 1 — chỉ báo cáo' }
Write-Step "ĐỀ XUẤT ⭐ xKiro ($mode)"

$capabilities = Read-ModelCapabilities -Path $CapabilitiesPath
$configRaw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8
$configObj = Get-ConfigContent $ConfigPath
$catalogModels = @((Get-Content -LiteralPath $CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json).models)

# Tầng 1: ứng viên → Tầng 2: áp rule → dòng đề xuất.
$bundle = Get-ModelCandidates -ConfigObj $configObj -CatalogModels $catalogModels -ProviderKeys $selected
$catalogById = $bundle.CatalogById
$configModels = $bundle.ConfigModels
$candidates = $bundle.Candidates

$resolved = Resolve-StarRules -Candidates $candidates -Capabilities $capabilities
$rows = $resolved.Rows
$map = $resolved.Map
$diffs = Compare-RecommendationToConfig -ConfigModels $configModels -RecommendationMap $map

Write-Info "Config: $ConfigPath"
Write-Info "Catalog: $CatalogPath ($($catalogModels.Count) model · khớp $(@($candidates | Where-Object { $catalogById.ContainsKey($_.Id) }).Count)/$($candidates.Count) ứng viên)"
Write-Info "Bảng tra: $CapabilitiesPath"
if (@($capabilities.Unsupported).Count -gt 0) {
    Write-Info ("xKiro KHÔNG có mục đích: {0}" -f (@($capabilities.Unsupported) -join ', '))
}

# ── Bảng 1: Theo nhóm ──
Write-Host ''
Write-Host '  ⭐ THEO NHÓM' -ForegroundColor DarkCyan
Write-Host ('  {0,-6} {1,-42} {2,-10} {3,-6} {4}' -f 'Nhóm', 'Model', 'Giá in', 'Ctx', 'Nguồn')
foreach ($r in @($rows | Where-Object { $_.Kind -eq 'group' })) {
    $c = $r.Candidate
    $ctx = if ($c.Context -ge 1000000) { '{0:0.#}M' -f ($c.Context / 1e6) } elseif ($c.Context -gt 0) { '{0:0.#}K' -f ($c.Context / 1e3) } else { '—' }
    Write-Host ('  {0,-6} {1,-42} {2,-10} {3,-6} {4}' -f $r.Key, $c.Id, (Format-RecommendPrice $c), $ctx, $r.Source)
}

# ── Bảng 2: Theo mục đích ──
Write-Host ''
Write-Host '  ⭐ THEO MỤC ĐÍCH' -ForegroundColor DarkCyan
Write-Host ('  {0,-18} {1,-5} {2,-42} {3,-10} {4}' -f 'Mục đích', 'Scope', 'Model', 'Giá in', 'Nguồn')
foreach ($r in @($rows | Where-Object { $_.Kind -eq 'purpose' })) {
    $c = $r.Candidate
    Write-Host ('  {0,-18} {1,-5} {2,-42} {3,-10} {4}' -f $r.Key, $r.Scope, $c.Id, (Format-RecommendPrice $c), $r.Source)
}

# ── Bảng 3: Khác biệt so với ⭐ hiện tại ──
Write-Host ''
Write-Step 'THAY ĐỔI SO VỚI ⭐ HIỆN TẠI'
$adds = @($diffs | Where-Object { $_.Action -eq 'THÊM ⭐' })
$drops = @($diffs | Where-Object { $_.Action -eq 'GỠ ⭐' })
$keep = @($diffs | Where-Object { $_.Action -eq 'giữ' })

if ($adds.Count -gt 0) {
    Write-Ok "THÊM ⭐ ($($adds.Count)):"
    foreach ($d in $adds) {
        $tasks = @($map[$d.Key].Purposes); $groups = @($map[$d.Key].Groups)
        $note = @()
        if ($groups.Count -gt 0) { $note += "nhóm: $($groups -join ',')" }
        if ($tasks.Count -gt 0) { $note += "mục đích: $($tasks -join ',')" }
        Write-Host "    + $($d.Id)  ($($note -join ' · '))" -ForegroundColor Green
    }
} else { Write-Info 'Không có model nào cần THÊM ⭐.' }

if ($drops.Count -gt 0) {
    Write-Warn "GỠ ⭐ ($($drops.Count)):"
    foreach ($d in $drops) { Write-Host "    - $($d.Id)" -ForegroundColor Yellow }
} else { Write-Info 'Không có model nào cần GỠ ⭐.' }

Write-Host ''
Write-Info "Giữ ⭐: $($keep.Count) model (đề xuất trùng với hiện tại)."
Write-Host ''

$reportLines = if ($Report) { New-RecommendReportLines -ConfigPath $ConfigPath -Capabilities $capabilities -Rows $rows -Adds $adds -Drops $drops } else { @() }

# ── Pha 2: GHI ⭐ vào config (chỉ khi -Apply) ──
if ($Apply) {
    $targets = @()
    foreach ($d in $adds)  { $targets += [pscustomobject]@{ Provider = $d.Provider; ModelId = $d.Id; Star = $true } }
    foreach ($d in $drops) { $targets += [pscustomobject]@{ Provider = $d.Provider; ModelId = $d.Id; Star = $false } }
    if ($targets.Count -eq 0) {
        Write-Ok 'Không có thay đổi ⭐ — config đã khớp đề xuất, không ghi.'
        if ($Report) { Write-Info "Report: $(Save-RecommendReportFile -RepoRoot $repo -Lines $reportLines)" }
        exit 0
    }

    $newRaw = Update-StarInConfigRaw -Raw $configRaw -Targets $targets
    if ($newRaw -ceq $configRaw) {
        Write-Fail 'Không sinh được thay đổi text (id không khớp dòng?) — không ghi.'
        exit 1
    }

    $backupDir = Join-Path $repo 'configs\development\.backup'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup = Join-Path $backupDir ("opencode." + (Get-Timestamp) + ".jsonc")
    Copy-Item -LiteralPath $ConfigPath -Destination $backup
    Write-Info "Backup: $backup"

    Set-Content -LiteralPath $ConfigPath -Value $newRaw -Encoding utf8NoBOM
    Write-Ok "Đã ghi ⭐ vào config: +$($adds.Count) · -$($drops.Count) · giữ $($keep.Count)."

    if (-not $SkipValidation) {
        Write-Info 'Validate config...'
        & (Get-ScriptPath 'Test-ModelCompassConfig.ps1') -Path $ConfigPath | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "VALIDATE THẤT BẠI — khôi phục thủ công từ: $backup"
            exit 1
        }
        Write-Ok 'Validate OK.'
    } else {
        Write-Warn '(-SkipValidation) bỏ qua validate.'
    }

    if ($Report) { Write-Info "Report: $(Save-RecommendReportFile -RepoRoot $repo -Lines $reportLines)" }

    Write-Step 'BƯỚC TIẾP'
    Write-Host '  • Publish: pwsh scripts/config/Publish-Config.ps1 -Yes'
    Write-Host '  • Install: pwsh scripts/config/Install-Config.ps1 -Force'
    Write-Host '  • Restart opencode để nạp config mới.'
    exit 0
}

Write-Host '  (Pha 1 chỉ báo cáo — chưa ghi config. Thêm -Apply để ghi ⭐ vào name.)' -ForegroundColor DarkGray

if ($Report) {
    Write-Info "Report: $(Save-RecommendReportFile -RepoRoot $repo -Lines $reportLines)"
}

exit 0
