#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test khoá sắp xếp 2099 (Phase 2.3).
Phủ: New-SortOrderKey / Get-SortOrderKeyBetween (Common-Functions) — thuần, không mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Common-Functions.ps1')
}

Describe 'New-SortOrderKey' {
    It 'sinh 3 key giảm dần mặc định từ 2099-12-31' {
        $keys = New-SortOrderKey -Count 3
        $keys.Count | Should -Be 3
        $keys[0] | Should -Be '2099-12-31'
        $keys[1] | Should -Be '2099-12-30'
        $keys[2] | Should -Be '2099-12-29'
    }

    It 'hỗ trợ -From tuỳ chỉnh (cụm B của 2-xkiro-max)' {
        $keys = New-SortOrderKey -From 2099-10-25 -Count 3
        $keys | Should -Be @('2099-10-25', '2099-10-24', '2099-10-23')
    }

    It '-StepDays -2 cách quãng 2 ngày' {
        $keys = New-SortOrderKey -StepDays -2 -Count 3
        $keys | Should -Be @('2099-12-31', '2099-12-29', '2099-12-27')
    }

    It '-Exclude bỏ qua key đã tồn tại (không trùng)' {
        $keys = New-SortOrderKey -Count 2 -Exclude @('2099-12-30')
        $keys | Should -Be @('2099-12-31', '2099-12-29')
    }

    It 'đầu ra luôn đúng định dạng yyyy-MM-dd' {
        $keys = New-SortOrderKey -From 2099-11-05 -Count 8
        foreach ($k in $keys) {
            $k | Should -Match '^\d{4}-\d{2}-\d{2}$'
        }
    }

    It 'giảm dần nghiêm ngặt theo thứ tự sắp xếp chuỗi' {
        $keys = New-SortOrderKey -Count 6 -StepDays -1
        for ($i = 1; $i -lt $keys.Count; $i++) {
            $keys[$i] | Should -BeLessThan $keys[$i - 1]
        }
    }

    It 'Count = 0 trả về rỗng, không lỗi' {
        New-SortOrderKey -Count 0 | Should -Be @()
    }

    It 'StepDays = 0 bị chặn' {
        { New-SortOrderKey -StepDays 0 } |
            Should -Throw 'StepDays phải khác 0'
    }
}

Describe 'Get-SortOrderKeyBetween' {
    It 'trả khoá nằm giữa 2 model kề (Upper 12-31, Lower 12-29)' {
        Get-SortOrderKeyBetween -Upper 2099-12-31 -Lower 2099-12-29 |
            Should -Be '2099-12-30'
    }

    It 'khoá giữa nằm giữa thứ tự (Upper > key > Lower)' {
        $mid = Get-SortOrderKeyBetween -Upper 2099-10-25 -Lower 2099-10-01
        $mid | Should -BeGreaterThan '2099-10-01'
        $mid | Should -BeLessThan '2099-10-25'
    }

    It '2 key kề sát (không còn ngày trống) bị chặn' {
        { Get-SortOrderKeyBetween -Upper 2099-12-31 -Lower 2099-12-30 } |
            Should -Throw 'Không còn ngày trống giữa 2 key kề sát nhau'
    }

    It '2 key trùng nhau bị chặn' {
        { Get-SortOrderKeyBetween -Upper 2099-12-31 -Lower 2099-12-31 } |
            Should -Throw 'Không thể chèn: 2 key trùng nhau'
    }

    It 'tự hoán đổi khi caller truyền Upper < Lower' {
        Get-SortOrderKeyBetween -Upper 2099-12-29 -Lower 2099-12-31 |
            Should -Be '2099-12-30'
    }

    It 'không trả về 1 trong 2 key biên' {
        $mid = Get-SortOrderKeyBetween -Upper 2099-12-31 -Lower 2099-11-01
        $mid | Should -Not -Be '2099-12-31'
        $mid | Should -Not -Be '2099-11-01'
    }
}