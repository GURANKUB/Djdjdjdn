--[[
    RANKUKI — Brookhaven Executor Script
    UI: Dark / Purple / Blue | Mobile + PC
    Features: Fly, Speed, Jump, Noclip, Local Teleport, Vehicle Speed/Fly (own vehicle only)
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer
local Camera            = workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end)

local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local gethui = gethui or function() return game:GetService("CoreGui") end
local GuiParent = (function()
    local ok, res = pcall(gethui)
    if ok and res then return res end
    return game:GetService("CoreGui")
end)()

-- Cleanup old
for _, n in ipairs({"RANKUKI_Root", "RANKUKI_Toggle"}) do
    local old = GuiParent:FindFirstChild(n)
    if old then old:Destroy() end
end

-- ══════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════
local State = {
    Fly = false,
    FlySpeed = 50,
    WalkSpeed = 16,
    JumpPower = 50,
    Noclip = false,
    VehicleFly = false,
    VehicleSpeed = 50,
    SelectedPlayer = nil,
    Connections = {},
    BodyGyro = nil,
    BodyVelocity = nil,
    NoclipConn = nil,
    VehicleFlyConn = nil,
}

local function addConn(c)
    table.insert(State.Connections, c)
    return c
end

local function cleanup()
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(State.Connections)
    if State.BodyGyro then pcall(function() State.BodyGyro:Destroy() end) State.BodyGyro = nil end
    if State.BodyVelocity then pcall(function() State.BodyVelocity:Destroy() end) State.BodyVelocity = nil end
    if State.NoclipConn then pcall(function() State.NoclipConn:Disconnect() end) State.NoclipConn = nil end
    if State.VehicleFlyConn then pcall(function() State.VehicleFlyConn:Disconnect() end) State.VehicleFlyConn = nil end
    State.Fly = false
    State.Noclip = false
    State.VehicleFly = false
end

-- ══════════════════════════════════════════════════════════════
-- CHARACTER HELPERS
-- ══════════════════════════════════════════════════════════════
local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getVehicle()
    local char = getChar()
    if not char then return nil end
    local hum = getHum()
    if hum and hum.SeatPart then
        local seat = hum.SeatPart
        local model = seat:FindFirstAncestorOfClass("Model")
        if model and model ~= char then return model end
    end
    -- fallback: look for common Brookhaven vehicle names near player
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:FindFirstChildWhichIsA("VehicleSeat", true) then
            local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
            if seat and seat.Occupant == hum then
                return m
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════
-- MOVEMENT SYSTEMS
-- ══════════════════════════════════════════════════════════════
local function setWalkSpeed(v)
    State.WalkSpeed = v
    local hum = getHum()
    if hum then hum.WalkSpeed = v end
end

local function setJumpPower(v)
    State.JumpPower = v
    local hum = getHum()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = v
    end
end

local function startFly()
    if State.Fly then return end
    local hrp = getHRP()
    if not hrp then return end

    State.Fly = true
    local bg = Instance.new("BodyGyro")
    bg.P = 9e4
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp
    State.BodyGyro = bg

    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Parent = hrp
    State.BodyVelocity = bv

    addConn(RunService.RenderStepped:Connect(function()
        if not State.Fly or not hrp or not hrp.Parent then return end
        local cam = Camera.CFrame
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
            dir = dir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
            dir = dir - Vector3.new(0, 1, 0)
        end

        -- mobile: use camera look roughly
        if isMobile and dir.Magnitude < 0.1 then
            -- keep velocity zero unless joystick used (simplified)
        end

        if dir.Magnitude > 0 then
            bv.Velocity = dir.Unit * State.FlySpeed
        else
            bv.Velocity = Vector3.zero
        end
        bg.CFrame = cam
    end))
end

local function stopFly()
    State.Fly = false
    if State.BodyGyro then pcall(function() State.BodyGyro:Destroy() end) State.BodyGyro = nil end
    if State.BodyVelocity then pcall(function() State.BodyVelocity:Destroy() end) State.BodyVelocity = nil end
end

local function startNoclip()
    if State.Noclip then return end
    State.Noclip = true
    State.NoclipConn = RunService.Stepped:Connect(function()
        local char = getChar()
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
    addConn(State.NoclipConn)
end

local function stopNoclip()
    State.Noclip = false
    if State.NoclipConn then
        pcall(function() State.NoclipConn:Disconnect() end)
        State.NoclipConn = nil
    end
    local char = getChar()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

local function teleportToPlayer(player)
    if not player or not player.Character then return end
    local target = player.Character:FindFirstChild("HumanoidRootPart")
    local hrp = getHRP()
    if target and hrp then
        hrp.CFrame = target.CFrame + Vector3.new(0, 3, 0)
    end
end

-- Vehicle Fly (own vehicle only)
local function startVehicleFly()
    local veh = getVehicle()
    if not veh then
        warn("[RANKUKI] ไม่พบรถที่คุณนั่งอยู่")
        return
    end
    local primary = veh.PrimaryPart or veh:FindFirstChildWhichIsA("BasePart")
    if not primary then return end

    State.VehicleFly = true
    if State.VehicleFlyConn then pcall(function() State.VehicleFlyConn:Disconnect() end) end

    local bv = primary:FindFirstChild("RANKUKI_BV") or Instance.new("BodyVelocity")
    bv.Name = "RANKUKI_BV"
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = primary

    local bg = primary:FindFirstChild("RANKUKI_BG") or Instance.new("BodyGyro")
    bg.Name = "RANKUKI_BG"
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.P = 9e4
    bg.Parent = primary

    State.VehicleFlyConn = RunService.RenderStepped:Connect(function()
        if not State.VehicleFly or not primary.Parent then return end
        local cam = Camera.CFrame
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end

        if dir.Magnitude > 0 then
            bv.Velocity = dir.Unit * State.VehicleSpeed
        else
            bv.Velocity = Vector3.zero
        end
        bg.CFrame = cam
    end)
    addConn(State.VehicleFlyConn)
end

local function stopVehicleFly()
    State.VehicleFly = false
    if State.VehicleFlyConn then
        pcall(function() State.VehicleFlyConn:Disconnect() end)
        State.VehicleFlyConn = nil
    end
    local veh = getVehicle()
    if veh then
        for _, v in ipairs(veh:GetDescendants()) do
            if v.Name == "RANKUKI_BV" or v.Name == "RANKUKI_BG" then
                pcall(function() v:Destroy() end)
            end
        end
    end
end

-- Character respawn handler
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if State.Fly then stopFly() end
    if State.Noclip then stopNoclip() end
    setWalkSpeed(State.WalkSpeed)
    setJumpPower(State.JumpPower)
end)

-- ══════════════════════════════════════════════════════════════
-- UI THEME
-- ══════════════════════════════════════════════════════════════
local Theme = {
    Bg          = Color3.fromRGB(12, 10, 20),
    Card        = Color3.fromRGB(22, 18, 36),
    Accent      = Color3.fromRGB(140, 80, 255),
    Accent2     = Color3.fromRGB(60, 120, 255),
    Text        = Color3.fromRGB(240, 240, 255),
    Muted       = Color3.fromRGB(140, 130, 170),
    On          = Color3.fromRGB(80, 220, 120),
    Off         = Color3.fromRGB(80, 80, 100),
    Danger      = Color3.fromRGB(220, 70, 90),
    Stroke      = Color3.fromRGB(80, 60, 140),
}

local FontTitle = Enum.Font.GothamBold
local FontBody  = Enum.Font.Gotham

-- ══════════════════════════════════════════════════════════════
-- UI BUILD
-- ══════════════════════════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RANKUKI_Root"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 9999
ScreenGui.Parent = GuiParent

local ToggleGui = Instance.new("ScreenGui")
ToggleGui.Name = "RANKUKI_Toggle"
ToggleGui.ResetOnSpawn = false
ToggleGui.IgnoreGuiInset = true
ToggleGui.DisplayOrder = 10000
ToggleGui.Parent = GuiParent

local panelW = isMobile and 300 or 340
local panelH = isMobile and 420 or 460

-- Floating toggle
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 52, 0, 52)
ToggleBtn.Position = UDim2.new(0, 12, 0.5, -26)
ToggleBtn.BackgroundColor3 = Theme.Bg
ToggleBtn.BackgroundTransparency = 0.1
ToggleBtn.Text = "R"
ToggleBtn.TextSize = 22
ToggleBtn.TextColor3 = Theme.Accent
ToggleBtn.Font = FontTitle
ToggleBtn.AutoButtonColor = false
ToggleBtn.Parent = ToggleGui
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 26)
local ts = Instance.new("UIStroke", ToggleBtn)
ts.Color = Theme.Accent
ts.Thickness = 2
ts.Transparency = 0.3

