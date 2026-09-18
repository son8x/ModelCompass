#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Validate cấu hình opencode (JSON/JSONC) theo chuẩn ModelCompass.

.DESCRIPTION
    Kiểm tra (logic chung Test-ConfigFile trong Common-Functions.ps1):
      - Cú pháp JSON(C) hợp lệ.
      - Có "$schema" và "model" đúng dạng provider/model-id.
      - Mỗi provider có ít nhất 1 model.
      - Options.baseURL / npm có vẻ hợp lệ.
      - Mọi {env:VAR} trong file có biến môi trường tương ứng (warning/mặc định).

.PARAMETER Path
    Đường dẫn tới file cấu hình. Mặc định: configs\production\opencode.json

.PARAMETER Strict
    Biến cấu hình thiếu -> coi là LỖI (dùng trong CI khi muốn chặt chẽ).

.EXAMPLE
    PS scripts\Test-ModelCompassConfig.ps1 -Path configs\development\opencode.jsonc
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Strict
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path (Get-RepoRoot) 'configs\production\opencode.json'
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Fail "Không tìm thấy file: $Path"
    exit 1
}

Write-Step "Validate: $Path"
$result = Test-ConfigFile -Path $Path -Strict:$Strict

if (@($result.Errors).Count -gt 0) {
    foreach ($e in $result.Errors) { Write-Fail $e }
    Write-Fail "Kết quả: FAIL ($(@($result.Errors).Count) lỗi)"
    exit 1
}
if (@($result.Warnings).Count -gt 0) {
    foreach ($w in $result.Warnings) { Write-Warn $w }
    Write-Info "Kết quả: OK nhưng có $(@($result.Warnings).Count) cảnh báo"
    exit 0
}
Write-Ok 'Kết quả: OK — cấu hình hợp lệ, không cảnh báo.'
exit 0