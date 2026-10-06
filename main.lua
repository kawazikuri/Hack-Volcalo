--[[
    PREHISTORIC TEAM V2.9.3 (NPC HUNT + FIXED TREES + ITEM CHECK)
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
local PHX = {} -- helper namespace; keeps Delta/Luau main-chunk local count below compiler limit

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
BOOT_LABEL.Text = "PREHISTORIC V2.9.3 NPC HUNT + FIXED TREES\nLoading automation..."
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

BOOT_LABEL.Text = "PREHISTORIC V2.9.3 NPC HUNT + FIXED TREES\nLoaded core, building UI..."

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
        STORE_RETRIES = 8,
        RETRY_DELAY = 0.35,
        POST_EGG_GUARD_SECONDS = 10.0,
        PRE_RESET_GUARD_SECONDS = 10.0,
    },

    -- V2.8: the full-video event logic is feedback driven. Master always fixes
    -- active pressure rocks; slaves delete Lava Golems first, then help pressure.
    PRESSURE = {
        SKILL_HOLD = 0.02,
        SKILL_GAP = 0.08,
        ROCK_HOVER_Y = 10,
        ASSIST_AT = 8,          -- when no golem, slaves help almost immediately
        EMERGENCY_AT = 42,
        RELIC_ASSIST_AT = 98,
        RELIC_EMERGENCY_AT = 92,
        MAX_BURST_SECONDS = 2.2,
    },

    GOLEM_AURA = {
        APPROACH_DISTANCE = 48,
        HOVER_Y = 14,
        ATTACK_INTERVAL = 0.035,
        BURST_SECONDS = 1.5,
        HITBOX_SIZE = 85,
    },

    EGG = {
        HOLD_E_SECONDS = 1.10,  -- PC prompt in the supplied full-run video
        RETRIES = 3,
        RETRY_GAP = 0.28,
        SPAWN_WAIT_SECONDS = 10,
        APPROACH_DISTANCE = 4.0,
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
_G.TeamConfig.StopReason = nil

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
        footer = {text = "Prehistoric Team V2.9.3 | " .. LP.Name},
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
-- V2.7: one serialized inventory poller + exact Material schema + GUI fallback.
-- Do NOT treat an absent/unreadable server entry as authoritative zero.
--==============================================================

function PHX.normalizeItemName(v)
    local x = string.lower(tostring(v or ""))
    x = x:gsub("[%[%]{}<>]", "")
    x = x:gsub("%s+", " ")
    return x:match("^%s*(.-)%s*$") or x
end

PHX.InventoryBusy = false
PHX.InventoryLastError = nil
PHX.InventorySchemaLogged = false
_G.__PH_MATERIAL_CACHE = _G.__PH_MATERIAL_CACHE or {}
_G.__PH_MATERIAL_CACHE[LP.Name] = _G.__PH_MATERIAL_CACHE[LP.Name] or {}
PHX.MaterialPersistent = _G.__PH_MATERIAL_CACHE[LP.Name]

function PHX.persistMaterial(itemName, count, source)
    local key = PHX.normalizeItemName(itemName)
    count = tonumber(count)
    if not count then return end
    PHX.MaterialPersistent[key] = {
        Count = math.max(0, count),
        Source = tostring(source or "MEMORY"),
        At = os.clock(),
    }
end

function PHX.consumeKnownMaterial(itemName, amount)
    local key = PHX.normalizeItemName(itemName)
    local t = ITEM_TRACK[key]
    amount = math.max(0, tonumber(amount) or 0)
    if t and t.Known then
        local n = math.max(0, (tonumber(t.Optimistic) or tonumber(t.Server) or 0) - amount)
        t.Server = n
        t.Optimistic = n
        t.OptimisticUntil = 0
        t.Source = "CRAFT_LOCAL"
        PHX.persistMaterial(itemName, n, "CRAFT_LOCAL")
        return n
    end
    return nil
end

local function getInventory(force)
    local now = os.clock()
    if not force and INVENTORY_CACHE.Raw and (now - INVENTORY_CACHE.At) < CONFIG.ITEM_COUNTER.CACHE_SECONDS then
        return INVENTORY_CACHE.Raw
    end

    local deadline = now + 2.5
    while PHX.InventoryBusy and os.clock() < deadline do task.wait(.03) end
    if PHX.InventoryBusy then
        return INVENTORY_CACHE.Raw or {}
    end

    PHX.InventoryBusy = true
    local ok, inv = pcall(function()
        return CommF:InvokeServer("getInventory")
    end)
    PHX.InventoryBusy = false

    PHX.LastInventoryReadOK = ok and type(inv) == "table"
    if PHX.LastInventoryReadOK then
        INVENTORY_CACHE.Raw = inv
        INVENTORY_CACHE.At = os.clock()
        PHX.InventoryLastError = nil
        if not PHX.InventorySchemaLogged then
            PHX.InventorySchemaLogged = true
            local n = 0
            for _ in pairs(inv) do n = n + 1 end
            logLine("INVENTORY", "getInventory OK | entries="..tostring(n))
        end
        return inv
    end

    PHX.InventoryLastError = tostring(inv)
    logLine("INVENTORY_FAIL", "getInventory failed | "..tostring(inv))
    return INVENTORY_CACHE.Raw or {}
end

function PHX.entryCount(v)
    if type(v) == "number" then return math.max(0, v) end
    if type(v) ~= "table" then return nil end
    local preferred = {
        "Count","count","Amount","amount","Quantity","quantity","Qty","qty",
        "Owned","owned","Number","number","Num","num","Stack","stack","Value","value"
    }
    for _,key in ipairs(preferred) do
        local n = tonumber(v[key])
        if n then return math.max(0, n) end
    end
    return nil
end

function PHX.exactMaterialCount(inv, itemName)
    if type(inv) ~= "table" then return nil end
    local wanted = PHX.normalizeItemName(itemName)
    for _,entry in pairs(inv) do
        if type(entry) == "table" then
            local nm = PHX.normalizeItemName(entry.Name or entry.name or entry.ItemName or entry.itemName or "")
            local tp = PHX.normalizeItemName(entry.Type or entry.type or "")
            if nm == wanted and (tp == "" or tp == "material") then
                local n = PHX.entryCount(entry)
                if n ~= nil then return n end
            end
        end
    end
    return nil
end

function PHX.smartTableCount(root, itemName)
    local wanted = PHX.normalizeItemName(itemName)
    local best = nil
    local seen = {}
    local function scan(tbl, depth)
        if type(tbl) ~= "table" or seen[tbl] or depth > 8 then return end
        seen[tbl] = true
        local matched = false
        for k,v in pairs(tbl) do
            if type(k) == "string" and PHX.normalizeItemName(k) == wanted then
                local n = PHX.entryCount(v)
                if n ~= nil then best = math.max(best or 0, n) end
            end
            if type(v) == "string" then
                local key = type(k) == "string" and string.lower(k) or ""
                if key == "name" or key == "itemname" or key == "displayname" or key == "material" then
                    if PHX.normalizeItemName(v) == wanted then matched = true end
                end
            end
        end
        if matched then
            local n = PHX.entryCount(tbl)
            if n ~= nil then best = math.max(best or 0, n) end
        end
        for _,v in pairs(tbl) do
            if type(v) == "table" then scan(v, depth + 1) end
        end
    end
    scan(root, 0)
    return best
end

-- Fallback for the new Stash UI. If the card is instantiated client-side, read the
-- count text nearest the exact material name. This is only used when getInventory
-- does not expose the Material entry; it never overrides a valid server count.
function PHX.guiMaterialCount(itemName)
    local wanted = PHX.normalizeItemName(itemName)
    local best, bestDist = nil, math.huge
    for _,obj in ipairs(PG:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and PHX.normalizeItemName(obj.Text) == wanted then
            local okPos, center = pcall(function()
                return obj.AbsolutePosition + obj.AbsoluteSize/2
            end)
            local ancestor = obj.Parent
            local hops = 0
            while ancestor and ancestor ~= PG and hops < 7 do
                if ancestor:IsA("GuiObject") then
                    for _,x in ipairs(ancestor:GetDescendants()) do
                        if x ~= obj and (x:IsA("TextLabel") or x:IsA("TextButton")) then
                            local raw = tostring(x.Text or ""):gsub(",",""):match("^%s*(%d+)%s*$")
                            local n = tonumber(raw)
                            if n and n >= 0 and n <= 999 then
                                local dist = 999999
                                if okPos then
                                    local ok2, p2 = pcall(function() return x.AbsolutePosition + x.AbsoluteSize/2 end)
                                    if ok2 then dist = (p2-center).Magnitude end
                                end
                                if dist < bestDist then best, bestDist = n, dist end
                            end
                        end
                    end
                end
                ancestor = ancestor.Parent
                hops = hops + 1
            end
        end
    end
    if best ~= nil and bestDist <= 520 then return best end
    return nil
end

function PHX.inventoryHasMaterialSchema(inv)
    if type(inv) ~= "table" then return false end
    for _,entry in pairs(inv) do
        if type(entry) == "table" then
            local tp = PHX.normalizeItemName(entry.Type or entry.type or "")
            if tp == "material" then return true end
        end
    end
    return false
end

function PHX.serverInventoryCount(itemName, force)
    local inv = getInventory(force)
    local exact = PHX.exactMaterialCount(inv, itemName)
    if exact ~= nil then return exact, "REMOTE_EXACT" end
    local deep = PHX.smartTableCount(inv, itemName)
    if deep ~= nil then return deep, "REMOTE_DEEP" end
    local gui = PHX.guiMaterialCount(itemName)
    if gui ~= nil then return gui, "STASH_GUI" end

    -- Only call a missing entry ZERO when the returned table demonstrably contains
    -- Material records. If the current game build returns weapons/other inventory only,
    -- "not found" is UNKNOWN, not zero. This was the V2.6.1 2/10-vs-27 bug.
    if PHX.LastInventoryReadOK and PHX.inventoryHasMaterialSchema(inv) then
        return 0, "REMOTE_ABSENT"
    end
    return nil, "UNAVAILABLE"
end


-- V2.9.3 runtime inventory probe. When material schema is unknown we dump the
-- exact getInventory table shape once. This is diagnostic only and does not
-- influence routing/counters.
function PHX.valuePreview(v)
    local tv = type(v)
    if tv == "string" then return string.format("%q", v) end
    if tv == "number" or tv == "boolean" or tv == "nil" then return tostring(v) end
    return "<"..tv..">"
end

function PHX.dumpInventoryProbe(reason)
    if not writefile then return nil end
    local inv = getInventory(true)
    local lines = {
        "===== PREHISTORIC INVENTORY PROBE V2.9.3 =====",
        "ACCOUNT="..LP.Name,
        "REASON="..tostring(reason or "manual"),
        "LastInventoryReadOK="..tostring(PHX.LastInventoryReadOK),
        "LastError="..tostring(PHX.InventoryLastError),
        "",
    }
    local seen, nodes = {}, 0
    local function walk(v, path, depth)
        if nodes > 1800 or depth > 7 then return end
        if type(v) ~= "table" then
            lines[#lines+1] = path.." = "..PHX.valuePreview(v)
            nodes = nodes + 1
            return
        end
        if seen[v] then return end
        seen[v] = true
        for k,x in pairs(v) do
            if nodes > 1800 then break end
            local kp = path.."["..PHX.valuePreview(k).."]"
            if type(x) == "table" then
                lines[#lines+1] = kp.." = <table>"
                nodes = nodes + 1
                walk(x, kp, depth + 1)
            else
                lines[#lines+1] = kp.." = "..PHX.valuePreview(x)
                nodes = nodes + 1
            end
        end
    end
    walk(inv, "inventory", 0)

    lines[#lines+1] = ""
    lines[#lines+1] = "===== PLAYER DATA CANDIDATES ====="
    local dataRoots = {LP:FindFirstChild("Data"), LP:FindFirstChild("Backpack")}
    for _,root in ipairs(dataRoots) do
        if root then
            for _,o in ipairs(root:GetDescendants()) do
                local n = string.lower(o.Name or "")
                if n:find("scrap",1,true) or n:find("ember",1,true) or n:find("magnet",1,true) or n:find("bone",1,true) then
                    local val = ""
                    pcall(function() val = " value="..tostring(o.Value) end)
                    lines[#lines+1] = o:GetFullName().." | "..o.ClassName..val
                end
            end
        end
    end

    lines[#lines+1] = ""
    lines[#lines+1] = "===== VISIBLE GUI ITEM TEXT ====="
    for _,o in ipairs(PG:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and visibleGui(o) then
            local txt = tostring(o.Text or "")
            local l = string.lower(txt)
            if l:find("scrap",1,true) or l:find("ember",1,true) or l:find("magnet",1,true) or l:find("bone",1,true)
                or txt:match("^%s*%d+%s*$") then
                lines[#lines+1] = o:GetFullName().." | text="..string.format("%q",txt)
            end
        end
    end

    local path = "PH_InventoryProbe_"..LP.Name.."_V293.txt"
    pcall(function() writefile(path, table.concat(lines, "\n")) end)
    logLine("INV_PROBE", "wrote "..path.." | nodes="..tostring(nodes))
    return path
end

PHX.InventoryProbeWritten = false
function PHX.ensureInventoryProbeIfUnknown()
    if PHX.InventoryProbeWritten then return end
    local _,ss,sk = PHX.materialCountInfo("Scrap Metal", true)
    local _,es,ek = PHX.materialCountInfo("Blaze Ember", true)
    if not sk or not ek or ss == "UNAVAILABLE" or es == "UNAVAILABLE" then
        PHX.InventoryProbeWritten = true
        task.spawn(function() PHX.dumpInventoryProbe("material_count_unknown") end)
    end
end

function PHX.trackerFor(itemName)
    local key = PHX.normalizeItemName(itemName)
    local t = ITEM_TRACK[key]
    if not t then
        local server, source = PHX.serverInventoryCount(itemName, true)
        local known = server ~= nil
        if not known then
            local mem = PHX.MaterialPersistent[key]
            if type(mem) == "table" and tonumber(mem.Count) then
                server = math.max(0, tonumber(mem.Count))
                source = "MEMORY"
                known = true
            end
        end
        server = server or 0
        t = {
            Server=server,
            Optimistic=server,
            OptimisticUntil=0,
            Source=source or "UNAVAILABLE",
            Known=known,
            ObservedGain=0,
        }
        ITEM_TRACK[key] = t
        if known then PHX.persistMaterial(itemName, server, source) end
    end
    return t, key
end

local function inventoryCount(itemName, force)
    local t = PHX.trackerFor(itemName)
    local server, source = PHX.serverInventoryCount(itemName, force)

    if server ~= nil then
        t.Server = server
        t.Source = source
        t.Known = true
        if server >= (t.Optimistic or 0) or os.clock() > (t.OptimisticUntil or 0) then
            t.Optimistic = server
            t.OptimisticUntil = 0
        end
        PHX.persistMaterial(itemName, math.max(t.Server or 0, t.Optimistic or 0), source)
    end

    return math.max(t.Server or 0, t.Optimistic or 0)
end

function PHX.materialCountInfo(itemName, force)
    local count = inventoryCount(itemName, force)
    local t = PHX.trackerFor(itemName)
    return count, tostring(t.Source or "UNAVAILABLE"), t.Known == true
end

function PHX.setKnownMaterial(itemName, count, source)
    count = tonumber(count)
    if not count then return false end
    local t = PHX.trackerFor(itemName)
    count = math.max(0, count)
    t.Server = count
    t.Optimistic = count
    t.OptimisticUntil = 0
    t.Source = source or "GUI"
    t.Known = true
    PHX.persistMaterial(itemName, count, t.Source)
    logLine("ITEM_SYNC", tostring(itemName).."="..tostring(count).." | source="..tostring(t.Source))
    return true
end

function PHX.guiVisible(obj)
    local p = obj
    while p and p ~= PG do
        if p:IsA("GuiObject") and not p.Visible then return false end
        p = p.Parent
    end
    return true
end

function PHX.guiRequirementCount(itemName, required)
    local wanted = PHX.normalizeItemName(itemName)
    local best, bestDist = nil, math.huge
    for _,obj in ipairs(PG:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and PHX.guiVisible(obj)
            and PHX.normalizeItemName(obj.Text) == wanted then
            local center = nil
            pcall(function() center = obj.AbsolutePosition + obj.AbsoluteSize/2 end)
            local a = obj.Parent
            local hops = 0
            while a and a ~= PG and hops < 8 do
                if a:IsA("GuiObject") then
                    for _,x in ipairs(a:GetDescendants()) do
                        if (x:IsA("TextLabel") or x:IsA("TextButton")) and PHX.guiVisible(x) then
                            local txt = tostring(x.Text or ""):gsub(",","")
                            local have, need = txt:match("(%d+)%s*/%s*(%d+)")
                            have, need = tonumber(have), tonumber(need)
                            if have and need and (not required or need == required) then
                                return have
                            end
                            local n = tonumber(txt:match("^%s*(%d+)%s*$"))
                            if n and n <= 9999 and center then
                                local p = nil
                                pcall(function() p = x.AbsolutePosition + x.AbsoluteSize/2 end)
                                if p then
                                    local d = (p-center).Magnitude
                                    if d < bestDist then best, bestDist = n, d end
                                end
                            end
                        end
                    end
                end
                a = a.Parent
                hops = hops + 1
            end
        end
    end
    if best ~= nil and bestDist < 420 then return best end
    return nil
end

function PHX.syncCraftMaterialCounts()
    local scrap = PHX.guiRequirementCount("Scrap Metal", 10)
    local ember = PHX.guiRequirementCount("Blaze Ember", 15)
    if scrap ~= nil then PHX.setKnownMaterial("Scrap Metal", scrap, "CRAFT_GUI") end
    if ember ~= nil then PHX.setKnownMaterial("Blaze Ember", ember, "CRAFT_GUI") end
    return scrap, ember
end

function PHX.warmMaterialInventory(seconds)
    local deadline = os.clock() + (seconds or 3.0)
    local names = {"Scrap Metal","Blaze Ember","Volcanic Magnet","Dinosaur Bones"}
    repeat
        local known = 0
        for _,name in ipairs(names) do
            local _,source = PHX.materialCountInfo(name, true)
            if source ~= "UNAVAILABLE" and source ~= "INIT" then known = known + 1 end
        end
        if known >= 3 then return true end
        task.wait(.18)
    until os.clock() >= deadline
    return false
end

function PHX.clearOptimisticCount(itemName)
    local t = PHX.trackerFor(itemName)
    local server, source = PHX.serverInventoryCount(itemName, true)
    if server ~= nil then
        t.Server = server
        t.Optimistic = server
        t.OptimisticUntil = 0
        t.Source = source
        t.Known = true
        PHX.persistMaterial(itemName, server, source)
    end
    return math.max(t.Server or 0, t.Optimistic or 0)
end

function PHX.recordItemGain(itemName, amount, sourceText)
    amount = math.max(1, tonumber(amount) or 1)
    local t = PHX.trackerFor(itemName)
    local before = math.max(t.Server or 0, t.Optimistic or 0)
    local server, source = PHX.serverInventoryCount(itemName, true)
    if server ~= nil and server > before then
        t.Server = server
        t.Optimistic = server
        t.OptimisticUntil = 0
        t.Source = source
        t.Known = true
        PHX.persistMaterial(itemName, server, source)
    else
        t.ObservedGain = (tonumber(t.ObservedGain) or 0) + amount
        t.Optimistic = before + amount
        t.OptimisticUntil = os.clock() + CONFIG.ITEM_COUNTER.OPTIMISTIC_GAIN_SECONDS
        if server ~= nil then
            t.Server = server
            t.Source = source
            t.Known = true
            PHX.persistMaterial(itemName, math.max(t.Server or 0,t.Optimistic or 0), source)
        end
    end
    logLine("ITEM_GAIN", tostring(itemName).." +"..amount.." | live="..tostring(math.max(t.Server or 0,t.Optimistic or 0)).." | known="..tostring(t.Known).." | source="..tostring(sourceText))
end

local TRACKED_PICKUPS = {
    ["scrap metal"] = "Scrap Metal",
    ["blaze ember"] = "Blaze Ember",
    ["volcanic magnet"] = "Volcanic Magnet",
    ["dinosaur bones"] = "Dinosaur Bones",
    ["dinosaur bone"] = "Dinosaur Bones",
}

function PHX.parsePickupText(text)
    local raw = tostring(text or "")
    local low = string.lower(raw)
    local amount = tonumber(raw:match("%((%d+)%s*[xX]%)") or raw:match("(%d+)%s*[xX]")) or 1
    local looksLikeGain = low:find("obtained",1,true) or low:find("received",1,true)
        or low:find("acquired",1,true) or low:find("crafted",1,true)
        or low:find("you got",1,true) or raw:match("%(%d+%s*[xX]%)")
    if not looksLikeGain then return end
    for needle,itemName in pairs(TRACKED_PICKUPS) do
        if low:find(needle,1,true) then
            PHX.recordItemGain(itemName, amount, raw)
            return
        end
    end
end

function PHX.watchPickupTextObject(obj)
    if PICKUP_WATCHED[obj] then return end
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    PICKUP_WATCHED[obj] = tostring(obj.Text or "")
    local function inspect()
        local text = tostring(obj.Text or "")
        if text ~= PICKUP_WATCHED[obj] then
            PICKUP_WATCHED[obj] = text
            PHX.parsePickupText(text)
        end
    end
    obj:GetPropertyChangedSignal("Text"):Connect(inspect)
    PHX.parsePickupText(obj.Text)
end

for _,obj in ipairs(PG:GetDescendants()) do pcall(PHX.watchPickupTextObject, obj) end
PG.DescendantAdded:Connect(function(obj) pcall(PHX.watchPickupTextObject, obj) end)

-- One inventory RemoteFunction poller instead of several independent loops racing it.
task.spawn(function()
    while true do
        task.wait(1.35)
        pcall(function()
            getInventory(true)
            for _,name in ipairs({"Scrap Metal","Blaze Ember","Volcanic Magnet","Dinosaur Bones"}) do
                inventoryCount(name, false)
            end
        end)
    end
end)

local function hasVolcanicMagnet()
    return inventoryCount("Volcanic Magnet", true) > 0
end

--==============================================================
-- SAVE CPU / LOW GRAPHICS (SAFE: visual-only, no gameplay objects destroyed)
--==============================================================

function PHX.isPressureSensorVFX(obj)
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

function PHX.isDynamicGameplayPart(obj)
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

function PHX.optimizeVisualObject(obj)
    if not SAVE_CPU_APPLIED or not obj or not obj.Parent then return end

    if obj:IsA("BasePart") then
        pcall(function() obj.CastShadow = false end)
        pcall(function() obj.Reflectance = 0 end)
        if CONFIG.SAVE_CPU.HIDE_STATIC_MAP_VISUALS then
            local map = workspace:FindFirstChild("Map")
            if map and obj:IsDescendantOf(map) and not PHX.isDynamicGameplayPart(obj) then
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
        if PHX.isPressureSensorVFX(obj) then
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

function PHX.applySaveCpu()
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
        PHX.optimizeVisualObject(obj)
        -- Yield periodically so Delta/mobile does not freeze the UI while optimizing a huge map.
        if i % 250 == 0 then task.wait() end
    end
    cpuObjects = nil
    workspace.DescendantAdded:Connect(function(obj)
        task.defer(function() pcall(PHX.optimizeVisualObject, obj) end)
    end)

    if CONFIG.SAVE_CPU.FULL_3D_RENDER_OFF then
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
    end

    logLine("SAVE_CPU", "ON | fps="..tostring(CONFIG.SAVE_CPU.FPS_CAP).." hideMap="..tostring(CONFIG.SAVE_CPU.HIDE_STATIC_MAP_VISUALS).." preservePressureVFX=true")
end

task.spawn(function()
    task.wait(1)
    PHX.applySaveCpu()
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
    if not r then return "UNKNOWN", math.huge end
    local p = r.Position

    -- Landmark-first region detection. The old nearest-portal-only method could
    -- misclassify a whole island and make Hydra recovery bounce through Castle/Turtle.
    local hydraD = (p - CONFIG.DRAGON_HUNTER.STAND.Position).Magnitude
    local turtleD = (p - CONFIG.MOB_CAMPS.ForestPirate.Position).Magnitude
    local tikiD = (p - CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude
    local castleD = (p - CONFIG.PORTALS.Castle_To_Hydra.Position).Magnitude

    if hydraD <= 5200 then return "HYDRA", hydraD end
    if turtleD <= 6500 then return "TURTLE", turtleD end
    if tikiD <= 5200 then return "TIKI", tikiD end
    if castleD <= 4200 then return "CASTLE", castleD end

    local regions = {
        TIKI = CONFIG.PORTALS.Tiki_To_Castle.Position,
        CASTLE = CONFIG.PORTALS.Castle_To_Hydra.Position,
        TURTLE = CONFIG.PORTALS.Turtle_To_Castle.Position,
        HYDRA = CONFIG.PORTALS.Hydra_To_Castle.Position,
    }

    local best,bestD = "UNKNOWN", math.huge
    for name,pos in pairs(regions) do
        local d = (p-pos).Magnitude
        if d < bestD then best,bestD = name,d end
    end
    if bestD > 8000 then return "UNKNOWN", bestD end
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

        -- Critical V2.8 fix: Castle portals sit close together. A straight tween
        -- to Hydra can physically cross the Turtle/Tiki trigger first. Always approach
        -- from ABOVE the selected gate, then descend to its own entry side.
        local approach = cf * CFrame.new(0,0,-12)
        if not highTween(approach, 320, token) then
            task.wait(.15)
        end
        if token and not isRunning(token) then return false end

        safeTween(cf * CFrame.new(0,0,3), 90, token)
        task.wait(.30)

        local r = root()
        if r then
            local passes = {
                CFrame.new(0,0,8),
                CFrame.new(0,0,-3),
                CFrame.new(3,0,1),
                CFrame.new(-3,0,1),
                CFrame.new(0,1.5,0),
            }
            for _,off in ipairs(passes) do
                if token and not isRunning(token) then return false end
                r.CFrame = cf * off
                task.wait(.18)
                local current = getRegion()
                if current == expectedRegion then
                    markPortalSuccess()
                    local afterRoot = root()
                    logLine("PORTAL_OK", "to="..tostring(expectedRegion).." pos="..tostring(afterRoot and afterRoot.Position or "nil"))
                    noteProgress("PORTAL:"..tostring(expectedRegion))
                    task.wait(1.25)
                    return true
                end
                -- If another nearby Castle portal fired, STOP manipulating CFrame
                -- immediately. The next route iteration will deliberately return to Castle.
                if current ~= beforeRegion and current ~= "UNKNOWN" then
                    logLine("PORTAL_WRONG_DEST", "wanted="..tostring(expectedRegion).." got="..tostring(current).." attempt="..attempt)
                    markPortalSuccess()
                    task.wait(1.25)
                    break
                end
            end
        end

        for _=1,10 do
            task.wait(.18)
            local current = getRegion()
            if current == expectedRegion then
                markPortalSuccess()
                local afterRoot = root()
                logLine("PORTAL_OK", "to="..tostring(expectedRegion).." pos="..tostring(afterRoot and afterRoot.Position or "nil"))
                noteProgress("PORTAL:"..tostring(expectedRegion))
                task.wait(1.25)
                return true
            end
            if current ~= beforeRegion and current ~= "UNKNOWN" then
                logLine("PORTAL_WRONG_DEST", "wanted="..tostring(expectedRegion).." got="..tostring(current).." replication phase")
                markPortalSuccess()
                task.wait(1.25)
                break
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

function PHX.prehistoricMarker()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    return locations and (locations:FindFirstChild("Prehistoric Island") or locations:FindFirstChild("PrehistoricIsland"))
end

local function findPrehistoric()
    local map = workspace:FindFirstChild("Map")
    local island = map and map:FindFirstChild("PrehistoricIsland")
    if island then return island end
    return nil
end

local function boatFlyTo(boat, targetPos, token)
    if not boat or not boat.Parent then return false end
    local start = boat:GetPivot()
    local startPos = start.Position
    local dist = (targetPos-startPos).Magnitude
    local duration = math.max(dist/CONFIG.BOAT_TWEEN_SPEED, .05)
    local startTime = os.clock()

    while isRunning(token) and boat.Parent do
        if findPrehistoric() or PHX.prehistoricMarker() then return true end
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
    return findPrehistoric() ~= nil or PHX.prehistoricMarker() ~= nil
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
        if PHX.prehistoricMarker() then
            setStatus("MASTER: Prehistoric marker detected -> STOP boat, waiting map")
            local deadline = os.clock() + 12
            while isRunning(token) and os.clock() < deadline do
                island = findPrehistoric()
                if island then return island end
                task.wait(.15)
            end
        end
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

-- V2.9 keeps the V2.8 pressure worker learned from the supplied full-run video:
-- react immediately instead of waiting for pressure/relic damage to accumulate.
function PHX.pressureRockBurst(target, token)
    if not target or not target.model or not target.part then return false end
    if not target.model.Parent or not rockActive(target.model) then return true end

    local deadline = os.clock() + CONFIG.PRESSURE.MAX_BURST_SECONDS
    while isRunning(token) and target.model.Parent and rockActive(target.model) and os.clock() < deadline do
        local p = target.part.Position
        local rp = root()
        if not rp then return false end

        local hover = CFrame.new(p + Vector3.new(0, CONFIG.PRESSURE.ROCK_HOVER_Y, 0))
        if (rp.Position - hover.Position).Magnitude > 14 then
            if not safeTween(hover, CONFIG.PRESSURE_TWEEN_SPEED, token) then return false end
        else
            rp.CFrame = CFrame.lookAt(rp.Position, Vector3.new(p.X, rp.Position.Y, p.Z))
        end
        aimAt(p)

        local function castSet(tooltip)
            local tool = equipTooltip(tooltip)
            if not tool then return end
            for _,k in ipairs(SKILL_KEYS) do
                if not isRunning(token) or not target.model.Parent or not rockActive(target.model) then break end
                aimAt(p)
                pressKey(k, CONFIG.PRESSURE.SKILL_HOLD)
                task.wait(CONFIG.PRESSURE.SKILL_GAP)
            end
        end

        -- User-locked pressure combo: Melee X/C/V/F, then Fruit X/C/V/F. No M1.
        castSet("Melee")
        if target.model.Parent and rockActive(target.model) then castSet("Blox Fruit") end

        if target.model.Parent and rockActive(target.model) then
            task.wait(.03)
        end
    end

    if not target.model.Parent or not rockActive(target.model) then
        noteProgress("PRESSURE_ROCK_FIXED")
        return true
    end
    return false
end

function PHX.pickPressureRock(island, offset)
    local rocks = activePressureRocks(island)
    if #rocks == 0 then return nil, 0 end
    local idx = ((tonumber(offset) or 1) - 1) % #rocks + 1
    return rocks[idx], #rocks
end

function PHX.golemKillAura(golem, token)
    if not golem or not golem.Parent then return true end
    local gh = golem:FindFirstChildOfClass("Humanoid")
    if not gh or gh.Health <= 0 then return true end

    local deadline = os.clock() + CONFIG.GOLEM_AURA.BURST_SECONDS
    local tool = equipTooltip("Melee")

    while isRunning(token) and golem.Parent and gh.Parent and gh.Health > 0 and os.clock() < deadline do
        local gp = golem:FindFirstChild("HumanoidRootPart") or golem:FindFirstChild("Head")
        local rp = root()
        if not gp or not rp then break end

        pcall(function()
            gp.CanCollide = false
            if gp:IsA("BasePart") then
                gp.Size = Vector3.new(CONFIG.GOLEM_AURA.HITBOX_SIZE, CONFIG.GOLEM_AURA.HITBOX_SIZE, CONFIG.GOLEM_AURA.HITBOX_SIZE)
            end
        end)

        if (rp.Position - gp.Position).Magnitude > CONFIG.GOLEM_AURA.APPROACH_DISTANCE then
            if not safeTween(CFrame.new(gp.Position + Vector3.new(0, CONFIG.GOLEM_AURA.HOVER_Y, 0)), 420, token) then
                return false
            end
        end

        aimAt(gp.Position)
        tool = equipTooltip("Melee") or tool
        if tool and tool.Parent == char() then
            virtualToolClick(tool, {golem})
        end
        task.wait(CONFIG.GOLEM_AURA.ATTACK_INTERVAL)
    end

    if gh.Health <= 0 or not golem.Parent then
        noteProgress("LAVA_GOLEM_DELETED")
        return true
    end
    return false
end

local function masterPressureLoop(island, token)
    enableLavaProtection(island)
    setStatus("MASTER: pressure controller armed")

    while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") == true do
        local pressure = getPressure()
        local hpPct = getRelicHealthPercent(island)
        local target, rockCount = PHX.pickPressureRock(island, teamIndex(LP.Name) or 1)

        local emergency = (pressure and pressure >= CONFIG.PRESSURE.EMERGENCY_AT)
            or (hpPct and hpPct <= CONFIG.PRESSURE.RELIC_EMERGENCY_AT)

        setStatus(
            "MASTER | Pressure="..tostring(pressure or "?")..
            "% | Relic="..string.format("%.1f", hpPct or 0)..
            "% | Rocks="..tostring(rockCount)..
            (emergency and " | EMERGENCY" or "")
        )

        if target then
            PHX.pressureRockBurst(target, token)
        else
            task.wait(.05)
        end
    end

    disableLavaProtection()
end

local function slaveGolemLoop(island, token)
    enableLavaProtection(island)
    local enemies = workspace:FindFirstChild("Enemies")
    local relic = getRelic(island)
    local rp = relicPart(relic)

    while isRunning(token) and island.Parent and island:GetAttribute("IsMinigameActive") == true do
        local golem = nil
        if enemies then
            for _,m in ipairs(enemies:GetChildren()) do
                if m.Name == "Lava Golem" then
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then
                        golem = m
                        break
                    end
                end
            end
        end

        -- Golems directly threaten Relic HP. All four slaves prioritize the same
        -- server-visible target and use the proven Net attack backend as a kill aura.
        if golem then
            local gh = golem:FindFirstChildOfClass("Humanoid")
            setStatus("SLAVE KILL AURA | Lava Golem "..tostring(gh and math.floor(gh.Health) or "?"))
            PHX.golemKillAura(golem, token)
        else
            local pressure = getPressure()
            local hpPct = getRelicHealthPercent(island)
            local needAssist = (pressure and pressure >= CONFIG.PRESSURE.ASSIST_AT)
                or (hpPct and hpPct <= CONFIG.PRESSURE.RELIC_ASSIST_AT)

            if needAssist then
                local idx = (slaveIndex() or 1) + 1
                local target, rockCount = PHX.pickPressureRock(island, idx)
                setStatus(
                    "SLAVE PRESSURE ASSIST | P="..tostring(pressure or "?")..
                    "% Relic="..string.format("%.1f", hpPct or 0)..
                    "% Rocks="..tostring(rockCount)
                )
                if target then
                    PHX.pressureRockBurst(target, token)
                else
                    task.wait(.05)
                end
            else
                if rp then
                    local idx = slaveIndex() or 1
                    local off = Vector3.new((idx-2.5)*5, 14, idx%2==0 and 8 or -8)
                    local rr = root()
                    local pos = rp.Position + off
                    if rr and (rr.Position-pos).Magnitude > 12 then
                        safeTween(CFrame.new(pos), 320, token)
                    end
                end
                task.wait(.08)
            end
        end
    end

    disableLavaProtection()
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
    -- In the supplied full-run video Dinosaur Bones are granted automatically
    -- as the event ends. Do only a short physical sweep so eggs are never delayed.
    setStatus("Rewards -> quick Dinosaur Bones sweep")
    local deadline = os.clock()+2.5
    local tried = {}
    local quietSince = os.clock()

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
                    quietSince = os.clock()
                    interactCollectible(v, token)
                end
            end
        end
        if not found then
            if os.clock()-quietSince > .55 then break end
            task.wait(.08)
        end
    end
end


function PHX.dragonVariantFromText(value)
    local s = string.lower(tostring(value or ""))
    if s:find("east",1,true) then return "East" end
    if s:find("west",1,true) then return "West" end
    return nil
end

-- Physical reward identity is strict: an actual Tool named Dragon Fruit (the normal
-- physical-fruit runtime name used by auto-store scripts), or an explicitly East/West
-- Blox Fruit label. Dragon Talon / Dragon Scale / Dragon Hunter never pass this check.
function PHX.isDragonFruitTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = string.lower(tostring(tool.Name or "")):gsub("%s+"," ")
    if name == "dragon fruit" or name == "blox fruit dragon (east)" or name == "blox fruit dragon (west)"
        or name == "dragon (east)" or name == "dragon (west)" then
        return true
    end

    local original = string.lower(tostring(tool:GetAttribute("OriginalName") or ""))
    local fruitName = string.lower(tostring(tool:GetAttribute("FruitName") or ""))
    local itemName = string.lower(tostring(tool:GetAttribute("ItemName") or ""))
    local dragonId = original == "dragon-dragon" or fruitName == "dragon-dragon" or itemName == "dragon-dragon"
    if not dragonId then return false end

    -- Metadata-only Dragon-Dragon must still look like a fruit tool.
    if tool:FindFirstChild("EatRemote", true) then return true end
    local tip = string.lower(tostring(tool.ToolTip or ""))
    return tip:find("fruit",1,true) ~= nil
end

function PHX.dragonVariantFromTool(tool)
    if not PHX.isDragonFruitTool(tool) then return nil end
    local variant = PHX.dragonVariantFromText(tool.Name)
        or PHX.dragonVariantFromText(tool:GetAttribute("Variant"))
        or PHX.dragonVariantFromText(tool:GetAttribute("Form"))
        or PHX.dragonVariantFromText(tool:GetAttribute("Side"))
        or PHX.dragonVariantFromText(tool:GetAttribute("FruitName"))
        or PHX.dragonVariantFromText(tool:GetAttribute("ItemName"))
    if variant then return variant end
    for _,v in ipairs(tool:GetDescendants()) do
        if v:IsA("StringValue") then
            local x = PHX.dragonVariantFromText(v.Value)
            if x then return x end
        end
    end
    return nil
end

function PHX.findPhysicalDragonFruits()
    local result, seen = {}, {}
    for _,container in ipairs({LP.Backpack, char()}) do
        if container then
            for _,v in ipairs(container:GetDescendants()) do
                if v:IsA("Tool") and PHX.isDragonFruitTool(v) and not seen[v] then
                    seen[v] = true
                    result[#result+1] = v
                end
            end
        end
    end
    return result
end

-- Kept for older call-sites. V2.7 intentionally has no fuzzy "unknown Dragon" alarm.
function PHX.findUnknownDragonFruitTools()
    return {}
end

function PHX.storedDragonTotal()
    local ok, inv = pcall(function() return CommF:InvokeServer("getInventoryFruits") end)
    if not ok or type(inv) ~= "table" then return nil end
    local total = 0
    for _,v in pairs(inv) do
        if type(v) == "table" then
            local nm = string.lower(tostring(v.Name or v.name or v.OriginalName or ""))
            if nm == "dragon-dragon" or nm == "dragon" or nm == "dragon fruit"
                or nm:find("dragon (east)",1,true) or nm:find("dragon (west)",1,true) then
                total = total + (tonumber(v.Count or v.count or v.Amount or v.amount) or 1)
            end
        end
    end
    return total
end

function PHX.storeOneDragonFruit(tool)
    if not PHX.isDragonFruitTool(tool) then return true end
    local variant = PHX.dragonVariantFromTool(tool)
    local label = variant and ("Dragon ("..variant..")") or "Dragon Fruit"
    local before = PHX.storedDragonTotal()

    setStatus("!!! PHYSICAL "..label.." -> STORE NOW")
    logLine("DRAGON", "physical Blox Fruit detected | tool="..tostring(tool.Name).." variant="..tostring(variant))
    sendWebhook("🐉 PHYSICAL DRAGON FRUIT DETECTED", "Immediate StoreFruit guard activated.", {
        {name="Account", value=LP.Name, inline=true},
        {name="Tool", value=tostring(tool.Name), inline=true},
        {name="Variant", value=tostring(variant or "server/tool metadata"), inline=true},
    })

    for attempt=1,CONFIG.DRAGON_GUARD.STORE_RETRIES do
        if not tool.Parent then
            DRAGON_GUARD_STATE.LastStored = label
            return true
        end

        local storeId = tostring(tool:GetAttribute("OriginalName") or "")
        if storeId == "" or not string.lower(storeId):find("dragon",1,true) then storeId = "Dragon-Dragon" end
        local ok, result = pcall(function()
            return CommF:InvokeServer("StoreFruit", storeId, tool)
        end)
        task.wait(CONFIG.DRAGON_GUARD.RETRY_DELAY)

        local after = PHX.storedDragonTotal()
        local disappeared = tool.Parent == nil
        local countIncreased = before ~= nil and after ~= nil and after > before
        logLine("DRAGON_STORE", "attempt="..attempt.." id="..tostring(storeId).." pcall="..tostring(ok).." result="..tostring(result).." disappeared="..tostring(disappeared).." storedBefore="..tostring(before).." storedAfter="..tostring(after))

        if disappeared or countIncreased then
            DRAGON_GUARD_STATE.LastStored = label
            setStatus(label.." STORED safely")
            sendWebhook("✅ DRAGON FRUIT STORED", label.." secured before reset/teleport.", {
                {name="Account", value=LP.Name, inline=true}, {name="Tool", value=tostring(tool.Name), inline=true},
            })
            return true
        end

        local remaining = PHX.findPhysicalDragonFruits()
        if #remaining == 0 then
            DRAGON_GUARD_STATE.LastStored = label
            return true
        end
        tool = remaining[1]
    end

    DRAGON_GUARD_STATE.Critical = true
    _G.TeamConfig.StopReason = "DRAGON_STORE_FAIL"
    _G.TeamConfig.IsRunning = false
    setStatus("CRITICAL: PHYSICAL DRAGON still present -> STOPPED")
    logLine("DRAGON_STORE_FAIL", "physical Dragon Fruit remained after retries")
    sendWebhook("🚨 CRITICAL: DRAGON STORE FAILED", "Physical Dragon Fruit remains; reset/portal blocked.", {
        {name="Account", value=LP.Name, inline=true},
    })
    return false
end

local function storeDragonFruitCritical()
    if DRAGON_GUARD_STATE.Busy then
        local deadline = os.clock() + 8
        while DRAGON_GUARD_STATE.Busy and os.clock() < deadline do task.wait(.05) end
        return #PHX.findPhysicalDragonFruits() == 0 and not DRAGON_GUARD_STATE.Critical
    end

    DRAGON_GUARD_STATE.Busy = true
    local okAll = true
    local safety = 0
    while safety < 4 do
        safety = safety + 1
        local fruits = PHX.findPhysicalDragonFruits()
        if #fruits == 0 then break end
        if not PHX.storeOneDragonFruit(fruits[1]) then okAll = false break end
        task.wait(.1)
    end
    DRAGON_GUARD_STATE.Busy = false
    return okAll and #PHX.findPhysicalDragonFruits() == 0
end

function PHX.secureDragonWindow(seconds, token)
    local untilAt = os.clock() + (tonumber(seconds) or 0)
    while os.clock() < untilAt do
        if token and not isRunning(token) then return false end
        if #PHX.findPhysicalDragonFruits() > 0 then
            if not storeDragonFruitCritical() then return false end
        end
        task.wait(.08)
    end
    if #PHX.findPhysicalDragonFruits() > 0 then return storeDragonFruitCritical() end
    return not DRAGON_GUARD_STATE.Critical
end

function PHX.hookDragonContainer(container)
    if not container then return end
    container.ChildAdded:Connect(function(obj)
        task.defer(function()
            task.wait(.05)
            if PHX.isDragonFruitTool(obj) then
                logLine("DRAGON_WATCH", "physical Blox Fruit ChildAdded -> "..tostring(obj.Name))
                storeDragonFruitCritical()
            end
        end)
    end)
end

PHX.hookDragonContainer(LP.Backpack)
if char() then PHX.hookDragonContainer(char()) end
LP.CharacterAdded:Connect(function(c)
    PHX.hookDragonContainer(c)
    task.defer(function()
        task.wait(.5)
        storeDragonFruitCritical()
    end)
end)
task.defer(function() storeDragonFruitCritical() end)

local function eggPosition(obj)
    local p = interactionPart(obj)
    return p and p.Position
end

function PHX.collectDragonEggRemote()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    local re = net and net:FindFirstChild("RE/CollectedDragonEgg")
    if not re then return false end
    local ok = pcall(function() re:FireServer() end)
    return ok
end

local function collectAssignedEgg(island, token)
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    if not folder then
        setStatus("Waiting Dragon Egg folder")
        local waitUntil = os.clock() + CONFIG.EGG.SPAWN_WAIT_SECONDS
        while isRunning(token) and os.clock() < waitUntil do
            core = island:FindFirstChild("Core")
            folder = core and core:FindFirstChild("SpawnedDragonEggs")
            if folder then break end
            task.wait(.10)
        end
        if not folder then
            logLine("EGG_NONE", "SpawnedDragonEggs folder not found")
            return true
        end
    end

    local deadline = os.clock() + CONFIG.EGG.SPAWN_WAIT_SECONDS
    while isRunning(token) and os.clock() < deadline do
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

            if rank > #eggs then
                setStatus("No Dragon Egg assigned this run")
                logLine("EGG", "rank="..rank.." eggs="..#eggs.." no assignment")
                return true
            end

            local egg = eggs[rank]
            local part = interactionPart(egg)
            if not part then
                logLine("EGG_FAIL", "assigned egg has no BasePart")
                return false
            end

            setStatus("Dragon Egg "..rank.."/"..#eggs.." -> PC HOLD E")
            highTween(part.CFrame * CFrame.new(0, 2.5, -CONFIG.EGG.APPROACH_DISTANCE), 380, token)
            aimAt(part.Position)

            local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
            local holdTime = CONFIG.EGG.HOLD_E_SECONDS
            if prompt then
                holdTime = math.max(holdTime, (tonumber(prompt.HoldDuration) or 0) + .12)
            end

            local picked = false
            for attempt=1,CONFIG.EGG.RETRIES do
                if not isRunning(token) then return false end
                if not egg.Parent or not egg:IsDescendantOf(folder) then
                    picked = true
                    break
                end

                local ep = interactionPart(egg)
                if ep then
                    local rr = root()
                    if rr and (rr.Position-ep.Position).Magnitude > 7 then
                        highTween(ep.CFrame * CFrame.new(0, 2.5, -CONFIG.EGG.APPROACH_DISTANCE), 380, token)
                    end
                    aimAt(ep.Position)
                end

                setStatus("Dragon Egg HOLD E "..attempt.."/"..CONFIG.EGG.RETRIES.." | "..string.format("%.2fs", holdTime))
                holdE(holdTime)
                task.wait(CONFIG.EGG.RETRY_GAP)

                if not egg.Parent or not egg:IsDescendantOf(folder) then
                    picked = true
                    break
                end
            end

            -- Fallback only after physical PC-style Hold-E attempts. Never spam the
            -- reward remote from range.
            if not picked and egg.Parent and egg:IsDescendantOf(folder) then
                logLine("EGG", "Hold-E not confirmed -> one remote fallback")
                PHX.collectDragonEggRemote()
                task.wait(.35)
                picked = not egg.Parent or not egg:IsDescendantOf(folder)
            end

            if not picked then
                setStatus("Dragon Egg pickup NOT confirmed -> staying on island")
                logLine("EGG_FAIL", "rank="..rank.." holdE attempts exhausted")
                return false
            end

            noteProgress("DRAGON_EGG_PICKED")
            setStatus("Dragon Egg picked -> Dragon fruit guard 10s")
            return PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS, token)
        end
        task.wait(.10)
    end

    -- No egg can legitimately happen on a low-quality relic run. Do not freeze forever.
    logLine("EGG_NONE", "no eggs spawned within wait window")
    setStatus("No Dragon Egg spawned this run")
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
    pcall(function() trySignal(btn.Activated) end)
    pcall(function() trySignal(btn.MouseButton1Click) end)
    task.wait(.12)
    return true
end

-- Dragon Hunter interaction is intentionally screen-click free.
-- V2.7.1 used VirtualInputManager on the NPC's projected screen position; that could
-- accidentally hit this script's STOP button and was also unreliable on mobile UI layers.
function PHX.dragonHunterRemote()
    local modules = ReplicatedStorage:FindFirstChild("Modules") or ReplicatedStorage:WaitForChild("Modules", 5)
    local net = modules and (modules:FindFirstChild("Net") or modules:WaitForChild("Net", 5))
    return net and (net:FindFirstChild("RF/DragonHunter") or net:WaitForChild("RF/DragonHunter", 5))
end

function PHX.dragonHunterCheckRaw()
    local rf = PHX.dragonHunterRemote()
    if not rf then return nil end
    local ok, response = pcall(function()
        return rf:InvokeServer({Context="Check"})
    end)
    if not ok then return nil end
    return response
end

function PHX.dragonHunterCheckText()
    local response = PHX.dragonHunterCheckRaw()
    if response == nil then return "" end
    local found = ""
    local seen = {}
    local function walk(v, depth)
        if found ~= "" or depth > 8 then return end
        if type(v) == "string" then
            local l = string.lower(v)
            if l:find("hydra enforcer",1,true)
                or l:find("venomous assailant",1,true)
                or (l:find("destroy",1,true) and l:find("tree",1,true)) then
                found = v
            end
        elseif type(v) == "table" and not seen[v] then
            seen[v] = true
            for k,x in pairs(v) do
                walk(k, depth + 1)
                walk(x, depth + 1)
            end
        end
    end
    walk(response, 0)
    return found
end

local function questText()
    local direct = PHX.dragonHunterCheckText()
    if direct ~= "" then return direct end
    local dg = dialogueGui()
    if not dg then return "" end
    for _,v in ipairs(dg:GetDescendants()) do
        if v:IsA("TextLabel") or v:IsA("TextButton") then
            local t = tostring(v.Text or "")
            local l = string.lower(t)
            if l:find("hydra enforcer",1,true)
                or l:find("venomous assailant",1,true)
                or (l:find("destroy",1,true) and l:find("tree",1,true)) then
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
    if l:find("destroy",1,true) and l:find("tree",1,true) then return "TREE" end
    return "NONE"
end

function PHX.questStatusText()
    local kind = questKind()
    local text = questText()
    if kind == "NONE" then return "No active Dragon Hunter quest" end
    if text == "" then text = kind end
    return "QUEST "..kind.." | "..text
end

PHX.QuestCompletedAt = -math.huge
PHX.QuestCompletedText = ""
PHX.LastQuestAcceptedAt = -math.huge

function PHX.markQuestCompleteText(text)
    local l = string.lower(tostring(text or ""))
    if l:find("task completed",1,true) or l:find("quest completed",1,true) then
        PHX.QuestCompletedAt = os.clock()
        PHX.QuestCompletedText = tostring(text or "Quest Completed")
        logLine("QUEST_POPUP", PHX.QuestCompletedText)
        noteProgress("QUEST_COMPLETED_POPUP")
        return true
    end
    return false
end

function PHX.questCompleteVisible()
    local dg = dialogueGui()
    local roots = {dg, PG:FindFirstChild("Notifications"), PG:FindFirstChild("Main")}
    for _,base in ipairs(roots) do
        if base then
            for _,v in ipairs(base:GetDescendants()) do
                if (v:IsA("TextLabel") or v:IsA("TextButton")) and visibleGui(v) then
                    if PHX.markQuestCompleteText(v.Text) then return true end
                end
            end
        end
    end
    return false
end

function PHX.questCompleteSince(since)
    if PHX.QuestCompletedAt >= (since or -math.huge) then return true end
    return PHX.questCompleteVisible() and PHX.QuestCompletedAt >= (since or -math.huge)
end

function PHX.watchQuestPopupObject(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
    local function inspect()
        if visibleGui(obj) then PHX.markQuestCompleteText(obj.Text) end
    end
    obj:GetPropertyChangedSignal("Text"):Connect(inspect)
    obj:GetPropertyChangedSignal("Visible"):Connect(inspect)
    inspect()
end

for _,obj in ipairs(PG:GetDescendants()) do pcall(PHX.watchQuestPopupObject, obj) end
PG.DescendantAdded:Connect(function(obj) pcall(PHX.watchQuestPopupObject, obj) end)

function PHX.fireDragonHunterWorldInteract()
    local npcPos = CONFIG.DRAGON_HUNTER.NPC.Position
    local best, bestD = nil, math.huge
    -- Only interaction objects near Dragon Hunter are eligible; this avoids touching unrelated NPCs.
    for _,v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") or v:IsA("ClickDetector") then
            local p = v.Parent
            local pos = nil
            if p and p:IsA("BasePart") then
                pos = p.Position
            elseif p and p:IsA("Model") then
                local pp = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
                pos = pp and pp.Position or nil
            end
            if pos then
                local d = (pos - npcPos).Magnitude
                if d < 45 and d < bestD then
                    best, bestD = v, d
                end
            end
        end
    end
    if not best then return false, "NO_WORLD_INTERACT" end
    if best:IsA("ProximityPrompt") then
        if fireproximityprompt then
            local ok = pcall(function() fireproximityprompt(best) end)
            return ok, "PROXIMITY_PROMPT"
        end
        local ok = pcall(function()
            best:InputHoldBegin()
            task.wait(math.max(.05, tonumber(best.HoldDuration) or 0))
            best:InputHoldEnd()
        end)
        if ok then return true, "PROMPT_HOLD" end
    end
    if best:IsA("ClickDetector") and fireclickdetector then
        local ok = pcall(function() fireclickdetector(best) end)
        return ok, "CLICK_DETECTOR"
    end
    return false, "EXECUTOR_NO_WORLD_INTERACT"
end

local function openDragonHunter(token)
    -- V2.9.3: NO screen-space mouse click. We only use the NPC's world
    -- interaction object (ProximityPrompt/ClickDetector) so the click cannot
    -- accidentally open Uzoth/Dragon-Talon lore panels or hit our own UI.
    if not safeTween(CONFIG.DRAGON_HUNTER.STAND, 260, token) then return false end
    task.wait(.20)

    local dg = dialogueGui()
    if dg and dg:IsA("ScreenGui") and PHX.DialogueLocallyHidden then
        pcall(function() dg.Enabled = true end)
        PHX.DialogueLocallyHidden = false
    end

    for attempt=1,10 do
        if not isRunning(token) then return false end
        local opts = dialogueOptions()
        if #opts >= 3 then
            logLine("DRAGON_HUNTER_INTERACT", "dialogue already open | options="..#opts)
            return true
        end

        local worldOK, worldMode = PHX.fireDragonHunterWorldInteract()
        logLine("DRAGON_HUNTER_INTERACT", "world interact="..tostring(worldMode).." ok="..tostring(worldOK).." | attempt="..attempt)
        if worldOK then
            local deadline = os.clock() + .75
            while os.clock() < deadline do
                if #dialogueOptions() >= 3 then return true end
                task.wait(.03)
            end
        end
        task.wait(.08)
    end
    return #dialogueOptions() >= 3
end

-- After Hunt -> Sure the game may leave one last NPC speech bubble open.
-- The user's recording shows that one more Interact closes it. Do that with
-- the world prompt, not a screen click. Close-like GUI controls are a secondary
-- fallback, and hiding DialogueGui is UI cleanup only after the quest was accepted.
function PHX.dismissDragonHunterFinalBubble()
    local dg = dialogueGui()
    if not dg then return true end

    -- First try explicit Close/Continue/OK/Bye controls if this build exposes one.
    for _,v in ipairs(dg:GetDescendants()) do
        if (v:IsA("TextButton") or v:IsA("ImageButton")) and visibleGui(v) then
            local txt = string.lower(tostring((v:IsA("TextButton") and v.Text) or ""))
            local nm = string.lower(v.Name or "")
            if txt:find("continue",1,true) or txt:find("close",1,true)
                or txt == "ok" or txt == "okay" or txt:find("bye",1,true)
                or txt:find("leave",1,true) or nm:find("close",1,true)
                or nm:find("continue",1,true) then
                pcall(function() fireButton(v) end)
                task.wait(.08)
                if not dialogueGui() or #dialogueOptions() == 0 then return true end
            end
        end
    end

    -- The normal in-game behavior in the supplied video: press Interact once more.
    local ok, mode = PHX.fireDragonHunterWorldInteract()
    logLine("DRAGON_HUNTER_DISMISS", "world interact="..tostring(mode).." ok="..tostring(ok))
    task.wait(.16)

    dg = dialogueGui()
    if dg and visibleGui(dg) then
        -- Final visual cleanup. Mark it so openDragonHunter can re-enable it next time.
        if dg:IsA("ScreenGui") then
            pcall(function() dg.Enabled = false end)
            PHX.DialogueLocallyHidden = true
        elseif dg:IsA("GuiObject") then
            pcall(function() dg.Visible = false end)
            PHX.DialogueLocallyHidden = true
        end
    end
    return true
end

function PHX.closeDragonHunterDialogue()
    local opts = dialogueOptions()
    -- Only close the four-option root menu. Never fire the second option in
    -- the two-option confirmation stage because that could reject a Hunt.
    if #opts >= 4 then
        pcall(function() fireButton(opts[#opts]) end) -- Nevermind / close
        task.wait(.05)
    end
end

local function receiveDragonHunterQuest(token)
    -- A completed popup means the previous Hunt is finished even if RF/DragonHunter
    -- still returns stale text for a short time. Never treat that stale text as active.
    if questKind() ~= "NONE" and PHX.QuestCompletedAt < (PHX.LastQuestAcceptedAt or -math.huge) then
        setStatus(PHX.questStatusText())
        return true
    end

    -- Restore the exact interaction path that previously worked on this account:
    -- physically return to Dragon Hunter, open DialogueGui, fire Hunt, then fire Sure.
    setStatus("Dragon Hunter NPC -> opening dialogue")
    for cycle=1,4 do
        if not isRunning(token) then return false end
        if openDragonHunter(token) then
            local opts = dialogueOptions()
            if #opts >= 3 then
                setStatus("Dragon Hunter NPC -> HUNT")
                fireButton(opts[1])

                local confirmDeadline = os.clock() + 2.0
                local confirmed = false
                while isRunning(token) and os.clock() < confirmDeadline do
                    opts = dialogueOptions()
                    if #opts >= 1 and #opts <= 2 then
                        setStatus("Dragon Hunter NPC -> SURE")
                        fireButton(opts[1])
                        confirmed = true
                        break
                    end
                    task.wait(.04)
                end

                if confirmed then
                    local acceptedAt = os.clock()
                    local verifyDeadline = acceptedAt + 3.5
                    while isRunning(token) and os.clock() < verifyDeadline do
                        -- A fresh quest can be the same TYPE as the previous one, so the
                        -- confirmation/dialogue transition itself is accepted, while Check
                        -- is used only to populate the status text.
                        local kind = questKind()
                        if kind ~= "NONE" or #dialogueOptions() == 0 then
                            PHX.LastQuestAcceptedAt = acceptedAt
                            PHX.QuestCompletedAt = -math.huge
                            PHX.QuestCompletedText = ""
                            local qt = kind ~= "NONE" and PHX.questStatusText() or "QUEST ACCEPTED | waiting replicated text"
                            setStatus(qt)
                            logLine("DRAGON_HUNTER_NPC", "accepted cycle="..cycle.." | "..qt)
                            noteProgress("QUEST_ACCEPTED_NPC:"..tostring(kind))
                            PHX.dismissDragonHunterFinalBubble()
                            return true
                        end
                        task.wait(.05)
                    end
                end
            end
        end
        PHX.closeDragonHunterDialogue()
        task.wait(.12)
    end

    -- Last-resort direct request only after the proven NPC path failed.
    local rf = PHX.dragonHunterRemote()
    if rf then
        local ok = pcall(function() rf:InvokeServer({Context="RequestQuest"}) end)
        if ok then
            task.wait(.25)
            local kind = questKind()
            if kind ~= "NONE" then
                PHX.LastQuestAcceptedAt = os.clock()
                PHX.QuestCompletedAt = -math.huge
                setStatus("RF FALLBACK ACCEPTED | "..PHX.questStatusText())
                logLine("DRAGON_HUNTER_RF_FALLBACK", PHX.questStatusText())
                return true
            end
        end
    end

    setStatus("Dragon Hunter quest FAILED -> retrying NPC")
    logLine("DRAGON_HUNTER", "NPC Hunt/Sure + RF fallback failed")
    return false
end

--==============================================================
-- DYNAMIC HYDRA TREE DETECTOR
--==============================================================
-- Hydra has several different tree/bamboo assets. We discover them at runtime,
-- dedupe their models, and prefer candidates around the known Hydra tree field.
-- CONFIG.TREES remains only as a last-resort fallback if the map changes names.
PHX._HydraTreeCache = PHX._HydraTreeCache or {At=-math.huge, List={}}
PHX._HydraTreeLastHit = PHX._HydraTreeLastHit or setmetatable({}, {__mode="k"})

function PHX.hydraTreePart(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if not obj:IsA("Model") then return nil end

    -- Some Hydra assets use Trunk as a MODEL, not a BasePart. V2.9 returned
    -- that Model directly and later read .Position, which crashed the state
    -- machine (e.g. WaterfallIslandModel.TallTree1.Trunk). Always resolve
    -- the tree to a real BasePart before any spatial math.
    if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then
        return obj.PrimaryPart
    end

    local trunk = obj:FindFirstChild("Trunk", true)
    if trunk then
        if trunk:IsA("BasePart") then
            return trunk
        elseif trunk:IsA("Model") then
            if trunk.PrimaryPart and trunk.PrimaryPart:IsA("BasePart") then
                return trunk.PrimaryPart
            end
            local trunkPart = trunk:FindFirstChildWhichIsA("BasePart", true)
            if trunkPart then return trunkPart end
        end
    end

    return obj:FindFirstChildWhichIsA("BasePart", true)
end

function PHX.hydraTreeCanonical(obj)
    if not obj then return nil end
    local cur = obj
    local best = obj:IsA("Model") and obj or nil
    for _=1,6 do
        if not cur then break end
        local l = string.lower(cur.Name)
        if cur:IsA("Model") and (l:find("tree",1,true) or l:find("bamboo",1,true)) then
            best = cur
        end
        cur = cur.Parent
    end
    return best or obj
end

function PHX.hydraTreeHealthSignal(obj)
    if not obj then return false end
    local function healthish(x)
        local n = string.lower(x.Name)
        if n == "health" or n == "hp" or n == "hitpoints" or n == "hitpoint" then
            if x:IsA("IntValue") or x:IsA("NumberValue") then return true end
        end
        return false
    end
    if healthish(obj) then return true end
    if obj:IsA("Model") then
        for _,d in ipairs(obj:GetDescendants()) do
            if healthish(d) then return true end
        end
    end
    for _,name in ipairs({"Health","HP","Hitpoints","HitPoints"}) do
        if obj:GetAttribute(name) ~= nil then return true end
    end
    return false
end

function PHX.hydraTreeCandidate(obj)
    if not obj or not obj.Parent then return false end
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end

    local l = string.lower(obj.Name)
    local named = l:find("tree",1,true) or l:find("bamboo",1,true) or l:find("trunk",1,true) or l:find("stem",1,true)
    local healthSignal = PHX.hydraTreeHealthSignal(obj)
    if not named and not healthSignal then return false end
    if l:find("leaf",1,true) or l:find("leaves",1,true) or l:find("foliage",1,true) or l:find("canopy",1,true) then
        return false
    end

    local canon = PHX.hydraTreeCanonical(obj)
    local p = PHX.hydraTreePart(canon)
    if not p then return false end
    local pos = p.Position

    -- Broad Hydra tree zone. The nearest-reference gate prevents unrelated map
    -- vegetation from being mistaken for quest trees.
    if pos.X < 4850 or pos.X > 5950 or pos.Y < 930 or pos.Y > 1325 or pos.Z < -100 or pos.Z > 1250 then
        return false
    end

    local nearest = math.huge
    for _,cf in ipairs(CONFIG.TREES) do
        local d = (pos - cf.Position).Magnitude
        if d < nearest then nearest = d end
    end
    return nearest <= 720
end

function PHX.scanHydraTrees(force)
    local cache = PHX._HydraTreeCache
    if not force and os.clock() - cache.At < .65 and #cache.List > 0 then
        return cache.List
    end

    local out, seen = {}, {}

    -- Spatial query instead of workspace.Map:GetDescendants() every cycle.
    -- This is much cheaper for multi-account/SaveCPU setups and only inspects
    -- objects physically inside the Hydra tree field.
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LP.Character}
    params.MaxParts = 1200

    local zoneCF = CFrame.new(5400, 1125, 560)
    local zoneSize = Vector3.new(1250, 430, 1400)
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInBox(zoneCF, zoneSize, params)
    end)
    if not ok then parts = {} end

    for _,part in ipairs(parts) do
        local probes = {part}
        local cur = part.Parent
        for _=1,5 do
            if not cur then break end
            probes[#probes+1] = cur
            cur = cur.Parent
        end

        for _,obj in ipairs(probes) do
            local okCandidate, isCandidate = pcall(PHX.hydraTreeCandidate, obj)
            if okCandidate and isCandidate then
                local canon = PHX.hydraTreeCanonical(obj)
                local p = PHX.hydraTreePart(canon)
                if canon and p and p:IsA("BasePart") and not seen[canon] then
                    seen[canon] = true
                    out[#out+1] = canon
                end
                break
            elseif not okCandidate then
                logLine("TREE_SCAN_SKIP", tostring(obj:GetFullName()).." | "..tostring(isCandidate))
            end
        end
    end

    local rr = root()
    table.sort(out, function(a,b)
        local ap = PHX.hydraTreePart(a)
        local bp = PHX.hydraTreePart(b)
        if not ap then return false end
        if not bp then return true end

        local ah = PHX._HydraTreeLastHit[a] or -math.huge
        local bh = PHX._HydraTreeLastHit[b] or -math.huge
        local aFresh = os.clock() - ah > .8
        local bFresh = os.clock() - bh > .8
        if aFresh ~= bFresh then return aFresh end
        if rr then
            return (ap.Position-rr.Position).Magnitude < (bp.Position-rr.Position).Magnitude
        end
        return ah < bh
    end)

    cache.At = os.clock()
    cache.List = out

    local sigParts = {}
    for i=1,math.min(#out,8) do
        local t = out[i]
        local p = PHX.hydraTreePart(t)
        sigParts[#sigParts+1] = t.Name..(p and string.format("@%.0f,%.0f,%.0f", p.Position.X,p.Position.Y,p.Position.Z) or "")
    end
    local sig = table.concat(sigParts, " | ")
    if cache.LastSig ~= sig then
        cache.LastSig = sig
        logLine("TREE_SCAN", "detected="..#out.." | "..sig)
    end

    return out
end

function PHX.pickHydraTree()
    local trees = PHX.scanHydraTrees(false)
    local now = os.clock()
    for _,tree in ipairs(trees) do
        local p = PHX.hydraTreePart(tree)
        local last = PHX._HydraTreeLastHit[tree] or -math.huge
        if p and p.Parent and now - last > .55 then
            return tree, p, #trees
        end
    end
    if #trees > 0 then
        local tree = trees[1]
        return tree, PHX.hydraTreePart(tree), #trees
    end
    return nil, nil, 0
end

local function farmTreeQuest(token)
    local i = 1
    local questStartedAt = PHX.LastQuestAcceptedAt
    if not questStartedAt or questStartedAt == -math.huge then questStartedAt = os.clock() end

    -- User-verified method: cycle ONLY the five known Hydra CFrames. Do not try to
    -- identify map tree models. At every point cast Melee X/C/V/F + Fruit X/C/V/F
    -- straight UP into the sky, then move to the next point.
    while isRunning(token) and not PHX.questCompleteSince(questStartedAt) do
        local cf = CONFIG.TREES[i]
        setStatus(PHX.questStatusText().." | TREE CFrame "..i.."/"..#CONFIG.TREES.." | wait Quest Completed popup")

        if not highTween(cf * CFrame.new(0,10,0), 340, token) then return false end
        local rr = root()
        local upTarget = rr and (rr.Position + Vector3.new(0, 1500, 0)) or (cf.Position + Vector3.new(0,1500,0))
        useXCVF(upTarget)

        PHX.pulseBlazeCollectRemote()
        PHX.touchVisibleBlaze(token, false)

        if PHX.questCompleteSince(questStartedAt) then break end
        i = i + 1
        if i > #CONFIG.TREES then i = 1 end
        task.wait(.035)
    end

    return PHX.questCompleteSince(questStartedAt)
end

function PHX.pulseBlazeCollectRemote()
    local re = PHX.blazeCollectRemote and PHX.blazeCollectRemote() or nil
    if re and re.FireServer then
        local ok = pcall(function() re:FireServer() end)
        return ok
    end
    return false
end

function PHX.blazeCollectRemote()
    local modules = ReplicatedStorage:FindFirstChild("Modules") or ReplicatedStorage:WaitForChild("Modules", 3)
    local net = modules and (modules:FindFirstChild("Net") or modules:WaitForChild("Net", 3))
    return net and (net:FindFirstChild("RE/DragonDojoEmber") or net:FindFirstChild("RE/DragonDojoEmber", true))
end

function PHX.findBlazeParts()
    local out, seen = {}, {}
    local function addObj(obj)
        if not obj then return end
        local p = interactionPart(obj)
        if p and p:IsA("BasePart") and not seen[p] then
            -- Blaze Ember lives on Hydra; reject obviously unrelated Azure/Kitsune objects.
            local fp = string.lower(p:GetFullName())
            if not fp:find("azure",1,true) and not fp:find("kitsune",1,true) then
                seen[p] = true
                out[#out+1] = p
            end
        end
    end

    for _,name in ipairs({"AttachedBlazeEmber","BlazeEmber","FireFlowers","EmberTemplate"}) do
        local obj = workspace:FindFirstChild(name)
        if obj then
            addObj(obj)
            for _,d in ipairs(obj:GetDescendants()) do
                local l = string.lower(d.Name)
                if d:IsA("BasePart") and (l:find("ember",1,true) or l:find("fire",1,true) or name == "EmberTemplate") then
                    addObj(d)
                end
            end
        end
    end

    -- Some builds parent the moving pickup under a differently named container.
    -- Scan only direct workspace children and their immediate children, not the whole map tree.
    for _,obj in ipairs(workspace:GetChildren()) do
        local l = string.lower(obj.Name)
        if (l:find("blaze",1,true) and l:find("ember",1,true)) or l == "fireflowers" then
            addObj(obj)
            for _,d in ipairs(obj:GetChildren()) do addObj(d) end
        end
    end
    return out
end

function PHX.touchVisibleBlaze(token, allowTween)
    local r = root()
    if not r then return 0 end
    local count = 0
    local parts = PHX.findBlazeParts()
    table.sort(parts, function(a,b)
        return (a.Position-r.Position).Magnitude < (b.Position-r.Position).Magnitude
    end)
    for _,p in ipairs(parts) do
        if not isRunning(token) or not p.Parent then break end
        local rr = root()
        if not rr then break end
        local d = (p.Position - rr.Position).Magnitude
        if firetouchinterest and d <= 220 then
            pcall(function()
                firetouchinterest(rr, p, 0)
                firetouchinterest(rr, p, 1)
            end)
            count = count + 1
        elseif allowTween and d <= 2800 then
            safeTween(p.CFrame * CFrame.new(0,1.5,0), 900, token)
            rr = root()
            if rr and firetouchinterest and p.Parent then
                pcall(function()
                    firetouchinterest(rr, p, 0)
                    firetouchinterest(rr, p, 1)
                end)
            end
            count = count + 1
        end
    end
    return count
end

local function farmHunterQuest(token)
    local kind = questKind()
    if kind == "NONE" then return false end
    local questStartedAt = PHX.LastQuestAcceptedAt
    if not questStartedAt or questStartedAt == -math.huge then questStartedAt = os.clock() end
    logLine("QUEST", "start | "..PHX.questStatusText())

    if kind == "TREE" then
        farmTreeQuest(token)
    elseif kind == "HYDRA" then
        while isRunning(token) and not PHX.questCompleteSince(questStartedAt) do
            setStatus(PHX.questStatusText().." | Ember "..tostring(inventoryCount("Blaze Ember")).."/15 | wait Quest Completed popup")
            farmNamedMob("Hydra Enforcer", CONFIG.MOB_CAMPS.HydraEnforcer, token)
            PHX.pulseBlazeCollectRemote()
            PHX.touchVisibleBlaze(token, false)
            task.wait(.02)
        end
    elseif kind == "VENOM" then
        while isRunning(token) and not PHX.questCompleteSince(questStartedAt) do
            setStatus(PHX.questStatusText().." | Ember "..tostring(inventoryCount("Blaze Ember")).."/15 | wait Quest Completed popup")
            farmNamedMob("Venomous Assailant", CONFIG.MOB_CAMPS.VenomousAssailant, token)
            PHX.pulseBlazeCollectRemote()
            PHX.touchVisibleBlaze(token, false)
            task.wait(.02)
        end
    end

    local completed = PHX.questCompleteSince(questStartedAt)
    logLine("QUEST", "popup-complete="..tostring(completed).." | previous="..kind.." | text="..tostring(PHX.QuestCompletedText))
    return completed
end

function PHX.collectBlazeEmberDrops(token, seconds)
    local before = inventoryCount("Blaze Ember", true)
    local maxUntil = os.clock() + (seconds or 2.4)
    local lastSeenAt = os.clock()
    setStatus("Quest complete -> FAST collecting Blaze Embers")

    while isRunning(token) and os.clock() < maxUntil and inventoryCount("Blaze Ember") < 15 do
        PHX.pulseBlazeCollectRemote()
        local touched = PHX.touchVisibleBlaze(token, true)
        if touched > 0 then lastSeenAt = os.clock() end

        local now = inventoryCount("Blaze Ember", true)
        if now >= before + 3 then break end
        -- Once no pickup is visible for a short grace window, immediately move on.
        if touched == 0 and os.clock() - lastSeenAt > .16 then break end
        task.wait(.02)
    end

    local after = inventoryCount("Blaze Ember", true)
    logLine("BLAZE_COLLECT", "before="..tostring(before).." after="..tostring(after).." fastWindow="..tostring(seconds or 2.4))
    return after > before
end

local function farmBlazeEmbers(token)
    while isRunning(token) and inventoryCount("Blaze Ember", true) < 15 do
        if not goHydra(token) then
            setStatus("Hydra portal failed - NOT flying across sea")
            task.wait(.35)
        else
            local completedPrevious = PHX.QuestCompletedAt >= (PHX.LastQuestAcceptedAt or -math.huge)
            local kind = questKind()

            if kind == "NONE" or completedPrevious then
                setStatus("Returning Dragon Hunter NPC -> receive next Hunt")
                if not receiveDragonHunterQuest(token) then
                    task.wait(.15)
                    kind = "NONE"
                else
                    kind = questKind()
                    if kind == "NONE" then
                        -- Dialogue acceptance can replicate a fraction later.
                        local untilAt = os.clock() + 1.4
                        repeat
                            task.wait(.04)
                            kind = questKind()
                        until kind ~= "NONE" or os.clock() >= untilAt or not isRunning(token)
                    end
                end
            end

            if kind ~= "NONE" and isRunning(token) then
                setStatus(PHX.questStatusText().." | Ember "..tostring(inventoryCount("Blaze Ember")).."/15")
                local before = inventoryCount("Blaze Ember", true)
                local collectorAlive = true
                task.spawn(function()
                    while collectorAlive and isRunning(token) do
                        PHX.pulseBlazeCollectRemote()
                        PHX.touchVisibleBlaze(token, false)
                        task.wait(.045)
                    end
                end)

                local completed = farmHunterQuest(token)
                collectorAlive = false

                if completed and isRunning(token) then
                    PHX.collectBlazeEmberDrops(token, 2.0)
                    local after = inventoryCount("Blaze Ember", true)
                    setStatus("Quest Completed popup confirmed | Blaze Ember "..tostring(after).."/15")
                    logLine("QUEST", "cycle done | emberBefore="..tostring(before).." emberAfter="..tostring(after))
                    if after < 15 then
                        -- Next loop is allowed to return to Dragon Hunter only now.
                        task.wait(.04)
                    end
                elseif isRunning(token) then
                    setStatus("Quest popup not detected -> stay on current quest")
                    task.wait(.08)
                end
            end
        end
    end
    return inventoryCount("Blaze Ember", true) >= 15
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
    -- Force a real inventory read before deciding whether Scrap farming is needed.
    PHX.clearOptimisticCount("Scrap Metal")
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
    if #opts < 2 then
        PHX.closeDragonHunterDialogue()
        return false
    end
    fireButton(opts[2]) -- Craft from Hunt/Craft/Gacha/Nevermind menu
    task.wait(.5)
    local opened = findTextObject("volcanic magnet") ~= nil or findTextObject("select a recipe") ~= nil
    if not opened then
        -- Do not leave the four-option NPC menu covering the screen/state machine.
        PHX.closeDragonHunterDialogue()
    end
    return opened
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
    PHX.syncCraftMaterialCounts()

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
        PHX.consumeKnownMaterial("Scrap Metal", 10)
        PHX.consumeKnownMaterial("Blaze Ember", 15)
        PHX.setKnownMaterial("Volcanic Magnet", 1, "CRAFT_LOCAL")
        PHX.clearOptimisticCount("Volcanic Magnet")
    end
    return crafted
end

local function recoverMagnet(token)
    -- V2.7.1: never require three unrelated material counters to be readable before progressing.
    -- Decide phase-by-phase: Scrap -> craft probe -> Blaze Ember -> craft.
    PHX.warmMaterialInventory(1.0)

    if hasVolcanicMagnet() then return true end

    local masterOnline = Players:FindFirstChild(_G.TeamConfig.MasterName) ~= nil
    local scrap, scrapSource = PHX.materialCountInfo("Scrap Metal", true)
    local ember, emberSource = PHX.materialCountInfo("Blaze Ember", true)
    local scrapKnown = scrapSource ~= "UNAVAILABLE" and scrapSource ~= "INIT"
    local emberKnown = emberSource ~= "UNAVAILABLE" and emberSource ~= "INIT"

    setStatus("RECOVERY scan | MASTER="..(masterOnline and "ONLINE" or "OFFLINE").." | Scrap="..tostring(scrap).."/10["..tostring(scrapSource).."] | Ember="..tostring(ember).."/15["..tostring(emberSource).."]")
    logLine("PREFLIGHT", "recover magnet | masterOnline="..tostring(masterOnline).." region="..tostring(getRegion()).." scrap="..tostring(scrap).." src="..tostring(scrapSource).." ember="..tostring(ember).." emberSrc="..tostring(emberSource))

    -- Only farm Scrap when we positively know it is below 10.
    -- If Scrap is unknown, first probe the Dragon Hunter craft menu instead of blindly teleporting Turtle.
    if scrapKnown and scrap < 10 then
        if not farmScrap(token) then return false end
        if not isRunning(token) then return false end
        scrap, scrapSource = PHX.materialCountInfo("Scrap Metal", true)
        scrapKnown = scrapSource ~= "UNAVAILABLE" and scrapSource ~= "INIT"
    end

    -- If Scrap is ready (or unknown), Hydra is the smartest next stop: a visible Craft button proves
    -- both ingredients are already sufficient. This fixes the old 38 Scrap -> PREFLIGHT_WAIT loop.
    setStatus("Material phase -> Hydra craft probe")
    if craftVolcanicMagnet(token) then
        setStatus("Volcanic Magnet crafted")
        logLine("MAGNET", "crafted on pre-Blaze probe")
        return true
    end
    if not isRunning(token) then return false end

    -- Craft failed. If Scrap was unknown, re-check it now; only go Turtle if we can positively
    -- establish that Scrap is actually below 10. Otherwise continue to Blaze Ember farming.
    scrap, scrapSource = PHX.materialCountInfo("Scrap Metal", true)
    scrapKnown = scrapSource ~= "UNAVAILABLE" and scrapSource ~= "INIT"
    if scrapKnown and scrap < 10 then
        setStatus("Craft probe failed | Scrap "..scrap.."/10 -> Floating Turtle")
        if not farmScrap(token) then return false end
        if not isRunning(token) then return false end
    end

    ember, emberSource = PHX.materialCountInfo("Blaze Ember", true)
    emberKnown = emberSource ~= "UNAVAILABLE" and emberSource ~= "INIT"

    -- Unknown Ember is treated as "needs verification/farm", not as a reason to stop the state machine.
    -- If Ember is already sufficient but unreadable, the craft probe above would have succeeded.
    if (not emberKnown) or ember < 15 then
        setStatus("Scrap ready -> Blaze Ember phase | Ember="..tostring(ember).."/15["..tostring(emberSource).."]")
        if not farmBlazeEmbers(token) then return false end
    end
    if not isRunning(token) then return false end

    for attempt=1,4 do
        if craftVolcanicMagnet(token) then
            setStatus("Volcanic Magnet crafted")
            logLine("MAGNET", "crafted after Blaze phase")
            return true
        end
        if not isRunning(token) then return false end
        local s, ss = PHX.materialCountInfo("Scrap Metal", true)
        local e, es = PHX.materialCountInfo("Blaze Ember", true)
        setStatus("Craft retry "..attempt.."/4 | Scrap="..tostring(s).."["..tostring(ss).."] Ember="..tostring(e).."["..tostring(es).."]")
        if ss ~= "UNAVAILABLE" and ss ~= "INIT" and s < 10 then
            farmScrap(token)
        else
            farmBlazeEmbers(token)
        end
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

    setStatus("Event ended -> Dragon Egg priority")
    task.wait(.35)

    -- Egg first: it is the time-sensitive/high-value reward and may create a
    -- physical Dragon Fruit that must be stored before any reset or portal.
    if not collectAssignedEgg(island, token) then return end
    if not isRunning(token) then return end
    collectBones(island, token)
    if not isRunning(token) then return end

    -- Final hard gate before ANY reset/portal. Reward replication is sometimes late;
    -- if a Dragon fruit appears here it must be stored first. On failure the account
    -- stops in place and never resets/leaves.
    setStatus("Reward safety check -> Dragon guard before reset")
    if not PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.PRE_RESET_GUARD_SECONDS, token) then return end
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
        _G.TeamConfig.StopReason = "NOT_IN_TEAM"
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
        "invScrapSource="..tostring((ITEM_TRACK[PHX.normalizeItemName("Scrap Metal")] or {}).Source or "?"),
        "dragonLoose="..tostring(#PHX.findPhysicalDragonFruits()),
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
TITLE.Text = "🌋 PREHISTORIC TEAM V2.9.3 NO-MOUSE DIALOG/INV PROBE | DELTA"

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
COUNTER_LABEL.Text = "Scrap ?/10 | Ember ?/15 | Magnet ? | Bones ? | DragonGuard ARMED"

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
    local scrap, scrapSource, scrapKnown = PHX.materialCountInfo("Scrap Metal")
    local ember, emberSource, emberKnown = PHX.materialCountInfo("Blaze Ember")
    PHX.ensureInventoryProbeIfUnknown()
    local magnet = inventoryCount("Volcanic Magnet")
    local bones = inventoryCount("Dinosaur Bones")
    local dragons = PHX.findPhysicalDragonFruits()
    local dragonText = "DragonGuard ARMED | physical:"..tostring(#dragons)
    if #dragons > 0 then
        local variant = PHX.dragonVariantFromTool(dragons[1])
        dragonText = "DRAGON PHYSICAL"..(variant and (" "..variant) or "").." -> STORE"
    elseif DRAGON_GUARD_STATE.Critical then
        dragonText = "DRAGON STORE CRITICAL"
    end

    local function srcTag(source)
        if source == "REMOTE_EXACT" then return "R" end
        if source == "STASH_GUI" then return "G" end
        if source == "REMOTE_DEEP" then return "D" end
        if source == "CRAFT_GUI" then return "C" end
        if source == "MEMORY" then return "M" end
        if source == "CRAFT_LOCAL" then return "L" end
        return "?"
    end
    local scrapText = scrapKnown and tostring(scrap) or "?"
    local emberText = emberKnown and tostring(ember) or "?"
    COUNTER_LABEL.Text = "Scrap "..scrapText.."/10["..srcTag(scrapSource).."] | Ember "..emberText.."/15["..srcTag(emberSource).."] | Magnet "..(magnet > 0 and "YES" or "NO").." | Bones "..tostring(bones).." | "..dragonText
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
        _G.TeamConfig.StopReason = "USER_BUTTON"
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
    _G.TeamConfig.StopReason = nil
    _G.TeamConfig.IsRunning = true
    START.Text = "⏹ STOP FULL AUTO"
    START.BackgroundColor3 = Color3.fromRGB(160,55,55)
    logLine("RUN", "START | role="..roleText().." master="..tostring(_G.TeamConfig.MasterName))
    setStatus("STARTED | "..roleText())

    task.spawn(function()
        while token == RUN_TOKEN and _G.TeamConfig.IsRunning do
            local ok, err = pcall(mainLoop, token)
            if not ok then
                logLine("RUN_FATAL", tostring(err))
                setStatus("RUN ERROR: "..tostring(err).." | retrying state machine")
                task.wait(.35)
            elseif token == RUN_TOKEN and _G.TeamConfig.IsRunning then
                -- Transient route/quest failures must NEVER flip the button back to START.
                logLine("RUN_RESTART", "mainLoop returned while still armed -> restart")
                setStatus("State machine returned -> auto retry")
                task.wait(.30)
            end
        end

        if token == RUN_TOKEN then
            logLine("RUN_END", "reason="..tostring(_G.TeamConfig.StopReason))
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
