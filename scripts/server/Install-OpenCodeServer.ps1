#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Cài opencode server tự chạy lúc khởi động Windows (Task Scheduler + firewall).

.DESCRIPTION
    "Cài" ở đây là đăng ký, KHÔNG phải build gì. Thứ tự lắp đặt:

        1. Task Scheduler chạy launcher ở lúc boot (hoặc lúc đăng nhập)
        2. Launcher tự nạp OPENCODE_SERVER_PASSWORD từ registry User scope
           -> đúng lý do "đổi mật khẩu mà server vẫn báo 401"
        3. Watchdog giữ server sống
        4. Firewall mở đúng một cổng, chỉ cho profile Private và IP bạn chỉ định

    Script KHÔNG chạy bằng SYSTEM và KHÔNG sửa file config của bạn trừ khi bạn
    truyền -WriteConfigBlock (khi đó có backup trước).

    AN TOÀN: muốn bind 0.0.0.0 mà không có mật khẩu thì script sẽ từ chối cài.
    Server opencode cho phép chạy lệnh shell — mở nó ra cả mạng LAN mà không mật
    khẩu là lộ quyền thực thi lệnh cho mọi thiết bị trong mạng.

.PARAMETER Uninstall
    Gỡ scheduled task, firewall rule, và dừng server (đảo ngược thao tác cài).

.PARAMETER Port
    Cổng server (mặc định 4096).

.PARAMETER Hostname
    Địa chỉ bind (mặc định 0.0.0.0 = mọi thiết bị trong mạng gọi được).

.PARAMETER PhoneIp
    Chỉ cho phép các IP này trong firewall. Bỏ trống = KHÔNG tạo rule nào
    (an toàn nhất; bạn tự mở khi đã hiểu rõ). Ví dụ: -PhoneIp 192.168.1.55

.PARAMETER AllowLanSubnet
    Mở cho MỌI máy trong cùng mạng LAN, profile Private. Dùng khi IP điện thoại
    động và hay đổi khi bạn đổi SSID — khoanh một IP cứng sẽ hỏng ngay.

.PARAMETER Tailscale
    Thêm luật firewall khoanh theo interface Tailscale: chỉ thiết bị đi qua đường
    Tailscale mới gọi được, thiết bị trong Wi-Fi cục bộ không chạm vào được.
    IP tailnet (100.x) cố định nên đổi SSID hay ra ngoài vẫn dùng được.

.PARAMETER SkipFirewall
    Không đụng tới firewall (kể cả khi có PhoneIp).

.PARAMETER WriteConfigBlock
    Ghi khối "server" vào ~/.config/opencode/opencode.json (có backup trước).
    Mặc định KHÔNG ghi — launcher đã truyền --hostname/--port từ scheduled task.

.PARAMETER RunWhenLoggedOut
    Chạy cả khi bạn chưa đăng nhập Windows. Cần -WindowsPassword vì Windows lưu
    mật khẩu để chạy task nền. Mặc định: chỉ chạy khi bạn đã đăng nhập (không cần mật khẩu).

.PARAMETER WindowsPassword
    Mật khẩu Windows (dùng cho -RunWhenLoggedOut). Nhập an toàn, không gõ trong câu lệnh.

.PARAMETER StartNow
    Chạy thử server ngay sau khi cài (mặc định: có).

.PARAMETER Force
    Ghi đè task/firewall rule đã tồn tại.

.EXAMPLE
    pwsh scripts\server\Install-OpenCodeServer.ps1
    pwsh scripts\server\Install-OpenCodeServer.ps1 -PhoneIp 192.168.1.55
    pwsh scripts\server\Install-OpenCodeServer.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [int]$Port = 4096,
    [string]$Hostname = '0.0.0.0',
    [string[]]$PhoneIp,
    [switch]$AllowLanSubnet,
    [switch]$Tailscale,
    [string]$TailscaleInterface = 'Tailscale',
    [switch]$SkipFirewall,
    [switch]$WriteConfigBlock,
    [switch]$RunWhenLoggedOut,
    [Security.SecureString]$WindowsPassword,
    [int]$DelaySeconds = 45,
    [switch]$StartNow,
    [switch]$Force
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ErrorActionPreference = 'Stop'

