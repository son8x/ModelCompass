#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test các hàm thuần của scripts/Update-XKiroModels.ps1
(đặt tên thân thiện từ id, xếp nhóm, so catalog, tính thứ tự, gán release_date,
edit JSONC giữ comment) — không gọi mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Update-XKiroModels.ps1') -SkipRun
}

Describe 'ConvertTo-FriendlyName' {
    It 'qwen free' {
        ConvertTo-FriendlyName 'qwen/qwen3.8-max:free' | Should -Be 'Qwen3.8 Max'
    }
    It 'deepseek pro' {
        ConvertTo-FriendlyName 'deepseek/deepseek-v4-pro' | Should -Be 'DeepSeek V4 Pro'
    }
    It 'anthropic claude' {
        ConvertTo-FriendlyName 'anthropic/claude-opus-5.5' | Should -Be 'Claude Opus 5.5'
    }
    It 'google gemini' {
        ConvertTo-FriendlyName 'google/gemini-3.8-flash' | Should -Be 'Gemini 3.8 Flash'
    }
    It 'openai gpt' {
        ConvertTo-FriendlyName 'openai/gpt-6-sol' | Should -Be 'GPT 6 Sol'
    }
    It 'z-ai glm' {
        ConvertTo-FriendlyName 'z-ai/glm-5.3' | Should -Be 'GLM 5.3'
    }
    It 'xiaomi mimo' {
        ConvertTo-FriendlyName 'xiaomi/mimo-v2.6-pro' | Should -Be 'MiMo V2.6 Pro'
    }
    It 'x-ai grok' {
        ConvertTo-FriendlyName 'x-ai/grok-4.7' | Should -Be 'Grok 4.7'
    }
    It 'minimax' {
        ConvertTo-FriendlyName 'minimax/minimax-m3:free' | Should -Be 'MiniMax M3'
    }
    It 'llama nemotron' {
        ConvertTo-FriendlyName 'nvidia/llama-3.3-nemotron-super-49b' | Should -Be 'Llama 3.3 Nemotron Super 49b'
    }
    It 'id không có slash' {
        ConvertTo-FriendlyName 'deepseek-chat' | Should -Be 'DeepSeek Chat'
    }
}

Describe 'Resolve-TierFromPrice' {
    It 'ngưỡng mặc định L dưới 0.5, B dưới 1.5, A dưới 4, S từ 4' {
        Resolve-TierFromPrice -InputPrice 0.08  | Should -Be 'L'
        Resolve-TierFromPrice -InputPrice 0.50  | Should -Be 'B'
        Resolve-TierFromPrice -InputPrice 1.49  | Should -Be 'B'
        Resolve-TierFromPrice -InputPrice 1.50  | Should -Be 'A'
        Resolve-TierFromPrice -InputPrice 3.99  | Should -Be 'A'
        Resolve-TierFromPrice -InputPrice 4.00  | Should -Be 'S'
    }
    It 'giá null -> L (rẻ nhất thực tế)' {
        Resolve-TierFromPrice -InputPrice $null | Should -Be 'L'
    }
    It 'ngưỡng tuỳ biến được' {
        Resolve-TierFromPrice -InputPrice 1.00 -L 0.5 -B 1.2 -A 3 | Should -Be 'B'
        Resolve-TierFromPrice -InputPrice 1.30 -L 0.5 -B 1.2 -A 3 | Should -Be 'A'
    }
}

Describe 'Resolve-TierFromName' {
    It 'trích tag [X]' {
        Resolve-TierFromName '[A] GPT-5.4 · $2.50/$15.00' | Should -Be 'A'
        Resolve-TierFromName '[S] Claude Opus 5' | Should -Be 'S'
    }
    It 'name free không có tag -> null' {
        Resolve-TierFromName 'Qwen3.8 Max · 1M' | Should -Be $null
    }
}

