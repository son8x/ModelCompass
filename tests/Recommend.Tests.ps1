#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test các hàm thuần của bộ đề xuất ⭐ xKiro (3 tầng)
  - scripts/recommend/Get-ModelCandidates.ps1 (tầng 1: ứng viên + nhóm)
  - scripts/recommend/Resolve-StarRules.ps1   (tầng 2: tag, chọn ⭐, ⭐ name)
  - scripts/recommend/New-RecommendReport.ps1 (tầng 3: diff) — kèm tích hợp baseline 13 ⭐.
Không gọi mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $sc = Join-Path $PSScriptRoot '..\scripts'
    . (Join-Path $sc 'Common-Functions.ps1')
    . (Join-Path $sc 'provider\Update-XKiroModels.ps1') -SkipRun
    . (Join-Path $sc 'recommend\Get-ModelCandidates.ps1')
    . (Join-Path $sc 'recommend\Resolve-StarRules.ps1')
    . (Join-Path $sc 'recommend\New-RecommendReport.ps1') -SkipRun
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ConfigPath = Join-Path $script:RepoRoot 'configs\development\opencode.jsonc'
    $script:CatalogPath = Join-Path $script:RepoRoot 'docs\catalogs\xkiro.json'
    $script:CapPath = Join-Path $script:RepoRoot 'scripts\recommend\model-capabilities.json'
}

Describe 'Read-ModelCapabilities' {
    It 'đọc được unsupported + preferred + tags từ file thật' {
        $cap = Read-ModelCapabilities -Path $script:CapPath
        $cap.Unsupported | Should -Contain 'image-gen'
        $cap.Unsupported | Should -Contain 'embedding'
        $cap.Preferred['reasoning']['free'] | Should -Be 'qwen/qwen3.8-max:free'
        $cap.Preferred['flagship']['paid'] | Should -Be 'openai/gpt-6.1-sol'
    }
    It 'file không tồn tại -> cấu trúc rỗng' {
        $cap = Read-ModelCapabilities -Path (Join-Path $TestDrive 'khong-ton-tai.json')
        @($cap.Unsupported).Count | Should -Be 0
        $cap.Preferred.Count | Should -Be 0
        $cap.Tags.Count | Should -Be 0
    }
    It 'path rỗng -> cấu trúc rỗng' {
        $cap = Read-ModelCapabilities -Path ''
        $cap.Preferred.Count | Should -Be 0
    }
}

Describe 'Get-ModelCapability (suy tag heuristic)' {
    It 'coder -> code' {
        (Get-ModelCapability -ModelId 'qwen/qwen3-coder-plus:free') | Should -Contain 'code'
    }
    It 'vl -> vision' {
        (Get-ModelCapability -ModelId 'qwen/qwen3-vl-plus:free') | Should -Contain 'vision'
    }
    It 'omni -> omni' {
        (Get-ModelCapability -ModelId 'qwen/qwen3.8-omni-flash:free') | Should -Contain 'omni'
    }
    It 'flash -> fast' {
        (Get-ModelCapability -ModelId 'z-ai/glm-5.3-flash') | Should -Contain 'fast'
    }
    It 'translate (id)' {
        (Get-ModelCapability -ModelId 'cohere/command-a-translate') | Should -Contain 'translate'
    }
    It 'dịch theo tên tiếng Việt' {
        (Get-ModelCapability -ModelId 'x/y' -Name 'Model · 9K · dịch') | Should -Contain 'translate'
    }
    It 'opus -> flagship' {
        (Get-ModelCapability -ModelId 'anthropic/claude-opus-5') | Should -Contain 'flagship'
    }
    It 'reasoning (tên)' {
        (Get-ModelCapability -ModelId 'qwen/qwen3.8-max:free' -Name 'Qwen3.8 Max · reasoning (mặc định)') | Should -Contain 'reasoning'
    }
    It 'nghiên cứu -> analysis' {
        (Get-ModelCapability -ModelId 'x/y' -Name 'X · nghiên cứu') | Should -Contain 'analysis'
    }
    It 'viết lách -> writing' {
        (Get-ModelCapability -ModelId 'x/y' -Name 'X · viết lách/agent') | Should -Contain 'writing'
    }
    It 'bulk trong tên' {
        (Get-ModelCapability -ModelId 'z-ai/glm-5.2' -Name '[B] GLM-5.2 · bulk') | Should -Contain 'bulk'
    }
    It 'hợp nhất tag từ bảng tra' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{}; Tags = @{ 'x/y' = @('omni', 'vision') } }
        $tags = Get-ModelCapability -ModelId 'x/y' -Capabilities $caps
        $tags | Should -Contain 'omni'
        $tags | Should -Contain 'vision'
    }
}