# -StartNow mặc định BẬT (khớp .PARAMETER); truyền -StartNow:$false để bỏ.
if (-not $PSBoundParameters.ContainsKey('StartNow')) { $StartNow = $true }

$repoRoot    = Get-RepoRoot
$startScript = Join-Path $PSScriptRoot 'Start-OpenCodeServer.ps1'
$stopScript  = Join-Path $PSScriptRoot 'Stop-OpenCodeServer.ps1'
$globalConfig = Join-Path $HOME '.config\opencode\opencode.json'
$taskName    = 'ModelCompass-OpenCodeServer'
$fwName      = "OpenCode Server TCP $Port"
$fwDesc      = 'ModelCompass opencode server (tao boi scripts\server\Install-OpenCodeServer.ps1)'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Remove-InstalledFirewallRules {
    <#
    Gỡ rule firewall do script này tạo. Nhận diện bằng Description (bền hơn tên
    hiển thị, vì tên có thể đổi theo -Port), KHÔNG đụng tới rule của người khác.
    #>
    $removed = 0
    $rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Description -eq $fwDesc })
    foreach ($r in $rules) {
        try {
            $r | Remove-NetFirewallRule -ErrorAction Stop
            $removed++
        } catch { }
    }
    # Dọn thêm rule cũ tạo trước khi có Description (đổi cách nhận diện).
    foreach ($n in @($fwName, "OpenCode Server TCP $Port", 'OpenCode Server (TCP)')) {
        foreach ($r in @(Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue)) {
            try { $r | Remove-NetFirewallRule -ErrorAction Stop; $removed++ } catch { }
        }
    }
    return $removed
}

# ── GỠ CÀI ĐẶT ────────────────────────────────────────────────
if ($Uninstall) {
    Write-Step "GỠ OPENCODE SERVER TỰ ĐỘNG"

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Ok "Đã gỡ scheduled task '$taskName'."
        } catch {
            Write-Fail "Không gỡ được task: $($_.Exception.Message)"
        }
    } else {
        Write-Info "Không có scheduled task '$taskName'."
    }

    if (-not $SkipFirewall) {
        if ($isAdmin) {
            $n = Remove-InstalledFirewallRules
            if ($n) { Write-Ok "Đã gỡ $n firewall rule liên quan." } else { Write-Info 'Không có firewall rule nào của opencode.' }
        } else {
            Write-Warn 'Cần chạy PowerShell bằng quyền Administrator để gỡ firewall rule.'
        }
    }

    & $stopScript -Port $Port -SkipTask
    Write-Host ''
    Write-Ok 'Đã gỡ xong. Server sẽ không tự chạy nữa.'
    exit 0
}

# ── KIỂM TRA ĐIỀU KIỆN ─────────────────────────────────────────
Write-Step "CÀI OPENCODE SERVER TỰ ĐỘNG"

if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) {
    Write-Fail "Không tìm thấy launcher: $startScript"
    exit 1
}

# Tìm pwsh
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) {
    $pwshExe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwshExe)) {
        Write-Fail 'Không tìm thấy pwsh (PowerShell 7). Script này cần PowerShell 7.'
        exit 1
    }
}
Write-Ok "PowerShell: $pwshExe"

# Mật khẩu server: đọc User scope (đúng nguồn launcher sẽ dùng)
$serverUser = [Environment]::GetEnvironmentVariable('OPENCODE_SERVER_USERNAME', 'User')
$serverPass = [Environment]::GetEnvironmentVariable('OPENCODE_SERVER_PASSWORD', 'User')
$hasPass    = -not [string]::IsNullOrWhiteSpace($serverPass)

