#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: test các hàm THUẦN của Test-ModelHealth.ps1 (không gọi mạng).
Nạp functions qua dot-source script với -SkipRun (pattern StatusUpdate/Benchmark.Tests).
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:scriptPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'scripts\health\Test-ModelHealth.ps1')
    . $script:scriptPath -SkipRun
}

Describe 'Get-HealthClass' {
    It 'OK nhanh ≤ FastMs -> fast' {
        Get-HealthClass -Status OK -Ms 800 -FastMs 1500 -SlowMs 5000 | Should -Be 'fast'
    }
    It 'OK đúng ngưỡng FastMs -> fast (biên ≤)' {
        Get-HealthClass -Status OK -Ms 1500 -FastMs 1500 -SlowMs 5000 | Should -Be 'fast'
    }
    It 'OK giữa FastMs và SlowMs -> ok' {
        Get-HealthClass -Status OK -Ms 3000 -FastMs 1500 -SlowMs 5000 | Should -Be 'ok'
    }
    It 'OK > SlowMs -> slow' {
        Get-HealthClass -Status OK -Ms 9000 -FastMs 1500 -SlowMs 5000 | Should -Be 'slow'
    }
    It 'RATE -> busy' {
        Get-HealthClass -Status RATE -Ms 100 | Should -Be 'busy'
    }
    It 'LOCKED (403) -> locked' {
        Get-HealthClass -Status LOCKED -Ms 100 | Should -Be 'locked'
    }
    It 'SKIP -> unknown' {
        Get-HealthClass -Status SKIP -Ms 0 | Should -Be 'unknown'
    }
    It 'TIMEOUT -> slow (kết nối được nhưng không trả lời kịp)' {
        Get-HealthClass -Status TIMEOUT -Ms 15000 | Should -Be 'slow'
    }
    It 'lỗi khác (AUTH/NOTFOUND/DOWN/ERROR/HTTP) -> down' {
        foreach ($s in 'AUTH', 'NOTFOUND', 'DOWN', 'ERROR', 'HTTP') {
            Get-HealthClass -Status $s -Ms 0 | Should -Be 'down'
        }
    }
}

Describe 'Get-HealthBadge' {
    It 'ánh xạ badge đúng' {
        Get-HealthBadge -Class fast | Should -Be '⚡'
        Get-HealthBadge -Class busy | Should -Be '🟡'
        Get-HealthBadge -Class slow | Should -Be '🐌'
        Get-HealthBadge -Class locked | Should -Be '🔒'
        Get-HealthBadge -Class down | Should -Be '⛔'
    }
    It 'ok/unknown không badge' {
        Get-HealthBadge -Class ok | Should -Be ''
        Get-HealthBadge -Class unknown | Should -Be ''
    }
}

Describe 'Remove-HealthBadge' {
    It 'gỡ badge ở đầu' {
        Remove-HealthBadge -Name '⚡[L] Fast Model · 128K' | Should -Be '[L] Fast Model · 128K'
    }
    It 'gỡ badge nhưng GIỮ ⭐ và 🆕' {
        Remove-HealthBadge -Name '⭐🐌Qwen3.8 Max · 1M' | Should -Be '⭐Qwen3.8 Max · 1M'
        Remove-HealthBadge -Name '🆕⛔New Model · 64K' | Should -Be '🆕New Model · 64K'
    }
    It 'name không có badge -> giữ nguyên' {
        Remove-HealthBadge -Name 'Qwen3.7 Plus · 1M · vision' | Should -Be 'Qwen3.7 Plus · 1M · vision'
    }
    It 'không đụng emoji nằm giữa tên' {
        Remove-HealthBadge -Name 'Model ⚡ nội bộ' | Should -Be 'Model ⚡ nội bộ'
    }
}

Describe 'Add-HealthBadge' {
    It 'gắn badge vào đầu' {
        Add-HealthBadge -Name '[L] Fast Model · 128K' -Badge '⚡' | Should -Be '⚡[L] Fast Model · 128K'
    }
    It 'gắn SAU tiền tố ⭐' {
        Add-HealthBadge -Name '⭐Qwen3.8 Max · 1M' -Badge '🐌' | Should -Be '⭐🐌Qwen3.8 Max · 1M'
    }
    It 'idempotent — gắn 2 lần không nhân đôi' {
        $once = Add-HealthBadge -Name '[A] Model · 256K' -Badge '⚡'
        $twice = Add-HealthBadge -Name $once -Badge '⚡'
        $twice | Should -Be $once
    }
    It 'đổi badge cũ sang badge mới' {
        Add-HealthBadge -Name '⚡[A] Model · 256K' -Badge '🐌' | Should -Be '🐌[A] Model · 256K'
    }
    It 'badge rỗng -> chỉ gỡ badge cũ' {
        Add-HealthBadge -Name '⛔[A] Model · 256K' -Badge '' | Should -Be '[A] Model · 256K'
    }
}

