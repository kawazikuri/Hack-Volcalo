--[[
    PREHISTORIC TEAM V1
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
local CommF = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")

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
        ForestPirate = CFrame.new(-11975.78515625, 331.7734069824219, -10620.0302734375),
    },

    TREES = {
        CFrame.new(5254.79297,1004.09454,469.443573),
        CFrame.new(5187.3042,1004.08722,281.555573),
        CFrame.new(5323.68555,1004.099,316.628693),
        CFrame.new(5424.94434,1004.09265,145.194458),
        CFrame.new(5671.45557,1211.30786,844.747864),
    },
}
