--[[
    PREHISTORIC TEAM V1.6 (SCRAP FARM FIX)
    5-account Blox Fruits automation scaffold built from the runtime dumps supplied in chat.

    IMPORTANT:
    - All 5 clients must run this same file and use the same MASTER_NAME.
    - MASTER = buys/drives MarineGrandBrigade + handles Volcano pressure.
    - SLAVES = passenger seats + Lava Golem combat.
    - WEBHOOK_URL is intentionally blank. Paste your Discord webhook in CONFIG.WEBHOOK_URL.
    - This V1 validates important actions from visible game state instead of assuming success.
]]

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

--==============================================================
-- DELTA-SAFE BOOT UI
-- Created BEFORE remote waits / automation init so Delta users
-- can immediately see whether the chunk actually started.
--==============================================================

local BOOT_GUI_NAME = "PrehistoricTeamBoot"
local oldBoot = PG:FindFirstChild(BOOT_GUI_NAME)
if oldBoot then oldBoot:Destroy() end

local BOOT_GUI = Instance.new("ScreenGui")
BOOT_GUI.Name = BOOT_GUI_NAME
BOOT_GUI.ResetOnSpawn = false
BOOT_GUI.IgnoreGuiInset = false
BOOT_GUI.DisplayOrder = 999999
BOOT_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
BOOT_GUI.Parent = PG

local BOOT_LABEL = Instance.new("TextLabel")
BOOT_LABEL.Parent = BOOT_GUI
BOOT_LABEL.Size = UDim2.fromOffset(330, 54)
BOOT_LABEL.Position = UDim2.new(0.5, -165, 0.04, 0)
BOOT_LABEL.BackgroundColor3 = Color3.fromRGB(20,20,26)
BOOT_LABEL.BorderColor3 = Color3.fromRGB(0,150,255)
BOOT_LABEL.TextColor3 = Color3.fromRGB(255,255,255)
BOOT_LABEL.Font = Enum.Font.SourceSansBold
BOOT_LABEL.TextSize = 14
BOOT_LABEL.TextWrapped = true
BOOT_LABEL.Text = "PREHISTORIC V1.6\nLoading automation..."
BOOT_LABEL.ZIndex = 999999

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if not remotes then
    BOOT_LABEL.Text = "PREHISTORIC V1.6 ERROR\nReplicatedStorage.Remotes not found"
    return
end

local CommF = remotes:WaitForChild("CommF_", 20)
if not CommF then
    BOOT_LABEL.Text = "PREHISTORIC V1.6 ERROR\nCommF_ not found"
    return
end

BOOT_LABEL.Text = "PREHISTORIC V1.6\nLoaded core, building UI..."

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    -- Default is the boat owner observed in your dump. Change here if needed.
    MASTER_NAME = "Hunter_Gerald16",

    TEAM = {
        "Hunter_Gerald16",
        "AshleyChelseaFrances",
        "ElaineClara24",
        "McDowellHuangk6",
        "Yoderep7",
    },

    WEBHOOK_URL = "", -- <<<<<<<<<< PASTE WEBHOOK HERE

    BOAT_NAME = "MarineGrandBrigade",
    BOAT_BUY_NAME = "MarineGrandBrigade",
    MIN_TEAM_NEAR_RELIC = 4,
    RELIC_RADIUS = 40,

    PLAYER_TWEEN_SPEED = 220,
    PRESSURE_TWEEN_SPEED = 300,
    BOAT_TWEEN_SPEED = 475,
    SAFE_ALTITUDE = 70,
    RESET_TO_TIKI_AFTER_EVENT = true,

    -- Public scripts use this offshore point as a Third Sea / high-danger travel target.
    SEA6_CENTER = Vector3.new(-37813.6953, 65, 6105.16895),

    BOAT_DEALER_CFRAME = CFrame.new(
        -16928.9277, 10, 434.619995,
        -0.434707522, 0, -0.900571883,
        0, 1, 0,
        0.900571883, 0, -0.434707522
    ),

    PORTALS = {
        Tiki_To_Castle = CFrame.new(-16799.9473, 59.9832191, 290.861969, 0.792721033, 6.48934986e-08, -0.60958457, -1.1125271e-07, 1, -3.82208896e-08, 0.60958457, 9.81164376e-08, 0.792721033),
        Castle_To_Tiki = CFrame.new(-5096.34131, 316.511047, -3174.32227, 0.999937356, 4.29376179e-08, -0.0111938119, -4.30900293e-08, 1, -1.33745131e-08, 0.0111938119, 1.38560168e-08, 0.999937356),
        Turtle_To_Castle = CFrame.new(-12463.6025, 376.335999, -7566.08301, 1, -2.37242093e-09, -3.80343628e-15, 2.37242093e-09, 1, 4.0985646e-09, 3.79371276e-15, -4.0985646e-09, 1),
        Castle_To_Turtle = CFrame.new(-5060.06006, 316.511047, -3194.63062, 0.992432296, 2.75590928e-08, -0.12279328, -2.76739218e-08, 1, 7.70395803e-10, 0.12279328, 2.63360578e-09, 0.992432296),
        Castle_To_Hydra = CFrame.new(-5027.03027, 316.511047, -3206.70361, 1, -4.02126652e-08, -1.21312694e-14, 4.02126652e-08, 1, 5.87755622e-08, 9.76774678e-15, -5.87755622e-08, 1),
        Hydra_To_Castle = CFrame.new(5650.94775, 1015.28326, -350.379181, 1, 5.02064275e-08, -1.44387506e-14, -5.02064275e-08, 1, -4.3968754e-08, 1.22312362e-14, 4.3968754e-08, 1),
    },

    DRAGON_HUNTER = {
        NPC = CFrame.new(5862.44092, 1208.89709, 807.572998, -0.400542974, 0, 0.916278243, 0, 1, 0, -0.916278243, 0, -0.400542974),
        STAND = CFrame.new(5863.4677734375, 1210.2822265625, 801.98779296875),
    },

    MOB_CAMPS = {
        HydraEnforcer = CFrame.new(4481.20752, 1004.28436, 538.046082),
        VenomousAssailant = CFrame.new(4622.26514, 1078.49329, 894.30603),
        -- User-captured safe point beside the Forest Pirate farming area on Floating Turtle.
        ForestPirate = CFrame.new(
            -13384.9883, 332.408264, -7814.93359,
            -0.840017498, 4.56535894e-08, 0.542559266,
            1.13496391e-07, 0.99999994, 5.30326076e-08,
            -0.542559206, 7.65943753e-08, -0.840017498
        ),
    },

    TREES = {
        CFrame.new(5254.79297,1004.09454,469.443573),
        CFrame.new(5187.3042,1004.08722,281.555573),
        CFrame.new(5323.68555,1004.099,316.628693),
        CFrame.new(5424.94434,1004.09265,145.194458),
        CFrame.new(5671.45557,1211.30786,844.747864),
    },
}

--==============================================================
-- STATE
--==============================================================

_G.TeamConfig = _G.TeamConfig or {}
_G.TeamConfig.MasterName = CONFIG.MASTER_NAME
_G.TeamConfig.IsMaster = LP.Name == CONFIG.MASTER_NAME
_G.TeamConfig.IsRunning = false

local RUN_TOKEN = 0
local STATUS_LABEL
local lastIslandWebhookKey = nil
local lavaConnection = nil

local function setStatus(s)
    if STATUS_LABEL then
        STATUS_LABEL.Text = tostring(s)
    end
    print("[PH-V1] " .. tostring(s))
end

local function isRunning(token)
    return _G.TeamConfig.IsRunning and token == RUN_TOKEN
end

local function isTeamName(name)
    return table.find(CONFIG.TEAM, name) ~= nil
end

local function teamIndex(name)
    return table.find(CONFIG.TEAM, name)
end

local function isMaster()
    return LP.Name == _G.TeamConfig.MasterName
end