Describe 'Sort-HealthResults' {
    It 'fast trước, down sau; trong lớp ms tăng dần' {
        $rows = @(
            [pscustomobject]@{ Id = 'c'; Class = 'down'; Ms = 10 }
            [pscustomobject]@{ Id = 'b'; Class = 'fast'; Ms = 900 }
            [pscustomobject]@{ Id = 'a'; Class = 'fast'; Ms = 300 }
            [pscustomobject]@{ Id = 'd'; Class = 'slow'; Ms = 6000 }
        )
        $sorted = @(Sort-HealthResults -Results $rows)
        $sorted[0].Id | Should -Be 'a'
        $sorted[1].Id | Should -Be 'b'
        $sorted[2].Id | Should -Be 'd'
        $sorted[3].Id | Should -Be 'c'
    }
}

Describe 'Get-HealthSummary' {
    It 'đếm đúng theo lớp + total' {
        $rows = @(
            [pscustomobject]@{ Class = 'fast' }
            [pscustomobject]@{ Class = 'fast' }
            [pscustomobject]@{ Class = 'down' }
        )
        $s = Get-HealthSummary -Results $rows
        $s.Total | Should -Be 3
        $s.fast | Should -Be 2
        $s.down | Should -Be 1
        $s.ok | Should -Be 0
    }
}

Describe 'Set-HealthBadgesInConfigText' {
    BeforeAll {
        $script:rawCfg = @'
{
  "provider": {
    "p-free": {
      "models": {
        "x/model-a": { "name": "[L] Model A · 128K", "release_date": "2099-12-31" },
        "x/model-b": { "name": "Model B · 64K", "release_date": "2099-11-01" }
      }
    },
    "p-max": {
      "models": {
        "x/model-a": { "name": "[A] Model A · $2.00/$12.00 · 256K", "release_date": "2099-01-01" }
      }
    }
  }
}
'@
    }
    It 'gắn badge dạng 1 dòng (dev), giữ release_date' {
        $out = Set-HealthBadgesInConfigText -Raw $script:rawCfg -Targets @(
            [pscustomobject]@{ Provider = 'p-free'; Id = 'x/model-a'; Badge = '⚡' }
        )
        $out | Should -Match '"x/model-a": \{ "name": "⚡\[L\] Model A · 128K", "release_date": "2099-12-31"'
    }
    It 'gắn badge dạng nhiều dòng (prod), giữ nguyên comment/layout' {
        $raw = @'
{
  "provider": {
    "p-free": {
      "models": {
        "x/model-b": {
          "name": "Model B · 64K",
          "release_date": "2099-11-01"
        }
      }
    }
  }
}
'@
        $out = Set-HealthBadgesInConfigText -Raw $raw -Targets @(
            [pscustomobject]@{ Provider = 'p-free'; Id = 'x/model-b'; Badge = '🐌' }
        )
        $out | Should -Match '"name": "🐌Model B · 64K"'
        $out | Should -Match '"release_date": "2099-11-01"'
    }
    It 'badge rỗng gỡ badge cũ' {
        $raw = @'
{
  "provider": {
    "p-free": {
      "models": {
        "x/model-c": { "name": "⛔Model C · 32K", "release_date": "2099-01-01" }
      }
    }
  }
}
'@
        $out = Set-HealthBadgesInConfigText -Raw $raw -Targets @(
            [pscustomobject]@{ Provider = 'p-free'; Id = 'x/model-c'; Badge = '' }
        )
        $out | Should -Match '"name": "Model C · 32K"'
    }
    It 'không đụng model khác' {
        $out = Set-HealthBadgesInConfigText -Raw $script:rawCfg -Targets @(
            [pscustomobject]@{ Provider = 'p-free'; Id = 'x/model-a'; Badge = '⚡' }
        )
        $out | Should -Match '"x/model-b": \{ "name": "Model B · 64K"'
    }
    It 'cùng id ở 2 provider — badge scope đúng provider' {
        $out = Set-HealthBadgesInConfigText -Raw $script:rawCfg -Targets @(
            [pscustomobject]@{ Provider = 'p-free'; Id = 'x/model-a'; Badge = '⚡' }
            [pscustomobject]@{ Provider = 'p-max'; Id = 'x/model-a'; Badge = '🐌' }
        )
        $out | Should -Match '"x/model-a": \{ "name": "⚡\[L\] Model A'
        $out | Should -Match '"x/model-a": \{ "name": "🐌\[A\] Model A'
    }
    It 'name chứa giá $In/$Out không bị hiểu nhầm' {
        $out = Set-HealthBadgesInConfigText -Raw $script:rawCfg -Targets @(
            [pscustomobject]@{ Provider = 'p-max'; Id = 'x/model-a'; Badge = '⚡' }
        )
        $out | Should -Match '"name": "⚡\[A\] Model A · \$2\.00/\$12\.00 · 256K"'
    }
}
