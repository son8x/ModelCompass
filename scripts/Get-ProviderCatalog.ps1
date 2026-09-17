#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Tải catalog model (GET /v1/models) của các provider về dạng JSON chuẩn
    rồi đối chiếu với config production — phát hiện model thiếu / biến mất / đổi tên.

.DESCRIPTION
    Cho mỗi provider (xKiro, Teamo, OpenRouter, OmniRoute local, 9Router local):
      - Gọi `GET {base}/v1/models` (OpenAI-compatible) với key từ env.
      - Chuẩn hoá mỗi model: id, context, pricing (input/output/request, nếu endpoint cung cấp), modality.
      - Xuất bản "latest" vào `docs/catalogs/<provider>.json` (theo dõi được bằng git diff)
        và snapshot đầy đủ (raw + normalized) vào `reports/catalogs/<provider>-<timestamp>.json` (gitignore).
      - So với config production: model trong config NHƯNG vắng trong catalog (nguy cơ 404),
        model trong catalog NHƯNG chưa khai báo (thông tin), gợi ý near-match khi đổi tên/`:free`.

    Provider local (OmniRoute/9Router) không bật sẽ BỊ BỎ QUA (cảnh báo) — không làm fail run.

.PARAMETER Provider
    Chạy cho một subset provider (mặc định: tất cả). Nhận: xkiro, teamo, openrouter, omniroute, 9router.

.PARAMETER ConfigMode
    File config dùng để so sánh: 'prod' (configs/production/opencode.json) hoặc 'dev' (development).
    Mặc định: prod — đây là bản thực tế đang dùng.

.PARAMETER ConfigPath
    Ghi đè đường dẫn file config so sánh (bỏ qua -ConfigMode).

.PARAMETER NoSave
    Không ghi file catalog (chỉ in ra console).

.PARAMETER NoCompare
    Không so sánh với config (chỉ lấy catalog + lưu file).

.PARAMETER NoSnapshots
    Không ghi snapshot đầy đủ vào reports/catalogs/ (chỉ ghi bản latest).

.PARAMETER FailOnMissing
    Exit code 1 nếu có model đã cấu hình nhưng vắng trong catalog (dùng cho CI/thủ công kiểm tra).

.PARAMETER ShowAllNew
    Liệt kê toàn bộ model "mới" (có trong catalog, chưa khai báo) thay vì chỉ số lượng + top.

.PARAMETER MaxNew
    Số model "mới" hiển thị mẫu khi không dùng -ShowAllNew (mặc định 5, 0 = không hiển thị).

.EXAMPLE
    pwsh scripts/Get-ProviderCatalog.ps1
    pwsh scripts/Get-ProviderCatalog.ps1 -Provider xkiro -FailOnMissing
    pwsh scripts/Get-ProviderCatalog.ps1 -NoCompare -NoSnapshots
