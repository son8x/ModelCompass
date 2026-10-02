#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Dừng opencode server theo đúng thứ tự (watchdog trước, tiến trình sau).

.DESCRIPTION
    THỨ TỰ QUAN TRỌNG. Nếu kill tiến trình opencode trước, vòng lặp watchdog
    trong Start-OpenCodeServer.ps1 sẽ tưởng là crash và khởi động lại — server
    sống dai. Nên script này luôn:

        1. Dừng tiến trình launcher (watchdog) trước
        2. Mới dừng tiến trình opencode.exe đang nghe cổng
        3. Xoá file PID cho khỏi rác

    Nếu server do Task Scheduler quản lý, nhớ chạy kèm
    Install-OpenCodeServer.ps1 -Uninstall, nếu không scheduler sẽ bật lại server.

.PARAMETER Port
    Cổng cần dừng. Mặc định đọc từ khối "server" trong opencode.json, không có thì 4096.

.PARAMETER Force
    Kill cưỡng bức (dùng cho tiến trình treo không đáp ứng lệnh dừng mềm).

.PARAMETER SkipTask
    Không tự tạm dừng scheduled task liên quan (mặc định: KHÔNG dừng task, chỉ
    cảnh báo nếu task đang tồn tại).

.EXAMPLE
    pwsh scripts\server\Stop-OpenCodeServer.ps1
    pwsh scripts\server\Stop-OpenCodeServer.ps1 -Force
#>
[CmdletBinding()]
param(
    [int]$Port,
    [switch]$Force,
    [switch]$SkipTask
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ErrorActionPreference = 'Stop'

$repoRoot    = Get-RepoRoot
$pidFile     = Join-Path $repoRoot 'reports\opencode-server.pid'
$taskName    = 'ModelCompass-OpenCodeServer'
$globalConfig = Join-Path $HOME '.config\opencode\opencode.json'

if (-not $Port) {
    $fromCfg = $null
    if (Test-Path -LiteralPath $globalConfig -PathType Leaf) {
        try {
            $clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $globalConfig -Raw -Encoding utf8)
            $cfg = $clean | ConvertFrom-Json
            if ($cfg.PSObject.Properties['server'] -and $cfg.server.PSObject.Properties['port']) {
                $fromCfg = [int]$cfg.server.port
            }
        } catch { }
    }
    $Port = if ($fromCfg) { $fromCfg } else { 4096 }
}

Write-Step "DỪNG OPENCODE SERVER (cổng $Port)"

# ── 1. Dừng watchdog trước ────────────────────────────────────
$watchdogStopped = $false
if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    $raw = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
    $lines = @($raw -split "`r?`n" | Where-Object { $_ -match '^\d+$' })
    if ($lines.Count -ge 1) {
        $wrapperPid = [int]$lines[0]
        # File PID có thể cũ (vd sau Stop-ScheduledTask) và PID thì Windows TÁI
        # SỬ DỤNG cho tiến trình khác — kill nhầm là hại. Chỉ kill khi đúng là
        # launcher của ta: tên pwsh + commandline chứa Start-OpenCodeServer.ps1.
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$wrapperPid" -ErrorAction SilentlyContinue
        $isOurLauncher = $owner -and
            $owner.CommandLine -and
            ($owner.CommandLine -match 'Start-OpenCodeServer\.ps1')
        if ($owner -and -not $isOurLauncher) {
            Write-Warn "PID $wrapperPid trong file PID KHÔNG phải launcher của ta (process khác đã tái dùng PID) — bỏ qua để tránh kill nhầm."
            Write-Info 'Tiến trình opencode nghe cổng vẫn được dừng ở bước sau.'
        } elseif ($owner) {
            $proc = Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue
            if ($Force) {
                Stop-Process -Id $wrapperPid -Force -ErrorAction SilentlyContinue
                Write-Ok "Đã kill watchdog (PID $wrapperPid)."
            } else {
                try { $proc.CloseMainWindow() | Out-Null } catch { }
                if ($proc -and -not $proc.WaitForExit(3000)) {
                    Stop-Process -Id $wrapperPid -Force -ErrorAction SilentlyContinue
                }
                Write-Ok "Đã dừng watchdog (PID $wrapperPid)."
            }
            $watchdogStopped = $true
        } else {
            Write-Info "Watchdog PID $wrapperPid không còn chạy (file PID cũ)."
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# ── 2. Dừng tiến trình opencode đang nghe cổng ────────────────
$stopped = @()
try {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
    foreach ($c in $conns) {
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if (-not $p -or $p.ProcessName -ne 'opencode') { continue }
        try {
            if ($Force) {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
            } else {
                Stop-Process -Id $c.OwningProcess -ErrorAction Stop
            }
            $stopped += $c.OwningProcess
            Write-Ok "Đã dừng opencode (PID $($c.OwningProcess)) nghe $($c.LocalAddress):$Port."
        } catch {
            Write-Fail "Không dừng được PID $($c.OwningProcess): $($_.Exception.Message)"
        }
    }
} catch { }

if ($stopped.Count -eq 0) {
    Write-Info "Không có tiến trình opencode nào đang nghe cổng $Port."
}

# ── 3. Cảnh báo scheduled task ─────────────────────────────────
if (-not $SkipTask) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Warn "Scheduled task '$taskName' vẫn tồn tại — nó có thể bật lại server (kể cả khi bạn vừa dừng)."
        Write-Info 'Gỡ hẳn: pwsh scripts\server\Install-OpenCodeServer.ps1 -Uninstall'
        Write-Info "Tạm dừng task: Disable-ScheduledTask -TaskName '$taskName'"
    }
}

# ── 4. Xác nhận ────────────────────────────────────────────────
Start-Sleep -Milliseconds 500
$stillUp = @()
try {
    $stillUp = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
} catch { }

if ($stillUp.Count -eq 0) {
    Write-Host ''
    Write-Ok "Cổng $Port đã trống — server đã dừng."
    exit 0
} else {
    Write-Host ''
    Write-Fail "Cổng $Port vẫn còn tiến trình giữ. Thử:  mc server-stop -Force"
    exit 1
}