-- Main Panel
local Panel = Instance.new("Frame")
Panel.Name = "Main"
Panel.Size = UDim2.new(0, panelW, 0, panelH)
Panel.Position = UDim2.new(0.5, -panelW/2, 0.5, -panelH/2)
Panel.BackgroundColor3 = Theme.Bg
Panel.BackgroundTransparency = 0.05
Panel.Visible = false
Panel.Parent = ScreenGui
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 14)
local ps = Instance.new("UIStroke", Panel)
ps.Color = Theme.Stroke
ps.Thickness = 1.5
ps.Transparency = 0.4

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, isMobile and 50 or 44)
Header.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
Header.BackgroundTransparency = 0.2
Header.Parent = Panel
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 14)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "RANKUKI"
Title.TextSize = 16
Title.TextColor3 = Theme.Accent
Title.Font = FontTitle
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, isMobile and 40 or 34, 0, isMobile and 40 or 34)
CloseBtn.Position = UDim2.new(1, -(isMobile and 46 or 40), 0.5, -(isMobile and 20 or 17))
CloseBtn.BackgroundColor3 = Theme.Danger
CloseBtn.BackgroundTransparency = 0.3
CloseBtn.Text = "✕"
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = Theme.Text
CloseBtn.Font = FontTitle
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, isMobile and 40 or 34, 0, isMobile and 40 or 34)
MinBtn.Position = UDim2.new(1, -(isMobile and 92 or 78), 0.5, -(isMobile and 20 or 17))
MinBtn.BackgroundColor3 = Theme.Accent2
MinBtn.BackgroundTransparency = 0.3
MinBtn.Text = "─"
MinBtn.TextSize = 14
MinBtn.TextColor3 = Theme.Text
MinBtn.Font = FontTitle
MinBtn.AutoButtonColor = false
MinBtn.Parent = Header
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 8)

