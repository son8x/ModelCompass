#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test Pha 3 — tự sinh bảng ⭐ trong docs/model-reference.md §2
(scripts/recommend/Update-RecommendDocs.ps1). Thuần + drift-guard tài liệu.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Rec = Join-Path $script:repo 'scripts\recommend'

    . (Join-Path $script:repo 'scripts\Common-Functions.ps1')
    . (Get-ScriptPath 'Update-XKiroModels.ps1') -SkipRun
    . (Join-Path $script:Rec 'Get-ModelCandidates.ps1')
    . (Join-Path $script:Rec 'Resolve-StarRules.ps1')
    . (Join-Path $script:Rec 'Update-RecommendDocs.ps1') -SkipRun

    $script:Groups = $script:StarGroups
    $script:Purposes = $script:StarPurposes

    function New-TestCandidate {
        param([string]$Id, [string]$Provider, [string]$Group, [int]$Context = 0, $In = $null, $Out = $null)
        [pscustomobject]@{ Id = $Id; Name = $Id; Provider = $Provider; Group = $Group; Context = $Context; In = $In; Out = $Out }
    }
}

Describe 'Format-RecommendPricePair / Format-RecommendContext' {
    It 'nhóm paid → $in / $out; free → free' {
        (Format-RecommendPricePair (New-TestCandidate -Id 'a/b' -Provider '2-xkiro-max' -Group 'A' -In 2.0 -Out 12.0)) | Should -Be '$2.00 / $12.00'
        (Format-RecommendPricePair (New-TestCandidate -Id 'a/b:free' -Provider '1-xkiro-free' -Group 'free')) | Should -Be 'free'
    }
    It 'context 1M → 1M; >1M → 1.5M; 0 → —' {
        (Format-RecommendContext (New-TestCandidate -Id 'a' -Provider 'p' -Group 'free' -Context 1000000)) | Should -Be '1M'
        (Format-RecommendContext (New-TestCandidate -Id 'a' -Provider 'p' -Group 'free' -Context 1500000)) | Should -Be '1.5M'
        (Format-RecommendContext (New-TestCandidate -Id 'a' -Provider 'p' -Group 'free' -Context 0)) | Should -Be '—'
    }
}

Describe 'New-RecommendStarsMarkdown (thuần)' {
    BeforeAll {
        $freeCand = New-TestCandidate -Id 'qwen/x:free' -Provider '1-xkiro-free' -Group 'free' -Context 1000000
        $paidCand = New-TestCandidate -Id 'z-ai/glm-l' -Provider '2-xkiro-max' -Group 'L' -In 0.15 -Out 0.5
        $script:Rows = @(
            [pscustomobject]@{ Kind = 'purpose'; Key = 'reasoning'; Label = 'reasoning (mặc định)'; Scope = 'free'; ModelId = 'qwen/x:free'; Source = 'table'; Candidate = $freeCand }
            [pscustomobject]@{ Kind = 'purpose'; Key = 'fast';      Label = 'nhanh/subagent';       Scope = 'paid'; ModelId = 'z-ai/glm-l';  Source = 'table'; Candidate = $paidCand }
            [pscustomobject]@{ Kind = 'group';   Key = 'free';      Label = 'nhóm free';             Scope = 'free'; ModelId = 'qwen/x:free'; Source = 'table'; Candidate = $freeCand }
            [pscustomobject]@{ Kind = 'group';   Key = 'L';         Label = 'nhóm L';                Scope = 'paid'; ModelId = 'z-ai/glm-l';  Source = 'table'; Candidate = $paidCand }
        )
    }
    It 'chứa bảng nhóm + bảng mục đích + số model' {
        $lines = New-RecommendStarsMarkdown -Rows $script:Rows -Groups $script:Groups -Purposes $script:Purposes -Date '01/01/2026'
        $txt = ($lines -join "`n")
        $txt | Should -Match '\*\*2 model\*\* được khuyến nghị'
        $txt | Should -Match '\(1 free \+ 1 trả phí\)'
        $txt | Should -Match '\*\*⭐ Theo nhóm\*\*'
        $txt | Should -Match '\*\*⭐ Theo mục đích\*\*'
        $txt | Should -Match '01/01/2026'
    }
    It 'liệt kê model của nhóm + mục đích' {
        $txt = (New-RecommendStarsMarkdown -Rows $script:Rows -Groups $script:Groups -Purposes $script:Purposes -Date 'x') -join "`n"
        $txt | Should -Match '`qwen/x:free`'
        $txt | Should -Match '`z-ai/glm-l`'
        $txt | Should -Match 'reasoning \(mặc định\)'
        $txt | Should -Match 'nhanh/subagent'
    }
    It 'mục đích không có model nào → KHÔNG xuất dòng' {
        $txt = (New-RecommendStarsMarkdown -Rows $script:Rows -Groups $script:Groups -Purposes $script:Purposes -Date 'x') -join "`n"
        $txt | Should -Not -Match 'flagship'
    }
}

