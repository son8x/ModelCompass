#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test Export-ModelBank (Phase 3.3) — các hàm THUẦN:
  - Get-PricesFromName (giá trong name)
  - Get-ModelBankPricing (ưu tiên catalog, fallback name)
  - New-ModelBank (cấu trúc, pricing, tag preset, không lộ key)
Dot-source với -SkipRun (giữ pattern Compare-Prices.Tests).
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:sut = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'scripts\Export-ModelBank.ps1'
    . $script:sut -SkipRun

    $script:fakeConfigProvider = [pscustomobject]@{
        '1-xkiro-free' = [pscustomobject]@{
            name    = 'xKiro free'
            npm     = '@ai-sdk/openai-compatible'
            options = [pscustomobject]@{ baseURL = 'https://api.xkiro.com/v1'; apiKey = '{env:XTROUTER_API_KEY}' }
            models  = [pscustomobject]@{
                'gpt-5.6-sol' = [pscustomobject]@{ name = 'GPT-5.6 Sol | In:$1 | Out:$2'; release_date = '2099-12-31' }
            }
        }
        '3-omniroute-free' = [pscustomobject]@{
            name    = 'OmniRoute free'
            npm     = '@ai-sdk/openai-compatible'
            options = [pscustomobject]@{ baseURL = 'http://127.0.0.1:20217/v1'; apiKey = '{env:OMNIROUTE_KEY}' }
            models  = [pscustomobject]@{
                'mistral-nemo:free' = [pscustomobject]@{ name = 'Mistral Nemo'; release_date = '2099-12-30' }
            }
        }
    }
    $script:fakeCatalogs = @{
        xkiro = [pscustomobject]@{ models = @([pscustomobject]@{ id = 'gpt-5.6-sol'; pricing = [pscustomobject]@{ input = 0.2; output = 0.4 } }) }
    }
    $script:fakeRegistry = @(
        [pscustomobject]@{ Id = 'xkiro'; ConfigProviders = @('1-xkiro-free', '2-xkiro-max'); IdStripPrefix = @(); KeyEnv = 'XTROUTER_API_KEY' },
        [pscustomobject]@{ Id = 'omniroute'; ConfigProviders = @('3-omniroute-free'); IdStripPrefix = @(); KeyEnv = 'OMNIROUTE_KEY' }
    )
    $script:fakePresets = @(
        [pscustomobject]@{ Name = 'safe-minimal'; Path = 'configs/presets/safe-minimal.jsonc'; models = [pscustomobject]@{ '1-xkiro-free' = [pscustomobject]@{ models = [pscustomobject]@{ 'gpt-5.6-sol' = [pscustomobject]@{} } } } }
    )
}

Describe 'Get-PricesFromName' {
    It 'parse được giá In:$X | Out:$Y' {
        $p = Get-PricesFromName 'DeepSeek V3 | In:$0.27 | Out:$1.10'
        $p.In | Should -Be 0.27
        $p.Out | Should -Be 1.10
    }
    It 'name không giá → In/Out = $null' {
        $p = Get-PricesFromName 'Model free không giá'
        $p.In | Should -BeNullOrEmpty
        $p.Out | Should -BeNullOrEmpty
    }
    It 'rỗng → $null' {
        $p = Get-PricesFromName ''
        $p.In | Should -BeNullOrEmpty
    }
}

Describe 'Get-ModelBankPricing' {
    It 'catalog live được ưu tiên khi có' {
        $cat = @{ 'my-model' = [pscustomobject]@{ id = 'my-model'; pricing = [pscustomobject]@{ input = 0.5; output = 1.5 } } }
        $p = Get-ModelBankPricing -ModelId 'my-model' -Name 'My Model | In:$1 | Out:$2' -CatalogLookup $cat
        $p.catalogPricing.input | Should -Be 0.5
        $p.namePricing.input | Should -Be 1
    }
    It 'fallback giá từ name khi catalog không có' {
        $p = Get-ModelBankPricing -ModelId 'x' -Name 'M | In:$0.5 | Out:$1' -CatalogLookup $null
        $p.catalogPricing | Should -BeNullOrEmpty
        $p.namePricing.output | Should -Be 1
    }
    It 'strip tiền tố gateway khi tra catalog' {
        $cat = @{ 'real-id' = [pscustomobject]@{ id = 'real-id'; pricing = [pscustomobject]@{ input = 2; output = 4 } } }
        $p = Get-ModelBankPricing -ModelId 'openrouter/real-id' -Name 'X' -StripPrefixes @('openrouter/') -CatalogLookup $cat
        $p.catalogPricing.input | Should -Be 2
    }
}