Describe 'New-ModelDisplayName' {
    It 'max ghi tier + giá + ctx' {
        $n = New-ModelDisplayName -FriendlyName 'GPT 6 Sol' -Tier 'S' -In 2 -Out 10 -Context 1050000
        $n | Should -Be '[S] GPT 6 Sol · $2.00/$10.00 · 1.1M'
    }
    It 'free không tier, không giá' {
        $n = New-ModelDisplayName -FriendlyName 'Qwen3.8 Max' -Context 1000000
        $n | Should -Be 'Qwen3.8 Max · 1M'
    }
    It 'giá lẻ 3 chữ số' {
        $n = New-ModelDisplayName -FriendlyName 'MiMo V2.6 Pro' -Tier 'B' -In 0.435 -Out 0.87 -Context 1000000
        $n | Should -Match ([regex]::Escape('$0.435/$0.87'))
    }
}

Describe 'Compare-ToLive' {
    BeforeEach {
        $cfg = @(
            [pscustomobject]@{ id = 'a/x'; name = '[L] A X'; release_date = '2099-10-31' },
            [pscustomobject]@{ id = 'b/y'; name = '[S] B Y'; release_date = '2099-09-01' }
        )
        $cat = @(
            [pscustomobject]@{ id = 'a/x'; pricing = [pscustomobject]@{ input = 0.1; output = 0.5 }; context = 1000000 },
            [pscustomobject]@{ id = 'b/y'; pricing = [pscustomobject]@{ input = 5; output = 25 }; context = 1000000 },
            [pscustomobject]@{ id = 'c/z'; pricing = [pscustomobject]@{ input = 2; output = 10 }; context = 500000 }
        )
        $probe = @{ 'a/x' = 'OK'; 'b/y' = 'OK'; 'c/z' = 'OK' }
    }

    It 'giữ model OK, thêm model mới probe OK, không gỡ ai' {
        $r = Compare-ToLive -ConfigModels $cfg -CatalogModels $cat -ProbeResults $probe
        $r.Keep.Count    | Should -Be 2
        $r.Add.Count     | Should -Be 1
        $r.Add[0].id     | Should -Be 'c/z'
        $r.Add[0].tier   | Should -Be 'A'
        $r.RemoveReason.Count | Should -Be 0
    }

    It 'max: gỡ model probe AUTH (403)' {
        $probe['b/y'] = 'AUTH'
        $r = Compare-ToLive -ConfigModels $cfg -CatalogModels $cat -ProbeResults $probe
        $r.RemoveReason['b/y'] | Should -Match '403'
        $r.Keep.Count | Should -Be 1
    }

    It 'max: gỡ model biến mất khỏi catalog' {
        $catOnly = @($cat | Where-Object { $_.id -ne 'b/y' })
        $r = Compare-ToLive -ConfigModels $cfg -CatalogModels $catOnly -ProbeResults $probe
        $r.RemoveReason['b/y'] | Should -Match 'biến mất'
    }

    It 'free: giữ cả model RATE/HTTP (lỗi tạm), chỉ gỡ NOTFOUND' {
        $cfgF = @(
            [pscustomobject]@{ id = 'a/x'; name = 'A X'; release_date = '2099-12-31' },
            [pscustomobject]@{ id = 'ghost/g'; name = 'G Ghost'; release_date = '2099-12-30' }
        )
        $catF = @(
            [pscustomobject]@{ id = 'a/x'; pricing = $null; context = $null },
            [pscustomobject]@{ id = 'ghost/g'; pricing = $null; context = $null }
        )
        $probeF = @{ 'a/x' = 'RATE'; 'ghost/g' = 'NOTFOUND' }
        $r = Compare-ToLive -ConfigModels $cfgF -CatalogModels $catF -ProbeResults $probeF -IsFree
        $r.Keep.Count | Should -Be 1
        $r.Keep[0].id | Should -Be 'a/x'
        $r.RemoveReason['ghost/g'] | Should -Match 'NOTFOUND'
    }

    It 'thêm model free không gán tier' {
        $cfgF = @([pscustomobject]@{ id = 'a/x'; name = 'A X'; release_date = '2099-12-31' })
        $catF = @(
            [pscustomobject]@{ id = 'a/x'; pricing = $null; context = $null },
            [pscustomobject]@{ id = 'q/q5:free'; pricing = $null; context = $null }
        )
        $probeF = @{ 'a/x' = 'OK'; 'q/q5:free' = 'OK' }
        $r = Compare-ToLive -ConfigModels $cfgF -CatalogModels $catF -ProbeResults $probeF -IsFree
        $r.Add[0].id | Should -Be 'q/q5:free'
        $r.Add[0].tier | Should -Be ''
    }

    It 'giữ model premium vẫn còn trong catalog đầy đủ, không gỡ oan' {
        $cfgM = @([pscustomobject]@{ id = 'google/gemini-3.8-flash'; name = '[S] Gemini 3.8 Flash'; release_date = '2099-09-04' })
        $catM = @(
            [pscustomobject]@{ id = 'google/gemini-3.8-flash'; access_tier = 'premium'; pricing = $null; context = $null },
            [pscustomobject]@{ id = 'openai/gpt-6-astra'; access_tier = 'paid'; pricing = [pscustomobject]@{ input = 10; output = 50 }; context = 1000000 }
        )
        $probeM = @{ 'google/gemini-3.8-flash' = 'OK'; 'openai/gpt-6-astra' = 'AUTH' }
        $r = Compare-ToLive -ConfigModels $cfgM -CatalogModels $catM -ProbeResults $probeM -TierFilter 'paid'
        $r.RemoveReason.Count | Should -Be 0
        $r.Keep.Count | Should -Be 1
        $r.Keep[0].id | Should -Be 'google/gemini-3.8-flash'
    }

    It 'TierFilter chỉ cho thêm model đúng tier, bỏ model khác tier' {
        $cfgM = @([pscustomobject]@{ id = 'a/x'; name = 'A X'; release_date = '2099-09-04' })
        $catM = @(
            [pscustomobject]@{ id = 'a/x'; access_tier = 'paid'; pricing = $null; context = $null },
            [pscustomobject]@{ id = 'new/paid-1'; access_tier = 'paid'; pricing = [pscustomobject]@{ input = 1; output = 4 }; context = 1000000 },
            [pscustomobject]@{ id = 'new/prem-1'; access_tier = 'premium'; pricing = $null; context = $null }
        )
        $probeM = @{ 'a/x' = 'OK'; 'new/paid-1' = 'OK'; 'new/prem-1' = 'OK' }
        $r = Compare-ToLive -ConfigModels $cfgM -CatalogModels $catM -ProbeResults $probeM -TierFilter 'paid'
        $r.Add.Count | Should -Be 1
        $r.Add[0].id | Should -Be 'new/paid-1'
    }
}

