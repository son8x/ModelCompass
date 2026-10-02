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

# Khi chạy `pwsh -File mc.ps1 <lệnh>` mà không có tham số phụ, $args là $null
# (không phải mảng rỗng) — splat nó vào sẽ thành một đối số $null và hỏng.
if ($null -ne $args -and $args.Count -gt 0) {
    $results = @(mc $Command @args)
} else {
    $results = @(mc $Command)
}

# `mc` trả về: <stdout của script con>... rồi mã thoát (int) ở cuối.
# Gán thẳng vào biến sẽ nuốt mất toàn bộ stdout, nên phải tách ra và in lại.
$code = 0
$text = [System.Collections.Generic.List[string]]::new()
foreach ($item in $results) {
    if ($null -eq $item) { continue }
    if ($item -is [int]) { $code = $item; continue }
    $text.Add([string]$item)
}
if ($text.Count -gt 0) { $text | Write-Host }

exit $code
