# 📊 STATUS — Trạng thái test từng model
<!-- START auto-status (Test-ModelConnectivity.ps1 -UpdateStatus) — KHÔNG sửa tay, script sẽ ghi đè -->
### Trạng thái gần nhất — 2026-09-19 09:32:58

> NOTFOUND 1

| Provider | Model | Status | Phản hồi |
|---|---|---|---|
| 1-xkiro-free | deepseek/deepseek-v4-pro | **NOTFOUND** | HTTP 404 - model không tồn tại trên endpoint này |

<!-- END auto-status -->

> Duy trì bảng này mỗi lần publish/rollback. Ký hiệu:
> ✅ Đã test OK trên máy thật · 🧪 Đang thử · ❌ Lỗi/gỡ · ⏸️ Test lại khi giá/tier đổi

## Provider hiện có (production snapshot 16/09/2026)

| Provider | Mô hình | Trạng thái | Ghi chú |
|---|---|---|---|
| `1-xkiro-free` | Đủ **42 model free** (catalog 25/09): Qwen (19), MiniMax (8), Mistral (8), SenseNova (2), DeepSeek (5) | ✅ | cập nhật 25/09; **xKiro đưa lại 5 DeepSeek vào free** (`v4-pro`, `v4-flash`, `v4.1-flash`, `v3.2`, `chat-v3.1` — probe 200 OK); `minimax-m3`/`m2.7`/`m2.5-highspeed` đang 500 tạm |
| `2-xkiro-max` | Claude Sonnet 5 / Opus 4.6–5 / Fable 5, GPT-5.6 Terra/Luna/Sol, GPT-5.4/Mini, Gemini 2.5–3.8, GLM-4.5→5.3, Nemotron 3 Super/Ultra | ✅ | **46 model** (probe 21/09); 4 nhóm `[L]→[B]→[A]→[S]`; ghi đủ giá `In/Out` USD/1M từ catalog 21/09; ⚠️ `gpt-5.5`, `gpt-5.6-sol`, `nemotron-3-nano`, `llama-49b` lỗi tạm |
| `2-xkiro-max` | ~~Kimi K2.5/2.6/2.7/K3, Grok 4.5/4.6/Build, DeepSeek V4-*, Qwen-premium, MiniMax-premium, Tencent, Xiaomi, GPT-6-Astra, Fable 5-1~~ | ❌ | **403 — gỡ 21/09**: tính theo wallet (pay-as-you-go) hoặc cần gói ≥ Ultra/Power, gói Max không phủ |
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

