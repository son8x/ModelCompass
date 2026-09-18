#Requires -Version 7
<#
mc.ps1 — shim gọi module ModelCompass CLI:
    pwsh scripts\mc.ps1 <lệnh> [tham số script]
Tương đương: Import-Module ModelCompass rồi mc <lệnh> ...
Hoặc dùng trực tiếp trong phiên: Import-Module modules\ModelCompass; mc help
#>
param([Parameter(Mandatory = $true, Position = 0)][string]$Command)

$moduleDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules\ModelCompass'
Import-Module (Join-Path $moduleDir 'ModelCompass.psd1') -Force -ErrorAction Stop

$code = mc $Command @args
exit $code