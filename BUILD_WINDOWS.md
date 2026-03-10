# Hướng dẫn Build cho Windows

## Yêu cầu
1. **Windows 10/11** (64-bit)
2. **Flutter SDK** >= 3.10 - [Tải tại đây](https://docs.flutter.dev/get-started/install/windows/desktop)
3. **Visual Studio 2022** với workload "Desktop development with C++"

## Các bước

### 1. Cài Flutter SDK
```powershell
# Tải và giải nén Flutter SDK
# Thêm flutter/bin vào PATH
flutter doctor
```

### 2. Copy project sang máy Windows
Copy toàn bộ folder `duplicate_image_cleaner` sang máy Windows.

### 3. Cài dependencies
```powershell
cd duplicate_image_cleaner
flutter pub get
```

### 4. Build Release
```powershell
flutter build windows --release
```

### 5. Kết quả
File build sẽ nằm tại:
```
build\windows\x64\runner\Release\
```

Trong đó có file `duplicate_image_cleaner.exe` và các DLL đi kèm.

### 6. Đóng gói (Tùy chọn)
Copy toàn bộ folder `Release` để phân phối. Có thể dùng Inno Setup hoặc NSIS để tạo installer.

## Lưu ý
- Không cần cài thêm gì trên máy người dùng cuối
- Chỉ cần copy toàn bộ folder Release là chạy được
- App hỗ trợ Windows 10 trở lên
