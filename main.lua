-- PH_PREHISTORIC_TEAM_AUTO_V1_KAWAII.lua
-- TEAM BUILD V1:
--   MASTER  : Magnet check + Grand Brigade driver + Fossil start + Golem controller
--   SLAVE 1 : Pressure A
--   SLAVE 2 : Pressure B
--   SLAVE 3 : Golem DPS support
--   SLAVE 4 : Pressure C
--
-- Coordination intentionally uses visible Roblox state (players, seats, boat,
-- island, raid HUD, enemies) rather than _G/shared between clients, because
-- executor globals are per-client.
--
-- Movement rule:
--   PLAYER = SAFE TWEEN ONLY. No long-distance player teleport / fast tween.
--   BOAT   = straight Sea 6 travel.
--   SEATED = JUMP OUT FIRST before any player tween.
--
-- Kawaii UI:
--   Set getgenv().PH_KAWAII_IMAGE to a Roblox asset id / rbxassetid:// URI.
--   HTTP image URLs are also supported when the executor exposes request +
--   writefile + getcustomasset.
--
-- V2.9 MULTI-GOLEM CLUSTER:
-- Supports 1, 2, 3+ Lava Golems at the same time.
-- All living Golems are pulled into ONE tight cluster ~145 studs away from
-- Fossil Relic, with a tiny ~3-stud spread only to reduce physics overlap.
-- RegisterHit receives the whole clustered target list in one attack.
-- Newly spawned Golems are detected and added to the same cluster mid-fight.
-- Bring remains throttled (0.25s + 12-stud drift) to avoid V2.7-style freezes.
-- Player movement remains SAFE tween only.
--
-- V2.8 GOLEM STABILITY FIX:
-- VIDEO DIAGNOSIS:
--   V2.7 was not truly dead; it repeatedly sat on GOLEM FIRST with HP unchanged
--   for long stretches, then eventually damaged the Golem again.
-- Main cause was the Golem loop being far too aggressive:
--   * PivotTo + full descendant velocity/collision writes every ~0.035s
--   * setsimulationradius(math.huge) repeatedly
--   * RegisterAttack/RegisterHit roughly 25-30 times/sec
-- This can choke client physics/replication and make the automation look frozen.
-- V2.8 prepares the Golem once, throttles re-bring to 0.25s only when it drifts,
-- attacks at 0.09s, uses RegisterAttack(.05), and adds a physical Melee fallback.
--
-- V2.7 EVENT DETECTION FIX:
-- VIDEO DIAGNOSIS:
--   * The running UI in the clip still showed V2.4, not V2.6.
--   * During a clearly active raid (Time Left / Pressure / Relic Health visible),
--     the old controller was not entering GOLEM/PRESSURE states.
-- ROOT BUG:
--   * old code depended on PrehistoricIsland:GetAttribute("IsMinigameActive"),
--     but that attribute has been observed as nil.
-- FIX:
--   * raid-active state now comes from the visible TopHUDList raid UI.
--   * Pressure and Relic Health are parsed from HUD text first.
--   * Golem-first/hard-bring logic from V2.6 is preserved.
--   * V2.7+ instances use a generation token so executing another V2.7+
--     automatically invalidates the previous compatible instance.
--
-- V2.6 GOLEM-FIRST / HARD BRING:
-- Lava Golem now has priority over pressure rocks while alive.
-- It is hard-brought roughly 135 studs away from Fossil Relic, frozen there,
-- enlarged for net hits, and attacked continuously in short bursts.
-- Player travel to the attack point still uses SAFE tween (175), not teleport.
-- Once Golem is dead, normal pressure-rock handling resumes.
--
-- V2.5 EXACT FOSSIL CAPTURE:
-- Uses the manually captured PLAYER_RELATIVE_TO_RELIC CFrame:
--   CFrame.new(-2.257812,-49.921875,27.808289,...)
-- Capture also proved PROMPT_COUNT = 0, so Fossil is NOT a ProximityPrompt.
-- V2.5 safe-tweens to that exact relative pose, then sends ONE virtual E hold
-- for 3.0 seconds. If the event does not confirm, Auto Volcano pauses instead
-- of spamming E/Observation.
--
-- V2.4 AUTO VOLCANO TOGGLE:
-- Adds a draggable-UI ON/OFF button.
-- OFF pauses automation without killing the script/state, so Fossil Relic can
-- be inspected manually. Active player tween cancels its current segment and
-- resumes safely from the current position when ON again. Boat movement stops
-- while paused. Fossil prompt hold is released immediately on pause.
--
-- V2.3 FOSSIL PROMPT HOLD FIX:
-- Fossil interaction now targets the actual ProximityPrompt near the relic
-- and stops ~2.8 studs in front of that prompt (nose/mouth area), not on top.
-- NO global VirtualInputManager E is sent for Fossil interaction.
-- Global E can toggle Observation/Instinct, so V2.3 uses prompt-level
-- InputHoldBegin/InputHoldEnd for ~3 seconds, with fireproximityprompt fallback.
--
-- V2.2 FOSSIL TWEEN / HOLD-E FIX:
-- Fossil approach no longer does the exaggerated +95Y lift/cross/descend path.
-- After JUMP-unseating, it uses one normal SAFE chunked tween at 135 studs/s
-- to an absolute point 3.2 studs above the Fossil.
-- Fossil interaction now uses VirtualInputManager E key-down for 3.0 seconds,
-- then E key-up, with up to 3 attempts.
--
-- V2.1 PORTAL ROUTE:
-- Adds Tiki/Castle/Turtle/Hydra game-portal routing.
-- Cross-island recovery uses SAFE tween to the portal, lets the GAME portal
-- perform the teleport, then safe-tweens locally to the Boat Dealer.
-- No long-distance CFrame teleport / fast player tween.
-- Sea 6 boat search stays one straight heading.
--
-- V2 JUMP-SEAT REBUILD:
-- Rebuilt around the user's required seat rule:
-- WHEN THE BOAT FINDS PREHISTORIC, THE PLAYER MUST JUMP OUT OF VehicleSeat
-- BEFORE ANY PLAYER TWEEN STARTS.
--
-- Preserved:
--   * Magnet check once at startup, no spam on death/boat loss
--   * death -> respawn -> rebuy/reboard -> continue hunt
--   * destroyed boat -> rebuy -> continue hunt
--   * Sea 6 boat search = one straight heading, no square patrol
--   * UI always visible/status-only/draggable
--   * pressure -> Golem net burst -> Dragon Egg -> optional Bones
--
-- V1.3 TWEEN / DISEMBARK FIX:
-- Video diagnosis: player tween started while still welded to MarineGrandBrigade's
-- VehicleSeat. That caused the boat weld/server physics to fight the HRP tween,
-- producing water dives, wall snaps and apparent teleport-backs.
-- Fix: stop boat -> force unseat -> confirm SeatPart=nil -> chunked player tween.
-- Sea 6 BOAT hunt remains one straight heading.
-- Island landing uses lift -> cross above terrain -> descend to avoid tunneling
-- through the island at sea level.
--
-- V1.2 RECOVERY LOOP:
-- Fixes repeated Stash/Magnet checks.
-- Magnet is checked once at startup, then only after a COMPLETED event.
-- Player death / boat destruction stays inside a recovery loop:
-- respawn -> rebuy boat -> board -> continue straight Sea 6 hunt.
-- UI remains visible during Magnet checks.
--
-- V1.1 STRAIGHT SEA SEARCH:
-- Sea 6 search no longer uses a square patrol.
-- Boat chooses one heading toward the Sea 6 center and keeps driving straight.
--
-- Standalone solo Prehistoric / Volcano automation.
--
-- Intended flow:
--   1) auto-join Marines
--   2) open Stash once and verify Volcanic Magnet
--   3) buy/board MarineGrandBrigade
--   4) search for Prehistoric Island
--   5) start Fossil Relic event
--   6) solo pressure rocks + Lava Golem "kill-aura style" net attacks
--   7) collect nearest Dragon Egg
--   8) quick Dinosaur Bones sweep
--   9) reset to Tiki, re-check Magnet, repeat
--
-- Notes:
--   * "Kill aura" here means rapid validated RE/RegisterAttack + RE/RegisterHit bursts
--     while close to the Lava Golem. It is NOT an unverified instant-delete remote.
--   * Stash is authoritative for Magnet.
--   * UI is status-only and draggable. No start/stop buttons.
--
-- Auto Magnet baseline kept separately:
--   PH_VOLCANIC_MAGNET_FULL_AUTO_V1_7_POSTCRAFT_VERIFY.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- TEAM singleton + backwards-compatible solo invalidation.
local ENV = (getgenv and getgenv()) or _G

-- Kill currently running V2.7+ solo build on this client.
ENV.PH_VOLCANO_GENERATION =
    (tonumber(ENV.PH_VOLCANO_GENERATION) or 0) + 1

-- Kill an older compatible TEAM build on this client.
ENV.PH_TEAM_VOLCANO_GENERATION =
    (tonumber(ENV.PH_TEAM_VOLCANO_GENERATION) or 0) + 1

local SCRIPT_GENERATION = ENV.PH_TEAM_VOLCANO_GENERATION

ENV.PH_VOLCANO_KILL = false
ENV.PH_TEAM_VOLCANO_KILL = false

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    PLAYER_SPEED = 200,
    PRESSURE_SPEED = 220,

    TEAM = {
        -- Optional runtime overrides:
        -- getgenv().PH_MASTER_NAME = "username"
        -- getgenv().PH_TEAM_NAMES  = {"master","slave1","slave2","slave3","slave4"}
        -- getgenv().PH_TEAM_SLOT   = 0..4   (0=MASTER)
        MASTER_NAME = tostring(ENV.PH_MASTER_NAME or "AshleyChelseaFrances"),

        NAMES = type(ENV.PH_TEAM_NAMES) == "table"
            and ENV.PH_TEAM_NAMES
            or {
                "AshleyChelseaFrances", -- MASTER
                "", -- SLAVE 1
                "", -- SLAVE 2
                "", -- SLAVE 3
                "", -- SLAVE 4
            },

        EXPECTED_SIZE = 5,
        REQUIRED_SLAVES = 4,
        WAIT_FOR_TEAM_SECONDS = 35,

        -- If not all alts have joined yet, MASTER may still depart after timeout.
        ALLOW_PARTIAL_AFTER_TIMEOUT = true,
        MIN_SLAVES_AFTER_TIMEOUT = 0,

        -- SLAVES wait for the MASTER's Grand Brigade and occupy passenger seats.
        PASSENGER_BOARD_RETRY = 1.0,
    },

    UI = {
        -- Example:
        -- getgenv().PH_KAWAII_IMAGE = "rbxassetid://123456789"
        -- or "123456789"
        -- or supported HTTP image URL on executors with custom-asset APIs.
        ANIME_IMAGE = tostring(ENV.PH_KAWAII_IMAGE or ""),
    },

    BOAT_NAME = "MarineGrandBrigade",
    BOAT_BUY_NAME = "MarineGrandBrigade",
    BOAT_SPEED = 360,

    -- Runtime point supplied earlier.
    BOAT_DEALER_CFRAME = CFrame.new(
        -16928.9277,10,434.619995,
        -0.434707522,0,-0.900571883,
        0,1,0,
        0.900571883,0,-0.434707522
    ),

    PORTALS = {
        Tiki_To_Castle = CFrame.new(
            -16799.9473,59.9832191,290.861969,
            0.792721033,6.48934986e-08,-0.60958457,
            -1.1125271e-07,1,-3.82208896e-08,
            0.60958457,9.81164376e-08,0.792721033
        ),

        Castle_To_Tiki = CFrame.new(
            -5096.34131,316.511047,-3174.32227,
            0.999937356,4.29376179e-08,-0.0111938119,
            -4.30900293e-08,1,-1.33745131e-08,
            0.0111938119,1.38560168e-08,0.999937356
        ),

        Turtle_To_Castle = CFrame.new(
            -12463.6025,376.335999,-7566.08301,
            1,-2.37242093e-09,-3.80343628e-15,
            2.37242093e-09,1,4.0985646e-09,
            3.79371276e-15,-4.0985646e-09,1
        ),

        Castle_To_Turtle = CFrame.new(
            -5060.06006,316.511047,-3194.63062,
            0.992432296,2.75590928e-08,-0.12279328,
            -2.76739218e-08,1,7.70395803e-10,
            0.12279328,2.63360578e-09,0.992432296
        ),

        Castle_To_Hydra = CFrame.new(
            -5027.03027,316.511047,-3206.70361,
            1,-4.02126652e-08,-1.21312694e-14,
            4.02126652e-08,1,5.87755622e-08,
            9.76774678e-15,-5.87755622e-08,1
        ),

        Hydra_To_Castle = CFrame.new(
            5650.94775,1015.28326,-350.379181,
            1,5.02064275e-08,-1.44387506e-14,
            -5.02064275e-08,1,-4.3968754e-08,
            1.22312362e-14,4.3968754e-08,1
        ),
    },

    -- Search fallback carried from the previous prehistoric script.
    -- It is treated only as a patrol center, not as a guaranteed island position.
    SEA_PATROL_CENTER = Vector3.new(-37813.6953,65,6105.16895),
    SEA_PATROL_RADIUS = 5500,

    PRESSURE = {
        ROCK_HOVER_Y = 10,
        SKILL_HOLD = 0.03,
        SKILL_GAP = 0.11,
        BURST_SECONDS = 1.65,

        -- Solo priority:
        -- pressure/relic emergency always overrides Golem.
        EMERGENCY_PRESSURE = 25,
        EMERGENCY_RELIC = 94,
    },

    GOLEM = {
        APPROACH_DISTANCE = 48,
        HOVER_Y = 14,
        HITBOX = 85,
        NET_DISTANCE = 135,
        ATTACK_INTERVAL = 0.09,
        BURST_SECONDS = 1.00,

        -- V2.6: Lava Golem has absolute combat priority while alive.
        PRIORITY_FIRST = true,

        -- Keep the Golem well away from Fossil Relic while attacking.
        BRING_DISTANCE_FROM_RELIC = 145,
        BRING_HEIGHT_OFFSET = 0,
        BRING_HITBOX = 72,

        -- Multi-Golem cluster bring.
        CLUSTER_RADIUS = 3.0,
        BRING_INTERVAL = 0.25,
        REBRING_DRIFT = 12,
        STALL_SECONDS = 4.0,
    },

    EGG = {
        HOLD_E = 1.10,
        RETRIES = 3,
        RETRY_GAP = 0.30,
        WAIT_SECONDS = 12,
        APPROACH_DISTANCE = 4.0,
    },

    BONES = {
        ENABLED = true,
        SWEEP_SECONDS = 2.5,
    },

    -- Captured manually at a position where HOLD E works.
    -- This is RELATIVE TO PrehistoricRelic:GetPivot(), so it should follow
    -- the relic even when the island spawns at another world position/rotation.
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
    },

    LOOP_AFTER_EVENT = true,

    MAGNET_CHECK = {
        STARTUP_RETRIES = 3,
        RETRY_GAP = 2.0,
        -- Re-check only after a completed event before starting a NEW hunt.
        -- Death / boat destruction never triggers another Stash check.
        RECHECK_AFTER_EVENT = true,
    },

    RECOVERY = {
        RESPAWN_WAIT = 20,
        BOAT_REBUY_GAP = 1.2,
    },
}

