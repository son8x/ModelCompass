#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Báo cáo định kỳ sức khoẻ cấu hình (chạy offline, không cần mạng/local router).

.DESCRIPTION
    Tạo báo cáo Markdown sẵn sàng cho GitHub issue (Phase 2.4 — CI cron):
      - Validate dev + prod + (tuỳ chọn) tất cả preset.
      - Chênh lệch dev vs prod (Get-ConfigDiff).
      - Thống kê: kích thước file, số provider/model mỗi config.
      - Dung lượng backup (nếu có thư mục backup cục bộ — CI không có → ghi chú).

.PARAMETER Dev / Prod / PresetsDir / BackupDir
    Vị trí file/thư mục. Mặc định: configs\development / production + presets + $HOME\.config\opencode.

.PARAMETER OutFile
    Nơi ghi báo cáo md. Mặc định: reports\config-drift-report.md.

.PARAMETER FailOnInvalid
    Config lỗi -> exit 1 (CI gating).

.PARAMETER FailOnDrift
    Có chênh lệch dev/prod -> exit 2 (chốt cứng sau publish).

.EXAMPLE
    PS scripts\New-ConfigDriftReport.ps1 -OutFile reports\drift.md
#>
[CmdletBinding()]
param(
    [string]$Dev,
    [string]$Prod,
    [string]$PresetsDir,
    [string]$BackupDir,
    [string]$OutFile,
    [switch]$FailOnInvalid,
    [switch]$FailOnDrift
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$repo = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($Dev)) { $Dev = Join-Path $repo 'configs\development\opencode.jsonc' }
if ([string]::IsNullOrWhiteSpace($Prod)) { $Prod = Join-Path $repo 'configs\production\opencode.json' }
if ([string]::IsNullOrWhiteSpace($PresetsDir)) { $PresetsDir = Join-Path $repo 'configs\presets' }
if ([string]::IsNullOrWhiteSpace($BackupDir)) { $BackupDir = Join-Path $HOME '.config\opencode' }
if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path $repo 'reports\config-drift-report.md' }

$lines = [System.Collections.Generic.List[string]]::new()
$issues = [System.Collections.Generic.List[string]]::new()

$lines.Add('# ModelCompass — Báo cáo định kỳ cấu hình')
$lines.Add('')
$lines.Add("- Thời điểm: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add('')
$lines.Add('## 1. Validate cấu hình')
$lines.Add('')

function Add-Validation {
    param([string]$File)
    $res = Test-ConfigFile -Path $File
    $nErr = @($res.Errors).Count
    $nWar = @($res.Warnings).Count
    $status = if ($nErr -gt 0) { 'LỖI' } elseif ($nWar -gt 0) { 'OK (cảnh báo)' } else { 'OK' }
    $lines.Add("- $(Split-Path -Leaf $File): **$status** ($nErr lỗi, $nWar cảnh báo)")
    foreach ($e in $res.Errors) { $issues.Add("Validate $File — $e") }
    return $res
}

$prodRes = Add-Validation $Prod
$devRes  = Add-Validation $Dev

if (Test-Path -LiteralPath $PresetsDir) {
    foreach ($p in (Get-ChildItem -LiteralPath $PresetsDir -Filter '*.jsonc' -File)) {
        $null = Add-Validation $p.FullName
    }
}

$lines.Add('')
$lines.Add('## 2. Chênh lệch dev vs prod')
$lines.Add('')
$diffs = @(Get-ConfigDiff -DevObj $devRes.Config -ProdObj $prodRes.Config)
$lines.Add("Số chênh lệch: $($diffs.Count)")
if ($diffs.Count -gt 0) {
    $lines.Add('')
    foreach ($d in $diffs) { $lines.Add("- $d") }
    $issues.Add('Có chênh lệch dev vs prod (xem mục 2).')
} else {
    $lines.Add('_Đồng bộ hoàn toàn._')
}

$lines.Add('')
$lines.Add('## 3. Thống kê')
$lines.Add('')
$lines.Add('| Config | Kích thước | Provider | Model |')
$lines.Add('|---|---|---|---|')
foreach ($res in @($prodRes, $devRes)) {
    $size = (Get-Item -LiteralPath $res.Path).Length
    $provs = @($res.Config.provider.PSObject.Properties)
    $nModels = 0
    foreach ($p in $provs) { $nModels += @($p.Value.models.PSObject.Properties).Count }
    $lines.Add("| $(Split-Path -Leaf $res.Path) | $([math]::Round($size / 1KB, 1)) KB | $($provs.Count) | $nModels |")
}

$lines.Add('')
$lines.Add('## 4. Backup cục bộ')
$lines.Add('')
if (Test-Path -LiteralPath $BackupDir) {
    $backups = @(Get-ChildItem -LiteralPath $BackupDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '(\.backup|\.bak-)' })
    if ($backups.Count -gt 0) {
        $total = ($backups | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum)
        $newest = ($backups | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        $lines.Add("- Tổng dung lượng backup: $([math]::Round($total / 1MB, 2)) MB ($($backups.Count) file)")
        $lines.Add("- Backup mới nhất: $($newest.Name) ($($newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))")
    } else {
        $lines.Add('- Không tìm thấy file backup trong thư mục.')
    }
} else {
    $lines.Add('- Không có backup cục bộ (môi trường CI — backup nằm trên máy chạy opencode).')
}

$lines.Add('')
if ($issues.Count -gt 0) {
    $lines.Add("## Kết luận: **CÓ $($issues.Count) VẤN ĐỀ**")
} else {
    $lines.Add('## Kết luận: **OK — mọi thứ đều nhất quán**')
}

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$lines | Set-Content -LiteralPath $OutFile -Encoding utf8
Write-Ok "Report: $OutFile  (issues=$($issues.Count))"

if ($FailOnInvalid -and @($issues | Where-Object { $_ -match '^Validate ' }).Count -gt 0) { exit 1 }
if ($FailOnDrift -and $diffs.Count -gt 0) { exit 2 }
exit 0