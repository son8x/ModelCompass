#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test mọi TEMPLATE config (Phase 3.2 + 3.3):
  - project-templates/{code,thesis,pentest}/opencode.json
  - provider-template/opencode.json
Yêu cầu: parse JSON hợp lệ (thuần, không JSONC), có schema + model chuẩn,
không lộ API key, ${env} không dính vào JSON.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    function Get-TemplateFiles {
        $files = @()
        $files += Get-ChildItem -Path (Join-Path $script:repo 'configs\project-templates') -Recurse -Filter '*.json' -File
        $files += Get-ChildItem -Path (Join-Path $script:repo 'configs\provider-template') -Recurse -Filter '*.json' -File
        return @($files)
    }
}

Describe 'Template configs (project + provider)' {
    It 'có ít nhất 4 file template hợp lệ' {
        $files = Get-TemplateFiles
        $files.Count | Should -BeGreaterOrEqual 4
    }

    It 'mọi template parse được dạng JSON thuần (không comment, không trailing comma)' {
        foreach ($f in Get-TemplateFiles) {
            $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
            { $null = $raw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw -Because "file $($f.Name) phải là JSON hợp lệ"
        }
    }

    It 'mọi template có $schema + model theo dạng provider/model-id' {
        foreach ($f in Get-TemplateFiles) {
            $cfg = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $cfg.'$schema' | Should -Not -BeNullOrEmpty -Because "file $($f.Name)"
            $cfg.model | Should -Match '^[^/]+/.*$' -Because "file $($f.Name)"
        }
    }

    It 'mọi provider khai báo có ít nhất 1 model' {
        foreach ($f in Get-TemplateFiles) {
            $cfg = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $providerProp = $cfg.PSObject.Properties['provider']
            if ($null -ne $providerProp) {
                foreach ($p in $cfg.provider.PSObject.Properties) {
                    $nModels = 0
                    if ($null -ne $p.Value.models) { $nModels = @($p.Value.models.PSObject.Properties).Count }
                    $nModels | Should -BeGreaterThan 0 -Because "file $($f.Name) provider $($p.Name)"
                }
            }
        }
    }

    It 'không có API key dạng sk- / token trong nội dung template' {
        foreach ($f in Get-TemplateFiles) {
            $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
            $raw | Should -Not -Match '(sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,})' -Because "file $($f.Name)"
        }
    }

    It 'mọi apiKey dùng đúng cú pháp {env:VARIABLE}' {
        foreach ($f in Get-TemplateFiles) {
            $cfg = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $providerProp = $cfg.PSObject.Properties['provider']
            if ($null -ne $providerProp) {
                foreach ($p in $cfg.provider.PSObject.Properties) {
                    if ($null -ne $p.Value.options) {
                        $key = [string]$p.Value.options.apiKey
                        if (-not [string]::IsNullOrWhiteSpace($key)) {
                            $key | Should -Match '^\{env:[A-Z][A-Z0-9_]*\}$' -Because "file $($f.Name) provider $($p.Name)"
                        }
                    }
                }
            }
        }
    }
}