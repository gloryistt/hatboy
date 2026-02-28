--------------------------------------------------
-- LUMIWARE V4 — Automation Update
-- Battle Detection + Auto-Move/Run/Walk
-- FORMAT: EVT(arg1="BattleEvent", arg2=sessionID,
--   arg3=subCmd, arg4=JSON commandTable)
--------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local PLAYER_NAME = player.Name

--------------------------------------------------
-- LOGGING
--------------------------------------------------
local VERBOSE_MODE = false

local function log(category, ...)
    print("[LumiWare][" .. category .. "]", ...)
end

local function logDebug(...)
    if VERBOSE_MODE then log("DEBUG", ...) end
end

log("INFO", "Initializing LumiWare v4 for:", PLAYER_NAME)

--------------------------------------------------
-- RARE LOOMIANS
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Protogon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Cynamoth", "Avitross", "Snocub", "Eaglit",
    "Vambat", "Weevolt", "Nevermare",
    "Akhalos", "Odasho", "Cosmiore", "Armenti"
}
local customRares = {}

-- LAYER 1: Name-based rare modifier detection
-- Catches: "Gleam Dripple", "Gamma Grubby", "SA Dripple", etc.
local RARE_MODIFIERS = {
    "gleam", "gleaming", "gamma", "corrupt", "corrupted",
    "alpha", "twilat", "iridescent", "metallic", "rainbow",
    "sa ", "pn ", "hw ", "ny ",           -- event prefixes
    "secret", "shiny", "radiant",
}

local function isRareModifier(name)
    if type(name) ~= "string" then return false end
    local l = string.lower(name)
    for _, mod in ipairs(RARE_MODIFIERS) do
        if string.find(l, mod) then return true end
    end
    return false
end

-- LAYER 2: Deep scan ANY table/string for gleam/gamma/corrupt keywords
-- This catches model tables like {disc="gleamdisc", ...} or {variant="gamma"}
local RARE_KEYWORDS_DEEP = {
    "gleam", "gamma", "corrupt", "alpha", "twilat",
    "iridescent", "metallic", "rainbow", "shiny", "radiant", "secret",
}

local function deepScanForRare(value, depth)
    if depth > 5 then return false end
    depth = depth or 0

    if type(value) == "string" then
        local l = string.lower(value)
        for _, kw in ipairs(RARE_KEYWORDS_DEEP) do
            if string.find(l, kw) then
                log("RARE", "Deep scan HIT: keyword=" .. kw .. " in string=" .. string.sub(value, 1, 60))
                return true
            end
        end
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            -- Check key names for variant/gleam/type properties
            if type(k) == "string" then
                local kl = string.lower(k)
                if kl == "variant" or kl == "gleam" or kl == "gamma" or kl == "corrupt"
                    or kl == "issecret" or kl == "isgleam" or kl == "isgamma" then
                    -- If the key is a flag and the value is truthy
                    if v == true or v == 1 or (type(v) == "string" and v ~= "" and v ~= "false" and v ~= "0") then
                        log("RARE", "Deep scan HIT: key=" .. k .. " val=" .. tostring(v))
                        return true
                    end
                end
            end
            -- Recurse into all values
            if deepScanForRare(v, depth + 1) then return true end
        end
    end
    return false
end

-- LAYER 3: Scan a full command entry for any rare indicators
-- Checks name, info string, AND all table args (model, disc, icon)
local function scanEntryForRare(entry)
    if type(entry) ~= "table" then return false end
    for i = 1, #entry do
        local v = entry[i]
        if type(v) == "string" then
            if isRareModifier(v) then return true end
        elseif type(v) == "table" then
            if deepScanForRare(v, 0) then return true end
        end
    end
    return false
end

local function isRareLoomian(name)
    local l = string.lower(name)
    for _, r in ipairs(RARE_LOOMIANS) do
        if string.find(l, string.lower(r)) then return true end
    end
    for _, r in ipairs(customRares) do
        if string.find(l, string.lower(r)) then return true end
    end
    return false
end

local function sendNotification(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = duration or 5 })
    end)
end

local function playRareSound()
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://6518811702"
        s.Volume = 1
        s.Parent = SoundService
        s:Play()
        task.delay(3, function() s:Destroy() end)
    end)
end

--------------------------------------------------
-- WEBHOOK
--------------------------------------------------
local webhookUrl = ""