$exposed = ($Hostname -eq '0.0.0.0' -or $Hostname -eq '::')
if ($exposed -and -not $hasPass) {
    Write-Host ''
    Write-Fail "Bạn chọn bind '$Hostname' (mọi thiết bị trong mạng) nhưng User env chưa có OPENCODE_SERVER_PASSWORD."
    Write-Info 'Đặt mật khẩu trước rồi chạy lại lệnh cài:'
    Write-Info '   pwsh scripts\env\setup-opencode-env.ps1 -PromptOptional'
    Write-Info 'Hoặc tạm thời chỉ bind localhost:  -Hostname 127.0.0.1'
    exit 1
}
if ($hasPass -and $serverPass.Length -lt 12) {
    Write-Warn "Mật khẩu hiện tại chỉ $($serverPass.Length) ký tự. Nên >= 24 ký tự ngẫu nhiên trước khi mở ra mạng."
}
Write-Ok "Server auth: username='$(if ($serverUser) { $serverUser } else { 'opencode' })'  password=$(if ($hasPass) { 'đã có' } else { 'không (chỉ localhost)' })"

# ── 1. FIREWALL ────────────────────────────────────────────────
Write-Host ''
Write-Step '1/3  Firewall'
if ($SkipFirewall) {
    Write-Info 'Bỏ qua (-SkipFirewall). Server sẽ không truy cập được từ mạng khác.'
} elseif (-not $isAdmin) {
    Write-Warn 'Cần PowerShell quyền Administrator để tạo firewall rule. Bỏ qua bước này.'
    Write-Info 'Mở lại PowerShell bằng "Run as administrator" rồi chạy lại lệnh cài nếu bạn cần truy cập từ điện thoại.'
} elseif ($PhoneIp -and $PhoneIp.Count -gt 0 -or $AllowLanSubnet) {
    # Gỡ rule cũ do script này tạo (nhận diện bằng Description, không phụ thuộc tên).
    Remove-InstalledFirewallRules | Out-Null

    if ($AllowLanSubnet) {
        # LocalSubnet thay vì khoanh 1 IP: IP điện thoại qua Wi-Fi hay đổi do DHCP
        # và còn đổi nữa khi bạn đổi SSID. Khoanh cứng 1 IP sẽ hỏng ngay.
        # Vẫn giới hạn profile Private để không mở khi ở quán/cafe (profile Public).
        try {
            New-NetFirewallRule -DisplayName "$fwName (LAN)" `
                -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
                -Profile Private -RemoteAddress LocalSubnet `
                -Description $fwDesc | Out-Null
            Write-Ok "Đã mở cổng $Port cho mọi máy trong cùng mạng LAN (profile Private)."
        } catch {
            Write-Fail "Không tạo được rule LAN: $($_.Exception.Message)"
        }
    }

    if ($PhoneIp -and $PhoneIp.Count -gt 0) {
        $remoteArg = ($PhoneIp -join ',')
        try {
            New-NetFirewallRule -DisplayName "$fwName (IP)" `
                -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
                -Profile Private -RemoteAddress $remoteArg `
                -Description $fwDesc | Out-Null
            Write-Ok "Đã mở cổng $Port cho: $remoteArg (profile Private)."
        } catch {
            Write-Fail "Không tạo được rule IP: $($_.Exception.Message)"
        }
    }
} else {
    Write-Warn 'Chưa chỉ định -PhoneIp / -AllowLanSubnet nên KHÔNG tạo firewall rule.'
    Write-Info 'An toàn nhất. Các lựa chọn:'
    Write-Info '   -AllowLanSubnet          mở cho mọi máy cùng mạng (IP động vẫn OK)'
    Write-Info '   -PhoneIp <ip>           chỉ đúng IP đó'
    Write-Info '   -Tailscale              chỉ qua đường Tailscale, không mở LAN'
}

