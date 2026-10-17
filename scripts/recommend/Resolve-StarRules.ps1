#Requires -Version 7
<#
Resolve-StarRules.ps1 — ModelCompass · tầng 2/3 của "Đề xuất ⭐ xKiro".

THƯ VIỆN hàm thuần (không có khối chạy chính) — ÁP RULE (heuristic tên + bảng tra) để chọn model
nên gắn ⭐ theo NHÓM (free/L/B/A/S) và theo MỤC ĐÍCH (reasoning/code/analysis/writing/vision/omni/
translate/fast/lecture/bulk/flagship):
  - Read-ModelCapabilities      : đọc bảng tra tay model-capabilities.json
  - Get-ModelCapability         : suy tag khả năng từ id+name (heuristic) + hợp nhất tag bảng tra
  - Select-RecommendedCandidate : chọn 1 ứng viên trong pool theo Order (top/cheap/ctx)
  - Resolve-StarRecommendation  : → danh sách dòng đề xuất (preferred thắng rule)
  - Merge-Recommendation        : gộp dòng theo khoá "provider|id"
  - Test/Remove/Set-StarInName  : thao tác tiền tố ⭐ trong name
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

function Select-RecommendedCandidate {
    <#
    .SYNOPSIS
        Chọn 1 ứng viên trong pool theo thứ tự. THUẦN.
        Order: 'top'   = release_date giảm dần → input tăng dần → ctx giảm dần.
               'cheap' = input tăng dần → ctx giảm dần.
               'ctx'   = ctx giảm dần → input tăng dần.
        Trả $null nếu pool rỗng.
    #>
    param($Pool, [string]$Order = 'top')
    $arr = @($Pool)
    if ($arr.Count -eq 0) { return $null }
    $byIn = { if ($null -ne $_.In) { [double]$_.In } else { [double]::MaxValue } }
    switch ($Order) {
        'cheap' { $arr = @($arr | Sort-Object @{ Expression = $byIn; Descending = $false }, @{ Expression = { -[int]$_.Context }; Descending = $false }) }
        'ctx'   { $arr = @($arr | Sort-Object @{ Expression = { -[int]$_.Context }; Descending = $false }, @{ Expression = $byIn; Descending = $false }) }
        default {
            $arr = @($arr | Sort-Object `
                @{ Expression = { if ($_.ReleaseDate) { [string]$_.ReleaseDate } else { '0000-00-00' } }; Descending = $true }, `
                @{ Expression = $byIn; Descending = $false }, `
                @{ Expression = { -[int]$_.Context }; Descending = $false })
        }
    }
    return $arr[0]
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

function Resolve-StarRecommendation {
    <#
    .SYNOPSIS
        Trả danh sách dòng đề xuất: mỗi dòng { Kind='purpose'|'group'; Key; Label; Scope; ModelId;
        Source='table'|'rule'; Candidate }. THUẦN.
        preferred (bảng tra) thắng rule; nếu model preferred đã biến mất khỏi config → dùng rule.
    #>
    param($Candidates, $Capabilities, $Purposes = $null, $Groups = $null)
    if ($null -eq $Purposes) { $Purposes = $script:StarPurposes }
    if ($null -eq $Groups) { $Groups = $script:StarGroups }

    $free = @($Candidates | Where-Object { $_.Group -eq 'free' })
    $paid = @($Candidates | Where-Object { $_.Group -in @('L', 'B', 'A', 'S') })

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in @($Purposes)) {
        foreach ($scope in @($spec.Scopes)) {
            $pool = if ($scope -eq 'free') { $free } else { $paid }
            $pick = $null; $src = ''
            if ($null -ne $Capabilities -and $Capabilities.Preferred.ContainsKey($spec.Id) -and
                $Capabilities.Preferred[$spec.Id].ContainsKey($scope)) {
                $prefId = $Capabilities.Preferred[$spec.Id][$scope]
                $pick = @($pool | Where-Object { $_.Id -eq $prefId }) | Select-Object -First 1
                if ($null -ne $pick) { $src = 'table' }
            }
            if ($null -eq $pick -and $spec.Tag) {
                $cand = @($pool | Where-Object { (Get-CandidateEffectiveTags $_ $Capabilities) -contains $spec.Tag })
                if ($cand.Count -gt 0) { $pick = Select-RecommendedCandidate -Pool $cand -Order $spec.Order; $src = 'rule' }
            }
            if ($null -eq $pick) { continue }
            $rows.Add([pscustomobject]@{
                Kind = 'purpose'; Key = $spec.Id; Label = $spec.Label; Scope = $scope
                ModelId = $pick.Id; Source = $src; Candidate = $pick
            })
        }
    }

    foreach ($g in @($Groups)) {
        $sig = $g.Signature
        $match = @($rows | Where-Object { $_.Key -eq $sig.Purpose -and $_.Scope -eq $sig.Scope }) | Select-Object -First 1
        if ($null -ne $match) {
            $rows.Add([pscustomobject]@{
                Kind = 'group'; Key = $g.Id; Label = "nhóm $($g.Id)"; Scope = $sig.Scope
                ModelId = $match.ModelId; Source = $match.Source; Candidate = $match.Candidate
            })
        }
    }
    return @($rows)
}

function Merge-Recommendation {
    <#
    .SYNOPSIS
        Gộp các dòng đề xuất → hashtable "provider|id" -> { Provider; ModelId; Groups=@(); Purposes=@() }.
        Khoá theo provider+id vì cùng model-id có thể xuất hiện ở cả 1-xkiro-free lẫn 2-xkiro-max. THUẦN.
    #>
    param($Rows)
    $map = @{}
    foreach ($r in @($Rows)) {
        $key = Get-RecommendationKey -Provider $r.Candidate.Provider -ModelId $r.ModelId
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [pscustomobject]@{
                Provider = $r.Candidate.Provider
                ModelId  = $r.ModelId
                Groups   = [System.Collections.Generic.List[string]]::new()
                Purposes = [System.Collections.Generic.List[string]]::new()
            }
        }
        if ($r.Kind -eq 'group') {
            [void]$map[$key].Groups.Add([string]$r.Key)
        } else {
            $tag = if ($r.Scope -eq 'free') { "$($r.Key)(free)" } else { [string]$r.Key }
            [void]$map[$key].Purposes.Add($tag)
        }
    }
    return $map
}

# ── Tiền tố ⭐ trong name ─────────────────────────────────────

function Test-ModelHasStar {
    <# Name có ⭐ ở đầu không. THUẦN. #>
    param([string]$Name)
    return ($Name -match '^\s*⭐')
}

function Remove-StarInName {
    <# Gỡ tiền tố ⭐ (nếu có), giữ nguyên phần còn lại. THUẦN. #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    return ($Name -replace '^\s*⭐\s*', '').TrimStart()
}

function Set-StarInName {
    <# Gắn tiền tố ⭐ (nếu chưa có), giữ nguyên phần còn lại. THUẦN. #>
    param([string]$Name)
    $clean = Remove-StarInName $Name
    return ('⭐ ' + $clean)
}

# ── Orchestrator tầng 2 ───────────────────────────────────────

function Resolve-StarRules {
    <#
    .SYNOPSIS
        Orchestrator tầng 2: candidates + capabilities → { Rows; Map }. THUẦN.
        Rows = danh sách dòng đề xuất; Map = gộp theo "provider|id".
    #>
    param($Candidates, $Capabilities)
    $rows = Resolve-StarRecommendation -Candidates $Candidates -Capabilities $Capabilities
    $map = Merge-Recommendation -Rows $rows
    return [pscustomobject]@{ Rows = @($rows); Map = $map }
}
