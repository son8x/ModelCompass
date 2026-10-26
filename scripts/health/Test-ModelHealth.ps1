#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: kiểm tra "sức khoẻ" từng model (độ trễ + trạng thái) và hiển thị
    trạng thái ngay trong danh sách chọn model của opencode (qua badge đầu `name`).

.DESCRIPTION
    Với mỗi model trong config, gửi N request chat/completions ngắn và đo thời gian
    (ms). Phân loại mỗi model thành một "lớp" để bạn biết nhanh model nào TỐT
    (nhanh), model nào CHẬM, model nào KHÔNG dùng được:

        fast    ⚡  OK, ≤ FastMs              — nên dùng
        ok          OK, ≤ SlowMs              — bình thường (không gắn badge)
        busy    🟡  HTTP 429                  — rate limit / hết quota tạm thời
        slow    🐌  OK > SlowMs hoặc TIMEOUT  — phản hồi chậm / treo
        locked  🔒  HTTP 402/403 hoặc paywall — khoá (hết ví / cần gói cao hơn)
        down    ⛔  401/404/lỗi mạng          — chết hoặc sai
        unknown     thiếu API key             — chưa test được

    Chế độ mặc định CHỈ BÁO CÁO (không sửa file). Thêm `-Apply` để gắn badge
    (⚡/🟡/🐌/🔒/⛔) vào đầu `name` model trong config development — badge sẽ
    hiện trong picker `/model` của opencode sau khi publish + install.
    `-Json` ghi thêm báo cáo máy đọc được vào `reports/model-health.json`.

    Badge do script này quản lý: `Update-XKiroModels.ps1` (sync) sẽ tự GỠ khi
    tái tạo danh sách, nên quy trình đúng là: `mc sync` → `mc health -Apply`.

.PARAMETER ConfigPath
    File cấu hình cần test. Mặc định: configs\development\opencode.jsonc

.PARAMETER Provider
    Chỉ test các provider này (tên khớp). Mặc định: tất cả.

.PARAMETER Model
    Chỉ test model ID này. Mặc định: tất cả.

.PARAMETER TimeoutSeconds
    Thời gian chờ tối đa mỗi request (giây). Mặc định: 15.

.PARAMETER Runs
    Số request mỗi model (lấy median ms của các lần OK). Mặc định: 1.
    Tăng lên 3 nếu muốn số đo ổn định (tốn thêm quota).

.PARAMETER FastMs
    Ngưỡng "fast" (ms). Mặc định: 1500.

.PARAMETER SlowMs
    Ngưỡng "slow" (ms); OK nhưng chậm hơn mức này bị gắn 🐌. Mặc định: 5000.

.PARAMETER Parallel
    Số model probe đồng thời. Mặc định: 4.

.PARAMETER Apply
    Ghi badge trạng thái vào `name` model trong config (có backup + validate).

.PARAMETER Json
    Ghi báo cáo JSON vào -JsonPath (mặc định reports\model-health.json).

.PARAMETER JsonPath
    Đường dẫn file JSON (dùng khi -Json). Mặc định: reports\model-health.json.

.PARAMETER ShowTop
    Chỉ in N model TỐT nhất (theo lớp rồi ms). 0 = in tất cả. Mặc định: 0.

.PARAMETER SkipRun
    Chỉ nạp định nghĩa hàm (dot-source cho test), không chạy probe.

.EXAMPLE
    PS scripts\health\Test-ModelHealth.ps1                 # báo cáo toàn bộ
    PS scripts\health\Test-ModelHealth.ps1 -Provider '1-xkiro-free' -ShowTop 10
    PS scripts\health\Test-ModelHealth.ps1 -Runs 3 -Json
    PS scripts\health\Test-ModelHealth.ps1 -Apply           # gắn badge vào picker
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$Provider,
    [string]$Model,
    [int]$TimeoutSeconds = 15,
    [int]$Runs = 1,
    [int]$FastMs = 1500,
    [int]$SlowMs = 5000,
    [int]$Parallel = 4,
    [switch]$Apply,
    [switch]$Json,
    [string]$JsonPath,
    [int]$ShowTop = 0,
    [switch]$SkipRun
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ProgressPreference = 'SilentlyContinue'

# Tập badge trạng thái do script này quản lý (dùng alternation — tránh lỗi
# character class với emoji ngoài BMP như 🐌/🟡/🔒).
$script:HealthBadges = @{
    fast   = '⚡'
    ok     = ''
    busy   = '🟡'
    slow   = '🐌'
    locked = '🔒'
    down   = '⛔'
    unknown = ''
}
$script:HealthBadgePattern = '(?:⚡|🐌|🟡|🔒|⛔)'
$script:HealthClassOrder = @('fast', 'ok', 'busy', 'slow', 'locked', 'down', 'unknown')

