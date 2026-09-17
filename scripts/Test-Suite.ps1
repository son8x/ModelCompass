#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    ModelCompass: Chạy toàn bộ test Pester (scripts + config validation).

.DESCRIPTION
    Quét test trong tests/ bằng Pester v5+. Exit code = số test FAILED.
    -InstallPester: tự cài Pester v5 nếu chưa có (dùng cho CI/máy mới).

.EXAMPLE
    PS scripts\Test-Suite.ps1
    PS scripts\Test-Suite.ps1 -InstallPester
#>
[CmdletBinding()]
param([switch]$InstallPester)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testsDir = Join-Path $repoRoot 'tests'
$testFiles = @(
    Get-ChildItem -LiteralPath $testsDir -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { $_.FullName }
)

if ($testFiles.Count -eq 0) {
    Write-Error "Không tìm thấy test nào trong: $testsDir"
    exit 2
}

if ($InstallPester -or -not (Get-Module -ListAvailable Pester)) {
    if (-not (Get-Module -ListAvailable Pester)) {
        Write-Host 'Cài Pester v5 (CurrentUser scope)...'
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
    }
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
Write-Host ("Chạy {0} file test: {1}" -f $testFiles.Count, ((Split-Path $testFiles -Leaf) -join ', ')) -ForegroundColor DarkCyan
$result = Invoke-Pester -Path $testFiles -PassThru

Write-Host ''
Write-Host ("Tests   : {0}" -f $result.TotalCount) -ForegroundColor Cyan
Write-Host ("Passed  : {0}" -f $result.PassedCount) -ForegroundColor Green
Write-Host ("Failed  : {0}" -f $result.FailedCount) -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ("Skipped : {0}" -f $result.SkippedCount) -ForegroundColor DarkYellow

exit $result.FailedCount