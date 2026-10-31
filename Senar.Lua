-- SENAR HUB | Farm Only
-- UI: Hitam / Putih, loading frame, efek cahaya bergerak, logo via Asset ID
-- Alur farm: CP1 (Safe Zone) -> CP2 (Zone) pakai Tween -> tunggu -> spam TP -> balik CP1 -> ulang

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

-- ================= CONFIG =================
local TITLE         = "SENAR HUB"
local SUBTITLE      = "Farm Only"
local TOGGLE_LABEL  = "Auto Farm"
local LOGO_ASSET_ID = 103508016316339

local CP1 = Vector3.new(-49.7, 4.0, -129.4)   -- Safe Zone
local CP2 = Vector3.new(-47.0, 12.3, 4319.9)  -- Zone

local TWEEN_SPEED  = 500   -- studs per detik
local WAIT_AT_CP2  = 9     -- detik tunggu di CP2
local SPAM_COUNT   = 8     -- jumlah spam TP
local SPAM_DELAY   = 0.15  -- jeda antar spam TP (detik)
local HEIGHT_OFFSET = 10    -- naikkan kalau karakter nyangkut di tanah

-- ================= UTIL =================
local function randName(n)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local t = table.create(n)
    for i = 1, n do
        local k = math.random(1, #chars)
        t[i] = chars:sub(k, k)
    end
    return table.concat(t)
end

local env = (getgenv and getgenv()) or _G
if env.__SenarCleanup then pcall(env.__SenarCleanup) end

-- ================= API PUBLIK =================
local UI = {
    onToggle = function(state) end,
    setStatus = function(text) end,
    setProgress = function(fraction) end,
    setStats = function(text) end,
    isEnabled = function() return false end,
    destroy = function() end,
}
env.SenarUI = UI

local enabled = false

-- ================= UI =================
local C = {
    BG    = Color3.fromRGB(8, 8, 8),
    PANEL = Color3.fromRGB(20, 20, 20),
    HOVER = Color3.fromRGB(36, 36, 36),
    BLUE  = Color3.fromRGB(72, 72, 72),    -- aksen utama (abu gelap)
    BLUE2 = Color3.fromRGB(170, 170, 170), -- aksen terang
    DEEP  = Color3.fromRGB(28, 28, 28),
    WHITE = Color3.fromRGB(255, 255, 255),
    GRAY  = Color3.fromRGB(140, 140, 140),
    HI    = Color3.fromRGB(235, 235, 235),
}

local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function corner(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end

local tweens = {}
local sweepGradients = {}

local function sweepSeq(base, hi)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, base),
        ColorSequenceKeypoint.new(0.38, base),
        ColorSequenceKeypoint.new(0.50, hi),
        ColorSequenceKeypoint.new(0.62, base),
        ColorSequenceKeypoint.new(1, base),
    })
end

local function addSweep(inst, base, hi)
    local g = make("UIGradient", {
        Color = sweepSeq(base, hi), Offset = Vector2.new(-1, 0),
    }, inst)
    sweepGradients[g] = true
    return g
end

local function shine(label, base)
    label.TextColor3 = C.WHITE
    return addSweep(label, base, C.WHITE)
end

local function glowFill(frame, base)
    frame.BackgroundColor3 = C.WHITE
    return addSweep(frame, base or C.BLUE, C.HI)
end

