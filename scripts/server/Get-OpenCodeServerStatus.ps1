#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Trạng thái opencode server (tiến trình, cổng, IP, URL cho điện thoại, health check).

.DESCRIPTION
    Chẩn đoán server đang chạy và trả lời câu hỏi thường gặp:
      - Server có chạy không, PID là bao nhiêu, đang nghe ở đâu
      - Điện thoại gõ URL nào để kết nối (IP LAN thật, không phải 127.0.0.1)
      - Health check CÓ / KHÔNG basic-auth, và biến môi trường đã đúng chưa

    Cốt lõi: server đọc process.env LÚC KHỞI ĐỘNG. Đổi User env sau đó KHÔNG
    áp cho tiến trình đang chạy — script này phân biệt rõ hai khái niệm:
      - User env  : giá trị trong registry (nguồn sự thật, dùng cho lần khởi động sau)
      - Tiến trình : env mà server thực sự đang dùng (suy ra từ kết quả health check)

.PARAMETER Check
    Chỉ kiểm tra, không sửa gì. Exit 0 = server đang chạy và truy cập được,
    exit 1 = không chạy, exit 2 = chạy nhưng KHÔNG đăng nhập được (auth lệch).

.PARAMETER Port
    Cổng cần kiểm tra. Mặc định đọc từ khối "server" trong opencode.json,
    không có thì dùng 4096.

.PARAMETER Json
    Xuất kết quả dạng JSON (tiện cho script khác hoặc app điện thoại đọc).

.EXAMPLE
    pwsh scripts\server\Get-OpenCodeServerStatus.ps1
    pwsh scripts\server\Get-OpenCodeServerStatus.ps1 -Check
    pwsh scripts\server\Get-OpenCodeServerStatus.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [int]$Port,
    [switch]$Json
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ErrorActionPreference = 'Stop'

$serverExe = (Get-ScriptPath 'Start-OpenCodeServer.ps1')
$globalConfig = Join-Path $HOME '.config\opencode\opencode.json'

function Get-ServerPort {
    <# Đọc port từ khối "server" trong opencode.json; null nếu không có. #>
    param([string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    try {
        $clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8)
        $cfg = $clean | ConvertFrom-Json
        if ($cfg.PSObject.Properties['server'] -and $cfg.server.PSObject.Properties['port']) {
            return [int]$cfg.server.port
        }
    } catch { }
    return $null
}

function Get-ListeningPids {
    <# PID của tiến trình opencode.exe đang LISTEN ở cổng đưa vào. #>
    param([int]$OnPort)
    $out = @()
    try {
        $conns = Get-NetTCPConnection -LocalPort $OnPort -State Listen -ErrorAction Stop
        foreach ($c in $conns) {
            $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -eq 'opencode') {
                $out += [pscustomobject]@{
                    Pid      = $c.OwningProcess
                    Bind     = "$($c.LocalAddress):$($c.LocalPort)"
                    StartAt  = $p.StartTime
                }
            }
        }
    } catch { }
    return $out
}

function Get-LanIp {
    <# IP của interface đang có default route — đó là Wi-Fi/Ethernet thật. #>
    try {
        $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
              Sort-Object RouteMetric | Select-Object -First 1
        if (-not $gw) { return $null }
        $ip = Get-NetIPAddress -InterfaceIndex $gw.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
              Where-Object { $_.IPAddress -notmatch '^169\.254' } | Select-Object -First 1
        return $ip.IPAddress
    } catch { return $null }
}

