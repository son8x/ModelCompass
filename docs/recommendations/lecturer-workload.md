# 🎯 Đề xuất model theo workload thực tế (của tôi)

> Phân tích từ **170 session** trong `opencode.db` (03/09–07/10/2026) +
> usage API live xKiro. Cập nhật lần cuối: **07/10/2026**.
> Mục tiêu: **mạnh — tối ưu chi phí — tận dụng free + paid**.

## 1. Phân tích nhu cầu thực tế

| Nhóm nhu cầu | Session | Chiếm (ước) | Yêu cầu model |
|---|---|---|---|
| **Nghiên cứu / Review** (luận văn, hồ sơ, văn bản, TT55) | 29 | ~44% | 1M ctx, reasoning, vision, tiếng Việt tốt |
| **Giảng dạy / PPTX / CTĐT** | 13 | ~15% (nặng nhất/session: ~18M cache) | 1M ctx, cấu trúc giỏi, **input rẻ** |
| **Coding / Tooling** (scripts PowerShell, test, ModelCompass) | 36 | ~20% | code giỏi, nhanh |
| **Trao đổi / subagent nhẹ** (explore, general, hỏi nhanh) | 94 | ~21% | nhanh, rẻ |

### Bài toán chi phí

- **~85% chi phí đến từ input/cache-read** (224M token/tuần ≈ $90/tuần),
  output chỉ ~1M token/tuần → **giá input quyết định tất cả**.
- Minh chứng all-time (589M input của Sonnet 5, giá list):

| Model dùng cho bulk input | Chi phí cùng số token |
|---|---|
| Claude Sonnet 5 ($2.00) | $1,178 |
| GLM-5.3 ($1.40) | $825 |
| Gemini 3.8 Flash ($0.75) | $442 |
| **GLM-5.2 ($0.25)** | **$147** |
| **Model free ($0)** | **$0** |

- Tuần hiện tại (rolling 7d, API live): **$90 / $140 budget = 64%** —
  pace tuần này ~$110 (nóng nhất từ trước tới nay).

## 2. Gợi ý theo từng nhu cầu

### A. Nghiên cứu / Review luận văn, phân tích tài liệu (quan trọng nhất)

| Ưu tiên | Trả phí (2-xkiro-max) | Miễn phí (1-xkiro-free) |
|---|---|---|
| **Mạnh, mặc định** | `[A] google/gemini-3.1-pro` · $2/$12 · 1M | `qwen/qwen3.8-max:free` · 1M · vision/reasoning |
| **Viết/Vietnamese tự nhiên** | `[A] anthropic/claude-sonnet-5` · $2/$10 | `qwen/qwen3.7-plus:free` · 1M — pass nhanh/cắt câu |
| **Rẻ mà vẫn mạnh** | `[A] z-ai/glm-5.3` · $1.40/$4.40 (tag VN/code) | `mistralai/mistral-large-2512` — paraphrase/rewrite |
| **Chương quan trọng nhất (S)** | `[S] openai/gpt-6.1-sol` · **$2/$10** (S nhưng input rẻ ngang Sonnet) | `qwen/qwen3-vl-plus:free` — bảng/biểu (vision) |

> ❌ Tránh `claude-opus-5` ($5 input) cho bulk đọc tài liệu — burn allowance
> gấp 2.5× Sonnet. Chỉ dùng Opus khi **chất lượng quyết định**.

### B. Soạn bài / PPTX / CTĐT (input khổng lồ → ưu tiên input RẺ)

| Ưu tiên | Trả phí | Miễn phí |
|---|---|---|
| **Tốt nhất/tiền** | `[A] mistralai/mistral-large-4-0` · **$0.00/$0.00** (08/10: catalog free → không trừ budget) | ✅ `mistralai/mistral-large-4-0` (free, 524K, 08/10) |
| **1M ctx, input rẻ** | `[A] google/gemini-3.8-flash` · $0.75/$3.75 · 1M | `qwen/qwen3.8-max:free` · 1M |
| **Bulk processing** | `[B] z-ai/glm-5.2` · **$0.25/$3.99** · 1M | `qwen/qwen3.6-max-preview:free` — reasoning |

