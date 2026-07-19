# Changelog

## [0.3.0] - 2026-07-19
### Added
- Battery 睡眠報告卡：睡眠時長/耗電/喚醒次數，異常警示（第三方喚醒源、頻率>6次/時、耗電>1.5%/時），即時「正在阻止睡眠」清單
- Network 連線資訊卡：Wi-Fi SSID（含定位權限流程與指令 fallback）、本機/公共 IPv4＋IPv6、Ping（1.1.1.1）
- IP 列點擊複製（CopyableValueRow，hover 佔位圖示不觸發重排版）
- CPU/Disk/Network 圖表 hover tooltip（浮動泡泡，「剛剛 / N 秒前」）
- Arc Gauge「數值顯示於圓環內」選項（18pt 圓＋圓內數字，三位數自動縮字）
- Battery 新增 Arc Gauge / Pie Chart / Bar Chart 選單列樣式
### Changed
- Percentage Text 電池圖示縮放至與 Capacity Bar 同高（glyph 本體 11pt）；Capacity Bar 數值文字放大至 13pt
- Network 行程清單合併為單清單（↓↑ 兩欄），0K 黏滯保留 60 秒，popover 重開不清空
### Fixed
- 充電閃電外框間距不均（改 12 方向位移剪影）
- `<redacted>` 被當成 SSID 顯示

## [0.2.0] - 2026-07-17
### Added
- 選單列新樣式：Core Bars（每核心直條）、Capacity Bar（電池型含電極頭）
- 每監控項自訂圖表顏色（含 Network 上/下行、Disk 讀/寫獨立色）；圖表旁數值文字
- Popover 行程清單 App 圖示（PID → .app bundle 歸戶）
- Disk history 圖表接上讀/寫真實數據（原為空白）
### Changed
- 設定重構為原生 grouped Form，移除 Live Preview；側欄圖示改系統設定風格
- 七個 popover 統一設計系統；Network popover 合併鏡像圖表；假數據換真（Memory 細目/Pressure、CPU User/System）
- Battery popover：健康度百分比、電量/完全充電/設計容量分列
### Fixed
- popover 重開後計數卡 0 導致行程/感測器停更
- 行程抓取重疊導致網路行程清單常空；nettop/top 名稱截斷

## [0.1.1] - 2026-07-10
- Battery 圖表互動 tooltip、時間同步修正、行事曆修正、省電最佳化

## [0.1.0] - 2026-07-10
- 初始版本（Antigravity/Gemini 3.1 Pro 產出）：CPU/Memory/Disk/Network/Battery/Time/Display 監控、GitHub Actions DMG release