local function roleText()
    return isMaster() and "MASTER / BUY BOAT" or "SLAVE / PASSENGER"
end

--==============================================================
-- CHARACTER HELPERS
--==============================================================

local function char()
    return LP.Character
end

local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function root()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function waitCharacter()
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then
        LP.CharacterAdded:Wait()
    end
    local c = LP.Character
    c:WaitForChild("HumanoidRootPart")
    c:WaitForChild("Humanoid")
    return c
end

local function stopSit()
    local h = hum()
    if h then
        h.Sit = false
        h.Jump = true
    end
end

local function safeTween(targetCFrame, speed, token)
    local c = waitCharacter()
    local r = c:FindFirstChild("HumanoidRootPart")
    if not r then return false end

    local d = (r.Position - targetCFrame.Position).Magnitude
    if d < 4 then
        r.CFrame = targetCFrame
        return true
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "PH_TweenBV"
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.zero
    bv.Parent = r

    local conn
    conn = RunService.Stepped:Connect(function()
        if token and not isRunning(token) then return end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
            end
        end
    end)

    local t = math.max(d / (speed or CONFIG.PLAYER_TWEEN_SPEED), 0.05)
    local tw = TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tw:Play()
    tw.Completed:Wait()

    if conn then conn:Disconnect() end
    if bv.Parent then bv:Destroy() end
    return true
end

local function highTween(targetCFrame, speed, token)
    local r = root()
    if not r then return false end

    local highY = math.max(r.Position.Y, targetCFrame.Position.Y) + CONFIG.SAFE_ALTITUDE
    local up = CFrame.new(r.Position.X, highY, r.Position.Z)
    local across = CFrame.new(targetCFrame.Position.X, highY, targetCFrame.Position.Z)

    safeTween(up, speed or CONFIG.PRESSURE_TWEEN_SPEED, token)
    if token and not isRunning(token) then return false end
    safeTween(across, speed or CONFIG.PRESSURE_TWEEN_SPEED, token)
    if token and not isRunning(token) then return false end
    safeTween(targetCFrame, speed or CONFIG.PRESSURE_TWEEN_SPEED, token)
    return true
end

local function resetCharacter()
    local h = hum()
    if h then
        h.Health = 0
    end
    LP.CharacterAdded:Wait()
    waitCharacter()
    task.wait(1)
end

-- Defined later after portal helpers are available.
local resetBackToTiki

--==============================================================
-- WEBHOOK
--==============================================================

local function sendWebhook(title, description, fields)
    if CONFIG.WEBHOOK_URL == nil or CONFIG.WEBHOOK_URL == "" then
        return false
    end

    local req = nil
    if syn and syn.request then req = syn.request end
    if not req and http_request then req = http_request end
    if not req and request then req = request end
    if not req then return false end

    local embed = {
        title = title,
        description = description,
        fields = fields or {},
        footer = {text = "Prehistoric Team V1 | " .. LP.Name},
        timestamp = DateTime.now():ToIsoDate(),
    }

    local payload = HttpService:JSONEncode({
        username = "Prehistoric Team",
        embeds = {embed},
    })

    pcall(function()
        req({
            Url = CONFIG.WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload,
        })
    end)
    return true
end

--==============================================================
-- INVENTORY
--==============================================================

local function getInventory()
    local ok, inv = pcall(function()
        return CommF:InvokeServer("getInventory")
    end)
    if ok and type(inv) == "table" then
        return inv
    end
    return {}
end

local function inventoryCount(itemName)
    local wanted = string.lower(itemName)
    local total = 0
    for _,v in pairs(getInventory()) do
        if type(v) == "table" and string.lower(tostring(v.Name or "")) == wanted then
            local n = tonumber(v.Count or v.Amount or v.count or v.Quantity or 1) or 1
            total = total + n
        end
    end
    return total
end

local function hasVolcanicMagnet()
    return inventoryCount("Volcanic Magnet") > 0
end

--==============================================================
-- TEAM / MARINES
--==============================================================

local function ensureMarines()
    if LP.Team and LP.Team.Name == "Marines" then return true end
    pcall(function()
        CommF:InvokeServer("SetTeam", "Marines")
    end)
    local deadline = os.clock() + 10
    repeat
        task.wait(.25)
        if LP.Team and LP.Team.Name == "Marines" then return true end
    until os.clock() > deadline
    return false
end

--==============================================================
-- TOOLS / COMBAT
--==============================================================

local function getToolByTooltip(tooltip)
    local c = char()
    local bp = LP:FindFirstChild("Backpack")
    for _,container in ipairs({c, bp}) do
        if container then
            for _,v in ipairs(container:GetChildren()) do
                if v:IsA("Tool") then
                    local ok,tip = pcall(function() return v.ToolTip end)
                    if ok and tip == tooltip then
                        return v
                    end
                end
            end
        end
    end
end

local function equipTooltip(tooltip)
    local h = hum()
    if not h then return nil end
    local tool = getToolByTooltip(tooltip)
    if not tool then return nil end
    if tool.Parent ~= char() then
        h:EquipTool(tool)
        task.wait(.12)
    end
    return tool
end

local function pressKey(keyCode, hold)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(hold or .07)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function aimAt(pos)
    local r = root()
    if r then
        local flat = Vector3.new(pos.X, r.Position.Y, pos.Z)
        if (flat - r.Position).Magnitude > 1 then
            r.CFrame = CFrame.lookAt(r.Position, flat)
        end
    end
    local cam = workspace.CurrentCamera
    if cam then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
    end
end

local SKILL_KEYS = {
    Enum.KeyCode.X,
    Enum.KeyCode.C,
    Enum.KeyCode.V,
    Enum.KeyCode.F,
}

local function useXCVF(targetPos)
    if targetPos then aimAt(targetPos) end

    if equipTooltip("Melee") then
        for _,k in ipairs(SKILL_KEYS) do
            if targetPos then aimAt(targetPos) end
            pressKey(k, .07)
            task.wait(.12)
        end
    end

    if equipTooltip("Blox Fruit") then
        for _,k in ipairs(SKILL_KEYS) do
            if targetPos then aimAt(targetPos) end
            pressKey(k, .07)
            task.wait(.12)
        end
    end
end

local function meleeM1(targetModel, token)
    local h = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
    local rr = targetModel and targetModel:FindFirstChild("HumanoidRootPart")
    if not h or not rr then return end

    pcall(function()
        rr.CanCollide = false
        rr.Size = Vector3.new(45,45,45)
    end)

    local tool = equipTooltip("Melee")
    while h.Parent and h.Health > 0 and (not token or isRunning(token)) do
        rr = targetModel:FindFirstChild("HumanoidRootPart")
        if not rr then break end
        safeTween(rr.CFrame * CFrame.new(0, 16, 0), 330, token)
        aimAt(rr.Position)
        tool = equipTooltip("Melee") or tool
        if tool and tool.Parent == char() then
            pcall(function() tool:Activate() end)
        end
        task.wait(.11)
    end
end

local function farmNamedMob(name, fallbackCFrame, token)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return false end

    local found = nil
    for _,m in ipairs(enemies:GetChildren()) do
        if m.Name == name then
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                found = m
                break
            end
        end
    end

    if found then
        meleeM1(found, token)
        return true
    end

    if fallbackCFrame then
        safeTween(fallbackCFrame * CFrame.new(0,18,0), CONFIG.PLAYER_TWEEN_SPEED, token)
    end
    task.wait(.5)
    return false
end

--==============================================================
-- LAVA PROTECTION
--==============================================================

local function isLavaPart(v)
    if not v:IsA("BasePart") then return false end
    local n = string.lower(v.Name)
    return n:find("lava", 1, true) ~= nil or v:GetAttribute("__LavaPart") == true
end

local function neutralizeLavaObject(v)
    if not isLavaPart(v) then return end
    pcall(function()
        v.CanTouch = false
        v.CanCollide = false
    end)
    local ti = v:FindFirstChild("TouchInterest")
    if ti then
        pcall(function() ti:Destroy() end)
    end