<#
.SYNOPSIS
    Phân loại 1 kết quả probe thành lớp sức khoẻ. THUẦN.
    Status: OK|RATE|LOCKED|AUTH|NOTFOUND|TIMEOUT|DOWN|HTTP|ERROR|SKIP.
#>
function Get-HealthClass {
    param(
        [Parameter(Mandatory)][string]$Status,
        [double]$Ms = 0,
        [int]$FastMs = 1500,
        [int]$SlowMs = 5000
    )
    switch ($Status) {
        'OK' {
            if ($Ms -le $FastMs) { return 'fast' }
            if ($Ms -le $SlowMs) { return 'ok' }
            return 'slow'
        }
        'RATE' { return 'busy' }
        'LOCKED' { return 'locked' }
        'TIMEOUT' { return 'slow' }
        'SKIP' { return 'unknown' }
        default { return 'down' }
    }
}

<#
.SYNOPSIS
    Badge hiển thị cho 1 lớp (rỗng với ok/unknown). THUẦN.
#>
function Get-HealthBadge {
    param([Parameter(Mandatory)][string]$Class)
    $b = $script:HealthBadges[$Class]
    if ($null -eq $b) { return '' }
    return $b
}

<#
.SYNOPSIS
    Gỡ badge trạng thái (nếu có) khỏi name, GIỮ tiền tố ⭐/🆕. THUẦN.
#>
function Remove-HealthBadge {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    $pattern = '^(?<pre>(?:⭐|🆕|\s)*)' + $script:HealthBadgePattern + '\s*'
    return [regex]::Replace($Name, $pattern, '${pre}').TrimEnd()
}

<#
.SYNOPSIS
    Gắn badge trạng thái vào name (sau tiền tố ⭐/🆕, idempotent — gỡ cũ trước). THUẦN.
    Badge rỗng → chỉ gỡ badge cũ.
#>
function Add-HealthBadge {
    param([string]$Name, [string]$Badge)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    $clean = Remove-HealthBadge -Name $Name
    if ([string]::IsNullOrWhiteSpace($Badge)) { return $clean }
    $m = [regex]::Match($clean, '^(?:⭐|🆕|\s)*')
    $prefix = $m.Value
    $rest = $clean.Substring($prefix.Length)
    return ($prefix + $Badge + $rest)
}

<#
.SYNOPSIS
    Sắp kết quả theo lớp (fast trước) rồi ms tăng dần. THUẦN.
