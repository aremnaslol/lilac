--[[
	LILAC v2 — interface + test-game features
	Two-column cards, sub-tabs, HSV color picker, dropdown popups, keybinds,
	tooltips, toasts, config export/import and a fully reactive live preview.

	LocalScript for your OWN test game (StarterPlayerScripts / StarterGui).
	The ESP / combat / movement modules act on real players in the server you
	are testing in. Menu key: RightShift (rebindable in Settings).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

if _G.__LilacCleanup then pcall(_G.__LilacCleanup) end

print("[Lilac] starting...")
local player = Players.LocalPlayer
if not player then
	warn("[Lilac] No LocalPlayer. You are in Edit mode. Press Play (or Run a client) first, then execute again.")
	return
end
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	warn("[Lilac] PlayerGui never loaded.")
	return
end
local stale = playerGui:FindFirstChild("LilacUI")
if stale then stale:Destroy() end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------
local connections = {}
local cleanups = {}
local gui

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function unload()
	for _, f in ipairs(cleanups) do pcall(f) end
	table.clear(cleanups)
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	if gui then gui:Destroy() end
	_G.__LilacCleanup = nil
end
_G.__LilacCleanup = unload

--------------------------------------------------------------------------
-- constants / theme
--------------------------------------------------------------------------
-- platform: "PC", "Mobile" or "Console". Override with _G.LilacPlatform = "Mobile" before running (handy for Studio testing).
local function detectPlatform()
	if _G.LilacPlatform then return _G.LilacPlatform end
	local U = UserInputService
	if U.TouchEnabled and not U.KeyboardEnabled then return "Mobile" end
	if U.GamepadEnabled and not U.KeyboardEnabled and not U.MouseEnabled and not U.TouchEnabled then return "Console" end
	return "PC"
end
local platform = detectPlatform()
local isMobile = platform == "Mobile"

local RW, RH = 1360, 650
local MAIN_W = 1080
local SIDEBAR_W = 200
if isMobile then RW, RH, MAIN_W, SIDEBAR_W = 820, 400, 820, 150 end
local PREVIEW_W = 260
local CONTENT_W = MAIN_W - SIDEBAR_W

local BODY = Enum.Font.GothamMedium
local LIGHT = Enum.Font.Gotham
local BOLD = Enum.Font.GothamBold
local HEAD = Enum.Font.Merriweather

local Theme = {
	Bg = Color3.fromRGB(12, 7, 15),
	Sidebar = Color3.fromRGB(16, 9, 19),
	Card = Color3.fromRGB(24, 14, 28),
	CardHead = Color3.fromRGB(34, 19, 39),
	Field = Color3.fromRGB(15, 9, 18),
	Border = Color3.fromRGB(66, 36, 62),
	Text = Color3.fromRGB(246, 232, 244),
	Muted = Color3.fromRGB(148, 122, 150),
	Off = Color3.fromRGB(54, 38, 58),
	Accent = Color3.fromRGB(240, 130, 200),
	Accent2 = Color3.fromRGB(176, 92, 232),
}

local Presets = {
	Lilac = { Color3.fromRGB(240, 130, 200), Color3.fromRGB(176, 92, 232) },
	Rose = { Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 160, 110) },
	Violet = { Color3.fromRGB(150, 110, 255), Color3.fromRGB(100, 150, 255) },
	Ice = { Color3.fromRGB(110, 200, 255), Color3.fromRGB(150, 130, 255) },
}

local Environments = {
	Default = Color3.fromRGB(9, 8, 13),
	Night = Color3.fromRGB(4, 6, 18),
	Soft = Color3.fromRGB(44, 32, 50),
	Neon = Color3.fromRGB(14, 4, 26),
}

local FontMap = {
	Gotham = Enum.Font.GothamMedium,
	Code = Enum.Font.Code,
	Merriweather = Enum.Font.Merriweather,
}

--------------------------------------------------------------------------
-- settings registry
--------------------------------------------------------------------------
local Settings, Defaults, Controls, Handlers = {}, {}, {}, {}
local TabKeys = {}
local bulk = false
local previewDirty = true

local function commit(key, value)
	Settings[key] = value
	previewDirty = true
	local h = Handlers[key]
	if h then h(value) end
end

local function applySetting(key, value)
	local c = Controls[key]
	if c then c.apply(value) end
	commit(key, value)
end

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------
local function create(className, props, parent)
	local obj = Instance.new(className)
	if props then
		for k, v in pairs(props) do obj[k] = v end
	end
	if parent then obj.Parent = parent end
	return obj
end

local function corner(parent, r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local function round(parent)
	return create("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function pad(parent, t, r, b, l)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or t or 0),
		PaddingBottom = UDim.new(0, b or t or 0),
		PaddingLeft = UDim.new(0, l or r or t or 0),
	}, parent)
end

local function tween(obj, props, dur, style)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(dur or 0.18, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function text(parent, str, size, color, font, align)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = str,
		TextSize = size,
		TextColor3 = color or Theme.Text,
		Font = font or BODY,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
end

local function contrast(c)
	local lum = c.R * 0.299 + c.G * 0.587 + c.B * 0.114
	return lum > 0.6 and Color3.fromRGB(20, 10, 24) or Color3.new(1, 1, 1)
end

local function hex(c)
	return "#" .. c:ToHex():upper()
end

local function pointer(i)
	if i.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		return Vector2.new(i.Position.X + inset.X, i.Position.Y + inset.Y)
	end
	return UserInputService:GetMouseLocation()
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch
end

local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement
		or i.UserInputType == Enum.UserInputType.Touch
end

local function lastInputIsPad()
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function matchesBind(i, name)
	if not name then return false end
	local ut = i.UserInputType
	if ut == Enum.UserInputType.Keyboard or ut.Name:sub(1, 7) == "Gamepad" then return i.KeyCode.Name == name end
	return ut.Name == name
end

local keyEnumCache = {}
local function bindDown(name)
	if not name then return false end
	if name:sub(1, 11) == "MouseButton" then
		local ok, ut = pcall(function() return Enum.UserInputType[name] end)
		return (ok and ut and UserInputService:IsMouseButtonPressed(ut)) or false
	end
	local kc = keyEnumCache[name]
	if kc == nil then
		local ok, v = pcall(function() return Enum.KeyCode[name] end)
		kc = ok and v or false
		keyEnumCache[name] = kc
	end
	if not kc then return false end
	if UserInputService:IsKeyDown(kc) then return true end
	local okG, down = pcall(UserInputService.IsGamepadButtonDown, UserInputService, Enum.UserInputType.Gamepad1, kc)
	return (okG and down) or false
end

local accentBinds = {}
local function bindAccent(fn)
	table.insert(accentBinds, fn)
	fn()
end
local function refreshAccent()
	for _, fn in ipairs(accentBinds) do fn() end
end

-- vector icons built from frames (no unicode glyphs, so nothing renders as a box)
local function makeIcon(kind, parent)
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
	}, parent)
	local fills, strokes = {}, {}

	local function shape(o)
		local f = create("Frame", {
			BackgroundTransparency = o.fill and 0 or 1,
			BackgroundColor3 = Theme.Muted,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(o.x, o.y),
			Size = UDim2.fromOffset(o.w, o.h),
			Rotation = o.rot or 0,
		}, holder)
		if o.round then round(f) elseif o.r then corner(f, o.r) end
		if o.fill then
			table.insert(fills, f)
		else
			table.insert(strokes, stroke(f, Theme.Muted, o.th or 1.5))
		end
	end

	if kind == "Combat" then
		shape({ x = 10, y = 10, w = 12, h = 12, round = true, th = 1.5 })
		shape({ x = 10, y = 2.5, w = 2, h = 5, fill = true })
		shape({ x = 10, y = 17.5, w = 2, h = 5, fill = true })
		shape({ x = 2.5, y = 10, w = 5, h = 2, fill = true })
		shape({ x = 17.5, y = 10, w = 5, h = 2, fill = true })
		shape({ x = 10, y = 10, w = 2.5, h = 2.5, round = true, fill = true })
	elseif kind == "ESP" then
		shape({ x = 10, y = 10, w = 18, h = 11, r = 6, th = 1.5 })
		shape({ x = 10, y = 10, w = 5, h = 5, round = true, fill = true })
	elseif kind == "Visuals" then
		shape({ x = 10, y = 10, w = 11, h = 11, r = 2, th = 1.5, rot = 45 })
		shape({ x = 10, y = 10, w = 4, h = 4, r = 1, fill = true, rot = 45 })
	elseif kind == "World" then
		shape({ x = 10, y = 10, w = 16, h = 16, round = true, th = 1.5 })
		shape({ x = 10, y = 10, w = 16, h = 1.5, fill = true })
		shape({ x = 10, y = 10, w = 7, h = 16, round = true, th = 1.2 })
	elseif kind == "Character" then
		shape({ x = 10, y = 5.5, w = 7, h = 7, round = true, th = 1.5 })
		shape({ x = 10, y = 14.5, w = 14, h = 7, r = 4, th = 1.5 })
	elseif kind == "Misc" then
		for _, p in ipairs({ { 5, 5 }, { 15, 5 }, { 5, 15 }, { 15, 15 } }) do
			shape({ x = p[1], y = p[2], w = 7, h = 7, r = 2, th = 1.5 })
		end
	elseif kind == "Settings" then
		shape({ x = 10, y = 10, w = 11, h = 11, round = true, th = 2 })
		shape({ x = 10, y = 2, w = 3, h = 4, fill = true })
		shape({ x = 10, y = 18, w = 3, h = 4, fill = true })
		shape({ x = 2, y = 10, w = 4, h = 3, fill = true })
		shape({ x = 18, y = 10, w = 4, h = 3, fill = true })
	end

	local function setColor(c)
		for _, f in ipairs(fills) do f.BackgroundColor3 = c end
		for _, s in ipairs(strokes) do s.Color = c end
	end
	return holder, setColor
end

local function chevron(parent, pos)
	local h = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(10, 10),
	}, parent)
	for _, d in ipairs({ { 3.2, 45 }, { 6.8, -45 } }) do
		create("Frame", {
			BackgroundColor3 = Theme.Muted,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(d[1], 4.5),
			Size = UDim2.fromOffset(6, 1.6),
			Rotation = d[2],
		}, h)
	end
	return h
end

local function makeButton(parent, label, w, h, primary)
	local b = create("TextButton", {
		Text = label,
		Font = BODY,
		TextSize = 11,
		AutoButtonColor = false,
		TextColor3 = primary and Color3.fromRGB(24, 10, 28) or Theme.Text,
		BackgroundColor3 = primary and Theme.Accent or Theme.CardHead,
		Size = UDim2.fromOffset(w, h),
		BorderSizePixel = 0,
	}, parent)
	corner(b, 8)
	local s = stroke(b, primary and Theme.Accent or Theme.Border, 1)
	bindAccent(function()
		if primary then
			b.BackgroundColor3 = Theme.Accent
			s.Color = Theme.Accent
		end
	end)
	b.MouseEnter:Connect(function()
		tween(b, { BackgroundTransparency = 0.25 }, 0.1)
	end)
	b.MouseLeave:Connect(function()
		tween(b, { BackgroundTransparency = 0 }, 0.1)
	end)
	return b
end

local function dragInput(guiObject, onPos, bag)
	bag = bag or connections
	local active = false
	table.insert(bag, guiObject.InputBegan:Connect(function(i)
		if isPress(i) then
			active = true
			onPos(pointer(i))
		end
	end))
	table.insert(bag, UserInputService.InputChanged:Connect(function(i)
		if active and isMove(i) then onPos(pointer(i)) end
	end))
	table.insert(bag, UserInputService.InputEnded:Connect(function(i)
		if isPress(i) then active = false end
	end))
end

--------------------------------------------------------------------------
-- screen / window
--------------------------------------------------------------------------
gui = create("ScreenGui", {
	Name = "LilacUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1000,
}, playerGui)

local root = create("Frame", {
	Name = "Root",
	ZIndex = 10,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RW, RH),
	BackgroundTransparency = 1,
}, gui)

local dim = create("TextButton", {
	Name = "Dim",
	Selectable = false,
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
	Modal = true,
}, gui)
local uiScale = create("UIScale", {}, root)
local userScale = 1
local function fit()
	local v = gui.AbsoluteSize
	local s = math.min(1, (v.X - 32) / RW, (v.Y - 32) / RH)
	uiScale.Scale = math.max(0.4, s) * userScale
end
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
fit()

-- layered glow behind the window
local glowOuter = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(-5, -5),
	Size = UDim2.fromOffset(MAIN_W + 10, RH + 10),
}, root)
corner(glowOuter, 20)
local glowOuterStroke = stroke(glowOuter, Theme.Accent, 7, 0.82)

local glowInner = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(-2, -2),
	Size = UDim2.fromOffset(MAIN_W + 4, RH + 4),
}, root)
corner(glowInner, 17)
local glowInnerStroke = stroke(glowInner, Theme.Accent, 3, 0.6)

local main = create("Frame", {
	Name = "Main",
	BackgroundColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromOffset(MAIN_W, RH),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, root)
corner(main, 15)
create("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(19, 10, 23), Color3.fromRGB(10, 6, 13)),
}, main)
local mainStroke = stroke(main, Theme.Accent, 1.5, 0.05)

bindAccent(function()
	glowOuterStroke.Color = Theme.Accent
	glowInnerStroke.Color = Theme.Accent
	mainStroke.Color = Theme.Accent
end)

-- falling petals layer (behind everything else in the window)
local fx = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ClipsDescendants = true,
}, main)

local petals = {}
for i = 1, 30 do
	local f = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(math.random(7, 11), math.random(5, 8)),
		Visible = false,
	}, fx)
	corner(f, 5)
	petals[i] = {
		f = f,
		x = math.random(0, MAIN_W),
		y = math.random(-40, RH),
		vy = math.random(16, 36),
		vx = math.random(-10, 6),
		rot = math.random(0, 360),
		vr = math.random(-60, 60),
		ph = math.random() * 6,
	}
end
bindAccent(function()
	for _, p in ipairs(petals) do p.f.BackgroundColor3 = Theme.Accent end
end)

--------------------------------------------------------------------------
-- sidebar
--------------------------------------------------------------------------
local sidebar = create("Frame", {
	Name = "Sidebar",
	BackgroundColor3 = Theme.Sidebar,
	BackgroundTransparency = 0.15,
	Size = UDim2.new(0, SIDEBAR_W, 1, 0),
	BorderSizePixel = 0,
}, main)
create("Frame", {
	BackgroundColor3 = Theme.Border,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	Position = UDim2.new(1, -1, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
}, sidebar)

local logo = create("Frame", {
	BackgroundColor3 = Theme.CardHead,
	Position = UDim2.fromOffset(14, 13),
	Size = UDim2.fromOffset(38, 38),
	BorderSizePixel = 0,
}, sidebar)
corner(logo, 11)
local logoStroke = stroke(logo, Theme.Accent, 1.2)
local logoText = text(logo, "L", 21, Theme.Accent, HEAD, Enum.TextXAlignment.Center)
logoText.Size = UDim2.fromScale(1, 1)
bindAccent(function()
	logoStroke.Color = Theme.Accent
	logoText.TextColor3 = Theme.Accent
end)

local brand = text(sidebar, "Lilac", 18, Theme.Text, HEAD)
brand.Position = UDim2.fromOffset(62, 12)
brand.Size = UDim2.new(1, -70, 0, 24)
local brandSub = text(sidebar, "PRIVATE BUILD  ·  v2.0", 8, Theme.Muted, LIGHT)
brandSub.Position = UDim2.fromOffset(63, 36)
brandSub.Size = UDim2.new(1, -70, 0, 14)

local modulesLbl = text(sidebar, "MODULES", 9, Theme.Muted, BOLD)
modulesLbl.Position = UDim2.fromOffset(20, 58)
modulesLbl.Size = UDim2.new(1, -40, 0, 14)

local navHolder = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, isMobile and 62 or 78),
	Size = UDim2.new(1, -24, 0, 380),
}, sidebar)
create("UIListLayout", { Padding = UDim.new(0, isMobile and 4 or 6), SortOrder = Enum.SortOrder.LayoutOrder }, navHolder)

