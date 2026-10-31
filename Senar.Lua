-- SENAR HUB | UI merah + Farm CP (gerak paksa) + Zombie + ESP + Anti Lag
--
-- Alur Farm CP:
--   Gerak paksa cepat ke CP1 -> tunggu 9 detik -> ke CP2 (lebih cepat / Instant Steal = langsung TP)
--   -> spam TP di CP2 -> ulang (balik ke CP1 gerak paksa)
--
-- Hook:
--   local UI = getgenv().SenarUI
--   UI.onToggle = function(name, state) end
--   UI.setStatus("teks")   UI.setStats("teks")   UI.destroy()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

-- ================= CONFIG =================
local ICON_ASSET_ID = 94315198453864

local CP1 = Vector3.new(-49.7, 4.0, -129.4)   -- Safe Zone
local CP2 = Vector3.new(-47.0, 12.3, 4319.9)  -- Zone

local CP1_SPEED     = 700    -- studs/detik, gerak paksa ke CP1 (cepat)
local CP2_SPEED     = 1500   -- studs/detik, gerak paksa ke CP2 (lebih cepat)
local WAIT_AT_CP1   = 9      -- detik tunggu di CP1 sebelum ke CP2
local SPAM_COUNT    = 8      -- jumlah spam TP di CP2
local SPAM_DELAY    = 0.15
local HEIGHT_OFFSET = 10     -- naikkan kalau nyangkut di tanah

-- Zombie / Guard / Bat dicari berdasarkan KATA di nama model (huruf kecil).
-- Ganti kalau nama di game kamu beda.
local ZOMBIE_KEYWORDS = { "zombie" }
local GUARD_KEYWORDS  = { "guard" }
local BAT_KEYWORD     = "bat"

local CHASE_DIST    = 3      -- jarak di belakang zombie
local ATTACK_DELAY  = 0.08
local CLICK_DELAY   = 0.07
local ZOMBIE_TWEEN_SPEED = 120

-- ================= CLEANUP =================
local env = (getgenv and getgenv()) or _G
if env.__SenarCleanup then pcall(env.__SenarCleanup) end

-- ================= API PUBLIK =================
local UI = {
	onToggle = function(name, state) end,
	setStatus = function() end,
	setStats = function() end,
	destroy = function() end,
}
env.SenarUI = UI

-- ================= WARNA =================
local C = {
	RED    = Color3.fromRGB(235, 35, 60),
	RED_DK = Color3.fromRGB(110, 12, 26),
	PINK   = Color3.fromRGB(255, 140, 190),
	BG     = Color3.fromRGB(13, 8, 10),
	SIDE   = Color3.fromRGB(8, 5, 6),
	PANEL  = Color3.fromRGB(26, 15, 18),
	HOVER  = Color3.fromRGB(44, 24, 29),
	STROKE = Color3.fromRGB(100, 52, 60),
	OFF    = Color3.fromRGB(55, 40, 44),
	GRAY   = Color3.fromRGB(150, 132, 137),
	WHITE  = Color3.fromRGB(255, 255, 255),
	BLACK  = Color3.fromRGB(0, 0, 0),
}

-- ================= HELPER =================
local function make(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	obj.Parent = parent
	return obj
end

local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function randName(n)
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local t = table.create(n)
	for i = 1, n do
		local k = math.random(1, #chars)
		t[i] = chars:sub(k, k)
	end
	return table.concat(t)
end

local tweens = {}
local sweepGradients = {}
local conns = {}

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
	local g = make("UIGradient", { Color = sweepSeq(base, hi), Offset = Vector2.new(-1, 0) }, inst)
	sweepGradients[g] = true
	return g
end

local function glowStroke(obj, th, base)
	local s = make("UIStroke", {
		Color = C.WHITE, Thickness = th or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, obj)
	addSweep(s, base or C.STROKE, C.WHITE)
	return s
end

local function spinStroke(parent, th)
	local st = make("UIStroke", {
		Color = C.WHITE, Thickness = th or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
	local g = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.BLACK),
			ColorSequenceKeypoint.new(0.2, C.RED),
			ColorSequenceKeypoint.new(0.35, C.WHITE),
			ColorSequenceKeypoint.new(0.5, C.BLACK),
			ColorSequenceKeypoint.new(0.7, C.RED_DK),
			ColorSequenceKeypoint.new(0.85, C.WHITE),
			ColorSequenceKeypoint.new(1, C.BLACK),
		}),
	}, st)
	local tw = TweenService:Create(g,
		TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 0),
		{ Rotation = 360 })
	tw:Play()
	table.insert(tweens, tw)
	return st