local function glowStroke(obj, th)
    local s = make("UIStroke", {
        Color = C.WHITE, Thickness = th or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
    addSweep(s, C.BLUE, C.WHITE)
    return s
end

local function applyLogo(holder)
    if not LOGO_ASSET_ID or tonumber(LOGO_ASSET_ID) == nil or tonumber(LOGO_ASSET_ID) == 0 then return end
    local img = make("ImageLabel", {
        Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3),
        BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
        Image = "rbxassetid://" .. tostring(LOGO_ASSET_ID), Visible = false,
    }, holder)
    task.spawn(function()
        pcall(function()
            ContentProvider:PreloadAsync({ img }, function(_, status)
                if status == Enum.AssetFetchStatus.Success and img.Parent then
                    img.Visible = true
                    holder.Text = ""
                end
            end)
        end)
    end)
end

local function makeLogo(parent, size, pos, textSize, radius)
    local bg = make("Frame", {
        Size = UDim2.fromOffset(size, size), Position = pos, BorderSizePixel = 0,
    }, parent)
    corner(bg, radius)
    glowFill(bg, C.BLUE)
    local lbl = make("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "S",
        TextColor3 = C.WHITE, Font = Enum.Font.GothamBlack, TextSize = textSize,
    }, bg)
    applyLogo(lbl)
    return bg, lbl
end

local function coreGuiOk()
    local okc, core = pcall(function() return game:GetService("CoreGui") end)
    if not okc or not core then return nil end
    local test = pcall(function()
        local f = Instance.new("Folder")
        f.Parent = core
        f:Destroy()
    end)
    return test and core or nil
end

local function mountGui(g)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(g)
        elseif protectgui then
            protectgui(g)
        elseif protect_gui then
            protect_gui(g)
        end
    end)
    local target = coreGuiOk()
    if not target then
        local okh, ui = pcall(function() return gethui and gethui() end)
        if okh and ui then target = ui end
    end
    if not target then target = LocalPlayer:WaitForChild("PlayerGui") end
    local okp = pcall(function() g.Parent = target end)
    if not okp or not g.Parent then
        g.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local gui = make("ScreenGui", {
    Name = randName(14), ResetOnSpawn = false, DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
mountGui(gui)

local farmToken = 0
local currentTween = nil

local myCleanup = function()
    farmToken += 1
    if currentTween then pcall(function() currentTween:Cancel() end) end
    if gui and gui.Parent then gui:Destroy() end
end
env.__SenarCleanup = myCleanup
UI.destroy = myCleanup

-- driver kilau
local sweepVal = make("NumberValue", { Value = -1 }, gui)
local sweepConn = sweepVal.Changed:Connect(function(v)
    local off = Vector2.new(v, 0)
    for g in pairs(sweepGradients) do
        if g.Parent then g.Offset = off else sweepGradients[g] = nil end
    end
end)
do
    local tw = TweenService:Create(sweepVal,
        TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0),
        { Value = 1 })
    tw:Play()
    table.insert(tweens, tw)
end

local W, HEADER_H, FULL_H = 240, 46, 176

-- ---------- Main window ----------
local main = make("Frame", {
    Name = "Main", Size = UDim2.fromOffset(W, FULL_H),
    Position = UDim2.new(0.5, -W / 2, 0.5, -FULL_H / 2),
    BackgroundColor3 = C.BG, BorderSizePixel = 0, Visible = false,
}, gui)
corner(main, 10)
local scale = make("UIScale", { Scale = 1 }, main)

local function spinStroke(st)
    local sg = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C.DEEP),
            ColorSequenceKeypoint.new(0.35, C.BLUE),
            ColorSequenceKeypoint.new(0.5, C.WHITE),
            ColorSequenceKeypoint.new(0.65, C.BLUE),
            ColorSequenceKeypoint.new(1, C.DEEP),
        }),
    }, st)
    local tw = TweenService:Create(sg,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 0),
        { Rotation = 360 })
    tw:Play()
    table.insert(tweens, tw)
