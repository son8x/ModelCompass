#Requires -Version 7
<#
Resolve-StarRules.ps1 — ModelCompass · tầng 2/3 của "Đề xuất ⭐ xKiro".

THƯ VIỆN hàm thuần (không có khối chạy chính) — ÁP RULE (heuristic tên + bảng tra) để chọn model
nên gắn ⭐ theo NHÓM (free/L/B/A/S) và theo MỤC ĐÍCH (reasoning/code/analysis/writing/vision/omni/
translate/fast/lecture/bulk/flagship):
  - Read-ModelCapabilities      : đọc bảng tra tay model-capabilities.json
  - Get-ModelCapability         : suy tag khả năng từ id+name (heuristic) + hợp nhất tag bảng tra
  - Select-RecommendedCandidate : chọn 1 ứng viên trong pool theo Order (top/cheap/ctx)
  - Select-TopCandidates        : chọn top N ứng viên + gán tier (primary/fallback/alt)
  - Resolve-StarRecommendation  : → danh sách dòng đề xuất (preferred thắng rule)
  - Merge-Recommendation        : gộp dòng theo khoá "provider|id" + tier cao nhất
  - Test/Remove/Set-StarInName  : thao tác tiền tố ⭐ trong name
  - Get/Remove/Set-TierPrefixInName : tiền tố phân tầng ⭐/✦/·
  - Resolve-StarRules           : orchestrator (candidates + capabilities → { Rows; Map })

Bảng registry: $script:StarGroups, $script:StarPurposes.
PHỤ THUỘC (bên dot-source phải nạp trước): Get-ModelCandidates.ps1 (Get-RecommendationKey).
#>
Set-StrictMode -Version Latest

# ── Registry mục đích + nhóm ──────────────────────────────────

# Nhóm "đặc trưng": ⭐ nhóm lấy lại từ mục đích đại diện của nhóm.
$script:StarGroups = @(
    @{ Id = 'free'; Label = 'Miễn phí';      Signature = @{ Purpose = 'reasoning'; Scope = 'free' } }
    @{ Id = 'L';    Label = 'Nhẹ·Nhanh·Rẻ';  Signature = @{ Purpose = 'fast';      Scope = 'paid' } }
    @{ Id = 'B';    Label = 'Đa dụng giá tốt'; Signature = @{ Purpose = 'bulk';     Scope = 'paid' } }
    @{ Id = 'A';    Label = 'Mạnh đa dụng';  Signature = @{ Purpose = 'analysis';  Scope = 'paid' } }
    @{ Id = 'S';    Label = 'Flagship';      Signature = @{ Purpose = 'flagship';  Scope = 'paid' } }
)

# Mục đích: Tag = tag cần có; Order = cách chọn khi nhiều ứng viên.
$script:StarPurposes = @(
    @{ Id = 'reasoning'; Label = 'reasoning (mặc định)'; Scopes = @('free');         Tag = 'reasoning'; Order = 'top' }
    @{ Id = 'code';      Label = 'code';                 Scopes = @('free', 'paid'); Tag = 'code';      Order = 'top' }
    @{ Id = 'analysis';  Label = 'phân tích/nghiên cứu'; Scopes = @('paid');         Tag = 'analysis';  Order = 'top' }
    @{ Id = 'writing';   Label = 'viết/văn phong';       Scopes = @('paid');         Tag = 'writing';   Order = 'top' }
    @{ Id = 'vision';    Label = 'vision (hiểu ảnh)';    Scopes = @('free', 'paid'); Tag = 'vision';    Order = 'top' }
    @{ Id = 'omni';      Label = 'omni';                 Scopes = @('free');         Tag = 'omni';      Order = 'top' }
    @{ Id = 'translate'; Label = 'dịch';                 Scopes = @('free');         Tag = 'translate'; Order = 'top' }
    @{ Id = 'fast';      Label = 'nhanh/subagent';       Scopes = @('free', 'paid'); Tag = 'fast';      Order = 'top' }
    @{ Id = 'lecture';   Label = 'soạn bài/PPTX';        Scopes = @('free');         Tag = 'bulk';      Order = 'top' }
    @{ Id = 'bulk';      Label = 'bulk (input rẻ)';      Scopes = @('paid');         Tag = 'bulk';      Order = 'cheap' }
    @{ Id = 'flagship';  Label = 'flagship';             Scopes = @('paid');         Tag = 'flagship';  Order = 'cheap' }
)

