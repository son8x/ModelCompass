#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: PHA 3 — tự sinh/cập nhật bảng ⭐ trong docs/model-reference.md §2
    từ config + catalog + rule (chống "drift" tài liệu).

.DESCRIPTION
    Tầng 3 (sibling của New-RecommendReport.ps1). Nạp 2 thư viện cùng nhóm:
      - Get-ModelCandidates.ps1  (tầng 1) — dựng danh sách ứng viên từ config + catalog.
      - Resolve-StarRules.ps1    (tầng 2) — áp rule → chọn ⭐ theo nhóm & mục đích.
    Rồi sinh khối Markdown (bảng nhóm + bảng mục đích) và ghi ĐÈ vùng giữa 2 marker
    <!-- BEGIN:recommend-stars ... --> ... <!-- END:recommend-stars --> trong file docs.

    Nội dung NGOÀI marker (tiêu đề, "Lưu ý chọn model", v.v.) được GIỮ NGUYÊN.
    Dùng -Check để CI kiểm tài liệu có khớp đề xuất hiện tại không (exit 1 nếu lệch).

.PARAMETER DocsPath
    File docs cần cập nhật. Mặc định: docs/model-reference.md.

.PARAMETER ConfigPath
    File config dev. Mặc định: configs/development/opencode.jsonc.

.PARAMETER CatalogPath
    Catalog xKiro. Mặc định: docs/catalogs/xkiro.json.

.PARAMETER CapabilitiesPath
    Bảng tra khả năng tay. Mặc định: scripts/recommend/model-capabilities.json.

.PARAMETER Provider
    Provider xKiro xét. Mặc định: cả 1-xkiro-free và 2-xkiro-max.

.PARAMETER Check
    KHÔNG ghi — chỉ so khối hiện có với nội dung vừa sinh; exit 1 nếu lệch (dùng cho CI).

.PARAMETER Top
    Số ứng viên mỗi mục đích/scope (1 ⭐ chính + dự phòng). Mặc định: 3.

.PARAMETER SkipRun
    Chỉ nạp định nghĩa function (dùng cho test dot-source), không chạy.
#>
[CmdletBinding()]
param(
    [string]$DocsPath,
    [string]$ConfigPath,
    [string]$CatalogPath,
    [string]$CapabilitiesPath,
    [string[]]$Provider,
    [switch]$Check,
    [switch]$SkipRun,
    [int]$Top = 3
)
Set-StrictMode -Version Latest

# Chụp cờ TRƯỚC khi dot-source (quirk PowerShell: script con cùng tên param ghi đè biến).
$urdSkipRun   = [bool]$SkipRun
$urdCheck     = [bool]$Check
$urdDocsPath  = $DocsPath
$urdConfig    = $ConfigPath
$urdCatalog   = $CatalogPath
$urdCapPath   = $CapabilitiesPath
$urdProvider  = @($Provider)
$urdTop       = [int]$Top

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
# Format-Price (Compare-Prices) + Resolve-TierFromName / Resolve-TierFromPrice (Update-XKiroModels).
. (Get-ScriptPath 'Update-XKiroModels.ps1') -SkipRun
# Tầng 1 + tầng 2 (thư viện thuần, không có param nên không ghi đè biến).
. (Join-Path $PSScriptRoot 'Get-ModelCandidates.ps1')
. (Join-Path $PSScriptRoot 'Resolve-StarRules.ps1')

# Khôi phục cờ sau dot-source.
$SkipRun          = $urdSkipRun
$Check            = $urdCheck
$DocsPath         = $urdDocsPath
$ConfigPath       = $urdConfig
$CatalogPath      = $urdCatalog
$CapabilitiesPath = $urdCapPath
$Provider         = $urdProvider
$Top              = $urdTop

# Marker bao vùng tự sinh (khớp cả khi có phần mô tả sau tên marker).
$script:BlockBegin = '<!-- BEGIN:recommend-stars'
$script:BlockEnd   = '<!-- END:recommend-stars -->'

# ═══════════════════════════════════════════════════════════════
# Hàm thuần của tầng 3 (định dạng + thay khối marker)
# ═══════════════════════════════════════════════════════════════