Describe 'Get-RecommendationConfigModels' {
    It 'đọc model của provider được chọn' {
        $cfg = @'
{ "provider": {
  "1-xkiro-free": { "models": { "a/one:free": { "name": "One", "release_date": "2099-01-01" } } },
  "2-xkiro-max":  { "models": { "b/two": { "name": "[L] Two", "release_date": "2099-01-02" } } },
  "3-omniroute-free": { "models": { "c/three": { "name": "Three" } } }
} }
'@ | ConvertFrom-Json
        $ms = Get-RecommendationConfigModels -ConfigObj $cfg -ProviderKeys @('1-xkiro-free', '2-xkiro-max')
        @($ms).Count | Should -Be 2
        @($ms | Where-Object { $_.Provider -eq '1-xkiro-free' }).Count | Should -Be 1
        @($ms | Where-Object { $_.Id -eq 'b/two' }).Count | Should -Be 1
    }
    It 'bỏ qua model của provider không chọn' {
        $cfg = @'
{ "provider": { "3-omniroute-free": { "models": { "c/three": { "name": "Three" } } } } }
'@ | ConvertFrom-Json
        @(Get-RecommendationConfigModels -ConfigObj $cfg -ProviderKeys @('1-xkiro-free')).Count | Should -Be 0
    }
}

Describe 'New-RecommendationCandidate (ghép catalog + xếp nhóm)' {
    BeforeEach {
        $script:CatalogById = @{
            'qwen/qwen3.8-max:free' = [pscustomobject]@{ context = 1000000; pricing = [pscustomobject]@{ input = 0.0; output = 0.0 } }
            'z-ai/glm-5.3-flash'    = [pscustomobject]@{ context = 1000000; pricing = [pscustomobject]@{ input = 0.15; output = 0.50 } }
            'weird/mystery'         = [pscustomobject]@{ context = 500000;  pricing = [pscustomobject]@{ input = 2.00; output = 6.00 } }
        }
        $script:Caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{}; Tags = @{} }
    }
    It 'free provider -> nhóm free' {
        $cm = [pscustomobject]@{ Id = 'qwen/qwen3.8-max:free'; Name = 'Qwen3.8 Max'; Provider = '1-xkiro-free'; ReleaseDate = '2099-12-31' }
        $c = New-RecommendationCandidate -ConfigModels @($cm) -CatalogById $script:CatalogById
        $c[0].Group | Should -Be 'free'
        $c[0].Context | Should -Be 1000000
    }
    It 'max có tag [L] -> nhóm L' {
        $cm = [pscustomobject]@{ Id = 'z-ai/glm-5.3-flash'; Name = '[L] GLM-5.3 Flash'; Provider = '2-xkiro-max'; ReleaseDate = '2099-01-01' }
        (New-RecommendationCandidate -ConfigModels @($cm) -CatalogById $script:CatalogById)[0].Group | Should -Be 'L'
    }
    It 'max KHÔNG tag -> xếp theo giá input (2.0 -> A)' {
        $cm = [pscustomobject]@{ Id = 'weird/mystery'; Name = 'Mystery'; Provider = '2-xkiro-max'; ReleaseDate = '2099-01-01' }
        (New-RecommendationCandidate -ConfigModels @($cm) -CatalogById $script:CatalogById)[0].Group | Should -Be 'A'
    }
    It 'max thiếu catalog -> nhóm L (mặc định)' {
        $cm = [pscustomobject]@{ Id = 'ghost/model'; Name = 'Ghost'; Provider = '2-xkiro-max'; ReleaseDate = '2099-01-01' }
        (New-RecommendationCandidate -ConfigModels @($cm) -CatalogById $script:CatalogById)[0].Group | Should -Be 'L'
    }
    It 'candidate KHÔNG tự gán tag (tag thuộc tầng 2)' {
        $cm = [pscustomobject]@{ Id = 'qwen/qwen3-coder-plus:free'; Name = 'Qwen3 Coder Plus'; Provider = '1-xkiro-free'; ReleaseDate = '2099-12-31' }
        $c = (New-RecommendationCandidate -ConfigModels @($cm) -CatalogById $script:CatalogById)[0]
        $c.PSObject.Properties['Tags'] | Should -BeNullOrEmpty
    }
}

