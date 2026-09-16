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

function Get-Timestamp {
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
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