#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass.Tests.ps1 — Pester v5 test cho phần lõi scripts/ và cấu hình.
Chạy bằng:  scripts\Test-Suite.ps1
#>

BeforeAll {
    $script:RepoRoot  = Split-Path $PSScriptRoot -Parent
    $script:Common    = Join-Path $script:RepoRoot 'scripts\Common-Functions.ps1'
    $script:TestConf  = Join-Path $script:RepoRoot 'scripts\Test-ModelCompassConfig.ps1'
    $script:DevConfig = Join-Path $script:RepoRoot 'configs\development\opencode.jsonc'
    $script:ProdRepos = Join-Path $script:RepoRoot 'configs\production\opencode.json'
    . $script:Common
}

Describe 'Remove-CommentsAndTrailingCommas' {
    It 'loại bỏ comment dòng (//)' {
        $in = "`"a`": 1, // comment`n`"b`": 2"
        Remove-CommentsAndTrailingCommas $in | Should -Be "`"a`": 1, `n`"b`": 2"
    }

    It 'giữ nguyên // nằm trong chuỗi' {
        $in = '{"note": "https://example.com // path"}'
        Remove-CommentsAndTrailingCommas $in | Should -Be $in
    }

    It 'loại bỏ comment block (/* */)' {
        $in = '/* đầu */ { "a": 1 /* giữa */ }'
        $out = Remove-CommentsAndTrailingCommas $in
        $out | Should -Not -Match '/\*'
        $out | Should -Be ' { "a": 1  }'
    }

    It 'loại bỏ trailing comma trước ] và }' {
        $in = '{ "a": 1, "b": [1, 2,], }'
        Remove-CommentsAndTrailingCommas $in | Should -Be '{ "a": 1, "b": [1, 2]}'
    }

    It 'trả null với input null' {
        Remove-CommentsAndTrailingCommas $null | Should -BeNullOrEmpty
    }
}

Describe 'Get-ConfigContent' {
    It 'parse JSONC hợp lệ' {
        $tmp = Join-Path $TestDrive 'sample.jsonc'
        Set-Content -LiteralPath $tmp -Value @'
{
  "model": "p/m",
  "provider": {
    "p": { "models": { "m": {} } } // comment cuối
  },
}
'@ -Encoding utf8
        $cfg = Get-ConfigContent $tmp
        $cfg.model | Should -Be 'p/m'
        $cfg.provider.p.models.PSObject.Properties.Name | Should -Contain 'm'
    }

    It 'throw khi file không tồn tại' {
        { Get-ConfigContent -Path (Join-Path $TestDrive 'missing.json') } | Should -Throw
    }

    It 'throw khi JSON hỏng cú pháp' {
        $tmp = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $tmp -Value '{ "a": }' -Encoding utf8
        { Get-ConfigContent $tmp } | Should -Throw
    }
}

Describe 'Resolve-EnvValue' {
    It 'trả nguyên bản khi không phải {env:...}' {
        Resolve-EnvValue 'some-value' | Should -Be 'some-value'
    }

    It 'trả $null khi biến chưa đặt' {
        Resolve-EnvValue '{env:MODELCOMPASS_TEST_MISSING_XYZ_123}' | Should -BeNullOrEmpty
    }

    It 'giải {env:VAR} theo biến đã đặt' {
        $env:MODELCOMPASS_TEST_KEY = 'secret123'
        try {
            Resolve-EnvValue '{env:MODELCOMPASS_TEST_KEY}' | Should -Be 'secret123'
        } finally {
            Remove-Item Env:MODELCOMPASS_TEST_KEY -ErrorAction SilentlyContinue
        }
    }

    It 'trả $null với chuỗi rỗng/trống' {
        Resolve-EnvValue '' | Should -BeNullOrEmpty
        Resolve-EnvValue '   ' | Should -BeNullOrEmpty
    }
}