# ── 1b. TAILSCALE ───────────────────────────────────────────────
if ($Tailscale -and -not $SkipFirewall -and $isAdmin) {
    Write-Host ''
    Write-Step '1b   Tailscale (đường điện thoại an toàn hơn firewall LAN)'
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $TailscaleInterface -or $_.InterfaceDescription -like '*Tailscale*' }
    if (-not $adapter) {
        Write-Warn "Không thấy adapter '$TailscaleInterface' — bỏ qua. Nếu đã cài Tailscale, hãy kiểm tra tên interface."
    } else {
        $tsIp = (Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^100\.' } | Select-Object -First 1).IPAddress
        if (-not $tsIp) {
            Write-Warn 'Adapter Tailscale có mặt nhưng chưa có IP 100.x — có thể chưa đăng nhập. Bỏ qua.'
        } else {
            try {
                Get-NetFirewallRule -DisplayName "$fwName (Tailscale)" -ErrorAction Stop | Remove-NetFirewallRule -ErrorAction Stop
            } catch { }
            try {
                # Khoanh theo INTERFACE, không theo IP: đổi SSID hay ra ngoài vẫn xuyên
                # được, còn thiết bị trong Wi-Fi cục bộ thì không chạm vào được.
                New-NetFirewallRule -DisplayName "$fwName (Tailscale)" `
                    -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
                    -Profile Any -InterfaceAlias $adapter.Name `
                    -Description $fwDesc | Out-Null
                Write-Ok "Đã mở cổng $Port qua interface '$($adapter.Name)' (IP tailnet $tsIp)."
                Write-Info "Điện thoại vào:  http://${tsIp}:$Port   (cần cài Tailscale + đăng nhập cùng tài khoản)"
            } catch {
                Write-Fail "Không tạo được rule Tailscale: $($_.Exception.Message)"
            }
        }
    }
}

# ── 2. SCHEDULED TASK ──────────────────────────────────────────
Write-Host ''
Write-Step $(if ($RunWhenLoggedOut) { '2/3  Scheduled Task (tự chạy lúc boot, trước khi đăng nhập)' } else { '2/3  Scheduled Task (tự chạy khi bạn đăng nhập)' })

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    Write-Info "Task '$taskName' đã tồn tại. Dùng -Force để ghi đè, hoặc -Uninstall rồi cài lại."
    exit 1
}

$argList = @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-File', "`"$startScript`""
    '-Hostname', $Hostname
    '-Port', $Port
)
$action = New-ScheduledTaskAction -Execute $pwshExe -Argument ($argList -join ' ') -WorkingDirectory $repoRoot

$userId = "$env:USERDOMAIN\$env:USERNAME"