end

local function tween(obj, info, props)
	local tw = TweenService:Create(obj, info, props)
	tw:Play()
	return tw
end

-- ================= STATE FITUR =================
local State = {}      -- State["Nama Fitur"] = true/false
local Handlers = {}   -- Handlers["Nama Fitur"] = function(on)

local farmToken, zombieToken, clickToken, espToken = 0, 0, 0, 0
local restoreAntiLag  -- diisi di bagian logika

-- ================= GUI =================
local gui = make("ScreenGui", {
	Name = randName(14), ResetOnSpawn = false, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

do
	local ok = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

local myCleanup = function()
	farmToken += 1
	zombieToken += 1
	clickToken += 1
	espToken += 1
	if restoreAntiLag then pcall(restoreAntiLag) end
	if gui and gui.Parent then gui:Destroy() end
end
env.__SenarCleanup = myCleanup
UI.destroy = myCleanup

local sweepVal = make("NumberValue", { Value = -1 }, gui)
table.insert(conns, sweepVal.Changed:Connect(function(v)
	local off = Vector2.new(v, 0)
	for g in pairs(sweepGradients) do
		if g.Parent then g.Offset = off else sweepGradients[g] = nil end
	end
end))
do
	local tw = TweenService:Create(sweepVal,
		TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0),
		{ Value = 1 })
	tw:Play()
	table.insert(tweens, tw)
end

local W, H = 470, 300

local holder = make("Frame", {
	Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
	BackgroundTransparency = 1,
}, gui)
local fitScale = make("UIScale", { Scale = 1 }, holder)

local function updateFit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	fitScale.Scale = math.clamp(math.min(vp.X / (W + 30), vp.Y / (H + 30)), 0.45, 1)
end
updateFit()
if workspace.CurrentCamera then
	table.insert(conns, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateFit))
end

local main = make("Frame", {
	Name = "Main", Size = UDim2.fromScale(1, 1),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = C.BG, BorderSizePixel = 0, ClipsDescendants = true,
}, holder)
corner(main, 12)
local popScale = make("UIScale", { Scale = 1 }, main)
spinStroke(main, 1.5)

-- ---------- Balok atas & bawah ----------
local blocks = {}
do
	local BW, GAP = 16, 4
	local count = math.floor((W - 16) / (BW + GAP))
	local rng = Random.new(7)
	for i = 1, count do
		local x = 8 + (i - 1) * (BW + GAP)
		local col = C.RED_DK:Lerp(C.RED, rng:NextNumber())
		local hTop = rng:NextInteger(7, 18)
		local hBot = rng:NextInteger(7, 18)

		local top = make("Frame", {
			Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(BW, hTop),
			BackgroundColor3 = col, BackgroundTransparency = 0.35, BorderSizePixel = 0,
		}, main)
		local bot = make("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, H),
			Size = UDim2.fromOffset(BW, hBot),
			BackgroundColor3 = col, BackgroundTransparency = 0.35, BorderSizePixel = 0,
		}, main)
		table.insert(blocks, { frame = top, base = hTop, phase = rng:NextNumber() * 6.28 })
		table.insert(blocks, { frame = bot, base = hBot, phase = rng:NextNumber() * 6.28 })
	end
	blocks.width = BW
end

-- ---------- Sidebar ----------
local side = make("Frame", {
	Position = UDim2.fromOffset(8, 24), Size = UDim2.fromOffset(124, 252),
	BackgroundColor3 = C.SIDE, BackgroundTransparency = 0.12, BorderSizePixel = 0,
}, main)
corner(side, 10)
glowStroke(side, 1)

local titleRow = make("Frame", {
	Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(108, 24),
	BackgroundTransparency = 1,
}, side)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center,
}, titleRow)

local senar = make("TextLabel", {
	Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Text = "Senar", TextColor3 = C.WHITE,
	Font = Enum.Font.GothamBlack, TextSize = 18, LayoutOrder = 1,
}, titleRow)
make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.RED),
		ColorSequenceKeypoint.new(0.40, C.RED),
		ColorSequenceKeypoint.new(0.44, C.PINK),
		ColorSequenceKeypoint.new(1, C.PINK),
	}),
}, senar)