Describe 'Get-CatalogById' {
    It 'đánh index theo id' {
        $byId = Get-CatalogById -CatalogModels @(
            [pscustomobject]@{ id = 'a/one'; context = 100 },
            [pscustomobject]@{ id = 'b/two'; context = 200 }
        )
        $byId.Count | Should -Be 2
        $byId['b/two'].context | Should -Be 200
    }
}

Describe 'Select-RecommendedCandidate' {
    BeforeEach {
        $script:Pool = @(
            [pscustomobject]@{ Id = 'old-cheap'; ReleaseDate = '2099-01-01'; In = 0.10; Context = 100000 },
            [pscustomobject]@{ Id = 'new-pricey'; ReleaseDate = '2099-12-01'; In = 3.00; Context = 200000 },
            [pscustomobject]@{ Id = 'new-cheap'; ReleaseDate = '2099-12-01'; In = 0.20; Context = 500000 }
        )
    }
    It 'top = release_date mới nhất, cùng ngày thì giá rẻ hơn thắng' {
        (Select-RecommendedCandidate -Pool $script:Pool -Order 'top').Id | Should -Be 'new-cheap'
    }
    It 'cheap = giá input rẻ nhất' {
        (Select-RecommendedCandidate -Pool $script:Pool -Order 'cheap').Id | Should -Be 'old-cheap'
    }
    It 'ctx = context lớn nhất' {
        (Select-RecommendedCandidate -Pool $script:Pool -Order 'ctx').Id | Should -Be 'new-cheap'
    }
    It 'pool rỗng -> $null' {
        Select-RecommendedCandidate -Pool @() -Order 'top' | Should -Be $null
    }
}

Describe 'Resolve-StarRecommendation + Merge-Recommendation' {
    BeforeEach {
        $script:Caps = [pscustomobject]@{
            Unsupported = @()
            Preferred   = @{ 'code' = @{ 'paid' = 'x-ai/grok-4.7' } }
            Tags        = @{}
        }
        $script:Candidates = @(
            [pscustomobject]@{ Id = 'qwen/qwen3-coder-plus:free'; Name = 'Qwen3 Coder Plus'; Provider = '1-xkiro-free'; Group = 'free'; ReleaseDate = '2099-12-31'; Context = 1000000; In = $null; Out = $null; Tags = @('code') }
            [pscustomobject]@{ Id = 'x-ai/grok-4.7';             Name = '[A] Grok 4.7';     Provider = '2-xkiro-max';  Group = 'A';    ReleaseDate = '2099-12-31'; Context = 500000;  In = 2.0;  Out = 6.0;  Tags = @('code') }
            [pscustomobject]@{ Id = 'other/coder';               Name = 'Other Coder';       Provider = '2-xkiro-max';  Group = 'L';    ReleaseDate = '2099-06-01'; Context = 200000;  In = 0.4;  Out = 1.0;  Tags = @('code') }
        )
        $script:Rows = Resolve-StarRecommendation -Candidates $script:Candidates -Capabilities $script:Caps
    }
    It 'preferred thắng rule cho code/paid (grok)' {
        $r = @($script:Rows | Where-Object { $_.Kind -eq 'purpose' -and $_.Key -eq 'code' -and $_.Scope -eq 'paid' })[0]
        $r.ModelId | Should -Be 'x-ai/grok-4.7'
        $r.Source  | Should -Be 'table'
    }
    It 'code/free chọn theo rule (coder)' {
        $r = @($script:Rows | Where-Object { $_.Kind -eq 'purpose' -and $_.Key -eq 'code' -and $_.Scope -eq 'free' })[0]
        $r.ModelId | Should -Be 'qwen/qwen3-coder-plus:free'
        $r.Source  | Should -Be 'rule'
    }
    It 'có dòng theo nhóm khi mục đích đặc trưng có ứng viên' {
        $cands = @(
            [pscustomobject]@{ Id = 'free/reason';   Name = 'Reason'; Provider = '1-xkiro-free'; Group = 'free'; ReleaseDate = '2099-01-01'; Context = 1000; In = $null; Out = $null; Tags = @('reasoning') }
            [pscustomobject]@{ Id = 'max/analysis';  Name = 'An';     Provider = '2-xkiro-max';  Group = 'A';    ReleaseDate = '2099-01-01'; Context = 1000; In = 2.0;   Out = 8.0;   Tags = @('analysis') }
        )
        $rows = Resolve-StarRecommendation -Candidates $cands -Capabilities $script:Caps
        $groupKeys = @($rows | Where-Object { $_.Kind -eq 'group' } | ForEach-Object { $_.Key })
        $groupKeys | Should -Contain 'free'
        $groupKeys | Should -Contain 'A'
    }
    It 'Merge khoá theo provider|id' {
        $map = Merge-Recommendation -Rows $script:Rows
        $map.ContainsKey('2-xkiro-max|x-ai/grok-4.7') | Should -Be $true
        $map.ContainsKey('1-xkiro-free|qwen/qwen3-coder-plus:free') | Should -Be $true
    }
    It 'preferred trỏ model đã biến mất -> fallback về rule' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{ 'code' = @{ 'paid' = 'da/bien-mat' } }; Tags = @{} }
        $rows = Resolve-StarRecommendation -Candidates $script:Candidates -Capabilities $caps
        $r = @($rows | Where-Object { $_.Kind -eq 'purpose' -and $_.Key -eq 'code' -and $_.Scope -eq 'paid' })[0]
        $r.Source | Should -Be 'rule'
        $r.ModelId | Should -Not -Be 'da/bien-mat'
    }
}

