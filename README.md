# Roblox 直接重連 + Discord 監看

## 使用

1. 雙擊 START.bat，填入 Place ID 並按「儲存設定」。
2. F6 直接送出重連請求，F7 顯示設定。
3. Discord：在要接收通知的頻道中，開啟「編輯頻道 → 整合 → Webhook」建立 Webhook，複製網址並貼入腳本設定。
4. 按「測試 Webhook」，確認頻道收到訊息。
5. 勾選「啟用 Discord 斷線與恢復通知」後儲存，開始背景監看。
6. Roblox 位於最前方時，按 F8 傳送目前遊戲截圖與判讀狀態。
7. 若需要定時畫面，勾選「定時傳送最前方 Roblox 遊戲畫面」，設定秒數並儲存。預設 300 秒，最少 60 秒；必須同時啟用 Discord 監看。
8. 關閉設定視窗後快捷鍵與監看仍有效。右鍵系統匣 AutoHotkey 圖示，選「結束重連腳本」才會停止監看。

按「傳送畫面」按鈕時會先隱藏設定視窗；Roblox 不在最前方時只傳文字，不擷取桌面。
定時截圖遇到 Roblox 不在最前方時，會略過該次，不傳文字洗版；60 秒後再檢查，不會重置整個截圖間隔。傳送失敗或 Discord 限流時也會在至少 60 秒後重試；只有成功傳送截圖才重新計算完整間隔。背景監看遇到暫時錯誤會記錄於 monitor-errors.log 並繼續運作，若程序結束則由主腳本重新啟動。

## Discord 通知

- 日誌記錄到斷線／離開伺服器。
- 最前方 Roblox 畫面出現 NatroMacro 的英文斷線提示圖樣。
- 已觀察到的 Roblox 程序結束。
- 斷線後重新建立連線，或畫面斷線提示消失。
- 手動與定時遊戲畫面。

狀態變化持續至少 8 秒才通知，減少正常切換伺服器時的短暫提示。
Discord 訊息不會標記所有人或使用者；Webhook 已綁定接收頻道，不需要 Discord Application ID 或 Bot Token。
傳送結果顯示在設定視窗下方。HTTP 429 或網路錯誤會顯示失敗；定時截圖至少 60 秒後再試。

## 判讀限制

Roblox 程序存在不等於仍在遊戲內連線。
日誌偵測只使用與目前程序啟動時間相符的單一 Player 日誌；多開、日誌缺少事件或無法可靠對應時會顯示未知。
Client:Disconnect 也可能是正常離開伺服器，因此通知不會斷言一定是網路故障。
畫面偵測使用 NatroMacro 的英文斷線提示圖樣及數個縮放比例；中文介面、新版提示或不同字型可能無法匹配。
畫面斷線提示消失只代表提示消失，並不證明恢復連線。
畫面偵測與截圖只在 Roblox 位於最前方時進行；不搶視窗焦點、不還原最小化遊戲。
截圖取 Roblox 用戶區域，沒有錄影或 Discord 語音直播功能。

## 重連

使用目前 Roblox 視窗所屬的 RobloxPlayerBeta.exe，傳入：
roblox://experiences/start?placeId=<PlaceID>

不經 Bloxstrap 啟動器，不執行關閉視窗、終止 Roblox 程序或重新登入。
外部加入連結不是遊戲內 TeleportService；客戶端可能沿用程序、忽略同一遊戲的請求或自行替換程序。
脚本不保證每個版本都能保留原程序，也不保證加入不同伺服器。送出請求不代表已成功加入。
F6 每次至少間隔 10 秒；勾選「斷線自動重連；仍斷線時每 30 秒重試」可啟用自動重連（預設啟用）。自動重連獨立於 Discord 通知。

## 設定與檔案

settings.ini：Place ID、Webhook、通知與截圖設定。Webhook 儲存在本機設定檔中，網址欄位以密碼方式遮蔽。
reconnect.log：重連請求與原 Roblox 程序檢查。
discord-status.txt / discord-status.json：最後一次 Discord 處理結果，不記錄 Webhook 網址。
visual-disconnect.txt：畫面偵測結果；沒有在本機保存遊戲截圖。
discord-monitor.stop：背景工具停止標記。
.gitignore 已排除設定、日誌與監看狀態檔。

## 本機驗證（不傳送訊息）

runtime\AutoHotkey64.exe /ErrorStdOut reconnect.ahk --check
runtime\AutoHotkey64.exe /ErrorStdOut reconnect.ahk --ui-check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File discord.ps1 -Mode Check

只讀查看日誌判讀結果：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File discord.ps1 -Mode Inspect

## 資源來源

runtime/AutoHotkey64.exe 複製自 ../NatroMacro/submacros/AutoHotkey64.exe，版本 2.0.12（GPL v2）。
https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.12
https://github.com/AutoHotkey/AutoHotkey/blob/v2.0.12/license.txt

assets/disconnected.png 複製自 NatroMacro/nm_image_assets/general/disconnected.png。
原 NatroMacro 授權保留於 LICENSE-NatroMacro.md；未啟動其 Heartbeat 或其他巨集。

reconnect.ahk 與 discord.ps1 為獨立撰寫。

連結啟動方式與 Discord API：
https://github.com/bloxstraplabs/bloxstrap/wiki/A-deep-dive-on-how-the-Roblox-bootstrapper-works
https://docs.discord.com/developers/platform/webhooks
https://docs.discord.com/developers/reference#uploading-files

## 30 秒自動重試

重新啟動 START.bat，確認 Place ID 已儲存。
斷線持續至少 8 秒後首次自動重連；若仍持續偵測到斷線，每次請求至少間隔 30 秒再試。
手動 F6 發出的請求同樣會更新自動重試計時，避免剛手動重連就再次自動送出。
日誌確認連線、或畫面斷線提示消失後停止重試；提示消失並不代表已確認連線。
正在加入遊戲、狀態未知、觀察檔過期、程序無法對應時不送出自動請求；再度明確斷線後重新確認 8 秒。
Roblox 程序已關閉或找不到視窗時，不另開遊戲。重試不會主動終止 Roblox。
自動重連不需要 Webhook。若需暂停，取消「斷線自動重連」並儲存，或結束腳本。
connection-state.txt 是背景監看工具供自動重試讀取的暫存判讀檔，不保存 Webhook。
已驗證 30 秒邊界、8 秒確認時間、連線／未知狀態不重試，以及未啟用 Discord 時背景監看仍可運作。