--==============================================================
-- TEAM ROLE RESOLUTION
--==============================================================

local function nonEmptyConfiguredNames()
    local out = {}

    for _,name in ipairs(CONFIG.TEAM.NAMES or {}) do
        name = tostring(name or "")
        if name ~= "" then
            out[#out+1] = name
        end
    end

    return out
end

local function dynamicTeamNames()
    local configured = nonEmptyConfiguredNames()

    -- If the user supplied at least MASTER + one slave, respect that roster.
    if #configured >= 2 then
        return configured
    end

    -- Zero-config fallback:
    -- MASTER + first four other players sorted by UserId.
    local out = {CONFIG.TEAM.MASTER_NAME}
    local others = {}

    for _,p in ipairs(Players:GetPlayers()) do
        if p.Name ~= CONFIG.TEAM.MASTER_NAME then
            others[#others+1] = p
        end
    end

    table.sort(others,function(a,b)
        return a.UserId < b.UserId
    end)

    for i=1,math.min(4,#others) do
        out[#out+1] = others[i].Name
    end

    return out
end

local function resolveTeamSlot()
    local explicit = tonumber(ENV.PH_TEAM_SLOT)

    if explicit and explicit >= 0 and explicit <= 4 then
        return math.floor(explicit)
    end

    if LP.Name == CONFIG.TEAM.MASTER_NAME then
        return 0
    end

    for i,name in ipairs(CONFIG.TEAM.NAMES or {}) do
        if tostring(name) ~= "" and LP.Name == tostring(name) then
            return i-1
        end
    end

    local names = dynamicTeamNames()
    for i,name in ipairs(names) do
        if LP.Name == name then
            return i-1
        end
    end

    -- Unconfigured extra client: deterministic fallback.
    return (math.abs(LP.UserId) % 4) + 1
end

local TEAM_SLOT = resolveTeamSlot()

local ROLE_BY_SLOT = {
    [0] = "MASTER / DRIVER / GOLEM CTRL",
    [1] = "PRESSURE A",
    [2] = "PRESSURE B",
    [3] = "GOLEM DPS",
    [4] = "PRESSURE C",
}

local ROLE = ROLE_BY_SLOT[TEAM_SLOT] or ("SUPPORT "..TEAM_SLOT)

local function isMaster()
    return TEAM_SLOT == 0
end

local function pressureWorkerIndex()
    if TEAM_SLOT == 1 then return 1 end
    if TEAM_SLOT == 2 then return 2 end
    if TEAM_SLOT == 4 then return 3 end
    if TEAM_SLOT == 3 then return 4 end
    return 1
end

local function teamPlayerNames()
    return dynamicTeamNames()
end

local function teamNameSet()
    local set = {}
    for _,name in ipairs(teamPlayerNames()) do
        set[name] = true
    end
    return set
end

local function teamOnlineCount()
    local set = teamNameSet()
    local n = 0

    for _,p in ipairs(Players:GetPlayers()) do
        if set[p.Name] then
            n += 1
        end
    end

    return n
end

local function masterPlayer()
    return Players:FindFirstChild(CONFIG.TEAM.MASTER_NAME)
end

local function masterAlive()
    local p = masterPlayer()
    local c = p and p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0 or false
end

--==============================================================
-- BASIC STATE
--==============================================================

local STATE = {
    Running = true,
    Phase = "BOOT",
    Status = "Starting...",
    Magnet = nil,
    Boat = "NONE",
    Pressure = nil,
    Relic = nil,
    GolemHP = nil,
    GolemCount = 0,
    Egg = "WAIT",
    Cycle = 0,
    Token = 1,

    MagnetChecked = false,
    MagnetNeedsRefresh = true,
    HuntRetry = 0,
    CompletedEvents = 0,

    -- User-facing pause switch.
    -- Running keeps the script alive; AutoVolcano controls whether automation may act.
    AutoVolcano = true,

    Role = ROLE,
    TeamSlot = TEAM_SLOT,
    TeamOnline = 0,
    TeamBoarded = 0,
    Raid = "OFF",
}

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

local function alive()
    local h = hum()
    return h and h.Health > 0 and root() ~= nil
end

local function normalize(v)
    return string.lower(tostring(v or ""))
        :gsub("<.->","")
        :gsub("&nbsp;"," ")
        :gsub("%s+"," ")
        :gsub("^%s+","")
        :gsub("%s+$","")
end

local function current(token)
    return STATE.Running
        and ENV.PH_VOLCANO_KILL ~= true
        and ENV.PH_TEAM_VOLCANO_KILL ~= true
        and ENV.PH_TEAM_VOLCANO_GENERATION == SCRIPT_GENERATION
        and (token == nil or token == STATE.Token)
end

local function autoOn()
    return STATE.AutoVolcano == true
end

local function waitAuto(token)
    while current(token) and not autoOn() do
        task.wait(.10)
    end
    return current(token)
end

local function waitAlive(token)
    while current(token) do
        if alive() then return true end
        task.wait(.15)
    end
    return false
end

--==============================================================
-- KAWAII TEAM UI / DRAGGABLE
--==============================================================

local GUI_NAME = "PH_PrehistoricTeamKawaiiV1"
local old = PG:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local function resolveKawaiiImage(source)
    source = tostring(source or "")
    if source == "" then
        return ""
    end

    if tonumber(source) then
        return "rbxassetid://"..source
    end

    if source:match("^rbxassetid://") then
        return source
    end

    -- Optional HTTP -> custom asset path for supported executors.
    if source:match("^https?://")
    and type(writefile) == "function"
    and type(getcustomasset) == "function" then
        local requestFn =
            (syn and syn.request)
            or http_request
            or request

        if type(requestFn) == "function" then
            local ok,res = pcall(function()
                return requestFn({
                    Url = source,
                    Method = "GET",
                })
            end)

            if ok and res and (res.Success == true or res.StatusCode == 200)
            and type(res.Body) == "string" then
                local ext = source:lower():match("%.([%a%d]+)[%?]?")
                if ext ~= "jpg" and ext ~= "jpeg"
                and ext ~= "png" and ext ~= "webp" then
                    ext = "png"
                end

                local fileName = "PH_KAWAII_GIRL."..ext

                local wrote = pcall(function()
                    writefile(fileName,res.Body)
                end)

                if wrote then
                    local okAsset,asset = pcall(function()
                        return getcustomasset(fileName)
                    end)

                    if okAsset and asset then
                        return asset
                    end
                end
            end
        end
    end

    return source
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 99999
gui.IgnoreGuiInset = false
gui.Parent = PG

local frame = Instance.new("Frame")
frame.Parent = gui
frame.Size = UDim2.fromOffset(720,440)
frame.Position = UDim2.new(0,18,0.5,-220)
frame.BackgroundColor3 = Color3.fromRGB(255,225,242)
frame.BorderSizePixel = 0
frame.Active = true
Instance.new("UICorner",frame).CornerRadius = UDim.new(0,18)

local frameStroke = Instance.new("UIStroke")
frameStroke.Parent = frame
frameStroke.Thickness = 2
frameStroke.Transparency = .1
frameStroke.Color = Color3.fromRGB(255,146,202)

local bgGradient = Instance.new("UIGradient")
bgGradient.Parent = frame
bgGradient.Rotation = 25
bgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(255,226,244)),
    ColorSequenceKeypoint.new(.5,Color3.fromRGB(238,226,255)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(219,239,255)),
})

local title = Instance.new("TextLabel")
title.Parent = frame
title.Position = UDim2.fromOffset(18,12)
title.Size = UDim2.fromOffset(670,34)
title.BackgroundTransparency = 1
title.Text = "♡ PREHISTORIC TEAM • KAWAII CONTROL ♡"
title.TextColor3 = Color3.fromRGB(109,66,119)
title.Font = Enum.Font.GothamBold
title.TextSize = 19
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true

local subtitle = Instance.new("TextLabel")
subtitle.Parent = frame
subtitle.Position = UDim2.fromOffset(20,44)
subtitle.Size = UDim2.fromOffset(450,22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "safe tween • team sync • volcano raid"
subtitle.TextColor3 = Color3.fromRGB(151,104,153)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left

local left = Instance.new("Frame")
left.Parent = frame
left.Position = UDim2.fromOffset(16,72)
left.Size = UDim2.fromOffset(486,352)
left.BackgroundColor3 = Color3.fromRGB(255,247,252)
left.BackgroundTransparency = .10
left.BorderSizePixel = 0
Instance.new("UICorner",left).CornerRadius = UDim.new(0,14)

local leftStroke = Instance.new("UIStroke")
leftStroke.Parent = left
leftStroke.Color = Color3.fromRGB(255,183,219)
leftStroke.Transparency = .35

local artPanel = Instance.new("Frame")
artPanel.Parent = frame
artPanel.Position = UDim2.fromOffset(514,72)
artPanel.Size = UDim2.fromOffset(190,352)
artPanel.BackgroundColor3 = Color3.fromRGB(248,235,255)
artPanel.BorderSizePixel = 0
Instance.new("UICorner",artPanel).CornerRadius = UDim.new(0,14)

local artStroke = Instance.new("UIStroke")
artStroke.Parent = artPanel
artStroke.Color = Color3.fromRGB(205,164,238)
artStroke.Transparency = .25

local artGradient = Instance.new("UIGradient")
artGradient.Parent = artPanel
artGradient.Rotation = 90
artGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(255,234,247)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(224,216,255)),
})

local artImage = Instance.new("ImageLabel")
artImage.Parent = artPanel
artImage.Position = UDim2.fromOffset(8,8)
artImage.Size = UDim2.fromOffset(174,268)
artImage.BackgroundTransparency = 1
artImage.ScaleType = Enum.ScaleType.Crop
artImage.Image = resolveKawaiiImage(CONFIG.UI.ANIME_IMAGE)
Instance.new("UICorner",artImage).CornerRadius = UDim.new(0,12)

local artFallback = Instance.new("TextLabel")
artFallback.Parent = artPanel
artFallback.Position = artImage.Position
artFallback.Size = artImage.Size
artFallback.BackgroundTransparency = 1
artFallback.Text = "૮ ˶ᵔ ᵕ ᵔ˶ ა\n\nKAWAII\nVOLCANO\nGIRL\n\n♡ ✦ ♡"
artFallback.TextColor3 = Color3.fromRGB(168,104,170)
artFallback.Font = Enum.Font.GothamBold
artFallback.TextSize = 17
artFallback.TextWrapped = true
artFallback.Visible = artImage.Image == ""

local roleBadge = Instance.new("TextLabel")
roleBadge.Parent = artPanel
roleBadge.Position = UDim2.fromOffset(8,286)
roleBadge.Size = UDim2.fromOffset(174,52)
roleBadge.BackgroundColor3 = Color3.fromRGB(255,255,255)
roleBadge.BackgroundTransparency = .2
roleBadge.BorderSizePixel = 0
roleBadge.TextColor3 = Color3.fromRGB(109,69,129)
roleBadge.Font = Enum.Font.GothamBold
roleBadge.TextSize = 11
roleBadge.TextWrapped = true
Instance.new("UICorner",roleBadge).CornerRadius = UDim.new(0,10)

local statusLabel = Instance.new("TextLabel")
statusLabel.Parent = left
statusLabel.Position = UDim2.fromOffset(10,10)
statusLabel.Size = UDim2.fromOffset(466,78)
statusLabel.BackgroundColor3 = Color3.fromRGB(80,59,98)
statusLabel.BackgroundTransparency = .05
statusLabel.BorderSizePixel = 0
statusLabel.TextColor3 = Color3.fromRGB(255,244,253)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
Instance.new("UICorner",statusLabel).CornerRadius = UDim.new(0,10)

local function makeCard(x,y,w,h)
    local t = Instance.new("TextLabel")
    t.Parent = left
    t.Position = UDim2.fromOffset(x,y)
    t.Size = UDim2.fromOffset(w,h)
    t.BackgroundColor3 = Color3.fromRGB(255,255,255)
    t.BackgroundTransparency = .08
    t.BorderSizePixel = 0
    t.TextColor3 = Color3.fromRGB(99,70,110)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 12
    t.TextWrapped = true
    Instance.new("UICorner",t).CornerRadius = UDim.new(0,10)

    local st = Instance.new("UIStroke")
    st.Parent = t
    st.Color = Color3.fromRGB(244,194,224)
    st.Transparency = .45

    return t
end

local teamLabel = makeCard(10,98,225,48)
local magnetLabel = makeCard(241,98,225,48)
local boatLabel = makeCard(10,154,225,48)
local raidLabel = makeCard(241,154,225,48)
local pressureLabel = makeCard(10,210,225,48)
local relicLabel = makeCard(241,210,225,48)
local golemLabel = makeCard(10,266,225,48)
local eggLabel = makeCard(241,266,225,48)