local hub = make("TextLabel", {
	Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Text = "Hub", TextColor3 = C.WHITE,
	Font = Enum.Font.GothamBlack, TextSize = 18, LayoutOrder = 2,
}, titleRow)
local hubGrad = make("UIGradient", {}, hub)

local function rainbowSeq(t)
	local kps = {}
	for i = 0, 6 do
		kps[#kps + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((t * 0.25 + i / 6) % 1, 0.85, 1))
	end
	return ColorSequence.new(kps)
end
hubGrad.Color = rainbowSeq(0)

local dot = make("Frame", {
	Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(6, 6),
	BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
}, side)
corner(dot, 3)
local statusLbl = make("TextLabel", {
	Position = UDim2.fromOffset(24, 32), Size = UDim2.new(1, -28, 0, 18),
	BackgroundTransparency = 1, Text = "Idle", TextColor3 = C.GRAY,
	Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, side)
local pingLbl = make("TextLabel", {
	Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -16, 0, 12),
	BackgroundTransparency = 1, Text = "Ping: -- ms", TextColor3 = C.PINK,
	Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
}, side)

UI.setStatus = function(t)
	if statusLbl and statusLbl.Parent then statusLbl.Text = tostring(t) end
end

-- ---------- Konten & halaman ----------
local content = make("Frame", {
	Position = UDim2.fromOffset(140, 24), Size = UDim2.fromOffset(322, 252),
	BackgroundTransparency = 1,
}, main)

local pages, tabBtns = {}, {}
local tabNames = { "Farm", "Zombie", "Visual", "Settings" }

for _, name in ipairs(tabNames) do
	pages[name] = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false,
	}, content)
end

local function selectTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, t in pairs(tabBtns) do
		local on = (n == name)
		t.btn.BackgroundTransparency = on and 0.15 or 1
		t.btn.TextColor3 = on and C.WHITE or C.GRAY
		t.stroke.Enabled = on
	end
end

for i, name in ipairs(tabNames) do
	local b = make("TextButton", {
		Position = UDim2.fromOffset(8, 68 + (i - 1) * 36), Size = UDim2.fromOffset(108, 30),
		BackgroundColor3 = C.HOVER, BackgroundTransparency = 1, BorderSizePixel = 0,
		Text = name, TextColor3 = C.GRAY, Font = Enum.Font.GothamBold, TextSize = 12,
		AutoButtonColor = false,
	}, side)
	corner(b, 8)
	local st = glowStroke(b, 1)
	st.Enabled = false
	tabBtns[name] = { btn = b, stroke = st }
	b.Activated:Connect(function() selectTab(name) end)
end

local hideBtn = make("TextButton", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.fromOffset(108, 28),
	BackgroundColor3 = C.PANEL, BorderSizePixel = 0, Text = "Hide", TextColor3 = C.WHITE,
	Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false,
}, side)
corner(hideBtn, 8)
glowStroke(hideBtn, 1)

-- ---------- Komponen ----------
local function makeList(parent)
	local s = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.SIDE, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.RED,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, parent)
	corner(s, 8)
	glowStroke(s, 1)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8),
	}, s)
	return s
end

local function makeSwitchCard(parent, name, order)
	local card = make("Frame", {
		Size = UDim2.new(1, 0, 0, 38), LayoutOrder = order or 0,
		BackgroundColor3 = C.PANEL, BorderSizePixel = 0,
	}, parent)
	corner(card, 8)
	glowStroke(card, 1)

	make("TextLabel", {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -64, 1, 0),
		BackgroundTransparency = 1, Text = name, TextColor3 = C.WHITE,
		Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, card)

	local track = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(38, 20), BackgroundColor3 = C.OFF, BorderSizePixel = 0,
	}, card)
	corner(track, 10)
	local knob = make("Frame", {
		Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.WHITE, BorderSizePixel = 0,
	}, track)
	corner(knob, 7)

	local overlay = make("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5,
	}, card)

	State[name] = false
	overlay.Activated:Connect(function()
		local on = not State[name]
		State[name] = on
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
		tween(knob, info, { Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) })
		tween(track, info, { BackgroundColor3 = on and C.RED or C.OFF })

		local okc, err = pcall(UI.onToggle, name, on)
		if not okc then warn("[Senar Hub] onToggle: " .. tostring(err)) end
		local h = Handlers[name]
		if h then
			task.spawn(function()
				local okh, e = pcall(h, on)
				if not okh then warn("[Senar Hub] " .. name .. ": " .. tostring(e)) end
			end)
		end
	end)
	return card