Describe 'Khoá đề xuất tách theo provider (cùng id ở free + max)' {
    It 'merge + diff không gán ⭐ cho bản trùng id ở provider khác' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{ 'lecture' = @{ 'free' = 'mistralai/mistral-large-4-0' } }; Tags = @{} }
        $cands = @(
            [pscustomobject]@{ Id = 'mistralai/mistral-large-4-0'; Name = '⭐ Mistral Large 4'; Provider = '1-xkiro-free'; Group = 'free'; ReleaseDate = '2099-12-31'; Context = 524300; In = $null; Out = $null; Tags = @('bulk') }
            [pscustomobject]@{ Id = 'mistralai/mistral-large-4-0'; Name = 'Mistral Large 4';     Provider = '2-xkiro-max';  Group = 'A';    ReleaseDate = '2099-12-31'; Context = 524300; In = 2.0;   Out = 8.0;  Tags = @() }
        )
        $rows = Resolve-StarRecommendation -Candidates $cands -Capabilities $caps
        $map = Merge-Recommendation -Rows $rows
        $map.ContainsKey('1-xkiro-free|mistralai/mistral-large-4-0') | Should -Be $true
        $map.ContainsKey('2-xkiro-max|mistralai/mistral-large-4-0')  | Should -Be $false

        $cfgModels = @(
            [pscustomobject]@{ Id = 'mistralai/mistral-large-4-0'; Name = '⭐ Mistral Large 4'; Provider = '1-xkiro-free' }
            [pscustomobject]@{ Id = 'mistralai/mistral-large-4-0'; Name = 'Mistral Large 4';     Provider = '2-xkiro-max' }
        )
        $diffs = Compare-RecommendationToConfig -ConfigModels $cfgModels -RecommendationMap $map
        $max = @($diffs | Where-Object { $_.Provider -eq '2-xkiro-max' })
        $max.Count | Should -Be 0
    }
}

Describe 'Test/Remove/Set-StarInName' {
    It 'phát hiện ⭐ ở đầu' {
        (Test-ModelHasStar '⭐ Foo') | Should -BeTrue
        (Test-ModelHasStar 'Foo ⭐') | Should -BeFalse
        (Test-ModelHasStar ' Foo') | Should -BeFalse
    }
    It 'gỡ ⭐ (giữ phần còn lại)' {
        Remove-StarInName '⭐ [A] Grok 4.7 · code' | Should -Be '[A] Grok 4.7 · code'
        Remove-StarInName 'No star' | Should -Be 'No star'
    }
    It 'gắn ⭐ không nhân đôi' {
        Set-StarInName '[B] GLM-5.2' | Should -Be '⭐ [B] GLM-5.2'
        Set-StarInName '⭐ [B] GLM-5.2' | Should -Be '⭐ [B] GLM-5.2'
    }
}

