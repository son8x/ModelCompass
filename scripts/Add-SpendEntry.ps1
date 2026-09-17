#Requires -Version 7
<#
.SYNOPSIS
    ModelCompass: Ghi 1 bản ghi chi phí vào spend log (mặc định reports/spend.jsonl).

.DESCRIPTION
    Dùng cho script/ plugin giám sát đa provider (mở rộng từ xKiro): sau mỗi phiên
    trả lời, ghi (provider, model, token in/out, chi phí USD) để Get-SpendReport.ps1
    tổng hợp theo ngày/model.

    Chi phí tính = token / 1.000.000 × giá (giá báo theo 1M token, như catalog live).
    Có thể truyền thẳng -CostIn/-CostOut để bỏ qua phép tính.

.PARAMETER Provider
    Tên provider: xkiro | teamo | openrouter | omniroute | 9router (bất kỳ chuỗi).

.PARAMETER Model
    ID model (vd 'openai/gpt-5.6-sol').

.PARAMETER PromptTokens
    Số token input.

.PARAMETER CompletionTokens
    Số token output.

.PARAMETER PriceIn
    Giá input (USD / 1M token). Mặc định 0 (free).

.PARAMETER PriceOut
    Giá output (USD / 1M token). Mặc định 0 (free).

.PARAMETER CostIn
    Ghi đè chi phí input (bỏ qua PriceIn).

.PARAMETER CostOut
    Ghi đè chi phí output (bỏ qua PriceOut).

.PARAMETER Note
    Ghi chú (vd use-case, tên phiên).

.PARAMETER Path
    File log khác (mặc định reports/spend.jsonl dưới repo root).

.EXAMPLE
    pwsh scripts\Add-SpendEntry.ps1 -Provider xkiro -Model 'openai/gpt-5.6-sol' `
        -PromptTokens 120000 -CompletionTokens 30000 -PriceIn 4.5 -PriceOut 27
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Provider,
    [Parameter(Mandatory)][string]$Model,
    [long]$PromptTokens = 0,
    [long]$CompletionTokens = 0,
    [double]$PriceIn = 0,
    [double]$PriceOut = 0,
    [double]$CostIn,
    [double]$CostOut,
    [string]$Note = '',
    [string]$Path
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$computed = ConvertTo-SpendCost -PromptTokens $PromptTokens -CompletionTokens $CompletionTokens -PriceIn $PriceIn -PriceOut $PriceOut
$costIn  = if ($PSBoundParameters.ContainsKey('CostIn'))  { $CostIn  } else { $computed.CostIn  }
$costOut = if ($PSBoundParameters.ContainsKey('CostOut')) { $CostOut } else { $computed.CostOut }

$file = Add-SpendEntry -Provider $Provider -Model $Model `
    -PromptTokens $PromptTokens -CompletionTokens $CompletionTokens `
    -CostInUsd $costIn -CostOutUsd $costOut -Note $Note -Path $Path

Write-Ok ("Đã ghi: {0} | {1} | in {2}/{3} tok | {4} (in) + {5} (out)" -f
    $Provider, $Model, $PromptTokens, $CompletionTokens, ('${0:N4}' -f $costIn), ('${0:N4}' -f $costOut))
Write-Info "Spend log: $file"
exit 0