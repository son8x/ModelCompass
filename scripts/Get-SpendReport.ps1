#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Tổng hợp chi phí từ spend log (reports/spend.jsonl) theo ngày/provider/model.

.DESCRIPTION
    Đọc spend log JSONL (mỗi dòng 1 bản ghi do Add-SpendEntry.ps1 / Add-SpendEntry
    ghi) rồi in:
        - Tổng: số phiên, token in/out, chi phí in/out, tổng chi phí USD
        - Theo ngày, theo provider, top model theo chi phí
    Hỗ trợ lọc: -Month (yyyy-MM), -Day (yyyy-MM-dd), -Provider, -Model (chuỗi con).

.PARAMETER Path
    File spend log (mặc định: reports/spend.jsonl).

.PARAMETER Month
    Lọc theo tháng 'yyyy-MM' (vd '2026-09').

.PARAMETER Day
    Lọc theo ngày 'yyyy-MM-dd' (vd '2026-09-17').

.PARAMETER Provider
    Lọc provider (chứa, không phân biệt hoa thường).

.PARAMETER Model
    Lọc model id (chứa, không phân biệt hoa thường).

.PARAMETER Top
    Số model hiển thị trong bảng per-model (mặc định 10).

.PARAMETER Json
    Chỉ xuất JSON tổng hợp ra stdout (pipe/script khác).

.PARAMETER Report
    Ghi báo cáo Markdown vào reports/spend-report-<timestamp>.md.

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function (dùng cho test dot-source), không chạy.

.EXAMPLE
    pwsh scripts\Get-SpendReport.ps1                     # tổng hợp toàn bộ log
    pwsh scripts\Get-SpendReport.ps1 -Month 2026-09 -Provider xkiro
    pwsh scripts\Get-SpendReport.ps1 -Json | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$Month,
    [string]$Day,
    [string]$Provider,
    [string]$Model,
    [int]$Top = 10,
    [switch]$Json,
    [switch]$Report,
    [switch]$SkipRun
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$skipRunFlag = [bool]$SkipRun

# ═══════════════════════════════════════════════════════════════
# Các hàm thuần (test bằng dot-source -SkipRun)
# ═══════════════════════════════════════════════════════════════

function Get-SpendGroupKey {
    <# Khoá nhóm: 'day' -> yyyy-MM-dd, 'month' -> yyyy-MM, 'provider'/'model' -> chuỗi. #>
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][string]$Key)
    switch ($Key) {
        'day' {
            $t = [string]$Entry.ts
            if ($t.Length -ge 10) { return $t.Substring(0, 10) }
            return '(không rõ)'
        }
        'month' {
            $t = [string]$Entry.ts
            if ($t.Length -ge 7) { return $t.Substring(0, 7) }
            return '(không rõ)'
        }
        'provider' { return [string]$Entry.provider }
        'model'    { return [string]$Entry.model }
        default    { return '(khác)' }
    }
}

function Get-SpendGroups {
    <#
    Gom entries theo Key ('day'|'month'|'provider'|'model'), cộng token + chi phí.
    Trả về array giảm dần theo Total USD: { Key, Entries, Prompt, Completion, CostIn, CostOut, Total }.
    #>
    param([Parameter(Mandatory)]$Entries, [Parameter(Mandatory)][string]$Key)
    $map = @{}
    foreach ($e in @($Entries)) {
        $k = Get-SpendGroupKey -Entry $e -Key $Key
        if (-not $map.ContainsKey($k)) {
            $map[$k] = [pscustomobject]@{
                Key        = $k
                Entries    = 0
                Prompt     = [long]0
                Completion = [long]0
                CostIn     = 0.0
                CostOut    = 0.0
                Total      = 0.0
            }
        }
        $g = $map[$k]
        $g.Entries++
        $g.Prompt     += [long]$e.prompt_tokens
        $g.Completion += [long]$e.completion_tokens
        $g.CostIn     += [double]$e.cost_in_usd
        $g.CostOut    += [double]$e.cost_out_usd
        $g.Total       = [math]::Round($g.CostIn + $g.CostOut, 6)
    }
    return @($map.Values | Sort-Object -Property @{ Expression = 'Total'; Descending = $true }, Key)
}

function Get-SpendSummary {
    <#
    Tổng hợp toàn bộ entries (dùng để in header / JSON).
    #>
    param([Parameter(Mandatory)]$Entries)
    $prompt = [long]0; $comp = [long]0; $in = 0.0; $out = 0.0
    foreach ($e in @($Entries)) {
        $prompt += [long]$e.prompt_tokens
        $comp   += [long]$e.completion_tokens
        $in     += [double]$e.cost_in_usd
        $out    += [double]$e.cost_out_usd
    }
    return [pscustomobject]@{
        Entries    = @($Entries).Count
        Prompt     = $prompt
        Completion = $comp
        CostIn     = [math]::Round($in, 6)
        CostOut    = [math]::Round($out, 6)
        Total      = [math]::Round($in + $out, 6)
    }
}