local function sendWebhook(embedData)
    if webhookUrl == "" then return end
    pcall(function()
        local payload = HttpService:JSONEncode({ username = "LumiWare", embeds = { embedData } })
        local httpFunc = (syn and syn.request) or (http and http.request) or request or http_request
        if httpFunc then
            httpFunc({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        end
    end)
end

local function sendRareWebhook(name, level, gender, enc, huntTime)
    sendWebhook({
        title = "⭐ RARE LOOMIAN FOUND!", description = "**" .. name .. "** detected!",
        color = 16766720,
        fields = {
            { name = "Loomian", value = name, inline = true },
            { name = "Level", value = tostring(level or "?"), inline = true },
            { name = "Gender", value = gender or "?", inline = true },
            { name = "Encounters", value = tostring(enc), inline = true },
            { name = "Hunt Time", value = huntTime or "?", inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare v3.1 • " .. os.date("%X") },
    })
end

local function sendSessionWebhook(enc, huntTime, rares)
    sendWebhook({
        title = "📊 Session Summary", description = "LumiWare session update",
        color = 7930367,
        fields = {
            { name = "Encounters", value = tostring(enc), inline = true },
            { name = "Hunt Time", value = huntTime, inline = true },
            { name = "Rares", value = tostring(rares), inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare v3.1 • " .. os.date("%X") },
    })
end

--------------------------------------------------
-- STATE
--------------------------------------------------
local encounterCount = 0
local huntStartTime = tick()
local currentEnemy = nil
local isMinimized = false
local battleState = "idle"
local lastBattleTick = 0
local raresFoundCount = 0
local encounterHistory = {}
local discoveryMode = false

-- Automation state
local autoMode = "off"      -- "off", "move", "run"
local autoMoveSlot = 1       -- 1-4 move slot
local autoWalkEnabled = false
local autoWalkThread = nil
local rareFoundPause = false -- pause automation on rare
local pendingAutoAction = false -- avoid double-firing

local currentBattle = {
    active = false,
    enemy = nil,
    player = nil,
    enemyStats = nil,
    playerStats = nil,
    battleType = "N/A",
    enemyProcessed = false,
}

local function resetBattle()
    currentBattle = {
        active = false, enemy = nil, player = nil,
        enemyStats = nil, playerStats = nil,
        battleType = "N/A", enemyProcessed = false,
    }
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function extractLoomianName(str)
    if not str then return "Unknown" end
    local formatted = str:gsub("-", " ")
    formatted = formatted:gsub("(%a)([%w_]*)", function(a, b) return string.upper(a) .. b end)
    return formatted
end

local function parseLoomianStats(infoStr)
    if type(infoStr) ~= "string" then return nil end
    local name, level, rest = infoStr:match("^(.+), L(%d+), (.+)$")
    if not level then return nil end
    local gender = rest and rest:match("^(%a)") or "?"
    local hp, maxHP = rest and rest:match("(%d+)/(%d+)") or nil, nil
    return { name = name, level = tonumber(level), gender = gender, hp = tonumber(hp), maxHP = tonumber(maxHP) }
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s)
    else return string.format("%dm %02ds", m, s) end
end

local function tablePreview(tbl, depth)
    depth = depth or 0
    if depth > 2 then return "{...}" end
    local parts, count = {}, 0
    for k, v in pairs(tbl) do
        count = count + 1
        if count > 6 then table.insert(parts, "...") break end
        if type(v) == "table" then table.insert(parts, tostring(k) .. "=" .. tablePreview(v, depth + 1))
        else table.insert(parts, tostring(k) .. "=" .. tostring(v)) end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--------------------------------------------------
-- GUI CLEANUP
--------------------------------------------------
local guiName = "LumiWare_Hub_" .. tostring(math.random(1000, 9999))
for _, v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
    if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
end
pcall(function()
    for _, v in pairs(CoreGui:GetChildren()) do
        if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then v:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok then gui.Parent = player:WaitForChild("PlayerGui") end

--------------------------------------------------
-- THEME
--------------------------------------------------
local C = {
    BG = Color3.fromRGB(16, 16, 22), TopBar = Color3.fromRGB(24, 24, 34),
    Accent = Color3.fromRGB(120, 80, 255), AccentDim = Color3.fromRGB(80, 50, 180),
    Text = Color3.fromRGB(240, 240, 245), TextDim = Color3.fromRGB(160, 160, 175),
    Panel = Color3.fromRGB(22, 22, 30), PanelAlt = Color3.fromRGB(28, 28, 38),
    Gold = Color3.fromRGB(255, 215, 0), Green = Color3.fromRGB(80, 220, 120),
    Red = Color3.fromRGB(255, 80, 80), Wild = Color3.fromRGB(80, 200, 255),
    Trainer = Color3.fromRGB(255, 160, 60), Orange = Color3.fromRGB(255, 160, 60),
    Cyan = Color3.fromRGB(80, 200, 255),
}

--------------------------------------------------
-- MAIN FRAME
--------------------------------------------------
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(460, 720)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = C.BG
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = C.Accent
stroke.Thickness = 1.5
stroke.Transparency = 0.4

-- TOPBAR
local topbar = Instance.new("Frame", mainFrame)
topbar.Size = UDim2.new(1, 0, 0, 36)
topbar.BackgroundColor3 = C.TopBar
topbar.BorderSizePixel = 0
Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, 10)
local topFill = Instance.new("Frame", topbar)
topFill.Size = UDim2.new(1, 0, 0, 10)
topFill.Position = UDim2.new(0, 0, 1, -10)
topFill.BackgroundColor3 = C.TopBar
topFill.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", topbar)
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "⚡ LumiWare v4"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextColor3 = C.Accent
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", topbar)
minBtn.Size = UDim2.fromOffset(28, 28)
minBtn.Position = UDim2.new(1, -66, 0, 4)
minBtn.BackgroundColor3 = C.AccentDim
minBtn.Text = "–"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.TextColor3 = C.Text
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton", topbar)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = C.Red
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = C.Text
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

closeBtn.MouseButton1Click:Connect(function()
    local elapsed = tick() - huntStartTime
    sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag
local dragging, dragInput, dragStart, startPos
topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = mainFrame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
topbar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local d = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- CONTENT
local contentFrame = Instance.new("Frame", mainFrame)
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, -16, 1, -44)
contentFrame.Position = UDim2.new(0, 8, 0, 40)
contentFrame.BackgroundTransparency = 1

-- STATS BAR
local statsBar = Instance.new("Frame", contentFrame)
statsBar.Size = UDim2.new(1, 0, 0, 50)
statsBar.BackgroundColor3 = C.Panel
statsBar.BorderSizePixel = 0
Instance.new("UICorner", statsBar).CornerRadius = UDim.new(0, 8)
local statsLayout = Instance.new("UIListLayout", statsBar)
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
statsLayout.Padding = UDim.new(0, 4)

local function makeStatCell(parent, label, value, color)
    local cell = Instance.new("Frame", parent)
    cell.Size = UDim2.new(0.2, -4, 1, -8)
    cell.BackgroundColor3 = C.PanelAlt
    cell.BorderSizePixel = 0
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel", cell)
    lbl.Size = UDim2.new(1, 0, 0.45, 0)
    lbl.Position = UDim2.new(0, 0, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 9
    lbl.TextColor3 = C.TextDim
    local val = Instance.new("TextLabel", cell)
    val.Name = "Value"
    val.Size = UDim2.new(1, 0, 0.55, 0)
    val.Position = UDim2.new(0, 0, 0.4, 0)
    val.BackgroundTransparency = 1
    val.Text = value
    val.Font = Enum.Font.GothamBold
    val.TextSize = 13
    val.TextColor3 = color or C.Text
    return val
end

local encounterVal = makeStatCell(statsBar, "ENCOUNTERS", "0", C.Green)
local epmVal = makeStatCell(statsBar, "ENC/MIN", "0.0", C.Text)
local timerVal = makeStatCell(statsBar, "HUNT TIME", "0m 00s", C.Text)
local typeVal = makeStatCell(statsBar, "BATTLE", "N/A", C.TextDim)
local stateVal = makeStatCell(statsBar, "STATUS", "Idle", C.TextDim)

-- ENCOUNTER PANEL
local encounterPanel = Instance.new("Frame", contentFrame)
encounterPanel.Size = UDim2.new(1, 0, 0, 90)
encounterPanel.Position = UDim2.new(0, 0, 0, 56)
encounterPanel.BackgroundColor3 = C.Panel
encounterPanel.BorderSizePixel = 0
Instance.new("UICorner", encounterPanel).CornerRadius = UDim.new(0, 8)

Instance.new("TextLabel", encounterPanel).Size = UDim2.new(1, -16, 0, 24)
local encTitle = encounterPanel:FindFirstChildOfClass("TextLabel")
encTitle.Position = UDim2.new(0, 8, 0, 4)
encTitle.BackgroundTransparency = 1
encTitle.Text = "CURRENT ENCOUNTER"
encTitle.Font = Enum.Font.GothamBold
encTitle.TextSize = 11
encTitle.TextColor3 = C.Accent
encTitle.TextXAlignment = Enum.TextXAlignment.Left

local enemyLbl = Instance.new("TextLabel", encounterPanel)
enemyLbl.Size = UDim2.new(1, -16, 0, 22)
enemyLbl.Position = UDim2.new(0, 8, 0, 28)
enemyLbl.BackgroundTransparency = 1
enemyLbl.Text = "Enemy: Waiting for battle..."
enemyLbl.Font = Enum.Font.GothamMedium
enemyLbl.TextSize = 15
enemyLbl.TextColor3 = C.Text
enemyLbl.TextXAlignment = Enum.TextXAlignment.Left
enemyLbl.RichText = true

local enemyStatsLbl = Instance.new("TextLabel", encounterPanel)
enemyStatsLbl.Size = UDim2.new(1, -16, 0, 18)
enemyStatsLbl.Position = UDim2.new(0, 8, 0, 48)
enemyStatsLbl.BackgroundTransparency = 1
enemyStatsLbl.Text = ""
enemyStatsLbl.Font = Enum.Font.Gotham
enemyStatsLbl.TextSize = 12
enemyStatsLbl.TextColor3 = C.TextDim
enemyStatsLbl.TextXAlignment = Enum.TextXAlignment.Left

local playerLbl = Instance.new("TextLabel", encounterPanel)
playerLbl.Size = UDim2.new(1, -16, 0, 18)
playerLbl.Position = UDim2.new(0, 8, 0, 68)
playerLbl.BackgroundTransparency = 1
playerLbl.Text = "Your Loomian: —"
playerLbl.Font = Enum.Font.Gotham
playerLbl.TextSize = 12
playerLbl.TextColor3 = C.TextDim
playerLbl.TextXAlignment = Enum.TextXAlignment.Left

-- RARE LOG
local logPanel = Instance.new("Frame", contentFrame)
logPanel.Size = UDim2.new(1, 0, 0, 80)
logPanel.Position = UDim2.new(0, 0, 0, 152)
logPanel.BackgroundColor3 = C.Panel
logPanel.BorderSizePixel = 0
Instance.new("UICorner", logPanel).CornerRadius = UDim.new(0, 8)
local logTitle = Instance.new("TextLabel", logPanel)
logTitle.Size = UDim2.new(1, -16, 0, 24)
logTitle.Position = UDim2.new(0, 8, 0, 4)
logTitle.BackgroundTransparency = 1
logTitle.Text = "⭐ RARE FINDER LOG"
logTitle.Font = Enum.Font.GothamBold
logTitle.TextSize = 11
logTitle.TextColor3 = C.Gold
logTitle.TextXAlignment = Enum.TextXAlignment.Left

local rareScroll = Instance.new("ScrollingFrame", logPanel)
rareScroll.Size = UDim2.new(1, -16, 1, -32)
rareScroll.Position = UDim2.new(0, 8, 0, 28)
rareScroll.BackgroundTransparency = 1
rareScroll.ScrollBarThickness = 3
rareScroll.ScrollBarImageColor3 = C.Accent
rareScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rareScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
local logLayout = Instance.new("UIListLayout", rareScroll)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 3)

local logOrder = 0
local function addRareLog(name, extraInfo)
    logOrder = logOrder + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 20)
    item.BackgroundTransparency = 1
    item.Text = "⭐ [" .. os.date("%X") .. "] " .. name .. (extraInfo and (" — " .. extraInfo) or "")
    item.Font = Enum.Font.GothamMedium
    item.TextSize = 12
    item.TextColor3 = C.Gold
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.LayoutOrder = logOrder
    item.Parent = rareScroll
end

-- CUSTOM RARE
local customPanel = Instance.new("Frame", contentFrame)
customPanel.Size = UDim2.new(1, 0, 0, 56)
customPanel.Position = UDim2.new(0, 0, 0, 238)
customPanel.BackgroundColor3 = C.Panel
customPanel.BorderSizePixel = 0
Instance.new("UICorner", customPanel).CornerRadius = UDim.new(0, 8)
local ct = Instance.new("TextLabel", customPanel)
ct.Size = UDim2.new(1, -16, 0, 20)
ct.Position = UDim2.new(0, 8, 0, 4)
ct.BackgroundTransparency = 1
ct.Text = "CUSTOM RARE LIST"
ct.Font = Enum.Font.GothamBold
ct.TextSize = 11
ct.TextColor3 = C.Accent
ct.TextXAlignment = Enum.TextXAlignment.Left

local customInput = Instance.new("TextBox", customPanel)
customInput.Size = UDim2.new(1, -90, 0, 26)
customInput.Position = UDim2.new(0, 8, 0, 26)
customInput.BackgroundColor3 = C.PanelAlt
customInput.BorderSizePixel = 0
customInput.PlaceholderText = "e.g. Twilat, Cathorn..."
customInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
customInput.Text = ""
customInput.Font = Enum.Font.Gotham
customInput.TextSize = 12
customInput.TextColor3 = C.Text
customInput.ClearTextOnFocus = false
customInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", customInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", customInput).PaddingLeft = UDim.new(0, 6)

local addBtn = Instance.new("TextButton", customPanel)
addBtn.Size = UDim2.fromOffset(36, 26)
addBtn.Position = UDim2.new(1, -82, 0, 26)
addBtn.BackgroundColor3 = C.Green
addBtn.Text = "+"
addBtn.Font = Enum.Font.GothamBold
addBtn.TextSize = 16
addBtn.TextColor3 = C.BG
addBtn.BorderSizePixel = 0
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 5)

local clearBtn = Instance.new("TextButton", customPanel)
clearBtn.Size = UDim2.fromOffset(36, 26)
clearBtn.Position = UDim2.new(1, -42, 0, 26)
clearBtn.BackgroundColor3 = C.Red
clearBtn.Text = "C"
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 14
clearBtn.TextColor3 = C.Text
clearBtn.BorderSizePixel = 0
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 5)

addBtn.MouseButton1Click:Connect(function()
    local input = customInput.Text
    if input == "" then return end
    for word in input:gmatch("[^,]+") do
        local trimmed = word:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then table.insert(customRares, trimmed) end
    end
    customInput.Text = ""
    sendNotification("LumiWare", "Added to custom rare list!", 3)
end)
clearBtn.MouseButton1Click:Connect(function()
    customRares = {}
    sendNotification("LumiWare", "Custom rare list cleared.", 3)
end)

-- WEBHOOK CONFIG
local whPanel = Instance.new("Frame", contentFrame)
whPanel.Size = UDim2.new(1, 0, 0, 56)
whPanel.Position = UDim2.new(0, 0, 0, 300)
whPanel.BackgroundColor3 = C.Panel
whPanel.BorderSizePixel = 0
Instance.new("UICorner", whPanel).CornerRadius = UDim.new(0, 8)
local wt = Instance.new("TextLabel", whPanel)
wt.Size = UDim2.new(1, -16, 0, 20)
wt.Position = UDim2.new(0, 8, 0, 4)
wt.BackgroundTransparency = 1
wt.Text = "📡 DISCORD WEBHOOK"
wt.Font = Enum.Font.GothamBold
wt.TextSize = 11
wt.TextColor3 = C.Cyan
wt.TextXAlignment = Enum.TextXAlignment.Left

local whInput = Instance.new("TextBox", whPanel)
whInput.Size = UDim2.new(1, -60, 0, 26)
whInput.Position = UDim2.new(0, 8, 0, 26)
whInput.BackgroundColor3 = C.PanelAlt
whInput.BorderSizePixel = 0
whInput.PlaceholderText = "Paste webhook URL..."
whInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
whInput.Text = ""
whInput.Font = Enum.Font.Gotham
whInput.TextSize = 11
whInput.TextColor3 = C.Text
whInput.ClearTextOnFocus = false
whInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", whInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", whInput).PaddingLeft = UDim.new(0, 6)

