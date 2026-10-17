
--[[
    LILAC UI
    Standalone Luau interface
    UI/demo settings only. No game manipulation.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remove previous instance
local previous = playerGui:FindFirstChild("LilacUI")
if previous then
    previous:Destroy()
end

local Theme = {
    Background = Color3.fromRGB(12, 8, 15),
    Sidebar = Color3.fromRGB(19, 12, 23),
    Panel = Color3.fromRGB(28, 17, 32),
    Panel2 = Color3.fromRGB(37, 22, 42),
    Border = Color3.fromRGB(76, 43, 73),
    Accent = Color3.fromRGB(235, 128, 196),
    Accent2 = Color3.fromRGB(179, 91, 225),
    Text = Color3.fromRGB(244, 225, 242),
    Muted = Color3.fromRGB(157, 133, 158),
    Off = Color3.fromRGB(62, 43, 64),
    Green = Color3.fromRGB(160, 231, 161),
}

local Settings = {}
local Controls = {}
local CurrentTab = "ESP"

local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 10)
    }, parent)
end

local function stroke(parent, color, thickness, transparency)
    return create("UIStroke", {
        Color = color or Theme.Border,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    }, parent)
end

local function padding(parent, amount)
    return create("UIPadding", {
        PaddingTop = UDim.new(0, amount),
        PaddingBottom = UDim.new(0, amount),
        PaddingLeft = UDim.new(0, amount),
        PaddingRight = UDim.new(0, amount),
    }, parent)
end

local function tween(object, properties, duration)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

local function label(parent, text, size, color, font)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = text,
        TextSize = size or 13,
        TextColor3 = color or Theme.Text,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 0, 22),
    }, parent)
end

local function newPanel(parent, title, height)
    local panel = create("Frame", {
        BackgroundColor3 = Theme.Panel,
        Size = UDim2.new(1, 0, 0, height or 300),
        BorderSizePixel = 0,
    }, parent)

    corner(panel, 13)
    stroke(panel, Theme.Border, 1)

    local header = create("Frame", {
        BackgroundColor3 = Theme.Panel2,
        Size = UDim2.new(1, 0, 0, 39),
        BorderSizePixel = 0,
    }, panel)

    corner(header, 13)

    create("Frame", {
        BackgroundColor3 = Theme.Panel2,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -10),
        Size = UDim2.new(1, 0, 0, 10),
    }, header)

    local titleLabel = label(header, title, 13, Theme.Text,
        Enum.Font.GothamMedium)
    titleLabel.Position = UDim2.new(0, 14, 0, 0)
    titleLabel.Size = UDim2.new(1, -45, 1, 0)

    local body = create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 46),
        Size = UDim2.new(1, -20, 1, -54),
    }, panel)

    return panel, body
end

-- Screen GUI
local gui = create("ScreenGui", {
    Name = "LilacUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- Main window
local main = create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 1100, 0, 650),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)

corner(main, 15)
stroke(main, Theme.Accent, 1.5)

local outerGlow = create("UIStroke", {
    Color = Theme.Accent,
    Thickness = 5,
    Transparency = 0.83,
}, main)

-- Drag window using top header
local dragging = false
local dragStart
local startPosition

local dragBar = create("Frame", {
    Name = "DragBar",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(1, 0, 0, 44),
    ZIndex = 20,
}, main)

dragBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- Sidebar
local sidebar = create("Frame", {
    Name = "Sidebar",
    BackgroundColor3 = Theme.Sidebar,
    Size = UDim2.new(0, 190, 1, 0),
    BorderSizePixel = 0,
}, main)

local logo = create("Frame", {
    BackgroundColor3 = Theme.Panel2,
    Position = UDim2.new(0, 12, 0, 12),
    Size = UDim2.new(0, 36, 0, 36),
    BorderSizePixel = 0,
}, sidebar)
corner(logo, 11)
stroke(logo, Theme.Accent, 1)