Describe 'Set-MarkerBlock / Get-MarkerBlock (thuần)' {
    It 'thay nội dung giữa marker, giữ marker + text ngoài, giữ LF' {
        $doc = "# H`n`n<!-- BEGIN:stars -->`nOLD`n<!-- END:stars -->`n`n> note`n"
        $new = Set-MarkerBlock -Content $doc -BodyLines @('L1', 'L2') -Begin '<!-- BEGIN:stars' -End '<!-- END:stars -->'
        $new | Should -Match '<!-- BEGIN:stars -->'
        $new | Should -Match "L1`nL2`n"
        $new | Should -Match '<!-- END:stars -->'
        $new | Should -Match '> note'
        $new | Should -Not -Match 'OLD'
        ([regex]::Matches($new, "`r`n")).Count | Should -Be 0
    }
    It 'thiếu marker → trả $null' {
        (Set-MarkerBlock -Content 'no markers' -BodyLines @('x') -Begin '<!-- BEGIN:stars' -End '<!-- END:stars -->') | Should -BeNullOrEmpty
    }
    It 'Get-MarkerBlock trích đúng body (roundtrip)' {
        $doc = "# H`n<!-- BEGIN:stars -->`nA`nB`n<!-- END:stars -->`n"
        (Get-MarkerBlock -Content $doc -Begin '<!-- BEGIN:stars' -End '<!-- END:stars -->') | Should -Be "A`nB"
    }
    It 'giữ CRLF nếu file dùng CRLF' {
        $doc = "# H`r`n<!-- BEGIN:stars -->`r`nOLD`r`n<!-- END:stars -->`r`n"
        $new = Set-MarkerBlock -Content $doc -BodyLines @('A') -Begin '<!-- BEGIN:stars' -End '<!-- END:stars -->'
        $new | Should -Match "A`r`n"
        ([regex]::Matches($new, "(?<!`r)`n")).Count | Should -Be 0
    }
}

Describe 'Tích hợp: bảng ⭐ trong docs khớp đề xuất hiện tại (drift guard)' {
    BeforeAll {
        $script:docPath = Join-Path $script:repo 'docs\model-reference.md'
        $script:cfgPath = Join-Path $script:repo 'configs\development\opencode.jsonc'
        $script:catPath = Join-Path $script:repo 'docs\catalogs\xkiro.json'
        $script:capPath = Join-Path $script:Rec 'model-capabilities.json'
    }
    It 'file docs có marker BEGIN/END' {
        $raw = Get-Content -LiteralPath $script:docPath -Raw -Encoding utf8
        $raw | Should -Match '<!-- BEGIN:recommend-stars'
        $raw | Should -Match '<!-- END:recommend-stars -->'
    }
    It 'khối hiện có = nội dung vừa sinh từ config/catalog' {
        $caps = Read-ModelCapabilities -Path $script:capPath
        $configObj = Get-ConfigContent $script:cfgPath
        $catalogModels = @((Get-Content -LiteralPath $script:catPath -Raw -Encoding utf8 | ConvertFrom-Json).models)
        $bundle = Get-ModelCandidates -ConfigObj $configObj -CatalogModels $catalogModels -ProviderKeys @('1-xkiro-free', '2-xkiro-max')
        $resolved = Resolve-StarRules -Candidates $bundle.Candidates -Capabilities $caps
        $body = New-RecommendStarsMarkdown -Rows $resolved.Rows -Groups $script:Groups -Purposes $script:Purposes
        $docRaw = Get-Content -LiteralPath $script:docPath -Raw -Encoding utf8
        $existing = Get-MarkerBlock -Content $docRaw -Begin '<!-- BEGIN:recommend-stars' -End '<!-- END:recommend-stars -->'
        $fresh = (@($body) -join "`n")
        ($existing -replace "`r`n", "`n").Trim() | Should -Be ($fresh -replace "`r`n", "`n").Trim()
    }
}