end
spinStroke(make("UIStroke", {
    Color = C.WHITE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, main))

-- header
local header = make("Frame", {
    Name = "Header", Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundTransparency = 1,
}, main)

makeLogo(header, 30, UDim2.fromOffset(10, 8), 18, 8)

local title = make("TextLabel", {
    Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
    Position = UDim2.fromOffset(50, 6), BackgroundTransparency = 1,
    Text = TITLE, Font = Enum.Font.GothamBold, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
shine(title, C.BLUE2)

local subtitle = make("TextLabel", {
    Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
    Position = UDim2.fromOffset(50, 25), BackgroundTransparency = 1,
    Text = SUBTITLE, Font = Enum.Font.Gotham, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
shine(subtitle, C.GRAY)

local minBtn = make("TextButton", {
    Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -38, 0, 9),
    BackgroundColor3 = C.PANEL, Text = "-", TextColor3 = C.WHITE,
    Font = Enum.Font.GothamBold, TextSize = 18, AutoButtonColor = false, ZIndex = 6,
}, header)
corner(minBtn, 8)
glowStroke(minBtn, 1)

local dragArea = make("Frame", {
    Size = UDim2.new(1, -48, 1, 0), BackgroundTransparency = 1, Active = true, ZIndex = 5,
}, header)

local line = make("Frame", {
    Size = UDim2.new(1, -20, 0, 1), Position = UDim2.fromOffset(10, HEADER_H),
    BorderSizePixel = 0,
}, main)
line.BackgroundColor3 = C.WHITE
addSweep(line, C.DEEP, C.BLUE2)

-- ---------- Body ----------
local body = make("Frame", {
    Name = "Body", Size = UDim2.new(1, 0, 1, -(HEADER_H + 1)),
    Position = UDim2.fromOffset(0, HEADER_H + 1), BackgroundTransparency = 1,
}, main)

local toggleBtn = make("TextButton", {
    Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 10),
    BackgroundColor3 = C.PANEL, Text = "", AutoButtonColor = false,
}, body)
corner(toggleBtn, 8)
glowStroke(toggleBtn, 1)

local toggleFill = make("Frame", {
    Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Visible = false, ZIndex = 1,
}, toggleBtn)
corner(toggleFill, 8)
glowFill(toggleFill, C.BLUE)

local toggleText = make("TextLabel", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = TOGGLE_LABEL .. " : OFF",
    TextColor3 = C.WHITE, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 2,
}, toggleBtn)

local progTrack = make("Frame", {
    Size = UDim2.new(1, -20, 0, 4), Position = UDim2.fromOffset(10, 54),
    BackgroundColor3 = C.PANEL, BorderSizePixel = 0,
}, body)
corner(progTrack, 2)
local progFill = make("Frame", {
    Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0,
}, progTrack)
corner(progFill, 2)
glowFill(progFill, C.BLUE)

local statusDot = make("Frame", {
    Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(12, 71),
    BackgroundColor3 = C.GRAY, BorderSizePixel = 0,
}, body)
corner(statusDot, 4)

local statusLbl = make("TextLabel", {
    Size = UDim2.new(1, -36, 0, 30), Position = UDim2.fromOffset(26, 66),
    BackgroundTransparency = 1, Text = "Status: Idle", TextColor3 = C.GRAY,
    Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
}, body)

local statsLbl = make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 104),
    BackgroundTransparency = 1, Text = "Putaran: 0",
    Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, body)
shine(statsLbl, C.BLUE2)

UI.setStatus = function(t)
    if statusLbl and statusLbl.Parent then
        statusLbl.Text = "Status: " .. tostring(t)
        statusLbl.TextColor3 = enabled and C.WHITE or C.GRAY
        statusDot.BackgroundColor3 = enabled and C.BLUE2 or C.GRAY
    end
end

UI.setProgress = function(fraction)
    if progFill and progFill.Parent then
        progFill.Size = UDim2.new(math.clamp(tonumber(fraction) or 0, 0, 1), 0, 1, 0)
    end
end

UI.setStats = function(t)
    if statsLbl and statsLbl.Parent then
        statsLbl.Text = tostring(t)
    end
end

UI.isEnabled = function() return enabled end

-- ---------- Toggle ----------
local function refreshToggle()
    toggleText.Text = TOGGLE_LABEL .. (enabled and " : ON" or " : OFF")
    toggleFill.Visible = enabled
    toggleBtn.BackgroundColor3 = C.PANEL