local profile = create("Frame", {
	BackgroundColor3 = Theme.Card,
	Position = UDim2.new(0, 12, 1, -68),
	Size = UDim2.new(1, -24, 0, 54),
	BorderSizePixel = 0,
}, sidebar)
corner(profile, 12)
stroke(profile, Theme.Border, 1, 0.2)

local avatar = create("ImageLabel", {
	BackgroundColor3 = Theme.CardHead,
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.fromOffset(38, 38),
	BorderSizePixel = 0,
	Image = "",
}, profile)
corner(avatar, 9)
task.spawn(function()
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	if ok and avatar.Parent then avatar.Image = img end
end)

local pName = text(profile, player.DisplayName, 12, Theme.Text, BODY)
pName.Position = UDim2.fromOffset(56, 9)
pName.Size = UDim2.new(1, -62, 0, 18)
pName.TextTruncate = Enum.TextTruncate.AtEnd
local pSub = text(profile, "Lilac Private", 10, Theme.Muted, LIGHT)
pSub.Position = UDim2.fromOffset(56, 28)
pSub.Size = UDim2.new(1, -62, 0, 14)
if isMobile then profile.Visible = false; modulesLbl.Visible = false end

--------------------------------------------------------------------------
-- top bar (inside main so minimizing keeps it)
--------------------------------------------------------------------------
local dragBar = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 56),
	Active = true,
}, main)

local pageTitle = text(main, "ESP", 17, Theme.Text, HEAD)
pageTitle.Position = UDim2.fromOffset(SIDEBAR_W + 22, 0)
pageTitle.Size = UDim2.fromOffset(120, 56)
local topLine = create("Frame", {
	BackgroundColor3 = Theme.Accent,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(SIDEBAR_W, 55),
	Size = UDim2.fromOffset(MAIN_W - SIDEBAR_W, 1),
}, main)
create("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.7), NumberSequenceKeypoint.new(1, 1),
	}),
}, topLine)
bindAccent(function() topLine.BackgroundColor3 = Theme.Accent end)
local fpsLabel = text(main, "", 10, Theme.Muted, BODY, Enum.TextXAlignment.Right)
fpsLabel.Position = UDim2.new(1, -150, 0, 0)
fpsLabel.Size = UDim2.fromOffset(90, 56)
local fpsSmooth = 60

local searchBox = create("TextBox", {
	Name = "Search",
	Text = "",
	PlaceholderText = "Search settings...",
	ClearTextOnFocus = false,
	Font = LIGHT,
	TextSize = 12,
	TextColor3 = Theme.Text,
	PlaceholderColor3 = Theme.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundColor3 = Theme.Field,
	Position = UDim2.fromOffset(SIDEBAR_W + 140, 12),
	Size = UDim2.fromOffset(isMobile and 330 or 440, 32),
	BorderSizePixel = 0,
}, main)
corner(searchBox, 10)
local searchStroke = stroke(searchBox, Theme.Border, 1)
pad(searchBox, 0, 10, 0, 36)
do
	local ring = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(-19, 15),
		Size = UDim2.fromOffset(10, 10),
	}, searchBox)
	round(ring)
	stroke(ring, Theme.Muted, 1.5)
	create("Frame", {
		BackgroundColor3 = Theme.Muted,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(-12.5, 21),
		Size = UDim2.fromOffset(6, 1.6),
		Rotation = 45,
	}, searchBox)
end
connect(searchBox.Focused, function() tween(searchStroke, { Color = Theme.Accent }, 0.12) end)
connect(searchBox.FocusLost, function() tween(searchStroke, { Color = Theme.Border }, 0.12) end)

local function windowButton(offsetX, kind)
	local b = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.CardHead,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, offsetX, 0, 13),
		Size = UDim2.fromOffset(30, 30),
		BorderSizePixel = 0,
	}, main)
	corner(b, 8)
	local bars = {}
	local function bar(rot)
		local f = create("Frame", {
			BackgroundColor3 = Theme.Muted,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 1.6),
			Rotation = rot,
		}, b)
		table.insert(bars, f)
	end
	if kind == "close" then bar(45); bar(-45) else bar(0) end
	b.MouseEnter:Connect(function()
		tween(b, { BackgroundTransparency = 0 }, 0.1)
		for _, f in ipairs(bars) do f.BackgroundColor3 = Theme.Text end
	end)
	b.MouseLeave:Connect(function()
		tween(b, { BackgroundTransparency = 1 }, 0.1)
		for _, f in ipairs(bars) do f.BackgroundColor3 = Theme.Muted end
	end)
	return b
end

local minButton = windowButton(-44, "min")

-- window dragging
local drag = { active = false }
connect(dragBar.InputBegan, function(i)
	if Settings["set.lock"] then return end
	if isPress(i) then
		drag.active = true
		drag.start = Vector2.new(i.Position.X, i.Position.Y)
		drag.origin = root.Position
	end
end)
connect(UserInputService.InputChanged, function(i)
	if drag.active and isMove(i) then
		local d = Vector2.new(i.Position.X, i.Position.Y) - drag.start
		root.Position = UDim2.new(
			drag.origin.X.Scale, drag.origin.X.Offset + d.X,
			drag.origin.Y.Scale, drag.origin.Y.Offset + d.Y
		)
	end
end)
connect(UserInputService.InputEnded, function(i)
	if isPress(i) then drag.active = false end
end)

--------------------------------------------------------------------------
-- content container
--------------------------------------------------------------------------
local content = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(SIDEBAR_W, 0),
	Size = UDim2.fromOffset(CONTENT_W, RH),
}, main)

local moduleLabel = text(content, "", 11, Theme.Muted, LIGHT)
moduleLabel.Position = UDim2.fromOffset(22, 56)
moduleLabel.Size = UDim2.fromOffset(300, 20)

--------------------------------------------------------------------------
-- overlay: popups, tooltip, toasts, confirm
--------------------------------------------------------------------------
local overlay = create("Frame", {
	Name = "Overlay",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 100,
}, root)

local catcher = create("TextButton", {
	Selectable = false,
	Text = "",
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 50,
	Visible = false,
}, overlay)

local popup
local popupConns = {}
local function closePopup()
	if popup then popup:Destroy(); popup = nil end
	catcher.Visible = false
	for _, c in ipairs(popupConns) do c:Disconnect() end
	table.clear(popupConns)
end
catcher.Activated:Connect(closePopup)

local function openPopup(anchor, size, build)
	closePopup()
	catcher.Visible = true
	local s = uiScale.Scale
	local rel = (anchor.AbsolutePosition - root.AbsolutePosition) / s
	local asz = anchor.AbsoluteSize / s
	local x = math.clamp(rel.X + asz.X - size.X, 8, RW - size.X - 8)
	local y = rel.Y + asz.Y + 6
	if y + size.Y > RH - 8 then y = rel.Y - size.Y - 6 end
	popup = create("Frame", {
		BackgroundColor3 = Theme.Card,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BorderSizePixel = 0,
		ZIndex = 60,
	}, overlay)
	corner(popup, 11)
	stroke(popup, Theme.Accent, 1, 0.4)
	build(popup)
	return popup
end

-- tooltip
local tipActive = false
local tipFrame = create("Frame", {
	BackgroundColor3 = Theme.CardHead,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Visible = false,
	ZIndex = 300,
	BorderSizePixel = 0,
}, gui)
corner(tipFrame, 7)
stroke(tipFrame, Theme.Border, 1)
pad(tipFrame, 6, 10, 6, 10)
local tipLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Font = LIGHT,
	TextSize = 11,
	TextColor3 = Theme.Text,
	Text = "",
}, tipFrame)

-- toasts
local toastHolder = create("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(300, 400),
}, gui)
create("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, toastHolder)

local toastCount = 0
local function notify(title, msg)
	if Settings["misc.notify"] == false then return end
	toastCount += 1
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(290, 56),
		LayoutOrder = toastCount,
	}, toastHolder)
	local card = create("Frame", {
		BackgroundColor3 = Theme.Card,
		Position = UDim2.fromOffset(320, 0),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	}, holder)
	corner(card, 11)
	stroke(card, Theme.Border, 1)
	local bar = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		Position = UDim2.fromOffset(8, 12),
		Size = UDim2.new(0, 3, 1, -24),
		BorderSizePixel = 0,
	}, card)
	round(bar)
	local t = text(card, title, 12, Theme.Text, HEAD)
	t.Position = UDim2.fromOffset(22, 8)
	t.Size = UDim2.new(1, -30, 0, 18)
	local m = text(card, msg, 11, Theme.Muted, LIGHT)
	m.Position = UDim2.fromOffset(22, 28)
	m.Size = UDim2.new(1, -30, 0, 16)
	tween(card, { Position = UDim2.fromOffset(0, 0) }, 0.35)
	task.delay(3.2, function()
		if card.Parent then
			tween(card, { Position = UDim2.fromOffset(320, 0) }, 0.3)
			task.wait(0.32)
			holder:Destroy()
		end
	end)
end

-- confirm dialog
local function confirm(title, msg, yes)
	if not Settings["set.confirm"] then
		yes()
		return
	end
	closePopup()
	local dim = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
		BorderSizePixel = 0,
	}, overlay)
	local box = create("Frame", {
		BackgroundColor3 = Theme.Card,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MAIN_W / 2, RH / 2),
		Size = UDim2.fromOffset(360, 160),
		BorderSizePixel = 0,
	}, dim)
	corner(box, 14)
	stroke(box, Theme.Accent, 1.2, 0.2)
	local t = text(box, title, 15, Theme.Text, HEAD)
	t.Position = UDim2.fromOffset(20, 16)
	t.Size = UDim2.new(1, -40, 0, 24)
	local m = text(box, msg, 12, Theme.Muted, LIGHT)
	m.Position = UDim2.fromOffset(20, 46)
	m.Size = UDim2.new(1, -40, 0, 40)
	m.TextWrapped = true
	m.TextYAlignment = Enum.TextYAlignment.Top
	local no = makeButton(box, "Cancel", 100, 32, false)
	no.AnchorPoint = Vector2.new(1, 1)
	no.Position = UDim2.new(1, -132, 1, -16)
	local ok = makeButton(box, "Confirm", 100, 32, true)
	ok.AnchorPoint = Vector2.new(1, 1)
	ok.Position = UDim2.new(1, -20, 1, -16)
	no.Activated:Connect(function() dim:Destroy() end)
	ok.Activated:Connect(function()
		dim:Destroy()
		yes()
	end)
end

--------------------------------------------------------------------------
-- color picker
--------------------------------------------------------------------------
local quickColors = {
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 130, 200), Color3.fromRGB(176, 92, 232),
	Color3.fromRGB(100, 170, 255), Color3.fromRGB(255, 80, 80), Color3.fromRGB(120, 230, 140),
	Color3.fromRGB(255, 210, 90), Color3.fromRGB(20, 20, 24),
}

local function openColorPicker(anchor, key)
	local h, s, v = Settings[key]:ToHSV()
	local pop = openPopup(anchor, Vector2.new(214, 240), function() end)

	local svBox = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(190, 120),
		BorderSizePixel = 0,
	}, pop)
	corner(svBox, 8)
	local white = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	}, svBox)
	corner(white, 8)
	create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, white)
	local black = create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	}, svBox)
	corner(black, 8)
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
	}, black)
	local svKnob = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
	}, svBox)
	round(svKnob)
	stroke(svKnob, Color3.new(1, 1, 1), 2)

	local hueBar = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(12, 142),
		Size = UDim2.fromOffset(190, 12),
		BorderSizePixel = 0,
	}, pop)
	round(hueBar)
	local kps = {}
	for i = 0, 6 do
		table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 == 1 and 0.999 or i / 6, 1, 1)))
	end
	create("UIGradient", { Color = ColorSequence.new(kps) }, hueBar)
	local hueKnob = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(6, 18),
		BorderSizePixel = 0,
	}, hueBar)
	corner(hueKnob, 3)
	stroke(hueKnob, Color3.fromRGB(20, 10, 24), 1)

	local hexBox = create("TextBox", {
		Text = hex(Settings[key]),
		ClearTextOnFocus = false,
		Font = BODY,
		TextSize = 11,
		TextColor3 = Theme.Text,
		BackgroundColor3 = Theme.Field,
		Position = UDim2.fromOffset(12, 166),
		Size = UDim2.fromOffset(110, 26),
		BorderSizePixel = 0,
	}, pop)
	corner(hexBox, 7)
	stroke(hexBox, Theme.Border, 1)
	local prev = create("Frame", {
		BackgroundColor3 = Settings[key],
		Position = UDim2.fromOffset(130, 166),
		Size = UDim2.fromOffset(72, 26),
		BorderSizePixel = 0,
	}, pop)
	corner(prev, 7)

	local function update(fromHex)
		local c = Color3.fromHSV(h, s, v)
		svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svKnob.Position = UDim2.fromScale(s, 1 - v)
		hueKnob.Position = UDim2.fromScale(h, 0.5)
		prev.BackgroundColor3 = c
		if not fromHex then hexBox.Text = hex(c) end
		applySetting(key, c)
	end

	dragInput(svBox, function(p)
		s = math.clamp((p.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
		v = 1 - math.clamp((p.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
		update()
	end, popupConns)
	dragInput(hueBar, function(p)
		h = math.clamp((p.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
		update()
	end, popupConns)

	table.insert(popupConns, hexBox.FocusLost:Connect(function()
		local ok, c = pcall(Color3.fromHex, hexBox.Text)
		if ok and c then
			h, s, v = c:ToHSV()
			update(false)
		else
			hexBox.Text = hex(Settings[key])
		end
	end))

	for i, qc in ipairs(quickColors) do
		local q = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = qc,
			Position = UDim2.fromOffset(12 + (i - 1) * 24, 205),
			Size = UDim2.fromOffset(20, 20),
			BorderSizePixel = 0,
		}, pop)
		round(q)
		stroke(q, Theme.Border, 1)
		q.Activated:Connect(function()
			h, s, v = qc:ToHSV()
			update()
		end)
	end
	update()
end

--------------------------------------------------------------------------
-- live preview panel
--------------------------------------------------------------------------
local preview, previewGlow, previewGlowStroke, char, parts, renderPreview, updatePreviewVisible
-- These preview references are shared with the main render loop below the preview scope.
local avatarPreview: {[string]: any} = {}
local currentTab = "ESP" -- forward-declared so preview visibility can read the active page
do -- preview scope (keeps the main chunk under the 200-local limit)
local SW, SH = 240, 504
local PH = 560

previewGlow = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(MAIN_W + 14 - 3, -3),
	Size = UDim2.fromOffset(PREVIEW_W + 6, PH + 6),
}, root)
corner(previewGlow, 17)
previewGlowStroke = stroke(previewGlow, Theme.Accent, 6, 0.84)

preview = create("Frame", {
	Name = "Preview",
	BackgroundColor3 = Theme.Bg,
	Position = UDim2.fromOffset(MAIN_W + 14, 0),
	Size = UDim2.fromOffset(PREVIEW_W, PH),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, root)
corner(preview, 14)
local previewStroke = stroke(preview, Theme.Accent, 1.5, 0.05)
bindAccent(function()
	previewGlowStroke.Color = Theme.Accent
	previewStroke.Color = Theme.Accent
end)

do
	local ic, setIc = makeIcon("Misc", preview)
	ic.Position = UDim2.fromOffset(14, 13)
	bindAccent(function() setIc(Theme.Accent) end)
end
local pvTitle = text(preview, "Live Preview", 13, Theme.Text, HEAD)
pvTitle.Position = UDim2.fromOffset(42, 8)
pvTitle.Size = UDim2.new(1, -90, 0, 28)

local pvMin = create("TextButton", {
	Text = "",
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(28, 28),
}, preview)
create("Frame", {
	BackgroundColor3 = Theme.Muted,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(11, 1.6),
}, pvMin)

local screen = create("Frame", {
	BackgroundColor3 = Environments.Default,
	Position = UDim2.fromOffset(10, 46),
	Size = UDim2.fromOffset(SW, SH),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, preview)
corner(screen, 11)
stroke(screen, Theme.Border, 1)

local pvBadge = text(screen, "LILAC · PREVIEW", 8, Theme.Muted, BOLD)
pvBadge.Position = UDim2.fromOffset(10, 8)
pvBadge.Size = UDim2.fromOffset(150, 12)

local function newLine(parent, z)
	return create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 1),
		ZIndex = z or 1,
	}, parent)
end

local function setLine(f, x1, y1, x2, y2, th, col)
	local dx, dy = x2 - x1, y2 - y1
	f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), th)
	f.Rotation = math.deg(math.atan2(dy, dx))
	if col then f.BackgroundColor3 = col end