function Format-RecommendContext {
    <# Context hiển thị: 0 → '—', ≥1M → '1M', còn lại 'NK'. THUẦN. #>
    param($Candidate)
    $ctx = [int]$Candidate.Context
    if ($ctx -ge 1000000) { return ('{0:0.#}M' -f ($ctx / 1e6)) }
    if ($ctx -gt 0) { return ('{0:0.#}K' -f ($ctx / 1e3)) }
    return '—'
}

function Format-RecommendPricePair {
    <#
        Giá in/out cho bảng nhóm: nhóm free/thiếu giá → 'free'; còn lại '$<in> / $<out>'
        (out thiếu → '$<in> / —'). THUẦN.
    #>
    param($Candidate)
    if ($Candidate.Group -eq 'free' -or $null -eq $Candidate.In) { return 'free' }
    $in = '$' + (Format-Price $Candidate.In)
    if ($null -eq $Candidate.Out) { return "$in / —" }
    return "$in / `$$(Format-Price $Candidate.Out)"
}

function New-RecommendStarsMarkdown {
    <#
    .SYNOPSIS
        Sinh NỘI DUNG (mảng dòng, KHÔNG gồm marker) cho vùng ⭐ của §2. THUẦN (không I/O).
        Params: Rows (từ Resolve-StarRules), Groups/Purposes (registry), Provider labels, Date.
    #>
    param(
        $Rows, $Groups, $Purposes,
        [string]$FreeProvider = '1-xkiro-free',
        [string]$MaxProvider = '2-xkiro-max',
        [string]$Date = $null
    )
    if ([string]::IsNullOrWhiteSpace($Date)) { $Date = (Get-Date -Format 'dd/MM/yyyy') }

    $groupRows = @($Rows | Where-Object { $_.Kind -eq 'group' })
    $purposeRows = @($Rows | Where-Object { $_.Kind -eq 'purpose' })

    # Đếm model ⭐ KHÔNG trùng (theo provider|id).
    $keys = @{}
    foreach ($r in @($Rows)) { $keys[(Get-RecommendationKey -Provider $r.Candidate.Provider -ModelId $r.ModelId)] = $r.Candidate.Group }
    $freeCount = @($keys.Keys | Where-Object { $keys[$_] -eq 'free' }).Count
    $paidCount = @($keys.Keys | Where-Object { $keys[$_] -ne 'free' }).Count

    $labelById = @{}
    foreach ($p in @($Purposes)) { $labelById[$p.Id] = $p.Label }
    $sigByGroup = @{}
    foreach ($g in @($Groups)) { $sigByGroup[$g.Id] = $g.Signature.Purpose }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("> Cập nhật tự động: **$Date** — **$($keys.Count) model** được khuyến nghị")
    $lines.Add("> ($freeCount free + $paidCount trả phí). Tiền tố trong ``/model``: ⭐ chính · ✦ dự phòng · · tham khảo. Sinh bởi")
    $lines.Add('> `scripts/recommend/Update-RecommendDocs.ps1`; chạy `mc recommend-docs` để cập nhật.')
    $lines.Add('')
    $lines.Add('**⭐ Theo nhóm** (⭐ = model mặc định nên chọn của nhóm):')
    $lines.Add('')
    $lines.Add('| Nhóm | ⭐ Model | Giá in/out | Dùng cho |')
    $lines.Add('|---|---|---|---|')
    foreach ($g in @($Groups)) {
        $row = @($groupRows | Where-Object { $_.Key -eq $g.Id }) | Select-Object -First 1
        if ($null -eq $row) { continue }
        $c = $row.Candidate
        $purpose = if ($sigByGroup.ContainsKey($g.Id)) { $sigByGroup[$g.Id] } else { '' }
        $useLabel = if ($labelById.ContainsKey($purpose)) { $labelById[$purpose] } else { $purpose }
        $tag = if ($g.Id -eq 'free') { 'free' } else { "[$($g.Id)] $($g.Label)" }
        $lines.Add("| $tag | ``$($c.Id)`` | $(Format-RecommendPricePair $c) | $useLabel |")
    }
    $lines.Add('')
    $lines.Add('**⭐/✦/· Theo mục đích** (khớp đúng label trong `/model`):')
    $lines.Add('')
    $lines.Add("| Mục đích | ⭐/✦/· Trả phí (``$MaxProvider``) | ⭐/✦/· Miễn phí (``$FreeProvider``) |")
    $lines.Add('|---|---|---|')
    $tierRank = @{ primary = 0; fallback = 1; alt = 2 }
    $tierOf = {
        param($Row)
        $p = $Row.PSObject.Properties['Tier']
        if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { return [string]$p.Value }
        return 'primary'
    }
    foreach ($spec in @($Purposes)) {
        $paidRows = @($purposeRows | Where-Object { $_.Key -eq $spec.Id -and $_.Scope -eq 'paid' } |
            Sort-Object { $r = & $tierOf $_; if ($tierRank.ContainsKey($r)) { $tierRank[$r] } else { 9 } })
        $freeRows = @($purposeRows | Where-Object { $_.Key -eq $spec.Id -and $_.Scope -eq 'free' } |
            Sort-Object { $r = & $tierOf $_; if ($tierRank.ContainsKey($r)) { $tierRank[$r] } else { 9 } })
        if ($paidRows.Count -eq 0 -and $freeRows.Count -eq 0) { continue }
        $paidCell = '—'; $freeCell = '—'
        if ($paidRows.Count -gt 0) {
            $paidCell = (@($paidRows | ForEach-Object {
                $c = $_.Candidate
                "$(Get-TierPrefix (& $tierOf $_)) ``[$($c.Group)] $($c.Id)`` · $(Format-RecommendPricePair $c)"
            }) -join '<br>')
        }
        if ($freeRows.Count -gt 0) {
            $freeCell = (@($freeRows | ForEach-Object {
                $c = $_.Candidate
                "$(Get-TierPrefix (& $tierOf $_)) ``$($c.Id)`` · $(Format-RecommendContext $c)"
            }) -join '<br>')
        }
        $lines.Add("| $($spec.Label) | $paidCell | $freeCell |")
    }
    return @($lines)
}

