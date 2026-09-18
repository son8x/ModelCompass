#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test GitHub Pages docs site (Phase 3.4) — cấu trúc Jekyll + workflow.
Không build Jekyll (cần Ruby) — chỉ kiểm toàn bộ file/điểm nối sẵn.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Describe 'GitHub Pages docs site' {
    It 'docs/site có _config.yml (theme minima) + index.md + models.md' {
        Test-Path -LiteralPath (Join-Path $script:repo 'docs\site\_config.yml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repo 'docs\site\index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repo 'docs\site\models.md') | Should -BeTrue
    }

    It '_config.yml khai báo theme' {
        $y = Get-Content -LiteralPath (Join-Path $script:repo 'docs\site\_config.yml') -Raw -Encoding utf8
        $y | Should -Match '(?m)^\s*theme: minima'
    }

    It 'index.md và models.md đọc dữ liệu từ site.data.modelbank (liquid)' {
        $idx = Get-Content -LiteralPath (Join-Path $script:repo 'docs\site\index.md') -Raw -Encoding utf8
        $mod = Get-Content -LiteralPath (Join-Path $script:repo 'docs\site\models.md') -Raw -Encoding utf8
        $idx | Should -Match 'site\.data\.modelbank\.providers'
        $idx | Should -Match 'site\.data\.modelbank\.presets'
        $mod | Should -Match 'site\.data\.modelbank\.models'
    }

    It 'workflow pages.yml cấu hình đầy đủ (jekyll build + deploy, sinh modelbank)' {
        $wf = Get-Content -LiteralPath (Join-Path $script:repo '.github\workflows\pages.yml') -Raw -Encoding utf8
        $wf | Should -Match 'actions/jekyll-build-pages@v1'
        $wf | Should -Match 'actions/deploy-pages@v4'
        $wf | Should -Match 'Export-ModelBank\.ps1 -OutDir ./docs/site/_data'
    }
}