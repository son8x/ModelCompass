#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: So sánh giá model trong config (nhồi trong `name`) vs catalog live.

.DESCRIPTION
    Các provider xKiro nhồi giá vào `name` mỗi model (vd `In:$1.40 | Out:$4.40`).
    Script này đối chiếu từng model đã khai báo với catalog live (docs/catalogs/)
    để phát hiện giá ĐÃ ĐỔI (config cũ → hiển thị gây hiểu lầm) và GỢI Ý tên mới.

    So sánh theo ID (tôn trọng strip tiền tố gateway như `openrouter/`). Model:
        - Có giá trong `name` + có giá trong catalog  -> so chênh lệch ($ và %)
        - Không có giá trong `name`                    -> bỏ qua (info)
        - Có trong config nhưng vắng trong catalog     -> cảnh báo (nguy cơ 404/đổi tên)
        - Có trong catalog nhưng catalog không có giá  -> bỏ qua (info)

    Mặc định chỉ IN RA. Dùng -Report để ghi reports/, -FailOnDiff để exit 1 khi có chênh lệch.

.PARAMETER ConfigMode
    File config so sánh: 'prod' (mặc định) hoặc 'dev'.

.PARAMETER ConfigPath
    Ghi đè đường dẫn file config (bỏ qua -ConfigMode).

.PARAMETER CatalogsDir
    Thư mục chứa catalog live (mặc định: docs/catalogs).

.PARAMETER IdStripPrefix
    Không cần thiết (lấy từ registry provider). Giữ entry để ghi đè khi cần.

.PARAMETER MinDiffPct
    Bỏ qua chênh lệch nhỏ hơn X% (mặc định 0 = báo mọi chênh lệch).

.PARAMETER ShowAll
    Liệt kê cả model "ok" và "không có giá trong name" (mặc định chỉ đếm).

.PARAMETER Report
    Ghi báo cáo Markdown vào reports\price-diff-<timestamp>.md.

.PARAMETER FailOnDiff
    Có chênh lệch giá >= 1 -> exit 1 (dùng làm chốt cứng/CI).

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function (dùng cho test dot-source), không chạy.

.EXAMPLE
    pwsh scripts/Compare-Prices.ps1                       # báo chênh lệch so với prod
    pwsh scripts/Compare-Prices.ps1 -ConfigMode dev       # so với development
    pwsh scripts/Compare-Prices.ps1 -ShowAll -Report
#>
[CmdletBinding()]
param(
    [ValidateSet('prod', 'dev')][string]$ConfigMode = 'prod',
    [string]$ConfigPath,
    [string]$CatalogsDir,
    [string]$IdStripPrefix,
    [double]$MinDiffPct = 0,
    [switch]$ShowAll,
    [switch]$Report,
    [switch]$FailOnDiff,
    [switch]$SkipRun
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

# Chụp cờ SkipRun TRƯỚC khi dot-source Get-ProviderCatalog: dot-source script có param
# cùng tên sẽ GHI ĐÈ variable vào scope hiện tại (quirk PowerShell) — làm mất cờ gốc.
$skipRunFlag = [bool]$SkipRun

# Tái dùng registry provider (Id, Display, ConfigProviders, IdStripPrefix) — không gọi mạng.
. (Join-Path $PSScriptRoot 'Get-ProviderCatalog.ps1') -SkipRun

# ═══════════════════════════════════════════════════════════════
# Các hàm thuần (test bằng dot-source -SkipRun)
# ═══════════════════════════════════════════════════════════════

function Get-PricesFromName {
    <#
    Trích giá `In:$X | Out:$Y` từ name model config. Trả Has=$false nếu không có.
    #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [pscustomobject]@{ Has = $false; In = $null; Out = $null }
    }
    $m = [regex]::Match($Name, 'In:\s*\$([0-9]+(?:\.[0-9]+)?)\s*\|\s*Out:\s*\$([0-9]+(?:\.[0-9]+)?)')
    if (-not $m.Success) {
        return [pscustomobject]@{ Has = $false; In = $null; Out = $null }
    }
    return [pscustomobject]@{
        Has = $true
        In  = [double]$m.Groups[1].Value
        Out = [double]$m.Groups[2].Value
    }
}

function Format-Price {
    <#
    Định dạng giá catalog về kiểu quen thuộc trong config: 0.05 / 9.00 / 0.285.
    #>
    param([AllowNull()][AllowEmptyString()]$Value)
    if ($null -eq $Value) { return '' }
    $p = [double]$Value
    if ([math]::Abs($p - [math]::Round($p, 2)) -gt 1e-9) {
        return $p.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $p.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Update-PricesInName {
    <#
    Thay giá cũ trong `name` bằng giá mới, giữ nguyên phần còn lại của mô tả.
    Không tìm thấy chuỗi `In:$.. | Out:$..` -> trả về nguyên bản.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][double]$In,
        [Parameter(Mandatory)][double]$Out
    )
    $pat = 'In:\s*\$[0-9]+(?:\.[0-9]+)?\s*\|\s*Out:\s*\$[0-9]+(?:\.[0-9]+)?'
    if (-not [regex]::IsMatch($Name, $pat)) { return $Name }
    $new = 'In:${0} | Out:${1}' -f (Format-Price $In), (Format-Price $Out)
    return [regex]::Replace($Name, $pat, $new)
}

