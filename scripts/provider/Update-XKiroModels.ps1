#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Tự động đồng bộ 2 provider xKiro (1-xkiro-free, 2-xkiro-max)
    trong dev config với catalog live — thêm model mới dùng được, gỡ model 403/404/biến mất,
    cập nhật giá, sinh release_date, rồi validate. Bật -Publish/-Install để chạy tiếp.

.DESCRIPTION
    Luồng tự động:
      1. Fetch catalog live (GET /v1/models) qua Get-ProviderCatalog.ps1.
      2. Probe TẤT CẢ model tier free+paid (song song) để biết OK / AUTH(403) / NOTFOUND / lỗi tạm.
      3. Đồng bộ vào dev config (.jsonc) — GIỮ NGUYÊN comment/structure xung quanh:
         - 1-xkiro-free: giữ model CÓ trong catalog tier free; gỡ 404/biến mất;
           thêm model free mới probe OK (thêm CUỐI danh sách).
         - 2-xkiro-max:   giữ model probe OK (hoặc lỗi tạm đã có); gỡ 403/404/biến mất;
           thêm model paid mới probe OK; chèn ĐÚNG vị trí nhóm [L]/[B]/[A]/[S]
           (kẹp vào giữa các model cùng nhóm — giữ thứ tự hiển thị hiện có).
      4. release_date: model cũ GIỮ NGUYÊN; model mới sinh date KẸP GIỮA 2 model kề
         (bảo toàn thứ tự sắp xếp opencode date-giảm-dần, giảm diff git).
      5. Validate config bằng Test-ModelCompassConfig.ps1 (-SkipValidation để bỏ qua).
      Kết thúc tại validate. -Publish / -Install chạy tiếp 2 bước promote.

    QUY ƯỚC name model:
      - KHÔNG tự ý đổi name model CŨ — chỉ cập nhật số giá nếu catalog đổi.
      - Model MỚI: sinh name từ id (ConvertTo-FriendlyName) + giá/context catalog
        (free: "Tên đẹp · ctx"; max: "[Tier] Tên đẹp · $In/$Out · ctx").

    Ngưỡng nhóm Max theo giá INPUT (USD/1M), có thể đổi qua tham số:
      [L] < -LThreshold, [B] < -BThreshold, [A] < -AThreshold, còn lại [S].

.PARAMETER ConfigPath
    File config cần cập nhật. Mặc định: configs\development\opencode.jsonc

.PARAMETER Provider
    Chỉ đồng bộ provider nào: '1-xkiro-free', '2-xkiro-max' hoặc cả hai (mặc định).

.PARAMETER NoWrite
    Chỉ BÁO CÁO thay đổi đề xuất, không ghi file.

.PARAMETER NoProbe
    Không gọi mạng probe: coi mọi model trong catalog là OK (chỉ so catalog + giá).

.PARAMETER LThreshold / BThreshold / AThreshold
    Ngưỡng giá Input (USD/1M) cho nhóm [L]/[B]/[A]. Mặc định 0.5 / 1.5 / 4.0.

.PARAMETER ParallelProbes
    Số model probe đồng thời. Mặc định 5.

.PARAMETER TimeoutSeconds
    Timeout mỗi request probe. Mặc định 20.

.PARAMETER Publish
    Sau validate OK, chạy Publish-Config.ps1 (dev -> production).

.PARAMETER Install
    Sau publish, chạy Install-Config.ps1 (global opencode).

.PARAMETER SkipValidation
    Bỏ qua bước validate (không khuyến khích).

.PARAMETER BaselineConfig
    File config làm MỐC để đánh dấu model "mới" (badge 🆕): mọi model đang có
    trong config nhưng KHÔNG có trong baseline sẽ được gắn badge. Dùng để
    hồi tố đánh dấu các model đã thêm từ sync trước (khi badge chưa ra đời).
    Mặc định: trống = chỉ badge model thêm trong chính lần chạy này.

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function cho test (dot-source -SkipRun), không chạy chính.

.EXAMPLE
    pwsh scripts/provider/Update-XKiroModels.ps1 -NoWrite
    pwsh scripts/provider/Update-XKiroModels.ps1
    pwsh scripts/provider/Update-XKiroModels.ps1 -Publish -Install
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$Provider,
    [switch]$NoWrite,
    [switch]$NoProbe,
    [double]$LThreshold = 0.50,
    [double]$BThreshold = 1.50,
    [double]$AThreshold = 4.00,
    [int]$ParallelProbes = 5,
    [int]$TimeoutSeconds = 20,
    [switch]$Publish,
    [switch]$Install,
    [switch]$SkipValidation,
    [string]$BaselineConfig,
    [switch]$SkipRun
)
Set-StrictMode -Version Latest

# Chụp cờ TRƯỚC khi dot-source (quirk PowerShell: dot-source script cùng param sẽ ghi đè).
# Dùng prefix riêng để không trùng biến cờ của các script con (Common-Functions/Get-ProviderCatalog/Compare-Prices).
$uxkSkipRun       = [bool]$SkipRun
$uxkNoWrite       = [bool]$NoWrite
$uxkNoProbe       = [bool]$NoProbe
$uxkConfigPath    = $ConfigPath
$uxkProvider      = @($Provider)
$uxkBaseline      = $BaselineConfig

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
# Registry provider + fetch catalog (không gọi mạng khi -SkipRun).
. (Get-ScriptPath 'Get-ProviderCatalog.ps1') -SkipRun
# Format-Price / Get-PricesFromName / Update-PricesInName.
. (Get-ScriptPath 'Compare-Prices.ps1') -SkipRun

# Khôi phục cờ sau khi dot-source.
$SkipRun          = $uxkSkipRun
$NoWrite          = $uxkNoWrite
$NoProbe          = $uxkNoProbe
$ConfigPath       = $uxkConfigPath
$Provider         = $uxkProvider
$BaselineConfig   = $uxkBaseline

