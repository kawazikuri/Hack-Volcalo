-- PX PREHISTORIC V2.17.16 | Golem-only local Humanoid.Health=0 (EXPERIMENT, server kill UNVERIFIED).
-- Forest Pirate, Dragon Hunter, idle NPC combat retain V2.17.15 Recovery NET unchanged.
-- The client can hide a Golem without removing it from the SERVER or protecting Fossil Relic.
-- PX PREHISTORIC V2.17.15 | Tiki first -> Fast Direct BuyBoat after Magnet craft or character reset.
-- Fast Direct uses ONE CommF_ BuyBoat RPC without tweening to Boat Dealer; fallback only after proven rejection.
-- PX PREHISTORIC V2.17.11 | Original Bring + verified-in-test Recovery NET; Egg unchanged
-- NET_HEAD default mirrors isolated PX KillAura Recovery Test V1 (35 studs / 0.30 s).
-- Modes selectable in Settings: NET_HEAD / NET_ROOT / NET_HEAD_0.
-- No independent attack worker when main automation is running; no mouse clicks in combat.
-- V2.17.05 FAST DIRECT BUY BOAT: avoids dealer travel on initial test; preserves one-RPC verification.
-- Plesneviy Xyu CONFIG V2.17.10 | V2.17.08 Bring + Kill Aura donor NET; SOLO Golem first
-- Integration: V2.16.38 main; donor PH_KILL_AURA_TEST_V1; PH_REMOVE_LAVA_TEST_V1; PX STASH TRACKER V4
-- Real-time quantities are client-cache observations; absent records can mean zero OR not replicated.
-- PX PREHISTORIC V2.16.34 | HYDRA/VENOM STABLE HOVER + GOLEM M1 | CLEAN TEST
local SCRIPT_EXECUTED_AT = os.clock() -- deadline starts before PlayerGui or remotes can yield
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")
local PHX = {} -- helper namespace; keeps Delta/Luau main-chunk local count below compiler limit

local ENV = (getgenv and getgenv()) or _G
if ENV.__PH_GACHA_ACCOUNT and ENV.__PH_GACHA_ACCOUNT~=LP.UserId then
    ENV.__PH_DIRECT_GACHA_LAST_SENT=0
    ENV.__PH_DIRECT_GACHA_NEXT_READY=0
    ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY=false
end
ENV.__PH_GACHA_ACCOUNT=LP.UserId
-- Retire standalone donor/recovery tests before their workers compete with main.
for _,key in ipairs({"__PH_REMOVE_LAVA_TEST","__PH_KILL_AURA_TEST","__PX_KILL_AURA_RECOVERY_TEST_V1"}) do
    local donor=ENV[key]
    if type(donor)=="table" and type(donor.Stop)=="function" then
        pcall(donor.Stop,"INTEGRATED_MAIN")
    end
end
-- Remove old standalone stash GUI; its auto loop stops when its ScreenGui is destroyed.
for _,name in ipairs({"PX_STASH_TRACKER_V2","PX_STASH_TRACKER_V3","PX_STASH_TRACKER_V4"}) do
    local old=PG:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
end
if type(ENV.BF_AutoStore_Stop)=="function" then pcall(ENV.BF_AutoStore_Stop) end
if type(ENV.PXGachaV6Cleanup)=="function" then pcall(ENV.PXGachaV6Cleanup) end -- Retire old standalone UI
if ENV.PH_FULL_SOLO_GENERATION~=nil then
    ENV.PH_FULL_SOLO_KILL=true
    ENV.PH_FULL_SOLO_GENERATION=(tonumber(ENV.PH_FULL_SOLO_GENERATION) or 0)+1
end
ENV.PH_VOLCANO_GENERATION = (tonumber(ENV.PH_VOLCANO_GENERATION) or 0) + 1
local SCRIPT_GENERATION = ENV.PH_VOLCANO_GENERATION
ENV.PH_VOLCANO_KILL = false
function PHX.generationAlive()
    return PHX.Runtime ~= nil and PHX.Runtime.Alive
        and not ENV.PH_VOLCANO_KILL and ENV.PH_VOLCANO_GENERATION == SCRIPT_GENERATION
end

PHX.Runtime = {
    Alive = true, RunState = "Ready", ExecutedAt = SCRIPT_EXECUTED_AT, Connections = {}, Tasks = {}, Tweens = {},
    UiReady = false, MarinesReady = false,
    LockOwners = {}, MovementLockLease = nil,
    HeldKeys = {}, HeldPointers = {}, HeldMouse = {}, Activity = {}, MovementObjects = {}, MovementConnections = {}, CollisionOverrides = setmetatable({}, {__mode="k"}),
}
-- Shared movement ownership gate, visible to every travel/hover/fruit controller.
-- Kept on PHX, not a local to avoid crossing Luau main chunk local limits.
function PHX.isMovementLocked()
    return PHX.Runtime~=nil and PHX.Runtime.MovementLockLease~=nil
end

function PHX.releaseBoatMovementLock(lease, reason)
    local runtime=PHX.Runtime
    local active=runtime and runtime.MovementLockLease
    if not active or (lease and active~=lease) then return false end
    runtime.MovementLockLease=nil  -- release ownership first; cleanup may yield through signals
    if active.Heartbeat then pcall(function() active.Heartbeat:Disconnect() end);runtime.Connections[active.Heartbeat]=nil end
    if active.ActionName then pcall(function() ContextActionService:UnbindAction(active.ActionName) end) end
    if active.Humanoid and active.Humanoid.Parent and active.Character==LP.Character then
        pcall(function()
            active.Humanoid.AutoRotate=active.AutoRotate
            active.Humanoid.WalkSpeed=active.WalkSpeed
            active.Humanoid.JumpPower=active.JumpPower
            active.Humanoid.JumpHeight=active.JumpHeight
        end)
    end
    active.Released=true
    active.ReleaseReason=tostring(reason or "DONE")
    print("[PX V2.16.38] [MOVEMENT_UNLOCKED] "..active.ReleaseReason)
    return true
end

if type(ENV.PHX_PreviousRuntime) == "table" and type(ENV.PHX_PreviousRuntime.destroy) == "function" then
    pcall(ENV.PHX_PreviousRuntime.destroy)
end
ENV.PHX_PreviousRuntime = PHX
PHX.Runtime.Tasks[coroutine.running()] = true -- cancel a superseded startup even while it yields

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

function PHX.ownsStartPreparation()
    local runtime=PHX.Runtime
    local owner=runtime and runtime.LockOwners and runtime.LockOwners.StartBusy
    return runtime and runtime.StartBusy==true and owner
        and owner.Container==runtime and owner.Key=="StartBusy" and owner.Name=="StartBusy"
        and owner.Owner==coroutine.running() and runtime.StartThread==owner.Owner or false
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
    if PHX.releaseBoatMovementLock then pcall(PHX.releaseBoatMovementLock,nil,"RUNTIME_CLEANUP") end
    if PHX.Runtime.FruitApproachCleanup then pcall(PHX.Runtime.FruitApproachCleanup) end
    if PHX.stopBoat then pcall(PHX.stopBoat) end
    if PHX.restoreTravel then pcall(PHX.restoreTravel) end
    if PHX.restoreGolemChanges then pcall(PHX.restoreGolemChanges) end
    -- Remove Lava must NOT be stopped by routine movement restoration.
    -- restoreMovement is also called by Auto OFF and TEAM/SOLO mode switches.
    if PHX.killAuraRelease then pcall(PHX.killAuraRelease) end
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
    -- Only full script unload is allowed to retire the independent Lava scanner.
    if PHX.removeLavaStop then pcall(PHX.removeLavaStop) end
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

PHX.spawn(function()
    while PHX.Runtime.Alive do
        task.wait(.1)
        if not PHX.generationAlive() then PHX.destroy(); return end
    end
end)

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
BOOT_LABEL.Text = "VOLCANO TEAM + SOLO V2.17.12\nLoading automation..."
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

BOOT_LABEL.Text = "VOLCANO TEAM + SOLO V2.17.12\nLoaded core, building UI..."

local CONFIG = {
    MIN_SLAVES_TO_SAIL = 3, -- Master + at least three live passenger Slaves.
    TEAM_TRUSTED_SLAVES = {},
    WEBHOOK_USER_ID = "", -- Discord user ID; receive Dragon East/West mentions.
    PROTECT_HELD_DRAGON = true, -- A reset always requires confirmed Dragon storage.
    FRUIT_AUTO = {Enabled=false, AutoStore=true, AutoApproachNPC=false, LegacyRemote=false, TickSeconds=5, RandomInterval=7200, RollVerifySeconds=35,
        MaxBackoff=300, StoreVerifySeconds=2},
    FARM_COMBAT = {
        HitDistance=1500, BringRadius=2200, BringInterval=0.20, BringSize=90,
        HoverAboveMob=13, DamageTimeout=4.5, RecoveryTimeout=10,
        ScrapBringVerifyRadius=8,
        -- V2.17.08: Restore original V2.16.38/V2.17.03 mob bring settings.
        ForestHitboxSize=40, ForestBringInterval=0.11, ForestRebringDrift=3,
        ForestAttackRange=55,
        QuestHitboxSize=16, QuestClusterRadius=3, QuestMobPickupRadius=135,
        QuestScanRadius=600, QuestBringEnabled=true,
        QuestAttackRange=48, QuestHoverGap=18, QuestRebringDrift=4,
        QuestBringInterval=0.11,
        NativeClickGap=0.22, EquipSettle=0.18, MaxWaveSeconds=20,
    },

    MASTER_NAME = nil,
    TEAM = {},
    AUTOMATION_MODE = "TEAM", -- SOLO drives and completes the event with this client alone.

    WEBHOOK_URL = "", -- <<<<<<<<<< PASTE WEBHOOK HERE

    BOAT_NAME = "MarineGrandBrigade",
    BOAT_BUY_NAME = "MarineGrandBrigade",
    BOAT_FAST_BUY = {
        Enabled = true,             -- try CommF_:InvokeServer("BuyBoat", ...) BEFORE dealer travel
        RejectionObserveSeconds = 3.5, -- wait to rule out delayed Beli/boat replication before fallback
    },
    BOAT_NOCLIP = {
        Enabled = true, -- continuous while on the boat (including idle throttle & passengers)
        RefreshSeconds = 0.10, -- re-apply before physics periodically; dynamic parts use descendant signals
    },
    MIN_TEAM_NEAR_RELIC = 4,
    RELIC_RADIUS = 40,

    PLAYER_TWEEN_SPEED = 200,
    PRESSURE_TWEEN_SPEED = 300,
    SOLO_PRESSURE_TWEEN_SPEED = 260, -- Baseline, multiplied by SOLO_GUARD.TWEEN_MULTIPLIER only in SOLO raid.
    SOLO_GUARD = {
        TWEEN_MULTIPLIER = 1.25,
        GOLEM_BASE_TWEEN_SPEED = 165,
        SAFE_APPROACH_CLEARANCE = 30, -- vertical approach above current and enemy Y; then descend to hover
        GOLEM_HOVER_Y = 20, -- keep the melee attacker above ordinary ground/lava height
        -- V2.17.03: SOLO event scheduler ignores distance/pressure thresholds while any Golem lives.
        -- Retained for compatibility with older saved profiles and stall target ordering.
        THREAT_RADIUS = 220,
        RELIC_ALARM_PERCENT = 95,
        PRESSURE_WHILE_FAR_AT = 28,
        PRESSURE_RECOVERY_EXIT = 13,
        PRESSURE_CRITICAL_AT = 80,
        CRITICAL_GOLEM_RADIUS = 130,  -- still used in stalled-Golem target ordering
        STALL_PRIORITY_PENALTY = 65, -- de-prioritize a stalled distant target, not a close one
        PRESSURE_SKILL_GAP = 0.045,  -- shorter time between pressure skills in SOLO only
        PRESSURE_BURST_SECONDS = 1.10,
        BURST_SECONDS = 0.78,         -- re-evaluate risk more frequently
        ATTACK_INTERVAL = 0.09, -- V2.9 donor stable remote cadence
        MELEE_FALLBACK_AFTER = 3.5, -- V2.9 donor: wait for sustained HP stall across bursts
        MELEE_FALLBACK_COOLDOWN = 4.0,
        TARGET_STALL_COOLDOWN = 1.25,
        ROCK_SAFE_HOVER_Y = 45,
        ROCK_UNSAFE_RETRY = 5,
        LAVA_CYLINDER = {
            SAMPLE_DEATH = Vector3.new(-61423.93359375, 786.7953491210938, 12642.5341796875),
            SAMPLE_FOSSIL_PLAYER = Vector3.new(-60632.46875, 55.007808685302734, 12520.9111328125),
            CORE_RADIUS = 30,
            ROUTE_RADIUS = 60, -- core plus 30-stud margin
            HEIGHT = 150, -- from death-sample Y downward
            WAYPOINT_OUTSET = 10, -- arc chords must stay outside R=60
            ARC_STEP_DEGREES = 12,
            MAX_WAYPOINTS = 48,
        },
    },
    BOAT_TWEEN_SPEED = 280, -- requested sea cruising speed (studs/sec)
    FOREST_FARM_HEIGHT = 18, -- retained for secondary forest helpers.
    FOREST_HITBOX_SIZE = 90,
    FOREST_MAGNET_RADIUS = 2200,
    FOREST_SCAN_RADIUS = 1800,
    FOREST_GHOST_TIMEOUT = 10,
    FOREST_GHOST_MIN_ATTACKS = 100,
    HOVER_SNAP_DISTANCE = 2.5,
    MELEE_NET_DISTANCE = 1500, -- Magnet V1.9 donor request range; server validates actual hits.
    MELEE_ATTACK_INTERVAL = 0.11,
    MELEE_CLICK_DELAY = 0.05, -- Preserved native attack argument.
    PORTAL_CHAIN_DELAY = 2.5,
    RESPAWN_SETTLE_DELAY = 1.5,
    RESET_TO_TIKI_AFTER_EVENT = true,

    ITEM_COUNTER = {
        CACHE_SECONDS = 0.65,
        OPTIMISTIC_GAIN_SECONDS = 180,
    },
    DIRECT_CACHE = {
        Enabled = true,
        Interval = 3.0, -- do not open the Stash UI or perform an inventory remote call
    },
    REMOVE_LAVA = {
        Enabled = true, -- runs before island spawns; client-only, no guaranteed server damage protection
        Interval = .5,
        Debug = true, -- print on transitions; do not spam each 0.5s scan
    },
    KILL_AURA = {
        Enabled = true, -- shared melee backend inside existing FARM / GOLEM loops
        IdleEnabled = false, -- optional nearby-NPC NET when Auto Volcano is OFF
        IdleMode = "NET", -- Recovery NET only, no native click or Tool:Activate()
        Radius = 35,
        Interval = .20,
        EquipWait = .12,
        MouseHold = .04, -- legacy setting; NET does not use the mouse
        NetMode = "NET_HEAD", -- Recovery Test V1 default; choose proven mode in Settings
        NetRange = 35, -- Recovery Test V1 verified-radius profile
        NetGap = .30, -- Recovery Test V1 verified-send cadence
    },

    STASH_UI = {
        STARTUP_DELAY_SECONDS = 2.5, -- begin initial Menu > Items > Stash once HUD and Marines are ready
        SPEED_MULTIPLIER = 2.5, -- faster click/settle steps while preserving UI-state checks
        RETRY_MIN_SECONDS = 5,
        RETRY_MAX_SECONDS = 15,
        ITEMS_SETTLE_SECONDS = 0.28,
        CATEGORY_SETTLE_SECONDS = 0.30,
        FILTER_SETTLE_SECONDS = 0.38,
        CARD_SETTLE_SECONDS = 0.14,
        OPEN_TIMEOUT_SECONDS = 8,
        CATEGORY_TIMEOUT_SECONDS = 8,
        FILTER_TIMEOUT_SECONDS = 8,
        CARD_TIMEOUT_SECONDS = 5,
    },

    DRAGON_GUARD = {
        STORE_RETRIES = 8,
        RETRY_DELAY = 0.35,
        POST_EGG_GUARD_SECONDS = 10.0,
        PRE_RESET_GUARD_SECONDS = 10.0,
    },

    TEAM_PRESSURE_GUARD = {
        SINGLE_ENTER = 30, SINGLE_EXIT = 14,
        DOUBLE_ENTER = 70, DOUBLE_EXIT = 40,
        DOUBLE_SAFE_GOLEM_DISTANCE = 185,
        DOUBLE_EMERGENCY = 88,
    },
    PRESSURE = {
        SKILL_HOLD = 0.03,
        SKILL_GAP = 0.09,
        ROCK_HOVER_Y = 10,
        ASSIST_AT = 8,          -- when no golem, slaves help almost immediately
        EMERGENCY_AT = 42,
        RELIC_ASSIST_AT = 98,
        RELIC_EMERGENCY_AT = 92,
        MAX_BURST_SECONDS = 1.65,
    },

    GOLEM_AURA = {
        APPROACH_DISTANCE = 48,
        HOVER_Y = 14,
        NET_DISTANCE = 135,
        ATTACK_INTERVAL = 0.09,
        BURST_SECONDS = 1.0,
        HITBOX_SIZE = 72,
        BRING_DISTANCE_FROM_RELIC = 195, -- horizontal distance, not distance to player
        MIN_RELIC_DISTANCE = 165, -- hard leash if a Golem approaches the Relic
        CLUSTER_RADIUS = 4,
        BRING_INTERVAL = 0.15,
        REBRING_DRIFT = 8,
        BRING_ENABLED = true, -- shared by TEAM and SOLO; no additional attack worker
        STALL_SECONDS = 4,
    },
    GOLEM_LOCAL_KILL = {
        Enabled = true, -- Golem ONLY: client Humanoid.Health=0, NOT a proven server kill
        Range = 48, -- must physically approach; no remote / cross-map targeting
        RetryGap = 1.5, -- minimum delay to retry an unsuccessful local write
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

    AFK_SOLO = {
        ENABLED = true,
        EGG_FAST_RESET_RELIC_ABOVE = 90, -- strictly greater than 90%
        RELIC_PROOF_MAX_AGE = 180,       -- last measured active-raid HUD
        EGG_RECOVERY_TIMEOUT = 90,       -- after raid end: never wait for missing egg forever
        ERROR_RETRY_GAP = 5,            -- do not spam UI/NPC on repeated failures
    },

    EGG = {
        HOLD_SECONDS = 1.10, -- mobile click/touch hold; fresh inventory still verifies pickup
        RETRIES = 3,
        RETRY_GAP = 0.30,
        SPAWN_WAIT_SECONDS = 12,
        APPROACH_DISTANCE = 4.0,
    },

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
        ForestPirate = CFrame.new(
            -13384.9883, 332.408264, -7814.93359,
            -0.840017498, 4.56535894e-08, 0.542559266,
            1.13496391e-07, 0.99999994, 5.30326076e-08,
            -0.542559206, 7.65943753e-08, -0.840017498
        ),
    },

    -- 2026-10-11: Three quest-tree teleports from player-provided CFrame screenshots.
    -- Screenshot text truncates the last two matrix components, recovered with
    -- row 3 = row 1 x row 2 (orthonormal rotation matrix; display-precision approximation).
    TREES = {
        CFrame.new(
            5347.57959, 1004.18365, 360.519379,
            0.633187354, -1.04531308e-08, -0.773998559,
            -6.83341668e-08, 1, -6.94077045e-08,
            0.773998559, 9.68386274e-08, 0.633187354
        ),
        CFrame.new(
            5238.90723, 1004.18365, 431.421295,
            0.109169416, 9.01457753e-08, -0.994023144,
            -2.92081577e-08, 1, 8.74799895e-08,
            0.994023144, 1.94834454e-08, 0.109169416
        ),
        CFrame.new(
            5260.65918, 1004.18365, 346.302185,
            0.125847995, -1.65535923e-08, -0.992049515,
            -5.53681225e-08, 1, -2.3710065e-08,
            0.992049515, 5.79117832e-08, 0.125847995
        ),
    },
}

ENV.TeamConfig = {Role="NONE", MasterName=nil, IsMaster=false, IsRunning=false}

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

local FOREST_GHOST_BLACKLIST = setmetatable({}, {__mode = "k"})
local FOREST_DAMAGE_TRACK = setmetatable({}, {__mode = "k"})
local ACTIVE_FOREST_MAGNET = {Enabled=false, Anchor=nil, Radius=0, Locked=setmetatable({}, {__mode="k"})}
local FOREST_DAMAGE_PROVEN = false
local ACTIVE_HOVER = {Root=nil, Humanoid=nil, Attachment=nil, Position=nil, Gyro=nil, Target=nil}
local lastIslandWebhookKey = nil
local CHARACTER_EPOCH = 0
PHX.BoatLifeCharacter = LP.Character
PHX.BoatRebuyPending = false
PHX.BoatPurchaseInFlight = false
PHX.BoatPurchasePending = nil -- per-session pending receipt, never persist across respawns
PHX.BoatFastForceDealer = false -- reset after respawn; only fallback after verified fast rejection
PHX.BoatRespawnEpoch = 0
PHX.RejectedBoats = setmetatable({}, {__mode="k"})
PHX.VerifiedSpawnBoats = setmetatable({}, {__mode="k"})
local lastPortalSuccessAt = -math.huge
local boundHumanoids = {}

PHX.UserConfigState={Schema=1,Loaded=false,Applying=false,Saving=false,Available=false,
    DesiredRunning=false,ResumePending=false,NextResumeAt=0,Status="Chưa đọc cấu hình",SelectedMaster=""}

function PHX.userConfigAccountId()
    local value=tonumber(LP and LP.UserId)
    if not value or value~=value or value==math.huge or value<=0 or value~=math.floor(value) then return nil end
    return string.format("%.0f",value)
end

function PHX.userConfigApi()
    local function api(name,value)
        if type(value)=="function" then return value end
        return type(ENV[name])=="function" and ENV[name] or nil
    end
    return {Read=api("readfile",readfile),Write=api("writefile",writefile),IsFile=api("isfile",isfile),
        MakeFolder=api("makefolder",makefolder),IsFolder=api("isfolder",isfolder)}
end

function PHX.sanitizeUserConfig(settings)
    local clean={masterRole=false,selectedMaster="",automationMode="TEAM",desiredRunning=false,
        debugEnabled=true,watchdogRestart=true,returnToTiki=true,randomFruit=false,autoStore=true,
        mapHidden=false,fpsCap=30,webhookURL="",webhookUserId="",gachaNextReadyEpoch=0,gachaLastAttemptEpoch=0,
        auraEnabled=true,auraIdle=false,netMode="NET_HEAD",removeLava=true,boatNoclip=true,fastBoatBuy=true,golemBring=true,golemLocalKill=true,questBring=true}
    if type(settings)~="table" then return clean end
    for _,key in ipairs({"masterRole","desiredRunning","debugEnabled","watchdogRestart","returnToTiki","randomFruit","autoStore","mapHidden","auraEnabled","auraIdle","removeLava","boatNoclip","fastBoatBuy","golemBring","golemLocalKill","questBring"}) do
        if type(settings[key])=="boolean" then clean[key]=settings[key] end
    end
    if settings.automationMode=="TEAM" or settings.automationMode=="SOLO" then clean.automationMode=settings.automationMode end
    if settings.netMode=="NET_HEAD" or settings.netMode=="NET_ROOT" or settings.netMode=="NET_HEAD_0" then
        clean.netMode=settings.netMode
    end
    local fps=tonumber(settings.fpsCap)
    if type(settings.fpsCap)=="number" and fps==fps and fps~=math.huge and fps~=-math.huge then
        clean.fpsCap=math.clamp(math.floor(fps),15,120)
    end
    local selected=type(settings.selectedMaster)=="string" and settings.selectedMaster or ""
    if #selected>=3 and #selected<=20 and selected:match("^[%w_]+$") then clean.selectedMaster=selected end
    local url=type(settings.webhookURL)=="string" and settings.webhookURL:match("^%s*(.-)%s*$") or ""
    if #url<=512 and (url=="" or url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$")
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$")) then clean.webhookURL=url end
    local id=type(settings.webhookUserId)=="string" and settings.webhookUserId:match("^%s*(.-)%s*$") or ""
    if id=="" or (id:match("^%d+$") and #id>=15 and #id<=22) then clean.webhookUserId=id end
    local now=os.time()
    for _,key in ipairs({"gachaNextReadyEpoch","gachaLastAttemptEpoch"}) do
        local epoch=tonumber(settings[key])
        if epoch and epoch==epoch and epoch>=0 and epoch<=now+86400*30 then
            clean[key]=math.floor(epoch)
        end
    end
    return clean
end

function PHX.userConfigSnapshot()
    local state=PHX.UserConfigState
    local master=ENV.TeamConfig.MasterName
    local selected=PHX.LastOtherMaster or (master~=LP.Name and master) or state.SelectedMaster or ""
    return {schema=1,accountId=PHX.userConfigAccountId(),settings=PHX.sanitizeUserConfig({
        masterRole=ENV.TeamConfig.Role=="MASTER",selectedMaster=selected,automationMode=CONFIG.AUTOMATION_MODE,
        desiredRunning=state.DesiredRunning==true,debugEnabled=CONFIG.DEBUG.ENABLED,
        watchdogRestart=CONFIG.DEBUG.WATCHDOG_RESTART,returnToTiki=CONFIG.RESET_TO_TIKI_AFTER_EVENT,
        randomFruit=CONFIG.FRUIT_AUTO.Enabled,autoStore=CONFIG.FRUIT_AUTO.AutoStore,mapHidden=PHX.MapVisualHidden,
        fpsCap=CONFIG.SAVE_CPU.FPS_CAP,webhookURL=CONFIG.WEBHOOK_URL,webhookUserId=CONFIG.WEBHOOK_USER_ID,
        gachaNextReadyEpoch=tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0,
        gachaLastAttemptEpoch=tonumber(ENV.__PH_DIRECT_GACHA_LAST_SENT) or 0,
        auraEnabled=CONFIG.KILL_AURA.Enabled, auraIdle=CONFIG.KILL_AURA.IdleEnabled,
        netMode=CONFIG.KILL_AURA.NetMode,
        removeLava=CONFIG.REMOVE_LAVA.Enabled,boatNoclip=CONFIG.BOAT_NOCLIP.Enabled,
        fastBoatBuy=CONFIG.BOAT_FAST_BUY.Enabled,
        golemBring=CONFIG.GOLEM_AURA.BRING_ENABLED,golemLocalKill=CONFIG.GOLEM_LOCAL_KILL.Enabled,
        questBring=CONFIG.FARM_COMBAT.QuestBringEnabled})}
end

function PHX.applyUserConfig(settings)
    local state=PHX.UserConfigState
    local clean=PHX.sanitizeUserConfig(settings)
    state.Applying=true
    CONFIG.DEBUG.ENABLED=clean.debugEnabled
    CONFIG.DEBUG.WATCHDOG_RESTART=clean.watchdogRestart
    CONFIG.RESET_TO_TIKI_AFTER_EVENT=clean.returnToTiki
    CONFIG.FRUIT_AUTO.Enabled=clean.randomFruit
    CONFIG.FRUIT_AUTO.AutoStore=clean.autoStore
    CONFIG.KILL_AURA.Enabled=clean.auraEnabled
    CONFIG.KILL_AURA.IdleEnabled=clean.auraIdle
    CONFIG.KILL_AURA.NetMode=clean.netMode
    CONFIG.REMOVE_LAVA.Enabled=clean.removeLava
    CONFIG.BOAT_NOCLIP.Enabled=clean.boatNoclip
    CONFIG.BOAT_FAST_BUY.Enabled=clean.fastBoatBuy
    CONFIG.GOLEM_AURA.BRING_ENABLED=clean.golemBring
    CONFIG.GOLEM_LOCAL_KILL.Enabled=clean.golemLocalKill
    CONFIG.FARM_COMBAT.QuestBringEnabled=clean.questBring
    ENV.__PH_DIRECT_GACHA_NEXT_READY=math.max(tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0,clean.gachaNextReadyEpoch)
    ENV.__PH_DIRECT_GACHA_LAST_SENT=math.max(tonumber(ENV.__PH_DIRECT_GACHA_LAST_SENT) or 0,clean.gachaLastAttemptEpoch)
    CONFIG.SAVE_CPU.FPS_CAP=clean.fpsCap
    CONFIG.WEBHOOK_URL,CONFIG.WEBHOOK_USER_ID=clean.webhookURL,clean.webhookUserId
    CONFIG.AUTOMATION_MODE=clean.automationMode
    PHX.Runtime.AutomationMode=clean.automationMode
    PHX.MapVisualHidden=clean.mapHidden
    state.MapNeedsApply=clean.mapHidden
    state.SelectedMaster=clean.selectedMaster
    state.DesiredRunning=clean.desiredRunning
    state.ResumePending=clean.desiredRunning
    state.RestoredRandom=clean.randomFruit
    PHX.LastOtherMaster=clean.selectedMaster~="" and clean.selectedMaster or nil
    local selectedPlayer
    if not clean.masterRole and clean.selectedMaster~="" then
        for _,player in ipairs(Players:GetPlayers()) do
            if string.lower(player.Name)==string.lower(clean.selectedMaster) and player.UserId~=LP.UserId then selectedPlayer=player;break end
        end
    end
    CONFIG.MASTER_NAME=clean.masterRole and LP.Name or (selectedPlayer and selectedPlayer.Name or nil)
    ENV.TeamConfig.MasterName=CONFIG.MASTER_NAME
    ENV.TeamConfig.Role=clean.masterRole and "MASTER" or (selectedPlayer and "SLAVE" or "NONE")
    ENV.TeamConfig.IsMaster=clean.masterRole
    ENV.TeamConfig.ForceMasterRole=clean.masterRole
    ENV.TeamConfig.IsRunning=false -- loading preferences cannot arm the runner
    state.Applying=false
    return true
end

function PHX.loadUserConfig()
    local state=PHX.UserConfigState
    local account=PHX.userConfigAccountId()
    local api=PHX.userConfigApi()
    state.Available=account~=nil and api.Read~=nil and api.Write~=nil and api.IsFile~=nil
    if not state.Available then state.Status="Executor không hỗ trợ lưu/đọc cấu hình file";return false,"CONFIG_FILE_UNAVAILABLE" end
    state.Folder="PH_VOLCANO_CONFIG"
    state.PrimaryPath=state.Folder.."/user_"..account..".json"
    state.FallbackPath="PH_VOLCANO_CONFIG_user_"..account..".json"
    state.Path=api.MakeFolder and state.PrimaryPath or state.FallbackPath
    local path
    for _,candidate in ipairs({state.PrimaryPath,state.FallbackPath}) do
        local ok,exists=pcall(api.IsFile,candidate)
        if not ok then state.Status="Không kiểm tra được file cấu hình";return false,"CONFIG_FILE_CHECK_FAILED" end
        if exists==true then path=candidate;break end
    end
    if not path then state.CreateNew=true;state.Status="Sẽ tạo file cấu hình cho account này";return false,"CONFIG_FILE_MISSING" end
    state.Path=path
    local ok,raw=pcall(api.Read,path)
    if not ok or type(raw)~="string" or #raw>32768 then state.Status="File cấu hình không đọc được; dùng mặc định";return false,"CONFIG_READ_FAILED" end
    local decoded,payload=pcall(function() return HttpService:JSONDecode(raw) end)
    if not decoded or type(payload)~="table" or payload.schema~=1 or type(payload.settings)~="table" then
        state.Status="File cấu hình lỗi hoặc khác phiên bản; dùng mặc định";return false,"CONFIG_SCHEMA_INVALID"
    end
    if tostring(payload.accountId)~=account then state.Status="File cấu hình khác account; dùng mặc định";return false,"CONFIG_ACCOUNT_MISMATCH" end
    PHX.applyUserConfig(payload.settings)
    state.Loaded=true;state.CreateNew=false
    state.Status="Đã khôi phục cấu hình"
    return true,"CONFIG_LOADED"
end

function PHX.saveUserConfig()
    local state=PHX.UserConfigState
    if state.Applying then return false,"CONFIG_RESTORING" end
    if PHX.generationAlive and not PHX.generationAlive() then return false,"CONFIG_RUNTIME_RETIRED" end
    if state.Saving then state.SaveQueued=true;return true,"CONFIG_SAVE_QUEUED" end
    local api=PHX.userConfigApi()
    if not state.Available or not api.Write then state.Status="Executor không hỗ trợ lưu/đọc cấu hình file";return false,"CONFIG_FILE_UNAVAILABLE" end
    local snapshot=PHX.userConfigSnapshot()
    if not snapshot.accountId then return false,"CONFIG_ACCOUNT_INVALID" end
    local primary="PH_VOLCANO_CONFIG/user_"..snapshot.accountId..".json"
    local fallback="PH_VOLCANO_CONFIG_user_"..snapshot.accountId..".json"
    if state.PrimaryPath~=primary or state.FallbackPath~=fallback or (state.Path~=primary and state.Path~=fallback) then
        state.Status="Đường dẫn cấu hình khác account; không ghi file"
        return false,"CONFIG_ACCOUNT_PATH_MISMATCH"
    end
    state.Saving=true
    local encoded,raw=pcall(function() return HttpService:JSONEncode(snapshot) end)
    if not encoded or type(raw)~="string" or #raw>32768 then
        state.Saving=false;state.Status="Không mã hóa được cấu hình";return false,"CONFIG_ENCODE_FAILED"
    end
    if state.Path==state.PrimaryPath and api.MakeFolder then pcall(api.MakeFolder,state.Folder) end
    local wrote,result=pcall(api.Write,state.Path,raw)
    wrote=wrote and result~=false
    if not wrote and state.Path==state.PrimaryPath then
        local fallbackOk,fallbackResult=pcall(api.Write,state.FallbackPath,raw)
        wrote=fallbackOk and fallbackResult~=false
        if wrote then state.Path=state.FallbackPath end
    end
    state.Saving=false
    if not wrote then state.Status="Không ghi được file cấu hình";return false,"CONFIG_WRITE_FAILED" end
    state.SelectedMaster=snapshot.settings.selectedMaster
    state.CreateNew=false;state.Status="Đã lưu cấu hình"
    if state.SaveQueued then
        state.SaveQueued=false
        return PHX.saveUserConfig()
    end
    return true,"CONFIG_SAVED"
end

function PHX.setSavedAutomationIntent(enabled)
    if type(enabled)~="boolean" then return false,"CONFIG_INTENT_INVALID" end
    local state=PHX.UserConfigState
    state.DesiredRunning=enabled
    state.ResumePending=enabled and not ENV.TeamConfig.IsRunning
    state.NextResumeAt=0
    return PHX.saveUserConfig()
end

function PHX.userConfigRestoreReady()
    if not PHX.generationAlive() then return false,"CONFIG_RUNTIME_RETIRED" end
    if os.clock()<(PHX.Runtime.ExecutedAt or SCRIPT_EXECUTED_AT)+math.max(0,tonumber(CONFIG.STASH_UI.STARTUP_DELAY_SECONDS) or 7) then
        return false,"CONFIG_WAIT_INITIAL_STASH_7_SECONDS"
    end
    if PHX.Runtime.UiReady~=true or PHX.Runtime.MarinesReady~=true or not LP.Team or LP.Team.Name~="Marines" then
        return false,"CONFIG_WAIT_UI_MARINES"
    end
    local c=LP.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local r=c and c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health<=0 or not r then return false,"CONFIG_WAIT_LIVING_CHARACTER" end
    local queue=PHX.StashScanQueue
    if not queue or queue.StartupDone~=true or queue.StartupPending or not PHX.StashBaselineReady then
        return false,"CONFIG_WAIT_AUTHORITATIVE_STASH"
    end
    if queue.Busy or PHX.StashSyncBusy or #queue.Jobs>0 then return false,"CONFIG_WAIT_STASH_UPDATE" end
    return true
end

function PHX.resumeSavedAutomation()
    local state=PHX.UserConfigState
    if not state.DesiredRunning or not state.ResumePending then return false,"CONFIG_NO_SAVED_START" end
    local ready,reason=PHX.userConfigRestoreReady()
    if not ready then state.ResumeStatus=reason;return false,reason end
    if ENV.TeamConfig.IsRunning then state.ResumePending=false;return true,"CONFIG_ALREADY_RUNNING" end
    if os.clock()<state.NextResumeAt then return false,"CONFIG_START_BACKOFF" end
    state.NextResumeAt=os.clock()+1
    local ok,why=PHX.startAutomation()
    state.ResumeStatus=ok and "CONFIG_AUTO_RESUMED" or why
    if ok then state.ResumePending=false end
    return ok,why
end

function PHX.userConfigStatus()
    local state=PHX.UserConfigState
    local resume=state.DesiredRunning and state.ResumePending and " · Chờ đủ điều kiện để tự chạy farm" or ""
    return tostring(state.Status or "")..(state.Path and (" · "..state.Path) or "")..resume
end

function PHX.startUserConfigResume()
    local state=PHX.UserConfigState
    if state.CreateNew then PHX.saveUserConfig() end
    PHX.spawn(function()
        if state.MapNeedsApply and PHX.setMapVisualHidden then
            state.MapNeedsApply=false
            pcall(PHX.setMapVisualHidden,true)
        end
        while PHX.generationAlive() do
            PHX.resumeSavedAutomation()
            task.wait(.5)
        end
    end)
end

PHX.loadUserConfig()

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
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return PHX.sameName(name,LP.Name) end
    for _,member in ipairs(CONFIG.TEAM) do
        if PHX.sameName(name, member) then return true end
    end
    return false
end

local function teamIndex(name)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return PHX.sameName(name,LP.Name) and 1 or nil end
    for i,member in ipairs(CONFIG.TEAM) do
        if PHX.sameName(name, member) then return i end
    end
end

function PHX.automationMode()
    local mode=(PHX.Runtime and PHX.Runtime.AutomationMode) or CONFIG.AUTOMATION_MODE
    return mode=="SOLO" and "SOLO" or "TEAM"
end

function PHX.isSoloAutomation()
    return PHX.automationMode()=="SOLO"
end

function PHX.automationLeaderName()
    return PHX.isSoloAutomation() and LP.Name or ENV.TeamConfig.MasterName
end

function PHX.requiredFossilPlayers()
    return PHX.isSoloAutomation() and 1 or CONFIG.MIN_TEAM_NEAR_RELIC
end

local function isMaster()
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return true end
    return ENV.TeamConfig.Role == "MASTER" and PHX.sameName(LP.Name, ENV.TeamConfig.MasterName)
end

local function roleText()
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return "SOLO / BUY BOAT" end
    if isMaster() then return "MASTER / BUY BOAT" end
    return ENV.TeamConfig.Role == "SLAVE" and "SLAVE / PASSENGER" or "CHƯA CÓ ROLE"
end

function PHX.localRole()
    return ENV.TeamConfig.Role or "NONE"
end

function PHX.crewNames()
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return {LP.Name} end
    return CONFIG.TEAM
end

function PHX.refreshCrew(boat)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return {LP.Name} end
    local masterName=ENV.TeamConfig.MasterName
    if not masterName then CONFIG.TEAM={}; return CONFIG.TEAM end
    if boat and boat.Parent and PHX.CrewBoat~=boat then
        PHX.CrewBoat=boat
        PHX.BoardedCrew={}
    end
    PHX.BoardedCrew=PHX.BoardedCrew or {}
    if boat and boat.Parent then
        for _,seat in ipairs(boat:GetDescendants()) do
            if seat:IsA("Seat") and not seat:IsA("VehicleSeat") then
                local occupant=seat.Occupant
                local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
                if player and occupant.Health>0 and player.Character==occupant.Parent and not PHX.sameName(player.Name,masterName) then
                    PHX.BoardedCrew[player.Name]=true
                end
            end
        end
    end
    local names,seen={masterName},{[string.lower(masterName)]=true}
    for name in pairs(PHX.BoardedCrew) do
        if not seen[string.lower(name)] then names[#names+1]=name; seen[string.lower(name)]=true end
    end
    local eventNames=PHX.EventCrews and PHX.ActiveEventCrewIsland and PHX.EventCrews[PHX.ActiveEventCrewIsland]
    for _,name in ipairs(eventNames or {}) do
        if not seen[string.lower(name)] then names[#names+1]=name; seen[string.lower(name)]=true end
    end
    if PHX.localRole()=="SLAVE" and not seen[string.lower(LP.Name)] then names[#names+1]=LP.Name end
    table.sort(names,function(a,b)
        if PHX.sameName(a,b) then return false end
        if PHX.sameName(a,masterName) then return true end
        if PHX.sameName(b,masterName) then return false end
        return string.lower(a)<string.lower(b)
    end)
    CONFIG.TEAM=names
    return names
end

function PHX.freezeEventCrew(island)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        PHX.SoloEventCrews=PHX.SoloEventCrews or setmetatable({}, {__mode="k"})
        PHX.SoloEventCrews[island]=PHX.SoloEventCrews[island] or {LP.Name}
        return PHX.SoloEventCrews[island]
    end
    PHX.EventCrews=PHX.EventCrews or setmetatable({}, {__mode="k"})
    if PHX.EventCrews[island] then return PHX.EventCrews[island] end
    local masterName=ENV.TeamConfig.MasterName
    local names=masterName and {masterName} or {}
    for name in pairs(PHX.BoardedCrew or {}) do
        if not PHX.sameName(name,masterName) then names[#names+1]=name end
    end
    table.sort(names,function(a,b)
        if PHX.sameName(a,b) then return false end
        if PHX.sameName(a,masterName) then return true end
        if PHX.sameName(b,masterName) then return false end
        return string.lower(a)<string.lower(b)
    end)
    if #names >= (tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3)+1 then PHX.EventCrews[island]=names end
    return names
end

function PHX.observeFossilCrew(island,pos,radius)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return PHX.freezeEventCrew(island) end
    local frozen=PHX.EventCrews and PHX.EventCrews[island]
    if frozen then return frozen end
    if not island or not island.Parent or not pos or PHX.eventActive(island) then return nil end
    local masterName=ENV.TeamConfig.MasterName
    if not masterName then return nil end
    local names,masterNear={},false
    for _,player in ipairs(Players:GetPlayers()) do
        local character=player.Character
        local h=character and character:FindFirstChildOfClass("Humanoid")
        local r=character and character:FindFirstChild("HumanoidRootPart")
        if h and h.Health>0 and r and (r.Position-pos).Magnitude <= radius then
            names[#names+1]=player.Name
            if PHX.sameName(player.Name,masterName) then masterNear=true end
        end
    end
    PHX.FossilCrewCandidates=PHX.FossilCrewCandidates or setmetatable({}, {__mode="k"})
    if not masterNear or #names < (tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3)+1 then
        PHX.FossilCrewCandidates[island]=nil
        return nil
    end
    table.sort(names,function(a,b)
        if PHX.sameName(a,b) then return false end
        if PHX.sameName(a,masterName) then return true end
        if PHX.sameName(b,masterName) then return false end
        return string.lower(a)<string.lower(b)
    end)
    local signature=table.concat(names,"|")
    local candidate=PHX.FossilCrewCandidates[island]
    if not candidate or candidate.Signature~=signature then
        PHX.FossilCrewCandidates[island]={Signature=signature,Since=os.clock()}
        return nil
    end
    if os.clock()-candidate.Since < 1 then return nil end
    PHX.EventCrews=PHX.EventCrews or setmetatable({}, {__mode="k"})
    PHX.EventCrews[island]=names
    return names
end

function PHX.rewardCrewIndex(island,name)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        PHX.freezeEventCrew(island)
        return PHX.sameName(name,LP.Name) and 1 or nil,1
    end
    local names=PHX.freezeEventCrew(island)
    if #names < (tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3)+1 then return nil,#names end
    for index,member in ipairs(names) do
        if PHX.sameName(member,name) then return index,#names end
    end
    return nil,#names
end

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
        local wasScriptReset=(os.clock()-(PHX.LastScriptResetAt or -10000))<6
        logLine("DEATH", "cause="..(wasScriptReset and "SCRIPT_RESET_REQUEST" or "UNKNOWN_OR_DAMAGE")..
            " pos="..tostring(r and r.Position or "nil").." status="..tostring(NIGHT.LastStatus))
        setStatus("DIED -> automation paused until respawn")
    end)
end

function PHX.invalidatePreRespawnBoats(newCharacter)
    if PHX.releaseBoatMovementLock then pcall(PHX.releaseBoatMovementLock,nil,"CHARACTER_RESPAWN") end
    local old=PHX.BoatLifeCharacter
    if newCharacter==old then return end
    PHX.BoatLifeCharacter=newCharacter
    if not old then return end -- initial spawn is not a reset
    if not (ENV.TeamConfig.Role=="MASTER" or
        (PHX.isSoloAutomation and PHX.isSoloAutomation()) or
        (PHX.Runtime.AutomationMode or CONFIG.AUTOMATION_MODE)=="SOLO") then return end

    PHX.BoatRespawnEpoch=(PHX.BoatRespawnEpoch or 0)+1
    PHX.BoatRebuyPending=true
    PHX.BoatPurchaseInFlight=false
    PHX.BoatPurchasePending=nil -- old character cannot claim a late-arriving pre-respawn boat
    PHX.BoatFastForceDealer=false -- try one fast direct attempt on new character
    PHX.NextBoatBuyAt=0 -- do not retain stale buy-backoff after a respawn
    PHX.BoatPurchaseAmbiguousUntil=nil
    PHX.BoatsBeforePurchase=nil
    local rejected=0
    local boats=workspace:FindFirstChild("Boats")
    if boats then
        for _,boat in ipairs(boats:GetChildren()) do
            if boat.Name==CONFIG.BOAT_NAME then
                PHX.RejectedBoats[boat]=true
                rejected+=1
            end
        end
    end
    PHX.TeamPhase="RECOVERY"
    PHX.BoatState="REBUY_AFTER_RESPAWN"
    logLine("BOAT_RESPAWN", "epoch="..PHX.BoatRespawnEpoch..
        " rejected_prev_boats="..rejected.." action=BUY_NEW_AT_DEALER")
end

PHX.StashTrackedCharacter=LP.Character
PHX.PostRespawnStashPending=false
PHX.PostRespawnStashEpoch=0
function PHX.flagStashAfterRespawn(character)
    local previous=PHX.StashTrackedCharacter
    if previous==character then return end
    PHX.StashTrackedCharacter=character
    if not previous then return end
    PHX.PostRespawnStashEpoch=PHX.PostRespawnStashEpoch+1
    PHX.PostRespawnStashPending=true
    PHX.ResetOrdinaryApproval=nil
    PHX.StashBaselineReady=false
    PHX.StashLastError=nil
    if PHX.StashSession then PHX.StashSession.Verified=false end
    if PHX.MagnetCache then PHX.MagnetCache.RefreshNeeded=true; PHX.MagnetCache.Checked=false end
    local queue=PHX.StashScanQueue
    if queue then
        queue.StartupPending=true
        queue.StartupDone=false
        queue.StartupFailures=0
        queue.NextStartupAttemptAt=0
    end
    logLine("RESPAWN_STASH", "QUEUED epoch="..PHX.PostRespawnStashEpoch.." | Scrap/Ember/Magnet")
end

PHX.connect(LP.CharacterAdded, function(c)
    PHX.AFKRewardExit=nil -- an old egg receipt never authorizes the next life
    PHX.flagStashAfterRespawn(c)
    PHX.invalidatePreRespawnBoats(c)
    PHX.spawn(function()
        bindCharacter(c)
        c:WaitForChild("HumanoidRootPart", 10)
        task.wait(CONFIG.RESPAWN_SETTLE_DELAY)
        local rr = c:FindFirstChild("HumanoidRootPart")
        logLine("RESPAWN", "pos="..tostring(rr and rr.Position or "nil"))
        if ENV.TeamConfig.IsRunning then
            setStatus(PHX.PostRespawnStashPending and "RESPAWNED -> checking Stash before resuming" or "RESPAWNED -> resuming current route")
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

PHX.TravelState = {Tween=nil, Parts=nil, BoatParts=nil, Boat=nil, BoatMoving=false}

function PHX.restoreTravel()
    -- V2.17.14: movement resets may run while the player is still in the boat.
    -- Never flash CanCollide=true during a seat/auto-pilot transition.
    local h=hum()
    local seat=h and h.SeatPart
    local seatedBoat=seat and PHX.boatForSeat and PHX.boatForSeat(seat)
    local preserveBoatNoclip=seatedBoat and PHX.boatNoclipActive and PHX.boatNoclipActive(seatedBoat)
    if PHX.restoreBoatNoclip and not preserveBoatNoclip then
        pcall(PHX.restoreBoatNoclip,"RESTORE_TRAVEL")
    end
    local state = PHX.TravelState
    if state.Cleanup then pcall(state.Cleanup) end
    if state.Tween then pcall(function() state.Tween:Cancel() end) end
    state.Tween = nil
    for part, collidable in pairs(state.Parts or {}) do
        if part.Parent then pcall(function() part.CanCollide = collidable end) end
    end
    state.Parts = nil
    if not preserveBoatNoclip then
        for part, collidable in pairs(state.BoatParts or {}) do
            if part.Parent then pcall(function() part.CanCollide = collidable end) end
        end
        state.BoatParts = nil
    end
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
    PHX.TravelState.BoatMoving = false
    -- Keep collision disabled while still seated: hand off cleanup to seat-exit guard.
    -- This prevents the next manual W press from crashing into a rock between re-arming passes.
    if PHX.restoreBoatNoclip and not PHX.boatNoclipActive(boat) then
        pcall(PHX.restoreBoatNoclip,"STOP_BOAT_NOT_SEATED")
    end
    if not isMaster() then return false end
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
    if not targetCFrame or not PHX.travelAlive(token) or PHX.isMovementLocked() then return false end
    local c,h,r,epoch = waitAlive(token)
    if PHX.isMovementLocked() then return false end
    if not c or not h or not r or not stopSit(token) then return false end
    if PHX.stopFarmHover then PHX.stopFarmHover() end
    local state = PHX.TravelState
    if state.Cleanup then pcall(state.Cleanup) end
    if state.Tween then pcall(function() state.Tween:Cancel() end) end
    speed=tonumber(speed) or CONFIG.PLAYER_TWEEN_SPEED or 200
    if speed<=0 or speed~=speed or speed==math.huge then return false end
    local MAX_SEGMENT,TARGET_EPS,MAX_TOTAL_SECONDS=48,3,120
    local original,connection,completedConnection,tween={},nil,nil,nil
    local interrupted,arrived,cleaned=false,false,false
    local oldAutoRotate=h.AutoRotate
    local started=os.clock()
    local runtime=PHX.Runtime
    local function disconnect(value)
        if not value then return end
        if runtime and runtime.MovementConnections then runtime.MovementConnections[value]=nil end
        if PHX.disconnect then PHX.disconnect(value) else pcall(function() value:Disconnect() end) end
    end
    local clean
    clean=function()
        if cleaned then return end
        cleaned=true;interrupted=true
        disconnect(completedConnection);disconnect(connection)
        if tween then
            pcall(function() tween:Cancel() end)
            if runtime and runtime.Tweens then runtime.Tweens[tween]=nil end
        end
        for part,collidable in pairs(original) do
            if part.Parent then pcall(function()
                part.CanCollide=collidable
                part.AssemblyLinearVelocity=Vector3.zero
                part.AssemblyAngularVelocity=Vector3.zero
            end) end
        end
        if h.Parent and oldAutoRotate~=nil then pcall(function() h.AutoRotate=oldAutoRotate end) end
        if state.Parts==original then state.Parts=nil end
        if state.Tween==tween then state.Tween=nil end
        if state.Cleanup==clean then state.Cleanup=nil end
    end
    local function active()
        return not interrupted and not PHX.isMovementLocked() and PHX.travelAlive(token) and h.Parent~=nil and h.Health>0
            and r.Parent~=nil and CHARACTER_EPOCH==epoch and h.SeatPart==nil
    end
    local function noclip()
        for _,part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") then
                if original[part]==nil then original[part]=part.CanCollide end
                part.CanCollide=false
                part.AssemblyLinearVelocity=Vector3.zero
                part.AssemblyAngularVelocity=Vector3.zero
            end
        end
    end
    local function segment(goal,duration)
        if not active() then return false end
        local finished,playbackState=false,nil
        local from=r.Position
        tween=TweenService:Create(r,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=goal})
        state.Tween=tween
        if runtime and runtime.Tweens then runtime.Tweens[tween]=true end
        completedConnection=PHX.connect(tween.Completed,function(result)
            finished=true;playbackState=result
        end)
        if runtime and runtime.MovementConnections then runtime.MovementConnections[completedConnection]=true end
        tween:Play()
        while not finished do
            if not active() or os.clock()-started>MAX_TOTAL_SECONDS then interrupted=true;break end
            if PHX.PortalTravel and (r.Position-from).Magnitude>200 then interrupted=true;break end
            task.wait(.03)
        end
        if PHX.PortalTravel and r.Parent and (r.Position-from).Magnitude>200 then interrupted=true end
        local completed=finished and playbackState==Enum.PlaybackState.Completed
        if not completed then interrupted=true end
        disconnect(completedConnection);completedConnection=nil
        if runtime and runtime.Tweens then runtime.Tweens[tween]=nil end
        if not completed or interrupted then pcall(function() tween:Cancel() end) end
        return completed and active()
    end
    local ok,err=pcall(function()
        h.AutoRotate=false
        noclip()
        state.Parts=original;state.Cleanup=clean
        connection=PHX.connect(RunService.Stepped,function()
            if not active() then
                interrupted=true
                if tween then pcall(function() tween:Cancel() end) end
                return
            end
            noclip()
        end)
        if runtime and runtime.MovementConnections then runtime.MovementConnections[connection]=true end
        while active() and os.clock()-started<=MAX_TOTAL_SECONDS do
            local from=r.CFrame
            local distance=(targetCFrame.Position-r.Position).Magnitude
            if distance<=TARGET_EPS then
                if not segment(targetCFrame,math.max(distance/speed,.03)) then break end
                if (r.Position-targetCFrame.Position).Magnitude<=.1 then arrived=true;break end
            else
                local length=math.min(MAX_SEGMENT,distance)
                local goal=from:Lerp(targetCFrame,length/distance)
                if not segment(goal,math.max(length/speed,.04)) then break end
                local beforePause=r.Position
                task.wait(.015)
                if PHX.PortalTravel and r.Parent and (r.Position-beforePause).Magnitude>200 then interrupted=true;break end
            end
        end
    end)
    local success=ok and arrived and active()
    clean()
    if not ok then logLine("MOVE_ERROR",tostring(err));return false end
    return success
end

local function highTween(targetCFrame, speed, token)
    return safeTween(targetCFrame,speed or CONFIG.PLAYER_TWEEN_SPEED,token)
end

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
            if hops <= 1 or node:IsA("BillboardGui") then
                if node:IsA("TextLabel") or node:IsA("TextButton") then labels[#labels + 1] = string.lower(node.Text) end
                local descendants = node:GetDescendants()
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
                            local namedTarget = egg and (text:find("egg", 1, true) or path:find("egg", 1, true))
                                or (not egg and (text:find("fossil", 1, true) or text:find("relic", 1, true)
                                    or path:find("fossil", 1, true) or path:find("relic", 1, true)))
                            if not associated and not namedTarget then return nil end
                            local prompt = path:find("prompt", 1, true) or path:find("interact", 1, true)
                                or text:find("hold", 1, true) or text:find("collect", 1, true)
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
    local function raidSafe(stage)
        if type(PHX.raidResetBlockReason) ~= "function" then
            logLine("RESET_BLOCKED", "RAID_GUARD_UNAVAILABLE | "..stage)
            return false
        end
        local reason=PHX.raidResetBlockReason()
        if reason then
            logLine("RESET_BLOCKED", tostring(reason).." | "..stage)
            setStatus("Reset blocked: Volcano raid not confirmed finished | "..tostring(reason))
            return false
        end
        return true
    end
    if not raidSafe("BEFORE_FRUIT_GUARD") then return false end
    if type(PHX.safeResetGuard)~="function" or not PHX.safeResetGuard(token) then return false end
    if not PHX.travelAlive(token) or not raidSafe("AFTER_FRUIT_GUARD") then return false end
    local previous=LP.Character
    local h=hum()
    if DRAGON_GUARD_STATE.Critical or type(PHX.findPhysicalDragonFruits)~="function" or
        #PHX.findPhysicalDragonFruits()>0 then
        setStatus("Reset blocked: physical Dragon storage not confirmed")
        return false
    end
    if not raidSafe("IMMEDIATE_HP_ZERO_BOUNDARY") then return false end
    local finalFruitOk,finalFruitWhy=PHX.finalFruitResetGuard()
    if not finalFruitOk then
        logLine("RESET_BLOCKED","FINAL_FRUIT_GATE:"..tostring(finalFruitWhy))
        return false
    end
    if h and h.Health>0 then
        PHX.LastScriptResetAt=os.clock()
        logLine("RESET_REQUEST", "SCRIPT_HEALTH_ZERO | at="..tostring(root() and root().Position or "nil")..
            " | event_phase="..tostring(PHX.EventState and PHX.EventState.Phase))
        h.Health=0
    end
    while PHX.travelAlive(token) do
        local c=LP.Character
        local hh=c and c:FindFirstChildOfClass("Humanoid")
        local rr=c and c:FindFirstChild("HumanoidRootPart")
        if c and c~=previous and hh and rr and hh.Health>0 then
            bindCharacter(c)
            task.wait(CONFIG.RESPAWN_SETTLE_DELAY)
            if PHX.PostRespawnStashPending then
                local deadline=os.clock()+35
                logLine("RESPAWN_STASH", "WAITING_FOR_FRESH_STASH_AFTER_SCRIPT_RESET")
                while PHX.travelAlive(token) and PHX.PostRespawnStashPending and os.clock()<deadline do
                    if PHX.processStashScanQueue then PHX.processStashScanQueue() end
                    task.wait(.15)
                end
                if PHX.PostRespawnStashPending then
                    logLine("RESPAWN_STASH", "SCAN_PENDING_OR_FAILED: automation must wait")
                    return false
                end
            end
            return PHX.travelAlive(token)
        end
        task.wait(.15)
    end
    return false
end

local resetBackToTiki

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
            footer={text="Volcano Team + Solo V2.16.0 | "..LP.Name}, timestamp=DateTime.now():ToIsoDate(),
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
    local snapshot=PHX.StashSession
    if snapshot and snapshot.Verified and snapshot.Counts[key]~=nil then
        snapshot.Counts[key]=math.max(0,math.floor(count))
        snapshot.Sources[key]=tostring(source or "CACHE_UPDATE")
    end
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

function PHX.activateOnce(button, physicalClick)
    if not button or not PHX.guiVisible(button) then return false end
    local click=physicalClick or PHX.stashInputClick or PHX.inputClick
    if type(click)=="function" then
        local ok,attempted=pcall(click,button)
        if ok and attempted==true then return true end
    end
    if type(getconnections) == "function" then
        for _,signalName in ipairs({"Activated","MouseButton1Click"}) do
            local found,signal=pcall(function() return button[signalName] end)
            local ok, connections = pcall(function() return found and signal and getconnections(signal) or nil end)
            if ok and type(connections) == "table" then
                local dispatched=false
                for _,connection in ipairs(connections) do
                    local eligible=true
                    pcall(function() eligible=connection.Enabled~=false and connection.Connected~=false end)
                    if eligible then
                        local fired=false
                        if connection.Fire then fired=pcall(function() connection:Fire() end)
                        elseif connection.Function then fired=pcall(function() connection.Function() end) end
                        dispatched=dispatched or fired
                    end
                end
                if dispatched then task.wait(.10);return true end
            end
        end
    end
    return false
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

function PHX.stashStepDelay(seconds)
    local speed=tonumber(CONFIG.STASH_UI and CONFIG.STASH_UI.SPEED_MULTIPLIER) or 1
    if speed<=0 then speed=1 end
    return math.max(0,tonumber(seconds) or 0)/speed
end

function PHX.stashInputClick(button)
    if not button or not PHX.guiVisible(button) then return false end
    local p,z=button.AbsolutePosition,button.AbsoluteSize
    if z.X<=0 or z.Y<=0 then return false end
    local inset=select(1,game:GetService("GuiService"):GetGuiInset())
    local x,y=p.X+z.X/2+inset.X,p.Y+z.Y/2+inset.Y
    local ok=PHX.inputPassthrough(function()
        PHX.mouseEvent(x,y,0,true,game,0)
        task.wait(PHX.stashStepDelay(.07))
        PHX.mouseEvent(x,y,0,false,game,0)
    end)
    task.wait(PHX.stashStepDelay(.10))
    return ok
end

function PHX.stashGuiRendered(object)
    if not object or not object:IsA("GuiObject") or not PHX.guiVisible(object) then return false end
    local size=object.AbsoluteSize
    return size.X>0 and size.Y>0
end

function PHX.stashGuiGeometry(object)
    if not object or not object:IsA("GuiObject") or not PHX.guiVisible(object) then return nil end
    local p,z=object.AbsolutePosition,object.AbsoluteSize
    return table.concat({p.X,p.Y,z.X,z.Y},",")
end

function PHX.waitStashStable(predicate, timeout, settle)
    settle=PHX.stashStepDelay(settle)
    local signature,since=nil,nil
    return PHX.waitGui(function()
        local value=predicate()
        if not value then signature,since=nil,nil;return false end
        if value~=signature then signature,since=value,os.clock() end
        return os.clock()-since>=settle
    end,timeout)
end

function PHX.inventoryActuallyOpen()
    local inv=PHX.inventoryUiRoot()
    if not inv or not PHX.guiVisible(inv) then return false end
    local main=inv:FindFirstChild("Main")
    local header=main and main:FindFirstChild("Header")
    local title=header and header:FindFirstChild("Title")
    if title and (title:IsA("TextLabel") or title:IsA("TextButton")) then
        return PHX.stashGuiRendered(title) and PHX.normalizeItemName(title.Text)=="items"
    end
    return main~=nil and PHX.guiVisible(main) and PHX.stashGuiRendered(PHX.stashGrid())
        and PHX.inventorySearchBox()~=nil
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
    local inv=PHX.inventoryUiRoot()
    local main=inv and inv:FindFirstChild("Main")
    if not inv or not main or not PHX.guiVisible(inv) then return nil end
    local page,header=main:FindFirstChild("PageContent"),main:FindFirstChild("Header")
    local right=inv:FindFirstChild("RightCard")
    local scopes={}
    if page then scopes[#scopes+1]=page end
    if header then scopes[#scopes+1]=header end
    scopes[#scopes+1]=inv
    for _,scope in ipairs(scopes) do
        for _,object in ipairs(scope:GetDescendants()) do
            if object:IsA("TextBox") and PHX.stashGuiRendered(object)
                and not (right and object:IsDescendantOf(right)) then
                local placeholder,name=PHX.normalizeItemName(object.PlaceholderText),PHX.normalizeItemName(object.Name)
                if placeholder:find("search",1,true) or name:find("search",1,true) then return object end
            end
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

function PHX.stashNavigation()
    local inv=PHX.inventoryUiRoot()
    local main=inv and inv:FindFirstChild("Main")
    return main and main:FindFirstChild("NavigationRail")
end

function PHX.stashCategoryLabel(category)
    if not category then return nil end
    local objects={category}
    for _,object in ipairs(category:GetDescendants()) do objects[#objects+1]=object end
    local first=nil
    for _,object in ipairs(objects) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.stashGuiRendered(object) then
            local text=PHX.guiTextNormalized(object):gsub("%s*%(%d+%)%s*$","")
            if text=="stash" or text=="wardrobe" or text=="backpack" or text=="treasure" or text=="build" then return text end
            if text~="" and not first then first=text end
        end
    end
    return first
end

function PHX.stashCategoryButton()
    local nav=PHX.stashNavigation()
    if not nav or not PHX.guiVisible(nav) then return nil,nil end
    for _,category in ipairs(nav:GetChildren()) do
        if PHX.stashCategoryLabel(category)=="stash" then
            local button=PHX.stashTileClickTarget(category)
            if PHX.stashGuiRendered(button) then return button,category end
        end
    end
    local category=nav:FindFirstChild("Category4")
    local label=PHX.stashCategoryLabel(category)
    if category and (label==nil or label=="stash") then
        local button=PHX.stashTileClickTarget(category)
        if PHX.stashGuiRendered(button) then return button,category end
    end
    return nil,nil
end

function PHX.stashSelectedCategory()
    local nav=PHX.stashNavigation()
    if not nav then return nil end
    local selected,bestScore=nil,0
    local function yellow(color)
        return color and color.R>.65 and color.G>.50 and math.min(color.R,color.G)-color.B>.20
    end
    for _,category in ipairs(nav:GetChildren()) do
        local label=PHX.stashCategoryLabel(category)
        if label then
            local score=0
            for _,attribute in ipairs({"Selected","IsSelected"}) do
                local ok,value=pcall(function() return category:GetAttribute(attribute) end)
                if ok and value==true then score=100 end
            end
            local objects={category}
            for _,object in ipairs(category:GetDescendants()) do objects[#objects+1]=object end
            for _,object in ipairs(objects) do
                if PHX.stashGuiRendered(object) then
                    local name=PHX.normalizeItemName(object.Name):gsub("[^%w]","")
                    if name=="selected" or name=="selection" or name=="selectedbackground"
                        or name=="selectionindicator" or name=="selectionmarker" or name=="highlight" then
                        score=math.max(score,80)
                    end
                    local ok,color,alpha=pcall(function() return object.BackgroundColor3,object.BackgroundTransparency end)
                    if ok and alpha and alpha<.5 and yellow(color) then score=math.max(score,40) end
                    if object:IsA("ImageButton") or object:IsA("ImageLabel") then
                        ok,color,alpha=pcall(function() return object.ImageColor3,object.ImageTransparency end)
                        if ok and alpha and alpha<.5 and yellow(color)
                            and (object:IsA("ImageButton") or name:find("background",1,true)
                                or name:find("selected",1,true) or name:find("highlight",1,true)) then
                            score=math.max(score,40)
                        end
                    elseif object:IsA("TextLabel") or object:IsA("TextButton") then
                        ok,color,alpha=pcall(function() return object.TextColor3,object.TextTransparency end)
                        if ok and alpha and alpha<.5 and yellow(color)
                            and PHX.guiTextNormalized(object)==label then score=math.max(score,40) end
                    end
                end
            end
            if score>bestScore then selected,bestScore=category,score
            elseif score>0 and score==bestScore then selected=nil end
        end
    end
    return selected
end

function PHX.stashCategoryConfirmed()
    local selected=PHX.stashSelectedCategory()
    if selected then
        if PHX.stashCategoryLabel(selected)~="stash" then PHX.StashPageAuthority=nil;return false end
        return true
    end
    local proof=PHX.StashPageAuthority
    if proof and proof.Inv==PHX.inventoryUiRoot() and PHX.inventoryActuallyOpen() then
        proof.Grid=PHX.stashGrid()
        return proof.Grid~=nil
    end
    return false
end

function PHX.stashItemsTitle()
    local inv=PHX.inventoryUiRoot()
    local main=inv and inv:FindFirstChild("Main")
    if not main then return nil,nil end
    local title=main:FindFirstChild("ItemsTitle",true)
    local objects={}
    if title then
        objects[#objects+1]=title
        for _,object in ipairs(title:GetDescendants()) do objects[#objects+1]=object end
    end
    for _,object in ipairs(main:GetDescendants()) do objects[#objects+1]=object end
    for _,object in ipairs(objects) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.stashGuiRendered(object) then
            local text=PHX.guiTextNormalized(object)
            local count=text:match("^all%s*%((%d+)%)$") or text:match("^stash%s*%((%d+)%)$")
            if count then return text,tonumber(count),object end
        end
    end
    return nil,nil
end

function PHX.stashResultObject(object)
    local inv=PHX.inventoryUiRoot()
    if not object or not inv or (object~=inv and not object:IsDescendantOf(inv)) then return false end
    local right=inv:FindFirstChild("RightCard")
    local nav=PHX.stashNavigation()
    return not (right and (object==right or object:IsDescendantOf(right)))
        and not (nav and (object==nav or object:IsDescendantOf(nav)))
end

function PHX.stashResultObjects()
    local inv=PHX.inventoryUiRoot()
    local objects={}
    if inv then
        local right=inv:FindFirstChild("RightCard")
        local nav=PHX.stashNavigation()
        for _,object in ipairs(inv:GetDescendants()) do
            if not (right and (object==right or object:IsDescendantOf(right)))
                and not (nav and (object==nav or object:IsDescendantOf(nav))) then
                objects[#objects+1]=object
            end
        end
    end
    return objects
end

function PHX.stashNoItemsFound()
    for _,object in ipairs(PHX.stashResultObjects()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.stashGuiRendered(object)
            then
            local text=PHX.guiTextNormalized(object):gsub("[%.!]+$","")
            if text=="no items found" or text=="no results found" then return true end
        end
    end
    return false
end

function PHX.stashPageLoading()
    local grid=PHX.stashGrid()
    if not grid or not grid.Parent then return true end
    for _,object in ipairs(PHX.stashResultObjects()) do
        if PHX.stashGuiRendered(object) then
            local name=PHX.normalizeItemName(object.Name)
            local text=(object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.guiTextNormalized(object) or ""
            if name:find("loading",1,true) or text=="loading" or text:match("^loading%.+$") then return true end
        end
    end
    return false
end

function PHX.stashVisibleTiles()
    local tiles={}
    local grid=PHX.stashGrid()
    if grid then
        for _,tile in ipairs(grid:GetChildren()) do
            if tostring(tile.Name):match("^Tile%-") then
                local button=PHX.stashTileClickTarget(tile)
                if PHX.guiVisible(tile) and PHX.stashGuiRendered(button) then tiles[#tiles+1]=button end
            end
        end
    end
    return tiles
end

function PHX.stashEmptyResultKind()
    local grid=PHX.stashGrid()
    if not grid or not PHX.guiVisible(grid) or PHX.stashPageLoading() then return nil end
    if PHX.stashNoItemsFound() then return "EMPTY_MESSAGE" end
    if #PHX.stashVisibleTiles()>0 then return nil end
    local _,total=PHX.stashItemsTitle()
    if total==0 then return "ZERO_COUNT_TITLE" end
    if PHX.stashCategoryConfirmed() then return "QUIET_EMPTY_GRID" end
    return nil
end

function PHX.stashResultSignature()
    local title,_,titleObject=PHX.stashItemsTitle()
    local grid=PHX.stashGrid()
    if not grid or not PHX.guiVisible(grid) or PHX.stashPageLoading() then return nil end
    local tiles=PHX.stashVisibleTiles()
    local empty=PHX.stashEmptyResultKind()
    if #tiles==0 and not empty then return nil end
    local parts={title or "NO_COUNT_TITLE",PHX.stashGuiGeometry(titleObject) or "",PHX.stashGuiGeometry(grid) or "",empty or "RESULTS"}
    for _,button in ipairs(tiles) do
        parts[#parts+1]=tostring(button:GetFullName())
        parts[#parts+1]=PHX.stashGuiGeometry(button) or ""
        local objects={button}
        for _,object in ipairs(button:GetDescendants()) do objects[#objects+1]=object end
        for _,object in ipairs(objects) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.stashGuiRendered(object) then
                parts[#parts+1]=PHX.guiTextNormalized(object)
            elseif (object:IsA("ImageLabel") or object:IsA("ImageButton")) and PHX.stashGuiRendered(object) then
                local ok,asset=pcall(function() return object.Image end)
                if ok then parts[#parts+1]=tostring(asset or "") end
            end
        end
    end
    return table.concat(parts,"|")
end

function PHX.stashPageReady()
    local selected=PHX.stashSelectedCategory()
    if selected and PHX.stashCategoryLabel(selected)~="stash" then PHX.StashPageAuthority=nil;return false end
    return PHX.inventoryActuallyOpen() and PHX.stashResultSignature()~=nil
        and PHX.inventorySearchBox()~=nil
end

function PHX.observeStashFilter()
    local revision=0
    local connections={}
    local function watch(signal,descendants)
        if signal then
            local ok,connection=pcall(function() return signal:Connect(function(object)
                if not descendants or PHX.stashResultObject(object) then revision=revision+1 end
            end) end)
            if ok and connection then
                connections[#connections+1]=connection
                if PHX.Runtime and PHX.Runtime.Connections then PHX.Runtime.Connections[connection]=true end
            end
        end
    end
    local grid=PHX.stashGrid()
    local inv=PHX.inventoryUiRoot()
    if grid and inv then
        watch(inv.DescendantAdded,true);watch(inv.DescendantRemoving,true)
        watch(grid.ChildAdded);watch(grid.ChildRemoved)
        for _,object in ipairs(PHX.stashResultObjects()) do
            if object:IsA("GuiObject") and not object:IsA("TextBox") then
                local ok,signal=pcall(function() return object:GetPropertyChangedSignal("Visible") end)
                if ok then watch(signal) end
                if object:IsA("TextLabel") or object:IsA("TextButton") then
                    ok,signal=pcall(function() return object:GetPropertyChangedSignal("Text") end)
                    if ok then watch(signal) end
                end
            end
        end
    end
    return function() return revision end,function()
        for _,connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
            if PHX.Runtime and PHX.Runtime.Connections then PHX.Runtime.Connections[connection]=nil end
        end
    end
end

function PHX.openStashPageExact()
    PHX.StashPageAuthority=nil -- exact-material proof never carries across tab transactions
    local state = {wasOpen=PHX.inventoryActuallyOpen()}
    local existing=PHX.inventoryUiRoot()
    local existingMain=existing and existing:FindFirstChild("Main")
    if not state.wasOpen and existingMain and PHX.guiVisible(existingMain) then
        if not PHX.waitGui(PHX.inventoryActuallyOpen,CONFIG.STASH_UI.OPEN_TIMEOUT_SECONDS) then
            return false,state,"ITEMS_ALREADY_OPEN_NOT_READY"
        end
        state.wasOpen=true
    end
    if not state.wasOpen then
        logLine("STASH_FAST_OPEN","Opening Menu > Items")
        local items = PHX.itemsHudButton()
        if not items or not PHX.guiVisible(items) then
            local hudRoot=PG:FindFirstChild("HUDRoot")
            local f=hudRoot and hudRoot:FindFirstChild("Frame")
            local hud=f and f:FindFirstChild("HUD")
            local col=hud and hud:FindFirstChild("LowerLeftColumn")
            local menu=col and col:FindFirstChild("Menu")
            local toggle=menu and menu:FindFirstChild("Menu")
            if toggle then
                PHX.stashInputClick(toggle)
                local menuOpened=PHX.waitGui(function()
                    local i=PHX.itemsHudButton(); return i and PHX.guiVisible(i)
                end,1.4)
                if not menuOpened then
                    PHX.activateOnce(toggle,function() return false end)
                    PHX.waitGui(function()
                        local i=PHX.itemsHudButton();return i and PHX.guiVisible(i)
                    end,1.6)
                end
            end
            items=PHX.itemsHudButton()
        end
        if not items or not PHX.guiVisible(items) then return false,state,"ITEMS_BUTTON_MISSING" end
        PHX.stashInputClick(items)
        if not PHX.waitGui(PHX.inventoryActuallyOpen,1.8) then
            logLine("STASH_FAST_OPEN","Items did not open after first click; trying Activated once")
            PHX.activateOnce(items,function() return false end)
            if not PHX.waitGui(PHX.inventoryActuallyOpen,2.3) then return false,state,"ITEMS_NOT_OPEN" end
        end
    end
    if not PHX.waitStashStable(function()
        if not PHX.inventoryActuallyOpen() then return nil end
        local button,category=PHX.stashCategoryButton()
        local inv=PHX.inventoryUiRoot()
        return button and table.concat({category:GetFullName(),PHX.stashGuiGeometry(inv),PHX.stashGuiGeometry(button)},"|") or nil
    end,CONFIG.STASH_UI.OPEN_TIMEOUT_SECONDS,CONFIG.STASH_UI.ITEMS_SETTLE_SECONDS) then
        return false,state,"ITEMS_NOT_SETTLED_OR_STASH_BUTTON_MISSING"
    end
    local button=PHX.stashCategoryButton()
    local before=PHX.stashResultSignature()
    local alreadyStash=PHX.stashCategoryConfirmed()
    local revision,stopObserving=PHX.observeStashFilter()
    local categoryStartedAt=os.clock()
    PHX.stashInputClick(button)
    local function selectedAndLoaded()
        local selected=PHX.stashSelectedCategory()
        local grid=PHX.stashGrid()
        if revision()>0 and grid and PHX.inventoryActuallyOpen() and not PHX.stashPageLoading()
            and #PHX.stashVisibleTiles()==0 and (not selected or PHX.stashCategoryLabel(selected)=="stash") then
            PHX.StashPageAuthority={Inv=PHX.inventoryUiRoot(),Grid=grid,ProofCategory="STASH_EMPTY_PAGE_TRANSITION"}
        end
        if not PHX.stashPageReady() then return nil end
        local signature=PHX.stashResultSignature()
        if not alreadyStash and signature==before and PHX.stashCategoryConfirmed() then
            if not PHX.stashEmptyResultKind() or os.clock()-categoryStartedAt<CONFIG.STASH_UI.CATEGORY_TIMEOUT_SECONDS then return nil end
        end
        return signature
    end
    local categoryTimeout=CONFIG.STASH_UI.CATEGORY_TIMEOUT_SECONDS+CONFIG.STASH_UI.CATEGORY_SETTLE_SECONDS+.12
    local ready=PHX.waitStashStable(selectedAndLoaded,categoryTimeout,CONFIG.STASH_UI.CATEGORY_SETTLE_SECONDS)
    if not ready then
        PHX.activateOnce(button,function() return false end)
        ready=PHX.waitStashStable(selectedAndLoaded,categoryTimeout,CONFIG.STASH_UI.CATEGORY_SETTLE_SECONDS)
    end
    stopObserving()
    if not ready then return false,state,"STASH_SELECTION_OR_PAGE_UNCONFIRMED" end
    local after=PHX.stashResultSignature()
    local selected=PHX.stashSelectedCategory()
    if before and after and before~=after and (not selected or PHX.stashCategoryLabel(selected)=="stash") then
        PHX.StashPageAuthority={Inv=PHX.inventoryUiRoot(),Grid=PHX.stashGrid(),ProofCategory="STASH_PAGE_TRANSITION"}
    end
    local search=PHX.inventorySearchBox()
    state.search,state.searchText=search,search.Text
    search.Text=""
    if not PHX.waitStashStable(function()
        if not PHX.stashPageReady() or search.Text~="" then return nil end
        return PHX.stashResultSignature()
    end,CONFIG.STASH_UI.FILTER_TIMEOUT_SECONDS,CONFIG.STASH_UI.FILTER_SETTLE_SECONDS) then
        return false,state,"STASH_CLEAR_FILTER_NOT_SETTLED"
    end
    local emptyKind=PHX.stashEmptyResultKind()
    if emptyKind and emptyKind~="QUIET_EMPTY_GRID" and PHX.stashCategoryConfirmed() then
        PHX.StashPageAuthority=PHX.StashPageAuthority or {Inv=PHX.inventoryUiRoot(),Grid=PHX.stashGrid()}
        PHX.StashPageAuthority.FullEmpty=true
    end
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
        PHX.stashInputClick(button)
        if not PHX.waitGui(function() return not PHX.inventoryActuallyOpen() end,1.5) then PHX.activateOnce(button,function() return false end) end
    end
end

function PHX.readStashItemExact(itemName)
    if not PHX.stashPageReady() then return nil,"STASH_PAGE_UNCONFIRMED" end
    local search=PHX.inventorySearchBox()
    local grid=PHX.stashGrid()
    if not search or not grid then return nil,"SEARCH_OR_GRID_MISSING" end
    local proof=PHX.StashPageAuthority
    if proof and proof.FullEmpty and proof.Inv==PHX.inventoryUiRoot()
        and search.Text=="" and PHX.stashCategoryConfirmed()
        and PHX.stashEmptyResultKind() then return 0,"STASH_ABSENT" end
    if tostring(search.Text)~="" and tostring(search.Text)~=itemName then
        search.Text=""
        if not PHX.waitStashStable(function()
            if not PHX.stashPageReady() or search.Text~="" then return nil end
            return PHX.stashResultSignature()
        end,CONFIG.STASH_UI.FILTER_TIMEOUT_SECONDS,CONFIG.STASH_UI.FILTER_SETTLE_SECONDS) then
            return nil,"STASH_CLEAR_FILTER_NOT_SETTLED"
        end
    end
    local before=PHX.stashResultSignature()
    local oldSearch=tostring(search.Text)
    local changed=oldSearch==itemName
    local revision,stopObserving=PHX.observeStashFilter()
    search.Text=itemName
    local filtered=PHX.waitStashStable(function()
        local selected=PHX.stashSelectedCategory()
        if not PHX.inventoryActuallyOpen() or selected and PHX.stashCategoryLabel(selected)~="stash"
            or search~=PHX.inventorySearchBox() or search.Text~=itemName then return nil end
        if PHX.stashPageLoading() or revision()>0 then changed=true end
        if not PHX.stashPageReady() then return nil end
        local signature=PHX.stashResultSignature()
        if signature~=before then changed=true end
        local _,total=PHX.stashItemsTitle()
        if not changed and total~=0 then
            if not PHX.stashEmptyResultKind() or not PHX.stashCategoryConfirmed() then return nil end
        end
        local tiles=PHX.stashVisibleTiles()
        if #tiles==0 then
            local emptyKind=PHX.stashEmptyResultKind()
            if not emptyKind then return nil end
        end
        return signature
    end,CONFIG.STASH_UI.FILTER_TIMEOUT_SECONDS+CONFIG.STASH_UI.FILTER_SETTLE_SECONDS+.12,CONFIG.STASH_UI.FILTER_SETTLE_SECONDS)
    stopObserving()
    if not filtered then return nil,"STASH_FILTER_NOT_CONFIRMED" end
    local tiles=PHX.stashVisibleTiles()
    local emptyKind=PHX.stashEmptyResultKind()
    if #tiles==0 or emptyKind=="EMPTY_MESSAGE" then
        if not PHX.stashPageReady() or search.Text~=itemName or not emptyKind then return nil,"EMPTY_RESULT_UNCONFIRMED" end
        if not PHX.stashCategoryConfirmed() then return nil,"EMPTY_RESULT_CATEGORY_UNCONFIRMED" end
        return 0,"STASH_ABSENT"
    end
    for _,button in ipairs(tiles) do
        PHX.stashInputClick(button)
        local got=nil
        local function exactCard()
            if not PHX.stashPageReady() or search.Text~=itemName then return nil end
            local title,count=PHX.readSelectedStashCard()
            if PHX.normalizeItemName(title)==PHX.normalizeItemName(itemName) and count~=nil then
                got=count;return tostring(title)..":"..tostring(count)
            end
            return nil
        end
        local matched=PHX.waitStashStable(exactCard,CONFIG.STASH_UI.CARD_TIMEOUT_SECONDS,CONFIG.STASH_UI.CARD_SETTLE_SECONDS)
        if not matched then
            PHX.activateOnce(button,function() return false end)
            matched=PHX.waitStashStable(exactCard,CONFIG.STASH_UI.CARD_TIMEOUT_SECONDS,CONFIG.STASH_UI.CARD_SETTLE_SECONDS)
        end
        if matched then
            PHX.StashPageAuthority={Inv=PHX.inventoryUiRoot(),Grid=PHX.stashGrid(),ProofItem=itemName}
            return math.max(0,math.floor(got)),"STASH_EXACT"
        end
    end
    return nil,"FILTER_RESULT_MISMATCH"
end

-- DIRECT CLIENT CACHE: replaces UI-driven opening / searching Stash.
-- Commit all three items together only after successful GetItems().
-- No network calls, no UI navigation, no implicit module hook.
PHX.DirectCache = {Service=nil, IdMap=nil, LastReadAt=0, LastError=nil, ScanCount=0, Absent={}}
function PHX.directMaterialSnapshot()
    local reader=PHX.DirectCache
    if not reader.Service then
        local module=ReplicatedStorage:FindFirstChild("ItemReplicationService")
        if not module or not module:IsA("ModuleScript") then return nil,"ItemReplicationService missing" end
        reader.Service=require(module)
    end
    if not reader.IdMap then
        local module=ReplicatedStorage:FindFirstChild("IdMap")
        if not module or not module:IsA("ModuleScript") then return nil,"IdMap missing" end
        reader.IdMap=require(module)
    end
    local service=reader.Service
    if type(service)~="table" or not service.IsInitialized then return nil,"SERVICE_NOT_INITIALIZED" end
    if not service.IS_CLIENT then return nil,"NOT_CLIENT_SERVICE" end
    local quantityKey=service.KEYS and service.KEYS.QUANTITY
    if quantityKey==nil then return nil,"QUANTITY_KEY_MISSING" end
    local materials=reader.IdMap and reader.IdMap.Material
    if type(materials)~="table" then return nil,"MATERIAL_MAP_MISSING" end

    local ids,byID,counts,matches={},{},{},{}
    local function normalized(name)
        return tostring(name):lower():gsub("[%s_%-]+","")
    end
    for _,name in ipairs(PHX.MaterialNames) do
        local id=materials[name]
        if id==nil then
            for key,value in pairs(materials) do
                if type(key)=="string" and normalized(key)==normalized(name) then id=value;break end
            end
        end
        if id==nil then return nil,"UNKNOWN_ITEM_ID: "..name end
        ids[name]=id
        byID[tostring(id)]=name
        counts[name]=0
        matches[name]=0
    end
    local records=service:GetItems(quantityKey)
    if records==nil then return nil,"GETITEMS_RETURNED_NIL" end
    local scanned=0
    for _,record in records do
        scanned+=1
        if type(record)=="table" then
            local name=byID[tostring(record.ItemId)]
            if name then
                matches[name]+=1
                local number=tonumber(record.Value)
                if number and number==number and number>=0 and number<math.huge then
                    counts[name]+=number
                end
            end
        end
    end
    return {Counts=counts,Matches=matches,IDs=ids,Scanned=scanned}
end

function PHX.authoritativeStash(force,reason)
    local reader=PHX.DirectCache
    if not PHX.generationAlive() then return false,"RUNTIME_RETIRED" end
    if PHX.StashSyncBusy then return false,"SYNC_BUSY" end
    if not force and PHX.StashBaselineReady then return true,"DIRECT_CACHE_READY" end
    if not CONFIG.DIRECT_CACHE.Enabled then return false,"DIRECT_CACHE_DISABLED" end
    if os.clock()-(reader.LastReadAt or 0)<.2 and PHX.StashBaselineReady then return true,"DIRECT_CACHE_THROTTLED" end
    local lock=PHX.acquireLock(PHX,"StashSyncBusy","stash")
    if not lock then return false,"SYNC_BUSY" end
    local ok,snapshot,why=pcall(PHX.directMaterialSnapshot)
    local success=ok and type(snapshot)=="table"
    local errorText=ok and tostring(why or "CACHE_UNAVAILABLE") or tostring(snapshot)
    if success and PHX.generationAlive() then
        reader.LastReadAt=os.clock()
        reader.ScanCount+=1
        reader.Absent={}
        local sources={}
        for _,name in ipairs(PHX.MaterialNames) do
            local absent=(snapshot.Matches[name] or 0)==0
            reader.Absent[name]=absent
            sources[name]=absent and "DIRECT_CACHE_NO_RECORD" or "DIRECT_CACHE"
            -- A missing record reads as 0, but is NOT proof of an empty Stash.
            local previous=PHX.cachedMaterialCount(name)
            if previous~=snapshot.Counts[name] or not PHX.StashBaselineReady then
                PHX.setKnownMaterial(name,snapshot.Counts[name],sources[name])
            end
        end
        PHX.StashBaselineReady=true
        PHX.StashLastError=nil
        PHX.cacheStashSession(snapshot.Counts,sources)
        if PHX.updateMagnetCache then PHX.updateMagnetCache(snapshot.Counts["Volcanic Magnet"],"DIRECT_CACHE") end
        if PHX.UI and PHX.UI.updateCounters then pcall(PHX.UI.updateCounters) end
        if reader.ScanCount==1 or reader.ScanCount%20==0 then
            logLine("DIRECT_CACHE",string.format("scan=%d records=%d Scrap=%s Ember=%s Magnet=%s",reader.ScanCount,snapshot.Scanned,
                tostring(snapshot.Counts["Scrap Metal"]),tostring(snapshot.Counts["Blaze Ember"]),tostring(snapshot.Counts["Volcanic Magnet"])))
        end
        errorText="DIRECT_CACHE_OK"
    else
        success=false
        reader.LastError=errorText
        PHX.StashLastError=errorText
    end
    PHX.releaseLock(lock)
    return success,errorText
end

function PHX.cachedMaterialCount(itemName)
    local t=ITEM_TRACK[PHX.normalizeItemName(itemName)]
    if t and t.Known then return math.max(0,tonumber(t.Server) or 0),t.Source or "CACHE" end
    return nil,"UNAVAILABLE"
end

function PHX.checkMagnetFromStash(force)
    if force==true then
        local ok,reason=PHX.authoritativeStash(true,"manual Magnet check")
        if not ok then return nil,reason end
    end
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
    if force==true then return PHX.authoritativeStash(true,"manual material check") end
    return PHX.StashBaselineReady,PHX.StashBaselineReady and "STASH_CACHED" or "STARTUP_PENDING"
end

PHX.CounterSyncBusy=false
function PHX.forceCounterSync(force)
    if force==true then return PHX.authoritativeStash(true,"manual sync") end
    return PHX.StashBaselineReady,PHX.StashBaselineReady and "STASH_CACHED" or "STARTUP_PENDING"
end

function PHX.inventoryHasMaterialSchema(inv)
    if type(inv) ~= "table" then return false end
    for _,entry in pairs(inv) do
        if type(entry)=="table" and PHX.normalizeItemName(entry.Type or entry.type)=="material" then return true end
    end
    return false
end

function PHX.serverInventoryCount(itemName, _force)
    return PHX.cachedMaterialCount(itemName)
end

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
PHX.StashScanQueue={StartupPending=true,StartupDone=false,StartupFailures=0,NextStartupAttemptAt=0,Jobs={},Busy=false,NextId=0,CompletedId=0}

function PHX.isMagnetCraftPopup(text)
    local low=PHX.normalizeItemName(tostring(text or ""):gsub("<[^>]+>",""))
    if not low:find("volcanic magnet",1,true) or not low:match("%f[%a]crafted%f[%A]") then return false end
    for _,failure in ipairs({"failed","unable","cannot","can't","not crafted","not enough"}) do
        if low:find(failure,1,true) then return false end
    end
    return true
end

function PHX.queueCraftStashScan(container,signature,text)
    local queue=PHX.StashScanQueue
    if PHX.StashSession then PHX.StashSession.Verified=false end
    queue.NextId=queue.NextId+1
    queue.Jobs[#queue.Jobs+1]={Id=queue.NextId,Container=container,Signature=signature,Text=text}
    logLine("STASH_SCAN_QUEUED","crafted Volcanic Magnet popup #"..queue.NextId)
    return queue.NextId
end

function PHX.inspectPickupContainer(container,allowGain)
    if not PHX.generationAlive() or not container then return end
    if not container.Parent or not PHX.guiVisible(container) then
        PHX.SeenPickupContainers[container]=nil
        return
    end
    local text,crafted=nil,false
    local objects={container}
    for _,object in ipairs(container:GetDescendants()) do objects[#objects+1]=object end
    for _,object in ipairs(objects) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.guiVisible(object) then
            if PHX.isMagnetCraftPopup(object.Text) then text,crafted=tostring(object.Text),true; break end
            if not text and PHX.parsePickupText(object.Text) then text=tostring(object.Text) end
        end
    end
    if not text then return end
    local signature=PHX.normalizeItemName(text:gsub("<[^>]+>",""))
    if PHX.SeenPickupContainers[container] == signature then return end
    PHX.SeenPickupContainers[container]=signature
    if not allowGain then return end -- old notifications precede the fresh baseline
    if crafted then
        PHX.queueCraftStashScan(container,signature,text)
        return
    end
    if PHX.StashBaselineReady and not PHX.StashSyncBusy then
        local name,amount=PHX.parsePickupText(text)
        local suppressed=PHX.PickupSuppress[name]
        if name and not (suppressed and os.clock() <= (suppressed.Until or 0)) then
            PHX.recordItemGain(name,amount,text)
        end
    end
end

function PHX.inspectPickupStack(allowGain)
    if not PHX.generationAlive() then return end
    local notifications=PG:FindFirstChild("Notifications")
    local stack=notifications and notifications:FindFirstChild("NotificationStack")
    if not stack then return end
    for _,container in ipairs(stack:GetChildren()) do PHX.inspectPickupContainer(container,allowGain) end
end

function PHX.cacheStashSession(counts,sources)
    local snapshot={SchemaVersion="STASH_V214_CONFIRMED",JobId=tostring(game.JobId),PlaceId=game.PlaceId,UserId=LP.UserId,Counts={},Sources={},
        Verified=not PHX.StashScanQueue or #PHX.StashScanQueue.Jobs==0}
    for _,name in ipairs(PHX.MaterialNames) do
        local count=tonumber(counts[name])
        if count==nil or count<0 or count~=count or count==math.huge then return false end
        local key=PHX.normalizeItemName(name)
        snapshot.Counts[key]=math.floor(count)
        snapshot.Sources[key]=sources[name] or "STASH_EXACT"
    end
    PHX.StashSession=snapshot
    ENV.__PH_STASH_SESSION=snapshot
    return true
end

function PHX.restoreStashSession()
    local snapshot=ENV.__PH_STASH_SESSION
    if type(snapshot)~="table" or snapshot.SchemaVersion~="STASH_V214_CONFIRMED"
        or snapshot.Verified~=true or tostring(game.JobId)==""
        or snapshot.JobId~=tostring(game.JobId) or snapshot.PlaceId~=game.PlaceId or snapshot.UserId~=LP.UserId
        or type(snapshot.Counts)~="table" or type(snapshot.Sources)~="table" then return false end
    local counts={}
    for _,name in ipairs(PHX.MaterialNames) do
        local count=tonumber(snapshot.Counts[PHX.normalizeItemName(name)])
        if count==nil or count<0 or count~=count or count==math.huge then return false end
        counts[name]=math.floor(count)
    end
    PHX.StashSession=snapshot
    for _,name in ipairs(PHX.MaterialNames) do PHX.setKnownMaterial(name,counts[name],"SESSION_CACHE") end
    PHX.StashBaselineReady=not PHX.PostRespawnStashPending
    PHX.StashStartupAttempted=false
    PHX.StashScanQueue.StartupPending=true
    PHX.StashScanQueue.StartupDone=false
    PHX.updateMagnetCache(counts["Volcanic Magnet"],"SESSION_CACHE")
    return true
end

function PHX.materialGameGuiReady()
    local items=PHX.itemsHudButton()
    if items and PHX.guiVisible(items) and items.AbsoluteSize.X>0 and items.AbsoluteSize.Y>0 then return true end
    local hudRoot=PG:FindFirstChild("HUDRoot")
    local frame=hudRoot and hudRoot:FindFirstChild("Frame")
    local hud=frame and frame:FindFirstChild("HUD")
    local column=hud and hud:FindFirstChild("LowerLeftColumn")
    local menu=column and column:FindFirstChild("Menu")
    local toggle=menu and PHX.stashTileClickTarget(menu:FindFirstChild("Menu"))
    return toggle~=nil and PHX.guiVisible(toggle) and toggle.AbsoluteSize.X>0 and toggle.AbsoluteSize.Y>0
end

function PHX.stashScanSafe()
    return PHX.generationAlive() and not PHX.StashSyncBusy
        and not PHX.StashScanQueue.Busy and CONFIG.DIRECT_CACHE.Enabled
end

function PHX.processStashScanQueue()
    local queue=PHX.StashScanQueue
    if not PHX.stashScanSafe() then return false,"DEFERRED" end
    if not queue.StartupPending and #queue.Jobs==0 then return true,"IDLE" end
    local startup=queue.StartupPending
    local job=not startup and queue.Jobs[1] or nil
    local retryAt=startup and (queue.NextStartupAttemptAt or 0) or (job.NextAttemptAt or 0)
    if os.clock()<retryAt then return false,"RETRY_WAIT" end
    queue.Busy=true
    local stashEpoch=PHX.PostRespawnStashEpoch
    if startup then PHX.StashStartupAttempted=true end
    local ok,result,reason=pcall(PHX.authoritativeStash,true,startup and "execute baseline" or "crafted Magnet popup #"..job.Id)
    queue.Busy=false
    if not PHX.generationAlive() then return false,"RUNTIME_RETIRED" end
    local success=ok and result==true
    local why=ok and reason or tostring(result)
    if stashEpoch~=PHX.PostRespawnStashEpoch then
        success=false
        why="CHARACTER_CHANGED_DURING_STASH_SCAN"
    end
    local failures=startup and (queue.StartupFailures or 0) or (job.Failures or 0)
    if success then
        if startup then
            queue.StartupPending=false
            queue.StartupDone=true
            if PHX.PostRespawnStashPending then
                PHX.PostRespawnStashPending=false
                logLine("RESPAWN_STASH", "VERIFIED epoch="..tostring(stashEpoch).." | Scrap/Ember/Magnet")
            end
            queue.StartupFailures=0
            queue.NextStartupAttemptAt=0
            PHX.Runtime.StartupStatus="Đã xác nhận Scrap / Ember / Magnet trong Stash"
            setStatus(PHX.Runtime.StartupStatus)
        else
            table.remove(queue.Jobs,1)
            queue.CompletedId=job.Id
            queue.LastPopupScan={Id=job.Id,Ok=true,Reason=why,Count=PHX.cachedMaterialCount("Volcanic Magnet")}
        end
        if PHX.StashSession then PHX.StashSession.Verified=#queue.Jobs==0 end
    else
        failures=failures+1
        local settings=CONFIG.STASH_UI or {}
        local minimum=math.max(1,tonumber(settings.RETRY_MIN_SECONDS) or 5)
        local maximum=math.max(minimum,tonumber(settings.RETRY_MAX_SECONDS) or 15)
        local delay=math.min(maximum,minimum*2^math.min(failures-1,8))
        if startup then
            queue.StartupFailures=failures
            queue.NextStartupAttemptAt=os.clock()+delay
            queue.StartupPending=true
            queue.StartupDone=false
            local partial={}
            for _,materialName in ipairs(PHX.MaterialNames) do
                local known=PHX.cachedMaterialCount(materialName)
                if known~=nil then
                    local short=materialName=="Scrap Metal" and "Scrap"
                        or (materialName=="Blaze Ember" and "Ember" or "Magnet")
                    partial[#partial+1]=short.."="..tostring(math.floor(known))
                end
            end
            local saved=#partial>0 and ("Đã lưu: "..table.concat(partial," | ").."\n") or ""
            PHX.Runtime.StartupStatus=string.format(
                "%sKho chưa đọc đủ · tự kiểm tra lại sau %.0fs\n%s",
                saved,delay,tostring(why)
            )
            setStatus(PHX.Runtime.StartupStatus)
        else
            job.Failures=failures
            job.NextAttemptAt=os.clock()+delay
            queue.LastPopupAttempt={Id=job.Id,Ok=false,Reason=why}
        end
    end
    return success,why
end

function PHX.waitForCraftInventory(token,afterId,seconds)
    local permit={Token=token,Owner=coroutine.running()}
    PHX.StashScanPermit=permit
    local deadline=os.clock()+(seconds or 8)
    local function release()
        if PHX.StashScanPermit==permit then PHX.StashScanPermit=nil end
    end
    while isRunning(token) and os.clock()<deadline do
        local scan=PHX.StashScanQueue.LastPopupScan
        if scan and scan.Id>afterId then
            release()
            return scan.Ok,scan.Reason
        end
        PHX.processStashScanQueue()
        task.wait(.08)
    end
    release()
    return false,isRunning(token) and "CRAFT_POPUP_NOT_VERIFIED" or "CANCELED"
end

function PHX.startMaterialNotifications()
    PHX.restoreStashSession()
    local watched=setmetatable({}, {__mode="k"})
    local function watchContainer(container,old)
        if watched[container] then return end
        watched[container]=true
        local originalParent=container.Parent
        PHX.inspectPickupContainer(container,not old)
        if container:IsA("GuiObject") then
            PHX.connect(container:GetPropertyChangedSignal("Visible"),function()
                PHX.inspectPickupContainer(container,true)
            end)
        end
        PHX.connect(container.AncestryChanged,function()
            if not container.Parent or container.Parent~=originalParent then
                PHX.SeenPickupContainers[container]=nil
            else
                PHX.inspectPickupContainer(container,true)
            end
        end)
        local function watchText(object)
            if not (object:IsA("TextLabel") or object:IsA("TextButton")) then return end
            PHX.connect(object:GetPropertyChangedSignal("Text"),function() PHX.inspectPickupContainer(container,true) end)
            PHX.connect(object:GetPropertyChangedSignal("Visible"),function() PHX.inspectPickupContainer(container,true) end)
        end
        watchText(container)
        for _,object in ipairs(container:GetDescendants()) do watchText(object) end
        PHX.connect(container.DescendantAdded,function(object)
            watchText(object)
            PHX.defer(function() PHX.inspectPickupContainer(container,true) end)
        end)
    end
    local stacks=setmetatable({}, {__mode="k"})
    local function watchStack(stack,old)
        if stacks[stack] then return end
        stacks[stack]=true
        for _,container in ipairs(stack:GetChildren()) do watchContainer(container,old) end
        PHX.connect(stack.ChildAdded,function(container) watchContainer(container,false) end)
    end
    local notifications=PG:FindFirstChild("Notifications")
    local initial=notifications and notifications:FindFirstChild("NotificationStack")
    if initial then watchStack(initial,true) end
    PHX.connect(PG.DescendantAdded,function(object)
        if object.Name=="NotificationStack" and object.Parent and object.Parent.Name=="Notifications" then watchStack(object,false) end
    end)
    PHX.spawn(function()
        local nextAutoAt=0
        while PHX.generationAlive() do
            PHX.processStashScanQueue()
            local now=os.clock()
            if CONFIG.DIRECT_CACHE.Enabled and PHX.StashBaselineReady and now>=nextAutoAt
                and not PHX.StashScanQueue.Busy and not PHX.StashSyncBusy then
                nextAutoAt=now+math.max(1,tonumber(CONFIG.DIRECT_CACHE.Interval) or 3)
                local ok,why=PHX.authoritativeStash(true,"auto-periodic")
                if not ok and why~="SYNC_BUSY" then
                    if PHX.DirectCache then PHX.DirectCache.LastError=tostring(why) end
                end
            end
            task.wait(.12)
        end
    end)
end

PHX.MagnetCache={Checked=false,Count=nil,Reason="STARTUP_PENDING",RefreshNeeded=false}

function PHX.updateMagnetCache(count,reason)
    PHX.MagnetCache.Count=tonumber(count)
    PHX.MagnetCache.Checked=true
    PHX.MagnetCache.RefreshNeeded=false
    PHX.MagnetCache.Reason=reason or (count~=nil and "STASH" or "UNKNOWN")
end

function PHX.invalidateMagnetCache()
    PHX.SeaHeading=nil
    PHX.MagnetCache.RefreshNeeded=false
end

local function hasVolcanicMagnet()
    local count,source=PHX.cachedMaterialCount("Volcanic Magnet")
    PHX.updateMagnetCache(count,source)
    if count==nil then return nil end
    return count>0
end

function PHX.nativeDiagnostics()
    local lines={"PH NATIVE UI V2.16.0"}
    local function add(key,value)
        lines[#lines+1]=key.." = "..tostring(value==nil and "nil" or value):gsub("[\r\n]"," "):sub(1,240)
    end
    local runtime=PHX.Runtime or {}
    add("UiReady",runtime.UiReady);add("MarinesReady",runtime.MarinesReady)
    add("Team",LP.Team and LP.Team.Name)
    add("Startup",runtime.StartupStatus)
    add("StashError",PHX.StashLastError)
    add("FruitStatus",PHX.FruitAutoState and PHX.FruitAutoState.Status)
    local selected=PHX.stashSelectedCategory and PHX.stashSelectedCategory()
    add("Selected inventory category",selected and PHX.stashCategoryLabel(selected))
    add("Exact material proof",PHX.StashPageAuthority and PHX.StashPageAuthority.ProofItem)
    local purchase,route=nil,nil
    if PHX.gachaPurchaseTarget then purchase,route=PHX.gachaPurchaseTarget() end
    add("Gacha route",route);add("Purchase surface class",purchase and purchase.ClassName)
    local function describe(object)
        if not object then return end
        local ok,path=pcall(function() return object:GetFullName() end)
        local detail=(ok and path or tostring(object.Name)).." ["..tostring(object.ClassName).."]"
        local visible,result=pcall(PHX.guiVisible,object)
        detail=detail.." visible="..tostring(visible and result)
        pcall(function() detail=detail.." size="..object.AbsoluteSize.X.."x"..object.AbsoluteSize.Y end)
        pcall(function() if object:IsA("CanvasGroup") then detail=detail.." groupAlpha="..object.GroupTransparency end end)
        pcall(function()
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                detail=detail.." text="..tostring(object.Text):gsub("[\r\n]"," "):sub(1,90)
            end
        end)
        lines[#lines+1]=detail:sub(1,340)
    end
    local inv=PHX.inventoryUiRoot()
    add("InventoryRoot",inv and inv.Name)
    if inv then
        describe(inv)
        local count=0
        for _,object in ipairs(inv:GetDescendants()) do
            local name=string.lower(tostring(object.Name))
            if object:IsA("TextBox") or name:find("category",1,true) or name:find("search",1,true)
                or name:find("title",1,true) or name:find("selected",1,true) or name=="count"
                or name=="noitemsfound" or name=="tilegrid" or name=="navigationrail" then
                describe(object);count+=1
                if count>=80 then break end
            end
        end
    end
    for _,name in ipairs({"LoadingGui","DialogueGui","ZiolesGacha_Window"}) do
        local window=PG:FindFirstChild(name)
        add(name,window and window.Name)
        if window then
            describe(window)
            for _,object in ipairs(window:GetDescendants()) do
                local key=string.lower(tostring(object.Name))
                if key=="loadingtext" or key=="purchasebutton" or key=="name" or key=="canvasgroup" then describe(object) end
            end
        end
    end
    local npcs=workspace:FindFirstChild("NPCs")
    add("NPCs",npcs and npcs.Name)
    if npcs then
        local count=0
        for _,npc in ipairs(npcs:GetChildren()) do
            if npc:IsA("Model") then
                local name=string.lower(tostring(npc.Name))
                if name:find("zioles",1,true) or name:find("gacha",1,true) or name:find("cousin",1,true) then
                    describe(npc)
                    pcall(function() add(npc.Name.." distance",root() and (npc:GetPivot().Position-root().Position).Magnitude) end)
                end
                count+=1
            end
        end
        add("NPC model count",count)
    end
    return table.concat(lines,"\n")
end

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

local function ensureMarines()
    if not PHX.generationAlive() then return false end
    if LP.Team and LP.Team.Name == "Marines" then
        PHX.Runtime.MarinesReady=true
        PHX.Runtime.MarinesReadyAt=PHX.Runtime.MarinesReadyAt or os.clock()
        return true
    end
    PHX.Runtime.MarinesReady=false
    pcall(function()
        CommF:InvokeServer("SetTeam", "Marines")
    end)
    local deadline = os.clock() + 10
    repeat
        if not PHX.generationAlive() then return false end
        task.wait(.25)
        if LP.Team and LP.Team.Name == "Marines" then
            PHX.Runtime.MarinesReady=true
            PHX.Runtime.MarinesReadyAt=os.clock()
            return true
        end
    until os.clock() > deadline
    return false
end

function PHX.startupStashReady()
    local runtime=PHX.Runtime
    if not PHX.generationAlive() then return false,"RUNTIME_RETIRED" end
    if not CONFIG.DIRECT_CACHE.Enabled then return false,"DIRECT_CACHE_DISABLED" end
    if not runtime.UiReady or not PHX.UI then return false,"WAIT_MAIN_UI" end
    -- No need to join Marines or open Menu > Items > Stash for client cache.
    local queue=PHX.StashScanQueue
    if queue and queue.StartupPending and os.clock()<(queue.NextStartupAttemptAt or 0) then
        return false,"CACHE_RETRY: "..tostring(PHX.StashLastError or "WAITING")
    end
    return true,"Đang đọc ItemReplicationService · không mở Stash"
end

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

local function getToolByTooltip(tooltip)
    local c = char()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if not c or not backpack then return nil end
    for _,container in ipairs({c, backpack}) do
        for _,tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tostring(tool.ToolTip) == tooltip
                and not (PHX.isPhysicalFruitTool and PHX.isPhysicalFruitTool(tool)) then
                return tool
            end
        end
    end
    return nil
end

local function equipTooltip(tooltip)
    local tool=getToolByTooltip(tooltip)
    if not tool then return nil end
    if tool.Parent==char() then return tool end
    local h=hum()
    if not h or h.Health<=0 or h.SeatPart then return nil end
    local ok=pcall(function() h:EquipTool(tool) end)
    if not ok then return nil end
    task.wait(CONFIG.FARM_COMBAT.EquipSettle)
    return tool.Parent==char() and tool or nil
end

local function pressKey(keyCode, hold)
    PHX.keyEvent(true, keyCode, false, game)
    task.wait(hold or .07)
    PHX.keyEvent(false, keyCode, false, game)
end

local function aimAt(pos)
    local r = root()
    if r and not PHX.isMovementLocked() then
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

-- V2.17.12: Weapon-specific skill allowlist. Never fire unavailable melee V/F.
-- Fruit Z/C/V/F remains usable for Pressure Rocks and Quest Trees.
local SKILL_KEYS = {
    ["Melee"] = {Enum.KeyCode.X, Enum.KeyCode.C},
    ["Blox Fruit"] = {Enum.KeyCode.Z, Enum.KeyCode.C, Enum.KeyCode.V, Enum.KeyCode.F},
}
local function skillKeysForTooltip(tooltip)
    return SKILL_KEYS[tooltip] or {}
end
local function skillNamesForTooltip(tooltip)
    return tooltip == "Melee" and "XC" or (tooltip == "Blox Fruit" and "ZCVF" or "NONE")
end

local function useConfiguredSkills(targetPos)
    local function castSet(tooltip)
        local tool = equipTooltip(tooltip)
        if not tool then
            logLine("SKILL_CAST", "missing tooltip="..tostring(tooltip))
            return false
        end
        task.wait(.18)

        for pass=1,2 do
            for _,k in ipairs(skillKeysForTooltip(tooltip)) do
                if targetPos then aimAt(targetPos) end
                pressKey(k, .11)
                task.wait(.17)
            end
            task.wait(.06)
        end
        logLine("SKILL_CAST", tostring(tooltip).." "..skillNamesForTooltip(tooltip).." x2 | "..tostring(tool.Name))
        return true
    end

    if targetPos then aimAt(targetPos) end
    castSet("Melee")
    task.wait(.08)
    castSet("Blox Fruit")
end

local CombatState = nil
local NetAttackCache = { Net = nil, RegisterAttack = nil, RegisterHit = nil }
PHX.FarmCombatDebug={LastDamageAt=os.clock(),LastNet="WAITING",Hits=0,Mode="NET",FailStreak=0,NativeAt=0}
local function observedHealth(models)
    local total,n=0,0
    for _,model in ipairs(models or {}) do
        local h=model and model:FindFirstChildOfClass("Humanoid")
        if h and h.Health>0 then total+=h.Health;n+=1 end
    end
    return total,n
end
local function networkOwned(part)
    if type(isnetworkowner)~="function" then return nil end
    local ok,value=pcall(isnetworkowner,part)
    if ok then return value==true end
    return nil
end
-- V2.17.10: No physical M1 in the combat dispatcher. UI/NPC interactions
-- elsewhere in main remain unchanged.

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
    if NetAttackCache.RegisterAttack and NetAttackCache.RegisterAttack.Parent
        and NetAttackCache.RegisterHit and NetAttackCache.RegisterHit.Parent then
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

function PHX.farmMobRoot(model)
    if not model or not model.Parent or not model:IsA("Model") then return nil,nil end
    local humanoid=model:FindFirstChildOfClass("Humanoid")
    local part=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    if not humanoid or not part or humanoid.Health<=0 then return nil,nil end
    return humanoid,part
end

function PHX.magnetName(value)
    return string.lower(tostring(value or ""))
        :gsub("<.->","")
        :gsub("%s+"," ")
        :gsub("^%s+","")
        :gsub("%s+$","")
end

function PHX.farmMobsNamed(name, center, radius)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return {} end
    local wanted = PHX.magnetName(name)
    local out = {}
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and PHX.magnetName(model.Name):find(wanted,1,true) then
            local humanoid,part = PHX.farmMobRoot(model)
            if humanoid and part then
                if not center or (part.Position-center).Magnitude <= (radius or math.huge) then
                    out[#out+1] = model
                end
            end
        end
    end
    return out
end

local function farmV19BoostSim()
    pcall(function() if setsimulationradius then setsimulationradius(math.huge,math.huge) end end)
    pcall(function() if sethiddenproperty then sethiddenproperty(LP,"SimulationRadius",math.huge) end end)
end

-- Forest Pirates use a separately sized root hitbox; Golem stays unchanged.
PHX.ForestGolemPrepared=setmetatable({}, {__mode="k"})
PHX.ForestGolemLastBring=setmetatable({}, {__mode="k"})
PHX.ForestGolemOriginal=setmetatable({}, {__mode="k"})
PHX.ForestGolemOriginalHumanoids=setmetatable({}, {__mode="k"})

function PHX.restoreForestGolemBring()
    for part,prior in pairs(PHX.ForestGolemOriginal) do
        if part and part.Parent then
            pcall(function()
                part.Size=prior.Size
                part.CanCollide=prior.CanCollide
            end)
        end
        PHX.ForestGolemOriginal[part]=nil
    end
    for humanoid,prior in pairs(PHX.ForestGolemOriginalHumanoids) do
        if humanoid and humanoid.Parent then
            pcall(function()
                humanoid.WalkSpeed=prior.WalkSpeed
                humanoid.JumpPower=prior.JumpPower
                humanoid.AutoRotate=prior.AutoRotate
            end)
        end
        PHX.ForestGolemOriginalHumanoids[humanoid]=nil
    end
    PHX.ForestGolemPrepared=setmetatable({}, {__mode="k"})
    PHX.ForestGolemLastBring=setmetatable({}, {__mode="k"})
end

-- Forest Pirate Bring reverted to V2.16.38 defaults.
-- V2.17.08: Reverted Forest Pirate Bring from the original V2.16.38 lineage.
function PHX.bringForestPiratesLikeGolem(models,anchor)
    if not anchor then return 0,0,0,{} end
    local playerRoot=root()
    if not playerRoot then return 0,0,0,{} end
    local now=os.clock()
    local moved,near,owned=0,0,0
    local candidates={}
    local attackTargets={}
    for _,mob in ipairs(models or {}) do
        local humanoid,mr=PHX.farmMobRoot(mob)
        if humanoid and mr and (mr.Position-playerRoot.Position).Magnitude<=CONFIG.FARM_COMBAT.BringRadius then
            candidates[#candidates+1]={mob=mob,humanoid=humanoid,root=mr}
        end
    end
    local spread= #candidates>1 and CONFIG.GOLEM_AURA.CLUSTER_RADIUS or 0
    for i,entry in ipairs(candidates) do
        local mob,humanoid,mr=entry.mob,entry.humanoid,entry.root
        if networkOwned(mr)==true then owned+=1 end
        if not PHX.ForestGolemPrepared[mob] then
            PHX.ForestGolemPrepared[mob]=true
            for _,body in ipairs(mob:GetDescendants()) do
                if body:IsA("BasePart") then
                    if not PHX.ForestGolemOriginal[body] then
                        PHX.ForestGolemOriginal[body]={Size=body.Size,CanCollide=body.CanCollide}
                    end
                end
            end
            if not PHX.ForestGolemOriginalHumanoids[humanoid] then
                PHX.ForestGolemOriginalHumanoids[humanoid]={WalkSpeed=humanoid.WalkSpeed,JumpPower=humanoid.JumpPower,AutoRotate=humanoid.AutoRotate}
            end
        end
        -- Refresh each tick: the game can restore root size or NPC movement after replication.
        pcall(function()
            mr.Size=Vector3.new(CONFIG.FARM_COMBAT.ForestHitboxSize,CONFIG.FARM_COMBAT.ForestHitboxSize,CONFIG.FARM_COMBAT.ForestHitboxSize)
            mr.CanCollide=false
            humanoid.WalkSpeed=0
            humanoid.JumpPower=0
            humanoid.AutoRotate=false
            for _,body in ipairs(mob:GetDescendants()) do
                if body:IsA("BasePart") then body.CanCollide=false end
            end
        end)
        local angle=(i-1)/math.max(#candidates,1)*math.pi*2
        local slot=CFrame.new(anchor.Position+Vector3.new(math.cos(angle)*spread,0,math.sin(angle)*spread))
        local drift=(mr.Position-slot.Position).Magnitude
        if (PHX.ForestGolemLastBring[mob] or -math.huge)+CONFIG.FARM_COMBAT.ForestBringInterval<=now
            and drift>=CONFIG.FARM_COMBAT.ForestRebringDrift then
            PHX.ForestGolemLastBring[mob]=now
            local ok=pcall(function()
                mob:PivotTo(slot)
                mr.CFrame=slot -- root alignment matters when a model pivot is offset
                mr.AssemblyLinearVelocity=Vector3.zero
                mr.AssemblyAngularVelocity=Vector3.zero
            end)
            if ok then moved+=1 end
        end
        -- Check actual local position AFTER the move, not before.
        if (mr.Position-slot.Position).Magnitude<=CONFIG.FARM_COMBAT.ScrapBringVerifyRadius then
            near+=1
        end
        -- The shared NET dispatcher uses the same nearby Pirate targets.
        if (mr.Position-playerRoot.Position).Magnitude<=CONFIG.FARM_COMBAT.ForestAttackRange then
            attackTargets[#attackTargets+1]=mob
        end
    end
    PHX.FarmCombatDebug.Brought=moved
    PHX.FarmCombatDebug.Owned=owned
    PHX.FarmCombatDebug.Near=near
    PHX.FarmCombatDebug.NetTargets=#attackTargets
    return moved,near,owned,attackTargets
end

function PHX.farmFixedScrapWave(camp,token,completed)
    if not camp or not isRunning(token) then return false end
    -- Keep the player hovering 18 studs above the mob cluster, never chase mobs.
    local mobAnchor=camp*CFrame.new(0,5,0)
    local playerHover=camp*CFrame.new(0,23,0)
    if not highTween(camp*CFrame.new(0,18,0),340,token) then return false end
    if not safeTween(playerHover,360,token) then return false end
    local epoch=CHARACTER_EPOCH
    local playerRoot=root()
    if not playerRoot or not hum() or hum().Health<=0 then return false end
    if not PHX.maintainFarmHover or not PHX.maintainFarmHover(playerHover) then
        logLine("SCRAP_GOLEM_NET","HOVER_FAILED")
        return false
    end
    local ok,finished=pcall(function()
        local models={}
        local spawnUntil=os.clock()+5
        repeat
            if not isRunning(token) or CHARACTER_EPOCH~=epoch then return false end
            if completed and completed() then return true end
            models=PHX.farmMobsNamed("Forest Pirate",camp.Position,CONFIG.FOREST_SCAN_RADIUS)
            if #models>0 then break end
            task.wait(.2)
        until os.clock()>=spawnUntil
        if #models==0 then logLine("SCRAP_GOLEM_NET","NO_MOBS"); return false end
        if not equipTooltip("Melee") then logLine("SCRAP_GOLEM_NET","NO_MELEE"); return false end
        farmV19BoostSim()
        logLine("SCRAP_GOLEM_NET",string.format("START | hoverY=%.1f clusterY=%.1f gap=18 | forestHitbox=%.0f",playerHover.Position.Y,mobAnchor.Position.Y,CONFIG.FARM_COMBAT.ForestHitboxSize))
        local untilTime=os.clock()+CONFIG.FARM_COMBAT.MaxWaveSeconds
        local lastHP,damageAt=nil,os.clock()
        local lastDiag,lastBoost,lastFallback,lastStall=0,0,0,0
        local sent=0
        while isRunning(token) and CHARACTER_EPOCH==epoch and os.clock()<untilTime do
            if completed and completed() then return true end
            local h,r=hum(),root()
            if not h or h.Health<=0 or not r or r~=playerRoot or h.SeatPart then return false end
            if not PHX.maintainFarmHover(playerHover) then
                if not safeTween(playerHover,340,token) or not PHX.maintainFarmHover(playerHover) then return false end
            end
            models=PHX.farmMobsNamed("Forest Pirate",camp.Position,CONFIG.FOREST_SCAN_RADIUS)
            if #models==0 then return true end
            local now=os.clock()
            if now-lastBoost>=3 then farmV19BoostSim();lastBoost=now end
            local brought,near,owned,attackTargets=PHX.bringForestPiratesLikeGolem(models,mobAnchor)
            -- Use shared NET dispatcher; Bring geometry remains original.
            local tool=equipTooltip("Melee")
            local hitOk=false
            if tool and tool.Parent==char() then
                if #attackTargets>0 then hitOk=PHX.killAuraDispatch(attackTargets,"NET") end
                if hitOk then sent+=1 end
            end
            local hp=observedHealth(models)
            if lastHP and hp<lastHP-.2 then
                damageAt=now
                PHX.FarmCombatDebug.LastDamageAt=now
            end
            lastHP=hp
            -- NET dispatch sends RegisterAttack/RegisterHit; do not send
            -- a second attack that would duplicate remote requests.
            if (not hitOk or now-damageAt>=CONFIG.FARM_COMBAT.DamageTimeout)
                and now-lastFallback>=2 then
                logLine("SCRAP_NET_STALL", "NO_VERIFIED_DAMAGE_OR_INPUT_FAILED | targets="..tostring(#attackTargets)
                    .." | hpAge="..string.format("%.1f",now-damageAt).." | net="..tostring(PHX.KillAura.LastMessage))
                lastFallback=now
            end
            if now-lastDiag>=2.5 then
                logLine("SCRAP_GOLEM_NET",string.format("LOOP | localNear=%d/%d moved=%d owned=%d netTargets=%d playerY=%.1f mobY=%.1f hp=%.0f sinceDamage=%.1f sent=%d attackOK=%s",near,#models,brought,owned,#attackTargets,r.Position.Y,mobAnchor.Position.Y,hp,now-damageAt,sent,tostring(hitOk)))
                lastDiag=now
            end
            if now-damageAt>=CONFIG.FARM_COMBAT.RecoveryTimeout and now-lastStall>=3 then
                logLine("SCRAP_GOLEM_NET","NO_DAMAGE | NET request does not imply server accepted damage")
                lastStall=now
            end
            task.wait(CONFIG.GOLEM_AURA.ATTACK_INTERVAL)
        end
        return false
    end)
    if PHX.stopFarmHover then PHX.stopFarmHover() end
    PHX.restoreForestGolemBring()
    if not ok then logLine("SCRAP_GOLEM_NET_ERROR",tostring(finished));return false end
    return finished==true
end

-- Hydra/Venom use their own small hitbox and a stationary aerial combat wave.
-- The old fallback chased the closest enemy and broke hover/bring coherence.
PHX.QuestFarmOriginalParts=setmetatable({}, {__mode="k"})
PHX.QuestFarmOriginalHumanoids=setmetatable({}, {__mode="k"})
PHX.QuestFarmLastBring=setmetatable({}, {__mode="k"})

function PHX.restoreQuestFarmBring()
    for part,prior in pairs(PHX.QuestFarmOriginalParts) do
        if part and part.Parent then
            pcall(function()
                part.Size=prior.Size
                part.CanCollide=prior.CanCollide
            end)
        end
        PHX.QuestFarmOriginalParts[part]=nil
    end
    for humanoid,prior in pairs(PHX.QuestFarmOriginalHumanoids) do
        if humanoid and humanoid.Parent then
            pcall(function()
                humanoid.WalkSpeed=prior.WalkSpeed
                humanoid.JumpPower=prior.JumpPower
                humanoid.AutoRotate=prior.AutoRotate
            end)
        end
        PHX.QuestFarmOriginalHumanoids[humanoid]=nil
    end
    PHX.QuestFarmLastBring=setmetatable({}, {__mode="k"})
end

-- V2.17.06: Only move network-owned NPCs; keep the original root size.
-- A successful PivotTo on the client is NOT proof that the server moved the mob.
-- V2.17.08: Reverted Hydra/Venom Bring from the original V2.16.38 lineage.
function PHX.bringQuestMobCluster(models,anchor)
    local rr=root()
    if not rr or not anchor then return 0,0,0,0,{} end
    local eligible={}
    local now=os.clock()
    local radius=CONFIG.FARM_COMBAT.QuestMobPickupRadius
    for _,mob in ipairs(models or {}) do
        local h,mr=PHX.farmMobRoot(mob)
        if h and mr and (mr.Position-anchor.Position).Magnitude<=radius then
            eligible[#eligible+1]={mob=mob,hum=h,part=mr}
        end
    end
    local moved,near,unowned,unknown=0,0,0,0
    local targets={}
    for i,entry in ipairs(eligible) do
        local mob,h,mr=entry.mob,entry.hum,entry.part
        local angle=(i-1)*math.pi*2/math.max(#eligible,1)
        local offset= #eligible>1 and Vector3.new(math.cos(angle),0,math.sin(angle))*CONFIG.FARM_COMBAT.QuestClusterRadius or Vector3.zero
        local slot=CFrame.new(anchor.Position+offset)
        local owned=networkOwned(mr)
        if owned==false then unowned+=1 elseif owned==nil then unknown+=1 end
        if CONFIG.FARM_COMBAT.QuestBringEnabled~=false and owned~=false then
            if not PHX.QuestFarmOriginalParts[mr] then
                PHX.QuestFarmOriginalParts[mr]={Size=mr.Size,CanCollide=mr.CanCollide}
            end
            if not PHX.QuestFarmOriginalHumanoids[h] then
                PHX.QuestFarmOriginalHumanoids[h]={WalkSpeed=h.WalkSpeed,JumpPower=h.JumpPower,AutoRotate=h.AutoRotate}
            end
            pcall(function()
                local size=CONFIG.FARM_COMBAT.QuestHitboxSize
                mr.Size=Vector3.new(size,size,size)
                mr.CanCollide=false
                h.WalkSpeed=0
                h.JumpPower=0
                h.AutoRotate=false
            end)
            local drift=(mr.Position-slot.Position).Magnitude
            if drift>=CONFIG.FARM_COMBAT.QuestRebringDrift
                and now-(PHX.QuestFarmLastBring[mob] or -math.huge)>=CONFIG.FARM_COMBAT.QuestBringInterval then
                PHX.QuestFarmLastBring[mob]=now
                local ok=pcall(function()
                    mob:PivotTo(slot)
                    mr.AssemblyLinearVelocity=Vector3.zero
                    mr.AssemblyAngularVelocity=Vector3.zero
                end)
                if ok then moved+=1 end
            end
        end
        local distance=(mr.Position-rr.Position).Magnitude
        if (mr.Position-slot.Position).Magnitude<=8 then near+=1 end
        if distance<=CONFIG.FARM_COMBAT.QuestAttackRange then
            targets[#targets+1]=mob
        end
    end
    return moved,near,unowned,unknown,targets
end

function PHX.farmStableQuestWave(name,camp,token,completed)
    if not camp or not isRunning(token) then return false end
    local epoch=CHARACTER_EPOCH
    if not highTween(camp*CFrame.new(0,26,0),340,token) then return false end
    local models={}
    local waitUntil=os.clock()+5
    repeat
        if not isRunning(token) or CHARACTER_EPOCH~=epoch then return false end
        if completed and completed() then return true end
        models=PHX.farmMobsNamed(name,camp.Position,CONFIG.FOREST_SCAN_RADIUS)
        if #models>0 then break end
        task.wait(.2)
    until os.clock()>=waitUntil
    if #models==0 then logLine("QUEST_NET","NO_MOBS | "..name); return false end
    -- Pick a new fixed point per wave. Never chase individual enemies mid-wave.
    local centerPart,smallest=nil,math.huge
    for _,mob in ipairs(models) do
        local _,mr=PHX.farmMobRoot(mob)
        if mr then
            local d=(mr.Position-camp.Position).Magnitude
            if d<smallest then centerPart,smallest=mr,d end
        end
    end
    if not centerPart then return false end
    local anchor=CFrame.new(centerPart.Position)
    local hover=anchor*CFrame.new(0,CONFIG.FARM_COMBAT.QuestHoverGap,0)
    if not safeTween(hover,340,token) then return false end
    if not PHX.maintainFarmHover or not PHX.maintainFarmHover(hover) then
        logLine("QUEST_NET","HOVER_START_FAILED | "..name)
        return false
    end
    local ok,result=pcall(function()
        local tool=equipTooltip("Melee")
        if not tool then logLine("QUEST_NET","NO_MELEE | "..name); return false end
        local deadline=os.clock()+CONFIG.FARM_COMBAT.MaxWaveSeconds
        local previousHP=setmetatable({}, {__mode="k"})
        local damageAt=os.clock()
        local lastDiag,lastFallback,lastBoost=0,0,0
        local sends=0
        logLine("QUEST_NET",string.format("START %s | fixedY=%.1f mobY=%.1f | legacyBring=%s",name,hover.Position.Y,anchor.Position.Y,tostring(CONFIG.FARM_COMBAT.QuestBringEnabled)))
        while isRunning(token) and CHARACTER_EPOCH==epoch and os.clock()<deadline do
            if completed and completed() then return true end
            local h,rr=hum(),root()
            if not h or h.Health<=0 or not rr or h.SeatPart then return false end
            if not PHX.maintainFarmHover(hover) then
                if not safeTween(hover,340,token) or not PHX.maintainFarmHover(hover) then
                    logLine("QUEST_NET","HOVER_RECOVER_FAILED | "..name)
                    return false
                end
            end
            models=PHX.farmMobsNamed(name,camp.Position,CONFIG.FOREST_SCAN_RADIUS)
            if #models==0 then return true end
            local localModels={}
            for _,mob in ipairs(models) do
                local _,mr=PHX.farmMobRoot(mob)
                if mr and (mr.Position-anchor.Position).Magnitude<=CONFIG.FARM_COMBAT.QuestMobPickupRadius then
                    localModels[#localModels+1]=mob
                end
            end
            if #localModels==0 then
                logLine("QUEST_BRING_REACQUIRE",name.." | remaining mobs outside local cluster")
                return false
            end
            local now=os.clock()
            if now-lastBoost>=3 then farmV19BoostSim();lastBoost=now end
            local moved,near,unowned,unknown,targets=PHX.bringQuestMobCluster(localModels,anchor)
            tool=equipTooltip("Melee") or tool
            local attackOK=false
            if tool and tool.Parent==char() and #targets>0 then
                attackOK=PHX.killAuraDispatch(targets,"NET")
                if attackOK then sends+=1 end
            end
            for _,mob in ipairs(localModels) do
                local mh=mob:FindFirstChildOfClass("Humanoid")
                if mh then
                    local oldHP=previousHP[mob]
                    if oldHP and mh.Health<oldHP-.2 then damageAt=now end
                    previousHP[mob]=mh.Health
                end
            end
            -- NET dispatcher sends the attack pair; never send native M1.
            if (not attackOK or now-damageAt>=CONFIG.FARM_COMBAT.DamageTimeout)
                and now-lastFallback>=2 then
                logLine("QUEST_NET_STALL",name.." | no verified HP loss"
                    .." | targets="..tostring(#targets)
                    .." | net="..tostring(PHX.KillAura.LastMessage)
                    .." | hpAge="..string.format("%.1f",now-damageAt))
                lastFallback=now
            end
            if now-lastDiag>=2.5 then
                logLine("QUEST_NET",string.format("%s | near=%d/%d moved=%d unowned=%d unknown=%d targets=%d hoverY=%.1f hpAge=%.1f sends=%d",name,near,#localModels,moved,unowned,unknown,#targets,rr.Position.Y,now-damageAt,sends))
                lastDiag=now
            end
            task.wait(CONFIG.MELEE_ATTACK_INTERVAL)
        end
        return false
    end)
    if PHX.stopFarmHover then PHX.stopFarmHover() end
    PHX.restoreQuestFarmBring()
    if not ok then logLine("QUEST_NET_ERROR",tostring(result));return false end
    return result==true
end

function PHX.farmMobWave(name,camp,token,completed)
    if name=="Forest Pirate" then
        return PHX.farmFixedScrapWave(camp,token,completed)
    end
    return PHX.farmStableQuestWave(name,camp,token,completed)
end

local function farmNamedMob(name, fallbackCFrame, token)
    return PHX.farmMobWave(name,fallbackCFrame,token,function()
        return PHX.QuestCompletedAt >= (PHX.LastQuestAcceptedAt or math.huge)
    end)
end

-- REMOVE LAVA V1 integrated: auto-discover Core.InteriorLava from startup.
-- Client-only appearance/touch/collision. Not confirmed against server damage.
PHX.RemoveLava = {
    Enabled=CONFIG.REMOVE_LAVA.Enabled, Root=nil, Snapshots=setmetatable({}, {__mode="k"}),
    Parts=0, Visuals=0, LastError=nil, LastStatus=nil, LastScanAt=nil,
}
local function lavaRootNow()
    -- Primary path from the confirmed standalone donor. Keep the scan scoped
    -- to PrehistoricIsland so unrelated lava/effects are never changed.
    local map=workspace:FindFirstChild("Map")
    local island=map and map:FindFirstChild("PrehistoricIsland")
    if not island then return nil end
    local core=island:FindFirstChild("Core")
    local exact=core and core:FindFirstChild("InteriorLava")
    if exact then return exact end
    -- Robust against an added intermediate Model/Folder in future map streams.
    return island:FindFirstChild("InteriorLava",true)
end
local function lavaBelongs(object,parent)
    return parent and object and (object==parent or object:IsDescendantOf(parent)) or false
end
local function lavaRestoreOne(object,entry)
    if object and object.Parent then
        for property,value in pairs(entry.Properties) do
            pcall(function() object[property]=value end)
        end
    end
    PHX.RemoveLava.Snapshots[object]=nil
end
local function lavaRestoreAll()
    for object,entry in pairs(PHX.RemoveLava.Snapshots) do
        lavaRestoreOne(object,entry)
    end
end
local function lavaSet(object,entry,property,value)
    local ok,original=pcall(function() return object[property] end)
    if not ok or original==nil then return false end
    if entry.Properties[property]==nil then entry.Properties[property]=original end
    if original==value then return true end
    local success=pcall(function() object[property]=value end)
    if not success then PHX.RemoveLava.LastError="Cannot set "..property end
    return success
end
local function lavaApply(object,parent)
    if not PHX.RemoveLava.Enabled or not lavaBelongs(object,parent) then return end
    local part=object:IsA("BasePart")
    local surface=object:IsA("Decal") or object:IsA("Texture")
    local effect=object:IsA("ParticleEmitter") or object:IsA("Beam") or object:IsA("Trail")
        or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles")
        or object:IsA("PointLight") or object:IsA("SpotLight") or object:IsA("SurfaceLight")
    if not part and not surface and not effect then return end
    local entry=PHX.RemoveLava.Snapshots[object]
    if not entry then
        entry={Properties={},IsPart=part}
        PHX.RemoveLava.Snapshots[object]=entry
    end
    if part then
        if not lavaSet(object,entry,"LocalTransparencyModifier",1) then
            lavaSet(object,entry,"Transparency",1)
        end
        lavaSet(object,entry,"CanTouch",false)
        lavaSet(object,entry,"CanCollide",false)
    elseif surface then lavaSet(object,entry,"Transparency",1)
    else lavaSet(object,entry,"Enabled",false) end
    if next(entry.Properties)==nil then PHX.RemoveLava.Snapshots[object]=nil end
end
function PHX.removeLavaRescan()
    local system=PHX.RemoveLava
    local current=lavaRootNow()
    system.Root=current
    for object,entry in pairs(system.Snapshots) do
        if not system.Enabled or not lavaBelongs(object,current) then lavaRestoreOne(object,entry) end
    end
    if system.Enabled and current then
        lavaApply(current,current)
        for _,object in ipairs(current:GetDescendants()) do lavaApply(object,current) end
    end
    local parts,visuals=0,0
    for _,entry in pairs(system.Snapshots) do
        if entry.IsPart then parts+=1 else visuals+=1 end
    end
    system.Parts,system.Visuals=parts,visuals
    system.LastScanAt=os.clock()
    local status=not system.Enabled and "OFF_RESTORED"
        or not current and "WAITING_INTERIOR_LAVA"
        or ("ROOT_FOUND parts="..parts.." visuals="..visuals)
    if status~=system.LastStatus then
        system.LastStatus=status
        if CONFIG.REMOVE_LAVA.Debug then
            print("[PX LAVA V2.17.02] "..status)
            if logLine then logLine("REMOVE_LAVA",status) end
        end
    end
    return current~=nil
end
function PHX.removeLavaStatus()
    local sys=PHX.RemoveLava
    return {Enabled=sys.Enabled,RootFound=sys.Root~=nil,Parts=sys.Parts,
        Visuals=sys.Visuals,LastError=sys.LastError,LastScanAt=sys.LastScanAt,
        Status=sys.LastStatus or "BOOT"}
end
function PHX.removeLavaSetEnabled(enabled)
    PHX.RemoveLava.Enabled=enabled==true
    CONFIG.REMOVE_LAVA.Enabled=PHX.RemoveLava.Enabled
    if not PHX.RemoveLava.Enabled then lavaRestoreAll() end
    local ok,why=pcall(PHX.removeLavaRescan)
    if not ok then PHX.RemoveLava.LastError=tostring(why) end
    return ok,ok and (PHX.RemoveLava.Enabled and "LAVA_ON_CLIENT_ONLY" or "LAVA_RESTORED") or tostring(why)
end
function PHX.removeLavaStop()
    PHX.RemoveLava.Enabled=false
    lavaRestoreAll()
end
local function enableLavaProtection(_island)
    -- Main event phase does not own the client lava scanner; it is always ready.
    PHX.removeLavaRescan()
end
local function disableLavaProtection()
    -- Auto lava survives event completion. Stop/Settings OFF restores values.
end
PHX.connect(workspace.DescendantAdded,function(object)
    local sys=PHX.RemoveLava
    if not sys.Enabled then return end
    if lavaBelongs(object,sys.Root) then
        local ok,err=pcall(lavaApply,object,sys.Root)
        if not ok then sys.LastError=tostring(err) end
    elseif object.Name=="PrehistoricIsland" or object.Name=="Core"
        or object.Name=="InteriorLava" then
        -- Scan immediately on significant map stream events; the polling
        -- loop below still catches fully populated/renamed descendants.
        local ok,err=pcall(PHX.removeLavaRescan)
        if not ok then sys.LastError=tostring(err) end
    end
end)
PHX.spawn(function()
    while PHX.generationAlive() do
        if PHX.RemoveLava.Enabled then
            local ok,err=pcall(PHX.removeLavaRescan)
            if not ok then PHX.RemoveLava.LastError=tostring(err) end
        end
        task.wait(math.max(.2,tonumber(CONFIG.REMOVE_LAVA.Interval) or .5))
    end
end)

local function nearestDistance(pos)
    local r = root()
    if not r then return math.huge end
    return (r.Position - pos).Magnitude
end

local function getRegion()
    local r = root()
    if not r then return "UNKNOWN", math.huge end
    local p = r.Position

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
            local approached=highTween(cf,200,token)
            local _,moved=confirm()
            if moved then return end
            if not approached or not PHX.travelAlive(token) then return end
            safeTween(cf,200,token) -- donor final exact gate settle
            local _,crossed=confirm()
            if crossed then return end
            local deadline=os.clock()+5
            while PHX.travelAlive(token) and os.clock()<deadline do
                local _,crossed=confirm()
                if crossed then return end
                task.wait(.10)
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
    logLine("RESET_PATH", "POST_EVENT_REWARDS_DEPARTURE")
    if not resetCharacter(token) then return false end
    if token and not isRunning(token) then return false end

    if getRegion() ~= "TIKI" then
        goTiki(token)
    end

    if getRegion() == "TIKI" then
        if not PHX.isMovementLocked() then pcall(function() CommF:InvokeServer("SetSpawnPoint") end) end
        setStatus("Returned to Tiki Outpost")
        return true
    end

    setStatus("WARNING: reset completed but Tiki position not confirmed")
    return false
end

local function boatOwnerName(boat)
    if not boat then return nil end
    local owner=boat:FindFirstChild("Owner",true)
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

PHX.RejectedBoats=PHX.RejectedBoats or setmetatable({},{__mode="k"})

local function getMasterBoat()
    local boats=workspace:FindFirstChild("Boats")
    if not boats then return nil end
    local masterName=PHX.automationLeaderName and PHX.automationLeaderName() or ENV.TeamConfig.MasterName
    local master=PHX.playerByName(masterName)
    local masterRoot=master and master.Character and master.Character:FindFirstChild("HumanoidRootPart")
    local best,bestDistance=nil,math.huge
    for _,boat in ipairs(boats:GetChildren()) do
        if boat.Name==CONFIG.BOAT_NAME and PHX.boatAlive(boat) and not PHX.RejectedBoats[boat]
            and (not PHX.BoatRebuyPending or
                (PHX.BoatPurchasePending and PHX.BoatPurchasePending.Snapshot
                    and not PHX.BoatPurchasePending.Snapshot[boat])) then
            local driver=PHX.findDriverSeat(boat)
            local occupant=driver and driver.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            local owner=boatOwnerName(boat)
            local owned=PHX.sameName(owner,masterName)
            if not owned and owner==nil and PHX.sameName(masterName,LP.Name)
                and PHX.VerifiedSpawnBoats[boat] then owned=true end
            if player and PHX.sameName(player.Name,masterName) then owned=true end
            if not owned and owner==nil and not player
                and os.clock()-(PHX.RecentBoatPurchaseAt or -math.huge)<48 then
                local boatPos=boat:GetPivot().Position
                local nearDealer=(boatPos-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude<280
                local nearMe=masterRoot and (boatPos-masterRoot.Position).Magnitude<280
                owned=(nearDealer or nearMe) and not (PHX.BoatsBeforePurchase and PHX.BoatsBeforePurchase[boat]) or false
            end
            if owned then
                if player and PHX.sameName(player.Name,masterName) then return boat end
                local distance=masterRoot and (boat:GetPivot().Position-masterRoot.Position).Magnitude or 0
                if distance<bestDistance then best,bestDistance=boat,distance end
            end
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

function PHX.passengerSeatCandidates(boat)
    local seats=sortPassengerSeats(boat)
    local candidates={}
    local h=hum()
    for _,seat in ipairs(seats) do
        if h and seat.Occupant==h then return {seat} end
        if not seat.Occupant then candidates[#candidates+1]=seat end
    end
    return candidates
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

local function nearestNativeBoatDealer()
    local folder=workspace:FindFirstChild("NPCs")
    if not folder then return nil,nil,"NPC_FOLDER_MISSING" end
    local wanted={
        ["marines boat dealer"]=1,
        ["advanced marines boat dealer"]=2,
        ["boat dealer"]=3,
    }
    local best,part,bestScore=nil,nil,math.huge
    for _,npc in ipairs(folder:GetChildren()) do
        local rank=wanted[tostring(npc.Name):lower()]
        if npc:IsA("Model") and rank then
            local p=npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
                or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart",true)
            if p and p:IsA("BasePart") then
                local d=(p.Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude
                if d<85 then
                    local score=d+rank*2
                    if score<bestScore then best,bestScore,part=npc,score,p end
                end
            end
        end
    end
    return best,part,best and "NPC_FOUND" or "NO_TIKI_MARINE_BOAT_DEALER"
end

-- V2.17.15: Return to the Tiki REGION only for purchasing a boat.
-- Buying through CommF_ does not require walking/tweening to the Boat Dealer.
-- Keep this separate from returnToDealer: that NPC approach is only a verified
-- rejection fallback, not the normal route after crafting a Magnet/respawning.
function PHX.returnToTikiForBoat(token,reason)
    if not PHX.travelAlive(token) then return false end
    reason=tostring(reason or "BOAT_PURCHASE")
    local region=getRegion()
    if region=="TIKI" then
        logLine("BOAT_TIKI_READY",reason.." already=TIKI noDealerTween=true")
        return true
    end
    logLine("BOAT_TIKI_ROUTE",reason.." from="..tostring(region).." to=TIKI noDealerTween=true")
    if region=="UNKNOWN" then
        -- Existing offshore safety path: reset only after Dragon/item guard.
        setStatus("BOAT: offshore -> secure inventory and return to Tiki spawn")
        if PHX.secureDragonWindow and not PHX.secureDragonWindow(1.0,token) then return false end
        if not resetCharacter(token) then
            logLine("BOAT_TIKI_FAILED",reason.." offshore reset blocked")
            return false
        end
    end
    if not PHX.travelAlive(token) then return false end
    if getRegion()~="TIKI" then
        setStatus("BOAT: using portals to Tiki; no Boat Dealer tween")
        if not goTiki(token) then
            logLine("BOAT_TIKI_FAILED",reason.." portal route failed region="..tostring(getRegion()))
            return false
        end
    end
    if not PHX.travelAlive(token) or getRegion()~="TIKI" then
        logLine("BOAT_TIKI_FAILED",reason.." Tiki region not verified after travel")
        return false
    end
    logLine("BOAT_TIKI_READY",reason.." region=TIKI noDealerTween=true")
    return true
end

function PHX.returnToDealer(token)
    if getRegion()=="UNKNOWN" then
        setStatus("RECOVERY offshore -> respawn at saved Tiki spawn")
        logLine("RESET_PATH", "UNKNOWN_REGION_RETURN_TO_DEALER")
        if PHX.secureDragonWindow and not PHX.secureDragonWindow(1.0,token) then return false end
        if not resetCharacter(token) then return false end
    end
    if not goTiki(token) then return false end
    local npc,npcPart,why=nearestNativeBoatDealer()
    local target=CONFIG.BOAT_DEALER_CFRAME
    if npcPart then
        local playerRoot=root()
        local away=playerRoot and (playerRoot.Position-npcPart.Position) or Vector3.new(0,0,1)
        away=Vector3.new(away.X,0,away.Z)
        if away.Magnitude<.2 then
            local look=npcPart.CFrame.LookVector
            away=Vector3.new(-look.X,0,-look.Z)
        end
        away=away.Magnitude>.2 and away.Unit or Vector3.new(0,0,1)
        local stand=npcPart.Position+away*4.0+Vector3.new(0,0.7,0)
        target=CFrame.lookAt(stand,Vector3.new(npcPart.Position.X,stand.Y,npcPart.Position.Z))
    end
    local rr=root()
    local distance=rr and (rr.Position-target.Position).Magnitude or math.huge
    logLine("BOAT_NATIVE","MOVE_START npc="..tostring(npc and npc.Name or "fallback")..
        " npc_reason="..tostring(why).." distance="..string.format("%.1f",distance))
    if distance>7.0 then
        if not safeTween(target,180,token) then
            logLine("BOAT_NATIVE","MOVE_FAILED")
            return false
        end
    end
    rr=root()
    local remain=rr and (rr.Position-target.Position).Magnitude or math.huge
    logLine("BOAT_NATIVE","TWEEN_STOPPED remain="..string.format("%.1f",remain)..
        " npc="..tostring(npc and npc.Name or "fallback"))
    if not PHX.travelAlive(token) then return false end
    if remain>14 then return false end
    logLine("BOAT_NATIVE","SETSPAWN_DEFERRED_UNTIL_BOAT_VERIFIED")
    noteProgress("TIKI_DEALER:"..CHARACTER_EPOCH)
    return true
end

local function boatBeli()
    for _,parentName in ipairs({"Data","leaderstats"}) do
        local parent=LP:FindFirstChild(parentName)
        if parent then
            for _,key in ipairs({"Beli","Money"}) do
                local stat=parent:FindFirstChild(key)
                if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then
                    return tonumber(stat.Value)
                end
            end
        end
    end
    return nil
end

-- V2.16.38: exclusive player-movement transaction for the *full* SOLO/TEAM main.
-- Never call tween:Play() then tween:Cancel() immediately: arrival must precede lock.
local function acquireBoatMovementLock(token)
    if not PHX.travelAlive(token) or PHX.isMovementLocked() then return nil,"LOCK_BUSY_OR_STOPPED" end
    local character=LP.Character
    local h=hum()
    local rr=root()
    if not character or not h or h.Health<=0 or not rr or h.SeatPart then return nil,"CHARACTER_NOT_READY" end
    local lease={Character=character,Humanoid=h,Root=rr,Owner=coroutine.running(),StartedAt=os.clock(),
        WalkSpeed=h.WalkSpeed,JumpPower=h.JumpPower,JumpHeight=h.JumpHeight,AutoRotate=h.AutoRotate,
        ActionName="PX_BoatBuy_Lock_"..tostring(SCRIPT_GENERATION)}
    -- Atomic gate FIRST: all other movement creators will now refuse new work.
    PHX.Runtime.MovementLockLease=lease
    logLine("MOVEMENT_LOCKED","owner=BUY_BOAT generation="..tostring(SCRIPT_GENERATION))

    -- Stop every known source of motion. Cleanup procedures can run without yielding.
    local rt=PHX.Runtime
    if rt.FruitApproachCleanup then pcall(rt.FruitApproachCleanup) end
    if PHX.stopFarmHover then pcall(PHX.stopFarmHover) end
    if PHX.stopBoat then pcall(PHX.stopBoat) end
    if PHX.restoreTravel then pcall(PHX.restoreTravel) end
    -- Snapshot normal humanoid state *after* retiring a prior hover controller.
    lease.AutoRotate=h.AutoRotate
    lease.WalkSpeed=h.WalkSpeed
    lease.JumpPower=h.JumpPower
    lease.JumpHeight=h.JumpHeight
    local tweens,connections,objects=0,0,0
    for tween in pairs(rt.Tweens or {}) do
        pcall(function() tween:Cancel() end); rt.Tweens[tween]=nil;tweens+=1
    end
    for connection in pairs(rt.MovementConnections or {}) do
        PHX.disconnect(connection);connections+=1
    end
    for obj in pairs(rt.MovementObjects or {}) do
        if obj and obj.Parent then pcall(function() obj:Destroy() end) end
        rt.MovementObjects[obj]=nil;objects+=1
    end
    for key in pairs(rt.HeldKeys or {}) do
        pcall(function() VirtualInputManager:SendKeyEvent(false,key,false,game) end)
        rt.HeldKeys[key]=nil
    end
    -- Sink ordinary character controls for this short-lived purchase window.
    local sink=function() return Enum.ContextActionResult.Sink end
    local bound=pcall(function()
        ContextActionService:BindActionAtPriority(lease.ActionName,sink,false,10000,
            Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,
            Enum.KeyCode.Up,Enum.KeyCode.Down,Enum.KeyCode.Left,Enum.KeyCode.Right,
            Enum.KeyCode.Space,Enum.KeyCode.Thumbstick1,Enum.KeyCode.ButtonA)
    end)
    if not bound then lease.ActionName=nil end
    pcall(function() h.AutoRotate=false;h.WalkSpeed=0;h.JumpPower=0;h.JumpHeight=0 end)
    -- A short Heartbeat guard prevents residual velocity and humanoid input.
    lease.Heartbeat=RunService.Heartbeat:Connect(function()
        if PHX.Runtime.MovementLockLease~=lease then return end
        if not PHX.generationAlive() or LP.Character~=character or h.Health<=0
            or os.clock()-lease.StartedAt>25 then
            lease.TimedOut=true
            -- If a remote may already have been issued, do not ever duplicate the charge.
            local pending=PHX.BoatPurchasePending
            if pending and pending.Lease==lease and pending.CallIssued then
                pending.Stage="PAYMENT_UNCERTAIN"
                PHX.BoatState="PAYMENT_UNCERTAIN"
            end
            PHX.BoatPurchaseInFlight=false
            PHX.releaseBoatMovementLock(lease,"SAFETY_TIMEOUT_OR_CHARACTER_CHANGE")
            return
        end
        pcall(function()
            h:Move(Vector3.zero,false)
            rr.AssemblyLinearVelocity=Vector3.zero
            rr.AssemblyAngularVelocity=Vector3.zero
        end)
    end)
    rt.Connections[lease.Heartbeat]=true
    logLine("TWEEN_CANCELLED","lease=true runtimeTweens="..tweens..
        " movementConnections="..connections.." movementObjects="..objects)
    return lease
end

local function settleBoatMovement(lease,npcPart,token)
    local stableSince=nil
    local prior=nil
    local deadline=os.clock()+4.5
    while os.clock()<deadline do
        if PHX.Runtime.MovementLockLease~=lease or lease.TimedOut
            or not PHX.travelAlive(token) or LP.Character~=lease.Character then
            return false,"LOCK_LOST"
        end
        local rr=root()
        if not rr or not npcPart or not npcPart.Parent then return false,"NPC_OR_CHARACTER_MISSING" end
        local distance=(rr.Position-npcPart.Position).Magnitude
        if distance>8 then return false,"NPC_OUT_OF_RANGE:"..string.format("%.1f",distance) end
        local pos=rr.Position
        local stable=prior~=nil and (pos-prior).Magnitude<=0.35
        if stable then stableSince=stableSince or os.clock()
        else stableSince=nil end
        prior=pos
        if stableSince and os.clock()-stableSince>=0.45 then
            logLine("BOAT_DIRECT","SETTLED seconds=0.45 dist="..string.format("%.2f",distance))
            return true
        end
        task.wait(.08)
    end
    return false,"MOVEMENT_NOT_SETTLED"
end

local function snapshotBoatsForPurchase()
    local folder=workspace:FindFirstChild("Boats")
    if not folder then return nil,nil end
    local snapshot=setmetatable({},{__mode="k"})
    for _,boat in ipairs(folder:GetChildren()) do snapshot[boat]=true end
    return folder,snapshot
end

local function findVerifiedPurchasedBoat(pending)
    local folder=workspace:FindFirstChild("Boats")
    if not folder or not pending or not pending.Snapshot then return nil,nil end
    local seen=nil
    local ownerless,ownerlessCount=nil,0
    for _,boat in ipairs(folder:GetChildren()) do
        if boat.Name==CONFIG.BOAT_BUY_NAME and not pending.Snapshot[boat] and PHX.boatAlive(boat) then
            local owner=boatOwnerName(boat)
            if owner and PHX.sameName(owner,LP.Name) then return boat,owner end
            if owner==nil then ownerless,ownerlessCount=boat,ownerlessCount+1 end
            seen=owner or "OWNER_PENDING"
        end
    end
    -- Same proof used by the supplied one-shot BuyBoat test: a fresh boat plus
    -- precisely 2000 Beli charged. Accept only ONE ownerless candidate; if the
    -- Owner identifies another player, never associate their boat with us.
    if ownerlessCount==1 and pending.BeliBefore~=nil then
        local after=boatBeli()
        if after~=nil and pending.BeliBefore-after==2000 then
            logLine("BOAT_DIRECT","OWNER_PENDING but Beli -2000 + unique fresh boat verified")
            pending.VerifiedByBeli=true
            return ownerless,"BELI_MINUS_2000"
        end
    end
    return nil,seen
end

local function finishVerifiedBoatBuy(pending,boat)
    if not boat or not PHX.boatAlive(boat) then return nil end
    if pending.VerifiedByBeli then PHX.VerifiedSpawnBoats[boat]=true end
    local after=boatBeli()
    logLine("SPAWN_VERIFIED","name="..tostring(boat.Name).." owner="..tostring(boatOwnerName(boat))..
        " mode="..(pending.FastDirect and "FAST" or "DEALER")..
        " elapsed="..string.format("%.2f",os.clock()-(pending.StartedAt or os.clock()))..
        " result="..tostring(pending.Result).." beliDelta="..
        tostring(after and pending.BeliBefore and (after-pending.BeliBefore) or "unknown"))
    PHX.BoatRebuyPending=false
    PHX.BoatPurchasePending=nil
    PHX.BoatsBeforePurchase=nil
    PHX.BoatPurchaseInFlight=false
    PHX.NextBoatBuyAt=0
    PHX.BoatState="READY"
    if pending.Rebuy then
        for previous in pairs(pending.Snapshot) do
            if previous.Parent and previous.Name==CONFIG.BOAT_NAME then PHX.RejectedBoats[previous]=true end
        end
    end
    PHX.releaseBoatMovementLock(pending.Lease,"SPAWN_VERIFIED")
    -- Spawn point is strictly after purchase verification and movement unlock.
    if PHX.travelAlive(pending.Token) and CommF and PHX.BoatSpawnpointCharacter~=LP.Character then
        PHX.BoatSpawnpointCharacter=LP.Character
        local ok,value=pcall(function() return CommF:InvokeServer("SetSpawnPoint") end)
        logLine("BOAT_DIRECT","POST_VERIFY_SETSPAWN ok="..tostring(ok).." result="..tostring(value))
    end
    return boat
end

local function buyGrandBrigade(token)
    if not isMaster() or not PHX.travelAlive(token) then return nil end
    local pending=PHX.BoatPurchasePending
    if pending and (pending.Character~=LP.Character or pending.Epoch~=PHX.BoatRespawnEpoch) then
        PHX.releaseBoatMovementLock(pending.Lease,"STALE_CHARACTER")
        PHX.BoatPurchasePending=nil;PHX.BoatsBeforePurchase=nil
        PHX.BoatPurchaseInFlight=false
        pending=nil
    end
    if pending then
        local boat,seen=findVerifiedPurchasedBoat(pending)
        if boat then return finishVerifiedBoatBuy(pending,boat) end
        if pending.Stage=="FAST_REJECT_OBSERVE" then
            -- A negative RPC response alone does not prove that the purchase is
            -- harmless to retry. Allow replication time before dealer fallback.
            if os.clock()>=(pending.ObserveUntil or math.huge) then
                local currentBeli=boatBeli()
                if pending.BeliBefore==nil or currentBeli==nil or currentBeli<pending.BeliBefore or seen then
                    pending.Stage="PAYMENT_UNCERTAIN"
                    PHX.BoatState="PAYMENT_UNCERTAIN"
                    logLine("BOAT_FAST_DIRECT","AMBIGUOUS_AFTER_REJECTION old="..tostring(pending.BeliBefore)..
                        " new="..tostring(currentBeli).." seen="..tostring(seen).." NO_DUPLICATE_BUY=true")
                else
                    -- Now it is safe to use the established dealer route.
                    PHX.BoatFastForceDealer=true
                    PHX.BoatPurchasePending=nil;PHX.BoatsBeforePurchase=nil
                    PHX.NextBoatBuyAt=os.clock()+0.2
                    PHX.BoatState="FAST_FALLBACK_DEALER"
                    logLine("BOAT_FAST_DIRECT","REJECT_CONFIRMED_NO_CHARGE -> DEALER_FALLBACK")
                end
            end
        elseif pending.Stage=="FAILED" then
            if os.clock()>=(pending.RetryAt or math.huge) then
                PHX.BoatPurchasePending=nil;PHX.BoatsBeforePurchase=nil
                PHX.NextBoatBuyAt=os.clock()+3
            end
        elseif pending.Stage=="VERIFY" then
            if os.clock()-(pending.RequestAt or pending.StartedAt)>=10 then
                pending.Stage="PAYMENT_UNCERTAIN"
                PHX.BoatState="PAYMENT_UNCERTAIN"
                logLine("BUY_TIMEOUT","result="..tostring(pending.Result)..
                    " seen="..tostring(seen).." NO_DUPLICATE_BUY=true")
            end
        end
        -- All uncertain cases remain pending; never charge again automatically.
        return nil
    end
    if PHX.BoatPurchaseInFlight or PHX.isMovementLocked() then return nil end
    if not PHX.BoatRebuyPending then
        local boat=getMasterBoat()
        if boat then return boat end
    end
    if os.clock()<(PHX.NextBoatBuyAt or 0) then return nil end
    if not PHX.returnToTikiForBoat(token,PHX.BoatRebuyPending and "RESPAWN_REBUY" or "PRE_BUY") then
        PHX.BoatState="TIKI_RETURN_REQUIRED"
        setStatus("Boat purchase waiting for confirmed Tiki arrival")
        return nil
    end
    if not PHX.travelAlive(token) or PHX.BoatPurchasePending or PHX.isMovementLocked() then return nil end
    local rr=root()
    if not rr then return nil end
    local fastDirect=CONFIG.BOAT_FAST_BUY.Enabled and not PHX.BoatFastForceDealer
    local npc,part=nil,nil
    if not fastDirect then npc,part=nearestNativeBoatDealer() end
    local distance=part and (rr.Position-part.Position).Magnitude or math.huge
    if fastDirect then
        -- Borrow the user's fast test: BuyBoat can be attempted without opening
        -- a menu, or pre-travelling to the NPC. Server acceptance is verified below.
        PHX.BoatState="FAST_DIRECT_PREP"
        logLine("BOAT_FAST_DIRECT","SKIP_DEALER distance="..string.format("%.1f",distance)..
            " region="..tostring(getRegion()).." mode=ONE_RPC")
    elseif not part or distance>8 then
        PHX.TeamPhase="RECOVERY";PHX.BoatState="TWEEN_TO_BOAT_DEALER"
        if not PHX.returnToDealer(token) then
            logLine("BUY_FAILED","ARRIVAL_FAILED")
            return nil
        end
    end
    if not PHX.travelAlive(token) then return nil end
    PHX.BoatPurchaseInFlight=true
    local character=LP.Character
    local lease,lockWhy=acquireBoatMovementLock(token)
    if not lease then
        PHX.BoatPurchaseInFlight=false
        logLine("BUY_FAILED","MOVEMENT_LOCK:"..tostring(lockWhy))
        return nil
    end
    local function abort(why)
        PHX.releaseBoatMovementLock(lease,why)
        PHX.BoatPurchaseInFlight=false
        PHX.BoatState=why
        logLine("BUY_FAILED",tostring(why))
        return nil
    end
    if not fastDirect then npc,part=nearestNativeBoatDealer() end
    if not fastDirect then
        local settled,why=settleBoatMovement(lease,part,token)
        if not settled then return abort("SETTLE:"..tostring(why)) end
    else
        -- Preserve the exclusive movement lock, but skip the .45s dealer settle.
        logLine("BOAT_FAST_DIRECT","LOCK_READY; SKIP_NPC_SETTLE")
    end
    if not PHX.travelAlive(token) or LP.Character~=character or PHX.Runtime.MovementLockLease~=lease then
        return abort("PURCHASE_INTERRUPTED")
    end
    local boats,snapshot=snapshotBoatsForPurchase()
    if not boats then return abort("BOATS_FOLDER_MISSING") end
    local initialCount=0;for _ in pairs(snapshot) do initialCount+=1 end
    pending={Stage="REQUEST",Snapshot=snapshot,Character=character,Epoch=PHX.BoatRespawnEpoch,
        FastDirect=fastDirect,Rebuy=PHX.BoatRebuyPending,StartedAt=os.clock(),
        BeliBefore=boatBeli(),Token=token,Lease=lease}
    PHX.BoatPurchasePending=pending
    PHX.BoatsBeforePurchase=snapshot
    PHX.RecentBoatPurchaseAt=pending.StartedAt
    PHX.BoatState="DIRECT_BUY_REQUEST"
    local currentRoot=root()
    local currentDist=(currentRoot and part) and (currentRoot.Position-part.Position).Magnitude or math.huge
    logLine("BOAT_DIRECT","START mode="..(fastDirect and "FAST" or "DEALER")..
        " dist="..string.format("%.2f",currentDist).." beli="..tostring(pending.BeliBefore)..
        " boats="..initialCount.." npc="..tostring(npc and npc.Name))
    pending.CallIssued=true  -- One transaction = one request; set before RemoteFunction yields.
    pending.RequestAt=os.clock()
    logLine("BUY_INVOKED","CommF_:InvokeServer(BuyBoat, MarineGrandBrigade) call=1 mode="..(fastDirect and "FAST" or "DEALER"))
    local ok,result=pcall(function() return CommF:InvokeServer("BuyBoat",CONFIG.BOAT_BUY_NAME) end)
    PHX.BoatPurchaseInFlight=false
    if PHX.BoatPurchasePending~=pending or LP.Character~=character then
        PHX.releaseBoatMovementLock(lease,"PURCHASE_SUPERSEDED")
        return nil
    end
    pending.Result=ok and result or nil
    logLine("BUY_RESULT="..tostring(ok and result or "ERROR"),
        "ok="..tostring(ok).." elapsed="..string.format("%.2f",os.clock()-pending.RequestAt))
    -- Payment can have succeeded even when result/replication is ambiguous.
    local after=boatBeli()
    local charged=after and pending.BeliBefore and after<pending.BeliBefore
    local appeared,seenNewBoat=findVerifiedPurchasedBoat(pending)
    if not ok or result~=1 then
        -- Only a concrete negative response is eligible for dealer fallback,
        -- and only after observing unchanged Beli and no fresh boat.
        local concreteReject=ok and (result==false or (type(result)=="number" and result~=1))
        if fastDirect and concreteReject and not charged and not appeared and not seenNewBoat then
            pending.Stage="FAST_REJECT_OBSERVE"
            pending.ObserveUntil=os.clock()+math.max(2,tonumber(CONFIG.BOAT_FAST_BUY.RejectionObserveSeconds) or 3.5)
            PHX.BoatState="FAST_REJECT_OBSERVE"
            logLine("BOAT_FAST_DIRECT","NEGATIVE_RESULT="..tostring(result)..
                " observeSeconds="..string.format("%.1f",pending.ObserveUntil-os.clock())..
                " NO_DUPLICATE_YET=true")
        elseif charged or appeared or seenNewBoat or not ok or result==nil then
            -- No automatic second RPC when payment/spawn replication is uncertain.
            pending.Stage="PAYMENT_UNCERTAIN";PHX.BoatState="PAYMENT_UNCERTAIN"
            logLine("BUY_FAILED","AMBIGUOUS_PAYMENT noDuplicate=true result="..tostring(result))
        else
            pending.Stage="FAILED"
            pending.RetryAt=os.clock()+((result==0 or result==3 or result==4) and 40 or 20)
            PHX.BoatState="DIRECT_BUY_REJECTED"
            logLine("BUY_FAILED","REJECTED result="..tostring(result)..
                " retryIn="..string.format("%.1f",pending.RetryAt-os.clock()))
        end
        PHX.releaseBoatMovementLock(lease,"REMOTE_FAILED_OR_UNCERTAIN")
        if appeared then return finishVerifiedBoatBuy(pending,appeared) end
        return nil
    end
    pending.Stage="VERIFY";PHX.BoatState="DIRECT_WAIT_SPAWN"
    local verifyUntil=os.clock()+8
    local lastSeen=nil
    while PHX.travelAlive(token) and LP.Character==character and os.clock()<verifyUntil do
        local boat,ownerOrPending=findVerifiedPurchasedBoat(pending)
        if boat then return finishVerifiedBoatBuy(pending,boat) end
        if ownerOrPending and lastSeen~=ownerOrPending then
            logLine("BOAT_DIRECT","SPAWN_SEEN owner="..tostring(ownerOrPending));lastSeen=ownerOrPending
        end
        if PHX.Runtime.MovementLockLease~=lease then break end
        task.wait(.10)
    end
    pending.Stage="PAYMENT_UNCERTAIN";PHX.BoatState="PAYMENT_UNCERTAIN"
    logLine("BUY_TIMEOUT","RESULT_1_BUT_OWNER_NOT_VERIFIED noDuplicate=true")
    PHX.releaseBoatMovementLock(lease,"VERIFY_TIMEOUT_NO_DUPLICATE")
    return nil
end

local function boardBoat(boat,token)
    if not PHX.boatAlive(boat) then return false end
    PHX.TeamPhase="BOARDING"
    if isMaster() then
        local driver=PHX.findDriverSeat(boat)
        return driver and sitOn(driver,token) or false
    end
    if PHX.localRole()~="SLAVE" then return false end
    for _,seat in ipairs(PHX.passengerSeatCandidates(boat)) do
        if not PHX.travelAlive(token) then return false end
        if sitOn(seat,token) then PHX.refreshCrew(boat); return true end
    end
    setStatus("SLAVE: chờ ghế hành khách còn trống")
    return false
end

local function countTeamAboard(boat)
    if not boat or not boat.Parent then return 0 end
    PHX.refreshCrew(boat)
    local aboard={}
    for _,seat in ipairs(boat:GetDescendants()) do
        if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
            local occupant=seat.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            if player and occupant.Health>0 and player.Character==occupant.Parent and isTeamName(player.Name) then aboard[player.Name]=true end
        end
    end
    local count=0
    for _ in pairs(aboard) do count=count+1 end
    return count
end

function PHX.crewReady(boat)
    if not PHX.boatAlive(boat) then return false,0 end
    PHX.refreshCrew(boat)
    local driver=PHX.findDriverSeat(boat)
    local pilot=driver and driver.Occupant
    local master=pilot and pilot.Parent and Players:GetPlayerFromCharacter(pilot.Parent)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        return master==LP and pilot.Health>0 and LP.Character==pilot.Parent and pilot.SeatPart==driver,0
    end
    if not master or not PHX.sameName(master.Name,ENV.TeamConfig.MasterName) or
        pilot.Health<=0 or master.Character~=pilot.Parent or pilot.SeatPart~=driver then return false,0 end
    local trusted, whitelistCount={},0
    for _,name in ipairs(CONFIG.TEAM_TRUSTED_SLAVES or {}) do
        if type(name)=="string" and name~="" then
            local key=string.lower(name)
            if not trusted[key] then trusted[key]=true; whitelistCount+=1 end
        end
    end
    local passengers={}
    for _,seat in ipairs(boat:GetDescendants()) do
        if seat:IsA("Seat") and not seat:IsA("VehicleSeat") then
            local occupant=seat.Occupant
            local player=occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent)
            if player and not PHX.sameName(player.Name,ENV.TeamConfig.MasterName) and
                occupant.Health>0 and player.Character==occupant.Parent and occupant.SeatPart==seat and
                (whitelistCount==0 or trusted[string.lower(player.Name)]) then
                passengers[player.Name]=true
            end
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
        Owner=PHX.automationLeaderName and PHX.automationLeaderName() or ENV.TeamConfig.MasterName,
        Mode=PHX.automationMode and PHX.automationMode() or "TEAM",State=PHX.BoatState or PHX.TeamPhase or "WAIT_MASTER",
        Heading=PHX.SeaHeading,IsDriver=driver and hum() and driver.Occupant==hum() or false}
end

-- V2.17.14: Continuous local collision guard for the ship AND seated character.
-- IMPORTANT: Cannot override server-authoritative world collision or server position correction.
-- No terrain destruction / CFrame forcing; guard turns off on seat exit or settings OFF.
function PHX.restoreBoatNoclip(reason)
    local guard=PHX.BoatNoclipGuard
    PHX.BoatNoclipGuard=nil -- invalidate callbacks before restoring state
    if guard then
        for _,connection in ipairs(guard.Connections or {}) do
            pcall(function() connection:Disconnect() end)
        end
    end
    local boatBackup=(guard and guard.Parts) or (PHX.TravelState and PHX.TravelState.BoatParts) or {}
    for part,old in pairs(boatBackup) do
        if part and part.Parent then pcall(function() part.CanCollide=old end) end
    end
    if guard then
        for part,old in pairs(guard.CharacterParts or {}) do
            if part and part.Parent then pcall(function() part.CanCollide=old end) end
        end
        logLine("BOAT_NOCLIP","RESTORED reason="..tostring(reason or "OFF")..
            " boatParts="..tostring(guard.BoatCount or 0).." playerParts="..tostring(guard.CharacterCount or 0))
    end
    if PHX.TravelState then PHX.TravelState.BoatParts=nil end
end

function PHX.boatNoclipActive(boat)
    if not CONFIG.BOAT_NOCLIP.Enabled or not boat or not boat.Parent then return false end
    if boat.Name~=CONFIG.BOAT_NAME then return false end
    local h=hum()
    if not h or h.Health<=0 or not h.SeatPart then return false end
    -- Do NOT check throttle/steer: releasing W for even a frame must not restore collision.
    -- Driver and seated passengers both need protection against their character collision.
    return PHX.boatForSeat(h.SeatPart)==boat
end

function PHX.enableBoatNoclip(boat)
    if not PHX.boatNoclipActive(boat) then return false end
    local currentCharacter=LP.Character
    local active=PHX.BoatNoclipGuard
    if active and active.Boat==boat and active.Character==currentCharacter then return true end
    if active then PHX.restoreBoatNoclip("BOAT_OR_CHARACTER_CHANGED") end

    local backup,characterBackup={},{}
    local guard={Boat=boat,Character=currentCharacter,Parts=backup,CharacterParts=characterBackup,
        Connections={},BoatCount=0,CharacterCount=0}
    PHX.BoatNoclipGuard=guard
    PHX.TravelState.BoatParts=backup

    local function ensurePart(part,stash,kind)
        if not part:IsA("BasePart") then return end
        local ok,collidable=pcall(function() return part.CanCollide end)
        if not ok then return end
        if stash[part]==nil then
            stash[part]=collidable
            if kind=="BOAT" then guard.BoatCount+=1 else guard.CharacterCount+=1 end
        end
        if collidable then pcall(function() part.CanCollide=false end) end
    end
    local function scan()
        for _,part in ipairs(boat:GetDescendants()) do ensurePart(part,backup,"BOAT") end
        if currentCharacter and currentCharacter.Parent then
            for _,part in ipairs(currentCharacter:GetDescendants()) do
                ensurePart(part,characterBackup,"PLAYER")
            end
        end
    end
    scan() -- apply immediately, before the player next presses W
    guard.Connections[#guard.Connections+1]=boat.DescendantAdded:Connect(function(part)
        if PHX.BoatNoclipGuard==guard then ensurePart(part,backup,"BOAT") end
    end)
    if currentCharacter then
        guard.Connections[#guard.Connections+1]=currentCharacter.DescendantAdded:Connect(function(part)
            if PHX.BoatNoclipGuard==guard then ensurePart(part,characterBackup,"PLAYER") end
        end)
    end
    local elapsed,scanElapsed=0,0
    -- Run before physics so CanCollide is corrected prior to nearby obstacle contact.
    guard.Connections[#guard.Connections+1]=RunService.Stepped:Connect(function(_,dt)
        if PHX.BoatNoclipGuard~=guard then return end
        if not PHX.generationAlive() or not PHX.boatNoclipActive(boat) or LP.Character~=currentCharacter then
            PHX.restoreBoatNoclip("LEFT_BOAT_OR_STOPPED")
            return
        end
        local delta=tonumber(dt) or 0
        elapsed+=delta; scanElapsed+=delta
        if elapsed<(tonumber(CONFIG.BOAT_NOCLIP.RefreshSeconds) or 0.10) then return end
        elapsed=0
        -- Some games re-enable collision during vehicle physics updates.
        for part in pairs(backup) do
            if part.Parent then pcall(function() if part.CanCollide then part.CanCollide=false end end) end
        end
        for part in pairs(characterBackup) do
            if part.Parent then pcall(function() if part.CanCollide then part.CanCollide=false end end) end
        end
        if scanElapsed>=0.40 then scanElapsed=0;scan() end
    end)
    logLine("BOAT_NOCLIP","CONTINUOUS boat="..tostring(boat.Name)..
        " boatParts="..guard.BoatCount.." playerParts="..guard.CharacterCount)
    return true
end

function PHX.setBoatNoclipEnabled(enabled)
    if type(enabled)~="boolean" then return false,"BOAT_NOCLIP_EXPECTS_BOOLEAN" end
    CONFIG.BOAT_NOCLIP.Enabled=enabled
    if not enabled then
        PHX.restoreBoatNoclip("SETTINGS_OFF")
    else
        local h=hum()
        local seat=h and h.SeatPart
        local boat=(seat and PHX.boatForSeat(seat)) or (PHX.TravelState and PHX.TravelState.Boat)
        if boat and PHX.boatNoclipActive(boat) then PHX.enableBoatNoclip(boat) end
    end
    return true,enabled and "Boat Noclip: luôn bật khi ngồi thuyền; tắt va chạm cả nhân vật." or "Boat Noclip tắt; đã khôi phục va chạm."
end

-- Works if executed before a ship spawns or while already seated as driver/passenger.
PHX.spawn(function()
    while PHX.generationAlive() do
        local h=hum()
        local seat=h and h.SeatPart
        local boat=seat and PHX.boatForSeat(seat) or nil
        if boat and PHX.boatNoclipActive(boat) then
            local ok,err=pcall(PHX.enableBoatNoclip,boat)
            if not ok then logLine("BOAT_NOCLIP_ERROR",tostring(err)) end
        elseif PHX.BoatNoclipGuard then
            PHX.restoreBoatNoclip("NOT_ON_BOAT")
        end
        task.wait(0.10)
    end
end)

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

PHX.BoatStallAttempts=PHX.BoatStallAttempts or setmetatable({}, {__mode="k"})
local function boatFlyTo(boat,targetPos,token)
    if PHX.isMovementLocked() then return false end
    if not isMaster() or not PHX.boatAlive(boat) then return false end
    local driver=PHX.findDriverSeat(boat)
    local h=hum()
    if not driver or not h or h.Health<=0 or h.SeatPart~=driver or driver.Occupant~=h then
        PHX.BoatState="NO_DRIVER";return false
    end
    PHX.TravelState.Boat=boat
    PHX.TravelState.BoatMoving=true
    PHX.enableBoatNoclip(boat)
    PHX.TravelState.BoatMoving=true
    local previousAt=os.clock()
    local speed=math.clamp(tonumber(CONFIG.BOAT_TWEEN_SPEED) or 280,50,280)
    local arrived=false
    local lastProgressPos=boat:GetPivot().Position
    local lastProgressAt=os.clock()
    local lastSamplePos=lastProgressPos
    local lastSampleAt=os.clock()
    local failure=nil
    while PHX.travelAlive(token) and not PHX.isMovementLocked() and PHX.boatAlive(boat) and PHX.TravelState.BoatMoving do
        if findPrehistoric() or PHX.prehistoricMarker() then break end
        if h~=hum() or h.Health<=0 or h.SeatPart~=driver or driver.Occupant~=h then failure="DRIVER_LOST";break end
        if not PHX.crewReady(boat) then failure="CREW_NOT_READY";break end
        local now=os.clock()
        local dt=math.clamp(now-previousAt,0,.10)
        previousAt=now
        local current=boat:GetPivot().Position
        local diff=Vector3.new(targetPos.X-current.X,0,targetPos.Z-current.Z)
        local heading=PHX.SeaHeading
        if not heading or heading.Magnitude<.01 then heading=diff.Magnitude>.01 and diff.Unit or Vector3.new(-1,0,0) end
        local remaining=diff:Dot(heading)
        if remaining<=4 then arrived=true;noteProgress("SAILED:"..math.floor(current.X)..":"..math.floor(current.Z));break end
        if now-lastSampleAt>=3 then
            local displacement=(current-lastSamplePos).Magnitude
            if displacement<18 then
                failure="BOAT_STALLED_3S"
                logLine("BOAT_STALL","distance="..string.format("%.1f",displacement)..
                    " speed="..speed.." seat="..tostring(h.SeatPart==driver)..
                    " boat="..tostring(boat.Name))
                break
            end
            lastSamplePos=current
            lastSampleAt=now
            noteProgress("SEA_PROGRESS:"..math.floor(current.X)..":"..math.floor(current.Z))
        end
        if now-lastProgressAt>=2 then
            PHX.BoatPosition=current
            lastProgressPos,lastProgressAt=current,now
        end
        local step=math.min(remaining,speed*dt)
        local position=current+heading*step
        position=Vector3.new(position.X,current.Y+math.clamp(targetPos.Y-current.Y,-speed*dt,speed*dt),position.Z)
        local ok=pcall(function() boat:PivotTo(CFrame.lookAt(position,position+heading)) end)
        if not ok then failure="BOAT_PIVOT_FAILED";break end
        RunService.Heartbeat:Wait()
    end
    PHX.stopBoat(boat)
    if failure then
        PHX.BoatState=failure
        logLine("BOAT_RECOVERY",failure.." | verify server ownership / team occupancy")
        if failure=="BOAT_STALLED_3S" or failure=="BOAT_PIVOT_FAILED" then
            local attempts=(PHX.BoatStallAttempts[boat] or 0)+1
            PHX.BoatStallAttempts[boat]=attempts
            if attempts>=2 then
                PHX.RejectedBoats[boat]=true
                PHX.SeaHeading=nil
                PHX.BoatState="REBUY_AFTER_STALL"
                PHX.NextBoatBuyAt=os.clock()+4
                logLine("BOAT_RECOVERY","Rejected stalled boat after "..attempts.." failed segments")
            end
        end
        return false
    end
    PHX.BoatStallAttempts[boat]=0
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
        PHX.refreshCrew(boat)
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
            if PHX.prehistoricMarker() then
                PHX.BoatState="MARKER_WAIT_TIMEOUT"
                logLine("BOAT_RECOVERY","Prehistoric marker still exists; island did not replicate after 20s")
                return nil
            end
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
        local label=PHX.isSoloAutomation and PHX.isSoloAutomation() and "SOLO" or "MASTER"
        setStatus(label..": Sea6 STRAIGHT | sailed "..math.floor(distanceSailed).." | aboard "..countTeamAboard(boat))
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

local function getRelic(island)
    local core = island and island:FindFirstChild("Core")
    return core and core:FindFirstChild("PrehistoricRelic")
end

local function relicPart(relic)
    if not relic then return nil end
    return relic:FindFirstChild("Inside") or relic:FindFirstChild("Skull") or relic:FindFirstChildWhichIsA("BasePart", true)
end

PHX.EventState = {Phase="WAIT", Egg="WAIT", Error=nil}
PHX.AFKLastRelic = setmetatable({}, {__mode="k"})
PHX.AFKRewardExit = nil
PHX.AFKRecoveryUntil = 0
PHX.AFKRecoveryCount = 0
function PHX.afkSoloEnabled()
    return CONFIG.AFK_SOLO and CONFIG.AFK_SOLO.ENABLED == true
        and PHX.isSoloAutomation and PHX.isSoloAutomation() == true
end
function PHX.afkRelicProof(island)
    local latest=PHX.AFKLastRelic and PHX.AFKLastRelic[island]
    if latest and os.clock()-latest.At <= CONFIG.AFK_SOLO.RELIC_PROOF_MAX_AGE then
        return latest.Value, "LAST_ACTIVE_HUD"
    end
    return nil,"NO_RECENT_RELIC_PROOF"
end
function PHX.afkResetAuthorized()
    local a=PHX.AFKRewardExit
    if not PHX.afkSoloEnabled() or not a or a.Confirmed ~= true then return false end
    if a.Character ~= LP.Character or os.clock()-(a.At or 0)>90 then return false end
    if a.Relic <= CONFIG.AFK_SOLO.EGG_FAST_RESET_RELIC_ABOVE then return false end
    local progress=PHX.RewardProgress and PHX.RewardProgress[a.Island]
    return progress==a.Progress and progress and progress.EggState=="CONFIRMED"
        and progress.PostEggGuard == true
end
PHX.FossilAttempted = setmetatable({}, {__mode="k"})
PHX.EventSeenHUD = setmetatable({}, {__mode="k"})
PHX.EventFinishedIslands = setmetatable({}, {__mode="k"})
PHX.RewardProgress = setmetatable({}, {__mode="k"})
PHX.CompletedIslands = setmetatable({}, {__mode="k"})
PHX.GolemPrepared = setmetatable({}, {__mode="k"})
PHX.GolemLastBring = setmetatable({}, {__mode="k"})
PHX.GolemDamage = setmetatable({}, {__mode="k"})
PHX.GolemLocalHpState = {Writes=0,LocalZero=0,Errors=0,LastAt=0,LastMessage="READY",
    Written=setmetatable({}, {__mode="k"}), LastTry=setmetatable({}, {__mode="k"}),
    IslandMarkers=setmetatable({}, {__mode="k"})}
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
    if out.Active then
        PHX.RaidLastSeenAt=os.clock()
        if type(out.TimerSeconds)=="number" and out.TimerSeconds>=0 then
            PHX.RaidLastTimer={At=os.clock(),Remaining=out.TimerSeconds}
        end
    end
    PHX.RaidHUDCache = out
    return out
end

function PHX.raidTimerStillRunning()
    local t=PHX.RaidLastTimer
    if not t then return false,nil end
    local left=(tonumber(t.Remaining) or 0)-(os.clock()-(tonumber(t.At) or os.clock()))
    return left>2,math.max(0,left)
end

function PHX.raidResetBlockReason()
    if PHX.afkResetAuthorized() then return nil end
    local hud=PHX.readRaidHUD(true)
    if hud.Active then return "HUD_ACTIVE" end
    local running,remaining=PHX.raidTimerStillRunning()
    if running then return string.format("TIMER_REMAINING_%.0fs",remaining) end
    if PHX.RaidLastSeenAt and os.clock()-PHX.RaidLastSeenAt<12 then return "RECENT_ACTIVE_HUD" end
    local island=PHX.ActiveEventCrewIsland
    if island and island.Parent and PHX.EventSeenHUD and PHX.EventSeenHUD[island]
        and not (PHX.EventFinishedIslands and PHX.EventFinishedIslands[island]) then
        return "ISLAND_EVENT_NOT_CONFIRMED_FINISHED"
    end
    return nil
end

function PHX.raidFinishAfterHudLoss(missingSince)
    if not missingSince or os.clock()-missingSince<12 then return false end
    if PHX.readRaidHUD(true).Active then return false end
    if PHX.raidTimerStillRunning() then return false end
    return true
end

function PHX.eventActive(island)
    local hud = PHX.readRaidHUD()
    if hud.Active then
        if island then PHX.EventSeenHUD[island] = true end
        return true
    end
    if island and PHX.EventSeenHUD[island] then return false end
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
    local relicPercent=getRelicHealthPercent(island)
    if active and island and type(relicPercent)=="number" then
        PHX.AFKLastRelic[island]={Value=relicPercent,At=os.clock()}
    end
    local out = {
        At=os.clock(), Active=active, Pressure=hud.Pressure, Relic=relicPercent,
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
    if PHX.afkSoloEnabled() then
        PHX.AFKRecoveryCount=PHX.AFKRecoveryCount+1
        PHX.AFKRecoveryUntil=os.clock()+CONFIG.AFK_SOLO.ERROR_RETRY_GAP
        logLine("AFK_RETRY", tostring(reason).." | retry="..PHX.AFKRecoveryCount)
        setStatus("AFK SOLO: tự thử lại sau "..CONFIG.AFK_SOLO.ERROR_RETRY_GAP.."s | "..tostring(reason))
        return
    end
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

local function countTeamNear(pos, radius, island)
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        local rr,hh=root(),hum()
        return rr and hh and hh.Health>0 and (rr.Position-pos).Magnitude<=radius and 1 or 0
    end
    local names=island and PHX.observeFossilCrew(island,pos,radius) or nil
    local n = 0
    for _,p in ipairs(Players:GetPlayers()) do
        local member=names and table.find(names,p.Name) or (not names and isTeamName(p.Name))
        if member and p.Character then
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
    local required=PHX.requiredFossilPlayers and PHX.requiredFossilPlayers() or CONFIG.MIN_TEAM_NEAR_RELIC
    local waitUntil = os.clock() + CONFIG.FOSSIL.TEAM_WAIT_SECONDS
    while isRunning(token) and island.Parent and not PHX.eventActive(island) and os.clock() < waitUntil do
        local near = countTeamNear(target.Position, CONFIG.RELIC_RADIUS, island)
        PHX.eventStatus(roleText()..": Fossil "..near.."/"..required, "FOSSIL_START")
        if near >= required then break end
        task.wait(.2)
    end
    if PHX.eventActive(island) then return true end
    if not isRunning(token) or not island.Parent then return false end
    if countTeamNear(target.Position, CONFIG.RELIC_RADIUS, island) < required then
        PHX.pauseEvent("TEAM_RELIC_TIMEOUT", "Team not ready at captured Fossil spot -> paused")
        return false
    end
    PHX.FossilAttempts = PHX.FossilAttempts or setmetatable({}, {__mode="k"})
    if PHX.FossilAttempted[island] then
        if PHX.isSoloAutomation() then
            local history=PHX.FossilAttempts[island] or {Count=1,At=os.clock()}
            if os.clock()-history.At < 14 then
                PHX.eventStatus("SOLO: waiting for Fossil HUD after E hold (no STOP)","FOSSIL_WAIT")
                task.wait(.7)
                return false
            end
            if history.Count >= 2 then
                if not PHX.afkSoloEnabled() then
                    PHX.eventStatus("SOLO: Fossil not confirmed after 2 holds; awaiting manual start / HUD (runner stays ON)","FOSSIL_WAIT")
                    task.wait(1)
                    return false
                end
                if history.Count >= 4 then
                    if PHX.raidResetBlockReason() then
                        task.wait(1)
                        return false
                    end
                    PHX.eventStatus("AFK SOLO: Fossil failed 4x -> safely return to Tiki", "FOSSIL_RECOVERY")
                    logLine("AFK_FOSSIL_RECOVER", "four E holds without raid HUD; return for new island")
                    PHX.PendingDepartureIsland=island
                    if resetBackToTiki and resetBackToTiki(token) then
                        PHX.CompletedIslands[island]=true
                        PHX.PendingDepartureIsland=nil
                        PHX.ActiveEventCrewIsland=nil
                    end
                    PHX.AFKRecoveryUntil=os.clock()+CONFIG.AFK_SOLO.ERROR_RETRY_GAP
                    return false
                end
                if os.clock()-history.At < 30 then
                    PHX.eventStatus("AFK SOLO: waiting 30s before Fossil retry "..(history.Count+1).."/4", "FOSSIL_WAIT")
                    task.wait(.7)
                    return false
                end
            end
            PHX.FossilAttempted[island]=nil
        else
            PHX.pauseEvent("FOSSIL_UNCONFIRMED", "Fossil already attempted; inspect or start manually, then resume")
            return false
        end
    end
    if not safeTween(target, CONFIG.FOSSIL.SAFE_SPEED, token) then return false end
    local rr = root()
    if not rr or (rr.Position-target.Position).Magnitude > 4 then return false end
    pcall(function()
        rr.AssemblyLinearVelocity = Vector3.zero
        rr.AssemblyAngularVelocity = Vector3.zero
    end)
    task.wait(CONFIG.FOSSIL.SETTLE_TIME)
    if not isRunning(token) then return false end
    PHX.FossilAttempted[island] = true
    if PHX.isSoloAutomation() then
        local history=PHX.FossilAttempts[island] or {Count=0,At=0}
        history.Count+=1
        history.At=os.clock()
        PHX.FossilAttempts[island]=history
        setStatus("SOLO: exact Fossil pose -> donor V2.9 Virtual HOLD E 3s")
        logLine("FOSSIL_SOLO", "Hold E begin | attempt="..history.Count)
        local down=pcall(function() PHX.keyEvent(true,Enum.KeyCode.E,false,game) end)
        if not down then
            pcall(function() PHX.keyEvent(false,Enum.KeyCode.E,false,game) end)
            PHX.FossilAttempted[island]=nil
            return false
        end
        local untilAt=os.clock()+(CONFIG.FOSSIL.HOLD_SECONDS or 3)
        while isRunning(token) and island.Parent and os.clock()<untilAt do task.wait(.04) end
        pcall(function() PHX.keyEvent(false,Enum.KeyCode.E,false,game) end)
        logLine("FOSSIL_SOLO","Hold E released")
        if not isRunning(token) or not island.Parent then return false end
    else
        setStatus(roleText()..": exact Fossil pose -> TEAM click/touch hold 3s")
        if not PHX.holdInteraction(getRelic(island), CONFIG.FOSSIL.HOLD_SECONDS, token) then return false end
    end
    local deadline = os.clock()+(PHX.isSoloAutomation() and 5 or 3)
    repeat
        PHX.RaidHUDCache = nil
        if PHX.eventActive(island) then
            PHX.EventState.Error = nil
            noteProgress("FOSSIL_STARTED")
            return true
        end
        task.wait(.08)
    until not isRunning(token) or not island.Parent or os.clock() >= deadline
    if isRunning(token) then
        if PHX.isSoloAutomation() then
            PHX.EventState.Error="FOSSIL_HUD_PENDING"
            PHX.eventStatus("SOLO Fossil E hold complete; HUD pending, no STOP / no rapid E spam", "FOSSIL_WAIT")
            logLine("FOSSIL_SOLO","HUD unconfirmed after 5s; runner retained for bounded recovery")
        else
            PHX.pauseEvent("FOSSIL_UNCONFIRMED", "TEAM Fossil hold unconfirmed -> paused for inspection")
        end
    end
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
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        local rr=root()
        local blocked=PHX.SoloUnsafeRockUntil or {}
        if rr then
            local best,distance=nil,math.huge
            for _,rock in ipairs(rocks) do
                if (blocked[rock.model] or 0) <= os.clock() then
                    local current=(rock.part.Position-rr.Position).Magnitude
                    if current<distance then best,distance=rock,current end
                end
            end
            return best,#rocks -- all unsafe: yield briefly, don't dive into magma
        end
    end
    return rocks[((tonumber(offset) or 1)-1)%#rocks+1], #rocks
end

function PHX.soloRelicGolemThreat(island, golems)
    golems = golems or PHX.liveGolems()
    if #golems == 0 then return nil, math.huge end
    local relic = relicPart(getRelic(island))
    local fallbackRoot = root()
    local refPosition = relic and relic.Position or (fallbackRoot and fallbackRoot.Position)
    local best, nearest = nil, math.huge
    for _,g in ipairs(golems) do
        local h = g:FindFirstChildOfClass("Humanoid")
        local gp = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
        if gp and h and h.Health > 0 then
            local distance = refPosition and (gp.Position - refPosition).Magnitude or 0
            if distance < nearest then best,nearest = g,distance end
        end
    end
    if not relic and best then return best,0 end
    return best,nearest
end

-- V2.17.03: GOLEM-ABSOLUTE SOLO POLICY.
-- Legacy radius/pressure thresholds no longer override a live Lava Golem.
-- TEAM's pressure allocation remains unchanged.
function PHX.soloRelicThreatRadius(relicHp, pressure)
    return math.huge -- compatibility for callers querying SOLO threat radius
end

function PHX.soloPressureMustYield(island)
    -- Any replicated, living Golem forces pressure work to yield, regardless of
    -- distance, pressure reading, Relic HP or the presence of active rocks.
    return #PHX.liveGolems() > 0
end

PHX.SoloPressureRecovery=setmetatable({}, {__mode="k"})
function PHX.soloPressurePriority(island, snapshot, distance, rock)
    -- Legacy entry point. Pressure is permitted ONLY when the Golem list is
    -- empty. Do not use previously latched recovery or pressure thresholds.
    if not rock then return false end
    return not PHX.soloPressureMustYield(island)
end

function PHX.teamPressureAssignment(island, snapshot, golems)
    golems=golems or PHX.liveGolems()
    if #golems==0 then PHX.TeamPressureDutyLevel=0; return true,"NO_GOLEMS" end
    local idx=teamIndex(LP.Name)
    if idx~=3 and idx~=4 then PHX.TeamPressureDutyLevel=0;return false,"GOLEM_CORE" end
    if PHX.TeamPressureDutyIsland~=island then
        PHX.TeamPressureDutyIsland=island
        PHX.TeamPressureDutyLevel=0
    end
    local pressure=tonumber(snapshot and snapshot.Pressure)
    if pressure==nil then PHX.TeamPressureDutyLevel=0;return false,"PRESSURE_UNKNOWN" end
    local cfg=CONFIG.TEAM_PRESSURE_GUARD
    local previous=PHX.TeamPressureDutyLevel or 0
    local assigned=false
    if idx==4 then
        assigned=pressure>=cfg.SINGLE_ENTER or (previous==1 and pressure>cfg.SINGLE_EXIT)
    else
        local _,distance=PHX.soloRelicGolemThreat(island,golems)
        local golemSafe=distance>=cfg.DOUBLE_SAFE_GOLEM_DISTANCE or pressure>=cfg.DOUBLE_EMERGENCY
        assigned=golemSafe and (pressure>=cfg.DOUBLE_ENTER or (previous==2 and pressure>cfg.DOUBLE_EXIT))
    end
    local level=assigned and (idx==4 and 1 or 2) or 0
    if level~=previous then
        logLine("TEAM_PRESSURE_DUTY", "slot="..idx.." | tier="..level.." | pressure="..pressure)
    end
    PHX.TeamPressureDutyLevel=level
    return assigned, assigned and "PRESSURE_HELPER" or "GOLEM_DEFENSE"
end

local function pressureWorkShouldYield(island)
    local golems=PHX.liveGolems()
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then
        -- Absolute priority: any live Golem interrupts pressure work.
        return #golems > 0
    end
    if #golems==0 then return false end
    local snapshot=PHX.eventSnapshot(island)
    return not PHX.teamPressureAssignment(island,snapshot,golems)
end

PHX.SoloLavaModelLogged = setmetatable({}, {__mode="k"})
local function soloLavaCylinderForIsland(island)
    local cfg = CONFIG.SOLO_GUARD.LAVA_CYLINDER
    if not island or not island.Parent then return nil, "NO_ISLAND" end
    local fossilPose = PHX.capturedFossilTarget(island)
    if not fossilPose then return nil, "NO_FOSSIL_POSE" end
    local sampleDelta = cfg.SAMPLE_DEATH - cfg.SAMPLE_FOSSIL_PLAYER
    local top = fossilPose.Position + sampleDelta
    if not PHX.SoloLavaModelLogged[island] then
        PHX.SoloLavaModelLogged[island] = true
        logLine("SOLO_LAVA_MODEL", "APPROX translation-only | centerXZ="..
            string.format("%.1f, %.1f", top.X, top.Z).." | topY="..
            math.floor(top.Y).." | bottomY="..math.floor(top.Y-cfg.HEIGHT)..
            " | avoidRadius="..cfg.ROUTE_RADIUS)
    end
    return {
        Center = Vector3.new(top.X, 0, top.Z),
        Top = top.Y,
        Bottom = top.Y - cfg.HEIGHT,
        Radius = cfg.ROUTE_RADIUS,
    }, "FOSSIL_TRANSLATION_CALIBRATION"
end

local function soloCylinderIntersects(a, b, zone)
    local ax, az = a.X-zone.Center.X, a.Z-zone.Center.Z
    local dx, dz = b.X-a.X, b.Z-a.Z
    local A = dx*dx+dz*dz
    local t0,t1 = 0,1
    if A < 1e-7 then
        if ax*ax+az*az >= zone.Radius*zone.Radius then return false end
    else
        local B = 2*(ax*dx+az*dz)
        local C = ax*ax+az*az-zone.Radius*zone.Radius
        local disc = B*B-4*A*C
        if disc < 0 then
            if C >= 0 then return false end
        else
            local sd=math.sqrt(math.max(0,disc))
            local enter=(-B-sd)/(2*A)
            local leave=(-B+sd)/(2*A)
            t0=math.max(t0,enter)
            t1=math.min(t1,leave)
            if t0>t1 then return false end
        end
    end
    local dy=b.Y-a.Y
    if math.abs(dy)<1e-7 then
        return a.Y>=zone.Bottom and a.Y<=zone.Top
    end
    local y0=(zone.Bottom-a.Y)/dy
    local y1=(zone.Top-a.Y)/dy
    if y0>y1 then y0,y1=y1,y0 end
    return math.max(t0,y0,0)<=math.min(t1,y1,1)
end

local function soloRockUnsafe(rock, why)
    PHX.SoloUnsafeRockUntil = PHX.SoloUnsafeRockUntil or setmetatable({}, {__mode="k"})
    if rock and rock.model then
        PHX.SoloUnsafeRockUntil[rock.model] = os.clock() + CONFIG.SOLO_GUARD.ROCK_UNSAFE_RETRY
    end
    logLine("SOLO_LAVA_SKIP", tostring(why))
end

local function soloGuardSegment(cf, speed, token, tag, zone, island)
    local h = hum()
    if not h or h.Health <= 0 then return false end
    local isRockTravel=type(tag)=="string" and tag:sub(1,4)=="ROCK"
    -- Perform early priority check BEFORE subscribing to Humanoid events.
    if isRockTravel and PHX.soloPressureMustYield(island) then return false end
    local starting = h.Health
    local damaged = false
    local conn = h.HealthChanged:Connect(function(hp)
        if hp < starting - 0.5 then
            damaged = true
            local activeTween = PHX.TravelState and PHX.TravelState.Tween
            if activeTween then pcall(function() activeTween:Cancel() end) end
        end
    end)
    local volumeEntered=false
    local priorityInterrupted=false
    local lastPriorityCheck=-math.huge
    local watch=nil
    if zone or isRockTravel then
        watch=RunService.Heartbeat:Connect(function()
            -- Abort an IN-PROGRESS rock tween when a new Golem spawns.
            -- Check at 0.1s intervals to avoid scanning enemies every frame.
            if isRockTravel and os.clock()-lastPriorityCheck>=.10 then
                lastPriorityCheck=os.clock()
                if PHX.soloPressureMustYield(island) then
                    priorityInterrupted=true
                    local tween=PHX.TravelState and PHX.TravelState.Tween
                    if tween then pcall(function() tween:Cancel() end) end
                    return
                end
            end
            if not zone then return end
            local rr=root()
            if not rr then return end
            local dx,dz=rr.Position.X-zone.Center.X,rr.Position.Z-zone.Center.Z
            if dx*dx+dz*dz < zone.Radius*zone.Radius
                and rr.Position.Y>=zone.Bottom and rr.Position.Y<=zone.Top then
                volumeEntered=true
                local activeTween=PHX.TravelState and PHX.TravelState.Tween
                if activeTween then pcall(function() activeTween:Cancel() end) end
            end
        end)
    end
    local result = safeTween(cf, speed, token)
    conn:Disconnect()
    if watch then watch:Disconnect() end
    if priorityInterrupted then
        logLine("SOLO_GOLEM_FIRST", "PREEMPT_ROCK_MOVE | "..tostring(tag or "ROCK"))
        return false
    end
    if volumeEntered then
        logLine("SOLO_LAVA_INTRUSION",tostring(tag or "MOVE").." | position="..
            tostring(root() and root().Position))
        return false
    end
    if damaged then
        logLine("SOLO_LAVA_ABORT", tostring(tag or "MOVE") .. " | hp=" ..
            tostring(math.floor(starting)) .. "->" .. tostring(math.floor(h.Health)))
        return false
    end
    return result == true
end

local function soloAtRisk(p,zone)
    local dx,dz=p.X-zone.Center.X,p.Z-zone.Center.Z
    return dx*dx+dz*dz < zone.Radius*zone.Radius
        and p.Y>=zone.Bottom and p.Y<=zone.Top
end

local function soloBuildLavaDetour(startPos,endPos,zone)
    local cfg=CONFIG.SOLO_GUARD.LAVA_CYLINDER
    if soloAtRisk(startPos,zone) then return nil,"START_IN_FORBIDDEN_VOLUME" end
    if soloAtRisk(endPos,zone) then return nil,"TARGET_IN_FORBIDDEN_VOLUME" end
    local cx,cz=zone.Center.X,zone.Center.Z
    local navR=zone.Radius+cfg.WAYPOINT_OUTSET
    local function polar(p)
        local x,z=p.X-cx,p.Z-cz
        return math.atan2(z,x),math.sqrt(x*x+z*z)
    end
    local sa,sd=polar(startPos)
    local ea,ed=polar(endPos)
    if sd<0.001 or ed<0.001 then return nil,"CENTER_AXIS_ROUTE_UNCALIBRATED" end
    local function point(angle)
        return Vector3.new(cx+math.cos(angle)*navR,0,cz+math.sin(angle)*navR)
    end
    local function tangent(angle,dist,sign)
        if dist<=navR then return angle end
        return angle+sign*math.acos(math.clamp(navR/dist,-1,1))
    end
    local best,bestLength=nil,math.huge
    local tau=2*math.pi
    for _,direction in ipairs({-1,1}) do
        local firstAngle=tangent(sa,sd,direction)
        local lastAngle=tangent(ea,ed,-direction)
        local span
        if direction==1 then
            span=(lastAngle-firstAngle)%tau
        else
            span=(firstAngle-lastAngle)%tau
        end
        local count=math.max(1,math.ceil(span/math.rad(cfg.ARC_STEP_DEGREES)))
        if count<=cfg.MAX_WAYPOINTS then
            local planar={Vector3.new(startPos.X,0,startPos.Z)}
            for i=0,count do
                planar[#planar+1]=point(firstAngle+direction*span*(i/count))
            end
            planar[#planar+1]=Vector3.new(endPos.X,0,endPos.Z)
            local total=0
            for i=2,#planar do total+=(planar[i]-planar[i-1]).Magnitude end
            local path={startPos}
            local walked=0
            for i=2,#planar-1 do
                walked+=(planar[i]-planar[i-1]).Magnitude
                local y=startPos.Y+(endPos.Y-startPos.Y)*math.clamp(walked/math.max(total,.001),0,1)
                path[#path+1]=Vector3.new(planar[i].X,y,planar[i].Z)
            end
            path[#path+1]=endPos
            local valid=true
            for i=2,#path do
                if soloCylinderIntersects(path[i-1],path[i],zone) then valid=false;break end
            end
            if valid and total<bestLength then best,bestLength=path,total end
        end
    end
    return best,best and "VALID_DETOUR" or "NO_COLLISION_FREE_DETOUR"
end

local function soloGuardApproach(position,hoverY,token,baseSpeed,tag,island)
    local rr = root()
    if not rr or not position or not isRunning(token) then return false end
    local cfg=CONFIG.SOLO_GUARD
    local speed=(tonumber(baseSpeed) or 165)*cfg.TWEEN_MULTIPLIER
    local destination=Vector3.new(position.X,position.Y+hoverY,position.Z)
    if (rr.Position-destination).Magnitude<=3 then return true end
    local zone,why=soloLavaCylinderForIsland(island)
    if not zone then
        logLine("SOLO_LAVA_ZONE_MISSING",tostring(why).." | target="..tostring(tag))
        return false -- fail closed instead of blindly crossing an unknown hazard
    end
    local name=tostring(tag or "TARGET")
    if not soloCylinderIntersects(rr.Position,destination,zone) then
        return soloGuardSegment(CFrame.new(destination),speed,token,name.."_DIRECT",zone,island)
    end
    local route,reason=soloBuildLavaDetour(rr.Position,destination,zone)
    if not route then
        logLine("SOLO_LAVA_UNREACHABLE",name.." | "..tostring(reason).." | top="..
            math.floor(zone.Top).." bottom="..math.floor(zone.Bottom).." r="..zone.Radius)
        return false
    end
    logLine("SOLO_LAVA_DETOUR",name.." | nodes="..tostring(#route)..
        " | center="..tostring(zone.Center).." | top="..math.floor(zone.Top)..
        " | bottom="..math.floor(zone.Bottom).." | r="..zone.Radius)
    for i=2,#route do
        local rootNow=root()
        if not rootNow or not isRunning(token) then return false end
        if soloCylinderIntersects(rootNow.Position,route[i],zone) then
            logLine("SOLO_LAVA_ROUTE_CHANGED",name.." | leg="..i)
            return false
        end
        if (rootNow.Position-route[i]).Magnitude>3 then
            if not soloGuardSegment(CFrame.new(route[i]),speed,token,name.."_DET"..i,zone,island) then return false end
        end
    end
    return true
end

function PHX.pressureRockBurst(target, token, island)
    if not target or not target.model or not target.part then return false end
    local solo=PHX.isSoloAutomation and PHX.isSoloAutomation()
    local deadline = os.clock() + (solo and CONFIG.SOLO_GUARD.PRESSURE_BURST_SECONDS or CONFIG.PRESSURE.MAX_BURST_SECONDS)
    while isRunning(token) and target.model.Parent and rockActive(target.model) and os.clock() < deadline do
        if pressureWorkShouldYield(island) then return false end
        if island and not PHX.eventActive(island) then return false end
        local p, rp = target.part.Position, root()
        if not rp then return false end
        local hoverHeight=solo and CONFIG.SOLO_GUARD.ROCK_SAFE_HOVER_Y or CONFIG.PRESSURE.ROCK_HOVER_Y
        local hover = CFrame.new(p + Vector3.new(0, hoverHeight, 0))
        if solo then
            if not soloGuardApproach(p, hoverHeight,token,CONFIG.SOLO_PRESSURE_TWEEN_SPEED or 260,"ROCK",island) then
                -- New Golem preemption is a priority switch, NOT an unsafe rock.
                if pressureWorkShouldYield(island) then return false end
                soloRockUnsafe(target, "Rock approach refused or HP dropped")
                return false
            end
        elseif (rp.Position-hover.Position).Magnitude>14 and not safeTween(hover,165,token) then
            return false
        end
        local postMoveHum=hum()
        local hpAtRock=postMoveHum and postMoveHum.Health or 0
        if solo and hpAtRock <= 0 then soloRockUnsafe(target,"Dead at Pressure Rock");return false end
        if solo then aimAt(p) end -- V2.9 donor pressure aim
        local order=solo and {"Blox Fruit","Melee"} or {"Melee","Blox Fruit"}
        for _,tooltip in ipairs(order) do
            local tool=equipTooltip(tooltip)
            if tool then
                for _,key in ipairs(skillKeysForTooltip(tooltip)) do
                    if os.clock()>=deadline then break end
                    if not isRunning(token) or not target.model.Parent or not rockActive(target.model) or pressureWorkShouldYield(island) then return false end
                    aimAt(p)
                    pressKey(key, CONFIG.PRESSURE.SKILL_HOLD)
                    task.wait(solo and CONFIG.SOLO_GUARD.PRESSURE_SKILL_GAP or CONFIG.PRESSURE.SKILL_GAP)
                    if solo then
                        local currentHum=hum()
                        if not currentHum or currentHum.Health < hpAtRock - 0.5 then
                            soloRockUnsafe(target,"HP fell during rock skills: "..tostring(hpAtRock).."->"..tostring(currentHum and currentHum.Health))
                            return false
                        end
                    end
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
    local islandPivot = island:GetPivot()
    local away = Vector3.new(-islandPivot.LookVector.X, 0, -islandPivot.LookVector.Z)
    if away.Magnitude < .1 then away = Vector3.new(1,0,0) end
    -- Prefer the direction from the Fossil to the existing Golems (for both
    -- TEAM and SOLO). This pushes them away rather than toward the Relic.
    local sum,count,sumY=Vector3.zero,0,0
    for _,g in ipairs(PHX.liveGolems()) do
        local gp=g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
        if gp then
            local delta=gp.Position-relicPivot.Position
            sum+=Vector3.new(delta.X,0,delta.Z)
            sumY+=gp.Position.Y
            count+=1
        end
    end
    if sum.Magnitude>=1 then away=sum end
    local distance=math.max(tonumber(CONFIG.GOLEM_AURA.BRING_DISTANCE_FROM_RELIC) or 195,
        (tonumber(CONFIG.GOLEM_AURA.MIN_RELIC_DISTANCE) or 165)+12)
    local pos=relicPivot.Position+away.Unit*distance
    pos=Vector3.new(pos.X,count>0 and sumY/count or target.Position.Y,pos.Z)
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

PHX.GolemBringStats={Attempts=0,Applied=0,Failed=0,NotOwned=0,LastError=nil,LastAt=nil,LastLoggedAt=-math.huge}
function PHX.bringGolemCluster(island, golems)
    if not island or not island.Parent then return nil end
    local anchor = PHX.clusterAnchor(island)
    -- Slave clients still need the anchor for their melee approach; only the
    -- Master/SOLO client owns the relocation attempt.
    if not anchor or not isMaster() or CONFIG.GOLEM_AURA.BRING_ENABLED==false then return anchor end
    local now = os.clock()
    local relic=getRelic(island)
    local relicPose=relic and relicPart(relic)
    local relicPos=relicPose and relicPose.Position or anchor.Position
    local minDistance=tonumber(CONFIG.GOLEM_AURA.MIN_RELIC_DISTANCE) or 165
    local interval=tonumber(CONFIG.GOLEM_AURA.BRING_INTERVAL) or .15
    local drift=tonumber(CONFIG.GOLEM_AURA.REBRING_DRIFT) or 8
    local radius=tonumber(CONFIG.GOLEM_AURA.CLUSTER_RADIUS) or 4
    for i,g in ipairs(golems or {}) do
        local h = g:FindFirstChildOfClass("Humanoid")
        local gp = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
        if h and h.Health > 0 and gp and gp:IsA("BasePart") and not gp.Anchored then
            PHX.prepareGolemOnce(g)
            local angle=((i-1)/math.max(#golems,1))*math.pi*2
            local off=#golems>1 and Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius) or Vector3.zero
            local targetPos=anchor.Position+off
            local slot=CFrame.lookAt(targetPos,targetPos+anchor.LookVector)
            local delta=gp.Position-relicPos
            local relicHorizontal=Vector3.new(delta.X,0,delta.Z).Magnitude
            local mustProtect=relicHorizontal<minDistance
            local movingFar=(gp.Position-targetPos).Magnitude>=drift
            if (mustProtect or movingFar) and now-(PHX.GolemLastBring[g] or -math.huge)>=interval then
                PHX.GolemLastBring[g]=now
                local stats=PHX.GolemBringStats
                stats.Attempts+=1
                local ok,err=pcall(function()
                    g:PivotTo(slot)
                    gp.AssemblyLinearVelocity=Vector3.zero
                    gp.AssemblyAngularVelocity=Vector3.zero
                end)
                if ok then stats.Applied+=1;stats.LastAt=now
                else stats.Failed+=1;stats.LastError=tostring(err) end
                -- Request accepted locally does not prove NPC moved on server.
                if now-stats.LastLoggedAt>10 then
                    stats.LastLoggedAt=now
                    print("[PX GOLEM BRING] local requests="..stats.Attempts.." applied="..stats.Applied..
                        " errors="..stats.Failed.." (server replication NOT verified)")
                end
            end
        end
    end
    return anchor
end

-- SOLO has its own golemRushBurst, so the TEAM burst's bring call did not
-- protect the Relic during pressure work. This single non-attack worker runs
-- only for SOLO while the raid is active, and shares the same bring throttle.
PHX.spawn(function()
    while PHX.generationAlive() do
        if ENV.TeamConfig.IsRunning and PHX.isSoloAutomation() then
            local island=findPrehistoric()
            if island and PHX.eventActive(island) then
                local golems=PHX.liveGolems()
                if #golems>0 then
                    local ok,err=pcall(PHX.bringGolemCluster,island,golems)
                    if not ok then PHX.GolemBringStats.LastError=tostring(err) end
                end
            end
        end
        task.wait(.18)
    end
end)

function PHX.netHitGolemCluster(golems)
    -- Compatibility: any legacy caller must use the same Recovery NET dispatcher.
    return PHX.killAuraDispatch(golems,"NET")
end


-- KILL AURA V1 integrated: one shared combat backend for farms and Golems.
-- No separate attack worker while main automation is active.
PHX.KillAura = {Requests=0,NativeRequests=0,NetRequests=0,ObservedDamage=0,
    LastDamageAt=nil,LastStepAt=0,TargetCount=0,Hp=setmetatable({}, {__mode="k"}),
    LastMessage="READY"}
function PHX.killAuraRelease()
    -- If another caller was interrupted during a mouse press, release it.
    if PHX.Runtime and PHX.Runtime.HeldMouse then
        for button,pointer in pairs(PHX.Runtime.HeldMouse) do
            pcall(function() PHX.mouseEvent(pointer.X,pointer.Y,button,false,pointer.Target,pointer.Layer) end)
        end
    end
end
function PHX.killAuraTargets(radius)
    local rr=root()
    local h=hum()
    local enemies=workspace:FindFirstChild("Enemies")
    if not rr or not h or h.Health<=0 or h.SeatPart or not enemies then return {} end
    local targets={}
    for _,model in ipairs(enemies:GetChildren()) do
        if model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            local enemy,part=PHX.farmMobRoot(model)
            if enemy and part then
                local distance=(part.Position-rr.Position).Magnitude
                if distance<=radius then
                    targets[#targets+1]={Model=model,Humanoid=enemy,Part=part,Distance=distance}
                end
            end
        end
    end
    table.sort(targets,function(a,b) return a.Distance<b.Distance end)
    return targets
end
function PHX.killAuraObserve(targets)
    local aura=PHX.KillAura
    for model,old in pairs(aura.Hp) do
        if not model.Parent or old.Humanoid.Parent~=model or old.Humanoid.Health<=0 then
            aura.Hp[model]=nil
        else
            if old.Humanoid.Health<old.Health then
                aura.ObservedDamage+=old.Health-old.Humanoid.Health
                aura.LastDamageAt=os.clock()
            end
            old.Health=old.Humanoid.Health
        end
    end
    for _,entry in ipairs(targets or {}) do
        local old=aura.Hp[entry.Model]
        if not old or old.Humanoid~=entry.Humanoid then
            aura.Hp[entry.Model]={Humanoid=entry.Humanoid,Health=entry.Humanoid.Health}
        end
    end
end
-- PX V2.17.11 RECOVERY NET BACKEND
-- Derived from standalone PX_KillAura_Recovery_Test_V1.sendNET that the user tested.
-- No native M1 fallback, no GUI clicks. Different hit-part modes are selectable in Settings.
-- RPC accepted for transmission != server-confirmed NPC damage.
function PHX.killAuraDispatch(models,backend)
    local aura=PHX.KillAura
    if not CONFIG.KILL_AURA.Enabled or not PHX.generationAlive() then return false end
    local h,rr=hum(),root()
    if not h or h.Health<=0 or h.SeatPart or not rr or PHX.isMovementLocked() then
        aura.LastMessage="ACTOR_UNAVAILABLE"
        return false
    end
    local now=os.clock()
    local interval=math.max(.10,tonumber(CONFIG.KILL_AURA.NetGap) or .30)
    if now-(aura.LastNetAttemptAt or -math.huge)<interval then
        aura.LastMessage="RATE_LIMITED"
        return false
    end
    local tool=equipTooltip("Melee")
    if not tool or tool.Parent~=char() or not tool:IsA("Tool")
        or tostring(tool.ToolTip or "")~="Melee" or tool.Enabled==false
        or (PHX.isPhysicalFruitTool and PHX.isPhysicalFruitTool(tool)) then
        aura.LastMessage="MELEE_NOT_EQUIPPED"
        return false
    end
    local folder=workspace:FindFirstChild("Enemies")
    if not folder then aura.LastMessage="ENEMIES_FOLDER_MISSING";return false end

    local selected=CONFIG.KILL_AURA.NetMode or "NET_HEAD"
    if selected~="NET_HEAD" and selected~="NET_ROOT" and selected~="NET_HEAD_0" then
        selected="NET_HEAD"
    end
    local useHead=selected~="NET_ROOT"
    local delay=selected=="NET_HEAD_0" and 0 or .05
    local radius=math.max(1,tonumber(CONFIG.KILL_AURA.NetRange) or 35)

    -- Matches the recovery test: fresh live NPCs, correct hit part, validate range.
    local function collectFresh()
        local actorRoot=root()
        local actorHum=hum()
        if not actorRoot or not actorHum or actorHum.Health<=0 or actorHum.SeatPart
            or not PHX.generationAlive() or tool.Parent~=char() then
            return nil,nil,0
        end
        local hits,base={},nil
        for _,model in ipairs(models or {}) do
            if model and model.Parent==folder and model:IsA("Model")
                and not Players:GetPlayerFromCharacter(model) then
                local enemyHum=model:FindFirstChildOfClass("Humanoid")
                local part=model:FindFirstChild(useHead and "Head" or "HumanoidRootPart")
                if enemyHum and enemyHum.Health>0 and part and part:IsA("BasePart")
                    and (part.Position-actorRoot.Position).Magnitude<=radius then
                    hits[#hits+1]={model,part}
                    base=base or part
                end
            end
        end
        return base,hits,#hits
    end

    local base,hits,count=collectFresh()
    aura.TargetCount=count
    if not base then
        aura.LastMessage="NO_VALID_HIT_PART_WITHIN_RANGE"
        return false
    end
    local registerAttack,registerHit=resolveNetAttack()
    if not registerAttack or not registerHit
        or not registerAttack:IsA("RemoteEvent") or not registerHit:IsA("RemoteEvent") then
        aura.LastMessage="REGISTER_REMOTES_MISSING"
        return false
    end
    -- Prevent TEAM/SOLO/idle dispatch overlap; one pair per send.
    if aura.NetDispatchBusy then aura.LastMessage="NET_BUSY";return false end
    aura.NetDispatchBusy=true
    aura.LastNetAttemptAt=now
    local ok,sent,message=pcall(function()
        local sentAttack,attackError=pcall(function() registerAttack:FireServer(delay) end)
        if not sentAttack then return false,"ATTACK_RPC_ERROR:"..tostring(attackError) end
        if selected~=CONFIG.KILL_AURA.NetMode then return false,"NET_MODE_CHANGED" end
        local freshBase,freshHits,freshCount=collectFresh()
        aura.TargetCount=freshCount
        if not freshBase then return false,"TARGETS_EXPIRED_AFTER_ATTACK_RPC" end
        local sentHit,hitError=pcall(function() registerHit:FireServer(freshBase,freshHits) end)
        if not sentHit then return false,"HIT_RPC_ERROR:"..tostring(hitError) end
        return true,"REQUESTED_NOT_VERIFIED | mode="..selected.." | targets="..freshCount
    end)
    aura.NetDispatchBusy=false
    if not ok then
        aura.LastMessage="RECOVERY_NET_ERROR:"..tostring(sent)
        aura.NetErrors=(aura.NetErrors or 0)+1
        return false
    end
    aura.LastMessage=message or "RECOVERY_NET_FAILED"
    if sent then
        aura.NetRequests+=1
        aura.Requests+=1
        aura.Mode=selected
        PHX.FarmCombatDebug.LastNet=aura.LastMessage
        PHX.FarmCombatDebug.Hits+=count
        -- Sparse diagnostic logging only; server may reject packets without client errors.
        if aura.NetRequests%12==1 then
            logLine("RECOVERY_NET", "mode="..selected.." | sent="..aura.NetRequests
                .." | targetCount="..count.." | radius="..radius
                .." | damageNotGuaranteed=true")
        end
    else
        aura.NetErrors=(aura.NetErrors or 0)+1
        if (aura.NetErrors%8)==1 then logLine("RECOVERY_NET_ERROR",aura.LastMessage) end
    end
    return sent==true
end

function PHX.setRecoveryNetMode(selected)
    if selected~="NET_HEAD" and selected~="NET_ROOT" and selected~="NET_HEAD_0" then
        return false,"INVALID_NET_MODE"
    end
    CONFIG.KILL_AURA.NetMode=selected
    PHX.KillAura.LastNetAttemptAt=-math.huge
    PHX.KillAura.LastMessage="NET_MODE_SELECTED:"..selected
    logLine("RECOVERY_NET_MODE",selected)
    if PHX.saveUserConfig then PHX.saveUserConfig() end
    return true,selected
end

function PHX.killAuraIdleStep()
    if not CONFIG.KILL_AURA.Enabled or not CONFIG.KILL_AURA.IdleEnabled then return end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy or PHX.isMovementLocked() then return end
    local targets=PHX.killAuraTargets(math.max(1,tonumber(CONFIG.KILL_AURA.Radius) or 60))
    PHX.KillAura.TargetCount=#targets
    PHX.killAuraObserve(targets)
    if #targets>0 then
        local models={}
        for _,entry in ipairs(targets) do models[#models+1]=entry.Model end
        PHX.killAuraDispatch(models,"NET")
    end
end
PHX.spawn(function()
    while PHX.generationAlive() do
        local ok,err=pcall(PHX.killAuraIdleStep)
        if not ok then PHX.KillAura.LastMessage="ERROR: "..tostring(err) end
        task.wait(math.max(.15,tonumber(CONFIG.KILL_AURA.Interval) or .2))
    end
end)

-- GOLEM-ONLY local HP experiment. This mirrors the standalone diagnostic,
-- NOT a server-authorized kill: client HP=0 can remove a model locally without
-- stopping server-side attacks, crediting a kill, or protecting Fossil Relic.
-- Never run this on Forest Pirate, Dragon Hunter targets, players or generic NPCs.
function PHX.golemLocalHpStep(models, island, token)
    local cfg=CONFIG.GOLEM_LOCAL_KILL
    local state=PHX.GolemLocalHpState
    if not cfg or cfg.Enabled~=true or not PHX.generationAlive() then return false,0 end
    if token and not isRunning(token) then return false,0 end
    if not island or not island.Parent or not PHX.eventActive(island) then return false,0 end
    local actor,actorHum=root(),hum()
    local folder=workspace:FindFirstChild("Enemies")
    if not actor or not actorHum or actorHum.Health<=0 or not folder then return false,0 end
    local range=math.clamp(tonumber(cfg.Range) or 48,12,60)
    local wrote=0
    for _,g in ipairs(models or {}) do
        if g and g.Parent==folder and g:IsA("Model") and g.Name=="Lava Golem" then
            local h=g:FindFirstChildOfClass("Humanoid")
            local gp=g:FindFirstChild("HumanoidRootPart") or g:FindFirstChild("Head")
            if h and h.Parent==g and h.Health>0 and gp and gp:IsA("BasePart")
                and (gp.Position-actor.Position).Magnitude<=range
                and not state.Written[h] and os.clock()-(state.LastTry[h] or -math.huge)>=(tonumber(cfg.RetryGap) or 1.5) then
                state.LastTry[h]=os.clock()
                local before=h.Health
                local dist=(gp.Position-actor.Position).Magnitude
                local ok,err=pcall(function() h.Health=0 end)
                local after=h.Parent==g and h.Health or nil
                state.Writes+=1
                state.LastAt=os.clock()
                if ok and type(after)=="number" and after<=0 then
                    state.Written[h]=true
                    state.LocalZero+=1
                    wrote+=1
                    state.IslandMarkers[island]=true
                    state.LastMessage="LOCAL_HP_ZERO_UNVERIFIED"
                    logLine("GOLEM_LOCAL_HP_ZERO",string.format("before=%.0f after=%.0f distance=%.1f total=%d | CLIENT ONLY / SERVER KILL UNVERIFIED / REWARD UNVERIFIED",before,after,dist,state.LocalZero))
                else
                    state.Errors+=1
                    state.LastMessage="LOCAL_WRITE_FAILED: "..tostring(err or after)
                    logLine("GOLEM_LOCAL_HP_FAIL", "before="..tostring(before).." after="..tostring(after).." error="..tostring(err))
                end
            end
        end
    end
    return wrote>0,wrote
end
function PHX.golemLocalHpStatus()
    local s=PHX.GolemLocalHpState
    return {Enabled=CONFIG.GOLEM_LOCAL_KILL.Enabled,Writes=s.Writes,LocalZero=s.LocalZero,
        Errors=s.Errors,LastAt=s.LastAt,Message=s.LastMessage,
        Warning="CLIENT ONLY, server kill / Relic protection NOT VERIFIED"}
end

function PHX.setGolemLocalHpEnabled(enabled)
    CONFIG.GOLEM_LOCAL_KILL.Enabled=enabled==true
    PHX.GolemLocalHpState.LastMessage=enabled and "ENABLED_UNVERIFIED" or "DISABLED_USE_RECOVERY_NET"
    logLine("GOLEM_LOCAL_HP_TOGGLE",PHX.GolemLocalHpState.LastMessage)
    if PHX.saveUserConfig then PHX.saveUserConfig() end
    return true
end

function PHX.golemClusterBurst(island, token)
    local golems = PHX.liveGolems()
    if #golems == 0 then return true end
    local anchor = PHX.bringGolemCluster(island, golems)
    if not anchor then return false end
    local idx = teamIndex(LP.Name) or 1
    local angle = ((idx-1)/math.max(#CONFIG.TEAM,1))*math.pi*2
    local solo=PHX.isSoloAutomation and PHX.isSoloAutomation()
    local playerTarget = CFrame.new(anchor.Position+(solo and Vector3.new(0,CONFIG.GOLEM_AURA.HOVER_Y,0)
        or Vector3.new(math.cos(angle)*8, CONFIG.GOLEM_AURA.HOVER_Y, math.sin(angle)*8)))
    local rr = root()
    if not rr then return false end
    do
        local firstPart = golems[1]:FindFirstChild("HumanoidRootPart") or golems[1]:FindFirstChild("Head")
        if firstPart and (firstPart.Position-anchor.Position).Magnitude > CONFIG.GOLEM_AURA.NET_DISTANCE then
            playerTarget = CFrame.new(firstPart.Position+(solo and Vector3.new(0,CONFIG.GOLEM_AURA.HOVER_Y,0)
                or Vector3.new(math.cos(angle)*8, CONFIG.GOLEM_AURA.HOVER_Y, math.sin(angle)*8)))
        end
    end
    if (rr.Position-playerTarget.Position).Magnitude > CONFIG.GOLEM_AURA.APPROACH_DISTANCE and not safeTween(playerTarget,165,token) then return false end
    local deadline = os.clock()+CONFIG.GOLEM_AURA.BURST_SECONDS
    while isRunning(token) and island.Parent and PHX.eventActive(island) and os.clock() < deadline do
        golems = PHX.liveGolems()
        if #golems == 0 then
            if PHX.GolemLocalHpState.IslandMarkers[island] then
                noteProgress("GOLEM_LOCAL_CLEAR_UNVERIFIED")
                logLine("GOLEM_LOCAL_CLEAR_UNVERIFIED","no live golem visible on THIS CLIENT; server status unknown")
            else
                noteProgress("GOLEM_CLUSTER_CLEAR")
            end
            return true
        end
        PHX.bringGolemCluster(island,golems)
        local total, damaged = PHX.totalGolemHP(golems), false
        for _,g in ipairs(golems) do
            local h = g:FindFirstChildOfClass("Humanoid")
            local old = PHX.GolemDamage[g]
            if old and h and h.Health < old then damaged = true end
            if h then PHX.GolemDamage[g] = h.Health end
        end
        if damaged then PHX.ClusterProgressAt = os.clock() noteProgress("GOLEM_DAMAGE:"..math.floor(total)) end
        PHX.eventStatus(roleText().." | GOLEM FIRST: "..#golems.." | HP "..math.floor(total), "GOLEM")
        if CONFIG.GOLEM_LOCAL_KILL.Enabled then
            -- No Melee tool or NET packet required by the donor HP=0 experiment.
            PHX.golemLocalHpStep(golems,island,token)
        else
            equipTooltip("Melee")
            PHX.killAuraDispatch(golems,"NET")
        end
        if os.clock()-(PHX.ClusterProgressAt or os.clock()) >=
            (CONFIG.GOLEM_LOCAL_KILL.Enabled and 1.5 or CONFIG.GOLEM_AURA.STALL_SECONDS) then
            PHX.eventStatus(CONFIG.GOLEM_LOCAL_KILL.Enabled and "Golem HP=0 test: approach target" or "Golem stalled -> reposition + donor NET retry", "GOLEM_RECOVERY")
            local firstPart = golems[1] and (golems[1]:FindFirstChild("HumanoidRootPart") or golems[1]:FindFirstChild("Head"))
            local currentRoot = root()
            if firstPart and currentRoot and (currentRoot.Position-firstPart.Position).Magnitude > CONFIG.GOLEM_AURA.APPROACH_DISTANCE then
                if not safeTween(CFrame.new(firstPart.Position+Vector3.new(0,CONFIG.GOLEM_AURA.HOVER_Y,0)),165,token) then return false end
            end
            if firstPart then aimAt(firstPart.Position) end
            if CONFIG.GOLEM_LOCAL_KILL.Enabled then
                PHX.golemLocalHpStep(golems,island,token)
                logLine("GOLEM_LOCAL_RETRY", "TEAM | nearby HP=0 attempt; local effect only")
            else
                PHX.killAuraDispatch(golems,"NET")
                logLine("GOLEM_NET_RETRY", "TEAM | NET request sent; await HP delta")
            end
            PHX.ClusterProgressAt = os.clock()
            task.wait(.2)
        end
        task.wait(CONFIG.GOLEM_AURA.ATTACK_INTERVAL)
    end
    return #PHX.liveGolems() == 0
end

PHX.SoloGolemStallUntil = setmetatable({}, {__mode="k"})
PHX.SoloGolemProgress = setmetatable({}, {__mode="k"})
function PHX.soloGolemRushBurst(island, token)
    local golems = PHX.liveGolems()
    if #golems == 0 then return true end
    -- Bring before selecting/chasing a target, not only during TEAM bursts.
    if CONFIG.GOLEM_AURA.BRING_ENABLED then
        pcall(PHX.bringGolemCluster,island,golems)
    end

    local settings = CONFIG.SOLO_GUARD
    local relic = relicPart(getRelic(island))
    local refPos = relic and relic.Position or (root() and root().Position)
    local now = os.clock()
    table.sort(golems,function(a,b)
        local ap = a:FindFirstChild("HumanoidRootPart") or a:FindFirstChild("Head")
        local bp = b:FindFirstChild("HumanoidRootPart") or b:FindFirstChild("Head")
        local ad = ap and refPos and (ap.Position-refPos).Magnitude or math.huge
        local bd = bp and refPos and (bp.Position-refPos).Magnitude or math.huge
        if (PHX.SoloGolemStallUntil[a] or 0)>now and ad>settings.CRITICAL_GOLEM_RADIUS then ad+=settings.STALL_PRIORITY_PENALTY end
        if (PHX.SoloGolemStallUntil[b] or 0)>now and bd>settings.CRITICAL_GOLEM_RADIUS then bd+=settings.STALL_PRIORITY_PENALTY end
        return ad<bd
    end)
    local target=golems[1]
    local th=target and target:FindFirstChildOfClass("Humanoid")
    local gp=target and (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head"))
    if not gp or not th or th.Health<=0 then return false end

    PHX.eventStatus("SOLO GUARD | Rush closest Relic threat | Golems "..#golems,"GOLEM")
    local hover = gp.Position + Vector3.new(0,settings.GOLEM_HOVER_Y,0)
    local rr=root()
    if not rr then return false end
    if (rr.Position-hover).Magnitude > 3 then
        if not soloGuardApproach(gp.Position, settings.GOLEM_HOVER_Y, token,settings.GOLEM_BASE_TWEEN_SPEED,"GOLEM",island) then
            logLine("SOLO_GUARD_MOVE_FAIL", tostring(target.Name))
            return false
        end
    end

    local started=os.clock()
    local initial=th.Health
    local last=initial
    local state=PHX.SoloGolemProgress[target]
    if not state then
        state={LastHP=initial, LastDamageAt=started, LastFallbackAt=-math.huge}
        PHX.SoloGolemProgress[target]=state
    elseif initial<state.LastHP then
        state.LastDamageAt=started
        state.LastHP=initial
    elseif initial>state.LastHP then
        state.LastHP=initial
        state.LastDamageAt=started
    end
    local damageSeen=false
    local fallbackUsed=false
    local attackSent=0
    while isRunning(token) and island.Parent and PHX.eventActive(island)
        and target.Parent and th.Parent and th.Health>0
        and os.clock()-started < settings.BURST_SECONDS do
        rr=root()
        gp=target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
        if not rr or not gp then break end
        if CONFIG.GOLEM_AURA.BRING_ENABLED then
            -- Shared throttle prevents this burst racing the SOLO guard worker.
            PHX.bringGolemCluster(island,PHX.liveGolems())
        end
        local holdCF=CFrame.new(gp.Position+Vector3.new(0,settings.GOLEM_HOVER_Y,0))
        if (gp.Position-rr.Position).Magnitude>CONFIG.GOLEM_AURA.NET_DISTANCE then break end
        if (rr.Position-holdCF.Position).Magnitude>36 then
            if not soloGuardApproach(gp.Position,settings.GOLEM_HOVER_Y,token,settings.GOLEM_BASE_TWEEN_SPEED,"GOLEM",island) then break end
        end
        if PHX.maintainFarmHover then pcall(PHX.maintainFarmHover,holdCF) end
        local hits={target}
        for _,other in ipairs(PHX.liveGolems()) do if other~=target then hits[#hits+1]=other end end
        if CONFIG.GOLEM_LOCAL_KILL.Enabled then
            local _,count=PHX.golemLocalHpStep(hits,island,token)
            attackSent+=count
        else
            equipTooltip("Melee")
            if PHX.killAuraDispatch(hits,"NET") then attackSent+=1 end
        end
        task.wait(settings.ATTACK_INTERVAL)
        local hp=th.Health
        if hp < last or hp < state.LastHP then
            damageSeen=true
            state.LastDamageAt=os.clock()
            noteProgress((CONFIG.GOLEM_LOCAL_KILL.Enabled and "SOLO_GOLEM_CLIENT_HP_DROP_UNVERIFIED:" or "SOLO_GOLEM_HP_DROP:")..math.floor(hp))
            PHX.ClusterProgressAt=state.LastDamageAt
        end
        state.LastHP=hp
        last=hp
        if hp<=0 then break end
        if not damageSeen and not fallbackUsed
            and os.clock()-state.LastDamageAt>=settings.MELEE_FALLBACK_AFTER
            and os.clock()-state.LastFallbackAt>=settings.MELEE_FALLBACK_COOLDOWN then
            fallbackUsed=true
            state.LastFallbackAt=os.clock()
            aimAt(gp.Position)
            if CONFIG.GOLEM_LOCAL_KILL.Enabled then
                local attempted,count=PHX.golemLocalHpStep(hits,island,token)
                logLine("SOLO_LOCAL_HP_RETRY", "localWrites="..tostring(count).." | attempted="..tostring(attempted))
            else
                local sentNative=PHX.killAuraDispatch(hits,"NET")
                logLine("SOLO_NET_RETRY","donor NET stall retry | sent="..tostring(sentNative).." | stalled="..
                    string.format("%.1f",os.clock()-state.LastDamageAt).."s")
            end
        end
    end
    if PHX.stopFarmHover then PHX.stopFarmHover() end
    local final=th.Health
    local dead=not target.Parent or not th.Parent or final<=0
    if dead then
        PHX.SoloGolemStallUntil[target]=nil
        PHX.SoloGolemProgress[target]=nil
        if PHX.GolemLocalHpState.Written[th] then
            noteProgress("SOLO_GOLEM_LOCAL_HP_ZERO_UNVERIFIED")
            logLine("SOLO_GUARD","LOCAL HP=0 ONLY | server kill UNVERIFIED | localWrites="..attackSent)
        else
            noteProgress("SOLO_GOLEM_KILL_CONFIRMED")
            logLine("SOLO_GUARD","KILL_CONFIRMED_BY_LOCAL_STATE | netRequests="..attackSent)
        end
        return true
    end
    if damageSeen or final<initial then
        PHX.SoloGolemStallUntil[target]=nil
        logLine("SOLO_GUARD","HP_DROP "..math.floor(initial).." -> "..math.floor(final).." | attacks="..attackSent)
    else
        PHX.SoloGolemStallUntil[target]=os.clock()+settings.TARGET_STALL_COOLDOWN
        logLine("SOLO_GUARD_NO_DAMAGE","unverified | attacks="..attackSent.." | fallback="..tostring(fallbackUsed))
    end
    return false
end

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
            if PHX.PostRespawnStashPending then task.wait(.15); continue end
            local snapshot = PHX.eventSnapshot(island)
            if snapshot.Active then sawActive = true missingSince = nil else missingSince = missingSince or os.clock() end
            if sawActive and PHX.raidFinishAfterHudLoss(missingSince) then
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
            local golems=PHX.liveGolems()
            local pressureDuty, reason=PHX.teamPressureAssignment(island,snapshot,golems)
            if pressureDuty then
                local target,count=PHX.pickPressureRock(island,teamIndex(LP.Name) or 1)
                if target then
                    PHX.eventStatus(roleText().." | PRESSURE HELP "..tostring(snapshot.Pressure or "?").."% | Rocks "..count.." | "..reason,"PRESSURE")
                    PHX.pressureRockBurst(target,token,island)
                elseif #golems>0 then
                    PHX.golemClusterBurst(island,token)
                else
                    task.wait(.1)
                end
            elseif #golems>0 then
                PHX.golemClusterBurst(island,token)
            else
                task.wait(.1)
            end
        end
    end)
    disableLavaProtection()
    PHX.restoreGolemChanges()
    if not ok then error(err,0) end
    return completed
end

PHX.SoloRelicGuardAudit = setmetatable({}, {__mode="k"})
PHX.SoloAbsolutePriorityState = setmetatable({}, {__mode="k"})
function PHX.soloDonorEventLoop(island, token)
    enableLavaProtection(island)
    local seenActive=false
    local missingSince=nil
    local completed=false
    local ok,err=pcall(function()
        while isRunning(token) and island.Parent do
            -- Keep Golem defense responsive even if a post-respawn Stash read
            -- is still pending. The existing alive/respawn guard runs below.
            if PHX.PostRespawnStashPending and #PHX.liveGolems()==0 then
                task.wait(.15)
                continue
            end
            PHX.RaidHUDCache=nil
            local snapshot=PHX.eventSnapshot(island)
            if snapshot.Active then seenActive=true;missingSince=nil
            else missingSince=missingSince or os.clock() end
            if seenActive and PHX.raidFinishAfterHudLoss(missingSince) then
                completed=true
                PHX.EventFinishedIslands[island]=true
                break
            end
            if not snapshot.Active then task.wait(.12);continue end
            if type(snapshot.Relic)=="number" then
                local previous=PHX.SoloRelicGuardAudit[island]
                if previous and snapshot.Relic < previous then
                    logLine("SOLO_RELIC_HP_DROP", string.format("%.1f -> %.1f | golems=%d | pressure=%s",
                        previous, snapshot.Relic, snapshot.GolemCount or 0,tostring(snapshot.Pressure or "?")))
                end
                PHX.SoloRelicGuardAudit[island]=snapshot.Relic
            end
            local hh=hum()
            if not hh or hh.Health<=0 or not root() then
                waitAlive(token)
                if not isRunning(token) or not island.Parent then break end
                continue
            end
            -- V2.17.03 strict SOLO scheduler: Golem > Rock, with NO pressure
            -- override (even at critical pressure or when Golems are distant).
            local golems=PHX.liveGolems()
            local golemPresent=#golems>0
            if PHX.SoloAbsolutePriorityState[island] ~= golemPresent then
                PHX.SoloAbsolutePriorityState[island]=golemPresent
                logLine("SOLO_GOLEM_FIRST",golemPresent and
                    ("ENGAGE | live="..tostring(#golems)) or "CLEAR | RESUME_PRESSURE")
            end
            if golemPresent then
                local _,distance=PHX.soloRelicGolemThreat(island,golems)
                PHX.eventStatus("SOLO GOLEM FIRST | Golems "..#golems..
                    " | Relic distance "..math.floor(distance)..
                    " | HP "..math.floor(PHX.totalGolemHP(golems)),"GOLEM")
                PHX.soloGolemRushBurst(island,token)
            else
                local rock,count=PHX.pickPressureRock(island,1)
                if rock then
                    local pressure=tonumber(snapshot.Pressure)
                    PHX.eventStatus("SOLO PRESSURE | "..tostring(pressure or "?").."% | Rocks "..count,"PRESSURE")
                    PHX.pressureRockBurst(rock,token,island)
                else
                    task.wait(.08)
                end
            end
        end
    end)
    disableLavaProtection()
    PHX.restoreGolemChanges()
    if not ok then error(err,0) end
    return completed
end

local function masterPressureLoop(island, token)
    if PHX.isSoloAutomation() then return PHX.soloDonorEventLoop(island,token) end
    return PHX.teamEventLoop(island,token)
end

local function slaveGolemLoop(island, token)
    return PHX.teamEventLoop(island,token)
end

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
    progress.BonesVerified = true
    return true
end

function PHX.dragonVariantFromText(value)
    local s = string.lower(tostring(value or ""))
    if s:find("east",1,true) then return "East" end
    if s:find("west",1,true) then return "West" end
    return nil
end

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

ENV.__PH_DRAGON_RECEIPT_NOTIFIED = ENV.__PH_DRAGON_RECEIPT_NOTIFIED or setmetatable({}, {__mode="k"})
PHX.DragonNotified = ENV.__PH_DRAGON_RECEIPT_NOTIFIED
function PHX.notifyDragonFruit(tool)
    if not PHX.isDragonFruitTool(tool) or PHX.DragonNotified[tool] then return false end
    PHX.DragonNotified[tool] = true
    local variant = PHX.dragonVariantFromTool(tool)
    local label = variant and ("Dragon ("..variant..")") or "Dragon Fruit"
    if PHX.recordPhysicalFruitReceipt then
        PHX.recordPhysicalFruitReceipt(tool)
    else
        local state=PHX.FruitAutoState
        if state then
            state.ReceiptSerial=(state.ReceiptSerial or 0)+1
            state.LastReceipt={Tool=tool,Name=tool.Name,Kind="Dragon",At=os.clock()}
        end
    end
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
        DRAGON_GUARD_STATE.Pending = pending
        DRAGON_GUARD_STATE.Critical = true
        DRAGON_GUARD_STATE.Unconfirmed = tool
    end
    pending.Label = pending.Label or "Dragon Fruit"
    if os.clock()<(tonumber(pending.RetryAt) or 0) then
        setStatus("Dragon storage full -> fruit kept; reset/portal blocked during retry wait")
        return false
    end
    local runtime=PHX.Runtime
    local ownsStart=runtime and runtime.StartBusy and PHX.ownsStartPreparation()
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (runtime and (runtime.InteractionHold or (runtime.StartBusy and not ownsStart))) then return false end
    local guiOwner=PHX.Runtime and PHX.acquireLock(PHX.Runtime,"FruitGuiBusy","FruitGuiBusy") or nil
    if PHX.Runtime and not guiOwner then return false end
    local function requestAndVerify()
        local function storageFullReply()
            if not PHX.dismissFruitStorageFull then return false end
            local _,reason=PHX.dismissFruitStorageFull(tool,true)
            if not reason then return false end
            pending.StorageFull=true
            pending.RetryAt=os.clock()+math.max(30,PHX.fruitRetryDelay and PHX.fruitRetryDelay(1) or 5)
            DRAGON_GUARD_STATE.Critical=true
            PHX.pauseEvent("DRAGON_STORAGE_FULL", "Dragon storage full -> Nevermind; fruit retained and reset/portal blocked")
            logLine("DRAGON_STORE_FULL",tostring(reason).."; original baseline retained")
            return true
        end
        if storageFullReply() then return false end
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
            local verifySeconds=CONFIG.FRUIT_AUTO and tonumber(CONFIG.FRUIT_AUTO.StoreVerifySeconds) or 2
            local deadline=os.clock()+math.max(.5,verifySeconds or 2)
            repeat
                task.wait(math.max(.05,math.min(.25,tonumber(CONFIG.DRAGON_GUARD.RETRY_DELAY) or .25)))
                if not PHX.generationAlive() then return false end
                if PHX.reconcileDragonPending() then return true end
                if storageFullReply() then return false end
            until os.clock()>=deadline
            logLine("DRAGON_STORE", "attempt="..attempt.." pcall="..tostring(ok).." result="..tostring(result).." stillLocal="..tostring(PHX.dragonToolIsLocal(tool)))
        end
        if not PHX.generationAlive() then return false end
        DRAGON_GUARD_STATE.Critical = true
        PHX.pauseEvent("DRAGON_STORE_UNCONFIRMED", "Dragon storage not confirmed -> paused; reset/portal blocked")
        logLine("DRAGON_STORE_FAIL", "original fresh stored inventory baseline unavailable or unchanged")
        return false
    end
    local ok,result=pcall(requestAndVerify)
    if guiOwner then PHX.releaseLock(guiOwner) end
    if not ok then
        DRAGON_GUARD_STATE.Critical=true
        PHX.pauseEvent("DRAGON_GUARD_ERROR", "Dragon guard error -> paused; reset/portal blocked")
        logLine("DRAGON_GUARD_ERROR",tostring(result))
        return false
    end
    return result
end

local function storeDragonFruitCritical()
    if not PHX.generationAlive() then return false end
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
    local solo=PHX.isSoloAutomation and PHX.isSoloAutomation()
    if solo then PHX.SoloEggRosters=PHX.SoloEggRosters or setmetatable({}, {__mode="k"}) end
    local rosters=solo and PHX.SoloEggRosters or PHX.EggRosters
    local existing = rosters[island]
    if existing then PHX.captureEggRoster(existing) return existing end
    local core = island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("SpawnedDragonEggs")
    local alreadySpawned = folder and #folder:GetChildren() > 0
    local state = {Island=island, Folder=folder, Entries={}, Connections={},Solo=solo==true}
    if alreadySpawned and not solo then
        state.Ambiguous = "Observer started after eggs spawned; earlier pickups cannot be reconstructed"
    end
    rosters[island] = state
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
    for i=2,#entries do
        local a,b = entries[i-1].Position,entries[i].Position
        if not state.Solo and a.X == b.X and a.Y == b.Y and a.Z == b.Z then
            state.Ambiguous = "Two eggs share the same position; stable assignment is unavailable"
            return nil,state.Ambiguous
        end
    end
    state.Frozen = {}
    for _,entry in ipairs(entries) do state.Frozen[#state.Frozen+1] = entry.Egg end
    return state.Frozen
end

function PHX.readEggCount()
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

function PHX.soloEggRank(eggs,progress)
    if progress.SoloEgg then
        for index,egg in ipairs(eggs) do if egg==progress.SoloEgg then return index end end
        return nil
    end
    local rr=root()
    if not rr then return nil end
    local rank,distance=nil,math.huge
    for index,egg in ipairs(eggs) do
        local part=egg.Parent and interactionPart(egg)
        if part then
            local current=(part.Position-rr.Position).Magnitude
            if current<distance then rank,distance=index,current end
        end
    end
    if rank then progress.SoloEgg=eggs[rank] end
    return rank
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
    local ti,crewSize=PHX.rewardCrewIndex(island,LP.Name)
    if not ti then
        PHX.EventState.Egg="NO SLOT"
        setStatus("Không có slot trứng: chưa có tên trong đội đã lên thuyền của chuyến này")
        progress.Egg,progress.EggState=true,"NO SLOT"
        return true
    end
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
        local rotate = math.abs(math.floor(island:GetPivot().Position.X)) % crewSize
        local rank = ((ti+rotate-1)%crewSize)+1
        if PHX.isSoloAutomation and PHX.isSoloAutomation() then
            rank=PHX.soloEggRank(eggs,progress)
            if not rank then
                PHX.pauseEvent("SOLO_EGG_UNAVAILABLE","Solo: không tìm thấy trứng đã chọn; giữ xác nhận cũ")
                return false
            end
        end
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

function PHX.dismissDragonHunterFinalBubble()
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
    if not isRunning(token) then return false end
    local rf=PHX.dragonHunterRemote()
    if not isRunning(token) then return false end
    if not rf then setStatus("RF/DragonHunter missing"); return false end
    if not safeTween(CONFIG.DRAGON_HUNTER.STAND,200,token) then return false end
    task.wait(.25)
    if not isRunning(token) then return false end

    local okCheck,checked=pcall(function() return rf:InvokeServer({Context="Check"}) end)
    if not isRunning(token) then return false end
    local text=okCheck and PHX.questTextFromValue(checked) or ""
    if text ~= "" then return PHX.latchQuest(text,"EXISTING QUEST") end

    local okRequest,response=pcall(function() return rf:InvokeServer({Context="RequestQuest"}) end)
    if not isRunning(token) then return false end
    text=okRequest and PHX.questTextFromValue(response) or ""
    if text == "" then
        task.wait(.35)
        if not isRunning(token) then return false end
        local okDelayed,delayed=pcall(function() return rf:InvokeServer({Context="Check"}) end)
        if not isRunning(token) then return false end
        text=okDelayed and PHX.questTextFromValue(delayed) or ""
    end
    if text == "" then setStatus("Dragon Hunter did not return a Hunt quest"); return false end
    return PHX.latchQuest(text,"ACCEPTED QUEST")
end

PHX._HydraTreeCache = PHX._HydraTreeCache or {At=-math.huge, List={}}
PHX._HydraTreeLastHit = PHX._HydraTreeLastHit or setmetatable({}, {__mode="k"})

function PHX.hydraTreePart(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if not obj:IsA("Model") then return nil end

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
    if PHX.isMovementLocked() then return function() end end
    local rr=root()
    if not rr then return function() end end
    local body=Instance.new("BodyPosition")
    body.Name="PH_TreeHover"
    body.MaxForce=Vector3.new(1e9,1e9,1e9)
    body.P,body.D=32000,1800
    body.Position=targetCF.Position
    body.Parent=rr
    PHX.Runtime.MovementObjects[body]=true
    local active=true
    local connection
    local function stop()
        active=false
        if connection then PHX.disconnect(connection);connection=nil end
        PHX.Runtime.MovementObjects[body]=nil
        if body and body.Parent then body:Destroy() end
        if rr and rr.Parent then rr.AssemblyLinearVelocity=Vector3.zero; rr.AssemblyAngularVelocity=Vector3.zero end
    end
    connection=PHX.connect(RunService.Heartbeat, function()
        if not active or PHX.isMovementLocked() or not isRunning(token) or rr ~= root() or not rr.Parent or not hum() or hum().Health<=0
            or (rr.Position-targetCF.Position).Magnitude>18 then stop(); return end
        body.Position=targetCF.Position
        rr.AssemblyLinearVelocity=Vector3.zero
        rr.AssemblyAngularVelocity=Vector3.zero
    end)
    PHX.Runtime.MovementConnections[connection]=true
    return stop
end

function PHX.treeSkillsNoViewLock(token)
    for index,tooltip in ipairs({"Melee","Blox Fruit"}) do
        if not isRunning(token) then return false end
        if equipTooltip(tooltip) then
            task.wait(.12)
            for _=1,2 do
                for _,key in ipairs(skillKeysForTooltip(tooltip)) do
                    if not isRunning(token) or not hum() or hum().Health<=0 then return false end
                    pressKey(key,.10)
                    task.wait(.16)
                end
                task.wait(.05)
            end
        end
        if index == 1 then task.wait(.08) end
    end
    return true
end

local function farmTreeQuest(token)
    local i=1
    local started=PHX.LastQuestAcceptedAt
    if not started or started == -math.huge then started=os.clock() end
    while isRunning(token) and not PHX.questCompleteSince(started) do
        if not waitAlive(token) then return false end
        -- The three saved CFrames are safe standing positions; use their exact coordinates.
        local hover=CONFIG.TREES[i]
        setStatus("QUEST TREE | saved point "..i.."/"..#CONFIG.TREES.." | Melee XC + Fruit ZCVF")
        if not safeTween(hover,180,token) then return false end
        local stopHover=PHX.startTreeHover(hover,token)
        local ok,result=xpcall(function()
            task.wait(.10)
            local cast=PHX.treeSkillsNoViewLock(token)
            task.wait(.08)
            return cast
        end,function(err) return tostring(err) end)
        stopHover()
        if not ok then logLine("TREE_ERROR",result); return false end
        if not result or not isRunning(token) then return false end
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
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    return net and (net:FindFirstChild("RE/DragonDojoEmber") or net:FindFirstChild("RE/DragonDojoEmber", true))
end

function PHX.findBlazeParts()
    local out, seen = {}, {}
    local function addPart(p)
        if p and p:IsA("BasePart") and not seen[p] then
            local fp = string.lower(p:GetFullName())
            if not fp:find("azure",1,true) and not fp:find("kitsune",1,true) then
                seen[p] = true
                out[#out+1] = p
            end
        end
    end

    for _,obj in ipairs(workspace:GetChildren()) do
        local l = string.lower(obj.Name)
        if l:find("blaze",1,true) or l:find("ember",1,true) or l == "fireflowers" then
            if obj:IsA("BasePart") then
                addPart(obj)
            else
                for _,d in ipairs(obj:GetDescendants()) do
                    local name=string.lower(d.Name)
                    if d:IsA("BasePart") and (name:find("ember",1,true) or name:find("fire",1,true) or l:find("blaze",1,true)) then
                        addPart(d)
                    end
                end
            end
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
        if not isRunning(token) then break end
        if not p.Parent then continue end
        local rr = root()
        if not rr then break end
        local d = (p.Position - rr.Position).Magnitude
        if firetouchinterest and d <= 250 then
            pcall(function()
                firetouchinterest(rr, p, 0)
                firetouchinterest(rr, p, 1)
            end)
            count = count + 1
        elseif allowTween and d <= 3000 then
            if not safeTween(p.CFrame * CFrame.new(0,1.5,0), 850, token) or not isRunning(token) then break end
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
            task.wait(.05)
        end
    elseif kind == "VENOM" then
        while isRunning(token) and not PHX.questCompleteSince(questStartedAt) do
            setStatus(PHX.questStatusText().." | Ember "..tostring(inventoryCount("Blaze Ember")).."/15 | wait Quest Completed popup")
            farmNamedMob("Venomous Assailant", CONFIG.MOB_CAMPS.VenomousAssailant, token)
            PHX.pulseBlazeCollectRemote()
            PHX.touchVisibleBlaze(token, false)
            task.wait(.05)
        end
    end

    local completed = PHX.questCompleteSince(questStartedAt)
    logLine("QUEST", "popup-complete="..tostring(completed).." | previous="..kind.." | text="..tostring(PHX.QuestCompletedText))
    return completed
end

function PHX.collectBlazeEmberDrops(token, seconds)
    local before = inventoryCount("Blaze Ember", true)
    local maxUntil = os.clock() + (seconds or 2.2)
    setStatus("Quest complete -> collecting Blaze Embers")

    while isRunning(token) and os.clock() < maxUntil do
        PHX.pulseBlazeCollectRemote()
        PHX.touchVisibleBlaze(token, true)
        task.wait(.04)
    end

    local after = inventoryCount("Blaze Ember", true)
    logLine("BLAZE_COLLECT", "before="..tostring(before).." after="..tostring(after).." collectWindow="..tostring(seconds or 2.2))
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
                    task.wait(.8)
                    kind = "NONE"
                else
                    kind = questKind()
                    if kind == "NONE" then
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
                        task.wait(.08)
                    end
                end)

                local completed = farmHunterQuest(token)
                collectorAlive = false

                if completed and isRunning(token) then
                    PHX.collectBlazeEmberDrops(token, 2.2)
                    local after = inventoryCount("Blaze Ember", true)
                    setStatus("Quest Completed popup confirmed | Blaze Ember "..tostring(after).."/15")
                    logLine("QUEST", "cycle done | emberBefore="..tostring(before).." emberAfter="..tostring(after))
                    if after < 15 then
                        task.wait(.12)
                    end
                elseif isRunning(token) then
                    setStatus("Quest popup not detected -> stay on current quest")
                    task.wait(.3)
                end
            end
        end
    end
    return inventoryCount("Blaze Ember", true) >= 15
end

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

    if FOREST_DAMAGE_PROVEN
        and ACTIVE_FOREST_MAGNET.Locked[m]
        and t.attacks >= CONFIG.FOREST_GHOST_MIN_ATTACKS
        and (now - t.lastDamageAt) >= CONFIG.FOREST_GHOST_TIMEOUT then
        FOREST_GHOST_BLACKLIST[m] = true
        ACTIVE_FOREST_MAGNET.Locked[m] = nil
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

local function hardLockForestMob(m,anchorCF)
    if isForestGhost(m) then return false end
    local h,rr=forestHumRoot(m)
    if not h or not rr then return false end
    if networkOwned(rr)==false then return false end
    local rp=root()
    if not rp or (rp.Position-rr.Position).Magnitude>CONFIG.FARM_COMBAT.BringRadius then return false end
    local ok=pcall(function()
        if (rr.Position-anchorCF.Position).Magnitude>5 then m:PivotTo(anchorCF) end
        rr.Size=Vector3.new(CONFIG.FARM_COMBAT.BringSize,CONFIG.FARM_COMBAT.BringSize,CONFIG.FARM_COMBAT.BringSize)
        rr.CanCollide=false
    end)
    return ok
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

local FOREST_LAST_MAINTAIN=0
local function maintainForestMagnet()
    if not ACTIVE_FOREST_MAGNET.Enabled or not ACTIVE_FOREST_MAGNET.Anchor then return end
    if os.clock()-FOREST_LAST_MAINTAIN<CONFIG.FARM_COMBAT.BringInterval then return end
    FOREST_LAST_MAINTAIN=os.clock()
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return end
    local anchorCF = ACTIVE_FOREST_MAGNET.Anchor
    local radius = ACTIVE_FOREST_MAGNET.Radius

    for m in pairs(ACTIVE_FOREST_MAGNET.Locked) do
        if not m.Parent or isForestGhost(m) then
            ACTIVE_FOREST_MAGNET.Locked[m] = nil
        else
            hardLockForestMob(m,anchorCF)
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
                    if hardLockForestMob(m,anchorCF) then ACTIVE_FOREST_MAGNET.Locked[m]=true end
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
        if obj then PHX.Runtime.MovementObjects[obj]=nil end
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
    if PHX.isMovementLocked() then return false end
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
    ap.MaxForce=7000000
    ap.MaxVelocity=45
    ap.Responsiveness=55
    ap.RigidityEnabled=false
    ap.Parent=rr
    PHX.Runtime.MovementObjects[att]=true
    PHX.Runtime.MovementObjects[ap]=true
    ACTIVE_HOVER.Root,ACTIVE_HOVER.Humanoid,ACTIVE_HOVER.Attachment=rr,h,att
    ACTIVE_HOVER.Position,ACTIVE_HOVER.Gyro,ACTIVE_HOVER.Target=ap,nil,targetCF
    return true
end

local function maintainStableHover(targetCF)
    if PHX.isMovementLocked() then stopStableHover();return false end
    local rr=root()
    if not rr or not hum() or hum().Health<=0 or hum().SeatPart then stopStableHover(); return false end
    if (rr.Position-targetCF.Position).Magnitude>18 then stopStableHover(); return false end
    if ACTIVE_HOVER.Root ~= rr or not ACTIVE_HOVER.Position or not ACTIVE_HOVER.Position.Parent then return startStableHover(targetCF) end
    ACTIVE_HOVER.Target=targetCF
    ACTIVE_HOVER.Position.Position=targetCF.Position
    return true
end

PHX.startFarmHover=startStableHover
PHX.maintainFarmHover=maintainStableHover
PHX.stopFarmHover=stopStableHover

local function magnetForestPirates(anchorCF, radius)
    setForestMagnet(true, anchorCF, radius)
    boostSimulationRadius()
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return 0 end

    for _,m in ipairs(enemies:GetChildren()) do
        if isForestPirate(m) and not isForestGhost(m) then
            local h, rr = forestHumRoot(m)
            if h and rr and (rr.Position - anchorCF.Position).Magnitude <= radius then
                if hardLockForestMob(m,anchorCF) then ACTIVE_FOREST_MAGNET.Locked[m]=true end
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
    if not goTurtle(token) then return false end
    local camp=CONFIG.MOB_CAMPS.ForestPirate
    while isRunning(token) do
        local scrap=PHX.cachedMaterialCount("Scrap Metal")
        if scrap==nil then setStatus("Scrap baseline unknown; farm paused"); return false end
        if scrap>=10 then setStatus("Scrap Metal ready: "..scrap.."/10"); return true end
        if not waitAlive(token) then return false end
        if getRegion()~="TURTLE" and not goTurtle(token) then return false end
        setStatus("Scrap Metal "..scrap.."/10 | Forest Pirate bring wave")
        PHX.farmMobWave("Forest Pirate",camp,token,function()
            local count=PHX.cachedMaterialCount("Scrap Metal")
            return count~=nil and count>=10
        end)
        task.wait(.35)
    end
    PHX.stopFarmHover()
    return false
end

function PHX.craftWindow()
    local craft=PG:FindFirstChild("Craft")
    if not craft or not PHX.guiVisible(craft) then return nil end
    local window=craft:FindFirstChild("Window")
    if window and PHX.guiVisible(window) then return window end
    return nil
end

local function craftAt(base, ...)
    local node=base
    for _,name in ipairs({...}) do
        node=node and node:FindFirstChild(name)
        if not node then return nil end
    end
    return node
end

function PHX.craftWindowRecipe(window)
    if not window or not PHX.guiVisible(window) then return nil,"WINDOW_NOT_VISIBLE" end
    local itemName=craftAt(window,"Main","Crafting","Main","Result","AssetTile",
        "ResultAsset","Filled","ItemInformation","ItemName")
    if not itemName then
        logLine("CRAFT_PROBE","Output ItemName path missing; safe abort")
        return nil,"OUTPUT_ITEMNAME_PATH_MISSING"
    end
    local texts={}
    local function addText(obj)
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and PHX.guiVisible(obj) then
            local compact=PHX.compactText(obj.Text)
            if compact~="" then texts[#texts+1]=compact end
        end
    end
    addText(itemName)
    for _,desc in ipairs(itemName:GetDescendants()) do addText(desc) end
    logLine("CRAFT_OUTPUT_SCAN", "result="..table.concat(texts,"|").." path="..itemName:GetFullName())
    for _,text in ipairs(texts) do
        if text=="dragonheart" or text=="dragonstorm" then
            return nil,"WRONG_OUTPUT_RECIPE:"..text
        end
    end
    for _,text in ipairs(texts) do
        if text=="volcanicmagnet" then
            return "volcanicmagnet","PROBE_EXACT_RESULT_ITEMNAME"
        end
    end
    return nil,"OUTPUT_ITEMNAME_NOT_MAGNET"
end

function PHX.craftConfirmButton(window)
    if not window or not PHX.guiVisible(window) then return nil,"WINDOW_NOT_VISIBLE" end
    local button=craftAt(window,"Info","Confirm")
    if not button or not button:IsA("TextButton") or not PHX.guiVisible(button) then
        return nil,"PROBE_CONFIRM_PATH_MISSING"
    end
    local active,interactable=button.Active,true
    pcall(function() interactable=button.Interactable end)
    if not active or not interactable or button.AbsoluteSize.X<=0 or button.AbsoluteSize.Y<=0 then
        return nil,"PROBE_CONFIRM_INACTIVE"
    end
    local child=button:FindFirstChild("TextLabel")
    if not child or PHX.compactText(child.Text)~="craft" then
        return nil,"PROBE_CONFIRM_LABEL_NOT_CRAFT"
    end
    return button,"PROBE_INFO_CONFIRM_ACTIVATED"
end

function PHX.craftActivateV19Once(button)
    if not button or not PHX.guiVisible(button) then return false,"BUTTON_NOT_VISIBLE" end
    local active,interactable=button.Active,true
    pcall(function() interactable=button.Interactable end)
    if not active or not interactable then return false,"BUTTON_NOT_INTERACTABLE" end
    local p,z=button.AbsolutePosition,button.AbsoluteSize
    if z.X<=0 or z.Y<=0 then return false,"BUTTON_SIZE_INVALID" end
    local center=Vector2.new(p.X+z.X/2,p.Y+z.Y/2)
    local gui=button:FindFirstAncestorWhichIsA("ScreenGui")
    local inset=select(1,game:GetService("GuiService"):GetGuiInset())
    local inputPoint=center+((gui and gui.IgnoreGuiInset) and Vector2.zero or inset)
    logLine("CRAFT_CLICK_POINT",string.format("center=%.0f,%.0f input=%.0f,%.0f inset=%.0f,%.0f",center.X,center.Y,inputPoint.X,inputPoint.Y,inset.X,inset.Y))
    local ok,dispatched=pcall(PHX.inputClick,button)
    if ok and dispatched==true then
        return true,"ONE_PHYSICAL_GUI_CLICK"
    end
    logLine("CRAFT_CLICK_BACKEND_WARN","Native pointer dispatch failed; attempting ONE Activated fallback")
    if type(getconnections)=="function" then
        local got,connections=pcall(function() return getconnections(button.Activated) end)
        if got and type(connections)=="table" then
            local enabled={}
            for _,connection in ipairs(connections) do
                local allowed=true
                pcall(function() allowed=connection.Enabled~=false and connection.Connected~=false end)
                if allowed then enabled[#enabled+1]=connection end
            end
            if #enabled==1 then
                local c=enabled[1]
                if type(c.Fire)=="function" then
                    local fired=pcall(function() c:Fire() end)
                    if fired then return true,"ACTIVATED_FALLBACK_CONNECTION_FIRE" end
                elseif type(c.Function)=="function" then
                    local fired=pcall(function() c.Function() end)
                    if fired then return true,"ACTIVATED_FALLBACK_CONNECTION_FUNCTION" end
                end
            end
        end
    end
    if type(firesignal)=="function" then
        local fired=pcall(function() firesignal(button.Activated) end)
        if fired then return true,"ACTIVATED_FALLBACK_FIRESIGNAL" end
    end
    return false,"NO_GUI_CLICK_BACKEND"
end

function PHX.logCraftWindowProof(window,why)
    local snippets={}
    for _,o in ipairs(window and window:GetDescendants() or {}) do
        if #snippets>=12 then break end
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.guiVisible(o) then
            local txt=tostring(o.Text or ""):gsub("%s+"," ")
            if txt~="" and #txt<=60 then snippets[#snippets+1]=o.Name.."="..txt end
        end
    end
    logLine("CRAFT_DIAG",tostring(why).." | labels="..table.concat(snippets,"; "))
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

function PHX.craftV19Visible(obj)
    if not obj or not obj:IsA("GuiObject") or not obj.Visible then return false end
    local p=obj.Parent
    while p and p~=PG do
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end

function PHX.craftV19DialogueButtons()
    local dg=PG:FindFirstChild("DialogueGui")
    if not dg then return {} end
    local found={}
    for _,o in ipairs(dg:GetDescendants()) do
        if (o:IsA("TextButton") or o:IsA("ImageButton")) and PHX.craftV19Visible(o)
            and o.AbsoluteSize.X>120 and o.AbsoluteSize.Y>25 then
            found[#found+1]=o
        end
    end
    table.sort(found,function(a,b)
        local ay,by=a.AbsolutePosition.Y,b.AbsolutePosition.Y
        if math.abs(ay-by)<=2 then return a.AbsolutePosition.X<b.AbsolutePosition.X end
        return ay<by
    end)
    local out,lastY={},nil
    for _,button in ipairs(found) do
        local y=math.floor(button.AbsolutePosition.Y+.5)
        if lastY==nil or math.abs(y-lastY)>5 then
            out[#out+1]=button;lastY=y
        end
    end
    return out
end

function PHX.craftV19VisualText(btn)
    if not btn then return "" end
    local glyphs={}
    if btn:IsA("TextButton") and tostring(btn.Text or "")~="" then
        glyphs[#glyphs+1]={x=btn.AbsolutePosition.X,y=btn.AbsolutePosition.Y,text=tostring(btn.Text)}
    end
    for _,obj in ipairs(btn:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and PHX.craftV19Visible(obj) then
            local txt=tostring(obj.Text or "")
            if txt~="" and #txt<=20 then
                local p=obj.AbsolutePosition
                glyphs[#glyphs+1]={x=p.X,y=p.Y,text=txt}
            end
        end
    end
    table.sort(glyphs,function(a,b)
        if math.abs(a.y-b.y)<=3 then return a.x<b.x end
        return a.y<b.y
    end)
    local out,seen={},{}
    for _,g in ipairs(glyphs) do
        local k=math.floor(g.x+.5)..":"..math.floor(g.y+.5)..":"..g.text
        if not seen[k] then seen[k]=true;out[#out+1]=g.text end
    end
    return table.concat(out,"")
end

function PHX.craftV19FindOption(buttons,wanted)
    local target=PHX.compactText(wanted)
    for i,button in ipairs(buttons or {}) do
        local txt=PHX.craftV19VisualText(button)
        local compact=PHX.compactText(txt)
        if compact==target or compact:find(target,1,true) then return button,i,txt end
    end
    return nil,nil,nil
end

function PHX.craftV19Transition(previous,minimum,timeout,token)
    local oldFirst=previous and previous[1] or nil
    local deadline=os.clock()+(timeout or 1.8)
    repeat
        if not isRunning(token) then return {} end
        if PHX.craftWindow() then return {} end
        local current=PHX.craftV19DialogueButtons()
        if #current>=(minimum or 1) and
            (not oldFirst or current[1]~=oldFirst or #current~=#(previous or {})) then
            return current
        end
        task.wait(.04)
    until os.clock()>=deadline
    return PHX.craftV19DialogueButtons()
end

function PHX.craftV19FireButton(button)
    if not button then return false,"NO_BUTTON" end
    if type(getconnections)=="function" then
        local ok,connections=pcall(function() return getconnections(button.Activated) end)
        if ok and type(connections)=="table" and #connections>0 then
            for _,connection in ipairs(connections) do
                if connection.Fire then
                    local fired=pcall(function() connection:Fire() end)
                    if fired then task.wait(.10);return true,"Activated/getconnections" end
                elseif connection.Function then
                    local fired=pcall(function() connection.Function() end)
                    if fired then task.wait(.10);return true,"Activated/function" end
                end
            end
        end
    end
    if type(firesignal)=="function" then
        local ok=pcall(function() firesignal(button.Activated) end)
        if ok then task.wait(.10);return true,"Activated/firesignal" end
    end
    local ok,attempted=pcall(PHX.inputClick,button)
    if ok and attempted==true then return true,"vim+inset" end
    return false,"NO_GUI_BACKEND"
end

function PHX.craftV19DragonHunterVisible()
    local dg=PG:FindFirstChild("DialogueGui")
    if not dg then return false end
    for _,o in ipairs(dg:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and PHX.craftV19Visible(o) then
            local text=PHX.normalizeItemName(o.Text)
            if text=="dragon hunter" or text:find("dragon hunter",1,true) then return true end
        end
    end
    return false
end

function PHX.craftV19ClickDragonHunter(token)
    if not highTween(CONFIG.DRAGON_HUNTER.STAND,200,token) then return false,"MOVE_FAIL" end
    task.wait(.25)
    for attempt=1,8 do
        if not isRunning(token) then return false,"STOPPED" end
        if #PHX.craftV19DialogueButtons()>=3 and PHX.craftV19DragonHunterVisible() then
            return true,"ALREADY_OPEN"
        end
        if PHX.craftWindow() then return true,"WINDOW_ALREADY_OPEN" end
        local cam=workspace.CurrentCamera
        if cam then
            local npcPos=CONFIG.DRAGON_HUNTER.NPC.Position+Vector3.new(0,2,0)
            local previousCam=cam.CFrame
            pcall(function() cam.CFrame=CFrame.lookAt(cam.CFrame.Position,npcPos) end)
            task.wait(.05)
            local point,onScreen=cam:WorldToViewportPoint(npcPos)
            if onScreen then
                local inset=select(1,game:GetService("GuiService"):GetGuiInset())
                for _,screenPos in ipairs({Vector2.new(point.X,point.Y)+inset,Vector2.new(point.X,point.Y)}) do
                    if not isRunning(token) then break end
                    local ok=PHX.inputPassthrough(function()
                        PHX.mouseEvent(screenPos.X,screenPos.Y,0,true,game,0)
                        task.wait(.07)
                        PHX.mouseEvent(screenPos.X,screenPos.Y,0,false,game,0)
                    end)
                    logLine("CRAFT_V19_NPC","attempt="..attempt.." dispatched="..tostring(ok))
                    local untilAt=os.clock()+.45
                    repeat
                        if (#PHX.craftV19DialogueButtons()>=3 and PHX.craftV19DragonHunterVisible())
                            or PHX.craftWindow() then
                            if cam.Parent then pcall(function() cam.CFrame=previousCam end) end
                            return true,"WORLD_CLICK_ATTEMPT_"..attempt
                        end
                        task.wait(.03)
                    until os.clock()>=untilAt
                end
            end
            if cam.Parent then pcall(function() cam.CFrame=previousCam end) end
        end
        task.wait(.08)
    end
    return false,"NPC_CLICK_NO_DRAGON_HUNTER_DIALOGUE"
end

function PHX.craftV19OpenWindow(token)
    if PHX.craftWindow() then return PHX.craftWindow(),"ALREADY_OPEN" end
    if not goHydra(token) then return nil,"HYDRA_ROUTE_FAIL" end
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_AFTER_TRAVEL" end
    local opened,mode=PHX.craftV19ClickDragonHunter(token)
    logLine("CRAFT_V19_NPC",tostring(mode))
    if not opened then return nil,"DRAGON_HUNTER_CLICK_FAIL:"..tostring(mode) end
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_AFTER_NPC" end

    local rootDeadline=os.clock()+1.2
    local rootButtons={}
    repeat
        if not isRunning(token) then return nil,"STOPPED" end
        rootButtons=PHX.craftV19DialogueButtons()
        if #rootButtons>=4 then break end
        task.wait(.04)
    until os.clock()>=rootDeadline
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_DURING_ROOT" end
    if #rootButtons<4 then return nil,"ROOT_OPTIONS_"..#rootButtons end
    local craftRoot,rootIndex=PHX.craftV19FindOption(rootButtons,"Craft")
    craftRoot=craftRoot or rootButtons[2]
    logLine("CRAFT_V19_ROOT","Craft row="..tostring(rootIndex or 2))
    local okRoot,whyRoot=PHX.craftV19FireButton(craftRoot)
    if not okRoot then return nil,"ROOT_CRAFT_SIGNAL_FAIL:"..tostring(whyRoot) end
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_AFTER_ROOT" end

    local recipeButtons=PHX.craftV19Transition(rootButtons,4,2.0,token)
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_DURING_RECIPE" end
    if #recipeButtons<4 then return nil,"RECIPE_OPTIONS_"..#recipeButtons end
    local magnet,magnetIndex=PHX.craftV19FindOption(recipeButtons,"Volcanic Magnet")
    magnet=magnet or recipeButtons[3] -- V1.9 working row fallback
    logLine("CRAFT_V19_RECIPE","Volcanic Magnet row="..tostring(magnetIndex or 3))
    local okRecipe,whyRecipe=PHX.craftV19FireButton(magnet)
    if not okRecipe then return nil,"MAGNET_SIGNAL_FAIL:"..tostring(whyRecipe) end
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_AFTER_RECIPE" end

    local finalButtons=PHX.craftV19Transition(recipeButtons,1,1.8,token)
    if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_DURING_FINAL" end
    if #finalButtons<=0 then return nil,"FINAL_OPTIONS_0" end
    local finalCraft,finalIndex=PHX.craftV19FindOption(finalButtons,"Craft")
    if not finalCraft then
        if #finalButtons>=2 then finalCraft=finalButtons[1];finalIndex=1
        else return nil,"FINAL_CRAFT_OPTION_MISSING" end
    end
    logLine("CRAFT_V19_FINAL","Craft row="..tostring(finalIndex))
    local okFinal,whyFinal=PHX.craftV19FireButton(finalCraft)
    if not okFinal then return nil,"FINAL_CRAFT_SIGNAL_FAIL:"..tostring(whyFinal) end
    local deadline=os.clock()+2.5
    repeat
        if PHX.craftWindow() then return PHX.craftWindow(),"OPEN_AFTER_FINAL" end
        if not isRunning(token) then return nil,"STOPPED" end
        task.wait(.04)
    until os.clock()>=deadline
    return nil,"CRAFT_WINDOW_NOT_OPEN"
end

local function craftVolcanicMagnet(token)
    local owner=coroutine.running()
    PHX.CraftUiBusy,PHX.CraftUiOwner=true,owner
    local ok,result=pcall(function()
        if not isRunning(token) then return false end
        if not PHX.StashBaselineReady then setStatus("Craft paused: startup Stash unknown; use manual Stash check"); return false end
        local beforeMagnet=PHX.cachedMaterialCount("Volcanic Magnet")
        if beforeMagnet == nil then return false end
        if beforeMagnet>0 then return true end
        local window,openWhy=PHX.craftV19OpenWindow(token)
        logLine("CRAFT_V19_PATH",tostring(openWhy))
        if not window or not PHX.guiVisible(window) then
            setStatus("V1.9 Magnet craft path failed: "..tostring(openWhy))
            return false
        end
        logLine("CRAFT_STATE","WINDOW_CONFIRMED -> VERIFY_RESULT -> CONFIRM_ONCE")
        logLine("CRAFT_WINDOW", "opened="..tostring(window:GetFullName()).." | size="..tostring(window.AbsoluteSize))
        local recipeName,recipeProof=PHX.craftWindowRecipe(window)
        if recipeName ~= "volcanicmagnet" then
            PHX.logCraftWindowProof(window,"MAGNET_RECIPE_NOT_VERIFIED:"..tostring(recipeProof)..":"..tostring(recipeName))
            logLine("CRAFT_BLOCKED", "Output card not proven; click NOT sent; verify visible result label")
            setStatus("Cannot verify Volcanic Magnet recipe ("..tostring(recipeProof)..") - craft NOT pressed")
            return false
        end
        logLine("CRAFT_RECIPE_PROOF", tostring(recipeName).." / "..tostring(recipeProof))
        local confirm,buttonProof=PHX.craftConfirmButton(window)
        if not confirm or not PHX.guiVisible(confirm) then
            PHX.logCraftWindowProof(window,"CONFIRM_BUTTON_NOT_FOUND")
            setStatus("Craft button not located - window left open")
            return false
        end
        logLine("CRAFT_TARGET","Volcanic Magnet confirmed | recipe="..tostring(recipeProof)
            .." | button="..confirm:GetFullName().." | selected="..tostring(buttonProof)
            .." position="..tostring(confirm.AbsolutePosition).." size="..tostring(confirm.AbsoluteSize))
        local beforeScrap=PHX.cachedMaterialCount("Scrap Metal")
        local beforeEmber=PHX.cachedMaterialCount("Blaze Ember")
        local popupBefore=PHX.StashScanQueue.NextId
        PHX.CraftPendingVerification={BeforeMagnet=beforeMagnet,BeforeScrap=beforeScrap,BeforeEmber=beforeEmber,AfterPopupId=popupBefore}
        PHX.CraftVerificationBlocked=true -- preserve uncertainty before the yielding confirm click
        if PHX.StashSession then PHX.StashSession.Verified=false end
        PHX.PickupSuppress["Volcanic Magnet"]={Until=os.clock()+8}
        if not isRunning(token) then PHX.PickupSuppress["Volcanic Magnet"]=nil; return false end
        logLine("CRAFT_CLICK","ONE attempt via V1.9 Activated-first; no repeated clicks")
        local attempted,clickBackend=PHX.craftV19FireButton(confirm)
        logLine("CRAFT_CLICK_BACKEND",tostring(clickBackend))
        if not attempted then
            PHX.PickupSuppress["Volcanic Magnet"]=nil
            PHX.CraftPendingVerification=nil
            PHX.CraftVerificationBlocked=false
            setStatus("Could not send Craft button click; window left open")
            logLine("CRAFT_CLICK_FAILED","Native Craft button input was not dispatched")
            return false
        end
        local receiptSeen=PHX.waitGui(function()
            local newId=(PHX.StashScanQueue and PHX.StashScanQueue.NextId) or popupBefore
            return PHX.craftWindow()==nil or newId>popupBefore
                or ((PHX.cachedMaterialCount("Volcanic Magnet") or 0)>beforeMagnet)
        end,4.5)
        if not receiptSeen then
            PHX.PickupSuppress["Volcanic Magnet"]=nil
            PHX.CraftVerificationBlocked=true
            logLine("CRAFT_CLICK_UNVERIFIED","Click dispatched but no close/receipt/count change; NO retry")
            setStatus("Craft click dispatched but no transaction verified; do NOT retry automatically")
            return false
        end
        if PHX.craftWindow()~=nil then
            logLine("CRAFT_WINDOW","still open after craft; close for Stash verification")
            PHX.closeCraftWindow()
        end
        PHX.CraftUiBusy=false
        local synced,why=PHX.waitForCraftInventory(token,popupBefore,8)
        PHX.PickupSuppress["Volcanic Magnet"]=nil
        if not synced then
            PHX.CraftVerificationBlocked=true
            setStatus("Craft not verified by popup + Stash | "..tostring(why))
            return false
        end
        local after=PHX.cachedMaterialCount("Volcanic Magnet")
        local scrapAfter=PHX.cachedMaterialCount("Scrap Metal")
        local emberAfter=PHX.cachedMaterialCount("Blaze Ember")
        if after and after-beforeMagnet>=1 then
            PHX.CraftVerificationBlocked=false
            PHX.CraftPendingVerification=nil
            if PHX.updateMagnetCache then PHX.updateMagnetCache(after,"CRAFT_VERIFIED") end
            setStatus("VERIFIED Volcanic Magnet +"..(after-beforeMagnet))
            logLine("CRAFT_OK","magnet="..beforeMagnet.."->"..after.." scrap="..tostring(beforeScrap).."->"..tostring(scrapAfter).." ember="..tostring(beforeEmber).."->"..tostring(emberAfter))
            return true
        end
        PHX.CraftVerificationBlocked=true
        setStatus("Crafted popup did not prove a Magnet increase; counters kept from real Stash")
        return false
    end)
    if PHX.CraftUiOwner==owner then PHX.CraftUiBusy=false;PHX.CraftUiOwner=nil end
    if not ok then
        PHX.CraftVerificationBlocked=PHX.CraftPendingVerification~=nil
        logLine("CRAFT_ERROR",tostring(result))
        setStatus("Craft error: "..tostring(result))
        return false
    end
    return result
end

local function recoverMagnet(token)
    if not PHX.StashBaselineReady then setStatus("MAGNET UNKNOWN: startup Stash incomplete; use manual Stash check"); return false end
    local count=PHX.cachedMaterialCount("Volcanic Magnet")
    if count and count>0 then
        PHX.CraftVerificationBlocked=false
        PHX.CraftPendingVerification=nil
        return true
    end
    if PHX.CraftVerificationBlocked then
        local pending=PHX.CraftPendingVerification
        if pending then
            local verified=PHX.waitForCraftInventory(token,pending.AfterPopupId,2)
            local after=PHX.cachedMaterialCount("Volcanic Magnet")
            if verified and after and after>pending.BeforeMagnet then
                PHX.CraftVerificationBlocked=false
                PHX.CraftPendingVerification=nil
                return true
            end
        end
        setStatus("Prior craft unverified: waiting for crafted popup or manual Stash check")
        return false
    end
    if count==nil then setStatus("MAGNET UNKNOWN: manual Stash check required"); return false end
    local scrap=PHX.cachedMaterialCount("Scrap Metal")
    local ember=PHX.cachedMaterialCount("Blaze Ember")
    if scrap==nil or ember==nil then setStatus("Material baseline unavailable"); return false end
    if scrap<10 and not farmScrap(token) then return false end
    if not isRunning(token) then return false end
    if ember<15 and not farmBlazeEmbers(token) then return false end
    if not isRunning(token) then return false end
    local crafted=craftVolcanicMagnet(token)
    if not crafted or not PHX.travelAlive(token) then return false end
    logLine("BOAT_AFTER_CRAFT","MAGNET_VERIFIED -> TIKI_PORTAL_ONLY -> FAST_DIRECT_RPC_ON_NEXT_CYCLE")
    if not PHX.returnToTikiForBoat(token,"MAGNET_CRAFT") then
        setStatus("Magnet crafted; waiting for Tiki return before boat purchase")
        return false
    end
    return true
end

PHX.EventFinishedIslands = PHX.EventFinishedIslands or setmetatable({}, {__mode="k"})
PHX.RewardProgress = PHX.RewardProgress or setmetatable({}, {__mode="k"})
PHX.CompletedIslands = PHX.CompletedIslands or setmetatable({}, {__mode="k"})

local function runPrehistoricEvent(island, token)
    if not island or not isRunning(token) then return false end
    if PHX.afkSoloEnabled() and os.clock() < (PHX.AFKRecoveryUntil or 0) then
        task.wait(math.min(1,(PHX.AFKRecoveryUntil or 0)-os.clock()))
        return false
    end
    PHX.ActiveEventCrewIsland=island
    PHX.refreshCrew(getMasterBoat())
    PHX.freezeEventCrew(island)
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
                    if target then PHX.observeFossilCrew(island,target.Position,CONFIG.RELIC_RADIUS) end
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
            if completed then
                PHX.EventFinishedIslands[island] = true
                progress.AFKRewardWaitAt=progress.AFKRewardWaitAt or os.clock()
            end
            if not PHX.EventFinishedIslands[island] or not isRunning(token) then return false end
            task.wait(.35)
        end
        if not isRunning(token) or not island.Parent then return false end

        if PHX.EventFinishedIslands[island] then
            progress.AFKRewardWaitAt=progress.AFKRewardWaitAt or os.clock()
        end
        if PHX.afkSoloEnabled() and not progress.Egg and progress.AFKRewardWaitAt
            and os.clock()-progress.AFKRewardWaitAt>=CONFIG.AFK_SOLO.EGG_RECOVERY_TIMEOUT
            and not PHX.eventActive(island) and not PHX.raidTimerStillRunning() then
            progress.Egg=true
            progress.EggState="AFK_SKIPPED_UNVERIFIED"
            progress.EggPending=nil
            logLine("AFK_EGG_TIMEOUT", "90s no verified pickup; raid ended; move to next cycle")
        end
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

        if PHX.afkSoloEnabled() and progress.EggState == "CONFIRMED"
            and progress.PostEggGuard == true then
            local relic,origin=PHX.afkRelicProof(island)
            if relic and relic > CONFIG.AFK_SOLO.EGG_FAST_RESET_RELIC_ABOVE then
                PHX.AFKRewardExit={Island=island,Progress=progress,Character=LP.Character,
                    Confirmed=true,Relic=relic,At=os.clock()}
                PHX.CompletedIslands[island]=true
                PHX.EventFinishedIslands[island]=true
                PHX.EventState.Phase="AFK_EGG_EXIT"
                logLine("AFK_EGG_RESET",string.format("verified egg + relic %.1f%% >90 (%s); skip Bones",relic,origin))
                PHX.PendingDepartureIsland=island
                if resetBackToTiki and resetBackToTiki(token) then
                    PHX.PendingDepartureIsland=nil
                    PHX.ActiveEventCrewIsland=nil
                    PHX.AFKRewardExit=nil
                    if not isRunning(token) then return false end
                    local magnet=hasVolcanicMagnet()
                    if magnet==false then return recoverMagnet(token) end
                    return magnet==true
                end
                logLine("AFK_EGG_RESET_WAIT","safety guard or return route unavailable; retry")
                PHX.AFKRecoveryUntil=os.clock()+CONFIG.AFK_SOLO.ERROR_RETRY_GAP
                return false
            end
            logLine("AFK_EGG_RELIC", "Egg confirmed, but relic not >90 | "..tostring(relic or origin))
        end
        if PHX.afkSoloEnabled() then
            progress.Bones=true
            if not progress.BonesLogged then
                logLine("AFK_BONES", "SOLO skipping optional Bones sweep")
                progress.BonesLogged=true
            end
        end
        if not progress.Bones then
            PHX.EventState.Phase = "BONES"
            if CONFIG.BONES.ENABLED then
                if collectBones(island,token) ~= true then return false end
            end
            progress.Bones = true
        end
        if not isRunning(token) then return false end
    end

    PHX.EventState.Phase = "REWARD_GUARD"
    setStatus("Reward verification -> Dragon storage guard before reset")
    if not PHX.secureDragonWindow(CONFIG.DRAGON_GUARD.PRE_RESET_GUARD_SECONDS,token) then return false end
    progress.Guard = true
    if not alreadyCompleted then
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
    PHX.ActiveEventCrewIsland=nil
    if not isRunning(token) then return false end
    local magnet = hasVolcanicMagnet()
    if magnet == false then return recoverMagnet(token) end
    return magnet == true
end

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
    if PHX.BoatPurchasePending then
        local pendingIsland=findPrehistoric()
        if pendingIsland then
            PHX.stopBoat()
            runPrehistoricEvent(pendingIsland,token)
            return
        end
        if not buyGrandBrigade(token) then
            task.wait(.25)
            return
        end
    end
    local pre=scanTeamPreflight(token)
    if pre.Interrupted then return end
    if pre.Island then PHX.stopBoat(pre.Boat); runPrehistoricEvent(pre.Island,token); return end
    if not PHX.requireMagnet(pre,token) then return end
    local boat
    if PHX.BoatRebuyPending then
        logLine("BOAT_RESPAWN", "masterCycle enforcing new boat purchase")
    elseif not PHX.BoatPurchasePending then
        boat=pre.Boat or getMasterBoat()
    end
    local r=root()
    if boat and r and (boat:GetPivot().Position-r.Position).Magnitude>8000 and
        (boat:GetPivot().Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude>5200 then
        PHX.stopBoat(boat)
        PHX.RejectedBoats[boat]=true
        PHX.TeamPhase="RECOVERY"; PHX.BoatState="OFFSHORE_RESPAWN"
        boat=nil
    end
    if not boat then
        if not PHX.BoatPurchasePending and os.clock()<(PHX.NextBoatBuyAt or 0) then
            setStatus("MASTER: waiting verified boat retry cooldown")
            task.wait(.5);return
        end
        boat=buyGrandBrigade(token)
    end
    if not boat then setStatus("MASTER RECOVERY: boat unavailable; keep Magnet cache"); task.wait(1); return end
    PHX.stopBoat(boat)
    if not boardBoat(boat,token) then
        PHX.TeamPhase="RECOVERY"; PHX.BoatState="DRIVER_SEAT_FAILED"
        setStatus("MASTER driver seat failed; retry without Stash check")
        task.wait(.5); return
    end
    PHX.TeamPhase="BOARDING"; PHX.BoatState="WAIT_PASSENGERS"
    while PHX.travelAlive(token) and PHX.boatAlive(boat) do
        PHX.refreshCrew(boat)
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
                    if not PHX.returnToTikiForBoat(token,"TEAM_RENDEZVOUS") then return end
                    return
                end
            end
        end
        setStatus("MASTER: aboard "..aboard.."; need driver + "..(tonumber(CONFIG.MIN_SLAVES_TO_SAIL) or 3).." passengers")
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
        PHX.refreshCrew(boat)
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
    if PHX.localRole()=="NONE" and not PHX.isSoloAutomation() then
        setStatus("Chưa có role: chọn player Master hoặc bật Add role Master")
        ENV.TeamConfig.StopReason = "NO_ROLE"
        ENV.TeamConfig.IsRunning = false
        return
    end

    ensureMarines()

    while isRunning(token) do
        local ready,waiting=true,nil
        if PHX.automationReadyGuard then ready,waiting=PHX.automationReadyGuard(token) end
        if not isRunning(token) then return end
        if not ready then
            waiting=waiting or "AUTOMATION_NOT_READY"
            if PHX.Runtime.AutomationBlockedReason~=waiting then
                setStatus("Auto Volcano đang chờ: "..tostring(waiting))
                logLine("RUN_WAIT",tostring(waiting))
            end
            PHX.Runtime.AutomationBlockedReason=waiting
            PHX.Runtime.RunState=DRAGON_GUARD_STATE.Critical and "Critical" or "Waiting"
            PHX.stopBoat()
            setForestMagnet(false)
            stopStableHover()
            task.wait(.5)
            continue
        end
        if PHX.Runtime.AutomationBlockedReason then
            PHX.Runtime.AutomationBlockedReason=nil
            PHX.Runtime.RunState="Running"
            setStatus("Auto Volcano tiếp tục | "..roleText())
        end
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

    local sig = table.concat({
        tostring(NIGHT.LastStatus), tostring(region), tostring(inv.Scrap), tostring(inv.Ember), tostring(inv.Magnet),
        tostring(active), tostring(relicHp), eventUiText("PrehistoricRaidTimer"), tostring(forestCount),
        tostring(math.floor(forestHp/100)), tostring(math.floor(math.max(golemHp,0)/100)), tostring(aboard), tostring(hb)
    }, ":")
    return sig,line,active
end

function PHX.setAutomationMode(mode)
    if not PHX.generationAlive() then return false,"Runtime đã đóng" end
    mode=type(mode)=="string" and string.upper(mode) or ""
    if mode~="TEAM" and mode~="SOLO" then return false,"Mode phải là TEAM hoặc SOLO" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then
        return false,"Tắt Auto Volcano trước khi đổi Team / Solo"
    end
    if PHX.Runtime.FruitGuiBusy or (PHX.FruitAutoState and PHX.FruitAutoState.Busy) then
        return false,"Đợi thao tác random / store hoàn tất trước khi đổi mode"
    end
    if PHX.automationMode()==mode then return true,mode.." đã được chọn" end
    if PHX.restoreMovement then PHX.restoreMovement() end
    CONFIG.AUTOMATION_MODE=mode
    PHX.Runtime.AutomationMode=mode
    PHX.ActiveEventCrewIsland=nil
    PHX.ClusterIsland,PHX.ClusterAnchor=nil,nil
    PHX.SeaHeading=nil
    PHX.TeamPhase="READY"
    PHX.BoatState=mode=="SOLO" and "SOLO_READY" or "WAIT_MASTER"
    if PHX.saveUserConfig then PHX.saveUserConfig() end
    return true,mode=="SOLO" and "Solo: tự farm Magnet, mua thuyền và đánh Prehistoric" or "Team: Master + ít nhất 3 Slave mới ra khơi"
end

function PHX.validateRole()
    if PHX.isSoloAutomation and PHX.isSoloAutomation() then return true end
    local role=PHX.localRole()
    local master=ENV.TeamConfig.MasterName
    if role=="NONE" then return false,"Chọn player Master để làm Slave hoặc bật Add role Master" end
    if role=="MASTER" and PHX.sameName(master,LP.Name) then return true end
    if role=="SLAVE" and type(master)=="string" and master~="" and not PHX.sameName(master,LP.Name) then return true end
    return false,"Role chưa hợp lệ; chọn lại Master"
end

function PHX.setMaster(name)
    name=type(name)=="string" and name:match("^%s*(.-)%s*$") or ""
    if PHX.sameName(name,LP.Name) then
        if PHX.localRole()=="MASTER" then return true,"Client này là Master" end
        return false,"Bật Add role Master để tự làm Master"
    end
    return PHX.assignMaster(name)
end

function PHX.stopAutomation(reason)
    ENV.TeamConfig.StopReason = reason or "USER_BUTTON"
    if PHX.UserConfigState then
        PHX.UserConfigState.ResumePending=false
        if ENV.TeamConfig.StopReason=="USER_BUTTON" or ENV.TeamConfig.StopReason=="USER_STOP" then
            PHX.UserConfigState.DesiredRunning=false
        end
    end
    ENV.TeamConfig.IsRunning = false
    if PHX.restoreForestGolemBring then pcall(PHX.restoreForestGolemBring) end
    if PHX.restoreQuestFarmBring then pcall(PHX.restoreQuestFarmBring) end
    RUN_TOKEN = RUN_TOKEN + 1
    PHX.Runtime.AutomationBlockedReason=nil
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
    if PHX.saveUserConfig and (ENV.TeamConfig.StopReason=="USER_BUTTON" or ENV.TeamConfig.StopReason=="USER_STOP") then
        PHX.saveUserConfig()
    end
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

function PHX.stashReadyToStart()
    if PHX.PostRespawnStashPending then return false,"Waiting for Stash refresh after respawn" end
    local queue=PHX.StashScanQueue
    if not queue then return true end
    if not queue.StartupDone then
        return false,PHX.Runtime.StartupStatus or "Stash sẽ tự kiểm tra sau 15 giây từ execute"
    end
    if not PHX.StashBaselineReady then
        return false,"Chưa đọc đủ thông tin Stash · đang chờ tự kiểm tra lại"
    end
    if queue.Busy or PHX.StashSyncBusy or #queue.Jobs>0 then
        return false,"Stash update pending; wait for the crafted Magnet scan"
    end
    return true
end

function PHX.startAutomation(masterName)
    if not PHX.generationAlive() then return false,"Runtime unloaded" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Automation is already starting/running" end
    if PHX.Runtime.FruitGuiBusy or (PHX.FruitAutoState and PHX.FruitAutoState.Busy) then
        return false,"Đợi thao tác random / store hiện tại hoàn tất trước khi bật Auto Volcano"
    end
    local stashReady,stashWhy=PHX.stashReadyToStart()
    if not stashReady then return false,stashWhy end
    if masterName then
        local ok,reason=PHX.setMaster(masterName)
        if not ok then return false,reason end
    end
    local valid,reason=PHX.validateRole()
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
        local stashReady,stashWhy=PHX.stashReadyToStart()
        if not stashReady then return false,stashWhy end
        RUN_TOKEN=RUN_TOKEN+1
        local token=RUN_TOKEN
        ENV.TeamConfig.StopReason=nil
        ENV.TeamConfig.IsRunning=true
        PHX.Runtime.RunState="Running"
        PHX.Runtime.Reason=nil
        PHX.Runtime.LastError=nil
        NIGHT.LastProgressAt=os.clock()
        NIGHT.LastProgressSignature="RUN_START:"..token
        logLine("RUN","START | mode="..(PHX.automationMode and PHX.automationMode() or "TEAM").." role="..roleText()
            .." master="..tostring(PHX.automationLeaderName and PHX.automationLeaderName() or ENV.TeamConfig.MasterName))
        setStatus("STARTED | "..roleText())
        if PHX.setSavedAutomationIntent then PHX.setSavedAutomationIntent(true) end
        PHX.launchRunner(token)
        return true,"Automation started"
    end)
    if PHX.Runtime.StartThread==startThread then PHX.Runtime.StartThread=nil end
    PHX.releaseLock(owner)
    if not ok then PHX.Runtime.LastError=tostring(result);return false,tostring(result) end
    return result,message
end

function PHX.assignMaster(name)
    if not PHX.generationAlive() then return false,"Runtime đã đóng" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Tắt Auto Volcano trước khi đổi Master" end
    local player=PHX.playerByName(name)
    if not player then return false,"Player đã rời server" end
    if PHX.sameName(player.Name,LP.Name) then return false,"Dùng nút Add role Master để tự làm Master" end
    if not PHX.sameName(ENV.TeamConfig.MasterName,player.Name) then
        PHX.BoardedCrew={}; PHX.CrewBoat=nil
        PHX.ActiveEventCrewIsland=nil
    end
    CONFIG.MASTER_NAME=player.Name
    ENV.TeamConfig.MasterName=player.Name
    ENV.TeamConfig.Role="SLAVE"
    ENV.TeamConfig.IsMaster=false
    ENV.TeamConfig.ForceMasterRole=false
    PHX.LastOtherMaster=player.Name
    PHX.refreshCrew(nil)
    return true,"Master: "..player.Name.." · client này được cấp role Slave"
end

function PHX.setLocalMaster(value)
    if not PHX.generationAlive() then return false,"Runtime đã đóng" end
    if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then return false,"Tắt Auto Volcano trước khi đổi role" end
    if value==true then
        if ENV.TeamConfig.MasterName and not PHX.sameName(ENV.TeamConfig.MasterName,LP.Name) then
            PHX.LastOtherMaster=ENV.TeamConfig.MasterName
        end
        if not PHX.sameName(ENV.TeamConfig.MasterName,LP.Name) then
            PHX.BoardedCrew={}; PHX.CrewBoat=nil; PHX.ActiveEventCrewIsland=nil
        end
        CONFIG.MASTER_NAME=LP.Name
        ENV.TeamConfig.MasterName=LP.Name
        ENV.TeamConfig.Role="MASTER"
        ENV.TeamConfig.IsMaster=true
        ENV.TeamConfig.ForceMasterRole=true
        PHX.refreshCrew(nil)
        return true,"Client này được cấp role Master"
    end
    local previous=PHX.LastOtherMaster and PHX.playerByName(PHX.LastOtherMaster)
    if previous and not PHX.sameName(previous.Name,LP.Name) then return PHX.assignMaster(previous.Name) end
    CONFIG.MASTER_NAME=nil; CONFIG.TEAM={}
    ENV.TeamConfig.MasterName=nil
    ENV.TeamConfig.Role="NONE"
    ENV.TeamConfig.IsMaster=false
    ENV.TeamConfig.ForceMasterRole=false
    PHX.BoardedCrew={}; PHX.CrewBoat=nil
    PHX.ActiveEventCrewIsland=nil
    return true,"Client này chưa có role"
end
CONFIG.FRUIT_AUTO = CONFIG.FRUIT_AUTO or {}
if CONFIG.FRUIT_AUTO.Enabled == nil then CONFIG.FRUIT_AUTO.Enabled = false end
if CONFIG.FRUIT_AUTO.AutoStore == nil then CONFIG.FRUIT_AUTO.AutoStore = true end
function PHX.fruitSessionKey()
    return tostring(game and game.JobId or "").."|"..tostring(game and game.PlaceId or "").."|"..tostring(LP and LP.UserId or "")
end
PHX.FruitSessionKey=PHX.fruitSessionKey()
if ENV.__PH_FRUIT_RECEIPT_SESSION~=PHX.FruitSessionKey then
    ENV.__PH_FRUIT_ROLL_PENDING=nil
    ENV.__PH_FRUIT_RECEIPT_SERIAL=0
    ENV.__PH_FRUIT_LAST_RECEIPT=nil
    ENV.__PH_FRUIT_RECEIPT_RECORDED=nil
    ENV.__PH_FRUIT_RECEIPT_SESSION=PHX.FruitSessionKey
end
ENV.__PH_FRUIT_PENDING = ENV.__PH_FRUIT_PENDING or {} -- strong references retain unverified operations across reload
ENV.__PH_FRUIT_RECEIPT_NOTIFIED = ENV.__PH_FRUIT_RECEIPT_NOTIFIED or setmetatable({}, {__mode="k"})
ENV.__PH_FRUIT_RECEIPT_RECORDED = ENV.__PH_FRUIT_RECEIPT_RECORDED or setmetatable({}, {__mode="k"})
PHX.FruitReceiptRecorded = ENV.__PH_FRUIT_RECEIPT_RECORDED
ENV.__PH_FRUIT_STORE_RETRIES = ENV.__PH_FRUIT_STORE_RETRIES or setmetatable({}, {__mode="k"})
PHX.FruitReceiptNotified = ENV.__PH_FRUIT_RECEIPT_NOTIFIED
PHX.FruitAutoState = {
    Busy=false, Enabled=CONFIG.FRUIT_AUTO.Enabled==true, AutoStore=CONFIG.FRUIT_AUTO.AutoStore==true,
    Status="READY", PhysicalCount=0, NextRandomAt=0, NextStoreAt=0,
    RandomFailures=0, StoreFailures=0, Pending=ENV.__PH_FRUIT_PENDING, LastRandom=nil, LastStored=nil,
    StoreRetries=ENV.__PH_FRUIT_STORE_RETRIES, DragonRetryAt=0, DragonFailures=0,
    ValuableQueued=false, ValuableRequested=false,
    ReceiptSerial=tonumber(ENV.__PH_FRUIT_RECEIPT_SERIAL) or 0, LastReceipt=ENV.__PH_FRUIT_LAST_RECEIPT,
    RollPending=ENV.__PH_FRUIT_ROLL_PENDING,
}
if (tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0)>os.time() then
    PHX.FruitAutoState.NextRandomAt=os.clock()+(ENV.__PH_DIRECT_GACHA_NEXT_READY-os.time())
end
PHX.FruitStoreIds = {}
for _,name in ipairs({"Rocket","Spin","Spring","Bomb","Smoke","Spike","Flame","Ice","Sand","Dark","Diamond","Light","Rubber","Ghost","Magma","Quake","Buddha","Love","Spider","Sound","Phoenix","Portal","Pain","Blizzard","Gravity","Mammoth","T-Rex","Dough","Shadow","Venom","Control","Gas","Spirit","Yeti","Kitsune","Leopard"}) do
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
    if raw=="" then
        local original=tool:FindFirstChild("OriginalName",true)
        if original and original:IsA("StringValue") then raw=tostring(original.Value or "") end
    end
    if raw:match("^[%w%-]+%-[%w%-]+$") then return raw end
    local key=PHX.fruitLabelKey(raw~="" and raw or tool.Name)
    for _,id in pairs(inventory and inventory.Ids or {}) do
        for split=1,#id do
            if id:sub(split,split)=="-" then
                local left,right=id:sub(1,split-1),id:sub(split+1)
                if string.lower(left)==string.lower(right) and PHX.fruitLabelKey(left)==key then return id end
            end
        end
    end
    local mapped=PHX.FruitStoreIds[key]
    if mapped then return mapped end
    return nil,"STORE_ID_UNVERIFIED"
end

function PHX.fruitRetryDelay(failures)
    local maxDelay=math.max(5,tonumber(CONFIG.FRUIT_AUTO.MaxBackoff) or 300)
    return math.min(maxDelay,5*2^math.min(failures or 1,7))
end

function PHX.valuableFruitKind(tool, inventory)
    if not PHX.isPhysicalFruitTool(tool) then return nil end
    if PHX.isDragonFruitTool(tool) then return "Dragon" end
    local id=PHX.fruitStoreId(tool,inventory)
    local key=string.lower(tostring(id or ""))
    if key=="kitsune-kitsune" then return "Kitsune" end
    if key=="leopard-leopard" then return "Leopard" end
    return nil
end

function PHX.findValuableFruits()
    local out={}
    for _,tool in ipairs(PHX.findPhysicalFruits()) do
        if PHX.valuableFruitKind(tool) then out[#out+1]=tool end
    end
    return out
end

function PHX.recordPhysicalFruitReceipt(tool)
    if not PHX.isPhysicalFruitTool(tool) or not PHX.fruitStillLocal(tool) then return false end
    local recorded=PHX.FruitReceiptRecorded
    if not recorded or recorded[tool] then return false end
    recorded[tool]=true
    local state=PHX.FruitAutoState
    if state then
        state.ReceiptSerial=(state.ReceiptSerial or 0)+1
        state.LastReceipt={Tool=tool,Name=tool.Name,Kind=PHX.valuableFruitKind and PHX.valuableFruitKind(tool) or nil,At=os.clock()}
        ENV.__PH_FRUIT_RECEIPT_SERIAL=state.ReceiptSerial
        ENV.__PH_FRUIT_LAST_RECEIPT=state.LastReceipt
    end
    return true
end

function PHX.notifyValuableFruit(tool)
    local kind=PHX.valuableFruitKind(tool)
    if kind and PHX.recordPhysicalFruitReceipt then PHX.recordPhysicalFruitReceipt(tool) end
    if kind=="Dragon" then return PHX.notifyDragonFruit and PHX.notifyDragonFruit(tool) or false end
    if not kind or PHX.FruitReceiptNotified[tool] then return false end
    PHX.FruitReceiptNotified[tool]=true
    return sendWebhook("VALUABLE FRUIT RECEIVED", LP.Name.." received "..kind.."; storing before reset.", {
        {name="Account",value=LP.Name,inline=true},
        {name="Fruit",value=kind,inline=true},
        {name="Server",value=tostring(game.JobId),inline=false},
    }, true)
end

function PHX.notifyPhysicalValuables()
    for _,tool in ipairs(PHX.findValuableFruits()) do PHX.notifyValuableFruit(tool) end
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
    local state=PHX.FruitAutoState
    if #PHX.findPhysicalDragonFruits()==0 and not DRAGON_GUARD_STATE.Pending and not DRAGON_GUARD_STATE.Critical then
        state.DragonFailures=0;state.DragonRetryAt=0
        return true,"DRAGON_CHECKED"
    end
    if os.clock()<state.DragonRetryAt then return false,"DRAGON_STORE_BACKOFF" end
    local guard=PHX.storeDragonFruitCritical or storeDragonFruitCritical
    if type(guard)~="function" then return false,"DRAGON_GUARD_UNAVAILABLE" end
    local ok,result=pcall(guard)
    local confirmed=ok and result==true and not DRAGON_GUARD_STATE.Critical
        and not DRAGON_GUARD_STATE.Pending and #PHX.findPhysicalDragonFruits()==0
    if confirmed then state.DragonFailures=0;state.DragonRetryAt=0
    else
        state.DragonFailures=state.DragonFailures+1
        state.DragonRetryAt=os.clock()+PHX.fruitRetryDelay(state.DragonFailures)
    end
    return confirmed,confirmed and "DRAGON_CHECKED" or (ok and "DRAGON_STORE_UNCONFIRMED" or "DRAGON_GUARD_ERROR: "..tostring(result))
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
                state.StoreRetries[tool]=nil
                state.LastStored=pending.Id
                logLine("FRUIT_STORED",pending.Id.." verified after delayed replication")
            else ready=false end
        end
    end
    return ready
end

function PHX.storePhysicalFruit(tool,token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    if PHX.isDragonFruitTool(tool) then return PHX.runDragonGuard() end
    if not PHX.isPhysicalFruitTool(tool) or not PHX.fruitStillLocal(tool) then return false,"TOOL_NOT_LOCAL" end
    PHX.recordPhysicalFruitReceipt(tool)
    PHX.notifyValuableFruit(tool)
    local before,reason=PHX.readStoredFruitInventory()
    if not before then
        if PHX.valuableFruitKind(tool) then return false,reason end
        if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
            or (PHX.Runtime and (PHX.Runtime.InteractionHold or PHX.Runtime.StartBusy)) then
            return false,"WAITING_FOR_GAME_INTERACTION"
        end
        local id,idWhy=PHX.fruitStoreId(tool,nil)
        if not id then return false,idWhy end
        local guiLock=PHX.acquireLock(PHX.Runtime,"FruitGuiBusy","FruitGuiBusy")
        if not guiLock then return false,"WAITING_FOR_GAME_INTERACTION" end
        local ok,result=pcall(function() return CommF:InvokeServer("StoreFruit",id,tool) end)
        local untilTime=os.clock()+2.5
        while PHX.fruitServiceAlive(token) and PHX.fruitStillLocal(tool) and os.clock()<untilTime do task.wait(.15) end
        local moved=not PHX.fruitStillLocal(tool)
        PHX.releaseLock(guiLock)
        if moved then
            PHX.FruitAutoState.LastStored=id
            PHX.FruitAutoState.LastStoreRoute="REMOTE_TOOL_REMOVED_INVENTORY_UNAVAILABLE"
            logLine("FRUIT_STORE_PROVISIONAL",id.." Tool removed; stored inventory unavailable, so not fully verified")
            return true,"STORE_TOOL_REMOVED_UNVERIFIED"
        end
        local _,fullReason=PHX.dismissFruitStorageFull(tool,false,token)
        if fullReason then return false,fullReason end
        return false,ok and "STORE_NOT_CONFIRMED_INVENTORY_UNAVAILABLE" or ("STORE_REMOTE_FAILED: "..tostring(result))
    end
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    local pending=PHX.FruitAutoState.Pending[tool]
    if pending and os.clock()<(tonumber(pending.RetryAt) or 0) then return false,"STORE_FULL_BACKOFF" end
    local id,idReason=PHX.fruitStoreId(tool,before)
    if pending then id=pending.Id end
    if not id then return false,idReason end
    local count=pending and pending.Before or (before.Counts[string.lower(id)] or 0)
    if not pending then
        pending={Id=id,Before=count,Kind=PHX.valuableFruitKind(tool,before)}
        PHX.FruitAutoState.Pending[tool]=pending
    end
    local storeButton=PHX.physicalFruitStoreOption and PHX.physicalFruitStoreOption(tool)
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (PHX.Runtime and (PHX.Runtime.InteractionHold or PHX.Runtime.StartBusy)) then
        return false,"WAITING_FOR_GAME_INTERACTION"
    end
    local guiOwner=PHX.acquireLock(PHX.Runtime,"FruitGuiBusy","FruitGuiBusy")
    if not guiOwner then return false,"WAITING_FOR_GAME_INTERACTION" end
    local function requestAndVerify()
        if not PHX.fruitServiceAlive(token) or not PHX.fruitStillLocal(tool) then return false,"CANCELED" end
        local function storageFullReply()
            local closed,fullReason=PHX.dismissFruitStorageFull(tool,true,token)
            if not fullReason then return nil end
            pending.StorageFull=true
            pending.StorageFullVerified=(fullReason=="STORE_FULL_FRUIT_RETAINED" and PHX.fruitStillLocal(tool))
            pending.FullReason=fullReason
            pending.RetryAt=os.clock()+math.max(30,PHX.fruitRetryDelay and PHX.fruitRetryDelay(1) or 5)
            PHX.FruitAutoState.LastStoreReply=fullReason
            logLine("FRUIT_STORE_FULL",id.." kept on character/backpack; "..tostring(fullReason))
            return fullReason
        end
        local fullReason=storageFullReply()
        if fullReason then return false,fullReason end
        local ok,result=pcall(function()
            if storeButton then
                if PHX.physicalFruitStoreOption(tool,true)~=storeButton then return false end
                return PHX.activateOnce(storeButton,PHX.stashInputClick)
            end
            return CommF:InvokeServer("StoreFruit",id,tool)
        end)
        PHX.FruitAutoState.LastStoreRoute=storeButton and "BLOX_FRUIT_NATIVE_STORE" or "STORE_FRUIT_REMOTE"
        local requestSent=ok and (not storeButton or result==true)
        if requestSent then pending.StoreAttemptedAt=os.clock() end
        local deadline=os.clock()+math.max(storeButton and 4 or .5,tonumber(CONFIG.FRUIT_AUTO.StoreVerifySeconds) or 2)
        repeat
            if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
            task.wait(.25)
            local after=PHX.readStoredFruitInventory()
            if after and not PHX.fruitStillLocal(tool) and (after.Counts[string.lower(id)] or 0)>count then
                PHX.FruitAutoState.Pending[tool]=nil
                PHX.FruitAutoState.StoreRetries[tool]=nil
                PHX.FruitAutoState.LastStored=id
                noteProgress("FRUIT_STORED:"..id)
                logLine("FRUIT_STORED",id.." removed and fresh stored count increased")
                return true,id
            end
            fullReason=storageFullReply()
            if fullReason then return false,fullReason end
        until os.clock()>=deadline
        if requestSent and PHX.fruitStillLocal(tool) then
            local fresh=PHX.readStoredFruitInventory()
            local existing=fresh and tonumber(fresh.Counts[string.lower(id)]) or 0
            if existing and existing>=1 and existing<=count and count>=1 then
                pending.StoreFailedWithDuplicate=true
                pending.StoreFailedAt=os.clock()
                logLine("FRUIT_STORE_DUPLICATE",id.." already stored; attempted Store but physical Tool remained")
            end
        end
        return false,ok and "STORE_UNCONFIRMED" or "STORE_REQUEST_FAILED: "..tostring(result)
    end
    local ok,stored,result=pcall(requestAndVerify)
    if guiOwner then PHX.releaseLock(guiOwner) end
    if not ok then return false,"STORE_SERVICE_ERROR: "..tostring(stored) end
    return stored,result
end

function PHX.storeValuableFruitSweep(token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    local state=PHX.FruitAutoState
    PHX.notifyPhysicalValuables()
    if #PHX.findPhysicalDragonFruits()>0 or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
        local ok,reason=PHX.runDragonGuard()
        if not ok then return false,reason end
    end
    if not PHX.reconcileFruitPending() then return false,"STORAGE_PENDING_VERIFICATION" end
    local failure=nil
    for _,tool in ipairs(PHX.findValuableFruits()) do
        if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
        if PHX.isDragonFruitTool(tool) then return false,"DRAGON_REPLICATING" end
        local retry=state.StoreRetries[tool]
        if retry and os.clock()<retry.At then failure=failure or "VALUABLE_STORE_BACKOFF"
        else
            local ok,reason=PHX.storePhysicalFruit(tool,token)
            if not ok then
                local failures=(retry and retry.Failures or 0)+1
                state.StoreRetries[tool]={Failures=failures,At=os.clock()+PHX.fruitRetryDelay(failures)}
                logLine("VALUABLE_STORE_WAIT",tostring(tool.Name)..": "..tostring(reason))
                failure=failure or reason
                if not PHX.fruitStillLocal(tool) then break end
            end
        end
    end
    if failure then return false,failure end
    return #PHX.findValuableFruits()==0,#PHX.findValuableFruits()==0 and "VALUABLE_FRUIT_SECURED" or "VALUABLE_FRUIT_REPLICATING"
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

function PHX.gachaPurchaseTarget()
    if not PG or not PHX.guiVisible then return nil,"GACHA_CLOSED" end
    local window=PG:FindFirstChild("ZiolesGacha_Window")
    local frame=window and window:FindFirstChild("Frame")
    local main=frame and frame:FindFirstChild("Main")
    if not main or not PHX.guiVisible(main) then return nil,"GACHA_CLOSED" end
    local footer=main:FindFirstChild("Footer")
    local purchase=footer and footer:FindFirstChild("PurchaseButton")
    local button=purchase and PHX.stashTileClickTarget(purchase)
    if not button and purchase and purchase:IsA("GuiObject") and PHX.guiVisible(purchase)
        and purchase.AbsoluteSize.X>0 and purchase.AbsoluteSize.Y>0 then button=purchase end
    if not button or not PHX.guiVisible(button) then return nil,"GACHA_PURCHASE_NOT_READY",window end
    local disabled=false
    pcall(function() disabled=button.Interactable==false end)
    if disabled then return nil,"GACHA_PURCHASE_DISABLED",window end
    return button,"GACHA_GUI",window
end

function PHX.gachaVisibleCooldown(window)
    if not window or not PHX.guiVisible then return nil end
    for _,object in ipairs(window:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and PHX.guiVisible(object) then
            local seconds,reason=PHX.fruitCooldown(object.Text)
            if seconds then return seconds,reason end
        end
    end
    return nil
end

function PHX.gachaSpinnerVisible()
    local spinner=PG and PG:FindFirstChild("SpinnerWindow")
    if not spinner or not PHX.guiVisible or not PHX.guiVisible(spinner) then return false end
    for _,object in ipairs(spinner:GetDescendants()) do
        if (object.Name=="AnimationFrame" or object.Name=="ItemName" or object.Name=="_VirtualContainer" or object.Name=="SelectorFrame")
            and object:IsA("GuiObject") and PHX.guiVisible(object)
            and object.AbsoluteSize.X>0 and object.AbsoluteSize.Y>0 then return true end
    end
    return false
end

function PHX.gachaRevealCloseTarget(pending)
    local spinner=PG and PG:FindFirstChild("SpinnerWindow")
    if not spinner or not PHX.guiVisible(spinner) then return nil,"SPINNER_NOT_VISIBLE" end
    local above=spinner:FindFirstChild("AboveSpinner")
    local navigation=above and above:FindFirstChild("Navigation")
    local button=navigation and navigation:FindFirstChild("CloseButton")
    if not button or not button:IsA("GuiButton") or not PHX.guiVisible(button)
        or button.AbsoluteSize.X<10 or button.AbsoluteSize.Y<10 then
        return nil,"PROBED_CLOSE_BUTTON_NOT_VISIBLE"
    end
    local enabled=true
    pcall(function() enabled=button.Interactable~=false end)
    if not enabled then return nil,"PROBED_CLOSE_BUTTON_DISABLED" end

    local selector=spinner:FindFirstChild("SelectorFrame")
    local frame=selector and selector:FindFirstChild("Frame")
    local template=frame and frame:FindFirstChild("AssetComponentTemplate")
    local filled=template and template:FindFirstChild("Filled")
    local info=filled and filled:FindFirstChild("ItemInformation")
    local item=info and info:FindFirstChild("ItemName")
    if not item or not PHX.guiVisible(item) then return nil,"REVEAL_RESULT_NOT_READY" end
    local result=PHX.compactText(item.Text)
    if result=="" then return nil,"REVEAL_RESULT_EMPTY" end

    if pending then
        local now=os.clock()
        if pending.LastRevealName~=result then
            pending.LastRevealName=result
            pending.LastRevealNameAt=now
        end
        if now-(pending.LastRevealNameAt or now)<0.75 then
            return nil,"REVEAL_LABEL_SETTLING"
        end
        if now-(tonumber(pending.StartedAt) or now)<3 then
            return nil,"WAIT_REVEAL_ANIMATION"
        end
    end
    return button,"PROBED_CLOSE_BUTTON_READY:"..tostring(result)
end

function PHX.gachaRevealXClosed()
    local spinner=PG and PG:FindFirstChild("SpinnerWindow")
    if not spinner or not PHX.guiVisible(spinner) then return true end
    local above=spinner:FindFirstChild("AboveSpinner")
    local navigation=above and above:FindFirstChild("Navigation")
    local close=navigation and navigation:FindFirstChild("CloseButton")
    return not close or not PHX.guiVisible(close)
end

function PHX.gachaRevealFireActivated(button)
    if not button or not button:IsA("GuiButton") then return false,"NOT_GUI_BUTTON" end
    if type(getconnections)=="function" then
        local ok,connections=pcall(function() return getconnections(button.Activated) end)
        if ok and type(connections)=="table" then
            for _,connection in ipairs(connections) do
                local enabled=true
                pcall(function() enabled=connection.Enabled~=false and connection.Connected~=false end)
                if enabled then
                    local fired=false
                    if connection.Fire then
                        fired=pcall(function() connection:Fire() end)
                    elseif connection.Function then
                        fired=pcall(function() connection.Function() end)
                    end
                    if fired then return true,"ACTIVATED_CONNECTION" end
                end
            end
        end
    end
    if type(firesignal)=="function" then
        local ok=pcall(function() firesignal(button.Activated) end)
        if ok then return true,"FIRESIGNAL_ACTIVATED" end
    end
    return false,"ACTIVATED_UNAVAILABLE"
end

function PHX.dismissGachaReveal(pending,ownsGui)
    if not pending or pending.CloseDone or pending.CloseBusy or not PHX.fruitServiceAlive() then return false end
    if os.clock()<(tonumber(pending.CloseNextAt) or 0) then return false end
    local runtime=PHX.Runtime
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (runtime and (runtime.InteractionHold or runtime.StartBusy or (runtime.FruitGuiBusy and not ownsGui))) then return false end
    local button,reason=PHX.gachaRevealCloseTarget(pending)
    if not button then
        if reason=="PROBED_CLOSE_BUTTON_NOT_VISIBLE" and pending.CloseAttempts and pending.CloseAttempts>0
            and PHX.gachaRevealXClosed() then
            pending.CloseDone=true
            logLine("GACHA_CLOSE_X","CLOSED_VERIFIED_AFTER_RETRY")
            return true
        end
        pending.RevealNeedsDismiss=true
        return false
    end
    local owner=not ownsGui and PHX.acquireLock(runtime,"FruitGuiBusy","FruitGuiBusy") or nil
    if not ownsGui and not owner then return false end
    pending.CloseBusy=true
    pending.CloseAttempts=(pending.CloseAttempts or 0)+1
    local attempt=pending.CloseAttempts
    local closed=false
    local method="NOT_SENT"
    local ok,err=pcall(function()
        local sent,backend=PHX.gachaRevealFireActivated(button)
        method=backend
        logLine("GACHA_CLOSE_X","attempt="..attempt.." | exact="..button:GetFullName().." | "..method)
        if sent then
            closed=PHX.waitGui(PHX.gachaRevealXClosed,1.6)
        end
        if not closed and PHX.guiVisible(button) then
            local mouseOk=PHX.stashInputClick(button)
            method="MOUSE_INSET_FALLBACK:"..tostring(mouseOk)
            logLine("GACHA_CLOSE_X","attempt="..attempt.." | "..method)
            if mouseOk then closed=PHX.waitGui(PHX.gachaRevealXClosed,1.6) end
        end
    end)
    if owner then PHX.releaseLock(owner) end
    pending.CloseBusy=false
    if not ok then logLine("GACHA_CLOSE_X","ERROR:"..tostring(err)) end
    if closed or PHX.gachaRevealXClosed() then
        pending.CloseDone=true
        pending.CloseAttempted=true
        pending.RevealNeedsDismiss=false
        logLine("GACHA_CLOSE_X","CLOSED_VERIFIED | attempt="..attempt)
        return true
    end
    pending.RevealNeedsDismiss=true
    pending.CloseNextAt=os.clock()+math.min(5,1.5*attempt)
    logLine("GACHA_CLOSE_X","NOT_CLOSED_YET | attempt="..attempt.." | will retry")
    return false
end

function PHX.watchGachaRevealAfterPurchase(pending)
    if not pending or pending.RevealWatchStarted then return end
    pending.RevealWatchStarted=true
    task.spawn(function()
        local deadline=os.clock()+120
        while PHX.fruitServiceAlive() and os.clock()<deadline do
            local spinner=PG and PG:FindFirstChild("SpinnerWindow")
            if spinner and PHX.guiVisible(spinner) then pending.SpinnerSeen=true end
            if pending.SpinnerSeen and PHX.dismissGachaReveal(pending,false) then break end
            if pending.CloseDone then break end
            task.wait(.30)
        end
        if pending.SpinnerSeen and not pending.CloseDone then
            logLine("GACHA_CLOSE_X","TIMEOUT: exact CloseButton still not confirmed closed")
        end
    end)
end

task.spawn(function()
    task.wait(2)
    if not PHX.fruitServiceAlive() then return end
    local spinner=PG and PG:FindFirstChild("SpinnerWindow")
    if not spinner or not PHX.guiVisible(spinner) then return end
    local oldPending=PHX.FruitAutoState and PHX.FruitAutoState.RollPending
    if oldPending and oldPending.SessionKey==PHX.FruitSessionKey then
        PHX.watchGachaRevealAfterPurchase(oldPending)
    else
        local recovery={StartedAt=os.clock()-4,SpinnerSeen=true,Recovery=true}
        PHX.watchGachaRevealAfterPurchase(recovery)
    end
end)

function PHX.observeFruitRoll()
    if not PHX.fruitServiceAlive() then return nil end
    local state=PHX.FruitAutoState
    local pending=state.RollPending or ENV.__PH_FRUIT_ROLL_PENDING
    if not pending then return nil end
    if pending.SessionKey~=PHX.FruitSessionKey then
        state.RollPending=nil
        if ENV.__PH_FRUIT_ROLL_PENDING==pending then ENV.__PH_FRUIT_ROLL_PENDING=nil end
        return nil
    end
    state.RollPending=pending
    local receipt=state.LastReceipt
    local name
    for _,tool in ipairs(PHX.findPhysicalFruits()) do
        if not pending.Previous[tool] then
            name=tool.Name
            if PHX.notifyValuableFruit then PHX.notifyValuableFruit(tool) end
            break
        end
    end
    if not name and (state.ReceiptSerial or 0)>pending.ReceiptBefore and receipt
        and receipt.At>=pending.StartedAt and not pending.Previous[receipt.Tool] then name=receipt.Name end
    if name then
        state.LastRandom=name
        state.RollPending=nil
        if ENV.__PH_FRUIT_ROLL_PENDING==pending then ENV.__PH_FRUIT_ROLL_PENDING=nil end
        logLine("FRUIT_RANDOM",pending.Backend.." | physical receipt: "..tostring(name))
        return true,name
    end
    if PHX.gachaSpinnerVisible() then pending.SpinnerSeen=true end
    state.Status=pending.RevealNeedsDismiss and "CLOSE_RANDOM_REVEAL_TO_RECEIVE_FRUIT"
        or pending.SpinnerSeen and "RANDOM_SPINNER_ACTIVE" or "RANDOM_WAITING_FOR_PHYSICAL_FRUIT"
    return false,"RANDOM_RESULT_PENDING"
end

function PHX.physicalFruitStoreOption(tool,ownsGui)
    if not PHX.isPhysicalFruitTool(tool) or not PHX.fruitStillLocal(tool) then return nil end
    local dialogue=PG and PG:FindFirstChild("DialogueGui")
    if not dialogue or not PHX.guiVisible or not PHX.guiVisible(dialogue) then return nil end
    local c=type(char)=="function" and char() or nil
    if not c or tool.Parent~=c then return nil end
    local equipped=0
    for _,object in ipairs(c:GetChildren()) do
        if PHX.isPhysicalFruitTool(object) then equipped=equipped+1 end
    end
    if equipped~=1 then return nil end
    local runtime=PHX.Runtime
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (runtime and (runtime.InteractionHold or runtime.StartBusy or (runtime.FruitGuiBusy and not ownsGui))) then return nil end
    local titled=false
    for _,object in ipairs(dialogue:GetDescendants()) do
        if object.Name=="dialogueTitleFrame" then
            local name=object:FindFirstChild("name")
            if name and (name:IsA("TextLabel") or name:IsA("TextButton")) and PHX.guiVisible(name)
                and PHX.compactText(name.Text)=="bloxfruit" then titled=true;break end
        end
    end
    if not titled then return nil end
    local options=type(dialogueOptions)=="function" and dialogueOptions() or {}
    if not PHX.dialogueOption(options,"Eat") or not PHX.dialogueOption(options,"Drop") then return nil end
    return PHX.dialogueOption(options,"Store")
end

function PHX.fruitStorageFullMenu(ownsGui)
    local dialogue=PG and PG:FindFirstChild("DialogueGui")
    if not dialogue or not PHX.guiVisible(dialogue) then return nil end
    local runtime=PHX.Runtime
    local guiOwner=runtime and runtime.LockOwners and runtime.LockOwners.FruitGuiBusy
    local ownsStartGui=runtime and runtime.StartBusy and ownsGui==true and PHX.ownsStartPreparation()
        and runtime.FruitGuiBusy==true and guiOwner and guiOwner.Container==runtime
        and guiOwner.Key=="FruitGuiBusy" and guiOwner.Name=="FruitGuiBusy"
        and guiOwner.Owner==coroutine.running()
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (runtime and (runtime.InteractionHold or (runtime.StartBusy and not ownsStartGui)
            or (runtime.FruitGuiBusy and not ownsGui))) then return nil end
    local titled=false
    for _,object in ipairs(dialogue:GetDescendants()) do
        if object.Name=="dialogueTitleFrame" then
            local name=object:FindFirstChild("name")
            if name and (name:IsA("TextLabel") or name:IsA("TextButton")) and PHX.guiVisible(name)
                and PHX.compactText(name.Text)=="bloxfruit" then titled=true;break end
        end
    end
    if not titled then return nil end
    local options=dialogueOptions()
    if not PHX.dialogueOption(options,"Upgrade") then return nil end
    local nevermind=PHX.dialogueOption(options,"Nevermind")
    return nevermind,dialogue
end

function PHX.fruitStorageFullOption(tool,ownsGui)
    if not PHX.isPhysicalFruitTool(tool) or not PHX.fruitStillLocal(tool) then return nil end
    return PHX.fruitStorageFullMenu(ownsGui)
end

function PHX.dismissFruitStorageFull(tool,ownsGui,token)
    if not PHX.fruitServiceAlive(token) then return false,nil end
    local button,dialogue=PHX.fruitStorageFullOption(tool,ownsGui)
    if not button then return false,nil end
    local owner=not ownsGui and PHX.acquireLock(PHX.Runtime,"FruitGuiBusy","FruitGuiBusy") or nil
    if not ownsGui and not owner then return false,"STORE_FULL_WAITING_FOR_GAME_INTERACTION" end
    local function dismiss()
        if not PHX.fruitServiceAlive(token) then return false,"STORE_FULL_CANCELED" end
        if PHX.fruitStorageFullOption(tool,true)~=button then return false,"STORE_FULL_DIALOGUE_CHANGED" end
        local clicked=PHX.activateOnce(button,PHX.stashInputClick)
        if clicked~=true then return false,"STORE_FULL_NEVERMIND_UNCONFIRMED" end
        local deadline=os.clock()+1.5
        repeat
            if not PHX.fruitServiceAlive(token) then return false,"STORE_FULL_CANCELED" end
            if not PHX.guiVisible(dialogue) or PHX.fruitStorageFullOption(tool,true)~=button then
                return true,"STORE_FULL_FRUIT_RETAINED"
            end
            task.wait(.05)
        until os.clock()>=deadline
        return false,"STORE_FULL_NEVERMIND_UNCONFIRMED"
    end
    local ok,closed,reason=pcall(dismiss)
    if owner then PHX.releaseLock(owner) end
    if not ok then return false,"STORE_FULL_NEVERMIND_ERROR: "..tostring(closed) end
    return closed,reason
end

function PHX.randomFruitContext(token, ownsGui, allowInventory, ownedTween)
    if PHX.isMovementLocked() then return false,"BOAT_PURCHASE_MOVEMENT_LOCKED" end
    if not PHX.fruitServiceAlive(token) or not PHX.FruitAutoState.Enabled then return false,"CANCELED" end
    if PHX.UserConfigState and PHX.UserConfigState.DesiredRunning and PHX.UserConfigState.ResumePending then
        return false,"WAITING_FOR_FARM_START"
    end
    if PHX.UserConfigState and PHX.UserConfigState.RestoredRandom and not PHX.userConfigRestoreReady() then
        return false,"WAITING_FOR_MARINES_AND_GAME_LOAD"
    end
    local runtime=PHX.Runtime
    if runtime and (runtime.UiReady==false or runtime.MarinesReady==false) then return false,"WAITING_FOR_MARINES_AND_GAME_LOAD" end
    if runtime and runtime.UiReady==true and PHX.startupStashReady and not PHX.startupStashReady() then
        return false,"WAITING_FOR_MARINES_AND_GAME_LOAD"
    end
    if PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy)
        or (PHX.StashScanQueue and (PHX.StashScanQueue.StartupPending or #(PHX.StashScanQueue.Jobs or {})>0))
        or (runtime and (runtime.InteractionHold or runtime.StartBusy or (runtime.FruitGuiBusy and not ownsGui))) then
        return false,"WAITING_FOR_GAME_INTERACTION"
    end
    if PHX.fruitStorageFullMenu(ownsGui) then return false,"FRUIT_STORAGE_FULL_NO_RANDOM_PURCHASE" end
    if not allowInventory and PHX.inventoryActuallyOpen and PHX.inventoryActuallyOpen() then return false,"CLOSE_INVENTORY_BEFORE_RANDOM_FRUIT" end
    if runtime then
        for tween in pairs(runtime.Tweens or {}) do
            if tween~=ownedTween then return false,"WAITING_FOR_TRAVEL_TO_FINISH" end
        end
    end
    if PHX.TravelState and (PHX.TravelState.Tween or PHX.TravelState.BoatMoving) then return false,"WAITING_FOR_TRAVEL_TO_FINISH" end
    local humanoid=type(hum)=="function" and hum() or nil
    if humanoid and (humanoid.Health<=0 or humanoid.SeatPart or humanoid.Sit) then return false,"LEAVE_BOAT_SEAT_BEFORE_RANDOM_FRUIT" end
    if type(ENV)=="table" and ENV.TeamConfig and ENV.TeamConfig.IsRunning then return false,"PAUSE_AUTO_VOLCANO_BEFORE_RANDOM_FRUIT" end
    if PHX.gachaSpinnerVisible() then return false,"RANDOM_SPINNER_ACTIVE" end
    return true
end

function PHX.prepareRandomFruitContext(token)
    local safe,why=PHX.randomFruitContext(token,true,true)
    if not safe then return false,why end
    if not PHX.inventoryActuallyOpen or not PHX.inventoryActuallyOpen() then return true end
    local close=PHX.inventoryCloseButton and PHX.inventoryCloseButton()
    local items=PHX.itemsHudButton and PHX.itemsHudButton()
    local function rendered(button)
        return button and (button:IsA("TextButton") or button:IsA("ImageButton")) and PHX.guiVisible(button)
            and button.AbsoluteSize.X>0 and button.AbsoluteSize.Y>0
    end
    local button=rendered(close) and close or rendered(items) and items
    if not button then return false,"RANDOM_CLOSE_INVENTORY_UNAVAILABLE" end
    PHX.FruitAutoState.Status="RANDOM_CLOSING_INVENTORY"
    if not PHX.activateOnce(button,PHX.stashInputClick) then return false,"RANDOM_CLOSE_INVENTORY_UNCONFIRMED" end
    local deadline=os.clock()+2
    repeat
        safe,why=PHX.randomFruitContext(token,true,true)
        if not safe then return false,why end
        if not PHX.inventoryActuallyOpen() then return true end
        task.wait(.05)
    until os.clock()>=deadline
    if PHX.inventoryActuallyOpen() and rendered(button) and PHX.activateOnce(button,function() return false end) then
        deadline=os.clock()+2
        repeat
            safe,why=PHX.randomFruitContext(token,true,true)
            if not safe then return false,why end
            if not PHX.inventoryActuallyOpen() then return true end
            task.wait(.05)
        until os.clock()>=deadline
    end
    return false,"RANDOM_CLOSE_INVENTORY_UNCONFIRMED"
end

function PHX.findZiolesNpc()
    local npcs=workspace and workspace:FindFirstChild("NPCs")
    local playerRoot=type(root)=="function" and root() or nil
    if not npcs or not playerRoot then return nil,"ZIOLES_NPC_NOT_FOUND" end
    local aliases={zioles=true,bloxfruitgacha=true,bloxfruitsgacha=true,bloxfruitdealercousin=true,dealercousin=true}
    local found={}
    for _,npc in ipairs(npcs:GetDescendants()) do
        if npc:IsA("Model") then
            local matched=aliases[PHX.compactText(npc.Name)]==true
            if not matched then
                for _,label in ipairs(npc:GetDescendants()) do
                    if label:IsA("TextLabel") and aliases[PHX.compactText(label.Text)] then
                        local ancestor=label.Parent
                        while ancestor and ancestor~=npc do
                            if ancestor:IsA("BillboardGui") then matched=true;break end
                            ancestor=ancestor.Parent
                        end
                        if matched then break end
                    end
                end
            end
            local part=matched and (npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart",true))
            if part and part.Parent then found[#found+1]={Npc=npc,Part=part,Distance=(playerRoot.Position-part.Position).Magnitude} end
        end
    end
    table.sort(found,function(a,b) return a.Distance<b.Distance end)
    if not found[1] then return nil,"ZIOLES_NPC_NOT_FOUND" end
    if found[2] and math.abs(found[2].Distance-found[1].Distance)<.1 then return nil,"ZIOLES_NPC_AMBIGUOUS" end
    return found[1].Npc,found[1].Part
end

function PHX.approachZiolesNpc(npc,part,range,token)
    if PHX.isMovementLocked() then return false,"BOAT_PURCHASE_MOVEMENT_LOCKED" end
    if CONFIG.FRUIT_AUTO.AutoApproachNPC==false then return false,"APPROACH_ZIOLES_FOR_RANDOM_FRUIT" end
    local character,humanoid,playerRoot=char(),hum(),root()
    if not character or not humanoid or not playerRoot or not part or not part.Parent then return false,"ZIOLES_INTERACTION_UNAVAILABLE" end
    local runtime=PHX.Runtime
    local original,tween,completedConnection={},nil,nil
    local oldAutoRotate=humanoid.AutoRotate
    local cleaned=false
    local function disconnectCompleted()
        if not completedConnection then return end
        if PHX.disconnect then PHX.disconnect(completedConnection)
        else pcall(function() completedConnection:Disconnect() end) end
        if runtime.MovementConnections then runtime.MovementConnections[completedConnection]=nil end
        completedConnection=nil
    end
    local clean
    clean=function()
        if cleaned then return end
        cleaned=true
        disconnectCompleted()
        if tween then pcall(function() tween:Cancel() end);runtime.Tweens[tween]=nil end
        for object,collidable in pairs(original) do
            if object.Parent then pcall(function()
                object.CanCollide=collidable
                object.AssemblyLinearVelocity=Vector3.zero
                object.AssemblyAngularVelocity=Vector3.zero
            end) end
            if runtime.CollisionOverrides then runtime.CollisionOverrides[object]=nil end
        end
        if humanoid.Parent and oldAutoRotate~=nil then pcall(function() humanoid.AutoRotate=oldAutoRotate end) end
        if runtime.FruitApproachCleanup==clean then runtime.FruitApproachCleanup=nil end
    end
    local function ready()
        if cleaned then return false,"CANCELED" end
        local safe,reason=PHX.randomFruitContext(token,true,false,tween)
        if not safe then return false,reason end
        if #PHX.findPhysicalFruits()>0 or next(PHX.FruitAutoState.Pending)~=nil
            or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then return false,"STORE_PHYSICAL_FRUIT_FIRST" end
        if char()~=character or hum()~=humanoid or root()~=playerRoot or humanoid.Health<=0
            or not playerRoot.Parent or not npc.Parent or not part.Parent then return false,"CANCELED" end
        return true
    end
    local function noclip()
        for _,object in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then
                if original[object]==nil then
                    original[object]=object.CanCollide
                    runtime.CollisionOverrides=runtime.CollisionOverrides or {}
                    runtime.CollisionOverrides[object]=object.CanCollide
                end
                object.CanCollide=false
                object.AssemblyLinearVelocity=Vector3.zero
                object.AssemblyAngularVelocity=Vector3.zero
            end
        end
    end
    local ok,arrived,why=pcall(function()
        local safe,reason=ready()
        if not safe then return false,reason end
        local speed=tonumber(CONFIG.PLAYER_TWEEN_SPEED) or 200
        if speed<=0 or speed~=speed or speed==math.huge then return false,"RANDOM_APPROACH_FAILED" end
        local started=os.clock()
        local offset=math.min(6,(tonumber(range) or 12)*.5)
        local function segment(goal,duration)
            local finished,playbackState=false,nil
            tween=TweenService:Create(playerRoot,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=goal})
            runtime.Tweens[tween]=true
            completedConnection=PHX.connect(tween.Completed,function(state)
                playbackState=state
                finished=true
            end)
            runtime.MovementConnections=runtime.MovementConnections or {}
            runtime.MovementConnections[completedConnection]=true
            tween:Play()
            while not finished do
                safe,reason=ready()
                if not safe then return false,reason end
                if os.clock()-started>120 then return false,"RANDOM_APPROACH_FAILED" end
                noclip()
                task.wait(.03)
            end
            disconnectCompleted()
            if playbackState~=Enum.PlaybackState.Completed then return false,"RANDOM_APPROACH_FAILED" end
            runtime.Tweens[tween]=nil
            tween=nil
            return ready()
        end
        runtime.FruitApproachCleanup=clean
        humanoid.AutoRotate=false
        noclip()
        PHX.FruitAutoState.Status="RANDOM_APPROACHING_ZIOLES"
        while os.clock()-started<=120 do
            safe,reason=ready()
            if not safe then return false,reason end
            local destination=(part.CFrame*CFrame.new(0,0,-offset)).Position
            local target=CFrame.lookAt(destination,part.Position)
            local from=playerRoot.CFrame
            local distance=(from.Position-target.Position).Magnitude
            if distance<=3 then
                safe,reason=segment(target,math.max(distance/speed,.03))
                if not safe then return false,reason end
                if (playerRoot.Position-part.Position).Magnitude<=range then return true end
            else
                local length=math.min(48,distance)
                safe,reason=segment(from:Lerp(target,length/distance),math.max(.04,length/speed))
                if not safe then return false,reason end
                task.wait(.015)
            end
        end
        return false,"RANDOM_APPROACH_FAILED"
    end)
    clean()
    if not ok then return false,"RANDOM_APPROACH_ERROR: "..tostring(arrived) end
    return arrived,why
end

function PHX.ziolesRandomOption()
    local dialogue=PG and PG:FindFirstChild("DialogueGui")
    if not dialogue or not PHX.guiVisible or not PHX.guiVisible(dialogue) then return nil,"OPEN_ZIOLES_RANDOM_FRUIT_MENU" end
    local titled=false
    for _,object in ipairs(dialogue:GetDescendants()) do
        if object.Name=="dialogueTitleFrame" then
            local name=object:FindFirstChild("name")
            if name and (name:IsA("TextLabel") or name:IsA("TextButton")) and PHX.guiVisible(name)
                and PHX.compactText(name.Text)=="zioles" then titled=true;break end
        end
    end
    if not titled then return nil,"OPEN_ZIOLES_RANDOM_FRUIT_MENU" end
    local options=type(dialogueOptions)=="function" and dialogueOptions() or {}
    local button=PHX.dialogueOption(options,"Random Fruit")
    if button then return button,"ZIOLES_RANDOM_OPTION" end
    local translation=dialogue:FindFirstChild("TranslationContext")
    if PHX.dialogueOption(options,"Upgrade") or (translation and PHX.compactText(translation.Text):find("storagefull",1,true)) then
        return nil,"FRUIT_STORAGE_FULL_NO_RANDOM_PURCHASE"
    end
    return nil,"ZIOLES_RANDOM_OPTION_NOT_READY"
end

function PHX.tryZiolesNativeInteract(token)
    local playerRoot=type(root)=="function" and root() or nil
    local npc,part=PHX.findZiolesNpc()
    if not npc or not playerRoot then return false,part or "ZIOLES_NPC_NOT_FOUND" end
    if not part then return false,"ZIOLES_INTERACTION_UNAVAILABLE" end
    local prompt=npc:FindFirstChildWhichIsA("ProximityPrompt",true)
    local detector=npc:FindFirstChildWhichIsA("ClickDetector",true)
    local range=prompt and prompt.Enabled and tonumber(prompt.MaxActivationDistance)
        or detector and tonumber(detector.MaxActivationDistance) or 12
    range=math.min(12,math.max(0,range or 0))
    if range<=0 then return false,"ZIOLES_INTERACTION_UNAVAILABLE" end
    if (playerRoot.Position-part.Position).Magnitude>range then
        local arrived,reason=PHX.approachZiolesNpc(npc,part,range,token)
        if not arrived then return false,reason end
    end
    local safe,why=PHX.randomFruitContext(token,true)
    if not safe then return false,why end
    if prompt and prompt.Enabled and type(PHX.holdInteraction)=="function" then
        local ok,result,reason=pcall(PHX.holdInteraction,prompt,(tonumber(prompt.HoldDuration) or 0)+.12,nil)
        return ok and result==true,ok and reason or "ZIOLES_INTERACTION_FAILED"
    end
    if detector and type(fireclickdetector)=="function" then
        local ok=pcall(function() fireclickdetector(detector) end)
        return ok,ok and "ZIOLES_CLICK_REQUESTED" or "ZIOLES_INTERACTION_FAILED"
    end
    if type(PHX.holdInteraction)=="function" then
        local ok,result,reason=pcall(PHX.holdInteraction,npc,.15,nil)
        return ok and result==true,ok and reason or "ZIOLES_INTERACTION_FAILED"
    end
    return false,"OPEN_ZIOLES_RANDOM_FRUIT_MENU"
end

function PHX.openZiolesGacha(token)
    local button,backend,window=PHX.gachaPurchaseTarget()
    if button or backend~="GACHA_CLOSED" then return button,backend,window end
    local option,why=PHX.ziolesRandomOption()
    if not option then
        if why~="OPEN_ZIOLES_RANDOM_FRUIT_MENU" then return nil,why end
        local interacted,reason=PHX.tryZiolesNativeInteract(token)
        if not interacted then return nil,reason end
        local deadline=os.clock()+3
        repeat
            local safe,canceled=PHX.randomFruitContext(token,true)
            if not safe then return nil,canceled end
            button,backend,window=PHX.gachaPurchaseTarget()
            if button or backend~="GACHA_CLOSED" then return button,backend,window end
            option,why=PHX.ziolesRandomOption()
            if option then break end
            task.wait(.05)
        until os.clock()>=deadline
        if not option then return nil,why or "ZIOLES_DIALOGUE_NOT_CONFIRMED" end
    end
    local safe,canceled=PHX.randomFruitContext(token,true)
    if not safe then return nil,canceled end
    if not PHX.activateOnce(option,PHX.stashInputClick) then return nil,"ZIOLES_OPTION_CLICK_FAILED" end
    local function waitWindow()
        local deadline=os.clock()+3
        repeat
            safe,canceled=PHX.randomFruitContext(token,true)
            if not safe then return nil,canceled end
            button,backend,window=PHX.gachaPurchaseTarget()
            if button then return button,backend,window end
            task.wait(.05)
        until os.clock()>=deadline
        return nil,backend~="GACHA_CLOSED" and backend or "GACHA_WINDOW_NOT_CONFIRMED",window
    end
    local ready,result,opened=waitWindow()
    if ready or result~="GACHA_WINDOW_NOT_CONFIRMED" then return ready,result,opened end
    local current,currentReason=PHX.ziolesRandomOption()
    if current~=option then return nil,currentReason or result,opened end
    if PHX.activateOnce(option,function() return false end) then return waitWindow() end
    return nil,result,opened
end

ENV.__PH_DIRECT_GACHA_LAST_SENT=tonumber(ENV.__PH_DIRECT_GACHA_LAST_SENT) or 0
ENV.__PH_DIRECT_GACHA_NEXT_READY=tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0

function PHX.directGachaRemote()
    local modules=ReplicatedStorage:FindFirstChild("Modules")
    local net=modules and modules:FindFirstChild("Net")
    local rf=net and net:FindFirstChild("RF/GachaNetworkRF")
    if rf and rf:IsA("RemoteFunction") then return rf end
    return nil
end

function PHX.gachaBeli()
    for _,folderName in ipairs({"Data","leaderstats"}) do
        local folder=LP:FindFirstChild(folderName)
        if folder then
            for _,name in ipairs({"Beli","Money"}) do
                local v=folder:FindFirstChild(name)
                if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
                    return tonumber(v.Value)
                end
            end
        end
    end
    return nil
end

function PHX.gachaToolSnapshot()
    local counts={}
    for _,container in ipairs({LP:FindFirstChild("Backpack"), LP.Character}) do
        if container then
            for _,item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then counts[item.Name]=(counts[item.Name] or 0)+1 end
            end
        end
    end
    return counts
end

function PHX.gachaNewTool(before)
    for name,count in pairs(PHX.gachaToolSnapshot()) do
        if count>(before[name] or 0) and string.lower(name):find("fruit",1,true) then
            return name
        end
    end
    return nil
end

function PHX.gachaPrepare(token, isManual)
    local rf=PHX.directGachaRemote()
    if not rf then return false,"V6_REMOTE_MISSING" end
    local requests={
        {SpokeNPC="Blox Fruit Gacha",Context="Check",BoxName="ZiolesGacha"},
        {Context="getGachaFromBoxName",BoxName="ZiolesGacha"},
        {Context="Check",BoxName="ZiolesGacha"},
    }
    for index,request in ipairs(requests) do
        if not PHX.fruitServiceAlive(token) or (not isManual and not PHX.FruitAutoState.Enabled) then
            return false,"CANCELED"
        end
        local ok,response=pcall(function() return rf:InvokeServer(request) end)
        logLine("GACHA_V6_PREPARE",index.."/3 : "..(ok and typeof(response) or tostring(response)))
        if not ok then return false,"PREPARE_"..index.."_FAILED" end
        task.wait(0.18)
    end
    return true,"PREPARE_OK"
end

function PHX.runGachaV6(token, manual, onlyPrepare)
    local state=PHX.FruitAutoState
    if not PHX.fruitServiceAlive(token) or (not manual and not state.Enabled) then return false,"CANCELED",true end
    if ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY then
        local started=tonumber(ENV.__PH_GACHA_GLOBAL_PURCHASE_STARTED)
        if started and os.clock()-started>120 then
            ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY=false
            logLine("GACHA_V6_RECOVERY","Expired local busy flag; saved cooldown still applies")
        else
            return false,"PURCHASE_BUSY",true
        end
    end
    if not onlyPrepare then
        local remaining=(tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0)-os.time()
        if remaining>0 then
            state.NextRandomAt=os.clock()+remaining
            return false,"RANDOM_COOLDOWN_"..math.ceil(remaining).."s",true
        end
    end
    local rf=PHX.directGachaRemote()
    if not rf then return false,"V6_REMOTE_MISSING",false end
    local prepared,reason=PHX.gachaPrepare(token,manual)
    if not prepared then return false,reason,false end
    if onlyPrepare then return true,"PREPARE_OK_NO_PURCHASE",true end
    if not PHX.fruitServiceAlive(token) or (not manual and not state.Enabled) then return false,"CANCELED",true end
    if not manual and (#PHX.findPhysicalFruits()>0 or next(state.Pending)~=nil) then
        return false,"STORE_PHYSICAL_FRUIT_FIRST",false
    end
    local beforeBeli=PHX.gachaBeli()
    local beforeTools=PHX.gachaToolSnapshot()
    local purchaseTime=os.time()
    local beforeReceipt=tonumber(state.ReceiptSerial) or 0
    local pending={Previous={},ReceiptBefore=beforeReceipt,StartedAt=os.clock(),
        Backend="V6_UNIFIED",SpinnerSeen=false,SessionKey=PHX.FruitSessionKey}
    for _,tool in ipairs(PHX.findPhysicalFruits()) do pending.Previous[tool]=true end
    state.RollPending=pending
    ENV.__PH_FRUIT_ROLL_PENDING=pending
    ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY=true
    ENV.__PH_GACHA_GLOBAL_PURCHASE_STARTED=os.clock()
    ENV.__PH_DIRECT_GACHA_LAST_SENT=purchaseTime
    ENV.__PH_DIRECT_GACHA_NEXT_READY=purchaseTime+7200
    state.NextRandomAt=os.clock()+7200
    local saved,saveWhy=PHX.saveUserConfig()
    if not saved then logLine("GACHA_CONFIG_WARN","Cooldown could not be persisted: "..tostring(saveWhy)) end
    state.Status="PURCHASE_SENT_WAITING_FOR_RECEIPT"
    logLine("GACHA_V6_PURCHASE","ONE Purchase to ZiolesGacha | NO TP | config="..tostring(saved))
    PHX.watchGachaRevealAfterPurchase(pending) -- survives early Beli/tool verification
    local ok,response=pcall(function()
        return rf:InvokeServer({Context="Purchase",BoxName="ZiolesGacha"})
    end)
    logLine("GACHA_V6_PURCHASE",ok and ("Result type="..typeof(response)) or ("ERROR="..tostring(response)))
    local deadline=os.clock()+math.max(8,tonumber(CONFIG.FRUIT_AUTO.RollVerifySeconds) or 35)
    local verified,detail=false,"NO_VERIFIED_CHANGE"
    while PHX.fruitServiceAlive(token) and os.clock()<deadline do
        local currentBeli=PHX.gachaBeli()
        if type(beforeBeli)=="number" and type(currentBeli)=="number" and currentBeli<beforeBeli then
            verified=true
            detail="BELI_DECREASED_"..tostring(beforeBeli-currentBeli)
            break
        end
        local newTool=PHX.gachaNewTool(beforeTools)
        if newTool then verified=true; detail="NEW_TOOL_"..newTool; break end
        local received,receivedName=PHX.observeFruitRoll()
        if received then verified=true;detail="RECEIPT_"..tostring(receivedName);break end
        if (tonumber(state.ReceiptSerial) or 0)>beforeReceipt then
            verified=true;detail="RECEIPT_OBSERVED";break
        end
        pending.SpinnerSeen=pending.SpinnerSeen or PHX.gachaSpinnerVisible()
        task.wait(.25)
    end
    if not verified and state.RollPending==pending then state.RollPending=nil end
    if not verified and ENV.__PH_FRUIT_ROLL_PENDING==pending then ENV.__PH_FRUIT_ROLL_PENDING=nil end
    ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY=false
    state.LastRandom=verified and detail or "UNVERIFIED"
    state.Status=verified and "GACHA_VERIFIED" or "V6_PURCHASE_UNVERIFIED_NO_RETRY"
    logLine("GACHA_V6_VERIFY",state.Status.." / "..detail)
    return verified,detail,true
end

function PHX.randomFruitOnce(token)
    return PHX.runGachaV6(token,false,false)
end

function PHX.manualGacha(onlyPrepare)
    return PHX.withFruitLock(function()
        return PHX.runGachaV6(nil,true,onlyPrepare)
    end)
end

function PHX.storeFruitSweep(token)
    local state=PHX.FruitAutoState
    local protected,why=PHX.storeValuableFruitSweep(token)
    if not protected then return false,why end
    if not state.AutoStore then return true,"AUTO_STORE_OFF" end
    local fruits=PHX.findPhysicalFruits()
    for _,tool in ipairs(fruits) do
        if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
        if PHX.valuableFruitKind(tool) then return false,"VALUABLE_FRUIT_REPLICATING" end
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
    local ok,result,reason,knownCooldown=pcall(callback)
    PHX.releaseLock(owner)
    if state.ValuableRequested and PHX.queueValuableFruitCheck then PHX.queueValuableFruitCheck() end
    if not ok then return false,"FRUIT_SERVICE_ERROR: "..tostring(result) end
    return result,reason,knownCooldown
end

function PHX.fruitRandomDeferredReason(reason)
    for _,waiting in ipairs({"STARTUP_UI_NOT_READY","WAITING_FOR_MARINES_AND_GAME_LOAD","WAITING_FOR_GAME_INTERACTION","WAITING_FOR_TRAVEL_TO_FINISH","WAITING_FOR_FARM_START",
        "LEAVE_BOAT_SEAT_BEFORE_RANDOM_FRUIT","PAUSE_AUTO_VOLCANO_BEFORE_RANDOM_FRUIT",
        "OPEN_ZIOLES_RANDOM_FRUIT_MENU","APPROACH_ZIOLES_FOR_RANDOM_FRUIT","STORE_PHYSICAL_FRUIT_FIRST",
        "CLOSE_INVENTORY_BEFORE_RANDOM_FRUIT",
        "ZIOLES_NPC_NOT_FOUND","ZIOLES_NPC_AMBIGUOUS","RANDOM_CLOSE_INVENTORY_UNAVAILABLE","RANDOM_CLOSE_INVENTORY_UNCONFIRMED","RANDOM_APPROACH_FAILED",
        "GACHA_PURCHASE_NOT_READY","GACHA_PURCHASE_DISABLED","ZIOLES_RANDOM_OPTION_NOT_READY",
        "FRUIT_STORAGE_FULL_NO_RANDOM_PURCHASE","RANDOM_SPINNER_ACTIVE","RANDOM_RESULT_PENDING"}) do
        if reason==waiting then return true end
    end
    return false
end

function PHX.fruitAutoTick(token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    return PHX.withFruitLock(function()
        local state=PHX.FruitAutoState
        if state.RollPending or ENV.__PH_FRUIT_ROLL_PENDING then
            local received=PHX.observeFruitRoll()
            if received==false and state.Enabled then PHX.dismissGachaReveal(state.RollPending) end
        end
        state.PhysicalCount=#PHX.findPhysicalFruits()
        local guarded,why=PHX.storeValuableFruitSweep(token)
        if not guarded then state.Status=why;return false,why end
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
        if state.Enabled and PHX.Runtime.UiReady and os.clock()>=(PHX.Runtime.ExecutedAt or os.clock())+7
            and os.clock()>=state.NextRandomAt and #PHX.findPhysicalFruits()==0 and next(state.Pending)==nil then
            local rolled,why,knownCooldown=PHX.randomFruitOnce(token)
            if not rolled and PHX.fruitRandomDeferredReason(why) then
                state.NextRandomAt=math.max(state.NextRandomAt or 0,os.clock()+5)
            elseif not rolled and why~="CANCELED" and not knownCooldown then
                state.RandomFailures=state.RandomFailures+1
                state.NextRandomAt=math.max(state.NextRandomAt or 0,
                    os.clock()+PHX.fruitRetryDelay(state.RandomFailures))
            elseif rolled then state.RandomFailures=0 end
            state.Status=rolled and "ROLLED: "..tostring(why) or why
        else
            if state.RollPending or ENV.__PH_FRUIT_ROLL_PENDING then
                state.Status=state.RollPending and state.RollPending.RevealNeedsDismiss and "CLOSE_RANDOM_REVEAL_TO_RECEIVE_FRUIT" or "RANDOM_RESULT_PENDING"
            elseif next(state.Pending)~=nil then state.Status="STORAGE_PENDING_VERIFICATION"
            elseif #PHX.findPhysicalFruits()>0 then state.Status=os.clock()<state.NextStoreAt and "STORE_BACKOFF" or "WAITING_TO_STORE"
            else state.Status=state.Enabled and "RANDOM_COOLDOWN" or "READY" end
        end
        state.PhysicalCount=#PHX.findPhysicalFruits()
        return true,state.Status
    end)
end

function PHX.setFruitAuto(enabled)
    PHX.FruitAutoState.Enabled=enabled==true;CONFIG.FRUIT_AUTO.Enabled=enabled==true
    if enabled then
        local remaining=math.max(0,(tonumber(ENV.__PH_DIRECT_GACHA_NEXT_READY) or 0)-os.time())
        PHX.FruitAutoState.NextRandomAt=os.clock()+remaining
    end
    return true,enabled and "Auto Random ON (saved; NO TP; cooldown persists)" or "Auto Random OFF (saved)"
end

function PHX.setAutoStore(enabled)
    PHX.FruitAutoState.AutoStore=enabled==true;CONFIG.FRUIT_AUTO.AutoStore=enabled==true
    if enabled then PHX.FruitAutoState.NextStoreAt=0 end
    return true,enabled and "Auto Store enabled locally" or "Auto Store disabled; Dragon, Kitsune and Leopard protection remains active"
end

function PHX.valuableStoragePending()
    local state=PHX.FruitAutoState
    for tool,pending in pairs(state and state.Pending or {}) do
        local id=type(pending)=="table" and string.lower(tostring(pending.Id or "")) or ""
        local kind=type(pending)=="table" and pending.Kind or nil
        if kind=="Dragon" or kind=="Kitsune" or kind=="Leopard"
            or id=="kitsune-kitsune" or id=="leopard-leopard" or id:find("dragon",1,true)
            or PHX.valuableFruitKind(tool) then return true end
    end
    return false
end

function PHX.automationReadyGuard(token)
    if not PHX.fruitServiceAlive(token) then return false,"CANCELED" end
    if PHX.PostRespawnStashPending then return false,"RESPAWN_STASH_REFRESH_REQUIRED" end
    if DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then
        return false,"DRAGON_STORAGE_UNVERIFIED"
    end
    if #PHX.findPhysicalDragonFruits()>0 or #PHX.findValuableFruits()>0 then
        return false,"VALUABLE_FRUIT_HELD"
    end
    if PHX.valuableStoragePending() then return false,"VALUABLE_STORAGE_UNVERIFIED" end
    local runtime,state=PHX.Runtime,PHX.FruitAutoState
    if (runtime and (runtime.FruitGuiBusy or runtime.InteractionHold)) or (state and state.Busy)
        or PHX.StashSyncBusy or PHX.CraftUiBusy or PHX.PortalTravel
        or (PHX.StashScanQueue and PHX.StashScanQueue.Busy) then
        return false,"WAITING_FOR_GAME_INTERACTION"
    end
    return PHX.fruitServiceAlive(token),"AUTOMATION_READY"
end

function PHX.resetProtectedFruitIdentity(tool)
    if not tool or not PHX.isPhysicalFruitTool(tool) then return nil end
    if PHX.isDragonFruitTool(tool) then return "Dragon" end
    for _,value in ipairs({
        tostring(tool.Name or ""), tostring(tool.ToolTip or ""),
        tostring(tool:GetAttribute("OriginalName") or ""),
        tostring(tool:GetAttribute("FruitName") or ""),
        tostring(tool:GetAttribute("ItemName") or "")
    }) do
        local key=string.lower(value)
        if key:find("dragon",1,true) then return "Dragon" end
        if key:find("kitsune",1,true) then return "Kitsune" end
        if key:find("leopard",1,true) then return "Leopard" end
    end
    return PHX.valuableFruitKind(tool)
end

function PHX.approveDuplicateOrdinaryReset()
    local state=PHX.FruitAutoState
    if not state or DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending
        or #PHX.findPhysicalDragonFruits()>0 or PHX.valuableStoragePending() then
        return false,"PROTECTED_FRUIT_PENDING"
    end
    local fruits=PHX.findPhysicalFruits()
    if #fruits==0 then
        if next(state.Pending)~=nil then return false,"STORE_PENDING_UNVERIFIED" end
        PHX.ResetOrdinaryApproval={}
        return true,"NO_PHYSICAL_FRUIT"
    end
    local inventory,why=PHX.readStoredFruitInventory()
    if not inventory then return false,"DUPLICATE_INVENTORY_UNKNOWN:"..tostring(why) end
    local approved={}
    for _,tool in ipairs(fruits) do
        if PHX.resetProtectedFruitIdentity(tool) then
            return false,"PROTECTED_FRUIT_HELD:"..tostring(tool.Name)
        end
        local record=state.Pending[tool]
        local provenFull=type(record)=="table" and record.StorageFullVerified==true
            and record.FullReason=="STORE_FULL_FRUIT_RETAINED"
        local provenFailed=type(record)=="table" and record.StoreFailedWithDuplicate==true
            and tonumber(record.StoreAttemptedAt)~=nil and tonumber(record.StoreFailedAt)~=nil
        if not provenFull and not provenFailed then
            return false,"ORDINARY_STORE_NOT_ATTEMPTED_OR_UNVERIFIED:"..tostring(tool.Name)
        end
        local id=PHX.fruitStoreId(tool,inventory)
        local canonical=string.lower(tostring(id or ""))
        local prior=tonumber(record.Before) or 0
        local currentlyStored=tonumber(inventory.Counts[canonical]) or 0
        if canonical=="" or canonical~=string.lower(tostring(record.Id or ""))
            or canonical=="dragon-dragon" or canonical=="kitsune-kitsune"
            or canonical=="leopard-leopard" or prior<1 or currentlyStored<1 then
            return false,"DUPLICATE_FRUIT_PROOF_MISSING:"..tostring(tool.Name)
        end
        approved[tool]=canonical
    end
    for tool in pairs(state.Pending) do
        if not approved[tool] then return false,"OTHER_STORE_PENDING_UNVERIFIED" end
    end
    PHX.ResetOrdinaryApproval=approved
    logLine("FRUIT_RESET_POLICY", "ALLOW duplicate ordinary fruit(s)="..tostring(#fruits).." | same-type inventory + failed Store")
    return true,"DUPLICATE_ORDINARY_CONFIRMED"
end

function PHX.finalFruitResetGuard()
    if DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then return false,"DRAGON_PENDING" end
    local state=PHX.FruitAutoState
    if not state or state.Busy or #PHX.findPhysicalDragonFruits()>0 then return false,"FRUIT_SERVICE_BUSY_OR_DRAGON" end
    local fruits=PHX.findPhysicalFruits()
    local approved=PHX.ResetOrdinaryApproval or {}
    for _,tool in ipairs(fruits) do
        if PHX.resetProtectedFruitIdentity(tool) then return false,"PROTECTED_FRUIT_HELD" end
        local record=state.Pending[tool]
        if not approved[tool] or not record
            or not (record.StorageFullVerified or record.StoreFailedWithDuplicate)
            or approved[tool]~=string.lower(tostring(record.Id or "")) then
            return false,"FRUIT_NOT_APPROVED_FOR_RESET"
        end
    end
    for tool in pairs(state.Pending) do
        if not approved[tool] then return false,"UNKNOWN_STORE_PENDING" end
    end
    return true,"SAFE_RESET"
end

function PHX.safeResetGuard(token)
    PHX.ResetOrdinaryApproval=nil
    if not PHX.fruitServiceAlive(token) then return false end
    if PHX.reconcileDragonPending then
        local ok=pcall(PHX.reconcileDragonPending)
        if not ok then return false end
    end
    if DRAGON_GUARD_STATE.Critical or DRAGON_GUARD_STATE.Pending then return false end
    local ok,reason=PHX.withFruitLock(function()
        local stored,why=PHX.storeFruitSweep(token)
        if stored then
            return PHX.approveDuplicateOrdinaryReset()
        end
        PHX.FruitAutoState.Status=tostring(why)
        local exempt,exemptWhy=PHX.approveDuplicateOrdinaryReset()
        if exempt then
            logLine("FRUIT_RESET_POLICY", "Ordinary duplicate cannot be stored; reset permitted")
            return true,exemptWhy
        end
        logLine("FRUIT_RESET_BLOCKED", tostring(why).." | "..tostring(exemptWhy))
        return false,exemptWhy
    end)
    if not ok then
        PHX.ResetOrdinaryApproval=nil
        return false
    end
    local final,why=PHX.finalFruitResetGuard()
    if not final then
        logLine("FRUIT_RESET_BLOCKED",tostring(why))
        PHX.ResetOrdinaryApproval=nil
    end
    return final==true and PHX.fruitServiceAlive(token)
end

function PHX.queueValuableFruitCheck()
    if not PHX.fruitServiceAlive() then return end
    local state=PHX.FruitAutoState
    state.ValuableRequested=true
    if state.ValuableQueued then return end
    state.ValuableQueued=true
    PHX.defer(function()
        task.wait(.05)
        state.ValuableQueued=false
        if not PHX.fruitServiceAlive() then return end
        PHX.notifyPhysicalValuables()
        if state.Busy then return end
        state.ValuableRequested=false
        local ok,reason=PHX.withFruitLock(function() return PHX.storeValuableFruitSweep() end)
        if not ok then state.Status=reason end
        state.PhysicalCount=#PHX.findPhysicalFruits()
    end)
end

PHX.FruitContainers=setmetatable({}, {__mode="k"})
function PHX.hookFruitContainer(container)
    if not container or PHX.FruitContainers[container] then return end
    PHX.FruitContainers[container]=true
    PHX.connect(container.DescendantAdded,function(obj)
        local tool=obj:IsA("Tool") and obj or obj:FindFirstAncestorWhichIsA("Tool")
        if tool then PHX.recordPhysicalFruitReceipt(tool);PHX.queueValuableFruitCheck() end
    end)
    for _,tool in ipairs(container:GetDescendants()) do PHX.recordPhysicalFruitReceipt(tool) end
    PHX.queueValuableFruitCheck()
end

PHX.hookFruitContainer(LP:FindFirstChild("Backpack"))
PHX.hookFruitContainer(char())
PHX.connect(LP.ChildAdded,function(obj)
    if obj:IsA("Backpack") then PHX.hookFruitContainer(obj) end
end)
PHX.connect(LP.CharacterAdded,function(c) PHX.hookFruitContainer(c) end)

PHX.spawn(function()
    while PHX.fruitServiceAlive() do
        PHX.fruitAutoTick()
        task.wait(math.max(5,tonumber(CONFIG.FRUIT_AUTO.TickSeconds) or 5))
    end
end)
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
                if CONFIG.DEBUG.WEBHOOK_ERRORS and not PHX.Runtime.AutomationBlockedReason then
                    sendWebhook("⚠️ PREHISTORIC WATCHDOG", "Automation appears stalled on "..LP.Name, {
                        {name="State", value=tostring(NIGHT.LastStatus), inline=false},
                        {name="Stalled", value=string.format("%.0fs", stalled), inline=true},
                        {name="Region", value=tostring(getRegion()), inline=true},
                    })
                end

                if PHX.Runtime.AutomationBlockedReason then
                    NIGHT.LastProgressAt = os.clock()
                    logLine("WATCHDOG", "Waiting prerequisite "..tostring(PHX.Runtime.AutomationBlockedReason).." -> keep current runner")
                elseif eventActive then
                    if PHX.afkSoloEnabled() then
                        if stalled>=240 and not DRAGON_GUARD_STATE.Critical then
                            restartNightStateMachine("AFK SOLO raid stalled for "..math.floor(stalled).."s; restart loop, NO character reset")
                        elseif os.clock()-(NIGHT.LastAFKStallWarnAt or 0)>30 then
                            NIGHT.LastAFKStallWarnAt=os.clock()
                            logLine("WATCHDOG", "AFK active raid unchanged; watchdog will restart controller after 240s")
                        end
                    else
                        NIGHT.LastProgressAt = os.clock()
                        logLine("WATCHDOG", "Active Volcano event -> logging only, no forced restart")
                    end
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

function PHX.buildUI()
    if not PHX.generationAlive() then return end
    local U = {Pages = {}, Tabs = {}, Sections = {}, EmptySearch = {}, CrewRows = {}, PlayerRows = {}, PlayerExiting = {}, Toggles = {}, InputNodes = {}, LastActivity = "", SyncBusy = false, LastSyncAt = -math.huge, PlayersDirty = true}
    PHX.UI = U
    local Input = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local Players = game:GetService("Players")
    local C = {
        Background = Color3.fromRGB(14, 19, 29), Surface = Color3.fromRGB(21, 28, 40),
        Raised = Color3.fromRGB(29, 39, 54), Border = Color3.fromRGB(43, 69, 88),
        Text = Color3.fromRGB(230, 238, 246), Muted = Color3.fromRGB(137, 154, 173),
        Pink = Color3.fromRGB(105, 199, 244), PinkSoft = Color3.fromRGB(18, 28, 41),
        Cyan = Color3.fromRGB(66, 190, 241), CyanSoft = Color3.fromRGB(22, 66, 89),
        Lavender = Color3.fromRGB(89, 173, 227), LavenderSoft = Color3.fromRGB(24, 54, 77),
        Amber = Color3.fromRGB(236, 184, 96), AmberSoft = Color3.fromRGB(65, 48, 27),
        Red = Color3.fromRGB(246, 116, 127), RedSoft = Color3.fromRGB(65, 31, 43),
    }
    local function make(className, props, parent)
        local object = Instance.new(className)
        for key, value in pairs(props or {}) do object[key] = value end
        if object:IsA("GuiObject") then object.Active = false end
        object.Parent = parent
        return object
    end
    local function round(object, radius)
        make("UICorner", {CornerRadius = UDim.new(0, radius or 5)}, object)
    end
    local function outline(object, color, transparency)
        return make("UIStroke", {Color = color or C.Border, Thickness = 1, Transparency = transparency or 0.15}, object)
    end
    local function text(parent, value, size, color, position, dimensions, weight)
        return make("TextLabel", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Text = value or "",
            TextColor3 = color or C.Text, Font = weight or Enum.Font.Gotham,
            TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true, RichText = false, LineHeight = 1.12,
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
        round(object, 4)
        outline(object)
        return object
    end
    local function card(parent, height, order, keywords)
        local object = make("Frame", {
            Size = UDim2.new(1, 0, 0, height), LayoutOrder = order or 0,
            BackgroundColor3 = C.Surface, BorderSizePixel = 0,
        }, parent)
        round(object, 5)
        outline(object)
        U.Sections[#U.Sections + 1] = {Object = object, Page = parent.Name, Keywords = string.lower(keywords or "")}
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
        round(object, 4)
        outline(object)
        make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, multiline and 8 or 0)}, object)
        return object
    end
    local function sourceLabel(source)
        if not source or source == "UNAVAILABLE" or source == "UNKNOWN" then return "CHƯA XÁC NHẬN" end
        if tostring(source):find("DIRECT_CACHE_NO_RECORD", 1, true) then return "0 / CHƯA REPLICATE" end
        if tostring(source):find("DIRECT_CACHE", 1, true) then return "CACHE LIVE" end
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
        text(parent, title, 12, C.Text, UDim2.fromOffset(11, y), UDim2.new(1, -64, 0, 19), Enum.Font.GothamMedium)
        text(parent, description, 10, C.Muted, UDim2.fromOffset(11, y + 20), UDim2.new(1, -64, 0, 27))
        local control = button(parent, "OFF", UDim2.new(1, -43, 0, y + 7), UDim2.fromOffset(32, 32), C.Raised)
        control.TextSize = 9
        U.Toggles[#U.Toggles + 1] = {Control = control, Read = read, RoleLock = roleLock == true, Stroke = control:FindFirstChildOfClass("UIStroke")}
        PHX.connect(control.Activated, function()
            if U.PassThrough then return end
            if roleLock and (ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy or U.SyncBusy) then
                U.notice("Tắt Auto Volcano trước khi đổi role.", false)
                return
            end
            local ok, message = write(not read())
            if ok ~= false and PHX.saveUserConfig then PHX.saveUserConfig() end
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
        Name = "VolcanoDarkDashboard", BackgroundColor3 = C.Background, BorderSizePixel = 0,
        Size = UDim2.fromOffset(690, 520), ClipsDescendants = true,
    }, U.Screen)
    round(U.Root, 6)
    outline(U.Root, C.Cyan, 0.2)
    local header = inputNode(make("Frame", {
        Name = "DragHeader", BackgroundColor3 = C.Surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 50),
    }, U.Root))
    make("Frame", {BackgroundColor3 = C.Cyan, BackgroundTransparency = 0.55, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1)}, header)
    U.Brand = text(header, "VOLCANO TEAM", 15, C.Text, UDim2.fromOffset(14, 8), UDim2.fromOffset(163, 22), Enum.Font.GothamBold)
    U.Version = text(header, "V2.17.10 / NET + BRING", 9, C.Muted, UDim2.fromOffset(14, 30), UDim2.fromOffset(170, 14))
    U.StatePill = text(header, "READY", 10, C.Cyan, UDim2.new(1, -129, 0, 8), UDim2.fromOffset(78, 21), Enum.Font.GothamBold)
    U.StatePill.BackgroundTransparency = 0
    U.StatePill.BackgroundColor3 = C.Raised
    U.StatePill.TextXAlignment = Enum.TextXAlignment.Center
    round(U.StatePill, 4)
    U.RolePill = text(header, "CHƯA CÓ ROLE", 9, C.Muted, UDim2.new(1, -253, 0, 30), UDim2.fromOffset(202, 14), Enum.Font.GothamMedium)
    U.RolePill.TextXAlignment = Enum.TextXAlignment.Right
    local minimize = button(header, "−", UDim2.new(1, -39, 0, 9), UDim2.fromOffset(28, 28), C.Raised)
    minimize.TextSize = 18
    U.SidebarToggle = button(header, "≡", UDim2.fromOffset(10, 31), UDim2.fromOffset(28, 24), C.Raised)
    U.SidebarToggle.TextSize = 18
    U.SidebarToggle.Visible = false

    U.Sidebar = make("Frame", {
        Name = "NavigationSidebar", BackgroundColor3 = C.Surface, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 50), Size = UDim2.new(0, 166, 1, -50), ZIndex = 5,
    }, U.Root)
    make("Frame", {BackgroundColor3 = C.Cyan, BackgroundTransparency = 0.65, BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0)}, U.Sidebar)
    U.Search = field(U.Sidebar, "", "Tìm cài đặt...", UDim2.fromOffset(10, 14), UDim2.new(1, -20, 0, 31))
    U.Search.Name = "SidebarSearch"
    U.Search.TextSize = 10
    U.NavHeading = text(U.Sidebar, "MENU", 9, C.Muted, UDim2.fromOffset(12, 58), UDim2.new(1, -24, 0, 17), Enum.Font.GothamBold)
    local navigation = make("Frame", {Name = "SidebarNavigation", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 82), Size = UDim2.new(1, -20, 0, 184)}, U.Sidebar)
    U.PageTitle = text(U.Root, "Tổng quan", 19, C.Text, UDim2.fromOffset(183, 59), UDim2.new(1, -199, 0, 25), Enum.Font.GothamBold)
    U.PageSubtitle = text(U.Root, "Trạng thái thuyền, vật liệu và sự kiện", 10, C.Muted, UDim2.fromOffset(183, 85), UDim2.new(1, -199, 0, 16))
    U.SearchResult = text(U.Sidebar, "", 9, C.Muted, UDim2.new(0, 12, 1, -87), UDim2.new(1, -24, 0, 22))
    U.SidebarFooter = text(U.Sidebar, "V2.17.10\n" .. tostring(LP.Name), 10, C.Muted, UDim2.new(0, 12, 1, -58), UDim2.new(1, -24, 0, 43), Enum.Font.GothamMedium)
    local pageInfo = {
        LIVE = {Title = "Tổng quan", Subtitle = "Trạng thái thuyền, vật liệu và sự kiện"},
        CREW = {Title = "Đội / Master", Subtitle = "Chọn Master để làm Slave, hoặc bật role Master"},
        SETTINGS = {Title = "Cài đặt", Subtitle = "Tùy chọn tự động, trái cây và Discord"},
        ACTIVITY = {Title = "Nhật ký", Subtitle = "Kiểm tra vật liệu và hoạt động gần đây"},
    }
    function U.setSidebar(value)
        U.SidebarOpen = value == true
        U.Sidebar.Visible = not U.Narrow or U.SidebarOpen
    end
    function U.selectPage(name, keepSidebar)
        if not U.Pages[name] then return end
        U.CurrentPage = name
        for key, frame in pairs(U.Pages) do frame.Visible = key == name end
        for key, control in pairs(U.Tabs) do
            control.BackgroundColor3 = key == name and C.CyanSoft or C.Surface
            control.TextColor3 = key == name and C.Cyan or C.Muted
            local stroke = control:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = key == name and C.Cyan or C.Border; stroke.Transparency = key == name and 0.2 or 0.65 end
        end
        U.PageTitle.Text = pageInfo[name].Title
        U.PageSubtitle.Text = pageInfo[name].Subtitle
        if U.Narrow and not keepSidebar then U.setSidebar(false) end
    end
    for index, entry in ipairs({{"LIVE", "Tổng quan"}, {"CREW", "Đội / Master"}, {"SETTINGS", "Cài đặt"}, {"ACTIVITY", "Nhật ký"}}) do
        local name = entry[1]
        local tab = button(navigation, entry[2], UDim2.fromOffset(0, (index - 1) * 45), UDim2.new(1, 0, 0, 36), C.Surface)
        tab.Name = "Navigate_" .. name
        tab.TextSize = 11
        tab.TextXAlignment = Enum.TextXAlignment.Left
        make("UIPadding", {PaddingLeft = UDim.new(0, 11)}, tab)
        U.Tabs[name] = tab
        local page = inputNode(make("ScrollingFrame", {
            Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(180, 109), Size = UDim2.new(1, -194, 1, -175),
            CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3, ScrollBarImageColor3 = C.Cyan,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = index == 1,
        }, U.Root))
        make("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        make("UIPadding", {PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 8)}, page)
        U.Pages[name] = page
        local empty = text(page, "Không tìm thấy mục phù hợp.\nThử từ khóa khác trong ô tìm kiếm.", 11, C.Muted, UDim2.fromOffset(0, 0), UDim2.new(1, -12, 0, 65))
        empty.Name = "NoSearchResults"
        empty.LayoutOrder = 999
        empty.Visible = false
        U.EmptySearch[name] = empty
        PHX.connect(tab.Activated, function() if not U.PassThrough then U.selectPage(name) end end)
    end
    U.selectPage("LIVE")
    PHX.connect(U.SidebarToggle.Activated, function()
        if not U.PassThrough then U.setSidebar(not U.SidebarOpen) end
    end)
    function U.applySearch()
        local query = string.lower(tostring(U.Search.Text or "")):match("^%s*(.-)%s*$")
        local matches, total = {}, 0
        for _, entry in ipairs(U.Sections) do
            local visible = query == "" or entry.Keywords:find(query, 1, true) ~= nil
            entry.Object.Visible = visible
            if visible then matches[entry.Page] = (matches[entry.Page] or 0) + 1; total = total + 1 end
        end
        for name, empty in pairs(U.EmptySearch) do empty.Visible = not matches[name] end
        U.SearchResult.Text = query ~= "" and (tostring(total) .. " mục phù hợp") or ""
        if query ~= "" and not matches[U.CurrentPage] then
            for _, name in ipairs({"LIVE", "CREW", "SETTINGS", "ACTIVITY"}) do
                if matches[name] then U.selectPage(name, true); break end
            end
        end
    end
    PHX.connect(U.Search:GetPropertyChangedSignal("Text"), function() if not U.PassThrough then U.applySearch() end end)

    local overview = U.Pages.LIVE
    local modeCard = card(overview, 77, 0, "solo team auto volcano một tài khoản master slave chế độ")
    U.ModeTitle = text(modeCard, "AUTO VOLCANO · TEAM / SOLO", 10, C.Cyan, UDim2.fromOffset(11, 6), UDim2.new(1, -22, 0, 19), Enum.Font.GothamBold)
    U.ModeHint = text(modeCard, "Team: Master + ít nhất 3 Slave. Solo: tự farm Magnet, mua thuyền và đánh Prehistoric.", 10, C.Muted, UDim2.fromOffset(11, 29), UDim2.new(1, -22, 0, 40))
    local status = card(overview, 118, 1, "trạng thái status ready volcano auto")
    status.AutomaticSize = Enum.AutomaticSize.Y
    make("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10)}, status)
    make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, status)
    U.Phase = text(status, "TRẠNG THÁI / READY", 10, C.Lavender, UDim2.fromOffset(11, 5), UDim2.new(1, -22, 0, 17), Enum.Font.GothamBold)
    STATUS_LABEL = text(status, "Sẵn sàng · Auto Volcano đang tắt", 12, C.Text, UDim2.fromOffset(11, 27), UDim2.new(1, -22, 0, 77), Enum.Font.GothamMedium)
    STATUS_LABEL.Name = "RuntimeStatus"
    STATUS_LABEL.LineHeight = 1.2
    STATUS_LABEL.TextYAlignment = Enum.TextYAlignment.Top
    STATUS_LABEL.AutomaticSize = Enum.AutomaticSize.Y
    STATUS_LABEL.LayoutOrder = 2
    STATUS_LABEL.Size = UDim2.new(1, 0, 0, 77)
    U.Phase.LayoutOrder = 1
    U.Phase.Size = UDim2.new(1, 0, 0, 17)

    local resources = card(overview, 72, 2, "vật liệu materials inventory túi đồ magnet scrap ember")
    local function material(index, title, accent)
        local host = make("Frame", {BackgroundTransparency = 1, Position = UDim2.new((index - 1) / 3, 0, 0, 0), Size = UDim2.new(1 / 3, 0, 1, 0)}, resources)
        text(host, title, 9, C.Muted, UDim2.fromOffset(10, 6), UDim2.new(1, -15, 0, 16), Enum.Font.GothamBold)
        local value = text(host, "--", 19, accent, UDim2.fromOffset(10, 23), UDim2.new(1, -15, 0, 25), Enum.Font.GothamBold)
        local source = text(host, "CHƯA XÁC NHẬN", 8, C.Muted, UDim2.fromOffset(10, 50), UDim2.new(1, -15, 0, 13))
        if index < 3 then make("Frame", {BackgroundColor3 = C.Border, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 12), Size = UDim2.new(0, 1, 1, -24)}, host) end
        return {Value = value, Source = source}
    end
    U.Magnet = material(1, "MAGNET", C.Cyan)
    U.Scrap = material(2, "SCRAP / 10", C.Lavender)
    U.Ember = material(3, "EMBER / 15", C.Red)
    COUNTER_LABEL = text(resources, "", 8, C.Muted, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0))
    COUNTER_LABEL.Visible = false

    local journey = card(overview, 91, 3, "thuyền boat grand brigade hp sea telemetry")
    U.BoatTitle = text(journey, "GRAND BRIGADE", 10, C.Cyan, UDim2.fromOffset(11, 5), UDim2.new(0.65, -12, 0, 18), Enum.Font.GothamBold)
    U.BoatHP = text(journey, "HP -- / --", 11, C.Text, UDim2.new(0.65, 0, 0, 5), UDim2.new(0.35, -11, 0, 18), Enum.Font.GothamBold)
    U.BoatTitle.TextWrapped = false
    U.BoatTitle.TextTruncate = Enum.TextTruncate.AtEnd
    U.BoatHP.TextXAlignment = Enum.TextXAlignment.Right
    U.BoatState = text(journey, "WAIT_MASTER · cần Master + 3 Slave", 10, C.Muted, UDim2.fromOffset(11, 28), UDim2.new(1, -22, 0, 24))
    U.SeaState = text(journey, "SEA 6 · giữ một hướng thẳng", 10, C.Cyan, UDim2.fromOffset(11, 56), UDim2.new(1, -22, 0, 27))

    local event = card(overview, 119, 4, "volcano sự kiện event timer pressure relic golem hp")
    local function metric(x, y, title, accent)
        local host = make("Frame", {BackgroundTransparency = 1, Position = UDim2.new(x, 0, 0, y), Size = UDim2.new(0.5, 0, 0, 49)}, event)
        text(host, title, 9, C.Muted, UDim2.fromOffset(11, 4), UDim2.new(1, -22, 0, 15), Enum.Font.GothamBold)
        local value = text(host, "--", 17, accent, UDim2.fromOffset(11, 21), UDim2.new(1, -22, 0, 24), Enum.Font.GothamBold)
        return value
    end
    U.Timer = metric(0, 3, "EVENT TIMER", C.Lavender)
    U.Pressure = metric(0.5, 3, "PRESSURE", C.Red)
    U.Relic = metric(0, 55, "RELIC HP", C.Cyan)
    U.Golems = metric(0.5, 55, "GOLEMS / TOTAL HP", C.Lavender)
    U.Golems.TextSize = 13
    make("Frame", {BackgroundColor3 = C.Border, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.fromOffset(11, 54), Size = UDim2.new(1, -22, 0, 1)}, event)

    local rewards = card(overview, 90, 5, "phần thưởng rewards egg trứng recovery phục hồi")
    U.EggState = text(rewards, "EGG · chưa có phần thưởng", 11, C.Pink, UDim2.fromOffset(11, 5), UDim2.new(1, -22, 0, 22), Enum.Font.GothamBold)
    U.Recovery = text(rewards, "RECOVERY · READY", 10, C.Muted, UDim2.fromOffset(11, 32), UDim2.new(1, -22, 0, 48))

    local crew = U.Pages.CREW
    local presence = card(crew, 136, 1, "đội crew online master slave role aboard")
    U.CrewPresence = presence
    U.CrewHeading = text(presence, "MASTER + ÍT NHẤT 3 SLAVE ĐỂ RA KHƠI", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.CrewSummary = text(presence, "Chưa chỉ định Master · client này chưa có role", 10, C.Cyan, UDim2.fromOffset(11, 28), UDim2.new(1, -22, 0, 24))
    function U.createCrewRow(index)
        local row = make("Frame", {BackgroundColor3 = C.Background, BorderSizePixel = 0, Position = UDim2.fromOffset(9, 60 + (index - 1) * 41), Size = UDim2.new(1, -18, 0, 36)}, presence)
        round(row, 4)
        local name = text(row, "", 11, C.Text, UDim2.fromOffset(9, 2), UDim2.new(1, -95, 0, 17), Enum.Font.GothamMedium)
        name.TextWrapped = false
        name.TextTruncate = Enum.TextTruncate.AtEnd
        local role = text(row, "", 8, C.Muted, UDim2.fromOffset(9, 20), UDim2.new(1, -95, 0, 13))
        local state = text(row, "OFFLINE", 8, C.Muted, UDim2.new(1, -88, 0, 9), UDim2.fromOffset(80, 18), Enum.Font.GothamBold)
        state.TextXAlignment = Enum.TextXAlignment.Right
        local entry = {Object = row, Name = name, Role = role, State = state}
        U.CrewRows[index] = entry
        return entry
    end
    U.CrewNote = text(presence, "Đội cập nhật theo thuyền. Slave còn lại có thể farm Magnet.", 9, C.Muted, UDim2.fromOffset(11, 101), UDim2.new(1, -22, 0, 30))
    local masterCard = card(crew, 239, 2, "master role driver username tài khoản chọn player online")
    text(masterCard, "MASTER / MUA THUYỀN + LÁI", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.MasterBox = field(masterCard, tostring(CONFIG.MASTER_NAME or ""), "Chưa chọn Master", UDim2.fromOffset(11, 31), UDim2.new(1, -96, 0, 34))
    U.ApplyMaster = button(masterCard, "CHỌN", UDim2.new(1, -76, 0, 31), UDim2.fromOffset(65, 34), C.CyanSoft)
    U.RoleLabel = text(masterCard, "", 9, C.Muted, UDim2.fromOffset(11, 70), UDim2.new(1, -22, 0, 24))
    U.LocalMasterToggle = toggle(masterCard, 101, "Add role Master", "Bật: client này mua và lái thuyền.", function()
        return PHX.localRole() == "MASTER"
    end, function(value)
        local ok, message = PHX.setLocalMaster(value)
        if ok then U.syncCrewFields() end
        return ok, message
    end, true)
    U.PlayerMenu = button(masterCard, "CHỌN MASTER TỪ PLAYER ONLINE  ▾", UDim2.fromOffset(11, 162), UDim2.new(1, -22, 0, 34), C.LavenderSoft)
    U.PlayerMenu.TextSize = 10
    U.PlayerList = inputNode(make("ScrollingFrame", {
        Name = "OnlineMasterMenu", BackgroundColor3 = C.Background, BorderSizePixel = 0,
        Position = UDim2.fromOffset(11, 205), Size = UDim2.new(1, -22, 0, 142), Visible = false,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.Lavender, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, masterCard))
    round(U.PlayerList, 4)
    make("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, U.PlayerList)
    make("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, U.PlayerList)
    U.NoPlayers = text(U.PlayerList, "Chưa có player khác online.", 10, C.Muted, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 35))
    U.NoPlayers.LayoutOrder = 0
    U.CrewLocalNote = text(masterCard, "Role lưu theo account. Chọn player → Slave; bật Master → Master.", 9, C.Muted, UDim2.fromOffset(11, 202), UDim2.new(1, -22, 0, 30))
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
    local settingsPage = U.Pages.SETTINGS
    local switches = card(settingsPage, 197, 1, "cài đặt chạy nhật ký debug phục hồi watchdog tiki")
    text(switches, "CÀI ĐẶT CHẠY", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    toggle(switches, 31, "Nhật ký chẩn đoán", "Lưu trạng thái thật và lỗi vào log.", function() return CONFIG.DEBUG.ENABLED end, function(value) CONFIG.DEBUG.ENABLED = value end)
    toggle(switches, 83, "Tự phục hồi khi bị kẹt", "Giữ an toàn khi sự kiện Volcano đang chạy.", function() return CONFIG.DEBUG.WATCHDOG_RESTART end, function(value) CONFIG.DEBUG.WATCHDOG_RESTART = value end)
    toggle(switches, 135, "Trở về Tiki", "Trở về sau reward và kiểm tra Dragon storage.", function() return CONFIG.RESET_TO_TIKI_AFTER_EVENT end, function(value) CONFIG.RESET_TO_TIKI_AFTER_EVENT = value end)
    local pxModules = card(settingsPage, 456, 1.5, "recovery net kill aura mode head root dragon hunter quest bring golem local health zero remove lava cache")
    text(pxModules, "PX NET COMBAT / QUEST BRING / LAVA", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    toggle(pxModules, 30, "NET Kill Aura hỗ trợ farm", "Donor NET cho Scrap / Hunter Quest / Golem; không click vào Inventory.",
        function() return CONFIG.KILL_AURA.Enabled end,
        function(value) CONFIG.KILL_AURA.Enabled=value end)
    toggle(pxModules, 81, "Kill Aura khi Auto OFF", "Donor NET bán kính 60; tự ngừng khi Auto Volcano chạy.",
        function() return CONFIG.KILL_AURA.IdleEnabled end,
        function(value) CONFIG.KILL_AURA.IdleEnabled=value end)
    toggle(pxModules, 132, "Remove Lava tự động", "Chờ InteriorLava xuất hiện, thay đổi client; không đảm bảo chống damage server.",
        function() return PHX.RemoveLava.Enabled end,
        function(value) PHX.removeLavaSetEnabled(value) end)
    toggle(pxModules, 183, "Bring Golem xa Fossil Relic", "TEAM + SOLO: đẩy Golem ra >=165 studs theo chiều ngang; client/network-owned only.",
        function() return CONFIG.GOLEM_AURA.BRING_ENABLED end,
        function(value) CONFIG.GOLEM_AURA.BRING_ENABLED=value==true end)
    toggle(pxModules, 234, "GOLEM LOCAL HP=0 (THỬ NGHIỆM)",
        "Chỉ Lava Golem trong 48 studs: xóa HP local; KHÔNG xác nhận chết server, Relic vẫn có nguy cơ bị tấn công.",
        function() return CONFIG.GOLEM_LOCAL_KILL.Enabled end,
        function(value) return PHX.setGolemLocalHpEnabled(value) end)
    toggle(pxModules, 285, "Bring Dragon Hunter Quest", "Hydra/Venom: Bring gốc V2.16.38 + Kill Aura NET.",
        function() return CONFIG.FARM_COMBAT.QuestBringEnabled end,
        function(value) CONFIG.FARM_COMBAT.QuestBringEnabled=value==true end)
    text(pxModules, "Golem HP=0: client only / server kill chưa xác minh. Quái thường giữ NET.", 9, C.Cyan,
        UDim2.fromOffset(11, 338), UDim2.new(1, -22, 0, 22))
    text(pxModules, "NET mode bên dưới áp dụng cho Scrap / Quest và Golem nếu tắt HP=0.", 10, C.Muted,
        UDim2.fromOffset(11, 366), UDim2.new(1, -22, 0, 18))
    local netModeButton = button(pxModules, "NET MODE · "..CONFIG.KILL_AURA.NetMode,
        UDim2.fromOffset(11, 391), UDim2.new(1, -22, 0, 34), C.Raised)
    local netModes={"NET_HEAD","NET_ROOT","NET_HEAD_0"}
    PHX.connect(netModeButton.Activated, function()
        if U.PassThrough then return end
        local current=CONFIG.KILL_AURA.NetMode
        local index=1
        for i,name in ipairs(netModes) do if name==current then index=i;break end end
        local nextMode=netModes[index%#netModes+1]
        local ok,chosen=PHX.setRecoveryNetMode(nextMode)
        if ok then netModeButton.Text="NET MODE · "..chosen end
        if U.notice then U.notice(ok and ("Recovery NET: "..chosen) or tostring(chosen),ok) end
    end)
    local boatNoclipCard = card(settingsPage, 169, 1.75, "thuyền boat noclip xuyên vật cản collision lái tàu manual auto fast buy")
    text(boatNoclipCard, "BOAT NOCLIP / FAST BUY", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    toggle(boatNoclipCard, 31, "Boat + Player Noclip", "Luôn bật khi ngồi Grand Brigade (lái/hành khách); tắt collision local cả thuyền và nhân vật, rời ghế tự khôi phục.",
        function() return CONFIG.BOAT_NOCLIP.Enabled end,
        function(value) return PHX.setBoatNoclipEnabled(value) end)
    toggle(boatNoclipCard, 83, "FAST DIRECT BUY BOAT", "Thử BuyBoat RPC ngay; chỉ đến Boat Dealer nếu server từ chối và xác minh chưa trừ tiền.",
        function() return CONFIG.BOAT_FAST_BUY.Enabled end,
        function(value) CONFIG.BOAT_FAST_BUY.Enabled=value==true; return true end)
    local fruitCard = card(settingsPage, 347, 2, "trái cây fruit random auto store dragon kitsune leopard discord V6 prepare roll")
    text(fruitCard, "DIRECT RANDOM / AUTO STORE", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.FruitToggle = toggle(fruitCard, 31, "Auto Random Fruit", "V6 Direct Gacha; tự mua khi đủ cooldown và tự nhớ lần tới.", function() return CONFIG.FRUIT_AUTO.Enabled == true end, function(value)
        local ok, message = PHX.setFruitAuto(value)
        return ok, ok and (value and "Đã bật Random fruit trên client này." or "Đã tắt Random fruit trên client này.") or message
    end)
    U.AutoStoreToggle = toggle(fruitCard, 83, "Auto Store", "Tự StoreFruit; Dragon/Kitsune/Leopard vẫn được bảo vệ.", function() return CONFIG.FRUIT_AUTO.AutoStore == true end, function(value)
        local ok, message = PHX.setAutoStore(value)
        return ok, ok and (value and "Đã bật Auto Store trên client này." or "Đã tắt Auto Store. Dragon / Kitsune / Leopard vẫn được bảo vệ.") or message
    end)
    U.FruitStatus = text(fruitCard, "READY", 9, C.Cyan, UDim2.fromOffset(11, 138), UDim2.new(1, -22, 0, 31), Enum.Font.GothamMedium)
    U.FruitCount = text(fruitCard, "Trái vật lý: 0", 9, C.Muted, UDim2.fromOffset(11, 174), UDim2.new(0.5, -11, 0, 19))
    U.FruitCooldown = text(fruitCard, "Random: OFF", 9, C.Muted, UDim2.new(0.5, 0, 0, 174), UDim2.new(0.5, -11, 0, 19))
    U.GachaPrepare = button(fruitCard, "PREPARE · NO BUY", UDim2.fromOffset(11, 204), UDim2.new(0.5, -16, 0, 34), C.LavenderSoft)
    U.GachaRoll = button(fruitCard, "ROLL ONCE", UDim2.new(0.5, 5, 0, 204), UDim2.new(0.5, -16, 0, 34), C.CyanSoft)
    U.GachaResult = text(fruitCard, "V6 sẵn sàng. Roll cần bấm xác nhận lần 2 trong 7 giây.", 9, C.Muted,
        UDim2.fromOffset(11, 244), UDim2.new(1, -22, 0, 38))
    text(fruitCard, "Tự lưu ON/OFF + cooldown vào file account. Chỉ gửi 1 Purchase, không tự retry khi chưa xác minh.",
        9, C.Muted, UDim2.fromOffset(11, 285), UDim2.new(1, -22, 0, 49))
    U.GachaManualBusy=false
    U.GachaArmedUntil=0
    local function performManualGacha(onlyPrepare)
        if U.GachaManualBusy or U.PassThrough then return end
        U.GachaManualBusy=true
        U.GachaArmedUntil=0
        U.GachaResult.Text=onlyPrepare and "Đang PREPARE (không mua)..." or "Đang gửi đúng 1 yêu cầu mua V6..."
        PHX.spawn(function()
            local ok,reason=PHX.manualGacha(onlyPrepare)
            U.GachaManualBusy=false
            if not PHX.generationAlive() or not U.Screen.Parent then return end
            U.GachaResult.Text=(ok and "OK · " or "WAIT/FAIL · ")..tostring(reason)
            logLine(onlyPrepare and "GACHA_MANUAL_PREPARE" or "GACHA_MANUAL_BUY",tostring(reason))
            U.updateControls()
        end)
    end
    PHX.connect(U.GachaPrepare.Activated,function()
        performManualGacha(true)
    end)
    PHX.connect(U.GachaRoll.Activated,function()
        if U.PassThrough or U.GachaManualBusy then return end
        local now=os.clock()
        if now>U.GachaArmedUntil then
            U.GachaArmedUntil=now+7
            U.GachaResult.Text="Xác nhận: bấm CONFIRM BUY trong 7 giây. Có thể trừ Beli!"
            U.updateControls()
            return
        end
        performManualGacha(false)
    end)

    local webhookCard = card(settingsPage, 236, 3, "discord webhook url id ping thông báo dragon kitsune leopard")
    text(webhookCard, "DISCORD WEBHOOK / ID PING", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.WebhookBox = field(webhookCard, tostring(CONFIG.WEBHOOK_URL or ""), "Discord webhook URL", UDim2.fromOffset(11, 31), UDim2.new(1, -22, 0, 33))
    U.DiscordIdBox = field(webhookCard, tostring(CONFIG.WEBHOOK_USER_ID or ""), "Discord user ID · 15–22 chữ số", UDim2.fromOffset(11, 73), UDim2.new(1, -22, 0, 33))
    U.ApplyWebhook = button(webhookCard, "LƯU WEBHOOK + ID PING", UDim2.fromOffset(11, 115), UDim2.new(1, -22, 0, 33), C.CyanSoft)
    U.WebhookState = text(webhookCard, "Webhook: OFF", 9, C.Cyan, UDim2.fromOffset(11, 156), UDim2.new(1, -22, 0, 18))
    text(webhookCard, "Lưu cục bộ. URL trống để tắt. Master báo đảo; Dragon, Kitsune và Leopard gửi ping ID đã lưu.", 10, C.Muted, UDim2.fromOffset(11, 179), UDim2.new(1, -22, 0, 49))
    PHX.connect(U.ApplyWebhook.Activated, function()
        if U.PassThrough then return end
        local ok, message = PHX.setWebhook(U.WebhookBox.Text, U.DiscordIdBox.Text)
        if ok then
            U.WebhookBox.Text = CONFIG.WEBHOOK_URL; U.DiscordIdBox.Text = CONFIG.WEBHOOK_USER_ID
            if PHX.saveUserConfig then PHX.saveUserConfig() end
        end
        U.notice(message, ok)
        U.updateControls()
    end)
    local performance = card(settingsPage, 136, 4, "hiệu năng performance fps cap cpu map hiển thị")
    text(performance, "HIỆU NĂNG", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
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
        if ok then
            CONFIG.SAVE_CPU.FPS_CAP = target; U.FpsLabel.Text = tostring(target)
            if PHX.saveUserConfig then PHX.saveUserConfig() end
        end
        U.notice(ok and ("FPS cap: " .. target) or ("FPS error: " .. tostring(err)), ok)
    end
    PHX.connect(minus.Activated, function() changeFps(-5) end)
    PHX.connect(plus.Activated, function() changeFps(5) end)
    local controls = card(settingsPage, 113, 5, "cửa sổ phiên chạy window thu gọn unload dừng gỡ ui")
    text(controls, "CỬA SỔ / PHIÊN CHẠY", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    text(controls, "Kéo thanh tiêu đề bằng chuột hoặc cảm ứng. Thu gọn bằng nút −; UI luôn giữ nguyên khi tương tác game.", 10, C.Muted, UDim2.fromOffset(11, 29), UDim2.new(1, -22, 0, 41))
    local unload = button(controls, "DỪNG & GỠ UI", UDim2.fromOffset(11, 77), UDim2.new(1, -22, 0, 28), C.RedSoft)
    unload.TextColor3 = C.Red
    PHX.connect(unload.Activated, function() if not U.PassThrough then PHX.destroy() end end)

    local configCard = card(settingsPage, 151, 6, "config cấu hình lưu tự động file execute discord")
    text(configCard, "CONFIG CỤC BỘ", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.ConfigState = text(configCard, PHX.userConfigStatus and PHX.userConfigStatus() or "Đang chuẩn bị config…", 9, C.Cyan, UDim2.fromOffset(11, 30), UDim2.new(1, -22, 0, 45), Enum.Font.GothamMedium)
    text(configCard, "Tự lưu TEAM/SOLO, farm, Auto Random, Store, cooldown và Discord.", 9, C.Muted, UDim2.fromOffset(11, 77), UDim2.new(1, -22, 0, 27))
    U.SaveConfigNow = button(configCard, "LƯU CONFIG NGAY", UDim2.fromOffset(11, 112), UDim2.new(1, -22, 0, 30), C.CyanSoft)
    PHX.connect(U.SaveConfigNow.Activated,function()
        if U.PassThrough then return end
        local saved,why=PHX.saveUserConfig()
        U.notice(saved and "Đã lưu config cho account này." or ("Không lưu được: "..tostring(why)),saved==true)
        if PHX.userConfigStatus then U.ConfigState.Text=PHX.userConfigStatus() end
    end)

    local activity = U.Pages.ACTIVITY
    local diagnostics = card(activity, 183, 1, "nhật ký kiểm tra vật liệu inventory stash magnet scrap ember sync")
    text(diagnostics, "PHIÊN CHẠY / KIỂM TRA VẬT LIỆU", 10, C.Lavender, UDim2.fromOffset(11, 7), UDim2.new(1, -22, 0, 18), Enum.Font.GothamBold)
    U.Health = text(diagnostics, "", 10, C.Text, UDim2.fromOffset(11, 31), UDim2.new(1, -22, 0, 35))
    U.LogPath = text(diagnostics, "Log: " .. tostring(NIGHT.LogPath), 9, C.Muted, UDim2.fromOffset(11, 70), UDim2.new(1, -22, 0, 29), Enum.Font.Code)
    U.Sync = button(diagnostics, "QUÉT CACHE ITEM NGAY", UDim2.fromOffset(11, 107), UDim2.new(1, -22, 0, 29), C.CyanSoft)
    text(diagnostics, "Auto scan mỗi 3 giây · không cần mở Stash.", 10, C.Muted, UDim2.fromOffset(11, 140), UDim2.new(1, -22, 0, 32))
    PHX.connect(U.Sync.Activated, function()
        if U.PassThrough or U.SyncBusy then return end
        -- A direct cache read does not require stopping Auto Volcano.
        if os.clock() - U.LastSyncAt < 5 then return end
        U.SyncBusy = true
        U.LastSyncAt = os.clock()
        U.updateControls()
        PHX.spawn(function()
            local ok, count, reason = pcall(PHX.checkMagnetFromStash, true)
            if not PHX.generationAlive() or not U.Screen.Parent then return end
            U.SyncBusy = false
            U.notice(ok and count ~= nil and ("Cache read · Magnet " .. number(count)) or ("Cache chưa sẵn sàng: " .. tostring(ok and reason or count)), ok and count ~= nil)
            U.updateControls()
            U.updateCounters()
        end)
    end)
    local logCard = make("Frame", {BackgroundColor3 = C.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2}, activity)
    U.Sections[#U.Sections + 1] = {Object = logCard, Page = "ACTIVITY", Keywords = "nhật ký log activity hoạt động gần đây"}
    round(logCard, 5)
    outline(logCard)
    make("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12)}, logCard)
    make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, logCard)
    local heading = text(logCard, "NHẬT KÝ GẦN ĐÂY / MỚI NHẤT TRƯỚC", 9, C.Lavender, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 18), Enum.Font.GothamBold)
    heading.LayoutOrder = 1
    U.ActivityText = text(logCard, "Chưa có log.", 9, C.Text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), Enum.Font.Code)
    U.ActivityText.TextYAlignment = Enum.TextYAlignment.Top
    U.ActivityText.AutomaticSize = Enum.AutomaticSize.Y
    U.ActivityText.LayoutOrder = 2

    local footer = make("Frame", {BackgroundColor3 = C.PinkSoft, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -69), Size = UDim2.new(1, 0, 0, 69)}, U.Root)
    U.Footer = footer
    U.Primary = button(footer, "AUTO VOLCANO · TEAM", UDim2.fromOffset(11, 8), UDim2.new(.5, -15, 0, 33), C.CyanSoft)
    U.Primary.TextColor3 = C.Cyan
    U.Primary.TextSize = 10
    U.SoloPrimary = button(footer, "AUTO VOLCANO · SOLO", UDim2.new(.5, 4, 0, 8), UDim2.new(.5, -15, 0, 33), C.LavenderSoft)
    U.SoloPrimary.TextColor3 = C.Lavender
    U.SoloPrimary.TextSize = 10
    for _,control in ipairs({U.Primary,U.SoloPrimary}) do
        control.TextScaled = true
        control.TextWrapped = false
        make("UITextSizeConstraint", {MinTextSize = 9, MaxTextSize = 12}, control)
        make("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, control)
    end
    U.FooterText = text(footer, "CHỌN MASTER → SLAVE · BẬT MASTER → MASTER", 8, C.Muted, UDim2.fromOffset(11, 44), UDim2.new(1, -22, 0, 20), Enum.Font.GothamMedium)
    U.FooterText.TextXAlignment = Enum.TextXAlignment.Center
    U.Toast = make("TextLabel", {
        Name = "Feedback", Visible = false, ZIndex = 20, BackgroundColor3 = C.Surface,
        BorderSizePixel = 0, TextColor3 = C.Text, Font = Enum.Font.GothamMedium,
        TextSize = 11, TextWrapped = true, Position = UDim2.new(0, 12, 1, -117), Size = UDim2.new(1, -24, 0, 48),
    }, U.Root)
    round(U.Toast, 4)
    U.ToastStroke = outline(U.Toast, C.Cyan, 0)
    make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, U.Toast)
    U.Dock = button(U.Screen, "VOLCANO · MỞ UI", UDim2.fromOffset(12, 100), UDim2.fromOffset(136, 32), C.PinkSoft)
    U.Dock.TextSize = 10
    U.Dock.Visible = false

    U.MapToggle = button(U.Screen, "HIỂN THỊ MAP · BẬT", UDim2.fromOffset(185, 100), UDim2.fromOffset(152, 32), C.LavenderSoft)
    U.MapToggle.TextSize = 10
    U.MapBusy = false
    PHX.connect(U.MapToggle.Activated, function()
        if U.PassThrough or U.MapBusy then return end
        U.MapBusy = true
        U.MapToggle.Text = "MAP · ĐANG XỬ LÝ..."
        PHX.spawn(function()
            local ok, err = pcall(PHX.setMapVisualHidden, not PHX.MapVisualHidden)
            if not PHX.generationAlive() or not U.Screen.Parent then return end
            U.MapToggle.TextSize = 10
    U.MapBusy = false
            if not ok then U.notice("Map visuals: " .. tostring(err), false) end
            if ok and PHX.saveUserConfig then PHX.saveUserConfig() end
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
        local width = math.min(690, math.max(1, bounds.Right - bounds.Left))
        local height = math.min(520, math.max(1, bounds.Bottom - bounds.Top - 40))
        U.Root.Size = UDim2.fromOffset(width, height)
        local narrow, compact = width < 520, height < 340
        local changedMode = U.Narrow ~= narrow
        U.Narrow = narrow
        if changedMode then U.SidebarOpen = false end
        local headerHeight = narrow and 62 or (compact and 43 or 50)
        local sidebarWidth = narrow and math.min(166, math.max(1, width - 20)) or 166
        local left = narrow and 12 or sidebarWidth + 14
        local pageTop = headerHeight + (compact and 43 or 59)
        local footerHeight = compact and 65 or 69
        header.Size = UDim2.new(1, 0, 0, headerHeight)
        U.Brand.TextSize = narrow and 13 or 15
        U.Brand.Position = UDim2.fromOffset(12, narrow and 6 or 8)
        U.Brand.Size = UDim2.fromOffset(narrow and 151 or 163, 22)
        U.Version.Visible = not narrow and not compact
        U.SidebarToggle.Visible = narrow
        U.RolePill.Position = narrow and UDim2.fromOffset(46, 36) or UDim2.new(1, -253, 0, compact and 27 or 30)
        U.RolePill.Size = narrow and UDim2.new(1, -59, 0, 15) or UDim2.fromOffset(202, 14)
        U.RolePill.TextXAlignment = narrow and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
        U.Sidebar.Position = UDim2.fromOffset(0, headerHeight)
        U.Sidebar.Size = UDim2.new(0, sidebarWidth, 1, -headerHeight)
        U.Sidebar.Visible = not narrow or U.SidebarOpen
        navigation.Position = UDim2.fromOffset(10, compact and 42 or 82)
        U.NavHeading.Visible = not compact
        local tabHeight = compact and math.clamp(math.floor((height - headerHeight - 54) / 4), 18, 25) or 36
        local tabStep = tabHeight + (compact and 4 or 9)
        for index, name in ipairs({"LIVE", "CREW", "SETTINGS", "ACTIVITY"}) do
            U.Tabs[name].Position = UDim2.fromOffset(0, (index - 1) * tabStep)
            U.Tabs[name].Size = UDim2.new(1, 0, 0, tabHeight)
        end
        U.Search.Size = UDim2.new(1, -20, 0, compact and 27 or 31)
        U.Search.Position = UDim2.fromOffset(10, compact and 9 or 14)
        U.SidebarFooter.Visible = not compact
        U.SearchResult.Visible = not compact
        U.PageTitle.Position = UDim2.fromOffset(left + 2, headerHeight + 8)
        U.PageTitle.Size = UDim2.new(1, -left - 18, 0, 24)
        U.PageTitle.TextSize = compact and 16 or 19
        U.PageSubtitle.Position = UDim2.fromOffset(left + 2, headerHeight + 34)
        U.PageSubtitle.Size = UDim2.new(1, -left - 18, 0, 16)
        U.PageSubtitle.Visible = not compact
        for _, page in pairs(U.Pages) do
            page.Position = UDim2.fromOffset(left, pageTop)
            page.Size = UDim2.new(1, -left - 14, 0, math.max(0, height - pageTop - footerHeight - 5))
        end
        U.Footer.Position = UDim2.new(0, narrow and 0 or sidebarWidth, 1, -footerHeight)
        U.Footer.Size = UDim2.new(1, narrow and 0 or -sidebarWidth, 0, footerHeight)
        local buttonHeight = compact and 29 or 33
        U.Primary.Position = UDim2.fromOffset(11, 8)
        U.SoloPrimary.Position = UDim2.new(.5, 4, 0, 8)
        for _,control in ipairs({U.Primary,U.SoloPrimary}) do
            control.Size = UDim2.new(.5, -15, 0, buttonHeight)
        end
        U.FooterText.Position = UDim2.fromOffset(11, compact and 40 or 44)
        U.FooterText.Visible = true
        U.Toast.Position = UDim2.new(0, left, 1, -footerHeight - 56)
        U.Toast.Size = UDim2.new(1, -left - 14, 0, 48)
        local point = U.Position or Vector2.new(bounds.Left + 4, bounds.Top + 8)
        U.Position = Vector2.new(math.clamp(point.X, bounds.Left, math.max(bounds.Left, bounds.Right - width)), math.clamp(point.Y, bounds.Top, math.max(bounds.Top, bounds.Bottom - height - 40)))
        U.Root.Position = UDim2.fromOffset(U.Position.X, U.Position.Y)
        U.Dock.Position = UDim2.fromOffset(bounds.Left, math.max(bounds.Top, bounds.Bottom - 32))
        U.MapToggle.Position = UDim2.fromOffset(math.max(bounds.Left, bounds.Right - 152), math.max(bounds.Top, bounds.Bottom - 32))
        U.Golems.TextSize = narrow and 11 or 13
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
        U.MasterBox.Text = tostring(CONFIG.MASTER_NAME or "")
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
                    if ok then
                        U.syncCrewFields(); U.setPlayerMenu(false)
                        if PHX.saveUserConfig then PHX.saveUserConfig() end
                    end
                    U.notice(ok and ("Master: " .. tostring(CONFIG.MASTER_NAME) .. ". Client này là Slave.") or message, ok)
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
        if ok then
            U.syncCrewFields()
            if PHX.saveUserConfig then PHX.saveUserConfig() end
        end
        U.notice(message, ok)
        U.updateControls()
    end)
    local clicking = false
    local function switchVolcano(mode)
        if U.PassThrough or clicking or U.SyncBusy then return end
        clicking = true
        if ENV.TeamConfig.IsRunning or PHX.Runtime.StartBusy then
            if PHX.automationMode()==mode then
                PHX.stopAutomation("USER_BUTTON")
                U.notice("Auto Volcano "..mode.." đã tắt.", true)
            else
                U.notice("Dừng chế độ đang chạy trước khi đổi Team / Solo.", false)
            end
        else
            local ok, message = PHX.setAutomationMode(mode)
            if ok then ok, message=PHX.startAutomation() end
            if ok and mode=="TEAM" then U.syncCrewFields() end
            U.notice(message, ok)
        end
        clicking = false
        U.updateControls()
    end
    PHX.connect(U.Primary.Activated, function() switchVolcano("TEAM") end)
    PHX.connect(U.SoloPrimary.Activated, function() switchVolcano("SOLO") end)

    function U.updateControls()
        if U.PlayersDirty then U.refreshPlayers() end
        local running = ENV.TeamConfig.IsRunning == true or PHX.Runtime.StartBusy == true
        local solo=PHX.isSoloAutomation()
        local critical = DRAGON_GUARD_STATE and DRAGON_GUARD_STATE.Critical == true
        for _,entry in ipairs({{Control=U.Primary,Mode="TEAM",Accent=C.Cyan,Surface=C.CyanSoft},{Control=U.SoloPrimary,Mode="SOLO",Accent=C.Lavender,Surface=C.LavenderSoft}}) do
            local active=running and (solo and "SOLO" or "TEAM")==entry.Mode
            local available=not U.PassThrough and not U.SyncBusy and (not running or active)
            entry.Control.Text=active and ("■ "..entry.Mode.." · DỪNG") or ("AUTO VOLCANO · "..entry.Mode)
            entry.Control.Active=available
            pcall(function() entry.Control.Interactable=available end)
            entry.Control.BackgroundColor3=active and C.RedSoft or entry.Surface
            entry.Control.TextColor3=active and C.Red or (available and entry.Accent or C.Muted)
        end
        U.ModeTitle.Text="AUTO VOLCANO · "..(solo and "SOLO · 1 TÀI KHOẢN" or "TEAM · MASTER + SLAVE")
        U.StatePill.Text = critical and "CRITICAL" or (running and "RUNNING" or string.upper(PHX.Runtime.RunState or "READY"))
        U.StatePill.TextColor3 = critical and C.Red or (running and C.Cyan or C.Lavender)
        U.Dock.Text = running and "VOLCANO · ĐANG BẬT" or "VOLCANO · MỞ UI"
        U.FooterText.Text = solo and "SOLO · TỰ LÁI THUYỀN VÀ ĐÁNH · KHÔNG CẦN CHỌN ROLE" or (U.Narrow and (running and "MASTER + ÍT NHẤT 3 SLAVE TRÊN THUYỀN" or "CHỌN MASTER → SLAVE · BẬT MASTER → MASTER") or (running and "MASTER GIỮ GHẾ LÁI · ÍT NHẤT 3 SLAVE NGỒI GHẾ PHỤ" or "CHỌN MASTER ĐỂ LÀM SLAVE · BẬT ADD ROLE MASTER ĐỂ LÀM MASTER"))
        local editable = not running and not U.PassThrough and not U.SyncBusy
        U.MasterBox.TextEditable = editable
        for _, control in ipairs({U.ApplyMaster, U.PlayerMenu}) do
            control.Active = editable
            pcall(function() control.Interactable = editable end)
            control.TextColor3 = editable and C.Cyan or C.Muted
            control.BackgroundColor3 = editable and C.CyanSoft or C.Raised
        end
        U.Sync.Text = U.SyncBusy and "CACHE · ĐANG QUÉT..." or "QUÉT CACHE ITEM NGAY"
        U.Sync.Active = not U.PassThrough and not U.SyncBusy
        pcall(function() U.Sync.Interactable = U.Sync.Active end)
        U.ApplyMaster.Text = running and "KHÓA" or "CHỌN"
        local master = ENV.TeamConfig.MasterName
        local role = PHX.localRole()
        U.RolePill.Text = solo and "SOLO / DRIVER" or (role == "MASTER" and "MASTER / DRIVER" or (role == "SLAVE" and "SLAVE / PASSENGER" or "CHƯA CÓ ROLE"))
        U.RolePill.TextColor3 = solo and C.Lavender or (role == "NONE" and C.Muted or C.Cyan)
        U.RoleLabel.Text = "CLIENT: " .. LP.Name .. "  ·  MASTER: " .. tostring(master or "chưa chọn")
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
            if entry.Stroke then entry.Stroke.Color = enabled and C.Cyan or C.Border end
        end
        local fruit = PHX.FruitAutoState or {}
        local fruitHelp={
            OPEN_ZIOLES_RANDOM_FRUIT_MENU="Đến Zioles và mở hội thoại.",
            APPROACH_ZIOLES_FOR_RANDOM_FRUIT="Cần đứng gần Zioles để random.",
            LEAVE_BOAT_SEAT_BEFORE_RANDOM_FRUIT="Rời ghế thuyền trước khi random.",
            PAUSE_AUTO_VOLCANO_BEFORE_RANDOM_FRUIT="Dừng Auto Volcano để random.",
            WAITING_FOR_FARM_START="Đợi Auto Volcano đã lưu khởi động trước.",
            CLOSE_INVENTORY_BEFORE_RANDOM_FRUIT="Đóng kho Items trước khi random.",
            WAITING_FOR_GAME_INTERACTION="Đợi kiểm tra Stash hoặc thao tác game hiện tại hoàn tất.",
            RANDOM_CLOSING_INVENTORY="Đang đóng kho để random fruit.",
            RANDOM_CLOSE_INVENTORY_UNAVAILABLE="Chưa tìm thấy nút đóng kho Items.",
            RANDOM_CLOSE_INVENTORY_UNCONFIRMED="Chưa xác nhận đóng kho Items; sẽ thử lại.",
            RANDOM_APPROACHING_ZIOLES="Đang đến NPC Gacha để random fruit.",
            ZIOLES_NPC_NOT_FOUND="Chưa tìm thấy NPC Gacha trong vùng game đã tải.",
            ZIOLES_NPC_AMBIGUOUS="Có nhiều NPC Gacha phù hợp; chưa chọn được NPC.",
            RANDOM_APPROACH_FAILED="Chưa đến được NPC Gacha; sẽ thử lại.",
            STARTUP_UI_NOT_READY="Đợi Marines và UI game tải xong.",
            WAITING_FOR_MARINES_AND_GAME_LOAD="Đợi Marines và UI game tải xong.",
            FRUIT_STORAGE_FULL_NO_RANDOM_PURCHASE="Kho fruit đầy; cần chỗ trống để cất.",
            STORE_FULL_FRUIT_RETAINED="Kho fruit đầy · đã bấm Nevermind; trái vẫn được giữ.",
            STORE_FULL_BACKOFF="Kho fruit đầy · đợi trước khi thử cất lại.",
            STORE_FULL_NEVERMIND_UNCONFIRMED="Kho fruit đầy · chưa xác nhận đóng hội thoại Nevermind.",
            STORE_FULL_WAITING_FOR_GAME_INTERACTION="Đợi thao tác game kết thúc để đóng hội thoại kho đầy.",
            VALUABLE_STORE_BACKOFF="Trái quý được giữ · đang đợi thử cất lại.",
            RANDOM_SPINNER_ACTIVE="Đang quay fruit; chờ lượt hiện tại hoàn tất.",
            RANDOM_WAITING_FOR_PHYSICAL_FRUIT="Đang chờ trái vật lý xuất hiện.",
            RANDOM_RESULT_PENDING="Lượt mua còn chờ xác nhận; chưa mua lượt khác. Nếu đang hiện kết quả, đóng bằng nút X.",
            CLOSE_RANDOM_REVEAL_TO_RECEIVE_FRUIT="Đóng màn hình kết quả bằng nút X để nhận trái vật lý.",
        }
        U.FruitStatus.Text = "STATUS · " .. tostring(fruitHelp[fruit.Status] or fruit.Status or "READY")
        U.FruitCount.Text = "Trái vật lý: " .. number(fruit.PhysicalCount or 0)
        local remaining = math.max(0, math.ceil((tonumber(fruit.NextRandomAt) or 0) - os.clock()))
        U.FruitCooldown.Text = remaining > 0 and ("Gacha CD: "..number(remaining).."s")
            or (CONFIG.FRUIT_AUTO.Enabled and "Random: READY" or "Auto: OFF / READY")
        local gachaBusy=U.GachaManualBusy or (PHX.FruitAutoState and PHX.FruitAutoState.Busy) or ENV.__PH_GACHA_GLOBAL_PURCHASE_BUSY
        U.GachaPrepare.Text=gachaBusy and "BUSY..." or "PREPARE · NO BUY"
        U.GachaRoll.Text=gachaBusy and "BUSY..." or (os.clock()<U.GachaArmedUntil and "CONFIRM BUY (7s)" or "ROLL ONCE")
        U.GachaPrepare.BackgroundColor3=gachaBusy and C.Raised or C.LavenderSoft
        U.GachaRoll.BackgroundColor3=gachaBusy and C.Raised or C.CyanSoft
        U.WebhookState.Text = CONFIG.WEBHOOK_URL ~= "" and ("Webhook: " .. tostring(PHX.Runtime.WebhookState or "CONFIGURED")) or "Webhook: OFF"
        U.WebhookBox.TextEditable = not U.PassThrough
        U.DiscordIdBox.TextEditable = not U.PassThrough
        U.ApplyWebhook.Active = not U.PassThrough
        pcall(function() U.ApplyWebhook.Interactable = not U.PassThrough end)
        U.CpuState.Text = "SaveCPU: " .. (SAVE_CPU_APPLIED and "APPLIED" or (CONFIG.SAVE_CPU.ENABLED and "PENDING" or "DISABLED")) .. " · FPS " .. tostring(CONFIG.SAVE_CPU.FPS_CAP)
        if PHX.userConfigStatus then U.ConfigState.Text = PHX.userConfigStatus() end
        if not U.MapBusy then U.MapToggle.Text = PHX.MapVisualHidden and "HIỂN THỊ MAP · TẮT" or "HIỂN THỊ MAP · BẬT" end
        if U.ToastUntil and os.clock() >= U.ToastUntil then U.Toast.Visible = false; U.ToastUntil = nil end
    end
    function U.updateCounters()
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
        local solo=PHX.isSoloAutomation()
        local boat = getMasterBoat()
        PHX.refreshCrew(boat)
        local names = table.clone(PHX.crewNames())
        local localFound = false
        for _, name in ipairs(names) do
            if PHX.sameName(name, LP.Name) then localFound = true; break end
        end
        if not localFound then names[#names + 1] = LP.Name end
        local driver = boat and PHX.driverSeat(boat)
        local online, aboard = 0, 0
        for index, name in ipairs(names) do
            local entry = U.CrewRows[index] or U.createCrewRow(index)
            local player = name and PHX.playerByName(name)
            local character = player and player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local seat = humanoid and humanoid.SeatPart
            local seated = seat and boat and seat:IsDescendantOf(boat)
            local master = name and PHX.sameName(name, solo and LP.Name or ENV.TeamConfig.MasterName)
            local isLocal = PHX.sameName(name, LP.Name)
            local role = isLocal and PHX.localRole() or (master and "MASTER" or "SLAVE")
            local wrong = seated and ((master and seat ~= driver) or (not master and seat == driver))
            local dead = humanoid and humanoid.Health <= 0
            entry.Name.Text = name .. (isLocal and " · YOU" or "")
            entry.Role.Text = solo and "SOLO / DRIVER" or (role == "MASTER" and "MASTER / DRIVER" or (role == "SLAVE" and "SLAVE / PASSENGER" or "CHƯA CÓ ROLE"))
            entry.Role.TextColor3 = role == "NONE" and C.Muted or (master and C.Cyan or C.Lavender)
            entry.State.Text = wrong and "WRONG SEAT" or (dead and "RESPAWN" or (seated and (master and "DRIVING" or "ABOARD") or (player and "ONLINE" or "OFFLINE")))
            entry.State.TextColor3 = (wrong or dead) and C.Red or (seated and C.Cyan or (player and C.Lavender or C.Muted))
            if player then online = online + 1 end
            if seated then aboard = aboard + 1 end
        end
        for index = #U.CrewRows, #names + 1, -1 do
            U.CrewRows[index].Object:Destroy()
            U.CrewRows[index] = nil
        end
        local rowsHeight = #names * 41
        presence.Size = UDim2.new(1, 0, 0, 95 + rowsHeight)
        U.CrewNote.Position = UDim2.fromOffset(11, 60 + rowsHeight)
        U.CrewHeading.Text = solo and "SOLO · TỰ MUA VÀ LÁI THUYỀN" or "MASTER + ÍT NHẤT 3 SLAVE ĐỂ RA KHƠI"
        U.CrewNote.Text = solo and "Chỉ account này tham gia Solo; cấu hình team vẫn được giữ." or "Đội cập nhật theo thuyền. Slave còn lại có thể farm Magnet."
        U.CrewSummary.Text = solo and (aboard .. " aboard · không cần Slave") or (ENV.TeamConfig.MasterName and (online .. " online · " .. aboard .. " aboard · cần Master + 3 Slave") or "Chưa chỉ định Master · client này chưa có role")
    end
    function U.updateTelemetry()
        local boat = PHX.boatTelemetry()
        U.BoatTitle.Text = "" .. tostring(boat.Name or "GRAND BRIGADE")
        U.BoatHP.Text = "HP " .. number(boat.HP) .. " / " .. number(boat.MaxHP)
        U.BoatState.Text = tostring(boat.State or "WAIT_MASTER") .. " · " .. number(boat.Aboard) .. " aboard · " .. (PHX.isSoloAutomation() and "Solo / local driver" or "Master + ≥3 Slave")
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
        U.Phase.Text = golems > 0 and ((PHX.isSoloAutomation() and "RELIC GUARD · " or "GOLEM FIRST · ") .. golems .. " LIVE") or ("PHASE · " .. tostring(snapshot.Phase or PHX.TeamPhase or PHX.Runtime.RunState or "READY"))
        U.EggState.Text = "EGG · " .. tostring(snapshot.Egg or "WAITING")
        local reason = snapshot.Error or PHX.Runtime.Reason
        local recovery = tostring(PHX.BoatState or PHX.TeamPhase or PHX.Runtime.RunState or "READY")
        U.Recovery.Text = reason and ("RECOVERY / ERROR · " .. tostring(reason)) or ("RECOVERY · " .. recovery .. " · " .. number(NIGHT.RecoveryCount) .. " lần")
        U.Recovery.TextColor3 = snapshot.Error and C.Red or C.Muted
        local queue=PHX.StashScanQueue
        if queue and not ENV.TeamConfig.IsRunning and not U.SyncBusy then
            if queue.StartupPending then
                U.Phase.Text="STARTUP · QUÉT CLIENT CACHE"
                STATUS_LABEL.Text=tostring(PHX.Runtime.StartupStatus or "Đợi ItemReplicationService khởi tạo, sẽ tự quét lại.")
            elseif queue.StartupDone and not PHX.StashBaselineReady and PHX.StashLastError then
                U.Phase.Text="STASH · ĐANG ĐỢI THỬ LẠI"
                STATUS_LABEL.Text="Chưa đủ thông tin kho: "..tostring(PHX.StashLastError).."\nScript sẽ tự kiểm tra lại khi thao tác hiện tại kết thúc."
            end
        end
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

    U.applySearch()
    U.updateControls()
    pcall(U.updateCounters)
    pcall(U.updateCrew)
    pcall(U.updateTelemetry)
    pcall(U.updateActivity)
    if BOOT_GUI and BOOT_GUI.Parent then BOOT_GUI:Destroy() end
    local role = PHX.localRole()
    setStatus("VOLCANO TEAM READY · " .. (role == "MASTER" and "MASTER / DRIVER" or (role == "SLAVE" and "SLAVE / PASSENGER" or "CHƯA CÓ ROLE")) .. " · Auto Volcano OFF")
    logLine("UI", "VOLCANO TEAM ready | dark sidebar | log=" .. tostring(NIGHT.LogPath))
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

if PHX.generationAlive() then
    PHX.buildUI()
    PHX.Runtime.UiReady=true
    PHX.startMaterialNotifications()
    PHX.startUserConfigResume()
end
PHX.Runtime.Tasks[coroutine.running()] = nil

-- V2.17.04: Strict NET combat and Dragon Hunter Bring integration.
