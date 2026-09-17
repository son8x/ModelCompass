#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Khôi phục cấu hình opencode đang chạy từ backup.

.DESCRIPTION
    Khi cài cấu hình mới gây lỗi cho opencode, dùng script này để quay lại
    cấu hình cũ đã hoạt động tốt.

    - Chạy KHÔNG tham số: liệt kê các backup có sẵn trong thư mục global.
    - Chạy với -Backup <file>: khôi phục cấu hình đó về vị trí đang dùng
      (backup tự động bản đang dùng trước khi ghi đè).

.PARAMETER Backup
    Đường dẫn (hoặc tên file) của backup dạng opencode.json.bak-<timestamp>.

.PARAMETER List
    Chỉ liệt kê các backup, không khôi phục.

.PARAMETER Target
    File đích (mặc định: ~/.config/opencode/opencode.json).

.EXAMPLE
    PS scripts\Restore-RunningConfig.ps1 -List
    PS scripts\Restore-RunningConfig.ps1 -Backup opencode.json.bak-20260916-100000
#>
[CmdletBinding()]
param(
    [string]$Backup,
    [switch]$List,
    [string]$Target
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
}
$dir = Split-Path $Target -Parent

$backs = @()
if (Test-Path -LiteralPath $dir -PathType Container) {
    $backs = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^opencode\.json\.bak-\d{8}-\d{6}' } | Sort-Object LastWriteTime -Descending)
}

if ($List -or ([string]::IsNullOrWhiteSpace($Backup))) {
    Write-Step "Backup hiện có trong $dir"

    $state = Read-ConfigState -Target $Target
    if ($null -ne $state) {
        Write-Host "  ── Trạng thái hiện tại ──" -ForegroundColor DarkCyan
        Write-Host ("    cài lúc   : {0}" -f $state.installedAt) -ForegroundColor Cyan
        Write-Host ("    nguồn     : {0}" -f $state.source) -ForegroundColor Cyan
        Write-Host ("    backup    : {0}" -f $state.backup) -ForegroundColor Cyan
        Write-Host ("    ghi chú   : {0}" -f $state.note) -ForegroundColor Cyan
        if ($state.targetHash) {
            $nowHash = Get-FileHashSha256 $Target
            $match = ($nowHash -eq $state.targetHash)
            Write-Host ("    hash      : {0}{1}" -f $state.targetHash, $(if ($match) { '  ✓ khớp với file đang chạy' } else { '  ⚠️ file đang chạy ĐÃ ĐỔI (bị sửa ngoài scripts)' })) -ForegroundColor $(if ($match) { 'Green' } else { 'DarkYellow' })
        }
        Write-Host ''
    } else {
        Write-Warn 'Chưa có file trạng thái cài đặt (.state.json) — chưa dùng Install-Config.ps1 trên target này?'
    }

    if ($null -eq $backs -or $backs.Count -eq 0) {
        Write-Warn 'Không tìm thấy backup nào.'
        exit 0
    }
    foreach ($b in $backs) {
        Write-Host ("  {0}   ({1})" -f $b.Name, $b.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor Green
    }
    Write-Host ''
    Write-Info 'Để khôi phục:  scripts\Restore-RunningConfig.ps1 -Backup <tên-file>'
    if (-not $List) { exit 0 }
    exit 0
}

# ── khôi phục với backup cụ thể ─────────────────────────────
$src = if (Test-Path -LiteralPath $Backup -PathType Leaf) { $Backup }
       else { Join-Path $dir $Backup }
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Write-Fail "Không tìm thấy backup: $Backup (thử -List để xem danh sách)."
    exit 1
}

Write-Step "Restore: $src -> $Target"
$backupNow = ''
if (Test-Path -LiteralPath $Target -PathType Leaf) {
    $bakNow = "${Target}.bak-" + (Get-Timestamp)
    Copy-Item -LiteralPath $Target -Destination $bakNow
    $backupNow = $bakNow
    Write-Info "Backup hiện trạng: $bakNow"
}
Copy-Item -LiteralPath $src -Destination $Target
$statePath = Save-ConfigState -Target $Target -Source $src -SourceHash (Get-FileHashSha256 $src) -Backup $backupNow -Note 'restore (rollback từ backup)'
Write-Ok 'Đã khôi phục. Quit & restart opencode để áp dụng.'
Write-Info "Trạng thái cài đặt: $statePath"
exit 0