function Test-SpendEntryMatch {
    <#
    Lọc entry theo Month/Day/Provider/Model (chuỗi con, không phân biệt hoa thường).
    #>
    param(
        [Parameter(Mandatory)]$Entry,
        [string]$Month,
        [string]$Day,
        [string]$Provider,
        [string]$Model
    )
    $ts = [string]$Entry.ts
    if (-not [string]::IsNullOrWhiteSpace($Month) -and $ts.Length -lt 7) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Month) -and $ts.Substring(0, 7) -ne $Month)          { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Day)   -and $ts.Length -lt 10) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Day)   -and $ts.Substring(0, 10) -ne $Day)           { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Provider) -and ([string]$Entry.provider).IndexOf($Provider, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Model)    -and ([string]$Entry.model).IndexOf($Model,    [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    return $true
}

function Format-Count {
    param([long]$Value)
    if ($Value -ge 1e9) { return ('{0:N2}B' -f ($Value / 1e9)) }
    if ($Value -ge 1e6) { return ('{0:N2}M' -f ($Value / 1e6)) }
    if ($Value -ge 1e3) { return ('{0:N1}K' -f ($Value / 1e3)) }
    return ('{0:F0}' -f $Value)
}

function Format-Usd {
    param([double]$Value)
    return ('${0:N2}' -f [double]$Value)
}

if ($skipRunFlag) { return }

# ═══════════════════════════════════════════════════════════════
# Chạy chính
# ═══════════════════════════════════════════════════════════════

$logFile = Get-SpendLogPath $Path
if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
    Write-Fail "Không tìm thấy spend log: $logFile (chạy Add-SpendEntry.ps1 trước đã ghi dữ liệu)."
    exit 2
}

$all = Get-SpendEntries $Path
$entry = @($all | Where-Object { Test-SpendEntryMatch -Entry $_ -Month $Month -Day $Day -Provider $Provider -Model $Model })

$summary = Get-SpendSummary $entry
$byDay  = Get-SpendGroups -Entries $entry -Key 'day'
$byProv = Get-SpendGroups -Entries $entry -Key 'provider'
$byModel = Get-SpendGroups -Entries $entry -Key 'model'

if (-not $Json) {
    Write-Step "SPEND REPORT  ($logFile)"
    $head = "Phiên: $($summary.Entries) | token in $(Format-Count $summary.Prompt) / out $(Format-Count $summary.Completion)"
    Write-Info $head
    Write-Info "Chi phí: in $(Format-Usd $summary.CostIn) + out $(Format-Usd $summary.CostOut) = $(Format-Usd $summary.Total)"

    if ($summary.Entries -eq 0) {
        Write-Ok 'Không có bản ghi thoả điều kiện lọc.'
    }

    Write-Step "Theo ngày"
    foreach ($g in $byDay) {
        Write-Host ("  {0}  | {1,6} phiên | {2,10} tok | In {3} + Out {4} = {5}" -f
            $g.Key, $g.Entries, (Format-Count $g.Prompt), (Format-Usd $g.CostIn), (Format-Usd $g.CostOut), (Format-Usd $g.Total))
    }

    Write-Step "Theo provider"
    foreach ($g in $byProv) {
        Write-Host ("  {0,-12} | {1,6} phiên | {2,10} tok | {3}" -f
            $g.Key, $g.Entries, (Format-Count $g.Prompt), (Format-Usd $g.Total))
    }

    Write-Step "Top $Top model theo chi phí"
    foreach ($g in @($byModel | Select-Object -First $Top)) {
        Write-Host ("  {0,-44} | {1,6} phiên | {2,10} tok | {3}" -f
            $g.Key, $g.Entries, (Format-Count $g.Prompt), (Format-Usd $g.Total))
    }
}

if ($Json) {
    $payload = [ordered]@{
        file    = $logFile
        filters = [ordered]@{
            month    = $Month
            day      = $Day
            provider = $Provider
            model    = $Model
        }
        summary = $summary
        by_day   = [array]$byDay
        by_provider = [array]$byProv
        by_model = [array]$byModel
    }
    Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
}

if ($Report) {
    $reportDir = Join-Path (Get-RepoRoot) 'reports'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $file = Join-Path $reportDir ("spend-report-" + (Get-Timestamp) + ".md")
    $lines = @(
        "# ModelCompass — Báo cáo chi phí", ''
        "Ngày: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  nguồn: $logFile", ''
        "Tổng: **$(Format-Usd $summary.Total)**  (in $(Format-Usd $summary.CostIn) + out $(Format-Usd $summary.CostOut))  —  $($summary.Entries) phiên, $(Format-Count $summary.Prompt) token in / $(Format-Count $summary.Completion) out", ''
        '## Theo ngày', '', '| Ngày | Phiên | Token | In | Out | Tổng |', '|---|---|---|---|---|---|'
    )
    foreach ($g in $byDay) {
        $lines += "| $($g.Key) | $($g.Entries) | $(Format-Count $g.Prompt) | $(Format-Usd $g.CostIn) | $(Format-Usd $g.CostOut) | $(Format-Usd $g.Total) |"
    }
    $lines += '', '## Theo provider', '', '| Provider | Phiên | Token | Tổng |', '|---|---|---|---|'
    foreach ($g in $byProv) {
        $lines += "| $($g.Key) | $($g.Entries) | $(Format-Count $g.Prompt) | $(Format-Usd $g.Total) |"
    }
    $lines += '', "## Top $Top model", '', '| Model | Phiên | Token | Tổng |', '|---|---|---|---|'
    foreach ($g in @($byModel | Select-Object -First $Top)) {
        $lines += "| $($g.Key) | $($g.Entries) | $(Format-Count $g.Prompt) | $(Format-Usd $g.Total) |"
    }
    $lines | Set-Content -LiteralPath $file -Encoding utf8
    Write-Info "Report: $file"
}

exit 0