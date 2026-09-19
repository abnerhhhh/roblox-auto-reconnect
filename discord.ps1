param(
    [ValidateSet('Monitor','Snapshot','Test','Check','Inspect')]
    [string]$Mode = 'Monitor'
)
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$configPath = Join-Path $base 'settings.ini'
$resultPath = Join-Path $base 'discord-status.json'
$stopPath = Join-Path $base 'discord-monitor.stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Read-Settings {
    $values = @{}
    $section = ''
    if (Test-Path -LiteralPath $configPath) {
        foreach ($line in [IO.File]::ReadAllLines($configPath)) {
            if ($line -match '^\s*\[([^\]]+)\]') { $section = $Matches[1]; continue }
            if ($line -match '^\s*([^;=]+?)\s*=(.*)$') {
                $values[$section + '.' + $Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }
    return $values
}
function Valid-Webhook([string]$url) {
    return $url -cmatch '^https://discord\.com/api(?:/v[0-9]+)?/webhooks/[0-9]+/[A-Za-z0-9_.-]+$'
}
function Get-LogState([string]$text) {
    $state = 'unknown'
    foreach ($line in ($text -split "\r?\n")) {
        if ($line -match '(?i)Connection accepted from') { $state = 'connected' }
        elseif ($line -match '(?i)Client:Disconnect|ID_CONNECTION_LOST|ID_DISCONNECTION_NOTIFICATION|Connection lost|Disconnected with error|disconnect reason|Disconnection Notification|Connection closed:.*error') {
            $state = 'disconnected'
        }
        elseif ($line -match '(?i)! Joining game|GameJoinUtil.*joinGame') { $state = 'joining' }
    }
    return $state
}
function State-Label([string]$state) {
    switch ($state) {
        'connected' { return '日誌記錄：已建立遊戲連線' }
        'disconnected' { return '日誌記錄：連線已中斷或已離開伺服器' }
        'joining' { return '日誌記錄：正在加入遊戲' }
        'screen-disconnected' { return '畫面偵測：出現 Roblox 英文斷線提示' }
        'screen-clear' { return '畫面未看到斷線提示；連線狀態尚未確認' }
        'closed' { return 'Roblox 程序未執行' }
        default { return 'Roblox 執行中；日誌不足，連線狀態未知' }
    }
}
function Write-Status([string]$message, [string]$state = '') {
    $payload = @{ time = (Get-Date).ToString('HH:mm:ss'); message = $message; state = $state }
    $tempPath = $resultPath + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($tempPath, ($payload | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $resultPath -Force
    $textTemp = (Join-Path $base ('discord-status.' + $PID + '.tmp'))
    [IO.File]::WriteAllText($textTemp, ('[' + $payload.time + '] ' + $message), [Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $textTemp -Destination (Join-Path $base 'discord-status.txt') -Force
}
function Read-Tail([string]$path) {
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $start = [Math]::Max(0, $stream.Length - 262144)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try {
            $text = $reader.ReadToEnd()
            if ($start -gt 0) {
                $newline = $text.IndexOf("`n")
                if ($newline -ge 0) { $text = $text.Substring($newline + 1) }
            }
            return $text
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
function Apply-VisualState($observation) {
    $path = Join-Path $base 'visual-disconnect.txt'
    if (Test-Path -LiteralPath $path) {
        $file = Get-Item -LiteralPath $path
        if (((Get-Date) - $file.LastWriteTime).TotalSeconds -lt 6) {
            $value = [IO.File]::ReadAllText($path).Trim()
            if ($value -match '^([0-9]+):(disconnected|clear)$' -and [int]$Matches[1] -eq $observation.pid) {
                if ($Matches[2] -eq 'disconnected') { $observation.state = 'screen-disconnected' }
                elseif ($observation.state -eq 'unknown') { $observation.state = 'screen-clear' }
            }
        }
    }
    return $observation
}

function Write-Observation($observation) {
    $path = Join-Path $base 'connection-state.txt'
    $temp = $path + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($temp, ([string]$observation.pid + ':' + $observation.state), [Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Get-Observation {
    $players = @(Get-Process -Name RobloxPlayerBeta -ErrorAction SilentlyContinue)
    if (!$players.Count) { return @{ state = 'closed'; pid = 0; log = ''; place = '' } }
    # Multiple clients cannot reliably be mapped to logs without process metadata.
    if ($players.Count -ne 1) { return @{ state = 'unknown'; pid = 0; log = ''; place = '' } }
    $player = $players[0]
    $startTime = $player.StartTime
    $logDirectory = Join-Path $env:LOCALAPPDATA 'Roblox\logs'
    $logs = @(Get-ChildItem -LiteralPath $logDirectory -File -Filter '*Player*.log' -ErrorAction SilentlyContinue |
        Where-Object { [Math]::Abs(($_.CreationTime - $startTime).TotalSeconds) -lt 60 } |
        Sort-Object CreationTime -Descending)
    if ($logs.Count -ne 1) { return (Apply-VisualState @{ state = 'unknown'; pid = $player.Id; log = ''; place = '' }) }
    $text = Read-Tail $logs[0].FullName
    $actualPlace = ''
    $joins = [regex]::Matches($text, "! Joining game '[^']+' place ([0-9]+)")
    if ($joins.Count) { $actualPlace = $joins[$joins.Count - 1].Groups[1].Value }
    return (Apply-VisualState @{ state = (Get-LogState $text); pid = $player.Id; log = $logs[0].Name; place = $actualPlace })
}
function Initialize-Capture {
    if ('ReconnectCapture' -as [type]) { return }
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ReconnectCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
    [void][ReconnectCapture]::SetProcessDPIAware()
}
function Capture-Game {
    Initialize-Capture
    $hwnd = [ReconnectCapture]::GetForegroundWindow()
    [uint32]$foregroundPID = 0
    [void][ReconnectCapture]::GetWindowThreadProcessId($hwnd, [ref]$foregroundPID)
    $player = Get-Process -Id $foregroundPID -ErrorAction SilentlyContinue
    if (!$player -or $player.ProcessName -ne 'RobloxPlayerBeta' -or [ReconnectCapture]::IsIconic($hwnd)) { return $null }
    $rect = [ReconnectCapture+RECT]::new()
    $point = [ReconnectCapture+POINT]::new()
    if (![ReconnectCapture]::GetClientRect($hwnd, [ref]$rect) -or ![ReconnectCapture]::ClientToScreen($hwnd, [ref]$point)) { return $null }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0 -or $width -gt 16384 -or $height -gt 16384) { return $null }
    $bitmap = [Drawing.Bitmap]::new($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $memory = [IO.MemoryStream]::new()
    try {
        if ([ReconnectCapture]::GetForegroundWindow() -ne $hwnd) { return $null }
        $graphics.CopyFromScreen($point.X, $point.Y, 0, 0, $bitmap.Size)
        # Discard a capture if the user switched apps while it was being taken.
        if ([ReconnectCapture]::GetForegroundWindow() -ne $hwnd) { return $null }
        $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
        return ,$memory.ToArray()
    } finally {
        $memory.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
function New-Payload([string]$message, [bool]$hasImage) {
    $payload = @{ username = 'Roblox 重連監看'; content = $message; allowed_mentions = @{ parse = @() } }
    if ($hasImage) {
        $payload['embeds'] = @(@{ title = '目前 Roblox 遊戲畫面'; image = @{ url = 'attachment://roblox.png' } })
    }
    return ($payload | ConvertTo-Json -Depth 6 -Compress)
}
function Screenshot-Due([datetime]$now, [datetime]$lastSuccess, [datetime]$lastAttempt, [int]$intervalSeconds) {
    return ($now - $lastSuccess).TotalSeconds -ge $intervalSeconds -and ($now - $lastAttempt).TotalSeconds -ge 60
}
function Send-Discord([string]$message, [bool]$withScreenshot, [string]$state = '', [bool]$skipWithoutImage = $false) {
    $settings = Read-Settings
    $url = [string]$settings['Discord.Webhook']
    if (!(Valid-Webhook $url)) {
        Write-Status '尚未設定有效的 Discord Webhook。' $state
        return $false
    }
    $image = $null
    if ($withScreenshot) { $image = Capture-Game }
    if ($withScreenshot -and !$image) {
        if ($skipWithoutImage) {
            Write-Status '略過定時截圖：Roblox 未在最前方；60 秒後再檢查。' $state
            return $false
        }
        $message += "`n未附截圖：Roblox 未在最前方或無法擷取。"
    }
    if ($image -and $image.Length -gt 9500000) {
        Write-Status '截圖超過上傳大小限制；60 秒後再檢查。' $state
        return $false
    }
    $body = New-Payload $message ([bool]$image)
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('RobloxReconnect/1.0')
    $form = [Net.Http.MultipartFormDataContent]::new()
    try {
        $form.Add([Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'application/json'), 'payload_json')
        if ($image) {
            $part = [Net.Http.ByteArrayContent]::new([byte[]]$image)
            $part.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('image/png')
            $form.Add($part, 'files[0]', 'roblox.png')
        }
        $response = $client.PostAsync($url + '?wait=true', $form).GetAwaiter().GetResult()
        try {
            if ($response.IsSuccessStatusCode) { Write-Status 'Discord 訊息已送出。' $state; return $true }
            elseif ([int]$response.StatusCode -eq 429) { Write-Status 'Discord 限流；60 秒後再試。' $state }
            else { Write-Status ('Discord 傳送失敗，HTTP ' + [int]$response.StatusCode) $state }
        } finally { $response.Dispose() }
    } catch {
        # Never include exception text: it can contain the secret webhook URL.
        Write-Status 'Discord 傳送失敗：連線逾時或網路錯誤。' $state
    } finally { $form.Dispose(); $client.Dispose() }
    return $false
}
if ($Mode -eq 'Check') {
    if (!(Valid-Webhook 'https://discord.com/api/webhooks/123456/test_token')) { throw 'Webhook validation failed' }
    if (Valid-Webhook 'https://discord.com.evil.test/api/webhooks/123/token') { throw 'Invalid host accepted' }
    if ((Get-LogState "Connection accepted from test`nClient:Disconnect") -ne 'disconnected') { throw 'Disconnect transition failed' }
    if ((Get-LogState "Client:Disconnect`n! Joining game 'test' place 123`nConnection accepted from test") -ne 'connected') { throw 'Rejoin transition failed' }
    if ((Get-LogState 'MegaReplicatorLogDisconnectCleanUpLog') -ne 'unknown') { throw 'Cleanup incorrectly classified' }
    $sample = New-Payload '文字 "quote" \ and newline' $true | ConvertFrom-Json
    if ($sample.embeds[0].image.url -ne 'attachment://roblox.png' -or $sample.allowed_mentions.parse.Count -ne 0) { throw 'Payload failed' }
    Initialize-Capture
    $t=Get-Date
    if(Screenshot-Due $t ($t.AddSeconds(-3600)) ($t.AddSeconds(-59)) 3600){throw 'Early retry'}
    if(!(Screenshot-Due $t ($t.AddSeconds(-3600)) ($t.AddSeconds(-60)) 3600)){throw 'Missed retry'}
    Write-Output 'PASS: log transitions, webhook validation, JSON attachment payload and capture API. No message or screenshot sent.'
    exit 0
}
if ($Mode -eq 'Inspect') {
    $observation = Get-Observation
    $observation | ConvertTo-Json -Compress
    exit 0
}
try {
    if ($Mode -eq 'Test') {
        Send-Discord ('Webhook 測試成功。時間：' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $false
        exit 0
    }
    if ($Mode -eq 'Snapshot') {
        $observation = Get-Observation
        $settings = Read-Settings
        $label = if ($observation.place) { '日誌 Place ID：' + $observation.place } else { '設定目標 Place ID：' + $settings['Reconnect.PlaceID'] }
        Send-Discord ((State-Label $observation.state) + "`n" + $label) $true $observation.state
        exit 0
    }
    $created = $false
    $mutexName = 'Local\RobloxReconnectMonitor_' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($base)).Replace('\','_').Replace('/','_')
    $mutex = [Threading.Mutex]::new($true, $mutexName, [ref]$created)
    if (!$created) { $mutex.Dispose(); exit 0 }
    try {
        $published = ''
        $candidate = ''
        $candidateSince = Get-Date
        $lastScreenshot = Get-Date
        $lastScreenshotAttempt = [datetime]::MinValue
        $awaitRecovery = $false
        while (!(Test-Path -LiteralPath $stopPath)) {
            try {
            $settings = Read-Settings
            if ($settings['Discord.Enabled'] -ne '1' -and $settings['Reconnect.AutoRetry'] -ne '1') {
                $published = ''
                Write-Status 'Discord 監看未啟用。'
                Start-Sleep -Seconds 2
                continue
            }
            $observation = Get-Observation
            Write-Observation $observation
            $state = $observation.state
            if (!$published) {
                $published = 'initial'
                $candidate = $state
                $candidateSince = Get-Date
                Write-Status ('監看中：' + (State-Label $state)) $state
            }
            if ($state -ne $candidate) {
                $candidate = $state
                $candidateSince = Get-Date
            }
            if ($candidate -ne $published -and ((Get-Date) - $candidateSince).TotalSeconds -ge 8) {
                # Debounce teleport/leave events; never label them as proven network failures.
                if ($settings['Discord.Enabled'] -eq '1' -and ($candidate -in @('disconnected','screen-disconnected') -or ($candidate -eq 'closed' -and $published -notin @('closed','initial')) -or
                    ($candidate -in @('connected','screen-clear') -and $awaitRecovery))) {
                    $label = if ($observation.place) { '日誌 Place ID：' + $observation.place } else { '設定目標 Place ID：' + $settings['Reconnect.PlaceID'] }
                    Send-Discord ((State-Label $candidate) + "`n" + $label + "`n時間：" + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $true $candidate
                    $awaitRecovery = $candidate -in @('disconnected','screen-disconnected','closed')
                }
                $published = $candidate
            }
            [int]$seconds = 300
            [int]$parsedSeconds = 0
            if ([int]::TryParse([string]$settings['Discord.ScreenshotSeconds'], [ref]$parsedSeconds)) { $seconds = [Math]::Max(60, $parsedSeconds) }
            if ($settings['Discord.Enabled'] -eq '1' -and $settings['Discord.Screenshots'] -eq '1' -and
                (Screenshot-Due (Get-Date) $lastScreenshot $lastScreenshotAttempt $seconds)) {
                $lastScreenshotAttempt = Get-Date
                if (Send-Discord ('定時遊戲畫面。' + "`n" + (State-Label $state)) $true $state $true) {
                    $lastScreenshot = Get-Date
                }
            }
            } catch {
                $errorType = $_.Exception.GetType().Name
                $errorLine = $_.InvocationInfo.ScriptLineNumber
                try {
                    Add-Content -LiteralPath (Join-Path $base 'monitor-errors.log') -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $errorType + ' line=' + $errorLine)
                    Write-Status ('監看暫時出錯（' + $errorType + '，第 ' + $errorLine + ' 行）；正在重試。')
                } catch {}
            }
            Start-Sleep -Seconds 2
        }
    } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
} catch {
    Write-Status '監看或截圖失敗；請確認 Roblox 日誌與視窗可存取。'
    exit 1
}