end

-- floor grid
local gridHolder = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, screen)
local gridLines = {}
do
	local hy = SH * 0.62
	for i = 0, 8 do
		local l = newLine(gridHolder)
		l.BackgroundTransparency = 0.82
		local x = -160 + i * (SW + 320) / 8
		setLine(l, SW / 2, hy, x, SH, 1)
		table.insert(gridLines, l)
	end
	for i = 1, 6 do
		local l = newLine(gridHolder)
		l.BackgroundTransparency = 0.82
		local y = hy + (SH - hy) * ((i / 6) ^ 1.7)
		setLine(l, 0, y, SW, y, 1)
		table.insert(gridLines, l)
	end
end

-- tracer (below the character)
local tracer = newLine(screen, 2)

-- character
char = create("Frame", {
	Name = "Char",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(SW / 2, SH / 2 + 6),
	Size = UDim2.fromOffset(150, 180),
	ZIndex = 3,
}, screen)
local charScale = create("UIScale", {}, char)

parts = {}
local function part(name, x, y, w, h, r)
	local f = create("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BorderSizePixel = 0,
	}, char)
	corner(f, r)
	local st = stroke(f, Color3.new(1, 1, 1), 1.5)
	st.Enabled = false
	parts[name] = { frame = f, stroke = st }
	return f
end
part("legL", 46, 108, 28, 70, 3)
part("legR", 76, 108, 28, 70, 3)
part("torso", 44, 38, 62, 68, 3)
local armL = part("armL", 21, 38, 22, 68, 3)
local armR = part("armR", 107, 38, 22, 68, 3)
local head = part("head", 57, 0, 36, 36, 7)

local function sleeve(parent)
	local f = create("Frame", { Size = UDim2.new(1, 0, 0, 40), BorderSizePixel = 0 }, parent)
	corner(f, 3)
	return f
end
local sleeveL, sleeveR = sleeve(armL), sleeve(armR)
local hair = create("Frame", { Size = UDim2.new(1, 0, 0, 11), BorderSizePixel = 0 }, head)
corner(hair, 5)
for _, ex in ipairs({ 9, 23 }) do
	local eye = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(18, 14, 22),
		Position = UDim2.fromOffset(ex, 19),
		Size = UDim2.fromOffset(4, 5),
		BorderSizePixel = 0,
	}, head)
	corner(eye, 2)
end

-- ESP: box
local box = create("Frame", {
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(-8, -8),
	Size = UDim2.fromOffset(166, 196),
	BorderSizePixel = 0,
	ZIndex = 4,
}, char)
local boxStroke = stroke(box, Color3.new(1, 1, 1), 1)
local boxCorners = {}
for _, a in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	for _, horizontal in ipairs({ true, false }) do
		local f = create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(a[1], a[2]),
			Position = UDim2.fromScale(a[1], a[2]),
			Visible = false,
		}, box)
		table.insert(boxCorners, { frame = f, h = horizontal })
	end
end

-- ESP: skeleton
local skelDefs = {
	{ 75, 36, 75, 108, 1 }, { 33, 50, 117, 50, 1 }, { 60, 108, 90, 108, 1 },
	{ 32, 50, 32, 104, 2 }, { 118, 50, 118, 104, 2 },
	{ 60, 108, 60, 178, 3 }, { 90, 108, 90, 178, 3 },
}
local skelLines = {}
for _, d in ipairs(skelDefs) do
	local l = newLine(char, 5)
	table.insert(skelLines, { f = l, d = d })
end

-- ESP: head marker
local crossH = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 18), ZIndex = 6 }, char)
local crossV = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 18), ZIndex = 6 }, char)
local circleM = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 18), ZIndex = 6 }, char)
round(circleM)
local circleStroke = stroke(circleM, Color3.new(1, 1, 1), 1)
local squareM = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 18), ZIndex = 6 }, char)
corner(squareM, 1)
local squareStroke = stroke(squareM, Color3.new(1, 1, 1), 1)

-- ESP: text
local function espLabel(parent)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = "",
		Font = BODY,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.35,
		ZIndex = 6,
	}, parent)
end
local nameLbl = espLabel(char)
nameLbl.AnchorPoint = Vector2.new(0.5, 0)
local hpTxt = espLabel(char)
hpTxt.AnchorPoint = Vector2.new(1, 0.5)
hpTxt.TextXAlignment = Enum.TextXAlignment.Right
hpTxt.Size = UDim2.fromOffset(34, 14)

local infoList = create("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromOffset(75, 192),
	Size = UDim2.fromOffset(220, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	ZIndex = 6,
}, char)
create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, infoList)
local weaponLbl, ammoLbl, distLbl = espLabel(infoList), espLabel(infoList), espLabel(infoList)
weaponLbl.LayoutOrder, ammoLbl.LayoutOrder, distLbl.LayoutOrder = 1, 2, 3
weaponLbl.Text, ammoLbl.Text = "AK-47", "24 / 90"
for _, l in ipairs({ weaponLbl, ammoLbl, distLbl }) do l.Size = UDim2.new(1, 0, 0, 16) end

-- ESP: health bar
local hpBack = create("Frame", {
	BackgroundColor3 = Color3.fromRGB(10, 8, 12),
	BorderSizePixel = 0,
	ZIndex = 5,
}, char)
corner(hpBack, 2)
local hpFill = create("Frame", {
	BackgroundColor3 = Color3.new(1, 1, 1),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	BorderSizePixel = 0,
}, hpBack)
corner(hpFill, 2)
local hpGrad = create("UIGradient", { Rotation = 90, Enabled = false }, hpFill)

-- ESP: look direction + arrows
local lookLine = newLine(char, 6)
local lookDot = create("Frame", {
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6),
	Position = UDim2.fromOffset(113, 12),
	ZIndex = 6,
}, char)
round(lookDot)
setLine(lookLine, 75, 18, 113, 12, 1.5)

local function arrow(x, y, rot)
	local f = create("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(11, 11),
		Rotation = rot,
		ZIndex = 6,
	}, screen)
	corner(f, 2)
	return f
end
local arrowR, arrowT, arrowL = arrow(SW - 16, 130, 45), arrow(SW / 2 + 40, 20, 45), arrow(16, 400, 45)

-- 3D player avatar preview. This replaces the old flat placeholder body with
-- a live clone of the local player's Roblox avatar, shown only in the ESP page.
local avatarViewport = create("ViewportFrame", {
	Name = "Avatar3DPreview",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(SW / 2, SH / 2 + 2),
	Size = UDim2.fromOffset(164, 244),
	ZIndex = 2,
	LightColor = Color3.fromRGB(255, 235, 255),
	Ambient = Color3.fromRGB(145, 120, 165),
	Visible = true,
}, screen)
avatarPreview.world = create("WorldModel", { Name = "AvatarWorld" }, avatarViewport)
avatarPreview.camera = create("Camera", { FieldOfView = 34 }, avatarViewport)
avatarViewport.CurrentCamera = avatarPreview.camera
local avatarRefreshBusy = false

local function refreshAvatarPreview()
	if avatarRefreshBusy then return end
	avatarRefreshBusy = true
	task.spawn(function()
		local ok, err = pcall(function()
			local liveCharacter = player.Character or player.CharacterAdded:Wait()
			if not liveCharacter or not liveCharacter.Parent then return end
			local wasArchivable = liveCharacter.Archivable
			liveCharacter.Archivable = true
			local clone = liveCharacter:Clone()
			liveCharacter.Archivable = wasArchivable
			if not clone then return end
			for _, obj in ipairs(clone:GetDescendants()) do
				if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
					obj:Destroy()
				elseif obj:IsA("BasePart") then
					obj.Anchored = true
					obj.CanCollide = false
					obj.CastShadow = false
				end
			end
			local hum = clone:FindFirstChildOfClass("Humanoid")
			if hum then
				local animator = hum:FindFirstChildOfClass("Animator")
				if animator then animator:Destroy() end
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			if avatarPreview.model then avatarPreview.model:Destroy() end
			clone.Parent = avatarPreview.world
			avatarPreview.model = clone
			local boxCF, boxSize = clone:GetBoundingBox()
			clone:PivotTo(clone:GetPivot() - boxCF.Position)
			avatarPreview.basePivot = clone:GetPivot()
			local height = math.max(boxSize.Y, 4)
			avatarPreview.camera.CFrame = CFrame.lookAt(Vector3.new(0, height * 0.12, height * 2.7), Vector3.new(0, height * 0.48, 0))
		end)
		if not ok then warn("[Lilac] 3D avatar preview refresh failed: " .. tostring(err)) end
		avatarRefreshBusy = false
	end)
end

-- Hide only the fake 2D body; retain its ESP overlay elements (box, labels,
-- health bar, skeleton and markers) so the preview settings still have feedback.
for _, item in pairs(parts) do item.frame.Visible = false end
sleeveL.Visible = false
sleeveR.Visible = false
hair.Visible = false
for _, child in ipairs(head:GetChildren()) do
	if child:IsA("GuiObject") then child.Visible = false end
end
refreshAvatarPreview()
connect(player.CharacterAdded, function()
	task.delay(0.75, refreshAvatarPreview)
end)

-- hit marker
local hitBars = {}
for i = 1, 4 do
	hitBars[i] = create("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(SW / 2, SH / 2 + 6),
		Visible = false,
		ZIndex = 9,
	}, screen)
end
local hitCatcher = create("TextButton", {
	Selectable = false,
	Text = "",
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 20,
}, screen)
local hitHint = text(screen, "click the preview to test the hit marker", 8, Theme.Muted, LIGHT, Enum.TextXAlignment.Center)
hitHint.Position = UDim2.new(0, 0, 1, -18)
hitHint.Size = UDim2.new(1, 0, 0, 12)

local hitToken = 0
hitCatcher.Activated:Connect(function()
	if not Settings["hit.enabled"] then return end
	hitToken += 1
	local my = hitToken
	local size = Settings["hit.size"]
	local col = Settings["hit.color"]
	local cx, cy = SW / 2, SH / 2 + 6
	local off = size * 0.9
	local dirs = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
	for i, b in ipairs(hitBars) do
		b.BackgroundColor3 = col
		b.BackgroundTransparency = 0
		b.Size = UDim2.fromOffset(size, 2)
		b.Rotation = (dirs[i][1] * dirs[i][2] > 0) and 45 or -45
		b.Position = UDim2.fromOffset(cx + dirs[i][1] * off, cy + dirs[i][2] * off)
		b.Visible = true
	end
	task.delay(0.12, function()
		if my ~= hitToken then return end
		for _, b in ipairs(hitBars) do
			tween(b, { BackgroundTransparency = 1 }, 0.25)
		end
		task.wait(0.26)
		if my == hitToken then
			for _, b in ipairs(hitBars) do b.Visible = false end
		end
	end)
end)

-- preview collapse
local pvCollapsed = false
function updatePreviewVisible()
	-- The live ESP preview belongs to the ESP page only; don't leave it
	-- floating beside Combat / Visuals / other pages.
	local show = Settings["set.preview"] ~= false
		and currentTab == "ESP"
		and not (main.Size.Y.Offset < 100)
	preview.Visible = show
	previewGlow.Visible = show
end
pvMin.Activated:Connect(function()
	pvCollapsed = not pvCollapsed
	screen.Visible = not pvCollapsed
	local h = pvCollapsed and 46 or PH
	tween(preview, { Size = UDim2.fromOffset(PREVIEW_W, h) }, 0.25)
	tween(previewGlow, { Size = UDim2.fromOffset(PREVIEW_W + 6, h + 6) }, 0.25)
end)

