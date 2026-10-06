--[[
    PREHISTORIC TEAM V2.5.1 (DELTA PARSE SAFE + COUNTERS + DRAGON GUARD + SAVE CPU)
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
local Lighting = game:GetService("Lighting")

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
BOOT_LABEL.Text = "PREHISTORIC V2.5.1 PARSE SAFE\nLoading automation..."
BOOT_LABEL.ZIndex = 999999

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if not remotes then
    BOOT_LABEL.Text = "PREHISTORIC V2 ERROR\nReplicatedStorage.Remotes not found"
    return
end

local CommF = remotes:WaitForChild("CommF_", 20)
if not CommF then
    BOOT_LABEL.Text = "PREHISTORIC V2 ERROR\nCommF_ not found"
    return
end

BOOT_LABEL.Text = "PREHISTORIC V2.5.1 PARSE SAFE\nLoaded core, building UI..."

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
    FOREST_FARM_HEIGHT = 32,
    FOREST_HITBOX_SIZE = 60,
    FOREST_MAGNET_RADIUS = 900,
    FOREST_SCAN_RADIUS = 1400,
    FOREST_GHOST_TIMEOUT = 10,
    FOREST_GHOST_MIN_ATTACKS = 100,
    HOVER_SNAP_DISTANCE = 2.5,
    MELEE_HITBOX_MAGNITUDE = 120,
    MELEE_NET_DISTANCE = 120,
    MELEE_ATTACK_INTERVAL = 0.06,
    MELEE_CLICK_DELAY = 0,
    PORTAL_CHAIN_DELAY = 2.5,
    RESPAWN_SETTLE_DELAY = 1.5,
    RESET_TO_TIKI_AFTER_EVENT = true,

    ITEM_COUNTER = {
        CACHE_SECONDS = 0.65,
        OPTIMISTIC_GAIN_SECONDS = 180,
    },

    DRAGON_GUARD = {
        STORE_RETRIES = 6,
        RETRY_DELAY = 0.45,
        POST_EGG_GUARD_SECONDS = 4.5,
        PRE_RESET_GUARD_SECONDS = 8.0,
    },

    -- SAFE low-CPU mode: visual-only changes. It never destroys Workspace.Map,
    -- Enemies, Boats, portal parts, or PrehistoricIsland logic objects.
    SAVE_CPU = {
        ENABLED = true,
        FPS_CAP = 30,
        HIDE_STATIC_MAP_VISUALS = true,
        HIDE_TEXTURES_DECALS = true,
        DISABLE_NONESSENTIAL_VFX = true,
        REDUCE_TERRAIN = true,
        LOW_GRAPHICS_QUALITY = true,
        FULL_3D_RENDER_OFF = false, -- strongest saving; leave false so you can still see the game
    },

    DEBUG = {
        ENABLED = true,
        LOG_TO_FILE = true,
        SNAPSHOT_INTERVAL = 15,
        WATCHDOG_SECONDS = 120,
        WATCHDOG_RESTART = true,
        WEBHOOK_ERRORS = true,
        MAX_MEMORY_LOG_LINES = 6000,
    },

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
local COUNTER_LABEL

local ITEM_TRACK = {}
local INVENTORY_CACHE = {Raw=nil, At=-math.huge}
local PICKUP_WATCHED = setmetatable({}, {__mode="k"})
local DRAGON_GUARD_STATE = {Busy=false, LastStored=nil, Critical=false}
local SAVE_CPU_APPLIED = false

-- Forest Pirate runtime state. Weak-key tables automatically forget despawned models.
local FOREST_GHOST_BLACKLIST = setmetatable({}, {__mode = "k"})
local FOREST_DAMAGE_TRACK = setmetatable({}, {__mode = "k"})
local ACTIVE_FOREST_MAGNET = {Enabled=false, Anchor=nil, Radius=0, Locked=setmetatable({}, {__mode="k"})}
local FOREST_DAMAGE_PROVEN = false
local ACTIVE_HOVER = {Root=nil, Humanoid=nil, Attachment=nil, Position=nil, Gyro=nil, Target=nil}
local lastIslandWebhookKey = nil
local lavaConnection = nil
local CHARACTER_EPOCH = 0
local lastPortalSuccessAt = -math.huge
local boundHumanoids = {}

--==============================================================
-- NIGHT DEBUG LOGGER / WATCHDOG STATE
-- No manual log file is required. If the executor supports writefile/appendfile,
-- the script creates one automatically in the executor workspace.
--==============================================================

local _nightStampOK, _nightStamp = pcall(function() return os.date("%Y%m%d_%H%M%S") end)
if not _nightStampOK then _nightStamp = tostring(math.floor(os.clock())) end

local NIGHT = {
    LogPath = "PH_Night_" .. tostring(LP.Name):gsub("[^%w_%-]", "_") .. "_" .. tostring(_nightStamp) .. ".txt",
    StartedAt = os.clock(),
    LastProgressAt = os.clock(),
    LastProgressSignature = "BOOT",
    LastStatus = nil,
    LastStatusLogAt = 0,
    RuntimeSignature = nil,
    RecoveryCount = 0,
    MemoryLines = {},
    FileReady = false,
}

local function nightTime()
    local ok, t = pcall(function() return os.date("%Y-%m-%d %H:%M:%S") end)
    return ok and t or tostring(math.floor(os.clock()))
end

local function initNightLog()
    if not CONFIG.DEBUG.ENABLED or not CONFIG.DEBUG.LOG_TO_FILE then return end
    local header = table.concat({
        "===== PREHISTORIC V2 NIGHT DEBUG =====",
        "ACCOUNT="..LP.Name,
        "MASTER="..tostring(CONFIG.MASTER_NAME),
        "JOB="..tostring(game.JobId),
        "START="..nightTime(),
        "LOG="..NIGHT.LogPath,
        "======================================",
        ""
    }, "\n")
    NIGHT.MemoryLines = {header}
    if type(writefile) == "function" then
        NIGHT.FileReady = pcall(writefile, NIGHT.LogPath, header)
    end
end

local function flushNightLog()
    if not CONFIG.DEBUG.ENABLED or not CONFIG.DEBUG.LOG_TO_FILE then return end
    -- When appendfile exists, every line is already persisted; rewriting from the
    -- memory fallback here would erase the appended overnight history.
    if type(appendfile) == "function" and NIGHT.FileReady then return end
    if type(writefile) ~= "function" then return end
    local maxLines = CONFIG.DEBUG.MAX_MEMORY_LOG_LINES or 6000
    while #NIGHT.MemoryLines > maxLines do
        table.remove(NIGHT.MemoryLines, 1)
    end
    pcall(writefile, NIGHT.LogPath, table.concat(NIGHT.MemoryLines, "\n"))
end

local function logLine(tag, message)
    if not CONFIG.DEBUG.ENABLED then return end
    local line = string.format("[%s] [%s] %s", nightTime(), tostring(tag), tostring(message))
    print("[PH-NIGHT] "..line)

    if CONFIG.DEBUG.LOG_TO_FILE then
        if type(appendfile) == "function" and NIGHT.FileReady then
            pcall(appendfile, NIGHT.LogPath, line.."\n")
        else
            NIGHT.MemoryLines[#NIGHT.MemoryLines+1] = line
            if (#NIGHT.MemoryLines % 10) == 0 then
                flushNightLog()
            end
        end
    end
end

local function noteProgress(signature)
    signature = tostring(signature or "progress")
    if signature ~= NIGHT.LastProgressSignature then
        NIGHT.LastProgressSignature = signature
        NIGHT.LastProgressAt = os.clock()
    end
end

initNightLog()
logLine("BOOT", "Script started | file="..NIGHT.LogPath.." | fileAPI="..tostring(NIGHT.FileReady or type(appendfile)=="function"))

local function setStatus(s)
    s = tostring(s)
    if STATUS_LABEL then
        STATUS_LABEL.Text = s
    end
    print("[PH-V2] " .. s)

    if NIGHT.LastStatus ~= s or (os.clock() - NIGHT.LastStatusLogAt) > 20 then
        NIGHT.LastStatus = s
        NIGHT.LastStatusLogAt = os.clock()
        logLine("STATUS", s)
        noteProgress("STATUS:"..s)
    end
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

local function bindCharacter(c)
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid", 10)
    if not h or boundHumanoids[h] then return end
    boundHumanoids[h] = true
    CHARACTER_EPOCH = CHARACTER_EPOCH + 1

    h.Died:Connect(function()
        CHARACTER_EPOCH = CHARACTER_EPOCH + 1
        local r = c:FindFirstChild("HumanoidRootPart")
        logLine("DEATH", "pos="..tostring(r and r.Position or "nil").." status="..tostring(NIGHT.LastStatus))
        setStatus("DIED -> automation paused until respawn")
    end)
end

LP.CharacterAdded:Connect(function(c)
    task.spawn(function()
        bindCharacter(c)
        c:WaitForChild("HumanoidRootPart", 10)
        task.wait(CONFIG.RESPAWN_SETTLE_DELAY)
        local rr = c:FindFirstChild("HumanoidRootPart")
        logLine("RESPAWN", "pos="..tostring(rr and rr.Position or "nil"))
        if _G.TeamConfig.IsRunning then
            setStatus("RESPAWNED -> resuming current route")
        end
    end)
end)

if LP.Character then
    task.spawn(function() bindCharacter(LP.Character) end)
end

local function waitAlive(token)
    while true do
        if token and not isRunning(token) then return nil end
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health > 0 then
            bindCharacter(c)
            return c, h, r, CHARACTER_EPOCH
        end
        task.wait(.15)
    end
end

local function waitCharacter()
    local c = waitAlive(nil)
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
    local c, h, r, epoch = waitAlive(token)
    if not c or not h or not r then return false end

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
    local died = false
    local tw
    local deathConn = h.Died:Connect(function()
        died = true
        if tw then pcall(function() tw:Cancel() end) end
    end)

    conn = RunService.Stepped:Connect(function()
        if token and not isRunning(token) then
            if tw then pcall(function() tw:Cancel() end) end
            return
        end
        if h.Health <= 0 or CHARACTER_EPOCH ~= epoch then
            died = true
            if tw then pcall(function() tw:Cancel() end) end
            return
        end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)

    local t = math.max(d / (speed or CONFIG.PLAYER_TWEEN_SPEED), 0.05)
    tw = TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tw:Play()
    tw.Completed:Wait()

    if conn then conn:Disconnect() end
    if deathConn then deathConn:Disconnect() end
    if bv and bv.Parent then bv:Destroy() end

    if died or CHARACTER_EPOCH ~= epoch or not r.Parent then
        setStatus("Movement interrupted by death -> waiting respawn")
        waitAlive(token)
        return false
    end
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
        footer = {text = "Prehistoric Team V2.5 | " .. LP.Name},
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
-- INVENTORY / LIVE ITEM COUNTERS
--==============================================================

local function normalizeItemName(v)
    local x = string.lower(tostring(v or ""))
    x = x:gsub("[%[%]{}<>]", "")
    x = x:gsub("%s+", " ")
    return x:match("^%s*(.-)%s*$") or x
end

local function getInventory(force)
    local now = os.clock()
    if not force and INVENTORY_CACHE.Raw and (now - INVENTORY_CACHE.At) < CONFIG.ITEM_COUNTER.CACHE_SECONDS then
        return INVENTORY_CACHE.Raw
    end

    local ok, inv = pcall(function()
        return CommF:InvokeServer("getInventory")
    end)
    if ok and type(inv) == "table" then
        INVENTORY_CACHE.Raw = inv
        INVENTORY_CACHE.At = now
        return inv
    end
    return INVENTORY_CACHE.Raw or {}
end

local function entryCount(v)
    if type(v) == "number" then return math.max(0, v) end
    if type(v) ~= "table" then return nil end
    local n = v.Count or v.count or v.Amount or v.amount or v.Quantity or v.quantity or v.Owned or v.owned
    n = tonumber(n)
    if n then return math.max(0, n) end
    return nil
end

local function serverInventoryCount(itemName, force)
    local wanted = normalizeItemName(itemName)
    local total = 0
    local matched = false
    local seen = {}

    local function walk(tbl, depth)
        if type(tbl) ~= "table" or seen[tbl] or depth > 3 then return end
        seen[tbl] = true
        for k,v in pairs(tbl) do
            local keyName = type(k) == "string" and normalizeItemName(k) or ""
            if type(v) == "table" then
                local name = normalizeItemName(v.Name or v.name or v.ItemName or v.itemName or v.Title or "")
                if name == wanted or keyName == wanted then
                    local n = entryCount(v)
                    total = total + (n or 1)
                    matched = true
                else
                    walk(v, depth + 1)
                end
            elseif keyName == wanted then
                local n = tonumber(v)
                if n then
                    total = total + math.max(0, n)
                    matched = true
                end
            end
        end
    end

    walk(getInventory(force), 0)
    return matched and total or 0
end

local function trackerFor(itemName)
    local key = normalizeItemName(itemName)
    local t = ITEM_TRACK[key]
    if not t then
        local server = serverInventoryCount(itemName, true)
        t = {Server=server, Optimistic=server, OptimisticUntil=0}
        ITEM_TRACK[key] = t
    end
    return t, key
end

local function inventoryCount(itemName, force)
    local t = trackerFor(itemName)
    local server = serverInventoryCount(itemName, force)
    t.Server = server

    if server >= (t.Optimistic or 0) then
        t.Optimistic = server
        t.OptimisticUntil = 0
        return server
    end

    if os.clock() <= (t.OptimisticUntil or 0) then
        return math.max(server, t.Optimistic or 0)
    end

    -- Optimistic popup count expired: trust the authoritative inventory again.
    t.Optimistic = server
    return server
end

local function clearOptimisticCount(itemName)
    local t = trackerFor(itemName)
    local server = serverInventoryCount(itemName, true)
    t.Server = server
    t.Optimistic = server
    t.OptimisticUntil = 0
    return server
end

local function recordItemGain(itemName, amount, sourceText)
    amount = math.max(1, tonumber(amount) or 1)
    local t, key = trackerFor(itemName)
    local beforeServer = t.Server or 0
    local nowServer = serverInventoryCount(itemName, true)
    t.Server = nowServer

    if nowServer > beforeServer then
        t.Optimistic = math.max(t.Optimistic or 0, nowServer)
    else
        t.Optimistic = math.max(t.Optimistic or 0, beforeServer, nowServer) + amount
        t.OptimisticUntil = os.clock() + CONFIG.ITEM_COUNTER.OPTIMISTIC_GAIN_SECONDS
    end

    logLine("ITEM_GAIN", tostring(itemName).." +"..amount.." | live="..tostring(math.max(nowServer, t.Optimistic or 0)).." | source="..tostring(sourceText))
end

local TRACKED_PICKUPS = {
    ["scrap metal"] = "Scrap Metal",
    ["blaze ember"] = "Blaze Ember",
    ["volcanic magnet"] = "Volcanic Magnet",
    ["dinosaur bones"] = "Dinosaur Bones",
    ["dinosaur bone"] = "Dinosaur Bones",
}

local function parsePickupText(text)
    local raw = tostring(text or "")
    local low = string.lower(raw)
    local amount = tonumber(raw:match("%((%d+)%s*[xX]%)") or raw:match("(%d+)%s*[xX]")) or 1
    local looksLikeGain = low:find("obtained",1,true) or low:find("received",1,true)
        or low:find("acquired",1,true) or low:find("crafted",1,true)
        or low:find("you got",1,true) or raw:match("%(%d+%s*[xX]%)")
    if not looksLikeGain then return end
    for needle,itemName in pairs(TRACKED_PICKUPS) do
        if low:find(needle,1,true) then
            recordItemGain(itemName, amount, raw)
            return
        end
    end
end

local function watchPickupTextObject(obj)
    if PICKUP_WATCHED[obj] then return end
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    PICKUP_WATCHED[obj] = tostring(obj.Text or "")

    local function inspect()
        local text = tostring(obj.Text or "")
        if text ~= PICKUP_WATCHED[obj] then
            PICKUP_WATCHED[obj] = text
            parsePickupText(text)
        end
    end

    obj:GetPropertyChangedSignal("Text"):Connect(inspect)
    parsePickupText(obj.Text)
end

for _,obj in ipairs(PG:GetDescendants()) do
    pcall(watchPickupTextObject, obj)
end
PG.DescendantAdded:Connect(function(obj)
    pcall(watchPickupTextObject, obj)
end)

local function hasVolcanicMagnet()
    return inventoryCount("Volcanic Magnet") > 0
end

--==============================================================
-- SAVE CPU / LOW GRAPHICS (SAFE: visual-only, no gameplay objects destroyed)
--==============================================================

local function isDescendantOfNamed(obj, ancestorName)
    local p = obj
    while p and p ~= workspace do
        if p.Name == ancestorName then return true end
        p = p.Parent
    end
    return false
end

local function isPressureSensorVFX(obj)
    local p = obj
    local sawRocks = false
    local sawPrehistoric = false
    while p and p ~= workspace do
        if p.Name == "VolcanoRocks" then sawRocks = true end
        if p.Name == "PrehistoricIsland" then sawPrehistoric = true end
        p = p.Parent
    end
    return sawRocks and sawPrehistoric
end

local function isDynamicGameplayPart(obj)
    if not obj then return false end
    local c = LP.Character
    if c and obj:IsDescendantOf(c) then return true end
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies and obj:IsDescendantOf(enemies) then return true end
    local boats = workspace:FindFirstChild("Boats")
    if boats and obj:IsDescendantOf(boats) then return true end
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character and obj:IsDescendantOf(p.Character) then return true end
    end
    return false
end

local function optimizeVisualObject(obj)
    if not SAVE_CPU_APPLIED or not obj or not obj.Parent then return end

    if obj:IsA("BasePart") then
        pcall(function() obj.CastShadow = false end)
        pcall(function() obj.Reflectance = 0 end)
        if CONFIG.SAVE_CPU.HIDE_STATIC_MAP_VISUALS then
            local map = workspace:FindFirstChild("Map")
            if map and obj:IsDescendantOf(map) and not isDynamicGameplayPart(obj) then
                -- LocalTransparencyModifier is render-only. Collision/touch/query and the
                -- instance tree stay intact, so portal/event logic can still use the map.
                pcall(function() obj.LocalTransparencyModifier = 1 end)
            end
        end
        return
    end

    if CONFIG.SAVE_CPU.HIDE_TEXTURES_DECALS and (obj:IsA("Texture") or obj:IsA("Decal")) then
        pcall(function() obj.Transparency = 1 end)
        return
    end

    if CONFIG.SAVE_CPU.DISABLE_NONESSENTIAL_VFX then
        if isPressureSensorVFX(obj) then
            -- Pressure detection reads Beam.Enabled / ParticleEmitter.Enabled. Never
            -- disable these sensor VFX or pressure farming would lose its runtime signal.
            return
        end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            pcall(function() obj.Enabled = false end)
            return
        end
        if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
            pcall(function() obj.Enabled = false end)
            return
        end
        if obj:IsA("Highlight") then
            pcall(function() obj.Enabled = false end)
            return
        end
    end
end

local function applySaveCpu()
    if SAVE_CPU_APPLIED or not CONFIG.SAVE_CPU.ENABLED then return end
    SAVE_CPU_APPLIED = true

    pcall(function()
        if type(setfpscap) == "function" then setfpscap(CONFIG.SAVE_CPU.FPS_CAP) end
    end)
    if CONFIG.SAVE_CPU.LOW_GRAPHICS_QUALITY then
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    end

    pcall(function() Lighting.GlobalShadows = false end)
    pcall(function() Lighting.EnvironmentDiffuseScale = 0 end)
    pcall(function() Lighting.EnvironmentSpecularScale = 0 end)

    if CONFIG.SAVE_CPU.REDUCE_TERRAIN then
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            pcall(function() terrain.Decoration = false end)
            pcall(function() terrain.WaterWaveSize = 0 end)
            pcall(function() terrain.WaterWaveSpeed = 0 end)
            pcall(function() terrain.WaterReflectance = 0 end)
            pcall(function() terrain.WaterTransparency = 1 end)
        end
    end

    local cpuObjects = workspace:GetDescendants()
    for i,obj in ipairs(cpuObjects) do
        optimizeVisualObject(obj)
        -- Yield periodically so Delta/mobile does not freeze the UI while optimizing a huge map.
        if i % 250 == 0 then task.wait() end
    end
    cpuObjects = nil
    workspace.DescendantAdded:Connect(function(obj)
        task.defer(function() pcall(optimizeVisualObject, obj) end)
    end)

    if CONFIG.SAVE_CPU.FULL_3D_RENDER_OFF then
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
    end

    logLine("SAVE_CPU", "ON | fps="..tostring(CONFIG.SAVE_CPU.FPS_CAP).." hideMap="..tostring(CONFIG.SAVE_CPU.HIDE_STATIC_MAP_VISUALS).." preservePressureVFX=true")
end

task.spawn(function()
    task.wait(1)
    applySaveCpu()
end)

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

-- Join Marines as soon as the script core is ready, before the user even presses START
-- or changes the local MASTER selection. This also handles the initial Blox Fruits team picker.
task.spawn(function()
    for attempt=1,4 do
        if ensureMarines() then
            logLine("TEAM", "Auto-joined Marines before role/master selection")
            return
        end
        task.wait(1)
    end
    logLine("TEAM", "Marine auto-join not confirmed after startup retries")
end)

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

--==============================================================
-- MELEE ATTACK BACKENDS
--==============================================================
-- V2 used Tool:Activate()/firesignal plus the legacy CombatFramework controller.
-- Current Blox Fruits clients can register melee swings through Modules.Net:
--   RE/RegisterAttack -> RE/RegisterHit
-- Keep the legacy controller only as a cooldown/range fallback. No real mouse click is used.

local CombatState = nil
local NetAttackCache = { Net = nil, RegisterAttack = nil, RegisterHit = nil }
local AttackBackendLogged = false
local AttackSuccessLogged = false

local function resolveCombatState()
    if type(CombatState) == "table" and CombatState.activeController then
        return CombatState
    end

    local ps = LP:FindFirstChild("PlayerScripts")
    local module = ps and ps:FindFirstChild("CombatFramework")
    if not module then return nil end

    local ok, framework = pcall(require, module)
    if not ok then return nil end

    if type(framework) == "table" and framework.activeController then
        CombatState = framework
        return CombatState
    end

    local candidates = {}
    if type(getupvalues) == "function" then candidates[#candidates+1] = getupvalues end
    if debug and type(debug.getupvalues) == "function" then candidates[#candidates+1] = debug.getupvalues end

    for _,getter in ipairs(candidates) do
        local ok2, ups = pcall(getter, framework)
        if ok2 and type(ups) == "table" then
            -- Most old clients expose the combat state as upvalue #2.
            local direct = ups[2]
            if type(direct) == "table" and direct.activeController then
                CombatState = direct
                return CombatState
            end
            for _,v in pairs(ups) do
                if type(v) == "table" and v.activeController then
                    CombatState = v
                    return CombatState
                end
            end
        end
    end

    return nil
end

local function resolveNetAttack()
    if NetAttackCache.RegisterAttack and NetAttackCache.RegisterHit then
        return NetAttackCache.RegisterAttack, NetAttackCache.RegisterHit
    end

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    if not net then return nil, nil end

    NetAttackCache.Net = net
    NetAttackCache.RegisterAttack = net:FindFirstChild("RE/RegisterAttack")
    NetAttackCache.RegisterHit = net:FindFirstChild("RE/RegisterHit")
    return NetAttackCache.RegisterAttack, NetAttackCache.RegisterHit
end

local function buffMeleeHitbox()
    local state = resolveCombatState()
    local ac = state and state.activeController
    if not ac then return nil end

    pcall(function()
        ac.hitboxMagnitude = CONFIG.MELEE_HITBOX_MAGNITUDE
        ac.timeToNextAttack = 0
        ac.timeToNextBlock = 0
        ac.focusStart = 0
        ac.attacking = false
        ac.blocking = false
        ac.increment = 4
        ac.currentAttackTrack = 0
        if ac.humanoid then ac.humanoid.AutoRotate = true end
    end)

    return ac
end

local function normalizeAttackModels(models)
    if typeof(models) == "Instance" then
        return {models}
    end
    if type(models) == "table" then
        return models
    end
    return nil
end

local function collectNetHits(models, distance)
    local rp = root()
    if not rp then return nil, {} end

    local list = normalizeAttackModels(models)
    local hits, basePart, seen = {}, nil, {}

    local function addEnemy(enemy)
        if not enemy or seen[enemy] or not enemy.Parent then return end
        local eh = enemy:FindFirstChildOfClass("Humanoid")
        local part = enemy:FindFirstChild("Head") or enemy:FindFirstChild("HumanoidRootPart")
        if not eh or eh.Health <= 0 or not part then return end
        if (part.Position - rp.Position).Magnitude > (distance or CONFIG.MELEE_NET_DISTANCE) then return end
        seen[enemy] = true
        basePart = basePart or part
        hits[#hits+1] = {enemy, part}
    end

    if list then
        for _,enemy in ipairs(list) do addEnemy(enemy) end
    else
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies then
            for _,enemy in ipairs(enemies:GetChildren()) do addEnemy(enemy) end
        end
    end

    return basePart, hits
end

local function attackViaNet(models)
    local registerAttack, registerHit = resolveNetAttack()
    if not registerAttack or not registerHit then return false, 0, "NET_MISSING" end

    local basePart, hits = collectNetHits(models, CONFIG.MELEE_NET_DISTANCE)
    if not basePart or #hits == 0 then return false, 0, "NO_HITS" end

    local okA = pcall(function()
        registerAttack:FireServer(CONFIG.MELEE_CLICK_DELAY)
    end)
    local okH = pcall(function()
        registerHit:FireServer(basePart, hits)
    end)

    return okA and okH, #hits, (okA and okH) and "NET" or "NET_ERROR"
end

local function attackViaLeftClickRemote(tool, models)
    if not tool then return false, 0 end
    local remote = tool:FindFirstChild("LeftClickRemote")
    if not remote or not remote.FireServer then return false, 0 end

    local rp = root()
    if not rp then return false, 0 end
    local list = normalizeAttackModels(models) or {}
    local fired = 0

    for _,enemy in ipairs(list) do
        local eh = enemy and enemy:FindFirstChildOfClass("Humanoid")
        local erp = enemy and (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Head"))
        if eh and eh.Health > 0 and erp then
            local delta = erp.Position - rp.Position
            if delta.Magnitude <= CONFIG.MELEE_NET_DISTANCE and delta.Magnitude > 0 then
                local ok = pcall(function() remote:FireServer(delta.Unit, 1) end)
                if ok then fired = fired + 1 end
            end
        end
    end

    return fired > 0, fired
end

local function virtualMeleeAttack(tool, models)
    if not tool or not char() or tool.Parent ~= char() then return false, "NO_TOOL" end

    local ac = buffMeleeHitbox()
    local registerAttack, registerHit = resolveNetAttack()
    if not AttackBackendLogged then
        AttackBackendLogged = true
        logLine("ATTACK_BACKEND", "RegisterAttack="..tostring(registerAttack ~= nil).." RegisterHit="..tostring(registerHit ~= nil).." CombatFramework="..tostring(ac ~= nil).." LeftClickRemote="..tostring(tool:FindFirstChild("LeftClickRemote") ~= nil))
    end

    -- Modern backend first. This is what actually tells the server that a melee swing hit.
    local okNet, hitCount, backend = attackViaNet(models)
    if okNet then return true, backend, hitCount end

    -- Some equipped tools expose a dedicated left-click remote. Still no screen/real click.
    local okLeft, leftCount = attackViaLeftClickRemote(tool, models)
    if okLeft then return true, "LEFT_CLICK_REMOTE", leftCount end

    -- Legacy controller fallback for older client layouts.
    if ac and type(ac.attack) == "function" then
        local ok = pcall(function() ac:attack() end)
        if ok then return true, "COMBAT_FRAMEWORK", 0 end
    end

    -- Final Roblox Tool fallback. This is activation of the Tool object, not a screen click.
    local ok = pcall(function() tool:Activate() end)
    if ok then return true, "TOOL_ACTIVATE", 0 end

    return false, backend or "NO_BACKEND", hitCount or 0
end

local function virtualToolClick(tool, models)
    return virtualMeleeAttack(tool, models)
end

-- Pin legacy controller values while automation is active. Modern Net attack does not
-- depend on hitboxMagnitude, but keeping this helps on old servers/client layouts.
task.spawn(function()
    while task.wait(0.05) do
        if _G.TeamConfig and _G.TeamConfig.IsRunning then
            pcall(buffMeleeHitbox)
        end
    end
end)

local function meleeM1(targetModel, token)
    local h = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
    local rr = targetModel and targetModel:FindFirstChild("HumanoidRootPart")
    if not h or not rr then return false end

    local _,_,_,epoch = waitAlive(token)
    if not epoch then return false end

    pcall(function()
        rr.CanCollide = false
        rr.Size = Vector3.new(110,110,110)
    end)

    local tool = equipTooltip("Melee")
    while h.Parent and h.Health > 0 and (not token or isRunning(token)) do
        if CHARACTER_EPOCH ~= epoch or not hum() or hum().Health <= 0 then
            setStatus("Died during mob farm -> pause and resume after respawn")
            waitAlive(token)
            return false
        end
        rr = targetModel:FindFirstChild("HumanoidRootPart")
        if not rr then break end
        if not safeTween(rr.CFrame * CFrame.new(0, 16, 0), 330, token) then return false end
        aimAt(rr.Position)
        tool = equipTooltip("Melee") or tool
        buffMeleeHitbox()
        if tool and tool.Parent == char() then virtualToolClick(tool, {targetModel}) end
        task.wait(CONFIG.MELEE_ATTACK_INTERVAL)
    end
    return h.Health <= 0
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
local function waitPortalChainDelay(token)
    local remain = CONFIG.PORTAL_CHAIN_DELAY - (os.clock() - lastPortalSuccessAt)
    if remain <= 0 then return true end
    setStatus(string.format("Portal cooldown %.1fs before next gate", remain))
    local untilAt = os.clock() + remain
    while os.clock() < untilAt do
        if token and not isRunning(token) then return false end
        if not waitAlive(token) then return false end
        task.wait(.10)
    end
    return true
end

local function markPortalSuccess()
    lastPortalSuccessAt = os.clock()
end

local function usePortal(cf, expectedRegion, token)
    for attempt=1,5 do
        if token and not isRunning(token) then return false end
        if not waitPortalChainDelay(token) then return false end
        if not waitAlive(token) then return false end

        local beforeRegion = getRegion()
        local beforeRoot = root()
        logLine("PORTAL", "attempt="..attempt.." from="..tostring(beforeRegion).." to="..tostring(expectedRegion).." pos="..tostring(beforeRoot and beforeRoot.Position or "nil"))
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
                    markPortalSuccess()
                    local afterRoot = root()
                    logLine("PORTAL_OK", "to="..tostring(expectedRegion).." pos="..tostring(afterRoot and afterRoot.Position or "nil"))
                    noteProgress("PORTAL:"..tostring(expectedRegion))
                    task.wait(.65)
                    return true
                end
            end
        end

        -- Give replication/teleport a moment before retrying.
        for _=1,8 do
            task.wait(.15)
            if getRegion() == expectedRegion then
                markPortalSuccess()
                local afterRoot = root()
                logLine("PORTAL_OK", "to="..tostring(expectedRegion).." pos="..tostring(afterRoot and afterRoot.Position or "nil"))
                noteProgress("PORTAL:"..tostring(expectedRegion))
                task.wait(.65)
                return true
            end
        end
    end

    logLine("PORTAL_FAIL", "expected="..tostring(expectedRegion).." current="..tostring(getRegion()))
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
        if not waitPortalChainDelay(token) then return false end
    end
    if getRegion() ~= "CASTLE" then return false end
    return usePortal(CONFIG.PORTALS.Castle_To_Turtle, "TURTLE", token)
end

local function goHydra(token)
    local region = getRegion()
    if region == "HYDRA" then return true end
    if region ~= "CASTLE" then
        if not goCastle(token) then return false end
        if not waitPortalChainDelay(token) then return false end
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
    if string.lower(tool.Name):find("fruit",1,true) or string.lower(tool.Name):find("dragon",1,true) then
        return tool.Name
    end
end

local function isDragonFruitTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local orig = fruitOriginalName(tool)
    local combined = string.lower(tostring(orig or "").." "..tostring(tool.Name or ""))
    return combined:find("dragon",1,true) ~= nil
end

local function findPhysicalDragonFruits()
    local result = {}
    local seen = {}
    for _,container in ipairs({LP.Backpack, char()}) do
        if container then
            for _,v in ipairs(container:GetChildren()) do
                if v:IsA("Tool") and isDragonFruitTool(v) and not seen[v] then
                    seen[v] = true
                    result[#result+1] = v
                end
            end
        end
    end
    return result
end

local function findPhysicalDragonFruit()
    local list = findPhysicalDragonFruits()
    local tool = list[1]
    return tool, tool and fruitOriginalName(tool) or nil
end

local function storedDragonFruitCount(originalName)
    local ok, fruits = pcall(function()
        return CommF:InvokeServer("getInventoryFruits")
    end)
    if not ok or type(fruits) ~= "table" then return nil end

    local wanted = normalizeItemName(originalName)
    local total = 0
    for k,v in pairs(fruits) do
        if type(v) == "table" then
            local n = normalizeItemName(v.Name or v.OriginalName or v.name or k)
            if n == wanted or (n:find("dragon",1,true) and wanted:find("dragon",1,true)) then
                total = total + (entryCount(v) or 1)
            end
        elseif type(k) == "string" then
            local n = normalizeItemName(k)
            if n == wanted or (n:find("dragon",1,true) and wanted:find("dragon",1,true)) then
                total = total + (tonumber(v) or 1)
            end
        end
    end
    return total
end

local function storeOneDragonFruit(tool)
    if not tool or not tool.Parent or not isDragonFruitTool(tool) then return true end
    local original = fruitOriginalName(tool) or tool.Name
    local beforeStored = storedDragonFruitCount(original)

    setStatus("!!! DRAGON FRUIT DETECTED: "..tostring(original).." -> STORE NOW")
    sendWebhook("🐉 DRAGON FRUIT DETECTED", "Immediate storage guard activated", {
        {name="Account", value=LP.Name, inline=true},
        {name="Fruit", value=tostring(original), inline=true},
    })
    logLine("DRAGON", "detected physical tool="..tostring(tool.Name).." original="..tostring(original).." beforeStored="..tostring(beforeStored))

    for attempt=1,CONFIG.DRAGON_GUARD.STORE_RETRIES do
        if not tool.Parent then
            DRAGON_GUARD_STATE.LastStored = original
            return true
        end

        local ok, result = pcall(function()
            return CommF:InvokeServer("StoreFruit", original, tool)
        end)
        task.wait(CONFIG.DRAGON_GUARD.RETRY_DELAY)

        local afterStored = storedDragonFruitCount(original)
        local disappeared = tool.Parent == nil
        local countIncreased = beforeStored ~= nil and afterStored ~= nil and afterStored > beforeStored
        logLine("DRAGON_STORE", "attempt="..attempt.." pcall="..tostring(ok).." result="..tostring(result).." disappeared="..tostring(disappeared).." storedBefore="..tostring(beforeStored).." storedAfter="..tostring(afterStored))

        if disappeared or countIncreased then
            DRAGON_GUARD_STATE.LastStored = original
            sendWebhook("✅ DRAGON FRUIT STORED", "Physical Dragon fruit secured before reset/teleport.", {
                {name="Account", value=LP.Name, inline=true},
                {name="Fruit", value=tostring(original), inline=true},
                {name="Attempt", value=tostring(attempt), inline=true},
            })
            setStatus("Dragon stored: "..tostring(original))
            return true
        end

        -- Some executors/games refresh the Tool reference after a failed call. Re-scan
        -- and continue with the newest physical Dragon tool if one exists.
        local again = findPhysicalDragonFruits()
        if #again == 0 then
            DRAGON_GUARD_STATE.LastStored = original
            return true
        end
        tool = again[1]
        original = fruitOriginalName(tool) or tool.Name
    end

    DRAGON_GUARD_STATE.Critical = true
    sendWebhook("🚨 CRITICAL: DRAGON STORE FAILED", "Automation STOPPED. Physical Dragon fruit is still loose; no reset/teleport will be attempted.", {
        {name="Account", value=LP.Name, inline=true},
        {name="Fruit", value=tostring(original), inline=true},
    })
    _G.TeamConfig.IsRunning = false
    setStatus("CRITICAL: Dragon still physical -> STOPPED, DO NOT RESET")
    logLine("DRAGON_STORE_FAIL", "physical Dragon remained after retries; automation stopped")
    return false
end

local function storeDragonFruitCritical()
    if DRAGON_GUARD_STATE.Busy then
        local deadline = os.clock() + 8
        while DRAGON_GUARD_STATE.Busy and os.clock() < deadline do task.wait(.05) end
        return #findPhysicalDragonFruits() == 0 and not DRAGON_GUARD_STATE.Critical
    end

    DRAGON_GUARD_STATE.Busy = true
    local okAll = true
    local safety = 0
    while safety < 4 do
        safety = safety + 1
        local fruits = findPhysicalDragonFruits()
        if #fruits == 0 then break end
        if not storeOneDragonFruit(fruits[1]) then
            okAll = false
            break
        end
        task.wait(.1)
    end
    DRAGON_GUARD_STATE.Busy = false
    return okAll and #findPhysicalDragonFruits() == 0
end

local function secureDragonWindow(seconds, token)
    local deadline = os.clock() + (seconds or 3)
    while os.clock() < deadline do
        if token and not isRunning(token) then return false end
        local fruits = findPhysicalDragonFruits()
        if #fruits > 0 then
            if not storeDragonFruitCritical() then return false end
        end
        task.wait(.15)
    end
    if #findPhysicalDragonFruits() > 0 then
        return storeDragonFruitCritical()
    end
    return not DRAGON_GUARD_STATE.Critical
end

-- Always-on emergency guard: if a Dragon fruit Tool appears in Backpack/Character,
-- attempt storage immediately instead of waiting for the event routine to notice it.
local function hookDragonContainer(container)
    if not container then return end
    container.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then
            task.defer(function()
                task.wait(.05)
                if isDragonFruitTool(obj) then
                    logLine("DRAGON_WATCH", "ChildAdded -> "..tostring(obj.Name))
                    storeDragonFruitCritical()
                end
            end)
        end
    end)
end

hookDragonContainer(LP.Backpack)
if char() then hookDragonContainer(char()) end
LP.CharacterAdded:Connect(function(c)
    hookDragonContainer(c)
    task.defer(function()
        task.wait(.25)
        storeDragonFruitCritical()
    end)
end)
task.defer(function() storeDragonFruitCritical() end)

local function eggPosition(obj)
    local p = interactionPart(obj)
    return p and p.Position
end

local function collectAssignedEgg(island, token)
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    if not folder then return true end

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
                setStatus("Egg assignment "..rank.."/"..#eggs.." | Dragon guard armed")
                interactCollectible(eggs[rank], token)
                -- Reward replication can lag behind the interaction. Guard this window
                -- so a physical Dragon East/West cannot appear after we already reset.
                return secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS, token)
            else
                setStatus("No egg assigned this run (rotating slot)")
                return true
            end
        end
        task.wait(.4)
    end
    return true
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
        else
            if questKind() == "NONE" then
                receiveDragonHunterQuest(token)
            end
            farmHunterQuest(token)
            task.wait(.4)
        end
    end
end

-- Forest Pirate/Scrap Metal farming is intentionally island-local.
-- V2.5 keeps the player hovering smoothly and hard-locks the mob cluster every Heartbeat.
local function isForestPirate(m)
    if not m or not m:IsA("Model") then return false end
    return string.find(string.lower(m.Name), "forest pirate", 1, true) ~= nil
end

local function isForestGhost(m)
    return FOREST_GHOST_BLACKLIST[m] == true
end

local function boostSimulationRadius()
    pcall(function()
        if setsimulationradius then setsimulationradius(math.huge, math.huge) end
    end)
    pcall(function()
        if sethiddenproperty then sethiddenproperty(LP, "SimulationRadius", math.huge) end
    end)
end

local function forestHumRoot(m)
    if not m or not m.Parent or not m:IsA("Model") then return nil, nil end
    local h = m:FindFirstChildOfClass("Humanoid")
    local rr = m:FindFirstChild("HumanoidRootPart")
    if not h or not rr or h.Health <= 0 or (h.MaxHealth and h.MaxHealth <= 0) then return nil, nil end
    return h, rr
end

local function updateForestDamageTrack(m, countedAttack)
    local h = m and m:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    local now = os.clock()
    local t = FOREST_DAMAGE_TRACK[m]
    if not t then
        t = {lastHealth=h.Health, lastDamageAt=now, attacks=0}
        FOREST_DAMAGE_TRACK[m] = t
        return false
    end

    if h.Health < (t.lastHealth - 0.05) then
        t.lastHealth = h.Health
        t.lastDamageAt = now
        t.attacks = 0
        FOREST_DAMAGE_PROVEN = true
        return false
    end

    if countedAttack then t.attacks = t.attacks + 1 end
    t.lastHealth = h.Health

    -- Never classify a mob as immortal until this farming session has already
    -- observed real HP loss on at least one Forest Pirate. This prevents a
    -- temporary attack/backend miss from blacklisting a perfectly valid mob.
    if FOREST_DAMAGE_PROVEN
        and ACTIVE_FOREST_MAGNET.Locked[m]
        and t.attacks >= CONFIG.FOREST_GHOST_MIN_ATTACKS
        and (now - t.lastDamageAt) >= CONFIG.FOREST_GHOST_TIMEOUT then
        FOREST_GHOST_BLACKLIST[m] = true
        ACTIVE_FOREST_MAGNET.Locked[m] = nil
        -- Hide stale/immortal duplicate models locally so they do not stay mixed into the real stack.
        pcall(function()
            for _,bp in ipairs(m:GetDescendants()) do
                if bp:IsA("BasePart") then
                    bp.CanCollide = false
                    bp.LocalTransparencyModifier = 1
                    bp.AssemblyLinearVelocity = Vector3.zero
                    bp.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end)
        logLine("FOREST_GHOST", "blacklisted+hidden immortal/stale model="..m:GetFullName().." hp="..tostring(h.Health).." attempts="..tostring(t.attacks))
        return true
    end
    return false
end

local function aliveForestPirates(centerPos, radius)
    local decorated = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return {} end

    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) and not isForestGhost(m) then
            local h, rr = forestHumRoot(m)
            if h and rr then
                updateForestDamageTrack(m, false)
                local d = (rr.Position - centerPos).Magnitude
                if d <= radius then
                    decorated[#decorated+1] = {model=m, distance=d}
                end
            end
        end
    end

    table.sort(decorated, function(a,b) return a.distance < b.distance end)
    local result = {}
    for _,entry in ipairs(decorated) do result[#result+1] = entry.model end
    return result
end

local function hardLockForestMob(m, anchorCF)
    if isForestGhost(m) then return false end
    local h, rr = forestHumRoot(m)
    if not h or not rr then return false end

    pcall(function()
        -- Move the whole model, not only HumanoidRootPart. Moving only HRP lets
        -- joints/server correction fling the visible body out of the stack.
        m:PivotTo(anchorCF)
        rr.CFrame = anchorCF
        rr.Size = Vector3.new(CONFIG.FOREST_HITBOX_SIZE, CONFIG.FOREST_HITBOX_SIZE, CONFIG.FOREST_HITBOX_SIZE)
        rr.Transparency = 1
        rr.CanCollide = false
        rr.CanTouch = false
        rr.AssemblyLinearVelocity = Vector3.zero
        rr.AssemblyAngularVelocity = Vector3.zero
        h.WalkSpeed = 0
        h.JumpPower = 0
        h.JumpHeight = 0
        h.AutoRotate = false
        pcall(function() h:ChangeState(Enum.HumanoidStateType.Physics) end)
        for _,bp in ipairs(m:GetDescendants()) do
            if bp:IsA("BasePart") then
                bp.CanCollide = false
                bp.AssemblyLinearVelocity = Vector3.zero
                bp.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)
    return true
end

local function setForestMagnet(enabled, anchorCF, radius)
    enabled = enabled and true or false
    if not enabled then
        ACTIVE_FOREST_MAGNET.Enabled = false
        ACTIVE_FOREST_MAGNET.Anchor = nil
        ACTIVE_FOREST_MAGNET.Locked = setmetatable({}, {__mode="k"})
        return
    end

    local resetLocked = not ACTIVE_FOREST_MAGNET.Enabled
    if ACTIVE_FOREST_MAGNET.Anchor and anchorCF then
        resetLocked = resetLocked or ((ACTIVE_FOREST_MAGNET.Anchor.Position - anchorCF.Position).Magnitude > 4)
    end
    if resetLocked then
        ACTIVE_FOREST_MAGNET.Locked = setmetatable({}, {__mode="k"})
    end
    ACTIVE_FOREST_MAGNET.Enabled = true
    ACTIVE_FOREST_MAGNET.Anchor = anchorCF
    ACTIVE_FOREST_MAGNET.Radius = radius or CONFIG.FOREST_MAGNET_RADIUS
end

-- Once a Forest Pirate enters the stack it is CLAIMED. Keep the exact models
-- pinned both before and after physics so knockback cannot visibly throw them out.
local function maintainForestMagnet()
    if not ACTIVE_FOREST_MAGNET.Enabled or not ACTIVE_FOREST_MAGNET.Anchor then return end
    boostSimulationRadius()
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return end
    local anchorCF = ACTIVE_FOREST_MAGNET.Anchor
    local radius = ACTIVE_FOREST_MAGNET.Radius

    for m in pairs(ACTIVE_FOREST_MAGNET.Locked) do
        if not m.Parent or isForestGhost(m) then
            ACTIVE_FOREST_MAGNET.Locked[m] = nil
        else
            hardLockForestMob(m, anchorCF)
        end
    end

    local rp = root()
    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) and not isForestGhost(m) and not ACTIVE_FOREST_MAGNET.Locked[m] then
            local h, rr = forestHumRoot(m)
            if h and rr then
                local nearAnchor = (rr.Position - anchorCF.Position).Magnitude <= radius
                local nearPlayer = rp and (rr.Position - rp.Position).Magnitude <= radius or false
                if nearAnchor or nearPlayer then
                    ACTIVE_FOREST_MAGNET.Locked[m] = true
                    hardLockForestMob(m, anchorCF)
                end
            end
        end
    end
end

RunService.Stepped:Connect(maintainForestMagnet)
RunService.Heartbeat:Connect(maintainForestMagnet)

local function stopStableHover()
    local h = ACTIVE_HOVER.Humanoid
    local rr = ACTIVE_HOVER.Root
    if h and h.Parent then
        pcall(function()
            h.AutoRotate = true
            h.PlatformStand = false
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    if rr and rr.Parent then
        pcall(function()
            rr.AssemblyLinearVelocity = Vector3.zero
            rr.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    for _,obj in ipairs({ACTIVE_HOVER.Position, ACTIVE_HOVER.Gyro, ACTIVE_HOVER.Attachment}) do
        if obj and obj.Parent then pcall(function() obj:Destroy() end) end
    end
    ACTIVE_HOVER.Root = nil
    ACTIVE_HOVER.Humanoid = nil
    ACTIVE_HOVER.Attachment = nil
    ACTIVE_HOVER.Position = nil
    ACTIVE_HOVER.Gyro = nil
    ACTIVE_HOVER.Target = nil
end

local function startStableHover(targetCF)
    stopStableHover()
    local rr, h = root(), hum()
    if not rr or not h or h.Health <= 0 then return false end
    rr.CFrame = targetCF
    rr.AssemblyLinearVelocity = Vector3.zero
    rr.AssemblyAngularVelocity = Vector3.zero
    h.AutoRotate = false
    h.PlatformStand = true

    local att = Instance.new("Attachment")
    att.Name = "PH_RigidHoverAttachment"
    att.Parent = rr

    local ap = Instance.new("AlignPosition")
    ap.Name = "PH_RigidHoverPosition"
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = att
    ap.ApplyAtCenterOfMass = true
    ap.Position = targetCF.Position
    ap.MaxForce = 1e9
    ap.MaxVelocity = 1e9
    ap.Responsiveness = 200
    ap.RigidityEnabled = true
    ap.Parent = rr

    local ao = Instance.new("AlignOrientation")
    ao.Name = "PH_RigidHoverOrientation"
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.Attachment0 = att
    ao.CFrame = targetCF
    ao.MaxTorque = 1e9
    ao.MaxAngularVelocity = 1e9
    ao.Responsiveness = 200
    ao.RigidityEnabled = true
    ao.Parent = rr

    ACTIVE_HOVER.Root = rr
    ACTIVE_HOVER.Humanoid = h
    ACTIVE_HOVER.Attachment = att
    ACTIVE_HOVER.Position = ap
    ACTIVE_HOVER.Gyro = ao
    ACTIVE_HOVER.Target = targetCF
    return true
end

local function maintainStableHover(targetCF)
    local rr = root()
    if not rr or ACTIVE_HOVER.Root ~= rr or not ACTIVE_HOVER.Position or not ACTIVE_HOVER.Position.Parent then
        return startStableHover(targetCF)
    end
    ACTIVE_HOVER.Target = targetCF
    ACTIVE_HOVER.Position.Position = targetCF.Position
    ACTIVE_HOVER.Gyro.CFrame = targetCF
    rr.AssemblyLinearVelocity = Vector3.zero
    rr.AssemblyAngularVelocity = Vector3.zero
    if (rr.Position - targetCF.Position).Magnitude > CONFIG.HOVER_SNAP_DISTANCE then
        rr.CFrame = targetCF
    end
    return true
end

local function magnetForestPirates(anchorCF, radius)
    setForestMagnet(true, anchorCF, radius)
    boostSimulationRadius()
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return 0 end

    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) and not isForestGhost(m) then
            local h, rr = forestHumRoot(m)
            if h and rr and (rr.Position - anchorCF.Position).Magnitude <= radius then
                ACTIVE_FOREST_MAGNET.Locked[m] = true
                hardLockForestMob(m, anchorCF)
            end
        end
    end

    local count = 0
    for m in pairs(ACTIVE_FOREST_MAGNET.Locked) do
        local h, rr = forestHumRoot(m)
        if h and rr and not isForestGhost(m) then
            count = count + 1
            hardLockForestMob(m, anchorCF)
        else
            ACTIVE_FOREST_MAGNET.Locked[m] = nil
        end
    end
    return count
end

local function farmScrap(token)
    local camp = CONFIG.MOB_CAMPS.ForestPirate
    local scanRadius = CONFIG.FOREST_SCAN_RADIUS
    local magnetRadius = CONFIG.FOREST_MAGNET_RADIUS
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
        if not waitAlive(token) then break end
        local scrap = inventoryCount("Scrap Metal")
        setStatus("Scrap Metal "..scrap.."/10 | route -> Floating Turtle")

        -- Delta parse-safe iteration guard: use repeat/break instead of Luau `continue`.
        repeat
        if not goTurtle(token) then
            setStatus("Turtle portal failed - retrying portal only")
            task.wait(1)
            break
        end

        -- Hard guard: never start Forest Pirate farming unless the portal destination
        -- was actually confirmed as Floating Turtle.
        if getRegion() ~= "TURTLE" then
            setStatus("Not on Floating Turtle -> abort Scrap farm cycle")
            task.wait(.8)
            break
        end

        -- Move only to the user-captured safe point beside the Forest Pirate area.
        highTween(camp * CFrame.new(0,18,0), CONFIG.PLAYER_TWEEN_SPEED, token)
        if not isRunning(token) then break end
        if getRegion() ~= "TURTLE" then
            setStatus("Left Turtle unexpectedly -> stop local farm")
            task.wait(.8)
            break
        end

        local noMobPasses = 0
        while isRunning(token)
            and getRegion() == "TURTLE"
            and inventoryCount("Scrap Metal") < 10 do

            -- Scan around the CURRENT player first. Older builds scanned around the static
            -- camp coordinate only, so mobs could literally be hitting us while the UI
            -- still said "scanning Forest Pirates". Fall back to a wider camp scan.
            local rpNow = root()
            local scanCenter = rpNow and rpNow.Position or camp.Position
            local mobs = aliveForestPirates(scanCenter, scanRadius)
            if #mobs == 0 then
                mobs = aliveForestPirates(camp.Position, scanRadius * 1.75)
            end

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

                -- Pull the local wave into one point, enlarge hitboxes, fly above it,
                -- force-equip Melee, then spam Tool:Activate() M1.
                local firstRoot = mobs[1] and mobs[1]:FindFirstChild("HumanoidRootPart")
                local anchorPos = firstRoot and firstRoot.Position or (root() and root().Position) or camp.Position
                local anchor = CFrame.new(anchorPos)
                local farmCF = anchor * CFrame.new(0, CONFIG.FOREST_FARM_HEIGHT, 0)
                local _,_,_,waveEpoch = waitAlive(token)
                if not waveEpoch then break end

                if not safeTween(farmCF, 300, token) then
                    -- Death/respawn or movement interruption: exit local loop so outer
                    -- route logic can re-confirm Turtle before farming again.
                    break
                end

                startStableHover(farmCF)
                setForestMagnet(true, anchor, magnetRadius)
                task.wait(.12)

                local tool = equipTooltip("Melee")
                local ac = buffMeleeHitbox()
                logLine("FOREST_WAVE", "mobs="..#mobs.." tool="..tostring(tool and tool.Name or "nil").." controller="..tostring(ac ~= nil).." hitbox="..tostring(ac and ac.hitboxMagnitude or "nil").." bodyHitbox="..tostring(CONFIG.FOREST_HITBOX_SIZE))
                local waveDeadline = os.clock() + 22
                while isRunning(token)
                    and getRegion() == "TURTLE"
                    and inventoryCount("Scrap Metal") < 10
                    and os.clock() < waveDeadline do

                    if CHARACTER_EPOCH ~= waveEpoch or not hum() or hum().Health <= 0 then
                        setStatus("Died during Scrap farm -> waiting respawn, then rerouting")
                        waitAlive(token)
                        break
                    end

                    local alive = magnetForestPirates(anchor, magnetRadius)
                    if alive <= 0 then break end

                    -- BodyPosition/BodyGyro hold the local character at one exact hover point.
                    -- We no longer rewrite HRP.CFrame every attack tick, which caused the visible jitter.
                    maintainStableHover(farmCF)

                    tool = equipTooltip("Melee") or tool
                    buffMeleeHitbox()
                    if tool and tool.Parent == char() then
                        local attackModels = aliveForestPirates(anchor.Position, magnetRadius)
                        local okAttack, backend, hitCount = virtualToolClick(tool, attackModels)
                        for _,m in ipairs(attackModels) do
                            updateForestDamageTrack(m, okAttack)
                        end
                        if not okAttack then
                            logLine("ATTACK_FAIL", "backend="..tostring(backend).." hits="..tostring(hitCount).." models="..tostring(#attackModels))
                        elseif hitCount and hitCount > 0 and not AttackSuccessLogged then
                            AttackSuccessLogged = true
                            logLine("ATTACK_OK", "backend="..tostring(backend).." hits="..tostring(hitCount).." models="..tostring(#attackModels))
                        end
                    end
                    task.wait(CONFIG.MELEE_ATTACK_INTERVAL)
                end

                setForestMagnet(false)
                stopStableHover()
                task.wait(.35)
                local remaining = #aliveForestPirates(anchor.Position, magnetRadius)
                if remaining > 0 then
                    setStatus("Scrap Metal "..inventoryCount("Scrap Metal").."/10 | attack stalled, retrying "..remaining.." mobs")
                    logLine("ATTACK_STALLED", "remaining="..remaining.." tool="..tostring(tool and tool.Name or "nil"))
                else
                    setStatus("Scrap Metal "..inventoryCount("Scrap Metal").."/10 | Forest Pirate wave cleared")
                end
            end
        end
        until true
    end

    setForestMagnet(false)
    stopStableHover()
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
    local crafted = hasVolcanicMagnet()
    if crafted then
        -- Scrap/Ember were consumed by crafting; discard short-lived popup optimism
        -- so every counter immediately returns to authoritative post-craft values.
        clearOptimisticCount("Scrap Metal")
        clearOptimisticCount("Blaze Ember")
        clearOptimisticCount("Volcanic Magnet")
    end
    return crafted
end

local function recoverMagnet(token)
    if hasVolcanicMagnet() then return true end

    local masterOnline = Players:FindFirstChild(_G.TeamConfig.MasterName) ~= nil
    local scrap = inventoryCount("Scrap Metal")
    local ember = inventoryCount("Blaze Ember")
    setStatus("RECOVERY scan | MASTER="..(masterOnline and "ONLINE" or "OFFLINE").." | Magnet=NO | Scrap="..scrap.."/10 | Ember="..ember.."/15")
    logLine("PREFLIGHT", "recover magnet | masterOnline="..tostring(masterOnline).." region="..tostring(getRegion()).." scrap="..scrap.." ember="..ember)

    -- Do not bounce to Tiki first. Route directly to whichever material is missing.
    -- This avoids Tiki -> Castle -> Turtle/Hydra chains when the account is already useful elsewhere.
    if scrap < 10 then
        if not farmScrap(token) then return false end
    end
    if not isRunning(token) then return false end

    if inventoryCount("Blaze Ember") < 15 then
        if not farmBlazeEmbers(token) then return false end
    end
    if not isRunning(token) then return false end

    -- Crafting is at Dragon Hunter on Hydra, so go directly there. Tiki is only needed later
    -- if this client is the MASTER and actually needs to buy a new boat.
    for attempt=1,4 do
        if craftVolcanicMagnet(token) then
            setStatus("Volcanic Magnet crafted")
            logLine("MAGNET", "crafted successfully without forced Tiki pre-route")
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
    if not collectAssignedEgg(island, token) then return end
    if not isRunning(token) then return end

    -- Final hard gate before ANY reset/portal. Reward replication is sometimes late;
    -- if a Dragon fruit appears here it must be stored first. On failure the account
    -- stops in place and never resets/leaves.
    setStatus("Reward safety check -> Dragon guard before reset")
    if not secureDragonWindow(CONFIG.DRAGON_GUARD.PRE_RESET_GUARD_SECONDS, token) then return end
    if not isRunning(token) then return end

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
-- SMART PREFLIGHT
--==============================================================

local function scanTeamPreflight(token)
    pcall(ensureMarines)
    local masterPlayer = Players:FindFirstChild(_G.TeamConfig.MasterName)
    local boat = getMasterBoat()
    local island = findPrehistoric()
    local magnet = hasVolcanicMagnet()
    local state = {
        MasterPlayer = masterPlayer,
        MasterOnline = masterPlayer ~= nil,
        Boat = boat,
        Island = island,
        Magnet = magnet,
        Region = getRegion(),
    }
    logLine("PREFLIGHT", "master="..tostring(_G.TeamConfig.MasterName).." online="..tostring(state.MasterOnline).." magnet="..tostring(magnet).." boat="..tostring(boat ~= nil).." island="..tostring(island ~= nil).." region="..tostring(state.Region))
    return state
end

local function waitForMasterOnline(token)
    while isRunning(token) do
        local p = Players:FindFirstChild(_G.TeamConfig.MasterName)
        if p then return p end
        setStatus("MASTER "..tostring(_G.TeamConfig.MasterName).." offline -> waiting, no teleport")
        task.wait(1)
    end
end

--==============================================================
-- MASTER / SLAVE CYCLES
--==============================================================

local function masterCycle(token)
    local pre = scanTeamPreflight(token)
    if pre.Island then
        runPrehistoricEvent(pre.Island, token)
        return
    end

    -- Check the actual Magnet state before any Tiki teleport.
    if not pre.Magnet then
        if not recoverMagnet(token) then return end
        pre = scanTeamPreflight(token)
    end

    -- Re-use an existing owned boat. Only go to Tiki when MASTER really needs to buy one.
    local boat = pre.Boat or getMasterBoat()
    if not boat then
        setStatus("MASTER preflight OK | Magnet=YES | no boat -> Tiki")
        if not goTiki(token) then return end
        boat = buyGrandBrigade(token)
    else
        setStatus("MASTER preflight | existing boat found -> skip Tiki purchase route")
    end

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
    if not island and boat.Parent then island = searchSeaUntilIsland(boat, token) end
    if island then runPrehistoricEvent(island, token) end
end

local function slaveCycle(token)
    local pre = scanTeamPreflight(token)
    if pre.Island then
        runPrehistoricEvent(pre.Island, token)
        return
    end

    -- Do not teleport anywhere while the configured MASTER is offline.
    if not pre.MasterOnline then
        if not waitForMasterOnline(token) then return end
        pre = scanTeamPreflight(token)
    end

    -- Each slave verifies its own Magnet before deciding on travel.
    if not pre.Magnet then
        if not recoverMagnet(token) then return end
        pre = scanTeamPreflight(token)
    end

    -- If MASTER already owns a live boat, board it immediately from the current state.
    local boat = pre.Boat or getMasterBoat()
    if not boat then
        setStatus("SLAVE preflight OK | Magnet=YES | waiting MASTER boat, no Tiki teleport")
        while isRunning(token) do
            local island = findPrehistoric()
            if island then
                runPrehistoricEvent(island, token)
                return
            end
            if not Players:FindFirstChild(_G.TeamConfig.MasterName) then
                waitForMasterOnline(token)
            end
            boat = getMasterBoat()
            if boat then break end
            task.wait(.5)
        end
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
-- NIGHT SNAPSHOT + WATCHDOG
--==============================================================

local function debugInventoryOnce()
    return {
        Scrap = inventoryCount("Scrap Metal"),
        Ember = inventoryCount("Blaze Ember"),
        Magnet = inventoryCount("Volcanic Magnet"),
        Bones = inventoryCount("Dinosaur Bones"),
    }
end

local function equippedToolName()
    local c = char()
    if not c then return "nil" end
    local t = c:FindFirstChildOfClass("Tool")
    return t and t.Name or "nil"
end

local function eventUiText(name)
    local main = PG:FindFirstChild("Main")
    local list = main and main:FindFirstChild("TopHUDList")
    local o = list and list:FindFirstChild(name)
    if o and pcall(function() return o.Text end) then
        return tostring(o.Text)
    end
    return ""
end

local function debugRuntimeSnapshot()
    local r = root()
    local h = hum()
    local region,regionD = getRegion()
    local inv = debugInventoryOnce()
    local island = findPrehistoric()
    local active = island and island:GetAttribute("IsMinigameActive") == true or false
    local relicHp,relicMax = -1,-1
    if island then
        local relic = getRelic(island)
        local hv = relic and relic:FindFirstChild("Health")
        local mv = relic and relic:FindFirstChild("MaxHealth")
        relicHp = hv and hv.Value or -1
        relicMax = mv and mv.Value or -1
    end

    local enemies = workspace:FindFirstChild("Enemies")
    local forestCount,forestHp = 0,0
    local golemHp = -1
    if enemies then
        for _,m in ipairs(enemies:GetChildren()) do
            local mh = m:FindFirstChildOfClass("Humanoid")
            if mh and mh.Health > 0 then
                if string.find(string.lower(m.Name), "forest pirate", 1, true) then
                    forestCount = forestCount + 1
                    forestHp = forestHp + math.floor(mh.Health)
                elseif string.find(string.lower(m.Name), "lava golem", 1, true) then
                    golemHp = math.floor(mh.Health)
                end
            end
        end
    end

    local state = resolveCombatState()
    local ac = state and state.activeController
    local hb = ac and ac.hitboxMagnitude or "nil"
    local boat = getMasterBoat()
    local aboard = boat and countTeamAboard(boat) or 0

    local line = table.concat({
        "status="..tostring(NIGHT.LastStatus),
        "region="..tostring(region).."("..string.format("%.0f", tonumber(regionD) or -1)..")",
        "pos="..tostring(r and r.Position or "nil"),
        "hp="..tostring(h and math.floor(h.Health) or -1),
        "tool="..equippedToolName(),
        "hitbox="..tostring(hb),
        "scrap="..inv.Scrap,
        "ember="..inv.Ember,
        "magnet="..inv.Magnet,
        "bones="..tostring(inv.Bones or 0),
        "dragonLoose="..tostring(#findPhysicalDragonFruits()),
        "dragonStored="..tostring(DRAGON_GUARD_STATE.LastStored or "none"),
        "island="..tostring(island ~= nil),
        "event="..tostring(active),
        "relic="..tostring(relicHp).."/"..tostring(relicMax),
        "pressure="..eventUiText("PrehistoricRaidTimer"),
        "forest="..forestCount..":"..forestHp,
        "golemHp="..golemHp,
        "boat="..tostring(boat ~= nil)..":"..aboard,
    }, " | ")

    -- Signature deliberately excludes exact player position so tiny movement cannot hide a stall.
    local sig = table.concat({
        tostring(NIGHT.LastStatus), tostring(region), tostring(inv.Scrap), tostring(inv.Ember), tostring(inv.Magnet),
        tostring(active), tostring(relicHp), eventUiText("PrehistoricRaidTimer"), tostring(forestCount),
        tostring(math.floor(forestHp/100)), tostring(math.floor(math.max(golemHp,0)/100)), tostring(aboard), tostring(hb)
    }, ":")
    return sig,line,active
end

local function restartNightStateMachine(reason)
    if not _G.TeamConfig.IsRunning then return end
    RUN_TOKEN = RUN_TOKEN + 1
    local token = RUN_TOKEN
    NIGHT.RecoveryCount = NIGHT.RecoveryCount + 1
    NIGHT.LastProgressAt = os.clock()
    NIGHT.LastProgressSignature = "WATCHDOG_RESTART:"..NIGHT.RecoveryCount
    logLine("WATCHDOG_RECOVER", "count="..NIGHT.RecoveryCount.." reason="..tostring(reason).." | re-entering mainLoop without killing character")
    task.spawn(function()
        mainLoop(token)
    end)
end

task.spawn(function()
    local nextSnapshot = 0
    while true do
        task.wait(5)
        if CONFIG.DEBUG.ENABLED and _G.TeamConfig.IsRunning then
            local sig,line,eventActive = debugRuntimeSnapshot()
            if sig ~= NIGHT.RuntimeSignature then
                NIGHT.RuntimeSignature = sig
                noteProgress("RUNTIME:"..sig)
            end

            if os.clock() >= nextSnapshot then
                nextSnapshot = os.clock() + (CONFIG.DEBUG.SNAPSHOT_INTERVAL or 15)
                logLine("SNAP", line)
                flushNightLog()
            end

            local stalled = os.clock() - NIGHT.LastProgressAt
            if stalled >= (CONFIG.DEBUG.WATCHDOG_SECONDS or 120) then
                logLine("WATCHDOG", string.format("STALL %.0fs | %s", stalled, line))
                if CONFIG.DEBUG.WEBHOOK_ERRORS then
                    sendWebhook("⚠️ PREHISTORIC WATCHDOG", "Automation appears stalled on "..LP.Name, {
                        {name="State", value=tostring(NIGHT.LastStatus), inline=false},
                        {name="Stalled", value=string.format("%.0fs", stalled), inline=true},
                        {name="Region", value=tostring(getRegion()), inline=true},
                    })
                end

                -- During an active Volcano event, do not reset/restart state automatically;
                -- preserving relic/event participation is safer. Log it for morning analysis.
                if eventActive then
                    NIGHT.LastProgressAt = os.clock()
                    logLine("WATCHDOG", "Active Volcano event -> logging only, no forced restart")
                elseif CONFIG.DEBUG.WATCHDOG_RESTART then
                    restartNightStateMachine("no meaningful progress for "..math.floor(stalled).."s")
                else
                    NIGHT.LastProgressAt = os.clock()
                end
            end
        else
            nextSnapshot = 0
        end
    end
end)

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
F.Size = UDim2.fromOffset(385, 360)
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
TITLE.Text = "🌋 PREHISTORIC TEAM V2.5.1 PARSE SAFE | DELTA"

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

COUNTER_LABEL = Instance.new("TextLabel")
COUNTER_LABEL.Parent = F
COUNTER_LABEL.Size = UDim2.new(1,-20,0,30)
COUNTER_LABEL.Position = UDim2.fromOffset(10,148)
COUNTER_LABEL.BackgroundTransparency = 1
COUNTER_LABEL.TextColor3 = Color3.fromRGB(120,235,170)
COUNTER_LABEL.Font = Enum.Font.SourceSansBold
COUNTER_LABEL.TextSize = 13
COUNTER_LABEL.TextWrapped = true
COUNTER_LABEL.Text = "Scrap ?/10 | Ember ?/15 | Magnet ? | Bones ? | Dragon safe"

STATUS_LABEL = Instance.new("TextLabel")
STATUS_LABEL.Parent = F
STATUS_LABEL.Size = UDim2.new(1,-20,0,78)
STATUS_LABEL.Position = UDim2.fromOffset(10,180)
STATUS_LABEL.BackgroundColor3 = Color3.fromRGB(14,14,19)
STATUS_LABEL.TextColor3 = Color3.fromRGB(255,210,80)
STATUS_LABEL.Font = Enum.Font.SourceSansSemibold
STATUS_LABEL.TextWrapped = true
STATUS_LABEL.Text = "READY"

local START = Instance.new("TextButton")
START.Parent = F
START.Size = UDim2.new(1,-20,0,42)
START.Position = UDim2.fromOffset(10,268)
START.BackgroundColor3 = Color3.fromRGB(45,150,70)
START.TextColor3 = Color3.new(1,1,1)
START.Font = Enum.Font.SourceSansBold
START.TextSize = 16
START.Text = "▶ START FULL AUTO"

local NOTE = Instance.new("TextLabel")
NOTE.Parent = F
NOTE.Size = UDim2.new(1,-20,0,38)
NOTE.Position = UDim2.fromOffset(10,316)
NOTE.BackgroundTransparency = 1
NOTE.TextColor3 = Color3.fromRGB(180,180,190)
NOTE.TextSize = 12
NOTE.Text = "Night log: "..NIGHT.LogPath.." | file="..tostring(NIGHT.FileReady or type(appendfile)=="function").." | SaveCPU="..tostring(CONFIG.SAVE_CPU.ENABLED)

local function refreshRole()
    _G.TeamConfig.IsMaster = LP.Name == _G.TeamConfig.MasterName
    ROLE.Text = "LOCAL: "..LP.Name.."\nROLE: "..roleText().." | MASTER: ".._G.TeamConfig.MasterName
end

local function refreshCounters()
    if not COUNTER_LABEL or not COUNTER_LABEL.Parent then return end
    local scrap = inventoryCount("Scrap Metal")
    local ember = inventoryCount("Blaze Ember")
    local magnet = inventoryCount("Volcanic Magnet")
    local bones = inventoryCount("Dinosaur Bones")
    local dragonLoose = #findPhysicalDragonFruits()
    local dragonText
    if DRAGON_GUARD_STATE.Critical then
        dragonText = "DRAGON CRITICAL"
    elseif dragonLoose > 0 then
        dragonText = "DRAGON LOOSE:"..dragonLoose
    elseif DRAGON_GUARD_STATE.LastStored then
        dragonText = "Dragon STORED"
    else
        dragonText = "Dragon safe"
    end
    COUNTER_LABEL.Text = string.format("Scrap %d/10 | Ember %d/15 | Magnet %s | Bones %d | %s", scrap, ember, magnet > 0 and "YES" or "NO", bones, dragonText)
end

APPLY.MouseButton1Click:Connect(function()
    pcall(ensureMarines)
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
        setForestMagnet(false)
        stopStableHover()
        logLine("RUN", "STOP pressed")
        flushNightLog()
        setStatus("STOPPED")
        return
    end

    -- Marine team is established before role/master selection is committed.
    ensureMarines()
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
    logLine("RUN", "START | role="..roleText().." master="..tostring(_G.TeamConfig.MasterName))
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
logLine("UI", "READY | log="..NIGHT.LogPath)
flushNightLog()

-- Live counter panel: one cached inventory fetch feeds every displayed material,
-- while pickup popups provide an immediate optimistic increment until the server catches up.
task.spawn(function()
    while SG.Parent do
        pcall(refreshCounters)
        task.wait(.5)
    end
end)

-- Keep Marine team alive even before START so the initial team picker cannot leave
-- one of the five clients on Pirates while the user is configuring MASTER.
task.spawn(function()
    while SG.Parent do
        pcall(ensureMarines)
        task.wait(10)
    end
end)
