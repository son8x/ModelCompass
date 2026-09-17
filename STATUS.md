# 📊 STATUS — Trạng thái test từng model

> Duy trì bảng này mỗi lần publish/rollback. Ký hiệu:
> ✅ Đã test OK trên máy thật · 🧪 Đang thử · ❌ Lỗi/gỡ · ⏸️ Test lại khi giá/tier đổi

## Provider hiện có (production snapshot 16/09/2026)

| Provider | Mô hình | Trạng thái | Ghi chú |
|---|---|---|---|
| `1-xkiro-free` | Đủ 24 free model: MiniMax (M2→M3, 8 model), DeepSeek (5), Mistral (8), SenseNova (2), GPT-5.3 Codex Spark | ✅ | từ 16/09 bổ sung đủ catalog free; `sensenova-6.8-flash-lite` & `gpt-5.3-codex-spark` đang 503 tạm |
| `2-xkiro-max` | Claude Sonnet 5 / Opus 5 / Fable 5, GPT-5.6 Sol/Terra/Luna | 🧪 | gói Max ($20/tháng, từ 16/09); Anthropic/OpenAI đang 429 tạm (upstream quá tải) |
| `2-xkiro-max` | Grok 4.6/4.5, GLM-5.3/5.2/5.1/5, Kimi K2.6/2.5, Nemotron 3 Super/Ultra | ✅ | đã ping OK trên gói Max |
| `3-omniroute-free` | GLM-5.2, DeepSeek V4 Pro, Kimi K2.7 Code (Cloudflare) | ✅ | ⭐ mạnh nhất nhóm free |
| `3-omniroute-free` | GPT-OSS 120B, Qwen3 30B, Nemotron 3 (Cloudflare) | ✅ | tốt, dùng fallback |
| `3-omniroute-free` | Qwen3.8 27B / Qwen3.6 27B / GPT-OSS 120B (Groq) | ✅ | ⭐ nhanh nhất, rate-limit |
| `3-omniroute-free` | Gemini 3.1 Flash Lite / 2.5 Flash 8B | 🧪 | free daily, giới hạn theo ngày |
| `4-openrouter-free` | North Mini Code `:free` | ✅ | siêu nhanh, chuyên code |
| `4-openrouter-free` | Ling 3.0 Flash, Nemotron 3 Super, Laguna S `:free` | 🧪 | connection `credits_exhausted` khi gọi paid, `:free` vẫn OK |
| `5-9router` | GPT-OSS 120B, Gemini 3.8 Flash (local) | ⏸️ | phụ thuộc dịch vụ local 20128 |
| `6-teamoRouter` | DeepSeek V4 Flash Free / GLM-5.3 Flash Free | ✅ | miễn phí, dùng cho tác vụ lặp |
| `6-teamoRouter` | GPT-5.4 Mini / GPT-5.6 Luna | ✅ | rẻ nhất nhóm paid, tính năng ổn |
| `6-teamoRouter` | DeepSeek V4 Flash / V4 Pro | ✅ | flash nhanh, pro reasoning |
| `6-teamoRouter` | Claude Haiku 4.5 / Sonnet 5 | ✅ | haiku nhanh, sonnet agent/viết |
| `6-teamoRouter` | GLM-5.3 | 🧪 | cần đo lại giá/ổn định session dài |
| `6-teamoRouter` | GPT-5.6 Terra / Gemini 3.1 Pro | 🧪 | context dài, kiểm tra phụ phí >200K |

## Bị gỡ / không dùng

| Model/Provider | Lý do | Thời gian |
|---|---|---|
| Gemini 2.5 Flash (direct AI Studio) | `404` với user mới → chuyển sang Gemini 3.x | 09/2026 |
| deepinfra / siliconflow / sambanova | router thương mại trả phí, rủi ro nhầm model tính tiền | đã cân nhắc gỡ |

## Lịch sử đáng nhớ

- 17/09/2026 — Điều tra cơ chế sort trong `/model` (source opencode 1.18.29): provider sort theo `name` A→Z; model trong provider sort theo `release_date` GIẢM DẦN rồi `name` A→Z — KHÔNG theo thứ tự khai báo. Áp dụng `release_date` tổng hợp (`2099-…`) để ép thứ tự cho `1-xkiro-free` (độ mạnh ↓) và `2-xkiro-max` (giá ↑). Recipe lưu tại `docs/providers-and-models.md` §6.
- 17/09/2026 — Cập nhật 2 nhóm xKiro (đối chiếu `GET /v1/models` catalog): free bỏ chữ "(Free)", ghi thế mạnh/lĩnh vực từng model (giữ 24 model, thứ tự độ mạnh không đổi). Max: xác minh chính xác giá 23 model (khớp 100%), thêm `nemotron-3-nano` ($0.05/$0.20) & `glm-5.3-flash` ($0.15/$0.50), đánh dấu "· khuyến nghị" cho model mạnh nhất tầm giá, loại `gpt-6-astra`/`claude-fable-5-1` (cần gói ≥ Ultra, 403 trên Max). Tổng paid = 25, sort giá rẻ→mắc. Đã publish + install global.
- 17/09/2026 — Xác minh thang gói xKiro (Free/Pro $5/Pro+ $10/Max $20/Ultra $100/Power $200): model access giống nhau cho mọi gói trả phí (free+paid+premium), chỉ khác allowance/budget — đổi gói trả phí KHÔNG đổi danh sách model; riêng `gpt-6-astra` & `claude-fable-5-1` gate `min_plan_usd=100` (Ultra/Power). Tạo `docs/thesis-review-plan.md` map tác vụ review luận văn → model + kịch bản + ước chi phí.
- 17/09/2026 — Sắp xếp lại `2-xkiro-max` theo NHÓM SỨC MẠNH (rẻ → mạnh: `[B] Nhẹ/rẻ` → `[A] Mạnh đa dụng` → `[S] Flagship`), trong nhóm giá rẻ→mắc; tên model thêm tag `[B]/[A]/[S]` + giá để nhận biết model thay thế được cho nhau. `release_date` đồng bộ `2099-10-25 → 2099-10-01`. Đã publish + install global.
- 16/09/2026 — Khởi tạo ModelCompass, snapshot production từ config đang chạy.

---

> Quy tắc cập nhật: ghi ✅ chỉ khi model đã chạy được ≥1 phiên đầy đủ trên
> opencode (không lỗi, tốc độ/giá như kỳ vọng). Ghi ❌ khi gỡ khỏi config.