#>
[CmdletBinding()]
param(
    [string[]]$Provider,
    [ValidateSet('prod', 'dev')][string]$ConfigMode = 'prod',
    [string]$ConfigPath,
    [switch]$NoSave,
    [switch]$NoCompare,
    [switch]$NoSnapshots,
    [switch]$FailOnMissing,
    [switch]$ShowAllNew,
    [int]$MaxNew = 5,
    [switch]$SkipRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

# ───────────────────────────────────────────────
# Registry provider: ai nào gọi endpoint nào, cấu hình trong config provider nào.
# ───────────────────────────────────────────────
$Providers = @(
    @{
        Id             = 'xkiro'
        Display        = 'xKiro (api.xkiro.com)'
        BaseUrl        = 'https://api.xkiro.com/v1'
        KeyEnv         = 'XTROUTER_API_KEY'
        KeyRequired    = $true
        ConfigProviders = @('1-xkiro-free', '2-xkiro-max')
        IdStripPrefix  = @()
    },
    @{
        Id             = 'teamo'
        Display        = 'TeamoRouter (api.teamorouter.cn)'
        BaseUrl        = 'https://api.teamorouter.cn/v1'
        KeyEnv         = 'TEAMO_API_KEY'
        KeyRequired    = $true
        ConfigProviders = @('6-teamoRouter')
        IdStripPrefix  = @()
    },
    @{
        Id             = 'openrouter'
        Display        = 'OpenRouter (openrouter.ai)'
        BaseUrl        = 'https://openrouter.ai/api/v1'
        KeyEnv         = 'OMNIROUTE_KEY'
        KeyRequired    = $false
        ConfigProviders = @('4-openrouter-free')
        # Gateway local thêm tiền tố 'openrouter/' vào id — catalog live KHÔNG có.
        IdStripPrefix  = @('openrouter/')
    },
    @{
        Id             = 'omniroute'
        Display        = 'OmniRoute local (127.0.0.1:20217)'
        BaseUrl        = 'http://127.0.0.1:20217/v1'
        KeyEnv         = 'OMNIROUTE_KEY'
        KeyRequired    = $true
        ConfigProviders = @('3-omniroute-free', '4-openrouter-free')
        IdStripPrefix  = @()
    },
    @{
        Id             = '9router'
        Display        = '9Router local (127.0.0.1:20128)'
        BaseUrl        = 'http://127.0.0.1:20128/v1'
        KeyEnv         = 'NINE_ROUTER_API_KEY'
        KeyRequired    = $true
        ConfigProviders = @('5-9router')
        IdStripPrefix  = @()
    }
)

# ───────────────────────────────────────────────
# Helper môi trường: ưu tiên Process -> User -> Machine.
# ───────────────────────────────────────────────
function Get-EnvValueAny {
    param([string]$Name)
    foreach ($scope in @(
            [System.EnvironmentVariableTarget]::Process,
            [System.EnvironmentVariableTarget]::User,
            [System.EnvironmentVariableTarget]::Machine
        )) {
        $v = [System.Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
    }
    return $null
}

# ───────────────────────────────────────────────
# Chuẩn hoá 1 model về dạng ổn định (dùng chung cho mọi provider).
# ───────────────────────────────────────────────
function ConvertTo-NormalizedModel {
    <#
    .SYNOPSIS
        Trích các trường chính từ 1 entry model (OpenAI-compatible) về cấu trúc ổn định.
        Pricing diễn giải theo "per 1 triệu token USD" nếu endpoint cung cấp
        (dạng OpenRouter pricing.prompt/completion/request hoặc các tên khác).
    #>
    param($Model)

    if ($null -eq $Model) { return $null }

    $id = $null
    $p = $Model.PSObject.Properties['id']
    if ($null -ne $p -and $null -ne $p.Value) { $id = [string]$p.Value }
    if ([string]::IsNullOrWhiteSpace($id)) {
        $p = $Model.PSObject.Properties['model']
        if ($null -ne $p -and $null -ne $p.Value) { $id = [string]$p.Value }
    }
    if ([string]::IsNullOrWhiteSpace($id)) {
        $p = $Model.PSObject.Properties['name']
        if ($null -ne $p -and $null -ne $p.Value) { $id = [string]$p.Value }
    }
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }

    $context = $null
    foreach ($k in @('context_length', 'context_window', 'context', 'max_context_length', 'max_total_tokens')) {
        $v = $Model.PSObject.Properties[$k]
        if ($null -ne $v -and $null -ne $v.Value) {
            try { $context = [int]$v.Value; break } catch { }
        }
    }

    $input = $null; $output = $null; $request = $null
    $p = $Model.PSObject.Properties['pricing']
    if ($null -ne $p -and $null -ne $p.Value) {
        $pr = $p.Value
        foreach ($pair in @(@('prompt', 'input'), @('completion', 'output'), @('request', 'request'))) {
            $slot = $pr.PSObject.Properties[$pair[0]]
            if ($null -ne $slot -and $null -ne $slot.Value) {
                try { $num = [double]$slot.Value } catch { $num = $null }
                if ($null -ne $num) {
                    switch ($pair[1]) { 'input' { $input = $num } 'output' { $output = $num } 'request' { $request = $num } }
                }
            }
        }
    }
    if ($null -eq $input) {
        foreach ($k in @('input_cost', 'input_price')) {
            $v = $Model.PSObject.Properties[$k]
            if ($null -ne $v -and $null -ne $v.Value) { try { $input = [double]$v.Value; break } catch { } }
        }
    }
    if ($null -eq $output) {
        foreach ($k in @('output_cost', 'output_price')) {
            $v = $Model.PSObject.Properties[$k]
            if ($null -ne $v -and $null -ne $v.Value) { try { $output = [double]$v.Value; break } catch { } }
        }
    }
    if ($null -eq $input -or $null -eq $output) {
        if ($null -ne $p -and $null -ne $p.Value) {
            if ($null -eq $input) {
                $pi = $p.Value.PSObject.Properties['input']
                if ($null -ne $pi -and $null -ne $pi.Value) { try { $input = [double]$pi.Value } catch { } }
            }
            if ($null -eq $output) {
                $po = $p.Value.PSObject.Properties['output']
                if ($null -ne $po -and $null -ne $po.Value) { try { $output = [double]$po.Value } catch { } }
            }
        }
    }
    if ($null -eq $input -or $null -eq $output) {
        $px = $Model.PSObject.Properties['price']
        if ($null -ne $px -and $null -ne $px.Value) {
            $pi = $px.Value.PSObject.Properties['input'];  if ($null -ne $pi -and $null -ne $pi.Value -and $null -eq $input)  { try { $input = [double]$pi.Value } catch { } }
            $po = $px.Value.PSObject.Properties['output']; if ($null -ne $po -and $null -ne $po.Value -and $null -eq $output) { try { $output = [double]$po.Value } catch { } }
        }
    }

    $modality = $null
    $mo = $Model.PSObject.Properties['modality']
    if ($null -ne $mo -and $null -ne $mo.Value) {
        $modIn = @()
        $mi = $mo.Value.PSObject.Properties['input']
        if ($null -ne $mi) { $modIn = @($mi.Value) }
        $modOut = @()
        $mout = $mo.Value.PSObject.Properties['output']
        if ($null -ne $mout) { $modOut = @($mout.Value) }
        $modality = [pscustomobject]@{ input = $modIn; output = $modOut }
    }

    $created = $null
    $cr = $Model.PSObject.Properties['created']
    if ($null -ne $cr -and $null -ne $cr.Value) { try { $created = [long]$cr.Value } catch { } }

    $accessTier = $null
    $at = $Model.PSObject.Properties['access_tier']
    if ($null -ne $at -and $null -ne $at.Value) { $accessTier = [string]$at.Value }

    return [pscustomobject]@{
        id          = $id
        name        = if ($null -ne $Model.PSObject.Properties['name']) { [string]$Model.name } else { '' }
        access_tier = $accessTier
        context     = $context
        pricing     = [pscustomobject]@{ input = $input; output = $output; request = $request }
        modality    = $modality
        created     = $created
    }
}

function ConvertTo-NormalizedCatalog {
    <#
    .SYNOPSIS
        Chuẩn hoá mảng model (hoặc 1 model) về danh sách ổn định, sắp theo id.
    #>
    param([Parameter(Mandatory)][array]$RawModels)
    $out = @()
    foreach ($m in $RawModels) {
        $n = ConvertTo-NormalizedModel $m
        if ($null -ne $n) { $out += $n }
    }
    return @($out | Sort-Object id)
}

# ───────────────────────────────────────────────
# So sánh: config model ids vs catalog ids.
# ───────────────────────────────────────────────
function Compare-ConfigSetToCatalog {
    <#
    .SYNOPSIS
        Đối chiếu bộ id model trong config với bộ id thực tế trả về từ catalog.
        Trả về cấu trúc { Missing, Near, New, Similar }.
          Missing: id trong config KHÔNG có trong catalog (nguy cơ 404).
          Near:    bản đồ id missing -> id thực (giống nhau bỏ hoa thường / hậu tố :free / tiền tố strip).
          New:     id trong catalog nhưng CHƯA khai báo trong config.
          Similar: id missing chưa có near-match -> danh sách id cùng "họ" trong catalog (gợi ý đổi tên).
    #>
    param(
        [Parameter(Mandatory)][string[]]$ConfigIds,
        [Parameter(Mandatory)][string[]]$CatalogIds,
        [string[]]$StripPrefixes = @(),
        [int]$MaxSimilar = 5
    )

    function Resolve-LookupId {
        param([string]$Raw)
        $out = $Raw
        foreach ($pfx in $StripPrefixes) {
            if ($out.StartsWith($pfx)) { $out = $out.Substring($pfx.Length) }
        }
        return $out
    }

    $cat = @{}; $catLower = @{}
    foreach ($ci in $CatalogIds) { $cat[$ci] = $true; $catLower[$ci.ToLowerInvariant()] = $ci }

    $cfgLower = @{}
    foreach ($cf in $ConfigIds) { $cfgLower[(Resolve-LookupId $cf).ToLowerInvariant()] = $true }

    $missing = @()
    foreach ($cf in $ConfigIds) {
        if (-not $cat.ContainsKey((Resolve-LookupId $cf))) { $missing += $cf }
    }

    $near = @{}
    $nearTargets = @{}
    foreach ($mf in $missing) {
        $lookup = Resolve-LookupId $mf
        $match = $null
        if ($catLower.ContainsKey($lookup.ToLowerInvariant())) {
            $match = $catLower[$lookup.ToLowerInvariant()]
        } else {
            $stripped = ($lookup -replace ':free$', '')
            if ($catLower.ContainsKey($stripped.ToLowerInvariant())) { $match = $catLower[$stripped.ToLowerInvariant()] }
        }
        if ($match) { $near[$mf] = $match; $nearTargets[$match] = $true }
    }

    $similar = @{}
    foreach ($mf in $missing) {
        if ($near.ContainsKey($mf)) { continue }
        $lookup = (Resolve-LookupId $mf).ToLowerInvariant()
        $seg = $lookup.Split('/')
        # "cùng họ" = mọi segment trừ segment cuối (tên model): deepseek/... hay cfp/zai-org/...
        $family = if ($seg.Count -ge 2) {
            @($seg[0..($seg.Count - 2)] | ForEach-Object { $_.ToLowerInvariant() }) -join '/'
        } else { $lookup }
        $cands = @( $CatalogIds | Where-Object {
                $_.ToLowerInvariant() -ne $lookup -and $_.ToLowerInvariant().StartsWith($family)
            } | Select-Object -First $MaxSimilar)
        if ($cands.Count -gt 0) { $similar[$mf] = @($cands) }
    }

    $new = @( $CatalogIds | Where-Object {
            -not $cfgLower.ContainsKey($_.ToLowerInvariant()) -and -not $nearTargets.ContainsKey($_)
        } )

    return [pscustomobject]@{
        Missing = $missing
        Near    = $near
        Similar = $similar
        New     = $new
    }
}

# ───────────────────────────────────────────────
# Các hàm chạy chính
# ───────────────────────────────────────────────
function Get-CatalogRaw {
    param([hashtable]$Prov)
    $key = Get-EnvValueAny $Prov.KeyEnv
    if ($Prov.KeyRequired -and [string]::IsNullOrWhiteSpace($key)) {
        Write-Warn ("BỎ QUA '{0}': thiếu biến {1}" -f $Prov.Id, $Prov.KeyEnv)
        return $null, "missing-key"
    }
    if ($Prov.Id -eq 'openrouter' -and $key -and -not $key.StartsWith('sk-or-')) {
        $key = $null  # endpoint public, không gửi key sai dạng
    }
    $headers = @{ Accept = 'application/json' }
    if ($key) { $headers['Authorization'] = "Bearer $key" }

    try {
        $resp = Invoke-RestMethod -Method Get -Uri "$($Prov.BaseUrl)/models" -Headers $headers -TimeoutSec 60
    } catch {
        Write-Warn ("LỖI '{0}': {1}" -f $Prov.Id, $_.Exception.Message)
        return $null, "error"
    }

    $rows = $null
    if ($resp -is [System.Array]) { $rows = @($resp) }
    elseif ($null -ne $resp) {
        foreach ($k in @('data', 'models', 'model', 'result')) {
            $v = $resp.PSObject.Properties[$k]
            if ($null -ne $v -and $null -ne $v.Value) { $rows = @($v.Value); break }
        }
    }
    if ($null -eq $rows -or $rows.Count -eq 0) {
        Write-Warn ("PHẢN HỒI TRỐNG '{0}' — không phân tích được payload (xem snapshot nếu có)" -f $Prov.Id)
        return $null, "empty"
    }
    return $rows, $null
}

function Resolve-ConfigFilePath {
    $repoRoot = Get-RepoRoot
    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "Không tìm thấy file cấu hình: $ConfigPath"
        }
        return (Get-Item -LiteralPath $ConfigPath).FullName
    }
    if ($ConfigMode -eq 'dev') {
        return (Join-Path $repoRoot 'configs/development/opencode.jsonc')
    }
    return (Join-Path $repoRoot 'configs/production/opencode.json')
}

