OUT_OF_SESSION_COLOR="20,20,20,30"
OUT_OF_SESSION_FONT_COLOR="255,255,255,100"
MACRO_COLOR="0,80,150,180"
WHITE_COLOR="255,255,255,200"

notifyTimer = 0
notifyMessage = ""
notifyColor = WHITE_COLOR
lastMacroState = false

-- 通知觸發函數：支援訊息、秒數、顏色
function SetNotification(msg, seconds, color)
    notifyMessage = msg
    notifyTimer = os.time() + seconds
    notifyColor = color or OUT_OF_SESSION_FONT_COLOR -- 若未指定則預設白色
end

function Update()

    -- 1. 自動計算紐約夏令時 (DST)
    local now = os.date("!*t")
    local year = now.year
    local dst_start = os.time({year=year, month=3, day=14 - (os.date("*t", os.time({year=year, month=3, day=1})).wday - 1)})
    local dst_end = os.time({year=year, month=11, day=7 - (os.date("*t", os.time({year=year, month=11, day=1})).wday - 1)})
    local current_utc = os.time(now)
    local offset = (current_utc >= dst_start and current_utc < dst_end) and -4 or -5
    -- 15 mins
    local countdown_sec = 900
    local currentTime = os.time()
    local displayTitle = ""
    local displayColor = ""
    
    SKIN:Bang('!SetVariable', 'NYOffset', offset)

    local ny_time_m = SKIN:GetMeasure('MeasureNYTime')
    if not ny_time_m then return "Waiting for Measure..." end
    
    local ny_time_str = ny_time_m:GetStringValue()
    if ny_time_str == "" then return "Initializing..." end

    -- 拆解 時:分:秒
    local h, m, s = ny_time_str:match("(%d+):(%d+):(%d+)")
    h, m, s = tonumber(h), tonumber(m), tonumber(s)

    local hhmm = h * 100 + m
    local total_now_seconds = (h * 3600) + (m * 60) + s

    -- 3. Session 資料表
    local sessions = {
        {start=0300, stop=0400, name="SILVER BULLET",    color="0,80,150,180", fColor="0,0,0,255"},
        {start=1000, stop=1100, name="SILVER BULLET",    color="0,80,150,180", fColor="0,0,0,255"},
        {start=1400, stop=1500, name="SILVER BULLET",    color="0,80,150,180", fColor="0,0,0,255"},
        {start=2000, stop=2400, name="ASIA SESSION",     color="255,215,0,30",  fColor="255,255,255,200"},
        {start=0200, stop=0500, name="LONDON SESSION",   color="0,255,255,20",  fColor="255,255,255,200"},
        {start=0930, stop=1100, name="NY AM SESSION",    color="238,118,104,15",  fColor="255,255,255,200"},
        {start=1330, stop=1600, name="NY PM SESSION",    color="238,118,104,15", fColor="255,255,255,200"}
    }

    local resName, resColor, resFont = "OUT OF SESSION", OUT_OF_SESSION_COLOR, OUT_OF_SESSION_FONT_COLOR
    local barPercent = 0
    local barColor = "0,0,0,0" -- 沒倒數時設為全透明

   -- 4. 邏輯 A: 判定當前 Session (依時長自動判斷主次)
    local active_sessions = {}
    
    for _, sess in ipairs(sessions) do
        local is_active = false
        -- 考慮跨午夜的時長計算
        local duration = 0
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
            sess.currentDuration = duration -- 暫存時長用於排序
            table.insert(active_sessions, sess)
        end
    end

    -- 排序：時長長的在前
    table.sort(active_sessions, function(a, b) return a.currentDuration > b.currentDuration end)

    local mainSess = active_sessions[1] -- 最長的 (例如 London)
    local subSess = active_sessions[#active_sessions] -- 最短的 (例如 Silver Bullet)
    if mainSess == subSess then subSess = nil end -- 如果只有一個，就沒有次要

    -- 輸出結果決定
    if mainSess and subSess then
        resName = mainSess.name .. " : " .. subSess.name
        resColor = mainSess.color   -- 主背景用大盤色
        resFont = mainSess.fColor
        subColor = subSess.color    -- 給你稍後要用的邊框或副標題
    elseif mainSess then
        resName, resColor, resFont = mainSess.name, mainSess.color, mainSess.fColor
        subColor = "0,0,0,0"
    else
        resName, resColor, resFont = "OUT OF SESSION", OUT_OF_SESSION_COLOR, OUT_OF_SESSION_FONT_COLOR
        subColor = "0,0,0,0"
    end

    -- 5. 判定倒數 (包含倒數時間文字)
    local min_diff = 999999
    local active_bar_color = "0,0,0,0"
    local active_bar_percent = 0
    local countdown_text = ""

    for _, sess in ipairs(sessions) do
        local s_h = math.floor(sess.start / 100)
        local s_m = sess.start % 100
        local total_start_seconds = (s_h * 3600) + (s_m * 60)
        
        local diff = total_start_seconds - total_now_seconds
        if diff <= 0 then diff = diff + 86400 end

        -- 檢查此 Session 是否已在 active_sessions 中
        local is_already_active = false
        for _, active in ipairs(active_sessions) do
            if active.name == sess.name and active.start == sess.start then
                is_already_active = true
                break
            end
        end

        if not is_already_active and diff < min_diff then
            min_diff = diff
            if diff <= countdown_sec then
                -- 【通知邏輯 B：偵測 Session 倒數 (15分鐘整)】
                -- 假設你目前的變數名為 next_sess_name 且 diff 是倒數秒數
                if diff == 900 then 
                    -- 觸發通知：顯示 10 秒
                    SetNotification(sess.name .. " COMING SOON", 10)
                end

                active_bar_percent = diff / countdown_sec
                active_bar_color = sess.color
                
                -- 格式化倒數時間: MM:SS
                local m_left = math.floor(diff / 60)
                local s_left = diff % 60
                countdown_text = string.format("%02d:%02d", m_left, s_left)
            end
        end
    end

    -- 如果沒有倒數文字，則設為 1 (隱藏)，否則設為 0 (顯示)
    -- 邏輯：如果沒文字，或者使用者在變數裡設為隱藏，則結果為 1
    local hideCD = ((countdown_text == "") or (SKIN:GetVariable('SHOW_COUNTDOWN') == "0")) and 1 or 0
    local hideCD_bar = ((countdown_text == "") or (SKIN:GetVariable('SHOW_COUNTDOWN_BAR') == "0")) and 1 or 0
    SKIN:Bang('!SetVariable', 'HideCountdown', hideCD)
    SKIN:Bang('!SetVariable', 'HideCountdownBar', hideCD_bar)
    barPercent = active_bar_percent
    barColor = active_bar_color

    -- 5. Macro 邏輯 (前 15 分縮減，後 15 分增長)
    local macroLeft = 0   -- 後 15 分 (45-60)
    local macroRight = 0  -- 前 15 分 (00-15)
    local total_m_sec = (m * 60) + s
    local mColor = "0,0,0,0"
    local hideMacro = 1

    if m < 15 then
        -- 前 15 分鐘：由左向右縮減 (1.0 -> 0.0)
        macroRight = 1 - (total_m_sec / 900)
    elseif m >= 45 then
        -- 後 15 分鐘：由左向右縮減 (1.0 -> 0.0)
        -- 注意：這裡邏輯是計算經過了多少百分比
        macroLeft = 1 - ((total_m_sec - 2700) / 900)
    end

    SKIN:Bang('!SetVariable', 'MacroLeft', macroLeft)
    SKIN:Bang('!SetVariable', 'MacroRight', macroRight)
    
    if (m < 15 or m >= 45) then
        if m < 15 then
            -- 前 15 分鐘：由左向右縮減 (1.0 -> 0.0)
            macroRight = 1 - (total_m_sec / 900)
        elseif m >= 45 then
            -- 後 15 分鐘：由左向右縮減 (1.0 -> 0.0)
            -- 注意：這裡邏輯是計算經過了多少百分比
            macroLeft = 1 - ((total_m_sec - 2700) / 900)
        end
        mColor = MACRO_COLOR
        hideMacro = 0 
    end

    -- 【通知邏輯 A：偵測 Macro 開始】
    local is_currently_macro = (m < 15 or m >= 45)
    if is_currently_macro and not lastMacroState then
        -- 觸發通知：顯示 10 秒，顏色設為亮青色
        SetNotification("IN MACRO...", 10)
    end
    lastMacroState = is_currently_macro

    -- 【最終MESSAGE顯示判定】
    if notifyTimer > 0 and currentTime < notifyTimer then
        -- 顯示「暫時通知」狀態
        displayTitle = notifyMessage
        displayColor = notifyColor
    else
        -- 回歸「正常顯示」狀態
        displayTitle = subSess and (mainSess.name.." : "..subSess.name) or (mainSess and mainSess.name or "OUT OF SESSION")
        displayColor = OUT_OF_SESSION_FONT_COLOR -- 正常狀態的預設白色
    end

    -- 邏輯：使用者在變數裡設為隱藏Macro，都不顯示 Macro Bar
    if ((hideMacro == 0) and (SKIN:GetVariable('SHOW_MACRO_BAR') == "0")) then 
        hideMacro = 1
    end

    

    -- 6. 更新 Rainmeter
    SKIN:Bang('!SetVariable', 'Message', displayTitle)
    
    -- 使用我們處理過的 displayColor
    SKIN:Bang('!SetVariable', 'MessageColor', displayColor)

    SKIN:Bang('!SetVariable', 'MacroColor', mColor)
    SKIN:Bang('!SetVariable', 'HideMacro', hideMacro)
    SKIN:Bang('!SetVariable', 'BarPercent', active_bar_percent)
    SKIN:Bang('!SetVariable', 'NextSessionColor', ForceOpaque(active_bar_color, 200))     -- 可用於邊框或進度條
    SKIN:Bang('!SetVariable', 'CurrentSessionColor', resColor)         -- 主背景
    SKIN:Bang('!SetVariable', 'SubSessionColor', ForceOpaque(subColor, 150))             -- 重疊時的副顏色 (邊框)
    SKIN:Bang('!SetVariable', 'CountdownText', countdown_text)         -- 倒數文字

    

    
    return "OK"
    --return "NY: " .. ny_time_str .. " | Session: " .. resName
end

-- 輸入 "80,80,80,150", 輸出 "80,80,80,alpha"
function ForceOpaque(colorStr, alpha)
    if not colorStr or colorStr == "0,0,0,0" or colorStr == "" then return "0,0,0,0" end
    -- 抓取前三個數字 (R, G, B)
    local r, g, b = colorStr:match("(%d+),(%d+),(%d+)")
    if r and g and b then
        return r .. "," .. g .. "," .. b .. "," .. (alpha or "255") -- 強制設定 Alpha 為 255
    end
    return colorStr
end