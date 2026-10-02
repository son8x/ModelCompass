#Requires -Version 7.0
<#
.SYNOPSIS
    ModelCompass: Cài đặt & kiểm tra biến môi trường cho opencode (User scope).

.DESCRIPTION
    Đọc key từ tệp .env.local (KHÔNG commit lên git) hoặc hỏi tay, rồi set vào
    Environment scope "User" để opencode dùng qua cú pháp {env:TEN_BIEN}.

    Nguồn dữ liệu (ưu tiên từ trên xuống):
      1) tệp .env.local (tự tìm: thư mục repo root, rồi scripts\)
      2) biến env đang chạy trong phiên làm việc
      3) giá trị User env đã set trước đó
      4) prompt nhập tay (tắt được bằng -NonInteractive)

    Script KHÔNG BAO GIỜ in giá trị key đầy đủ ra màn hình (luôn che giấu).

.PARAMETER Check
    Chỉ kiểm tra trạng thái, không set gì. Exit code 1 nếu thiếu biến bắt buộc.

.PARAMETER CreateSample
    Tạo tệp .env.sample (chỉ TÊN TRƯỜNG + placeholder, KHÔNG có giá trị thật).
    Tên biến được quét tự động từ các file cấu hình configs\*.  Không đọc
    file .env.local khi tạo mẫu — nên mẫu luôn an toàn để commit.

.PARAMETER SamplePath
    Đường dẫn tệp .env.sample tạo ra. Mặc định: <repo>\.env.sample

.PARAMETER FileName
    Nạp key từ một tệp .env cụ thể (nếu không truyền, tự dò ở trên).

.PARAMETER Force
    Ghi đè giá trị User env hiện có bằng nguồn mới (mặc định: giữ nguyên).

.PARAMETER PromptOptional
    Cũng hỏi nhập tay cho biến TÙY CHỌN đang trống (mặc định: chỉ hỏi biến bắt buộc).

.PARAMETER NonInteractive
    Không hỏi nhập tay; biến nào chưa có sẽ bị bỏ qua (thích hợp CI).

.EXAMPLE
    .\setup-opencode-env.ps1                  # nhập / set toàn bộ key
    .\setup-opencode-env.ps1 -PromptOptional   # kèm hỏi OPENCODE_SERVER_PASSWORD
    .\setup-opencode-env.ps1 -Check           # kiểm tra trạng thái (che giấu)
    .\setup-opencode-env.ps1 -CreateSample    # tạo .env.sample an toàn
    .\setup-opencode-env.ps1 -FileName D:\keys\my.env -Force
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$CreateSample,
    [string]$SamplePath,
    [string]$FileName,
    [switch]$Force,
    [switch]$PromptOptional,
    [switch]$NonInteractive
)

# ── Khung chung + helper ──────────────────────────────────────
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common-Functions.ps1')
$ErrorActionPreference = 'Stop'
$scope = 'User'
$repoRoot = Get-RepoRoot

# Danh sách biến BẮT BUỘC (được tham chiếu thực tế trong cấu hình đang dùng)
$knownVars = @(
    @{ Name = 'TEAMO_API_KEY';       Desc = 'Teamorouter - api.teamorouter.cn (provider 6-teamoRouter)';       Required = $true },
    @{ Name = 'OMNIROUTE_KEY';       Desc = 'Gateway OmniRoute local - 127.0.0.1:20217 (provider 3-omniroute-free, 4-openrouter-free)'; Required = $true },
    @{ Name = 'XTROUTER_API_KEY';    Desc = 'xKiro - api.xkiro.com (provider 1-xkiro-free, 2-xkiro-max)';       Required = $true },
    @{ Name = 'NINE_ROUTER_API_KEY'; Desc = '9Router local - 127.0.0.1:20128 (provider 5-9router)';          Required = $true }
)

# Biến TÙY CHỌN — KHÔNG phải {env:...} trong configs\, không tham chiếu trong cấu hình.
# opencode tự đọc thẳng process.env nên không cần khai trong opencode.json.
# Thiếu chúng không làm hỏng gì → Required = $false để -Check/CI không bao giờ fail.
#
#   Mask = 'Full' : giá trị bí mật nhạy cảm (mật khẩu) → không lộ bất kỳ ký tự nào,
#                   và sẽ hỏi nhập bằng -AsSecureString (không echo lên màn hình).
$optionalVars = @(
    @{ Name = 'OPENCODE_SERVER_PASSWORD'
       Desc = 'HTTP basic auth cho `opencode serve` / `opencode web` (user mặc định: opencode)'
       Required = $false
       Mask = 'Full' }
    @{ Name = 'OPENCODE_SERVER_USERNAME'
       Desc = 'Tên đăng nhập cho basic-auth (mặc định opencode)'
       Required = $false }
)