local whSave = Instance.new("TextButton", whPanel)
whSave.Size = UDim2.fromOffset(42, 26)
whSave.Position = UDim2.new(1, -50, 0, 26)
whSave.BackgroundColor3 = C.Cyan
whSave.Text = "SET"
whSave.Font = Enum.Font.GothamBold
whSave.TextSize = 11
whSave.TextColor3 = C.BG
whSave.BorderSizePixel = 0
Instance.new("UICorner", whSave).CornerRadius = UDim.new(0, 5)

whSave.MouseButton1Click:Connect(function()
    webhookUrl = whInput.Text
    if webhookUrl ~= "" then
        sendNotification("LumiWare", "Webhook saved!", 3)
        sendWebhook({
            title = "✅ Webhook Connected!", color = 5763719,
            fields = { { name = "Player", value = PLAYER_NAME, inline = true } },
            footer = { text = "LumiWare v3.1" },
        })
    else
        sendNotification("LumiWare", "Webhook cleared.", 3)
    end
end)

-- Forward declarations (needed by automation panel handlers)
local addBattleLog

-- ============================================
-- AUTOMATION PANEL
-- ============================================
local autoPanel = Instance.new("Frame", contentFrame)
autoPanel.Size = UDim2.new(1, 0, 0, 130)
autoPanel.Position = UDim2.new(0, 0, 0, 362)
autoPanel.BackgroundColor3 = C.Panel
autoPanel.BorderSizePixel = 0
Instance.new("UICorner", autoPanel).CornerRadius = UDim.new(0, 8)