-- render everything from Settings
function renderPreview()
	local S = Settings
	if S["esp.enabled"] == nil then return end
	local on = S["esp.enabled"]
	local sc = S["char.scale"] / 100
	charScale.Scale = sc

	-- scene
	local base = (Environments[S["world.env"]] or Environments.Default):Lerp(S["world.tint"], 0.12)
	local f = 0.45 + (S["world.brightness"] / 100) * 0.8
	screen.BackgroundColor3 = Color3.new(math.min(base.R * f, 1), math.min(base.G * f, 1), math.min(base.B * f, 1))
	gridHolder.Visible = S["world.grid"]
	for _, l in ipairs(gridLines) do l.BackgroundColor3 = Theme.Accent2 end

	-- body + chams
	local cham = on and S["esp.highlight"]
	local cf, co = S["cham.fill"], S["cham.opacity"] / 100
	local function tint(c) return cham and c:Lerp(cf, co) or c end
	parts.head.frame.BackgroundColor3 = tint(S["char.skin"])
	parts.armL.frame.BackgroundColor3 = tint(S["char.skin"])
	parts.armR.frame.BackgroundColor3 = tint(S["char.skin"])
	parts.torso.frame.BackgroundColor3 = tint(S["char.shirt"])
	sleeveL.BackgroundColor3 = tint(S["char.shirt"])
	sleeveR.BackgroundColor3 = tint(S["char.shirt"])
	parts.legL.frame.BackgroundColor3 = tint(S["char.pants"])
	parts.legR.frame.BackgroundColor3 = tint(S["char.pants"])
	hair.BackgroundColor3 = tint(S["char.hair"])
	for _, p in pairs(parts) do
		p.stroke.Enabled = cham
		p.stroke.Color = S["cham.outline"]
	end

	-- box
	local th = S["bars.boxthick"]
	local asCorners = S["bars.boxstyle"] == "Corners"
	box.Visible = on and S["esp.box"]
	boxStroke.Enabled = not asCorners
	boxStroke.Thickness = th
	boxStroke.Color = S["bars.boxcolor"]
	box.BackgroundColor3 = S["bars.fillcolor"]
	box.BackgroundTransparency = S["bars.fillbox"] and (1 - S["bars.fillopacity"] / 100) or 1
	for _, c in ipairs(boxCorners) do
		c.frame.Visible = asCorners
		c.frame.BackgroundColor3 = S["bars.boxcolor"]
		c.frame.Size = c.h and UDim2.fromOffset(24, th) or UDim2.fromOffset(th, 24)
	end

	-- text styling
	local font = FontMap[S["fmt.font"]] or BODY
	local ts = S["fmt.size"]
	local tst = S["fmt.outline"] and 0.35 or 1
	for _, l in ipairs({ nameLbl, hpTxt, weaponLbl, ammoLbl, distLbl }) do
		l.Font = font
		l.TextSize = ts
		l.TextColor3 = S["fmt.color"]
		l.TextStrokeTransparency = tst
	end
	nameLbl.Visible = on and S["esp.names"]
	nameLbl.Text = player.DisplayName .. (S["esp.team"] and "  [TEAM]" or "")
	nameLbl.Size = UDim2.fromOffset(220, ts + 6)
	nameLbl.Position = UDim2.fromOffset(75, -12 - (ts + 6))
	weaponLbl.Visible = on and S["esp.weapon"]
	ammoLbl.Visible = on and S["esp.ammo"]
	distLbl.Visible = on and S["esp.distance"]
	distLbl.Text = S["fmt.unit"] == "Meters" and "42 m" or "150 studs"
	for _, l in ipairs({ weaponLbl, ammoLbl, distLbl }) do l.Size = UDim2.new(1, 0, 0, ts + 4) end

	-- health
	local hp = S["fmt.hp"] / 100
	local bw = S["bars.width"]
	local col = S["bars.low"]:Lerp(S["bars.high"], hp)
	local showBar = on and S["esp.vhealth"]
	hpBack.Visible = showBar
	hpBack.Size = UDim2.fromOffset(bw, 196)
	hpBack.Position = UDim2.fromOffset(-12 - bw, -8)
	hpFill.Size = UDim2.new(1, 0, hp, 0)
	hpGrad.Enabled = S["bars.gradient"]
	hpGrad.Color = ColorSequence.new(S["bars.high"], S["bars.low"])
	hpFill.BackgroundColor3 = S["bars.gradient"] and Color3.new(1, 1, 1) or col
	hpTxt.Visible = on and S["esp.healthinfo"]
	hpTxt.Text = tostring(S["fmt.hp"])
	hpTxt.TextColor3 = col
	hpTxt.Size = UDim2.fromOffset(34, ts + 2)
	hpTxt.Position = UDim2.fromOffset(-15 - (showBar and bw or 0), math.clamp(-8 + 196 * (1 - hp), 0, 180))

	-- look + arrows
	lookLine.Visible = on and S["esp.look"]
	lookDot.Visible = on and S["esp.look"]
	lookLine.BackgroundColor3 = Theme.Accent
	lookDot.BackgroundColor3 = Theme.Accent
	for _, a in ipairs({ arrowR, arrowT, arrowL }) do
		a.Visible = on and S["esp.arrows"]
		a.BackgroundColor3 = Theme.Accent
	end

	-- skeleton
	local sk = on and S["skel.enabled"]
	local colors = { S["skel.c1"], S["skel.c2"], S["skel.c3"] }
	for _, l in ipairs(skelLines) do
		local d = l.d
		l.f.Visible = sk
		setLine(l.f, d[1], d[2], d[3], d[4], S["skel.thick"], colors[d[5]])
	end

	-- head marker
	local hm = on and S["head.enabled"]
	local px = 4 + S["head.size"] * 2.2
	local ht = S["head.thick"]
	local hc = S["head.color"]
	local shape = S["head.shape"]
	local fillOn = S["head.fill"]
	crossH.Visible = hm and shape == "Cross"
	crossV.Visible = hm and shape == "Cross"
	crossH.BackgroundColor3, crossV.BackgroundColor3 = hc, hc
	crossH.Size = UDim2.fromOffset(px, ht)
	crossV.Size = UDim2.fromOffset(ht, px)
	circleM.Visible = hm and shape == "Circle"
	circleM.Size = UDim2.fromOffset(px, px)
	circleM.BackgroundColor3 = hc
	circleM.BackgroundTransparency = fillOn and 0 or 1
	circleStroke.Thickness, circleStroke.Color = ht, hc
	squareM.Visible = hm and shape == "Square"
	squareM.Size = UDim2.fromOffset(px, px)
	squareM.BackgroundColor3 = hc
	squareM.BackgroundTransparency = fillOn and 0 or 1
	squareStroke.Thickness, squareStroke.Color = ht, hc

	-- tracer
	tracer.Visible = on and S["tr.enabled"]
	local feetY = SH / 2 + 6 + 90 * sc + 2
	local oy = SH
	if S["tr.origin"] == "Center" then oy = SH / 2 elseif S["tr.origin"] == "Top" then oy = 0 end
	setLine(tracer, SW / 2, oy, SW / 2, feetY, S["tr.thick"], S["tr.color"])

end

end -- preview scope

--------------------------------------------------------------------------
-- rows
--------------------------------------------------------------------------
local sliderNudge = {}
local allRows = {}
local cardFrames = {}
local buildingKeys

local function reg(def)
	Settings[def.key] = def.default
	Defaults[def.key] = def.default
	if buildingKeys then table.insert(buildingKeys, def.key) end
end

local function makeRow(body, def)
	local height = def.type == "config" and 84 or 36
	local row = create("Frame", {
		Name = def.name or def.type,
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		BorderSizePixel = 0,
	}, body)
	bindAccent(function() row.BackgroundColor3 = Theme.Accent end)
	row:SetAttribute("Search", ((def.name or "") .. " " .. (def.tip or "")):lower())
	table.insert(allRows, { frame = row, base = height })

	create("Frame", {
		BackgroundColor3 = Theme.Border,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 1, -1),
		Size = UDim2.new(1, -24, 0, 1),
	}, row)

	row.MouseEnter:Connect(function()
		tween(row, { BackgroundTransparency = 0.93 }, 0.12)
		if Settings["misc.tips"] and def.tip and def.tip ~= "" then
			tipLabel.Text = def.tip
			tipFrame.Visible = true
			tipActive = true
		end
	end)
	row.MouseLeave:Connect(function()
		tween(row, { BackgroundTransparency = 1 }, 0.12)
		tipActive = false
		tipFrame.Visible = false
	end)

	if def.type ~= "config" then
		local lbl = text(row, def.name, 12, Theme.Text, BODY)
		lbl.Position = UDim2.fromOffset(14, 0)
		lbl.Size = UDim2.new(0.42, -14, 1, 0)
	end

	local kind = def.type
	local key = def.key

	if kind == "toggle" then
		reg(def)
		local track = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(40, 20),
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.Off,
		}, row)
		round(track)
		local glow = stroke(track, Theme.Accent, 3, 1)
		local knob = create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BorderSizePixel = 0,
		}, track)
		round(knob)
		local function render(v)
			tween(track, { BackgroundColor3 = v and Theme.Accent or Theme.Off })
			tween(knob, { Position = v and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
			tween(glow, { Transparency = v and 0.72 or 1 })
		end
		Controls[key] = { apply = render }
		bindAccent(function()
			track.BackgroundColor3 = Settings[key] and Theme.Accent or Theme.Off
			glow.Color = Theme.Accent
			knob.Position = Settings[key] and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			glow.Transparency = Settings[key] and 0.72 or 1
		end)
		track.Activated:Connect(function()
			local v = not Settings[key]
			render(v)
			commit(key, v)
		end)

	elseif kind == "slider" then
		reg(def)
		local mn, mx, step = def.min, def.max, def.step or 1
		local function fmt(v)
			if step >= 1 then return tostring(math.floor(v + 0.5)) end
			return string.format("%.1f", v)
		end
		local box = create("TextBox", {
			Text = fmt(def.default),
			ClearTextOnFocus = false,
			Font = BODY,
			TextSize = 11,
			TextColor3 = Theme.Text,
			BackgroundColor3 = Theme.Field,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(46, 24),
			BorderSizePixel = 0,
		}, row)
		corner(box, 7)
		stroke(box, Theme.Border, 1)
		local tPos = UDim2.new(0.42, 0, 0.5, 0)
		local tSize = UDim2.new(0.58, -84, 0, 6)
		local track = create("Frame", {
			BackgroundColor3 = Theme.Off,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = tPos,
			Size = tSize,
			BorderSizePixel = 0,
		}, row)
		round(track)
		local fill = create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(0, 1),
			BorderSizePixel = 0,
		}, track)
		round(fill)
		local grad = create("UIGradient", {}, fill)
		local knob = create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(13, 13),
			BorderSizePixel = 0,
		}, track)
		round(knob)
		local kglow = stroke(knob, Theme.Accent, 3, 0.6)
		bindAccent(function()
			grad.Color = ColorSequence.new(Theme.Accent2, Theme.Accent)
			kglow.Color = Theme.Accent
		end)
		local hit = create("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = tPos,
			Size = UDim2.new(0.58, -84, 0, 26),
		}, row)

		local function render(v)
			local frac = (v - mn) / (mx - mn)
			fill.Size = UDim2.fromScale(frac, 1)
			knob.Position = UDim2.fromScale(frac, 0.5)
			box.Text = fmt(v)
		end
		local function snap(v)
			v = mn + math.floor((v - mn) / step + 0.5) * step
			v = math.clamp(v, mn, mx)
			return math.floor(v * 1000 + 0.5) / 1000
		end
		Controls[key] = { apply = render }
		render(def.default)
		dragInput(hit, function(p)
			local frac = math.clamp((p.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			local v = snap(mn + frac * (mx - mn))
			if v ~= Settings[key] then
				render(v)
				commit(key, v)
			end
		end)
		sliderNudge[hit] = function(dir)
			local v = snap(Settings[key] + dir * math.max(step, (mx - mn) * 0.05))
			render(v)
			commit(key, v)
		end
		connect(box.FocusLost, function()
			local n = tonumber(box.Text)
			if n then
				n = snap(n)
				render(n)
				commit(key, n)
			else
				render(Settings[key])
			end
		end)

	elseif kind == "dropdown" then
		reg(def)
		local opts = def.options
		local btn = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Field,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(128, 26),
			BorderSizePixel = 0,
		}, row)
		corner(btn, 8)
		local btnStroke = stroke(btn, Theme.Border, 1)
		btn.MouseEnter:Connect(function() tween(btnStroke, { Color = Theme.Accent }, 0.12) end)
		btn.MouseLeave:Connect(function() tween(btnStroke, { Color = Theme.Border }, 0.12) end)
		local lab = text(btn, def.default, 11, Theme.Text, BODY)
		lab.Position = UDim2.fromOffset(11, 0)
		lab.Size = UDim2.new(1, -30, 1, 0)
		chevron(btn, UDim2.new(1, -15, 0.5, 0))
		Controls[key] = { apply = function(v) lab.Text = v end }
		btn.Activated:Connect(function()
			openPopup(btn, Vector2.new(140, #opts * 28 + 10), function(pop)
				local list = create("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(5, 5),
					Size = UDim2.new(1, -10, 1, -10),
				}, pop)
				create("UIListLayout", {}, list)
				for _, o in ipairs(opts) do
					local ob = create("TextButton", {
						Text = o,
						Font = BODY,
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = (o == Settings[key]) and Theme.Accent or Theme.Text,
						AutoButtonColor = false,
						BackgroundColor3 = Theme.CardHead,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 28),
						BorderSizePixel = 0,
					}, list)
					corner(ob, 7)
					pad(ob, 0, 8, 0, 10)
					ob.MouseEnter:Connect(function() tween(ob, { BackgroundTransparency = 0.2 }, 0.08) end)
					ob.MouseLeave:Connect(function() tween(ob, { BackgroundTransparency = 1 }, 0.08) end)
					ob.Activated:Connect(function()
						lab.Text = o
						commit(key, o)
						closePopup()
					end)
				end
			end)
		end)

	elseif kind == "color" then
		reg(def)
		local sw = create("TextButton", {
			Text = hex(def.default),
			AutoButtonColor = false,
			Font = BOLD,
			TextSize = 10,
			BackgroundColor3 = def.default,
			TextColor3 = contrast(def.default),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(84, 24),
			BorderSizePixel = 0,
		}, row)
		corner(sw, 8)
		local swGlow = stroke(sw, def.default, 3, 0.75)
		Controls[key] = {
			apply = function(c)
				sw.BackgroundColor3 = c
				sw.Text = hex(c)
				sw.TextColor3 = contrast(c)
				swGlow.Color = c
			end,
		}
		sw.Activated:Connect(function() openColorPicker(sw, key) end)

	elseif kind == "keybind" then
		reg(def)
		local btn = create("TextButton", {
			Text = Settings[key],
			AutoButtonColor = false,
			Font = BODY,
			TextSize = 11,
			TextColor3 = Theme.Text,
			BackgroundColor3 = Theme.Field,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(128, 26),
			BorderSizePixel = 0,
		}, row)
		corner(btn, 8)
		local kbStroke = stroke(btn, Theme.Border, 1)
		btn.MouseEnter:Connect(function() tween(kbStroke, { Color = Theme.Accent }, 0.12) end)
		btn.MouseLeave:Connect(function() tween(kbStroke, { Color = Theme.Border }, 0.12) end)
		Controls[key] = { apply = function(v) btn.Text = v end }
		btn.Activated:Connect(function()
			_G.__LilacBinding = true
			_G.__LilacBindStart = os.clock()
			btn.Text = "press a key..."
		end)
		connect(UserInputService.InputBegan, function(i)
			if not _G.__LilacBinding or btn.Text ~= "press a key..." then return end
			local name
			local ut = i.UserInputType
			if ut == Enum.UserInputType.Keyboard then
				name = i.KeyCode.Name
			elseif ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.MouseButton2 or ut == Enum.UserInputType.MouseButton3 then
				name = ut.Name
			elseif ut.Name:sub(1, 7) == "Gamepad" and i.KeyCode ~= Enum.KeyCode.Thumbstick1
				and i.KeyCode ~= Enum.KeyCode.Thumbstick2 and i.KeyCode ~= Enum.KeyCode.Unknown then
				name = i.KeyCode.Name
			end
			if not name then return end
			if os.clock() - (_G.__LilacBindStart or 0) < 0.15 then return end
			_G.__LilacBinding = false
			_G.__LilacBindTime = os.clock()
			if name == "Escape" then
				btn.Text = Settings[key]
			else
				btn.Text = name
				commit(key, name)
			end
		end)

	elseif kind == "button" then
		local b = makeButton(row, def.label or def.name, 128, 26, def.primary)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -14, 0.5, 0)
		b.Activated:Connect(function() def.fn() end)

	elseif kind == "config" then
		local tb = create("TextBox", {
			Text = "",
			PlaceholderText = "Export to generate a config string, or paste one and press Import",
			PlaceholderColor3 = Theme.Muted,
			ClearTextOnFocus = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Enum.Font.Code,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Text,
			BackgroundColor3 = Theme.Field,
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 30),
			BorderSizePixel = 0,
		}, row)
		corner(tb, 8)
		stroke(tb, Theme.Border, 1)
		pad(tb, 0, 10, 0, 10)
		local exp = makeButton(row, "Export", 100, 26, false)
		exp.Position = UDim2.fromOffset(12, 48)
		local imp = makeButton(row, "Import", 100, 26, true)
		imp.Position = UDim2.fromOffset(120, 48)
		def.hook(tb, exp, imp)
	end

	return row
