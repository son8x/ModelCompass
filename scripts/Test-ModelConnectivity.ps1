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

.PARAMETER UpdateStatus
    Cập nhật STATUS.md (repo root) với khối "Trạng thái gần nhất" sinh từ kết quả
    probe — chèn/ghi đè giữa marker `<!-- START auto-status -->` / `<!-- END auto-status -->`.
    Bán tự động: chỉ chạy khi có flag này.

.PARAMETER StatusPath
    Thay đổi đường dẫn STATUS.md (mặc định: repo root). Dùng cho test/demo.

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function (dùng cho test dot-source), không chạy probe.

.PARAMETER Benchmark
    Đo latency + token thực: gọi -BenchmarkRuns lần mỗi model, tổng hợp median/min/max
    (ms) + tokens/giây. BẮT BUỘC thu hẹp bằng -Provider hoặc -Model (tránh đốt quota).

.PARAMETER BenchmarkRuns
    Số request benchmark mỗi model. Mặc định: 6.

.PARAMETER BenchmarkPrompt
    Prompt dùng trong benchmark. Mặc định: yêu cầu trả lời ngắn.

.PARAMETER BenchmarkMaxTokens
    max_tokens trong benchmark. Mặc định: 32.

.EXAMPLE
    PS scripts\Test-ModelConnectivity.ps1
    PS scripts\Test-ModelConnectivity.ps1 -Provider '6-teamoRouter' -Report
    PS scripts\Test-ModelConnectivity.ps1 -UpdateStatus   # cập nhật STATUS.md
    PS scripts\Test-ModelConnectivity.ps1 -Benchmark -Provider '1-xkiro-free' -Model 'minimax/minimax-m3:free'
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$Provider,
    [string]$Model,
    [int]$TimeoutSeconds = 20,
    [switch]$Report,
    [switch]$UpdateStatus,
    [string]$StatusPath,
    [switch]$SkipRun,
    [switch]$Benchmark,
    [int]$BenchmarkRuns = 6,
    [string]$BenchmarkPrompt = 'Trả lời một câu ngắn bằng tiếng Việt: 2+2 bằng mấy?',
    [int]$BenchmarkMaxTokens = 32
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')
$ProgressPreference = 'SilentlyContinue'

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

function Invoke-Benchmark {
    <#
    Gọi -Runs request chat/completions giống Invoke-Probe nhưng ghi lại ms + usage token.
    Trả mảng run: { ms, ok, prompt_tokens, completion_tokens, code, error }.
    #>
    param(
        [string]$Url,
        [string]$ModelId,
        [string]$ApiKey,
        [string]$Prompt,
        [int]$MaxTokens,
        [int]$Runs,
        [int]$TimeoutSeconds
    )
    $runs = [System.Collections.Generic.List[object]]::new()
    $headers = @{ Authorization = "Bearer $ApiKey" }
    for ($i = 1; $i -le $Runs; $i++) {
        $body = @{
            model      = $ModelId
            messages   = @(@{ role = 'user'; content = $Prompt })
            max_tokens = $MaxTokens
        } | ConvertTo-Json -Depth 5
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri $Url -Method Post -Headers $headers `
                -ContentType 'application/json' -Body $body `
                -TimeoutSec $TimeoutSeconds -SkipHttpErrorCheck
            $sw.Stop()
            $code = [int]$resp.StatusCode
            $tokIn = 0; $tokOut = 0
            if ($resp.Content) {
                try {
                    $parsed = $null
                    $parsed = $resp.Content | ConvertFrom-Json
                    if ($null -ne $parsed.usage) {
                        $tokIn = [int]$parsed.usage.prompt_tokens
                        $tokOut = [int]$parsed.usage.completion_tokens
                    }
                } catch { }
            }
            $runs.Add([pscustomobject]@{
                ms = $sw.ElapsedMilliseconds; ok = ($code -eq 200 -or $code -eq 201)
                prompt_tokens = $tokIn; completion_tokens = $tokOut; code = $code; error = ''
            })
        } catch {
            $sw.Stop()
            $msg = $_.Exception.Message
            $runs.Add([pscustomobject]@{
                ms = $sw.ElapsedMilliseconds; ok = $false
                prompt_tokens = 0; completion_tokens = 0; code = 0; error = $msg
            })
        }
    }
    return ,$runs
}