label(logo, "L", 24, Theme.Accent, Enum.Font.GothamBold).TextXAlignment =
    Enum.TextXAlignment.Center

local brand = label(sidebar, "Lilac", 19, Theme.Text,
    Enum.Font.GothamBold)
brand.Position = UDim2.new(0, 57, 0, 12)
brand.Size = UDim2.new(1, -65, 0, 22)

local edition = label(sidebar, "PREMIUM INTERFACE", 8, Theme.Muted)
edition.Position = UDim2.new(0, 58, 0, 34)
edition.Size = UDim2.new(1, -65, 0, 15)

local navHolder = create("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 10, 0, 76),
    Size = UDim2.new(1, -20, 0, 350),
}, sidebar)

local navLayout = create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, navHolder)

local tabIcons = {
    Combat = "⚔",
    ESP = "◎",
    Visuals = "✧",
    World = "◉",
    Character = "♙",
    Misc = "▦",
    Settings = "⚙",
}

local tabNames = {
    "Combat", "ESP", "Visuals", "World",
    "Character", "Misc", "Settings"
}

local navButtons = {}

local profile = create("Frame", {
    BackgroundColor3 = Theme.Panel,
    Position = UDim2.new(0, 10, 1, -61),
    Size = UDim2.new(1, -20, 0, 48),
    BorderSizePixel = 0,
}, sidebar)
corner(profile, 10)

local avatar = create("Frame", {
    BackgroundColor3 = Theme.Panel2,
    Position = UDim2.new(0, 7, 0, 7),
    Size = UDim2.new(0, 34, 0, 34),
    BorderSizePixel = 0,
}, profile)
corner(avatar, 8)

label(avatar, "L", 17, Theme.Accent, Enum.Font.GothamBold)
    .TextXAlignment = Enum.TextXAlignment.Center

local profileName = label(profile, player.DisplayName, 11, Theme.Text,
    Enum.Font.GothamMedium)
profileName.Position = UDim2.new(0, 48, 0, 6)
profileName.Size = UDim2.new(1, -53, 0, 17)

local profileStatus = label(profile, "Lilac UI Demo", 9, Theme.Muted)
profileStatus.Position = UDim2.new(0, 48, 0, 23)
profileStatus.Size = UDim2.new(1, -53, 0, 15)

-- Main content
local content = create("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 190, 0, 0),
    Size = UDim2.new(1, -190, 1, 0),
}, main)

local topbar = create("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 22, 0, 8),
    Size = UDim2.new(1, -44, 0, 39),
}, content)

local pageTitle = label(topbar, "ESP", 17, Theme.Text,
    Enum.Font.GothamMedium)
pageTitle.Size = UDim2.new(0.5, 0, 1, 0)

local closeButton = create("TextButton", {
    Text = "×",
    Font = Enum.Font.Gotham,
    TextSize = 24,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    Size = UDim2.new(0, 30, 0, 30),
}, topbar)

closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local minimizeButton = create("TextButton", {
    Text = "−",
    Font = Enum.Font.Gotham,
    TextSize = 21,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -32, 0, 0),
    Size = UDim2.new(0, 28, 0, 30),
}, topbar)

local minimized = false
minimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    sidebar.Visible = not minimized
    content.Visible = not minimized
    main.Size = minimized and UDim2.new(0, 180, 0, 44)
        or UDim2.new(0, 1100, 0, 650)
end)

-- Search
local search = create("TextBox", {
    Name = "Search",
    PlaceholderText = "⌕   Search settings...",
    Text = "",
    ClearTextOnFocus = false,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Theme.Text,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.Sidebar,
    Position = UDim2.new(0, 0, 0, 45),
    Size = UDim2.new(1, 0, 0, 34),
    BorderSizePixel = 0,
}, content)
corner(search, 9)
stroke(search, Theme.Border, 1)
padding(search, 10)

-- Page body
local pageBody = create("ScrollingFrame", {
    Name = "PageBody",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, 91),
    Size = UDim2.new(1, 0, 1, -101),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
}, content)