end

--------------------------------------------------------------------------
-- cards + pages
--------------------------------------------------------------------------
local pages = {}

local function buildCard(col, def)
	local card = create("Frame", {
		Name = def.title,
		BackgroundColor3 = Theme.Card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = def.order or 1,
	}, col)
	corner(card, 12)
	stroke(card, Theme.Border, 1, 0.1)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 195, 212)),
	}, card)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)
	table.insert(cardFrames, card)

	local header = create("Frame", {
		BackgroundColor3 = Theme.CardHead,
		Size = UDim2.new(1, 0, 0, 40),
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, card)
	corner(header, 12)
	create("Frame", {
		BackgroundColor3 = Theme.CardHead,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 12),
	}, header)
	local dia = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
	}, header)
	corner(dia, 1)
	bindAccent(function() dia.BackgroundColor3 = Theme.Accent end)
	local headLine = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 2,
	}, header)
	create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, headLine)
	bindAccent(function() headLine.BackgroundColor3 = Theme.Accent end)
	local title = text(header, def.title, 13, Theme.Text, HEAD)
	title.Position = UDim2.fromOffset(36, 0)
	title.Size = UDim2.new(1, -80, 1, 0)

	local obj = { frame = card, title = def.title, bodies = {}, active = 1, searching = false, collapsed = false }
	local strip
	local pills = {}

	local function newBody(order)
		local b = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		}, card)
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, b)
		pad(b, 4, 0, 6, 0)
		return b
	end

	obj.layout = function()
		for i, b in ipairs(obj.bodies) do
			local show
			if obj.collapsed then show = false
			elseif obj.searching then show = b.hit
			else show = (i == obj.active) end
			b.frame.Visible = show
		end
		if strip then strip.Visible = (not obj.collapsed) and (not obj.searching) end
	end

	local function styleBody(tbl, rows)
		for _, r in ipairs(rows) do
			table.insert(tbl.rows, makeRow(tbl.frame, r))
		end
	end

	if def.tabs then
		strip = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 2,
		}, card)
		pad(strip, 6, 10, 0, 10)
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, strip)
		local function stylePills()
			for i, p in ipairs(pills) do
				local a = i == obj.active
				p.btn.TextColor3 = a and Theme.Accent or Theme.Muted
				p.btn.BackgroundColor3 = a and Theme.CardHead or Theme.Field
				p.stroke.Color = a and Theme.Accent or Theme.Border
				p.stroke.Transparency = a and 0.15 or 0
			end
		end
		for i, tdef in ipairs(def.tabs) do
			local body = { frame = newBody(2 + i), rows = {}, hit = false }
			table.insert(obj.bodies, body)
			styleBody(body, tdef.rows)
			local pill = create("TextButton", {
				Text = tdef.name,
				Font = BODY,
				TextSize = 9,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(#tdef.name * 5.6 + 18, 24),
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, strip)
			round(pill)
			local ps = stroke(pill, Theme.Border, 1)
			table.insert(pills, { btn = pill, stroke = ps })
			pill.Activated:Connect(function()
				obj.active = i
				stylePills()
				obj.layout()
			end)
		end
		bindAccent(stylePills)
	else
		local body = { frame = newBody(3), rows = {}, hit = false }
		table.insert(obj.bodies, body)
		styleBody(body, def.rows)
	end
	obj.layout()

	-- collapse button
	local cb = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
	}, header)
	create("Frame", {
		BackgroundColor3 = Theme.Muted,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 1.6),
	}, cb)
	local v1 = create("Frame", {
		BackgroundColor3 = Theme.Muted,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1.6, 11),
		Visible = false,
	}, cb)
	cb.Activated:Connect(function()
		obj.collapsed = not obj.collapsed
		v1.Visible = obj.collapsed
		obj.layout()
	end)

	return obj
end

local function buildPage(name, cardDefs)
	local scroll = create("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(22, 84),
		Size = UDim2.new(1, -44, 1, -96),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Visible = false,
	}, content)
	bindAccent(function() scroll.ScrollBarImageColor3 = Theme.Accent end)

	local wrap = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, scroll)
	pad(wrap, 2, 0, 16, 0)

	local cols = {}
	for i = 1, 2 do
		cols[i] = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new((i - 1) * 0.5, (i - 1) * 6, 0, 0),
			Size = UDim2.new(0.5, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, wrap)
		create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, cols[i])
	end

	local empty = text(scroll, "No settings match your search.", 12, Theme.Muted, LIGHT, Enum.TextXAlignment.Center)
	empty.Position = UDim2.fromOffset(0, 40)
	empty.Visible = false

	local page = { scroll = scroll, cards = {}, empty = empty, count = #cardDefs }
	buildingKeys = {}
	TabKeys[name] = buildingKeys
	for _, cd in ipairs(cardDefs) do
		table.insert(page.cards, buildCard(cols[cd.col or 1], cd))
	end
	buildingKeys = nil
	pages[name] = page
end

local function applySearch(page, q)
	if not page then return end
	q = q:lower()
	local searching = q ~= ""
	local visibleCards = 0
	for _, card in ipairs(page.cards) do
		local titleHit = searching and card.title:lower():find(q, 1, true) ~= nil
		local any = false
		for _, b in ipairs(card.bodies) do
			b.hit = false
			for _, r in ipairs(b.rows) do
				local m = (not searching) or titleHit or ((r:GetAttribute("Search") or ""):find(q, 1, true) ~= nil)
				r.Visible = m
				if m then b.hit = true end
			end
			if b.hit then any = true end
		end
		card.searching = searching
		card.frame.Visible = (not searching) or any
		card.layout()
		if card.frame.Visible then visibleCards += 1 end
	end
	page.empty.Visible = visibleCards == 0
end

connect(searchBox:GetPropertyChangedSignal("Text"), function()
	applySearch(pages[currentTab], searchBox.Text)
end)

--------------------------------------------------------------------------
-- actions used by buttons
--------------------------------------------------------------------------
local tabOrder = { "Combat", "ESP", "Visuals", "World", "Character", "Misc", "Settings" }

local function resetKeys(keys)
	bulk = true
	for _, k in ipairs(keys) do applySetting(k, Defaults[k]) end
	bulk = false
end

local function resetAll()
	local keys = {}
	for k in pairs(Defaults) do table.insert(keys, k) end
	resetKeys(keys)
end

local function serialize()
	local out = {}
	for k, v in pairs(Settings) do
		local t = typeof(v)
		if t == "Color3" then out[k] = hex(v)
		elseif t == "EnumItem" then out[k] = v.Name
		else out[k] = v end
	end
	return HttpService:JSONEncode(out)
end

local function importConfig(str)
	local ok, data = pcall(function() return HttpService:JSONDecode(str) end)
	if not ok or type(data) ~= "table" then return false end
	bulk = true
	for k, v in pairs(data) do
		local cur = Settings[k]
		if cur ~= nil then
			local t = typeof(cur)
			if t == "Color3" and type(v) == "string" then
				local ok2, c = pcall(Color3.fromHex, v)
				if ok2 and c then applySetting(k, c) end
			elseif t == "EnumItem" and type(v) == "string" then
				local ok2, kc = pcall(function() return Enum.KeyCode[v] end)
				if ok2 and kc then applySetting(k, kc) end
			elseif t == type(v) and (t == "boolean" or t == "number" or t == "string") then
				applySetting(k, v)
			end
		end
	end
	bulk = false
	return true
end

--------------------------------------------------------------------------
-- page definitions
--------------------------------------------------------------------------
local function T(key, name, default, tip) return { type = "toggle", key = key, name = name, default = default, tip = tip } end
local function S(key, name, min, max, default, tip, step) return { type = "slider", key = key, name = name, min = min, max = max, default = default, tip = tip, step = step } end
local function C(key, name, default, tip) return { type = "color", key = key, name = name, default = default, tip = tip } end
local function D(key, name, options, tip) return { type = "dropdown", key = key, name = name, options = options, default = options[1], tip = tip } end
local function B(name, label, fn, tip, primary) return { type = "button", name = name, label = label, fn = fn, tip = tip, primary = primary } end

local rgb = Color3.fromRGB

buildPage("Combat", {
	{ title = "Hit Feedback", col = 2, rows = {
		T("hit.enabled", "Hit Marker", true, "Click the preview to flash a hit marker"),
		C("hit.color", "Hit Color", rgb(255, 80, 100), "Hit marker color"),
		S("hit.size", "Hit Size", 4, 18, 8, "Hit marker size"),
	} },
	{ title = "Aimbot", col = 1, rows = {
		T("aim.enabled", "Aim Assist", false, "Pull the camera onto a target"),
		{ type = "keybind", key = "aim.key", name = "Aim Key", default = "Q", tip = "Keyboard key or mouse button" },
		{ type = "keybind", key = "aim.pad", name = "Controller Aim", default = "ButtonL2", tip = "Controller button" },
		D("aim.mode", "Activation", { "Hold", "Toggle", "Always" }, "Hold the key, toggle it, or always on"),
		S("aim.smooth", "Smoothness", 1, 30, 6, "1 = instant lock, higher = slower and softer"),
		D("aim.sync", "Camera Sync", { "Early", "Late" }, "If your scope looks off-center try Late, if it jitters try Early"),
		D("aim.bone", "Bone", { "Head", "Torso", "Closest" }, "Which body part to aim at"),
		T("aim.wall", "Wall Check", true, "Ignore targets behind geometry"),
		T("aim.team", "Team Check", true, "Ignore teammates"),
		T("aim.hpcheck", "Health Check", true, "Skip dead targets and targets with a ForceField"),
		S("aim.minhp", "Min Target HP %", 0, 100, 0, "Ignore targets below this health percent"),
	} },
	{ title = "FOV", col = 2, rows = {
		S("fov.size", "FOV Radius", 20, 400, 120, "Pixels around the cursor that can be targeted"),
		T("fov.draw", "Draw FOV Circle", true, "Show the activation circle"),
		C("fov.color", "FOV Color", rgb(240, 130, 200), "Circle color"),
	} },
	{ title = "Triggerbot", col = 2, rows = {
		T("trig.enabled", "Triggerbot", false, "Activates your equipped Tool when the cursor is on an enemy"),
		{ type = "keybind", key = "trig.key", name = "Trigger Key", default = "E", tip = "Keyboard key or mouse button" },
		{ type = "keybind", key = "trig.pad", name = "Controller Trigger", default = "ButtonR2", tip = "Controller button" },
		D("trig.mode", "Activation", { "Hold", "Toggle", "Always" }, "Hold the key, toggle it, or always on"),
		S("trig.delay", "Delay (ms)", 0, 300, 60, "Wait before firing"),
		T("trig.wall", "Wall Check", true, "Only fire at targets you can actually see"),
		T("trig.team", "Team Check", true, "Ignore teammates"),
		T("trig.hpcheck", "Health Check", true, "Skip dead targets and targets with a ForceField"),
	} },
	{ title = "Hitbox", col = 1, rows = {
		T("hb.enabled", "Hitbox Expander", false, "Enlarges enemy root parts on YOUR client only"),
		S("hb.size", "Hitbox Size", 2, 20, 6, "Studs"),
	} },
})

buildPage("ESP", {
	{ title = "ESP Options", col = 1, rows = {
		T("live.esp", "In-Game ESP", true, "Apply the ESP settings to real players (uses every ESP option here)"),
		T("esp.enabled", "ESP Enabled", true, "Master switch for every preview overlay"),
		T("esp.highlight", "Highlight", false, "Tint and outline the body (see Tracers / Chams)"),
		T("esp.box", "Box", true, "Bounding box around the model"),
		T("esp.names", "Names", true, "Name label above the box"),
		T("esp.healthinfo", "Health Info", true, "Numeric health next to the bar"),
		T("esp.vhealth", "Vertical Health", true, "Vertical health bar on the left"),
		T("esp.weapon", "Weapon Info", false, "Equipped item label"),
		T("esp.ammo", "Ammo Text", false, "Ammo counter label"),
		T("esp.distance", "Distance", false, "Distance label"),
		T("esp.look", "Look Direction", false, "Facing indicator from the head"),
		T("esp.arrows", "Arrows", false, "Off-screen style markers on the preview edge"),
		T("esp.team", "Show Teammates", false, "Adds a team tag to the name"),
	} },
	{ title = "Extra ESP", col = 2, tabs = {
		{ name = "Skeleton / Head", rows = {
			T("skel.enabled", "Skeleton", true, "Draw bones over the model"),
			S("skel.thick", "Skeleton thickness", 1, 5, 1, "Bone line thickness"),
			C("skel.c1", "Skeleton color 1", rgb(255, 255, 255), "Spine, shoulders, hips"),
			C("skel.c2", "Skeleton color 2", rgb(160, 100, 255), "Arms"),
			C("skel.c3", "Skeleton color 3", rgb(90, 160, 255), "Legs"),
			T("head.enabled", "Head marker", true, "Marker over the head"),
			C("head.color", "Head marker color", rgb(255, 80, 80), "Marker color"),
			D("head.shape", "Marker shape", { "Cross", "Circle", "Square" }, "Marker appearance"),
			T("head.fill", "Fill circle marker", false, "Fill circle / square shapes"),
			S("head.size", "Marker size", 1, 12, 5, "Marker size"),
			S("head.thick", "Marker thickness", 1, 5, 1, "Marker line thickness"),
		} },
		{ name = "Bars / Fill", rows = {
			S("bars.width", "Bar width", 2, 8, 3, "Health bar width"),
			C("bars.high", "Health high color", rgb(120, 255, 120), "Color at full health"),
			C("bars.low", "Health low color", rgb(255, 80, 100), "Color at low health"),
			T("bars.gradient", "Gradient bar", false, "Blend high and low colors along the bar"),
			D("bars.boxstyle", "Box style", { "Full", "Corners" }, "Outline or corner brackets"),
			C("bars.boxcolor", "Box color", rgb(255, 255, 255), "Box outline color"),
			S("bars.boxthick", "Box thickness", 1, 4, 1, "Box line thickness"),
			T("bars.fillbox", "Fill box", false, "Shade the inside of the box"),
			C("bars.fillcolor", "Fill color", rgb(160, 100, 255), "Box fill color"),
			S("bars.fillopacity", "Fill opacity", 5, 70, 20, "Box fill opacity"),
		} },
		{ name = "Tracers / Chams", rows = {
			T("tr.enabled", "Tracers", false, "Line from a screen anchor to the feet"),
			D("tr.origin", "Tracer origin", { "Bottom", "Center", "Top" }, "Where tracers start"),
			C("tr.color", "Tracer color", rgb(240, 130, 200), "Tracer color"),
			S("tr.thick", "Tracer thickness", 1, 4, 1, "Tracer line thickness"),
			C("cham.fill", "Chams fill", rgb(160, 100, 255), "Requires Highlight in ESP Options"),
			C("cham.outline", "Chams outline", rgb(255, 255, 255), "Requires Highlight in ESP Options"),
			S("cham.opacity", "Chams opacity", 0, 100, 45, "How strongly the fill tints the body"),
			T("cham.pulse", "Chams pulse", false, "Animate the outline"),
		} },
		{ name = "Formatting", rows = {
			S("fmt.size", "Text size", 9, 18, 12, "ESP text size"),
			C("fmt.color", "Text color", rgb(255, 255, 255), "ESP text color"),
			D("fmt.font", "Font", { "Gotham", "Code", "Merriweather" }, "ESP text font"),
			T("fmt.outline", "Text outline", true, "Outline ESP text"),
			D("fmt.unit", "Distance unit", { "Meters", "Studs" }, "Distance format"),
			S("fmt.hp", "Preview health", 0, 100, 75, "Health value shown in the preview"),
		} },
	} },
})

buildPage("Visuals", {
	{ title = "Interface", col = 1, rows = {
		T("vis.glow", "Glow Effects", true, "Window glow"),
		S("vis.glowstr", "Glow Strength", 0, 100, 70, "Glow intensity"),
		T("vis.anim", "Animated Glow", true, "Pulse the glow"),
		T("vis.petals", "Falling Petals", true, "Decorative petals"),
		S("vis.petalcount", "Petal Count", 1, 30, 14, "How many petals"),
		S("vis.opacity", "UI Opacity", 40, 100, 100, "Card opacity"),
	} },
	{ title = "Colors", col = 2, rows = {
		D("vis.preset", "Theme Preset", { "Lilac", "Rose", "Violet", "Ice" }, "Applies a color pair"),
		C("vis.accent", "Accent Color", Presets.Lilac[1], "Primary accent"),
		C("vis.accent2", "Secondary Accent", Presets.Lilac[2], "Secondary accent"),
	} },
})

buildPage("World", {
	{ title = "Scene", col = 1, rows = {
		D("world.env", "Environment", { "Default", "Night", "Soft", "Neon" }, "Preview backdrop"),
		S("world.brightness", "Brightness", 20, 100, 70, "Preview brightness"),
		T("world.grid", "Grid Floor", true, "Perspective grid"),
	} },
	{ title = "Lighting", col = 2, rows = {
		C("world.tint", "Ambient Tint", rgb(255, 255, 255), "Tints the backdrop"),
	} },
	{ title = "Ambiance", col = 2, rows = {
		T("amb.override", "Override Time", false, "Force the time of day"),
		S("amb.clock", "Clock Time", 0, 24, 14, "0 = midnight, 12 = noon", 0.5),
	} },
})

buildPage("Character", {
	{ title = "Appearance", col = 1, rows = {
		C("char.skin", "Skin", rgb(226, 190, 150), "Skin color"),
		C("char.shirt", "Shirt", rgb(24, 22, 30), "Shirt color"),
		C("char.pants", "Pants", rgb(70, 76, 66), "Pants color"),
		C("char.hair", "Hair", rgb(30, 24, 30), "Hair color"),
	} },
	{ title = "Animation", col = 2, rows = {
		T("char.sway", "Idle Sway", true, "Gentle idle motion"),
		S("char.speed", "Sway Speed", 0.5, 4, 1.5, "Sway speed", 0.1),
		S("char.scale", "Model Scale", 60, 130, 100, "Preview model scale"),
	} },
	{ title = "Movement", col = 1, rows = {
		T("mv.speed", "Speed", false, "Override WalkSpeed"),
		S("mv.speedval", "Walk Speed", 16, 120, 40, "Studs / second"),
		T("mv.fly", "Fly", false, "WASD + Space / LeftShift to move"),
		S("mv.flyspeed", "Fly Speed", 10, 150, 50, "Studs / second"),
		T("mv.infjump", "Infinite Jump", false, "Jump in mid-air"),
		T("mv.bhop", "Bunny Hop", false, "Hold Space to keep hopping"),
	} },
})

buildPage("Misc", {
	{ title = "Interface", col = 1, rows = {
		T("misc.notify", "Notifications", true, "Show toast messages"),
		T("misc.tips", "Tooltips", not isMobile, "Show setting descriptions on hover"),
		T("misc.compact", "Compact Mode", false, "Tighter row spacing"),
		T("misc.antiafk", "Anti-AFK", false, "Stops the idle timeout from kicking you"),
		B("Test Notification", "Send", function() notify("Lilac", "Notifications are working.") end, "Fire a test toast"),
	} },
	{ title = "Config", col = 2, rows = {
		{ type = "config", name = "Config", tip = "Copy or paste a config string", hook = function(tb, exp, imp)
			exp.Activated:Connect(function()
				tb.Text = serialize()
				notify("Config exported", "Select the text to copy it.")
			end)
			imp.Activated:Connect(function()
				if importConfig(tb.Text) then
					notify("Config imported", "Settings applied.")
				else
					notify("Import failed", "That config string isn't valid.")
				end
			end)
		end },
	} },
})

buildPage("Settings", {
	{ title = "Menu", col = 1, rows = {
		{ type = "keybind", key = "set.menukey", name = "Menu Key", default = "RightShift", tip = "Show / hide the window" },
		{ type = "keybind", key = "set.menupad", name = "Controller Menu", default = "ButtonSelect", tip = "Controller button that shows / hides the window" },
		S("set.scale", "Interface Scale", 70, 120, 100, "Window scale (%)"),
		T("set.preview", "Show Live Preview", not isMobile, "Show the preview panel"),
		T("set.lock", "Lock Window", false, "Disable dragging"),
		T("set.confirm", "Confirm Resets", true, "Ask before resetting"),
	} },
	{ title = "Reset", col = 2, rows = {
		D("set.resettab", "Section", tabOrder, "Which section to reset"),
		B("Reset Section", "Reset", function()
			local tab = Settings["set.resettab"]
			confirm("Reset " .. tab .. "?", "This restores every " .. tab .. " setting to its default.", function()
				resetKeys(TabKeys[tab])
				notify("Reset complete", tab .. " restored to defaults.")
			end)
		end, "Reset the selected section"),
		B("Reset All Settings", "Reset all", function()
			confirm("Reset everything?", "Every setting returns to its default.", function()
				resetAll()
				notify("Reset complete", "All settings restored.")
			end)
		end, "Reset every setting", true),
		B("Unload Interface", "Unload", function()
			confirm("Unload Lilac?", "This removes the menu and turns every feature off.", function()
				unload()
			end)
		end, "Remove Lilac completely"),
	} },
})

--------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------
local navButtons = {}
local function styleNav()
	for name, nb in pairs(navButtons) do
		local a = name == currentTab
		tween(nb.btn, { BackgroundTransparency = a and 0 or 1 }, 0.15)
		tween(nb.stroke, { Transparency = a and 0.05 or 1 }, 0.15)
		tween(nb.bar, { BackgroundTransparency = a and 0 or 1 }, 0.15)
		nb.label.TextColor3 = a and Theme.Text or Theme.Muted
		nb.stroke.Color = Theme.Accent
		nb.icon(a and Theme.Accent or Theme.Muted)
	end
end

local function selectTab(name)
	closePopup()
	currentTab = name
	pageTitle.Text = name
	searchBox.Text = ""
	for n, p in pairs(pages) do
		p.scroll.Visible = n == name
	end
	local p = pages[name]
	applySearch(p, "")
	p.scroll.CanvasPosition = Vector2.new(0, 0)
	p.scroll.Position = UDim2.fromOffset(22, 94)
	tween(p.scroll, { Position = UDim2.fromOffset(22, 84) }, 0.25)
	moduleLabel.Text = p.count .. (p.count == 1 and " module" or " modules")
	styleNav()
	if updatePreviewVisible then updatePreviewVisible() end
end

for i, name in ipairs(tabOrder) do
	if name == "Settings" then
		create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 99 }, navHolder)
	end
	local btn = create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.CardHead,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, isMobile and 34 or 42),
		LayoutOrder = name == "Settings" and 100 or i,
		BorderSizePixel = 0,
	}, navHolder)
	corner(btn, 12)
	local st = stroke(btn, Theme.Accent, 1.5, 1)
	local bar = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0.5, -9),
		Size = UDim2.fromOffset(3, 18),
	}, btn)
	round(bar)
	bindAccent(function() bar.BackgroundColor3 = Theme.Accent end)
	local ic, setIc = makeIcon(name, btn)
	ic.Position = UDim2.new(0, 14, 0.5, -10)
	local lb = text(btn, name, 13, Theme.Muted, BODY)
	lb.Position = UDim2.fromOffset(46, 0)
	lb.Size = UDim2.new(1, -50, 1, 0)
	navButtons[name] = { btn = btn, stroke = st, icon = setIc, label = lb, bar = bar }
	btn.Activated:Connect(function() selectTab(name) end)
	btn.MouseEnter:Connect(function()
		if currentTab ~= name then tween(btn, { BackgroundTransparency = 0.6 }, 0.1) end
	end)
	btn.MouseLeave:Connect(function()
		if currentTab ~= name then tween(btn, { BackgroundTransparency = 1 }, 0.1) end
	end)