function Get-MarkerBlock {
    <#
    .SYNOPSIS
        Lấy nội dung GIỮA marker Begin và End (không gồm 2 dòng marker). THUẦN.
        Trả $null nếu không tìm thấy đủ cặp marker.
    #>
    param([Parameter(Mandatory)][string]$Content, [string]$Begin, [string]$End)
    $bi = $Content.IndexOf($Begin, [System.StringComparison]::Ordinal)
    if ($bi -lt 0) { return $null }
    $bEnd = $Content.IndexOf("`n", $bi, [System.StringComparison]::Ordinal)
    if ($bEnd -lt 0) { return $null }
    $ei = $Content.IndexOf($End, $bEnd, [System.StringComparison]::Ordinal)
    if ($ei -lt 0) { return $null }
    $body = $Content.Substring($bEnd + 1, $ei - $bEnd - 1)
    return $body.Trim("`r", "`n")
}

function Set-MarkerBlock {
    <#
    .SYNOPSIS
        Thay nội dung giữa Begin/End bằng $BodyLines (giữ nguyên 2 dòng marker). THUẦN.
        Trả $null nếu thiếu marker. Giữ đúng kiểu xuống dòng của file gốc (CRLF/LF).
    #>
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)]$BodyLines,
        [string]$Begin, [string]$End
    )
    $bi = $Content.IndexOf($Begin, [System.StringComparison]::Ordinal)
    if ($bi -lt 0) { return $null }
    $bLineEnd = $Content.IndexOf("`n", $bi, [System.StringComparison]::Ordinal)
    if ($bLineEnd -lt 0) { return $null }
    $ei = $Content.IndexOf($End, $bLineEnd, [System.StringComparison]::Ordinal)
    if ($ei -lt 0) { return $null }
    $firstLf = $Content.IndexOf("`n", [System.StringComparison]::Ordinal)
    $newline = if ($firstLf -gt 0 -and $Content[$firstLf - 1] -eq "`r") { "`r`n" } else { "`n" }
    $before = $Content.Substring(0, $bLineEnd + 1)
    $after = $Content.Substring($ei)
    $body = (@($BodyLines) -join $newline) + $newline
    return ($before + $body + $after)
}