local autoTitle = Instance.new("TextLabel", autoPanel)
autoTitle.Size = UDim2.new(1, -16, 0, 20)
autoTitle.Position = UDim2.new(0, 8, 0, 4)
autoTitle.BackgroundTransparency = 1
autoTitle.Text = "🤖 AUTOMATION"
autoTitle.Font = Enum.Font.GothamBold
autoTitle.TextSize = 11
autoTitle.TextColor3 = Color3.fromRGB(255, 120, 255)
autoTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Mode label
local modeLabel = Instance.new("TextLabel", autoPanel)
modeLabel.Size = UDim2.new(0, 46, 0, 22)
modeLabel.Position = UDim2.new(0, 8, 0, 26)
modeLabel.BackgroundTransparency = 1
modeLabel.Text = "Mode:"
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 11
modeLabel.TextColor3 = C.TextDim
modeLabel.TextXAlignment = Enum.TextXAlignment.Left

local function mkAutoBtn(parent, text, xOff, yOff, width)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.fromOffset(width or 60, 22)
    b.Position = UDim2.new(0, xOff, 0, yOff)
    b.BackgroundColor3 = C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local offBtn = mkAutoBtn(autoPanel, "OFF", 56, 26, 50)
local moveBtn = mkAutoBtn(autoPanel, "MOVE", 112, 26, 60)
local runBtn = mkAutoBtn(autoPanel, "RUN", 178, 26, 50)

-- Move slot label + buttons
local slotLabel = Instance.new("TextLabel", autoPanel)
slotLabel.Size = UDim2.new(0, 70, 0, 22)
slotLabel.Position = UDim2.new(0, 8, 0, 52)
slotLabel.BackgroundTransparency = 1
slotLabel.Text = "Move Slot:"
slotLabel.Font = Enum.Font.GothamBold
slotLabel.TextSize = 11
slotLabel.TextColor3 = C.TextDim
slotLabel.TextXAlignment = Enum.TextXAlignment.Left

local slotBtns = {}
for s = 1, 4 do
    local sb = mkAutoBtn(autoPanel, tostring(s), 78 + (s - 1) * 36, 52, 30)
    slotBtns[s] = sb
end

-- Auto-walk toggle
local walkBtn = mkAutoBtn(autoPanel, "🚶 AUTO-WALK: OFF", 8, 78, 140)
local scanBtn = mkAutoBtn(autoPanel, "🔍 SCAN UI", 155, 78, 80)
scanBtn.BackgroundColor3 = C.Orange

-- Status label
local autoStatusLbl = Instance.new("TextLabel", autoPanel)
autoStatusLbl.Size = UDim2.new(1, -16, 0, 22)
autoStatusLbl.Position = UDim2.new(0, 8, 0, 104)
autoStatusLbl.BackgroundTransparency = 1
autoStatusLbl.Text = ""
autoStatusLbl.Font = Enum.Font.Gotham
autoStatusLbl.TextSize = 10
autoStatusLbl.TextColor3 = C.TextDim
autoStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function updateAutoUI()
    offBtn.BackgroundColor3 = autoMode == "off" and C.Red or C.AccentDim
    moveBtn.BackgroundColor3 = autoMode == "move" and C.Green or C.AccentDim
    runBtn.BackgroundColor3 = autoMode == "run" and C.Cyan or C.AccentDim
    for s = 1, 4 do
        slotBtns[s].BackgroundColor3 = (autoMoveSlot == s and autoMode == "move") and C.Accent or C.AccentDim
    end
    slotLabel.TextColor3 = autoMode == "move" and C.Text or C.TextDim
    walkBtn.BackgroundColor3 = autoWalkEnabled and C.Green or C.AccentDim
    walkBtn.Text = autoWalkEnabled and "🚶 WALKING" or "🚶 AUTO-WALK"
    -- Status text
    if autoMode == "off" then
        autoStatusLbl.Text = "Automation disabled"
    elseif autoMode == "move" then
        autoStatusLbl.Text = "Auto-move slot " .. autoMoveSlot .. (rareFoundPause and " [PAUSED: RARE]" or "")
    elseif autoMode == "run" then
        autoStatusLbl.Text = "Auto-run" .. (rareFoundPause and " [PAUSED: RARE]" or "")
    end
end

offBtn.MouseButton1Click:Connect(function()
    autoMode = "off"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Automation OFF", 3)
end)
moveBtn.MouseButton1Click:Connect(function()
    autoMode = "move"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Auto-MOVE slot " .. autoMoveSlot, 3)
end)
runBtn.MouseButton1Click:Connect(function()
    autoMode = "run"
    rareFoundPause = false
    updateAutoUI()
    sendNotification("LumiWare", "Auto-RUN enabled", 3)
end)
for s = 1, 4 do
    slotBtns[s].MouseButton1Click:Connect(function()
        autoMoveSlot = s
        updateAutoUI()
    end)
end

updateAutoUI()

-- SCAN UI: dump all buttons in PlayerGui
scanBtn.MouseButton1Click:Connect(function()
    log("SCAN", "========== SCANNING PlayerGui ==========")
    addBattleLog("🔍 Scanning PlayerGui for buttons...", C.Orange)
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then
        addBattleLog("⚠ PlayerGui not found", C.Red)
        return
    end

    local btnCount = 0
    local function scanNode(inst, path, depth)
        if depth > 15 then return end
        for _, child in ipairs(inst:GetChildren()) do
            local childPath = path .. "/" .. child.Name
            local isBtn = child:IsA("TextButton") or child:IsA("ImageButton")

            if isBtn then
                btnCount = btnCount + 1
                local text = child:IsA("TextButton") and child.Text or "[ImageBtn]"
                local vis = child.Visible and "V" or "H"
                local info = string.format("[%s] %s | text=%q class=%s size=%dx%d",
                    vis, childPath, text, child.ClassName,
                    math.floor(child.AbsoluteSize.X), math.floor(child.AbsoluteSize.Y))
                log("SCAN", info)
                addBattleLog("🔘 " .. child.Name .. " | " .. text .. " [" .. vis .. "]", C.Orange)
            end

            scanNode(child, childPath, depth + 1)
        end
    end

    scanNode(pgui, "PlayerGui", 0)
    log("SCAN", "Total buttons found: " .. btnCount)
    addBattleLog("🔍 Scan: " .. btnCount .. " buttons (check F9 console)", C.Orange)
    sendNotification("LumiWare", "Scan: " .. btnCount .. " buttons found.\nCheck F9 console for full paths.", 5)
end)

