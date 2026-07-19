# 工作進度（新的在上）

## 2026-07-19
- 完成：圖表 hover tooltip（浮動泡泡＋「剛剛/N 秒前」）；Gauge 圓環內數值選項；電池圖示尺寸統一（glyph 實測 0.82 縮放）＋閃電邊距修正（12 方向膨脹）；Battery 補 Gauge/Pie/Bar 三樣式；發布 v0.3.0（CI DMG 成功）
- 驗證：離線渲染 PNG 目視（gauge 7/42/100、電池圖示）；debug 版重啟運行；CI green
- 未完：無（M1 收尾）；建立八文件架構＋project-docs skill

## 2026-07-18
- 完成：睡眠報告（pmset 解析＋異常門檻＋阻睡清單）；Network 資訊卡（SSID/IPv4/IPv6/Ping/公共 IP）；IP 點擊複製（hover 佔位修排版連動）；SSID 定位權限流程＋`<redacted>` 過濾；行程清單合併＋黏滯＋重開保留快取；桌面簽名版工作流程建立
- 驗證：睡眠解析器吃真實 pmset 輸出（重建 29h 場次，數字與手動分析一致）；抓到活的 assertion 案例（AddressBookSourceSync）
- 關鍵修正：activePopoversCount 重開卡 0（行程/感測器停更主因）

## 2026-07-17
- 完成：設定重構（grouped Form、去 preview）；選單列新樣式（Core Bars/Capacity Bar/色票/數值文字）；popover 統一設計系統；行程圖示；假數據換真（Memory 細目、CPU User/System）；Network 合併鏡像圖＋行程抓取防重疊＋nettop/top 名稱反查；發布 v0.2.0
- 驗證：離線渲染各新樣式 PNG；Swift 測試 harness 直跑 provider 確認解析；curl 產流量實測
