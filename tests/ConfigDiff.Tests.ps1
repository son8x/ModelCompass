#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test Get-ConfigDiff / Test-ConfigFile / New-ConfigDriftReport (Phase 2.4).
Dùng config tạm nhỏ, không đụng file thật, không cần mạng.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot '..\scripts\Common-Functions.ps1')
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('modelcompass-cfgdiff-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:tmpRoot -Force | Out-Null

    $base = '{
      "$schema": "https://opencode.ai/config.json",
      "model": "p1/m-a",
      "provider": {
        "p1": {
          "npm": "@ai-sdk/openai-compatible",
          "options": { "baseURL": "http://127.0.0.1:1/v1", "apiKey": "{env:FAKE_KEY_CFGDIFF}" },
          "models": { "m-a": { "name": "A" }, "m-b": { "name": "B" } }
        }
      }
    }'
    $script:cfgApath = Join-Path $script:tmpRoot 'a.json'
    $script:cfgBpath = Join-Path $script:tmpRoot 'b.json'
    Set-Content -LiteralPath $script:cfgApath -Value $base -Encoding utf8

    $mod = $base -replace '"model": "p1/m-a"', '"model": "p1/m-x"'
    Set-Content -LiteralPath $script:cfgBpath -Value $mod -Encoding utf8

    [Environment]::SetEnvironmentVariable('FAKE_KEY_CFGDIFF', 'fake', 'Process')
}

AfterAll {
    Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ConfigDiff' {
    It '2 config giống hệt → 0 chênh lệch (Count không vỡ cho 0 phần tử)' {
        $a = Get-ConfigContent $script:cfgApath
        $d = @(Get-ConfigDiff -DevObj $a -ProdObj $a)
        $d.Count | Should -Be 0
    }

    It 'model mặc định khác nhau → đúng 1 diff có nội dung' {
        $a = Get-ConfigContent $script:cfgApath
        $b = Get-ConfigContent $script:cfgBpath
        $d = @(Get-ConfigDiff -DevObj $b -ProdObj $a)
        $d.Count | Should -Be 1
        $d[0] | Should -Match 'Model mặc định khác nhau'
    }

    It 'provider chỉ có ở prod bị báo' {
        $a = Get-ConfigContent $script:cfgApath
        $b = Get-ConfigContent $script:cfgBpath
        $b.provider | Add-Member -NotePropertyName 'pZ' -NotePropertyValue ([pscustomobject]@{ models = ([pscustomobject]@{ m = ([pscustomobject]@{}) }) })
        $d = @(Get-ConfigDiff -DevObj $a -ProdObj $b)
        $d | Where-Object { $_ -match "chỉ có ở prod: 'pZ'" } | Should -Not -BeNullOrEmpty
    }

    It 'model chỉ có ở dev bị báo (chưa publish)' {
        $a = Get-ConfigContent $script:cfgApath
        $b = Get-ConfigContent $script:cfgBpath
        $a.provider.p1.models | Add-Member -NotePropertyName 'm-dev' -NotePropertyValue ([pscustomobject]@{ name = 'Dev' })
        $d = @(Get-ConfigDiff -DevObj $a -ProdObj $b)
        $d | Where-Object { $_ -match "m-dev" } | Should -Not -BeNullOrEmpty
    }

    It '-SkipModelSet bỏ qua diff bộ model' {
        $a = Get-ConfigContent $script:cfgApath
        $b = Get-ConfigContent $script:cfgBpath
        $a | Add-Member -NotePropertyName 'model' -NotePropertyValue 'p1/m-a' -Force
        $b | Add-Member -NotePropertyName 'model' -NotePropertyValue 'p1/m-a' -Force
        $a.provider.p1.models | Add-Member -NotePropertyName 'm-extra' -NotePropertyValue ([pscustomobject]@{ name = 'X' })
        $d = @(Get-ConfigDiff -DevObj $a -ProdObj $b -SkipModelSet)
        $d | Where-Object { $_ -match 'm-extra' } | Should -BeNullOrEmpty
    }

    It 'exit code contract: 0 / 1 phần tử không làm vỡ caller bọc @()' {
        $a = Get-ConfigContent $script:cfgApath
        $d0 = @(Get-ConfigDiff -DevObj $a -ProdObj $a)
        $b = Get-ConfigContent $script:cfgBpath
        $d1 = @(Get-ConfigDiff -DevObj $b -ProdObj $a)
        $d0.GetType().IsArray | Should -BeTrue
        $d1.GetType().IsArray | Should -BeTrue
    }
}

Describe 'Test-ConfigFile' {
    It 'config hợp lệ → không lỗi' {
        $res = Test-ConfigFile -Path $script:cfgApath
        @($res.Errors).Count | Should -Be 0
        @($res.Warnings).Count | Should -Be 0
    }

    It 'thiếu model → lỗi' {
        $p = Join-Path $script:tmpRoot 'nomodel.json'
        Set-Content -LiteralPath $p -Value '{
          "$schema": "https://opencode.ai/config.json",
          "provider": {}
        }' -Encoding utf8
        $res = Test-ConfigFile -Path $p
        @($res.Errors) | Where-Object { $_ -match 'Thiếu "model"' } | Should -Not -BeNullOrEmpty
    }

    It 'không có provider → cảnh báo (không lỗi)' {
        $p = Join-Path $script:tmpRoot 'noprov.json'
        Set-Content -LiteralPath $p -Value '{
          "$schema": "https://opencode.ai/config.json",
          "model": "p1/m-a"
        }' -Encoding utf8
        $res = Test-ConfigFile -Path $p
        @($res.Errors).Count | Should -Be 0
        @($res.Warnings) | Where-Object { $_ -match 'Không có mục "provider"' } | Should -Not -BeNullOrEmpty
    }

    It 'env thiếu: cảnh báo (mặc định) → lỗi khi -Strict' {
        $p = Join-Path $script:tmpRoot 'env.json'
        Set-Content -LiteralPath $p -Value '{
          "$schema": "https://opencode.ai/config.json",
          "model": "p1/m-a",
          "provider": { "p1": {
            "options": { "apiKey": "{env:CFGDIFF_ABSENT_VAR_XYZ}" },
            "models": { "m-a": {} }
          } }
        }' -Encoding utf8
        $res = Test-ConfigFile -Path $p
        @($res.Errors).Count | Should -Be 0
        $resStrict = Test-ConfigFile -Path $p -Strict
        @($resStrict.Errors) | Where-Object { $_ -match 'CFGDIFF_ABSENT_VAR_XYZ' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'New-ConfigDriftReport (đồng bộ → OK)' {
    It 'chạy với dev=prod → report OK, exit 0' {
        $out = Join-Path $script:tmpRoot 'report.md'
        & (Join-Path $script:RepoRoot 'scripts\New-ConfigDriftReport.ps1') `
            -Dev $script:cfgApath -Prod $script:cfgApath `
            -PresetsDir (Join-Path $script:tmpRoot 'empty-presets') `
            -BackupDir (Join-Path $script:tmpRoot 'no-backup') `
            -OutFile $out | Out-Null
        [int]$LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $out | Should -BeTrue
        $content = Get-Content -LiteralPath $out -Raw
        $content | Should -Match 'Kết luận: \*\*OK'
        $content | Should -Match 'Chênh lệch dev vs prod'
    }
}