end
bindAccent(styleNav)

--------------------------------------------------------------------------
-- handlers
--------------------------------------------------------------------------
Handlers["vis.accent"] = function(c) Theme.Accent = c; refreshAccent() end
Handlers["vis.accent2"] = function(c) Theme.Accent2 = c; refreshAccent() end
Handlers["vis.preset"] = function(v)
	if bulk then return end
	local p = Presets[v]
	if p then
		applySetting("vis.accent", p[1])
		applySetting("vis.accent2", p[2])
	end
end
Handlers["vis.opacity"] = function(v)
	local t = (100 - v) / 100 * 0.85
	for _, c in ipairs(cardFrames) do c.BackgroundTransparency = t end
	sidebar.BackgroundTransparency = 0.15 + (100 - v) / 100 * 0.6
end
Handlers["misc.compact"] = function(v)
	for _, r in ipairs(allRows) do
		r.frame.Size = UDim2.new(1, 0, 0, r.base - (v and 6 or 0))
	end
end
Handlers["set.scale"] = function(v) userScale = v / 100; fit() end
Handlers["set.preview"] = function() updatePreviewVisible() end

-- minimize / close
local minimized = false
minButton.Activated:Connect(function()
	minimized = not minimized
	closePopup()
	local h = minimized and 56 or RH
	tween(main, { Size = UDim2.fromOffset(MAIN_W, h) }, 0.28)
	tween(glowOuter, { Size = UDim2.fromOffset(MAIN_W + 10, h + 10) }, 0.28)
	tween(glowInner, { Size = UDim2.fromOffset(MAIN_W + 4, h + 4) }, 0.28)
	if minimized then
		preview.Visible = false
		previewGlow.Visible = false
	else
		task.delay(0.2, updatePreviewVisible)
	end
end)

-- open / close: release the first-person mouse while the menu is open.
-- Some first-person camera controllers re-apply LockCenter every frame, so a
-- one-time MouseBehavior assignment is not sufficient. Enforce the free cursor
-- after the camera update, then restore the state captured when the menu opened.
local prevMouseIcon = UserInputService.MouseIconEnabled
local prevMouseBehavior = UserInputService.MouseBehavior
local cursorEnforcerBound = false
local CURSOR_BIND_NAME = "LilacMenuCursorEnforcer"
local function bindMenuCursorEnforcer()
	if cursorEnforcerBound then return end
	cursorEnforcerBound = true
	RunService:BindToRenderStep(CURSOR_BIND_NAME, Enum.RenderPriority.Last.Value + 10, function()
		if not root.Parent or not root.Visible then return end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end
local function unbindMenuCursorEnforcer()
	if not cursorEnforcerBound then return end
	cursorEnforcerBound = false
	RunService:UnbindFromRenderStep(CURSOR_BIND_NAME)
end
local function setMenuOpen(open)
	root.Visible = open
	closePopup()
	dim.Visible = open
	dim.Modal = open
	if open then
		prevMouseIcon = UserInputService.MouseIconEnabled
		prevMouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		bindMenuCursorEnforcer()
		dim.BackgroundTransparency = 1
		tween(dim, { BackgroundTransparency = 0.45 }, 0.25)
		if lastInputIsPad() then GuiService.SelectedObject = navButtons[currentTab].btn end
	else
		unbindMenuCursorEnforcer()
		UserInputService.MouseBehavior = prevMouseBehavior
		UserInputService.MouseIconEnabled = prevMouseIcon
		GuiService.SelectedObject = nil
	end
	if updatePreviewVisible then updatePreviewVisible() end
end
table.insert(cleanups, function()
	unbindMenuCursorEnforcer()
	if root.Visible then
		UserInputService.MouseBehavior = prevMouseBehavior
		UserInputService.MouseIconEnabled = prevMouseIcon
	end
end)

-- floating open/close button (mobile only)
if isMobile then
	local mt = create("TextButton", {
		Name = "LilacToggle",
		Text = "L",
		Font = HEAD,
		TextSize = 20,
		TextColor3 = Theme.Accent,
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Card,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 400,
	}, gui)
	round(mt)
	local mtStroke = stroke(mt, Theme.Accent, 1.5, 0.1)
	bindAccent(function() mt.TextColor3 = Theme.Accent; mtStroke.Color = Theme.Accent end)
	mt.Activated:Connect(function() setMenuOpen(not root.Visible) end)
end

-- controller hint bar
local padHint = text(content, "A select    B back    LB / RB tabs    X / Y adjust sliders", 10, Theme.Muted, LIGHT, Enum.TextXAlignment.Right)
padHint.Position = UDim2.fromOffset(22, RH - 20)
padHint.Size = UDim2.fromOffset(CONTENT_W - 44, 14)
padHint.ZIndex = 5
padHint.Visible = lastInputIsPad()
connect(UserInputService.LastInputTypeChanged, function()
	padHint.Visible = lastInputIsPad()
	if root.Visible and lastInputIsPad() and not GuiService.SelectedObject then
		GuiService.SelectedObject = navButtons[currentTab].btn
	end
end)

-- menu key
connect(UserInputService.InputBegan, function(i)
	if _G.__LilacBinding or UserInputService:GetFocusedTextBox() then return end
	if os.clock() - (_G.__LilacBindTime or 0) < 0.3 then return end
	if matchesBind(i, Settings["set.menukey"]) or matchesBind(i, Settings["set.menupad"]) then
		setMenuOpen(not root.Visible)
	end
end)

-- controller navigation: LB/RB tabs, B back, X/Y nudge the selected slider
connect(UserInputService.InputBegan, function(i)
	if not root.Visible or _G.__LilacBinding then return end
	if i.UserInputType.Name:sub(1, 7) ~= "Gamepad" then return end
	local kc = i.KeyCode
	if kc == Enum.KeyCode.ButtonR1 or kc == Enum.KeyCode.ButtonL1 then
		local idx = table.find(tabOrder, currentTab) or 1
		idx = (idx - 1 + (kc == Enum.KeyCode.ButtonR1 and 1 or -1)) % #tabOrder + 1
		selectTab(tabOrder[idx])
	elseif kc == Enum.KeyCode.ButtonB then
		if popup then closePopup() else setMenuOpen(false) end
	elseif kc == Enum.KeyCode.ButtonX or kc == Enum.KeyCode.ButtonY then
		local fn = sliderNudge[GuiService.SelectedObject]
		if fn then fn(kc == Enum.KeyCode.ButtonY and 1 or -1) end
	end
end)

--------------------------------------------------------------------------
-- frame loop
--------------------------------------------------------------------------
local t0 = os.clock()
connect(RunService.Heartbeat, function(dt)
	if not root.Visible then return end
	local t = os.clock() - t0
	fpsSmooth = fpsSmooth + (1 / math.max(dt, 1e-3) - fpsSmooth) * 0.05
	fpsLabel.Text = string.format("%d FPS", math.floor(fpsSmooth + 0.5))

	-- glow
	local strength = Settings["vis.glow"] and (Settings["vis.glowstr"] / 100) or 0
	local pulse = Settings["vis.anim"] and (0.78 + 0.22 * math.sin(t * 1.8)) or 1
	glowOuterStroke.Transparency = 1 - 0.34 * strength * pulse
	glowInnerStroke.Transparency = 1 - 0.6 * strength * pulse
	previewGlowStroke.Transparency = 1 - 0.3 * strength * pulse

	-- petals
	local show = Settings["vis.petals"]
	local count = Settings["vis.petalcount"]
	for i, p in ipairs(petals) do
		local vis = show and i <= count
		p.f.Visible = vis
		if vis then
			p.y += p.vy * dt
			p.x += (p.vx + 10 * math.sin(t * 1.1 + p.ph)) * dt
			p.rot += p.vr * dt
			if p.y > RH + 20 or p.x < -20 then
				p.y = -20
				p.x = math.random(0, MAIN_W)
			end
			p.f.Position = UDim2.fromOffset(p.x, p.y)
			p.f.Rotation = p.rot
		end
	end

	-- preview
	if previewDirty then
		previewDirty = false
		renderPreview()
	end
	if avatarPreview.model and avatarPreview.model.Parent == avatarPreview.world and avatarPreview.basePivot then
		local spin = CFrame.Angles(0, math.rad((t * 32) % 360), 0)
		avatarPreview.model:PivotTo(spin * avatarPreview.basePivot)
	end
	if Settings["char.sway"] then
		char.Rotation = math.sin(t * Settings["char.speed"]) * 1.6
	elseif char.Rotation ~= 0 then
		char.Rotation = 0
	end
	if Settings["esp.enabled"] and Settings["esp.highlight"] and Settings["cham.pulse"] then
		local a = 0.45 + 0.35 * math.sin(t * 3)
		for _, p in pairs(parts) do p.stroke.Transparency = a end
	else
		for _, p in pairs(parts) do p.stroke.Transparency = 0 end
	end

	-- tooltip
	if tipActive then
		local m = UserInputService:GetMouseLocation()
		tipFrame.Position = UDim2.fromOffset(m.X + 16, m.Y + 18)
	end
end)

--------------------------------------------------------------------------
-- features (act on real players in your test game)
--------------------------------------------------------------------------
do -- features scope
local lp = player
local cam = workspace.CurrentCamera
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function() cam = workspace.CurrentCamera end)