local autoToggle = Instance.new("TextButton")
autoToggle.Parent = left
autoToggle.Position = UDim2.fromOffset(10,322)
autoToggle.Size = UDim2.fromOffset(456,22)
autoToggle.BorderSizePixel = 0
autoToggle.Font = Enum.Font.GothamBold
autoToggle.TextSize = 11
autoToggle.TextColor3 = Color3.new(1,1,1)
autoToggle.AutoButtonColor = true
Instance.new("UICorner",autoToggle).CornerRadius = UDim.new(0,9)

local function refreshUI()
    STATE.TeamOnline = teamOnlineCount()

    statusLabel.Text =
        "STATUS: "..STATE.Status..
        "\nPHASE: "..STATE.Phase..
        "\nPLAYER: "..LP.Name..
        " | SLOT: "..tostring(STATE.TeamSlot)..
        " | CYCLE: "..tostring(STATE.Cycle)

    roleBadge.Text =
        "♡ ROLE ♡\n"..tostring(STATE.Role)

    teamLabel.Text =
        "TEAM  ♡  Online "..tostring(STATE.TeamOnline)..
        "/"..tostring(CONFIG.TEAM.EXPECTED_SIZE)..
        "\nBoarded slaves: "..tostring(STATE.TeamBoarded or 0)

    if isMaster() then
        magnetLabel.Text =
            "MAGNET  ✦  "..(
                STATE.Magnet == nil and "?"
                or (STATE.Magnet > 0 and ("YES ("..math.floor(STATE.Magnet)..")") or "NO")
            )
    else
        magnetLabel.Text = "MAGNET  ✦  MASTER handles"
    end

    boatLabel.Text = "BOAT  ♡  "..tostring(STATE.Boat)
    raidLabel.Text = "RAID  ✦  "..tostring(STATE.Raid)

    pressureLabel.Text =
        "PRESSURE  ♡  "..(
            STATE.Pressure == nil and "?" or (tostring(STATE.Pressure).."%")
        )

    relicLabel.Text =
        "RELIC HP  ✦  "..(
            STATE.Relic == nil and "?"
            or string.format("%.1f%%",STATE.Relic)
        )

    golemLabel.Text =
        "GOLEM  ♡  "..(
            (STATE.GolemCount or 0) <= 0 and "NONE"
            or (
                tostring(STATE.GolemCount).."x | HP "
                ..tostring(math.floor(STATE.GolemHP or 0))
            )
        )

    eggLabel.Text = "DRAGON EGG  ✦  "..tostring(STATE.Egg)

    if STATE.AutoVolcano then
        autoToggle.Text = "AUTO TEAM: ON  ♡  click to pause"
        autoToggle.BackgroundColor3 = Color3.fromRGB(219,111,171)
    else
        autoToggle.Text = "AUTO TEAM: OFF  ♡  click to resume"
        autoToggle.BackgroundColor3 = Color3.fromRGB(125,96,145)
    end
end

local function setStatus(text, phase)
    STATE.Status = tostring(text)
    if phase then STATE.Phase = tostring(phase) end
    refreshUI()
    print(
        "[PH TEAM]["..ROLE.."] "
        ..STATE.Phase.." | "..STATE.Status
    )
end

autoToggle.Activated:Connect(function()
    STATE.AutoVolcano = not STATE.AutoVolcano

    if STATE.AutoVolcano then
        setStatus("AUTO TEAM resumed","RESUME")
    else
        setStatus("AUTO TEAM paused","PAUSED")
    end
end)

refreshUI()

-- Mouse + touch draggable title bar.
do
    local dragging = false
    local dragStart
    local startPos

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            local d = input.Position-dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

--==============================================================
-- MOVEMENT / NOCLIP
--==============================================================

local noclip = false
local collisionBackup = {}

local function setPlayerNoclip(enabled)
    local c = char()
    if not c then return end

    if enabled then
        if not noclip then
            table.clear(collisionBackup)
            for _,v in ipairs(c:GetDescendants()) do
                if v:IsA("BasePart") then
                    collisionBackup[v] = v.CanCollide
                end
            end
        end

        noclip = true

        for _,v in ipairs(c:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
                v.AssemblyLinearVelocity = Vector3.zero
                v.AssemblyAngularVelocity = Vector3.zero
            end
        end
    else
        for part,old in pairs(collisionBackup) do
            if part and part.Parent then
                pcall(function() part.CanCollide = old end)
            end
        end
        table.clear(collisionBackup)
        noclip = false
    end
end

RunService.Stepped:Connect(function()
    if noclip then
        setPlayerNoclip(true)
    end
end)

local function jumpOutOfSeat(token, reason)
    if not waitAuto(token) then
        return false,"STOPPED"
    end

    local h = hum()
    if not h then
        return false,"NO_HUMANOID"
    end

    if not h.SeatPart then
        return true,"NOT_SEATED"
    end

    setStatus(
        "JUMP out of boat seat"..(reason and (" | "..tostring(reason)) or ""),
        "DISEMBARK"
    )

    local deadline = os.clock()+3.0

    while current(token) and os.clock() < deadline do
        if not alive() then
            return false,"DIED_WHILE_JUMPING"
        end

        if not h.SeatPart then
            task.wait(.12)

            local rr = root()
            if rr then
                pcall(function()
                    rr.AssemblyLinearVelocity = Vector3.zero
                    rr.AssemblyAngularVelocity = Vector3.zero
                end)
            end

            return true,"JUMP_UNSEATED"
        end

        -- User-required behavior: actually JUMP to break the VehicleSeat weld.
        pcall(function()
            h.Jump = true
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end)

        pcall(function()
            VirtualInputManager:SendKeyEvent(
                true,
                Enum.KeyCode.Space,
                false,
                game
            )
            task.wait(.06)
            VirtualInputManager:SendKeyEvent(
                false,
                Enum.KeyCode.Space,
                false,
                game
            )
        end)

        -- Sit=false is only a helper AFTER issuing Jump, not the primary method.
        pcall(function()
            h.Sit = false
        end)

        task.wait(.10)
    end

    return h.SeatPart == nil,
        h.SeatPart == nil and "JUMP_UNSEATED_LATE" or "JUMP_SEAT_STUCK"
end

local function tweenTo(cf, speed, token)
    if not waitAlive(token) then return false,"DEAD" end
    if not waitAuto(token) then return false,"STOPPED" end

    -- Critical rule:
    -- if player is seated, JUMP OUT FIRST. Never tween HRP against a seat weld.
    local h0 = hum()
    if h0 and h0.SeatPart then
        local unseatOk,unseatWhy = jumpOutOfSeat(token,"before player tween")
        if not unseatOk then
            return false,"UNSEAT_FAIL:"..tostring(unseatWhy)
        end
    end

    local moveSpeed = speed or CONFIG.PLAYER_SPEED
    local MAX_SEGMENT = 42
    local TARGET_EPS = 3
    local started = os.clock()
    local MAX_TOTAL = 120

    local h = hum()
    local oldAutoRotate = h and h.AutoRotate

    if h then
        h.AutoRotate = false
    end

    setPlayerNoclip(true)

    local function cleanup()
        setPlayerNoclip(false)

        local hh = hum()
        if hh and oldAutoRotate ~= nil then
            hh.AutoRotate = oldAutoRotate
        end
    end

    while current(token) do
        if not autoOn() then
            cleanup()
            if not waitAuto(token) then
                return false,"STOPPED"
            end
            setPlayerNoclip(true)
        end

        if not alive() then
            cleanup()
            return false,"DEAD"
        end

        local hh = hum()

        -- If Roblox re-seats us mid-route, cancel movement, jump out, then continue
        -- from the current replicated position.
        if hh and hh.SeatPart then
            setPlayerNoclip(false)

            local unseatOk,unseatWhy =
                jumpOutOfSeat(token,"re-seated during tween")

            if not unseatOk then
                cleanup()
                return false,"RESEAT_UNSEAT_FAIL:"..tostring(unseatWhy)
            end

            setPlayerNoclip(true)
        end

        local r = root()
        if not r then
            cleanup()
            return false,"NO_ROOT"
        end

        local delta = cf.Position-r.Position
        local dist = delta.Magnitude

        if dist <= TARGET_EPS then
            local dur = math.max(dist/moveSpeed,.03)

            local tw = TweenService:Create(
                r,
                TweenInfo.new(dur,Enum.EasingStyle.Linear),
                {CFrame=cf}
            )

            tw:Play()
            tw.Completed:Wait()

            pcall(function()
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
            end)

            cleanup()
            return true,"ARRIVED"
        end

        if os.clock()-started > MAX_TOTAL then
            cleanup()
            return false,"TIMEOUT"
        end

        local stepDist = math.min(MAX_SEGMENT,dist)
        local alpha = stepDist/dist
        local nextCF = r.CFrame:Lerp(cf,alpha)
        local dur = math.max(stepDist/moveSpeed,.04)

        local tw = TweenService:Create(
            r,
            TweenInfo.new(dur,Enum.EasingStyle.Linear),
            {CFrame=nextCF}
        )

        local done = false
        local conn

        conn = tw.Completed:Connect(function()
            done = true
            if conn then conn:Disconnect() end
        end)

        tw:Play()

        while not done do
            if not current(token) or not alive() then
                pcall(function() tw:Cancel() end)
                cleanup()
                return false,"INTERRUPTED"
            end

            if not autoOn() then
                pcall(function() tw:Cancel() end)
                done = true
                break
            end

            local h2 = hum()

            if h2 and h2.SeatPart then
                pcall(function() tw:Cancel() end)
                done = true
                break
            end

            local rr = root()
            if rr then
                pcall(function()
                    rr.AssemblyLinearVelocity = Vector3.zero
                    rr.AssemblyAngularVelocity = Vector3.zero
                end)
            end

            task.wait(.03)
        end

        task.wait(.015)
    end

    cleanup()
    return false,"STOPPED"
end


-- Boat-search is straight. Player landing is intentionally NOT a direct
-- sea-level line through the island: lift -> cross above terrain -> descend.
local function safeIslandApproach(targetCF, token)
    -- V2.2: no more exaggerated lift -> cross -> descend route.
    -- After jumping out of the boat, move in ONE safe chunked straight tween.
    -- tweenTo() already uses short segments + noclip + replicated-position recovery.
    if not waitAlive(token) then
        return false,"DEAD"
    end

    local h = hum()
    if h and h.SeatPart then
        local ok,why = jumpOutOfSeat(token,"before Fossil tween")
        if not ok then
            return false,"UNSEAT_FAIL:"..tostring(why)
        end
    end

    return tweenTo(targetCF,135,token)
end

local function aimAt(pos)
    local cam = workspace.CurrentCamera
    if not cam then return end

    pcall(function()
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position,pos)
    end)
end

local function pressKey(key, hold)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,key,false,game)
        task.wait(hold or .05)
        VirtualInputManager:SendKeyEvent(false,key,false,game)
    end)
end

local function holdE(sec)
    pressKey(Enum.KeyCode.E,sec or .65)
end

local function holdFossilEVirtual(seconds, token)
    -- Capture probe found PROMPT_COUNT = 0, so Fossil interaction is not a
    -- ProximityPrompt. There is no prompt object to hold directly.
    --
    -- At the exact manually verified standing CFrame, emulate a REAL E hold:
    -- key down -> wait -> key up. We only do this after reaching the captured
    -- interaction spot to minimize accidental Observation/Instinct toggles.
    local holdFor = seconds or CONFIG.FOSSIL.HOLD_SECONDS or 3.0

    if not waitAuto(token) then
        return false,"STOPPED"
    end

    if not current(token) or not alive() then
        return false,"NOT_READY"
    end

    local downOk = pcall(function()
        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.E,
            false,
            game
        )
    end)

    if not downOk then
        return false,"E_KEYDOWN_FAIL"
    end

    local deadline = os.clock()+holdFor

    while current(token)
    and alive()
    and autoOn()
    and os.clock() < deadline do
        task.wait(.03)
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.E,
            false,
            game
        )
    end)

    if not autoOn() then
        return false,"PAUSED"
    end

    return true,"VIRTUAL_E_HOLD"
end

local function equipTooltip(tip)
    local c = char()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if not c or not backpack then return nil end

    for _,tool in ipairs(c:GetChildren()) do
        if tool:IsA("Tool") and tostring(tool.ToolTip) == tip then
            return tool
        end
    end

    for _,tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tostring(tool.ToolTip) == tip then
            local h = hum()
            if h then
                pcall(function() h:EquipTool(tool) end)
                task.wait(.10)
                return tool
            end
        end
    end
end

--==============================================================
-- REMOTES
--==============================================================

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local CommF = Remotes and Remotes:FindFirstChild("CommF_")
if not CommF then
    CommF = ReplicatedStorage:FindFirstChild("CommF_",true)
end

local Modules = ReplicatedStorage:FindFirstChild("Modules")
local Net = Modules and Modules:FindFirstChild("Net")
local RegisterAttack = Net and Net:FindFirstChild("RE/RegisterAttack")
local RegisterHit = Net and Net:FindFirstChild("RE/RegisterHit")

local function ensureMarines()
    if LP.Team and LP.Team.Name == "Marines" then
        return true
    end

    if not CommF then return false end

    pcall(function()
        CommF:InvokeServer("SetTeam","Marines")
    end)

    local deadline = os.clock()+10
    repeat
        task.wait(.25)
        if LP.Team and LP.Team.Name == "Marines" then
            return true
        end
    until os.clock() >= deadline

    return false
end

--==============================================================
-- GUI CLICK HELPERS / ONE-TIME MAGNET CHECK
--==============================================================

local function visibleGui(o)
    if not o or not o:IsA("GuiObject") then return false end

    local p = o
    while p and p ~= PG do
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("CanvasGroup") and p.GroupTransparency >= .995 then return false end
        p = p.Parent
    end

    return true
end

local function insetClick(btn)
    if not btn or not visibleGui(btn) then return false end

    local p = btn.AbsolutePosition
    local s = btn.AbsoluteSize
    local center = Vector2.new(p.X+s.X/2,p.Y+s.Y/2)
    local inset = select(1,GuiService:GetGuiInset())
    local pt = center+inset

    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(pt.X,pt.Y,0,true,game,0)
        task.wait(.07)
        VirtualInputManager:SendMouseButtonEvent(pt.X,pt.Y,0,false,game,0)
    end)

    task.wait(.10)
    return ok