#>
function Sort-HealthResults {
    param([Parameter(Mandatory)]$Results)
    $prio = @{}
    for ($i = 0; $i -lt $script:HealthClassOrder.Count; $i++) { $prio[$script:HealthClassOrder[$i]] = $i }
    return @($Results | Sort-Object `
        @{ Expression = { $p = $prio[$_.Class]; if ($null -eq $p) { 99 } else { $p } } }, `
        @{ Expression = { [double]$_.Ms } }, `
        @{ Expression = { [string]$_.Id } })
}

<#
.SYNOPSIS
    Tổng hợp số lượng theo lớp. THUẦN.
#>
function Get-HealthSummary {
    param([Parameter(Mandatory)]$Results)
    $sum = [ordered]@{}
    foreach ($c in $script:HealthClassOrder) { $sum[$c] = 0 }
    foreach ($r in @($Results)) {
        if ($sum.Contains($r.Class)) { $sum[$r.Class]++ }
    }
    $o = [pscustomobject]@{ Total = @($Results).Count }
    foreach ($c in $script:HealthClassOrder) { $o | Add-Member -NotePropertyName $c -NotePropertyValue $sum[$c] }
    return $o
}

<#
.SYNOPSIS
    Sinh TEXT config mới: gắn/gỡ badge trạng thái đầu `name` từng model. THUẦN.
    Targets: mảng @{ Provider; Id; Badge } — scope THEO PROVIDER vì cùng 1 model id có
    thể nằm ở nhiều provider (vd `mistralai/mistral-large-4-0` vừa free vừa max).
    Chỉ chạm dòng/khoá "name" trong ĐÚNG provider — giữ comment, indent, release_date.
#>
function Set-HealthBadgesInConfigText {
    param(
        [Parameter(Mandatory)][string]$Raw,
        [Parameter(Mandatory)]$Targets
    )
    $newline = if ($Raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Raw -split "`r?`n")) { $lines.Add($l) }

    $singleRe = [regex]::new('^(?<pre>\s*"(?<id>[^"]+)"\s*:\s*\{\s*"name"\s*:\s*")(?<name>(?:[^"\\]|\\.)*)(?<post>".*)$')
    $multiOpenRe = [regex]::new('^\s*"(?<id>[^"]+)"\s*:\s*\{\s*$')
    $nameRe = [regex]::new('^(?<pre>\s*"name"\s*:\s*")(?<name>(?:[^"\\]|\\.)*)(?<post>".*)$')

    foreach ($prov in @(@($Targets) | ForEach-Object { $_.Provider } | Select-Object -Unique)) {
        $want = @{}
        foreach ($t in @($Targets)) { if ($t.Provider -eq $prov) { $want[[string]$t.Id] = [string]$t.Badge } }
        if ($want.Count -eq 0) { continue }

        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^\s*"' + [regex]::Escape($prov) + '"\s*:\s*\{')) { $start = $i; break }
        }
        if ($start -lt 0) { continue }

        $depth = 0; $end = $lines.Count - 1
        for ($i = $start; $i -lt $lines.Count; $i++) {
            $depth += ([regex]::Matches($lines[$i], '\{')).Count
            $depth -= ([regex]::Matches($lines[$i], '\}')).Count
            if ($i -gt $start -and $depth -le 0) { $end = $i; break }
        }

        for ($i = $start + 1; $i -lt $end; $i++) {
            $sm = $singleRe.Match($lines[$i])
            if ($sm.Success -and $want.ContainsKey($sm.Groups['id'].Value)) {
                $nm = Add-HealthBadge -Name $sm.Groups['name'].Value -Badge $want[$sm.Groups['id'].Value]
                $lines[$i] = $sm.Groups['pre'].Value + $nm + $sm.Groups['post'].Value
                continue
            }
            $mo = $multiOpenRe.Match($lines[$i])
            if ($mo.Success -and $want.ContainsKey($mo.Groups['id'].Value)) {
                for ($k = $i + 1; $k -lt $end -and $k -le $i + 6; $k++) {
                    $nm2 = $nameRe.Match($lines[$k])
                    if ($nm2.Success) {
                        $newName = Add-HealthBadge -Name $nm2.Groups['name'].Value -Badge $want[$mo.Groups['id'].Value]
                        $lines[$k] = $nm2.Groups['pre'].Value + $newName + $nm2.Groups['post'].Value
                        break
                    }
                }
            }
        }
    }
    return ($lines -join $newline)
}

<#
.SYNOPSIS
    Dựng đối tượng báo cáo JSON (THUẦN) từ kết quả + ngưỡng + thời điểm.
#>
function ConvertTo-HealthReport {
    param(
        [Parameter(Mandatory)]$Results,
        [int]$FastMs = 1500,
        [int]$SlowMs = 5000,
        [datetime]$TestedAt = (Get-Date)
    )
    return [pscustomobject]@{
        testedAt = $TestedAt.ToString('yyyy-MM-dd HH:mm:ss')
        fastMs   = $FastMs
        slowMs   = $SlowMs
        summary   = Get-HealthSummary -Results $Results
        models   = @((Sort-HealthResults -Results $Results) | ForEach-Object {
            [pscustomobject]@{
                provider = $_.Provider
                id       = $_.Id
                class    = $_.Class
                badge    = (Get-HealthBadge -Class $_.Class)
                ms       = $_.Ms
                status   = $_.Status
                code     = $_.Code
            }
        })
    }
}

if ($SkipRun) { return }

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Get-RepoRoot) 'configs\development\opencode.jsonc'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy file: $ConfigPath"
    exit 1
}
if ($Runs -lt 1) { Write-Fail 'Runs phải >= 1.'; exit 2 }
if ($SlowMs -le $FastMs) { Write-Fail 'SlowMs phải > FastMs.'; exit 2 }

Write-Step "Health check: $ConfigPath (timeout ${TimeoutSeconds}s, runs $Runs, fast<=${FastMs}ms, slow>${SlowMs}ms)"
$config = Get-ConfigContent $ConfigPath
if ($null -eq $config.provider) { Write-Fail 'Cấu hình không có mục "provider".'; exit 1 }

# ── 1. Thu thập mục tiêu probe ──
$targets = [System.Collections.Generic.List[object]]::new()
foreach ($p in @($config.provider.PSObject.Properties)) {
    if ($Provider -and $Provider -notcontains $p.Name) { continue }
    $def = $p.Value
    $baseUrl = $null
    if ($null -ne $def.options) { $baseUrl = $def.options.baseURL }
    if ([string]::IsNullOrWhiteSpace($baseUrl)) { continue }
    $key = Resolve-EnvValue ([string]$def.options.apiKey)
    $url = $baseUrl.TrimEnd('/') + '/chat/completions'
    foreach ($m in @($def.models.PSObject.Properties)) {
        if ($Model -and $Model -ne $m.Name) { continue }
        $targets.Add([pscustomobject]@{ provider = $p.Name; id = $m.Name; url = $url; hasKey = (-not [string]::IsNullOrWhiteSpace($key)) })
    }
}

if ($targets.Count -eq 0) {
    Write-Warn 'Không có model nào để test.'
    exit 0
}
Write-Info "Probe $($targets.Count) model (parallel $Parallel)…"

# ── 2. Probe song song, đo ms ──
$keyByProvider = @{}
foreach ($p in @($config.provider.PSObject.Properties)) {
    $keyByProvider[$p.Name] = Resolve-EnvValue ([string]$p.Value.options.apiKey)
}

$raw = @($targets | ForEach-Object -Parallel {
    $t = $_
    $runs = $using:Runs
    $timeout = $using:TimeoutSeconds
    $keyMap = $using:keyByProvider
    $key = $keyMap[$t.provider]
    if ([string]::IsNullOrWhiteSpace($key)) {
        return [pscustomobject]@{ provider = $t.provider; id = $t.id; status = 'SKIP'; ms = 0; code = 0 }
    }
    $hdr = @{ Authorization = "Bearer $key" }
    $okMs = [System.Collections.Generic.List[double]]::new()
    $lastStatus = 'TIMEOUT'; $lastCode = 0; $lastMs = 0.0
    for ($i = 1; $i -le $runs; $i++) {
        $body = @{ model = $t.id; messages = @(@{ role = 'user'; content = 'ping' }); max_tokens = 1 } | ConvertTo-Json -Depth 5
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri $t.url -Method Post -Headers $hdr `
                -ContentType 'application/json' -Body $body -TimeoutSec $timeout -SkipHttpErrorCheck
            $sw.Stop()
            $code = [int]$resp.StatusCode
            $lastCode = $code; $lastMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
            switch ($code) {
                200 { $lastStatus = 'OK'; $okMs.Add($lastMs) }
                201 { $lastStatus = 'OK'; $okMs.Add($lastMs) }
                401 { $lastStatus = 'AUTH' }
                403 { $lastStatus = 'LOCKED' }
                404 { $lastStatus = 'NOTFOUND' }
                402 { $lastStatus = 'LOCKED' }
                429 { $lastStatus = 'RATE' }
                default { $lastStatus = 'HTTP' }
            }
            # Nhận diện "paywall" (hết ví/quota) trả về HTTP 400/403 kèm thông điệp
            # → LOCKED thay vì down (cùng key, chỉ cần nạp thêm tiền là dùng được).
            if ($code -in @(400, 403) -and ([string]$resp.Content) -match 'insufficient|paywall|wallet|balance|quota|credit') {
                $lastStatus = 'LOCKED'
            }
        } catch {
            $sw.Stop()
            $lastMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
            $msg = $_.Exception.Message
            $inner = $_.Exception.InnerException
            if ($null -ne $inner -and $inner.Message) { $msg = $inner.Message }
            if ($msg -match 'timed out|timeout|operation has timed out|operation was canceled|canceled') {
                $lastStatus = 'TIMEOUT'
            } elseif ($msg -match 'refused|unreachable|failed to connect|No connection|could not be resolved|actively refused') {
                $lastStatus = 'DOWN'
            } else {
                $lastStatus = 'ERROR'
            }
            $lastCode = 0
        }
    }
    if ($okMs.Count -gt 0) {
        $sorted = @($okMs | Sort-Object)
        $n = $sorted.Count
        $med = if ($n % 2 -eq 1) { [double]$sorted[[int](($n - 1) / 2)] }
               else { ([double]$sorted[$n / 2 - 1] + [double]$sorted[$n / 2]) / 2 }
        return [pscustomobject]@{ provider = $t.provider; id = $t.id; status = 'OK'; ms = [math]::Round($med, 0); code = 200 }
    }
    return [pscustomobject]@{ provider = $t.provider; id = $t.id; status = $lastStatus; ms = $lastMs; code = $lastCode }
} -ThrottleLimit $Parallel)