local worldLayer = create("Frame", {
	Name = "World",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
	Active = false,
}, gui)

local function myChar() return lp.Character end
local function myHum()
	local c = myChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function myRoot()
	local c = myChar()
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function sameTeam(plr)
	return lp.Team ~= nil and plr.Team == lp.Team
end
local function alive(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return c, h, (h and h.Health > 0)
end
local function typing() return UserInputService:GetFocusedTextBox() ~= nil end

local toggled = { aim = false, trig = false }
local touchHeld = { aim = false, trig = false }
local function modeActive(p)
	local mode = Settings[p .. ".mode"]
	if mode == "Always" then return true end
	if mode == "Toggle" then return toggled[p] end
	return bindDown(Settings[p .. ".key"]) or bindDown(Settings[p .. ".pad"]) or touchHeld[p]
end
connect(UserInputService.InputBegan, function(i)
	if _G.__LilacBinding or typing() then return end
	for p in pairs(toggled) do
		if Settings[p .. ".mode"] == "Toggle"
			and (matchesBind(i, Settings[p .. ".key"]) or matchesBind(i, Settings[p .. ".pad"])) then
			toggled[p] = not toggled[p]
		end
	end
end)

-- on-screen AIM / FIRE buttons (mobile only)
local aimBtn, trigBtn
local function isTap(i)
	return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1
end
local function touchButton(p, label, pos)
	local b = create("TextButton", {
		Text = label,
		Font = BOLD,
		TextSize = 13,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Card,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 1),
		Position = pos,
		Size = UDim2.fromOffset(66, 66),
		Visible = false,
		ZIndex = 5,
	}, gui)
	round(b)
	stroke(b, Theme.Accent, 2, 0.2)
	b.InputBegan:Connect(function(i)
		if not isTap(i) then return end
		if Settings[p .. ".mode"] == "Toggle" then toggled[p] = not toggled[p] else touchHeld[p] = true end
	end)
	b.InputEnded:Connect(function(i)
		if isTap(i) then touchHeld[p] = false end
	end)
	return b
end
if isMobile then
	aimBtn = touchButton("aim", "AIM", UDim2.new(1, -24, 1, -210))
	trigBtn = touchButton("trig", "FIRE", UDim2.new(1, -108, 1, -250))
end

local function targetOk(plr, c, hum, p)
	if not hum or hum.Health <= 0 then return false end
	if Settings[p .. ".team"] and sameTeam(plr) then return false end
	if Settings[p .. ".hpcheck"] then
		if c:FindFirstChildOfClass("ForceField") then return false end
		if p == "aim" and hum.Health / math.max(hum.MaxHealth, 1) * 100 < Settings["aim.minhp"] then return false end
	end
	return true
end

-- ESP -------------------------------------------------------------------
local espObjs = {}

local BONES_R15 = {
	{ "Head", "UpperTorso", 1 }, { "UpperTorso", "LowerTorso", 1 },
	{ "UpperTorso", "LeftUpperArm", 2 }, { "LeftUpperArm", "LeftLowerArm", 2 }, { "LeftLowerArm", "LeftHand", 2 },
	{ "UpperTorso", "RightUpperArm", 2 }, { "RightUpperArm", "RightLowerArm", 2 }, { "RightLowerArm", "RightHand", 2 },
	{ "LowerTorso", "LeftUpperLeg", 3 }, { "LeftUpperLeg", "LeftLowerLeg", 3 }, { "LeftLowerLeg", "LeftFoot", 3 },
	{ "LowerTorso", "RightUpperLeg", 3 }, { "RightUpperLeg", "RightLowerLeg", 3 }, { "RightLowerLeg", "RightFoot", 3 },
}
local BONES_R6 = {
	{ "Head", "Torso", 1 }, { "Torso", "Left Arm", 2 }, { "Torso", "Right Arm", 2 },
	{ "Torso", "Left Leg", 3 }, { "Torso", "Right Leg", 3 },
}

local function lineBetween(f, a, b, th, col)
	local d = b - a
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, th)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = col
end

local function destroyEsp(o)
	if not o then return end
	for _, k in ipairs({ "hl", "bb", "tracer", "lookLine", "lookDot", "arrow" }) do
		if o[k] then o[k]:Destroy() end
	end
	for _, f in pairs(o.headM or {}) do
		if typeof(f) == "Instance" then f:Destroy() end
	end
	for _, f in ipairs(o.bones or {}) do f:Destroy() end
end

local function buildEsp(plr, char)
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not rootPart or not hum then return nil end
	local o = { char = char, root = rootPart, hum = hum }
	o.hl = create("Highlight", {
		Adornee = char, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false,
	}, char)
	o.bb = create("BillboardGui", {
		Adornee = rootPart, AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false,
		Size = UDim2.fromScale(4.5, 6.2),
	}, char)
	o.box = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, o.bb)
	o.boxStroke = stroke(o.box, Color3.new(1, 1, 1), 1)
	o.corners = {}
	for _, a in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for _, h in ipairs({ true, false }) do
			local f = create("Frame", {
				BorderSizePixel = 0, AnchorPoint = Vector2.new(a[1], a[2]),
				Position = UDim2.fromScale(a[1], a[2]), Visible = false,
			}, o.bb)
			table.insert(o.corners, { f = f, h = h })
		end
	end
	o.hpBack = create("Frame", { BackgroundColor3 = Color3.fromRGB(10, 8, 12), BorderSizePixel = 0 }, o.bb)
	o.hpFill = create("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BorderSizePixel = 0,
	}, o.hpBack)
	o.hpGrad = create("UIGradient", { Rotation = 90, Enabled = false }, o.hpFill)
	local function lbl()
		return create("TextLabel", {
			BackgroundTransparency = 1, Text = "", TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = Color3.new(0, 0, 0),
		}, o.bb)
	end
	o.name = lbl()
	o.name.AnchorPoint = Vector2.new(0.5, 1)
	o.name.Position = UDim2.new(0.5, 0, 0, -2)
	o.hpTxt = lbl()
	o.hpTxt.AnchorPoint = Vector2.new(1, 0.5)
	o.hpTxt.TextXAlignment = Enum.TextXAlignment.Right
	o.info = create("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y,
	}, o.bb)
	create("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, o.info)
	o.weapon, o.ammo, o.dist = lbl(), lbl(), lbl()
	for i, l in ipairs({ o.weapon, o.ammo, o.dist }) do l.Parent = o.info; l.LayoutOrder = i end
	o.tracer = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Visible = false,
	}, worldLayer)
	local function sq()
		return create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false }, worldLayer)
	end
	o.bones = {}
	o.headM = { h = sq(), v = sq(), circle = sq(), square = sq() }
	round(o.headM.circle)
	corner(o.headM.square, 1)
	o.headM.circleStroke = stroke(o.headM.circle, Color3.new(1, 1, 1), 1)
	o.headM.squareStroke = stroke(o.headM.square, Color3.new(1, 1, 1), 1)
	o.lookLine = sq()
	o.lookDot = sq()
	o.lookDot.Size = UDim2.fromOffset(6, 6)
	round(o.lookDot)
	o.arrow = sq()
	o.arrow.Size = UDim2.fromOffset(11, 11)
	o.arrow.Rotation = 45
	corner(o.arrow, 2)
	return o
end

local function hideEsp(o)
	o.hl.Enabled = false
	o.bb.Enabled = false
	o.tracer.Visible = false
	o.lookLine.Visible = false
	o.lookDot.Visible = false
	o.arrow.Visible = false
	for _, f in pairs(o.headM) do
		if typeof(f) == "Instance" and f:IsA("GuiObject") then f.Visible = false end
	end
	for _, f in ipairs(o.bones) do f.Visible = false end
end

local function updateEsp(plr, o, t)
	local S = Settings
	local d = (cam.CFrame.Position - o.root.Position).Magnitude
	o.bb.Enabled = true
	-- chams
	o.hl.Enabled = S["esp.highlight"]
	o.hl.FillColor = S["cham.fill"]
	o.hl.FillTransparency = 1 - S["cham.opacity"] / 100
	o.hl.OutlineColor = S["cham.outline"]
	o.hl.OutlineTransparency = S["cham.pulse"] and (0.45 + 0.35 * math.sin(t * 3)) or 0
	-- box
	local th = S["bars.boxthick"]
	local asCorners = S["bars.boxstyle"] == "Corners"
	o.box.Visible = S["esp.box"]
	o.boxStroke.Enabled = not asCorners
	o.boxStroke.Thickness = th
	o.boxStroke.Color = S["bars.boxcolor"]
	o.box.BackgroundColor3 = S["bars.fillcolor"]
	o.box.BackgroundTransparency = S["bars.fillbox"] and (1 - S["bars.fillopacity"] / 100) or 1
	for _, c in ipairs(o.corners) do
		c.f.Visible = S["esp.box"] and asCorners
		c.f.BackgroundColor3 = S["bars.boxcolor"]
		c.f.Size = c.h and UDim2.fromOffset(14, th) or UDim2.fromOffset(th, 14)
	end
	-- text
	local font, ts = FontMap[S["fmt.font"]] or BODY, S["fmt.size"]
	local tst = S["fmt.outline"] and 0.35 or 1
	for _, l in ipairs({ o.name, o.hpTxt, o.weapon, o.ammo, o.dist }) do
		l.Font, l.TextSize, l.TextColor3, l.TextStrokeTransparency = font, ts, S["fmt.color"], tst
	end
	o.name.Visible = S["esp.names"]
	o.name.Text = plr.DisplayName .. ((S["esp.team"] and sameTeam(plr)) and "  [TEAM]" or "")
	o.name.Size = UDim2.fromOffset(220, ts + 6)
	local tool = o.char:FindFirstChildOfClass("Tool")
	o.weapon.Visible = S["esp.weapon"]
	o.weapon.Text = tool and tool.Name or "None"
	o.ammo.Visible = S["esp.ammo"]
	o.ammo.Text = tool and tostring(tool:GetAttribute("Ammo") or "-") or "-"
	o.dist.Visible = S["esp.distance"]
	o.dist.Text = S["fmt.unit"] == "Meters" and string.format("%d m", math.floor(d * 0.28 + 0.5)) or string.format("%d studs", math.floor(d + 0.5))
	for _, l in ipairs({ o.weapon, o.ammo, o.dist }) do l.Size = UDim2.new(1, 0, 0, ts + 4) end
	-- health
	local hp = math.clamp(o.hum.Health / math.max(o.hum.MaxHealth, 1), 0, 1)
	local bw = S["bars.width"]
	local col = S["bars.low"]:Lerp(S["bars.high"], hp)
	o.hpBack.Visible = S["esp.vhealth"]
	o.hpBack.Size = UDim2.new(0, bw, 1, 0)
	o.hpBack.Position = UDim2.new(0, -4 - bw, 0, 0)
	o.hpFill.Size = UDim2.fromScale(1, hp)
	o.hpGrad.Enabled = S["bars.gradient"]
	o.hpGrad.Color = ColorSequence.new(S["bars.high"], S["bars.low"])
	o.hpFill.BackgroundColor3 = S["bars.gradient"] and Color3.new(1, 1, 1) or col
	o.hpTxt.Visible = S["esp.healthinfo"]
	o.hpTxt.Text = tostring(math.floor(o.hum.Health))
	o.hpTxt.TextColor3 = col
	o.hpTxt.Size = UDim2.fromOffset(34, ts + 2)
	o.hpTxt.Position = UDim2.new(0, -8 - (S["esp.vhealth"] and bw or 0), 1 - hp, 0)
	-- tracer
	if S["tr.enabled"] then
		local v, on = cam:WorldToViewportPoint(o.root.Position - Vector3.new(0, 3, 0))
		if on then
			local vs = cam.ViewportSize
			local origin = Vector2.new(vs.X / 2, vs.Y)
			if S["tr.origin"] == "Center" then origin = vs / 2 elseif S["tr.origin"] == "Top" then origin = Vector2.new(vs.X / 2, 0) end
			local to = Vector2.new(v.X, v.Y)
			local diff = to - origin
			o.tracer.Visible = true
			o.tracer.Position = UDim2.fromOffset((origin.X + to.X) / 2, (origin.Y + to.Y) / 2)
			o.tracer.Size = UDim2.fromOffset(diff.Magnitude, S["tr.thick"])
			o.tracer.Rotation = math.deg(math.atan2(diff.Y, diff.X))
			o.tracer.BackgroundColor3 = S["tr.color"]
		else
			o.tracer.Visible = false
		end
	else
		o.tracer.Visible = false
	end

	-- skeleton
	local sk = S["skel.enabled"]
	local list = o.char:FindFirstChild("UpperTorso") and BONES_R15 or BONES_R6
	local cols = { S["skel.c1"], S["skel.c2"], S["skel.c3"] }
	for idx, b in ipairs(list) do
		local fr = o.bones[idx]
		if not fr then
			fr = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false }, worldLayer)
			o.bones[idx] = fr
		end
		local p1, p2 = o.char:FindFirstChild(b[1]), o.char:FindFirstChild(b[2])
		if sk and p1 and p2 then
			local a = cam:WorldToViewportPoint(p1.Position)
			local c2 = cam:WorldToViewportPoint(p2.Position)
			if a.Z > 0 and c2.Z > 0 then
				lineBetween(fr, Vector2.new(a.X, a.Y), Vector2.new(c2.X, c2.Y), S["skel.thick"], cols[b[3]])
				fr.Visible = true
			else
				fr.Visible = false
			end
		else
			fr.Visible = false
		end
	end
	for idx = #list + 1, #o.bones do o.bones[idx].Visible = false end

	-- head marker
	local M = o.headM
	local headPart = o.char:FindFirstChild("Head")
	local showHead = false
	if S["head.enabled"] and headPart then
		local v = cam:WorldToViewportPoint(headPart.Position)
		if v.Z > 0 then
			showHead = true
			local px = 4 + S["head.size"] * 2.2
			local ht, hc, shape, fillOn = S["head.thick"], S["head.color"], S["head.shape"], S["head.fill"]
			local pos = UDim2.fromOffset(v.X, v.Y)
			M.h.Position, M.v.Position, M.circle.Position, M.square.Position = pos, pos, pos, pos
			M.h.Visible, M.v.Visible = shape == "Cross", shape == "Cross"
			M.h.BackgroundColor3, M.v.BackgroundColor3 = hc, hc
			M.h.Size, M.v.Size = UDim2.fromOffset(px, ht), UDim2.fromOffset(ht, px)
			M.circle.Visible = shape == "Circle"
			M.circle.Size = UDim2.fromOffset(px, px)
			M.circle.BackgroundColor3 = hc
			M.circle.BackgroundTransparency = fillOn and 0 or 1
			M.circleStroke.Thickness, M.circleStroke.Color = ht, hc
			M.square.Visible = shape == "Square"
			M.square.Size = UDim2.fromOffset(px, px)
			M.square.BackgroundColor3 = hc
			M.square.BackgroundTransparency = fillOn and 0 or 1
			M.squareStroke.Thickness, M.squareStroke.Color = ht, hc
		end
	end
	if not showHead then
		M.h.Visible, M.v.Visible, M.circle.Visible, M.square.Visible = false, false, false, false
	end

	-- look direction
	local lookShown = false
	if S["esp.look"] and headPart then
		local a = cam:WorldToViewportPoint(headPart.Position)
		local b = cam:WorldToViewportPoint(headPart.Position + headPart.CFrame.LookVector * 4)
		if a.Z > 0 and b.Z > 0 then
			lookShown = true
			lineBetween(o.lookLine, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), 1.5, Theme.Accent)
			o.lookDot.Position = UDim2.fromOffset(b.X, b.Y)
			o.lookDot.BackgroundColor3 = Theme.Accent
		end
	end
	o.lookLine.Visible, o.lookDot.Visible = lookShown, lookShown

	-- off-screen arrow
	local rv = cam:WorldToViewportPoint(o.root.Position)
	local offscreen = false
	if S["esp.arrows"] then
		local vs = cam.ViewportSize
		offscreen = rv.Z <= 0 or rv.X < 0 or rv.Y < 0 or rv.X > vs.X or rv.Y > vs.Y
		if offscreen then
			local center = vs / 2
			local dir = Vector2.new(rv.X, rv.Y) - center
			if rv.Z <= 0 then dir = -dir end
			if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end
			dir = dir.Unit
			local sc = math.min((vs.X / 2 - 30) / math.max(math.abs(dir.X), 1e-3), (vs.Y / 2 - 30) / math.max(math.abs(dir.Y), 1e-3))
			local p = center + dir * sc
			o.arrow.Position = UDim2.fromOffset(p.X, p.Y)
			o.arrow.BackgroundColor3 = Theme.Accent
		end
	end
	o.arrow.Visible = offscreen
