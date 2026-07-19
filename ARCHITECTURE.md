# 系統架構

## 總覽
選單列常駐 App（SwiftUI + AppKit，macOS 13+，無沙盒）。`SystemMonitor` 每秒 tick 從各 Provider 取數據並 @Published；每個啟用的監控項是一個 `StatusItemController`（NSStatusItem＋自訂 NSPanel popover）；設定是 NavigationSplitView＋grouped Form。省電核心：`activePopoversCount == 0` 時跳過行程/GPU/感測器/網路資訊抓取。

## 模組

### Sources/Monitor/SystemMonitor.swift
中樞。1 秒 Timer tick，依「有 popover 開啟或該監控項顯示中」決定抓什麼。行程抓取丟背景 queue 且以 `isFetchingProcesses` 防重疊。

### Sources/Monitor/Providers/
- `CPUProvider`：host_processor_info，總量＋User/System 拆分＋每核心
- `MemoryProvider`：host_statistics64（wired/active/compressed/swap）
- `DiskProvider`、`GPUProvider`、`SensorProvider`：容量與 I/O、GPU 使用率、溫度風扇
- `NetworkProvider`：介面流量計數；**NetworkInfoManager**（同檔）：主介面/SSID（CoreWLAN＋CLLocation＋指令 fallback）/IPv4/IPv6/公共 IP（ipify，快取 5 分）/Ping
- `NetworkProcessProvider`：nettop -P 差值計算，PID 反查名稱、App 歸戶、EMA 平滑、0K 黏滯 60 秒、中斷恢復保留快取
- `ProcessProvider`：proc_pidinfo 掃全行程（CPU/記憶體/磁碟 top）；top 指令抓 Energy Impact；**ProcessIcon**（同檔）：PID → .app bundle 圖示，路徑快取
- `BatteryProvider`：IOKit AppleSmartBattery（含 designCapacity/健康度）；**SleepReportManager**（同檔）：pmset log 睡眠場次解析＋異常判定＋assertions 阻睡清單；BatteryHistoryManager：24h 電量紀錄

### Sources/StatusItemController.swift
選單列渲染與 popover 生命週期。依 UserDefaults 樣式 key 分派到 MenuBarImageGenerator；顏色：預設色 → 使用者色票覆蓋。popover 開關維護 activePopoversCount（每開 +1 每關 -1，panel 保留重用）。

### Sources/Monitor/MenuBarImageGenerator.swift
純繪圖：history/pie/gauge（可含圓內數字，18pt）/bar/coreBars/capacityBar（可帶電池電極頭）、addValueText/addLabel/addSpeedText。NSImage drawingHandler 每次顯示重繪，controlTextColor 自動適應外觀。

### Sources/UI/
- `GlassCard.swift`：**popover 設計系統**——GlassCard/PopoverHeader/StatRow/CardSectionHeader/ProcessListView/CopyableValueRow/ByteFormat/PopoverStyle 常數/MonitorType.accentColor
- `*PopoverView.swift`：七個 popover，一律組裝設計系統元件；圖表 hover tooltip 模式（chartOverlay + onContinuousHover + RuleMark annotation）
- `SettingsView.swift`：DisplayStyle/MenuBarColor enum＋設定 UI（grouped Form）

### Sources/Resources/Localizable.xcstrings
en source + zh-Hant。用 python json 腳本批次維護。

### 建置/發布
Xcode 專案（明確檔案引用，新檔要動 pbxproj）。tag push 觸發 GitHub Actions「Build and Release DMG」。
