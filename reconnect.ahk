#Requires AutoHotkey v2.0
#SingleInstance Force

config := A_ScriptDir "\settings.ini"
if A_Args.Length && A_Args[1] = "--check" {
    if !ValidPlace("1537690962") || ValidPlace("0") || ValidPlace("12&bad=1")
        ExitApp 1
    if BuildURI("1537690962") != "roblox://experiences/start?placeId=1537690962"
        ExitApp 2
    if RetryDue("disconnected", 30999, 1000, 1000)
        ExitApp 3
    if !RetryDue("disconnected", 31000, 1000, 1000)
        ExitApp 4
    if RetryDue("connected", 31000, 1000, 1000) || RetryDue("unknown", 31000, 1000, 1000)
        ExitApp 5
    if RetryDue("screen-disconnected", 8999, 1000, 0) || !RetryDue("screen-disconnected", 9000, 1000, 0)
        ExitApp 6

    FileAppend "PASS: syntax, Place ID validation, URI construction and 30-second retry boundaries. No Roblox request sent.`n", "*"
    ExitApp 0
}

app := Gui(, "Roblox 直接重連")
app.SetFont("s10", "Microsoft JhengHei")
app.AddText("w470", "保留目前 Roblox，直接送出加入遊戲請求。")
app.AddText("xm y+15", "Place ID（遊戲網址 /games/ 後面的數字）")
place := app.AddEdit("xm w470", IniRead(config, "Reconnect", "PlaceID", ""))
autoRetry := app.AddCheckbox("xm y+10", "斷線自動重連；仍斷線時每 30 秒重試")
autoRetry.Value := IniRead(config, "Reconnect", "AutoRetry", "1")
app.AddText("xm y+12 w470", "先儲存 Place ID，再按 F6 重連。F7 顯示設定。")
save := app.AddButton("xm y+12 w150", "儲存設定")
join := app.AddButton("x+10 w150", "直接重連（F6）")
status := app.AddText("xm y+15 w470 h75", "就緒；請先填入 Place ID。")
app.AddText("xm w470", "腳本不關閉 Roblox；是否沿用原程序由客戶端決定。")

app.AddText("xm y+15 w470", "Discord Webhook（在 Discord 頻道整合設定中建立）")
webhook := app.AddEdit("xm w470 Password", IniRead(config, "Discord", "Webhook", ""))
discordEnabled := app.AddCheckbox("xm y+10", "啟用 Discord 斷線與恢復通知")
discordEnabled.Value := IniRead(config, "Discord", "Enabled", "0")
screenshots := app.AddCheckbox("xm y+8", "定時傳送最前方 Roblox 遊戲畫面")
screenshots.Value := IniRead(config, "Discord", "Screenshots", "0")
app.AddText("xm y+8", "截圖間隔（秒，最少 60）")
screenshotSeconds := app.AddEdit("x+10 w100", IniRead(config, "Discord", "ScreenshotSeconds", "300"))
testDiscord := app.AddButton("xm y+10 w150", "測試 Webhook")
screenshotButton := app.AddButton("x+10 w150", "傳送畫面（F8）")
discordStatus := app.AddText("xm y+10 w470 h65", "填入 Webhook 後儲存；F8 可傳送目前畫面。")
app.AddText("xm w470", "僅擷取最前方 Roblox 的遊戲區域；未在最前方時不截圖。")
testDiscord.OnEvent("Click", (*) => LaunchDiscord("Test"))
screenshotButton.OnEvent("Click", SendScreenshot)

save.OnEvent("Click", SaveSettings)
join.OnEvent("Click", Reconnect)
app.OnEvent("Close", (*) => app.Hide())
A_TrayMenu.Add("顯示重連設定", (*) => app.Show())
A_TrayMenu.Add("結束重連腳本", (*) => ExitApp())
if A_Args.Length && A_Args[1] = "--ui-check" {
    FileAppend "PASS: settings UI and event handlers constructed. No Roblox request sent.`n", "*"
    ExitApp 0
}
app.Show()
lastRequest := 0
disconnectedSinceTick := 0
retryAttempts := 0
IniWrite autoRetry.Value, config, "Reconnect", "AutoRetry"
busy := false
lastDiscordRequest := 0
discordRequestPID := 0
monitorPID := 0
OnExit(StopDiscordMonitor)
StartDiscordMonitor()
SetTimer ReadDiscordStatus, 2000
SetTimer CheckVisualDisconnect, 2000
SetTimer AutoRetryTick, 2000
SetTimer EnsureDiscordMonitor, 10000
F6::Reconnect()
F7::app.Show()
F8::SendScreenshot()