Describe 'Compare-RecommendationToConfig' {
    It 'phân loại THÊM / GỠ / giữ' {
        $map = @{ '1-xkiro-free|need/star' = [pscustomobject]@{ Purposes = @(); Groups = @() } }
        $cfgs = @(
            [pscustomobject]@{ Id = 'need/star'; Name = 'No star';    Provider = '1-xkiro-free' },
            [pscustomobject]@{ Id = 'have/star'; Name = '⭐ Starred'; Provider = '1-xkiro-free' }
        )
        $diffs = Compare-RecommendationToConfig -ConfigModels $cfgs -RecommendationMap $map
        @($diffs | Where-Object { $_.Action -eq 'THÊM ⭐' }).Count | Should -Be 1
        @($diffs | Where-Object { $_.Action -eq 'GỠ ⭐' }).Count   | Should -Be 1
        @($diffs | Where-Object { $_.Id -eq 'need/star' })[0].Action | Should -Be 'THÊM ⭐'
        @($diffs | Where-Object { $_.Id -eq 'have/star' })[0].Action | Should -Be 'GỠ ⭐'
    }
    It 'model không star + không đề xuất -> bỏ qua' {
        $cfgs = @([pscustomobject]@{ Id = 'x/y'; Name = 'X'; Provider = '1-xkiro-free' })
        @(Compare-RecommendationToConfig -ConfigModels $cfgs -RecommendationMap @{}).Count | Should -Be 0
    }
}

Describe 'Orchestrator tầng 1 & 2' {
    It 'Get-ModelCandidates (tầng 1) trả bundle { CatalogById; ConfigModels; Candidates } + nhóm' {
        $cfg = @'
{ "provider": { "1-xkiro-free": { "models": { "a/b:free": { "name": "B", "release_date": "2099-01-01" } } } } }
'@ | ConvertFrom-Json
        $catalog = @([pscustomobject]@{ id = 'a/b:free'; context = 1000; pricing = [pscustomobject]@{ input = 0.0; output = 0.0 } })
        $bundle = Get-ModelCandidates -ConfigObj $cfg -CatalogModels $catalog -ProviderKeys @('1-xkiro-free')
        @($bundle.Candidates).Count | Should -Be 1
        $bundle.Candidates[0].Group | Should -Be 'free'
        $bundle.CatalogById.ContainsKey('a/b:free') | Should -Be $true
    }
    It 'Resolve-StarRules (tầng 2) trả { Rows; Map }' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{ 'reasoning' = @{ 'free' = 'free/reason' } }; Tags = @{} }
        $cands = @([pscustomobject]@{ Id = 'free/reason'; Name = 'R'; Provider = '1-xkiro-free'; Group = 'free'; ReleaseDate = '2099-01-01'; Context = 1000; In = $null; Out = $null })
        $res = Resolve-StarRules -Candidates $cands -Capabilities $caps
        @($res.Rows | Where-Object { $_.Kind -eq 'purpose' -and $_.Key -eq 'reasoning' }).Count | Should -Be 1
        $res.Map.ContainsKey('1-xkiro-free|free/reason') | Should -Be $true
    }
    It 'Get-CandidateEffectiveTags: dùng .Tags nếu có, ngược lại suy từ tên' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{}; Tags = @{} }
        $withTags = [pscustomobject]@{ Id = 'x/y'; Name = 'Y'; Tags = @('omni') }
        (Get-CandidateEffectiveTags $withTags $caps) | Should -Contain 'omni'
        $noTags = [pscustomobject]@{ Id = 'qwen/qwen3-coder-plus:free'; Name = 'Coder' }
        (Get-CandidateEffectiveTags $noTags $caps) | Should -Contain 'code'
    }
}

