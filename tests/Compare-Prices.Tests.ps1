#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test các hàm thuần của scripts/Compare-Prices.ps1
(trích giá từ name, định dạng, gợi ý name, đối chiếu giá config vs catalog) — không gọi mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Compare-Prices.ps1') -SkipRun
}

Describe 'Get-PricesFromName' {
    It 'trích giá `In:$X | Out:$Y` từ name xKiro Max' {
        $p = Get-PricesFromName '[B – Nhẹ/rẻ] Nemotron 3 Nano (In:$0.05 | Out:$0.20 – Rẻ nhất, 1M ctx)'
        $p.Has | Should -Be $true
        $p.In   | Should -Be 0.05
        $p.Out  | Should -Be 0.20
    }

    It 'chịu khoảng trắng quanh `:` và giá 3 số thập phân' {
        $p = Get-PricesFromName '[A – Đa dạng] Kimi K2.5 (In: $0.285 | Out: $1.425 – Coding giá tốt)'
        $p.Has | Should -Be $true
        $p.In  | Should -Be 0.285
        $p.Out | Should -Be 1.425
    }

    It 'trả Has=$false khi name không có giá (model free)' {
        $p = Get-PricesFromName 'DeepSeek V4 Pro (Reasoning + code mạnh nhất free - 1M ctx)'
        $p.Has | Should -Be $false
    }

    It 'name rỗng/null -> Has=$false' {
        (Get-PricesFromName '').Has   | Should -Be $false
        (Get-PricesFromName $null).Has | Should -Be $false
    }
}

Describe 'Format-Price' {
    It 'giữ 2 chữ số cho giá chẵn' {
        Format-Price 0.05   | Should -Be '0.05'
        Format-Price 9      | Should -Be '9.00'
        Format-Price 4.5    | Should -Be '4.50'
        Format-Price 0      | Should -Be '0.00'
    }

    It 'giữ 3 chữ số cho giá lẻ' {
        Format-Price 0.285  | Should -Be '0.285'
        Format-Price 1.425  | Should -Be '1.425'
    }

    It 'null -> chuỗi rỗng' {
        Format-Price $null   | Should -Be ''
    }
}

Describe 'Update-PricesInName' {
    It 'thay giá mới, giữ nguyên mô tả quanh giá' {
        $new = Update-PricesInName -Name '[A – Đa dạng] GLM-5 (In:$1.00 | Out:$3.20 – Không vision)' -In 1.2 -Out 3.8
        $new | Should -Be '[A – Đa dạng] GLM-5 (In:$1.20 | Out:$3.80 – Không vision)'
    }

    It 'không đổi name khi không có chuỗi giá' {
        $new = Update-PricesInName -Name 'DeepSeek V4 Pro (free - 1M ctx)' -In 0 -Out 0
        $new | Should -Be 'DeepSeek V4 Pro (free - 1M ctx)'
    }
}

Describe 'Compare-ConfigModelsToCatalogPrices' {
    It 'OK khi giá trong name khớp catalog' {
        $cfg = [pscustomobject]@{ 'z-ai/glm-5' = [pscustomobject]@{ name = '[A – Đa dạng] GLM-5 (In:$1.00 | Out:$3.20 – Không vision)' } }
        $cat = @(
            [pscustomobject]@{ id = 'z-ai/glm-5'; pricing = [pscustomobject]@{ input = 1.0; output = 3.2 } }
        )
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat
        $row.State   | Should -Be 'ok'
        $row.CfgIn   | Should -Be 1.0
        $row.CatOut  | Should -Be 3.2
    }

    It 'báo diff + sinh SuggestedName khi giá catalog đổi' {
        $cfg = [pscustomobject]@{ 'openai/gpt-5.4' = [pscustomobject]@{ name = '[A – Đa dạng] GPT-5.4 (In:$2.25 | Out:$13.50 – Đa dạng)' } }
        $cat = @(
            [pscustomobject]@{ id = 'openai/gpt-5.4'; pricing = [pscustomobject]@{ input = 2.4; output = 14.0 } }
        )
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat
        $row.State   | Should -Be 'diff'
        $row.DiffIn  | Should -Be 0.15
        $row.DiffOut | Should -Be 0.5
        $row.SuggestedName | Should -Be '[A – Đa dạng] GPT-5.4 (In:$2.40 | Out:$14.00 – Đa dạng)'
    }

    It 'Pct = chênh lệch / giá config (phần trăm thay đổi đối với người dùng)' {
        $cfg = [pscustomobject]@{ 'x/y' = [pscustomobject]@{ name = 'X (In:$0.50 | Out:$1.00)' } }
        $cat = @([pscustomobject]@{ id = 'x/y'; pricing = [pscustomobject]@{ input = 0.75; output = 1.0 } })
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat
        $row.DiffIn | Should -Be 0.25
        $row.PctIn  | Should -Be 50.0
    }

    It 'no-catalog khi model vắng trong catalog' {
        $cfg = [pscustomobject]@{ 'deepseek/deepseek-v4-pro' = [pscustomobject]@{ name = 'DeepSeek (In:$0.00 | Out:$0.00)' } }
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels @()
        $row.State | Should -Be 'no-catalog'
    }

    It 'strip tiền tố gateway (openrouter/) trước khi tra catalog' {
        $cfg = [pscustomobject]@{ 'openrouter/inclusionai/ling-3.0-flash-sante:free' = [pscustomobject]@{ name = 'Ling 3.0 Flash (Free - OpenRouter)' } }
        $cat = @([pscustomobject]@{ id = 'inclusionai/ling-3.0-flash-sante:free'; pricing = [pscustomobject]@{ input = 0; output = 0 } })
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat -StripPrefixes @('openrouter/')
        $row.State | Should -Be 'no-name-price'
        $row.CatIn  | Should -Be 0
    }

    It 'no-name-price khi catalog có giá nhưng name không nhồi giá' {
        $cfg = [pscustomobject]@{ 'minimax/minimax-m3:free' = [pscustomobject]@{ name = 'MiniMax M3 (free)' } }
        $cat = @([pscustomobject]@{ id = 'minimax/minimax-m3:free'; pricing = [pscustomobject]@{ input = 0; output = 0 } })
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat
        $row.State | Should -Be 'no-name-price'
    }

    It 'no-catalog-price khi catalog thiếu giá (không so được)' {
        $cfg = [pscustomobject]@{ 'teamo/x' = [pscustomobject]@{ name = 'X (In:$1.00 | Out:$2.00)' } }
        $cat = @([pscustomobject]@{ id = 'teamo/x'; pricing = [pscustomobject]@{ input = $null; output = $null } })
        $row = Compare-ConfigModelsToCatalogPrices -ConfigModels $cfg -CatalogModels $cat
        $row.State | Should -Be 'no-catalog-price'
    }
}