# Trigger phải KHỚP với principal, nếu không task sẽ không bao giờ chạy:
#   Interactive (chạy khi đã đăng nhập) -> AtLogOn
#   Password    (chạy cả lúc boot)     -> AtStartup
# Ghép AtStartup với Interactive là sai: lúc boot chưa có phiên tương tác nên
# task bị treo trong hàng đợi cho tới lần đăng nhập đầu tiên.
if ($RunWhenLoggedOut) {
    if (-not $WindowsPassword) {
        Write-Fail '-RunWhenLoggedOut cần -WindowsPassword (Windows phải lưu mật khẩu để chạy task nền).'
        exit 1
    }
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Password -RunLevel Limited
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT${DelaySeconds}S"   # chờ mạng LAN lên sau khi boot
    Write-Info "Chạy cả khi chưa đăng nhập, với tài khoản: $userId (trễ ${DelaySeconds}s sau boot)"
} else {
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
    $trigger.Delay = "PT${DelaySeconds}S"   # chờ profile + mạng sẵn sàng
    Write-Info "Chạy khi bạn đăng nhập, với tài khoản: $userId (trễ ${DelaySeconds}s sau khi đăng nhập)"
    Write-Info 'Muốn chạy cả lúc vừa bật máy (chưa đăng nhập)? Thêm -RunWhenLoggedOut -WindowsPassword <...>'
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

try {
    if ($RunWhenLoggedOut) {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -User $userId -Password $WindowsPassword `
            -Force:$Force | Out-Null
    } else {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -Force:$Force | Out-Null
    }
    Write-Ok "Đã đăng ký task '$taskName'."
} catch {
    Write-Fail "Không đăng ký được scheduled task: $($_.Exception.Message)"
    Write-Info 'Cần chạy PowerShell bằng quyền Administrator để tạo task khởi động.'
    exit 1
}

# ── 3. CONFIG BLOCK (tuỳ chọn) ─────────────────────────────────
Write-Host ''
Write-Step '3/3  Config'
if ($WriteConfigBlock) {
    if (-not (Test-Path -LiteralPath $globalConfig -PathType Leaf)) {
        Write-Warn "Không tìm thấy $globalConfig — bỏ qua. Launcher vẫn chạy đúng nhờ tham số task."
    } else {
        $backup = "$globalConfig.bak-server"
        try {
            Copy-Item -LiteralPath $globalConfig -Destination $backup -Force
            $clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $globalConfig -Raw -Encoding utf8)
            $cfg = $clean | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties['server']) {
                $cfg | Add-Member -NotePropertyName 'server' -NotePropertyValue ([pscustomobject]@{})
            }
            $cfg.server | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $Hostname -Force
            $cfg.server | Add-Member -NotePropertyName 'port'     -NotePropertyValue $Port     -Force
            if ($serverUser) {
                $cfg.server | Add-Member -NotePropertyName 'username' -NotePropertyValue $serverUser -Force
            }
            $json = ($cfg | ConvertTo-Json -Depth 100)
            [IO.File]::WriteAllText($globalConfig, $json, (New-Object Text.UTF8Encoding $false))
            Write-Ok "Đã ghi khối server vào config (backup: $backup)."
            Write-Info 'Lưu ý: file được ghi lại dạng JSON thuần — comment trong file cũ (nếu có) đã mất.'
            Write-Info 'Cần khôi phục: Copy-Item "' + $backup + '" "' + $globalConfig + '"'
        } catch {
            Write-Fail "Không ghi được config (đã giữ nguyên file gốc): $($_.Exception.Message)"
        }
    }
} else {
    Write-Info 'Bỏ qua ghi config (mặc định an toàn). Launcher nhận hostname/port từ task.'
    Write-Info 'Muốn ghim vào config cho công cụ khác đọc: chạy lại với -WriteConfigBlock'
}

# ── CHẠY THỬ ───────────────────────────────────────────────────
Write-Host ''
if ($StartNow) {
    Write-Step 'Khởi động thử'
    # Task đang chạy sẵn vẫn giữ tiến trình CŨ (MultipleInstances=IgnoreNew),
    # nên tham số vừa ghi (vd -Hostname) không có tác dụng. Phải dừng rồi chạy lại.
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Running' }) {
        Write-Info 'Task đang chạy (tiến trình cũ) — dừng để nạp tham số mới rồi khởi động lại.'
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
            Start-Sleep -Seconds 2
        } catch {
            Write-Warn "Không dừng được task: $($_.Exception.Message)"
        }
    }
    try {
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Start-Sleep -Seconds 5
        & (Join-Path $PSScriptRoot 'Get-OpenCodeServerStatus.ps1') -Port $Port
        exit 0
    } catch {
        Write-Warn "Không khởi động được task: $($_.Exception.Message)"
    }
} else {
    Write-Info 'Bỏ qua bước chạy thử (-StartNow bật/tắt).'
}

Write-Host ''
Write-Ok "Cài xong. Kiểm tra:  mc server"
Write-Info 'Gỡ:                 pwsh scripts\server\Install-OpenCodeServer.ps1 -Uninstall'
exit 0