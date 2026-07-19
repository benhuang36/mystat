# 專案計劃

## 目前 Milestone
**M1：iStat 視覺與功能基本對齊（v0.3.0）— 已完成 2026-07-19**
選單列樣式豐富化、設定原生化、popover 統一設計系統、Network/Battery 資訊深化、睡眠報告。

## Roadmap
1. **M2：Combined Mode** — 多監控項合併為單一選單列項目（iStat 的招牌功能），可自訂順序與間距
2. **M3：GPU / Sensors 獨立監控項** — GPU 使用率、溫度、風扇進選單列（資料源已有：gpuUsage/sensorStats）
3. **M4：通知與自動化** — 睡眠異常通知（UNUserNotificationCenter）、低電量/高溫警示
4. **M5：客製化深化** — Ping 目標主機設定、更新頻率設定、更多語言

## 範圍之外
- Safari 流量精確歸戶（WebKit.Networking 需私有 API）
- 上架 App Store / 開發者簽名（目前 ad-hoc + GitHub Release DMG）
