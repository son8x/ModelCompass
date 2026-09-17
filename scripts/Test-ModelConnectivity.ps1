#Requires -Version 7
#Requires -Modules Microsoft.PowerShell.Utility
<#
.SYNOPSIS
    ModelCompass: Test kết nối thực tế tới từng provider/model trong cấu hình.

.DESCRIPTION
    Với mỗi provider có khai báo "options.baseURL", script gửi 1 request
    "chat/completions" (prompt chỉ 1 token) để xác nhận model có thể gọi được.
    Kết quả phân loại:
        OK        — HTTP 200/201, model phản hồi được
        AUTH      — HTTP 401/403 (key không hợp lệ)
        RATE      — HTTP 429 (rate limit)
        NOTFOUND  — HTTP 404 (model ID sai trên endpoint)
        HTTP      — HTTP khác
        TIMEOUT   — quá TimeoutSeconds
        DOWN      — không kết nối được (refused/connection)
        ERROR     — lỗi khác
        SKIP      — chưa có API key (Resolve-EnvValue trả null) hay thiếu cấu hình

.PARAMETER ConfigPath
    File cấu hình cần test. Mặc định: configs\development\opencode.jsonc

.PARAMETER Provider
    Chỉ test các provider này (tên khớp). Mặc định: tất cả.

.PARAMETER Model
    Chỉ test model ID này. Mặc định: tất cả.

.PARAMETER TimeoutSeconds
    Thời gian chờ tối đa mỗi request (giây). Mặc định: 20.

.PARAMETER Report
    Xuất report dạng Markdown vào reports\.

.EXAMPLE
    PS scripts\Test-ModelConnectivity.ps1
    PS scripts\Test-ModelConnectivity.ps1 -Provider '6-teamoRouter' -Report
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$Provider,
    [string]$Model,
    [int]$TimeoutSeconds = 20,
    [switch]$Report
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Get-RepoRoot) 'configs\development\opencode.jsonc'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy file: $ConfigPath"
    exit 1
}

Write-Step "Test kết nối: $ConfigPath (timeout ${TimeoutSeconds}s)"
$config = Get-ConfigContent $ConfigPath

$results = [System.Collections.Generic.List[object]]::new()

function Invoke-Probe {
    param([string]$Url, [string]$ModelId, [string]$ApiKey, [int]$TimeoutSeconds)
    $headers = @{ Authorization = "Bearer $ApiKey" }
    $body = @{
        model      = $ModelId
        messages   = @(@{ role = 'user'; content = 'ping' })
        max_tokens = 1
    } | ConvertTo-Json -Depth 5

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Post -Headers $headers `
            -ContentType 'application/json' -Body $body `
            -TimeoutSec $TimeoutSeconds -SkipHttpErrorCheck
        $sw.Stop()
        $code = [int]$resp.StatusCode
        switch ($code) {
            200 { return [pscustomobject]@{ status = 'OK'; msg = 'phản hồi OK'; code = $code } }
            201 { return [pscustomobject]@{ status = 'OK'; msg = 'phản hồi OK'; code = $code } }
            { $_ -in 401, 403 } { return [pscustomobject]@{ status = 'AUTH'; msg = 'HTTP 401/403 - key không hợp lệ hoặc thiếu quyền'; code = $code } }
            429 { return [pscustomobject]@{ status = 'RATE'; msg = 'HTTP 429 - rate limit / hết quota'; code = $code } }
            404 { return [pscustomobject]@{ status = 'NOTFOUND'; msg = 'HTTP 404 - model không tồn tại trên endpoint này'; code = $code } }
            400 { return [pscustomobject]@{ status = 'BADREQ'; msg = 'HTTP 400 - sai payload (model tồn tại?)'; code = $code } }
            default { return [pscustomobject]@{ status = 'HTTP'; msg = "HTTP $code"; code = $code } }
        }
    } catch {
        $sw.Stop()
        $msg = $_.Exception.Message
        $inner = $_.Exception.InnerException
        if ($null -ne $inner -and $inner.Message) { $msg = $inner.Message }
        if ($msg -match 'timed out|timeout|operation has timed out|operation was canceled|canceled') {
            return [pscustomobject]@{ status = 'TIMEOUT'; msg = "quá ${TimeoutSeconds}s (không phản hồi)"; code = 0 }
        }
        if ($msg -match 'refused|unreachable|failed to connect|No connection|could not be resolved|actively refused') {
            return [pscustomobject]@{ status = 'DOWN'; msg = 'không kết nối được (host refused / down)'; code = 0 }
        }
        return [pscustomobject]@{ status = 'ERROR'; msg = $msg; code = 0 }
    }
}

