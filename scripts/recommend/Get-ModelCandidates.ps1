#Requires -Version 7
<#
Get-ModelCandidates.ps1 — ModelCompass · tầng 1/3 của "Đề xuất ⭐ xKiro".

THƯ VIỆN hàm thuần (không có khối chạy chính) — dựng DANH SÁCH ỨNG VIÊN từ config + catalog:
  - Get-RecommendationConfigModels : model ĐANG CÓ trong config (free/max) → {Id,Name,Provider,ReleaseDate}
  - Get-CatalogById                : đánh index catalog theo id → tra giá/context
  - New-RecommendationCandidate    : ghép config + catalog → ứng viên (+ suy NHÓM free/L/B/A/S)
  - Get-RecommendationKey          : khoá nội bộ "provider|id"
  - Get-ModelCandidates            : orchestrator (config obj + catalog models → candidates)

POOL = model trong CONFIG (đã qua probe), KHÔNG phải cả catalog ⇒ không đề xuất model chết.
Không gán tag ở tầng này (tag khả năng thuộc Resolve-StarRules.ps1).

PHỤ THUỘC (bên dot-source phải nạp trước):
  - Common-Functions.ps1
  - provider\Update-XKiroModels.ps1 -SkipRun   (Resolve-TierFromName / Resolve-TierFromPrice)
#>
Set-StrictMode -Version Latest

function Get-CatalogById {
    <#
    .SYNOPSIS
        Chuẩn hoá mảng model catalog → hashtable id -> normalized model. THUẦN.
    #>
    param($CatalogModels)
    $byId = @{}
    foreach ($m in @($CatalogModels)) {
        if ($null -ne $m -and -not [string]::IsNullOrWhiteSpace([string]$m.id)) { $byId[[string]$m.id] = $m }
    }
    return $byId
}

function Get-RecommendationConfigModels {
    <#
    .SYNOPSIS
        Đọc model hiện có của các provider xKiro trong config → @{Id, Name, Provider, ReleaseDate}.
        THUẦN (nhận object config đã parse).
    #>
    param($ConfigObj, [string[]]$ProviderKeys)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $ConfigObj -or $null -eq $ConfigObj.provider) { return @() }
    foreach ($key in @($ProviderKeys)) {
        $cp = $ConfigObj.provider.PSObject.Properties[$key]
        if ($null -eq $cp -or $null -eq $cp.Value) { continue }
        $modelsProp = $cp.Value.PSObject.Properties['models']
        if ($null -eq $modelsProp -or $null -eq $modelsProp.Value) { continue }
        foreach ($prop in @($modelsProp.Value.PSObject.Properties)) {
            $out.Add([pscustomobject]@{
                Id          = $prop.Name
                Name        = [string]$prop.Value.name
                Provider    = $key
                ReleaseDate = [string]$prop.Value.release_date
            })
        }
    }
    return @($out)
}

function Get-RecommendationKey {
    <#
    .SYNOPSIS
        Khoá nội bộ cho 1 entry config: provider + id.
        (Cùng model-id có thể nằm ở cả 1-xkiro-free lẫn 2-xkiro-max → phải tách theo provider.) THUẦN.
    #>
    param([string]$Provider, [string]$ModelId)
    return ("{0}|{1}" -f $Provider, $ModelId)
}

function Read-HealthReportMap {
    <#
    .SYNOPSIS
        Đọc reports/model-health.json → hashtable "provider|id" -> class. THUẦN.
        Trả hashtable rỗng nếu file không tồn tại.
    #>
    param([string]$Path)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $map }
    $obj = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($m in @($obj.models)) {
        if ($null -eq $m) { continue }
        $p = [string]$m.provider; $id = [string]$m.id
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not [string]::IsNullOrWhiteSpace($id)) {
            $map[(Get-RecommendationKey -Provider $p -ModelId $id)] = [string]$m.class
        }
    }
    return $map
}

function New-RecommendationCandidate {
    <#
    .SYNOPSIS
        Ghép model config với catalog (giá/ctx) + suy NHÓM → ứng viên đề xuất. THUẦN.
        Nhóm: free provider → 'free'; max → tag [L/B/A/S] trong name, không có thì theo giá input.
        HealthMap (tuỳ chọn) gán HealthClass để rule ưu tiên model còn sống.
        KHÔNG gán tag khả năng (Resolve-StarRules.ps1 lo).
    #>
    param($ConfigModels, $CatalogById, $HealthMap = @{})
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($cm in @($ConfigModels)) {
        $isFree = ($cm.Provider -eq '1-xkiro-free')
        $cat = $CatalogById[$cm.Id]
        $ctx = 0; $in = $null; $outP = $null
        if ($null -ne $cat) {
            $ctxProp = $cat.PSObject.Properties['context']
            if ($null -ne $ctxProp -and $null -ne $ctxProp.Value) { $ctx = [int]$ctxProp.Value }
            $prProp = $cat.PSObject.Properties['pricing']
            if ($null -ne $prProp -and $null -ne $prProp.Value) {
                $inProp = $prProp.Value.PSObject.Properties['input']
                if ($null -ne $inProp) { $in = $inProp.Value }
                $outProp = $prProp.Value.PSObject.Properties['output']
                if ($null -ne $outProp) { $outP = $outProp.Value }
            }
        }
        if ($isFree) {
            $group = 'free'
        } else {
            $group = Resolve-TierFromName $cm.Name
            if (-not $group) {
                $group = if ($null -ne $in) { Resolve-TierFromPrice -InputPrice $in } else { 'L' }
            }
        }
        $hKey = Get-RecommendationKey -Provider $cm.Provider -ModelId $cm.Id
        $health = if ($HealthMap.ContainsKey($hKey)) { [string]$HealthMap[$hKey] } else { '' }
        $out.Add([pscustomobject]@{
            Id          = $cm.Id
            Name        = $cm.Name
            Provider    = $cm.Provider
            ReleaseDate = $cm.ReleaseDate
            Group       = $group
            Context     = $ctx
            In          = $in
            Out         = $outP
            HealthClass = $health
        })
    }
    return @($out)
}

function Get-ModelCandidates {
    <#
    .SYNOPSIS
        Orchestrator tầng 1: config obj + catalog models → bộ ứng viên + chỉ mục phụ trợ. THUẦN.
        HealthReportPath (tuỳ chọn) để gán HealthClass từ reports/model-health.json.
        Trả { CatalogById; ConfigModels; Candidates }.
    #>
    param($ConfigObj, $CatalogModels, [string[]]$ProviderKeys, [string]$HealthReportPath)
    $catalogById = Get-CatalogById -CatalogModels $CatalogModels
    $configModels = Get-RecommendationConfigModels -ConfigObj $ConfigObj -ProviderKeys $ProviderKeys
    $healthMap = Read-HealthReportMap -Path $HealthReportPath
    $candidates = New-RecommendationCandidate -ConfigModels $configModels -CatalogById $catalogById -HealthMap $healthMap
    return [pscustomobject]@{
        CatalogById  = $catalogById
        ConfigModels = $configModels
        Candidates   = @($candidates)
    }
}
