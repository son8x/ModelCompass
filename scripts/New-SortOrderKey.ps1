#Requires -Version 7

<#
New-SortOrderKey.ps1 — helper "khoá sắp xếp 2099" cho thứ tự model trong /model.

Quy ước (docs/providers-and-models.md §6): opencode sắp model theo release_date
GIẢM DẦN. Ta dùng release_date (không hiển thị trên UI) làm khoá 2099 để ép thứ tự.
Script này chỉ IN key — KHÔNG sửa file config (configs chứa nhiều comment, tránh hỏng).

Cách dùng:
  # sinh N key giảm dần (mặc định từ 2099-12-31, cách 1 ngày)
  pwsh scripts\New-SortOrderKey.ps1 -Count 24
  # sinh key cho cụm (cluster) B của provider trả phí, bắt đầu 2099-10-25
  pwsh scripts\New-SortOrderKey.ps1 -From 2099-10-25 -Count 9
  # key nằm giữa 2 model kề sẵn (chèn model mới không đụng date cũ)
  pwsh scripts\New-SortOrderKey.ps1 -Between 2099-12-31 -BetweenLower 2099-12-29
  # thêm N model vào CUỐI provider (đọc key nhỏ nhất sẵn có, nối tiếp phía dưới)
  pwsh scripts\New-SortOrderKey.ps1 -Append -Config configs\production\opencode.json -Provider 1-xkiro-free -Count 3
  # dựng LẠI toàn bộ key của provider (in bảng model -> key mới; dán vào file)
  pwsh scripts\New-SortOrderKey.ps1 -Rebuild -Config configs\development\opencode.jsonc -Provider 1-xkiro-free -From 2099-12-31
#>

param(
    [CmdletBinding()]
    [int]$Count = 1,
    [string]$From = '2099-12-31',
    [int]$StepDays = -1,
    [string[]]$Exclude = @(),
    [string]$Between,                      # Upper (key lớn hơn)
    [string]$BetweenLower,
    [switch]$Append,
    [switch]$Rebuild,
    [string]$Config,
    [string]$Provider
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

function Get-ProviderModels {
    param([string]$Path, [string]$ProviderId)
    $cfg = Get-ConfigContent $Path
    $prov = $cfg.provider.PSObject.Properties[$ProviderId]
    if ($null -eq $prov) { throw "Provider '$ProviderId' không có trong config." }
    $models = $prov.Value.models
    if ($null -eq $models) { throw "Provider '$ProviderId' chưa có models." }
    return $models
}

if ($Between -or $BetweenLower) {
    if (-not $Between -or -not $BetweenLower) {
        throw 'Cần đủ cả -Between <Upper> và -BetweenLower <Lower>.'
    }
    Write-Host (Get-SortOrderKeyBetween -Upper $Between -Lower $BetweenLower)
    exit 0
}

if ($Append) {
    if (-not $Config -or -not $Provider) { throw '-Append cần cả -Config và -Provider.' }
    $models = Get-ProviderModels $Config $Provider
    $existing = @()
    foreach ($m in $models.PSObject.Properties) {
        $rd = $m.Value.PSObject.Properties['release_date']
        if ($null -ne $rd -and -not [string]::IsNullOrWhiteSpace($rd.Value)) {
            $existing += $rd.Value
        }
    }
    if ($existing.Count -eq 0) { throw "Provider '$Provider' chưa có key release_date nào để nối tiếp." }
    $minKey = ($existing | Sort-Object)[0]
    $keys = New-SortOrderKey -From $minKey -StepDays -1 -Count $Count -Exclude $existing
    $keys | ForEach-Object { Write-Host $_ }
    exit 0
}

if ($Rebuild) {
    if (-not $Config -or -not $Provider) { throw '-Rebuild cần cả -Config và -Provider.' }
    if ($StepDays -ge 0) { throw '-Rebuild yêu cầu -StepDays âm (giảm dần).' }
    $models = Get-ProviderModels $Config $Provider
    $names = @($models.PSObject.Properties.Name)
    $keys = New-SortOrderKey -From $From -StepDays $StepDays -Count $names.Count
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ('{0}  =>  {1}' -f $names[$i], $keys[$i])
    }
    exit 0
}

# Mặc định: sinh dãy key.
New-SortOrderKey -From $From -StepDays $StepDays -Count $Count -Exclude $Exclude |
    ForEach-Object { Write-Host $_ }