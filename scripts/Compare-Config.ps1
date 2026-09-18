#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: So sánh cấu hình development vs production (chống lệch phiên bản).

.DESCRIPTION
    Phát hiện lệch giữa config development (WIP) và production (đã test) để không
    vô tình mất model/đổi option khi publish. So sánh:
        - Model mặc định ("model")
        - Bộ provider: provider thiếu ở 1 bên
        - Options mỗi provider: npm, baseURL
        - Bộ model mỗi provider: model thiếu ở 1 bên / thừa (chưa publish)

    Mặc định script CHỈ CẢNH BÁO (exit 0): dev thường chứa model WIP chưa lên prod,
    nên "lệch" không tự động là lỗi. Dùng -FailOnDiff khi muốn chốt cứng (vd sau
    khi publish, xác nhận 2 file khớp).

.PARAMETER Dev
    File development. Mặc định: configs\development\opencode.jsonc

.PARAMETER Prod
    File production. Mặc định: configs\production\opencode.json

.PARAMETER SkipModelSet
    Không so bộ model từng provider (chỉ so provider set + options + model mặc định).

.PARAMETER FailOnDiff
    Có khác biệt >= 1 -> exit 1 (dùng làm chốt cứng / CI gating).

.PARAMETER Report
    Ghi báo cáo Markdown vào reports\.

.EXAMPLE
    PS scripts\Compare-Config.ps1
    PS scripts\Compare-Config.ps1 -FailOnDiff    # sau publish: phải khớp trừ model mặc định
#>
[CmdletBinding()]
param(
    [string]$Dev,
    [string]$Prod,
    [switch]$SkipModelSet,
    [switch]$FailOnDiff,
    [switch]$Report
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$repo  = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($Dev))  { $Dev  = Join-Path $repo 'configs\development\opencode.jsonc' }
if ([string]::IsNullOrWhiteSpace($Prod)) { $Prod = Join-Path $repo 'configs\production\opencode.json' }
foreach ($p in @($Dev, $Prod)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Write-Fail "Không tìm thấy file: $p"
        exit 2
    }
}

Write-Step "Compare: dev (WIP) vs prod (đã test)"
Write-Info "  dev  = $Dev"
Write-Info "  prod = $Prod"

$devObj  = Get-ConfigContent $Dev
$prodObj = Get-ConfigContent $Prod

$diffs = @(Get-ConfigDiff -DevObj $devObj -ProdObj $prodObj -SkipModelSet:$SkipModelSet)

# ── báo cáo ───────────────────────────────────────────────────
Write-Step "Chênh lệch ($($diffs.Count))"
if ($diffs.Count -eq 0) {
    Write-Ok 'Không có chênh lệch — dev và prod đồng bộ (trừ thứ tự khai báo).'
} else {
    foreach ($d in $diffs) {
        if ($d -match 'chưa publish') { Write-Warn "  $d" } else { Write-Host "  $d" -ForegroundColor DarkYellow }
    }
    if (-not $FailOnDiff) {
        Write-Info 'Cảnh báo: những model "chỉ có ở dev" là bình thường (WIP chưa publish).'
        Write-Info 'Để chốt cứng sau publish, chạy lại với -FailOnDiff.'
    }
}

if ($Report) {
    $reportDir = Join-Path $repo 'reports'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $file = Join-Path $reportDir ("config-diff-" + (Get-Timestamp) + ".md")
    $lines = @("# ModelCompass — Chênh lệch dev vs prod", '', "Ngày: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '', "Số chênh lệch: $($diffs.Count)", '')
    if ($diffs.Count -gt 0) {
        $lines += '| # | Chênh lệch |', '|---|---|'
        $i = 0
        foreach ($d in $diffs) { $i++; $lines += "| $i | $d |" }
    } else {
        $lines += '_Đồng bộ hoàn toàn._'
    }
    $lines | Set-Content -LiteralPath $file -Encoding utf8
    Write-Info "Report: $file"
}

if ($FailOnDiff -and $diffs.Count -gt 0) {
    Write-Fail "Có $($diffs.Count) chênh lệch (FailOnDiff)."
    exit 1
}
exit 0