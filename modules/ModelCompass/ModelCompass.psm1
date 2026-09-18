#Requires -Version 7
#Requires -Modules Microsoft.PowerShell.Utility
Set-StrictMode -Version Latest

<#
ModelCompass.psm1 — CLI `mc`: đóng gói các script trong scripts/ thành 1 điểm vào.
Mỗi lệnh chạy script tương ứng trong TIẾN TRÌNH pwsh con (pwsh -NoProfile -Command)
nên `exit` của script con không giết phiên làm việc của bạn; mã thoát được giữ nguyên.

Một số lệnh có logic riêng (không phải wrapper):
  - mc doctor  : kiểm sức khoẻ (env vars, local service OmniRoute/9Router, config prod).
  - mc status  : validate production + so sánh dev/prod.
  - mc benchmark: Test-ModelConnectivity.ps1 -Benchmark (thêm sẵn cờ đến các tham số còn lại).
  - mc help    : danh sách lệnh.
#>

$script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ScriptsDir = Join-Path $script:RepoRoot 'scripts'

$script:CommandMap = @{
    'sync'         = 'Get-ProviderCatalog.ps1'
    'publish'      = 'Publish-Config.ps1'
    'validate'     = 'Test-ModelCompassConfig.ps1'
    'connectivity' = 'Test-ModelConnectivity.ps1'
    'compare'      = 'Compare-Config.ps1'
    'prices'       = 'Compare-Prices.ps1'
    'spend'        = 'Get-SpendReport.ps1'
    'add-spend'    = 'Add-SpendEntry.ps1'
    'usage'        = 'Get-XKiroUsage.ps1'
    'install'      = 'Install-Config.ps1'
    'restore'      = 'Restore-RunningConfig.ps1'
    'prune'        = 'Prune-Backups.ps1'
    'report'       = 'New-ConfigDriftReport.ps1'
    'sort-order'   = 'New-SortOrderKey.ps1'
    'env'          = 'setup-opencode-env.ps1'
    'export'       = 'Export-ModelBank.ps1'
    'test'         = 'Test-Suite.ps1'
}

$script:EnvChecks = @(
    @{ Name = 'XTROUTER_API_KEY';    Required = $true; Desc = 'xKiro — api.xkiro.com (1-xkiro-free, 2-xkiro-max)' }
    @{ Name = 'OMNIROUTE_KEY';       Required = $true; Desc = 'Gateway OmniRoute local 127.0.0.1:20217 (3/4-*)' }
    @{ Name = 'TEAMO_API_KEY';       Required = $true; Desc = 'TeamoRouter — api.teamorouter.cn (6-teamoRouter)' }
    @{ Name = 'NINE_ROUTER_API_KEY'; Required = $true; Desc = '9Router local 127.0.0.1:20128 (5-9router)' }
)

$script:PortChecks = @(
    @{ Name = 'OmniRoute local (3-omniroute-free, 4-openrouter-free)'; Address = '127.0.0.1'; Port = 20217 }
    @{ Name = '9Router local (5-9router)';                            Address = '127.0.0.1'; Port = 20128 }
)

# ── Hàm nội bộ (một số được test trực tiếp) ──────────────────

function Get-McCommandMap {
    <# Bản đồ lệnh -> tên script (test dùng bản copy). #>
    return $script:CommandMap.Clone()
}

function Get-McScript {
    <#
    Trả đường dẫn đầy đủ script cho tên lệnh; $null nếu lệnh không có trong map.
    #>
    param([Parameter(Mandatory)][string]$Command)
    if ($null -eq $script:CommandMap[$Command]) { return $null }
    $rel = $script:CommandMap[$Command]
    return Join-Path $script:ScriptsDir $rel
}