Describe 'Compute-OrderedModels' {
    It 'giữ thứ tự model cũ, model max mới chèn sau cùng nhóm' {
        $cfg = @(
            [pscustomobject]@{ id = 'a/L1'; name = '[L] A1'; release_date = '2099-10-31' },
            [pscustomobject]@{ id = 'b/L2'; name = '[L] B2'; release_date = '2099-10-30' },
            [pscustomobject]@{ id = 'c/S1'; name = '[S] C1'; release_date = '2099-09-01' }
        )
        $cmp = [pscustomobject]@{
            Keep = @(
                [pscustomobject]@{ id = 'a/L1'; name = '[L] A1'; release_date = '2099-10-31'; CatIn = 0.1; CatOut = 0.5; Context = 0 },
                [pscustomobject]@{ id = 'b/L2'; name = '[L] B2'; release_date = '2099-10-30'; CatIn = 0.1; CatOut = 0.5; Context = 0 },
                [pscustomobject]@{ id = 'c/S1'; name = '[S] C1'; release_date = '2099-09-01'; CatIn = 5; CatOut = 25; Context = 0 }
            )
            Add = @([pscustomobject]@{ id = 'd/S2'; friendly = 'D2'; tier = 'S'; in = 6; out = 30; context = 0 })
            RemoveReason = @{}
        }
        $o = Compute-OrderedModels -ConfigModels $cfg -Compare $cmp
        $ids = @($o.Ordered | ForEach-Object { $_.id })
        $ids | Should -Be @('a/L1', 'b/L2', 'c/S1', 'd/S2')
        $o.Ordered[-1].name | Should -Match '^\[S\]'
    }

    It 'cập nhật giá khi catalog đổi, giữ phần mô tả' {
        $cfg = @([pscustomobject]@{ id = 'a/L1'; name = '[L] A1 · $0.10/$0.50'; release_date = '2099-10-31' })
        $cmp = [pscustomobject]@{
            Keep = @([pscustomobject]@{ id = 'a/L1'; name = '[L] A1 · $0.10/$0.50'; release_date = '2099-10-31'; CatIn = 0.2; CatOut = 1.0; Context = 0 })
            Add = @()
            RemoveReason = @{}
        }
        $o = Compute-OrderedModels -ConfigModels $cfg -Compare $cmp
        $o.Ordered[0].name | Should -Be '[L] A1 · $0.20/$1.00'
        $o.ChangedPrice.Count | Should -Be 1
    }

    It 'free: model mới thêm cuối, không tag nhóm' {
        $cfg = @([pscustomobject]@{ id = 'a/A'; name = 'A AA'; release_date = '2099-12-31' })
        $cmp = [pscustomobject]@{
            Keep = @([pscustomobject]@{ id = 'a/A'; name = 'A AA'; release_date = '2099-12-31'; CatIn = $null; CatOut = $null; Context = 0 })
            Add = @([pscustomobject]@{ id = 'b/B'; friendly = 'B BB'; tier = ''; in = $null; out = $null; context = 1000000 })
            RemoveReason = @{}
        }
        $o = Compute-OrderedModels -ConfigModels $cfg -Compare $cmp -IsFree
        $ids = @($o.Ordered | ForEach-Object { $_.id })
        $ids | Should -Be @('a/A', 'b/B')
        $o.Ordered[1].name | Should -Be 'B BB · 1M'
    }
}

