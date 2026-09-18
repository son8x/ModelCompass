#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test CLI `mc` (Phase 3.1) — mapping lệnh, quoting chuyển tiếp,
doctor table (thuần). Không gọi mạng, không spawn tiến trình.
Truy cập hàm nội bộ qua InModuleScope (chỉ export `mc` ra ngoài).
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $moduleRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') 'modules\ModelCompass')).Path
    $script:psd1 = Join-Path $moduleRoot 'ModelCompass.psd1'
    Import-Module $script:psd1 -Force
}

Describe 'mc — mapping lệnh' {
    It 'map chứa các lệnh core theo ROADMAP 3.1' {
        InModuleScope ModelCompass {
            $map = Get-McCommandMap
            foreach ($cmd in @('sync', 'publish', 'report', 'validate', 'export')) {
                $map.ContainsKey($cmd) | Should -BeTrue -Because "lệnh $cmd phải có trong map"
            }
        }
    }

    It 'mọi script trong map đều tồn tại trong scripts/' {
        InModuleScope ModelCompass {
            $map = Get-McCommandMap
            foreach ($k in $map.Keys) {
                $path = Get-McScript -Command $k
                $path | Should -Not -BeNullOrEmpty
                (Test-Path -LiteralPath $path -PathType Leaf) | Should -BeTrue -Because "script của lệnh $k"
            }
        }
    }

    It 'lệnh không biết → Get-McScript trả $null' {
        InModuleScope ModelCompass {
            Get-McScript -Command 'nonsense-cmd' | Should -BeNullOrEmpty
        }
    }

    It 'module manifest import được (không lỗi)' {
        $m = Import-Module $script:psd1 -Force -PassThru
        $m.Name | Should -Be 'ModelCompass'
        @($m.ExportedFunctions.Keys) | Should -Contain 'mc'
    }
}

Describe 'ConvertTo-McCommandLine' {
    It 'bọc giá trị chứa khoảng trắng bằng nháy đơn' {
        InModuleScope ModelCompass {
            $line = ConvertTo-McCommandLine -ScriptPath 'C:\x\Test-ModelCompassConfig.ps1' -Args @('-Path', 'configs/development/opencode.jsonc')
            $line | Should -Match "& 'C:\\x\\Test-ModelCompassConfig.ps1'"
            $line | Should -Match ' -Path ''configs/development/opencode.jsonc''$'
        }
    }

    It 'giữ nguyên cờ (switch) không bọc' {
        InModuleScope ModelCompass {
            $line = ConvertTo-McCommandLine -ScriptPath 's.ps1' -Args @('-Report', '-FailOnInvalid')
            $line | Should -Match ' -Report -FailOnInvalid$'
        }
    }

    It 'escape nháy đơn trong giá trị ('' → '''')' {
        InModuleScope ModelCompass {
            $line = ConvertTo-McCommandLine -ScriptPath 's.ps1' -Args @('-Provider', "6-team`'o")
            $line | Should -Match " -Provider '6-team''o'$"
        }
    }

    It 'giá trị số âm bị bọc (không hiểu nhầm thành cờ)' {
        InModuleScope ModelCompass {
            $line = ConvertTo-McCommandLine -ScriptPath 's.ps1' -Args @('-StepDays', '-5')
            $line | Should -Match "'-5'"
        }
    }
}

Describe 'New-McDoctorTable' {
    It 'env thiếu → THIẾU; có → OK' {
        InModuleScope ModelCompass {
            $rows = New-McDoctorTable -Environment @{ XTROUTER_API_KEY = 'abc' } `
                -Ports @([pscustomobject]@{ Name = 'p'; Address = '127.0.0.1'; Port = 1; Ok = $true }) `
                -ConfigValid $true
            $row = @($rows | Where-Object { $_.Name -eq 'XTROUTER_API_KEY' })
            $row.Status | Should -Be 'OK'
            $row = @($rows | Where-Object { $_.Name -eq 'TEAMO_API_KEY' })
            $row.Status | Should -Be 'THIẾU'
        }
    }

    It 'port DOWN và config LỖI được đánh dấu đúng' {
        InModuleScope ModelCompass {
            $rows = New-McDoctorTable -Environment @{} `
                -Ports @([pscustomobject]@{ Name = '9Router local'; Address = '127.0.0.1'; Port = 20128; Ok = $false }) `
                -ConfigValid $false
            @($rows | Where-Object { $_.Kind -eq 'port' }).Status | Should -Be 'DOWN'
            @($rows | Where-Object { $_.Kind -eq 'config' }).Status | Should -Be 'LỖI'
        }
    }

    It 'trả đủ 4 dòng env + N port + 1 config' {
        InModuleScope ModelCompass {
            $rows = New-McDoctorTable -Environment @{} `
                -Ports @(
                    [pscustomobject]@{ Name = 'a'; Address = 'x'; Port = 1; Ok = $true },
                    [pscustomobject]@{ Name = 'b'; Address = 'x'; Port = 2; Ok = $false }
                ) -ConfigValid $true
            $rows.Count | Should -Be (4 + 2 + 1)
        }
    }
}