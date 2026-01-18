-- ============================================================================
-- GLOBAL COLORS & VARIABLES / 全域顏色與變數定義
-- ============================================================================
OUT_OF_SESSION_COLOR="20,20,20,30"
OUT_OF_SESSION_FONT_COLOR="255,255,255,100"
OUT_OF_SESSION="OUT OF SESSION"
MACRO_COLOR="0,80,150,180"
WHITE_COLOR="255,255,255,200"
LIGHT_COLOR="255,255,255,150"
COUNTDOWN_COLOR="255,255,255,150"
ALERT_COLOR="255,0,0,150"

-- Notification System State / 通知系統狀態變數
notifyTimer = 0
notifyMessage = ""
notifyColor = WHITE_COLOR
lastMacroState = false
NOW_UTC = os.time(os.date("!*t"))

-- DEBUG SETTINGS: Simulation Mode / 調試設定：模擬穿越模式
DEBUG_MODE = false
--DEBUG_NY_TIME_STR="2026-01-13 06:50:00"
--DEBUG_NY_TIME_STR="" -- Target simulation time / 目標模擬時間

local nextRetryTime = 0 
local RETRY_INTERVAL = 3600 -- WebParser retry interval (1hr) / 網頁重試間隔 (1小時)

-- ============================================================================
-- MARKET CALENDAR 2026 / 2026 年市場交易日曆 (休市與提早收盤)
-- ============================================================================
local holidays2026 = {
    ["2026-01-01"] = "NEW YEAR'S DAY",
    ["2026-01-19"] = "MLK DAY",
    ["2026-02-16"] = "PRESIDENTS' DAY",
    ["2026-04-03"] = "GOOD FRIDAY",
    ["2026-05-25"] = "MEMORIAL DAY",
    ["2026-06-19"] = "JUNETEENTH",
    ["2026-07-03"] = "INDEPENDENCE DAY (OBS)",
    ["2026-09-07"] = "LABOR DAY",
    ["2026-11-26"] = "THANKSGIVING",
    ["2026-12-25"] = "CHRISTMAS DAY"
}

-- Days closing early at 13:00 / 提早於 13:00 收盤的日期
local earlyClose2026 = {
    ["2026-11-27"] = "EARLY CLOSE (13:00)", -- Black Friday
    ["2026-12-24"] = "EARLY CLOSE (13:00)"  -- Christmas Eve
}

local json
local CurrentEvents = {}
local lastShowNewsState = -1 -- Track UI state change / 追蹤 UI 狀態變更

-- News keywords for filtering / 用於過濾的新聞關鍵字
local targetKeywords = { "GDP", "PPI", "CPI", "FOMC", "Unemployment" }
local upcomingNewsCD = ""
local upcomingNewsTitle = ""
local upcomingNewsDiff = 0  
local offset = -5 -- Default NY offset / 預設紐約偏移量

-- ============================================================================
-- INITIALIZE: Load JSON Library & Cache / 初始化：載入 JSON 函式庫與快取
-- ============================================================================
function Initialize()
    local jsonPath = SKIN:GetVariable('@') .. 'json.lua'
    local f, err = loadfile(jsonPath)
    
    if f then
        json = f() -- Execute JSON script / 執行 JSON 腳本
        print("JSON Library Loaded Successfully via loadfile")
    else
        print("JSON Load Error: " .. tostring(err))
    end

    local thisMonday = GetThisMonday()
    local filteredPath = SKIN:GetVariable('CURRENTPATH') .."News\\".. thisMonday .. ".json"
    
    local f = io.open(filteredPath, "r")
    if f then
        local content = f:read("*all")
        f:close()
        -- Validity check for content / 檢查內容長度是否有效
        if content and #content > 0 then
            local success, decoded = pcall(json.decode, content)
            if success then
                CurrentEvents = decoded
                print(">>> [Init] Loaded cached news for " .. thisMonday)
            else
                print(">>> [Init] JSON format error, re-fetching...")
                SKIN:Bang('!EnableMeasure', 'MeasureJSONRaw')
                SKIN:Bang('!CommandMeasure', 'MeasureJSONRaw', 'Update')
            end
        else
            print(">>> [Init] Cache file is empty, fetching...")
            SKIN:Bang('!EnableMeasure', 'MeasureJSONRaw')
            SKIN:Bang('!CommandMeasure', 'MeasureJSONRaw', 'Update')
        end
    else
        -- Check local raw file before fetching / 抓取前先檢查本地原始檔
        local rawNewsPath = SKIN:GetVariable('CURRENTPATH') .."News\\".. thisMonday .. "-raw.json"
        local rawFile = io.open(rawNewsPath, "r")
        if rawFile then
            local rawJsonStr = rawFile:read("*all")
            rawFile:close()
            CurrentEvents = FilterNewsAndSave(rawJsonStr)
            print(">>> [Init] Found local raw.json, filtered and loaded.")
        else
            SKIN:Bang('!EnableMeasure', 'MeasureJSONRaw') 
            SKIN:Bang('!CommandMeasure', 'MeasureJSONRaw', 'Update')
        end
    end