Describe 'Assign-ReleaseDates' {
    It 'giữ nguyên date model cũ, sinh date model mới giữa 2 date kề' {
        $ordered = @(
            [pscustomobject]@{ id = 'a'; name = 'A'; tier = '' },
            [pscustomobject]@{ id = 'n1'; name = 'NEW'; tier = '' },
            [pscustomobject]@{ id = 'c'; name = 'C'; tier = '' }
        )
        $cfg = @(
            [pscustomobject]@{ id = 'a'; name = 'A'; release_date = '2099-12-31' },
            [pscustomobject]@{ id = 'c'; name = 'C'; release_date = '2099-12-29' }
        )
        $f = Assign-ReleaseDates -Ordered $ordered -ConfigModels $cfg
        $f[0].release_date | Should -Be '2099-12-31'
        $f[2].release_date | Should -Be '2099-12-29'
        [datetime]::ParseExact($f[1].release_date, 'yyyy-MM-dd', [cultureinfo]'en-US') |
            Should -Be ([datetime]'2099-12-30')
    }

    It 'model mới cuối dãy (không có lower) -> sinh date dưới upper' {
        $ordered = @(
            [pscustomobject]@{ id = 'a'; name = 'A'; tier = '' },
            [pscustomobject]@{ id = 'n'; name = 'NEW'; tier = '' }
        )
        $cfg = @([pscustomobject]@{ id = 'a'; name = 'A'; release_date = '2099-11-20' })
        $f = Assign-ReleaseDates -Ordered $ordered -ConfigModels $cfg
        $f[1].release_date | Should -Be '2099-11-19'
    }

    It 'không vỡ khi upper/lower kề sát nhau (fallback không throw)' {
        $ordered = @(
            [pscustomobject]@{ id = 'a'; name = 'A'; tier = '' },
            [pscustomobject]@{ id = 'n'; name = 'NEW'; tier = '' },
            [pscustomobject]@{ id = 'b'; name = 'B'; tier = '' }
        )
        $cfg = @(
            [pscustomobject]@{ id = 'a'; name = 'A'; release_date = '2099-10-11' },
            [pscustomobject]@{ id = 'b'; name = 'B'; release_date = '2099-10-10' }
        )
        $f = Assign-ReleaseDates -Ordered $ordered -ConfigModels $cfg
        $f[1].release_date | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-ProviderModelsBlock' {
    It 'thay model trong block, giữ comment header + comment nhóm' {
        $raw = @'
{
  "provider": {
    "2-xkiro-max": {
      "models": {
        //  Header giữ nguyên.
        // ── [L] Nhẹ ──
        "a/l1": { "name": "[L] A1", "release_date": "2099-10-31" },
        "a/l2": { "name": "[L] A2", "release_date": "2099-10-30" },
        // ── [S] Flagship ──
        "s/s1": { "name": "[S] S1", "release_date": "2099-09-01" }
      }
    }
  }
}
'@
        $newModels = @(
            [pscustomobject]@{ id = 'a/l1'; name = '[L] A1'; release_date = '2099-10-31'; tier = 'L' },
            [pscustomobject]@{ id = 'a/new'; name = '[L] New'; release_date = '2099-10-20'; tier = 'L' },
            [pscustomobject]@{ id = 'a/l2'; name = '[L] A2'; release_date = '2099-10-30'; tier = 'L' },
            [pscustomobject]@{ id = 's/s1'; name = '[S] S1'; release_date = '2099-09-01'; tier = 'S' }
        )
        $out = Set-ProviderModelsBlock -Raw $raw -ProviderKey '2-xkiro-max' -Models $newModels
        $out | Should -Match 'Header giữ nguyên'
        $out | Should -Match '// ── \[L\] Nhẹ ──'
        $out | Should -Match '// ── \[S\] Flagship ──'
        $out | Should -Match '"a/new":'
        $out | Should -Not -Match 'a/secret'

        # Kết quả vẫn là JSON hợp lệ sau khi bỏ comment.
        $clean = Remove-CommentsAndTrailingCommas $out
        $parsed = $clean | ConvertFrom-Json
        $parsed.provider.'2-xkiro-max'.models.'a/new'.name | Should -Be '[L] New'
    }

    It 'block free không có comment nhóm — sinh mỗi model 1 dòng' {
        $raw = @'
{
  "provider": {
    "1-xkiro-free": {
      "models": {
        "a/x": { "name": "A X", "release_date": "2099-12-31" }
      }
    }
  }
}
'@
        $newModels = @(
            [pscustomobject]@{ id = 'a/x'; name = 'A X'; release_date = '2099-12-31'; tier = '' },
            [pscustomobject]@{ id = 'b/y'; name = 'B Y'; release_date = '2099-12-30'; tier = '' }
        )
        $out = Set-ProviderModelsBlock -Raw $raw -ProviderKey '1-xkiro-free' -Models $newModels
        $clean = Remove-CommentsAndTrailingCommas $out
        $parsed = $clean | ConvertFrom-Json
        $parsed.provider.'1-xkiro-free'.models.PSObject.Properties.Name.Count | Should -Be 2
    }

    It 'throw khi không tìm thấy provider' {
        { Set-ProviderModelsBlock -Raw '{}' -ProviderKey '2-xkiro-max' -Models @() } |
            Should -Throw -ErrorId "Không tìm thấy provider '2-xkiro-max' trong config."
    }
}