-- Tab bar
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -16, 0, 34)
TabBar.Position = UDim2.new(0, 8, 0, isMobile and 56 or 50)
TabBar.BackgroundTransparency = 1
TabBar.Parent = Panel

local Tabs = {}
local Pages = {}
local currentTab = "Functions"

local function makeTab(name, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1/3, -4, 1, 0)
    b.Position = UDim2.new((order-1)/3, 2, 0, 0)
    b.BackgroundColor3 = Theme.Card
    b.BackgroundTransparency = 0.3
    b.Text = name
    b.TextSize = isMobile and 12 or 13
    b.TextColor3 = Theme.Muted
    b.Font = FontTitle
    b.AutoButtonColor = false
    b.Parent = TabBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    Tabs[name] = b
    return b
end

makeTab("Functions", 1)
makeTab("Troll", 2)
makeTab("Settings", 3)

-- Content area
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, 0, 1, -(isMobile and 96 or 90))
Content.Position = UDim2.new(0, 0, 0, isMobile and 96 or 90)
Content.BackgroundTransparency = 1
Content.Parent = Panel

local function makePage(name)
    local sc = Instance.new("ScrollingFrame")
    sc.Name = name
    sc.Size = UDim2.new(1, 0, 1, 0)
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 3
    sc.ScrollBarImageColor3 = Theme.Accent
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.Visible = false
    sc.Parent = Content
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sc
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = sc
    Pages[name] = sc
    return sc