# ═══════════════════════════════════════════════════════════════
# Các hàm thuần (test bằng dot-source -SkipRun) — không gọi mạng
# ═══════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Sinh tên hiển thị thân thiện từ model id xKiro. THUẦN trên chuỗi.
    VD:
      'qwen/qwen3.8-max:free'  -> 'Qwen3.8 Max'
      'deepseek/deepseek-v4-pro' -> 'DeepSeek V4 Pro'
      'anthropic/claude-opus-5.5' -> 'Claude Opus 5.5'
      'google/gemini-3.8-flash' -> 'Gemini 3.8 Flash'
      'openai/gpt-6-sol'        -> 'GPT 6 Sol'
      'z-ai/glm-5.3'            -> 'GLM 5.3'
      'xiaomi/mimo-v2.6-pro'    -> 'MiMo V2.6 Pro'
      'x-ai/grok-4.7'           -> 'Grok 4.7'
    Không thêm tiền tố hãng (khớp quy ước name hiện có: chỉ viết tên model).
#>
function ConvertTo-FriendlyName {
    param([Parameter(Mandatory)][string]$ModelId)

    $namePart = $ModelId
    $slash = $ModelId.IndexOf('/')
    if ($slash -ge 0) { $namePart = $ModelId.Substring($slash + 1) }
    $namePart = $namePart -replace ':free$', ''

    # Tách token theo '-' và viết hoa mỗi token.
    $tokens = @($namePart -split '-')
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t.Length -eq 0) { continue }
        $tokens[$i] = $t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1)
    }
    # Viết hoa/ký hiệu theo "family": token đầu tiên chứa tên hãng.
    if ($tokens.Count -gt 0) {
        $t0 = $tokens[0]
        switch -Regex ($t0) {
            '^Qwen'     { $tokens[0] = 'Qwen' + $t0.Substring(4) }
            '^MiniMax'  { $tokens[0] = 'MiniMax' + $t0.Substring(7) }
            '^DeepSeek' { $tokens[0] = 'DeepSeek' + $t0.Substring(8) }
            '^SenseNova'{ $tokens[0] = 'SenseNova' + $t0.Substring(9) }
            '^Mistral'  { $tokens[0] = 'Mistral' + $t0.Substring(7) }
            '^Ministral'{ $tokens[0] = 'Ministral' + $t0.Substring(9) }
            '^Codestral'{ $tokens[0] = 'Codestral' + $t0.Substring(9) }
            '^Devstral' { $tokens[0] = 'Devstral' + $t0.Substring(8) }
            '^MiMo'     { $tokens[0] = 'MiMo' + $t0.Substring(4) }
            '^GLM'      { $tokens[0] = 'GLM' + $t0.Substring(3) }
            '^Claude'   { $tokens[0] = 'Claude' + $t0.Substring(6) }
            '^Gemini'   { $tokens[0] = 'Gemini' + $t0.Substring(6) }
            '^Grok'     { $tokens[0] = 'Grok' + $t0.Substring(4) }
            '^GPT'      { $tokens[0] = 'GPT' + $t0.Substring(3) }
            '^Nemotron' { $tokens[0] = 'Nemotron' + $t0.Substring(8) }
            '^Llama'    { $tokens[0] = 'Llama' + $t0.Substring(5) }
            '^Opus'     { $tokens[0] = 'Opus' + $t0.Substring(4) }
            '^Sonnet'   { $tokens[0] = 'Sonnet' + $t0.Substring(6) }
            '^Haiku'    { $tokens[0] = 'Haiku' + $t0.Substring(5) }
            '^Flash'    { $tokens[0] = 'Flash' + $t0.Substring(5) }
            '^Turbo'    { $tokens[0] = 'Turbo' + $t0.Substring(5) }
            default     { }
        }
    }
    return ($tokens -join ' ').Trim()
}

<#
.SYNOPSIS
    Đọc nhóm [L]/[B]/[A]/[S] từ name model. Trả $null nếu không có tag.
#>
function Resolve-TierFromName {
    param([string]$Name)
    $m = [regex]::Match($Name, '\[([LBAS])\]')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

<#
.SYNOPSIS
    Xếp nhóm cho model MỚI (MAX) theo giá Input với ngưỡng cho phép.
    Giá $null ($0 hoặc catalog thiếu) -> nhóm 'L' (rẻ nhất thực tế).
#>
function Resolve-TierFromPrice {
    param(
        [AllowNull()]$InputPrice,
        [double]$L = 0.50,
        [double]$B = 1.50,
        [double]$A = 4.00
    )
    if ($null -eq $InputPrice -or [double]$InputPrice -lt $L) { return 'L' }
    if ([double]$InputPrice -lt $B) { return 'B' }
    if ([double]$InputPrice -lt $A) { return 'A' }
    return 'S'
}

<#
.SYNOPSIS
    Sinh name đầy đủ cho model MỚI.
    Free:  không tier, không giá ("Tên đẹp · ctx").
    Max:   "[Tier] Tên đẹp · $In/$Out · ctx".
#>
function New-ModelDisplayName {
    param(
        [Parameter(Mandatory)][string]$FriendlyName,
        [string]$Tier = '',
        [AllowNull()]$In = $null,
        [AllowNull()]$Out = $null,
        [AllowNull()][int]$Context = 0
    )
    $price = ''
    if ($Tier -and $null -ne $In -and $null -ne $Out) {
        $price = " · `$$(Format-Price $In)/`$$(Format-Price $Out)"
    }
    $ctx = ''
    if ($Context -gt 0) {
        $ctx = ' · ' + $(if ($Context -ge 1000000) { '{0:0.#}M' -f ($Context / 1000000) } else { '{0:0.#}K' -f ($Context / 1000) })
    }
    $tierTag = if ($Tier) { "[$Tier] " } else { '' }
    return "$tierTag$FriendlyName$price$ctx"
}

<#
.SYNOPSIS
    Đọc danh sách model hiện tại của 1 provider config -> @{id, name, release_date}.
#>
function Get-ConfigModels {
    param([Parameter(Mandatory)]$ProviderSection)
    if ($null -eq $ProviderSection -or $null -eq $ProviderSection.models) { return @() }
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in @($ProviderSection.models.PSObject.Properties)) {
        $out.Add([pscustomobject]@{
            id           = $prop.Name
            name         = [string]$prop.Value.name
            release_date = [string]$prop.Value.release_date
        })
    }
    return @($out)
}