end

local function enableLavaProtection(island)
    if lavaConnection then
        lavaConnection:Disconnect()
        lavaConnection = nil
    end
    for _,v in ipairs(island:GetDescendants()) do
        neutralizeLavaObject(v)
    end
    lavaConnection = island.DescendantAdded:Connect(function(v)
        task.defer(function()
            neutralizeLavaObject(v)
        end)
    end)
end

local function disableLavaProtection()
    if lavaConnection then
        lavaConnection:Disconnect()
        lavaConnection = nil
    end
end

--==============================================================
-- PORTALS
--==============================================================

local function nearestDistance(pos)
    local r = root()
    if not r then return math.huge end
    return (r.Position - pos).Magnitude
end

local function getRegion()
    local r = root()
    if not r then return "UNKNOWN" end
    local p = r.Position

    local regions = {
        TIKI = CONFIG.PORTALS.Tiki_To_Castle.Position,
        CASTLE = CONFIG.PORTALS.Castle_To_Tiki.Position,
        TURTLE = CONFIG.PORTALS.Turtle_To_Castle.Position,
        HYDRA = CONFIG.PORTALS.Hydra_To_Castle.Position,
    }

    local best,bestD = "UNKNOWN", math.huge
    for name,pos in pairs(regions) do
        local d = (p-pos).Magnitude
        if d < bestD then best,bestD = name,d end
    end
    return best, bestD
end

-- Portal travel is NEVER allowed to fall through into long-distance island tweening.
-- We cross the portal plane several times and verify the destination region.
local function usePortal(cf, expectedRegion, token)
    for attempt=1,5 do
        if token and not isRunning(token) then return false end

        setStatus("PORTAL -> "..tostring(expectedRegion).." ["..attempt.."/5]")

        -- Approach from one side, then physically cross through the portal plane.
        safeTween(cf * CFrame.new(0,0,-12), 260, token)
        if token and not isRunning(token) then return false end

        safeTween(cf * CFrame.new(0,0,3), 110, token)
        task.wait(.20)

        local r = root()
        if r then
            -- Small local-space passes help portals whose trigger volume is thin.
            local passes = {
                CFrame.new(0,0,8),
                CFrame.new(0,0,-4),
                CFrame.new(4,0,2),
                CFrame.new(-4,0,2),
                CFrame.new(0,2,0),
            }
            for _,off in ipairs(passes) do
                if token and not isRunning(token) then return false end
                r.CFrame = cf * off
                task.wait(.16)
                if getRegion() == expectedRegion then
                    task.wait(.45)
                    return true
                end
            end
        end

        -- Give replication/teleport a moment before retrying.
        for _=1,8 do
            task.wait(.15)
            if getRegion() == expectedRegion then
                task.wait(.45)
                return true
            end
        end
    end

    setStatus("PORTAL FAILED -> "..tostring(expectedRegion).." | STOP ROUTE")
    return false
end

local function goCastle(token)
    local region = getRegion()
    if region == "CASTLE" then return true end
    if region == "TIKI" then return usePortal(CONFIG.PORTALS.Tiki_To_Castle, "CASTLE", token) end
    if region == "TURTLE" then return usePortal(CONFIG.PORTALS.Turtle_To_Castle, "CASTLE", token) end
    if region == "HYDRA" then return usePortal(CONFIG.PORTALS.Hydra_To_Castle, "CASTLE", token) end
    return false
end

local function goTiki(token)
    local region = getRegion()
    if region == "TIKI" then return true end

    if region ~= "CASTLE" then
        if not goCastle(token) then
            setStatus("PORTAL: failed to reach Castle")
            return false
        end
        task.wait(1.0)
    end

    if getRegion() == "TIKI" then return true end
    local ok = usePortal(CONFIG.PORTALS.Castle_To_Tiki, "TIKI", token)
    task.wait(1.0)
    if getRegion() == "TIKI" then return true end

    setStatus("PORTAL: Castle -> Tiki not confirmed")
    return ok and true or false
end

local function goTurtle(token)
    local region = getRegion()
    if region == "TURTLE" then return true end
    if region ~= "CASTLE" then
        if not goCastle(token) then return false end
        task.wait(.5)
    end
    if getRegion() ~= "CASTLE" then return false end
    return usePortal(CONFIG.PORTALS.Castle_To_Turtle, "TURTLE", token)
end

local function goHydra(token)
    local region = getRegion()
    if region == "HYDRA" then return true end
    if region ~= "CASTLE" then
        if not goCastle(token) then return false end
        task.wait(.5)
    end
    if getRegion() ~= "CASTLE" then return false end
    return usePortal(CONFIG.PORTALS.Castle_To_Hydra, "HYDRA", token)
end

resetBackToTiki = function(token)
    if not CONFIG.RESET_TO_TIKI_AFTER_EVENT then return true end

    setStatus("Rewards collected -> reset back to Tiki")
    resetCharacter()
    if token and not isRunning(token) then return false end

    -- If this account already had Tiki as its spawn, the reset is enough.
    -- Otherwise, finish the return through the known Castle/Tiki portal route.
    if getRegion() ~= "TIKI" then
        goTiki(token)
    end

    if getRegion() == "TIKI" then
        pcall(function() CommF:InvokeServer("SetSpawnPoint") end)
        setStatus("Returned to Tiki Outpost")
        return true
    end

    setStatus("WARNING: reset completed but Tiki position not confirmed")
    return false
end

--==============================================================
-- BOAT
--==============================================================

local function boatOwnerName(boat)
    local owner = boat and boat:FindFirstChild("Owner")
    if owner and owner:IsA("ValueBase") then
        return tostring(owner.Value)
    end
end

local function getMasterBoat()
    local boats = workspace:FindFirstChild("Boats")
    if not boats then return nil end
    for _,b in ipairs(boats:GetChildren()) do
        if b.Name == CONFIG.BOAT_NAME and boatOwnerName(b) == _G.TeamConfig.MasterName then
            return b
        end
    end
end

local function sortPassengerSeats(boat)
    local driver = boat and boat:FindFirstChild("VehicleSeat")
    if not driver or not driver:IsA("VehicleSeat") then return {} end

    local seats = {}
    for _,v in ipairs(boat:GetDescendants()) do
        if v:IsA("Seat") and not v:IsA("VehicleSeat") then
            local lp = driver.CFrame:PointToObjectSpace(v.Position)
            table.insert(seats, {seat=v, x=lp.X, z=lp.Z})
        end
    end

    table.sort(seats, function(a,b)
        if math.abs(a.z-b.z) > .1 then return a.z < b.z end
        return a.x < b.x
    end)

    local out = {}
    for _,x in ipairs(seats) do table.insert(out, x.seat) end
    return out
end

local function slaveIndex()
    local n = 0
    for _,name in ipairs(CONFIG.TEAM) do
        if name ~= _G.TeamConfig.MasterName then
            n = n + 1
            if name == LP.Name then return n end
        end
    end
end

local function sitOn(seat, token)
    if not seat then return false end
    local h = hum()
    if not h then return false end

    if seat.Occupant == h then return true end
    stopSit()
    safeTween(seat.CFrame * CFrame.new(0,3,0), 250, token)

    pcall(function() seat:Sit(h) end)
    if firetouchinterest and root() then
        pcall(function()
            firetouchinterest(root(), seat, 0)
            task.wait(.1)
            firetouchinterest(root(), seat, 1)
        end)
    end

    local deadline = os.clock()+4
    repeat
        task.wait(.1)
        if seat.Occupant == h then return true end
        pcall(function() seat:Sit(h) end)
    until os.clock()>deadline or (token and not isRunning(token))
    return seat.Occupant == h
end