- 17/09/2026 — Probe thực tế overload ở xKiro Max: `gpt-5.6-terra`/`gpt-5.6-luna` `500`, `kimi-k2.5` `429` (temporarily at capacity) — mẫu chung là model "đáng tiền" nhất trong tầm giá hay bị ép, không giới hạn ở nhóm A. `GET /v1/models` không có field availability → không lọc trước được, phải retry + fallback. Thêm bảng **"Ứng cứu khi bị overload (fallback theo tầng)"** vào `docs/providers-and-models.md` (A→A cùng tầng / B rẻ / S nâng cấp) + cập nhật README + sửa đường dẫn plugin cũ.
- 21/09/2026 — Rà lại toàn bộ catalog free `GET /v1/models` trên tài khoản: xKiro đã **gỡ toàn bộ nhóm DeepSeek và GPT-5.3 Codex Spark khỏi tier free** (`deepseek-v4-pro` → `404 model does not exist`), nhóm mới **chỉ còn 37 model**: Qwen (19), MiniMax (8), Mistral (8), SenseNova (2). Cập nhật `1-xkiro-free` lên 37 model (Qwen3.8 Max đứng đầu), đổi model mặc định → `1-xkiro-free/qwen/qwen3.8-max:free`, ghi chú model đang lỗi phía xKiro: `minimax-m3:free`, `minimax-m2.7:free`, `minimax-m2.5-highspeed:free` (`500`). Đã validate + publish production + install global.
- 25/09/2026 — **xKiro đưa 5 model DeepSeek trở lại tier free** (`deepseek/deepseek-v4-pro`, `deepseek-v4-flash`, `deepseek-v4.1-flash:free`, `deepseek-v3.2`, `deepseek-chat-v3.1` — probe chat/completions 200 OK, giá 0). Thêm vào `1-xkiro-free` (37 → **42 model**), đặt sau Qwen3.8 Max theo độ mạnh (V4 Pro code agent). Re-gen catalog, Compare-Prices khớp 42/42 (vắng: 0). Validate + publish + install global.
- 21/09/2026 — **Phát hiện đổi cơ chế ở xKiro Max**: 27 model premium (Kimi K2.5/2.6/2.7/K3, Grok 4.5/4.6/Build, DeepSeek V4-pro/flash/4.1, Qwen3.5+→3.8-max, MiniMax m2.5/m2.7/m3, Tencent hy3/hy4, Xiaomi mimo2.5/pro, Longcat, Muse-Spark, `gpt-6-astra`, `claude-fable-5-1`) trả `403 "billed from wallet"` — gói Max không còn phủ premium, chỉ phủ model `paid`. Probe thực tế 46 model dùng được (200 OK + 4 lỗi tạm). Cập nhật `2-xkiro-max`: gỡ 27 model 403, thêm Gemini 2.5→3.8 + GLM-4.5→4.7 + Opus 4.6/4.7, chia **4 nhóm sức mạnh `[L]→[B]→[A]→[S]`** (46 model, `release_date` `2099-10-25`→`2099-09-10`), sửa bảng fallback + STATUS + docs. Đã validate + publish production + install global.
- 21/09/2026 — **Bổ sung giá đầy đủ cho 46 model `2-xkiro-max`** từ catalog live (`GET /v1/models` trả `unit=per_1m_tokens`): trước đó nhiều model không ghi giá còn vài model ghi sai (vd Haiku 4.5 = $1/$5, Sonnet 5 = $2/$10, Fable 5 = $10/$50, Gemini có hệ số premium). Re-gen `docs/catalogs/xkiro.json`, sửa `Compare-Prices.ps1` (parse thêm format `$X/$Y`, khôi phục `ConfigMode` bị dot-source ghi đè), khớp 46/46 với catalog. Đã validate + publish + install global.
- 17/09/2026 — Điều tra cơ chế sort trong `/model` (source opencode 1.18.29): provider sort theo `name` A→Z; model trong provider sort theo `release_date` GIẢM DẦN rồi `name` A→Z — KHÔNG theo thứ tự khai báo. Áp dụng `release_date` tổng hợp (`2099-…`) để ép thứ tự cho `1-xkiro-free` (độ mạnh ↓) và `2-xkiro-max` (giá ↑). Recipe lưu tại `docs/providers-and-models.md` §6.
- 17/09/2026 — Cập nhật 2 nhóm xKiro (đối chiếu `GET /v1/models` catalog): free bỏ chữ "(Free)", ghi thế mạnh/lĩnh vực từng model (giữ 24 model, thứ tự độ mạnh không đổi). Max: xác minh chính xác giá 23 model (khớp 100%), thêm `nemotron-3-nano` ($0.05/$0.20) & `glm-5.3-flash` ($0.15/$0.50), đánh dấu "· khuyến nghị" cho model mạnh nhất tầm giá, loại `gpt-6-astra`/`claude-fable-5-1` (cần gói ≥ Ultra, 403 trên Max). Tổng paid = 25, sort giá rẻ→mắc. Đã publish + install global.
- 17/09/2026 — Xác minh thang gói xKiro (Free/Pro $5/Pro+ $10/Max $20/Ultra $100/Power $200): model access giống nhau cho mọi gói trả phí (free+paid+premium), chỉ khác allowance/budget — đổi gói trả phí KHÔNG đổi danh sách model; riêng `gpt-6-astra` & `claude-fable-5-1` gate `min_plan_usd=100` (Ultra/Power). Tạo `docs/thesis-review-plan.md` map tác vụ review luận văn → model + kịch bản + ước chi phí.
- 17/09/2026 — Sắp xếp lại `2-xkiro-max` theo NHÓM SỨC MẠNH (rẻ → mạnh: `[B] Nhẹ/rẻ` → `[A] Mạnh đa dụng` → `[S] Flagship`), trong nhóm giá rẻ→mắc; tên model thêm tag `[B]/[A]/[S]` + giá để nhận biết model thay thế được cho nhau. `release_date` đồng bộ `2099-10-25 → 2099-10-01`. Đã publish + install global.
- 16/09/2026 — Khởi tạo ModelCompass, snapshot production từ config đang chạy.

---

> Quy tắc cập nhật: ghi ✅ chỉ khi model đã chạy được ≥1 phiên đầy đủ trên
> opencode (không lỗi, tốc độ/giá như kỳ vọng). Ghi ❌ khi gỡ khỏi config.