end

local pageFunc = makePage("Functions")
local pageTroll = makePage("Troll")
local pageSet = makePage("Settings")
Pages["Functions"].Visible = true
Tabs["Functions"].TextColor3 = Theme.Accent

local function switchTab(name)
    currentTab = name
    for n, p in pairs(Pages) do p.Visible = (n == name) end
    for n, b in pairs(Tabs) do
        b.TextColor3 = (n == name) and Theme.Accent or Theme.Muted
        b.BackgroundTransparency = (n == name) and 0.1 or 0.3
    end
end

for name, btn in pairs(Tabs) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- UI Helpers
local function section(parent, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 22)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = 12
    l.TextColor3 = Theme.Muted
    l.Font = FontBody
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function toggleBtn(parent, label, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, isMobile and 44 or 38)
    frame.BackgroundColor3 = Theme.Card
    frame.BackgroundTransparency = 0.25
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, -70, 1, 0)
    nameL.Position = UDim2.new(0, 12, 0, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text = label
    nameL.TextSize = isMobile and 13 or 12
    nameL.TextColor3 = Theme.Text
    nameL.Font = FontBody
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Parent = frame

    local state = default
    local ind = Instance.new("TextButton")
    ind.Size = UDim2.new(0, 52, 0, 26)
    ind.Position = UDim2.new(1, -60, 0.5, -13)
    ind.BackgroundColor3 = state and Theme.On or Theme.Off
    ind.Text = state and "ON" or "OFF"
    ind.TextSize = 11
    ind.TextColor3 = Theme.Text
    ind.Font = FontTitle
    ind.AutoButtonColor = false
    ind.Parent = frame
    Instance.new("UICorner", ind).CornerRadius = UDim.new(0, 6)

    ind.MouseButton1Click:Connect(function()
        state = not state
        ind.BackgroundColor3 = state and Theme.On or Theme.Off
        ind.Text = state and "ON" or "OFF"
        if callback then callback(state) end
    end)
    return frame, function() return state end, function(v)
        state = v
        ind.BackgroundColor3 = state and Theme.On or Theme.Off
        ind.Text = state and "ON" or "OFF"
    end
end

local function slider(parent, label, min, max, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, isMobile and 56 or 50)
    frame.BackgroundColor3 = Theme.Card
    frame.BackgroundTransparency = 0.25
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(0.6, 0, 0, 18)
    nameL.Position = UDim2.new(0, 12, 0, 4)
    nameL.BackgroundTransparency = 1
    nameL.Text = label
    nameL.TextSize = 12
    nameL.TextColor3 = Theme.Text
    nameL.Font = FontBody
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Parent = frame

    local valL = Instance.new("TextLabel")
    valL.Size = UDim2.new(0.35, 0, 0, 18)
    valL.Position = UDim2.new(0.6, 0, 0, 4)
    valL.BackgroundTransparency = 1
    valL.Text = tostring(default)
    valL.TextSize = 12
    valL.TextColor3 = Theme.Accent
    valL.Font = FontTitle
    valL.TextXAlignment = Enum.TextXAlignment.Right
    valL.Parent = frame

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -24, 0, 8)
    barBg.Position = UDim2.new(0, 12, 1, -18)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
    barBg.Parent = frame
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.Parent = barBg
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
        local v = math.floor(min + rel * (max - min) + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        valL.Text = tostring(v)
        if callback then callback(v) end
    end

    barBg.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(inp.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            update(inp.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return frame
end

local function actionBtn(parent, text, color, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, isMobile and 40 or 36)
    b.BackgroundColor3 = color or Theme.Card
    b.BackgroundTransparency = 0.15
    b.Text = text
    b.TextSize = isMobile and 13 or 12
    b.TextColor3 = Theme.Text
    b.Font = FontTitle
    b.AutoButtonColor = false
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    return b
end

-- ══════════════════════════════════════════════════════════════
-- FUNCTIONS PAGE
-- ══════════════════════════════════════════════════════════════
section(pageFunc, "── MOVEMENT ──")

toggleBtn(pageFunc, "Fly", false, function(on)
    if on then startFly() else stopFly() end
end)

slider(pageFunc, "Fly Speed", 10, 200, 50, function(v)
    State.FlySpeed = v
end)

slider(pageFunc, "Walk Speed", 8, 200, 16, function(v)
    setWalkSpeed(v)
end)

slider(pageFunc, "Jump Power", 20, 200, 50, function(v)
    setJumpPower(v)
end)

toggleBtn(pageFunc, "Noclip", false, function(on)
    if on then startNoclip() else stopNoclip() end
end)

section(pageFunc, "── TELEPORT ──")

local playerListFrame = Instance.new("Frame")
playerListFrame.Size = UDim2.new(1, 0, 0, 120)
playerListFrame.BackgroundColor3 = Theme.Card
playerListFrame.BackgroundTransparency = 0.25
playerListFrame.Parent = pageFunc
Instance.new("UICorner", playerListFrame).CornerRadius = UDim.new(0, 8)

local playerScroll = Instance.new("ScrollingFrame")
playerScroll.Size = UDim2.new(1, -8, 1, -8)
playerScroll.Position = UDim2.new(0, 4, 0, 4)
playerScroll.BackgroundTransparency = 1
playerScroll.BorderSizePixel = 0
playerScroll.ScrollBarThickness = 3
playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerScroll.Parent = playerListFrame
local pLay = Instance.new("UIListLayout")
pLay.Padding = UDim.new(0, 3)
pLay.Parent = playerScroll

local function refreshPlayers()
    for _, c in ipairs(playerScroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, 0, 0, 28)
            b.BackgroundColor3 = Theme.Bg
            b.BackgroundTransparency = 0.4
            b.Text = "  " .. plr.DisplayName
            b.TextSize = 12
            b.TextColor3 = Theme.Text
            b.Font = FontBody
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.AutoButtonColor = false
            b.Parent = playerScroll
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            b.MouseButton1Click:Connect(function()
                State.SelectedPlayer = plr
                teleportToPlayer(plr)
            end)
        end
    end
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(refreshPlayers)

actionBtn(pageFunc, "Refresh Player List", Theme.Accent2, refreshPlayers)

section(pageFunc, "── VEHICLE ──")

toggleBtn(pageFunc, "Vehicle Fly (own only)", false, function(on)
    if on then startVehicleFly() else stopVehicleFly() end
end)

slider(pageFunc, "Vehicle Speed", 20, 300, 50, function(v)
    State.VehicleSpeed = v
end)

-- ══════════════════════════════════════════════════════════════
-- TROLL PAGE (limited — own vehicle only)
-- ══════════════════════════════════════════════════════════════
section(pageTroll, "── OWN VEHICLE ONLY ──")
section(pageTroll, "ระบบ Troll ที่รบกวนผู้อื่นถูกจำกัดไว้")

actionBtn(pageTroll, "Stop All Vehicle Control", Theme.Danger, function()
    stopVehicleFly()
end)

actionBtn(pageTroll, "Emergency Stop Everything", Theme.Danger, function()
    stopFly()
    stopNoclip()
    stopVehicleFly()
end)

section(pageTroll, "── TELEPORT TO PLAYER ──")
actionBtn(pageTroll, "TP to Selected Player", Theme.Accent, function()
    if State.SelectedPlayer then
        teleportToPlayer(State.SelectedPlayer)
    else
        warn("[RANKUKI] ยังไม่ได้เลือกผู้เล่น (ไปที่ Functions แล้วกดชื่อ)")
    end
end)

-- ══════════════════════════════════════════════════════════════
-- SETTINGS PAGE
-- ══════════════════════════════════════════════════════════════
section(pageSet, "── SYSTEM ──")

actionBtn(pageSet, "Stop All Functions", Theme.Danger, function()
    stopFly()
    stopNoclip()
    stopVehicleFly()
    setWalkSpeed(16)
    setJumpPower(50)
end)

actionBtn(pageSet, "Cleanup & Reset", Theme.Danger, function()
    cleanup()
    setWalkSpeed(16)
    setJumpPower(50)
end)

section(pageSet, "── INFO ──")
local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, 0, 0, 80)
info.BackgroundTransparency = 1
info.Text = "RANKUKI Executor Edition\nFly / Noclip / Vehicle Fly = own only\nMobile + PC supported\nไม่รองรับการควบคุมรถคนอื่น"
info.TextSize = 11
info.TextColor3 = Theme.Muted
info.Font = FontBody
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Parent = pageSet

-- ══════════════════════════════════════════════════════════════
-- DRAG + TOGGLE LOGIC
-- ══════════════════════════════════════════════════════════════
local panelOpen = false
local minimized = false
local normalH = panelH

local function openPanel()
    panelOpen = true
    Panel.Visible = true
    Panel.Size = UDim2.new(0, panelW, 0, 0)
    TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quart), {
        Size = UDim2.new(0, panelW, 0, normalH)
    }):Play()
