--------------------------------------------------
-- LUMIWARE V3.1 — Battle Detection Fix
-- FORMAT: EVT(arg1="BattleEvent", arg2=sessionID,
--   arg3=subCmd, arg4=commandTable)
-- Commands: "owm"/"switch"/"player"/"start"
--------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

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

log("INFO", "Initializing LumiWare v3.1 for:", PLAYER_NAME)

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

local function isRareModifier(name)
    local l = string.lower(name)
    return string.find(l, "gleam") or string.find(l, "gamma") or string.find(l, "corrupt") or string.find(l, "alpha") or string.find(l, "sa ") or string.find(l, "pn ")
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
mainFrame.Size = UDim2.fromOffset(460, 580)
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
titleLbl.Text = "⚡ LumiWare v3.1"
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

-- BATTLE LOG
local blPanel = Instance.new("Frame", contentFrame)
blPanel.Size = UDim2.new(1, 0, 0, 100)
blPanel.Position = UDim2.new(0, 0, 0, 362)
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
local function addBattleLog(text, color)
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

-- CONTROLS
local ctrlPanel = Instance.new("Frame", contentFrame)
ctrlPanel.Size = UDim2.new(1, 0, 0, 36)
ctrlPanel.Position = UDim2.new(0, 0, 0, 468)
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
local fullSize = mainFrame.Size
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
                        log("BATTLE", "    -> ENEMY: " .. displayName)
                    elseif side == "p1" then
                        currentBattle.player = displayName
                        currentBattle.playerStats = stats
                        log("BATTLE", "    -> PLAYER: " .. displayName)
                    else
                        -- No side detected, use position
                        if not currentBattle.enemy then
                            currentBattle.enemy = displayName
                            currentBattle.enemyStats = stats
                        elseif not currentBattle.player then
                            currentBattle.player = displayName
                            currentBattle.playerStats = stats
                        end
                    end
                else
                    log("BATTLE", "  " .. entry[1] .. ": FAILED to extract name")
                    -- Emergency dump of this entry
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

        local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)
        if rareFound then
            enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
            addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
            if currentEnemy ~= enemyName then
                currentEnemy = enemyName
                raresFoundCount = raresFoundCount + 1
                playRareSound()
                sendNotification("⭐ LumiWare", "RARE: " .. enemyName .. "!", 10)
                addRareLog(enemyName, currentBattle.enemyStats and ("Lv." .. tostring(currentBattle.enemyStats.level)) or nil)
                sendRareWebhook(enemyName, currentBattle.enemyStats and currentBattle.enemyStats.level,
                    currentBattle.enemyStats and currentBattle.enemyStats.gender or "?",
                    encounterCount, formatTime(tick() - huntStartTime))
            end
        else
            enemyLbl.Text = "Enemy: " .. enemyName
            addBattleLog(currentBattle.battleType .. ": " .. enemyName, C.TextDim)
            currentEnemy = nil
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
        -- STEP 2: Find the command table
        -- Search EVERY arg for a table containing
        -- subtables whose [1] is a known command.
        -- Uses BOTH pairs() AND direct indexing as
        -- redundant methods.
        -- ============================================
        local cmdTable = nil

        local searchFrom = isBattle and 1 or 1
        for i = searchFrom, argCount do
            local arg = allArgs[i]
            if type(arg) == "table" then
                local found = false

                -- Method 1: pairs() iteration
                for k, v in pairs(arg) do
                    if type(v) == "table" then
                        local first = v[1]
                        if type(first) == "string" then
                            local cmd = string.lower(first)
                            if KNOWN_COMMANDS[cmd] then
                                log("BATTLE", ">>> FOUND cmd table via pairs() in arg" .. i .. " key=" .. tostring(k) .. " cmd=" .. first)
                                cmdTable = arg
                                found = true
                                break
                            end
                        end
                    end
                end

                if found then break end

                -- Method 2: Direct numeric indexing (1 to 20)
                -- In case pairs() somehow skips entries
                for j = 1, 20 do
                    local v = arg[j]
                    if v == nil then break end
                    if type(v) == "table" then
                        local first = v[1]
                        if type(first) == "string" then
                            local cmd = string.lower(first)
                            if KNOWN_COMMANDS[cmd] then
                                log("BATTLE", ">>> FOUND cmd table via index in arg" .. i .. " [" .. j .. "] cmd=" .. first)
                                cmdTable = arg
                                found = true
                                break
                            end
                        end
                    end
                end

                if found then break end

                -- Method 3: rawget (bypass metatables)
                -- Try key 1 directly with rawget
                local raw1 = rawget(arg, 1)
                if type(raw1) == "table" then
                    local rawFirst = rawget(raw1, 1)
                    if type(rawFirst) == "string" then
                        local cmd = string.lower(rawFirst)
                        if KNOWN_COMMANDS[cmd] then
                            log("BATTLE", ">>> FOUND cmd table via rawget in arg" .. i .. " cmd=" .. rawFirst)
                            cmdTable = arg
                            break
                        end
                    end
                end

                -- Diagnostic: if this is a BattleEvent and this arg is a table, log what we see
                if isBattle and VERBOSE_MODE then
                    log("DEBUG", "  arg" .. i .. " is table, scanning entries:")
                    local entryCount = 0
                    for k, v in pairs(arg) do
                        entryCount = entryCount + 1
                        if entryCount <= 5 then
                            log("DEBUG", "    key=" .. tostring(k) .. " type(v)=" .. type(v))
                            if type(v) == "table" then
                                log("DEBUG", "      v[1]=" .. tostring(v[1]) .. " type(v[1])=" .. type(v[1]))
                            end
                        end
                    end
                    log("DEBUG", "  total entries: " .. entryCount)
                end
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
log("INFO", "LumiWare v3.2 READY | Hooked " .. hookedCount .. " | Player: " .. PLAYER_NAME)
sendNotification("⚡ LumiWare v3.2", "Hooked " .. hookedCount .. " remotes. Battle detection active.", 6)