<#
.SYNOPSIS
    Tính tập giữ/thêm/gỡ cho 1 provider. THUẦN — không gọi mạng.
    ConfigModels : mảng từ Get-ConfigModels.
    CatalogModels: mảng chuẩn hoá (ConvertTo-NormalizedCatalog).
    ProbeResults : hashtable id -> status ('OK'|'AUTH'|'NOTFOUND'|'RATE'|'HTTP'|'TIMEOUT').
    Trả về { Keep, Add, RemoveReason }.
#>
function Compare-ToLive {
    param(
        [Parameter(Mandatory)]$ConfigModels,
        [Parameter(Mandatory)]$CatalogModels,
        [Parameter(Mandatory)][hashtable]$ProbeResults,
        [switch]$IsFree,
        [double]$LThreshold = 0.50,
        [double]$BThreshold = 1.50,
        [double]$AThreshold = 4.00,
        [string]$TierFilter = ''
    )
    $byId = @{}
    foreach ($cm in @($CatalogModels)) { $byId[$cm.id] = $cm }

    $keep   = [System.Collections.Generic.List[object]]::new()
    $add    = [System.Collections.Generic.List[object]]::new()
    $remove = @{}
    $badProbe = @('AUTH', 'NOTFOUND', 'DOWN')

    foreach ($m in @($ConfigModels)) {
        $cat = $byId[$m.id]
        if ($null -eq $cat) {
            $remove[$m.id] = 'biến mất khỏi catalog live'
            continue
        }
        $status = $ProbeResults[$m.id]
        if (-not $IsFree -and $status -in $badProbe) {
            $remove[$m.id] = "probe $status (403/404) — không còn dùng được"
            continue
        }
        if ($IsFree -and $status -eq 'NOTFOUND') {
            $remove[$m.id] = 'probe NOTFOUND — không còn tồn tại'
            continue
        }
        $in = $null; $out = $null; $ctx = 0
        if ($null -ne $cat.pricing) { $in = $cat.pricing.input; $out = $cat.pricing.output }
        if ($null -ne $cat.context) { $ctx = [int]$cat.context }
        $keep.Add([pscustomobject]@{
            id           = $m.id
            name         = $m.name
            release_date = $m.release_date
            CatIn        = $in
            CatOut       = $out
            Context      = $ctx
        })
    }

    $existingIds = @($ConfigModels | ForEach-Object { $_.id })
    foreach ($catId in @($CatalogModels | ForEach-Object { $_.id })) {
        if ($existingIds -contains $catId) { continue }
        $cat = $byId[$catId]
        if ([string]::IsNullOrWhiteSpace($TierFilter)) { $at = '' } else { $at = $cat.access_tier }
        if ($TierFilter -and $at -ne $TierFilter) { continue }
        $status = $ProbeResults[$catId]
        if ($null -eq $status) { $status = 'OK' }   # -NoProbe: coi như OK
        if ($status -notin @('OK', 'RATE')) { continue }

        $in = $null; $out = $null; $ctx = 0
        if ($null -ne $cat.pricing) { $in = $cat.pricing.input; $out = $cat.pricing.output }
        if ($null -ne $cat.context) { $ctx = [int]$cat.context }

        $friendly = ConvertTo-FriendlyName $catId
        $tier = ''
        if (-not $IsFree -and $null -ne $in) {
            $tier = Resolve-TierFromPrice -InputPrice $in -L $LThreshold -B $BThreshold -A $AThreshold
        }
        $add.Add([pscustomobject]@{
            id = $catId; friendly = $friendly; tier = $tier
            in = $in; out = $out; context = $ctx
        })
    }

    return [pscustomobject]@{
        Keep         = @($keep)
        Add          = @($add)
        RemoveReason = $remove
    }
}

<#
.SYNOPSIS
    Từ Compare-ToLive, sinh danh sách model FINAL (theo thứ tự hiển thị) cho 1 provider.
    THUẦN. Quy tắc:
      - Keep: giữ NGUYÊN thứ tự cũ.
      - Max: model mới chèn vào đúng nhóm, sau model cùng nhóm cuối cùng (giữ cụm nhóm),
             trong nhóm model mới xếp theo giá input tăng dần.
      - Free: model mới thêm CUỐI danh sách.
    Trả { Ordered = @(id, name, tier), ChangedPrice = @("id: old -> new") }.
