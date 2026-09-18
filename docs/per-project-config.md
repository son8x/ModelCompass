# Per-project config (không đụng global)

Cấu hình ModelCompass nằm ở 3 tầng, **deep-merge** (tầng sau ghi đè tầng trước):

| Tầng | File |
|------|------|
| Global (máy) | `~/.config/opencode/opencode.json` — do `Install-Config.ps1` quản lý |
| Project (repo) | `./opencode.json` / `./opencode.jsonc` / `.opencode/opencode.json` — opencode tự dò từ cwd lên worktree root |
| Per-project ghi đè | env `OPENCODE_CONFIG=<path>` — file JSON nạp thêm ở scope cuối |

Khi chỉ muốn **project này dùng model khác** (ví dụ luận văn, pentest, hoặc một
client bảo mật), không nên sửa config global — dùng tầng `OPENCODE_CONFIG`.

## Cách dùng

Template có sẵn trong `configs/project-templates/<code|thesis|pentest>/opencode.json`.

1. Copy template vào project (hoặc tự tạo `opencode.json` với đúng `$schema`).
2. Chạy opencode với biến môi trường:

   ```powershell
   $env:OPENCODE_CONFIG = "$PWD\opencode.json"
   opencode
   ```

   Hoặc dùng `OPENCODE_CONFIG_CONTENT` để inject inline tạm (không cần file):

   ```powershell
   $env:OPENCODE_CONFIG_CONTENT = '{"model":"1-xkiro-free/mistralai/codestral-2508"}'
   opencode
   ```

3. Chạy xong: `Remove-Item Env:OPENCODE_CONFIG` để về cấu hình thường.

## Lưu ý quan trọng

- `OPENCODE_CONFIG` chỉ **ghi đè**, không thay thế — provider/plugin/MCP vẫn kế
  thừa từ global (đã cài ModelCompass). Template chỉ cần khai báo
  `model` (+ tuỳ chọn `instructions`).
- `model` **phải có tiền tố provider**, ví dụ `"6-teamoRouter/claude-sonnet-5"`.
- Config được **nạp một lần lúc khởi động** — đổi template phải thoát và mở
  lại opencode.
- Nếu muốn project này lệch hẳn cấu hình/agent/skill, chỉ việc thêm file vào
  `.opencode/` của project; không cần ghi gì vào config global.

## Cứu hộ khi project config hỏng

- `OPENCODE_DISABLE_PROJECT_CONFIG=1` — bỏ qua project config, chỉ dùng global.
- `OPENCODE_CONFIG=<safe preset>` — chạy với `configs/presets/safe-minimal.jsonc`
  (xem README presets).

Dùng kèm: `docs/thesis-review-plan.md` (map tác vụ → model) nếu viết luận văn.