end

local function signalButton(btn)
    if not btn then return false end

    if type(getconnections) == "function" then
        local ok,cons = pcall(function() return getconnections(btn.Activated) end)
        if ok and type(cons) == "table" and #cons > 0 then
            for _,c in ipairs(cons) do
                if c.Fire then
                    local fired = pcall(function() c:Fire() end)
                    if fired then task.wait(.08) return true end
                elseif c.Function then
                    local fired = pcall(function() c.Function() end)
                    if fired then task.wait(.08) return true end
                end
            end
        end
    end

    if type(firesignal) == "function" then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if ok then task.wait(.08) return true end
    end

    return insetClick(btn)
end

local function waitUntil(fn, timeout)
    local deadline = os.clock()+(timeout or 1)
    repeat
        local ok,res = pcall(fn)
        if ok and res then return true end
        task.wait(.04)
    until os.clock() >= deadline
    return false
end

local function inventoryRoot()
    local top = PG:FindFirstChild("Inventory")
    return top and top:FindFirstChild("Inventory")
end

local function inventoryOpen()
    local inv = inventoryRoot()
    if not inv then return false end

    local main = inv:FindFirstChild("Main")
    local header = main and main:FindFirstChild("Header")
    local t = header and header:FindFirstChild("Title")

    if t and (t:IsA("TextLabel") or t:IsA("TextButton")) then
        return visibleGui(t) and normalize(t.Text) == "items"
    end

    return visibleGui(inv)
end

local function buttonInside(o)
    if not o then return nil end
    if o:IsA("TextButton") or o:IsA("ImageButton") then return o end

    for _,d in ipairs(o:GetDescendants()) do
        if d:IsA("TextButton") or d:IsA("ImageButton") then
            return d
        end
    end
end

local function menuRoot()
    local hudRoot = PG:FindFirstChild("HUDRoot")
    local f = hudRoot and hudRoot:FindFirstChild("Frame")
    local hud = f and f:FindFirstChild("HUD")
    local col = hud and hud:FindFirstChild("LowerLeftColumn")
    return col and col:FindFirstChild("Menu")
end

local function ensureInventoryOpen()
    if inventoryOpen() then return true end

    for _=1,4 do
        local menu = menuRoot()
        local items = menu and menu:FindFirstChild("Items")

        if not items or not visibleGui(items) then
            local toggle = menu and menu:FindFirstChild("Menu")
            if toggle then
                signalButton(toggle)
                waitUntil(function()
                    local m = menuRoot()
                    local i = m and m:FindFirstChild("Items")
                    return i and visibleGui(i)
                end,.8)
            end
        end

        menu = menuRoot()
        items = menu and menu:FindFirstChild("Items")

        if items and visibleGui(items) then
            insetClick(items)
            if waitUntil(inventoryOpen,1.5) then
                return true
            end
        end

        task.wait(.15)
    end

    return false
end

local function selectStash()
    local inv = inventoryRoot()
    local main = inv and inv:FindFirstChild("Main")
    local nav = main and main:FindFirstChild("NavigationRail")

    local deadline = os.clock()+3
    local cat4

    repeat
        inv = inventoryRoot()
        main = inv and inv:FindFirstChild("Main")
        nav = main and main:FindFirstChild("NavigationRail")
        cat4 = nav and nav:FindFirstChild("Category4")
        if cat4 then break end
        task.wait(.05)
    until os.clock() >= deadline

    if not cat4 then return false end

    local b = buttonInside(cat4)
    if not b then return false end

    insetClick(b)
    task.wait(.30)
    return true
end

local function searchBox()
    local inv = inventoryRoot()
    if not inv then return nil end

    for _,o in ipairs(inv:GetDescendants()) do
        if o:IsA("TextBox") and visibleGui(o) then
            local ph = normalize(o.PlaceholderText)
            local nm = normalize(o.Name)
            if ph:find("search",1,true)
            or nm:find("search",1,true) then
                return o
            end
        end
    end
end

local function pageGrid()
    local inv = inventoryRoot()
    local main = inv and inv:FindFirstChild("Main")
    local page = main and main:FindFirstChild("PageContent")
    return page and page:FindFirstChild("TileGrid")
end

local function rightCard()
    local inv = inventoryRoot()
    local right = inv and inv:FindFirstChild("RightCard")
    local card = right and right:FindFirstChild("ItemCard")
    if not card then return nil,nil end

    local titleRoot = card:FindFirstChild("Title")
    local titleObj = titleRoot and titleRoot:FindFirstChild("Text")

    local display = card:FindFirstChild("Display")
    local footer = display and display:FindFirstChild("Footer")
    local ribbon = footer and footer:FindFirstChild("CountRibbon")
    local countObj = ribbon and ribbon:FindFirstChild("Count")

    if not titleObj or not countObj then return nil,nil end

    local count = tonumber(tostring(countObj.Text or ""):gsub(",",""):match("(%d+)"))
    return tostring(titleObj.Text or ""),count
end

local function findInventoryClose()
    local inv = inventoryRoot()
    local main = inv and inv:FindFirstChild("Main")
    if not inv or not main then return nil end

    local target = Vector2.new(
        main.AbsolutePosition.X+main.AbsoluteSize.X-20,
        main.AbsolutePosition.Y+20
    )

    local best,bestDist = nil,math.huge

    for _,o in ipairs(inv:GetDescendants()) do
        if (o:IsA("TextButton") or o:IsA("ImageButton"))
        and visibleGui(o)
        and o.AbsoluteSize.X <= 130
        and o.AbsoluteSize.Y <= 130 then
            local p = o.AbsolutePosition
            local s = o.AbsoluteSize
            local c = Vector2.new(p.X+s.X/2,p.Y+s.Y/2)
            local d = (c-target).Magnitude

            if d < bestDist then
                bestDist = d
                best = o
            end
        end
    end

    return best
end

local function closeInventory()
    if not inventoryOpen() then return true end

    local b = findInventoryClose()
    if not b then return false end

    insetClick(b)
    return waitUntil(function() return not inventoryOpen() end,1.5)
end

