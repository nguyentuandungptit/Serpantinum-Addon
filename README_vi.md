# Hệ Thống Addon Mô-đun Serpantinum

[![Serpantinum](https://img.shields.io/badge/Serpantinum-v2-blue?style=flat-square)](https://github.com/ilyamiro/serpantinum)
[![Addon Architecture](https://img.shields.io/badge/Architecture-Modular-green?style=flat-square)](#️-hướng-dẫn-dành-cho-nhà-phát-triển-tạo-addon-mới)
[![License](https://img.shields.io/badge/License-GPLv3-orange?style=flat-square)](LICENSE)

*Đọc tài liệu này bằng [English](README.md) hoặc [Tiếng Việt](README_vi.md).*

---

## Mục Lục

- [🌟 Giới Thiệu](#-giới-thiệu)
- [🚀 Hướng Dẫn Sử Dụng](#-hướng-dẫn-sử-dụng)
  - [Trình Quản Lý Addon Tương Tác](#trình-quản-lý-addon-tương-tác)
  - [Các Lệnh CLI](#các-lệnh-cli)
- [🛠️ Hướng Dẫn Dành Cho Nhà Phát Triển (Tạo Addon Mới)](#️-hướng-dẫn-dành-cho-nhà-phát-triển-tạo-addon-mới)
  - [Cấu Trúc Thư Mục](#cấu-trúc-thư-mục)
  - [Quy Chuẩn Manifest (`addon.json`)](#quy-chuẩn-manifest-addonjson)
  - [Quy Ước Cho `install.sh`](#quy-ước-cho-installsh)
  - [Quy Ước Cho `uninstall.sh`](#quy-ước-cho-uninstallsh)
  - [Tích Hợp Với Matugen & Pipeline Giao Diện](#tích-hợp-với-matugen--pipeline-giao-diện)
- [🧩 Các Addon Hiện Có](#-các-addon-hiện-có)
  - [Discord Mod (`discord/`)](#discord-mod-discord)

---

## 🌟 Giới Thiệu

**Serpantinum** là một giao diện shell hiện đại, siêu mượt dành cho các Wayland compositor trên Linux (Hyprland, Niri, Sway, Mango) với hệ thống đổi màu động **Material You** thông qua `matugen`.

**Hệ Thống Addon Mô-đun (Modular Addon System)** tách biệt hoàn toàn việc tùy biến các ứng dụng bên thứ ba (như Discord Vencord, Spotify Spicetify, Steam, Trình duyệt web...) ra khỏi mã nguồn gốc của dotfile:
- **Không Gây Phình Dotfile Gốc:** Toàn bộ cấu hình gốc của Serpantinum (`config.toml`, `config-static.toml`) và các tập lệnh mặc định hoàn toàn sạch sẽ, không chứa bất kỳ cấu hình rác nào của bên thứ ba.
- **Tự Động Phát Hiện (Dynamic Auto-Discovery):** Mỗi addon được đóng gói biệt lập trong thư mục riêng (`<id>/`). Trình quản lý trung tâm tự động quét, đọc thông tin và hiển thị menu từ manifest `addon.json`.
- **Đảm Bảo Tính Bất Biến & Gỡ Cài Đặt Sạch Sẽ:** Mọi addon đều tuân thủ hợp đồng giao tiếp chuẩn, cho phép cài đặt lặp lại nhiều lần (idempotent) và gỡ cài đặt triệt để, trả lại trạng thái nguyên bản cho hệ thống.

---

## 🚀 Hướng Dẫn Sử Dụng

### Trình Quản Lý Addon Tương Tác

Để mở menu giao diện tương tác trên Terminal (TUI), bạn chỉ cần chạy lệnh:

```bash
./install.sh
```

Giao diện sẽ hiển thị:
1. Danh sách toàn bộ các addon hiện có và trạng thái hiện tại (`[INSTALLED]` hoặc `[NOT INSTALLED]`).
2. Nhập số thứ tự để cài đặt hoặc gỡ cài đặt nhanh chóng chỉ với 1 thao tác.
3. Tự động kiểm tra các gói phụ thuộc trước khi tiến hành cài đặt.

### Các Lệnh CLI

Bạn có thể chạy trực tiếp các lệnh CLI để tích hợp vào các script tự động hóa:

#### 1. Liệt kê danh sách Addon
Xem toàn bộ addon đã được phát hiện, phiên bản, mô tả và trạng thái cài đặt:
```bash
./install.sh list
```

#### 2. Kiểm tra trạng thái cài đặt
Kiểm tra xem một addon đã được cài hay chưa. Lệnh trả về exit code `0` nếu đã cài đặt, và `1` nếu chưa cài đặt (rất tiện cho bash script):
```bash
./install.sh status <addon_id>
# Ví dụ:
./install.sh status discord
```

#### 3. Xem thông tin chi tiết
Hiển thị metadata đầy đủ: tên, tác giả, phiên bản, phụ thuộc, trang chủ và mô tả chi tiết:
```bash
./install.sh info <addon_id>
# Ví dụ:
./install.sh info discord
```

#### 4. Cài đặt một Addon
Cài đặt addon chỉ định. Tất cả các tham số bổ sung sẽ được chuyển tiếp trực tiếp vào `install.sh` của addon đó:
```bash
./install.sh install <addon_id> [TÙY CHỌN...]

# Ví dụ:
./install.sh install discord
./install.sh install discord --force --non-interactive
```

#### 5. Gỡ cài đặt Addon
Gỡ bỏ hoàn toàn addon và phục hồi các file cấu hình về trạng thái sạch ban đầu:
```bash
./install.sh uninstall <addon_id> [TÙY CHỌN...]

# Ví dụ:
./install.sh uninstall discord
./install.sh uninstall discord --non-interactive
```

#### 6. Kiểm tra phần mềm phụ thuộc
Kiểm tra xem hệ thống của bạn đã cài đặt các công cụ cần thiết cho addon hay chưa:
```bash
./install.sh check-deps <addon_id>
# Ví dụ:
./install.sh check-deps discord
```

#### Tùy chọn chung:
- `--target-dir <DIR>`: Chỉ định thư mục gốc Serpantinum mục tiêu (mặc định là thư mục repo hiện tại hoặc `~/.local/share/serpantinum`).

---

## 🛠️ Hướng Dẫn Dành Cho Nhà Phát Triển (Tạo Addon Mới)

Việc tạo một addon mới rất trực quan và theo chuẩn mô-đun. Bạn có thể dễ dàng tạo thêm addon cho **Spotify** (`spicetify`), **Steam**, **Firefox/Zen Browser**, hoặc bất kỳ ứng dụng nào theo hướng dẫn sau:

### Cấu Trúc Thư Mục

Tạo thư mục mới tại `<addon_id>/`:

```
<addon_id>/
├── addon.json                  # File manifest mô tả thông tin (Bắt buộc)
├── install.sh                  # Script cài đặt (Bắt buộc, chmod +x)
├── uninstall.sh                # Script gỡ cài đặt (Bắt buộc, chmod +x)
├── templates/                  # Template Matugen cần triển khai (Tùy chọn)
│   └── <addon_id>-theme.css.template
├── scripts/                    # Script tiện ích / đồng bộ runtime (Tùy chọn)
│   └── <addon_id>_sync.sh
└── assets/                     # Tài nguyên bổ sung, icon, patch (Tùy chọn)
```

### Quy Chuẩn Manifest (`addon.json`)

Tệp `addon.json` cung cấp thông tin metadata cho trình quản lý addon trung tâm:

```json
{
  "id": "spotify",
  "name": "Spotify Spicetify Mod",
  "version": "1.0.0",
  "description": "Adaptive Material You styling for Spotify using Spicetify-cli.",
  "author": "YourName",
  "dependencies": ["spotify|spotify-launcher", "spicetify"],
  "homepage": "https://spicetify.app",
  "installed_check": "[ -f \"$SERPANTINUM_DIR/src/scripts/spotify_sync.sh\" ]"
}
```

#### Ý Nghĩa Các Trường:
| Trường | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `id` | `string` | **Có** | Định danh duy nhất, trùng tên thư mục (`[a-z0-9_-]+`). |
| `name` | `string` | **Có** | Tên hiển thị thân thiện trên giao diện quản lý. |
| `version` | `string` | **Có** | Chuỗi phiên bản theo chuẩn Semantic Versioning (ví dụ: `1.0.0`). |
| `description` | `string` | **Có** | Mô tả tóm tắt tính năng của addon. |
| `author` | `string` | Không | Tên hoặc nickname của tác giả/người bảo trì. |
| `dependencies` | `array` | Không | Danh sách các lệnh/phần mềm cần thiết. Dùng ký tự `|` cho các lựa chọn thay thế. |
| `homepage` | `string` | Không | Trang chủ hoặc kho mã nguồn dự án. |
| `installed_check` | `string` | Không | Lệnh bash kiểm tra trạng thái cài đặt. Trả về `0` nếu đã cài đặt, khác `0` nếu chưa. |

### Quy Ước Cho `install.sh`

Tệp `install.sh` phải được cấp quyền thực thi (`chmod +x install.sh`) và hỗ trợ các cờ lệnh tiêu chuẩn:

| Cờ lệnh | Mục đích |
|---|---|
| `--target-dir <DIR>` | Thư mục Serpantinum mục tiêu sẽ cài đặt file vào. |
| `--non-interactive` | Chạy tự động không chờ người dùng bấm phím. |
| `--check-deps` | Chỉ kiểm tra phần mềm phụ thuộc, thoát với mã `0` (thành công) hoặc `1` (thiếu). |
| `--force` | Bắt buộc tiếp tục cài đặt kể cả khi thiếu một số phần mềm. |
| `--skip-deps` | Bỏ qua bước kiểm tra phụ thuộc. |
| `-h`, `--help` | Hiển thị thông tin hướng dẫn sử dụng. |

#### Nhiệm vụ của `install.sh`:
1. **Kiểm tra phụ thuộc:** Xác thực các ứng dụng cần thiết trước khi bắt đầu.
2. **Triển khai tệp:** Sao chép template vào `<TARGET_DIR>/src/assets/matugen/templates/` và script vào `<TARGET_DIR>/src/scripts/`.
3. **Thêm cấu hình Matugen:** Bổ sung khối `[templates.<addon_id>]` vào `<TARGET_DIR>/src/assets/matugen/config.toml` và `config-static.toml` (**phải đảm bảo không bị nhân bản nếu chạy lại nhiều lần**).
4. **Cấu hình ứng dụng đích:** Tự động kích hoạt theme trong file thiết lập của ứng dụng (ví dụ: `~/.config/Vencord/settings/settings.json`).
5. **Vá shell khi cần:** Nếu addon phụ thuộc vào một lỗi đã được sửa trong shell, hãy kèm một patcher nhỏ bám vào mã nguồn gốc, chạy lặp lại an toàn, giữ bản sao lưu `.pre-<addon_id>` và khôi phục khi gỡ cài đặt.

### Quy Ước Cho `uninstall.sh`

Tệp `uninstall.sh` phải có quyền thực thi (`chmod +x uninstall.sh`) và hỗ trợ:

| Cờ lệnh | Mục đích |
|---|---|
| `--target-dir <DIR>` | Thư mục Serpantinum cần dọn dẹp các tệp addon. |
| `--non-interactive` | Chạy tự động không hỏi xác nhận. |
| `-h`, `--help` | Hiển thị trợ giúp. |

#### Nhiệm vụ của `uninstall.sh`:
1. **Xóa tệp addon:** Xóa template và script đã cài trong `<TARGET_DIR>`.
2. **Khôi phục cấu hình Matugen:** Tách bỏ sạch sẽ khối `[templates.<addon_id>]` khỏi `config.toml` và `config-static.toml` mà không làm thay đổi các phần cấu hình khác.
3. **Khôi phục ứng dụng:** Tắt theme trong ứng dụng đích (hoặc chạy lệnh khôi phục nguyên bản).
4. **Khôi phục tệp shell đã vá:** Trả lại bản sao lưu `.pre-<addon_id>` do installer tạo ra.
5. **Tính lũy biến:** Phải chạy trơn tru với mã thoát `0` ngay cả khi các tệp đã bị xóa từ trước.

### Tích Hợp Với Matugen & Pipeline Giao Diện

Khi người dùng thay đổi hình nền hoặc chế độ màu, Serpantinum sẽ kích hoạt `matugen`:

1. **Template Matugen:** Đặt template của bạn tại `<id>/templates/<id>-theme.css.template`. Sử dụng các biến màu Material You:
   ```css
   :root {
     --surface: {{colors.surface.default.hex}};
     --primary: {{colors.primary.default.hex}};
     --on-primary: {{colors.on_primary.default.hex}};
     --outline: {{colors.outline.default.hex}};
   }
   ```
2. **Khai báo trong Matugen TOML:**
   ```toml
   [templates.<addon_id>]
   input_path = "templates/<addon_id>-theme.css.template"
   output_path = "~/.config/<app>/themes/serpantinum.theme.css"
   ```
3. **Hook đồng bộ thời gian thực:** Nếu ứng dụng cần tín hiệu reload sau khi sinh file CSS mới, bạn hãy viết logic đó trong `src/scripts/<addon_id>_sync.sh` và kích hoạt qua event pipeline.

---

## 🧩 Các Addon Hiện Có

### Discord Mod (`discord/`)

Tùy biến giao diện **Discord** và **Vesktop** theo phong cách Material You thông qua **Vencord**.

#### Điểm Nổi Bật:
- 🎨 **Đồng bộ màu sắc tức thì:** Tự động tạo theme CSS mới mỗi khi hình nền thay đổi bằng Matugen.
- 🏝️ **Kiến trúc Floating Island & Kính Mờ (Liquid Glass):** Hiệu ứng nền mờ trong suốt (`backdrop-filter: blur(16px)`), phân tầng độ sâu giao diện tinh tế.
- 📐 **Viền sắc nét 2px:** Bo viền 2px nhất quán xung quanh danh sách kênh, danh sách thành viên và khung chat.
- 👤 **Sửa lỗi đệm Avatar (Avatar Padding Fix):** Khắc phục triệt để hiện tượng tràn lề hoặc lệch khung hiển thị trạng thái avatar của người dùng.
- ⚡ **Tiện lợi tối đa:** Tự động nhận diện Discord native, Vesktop, Flatpak Discord và Vencord độc lập.

```bash
# Cài đặt Discord Addon
./install.sh install discord

# Gỡ bỏ Discord Addon
./install.sh uninstall discord
```

#### Bản Vá Shell (bắt buộc để đồng bộ màu và blur)

Blur và bố cục do `scripts/discord_sync.sh` thay token, nhưng màu chỉ đến từ
file CSS mà matugen render. Bốn lỗi trong shell phá vỡ pipeline đó:

- `matugenBaseDir` ghép thêm một `/src` nữa (`SERPANTINUM_DIR` vốn đã kết thúc
  bằng `/src`), nên matugen nhận đường dẫn config không tồn tại và thoát ngay.
  Code cũ bỏ qua stderr nên không ai thấy lỗi.
- `toMd3()` không sinh `outline_variant`, nên palette tĩnh chết với
  `ResolveError at discord:NN:NN`.
- `syncDiscord()` tin vào `ThemeBackend.blurBackground`, mà giá trị này bị ép
  về `false` trong cửa sổ settings standalone. Chọn màu ở đó sẽ ghi lại theme
  Discord với `--serp-backdrop-blur: none` dù blur đang bật.
- `Config` bỏ qua thay đổi `settings.json` đến trong lúc đang ghi, và ghi đè
  file khi thoát, nên cửa sổ settings và shell có thể làm sống lại giá trị cũ
  như `blurBackground: false`.

`scripts/patch_matugen.py` vá tất cả trong
`<TARGET_DIR>/src/quickshell/singletons/` (`theme/Matugen.qml`,
`theme/ThemeBackend.qml` nếu có, `system/Config.qml`). Script bám vào mã nguồn
gốc thay vì chép đè cả file, chạy lại nhiều lần không nhân bản, giữ bản gốc ở
`<tên>.pre-discord-addon`, và `uninstall.sh` sẽ khôi phục lại.

Phải chạy lại installer sau mỗi lần cập nhật Serpantinum, vì bản cập nhật thay
toàn bộ cây `src/`:

```bash
./install.sh install discord
```

Dùng `--skip-qml-patch` nếu chỉ muốn cài theme mà không đụng vào shell (blur
vẫn đồng bộ theo CSS đã tạo lần cuối, nhưng màu sẽ không đổi theo hình nền và
chọn màu từ cửa sổ settings có thể làm mất blur).