end
toggleBtn.MouseEnter:Connect(function()
    if not enabled then toggleBtn.BackgroundColor3 = C.HOVER end
end)
toggleBtn.MouseLeave:Connect(function() toggleBtn.BackgroundColor3 = C.PANEL end)

toggleBtn.Activated:Connect(function()
    enabled = not enabled
    refreshToggle()
    UI.setStatus(enabled and "Aktif" or "Idle")
    local okc, err = pcall(UI.onToggle, enabled)
    if not okc then warn("[Senar Hub] onToggle: " .. tostring(err)) end
end)

-- ---------- Minimize / restore ----------
local minimized = false
minBtn.MouseEnter:Connect(function() minBtn.BackgroundColor3 = C.HOVER end)
minBtn.MouseLeave:Connect(function() minBtn.BackgroundColor3 = C.PANEL end)
minBtn.Activated:Connect(function()
    minimized = not minimized
    if minimized then
        body.Visible = false
        line.Visible = false
        minBtn.Text = "+"
        TweenService:Create(main, TweenInfo.new(0.2), { Size = UDim2.fromOffset(W, HEADER_H) }):Play()
    else
        minBtn.Text = "-"
        TweenService:Create(main, TweenInfo.new(0.2), { Size = UDim2.fromOffset(W, FULL_H) }):Play()
        task.delay(0.2, function()
            if not minimized and body.Parent then
                body.Visible = true
                line.Visible = true
            end
        end)
    end
end)

-- ---------- Drag (mouse + touch) ----------
local uiConns = {}
do
    local dragging, dragStart, startPos
    dragArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
        end
    end)
    table.insert(uiConns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    table.insert(uiConns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

gui.Destroying:Connect(function()
    if env.__SenarCleanup == myCleanup then env.__SenarCleanup = nil end
    if env.SenarUI == UI then env.SenarUI = nil end
    sweepConn:Disconnect()
    table.clear(sweepGradients)
    for _, c in ipairs(uiConns) do c:Disconnect() end
    for _, t in ipairs(tweens) do pcall(function() t:Cancel() end) end
end)

-- ================= LOGIKA AUTO FARM =================
local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function target(pos)
    return pos + Vector3.new(0, HEIGHT_OFFSET, 0)
end

-- Tween ke posisi dengan kecepatan TWEEN_SPEED (studs/detik)
-- return true kalau sampai, false kalau dibatalkan / karakter tidak ada
local function tweenTo(pos, token)
    local root = getRoot()
    if not root then return false end

    local goal = target(pos)
    local dist = (root.Position - goal).Magnitude
    local duration = math.max(dist / TWEEN_SPEED, 0.05)

    local tw = TweenService:Create(root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(goal) })
    currentTween = tw
    tw:Play()

    local startT = os.clock()
    while tw.PlaybackState == Enum.PlaybackState.Playing do
        if farmToken ~= token then
            tw:Cancel()
            return false
        end
        root.AssemblyLinearVelocity = Vector3.zero
        UI.setProgress((os.clock() - startT) / duration)
        task.wait()
    end

    currentTween = nil
    if farmToken ~= token then return false end
    UI.setProgress(1)
    return getRoot() ~= nil
end

-- Tunggu dengan hitung mundur; berhenti kalau farm dimatikan
local function waitFor(seconds, token, label)
    local untilT = os.clock() + seconds
    while os.clock() < untilT do
        if farmToken ~= token then return false end
        local left = untilT - os.clock()
        UI.setStatus(string.format("%s (%.1fs)", label, left))
        UI.setProgress(1 - left / seconds)
        task.wait(0.1)
    end
    return farmToken == token
end

local function spamTeleport(pos, count, token)
    for i = 1, count do
        if farmToken ~= token then return false end
        local root = getRoot()
        if root then
            root.CFrame = CFrame.new(target(pos))
            root.AssemblyLinearVelocity = Vector3.zero
        end
        UI.setStatus(string.format("Spam TP %d/%d", i, count))
        task.wait(SPAM_DELAY)
    end
    return farmToken == token
end

local function farmLoop(token)
    local cycles = 0
    while farmToken == token do
        -- 1) ke CP1 (Safe Zone)
        UI.setStatus("Menuju CP1 (Safe Zone)")
        if not tweenTo(CP1, token) then
            if farmToken ~= token then break end
            UI.setStatus("Menunggu karakter...")
            task.wait(1)
            continue
        end

        -- 2) ke CP2 (Zone)
        UI.setStatus("Menuju CP2 (Zone)")
        if not tweenTo(CP2, token) then
            if farmToken ~= token then break end
            task.wait(1)
            continue
        end

        -- 3) tunggu di CP2
        if not waitFor(WAIT_AT_CP2, token, "Menunggu di CP2") then break end

        -- 4) spam TP
        if not spamTeleport(CP2, SPAM_COUNT, token) then break end

        -- 5) balik ke CP1
        UI.setStatus("Kembali ke CP1 (Safe Zone)")
        if not tweenTo(CP1, token) then
            if farmToken ~= token then break end
            task.wait(1)
            continue
        end

        cycles += 1
        UI.setStats("Putaran: " .. cycles)
    end