function Compare-ConfigModelsToCatalogPrices {
    <#
    Đối chiếu từng model config (giá trong `name`) với catalog live.
    ConfigModels : PSCustomObject: key model -> { name, ... } (giống provider.models).
    CatalogModels: array chuẩn hoá (ConvertTo-NormalizedModel) — có .id, .pricing.
    StripPrefixes: tiền tố gateway cần bỏ khỏi id config khi tra catalog (vd 'openrouter/').

    Trả về array row:
        Model, Name, State, CfgIn, CfgOut, CatIn, CatOut, DiffIn, DiffOut, PctIn, PctOut, SuggestedName
    State: 'ok' | 'diff' | 'no-name-price' | 'no-catalog-price' | 'no-catalog'
    #>
    param(
        [Parameter(Mandatory)]$ConfigModels,
        [Parameter(Mandatory)]$CatalogModels,
        [string[]]$StripPrefixes = @()
    )
    $byId = @{}
    foreach ($cm in @($CatalogModels)) {
        if ($null -ne $cm.id) { $byId[$cm.id] = $cm }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in $ConfigModels.PSObject.Properties) {
        $model    = $prop.Name
        $name     = [string]($prop.Value.name)
        $pName    = Get-PricesFromName $name

        $lookup = $model
        foreach ($pre in $StripPrefixes) {
            if (-not [string]::IsNullOrWhiteSpace($pre) -and $lookup.StartsWith($pre, [System.StringComparison]::OrdinalIgnoreCase)) {
                $lookup = $lookup.Substring($pre.Length)
                break
            }
        }

        $cat = $byId[$lookup]
        $row = [pscustomobject]@{
            Model          = $model
            Name           = $name
            State          = ''
            CfgIn          = $null
            CfgOut         = $null
            CatIn          = $null
            CatOut         = $null
            DiffIn         = $null
            DiffOut        = $null
            PctIn          = $null
            PctOut         = $null
            SuggestedName  = $null
        }

        if ($null -eq $cat) {
            $row.State = 'no-catalog'
        } elseif ($null -eq $cat.pricing.input -or $null -eq $cat.pricing.output) {
            $row.State = 'no-catalog-price'
            $row.CatIn = $cat.pricing.input
            $row.CatOut = $cat.pricing.output
        } elseif (-not $pName.Has) {
            $row.State = 'no-name-price'
            $row.CatIn = $cat.pricing.input
            $row.CatOut = $cat.pricing.output
        } else {
            $row.CfgIn  = $pName.In
            $row.CfgOut = $pName.Out
            $row.CatIn  = $cat.pricing.input
            $row.CatOut = $cat.pricing.output
            $row.DiffIn  = [math]::Round(([double]$row.CatIn - $row.CfgIn), 6)
            $row.DiffOut = [math]::Round(([double]$row.CatOut - $row.CfgOut), 6)
            if ($row.CfgIn  -gt 0) { $row.PctIn  = [math]::Round(($row.DiffIn  / $row.CfgIn)  * 100, 4) }
            if ($row.CfgOut -gt 0) { $row.PctOut = [math]::Round(($row.DiffOut / $row.CfgOut) * 100, 4) }
            if ([math]::Abs([double]$row.DiffIn) -lt 1e-9 -and [math]::Abs([double]$row.DiffOut) -lt 1e-9) {
                $row.State = 'ok'
            } else {
                $row.State = 'diff'
                $row.SuggestedName = Update-PricesInName -Name $name -In ([double]$row.CatIn) -Out ([double]$row.CatOut)
            }
        }
        $rows.Add($row)
    }
    return $rows
}

if ($skipRunFlag) { return }

# ═══════════════════════════════════════════════════════════════
# Chạy chính
# ═══════════════════════════════════════════════════════════════

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
if ([string]::IsNullOrWhiteSpace($CatalogsDir)) {
    $CatalogsDir = Join-Path $repo 'docs\catalogs'
}

Write-Step "Compare-Prices: $ConfigMode  ($ConfigPath)"

$cfgObj = Get-ConfigContent $ConfigPath

$diffRows  = [System.Collections.Generic.List[object]]::new()
$provCount = 0

