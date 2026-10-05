--[[
    PREHISTORIC TEAM V1.3 (DELTA COMPAT)
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
BOOT_LABEL.Text = "PREHISTORIC V1.3\nLoading automation..."
BOOT_LABEL.ZIndex = 999999

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if not remotes then
    BOOT_LABEL.Text = "PREHISTORIC V1.3 ERROR\nReplicatedStorage.Remotes not found"
    return
end

local CommF = remotes:WaitForChild("CommF_", 20)
if not CommF then
    BOOT_LABEL.Text = "PREHISTORIC V1.3 ERROR\nCommF_ not found"
    return
end

BOOT_LABEL.Text = "PREHISTORIC V1.3\nLoaded core, building UI..."

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