Describe 'New-RecommendReportLines (markdown thuần)' {
    It 'sinh tiêu đề + 3 mục; THÊM/GỠ đúng' {
        $caps = [pscustomobject]@{ Unsupported = @('audio'); Preferred = @{}; Tags = @{} }
        $rows = @(
            [pscustomobject]@{ Kind = 'group'; Key = 'free'; Scope = 'free'; ModelId = 'a/b:free'; Source = 'table'; Candidate = [pscustomobject]@{ Id = 'a/b:free'; Group = 'free'; In = $null } }
        )
        $lines = New-RecommendReportLines -ConfigPath 'C:\x\cfg.jsonc' -Capabilities $caps -Rows $rows -Adds @([pscustomobject]@{ Id = 'x/y' }) -Drops @() -Date '2026-01-01 00:00:00'
        $txt = ($lines -join "`n")
        $txt | Should -Match '# ModelCompass'
        $txt | Should -Match 'Ngày: 2026-01-01 00:00:00'
        $txt | Should -Match 'audio'
        $txt | Should -Match '## ⭐ Theo nhóm'
        $txt | Should -Match '\*\*THÊM ⭐:\*\* `x/y`'
        $txt | Should -Match 'a/b:free'
    }
    It 'không có thay đổi → ghi dòng "Không thay đổi"' {
        $caps = [pscustomobject]@{ Unsupported = @(); Preferred = @{}; Tags = @{} }
        $lines = New-RecommendReportLines -ConfigPath 'c' -Capabilities $caps -Rows @() -Adds @() -Drops @() -Date 'x'
        ($lines -join "`n") | Should -Match 'Không thay đổi'
    }
}

Describe 'Tích hợp: tái tạo baseline 13 ⭐' {
    BeforeAll {
        $caps = Read-ModelCapabilities -Path $script:CapPath
        $cfg = Get-ConfigContent $script:ConfigPath
        $catalog = (Get-Content -LiteralPath $script:CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json).models
        $catalogById = Get-CatalogById -CatalogModels $catalog
        $cfgModels = Get-RecommendationConfigModels -ConfigObj $cfg -ProviderKeys @('1-xkiro-free', '2-xkiro-max')
        $cands = New-RecommendationCandidate -ConfigModels $cfgModels -CatalogById $catalogById
        $rows = Resolve-StarRecommendation -Candidates $cands -Capabilities $caps
        $script:Map = Merge-Recommendation -Rows $rows
        $script:Diffs = Compare-RecommendationToConfig -ConfigModels $cfgModels -RecommendationMap $script:Map
    }
    It 'có 13 model được gắn ⭐ theo đề xuất (7 free + 6 max)' {
        @($script:Map.Keys).Count | Should -Be 13
        @($script:Map.Keys | Where-Object { $_ -like '1-xkiro-free|*' }).Count | Should -Be 7
        @($script:Map.Keys | Where-Object { $_ -like '2-xkiro-max|*' }).Count | Should -Be 6
    }
    It 'KHÔNG có model nào cần THÊM ⭐' {
        @($script:Diffs | Where-Object { $_.Action -eq 'THÊM ⭐' }).Count | Should -Be 0
    }
    It 'KHÔNG có model nào cần GỠ ⭐' {
        @($script:Diffs | Where-Object { $_.Action -eq 'GỠ ⭐' }).Count | Should -Be 0
    }
    It 'tất cả đều là "giữ"' {
        @($script:Diffs | Where-Object { $_.Action -eq 'giữ' }).Count | Should -Be 13
    }
}