# ── Bảng tra tay ──────────────────────────────────────────────

function Read-ModelCapabilities {
    <#
    .SYNOPSIS
        Đọc bảng tra tay → { Unsupported[], Preferred@{task->@{scope->id}}, Tags@{id->@(tag)} }.
        Trả cấu trúc rỗng nếu file không tồn tại. Key model id luôn là string (an toàn với '/').
    #>
    param([string]$Path)
    $empty = [pscustomobject]@{ Unsupported = @(); Preferred = @{}; Tags = @{} }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $empty
    }
    $obj = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json

    $unsupported = @()
    if ($null -ne $obj.PSObject.Properties['unsupported']) { $unsupported = @($obj.unsupported) }

    $preferred = @{}
    if ($null -ne $obj.PSObject.Properties['preferred']) {
        foreach ($taskProp in @($obj.preferred.PSObject.Properties)) {
            $slot = @{}
            foreach ($scopeProp in @($taskProp.Value.PSObject.Properties)) {
                $slot[$scopeProp.Name] = [string]$scopeProp.Value
            }
            $preferred[$taskProp.Name] = $slot
        }
    }

    $tags = @{}
    if ($null -ne $obj.PSObject.Properties['tags']) {
        foreach ($tagProp in @($obj.tags.PSObject.Properties)) {
            $tags[$tagProp.Name] = @($tagProp.Value | ForEach-Object { [string]$_ })
        }
    }

    return [pscustomobject]@{ Unsupported = $unsupported; Preferred = $preferred; Tags = $tags }
}

function Get-ModelCapability {
    <#
    .SYNOPSIS
        Suy tag khả năng cho 1 model từ id + name (heuristic) rồi hợp nhất tag từ bảng tra.
        THUẦN. Trả mảng tag (đã loại trùng). Tag dùng: code, vision, omni, translate, fast,
        reasoning, flagship, analysis, writing, bulk.
    #>
    param(
        [Parameter(Mandatory)][string]$ModelId,
        [string]$Name = '',
        $Capabilities
    )
    $hay = ($ModelId + ' ' + $Name).ToLowerInvariant()
    $tok = @{}
    foreach ($t in ($hay -split '[^\p{L}\p{Nd}]+')) { if ($t) { $tok[$t] = $true } }

    $tags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $has = { param($w) $tok.ContainsKey($w) }
    $any = { param([string[]]$ws) foreach ($w in $ws) { if ($tok.ContainsKey($w)) { return $true } } return $false }

    if ((& $any @('coder', 'codex', 'code', 'devstral', 'codestral'))) { [void]$tags.Add('code') }
    if ((& $any @('vl', 'vision', 'multimodal')))                   { [void]$tags.Add('vision') }
    if ((& $has 'omni'))                                            { [void]$tags.Add('omni') }
    if ((& $any @('translate', 'translation')) -or $hay -match 'dịch') { [void]$tags.Add('translate') }
    if ((& $any @('flash', 'lite', 'mini', 'small', 'turbo', 'nano', 'air', 'nhanh', 'fast', 'subagent', 'instant'))) { [void]$tags.Add('fast') }
    if ((& $any @('reasoning', 'thinking', 'think')))               { [void]$tags.Add('reasoning') }
    if ((& $any @('opus', 'fable', 'flagship', 'sol', 'ultra')))    { [void]$tags.Add('flagship') }
    if ($hay -match 'nghiên cứu|phân tích|research|analys')         { [void]$tags.Add('analysis') }
    if ($hay -match 'viết lách|viết|writing|văn phong')             { [void]$tags.Add('writing') }
    if ($hay -match 'bulk|ppt|slide|ctđt|soạn bài')                 { [void]$tags.Add('bulk') }

    if ($null -ne $Capabilities -and $Capabilities.Tags.ContainsKey($ModelId)) {
        foreach ($t in @($Capabilities.Tags[$ModelId])) { if ($t) { [void]$tags.Add([string]$t) } }
    }
    return @($tags)
}

# ── Chọn ứng viên ─────────────────────────────────────────────