end

UI.onToggle = function(state)
    farmToken += 1
    if currentTween then
        pcall(function() currentTween:Cancel() end)
        currentTween = nil
    end
    if state then
        task.spawn(farmLoop, farmToken)
    else
        UI.setProgress(0)
    end
end

-- ---------- Loading frame ----------
local loading = make("Frame", {
    Name = "Loading", Size = UDim2.fromOffset(250, 124),
    Position = UDim2.new(0.5, -125, 0.5, -62),
    BackgroundColor3 = C.BG, BorderSizePixel = 0,
}, gui)
corner(loading, 10)
spinStroke(make("UIStroke", {
    Color = C.WHITE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, loading))

makeLogo(loading, 38, UDim2.fromOffset(14, 14), 22, 10)

local lTitle = make("TextLabel", {
    Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
    Position = UDim2.fromOffset(62, 14), BackgroundTransparency = 1,
    Text = TITLE, Font = Enum.Font.GothamBold, TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, loading)
shine(lTitle, C.BLUE2)

local lSub = make("TextLabel", {
    Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
    Position = UDim2.fromOffset(62, 36), BackgroundTransparency = 1,
    Text = SUBTITLE, Font = Enum.Font.Gotham, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, loading)
shine(lSub, C.GRAY)

local track = make("Frame", {
    Size = UDim2.new(1, -28, 0, 8), Position = UDim2.fromOffset(14, 74),
    BackgroundColor3 = C.PANEL, BorderSizePixel = 0,
}, loading)
corner(track, 4)
local fill = make("Frame", {
    Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0,
}, track)
corner(fill, 4)
glowFill(fill, C.BLUE)

local lStatus = make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 16), Position = UDim2.fromOffset(14, 92),
    BackgroundTransparency = 1, Text = "Loading...", TextColor3 = C.GRAY,
    Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
}, loading)

task.spawn(function()
    local steps = {
        { "Memuat UI...", 0.35 },
        { "Menyiapkan farm...", 0.7 },
        { "Selesai", 1 },
    }
    for _, s in ipairs(steps) do
        if not gui.Parent then return end
        lStatus.Text = s[1]
        TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
            { Size = UDim2.new(s[2], 0, 1, 0) }):Play()
        task.wait(0.5)
    end
    task.wait(0.2)
    if not gui.Parent then return end
    loading:Destroy()
    scale.Scale = 0.9
    main.Visible = true
    TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back),
        { Scale = 1 }):Play()
end)
