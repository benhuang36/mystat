# AI 工作守則

## 開工前
依序讀：AGENTS.md（本檔）→ TASKS.md → PROGRESS.md 最近 1-2 筆 → 與任務相關的 ARCHITECTURE/MEMORY 段落。不要一次讀完所有文件。

## 建置與驗證
- Build（Debug）：`xcodebuild -project MyStat.xcodeproj -scheme MyStat -configuration Debug build`
- 驗證：重啟 debug 版確認 `pgrep -x MyStat` 存活；圖形類改動用離線渲染（swiftc 單獨編譯 MenuBarImageGenerator.swift + 測試 main.swift 輸出 PNG 目視）
- **交付測試版（每次有可測試的改動都要做，不用等使用者要求）**：
  ```
  xcodebuild -project MyStat.xcodeproj -scheme MyStat -configuration Release build
  rm -rf ~/Desktop/MyStat.app
  cp -R ~/Library/Developer/Xcode/DerivedData/MyStat-*/Build/Products/Release/MyStat.app ~/Desktop/MyStat.app
  codesign --force --deep -s - ~/Desktop/MyStat.app
  ```
- Release：bump `MARKETING_VERSION`（pbxproj 兩處）→ commit → `git tag vX.Y.Z` → push main＋tag → GitHub Actions 自動出 DMG

## 慣例
- 新型別優先放進既有檔案——pbxproj 是明確檔案引用，新增檔案要動 pbxproj
- 在地化：所有 UI 字串進 `Sources/Resources/Localizable.xcstrings`（en source + zh-Hant），用 python json 腳本批次增修
- UserDefaults key 模式：`show{Type}`、`{type小寫}DisplayStyle`、`{type小寫}ChartColor`、`{type小寫}SecondaryColor`、`{type小寫}ShowValue`、`{type小寫}ShowLabel`、`{type小寫}GaugeValueInside`
- Popover UI 一律用 GlassCard.swift 的共用元件（PopoverHeader/StatRow/CardSectionHeader/ProcessListView/CopyableValueRow/ByteFormat）
- Commit 訊息含版本時附 `(vX.Y.Z)`，結尾附 Co-Authored-By
- 系統權限（TCC）注意事項見 project.md：ad-hoc 簽名綁路徑，app 移動後要重簽

## 收工時
更新 PROGRESS.md；有設計決策補 DECISIONS.md；Milestone 完成更新 PLAN/CHANGELOG/TASKS。

## 文件索引
DECISIONS.md / CHANGELOG.md / PLAN.md / TASKS.md / ARCHITECTURE.md / PROGRESS.md / MEMORY.md / project.md（原始需求與 TCC 注意事項）