# ───────────────────────────────────────────────
# Chạy
# ───────────────────────────────────────────────
# -SkipRun: chỉ nạp định nghĩa function + registry (dùng cho test dot-source), không gọi mạng.
if ($SkipRun) { return }

$repoRoot = Get-RepoRoot
if ($NoSave) { $NoSnapshots = $true }

$selected = @($Providers)
if ($Provider -and $Provider.Count -gt 0) {
    $selected = @($Providers | Where-Object { $Provider -contains $_.Id })
    if ($selected.Count -eq 0) {
        Write-Fail "Không có provider nào khớp: $($Provider -join ', ') (chấp nhận: $($Providers.Id -join ', '))"
        exit 2
    }
}

# Load config 1 lần nếu cần so sánh
$config = $null
if (-not $NoCompare) {
    $cfgPath = Resolve-ConfigFilePath
    Write-Step ("LOAD CONFIG ({0})" -f (Split-Path $cfgPath -Leaf))
    $config = Get-ConfigContent $cfgPath
    Write-Ok ("Đã đọc {0} provider từ config" -f @($config.provider.PSObject.Properties).Count)
}

$totalMissing = @()
foreach ($prov in $selected) {
    Write-Step ("CATALOG: {0}  [{1}/models]" -f $prov.Display, $prov.BaseUrl)

    $rows, $err = Get-CatalogRaw $prov
    if ($null -eq $rows) { continue }

    $models = ConvertTo-NormalizedCatalog @($rows)
    if ($models.Count -eq 0) {
        Write-Warn "Không chuẩn hoá được model nào — payload lạ?"
        continue
    }
    $withPrice = @($models | Where-Object { $null -ne $_.pricing.input -or $null -ne $_.pricing.output })
    $withCtx   = @($models | Where-Object { $null -ne $_.context })
    Write-Ok   ("{0} model | có pricing: {1} | có context: {2}" -f $models.Count, $withPrice.Count, $withCtx.Count)

    # Lưu file
    if (-not $NoSave) {
        $catalogDir   = Join-Path $repoRoot 'docs/catalogs'
        $snapshotDir  = Join-Path $repoRoot 'reports/catalogs'
        New-Item -ItemType Directory -Force -Path $catalogDir, $snapshotDir | Out-Null

        $latest = [ordered]@{
            fetched_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            provider   = $prov.Id
            source     = "$($prov.BaseUrl)/models"
            count      = $models.Count
            models     = $models
        }
        $latestPath = Join-Path $catalogDir "$($prov.Id).json"
        try {
            $latest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestPath -Encoding utf8
            Write-Info "latest -> $latestPath"
        } catch {
            Write-Warn "Ghi latest thất bại: $($_.Exception.Message)"
        }

        if (-not $NoSnapshots) {
            $snapPath = Join-Path $snapshotDir ("{0}-{1}.json" -f $prov.Id, (Get-Timestamp))
            try {
                @{ fetched_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); provider = $prov.Id; raw = $rows; models = $models } |
                    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $snapPath -Encoding utf8
                Write-Info "snapshot -> $snapPath"
            } catch {
                Write-Warn "Ghi snapshot thất bại: $($_.Exception.Message)"
            }
        }
    }

    # So sánh với config
    if (-not $NoCompare -and $null -ne $config) {
        foreach ($cpKey in $prov.ConfigProviders) {
            $cp = $config.provider.PSObject.Properties[$cpKey]
            if ($null -eq $cp -or $null -eq $cp.Value) { continue }
            $cfgIds = @($cp.Value.models.PSObject.Properties | ForEach-Object { $_.Name })
            $cmp = Compare-ConfigSetToCatalog -ConfigIds $cfgIds -CatalogIds @($models | ForEach-Object { $_.id }) `
                -StripPrefixes @($prov.IdStripPrefix) -MaxSimilar 5

            $present = $cfgIds.Count - $cmp.Missing.Count
            Write-Host ''
            Write-Info ("[{0}] cấu hình: {1} model | có trong catalog: {2} | thiếu: {3} | mới chưa khai báo: {4}" -f `
                    $cpKey, $cfgIds.Count, $present, $cmp.Missing.Count, $cmp.New.Count)

            foreach ($mf in $cmp.Missing) {
                if ($cmp.Near.ContainsKey($mf)) {
                    Write-Warn ("  MISS  {0}   → có thể chính là  '{1}'" -f $mf, $cmp.Near[$mf])
                } else {
                    Write-Warn ("  MISS  {0}" -f $mf)
                    if ($cmp.Similar.ContainsKey($mf)) {
                        Write-Warn ("        cùng họ: {0}" -f (($cmp.Similar[$mf]) -join ' | '))
                    }
                }
            }
            $totalMissing += @( $cmp.Missing | Where-Object { -not $cmp.Near.ContainsKey($_) } )

            $newShown = if ($ShowAllNew) { $cmp.New } else { @($cmp.New | Select-Object -First ([Math]::Max(0, $MaxNew))) }
            foreach ($nid in $newShown) {
                Write-Host ("  NEW   {0}" -f $nid) -ForegroundColor DarkGray
            }
            if (-not $ShowAllNew -and $MaxNew -gt 0 -and $cmp.New.Count -gt $MaxNew) {
                Write-Host ("        ... còn {0} model mới nữa (-ShowAllNew để xem hết)" -f ($cmp.New.Count - $MaxNew)) -ForegroundColor DarkGray
            }
        }
    }
}

Write-Step 'KẾT QUẢ'
if (-not $NoCompare) {
    $prev = $totalMissing.Count
    if ($prev -gt 0) {
        Write-Warn "Có $prev model đã cấu hình KHÔNG nằm trong catalog live (nguy cơ 404/đổi tên)."
    } else {
        $checked = 0
        foreach ($prov in $selected) { $checked += @($prov.ConfigProviders).Count }
        Write-Ok "Toàn bộ model đã cấu hình đều khớp catalog live."
    }
} else {
    Write-Info "(-NoCompare) Bỏ qua bước đối chiếu config."
}

if ($FailOnMissing -and $totalMissing.Count -gt 0) {
    Write-Fail "FailOnMissing: phát hiện $($totalMissing.Count) model thiếu."
    exit 1
}
exit 0