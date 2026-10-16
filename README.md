# Vcamcobay Virtual Camera Tweak

Một tweak iOS nhắm tới môi trường RootHide, đi kèm giao diện điều khiển nổi (floating UI) có thể kéo thả.

## Tính năng
- **Virtual Stream:** Thay thế camera thật bằng logo hoặc video tùy chỉnh.
- **Floating UI:** Nút tròn nhỏ gọn, có thể kéo thả khắp màn hình.
- **Control Panel:** Nhấn vào nút tròn để mở bảng điều khiển bật/tắt chế độ Logo.
- **RootHide Package:** Đóng gói bằng RootHide Theos scheme (`roothide`); không phải gói rootless thường.

## Cài đặt
1. Clone repository này về máy.
2. Sử dụng Theos để build gói `.deb`.
3. Cài đặt qua Sileo/Zebra hoặc trực tiếp trên thiết bị.

## Cấu trúc thư mục
- `Tweak.x`: Logic chính của tweak (Hook Camera & UI).
- `Makefile`: Cấu hình build.
- `DEBIAN/`: File cấu hình package.
- `Resources/`: Ảnh logo và cấu hình UI.

## Tác giả
hoanggiasg89-coder