-- OUTGOING REMOTE SPY: hook FireServer to see what client sends
pcall(function()
    local oldFire
    if hookfunction then
        local remoteEventMeta = getrawmetatable(Instance.new("RemoteEvent"))
        if remoteEventMeta then
            -- Use namecall hook instead
        end
    end

    -- Try namecall hook (most compatible)
    if hookmetamethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and self:IsA("RemoteEvent") then
                if discoveryMode and self.Name == "EVT" then
                    local args = {...}
                    local parts = {}
                    for i = 1, math.min(#args, 6) do
                        if type(args[i]) == "string" then
                            table.insert(parts, "arg" .. i .. '="' .. string.sub(args[i], 1, 30) .. '"')
                        elseif type(args[i]) == "table" then
                            table.insert(parts, "arg" .. i .. "=table")
                        elseif type(args[i]) == "number" then
                            table.insert(parts, "arg" .. i .. "=" .. tostring(args[i]))
                        else
                            table.insert(parts, "arg" .. i .. "=" .. type(args[i]))
                        end
                    end
                    log("OUTGOING", ">>> " .. self.Name .. ":FireServer(" .. table.concat(parts, ", ") .. ")")
                    addBattleLog("📤 OUT " .. self.Name .. " | " .. table.concat(parts, ", "), Color3.fromRGB(255, 180, 80))
                end
            end
            return oldNamecall(self, ...)
        end)
        log("HOOK", "Outgoing remote spy installed (namecall)")
    else
        log("HOOK", "hookmetamethod not available — outgoing spy disabled")
    end
end)

-- BATTLE LOG (shifted down)
local blPanel = Instance.new("Frame", contentFrame)
blPanel.Size = UDim2.new(1, 0, 0, 100)
blPanel.Position = UDim2.new(0, 0, 0, 498)
blPanel.BackgroundColor3 = C.Panel
blPanel.BorderSizePixel = 0
Instance.new("UICorner", blPanel).CornerRadius = UDim.new(0, 8)
local blt = Instance.new("TextLabel", blPanel)
blt.Size = UDim2.new(1, -16, 0, 20)
blt.Position = UDim2.new(0, 8, 0, 4)
blt.BackgroundTransparency = 1
blt.Text = "⚔️ BATTLE LOG"
blt.Font = Enum.Font.GothamBold
blt.TextSize = 11
blt.TextColor3 = C.Green
blt.TextXAlignment = Enum.TextXAlignment.Left

local battleScroll = Instance.new("ScrollingFrame", blPanel)
battleScroll.Size = UDim2.new(1, -16, 1, -28)
battleScroll.Position = UDim2.new(0, 8, 0, 24)
battleScroll.BackgroundTransparency = 1
battleScroll.ScrollBarThickness = 3
battleScroll.ScrollBarImageColor3 = C.Green
battleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
battleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
local bll = Instance.new("UIListLayout", battleScroll)
bll.SortOrder = Enum.SortOrder.LayoutOrder
bll.Padding = UDim.new(0, 2)

local blOrder, blCount = 0, 0
addBattleLog = function(text, color)
    blOrder = blOrder + 1
    blCount = blCount + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.TextDim
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = blOrder
    item.Parent = battleScroll
    if blCount > 40 then
        for _, ch in ipairs(battleScroll:GetChildren()) do
            if ch:IsA("TextLabel") then ch:Destroy() blCount = blCount - 1 break end
        end
    end
end

-- CONTROLS (shifted down)
local ctrlPanel = Instance.new("Frame", contentFrame)
ctrlPanel.Size = UDim2.new(1, 0, 0, 36)
ctrlPanel.Position = UDim2.new(0, 0, 0, 604)
ctrlPanel.BackgroundColor3 = C.Panel
ctrlPanel.BorderSizePixel = 0
Instance.new("UICorner", ctrlPanel).CornerRadius = UDim.new(0, 8)
local cl = Instance.new("UIListLayout", ctrlPanel)
cl.FillDirection = Enum.FillDirection.Horizontal
cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
cl.VerticalAlignment = Enum.VerticalAlignment.Center
cl.Padding = UDim.new(0, 6)

local function mkBtn(parent, text)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0.3, -6, 0, 26)
    b.BackgroundColor3 = C.AccentDim
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C.Text
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local resetBtn = mkBtn(ctrlPanel, "🔄 RESET")
local discoveryBtn = mkBtn(ctrlPanel, "🔍 DISCOVERY")
local verboseBtn = mkBtn(ctrlPanel, "📝 VERBOSE")

resetBtn.MouseButton1Click:Connect(function()
    encounterCount = 0; huntStartTime = tick(); raresFoundCount = 0
    encounterHistory = {}; currentEnemy = nil; resetBattle()
    encounterVal.Text = "0"; epmVal.Text = "0.0"; timerVal.Text = "0m 00s"
    typeVal.Text = "N/A"; typeVal.TextColor3 = C.TextDim
    stateVal.Text = "Idle"; stateVal.TextColor3 = C.TextDim
    enemyLbl.Text = "Enemy: Waiting for battle..."
    enemyStatsLbl.Text = ""; playerLbl.Text = "Your Loomian: —"
    addBattleLog("Session reset", C.Accent)
end)
discoveryBtn.MouseButton1Click:Connect(function()
    discoveryMode = not discoveryMode
    discoveryBtn.BackgroundColor3 = discoveryMode and C.Orange or C.AccentDim
    discoveryBtn.Text = discoveryMode and "🔍 DISC: ON" or "🔍 DISCOVERY"
    addBattleLog("Discovery: " .. tostring(discoveryMode), C.Orange)
end)
verboseBtn.MouseButton1Click:Connect(function()
    VERBOSE_MODE = not VERBOSE_MODE
    verboseBtn.BackgroundColor3 = VERBOSE_MODE and C.Orange or C.AccentDim
    verboseBtn.Text = VERBOSE_MODE and "📝 VERB: ON" or "📝 VERBOSE"
end)

-- MINIMIZE
local fullSize = UDim2.fromOffset(460, 720)
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = UDim2.fromOffset(460, 36) }):Play()
        contentFrame.Visible = false; minBtn.Text = "+"
    else
        contentFrame.Visible = true
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = fullSize }):Play()
        minBtn.Text = "–"
    end
end)

-- TIMER
task.spawn(function()
    while gui.Parent do
        local elapsed = tick() - huntStartTime
        timerVal.Text = formatTime(elapsed)
        local minutes = elapsed / 60
        if minutes > 0 then epmVal.Text = string.format("%.1f", encounterCount / minutes) end
        if battleState == "active" and (tick() - lastBattleTick) > 30 then
            battleState = "idle"; stateVal.Text = "Idle"; stateVal.TextColor3 = C.TextDim
        end
        task.wait(1)
    end
end)
-- SESSION WEBHOOK
task.spawn(function()
    local lastMs = 0
    while gui.Parent do
        if encounterCount > 0 and encounterCount % 50 == 0 and encounterCount ~= lastMs then
            lastMs = encounterCount
            sendSessionWebhook(encounterCount, formatTime(tick() - huntStartTime), raresFoundCount)
        end
        task.wait(5)
    end
end)

