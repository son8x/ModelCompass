#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Dọn backup theo chính sách (giữ N bản mới nhất mỗi nơi).

.DESCRIPTION
    Chống backup chất đống trong repo và trong thư mục global opencode:
      - configs\production\.backup\*.json            (backup do Publish-Config.ps1 tạo)
      - $env:USERPROFILE\.config\opencode\opencode.json.bak-<ts>  (do Install/Restore tạo)

    Mặc định giữ 10 bản mới nhất mỗi nơi, xoá phần cũ hơn.
    -DryRun: chỉ liệt kê, không xoá.

.PARAMETER KeepRepo
    Số backup repo giữ lại. Mặc định 10.

.PARAMETER KeepGlobal
    Số backup global giữ lại. Mặc định 10.

.PARAMETER DryRun
    Chỉ liệt kê sẽ xoá, không xoá thật.

.PARAMETER RepoOnly
    Chỉ dọn backup trong repo (không đụng thư mục global).

.PARAMETER GlobalOnly
    Chỉ dọn backup global opencode (không đụng repo).

.EXAMPLE
    PS scripts\Prune-Backups.ps1 -DryRun
    PS scripts\Prune-Backups.ps1 -KeepRepo 5 -KeepGlobal 20
#>
[CmdletBinding()]
param(
    [int]$KeepRepo = 10,
    [int]$KeepGlobal = 10,
    [switch]$DryRun,
    [switch]$RepoOnly,
    [switch]$GlobalOnly
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$repo     = Get-RepoRoot
$repoBak  = Join-Path $repo 'configs\production\.backup'
$globalDir = Join-Path $env:USERPROFILE '.config\opencode'

$mode = if ($RepoOnly) { 'repo' } elseif ($GlobalOnly) { 'global' } else { 'all' }
Write-Step "Prune backup (mode=$mode, keep repo=$KeepRepo, global=$KeepGlobal, dryRun=$($DryRun.IsPresent))"

$deleted = 0
$kept = 0

function Invoke-PruneDir {
    <#
    Giữ N file .bak/.json mới nhất theo LastWriteTime, xoá phần còn lại.
    #>
    param(
        [string]$Dir,
        [string]$Filter,
        [bool]$IsRepo,
        [int]$Keep,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        Write-Warn "${Label}: chưa có thư mục $Dir"
        return
    }
    $files = @(Get-ChildItem -LiteralPath $Dir -File -Filter $Filter | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        Write-Info "${Label}: không có backup nào."
        return
    }
    $toDelete = @($files | Select-Object -Skip $Keep)
    Write-Info "${Label}: tổng $($files.Count), giữ $([Math]::Min($files.Count, $Keep)), xoá $($toDelete.Count)."
    foreach ($f in $toDelete) {
        if ($DryRun) {
            Write-Host "  [dry] sẽ xoá: $($f.Name)" -ForegroundColor DarkYellow
        } else {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Host "  đã xoá: $($f.Name)" -ForegroundColor Red
        }
        $script:deleted++
    }
    $script:kept += $files.Count - $toDelete.Count
}

if ($mode -in 'all', 'repo')   { Invoke-PruneDir -Dir $repoBak  -Filter '*.json'      -Keep $KeepRepo   -Label 'Backup repo' }
if ($mode -in 'all', 'global') { Invoke-PruneDir -Dir $globalDir -Filter 'opencode.json.bak-*' -Keep $KeepGlobal -Label 'Backup global' }

Write-Step 'Kết quả'
if ($DryRun) {
    Write-Info "DryRun: sẽ xoá $deleted file (chưa xoá gì). Giữ lại tổng $kept."
} else {
    Write-Ok "Đã xoá $deleted file, giữ lại $kept backup."
}
exit 0