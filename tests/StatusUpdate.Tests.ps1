#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test cập nhật STATUS.md bán tự động (Phase 1.5).
Phủ: ConvertTo-StatusBlock + Update-StatusFile (marker insert/replace) — file tạm.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Test-ModelConnectivity.ps1') -SkipRun
    $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('modelcompass-status-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:tmpRoot -Force | Out-Null
    $script:results = @(
        [pscustomobject]@{ Provider = '1-xkiro-free'; Model = 'deepseek-v4';  Status = 'OK';    Message = 'phản hồi OK' }
        [pscustomobject]@{ Provider = '6-teamoRouter'; Model = 'glm-5.3';     Status = 'SKIP';  Message = 'thiếu API key ({env:...})' }
        [pscustomobject]@{ Provider = '1-xkiro-free'; Model = 'kimi-k2.5';    Status = 'NOTFOUND'; Message = 'HTTP 404' }
    )
}

AfterAll {
    Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-StatusBlock' {
    It 'chứa marker START/END + tiêu đề + bảng đủ hàng' {
        $b = ConvertTo-StatusBlock -Results $script:results -TestedAt (Get-Date '2026-09-17T12:00:00')
        $b[0]      | Should -Match '^<!-- START auto-status'
        $b[-1]     | Should -Be '<!-- END auto-status -->'
        $b[1]      | Should -Be '### Trạng thái gần nhất — 2026-09-17 12:00:00'
        ($b -contains '| Provider | Model | Status | Phản hồi |') | Should -Be $true
        ($b -contains '| 1-xkiro-free | deepseek-v4 | **OK** | phản hồi OK |') | Should -Be $true
        ($b -contains '| 6-teamoRouter | glm-5.3 | **SKIP** | thiếu API key ({env:...}) |') | Should -Be $true
    }

    It 'dòng đếm theo status, đếm lớn trước' {
        $b = ConvertTo-StatusBlock -Results $script:results -TestedAt (Get-Date)
        ($b -match '^> (OK 1|NOTFOUND 1|SKIP 1)') | Should -Be $true
    }
}

Describe 'Update-StatusFile' {
    BeforeAll {
        $script:statusFile = Join-Path $script:tmpRoot 'STATUS.md'
        Set-Content -LiteralPath $script:statusFile -Value @(
            '# STATUS - Trạng thái test từng model', '',
            '> Ghi chú gốc giữ nguyên.',
            '', '## Mục cũ', 'nội dung cũ vẫn còn'
        ) -Encoding utf8
    }

    It 'chưa có marker -> chèn sau dòng tiêu đề, giữ nguyên nội dung cũ' {
        $u = Update-StatusFile -StatusPath $script:statusFile -BlockLines (ConvertTo-StatusBlock -Results $script:results -TestedAt (Get-Date))
        $u.Action | Should -Be 'insert'
        $content = Get-Content -LiteralPath $script:statusFile -Encoding utf8
        $content[1]   | Should -Match '^<!-- START auto-status'
        ($content -contains 'nội dung cũ vẫn còn') | Should -Be $true
    }

    It 'đã có marker -> replace đúng 1 khối, cập nhật nội dung mới' {
        $new = @([pscustomobject]@{ Provider = 'x'; Model = 'y'; Status = 'OK'; Message = 'ok mới' })
        $u = Update-StatusFile -StatusPath $script:statusFile -BlockLines (ConvertTo-StatusBlock -Results $new -TestedAt (Get-Date))
        $u.Action | Should -Be 'replace'
        $content = Get-Content -LiteralPath $script:statusFile -Encoding utf8
        @($content | Where-Object { $_ -match '^<!-- START auto-status' }).Count | Should -Be 1
        ($content -contains '| x | y | **OK** | ok mới |') | Should -Be $true
        ($content -contains '| 1-xkiro-free | deepseek-v4 | **OK** | phản hồi OK |') | Should -Be $false
        ($content -contains 'nội dung cũ vẫn còn') | Should -Be $true
    }

    It 'file không tồn tại -> throw' {
        { Update-StatusFile -StatusPath (Join-Path $script:tmpRoot 'missing.md') -BlockLines @('x') } | Should -Throw
    }
}