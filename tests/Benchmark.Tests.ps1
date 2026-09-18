#Requires -Version 7
#Requires -Modules Pester
<#
ModelCompass: Test Get-BenchmarkSummary (Phase 2.5) — thuần, không gọi mạng.
Nạp functions qua dot-source script với -SkipRun (giữ nguyên pattern StatusUpdate.Tests).
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:scriptPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'scripts\Test-ModelConnectivity.ps1')
    . $script:scriptPath -SkipRun
}

Describe 'Get-BenchmarkSummary' {
    It 'trung vị/avg/min/max từ các run OK' {
        $runs = @(
            [pscustomobject]@{ ms = 100; ok = $true;  prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 200; ok = $true;  prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 300; ok = $true;  prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 400; ok = $true;  prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 500; ok = $true;  prompt_tokens = 10; completion_tokens = 20; error = '' }
        )
        $s = Get-BenchmarkSummary -Runs $runs
        $s.Ok | Should -Be 5
        $s.Fail | Should -Be 0
        $s.MinMs | Should -Be 100
        $s.MaxMs | Should -Be 500
        $s.MedianMs | Should -Be 300
        $s.AvgMs | Should -Be 300
    }

    It 'token trung bình + TokensPerSec tính đúng' {
        $runs = @(
            [pscustomobject]@{ ms = 100; ok = $true; prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 100; ok = $true; prompt_tokens = 10; completion_tokens = 20; error = '' }
            [pscustomobject]@{ ms = 100; ok = $true; prompt_tokens = 10; completion_tokens = 20; error = '' }
        )
        $s = Get-BenchmarkSummary -Runs $runs
        $s.AvgTokenIn | Should -Be 10
        $s.AvgTokenOut | Should -Be 20
        $s.TokensPerSec | Should -Be 300   # (10+20)*3 / 0.3s
    }

    It 'run lỗi → Fail > 0 + FirstError, không đếm vào Ok' {
        $runs = @(
            [pscustomobject]@{ ms = 50;  ok = $true;  prompt_tokens = 5; completion_tokens = 5; error = '' }
            [pscustomobject]@{ ms = 30;  ok = $false; prompt_tokens = 0; completion_tokens = 0; error = 'timeout' }
        )
        $s = Get-BenchmarkSummary -Runs $runs
        $s.Ok | Should -Be 1
        $s.Fail | Should -Be 1
        $s.FirstError | Should -Match 'timeout'
        $s.MedianMs | Should -Be 50
    }

    It 'không có run OK → thông số về 0, chỉ ghi Fail + FirstError' {
        $runs = @(
            [pscustomobject]@{ ms = 30; ok = $false; prompt_tokens = 0; completion_tokens = 0; error = 'refused' }
        )
        $s = Get-BenchmarkSummary -Runs $runs
        $s.Ok | Should -Be 0
        $s.Fail | Should -Be 1
        $s.MedianMs | Should -Be 0
        $s.TokensPerSec | Should -Be 0
        $s.FirstError | Should -Match 'refused'
    }

    It 'median chẵn = trung bình 2 giá trị giữa' {
        $runs = @(
            [pscustomobject]@{ ms = 100; ok = $true; prompt_tokens = 1; completion_tokens = 1; error = '' }
            [pscustomobject]@{ ms = 400; ok = $true; prompt_tokens = 1; completion_tokens = 1; error = '' }
            [pscustomobject]@{ ms = 200; ok = $true; prompt_tokens = 1; completion_tokens = 1; error = '' }
            [pscustomobject]@{ ms = 300; ok = $true; prompt_tokens = 1; completion_tokens = 1; error = '' }
        )
        $s = Get-BenchmarkSummary -Runs $runs
        $s.MedianMs | Should -Be 250
    }
}