function Invoke-HealthProbe {
    <#
    Gọi /global/health với Basic auth.
    Trả về @{ Code=<int>; WithoutAuth=<int> } — mã 401 = server CÓ yêu cầu auth.
    #>
    param([int]$OnPort, [string]$User, [string]$Pass)
    $url = "http://127.0.0.1:$OnPort/global/health"
    $result = [ordered]@{ Code = 0; WithoutAuth = 0 }

    try {
        $result.WithoutAuth = [int](& curl.exe -s -o NUL -w '%{http_code}' --max-time 5 $url 2>$null)
    } catch { $result.WithoutAuth = 0 }

    if ($User -and $Pass) {
        # Dựng header Basic trong tiến trình, KHÔNG đưa mật khẩu vào argv
        # (tránh lộ qua danh sách tiến trình / log của antivirus).
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${User}:${Pass}"))
        try {
            $result.Code = [int](& curl.exe -s -o NUL -w '%{http_code}' --max-time 5 `
                       -H "Authorization: Basic $b64" $url 2>$null)
        } catch { $result.Code = 0 }
    }
    return $result
}

# ── Thu thập ────────────────────────────────────────────────────
if (-not $Port) {
    $fromCfg = Get-ServerPort -ConfigPath $globalConfig
    $Port = if ($fromCfg) { $fromCfg } else { 4096 }
}

# Bọc @() — hàm trả về mảng rỗng sẽ bị PowerShell unroll thành $null,
# khiến $listeners.Count nổ lỗi đúng lúc server đang tắt.
$listeners = @(Get-ListeningPids -OnPort $Port)
$userEnv  = [Environment]::GetEnvironmentVariable('OPENCODE_SERVER_USERNAME', 'User')
$passEnv  = [Environment]::GetEnvironmentVariable('OPENCODE_SERVER_PASSWORD', 'User')
$lanIp    = Get-LanIp

# IP tailnet Tailscale (100.x): co dinh, khong doi khi doi SSID -> duong an toan hon LAN.
$tailscaleIp = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -match '^100\.' -and $_.InterfaceAlias -like '*Tailscale*' } |
    Select-Object -ExpandProperty IPAddress -First 1)[0]

$hasCreds = -not [string]::IsNullOrWhiteSpace($passEnv)
if (-not $userEnv) { $userEnv = 'opencode' }   # opencode tự mặc định là vậy

$probe = Invoke-HealthProbe -OnPort $Port -User $userEnv -Pass $passEnv

# Chẩn đoán: server có chạy, và có khớp User env không?
$running   = $listeners.Count -gt 0
$authOn    = $probe.WithoutAuth -eq 401
$authWorks = $probe.Code -eq 200
$credsMatch = $authWorks

# Có nghe mọi interface không? (0.0.0.0 / :: ) — quyết định điện thoại vào được không.
$lanReachable = @($listeners | Where-Object { $_.Bind -match '^(0\.0\.0\.0|\[::\]|:::):' }).Count -gt 0

$verdict = if (-not $running) { 'STOPPED' }
           elseif (-not $authOn) { 'UNSECURED' }
           elseif ($credsMatch) { 'OK' }
           else { 'AUTH-MISMATCH' }

$exitCode = switch ($verdict) {
    'OK'      { 0 }
    'STOPPED' { 1 }
    default   { 2 }
}

$data = [ordered]@{
    verdict     = $verdict
    port        = $Port
    running     = $running
    pids        = @($listeners | ForEach-Object { $_.Pid })
    bind        = @($listeners | ForEach-Object { $_.Bind })
    startedAt   = if ($listeners.Count) { $listeners[0].StartAt } else { $null }
    lanIp       = $lanIp
    urlLocal    = "http://localhost:$Port"
    urlPhone    = if ($lanIp -and $lanReachable) { "http://${lanIp}:$Port" } else { $null }
    tailscaleIp = $tailscaleIp
    urlTailscale = if ($tailscaleIp -and $lanReachable) { "http://${tailscaleIp}:$Port" } else { $null }
    authRequired = $authOn
    userEnvMatch = $credsMatch
    httpNoAuth  = $probe.WithoutAuth
    httpWithAuth = $probe.Code
    userScopeHasPassword = $hasCreds
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}

if ($Json) {
    $data | ConvertTo-Json -Depth 4
    exit $exitCode
}

# ── Hiển thị ────────────────────────────────────────────────────
Write-Step "TRẠNG THÁI OPENCODE SERVER (cổng $Port)"

if (-not $running) {
    Write-Warn "Không có tiến trình opencode nào đang nghe cổng $Port."
    Write-Info  'Chạy: pwsh scripts\server\Start-OpenCodeServer.ps1'
    Write-Info  'Hoặc cài tự chạy lúc boot: pwsh scripts\server\Install-OpenCodeServer.ps1'
    exit $exitCode
}

foreach ($l in $listeners) {
    Write-Ok ("PID {0,-7} nghe {1,-22} (khởi động {2})" -f $l.Pid, $l.Bind, $l.StartAt.ToString('HH:mm:ss'))
}

Write-Host ''
switch ($verdict) {
    'OK' {
        Write-Ok 'Đăng nhập OK — User env khớp với tiến trình đang chạy.'
    }
    'UNSECURED' {
        Write-Warn 'Server KHÔNG yêu cầu mật khẩu (thiếu OPENCODE_SERVER_PASSWORD khi khởi động).'
        Write-Info  'Ai trong mạng cũng gọi được — bao gồm cả lệnh shell. Nên đặt mật khẩu.'
    }
    'AUTH-MISMATCH' {
        Write-Fail 'CÓ mật khẩu nhưng ĐĂNG NHẬP KHÔNG ĐƯỢC — User env lệch với tiến trình đang chạy.'
        Write-Info  'Nguyên nhân: server đọc process.env LÚC KHỞI ĐỘNG. Đổi User env sau đó không áp cho tiến trình cũ.'
        Write-Info  'Cách sửa: chạy lại  mc server-stop  rồi  mc server-start'
    }
}

Write-Host ''
Write-Info ("User env : username='{0}'  password={1}" -f $userEnv, $(if ($hasCreds) { 'đã có' } else { 'CHƯA CÓ' }))
Write-Host ("HTTP     : không auth = {0}   có auth = {1}" -f $probe.WithoutAuth, $probe.Code) -ForegroundColor DarkCyan
Write-Host ''
if (-not $running) {
    Write-Host "  Máy này: $($data.urlLocal)  (đang tắt)" -ForegroundColor DarkGray
} elseif ($lanReachable -and $lanIp) {
    Write-Host "  Máy này  : $($data.urlLocal)" -ForegroundColor Cyan
    Write-Host "  Điện thoại: $($data.urlPhone)" -ForegroundColor Cyan
    Write-Host '  (điện thoại phải cùng Wi-Fi; nếu IP đổi do DHCP, xem lại bằng lệnh trên)' -ForegroundColor DarkGray
    if ($data.urlTailscale) {
        Write-Host "  Qua Tailscale: $($data.urlTailscale)" -ForegroundColor Green
        Write-Host '    (IP này CỐ ĐỊNH — dùng được cả khi đổi Wi-Fi hay ra ngoài)' -ForegroundColor DarkGray
    }
} else {
    # Chỉ bind loopback -> URL LAN không dùng được. Không được in ra URL LAN
    # trong trường hợp này, nếu không người dùng sẽ gõ vào rồi tưởng server hỏng.
    Write-Host "  Máy này: $($data.urlLocal)" -ForegroundColor Cyan
    Write-Host "  Điện thoại: KHÔNG truy cập được" -ForegroundColor Yellow
    Write-Info  "Server chỉ bind loopback ($($listeners[0].Bind)) — điện thoại cùng Wi-Fi cũng không vào được."
    Write-Info  'Muốn điện thoại truy cập, KHÔNG nên mở 0.0.0.0 cho cả mạng. Cách an toàn hơn:'
    Write-Info  '  dùng Tailscale — bind vào IP tailnet (cố định, không đổi khi đổi SSID):'
    Write-Info  '    pwsh scripts\server\Install-OpenCodeServer.ps1 -Hostname <ip-tailscale-cua-may>'
    Write-Info  '  hoặc chạy tạm:  pwsh scripts\server\Start-OpenCodeServer.ps1 -Hostname 0.0.0.0'
}

exit $exitCode