Describe 'New-ModelBank' {
    $script:fakeConfigProvider = [pscustomobject]@{
        '1-xkiro-free' = [pscustomobject]@{
            name    = 'xKiro free'
            npm     = '@ai-sdk/openai-compatible'
            options = [pscustomobject]@{ baseURL = 'https://api.xkiro.com/v1'; apiKey = '{env:XTROUTER_API_KEY}' }
            models  = [pscustomobject]@{
                'gpt-5.6-sol' = [pscustomobject]@{ name = 'GPT-5.6 Sol | In:$1 | Out:$2'; release_date = '2099-12-31' }
            }
        }
        '3-omniroute-free' = [pscustomobject]@{
            name    = 'OmniRoute free'
            npm     = '@ai-sdk/openai-compatible'
            options = [pscustomobject]@{ baseURL = 'http://127.0.0.1:20217/v1'; apiKey = '{env:OMNIROUTE_KEY}' }
            models  = [pscustomobject]@{
                'mistral-nemo:free' = [pscustomobject]@{ name = 'Mistral Nemo'; release_date = '2099-12-30' }
            }
        }
    }
    $script:fakeCatalogs = @{
        xkiro = [pscustomobject]@{ models = @([pscustomobject]@{ id = 'gpt-5.6-sol'; pricing = [pscustomobject]@{ input = 0.2; output = 0.4 } }) }
    }
    $script:fakeRegistry = @(
        [pscustomobject]@{ Id = 'xkiro'; ConfigProviders = @('1-xkiro-free', '2-xkiro-max'); IdStripPrefix = @(); KeyEnv = 'XTROUTER_API_KEY' },
        [pscustomobject]@{ Id = 'omniroute'; ConfigProviders = @('3-omniroute-free'); IdStripPrefix = @(); KeyEnv = 'OMNIROUTE_KEY' }
    )
    $script:fakePresets = @(
        [pscustomobject]@{ Name = 'safe-minimal'; Path = 'configs/presets/safe-minimal.jsonc'; models = [pscustomobject]@{ '1-xkiro-free' = [pscustomobject]@{ models = [pscustomobject]@{ 'gpt-5.6-sol' = [pscustomobject]@{} } } } }
    )

    It 'xuất đủ providers/models/presets + stats' {
        $b = New-ModelBank -ConfigProvider $script:fakeConfigProvider -Catalogs $script:fakeCatalogs -PresetInfo $script:fakePresets -ProviderReg $script:fakeRegistry
        $b.providers.Count | Should -Be 2
        $b.models.Count | Should -Be 2
        $b.presets.Count | Should -Be 1
        $b.stats.providers | Should -Be 2
        $b.stats.models | Should -Be 2
        $b.version | Should -Be '1.0.0'
    }

    It 'provider local được đánh dấu local=true' {
        $b = New-ModelBank -ConfigProvider $script:fakeConfigProvider -Catalogs $script:fakeCatalogs -PresetInfo $script:fakePresets -ProviderReg $script:fakeRegistry
        @($b.providers | Where-Object id -eq '3-omniroute-free').local | Should -BeTrue
        @($b.providers | Where-Object id -eq '1-xkiro-free').local | Should -BeFalse
    }

    It 'apiKey của từng provider trích đúng tên biến' {
        $b = New-ModelBank -ConfigProvider $script:fakeConfigProvider -Catalogs $script:fakeCatalogs -PresetInfo $script:fakePresets -ProviderReg $script:fakeRegistry
        @($b.providers | Where-Object id -eq '1-xkiro-free').apiKeyEnv | Should -Be 'XTROUTER_API_KEY'
        @($b.providers | Where-Object id -eq '3-omniroute-free').apiKeyEnv | Should -Be 'OMNIROUTE_KEY'
    }

    It 'model có pricing từ catalog khi có; fallback từ name khi không' {
        $b = New-ModelBank -ConfigProvider $script:fakeConfigProvider -Catalogs $script:fakeCatalogs -PresetInfo $script:fakePresets -ProviderReg $script:fakeRegistry
        $m1 = @($b.models | Where-Object id -eq 'gpt-5.6-sol')
        $m1.catalogPricing.input | Should -Be 0.2
        $m1.pricing.input | Should -Be 1
        $m2 = @($b.models | Where-Object id -eq 'mistral-nemo:free')
        $m2.catalogPricing | Should -BeNullOrEmpty
        $m2.pricing | Should -BeNullOrEmpty
    }

    It 'model trong preset được gắn tag preset' {
        $b = New-ModelBank -ConfigProvider $script:fakeConfigProvider -Catalogs $script:fakeCatalogs -PresetInfo $script:fakePresets -ProviderReg $script:fakeRegistry
        $m = @($b.models | Where-Object { $_.id -eq 'gpt-5.6-sol' })
        @($m[0].tags) -contains 'preset:safe-minimal' | Should -BeTrue
        $m2 = @($b.models | Where-Object { $_.id -eq 'mistral-nemo:free' })
        @($m2[0].tags).Count | Should -Be 0
    }

    It 'schema model-bank/schema.json parse được' {
        $schema = Get-Content -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'model-bank\schema.json') -Raw | ConvertFrom-Json
        $schema.title | Should -Match 'Model Bank'
        @($schema.required) | Should -Contain 'models'
    }
}