ValidPlace(value) {
    return RegExMatch(value, "^[1-9][0-9]{0,19}$")
}
BuildURI(value) {
    return "roblox://experiences/start?placeId=" value
}
SaveSettings(*) {
    global place, config, status, webhook, discordEnabled, screenshots, screenshotSeconds, discordStatus, autoRetry
    value := Trim(place.Value)
    hook := Trim(webhook.Value)
    interval := Trim(screenshotSeconds.Value)
    if value != "" && !ValidPlace(value) {
        status.Text := "請填入有效的數字 Place ID（不能是 0 或完整網址）。"
        return false
    }
    if !ValidWebhook(hook) {
        discordStatus.Text := "Webhook 必須是 https://discord.com/api/webhooks/… 的完整網址。"
        return false
    }
    if discordEnabled.Value && hook = "" {
        discordStatus.Text := "啟用 Discord 通知前，請先填入 Webhook。"
        return false
    }
    if !RegExMatch(interval, "^[0-9]{1,5}$") || Integer(interval) < 60 {
        discordStatus.Text := "截圖間隔請填入 60 至 99999 秒。"
        return false
    }
    try {
        IniWrite value, config, "Reconnect", "PlaceID"
        IniWrite autoRetry.Value, config, "Reconnect", "AutoRetry"
        IniWrite hook, config, "Discord", "Webhook"
        IniWrite discordEnabled.Value, config, "Discord", "Enabled"
        IniWrite screenshots.Value, config, "Discord", "Screenshots"
        IniWrite interval, config, "Discord", "ScreenshotSeconds"
        StartDiscordMonitor()
        status.Text := "設定已儲存；目標 Place ID：" value
        discordStatus.Text := "Discord 設定已儲存。"
        return true
    } catch Error as err {
        status.Text := "儲存設定失敗；請確認設定檔可寫入。"
        return false
    }
}

Reconnect(*) => DoReconnect(false)
DoReconnect(automatic := false) {
    global place, config, status, lastRequest, busy, retryAttempts
    if busy
        return
    if lastRequest && A_TickCount - lastRequest < 10000 {
        status.Text := "請等待 10 秒再重連，避免重複送出請求。"
        return
    }
    if !automatic && !SaveSettings()
        return
    targetPlace := automatic ? IniRead(config, "Reconnect", "PlaceID", "") : Trim(place.Value)
    if !ValidPlace(targetPlace) {
        status.Text := "重連前請先填入 Place ID。"
        return
    }
    hwnd := WinExist("ahk_exe RobloxPlayerBeta.exe")
    if !hwnd {
        status.Text := "找不到正在執行的 Roblox 視窗；請先開啟 Roblox。"
        return
    }
    busy := true
    try {
        pid := WinGetPID("ahk_id " hwnd)
        exe := WinGetProcessPath("ahk_id " hwnd)
        if !FileExist(exe)
            throw Error("找不到目前 Roblox 的執行檔。")
        ; Use the running client's executable, without a bootstrapper or close step.
        uri := BuildURI(targetPlace)
        lastRequest := A_TickCount
        Run '"' exe '" "' uri '"', , , &requestPID
        lastRequest := A_TickCount
        status.Text := automatic
            ? "已自動重連（第 " retryAttempts " 次）；仍斷線時 30 秒後再試。"
            : "已送出重連請求；正在確認原 Roblox 程序是否仍在執行。"
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " request placeId=" targetPlace " originalPID=" pid " requestPID=" requestPID "`n",
            A_ScriptDir "\reconnect.log", "UTF-8"
        SetTimer CheckOriginal.Bind(pid), -8000
    } catch Error as err {
        status.Text := "重連請求失敗：" err.Message
    } finally {
        busy := false
    }
}
CheckOriginal(pid) {
    global status
    alive := ProcessExist(pid)
    message := alive
        ? "原 Roblox 程序仍在執行（PID " pid "）。請在遊戲畫面確認是否已加入。"
        : "原 Roblox 程序已結束；客戶端未保留原程序。腳本沒有關閉遊戲。"
    status.Text := message
    try FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " originalPID=" pid " alive=" (alive ? "yes" : "no") "`n",
        A_ScriptDir "\reconnect.log", "UTF-8"
}