# Danh sách gộp dùng cho cả 3 chế độ.
$envVars = @($knownVars) + @($optionalVars)

function Test-FullMask {
    param($Var)
    # $Var là hashtable — phải tra key trực tiếp, không dùng PSObject.Properties
    return ([string]$Var['Mask'] -eq 'Full')
}

# ── Tiện ích nội bộ ───────────────────────────────────────────
function Get-EnvVarsFromConfigs {
    <#
    Quét mọi {env:VAR} trong configs\ để ghép danh sách biến.
    Chỉ trả về TÊN — không hề đụng tới giá trị.
    #>
    $found = @()
    $scanned = @()
    $configFiles = @(
        (Join-Path $repoRoot 'configs\production\opencode.json'),
        (Join-Path $repoRoot 'configs\development\opencode.jsonc')
    )
    $configFiles += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'configs\presets') -Filter '*.jsonc' -ErrorAction SilentlyContinue).FullName

    foreach ($f in $configFiles) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $f -Raw -Encoding utf8)
        foreach ($m in [regex]::Matches($clean, '\{env:([^}]+)\}')) {
            $name = $m.Groups[1].Value.Trim()
            if ($name -and $found -notcontains $name -and $scanned -notcontains $name) {
                $found += $name
            }
        }
        $scanned += $f
    }
    return ($found | Sort-Object -Unique)
}

function Find-EnvFile {
    <#
    Trả về đường dẫn tệp .env.local đầu tiên tìm thấy (theo thứ tự ưu tiên).
    #>
    if ($FileName) {
        if (-not (Test-Path -LiteralPath $FileName -PathType Leaf)) {
            throw "Không tìm thấy tệp key: $FileName"
        }
        return (Get-Item -LiteralPath $FileName).FullName
    }
    $candidates = @(
        (Join-Path $repoRoot '.env.local'),
        (Join-Path (Get-ScriptsDir) '.env.local'),
        (Join-Path $PSScriptRoot '.env.local')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Get-Item -LiteralPath $c).FullName }
    }
    return $null
}

function Read-EnvFile {
    <#
    Đọc tệp KEY=VALUE. Bỏ qua dòng trống và comment (#).
    Hỗ trợ cả cú pháp "export VAR=..." và giá trị có nháy '...' hoặc "...".
    Trả về hashtable tên -> giá trị (giá trị chỉ dùng nội bộ, không in ra).
    #>
    param([Parameter(Mandatory)][string]$File)
    $table = @{}
    Get-Content -LiteralPath $File | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        if ($line -match '^\s*export\s+(.+)$') { $line = $Matches[1].Trim() }
        if ($line -match '^([A-Za-z0-9_]+)=(.*)$') {
            $name  = $Matches[1]
            $value = ($Matches[2].Trim())
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $table[$name] = $value
        }
    }
    return $table
}

function Hide-Value {
    <#
    Che giấu chuỗi: chỉ lộ 4 ký tự đầu – 4 ký tự cuối (nếu đủ dài).
    -FullMask: che 100%, cố định 12 dấu '*' — không lộ cả độ dài.
    #>
    param([string]$Value, [switch]$FullMask)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '(trống)' }
    if ($FullMask) { return '*' * 12 }
    if ($Value.Length -le 12) { return ('*' * $Value.Length) }
    return $Value.Substring(0, 4) + ('*' * ([Math]::Min(8, $Value.Length - 8))) + $Value.Substring($Value.Length - 4)
}

function Write-StatusLine {
    # Cột rộng 24 để vừa tên biến dài nhất (OPENCODE_SERVER_PASSWORD = 24 ký tự).
    param([string]$Name, [string]$Desc, [bool]$Required, [string]$Value, [switch]$FullMask)
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        Write-Ok ("{0,-24} -> {1}   ({2})" -f $Name, (Hide-Value $Value -FullMask:$FullMask), $Desc)
    } else {
        $tag = if ($Required) { 'THIẾU - bắt buộc' } else { 'trống - tùy chọn' }
        Write-Warn ("{0,-24} -> {1}   ({2})" -f $Name, $tag, $Desc)
    }
}