local function checkVolcanicMagnet()
    setStatus("Checking Volcanic Magnet in Stash","MAGNET CHECK")

    -- Keep UI visible. Only disable input interception while the game UI is clicked.
    local oldFrameActive = frame.Active
    local oldTitleActive = title.Active
    frame.Active = false
    title.Active = false
    task.wait(.05)

    local count = nil
    local why = "UNKNOWN"

    local ok,err = xpcall(function()
        if not ensureInventoryOpen() then
            why = "ITEMS_OPEN_FAIL"
            return
        end

        if not selectStash() then
            why = "STASH_OPEN_FAIL"
            return
        end

        local search = searchBox()
        local grid = pageGrid()

        if not search or not grid then
            why = "SEARCH_OR_GRID_MISSING"
            return
        end

        search.Text = "Volcanic Magnet"
        task.wait(.35)

        local candidates = {}

        for _,tile in ipairs(grid:GetChildren()) do
            if tostring(tile.Name):match("^Tile%-") then
                local btn = buttonInside(tile)
                if btn and visibleGui(btn) then
                    candidates[#candidates+1] = btn
                end
            end
        end

        if #candidates == 0 then
            count = 0
            why = "ABSENT"
        else
            for _,btn in ipairs(candidates) do
                insetClick(btn)

                local deadline = os.clock()+.65
                repeat
                    local name,n = rightCard()
                    if normalize(name) == "volcanic magnet" and n ~= nil then
                        count = n
                        why = "FOUND"
                        break
                    end
                    task.wait(.04)
                until os.clock() >= deadline

                if count ~= nil then break end
            end
        end

        search.Text = ""
        closeInventory()
    end,function(e)
        return tostring(e)
    end)

    frame.Active = oldFrameActive
    title.Active = oldTitleActive

    if not ok then
        setStatus("Magnet check error: "..tostring(err),"MAGNET CHECK")
        return nil
    end

    STATE.Magnet = count
    refreshUI()

    setStatus(
        "Volcanic Magnet = "..tostring(count).." | "..tostring(why),
        "MAGNET CHECK"
    )

    return count
end

local function ensureMagnetBaseline(reason)
    -- IMPORTANT:
    -- This is NOT called for death/boat-loss recovery.
    -- It runs at startup, then optionally once after a completed event.
    if STATE.MagnetChecked and not STATE.MagnetNeedsRefresh then
        return STATE.Magnet ~= nil and STATE.Magnet > 0
    end

    for attempt=1,CONFIG.MAGNET_CHECK.STARTUP_RETRIES do
        setStatus(
            "Magnet check "..attempt.."/"..CONFIG.MAGNET_CHECK.STARTUP_RETRIES..
            " | "..tostring(reason),
            "MAGNET CHECK"
        )

        local count = checkVolcanicMagnet()

        if count ~= nil then
            STATE.Magnet = count
            STATE.MagnetChecked = true
            STATE.MagnetNeedsRefresh = false
            refreshUI()

            if count > 0 then
                setStatus(
                    "Magnet confirmed once -> hunt loop armed",
                    "READY"
                )
                return true
            end

            setStatus(
                "NO Volcanic Magnet -> Auto Magnet required",
                "WAIT MAGNET"
            )
            return false
        end

        if attempt < CONFIG.MAGNET_CHECK.STARTUP_RETRIES then
            task.wait(CONFIG.MAGNET_CHECK.RETRY_GAP)
        end
    end

    setStatus(
        "Magnet check failed after controlled retries",
        "MAGNET CHECK"
    )
    return false
end

--==============================================================
-- PORTAL ROUTING
-- Uses the game's own island portals.
-- Player only SAFE-TWEENs to a portal CFrame; the portal performs the teleport.
--==============================================================

local function nearestRegion()
    local rr = root()
    if not rr then return "UNKNOWN",math.huge end

    local p = rr.Position

    local anchors = {
        TIKI = CONFIG.PORTALS.Tiki_To_Castle.Position,
        CASTLE = CONFIG.PORTALS.Castle_To_Tiki.Position,
        TURTLE = CONFIG.PORTALS.Turtle_To_Castle.Position,
        HYDRA = CONFIG.PORTALS.Hydra_To_Castle.Position,
    }

    local best = "UNKNOWN"
    local bestDist = math.huge

    for name,pos in pairs(anchors) do
        local d = (p-pos).Magnitude
        if d < bestDist then
            bestDist = d
            best = name
        end
    end

    return best,bestDist
end

local function enterPortalSafe(cf,label,token)
    setStatus("Portal route -> "..label,"PORTAL")

    if not alive() then
        return false,"DEAD"
    end

    -- If somehow seated, obey the project rule: jump out first.
    local h = hum()
    if h and h.SeatPart then
        local ok,why = jumpOutOfSeat(token,"before portal")
        if not ok then
            return false,"UNSEAT_FAIL:"..tostring(why)
        end
    end

    local before = root()
    before = before and before.Position or nil

    -- Safe approach to the portal; no long CFrame teleport.
    local approach = cf * CFrame.new(0,8,0)

    local ok,why = tweenTo(approach,155,token)
    if not ok then
        return false,"APPROACH_FAIL:"..tostring(why)
    end

    ok,why = tweenTo(cf,95,token)
    if not ok then
        return false,"ENTRY_FAIL:"..tostring(why)
    end

    -- Wait for the game's portal transition.
    local deadline = os.clock()+5

    repeat
        if not current(token) then
            return false,"STOPPED"
        end

        if not alive() then
            return false,"DIED_IN_PORTAL"
        end

        local rr = root()
        if rr and before and (rr.Position-before).Magnitude > 700 then
            task.wait(.7)
            return true,"PORTAL_OK"
        end

        task.wait(.10)
    until os.clock() >= deadline

    return false,"NO_PORTAL_TRANSITION"
end

local function routeToTiki(token)
    local region,dist = nearestRegion()

    setStatus(
        "Route to Tiki | "..tostring(region)..
        " | nearest "..tostring(math.floor(dist or 0)),
        "PORTAL"
    )

    if region == "TIKI" then
        return true,"ALREADY_TIKI"
    end

    if region == "CASTLE" then
        return enterPortalSafe(
            CONFIG.PORTALS.Castle_To_Tiki,
            "Castle -> Tiki",
            token
        )
    end

    if region == "HYDRA" then
        local ok,why = enterPortalSafe(
            CONFIG.PORTALS.Hydra_To_Castle,
            "Hydra -> Castle",
            token
        )
        if not ok then return false,why end

        task.wait(.65)

        return enterPortalSafe(
            CONFIG.PORTALS.Castle_To_Tiki,
            "Castle -> Tiki",
            token
        )
    end

    if region == "TURTLE" then
        local ok,why = enterPortalSafe(
            CONFIG.PORTALS.Turtle_To_Castle,
            "Turtle -> Castle",
            token
        )
        if not ok then return false,why end

        task.wait(.65)

        return enterPortalSafe(
            CONFIG.PORTALS.Castle_To_Tiki,
            "Castle -> Tiki",
            token
        )
    end

    return false,"UNKNOWN_REGION"
end

--==============================================================
-- BOAT
--==============================================================

local function boatOwner(boat)
    if not boat then return nil end

    local attr = boat:GetAttribute("Owner")
    if attr ~= nil then
        return tostring(attr)
    end

    local owner = boat:FindFirstChild("Owner")
    if owner and owner:IsA("ValueBase") then
        return tostring(owner.Value)
    end
end

local function readBoatHealth(boat)
    if not boat then return nil end

    for _,attrName in ipairs({"Health","BoatHealth","HP"}) do
        local v = boat:GetAttribute(attrName)
        if tonumber(v) ~= nil then
            return tonumber(v)
        end
    end

    for _,name in ipairs({"Health","BoatHealth","HP"}) do
        local v = boat:FindFirstChild(name,true)
        if v and v:IsA("ValueBase") and tonumber(v.Value) ~= nil then
            return tonumber(v.Value)
        end
    end

    return nil
end

local function boatAlive(boat)
    if not boat or not boat.Parent then
        return false
    end

    local hp = readBoatHealth(boat)
    if hp ~= nil and hp <= 0 then
        return false
    end

    return true
end

local function getOwnBoat()
    local boats = workspace:FindFirstChild("Boats")
    if not boats then return nil end

    for _,b in ipairs(boats:GetChildren()) do
        if b.Name == CONFIG.BOAT_NAME and boatAlive(b) then
            local owner = boatOwner(b)
            if owner == LP.Name or owner == tostring(LP) then
                return b
            end
        end
    end
end

local function masterBoat()
    local boats = workspace:FindFirstChild("Boats")
    if not boats then return nil end

    for _,b in ipairs(boats:GetChildren()) do
        if b.Name == CONFIG.BOAT_NAME and boatAlive(b) then
            local owner = boatOwner(b)

            if owner == CONFIG.TEAM.MASTER_NAME then
                return b
            end

            local driver = b:FindFirstChildWhichIsA("VehicleSeat",true)
            local occ = driver and driver.Occupant
            local c = occ and occ.Parent

            if c and c.Name == CONFIG.TEAM.MASTER_NAME then
                return b
            end
        end
    end
end

local function passengerSeats(boat)
    local seats = {}
    if not boat then return seats end

    for _,o in ipairs(boat:GetDescendants()) do
        if o:IsA("Seat") and not o:IsA("VehicleSeat") then
            seats[#seats+1] = o
        end
    end

    table.sort(seats,function(a,b)
        local ap,bp = a.Position,b.Position
        if math.abs(ap.X-bp.X) > .1 then return ap.X < bp.X end
        if math.abs(ap.Z-bp.Z) > .1 then return ap.Z < bp.Z end
        return a:GetFullName() < b:GetFullName()
    end)

    return seats
end

local function teamBoardedCount(boat)
    local set = teamNameSet()
    local count = 0

    for _,seat in ipairs(passengerSeats(boat)) do
        local occ = seat.Occupant
        local c = occ and occ.Parent

        if c and set[c.Name] and c.Name ~= CONFIG.TEAM.MASTER_NAME then
            count += 1
        end
    end

    STATE.TeamBoarded = count
    return count
end

local function boardPassenger(boat,token)
    if not boatAlive(boat) then
        return false,"NO_BOAT"
    end

    local h = hum()
    if not h then
        return false,"NO_HUMANOID"
    end

    -- Already sitting somewhere in this boat.
    if h.SeatPart and h.SeatPart:IsDescendantOf(boat) then
        STATE.Boat = "PASSENGER"
        refreshUI()
        return true,"ALREADY_SEATED"
    end

    local seats = passengerSeats(boat)
    if #seats == 0 then
        return false,"NO_PASSENGER_SEATS"
    end

    local preferred = math.clamp(TEAM_SLOT,1,#seats)
    local seat = seats[preferred]

    if seat.Occupant and seat.Occupant ~= h then
        seat = nil
        for _,candidate in ipairs(seats) do
            if not candidate.Occupant then
                seat = candidate
                break
            end
        end
    end

    if not seat then
        return false,"ALL_PASSENGER_SEATS_BUSY"
    end

    setStatus(
        "Safe tween -> passenger seat "..preferred,
        "BOARD TEAM BOAT"
    )

    local ok,why = tweenTo(
        seat.CFrame*CFrame.new(0,3,0),
        145,
        token
    )

    if not ok then
        return false,"SEAT_TWEEN:"..tostring(why)
    end

    pcall(function()
        seat:Sit(h)
    end)

    if firetouchinterest and root() then
        pcall(function()
            firetouchinterest(root(),seat,0)
            task.wait(.08)
            firetouchinterest(root(),seat,1)
        end)
    end

    local deadline = os.clock()+4

    repeat
        if h.SeatPart == seat or seat.Occupant == h then
            STATE.Boat = "PASSENGER"
            refreshUI()
            return true,"SEATED"
        end

        pcall(function()
            seat:Sit(h)
        end)

        task.wait(.10)
    until os.clock() >= deadline

    return false,"SEAT_TIMEOUT"
end

local function waitForTeamBoarding(boat,token)
    if not isMaster() then
        return true
    end

    local roster = teamPlayerNames()
    local desired = math.min(
        CONFIG.TEAM.REQUIRED_SLAVES,
        math.max(#roster-1,0)
    )

    -- If roster isn't configured yet, still display/await the requested size.
    if desired <= 0 then
        desired = CONFIG.TEAM.REQUIRED_SLAVES
    end

    local deadline = os.clock()+CONFIG.TEAM.WAIT_FOR_TEAM_SECONDS

    while current(token) and boatAlive(boat) do
        local boarded = teamBoardedCount(boat)

        setStatus(
            "Waiting team on Grand Brigade | "
            ..boarded.."/"..desired.." slaves",
            "TEAM BOARDING"
        )

        if boarded >= desired then
            return true
        end

        if os.clock() >= deadline then
            if CONFIG.TEAM.ALLOW_PARTIAL_AFTER_TIMEOUT
            and boarded >= CONFIG.TEAM.MIN_SLAVES_AFTER_TIMEOUT then
                setStatus(
                    "Team wait timeout -> depart with "..boarded.." slaves",
                    "TEAM BOARDING"
                )
                return true
            end

            deadline = os.clock()+10
        end

        task.wait(.35)
    end

    return boatAlive(boat)
end

local function buyBoat(token)
    local existing = getOwnBoat()
    if existing then
        STATE.Boat = "READY"
        refreshUI()
        return existing
    end

    -- Use island portals instead of doing one huge cross-map player tween.
    local rr = root()

    if rr
    and (rr.Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude > 3500 then
        local portalOk,portalWhy = routeToTiki(token)

        if not portalOk then
            setStatus(
                "Portal route failed: "..tostring(portalWhy)..
                " -> safe tween fallback",
                "BUY BOAT"
            )
        end
    end

    setStatus("Safe tween -> Tiki Boat Dealer","BUY BOAT")

    local moveOk,moveWhy =
        tweenTo(CONFIG.BOAT_DEALER_CFRAME,165,token)

    if not moveOk then
        setStatus(
            "Boat Dealer tween failed: "..tostring(moveWhy),
            "BUY BOAT"
        )
        return nil
    end

    pcall(function()
        if CommF then CommF:InvokeServer("SetSpawnPoint") end
    end)

    for attempt=1,5 do
        setStatus("Buying MarineGrandBrigade "..attempt.."/5","BUY BOAT")

        pcall(function()
            if CommF then
                CommF:InvokeServer("BuyBoat",CONFIG.BOAT_BUY_NAME)
            end
        end)

        task.wait(1)

        local b = getOwnBoat()
        if b then
            STATE.Boat = "READY"
            refreshUI()
            return b
        end
    end

    STATE.Boat = "BUY FAIL"
    refreshUI()
    return nil
end

local function boardDriver(boat, token)
    if not boat then return false end

    local seat = boat:FindFirstChild("VehicleSeat")
        or boat:FindFirstChildWhichIsA("VehicleSeat",true)

    if not seat then return false end

    local h = hum()
    if not h then return false end

    if seat.Occupant == h then return true end

    tweenTo(seat.CFrame*CFrame.new(0,3,0),CONFIG.PLAYER_SPEED,token)

    pcall(function() seat:Sit(h) end)

    if firetouchinterest and root() then
        pcall(function()
            firetouchinterest(root(),seat,0)
            task.wait(.1)
            firetouchinterest(root(),seat,1)
        end)
    end

    local deadline = os.clock()+4
    repeat
        if seat.Occupant == h then
            STATE.Boat = "DRIVING"
            refreshUI()
            return true
        end

        pcall(function() seat:Sit(h) end)
        task.wait(.10)
    until os.clock() >= deadline

    return seat.Occupant == h
end

local function boatNoclip(boat)
    if not boat then return end
    for _,v in ipairs(boat:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end

local function stopBoatMotion(boat)
    if not boat or not boat.Parent then return end

    local seat = boat:FindFirstChildWhichIsA("VehicleSeat",true)

    if seat then
        pcall(function()
            seat.ThrottleFloat = 0
            seat.SteerFloat = 0
        end)
    end

    for _,v in ipairs(boat:GetDescendants()) do
        if v:IsA("BasePart") then
            pcall(function()
                v.AssemblyLinearVelocity = Vector3.zero
                v.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

local function dismountBoat(boat,token)
    stopBoatMotion(boat)

    local h = hum()
    if not h then
        return false,"NO_HUMANOID"
    end

    if not h.SeatPart then
        return true,"ALREADY_UNSEATED"
    end

    -- Mandatory boat exit path:
    -- JUMP first -> confirm SeatPart=nil -> only then may player tween.
    local ok,why = jumpOutOfSeat(token,"Prehistoric island found")

    if not ok then
        return false,why
    end

    stopBoatMotion(boat)
    task.wait(.12)

    return true,why
end

local function prehistoricMarker()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    return locations and (
        locations:FindFirstChild("Prehistoric Island")
        or locations:FindFirstChild("PrehistoricIsland")
    )
end

local function prehistoricIsland()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("PrehistoricIsland")
end

local function boatFlyTo(boat,targetPos,token)
    if not boatAlive(boat) then
        return false,"BOAT_DESTROYED"
    end

    if not alive() then
        return false,"PLAYER_DIED"
    end

    local start = boat:GetPivot()
    local startPos = start.Position
    local dist = (targetPos-startPos).Magnitude
    local duration = math.max(dist/CONFIG.BOAT_SPEED,.05)
    local started = os.clock()

    while current(token) do
        if not autoOn() then
            stopBoatMotion(boat)

            if not waitAuto(token) then
                return false,"STOPPED"
            end

            -- Rebuild this leg from the boat's current replicated position.
            start = boat:GetPivot()
            startPos = start.Position
            dist = (targetPos-startPos).Magnitude
            duration = math.max(dist/CONFIG.BOAT_SPEED,.05)
            started = os.clock()
        end

        if prehistoricIsland() or prehistoricMarker() then
            return true,"PREHISTORIC_FOUND"
        end

        if not alive() then
            return false,"PLAYER_DIED"
        end

        if not boatAlive(boat) then
            return false,"BOAT_DESTROYED"
        end

        local a = math.clamp((os.clock()-started)/duration,0,1)
        local pos = startPos:Lerp(targetPos,a)
        local dir = targetPos-pos

        local cf
        if dir.Magnitude > .5 then
            cf = CFrame.lookAt(
                pos,
                pos+Vector3.new(dir.X,0,dir.Z)
            )
        else
            cf = CFrame.new(pos)*start.Rotation
        end

        boatNoclip(boat)

        pcall(function()
            boat:PivotTo(cf)
        end)

        if a >= 1 then
            return true,"LEG_COMPLETE"
        end

        RunService.Heartbeat:Wait()
    end

    return false,"STOPPED"
end

local function searchPrehistoric(boat,token)
    -- Straight-only Sea 6 search.
    -- If player dies or boat is destroyed, return a reason to the recovery loop.
    if not boatAlive(boat) then
        return nil,"BOAT_DESTROYED"
    end

    if not alive() then
        return nil,"PLAYER_DIED"
    end

    local startPos = boat:GetPivot().Position
    local center = CONFIG.SEA_PATROL_CENTER

    local flatDir = Vector3.new(
        center.X-startPos.X,
        0,
        center.Z-startPos.Z
    )

    if flatDir.Magnitude < 1 then
        local look = boat:GetPivot().LookVector
        flatDir = Vector3.new(look.X,0,look.Z)
    end

    if flatDir.Magnitude < 1 then
        flatDir = Vector3.new(0,0,-1)
    end

    local dir = flatDir.Unit
    local STEP = 6500
    local leg = 1

    while current(token) do
        if not alive() then
            return nil,"PLAYER_DIED"
        end

        if not boatAlive(boat) then
            return nil,"BOAT_DESTROYED"
        end

        local island = prehistoricIsland()
        if island then
            return island,"MAP_FOUND"
        end

        if prehistoricMarker() then
            setStatus(
                "Prehistoric marker found -> waiting map",
                "SEA SEARCH"
            )

            local deadline = os.clock()+12
            repeat
                if not alive() then
                    return nil,"PLAYER_DIED"
                end

                if not boatAlive(boat) then
                    return nil,"BOAT_DESTROYED"
                end

                island = prehistoricIsland()
                if island then
                    return island,"MARKER_FOUND"
                end

                task.wait(.15)
            until os.clock() >= deadline
        end

        local target = startPos + dir*(STEP*leg)

        setStatus(
            "Sea 6 straight hunt | leg "..leg..
            " | retry "..STATE.HuntRetry,
            "SEA SEARCH"
        )

        local moved,why = boatFlyTo(boat,target,token)

        if not moved then
            return nil,why
        end

        island = prehistoricIsland()
        if island then
            return island,"MAP_FOUND"
        end

        leg += 1
    end

    return nil,"STOPPED"
end

local function waitForRespawnRecovery(token)
    setStatus(
        "Player died -> waiting respawn, Magnet cache preserved",
        "RECOVERY"
    )

    local deadline = os.clock()+CONFIG.RECOVERY.RESPAWN_WAIT

    repeat
        if alive() then
            task.wait(1.0)
            return true
        end
        task.wait(.20)
    until os.clock() >= deadline or not current(token)

    return alive()
end

local function huntPrehistoricWithRecovery(token)
    -- Death and boat destruction stay INSIDE this loop.
    -- They never call checkVolcanicMagnet again.
    while current(token) do
        local existingIsland = prehistoricIsland()
        if existingIsland then
            local currentBoat = getOwnBoat()

            if currentBoat then
                stopBoatMotion(currentBoat)

                local ok,why = dismountBoat(currentBoat,token)
                if not ok and alive() then
                    setStatus(
                        "Existing island | dismount retry: "..tostring(why),
                        "DISEMBARK"
                    )
                    task.wait(.30)
                    continue
                end
            end

            STATE.Boat = "PARKED / ISLAND FOUND"
            refreshUI()
            return existingIsland,"EXISTING_ISLAND"
        end

        if not alive() then
            STATE.HuntRetry += 1

            if not waitForRespawnRecovery(token) then
                return nil,"RESPAWN_TIMEOUT"
            end

            -- Respawn can change team in some situations; repair it quietly.
            ensureMarines()
        end

        local boat = getOwnBoat()

        if not boatAlive(boat) then
            STATE.HuntRetry += 1
            STATE.Boat = "REBUY"
            refreshUI()

            setStatus(
                "Boat missing/destroyed -> portal Tiki -> rebuy, Magnet NOT rechecked",
                "RECOVERY"
            )

            boat = buyBoat(token)

            if not boat then
                task.wait(CONFIG.RECOVERY.BOAT_REBUY_GAP)
                continue
            end
        end

        if not boardDriver(boat,token) then
            if not alive() then
                STATE.HuntRetry += 1
                waitForRespawnRecovery(token)
            elseif not boatAlive(boat) then
                STATE.HuntRetry += 1
                STATE.Boat = "DESTROYED"
                refreshUI()
            else
                setStatus("Driver seat failed -> retrying same hunt","RECOVERY")
                task.wait(.75)
            end
            continue
        end

        waitForTeamBoarding(boat,token)

        local island,why = searchPrehistoric(boat,token)

        if island then
            setStatus(
                "Prehistoric found -> stop boat -> JUMP out -> island tween",
                "DISEMBARK"
            )

            stopBoatMotion(boat)

            local unseatOk,unseatWhy = dismountBoat(boat,token)

            if not unseatOk then
                setStatus(
                    "Island found but dismount failed: "..tostring(unseatWhy),
                    "DISEMBARK"
                )

                if not alive() then
                    waitForRespawnRecovery(token)
                    continue
                end

                task.wait(.35)
                continue
            end

            STATE.Boat = "PARKED / ISLAND FOUND"
            refreshUI()
            return island,why
        end

        STATE.HuntRetry += 1

        if why == "PLAYER_DIED" then
            waitForRespawnRecovery(token)

        elseif why == "BOAT_DESTROYED" then
            STATE.Boat = "DESTROYED"
            refreshUI()
            setStatus(
                "Boat destroyed -> rebuy + continue straight hunt",
                "RECOVERY"
            )
            task.wait(CONFIG.RECOVERY.BOAT_REBUY_GAP)

        elseif why == "STOPPED" then
            return nil,why

        else
            setStatus(
                "Sea hunt retry: "..tostring(why),
                "RECOVERY"
            )
            task.wait(.75)
        end
    end

    return nil,"STOPPED"
end

--==============================================================
-- PREHISTORIC EVENT
--==============================================================

local function relic(island)
    local core = island and island:FindFirstChild("Core")
    return core and core:FindFirstChild("PrehistoricRelic")
end

local function relicPart(island)
    local r = relic(island)
    if not r then return nil end

    return r:FindFirstChild("Inside")
        or r:FindFirstChild("Skull")
        or r:FindFirstChildWhichIsA("BasePart",true)
end

local function capturedFossilTarget(island)
    local r = relic(island)
    if not r then return nil,nil end

    local ok,pivot = pcall(function()
        return r:GetPivot()
    end)

    if not ok or not pivot then
        return nil,nil
    end

    return pivot * CONFIG.FOSSIL.PLAYER_RELATIVE_TO_RELIC, pivot
end

local function parsePercent(text)
    return tonumber(tostring(text or ""):match("(%d+)%s*%%"))
end

local function topHUD()
    local main = PG:FindFirstChild("Main")
    return main and main:FindFirstChild("TopHUDList")
end

local function hudActuallyVisible(o)
    if not o or not o:IsA("GuiObject") then
        return false
    end

    local p = o
    while p and p ~= PG do
        if p:IsA("ScreenGui") and not p.Enabled then
            return false
        end

        if p:IsA("GuiObject") and not p.Visible then
            return false
        end

        if p:IsA("CanvasGroup") and p.GroupTransparency >= .995 then
            return false
        end

        p = p.Parent
    end

    return o.AbsoluteSize.X > 0 and o.AbsoluteSize.Y > 0
end

local function visibleHUDTextObjects()
    local hud = topHUD()
    local out = {}

    if not hud then
        return out
    end

    for _,o in ipairs(hud:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton"))
        and hudActuallyVisible(o)
        and tostring(o.Text or "") ~= "" then
            out[#out+1] = o
        end
    end

    table.sort(out,function(a,b)
        local sa = a.AbsoluteSize.X*a.AbsoluteSize.Y + a.ZIndex*100
        local sb = b.AbsoluteSize.X*b.AbsoluteSize.Y + b.ZIndex*100
        return sa > sb
    end)

    return out
end

local function allTopHUDText()
    local parts = {}

    for _,o in ipairs(visibleHUDTextObjects()) do
        parts[#parts+1] = tostring(o.Text)
    end

    return table.concat(parts,"\n")
end

local function findVisiblePercent(labelNeedle)
    labelNeedle = string.lower(labelNeedle)

    for _,o in ipairs(visibleHUDTextObjects()) do
        local raw = tostring(o.Text or "")
        local low = string.lower(raw)

        if low:find(labelNeedle,1,true) then
            local n = parsePercent(raw)
            if n ~= nil then
                return n
            end
        end
    end

    return nil
end

local function eventActive()
    local txt = string.lower(allTopHUDText())

    if txt:find("time left",1,true)
    and (
        txt:find("volcano pressure",1,true)
        or txt:find("relic health",1,true)
    ) then
        return true
    end

    local island = prehistoricIsland()
    return island and island:GetAttribute("IsMinigameActive") == true or false
end

local function pressure()
    local exact = findVisiblePercent("volcano pressure")
    if exact ~= nil then
        return exact
    end

    local txt = allTopHUDText()
    return tonumber(
        txt:match("[Vv]olcano%s+[Pp]ressure%s*:%s*(%d+)%s*%%")
        or txt:match("[Pp]ressure%s*:%s*(%d+)%s*%%")
    )
end

local function relicHP(island)
    local exact = findVisiblePercent("relic health")
    if exact ~= nil then
        return exact
    end

    local txt = allTopHUDText()
    local n = tonumber(
        txt:match("[Rr]elic%s+[Hh]ealth%s*:%s*(%d+)%s*%%")
        or txt:match("[Rr]elic%s+[Hh][Pp]%s*:%s*(%d+)%s*%%")
    )

    if n ~= nil then
        return n
    end

    local r = relic(island)
    if not r then return nil end

    local hp = r:FindFirstChild("Health")
    local mx = r:FindFirstChild("MaxHealth")

    if hp and mx and mx.Value > 0 then
        return hp.Value/mx.Value*100
    end
end

local function rockActive(rock)
    for _,v in ipairs(rock:GetDescendants()) do
        if (v:IsA("Beam") or v:IsA("ParticleEmitter"))
        and v.Enabled then
            return true
        end
    end

    return false
end

local function activeRocks(island)
    local core = island and island:FindFirstChild("Core")
    local folder = core and core:FindFirstChild("VolcanoRocks")
    if not folder then return {} end

    local out = {}

    for _,rock in ipairs(folder:GetChildren()) do
        if rock:IsA("Model") and rockActive(rock) then
            local p = rock:FindFirstChild("volcanorock")
                or rock:FindFirstChildWhichIsA("BasePart",true)

            if p then
                out[#out+1] = {model=rock,part=p}
            end
        end
    end

    local rr = root()
    if rr then
        table.sort(out,function(a,b)
            return (a.part.Position-rr.Position).Magnitude
                < (b.part.Position-rr.Position).Magnitude
        end)
    end

    return out
end

local function teamPressureTarget(island,workerIndex)
    local rocks = activeRocks(island)

    if #rocks == 0 then
        return nil,0
    end

    -- Stable cross-client ordering by world position.
    table.sort(rocks,function(a,b)
        local ap,bp = a.part.Position,b.part.Position

        if math.abs(ap.X-bp.X) > .25 then
            return ap.X < bp.X
        end

        if math.abs(ap.Z-bp.Z) > .25 then
            return ap.Z < bp.Z
        end

        return ap.Y < bp.Y
    end)

    local idx = ((math.max(workerIndex,1)-1) % #rocks)+1
    return rocks[idx],#rocks
end

local SKILLS = {
    Enum.KeyCode.X,
    Enum.KeyCode.C,
    Enum.KeyCode.V,
    Enum.KeyCode.F,
}

local function pressureBurst(target,token)
    if not target or not target.model or not target.part then
        return false
    end

    local deadline = os.clock()+CONFIG.PRESSURE.BURST_SECONDS

    while current(token)
    and target.model.Parent
    and rockActive(target.model)
    and os.clock() < deadline do
        local p = target.part.Position
        local hover = CFrame.new(
            p+Vector3.new(0,CONFIG.PRESSURE.ROCK_HOVER_Y,0)
        )

        local rr = root()
        if not rr then return false end

        if (rr.Position-hover.Position).Magnitude > 14 then
            if not tweenTo(hover,CONFIG.PRESSURE_SPEED,token) then
                return false
            end
        end

        aimAt(p)

        for _,tip in ipairs({"Melee","Blox Fruit"}) do
            local tool = equipTooltip(tip)
            if tool then
                for _,key in ipairs(SKILLS) do
                    if not current(token)
                    or not target.model.Parent
                    or not rockActive(target.model) then
                        break
                    end

                    aimAt(p)
                    pressKey(key,CONFIG.PRESSURE.SKILL_HOLD)
                    task.wait(CONFIG.PRESSURE.SKILL_GAP)
                end
            end
        end
    end

    return not target.model.Parent or not rockActive(target.model)
end

local function enableLavaProtection(island)
    local core = island and island:FindFirstChild("Core")
    local lava = core and core:FindFirstChild("InteriorLava")
    if not lava then return end

    for _,v in ipairs(lava:GetDescendants()) do
        if v:IsA("BasePart") then
            pcall(function()
                v.CanTouch = false
                v.CanCollide = false
            end)
        end
    end
end

local golemPrepared = setmetatable({}, {__mode="k"})
local golemLastBring = setmetatable({}, {__mode="k"})
local clusterAnchorCF = nil
local clusterIslandRef = nil

local function boostSimulationRadiusOnce(golem)
    if not golem or golemPrepared[golem] then
        return
    end

    golemPrepared[golem] = true

    pcall(function()
        if setsimulationradius then
            setsimulationradius(1000,1000)
        end
    end)

    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(LP,"SimulationRadius",1000)
        end
    end)
end

local function prepareGolemOnce(golem)
    if not golem or not golem.Parent then return end

    boostSimulationRadiusOnce(golem)

    local gp = golem:FindFirstChild("HumanoidRootPart")
        or golem:FindFirstChild("Head")

    if gp then
        pcall(function()
            gp.Size = Vector3.new(
                CONFIG.GOLEM.BRING_HITBOX,
                CONFIG.GOLEM.BRING_HITBOX,
                CONFIG.GOLEM.BRING_HITBOX
            )
            gp.CanCollide = false
        end)
    end

    -- Heavy descendant pass only once per Golem.
    for _,bp in ipairs(golem:GetDescendants()) do
        if bp:IsA("BasePart") then
            pcall(function()
                bp.CanCollide = false
            end)
        end
    end
end

local function liveGolems()
    local enemies = workspace:FindFirstChild("Enemies")
    local out = {}

    if not enemies then
        return out
    end

    for _,m in ipairs(enemies:GetChildren()) do
        if m:IsA("Model") and m.Name == "Lava Golem" then
            local h = m:FindFirstChildOfClass("Humanoid")
            local gp = m:FindFirstChild("HumanoidRootPart")
                or m:FindFirstChild("Head")

            if h and h.Health > 0 and gp then
                out[#out+1] = m
            end
        end
    end

    return out
end

local function totalGolemHP(golems)
    local total = 0

    for _,g in ipairs(golems or {}) do
        local h = g:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then
            total += h.Health
        end
    end

    return total
end

local function resetClusterAnchorIfNeeded(island)
    if clusterIslandRef ~= island then
        clusterIslandRef = island
        clusterAnchorCF = nil
    end
end

local function computeClusterAnchor(island,golems)
    resetClusterAnchorIfNeeded(island)

    if clusterAnchorCF then
        return clusterAnchorCF
    end

    local r = relic(island)
    if not r then return nil end

    local ok,pivot = pcall(function()
        return r:GetPivot()
    end)

    if not ok or not pivot then
        return nil
    end

    local relicPos = pivot.Position

    -- Use the average spawn direction of all current Golems, so the cluster
    -- is pushed AWAY from Fossil instead of dragged across it.
    local sum = Vector3.zero
    local count = 0
    local avgY = relicPos.Y

    for _,g in ipairs(golems or {}) do
        local gp = g:FindFirstChild("HumanoidRootPart")
            or g:FindFirstChild("Head")

        if gp then
            sum += Vector3.new(
                gp.Position.X-relicPos.X,
                0,
                gp.Position.Z-relicPos.Z
            )
            avgY += gp.Position.Y
            count += 1
        end
    end

    local away = sum

    if away.Magnitude < 1 then
        local lv = pivot.LookVector
        away = Vector3.new(-lv.X,0,-lv.Z)
    end

    if away.Magnitude < 1 then
        away = Vector3.new(1,0,0)
    end

    if count > 0 then
        avgY = (avgY-relicPos.Y)/count
    else
        avgY = relicPos.Y
    end

    local targetPos =
        relicPos
        + away.Unit*CONFIG.GOLEM.BRING_DISTANCE_FROM_RELIC

    targetPos = Vector3.new(
        targetPos.X,
        avgY + CONFIG.GOLEM.BRING_HEIGHT_OFFSET,
        targetPos.Z
    )

    local face = Vector3.new(
        relicPos.X,
        targetPos.Y,
        relicPos.Z
    )

    clusterAnchorCF = CFrame.lookAt(targetPos,face)
    return clusterAnchorCF
end

local function clusterSlotCF(anchor,index,total)
    -- User asked to "túm lại 1 chỗ".
    -- Keep the cluster extremely tight, but give each model a tiny offset
    -- to reduce unstable model overlap.
    if not anchor then return nil end

    if total <= 1 then
        return anchor
    end

    local angle = ((index-1)/math.max(total,1))*math.pi*2
    local radius = CONFIG.GOLEM.CLUSTER_RADIUS

    local offset = Vector3.new(
        math.cos(angle)*radius,
        0,
        math.sin(angle)*radius
    )

    return CFrame.lookAt(
        anchor.Position+offset,
        anchor.Position+offset+anchor.LookVector
    )
end

local function bringAllGolemsToCluster(island,golems,force)
    local golemes = golems or liveGolems()
    if #golemes == 0 then
        return nil,0
    end

    local anchor = computeClusterAnchor(island,golemes)
    if not anchor then
        return nil,#golemes
    end

    local now = os.clock()

    for i,golem in ipairs(golemes) do
        local h = golem:FindFirstChildOfClass("Humanoid")
        local gp = golem:FindFirstChild("HumanoidRootPart")
            or golem:FindFirstChild("Head")

        if h and h.Health > 0 and gp then
            prepareGolemOnce(golem)

            local slot = clusterSlotCF(anchor,i,#golemes)
            local last = golemLastBring[golem] or 0
            local drift = (gp.Position-slot.Position).Magnitude

            if force or (
                now-last >= CONFIG.GOLEM.BRING_INTERVAL
                and drift >= CONFIG.GOLEM.REBRING_DRIFT
            ) then
                golemLastBring[golem] = now

                pcall(function()
                    golem:PivotTo(slot)

                    local newRoot =
                        golem:FindFirstChild("HumanoidRootPart")
                        or golem:FindFirstChild("Head")

                    if newRoot then
                        newRoot.AssemblyLinearVelocity = Vector3.zero
                        newRoot.AssemblyAngularVelocity = Vector3.zero
                    end
                end)
            end
        end
    end

    return anchor,#golemes
end

local function netHitGolemCluster(golems)
    local rr = root()

    if not rr then
        return false
    end

    local live = {}
    local primaryPart = nil

    for _,golem in ipairs(golems or {}) do
        local h = golem:FindFirstChildOfClass("Humanoid")
        local gp = golem:FindFirstChild("HumanoidRootPart")
            or golem:FindFirstChild("Head")

        if h and h.Health > 0 and gp
        and (rr.Position-gp.Position).Magnitude <= CONFIG.GOLEM.NET_DISTANCE then
            primaryPart = primaryPart or gp
            live[#live+1] = {golem,gp}
        end
    end

    if #live == 0 or not primaryPart then
        return false
    end

    if not RegisterAttack or not RegisterHit then
        local tool = equipTooltip("Melee")
        if tool then
            pcall(function() tool:Activate() end)
            return true
        end
        return false
    end

    local okA = pcall(function()
        RegisterAttack:FireServer(.05)
    end)

    local okH = pcall(function()
        -- One attack registration, all clustered Golems in one target list.
        RegisterHit:FireServer(primaryPart,live)
    end)

    return okA and okH
end

local function golemClusterBurst(island,token)
    local golemes = liveGolems()

    if #golemes == 0 then
        STATE.GolemCount = 0
        STATE.GolemHP = nil
        refreshUI()
        return true
    end

    local anchor = computeClusterAnchor(island,golemes)
    if not anchor then
        return false
    end

    -- Immediately pull ALL living Golems away from Fossil.
    bringAllGolemsToCluster(island,golemes,true)

    local rr = root()
    if not rr then
        return false
    end

    local playerTarget = CFrame.new(
        anchor.Position + Vector3.new(0,CONFIG.GOLEM.HOVER_Y,0)
    )

    if (rr.Position-playerTarget.Position).Magnitude
    > CONFIG.GOLEM.APPROACH_DISTANCE then
        local ok = tweenTo(
            playerTarget,
            165,
            token
        )

        if not ok then
            return false
        end
    end

    local deadline = os.clock()+CONFIG.GOLEM.BURST_SECONDS
    local lastTotalHP = totalGolemHP(golemes)
    local progressAt = os.clock()

    while current(token)
    and autoOn()
    and os.clock() < deadline do
        -- Re-scan every loop because another Golem can spawn during the event.
        golemes = liveGolems()

        if #golemes == 0 then
            STATE.GolemCount = 0
            STATE.GolemHP = nil
            refreshUI()
            return true
        end

        anchor = computeClusterAnchor(island,golemes) or anchor

        -- Keep every live Golem in the same cluster.
        bringAllGolemsToCluster(island,golemes,false)

        local totalHP = totalGolemHP(golemes)
        STATE.GolemCount = #golemes
        STATE.GolemHP = totalHP
        refreshUI()

        if totalHP < lastTotalHP then
            lastTotalHP = totalHP
            progressAt = os.clock()
        end

        local first = golemes[1]
        local firstPart = first and (
            first:FindFirstChild("HumanoidRootPart")
            or first:FindFirstChild("Head")
        )

        if firstPart then
            aimAt(firstPart.Position)
        end

        equipTooltip("Melee")
        netHitGolemCluster(golemes)

        -- Stall fallback: if aggregate HP is not changing, use one normal
        -- physical activation rather than flooding more remotes.
        if os.clock()-progressAt >= CONFIG.GOLEM.STALL_SECONDS then
            setStatus(
                "Golem cluster stalled -> physical Melee fallback | "
                ..#golemes.."x",
                "GOLEM RECOVERY"
            )

            local tool = equipTooltip("Melee")
            if tool then
                pcall(function() tool:Activate() end)
            end

            progressAt = os.clock()
            task.wait(.20)
        end

        task.wait(CONFIG.GOLEM.ATTACK_INTERVAL)
    end

    return #liveGolems() == 0
end

local function golemSupportBurst(island,token)
    local golemes = liveGolems()

    if #golemes == 0 then
        return true
    end

    local center = Vector3.zero
    local count = 0

    for _,g in ipairs(golemes) do
        local gp = g:FindFirstChild("HumanoidRootPart")
            or g:FindFirstChild("Head")

        if gp then
            center += gp.Position
            count += 1
        end
    end

    if count <= 0 then
        return false
    end

    center /= count

    local targetCF = CFrame.new(
        center + Vector3.new(0,CONFIG.GOLEM.HOVER_Y,0)
    )

    local rr = root()
    if not rr then return false end

    if (rr.Position-targetCF.Position).Magnitude
    > CONFIG.GOLEM.APPROACH_DISTANCE then
        local ok = tweenTo(targetCF,165,token)
        if not ok then
            return false
        end
    end

    local deadline = os.clock()+CONFIG.GOLEM.BURST_SECONDS

    while current(token)
    and autoOn()
    and eventActive()
    and os.clock() < deadline do
        golemes = liveGolems()

        if #golemes == 0 then
            return true
        end

        STATE.GolemCount = #golemes
        STATE.GolemHP = totalGolemHP(golemes)
        refreshUI()

        local first = golemes[1]
        local gp = first and (
            first:FindFirstChild("HumanoidRootPart")
            or first:FindFirstChild("Head")
        )

        if gp then
            aimAt(gp.Position)
        end

        equipTooltip("Melee")
        netHitGolemCluster(golemes)

        task.wait(CONFIG.GOLEM.ATTACK_INTERVAL)
    end

    return #liveGolems() == 0
end

local function startEvent(island,token)
    if eventActive() then
        return true
    end

    local r = relic(island)
    if not r then
        setStatus("PrehistoricRelic not found","START EVENT")
        return false
    end

    setStatus(
        "Fossil -> exact captured spot -> Virtual HOLD E 3s",
        "START EVENT"
    )

    local h = hum()

    if h and h.SeatPart then
        local unseatOk,unseatWhy =
            jumpOutOfSeat(token,"before exact Fossil spot")

        if not unseatOk then
            setStatus(
                "Could not JUMP out of seat: "..tostring(unseatWhy),
                "START EVENT"
            )
            return false
        end
    end

    local targetCF,pivot = capturedFossilTarget(island)

    if not targetCF then
        setStatus(
            "Could not resolve captured Fossil CFrame",
            "START EVENT"
        )
        return false
    end

    -- Safe tween to the EXACT relative standing pose that was manually captured.
    local moveOk,moveWhy =
        tweenTo(targetCF,CONFIG.FOSSIL.SAFE_SPEED,token)

    if not moveOk then
        setStatus(
            "Exact Fossil tween failed: "..tostring(moveWhy),
            "START EVENT"
        )
        return false
    end

    -- Settle at the precise captured pose without a long-distance teleport.
    -- This final assignment is only a tiny correction after the safe tween.
    local rr = root()
    if rr and (rr.Position-targetCF.Position).Magnitude <= 4 then
        pcall(function()
            rr.CFrame = targetCF
            rr.AssemblyLinearVelocity = Vector3.zero
            rr.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    task.wait(CONFIG.FOSSIL.SETTLE_TIME)

    if not autoOn() then
        return false
    end

    setStatus(
        "Exact Fossil position reached | Virtual HOLD E "..tostring(CONFIG.FOSSIL.HOLD_SECONDS).."s",
        "START EVENT"
    )

    -- One deliberate hold first. Do not spam E because E is also Observation.
    local held,holdWhy =
        holdFossilEVirtual(CONFIG.FOSSIL.HOLD_SECONDS,token)

    if not held then
        setStatus(
            "Fossil E hold failed: "..tostring(holdWhy),
            "START EVENT"
        )
        return false
    end

    local deadline = os.clock()+2.0

    repeat
        if eventActive() then
            setStatus("Fossil event started","VOLCANO")
            return true
        end
        task.wait(.08)
    until os.clock() >= deadline

    -- Safety: do NOT repeatedly press E when the interaction is unconfirmed,
    -- because E can toggle Observation/Instinct.
    setStatus(
        "Fossil E hold sent but event not confirmed -> AUTO PAUSED for inspection",
        "FOSSIL DEBUG"
    )

    STATE.AutoVolcano = false
    refreshUI()

    return false
end

local function runVolcano(island,token)
    enableLavaProtection(island)

    setStatus("Volcano HUD detected -> solo controller armed","VOLCANO")

    local hudGrace = os.clock()+2.0
    while current(token) and not eventActive() and os.clock() < hudGrace do
        task.wait(.05)
    end

    while current(token)
    and island.Parent
    and eventActive() do
        if not autoOn() then
            setStatus(
                "AUTO VOLCANO OFF - event control paused",
                "PAUSED"
            )

            if not waitAuto(token) then
                break
            end

            setStatus(
                "AUTO VOLCANO resumed inside event",
                "VOLCANO"
            )
        end
        STATE.Pressure = pressure()
        STATE.Relic = relicHP(island)

        local rocks = activeRocks(island)
        local rock = rocks[1]
        local golemes = liveGolems()

        STATE.GolemCount = #golemes
        STATE.GolemHP = #golemes > 0 and totalGolemHP(golemes) or nil
        refreshUI()

        -- V2.9 MULTI-GOLEM PRIORITY:
        -- Any number of live Lava Golems are gathered into ONE cluster far
        -- from Fossil, then hit together with one RegisterHit target list.
        if #golemes > 0 and CONFIG.GOLEM.PRIORITY_FIRST then
            local anchor = computeClusterAnchor(island,golemes)
            local relicModel = relic(island)
            local relicPivot

            if relicModel then
                pcall(function()
                    relicPivot = relicModel:GetPivot()
                end)
            end

            local awayDist = "?"
            if anchor and relicPivot then
                awayDist = tostring(math.floor(
                    (anchor.Position-relicPivot.Position).Magnitude
                ))
            end

            setStatus(
                "GOLEM CLUSTER FIRST | "..#golemes..
                "x | bring "..awayDist..
                " studs | total HP="..
                tostring(math.floor(STATE.GolemHP or 0)),
                "GOLEM"
            )

            golemClusterBurst(island,token)

        elseif rock then
            setStatus(
                "Fixing pressure | P="..tostring(STATE.Pressure or "?")..
                " | Rocks="..#rocks,
                "PRESSURE"
            )
            pressureBurst(rock,token)

        else
            setStatus(
                "Stable | P="..tostring(STATE.Pressure or "?")..
                " | Relic="..tostring(STATE.Relic or "?"),
                "VOLCANO"
            )
            task.wait(.08)
        end
    end

    STATE.Pressure = pressure()
    STATE.Relic = relicHP(island)
    STATE.GolemHP = nil
    STATE.GolemCount = 0
    clusterAnchorCF = nil
    clusterIslandRef = nil
    refreshUI()

    return true
end

local function runTeamVolcano(island,token)
    enableLavaProtection(island)

    STATE.Raid = "ACTIVE"
    setStatus(
        "TEAM RAID ACTIVE | "..ROLE,
        "TEAM VOLCANO"
    )

    while current(token)
    and island.Parent
    and eventActive() do
        if not autoOn() then
            STATE.Raid = "PAUSED"
            setStatus("AUTO TEAM OFF - raid control paused","PAUSED")

            if not waitAuto(token) then
                break
            end

            STATE.Raid = "ACTIVE"
        end

        STATE.Pressure = pressure()
        STATE.Relic = relicHP(island)

        local golemes = liveGolems()
        STATE.GolemCount = #golemes
        STATE.GolemHP = #golemes > 0 and totalGolemHP(golemes) or nil
        refreshUI()

        if TEAM_SLOT == 0 then
            -- MASTER controls the cluster so multiple clients do not fight over PivotTo.
            if #golemes > 0 then
                setStatus(
                    "MASTER GOLEM CTRL | "..#golemes..
                    "x | total HP "..math.floor(STATE.GolemHP or 0),
                    "GOLEM CTRL"
                )
                golemClusterBurst(island,token)
            else
                local rock,count = teamPressureTarget(island,1)

                if rock then
                    setStatus(
                        "MASTER assists pressure | "..count.." rocks",
                        "PRESSURE"
                    )
                    pressureBurst(rock,token)
                else
                    task.wait(.08)
                end
            end

        elseif TEAM_SLOT == 3 then
            -- Dedicated DPS account does NOT move Golems. MASTER owns bring.
            if #golemes > 0 then
                setStatus(
                    "GOLEM DPS | "..#golemes..
                    "x | total HP "..math.floor(STATE.GolemHP or 0),
                    "GOLEM DPS"
                )

                -- If MASTER died, temporarily take over cluster control.
                if masterAlive() then
                    golemSupportBurst(island,token)
                else
                    setStatus(
                        "MASTER down -> GOLEM DPS takes cluster control",
                        "GOLEM TAKEOVER"
                    )
                    golemClusterBurst(island,token)
                end
            else
                local rock,count =
                    teamPressureTarget(island,pressureWorkerIndex())

                if rock then
                    setStatus(
                        "No Golem -> DPS helps pressure | "..count.." rocks",
                        "PRESSURE SUPPORT"
                    )
                    pressureBurst(rock,token)
                else
                    task.wait(.08)
                end
            end

        else
            -- Pressure A/B/C stay on rocks even while Golems exist.
            -- This is the main advantage over solo.
            local worker = pressureWorkerIndex()
            local rock,count = teamPressureTarget(island,worker)

            if rock then
                setStatus(
                    ROLE.." | rock slot "..worker..
                    " | active "..count,
                    "PRESSURE TEAM"
                )
                pressureBurst(rock,token)

            elseif #golemes > 0 then
                -- No active rock: free account contributes DPS.
                setStatus(
                    ROLE.." | no rock -> Golem support",
                    "GOLEM SUPPORT"
                )
                golemSupportBurst(island,token)

            else
                setStatus(
                    ROLE.." | stable | P="..
                    tostring(STATE.Pressure or "?")..
                    " | Relic="..tostring(STATE.Relic or "?"),
                    "TEAM VOLCANO"
                )
                task.wait(.08)
            end
        end
    end

    STATE.Raid = "ENDED"
    STATE.Pressure = pressure()
    STATE.Relic = relicHP(island)
    STATE.GolemHP = nil
    STATE.GolemCount = 0
    refreshUI()

    return true
end

--==============================================================
-- REWARDS
--==============================================================

local function interactionPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart",true)
end

local function collectDragonEgg(island,token)
    STATE.Egg = "WAIT"
    refreshUI()

    local core = island and island:FindFirstChild("Core")
    if not core then return false end

    local folder = core:FindFirstChild("SpawnedDragonEggs")

    local waitUntilTime = os.clock()+CONFIG.EGG.WAIT_SECONDS

    while current(token) and os.clock() < waitUntilTime do
        folder = core:FindFirstChild("SpawnedDragonEggs")

        if folder and #folder:GetChildren() > 0 then
            break
        end

        task.wait(.10)
    end

    if not folder or #folder:GetChildren() == 0 then
        STATE.Egg = "NONE"
        refreshUI()
        setStatus("No Dragon Egg spawned","REWARD")
        return true
    end

    local rr = root()
    local eggs = {}

    for _,egg in ipairs(folder:GetChildren()) do
        local p = interactionPart(egg)
        if p then
            eggs[#eggs+1] = {obj=egg,part=p}
        end
    end

    if #eggs == 0 then
        STATE.Egg = "NONE"
        refreshUI()
        return true
    end

    table.sort(eggs,function(a,b)
        if not rr then return true end
        return (a.part.Position-rr.Position).Magnitude
            < (b.part.Position-rr.Position).Magnitude
    end)

    local egg = eggs[1].obj
    local p = eggs[1].part

    setStatus("Nearest Dragon Egg -> HOLD E","DRAGON EGG")
    STATE.Egg = "PICKING"
    refreshUI()

    tweenTo(
        p.CFrame*CFrame.new(0,2.5,-CONFIG.EGG.APPROACH_DISTANCE),
        CONFIG.PLAYER_SPEED,
        token
    )

    aimAt(p.Position)

    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt",true)
    local hold = CONFIG.EGG.HOLD_E

    if prompt then
        hold = math.max(
            hold,
            (tonumber(prompt.HoldDuration) or 0)+.12
        )
    end

    local picked = false

    for attempt=1,CONFIG.EGG.RETRIES do
        if not egg.Parent
        or not egg:IsDescendantOf(folder) then
            picked = true
            break
        end

        local ep = interactionPart(egg)
        if ep then
            if (root().Position-ep.Position).Magnitude > 7 then
                tweenTo(
                    ep.CFrame*CFrame.new(0,2.5,-CONFIG.EGG.APPROACH_DISTANCE),
                    CONFIG.PLAYER_SPEED,
                    token
                )
            end
            aimAt(ep.Position)
        end

        setStatus(
            "Dragon Egg HOLD E "..attempt.."/"..CONFIG.EGG.RETRIES,
            "DRAGON EGG"
        )

        holdE(hold)
        task.wait(CONFIG.EGG.RETRY_GAP)
    end

    if not egg.Parent or not egg:IsDescendantOf(folder) then
        picked = true
    end

    -- One fallback only, after physical Hold-E attempts.
    if not picked and Net then
        local re = Net:FindFirstChild("RE/CollectedDragonEgg")
        if re then
            pcall(function() re:FireServer() end)
            task.wait(.35)
            picked = not egg.Parent or not egg:IsDescendantOf(folder)
        end
    end

    STATE.Egg = picked and "PICKED" or "FAILED"
    refreshUI()

    setStatus(
        picked and "Dragon Egg picked" or "Dragon Egg pickup not confirmed",
        "DRAGON EGG"
    )

    return picked
end

local function interactCollectible(obj,token)
    local p = interactionPart(obj)
    if not p then return false end

    tweenTo(p.CFrame*CFrame.new(0,3,0),CONFIG.PLAYER_SPEED,token)

    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt",true)
    if prompt and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(.20)
        return true
    end

    local click = obj:FindFirstChildWhichIsA("ClickDetector",true)
    if click and fireclickdetector then
        pcall(function() fireclickdetector(click) end)
        task.wait(.20)
        return true
    end

    local touch = obj:FindFirstChildWhichIsA("TouchTransmitter",true)
    if touch and firetouchinterest and root() then
        local tp = touch.Parent
        if tp and tp:IsA("BasePart") then
            pcall(function()
                firetouchinterest(root(),tp,0)
                task.wait(.10)
                firetouchinterest(root(),tp,1)
            end)
            task.wait(.20)
            return true
        end
    end

    return false
end

local function collectBones(island,token)
    if not CONFIG.BONES.ENABLED then return true end

    setStatus("Quick Dinosaur Bones sweep","BONES")

    local deadline = os.clock()+CONFIG.BONES.SWEEP_SECONDS
    local tried = {}
    local quiet = os.clock()

    while current(token)
    and island.Parent
    and os.clock() < deadline do
        local found = false

        for _,v in ipairs(island:GetDescendants()) do
            if not tried[v]
            and normalize(v.Name):find("bone",1,true) then
                local hasInteract =
                    v:FindFirstChildWhichIsA("ProximityPrompt",true)
                    or v:FindFirstChildWhichIsA("ClickDetector",true)
                    or v:FindFirstChildWhichIsA("TouchTransmitter",true)

                if hasInteract then
                    tried[v] = true
                    found = true
                    quiet = os.clock()
                    interactCollectible(v,token)
                end
            end
        end

        if not found then
            if os.clock()-quiet > .55 then
                break
            end
            task.wait(.08)
        end
    end

    return true
end

local function slaveWaitForIsland(token)
    local lastPortalAttempt = 0

    while current(token) do
        if not waitAuto(token) then
            return nil,"STOPPED"
        end

        local island = prehistoricIsland()

        if island then
            local h = hum()

            if h and h.SeatPart then
                local ok,why =
                    jumpOutOfSeat(token,"team reached Prehistoric")

                if not ok then
                    return nil,"UNSEAT_FAIL:"..tostring(why)
                end
            end

            STATE.Boat = "ISLAND FOUND"
            refreshUI()
            return island,"ISLAND_FOUND"
        end

        if not alive() then
            if not waitForRespawnRecovery(token) then
                return nil,"RESPAWN_TIMEOUT"
            end
        end

        local boat = masterBoat()

        if not boatAlive(boat) then
            STATE.Boat = "WAIT MASTER BOAT"
            STATE.TeamBoarded = 0
            refreshUI()

            local rr = root()

            if rr
            and (rr.Position-CONFIG.BOAT_DEALER_CFRAME.Position).Magnitude > 3500
            and os.clock()-lastPortalAttempt > 12 then
                lastPortalAttempt = os.clock()

                setStatus(
                    "No MASTER boat -> portal route toward Tiki",
                    "TEAM RENDEZVOUS"
                )

                routeToTiki(token)
            else
                setStatus(
                    "Waiting MASTER Grand Brigade",
                    "TEAM RENDEZVOUS"
                )
            end

            task.wait(.5)
            continue
        end

        teamBoardedCount(boat)

        local h = hum()
        if not h or not h.SeatPart
        or not h.SeatPart:IsDescendantOf(boat) then
            local ok,why = boardPassenger(boat,token)

            if not ok then
                setStatus(
                    "Passenger board retry: "..tostring(why),
                    "BOARD TEAM BOAT"
                )
                task.wait(CONFIG.TEAM.PASSENGER_BOARD_RETRY)
                continue
            end
        end

        STATE.Boat = "PASSENGER / HUNTING"
        refreshUI()

        -- Stay seated. MASTER moves the boat.
        while current(token)
        and autoOn()
        and alive()
        and boatAlive(boat)
        and not prehistoricIsland()
        and not prehistoricMarker() do
            teamBoardedCount(boat)
            task.wait(.20)
        end
    end

    return nil,"STOPPED"
end

local function waitForMasterEvent(island,token)
    setStatus(
        "Island ready -> waiting MASTER to start Fossil",
        "WAIT RAID"
    )

    while current(token)
    and island
    and island.Parent do
        if eventActive() then
            STATE.Raid = "ACTIVE"
            refreshUI()
            return true
        end

        if not alive() then
            waitForRespawnRecovery(token)
        end

        task.wait(.10)
    end

    return false
end

--==============================================================
-- LOOP / RESET
--==============================================================

local function resetCharacter(token)
    setStatus("Reset -> respawn for next hunt","RESET")

    local h = hum()
    if h then
        pcall(function() h.Health = 0 end)
    end

    local deadline = os.clock()+15
    repeat
        task.wait(.20)
        if alive() then
            task.wait(1.2)
            return true
        end
    until os.clock() >= deadline or not current(token)

    return alive()
end

local function runMasterCycle(token)
    if not waitAuto(token) then
        return false
    end

    STATE.Cycle += 1
    STATE.Egg = "WAIT"
    STATE.HuntRetry = 0
    STATE.Raid = "OFF"
    refreshUI()

    if not ensureMarines() then
        setStatus("Could not confirm Marines team","TEAM")
        task.wait(2)
        return true
    end

    -- MASTER is the only client that touches Stash/Magnet.
    if STATE.MagnetNeedsRefresh then
        local magnetOk = ensureMagnetBaseline(
            STATE.MagnetChecked and "post-event" or "startup"
        )

        if not magnetOk then
            if STATE.Magnet ~= nil and STATE.Magnet <= 0 then
                STATE.Running = false
                refreshUI()
                return false
            end

            task.wait(3)
            return true
        end
    end

    local island,searchWhy = huntPrehistoricWithRecovery(token)

    if not island then
        if searchWhy == "STOPPED" then
            return false
        end

        setStatus(
            "MASTER hunt recovery: "..tostring(searchWhy),
            "RECOVERY"
        )
        task.wait(1)
        return true
    end

    setStatus("Prehistoric Island found","PREHISTORIC")

    if not alive() then
        waitForRespawnRecovery(token)
        return true
    end

    if not startEvent(island,token) then
        if not alive() then
            waitForRespawnRecovery(token)
            return true
        end

        setStatus(
            "MASTER could not confirm raid HUD",
            "START EVENT"
        )
        task.wait(1)
        return true
    end

    if eventActive() then
        runTeamVolcano(island,token)
    else
        setStatus(
            "Fossil interaction sent but raid HUD never appeared",
            "START EVENT"
        )
        return true
    end

    if not alive() then
        waitForRespawnRecovery(token)
        return true
    end

    setStatus("TEAM event ended -> rewards","REWARD")
    collectDragonEgg(island,token)
    collectBones(island,token)

    STATE.CompletedEvents += 1

    if CONFIG.MAGNET_CHECK.RECHECK_AFTER_EVENT then
        STATE.MagnetNeedsRefresh = true
    end

    if not CONFIG.LOOP_AFTER_EVENT then
        STATE.Running = false
        setStatus("MASTER cycle complete","DONE")
        return false
    end

    resetCharacter(token)
    task.wait(2.0)

    return true
end

local function runSlaveCycle(token)
    if not waitAuto(token) then
        return false
    end

    STATE.Cycle += 1
    STATE.Egg = "WAIT"
    STATE.Raid = "OFF"
    STATE.Magnet = nil
    refreshUI()

    if not ensureMarines() then
        setStatus("Could not confirm Marines team","TEAM")
        task.wait(2)
        return true
    end

    local island,why = slaveWaitForIsland(token)

    if not island then
        if why == "STOPPED" then
            return false
        end

        setStatus(
            "Slave rendezvous retry: "..tostring(why),
            "RECOVERY"
        )
        task.wait(1)
        return true
    end

    if not waitForMasterEvent(island,token) then
        task.wait(.5)
        return true
    end

    if eventActive() then
        runTeamVolcano(island,token)
    end

    if not alive() then
        waitForRespawnRecovery(token)
        return true
    end

    setStatus("TEAM event ended -> personal rewards","REWARD")
    collectDragonEgg(island,token)
    collectBones(island,token)

    STATE.CompletedEvents += 1

    if not CONFIG.LOOP_AFTER_EVENT then
        STATE.Running = false
        setStatus("Slave cycle complete","DONE")
        return false
    end

    resetCharacter(token)
    task.wait(2.0)

    return true
end

local function runCycle(token)
    if isMaster() then
        return runMasterCycle(token)
    end

    return runSlaveCycle(token)
end

task.spawn(function()
    if type(setfpscap) == "function" then
        pcall(function() setfpscap(30) end)
    end

    task.wait(.5)

    while current(STATE.Token) do
        if not STATE.AutoVolcano then
            setStatus(
                "AUTO TEAM OFF - waiting",
                "PAUSED"
            )
            waitAuto(STATE.Token)
        end

        local keepGoing = runCycle(STATE.Token)

        if not keepGoing then
            break
        end

        task.wait(.5)
    end
end)
