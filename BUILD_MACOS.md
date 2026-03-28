# Hướng dẫn Build cho macOS

## Yêu cầu
1. **macOS 10.14+** (Mojave trở lên)
2. **Flutter SDK** >= 3.10 - [Tải tại đây](https://docs.flutter.dev/get-started/install/macos/desktop)
3. **Xcode** (cài từ App Store)

## Các bước

### 1. Cài Flutter SDK
```bash
# Tải và giải nén Flutter SDK
# Thêm flutter/bin vào PATH
flutter doctor
```

### 2. Cài dependencies
```bash
cd duplicate_image_cleaner
flutter pub get
```

### 3. Build Release
```bash
flutter build macos --release
```

### 4. Kết quả
File `.app` sẽ nằm tại:
```
build/macos/Build/Products/Release/duplicate_image_cleaner.app
```

### 5. Tạo DMG (Tùy chọn)
```bash
hdiutil create -volname "Duplicate Image Cleaner" \
  -srcfolder "build/macos/Build/Products/Release/duplicate_image_cleaner.app" \
  -ov -format UDZO \
  "build/duplicate_image_cleaner_macos.dmg"
```

File DMG sẽ nằm tại: `build/duplicate_image_cleaner_macos.dmg`

## Cách sử dụng
- **File .app**: Kéo vào thư mục Applications hoặc double-click để chạy trực tiếp
- **File .dmg**: Mở DMG, kéo app vào Applications

## Lưu ý
- App đã được cấu hình sandbox với quyền đọc/ghi file do người dùng chọn
- Không cần cài thêm gì trên máy người dùng cuối
- Nếu macOS chặn app (Gatekeeper), vào System Settings > Privacy & Security > cho phép app chạy
