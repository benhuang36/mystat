# 設計決策紀錄（新的在上）

## 2026-07-19 SF Symbol 電池按 glyph 本體縮放（比例 0.82）
**決策**：Percentage Text 的電池圖示縮放以「glyph 本體高度」為準（實測本體佔畫布 82%），目標本體 11pt，與 Capacity Bar 自繪電池同高。
**原因**：SF Symbol 畫布四周有留白，按畫布縮放視覺上對不齊。
**捨棄方案**：symbol configuration pointSize（結果不可預測）；改畫自繪電池（使用者要保留閃電樣式）。

## 2026-07-19 充電閃電外框用 12 方向位移剪影（形態學膨脹）
**決策**：閃電鏤空邊距改為沿圓周 12 個方向各位移 1.3pt 打洞。
**原因**：原本「放大 1.5pt 再剪影」在尖角處間距過大、平緩處過小，邊距不均。
**捨棄方案**：原生 `battery.100.bolt` symbol——只有 100% 一種，無法同時表達電量級距＋充電。

## 2026-07-19 圖表 hover 採浮動 tooltip，不動即時數值
**決策**：CPU/Disk/Network 圖表 hover 顯示浮動泡泡（同 Battery 24h 圖樣式），時間標示用「剛剛 / N 秒前」。
**原因**：使用者回饋「hover 值與 current 值共用同一位置很怪」；60 秒短視窗用相對時間比時鐘時間直覺。
**捨棄方案**：header 數值切換式（第一版實作，被否決）；`-12s` 工程式標記（太生硬）。

## 2026-07-18 Network 行程清單：合併單清單＋黏滯保留
**決策**：下載/上傳合併為單一清單（↓↑ 兩欄），行程歸零後以 0K 顯示 60 秒才移除；速度做 EMA 平滑（新 0.7/舊 0.3）；取樣中斷後恢復（>5s）只重建基準值並回傳快取清單。
**原因**：仿 iStat——清單不跳動、不瞬間變空；popover 重開不清空。
**捨棄方案**：即時清單（行程頻繁進出，視覺跳動）。

## 2026-07-18 SSID 取得：CoreWLAN＋定位權限，指令工具當 fallback
**決策**：主要用 CWWiFiClient（新 macOS 需 CoreLocation 授權，首次需要時請求）；拿不到時背景跑 `ipconfig getsummary` → `networksetup -getairportnetwork`；所有來源過濾 `<redacted>` 字面值。
**原因**：macOS 14+ 無定位權限時 SSID 被遮蔽，且 ipconfig 會輸出字面值 `<redacted>`。

## 2026-07-18 睡眠報告：解析 pmset log，異常門檻 6 次/時、1.5%/時
**決策**：從 `pmset -g log` 重建睡眠場次（進睡→完整喚醒），異常條件：第三方喚醒來源（Apple daemon 白名單比對）、>6 喚醒/時、>1.5%/時耗電；僅評估 >30 分鐘場次。另以 `pmset -g assertions` 即時列出阻止睡眠者。
**原因**：第三方 App 幾乎不排程 RTC 喚醒，真正耗電元兇是 assertion 阻睡；門檻基於實測正常值（約 4 次/時、0.2-0.3%/時）。
**捨棄方案**：只警示非 Apple 喚醒（幾乎不會觸發，漏掉主要場景）。

## 2026-07-18 nettop 用 -P＋PID 反查全名，行程按 App 歸戶
**決策**：nettop 加 `-P`（只出 process 列）；名稱用 `proc_pidpath` 反查完整執行檔名；`XXX Helper (…)` 歸戶到主程式名。top 的 Energy Impact 同樣用 PID 反查。
**原因**：nettop 截斷名稱至 15 字元、top 的 COMMAND 欄也截斷；瀏覽器流量分散在多個 Helper。

## 2026-07-18 行程抓取防重疊（isFetchingProcesses）
**決策**：SystemMonitor 的行程抓取加 guard；NetworkProcessProvider 另有 0.5 秒最小取樣間隔＋快取。
**原因**：nettop/ps 要跑 >1 秒，重疊取樣的時間差趨近 0 → 速度算出 ~0 → 清單被門檻清空（曾是「清單常空」的主因）。

## 2026-07-18 activePopoversCount 修正：每次開啟都 +1
**決策**：popover 計數移出「panel 首次建立」區塊。
**原因**：panel 會保留重用，原寫法只在第一次開啟 +1、每次關閉 -1，重開後計數卡 0，行程/GPU/感測器全部停更。

## 2026-07-17 Popover 共用設計系統（GlassCard.swift）
**決策**：PopoverHeader/StatRow/CardSectionHeader/ProcessListView/ByteFormat/MonitorType.accentColor 集中於 GlassCard.swift；popover 寬 320、行程列高 17pt、圖示 16pt。
**原因**：七個 popover 各自手刻，字級/顏色/結構不一致；accent 色與設定側欄統一單一來源。
**捨棄方案**：逐檔微調（治標）。

## 2026-07-17 Network 圖表合併為鏡像圖，各方向獨立正規化
**決策**：下載朝上、上傳朝下的單一 BarMark 圖，各以自身峰值正規化；顏色統一下載青/上傳紅（與選單列一致，修正原本 popover 顏色相反的問題）。
**原因**：省空間（原兩張 70px 圖）；上下行量級差距大，共用刻度會壓扁小的一方。精確值由 hover tooltip 提供。

## 2026-07-17 設定改用原生 grouped Form、移除 Live Preview
**決策**：Settings 用 `Form + .formStyle(.grouped)`（系統設定風格），刪除 popover 即時預覽，視窗 640×460。
**原因**：使用者明確不要 preview；原生控件比自刻 GroupBox 佈局可維護。

## 2026-07-17 假數據一律換真或移除
**決策**：Memory PRESSURE 用 `(wired+compressed)/total`、App/Wired/Compressed 接 host_statistics64;CPU User/System 用 host_processor_info 的真實 tick 拆分（User 含 nice，對齊活動監視器口徑）。
**原因**：原程式碼寫死 44%、"3.7 GB" 或用 `cpuUsage×0.7` 捏造，顯示假數據比少顯示更糟。