local function buyGrandBrigade(token)
    if not isMaster() then return nil end
    local existing = getMasterBoat()
    if existing then return existing end

    setStatus("MASTER: going to Tiki Boat Dealer")
    goTiki(token)
    safeTween(CONFIG.BOAT_DEALER_CFRAME, 260, token)

    pcall(function() CommF:InvokeServer("SetSpawnPoint") end)

    for attempt=1,5 do
        pcall(function()
            CommF:InvokeServer("BuyBoat", CONFIG.BOAT_BUY_NAME)
        end)
        task.wait(1)
        local b = getMasterBoat()
        if b then
            setStatus("Boat spawned: "..b.Name)
            return b
        end
        setStatus("BuyBoat retry "..attempt.."/5")
    end
    return nil
end

local function boardBoat(boat, token)
    if not boat then return false end
    if isMaster() then
        return sitOn(boat:FindFirstChild("VehicleSeat"), token)
    end

    local idx = slaveIndex()
    local seats = sortPassengerSeats(boat)
    if not idx or not seats[idx] then return false end
    return sitOn(seats[idx], token)
end

local function countTeamAboard(boat)
    local count = 0
    for _,v in ipairs(boat:GetDescendants()) do
        if v:IsA("Seat") or v:IsA("VehicleSeat") then
            local occ = v.Occupant
            if occ and occ.Parent then
                local p = Players:GetPlayerFromCharacter(occ.Parent)
                if p and isTeamName(p.Name) then count = count + 1 end
            end
        end
    end
    return count
end

