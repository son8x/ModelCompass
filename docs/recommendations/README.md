# 📚 Đề xuất model theo nhu cầu

Chọn đúng "provider/model-id" để dán vào `configs/development/opencode.jsonc`
rồi publish. Mỗi trang gồm: **top pick**, **dự phòng**, **giá (nếu trả phí)**,
và **cách cấu hình nhanh**.

| Hồ sơ | Trang |
|---|---|
| Lập trình viên (code hàng ngày, fix lỗi, refactor, tìm hiểu repo) | [programming.md](programming.md) |
| Sinh viên/Viết luận văn (văn phong hàn lâm tiếng Việt, trích dẫn IEEE) | [thesis-writing.md](thesis-writing.md) |
| Pentest / CTF / bảo mật (phân tích khai thác, đọc mã) | [pentest.md](pentest.md) |

## Công thức chọn model chung

1. **Ngân sách $0** → nhóm free: `3-omniroute-free`, `4-openrouter-free`, `1-xkiro-free`.
2. **$0–5/tháng** → `6-teamoRouter` DeepSeek V4 Flash/Pro, GPT-5.6 Luna.
3. **$10–30/tháng** → Claude Sonnet 5 / Gemini 3.1 Pro (theo tác vụ nặng/ngữ cảnh dài).
4. **Tốc độ trên hết** → Groq (free) hoặc Gemini 3.x Flash Lite (paid rẻ).

> Preset tương ứng nằm trong `configs/presets/*.jsonc`. Sau khi quyết định:
> `Test-ModelConnectivity` → `Publish-Config` → `Install-Config`.