end

-- targeting -------------------------------------------------------------
local function boneParts(c, mode)
	local head = c:FindFirstChild("Head")
	local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or c:FindFirstChild("HumanoidRootPart")
	if mode == "Head" then return { head } elseif mode == "Torso" then return { torso } end
	return { head, torso }
end

local function visibleFrom(part, c)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { myChar(), c }
	local origin = cam.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, params) == nil
end

local function aimRef()
	local vs = cam.ViewportSize
	local firstPerson = (cam.Focus.Position - cam.CFrame.Position).Magnitude < 1.5
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or firstPerson or isMobile or lastInputIsPad() then
		return Vector2.new(vs.X / 2, vs.Y / 2)
	end
	return UserInputService:GetMouseLocation()
end

local function bestTarget()
	local S = Settings
	local m = aimRef()
	local best, bestD = nil, S["fov.size"]
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local c, hum, ok = alive(plr)
			if ok and targetOk(plr, c, hum, "aim") then
				for _, part in ipairs(boneParts(c, S["aim.bone"])) do
					local v, on = cam:WorldToViewportPoint(part.Position)
					if on then
						local dist = (Vector2.new(v.X, v.Y) - m).Magnitude
						if dist < bestD and (not S["aim.wall"] or visibleFrom(part, c)) then
							best, bestD = part, dist
						end
					end
				end
			end
		end
	end
	return best
end

-- FOV circle
local fovCircle = create("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false,
}, worldLayer)
round(fovCircle)
local fovStroke = stroke(fovCircle, Color3.new(1, 1, 1), 1.5)

-- sticky target: stay on the same player while the key is held (no jumping between bones)
local sticky
local function stickyValid(part)
	if not part or not part.Parent then return false end
	local c = part:FindFirstAncestorOfClass("Model")
	local plr = c and Players:GetPlayerFromCharacter(c)
	if not plr then return false end
	local ch, hum, ok = alive(plr)
	if not ok or not targetOk(plr, ch, hum, "aim") then return false end
	local v, on = cam:WorldToViewportPoint(part.Position)
	if not on or (Vector2.new(v.X, v.Y) - aimRef()).Magnitude > Settings["fov.size"] * 1.5 then return false end
	if Settings["aim.wall"] and not visibleFrom(part, ch) then return false end
	return true
end

-- aimbot: rotates the view toward the target relative to the crosshair/cursor.
-- Works whether your game's camera keeps our rotation or recomputes it every frame.
local lastAim = os.clock()
local aimF, lastBase, lastSet = 0, nil, nil
local function aimStep(which)
	local S = Settings
	if S["aim.sync"] ~= which then return end
	local nowT = os.clock()
	local dtA = math.min(nowT - lastAim, 0.1)
	lastAim = nowT

	if S["aim.enabled"] and not typing() and modeActive("aim") then
		local target = sticky
		if not stickyValid(target) then
			target = bestTarget()
			sticky = target
			aimF = 0
		end
		if target then
			local ref = aimRef()
			local cf = cam.CFrame
			local persisted = false
			if lastSet and lastBase then
				local d1 = math.acos(math.clamp(cf.LookVector:Dot(lastSet.LookVector), -1, 1))
				local d2 = math.acos(math.clamp(cf.LookVector:Dot(lastBase.LookVector), -1, 1))
				persisted = d1 <= d2
			end
			local under = cam:ViewportPointToRay(ref.X, ref.Y).Direction.Unit
			local want = (target.Position - cf.Position).Unit
			local axis = under:Cross(want)
			local angle = math.acos(math.clamp(under:Dot(want), -1, 1))
			local alpha = S["aim.smooth"] <= 1 and 1 or (1 - math.exp(-dtA * 40 / S["aim.smooth"]))
			local frac
			if persisted then
				aimF = 0
				frac = alpha
			else
				aimF = aimF + (1 - aimF) * alpha
				frac = aimF
			end
			if axis.Magnitude > 1e-5 and angle > 1e-4 then
				local rot = CFrame.fromAxisAngle(axis.Unit, angle * frac)
				local newCf = CFrame.new(cf.Position) * rot * (cf - cf.Position)
				lastBase, lastSet = cf, newCf
				cam.CFrame = newCf
			else
				lastBase, lastSet = cf, cf
			end
		else
			lastBase, lastSet, aimF = nil, nil, 0
		end
	else
		sticky, aimF, lastBase, lastSet = nil, 0, nil, nil
	end
end
RunService:BindToRenderStep("LilacAimE", Enum.RenderPriority.Camera.Value + 1, function() aimStep("Early") end)
RunService:BindToRenderStep("LilacAimL", Enum.RenderPriority.Last.Value, function() aimStep("Late") end)
table.insert(cleanups, function()
	RunService:UnbindFromRenderStep("LilacAimE")
	RunService:UnbindFromRenderStep("LilacAimL")
end)

-- fov circle + triggerbot (not camera work)
local trigBusy = false
connect(RunService.RenderStepped, function()
	local S = Settings
	local ref = aimRef()
	-- The gameplay FOV indicator must not disappear just because the menu closes.
	fovCircle.Visible = S["aim.enabled"] and S["fov.draw"]
	fovCircle.Position = UDim2.fromOffset(ref.X, ref.Y)
	fovCircle.Size = UDim2.fromOffset(S["fov.size"] * 2, S["fov.size"] * 2)
	fovStroke.Color = S["fov.color"]

	if S["trig.enabled"] and not trigBusy and not typing() and modeActive("trig") then
		local ray = cam:ViewportPointToRay(ref.X, ref.Y)
		local params = RaycastParams.new()
		if S["trig.wall"] then
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { myChar() }
		else
			local list = {}
			for _, pl in ipairs(Players:GetPlayers()) do
				if pl ~= lp and pl.Character then table.insert(list, pl.Character) end
			end
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = list
		end
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local plr = hit and Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model"))
		if plr and plr ~= lp then
			local c, hum, ok = alive(plr)
			local tool = myChar() and myChar():FindFirstChildOfClass("Tool")
			if ok and tool and targetOk(plr, c, hum, "trig") then
				trigBusy = true
				task.delay(S["trig.delay"] / 1000, function()
					if tool.Parent then tool:Activate() end
					task.wait(0.1)
					trigBusy = false
				end)
			end
		end
	end
end)

-- hitbox expander (client-side only) ---------------------------------------
local origSizes = {}
local function restoreHitboxes()
	for part, o in pairs(origSizes) do
		if part.Parent then part.Size, part.Transparency, part.CanCollide = o.size, o.trans, o.collide end
	end
	table.clear(origSizes)
end
table.insert(cleanups, restoreHitboxes)

-- movement -----------------------------------------------------------------
local savedSpeed, flyVel
local function stopFly()
	if flyVel then flyVel:Destroy(); flyVel = nil end
end
table.insert(cleanups, stopFly)
table.insert(cleanups, function()
	local h = myHum()
	if h and savedSpeed then h.WalkSpeed = savedSpeed end
end)

connect(UserInputService.JumpRequest, function()
	if Settings["mv.infjump"] then
		local h = myHum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

-- ambiance ------------------------------------------------------------------
local origClock = Lighting.ClockTime
local ambOn = false
table.insert(cleanups, function() if ambOn then Lighting.ClockTime = origClock end end)

-- anti-afk (own game only) ----------------------------------------------------
connect(lp.Idled, function()
	if Settings["misc.antiafk"] then
		local ok, vu = pcall(function() return game:GetService("VirtualUser") end)
		if ok and vu then
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end
	end
end)

-- main feature loop ------------------------------------------------------------
connect(RunService.Heartbeat, function()
	local S = Settings
	local t = os.clock()

	-- mobile on-screen buttons
	if isMobile then
		local show = not root.Visible
		for p, b in pairs({ aim = aimBtn, trig = trigBtn }) do
			b.Visible = show and S[p .. ".enabled"] and S[p .. ".mode"] ~= "Always"
			local on = toggled[p] or touchHeld[p]
			b.BackgroundColor3 = on and Theme.Accent or Theme.Card
			b.TextColor3 = on and Color3.fromRGB(24, 10, 28) or Theme.Text
		end
	end

	-- ESP
	local want = S["live.esp"] and S["esp.enabled"]
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local o = espObjs[plr]
			local c, _, ok = alive(plr)
			if o and o.char ~= c then destroyEsp(o); o = nil; espObjs[plr] = nil end
			if want and c and ok then
				if not o then o = buildEsp(plr, c); espObjs[plr] = o end
				if o then
					if sameTeam(plr) and not S["esp.team"] then
						hideEsp(o)
					else
						local okU, errU = pcall(updateEsp, plr, o, t)
						if not okU and not _G.__LilacEspWarned then
							_G.__LilacEspWarned = true
							warn("[Lilac] ESP error: " .. tostring(errU))
						end
					end
				end
			elseif o then
				hideEsp(o)
			end
		end
	end
	for plr, o in pairs(espObjs) do
		if not plr.Parent then destroyEsp(o); espObjs[plr] = nil end
	end

	-- hitboxes
	if S["hb.enabled"] then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and not sameTeam(plr) then
				local c, _, ok = alive(plr)
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r and ok then
					origSizes[r] = origSizes[r] or { size = r.Size, trans = r.Transparency, collide = r.CanCollide }
					r.Size = Vector3.new(S["hb.size"], S["hb.size"], S["hb.size"])
					r.Transparency, r.CanCollide = 0.7, false
				end
			end
		end
	elseif next(origSizes) then
		restoreHitboxes()
	end

	-- speed
	local hum, rootPart = myHum(), myRoot()
	if hum then
		if S["mv.speed"] then
			savedSpeed = savedSpeed or hum.WalkSpeed
			hum.WalkSpeed = S["mv.speedval"]
		elseif savedSpeed then
			hum.WalkSpeed = savedSpeed
			savedSpeed = nil
		end
		if S["mv.bhop"] and not typing() and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			hum.Jump = true
		end
	end

	-- fly
	if S["mv.fly"] and rootPart and hum then
		if not flyVel or flyVel.Parent ~= rootPart then
			stopFly()
			flyVel = create("BodyVelocity", { MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero }, rootPart)
		end
		local dir = Vector3.zero
		if not typing() then
			local cf = cam.CFrame
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
		end
		flyVel.Velocity = dir.Magnitude > 0 and dir.Unit * S["mv.flyspeed"] or Vector3.zero
	else
		stopFly()
	end

	-- ambiance
	if S["amb.override"] then
		if not ambOn then origClock = Lighting.ClockTime; ambOn = true end
		Lighting.ClockTime = S["amb.clock"]
	elseif ambOn then
		Lighting.ClockTime = origClock
		ambOn = false
	end
end)

table.insert(cleanups, function()
	for _, o in pairs(espObjs) do destroyEsp(o) end
	table.clear(espObjs)
end)

end -- features scope

--------------------------------------------------------------------------
-- go
--------------------------------------------------------------------------
bulk = true
for key, h in pairs(Handlers) do h(Settings[key]) end
bulk = false
renderPreview()
updatePreviewVisible()
selectTab("ESP")
setMenuOpen(true)
print("[Lilac] loaded")
notify("Lilac loaded", "Press " .. Settings["set.menukey"] .. " to hide or show.")