local pagePadding = padding(pageBody, 0)
pagePadding.PaddingRight = UDim.new(0, 6)
pagePadding.PaddingBottom = UDim.new(0, 12)

local pageLayout = create("UIListLayout", {
    Padding = UDim.new(0, 12),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, pageBody)

-- Settings data: all switches are UI/demo preferences.
local Definitions = {
    Combat = {
        {type="toggle", name="Combat Interface", desc="Show the combat settings panel", default=true},
        {type="toggle", name="Keybind Hints", desc="Display keybind helper labels", default=true},
        {type="slider", name="Interface Scale", desc="Scale the controls", min=75, max=125, default=100},
        {type="dropdown", name="Input Display", desc="Choose the input display style", options={"Compact","Detailed","Minimal"}},
        {type="toggle", name="Show Status Indicators", desc="Show demo status indicators", default=true},
    },
    ESP = {
        {type="toggle", name="ESP Enabled", desc="Enable the ESP demo settings", default=true},
        {type="toggle", name="Highlight", desc="Highlight style preview", default=false},
        {type="toggle", name="Box", desc="Show a sample box in the preview", default=true},
        {type="toggle", name="Names", desc="Display a sample name label", default=true},
        {type="toggle", name="Health Info", desc="Display sample health information", default=true},
        {type="toggle", name="Vertical Health", desc="Show a vertical health bar preview", default=true},
        {type="toggle", name="Weapon Info", desc="Display a sample equipment label", default=false},
        {type="toggle", name="Ammo Text", desc="Display sample ammunition text", default=false},
        {type="toggle", name="Distance", desc="Display a sample distance label", default=false},
        {type="toggle", name="Look Direction", desc="Show a direction indicator preview", default=false},
        {type="toggle", name="Arrows", desc="Show sample directional markers", default=false},
        {type="toggle", name="Show Teammates", desc="Include teammates in the demo preview", default=false},
        {type="section", name="Extra ESP"},
        {type="toggle", name="Skeleton / Head", desc="Skeleton marker demo setting", default=false},
        {type="toggle", name="Bars / Fill", desc="Fill and bar styling preview", default=true},
        {type="toggle", name="Tracers / Chams", desc="Tracer and material style preview", default=false},
        {type="slider", name="Skeleton Thickness", desc="Preview line thickness", min=1, max=5, default=1},
        {type="color", name="Skeleton Color 1", desc="Primary preview color", default=Color3.fromRGB(255,255,255)},
        {type="color", name="Skeleton Color 2", desc="Secondary preview color", default=Color3.fromRGB(160,100,255)},
        {type="color", name="Skeleton Color 3", desc="Accent preview color", default=Color3.fromRGB(100,170,255)},
        {type="toggle", name="Head Marker", desc="Show a sample head marker", default=true},
        {type="color", name="Head Marker Color", desc="Head marker preview color", default=Color3.fromRGB(255,80,100)},
        {type="dropdown", name="Marker Shape", desc="Select a marker appearance", options={"Cross","Circle","Square"}},
        {type="toggle", name="Fill Circle Marker", desc="Use a filled marker in the preview", default=false},
        {type="slider", name="Marker Size", desc="Marker preview size", min=1, max=12, default=5},
        {type="slider", name="Marker Thickness", desc="Marker preview thickness", min=1, max=5, default=1},
    },
    Visuals = {
        {type="toggle", name="Animated Background", desc="Animate the interface accent", default=true},
        {type="toggle", name="Glow Effects", desc="Show panel glow styling", default=true},
        {type="toggle", name="Rounded Cards", desc="Use rounded interface panels", default=true},
        {type="slider", name="UI Opacity", desc="Interface background opacity", min=40, max=100, default=100},
        {type="color", name="Accent Color", desc="Primary interface accent", default=Theme.Accent},
        {type="color", name="Secondary Accent", desc="Secondary interface accent", default=Theme.Accent2},
        {type="dropdown", name="Theme Preset", desc="Choose an interface color preset", options={"Lilac","Rose","Violet","Ice"}},
    },
    World = {
        {type="toggle", name="World Preview", desc="Show the world preview panel", default=true},
        {type="toggle", name="Environment Card", desc="Display environment information", default=true},
        {type="toggle", name="Lighting Preview", desc="Show lighting demo settings", default=false},
        {type="slider", name="Preview Brightness", desc="Adjust preview brightness", min=0, max=100, default=70},
        {type="dropdown", name="Environment Preset", desc="Choose a sample environment", options={"Default","Night","Soft","Neon"}},
    },
    Character = {
        {type="toggle", name="Character Card", desc="Display a character demo card", default=true},
        {type="toggle", name="Movement HUD", desc="Show movement information in the UI", default=false},
        {type="toggle", name="Input HUD", desc="Show sample input information", default=true},
        {type="slider", name="HUD Scale", desc="Adjust the demo HUD size", min=50, max=150, default=100},
        {type="dropdown", name="HUD Position", desc="Choose the demo HUD position", options={"Left","Center","Right"}},
    },
    Misc = {
        {type="toggle", name="Notifications", desc="Show interface notifications", default=true},
        {type="toggle", name="Tooltips", desc="Show setting descriptions", default=true},
        {type="toggle", name="Sound Effects", desc="Enable interface sound preference", default=false},
        {type="toggle", name="Compact Mode", desc="Use a more compact layout preference", default=false},
        {type="dropdown", name="Language", desc="Interface language preference", options={"English","Spanish","French"}},
        {type="button", name="Reset Demo Settings", desc="Restore all default UI settings"},
    },
    Settings = {
        {type="toggle", name="Show Live Preview", desc="Display the live preview card", default=true},
        {type="toggle", name="Remember UI Position", desc="Remember position during this session", default=true},
        {type="toggle", name="Confirm Resets", desc="Ask before resetting demo settings", default=true},
        {type="dropdown", name="Interface Scale", desc="Choose the interface scale", options={"90%","100%","110%"}},
        {type="button", name="Reset Current Tab", desc="Restore current tab defaults"},
        {type="button", name="Reset All Settings", desc="Restore every demo setting"},
    },
}

-- Build controls
local buildPage

local function registerControl(name, value, default)
    Settings[name] = value
    Controls[name] = {value=value, default=default}
end

local function makeRow(parent, definition)
    local kind = definition.type
    local name = definition.name

    if kind == "section" then
        local section = label(parent, name, 13, Theme.Accent,
            Enum.Font.GothamBold)
        section.Size = UDim2.new(1, 0, 0, 28)
        return section
    end

    local row = create("Frame", {
        Name = "Setting_" .. name:gsub("%W", ""),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.15,
        Size = UDim2.new(1, 0, 0, kind == "slider" and 67 or 55),
        BorderSizePixel = 0,
    }, parent)

    row:SetAttribute("SettingName", name)
    row:SetAttribute("SearchText", (name .. " " .. (definition.desc or "")):lower())

    local title = label(row, name, 12, Theme.Text,
        Enum.Font.GothamMedium)
    title.Position = UDim2.new(0, 8, 0, kind == "slider" and 5 or 4)
    title.Size = UDim2.new(1, -130, 0, 21)

    local description = label(row, definition.desc or "", 9, Theme.Muted)
    description.Position = UDim2.new(0, 8, 0, 25)
    description.Size = UDim2.new(1, -140, 0, 18)

    if kind == "toggle" then
        registerControl(name, definition.default, definition.default)

        local track = create("TextButton", {
            Name = "Switch",
            Text = "",
            AutoButtonColor = false,
            BackgroundColor3 = definition.default and Theme.Accent or Theme.Off,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.new(0, 38, 0, 20),
            BorderSizePixel = 0,
        }, row)
        corner(track, 12)

        local knob = create("Frame", {
            BackgroundColor3 = Color3.new(1,1,1),
            Position = definition.default and UDim2.new(1,-17,0,3)
                or UDim2.new(0,3,0,3),
            Size = UDim2.new(0,14,0,14),
            BorderSizePixel = 0,
        }, track)
        corner(knob, 10)

        track.MouseButton1Click:Connect(function()
            local value = not Settings[name]
            Settings[name] = value
            Controls[name].value = value
            tween(track, {
                BackgroundColor3 = value and Theme.Accent or Theme.Off
            })
            tween(knob, {
                Position = value and UDim2.new(1,-17,0,3)
                    or UDim2.new(0,3,0,3)
            })
        end)

    elseif kind == "slider" then
        registerControl(name, definition.default, definition.default)

        local min = definition.min or 0
        local max = definition.max or 100

        local valueLabel = label(row, tostring(definition.default), 10,
            Theme.Accent, Enum.Font.GothamMedium)
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Position = UDim2.new(1,-44,0,5)
        valueLabel.Size = UDim2.new(0,32,0,18)

        local bar = create("Frame", {
            BackgroundColor3 = Theme.Off,
            Position = UDim2.new(0, 8, 1, -13),
            Size = UDim2.new(1, -16, 0, 5),
            BorderSizePixel = 0,
        }, row)
        corner(bar, 6)

        local fill = create("Frame", {
            BackgroundColor3 = Theme.Accent,
            Size = UDim2.new((definition.default-min)/(max-min),0,1,0),
            BorderSizePixel = 0,
        }, bar)
        corner(fill, 6)

        local knob = create("Frame", {
            BackgroundColor3 = Color3.new(1,1,1),
            AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.new((definition.default-min)/(max-min),0,0.5,0),
            Size = UDim2.new(0,12,0,12),
            BorderSizePixel = 0,
        }, bar)
        corner(knob, 10)

        local function setValue(inputX)
            local fraction = math.clamp(
                (inputX-bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0, 1)
            local value = math.floor(min + fraction*(max-min) + 0.5)
            Settings[name] = value
            Controls[name].value = value
            valueLabel.Text = tostring(value)
            fill.Size = UDim2.new(fraction,0,1,0)
            knob.Position = UDim2.new(fraction,0,0.5,0)
        end

        local sliding = false

        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = true
                setValue(input.Position.X)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
                setValue(input.Position.X)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = false
            end
        end)

    elseif kind == "dropdown" then
        local options = definition.options or {"Default"}
        registerControl(name, options[1], options[1])

        local index = 1
        local dropdown = create("TextButton", {
            Text = options[index] .. "  ▾",
            TextColor3 = Theme.Text,
            TextSize = 10,
            Font = Enum.Font.Gotham,
            BackgroundColor3 = Theme.Sidebar,
            AnchorPoint = Vector2.new(1,0.5),
            Position = UDim2.new(1,-8,0.5,0),
            Size = UDim2.new(0,105,0,29),
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        corner(dropdown, 8)
        stroke(dropdown, Theme.Border, 1)

        dropdown.MouseButton1Click:Connect(function()
            index = index % #options + 1
            Settings[name] = options[index]
            Controls[name].value = options[index]
            dropdown.Text = options[index] .. "  ▾"
        end)

    elseif kind == "color" then
        local colors = {
            Color3.fromRGB(255,255,255),
            Color3.fromRGB(235,128,196),
            Color3.fromRGB(179,91,225),
            Color3.fromRGB(100,170,255),
            Color3.fromRGB(255,80,100),
            Color3.fromRGB(160,231,161),
        }

        registerControl(name, definition.default, definition.default)

        local swatch = create("TextButton", {
            Text = "●",
            TextSize = 14,
            TextColor3 = definition.default,
            Font = Enum.Font.GothamBold,
            BackgroundColor3 = Theme.Sidebar,
            AnchorPoint = Vector2.new(1,0.5),
            Position = UDim2.new(1,-8,0.5,0),
            Size = UDim2.new(0,72,0,29),
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        corner(swatch, 9)
        stroke(swatch, Theme.Border, 1)

        local index = 1
        swatch.MouseButton1Click:Connect(function()
            index = index % #colors + 1
            Settings[name] = colors[index]
            Controls[name].value = colors[index]
            swatch.TextColor3 = colors[index]
        end)

    elseif kind == "button" then
        local button = create("TextButton", {
            Text = name,
            TextColor3 = Theme.Text,
            TextSize = 10,
            Font = Enum.Font.GothamMedium,
            BackgroundColor3 = Theme.Panel2,
            AnchorPoint = Vector2.new(1,0.5),
            Position = UDim2.new(1,-8,0.5,0),
            Size = UDim2.new(0,125,0,29),
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        corner(button, 8)
        stroke(button, Theme.Border, 1)

        button.MouseButton1Click:Connect(function()
            if name == "Reset Current Tab" then
                for _, def in ipairs(Definitions[CurrentTab] or {}) do
                    if Controls[def.name] then
                        Settings[def.name] = Controls[def.name].default
                        Controls[def.name].value = Controls[def.name].default
                    end
                end
            elseif name == "Reset All Settings" or name == "Reset Demo Settings" then
                for key, control in pairs(Controls) do
                    Settings[key] = control.default
                    control.value = control.default
                end
            end

            button.Text = "Reset complete!"
            tween(button, {BackgroundColor3 = Theme.Accent}, 0.15)
            task.delay(1, function()
                if button.Parent then
                    button.Text = name
                    tween(button, {BackgroundColor3 = Theme.Panel2}, 0.15)
                end
            end)
        end)
    end

    local separator = create("Frame", {
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.65,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -1),
        Size = UDim2.new(1, -16, 0, 1),
    }, row)

    return row
end

-- Right-hand live preview
local preview = create("Frame", {
    Name = "LivePreview",
    BackgroundColor3 = Theme.Panel,
    AnchorPoint = Vector2.new(1,0),
    Position = UDim2.new(1,-12,0,74),
    Size = UDim2.new(0,230,0,400),
    BorderSizePixel = 0,
}, main)
corner(preview, 14)
stroke(preview, Theme.Accent, 1)

local previewHeader = label(preview, "▦  Live Preview", 13, Theme.Text,
    Enum.Font.GothamMedium)
previewHeader.Position = UDim2.new(0,12,0,8)
previewHeader.Size = UDim2.new(1,-24,0,28)

local previewScreen = create("Frame", {
    BackgroundColor3 = Color3.fromRGB(7,7,11),
    Position = UDim2.new(0,9,0,45),
    Size = UDim2.new(1,-18,1,-55),
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, preview)
corner(previewScreen, 11)
stroke(previewScreen, Theme.Border, 1)

local demoCard = create("Frame", {
    BackgroundColor3 = Color3.fromRGB(23,23,30),
    AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.new(0.5,0,0.5,0),
    Size = UDim2.new(0,110,0,170),
    BorderSizePixel = 0,
}, previewScreen)
corner(demoCard, 6)
stroke(demoCard, Theme.Accent, 1.5)

local demoTop = create("Frame", {
    BackgroundColor3 = Color3.fromRGB(42,42,53),
    Size = UDim2.new(1,0,0,34),
    BorderSizePixel = 0,
}, demoCard)
corner(demoTop, 6)

local demoBody = create("Frame", {
    BackgroundColor3 = Color3.fromRGB(35,35,44),
    Position = UDim2.new(0,10,0,44),
    Size = UDim2.new(1,-20,0,84),
    BorderSizePixel = 0,
}, demoCard)
corner(demoBody, 4)

label(demoBody, "LILAC", 12, Theme.Accent, Enum.Font.GothamBold)
    .TextXAlignment = Enum.TextXAlignment.Center

local demoLine = create("Frame", {
    BackgroundColor3 = Theme.Accent,
    Position = UDim2.new(0,0,1,-4),
    Size = UDim2.new(0.75,0,0,3),
    BorderSizePixel = 0,
}, demoBody)
corner(demoLine, 3)

label(demoCard, "DEMO PREVIEW", 8, Theme.Muted)
    .Position = UDim2.new(0,8,1,-29)

local previewInfo = label(previewScreen, "Lilac UI", 10, Theme.Accent)
previewInfo.Position = UDim2.new(0,8,0,8)
previewInfo.Size = UDim2.new(1,-16,0,18)

-- Build and switch pages
buildPage = function(tabName)
    CurrentTab = tabName
    pageTitle.Text = tabName

    for _, child in ipairs(pageBody:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    local definitions = Definitions[tabName] or {}

    for _, definition in ipairs(definitions) do
        makeRow(pageBody, definition)
    end

    for name, button in pairs(navButtons) do
        local active = name == tabName
        tween(button, {
            BackgroundColor3 = active and Theme.Panel2 or Theme.Sidebar
        }, 0.15)

        button.TextColor3 = active and Theme.Accent or Theme.Muted

        local indicator = button:FindFirstChild("ActiveIndicator")
        if indicator then
            indicator.Visible = active
        end
    end

    search.Text = ""
end

for index, tabName in ipairs(tabNames) do
    local button = create("TextButton", {
        Name = "Nav_" .. tabName,
        Text = tabIcons[tabName] .. "    " .. tabName,
        TextColor3 = Theme.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Theme.Sidebar,
        Size = UDim2.new(1,0,0,39),
        BorderSizePixel = 0,
        LayoutOrder = index,
        AutoButtonColor = false,
    }, navHolder)
    corner(button, 10)

    local indicator = create("Frame", {
        Name = "ActiveIndicator",
        BackgroundColor3 = Theme.Accent,
        Position = UDim2.new(0,0,0.2,0),
        Size = UDim2.new(0,3,0.6,0),
        BorderSizePixel = 0,
        Visible = tabName == CurrentTab,
    }, button)
    corner(indicator, 3)

    navButtons[tabName] = button

    button.MouseButton1Click:Connect(function()
        buildPage(tabName)
    end)

    button.MouseEnter:Connect(function()
        if CurrentTab ~= tabName then
            tween(button, {BackgroundColor3 = Theme.Panel}, 0.12)
        end
    end)

    button.MouseLeave:Connect(function()
        if CurrentTab ~= tabName then
            tween(button, {BackgroundColor3 = Theme.Sidebar}, 0.12)
        end
    end)
end

-- Live search across currently displayed settings
search:GetPropertyChangedSignal("Text"):Connect(function()
    local query = search.Text:lower()

    for _, child in ipairs(pageBody:GetChildren()) do
        if child:IsA("Frame") and child:GetAttribute("SettingName") then
            local searchable = child:GetAttribute("SearchText") or ""
            child.Visible = query == "" or searchable:find(query, 1, true) ~= nil
        elseif child:IsA("TextLabel") then
            child.Visible = query == "" or child.Text:lower():find(query, 1, true) ~= nil
        end
    end
end)

-- Accent animation
task.spawn(function()
    while gui.Parent do
        if Settings["Animated Background"] ~= false then
            tween(outerGlow, {Transparency = 0.72}, 1.2)
            task.wait(1.2)
            tween(outerGlow, {Transparency = 0.9}, 1.2)
            task.wait(1.2)
        else
            task.wait(0.5)
        end
    end
end)

-- Entry animation
main.Size = UDim2.new(0, 1040, 0, 610)
main.BackgroundTransparency = 0.2

tween(main, {
    Size = UDim2.new(0,1100,0,650),
    BackgroundTransparency = 0,
}, 0.35)

buildPage("ESP")

print("Lilac UI loaded successfully.")
print("Settings are UI-only demo values.")