end

local function closePanel()
    panelOpen = false
    TweenService:Create(Panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart), {
        Size = UDim2.new(0, panelW, 0, 0)
    }):Play()
    task.delay(0.2, function() Panel.Visible = false end)
end

CloseBtn.MouseButton1Click:Connect(closePanel)
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Content.Visible = not minimized
    TabBar.Visible = not minimized
    TweenService:Create(Panel, TweenInfo.new(0.2), {
        Size = minimized and UDim2.new(0, panelW, 0, isMobile and 50 or 44) or UDim2.new(0, panelW, 0, normalH)
    }):Play()
    MinBtn.Text = minimized and "□" or "─"
end)

-- Toggle button drag + click
local togDragging, togDidDrag = false, false
local togStart, togMouse
ToggleBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        togDragging = true
        togDidDrag = false
        togStart = ToggleBtn.Position
        togMouse = inp.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if togDragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local d = inp.Position - togMouse
        if math.abs(d.X) > 6 or math.abs(d.Y) > 6 then
            togDidDrag = true
            local vp = Camera.ViewportSize
            ToggleBtn.Position = UDim2.new(0,
                math.clamp(togStart.X.Offset + d.X, 0, vp.X - 52),
                0,
                math.clamp(togStart.Y.Offset + d.Y, 0, vp.Y - 52))
        end
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        togDragging = false
    end
end)
ToggleBtn.MouseButton1Click:Connect(function()
    if togDidDrag then return end
    if panelOpen then closePanel() else openPanel() end
end)

-- Panel drag
local pDragging = false
local pStart, pMouse
Header.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        pDragging = true
        pStart = Panel.Position
        pMouse = inp.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if pDragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local d = inp.Position - pMouse
        local vp = Camera.ViewportSize
        Panel.Position = UDim2.new(0,
            math.clamp(pStart.X.Offset + d.X, 0, vp.X - panelW),
            0,
            math.clamp(pStart.Y.Offset + d.Y, 0, vp.Y - 40))
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        pDragging = false
    end
end)

print("[RANKUKI] Loaded — Executor Edition")
print("[RANKUKI] Fly / Noclip / Vehicle Fly (own vehicle) ready")
