#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Cài cấu hình production vào thư mục opencode global
    (mặc định ~/.config/opencode/opencode.json) — CÓ BACKUP AN TOÀN.

.DESCRIPTION
    - Chỉ cài từ bản production (đã test) — không bao giờ từ development.
    - Backup file đích cũ thành opencode.json.bak-<timestamp>.
    - KHÔNG ghi key thật hay biến cấu trúc lạ — chỉ copy file config.
    - Sau khi cài: QUIT & RESTART opencode để nạp cấu hình mới.

.PARAMETER Target
    File đích. Mặc định: $env:USERPROFILE\.config\opencode\opencode.json
    (chuẩn global config của opencode).

.PARAMETER Force
    Không hỏi xác nhận (dùng cho tự động hoá).

.EXAMPLE
    PS scripts\Install-Config.ps1
#>
[CmdletBinding()]
param(
    [string]$Target,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$repo = Get-RepoRoot
$source = Join-Path $repo 'configs\production\opencode.json'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    Write-Fail "Chưa có production config: $source — chạy Publish-Config.ps1 trước."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
}

Write-Step "Install: $source -> $Target"

# xuất cảnh báo nếu có source hoặc target là file chứa comment JSONC
$rawSource = Get-Content -LiteralPath $source -Raw -Encoding utf8
if ($rawSource -match '(?m)^\s*//') {
    Write-Warn 'Source là JSONC có comment — opencode.json dạng JSON thuần sẽ không chấp nhận. Kiểm tra production.'
}

$targetDir = Split-Path $Target -Parent
if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    Write-Fail "Chưa có thư mục config global: $targetDir"
    Write-Info 'Bạn đã từng chạy opencode trên máy này chưa? Nếu chưa, hãy trỏ -Target tới nơi khác.'
    exit 1
}

# kiểm tra cấu hình hợp lệ trước khi cài thay
Write-Info 'Validate source trước khi cài...'
& (Join-Path $PSScriptRoot 'Test-ModelCompassConfig.ps1') -Path $source | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'Source không hợp lệ — không cài.'
    exit 1
}

$sourceHash = Get-FileHashSha256 $source
$backup = ''
$hadTarget = Test-Path -LiteralPath $Target -PathType Leaf
if ($hadTarget) {
    $stamp = Get-Timestamp
    $backup = "${Target}.bak-${stamp}"
    Copy-Item -LiteralPath $Target -Destination $backup
    Write-Info "Backup config đang dùng: $backup"
}

Copy-Item -LiteralPath $source -Destination $Target
$statePath = Save-ConfigState -Target $Target -Source $source -SourceHash $sourceHash -Backup $backup -Note 'install (production -> global)'
Write-Ok "Đã cài: $Target"
Write-Info "Trạng thái cài đặt: $statePath"

# cảnh báo nếu tồn tại cả .json và .jsonc (tránh mơ hồ khi opencode load)
$alt = $Target -replace '\.json$', '.jsonc'
if ($alt -ne $Target -and (Test-Path -LiteralPath $alt -PathType Leaf)) {
    Write-Warn "PHÁT HIỆN cả $([System.IO.Path]::GetFileName($Target)) và $([System.IO.Path]::GetFileName($alt)) cùng tồn tại."
    Write-Warn 'opencode có thể nạp nhầm file. Nên xoá/bỏ tên 1 trong 2 file tương ứng.'
}

Write-Host ''
Write-Ok 'HOÀN TẤT. Quy trình còn lại:'
Write-Host '  1. Quit opencode hoàn toàn.'
Write-Host '  2. Mở lại opencode — cấu hình mới sẽ được nạp.'
Write-Host '  3. Nếu gặp sự cố: scripts\Restore-RunningConfig.ps1 -Backup <tên-file-bak>'
exit 0