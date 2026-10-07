--[[
    PREHISTORIC TEAM V2.11 (MAGNET V1.9 + SOLO V2.9 TEAM MERGE)
    Full standalone merge based on the supplied TEAM V2.10.4, MAGNET V1.9 and SOLO V2.9.

    IMPORTANT:
    - All 5 clients must run this same file and use the same MASTER_NAME.
    - MASTER = buys/drives MarineGrandBrigade + exclusively brings the shared Golem cluster.
    - SLAVES = passenger seats; all clients attack Golems before handling pressure.
    - Sailing requires the Master driver + at least three live Slave passengers.
    - WEBHOOK_URL is intentionally blank. Paste your Discord webhook in CONFIG.WEBHOOK_URL.
    - Same server, same five usernames in the same order, same MASTER on all five clients.
    - Each client has its own cache/generation; executor globals are not a cross-client channel.
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

-- One generation per client. Executing a newer copy retires the previous copy.
local ENV = (getgenv and getgenv()) or _G
ENV.PH_VOLCANO_GENERATION = (tonumber(ENV.PH_VOLCANO_GENERATION) or 0) + 1
local SCRIPT_GENERATION = ENV.PH_VOLCANO_GENERATION
ENV.PH_VOLCANO_KILL = false
function PHX.generationAlive()
    return PHX.Runtime ~= nil and PHX.Runtime.Alive
        and not ENV.PH_VOLCANO_KILL and ENV.PH_VOLCANO_GENERATION == SCRIPT_GENERATION
end

-- LIFECYCLE BOOTSTRAP BEGIN
-- Each executor/client owns its own runtime. Reloading this file retires that copy.
PHX.Runtime = {
    Alive = true, RunState = "Ready", Connections = {}, Tasks = {}, Tweens = {},
    LockOwners = {},
    HeldKeys = {}, HeldPointers = {}, HeldMouse = {}, Activity = {}, MovementObjects = {}, MovementConnections = {}, CollisionOverrides = setmetatable({}, {__mode="k"}),
}
if type(ENV.PHX_PreviousRuntime) == "table" and type(ENV.PHX_PreviousRuntime.destroy) == "function" then
    pcall(ENV.PHX_PreviousRuntime.destroy)
end
ENV.PHX_PreviousRuntime = PHX
PHX.Runtime.Tasks[coroutine.running()] = true -- cancel a superseded startup even while it yields

-- Busy flags belong to the coroutine that acquired them. Cancellation can skip
-- a yielding helper's normal cleanup, so retire only that owner's generation.
function PHX.acquireLock(container, key, name)
    if container[key] then return nil end
    local lock = {Container=container, Key=key, Name=name, Owner=coroutine.running()}
    PHX.Runtime.LockOwners[name] = lock
    container[key] = true
    return lock
end

function PHX.releaseLock(lock)
    if not lock or PHX.Runtime.LockOwners[lock.Name] ~= lock then return false end
    PHX.Runtime.LockOwners[lock.Name] = nil
    lock.Container[lock.Key] = false
    return true
end

function PHX.releaseRunnerLocks(thread)
    if not thread then return end
    for _,lock in pairs(PHX.Runtime.LockOwners) do
        if lock.Owner == thread then PHX.releaseLock(lock) end
    end
end

function PHX.connect(signal, callback)
    local connection = signal:Connect(function(...)
        if not PHX.generationAlive() then return end
        local thread = coroutine.running()
        PHX.Runtime.Tasks[thread] = true
        local ok,err = pcall(callback, ...)
        PHX.Runtime.Tasks[thread] = nil
        if not ok and PHX.generationAlive() then PHX.Runtime.LastError = tostring(err); warn("[PHX CALLBACK] "..tostring(err)) end
    end)
    PHX.Runtime.Connections[connection] = true
    return connection
end

function PHX.disconnect(connection)
    if connection then
        pcall(function() connection:Disconnect() end)
        PHX.Runtime.Connections[connection] = nil
        PHX.Runtime.MovementConnections[connection] = nil
    end
end

function PHX.spawn(callback, ...)
    if not PHX.generationAlive() then return nil end
    local thread = task.spawn(function(...)
        local ok,err = true,nil
        if PHX.generationAlive() then ok,err = pcall(callback, ...) end
        PHX.Runtime.Tasks[coroutine.running()] = nil
        if not ok and PHX.generationAlive() then PHX.Runtime.LastError = tostring(err); warn("[PHX TASK] "..tostring(err)) end
    end, ...)
    if coroutine.status(thread) ~= "dead" then PHX.Runtime.Tasks[thread] = true end
    return thread
end

function PHX.defer(callback, ...)
    if not PHX.generationAlive() then return nil end
    local thread = task.defer(function(...)
        local ok,err = true,nil
        if PHX.generationAlive() then ok,err = pcall(callback, ...) end
        PHX.Runtime.Tasks[coroutine.running()] = nil
        if not ok and PHX.generationAlive() then PHX.Runtime.LastError = tostring(err); warn("[PHX TASK] "..tostring(err)) end
    end, ...)
    PHX.Runtime.Tasks[thread] = true
    return thread
end

function PHX.isOwnGui(obj)
    local node = obj
    while node and node ~= PG do
        if node == PHX.CustomGui or node.Name == "PrehistoricTeamV1" or node.Name == "PrehistoricTeamGUI" or node.Name == "PrehistoricTeamBoot" then return true end
        node = node.Parent
    end
    return false
end

function PHX.gameGuiDescendants(base)
    local out = {}
    for _,obj in ipairs((base or PG):GetDescendants()) do
        if not PHX.isOwnGui(obj) then out[#out+1] = obj end
    end
    return out
end

function PHX.restoreMovement()
    if PHX.stopBoat then pcall(PHX.stopBoat) end
    if PHX.restoreTravel then pcall(PHX.restoreTravel) end
    if PHX.restoreGolemChanges then pcall(PHX.restoreGolemChanges) end
    for pointer in pairs(PHX.Runtime.HeldPointers or {}) do pcall(pointer.release) end
    PHX.Runtime.HeldPointers = {}
    for button,pointer in pairs(PHX.Runtime.HeldMouse or {}) do
        pcall(function() VirtualInputManager:SendMouseButtonEvent(pointer.X,pointer.Y,button,false,pointer.Target,pointer.Layer) end)
    end
    PHX.Runtime.HeldMouse = {}
    if PHX.UI and PHX.UI.setPassThrough then pcall(PHX.UI.setPassThrough,false) end
    for _,entry in ipairs(PHX.Runtime.InputPassthroughRestore or {}) do
        if entry.Object.Parent then
            pcall(function() entry.Object.Active=entry.Active end)
            if entry.Interactable ~= nil then pcall(function() entry.Object.Interactable=entry.Interactable end) end
        end
    end
    PHX.Runtime.InputPassthroughRestore=nil
    for tween in pairs(PHX.Runtime.Tweens) do pcall(function() tween:Cancel() end) end
    for connection in pairs(PHX.Runtime.MovementConnections) do PHX.disconnect(connection) end
    for object in pairs(PHX.Runtime.MovementObjects) do
        if object.Parent then pcall(function() object:Destroy() end) end
    end
    PHX.Runtime.MovementObjects = {}
    for key in pairs(PHX.Runtime.HeldKeys) do
        pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
    end
    PHX.Runtime.HeldKeys = {}
    for part,old in pairs(PHX.Runtime.CollisionOverrides) do
        if part.Parent then pcall(function() part.CanCollide = old end) end
    end
    PHX.Runtime.CollisionOverrides = setmetatable({}, {__mode="k"})
end

function PHX.destroy()
    if not PHX.Runtime.Alive then return end
    if PHX.stopAutomation then PHX.stopAutomation("UNLOAD") end
    PHX.Runtime.Alive = false
    if ENV.PH_VOLCANO_GENERATION == SCRIPT_GENERATION then ENV.PH_VOLCANO_KILL = true end
    PHX.restoreMovement()
    for connection in pairs(PHX.Runtime.Connections) do pcall(function() connection:Disconnect() end) end
    local current = coroutine.running()
    for thread in pairs(PHX.Runtime.Tasks) do
        if thread ~= current then pcall(task.cancel, thread) end
    end
    if PHX.CustomGui then pcall(function() PHX.CustomGui:Destroy() end) end
    for _,name in ipairs({"PrehistoricTeamV1", "PrehistoricTeamGUI", "PrehistoricTeamBoot"}) do
        local gui = PG:FindFirstChild(name)
        if gui then gui:Destroy() end
    end
    if ENV.PHX_PreviousRuntime == PHX then ENV.PHX_PreviousRuntime = nil end
end

-- Stop and generation retirement release every synthetic key that this copy held.
function PHX.keyEvent(down, key, repeated, target)
    if down and not PHX.generationAlive() then return end
    PHX.Runtime.HeldKeys[key] = down and true or nil
    return VirtualInputManager:SendKeyEvent(down, key, repeated or false, target or game)
end
function PHX.mouseEvent(x, y, button, down, target, layer)
    if down and not PHX.generationAlive() then return end
    PHX.Runtime.HeldMouse[button] = down and {X=x,Y=y,Target=target or game,Layer=layer or 0} or nil
    return VirtualInputManager:SendMouseButtonEvent(x,y,button,down,target or game,layer or 0)
end
-- LIFECYCLE BOOTSTRAP END

PHX.spawn(function()
    while PHX.Runtime.Alive do
        task.wait(.1)
        if not PHX.generationAlive() then PHX.destroy(); return end
    end
end)

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
BOOT_LABEL.Text = "VOLCANO TEAM V2.11\nLoading automation..."
BOOT_LABEL.ZIndex = 999999

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if not PHX.generationAlive() then return end
if not remotes then
    BOOT_LABEL.Text = "PREHISTORIC V2 ERROR\nReplicatedStorage.Remotes not found"
    return
end

local CommF = remotes:WaitForChild("CommF_", 20)
if not PHX.generationAlive() then return end
if not CommF then
    BOOT_LABEL.Text = "PREHISTORIC V2 ERROR\nCommF_ not found"
    return
end

BOOT_LABEL.Text = "VOLCANO TEAM V2.11\nLoaded core, building UI..."

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    MIN_SLAVES_TO_SAIL = 3, -- Master + at least three live passenger Slaves.
    WEBHOOK_USER_ID = "", -- Discord user ID; receive Dragon East/West mentions.
    PROTECT_HELD_DRAGON = true, -- A reset always requires confirmed Dragon storage.
    FRUIT_AUTO = {Enabled=false, AutoStore=true, TickSeconds=5, RandomInterval=5,
        MaxBackoff=300, StoreVerifySeconds=2},

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

    -- Team event is feedback driven: every client prioritizes all live Golems.
    -- Pressure work runs only when no Golem remains.
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
        NET_DISTANCE = 135,
        ATTACK_INTERVAL = 0.09,
        BURST_SECONDS = 1.0,
        HITBOX_SIZE = 72,
        BRING_DISTANCE_FROM_RELIC = 145,
        CLUSTER_RADIUS = 3,
        BRING_INTERVAL = 0.25,
        REBRING_DRIFT = 12,
        STALL_SECONDS = 4,
    },

    FOSSIL = {
        PLAYER_RELATIVE_TO_RELIC = CFrame.new(
            -2.257812, -49.921875, 27.808289,
            -0.235301, -0.001449, 0.971921,
            -0.971886, -0.008328, -0.235305,
            0.008435, -0.999964, 0.000552
        ),
        HOLD_SECONDS = 3.0,
        SAFE_SPEED = 125,
        SETTLE_TIME = 0.35,
        TEAM_WAIT_SECONDS = 120,
    },

    BONES = {ENABLED=true, SWEEP_SECONDS=2.5},

    EGG = {
        HOLD_SECONDS = 1.10, -- mobile click/touch hold; fresh inventory still verifies pickup
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
        HIDE_STATIC_MAP_VISUALS = false, -- map removal moved to a separate UI toggle
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
        CFrame.new(
            5431.108398, 1253.348877, 965.289429,
            0.295610, -0.000000, 0.955309,
            -0.000000, 1.000000, 0.000000,
            -0.955309, -0.000000, 0.295610
        ),
        CFrame.new(
            4976.212891, 1144.915039, 623.489624,
            -0.078839, 0.000000, -0.996887,
            0.000000, 1.000000, 0.000000,
            0.996887, 0.000000, -0.078839
        ),
        CFrame.new(
            5569.339355, 1264.950562, 702.382935,
            -0.431751, 0.000000, -0.901993,
            0.000000, 1.000000, 0.000000,
            0.901993, 0.000000, -0.431751
        ),
        CFrame.new(
            5312.936523, 1159.892822, 0.588688,
            -0.862379, 0.000000, -0.506264,
            0.000000, 1.000000, 0.000000,
            0.506264, 0.000000, -0.862379
        ),
        CFrame.new(
            5043.579590, 1149.748535, 180.001953,
            -0.936677, -0.000000, -0.350194,
            -0.000000, 1.000000, -0.000000,
            0.350194, -0.000000, -0.936677
        ),
        CFrame.new(
            4477.374023, 1356.148926, 26.291494,
            0.614400, 0.000000, 0.788995,
            -0.000000, 1.000000, -0.000000,
            -0.788995, 0.000000, 0.614400
        ),
        CFrame.new(
            4410.110840, 1384.577026, 306.693695,
            0.503457, 0.000000, 0.864020,
            -0.000000, 1.000000, -0.000000,
            -0.864020, 0.000000, 0.503457
        ),
    },
}

--==============================================================
-- STATE
--==============================================================

ENV.TeamConfig = ENV.TeamConfig or {}
ENV.TeamConfig.MasterName = CONFIG.MASTER_NAME
ENV.TeamConfig.IsMaster = LP.Name == CONFIG.MASTER_NAME
ENV.TeamConfig.IsRunning = false
ENV.TeamConfig.StopReason = nil

local RUN_TOKEN = 0
local STATUS_LABEL
local COUNTER_LABEL

local ITEM_TRACK = {}
local INVENTORY_CACHE = {Raw=nil, At=-math.huge}
local PICKUP_WATCHED = setmetatable({}, {__mode="k"})
ENV.__PH_DRAGON_GUARD_STATE = ENV.__PH_DRAGON_GUARD_STATE or {Busy=false, LastStored=nil, Critical=false}
local DRAGON_GUARD_STATE = ENV.__PH_DRAGON_GUARD_STATE
DRAGON_GUARD_STATE.Busy = false -- old runtime was retired before this declaration
local SAVE_CPU_APPLIED = false
PHX.MapVisualHidden = false
PHX.MapVisualBackup = setmetatable({}, {__mode = "k"})

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
    PHX.Runtime.Activity[#PHX.Runtime.Activity+1] = {Time=os.clock(), Tag=tostring(tag), Text=tostring(message)}
    if #PHX.Runtime.Activity > 120 then table.remove(PHX.Runtime.Activity, 1) end
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
    PHX.Runtime.Status = s
    print("[PH-V2] " .. s)

    if NIGHT.LastStatus ~= s or (os.clock() - NIGHT.LastStatusLogAt) > 20 then
        NIGHT.LastStatus = s
        NIGHT.LastStatusLogAt = os.clock()
        logLine("STATUS", s)
        noteProgress("STATUS:"..s)
    end
end

local function isRunning(token)
    return PHX.generationAlive() and ENV.TeamConfig.IsRunning and token == RUN_TOKEN
end

function PHX.sameName(a, b)
    return type(a) == "string" and type(b) == "string" and string.lower(a) == string.lower(b)
end

function PHX.playerByName(name)
    for _,player in ipairs(Players:GetPlayers()) do
        if PHX.sameName(player.Name, name) then return player end
    end
end

local function isTeamName(name)
    for _,member in ipairs(CONFIG.TEAM) do
        if PHX.sameName(name, member) then return true end
    end
    return false
end

local function teamIndex(name)
    for i,member in ipairs(CONFIG.TEAM) do
        if PHX.sameName(name, member) then return i end
    end
end

local function isMaster()
    return PHX.sameName(LP.Name, ENV.TeamConfig.MasterName)
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

    PHX.connect(h.Died, function()
        CHARACTER_EPOCH = CHARACTER_EPOCH + 1
        local r = c:FindFirstChild("HumanoidRootPart")
        logLine("DEATH", "pos="..tostring(r and r.Position or "nil").." status="..tostring(NIGHT.LastStatus))
        setStatus("DIED -> automation paused until respawn")
    end)
end

PHX.connect(LP.CharacterAdded, function(c)
    PHX.spawn(function()
        bindCharacter(c)
        c:WaitForChild("HumanoidRootPart", 10)
        task.wait(CONFIG.RESPAWN_SETTLE_DELAY)
        local rr = c:FindFirstChild("HumanoidRootPart")
        logLine("RESPAWN", "pos="..tostring(rr and rr.Position or "nil"))
        if ENV.TeamConfig.IsRunning then
            setStatus("RESPAWNED -> resuming current route")
        end
    end)
end)

if LP.Character then
    PHX.spawn(function() bindCharacter(LP.Character) end)
end

local function waitAlive(token)
    while PHX.generationAlive() do
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

-- Travel writes are short tweens only; collision changes exist only during travel.
PHX.TravelState = {Tween=nil, Parts=nil, BoatParts=nil, Boat=nil, BoatMoving=false}

function PHX.restoreTravel()
    local state = PHX.TravelState
    if state.Tween then pcall(function() state.Tween:Cancel() end) end
    state.Tween = nil
    for part, collidable in pairs(state.Parts or {}) do
        if part.Parent then pcall(function() part.CanCollide = collidable end) end
    end
    state.Parts = nil
    for part, collidable in pairs(state.BoatParts or {}) do
        if part.Parent then pcall(function() part.CanCollide = collidable end) end
    end
    state.BoatParts = nil
    state.BoatMoving = false
end

function PHX.travelAlive(token)
    if PHX.generationAlive and not PHX.generationAlive() then return false end
    return token == nil or isRunning(token)
end

function PHX.boatForSeat(seat)
    local boats = workspace:FindFirstChild("Boats")
    local current = seat
    while current and current ~= workspace do
        if boats and current.Parent == boats then return current end
        current = current.Parent
    end
end

function PHX.findDriverSeat(boat)
    if not boat then return nil end
    local named = boat:FindFirstChild("VehicleSeat", true)
    if named and named:IsA("VehicleSeat") then return named end
    return boat:FindFirstChildWhichIsA("VehicleSeat", true)
end

function PHX.stopBoat(boat)
    boat = boat or PHX.TravelState.Boat
    -- Passengers observe MASTER stopping; they never write boat steering/physics.
    if not isMaster() then return false end
    PHX.TravelState.BoatMoving = false
    if not boat or not boat.Parent then return true end
    local driver = PHX.findDriverSeat(boat)
    if driver then
        pcall(function()
            driver.Throttle = 0; driver.ThrottleFloat = 0
            driver.Steer = 0; driver.SteerFloat = 0
        end)
    end
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
    for part, collidable in pairs(PHX.TravelState.BoatParts or {}) do
        if part.Parent then pcall(function() part.CanCollide = collidable end) end
    end
    PHX.TravelState.BoatParts = nil
    return true
end

local function stopSit(token)
    local h = hum()
    if not h or h.Health <= 0 then return false end
    local seat = h.SeatPart
    if not seat then return true end
    local boat = PHX.boatForSeat(seat)
    if boat and boat.Parent then
        if isMaster() then
            PHX.stopBoat(boat)
        else
            -- Observe two stationary boat samples before a passenger jumps.
            local deadline, previous, stationary = os.clock()+7, boat:GetPivot().Position, 0
            while PHX.travelAlive(token) and boat.Parent and os.clock()<deadline do
                task.wait(.15)
                local position = boat:GetPivot().Position
                if (position-previous).Magnitude <= 1 then stationary=stationary+1 else stationary=0 end
                previous=position
                if stationary >= 2 then break end
                if h.Health<=0 or h~=hum() then return false end
            end
            if boat.Parent and stationary<2 then
                setStatus("DISEMBARK waiting MASTER to stop boat")
                return false
            end
        end
    end
    local deadline = os.clock()+4
    repeat
        if not PHX.travelAlive(token) or h.Health<=0 or h~=hum() then return false end
        pcall(function()
            h.Sit=false; h.Jump=true
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        if h.SeatPart==nil then return true end
        task.wait(.10)
    until os.clock()>=deadline
    setStatus("Seat weld still active; player travel paused")
    return h.SeatPart==nil
end
PHX.ensureSeatExit = stopSit

local function safeTween(targetCFrame, speed, token)
    if not targetCFrame or not PHX.travelAlive(token) then return false end
    local c,h,r,epoch = waitAlive(token)
    if not c or not h or not r or not stopSit(token) then return false end
    if PHX.StopHover then PHX.StopHover() end
    local state = PHX.TravelState
    if state.Tween then pcall(function() state.Tween:Cancel() end) end
    speed=math.clamp(tonumber(speed) or CONFIG.PLAYER_TWEEN_SPEED, 35, 220)
    local original, connection, tween = {}, nil, nil
    local interrupted, corrected, arrived = false, false, false
    local initialDistance=(r.Position-targetCFrame.Position).Magnitude
    local deadline=os.clock()+math.max(15,initialDistance/speed*3+10)
    local function clean()
        if tween then pcall(function() tween:Cancel() end) end
        if connection then connection:Disconnect() end
        for part, collidable in pairs(original) do
            if part.Parent then pcall(function() part.CanCollide=collidable end) end
        end
        if state.Parts==original then state.Parts=nil end
        if state.Tween==tween then state.Tween=nil end
        if r.Parent then pcall(function()
            r.AssemblyLinearVelocity=Vector3.zero
            r.AssemblyAngularVelocity=Vector3.zero
        end) end
    end
    local ok,err=pcall(function()
        for _,part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") then original[part]=part.CanCollide; part.CanCollide=false end
        end
        state.Parts=original
        connection=PHX.connect(RunService.Stepped, function()
            if not PHX.travelAlive(token) or h.Health<=0 or CHARACTER_EPOCH~=epoch or h.SeatPart~=nil then
                interrupted=true
                if tween then pcall(function() tween:Cancel() end) end
                return
            end
            for part in pairs(original) do if part.Parent then part.CanCollide=false end end
            if r.Parent then
                r.AssemblyLinearVelocity=Vector3.zero
                r.AssemblyAngularVelocity=Vector3.zero
            end
        end)
        while PHX.travelAlive(token) and os.clock()<deadline and not interrupted do
            if h.Health<=0 or not r.Parent or CHARACTER_EPOCH~=epoch or h.SeatPart~=nil then break end
            -- Never reuse a stale start after server replication changes our position.
            local from=r.CFrame
            local distance=(from.Position-targetCFrame.Position).Magnitude
            if distance<=1.2 then arrived=true; break end
            local length=math.min(distance,40)
            local goal=from:Lerp(targetCFrame,length/distance)
            local duration=math.max(length/speed,.06)
            local started=os.clock()
            corrected=false
            tween=TweenService:Create(r,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=goal})
            state.Tween=tween
            tween:Play()
            while PHX.travelAlive(token) and os.clock()-started<duration+.03 and not interrupted do
                RunService.Heartbeat:Wait()
                if not r.Parent or h.Health<=0 or CHARACTER_EPOCH~=epoch then interrupted=true; break end
                local expected=from.Position:Lerp(goal.Position,math.clamp((os.clock()-started)/duration,0,1))
                if (r.Position-expected).Magnitude>18 then
                    tween:Cancel(); corrected=true
                    -- A game portal transition must be observed by usePortal; never tween back across seas.
                    if PHX.PortalTravel and (r.Position-from.Position).Magnitude>200 then interrupted=true end
                    break
                end
            end
            tween:Cancel()
            if interrupted then break end
            if corrected then task.wait(.08) else task.wait(.02) end
        end
        if arrived and not interrupted and PHX.travelAlive(token) then
            -- Exact Fossil capture includes orientation. Finish with a short rotation tween at the live position.
            local turnStart=r.CFrame
            local aligned=CFrame.new(r.Position)*targetCFrame.Rotation
            local _,angle=turnStart:ToObjectSpace(aligned):ToAxisAngle()
            if math.abs(angle)>.001 then
                local duration=math.max(.12,math.abs(angle)/math.rad(180))
                local started=os.clock()
                tween=TweenService:Create(r,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=aligned})
                state.Tween=tween
                tween:Play()
                while PHX.travelAlive(token) and not interrupted and os.clock()-started<duration+.03 do
                    RunService.Heartbeat:Wait()
                    if h.Health<=0 or CHARACTER_EPOCH~=epoch or not r.Parent or h.SeatPart~=nil or
                        (r.Position-turnStart.Position).Magnitude>3 then interrupted=true end
                end
                tween:Cancel()
            end
        end
    end)
    clean()
    if not ok then logLine("MOVE_ERROR",tostring(err)); return false end
    return arrived and not interrupted and PHX.travelAlive(token)
end

local function highTween(targetCFrame, speed, token)
    local r=root()
    if not r or not targetCFrame then return false end
    if (r.Position-targetCFrame.Position).Magnitude<80 then return safeTween(targetCFrame,speed,token) end
    local highY=math.max(r.Position.Y,targetCFrame.Position.Y)+CONFIG.SAFE_ALTITUDE
    if not safeTween(CFrame.new(r.Position.X,highY,r.Position.Z),speed,token) then return false end
    if not safeTween(CFrame.new(targetCFrame.Position.X,highY,targetCFrame.Position.Z),speed,token) then return false end
    return safeTween(targetCFrame,speed,token)
end

--==============================================================
-- MOBILE HOLD INTERACTION (no keyboard emulation)
-- True means only that an input hold completed. The caller must verify the
-- event HUD or its own egg inventory before declaring the game action complete.
--==============================================================
do
    PHX.Runtime.HeldPointers = PHX.Runtime.HeldPointers or {}

    local function isOwnGui(object)
        if PHX.isOwnGui and PHX.isOwnGui(object) then return true end
        local custom = PHX.CustomGui or (PHX.UI and PHX.UI.Screen)
        return custom and (object == custom or object:IsDescendantOf(custom)) or false
    end

    local function visibleButton(button)
        if not button.Parent or not button:IsA("GuiButton") or isOwnGui(button) then return false end
        local size = button.AbsoluteSize
        if size.X < 2 or size.Y < 2 then return false end
        local center = button.AbsolutePosition + size / 2
        local node = button
        while node do
            if node:IsA("GuiObject") then
                if not node.Visible then return false end
                if node.ClipsDescendants then
                    local pos, rect = node.AbsolutePosition, node.AbsoluteSize
                    if center.X < pos.X or center.Y < pos.Y or center.X > pos.X + rect.X or center.Y > pos.Y + rect.Y then
                        return false
                    end
                end
            elseif node:IsA("ScreenGui") or node:IsA("BillboardGui") or node:IsA("SurfaceGui") then
                if not node.Enabled then return false end
            end
            node = node.Parent
        end
        local supported, interactable = pcall(function() return button.Interactable end)
        return not supported or interactable ~= false
    end

    local function associatedWith(object, target)
        return object and (object == target or object:IsDescendantOf(target)) or false
    end

    local function contextFor(button, target)
        local names, labels, associated = {}, {}, false
        local node, hops = button, 0
        while node and node ~= PG and node ~= CoreGui and hops < 7 do
            names[#names + 1] = string.lower(node.Name)
            if node:IsA("BillboardGui") or node:IsA("SurfaceGui") then
                associated = associated or associatedWith(node.Adornee, target)
            end
            -- A prompt label is commonly a sibling of its transparent button.
            if hops <= 1 or node:IsA("BillboardGui") then
                if node:IsA("TextLabel") or node:IsA("TextButton") then labels[#labels + 1] = string.lower(node.Text) end
                local descendants = node:GetDescendants()
                -- Never scrape a whole game menu to label an unrelated button.
                if #descendants > 100 then descendants = {} end
                for _, child in ipairs(descendants) do
                    if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Visible and not isOwnGui(child) then
                        labels[#labels + 1] = string.lower(child.Text)
                    elseif child:IsA("ObjectValue") and associatedWith(child.Value, target) then
                        associated = true
                    end
                end
            end
            node, hops = node.Parent, hops + 1
        end
        return table.concat(names, "/"), table.concat(labels, " "), associated
    end

    local function mobileButtonFor(target, egg)
        local candidates = {}
        for _, base in ipairs({PG, CoreGui}) do
            local ok, descendants = pcall(function() return base:GetDescendants() end)
            if ok then
                for _, object in ipairs(descendants) do
                    if object:IsA("GuiButton") then
                        local checked, score = pcall(function()
                            if not visibleButton(object) then return nil end
                            local path, text, associated = contextFor(object, target)
                            if path:find("inventory", 1, true) or path:find("backpack", 1, true)
                                or path:find("menu", 1, true) or path:find("attack", 1, true) or path:find("jump", 1, true) then return nil end
                            local ownText = object:IsA("TextButton") and string.lower(object.Text) or ""
                            if ownText:find("cancel", 1, true) or ownText:find("close", 1, true) or ownText:find("exit", 1, true) then return nil end
                            -- Never select generic attack/jump/mobile controls.
                            local namedTarget = egg and (text:find("egg", 1, true) or path:find("egg", 1, true))
                                or (not egg and (text:find("fossil", 1, true) or text:find("relic", 1, true)
                                    or path:find("fossil", 1, true) or path:find("relic", 1, true)))
                            if not associated and not namedTarget then return nil end
                            local prompt = path:find("prompt", 1, true) or path:find("interact", 1, true)
                                or text:find("hold", 1, true) or text:find("collect", 1, true)
                            -- A target's unrelated menu or inventory entry is not an interaction control.
                            if not associated and not prompt then return nil end
                            local value = associated and 100 or 0
                            if namedTarget then value = value + 30 end
                            if prompt then value = value + 10 end
                            if path:find("touch", 1, true) or path:find("mobile", 1, true) then value = value + 5 end
                            return value
                        end)
                        if checked and score then candidates[#candidates + 1] = {Button = object, Score = score} end
                    end
                end
            end
        end
        table.sort(candidates, function(a, b) return a.Score > b.Score end)
        -- Equally plausible controls without target association are unsafe to guess.
        if candidates[2] and candidates[1].Score == candidates[2].Score and candidates[1].Score < 100 then return nil end
        return candidates[1] and candidates[1].Button
    end

    local function worldPart(target)
        if target:IsA("BasePart") then return target end
        if target:IsA("Attachment") and target.Parent and target.Parent:IsA("BasePart") then return target.Parent end
        if target:IsA("Model") and target.PrimaryPart then return target.PrimaryPart end
        return target:FindFirstChildWhichIsA("BasePart", true)
    end

    local function restoreInput(record)
        if record.UiOwned and record.Ui and record.Ui.setPassThrough then
            pcall(record.Ui.setPassThrough, false)
        end
        for _, entry in ipairs(record.InputRestore or {}) do
            if entry.Object.Parent then
                pcall(function() entry.Object.Active = entry.Active end)
                if entry.Interactable ~= nil then pcall(function() entry.Object.Interactable = entry.Interactable end) end
            end
        end
        record.InputRestore = nil
    end

    local function passThrough(record)
        local ui = PHX.UI
        if ui and ui.setPassThrough then
            record.Ui = ui
            record.UiOwned = not ui.PassThrough
            if record.UiOwned then ui.setPassThrough(true) end
            return
        end
        -- Works before the dashboard is built as well. Only input flags change.
        record.InputRestore = {}
        for _, base in ipairs({PG, CoreGui}) do
            local ok, descendants = pcall(function() return base:GetDescendants() end)
            if ok then
                for _, object in ipairs(descendants) do
                    if object:IsA("GuiObject") and isOwnGui(object) then
                        local entry = {Object = object, Active = object.Active}
                        pcall(function() entry.Interactable = object.Interactable; object.Interactable = false end)
                        record.InputRestore[#record.InputRestore + 1] = entry
                        object.Active = false
                    end
                end
            end
        end
    end

    function PHX.holdInteraction(target, duration, token)
        if typeof(target) ~= "Instance" or not target.Parent then return false, "TARGET_UNAVAILABLE" end
        local character, humanoid, playerRoot = char(), hum(), root()
        local epoch = CHARACTER_EPOCH
        local function active()
            if not PHX.Runtime.Alive or (PHX.generationAlive and not PHX.generationAlive()) then return false end
            if token ~= nil and not isRunning(token) then return false end
            return CHARACTER_EPOCH == epoch and LP.Character == character and humanoid and humanoid.Parent
                and humanoid.Health > 0 and playerRoot and playerRoot.Parent
        end
        if not active() then return false, "INTERACTION_CANCELLED" end
        if PHX.Runtime.InteractionHold then return false, "INTERACTION_BUSY" end
        local record = {Released = false, Owner = coroutine.running()}
        PHX.Runtime.InteractionHold = record
        PHX.Runtime.HeldPointers[record] = true
        local mode, x, y, prompt, touchId
        local function release()
            if record.Released then return end
            record.Released = true
            if mode == "TOUCH" then
                pcall(function() VirtualInputManager:SendTouchEvent(touchId, Enum.UserInputState.End.Value, x, y) end)
            elseif mode == "MOUSE" then
                pcall(function() PHX.mouseEvent(x, y, 0, false, game, 0) end)
            elseif mode == "PROMPT" and prompt then
                pcall(function() prompt:InputHoldEnd() end)
            end
            restoreInput(record)
            PHX.Runtime.HeldPointers[record] = nil
            if PHX.Runtime.InteractionHold == record then PHX.Runtime.InteractionHold = nil end
        end
        record.release = release
        local function alive()
            return not record.Released and active()
        end
        local ok, attempted, reason = pcall(function()
            if not alive() then return false, "INTERACTION_CANCELLED" end
            local egg = string.lower(target.Name):find("egg", 1, true) ~= nil
            local ancestor = target.Parent
            for _ = 1, 3 do
                if not ancestor then break end
                if string.lower(ancestor.Name):find("egg", 1, true) then egg = true break end
                ancestor = ancestor.Parent
            end
            local seconds = math.clamp(tonumber(duration) or (egg and 1.0 or 3.0), 0.05, 15)
            local button = mobileButtonFor(target, egg)
            if button then
                local center = button.AbsolutePosition + button.AbsoluteSize / 2
                x, y = center.X, center.Y
            else
                -- Eggs with normal prompts can use Roblox's hold lifecycle directly.
                prompt = target:IsA("ProximityPrompt") and target or target:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    local promptPart = worldPart(prompt.Parent)
                    if promptPart and (playerRoot.Position - promptPart.Position).Magnitude > prompt.MaxActivationDistance + 1 then
                        return false, "PROMPT_OUT_OF_RANGE"
                    end
                    seconds = math.max(seconds, (tonumber(prompt.HoldDuration) or 0) + 0.12)
                    mode = "PROMPT"
                    prompt:InputHoldBegin()
                else
                    local part, camera = worldPart(target), workspace.CurrentCamera
                    if not part or not camera then return false, "INTERACTION_PROJECTION_UNAVAILABLE" end
                    local position = part.Position
                    -- Relic artwork may sit above its ground-level interaction area.
                    if not egg and math.abs(position.Y - playerRoot.Position.Y) > 12 then
                        position = playerRoot.Position + playerRoot.CFrame.LookVector * 6
                    end
                    local point, onScreen = camera:WorldToViewportPoint(position)
                    if not onScreen or point.Z <= 0 then return false, "INTERACTION_TARGET_OFFSCREEN" end
                    x, y = point.X, point.Y
                end
            end
            if not alive() then return false, "INTERACTION_CANCELLED" end
            if not mode then
                local camera = workspace.CurrentCamera
                local viewport = camera and camera.ViewportSize
                if not viewport or x < 0 or y < 0 or x >= viewport.X or y >= viewport.Y then return false, "INTERACTION_POINTER_OFFSCREEN" end
                passThrough(record)
                if not alive() then return false, "INTERACTION_CANCELLED" end
                local touchEnabled = false
                pcall(function() touchEnabled = game:GetService("UserInputService").TouchEnabled end)
                if touchEnabled then
                    PHX.Runtime.TouchSerial = (PHX.Runtime.TouchSerial or 0) + 1
                    touchId = PHX.Runtime.TouchSerial
                    mode = "TOUCH"
                    local sent = pcall(function() VirtualInputManager:SendTouchEvent(touchId, Enum.UserInputState.Begin.Value, x, y) end)
                    if not sent then
                        pcall(function() VirtualInputManager:SendTouchEvent(touchId, Enum.UserInputState.End.Value, x, y) end)
                        mode = nil
                    end
                end
                if not mode then
                    mode = "MOUSE"
                    local sent = pcall(function() PHX.mouseEvent(x, y, 0, true, game, 0) end)
                    if not sent then return false, "POINTER_INPUT_UNAVAILABLE" end
                end
            end
            local deadline = os.clock() + seconds
            while os.clock() < deadline do
                if not alive() then return false, "INTERACTION_CANCELLED" end
                task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
                if not alive() then return false, "INTERACTION_CANCELLED" end
            end
            return true, mode .. "_HOLD_ATTEMPT_COMPLETED"
        end)
        release()
        if not ok then return false, "INTERACTION_INPUT_ERROR: " .. tostring(attempted) end
        return attempted == true, reason
    end
end

local function resetCharacter(token)
    -- Guard can yield while storing. Check again at the exact kill boundary afterwards.
    if type(PHX.safeResetGuard)~="function" or not PHX.safeResetGuard(token) then return false end
    if not PHX.travelAlive(token) then return false end
    local previous=LP.Character
    local h=hum()
    if DRAGON_GUARD_STATE.Critical or type(PHX.findPhysicalDragonFruits)~="function" or
        #PHX.findPhysicalDragonFruits()>0 then
        setStatus("Reset blocked: physical Dragon storage not confirmed")
        return false
    end
    if h and h.Health>0 then h.Health=0 end
    while PHX.travelAlive(token) do
        local c=LP.Character
        local hh=c and c:FindFirstChildOfClass("Humanoid")
        local rr=c and c:FindFirstChild("HumanoidRootPart")
        if c and c~=previous and hh and rr and hh.Health>0 then
            bindCharacter(c)
            task.wait(CONFIG.RESPAWN_SETTLE_DELAY)
            return PHX.travelAlive(token)
        end
        task.wait(.15)
    end
    return false
end

-- Defined later after portal helpers are available.
local resetBackToTiki

--==============================================================
-- WEBHOOK
--==============================================================

-- Webhook credentials stay on this client. No request is made unless configured.
function PHX.validWebhookConfig(url, userId)
    url = type(url)=="string" and url:match("^%s*(.-)%s*$") or ""
    userId = type(userId)=="string" and userId:match("^%s*(.-)%s*$") or tostring(userId or "")
    if url ~= "" and not (url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$")
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$")) then
        return false, "URL cần là Discord webhook https://discord.com/api/webhooks/..."
    end
    if userId ~= "" and (not userId:match("^%d+$") or #userId < 15 or #userId > 22) then
        return false, "Discord user ID cần là 15–22 chữ số"
    end
    return true, url, userId
end

function PHX.setWebhook(url, userId)
    local ok, checkedUrl, checkedId = PHX.validWebhookConfig(url, userId)
    if not ok then return false, checkedUrl end
    CONFIG.WEBHOOK_URL, CONFIG.WEBHOOK_USER_ID = checkedUrl, checkedId
    return true, checkedUrl == "" and "Webhook đã tắt" or "Đã lưu webhook và ID ping trên client này"
end

function PHX.webhookPayload(title, description, fields, ping)
    local userId = tostring(CONFIG.WEBHOOK_USER_ID or "")
    local mention = ping and userId:match("^%d+$") and #userId >= 15 and #userId <= 22
    return {
        username = "Volcano Team",
        content = mention and ("<@"..userId..">") or "",
        allowed_mentions = {parse={}, users=mention and {userId} or {}},
        embeds = {{
            title=tostring(title), description=tostring(description or ""), fields=fields or {},
            footer={text="Volcano Team V2.11 | "..LP.Name}, timestamp=DateTime.now():ToIsoDate(),
        }},
    }
end

local function sendWebhook(title, description, fields, ping)
    if not PHX.generationAlive() then return false end
    if tostring(title):upper():find("PREHISTORIC ISLAND",1,true) and not isMaster() then return false end
    local valid,url = PHX.validWebhookConfig(CONFIG.WEBHOOK_URL,CONFIG.WEBHOOK_USER_ID)
    if not valid or url == "" then return false end
    local req = (syn and syn.request) or http_request or request
    if type(req) ~= "function" then PHX.Runtime.WebhookState="HTTP_UNAVAILABLE"; return false end
    local payload = HttpService:JSONEncode(PHX.webhookPayload(title,description,fields,ping == true))
    PHX.Runtime.WebhookState="QUEUED"
    PHX.spawn(function()
        if not PHX.generationAlive() then return end
        local ok,response = pcall(req, {Url=url,Method="POST",Headers={["Content-Type"]="application/json"},Body=payload})
        local status = ok and type(response)=="table" and tonumber(response.StatusCode or response.Status) or nil
        local confirmed = status and status >= 200 and status < 300
        PHX.Runtime.WebhookState = confirmed and "SENT" or (status and ("HTTP_"..status) or "UNCONFIRMED")
        if not confirmed then logLine("WEBHOOK", "Delivery "..PHX.Runtime.WebhookState) end
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
ENV.__PH_MATERIAL_CACHE = ENV.__PH_MATERIAL_CACHE or {}
ENV.__PH_MATERIAL_CACHE[LP.Name] = ENV.__PH_MATERIAL_CACHE[LP.Name] or {}
PHX.MaterialPersistent = ENV.__PH_MATERIAL_CACHE[LP.Name]

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

    local inventoryLock=nil
    if PHX.acquireLock then
        inventoryLock=PHX.acquireLock(PHX,"InventoryBusy","inventory")
        if not inventoryLock then return INVENTORY_CACHE.Raw or {} end
    else PHX.InventoryBusy=true end
    local ok, inv = pcall(function()
        return CommF:InvokeServer("getInventory")
    end)
    if inventoryLock then PHX.releaseLock(inventoryLock) else PHX.InventoryBusy=false end

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
function PHX.guiTextNormalized(obj)
    local txt = ""
    pcall(function() txt = tostring(obj.Text or "") end)
    txt = txt:gsub("<.->", "")
    txt = txt:gsub("&nbsp;", " ")
    return PHX.normalizeItemName(txt)
end

function PHX.guiMaterialCount(itemName)
    local wanted = PHX.normalizeItemName(itemName)
    local best, bestScore = nil, -math.huge

    local function numericText(o)
        if not (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then return nil end
        local raw = tostring(o.Text or ""):gsub("<.->", ""):gsub(",", "")
        local n = tonumber(raw:match("^%s*(%d+)%s*$"))
        if n and n >= 0 and n <= 999999 then return n end
        return nil
    end

    for _,label in ipairs(PHX.gameGuiDescendants(PG)) do
        if (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox"))
            and PHX.guiTextNormalized(label) == wanted then
            local okCenter, center = pcall(function()
                return label.AbsolutePosition + label.AbsoluteSize/2
            end)
            local ancestor = label.Parent
            local depth = 0
            while ancestor and ancestor ~= PG and depth < 10 do
                if ancestor:IsA("GuiObject") then
                    for _,cand in ipairs(ancestor:GetDescendants()) do
                        if cand ~= label then
                            local n = numericText(cand)
                            if n ~= nil then
                                local score = 1000 - depth * 60
                                local nm = string.lower(cand.Name or "")
                                if nm:find("count",1,true) or nm:find("amount",1,true) or nm:find("quantity",1,true) or nm:find("owned",1,true) then
                                    score = score + 500
                                end
                                if okCenter then
                                    local ok2,p2 = pcall(function() return cand.AbsolutePosition + cand.AbsoluteSize/2 end)
                                    if ok2 then score = score - math.min(700, (p2-center).Magnitude) end
                                end
                                if score > bestScore then
                                    best, bestScore = n, score
                                end
                            end
                        end
                    end
                end
                ancestor = ancestor.Parent
                depth = depth + 1
            end
        end
    end
    return best
end

function PHX.buttonAncestor(o)
    local p = o
    for _=1,12 do
        if not p or p == PG then break end
        if p:IsA("TextButton") or p:IsA("ImageButton") then return p end
        p = p.Parent
    end
    return nil
end

function PHX.findStashButton()
    local best, bestScore = nil, -math.huge
    for _,o in ipairs(PHX.gameGuiDescendants(PG)) do
        if o:IsA("GuiObject") then
            local name = string.lower(tostring(o.Name or ""))
            local txt = ""
            if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
                txt = PHX.guiTextNormalized(o)
            end
            local hit = name:find("stash",1,true) ~= nil or txt == "stash" or txt:find("stash",1,true) ~= nil
            if hit then
                local b = (o:IsA("TextButton") or o:IsA("ImageButton")) and o or PHX.buttonAncestor(o)
                if b then
                    local score = 0
                    if txt == "stash" then score = score + 1000 end
                    if name:find("stash",1,true) then score = score + 700 end
                    pcall(function() if b.Visible then score = score + 100 end end)
                    if score > bestScore then best,bestScore = b,score end
                end
            end
        end
    end
    return best
end

function PHX.stashLooksOpen()
    local materialHits = 0
    local allHits = 0
    for _,o in ipairs(PHX.gameGuiDescendants(PG)) do
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            local t = PHX.guiTextNormalized(o)
            if t == "scrap metal" or t == "blaze ember" or t == "dinosaur bones" or t == "volcanic magnet" then
                materialHits = materialHits + 1
            elseif t:match("^all%s*%(%d+%)$") or t == "items" then
                allHits = allHits + 1
            end
        end
    end
    return materialHits > 0 or allHits >= 2
end

function PHX.findVisibleStashClose()
    for _,o in ipairs(PHX.gameGuiDescendants(PG)) do
        if o:IsA("TextButton") or o:IsA("ImageButton") then
            local nm = string.lower(tostring(o.Name or ""))
            local tx = ""
            if o:IsA("TextButton") then tx = string.lower(tostring(o.Text or "")) end
            if (nm:find("close",1,true) or tx == "x" or tx == "×") then
                local vis = false
                pcall(function() vis = o.Visible end)
                if vis then return o end
            end
        end
    end
    return nil
end


function PHX.signalGuiButton(btn)
    if not btn then return false end
    local fired = false
    local function hit(sig)
        if getconnections then
            local ok, cons = pcall(function() return getconnections(sig) end)
            if ok and type(cons) == "table" then
                for _,c in ipairs(cons) do
                    if c.Fire then pcall(function() c:Fire() end); fired = true
                    elseif c.Function then pcall(function() c.Function() end); fired = true end
                end
            end
        end
        if firesignal then
            local ok = pcall(function() firesignal(sig) end)
            if ok then fired = true end
        end
    end
    pcall(function() hit(btn.Activated) end)
    pcall(function() hit(btn.MouseButton1Click) end)
    task.wait(.08)
    return fired
end


-- V2.10: exact Stash reader learned from PH_FULL_PROBE.
-- The live UI exposes:
--   Inventory.Inventory.RightCard.ItemCard.Title.Text
--   Inventory.Inventory.RightCard.ItemCard.Display.Footer.CountRibbon.Count
-- We select Stash tiles through GUI signals and read that authoritative pair.
function PHX.inventoryUiRoot()
    local top = PG:FindFirstChild("Inventory")
    if not top then return nil end
    return top:FindFirstChild("Inventory")
end


function PHX.readSelectedStashCard()
    local inv = PHX.inventoryUiRoot()
    local right = inv and inv:FindFirstChild("RightCard")
    local card = right and right:FindFirstChild("ItemCard")
    if not card or not PHX.guiVisible(card) then return nil,nil,nil end
    local title = card:FindFirstChild("Title")
    title = title and title:FindFirstChild("Text")
    local display = card:FindFirstChild("Display")
    local footer = display and display:FindFirstChild("Footer")
    local ribbon = footer and footer:FindFirstChild("CountRibbon")
    local count = ribbon and ribbon:FindFirstChild("Count")
    local header = display and display:FindFirstChild("Header")
    local category = header and header:FindFirstChild("Category")
    if not title or not count or not PHX.guiVisible(title) or not PHX.guiVisible(count) then
        return nil,nil,nil
    end
    local raw = tostring(count.Text or ""):gsub(",", "")
    return tostring(title.Text or ""), tonumber(raw:match("(%d+)")), category and tostring(category.Text or "") or ""
end

function PHX.stashTileClickTarget(tile)
    if not tile then return nil end
    if tile:IsA("TextButton") or tile:IsA("ImageButton") then return tile end
    for _,o in ipairs(tile:GetDescendants()) do
        if o:IsA("TextButton") or o:IsA("ImageButton") then
            return o
        end
    end
    return nil
end


-- Stash is the material authority. Readers and UI never reopen Items automatically.
PHX.StashBaselineReady = false
PHX.StashSyncBusy = false
PHX.StashLastError = nil
PHX.PickupSuppress = {}
PHX.MaterialNames = {"Scrap Metal", "Blaze Ember", "Volcanic Magnet"}

function PHX.inputPassthrough(action)
    local ui = PHX.UI
    if ui and ui.setPassThrough then
        local wasPassthrough = ui.PassThrough == true
        if not wasPassthrough then ui.setPassThrough(true) end
        local ok,result = xpcall(action,function(err) return tostring(err) end)
        if not wasPassthrough then ui.setPassThrough(false) end
        return ok,result
    end
    local saved = {}
    PHX.Runtime.InputPassthroughRestore=saved
    local own = PHX.CustomGui or PG:FindFirstChild("PrehistoricTeamUI") or PG:FindFirstChild("PrehistoricTeamGUI")
    if own then
        for _,o in ipairs(own:GetDescendants()) do
            if o:IsA("GuiObject") then
                local state = {Object=o, Active=o.Active}
                pcall(function() state.Interactable=o.Interactable; o.Interactable=false end)
                o.Active = false
                saved[#saved+1] = state
            end
        end
    end
    local ok, result = xpcall(action, function(err) return tostring(err) end)
    for _,state in ipairs(saved) do
        local o = state.Object
        if o and o.Parent then
            pcall(function() o.Active=state.Active end)
            if state.Interactable ~= nil then pcall(function() o.Interactable=state.Interactable end) end
        end
    end
    if PHX.Runtime.InputPassthroughRestore == saved then PHX.Runtime.InputPassthroughRestore=nil end
    return ok, result
end

PHX.withGuiPassThrough=PHX.inputPassthrough

function PHX.inputClick(button)
    if not button or not PHX.guiVisible(button) then return false end
    local p,z = button.AbsolutePosition,button.AbsoluteSize
    if z.X <= 0 or z.Y <= 0 then return false end
    local inset = select(1,game:GetService("GuiService"):GetGuiInset())
    local top = button:FindFirstAncestorWhichIsA("ScreenGui")
    local x,y = p.X+z.X/2,p.Y+z.Y/2
    if not top or not top.IgnoreGuiInset then x=x+inset.X; y=y+inset.Y end
    local ok = PHX.inputPassthrough(function()
        PHX.mouseEvent(x,y,0,true,game,0)
        task.wait(.07)
        PHX.mouseEvent(x,y,0,false,game,0)
    end)
    task.wait(.10)
    return ok
end

-- Exactly one activation: never fire Activated and MouseButton1Click together.
-- NPC option instances can be reused for the next menu during the first callback.
function PHX.activateOnce(button)
    if not button or not PHX.guiVisible(button) then return false end
    if type(getconnections) == "function" then
        for _,signal in ipairs({button.Activated,button.MouseButton1Click}) do
            local ok, connections = pcall(function() return getconnections(signal) end)
            if ok and type(connections) == "table" then
                for _,connection in ipairs(connections) do
                    local fired = false
                    if connection.Fire then fired=pcall(function() connection:Fire() end)
                    elseif connection.Function then fired=pcall(function() connection.Function() end) end
                    if fired then task.wait(.10); return true end
                end
            end
        end
    end
    if type(firesignal) == "function" then
        local fired = pcall(function() firesignal(button.Activated) end)
        if fired then task.wait(.10); return true end
    end
    return PHX.inputClick(button)
end

function PHX.waitGui(predicate, seconds)
    local untilAt = os.clock()+(seconds or 1)
    repeat
        if PHX.generationAlive and not PHX.generationAlive() then return false end
        local ok,result = pcall(predicate)
        if ok and result then return true end
        task.wait(.04)
    until os.clock() >= untilAt
    return false
end

function PHX.inventoryActuallyOpen()
    local inv = PHX.inventoryUiRoot()
    if not inv or not PHX.guiVisible(inv) then return false end
    local main = inv:FindFirstChild("Main")
    local header = main and main:FindFirstChild("Header")
    local title = header and header:FindFirstChild("Title")
    return not title or (PHX.guiVisible(title) and PHX.normalizeItemName(title.Text) == "items")
end

function PHX.itemsHudButton()
    local hudRoot = PG:FindFirstChild("HUDRoot")
    local f = hudRoot and hudRoot:FindFirstChild("Frame")
    local hud = f and f:FindFirstChild("HUD")
    local col = hud and hud:FindFirstChild("LowerLeftColumn")
    local menu = col and col:FindFirstChild("Menu")
    local items = menu and menu:FindFirstChild("Items")
    return PHX.stashTileClickTarget(items)
end

function PHX.inventoryCloseButton()
    local inv = PHX.inventoryUiRoot()
    if not inv then return nil end
    for _,o in ipairs(inv:GetDescendants()) do
        if (o:IsA("TextButton") or o:IsA("ImageButton")) and PHX.guiVisible(o) then
            local n = PHX.normalizeItemName(o.Name)
            local t = o:IsA("TextButton") and PHX.normalizeItemName(o.Text) or ""
            if n:find("close",1,true) or n:find("exit",1,true) or t == "x" or t == "×" or t == "close" then
                return o
            end
        end
    end
    return nil
end

function PHX.inventorySearchBox()
    local inv = PHX.inventoryUiRoot()
    if not inv then return nil end
    for _,o in ipairs(inv:GetDescendants()) do
        if o:IsA("TextBox") and PHX.guiVisible(o) then
            local ph,nm = PHX.normalizeItemName(o.PlaceholderText),PHX.normalizeItemName(o.Name)
            if ph:find("search",1,true) or nm:find("search",1,true) then return o end
        end
    end
    return nil
end

function PHX.stashGrid()
    local inv = PHX.inventoryUiRoot()
    local main = inv and inv:FindFirstChild("Main")
    local page = main and main:FindFirstChild("PageContent")
    return page and page:FindFirstChild("TileGrid")
end

function PHX.openStashPageExact()
    local state = {wasOpen=PHX.inventoryActuallyOpen()}
    if not state.wasOpen then
        local items = PHX.itemsHudButton()
        if not items or not PHX.guiVisible(items) then
            local hudRoot=PG:FindFirstChild("HUDRoot")
            local f=hudRoot and hudRoot:FindFirstChild("Frame")
            local hud=f and f:FindFirstChild("HUD")
            local col=hud and hud:FindFirstChild("LowerLeftColumn")
            local menu=col and col:FindFirstChild("Menu")
            local toggle=menu and menu:FindFirstChild("Menu")
            if toggle then
                PHX.activateOnce(toggle)
                PHX.waitGui(function()
                    local i=PHX.itemsHudButton(); return i and PHX.guiVisible(i)
                end,.8)
            end
            items=PHX.itemsHudButton()
        end
        if not items or not PHX.guiVisible(items) then return false,state,"ITEMS_BUTTON_MISSING" end
        PHX.activateOnce(items)
        if not PHX.waitGui(PHX.inventoryActuallyOpen,1.3) then
            PHX.inputClick(items)
            if not PHX.waitGui(PHX.inventoryActuallyOpen,1.3) then return false,state,"ITEMS_NOT_OPEN" end
        end
    end
    local inv = PHX.inventoryUiRoot()
    local main = inv and inv:FindFirstChild("Main")
    local nav = main and main:FindFirstChild("NavigationRail")
    local category = nav and nav:FindFirstChild("Category4")
    local button = PHX.stashTileClickTarget(category)
    if not button then return false,state,"STASH_CATEGORY4_MISSING" end
    local search=PHX.inventorySearchBox()
    state.search=search
    state.searchText=search and search.Text or nil
    if search then search.Text=""; task.wait(.16) end
    -- v1.9's confirmed physical Items/Stash path: preserve UI visibility and bypass input interception.
    PHX.inputClick(button)
    local populated=PHX.waitGui(function()
        local grid=PHX.stashGrid()
        if not grid or not PHX.guiVisible(grid) then return false end
        for _,tile in ipairs(grid:GetChildren()) do
            if tostring(tile.Name):match("^Tile%-") and tile:FindFirstChild("Count",true) then return true end
        end
        return false
    end,1.5)
    if not populated then
        PHX.activateOnce(button)
        populated=PHX.waitGui(function()
            local grid=PHX.stashGrid()
            if not grid or not PHX.guiVisible(grid) then return false end
            for _,tile in ipairs(grid:GetChildren()) do
                if tostring(tile.Name):match("^Tile%-") and tile:FindFirstChild("Count",true) then return true end
            end
            return false
        end,1.5)
    end
    if not populated then return false,state,"STASH_NOT_POPULATED" end
    if not PHX.inventorySearchBox() then return false,state,"STASH_SEARCH_MISSING" end
    return true,state,"STASH_OPEN"
end

function PHX.restoreInventoryUiState(state)
    if not state then return end
    if state.search and state.search.Parent and state.searchText ~= nil then state.search.Text=state.searchText end
    if state.wasOpen or not PHX.inventoryActuallyOpen() then return end
    local close=PHX.inventoryCloseButton()
    local items=PHX.itemsHudButton()
    local button=close or items
    if button then
        PHX.activateOnce(button)
        if not PHX.waitGui(function() return not PHX.inventoryActuallyOpen() end,.7) then PHX.inputClick(button) end
    end
end

function PHX.readStashItemExact(itemName)
    local search=PHX.inventorySearchBox()
    local grid=PHX.stashGrid()
    if not search or not grid then return nil,"SEARCH_OR_GRID_MISSING" end
    search.Text=itemName
    task.wait(.32)
    local tiles={}
    for _,tile in ipairs(grid:GetChildren()) do
        if tostring(tile.Name):match("^Tile%-") then
            local button=PHX.stashTileClickTarget(tile)
            if button and PHX.guiVisible(button) then tiles[#tiles+1]=button end
        end
    end
    if #tiles == 0 then
        -- Only a populated Stash + exact search with a stable empty result proves zero.
        task.wait(.18)
        if PHX.normalizeItemName(search.Text) ~= PHX.normalizeItemName(itemName) then return nil,"SEARCH_CHANGED" end
        for _,tile in ipairs(grid:GetChildren()) do
            if tostring(tile.Name):match("^Tile%-") then return nil,"FILTER_NOT_STABLE" end
        end
        return 0,"STASH_ABSENT"
    end
    for _,button in ipairs(tiles) do
        PHX.activateOnce(button)
        local got=nil
        local matched=PHX.waitGui(function()
            local title,count=PHX.readSelectedStashCard()
            if PHX.normalizeItemName(title) == PHX.normalizeItemName(itemName) and count ~= nil then got=count; return true end
        end,.65)
        if not matched then
            PHX.inputClick(button)
            matched=PHX.waitGui(function()
                local title,count=PHX.readSelectedStashCard()
                if PHX.normalizeItemName(title) == PHX.normalizeItemName(itemName) and count ~= nil then got=count; return true end
            end,.65)
        end
        if matched then return math.max(0,math.floor(got)),"STASH_EXACT" end
    end
    return nil,"FILTER_RESULT_MISMATCH"
end

function PHX.authoritativeStash(force, reason)
    if PHX.StashSyncBusy then return false,"SYNC_BUSY" end
    if PHX.StashBaselineReady and not force then return true,"STASH_CACHED" end
    local lock=nil
    if PHX.acquireLock then
        lock=PHX.acquireLock(PHX,"StashSyncBusy","stash")
        if not lock then return false,"SYNC_BUSY" end
    else PHX.StashSyncBusy=true end
    local state,counts,sources=nil,{},{}
    local success,why=false,"UNKNOWN"
    local ok,err=xpcall(function()
        local opened,uiState,openWhy=PHX.openStashPageExact()
        state=uiState
        if not opened then why=openWhy; return end
        for _,name in ipairs(PHX.MaterialNames) do
            local count,source=PHX.readStashItemExact(name)
            if count == nil then why=name..":"..source; return end
            counts[name],sources[name]=count,source
        end
        -- Atomic replacement: postcraft repairs all three counters from real cards.
        for _,name in ipairs(PHX.MaterialNames) do PHX.setKnownMaterial(name,counts[name],sources[name]) end
        PHX.StashBaselineReady=true
        if PHX.updateMagnetCache then PHX.updateMagnetCache(counts["Volcanic Magnet"],"STASH_EXACT") end
        PHX.StashLastError=nil
        success,why=true,"STASH_VERIFIED"
    end,function(e) return tostring(e) end)
    pcall(function() PHX.restoreInventoryUiState(state) end)
    if lock then PHX.releaseLock(lock) else PHX.StashSyncBusy=false end
    if not ok then why="ERROR:"..tostring(err); success=false end
    if not success then PHX.StashLastError=why end
    logLine(success and "STASH_SYNC" or "STASH_SYNC_FAIL",tostring(reason or "baseline").." | "..tostring(why))
    return success,why
end

function PHX.cachedMaterialCount(itemName)
    local t=ITEM_TRACK[PHX.normalizeItemName(itemName)]
    if t and t.Known then return math.max(0,tonumber(t.Server) or 0),t.Source or "CACHE" end
    return nil,"UNAVAILABLE"
end

function PHX.checkMagnetFromStash(force)
    local ok,reason=PHX.authoritativeStash(force == true,force and "explicit magnet refresh" or "startup magnet")
    if not ok then return nil,reason end
    return PHX.cachedMaterialCount("Volcanic Magnet")
end

function PHX.scanStashTilesExact()
    local found=0
    for _,name in ipairs(PHX.MaterialNames) do
        local count,source=PHX.readStashItemExact(name)
        if count ~= nil then PHX.setKnownMaterial(name,count,source); found=found+1 end
    end
    return found
end

function PHX.refreshMaterialViaStash(force)
    return PHX.authoritativeStash(force == true,"material sync")
end

PHX.CounterSyncBusy=false
function PHX.forceCounterSync(force)
    -- Automatic legacy/UI calls are cache-only after startup, including respawn.
    if force == true then return PHX.authoritativeStash(true,"manual sync") end
    if PHX.StashBaselineReady then return true end
    if not ENV.TeamConfig.IsRunning then return false end
    return PHX.authoritativeStash(false,"startup")
end

function PHX.inventoryHasMaterialSchema(inv)
    if type(inv) ~= "table" then return false end
    for _,entry in pairs(inv) do
        if type(entry)=="table" and PHX.normalizeItemName(entry.Type or entry.type)=="material" then return true end
    end
    return false
end

function PHX.serverInventoryCount(itemName, _force)
    -- getInventory / hidden templates / getgc stores never override Stash material counts.
    return PHX.cachedMaterialCount(itemName)
end

-- V2.9.5 runtime inventory probe. When material schema is unknown we dump the
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
        "===== PREHISTORIC INVENTORY PROBE V2.10 =====",
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
    for _,o in ipairs(PHX.gameGuiDescendants(PG)) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and visibleGui(o) then
            local txt = tostring(o.Text or "")
            local l = string.lower(txt)
            if l:find("scrap",1,true) or l:find("ember",1,true) or l:find("magnet",1,true) or l:find("bone",1,true)
                or txt:match("^%s*%d+%s*$") then
                lines[#lines+1] = o:GetFullName().." | text="..string.format("%q",txt)
            end
        end
    end

    local path = "PH_InventoryProbe_"..LP.Name.."_V294.txt"
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
        PHX.spawn(function() PHX.dumpInventoryProbe("material_count_unknown") end)
    end
end


function PHX.trackerFor(itemName)
    local key=PHX.normalizeItemName(itemName)
    local t=ITEM_TRACK[key]
    if not t then
        t={Server=0,Optimistic=0,OptimisticUntil=0,Source="UNAVAILABLE",Known=false,ObservedGain=0}
        ITEM_TRACK[key]=t
    end
    return t,key
end

local function inventoryCount(itemName, _force)
    local count=PHX.cachedMaterialCount(itemName)
    return count or 0
end

function PHX.materialCountInfo(itemName, _force)
    local count,source=PHX.cachedMaterialCount(itemName)
    return count or 0,source,count ~= nil
end

function PHX.setKnownMaterial(itemName,count,source)
    count=tonumber(count)
    if count == nil then return false end
    local t=PHX.trackerFor(itemName)
    count=math.max(0,math.floor(count))
    t.Server,t.Optimistic,t.OptimisticUntil=count,count,0
    t.Source,t.Known=source or "STASH_EXACT",true
    PHX.persistMaterial(itemName,count,t.Source)
    logLine("ITEM_SYNC",tostring(itemName).."="..tostring(count).." | "..tostring(t.Source))
    return true
end


function PHX.guiVisible(obj)
    if not obj then return false end
    local p=obj
    while p and p ~= PG do
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("CanvasGroup") and p.GroupTransparency >= .995 then return false end
        p=p.Parent
    end
    return true
end

function PHX.guiRequirementCount(itemName, required)
    local wanted = PHX.normalizeItemName(itemName)
    local best, bestDist = nil, math.huge
    for _,obj in ipairs(PHX.gameGuiDescendants(PG)) do
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
    -- Recipe display is diagnostic; only Stash and new pickup deltas change materials.
    return PHX.guiRequirementCount("Scrap Metal",10),PHX.guiRequirementCount("Blaze Ember",15)
end


function PHX.warmMaterialInventory(_seconds)
    return PHX.StashBaselineReady == true
end

function PHX.clearOptimisticCount(itemName)
    local count=PHX.cachedMaterialCount(itemName)
    return count or 0
end

function PHX.recordItemGain(itemName,amount,sourceText)
    if PHX.generationAlive and not PHX.generationAlive() then return end
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    local count=PHX.cachedMaterialCount(itemName)
    -- Unknown baseline stays unknown. A Magnet toast cannot verify a crafted recipe.
    if count == nil or PHX.StashSyncBusy then return end
    if itemName == "Volcanic Magnet" then return end
    PHX.setKnownMaterial(itemName,count+amount,"PICKUP")
    logLine("ITEM_GAIN",itemName.." +"..amount.." | "..tostring(sourceText))
end

local TRACKED_PICKUPS = {
    ["scrap metal"] = "Scrap Metal",
    ["blaze ember"] = "Blaze Ember",
    ["volcanic magnet"] = "Volcanic Magnet",
    ["dinosaur bones"] = "Dinosaur Bones",
    ["dinosaur bone"] = "Dinosaur Bones",
}


function PHX.parsePickupText(text)
    local raw=tostring(text or "")
    local low=PHX.normalizeItemName(raw:gsub("<.->",""))
    if not (low:find("obtained",1,true) or low:find("received",1,true) or low:find("acquired",1,true) or low:find("you got",1,true)) then return nil,nil end
    local amount=tonumber(raw:match("%((%d+)%s*[xX]%)") or raw:match("(%d+)%s*[xX]")) or 1
    for needle,name in pairs(TRACKED_PICKUPS) do
        if low:find(needle,1,true) then return name,amount end
    end
    return nil,nil
end

PHX.SeenPickupContainers=setmetatable({}, {__mode="k"})
function PHX.inspectPickupStack(allowGain)
    if PHX.generationAlive and not PHX.generationAlive() then return end
    local notifications=PG:FindFirstChild("Notifications")
    local stack=notifications and notifications:FindFirstChild("NotificationStack")
    if not stack then return end
    for _,container in ipairs(stack:GetChildren()) do
        local text=nil
        local objects={container}
        for _,o in ipairs(container:GetDescendants()) do objects[#objects+1]=o end
        for _,o in ipairs(objects) do
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.guiVisible(o) then
                local item=PHX.parsePickupText(o.Text)
                if item then text=tostring(o.Text); break end
            end
        end
        if text then
            local signature=PHX.normalizeItemName(text)
            if PHX.SeenPickupContainers[container] ~= signature then
                PHX.SeenPickupContainers[container]=signature
                if allowGain and PHX.StashBaselineReady and not PHX.StashSyncBusy then
                    local name,amount=PHX.parsePickupText(text)
                    local suppressed=PHX.PickupSuppress[name]
                    if suppressed and os.clock() <= (suppressed.Until or 0) then
                        -- Stash aftercraft already incorporates this notification.
                    elseif name then PHX.recordItemGain(name,amount,text) end
                end
            end
        end
    end
end

-- Mark pre-existing notifications before seeding the baseline; they are not new gains.
PHX.inspectPickupStack(false)
PHX.spawn(function()
    while not PHX.generationAlive or PHX.generationAlive() do
        pcall(function() PHX.inspectPickupStack(PHX.StashBaselineReady) end)
        task.wait(.12)
    end
end)

PHX.MagnetCache={Checked=false,Count=nil,Reason="STARTUP_PENDING",RefreshNeeded=false}

function PHX.updateMagnetCache(count,reason)
    PHX.MagnetCache.Count=tonumber(count)
    PHX.MagnetCache.Checked=true
    PHX.MagnetCache.RefreshNeeded=false
    PHX.MagnetCache.Reason=reason or (count~=nil and "STASH" or "UNKNOWN")
end

function PHX.invalidateMagnetCache()
    -- Call only after a verified completed event, immediately before the next hunt.
    PHX.MagnetCache.RefreshNeeded=true
    PHX.SeaHeading=nil
end

local function hasVolcanicMagnet()
    local cache=PHX.MagnetCache
    if not cache.Checked or cache.RefreshNeeded then
        local refresh=cache.RefreshNeeded
        local count,reason=PHX.checkMagnetFromStash(refresh)
        PHX.updateMagnetCache(count,reason)
        logLine("MAGNET_CACHE",tostring(count).." | "..tostring(reason))
    end
    if cache.Count==nil then return nil end
    return cache.Count>0
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
        if CONFIG.SAVE_CPU.HIDE_STATIC_MAP_VISUALS or PHX.MapVisualHidden then
            local map = workspace:FindFirstChild("Map")
            if map and obj:IsDescendantOf(map) and not PHX.isDynamicGameplayPart(obj) then
                -- Render-only: never destroy Map or alter collision/query/touch.
                if PHX.MapVisualBackup[obj] == nil then
                    pcall(function() PHX.MapVisualBackup[obj] = obj.LocalTransparencyModifier end)
                end
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


function PHX.setMapVisualHidden(hidden)
    hidden = hidden and true or false
    PHX.MapVisualHidden = hidden

    local map = workspace:FindFirstChild("Map")
    if not map then
        logLine("MAP_VISUAL", "Map missing | hidden="..tostring(hidden))
        return false
    end

    local n = 0
    for _,obj in ipairs(map:GetDescendants()) do
        if obj:IsA("BasePart") and not PHX.isDynamicGameplayPart(obj) then
            if hidden then
                if PHX.MapVisualBackup[obj] == nil then
                    pcall(function() PHX.MapVisualBackup[obj] = obj.LocalTransparencyModifier end)
                end
                pcall(function() obj.LocalTransparencyModifier = 1 end)
            else
                local old = PHX.MapVisualBackup[obj]
                pcall(function() obj.LocalTransparencyModifier = old ~= nil and old or 0 end)
                PHX.MapVisualBackup[obj] = nil
            end
            n = n + 1
            if n % 350 == 0 then task.wait() end
        end
    end

    logLine("MAP_VISUAL", (hidden and "HIDDEN" or "RESTORED").." parts="..tostring(n))
    return true
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
    PHX.connect(workspace.DescendantAdded, function(obj)
        PHX.defer(function() pcall(PHX.optimizeVisualObject, obj) end)
    end)

    if CONFIG.SAVE_CPU.FULL_3D_RENDER_OFF then
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
    end

    logLine("SAVE_CPU", "ON | fps="..tostring(CONFIG.SAVE_CPU.FPS_CAP).." mapRemoval=SEPARATE_TOGGLE preservePressureVFX=true")
end

PHX.spawn(function()
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
PHX.spawn(function()
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
                    if ok and tip == tooltip and not (PHX.isPhysicalFruitTool and PHX.isPhysicalFruitTool(v)) then
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
    PHX.keyEvent(true, keyCode, false, game)
    task.wait(hold or .07)
    PHX.keyEvent(false, keyCode, false, game)
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
    -- Probe confirms Dragon Talon exposes ToolTip="Melee" and the fruit exposes
    -- ToolTip="Blox Fruit". Give equip/input replication time, then spam a full
    -- X/C/V/F cycle twice. No mouse input is used.
    local function castSet(tooltip)
        local tool = equipTooltip(tooltip)
        if not tool then
            logLine("SKILL_CAST", "missing tooltip="..tostring(tooltip))
            return false
        end
        task.wait(.18)

        for pass=1,2 do
            for _,k in ipairs(SKILL_KEYS) do
                if targetPos then aimAt(targetPos) end
                pressKey(k, .11)
                task.wait(.17)
            end
            task.wait(.06)
        end
        logLine("SKILL_CAST", tostring(tooltip).." XCVF x2 | "..tostring(tool.Name))
        return true
    end

    if targetPos then aimAt(targetPos) end
    castSet("Melee")
    task.wait(.08)
    castSet("Blox Fruit")
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
PHX.spawn(function()
    while PHX.generationAlive() and task.wait(0.05) do
        if ENV.TeamConfig and ENV.TeamConfig.IsRunning then
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
    lavaConnection = PHX.connect(island.DescendantAdded, function(v)
        PHX.defer(function()
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

local function usePortal(cf,expectedRegion,token)
    for attempt=1,4 do
        if not PHX.travelAlive(token) or not waitPortalChainDelay(token) or not waitAlive(token) then return false end
        if not stopSit(token) then return false end
        local beforeRegion=getRegion()
        local r=root()
        if beforeRegion==expectedRegion then return true end
        if not r then return false end
        local beforePosition=r.Position
        setStatus("PORTAL -> "..expectedRegion.." ["..attempt.."/4]")
        logLine("PORTAL","from="..beforeRegion.." to="..expectedRegion)
        local function transitioned()
            local rr=root()
            local region=getRegion()
            return rr and (rr.Position-beforePosition).Magnitude>500 and region~=beforeRegion,region
        end
        local function confirm()
            local moved,region=transitioned()
            if moved then
                markPortalSuccess()
                PHX.PortalTravel=false
                task.wait(1.25)
                noteProgress("PORTAL:"..region)
                return region==expectedRegion, true
            end
            return false,false
        end
        PHX.PortalTravel=true
        local ok,err=pcall(function()
            -- Approach from above to avoid adjacent Castle gate triggers.
            highTween(cf*CFrame.new(0,0,-12),180,token)
            local _,moved=confirm()
            if moved then return end
            for _,offset in ipairs({CFrame.new(0,0,3),CFrame.new(0,0,8),CFrame.new(0,0,-3)}) do
                if not PHX.travelAlive(token) then return end
                safeTween(cf*offset,80,token)
                task.wait(.18)
                local _,crossed=confirm()
                if crossed then return end
            end
            local deadline=os.clock()+3
            while PHX.travelAlive(token) and os.clock()<deadline do
                local _,crossed=confirm()
                if crossed then return end
                task.wait(.18)
            end
        end)
        PHX.PortalTravel=false
        if not ok then logLine("PORTAL_ERROR",tostring(err)) end
        local region=getRegion()
        local rr=root()
        if region==expectedRegion and rr and (rr.Position-beforePosition).Magnitude>500 then return true end
        if region~=beforeRegion and region~="UNKNOWN" then
            logLine("PORTAL_WRONG_DEST","wanted="..expectedRegion.." got="..region)
            return false
        end
    end
    setStatus("PORTAL FAILED -> "..expectedRegion.."; route paused")
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
    if not resetCharacter(token) then return false end
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
    if not boat then return nil end
    local owner=boat:FindFirstChild("Owner")
    local value=owner and owner:IsA("ValueBase") and owner.Value or boat:GetAttribute("Owner")
    if typeof(value)=="Instance" and value:IsA("Player") then return value.Name end
    if tonumber(value) then
        for _,player in ipairs(Players:GetPlayers()) do if player.UserId==tonumber(value) then return player.Name end end
    end
    return value~=nil and tostring(value) or nil
end

function PHX.boatHealth(boat)
    if not boat then return nil,nil end
    local health,maxHealth=boat:FindFirstChild("Health",true),boat:FindFirstChild("MaxHealth",true)
    return tonumber(health and health:IsA("ValueBase") and health.Value or boat:GetAttribute("Health")),
        tonumber(maxHealth and maxHealth:IsA("ValueBase") and maxHealth.Value or boat:GetAttribute("MaxHealth"))
end

function PHX.boatAlive(boat)
    if not boat or not boat.Parent then return false end
    local hp=PHX.boatHealth(boat)
    return hp==nil or hp>0
end

PHX.RejectedBoats=setmetatable({},{__mode="k"})

local function getMasterBoat()
    local boats=workspace:FindFirstChild("Boats")
    if not boats then return nil end
    local master=PHX.playerByName(ENV.TeamConfig.MasterName)
    local masterRoot=master and master.Character and master.Character:FindFirstChild("HumanoidRootPart")
    local best,bestDistance=nil,math.huge
    for _,boat in ipairs(boats:GetChildren()) do
        if boat.Name==CONFIG.BOAT_NAME and PHX.sameName(boatOwnerName(boat),ENV.TeamConfig.MasterName) and PHX.boatAlive(boat) and not PHX.RejectedBoats[boat] then
            local driver=PHX.findDriverSeat(boat)
            local occupant=driver and driver.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            if player and PHX.sameName(player.Name,ENV.TeamConfig.MasterName) then return boat end
            local distance=masterRoot and (boat:GetPivot().Position-masterRoot.Position).Magnitude or 0
            if distance<bestDistance then best,bestDistance=boat,distance end
        end
    end
    return best
end

local function sortPassengerSeats(boat)
    local driver=PHX.findDriverSeat(boat)
    if not driver then return {} end
    local decorated={}
    for _,seat in ipairs(boat:GetDescendants()) do
        if seat:IsA("Seat") and not seat:IsA("VehicleSeat") then
            local position=driver.CFrame:PointToObjectSpace(seat.Position)
            decorated[#decorated+1]={seat=seat,x=math.floor(position.X*10+.5),z=math.floor(position.Z*10+.5),name=seat:GetFullName()}
        end
    end
    table.sort(decorated,function(a,b)
        if a.z~=b.z then return a.z<b.z end
        if a.x~=b.x then return a.x<b.x end
        return a.name<b.name
    end)
    local seats={}
    for _,entry in ipairs(decorated) do seats[#seats+1]=entry.seat end
    return seats
end

local function slaveIndex()
    local n=0
    for _,name in ipairs(CONFIG.TEAM) do
        if not PHX.sameName(name,ENV.TeamConfig.MasterName) then n=n+1; if PHX.sameName(name,LP.Name) then return n end end
    end
end

local function sitOn(seat,token)
    local c,h=waitAlive(token)
    if not c or not h or not seat or not seat.Parent then return false end
    if h.SeatPart==seat and seat.Occupant==h then return true end
    if seat.Occupant and seat.Occupant~=h then return false end
    if not stopSit(token) then return false end
    local deadline=os.clock()+8
    while PHX.travelAlive(token) and seat.Parent and os.clock()<deadline do
        if h~=hum() or h.Health<=0 then return false end
        if seat.Occupant and seat.Occupant~=h then return false end
        if not safeTween(seat.CFrame*CFrame.new(0,3,0),180,token) then return false end
        if not seat.Parent then return false end
        pcall(function() seat:Sit(h) end)
        local verifyUntil=os.clock()+1.4
        while PHX.travelAlive(token) and seat.Parent and os.clock()<verifyUntil do
            if h.SeatPart==seat and seat.Occupant==h then noteProgress("SEATED:"..seat:GetFullName()..":"..CHARACTER_EPOCH); return true end
            if h~=hum() or h.Health<=0 then return false end
            task.wait(.10)
        end
    end
    return false
end

function PHX.returnToDealer(token)
    if getRegion()=="UNKNOWN" then
        setStatus("RECOVERY offshore -> respawn at saved Tiki spawn")
        if PHX.secureDragonWindow and not PHX.secureDragonWindow(1.0,token) then return false end
        if not resetCharacter(token) then return false end
    end
    if not goTiki(token) then return false end
    if not safeTween(CONFIG.BOAT_DEALER_CFRAME,180,token) then return false end
    pcall(function() CommF:InvokeServer("SetSpawnPoint") end)
    noteProgress("TIKI_DEALER:"..CHARACTER_EPOCH)
    return true
end

local function buyGrandBrigade(token)
    if not isMaster() or not PHX.travelAlive(token) then return nil end
    local existing=getMasterBoat()
    if existing then return existing end
    PHX.TeamPhase="RECOVERY"
    PHX.BoatState="BUYING"
    if not PHX.returnToDealer(token) then return nil end
    for attempt=1,5 do
        if not PHX.travelAlive(token) then return nil end
        local boat=getMasterBoat()
        if boat then return boat end
        pcall(function() CommF:InvokeServer("BuyBoat",CONFIG.BOAT_BUY_NAME) end)
        task.wait(1)
        boat=getMasterBoat()
        if boat then PHX.BoatState="READY"; return boat end
        setStatus("BuyBoat retry "..attempt.."/5")
    end
    PHX.BoatState="BUY_FAILED"
end

local function boardBoat(boat,token)
    if not PHX.boatAlive(boat) then return false end
    PHX.TeamPhase="BOARDING"
    if isMaster() then
        local driver=PHX.findDriverSeat(boat)
        return driver and sitOn(driver,token) or false
    end
    local index=slaveIndex()
    local seats=sortPassengerSeats(boat)
    if not index or index>4 or not seats[index] then
        setStatus("Passenger seat "..tostring(index).." unavailable; waiting real boat seats")
        return false
    end
    return sitOn(seats[index],token)
end

local function countTeamAboard(boat)
    if not boat or not boat.Parent then return 0 end
    local aboard={}
    for _,seat in ipairs(boat:GetDescendants()) do
        if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
            local occupant=seat.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            if player and isTeamName(player.Name) then aboard[player.Name]=true end
        end
    end
    local count=0
    for _ in pairs(aboard) do count=count+1 end
    return count
end

function PHX.crewReady(boat)
    if not PHX.boatAlive(boat) then return false,0 end
    local driver=PHX.findDriverSeat(boat)
    local pilot=driver and driver.Occupant
    local master=pilot and pilot.Parent and Players:GetPlayerFromCharacter(pilot.Parent)
    if not master or master.Name~=ENV.TeamConfig.MasterName or pilot.Health<=0 or master.Character~=pilot.Parent then return false,0 end
    local passengers={}
    for _,seat in ipairs(boat:GetDescendants()) do
        if seat:IsA("Seat") and not seat:IsA("VehicleSeat") then
            local occupant=seat.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            if player and player.Name~=ENV.TeamConfig.MasterName and isTeamName(player.Name) and
                occupant.Health>0 and player.Character==occupant.Parent then passengers[player.Name]=true end
        end
    end
    local count=0
    for _ in pairs(passengers) do count=count+1 end
    return count>=(tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3),count
end

PHX.driverSeat = PHX.findDriverSeat

function PHX.boatTelemetry()
    local boat=getMasterBoat()
    local hp,maxHp=PHX.boatHealth(boat)
    local driver=PHX.findDriverSeat(boat)
    return {Name=boat and boat.Name,HP=hp,MaxHP=maxHp,Aboard=boat and countTeamAboard(boat) or 0,
        Owner=ENV.TeamConfig.MasterName,State=PHX.BoatState or PHX.TeamPhase or "WAIT_MASTER",
        Heading=PHX.SeaHeading,IsDriver=driver and hum() and driver.Occupant==hum() or false}
end

local function boatNoclip(boat)
    if not isMaster() then return end
    local backup=PHX.TravelState.BoatParts
    if not backup then backup={}; PHX.TravelState.BoatParts=backup end
    for _,part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") then
            if backup[part]==nil then backup[part]=part.CanCollide end
            part.CanCollide=false
        end
    end
end

function PHX.prehistoricMarker()
    local map = workspace:FindFirstChild("Map")
    local oldIsland = map and map:FindFirstChild("PrehistoricIsland")
    if oldIsland and PHX.CompletedIslands and PHX.CompletedIslands[oldIsland] then return nil end
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    return locations and (locations:FindFirstChild("Prehistoric Island") or locations:FindFirstChild("PrehistoricIsland"))
end

local function findPrehistoric()
    local map = workspace:FindFirstChild("Map")
    local island = map and map:FindFirstChild("PrehistoricIsland")
    if island and not (PHX.CompletedIslands and PHX.CompletedIslands[island]) then return island end
    return nil
end

local function boatFlyTo(boat,targetPos,token)
    if not isMaster() or not PHX.boatAlive(boat) then return false end
    local driver=PHX.findDriverSeat(boat)
    local h=hum()
    if not driver or not h or h.Health<=0 or h.SeatPart~=driver or driver.Occupant~=h then return false end
    PHX.TravelState.Boat=boat
    PHX.TravelState.BoatMoving=true
    boatNoclip(boat)
    local previousAt=os.clock()
    local speed=math.clamp(tonumber(CONFIG.BOAT_TWEEN_SPEED) or 475,50,475)
    local arrived=false
    while PHX.travelAlive(token) and PHX.boatAlive(boat) and PHX.TravelState.BoatMoving do
        if findPrehistoric() or PHX.prehistoricMarker() then break end
        if h~=hum() or h.Health<=0 or h.SeatPart~=driver or driver.Occupant~=h then break end
        -- A required crew drop pauses search for recovery; a missing fifth account is allowed.
        if not PHX.crewReady(boat) then PHX.BoatState="PASSENGER_RECOVERY"; break end
        local now=os.clock()
        local dt=math.clamp(now-previousAt,0,.10)
        previousAt=now
        local current=boat:GetPivot().Position
        local heading=PHX.SeaHeading or Vector3.new(targetPos.X-current.X,0,targetPos.Z-current.Z).Unit
        local remaining=(targetPos-current):Dot(heading)
        if remaining<=4 then arrived=true; noteProgress("SAILED:"..math.floor(current.X)..":"..math.floor(current.Z)); break end
        local step=math.min(remaining,speed*dt)
        -- Even a replication correction never makes the boat steer sideways toward an old waypoint.
        local position=current+heading*step
        position=Vector3.new(position.X,current.Y+math.clamp(targetPos.Y-current.Y,-speed*dt,speed*dt),position.Z)
        local ok=pcall(function() boat:PivotTo(CFrame.lookAt(position,position+heading)) end)
        if not ok then break end
        RunService.Heartbeat:Wait()
    end
    PHX.stopBoat(boat)
    return arrived or findPrehistoric()~=nil or PHX.prehistoricMarker()~=nil
end

local function searchSeaUntilIsland(boat,token)
    if not isMaster() or not PHX.boatAlive(boat) then return nil end
    if not PHX.SeaHeading then
        local start=boat:GetPivot().Position
        local direction=Vector3.new(CONFIG.SEA6_CENTER.X-start.X,0,CONFIG.SEA6_CENTER.Z-start.Z)
        if direction.Magnitude<1 then
            local look=boat:GetPivot().LookVector
            direction=Vector3.new(look.X,0,look.Z)
        end
        if direction.Magnitude<.01 then direction=Vector3.new(-1,0,0) end
        PHX.SeaHeading=direction.Unit
    end
    local distanceSailed=0
    while PHX.travelAlive(token) and PHX.boatAlive(boat) do
        local island=findPrehistoric()
        if island then PHX.stopBoat(boat); PHX.TeamPhase="ISLAND_FOUND"; return island end
        if PHX.prehistoricMarker() then
            PHX.stopBoat(boat)
            PHX.TeamPhase="ISLAND_FOUND"
            PHX.BoatState="MARKER_DETECTED"
            setStatus("Prehistoric marker detected; boat stopped, waiting replicated island")
            local deadline=os.clock()+20
            while PHX.travelAlive(token) and PHX.boatAlive(boat) and os.clock()<deadline do
                island=findPrehistoric()
                if island then return island end
                task.wait(.2)
            end
            -- Keep still while a known marker is streaming; never drift away from it.
            if PHX.prehistoricMarker() then return nil end
        end
        local driver=PHX.findDriverSeat(boat)
        local h=hum()
        if not driver or not h or h.Health<=0 or h.SeatPart~=driver or driver.Occupant~=h then
            PHX.stopBoat(boat); PHX.TeamPhase="RECOVERY"; return nil
        end
        if not PHX.crewReady(boat) then
            PHX.stopBoat(boat); PHX.TeamPhase="BOARDING"; return nil
        end
        PHX.TeamPhase="SAILING"; PHX.BoatState="STRAIGHT_SEA6"
        setStatus("MASTER: Sea6 STRAIGHT | sailed "..math.floor(distanceSailed).." | aboard "..countTeamAboard(boat).."/5")
        local position=boat:GetPivot().Position
        local target=position+PHX.SeaHeading*3000
        target=Vector3.new(target.X,CONFIG.SEA6_CENTER.Y,target.Z)
        local result=boatFlyTo(boat,target,token)
        distanceSailed=distanceSailed+(boat.Parent and (boat:GetPivot().Position-position).Magnitude or 0)
        if not result then PHX.TeamPhase="RECOVERY"; return nil end
    end
    PHX.stopBoat(boat)
    PHX.TeamPhase="RECOVERY"; PHX.BoatState="BOAT_LOST"
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

PHX.EventState = {Phase="WAIT", Egg="WAIT", Error=nil}
PHX.FossilAttempted = setmetatable({}, {__mode="k"})
PHX.EventSeenHUD = setmetatable({}, {__mode="k"})
PHX.EventFinishedIslands = setmetatable({}, {__mode="k"})
PHX.RewardProgress = setmetatable({}, {__mode="k"})
PHX.CompletedIslands = setmetatable({}, {__mode="k"})
PHX.GolemPrepared = setmetatable({}, {__mode="k"})
PHX.GolemLastBring = setmetatable({}, {__mode="k"})
PHX.GolemDamage = setmetatable({}, {__mode="k"})
PHX.GolemOriginal = setmetatable({}, {__mode="k"})

function PHX.raidGuiVisible(obj)
    if not obj or not obj:IsDescendantOf(PG) then return false end
    local p = obj
    while p and p ~= PG do
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        if p:IsA("GuiObject") and (not p.Visible or p.AbsoluteSize.X <= 0 or p.AbsoluteSize.Y <= 0) then return false end
        if p:IsA("CanvasGroup") and p.GroupTransparency >= .995 then return false end
        p = p.Parent
    end
    return (not obj:IsA("TextLabel") and not obj:IsA("TextButton")) or obj.TextTransparency < .995
end

function PHX.cleanHudText(value)
    return tostring(value or ""):gsub("<[^>]+>", ""):gsub("&nbsp;", " ")
end

function PHX.percentFor(text, kind)
    local plain = string.lower(PHX.cleanHudText(text))
    local raw
    if kind == "pressure" then
        raw = plain:match("volcano%s+pressure%s*[:%-]?%s*(%d+%.?%d*)%s*%%")
            or plain:match("pressure%s*[:%-]?%s*(%d+%.?%d*)%s*%%")
    else
        raw = plain:match("relic%s+health%s*[:%-]?%s*(%d+%.?%d*)%s*%%")
            or plain:match("relic%s+hp%s*[:%-]?%s*(%d+%.?%d*)%s*%%")
    end
    local n = tonumber(raw)
    if n and n >= 0 and n <= 100 then return n end
    return nil
end

function PHX.readRaidHUD(force)
    if not force and PHX.RaidHUDCache and os.clock() - PHX.RaidHUDCache.At < .15 then
        return PHX.RaidHUDCache
    end
    local out = {At=os.clock(), Active=false, Pressure=nil, Relic=nil, Timer=nil, TimerSeconds=nil}
    local main = PG:FindFirstChild("Main")
    local hud = main and main:FindFirstChild("TopHUDList")
    if hud then
        local texts = {}
        local function accept(obj, priority)
            if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) or not PHX.raidGuiVisible(obj) then return end
            local text = PHX.cleanHudText(obj.Text)
            if text == "" then return end
            texts[#texts+1] = {Object=obj, Text=text, Priority=priority}
        end
        -- Direct current game cards win over hierarchy-change fallbacks. Ancestor
        -- visibility is checked, so hidden templates cannot supply stale percentages.
        for _,name in ipairs({"PrehistoricRaidTimer", "PrehistoricRelicHealth", "PrehistoricVolcanoPressure"}) do
            local card = hud:FindFirstChild(name)
            if card then
                accept(card, 0)
                for _,o in ipairs(card:GetDescendants()) do accept(o, 1) end
            end
        end
        for _,o in ipairs(hud:GetDescendants()) do accept(o, 2) end
        table.sort(texts, function(a,b)
            if a.Priority ~= b.Priority then return a.Priority < b.Priority end
            if a.Object.ZIndex ~= b.Object.ZIndex then return a.Object.ZIndex > b.Object.ZIndex end
            return a.Object:GetFullName() < b.Object:GetFullName()
        end)
        for _,entry in ipairs(texts) do
            local text, obj = entry.Text, entry.Object
            local lower, name = string.lower(text), string.lower(obj.Name)
            if out.Pressure == nil then
                out.Pressure = PHX.percentFor(text, "pressure")
                if out.Pressure == nil and name:find("pressure", 1, true) then
                    out.Pressure = tonumber(lower:match("(%d+%.?%d*)%s*%%"))
                    if out.Pressure and (out.Pressure < 0 or out.Pressure > 100) then out.Pressure = nil end
                end
            end
            if out.Relic == nil then
                out.Relic = PHX.percentFor(text, "relic")
                if out.Relic == nil and name == "prehistoricrelichealth" then
                    out.Relic = tonumber(lower:match("(%d+%.?%d*)%s*%%"))
                end
            end
            if out.Timer == nil then
                out.Timer = lower:match("time%s+left%s*[:%-]?%s*([^\n]+)")
                if out.Timer then
                    -- Some versions combine timer and pressure in one RichText line.
                    out.Timer = out.Timer:gsub("%s*[|•].*", ""):gsub("%s*volcano.*", "")
                    local mins, secs = out.Timer:match("(%d+)%s*:%s*(%d+)")
                    if mins then
                        out.TimerSeconds = tonumber(mins)*60 + tonumber(secs)
                    else
                        local m = tonumber(out.Timer:match("(%d+)%s*m"))
                        local s = tonumber(out.Timer:match("(%d+%.?%d*)%s*s"))
                        out.TimerSeconds = (m or s) and (m or 0)*60+(s or 0) or tonumber(out.Timer:match("^%s*(%d+%.?%d*)%s*$"))
                    end
                end
            end
            if lower:find("volcano pressure", 1, true) or lower:find("relic health", 1, true)
                or name == "prehistoricrelichealth" or (name == "prehistoricraidtimer" and lower:find("time left", 1, true)) then
                out.Active = true
            end
        end
    end
    if out.Relic and (out.Relic < 0 or out.Relic > 100) then out.Relic=nil end
    PHX.RaidHUDCache = out
    return out
end

function PHX.eventActive(island)
    local hud = PHX.readRaidHUD()
    if hud.Active then
        if island then PHX.EventSeenHUD[island] = true end
        return true
    end
    -- Once this client has observed the active HUD, its disappearance wins over
    -- an obsolete attribute value from a game build that never clears it.
    if island and PHX.EventSeenHUD[island] then return false end
    -- IsMinigameActive may be nil in tested clients; HUD remains the primary signal.
    return island ~= nil and island.Parent ~= nil and island:GetAttribute("IsMinigameActive") == true
end

local function parsePercent(text)
    return tonumber(PHX.cleanHudText(text):match("(%d+%.?%d*)%s*%%"))
end

local function getPressure()
    return PHX.readRaidHUD().Pressure
end

local function getRelicHealthPercent(island)
    local hud = PHX.readRaidHUD()
    if hud.Relic ~= nil then return hud.Relic end
    local relic = getRelic(island)
    local hp = relic and relic:FindFirstChild("Health")
    local mx = relic and relic:FindFirstChild("MaxHealth")
    if hp and mx and tonumber(hp.Value) and tonumber(mx.Value) and mx.Value > 0 then
        return hp.Value / mx.Value * 100
    end
    return nil
end

function PHX.liveGolems()
    local out = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _,m in ipairs(enemies:GetChildren()) do
            if m:IsA("Model") and m.Name == "Lava Golem" then
                local h = m:FindFirstChildOfClass("Humanoid")
                local gp = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
                if h and h.Health > 0 and gp and gp:IsA("BasePart") then out[#out+1] = m end
            end
        end
    end
    return out
end

function PHX.totalGolemHP(golems)
    local total = 0
    for _,g in ipairs(golems or {}) do
        local h = g:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then total = total + h.Health end
    end
    return total
end

function PHX.eventSnapshot(island)
    island = island or findPrehistoric()
    if PHX.EventSnapshotCache and PHX.EventSnapshotIsland == island and os.clock()-PHX.EventSnapshotCache.At < .15 then
        return PHX.EventSnapshotCache
    end
    local hud = PHX.readRaidHUD()
    local golems = PHX.liveGolems()
    local active = PHX.eventActive(island)
    local phase = PHX.EventState.Phase
    if active then phase = #golems > 0 and "GOLEM" or "PRESSURE" end
    local out = {
        At=os.clock(), Active=active, Pressure=hud.Pressure, Relic=getRelicHealthPercent(island),
        Timer=hud.Timer, TimerSeconds=hud.TimerSeconds, GolemCount=#golems,
        GolemHP=PHX.totalGolemHP(golems), Egg=PHX.EventState.Egg,
        Phase=phase, Error=PHX.EventState.Error,
    }
    PHX.EventSnapshotCache, PHX.EventSnapshotIsland = out, island
    return out
end

function PHX.eventStatus(text, phase)
    if phase then PHX.EventState.Phase = phase end
    if text ~= PHX.LastEventStatus and (os.clock()-(PHX.LastEventStatusAt or -math.huge) >= .35) then
        PHX.LastEventStatus, PHX.LastEventStatusAt = text, os.clock()
        setStatus(text)
    end
end

function PHX.pauseEvent(reason, message)
    PHX.EventState.Error = reason
    if PHX.stopAutomation then PHX.stopAutomation(reason) else
        ENV.TeamConfig.StopReason = reason
        ENV.TeamConfig.IsRunning = false
    end
    setStatus(message)
end

function PHX.capturedFossilTarget(island)
    local relic = getRelic(island)
    if not relic then return nil end
    local ok,pivot = pcall(function() return relic:GetPivot() end)
    if not ok then return nil end
    return pivot * CONFIG.FOSSIL.PLAYER_RELATIVE_TO_RELIC, pivot
end

local function countTeamNear(pos, radius)
    local n = 0
    for _,p in ipairs(Players:GetPlayers()) do
        if isTeamName(p.Name) and p.Character then
            local rr = p.Character:FindFirstChild("HumanoidRootPart")
            local hh = p.Character:FindFirstChildOfClass("Humanoid")
            if rr and hh and hh.Health > 0 and (rr.Position-pos).Magnitude <= radius then n = n + 1 end
        end
    end
    return n
end

local function moveToRelic(island, token)
    local target = PHX.capturedFossilTarget(island)
    if not target then return false end
    -- Capture is ~60 studs below/aside the relic pivot. Group around the actual
    -- captured interaction position instead of the noninteractive skull pivot.
    if not isMaster() then
        local idx = slaveIndex() or 1
        local angle = ((idx-1)/4)*math.pi*2
        target = CFrame.new(target.Position + Vector3.new(math.cos(angle)*8, 0, math.sin(angle)*8))
    end
    PHX.EventState.Phase = "DISEMBARK"
    return safeTween(target, CONFIG.FOSSIL.SAFE_SPEED, token)
end

local function startEventAsMaster(island, token)
    if not isMaster() then return PHX.eventActive(island) end
    if PHX.eventActive(island) then return true end
    local target = PHX.capturedFossilTarget(island)
    if not target then return false end
    PHX.EventState.Phase = "FOSSIL_START"
    local waitUntil = os.clock() + CONFIG.FOSSIL.TEAM_WAIT_SECONDS
    while isRunning(token) and island.Parent and not PHX.eventActive(island) and os.clock() < waitUntil do
        local near = countTeamNear(target.Position, CONFIG.RELIC_RADIUS)
        PHX.eventStatus("MASTER: Fossil team "..near.."/"..CONFIG.MIN_TEAM_NEAR_RELIC, "FOSSIL_START")
        if near >= CONFIG.MIN_TEAM_NEAR_RELIC then break end
        task.wait(.2)
    end
    if PHX.eventActive(island) then return true end
    if not isRunning(token) or not island.Parent then return false end
    if countTeamNear(target.Position, CONFIG.RELIC_RADIUS) < CONFIG.MIN_TEAM_NEAR_RELIC then
        PHX.pauseEvent("TEAM_RELIC_TIMEOUT", "Team not ready at captured Fossil spot -> paused")
        return false
    end
    if PHX.FossilAttempted[island] then
        PHX.pauseEvent("FOSSIL_UNCONFIRMED", "Fossil already attempted; inspect or start manually, then resume")
        return false
    end
    if not safeTween(target, CONFIG.FOSSIL.SAFE_SPEED, token) then return false end
    local rr = root()
    if not rr or (rr.Position-target.Position).Magnitude > 4 then return false end
    -- safeTween already completed the captured orientation using a rotation tween.
    pcall(function()
        rr.AssemblyLinearVelocity = Vector3.zero
        rr.AssemblyAngularVelocity = Vector3.zero
    end)
    task.wait(CONFIG.FOSSIL.SETTLE_TIME)
    if not isRunning(token) then return false end
    -- No ProximityPrompt was present in the user's successful capture.
    PHX.FossilAttempted[island] = true
    setStatus("MASTER: exact Fossil pose -> mobile click/touch hold 3s")
    if not PHX.holdInteraction(getRelic(island), CONFIG.FOSSIL.HOLD_SECONDS, token) then return false end
    local deadline = os.clock()+3
    repeat
        PHX.RaidHUDCache = nil
        if PHX.eventActive(island) then
            PHX.EventState.Error = nil
            noteProgress("FOSSIL_STARTED")
            return true
        end
        task.wait(.08)
    until not isRunning(token) or not island.Parent or os.clock() >= deadline
    if isRunning(token) then PHX.pauseEvent("FOSSIL_UNCONFIRMED", "Fossil hold unconfirmed -> paused; inspect before another click/touch hold") end
    return false
end

local function rockActive(rock)
    for _,v in ipairs(rock:GetDescendants()) do
        if (v:IsA("Beam") or v:IsA("ParticleEmitter")) and v.Enabled then return true end
    end
    return false
end

local function activePressureRocks(island)
    local core = island and island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("VolcanoRocks")
    local list = {}
    if folder then
        for _,rock in ipairs(folder:GetChildren()) do
            if rock:IsA("Model") and rockActive(rock) then
                local part = rock:FindFirstChild("volcanorock") or rock:FindFirstChildWhichIsA("BasePart", true)
                if part then list[#list+1] = {model=rock, part=part} end
            end
        end
    end
    -- All five clients choose slots from the same island-relative order, not
    -- each client's distance order (which causes teammates to pick the same rock).
    local pivot = island and island:GetPivot()
    table.sort(list, function(a,b)
        local ap = pivot and pivot:PointToObjectSpace(a.part.Position) or a.part.Position
        local bp = pivot and pivot:PointToObjectSpace(b.part.Position) or b.part.Position
        if ap.X ~= bp.X then return ap.X < bp.X end
        if ap.Z ~= bp.Z then return ap.Z < bp.Z end
        return a.model.Name < b.model.Name
    end)
    return list
end

function PHX.pickPressureRock(island, offset)
    local rocks = activePressureRocks(island)
    if #rocks == 0 then return nil, 0 end
    return rocks[((tonumber(offset) or 1)-1)%#rocks+1], #rocks
end

function PHX.pressureRockBurst(target, token, island)
    if not target or not target.model or not target.part then return false end
    local deadline = os.clock() + CONFIG.PRESSURE.MAX_BURST_SECONDS
    while isRunning(token) and target.model.Parent and rockActive(target.model) and os.clock() < deadline do
        -- A newly spawned Golem interrupts pressure within one skill step.
        if #PHX.liveGolems() > 0 then return false end
        if island and not PHX.eventActive(island) then return false end
        local p, rp = target.part.Position, root()
        if not rp then return false end
        local hover = CFrame.new(p + Vector3.new(0, CONFIG.PRESSURE.ROCK_HOVER_Y, 0))
        if (rp.Position-hover.Position).Magnitude > 14 and not safeTween(hover, 165, token) then return false end
        for _,tooltip in ipairs({"Melee", "Blox Fruit"}) do
            local tool = equipTooltip(tooltip)
            if tool then
                for _,key in ipairs(SKILL_KEYS) do
                    if not isRunning(token) or not target.model.Parent or not rockActive(target.model) or #PHX.liveGolems() > 0 then return false end
                    aimAt(p)
                    pressKey(key, CONFIG.PRESSURE.SKILL_HOLD)
                    task.wait(CONFIG.PRESSURE.SKILL_GAP)
                end
            end
        end
    end
    if not target.model.Parent or not rockActive(target.model) then noteProgress("PRESSURE_ROCK_FIXED") return true end
    return false
end

function PHX.clusterAnchor(island)
    if PHX.ClusterIsland == island and PHX.ClusterAnchor then return PHX.ClusterAnchor end
    local target, relicPivot = PHX.capturedFossilTarget(island)
    if not target or not relicPivot then return nil end
    -- Shared deterministic geometry. Only Master moves enemies; Slaves compute
    -- the same attack point without competing for network ownership.
    local islandPivot = island:GetPivot()
    local away = Vector3.new(-islandPivot.LookVector.X, 0, -islandPivot.LookVector.Z)
    if away.Magnitude < .1 then away = Vector3.new(1,0,0) end
    local pos = relicPivot.Position + away.Unit * CONFIG.GOLEM_AURA.BRING_DISTANCE_FROM_RELIC
    pos = Vector3.new(pos.X, target.Position.Y, pos.Z)
    PHX.ClusterIsland = island
    PHX.ClusterAnchor = CFrame.lookAt(pos, Vector3.new(relicPivot.Position.X, pos.Y, relicPivot.Position.Z))
    PHX.ClusterProgressAt, PHX.ClusterLastHP = os.clock(), nil
    PHX.SimulationBoosted = false
    return PHX.ClusterAnchor
end

function PHX.prepareGolemOnce(golem)
    if not isMaster() or PHX.GolemPrepared[golem] then return end
    PHX.GolemPrepared[golem] = true
    if not PHX.SimulationBoosted then
        PHX.SimulationBoosted = true
        pcall(function() if setsimulationradius then setsimulationradius(1000,1000) end end)
        pcall(function() if sethiddenproperty then sethiddenproperty(LP,"SimulationRadius",1000) end end)
    end
    for _,part in ipairs(golem:GetDescendants()) do
        if part:IsA("BasePart") then
            PHX.GolemOriginal[part] = {CanCollide=part.CanCollide, Size=part.Size}
            pcall(function() part.CanCollide = false end)
        end
    end
    local gp = golem:FindFirstChild("HumanoidRootPart") or golem:FindFirstChild("Head")
    if gp then
        pcall(function() gp.Size = Vector3.new(CONFIG.GOLEM_AURA.HITBOX_SIZE, CONFIG.GOLEM_AURA.HITBOX_SIZE, CONFIG.GOLEM_AURA.HITBOX_SIZE) end)
    end
end

function PHX.restoreGolemChanges()
    for part, original in pairs(PHX.GolemOriginal) do
        if part.Parent then pcall(function() part.CanCollide = original.CanCollide part.Size = original.Size end) end
        PHX.GolemOriginal[part] = nil
    end
    PHX.GolemPrepared = setmetatable({}, {__mode="k"})
    PHX.GolemLastBring = setmetatable({}, {__mode="k"})
end

function PHX.bringGolemCluster(island, golems)
    local anchor = PHX.clusterAnchor(island)
    if not anchor or not isMaster() then return anchor end
    local now = os.clock()
    for i,g in ipairs(golems) do
        local h = g:FindFirstChildOfClass("Humanoid")
        local gp = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
        if h and h.Health > 0 and gp then
            local first = not PHX.GolemPrepared[g]
            PHX.prepareGolemOnce(g)
            local angle = ((i-1)/math.max(#golems,1))*math.pi*2
            local off = #golems > 1 and Vector3.new(math.cos(angle)*CONFIG.GOLEM_AURA.CLUSTER_RADIUS,0,math.sin(angle)*CONFIG.GOLEM_AURA.CLUSTER_RADIUS) or Vector3.zero
            local slot = CFrame.lookAt(anchor.Position+off, anchor.Position+off+anchor.LookVector)
            if first or (now-(PHX.GolemLastBring[g] or -math.huge) >= CONFIG.GOLEM_AURA.BRING_INTERVAL and (gp.Position-slot.Position).Magnitude >= CONFIG.GOLEM_AURA.REBRING_DRIFT) then
                PHX.GolemLastBring[g] = now
                pcall(function()
                    g:PivotTo(slot)
                    gp.AssemblyLinearVelocity = Vector3.zero
                    gp.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end
    return anchor
end

function PHX.netHitGolemCluster(golems)
    local rr = root()
    if not rr then return false end
    local hits, primary = {}, nil
    for _,g in ipairs(golems) do
        local h = g:FindFirstChildOfClass("Humanoid")
        local gp = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
        if h and h.Health > 0 and gp and (gp.Position-rr.Position).Magnitude <= CONFIG.GOLEM_AURA.NET_DISTANCE then
            primary = primary or gp
            hits[#hits+1] = {g, gp}
        end
    end
    if not primary then return false end
    local registerAttack, registerHit = resolveNetAttack()
    if not registerAttack or not registerHit then
        local tool = equipTooltip("Melee")
        if tool then pcall(function() tool:Activate() end) end
        return false
    end
    local okA = pcall(function() registerAttack:FireServer(.05) end)
    if not okA then return false end
    return pcall(function() registerHit:FireServer(primary, hits) end)
end

function PHX.golemClusterBurst(island, token)
    local golems = PHX.liveGolems()
    if #golems == 0 then return true end
    local anchor = PHX.bringGolemCluster(island, golems)
    if not anchor then return false end
    local idx = teamIndex(LP.Name) or 1
    local angle = ((idx-1)/math.max(#CONFIG.TEAM,1))*math.pi*2
    local playerTarget = CFrame.new(anchor.Position+Vector3.new(math.cos(angle)*8, CONFIG.GOLEM_AURA.HOVER_Y, math.sin(angle)*8))
    local rr = root()
    if not rr then return false end
    -- Slaves approach the replicated actual cluster if a server refuses a bring.
    -- They never independently PivotTo enemies or enlarge simulation radius.
    do
        local firstPart = golems[1]:FindFirstChild("HumanoidRootPart") or golems[1]:FindFirstChild("Head")
        if firstPart and (firstPart.Position-anchor.Position).Magnitude > CONFIG.GOLEM_AURA.NET_DISTANCE then
            playerTarget = CFrame.new(firstPart.Position+Vector3.new(math.cos(angle)*8, CONFIG.GOLEM_AURA.HOVER_Y, math.sin(angle)*8))
        end
    end
    if (rr.Position-playerTarget.Position).Magnitude > CONFIG.GOLEM_AURA.APPROACH_DISTANCE and not safeTween(playerTarget,165,token) then return false end
    local deadline = os.clock()+CONFIG.GOLEM_AURA.BURST_SECONDS
    while isRunning(token) and island.Parent and PHX.eventActive(island) and os.clock() < deadline do
        golems = PHX.liveGolems()
        if #golems == 0 then noteProgress("GOLEM_CLUSTER_CLEAR") return true end
        PHX.bringGolemCluster(island,golems)
        local total, damaged = PHX.totalGolemHP(golems), false
        for _,g in ipairs(golems) do
            local h = g:FindFirstChildOfClass("Humanoid")
            local old = PHX.GolemDamage[g]
            if old and h and h.Health < old then damaged = true end
            if h then PHX.GolemDamage[g] = h.Health end
        end
        if damaged then PHX.ClusterProgressAt = os.clock() noteProgress("GOLEM_DAMAGE:"..math.floor(total)) end
        PHX.eventStatus((isMaster() and "MASTER" or "SLAVE").." | GOLEM FIRST: "..#golems.." | HP "..math.floor(total), "GOLEM")
        equipTooltip("Melee")
        PHX.netHitGolemCluster(golems)
        if os.clock()-(PHX.ClusterProgressAt or os.clock()) >= CONFIG.GOLEM_AURA.STALL_SECONDS then
            PHX.eventStatus("Golem stalled -> safe approach + one physical Melee fallback", "GOLEM_RECOVERY")
            local firstPart = golems[1] and (golems[1]:FindFirstChild("HumanoidRootPart") or golems[1]:FindFirstChild("Head"))
            local currentRoot = root()
            if firstPart and currentRoot and (currentRoot.Position-firstPart.Position).Magnitude > CONFIG.GOLEM_AURA.APPROACH_DISTANCE then
                if not safeTween(CFrame.new(firstPart.Position+Vector3.new(0,CONFIG.GOLEM_AURA.HOVER_Y,0)),165,token) then return false end
            end
            if firstPart then aimAt(firstPart.Position) end
            local tool = equipTooltip("Melee")
            if tool then pcall(function() tool:Activate() end) end
            PHX.ClusterProgressAt = os.clock()
            task.wait(.2)
        end
        task.wait(CONFIG.GOLEM_AURA.ATTACK_INTERVAL)
    end
    return #PHX.liveGolems() == 0
end

-- Preserve legacy helper entry point while replacing its single-target fast loop.
function PHX.golemKillAura(golem, token)
    local island = findPrehistoric()
    return island and PHX.golemClusterBurst(island,token) or false
end

function PHX.teamEventLoop(island, token)
    enableLavaProtection(island)
    PHX.EventState.Error = nil
    local missingSince = nil
    local sawActive = false
    local completed = false
    local ok,err = pcall(function()
        while isRunning(token) and island.Parent do
            local snapshot = PHX.eventSnapshot(island)
            if snapshot.Active then sawActive = true missingSince = nil else missingSince = missingSince or os.clock() end
            if sawActive and missingSince and os.clock()-missingSince >= 1.2 then
                completed = true
                PHX.EventFinishedIslands[island] = true
                break
            end
            if not snapshot.Active then task.wait(.1) continue end
            local hh = hum()
            if not hh or hh.Health <= 0 or not root() then
                PHX.EventState.Phase = "RECOVERY"
                setStatus("Event death -> respawn and resume team phase (Magnet cache kept)")
                waitAlive(token)
                if not isRunning(token) or not island.Parent then break end
                if PHX.eventActive(island) then
                    local moved = moveToRelic(island,token)
                    if not moved and not isRunning(token) then break end
                end
                continue
            end
            if snapshot.GolemCount > 0 then
                PHX.golemClusterBurst(island,token)
            else
                local target, count = PHX.pickPressureRock(island,teamIndex(LP.Name) or 1)
                PHX.eventStatus((isMaster() and "MASTER" or "SLAVE").." | PRESSURE "..tostring(snapshot.Pressure or "?").."% | Relic "..(snapshot.Relic and string.format("%.1f",snapshot.Relic) or "?").."% | Rocks "..count,"PRESSURE")
                if target then PHX.pressureRockBurst(target,token,island) else task.wait(.1) end
            end
        end
    end)
    disableLavaProtection()
    PHX.restoreGolemChanges()
    if not ok then error(err,0) end
    return completed
end

local function masterPressureLoop(island, token)
    return PHX.teamEventLoop(island,token)
end

local function slaveGolemLoop(island, token)
    return PHX.teamEventLoop(island,token)
end


--==============================================================
-- COLLECT BONES / EGGS / DRAGON FRUIT
--==============================================================

local function interactionPart(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

function PHX.readBonesCount()
    local ok,inv = pcall(function() return CommF:InvokeServer("getInventory") end)
    if not ok or type(inv) ~= "table" then return nil end
    local count = PHX.exactMaterialCount(inv,"Dinosaur Bones")
    if count ~= nil then return count end
    if PHX.inventoryHasMaterialSchema(inv) then return 0 end
    return nil
end

local function interactCollectible(obj, token, progress)
    if not isRunning(token) then return false end
    progress = progress or {}
    local pending = progress.BonesPending
    if pending then
        local after = PHX.readBonesCount()
        if not isRunning(token) then return false end
        if pending.Attempted and pending.BeforeCount ~= nil and after ~= nil and after > pending.BeforeCount then
            progress.BonesPending = nil
            noteProgress("DINOSAUR_BONES_CONFIRMED")
            return true
        end
        if pending.Object ~= obj then return false end
    else
        if not obj or not obj.Parent then return false end
        local before = PHX.readBonesCount()
        if not isRunning(token) then return false end
        pending = {Object=obj, BeforeCount=before, Attempted=false}
        progress.BonesPending = pending
    end
    if not obj or not obj.Parent then
        PHX.pauseEvent("BONES_PICKUP_UNCONFIRMED", "Bone disappeared without fresh inventory confirmation -> paused")
        return false
    end
    local part = interactionPart(obj)
    if not part then return false end
    if not safeTween(part.CFrame*CFrame.new(0,3,0),125,token) then return false end
    local rr = root()
    if not rr or (rr.Position-part.Position).Magnitude > 8 then return false end
    aimAt(part.Position)
    setStatus("Dinosaur Bones -> mobile click/touch hold 1s")
    pending.Attempted = true
    if not PHX.holdInteraction(obj,1.0,token) then return false end
    local verifyUntil = os.clock()+1.5
    repeat
        local after = PHX.readBonesCount()
        if not isRunning(token) then return false end
        if pending.BeforeCount ~= nil and after ~= nil and after > pending.BeforeCount then
            progress.BonesPending = nil
            noteProgress("DINOSAUR_BONES_CONFIRMED")
            return true
        end
        task.wait(.15)
    until not isRunning(token) or os.clock() >= verifyUntil
    if isRunning(token) then PHX.pauseEvent("BONES_PICKUP_UNCONFIRMED", "Bone hold not confirmed by fresh inventory -> paused") end
    return false
end

local function collectBones(island, token)
    if not island or not island.Parent or not isRunning(token) then return false end
    PHX.RewardProgress = PHX.RewardProgress or setmetatable({}, {__mode="k"})
    local progress = PHX.RewardProgress[island] or {}
    PHX.RewardProgress[island] = progress
    if progress.BonesVerified then return true end
    setStatus("Rewards -> quick Dinosaur Bones sweep")
    if progress.BonesPending and not interactCollectible(progress.BonesPending.Object,token,progress) then return false end
    local deadline = os.clock()+(CONFIG.BONES.SWEEP_SECONDS or 2.5)
    local tried, interactions = {}, {}
    local quietSince = os.clock()
    while isRunning(token) and island.Parent and os.clock()<deadline do
        local found = false
        for _,obj in ipairs(island:GetDescendants()) do
            if not tried[obj] and string.lower(obj.Name):find("bone",1,true) then
                local interact = obj:FindFirstChildWhichIsA("ProximityPrompt",true)
                    or obj:FindFirstChildWhichIsA("ClickDetector",true)
                    or obj:FindFirstChildWhichIsA("TouchTransmitter",true)
                tried[obj] = true
                if interact and not interactions[interact] then
                    interactions[interact] = true
                    found = true
                    quietSince = os.clock()
                    if not interactCollectible(obj,token,progress) then return false end
                end
            end
        end
        if not found then
            if os.clock()-quietSince > .55 then
                progress.BonesVerified = true
                return true
            end
            task.wait(.08)
        end
    end
    if not isRunning(token) or not island.Parent or progress.BonesPending then return false end
    -- A bounded sweep may finish after the last verified pickup. Every input
    -- attempted above has fresh count evidence; no object disappearance is used.
    progress.BonesVerified = true
    return true
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
    return name:find("fruit",1,true) ~= nil and tip:find("fruit",1,true) ~= nil
end

function PHX.dragonVariantFromTool(tool)
    if not PHX.isDragonFruitTool(tool) then return nil end
    local variant = PHX.dragonVariantFromText(tool.Name)
        or PHX.dragonVariantFromText(tool:GetAttribute("OriginalName"))
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

function PHX.dragonToolIsLocal(tool)
    if not tool then return false end
    local ok,parent = pcall(function() return tool.Parent end)
    return ok and (parent == LP.Backpack or parent == char())
end

function PHX.reconcileDragonPending()
    if not PHX.generationAlive() then return false end
    local pending = DRAGON_GUARD_STATE.Pending
    if not pending then return not DRAGON_GUARD_STATE.Critical end
    -- Preserve the original baseline through retries and reloads. Tool removal
    -- alone can also mean death/transfer, so only fresh server inventory counts.
    DRAGON_GUARD_STATE.Critical = true
    local after = PHX.storedDragonTotal()
    if not PHX.generationAlive() then return false end
    if DRAGON_GUARD_STATE.Pending ~= pending then
        return not DRAGON_GUARD_STATE.Pending and not DRAGON_GUARD_STATE.Critical
    end
    local before = pending.BeforeCount
    if before == nil or after == nil or after <= before or PHX.dragonToolIsLocal(pending.Tool) then
        return false
    end
    DRAGON_GUARD_STATE.LastStored = pending.Label or "Dragon Fruit"
    DRAGON_GUARD_STATE.Pending = nil
    DRAGON_GUARD_STATE.Critical = false
    DRAGON_GUARD_STATE.Unconfirmed = nil
    setStatus(DRAGON_GUARD_STATE.LastStored.." stored: authoritative inventory increase confirmed")
    noteProgress("DRAGON_STORED_CONFIRMED")
    return true
end


PHX.DragonNotified = setmetatable({}, {__mode="k"})
function PHX.notifyDragonFruit(tool)
    if not PHX.isDragonFruitTool(tool) or PHX.DragonNotified[tool] then return false end
    PHX.DragonNotified[tool] = true
    local variant = PHX.dragonVariantFromTool(tool)
    local label = variant and ("Dragon ("..variant..")") or "Dragon Fruit"
    return sendWebhook("DRAGON FRUIT RECEIVED", LP.Name.." received "..label.."; storing before reset.", {
        {name="Account",value=LP.Name,inline=true},
        {name="Variant",value=tostring(variant or "Unknown"),inline=true},
        {name="Server",value=tostring(game.JobId),inline=false},
    }, variant == "East" or variant == "West")
end

function PHX.storeOneDragonFruit(tool)
    PHX.notifyDragonFruit(tool)
    if not PHX.generationAlive() then return false end
    if not PHX.isDragonFruitTool(tool) then return not DRAGON_GUARD_STATE.Pending and not DRAGON_GUARD_STATE.Critical end
    local pending = DRAGON_GUARD_STATE.Pending
    if pending then
        if PHX.reconcileDragonPending() then return true end
        if not PHX.generationAlive() then return false end
        pending = DRAGON_GUARD_STATE.Pending
        if not pending or pending.Tool ~= tool then return false end
    else
        local variant = PHX.dragonVariantFromTool(tool)
        local label = variant and ("Dragon ("..variant..")") or "Dragon Fruit"
        local storeId = tostring(tool:GetAttribute("OriginalName") or "")
        if storeId == "" or not string.lower(storeId):find("dragon",1,true) then storeId = "Dragon-Dragon" end
        local before = PHX.storedDragonTotal()
        if not PHX.generationAlive() then return false end
        pending = {Tool=tool, BeforeCount=before, StoreId=storeId, Label=label}
        -- Persist BEFORE StoreFruit yields. A new generation must retain evidence
        -- of an in-flight request even if the physical Tool is already gone.
        DRAGON_GUARD_STATE.Pending = pending
        DRAGON_GUARD_STATE.Critical = true
        DRAGON_GUARD_STATE.Unconfirmed = tool
    end
    pending.Label = pending.Label or "Dragon Fruit"
    setStatus("PHYSICAL "..pending.Label.." -> StoreFruit + fresh inventory confirmation")
    logLine("DRAGON", "physical Blox Fruit | tool="..tostring(tool.Name).." baseline="..tostring(pending.BeforeCount))
    for attempt=1,CONFIG.DRAGON_GUARD.STORE_RETRIES do
        if not PHX.generationAlive() then return false end
        if DRAGON_GUARD_STATE.Pending ~= pending then
            return not DRAGON_GUARD_STATE.Pending and not DRAGON_GUARD_STATE.Critical
        end
        local ok,result = false,nil
        if PHX.dragonToolIsLocal(tool) then
            ok,result = pcall(function() return CommF:InvokeServer("StoreFruit",pending.StoreId,tool) end)
        end
        if not PHX.generationAlive() then return false end
        task.wait(CONFIG.DRAGON_GUARD.RETRY_DELAY)
        if not PHX.generationAlive() then return false end
        logLine("DRAGON_STORE", "attempt="..attempt.." pcall="..tostring(ok).." result="..tostring(result).." stillLocal="..tostring(PHX.dragonToolIsLocal(tool)))
        if PHX.reconcileDragonPending() then return true end
    end
    if not PHX.generationAlive() then return false end
    DRAGON_GUARD_STATE.Critical = true
    PHX.pauseEvent("DRAGON_STORE_UNCONFIRMED", "Dragon storage not confirmed -> paused; reset/portal blocked")
    logLine("DRAGON_STORE_FAIL", "original fresh stored inventory baseline unavailable or unchanged")
    return false
end

local function storeDragonFruitCritical()
    if not PHX.generationAlive() then return false end
    -- Reconcile even when no physical fruit remains after a previous request.
    PHX.reconcileDragonPending()
    if not PHX.generationAlive() then return false end
    if DRAGON_GUARD_STATE.Busy then
        local deadline = os.clock()+8
        while DRAGON_GUARD_STATE.Busy and os.clock()<deadline and PHX.generationAlive() do task.wait(.05) end
        if not PHX.generationAlive() then return false end
        PHX.reconcileDragonPending()
        return not DRAGON_GUARD_STATE.Busy and not DRAGON_GUARD_STATE.Pending
            and #PHX.findPhysicalDragonFruits() == 0 and not DRAGON_GUARD_STATE.Critical
    end
    local pending = DRAGON_GUARD_STATE.Pending
    -- A failed request with its Tool still local is retryable on explicit resume.
    if DRAGON_GUARD_STATE.Critical and (not pending or not PHX.dragonToolIsLocal(pending.Tool)) then return false end
    local owner = PHX.acquireLock(DRAGON_GUARD_STATE,"Busy","DragonStoreBusy")
    if not owner then return false end
    local ok, result = pcall(function()
        for _=1,4 do
            if not PHX.generationAlive() then return false end
            local unresolved = DRAGON_GUARD_STATE.Pending
            if unresolved then
                if not PHX.storeOneDragonFruit(unresolved.Tool) then return false end
            else
                local fruits = PHX.findPhysicalDragonFruits()
                if #fruits == 0 then return not DRAGON_GUARD_STATE.Critical end
                if not PHX.storeOneDragonFruit(fruits[1]) then return false end
            end
            task.wait(.1)
        end
        return not DRAGON_GUARD_STATE.Pending and #PHX.findPhysicalDragonFruits() == 0 and not DRAGON_GUARD_STATE.Critical
    end)
    PHX.releaseLock(owner)
    if not PHX.generationAlive() then return false end
    if not ok then
        DRAGON_GUARD_STATE.Critical = true
        PHX.pauseEvent("DRAGON_GUARD_ERROR", "Dragon guard error -> paused; reset/portal blocked")
        logLine("DRAGON_GUARD_ERROR", tostring(result))
    end
    return ok and result
end

function PHX.secureDragonWindow(seconds, token)
    if not PHX.generationAlive() then return false end
    local untilAt = os.clock() + (tonumber(seconds) or 0)
    while os.clock() < untilAt do
        if (token and not isRunning(token)) or not PHX.generationAlive() then return false end
        if not storeDragonFruitCritical() then return false end
        task.wait(.08)
    end
    if (token and not isRunning(token)) or not PHX.generationAlive() then return false end
    return storeDragonFruitCritical()
end

function PHX.hookDragonContainer(container)
    if not container then return end
    PHX.connect(container.ChildAdded,function(obj)
        PHX.defer(function()
            task.wait(.05)
            if not PHX.generationAlive() then return end
            if PHX.isDragonFruitTool(obj) then
                logLine("DRAGON_WATCH", "physical fruit ChildAdded -> "..tostring(obj.Name))
                storeDragonFruitCritical()
            end
        end)
    end)
end

PHX.hookDragonContainer(LP.Backpack)
if char() then PHX.hookDragonContainer(char()) end
PHX.connect(LP.CharacterAdded,function(c)
    if not PHX.generationAlive() then return end
    PHX.hookDragonContainer(c)
    PHX.defer(function()
        task.wait(.5)
        if not PHX.generationAlive() then return end
        storeDragonFruitCritical()
    end)
end)
PHX.defer(function() storeDragonFruitCritical() end)

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

-- EGG ROSTER OBSERVER BEGIN
-- Observe before rewards spawn. Keep original model references and last positions
-- after other clients collect an egg; never reindex the remaining folder children.
PHX.EggRosters = setmetatable({}, {__mode="k"})

function PHX.captureEggRoster(state)
    local core = state.Island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    if not folder then return end
    if state.Folder and state.Folder ~= folder and next(state.Entries) ~= nil then
        state.Ambiguous = "Reward folder changed after eggs were observed"
        return
    end
    state.Folder = folder
    for _,egg in ipairs(folder:GetChildren()) do
        local entry = state.Entries[egg]
        if not entry then
            if state.Frozen then
                state.Ambiguous = "More eggs appeared after the assignment snapshot"
                return
            end
            state.LastAddedAt = os.clock()
            entry = {Egg=egg}
            state.Entries[egg] = entry
        end
        local position = eggPosition(egg)
        if position then entry.Position = position end
    end
end

function PHX.watchEggRoster(island)
    local existing = PHX.EggRosters[island]
    if existing then PHX.captureEggRoster(existing) return existing end
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    local alreadySpawned = folder and #folder:GetChildren() > 0
    local state = {Island=island, Folder=folder, Entries={}, Connections={}}
    if alreadySpawned then
        state.Ambiguous = "Observer started after eggs spawned; earlier pickups cannot be reconstructed"
    end
    PHX.EggRosters[island] = state
    state.Connections[#state.Connections+1] = PHX.connect(island.DescendantAdded, function(obj)
        if obj.Name ~= "SpawnedDragonEggs" and not (state.Folder and obj:IsDescendantOf(state.Folder)) then return end
        if state.RefreshScheduled then return end
        state.RefreshScheduled = true
        PHX.defer(function()
            state.RefreshScheduled = false
            PHX.captureEggRoster(state)
        end)
    end)
    state.Connections[#state.Connections+1] = PHX.connect(island.AncestryChanged, function()
        if not island.Parent then
            for _,connection in ipairs(state.Connections) do PHX.disconnect(connection) end
            state.Connections = {}
        end
    end)
    PHX.captureEggRoster(state)
    return state
end

function PHX.freezeEggRoster(state)
    PHX.captureEggRoster(state)
    if state.Ambiguous then return nil,state.Ambiguous end
    if state.Frozen then return state.Frozen end
    local entries = {}
    for _,entry in pairs(state.Entries) do
        if not entry.Position then return {},nil end -- existing spawn-wait loop retries without guessing a position
        entries[#entries+1] = entry
    end
    if #entries == 0 then return {},nil end
    if os.clock()-(state.LastAddedAt or os.clock()) < 1.0 then return {},nil end
    table.sort(entries, function(a,b)
        if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
        if a.Position.Z ~= b.Position.Z then return a.Position.Z < b.Position.Z end
        return a.Position.Y < b.Position.Y
    end)
    -- Duplicate coordinates have no deterministic identity ordering across clients.
    for i=2,#entries do
        local a,b = entries[i-1].Position,entries[i].Position
        if a.X == b.X and a.Y == b.Y and a.Z == b.Z then
            state.Ambiguous = "Two eggs share the same position; stable assignment is unavailable"
            return nil,state.Ambiguous
        end
    end
    state.Frozen = {}
    for _,entry in ipairs(entries) do state.Frozen[#state.Frozen+1] = entry.Egg end
    return state.Frozen
end
-- EGG ROSTER OBSERVER END


function PHX.readEggCount()
    -- Read the real server material inventory; never use optimistic UI counters.
    local ok, inv = pcall(function() return CommF:InvokeServer("getInventory") end)
    if not ok or type(inv) ~= "table" then return nil end
    local count = PHX.exactMaterialCount(inv, "Dragon Egg")
    if count ~= nil then return count end
    if PHX.inventoryHasMaterialSchema(inv) then return 0 end
    return nil
end

function PHX.confirmEggPickup(before)
    local after = PHX.readEggCount()
    return before ~= nil and after ~= nil and after > before, after
end

local function collectAssignedEgg(island, token)
    PHX.RewardProgress = PHX.RewardProgress or setmetatable({}, {__mode="k"})
    local progress = PHX.RewardProgress[island] or {}
    PHX.RewardProgress[island] = progress
    if progress.Egg then
        PHX.EventState.Egg = progress.EggState or "CONFIRMED"
        return PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS,token)
    end
    local pending = progress.EggPending
    local resumedConfirmed = pending and pending.Attempted and PHX.confirmEggPickup(pending.BeforeCount)
    if not isRunning(token) then return false end
    if resumedConfirmed then
        PHX.EventState.Egg = "CONFIRMED"
        progress.Egg, progress.EggState, progress.EggPending = true, "CONFIRMED", nil
        noteProgress("DRAGON_EGG_CONFIRMED")
        return PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS,token)
    end
    if not isRunning(token) then return false end
    local roster = PHX.watchEggRoster(island)
    PHX.EventState.Egg = "WAIT"
    PHX.EventState.Phase = "EGG"
    local deadline = os.clock()+CONFIG.EGG.SPAWN_WAIT_SECONDS
    while isRunning(token) and island.Parent and os.clock()<deadline do
        local eggs, rosterError = PHX.freezeEggRoster(roster)
        if rosterError then
            PHX.EventState.Egg = "ROSTER AMBIGUOUS"
            PHX.pauseEvent("EGG_ROSTER_AMBIGUOUS", "Egg slots ambiguous: "..rosterError.." -> paused")
            return false
        end
        if #eggs == 0 then task.wait(.1) continue end
        local folder = roster.Folder
        local ti = teamIndex(LP.Name)
        if not ti then PHX.pauseEvent("TEAM_ACCOUNT_UNKNOWN", "Account missing from team -> no egg assignment") return false end
        local rotate = math.abs(math.floor(island:GetPivot().Position.X)) % #CONFIG.TEAM
        local rank = ((ti+rotate-1)%#CONFIG.TEAM)+1
        if rank > #eggs then
            PHX.EventState.Egg = "NO SLOT"
            setStatus("No Dragon Egg assigned this run (stable original rank "..rank..")")
            progress.Egg, progress.EggState = true, "NO SLOT"
            return true
        end
        local egg = eggs[rank]
        if pending and pending.Egg ~= egg then
            PHX.pauseEvent("EGG_SLOT_CHANGED", "Original pending egg assignment changed -> paused")
            return false
        end
        -- Retain references of all original eggs, even those collected by others.
        -- Never substitute the next remaining egg after another player's pickup.
        if not egg.Parent or not egg:IsDescendantOf(folder) then
            PHX.EventState.Egg = "SLOT UNAVAILABLE"
            PHX.pauseEvent("EGG_SLOT_UNAVAILABLE", "Assigned original egg disappeared before interaction -> paused; no substitute selected")
            return false
        end
        local part = interactionPart(egg)
        if not part then PHX.pauseEvent("EGG_NO_PART", "Assigned egg has no replicated interaction part") return false end
        if not pending then
            local before = PHX.readEggCount()
            if not isRunning(token) then return false end
            pending = {Egg=egg, BeforeCount=before, Rank=rank, Attempted=false}
            progress.EggPending = pending
        end
        local before = pending.BeforeCount
        local holdTime = math.max(1.1,tonumber(CONFIG.EGG.HOLD_SECONDS) or 1.1)
        local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt",true)
        if prompt then holdTime = math.max(holdTime,(tonumber(prompt.HoldDuration) or 0)+.12) end
        local attempted, confirmed = pending.Attempted,false
        for attempt=1,CONFIG.EGG.RETRIES do
            if not isRunning(token) then return false end
            PHX.captureEggRoster(roster)
            if roster.Ambiguous then PHX.pauseEvent("EGG_ROSTER_AMBIGUOUS",roster.Ambiguous) return false end
            if not egg.Parent or not egg:IsDescendantOf(folder) then
                if attempted then confirmed = PHX.confirmEggPickup(before) end
                break
            end
            part = interactionPart(egg)
            if not part then break end
            local target = part.CFrame*CFrame.new(0,2.5,-CONFIG.EGG.APPROACH_DISTANCE)
            if not safeTween(target,125,token) then return false end
            local rr = root()
            if not rr or (rr.Position-part.Position).Magnitude > 8 then
                PHX.EventState.Egg = "TOO FAR"
                return false
            end
            aimAt(part.Position)
            PHX.EventState.Egg = "TOUCH HOLD "..attempt.."/"..CONFIG.EGG.RETRIES
            setStatus("Dragon Egg slot "..rank..": mobile click/touch hold "..string.format("%.2fs",holdTime))
            attempted, pending.Attempted = true,true
            if not PHX.holdInteraction(egg,holdTime,token) then return false end
            task.wait(CONFIG.EGG.RETRY_GAP)
            confirmed = PHX.confirmEggPickup(before)
            if confirmed then break end
        end
        -- The donor remote is a one-shot fallback after physical nearby attempts.
        -- Its FireServer return only means 'sent'; inventory must still confirm.
        if not confirmed and not pending.RemoteSent and egg.Parent and egg:IsDescendantOf(folder) and attempted and isRunning(token) then
            local p, rr = interactionPart(egg), root()
            if p and rr and (rr.Position-p.Position).Magnitude <= 8 then
                pending.RemoteSent = true
                PHX.collectDragonEggRemote()
                task.wait(.35)
                confirmed = PHX.confirmEggPickup(before)
            end
        end
        local verifyUntil = os.clock()+2
        while not confirmed and attempted and isRunning(token) and os.clock()<verifyUntil do
            task.wait(.3)
            confirmed = PHX.confirmEggPickup(before)
        end
        if not isRunning(token) then return false end
        if not confirmed then
            PHX.EventState.Egg = "UNCONFIRMED"
            PHX.pauseEvent("EGG_PICKUP_UNCONFIRMED", "Egg pickup not confirmed by fresh inventory -> paused on island")
            logLine("EGG_FAIL", "original rank="..rank.." baseline="..tostring(before).."; object removal alone is not local pickup evidence")
            return false
        end
        PHX.EventState.Egg = "CONFIRMED"
        progress.Egg, progress.EggState, progress.EggPending = true, "CONFIRMED", nil
        noteProgress("DRAGON_EGG_CONFIRMED")
        setStatus("Dragon Egg confirmed -> physical Dragon storage guard")
        return PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS,token)
    end
    if not isRunning(token) then return false end
    if next(roster.Entries) ~= nil then
        PHX.EventState.Egg = "ROSTER INCOMPLETE"
        PHX.pauseEvent("EGG_ROSTER_INCOMPLETE", "Egg snapshot incomplete -> paused, original slots preserved")
        return false
    end
    PHX.EventState.Egg = "NONE"
    logLine("EGG_NONE","No eggs spawned within wait window")
    setStatus("No Dragon Egg spawned this run")
    progress.Egg, progress.EggState = true, "NONE"
    return true
end


--==============================================================
-- DRAGON HUNTER DIALOGUE / QUESTS
--==============================================================

local function visibleGui(o)
    local p = o
    while p and p ~= PG do
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("CanvasGroup") and p.GroupTransparency >= 0.995 then return false end
        p = p.Parent
    end
    return true
end

local function dialogueGui()
    return PG:FindFirstChild("DialogueGui")
end


local function dialogueOptions()
    local dg=dialogueGui()
    if not dg or not PHX.guiVisible(dg) then return {} end
    local found={}
    for _,o in ipairs(dg:GetDescendants()) do
        if (o:IsA("TextButton") or o:IsA("ImageButton")) and PHX.guiVisible(o)
            and o.AbsoluteSize.X > 120 and o.AbsoluteSize.Y > 25 then found[#found+1]=o end
    end
    table.sort(found,function(a,b)
        if math.abs(a.AbsolutePosition.Y-b.AbsolutePosition.Y) <= 2 then return a.AbsolutePosition.X < b.AbsolutePosition.X end
        return a.AbsolutePosition.Y < b.AbsolutePosition.Y
    end)
    local options,lastY={},nil
    for _,button in ipairs(found) do
        local y=math.floor(button.AbsolutePosition.Y+.5)
        if lastY == nil or math.abs(y-lastY)>5 then options[#options+1]=button; lastY=y end
    end
    return options
end

local function fireButton(button)
    return PHX.activateOnce(button)
end

function PHX.dialogueVisualText(button)
    if not button then return "" end
    local glyphs={}
    if button:IsA("TextButton") and tostring(button.Text or "") ~= "" then
        glyphs[#glyphs+1]={X=button.AbsolutePosition.X,Y=button.AbsolutePosition.Y,Text=tostring(button.Text)}
    end
    for _,o in ipairs(button:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.guiVisible(o) then
            local text=tostring(o.Text or "")
            if text ~= "" and #text<=80 then glyphs[#glyphs+1]={X=o.AbsolutePosition.X,Y=o.AbsolutePosition.Y,Text=text} end
        end
    end
    table.sort(glyphs,function(a,b) if math.abs(a.Y-b.Y)<=3 then return a.X<b.X end; return a.Y<b.Y end)
    local pieces,seen={},{}
    for _,glyph in ipairs(glyphs) do
        local key=math.floor(glyph.X+.5)..":"..math.floor(glyph.Y+.5)..":"..glyph.Text
        if not seen[key] then seen[key]=true; pieces[#pieces+1]=glyph.Text end
    end
    return table.concat(pieces,"")
end

function PHX.compactText(value)
    return PHX.normalizeItemName(tostring(value or ""):gsub("<.->", "")):gsub("[^%w]", "")
end

function PHX.dialogueOption(options,wanted)
    local target=PHX.compactText(wanted)
    for _,button in ipairs(options or {}) do
        if PHX.compactText(PHX.dialogueVisualText(button)) == target then return button end
    end
    return nil
end

function PHX.dialogueSignature(options)
    local pieces={}
    for _,button in ipairs(options or {}) do pieces[#pieces+1]=PHX.compactText(PHX.dialogueVisualText(button)) end
    return table.concat(pieces,"|")
end

function PHX.waitDialogueMenu(oldSignature, wanted, token, timeout)
    local deadline=os.clock()+(timeout or 2)
    repeat
        if not isRunning(token) then return nil,"STOPPED" end
        local options=dialogueOptions()
        local signature=PHX.dialogueSignature(options)
        local button=PHX.dialogueOption(options,wanted)
        if button and (oldSignature == nil or signature ~= oldSignature) then return button,options end
        task.wait(.04)
    until os.clock() >= deadline
    return nil,"MENU_NOT_CONFIRMED:"..wanted
end

function PHX.dialogueIsDragonHunter()
    local dg=dialogueGui()
    if not dg or not PHX.guiVisible(dg) then return false end
    for _,o in ipairs(dg:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.guiVisible(o)
            and PHX.compactText(o.Text):find("dragonhunter",1,true) then return true end
    end
    return false
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

PHX.ActiveQuestKind = PHX.ActiveQuestKind or "NONE"
PHX.ActiveQuestText = PHX.ActiveQuestText or ""

function PHX.questTextFromValue(response)
    if response == nil then return "" end
    local found = ""
    local seen = {}
    local function walk(v, depth)
        if found ~= "" or depth > 10 then return end
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
    walk(response,0)
    return found
end

function PHX.questKindFromText(text)
    local l = string.lower(tostring(text or ""))
    if l:find("hydra enforcer",1,true) then return "HYDRA" end
    if l:find("venomous assailant",1,true) then return "VENOM" end
    if l:find("destroy",1,true) and l:find("tree",1,true) then return "TREE" end
    return "NONE"
end

function PHX.questTextFromVisibleGui()
    for _,v in ipairs(PHX.gameGuiDescendants(PG)) do
        if (v:IsA("TextLabel") or v:IsA("TextButton")) and visibleGui(v) then
            local t = tostring(v.Text or "")
            if PHX.questKindFromText(t) ~= "NONE" then return t end
        end
    end
    return ""
end

function PHX.latchQuest(text, source)
    local kind = PHX.questKindFromText(text)
    if kind == "NONE" then return false end
    PHX.ActiveQuestKind = kind
    PHX.ActiveQuestText = tostring(text or kind)
    PHX.LastQuestAcceptedAt = os.clock()
    PHX.QuestCompletedAt = -math.huge
    PHX.QuestCompletedText = ""
    local msg = tostring(source or "QUEST").." | QUEST "..kind.." | "..PHX.ActiveQuestText
    setStatus(msg)
    logLine("DRAGON_HUNTER_QUEST", msg)
    noteProgress("QUEST_ACCEPTED:"..kind)
    return true
end

function PHX.dragonHunterCheckText()
    return PHX.questTextFromValue(PHX.dragonHunterCheckRaw())
end

local function questText()
    if PHX.ActiveQuestKind and PHX.ActiveQuestKind ~= "NONE"
        and (PHX.QuestCompletedAt or -math.huge) < (PHX.LastQuestAcceptedAt or -math.huge) then
        return PHX.ActiveQuestText or PHX.ActiveQuestKind
    end

    local direct = PHX.dragonHunterCheckText()
    if direct ~= "" then return direct end
    return PHX.questTextFromVisibleGui()
end

local function questKind()
    if PHX.ActiveQuestKind and PHX.ActiveQuestKind ~= "NONE"
        and (PHX.QuestCompletedAt or -math.huge) < (PHX.LastQuestAcceptedAt or -math.huge) then
        return PHX.ActiveQuestKind
    end
    return PHX.questKindFromText(questText())
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
    local raw = tostring(text or ""):gsub("<.->", ""):gsub("^%s+",""):gsub("%s+$","")
    local l = string.lower(raw)
    -- Do not use substring matching: our own status/help text contains the words
    -- "Quest Completed", which caused false positives in the probe.
    local exact = (l == "task completed" or l == "task completed!"
        or l == "quest completed" or l == "quest completed!")
    if exact then
        PHX.QuestCompletedAt = os.clock()
        PHX.QuestCompletedText = raw
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
    PHX.connect(obj:GetPropertyChangedSignal("Text"), inspect)
    PHX.connect(obj:GetPropertyChangedSignal("Visible"), inspect)
    inspect()
end

for _,obj in ipairs(PHX.gameGuiDescendants(PG)) do pcall(PHX.watchQuestPopupObject, obj) end
PHX.connect(PG.DescendantAdded, function(obj) pcall(PHX.watchQuestPopupObject, obj) end)


function PHX.fireDragonHunterWorldInteract()
    local npcPos=CONFIG.DRAGON_HUNTER.NPC.Position
    local candidates={}
    for _,o in ipairs(workspace:GetDescendants()) do
        if o:IsA("ClickDetector") then
            local part=o.Parent
            if not part or not part:IsA("BasePart") then
                local model=o:FindFirstAncestorOfClass("Model")
                part=model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart",true))
            end
            if part then
                local path=PHX.compactText(o:GetFullName())
                local distance=(part.Position-npcPos).Magnitude
                if distance<=26 and path:find("dragonhunter",1,true)
                    and not path:find("uzoth",1,true) and not path:find("dragontalon",1,true) then
                    candidates[#candidates+1]={Detector=o,Distance=distance}
                end
            end
        end
    end
    table.sort(candidates,function(a,b) return a.Distance<b.Distance end)
    for _,candidate in ipairs(candidates) do
        if type(fireclickdetector)=="function" then
            local ok=pcall(function() fireclickdetector(candidate.Detector) end)
            if ok then return true,"DRAGON_HUNTER_CLICKDETECTOR" end
        end
    end
    return false,"CLICKDETECTOR_UNAVAILABLE"
end

function PHX.clickDragonHunterScreen(token)
    local camera=workspace.CurrentCamera
    if not camera or not isRunning(token) then return false end
    local npcPos=CONFIG.DRAGON_HUNTER.NPC.Position+Vector3.new(0,2,0)
    local original=camera.CFrame
    local success=false
    PHX.inputPassthrough(function()
        camera.CFrame=CFrame.lookAt(camera.CFrame.Position,npcPos)
        task.wait(.05)
        local point,onScreen=camera:WorldToViewportPoint(npcPos)
        if not onScreen then return end
        local inset=select(1,game:GetService("GuiService"):GetGuiInset())
        for _,offset in ipairs({inset,Vector2.zero}) do
            if not isRunning(token) then break end
            PHX.mouseEvent(point.X+offset.X,point.Y+offset.Y,0,true,game,0)
            task.wait(.07)
            PHX.mouseEvent(point.X+offset.X,point.Y+offset.Y,0,false,game,0)
            if PHX.waitGui(function() return PHX.dialogueIsDragonHunter() and #dialogueOptions()>=3 end,.6) then success=true; break end
        end
    end)
    -- A deliberate NPC click must not leave the camera view locked afterward.
    if camera.Parent then pcall(function() camera.CFrame=original end) end
    return success
end

local function openDragonHunter(token)
    if not safeTween(CONFIG.DRAGON_HUNTER.STAND,200,token) then return false end
    task.wait(.25)
    local dg=dialogueGui()
    if dg and PHX.DialogueLocallyHidden then
        if dg:IsA("ScreenGui") then dg.Enabled=true elseif dg:IsA("GuiObject") then dg.Visible=true end
        PHX.DialogueLocallyHidden=false
    end
    for attempt=1,6 do
        if not isRunning(token) then return false end
        if PHX.dialogueIsDragonHunter() and #dialogueOptions()>=3 then return true end
        local worldOK,mode=PHX.fireDragonHunterWorldInteract()
        if worldOK and PHX.waitGui(function() return PHX.dialogueIsDragonHunter() and #dialogueOptions()>=3 end,.7) then return true end
        logLine("DRAGON_HUNTER_CLICK",tostring(mode).." | attempt="..attempt)
        if PHX.clickDragonHunterScreen(token) then return true end
        task.wait(.12)
    end
    return false
end

-- Close only the accepted final speech bubble; no synthetic E interaction.

function PHX.dismissDragonHunterFinalBubble()
    -- V2.9.5: never press the world interact again to close a bubble.
    -- The Hunt path is remote-only; if stale DialogueGui exists, hide it locally.
    local dg = dialogueGui()
    if not dg then return true end
    if dg:IsA("ScreenGui") then
        pcall(function() dg.Enabled = false end)
        PHX.DialogueLocallyHidden = true
    elseif dg:IsA("GuiObject") then
        pcall(function() dg.Visible = false end)
        PHX.DialogueLocallyHidden = true
    end
    logLine("DRAGON_HUNTER_DISMISS", "local dialogue cleanup only; no world click")
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



function PHX.acceptHuntViaDialogue(token)
    setStatus("Dragon Hunter CLICK -> Hunt / Sure")
    if not openDragonHunter(token) then return false end
    local hunt,rootOptions=PHX.waitDialogueMenu(nil,"Hunt",token,1.4)
    if not hunt then return false end
    local oldSignature=PHX.dialogueSignature(rootOptions)
    if not fireButton(hunt) then return false end
    local sure=PHX.waitDialogueMenu(oldSignature,"Sure",token,1.8)
    if not sure then
        local t=PHX.questTextFromVisibleGui()
        if t ~= "" and PHX.latchQuest(t,"VISIBLE HUNT ACCEPTED") then PHX.dismissDragonHunterFinalBubble(); return true end
        return false
    end
    if not fireButton(sure) then return false end
    local deadline=os.clock()+2.0
    while isRunning(token) and os.clock()<deadline do
        local text=PHX.dragonHunterCheckText()
        if text=="" then text=PHX.questTextFromVisibleGui() end
        if text ~= "" and PHX.latchQuest(text,"HUNT/SURE CONFIRMED") then PHX.dismissDragonHunterFinalBubble(); return true end
        task.wait(.10)
    end
    return false
end

local function receiveDragonHunterQuest(token)
    local existing=PHX.dragonHunterCheckText()
    if existing=="" then existing=PHX.questTextFromVisibleGui() end
    if existing ~= "" then return PHX.latchQuest(existing,"EXISTING QUEST") end
    return PHX.acceptHuntViaDialogue(token)
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


function PHX.startTreeHover(targetCF, token)
    local rr=root()
    if not rr then return function() end end
    local body=Instance.new("BodyPosition")
    body.Name="PH_TreeHover"
    body.MaxForce=Vector3.new(1e6,1e6,1e6)
    body.P,body.D=32000,1800
    body.Position=targetCF.Position
    body.Parent=rr
    local active=true
    local connection
    local function stop()
        active=false
        if connection then connection:Disconnect(); connection=nil end
        if body and body.Parent then body:Destroy() end
        if rr and rr.Parent then rr.AssemblyLinearVelocity=Vector3.zero; rr.AssemblyAngularVelocity=Vector3.zero end
    end
    connection=PHX.connect(RunService.Heartbeat, function()
        if not active or not isRunning(token) or rr ~= root() or not rr.Parent or not hum() or hum().Health<=0
            or (rr.Position-targetCF.Position).Magnitude>18 then stop(); return end
        body.Position=targetCF.Position
        rr.AssemblyLinearVelocity=Vector3.zero
        rr.AssemblyAngularVelocity=Vector3.zero
    end)
    return stop
end

function PHX.treeSkillsNoViewLock(token)
    local keys={Enum.KeyCode.X,Enum.KeyCode.C,Enum.KeyCode.V,Enum.KeyCode.F}
    for _,tooltip in ipairs({"Melee","Blox Fruit"}) do
        if not isRunning(token) then return false end
        if equipTooltip(tooltip) then
            task.wait(.12)
            for _=1,2 do
                for _,key in ipairs(keys) do
                    if not isRunning(token) or not hum() or hum().Health<=0 then return false end
                    pressKey(key,.10)
                    task.wait(.16)
                end
                task.wait(.05)
            end
        end
        task.wait(.08)
    end
    return true
end

local function farmTreeQuest(token)
    local i=1
    local started=PHX.LastQuestAcceptedAt
    if not started or started == -math.huge then started=os.clock() end
    while isRunning(token) and not PHX.questCompleteSince(started) do
        if not waitAlive(token) then return false end
        local hover=CONFIG.TREES[i]*CFrame.new(0,10,0)
        setStatus("QUEST TREE | saved point "..i.."/"..#CONFIG.TREES.." | Melee XCVF + Fruit XCVF")
        if not safeTween(hover,180,token) then return false end
        local stopHover=PHX.startTreeHover(hover,token)
        local ok,result=xpcall(function() return PHX.treeSkillsNoViewLock(token) end,function(err) return tostring(err) end)
        stopHover()
        if not ok then logLine("TREE_ERROR",result); return false end
        PHX.pulseBlazeCollectRemote()
        PHX.touchVisibleBlaze(token,false)
        if PHX.questCompleteSince(started) then break end
        i=i%#CONFIG.TREES+1
        task.wait(.08)
    end
    if PHX.questCompleteSince(started) then PHX.ActiveQuestKind="NONE"; PHX.ActiveQuestText=""; return true end
    return false
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
                PHX.spawn(function()
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
    if os.clock() - (PHX.ForestBringAt or -math.huge) < .25 then return end
    PHX.ForestBringAt = os.clock()
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
            local _, mobRoot = forestHumRoot(m)
            if mobRoot and (mobRoot.Position-anchorCF.Position).Magnitude >= 12 then hardLockForestMob(m,anchorCF) end
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

PHX.connect(RunService.Stepped, maintainForestMagnet)
PHX.connect(RunService.Heartbeat, maintainForestMagnet)

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
    local rr,h=root(),hum()
    if not rr or not h or h.Health<=0 or h.SeatPart or (rr.Position-targetCF.Position).Magnitude>12 then return false end
    rr.AssemblyLinearVelocity=Vector3.zero
    rr.AssemblyAngularVelocity=Vector3.zero
    local att=Instance.new("Attachment")
    att.Name="PH_RigidHoverAttachment"
    att.Parent=rr
    local ap=Instance.new("AlignPosition")
    ap.Name="PH_RigidHoverPosition"
    ap.Mode=Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0=att
    ap.ApplyAtCenterOfMass=true
    ap.Position=targetCF.Position
    ap.MaxForce=1e6
    ap.MaxVelocity=25
    ap.Responsiveness=45
    ap.RigidityEnabled=false
    ap.Parent=rr
    ACTIVE_HOVER.Root,ACTIVE_HOVER.Humanoid,ACTIVE_HOVER.Attachment=rr,h,att
    ACTIVE_HOVER.Position,ACTIVE_HOVER.Gyro,ACTIVE_HOVER.Target=ap,nil,targetCF
    return true
end

local function maintainStableHover(targetCF)
    local rr=root()
    if not rr or not hum() or hum().Health<=0 or hum().SeatPart then stopStableHover(); return false end
    if (rr.Position-targetCF.Position).Magnitude>18 then stopStableHover(); return false end
    if ACTIVE_HOVER.Root ~= rr or not ACTIVE_HOVER.Position or not ACTIVE_HOVER.Position.Parent then return startStableHover(targetCF) end
    ACTIVE_HOVER.Target=targetCF
    ACTIVE_HOVER.Position.Position=targetCF.Position
    rr.AssemblyLinearVelocity=Vector3.zero
    rr.AssemblyAngularVelocity=Vector3.zero
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
                    if not maintainStableHover(farmCF) then
                        if not safeTween(farmCF,180,token) then break end
                        if not startStableHover(farmCF) then break end
                    end

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


function PHX.craftWindow()
    local craft=PG:FindFirstChild("Craft")
    if not craft or not PHX.guiVisible(craft) then return nil end
    local window=craft:FindFirstChild("Window")
    if window and PHX.guiVisible(window) then return window end
    return nil
end

function PHX.craftWindowRecipe(window)
    if not window or not PHX.guiVisible(window) then return nil end
    -- Restrict proof to selected title/recipe headers, never a material/candidate list.
    local matches={}
    for _,o in ipairs(window:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.guiVisible(o) then
            local text=PHX.compactText(o.Text)
            if text=="dragonheart" or text=="dragonstorm" or text=="volcanicmagnet" then
                local path=PHX.compactText(o:GetFullName())
                if not path:find("tilegrid",1,true) and not path:find("recipelist",1,true)
                    and not path:find("scroll",1,true) and not path:find("material",1,true) then matches[text]=true end
            end
        end
    end
    local only,count=nil,0
    for text in pairs(matches) do only=text; count=count+1 end
    return count==1 and only or nil
end

function PHX.closeCraftWindow()
    local window=PHX.craftWindow()
    if not window then return true end
    for _,o in ipairs(window:GetDescendants()) do
        if (o:IsA("TextButton") or o:IsA("ImageButton")) and PHX.guiVisible(o) then
            local text=o:IsA("TextButton") and PHX.normalizeItemName(o.Text) or ""
            if PHX.normalizeItemName(o.Name):find("close",1,true) or text=="x" or text=="×" or text=="close" then
                fireButton(o)
                return PHX.waitGui(function() return PHX.craftWindow()==nil end,1)
            end
        end
    end
    return false
end

local function craftVolcanicMagnet(token)
    if not isRunning(token) then return false end
    if not PHX.StashBaselineReady then
        local ready,why=PHX.authoritativeStash(false,"precraft baseline")
        if not ready then setStatus("Craft paused: Stash unknown | "..tostring(why)); return false end
    end
    local beforeMagnet=PHX.cachedMaterialCount("Volcanic Magnet")
    if beforeMagnet == nil then return false end
    if beforeMagnet>0 then return true end
    if not goHydra(token) then setStatus("Hydra portal failed - craft cancelled"); return false end
    local stale=PHX.craftWindow()
    if stale and not PHX.closeCraftWindow() then setStatus("Close stale Craft window before retry"); return false end
    if not openDragonHunter(token) then setStatus("Dragon Hunter CLICK failed"); return false end
    local rootCraft,rootOptions=PHX.waitDialogueMenu(nil,"Craft",token,1.5)
    if not rootCraft then setStatus("Root Hunt / Craft / Gacha menu not confirmed"); return false end
    local signature=PHX.dialogueSignature(rootOptions)
    if not fireButton(rootCraft) then return false end
    local magnet,recipeOptions=PHX.waitDialogueMenu(signature,"Volcanic Magnet",token,2)
    if not magnet then setStatus("Volcanic Magnet recipe option missing"); return false end
    signature=PHX.dialogueSignature(recipeOptions)
    if not fireButton(magnet) then return false end
    local finalCraft=PHX.waitDialogueMenu(signature,"Craft",token,2)
    if not finalCraft then
        setStatus("Final Craft absent | needs 10 Scrap + 15 Ember")
        PHX.closeDragonHunterDialogue()
        return false
    end
    if not fireButton(finalCraft) then return false end
    if not PHX.waitGui(function() return PHX.craftWindow()~=nil end,2.5) then setStatus("Craft.Window not visible"); return false end
    local window=PHX.craftWindow()
    if PHX.craftWindowRecipe(window) ~= "volcanicmagnet" then
        setStatus("Wrong or unverified recipe: refused confirmation")
        PHX.closeCraftWindow()
        return false
    end
    local info=window:FindFirstChild("Info")
    local confirm=info and info:FindFirstChild("Confirm")
    confirm=PHX.stashTileClickTarget(confirm)
    if not confirm or not PHX.guiVisible(confirm) then setStatus("Craft confirm missing"); return false end
    local beforeScrap=PHX.cachedMaterialCount("Scrap Metal")
    local beforeEmber=PHX.cachedMaterialCount("Blaze Ember")
    PHX.PickupSuppress["Volcanic Magnet"]={Until=os.clock()+8}
    if not isRunning(token) or not fireButton(confirm) then PHX.PickupSuppress["Volcanic Magnet"]=nil; return false end
    if not PHX.waitGui(function() return PHX.craftWindow()==nil end,3.5) then
        PHX.PickupSuppress["Volcanic Magnet"]=nil
        setStatus("Craft window still open: no verified craft")
        return false
    end
    task.wait(.45)
    local synced,why=false,"NOT_READ"
    for attempt=1,3 do
        if not isRunning(token) then break end
        synced,why=PHX.authoritativeStash(true,"postcraft verify "..attempt.."/3")
        if synced then break end
        task.wait(.65)
    end
    PHX.PickupSuppress["Volcanic Magnet"]=nil
    if not synced then
        PHX.CraftVerificationBlocked=true
        setStatus("POSTCRAFT STASH VERIFY FAILED | "..tostring(why))
        return false
    end
    PHX.CraftVerificationBlocked=false
    local after=PHX.cachedMaterialCount("Volcanic Magnet")
    local scrapAfter=PHX.cachedMaterialCount("Scrap Metal")
    local emberAfter=PHX.cachedMaterialCount("Blaze Ember")
    if after and after-beforeMagnet>=1 then
        -- No synthetic -10/-15/+1: all counters already replaced by real Stash data.
        if PHX.updateMagnetCache then PHX.updateMagnetCache(after,"CRAFT_VERIFIED") end
        setStatus("VERIFIED Volcanic Magnet +"..(after-beforeMagnet))
        logLine("CRAFT_OK","magnet="..beforeMagnet.."->"..after.." scrap="..tostring(beforeScrap).."->"..tostring(scrapAfter).." ember="..tostring(beforeEmber).."->"..tostring(emberAfter))
        return true
    end
    setStatus("Craft unchanged: counters repaired from Stash")
    return false
end

local function recoverMagnet(token)
    local synced,why=PHX.authoritativeStash(false,"magnet material baseline")
    if not synced then setStatus("MAGNET CHECK UNKNOWN | "..tostring(why)); return false end
    local count=PHX.cachedMaterialCount("Volcanic Magnet")
    if count and count>0 then return true end
    if PHX.CraftVerificationBlocked then
        -- A prior unknown craft result must be resolved before spending materials again.
        synced,why=PHX.authoritativeStash(true,"retry postcraft verification")
        if not synced then setStatus("Craft verification still blocked | "..tostring(why)); return false end
        PHX.CraftVerificationBlocked=false
        count=PHX.cachedMaterialCount("Volcanic Magnet")
        if count and count>0 then return true end
    end
    for attempt=1,4 do
        if not isRunning(token) then return false end
        local scrap=PHX.cachedMaterialCount("Scrap Metal")
        local ember=PHX.cachedMaterialCount("Blaze Ember")
        if scrap==nil or ember==nil then setStatus("Material baseline unavailable"); return false end
        if scrap<10 and not farmScrap(token) then return false end
        if not isRunning(token) then return false end
        if ember<15 and not farmBlazeEmbers(token) then return false end
        if not isRunning(token) then return false end
        if craftVolcanicMagnet(token) then return true end
        if PHX.CraftVerificationBlocked then return false end
        -- One verified failed Craft can safely repair stale pickup deltas; no hunt/recovery spam.
        synced,why=PHX.authoritativeStash(true,"failed craft material diagnosis")
        if not synced then setStatus("Craft diagnosis unavailable | "..tostring(why)); return false end
        task.wait(.35)
    end
    setStatus("RECOVERY FAILED: no verified Volcanic Magnet")
    return false
end

--==============================================================
-- COMPLETE EVENT FLOW
--==============================================================

-- Keep reward checkpoints on the captured island, so Stop/Start never repeats a
-- finished Fossil event or substitutes another egg after a verified pickup.
PHX.EventFinishedIslands = PHX.EventFinishedIslands or setmetatable({}, {__mode="k"})
PHX.RewardProgress = PHX.RewardProgress or setmetatable({}, {__mode="k"})
PHX.CompletedIslands = PHX.CompletedIslands or setmetatable({}, {__mode="k"})

local function runPrehistoricEvent(island, token)
    if not island or not isRunning(token) then return false end
    local alreadyCompleted = PHX.CompletedIslands[island] == true
    if not alreadyCompleted and not island.Parent then return false end
    local progress = PHX.RewardProgress[island]
    if not progress then
        progress = {}
        PHX.RewardProgress[island] = progress
    end
    PHX.EventState.Egg, PHX.EventState.Error = progress.EggState or "WAIT", nil

    if not alreadyCompleted then
        PHX.watchEggRoster(island)
        local key = tostring(math.floor(island:GetPivot().Position.X))..":"..tostring(math.floor(island:GetPivot().Position.Z))
        if isMaster() and lastIslandWebhookKey ~= key then
            lastIslandWebhookKey = key
            sendWebhook("🌋 PREHISTORIC ISLAND FOUND", "Team moving to captured Fossil pose.", {
                {name="Server",value=tostring(game.JobId),inline=false},
                {name="Account",value=LP.Name,inline=true},
                {name="Role",value=roleText(),inline=true},
            })
        end

        if not PHX.EventFinishedIslands[island] then
            setStatus("Prehistoric found -> disembark -> captured Fossil pose")
            if not moveToRelic(island,token) then return false end
            if isMaster() then
                if not startEventAsMaster(island,token) then return false end
            else
                local deadline = os.clock()+CONFIG.FOSSIL.TEAM_WAIT_SECONDS+10
                PHX.EventState.Phase = "WAIT_MASTER"
                while isRunning(token) and island.Parent and not PHX.eventActive(island) and os.clock()<deadline do
                    local target = PHX.capturedFossilTarget(island)
                    local rr, hh = root(), hum()
                    if not rr or not hh or hh.Health <= 0 then
                        waitAlive(token)
                        if isRunning(token) then moveToRelic(island,token) end
                    elseif target and (rr.Position-target.Position).Magnitude > 25 then
                        moveToRelic(island,token)
                    end
                    PHX.eventStatus("SLAVE: waiting for Master's Fossil start","WAIT_MASTER")
                    task.wait(.2)
                end
                if isRunning(token) and not PHX.eventActive(island) then
                    PHX.pauseEvent("MASTER_EVENT_TIMEOUT", "Master event start not observed -> paused at Fossil")
                    return false
                end
            end
            if not isRunning(token) or not island.Parent or not PHX.eventActive(island) then return false end
            local completed
            if isMaster() then completed = masterPressureLoop(island,token) else completed = slaveGolemLoop(island,token) end
            if completed then PHX.EventFinishedIslands[island] = true end
            if not PHX.EventFinishedIslands[island] or not isRunning(token) then return false end
            task.wait(.35)
        end
        if not isRunning(token) or not island.Parent then return false end

        -- Dragon Egg has first reward priority. Save inventory-confirmed pickup
        -- even if its subsequent storage guard pauses; that guard resumes below.
        if not progress.Egg then
            PHX.EventState.Phase = "EGG"
            setStatus("Event ended -> assigned Dragon Egg first")
            local eggCompleted = collectAssignedEgg(island,token)
            if eggCompleted == true or PHX.EventState.Egg == "CONFIRMED" then
                progress.Egg = true
                progress.EggState = PHX.EventState.Egg
                if eggCompleted == true then progress.PostEggGuard = true end
            end
            if eggCompleted ~= true or not isRunning(token) then return false end
        end
        if progress.EggState == "CONFIRMED" and not progress.PostEggGuard then
            PHX.EventState.Phase = "REWARD_GUARD"
            setStatus("Dragon Egg already confirmed -> resume Dragon storage guard")
            if not PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.POST_EGG_GUARD_SECONDS,token) then return false end
            progress.PostEggGuard = true
            if not isRunning(token) then return false end
        end

        if not progress.Bones then
            PHX.EventState.Phase = "BONES"
            if CONFIG.BONES.ENABLED then
                -- collectBones must return true only for a completed, verified
                -- sweep. False/nil keeps this checkpoint pending for resume.
                if collectBones(island,token) ~= true then return false end
            end
            progress.Bones = true
        end
        if not isRunning(token) then return false end
    end

    -- Always perform a fresh guard before departure, including a resumed reset.
    PHX.EventState.Phase = "REWARD_GUARD"
    setStatus("Reward verification -> Dragon storage guard before reset")
    if not PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.PRE_RESET_GUARD_SECONDS,token) then return false end
    progress.Guard = true
    if not alreadyCompleted then
        -- Persist completion before any Stop, reset, or island removal can cause
        -- rediscovery to try the Fossil or reward collection again.
        PHX.CompletedIslands[island] = true
        PHX.EventState.Phase = "DONE"
        noteProgress("EVENT_COMPLETED")
        if PHX.invalidateMagnetCache then PHX.invalidateMagnetCache() end
    else
        PHX.EventState.Phase = "DONE"
    end
    if not isRunning(token) then return false end
    task.wait(.5)
    if not isRunning(token) then return false end
    PHX.PendingDepartureIsland=island
    if resetBackToTiki and not resetBackToTiki(token) then return false end
    PHX.PendingDepartureIsland=nil
    if not isRunning(token) then return false end
    local magnet = hasVolcanicMagnet()
    if magnet == false then return recoverMagnet(token) end
    return magnet == true
end

--==============================================================
-- SMART PREFLIGHT
--==============================================================

local function scanTeamPreflight(token)
    if not waitAlive(token) then return {Interrupted=true} end
    pcall(ensureMarines)
    local master=PHX.playerByName(ENV.TeamConfig.MasterName)
    local magnet=hasVolcanicMagnet()
    return {MasterPlayer=master,MasterOnline=master~=nil,Boat=getMasterBoat(),Island=findPrehistoric(),
        Magnet=magnet,MagnetKnown=magnet~=nil,Region=getRegion()}
end

local function waitForMasterOnline(token)
    while isRunning(token) do
        local p = PHX.playerByName(ENV.TeamConfig.MasterName)
        if p then return p end
        setStatus("MASTER "..tostring(ENV.TeamConfig.MasterName).." offline -> waiting, no teleport")
        task.wait(1)
    end
end

--==============================================================
-- MASTER / SLAVE CYCLES
--==============================================================

function PHX.requireMagnet(pre,token)
    if pre.Magnet==nil then
        setStatus("Magnet UNKNOWN: authoritative Stash sync required; hunt paused")
        PHX.TeamPhase="MAGNET_UNKNOWN"
        task.wait(2)
        return false
    end
    if pre.Magnet==false then
        PHX.TeamPhase="MAGNET_FARM"
        if not recoverMagnet(token) then return false end
        return hasVolcanicMagnet()==true
    end
    return true
end

local function masterCycle(token)
    local pre=scanTeamPreflight(token)
    if pre.Interrupted then return end
    if pre.Island then PHX.stopBoat(pre.Boat); runPrehistoricEvent(pre.Island,token); return end
    if not PHX.requireMagnet(pre,token) then return end
    local boat=pre.Boat or getMasterBoat()
    local r=root()
    if boat and r and (boat:GetPivot().Position-r.Position).Magnitude>8000 and
        (boat:GetPivot().Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude>5200 then
        -- A previous life left the boat offshore. Rebuy at the saved rendezvous instead of giant player travel.
        PHX.stopBoat(boat)
        PHX.RejectedBoats[boat]=true
        PHX.TeamPhase="RECOVERY"; PHX.BoatState="OFFSHORE_RESPAWN"
        boat=nil
    end
    if not boat then boat=buyGrandBrigade(token) end
    if not boat then setStatus("MASTER RECOVERY: boat unavailable; keep Magnet cache"); task.wait(1); return end
    PHX.stopBoat(boat)
    if not boardBoat(boat,token) then
        PHX.TeamPhase="RECOVERY"; PHX.BoatState="DRIVER_SEAT_FAILED"
        setStatus("MASTER driver seat failed; retry without Stash check")
        task.wait(.5); return
    end
    PHX.TeamPhase="BOARDING"; PHX.BoatState="WAIT_PASSENGERS"
    while PHX.travelAlive(token) and PHX.boatAlive(boat) do
        local island=findPrehistoric()
        if island then PHX.stopBoat(boat); runPrehistoricEvent(island,token); return end
        local h=hum()
        local driver=PHX.findDriverSeat(boat)
        if not h or h.Health<=0 or h.SeatPart~=driver then PHX.TeamPhase="RECOVERY"; return end
        local aboard=countTeamAboard(boat)
        if PHX.crewReady(boat) then break end
        if (boat:GetPivot().Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude>5200 then
            for _,name in ipairs(CONFIG.TEAM) do
                local player=PHX.playerByName(name)
                local rr=player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local hh=player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                if rr and hh and hh.Health>0 and (rr.Position-boat:GetPivot().Position).Magnitude>8000 then
                    PHX.stopBoat(boat)
                    PHX.RejectedBoats[boat]=true
                    PHX.TeamPhase="RECOVERY"; PHX.BoatState="TEAM_RESPAWN_RENDEZVOUS"
                    setStatus("Team respawn far offshore -> rebuy/reboard at Tiki; keep Magnet cache")
                    if not PHX.returnToDealer(token) then return end
                    return
                end
            end
        end
        setStatus("MASTER: aboard "..aboard.."/5; need driver + "..(tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3).." passengers")
        PHX.stopBoat(boat)
        task.wait(.5)
    end
    if not PHX.travelAlive(token) then PHX.stopBoat(boat); return end
    if not PHX.boatAlive(boat) then PHX.TeamPhase="RECOVERY"; return end
    local island=searchSeaUntilIsland(boat,token)
    if island then runPrehistoricEvent(island,token) end
end

local function slaveCycle(token)
    local pre=scanTeamPreflight(token)
    if pre.Interrupted then return end
    if pre.Island then runPrehistoricEvent(pre.Island,token); return end
    if not pre.MasterOnline then
        PHX.TeamPhase="WAIT_MASTER"
        if not waitForMasterOnline(token) then return end
    end
    if not PHX.requireMagnet(pre,token) then return end
    local boat=getMasterBoat()
    while PHX.travelAlive(token) and not boat do
        PHX.TeamPhase="WAIT_MASTER"; PHX.BoatState="WAIT_MASTER_BOAT"
        local island=findPrehistoric()
        if island then runPrehistoricEvent(island,token); return end
        -- Tiki preparation allows the deterministic boarding rendezvous; never buy/drive as a slave.
        if getRegion()~="TIKI" and not PHX.returnToDealer(token) then task.wait(1); return end
        setStatus("SLAVE: waiting MASTER Grand Brigade at Tiki")
        task.wait(.5)
        boat=getMasterBoat()
    end
    if not PHX.travelAlive(token) or not PHX.boatAlive(boat) then return end
    local r=root()
    local master=PHX.playerByName(ENV.TeamConfig.MasterName)
    local masterRoot=master and master.Character and master.Character:FindFirstChild("HumanoidRootPart")
    if masterRoot and (masterRoot.Position-boat:GetPivot().Position).Magnitude>8000 and
        (boat:GetPivot().Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude>5200 then
        PHX.TeamPhase="WAIT_MASTER"; PHX.BoatState="MASTER_REBUYING"
        setStatus("MASTER respawned away from old boat -> waiting new Tiki rendezvous")
        task.wait(1)
        return
    end
    if r and (r.Position-boat:GetPivot().Position).Magnitude>8000 then
        if (boat:GetPivot().Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude<=5200 then
            if not PHX.returnToDealer(token) then return end
        else
            -- MASTER observes our replicated respawn and starts a new Tiki rendezvous.
            PHX.TeamPhase="RECOVERY"; PHX.BoatState="WAIT_TIKI_RENDEZVOUS"
            setStatus("SLAVE far from offshore boat -> waiting MASTER rebuy/reboard at Tiki")
            task.wait(1)
            return
        end
    end
    if not boardBoat(boat,token) then
        PHX.TeamPhase="RECOVERY"; PHX.BoatState="PASSENGER_SEAT_FAILED"
        setStatus("SLAVE passenger seat retry; keep Magnet cache")
        task.wait(.5); return
    end
    PHX.TeamPhase="SAILING"; PHX.BoatState="PASSENGER_SEATED"
    while PHX.travelAlive(token) and PHX.boatAlive(boat) do
        local island=findPrehistoric()
        if island then runPrehistoricEvent(island,token); return end
        local h=hum()
        if not h or h.Health<=0 then PHX.TeamPhase="RECOVERY"; return end
        local masterPlayer=PHX.playerByName(ENV.TeamConfig.MasterName)
        local rr=masterPlayer and masterPlayer.Character and masterPlayer.Character:FindFirstChild("HumanoidRootPart")
        if rr and (rr.Position-boat:GetPivot().Position).Magnitude>8000 then
            PHX.TeamPhase="RECOVERY"
            if stopSit(token) then PHX.returnToDealer(token) end
            return
        end
        local seat=h.SeatPart
        if not seat or seat:IsA("VehicleSeat") or PHX.boatForSeat(seat)~=boat then
            PHX.TeamPhase="RECOVERY"
            setStatus("SLAVE lost passenger seat -> reboard")
            return
        end
        task.wait(.3)
    end
    PHX.TeamPhase="RECOVERY"; PHX.BoatState="BOAT_LOST"
end

local function mainLoop(token)
    if not isTeamName(LP.Name) then
        setStatus("This account is not in CONFIG.TEAM")
        ENV.TeamConfig.StopReason = "NOT_IN_TEAM"
        ENV.TeamConfig.IsRunning = false
        return
    end

    ensureMarines()

    while isRunning(token) do
        if PHX.safeResetGuard and not PHX.safeResetGuard(token) then return end
        pcall(ensureMarines)

        local island = PHX.PendingDepartureIsland or findPrehistoric()
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
    local active = PHX.eventActive(island)
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
                    golemHp = math.max(golemHp,0) + math.floor(mh.Health)
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
        "scrap="..tostring(inv.Scrap),
        "ember="..tostring(inv.Ember),
        "magnet="..tostring(inv.Magnet),
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

-- AUTOMATION CONTROLLER BEGIN
function PHX.validateTeam(names, masterName)
    if type(names) ~= "table" or #names ~= 5 then return false, "Crew requires exactly 5 accounts" end
    local seen, localFound, masterFound = {}, false, false
    for _,name in ipairs(names) do
        if type(name) ~= "string" or #name < 3 or #name > 20 or not name:match("^[%w_]+$") then
            return false, "Use Roblox usernames (3–20 letters, digits or underscores)"
        end
        local key = string.lower(name)
        if seen[key] then return false, "Crew usernames must be unique" end
        seen[key] = true
        localFound = localFound or key == string.lower(LP.Name)
        masterFound = masterFound or key == string.lower(masterName or "")
    end
    if not localFound then return false, "This account must belong to the crew" end
    if not masterFound then return false, "MASTER must belong to the crew" end
    return true
end

function PHX.setTeam(names, proposedMaster)
    if not PHX.generationAlive() then return false, "Runtime unloaded" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false, "Stop automation before editing crew" end
    local masterName = proposedMaster ~= nil and proposedMaster or ENV.TeamConfig.MasterName
    if type(masterName) == "string" then masterName = masterName:match("^%s*(.-)%s*$") end
    local ok,reason = PHX.validateTeam(names, masterName)
    if not ok then return false, reason end
    local canonicalNames, canonicalMaster = {},nil
    for i,name in ipairs(names) do
        local online = PHX.playerByName(name)
        local canonical = online and online.Name or name
        if PHX.sameName(name, LP.Name) then canonical = LP.Name end
        canonicalNames[i] = canonical
        if PHX.sameName(name, masterName) then canonicalMaster = canonical end
    end
    CONFIG.TEAM = canonicalNames
    CONFIG.MASTER_NAME = canonicalMaster
    ENV.TeamConfig.MasterName = canonicalMaster
    ENV.TeamConfig.IsMaster = PHX.sameName(LP.Name, canonicalMaster)
    return true, "Crew saved on this client; use the same five names and MASTER on every client"
end

function PHX.setMaster(name)
    if not PHX.generationAlive() then return false, "Runtime unloaded" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false, "Stop automation before changing MASTER" end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    local canonical
    for _,member in ipairs(CONFIG.TEAM) do
        if string.lower(member) == string.lower(name) then canonical = member break end
    end
    if not canonical then return false, "MASTER must be one of the five crew usernames" end
    local online = PHX.playerByName(canonical)
    if online then canonical = online.Name end
    CONFIG.MASTER_NAME = canonical
    ENV.TeamConfig.MasterName = canonical
    ENV.TeamConfig.IsMaster = PHX.sameName(LP.Name, canonical)
    return true, "MASTER saved locally: "..canonical
end

function PHX.stopAutomation(reason)
    ENV.TeamConfig.StopReason = reason or "USER_BUTTON"
    ENV.TeamConfig.IsRunning = false
    RUN_TOKEN = RUN_TOKEN + 1
    PHX.Runtime.RunState = DRAGON_GUARD_STATE.Critical and "Critical" or "Stopped"
    PHX.Runtime.Reason = ENV.TeamConfig.StopReason
    PHX.restoreMovement()
    if PHX.EventState then PHX.EventState.Phase = "STOPPED" end
    disableLavaProtection()
    setForestMagnet(false)
    stopStableHover()
    local starter=PHX.Runtime.StartThread
    if starter and starter~=coroutine.running() then
        pcall(task.cancel,starter)
        PHX.releaseRunnerLocks(starter)
        PHX.Runtime.Tasks[starter]=nil
        PHX.Runtime.StartThread=nil
    end
    local runner = PHX.Runtime.Runner
    if runner and runner ~= coroutine.running() then
        local cancelled = pcall(task.cancel, runner)
        if cancelled or coroutine.status(runner) == "dead" then PHX.releaseRunnerLocks(runner) end
    end
    if runner then PHX.Runtime.Tasks[runner] = nil end
    PHX.Runtime.Runner = nil
    logLine("RUN", "STOP | reason="..tostring(ENV.TeamConfig.StopReason))
    flushNightLog()
    return true
end

function PHX.launchRunner(token)
    PHX.Runtime.Runner = PHX.spawn(function()
        while isRunning(token) do
            local ok,err = pcall(mainLoop, token)
            if not ok and isRunning(token) then
                logLine("RUN_FATAL", tostring(err))
                setStatus("RUN ERROR: "..tostring(err).." | retrying state machine")
                disableLavaProtection()
                setForestMagnet(false)
                stopStableHover()
                task.wait(.35)
            elseif isRunning(token) then
                logLine("RUN_RESTART", "State machine returned while armed; retrying")
                task.wait(.30)
            end
        end
        if token == RUN_TOKEN then
            PHX.Runtime.RunState = DRAGON_GUARD_STATE.Critical and "Critical" or "Stopped"
            PHX.Runtime.Reason = ENV.TeamConfig.StopReason
            disableLavaProtection()
            setForestMagnet(false)
            stopStableHover()
            flushNightLog()
        end
    end)
end

function PHX.startAutomation(masterName)
    if not PHX.generationAlive() then return false,"Runtime unloaded" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Automation is already starting/running" end
    if masterName then
        local ok,reason=PHX.setMaster(masterName)
        if not ok then return false,reason end
    end
    local valid,reason=PHX.validateTeam(CONFIG.TEAM,ENV.TeamConfig.MasterName)
    if not valid then return false,reason end
    local owner=PHX.acquireLock(PHX.Runtime,"StartBusy","StartBusy")
    if not owner then return false,"Automation is already starting" end
    local startThread=coroutine.running()
    local beforeToken=RUN_TOKEN
    PHX.Runtime.StartThread=startThread
    local ok,result,message=pcall(function()
        if DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
            local guarded=PHX.runDragonGuard and PHX.runDragonGuard()
            if not guarded or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
                return false,"Dragon storage remains unverified; reset blocked"
            end
        end
        if not PHX.generationAlive() or RUN_TOKEN~=beforeToken then return false,"Start canceled" end
        RUN_TOKEN=RUN_TOKEN+1
        local token=RUN_TOKEN
        ENV.TeamConfig.StopReason=nil
        ENV.TeamConfig.IsRunning=true
        PHX.Runtime.RunState="Running"
        PHX.Runtime.Reason=nil
        PHX.Runtime.LastError=nil
        NIGHT.LastProgressAt=os.clock()
        NIGHT.LastProgressSignature="RUN_START:"..token
        logLine("RUN","START | role="..roleText().." master="..ENV.TeamConfig.MasterName)
        setStatus("STARTED | "..roleText())
        PHX.launchRunner(token)
        return true,"Automation started"
    end)
    if PHX.Runtime.StartThread==startThread then PHX.Runtime.StartThread=nil end
    PHX.releaseLock(owner)
    if not ok then PHX.Runtime.LastError=tostring(result);return false,tostring(result) end
    return result,message
end
-- AUTOMATION CONTROLLER END

-- Choosing another player makes this client a Slave; the self toggle is separate.
function PHX.assignMaster(name)
    if not PHX.generationAlive() then return false,"Runtime đã đóng" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Tắt Auto Volcano trước khi đổi Master" end
    local player = PHX.playerByName(name)
    if not player then return false,"Player đã rời server" end
    if PHX.sameName(player.Name,LP.Name) then return false,"Dùng nút Add role Master để tự làm Master" end
    local names, found, localFound = table.clone(CONFIG.TEAM), false, false
    for _,member in ipairs(names) do if PHX.sameName(member,LP.Name) then localFound=true end end
    if not localFound then
        local localSlot
        for i=#names,1,-1 do
            if not PHX.sameName(names[i],player.Name) and not PHX.sameName(names[i],ENV.TeamConfig.MasterName) then localSlot=i;break end
        end
        if not localSlot then return false,"Cần một slot trong team cho tài khoản này" end
        names[localSlot]=LP.Name
    end
    for _,member in ipairs(names) do if PHX.sameName(member,player.Name) then found=true end end
    if not found then
        local replaceIndex
        for i,member in ipairs(names) do
            if PHX.sameName(member,ENV.TeamConfig.MasterName) and not PHX.sameName(member,LP.Name) then replaceIndex=i; break end
        end
        if not replaceIndex then
            for i=#names,1,-1 do if not PHX.sameName(names[i],LP.Name) then replaceIndex=i; break end end
        end
        if not replaceIndex then return false,"Không có slot team để thêm Master" end
        names[replaceIndex]=player.Name
    end
    local ok,reason = PHX.setTeam(names,player.Name)
    if ok then PHX.LastOtherMaster=player.Name; ENV.TeamConfig.ForceMasterRole=false end
    return ok,reason
end

function PHX.setLocalMaster(value)
    if not PHX.generationAlive() then return false,"Runtime đã đóng" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Tắt Auto Volcano trước khi đổi role" end
    if value == true then
        if not PHX.sameName(ENV.TeamConfig.MasterName,LP.Name) then PHX.LastOtherMaster=ENV.TeamConfig.MasterName end
        local localFound=false
        for _,member in ipairs(CONFIG.TEAM) do if PHX.sameName(member,LP.Name) then localFound=true end end
        if not localFound then
            local names=table.clone(CONFIG.TEAM)
            for i=#names,1,-1 do
                if not PHX.sameName(names[i],ENV.TeamConfig.MasterName) then names[i]=LP.Name;break end
            end
            local ok,reason=PHX.setTeam(names,LP.Name)
            if ok then ENV.TeamConfig.ForceMasterRole=true end
            return ok,reason
        end
        local ok,reason = PHX.setMaster(LP.Name)
        if ok then ENV.TeamConfig.ForceMasterRole=true end
        return ok,reason
    end
    local other=PHX.LastOtherMaster
    if not other or PHX.sameName(other,LP.Name) then
        if not PHX.sameName(ENV.TeamConfig.MasterName,LP.Name) then other=ENV.TeamConfig.MasterName end
    end
    if not other then return false,"Chọn Master khác trong menu player trước" end
    local ok,reason = PHX.setMaster(other)
    if ok then ENV.TeamConfig.ForceMasterRole=false end
    return ok,reason
end
-- FRUIT AUTO BEGIN
-- Per-client service. Insert after Dragon storage helpers; no equipped ability Tool is stored.
CONFIG.FRUIT_AUTO = CONFIG.FRUIT_AUTO or {}
if CONFIG.FRUIT_AUTO.Enabled == nil then CONFIG.FRUIT_AUTO.Enabled = false end
if CONFIG.FRUIT_AUTO.AutoStore == nil then CONFIG.FRUIT_AUTO.AutoStore = true end
ENV.__PH_FRUIT_PENDING = ENV.__PH_FRUIT_PENDING or {} -- strong references retain unverified operations across reload
PHX.FruitAutoState = {
    Busy=false, Enabled=CONFIG.FRUIT_AUTO.Enabled==true, AutoStore=CONFIG.FRUIT_AUTO.AutoStore==true,
    Status="READY", PhysicalCount=0, NextRandomAt=0, NextStoreAt=0,
    RandomFailures=0, StoreFailures=0, Pending=ENV.__PH_FRUIT_PENDING, LastRandom=nil, LastStored=nil,
}
PHX.FruitStoreIds = {}
-- Longstanding canonical IDs only; renamed/new fruits use precise tool metadata or server inventory IDs.
for _,name in ipairs({"Rocket","Spin","Spring","Bomb","Smoke","Spike","Flame","Ice","Sand","Dark","Diamond","Light","Rubber","Ghost","Magma","Quake","Buddha","Love","Spider","Sound","Phoenix","Portal","Pain","Blizzard","Gravity","Mammoth","T-Rex","Dough","Shadow","Venom","Control","Gas","Spirit","Yeti","Kitsune"}) do
    PHX.FruitStoreIds[string.lower(name)] = name.."-"..name
end

function PHX.fruitServiceAlive(token)
    return (not PHX.generationAlive or PHX.generationAlive())
        and (not PHX.Runtime or PHX.Runtime.Alive)
        and (token == nil or isRunning(token))
end

function PHX.fruitLabelKey(value)
    return string.lower(tostring(value or "")):gsub("<[^>]*>",""):gsub("^blox%s+fruit%s+","")
        :gsub("%s+fruit$",""):gsub("^%s+",""):gsub("%s+$","")
end

function PHX.isPhysicalFruitTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if PHX.isDragonFruitTool(tool) then return true end
    local tip = string.lower(tostring(tool.ToolTip or "")):gsub("%s+", " ")
    local name = string.lower(tostring(tool.Name or ""))
    local physical = name:match("%sfruit$") ~= nil or name:match("^blox%s+fruit%s+") ~= nil
        or tool:FindFirstChild("EatRemote",true) ~= nil
    return physical and (tip == "blox fruit" or tool:FindFirstChild("EatRemote",true) ~= nil)
end

function PHX.findPhysicalFruits()
    local out,seen = {},{}
    local function scan(container)
        if not container then return end
        for _,tool in ipairs(container:GetDescendants()) do
            if PHX.isPhysicalFruitTool(tool) and not seen[tool] then seen[tool]=true;out[#out+1]=tool end
        end
    end
    scan(LP:FindFirstChild("Backpack"));scan(char())
    return out
end

function PHX.fruitStillLocal(tool)
    local backpack,c = LP:FindFirstChild("Backpack"),char()
    return tool.Parent ~= nil and ((backpack and tool:IsDescendantOf(backpack)) or (c and tool:IsDescendantOf(c))) or false
end

function PHX.readStoredFruitInventory()
    local ok,inv = pcall(function() return CommF:InvokeServer("getInventoryFruits") end)
    if not ok or type(inv) ~= "table" then return nil,"STORED_INVENTORY_UNAVAILABLE" end
    local counts,ids,recognized = {},{},next(inv)==nil
    for key,entry in pairs(inv) do
        local name,amount
        if type(entry)=="table" then
            name = entry.Name or entry.name or entry.OriginalName
            amount = tonumber(entry.Count or entry.count or entry.Amount or entry.amount) or 1
        elseif type(key)=="string" and type(entry)=="number" then name,amount=key,entry end
        if type(name)=="string" and name:match("^[%w%-]+%-[%w%-]+$") and amount and amount>=0 then
            recognized=true
            local normalized=string.lower(name)
            counts[normalized]=(counts[normalized] or 0)+amount
            ids[normalized]=name
        end
    end
    if not recognized then return nil,"STORED_INVENTORY_SCHEMA_UNKNOWN" end
    return {Counts=counts,Ids=ids}
end

function PHX.fruitStoreId(tool, inventory)
    if PHX.isDragonFruitTool(tool) then return nil,"DRAGON_USES_CRITICAL_GUARD" end
    local raw=tostring(tool:GetAttribute("OriginalName") or "")
    if raw:match("^[%w%-]+%-[%w%-]+$") then return raw end
    local key=PHX.fruitLabelKey(raw~="" and raw or tool.Name)
    local mapped=PHX.FruitStoreIds[key]
    if mapped then return mapped end
    -- Match only a repeated canonical fruit ID from the real stored inventory.
    for _,id in pairs(inventory and inventory.Ids or {}) do
        for split=1,#id do
            if id:sub(split,split)=="-" then
                local left,right=id:sub(1,split-1),id:sub(split+1)
                if string.lower(left)==string.lower(right) and PHX.fruitLabelKey(left)==key then return id end
            end
        end
    end
    return nil,"STORE_ID_UNVERIFIED"
end

function PHX.fruitRetryDelay(failures)
    local maxDelay=math.max(5,tonumber(CONFIG.FRUIT_AUTO.MaxBackoff) or 300)
    return math.min(maxDelay,5*2^math.min(failures or 1,7))
end

function PHX.notifyPhysicalDragons()
    for _,tool in ipairs(PHX.findPhysicalDragonFruits()) do
        if PHX.notifyDragonFruit then PHX.notifyDragonFruit(tool) end
    end
end

function PHX.runDragonGuard()
    PHX.notifyPhysicalDragons()
    if PHX.reconcileDragonPending then
        local reconciled,reason=pcall(PHX.reconcileDragonPending)
        if not reconciled then return false,"DRAGON_PENDING_RECONCILE_ERROR: "..tostring(reason) end
    end
    local guard=PHX.storeDragonFruitCritical or storeDragonFruitCritical
    if type(guard)~="function" then return false,"DRAGON_GUARD_UNAVAILABLE" end
    local ok,result=pcall(guard)
    if not ok then return false,"DRAGON_GUARD_ERROR: "..tostring(result) end
    return result==true and not DRAGON_GUARD_STATE.Critical and not DRAGON_GUARD_STATE.Pending and #PHX.findPhysicalDragonFruits()==0,
        result==true and "DRAGON_CHECKED" or "DRAGON_STORE_UNCONFIRMED"
end

function PHX.reconcileFruitPending()
    local state=PHX.FruitAutoState
    if next(state.Pending)==nil then return true end
    local inv=PHX.readStoredFruitInventory()
    if not inv then return false end
    local ready=true
    for tool,pending in pairs(state.Pending) do
        if not PHX.fruitStillLocal(tool) then
            if (inv.Counts[string.lower(pending.Id)] or 0)>pending.Before then
                state.Pending[tool]=nil
                state.LastStored=pending.Id
                logLine("FRUIT_STORED",pending.Id.." verified after delayed replication")
            else ready=false end
        end
        -- A still-carried tool is safe to retry under the same owner lock; keep
        -- its record until actual removal and count gain, rather than deadlocking storage.
    end
    return ready
end

function PHX.storePhysicalFruit(tool,token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    if PHX.isDragonFruitTool(tool) then return PHX.runDragonGuard() end
    if not PHX.isPhysicalFruitTool(tool) or not PHX.fruitStillLocal(tool) then return false,"TOOL_NOT_LOCAL" end
    local before,reason=PHX.readStoredFruitInventory()
    if not before then return false,reason end
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    local id,idReason=PHX.fruitStoreId(tool,before)
    if not id then return false,idReason end
    local count=before.Counts[string.lower(id)] or 0
    -- Save before the yielding mutation. A reload may cancel its owner between
    -- server removal and verification; a new generation must retain this baseline.
    PHX.FruitAutoState.Pending[tool]={Id=id,Before=count}
    local ok,result=pcall(function() return CommF:InvokeServer("StoreFruit",id,tool) end)
    local deadline=os.clock()+math.max(.5,tonumber(CONFIG.FRUIT_AUTO.StoreVerifySeconds) or 2)
    repeat
        if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
        task.wait(.25)
        local after=PHX.readStoredFruitInventory()
        if after and not PHX.fruitStillLocal(tool) and (after.Counts[string.lower(id)] or 0)>count then
            PHX.FruitAutoState.Pending[tool]=nil
            PHX.FruitAutoState.LastStored=id
            noteProgress("FRUIT_STORED:"..id)
            logLine("FRUIT_STORED",id.." removed and fresh stored count increased")
            return true,id
        end
    until os.clock()>=deadline
    return false,ok and "STORE_UNCONFIRMED" or "STORE_REQUEST_FAILED: "..tostring(result)
end

function PHX.fruitCooldown(response)
    if type(response)=="table" then
        for _,key in ipairs({"CooldownSeconds","RetryAfter","Cooldown","cooldown","retryAfter"}) do
            local n=tonumber(response[key])
            if n and n>0 then return n,"SERVER_COOLDOWN" end
        end
        if response.CanBuy==false or response.Ready==false then return 60,"SERVER_NOT_READY" end
    elseif type(response)=="string" then
        local text=string.lower(response)
        if text:find("not enough money",1,true) or text:find("cannot afford",1,true) or text:find("can't afford",1,true) then
            return 300,"INSUFFICIENT_MONEY"
        end
        if text:find("cooldown",1,true) or text:find("come back",1,true) or text:find("wait",1,true) then
            local hours,mins,secs=text:match("(%d+):(%d+):(%d+)")
            if hours then return tonumber(hours)*3600+tonumber(mins)*60+tonumber(secs),"SERVER_COOLDOWN" end
            local h=tonumber(text:match("(%d+)%s*hours?")) or 0
            local m=tonumber(text:match("(%d+)%s*minutes?")) or 0
            local ss=tonumber(text:match("(%d+)%s*seconds?")) or 0
            return h*3600+m*60+ss>0 and h*3600+m*60+ss or 60,"SERVER_COOLDOWN"
        end
    end
    return nil,"CHECK_RESPONSE_UNPARSED"
end

function PHX.randomFruitOnce(token)
    local state=PHX.FruitAutoState
    if not PHX.fruitServiceAlive(token) or not state.Enabled then return false,"CANCELED" end
    if #PHX.findPhysicalFruits()>0 or next(state.Pending)~=nil or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then return false,"STORE_PHYSICAL_FRUIT_FIRST" end
    local checked,response=pcall(function() return CommF:InvokeServer("Cousin","Check") end)
    if not PHX.fruitServiceAlive(token) or not state.Enabled then return false,"CANCELED" end
    if not checked then return false,"RANDOM_CHECK_FAILED" end
    local cooldown,reason=PHX.fruitCooldown(response)
    if cooldown then state.NextRandomAt=os.clock()+math.max(5,cooldown);return false,reason,true end
    -- Unparsed Check metadata is not a readiness/success assertion. The server
    -- enforces Buy; one attempt is followed by physical-tool evidence or backoff.
    local previous={}
    for _,tool in ipairs(PHX.findPhysicalFruits()) do previous[tool]=true end
    local ok,result=pcall(function() return CommF:InvokeServer("Cousin","Buy") end)
    state.NextRandomAt=os.clock()+math.max(5,tonumber(CONFIG.FRUIT_AUTO.RandomInterval) or 5)
    if not ok then return false,"RANDOM_BUY_FAILED: "..tostring(result) end
    local deadline=os.clock()+2
    repeat
        if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
        for _,tool in ipairs(PHX.findPhysicalFruits()) do
            if not previous[tool] then
                state.LastRandom=tool.Name
                if PHX.isDragonFruitTool(tool) and PHX.notifyDragonFruit then PHX.notifyDragonFruit(tool) end
                logLine("FRUIT_RANDOM", "New physical fruit observed: "..tostring(tool.Name))
                return true,tool.Name
            end
        end
        task.wait(.1)
    until os.clock()>=deadline
    return false,"RANDOM_RESULT_UNCONFIRMED"
end

function PHX.storeFruitSweep(token)
    local state=PHX.FruitAutoState
    PHX.notifyPhysicalDragons()
    if #PHX.findPhysicalDragonFruits()>0 or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
        local ok,reason=PHX.runDragonGuard()
        if not ok then return false,reason end
    end
    if not PHX.reconcileFruitPending() then return false,"STORAGE_PENDING_VERIFICATION" end
    if not state.AutoStore then return true,"AUTO_STORE_OFF" end
    local fruits=PHX.findPhysicalFruits()
    for _,tool in ipairs(fruits) do
        if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
        local ok,reason=PHX.storePhysicalFruit(tool,token)
        if not ok then return false,reason end
    end
    state.PhysicalCount=#PHX.findPhysicalFruits()
    return state.PhysicalCount==0,state.PhysicalCount==0 and "NO_PHYSICAL_FRUIT" or "MORE_FRUIT_REPLICATING"
end

function PHX.withFruitLock(callback)
    local state=PHX.FruitAutoState
    if state.Busy then return false,"FRUIT_SERVICE_BUSY" end
    local owner=PHX.acquireLock(state,"Busy","FruitAutoBusy")
    if not owner then return false,"FRUIT_SERVICE_BUSY" end
    local ok,result,reason=pcall(callback)
    PHX.releaseLock(owner)
    if not ok then return false,"FRUIT_SERVICE_ERROR: "..tostring(result) end
    return result,reason
end

function PHX.fruitAutoTick(token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    return PHX.withFruitLock(function()
        local state=PHX.FruitAutoState
        state.PhysicalCount=#PHX.findPhysicalFruits()
        -- Dragons are protected even with random/store toggles OFF and team auto OFF.
        PHX.notifyPhysicalDragons()
        if #PHX.findPhysicalDragonFruits()>0 or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
            local guarded,why=PHX.runDragonGuard()
            if not guarded then state.Status=why;return false,why end
        end
        if os.clock()>=state.NextStoreAt then
            local stored,why=PHX.storeFruitSweep(token)
            if not stored then
                state.StoreFailures=state.StoreFailures+1
                state.NextStoreAt=os.clock()+PHX.fruitRetryDelay(state.StoreFailures)
                state.Status=why
                logLine("FRUIT_STORE_WAIT",tostring(why))
                return false,why
            end
            state.StoreFailures=0;state.NextStoreAt=os.clock()+5
        end
        if state.Enabled and os.clock()>=state.NextRandomAt and #PHX.findPhysicalFruits()==0 and next(state.Pending)==nil then
            local rolled,why,knownCooldown=PHX.randomFruitOnce(token)
            if not rolled and why~="CANCELED" and not knownCooldown then
                state.RandomFailures=state.RandomFailures+1
                state.NextRandomAt=os.clock()+PHX.fruitRetryDelay(state.RandomFailures)
            elseif rolled then state.RandomFailures=0 end
            state.Status=rolled and "ROLLED: "..tostring(why) or why
        else
            if next(state.Pending)~=nil then state.Status="STORAGE_PENDING_VERIFICATION"
            elseif #PHX.findPhysicalFruits()>0 then state.Status=os.clock()<state.NextStoreAt and "STORE_BACKOFF" or "WAITING_TO_STORE"
            else state.Status=state.Enabled and "RANDOM_COOLDOWN" or "READY" end
        end
        state.PhysicalCount=#PHX.findPhysicalFruits()
        return true,state.Status
    end)
end

function PHX.setFruitAuto(enabled)
    PHX.FruitAutoState.Enabled=enabled==true;CONFIG.FRUIT_AUTO.Enabled=enabled==true
    return true,enabled and "Random fruit enabled locally" or "Random fruit disabled locally"
end

function PHX.setAutoStore(enabled)
    PHX.FruitAutoState.AutoStore=enabled==true;CONFIG.FRUIT_AUTO.AutoStore=enabled==true
    if enabled then PHX.FruitAutoState.NextStoreAt=0 end
    return true,enabled and "Auto Store enabled locally" or "Auto Store disabled; Dragon protection remains active"
end

function PHX.safeResetGuard(token)
    if not PHX.fruitServiceAlive(token) then return false end
    if PHX.reconcileDragonPending then
        local ok=pcall(PHX.reconcileDragonPending)
        if not ok then return false end
    end
    if DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then return false end
    local ok=PHX.withFruitLock(function()
        local protected,why=PHX.storeFruitSweep(token)
        if not protected then PHX.FruitAutoState.Status=why;return false end
        return #PHX.findPhysicalDragonFruits()==0 and not DRAGON_GUARD_STATE.Critical and not DRAGON_GUARD_STATE.Pending
            and (not PHX.FruitAutoState.AutoStore or #PHX.findPhysicalFruits()==0)
            and next(PHX.FruitAutoState.Pending)==nil
    end)
    -- Recheck after awaited calls; fruit replication can occur while a storage request yields.
    return ok==true and PHX.fruitServiceAlive(token) and #PHX.findPhysicalDragonFruits()==0
        and not DRAGON_GUARD_STATE.Critical and not DRAGON_GUARD_STATE.Pending
        and (not PHX.FruitAutoState.AutoStore or #PHX.findPhysicalFruits()==0)
        and next(PHX.FruitAutoState.Pending)==nil
end

PHX.spawn(function()
    while PHX.fruitServiceAlive() do
        PHX.fruitAutoTick()
        task.wait(math.max(5,tonumber(CONFIG.FRUIT_AUTO.TickSeconds) or 5))
    end
end)
-- FRUIT AUTO END
local function restartNightStateMachine(reason)
    if not ENV.TeamConfig.IsRunning then return end
    PHX.stopAutomation("WATCHDOG_RECOVERY")
    RUN_TOKEN = RUN_TOKEN + 1
    local token = RUN_TOKEN
    ENV.TeamConfig.IsRunning = true
    ENV.TeamConfig.StopReason = nil
    PHX.Runtime.RunState = "Running"
    NIGHT.RecoveryCount = NIGHT.RecoveryCount + 1
    NIGHT.LastProgressAt = os.clock()
    NIGHT.LastProgressSignature = "WATCHDOG_RESTART:"..NIGHT.RecoveryCount
    logLine("WATCHDOG_RECOVER", "count="..NIGHT.RecoveryCount.." reason="..tostring(reason).." | re-entering mainLoop without killing character")
    PHX.launchRunner(token)
end

PHX.spawn(function()
    local nextSnapshot = 0
    while PHX.generationAlive() do
        task.wait(5)
        if CONFIG.DEBUG.ENABLED and ENV.TeamConfig.IsRunning then
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
-- UI: VOLCANO TEAM V2.11 / DASHBOARD KAWAII PASTEL
-- Dùng UI Roblox gốc; không tải thư viện/ảnh ngoài, không chặn input bằng trang trí.
--==============================================================
function PHX.buildUI()
    if not PHX.generationAlive() then return end
    local U = {Pages = {}, Tabs = {}, CrewRows = {}, PlayerRows = {}, PlayerExiting = {}, Toggles = {}, InputNodes = {}, LastActivity = "", SyncBusy = false, LastSyncAt = -math.huge, PlayersDirty = true}
    PHX.UI = U
    local Input = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local Players = game:GetService("Players")
    local C = {
        Background = Color3.fromRGB(248, 241, 255), Surface = Color3.fromRGB(255, 251, 255),
        Raised = Color3.fromRGB(238, 224, 252), Border = Color3.fromRGB(214, 193, 232),
        Text = Color3.fromRGB(77, 55, 98), Muted = Color3.fromRGB(126, 104, 147),
        Pink = Color3.fromRGB(235, 137, 179), PinkSoft = Color3.fromRGB(255, 219, 235),
        Cyan = Color3.fromRGB(68, 151, 168), CyanSoft = Color3.fromRGB(207, 243, 247),
        Lavender = Color3.fromRGB(145, 116, 201), LavenderSoft = Color3.fromRGB(230, 218, 255),
        Amber = Color3.fromRGB(173, 121, 47), AmberSoft = Color3.fromRGB(255, 237, 202),
        Red = Color3.fromRGB(179, 73, 104), RedSoft = Color3.fromRGB(255, 218, 227),
    }
    local function make(className, props, parent)
        local object = Instance.new(className)
        for key, value in pairs(props or {}) do object[key] = value end
        if object:IsA("GuiObject") then object.Active = false end
        object.Parent = parent
        return object
    end
    local function round(object, radius)
        make("UICorner", {CornerRadius = UDim.new(0, radius or 12)}, object)
    end
    local function outline(object, color, transparency)
        return make("UIStroke", {Color = color or C.Border, Thickness = 1, Transparency = transparency or 0.15}, object)
    end
    local function text(parent, value, size, color, position, dimensions, weight)
        return make("TextLabel", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Text = value or "",
            TextColor3 = color or C.Text, Font = weight or Enum.Font.Gotham,
            TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true, RichText = false,
            Position = position or UDim2.fromOffset(12, 8), Size = dimensions or UDim2.new(1, -24, 0, 20),
        }, parent)
    end
    local function inputNode(object)
        object.Active = true
        U.InputNodes[#U.InputNodes + 1] = object
        return object
    end
    local function button(parent, value, position, dimensions, color)
        local object = inputNode(make("TextButton", {
            Text = value, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.Text,
            AutoButtonColor = false, BackgroundColor3 = color or C.Raised, BorderSizePixel = 0,
            Position = position, Size = dimensions,
        }, parent))
        round(object, 10)
        outline(object)
        return object
    end
    local function card(parent, height, order)
        local object = make("Frame", {
            Size = UDim2.new(1, 0, 0, height), LayoutOrder = order or 0,
            BackgroundColor3 = C.Surface, BorderSizePixel = 0,
        }, parent)
        round(object, 12)
        outline(object)
        return object
    end
    local function field(parent, value, placeholder, position, dimensions, multiline)
        local object = inputNode(make("TextBox", {
            BackgroundColor3 = C.Background, BorderSizePixel = 0, Text = value,
            PlaceholderText = placeholder, PlaceholderColor3 = C.Muted, TextColor3 = C.Text,
            Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
            MultiLine = multiline or false, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
            Position = position, Size = dimensions,
        }, parent))
        round(object, 9)
        outline(object)
        make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, multiline and 8 or 0)}, object)
        return object
    end
    local function sourceLabel(source)
        if not source or source == "UNAVAILABLE" or source == "UNKNOWN" then return "CHƯA XÁC NHẬN" end
        if tostring(source):find("STASH", 1, true) then return "STASH CACHE" end
        if tostring(source):find("REMOTE", 1, true) then return "SERVER CACHE" end
        if tostring(source):find("CRAFT", 1, true) then return "CRAFT CACHE" end
        return "LOCAL CACHE"
    end
    local function number(value)
        if value == nil then return "--" end
        return tostring(math.floor(tonumber(value) or 0))
    end
    local function percent(value)
        return value ~= nil and string.format("%.1f%%", tonumber(value) or 0) or "--"
    end
    local function toggle(parent, y, title, description, read, write, roleLock)
        text(parent, title, 11, C.Text, UDim2.fromOffset(11, y), UDim2.new(1, -84, 0, 20), Enum.Font.GothamMedium)
        text(parent, description, 9, C.Muted, UDim2.fromOffset(11, y + 21), UDim2.new(1, -84, 0, 25))
        local control = button(parent, "OFF", UDim2.new(1, -63, 0, y + 4), UDim2.fromOffset(52, 32), C.Raised)
        U.Toggles[#U.Toggles + 1] = {Control = control, Read = read, RoleLock = roleLock == true}
        PHX.connect(control.Activated, function()
            if U.PassThrough then return end
            if roleLock and (ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy or U.SyncBusy) then
                U.notice("Tắt Auto Volcano trước khi đổi role.", false)
                return
            end
            local ok, message = write(not read())
            if message then U.notice(message, ok == true) end
            U.updateControls()
        end)
        return control
    end

    for _, parent in ipairs({PG, CoreGui}) do
        pcall(function()
            local older = parent:FindFirstChild("PrehistoricTeamV1")
            if older then older:Destroy() end
        end)
    end
    if type(gethui) == "function" then
        pcall(function()
            local hidden = gethui()
            local older = hidden and hidden:FindFirstChild("PrehistoricTeamV1")
            if older then older:Destroy() end
        end)
    end
    U.Screen = make("ScreenGui", {
        Name = "PrehistoricTeamV1", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true,
    }, PG)
    PHX.CustomGui = U.Screen
    U.Root = make("Frame", {
        Name = "KawaiiDashboard", BackgroundColor3 = C.Background, BorderSizePixel = 0,
        Size = UDim2.fromOffset(448, 586), ClipsDescendants = true,
    }, U.Screen)
    round(U.Root, 16)
    outline(U.Root, C.Lavender, 0.25)
    local header = inputNode(make("Frame", {
        Name = "DragHeader", BackgroundColor3 = C.PinkSoft, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 72),
    }, U.Root))
    make("UIGradient", {Color = ColorSequence.new(C.PinkSoft, C.LavenderSoft), Rotation = 20}, header)
    make("Frame", {BackgroundColor3 = C.CyanSoft, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3)}, header)
    text(header, "VOLCANO  ♥  TEAM", 18, C.Text, UDim2.fromOffset(13, 11), UDim2.new(1, -111, 0, 24), Enum.Font.GothamBold)
    U.StatePill = text(header, "READY", 10, C.Lavender, UDim2.fromOffset(13, 43), UDim2.fromOffset(82, 20), Enum.Font.GothamBold)
    U.StatePill.BackgroundTransparency = 0
    U.StatePill.BackgroundColor3 = C.Surface
    U.StatePill.TextXAlignment = Enum.TextXAlignment.Center
    round(U.StatePill, 7)
    U.RolePill = text(header, "SLAVE", 10, C.Cyan, UDim2.fromOffset(103, 43), UDim2.new(1, -200, 0, 20), Enum.Font.GothamBold)
    local minimize = button(header, "−", UDim2.new(1, -40, 0, 10), UDim2.fromOffset(29, 29), C.Surface)
    minimize.TextSize = 18

    -- Chibi anime dựng bằng Frame gốc; mọi chi tiết trang trí đều không nhận input.
    -- Không cần ảnh bổ sung và không tải URL bên ngoài.
    local art = make("Frame", {Name = "AnimeGirl", BackgroundTransparency = 1, Position = UDim2.new(1, -111, 0, 7), Size = UDim2.fromOffset(63, 66)}, header)
    local function shape(x, y, w, h, color, radius, rotation)
        local object = make("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = rotation or 0}, art)
        round(object, radius or 30)
        return object
    end
    shape(6, 4, 48, 52, C.Lavender, 24)
    shape(5, 29, 12, 31, C.Lavender, 8, 8)
    shape(43, 29, 12, 31, C.Lavender, 8, -8)
    shape(13, 17, 34, 34, Color3.fromRGB(255, 229, 220), 20)
    shape(13, 10, 34, 16, C.Lavender, 10)
    shape(20, 18, 11, 12, C.Lavender, 4, 25)
    shape(19, 32, 7, 10, C.Text, 5)
    shape(35, 32, 7, 10, C.Text, 5)
    shape(20, 32, 3, 4, C.Surface, 3)
    shape(36, 32, 3, 4, C.Surface, 3)
    shape(14, 42, 9, 4, C.Pink, 3)
    shape(39, 42, 9, 4, C.Pink, 3)
    text(art, "ω", 12, C.Red, UDim2.fromOffset(25, 40), UDim2.fromOffset(14, 11), Enum.Font.GothamBold)
    shape(20, 53, 25, 15, C.Pink, 8)
    shape(37, 7, 11, 11, C.CyanSoft, 2, 28)
    shape(46, 7, 11, 11, C.CyanSoft, 2, -28)
    shape(44, 10, 5, 5, C.Cyan, 3)
    text(art, "✦", 12, C.Pink, UDim2.fromOffset(0, 0), UDim2.fromOffset(13, 15))

    local navigation = make("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(11, 80), Size = UDim2.new(1, -22, 0, 30)}, U.Root)
    for index, entry in ipairs({{"LIVE", "♡ TRẠNG THÁI"}, {"CREW", "♧ ĐỘI"}, {"SETTINGS", "⚙ CÀI ĐẶT"}, {"ACTIVITY", "☆ NHẬT KÝ"}}) do
        local name = entry[1]
        local tab = button(navigation, entry[2], UDim2.new((index - 1) / 4, 2, 0, 0), UDim2.new(0.25, -4, 1, 0), C.Surface)
        tab.TextSize = 10
        U.Tabs[name] = tab
        local page = inputNode(make("ScrollingFrame", {
            Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(12, 119), Size = UDim2.new(1, -24, 1, -184),
            CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3, ScrollBarImageColor3 = C.Lavender,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = index == 1,
        }, U.Root))
        make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        make("UIPadding", {PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6)}, page)
        U.Pages[name] = page
        PHX.connect(tab.Activated, function()
            if U.PassThrough then return end
            for key, frame in pairs(U.Pages) do frame.Visible = key == name end
            for key, control in pairs(U.Tabs) do
                control.BackgroundColor3 = key == name and C.LavenderSoft or C.Surface
                control.TextColor3 = key == name and C.Lavender or C.Muted
            end
            U.CurrentPage = name
        end)
    end
    U.CurrentPage = "LIVE"
    U.Tabs.LIVE.BackgroundColor3 = C.LavenderSoft
    U.Tabs.LIVE.TextColor3 = C.Lavender

    local overview = U.Pages.LIVE
    local status = card(overview, 67, 1)
    U.Phase = text(status, "♡ READY", 10, C.Lavender, UDim2.fromOffset(11, 5), UDim2.new(1, -22, 0, 17), Enum.Font.GothamBold)
    STATUS_LABEL = text(status, "Sẵn sàng · Auto Volcano đang tắt", 11, C.Text, UDim2.fromOffset(11, 24), UDim2.new(1, -22, 0, 38), Enum.Font.GothamMedium)
    STATUS_LABEL.TextYAlignment = Enum.TextYAlignment.Top

    local resources = card(overview, 68, 2)
    local function material(index, title, accent)
        local host = make("Frame", {BackgroundTransparency = 1, Position = UDim2.new((index - 1) / 3, 0, 0, 0), Size = UDim2.new(1 / 3, 0, 1, 0)}, resources)
        text(host, title, 9, C.Muted, UDim2.fromOffset(10, 6), UDim2.new(1, -15, 0, 16), Enum.Font.GothamBold)
        local value = text(host, "--", 19, accent, UDim2.fromOffset(10, 23), UDim2.new(1, -15, 0, 25), Enum.Font.GothamBold)
        local source = text(host, "CHƯA XÁC NHẬN", 8, C.Muted, UDim2.fromOffset(10, 50), UDim2.new(1, -15, 0, 13))
        if index < 3 then make("Frame", {BackgroundColor3 = C.Border, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 12), Size = UDim2.new(0, 1, 1, -24)}, host) end
        return {Value = value, Source = source}
    end
    U.Magnet = material(1, "🧲 MAGNET", C.Cyan)
    U.Scrap = material(2, "♡ SCRAP / 10", C.Lavender)
    U.Ember = material(3, "✦ EMBER / 15", C.Red)
    COUNTER_LABEL = text(resources, "", 8, C.Muted, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0))
    COUNTER_LABEL.Visible = false

    local journey = card(overview, 73, 3)
    U.BoatTitle = text(journey, "⛵ GRAND BRIGADE", 10, C.Cyan, UDim2.fromOffset(11, 5), UDim2.new(0.65, -12, 0, 18), Enum.Font.GothamBold)
    U.BoatHP = text(journey, "HP -- / --", 11, C.Text, UDim2.new(0.65, 0, 0, 5), UDim2.new(0.35, -11, 0, 18), Enum.Font.GothamBold)
    U.BoatHP.TextXAlignment = Enum.TextXAlignment.Right
    U.BoatState = text(journey, "WAIT_MASTER · 0/5 aboard · ≥4 để đi", 10, C.Muted, UDim2.fromOffset(11, 26), UDim2.new(1, -22, 0, 16))
    U.SeaState = text(journey, "SEA 6 · giữ một hướng thẳng", 10, C.Cyan, UDim2.fromOffset(11, 46), UDim2.new(1, -22, 0, 18))

    local event = card(overview, 111, 4)
    local function metric(x, y, title, accent)
        local host = make("Frame", {BackgroundTransparency = 1, Position = UDim2.new(x, 0, 0, y), Size = UDim2.new(0.5, 0, 0, 49)}, event)
        text(host, title, 9, C.Muted, UDim2.fromOffset(11, 4), UDim2.new(1, -22, 0, 15), Enum.Font.GothamBold)
        local value = text(host, "--", 17, accent, UDim2.fromOffset(11, 21), UDim2.new(1, -22, 0, 24), Enum.Font.GothamBold)
        return value
    end
    U.Timer = metric(0, 3, "🌋 EVENT TIMER / HUD", C.Lavender)
    U.Pressure = metric(0.5, 3, "♨ PRESSURE / HUD", C.Red)
    U.Relic = metric(0, 55, "♡ RELIC HP", C.Cyan)
    U.Golems = metric(0.5, 55, "♟ LIVE GOLEMS / TOTAL HP", C.Lavender)
    U.Golems.TextSize = 13
    make("Frame", {BackgroundColor3 = C.Border, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.fromOffset(11, 54), Size = UDim2.new(1, -22, 0, 1)}, event)

    local rewards = card(overview, 64, 5)
    U.EggState = text(rewards, "🥚 EGG · chưa có phần thưởng", 11, C.Pink, UDim2.fromOffset(11, 5), UDim2.new(1, -22, 0, 22), Enum.Font.GothamBold)
    U.Recovery = text(rewards, "♡ RECOVERY · READY", 10, C.Muted, UDim2.fromOffset(11, 29), UDim2.new(1, -22, 0, 30))

    local crew = U.Pages.CREW
    local presence = card(crew, 296, 1)
    text(presence, "♧ MASTER + ÍT NHẤT 3 SLAVE ĐỂ RA KHƠI", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.CrewSummary = text(presence, "0/5 online · 0/5 trên thuyền · cần 4/5", 10, C.Cyan, UDim2.fromOffset(11, 28), UDim2.new(1, -22, 0, 18))
    for index = 1, 5 do
        local row = make("Frame", {BackgroundColor3 = C.Background, BorderSizePixel = 0, Position = UDim2.fromOffset(9, 54 + (index - 1) * 41), Size = UDim2.new(1, -18, 0, 36)}, presence)
        round(row, 9)
        local name = text(row, "", 11, C.Text, UDim2.fromOffset(9, 2), UDim2.new(1, -95, 0, 17), Enum.Font.GothamMedium)
        name.TextWrapped = false
        name.TextTruncate = Enum.TextTruncate.AtEnd
        local role = text(row, "", 8, C.Muted, UDim2.fromOffset(9, 20), UDim2.new(1, -95, 0, 13))
        local state = text(row, "OFFLINE", 8, C.Muted, UDim2.new(1, -88, 0, 9), UDim2.fromOffset(80, 18), Enum.Font.GothamBold)
        state.TextXAlignment = Enum.TextXAlignment.Right
        U.CrewRows[index] = {Name = name, Role = role, State = state}
    end
    text(presence, "Slave thứ 4 có thể farm Magnet. Master giữ ghế lái.", 9, C.Muted, UDim2.fromOffset(11, 262), UDim2.new(1, -22, 0, 26))
    local masterCard = card(crew, 239, 2)
    text(masterCard, "♡ MASTER / BUY BOAT + DRIVER", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.MasterBox = field(masterCard, CONFIG.MASTER_NAME, "Roblox username chính xác", UDim2.fromOffset(11, 31), UDim2.new(1, -96, 0, 34))
    U.ApplyMaster = button(masterCard, "LƯU", UDim2.new(1, -76, 0, 31), UDim2.fromOffset(65, 34), C.CyanSoft)
    U.RoleLabel = text(masterCard, "", 9, C.Muted, UDim2.fromOffset(11, 70), UDim2.new(1, -22, 0, 24))
    U.LocalMasterToggle = toggle(masterCard, 101, "Add role Master", "Bật: client này mua và lái thuyền.", function()
        return PHX.sameName(LP.Name, ENV.TeamConfig.MasterName)
    end, function(value)
        local ok, message = PHX.setLocalMaster(value)
        if ok then U.syncCrewFields() end
        return ok, ok and (value and "Client này là Master. Lưu cùng đội trên cả 5 client." or "Client này là Slave. Lưu cùng Master trên cả 5 client.") or message
    end, true)
    U.PlayerMenu = button(masterCard, "CHỌN MASTER TỪ PLAYER ONLINE  ▾", UDim2.fromOffset(11, 162), UDim2.new(1, -22, 0, 34), C.LavenderSoft)
    U.PlayerMenu.TextSize = 10
    U.PlayerList = inputNode(make("ScrollingFrame", {
        Name = "OnlineMasterMenu", BackgroundColor3 = C.Background, BorderSizePixel = 0,
        Position = UDim2.fromOffset(11, 205), Size = UDim2.new(1, -22, 0, 142), Visible = false,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.Lavender, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, masterCard))
    round(U.PlayerList, 9)
    make("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, U.PlayerList)
    make("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, U.PlayerList)
    U.NoPlayers = text(U.PlayerList, "Chưa có player khác online.", 10, C.Muted, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 35))
    U.NoPlayers.LayoutOrder = 0
    U.CrewLocalNote = text(masterCard, "Chọn player khác: client này là Slave. Cài đặt chỉ lưu cục bộ.", 9, C.Muted, UDim2.fromOffset(11, 202), UDim2.new(1, -22, 0, 30))
    function U.setPlayerMenu(value)
        U.PlayerMenuOpen = value == true
        U.PlayerList.Visible = U.PlayerMenuOpen
        masterCard.Size = UDim2.new(1, 0, 0, U.PlayerMenuOpen and 391 or 239)
        U.CrewLocalNote.Position = UDim2.fromOffset(11, U.PlayerMenuOpen and 354 or 202)
    end
    PHX.connect(U.PlayerMenu.Activated, function()
        if U.PassThrough or ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy or U.SyncBusy then return end
        U.setPlayerMenu(not U.PlayerMenuOpen)
        U.refreshPlayers()
        U.updateControls()
    end)
    local rosterCard = card(crew, 224, 3)
    text(rosterCard, "♧ NĂM USERNAME / CÙNG THỨ TỰ TRÊN 5 CLIENT", 9, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.TeamBox = field(rosterCard, table.concat(CONFIG.TEAM, "\n"), "Mỗi dòng một username", UDim2.fromOffset(11, 31), UDim2.new(1, -22, 0, 112), true)
    U.ApplyCrew = button(rosterCard, "LƯU ĐỘI NĂM TÀI KHOẢN", UDim2.fromOffset(11, 151), UDim2.new(1, -22, 0, 32), C.CyanSoft)
    text(rosterCard, "Lưu cục bộ: đặt cùng danh sách + Master trên cả 5 client.", 9, C.Muted, UDim2.fromOffset(11, 187), UDim2.new(1, -22, 0, 29))

    local settingsPage = U.Pages.SETTINGS
    local switches = card(settingsPage, 211, 1)
    text(switches, "⚙ CÀI ĐẶT CHẠY", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    toggle(switches, 31, "Nhật ký chẩn đoán", "Lưu trạng thái thật và lỗi vào log.", function() return CONFIG.DEBUG.ENABLED end, function(value) CONFIG.DEBUG.ENABLED = value end)
    toggle(switches, 89, "Tự phục hồi khi bị kẹt", "Giữ an toàn khi sự kiện Volcano đang chạy.", function() return CONFIG.DEBUG.WATCHDOG_RESTART end, function(value) CONFIG.DEBUG.WATCHDOG_RESTART = value end)
    toggle(switches, 147, "Trở về Tiki", "Trở về sau reward và kiểm tra Dragon storage.", function() return CONFIG.RESET_TO_TIKI_AFTER_EVENT end, function(value) CONFIG.RESET_TO_TIKI_AFTER_EVENT = value end)
    local fruitCard = card(settingsPage, 235, 2)
    text(fruitCard, "♡ RANDOM FRUIT / AUTO STORE", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.FruitToggle = toggle(fruitCard, 31, "Random fruit", "Tự random khi hết cooldown trên client này.", function() return CONFIG.FRUIT_AUTO.Enabled == true end, function(value)
        local ok, message = PHX.setFruitAuto(value)
        return ok, ok and (value and "Đã bật Random fruit trên client này." or "Đã tắt Random fruit trên client này.") or message
    end)
    U.AutoStoreToggle = toggle(fruitCard, 88, "Auto Store", "Tự cất trái vật lý; Dragon luôn được bảo vệ.", function() return CONFIG.FRUIT_AUTO.AutoStore == true end, function(value)
        local ok, message = PHX.setAutoStore(value)
        return ok, ok and (value and "Đã bật Auto Store trên client này." or "Đã tắt Auto Store. Dragon vẫn được bảo vệ.") or message
    end)
    U.FruitStatus = text(fruitCard, "READY", 9, C.Cyan, UDim2.fromOffset(11, 147), UDim2.new(1, -22, 0, 31), Enum.Font.GothamMedium)
    U.FruitCount = text(fruitCard, "Trái vật lý: 0", 9, C.Muted, UDim2.fromOffset(11, 181), UDim2.new(0.5, -11, 0, 19))
    U.FruitCooldown = text(fruitCard, "Random: OFF", 9, C.Muted, UDim2.new(0.5, 0, 0, 181), UDim2.new(0.5, -11, 0, 19))
    text(fruitCard, "Cài đặt riêng mỗi client; không cần bật Auto Volcano.", 9, C.Muted, UDim2.fromOffset(11, 203), UDim2.new(1, -22, 0, 25))
    local webhookCard = card(settingsPage, 216, 3)
    text(webhookCard, "☆ DISCORD WEBHOOK / ID PING", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.WebhookBox = field(webhookCard, tostring(CONFIG.WEBHOOK_URL or ""), "Discord webhook URL", UDim2.fromOffset(11, 31), UDim2.new(1, -22, 0, 33))
    U.DiscordIdBox = field(webhookCard, tostring(CONFIG.WEBHOOK_USER_ID or ""), "Discord user ID · 15–22 chữ số", UDim2.fromOffset(11, 73), UDim2.new(1, -22, 0, 33))
    U.ApplyWebhook = button(webhookCard, "LƯU WEBHOOK + ID PING", UDim2.fromOffset(11, 115), UDim2.new(1, -22, 0, 33), C.CyanSoft)
    U.WebhookState = text(webhookCard, "Webhook: OFF", 9, C.Cyan, UDim2.fromOffset(11, 156), UDim2.new(1, -22, 0, 18))
    text(webhookCard, "Lưu cục bộ. Để URL trống để tắt. Master báo đảo; Dragon gửi ping ID đã lưu.", 9, C.Muted, UDim2.fromOffset(11, 179), UDim2.new(1, -22, 0, 30))
    PHX.connect(U.ApplyWebhook.Activated, function()
        if U.PassThrough then return end
        local ok, message = PHX.setWebhook(U.WebhookBox.Text, U.DiscordIdBox.Text)
        if ok then U.WebhookBox.Text = CONFIG.WEBHOOK_URL; U.DiscordIdBox.Text = CONFIG.WEBHOOK_USER_ID end
        U.notice(message, ok)
        U.updateControls()
    end)
    local performance = card(settingsPage, 136, 4)
    text(performance, "✦ HIỆU NĂNG", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.CpuState = text(performance, "", 10, C.Text, UDim2.fromOffset(11, 30), UDim2.new(1, -22, 0, 26))
    text(performance, "Ẩn/hiện map bằng nút riêng ở góc màn hình.", 9, C.Muted, UDim2.fromOffset(11, 60), UDim2.new(1, -22, 0, 25))
    text(performance, "FPS CAP", 10, C.Muted, UDim2.fromOffset(11, 93), UDim2.fromOffset(90, 25), Enum.Font.GothamBold)
    local minus = button(performance, "−", UDim2.new(1, -141, 0, 91), UDim2.fromOffset(30, 30))
    U.FpsLabel = text(performance, tostring(CONFIG.SAVE_CPU.FPS_CAP), 12, C.Text, UDim2.new(1, -109, 0, 92), UDim2.fromOffset(63, 27), Enum.Font.GothamBold)
    U.FpsLabel.TextXAlignment = Enum.TextXAlignment.Center
    local plus = button(performance, "+", UDim2.new(1, -41, 0, 91), UDim2.fromOffset(30, 30))
    local function changeFps(amount)
        if U.PassThrough then return end
        if type(setfpscap) ~= "function" then U.notice("Executor chưa hỗ trợ FPS cap.", false); return end
        local target = math.clamp(CONFIG.SAVE_CPU.FPS_CAP + amount, 15, 120)
        local ok, err = pcall(setfpscap, target)
        if ok then CONFIG.SAVE_CPU.FPS_CAP = target; U.FpsLabel.Text = tostring(target) end
        U.notice(ok and ("FPS cap: " .. target) or ("FPS error: " .. tostring(err)), ok)
    end
    PHX.connect(minus.Activated, function() changeFps(-5) end)
    PHX.connect(plus.Activated, function() changeFps(5) end)
    local controls = card(settingsPage, 113, 5)
    text(controls, "♡ CỬA SỔ / PHIÊN CHẠY", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    text(controls, "Kéo thanh tiêu đề bằng chuột hoặc cảm ứng. Thu gọn bằng nút −; UI luôn giữ nguyên khi tương tác game.", 10, C.Muted, UDim2.fromOffset(11, 29), UDim2.new(1, -22, 0, 41))
    local unload = button(controls, "DỪNG & GỠ UI", UDim2.fromOffset(11, 77), UDim2.new(1, -22, 0, 28), C.RedSoft)
    unload.TextColor3 = C.Red
    PHX.connect(unload.Activated, function() if not U.PassThrough then PHX.destroy() end end)

    local activity = U.Pages.ACTIVITY
    local diagnostics = card(activity, 163, 1)
    text(diagnostics, "☆ PHIÊN CHẠY / STASH XÁC THỰC", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.Health = text(diagnostics, "", 10, C.Text, UDim2.fromOffset(11, 31), UDim2.new(1, -22, 0, 35))
    U.LogPath = text(diagnostics, "Log: " .. tostring(NIGHT.LogPath), 9, C.Muted, UDim2.fromOffset(11, 70), UDim2.new(1, -22, 0, 29), Enum.Font.Code)
    U.Sync = button(diagnostics, "KIỂM TRA STASH · KHI ĐÃ DỪNG", UDim2.fromOffset(11, 107), UDim2.new(1, -22, 0, 29), C.CyanSoft)
    text(diagnostics, "Dashboard chỉ đọc cache; chết/mất thuyền không mở lại Stash.", 9, C.Muted, UDim2.fromOffset(11, 139), UDim2.new(1, -22, 0, 20))
    PHX.connect(U.Sync.Activated, function()
        if U.PassThrough or U.SyncBusy then return end
        if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then U.notice("Tắt Auto Volcano trước khi kiểm tra Stash thủ công.", false); return end
        if os.clock() - U.LastSyncAt < 5 then return end
        U.SyncBusy = true
        U.LastSyncAt = os.clock()
        U.updateControls()
        PHX.spawn(function()
            local ok, count, reason = pcall(PHX.checkMagnetFromStash, true)
            if not PHX.generationAlive() or not U.Screen.Parent then return end
            U.SyncBusy = false
            U.notice(ok and count ~= nil and ("Stash confirmed · Magnet " .. number(count)) or ("Stash chưa xác nhận: " .. tostring(ok and reason or count)), ok and count ~= nil)
            U.updateControls()
            U.updateCounters()
        end)
    end)
    local logCard = make("Frame", {BackgroundColor3 = C.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2}, activity)
    round(logCard, 12)
    outline(logCard)
    make("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12)}, logCard)
    make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, logCard)
    local heading = text(logCard, "☆ NHẬT KÝ GẦN ĐÂY / MỚI NHẤT TRƯỚC", 9, C.Lavender, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 18), Enum.Font.GothamBold)
    heading.LayoutOrder = 1
    U.ActivityText = text(logCard, "Chưa có log.", 9, C.Text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), Enum.Font.Code)
    U.ActivityText.TextYAlignment = Enum.TextYAlignment.Top
    U.ActivityText.AutomaticSize = Enum.AutomaticSize.Y
    U.ActivityText.LayoutOrder = 2

    local footer = make("Frame", {BackgroundColor3 = C.PinkSoft, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -61), Size = UDim2.new(1, 0, 0, 61)}, U.Root)
    U.Primary = button(footer, "♡ AUTO VOLCANO · TẮT / BẬT", UDim2.fromOffset(11, 8), UDim2.new(1, -22, 0, 33), C.CyanSoft)
    U.Primary.TextColor3 = C.Cyan
    U.FooterText = text(footer, "MASTER + ≥3 SLAVE · ĐỦ 4/5 ĐỂ RA KHƠI", 8, C.Muted, UDim2.fromOffset(11, 44), UDim2.new(1, -22, 0, 13), Enum.Font.GothamMedium)
    U.FooterText.TextXAlignment = Enum.TextXAlignment.Center
    U.Toast = make("TextLabel", {
        Name = "Feedback", Visible = false, ZIndex = 20, BackgroundColor3 = C.Surface,
        BorderSizePixel = 0, TextColor3 = C.Text, Font = Enum.Font.GothamMedium,
        TextSize = 11, TextWrapped = true, Position = UDim2.new(0, 12, 1, -117), Size = UDim2.new(1, -24, 0, 48),
    }, U.Root)
    round(U.Toast, 10)
    U.ToastStroke = outline(U.Toast, C.Cyan, 0)
    make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, U.Toast)
    U.Dock = button(U.Screen, "♡ VOLCANO · MỞ UI", UDim2.fromOffset(12, 100), UDim2.fromOffset(164, 32), C.PinkSoft)
    U.Dock.Visible = false

    -- Nút ẩn/hiện map độc lập, giữ từ script thứ tư.
    -- Auto Volcano không tự bật nút này; dashboard luôn được giữ nguyên.
    U.MapToggle = button(U.Screen, "HIỂN THỊ MAP · BẬT", UDim2.fromOffset(185, 100), UDim2.fromOffset(152, 32), C.LavenderSoft)
    U.MapBusy = false
    PHX.connect(U.MapToggle.Activated, function()
        if U.PassThrough or U.MapBusy then return end
        U.MapBusy = true
        U.MapToggle.Text = "MAP · ĐANG XỬ LÝ..."
        PHX.spawn(function()
            local ok, err = pcall(PHX.setMapVisualHidden, not PHX.MapVisualHidden)
            if not PHX.generationAlive() or not U.Screen.Parent then return end
            U.MapBusy = false
            if not ok then U.notice("Map visuals: " .. tostring(err), false) end
            U.updateControls()
        end)
    end)

    function U.notice(message, success)
        U.Toast.Text = tostring(message)
        U.Toast.TextColor3 = success and C.Cyan or C.Red
        U.ToastStroke.Color = success and C.Cyan or C.Red
        U.Toast.Visible = true
        U.ToastUntil = os.clock() + 5
    end
    function U.minimize(value)
        if U.PassThrough then return end
        U.Minimized = value
        U.Root.Visible = not value
        U.Dock.Visible = value
    end
    PHX.connect(minimize.Activated, function() U.minimize(true) end)
    PHX.connect(U.Dock.Activated, function() U.minimize(false) end)

    -- Tạm nhả input khi click game: không sửa Screen.Enabled hoặc Visible.
    function U.setPassThrough(value)
        value = value == true
        if U.PassThrough == value then return end
        U.PassThrough = value
        if value then
            U.InputRestore = {}
            local focused = Input:GetFocusedTextBox()
            if focused and focused:IsDescendantOf(U.Screen) then focused:ReleaseFocus() end
            for _, object in ipairs(U.Screen:GetDescendants()) do
                if object:IsA("GuiObject") then
                    local entry = {Object = object, Active = object.Active, Selectable = object.Selectable}
                    pcall(function() entry.Interactable = object.Interactable; object.Interactable = false end)
                    if object:IsA("TextBox") then entry.TextEditable = object.TextEditable; object.TextEditable = false end
                    if object:IsA("ScrollingFrame") then entry.ScrollingEnabled = object.ScrollingEnabled; object.ScrollingEnabled = false end
                    object.Active = false
                    object.Selectable = false
                    U.InputRestore[#U.InputRestore + 1] = entry
                end
            end
        else
            for _, entry in ipairs(U.InputRestore or {}) do
                local object = entry.Object
                if object.Parent then
                    object.Active = entry.Active
                    object.Selectable = entry.Selectable
                    if entry.Interactable ~= nil then pcall(function() object.Interactable = entry.Interactable end) end
                    if entry.TextEditable ~= nil then object.TextEditable = entry.TextEditable end
                    if entry.ScrollingEnabled ~= nil then object.ScrollingEnabled = entry.ScrollingEnabled end
                end
            end
            U.InputRestore = nil
            U.updateControls()
        end
    end

    function U.updateViewport()
        local camera = workspace.CurrentCamera
        if not camera then return end
        local viewport = camera.ViewportSize
        local insetA, insetB = Vector2.new(0, 0), Vector2.new(0, 0)
        pcall(function() insetA, insetB = GuiService:GetGuiInset() end)
        U.Bounds = {Left = 8 + insetA.X, Top = 8 + insetA.Y, Right = viewport.X - 8 - insetB.X, Bottom = viewport.Y - 8 - insetB.Y}
        local bounds = U.Bounds
        local width = math.min(448, math.max(1, bounds.Right - bounds.Left))
        local height = math.min(586, math.max(1, bounds.Bottom - bounds.Top - 40))
        U.Root.Size = UDim2.fromOffset(width, height)
        local compact = height < 340
        header.Size = UDim2.new(1, 0, 0, compact and 64 or 72)
        navigation.Position = UDim2.fromOffset(11, compact and 70 or 80)
        for _, page in pairs(U.Pages) do
            page.Position = UDim2.fromOffset(12, compact and 107 or 119)
            page.Size = UDim2.new(1, -24, 1, compact and -172 or -184)
        end
        local point = U.Position or Vector2.new(bounds.Left + 4, bounds.Top + 8)
        U.Position = Vector2.new(math.clamp(point.X, bounds.Left, math.max(bounds.Left, bounds.Right - width)), math.clamp(point.Y, bounds.Top, math.max(bounds.Top, bounds.Bottom - height - 40)))
        U.Root.Position = UDim2.fromOffset(U.Position.X, U.Position.Y)
        U.Dock.Position = UDim2.fromOffset(bounds.Left, math.max(bounds.Top, bounds.Bottom - 32))
        U.MapToggle.Position = UDim2.fromOffset(math.max(bounds.Left, bounds.Right - 152), math.max(bounds.Top, bounds.Bottom - 32))
        U.Primary.TextSize = width < 330 and 10 or 12
    end
    local cameraConnection
    local function bindViewport()
        if cameraConnection then PHX.disconnect(cameraConnection); cameraConnection = nil end
        local camera = workspace.CurrentCamera
        if camera then cameraConnection = PHX.connect(camera:GetPropertyChangedSignal("ViewportSize"), U.updateViewport) end
        U.updateViewport()
    end
    PHX.connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindViewport)
    bindViewport()
    local dragInput, dragStart, startPosition
    PHX.connect(header.InputBegan, function(event)
        if U.PassThrough then return end
        local kind = event.UserInputType
        if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
        if event.Position.X > header.AbsolutePosition.X + header.AbsoluteSize.X - 45 then return end
        if Input:GetFocusedTextBox() then return end
        dragInput = event
        dragStart = Vector2.new(event.Position.X, event.Position.Y)
        startPosition = U.Position
    end)
    PHX.connect(Input.InputChanged, function(event)
        if U.PassThrough or not dragInput or not U.Bounds then return end
        local isTouch = dragInput.UserInputType == Enum.UserInputType.Touch
        if (isTouch and event ~= dragInput) or (not isTouch and event.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
        local target = startPosition + Vector2.new(event.Position.X, event.Position.Y) - dragStart
        local size, bounds = U.Root.AbsoluteSize, U.Bounds
        U.Position = Vector2.new(math.clamp(target.X, bounds.Left, math.max(bounds.Left, bounds.Right - size.X)), math.clamp(target.Y, bounds.Top, math.max(bounds.Top, bounds.Bottom - size.Y - 40)))
        U.Root.Position = UDim2.fromOffset(U.Position.X, U.Position.Y)
    end)
    PHX.connect(Input.InputEnded, function(event)
        if event == dragInput or event.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
    end)

    function U.syncCrewFields()
        U.MasterBox.Text = CONFIG.MASTER_NAME
        U.TeamBox.Text = table.concat(CONFIG.TEAM, "\n")
    end
    function U.refreshPlayers()
        if U.PassThrough then U.PlayersDirty = true; return end
        local players, present = {}, {}
        for _, player in ipairs(Players:GetPlayers()) do
            if not PHX.sameName(player.Name, LP.Name) and not U.PlayerExiting[player.Name] then
                players[#players + 1] = player
                present[player.Name] = true
            end
        end
        table.sort(players, function(a, b)
            local first, second = string.lower(a.Name), string.lower(b.Name)
            return first == second and a.Name < b.Name or first < second
        end)
        for name, row in pairs(U.PlayerRows) do
            if not present[name] then
                PHX.disconnect(row.Connection)
                for index = #U.InputNodes, 1, -1 do
                    if U.InputNodes[index] == row.Control then table.remove(U.InputNodes, index) end
                end
                row.Control:Destroy()
                U.PlayerRows[name] = nil
            end
        end
        for index, player in ipairs(players) do
            local name = player.Name
            local row = U.PlayerRows[name]
            if not row then
                local control = button(U.PlayerList, name, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 34), C.Surface)
                control.Name = "MasterPlayer_" .. name
                control.TextSize = 10
                control.TextTruncate = Enum.TextTruncate.AtEnd
                control.TextWrapped = false
                row = {Control = control}
                row.Connection = PHX.connect(control.Activated, function()
                    if U.PassThrough or ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy or U.SyncBusy then return end
                    local ok, message = PHX.assignMaster(name)
                    if ok then U.syncCrewFields(); U.setPlayerMenu(false) end
                    U.notice(ok and ("Master: " .. CONFIG.MASTER_NAME .. ". Client này là Slave; đặt cùng đội trên cả 5 client.") or message, ok)
                    U.updateControls()
                end)
                U.PlayerRows[name] = row
            end
            row.Control.LayoutOrder = index
            row.Control.Text = name .. (PHX.sameName(name, ENV.TeamConfig.MasterName) and "  · MASTER" or "")
        end
        U.OtherPlayerCount = #players
        U.NoPlayers.Visible = #players == 0
        U.PlayersDirty = false
    end
    PHX.connect(Players.PlayerAdded, function(player)
        U.PlayerExiting[player.Name] = nil
        U.PlayersDirty = true
        if PHX.generationAlive() and U.Screen.Parent then U.refreshPlayers(); U.updateControls() end
    end)
    PHX.connect(Players.PlayerRemoving, function(player)
        U.PlayerExiting[player.Name] = true
        U.PlayersDirty = true
        if PHX.generationAlive() and U.Screen.Parent then U.refreshPlayers(); U.updateControls() end
    end)

    PHX.connect(U.ApplyMaster.Activated, function()
        if U.PassThrough then return end
        local ok, message = PHX.setMaster(U.MasterBox.Text)
        if ok then U.syncCrewFields() end
        U.notice(message, ok)
        U.updateControls()
    end)
    local function editedNames()
        local names = {}
        for name in U.TeamBox.Text:gmatch("[^\r\n,]+") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed ~= "" then names[#names + 1] = trimmed end
        end
        return names
    end
    PHX.connect(U.ApplyCrew.Activated, function()
        if U.PassThrough then return end
        local ok, message = PHX.setTeam(editedNames(), U.MasterBox.Text)
        if ok then U.syncCrewFields() end
        U.notice(message, ok)
        U.updateControls()
    end)
    local clicking = false
    PHX.connect(U.Primary.Activated, function()
        if U.PassThrough or clicking or U.SyncBusy then return end
        clicking = true
        if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then
            PHX.stopAutomation("USER_BUTTON")
            U.notice("Auto Volcano đã tắt.", true)
        else
            local saved, edited = {}, editedNames()
            for i, name in ipairs(CONFIG.TEAM) do saved[i] = name:lower() end
            for i, name in ipairs(edited) do edited[i] = name:lower() end
            if table.concat(saved, "\n") ~= table.concat(edited, "\n") then
                U.notice("Apply danh sách đội trước khi bật Auto Volcano.", false)
            else
                local ok, message = PHX.startAutomation(U.MasterBox.Text)
                if ok then U.MasterBox.Text = CONFIG.MASTER_NAME end
                U.notice(message, ok)
            end
        end
        clicking = false
        U.updateControls()
    end)

    function U.updateControls()
        if U.PlayersDirty then U.refreshPlayers() end
        local running = ENV.TeamConfig.IsRunning == true or PHX.Runtime.StartBusy == true
        local critical = DRAGON_GUARD_STATE and DRAGON_GUARD_STATE.Critical == true
        U.Primary.Text = running and "■ AUTO VOLCANO · BẬT / DỪNG" or "♡ AUTO VOLCANO · TẮT / BẬT"
        U.Primary.BackgroundColor3 = running and C.RedSoft or C.CyanSoft
        U.Primary.TextColor3 = running and C.Red or C.Cyan
        U.StatePill.Text = critical and "CRITICAL" or (running and "RUNNING" or string.upper(PHX.Runtime.RunState or "READY"))
        U.StatePill.TextColor3 = critical and C.Red or (running and C.Cyan or C.Lavender)
        U.Dock.Text = running and "♡ VOLCANO · ĐANG BẬT" or "♡ VOLCANO · MỞ UI"
        U.FooterText.Text = running and "MASTER + ≥3 SLAVE · 4/5 ĐỂ ĐI · SLAVE THỨ 4 CÓ THỂ FARM" or "CÀI ĐẶT CỤC BỘ · CÙNG MASTER + ĐỘI TRÊN CẢ 5 CLIENT"
        local editable = not running and not U.PassThrough and not U.SyncBusy
        U.MasterBox.TextEditable = editable
        U.TeamBox.TextEditable = editable
        for _, control in ipairs({U.ApplyMaster, U.ApplyCrew, U.Sync, U.PlayerMenu}) do
            control.Active = editable
            pcall(function() control.Interactable = editable end)
            control.TextColor3 = editable and C.Cyan or C.Muted
            control.BackgroundColor3 = editable and C.CyanSoft or C.Raised
        end
        U.Sync.Text = U.SyncBusy and "STASH · ĐANG KIỂM TRA..." or (running and "DỪNG AUTO ĐỂ KIỂM TRA STASH" or "KIỂM TRA STASH · KHI ĐÃ DỪNG")
        U.ApplyMaster.Text = running and "KHÓA" or "LƯU"
        U.ApplyCrew.Text = running and "DỪNG AUTO ĐỂ SỬA ĐỘI" or "LƯU ĐỘI NĂM TÀI KHOẢN"
        local master = ENV.TeamConfig.MasterName
        local isMaster = PHX.sameName(LP.Name, master)
        U.RolePill.Text = isMaster and "MASTER / DRIVER" or "SLAVE / PASSENGER"
        U.RoleLabel.Text = "CLIENT: " .. LP.Name .. "  ·  MASTER: " .. tostring(master)
        U.PlayerMenu.Text = "CHỌN MASTER · " .. tostring(U.OtherPlayerCount or 0) .. " PLAYER KHÁC  " .. (U.PlayerMenuOpen and "▴" or "▾")
        for name, row in pairs(U.PlayerRows) do
            local selected = PHX.sameName(name, master)
            row.Control.Text = name .. (selected and "  · MASTER" or "")
            row.Control.Active = editable
            pcall(function() row.Control.Interactable = editable end)
            row.Control.BackgroundColor3 = selected and C.CyanSoft or C.Surface
            row.Control.TextColor3 = editable and (selected and C.Cyan or C.Text) or C.Muted
        end
        for _, entry in ipairs(U.Toggles) do
            local enabled = entry.Read()
            local available = not U.PassThrough and (not entry.RoleLock or editable)
            entry.Control.Active = available
            pcall(function() entry.Control.Interactable = available end)
            entry.Control.Text = enabled and "ON" or "OFF"
            entry.Control.TextColor3 = enabled and (available and C.Cyan or C.Muted) or C.Muted
            entry.Control.BackgroundColor3 = enabled and C.CyanSoft or C.Raised
        end
        local fruit = PHX.FruitAutoState or {}
        U.FruitStatus.Text = "STATUS · " .. tostring(fruit.Status or "READY")
        U.FruitCount.Text = "Trái vật lý: " .. number(fruit.PhysicalCount or 0)
        local remaining = math.max(0, math.ceil((tonumber(fruit.NextRandomAt) or 0) - os.clock()))
        U.FruitCooldown.Text = CONFIG.FRUIT_AUTO.Enabled and (remaining > 0 and ("Random: " .. number(remaining) .. "s") or "Random: READY") or "Random: OFF"
        U.WebhookState.Text = CONFIG.WEBHOOK_URL ~= "" and ("Webhook: " .. tostring(PHX.Runtime.WebhookState or "CONFIGURED")) or "Webhook: OFF"
        U.WebhookBox.TextEditable = not U.PassThrough
        U.DiscordIdBox.TextEditable = not U.PassThrough
        U.ApplyWebhook.Active = not U.PassThrough
        pcall(function() U.ApplyWebhook.Interactable = not U.PassThrough end)
        U.CpuState.Text = "SaveCPU: " .. (SAVE_CPU_APPLIED and "APPLIED" or (CONFIG.SAVE_CPU.ENABLED and "PENDING" or "DISABLED")) .. " · FPS " .. tostring(CONFIG.SAVE_CPU.FPS_CAP)
        if not U.MapBusy then U.MapToggle.Text = PHX.MapVisualHidden and "HIỂN THỊ MAP · TẮT" or "HIỂN THỊ MAP · BẬT" end
        if U.ToastUntil and os.clock() >= U.ToastUntil then U.Toast.Visible = false; U.ToastUntil = nil end
    end
    function U.updateCounters()
        -- Chỉ đọc cache. Không gọi inventoryCount, forceCounterSync hay mở Stash ở đây.
        local scrap, scrapSource = PHX.cachedMaterialCount("Scrap Metal")
        local ember, emberSource = PHX.cachedMaterialCount("Blaze Ember")
        local magnet, magnetSource = PHX.cachedMaterialCount("Volcanic Magnet")
        U.Scrap.Value.Text = number(scrap) .. " / 10"
        U.Ember.Value.Text = number(ember) .. " / 15"
        U.Magnet.Value.Text = number(magnet)
        U.Scrap.Source.Text = scrap ~= nil and sourceLabel(scrapSource) or "CHƯA XÁC NHẬN"
        U.Ember.Source.Text = ember ~= nil and sourceLabel(emberSource) or "CHƯA XÁC NHẬN"
        U.Magnet.Source.Text = magnet ~= nil and sourceLabel(magnetSource) or "CHƯA XÁC NHẬN"
        COUNTER_LABEL.Text = "Scrap " .. number(scrap) .. "/10 | Ember " .. number(ember) .. "/15 | Magnet " .. number(magnet)
    end
    function U.updateCrew()
        local boat = getMasterBoat()
        local driver = boat and PHX.driverSeat(boat)
        local online, aboard = 0, 0
        for index, entry in ipairs(U.CrewRows) do
            local name = CONFIG.TEAM[index]
            local player = name and PHX.playerByName(name)
            local character = player and player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local seat = humanoid and humanoid.SeatPart
            local seated = seat and boat and seat:IsDescendantOf(boat)
            local master = name and PHX.sameName(name, ENV.TeamConfig.MasterName)
            local wrong = seated and ((master and seat ~= driver) or (not master and seat == driver))
            local dead = humanoid and humanoid.Health <= 0
            entry.Name.Text = tostring(name or "--") .. (name and PHX.sameName(name, LP.Name) and " · YOU" or "")
            entry.Role.Text = master and "MASTER / DRIVER" or "SLAVE / PASSENGER"
            entry.Role.TextColor3 = master and C.Cyan or C.Lavender
            entry.State.Text = wrong and "WRONG SEAT" or (dead and "RESPAWN" or (seated and (master and "DRIVING" or "ABOARD") or (player and "ONLINE" or "OFFLINE")))
            entry.State.TextColor3 = (wrong or dead) and C.Red or (seated and C.Cyan or (player and C.Lavender or C.Muted))
            if player then online = online + 1 end
            if seated then aboard = aboard + 1 end
        end
        U.CrewSummary.Text = online .. "/5 online · " .. aboard .. "/5 aboard · cần Master + 3 Slave"
    end
    function U.updateTelemetry()
        local boat = PHX.boatTelemetry()
        U.BoatTitle.Text = "⛵ " .. tostring(boat.Name or "GRAND BRIGADE")
        U.BoatHP.Text = "HP " .. number(boat.HP) .. " / " .. number(boat.MaxHP)
        U.BoatState.Text = tostring(boat.State or "WAIT_MASTER") .. " · " .. number(boat.Aboard) .. "/5 aboard · ≥4 để đi"
        local heading = boat.Heading
        local headingText = typeof(heading) == "Vector3" and string.format("X %.2f / Z %.2f", heading.X, heading.Z) or "đang chờ hướng lái"
        U.SeaState.Text = "SEA 6 · STRAIGHT · " .. headingText
        local snapshot = PHX.eventSnapshot()
        U.Timer.Text = snapshot.Timer ~= nil and tostring(snapshot.Timer) or (snapshot.Active and "HUD chưa rõ" or "--")
        U.Pressure.Text = percent(snapshot.Pressure)
        U.Relic.Text = percent(snapshot.Relic)
        local golems = tonumber(snapshot.GolemCount) or 0
        U.Golems.Text = golems .. " live · " .. number(snapshot.GolemHP) .. " HP"
        U.Golems.TextColor3 = golems > 0 and C.Red or C.Lavender
        U.Phase.Text = golems > 0 and ("♟ GOLEM FIRST · " .. golems .. " LIVE") or ("♡ " .. tostring(snapshot.Phase or PHX.TeamPhase or PHX.Runtime.RunState or "READY"))
        U.EggState.Text = "🥚 EGG · " .. tostring(snapshot.Egg or "WAITING")
        local reason = snapshot.Error or PHX.Runtime.Reason
        local recovery = tostring(PHX.BoatState or PHX.TeamPhase or PHX.Runtime.RunState or "READY")
        U.Recovery.Text = reason and ("RECOVERY / ERROR · " .. tostring(reason)) or ("♡ RECOVERY · " .. recovery .. " · " .. number(NIGHT.RecoveryCount) .. " lần")
        U.Recovery.TextColor3 = snapshot.Error and C.Red or C.Muted
    end
    function U.updateActivity()
        local lines = PHX.Runtime.Activity or NIGHT.MemoryLines or {}
        local recent = {}
        for index = #lines, math.max(1, #lines - 29), -1 do
            local entry = lines[index]
            if type(entry) == "table" then
                local elapsed = tonumber(entry.Time)
                local time = elapsed and string.format("[%dm%02ds] ", math.floor(math.max(0, elapsed - (NIGHT.StartedAt or 0)) / 60), math.floor(math.max(0, elapsed - (NIGHT.StartedAt or 0)) % 60)) or ""
                recent[#recent + 1] = time .. "[" .. tostring(entry.Tag or "LOG") .. "] " .. tostring(entry.Text or "")
            else
                recent[#recent + 1] = tostring(entry)
            end
        end
        local combined = #recent > 0 and table.concat(recent, "\n\n") or tostring(NIGHT.LastStatus or "Chưa có log.")
        if combined ~= U.LastActivity then U.ActivityText.Text = combined; U.LastActivity = combined end
        local elapsed = math.max(0, os.clock() - (NIGHT.StartedAt or os.clock()))
        U.Health.Text = string.format("Uptime %dm %02ds · Recoveries %d\nState: %s · File log: %s", math.floor(elapsed / 60), math.floor(elapsed % 60), tonumber(NIGHT.RecoveryCount) or 0, tostring(PHX.Runtime.RunState or "READY"), NIGHT.FileReady and "WRITING" or "MEMORY")
    end

    U.updateControls()
    pcall(U.updateCounters)
    pcall(U.updateCrew)
    pcall(U.updateTelemetry)
    pcall(U.updateActivity)
    if BOOT_GUI and BOOT_GUI.Parent then BOOT_GUI:Destroy() end
    setStatus("KAWAII TEAM READY | " .. (PHX.sameName(LP.Name, ENV.TeamConfig.MasterName) and "MASTER / DRIVER" or "SLAVE / PASSENGER") .. " | Auto Volcano OFF")
    logLine("UI", "KAWAII TEAM ready | cache-only dashboard | log=" .. tostring(NIGHT.LogPath))
    flushNightLog()
    PHX.spawn(function()
        local ticks = 0
        while PHX.generationAlive() and U.Screen.Parent do
            pcall(U.updateControls)
            pcall(U.updateCounters)
            pcall(U.updateTelemetry)
            ticks = ticks + 1
            if ticks % 3 == 0 then pcall(U.updateCrew); pcall(U.updateActivity) end
            task.wait(0.35)
        end
    end)
end

if PHX.generationAlive() then PHX.buildUI() end
PHX.Runtime.Tasks[coroutine.running()] = nil