$results = @($raw | ForEach-Object {
    [pscustomobject]@{
        Provider = $_.provider
        Id       = $_.id
        Status   = $_.status
        Ms       = $_.ms
        Code     = $_.code
        Class    = (Get-HealthClass -Status $_.status -Ms $_.ms -FastMs $FastMs -SlowMs $SlowMs)
    }
})

$sorted = @(Sort-HealthResults -Results $results)

# ── 3. In bảng ──
Write-Step 'Kết quả'
$colorMap = @{ fast = 'Green'; ok = 'Gray'; busy = 'Yellow'; slow = 'Yellow'; locked = 'DarkYellow'; down = 'Red'; unknown = 'DarkGray' }
$show = if ($ShowTop -gt 0) { @($sorted | Select-Object -First $ShowTop) } else { $sorted }
foreach ($r in $show) {
    $c = $colorMap[$r.Class]; if (-not $c) { $c = 'White' }
    $badge = Get-HealthBadge -Class $r.Class
    $label = if ($badge) { "$badge $($r.Class)" } else { $r.Class }
    $extra = ''
    if ($r.Status -ne 'OK') {
        $extra = if ($r.Code -gt 0) { " (HTTP $($r.Code))" } else { " ($($r.Status))" }
    }
    Write-Host ("  [{0,-8}] {1,6}ms  {2,-40}  {3}{4}" -f $label, $r.Ms, $r.Id, $r.Provider, $extra) -ForegroundColor $c
}