end

local function makeButtonCard(parent, order, getText, onClick)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 38), LayoutOrder = order or 0,
		BackgroundColor3 = C.PANEL, BorderSizePixel = 0, Text = getText(),
		TextColor3 = C.WHITE, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false,
	}, parent)
	corner(btn, 8)
	glowStroke(btn, 1)
	btn.Activated:Connect(function()
		onClick()
		btn.Text = getText()
	end)
	return btn
end

local function makeInfo(parent, order, text)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order or 0,
		BackgroundTransparency = 1, Text = text, TextColor3 = C.GRAY,
		Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

-- ---------- Isi halaman ----------
local METHODS = { "Chase (TP)", "Tween", "Instant Kill" }
local methodIdx = 1
local statsLbl

do -- Farm
	local list = makeList(pages.Farm)
	makeSwitchCard(list, "Auto Farm CP", 1)
	makeSwitchCard(list, "Instant Steal", 2)
	statsLbl = makeInfo(list, 3, "Putaran: 0")
	makeInfo(list, 4, "Instant Steal: setelah 9 dtk langsung TP ke CP2")
end

do -- Zombie
	local list = makeList(pages.Zombie)
	makeSwitchCard(list, "Auto Farm Zombie", 1)
	makeSwitchCard(list, "Melee (Bat)", 2)
	makeButtonCard(list, 3, function() return "Method: " .. METHODS[methodIdx] end, function()
		methodIdx = methodIdx % #METHODS + 1
	end)
	makeSwitchCard(list, "Auto Click", 4)
end

do -- Visual
	local list = makeList(pages.Visual)
	makeSwitchCard(list, "ESP Guard", 1)
	makeSwitchCard(list, "Anti Lag", 2)
end

do -- Settings
	local list = makeList(pages.Settings)
	makeSwitchCard(list, "Notification", 1)
	makeInfo(list, 2, "Matikan Auto Farm CP & Zombie bersamaan")
end

UI.setStats = function(t)
	if statsLbl and statsLbl.Parent then statsLbl.Text = tostring(t) end
end

selectTab("Farm")

-- ---------- Kilatan cahaya ----------
do
	local streak = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(-60, H / 2),
		Size = UDim2.fromOffset(14, H + 120), Rotation = 18,
		BackgroundTransparency = 1, ZIndex = 50,
	}, main)
	make("Frame", {
		Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(3, H + 120),
		BackgroundColor3 = C.WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 50,
	}, streak)
	make("Frame", {
		Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(5, H + 120),
		BackgroundColor3 = C.BLACK, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 50,
	}, streak)

	local tw = TweenService:Create(streak,
		TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.5),
		{ Position = UDim2.fromOffset(W + 60, H / 2) })
	tw:Play()
	table.insert(tweens, tw)
end

-- ---------- Buka / tutup ----------
local opened = true
local function setOpen(state)
	opened = state
	if state then
		holder.Visible = true
		popScale.Scale = 0.85
		tween(popScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	else
		tween(popScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		task.delay(0.18, function()
			if not opened and holder.Parent then holder.Visible = false end
		end)
	end
end
hideBtn.Activated:Connect(function() setOpen(false) end)

-- ---------- Drag window ----------
local function attachDrag(dragFrame)
	local dragging, startMouse, startPos
	table.insert(conns, dragFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startMouse, startPos = true, input.Position, holder.Position
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = (input.Position - startMouse) / fitScale.Scale
			holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

attachDrag(make("Frame", {
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Active = true, ZIndex = 40,
}, main))
attachDrag(make("Frame", {
	Position = UDim2.fromOffset(8, 24), Size = UDim2.fromOffset(124, 40),
	BackgroundTransparency = 1, Active = true, ZIndex = 40,
}, main))

-- ---------- Floating icon ----------
local iconBtn = make("TextButton", {
	Name = "FloatingIcon", Position = UDim2.new(0, 16, 0.5, -26), Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = C.BG, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 60,
}, gui)
corner(iconBtn, 26)
spinStroke(iconBtn, 2)

local iconFallback = make("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "S",
	TextColor3 = C.RED, Font = Enum.Font.GothamBlack, TextSize = 24, ZIndex = 61,
}, iconBtn)

do
	local img = make("ImageLabel", {
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10),
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
		Image = "rbxassetid://" .. tostring(ICON_ASSET_ID), Visible = false, ZIndex = 62,
	}, iconBtn)
	corner(img, 21)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ img }, function(_, status)
				if status == Enum.AssetFetchStatus.Success and img.Parent then
					img.Visible = true
					iconFallback.Text = ""
				end
			end)
		end)
	end)