#>
function Compute-OrderedModels {
    param(
        [Parameter(Mandatory)]$ConfigModels,
        [Parameter(Mandatory)]$Compare,
        [switch]$IsFree,
        [double]$LThreshold = 0.50,
        [double]$BThreshold = 1.50,
        [double]$AThreshold = 4.00,
        [string]$NewBadge = '',
        [switch]$RefreshBadges
    )
    $badge = ''
    if ($NewBadge) { $badge = [regex]::Escape($NewBadge) }
    $keepById = @{}
    foreach ($k in @($Compare.Keep)) { $keepById[$k.id] = $k }

    $ordered = [System.Collections.Generic.List[object]]::new()
    $changedPrice = [System.Collections.Generic.List[string]]::new()

    # ══ 1) Keep theo thứ tự cũ; cập nhật giá nếu lệch catalog. ══
    foreach ($old in @($ConfigModels)) {
        if (-not $keepById.ContainsKey($old.id)) { continue }
        $k = $keepById[$old.id]
        $name = $old.name

        # Gỡ badge "mới" cũ (nếu có) — chỉ khi sync NÀY thực sự đổi danh sách
        # (thêm/gỡ). Nếu danh sách không đổi thì giữ badge để nhìn picker còn biết.
        if ($badge -and $RefreshBadges) { $name = $name -replace "^$badge", '' }

        # Gỡ annotation ghi tay (vd " ⚠️đang 500") — không được probe kiểm tra.
        $name = Remove-HandAnnotation $name

        if (-not $IsFree) {
            $cur = Get-PricesFromName $name
            if ($cur.Has -and $null -ne $k.CatIn -and $null -ne $k.CatOut) {
                if ([math]::Abs([double]$cur.In - [double]$k.CatIn) -gt 1e-9 -or
                    [math]::Abs([double]$cur.Out - [double]$k.CatOut) -gt 1e-9) {
                    $new = Update-PricesInName -Name $name -In ([double]$k.CatIn) -Out ([double]$k.CatOut)
                    if ($new -ne $name) {
                        $changedPrice.Add("$($old.id): '$name' -> '$new'")
                        $name = $new
                    }
                }
            }
        }
        $ordered.Add([pscustomobject]@{
            id   = $old.id
            name = $name
            tier = if ($IsFree) { '' } else { Resolve-TierFromName $name }
        })
    }

    # ══ 2) Model mới. ══
    $newList = @($Compare.Add | Sort-Object @{ Expression = { if ($_.in) { [double]$_.in } else { [double]::MaxValue } } })
    $groupOrder = @{ 'L' = 0; 'B' = 1; 'A' = 2; 'S' = 3 }

    if ($IsFree) {
        foreach ($a in $newList) {
            $nm = New-ModelDisplayName -FriendlyName $a.friendly -Context $a.context
            if ($NewBadge) { $nm = "$NewBadge$nm" }
            $ordered.Add([pscustomobject]@{ id = $a.id; name = $nm; tier = '' })
        }
    } else {
        foreach ($a in $newList) {
            $tier = $a.tier
            if (-not ($tier -and $groupOrder.ContainsKey($tier))) { $tier = 'L' }

            # Vị trí chèn: sau model CÙNG NHÓM cuối cùng; nếu nhóm chưa có model,
            # chèn trước model của nhóm "nặng" hơn đầu tiên.
            $insertIdx = $ordered.Count
            $lastSame = -1
            for ($i = $ordered.Count - 1; $i -ge 0; $i--) {
                $t = Resolve-TierFromName $ordered[$i].name
                if ($t -eq $tier) { $lastSame = $i; break }
            }
            if ($lastSame -ge 0) {
                $insertIdx = $lastSame + 1
            } else {
                $tierPrio = $groupOrder[$tier]
                $insertIdx = $ordered.Count
                for ($i = 0; $i -lt $ordered.Count; $i++) {
                    $t = Resolve-TierFromName $ordered[$i].name
                    if ($t -and $groupOrder.ContainsKey($t) -and $groupOrder[$t] -gt $tierPrio) {
                        $insertIdx = $i
                        break
                    }
                }
            }

            $nm = New-ModelDisplayName -FriendlyName $a.friendly -Tier $tier -In $a.in -Out $a.out -Context $a.context
            if ($NewBadge) { $nm = "$NewBadge$nm" }
            $ordered.Insert($insertIdx, [pscustomobject]@{ id = $a.id; name = $nm; tier = $tier })
        }
    }

    return [pscustomobject]@{
        Ordered      = @($ordered)
        ChangedPrice = @($changedPrice)
    }
}

<#
.SYNOPSIS
    Gán release_date cho danh sách model FINAL. Model đã có date -> GIỮ NGUYÊN.
    Model mới -> sinh date KẸP GIỮA upper/lower (date giảm dần), fallback xuống duới.
    THUẦN. Không vứt đúng thứ tự hiển thị.
#>
function Assign-ReleaseDates {
    param(
        [Parameter(Mandatory)]$Ordered,        # @(id, name, tier)
        [Parameter(Mandatory)]$ConfigModels,   # @(id, name, release_date)
        [string]$BaseDate = '2099-12-31'
    )
    $dateById = @{}
    foreach ($cm in @($ConfigModels)) { $dateById[$cm.id] = $cm.release_date }

    $final = [System.Collections.Generic.List[object]]::new()
    foreach ($m in @($Ordered)) {
        $final.Add([pscustomobject]@{
            id           = $m.id
            name         = $m.name
            tier         = $m.tier
            release_date = $dateById[$m.id]
        })
    }

    for ($i = 0; $i -lt $final.Count; $i++) {
        $cur = $final[$i]
        if (-not [string]::IsNullOrWhiteSpace($cur.release_date)) { continue }

        # Điểm neo: model NGAY PHÍA TRÊN (i-1) và phía dưới (i+1) trong dãy HIỆN TẠI
        # (đa số đã có date vì thứ tự giữ model cũ không đổi, chỉ chèn model mới xen kẽ).
        $upper = if ($i -gt 0 -and $final[$i - 1].release_date) { [string]$final[$i - 1].release_date } else { $null }
        $lower = if ($i + 1 -lt $final.Count -and $final[$i + 1].release_date) { [string]$final[$i + 1].release_date } else { $null }

        $taken = @($final | Where-Object { $_.release_date } | ForEach-Object { [string]$_.release_date })

        # Ưu tiên kẹp giữa (upper, lower).
        $key = $null
        if ($upper -and $lower) {
            $key = try { Get-SortOrderKeyBetween -Upper $upper -Lower $lower } catch { $null }
        }

        # Fallback: tìm ngày trống TRƯỚC HẾT ngay dưới upper, không va chạm taken/lower.
        if ($null -eq $key) {
            $anchor = if ($upper) { [datetime]::ParseExact($upper, 'yyyy-MM-dd', [cultureinfo]'en-US') } else { [datetime]::ParseExact($BaseDate, 'yyyy-MM-dd', [cultureinfo]'en-US') }
            $lDate = if ($lower) { [datetime]::ParseExact($lower, 'yyyy-MM-dd', [cultureinfo]'en-US') } else { [datetime]::MinValue }

            $cand = $null
            # a) dưới anchor (nhưng phải > lower).
            $s = $anchor
            for ($k = 0; $k -lt 500 -and $null -eq $cand; $k++) {
                $s = $s.AddDays(-1)
                $fmt = $s.ToString('yyyy-MM-dd')
                if ($s -gt $lDate -and $fmt -notin $taken) { $cand = $fmt }
            }
            # b) trên anchor (nếu không chui được xuống — ngày kề liền nhau).
            if ($null -eq $cand -and $upper) {
                $base = [datetime]::ParseExact($BaseDate, 'yyyy-MM-dd', [cultureinfo]'en-US')
                $s = $anchor
                for ($k = 0; $k -lt 500 -and $null -eq $cand; $k++) {
                    $s = $s.AddDays(1)
                    if ($s -gt $base) { break }
                    $fmt = $s.ToString('yyyy-MM-dd')
                    if ($fmt -notin $taken) { $cand = $fmt }
                }
            }
            # c) hết cách: đẩy xuống dưới lower cho chắc chắn (vẫn hợp lệ JSON, chỉ thứ tự xê dịch).
            if ($null -eq $cand -and $lower) {
                $s = $lDate
                for ($k = 0; $k -lt 500 -and $null -eq $cand; $k++) {
                    $s = $s.AddDays(-1)
                    $fmt = $s.ToString('yyyy-MM-dd')
                    if ($fmt -notin $taken) { $cand = $fmt }
                }
            }
            $key = $cand
            if ($null -eq $key) { $key = '2099-01-01' }
        }

        $cur.release_date = $key
    }
    return @($final)
}