foreach ($prov in @($Providers)) {
    $catFile = Join-Path $CatalogsDir ($prov.Id + '.json')
    if (-not (Test-Path -LiteralPath $catFile -PathType Leaf)) {
        Write-Info "[$($prov.Id)] không có catalog '$catFile' — bỏ qua."
        continue
    }
    $strip = if ($PSBoundParameters.ContainsKey('IdStripPrefix') -and -not [string]::IsNullOrWhiteSpace($IdStripPrefix)) {
        @($IdStripPrefix)
    } else {
        @(@($prov.IdStripPrefix))
    }

    foreach ($cpKey in @($prov.ConfigProviders)) {
        $cp = $cfgObj.provider.$cpKey
        if ($null -eq $cp -or $null -eq $cp.models) { continue }

        $catalog = Get-Content -LiteralPath $catFile -Raw -Encoding utf8 | ConvertFrom-Json
        $rows = Compare-ConfigModelsToCatalogPrices -ConfigModels $cp.models -CatalogModels @($catalog.models) -StripPrefixes $strip

        $nDiff    = @($rows | Where-Object State -eq 'diff').Count
        $nOk      = @($rows | Where-Object State -eq 'ok').Count
        $nNoName  = @($rows | Where-Object State -eq 'no-name-price').Count
        $nNoCatPr = @($rows | Where-Object State -eq 'no-catalog-price').Count
        $nNoCat   = @($rows | Where-Object State -eq 'no-catalog').Count
        $provCount++

        Write-Step "Provider: $cpKey  ->  catalog $($prov.Display)"
        Write-Host "  info : tổng $($rows.Count) model | OK $nOk | chênh lệch $nDiff | không có giá trong name $nNoName | catalog không giá $nNoCatPr | vắng trong catalog $nNoCat"

        foreach ($r in @($rows | Where-Object State -eq 'diff')) {
            $pctTxt = if ($null -ne $r.PctIn -or $null -ne $r.PctOut) {
                '({0:+#0.##;-#0.##;+0}% / {1:+#0.##;-#0.##;+0}%)' -f ([double]($r.PctIn ?? 0)), ([double]($r.PctOut ?? 0))
            } else { '' }
            Write-Warn "  [CHÊNH] $($r.Model): config In:`$$(Format-Price $r.CfgIn) / Out:`$$(Format-Price $r.CfgOut)  ->  live In:`$$(Format-Price $r.CatIn) / Out:`$$(Format-Price $r.CatOut)  $pctTxt"
            Write-Host "        gợi ý name: $($r.SuggestedName)" -ForegroundColor DarkYellow
            $diffRows.Add($r)
        }
        foreach ($r in @($rows | Where-Object State -eq 'no-catalog')) {
            Write-Warn "  [VẮNG]  $($r.Model) — có trong config NHƯNG không có trong catalog live."
        }
        if ($ShowAll) {
            foreach ($r in @($rows | Where-Object State -in @('ok', 'no-name-price', 'no-catalog-price'))) {
                Write-Info "  [$($r.State)] $($r.Model) (config `$$(Format-Price $r.CfgIn)/`$$(Format-Price $r.CfgOut) | live `$$(Format-Price $r.CatIn)/`$$(Format-Price $r.CatOut))"
            }
        }
    }
}

Write-Step "KẾT QUẢ"
if ($diffRows.Count -eq 0) {
    Write-Ok "Giá model trong config đã khớp catalog live ($provCount provider được so)."
} else {
    Write-Warn "Có $($diffRows.Count) model có giá LỆCH so với catalog live — cập nhật lại \`name\` để trang `/model` không hiển thị giá cũ."
}

if ($Report) {
    $reportDir = Join-Path $repo 'reports'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $file = Join-Path $reportDir ("price-diff-" + (Get-Timestamp) + ".md")
    $lines = @(
        "# ModelCompass — Chênh lệch giá config vs catalog live", ''
        "Ngày: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", ''
        "Config: $ConfigPath", ''
        "Số model chênh lệch: $($diffRows.Count)", ''
    )
    if ($diffRows.Count -gt 0) {
        $lines += '| Model | Config In/Out | Live In/Out | Chênh lệch | Gợi ý name |', '|---|---|---|---|---|'
        foreach ($r in $diffRows) {
            $pct = if ($null -ne $r.PctIn) { '{0:+#0.##;-#0.##;+0}%/{1:+#0.##;-#0.##;+0}%' -f $r.PctIn, $r.PctOut } else { '/' }
            $lines += "| `$($r.Model) | `$$(Format-Price $r.CfgIn)/`$$(Format-Price $r.CfgOut) | `$$(Format-Price $r.CatIn)/`$$(Format-Price $r.CatOut) | $pct | $($r.SuggestedName) |"
        }
    } else {
        $lines += '_Giá khớp hoàn toàn._'
    }
    $lines | Set-Content -LiteralPath $file -Encoding utf8
    Write-Info "Report: $file"
}

if ($FailOnDiff -and $diffRows.Count -gt 0) {
    Write-Fail "Có $($diffRows.Count) model chênh lệch giá (FailOnDiff)."
    exit 1
}
exit 0