function Get-BenchmarkSummary {
    <#
    Tổng hợp mảng runs (từ Invoke-Benchmark) → summary latency/token.
    Hàm THUẦN (không gọi mạng) — phủ test:
      - MedianMs: trung vị các run OK (bền với outlier), MinMs/MaxMs/AvgMs.
      - AvgTokenIn/AvgTokenOut: trung bình token mỗi run OK.
      - TokensPerSec: tổng token / tổng thời gian các run OK (giây), làm tròn 1 chữ số.
      - FailCount + FirstError để phát hiện lỗi lẫn trong benchmark.
    #>
    param([Parameter(Mandatory)]$Runs)
    $okRuns = @($Runs | Where-Object { $_.ok })
    $failRuns = @($Runs | Where-Object { -not $_.ok })

    $msOk = @($okRuns | ForEach-Object { [long]$_.ms })
    $median = 0.0
    $minMs = 0.0; $maxMs = 0.0; $avgMs = 0.0
    $avgIn = 0.0; $avgOut = 0.0; $tps = 0.0
    if ($msOk.Count -gt 0) {
        $sorted = @($msOk | Sort-Object)
        $n = $sorted.Count
        $median = if ($n % 2 -eq 1) { [double]$sorted[[int](($n - 1) / 2)] }
                else { ([double]$sorted[$n / 2 - 1] + [double]$sorted[$n / 2]) / 2 }
        $minMs = [double]($sorted | Select-Object -First 1)
        $maxMs = [double]($sorted | Select-Object -Last 1)
        $avgMs = [math]::Round((($msOk | Measure-Object -Sum -Average).Average), 1)
        $inSum  = ($okRuns | Measure-Object -Property prompt_tokens -Sum).Sum
        $outSum = ($okRuns | Measure-Object -Property completion_tokens -Sum).Sum
        $totMs  = (($msOk | Measure-Object -Sum).Sum)
        $avgIn  = [math]::Round($inSum / $msOk.Count, 1)
        $avgOut = [math]::Round($outSum / $msOk.Count, 1)
        if ($totMs -gt 0) {
            $tps = [math]::Round(($inSum + $outSum) / ($totMs / 1000.0), 1)
        }
    }
    return [pscustomobject]@{
        Ok          = $okRuns.Count
        Fail        = $failRuns.Count
        MedianMs    = [math]::Round($median, 1)
        MinMs       = $minMs
        MaxMs       = $maxMs
        AvgMs       = $avgMs
        AvgTokenIn  = $avgIn
        AvgTokenOut = $avgOut
        TokensPerSec = $tps
        FirstError  = if ($failRuns.Count -gt 0) { [string]$failRuns[0].error } else { '' }
    }
}