function Read-SecretValue {
    <#
    Nhập bí mật không echo (ẩn ký tự trên màn hình), trả về chuỗi thường.
    #>
    param([string]$Name, [string]$Desc)
    $secure = Read-Host "Nhập $Name ($Desc)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        # Xoá bản copy trong bộ nhớ unmanaged ngay sau khi chuyển
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Protect-EmptyValue {
    # Ngăn vô tình đặt giá trị rỗng / chỉ khoảng trắng.
    param([string]$Value, [string]$Name)
    $trimmed = if ($null -eq $Value) { '' } else { $Value.Trim() }
    if ($trimmed -and -not ([bool]($trimmed -match '^[a-f0-9]{12,}$'))) {
        # giữ nguyên — không kiểm tra định dạng quá gắt
    }
    return $trimmed
}

function Assert-EnvFileNotTracked {
    <#
    BẢO MẬT: nếu tệp .env.local đã bị git theo dõi thì NGHI NGỜ key lộ.
    #>
    param([string]$EnvFilePath)
    $rel = [System.IO.Path]::GetRelativePath($repoRoot, $EnvFilePath)
    # GetRelativePath trả về chuỗi TUYỆT ĐỐI khi nằm khác ổ đĩa → coi như ngoài repo
    if ($rel.StartsWith('..') -or [System.IO.Path]::IsPathRooted($rel)) { return $rel }
    $tracked = git ls-files -- $rel
    if ($tracked) {
        throw "TỆP KEY ĐANG BỊ GIT THEO DÕI: $rel`n  Key trong đó đã (hoặc sắp) lộ trên GitHub.`n  KHẮC PHỤC: git rm --cached `"$rel`"`n  Rồi đổi/khóa key cũ trên dashboard nhà cung cấp."
    }
    return $rel
}

# ── CHẾ ĐỘ 1: —CreateSample (tạo mẫu an toàn) ─────────────────
if ($CreateSample) {
    if ([string]::IsNullOrWhiteSpace($SamplePath)) { $SamplePath = Join-Path $repoRoot '.env.sample' }

    # Gom tên biến: danh sách đã biết + mọi {env:...} trong configs
    $all = @{}
    foreach ($v in $envVars) { $all[$v.Name] = $v.Desc }
    foreach ($envName in Get-EnvVarsFromConfigs) {
        if (-not $all.ContainsKey($envName)) {
            $all[$envName] = 'Được tham chiếu trong configs\ - cấu hình opencode của bạn'
        }
    }

    $lines = @(
        '# ═══════════════════════════════════════════════════════════════',
        '#  ModelCompass — .env.sample (MẪU, AN TOÀN ĐỂ COMMIT)',
        '# ═══════════════════════════════════════════════════════════════',
        '#  Tệp này CHỈ chứa TÊN TRƯỜNG và placeholder — KHÔNG có key thật.',
        '#',
        '#  Cách dùng:',
        '#    1. Copy thành .env.local (KHÔNG commit file .env.local):',
        '#         Copy-Item .env.sample .env.local',
        '#    2. Điền giá trị key thật vào .env.local.',
        '#    3. Chạy để nạp vào môi trường User:',
        '#         pwsh scripts\env\setup-opencode-env.ps1 -FileName .env.local',
        '#',
        '#  LƯU Ý: .env.local bị .gitignore chặn — không bao giờ add -f nó lên GitHub.',
        '# ─────────────────────────────────────────────────────────────────' )
    foreach ($k in ($all.Keys | Sort-Object)) {
        $lines += ''
        $lines += ("# {0}" -f $all[$k])
        $lines += ("{0}=" -f $k)
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $SamplePath) | Out-Null
    Set-Content -LiteralPath $SamplePath -Value $lines -Encoding utf8
    Write-Ok "Đã tạo mẫu: $SamplePath"
    Write-Info 'Mẫu chỉ có tên trường — an toàn để commit. Điền giá trị vào .env.local (bản sao cục bộ).'
    exit 0
}

# ── CHẾ ĐỘ 2: -Check (chỉ kiểm tra) ───────────────────────────
if ($Check) {
    Write-Step "KIỂM TRA BIẾN MÔI TRƯỜNG (scope: $scope)"
    $missingRequired = 0
    foreach ($v in $envVars) {
        $val = [System.Environment]::GetEnvironmentVariable($v.Name, $scope)
        Write-StatusLine -Name $v.Name -Desc $v.Desc -Required $v.Required -Value $val -FullMask:(Test-FullMask $v)
        if ($v.Required -and [string]::IsNullOrWhiteSpace($val)) { $missingRequired++ }
    }
    Write-Info 'Biến chưa đặt sẽ không ảnh hưởng tới cú pháp cấu hình, nhưng provider tương ứng sẽ không gọi được.'
    if ($missingRequired -gt 0) {
        Write-Fail "Thiếu $missingRequired biến bắt buộc."
        exit 1
    }
    Write-Ok 'Đủ biến bắt buộc.'
    exit 0
}

# ── CHẾ ĐỘ 3: set biến môi trường ─────────────────────────────
Write-Step "CÀI ĐẶT BIẾN MÔI TRƯỜNG (scope: $scope)"

# An toàn: kiểm tra tệp key xem có lọt vào git theo dõi không
$envFilePath = Find-EnvFile
if ($envFilePath) {
    $rel = Assert-EnvFileNotTracked -EnvFilePath $envFilePath
    Write-Info "Đọc key từ: $rel"
    $envTable = Read-EnvFile -File $envFilePath

    # Cảnh báo biến lạ trong file: thường là gõ sai tên (vd PASSWORD/_USERNAME)
    # — nếu im lặng bỏ qua, người dùng tưởng đã set mà thực ra chưa.
    $knownNames = $envVars | ForEach-Object { $_.Name }
    $unknown = @($envTable.Keys | Where-Object { $knownNames -notcontains $_ } | Sort-Object)
    foreach ($u in $unknown) {
        Write-Warn "BỎ QUA - không nhận biết: $u trong $rel (tên không khớp biến nào trong danh sách)"
    }

    # Biến có trong file nhưng để TRỐNG → rất dễ tưởng là đã set xong.
    $blanks = @($envVars | Where-Object {
        $envTable.ContainsKey($_.Name) -and [string]::IsNullOrWhiteSpace($envTable[$_.Name])
    } | ForEach-Object { $_.Name })
    foreach ($b in $blanks) {
        Write-Warn "TRỐNG trong file: $b (dòng có trong $rel nhưng chưa điền giá trị)"
    }
} else {
    $envTable = @{}
    Write-Warn 'Không tìm thấy .env.local — sẽ dùng biến env hiện có hoặc hỏi tay.'
}

foreach ($v in $envVars) {
    $current  = [System.Environment]::GetEnvironmentVariable($v.Name, $scope)
    $newValue = ''
    $isSecret = Test-FullMask $v

    # 1) từ .env.local
    if ($envTable.ContainsKey($v.Name)) { $newValue = $envTable[$v.Name] }

    # 2) từ biến env của phiên hiện tại
    if ([string]::IsNullOrWhiteSpace($newValue)) {
        $proc = Get-ChildItem Env: -ErrorAction SilentlyContinue | Where-Object Name -eq $v.Name
        if ($proc) { $newValue = $proc.Value }
    }

    # 3) giá trị đã set User env trước đó (trừ khi -Force)
    if ((-not $Force) -and [string]::IsNullOrWhiteSpace($newValue)) {
        $newValue = $current
    }

    # 4) nếu vẫn trống → hỏi tay. Biến bắt buộc luôn hỏi;
    #    biến tùy chọn chỉ hỏi khi có -PromptOptional (trừ -NonInteractive).
    $wantPrompt = $v.Required -or $PromptOptional
    if ([string]::IsNullOrWhiteSpace($newValue) -and $wantPrompt -and (-not $NonInteractive)) {
        if ($isSecret) {
            $newValue = Read-SecretValue -Name $v.Name -Desc $v.Desc
        } else {
            $newValue = Read-Host "Nhập $($v.Name) ($($v.Desc))"
        }
    }

    $newValue = Protect-EmptyValue -Value $newValue -Name $v.Name

    if (-not [string]::IsNullOrWhiteSpace($newValue)) {
        [System.Environment]::SetEnvironmentVariable($v.Name, $newValue, $scope)
        Set-Item -Path "Env:$($v.Name)" -Value $newValue
        Write-StatusLine -Name $v.Name -Desc $v.Desc -Required $v.Required -Value $newValue -FullMask:$isSecret
    } else {
        Write-StatusLine -Name $v.Name -Desc $v.Desc -Required $v.Required -Value '' -FullMask:$isSecret
    }
}

Write-Host ''
Write-Ok "Xong. Mở cửa sổ opencode/pwsh MỚI để áp dụng."
Write-Info "Key được đọc từ .env.local (đã bị gitignore) — an toàn khỏi GitHub."
Write-Host "  Mẫu an toàn: .env.sample   |   Tạo lại: pwsh scripts\env\setup-opencode-env.ps1 -CreateSample" -ForegroundColor DarkCyan

# Gợi ý riêng khi biến server password đã có giá trị
if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable('OPENCODE_SERVER_PASSWORD', $scope))) {
    Write-Host ''
    Write-Info 'OPENCODE_SERVER_PASSWORD đã được set — MỌI phiên opencode (kể cả TUI) sẽ bắt basic-auth.'
    Write-Host '  Chạy server có bảo vệ : opencode serve --port 4096' -ForegroundColor DarkCyan
    Write-Host '  Đăng nhập             : user "opencode" (đổi bằng OPENCODE_SERVER_USERNAME)' -ForegroundColor DarkCyan
    Write-Host '  Gỡ bỏ                 : [Environment]::SetEnvironmentVariable("OPENCODE_SERVER_PASSWORD", $null, "User")' -ForegroundColor DarkCyan
}