if ($null -eq $config.provider) {
    Write-Fail 'Cấu hình không có mục "provider".'
    exit 1
}

foreach ($p in @($config.provider.PSObject.Properties)) {
    if ($Provider -and $Provider -notcontains $p.Name) { continue }

    $def = $p.Value
    $baseUrl = $null
    if ($null -ne $def.options) { $baseUrl = $def.options.baseURL }
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        Write-Warn "provider [$($p.Name)]: thiếu baseURL — bỏ qua."
        continue
    }
    $key = Resolve-EnvValue ([string]$def.options.apiKey)
    $url = $baseUrl.TrimEnd('/') + '/chat/completions'

    foreach ($m in @($def.models.PSObject.Properties)) {
        $modelId = $m.Name
        if ($Model -and $Model -ne $modelId) { continue }

        if ([string]::IsNullOrWhiteSpace($key)) {
            $results.Add([pscustomobject]@{
                Provider = $p.Name; Model = $modelId; Status = 'SKIP'; Message = 'thiếu API key ({env:...})'; ms = 0
            })
            continue
        }
        $r = Invoke-Probe -Url $url -ModelId $modelId -ApiKey $key -TimeoutSeconds $TimeoutSeconds
        $results.Add([pscustomobject]@{
            Provider = $p.Name; Model = $modelId; Status = $r.status; Message = $r.msg; ms = $null
        })
    }
}

Write-Step "Kết quả"
if ($results.Count -eq 0) {
    Write-Warn 'Không có provider/model nào để test.'
    exit 0
}

$colorMap = @{
    OK = 'Green'; AUTH = 'Yellow'; RATE = 'Yellow'; BADREQ = 'Yellow'
    NOTFOUND = 'Red'; TIMEOUT = 'Red'; DOWN = 'Red'; ERROR = 'Red'; SKIP = 'DarkGray'; HTTP = 'Yellow'
}
foreach ($r in $results) {
    $color = $colorMap[$r.Status]
    if (-not $color) { $color = 'White' }
    Write-Host ("  [{0,-8}] {1,-16} => {2}" -f $r.Status, $r.Model, $r.Message) -ForegroundColor $color
}

$counts = $results | Group-Object Status | Sort-Object Count -Descending
Write-Host ''
foreach ($g in $counts) {
    $gColor = $colorMap[$g.Name]
    if (-not $gColor) { $gColor = 'White' }
    Write-Host ("  {0,-10}: {1}" -f $g.Name, $g.Count) -ForegroundColor $gColor
}

if ($Report) {
    $reportDir = Join-Path (Get-RepoRoot) 'reports'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $file = Join-Path $reportDir ("connectivity-" + (Get-Timestamp) + ".md")
    $lines = @("# ModelCompass — Kết quả test kết nối", '', "Ngày: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '', '| Provider | Model | Status | Message |', '|---|---|---|---|')
    foreach ($r in $results) {
        $lines += "| $($r.Provider) | $($r.Model) | $($r.Status) | $($r.Message) |"
    }
    $lines | Set-Content -LiteralPath $file -Encoding utf8
    Write-Info "Report: $file"
}

$bad = @('ERROR', 'DOWN', 'NOTFOUND', 'TIMEOUT')
$nBad = @($results | Where-Object { $bad -contains $_.Status }).Count
if ($nBad -gt 0) {
    Write-Fail "Có $nBad provider/model lỗi — kiểm tra trước khi publish."
    exit 1
}
Write-Ok 'Tất cả provider/model reachable (AUTH/RATE/SKIP không tính là lỗi).'
exit 0