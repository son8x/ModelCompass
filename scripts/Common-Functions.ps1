#Requires -Version 7
Set-StrictMode -Version Latest

<#
Common-Functions.ps1 — thư viện dùng chung cho các script ModelCompass.
Mỗi script khác load bằng:  . (Join-Path $PSScriptRoot 'Common-Functions.ps1')
#>

function Get-ConfigContent {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Không tìm thấy file cấu hình: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $json = Remove-CommentsAndTrailingCommas $raw
    try {
        return $json | ConvertFrom-Json
    } catch {
        throw "Lỗi parse JSON trong '$Path': $($_.Exception.Message)"
    }
}

function Remove-CommentsAndTrailingCommas {
    <#
    Loại bỏ comment (// và /* */) và dấu phẩy thừa của JSONC,
    trả về chuỗi JSON hợp lệ. Tôn trọng chuỗi "" (comment trong string không bị xoá).
    #>
    param([string]$Content)
    if ($null -eq $Content) { return $Content }

    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $i = 0
    $n = $Content.Length
    while ($i -lt $n) {
        $c = $Content[$i]
        $next = if (($i + 1) -lt $n) { $Content[$i + 1] } else { $null }

        if ($inString) {
            if ($c -eq '\' -and $null -ne $next) {
                [void]$sb.Append($c).Append($next); $i += 2; continue
            }
            if ($c -eq '"') { $inString = $false }
            [void]$sb.Append($c); $i++; continue
        }

        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }

        if ($c -eq '/' -and $next -eq '/') {
            while ($i -lt $n -and $Content[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '/' -and $next -eq '*') {
            $i += 2
            while (($i + 1) -lt $n -and -not ($Content[$i] -eq '*' -and $Content[$i + 1] -eq '/')) { $i++ }
            $i += 2
            continue
        }

        [void]$sb.Append($c); $i++
    }

    $out = $sb.ToString()
    $out = [regex]::Replace($out, ',\s*([}\]])', '$1')
    return $out
}

function ConvertTo-OpenCodeJson {
    <#
    Chuẩn hoá config đã parse về JSON thuần (2-space indent) — dùng cho production.
    #>
    param([Parameter(Mandatory)]$Object)
    return ($Object | ConvertTo-Json -Depth 100)
}

function Resolve-EnvValue {
    <#
    Giải chuỗi dạng {env:VAR} về giá trị biến môi trường.
    Nếu không phải dạng {env:...} thì trả về nguyên bản.
    Trả $null khi biến chưa được đặt.
    #>
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -match '^\{env:(.+)\}$') {
        $name = $Matches[1].Trim()
        $val = [Environment]::GetEnvironmentVariable($name)
        if ($null -eq $val -or '' -eq $val) { return $null }
        return $val
    }
    return $Value
}

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-InstallStatePath {
    <#
    Đường dẫn file trạng thái cài đặt (sentry) của target config global.
    Vị trí: <target>.state.json — đặt cạnh config đang dùng, không commit.
    #>
    param([Parameter(Mandatory)][string]$Target)
    return "$Target.state.json"
}

function Get-FileHashSha256 {
    <#
    Hash SHA256 của file; trả $null nếu file không tồn tại.
    #>
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Save-ConfigState {
    <#
    Ghi file trạng thái cài đặt (được gọi bởi Install-Config.ps1 / Restore-RunningConfig.ps1).
    Dữ liệu lưu: thời điểm, nguồn, đích, hash nguồn/đích, backup, ghi chú.
    #>
    param(
        [Parameter(Mandatory)][string]$Target,
        [string]$Source,
        [string]$SourceHash,
        [string]$Backup,
        [string]$Note = ''
    )
    $statePath = Get-InstallStatePath $Target
    $obj = [ordered]@{
        installedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        source      = if ($Source) { $Source } else { '' }
        sourceHash  = if ($SourceHash) { $SourceHash } else { '' }
        target      = $Target
        targetHash  = (Get-FileHashSha256 $Target)
        backup      = if ($Backup) { $Backup } else { '' }
        note        = $Note
    }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8
    return $statePath
}

function Read-ConfigState {
    <#
    Đọc file trạng thái cài đặt; trả $null nếu chưa từng install hoặc hỏng cú pháp.
    #>
    param([string]$Target)
    $statePath = Get-InstallStatePath $Target
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-Timestamp {
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function ConvertTo-SpendCost {
    <#
    Tính chi phí USD từ token × giá (giá/1M token). Trả cost in/out làm tròn 6 chữ số.
    -PriceIn/-PriceOut có thể bỏ (mô hình free → 0).
    #>
    param(
        [long]$PromptTokens = 0,
        [long]$CompletionTokens = 0,
        [double]$PriceIn = 0,
        [double]$PriceOut = 0
    )
    return [pscustomobject]@{
        CostIn  = [math]::Round([double]$PromptTokens / 1e6 * $PriceIn, 6)
        CostOut = [math]::Round([double]$CompletionTokens / 1e6 * $PriceOut, 6)
    }
}

function Get-SpendLogPath {
    <#
    Đường dẫn spend log. Mặc định: reports/spend.jsonl (append-only, 1 JSON/dòng).
    #>
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return Join-Path (Get-RepoRoot) 'reports\spend.jsonl'
}

function Add-SpendEntry {
    <#
    Ghi 1 bản ghi chi phí (append) vào spend log JSONL. Tự tạo thư mục reports/ nếu chưa có.
    Dữ liệu: hai stamp, provider, model, token in/out, cost in/out (USD), total.
    Trả về đường dẫn file vừa ghi.
    #>
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Model,
        [long]$PromptTokens = 0,
        [long]$CompletionTokens = 0,
        [double]$CostInUsd = 0,
        [double]$CostOutUsd = 0,
        [string]$Note = '',
        [string]$Path
    )
    $file = Get-SpendLogPath $Path
    $dir = Split-Path -Parent $file
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $entry = [ordered]@{
        ts                = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        provider          = $Provider
        model             = $Model
        prompt_tokens     = $PromptTokens
        completion_tokens = $CompletionTokens
        cost_in_usd       = [math]::Round($CostInUsd, 6)
        cost_out_usd      = [math]::Round($CostOutUsd, 6)
        total_usd         = [math]::Round($CostInUsd + $CostOutUsd, 6)
        note              = $Note
    }
    Add-Content -LiteralPath $file -Value ($entry | ConvertTo-Json -Compress -Depth 3) -Encoding utf8
    return $file
}

function Get-SpendEntries {
    <#
    Đọc toàn bộ spend log (JSONL) thành mảng object; lướt qua dòng hỏng.
    Trả array rỗng nếu file chưa tồn tại.
    #>
    param([string]$Path)
    $file = Get-SpendLogPath $Path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @() }
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $file) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $parsed = $line | ConvertFrom-Json
            if (($parsed.PSObject.Properties.Name -contains 'ts') -and ($parsed.ts -is [datetime])) {
                $parsed.ts = $parsed.ts.ToString('yyyy-MM-ddTHH:mm:ss')
            }
            $out.Add($parsed)
        } catch {
            continue
        }
    }
    return @($out)
}

function Write-Step {
    param([string]$Msg)
    Write-Host ''
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host "  $Msg" -ForegroundColor DarkCyan
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
}
function Write-Info  { param([string]$Msg) Write-Host "  info : $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  OK   : $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  warn : $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "  FAIL : $Msg" -ForegroundColor Red }