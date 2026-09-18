#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Xuất "Model Bank" — config + presets + catalog pricing thành JSON
    dùng chung (đồng bộ nhiều máy, công cụ khác tiêu thụ).

.DESCRIPTION
    Đọc config (production mặc định), catalog live (docs/catalogs/<id>.json nếu có)
    và các preset (configs/presets/*.jsonc), sinh:
        model-bank/modelbank.json  — providers + models (kèm giá + tag preset) + presets + stats
        model-bank/schema.json     — JSON Schema mô tả cấu trúc (tĩnh, đã commit)

    KHÔNG xuất giá trị API key — chỉ tên biến môi trường ({env:VAR} -> apiKeyEnv).

.PARAMETER ConfigMode
    prod (mặc định) | dev — chọn file config gốc.

.PARAMETER ConfigPath
    Đường dẫn config tuỳ chỉnh (ghi đè ConfigMode).

.PARAMETER OutDir
    Thư mục xuất. Mặc định: <repo>\model-bank

.PARAMETER PresetsDir
    Thư mục preset. Mặc định: <repo>\configs\presets

.PARAMETER CatalogsDir
    Thư mục catalog live. Mặc định: <repo>\docs\catalogs

.PARAMETER SkipRun
    Chỉ nạp hàm (dot-source cho test), không chạy xuất.

.EXAMPLE
    PS scripts\Export-ModelBank.ps1
    PS mc export                          # tương đương
#>
[CmdletBinding()]
param(
    [ValidateSet('prod', 'dev')][string]$ConfigMode = 'prod',
    [string]$ConfigPath,
    [string]$OutDir,
    [string]$PresetsDir,
    [string]$CatalogsDir,
    [switch]$SkipRun
)

# Chụp cờ trước khi dot-source (quirk param trùng tên).
$skipRunFlag = [bool]$SkipRun

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

# Registry provider (Id, ConfigProviders, IdStripPrefix, KeyEnv) — không gọi mạng.
. (Join-Path $PSScriptRoot 'Get-ProviderCatalog.ps1') -SkipRun

function Get-PricesFromName {
    <# Trích giá `In:$X | Out:$Y` từ name model. #>
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [pscustomobject]@{ In = $null; Out = $null }
    }
    $m = [regex]::Match($Name, 'In:\s*\$([0-9]+(?:\.[0-9]+)?)\s*\|\s*Out:\s*\$([0-9]+(?:\.[0-9]+)?)')
    if (-not $m.Success) { return [pscustomobject]@{ In = $null; Out = $null } }
    return [pscustomobject]@{ In = [double]$m.Groups[1].Value; Out = [double]$m.Groups[2].Value }
}

function Get-ModelBankPricing {
    <#
    Giá model: ưu tiên catalog live (pricing.input/output); fallback parse từ name.
    THUẦN — phủ test.
    #>
    param(
        [Parameter(Mandatory)][string]$ModelId,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$StripPrefixes = @(),
        $CatalogLookup          # hashtable id -> normalized model (.pricing.input/.output)
    )
    $p = Get-PricesFromName $Name
    $namePricing = if ($null -ne $p.In -and $null -ne $p.Out) {
        [pscustomobject]@{ input = $p.In; output = $p.Out }
    } else { $null }

    $catalogPricing = $null
    $lookup = $ModelId
    foreach ($pre in $StripPrefixes) {
        if (-not [string]::IsNullOrWhiteSpace($pre) -and $lookup.StartsWith($pre, [System.StringComparison]::OrdinalIgnoreCase)) {
            $lookup = $lookup.Substring($pre.Length)
            break
        }
    }
    if ($null -ne $CatalogLookup -and $CatalogLookup.ContainsKey($lookup)) {
        $cat = $CatalogLookup[$lookup]
        if ($null -ne $cat.pricing.input -and $null -ne $cat.pricing.output) {
            $catalogPricing = [pscustomobject]@{ input = [double]$cat.pricing.input; output = [double]$cat.pricing.output }
        }
    }
    return [pscustomobject]@{ namePricing = $namePricing; catalogPricing = $catalogPricing }
}

function New-ModelBank {
    <#
    Dựng đối tượng "Model Bank" từ config parse + catalogs + presets.
    THUẦN (không IO) — phủ test.

    ConfigProvider : PSCustomObject `provider` (như Get-ConfigContent hầu ra).
    Catalogs       : hashtable catalogId -> PSCustomObject có .models (dạng chuẩn hoá).
    PresetInfo     : array { name, path, models = [hashtable provider(model1,model2)] }.
    ProviderReg    : registry provider (Id, ConfigProviders, IdStripPrefix, KeyEnv).
    #>
    param(
        [Parameter(Mandatory)]$ConfigProvider,
        [hashtable]$Catalogs = @{},
        $PresetInfo = @(),
        $ProviderReg = @(),
        [string]$SourceConfig = ''
    )
    $provList = [System.Collections.Generic.List[object]]::new()
    $modelList = [System.Collections.Generic.List[object]]::new()

    # preset -> danh sách "provider/model"
    $presetModelMap = @{}
    foreach ($pr in @($PresetInfo)) {
        $ids = [System.Collections.Generic.List[string]]::new()
        foreach ($kp in $pr.models.PSObject.Properties) {
            foreach ($mp in $kp.Value.models.PSObject.Properties) {
                $ids.Add("$($kp.Name)/$($mp.Name)")
            }
        }
        $presetModelMap[$pr.Name] = @($ids)
    }
    $allPresetModels = @{}
    foreach ($pr in @($PresetInfo)) {
        foreach ($mid in $presetModelMap[$pr.Name]) {
            if (-not $allPresetModels.ContainsKey($mid)) { $allPresetModels[$mid] = @() }
            $allPresetModels[$mid] = @($allPresetModels[$mid]) + $pr.Name
        }
    }

    foreach ($prov in $ConfigProvider.PSObject.Properties) {
        $def = $prov.Value
        $baseURL = $null
        if ($null -ne $def.options) { $baseURL = [string]$def.options.baseURL }

        $apiKeyEnv = $null
        if ($null -ne $def.options -and -not [string]::IsNullOrWhiteSpace([string]$def.options.apiKey)) {
            $kv = [string]$def.options.apiKey
            if ($kv -match '^\{env:([A-Z][A-Z0-9_]*)\}$') { $apiKeyEnv = $Matches[1] }
        }

        $registryHits = @($ProviderReg | Where-Object { $_.ConfigProviders -contains $prov.Name })
        $catalogLookup = $null
        $stripPrefixes = @()
        $catalogId = $null
        foreach ($reg in $registryHits) {
            $catObj = $Catalogs[$reg.Id]
            if ($null -ne $catObj -and $null -ne $catObj.models) {
                $lookup = @{}
                foreach ($cm in @($catObj.models)) {
                    if ($null -ne $cm.id) { $lookup[$cm.id] = $cm }
                }
                $catalogLookup = $lookup
                $catalogId = $reg.Id
                $stripPrefixes = @(@($reg.IdStripPrefix))
                break
            }
        }

        $nameProp = $def.PSObject.Properties['name']
        $npmProp = $def.PSObject.Properties['npm']
        $provList.Add([pscustomobject]@{
            id        = $prov.Name
            catalogId = $catalogId
            name      = if ($null -ne $nameProp) { [string]$nameProp.Value } else { '' }
            npm       = if ($null -ne $npmProp) { [string]$npmProp.Value } else { '' }
            baseURL   = $baseURL
            apiKeyEnv = $apiKeyEnv
            local     = ($null -ne $baseURL -and $baseURL -match '127\.0\.0\.1|localhost')
        })

        foreach ($mp in $def.models.PSObject.Properties) {
            $rdProp = $mp.Value.PSObject.Properties['release_date']
            $releaseDate = if ($null -ne $rdProp) { [string]$rdProp.Value } else { '' }
            $nmProp = $mp.Value.PSObject.Properties['name']
            $modelName = if ($null -ne $nmProp) { [string]$nmProp.Value } else { '' }
            $pricing = Get-ModelBankPricing -ModelId $mp.Name -Name $modelName `
                -StripPrefixes $stripPrefixes -CatalogLookup $catalogLookup
            $tags = @()
            $full = "$($prov.Name)/$($mp.Name)"
            if ($allPresetModels.ContainsKey($full)) { $tags = @($allPresetModels[$full] | ForEach-Object { "preset:$_" }) }
            $modelList.Add([pscustomobject]@{
                provider    = $prov.Name
                id          = $mp.Name
                releaseDate = $releaseDate
                name        = $modelName
                pricing     = $pricing.namePricing
                catalogPricing = $pricing.catalogPricing
                tags        = @($tags)
            })
        }
    }

    $presetOut = @()
    foreach ($pr in @($PresetInfo)) {
        $presetOut += [pscustomobject]@{
            name       = $pr.Name
            path       = $pr.Path
            modelCount = @($presetModelMap[$pr.Name]).Count
        }
    }

    return [pscustomobject]@{
        '$schema'    = 'https://raw.githubusercontent.com/son8x/ModelCompass/main/model-bank/schema.json'
        version      = '1.0.0'
        exportedAt   = (Get-Date).ToString('o')
        generatedBy  = 'Export-ModelBank.ps1'
        sourceConfig = $SourceConfig
        providers    = @($provList)
        models       = @($modelList)
        presets      = @($presetOut)
        stats        = [pscustomobject]@{
            providers = $provList.Count
            models    = $modelList.Count
            presets   = @($PresetInfo).Count
        }
    }
}

# ═══ Chạy chính ═══════════════════════════════════════════════
if ($skipRunFlag) { return }

$repo = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $cfgDir  = if ($ConfigMode -eq 'prod') { 'production' } else { 'development' }
    $cfgFile = if ($ConfigMode -eq 'prod') { 'json' } else { 'jsonc' }
    $ConfigPath = Join-Path $repo "configs\$cfgDir\opencode.$cfgFile"
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy file cấu hình: $ConfigPath"
    exit 2
}
if ([string]::IsNullOrWhiteSpace($OutDir))        { $OutDir = Join-Path $repo 'model-bank' }
if ([string]::IsNullOrWhiteSpace($PresetsDir))    { $PresetsDir = Join-Path $repo 'configs\presets' }
if ([string]::IsNullOrWhiteSpace($CatalogsDir))   { $CatalogsDir = Join-Path $repo 'docs\catalogs' }

Write-Step "Export Model Bank: $ConfigMode  ($ConfigPath)"

$cfgObj = Get-ConfigContent $ConfigPath
if ($null -eq $cfgObj.provider) {
    Write-Fail 'Cấu hình không có mục "provider".'
    exit 1
}

# Nạp catalog theo registry (chỉ những file có sẵn).
$catalogs = @{}
if (Test-Path -LiteralPath $CatalogsDir -PathType Container) {
    foreach ($reg in @($Providers)) {
        $catFile = Join-Path $CatalogsDir ($reg.Id + '.json')
        if (Test-Path -LiteralPath $catFile -PathType Leaf) {
            $catalogs[$reg.Id] = (Get-Content -LiteralPath $catFile -Raw -Encoding utf8 | ConvertFrom-Json)
        }
    }
}

# Presets: đọc từng file (JSONC), không cần env.
$presetInfo = @()
if (Test-Path -LiteralPath $PresetsDir -PathType Container) {
    foreach ($pf in @(Get-ChildItem -LiteralPath $PresetsDir -Filter '*.jsonc' -File)) {
        $obj = $null
        try {
            $raw = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $pf.FullName -Raw -Encoding utf8)
            $obj = $raw | ConvertFrom-Json
        } catch {
            Write-Warn "Preset '$($pf.Name)' parse lỗi — bỏ qua: $($_.Exception.Message)"
            continue
        }
        if ($null -ne $obj.provider) {
            $presetInfo += [pscustomobject]@{ Name = $pf.BaseName; Path = ("configs/presets/" + $pf.Name); models = $obj.provider }
        }
    }
}

$bank = New-ModelBank -ConfigProvider $cfgObj.provider -Catalogs $catalogs `
    -PresetInfo $presetInfo -ProviderReg @($Providers) -SourceConfig ("configs/" + $cfgDir + "/opencode." + $cfgFile)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outFile = Join-Path $OutDir 'modelbank.json'
$bank | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $outFile -Encoding utf8

Write-Info "Đã xuất: $outFile"
Write-Info "  providers=$($bank.stats.providers)  models=$($bank.stats.models)  presets=$($bank.stats.presets)"
Write-Ok "Model Bank OK."
exit 0