end

do
	local dragging, moved, startMouse, startPos
	table.insert(conns, iconBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved, startMouse, startPos = true, false, input.Position, iconBtn.Position
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			if d.Magnitude > 6 then moved = true end
			if moved then
				iconBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if not moved then setOpen(not opened) end
		end
	end))
end

-- ---------- Animasi ----------
do
	local t0 = os.clock()
	local acc = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not holder.Visible then return end
		local t = os.clock() - t0
		local bw = blocks.width
		for _, b in ipairs(blocks) do
			b.frame.Size = UDim2.fromOffset(bw, b.base + math.sin(t * 2 + b.phase) * 3)
		end
		acc += dt
		if acc >= 0.05 then
			acc = 0
			hubGrad.Color = rainbowSeq(t)
		end
	end))
end

---------------------------------------------------------------------
-- ===================== LOGIKA FITUR =====================
---------------------------------------------------------------------
local function getChar() return LocalPlayer.Character end
local function getRoot()
	local ch = getChar()
	return ch and ch:FindFirstChild("HumanoidRootPart")
end
local function getHum()
	local ch = getChar()
	return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function above(pos) return pos + Vector3.new(0, HEIGHT_OFFSET, 0) end

-- ---------- Ping ----------
task.spawn(function()
	while gui.Parent do
		local ok, v = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and pingLbl.Parent then
			pingLbl.Text = string.format("Ping: %d ms", math.floor(v))
		end
		task.wait(1)
	end
end)

-- ---------- Gerak paksa (bukan Tween) ----------
-- Tiap frame CFrame digeser langsung ke target dengan kecepatan `speed`.
local function forceMove(pos, speed, token)
	local goal = above(pos)
	while farmToken == token do
		local root = getRoot()
		if not root then return false end
		local delta = goal - root.Position
		local dist = delta.Magnitude
		if dist <= 3 then
			root.CFrame = CFrame.new(goal) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			return true
		end
		local dt = RunService.Heartbeat:Wait()
		root = getRoot()
		if not root then return false end
		local step = math.min(speed * dt, dist)
		root.CFrame = CFrame.new(root.Position + delta.Unit * step) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return false
end

local function instantTP(pos)
	local root = getRoot()
	if not root then return false end
	root.CFrame = CFrame.new(above(pos)) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function waitFor(seconds, token, label)
	local untilT = os.clock() + seconds
	while os.clock() < untilT do
		if farmToken ~= token then return false end
		UI.setStatus(string.format("%s (%.1fs)", label, untilT - os.clock()))
		task.wait(0.1)
	end
	return farmToken == token
end

local function spamTeleport(pos, count, token)
	for i = 1, count do
		if farmToken ~= token then return false end
		instantTP(pos)
		UI.setStatus(string.format("Spam TP %d/%d", i, count))
		task.wait(SPAM_DELAY)
	end
	return farmToken == token
end

-- ---------- Auto Farm CP ----------
local function farmLoop(token)
	local cycles = 0
	while farmToken == token do
		-- 1) gerak paksa cepat ke CP1
		UI.setStatus("Gerak ke CP1")
		if not forceMove(CP1, CP1_SPEED, token) then
			if farmToken ~= token then break end
			task.wait(1)
			continue
		end

		-- 2) tunggu di CP1
		if not waitFor(WAIT_AT_CP1, token, "Tunggu di CP1") then break end

		-- 3) ke CP2: Instant Steal = langsung TP, kalau mati = gerak paksa lebih cepat
		if State["Instant Steal"] then
			UI.setStatus("Instant Steal -> CP2")
			if not instantTP(CP2) then task.wait(1) continue end
		else
			UI.setStatus("Gerak ke CP2")
			if not forceMove(CP2, CP2_SPEED, token) then
				if farmToken ~= token then break end
				task.wait(1)
				continue
			end
		end

		-- 4) spam TP di CP2
		if not spamTeleport(CP2, SPAM_COUNT, token) then break end

		cycles += 1
		UI.setStats("Putaran: " .. cycles)
	end