<#
.SYNOPSIS
    Sinh 1 dòng JSONC cho 1 model (indent 8).
#>
function Format-ModelLine {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ReleaseDate
    )
    return ('        "' + $Id + '": { "name": "' + $Name + '", "release_date": "' + $ReleaseDate + '" }')
}

<#
.SYNOPSIS
    Thay khối "models": { ... } của 1 provider trong TEXT JSONC.
    GIỮ: comment header (dòng comment trước model đầu), comment phân nhóm "// ── [X] ──",
    indent, mọi thứ bên ngoài block. Chỉ thay CÁC DÒNG MODEL.
    Models: mảng @{id, name, release_date, tier}.
#>
function Set-ProviderModelsBlock {
    param(
        [Parameter(Mandatory)][string]$Raw,
        [Parameter(Mandatory)][string]$ProviderKey,
        [Parameter(Mandatory)]$Models   # mảng {id, name, release_date, tier}
    )

    # Chia theo dòng (giữ nguyên ký tự dòng mới: \r\n hoặc \n).
    $newline = if ($Raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($Raw -split "`r?`n")
    $sepRe = '^\s*//\s*──\s*\[([LBAS])\]'

    # 1) Vị trí provider.
    $pIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*"' + [regex]::Escape($ProviderKey) + '"\s*:\s*\{')) { $pIdx = $i; break }
    }
    if ($pIdx -lt 0) { throw "Không tìm thấy provider '$ProviderKey' trong config." }

    # 2) Vị trí mở "models": { ngay sau provider.
    $mOpen = -1
    for ($i = $pIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*"models"\s*:\s*\{') { $mOpen = $i; break }
    }
    if ($mOpen -lt 0) { throw "Provider '$ProviderKey' không có 'models'." }

    # 3) Vị trí đóng block models: dòng '      }' (6 khoảng trắng) sau mOpen.
    $mClose = -1
    for ($i = $mOpen + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s{6}\}\,?\s*$') { $mClose = $i; break }
    }
    if ($mClose -lt 0) { throw "Không tìm thấy '}' đóng models của '$ProviderKey'." }

    # 4) Giữ comment header (dòng bắt đầu '//') từ sau mở cho tới model đầu / sep đầu.
    $header = [System.Collections.Generic.List[string]]::new()
    for ($i = $mOpen + 1; $i -lt $mClose; $i++) {
        $ln = $lines[$i]
        if ($ln -match $sepRe) { break }                 # stop ở sep nhóm đầu
        if ($ln -match '^\s*//') { $header.Add($ln); continue }
        if ($ln -match '^\s*"') { break }                 # model đầu
        if (-not [string]::IsNullOrWhiteSpace($ln)) { $header.Add($ln) }
    }

    # 5) Thu comment phân nhóm cũ (nếu có).
    $sepMap = @{}
    for ($i = $mOpen + 1; $i -lt $mClose; $i++) {
        $ln = $lines[$i]
        $mm = [regex]::Match($ln, $sepRe)
        if ($mm.Success) { if (-not $sepMap.ContainsKey($mm.Groups[1].Value)) { $sepMap[$mm.Groups[1].Value] = $ln } }
    }

    # 6) Dựng block mới.
    $blk = [System.Collections.Generic.List[string]]::new()
    $blk.Add($lines[$mOpen])

    foreach ($h in $header) { $blk.Add($h) }

    $modelLines = [System.Collections.Generic.List[string]]::new()

    # Gộp theo nhóm: MAX theo tier; FREE đơn dãy.
    $groupOrder = @('L', 'B', 'A', 'S')
    if (@($Models | Where-Object { $_.tier }).Count -eq 0) {
        foreach ($m in @($Models)) {
            $modelLines.Add('        "' + $m.id + '": { "name": "' + $m.name + '", "release_date": "' + $m.release_date + '" }')
        }
    } else {
        foreach ($t in $groupOrder) {
            $tierModels = @($Models | Where-Object { $_.tier -eq $t })
            if ($tierModels.Count -eq 0) { continue }
            if ($sepMap.ContainsKey($t)) {
                $modelLines.Add($sepMap[$t])
            } else {
                $modelLines.Add("        // ── [$t] ──")
            }
            foreach ($m in $tierModels) {
                $modelLines.Add('        "' + $m.id + '": { "name": "' + $m.name + '", "release_date": "' + $m.release_date + '" }')
            }
        }
    }

    # Phẩy giữa các dòng model — KHÔNG phẩy ở dòng model cuối cùng.
    $lastModelIdx = -1
    for ($li = 0; $li -lt $modelLines.Count; $li++) {
        if ($modelLines[$li] -notmatch '^\s*//') { $lastModelIdx = $li }
    }
    for ($li = 0; $li -lt $modelLines.Count; $li++) {
        if ($modelLines[$li] -match '^\s*//') { $blk.Add($modelLines[$li]); continue }
        if ($li -eq $lastModelIdx) {
            $blk.Add($modelLines[$li])
        } else {
            $blk.Add($modelLines[$li] + ',')
        }
    }
    $blk.Add('      }')

    # 7) Ghép lại: mọi dòng trừ khối cũ.
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $mOpen; $i++) { $out.Add($lines[$i]) }
    foreach ($b in $blk) { $out.Add($b) }
    for ($i = $mClose + 1; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }

    return $out -join $newline
}