end

-- ============================================================================
-- PROCESS NEWS: Calculate Countdown / 新聞處理：計算新聞倒數
-- ============================================================================
function ProcessNews(ny_reference_ts)
    if not json then return end

    local displayList = {}
    local maxDisplay = 4
    local isBlinking = 0  
    local countdownText = ""

    upcomingNewsCD = ""    
    upcomingNewsTitle = ""
    upcomingNewsDiff = 0    

    if CurrentEvents and #CurrentEvents > 0 then
        for i, event in ipairs(CurrentEvents) do
            -- Compare event NY time with simulated NY time / 比較新聞時間與模擬時間
            local diff = event.ny_timestamp - ny_reference_ts

            if diff > 0 then
                local dayStr = os.date("%a", event.ny_timestamp)
                local shortTime = event.ny_time:sub(-5)
                
                -- Detect news within 15 mins / 偵測 15 分鐘內的新聞
                if upcomingNewsCD == "" and diff <= 900 then
                    upcomingNewsDiff = diff 
                    local m = math.floor(diff / 60)
                    local s = diff % 60
                    upcomingNewsCD = string.format("%02d:%02d", m, s)
                    countdownText = upcomingNewsCD 
                    upcomingNewsTitle = event.title
                    
                    -- Flash BG in last 10s / 最後 10 秒背景閃爍
                    if diff <= 10 then isBlinking = 1 end
                end

                local eventString = string.format("[%s %s] %s", dayStr, shortTime, event.title)
                table.insert(displayList, eventString)
                if #displayList >= maxDisplay then break end
            end
        end
    end

    -- Update Skin Variables / 更新皮膚變數
    local finalDisplay = (#displayList > 0) and table.concat(displayList, "\n") or "No More News"
    SKIN:Bang('!SetVariable', 'EventDisplay', finalDisplay)
    SKIN:Bang('!SetVariable', 'IsNewsFlash', isBlinking)
   
    return "OK"
end

-- Notification setter function / 通知訊息設定函數
function SetNotification(msg, seconds, color)
    notifyMessage = msg
    notifyTimer = os.time() + seconds
    notifyColor = color or OUT_OF_SESSION_FONT_COLOR 
end

-- ============================================================================
-- UPDATE: Main Script Loop / 更新：主腳本循環
-- ============================================================================
function Update()

    -- 1. Sync Time / 同步時間 (UTC vs NY Simulation)
    local now_utc = GetCurrentTime(false)
    local ny_now_ts = GetCurrentTime(true)

    -- Visual Clock Override (Handling UI) / 時鐘顯示接管 (處理 UI)
    if DEBUG_MODE then
        -- Format simulated time string / 格式化模擬時間字串
        local fake_time_str = os.date("!%H:%M:%S", ny_now_ts + (os.difftime(os.time(), os.time(os.date("!*t")))))
        local d_ny = os.date("*t", ny_now_ts)
        fake_time_str = string.format("%02d:%02d:%02d", d_ny.hour, d_ny.min, d_ny.sec)

        -- Decouple Meter from Measure / 讓 Meter 脫離 Measure 連結
        SKIN:Bang('!SetOption', 'MeterNYClock', 'MeasureName', '') 
        SKIN:Bang('!SetOption', 'MeterNYClock', 'Text', fake_time_str)
        SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a %H:%M:%S", ny_now_ts))
    else
        -- Link back to standard Measure / 連回標準 Measure
        SKIN:Bang('!SetOption', 'MeterNYClock', 'MeasureName', 'MeasureNYTime')
        SKIN:Bang('!SetOption', 'MeterNYClock', 'Text', '%1')
        SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a", ny_now_ts))
    end

    -- Data Watchdog: Auto-retry if news data is invalid / 守護進程：資料失效自動重試
    if not DEBUG_MODE and not CheckDataValidity() then
        if os.time() >= nextRetryTime then
            print(">>> [Data Watchdog] No future news found. Retrying fetch...")
            SKIN:Bang('!EnableMeasure', 'MeasureJSONRaw')
            SKIN:Bang('!CommandMeasure', 'MeasureJSONRaw', 'Update')
            nextRetryTime = os.time() + RETRY_INTERVAL
        end
    end

    -- Market State Check: Holidays & Weekends / 市場狀態檢查：節日與週末
    local d = os.date("*t", ny_now_ts)
    local wday, h = d.wday, d.hour
    local dateKey = os.date("%Y-%m-%d", ny_now_ts)

    local holidayName = holidays2026[dateKey]
    local earlyCloseName = earlyClose2026[dateKey]
    local isStrictlyClosed = (wday == 6 and h >= 17) or (wday == 7)
    local isHoliday = (holidayName ~= nil)
    local isEarlyClosePassed = (earlyCloseName and h >= 13)
    local isSunday = (wday == 1)
    local isPrepMode = isSunday or isHoliday or isEarlyClosePassed

    -- [Path 1] Market Strictly Closed / 徹底關閉路徑
    if isStrictlyClosed then
        SKIN:Bang('!SetVariable', 'Message', "MARKET CLOSED")
        SKIN:Bang('!SetVariable', 'MessageColor', OUT_OF_SESSION_FONT_COLOR)
        SKIN:Bang('!SetVariable', 'CountdownText', "")
        SKIN:Bang('!SetVariable', 'BarPercent', "0")
        SKIN:Bang('!SetVariable', 'HideMacro', "1")
        SKIN:Bang('!SetVariable', 'HideCountdown', "1")
        SKIN:Bang('!SetVariable', 'HideCountdownBar', "1")
        SKIN:Bang('!SetVariable', 'HideNewsToggleButton', "1") 
        SKIN:Bang('!HideMeterGroup', 'NewsGroup')
        SKIN:Bang('!SetVariable', 'CurrentSessionColor', OUT_OF_SESSION_COLOR)
        
        if DEBUG_MODE then SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a %H:%M:%S", ny_now_ts))
        else SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a", ny_now_ts)) end
        
        SKIN:Bang('!Redraw')
        return "OK" 
    end

    -- [Path 2] Preparation Mode (Weekend/Holiday) / 準備模式 (週末或假日)
    if isPrepMode then
        ProcessNews(ny_now_ts)
        ToggleNews(ny_now_ts, false) -- Unified Toggle logic / 統一開關邏輯

        local msg = holidayName or (isEarlyClosePassed and earlyCloseName) or "WEEKEND PREP"
        SKIN:Bang('!SetVariable', 'Message', msg)
        SKIN:Bang('!SetVariable', 'MessageColor', LIGHT_COLOR)
        SKIN:Bang('!SetVariable', 'CurrentSessionColor', OUT_OF_SESSION_COLOR)
        SKIN:Bang('!SetVariable', 'HideMacro', "1")
        SKIN:Bang('!SetVariable', 'HideCountdown', "1")
        SKIN:Bang('!SetVariable', 'HideCountdownBar', "1")
        SKIN:Bang('!UpdateMeter', 'MeterNews')
        SKIN:Bang('!UpdateMeter', 'MeterNewsBG')
        
        if DEBUG_MODE then SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a %H:%M:%S", ny_now_ts))
        else SKIN:Bang('!SetVariable', 'CurrentDate', os.date("%b %d %a", ny_now_ts)) end

        SKIN:Bang('!Redraw')
        return "OK"
    end

    -- [Path 3] Normal Trading Session / 正常交易時段路徑
    ProcessNews(ny_now_ts)
    
    local countdown_sec = 900
    local currentTime = os.time()
    local displayTitle = ""
    local displayColor = ""
    local notify_duration = tonumber(SKIN:GetVariable('NOTIFY_DURATION')) or 5

    -- Parsing Time for Logic / 解析用於判定的時間
    local d_ny = os.date("*t", ny_now_ts)
    local h, m, s = d_ny.hour, d_ny.min, d_ny.sec
    local hhmm = h * 100 + m
    local total_now_seconds = (h * 3600) + (m * 60) + s

    -- Trading Session Table / 交易時段資料表
    local sessions = {
        {start=0300, stop=0400, name="SILVER BULLET",    color="0,80,150,100", fColor="255,255,255,150"},
        {start=1000, stop=1100, name="SILVER BULLET",    color="0,80,150,100", fColor="255,255,255,150"},
        {start=1400, stop=1500, name="SILVER BULLET",    color="0,80,150,100", fColor="255,255,255,150"},
        {start=2000, stop=2400, name="ASIA SESSION",     color="255,215,0,30",  fColor="255,255,255,150"},
        {start=0200, stop=0500, name="LONDON SESSION",   color="0,255,255,20",  fColor="255,255,255,150"},
        {start=0930, stop=1100, name="NY AM SESSION",    color="238,118,104,15",  fColor="255,255,255,150"},
        {start=1330, stop=1600, name="NY PM SESSION",    color="238,118,104,15", fColor="255,255,255,150"}
    }

    local resName, resColor, resFont = OUT_OF_SESSION, OUT_OF_SESSION_COLOR, OUT_OF_SESSION_FONT_COLOR
    local barPercent, barColor = 0, "0,0,0,0"

    -- Find Current Active Sessions / 搜尋當前活躍時段
    local active_sessions = {}
    for _, sess in ipairs(sessions) do
        local is_active = false
        local start_sec = (math.floor(sess.start / 100) * 3600) + (sess.start % 100 * 60)
        local stop_sec = (math.floor(sess.stop / 100) * 3600) + (sess.stop % 100 * 60)
        
        if sess.start < sess.stop then
            is_active = (hhmm >= sess.start and hhmm < sess.stop)
            duration = stop_sec - start_sec
        else
            is_active = (hhmm >= sess.start or hhmm < sess.stop)
            duration = (86400 - start_sec) + stop_sec
        end

        if is_active then
            sess.currentDuration = duration 
            table.insert(active_sessions, sess)
        end
    end

    -- Sorting Sessions by Duration / 依時長排序時段 (長者優先)
    table.sort(active_sessions, function(a, b) return a.currentDuration > b.currentDuration end)

    local mainSess = active_sessions[1] 
    local subSess = active_sessions[#active_sessions] 
    if mainSess == subSess then subSess = nil end 

    -- UI Result Assignment / UI 顯示結果賦值
    if mainSess and subSess then
        resName, resColor, resFont = mainSess.name .. " : " .. subSess.name, mainSess.color, mainSess.fColor
        subColor = subSess.color
    elseif mainSess then
        resName, resColor, resFont = mainSess.name, mainSess.color, mainSess.fColor
        subColor = "0,0,0,0"
    else
        resName, resColor, resFont = OUT_OF_SESSION, OUT_OF_SESSION_COLOR, OUT_OF_SESSION_FONT_COLOR
        subColor = "0,0,0,0"
    end

    -- Session Countdown Logic / 時段倒數邏輯
    local min_diff, countdown_text = 999999, ""
    local active_bar_percent, active_bar_color = 0, "0,0,0,0"

    for _, sess in ipairs(sessions) do
        local total_start_seconds = (math.floor(sess.start / 100) * 3600) + (sess.start % 100 * 60)
        local diff = total_start_seconds - total_now_seconds
        if diff <= 0 then diff = diff + 86400 end

        -- Skip if already active / 若已在時段內則跳過
        local is_already_active = false
        for _, active in ipairs(active_sessions) do
            if active.name == sess.name and active.start == sess.start then is_already_active = true break end
        end

        if not is_already_active and diff < min_diff then
            min_diff = diff
            if diff <= countdown_sec then
                if diff == 900 then SetNotification(sess.name .. " COMING SOON", notify_duration) end
                active_bar_percent, active_bar_color = diff / countdown_sec, sess.color
                countdown_text = string.format("%02d:%02d", math.floor(diff / 60), diff % 60)
            end
        end
    end

    barPercent, barColor = active_bar_percent, active_bar_color

    -- Macro Animation (0-15 and 45-60 mins) / Macro 動畫 (每小時前後 15 分鐘)
    local macroLeft, macroRight = 0, 0
    local total_m_sec = (m * 60) + s
    local mColor, hideMacro = "0,0,0,0", 1

    if m < 15 then macroRight = 1 - (total_m_sec / 900)
    elseif m >= 45 then macroLeft = 1 - ((total_m_sec - 2700) / 900) end

    SKIN:Bang('!SetVariable', 'MacroLeft', macroLeft)
    SKIN:Bang('!SetVariable', 'MacroRight', macroRight)
    
    if (m < 15 or m >= 45) then
        mColor, hideMacro = MACRO_COLOR, 0 
        if not lastMacroState then SetNotification("IN MACRO...", notify_duration) end
    end
    lastMacroState = (m < 15 or m >= 45)

    -- Final UI Priority Selection / 最終 UI 優先級選擇
    local finalMessage, finalCountdown = resName, countdown_text
    local finalMsgColor, finalBarColor = resFont, barColor
    local finalBarPercent, finalCountdownColor = barPercent, COUNTDOWN_COLOR

    if notifyTimer > 0 and currentTime < notifyTimer then
        finalMessage, finalMsgColor = notifyMessage, notifyColor
    elseif upcomingNewsCD ~= "" then
        finalMessage, finalCountdown = "NEWS: " .. upcomingNewsTitle, upcomingNewsCD
        finalMsgColor, finalBarColor, finalCountdownColor = WHITE_COLOR, ALERT_COLOR, WHITE_COLOR
        finalBarPercent = math.max(0, math.min(1, upcomingNewsDiff / 900))
    end

    -- Force hide Macro if user set SHOW_MACRO_BAR to 0 / 強制隱藏 Macro Bar (若使用者設定關閉)
    if ((hideMacro == 0) and (SKIN:GetVariable('SHOW_MACRO_BAR') == "0")) then hideMacro = 1 end

    -- Update Rainmeter Variables / 更新 Rainmeter 全域變數
    local hideCD = ((finalCountdown == "") or (SKIN:GetVariable('SHOW_COUNTDOWN') == "0")) and 1 or 0
    local hideCD_bar = ((finalCountdown == "") or (SKIN:GetVariable('SHOW_COUNTDOWN_BAR') == "0")) and 1 or 0
    SKIN:Bang('!SetVariable', 'HideCountdown', hideCD)
    SKIN:Bang('!SetVariable', 'HideCountdownBar', hideCD_bar)
    SKIN:Bang('!SetVariable', 'Message', finalMessage)
    SKIN:Bang('!SetVariable', 'MessageColor', finalMsgColor)
    SKIN:Bang('!SetVariable', 'CountdownText', finalCountdown)
    SKIN:Bang('!SetVariable', 'CountdownColor', finalCountdownColor)
    SKIN:Bang('!SetVariable', 'NextSessionColor', ForceOpaque(finalBarColor, 200)) 
    SKIN:Bang('!SetVariable', 'MacroColor', mColor)
    SKIN:Bang('!SetVariable', 'HideMacro', hideMacro)
    SKIN:Bang('!SetVariable', 'BarPercent', finalBarPercent)
    SKIN:Bang('!SetVariable', 'CurrentSessionColor', resColor)         
    SKIN:Bang('!SetVariable', 'SubSessionColor', ForceOpaque(subColor, 150))             

    -- News UI Toggle Monitoring / 新聞 UI 開關監控
    ToggleNews(ny_now_ts, false)
    
    SKIN:Bang('!UpdateMeter', 'MeterNYClock') 
    SKIN:Bang('!Redraw')

    return "OK"
end

-- ============================================================================
-- HELPER FUNCTIONS / 輔助函數
-- ============================================================================

-- Adjust Color Alpha / 調整顏色透明度
function ForceOpaque(colorStr, alpha)
    if not colorStr or colorStr == "0,0,0,0" or colorStr == "" then return "0,0,0,0" end
    local r, g, b = colorStr:match("(%d+),(%d+),(%d+)")
    if r and g and b then return r .. "," .. g .. "," .. b .. "," .. (alpha or "255") end
    return colorStr
end

-- Download Callback Logic / 下載完成回呼邏輯
function OnDownloadComplete()
    local measureObj = SKIN:GetMeasure('MeasureJSONRaw')
    local rawJsonStr = measureObj:GetStringValue()
    if rawJsonStr == "" then return end

    local tempData = FilterNews(rawJsonStr)
    local ny_now = GetCurrentTime(true)
    local isDataNew = false
    for _, ev in ipairs(tempData) do
        if ev.ny_timestamp > ny_now then isDataNew = true break end
    end

    if isDataNew then
        local thisMonday = GetThisMonday()
        local resPath = SKIN:GetVariable('CURRENTPATH') .."News\\"
        local rawFile = io.open(resPath .. thisMonday .. "-raw.json", "w")
        if rawFile then rawFile:write(rawJsonStr) rawFile:close() end
        CurrentEvents = FilterNewsAndSave(rawJsonStr)
        CleanupCache(resPath)
        SKIN:Bang('!DisableMeasure', 'MeasureJSONRaw')
    end
end

-- Clear Cache after 31 days / 清理 31 天後的快取
function CleanupCache(path)
    local oneYearAgoTime = os.time() - (365 * 86400)
    local d = os.date("*t", oneYearAgoTime)
    local diff = (d.wday == 1) and 6 or (d.wday - 2)
    local targetDate = os.date("%Y-%m-%d", oneYearAgoTime - (diff * 86400))
    local files = { targetDate .. ".json", targetDate .. "-raw.json" }
    for _, fileName in ipairs(files) do os.remove(path .. fileName) end
end

-- Find this week's Monday (NY base) / 找出本週週一日期 (以紐約為準)
function GetThisMonday()
    local now = GetCurrentTime(false)
    local d = os.date("*t", now)
    local diff = (d.wday == 1) and 1 or (2 - d.wday)
    local targetTime = now + (diff * 86400)
    return os.date("%Y-%m-%d", targetTime)
end

-- Filter News JSON data / 過濾新聞 JSON 資料
function FilterNews(rawData)
    local data = json.decode(rawData)
    local filtered = {}
    if not data then return filtered end
    for _, event in ipairs(data) do
        if event.country == "USD" and event.impact == "High" then
            local year, month, day, hr, min, sc = event.date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
            local ny_date_string = string.format("%s-%s-%s %s:%s", year, month, day, hr, min)
            local ev_ny_ts = os.time({year=year, month=month, day=day, hour=hr, min=min, sec=sc})
            table.insert(filtered, {
                title = event.title, country = event.country, impact = event.impact,
                ny_time = ny_date_string, ny_timestamp = ev_ny_ts
            })
        end
    end
    return filtered
end

-- Save filtered results / 儲存過濾後的結果
function FilterNewsAndSave(rawStr)
    local filteredTable = FilterNews(rawStr) 
    local thisMonday = GetThisMonday()
    local resPath = SKIN:GetVariable('CURRENTPATH') .."News\\"
    local filteredFile = io.open(resPath .. thisMonday .. ".json", "w")
    if filteredFile then filteredFile:write(json.encode(filteredTable)) filteredFile:close() end
    return filteredTable
end

-- MASTER TIME: DST & Simulation Engine / 主時間引擎：處理夏令時與模擬
function GetCurrentTime(applyOffset)
    local base_utc
    local local_now = os.time()
    local utc_now = os.time(os.date("!*t"))
    local local_to_utc_diff = os.difftime(local_now, utc_now)
    
    -- Fail-safe for empty debug string / 空字串安全回退機制
    local is_debug_valid = DEBUG_MODE and (DEBUG_NY_TIME_STR ~= nil) and (string.len(DEBUG_NY_TIME_STR) > 10)
    
    if is_debug_valid then
        local y, m, d, h, min, s = DEBUG_NY_TIME_STR:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if not y then return os.time() end
        local elapsed = math.floor(os.clock())
        -- Clean simulated timestamp / 產生乾淨的模擬時間戳記
        local fake_ny_ts = os.time({year=y, month=m, day=d, hour=h, min=min, sec=s, isdst=false}) + elapsed
        if applyOffset then return fake_ny_ts end
        base_utc = fake_ny_ts + (5 * 3600)
    else
        base_utc = os.time(os.date("!*t"))
    end

    -- Automatic DST Rule Calculation / 自動夏令時法則計算
    local nowT = os.date("!*t", base_utc)
    local year = nowT.year
    local dst_start = os.time({year=year, month=3, day=14 - (os.date("*t", os.time({year=year, month=3, day=1})).wday - 1), hour=7})
    local dst_end = os.time({year=year, month=11, day=7 - (os.date("*t", os.time({year=year, month=11, day=1})).wday - 1), hour=6})
    offset = (base_utc >= dst_start and base_utc < dst_end) and -4 or -5
    SKIN:Bang('!SetVariable', 'NYOffset', offset)

    if not applyOffset then 
        if is_debug_valid then
            local y, m, d, h, min, s = DEBUG_NY_TIME_STR:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
            return os.time({year=y, month=m, day=d, hour=h, min=min, sec=s}) + math.floor(os.clock()) - (offset * 3600)
        end
        return base_utc 
    end
    return base_utc + (offset * 3600)
end

-- Watchdog: Check if future news exists / 監控：檢查是否還有未來新聞
function CheckDataValidity()
    local ny_now = GetCurrentTime(true) 
    if not CurrentEvents or #CurrentEvents == 0 then return false end
    for _, ev in ipairs(CurrentEvents) do
        if ev.ny_timestamp > ny_now then return true end
    end
    return false
end

-- News Panel Expand/Collapse Control / 新聞面板展開與收合控制
function ToggleNews(ny_now_ts, redraw)
    local showNewsVar = tonumber(SKIN:GetVariable('SHOW_NEWS')) or 0
    local hasNews = false
    
    if CurrentEvents and #CurrentEvents > 0 then
        for _, ev in ipairs(CurrentEvents) do
            if ev.ny_timestamp > ny_now_ts then hasNews = true break end
        end
    end
    
    if hasNews then
        SKIN:Bang('!SetVariable', 'HideNewsToggleButton', '0')
        -- State monitoring to avoid Bang conflict / 狀態監控防止重複發送指令
        if showNewsVar ~= lastShowNewsState then
            if showNewsVar == 1 then SKIN:Bang('!ShowMeterGroup', 'NewsGroup')
            else SKIN:Bang('!HideMeterGroup', 'NewsGroup') end
            lastShowNewsState = showNewsVar
        end
    else
        SKIN:Bang('!SetVariable', 'HideNewsToggleButton', '1')
        SKIN:Bang('!HideMeterGroup', 'NewsGroup')
        lastShowNewsState = 0
    end
end