function ConvertTo-StatusBlock {
    <#
    Sinh khối markdown "Trạng thái gần nhất" (giữa marker auto-status) từ kết quả probe.
    Chạy được độc lập (hàm thuần) để test.
    #>
    param(
        [Parameter(Mandatory)]$Results,
        [datetime]$TestedAt = (Get-Date)
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<!-- START auto-status (Test-ModelConnectivity.ps1 -UpdateStatus) — KHÔNG sửa tay, script sẽ ghi đè -->')
    $lines.Add("### Trạng thái gần nhất — $(Get-Date $TestedAt -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add('')
    $countParts = @()
    foreach ($g in @($Results | Group-Object Status | Sort-Object Count -Descending)) {
        $countParts += ("{0} {1}" -f $g.Name, $g.Count)
    }
    $lines.Add(('> {0}' -f ($countParts -join '  ·  ')))
    $lines.Add('')
    $lines.Add('| Provider | Model | Status | Phản hồi |')
    $lines.Add('|---|---|---|---|')
    foreach ($r in @($Results)) {
        $lines.Add("| $($r.Provider) | $($r.Model) | **$($r.Status)** | $($r.Message) |")
    }
    $lines.Add('')
    $lines.Add('<!-- END auto-status -->')
    return @($lines)
}

function Update-StatusFile {
    <#
    Ghi/đè khối auto-status vào STATUS.md dựa trên marker.
    Chưa có marker → chèn ngay sau dòng tiêu đề đầu tiên (dòng bắt đầu bằng '#'),
    nếu không còn dòng nào thì chèn cuối file. Trả { Path, Action = insert|replace }.
    #>
    param(
        [Parameter(Mandatory)][string]$StatusPath,
        [Parameter(Mandatory)]$BlockLines
    )
    if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
        throw "Không tìm thấy STATUS.md: $StatusPath"
    }
    $start = '<!-- START auto-status'
    $end = '<!-- END auto-status -->'
    $existing = Get-Content -LiteralPath $StatusPath -Encoding utf8
    $fileLines = [System.Collections.Generic.List[string]]::new([string[]]$existing)

    $iStart = -1; $iEnd = -1
    for ($i = 0; $i -lt $fileLines.Count; $i++) {
        if ($iStart -lt 0 -and $fileLines[$i].StartsWith($start, [System.StringComparison]::Ordinal)) { $iStart = $i }
        if ($fileLines[$i].StartsWith($end, [System.StringComparison]::Ordinal)) { $iEnd = $i }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    if ($iStart -ge 0 -and $iEnd -ge $iStart) {
        for ($i = 0; $i -lt $fileLines.Count; $i++) {
            if ($i -eq $iStart) {
                foreach ($b in $BlockLines) { $out.Add($b) }
            }
            if ($i -lt $iStart -or $i -gt $iEnd) { $out.Add($fileLines[$i]) }
        }
        $action = 'replace'
    } else {
        $insertAt = -1
        for ($i = 0; $i -lt $fileLines.Count; $i++) {
            if ($fileLines[$i] -match '^#') { $insertAt = $i + 1; break }
        }
        if ($insertAt -lt 0) { $insertAt = $fileLines.Count }
        for ($i = 0; $i -le $fileLines.Count; $i++) {
            if ($i -eq $insertAt) {
                foreach ($b in $BlockLines) { $out.Add($b) }
            }
            if ($i -lt $fileLines.Count) { $out.Add($fileLines[$i]) }
        }
        $action = 'insert'
    }
    $out | Set-Content -LiteralPath $StatusPath -Encoding utf8
    return [pscustomobject]@{ Path = $StatusPath; Action = $action }
}

if ($SkipRun) { return }

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Get-RepoRoot) 'configs\development\opencode.jsonc'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy file: $ConfigPath"
    exit 1
}

if ($Benchmark -and -not $Provider -and -not $Model) {
    Write-Fail 'Benchmark bắn nhiều request/model — hãy thu hẹp bằng -Provider và/hoặc -Model.'
    exit 2
}
if ($Benchmark -and $BenchmarkRuns -lt 1) {
    Write-Fail 'BenchmarkRuns phải >= 1.'
    exit 2
}

Write-Step "Test kết nối: $ConfigPath (timeout ${TimeoutSeconds}s)"
if ($Benchmark) {
    Write-Info "Benchmark: $BenchmarkRuns runs/model, prompt='$BenchmarkPrompt' max_tokens=$BenchmarkMaxTokens"
}
$config = Get-ConfigContent $ConfigPath

$results = [System.Collections.Generic.List[object]]::new()

if ($null -eq $config.provider) {
    Write-Fail 'Cấu hình không có mục "provider".'
    exit 1
}

if (-not $Benchmark) {
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
}

