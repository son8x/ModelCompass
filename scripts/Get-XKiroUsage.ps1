#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Giám sát hạn mức sử dụng xKiro (free-token + budget paid + wallet).

.DESCRIPTION
    Gọi endpoint MIỄN PHÍ GET /v1/usage của xKiro (không tốn token, không tính
    vào rate limit) và hiển thị:
        - Free-model tokens: đã dùng / hạn mức ngày / còn lại
        - Spend windows paid: budget (7 ngày) + window burst (~5 giờ)
        - Wallet balance (nếu có)

    Key được đọc theo thứ tự: biến môi trường XTROUTER_API_KEY -> .env.local
    (scripts\ hoặc repo root). Script KHÔNG BAO GIỜ in key ra màn hình.

.PARAMETER Refresh
    Số giây giữa các lần tự refresh (chế độ theo dõi trực tiếp). Mặc định 0 = 1 lần.

.PARAMETER Json
    Chỉ xuất JSON thu gọn ra stdout (dùng để pipe / script khác), không in tiêu đề.

.PARAMETER TimeoutSeconds
    Thời gian chờ tối đa mỗi request (mặc định 20s).

.EXAMPLE
    pwsh scripts\Get-XKiroUsage.ps1                  # xem 1 lần
    pwsh scripts\Get-XKiroUsage.ps1 -Refresh 60      # theo dõi liên tục mỗi phút
    pwsh scripts\Get-XKiroUsage.ps1 -Json | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [int]$Refresh = 0,
    [switch]$Json,
    [int]$TimeoutSeconds = 20
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')
$ProgressPreference = 'SilentlyContinue'

function Get-XKiroApiKey {
    # 1) biến môi trường (đã set qua setup-opencode-env.ps1)
    $fromEnv = Resolve-EnvValue '{env:XTROUTER_API_KEY}'
    if ($fromEnv) { return $fromEnv }

    # 2) tệp .env.local (scripts\ hoặc repo root)
    $candidates = @(
        (Join-Path $PSScriptRoot '.env.local'),
        (Join-Path (Get-RepoRoot) '.env.local')
    )
    foreach ($p in $candidates) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        foreach ($line in Get-Content -LiteralPath $p -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*export\s+XKIRO|XTROUTER') { } # chấp nhận cả 2 tên, xử lý dưới
            if ($line -match '^\s*(?:XKIRO|XTROUTER)_API_KEY\s*=\s*(.+?)\s*$') {
                $v = $Matches[1].Trim().Trim('"').Trim("'")
                if ($v) { return $v }
            }
        }
    }
    return $null
}

function Format-Count {
    param([double]$Value)
    if ($null -eq $Value) { return '-' }
    if ($Value -ge 1e9) { return ('{0:N2}B' -f ($Value / 1e9)) }
    if ($Value -ge 1e6) { return ('{0:N2}M' -f ($Value / 1e6)) }
    if ($Value -ge 1e3) { return ('{0:N1}K' -f ($Value / 1e3)) }
    return ('{0:F0}' -f $Value)
}

function Format-Usd {
    param([string]$Value)
    if ($null -eq $Value) { return '$0.00' }
    try { return ('${0:N2}' -f [double]$Value) } catch { return $Value }
}

function Format-Duration {
    param([int]$Sec)
    if ($Sec -lt 0) { $Sec = 0 }
    $d = [math]::Floor($Sec / 86400)
    $h = [math]::Floor(($Sec % 86400) / 3600)
    $m = [math]::Floor(($Sec % 3600) / 60)
    if ($d -gt 0) { return ("{0}d {1}h {2}m" -f $d, $h, $m) }
    if ($h -gt 0) { return ("{0}h {1}m" -f $h, $m) }
    return ("{0}m" -f $m)
}

