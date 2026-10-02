#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Chạy opencode server ở foreground, có watchdog tự khởi động lại.

.DESCRIPTION
    Đây là launcher cho `opencode serve`. Ba điều nó làm đúng hơn chạy lệnh thô:

    1) NẠP LẠI ENV TỪ REGISTRY (rất quan trọng)
       opencode đọc process.env LÚC KHỞI ĐỘNG rồi giữ nguyên. Nếu bạn đổi
       OPENCODE_SERVER_PASSWORD sau đó, tiến trình cũ vẫn dùng mật khẩu cũ —
       đây chính là nguyên nhân "đổi mật khẩu rồi mà vẫn không đăng nhập được".
       Script này đọc thẳng từ HKCU (scope User) nên miễn nhiễm với việc
       terminal cũ mang env cũ.

    2) WATCHDOG
       Task Scheduler chỉ "restart on failure" — mà tiến trình bị kill tay thì
       KHÔNG tính là lỗi. Vòng lặp này bảo đảm server sống lại sau bất kỳ lần
       thoát nào (kể cả crash, kể cả Ctrl+C).

    3) GHI PID + LOG
       Để mc server-stop tìm đúng tiến trình, và bạn xem log khi trục trặc.

.PARAMETER Port
    Cổng nghe. Mặc định đọc khối "server.port" trong opencode.json, không có thì 4096.

.PARAMETER Hostname
    Địa chỉ bind. Mặc định đọc "server.hostname"; không có thì 127.0.0.1.
    Muốn điện thoại truy cập được thì dùng 0.0.0.0 (KÈM mật khẩu + firewall).

.PARAMETER Once
    Chạy đúng một lần, không watchdog (tiện debug).

.PARAMETER NoReloadEnv
    Không nạp lại env từ registry, dùng env kế thừa (mặc định: CÓ nạp lại).

.EXAMPLE
    pwsh scripts\server\Start-OpenCodeServer.ps1
    pwsh scripts\server\Start-OpenCodeServer.ps1 -Hostname 0.0.0.0
    pwsh scripts\server\Start-OpenCodeServer.ps1 -Once
#>
[CmdletBinding()]
param(
    [int]$Port,
    [string]$Hostname,
    [switch]$Once,
    [switch]$NoReloadEnv
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ErrorActionPreference = 'Stop'

$globalConfig = Join-Path $HOME '.config\opencode\opencode.json'
$pidFile      = Join-Path (Get-RepoRoot) 'reports\opencode-server.pid'
$logFile      = Join-Path (Get-RepoRoot) 'reports\opencode-server.log'

function Read-ServerSetting {
    <# Đọc 1 khóa trong khối "server" của opencode.json; null nếu không có/không đọc được. #>
    param([string]$Key, [string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    try {
        $clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8)
        $cfg = $clean | ConvertFrom-Json
        if ($cfg.PSObject.Properties['server'] -and $cfg.server.PSObject.Properties[$Key]) {
            return $cfg.server.$Key
        }
    } catch { }
    return $null
}

# ── Xác định cổng / hostname ───────────────────────────────────
if (-not $Port) {
    $p = Read-ServerSetting -Key 'port' -ConfigPath $globalConfig
    $Port = if ($p) { [int]$p } else { 4096 }
}
if (-not $Hostname) {
    $h = Read-ServerSetting -Key 'hostname' -ConfigPath $globalConfig
    $Hostname = if ($h) { [string]$h } else { '127.0.0.1' }
}

# ── Tìm opencode.exe ───────────────────────────────────────────
$exe = (Get-Command opencode -ErrorAction SilentlyContinue).Source
if (-not $exe) {
    foreach ($cand in @(
        'C:\Programs\OpenCode\opencode.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenCode\opencode.exe'),
        (Join-Path $HOME '.opencode\bin\opencode.exe')
    )) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $exe = $cand; break }
    }
}
if (-not $exe) {
    Write-Fail 'Không tìm thấy opencode.exe — cài opencode hoặc mở terminal đã cài PATH.'
    exit 1
}

# ── Nạp lại env từ registry ────────────────────────────────────
# Danh sách biến opencode đọc trực tiếp từ process.env.
$envNames = @(
    'OPENCODE_SERVER_PASSWORD'
    'OPENCODE_SERVER_USERNAME'
    'XTROUTER_API_KEY'
    'OMNIROUTE_KEY'
    'TEAMO_API_KEY'
    'NINE_ROUTER_API_KEY'
)
$reloaded = @()
if (-not $NoReloadEnv) {
    foreach ($n in $envNames) {
        $v = [Environment]::GetEnvironmentVariable($n, 'User')
        if ($null -ne $v -and $v -ne '') {
            Set-Item -Path "Env:$n" -Value $v
            $reloaded += $n
        }
    }
}

# ── Cảnh báo bảo mật ───────────────────────────────────────────
$hasPass = -not [string]::IsNullOrWhiteSpace($env:OPENCODE_SERVER_PASSWORD)
$exposed = ($Hostname -eq '0.0.0.0' -or $Hostname -eq '::')
if ($exposed -and -not $hasPass) {
    Write-Fail "Đang bind '$Hostname' (mọi thiết bị trong mạng) mà KHÔNG có OPENCODE_SERVER_PASSWORD."
    Write-Info 'Server này cho phép chạy lệnh shell và tốn tiền API. Hãy đặt mật khẩu trước:'
    Write-Info '   pwsh scripts\env\setup-opencode-env.ps1 -PromptOptional'
    exit 1
}
if ($exposed -and $hasPass) {
    $pwLen = $env:OPENCODE_SERVER_PASSWORD.Length
    if ($pwLen -lt 12) {
        Write-Warn "Mật khẩu chỉ $pwLen ký tự — quá yếu cho server đang mở toàn mạng. Nên >= 24 ký tự ngẫu nhiên."
    }
    Write-Info "Đang bind '$Hostname' — nhớ mở firewall CHỈ cho IP điện thoại (xem Install-OpenCodeServer.ps1)."
}

New-Item -ItemType Directory -Force -Path (Split-Path $pidFile) | Out-Null

Write-Step "KHỞI ĐỘNG OPENCODE SERVER"
Write-Info "exe      : $exe"
Write-Info "bind     : ${Hostname}:${Port}"
Write-Info "env nạp  : $(if ($reloaded.Count) { $reloaded -join ', ' } else { '(không có biến nào trong User scope)' })"
Write-Info "pid file : $pidFile"
Write-Host ''

if ($Once) {
    & $exe serve --hostname $Hostname --port $Port 2>&1 | Tee-Object -FilePath $logFile
    exit $LASTEXITCODE
}

# ── Watchdog ───────────────────────────────────────────────────
$iteration = 0
while ($true) {
    $iteration++
    if ($iteration -gt 1) {
        Write-Host ''
        Write-Warn "opencode serve đã thoát — khởi động lại sau 10 giây (lần $iteration)."
        Start-Sleep -Seconds 10
    }

    # Ghi PID của wrapper để mc server-stop dừng được cả vòng lặp
    Set-Content -LiteralPath $pidFile -Value "$PID`n$($iteration)" -Encoding ascii -ErrorAction SilentlyContinue

    try {
        & $exe serve --hostname $Hostname --port $Port *>> $logFile
    } catch {
        Write-Fail "Lỗi khi chạy opencode: $($_.Exception.Message)"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] opencode serve kết thúc (exit=$LASTEXITCODE). Log: $logFile" -ForegroundColor DarkYellow
}