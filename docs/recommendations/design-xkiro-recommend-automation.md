# 🤖 Thiết kế: Tự động hóa đồng bộ + Đánh giá + Đề xuất model xKiro

> **Trạng thái: BẢN THIẾT KẾ (chưa code).** Tài liệu này là "bàn giao" để bạn và agent
> cùng bàn tiếp rồi mới triển khai. Cập nhật: **17/10/2026**.
>
> **Mục tiêu cuối:** khi xKiro thay đổi danh mục model, hệ thống tự (1) đồng bộ,
> (2) đánh giá model sống/chết, (3) **đề xuất model nên dùng** cho từng nhóm/tác vụ,
> mà không phải làm tay từng bước.
>
> **⚠️ Quyết định đến nay:** phần (1)(2) **đã có sẵn** và chạy được; phần (3) —
> tự gắn `⭐` recommend — **vẫn thủ công**, và đây chính là nút thắt.

---

## 1. Hiện trạng tự động hóa

| Việc | Script / lệnh | Trạng thái |
|---|---|---|
| Lấy catalog live `GET /v1/models` | `Get-ProviderCatalog.ps1` (`mc sync`) | ✅ |
| Probe model sống/chết (OK / 403 / 404 / timeout) | `Test-ModelConnectivity.ps1` (`mc connectivity`) | ✅ |
| **Pipeline tổng** (fetch → probe → thêm/gỡ → chèn nhóm → `release_date` → validate → publish → install) | `Update-XKiroModels.ps1 -Publish -Install` | ✅ |
| Đổi giá trong `name` theo catalog | `Compare-Prices.ps1` (`mc prices`) | ✅ |
| Ép thứ tự hiển thị | `New-SortOrderKey.ps1` (`mc sort-order`) | ✅ |
| Đổi giá + kiểm chứng lại sau khi sync | `Compare-Prices.ps1` | ✅ |
| Validate config | `Test-ModelCompassConfig.ps1` (`mc validate`) | ✅ |
| **Đề xuất / gắn `⭐` theo nhóm & tác vụ** | *(không có)* | ❌ **THỦ CÔNG** |
| **Chạy định kỳ (lịch)** | *(không có)* | ❌ |
| **Cảnh báo khi catalog đổi** | *(không có)* | ❌ |

> **Lưu ý quan trọng về `⭐` và sync:** `Update-PricesInName` (trong `Compare-Prices.ps1`)
> chỉ **thay chuỗi giá** bên trong `name` và giữ nguyên phần còn lại → **`⭐` + nhãn tác vụ
> sống sót qua mỗi lần sync** (đã kiểm chứng code). Model mới do sync sinh thì **không có**
> `⭐` — đó chính là việc cần tự động hóa.

---

## 2. 🔴 Nút thắt: catalog xKiro KHÔNG CÒN metadata khả năng

Đây là phát hiện quan trọng nhất, quyết định hướng thiết kế.

`docs/catalogs/xkiro.json` (124 model, `fetched_at` 16/10/2026) chỉ có:

| Field | Thực tế | Đánh giá |
|---|---|---|
| `id` | `vendor/model-name` | ✅ Duy nhất có giá trị phân tích |
| `access_tier` | `free` 51 · `paid` 62 · `premium` 11 | ✅ Hữu ích (premium = gate Ultra/Power) |
| `context` | số token | ✅ Hữu ích |
| `pricing.input/output` | số USD/1M | ✅ Hữu ích |
| `name` | **rỗng với CẢ 124 model** | ❌ Không dùng được |
| `modality.input/output` | **rỗng với CẢ 124 model** | ❌ Không dùng được |
| `created` | **bằng 1 với CẢ 124 model** | ❌ Phế, không phân biệt được model mới/ cũ |

**Hệ quả:** API **không cho biết** model nào làm tốt việc gì. Các nhãn `vision` / `code` /
`reasoning` / `omni` trong `name` config hiện tại **là do người gán tay** (từ catalog giàu
metadata ngày 21/09 + kiến thức thị trường), **không** phải do script đọc từ API.