local function boatNoclip(boat)
    for _,v in ipairs(boat:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end

local function findPrehistoric()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("PrehistoricIsland")
end

local function boatFlyTo(boat, targetPos, token)
    if not boat or not boat.Parent then return false end
    local start = boat:GetPivot()
    local startPos = start.Position
    local dist = (targetPos-startPos).Magnitude
    local duration = math.max(dist/CONFIG.BOAT_TWEEN_SPEED, .05)
    local startTime = os.clock()

    while isRunning(token) and boat.Parent do
        if findPrehistoric() then return true end
        local a = math.clamp((os.clock()-startTime)/duration, 0, 1)
        local pos = startPos:Lerp(targetPos, a)
        local dir = targetPos-pos
        local targetCF
        if dir.Magnitude > .5 then
            targetCF = CFrame.lookAt(pos, pos+Vector3.new(dir.X,0,dir.Z))
        else
            targetCF = CFrame.new(pos) * start.Rotation
        end
        boatNoclip(boat)
        pcall(function() boat:PivotTo(targetCF) end)
        if a >= 1 then break end
        RunService.Heartbeat:Wait()
    end
    return findPrehistoric() ~= nil
end

local function searchSeaUntilIsland(boat, token)
    local c = CONFIG.SEA6_CENTER
    local patrol = {
        c,
        c + Vector3.new(-5500,0,0),
        c + Vector3.new(-5500,0,5500),
        c + Vector3.new(0,0,5500),
        c + Vector3.new(5500,0,5500),
        c + Vector3.new(5500,0,0),
        c + Vector3.new(5500,0,-5500),
        c + Vector3.new(0,0,-5500),
        c + Vector3.new(-5500,0,-5500),
    }

    local i = 1
    while isRunning(token) and boat and boat.Parent do
        local island = findPrehistoric()
        if island then return island end
        setStatus("MASTER: sea search point "..i.." | aboard "..countTeamAboard(boat).."/5")
        boatFlyTo(boat, patrol[i], token)
        island = findPrehistoric()
        if island then return island end
        i = i + 1
        if i > #patrol then i = 1 end
    end
end

--==============================================================
-- PREHISTORIC / RELIC
--==============================================================

local function getRelic(island)
    local core = island and island:FindFirstChild("Core")
    return core and core:FindFirstChild("PrehistoricRelic")
end

local function relicPart(relic)
    if not relic then return nil end
    return relic:FindFirstChild("Inside") or relic:FindFirstChild("Skull") or relic:FindFirstChildWhichIsA("BasePart", true)
end

local function countTeamNear(pos, radius)
    local n = 0
    for _,p in ipairs(Players:GetPlayers()) do
        if isTeamName(p.Name) and p.Character then
            local rr = p.Character:FindFirstChild("HumanoidRootPart")
            local hh = p.Character:FindFirstChildOfClass("Humanoid")
            if rr and hh and hh.Health > 0 and (rr.Position-pos).Magnitude <= radius then
                n = n + 1
            end
        end
    end
    return n
end

local function moveToRelic(island, token)
    stopSit()
    local relic = getRelic(island)
    local part = relicPart(relic)
    if not part then return false end

    local idx = teamIndex(LP.Name) or 1
    local angle = (idx-1) * (math.pi*2/5)
    local off = Vector3.new(math.cos(angle)*9, 4, math.sin(angle)*9)
    highTween(CFrame.new(part.Position+off), 360, token)
    return true
end

local function holdE(sec)
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(sec or .62)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function startEventAsMaster(island, token)
    if not isMaster() then return true end
    if island:GetAttribute("IsMinigameActive") == true then return true end

    local relic = getRelic(island)
    local part = relicPart(relic)
    if not part then return false end

    setStatus("MASTER: waiting >=4 team near relic")
    while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") ~= true do
        local near = countTeamNear(part.Position, CONFIG.RELIC_RADIUS)
        if near >= CONFIG.MIN_TEAM_NEAR_RELIC then
            setStatus("MASTER: "..near.." near relic -> HOLD E")
            safeTween(part.CFrame * CFrame.new(0,0,-5), 220, token)
            aimAt(part.Position)
            holdE(.62)
            task.wait(.7)
            if island:GetAttribute("IsMinigameActive") == true then return true end
        else
            setStatus("Relic ready: "..near.."/"..CONFIG.MIN_TEAM_NEAR_RELIC)
        end
        task.wait(.4)
    end
    return island:GetAttribute("IsMinigameActive") == true
end

local function parsePercent(text)
    return tonumber(tostring(text or ""):match("(%d+)%%"))
end

local function getPressure()
    local main = PG:FindFirstChild("Main")
    local hud = main and main:FindFirstChild("TopHUDList")
    local lbl = hud and hud:FindFirstChild("PrehistoricRaidTimer")
    return lbl and parsePercent(lbl.Text), lbl
end

local function getRelicHealthPercent(island)
    local relic = getRelic(island)
    if not relic then return nil end
    local hp = relic:FindFirstChild("Health")
    local mx = relic:FindFirstChild("MaxHealth")
    if hp and mx and mx.Value > 0 then
        return hp.Value/mx.Value*100
    end
end

local function rockActive(rock)
    for _,v in ipairs(rock:GetDescendants()) do
        if (v:IsA("Beam") or v:IsA("ParticleEmitter")) and v.Enabled then
            return true
        end
    end
    return false
end

local function activePressureRocks(island)
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("VolcanoRocks")
    if not folder then return {} end

    local list = {}
    for _,rock in ipairs(folder:GetChildren()) do
        if rock:IsA("Model") and rockActive(rock) then
            local mesh = rock:FindFirstChild("volcanorock") or rock:FindFirstChildWhichIsA("BasePart", true)
            if mesh then table.insert(list, {model=rock, part=mesh}) end
        end
    end

    local rr = root()
    if rr then
        table.sort(list, function(a,b)
            return (a.part.Position-rr.Position).Magnitude < (b.part.Position-rr.Position).Magnitude
        end)
    end
    return list
end

local function masterPressureLoop(island, token)
    enableLavaProtection(island)
    setStatus("MASTER: pressure mode")

    while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") == true do
        local pressure = getPressure()
        local hpPct = getRelicHealthPercent(island)
        setStatus("MASTER Pressure="..tostring(pressure or "?").."% | Relic="..string.format("%.1f", hpPct or 0).."%")

        local rocks = activePressureRocks(island)
        if #rocks == 0 then
            task.wait(.15)
        else
            local target = rocks[1]
            local p = target.part.Position
            highTween(CFrame.new(p + Vector3.new(0,12,0)), CONFIG.PRESSURE_TWEEN_SPEED, token)

            for _=1,2 do
                if not isRunning(token) or island:GetAttribute("IsMinigameActive") ~= true then break end
                if not target.model.Parent or not rockActive(target.model) then break end
                useXCVF(p)
                task.wait(.15)
            end
        end
    end

    disableLavaProtection()
end

local function slaveGolemLoop(island, token)
    local enemies = workspace:FindFirstChild("Enemies")
    local relic = getRelic(island)
    local rp = relicPart(relic)

    while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") == true do
        local golem = enemies and enemies:FindFirstChild("Lava Golem")
        local gh = golem and golem:FindFirstChildOfClass("Humanoid")
        if golem and gh and gh.Health > 0 then
            setStatus("SLAVE: Lava Golem "..math.floor(gh.Health).."/"..math.floor(gh.MaxHealth))
            meleeM1(golem, token)
        else
            if rp then
                local idx = slaveIndex() or 1
                local off = Vector3.new(idx*4, 14, idx%2==0 and 8 or -8)
                safeTween(CFrame.new(rp.Position+off), 280, token)
            end
            task.wait(.25)
        end
    end
end

--==============================================================
-- COLLECT BONES / EGGS / DRAGON FRUIT
--==============================================================

local function interactionPart(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function interactCollectible(obj, token)
    if not obj or not obj.Parent then return false end
    local p = interactionPart(obj)
    if not p then return false end

    highTween(p.CFrame * CFrame.new(0,3,0), 330, token)

    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(.25)
        return true
    end

    local cd = obj:FindFirstChildWhichIsA("ClickDetector", true)
    if cd and fireclickdetector then
        pcall(function() fireclickdetector(cd) end)
        task.wait(.25)
        return true
    end

    local touch = obj:FindFirstChildWhichIsA("TouchTransmitter", true)
    if touch and firetouchinterest and root() then
        local tp = touch.Parent
        if tp and tp:IsA("BasePart") then
            pcall(function()
                firetouchinterest(root(), tp, 0)
                task.wait(.12)
                firetouchinterest(root(), tp, 1)
            end)
            task.wait(.25)
            return true
        end
    end

    return false
end

local function collectBones(island, token)
    setStatus("Collecting Dinosaur Bones")
    local deadline = os.clock()+18
    local tried = {}

    while isRunning(token) and island.Parent and os.clock()<deadline do
        local found = false
        for _,v in ipairs(island:GetDescendants()) do
            if not tried[v] and string.lower(v.Name):find("bone",1,true) then
                local hasInteract = v:FindFirstChildWhichIsA("ProximityPrompt", true)
                    or v:FindFirstChildWhichIsA("ClickDetector", true)
                    or v:FindFirstChildWhichIsA("TouchTransmitter", true)
                if hasInteract then
                    tried[v] = true
                    found = true
                    interactCollectible(v, token)
                end
            end
        end
        if not found then task.wait(.4) end
    end
end

local function fruitOriginalName(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local orig = tool:GetAttribute("OriginalName")
    if orig and tostring(orig) ~= "" then return tostring(orig) end
    if string.lower(tool.Name):find("fruit",1,true) then return tool.Name end
end

local function findPhysicalDragonFruit()
    for _,container in ipairs({LP.Backpack, char()}) do
        if container then
            for _,v in ipairs(container:GetChildren()) do
                if v:IsA("Tool") then
                    local orig = fruitOriginalName(v)
                    local combined = string.lower((orig or "").." "..v.Name)
                    if orig and combined:find("dragon",1,true) then
                        return v, orig
                    end
                end
            end
        end
    end
end

local function storedFruitExists(originalName)
    local ok, fruits = pcall(function()
        return CommF:InvokeServer("getInventoryFruits")
    end)
    if not ok or type(fruits) ~= "table" then return false end
    local wanted = string.lower(tostring(originalName))
    for _,v in pairs(fruits) do
        if type(v) == "table" then
            local n = string.lower(tostring(v.Name or v.OriginalName or ""))
            if n == wanted or n:find("dragon",1,true) and wanted:find("dragon",1,true) then
                return true
            end
        end
    end
    return false
end

local function storeDragonFruitCritical()
    local tool, original = findPhysicalDragonFruit()
    if not tool then return true end

    setStatus("!!! DRAGON FRUIT DETECTED: "..original.." -> STORE NOW")
    sendWebhook("🐉 DRAGON FRUIT DETECTED", "Attempting immediate StoreFruit", {
        {name="Account", value=LP.Name, inline=true},
        {name="Fruit", value=original, inline=true},
    })

    local ok = pcall(function()
        CommF:InvokeServer("StoreFruit", original, tool)
    end)
    task.wait(1)

    local stillTool = tool.Parent ~= nil
    local verified = storedFruitExists(original)
    if ok and (verified or not stillTool) then
        sendWebhook("✅ DRAGON FRUIT STORED", "Storage call completed and the physical tool is no longer loose.", {
            {name="Account", value=LP.Name, inline=true},
            {name="Fruit", value=original, inline=true},
        })
        setStatus("Dragon stored: "..original)
        return true
    end

    sendWebhook("🚨 CRITICAL: DRAGON STORE FAILED", "Automation STOPPED on this account. Do not reset or leave.", {
        {name="Account", value=LP.Name, inline=true},
        {name="Fruit", value=original, inline=true},
    })
    _G.TeamConfig.IsRunning = false
    setStatus("CRITICAL: StoreFruit failed -> STOPPED")
    return false
end

local function eggPosition(obj)
    local p = interactionPart(obj)
    return p and p.Position
end

local function collectAssignedEgg(island, token)
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    if not folder then return end

    local deadline = os.clock()+20
    while isRunning(token) and os.clock()<deadline do
        local eggs = folder:GetChildren()
        if #eggs > 0 then
            table.sort(eggs, function(a,b)
                local ap,bp = eggPosition(a),eggPosition(b)
                if not ap then return false end
                if not bp then return true end
                if math.abs(ap.X-bp.X) > 1 then return ap.X < bp.X end
                return ap.Z < bp.Z
            end)

            local ti = teamIndex(LP.Name) or 1
            local islandPos = island:GetPivot().Position
            local rotate = math.abs(math.floor(islandPos.X)) % #CONFIG.TEAM
            local rank = ((ti + rotate - 1) % #CONFIG.TEAM) + 1

            if rank <= #eggs then
                setStatus("Egg assignment "..rank.."/"..#eggs)
                interactCollectible(eggs[rank], token)
                task.wait(.7)
                storeDragonFruitCritical()
                return
            else
                setStatus("No egg assigned this run (rotating slot)")
                return
            end
        end
        task.wait(.4)
    end
end

--==============================================================
-- DRAGON HUNTER DIALOGUE / QUESTS
--==============================================================

local function visibleGui(o)
    local p = o
    while p and p ~= PG do
        if p:IsA("GuiObject") and not p.Visible then return false end
        p = p.Parent
    end
    return true
end

local function dialogueGui()
    return PG:FindFirstChild("DialogueGui")
end

local function dialogueOptions()
    local dg = dialogueGui()
    if not dg then return {} end
    local arr,seen = {},{}
    for _,v in ipairs(dg:GetDescendants()) do
        if v:IsA("TextButton") and visibleGui(v) and v.AbsoluteSize.X > 80 and v.AbsoluteSize.Y > 20 then
            local pn = v.Parent and string.lower(v.Parent.Name) or ""
            local fp = string.lower(v:GetFullName())
            if pn:find("option",1,true) or fp:find(":option",1,true) then
                if not seen[v] then
                    seen[v]=true
                    table.insert(arr,v)
                end
            end
        end
    end
    table.sort(arr,function(a,b) return a.AbsolutePosition.Y < b.AbsolutePosition.Y end)
    return arr
end

local function fireButton(btn)
    if not btn then return false end
    local function trySignal(sig)
        if getconnections then
            local ok,cons = pcall(function() return getconnections(sig) end)
            if ok then
                for _,c in ipairs(cons) do
                    if c.Fire then pcall(function() c:Fire() end)
                    elseif c.Function then pcall(function() c.Function() end) end
                end
            end
        end
        if firesignal then pcall(function() firesignal(sig) end) end
    end
    trySignal(btn.MouseButton1Click)
    task.wait(.12)
    return true
end

local function openDragonHunter(token)
    safeTween(CONFIG.DRAGON_HUNTER.STAND, 260, token)

    for _=1,6 do
        local opts = dialogueOptions()
        if #opts >= 3 then return true end

        local cam = workspace.CurrentCamera
        if cam then
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, CONFIG.DRAGON_HUNTER.NPC.Position)
            local p,on = cam:WorldToViewportPoint(CONFIG.DRAGON_HUNTER.NPC.Position)
            if on then
                VirtualInputManager:SendMouseButtonEvent(p.X,p.Y,0,true,game,0)
                task.wait(.08)
                VirtualInputManager:SendMouseButtonEvent(p.X,p.Y,0,false,game,0)
            end
        end
        task.wait(.35)
    end
    return #dialogueOptions() >= 3
end

local function questText()
    local dg = dialogueGui()
    if not dg then return "" end
    for _,v in ipairs(dg:GetDescendants()) do
        if v:IsA("TextLabel") or v:IsA("TextButton") then
            local t = tostring(v.Text or "")
            local l = string.lower(t)
            if l:find("hydra enforcer",1,true)
                or l:find("venomous assailant",1,true)
                or l:find("destroy 10 trees",1,true) then
                return t
            end
        end
    end
    return ""
end

local function questKind()
    local l = string.lower(questText())
    if l:find("hydra enforcer",1,true) then return "HYDRA" end
    if l:find("venomous assailant",1,true) then return "VENOM" end
    if l:find("destroy 10 trees",1,true) then return "TREE" end
    return "NONE"
end

local function receiveDragonHunterQuest(token)
    if questKind() ~= "NONE" then return true end
    if not openDragonHunter(token) then return false end

    local opts = dialogueOptions()
    if #opts < 3 then return false end
    fireButton(opts[1]) -- Hunt

    local deadline = os.clock()+2
    repeat
        task.wait(.12)
        if questKind() ~= "NONE" then return true end
        opts = dialogueOptions()
        if #opts >= 1 and #opts <= 2 then break end
    until os.clock()>deadline

    opts = dialogueOptions()
    if #opts >= 1 then fireButton(opts[1]) end -- Sure

    deadline = os.clock()+4
    repeat
        task.wait(.15)
        if questKind() ~= "NONE" then return true end
    until os.clock()>deadline
    return false
end

local function farmTreeQuest(token)
    local i = 1
    while isRunning(token) and questKind() == "TREE" do
        local cf = CONFIG.TREES[i]
        highTween(cf * CFrame.new(0,10,0), 300, token)
        useXCVF(cf.Position)
        i = i + 1
        if i > #CONFIG.TREES then i = 1 end
        task.wait(.12)
    end
end

local function farmHunterQuest(token)
    local kind = questKind()
    if kind == "TREE" then
        farmTreeQuest(token)
    elseif kind == "HYDRA" then
        while isRunning(token) and questKind() == "HYDRA" do
            farmNamedMob("Hydra Enforcer", CONFIG.MOB_CAMPS.HydraEnforcer, token)
        end
    elseif kind == "VENOM" then
        while isRunning(token) and questKind() == "VENOM" do
            farmNamedMob("Venomous Assailant", CONFIG.MOB_CAMPS.VenomousAssailant, token)
        end
    end
end

local function farmBlazeEmbers(token)
    while isRunning(token) and inventoryCount("Blaze Ember") < 15 do
        setStatus("Blaze Ember "..inventoryCount("Blaze Ember").."/15")
        if not goHydra(token) then
            setStatus("Hydra portal failed - NOT flying across sea")
            task.wait(1)
            continue
        end
        if questKind() == "NONE" then
            receiveDragonHunterQuest(token)
        end
        farmHunterQuest(token)
        task.wait(.4)
    end
end

-- Forest Pirate/Scrap Metal farming is intentionally island-local.
-- Once Turtle is confirmed, this routine never long-distance tweens to another island.
local function isForestPirate(m)
    if not m or not m:IsA("Model") then return false end
    return string.find(string.lower(m.Name), "forest pirate", 1, true) ~= nil
end

local function aliveForestPirates(centerPos, radius)
    local result = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return result end

    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) then
            local h = m:FindFirstChildOfClass("Humanoid")
            local rr = m:FindFirstChild("HumanoidRootPart")
            if h and rr and h.Health > 0 then
                local d = (rr.Position - centerPos).Magnitude
                if d <= radius then
                    result[#result+1] = {model=m, distance=d}
                end
            end
        end
    end

    table.sort(result, function(a,b) return a.distance < b.distance end)
    return result
end

local function magnetForestPirates(anchorCF, radius)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return 0 end

    local count = 0
    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) then
            local h = m:FindFirstChildOfClass("Humanoid")
            local rr = m:FindFirstChild("HumanoidRootPart")
            if h and rr and h.Health > 0 and (rr.Position - anchorCF.Position).Magnitude <= radius then
                count = count + 1
                pcall(function()
                    rr.CFrame = anchorCF
                    rr.Size = Vector3.new(55,55,55)
                    rr.CanCollide = false
                    h.WalkSpeed = 0
                    h.JumpPower = 0
                end)
            end
        end
    end
    return count
end

local function farmScrap(token)
    local camp = CONFIG.MOB_CAMPS.ForestPirate
    local scanRadius = 850
    local magnetRadius = 650
    local patrol = {
        CFrame.new(0,0,0),
        CFrame.new(170,0,0),
        CFrame.new(-170,0,0),
        CFrame.new(0,0,170),
        CFrame.new(0,0,-170),
        CFrame.new(240,0,180),
        CFrame.new(-240,0,180),
        CFrame.new(240,0,-180),
        CFrame.new(-240,0,-180),
    }
    local patrolIndex = 1

    while isRunning(token) and inventoryCount("Scrap Metal") < 10 do
        local scrap = inventoryCount("Scrap Metal")
        setStatus("Scrap Metal "..scrap.."/10 | route -> Floating Turtle")

        if not goTurtle(token) then
            setStatus("Turtle portal failed - retrying portal only")
            task.wait(1)
            continue
        end

        -- Hard guard: never start Forest Pirate farming unless the portal destination
        -- was actually confirmed as Floating Turtle.
        if getRegion() ~= "TURTLE" then
            setStatus("Not on Floating Turtle -> abort Scrap farm cycle")
            task.wait(.8)
            continue
        end

        -- Move only to the user-captured safe point beside the Forest Pirate area.
        highTween(camp * CFrame.new(0,18,0), CONFIG.PLAYER_TWEEN_SPEED, token)
        if not isRunning(token) then break end
        if getRegion() ~= "TURTLE" then
            setStatus("Left Turtle unexpectedly -> stop local farm")
            task.wait(.8)
            continue
        end

        local noMobPasses = 0
        while isRunning(token)
            and getRegion() == "TURTLE"
            and inventoryCount("Scrap Metal") < 10 do

            local mobs = aliveForestPirates(camp.Position, scanRadius)

            if #mobs == 0 then
                noMobPasses = noMobPasses + 1
                local off = patrol[patrolIndex]
                patrolIndex = patrolIndex + 1
                if patrolIndex > #patrol then patrolIndex = 1 end

                setStatus("Scrap Metal "..inventoryCount("Scrap Metal").."/10 | scanning Forest Pirates")
                highTween(camp * off * CFrame.new(0,18,0), 260, token)
                task.wait(noMobPasses >= #patrol and 1.2 or .45)
            else
                noMobPasses = 0

                -- Pull the current local wave to one point and use Melee M1 only.
                local anchor = CFrame.new(camp.Position + Vector3.new(0,2,0))
                safeTween(anchor * CFrame.new(0,16,0), 300, token)

                local waveDeadline = os.clock() + 18
                while isRunning(token)
                    and getRegion() == "TURTLE"
                    and inventoryCount("Scrap Metal") < 10
                    and os.clock() < waveDeadline do

                    local alive = magnetForestPirates(anchor, magnetRadius)
                    if alive <= 0 then break end

                    local tool = equipTooltip("Melee")
                    if tool and tool.Parent == char() then
                        pcall(function() tool:Activate() end)
                    end
                    task.wait(.10)
                end

                task.wait(.35)
                setStatus("Scrap Metal "..inventoryCount("Scrap Metal").."/10 | Forest Pirate wave cleared")
            end
        end
    end

    if inventoryCount("Scrap Metal") >= 10 then
        setStatus("Scrap Metal ready: "..inventoryCount("Scrap Metal").."/10")
        return true
    end
    return false
end

local function findTextObject(textNeedle)
    local needle = string.lower(textNeedle)
    for _,v in ipairs(PG:GetDescendants()) do
        if (v:IsA("TextButton") or v:IsA("TextLabel")) and visibleGui(v) then
            if string.lower(tostring(v.Text or "")):find(needle,1,true) then
                return v
            end
        end
    end
end

local function clickRecipeByText(textNeedle)
    local o = findTextObject(textNeedle)
    if not o then return false end
    if o:IsA("TextButton") then fireButton(o) return true end
    local p=o.Parent
    for _=1,6 do
        if not p then break end
        if p:IsA("TextButton") then fireButton(p) return true end
        p=p.Parent
    end
    return false
end

local function findCraftButton()
    for _,v in ipairs(PG:GetDescendants()) do
        if v:IsA("TextButton") and visibleGui(v) then
            local t = string.lower(tostring(v.Text or "")):gsub("%s+","")
            if t == "craft" then return v end
        end
    end
end

local function openCraftMenu(token)
    if not openDragonHunter(token) then return false end
    local opts = dialogueOptions()
    if #opts < 2 then return false end
    fireButton(opts[2]) -- Craft from Hunt/Craft/Gacha/Nevermind menu
    task.wait(.5)
    return findTextObject("volcanic magnet") ~= nil or findTextObject("select a recipe") ~= nil
end

local function craftVolcanicMagnet(token)
    if not goHydra(token) then
        setStatus("Hydra portal failed - craft cancelled")
        return false
    end
    if not openCraftMenu(token) then
        setStatus("Craft menu failed to open")
        return false
    end

    clickRecipeByText("volcanic magnet")
    task.wait(.35)

    local btn = findCraftButton()
    if not btn then
        setStatus("Craft button absent -> materials still insufficient")
        return false
    end

    fireButton(btn)
    task.wait(1)
    return hasVolcanicMagnet()
end

local function recoverMagnet(token)
    if hasVolcanicMagnet() then return true end

    setStatus("RECOVERY: Volcanic Magnet missing")

    -- IMPORTANT: never reset again during portal recovery.
    -- The only reset in the whole post-event flow happens in resetBackToTiki().
    -- A second reset here could kill the character right after Hydra/Turtle -> Castle.
    if getRegion() ~= "TIKI" then
        setStatus("RECOVERY: returning to Tiki without reset")
        if not goTiki(token) then
            setStatus("RECOVERY: failed to return to Tiki")
            return false
        end
    end
    if not isRunning(token) then return false end

    if inventoryCount("Scrap Metal") < 10 then
        farmScrap(token)
    end
    if not isRunning(token) then return false end

    if inventoryCount("Blaze Ember") < 15 then
        farmBlazeEmbers(token)
    end
    if not isRunning(token) then return false end

    for attempt=1,4 do
        if craftVolcanicMagnet(token) then
            setStatus("Volcanic Magnet crafted")
            return true
        end
        setStatus("Craft retry "..attempt.."/4")
        if inventoryCount("Scrap Metal") < 10 then farmScrap(token) end
        if inventoryCount("Blaze Ember") < 15 then farmBlazeEmbers(token) end
    end

    setStatus("RECOVERY FAILED: no Volcanic Magnet")
    return false
end

--==============================================================
-- COMPLETE EVENT FLOW
--==============================================================

local function runPrehistoricEvent(island, token)
    if not island or not island.Parent then return end

    local key = tostring(math.floor(island:GetPivot().Position.X))..":"..tostring(math.floor(island:GetPivot().Position.Z))
    if lastIslandWebhookKey ~= key then
        lastIslandWebhookKey = key
        sendWebhook("🌋 PREHISTORIC ISLAND FOUND", "Team is moving to Fossil Relic.", {
            {name="Server", value=tostring(game.JobId), inline=false},
            {name="Account", value=LP.Name, inline=true},
            {name="Role", value=roleText(), inline=true},
        })
    end

    setStatus("Prehistoric found -> Fossil Relic")
    moveToRelic(island, token)

    if isMaster() then
        startEventAsMaster(island, token)
    else
        while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") ~= true do
            moveToRelic(island, token)
            task.wait(.4)
        end
    end

    if not isRunning(token) or not island.Parent then return end
    if island:GetAttribute("IsMinigameActive") ~= true then
        setStatus("Event failed to start")
        return
    end

    if isMaster() then
        masterPressureLoop(island, token)
    else
        slaveGolemLoop(island, token)
    end

    if not isRunning(token) then return end

    setStatus("Event ended -> rewards")
    task.wait(1.2)

    collectBones(island, token)
    if not isRunning(token) then return end
    collectAssignedEgg(island, token)
    if not isRunning(token) then return end
    storeDragonFruitCritical()

    task.wait(.5)

    -- User requirement: after the Volcano rewards are collected, every account
    -- resets and ends up back at Tiki before deciding whether Magnet recovery is needed.
    if resetBackToTiki then
        resetBackToTiki(token)
    end
    if not isRunning(token) then return end

    if not hasVolcanicMagnet() then
        recoverMagnet(token)
    end
end

--==============================================================
-- MASTER / SLAVE CYCLES
--==============================================================

local function masterCycle(token)
    if not hasVolcanicMagnet() then
        if not recoverMagnet(token) then return end
    end

    goTiki(token)
    local boat = buyGrandBrigade(token)
    if not boat then
        setStatus("MASTER: boat spawn failed")
        task.wait(2)
        return
    end

    boardBoat(boat, token)
    setStatus("MASTER: waiting all 5 aboard")

    while isRunning(token) and boat.Parent and not findPrehistoric() do
        local n = countTeamAboard(boat)
        if n >= #CONFIG.TEAM then break end
        setStatus("Waiting passengers "..n.."/"..#CONFIG.TEAM)
        task.wait(.5)
    end

    if not isRunning(token) then return end
    local island = findPrehistoric()
    if not island and boat.Parent then
        island = searchSeaUntilIsland(boat, token)
    end
    if island then runPrehistoricEvent(island, token) end
end

local function slaveCycle(token)
    if not hasVolcanicMagnet() then
        if not recoverMagnet(token) then return end
    end

    setStatus("SLAVE: waiting MASTER boat")
    local boat
    while isRunning(token) do
        local island = findPrehistoric()
        if island then
            runPrehistoricEvent(island, token)
            return
        end
        boat = getMasterBoat()
        if boat then break end
        task.wait(.5)
    end

    if not isRunning(token) or not boat then return end

    if not boardBoat(boat, token) then
        setStatus("SLAVE: seat failed, retry")
        task.wait(.5)
        return
    end

    setStatus("SLAVE: seated, waiting island")
    while isRunning(token) and boat.Parent do
        local island = findPrehistoric()
        if island then
            runPrehistoricEvent(island, token)
            return
        end
        task.wait(.3)
    end
end

local function mainLoop(token)
    if not isTeamName(LP.Name) then
        setStatus("This account is not in CONFIG.TEAM")
        _G.TeamConfig.IsRunning = false
        return
    end

    ensureMarines()

    while isRunning(token) do
        pcall(ensureMarines)

        local island = findPrehistoric()
        if island then
            local ok,err = pcall(runPrehistoricEvent, island, token)
            if not ok then setStatus("EVENT ERROR: "..tostring(err)) task.wait(1) end
        else
            if isMaster() then
                local ok,err = pcall(masterCycle, token)
                if not ok then setStatus("MASTER ERROR: "..tostring(err)) task.wait(1) end
            else
                local ok,err = pcall(slaveCycle, token)
                if not ok then setStatus("SLAVE ERROR: "..tostring(err)) task.wait(1) end
            end
        end

        task.wait(.5)
    end
end

--==============================================================
-- UI: MASTER SELECTION + START / STOP
--==============================================================

-- Delta-safe: always parent the real controls to PlayerGui.
-- gethui/CoreGui are only cleaned up so an older invisible copy cannot interfere.
local guiParent = PG

pcall(function()
    local x = CoreGui:FindFirstChild("PrehistoricTeamV1")
    if x then x:Destroy() end
end)

if gethui then
    pcall(function()
        local h = gethui()
        if h then
            local x = h:FindFirstChild("PrehistoricTeamV1")
            if x then x:Destroy() end
        end
    end)
end

local old = guiParent:FindFirstChild("PrehistoricTeamV1")
if old then old:Destroy() end

local SG = Instance.new("ScreenGui")
SG.Name = "PrehistoricTeamV1"
SG.ResetOnSpawn = false
SG.IgnoreGuiInset = false
SG.DisplayOrder = 999999
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.Enabled = true
SG.Parent = guiParent

local F = Instance.new("Frame")
F.Parent = SG
F.Size = UDim2.fromOffset(385, 315)
F.Position = UDim2.new(0.5,-192,0.12,0)
F.BackgroundColor3 = Color3.fromRGB(20,20,26)
F.BorderSizePixel = 1
F.BorderColor3 = Color3.fromRGB(0,150,255)
F.Active = true
F.Draggable = true

local TITLE = Instance.new("TextLabel")
TITLE.Parent = F
TITLE.Size = UDim2.new(1,0,0,32)
TITLE.BackgroundColor3 = Color3.fromRGB(30,30,40)
TITLE.TextColor3 = Color3.new(1,1,1)
TITLE.Font = Enum.Font.SourceSansBold
TITLE.TextSize = 15
TITLE.Text = "🌋 PREHISTORIC TEAM V1.6 | DELTA"

local MASTER_BOX = Instance.new("TextBox")
MASTER_BOX.Parent = F
MASTER_BOX.Size = UDim2.new(1,-20,0,32)
MASTER_BOX.Position = UDim2.fromOffset(10,42)
MASTER_BOX.BackgroundColor3 = Color3.fromRGB(38,38,48)
MASTER_BOX.TextColor3 = Color3.new(1,1,1)
MASTER_BOX.PlaceholderText = "MASTER / BUY BOAT username"
MASTER_BOX.Text = CONFIG.MASTER_NAME
MASTER_BOX.ClearTextOnFocus = false

local APPLY = Instance.new("TextButton")
APPLY.Parent = F
APPLY.Size = UDim2.new(1,-20,0,30)
APPLY.Position = UDim2.fromOffset(10,80)
APPLY.BackgroundColor3 = Color3.fromRGB(55,100,155)
APPLY.TextColor3 = Color3.new(1,1,1)
APPLY.Font = Enum.Font.SourceSansBold
APPLY.Text = "SET MASTER FOR THIS CLIENT"

local ROLE = Instance.new("TextLabel")
ROLE.Parent = F
ROLE.Size = UDim2.new(1,-20,0,35)
ROLE.Position = UDim2.fromOffset(10,116)
ROLE.BackgroundTransparency = 1
ROLE.TextColor3 = Color3.fromRGB(100,220,255)
ROLE.Font = Enum.Font.SourceSansBold
ROLE.TextWrapped = true

STATUS_LABEL = Instance.new("TextLabel")
STATUS_LABEL.Parent = F
STATUS_LABEL.Size = UDim2.new(1,-20,0,78)
STATUS_LABEL.Position = UDim2.fromOffset(10,150)
STATUS_LABEL.BackgroundColor3 = Color3.fromRGB(14,14,19)
STATUS_LABEL.TextColor3 = Color3.fromRGB(255,210,80)
STATUS_LABEL.Font = Enum.Font.SourceSansSemibold
STATUS_LABEL.TextWrapped = true
STATUS_LABEL.Text = "READY"

local START = Instance.new("TextButton")
START.Parent = F
START.Size = UDim2.new(1,-20,0,42)
START.Position = UDim2.fromOffset(10,238)
START.BackgroundColor3 = Color3.fromRGB(45,150,70)
START.TextColor3 = Color3.new(1,1,1)
START.Font = Enum.Font.SourceSansBold
START.TextSize = 16
START.Text = "▶ START FULL AUTO"

local NOTE = Instance.new("TextLabel")
NOTE.Parent = F
NOTE.Size = UDim2.new(1,-20,0,25)
NOTE.Position = UDim2.fromOffset(10,284)
NOTE.BackgroundTransparency = 1
NOTE.TextColor3 = Color3.fromRGB(180,180,190)
NOTE.TextSize = 12
NOTE.Text = "All 5 clients must use the same MASTER username."

local function refreshRole()
    _G.TeamConfig.IsMaster = LP.Name == _G.TeamConfig.MasterName
    ROLE.Text = "LOCAL: "..LP.Name.."\nROLE: "..roleText().." | MASTER: ".._G.TeamConfig.MasterName
end

APPLY.MouseButton1Click:Connect(function()
    local n = MASTER_BOX.Text:gsub("%s+","")
    if n ~= "" then
        _G.TeamConfig.MasterName = n
        CONFIG.MASTER_NAME = n
        refreshRole()
        setStatus("Master set locally: "..n)
    end
end)

START.MouseButton1Click:Connect(function()
    if _G.TeamConfig.IsRunning then
        _G.TeamConfig.IsRunning = false
        RUN_TOKEN = RUN_TOKEN + 1
        START.Text = "▶ START FULL AUTO"
        START.BackgroundColor3 = Color3.fromRGB(45,150,70)
        disableLavaProtection()
        setStatus("STOPPED")
        return
    end

    local n = MASTER_BOX.Text:gsub("%s+","")
    if n ~= "" then
        _G.TeamConfig.MasterName = n
        CONFIG.MASTER_NAME = n
    end
    refreshRole()

    RUN_TOKEN = RUN_TOKEN + 1
    local token = RUN_TOKEN
    _G.TeamConfig.IsRunning = true
    START.Text = "⏹ STOP FULL AUTO"
    START.BackgroundColor3 = Color3.fromRGB(160,55,55)
    setStatus("STARTED | "..roleText())

    task.spawn(function()
        mainLoop(token)
        if token == RUN_TOKEN then
            _G.TeamConfig.IsRunning = false
            START.Text = "▶ START FULL AUTO"
            START.BackgroundColor3 = Color3.fromRGB(45,150,70)
        end
    end)
end)

refreshRole()

-- The real UI exists now, remove the boot banner.
if BOOT_GUI and BOOT_GUI.Parent then
    BOOT_GUI:Destroy()
end
setStatus("UI READY | "..roleText().." | press START FULL AUTO")

-- Keep Marine team alive without spamming the server.
task.spawn(function()
    while SG.Parent do
        task.wait(10)
        if _G.TeamConfig.IsRunning then
            pcall(ensureMarines)
        end
    end
end)