<#
.SYNOPSIS
    Gỡ annotation GHI TAY khỏi name model (vd " ⚠️đang 500", " ⚠️ERR tạm").
    Annotation không được probe kiểm tra nên dễ lỗi thời/gây rối — sync sẽ tự strip
    mọi thứ từ dấu ⚠️ đến cuối name. THUẦN.
#>
function Remove-HandAnnotation {
    param([Parameter(Mandatory)][string]$Name)
    $clean = $Name -replace '\s*⚠️.*$', ''
    return $clean.TrimEnd()
}

<#
.SYNOPSIS
    Sinh tiêu đề provider hiển thị trong opencode picker: "<name> — <count> model".
    Nếu có thêm/gỡ, phụ chú "(+N · gỡ: a, b)" để nhìn list biết ngay.
    THUẦN. Nếu name đã mang hậu tố "— N model" thì strip trước khi tái tạo.
#>
function Format-ProviderHeader {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Count,
        [string[]]$Added = @(),
        [string[]]$Removed = @()
    )
    $base = $Name -replace '\s*—\s*\d+ model.*$', ''
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $Name }
    $h = "{0} — {1} model" -f $base, $Count

    $notes = [System.Collections.Generic.List[string]]::new()
    $added = @($Added); $removed = @($Removed)
    if ($added.Count -gt 0) { $notes.Add("+$($added.Count)") }
    if ($removed.Count -gt 0) {
        # Tên ngắn: bỏ tiền tố provider ("anthropic/claude-opus-5.5" -> "claude-opus-5.5").
        $short = @($removed | ForEach-Object { if ($_ -match '^[^/]+/') { $_.Substring($_.IndexOf('/') + 1) } else { $_ } })
        $notes.Add("gỡ: " + ($short -join ', '))
    }
    if ($notes.Count -gt 0) { $h += " (" + ($notes -join ' · ') + ")" }
    return $h
}

<#
.SYNOPSIS
    Thay dòng '"name": "..."' của 1 provider (KHÔNG phải model) trong TEXT JSONC.
    Dòng name của provider là dòng bắt đầu bằng khoảng trắng + '"name":' trong block provider
    (name model nằm giữa dòng '"id": { "name": ...' nên không khớp). Giữ nguyên indent.