if ($Benchmark) {
    foreach ($p in @($config.provider.PSObject.Properties)) {
        if ($Provider -and $Provider -notcontains $p.Name) { continue }
        $def = $p.Value
        $baseUrl = $null
        if ($null -ne $def.options) { $baseUrl = $def.options.baseURL }
        if ([string]::IsNullOrWhiteSpace($baseUrl)) { continue }
        $key = Resolve-EnvValue ([string]$def.options.apiKey)
        $url = $baseUrl.TrimEnd('/') + '/chat/completions'
        if ([string]::IsNullOrWhiteSpace($key)) {
            foreach ($m in @($def.models.PSObject.Properties)) {
                if ($Model -and $Model -ne $m.Name) { continue }
                $results.Add([pscustomobject]@{
                    Provider = $p.Name; Model = $m.Name; Status = 'SKIP'; Message = 'thiếu API key ({env:...})'; ms = 0
                })
            }
            continue
        }
        foreach ($m in @($def.models.PSObject.Properties)) {
            $modelId = $m.Name
            if ($Model -and $Model -ne $modelId) { continue }
            $runs = Invoke-Benchmark -Url $url -ModelId $modelId -ApiKey $key `
                -Prompt $BenchmarkPrompt -MaxTokens $BenchmarkMaxTokens `
                -Runs $BenchmarkRuns -TimeoutSeconds $TimeoutSeconds
            $s = Get-BenchmarkSummary -Runs $runs
            if ($s.Fail -gt 0) {
                $results.Add([pscustomobject]@{
                    Provider = $p.Name; Model = $modelId; Status = 'ERROR'
                    Message = "benchmark fail $($s.Fail)/$($s.Ok + $s.Fail): $($s.FirstError)"
                    ms = $null
                })
            } else {
                $results.Add([pscustomobject]@{
                    Provider = $p.Name; Model = $modelId; Status = 'OK'
                    Message = "med=${($s.MedianMs)}ms ${($s.TokensPerSec)}tok/s (in ${($s.AvgTokenIn)}/out ${($s.AvgTokenOut)})"
                    ms = $s.MedianMs
                })
            }
        }
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
    $lines = @("# ModelCompass — Kết quả test kết nối", '', "Ngày: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '')
    if ($Benchmark) {
        $lines += '| Provider | Model | Status | Median ms | Tokens/s | Token in | Token out |', '|---|---|---|---|---|---|---|'
        foreach ($r in $results) {
            $med = [string]$r.ms
            if ($r.Message -match 'med=([0-9.]+)ms ([0-9.]+)tok/s \(in ([0-9.]+)/out ([0-9.]+)\)') {
                $med = $Matches[1]
                $tps = $Matches[2]; $tin = $Matches[3]; $tout = $Matches[4]
            } else {
                $tps = '—'; $tin = '—'; $tout = '—'
            }
            $lines += "| $($r.Provider) | $($r.Model) | $($r.Status) | $med | $tps | $tin | $tout |"
        }
    } else {
        $lines += '| Provider | Model | Status | Message |', '|---|---|---|---|'
        foreach ($r in $results) {
            $lines += "| $($r.Provider) | $($r.Model) | $($r.Status) | $($r.Message) |"
        }
    }
    $lines | Set-Content -LiteralPath $file -Encoding utf8
    Write-Info "Report: $file"
}

if ($UpdateStatus) {
    $statusFile = $StatusPath
    if ([string]::IsNullOrWhiteSpace($statusFile)) {
        $statusFile = Join-Path (Get-RepoRoot) 'STATUS.md'
    }
    try {
        $block = ConvertTo-StatusBlock -Results $results -TestedAt (Get-Date)
        $upd = Update-StatusFile -StatusPath $statusFile -BlockLines $block
        Write-Info "STATUS.md — khối 'Trạng thái gần nhất' $($upd.Action) xong: $($upd.Path)"
    } catch {
        Write-Fail "Không cập nhật được STATUS.md: $($_.Exception.Message)"
        exit 1
    }
}

$bad = @('ERROR', 'DOWN', 'NOTFOUND', 'TIMEOUT')
$nBad = @($results | Where-Object { $bad -contains $_.Status }).Count
if ($nBad -gt 0) {
    Write-Fail "Có $nBad provider/model lỗi — kiểm tra trước khi publish."
    exit 1
}
Write-Ok 'Tất cả provider/model reachable (AUTH/RATE/SKIP không tính là lỗi).'
exit 0