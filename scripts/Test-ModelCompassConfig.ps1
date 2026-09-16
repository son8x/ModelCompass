#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Validate cấu hình opencode (JSON/JSONC) theo chuẩn ModelCompass.

.DESCRIPTION
    Kiểm tra:
      - Cú pháp JSON(C) hợp lệ.
      - Có "$schema" và "model" đúng dạng provider/model-id.
      - Mỗi provider có ít nhất 1 model.
      - Options.baseURL / npm có vẻ hợp lệ.
      - Mọi {env:VAR} trong file có biến môi trường tương ứng (warning/mặc định).

.PARAMETER Path
    Đường dẫn tới file cấu hình. Mặc định: configs\production\opencode.json

.PARAMETER Strict
    Biến cấu hình thiếu -> coi là LỖI (dùng trong CI khi muốn chặt chẽ).

.EXAMPLE
    PS scripts\Test-ModelCompassConfig.ps1 -Path configs\development\opencode.jsonc
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Strict
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path (Get-RepoRoot) 'configs\production\opencode.json'
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Fail "Không tìm thấy file: $Path"
    exit 1
}
$Path = (Get-Item -LiteralPath $Path).FullName

Write-Step "Validate: $Path"
$config   = Get-ConfigContent $Path
$errors   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

# ── $schema ────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($config.'$schema')) {
    $errors.Add('Thiếu "$schema". Nên khai báo "https://opencode.ai/config.json".')
}

# ── model ──────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($config.model)) {
    $errors.Add('Thiếu "model". Yêu cầu dạng provider/model-id.')
} elseif ($config.model -notmatch '/') {
    $errors.Add("Model thiếu tiền tố provider: '$($config.model)' (phải là provider/model-id).")
}

# ── providers ──────────────────────────────────────────────
if ($null -ne $config.provider) {
    $properties = @($config.provider.PSObject.Properties)
    if ($properties.Count -eq 0) {
        $warnings.Add('Provider rỗng — sẽ không có model có thể chọn.')
    }
    foreach ($p in $properties) {
        $name = $p.Name
        $def  = $p.Value
        $modelProps = if ($null -ne $def.models) { @($def.models.PSObject.Properties) } else { @() }
        $nModels = $modelProps.Count
        if ($nModels -eq 0) {
            $errors.Add("Provider '$name': không có model nào (mục 'models' trống).")
        }
        if ([string]::IsNullOrWhiteSpace($def.npm)) {
            $warnings.Add("Provider '$name': thiếu 'npm' (vd: '@ai-sdk/openai-compatible').")
        }
        $burl = $null
        if ($null -ne $def.options) { $burl = $def.options.baseURL }
        if ([string]::IsNullOrWhiteSpace($burl)) {
            $warnings.Add("Provider '$name': thiếu options.baseURL.")
        }
    }
} else {
    $warnings.Add('Không có mục "provider" trong cấu hình.')
}

# ── env vars ───────────────────────────────────────────────
# Quét trên nội dung đã bỏ comment (tránh báo nhầm env trong ví dụ/chú thích)
$clean = Remove-CommentsAndTrailingCommas (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
foreach ($m in [regex]::Matches($clean, '\{env:([^}]+)\}')) {
    $name = $m.Groups[1].Value
    $val  = [Environment]::GetEnvironmentVariable($name)
    if ($null -eq $val -or '' -eq $val) {
        $msg = "Biến môi trường '$name' chưa được đặt — provider/model này sẽ không có API key."
        if ($Strict) { $errors.Add($msg) } else { $warnings.Add($msg) }
    }
}

# ── báo cáo ────────────────────────────────────────────────
if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Fail $e }
    Write-Fail "Kết quả: FAIL ($($errors.Count) lỗi)"
    exit 1
}
if ($warnings.Count -gt 0) {
    foreach ($w in $warnings) { Write-Warn $w }
    Write-Info "Kết quả: OK nhưng có $($warnings.Count) cảnh báo"
    exit 0
}
Write-Ok "Kết quả: OK — cấu hình hợp lệ, không cảnh báo."
exit 0