ValidWebhook(value) {
    return value = "" || RegExMatch(value, "^https://discord\.com/api(?:/v[0-9]+)?/webhooks/[0-9]+/[A-Za-z0-9_.-]+$")
}
StartDiscordMonitor() {
    global discordEnabled, autoRetry, monitorPID
    stopFile := A_ScriptDir "\discord-monitor.stop"
    if discordEnabled.Value || autoRetry.Value {
        if FileExist(stopFile)
            FileDelete stopFile
        if !monitorPID || !ProcessExist(monitorPID)
            monitorPID := RunDiscordHelper("Monitor")
    } else {
        FileAppend "", stopFile
    }
}
EnsureDiscordMonitor() {
    global discordEnabled, autoRetry, monitorPID
    if (discordEnabled.Value || autoRetry.Value) && (!monitorPID || !ProcessExist(monitorPID))
        StartDiscordMonitor()
}
RunDiscordHelper(mode) {
    ps := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Run '"' ps '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' A_ScriptDir '\discord.ps1" -Mode ' mode, , "Hide", &helperPID
    return helperPID
}
LaunchDiscord(mode) {
    global webhook, discordStatus, lastDiscordRequest, discordRequestPID
    if discordRequestPID && ProcessExist(discordRequestPID) {
        discordStatus.Text := "前一則 Discord 請求尚未完成。"
        return
    }
    if lastDiscordRequest && A_TickCount - lastDiscordRequest < 10000 {
        discordStatus.Text := "請等 10 秒再傳送 Discord 訊息。"
        return
    }
    if !SaveSettings()
        return
    if !Trim(webhook.Value) {
        discordStatus.Text := "請先填入 Discord Webhook。"
        return
    }
    try {
        discordRequestPID := RunDiscordHelper(mode)
        lastDiscordRequest := A_TickCount
        discordStatus.Text := "正在處理 Discord 請求…"
    } catch Error as err {
        discordStatus.Text := "無法啟動 Discord 傳送工具。"
    }
}
SendScreenshot(*) {
    global app
    app.Hide()
    SetTimer (() => LaunchDiscord("Snapshot")), -400
}
ReadDiscordStatus() {
    global discordStatus
    path := A_ScriptDir "\discord-status.txt"
    if FileExist(path) {
        try discordStatus.Text := FileRead(path, "UTF-8")
    }
}
StopDiscordMonitor(*) {
    try FileAppend "", A_ScriptDir "\discord-monitor.stop"
}


CheckVisualDisconnect() {
    global discordEnabled, autoRetry
    path := A_ScriptDir "\visual-disconnect.txt"
    value := "unknown"
    try {
        if (discordEnabled.Value || autoRetry.Value) && (hwnd := WinActive("ahk_exe RobloxPlayerBeta.exe")) {
            CoordMode "Pixel", "Screen"
            WinGetClientPos &x, &y, &w, &h, "ahk_id " hwnd
            pid := WinGetPID("ahk_id " hwnd)
            found := false
            for width in [75, 100, 125, 150, 175, 200] {
                if ImageSearch(&matchX, &matchY, x, y, x + w - 1, y + h - 1,
                    "*5 *w" width " " A_ScriptDir "\assets\disconnected.png") {
                    found := true
                    break
                }
            }
            if WinActive("ahk_id " hwnd)
                value := pid ":" (found ? "disconnected" : "clear")
        }
        tempPath := path ".tmp"
        file := FileOpen(tempPath, "w", "UTF-8")
        file.Write(value)
        file.Close()
        FileMove tempPath, path, 1
    }
}


RetryDue(state, nowTick, disconnectedSince, previousAttempt) {
    return (state = "disconnected" || state = "screen-disconnected")
        && disconnectedSince > 0 && nowTick - disconnectedSince >= 8000
        && (!previousAttempt || nowTick - previousAttempt >= 30000)
}
AutoRetryTick() {
    global autoRetry, disconnectedSinceTick, lastRequest, status, retryAttempts
    if !autoRetry.Value {
        disconnectedSinceTick := 0
        retryAttempts := 0
        return
    }
    path := A_ScriptDir "\connection-state.txt"
    try {
        if !FileExist(path) || Abs(DateDiff(A_Now, FileGetTime(path), "Seconds")) > 6 {
            disconnectedSinceTick := 0
            return
        }
        value := Trim(FileRead(path, "UTF-8"))
        if !RegExMatch(value, "^([0-9]+):([a-z-]+)$", &match) {
            disconnectedSinceTick := 0
            return
        }
        hwnd := WinExist("ahk_exe RobloxPlayerBeta.exe")
        if !hwnd || WinGetPID("ahk_id " hwnd) != Integer(match[1]) {
            disconnectedSinceTick := 0
            return
        }
        state := match[2]
        if state != "disconnected" && state != "screen-disconnected" {
            disconnectedSinceTick := 0
            if retryAttempts && (state = "connected" || state = "screen-clear") {
                retryAttempts := 0
                status.Text := state = "connected"
                    ? "日誌已確認連線；已停止自動重試。"
                    : "畫面斷線提示已消失；已停止重試，連線狀態待確認。"
            }
            return
        }
        nowTick := A_TickCount
        if !disconnectedSinceTick
            disconnectedSinceTick := nowTick
        if RetryDue(state, nowTick, disconnectedSinceTick, lastRequest) {
            retryAttempts += 1
            DoReconnect(true)
        }
    } catch {
        disconnectedSinceTick := 0
    }
}
