# Chat 應用程式

這是一個使用 Flutter 開發的即時聊天應用程式，支援 WebSocket 和 TCP Socket 連線。

## 主要功能

*   即時訊息傳遞
*   使用者上線/離線通知
*   顯示線上使用者列表
*   使用者名稱設定
*   管理員功能：
    *   踢出使用者
    *   提升/降級使用者權限 (管理員/Root)
    *   關閉聊天室 (管理員/Root)
*   輸入狀態提示
*   訊息時間戳記
*   支援 Markdown 格式訊息
*   深色模式支援

## 技術棧

*   **前端**: Flutter
*   **後端**: Python (WebSocket/Socket 伺服器 - 參考 `chat-server` 目錄)
*   **通訊協定**: WebSocket, TCP Socket

## 如何開始

### 1. 設定後端伺服器

本專案包含一個 Python 後端伺服器範例，位於 `chat-server` 目錄下。

*   進入 `chat-server` 目錄：
    ```bash
    cd chat-server
    ```
*   (可選) 建立並啟用虛擬環境：
    ```bash
    python3 -m venv venv
    source venv/bin/activate  # macOS/Linux
    # venv\Scripts\activate    # Windows
    ```
*   安裝依賴套件：
    ```bash
    pip install -r requirements.txt
    ```
*   啟動伺服器 (預設監聽 `localhost:8765` for WebSocket 和 `localhost:12345` for Socket)：
    ```bash
    python src/chat_server.py
    ```
    您可以修改 `config.json` 來變更伺服器設定。

### 2. 執行 Flutter 前端應用程式

*   確保您已安裝 Flutter SDK。
*   在專案根目錄下 (包含此 `README.md` 的目錄) 執行：
    ```bash
    flutter pub get
    flutter run
    ```
*   應用程式啟動後，在登入頁面輸入伺服器位址 (例如 `localhost:8765` for WebSocket 或 `localhost:12345` for Socket) 和您的使用者名稱即可開始使用。

## 專案結構 (簡化)

```
chat/
├── android/              # Android 專案檔案
├── ios/                  # iOS 專案檔案
├── lib/                  # Flutter Dart 程式碼
│   ├── main.dart         # 應用程式進入點
│   ├── models/           # 資料模型 (User, ChatMessage)
│   ├── screens/          # UI 畫面 (LoginPage, ChatRoom)
│   └── widgets/          # 自訂 UI 元件
├── chat-server/          # Python 後端伺服器
│   ├── src/
│   │   ├── chat_server.py  # 伺服器主程式
│   │   └── ...             # 其他後端模組
│   ├── config.json       # 伺服器設定檔
│   └── requirements.txt  # Python 依賴
├── pubspec.yaml          # Flutter 專案設定檔
└── README.md             # 本文件
```

## Flutter 預設說明

(以下為 Flutter 專案建立時的預設說明，您可以選擇保留或移除)

A new Flutter project.

### Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
