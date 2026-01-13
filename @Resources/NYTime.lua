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
    
    SKIN:Bang('!SetVariable', 'NYOffset', offset)

    --[[
    -- 2. 獲取當前紐約時間並拆解分鐘 (修正當機點)
    local hhmm_str = SKIN:GetMeasure('MeasureNYTime'):GetStringValue()
    local hhmm = tonumber(hhmm_str)
    if not hhmm then return "Wait..." end

    local h = math.floor(hhmm / 100)
    local m = hhmm % 100
    local total_now_minutes = (h * 60) + m  -- 補上這個變數定義
    ]]

    -- 2. 獲取當前紐約時間 (抓取 MeasureNYTime, 格式 HH:MM:SS)
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
        {start=0300, stop=0400, name="SILVER BULLET",    color="255,180,0,200", fColor="0,0,0,255"},
        {start=1000, stop=1100, name="SILVER BULLET",    color="255,180,0,200", fColor="0,0,0,255"},
        {start=1400, stop=1500, name="SILVER BULLET",    color="255,180,0,200", fColor="0,0,0,255"},
        {start=2000, stop=0200, name="ASIA SESSION",     color="80,80,80,150",  fColor="255,255,255,200"},
        {start=0200, stop=0500, name="LONDON SESSION",   color="0,80,150,180",  fColor="255,255,255,200"},
        {start=0930, stop=1100, name="NY AM SESSION",    color="0,120,60,180",  fColor="255,255,255,200"},
        {start=1330, stop=1600, name="NY PM SESSION",    color="120,0,150,180", fColor="255,255,255,200"}
    }

    local resName, resColor, resFont = "OUT OF SESSION", "20,20,20,150", "255,255,255,100"
    local barPercent = 0
    local barColor = "0,0,0,0" -- 沒倒數時設為全透明

    -- 4. 邏輯 A: 判定當前 Session
    local in_session = false
    for _, sess in ipairs(sessions) do
        local is_active = false
        if sess.start < sess.stop then
            is_active = (hhmm >= sess.start and hhmm < sess.stop)
        else
            -- 跨午夜判定 (如 ASIA 2000-0200)
            is_active = (hhmm >= sess.start or hhmm < sess.stop)
        end

        if is_active then
            resName, resColor, resFont = sess.name, sess.color, sess.fColor
            break
        end
    end

    -- 5. 判定倒數 (邏輯 B: 距離下一個開盤 30 分鐘內)
    for _, sess in ipairs(sessions) do
        local s_h = math.floor(sess.start / 100)
        local s_m = sess.start % 100
        local total_start_seconds = (s_h * 3600) + (s_m * 60)
        
        local diff = total_start_seconds - total_now_seconds
        -- 如果 diff 是負數或 0，代表該 Session 是下一輪 (明天) 的
        if diff <= 0 then diff = diff + 86400 end

        -- 判定：距離開盤 900 秒 (15 分鐘) 內，且目前「不在」該 Session 內
        if diff > 0 and diff <= countdown_sec and resName ~= sess.name then
            -- 計算百分比 (0 到 1 漸進)
            --barPercent = (1800 - diff) / 1800
            barPercent = diff / countdown_sec
            barColor = sess.color
            break 
        end
    end

    -- 6. 更新 Rainmeter
    SKIN:Bang('!SetVariable', 'BarPercent', barPercent)
    SKIN:Bang('!SetVariable', 'NextSessionColor', barColor)
    SKIN:Bang('!SetVariable', 'CurrentSessionColor', resColor)
    SKIN:Bang('!SetVariable', 'Message', resName)
    SKIN:Bang('!SetOption', 'MeterMessage', 'FontColor', resFont)
    
    
    return "OK"
    --return "NY: " .. ny_time_str .. " | Session: " .. resName
end