Describe 'Update-StarInConfigRaw (Pha 2 — ghi ⭐)' {
    BeforeAll {
        $script:Raw = @"
{
  "provider": {
    "1-xkiro-free": {
      "name": "Free",
      "models": {
        "a/one:free": { "name": "One · 1M", "release_date": "2099-01-01" },
        "a/two:free": { "name": "⭐ Two · 1M", "release_date": "2099-01-01" }
      }
    },
    "2-xkiro-max": {
      "models": {
        "a/one:free": { "name": "⭐ One paid", "release_date": "2099-01-01" },
        "a/three": { "name": "[L] Three", "release_date": "2099-01-01" }
      }
    }
  }
}
"@
    }
    It 'gắn ⭐ vào name của model (giữ phần còn lại)' {
        $out = Update-StarInConfigRaw -Raw $script:Raw -Targets @([pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/one:free'; Star = $true })
        $out | Should -Match '"a/one:free": \{ "name": "⭐ One · 1M"'
        $out | Should -Match '"a/two:free": \{ "name": "⭐ Two · 1M"'
    }
    It 'gỡ ⭐ khỏi name của model' {
        $out = Update-StarInConfigRaw -Raw $script:Raw -Targets @([pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/two:free'; Star = $false })
        $out | Should -Match '"a/two:free": \{ "name": "Two · 1M"'
    }
    It 'chỉ sửa ĐÚNG provider — cùng id ở provider khác không đổi' {
        $out = Update-StarInConfigRaw -Raw $script:Raw -Targets @([pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'a/one:free'; Star = $false })
        $out | Should -Match '"2-xkiro-max"[\s\S]*"a/one:free": \{ "name": "One paid"'
        $out | Should -Match '"1-xkiro-free"[\s\S]*"a/one:free": \{ "name": "One · 1M"'
    }
    It 'không đổi gì khi đã đúng trạng thái' {
        $out = Update-StarInConfigRaw -Raw $script:Raw -Targets @([pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/two:free'; Star = $true })
        $out | Should -BeExactly $script:Raw
    }
    It 'giữ nguyên comment / dòng không phải model' {
        $raw2 = "// keep me`n" + $script:Raw
        $out = Update-StarInConfigRaw -Raw $raw2 -Targets @([pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'a/three'; Star = $true })
        $out | Should -Match '^// keep me'
        $out | Should -Match '"a/three": \{ "name": "⭐ \[L\] Three"'
    }
    It 'không phá JSON — vẫn parse được sau khi gắn/gỡ' {
        $t = @(
            [pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/one:free'; Star = $true }
            [pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/two:free'; Star = $false }
            [pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'a/one:free'; Star = $false }
        )
        $out = Update-StarInConfigRaw -Raw $script:Raw -Targets $t
        { $out | ConvertFrom-Json } | Should -Not -Throw
    }
    It 'REGRESSION: giữ nguyên giá $X/$Y trong name (không bị regex group-ref cắn)' {
        $rawDollar = @'
{
  "provider": {
    "2-xkiro-max": {
      "models": {
        "g/one": { "name": "[A] Foo · $0.75/$3.75 · 1M", "release_date": "2099-01-01" }
      }
    }
  }
}
'@
        $out = Update-StarInConfigRaw -Raw $rawDollar -Targets @([pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'g/one'; Star = $true })
        $out.Contains('⭐ [A] Foo') | Should -BeTrue
        $out.Contains('$0.75/$3.75') | Should -BeTrue
        $out.Contains('1M') | Should -BeTrue
    }
    It 'prefix khác (⚠️) và hậu tố (✓Max) được giữ nguyên khi gắn/gỡ ⭐' {
        $warn = [char]0x26A0
        $rawWarn = @'
{
  "provider": {
    "2-xkiro-max": {
      "models": {
        "w/one": { "name": "WARN [L] Foo · $0.10/$0.20 · bar (MAX)", "release_date": "2099-01-01" }
      }
    }
  }
}
'@.Replace('WARN', $warn).Replace('MAX', [char]0x2713 + 'Max')
        $add = Update-StarInConfigRaw -Raw $rawWarn -Targets @([pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'w/one'; Star = $true })
        $add.Contains([char]0x2B50) | Should -BeTrue
        $add.Contains($warn) | Should -BeTrue
        $add.Contains([char]0x2713 + 'Max') | Should -BeTrue
        $rem = Update-StarInConfigRaw -Raw $add -Targets @([pscustomobject]@{ Provider = '2-xkiro-max'; ModelId = 'w/one'; Star = $false })
        $rem.Contains([char]0x2B50) | Should -BeFalse
        $rem.Contains($warn) | Should -BeTrue
        $rem.Contains('[L] Foo · $0.10/$0.20') | Should -BeTrue
    }
    It 'idempotent: gắn ⭐ 2 lần cho kết quả như 1 lần' {
        $one = Update-StarInConfigRaw -Raw $script:Raw -Targets @([pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/one:free'; Star = $true })
        $two = Update-StarInConfigRaw -Raw $one -Targets @([pscustomobject]@{ Provider = '1-xkiro-free'; ModelId = 'a/one:free'; Star = $true })
        $two | Should -BeExactly $one
    }
}