→ **Không thể** có "rule đọc từ catalog → ra ⭐". Phải chọn một trong:
- **(a)** rule dựa trên **heuristic tên model** (`coder`, `vl`, `vision`, `omni`, `flash`, `pro`, `translate`) — rẻ nhưng dễ sai;
- **(b)** maintain **bảng tra khả năng tay** (file `model-capabilities.json` trong repo) — chắc chắn nhưng vẫn là việc người;
- **(c)** **benchmark thực nghiệm** — không cần metadata, đo thật rồi chọn — tốn token nhưng客观;
- **(d)** kéo metadata từ nguồn thứ ba (OpenRouter / HuggingFace) — thêm dependency.

> 🔎 **Cần kiểm chứng thêm khi triển khai:** `premium` (11 model) chưa hề xuất hiện trong
> config free/max — cần probe để biết chúng **chặn thật sự** hay chỉ catalog ghi vậy.

---

## 3. Baseline "ground truth": 14 model `⭐` hiện tại (17/10/2026)

Đây là kết quả **người quyết định**. Nó chính là tập dữ liệu giám sát để rút ra quy tắc.

### 3.1 Free (`1-xkiro-free`, 51 model) — 7 ⭐

| Model id | Nhãn trong `name` | Tiêu chí ngầm đã dùng |
|---|---|---|
| `qwen/qwen3.8-max:free` | reasoning (mặc định) | Model **đầu bảng free**, 1M ctx, vision+reasoning |
| `qwen/qwen3-coder-plus:free` | code | id chứa `coder` |
| `qwen/qwen3-vl-plus:free` | vision | id chứa `vl` |
| `qwen/qwen3.8-omni-flash:free` | omni | id chứa `omni` |
| `qwen/qwen3.5-flash:free` | nhanh | id chứa `flash` |
| `mistralai/mistral-large-4-0` | soạn bài/PPTX | **Chỉ định của người dùng**; input free, 524K, model `Large` |
| `cohere/command-a-translate` | dịch | id chứa `translate` |

### 3.2 Paid (`2-xkiro-max`, 62 model) — 7 ⭐