### C. Coding / Tooling

| Ưu tiên | Trả phí | Miễn phí |
|---|---|---|
| **Agent/code sâu** | `[A] openai/gpt-5.6-terra` · $1/$6 · 1M | `qwen/qwen3-coder-plus:free` · 1M · code |
| **PowerShell/CLI** | `[A] z-ai/glm-5.3` · $1.40/$4.40 | `mistralai/codestral-2508` · `devstral-medium` |
| **Task nhỏ, nhanh, rẻ** | `[L] nvidia/nemotron-3-super` · **$0.08/$0.45** · 1M · code | — |

### D. Subagent nhẹ / hỏi nhanh (94 session!)

| Trả phí | Miễn phí |
|---|---|
| `[L] z-ai/glm-5.3-flash` · $0.15/$0.50 · vision | `qwen/qwen3.5-flash:free` · 1M · fast |
| `[L] openai/gpt-6-luna` · $0.10/$0.50 · reasoning/vision | `qwen/qwen3.7-flash:free` · vision |
| `[L] google/gemini-3-flash` · $0.75/$3.75 · 1M | `minimax/minimax-m3:free` (probe lại nếu lỗi 500) |

## 3. Bộ preset khuyên dùng (mặc định hằng ngày)

```
Mặc định (default)   : 1-xkiro-free/qwen/qwen3.8-max:free   ← đã set, miễn phí
Nghiên cứu/Review    : google/gemini-3.1-pro   (fallback: qwen3.8-max:free)
Soạn bài/PPTX/CTĐT   : mistralai/mistral-large-4-0 (FREE 08/10) hoặc z-ai/glm-5.2   ← input rẻ nhất
Coding               : openai/gpt-5.6-terra    (fallback: qwen3-coder-plus:free)
Subagent/nhẹ         : z-ai/glm-5.3-flash      (hoặc qwen3.5-flash:free)
Chốt chất lượng cao  : openai/gpt-6.1-sol (S, $2 input) hoặc claude-sonnet-5
```

## 4. Quy tắc vàng tối ưu chi phí

1. **Input price = chi phí (85%)**: bulk đọc file/tạo PPTX → model
   **input ≤ $0.75** hoặc **free**. Sonnet/Opus chỉ cho việc cần chất lượng văn viết.
2. **Free quota 32M/ngày** (mới dùng 14K/ngày) → subagent/tra cứu
   **chuyển free được ngay**, không đụng budget tuần.
3. **Subagent đọc lại context mỗi session con** → gộp task, tránh kéo
   100K context vô ích.
4. **Cache-read là chi phí âm thầm** (224M/tuần) → session dài càng đắt →
   **compact / start session mới** định kỳ tiết kiệm hơn cả đổi model.
5. **Gói khuyến nghị: Pro+ ($10/tháng, budget $132/tuần)** — usage thực
   $75–90/tuần khớp 56–83%. Nếu chuyển bulk sang free/cheap, usage giảm
   còn ~$30–50/tuần → dư rất lớn. (Pro $5 bị vượt mỗi tuần; Max $20 thừa.)

## 5. Cách cập nhật lại phân tích này

```powershell
# Lấy usage live (allowance/burst/free tokens)
pwsh scripts\provider\Get-XKiroUsage.ps1
# Đồng bộ catalog mới nhất (nếu có model đổi giá/thêm mới)
pwsh scripts\provider\Update-XKiroModels.ps1 -Publish -Install
```

> Số liệu session/token lấy từ `~\.local\share\opencode\opencode.db`
> (bảng `session`: tokens_input/output/cache_read, model, time_created).