function Get-SortedCandidatePool {
    <#
    .SYNOPSIS
        Sắp xếp pool theo Order + health penalty. THUẦN.
        Model slow/down/locked bị đẩy xuống cuối (không loại bỏ).
        Order: 'top'   = release_date giảm dần → input tăng dần → ctx giảm dần.
               'cheap' = input tăng dần → ctx giảm dần.
               'ctx'   = ctx giảm dần → input tăng dần.
    #>
    param($Pool, [string]$Order = 'top')
    $arr = @($Pool)
    if ($arr.Count -eq 0) { return @() }
    $byIn = { if ($null -ne $_.In) { [double]$_.In } else { [double]::MaxValue } }
    $healthPenalty = {
        $h = $_.PSObject.Properties['HealthClass']
        if ($null -ne $h -and $h.Value -in @('down', 'locked', 'slow')) { return 1 }
        return 0
    }
    switch ($Order) {
        'cheap' { $arr = @($arr | Sort-Object $healthPenalty, @{ Expression = $byIn; Descending = $false }, @{ Expression = { -[int]$_.Context }; Descending = $false }) }
        'ctx'   { $arr = @($arr | Sort-Object $healthPenalty, @{ Expression = { -[int]$_.Context }; Descending = $false }, @{ Expression = $byIn; Descending = $false }) }
        default {
            $arr = @($arr | Sort-Object $healthPenalty, `
                @{ Expression = { if ($_.ReleaseDate) { [string]$_.ReleaseDate } else { '0000-00-00' } }; Descending = $true }, `
                @{ Expression = $byIn; Descending = $false }, `
                @{ Expression = { -[int]$_.Context }; Descending = $false })
        }
    }
    return $arr
}

function Select-RecommendedCandidate {
    <#
    .SYNOPSIS
        Chọn 1 ứng viên tốt nhất trong pool. THUẦN. Wrapper của Get-SortedCandidatePool.
    #>
    param($Pool, [string]$Order = 'top')
    $sorted = @(Get-SortedCandidatePool -Pool $Pool -Order $Order)
    if ($sorted.Count -eq 0) { return $null }
    return $sorted[0]
}

function Select-TopCandidates {
    <#
    .SYNOPSIS
        Chọn top N ứng viên từ pool, gán tier. THUẦN.
        Trả mảng @{ Candidate; Tier } với Tier = 'primary' | 'fallback' | 'alt'.
    #>
    param($Pool, [string]$Order = 'top', [int]$Top = 3)
    $sorted = @(Get-SortedCandidatePool -Pool $Pool -Order $Order)
    $result = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt [Math]::Min($Top, $sorted.Count); $i++) {
        $tier = switch ($i) {
            0       { 'primary' }
            1       { 'fallback' }
            default { 'alt' }
        }
        $result.Add([pscustomobject]@{ Candidate = $sorted[$i]; Tier = $tier })
    }
    return @($result)
}

function Get-CandidateEffectiveTags {
    <#
    .SYNOPSIS
        Tag hiệu lực của 1 ứng viên: nếu ứng viên đã có .Tags thì dùng; nếu chưa thì suy từ
        id+name+bảng tra (Get-ModelCapability). THUẦN. Giúp tầng 1 không phải gán tag.
    #>
    param($Candidate, $Capabilities)
    $prop = $Candidate.PSObject.Properties['Tags']
    if ($null -ne $prop -and @($prop.Value).Count -gt 0) { return @($prop.Value) }
    return @(Get-ModelCapability -ModelId $Candidate.Id -Name $Candidate.Name -Capabilities $Capabilities)
}

# ── Áp rule → dòng đề xuất ────────────────────────────────────

function Get-CandidateHealthClass {
    <# HealthClass của ứng viên ('' nếu không có report). THUẦN. #>
    param($Candidate)
    $p = $Candidate.PSObject.Properties['HealthClass']
    if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { return [string]$p.Value }
    return ''
}

function Test-CandidateHealthy {
    <# Ứng viên không ở trạng thái xấu (slow/down/locked). THUẦN. #>
    param($Candidate)
    return ((Get-CandidateHealthClass $Candidate) -notin @('slow', 'down', 'locked'))
}

function Resolve-StarRecommendation {
    <#
    .SYNOPSIS
        Trả danh sách dòng đề xuất: mỗi dòng { Kind='purpose'|'group'; Key; Label; Scope;
        Tier='primary'|'fallback'|'alt'; ModelId; Source='table'|'rule'; Candidate }. THUẦN.
        -Top N: mỗi mục đích/scope lấy tối đa N ứng viên (1 chính + dự phòng).
        preferred (bảng tra) là primary nếu model còn sống; nếu preferred slow/down/locked
        thì bị đẩy xuống cuối pool (health penalty) thay vì ép làm primary.
    #>
    param($Candidates, $Capabilities, $Purposes = $null, $Groups = $null, [int]$Top = 1)
    if ($null -eq $Purposes) { $Purposes = $script:StarPurposes }
    if ($null -eq $Groups) { $Groups = $script:StarGroups }
    if ($Top -lt 1) { $Top = 1 }

    $free = @($Candidates | Where-Object { $_.Group -eq 'free' })
    $paid = @($Candidates | Where-Object { $_.Group -in @('L', 'B', 'A', 'S') })

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in @($Purposes)) {
        foreach ($scope in @($spec.Scopes)) {
            $pool = if ($scope -eq 'free') { $free } else { $paid }
            $ordered = [System.Collections.Generic.List[object]]::new()

            $prefPick = $null
            if ($null -ne $Capabilities -and $Capabilities.Preferred.ContainsKey($spec.Id) -and
                $Capabilities.Preferred[$spec.Id].ContainsKey($scope)) {
                $prefId = $Capabilities.Preferred[$spec.Id][$scope]
                $prefPick = @($pool | Where-Object { $_.Id -eq $prefId }) | Select-Object -First 1
            }
            if ($null -ne $prefPick -and (Test-CandidateHealthy $prefPick)) {
                $ordered.Add([pscustomobject]@{ Candidate = $prefPick; Source = 'table' })
            }
            if ($spec.Tag) {
                $cand = @($pool | Where-Object { (Get-CandidateEffectiveTags $_ $Capabilities) -contains $spec.Tag })
                foreach ($c in (Get-SortedCandidatePool -Pool $cand -Order $spec.Order)) {
                    $ordered.Add([pscustomobject]@{ Candidate = $c; Source = 'rule' })
                }
            }
            if ($null -ne $prefPick -and -not (Test-CandidateHealthy $prefPick)) {
                $ordered.Add([pscustomobject]@{ Candidate = $prefPick; Source = 'table' })
            }

            $final = [System.Collections.Generic.List[object]]::new()
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($o in $ordered) {
                $k = Get-RecommendationKey -Provider $o.Candidate.Provider -ModelId $o.Candidate.Id
                if (-not $seen.Add($k)) { continue }
                $final.Add($o)
                if ($final.Count -ge $Top) { break }
            }
            if ($final.Count -eq 0) { continue }

            for ($i = 0; $i -lt $final.Count; $i++) {
                $tier = switch ($i) { 0 { 'primary' } 1 { 'fallback' } default { 'alt' } }
                $rows.Add([pscustomobject]@{
                    Kind = 'purpose'; Key = $spec.Id; Label = $spec.Label; Scope = $scope
                    Tier = $tier; ModelId = $final[$i].Candidate.Id
                    Source = $final[$i].Source; Candidate = $final[$i].Candidate
                })
            }
        }
    }

    foreach ($g in @($Groups)) {
        $sig = $g.Signature
        $match = @($rows | Where-Object {
            $_.Kind -eq 'purpose' -and $_.Key -eq $sig.Purpose -and
            $_.Scope -eq $sig.Scope -and $_.Tier -eq 'primary'
        }) | Select-Object -First 1
        if ($null -ne $match) {
            $rows.Add([pscustomobject]@{
                Kind = 'group'; Key = $g.Id; Label = "nhóm $($g.Id)"; Scope = $sig.Scope
                Tier = 'primary'; ModelId = $match.ModelId; Source = $match.Source; Candidate = $match.Candidate
            })
        }
    }
    return @($rows)
}

function Merge-Recommendation {
    <#
    .SYNOPSIS
        Gộp các dòng đề xuất → hashtable "provider|id" ->
        { Provider; ModelId; Tier (cao nhất); Groups; Purposes; PurposeTiers }.
        Tier cao nhất: primary > fallback > alt. Khoá theo provider+id. THUẦN.
    #>
    param($Rows)
    $rank = @{ primary = 0; fallback = 1; alt = 2 }
    $map = @{}
    foreach ($r in @($Rows)) {
        $key = Get-RecommendationKey -Provider $r.Candidate.Provider -ModelId $r.ModelId
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [pscustomobject]@{
                Provider     = $r.Candidate.Provider
                ModelId      = $r.ModelId
                Tier         = ''
                Groups       = [System.Collections.Generic.List[string]]::new()
                Purposes     = [System.Collections.Generic.List[string]]::new()
                PurposeTiers = @{}
            }
        }
        if ($r.Kind -eq 'group') {
            [void]$map[$key].Groups.Add([string]$r.Key)
            continue
        }
        $tier = 'primary'
        $tp = $r.PSObject.Properties['Tier']
        if ($null -ne $tp -and -not [string]::IsNullOrWhiteSpace([string]$tp.Value)) { $tier = [string]$tp.Value }
        $tag = if ($r.Scope -eq 'free') { "$($r.Key)(free)" } else { [string]$r.Key }
        [void]$map[$key].Purposes.Add($tag)
        $map[$key].PurposeTiers[$tag] = $tier
        $cur = $map[$key].Tier
        if ([string]::IsNullOrWhiteSpace($cur) -or $rank[$tier] -lt $rank[$cur]) { $map[$key].Tier = $tier }
    }
    return $map
}

# ── Tiền tố mức ưu tiên trong name (⭐/✦/·) ───────────────────

$script:TierPrefixes = @{ primary = '⭐'; fallback = '✦'; alt = '·' }
$script:TierRanks    = @{ primary = 0; fallback = 1; alt = 2 }

function Get-TierPrefix {
    <# Ký tự tiền tố cho tier ('' nếu không hợp lệ). THUẦN. #>
    param([string]$Tier)
    if ($script:TierPrefixes.ContainsKey($Tier)) { return $script:TierPrefixes[$Tier] }
    return ''
}

function Get-TierRank {
    <# Thứ hạng tier (0 = cao nhất; 99 = không có). THUẦN. #>
    param([string]$Tier)
    if ($script:TierRanks.ContainsKey($Tier)) { return $script:TierRanks[$Tier] }
    return 99
}

function Get-RecommendTierInName {
    <#
    .SYNOPSIS
        Tier hiện có trong name ('' nếu không có). Chấp nhận tier nằm trước HOẶC sau
        1 health badge (⚡🐌🟡🔒⛔). THUẦN.
    #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $m = [regex]::Match($Name, '^\s*(?:[⚡🐌🟡🔒⛔]\s*)?(⭐|✦|·)')
    if (-not $m.Success) { return '' }
    switch ($m.Groups[1].Value) {
        '⭐' { return 'primary' }
        '✦' { return 'fallback' }
        '·' { return 'alt' }
    }
    return ''
}

function Remove-TierPrefixInName {
    <# Gỡ tiền tố tier (⭐/✦/·) ở đầu name, giữ health badge + phần còn lại. THUẦN. #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    return ($Name -replace '^\s*(?:⭐|✦|·)\s*', '').TrimStart()
}

function Set-TierPrefixInName {
    <# Gắn/thay tiền tố tier ở đầu name (idempotent). THUẦN. #>
    param([string]$Name, [string]$Tier)
    $clean = Remove-TierPrefixInName $Name
    $prefix = Get-TierPrefix $Tier
    if ([string]::IsNullOrWhiteSpace($prefix)) { return $clean }
    return ($prefix + ' ' + $clean)
}

# ── Tiền tố ⭐ trong name (tương thích cũ) ────────────────────

function Test-ModelHasStar {
    <# Name có tier prefix nào (⭐/✦/·) không. THUẦN. #>
    param([string]$Name)
    return (-not [string]::IsNullOrWhiteSpace((Get-RecommendTierInName $Name)))
}

function Remove-StarInName {
    <# Gỡ tiền tố ⭐ (chỉ ⭐), giữ nguyên phần còn lại. THUẦN. #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    return ($Name -replace '^\s*⭐\s*', '').TrimStart()
}

function Set-StarInName {
    <# Gắn tiền tố ⭐ (nếu chưa có), giữ nguyên phần còn lại. THUẦN. #>
    param([string]$Name)
    return (Set-TierPrefixInName -Name $Name -Tier 'primary')
}

# ── Orchestrator tầng 2 ───────────────────────────────────────

function Resolve-StarRules {
    <#
    .SYNOPSIS
        Orchestrator tầng 2: candidates + capabilities → { Rows; Map }. THUẦN.
        -Top N: số ứng viên mỗi mục đích/scope (mặc định 1).
        Rows = danh sách dòng đề xuất; Map = gộp theo "provider|id".
    #>
    param($Candidates, $Capabilities, [int]$Top = 1)
    $rows = Resolve-StarRecommendation -Candidates $Candidates -Capabilities $Capabilities -Top $Top
    $map = Merge-Recommendation -Rows $rows
    return [pscustomobject]@{ Rows = @($rows); Map = $map }
}
