#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test nhóm scripts/server/ + regression cho shim mc.ps1.

Phạm vi: kiểm tra TĨNH và hành vi không chạm hệ thống.
  - 4 script server tồn tại, parse được, có #Requires -Version 7
  - launcher nạp lại env từ User scope (không phụ thuộc env của terminal)
  - launcher TỪ CHỐI bind 0.0.0.0 khi không có mật khẩu
  - installer từ chối cài khi bind mở mà thiếu mật khẩu
  - verdict của Get-OpenCodeServerStatus đúng logic
  - mc.ps1 chịu được cả lệnh không tham số phụ (bug $args=$null) và không nuốt stdout

KHÔNG chạy Get-NetTCPConnection / New-ScheduledTask / firewall trong test.
#>

BeforeAll {
    Set-StrictMode -Version Latest
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $serverDir = Join-Path $repoRoot 'scripts\server'
    $mcShim = Join-Path $repoRoot 'scripts\mc.ps1'

    $serverScripts = @{
        Status = Join-Path $serverDir 'Get-OpenCodeServerStatus.ps1'
        Start = Join-Path $serverDir 'Start-OpenCodeServer.ps1'
        Stop = Join-Path $serverDir 'Stop-OpenCodeServer.ps1'
        Install = Join-Path $serverDir 'Install-OpenCodeServer.ps1'
    }

    function Get-ParseErrors {
        param([string]$Path)
        $errs = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
        # @($null) là mảng 1 phần tử, phải trả mảng rỗng khi không có lỗi.
        if ($null -eq $errs) { return @() }
        return @($errs)
    }
}