end

Handlers["Auto Farm CP"] = function(on)
	farmToken += 1
	if on then
		task.spawn(farmLoop, farmToken)
	else
		UI.setStatus("Idle")
	end
end

-- ---------- Pelacak NPC (zombie / guard) ----------
local function nameMatch(inst, kws)
	local n = inst.Name:lower()
	for _, k in ipairs(kws) do
		if n:find(k, 1, true) then return true end
	end
	return false
end

local function makeTracker(kws)
	local set = {}
	local function consider(d)
		if d:IsA("Humanoid") then
			local m = d.Parent
			if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) and nameMatch(m, kws) then
				set[m] = d
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do consider(d) end
	table.insert(conns, workspace.DescendantAdded:Connect(consider))
	table.insert(conns, workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("Humanoid") and set[d.Parent] then set[d.Parent] = nil end
	end))
	return set
end

local zombieSet, guardSet
local function zombies()
	if not zombieSet then zombieSet = makeTracker(ZOMBIE_KEYWORDS) end
	return zombieSet
end
local function guards()
	if not guardSet then guardSet = makeTracker(GUARD_KEYWORDS) end
	return guardSet
end

local function partOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
end

local function nearestAlive(set, from)
	local best, bestHum, bestD = nil, nil, math.huge
	for m, h in pairs(set) do
		if m.Parent and h.Parent and h.Health > 0 then
			local p = partOf(m)
			if p then
				local d = (p.Position - from).Magnitude
				if d < bestD then best, bestHum, bestD = m, h, d end
			end
		end
	end
	return best, bestHum
end

-- ---------- Bat / Auto Click ----------
local function findTool(pattern)
	local ch = getChar()
	local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
	for _, holderObj in ipairs({ ch, bp }) do
		if holderObj then
			for _, t in ipairs(holderObj:GetChildren()) do
				if t:IsA("Tool") and t.Name:lower():find(pattern, 1, true) then return t end
			end
		end
	end
	return nil
end

local function equipBat()
	local tool = findTool(BAT_KEYWORD)
	local hum = getHum()
	if tool and hum and tool.Parent ~= getChar() then
		pcall(function() hum:EquipTool(tool) end)
	end
	return tool
end

local function swing()
	local ch = getChar()
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	if tool then
		pcall(function() tool:Activate() end)
	else
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton1(Vector2.new(0, 0))
		end)
	end
end

Handlers["Auto Click"] = function(on)
	clickToken += 1
	if not on then return end
	local token = clickToken
	while clickToken == token and gui.Parent do
		swing()
		task.wait(CLICK_DELAY)
	end
end

-- Melee (Bat): ambil bat sekali saat dinyalakan, selanjutnya dijaga di loop zombie
Handlers["Melee (Bat)"] = function(on)
	if on then equipBat() end
end

-- ---------- Auto Farm Zombie ----------
local function touchHit(zr)
	local ch = getChar()
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle")
	if handle and zr and firetouchinterest then
		pcall(function()
			firetouchinterest(handle, zr, 0)
			firetouchinterest(handle, zr, 1)
		end)
	end
end

local function zombieLoop(token)
	local kills = 0
	while zombieToken == token do
		local root = getRoot()
		if not root then task.wait(0.5) continue end

		local z, zh = nearestAlive(zombies(), root.Position)
		if not z then
			UI.setStatus("Cari zombie...")
			task.wait(0.4)
			continue
		end
		UI.setStatus("Target: " .. z.Name)

		while zombieToken == token and zh.Health > 0 and z.Parent do
			root = getRoot()
			local zr = partOf(z)
			if not root or not zr then break end

			local method = METHODS[methodIdx]
			local goal = (zr.CFrame * CFrame.new(0, 0, CHASE_DIST)).Position
			local look = CFrame.lookAt(goal, zr.Position)

			if method == "Tween" then
				local dur = math.max((root.Position - goal).Magnitude / ZOMBIE_TWEEN_SPEED, 0.03)
				local tw = TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = look })
				tw:Play()
				task.wait(dur)
				tw:Cancel()
			else
				-- Chase (TP) & Instant Kill: nempel di belakang zombie tiap frame
				root.CFrame = look
			end
			root.AssemblyLinearVelocity = Vector3.zero

			if method == "Instant Kill" then
				pcall(function() zh.Health = 0 end)
				touchHit(zr)
			end

			if State["Melee (Bat)"] then equipBat() end
			if not State["Auto Click"] then swing() end
			task.wait(ATTACK_DELAY)
		end

		if zh.Health <= 0 then
			kills += 1
			UI.setStats("Zombie mati: " .. kills)
		end
	end
