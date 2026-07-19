# 長期知識與慣例

- DerivedData 路徑：`~/Library/Developer/Xcode/DerivedData/MyStat-cptaprsmcqofhgawdbywlfmhbzgk/Build/Products/{Debug,Release}/MyStat.app`
- ad-hoc 簽名綁絕對路徑：app 移動後必跑 `codesign --force --deep -s - <path>`；TCC 重置用 `tccutil reset Calendar com.mystat.MyStat`
- SF Symbol `battery.100` 畫布 22×11，glyph 本體 18.2×9（佔比 0.82）——縮放要按本體算
- nettop 名稱截 15 字元、top COMMAND 欄也截斷 → 一律 `proc_pidpath` 反查；新 macOS `ipconfig getsummary` 無定位權限時 SSID 輸出字面值 `<redacted>`
- nettop/ps 單次要跑 >1 秒：任何週期抓取都要防重疊，否則差值趨近 0
- pmset log 格式：Sleep 行 `Using Batt`、Wake 行 `Using BATT`（大小寫不同）；`DarkWake from` 包含 `Wake from`，判斷順序要先 DarkWake
- 睡眠正常基準（此機實測）：約 4 次喚醒/時、0.2-0.3%/時耗電 → 異常門檻 6 次/時、1.5%/時
- 選單列高度 22pt；圖形安全高度：一般 16-18pt、含數字 gauge 18pt、電池充電合成 ~14pt
- SwiftUI hover 加圖示要「常駐佔位＋opacity 切換」，條件式插入會觸發整卡重排版、鄰近 minimumScaleFactor 文字跳動
- Swift Charts hover 模式：chartOverlay + GeometryReader + onContinuousHover + `proxy.value(atX:)`，RuleMark annotation 當 tooltip
- 測試 harness 技巧:swiftc 單獨編譯 provider/generator 檔＋main.swift 即可離線驗證（不用開 app）；scratchpad 在 /private/tmp/claude-501/...
- xcstrings 直接用 python json 讀寫（ensure_ascii=False, indent=2, sort_keys=True）
