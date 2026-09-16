#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Promote cấu hình từ development -> production.

.DESCRIPTION
    Quy trình 2 giai đoạn để không bao giờ đưa cấu hình chưa test vào hoạt động:

      1. Validate cú pháp/cấu trúc (Test-ModelCompassConfig.ps1).
      2. [Tuỳ chọn] Test kết nối thực tế (Test-ModelConnectivity.ps1).
      3. Backup production hiện tại vào configs\production\.backup\.
      4. Ghi production (chuẩn hoá về JSON thuần, bỏ comment).
      5. [Tuỳ chọn] `git add` để chuẩn bị commit.

    Script KHÔNG tự ghi lên cấu hình opencode đang chạy — việc đó thuộc
    Install-Config.ps1 và do bạn chủ động gọi.

.PARAMETER Source
    File cấu hình nguồn. Mặc định: configs\development\opencode.jsonc

.PARAMETER SkipValidation
    Bỏ qua bước validate (KHÔNG khuyến khích).

.PARAMETER ConnectivityTest
    Chạy test kết nối tới các provider trước khi publish.

.PARAMETER GitCommitMessage
    Nếu có: `git add` file production + commit với message này.
    (Chỉ file production được stage, không commit các thay đổi khác.)

.PARAMETER Yes
    Tự xác nhận các bước thủ công (dành cho non-interactive).

.EXAMPLE
    PS scripts\Publish-Config.ps1 -ConnectivityTest
    PS scripts\Publish-Config.ps1 -GitCommitMessage "Add DeepSeek V4 Flash vào production"
#>
[CmdletBinding()]
param(
    [string]$Source,
    [switch]$SkipValidation,
    [switch]$ConnectivityTest,
    [string]$GitCommitMessage,
    [switch]$Yes
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$repo       = Get-RepoRoot
$prodPath   = Join-Path $repo 'configs\production\opencode.json'
$backupDir  = Join-Path $repo 'configs\production\.backup'

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $repo 'configs\development\opencode.jsonc'
}
if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    Write-Fail "Không tìm thấy source: $Source"
    exit 1
}
$Source = (Get-Item -LiteralPath $Source).FullName

Write-Step "Publish: $Source -> $prodPath"

# ── 1. Validate ─────────────────────────────────────────────
if (-not $SkipValidation) {
    Write-Info 'Bước 1: Validate cấu hình...'
    & (Join-Path $PSScriptRoot 'Test-ModelCompassConfig.ps1') -Path $Source | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'Validate thất bại. Sửa cấu hình rồi chạy lại.'
        exit 1
    }
} else {
    Write-Warn 'BƯỚC 1 BỊ BỎ QUA (SkipValidation) — bạn tự chịu trách nhiệm.'
}

# ── 2. Connectivity test ────────────────────────────────────
if ($ConnectivityTest) {
    Write-Info 'Bước 2: Test kết nối provider/model...'
    & (Join-Path $PSScriptRoot 'Test-ModelConnectivity.ps1') -ConfigPath $Source | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'Connectivity test thất bại. Không publish.'
        exit 1
    }
}

# ── 3. Parse + chuẩn hoá ────────────────────────────────────
Write-Info 'Bước 3: Chuẩn hoá JSON (bỏ comment) và kiểm tra khác biệt...'
try {
    $config = Get-ConfigContent $Source
} catch {
    Write-Fail $_.Exception.Message
    exit 1
}
$newJson = (ConvertTo-OpenCodeJson $config) + "`n"

$hadProd = Test-Path -LiteralPath $prodPath -PathType Leaf
if ($hadProd) {
    $oldRaw = Get-Content -LiteralPath $prodPath -Raw -Encoding utf8
    if ($oldRaw.Trim() -eq $newJson.Trim()) {
        Write-Warn 'Nội dung source giống hệt production hiện tại — không cần publish.'
        exit 0
    }
}

# ── 4. xác nhận + backup + ghi ──────────────────────────────
if (-not $Yes -and -not $GitCommitMessage) {
    Write-Host "  Sẽ ghi đè: $prodPath" -ForegroundColor DarkYellow
}

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if ($hadProd) {
    $backup = Join-Path $backupDir ("opencode." + (Get-Timestamp) + ".json")
    Copy-Item -LiteralPath $prodPath -Destination $backup
    Write-Info "Backup production cũ: $backup"
}

Set-Content -LiteralPath $prodPath -Value $newJson -Encoding utf8NoBOM
Write-Ok "Đã ghi production (JSON thuần, sẵn sàng cài): $prodPath"

# ── 5. git ──────────────────────────────────────────────────
if ($GitCommitMessage) {
    Push-Location $repo
    try {
        & git add configs/production/opencode.json
        if ($LASTEXITCODE -ne 0) { throw 'git add thất bại' }
        & git commit -m $GitCommitMessage
        if ($LASTEXITCODE -ne 0) { Write-Warn 'git commit thất bại (chưa có repo? kiểm tra git status).' }
        else { Write-Ok "Đã commit: $GitCommitMessage" }
    } finally {
        Pop-Location
    }
} else {
    Write-Info 'Gợi ý commit nếu cần quản lý phiên bản trong GitHub:'
    Write-Host "  git add configs/production/opencode.json"
    Write-Host "  git commit -m ""Mô tả thay đổi cấu hình"""
}

Write-Info 'Bước kế tiếp (chỉ khi bạn muốn áp dụng vào opencode đang dùng):'
Write-Host '  scripts\Install-Config.ps1'
Write-Ok 'Xong.'
exit 0