end

Handlers["Auto Farm Zombie"] = function(on)
	zombieToken += 1
	if on then
		task.spawn(zombieLoop, zombieToken)
	else
		UI.setStatus("Idle")
	end
end

-- ---------- ESP Guard ----------
local espFolder = make("Folder", { Name = "esp" }, gui)
local espObjs = {}

local function clearEsp(m)
	local o = espObjs[m]
	if o then
		pcall(function() o.hl:Destroy() end)
		pcall(function() o.bb:Destroy() end)
		espObjs[m] = nil
	end
end

Handlers["ESP Guard"] = function(on)
	espToken += 1
	for m in pairs(espObjs) do clearEsp(m) end
	if not on then return end
	local token = espToken
	local set = guards()

	while espToken == token and gui.Parent do
		local root = getRoot()
		for m in pairs(set) do
			local part = m.Parent and partOf(m)
			if part and not espObjs[m] then
				local hl = make("Highlight", {
					Adornee = m, FillColor = C.RED, FillTransparency = 0.55,
					OutlineColor = C.WHITE, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				}, espFolder)
				local bb = make("BillboardGui", {
					Adornee = part, Size = UDim2.fromOffset(130, 26), AlwaysOnTop = true,
					StudsOffset = Vector3.new(0, 3.5, 0),
				}, espFolder)
				local lbl = make("TextLabel", {
					Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = m.Name,
					TextColor3 = C.WHITE, TextStrokeTransparency = 0.4,
					Font = Enum.Font.GothamBold, TextSize = 12,
				}, bb)
				espObjs[m] = { hl = hl, bb = bb, lbl = lbl, part = part }
			end
		end
		for m, o in pairs(espObjs) do
			if not m.Parent or not set[m] then
				clearEsp(m)
			elseif root and o.part and o.part.Parent then
				local d = (o.part.Position - root.Position).Magnitude
				o.lbl.Text = string.format("%s [%dm]", m.Name, math.floor(d))
			end
		end
		task.wait(0.25)
	end
end

-- ---------- Anti Lag ----------
local antiBackup, antiConn

local function killFx(d)
	if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Smoke")
		or d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("PostEffect") then
		if antiBackup then antiBackup.fx[d] = d.Enabled end
		pcall(function() d.Enabled = false end)
	end
end

restoreAntiLag = function()
	if antiConn then antiConn:Disconnect() antiConn = nil end
	if not antiBackup then return end
	for d, v in pairs(antiBackup.fx) do
		pcall(function() if d.Parent then d.Enabled = v end end)
	end
	pcall(function() Lighting.GlobalShadows = antiBackup.shadows end)
	pcall(function() settings().Rendering.QualityLevel = antiBackup.quality end)
	antiBackup = nil
end

Handlers["Anti Lag"] = function(on)
	if not on then
		restoreAntiLag()
		return
	end
	if antiBackup then return end
	antiBackup = { fx = {}, shadows = Lighting.GlobalShadows, quality = settings().Rendering.QualityLevel }
	pcall(function() Lighting.GlobalShadows = false end)
	pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
	for _, d in ipairs(workspace:GetDescendants()) do killFx(d) end
	for _, d in ipairs(Lighting:GetDescendants()) do killFx(d) end
	antiConn = workspace.DescendantAdded:Connect(killFx)
end

-- ---------- Cleanup ----------
gui.Destroying:Connect(function()
	if env.__SenarCleanup == myCleanup then env.__SenarCleanup = nil end
	if env.SenarUI == UI then env.SenarUI = nil end
	table.clear(sweepGradients)
	for _, c in ipairs(conns) do c:Disconnect() end
	for _, t in ipairs(tweens) do pcall(function() t:Cancel() end) end
end)

-- ====== TARUH KODE PROJECT KAMU DI BAWAH SINI ======