Describe 'scripts/server — hiện diện và parse được' {
    It 'đủ 4 script' {
        foreach ($k in $serverScripts.Keys) {
            (Test-Path -LiteralPath $serverScripts[$k] -PathType Leaf) |
                Should -BeTrue -Because "script server $k phải tồn tại"
        }
    }

    It 'mọi script parse không lỗi cú pháp' {
        foreach ($k in $serverScripts.Keys) {
            $errs = @(Get-ParseErrors $serverScripts[$k])
            $errs.Count | Should -Be 0 -Because "$k phải parse sạch"
        }
    }

    It 'mọi script khai báo #Requires -Version 7' {
        foreach ($k in $serverScripts.Keys) {
            $raw = Get-Content -LiteralPath $serverScripts[$k] -Raw
            $raw | Should -Match '#Requires -Version 7' -Because "$k cần PowerShell 7"
        }
    }

    It 'mọi script có comment-based help' {
        foreach ($k in $serverScripts.Keys) {
            $raw = Get-Content -LiteralPath $serverScripts[$k] -Raw
            $raw | Should -Match '\.SYNOPSIS' -Because "$k cần có .SYNOPSIS"
        }
    }

    It 'script trong scripts/ nào cũng dot-source Common-Functions từ thư mục cha' {
        Get-ChildItem -LiteralPath $serverDir -Filter *.ps1 | ForEach-Object {
            $raw = Get-Content -LiteralPath $_.FullName -Raw
            $raw | Should -Match "Join-Path \(Split-Path -Parent \`$PSScriptRoot\) 'Common-Functions\.ps1'" `
                -Because "$($_.Name) phải nạp Common-Functions"
        }
    }
}

Describe 'Start-OpenCodeServer — nạp lại env từ registry' {
    It 'đọc User scope thay vì tin env kế thừa' {
        $text = Get-Content -LiteralPath $serverScripts.Start -Raw
        $text | Should -Match "GetEnvironmentVariable\(\`$n, 'User'\)" `
            -Because 'phải đọc trực tiếp từ HKCU, không dựa vào process.env của terminal'
    }

    It 'nạp cả OPENCODE_SERVER_PASSWORD và OPENCODE_SERVER_USERNAME' {
        $text = Get-Content -LiteralPath $serverScripts.Start -Raw
        $text | Should -Match "'OPENCODE_SERVER_PASSWORD'"
        $text | Should -Match "'OPENCODE_SERVER_USERNAME'"
    }

    It 'chặn bind mở (0.0.0.0) khi không có mật khẩu' {
        $text = Get-Content -LiteralPath $serverScripts.Start -Raw
        $text | Should -Match '\$exposed -and -not \$hasPass' `
            -Because 'không được mở server cho cả mạng mà không có mật khẩu'
        $text | Should -Match 'exit 1'
    }

    It 'có vòng watchdog để server sống lại sau khi thoát' {
        $text = Get-Content -LiteralPath $serverScripts.Start -Raw
        $text | Should -Match 'while \(\$true\)'
        $text | Should -Match 'serve'
    }

    It 'ghi file PID để mc server-stop tìm được tiến trình' {
        $text = Get-Content -LiteralPath $serverScripts.Start -Raw
        $text | Should -Match 'opencode-server\.pid'
    }
}

Describe 'Stop-OpenCodeServer — thứ tự dừng đúng' {
    It 'dừng watchdog TRƯỚC tiến trình opencode' {
        $raw = Get-Content -LiteralPath $serverScripts.Stop -Raw
        $iWatch = $raw.IndexOf('$wrapperPid')
        $iOpen = $raw.IndexOf('Get-NetTCPConnection -LocalPort')
        $iWatch | Should -BeGreaterThan 0
        $iOpen | Should -BeGreaterThan 0
        $iWatch | Should -BeLessThan $iOpen `
            -Because 'kill tiến trình opencode trước sẽ bị watchdog bật lại'
    }

    It 'cảnh báo khi scheduled task còn tồn tại' {
        Get-Content -LiteralPath $serverScripts.Stop -Raw |
            Should -Match 'ModelCompass-OpenCodeServer' -Because 'phải nhắc task sẽ bật lại server'
    }

    It 'xoá file PID sau khi dừng' {
        Get-Content -LiteralPath $serverScripts.Stop -Raw |
            Should -Match 'Remove-Item -LiteralPath \$pidFile'
    }
}

Describe 'Install-OpenCodeServer — an toàn khi cài' {
    It 'từ chối cài khi bind 0.0.0.0 mà User env chưa có mật khẩu' {
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match '\$exposed -and -not \$hasPass'
        $raw | Should -Match 'setup-opencode-env\.ps1' `
            -Because 'phải chỉ đường dẫn đặt mật khẩu'
    }

    It 'chạy launcher với tài khoản người dùng, không phải SYSTEM' {
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match 'New-ScheduledTaskPrincipal'
        $raw | Should -Match '\$env:USERDOMAIN\\\$env:USERNAME' `
            -Because 'cần profile người dùng để đọc config, auth và DB của opencode'
        $raw | Should -Not -Match "'SYSTEM'"
    }

    It 'không tạo firewall rule nếu không chỉ định -PhoneIp' {
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match 'KHÔNG tạo firewall rule' -Because 'mặc định phải đóng'
        $raw | Should -Match '-RemoteAddress' -Because 'khi có chỉ định thì khoanh IP'
        $raw | Should -Match '-Profile Private' -Because 'chỉ mạng Private'
    }

    It 'không sửa config người dùng trừ khi có -WriteConfigBlock, và có backup' {
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match '\$WriteConfigBlock'
        $raw | Should -Match '\.bak-server' -Because 'phải backup trước khi ghi config'
    }

    It 'có đường gỡ cài đặt' {
        Get-Content -LiteralPath $serverScripts.Install -Raw |
            Should -Match 'Unregister-ScheduledTask' -Because '-Uninstall phải gỡ task'
    }
}

Describe 'Get-OpenCodeServerStatus — logic verdict' {
    BeforeAll {
        $script:statusRaw = Get-Content -LiteralPath $serverScripts.Status -Raw
    }

    It 'phân biệt 4 trạng thái' {
        $script:statusRaw | Should -Match "'STOPPED'"
        $script:statusRaw | Should -Match "'UNSECURED'"
        $script:statusRaw | Should -Match "'OK'"
        $script:statusRaw | Should -Match "'AUTH-MISMATCH'"
    }

    It 'coi HTTP 401 (không auth) là server CÓ bật auth' {
        $script:statusRaw | Should -Match '\$probe\.WithoutAuth -eq 401'
    }

    It 'giải thích nguyên nhân env lệch thay vì chỉ báo lỗi' {
        $script:statusRaw | Should -Match 'process\.env' `
            -Because 'nguyên nhân chính là server đọc env lúc khởi động'
    }

    It 'trả IP LAN để người dùng gõ URL trên điện thoại' {
        $script:statusRaw | Should -Match 'urlPhone'
        $script:statusRaw | Should -Match '0\.0\.0\.0/0' `
            -Because 'IP cần lấy từ interface có default route, không phải loopback'
    }

    It 'không in mật khẩu ra màn hình' {
        $script:statusRaw | Should -Not -Match 'OPENCODE_SERVER_PASSWORD[^''"]*\)\s*\}' `
            -Because 'chỉ được báo có/không, không được lộ giá trị'
    }

    # Bug thật, chỉ lộ ra khi server ĐANG TẮT: hàm trả về mảng rỗng bị PowerShell
    # unroll thành $null, nên $listeners.Count nổ "property 'Count' cannot be found".
    It 'bọc @() quá kết quả hàm có thể rỗng' {
        $script:statusRaw | Should -Match '\$listeners = @\(Get-ListeningPids' `
            -Because 'server tắt là trường hợp phổ biến nhất, không được vỡ'
        $script:statusRaw | Should -Not -Match '\$listeners = Get-ListeningPids' `
            -Because 'gán thẳng sẽ nhận $null khi không có tiến trình nào'
    }
}

Describe 'Stop-OpenCodeServer — không kill nhầm qua PID cũ' {
    It 'bọc @() cho danh sách PID trong file' {
        $raw = Get-Content -LiteralPath $serverScripts.Stop -Raw
        $raw | Should -Match '\$lines = @\(\$raw -split' `
            -Because 'file PID rỗng cũng phải xử lý được'
    }

    It 'chỉ kill PID nếu commandline đúng là launcher của ta' {
        $raw = Get-Content -LiteralPath $serverScripts.Stop -Raw
        $raw | Should -Match 'Start-OpenCodeServer\\?\.ps1' `
            -Because 'Windows tái sử dụng PID; PID file cũ có thể trỏ sang tiến trình khác'
        $raw | Should -Match 'KHÔNG phải launcher của ta' -Because 'phải cảnh báo thay vì im lặng bỏ qua'
    }
}

Describe 'Install-OpenCodeServer — trigger khớp principal' {
    It 'Interactive -> AtLogOn, không phải AtStartup' {
        # Ghép sai thì task không bao giờ chạy: AtStartup lúc boot chưa có phiên
        # tương tác nên task bị treo cho tới lần đăng nhập đầu.
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match 'New-ScheduledTaskTrigger -AtLogOn -User \$userId'
        $raw | Should -Match "LogonType Password" -Because 'chế độ chạy cả lúc boot mới cần LogonType Password'
    }

    It 'đặt Delay qua property (New-ScheduledTaskTrigger -RandomDelay không dính)' {
        # -RandomDelay tạo ra trigger không lưu được giá trị, phải gán .Delay.
        $raw = Get-Content -LiteralPath $serverScripts.Install -Raw
        $raw | Should -Match '\$trigger\.Delay = "PT\$\{DelaySeconds\}S"'
        $raw | Should -Not -Match 'New-ScheduledTaskTrigger -AtStartup -RandomDelay'
    }
}

Describe 'mc.ps1 — regression shim CLI' {
    It 'tồn tại' {
        Test-Path -LiteralPath $mcShim -PathType Leaf | Should -BeTrue
    }

    It 'lệnh không có tham số phụ không được splat $args=$null' {
        # Bug: `pwsh -File mc.ps1 <lệnh>` để $args là $null, splat vào thành
        # đối số $null và hỏng ("A positional parameter cannot be found").
        $raw = Get-Content -LiteralPath $mcShim -Raw
        $raw | Should -Match '\$null -ne \$args' -Because 'phải kiểm tra $args trước khi splat'
        $raw | Should -Not -Match '(?m)^\s*\$code = mc \$Command @args\s*$' `
            -Because 'splat thẳng @args là hỏng khi $args là $null'
    }

    It 'không nuốt stdout của script con' {
        # Bug: `$code = mc ...` nuốt luôn stdout của tiến trình pwsh con,
        # khiến mọi lệnh (mc sync, mc compare...) in ra rỗng.
        $raw = Get-Content -LiteralPath $mcShim -Raw
        $raw | Should -Match '\$results = @\(mc \$Command' -Because 'phải tách output khỏi mã thoát'
        $raw | Should -Match '\$item -is \[int\]' -Because 'mã thoát là int ở cuối'
    }

    It 'mọi lệnh trong CommandMap đều trỏ tới file tồn tại' {
        $map = & (Import-Module (Join-Path $repoRoot 'modules\ModelCompass\ModelCompass.psd1') -Force -PassThru) {
            Get-McCommandMap
        }
        foreach ($k in $map.Keys) {
            $p = Join-Path (Join-Path $repoRoot 'scripts') $map[$k]
            (Test-Path -LiteralPath $p -PathType Leaf) |
                Should -BeTrue -Because "lệnh '$k' -> $($map[$k])"
        }
    }

    It 'có đủ nhóm lệnh server' {
        $map = & (Import-Module (Join-Path $repoRoot 'modules\ModelCompass\ModelCompass.psd1') -Force -PassThru) {
            Get-McCommandMap
        }
        foreach ($cmd in @('server', 'server-start', 'server-stop', 'server-setup')) {
            $map.ContainsKey($cmd) | Should -BeTrue -Because "lệnh '$cmd' phải có trong map"
        }
    }
}

Describe 'layout scripts/ — không còn đường dẫn phẳng cũ' {
    It 'mọi tham chiếu scripts\*.ps1 đã có nhóm thư mục' {
        # mc.ps1 và Common-Functions.ps1 cố ý ở gốc scripts/ — loại ra.
        $flat = [regex]'(?:mc|Common-Functions)\.ps1$'
        $stale = @(
            foreach ($f in Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include *.md, *.yml, *.ps1, *.jsonc -Force) {
                if ($f.FullName -match '\\\.git\\' -or $f.Name -eq '.env.local') { continue }
                if ($f.FullName -notmatch '\\(docs|tests|scripts|configs|modules|\.github)\\' -and $f.Name -notin @('README.md', 'CHANGELOG.md', 'ROADMAP.md')) { continue }
                $pattern = 'scripts[\\/](?!config[\\/]|provider[\\/]|spend[\\/]|env[\\/]|test[\\/]|server[\\/])([A-Za-z\-]+\.ps1)'
                foreach ($h in (Select-String -LiteralPath $f.FullName -Pattern $pattern -AllMatches)) {
                    foreach ($m in $h.Matches) {
                        if ($flat.IsMatch($m.Value)) { continue }
                        "$($f.Name):$($h.LineNumber): $($m.Value)"
                    }
                }
            }
        )
        $stale | Should -BeNullOrEmpty -Because 'mọi đường dẫn scripts/ phải trỏ kèm nhóm thư mục'
    }

    It 'mc.ps1 và Common-Functions.ps1 vẫn ở gốc scripts/' {
        (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\mc.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\Common-Functions.ps1') -PathType Leaf) | Should -BeTrue
    }
}
Describe 'Firewall + bind options' {

    BeforeAll {
        $installer = Join-Path $repoRoot 'scripts\server\Install-OpenCodeServer.ps1'
    }

    It 'installer có tham số -AllowLanSubnet và -Tailscale' {
        $params = (Get-Command $installer).Parameters
        $params.ContainsKey('AllowLanSubnet') | Should -BeTrue -Because 'IP dien thoai doi khi doi SSID, khoanh IP cung se hong'
        $params.ContainsKey('Tailscale')     | Should -BeTrue -Because 'duong Tailscale khong can khoanh IP'
    }

It 'rule LAN dùng LocalSubnet + Private, KHÔNG khoanh IP cu the' {
        $s = Get-Content -LiteralPath $installer -Raw
        $s | Should -Match '-RemoteAddress LocalSubnet'
        $s | Should -Match '\-Profile Private'
        # Bỏ dòng chú thích (.PARAMETER/helper) vì ví dụ trong help có IP mẫu.
        $code = @(Get-Content -LiteralPath $installer |
            Where-Object { $_ -notmatch '^\s*[.#]' })
        $hard = @($code | Where-Object { $_ -match '-RemoteAddress\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' })
        $hard | Should -BeNullOrEmpty -Because 'IP điện thoại động, khoanh cứng sẽ hỏng'
    }

    It 'rule Tailscale khoán theo interface, KHÔNG mở toàn bộ' {
        $s = Get-Content -LiteralPath $installer -Raw
        $s | Should -Match '-InterfaceAlias \$adapter\.Name'
        # Phai kiem tra adapter ton tai truocc khi tao rule
        $s | Should -Match 'Get-NetAdapter'
    }

    It 'moi rule firewall đều mang Description để -Uninstall gỡ được' {
        $s = Get-Content -LiteralPath $installer -Raw
        # Moi New-NetFirewallRule deu phai kem -Description $fwDesc
        $newRules = [regex]::Matches($s, 'New-NetFirewallRule[\s\S]{0,400}?Out-Null')
        $newRules.Count | Should -BeGreaterThan 0
        foreach ($m in $newRules) {
            $m.Value | Should -Match '-Description \$fwDesc'
        }
    }

    It '-Uninstall gỡ rule theo Description chứ không theo tên' {
        $s = Get-Content -LiteralPath $installer -Raw
        $s | Should -Match 'Description -eq \$fwDesc'
    }

    It 'bind 0.0.0.0 mà không có mật khẩu thì phải chặn cài' {
        $s = Get-Content -LiteralPath $installer -Raw
        # Single-quote: nếu dùng double-quote, $exposed sẽ bị nội suy và
        # StrictMode Latest ném lỗi "variable has not been set".
        $s | Should -Match '\$exposed -and -not \$hasPass'
    }
}

Describe 'StartNow phải nạp lại tham số mới' {

    BeforeAll {
        $installer = Join-Path $repoRoot 'scripts\server\Install-OpenCodeServer.ps1'
    }

    It 'dừng task đang chạy trước khi Start-ScheduledTask lại' {
        $s = Get-Content -LiteralPath $installer -Raw
        # Task MultipleInstances=IgnoreNew nen Start lai khong thay the tien trinh cu,
        # tham so moi (vd -Hostname) se khong co tac dung.
        $s | Should -Match 'Stop-ScheduledTask -TaskName \$taskName'
        $iStop = $s.IndexOf('Stop-ScheduledTask -TaskName $taskName')
        $iStart = $s.IndexOf('Start-ScheduledTask -TaskName $taskName')
        $iStop | Should -BeGreaterThan -1
        $iStart | Should -BeGreaterThan $iStop -Because 'phai stop truoc, start sau'
    }
}

Describe 'Status phải phản ánh đúng khả năng truy cập' {

    BeforeAll {
        $status = Join-Path $repoRoot 'scripts\server\Get-OpenCodeServerStatus.ps1'
    }

    It 'urlPhone chỉ có khi server thật sự bind mọi interface' {
        $s = Get-Content -LiteralPath $status -Raw
        $s | Should -Match 'urlPhone\s*=\s*if \(\$lanIp -and \$lanReachable\)'
    }

    It 'in cảnh báo khi chỉ bind loopback, không in URL LAN' {
        $s = Get-Content -LiteralPath $status -Raw
        $s | Should -Match 'KHÔNG truy cập được'
    }

    It 'có urlTailscale cho IP 100.x' {
        $s = Get-Content -LiteralPath $status -Raw
        $s | Should -Match 'urlTailscale'
        $s | Should -Match "\^100\\\."
    }
}