function ConvertTo-McCommandLine {
    <#
    Dựng lệnh gọi script an toàn: & '<path>' <tokens...>.
    Token dạng cờ (-X hoặc -X:value) để nguyên; giá trị thường được bọc nháy đơn.
    Hàm THUẦN — phủ test.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        $Args = @()
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('& ').Append('''' + ($ScriptPath -replace [regex]::Escape("'"), "''") + '''')
    foreach ($a in $Args) {
        if ($null -eq $a) { continue }
        [void]$sb.Append(' ')
        $s = [string]$a
        if ($s -match '^-[A-Za-z][A-Za-z0-9]*(?:::)?[A-Za-z0-9]*$' -or $s -match '^-[A-Za-z][A-Za-z0-9]*(:|=).+$') {
            [void]$sb.Append($s)
        } else {
            [void]$sb.Append('''' + ($s -replace [regex]::Escape("'"), "''") + '''')
        }
    }
    return $sb.ToString()
}

function Invoke-McScript {
    <# Chạy script trong tiến trình pwsh con, giữ nguyên mã thoát. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [object[]]$Args = @()
    )
    $line = ConvertTo-McCommandLine -ScriptPath $ScriptPath -Args $Args
    & pwsh -NoProfile -Command $line
    return $LASTEXITCODE
}

function Test-McPort {
    <# Kiểm TCP tới địa chỉ/cổng với timeout 1s (trả bool). #>
    param([string]$Address = '127.0.0.1', [int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($Address, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(1000)) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function New-McDoctorTable {
    <#
    Tổng hợp bảng "sức khoẻ" từ dữ liệu đã thu thập (THUẦN, không IO — phủ test).
    Mỗi dòng: { Kind = env|port|config, Name, Status = OK|THIẾU|DOWN|LỖI, Detail }.
    #>
    param(
        [hashtable]$Environment,
        [Parameter(Mandatory)]$Ports,
        [bool]$ConfigValid,
        [string]$ConfigName = 'configs/production/opencode.json'
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $script:EnvChecks) {
        $present = $false
        $val = $null
        if ($null -ne $Environment -and $Environment.ContainsKey($e.Name)) { $val = $Environment[$e.Name] }
        if (-not [string]::IsNullOrWhiteSpace([string]$val)) { $present = $true }
        $rows.Add([pscustomobject]@{
            Kind   = if ($e.Required) { 'env' } else { 'env' }
            Name   = $e.Name
            Status = if ($present) { 'OK' } else { 'THIẾU' }
            Detail = $e.Desc
        })
    }
    foreach ($p in $Ports) {
        $rows.Add([pscustomobject]@{
            Kind   = 'port'
            Name   = "$($p.Name) ($($p.Address):$($p.Port))"
            Status = if ($p.Ok) { 'OK' } else { 'DOWN' }
            Detail = 'kiểm TCP 1s'
        })
    }
    $rows.Add([pscustomobject]@{
        Kind   = 'config'
        Name   = $ConfigName
        Status = if ($ConfigValid) { 'OK' } else { 'LỖI' }
        Detail = 'Test-ModelCompassConfig (production)'
    })
    return @($rows)
}

function Show-McDoctorReport {
    <# Render bảng doctor thành dòng console với màu. #>
    param([Parameter(Mandatory)]$Rows)
    $color = @{ OK = 'Green'; THIẾU = 'Yellow'; DOWN = 'Yellow'; LỖI = 'Red' }
    foreach ($r in $Rows) {
        $c = $color[$r.Status]; if (-not $c) { $c = 'White' }
        Write-Host ("  [{0,-6}] {1}" -f $r.Status, $r.Name) -ForegroundColor $c
    }
}

function Invoke-McDoctor {
    <# mc doctor: thu thập + chạy Test-ModelCompassConfig production, trả mã thoát. #>
    $envMap = @{}
    foreach ($e in $script:EnvChecks) {
        $envMap[$e.Name] = [Environment]::GetEnvironmentVariable($e.Name)
    }
    $ports = @()
    foreach ($p in $script:PortChecks) {
        $ports += [pscustomobject]@{
            Name = $p.Name; Address = $p.Address; Port = $p.Port
            Ok = (Test-McPort -Address $p.Address -Port $p.Port)
        }
    }
    $cfgPath = Get-McScript -Command 'validate'
    $cfgCode = Invoke-McScript -ScriptPath $cfgPath -Args @(@('-Path', (Join-Path $script:RepoRoot 'configs\production\opencode.json')))
    $ConfigValid = ($cfgCode -eq 0)
    $rows = New-McDoctorTable -Environment $envMap -Ports $ports -ConfigValid $ConfigValid
    Show-McDoctorReport -Rows $rows
    $fail = @($rows | Where-Object { $_.Kind -eq 'config' -and $_.Status -eq 'LỖI' }).Count
    if ($fail -gt 0) {
        Write-Host '  → Kết luận: cấu hình production LỖI — chạy mc validate để xem chi tiết.' -ForegroundColor Red
        return 1
    }
    Write-Host '  → Kết luận: OK (thiếu key / service local down chỉ là cảnh báo).' -ForegroundColor Green
    return 0
}

function Invoke-McStatus {
    <# mc status: validate production + Compare-Config (dev vs prod). #>
    $v = Invoke-McScript -ScriptPath (Get-McScript -Command 'validate')
    $c = Invoke-McScript -ScriptPath (Get-McScript -Command 'compare')
    return [Math]::Max($v, $c)
}

function Invoke-McBenchmark {
    <# mc benchmark: Test-ModelConnectivity.ps1 -Benchmark + các tham số còn lại. #>
    $path = Get-McScript -Command 'connectivity'
    $all = [System.Collections.Generic.List[object]]::new()
    $all.Add('-Benchmark')
    foreach ($a in $args) { $all.Add($a) }
    return Invoke-McScript -ScriptPath $path -Args @($all)
}

function Show-McHelp {
    Write-Host ''
    Write-Host 'mc — ModelCompass CLI' -ForegroundColor Cyan
    Write-Host 'Dùng: mc <lệnh> [tham số script] [--]'
    Write-Host ''
    Write-Host '  sync        Get-ProviderCatalog.ps1        (catalog live -> docs/catalogs + snapshots)'
    Write-Host '  publish     Publish-Config.ps1             (dev -> prod, có backup/validate/connectivity)'
    Write-Host '  status      validate production + compare dev/prod'
    Write-Host '  report      New-ConfigDriftReport.ps1      (báo cáo lệch dev/prod + presets + backup)'
    Write-Host '  doctor      kiểm env vars + local service OmniRoute/9Router + config prod'
    Write-Host '  validate    Test-ModelCompassConfig.ps1    (validate 1 file config)'
    Write-Host '  connectivity Test-ModelConnectivity.ps1    (ping provider/model)'
    Write-Host '  benchmark   Test-ModelConnectivity.ps1 -Benchmark (đo latency/token)'
    Write-Host '  compare     Compare-Config.ps1             (dev vs prod)'
    Write-Host '  prices      Compare-Prices.ps1             (giá config vs catalog live)'
    Write-Host '  spend       Get-SpendReport.ps1            (tổng hợp chi phí)'
    Write-Host '  add-spend   Add-SpendEntry.ps1             (ghi 1 phiên chi phí)'
    Write-Host '  usage       Get-XKiroUsage.ps1             (hạn mức xKiro)'
    Write-Host '  install     Install-Config.ps1             (áp production lên opencode global)'
    Write-Host '  restore     Restore-RunningConfig.ps1      (rollback config đang chạy)'
    Write-Host '  prune       Prune-Backups.ps1              (chính sách backup)'
    Write-Host '  sort-order  New-SortOrderKey.ps1           (sinh khoá sắp xếp 2099)'
    Write-Host '  export      Export-ModelBank.ps1           (xuất model bank JSON + schema)'
    Write-Host '  env         setup-opencode-env.ps1         (nạp key từ .env.local vào User env)'
    Write-Host '  test        Test-Suite.ps1                 (chạy toàn bộ test Pester)'
    Write-Host '  help        danh sách lệnh này'
    Write-Host ''
    Write-Host 'Ví dụ: mc sync; mc publish -ConnectivityTest; mc doctor; mc report -FailOnInvalid' -ForegroundColor DarkGray
    Write-Host ''
}

# ── Điểm vào ──────────────────────────────────────────────────
function mc {
    <#
    Điểm vào CLI. Command đầu tiên là tên lệnh; toàn bộ tham số còn lại
    ($args) được chuyển tiếp nguyên trạng tới script phía sau.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Command)
    $rest = $args
    switch ($Command) {
        'help'     { Show-McHelp; return 0 }
        'doctor'   { return Invoke-McDoctor }
        'status'   { return Invoke-McStatus }
        'benchmark' { return Invoke-McBenchmark }
        default {
            $path = Get-McScript -Command $Command
            if ($null -eq $path) {
                Write-Host "mc: không biết lệnh '$Command' — gõ 'mc help'." -ForegroundColor Yellow
                return 2
            }
            return Invoke-McScript -ScriptPath $path -Args $rest
        }
    }
}