--------------------------------------------------
-- AUTO-WALK: Circle Movement
--------------------------------------------------
local function startAutoWalk()
    if autoWalkThread then return end
    autoWalkThread = task.spawn(function()
        log("INFO", "Auto-walk started")
        local char = player.Character or player.CharacterAdded:Wait()
        local humanoid = char:WaitForChild("Humanoid")
        local rootPart = char:WaitForChild("HumanoidRootPart")
        local center = rootPart.Position
        local radius = 6
        local numPoints = 6
        local pointIndex = 0

        while autoWalkEnabled and gui.Parent do
            -- Pause during battles
            if battleState == "active" then
                task.wait(0.5)
            else
                -- Refresh character reference
                char = player.Character
                if not char then task.wait(1)
                else
                    humanoid = char:FindFirstChild("Humanoid")
                    rootPart = char:FindFirstChild("HumanoidRootPart")
                    if not humanoid or not rootPart or humanoid.Health <= 0 then
                        task.wait(1)
                    else
                        -- Calculate next waypoint in circle
                        local angle = (pointIndex / numPoints) * math.pi * 2
                        local targetPos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                        pointIndex = (pointIndex + 1) % numPoints

                        humanoid:MoveTo(targetPos)

                        -- Wait for move to complete or timeout
                        local moveStart = tick()
                        local reached = false
                        local conn
                        conn = humanoid.MoveToFinished:Connect(function()
                            reached = true
                        end)
                        while not reached and (tick() - moveStart) < 4 and autoWalkEnabled do
                            task.wait(0.1)
                        end
                        if conn then conn:Disconnect() end
                        task.wait(0.2)
                    end
                end
            end
        end
        log("INFO", "Auto-walk stopped")
    end)
end

local function stopAutoWalk()
    autoWalkEnabled = false
    if autoWalkThread then
        pcall(function() task.cancel(autoWalkThread) end)
        autoWalkThread = nil
    end
    pcall(function()
        local char = player.Character
        if char then
            local h = char:FindFirstChild("Humanoid")
            local rp = char:FindFirstChild("HumanoidRootPart")
            if h and rp then h:MoveTo(rp.Position) end
        end
    end)
end

walkBtn.MouseButton1Click:Connect(function()
    autoWalkEnabled = not autoWalkEnabled
    updateAutoUI()
    if autoWalkEnabled then
        startAutoWalk()
        sendNotification("LumiWare", "Auto-walk ON — walking in circles", 3)
        addBattleLog("🚶 Auto-walk ON", C.Green)
    else
        stopAutoWalk()
        sendNotification("LumiWare", "Auto-walk OFF", 3)
        addBattleLog("🚶 Auto-walk OFF", C.TextDim)
    end
end)

--------------------------------------------------
-- AUTO-BATTLE: Find & Click Game UI Buttons
--------------------------------------------------
local function findBattleUI()
    local pgui = player:FindFirstChild("PlayerGui")
    if not pgui then return nil end

    local result = {
        runButton = nil,
        fightButton = nil,
        moveButtons = {},
    }

    local function searchUI(parent, depth)
        if depth > 12 then return end
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("ImageButton") then
                local text = ""
                if child:IsA("TextButton") then text = string.lower(child.Text) end
                local cname = child.Name:lower()

                -- Run button
                if text == "run" or cname == "run" or string.find(cname, "runbtn") or string.find(cname, "flee") then
                    if child.Visible ~= false then result.runButton = child end
                end

                -- Fight button
                if text == "fight" or cname == "fight" or string.find(cname, "fightbtn") or string.find(cname, "attack") then
                    if child.Visible ~= false then result.fightButton = child end
                end
            end

            -- Move buttons container
            if child:IsA("Frame") or child:IsA("ScrollingFrame") then
                local cname = child.Name:lower()
                if string.find(cname, "move") or string.find(cname, "skill") or string.find(cname, "attack") then
                    local moveIdx = 0
                    for _, mBtn in ipairs(child:GetChildren()) do
                        if mBtn:IsA("TextButton") or mBtn:IsA("ImageButton") then
                            moveIdx = moveIdx + 1
                            result.moveButtons[moveIdx] = mBtn
                        end
                    end
                end
            end

            searchUI(child, depth + 1)
        end
    end

    searchUI(pgui, 0)
    return result
end

local function clickButton(button)
    if not button then return false end
    local success = false
    pcall(function()
        -- Method 1: fireclick (common executor function)
        if fireclick then
            fireclick(button)
            success = true
            return
        end
        -- Method 2: firesignal
        if firesignal then
            firesignal(button.MouseButton1Click)
            success = true
            return
        end
        -- Method 3: VirtualInputManager
        local absPos = button.AbsolutePosition
        local absSize = button.AbsoluteSize
        local cx = absPos.X + absSize.X / 2
        local cy = absPos.Y + absSize.Y / 2
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        success = true
    end)
    return success
end

local function performAutoAction()
    if autoMode == "off" or rareFoundPause or pendingAutoAction then return end
    if currentBattle.battleType ~= "Wild" then return end

    pendingAutoAction = true

    task.spawn(function()
        -- Wait for game UI to render
        task.wait(1.5)

        if rareFoundPause or autoMode == "off" then
            pendingAutoAction = false
            return
        end

        local ui = findBattleUI()
        if not ui then
            log("AUTO", "Could not find battle UI")
            addBattleLog("⚠ Auto: Battle UI not found", C.Orange)
            pendingAutoAction = false
            return
        end

        if autoMode == "run" then
            if ui.runButton then
                log("AUTO", "Auto-RUN: clicking run button")
                addBattleLog("🤖 Auto-RUN ▸ fleeing", C.Cyan)
                clickButton(ui.runButton)
            else
                addBattleLog("⚠ Auto: Run button not found", C.Orange)
            end
        elseif autoMode == "move" then
            -- Click Fight first to open move menu
            if ui.fightButton then
                log("AUTO", "Auto-MOVE: clicking fight button")
                clickButton(ui.fightButton)
                task.wait(0.8)

                -- Re-scan for move buttons
                local ui2 = findBattleUI()
                if ui2 and ui2.moveButtons[autoMoveSlot] then
                    log("AUTO", "Auto-MOVE: clicking move slot " .. autoMoveSlot)
                    addBattleLog("🤖 Auto-MOVE ▸ slot " .. autoMoveSlot, C.Green)
                    clickButton(ui2.moveButtons[autoMoveSlot])
                elseif ui2 then
                    -- Fallback: click any available move
                    for s = 1, 4 do
                        if ui2.moveButtons[s] then
                            addBattleLog("🤖 Auto-MOVE ▸ slot " .. s .. " (fallback)", C.Green)
                            clickButton(ui2.moveButtons[s])
                            break
                        end
                    end
                else
                    addBattleLog("⚠ Auto: Move buttons not found", C.Orange)
                end
            else
                addBattleLog("⚠ Auto: Fight button not found", C.Orange)
            end
        end

        pendingAutoAction = false
    end)
end