if ($SkipRun) { return }

# ═══════════════════════════════════════════════════════════════
# Chạy chính (Pha 3: đồng bộ bảng ⭐ trong docs)
# ═══════════════════════════════════════════════════════════════

$repo = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($DocsPath))        { $DocsPath = Join-Path $repo 'docs\model-reference.md' }
if ([string]::IsNullOrWhiteSpace($ConfigPath))      { $ConfigPath = Join-Path $repo 'configs\development\opencode.jsonc' }
if ([string]::IsNullOrWhiteSpace($CatalogPath))     { $CatalogPath = Join-Path $repo 'docs\catalogs\xkiro.json' }
if ([string]::IsNullOrWhiteSpace($CapabilitiesPath)) { $CapabilitiesPath = Join-Path $PSScriptRoot 'model-capabilities.json' }

foreach ($f in @($DocsPath, $ConfigPath, $CatalogPath)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Write-Fail "Không tìm thấy file: $f"; exit 2 }
}

$selected = @('1-xkiro-free', '2-xkiro-max')
if ($Provider -and @($Provider).Count -gt 0) {
    $selected = @($Provider | Where-Object { $_ -in @('1-xkiro-free', '2-xkiro-max') })
    if ($selected.Count -eq 0) { Write-Fail 'Provider không hợp lệ (chỉ hỗ trợ 1-xkiro-free, 2-xkiro-max).'; exit 2 }
}

$mode = if ($Check) { 'KIỂM TRA (không ghi)' } else { 'CẬP NHẬT' }
Write-Step "TÀI LIỆU ⭐ xKiro — $mode"

$capabilities = Read-ModelCapabilities -Path $CapabilitiesPath
$configObj = Get-ConfigContent $ConfigPath
$catalogModels = @((Get-Content -LiteralPath $CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json).models)
$healthPath = Join-Path $repo 'reports\model-health.json'

$bundle = Get-ModelCandidates -ConfigObj $configObj -CatalogModels $catalogModels -ProviderKeys $selected -HealthReportPath $healthPath
$resolved = Resolve-StarRules -Candidates $bundle.Candidates -Capabilities $capabilities -Top $Top

$body = New-RecommendStarsMarkdown -Rows $resolved.Rows -Groups $script:StarGroups -Purposes $script:StarPurposes
$docsRaw = Get-Content -LiteralPath $DocsPath -Raw -Encoding utf8

if ($Check) {
    $existing = Get-MarkerBlock -Content $docsRaw -Begin $script:BlockBegin -End $script:BlockEnd
    if ($null -eq $existing) {
        Write-Fail "Không thấy marker '$($script:BlockBegin)' trong $DocsPath."; exit 2
    }
    $fresh = ((@($body) -join "`n") -replace "`r`n", "`n").Trim("`r", "`n")
    if ((($existing -replace "`r`n", "`n").Trim("`r", "`n")) -ceq $fresh) {
        Write-Ok "Bảng ⭐ trong $([IO.Path]::GetFileName($DocsPath)) KHỚP đề xuất hiện tại."
        exit 0
    }
    Write-Fail "Bảng ⭐ trong $([IO.Path]::GetFileName($DocsPath)) LỆCH so với đề xuất — chạy: mc recommend-docs"
    exit 1
}

$newDocs = Set-MarkerBlock -Content $docsRaw -BodyLines $body -Begin $script:BlockBegin -End $script:BlockEnd
if ($null -eq $newDocs) {
    Write-Fail "Không thấy marker '$($script:BlockBegin)' trong $DocsPath — thêm marker trước."
    exit 2
}
if ($newDocs -ceq $docsRaw) {
    Write-Ok "Bảng ⭐ đã khớp — không cần ghi ($DocsPath)."
    exit 0
}
[System.IO.File]::WriteAllText($DocsPath, $newDocs, [System.Text.UTF8Encoding]::new($false))
Write-Ok "Đã cập nhật bảng ⭐: $DocsPath"
exit 0