Describe 'Hash & state helpers' {
    It 'Get-InstallStatePath thêm .state.json' {
        Get-InstallStatePath 'C:\x\opencode.json' | Should -Be 'C:\x\opencode.json.state.json'
    }

    It 'Get-FileHashSha256 trả hash 64 ký tự hex cho file có thật' {
        $tmp = Join-Path $TestDrive 'h.txt'
        Set-Content -LiteralPath $tmp -Value 'abc' -Encoding utf8
        Get-FileHashSha256 $tmp | Should -Match '^[0-9A-Fa-f]{64}$'
    }

    It 'Get-FileHashSha256 trả $null cho file thiếu' {
        Get-FileHashSha256 (Join-Path $TestDrive 'nope.txt') | Should -BeNullOrEmpty
    }

    It 'Save/Read-ConfigState roundtrip' {
        $src = Join-Path $TestDrive 'src.json'
        $dst = Join-Path $TestDrive 'opencode.json'
        Set-Content -LiteralPath $src -Value '{"a":1}' -Encoding utf8
        Set-Content -LiteralPath $dst -Value '{}' -Encoding utf8

        $statePath = Save-ConfigState -Target $dst -Source $src -SourceHash (Get-FileHashSha256 $src) -Backup 'b1' -Note 'test'
        Test-Path -LiteralPath $statePath | Should -BeTrue

        $st = Read-ConfigState -Target $dst
        $st.note    | Should -Be 'test'
        $st.backup  | Should -Be 'b1'
        $st.source  | Should -Be $src
        $st.targetHash | Should -Match '^[0-9A-Fa-f]{64}$'
    }

    It 'Read-ConfigState trả $null khi chưa có state' {
        Read-ConfigState (Join-Path $TestDrive 'nope.json') | Should -BeNullOrEmpty
    }
}

Describe 'Cấu hình production/development hợp lệ' {
    It 'production có $schema, model provider/model, provider <= 1 model' {
        $cfg = Get-ConfigContent $script:ProdRepos
        $cfg.'$schema' | Should -Match 'opencode.ai/config.json'
        $cfg.model | Should -Match '/'
        @($cfg.provider.PSObject.Properties).Count | Should -BeGreaterThan 0
        foreach ($p in @($cfg.provider.PSObject.Properties)) {
            @($p.Value.models.PSObject.Properties).Count | Should -BeGreaterThan 0
            $p.Value.npm | Should -Not -BeNullOrEmpty
            $p.Value.options.baseURL | Should -Not -BeNullOrEmpty
        }
    }

    It 'development có $schema + >= 1 provider' {
        $cfg = Get-ConfigContent $script:DevConfig
        $cfg.'$schema' | Should -Match 'opencode.ai/config.json'
        @($cfg.provider.PSObject.Properties).Count | Should -BeGreaterThan 0
    }

    It 'Test-ModelCompassConfig pass cho production và development (exit 0)' {
        foreach ($f in @($script:ProdRepos, $script:DevConfig)) {
            & $script:TestConf -Path $f | Out-Null
            [int]$LASTEXITCODE | Should -Be 0
        }
    }

    It 'không còn API key thật trong configs/' {
        $leaks = @()
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'configs') -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $m = Select-String -Path $_.FullName -Pattern '(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|Bearer\s+[A-Za-z0-9._-]{20,})' -ErrorAction SilentlyContinue
            if ($m) { $leaks += "$($_.Name):$($m.LineNumber)" }
        }
        $leaks | Should -BeNullOrEmpty
    }

    It 'config chỉ dùng {env:VAR} cho apiKey' {
        $cfg = Get-ConfigContent $script:ProdRepos
        foreach ($p in @($cfg.provider.PSObject.Properties)) {
            $key = [string]$p.Value.options.apiKey
            $key | Should -Match '^\{env:[A-Z0-9_]+\}$'
        }
    }
}

Describe 'Compare-Config (dev vs prod)' {
    It 'chạy được và exit 0 (dev/prod hiện đang đồng bộ)' {
        & (Join-Path $script:RepoRoot 'scripts\Compare-Config.ps1') | Out-Null
        [int]$LASTEXITCODE | Should -Be 0
    }
}