| Model id | Nhóm | Nhãn | Tiêu chí ngầm đã dùng |
|---|---|---|---|
| `z-ai/glm-5.3-flash` | `[L]` | subagent | input $0.15 (< ngưỡng L $0.5), vision, rẻ |
| `z-ai/glm-5.2` | `[B]` | bulk | 1M ctx, input $0.25 = **rẻ nhất nhóm B** |
| `google/gemini-3.1-pro` | `[A]` | nghiên cứu | 1M ctx, mạnh cho research (benchmark cộng đồng) |
| `anthropic/claude-sonnet-5` | `[A]` | viết/agent | Văn phong tiếng Việt (cộng đồng #1), $2/$10 |
| `x-ai/grok-4.7` | `[A]` | code | 500K, thiên code |
| `google/gemini-3.8-flash` | `[A]` | vision | 1M, input $0.75, catalog ghi premium nhưng probe **OK trên Max** (`✓Max`) |
| `openai/gpt-6.1-sol` | `[S]` | flagship | Flagship **nhưng input chỉ $2** (như Sonnet) — tối ưu cho workload nặng input |

### 3.3 Tiêu chí ngầm rút ra (để chuyển thành rule)

1. **Nhóm max** đã tự quyết theo **giá input** — `Update-XKiroModels.ps1` đang dùng
   `L<$0.5 · B<$1.5 · A<$4 · còn lại S` (đổi được qua `-LThreshold/-BThreshold/-AThreshold`).
2. **⭐ trong nhóm = "ngon nhất trong tầm giá"**, dựa trên: context lớn (ưu tiên 1M),
   **giá input thấp** (vì ~85% chi phí của bạn đến từ input/cache-read),
   benchmark/thương hiệu cộng đồng.
3. **⭐ free** gần như **heuristic theo tên model** + "model đầu bảng = mặc định".
4. **Ngoại lệ duy nhất mang tính chủ quan:** `mistral-large-4-0` cho *soạn bài/PPTX*
   (bạn chỉ định) và `gpt-6.1-sol` làm flagship vì *giá input rẻ hơn Opus* —
   hai case này **không suy ra được từ dữ liệu**.

---

## 4. Ba hướng thiết kế

| Tiêu chí | **A. Rule-based** | **B. Benchmark-driven** | **C. Hybrid (khuyến nghị)** |
|---|---|---|---|
| Nguyên lý | Chốt tiêu chí → script áp đúng | Chạy benchmark định kỳ → model thắng được ⭐ | Rule xử lý phần chắc (heuristic tên, giá, ctx, nhóm) + benchmark cho phần tranh lệch |
| Nguồn dữ liệu | tên id, giá, ctx, tier | đo thật (quality/latency) | kết hợp + bảng tra tay nhỏ |
| Tự động tới đâu | 100% | 100% (nhưng chậm/tốn) | 90%, người chỉ chốt ngoại lệ |
| Chi phí | $0 (chỉ API catalog + probe) | token benchmark × ~113 model × số lượt | trung bình |
| Độ chính xác | trung bình-cao (free), cao (max theo giá) | cao nhưng dao động (model mới/bị overload) | cao nhất |
| Rủi ro | rule sai khi model đổi tên / ra biến thể mới | benchmark 1 lần không đại diện; tốn allowance | cần bảo trì bảng tra |
| Khuyến nghị | làm **bước 1** | chỉ khi bạn muốn chọn "mạnh nhất thật sự" | **nên đi đường này** |

### 4.1 Cấu trúc code đề xuất (đường Hybrid)

```
scripts/recommend/
  Get-ModelCandidates.ps1   # lọc catalog theo tier/ctx/price → danh sách ứng viên/nhóm
  Resolve-StarRules.ps1     # áp rule (heuristic tên + bảng tra) → gán ⭐ theo nhóm & tác vụ
  New-RecommendReport.ps1   # sinh bảng đề xuất + diff so với ⭐ hiện tại → CHỈ BÁO CÁO
scripts/recommend/model-capabilities.json   # bảng tra khả năng do người maintain
```

- Kết nối vào pipeline: chạy **sau** `Update-XKiroModels.ps1`, **trước** publish.
- Thêm 1 lệnh CLI: `mc recommend` (đặt vào `$script:CommandMap` trong
  `modules/ModelCompass/ModelCompass.psm1`).
- **Mặc định KHÔNG ghi đè `name`** — chỉ in bảng diff; phải thêm cờ `-Apply` mới ghi
  (tránh mất nhãn tay, tránh surprise).

### 4.2 Quy tắc rule khởi điểm (mời bạn sửa trước khi code)

```
FREE
  reasoning/mặc định : model CÓ release_date lớn nhất trong free (đầu bảng)
  code                : id match  coder|codex|devstral|code
  vision              : id match  -vl|vision|-v\d|multimodal
  omni                : id match  omni
  nhanh               : id match  flash|lite|mini|small   (ưu tiên ctx > 100K)
  dịch                : id match  translate
  soạn bài/PPTX       : id match  large (ưu tiên input free, ctx > 250K)

MAX  (nhóm đã chốt theo giá input)
  mỗi nhóm [L]/[B]/[A]/[S]: model input-price THẤP NHẤT nhóm, tie-break ctx lớn nhất
  nghiên cứu           : model 1M ctx + nhóm [A]/[S]
  viết/văn phong       : claude-sonnet-*  (nếu có trong config)
  code                 : id match grok|coder|gpt-5.6-terra|glm-5.3
  vision               : id match gemini|glm-.*v|vl
  subagent/nhẹ         : model nhóm [L] input < $0.2
  flagship             : model nhóm [S] input-price thấp nhất (ưu tiên chi phí)
```

> ⚠️ Hai chỗ rule **bắt buộc** phải nới cho người quyết: (1) *soạn bài/PPTX → mistral-large-4-0*;
> (2) *flagship → input rẻ thay vì mạnh nhất*. Nên đặt trong bảng tra, không hardcode rule.

---

## 5. Câu hỏi cần chốt trước khi code

- [ ] **Đi đường A (rule), B (benchmark) hay C (hybrid)?** — xem mục 4.
- [ ] **Rule dùng heuristic tên hay bảng tra tay?** Nếu bảng tra: ai maintain, format thế nào?
- [ ] **Số lượng ⭐ mỗi nhóm?** Hiện free 7 / max 7 — giữ, tăng (mỗi tác vụ 1 model), hay giảm (1/nhóm)?
- [ ] **Có benchmark không?** Nếu có: metric nào (đúng/SWE-bench proxy, latency, tiếng Việt), bao nhiêu model, ngân sách token?
- [ ] **Chạy tay hay có lịch?** (Task Scheduler hằng tuần / chạy tay khi cần / GitHub Actions)
- [ ] **`-Apply` hay chỉ báo cáo?** Đề xuất: mặc định báo cáo, `-Apply` mới ghi.
- [ ] **Xử lý model `premium` (11 model)?** Cần probe xác nhận chúng có thật sự dùng được không.
- [ ] **Khi ⭐ đổi thì docs có tự cập nhật không?** (bảng §2 `docs/model-reference.md`
      + preset `docs/recommendations/lecturer-workload.md` đang tay)

---

## 6. Rủi ro & ràng buộc

1. **Probe tốn thời gian/token.** `Update-XKiroModels.ps1` đã probe ~113 model; benchmark thêm 1 lần × N model sẽ **trừ vào allowance tuần** (đo được ~$75/tuần). Benchmark nên chạy **rất thưa** (vd 1 tháng/lần) hoặc chỉ trên danh sách rút gọn.
2. **Model "đúng lúc" bị overload.** `429/500` là thoáng qua (xKiro là reseller) — **không được** tự gỡ model chỉ vì 1 lần probe lỗi. Chỉ gỡ khi `404`/biến mất khỏi catalog.
3. **`⭐` × badge.** Config đang dùng `⭐` (recommend), `⚠️` (lỗi tạm), `✓Max` (dùng được trên Max dù catalog ghi premium). Đã bỏ `🆕` để tránh chồng badge. Khi tự động phải **giữ quy ước này**, không ghi đè lên nhau.
4. **Fuzzy search.** Đánh số/emoji đầu `name` làm nhiễu tìm kiếm trong `/model` — giữ ⭐ ngắn, không thêm chữ số thứ tự.
5. **Config chỉ nạp lúc khởi động.** Sau khi auto-apply phải **restart opencode** mới thấy — script nên nhắc.
6. **Không có ngày hết hạn gói trong API** (đã dò toàn bộ → 404) — automation **không dự đoán được** ngày gói hết hạn để nhắc người dùng.

---

## 7. Gợi ý bước tiếp theo cho agent

1. Đọc tài liệu này + `docs/model-reference.md` §2 (bảng ⭐) + `scripts/provider/Update-XKiroModels.ps1`.
2. Hỏi người dùng các mục **§5** — đặc biệt mục đầu (đường A/B/C).
3. **Không code vội**: chạy `Update-XKiroModels.ps1 -NoWrite` để xem pipeline hiện xử lý gì,
   rồi mới thiết kế file `scripts/recommend/*`.
4. Khi code: thêm test Pester vào `tests/` (xem `tests/SortOrder.Tests.ps1` làm mẫu),
   dùng `dot-source -SkipRun` để test hàm thuần không gọi mạng.
5. Sau khi auto-apply ⭐: chạy `mc validate` → `mc publish` → `mc install` → nhắc restart.

---

## 8. Trạng thái triển khai (đã xong)

- **Pha 1 — Báo cáo:** `scripts/recommend/New-RecommendReport.ps1` (mặc định chỉ in; `-Report` ghi `reports/`).
  Tầng 1 `Get-ModelCandidates.ps1` + tầng 2 `Resolve-StarRules.ps1` + bảng tra `model-capabilities.json`.
- **Pha 2 — Ghi ⭐ (`-Apply`):** gắn/gỡ ⭐ đầu `name`, backup `configs/development/.backup/`, validate.
- **Pha 3 — Đồng bộ docs:** `scripts/recommend/Update-RecommendDocs.ps1` ghi ĐÈ vùng giữa marker
  `<!-- BEGIN:recommend-stars --> … <!-- END:recommend-stars -->` trong `docs/model-reference.md` §2;
  `-Check` cho CI (exit 1 nếu tài liệu lệch đề xuất).
- **Nối pipeline:** `Update-XKiroModels.ps1 -Recommend` chạy Pha 2 rồi Pha 3 sau validate, TRƯỚC `-Publish`.
- **CI:** `validate.yml` thêm bước `Update-RecommendDocs.ps1 -Check` (chống drift tài liệu).
- **`mc`:** `mc recommend` (Pha 1/2) · `mc recommend-docs` (Pha 3; `-Check`).
- **Test:** `tests/Recommend.Tests.ps1` (56) + `tests/RecommendDocs.Tests.ps1` (11, gồm drift guard).

---

*Cập nhật: 17/10/2026. Liên quan: `docs/model-reference.md` §2,
`docs/recommendations/lecturer-workload.md`, `scripts/provider/Update-XKiroModels.ps1`,
`scripts/provider/Compare-Prices.ps1`, `modules/ModelCompass/ModelCompass.psm1`.*