#>
function Set-ProviderNameLine {
    param(
        [Parameter(Mandatory)][string]$Raw,
        [Parameter(Mandatory)][string]$ProviderKey,
        [Parameter(Mandatory)][string]$NewName
    )
    $newline = if ($Raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($Raw -split "`r?`n")

    $pIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*"' + [regex]::Escape($ProviderKey) + '"\s*:\s*\{')) { $pIdx = $i; break }
    }
    if ($pIdx -lt 0) { throw "Không tìm thấy provider '$ProviderKey' trong config." }

    for ($i = $pIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*"models"\s*:\s*\{') { break }
        if ($lines[$i] -match '^\s*"name"\s*:\s*') {
            $indent = [regex]::Match($lines[$i], '^\s*').Value
            $lines[$i] = '{0}"name": "{1}",' -f $indent, ($NewName -replace '"', '\"')
            return $lines -join $newline
        }
    }
    return $Raw
}

if ($SkipRun) { return }

# ───────────────────────────────────────────────
# Chạy chính
# ───────────────────────────────────────────────

$repo = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repo 'configs\development\opencode.jsonc'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Fail "Không tìm thấy file cấu hình: $ConfigPath"
    exit 2
}

$selected = @('1-xkiro-free', '2-xkiro-max')
if ($Provider -and $Provider.Count -gt 0) {
    $selected = @($Provider | Where-Object { $_ -in @('1-xkiro-free', '2-xkiro-max') })
    if ($selected.Count -eq 0) {
        Write-Fail 'Provider không hợp lệ (chỉ hỗ trợ: 1-xkiro-free, 2-xkiro-max).'
        exit 2
    }
}

Write-Step "Update-XKiroModels: $ConfigPath"

$key = Get-EnvValueAny 'XTROUTER_API_KEY'
if (-not $NoProbe -and [string]::IsNullOrWhiteSpace($key)) {
    Write-Fail 'Thiếu biến môi trường XTROUTER_API_KEY — không probe được.'
    exit 1
}

# ── 1. Fetch catalog live ─────────────────────
$provDef = @($Providers | Where-Object { $_.Id -eq 'xkiro' })[0]
$rows, $err = Get-CatalogRaw $provDef
if ($null -eq $rows) {
    Write-Fail "Không tải được catalog xKiro: $err"
    exit 1
}
$catalog = ConvertTo-NormalizedCatalog @($rows)
Write-Ok "Catalog live: $($catalog.Count) model."

# ── 2. Probe (song song). ──
$probeIds = @($catalog | Where-Object { $_.access_tier -in @('free', 'paid') } |
    ForEach-Object { $_.id } | Sort-Object)

if ($NoProbe) {
    $probeResults = @{}
    foreach ($id in $probeIds) { $probeResults[$id] = 'OK' }
    Write-Info "(-NoProbe) coi mọi model trong catalog là OK — chỉ so catalog + giá."
} else {
    Write-Info "Probe $($probeIds.Count) model (free+paid, parallel $ParallelProbes, timeout ${TimeoutSeconds}s)…"
    $url = "$($provDef.BaseUrl)/chat/completions"
    $rawResults = @($probeIds | ForEach-Object -Parallel {
        $mid = $_
        $body = @{ model = $mid; messages = @(@{ role = 'user'; content = 'ping' }); max_tokens = 1 } | ConvertTo-Json -Depth 5
        $hdr = @{ Authorization = "Bearer $($using:key)" }
        $status = 'TIMEOUT'
        try {
            $r = Invoke-WebRequest -Uri "$($using:url)" -Method Post -Headers $hdr `
                -ContentType 'application/json' -Body $body -TimeoutSec $using:TimeoutSeconds -SkipHttpErrorCheck
            switch ([int]$r.StatusCode) {
                200 { $status = 'OK' }
                201 { $status = 'OK' }
                401 { $status = 'AUTH' }
                403 { $status = 'AUTH' }
                404 { $status = 'NOTFOUND' }
                429 { $status = 'RATE' }
                default { $status = 'HTTP' }
            }
        } catch { $status = 'TIMEOUT' }
        [pscustomobject]@{ id = $mid; status = $status }
    } -ThrottleLimit $ParallelProbes)

    $probeResults = @{}
    foreach ($r in $rawResults) { $probeResults[$r.id] = $r.status }

    $nOk = @($probeResults.Values | Where-Object { $_ -eq 'OK' }).Count
    $nAuth = @($probeResults.Values | Where-Object { $_ -eq 'AUTH' }).Count
    $n404 = @($probeResults.Values | Where-Object { $_ -eq 'NOTFOUND' }).Count
    Write-Ok "Probe xong: OK $nOk · AUTH(403) $nAuth · NOTFOUND $n404."
}

# ── 3. Đồng bộ từng provider ──────────────────
$config = Get-ConfigContent $ConfigPath
$totalAdd = 0; $totalRemove = 0
$allChanges = [System.Collections.Generic.List[string]]::new()
$summary = [System.Collections.Generic.List[pscustomobject]]::new()

$originalRaw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8
$newRaw = $originalRaw

# Badge cho model MỚI trong picker opencode (tự gỡ ở lần sync sau khi model đã cũ).
$NewBadge = '🆕 '

# Mốc để hồi tố đánh dấu model mới/gỡ: model có trong config nhưng không có trong
# baseline -> badge 🆕 + phụ chú thêm; model có trong baseline nhưng không còn
# trong config -> phụ chú gỡ. Mặc định TỰ TÌM backup mới nhất trong configs/development/.backup
# (không cần truyền -BaselineConfig; config mới ghi chính là baseline cho lần sau).
$baselineCfg = $null
if ($BaselineConfig) {
    if (-not (Test-Path -LiteralPath $BaselineConfig -PathType Leaf)) {
        Write-Fail "Baseline không tồn tại: $BaselineConfig"
        exit 2
    }
    $baselineCfg = Get-ConfigContent $BaselineConfig
    Write-Info "Baseline: $BaselineConfig (chỉ định tay)."
} else {
    $backupDir = Join-Path $repo 'configs\development\.backup'
    $latestBackup = @(Get-ChildItem -LiteralPath $backupDir -Filter 'opencode.*.jsonc' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($latestBackup.Count -gt 0) {
        try {
            $baselineCfg = Get-ConfigContent $latestBackup[0].FullName
            Write-Info "Baseline tự động: $($latestBackup[0].FullName)"
        } catch {
            Write-Warn "Không đọc được baseline backup — bỏ qua hồi tố."
        }
    } else {
        Write-Info 'Chưa có backup — không hồi tố badge/gỡ (lần chạy đầu).'
    }
}

foreach ($cpKey in $selected) {
    $cp = $config.provider.PSObject.Properties[$cpKey]
    if ($null -eq $cp -or $null -eq $cp.Value) {
        Write-Warn "Provider [$cpKey] không tồn tại trong config — bỏ qua."
        continue
    }
    $isFree = ($cpKey -eq '1-xkiro-free')
    $tierLabel = if ($isFree) { 'free' } else { 'paid' }

    $cur = Get-ConfigModels $cp.Value
    $cmp = Compare-ToLive -ConfigModels $cur -CatalogModels $catalog -ProbeResults $probeResults `
        -IsFree:$isFree -TierFilter $tierLabel `
        -LThreshold $LThreshold -BThreshold $BThreshold -AThreshold $AThreshold

    Write-Step "[$cpKey] sync"
    Write-Info "giữ $($cmp.Keep.Count) · thêm $($cmp.Add.Count) · gỡ $($cmp.RemoveReason.Count)"

    foreach ($rId in @($cmp.RemoveReason.Keys)) { Write-Warn "  GỠ  $rId — $($cmp.RemoveReason[$rId])" }
    foreach ($a in @($cmp.Add)) {
        $nm = New-ModelDisplayName -FriendlyName $a.friendly -Tier $a.tier -In $a.in -Out $a.out -Context $a.context
        Write-Ok "  THÊM $($a.id) -> $NewBadge$nm"
    }

    $listChanged = ($cmp.Add.Count -gt 0 -or $cmp.RemoveReason.Count -gt 0)
    $computed = Compute-OrderedModels -ConfigModels $cur -Compare $cmp `
        -IsFree:$isFree -LThreshold $LThreshold -BThreshold $BThreshold -AThreshold $AThreshold `
        -NewBadge $NewBadge -RefreshBadges:$listChanged

    foreach ($c in $computed.ChangedPrice) { $allChanges.Add("[$cpKey] CẬP NHẬT GIÁ $c") }
    foreach ($rId in @($cmp.RemoveReason.Keys)) { $allChanges.Add("[$cpKey] GỠ $rId — $($cmp.RemoveReason[$rId])") }
    foreach ($a in @($cmp.Add)) { $allChanges.Add("[$cpKey] THÊM $($a.id)") }
    $provChange = $computed.ChangedPrice.Count + $cmp.RemoveReason.Count + $cmp.Add.Count

    $final = Assign-ReleaseDates -Ordered $computed.Ordered -ConfigModels $cur `
        -BaseDate $(if ($isFree) { '2099-12-31' } else { '2099-11-30' })

    # ── Hồi tố badge + liệt kê model bị gỡ so với baseline ──
    # (chỉ khi truyền -BaselineConfig). Model có trong config nhưng không có trong
    # baseline -> gắn badge 🆕 và gộp vào "thêm"; model có trong baseline nhưng
    # không còn trong config -> gộp vào "gỡ" để header/summary hiển thị.
    $backfillAdded = @(); $backfillRemoved = @()
    if ($null -ne $baselineCfg) {
        $blProv = $baselineCfg.provider.PSObject.Properties[$cpKey]
        if ($null -ne $blProv -and $null -ne $blProv.Value) {
            $blIds = @(Get-ConfigModels $blProv.Value | ForEach-Object { $_.id })
            $finalIds = @($final | ForEach-Object { $_.id })
            $backfillRemoved = @($blIds | Where-Object { $_ -notin $finalIds })
            foreach ($m in @($final)) {
                if ($m.id -notin $blIds) {
                    if ($m.name -notlike "$NewBadge*") { $m.name = "$NewBadge$($m.name)" }
                    $backfillAdded += $m.id
                }
            }
        }
        if ($backfillAdded.Count -gt 0) {
            Write-Info "[$cpKey] hồi tố đánh dấu MỚI: $($backfillAdded.Count) model"
        }
        if ($backfillRemoved.Count -gt 0) {
            Write-Info "[$cpKey] hồi tố GỠ: $($backfillRemoved.Count) model ($($backfillRemoved -join ', '))"
        }
    }

    $totalAdd += $cmp.Add.Count
    $totalRemove += $cmp.RemoveReason.Count

    $summary.Add([pscustomobject]@{
        Key      = $cpKey
        Label    = if ($isFree) { 'xKiro FREE' } else { 'xKiro MAX' }
        OldCount = @($cur).Count
        NewCount = @($final).Count
        Added    = @(@(@($cmp.Add) | ForEach-Object { $_.id }) + $backfillAdded | Select-Object -Unique)
        Removed  = @(@($cmp.RemoveReason.Keys) + $backfillRemoved | Select-Object -Unique)
        Changes  = $provChange
    })

    if ($final.Count -gt 0) {
        $newRaw = Set-ProviderModelsBlock -Raw $newRaw -ProviderKey $cpKey -Models $final
    }

    # Cập nhật tiêu đề provider (nhìn picker opencode là biết tổng số + mới/gỡ).
    # Chỉ tái tạo KHI có thêm/gỡ (live hoặc hồi tố) — nếu không, giữ nguyên note cũ
    # (vd "(+16)", "gỡ: ...") để thông tin không biến mất giữa các lần chạy.
    $provName = [string]$cp.Value.name
    $hdrAdded = @(@(@($cmp.Add) | ForEach-Object { $_.id }) + $backfillAdded | Select-Object -Unique)
    $hdrRemoved = @(@($cmp.RemoveReason.Keys) + $backfillRemoved | Select-Object -Unique)
    if ($provName -and ($hdrAdded.Count -gt 0 -or $hdrRemoved.Count -gt 0)) {
        $hdr = Format-ProviderHeader -Name $provName -Count @($final).Count `
            -Added $hdrAdded `
            -Removed $hdrRemoved
        if ($hdr -ne $provName) {
            $newRaw = Set-ProviderNameLine -Raw $newRaw -ProviderKey $cpKey -NewName $hdr
        }
    }
}

# ── 4. Báo cáo + ghi ──────────────────────────
Write-Step 'KẾT QUẢ'
$rawChanged = ($newRaw -cne $originalRaw)
if (-not $rawChanged) {
    Write-Ok 'Không có thay đổi so với catalog live — config đã đồng bộ.'
    Write-Info 'Bỏ qua bước ghi/validate.'
    exit 0
}

# ── TỔNG KẾT delta theo provider ──────────────
foreach ($s in $summary) {
    Write-Host ''
    Write-Step ("{0}  {1} → {2}" -f $s.Label, $s.OldCount, $s.NewCount)
    Write-Host ("    Thêm {0} · Gỡ {1} · cập nhật giá {2}" -f `
        $s.Added.Count, $s.Removed.Count, $s.Changes)

    if ($s.Added.Count -gt 0) {
        Write-Ok ("    MỚI ({0}): {1}" -f $s.Added.Count, ($s.Added -join ', '))
    }
    if ($s.Removed.Count -gt 0) {
        Write-Warn ("    MẤT ({0}): {1}" -f $s.Removed.Count, ($s.Removed -join ', '))
    }
    if ($s.Added.Count -eq 0 -and $s.Removed.Count -eq 0) {
        Write-Info '    Không thêm/gỡ model — chỉ có thể đổi thứ tự/giá.'
    }
}
Write-Host ''

Write-Info "Tóm tắt: thêm $totalAdd · gỡ $totalRemove · $($allChanges.Count) thay đổi name/giá."
foreach ($c in $allChanges) { Write-Host "  · $c" -ForegroundColor DarkGray }

if ($NoWrite) {
    Write-Info '(-NoWrite) KHÔNG ghi vào file — kết thúc với báo cáo trên.'
    exit 0
}

# Backup dev trước khi ghi.
$backupDir = Join-Path $repo 'configs\development\.backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir ("opencode." + (Get-Timestamp) + ".jsonc")
Copy-Item -LiteralPath $ConfigPath -Destination $backup
Write-Info "Backup dev: $backup"

Set-Content -LiteralPath $ConfigPath -Value $newRaw -Encoding utf8NoBOM
Write-Ok "Đã ghi dev config: $ConfigPath"

# ── 5. Validate ───────────────────────────────
if (-not $SkipValidation) {
    Write-Info 'Validate dev config...'
    & (Get-ScriptPath 'Test-ModelCompassConfig.ps1') -Path $ConfigPath | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'VALIDATE THẤT BẠI — kiểm tra lại thay đổi.'
        exit 1
    }
    Write-Ok 'Validate OK.'
} else {
    Write-Warn '(-SkipValidation) bỏ qua validate.'
}

Write-Step 'BƯỚC TIẾP'
Write-Host '  • Kiểm tra giá: pwsh scripts/provider/Compare-Prices.ps1 -ConfigMode dev -FailOnDiff'
Write-Host '  • Quy trình hoàn tất: pwsh scripts/config/Publish-Config.ps1 -Yes'
Write-Host '  • Áp dụng global: pwsh scripts/config/Install-Config.ps1 -Force'

if ($Publish) {
    Write-Info 'Chạy Publish-Config.ps1...'
    & (Get-ScriptPath 'Publish-Config.ps1') -Source $ConfigPath -Yes
    if ($LASTEXITCODE -ne 0) { Write-Fail 'Publish thất bại.'; exit 1 }
}
if ($Install) {
    Write-Info 'Chạy Install-Config.ps1...'
    & (Get-ScriptPath 'Install-Config.ps1') -Force
    if ($LASTEXITCODE -ne 0) { Write-Fail 'Install thất bại.'; exit 1 }
}

Write-Ok 'Xong.'
exit 0