--------------------------------------------------
-- BATTLE PROCESSING (THE CORE FIX)
--
-- From discovery logs, the actual data is:
--   arg4 = { {cmd, ...}, {cmd, ...}, ... }
-- Where commands are:
--   {"player", "p2", "#Wild", 0}
--   {"player", "p1", "glo", 0}
--   {"owm", "p1", "1p1: Dripple", "Dripple, L13, M;41/44;...", {disc=..., name=..., scale=...}, 0}
--   {"start"}
--   {"switch", "1p2a: Grubby", "Grubby, L5, M;18/18;...", {disc=..., name=...}, {icon=...}}
--
-- KEY DIFFERENCE: "owm" has side as entry[2], identifier as entry[3]
--                 "switch" has identifier as entry[2] (contains side like "p2a")
--------------------------------------------------

local function extractNameAndSide(cmdEntry)
    -- Returns: rawName, side ("p1"/"p2"), infoStr, displayName
    local cmd = cmdEntry[1]
    if type(cmd) ~= "string" then return nil end
    local cmdL = string.lower(cmd)

    if cmdL ~= "owm" and cmdL ~= "switch" then return nil end

    local rawName = nil
    local side = nil
    local infoStr = nil

    -- Scan ALL string args to find: side, identifier (has ":"), and info string (has ", L")
    for i = 2, math.min(#cmdEntry, 8) do
        local v = cmdEntry[i]
        if type(v) == "string" then
            -- Pure side: "p1" or "p2"
            if (v == "p1" or v == "p2") and not side then
                side = v
            -- Identifier with colon: "1p1a: Dripple" or "1p2a: Grubby"
            elseif string.find(v, ":%s*.+") then
                local n = v:match(":%s*(.+)$")
                if n then rawName = n end
                -- Extract side from identifier too
                if string.find(v, "p1") then side = side or "p1"
                elseif string.find(v, "p2") then side = side or "p2" end
            -- Info string: "Dripple, L13, M;41/44;..."
            elseif string.find(v, ", L%d+") then
                infoStr = v
                -- Can also get name from info string
                if not rawName then
                    rawName = v:match("^([^,]+)")
                end
            end
        elseif type(v) == "table" and not rawName then
            -- Model table: might have .name
            if type(v.name) == "string" then
                rawName = v.name
            end
        end
    end

    if rawName then
        return rawName, side, infoStr, extractLoomianName(rawName)
    end
    return nil
end

local function processBattleCommands(commandTable)
    log("BATTLE", "========== PROCESSING " .. tostring(#commandTable) .. " COMMANDS ==========")
    addBattleLog(">>> " .. tostring(#commandTable) .. " battle cmds <<<", C.Green)

    -- Check for "start" -> new battle
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" and string.lower(entry[1]) == "start" then
            log("BATTLE", "  NEW BATTLE (start found)")
            resetBattle()
            currentBattle.active = true
            break
        end
    end

    -- Process "player" commands first (to establish battle type)
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" and string.lower(entry[1]) == "player" then
            local side = entry[2]
            local tag = entry[3]
            log("BATTLE", "  player cmd: side=" .. tostring(side) .. " tag=" .. tostring(tag))
            if type(tag) == "string" then
                if string.find(tag, "#Wild") then
                    currentBattle.battleType = "Wild"
                elseif side == "p2" then
                    currentBattle.battleType = "Trainer"
                end
            end
        end
    end

    -- Process "owm" and "switch" commands (Loomian data)
    -- ALSO: deep scan each enemy entry for gleam/corrupt/gamma
    for _, entry in pairs(commandTable) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmdL = string.lower(entry[1])
            if cmdL == "owm" or cmdL == "switch" then
                local rawName, side, infoStr, displayName = extractNameAndSide(entry)
                if rawName then
                    local stats = parseLoomianStats(infoStr)
                    log("BATTLE", "  " .. entry[1] .. ": name=" .. displayName .. " side=" .. tostring(side))

                    if side == "p2" then
                        currentBattle.enemy = displayName
                        currentBattle.enemyStats = stats
                        currentBattle.enemyRawEntry = entry  -- save for deep scan
                        log("BATTLE", "    -> ENEMY: " .. displayName)
                    elseif side == "p1" then
                        currentBattle.player = displayName
                        currentBattle.playerStats = stats
                        log("BATTLE", "    -> PLAYER: " .. displayName)
                    else
                        if not currentBattle.enemy then
                            currentBattle.enemy = displayName
                            currentBattle.enemyStats = stats
                            currentBattle.enemyRawEntry = entry
                        elseif not currentBattle.player then
                            currentBattle.player = displayName
                            currentBattle.playerStats = stats
                        end
                    end
                else
                    log("BATTLE", "  " .. entry[1] .. ": FAILED to extract name")
                    for idx = 1, math.min(#entry, 6) do
                        log("BATTLE", "    [" .. idx .. "] type=" .. type(entry[idx]) .. " val=" .. tostring(entry[idx]))
                    end
                end
            end
        end
    end

    -- Also try to get enemy name from "move" / "damage" commands if still unknown
    if not currentBattle.enemy then
        for _, entry in pairs(commandTable) do
            if type(entry) == "table" and type(entry[1]) == "string" then
                local cmdL = string.lower(entry[1])
                if cmdL == "move" or cmdL == "damage" or cmdL == "-damage" then
                    for i = 2, #entry do
                        if type(entry[i]) == "string" then
                            local pNum, name = entry[i]:match("p(%d+)%a*:%s*(.+)$")
                            if pNum == "2" and name then
                                currentBattle.enemy = extractLoomianName(name)
                                log("BATTLE", "  enemy from " .. cmdL .. ": " .. currentBattle.enemy)
                                break
                            end
                        end
                    end
                    if currentBattle.enemy then break end
                end
            end
        end
    end

    -- Mark active
    battleState = "active"
    lastBattleTick = tick()
    currentBattle.active = true
    stateVal.Text = "In Battle"
    stateVal.TextColor3 = C.Green

    local enemyName = currentBattle.enemy or "Unknown"
    local playerName = currentBattle.player or "Unknown"

    log("BATTLE", "RESULT: Enemy=" .. enemyName .. " Player=" .. playerName .. " Type=" .. currentBattle.battleType)

    -- Update display
    if currentBattle.battleType == "Wild" then
        typeVal.Text = "Wild"; typeVal.TextColor3 = C.Wild
    elseif currentBattle.battleType == "Trainer" then
        typeVal.Text = "Trainer"; typeVal.TextColor3 = C.Trainer
    end

    if enemyName ~= "Unknown" and not currentBattle.enemyProcessed then
        currentBattle.enemyProcessed = true

        if currentBattle.battleType == "Wild" then
            encounterCount = encounterCount + 1
            encounterVal.Text = tostring(encounterCount)
            table.insert(encounterHistory, 1, { name = enemyName, time = os.date("%X") })
            if #encounterHistory > 10 then table.remove(encounterHistory, 11) end
        end

        -- MULTI-LAYER RARE CHECK:
        -- 1. Is the enemy name in the rare list?
        -- 2. Does the name contain a rare modifier (gleam/gamma/etc)?
        -- 3. Deep scan the raw command entry (model tables, disc names, etc.)
        local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)
        if not rareFound and currentBattle.enemyRawEntry then
            rareFound = scanEntryForRare(currentBattle.enemyRawEntry)
            if rareFound then
                log("RARE", "!!! DEEP SCAN caught rare in model/disc data !!!")
            end
        end
        if rareFound then
            enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
            addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
            -- PAUSE automation on rare!
            rareFoundPause = true
            updateAutoUI()
            if currentEnemy ~= enemyName then
                currentEnemy = enemyName
                raresFoundCount = raresFoundCount + 1
                playRareSound()
                sendNotification("⭐ LumiWare", "RARE: " .. enemyName .. "! Automation PAUSED.", 10)
                addRareLog(enemyName, currentBattle.enemyStats and ("Lv." .. tostring(currentBattle.enemyStats.level)) or nil)
                sendRareWebhook(enemyName, currentBattle.enemyStats and currentBattle.enemyStats.level,
                    currentBattle.enemyStats and currentBattle.enemyStats.gender or "?",
                    encounterCount, formatTime(tick() - huntStartTime))
            end
        else
            enemyLbl.Text = "Enemy: " .. enemyName
            addBattleLog(currentBattle.battleType .. ": " .. enemyName, C.TextDim)
            currentEnemy = nil
            -- Trigger auto-action on non-rare wild encounter
            if currentBattle.battleType == "Wild" and autoMode ~= "off" and not rareFoundPause then
                performAutoAction()
            end
        end
    end

    if currentBattle.enemyStats then
        local s = currentBattle.enemyStats
        local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        enemyStatsLbl.Text = string.format("Lv.%d  %s  HP %d/%d", s.level or 0, g, s.hp or 0, s.maxHP or 0)
    end

    if playerName ~= "Unknown" then
        playerLbl.Text = "Your Loomian: " .. playerName
        if currentBattle.playerStats then
            local s = currentBattle.playerStats
            local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
            playerLbl.Text = playerLbl.Text .. string.format("  (Lv.%d %s HP %d/%d)", s.level or 0, g, s.hp or 0, s.maxHP or 0)
        end
    end

    log("BATTLE", "========== DONE ==========")
end

--------------------------------------------------
-- HOOK REMOTES
-- CRITICAL: Do NOT use vararg forwarding to helper
-- functions — Roblox executors break it.
-- Instead, capture args into a table IMMEDIATELY
-- at the top of the callback.
--------------------------------------------------
local hooked = {}
local hookedCount = 0

local KNOWN_COMMANDS = {
    player = true, owm = true, switch = true, start = true,
    move = true, damage = true, ["-damage"] = true,
    turn = true, faint = true, ["end"] = true,
}

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    remote.OnClientEvent:Connect(function(...)
        -- ============================================
        -- STEP 0: Capture ALL args into a table IMMEDIATELY
        -- Do not rely on ... after this point.
        -- ============================================
        local argCount = select("#", ...)
        local allArgs = {}
        for i = 1, argCount do
            allArgs[i] = select(i, ...)
        end
        allArgs.n = argCount

        -- Discovery logging
        if discoveryMode then
            local parts = {}
            for i = 1, argCount do
                local a = allArgs[i]
                local info = "arg" .. i .. "=" .. type(a)
                if type(a) == "string" then
                    info = info .. '("' .. string.sub(a, 1, 20) .. '")'
                elseif type(a) == "table" then
                    local c = 0
                    for _ in pairs(a) do c = c + 1 end
                    info = info .. "(n=" .. c .. ")"
                end
                table.insert(parts, info)
            end
            addBattleLog("📡 " .. remote.Name .. " | " .. table.concat(parts, ", "), Color3.fromRGB(180, 180, 180))

            if VERBOSE_MODE then
                for i = 1, argCount do
                    local a = allArgs[i]
                    if type(a) == "table" then
                        log("EVT", remote.Name, "arg" .. i .. ":", tablePreview(a))
                    end
                end
            end
        end

        -- ============================================
        -- STEP 1: Is this a battle event?
        -- ============================================
        local isBattle = false
        if type(allArgs[1]) == "string" then
            if string.lower(allArgs[1]):find("battle") then
                isBattle = true
            end
        end

        -- ============================================
        -- STEP 2: Find and decode the command table
        -- CRITICAL: Battle commands are JSON-ENCODED
        -- STRINGS, not Lua tables! e.g.:
        --   arg4[1] = '["player","p2","#Wild",0]'
        --   arg4[2] = '["player","p1","glo",0]'
        -- We must JSONDecode each entry first.
        -- ============================================
        local cmdTable = nil

        for i = 1, argCount do
            local arg = allArgs[i]
            if type(arg) == "table" then
                -- Check entries: are they JSON strings or Lua tables?
                for k, v in pairs(arg) do
                    if type(v) == "table" then
                        -- Already a Lua table (unlikely based on diagnostics, but handle it)
                        local first = v[1]
                        if type(first) == "string" and KNOWN_COMMANDS[string.lower(first)] then
                            log("BATTLE", ">>> FOUND native cmd table in arg" .. i)
                            cmdTable = arg
                            break
                        end
                    elseif type(v) == "string" and string.sub(v, 1, 1) == "[" then
                        -- JSON-encoded string! Try to decode it
                        local ok, decoded = pcall(function()
                            return HttpService:JSONDecode(v)
                        end)
                        if ok and type(decoded) == "table" and type(decoded[1]) == "string" then
                            local cmd = string.lower(decoded[1])
                            if KNOWN_COMMANDS[cmd] then
                                log("BATTLE", ">>> FOUND JSON cmd table in arg" .. i .. " (cmd=" .. decoded[1] .. ")")
                                -- Decode ALL entries in this table
                                local decodedTable = {}
                                for key, val in pairs(arg) do
                                    if type(val) == "string" and string.sub(val, 1, 1) == "[" then
                                        local ok2, dec2 = pcall(function()
                                            return HttpService:JSONDecode(val)
                                        end)
                                        if ok2 and type(dec2) == "table" then
                                            decodedTable[key] = dec2
                                        else
                                            decodedTable[key] = val
                                        end
                                    elseif type(val) == "string" and string.sub(val, 1, 1) == "{" then
                                        local ok2, dec2 = pcall(function()
                                            return HttpService:JSONDecode(val)
                                        end)
                                        if ok2 and type(dec2) == "table" then
                                            decodedTable[key] = dec2
                                        else
                                            decodedTable[key] = val
                                        end
                                    else
                                        decodedTable[key] = val
                                    end
                                end
                                cmdTable = decodedTable
                                break
                            end
                        end
                    end
                end
                if cmdTable then break end
            end
        end

        -- ============================================
        -- STEP 3: Process battle data if found
        -- ============================================
        if cmdTable then
            processBattleCommands(cmdTable)
        elseif isBattle then
            logDebug("BattleEvent no cmd table, arg3=" .. tostring(allArgs[3]))
        end
    end)
end

-- Hook all
log("HOOK", "Scanning...")
local c = 0
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") then hookEvent(obj) c = c + 1 end
end
log("HOOK", "Hooked", c, "from ReplicatedStorage")

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then hookEvent(obj) end
end)

pcall(function()
    for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then hookEvent(obj) end
    end
end)
pcall(function()
    for _, obj in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then hookEvent(obj) end
    end
end)

addBattleLog("Hooked " .. hookedCount .. " remotes — READY", C.Green)
log("INFO", "LumiWare v4 READY | Hooked " .. hookedCount .. " | Player: " .. PLAYER_NAME)
sendNotification("⚡ LumiWare v4", "Hooked " .. hookedCount .. " remotes.\nBattle detection + automation ready.", 6)