$summary = Get-HealthSummary -Results $results
Write-Host ''
Write-Host ('  Tổng {0}: ' -f $summary.Total) -NoNewline
$parts = @()
foreach ($c in $script:HealthClassOrder) {
    $n = $summary.$c
    if ($n -gt 0) {
        $b = Get-HealthBadge -Class $c
        $parts += ("{0}{1} {2}" -f $b, $c, $n)
    }
}
Write-Host ($parts -join '  ·  ')

# ── 4. JSON ──
if ($Json) {
    if ([string]::IsNullOrWhiteSpace($JsonPath)) {
        $JsonPath = Join-Path (Get-RepoRoot) 'reports\model-health.json'
    }
    $dir = Split-Path -Parent $JsonPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $report = ConvertTo-HealthReport -Results $results -FastMs $FastMs -SlowMs $SlowMs
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $JsonPath -Encoding utf8
    Write-Info "JSON: $JsonPath"
}

# ── 5. Apply badge vào config ──
if ($Apply) {
    $rawText = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8
    $applyTargets = @($results | ForEach-Object {
        # 'busy' (429) là trạng thái TẠM THỜI (dễ do chính probe dồn dập gây ra) →
        # không đóng băng vào name; chỉ ghi badge cho fast/slow/locked/down.
        $badge = if ($_.Class -eq 'busy') { '' } else { Get-HealthBadge -Class $_.Class }
        [pscustomobject]@{ Provider = $_.Provider; Id = $_.Id; Badge = $badge }
    })
    $newText = Set-HealthBadgesInConfigText -Raw $rawText -Targets $applyTargets
    if ($newText -eq $rawText) {
        Write-Info 'Config không đổi (badge đã đúng).'
    } else {
        $backupDir = Join-Path (Split-Path -Parent $ConfigPath) '.backup'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Force -Path $backupDir | Out-Null }
        $backup = Join-Path $backupDir ("opencode.{0}.jsonc" -f (Get-Timestamp))
        Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
        [System.IO.File]::WriteAllText($ConfigPath, $newText, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "Đã gắn badge vào config: $ConfigPath"
        Write-Info "Backup: $backup"

        $validateScript = Join-Path (Get-ScriptsDir) 'config\Test-ModelCompassConfig.ps1'
        & pwsh -NoProfile -File $validateScript -Path $ConfigPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail 'Validate sau khi gắn badge THẤT BẠI — khôi phục backup.'
            Copy-Item -LiteralPath $backup -Destination $ConfigPath -Force
            exit 1
        }
        Write-Ok 'Validate OK.'
    }
}

Write-Step 'BƯỚC TIẾP'
Write-Host '  • Xem trạng thái trong picker: mc health -Apply → mc publish → mc install'
Write-Host '  • Đo ổn định hơn: mc health -Runs 3 -Json (đọc reports/model-health.json)'
Write-Host ''

$down = @($results | Where-Object { $_.Class -in @('down', 'locked') }).Count
if ($down -gt 0) {
    Write-Warn "Có $down model không dùng được ngay (⛔ down / 🔒 locked) — xem bảng trên."
}
Write-Ok 'Xong.'
exit 0
