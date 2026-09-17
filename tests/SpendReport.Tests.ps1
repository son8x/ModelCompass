#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test spend log + báo cáo chi phí (Phase 1.3).
Phủ: ConvertTo-SpendCost / Add-SpendEntry / Get-SpendEntries (Common-Functions)
và các hàm thuần của Get-SpendReport.ps1 — không gọi mạng, dùng file tạm.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Common-Functions.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\Get-SpendReport.ps1') -SkipRun
    $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('modelcompass-spend-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:tmpRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-SpendCost' {
    It 'model free -> 0 USD in/out' {
        $c = ConvertTo-SpendCost -PromptTokens 100 -CompletionTokens 50
        $c.CostIn  | Should -Be 0
        $c.CostOut | Should -Be 0
    }

    It '120K in @2.5 + 30K out @15 = 0.30 + 0.45' {
        $c = ConvertTo-SpendCost -PromptTokens 120000 -CompletionTokens 30000 -PriceIn 2.5 -PriceOut 15
        $c.CostIn  | Should -Be 0.3
        $c.CostOut | Should -Be 0.45
    }

    It 'làm tròn 6 chữ số cho khối lượng nhỏ' {
        $c = ConvertTo-SpendCost -PromptTokens 123 -CompletionTokens 0 -PriceIn 0.285
        $c.CostIn | Should -Be ([math]::Round(123 / 1e6 * 0.285, 6))
    }
}

Describe 'Add-SpendEntry / Get-SpendEntries' {
    It 'ghi 1 dòng JSON hợp lệ và trả về đường dẫn' {
        $file = Add-SpendEntry -Provider 'xkiro' -Model 'open1/sonic-pro' -PromptTokens 1000 -CompletionTokens 200 -CostInUsd 0.001 -CostOutUsd 0.006 -Path (Join-Path $script:tmpRoot 'spend.jsonl')
        $file | Should -Be (Join-Path $script:tmpRoot 'spend.jsonl')
        Test-Path -LiteralPath $file -PathType Leaf | Should -Be $true
    }

    It 'đọc lại đúng các trường (round-trip)' {
        $entries = Get-SpendEntries -Path (Join-Path $script:tmpRoot 'spend.jsonl')
        $e = @($entries)[0]
        $e.provider | Should -Be 'xkiro'
        $e.model    | Should -Be 'open1/sonic-pro'
        $e.prompt_tokens     | Should -Be 1000
        $e.completion_tokens | Should -Be 200
        $e.cost_in_usd       | Should -Be 0.001
        $e.cost_out_usd      | Should -Be 0.006
        $e.total_usd         | Should -Be 0.007
        ($e.ts -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$') | Should -Be $true
    }

    It 'tự tạo thư mục mới khi chưa tồn tại' {
        $deep = Join-Path $script:tmpRoot 'a\b\c\spend.jsonl'
        Add-SpendEntry -Provider 'teamo' -Model 'gpt-7-mini' -Path $deep | Out-Null
        Test-Path -LiteralPath $deep -PathType Leaf | Should -Be $true
        (Get-SpendEntries -Path $deep).Count | Should -Be 1
    }

    It 'lướt qua dòng hỏng, không chết' {
        $file = Join-Path $script:tmpRoot 'bad.jsonl'
        Set-Content -LiteralPath $file -Value @('{"ts":"x","provider":"a"}', 'NOT-JSON{{{', '{"ok":true}') -Encoding utf8
        $entries = @(Get-SpendEntries -Path $file)
        $entries.Count | Should -Be 2
    }

    It 'file chưa tồn tại -> array rỗng' {
        @(Get-SpendEntries -Path (Join-Path $script:tmpRoot 'missing.jsonl')).Count | Should -Be 0
    }
}

Describe 'Get-SpendGroupKey' {
    It 'tách ngày và tháng từ ts' {
        $e = [pscustomobject]@{ ts = '2026-09-17T15:04:05' }
        Get-SpendGroupKey -Entry $e -Key 'day'   | Should -Be '2026-09-17'
        Get-SpendGroupKey -Entry $e -Key 'month' | Should -Be '2026-09'
    }

    It 'provider/model dùng chuỗi trực tiếp' {
        $e = [pscustomobject]@{ provider = 'openrouter'; model = 'x/y' }
        Get-SpendGroupKey -Entry $e -Key 'provider' | Should -Be 'openrouter'
        Get-SpendGroupKey -Entry $e -Key 'model'    | Should -Be 'x/y'
    }
}

Describe 'Get-SpendSummary / Get-SpendGroups' {
    BeforeAll {
        $script:entries = @(
            [pscustomobject]@{ ts = '2026-09-17T10:00:00'; provider = 'xkiro';       model = 'open1/sonic-pro';  prompt_tokens = 100; completion_tokens = 10; cost_in_usd = 0.001; cost_out_usd = 0.002; total_usd = 0.003 }
            [pscustomobject]@{ ts = '2026-09-17T11:00:00'; provider = 'xkiro';       model = 'open1/sonic-pro';  prompt_tokens = 200; completion_tokens = 20; cost_in_usd = 0.002; cost_out_usd = 0.004; total_usd = 0.006 }
            [pscustomobject]@{ ts = '2026-09-18T09:00:00'; provider = 'openrouter';  model = 'deepseek/r2';       prompt_tokens = 50;  completion_tokens = 5;  cost_in_usd = 0.05;  cost_out_usd = 0.1;   total_usd = 0.15 }
        )
    }

    It 'summary cộng đúng token + chi phí' {
        $s = Get-SpendSummary $script:entries
        $s.Entries    | Should -Be 3
        $s.Prompt     | Should -Be 350
        $s.Completion | Should -Be 35
        $s.CostIn     | Should -Be 0.053
        $s.CostOut    | Should -Be 0.106
        $s.Total      | Should -Be 0.159
    }

    It 'gom theo provider, sort giảm dần theo Total' {
        $g = Get-SpendGroups -Entries $script:entries -Key 'provider'
        $g.Count | Should -Be 2
        @($g)[0].Key   | Should -Be 'openrouter'
        @($g)[0].Total | Should -Be 0.15
        @($g)[1].Key   | Should -Be 'xkiro'
        @($g)[1].Total | Should -Be 0.009
    }

    It 'gom theo model, gộp nhiều phiên cùng model' {
        $g = Get-SpendGroups -Entries $script:entries -Key 'model'
        $m = @($g | Where-Object Key -eq 'open1/sonic-pro')
        $m.Count  | Should -Be 1
        $m.Entries    | Should -Be 2
        $m.Prompt     | Should -Be 300
        $m.Completion | Should -Be 30
        $m.CostIn     | Should -Be 0.003
        $m.CostOut    | Should -Be 0.006
        $m.Total      | Should -Be 0.009
    }

    It 'gom theo ngày phân tách 2 ngày' {
        $g = Get-SpendGroups -Entries $script:entries -Key 'day'
        $g.Count | Should -Be 2
        @($g | Where-Object Key -eq '2026-09-17').Entries | Should -Be 2
        @($g | Where-Object Key -eq '2026-09-18').Entries | Should -Be 1
    }

    It 'entries rỗng -> nhóm rỗng, summary toàn 0' {
        @(Get-SpendGroups -Entries @() -Key 'provider').Count | Should -Be 0
        $s = Get-SpendSummary @()
        $s.Entries | Should -Be 0
        $s.Total   | Should -Be 0
    }
}

Describe 'Test-SpendEntryMatch' {
    BeforeAll {
        $script:one = [pscustomobject]@{ ts = '2026-09-17T10:00:00'; provider = 'XKiro'; model = 'open1/sonic-pro' }
    }

    It 'không lọc gì -> true' {
        Test-SpendEntryMatch -Entry $script:one | Should -Be $true
    }

    It 'lọc theo ngày / tháng' {
        Test-SpendEntryMatch -Entry $script:one -Month '2026-09'      | Should -Be $true
        Test-SpendEntryMatch -Entry $script:one -Day '2026-09-17'     | Should -Be $true
        Test-SpendEntryMatch -Entry $script:one -Month '2026-08'      | Should -Be $false
        Test-SpendEntryMatch -Entry $script:one -Day '2026-09-18'     | Should -Be $false
        Test-SpendEntryMatch -Entry $script:one -Month '2026-09' -Day '2026-09-18' | Should -Be $false
    }

    It 'lọc provider/model theo chuỗi con, không phân biệt hoa thường' {
        Test-SpendEntryMatch -Entry $script:one -Provider 'xki'   | Should -Be $true
        Test-SpendEntryMatch -Entry $script:one -Provider 'teamo' | Should -Be $false
        Test-SpendEntryMatch -Entry $script:one -Model 'SONIC'    | Should -Be $true
        Test-SpendEntryMatch -Entry $script:one -Model 'gpt'      | Should -Be $false
    }
}