function Show-Usage {
    param($u, [bool]$AsJson)

    if ($AsJson) {
        $trim = [ordered]@{
            plan       = $u.plan
            free_tokens = @{
                limit_per_day = $u.free_tokens.limit_per_day
                used_today    = $u.free_tokens.used_today
                remaining     = $u.free_tokens.remaining
            }
            windows = @(
                foreach ($w in $u.windows) {
                    [ordered]@{
                        kind       = $w.kind
                        label      = if ($w.kind -eq 'short') { 'burst' } else { 'budget' }
                        window_sec = $w.window_sec
                        cap_usd    = $w.cap_usd
                        spent_usd  = $w.spent_usd
                        remaining  = $w.remaining_usd
                        resets_in_sec = $w.resets_in_sec
                    }
                }
            )
            wallet = if ($u.wallet) { [ordered]@{ balance_usd = $u.wallet.balance_usd } } else { $null }
        }
        Write-Output ($trim | ConvertTo-Json -Depth 6 -Compress)
        return
    }

    Write-Step ("xKiro USAGE  —  plan: {0}" -f $(if ($u.plan) { $u.plan } else { 'PAYG' }))

    # ── Free-model tokens ──
    if ($u.free_tokens) {
        $lim = [double]$u.free_tokens.limit_per_day
        $used = [double]$u.free_tokens.used_today
        $rem  = [double]$u.free_tokens.remaining
        if ($lim -gt 0) {
            $pct = (($lim - $rem) / $lim) * 100
            $color = if ($pct -ge 90) { 'Red' } elseif ($pct -ge 70) { 'Yellow' } else { 'Green' }
            Write-Host ("  FREE TOKENS : {0} / {1} hôm nay  ({2:F0}%)" -f
                (Format-Count $used), (Format-Count $lim), $pct) -ForegroundColor $color
            Write-Host ("    còn lại   : {0} token" -f (Format-Count $rem)) -ForegroundColor $color
        } else {
            Write-Host ("  FREE TOKENS : {0} đã dùng hôm nay (không có hạn mức)" -f (Format-Count $used)) -ForegroundColor Cyan
        }
    }

    # ── Spend windows (paid) ──
    foreach ($w in $u.windows) {
        $label = if ($w.kind -eq 'short') { 'BURST  (~5h)  ' } else { 'BUDGET (7 ngày)' }
        $cap = [double]$w.cap_usd; $spent = [double]$w.spent_usd; $rem = [double]$w.remaining_usd
        if ($cap -gt 0) {
            $pctSpent = ($spent / $cap) * 100
            $color = if ($pctSpent -ge 90) { 'Red' } elseif ($pctSpent -ge 70) { 'Yellow' } else { 'Green' }
            Write-Host ("  {0} : {1} / {2}  ({3:F0}%)" -f $label, (Format-Usd $spent), (Format-Usd $cap), $pctSpent) -ForegroundColor $color
            Write-Host ("    còn lại   : {0}   —   reset sau {1}" -f (Format-Usd $rem), (Format-Duration ([int]$w.resets_in_sec))) -ForegroundColor $color
        }
    }

    # ── Wallet ──
    if ($u.wallet) {
        Write-Host ("  WALLET      : {0}" -f (Format-Usd $u.wallet.balance_usd)) -ForegroundColor DarkCyan
    }
}

$key = Get-XKiroApiKey
if (-not $key) {
    Write-Fail 'Thiếu key xKiro. Chạy: pwsh scripts\setup-opencode-env.ps1  (hoặc đặt XTROUTER_API_KEY).'
    exit 1
}

$uri = 'https://api.xkiro.com/v1/usage'
$headers = @{ Authorization = "Bearer $key"; 'x-api-key' = $key }

try {
    $usage = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
} catch {
    Write-Fail "Không đọc được /v1/usage: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
        Write-Fail "HTTP $code — kiểm tra lại key / đăng nhập xkiro.com"
    }
    exit 1
}

if ($Refresh -gt 0) {
    while ($true) {
        Clear-Host
        Write-Info ("Theo dõi liên tục, refresh mỗi {0}s (Ctrl+C để dừng) — {1}" -f $Refresh, (Get-Date -Format 'HH:mm:ss'))
        Show-Usage -u $usage -AsJson $false
        Start-Sleep -Seconds $Refresh
        try {
            $usage = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
        } catch {
            Write-Fail "Lỗi refresh: $($_.Exception.Message)"
            Start-Sleep -Seconds $Refresh
        }
    }
} else {
    Show-Usage -u $usage -AsJson $Json
}