#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test các hàm thuần của scripts/Get-ProviderCatalog.ps1
(chuẩn hoá catalog + đối chiếu config vs catalog) — KHÔNG gọi mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Get-ProviderCatalog.ps1') -Provider @() -NoSave -NoCompare -SkipRun
}

Describe 'ConvertTo-NormalizedModel' {
    It 'chuẩn hoá model dạng OpenRouter (pricing.modality.context_length.created)' {
        $m = [pscustomobject]@{
            id             = 'openai/gpt-5.6-sol'
            context_length = 120000
            pricing        = [pscustomobject]@{ prompt = 4.5; completion = 27.0; request = 0.0005 }
            modality       = [pscustomobject]@{ input = @('text', 'image'); output = @('text') }
            created        = 1710000000
        }
        $n = ConvertTo-NormalizedModel $m
        $n.id       | Should -Be 'openai/gpt-5.6-sol'
        $n.context  | Should -Be 120000
        $n.pricing.input   | Should -Be 4.5
        $n.pricing.output  | Should -Be 27.0
        $n.pricing.request | Should -Be 0.0005
        $n.modality.input  | Should -Be @('text', 'image')
        $n.modality.output | Should -Be @('text')
        $n.created   | Should -Be 1710000000
    }

    It 'đọc pricing qua input_cost/output_cost và context_window' {
        $m = [pscustomobject]@{
            id            = 'deepseek/deepseek-v4-pro'
            context_window = 65536
            input_cost    = 1.2
            output_cost   = 4.8
        }
        $n = ConvertTo-NormalizedModel $m
        $n.context         | Should -Be 65536
        $n.pricing.input   | Should -Be 1.2
        $n.pricing.output  | Should -Be 4.8
        $n.pricing.request | Should -BeNullOrEmpty
        $n.modality        | Should -BeNullOrEmpty
    }

    It 'giữ nguyên id/model name khi không có pricing/context' {
        $n = ConvertTo-NormalizedModel ([pscustomobject]@{ id = 'ollama/gpt-oss:120b' })
        $n.id                  | Should -Be 'ollama/gpt-oss:120b'
        $n.context             | Should -BeNullOrEmpty
        $n.pricing.input       | Should -BeNullOrEmpty
        $n.pricing.output      | Should -BeNullOrEmpty
    }

    It 'loại bỏ entry không có id (không ảnh hưởng danh sách)' {
        $nullEntry = ConvertTo-NormalizedModel ([pscustomobject]@{ object = 'list' })
        $nullEntry | Should -BeNullOrEmpty
    }

    It 'đọc pricing.input/output lồng nhau kiểu xKiro + access_tier' {
        $m = [pscustomobject]@{
            id           = 'openai/gpt-5.6-terra'
            access_tier  = 'paid'
            pricing      = [pscustomobject]@{ currency = 'USD'; unit = 'per_1m_tokens'; input = 1; output = 6; cache_read = 0.125 }
            context_length = 1000000
        }
        $n = ConvertTo-NormalizedModel $m
        $n.access_tier     | Should -Be 'paid'
        $n.pricing.input   | Should -Be 1
        $n.pricing.output  | Should -Be 6
        $n.context         | Should -Be 1000000
    }
}

Describe 'ConvertTo-NormalizedCatalog' {
    It 'sắp theo id và bỏ entry rác' {
        $raw = @(
            [pscustomobject]@{ id = 'b-model' },
            [pscustomobject]@{ object = 'list' },
            [pscustomobject]@{ id = 'a-model' }
        )
        $out = ConvertTo-NormalizedCatalog $raw
        @($out).Count   | Should -Be 2
        @($out)[0].id   | Should -Be 'a-model'
        @($out)[1].id   | Should -Be 'b-model'
    }
}

Describe 'Compare-ConfigSetToCatalog' {
    It 'liệt kê missing / near-match / new' {
        $cmp = Compare-ConfigSetToCatalog -ConfigIds @('a', 'b', 'c:free', 'x') -CatalogIds @('a', 'c', 'x-fresh')
        $cmp.Missing | Should -Be @('b', 'c:free', 'x')
        $cmp.Near['c:free'] | Should -Be 'c'
        $cmp.Near['b']      | Should -BeNullOrEmpty
        $cmp.New      | Should -Be @('x-fresh')
    }

    It 'không đếm near-match là missing nghiêm trọng (vẫn nằm trong Missing nhưng có Near)' {
        $cmp = Compare-ConfigSetToCatalog -ConfigIds @('z-ai/glm-5:free') -CatalogIds @('z-ai/glm-5')
        $cmp.Missing | Should -Be @('z-ai/glm-5:free')
        $cmp.Near['z-ai/glm-5:free'] | Should -Be 'z-ai/glm-5'
        $cmp.New | Should -BeNullOrEmpty
    }

    It 'khớp hoa/thường khi xét missing (id catalog trùng config dù khác case)' {
        $cmp = Compare-ConfigSetToCatalog -ConfigIds @('OpenAI/GPT-5') -CatalogIds @('openai/gpt-5', 'extension-x')
        $cmp.Missing | Should -BeNullOrEmpty
        $cmp.Near     | Should -BeNullOrEmpty
        $cmp.New      | Should -Be @('extension-x')
    }

    It 'strip tiền tố gateway (openrouter/) khi đối chiếu catalog live' {
        $cmp = Compare-ConfigSetToCatalog -ConfigIds @('openrouter/others/v1', 'openrouter/inclusionai/ling-3.0-flash-sante:free') `
            -CatalogIds @('inclusionai/ling-3.0-flash-sante:free', 'others/x') `
            -StripPrefixes @('openrouter/')
        # id 'openrouter/inclusionai/...' stripped -> khớp chính xác trong catalog → KHÔNG missing
        $cmp.Missing | Should -Be @('openrouter/others/v1')
        $cmp.Near | Should -BeNullOrEmpty
        $cmp.Similar['openrouter/others/v1'] | Should -Contain 'others/x'
        $cmp.New | Should -Be @('others/x')
    }

    It 'gợi ý các id cùng họ cho model thiếu (gần như đổi tên)' {
        $cmp = Compare-ConfigSetToCatalog -ConfigIds @('deepseek/deepseek-v4-pro') `
            -CatalogIds @('deepseek/deepseek-v4-pro-0813', 'deepseek/deepseek-v4-pro-max', 'other/model', 'deepseek/deepseek-v4.1-flash')
        $cmp.Missing | Should -Be @('deepseek/deepseek-v4-pro')
        $cmp.Near | Should -BeNullOrEmpty
        $cmp.Similar['deepseek/deepseek-v4-pro'] | Should -Contain 'deepseek/deepseek-v4-pro-0813'
        $cmp.Similar['deepseek/deepseek-v4-pro'] | Should -Contain 'deepseek/deepseek-v4-pro-max'
        $cmp.Similar['deepseek/deepseek-v4-pro'] | Should -Not -Contain 'other/model'
    }
}