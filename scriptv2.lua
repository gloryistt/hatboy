--------------------------------------------------
-- LUMIWARE V3 — Battle Detection Fix + Webhook
-- Data format: EVT remote fires individual events
-- arg1=command, arg2-5=data (NOT array-of-commands)
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
-- STRUCTURED LOGGING
--------------------------------------------------
local LOG_LEVELS = { HOOK = "🔗", BATTLE = "⚔️", RARE = "⭐", INFO = "ℹ️", WARN = "⚠️", WEBHOOK = "📡", DEBUG = "🔍", EVT = "📦" }
local VERBOSE_MODE = false

local function log(category, ...)
    local prefix = "[LumiWare][" .. (LOG_LEVELS[category] or "?") .. " " .. category .. "]"
    print(prefix, ...)
end

local function logDebug(...)
    if VERBOSE_MODE then
        log("DEBUG", ...)
    end
end

log("INFO", "Initializing LumiWare v3 for player:", PLAYER_NAME)

--------------------------------------------------
-- RARE LOOMIANS DB
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Protogon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Cynamoth", "Avitross", "Snocub", "Eaglit",
    "Vambat", "Weevolt", "Nevermare",
    "Akhalos", "Odasho", "Cosmiore", "Armenti"
}

local customRares = {}
log("INFO", "Loaded", #RARE_LOOMIANS, "built-in rare Loomians")

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
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

local function playRareSound()
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://6518811702"
        sound.Volume = 1
        sound.Parent = SoundService
        sound:Play()
        task.delay(3, function() sound:Destroy() end)
    end)
end

--------------------------------------------------
-- WEBHOOK
--------------------------------------------------
local webhookUrl = ""

local function sendWebhook(embedData)
    if webhookUrl == "" then return end
    pcall(function()
        local payload = HttpService:JSONEncode({
            username = "LumiWare",
            embeds = { embedData }
        })
        local httpFunc = (syn and syn.request) or (http and http.request) or request or http_request
        if httpFunc then
            httpFunc({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = payload
            })
            log("WEBHOOK", "Sent:", embedData.title or "untitled")
        else
            log("WARN", "No HTTP function available for webhooks")
        end
    end)
end

local function sendRareWebhook(loomianName, level, gender, encounterCount, huntTime)
    sendWebhook({
        title = "⭐ RARE LOOMIAN FOUND!",
        description = "**" .. loomianName .. "** has been detected!",
        color = 16766720,
        fields = {
            { name = "Loomian", value = loomianName, inline = true },
            { name = "Level", value = tostring(level or "?"), inline = true },
            { name = "Gender", value = gender or "?", inline = true },
            { name = "Encounters", value = tostring(encounterCount), inline = true },
            { name = "Hunt Time", value = huntTime or "?", inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare v3 • " .. os.date("%X") },
    })
end

local function sendSessionWebhook(encounterCount, huntTime, raresFound)
    sendWebhook({
        title = "📊 Session Summary",
        description = "LumiWare hunting session update",
        color = 7930367,
        fields = {
            { name = "Total Encounters", value = tostring(encounterCount), inline = true },
            { name = "Hunt Time", value = huntTime, inline = true },
            { name = "Rares Found", value = tostring(raresFound), inline = true },
            { name = "Player", value = PLAYER_NAME, inline = true },
        },
        footer = { text = "LumiWare v3 • " .. os.date("%X") },
    })
end

--------------------------------------------------
-- STATE
--------------------------------------------------
local encounterCount = 0
local huntStartTime = tick()
local currentEnemy = nil
local isMinimized = false
local battleType = "N/A"
local battleState = "idle" -- idle / active
local lastBattleTick = 0
local raresFoundCount = 0
local encounterHistory = {}
local discoveryMode = false
local discoveryEvtOnly = false -- discovery but only EVT

-- Battle accumulator: since EVT fires individual events, we accumulate per-battle
local currentBattle = {
    active = false,
    enemy = nil,
    player = nil,
    enemyStats = nil,
    playerStats = nil,
    battleType = "N/A",
    startTime = 0,
    switches = {},  -- track which sides we've seen switch
}

local function resetBattleAccumulator()
    currentBattle = {
        active = false,
        enemy = nil,
        player = nil,
        enemyStats = nil,
        playerStats = nil,
        battleType = "N/A",
        startTime = 0,
        switches = {},
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
    -- Try format: "Cathorn, L3, F;15/15;0;85/85"
    local name, level, rest = infoStr:match("^(.+), L(%d+), (.+)$")
    if not name then
        -- Try format without name: "L3, F;15/15;0;85/85"
        level, rest = infoStr:match("^L(%d+), (.+)$")
    end
    if not level then return nil end
    local gender = rest and rest:match("^(%a)") or "?"
    local hp, maxHP = rest and rest:match("(%d+)/(%d+)") or nil, nil
    return {
        name = name,
        level = tonumber(level),
        gender = gender,
        hp = tonumber(hp),
        maxHP = tonumber(maxHP)
    }
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%dh %02dm %02ds", h, m, s)
    else
        return string.format("%dm %02ds", m, s)
    end
end

local function tablePreview(tbl, depth)
    depth = depth or 0
    if depth > 2 then return "{...}" end
    local parts = {}
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        if count > 5 then
            table.insert(parts, "...")
            break
        end
        local val
        if type(v) == "table" then
            val = tablePreview(v, depth + 1)
        else
            val = tostring(v)
        end
        table.insert(parts, tostring(k) .. "=" .. val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Deep serialize for when we truly need full dumps (verbose only)
local function deepSerialize(tbl, indent, seen)
    indent = indent or 0
    seen = seen or {}
    if seen[tbl] then return string.rep("  ", indent) .. "<recursive>\n" end
    seen[tbl] = true
    local out = {}
    for k, v in pairs(tbl) do
        local pre = string.rep("  ", indent) .. tostring(k) .. ": "
        if type(v) == "table" then
            table.insert(out, pre .. "{")
            table.insert(out, deepSerialize(v, indent + 1, seen))
            table.insert(out, string.rep("  ", indent) .. "}")
        else
            table.insert(out, pre .. tostring(v))
        end
    end
    return table.concat(out, "\n")
end

--------------------------------------------------
-- GUI: CLEANUP OLD
--------------------------------------------------
log("INFO", "Cleaning up old GUI instances...")
local guiName = "LumiWare_Hub_" .. tostring(math.random(1000, 9999))

for _, v in pairs(player:WaitForChild("PlayerGui"):GetChildren()) do
    if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then
        v:Destroy()
    end
end
pcall(function()
    for _, v in pairs(CoreGui:GetChildren()) do
        if string.find(v.Name, "LumiWare_Hub") or v.Name == "BattleLoomianViewer" then
            v:Destroy()
        end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local ok = pcall(function() gui.Parent = CoreGui end)
if ok then
    log("INFO", "GUI parented to CoreGui")
else
    gui.Parent = player:WaitForChild("PlayerGui")
    log("INFO", "GUI parented to PlayerGui")
end

--------------------------------------------------
-- THEME
--------------------------------------------------
local C = {
    BG        = Color3.fromRGB(16, 16, 22),
    TopBar    = Color3.fromRGB(24, 24, 34),
    Accent    = Color3.fromRGB(120, 80, 255),
    AccentDim = Color3.fromRGB(80, 50, 180),
    Text      = Color3.fromRGB(240, 240, 245),
    TextDim   = Color3.fromRGB(160, 160, 175),
    Panel     = Color3.fromRGB(22, 22, 30),
    PanelAlt  = Color3.fromRGB(28, 28, 38),
    Gold      = Color3.fromRGB(255, 215, 0),
    Green     = Color3.fromRGB(80, 220, 120),
    Red       = Color3.fromRGB(255, 80, 80),
    Wild      = Color3.fromRGB(80, 200, 255),
    Trainer   = Color3.fromRGB(255, 160, 60),
    Orange    = Color3.fromRGB(255, 160, 60),
    Cyan      = Color3.fromRGB(80, 200, 255),
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

--------------------------------------------------
-- TOPBAR
--------------------------------------------------
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
titleLbl.Text = "⚡ LumiWare v3"
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
    log("INFO", "Closing — sending session summary")
    local elapsed = tick() - huntStartTime
    sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag
local dragging, dragInput, dragStart, startPos
topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
topbar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

--------------------------------------------------
-- CONTENT CONTAINER
--------------------------------------------------
local contentFrame = Instance.new("Frame", mainFrame)
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, -16, 1, -44)
contentFrame.Position = UDim2.new(0, 8, 0, 40)
contentFrame.BackgroundTransparency = 1

-- ═══════════════════════════════════════════════
-- STATS BAR
-- ═══════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════
-- CURRENT ENCOUNTER PANEL
-- ═══════════════════════════════════════════════
local encounterPanel = Instance.new("Frame", contentFrame)
encounterPanel.Size = UDim2.new(1, 0, 0, 90)
encounterPanel.Position = UDim2.new(0, 0, 0, 56)
encounterPanel.BackgroundColor3 = C.Panel
encounterPanel.BorderSizePixel = 0
Instance.new("UICorner", encounterPanel).CornerRadius = UDim.new(0, 8)

local encTitle = Instance.new("TextLabel", encounterPanel)
encTitle.Size = UDim2.new(1, -16, 0, 24)
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

-- ═══════════════════════════════════════════════
-- RARE FINDER LOG
-- ═══════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════
-- CUSTOM RARE LIST
-- ═══════════════════════════════════════════════
local customPanel = Instance.new("Frame", contentFrame)
customPanel.Size = UDim2.new(1, 0, 0, 56)
customPanel.Position = UDim2.new(0, 0, 0, 238)
customPanel.BackgroundColor3 = C.Panel
customPanel.BorderSizePixel = 0
Instance.new("UICorner", customPanel).CornerRadius = UDim.new(0, 8)

local customTitle = Instance.new("TextLabel", customPanel)
customTitle.Size = UDim2.new(1, -16, 0, 20)
customTitle.Position = UDim2.new(0, 8, 0, 4)
customTitle.BackgroundTransparency = 1
customTitle.Text = "CUSTOM RARE LIST"
customTitle.Font = Enum.Font.GothamBold
customTitle.TextSize = 11
customTitle.TextColor3 = C.Accent
customTitle.TextXAlignment = Enum.TextXAlignment.Left

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
        if trimmed and trimmed ~= "" then
            table.insert(customRares, trimmed)
            log("INFO", "Added custom rare:", trimmed)
        end
    end
    customInput.Text = ""
    sendNotification("LumiWare", "Added to custom rare list!", 3)
end)

clearBtn.MouseButton1Click:Connect(function()
    customRares = {}
    log("INFO", "Custom rare list cleared")
    sendNotification("LumiWare", "Custom rare list cleared.", 3)
end)

-- ═══════════════════════════════════════════════
-- WEBHOOK CONFIG
-- ═══════════════════════════════════════════════
local webhookPanel = Instance.new("Frame", contentFrame)
webhookPanel.Size = UDim2.new(1, 0, 0, 56)
webhookPanel.Position = UDim2.new(0, 0, 0, 300)
webhookPanel.BackgroundColor3 = C.Panel
webhookPanel.BorderSizePixel = 0
Instance.new("UICorner", webhookPanel).CornerRadius = UDim.new(0, 8)

local webhookTitle = Instance.new("TextLabel", webhookPanel)
webhookTitle.Size = UDim2.new(1, -16, 0, 20)
webhookTitle.Position = UDim2.new(0, 8, 0, 4)
webhookTitle.BackgroundTransparency = 1
webhookTitle.Text = "📡 DISCORD WEBHOOK"
webhookTitle.Font = Enum.Font.GothamBold
webhookTitle.TextSize = 11
webhookTitle.TextColor3 = C.Cyan
webhookTitle.TextXAlignment = Enum.TextXAlignment.Left

local webhookInput = Instance.new("TextBox", webhookPanel)
webhookInput.Size = UDim2.new(1, -60, 0, 26)
webhookInput.Position = UDim2.new(0, 8, 0, 26)
webhookInput.BackgroundColor3 = C.PanelAlt
webhookInput.BorderSizePixel = 0
webhookInput.PlaceholderText = "Paste webhook URL here..."
webhookInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
webhookInput.Text = ""
webhookInput.Font = Enum.Font.Gotham
webhookInput.TextSize = 11
webhookInput.TextColor3 = C.Text
webhookInput.ClearTextOnFocus = false
webhookInput.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UICorner", webhookInput).CornerRadius = UDim.new(0, 5)
Instance.new("UIPadding", webhookInput).PaddingLeft = UDim.new(0, 6)

local webhookSaveBtn = Instance.new("TextButton", webhookPanel)
webhookSaveBtn.Size = UDim2.fromOffset(42, 26)
webhookSaveBtn.Position = UDim2.new(1, -50, 0, 26)
webhookSaveBtn.BackgroundColor3 = C.Cyan
webhookSaveBtn.Text = "SET"
webhookSaveBtn.Font = Enum.Font.GothamBold
webhookSaveBtn.TextSize = 11
webhookSaveBtn.TextColor3 = C.BG
webhookSaveBtn.BorderSizePixel = 0
Instance.new("UICorner", webhookSaveBtn).CornerRadius = UDim.new(0, 5)

webhookSaveBtn.MouseButton1Click:Connect(function()
    webhookUrl = webhookInput.Text
    if webhookUrl ~= "" then
        log("WEBHOOK", "Webhook URL set")
        sendNotification("LumiWare", "Webhook URL saved!", 3)
        sendWebhook({
            title = "✅ Webhook Connected!",
            description = "LumiWare v3 is now sending alerts to this channel.",
            color = 5763719,
            fields = {
                { name = "Player", value = PLAYER_NAME, inline = true },
                { name = "Rares Tracked", value = tostring(#RARE_LOOMIANS + #customRares), inline = true },
            },
            footer = { text = "LumiWare v3 • " .. os.date("%X") },
        })
    else
        log("WEBHOOK", "Webhook URL cleared")
        sendNotification("LumiWare", "Webhook URL cleared.", 3)
    end
end)

-- ═══════════════════════════════════════════════
-- BATTLE LOG
-- ═══════════════════════════════════════════════
local battleLogPanel = Instance.new("Frame", contentFrame)
battleLogPanel.Size = UDim2.new(1, 0, 0, 100)
battleLogPanel.Position = UDim2.new(0, 0, 0, 362)
battleLogPanel.BackgroundColor3 = C.Panel
battleLogPanel.BorderSizePixel = 0
Instance.new("UICorner", battleLogPanel).CornerRadius = UDim.new(0, 8)

local battleLogTitle = Instance.new("TextLabel", battleLogPanel)
battleLogTitle.Size = UDim2.new(1, -16, 0, 20)
battleLogTitle.Position = UDim2.new(0, 8, 0, 4)
battleLogTitle.BackgroundTransparency = 1
battleLogTitle.Text = "⚔️ BATTLE LOG"
battleLogTitle.Font = Enum.Font.GothamBold
battleLogTitle.TextSize = 11
battleLogTitle.TextColor3 = C.Green
battleLogTitle.TextXAlignment = Enum.TextXAlignment.Left

local battleScroll = Instance.new("ScrollingFrame", battleLogPanel)
battleScroll.Size = UDim2.new(1, -16, 1, -28)
battleScroll.Position = UDim2.new(0, 8, 0, 24)
battleScroll.BackgroundTransparency = 1
battleScroll.ScrollBarThickness = 3
battleScroll.ScrollBarImageColor3 = C.Green
battleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
battleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local battleLogLayout = Instance.new("UIListLayout", battleScroll)
battleLogLayout.SortOrder = Enum.SortOrder.LayoutOrder
battleLogLayout.Padding = UDim.new(0, 2)

local battleLogOrder = 0
local battleLogItemCount = 0
local MAX_BATTLE_LOG_ITEMS = 40

local function addBattleLog(text, color)
    battleLogOrder = battleLogOrder + 1
    battleLogItemCount = battleLogItemCount + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.TextDim
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = battleLogOrder
    item.Parent = battleScroll

    if battleLogItemCount > MAX_BATTLE_LOG_ITEMS then
        local children = battleScroll:GetChildren()
        for _, child in ipairs(children) do
            if child:IsA("TextLabel") then
                child:Destroy()
                battleLogItemCount = battleLogItemCount - 1
                break
            end
        end
    end
end

-- ═══════════════════════════════════════════════
-- CONTROLS ROW
-- ═══════════════════════════════════════════════
local controlsPanel = Instance.new("Frame", contentFrame)
controlsPanel.Size = UDim2.new(1, 0, 0, 36)
controlsPanel.Position = UDim2.new(0, 0, 0, 468)
controlsPanel.BackgroundColor3 = C.Panel
controlsPanel.BorderSizePixel = 0
Instance.new("UICorner", controlsPanel).CornerRadius = UDim.new(0, 8)

local controlsLayout = Instance.new("UIListLayout", controlsPanel)
controlsLayout.FillDirection = Enum.FillDirection.Horizontal
controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
controlsLayout.Padding = UDim.new(0, 6)

local function makeToggleBtn(parent, text, defaultOn, onColor, offColor)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.3, -6, 0, 26)
    btn.BackgroundColor3 = defaultOn and onColor or offColor
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = C.Text
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    return btn
end

local resetBtn = makeToggleBtn(controlsPanel, "🔄 RESET", false, C.Green, C.AccentDim)
local discoveryBtn = makeToggleBtn(controlsPanel, "🔍 DISCOVERY", false, C.Orange, C.AccentDim)
local verboseBtn = makeToggleBtn(controlsPanel, "📝 VERBOSE", false, C.Orange, C.AccentDim)

resetBtn.MouseButton1Click:Connect(function()
    encounterCount = 0
    huntStartTime = tick()
    raresFoundCount = 0
    encounterHistory = {}
    currentEnemy = nil
    resetBattleAccumulator()
    encounterVal.Text = "0"
    epmVal.Text = "0.0"
    timerVal.Text = "0m 00s"
    typeVal.Text = "N/A"
    typeVal.TextColor3 = C.TextDim
    stateVal.Text = "Idle"
    stateVal.TextColor3 = C.TextDim
    enemyLbl.Text = "Enemy: Waiting for battle..."
    enemyStatsLbl.Text = ""
    playerLbl.Text = "Your Loomian: —"
    log("INFO", "Session reset")
    sendNotification("LumiWare", "Session stats reset!", 3)
    addBattleLog("Session reset", C.Accent)
end)

discoveryBtn.MouseButton1Click:Connect(function()
    discoveryMode = not discoveryMode
    discoveryBtn.BackgroundColor3 = discoveryMode and C.Orange or C.AccentDim
    discoveryBtn.Text = discoveryMode and "🔍 DISC: ON" or "🔍 DISCOVERY"
    log("INFO", "Discovery mode:", tostring(discoveryMode))
    sendNotification("LumiWare", discoveryMode and "Discovery ON — logging all EVT args" or "Discovery OFF", 3)
    addBattleLog("Discovery mode: " .. tostring(discoveryMode), C.Orange)
end)

verboseBtn.MouseButton1Click:Connect(function()
    VERBOSE_MODE = not VERBOSE_MODE
    verboseBtn.BackgroundColor3 = VERBOSE_MODE and C.Orange or C.AccentDim
    verboseBtn.Text = VERBOSE_MODE and "📝 VERB: ON" or "📝 VERBOSE"
    log("INFO", "Verbose mode:", tostring(VERBOSE_MODE))
    sendNotification("LumiWare", VERBOSE_MODE and "Verbose logging ON" or "Verbose logging OFF", 3)
end)

--------------------------------------------------
-- MINIMIZE / MAXIMIZE
--------------------------------------------------
local fullSize = mainFrame.Size

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
            Size = UDim2.fromOffset(460, 36)
        }):Play()
        contentFrame.Visible = false
        minBtn.Text = "+"
    else
        contentFrame.Visible = true
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
            Size = fullSize
        }):Play()
        minBtn.Text = "–"
    end
end)

--------------------------------------------------
-- TIMER / EPM UPDATER
--------------------------------------------------
task.spawn(function()
    while gui.Parent do
        local elapsed = tick() - huntStartTime
        timerVal.Text = formatTime(elapsed)
        local minutes = elapsed / 60
        if minutes > 0 then
            epmVal.Text = string.format("%.1f", encounterCount / minutes)
        end
        -- Auto-idle after 30s of no battle events
        if battleState == "active" and (tick() - lastBattleTick) > 30 then
            battleState = "idle"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
        end
        task.wait(1)
    end
end)

-- Session webhook every 50 encounters
task.spawn(function()
    local lastMilestone = 0
    while gui.Parent do
        if encounterCount > 0 and encounterCount % 50 == 0 and encounterCount ~= lastMilestone then
            lastMilestone = encounterCount
            local elapsed = tick() - huntStartTime
            sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
        end
        task.wait(5)
    end
end)

--------------------------------------------------
-- EVT BATTLE PROCESSING
-- The EVT remote fires INDIVIDUAL events, not arrays.
-- Each fire: arg1=command, arg2=identifier, arg3=infoStr, arg4=string/number, arg5=table
-- Commands we care about: "switch", "start", "player", "end"
--------------------------------------------------

local function updateBattleUI()
    local enemyName = currentBattle.enemy or "Unknown"
    local playerName = currentBattle.player or "Unknown"

    if enemyName == "Unknown" and playerName == "Unknown" then return end

    -- Update battle type display
    if currentBattle.battleType == "Wild" then
        typeVal.Text = "Wild"
        typeVal.TextColor3 = C.Wild
    elseif currentBattle.battleType == "Trainer" then
        typeVal.Text = "Trainer"
        typeVal.TextColor3 = C.Trainer
    end

    -- Rare check
    local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)

    if rareFound then
        enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
    else
        enemyLbl.Text = "Enemy: " .. enemyName
    end

    -- Enemy stats
    if currentBattle.enemyStats then
        local s = currentBattle.enemyStats
        local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        enemyStatsLbl.Text = string.format("Lv.%d  %s  HP %d/%d", s.level or 0, g, s.hp or 0, s.maxHP or 0)
    else
        enemyStatsLbl.Text = ""
    end

    -- Player display
    if playerName ~= "Unknown" then
        playerLbl.Text = "Your Loomian: " .. playerName
        if currentBattle.playerStats then
            local s = currentBattle.playerStats
            local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
            playerLbl.Text = playerLbl.Text .. string.format("  (Lv.%d %s HP %d/%d)", s.level or 0, g, s.hp or 0, s.maxHP or 0)
        end
    end

    -- Alert on rare
    if rareFound and currentEnemy ~= enemyName then
        currentEnemy = enemyName
        raresFoundCount = raresFoundCount + 1
        log("RARE", "🌟 RARE LOOMIAN FOUND:", enemyName)
        playRareSound()
        sendNotification("⭐ LumiWare Rare Finder", "RARE SPOTTED: " .. enemyName .. "!", 10)
        local extra = currentBattle.enemyStats and ("Lv." .. tostring(currentBattle.enemyStats.level)) or nil
        addRareLog(enemyName, extra)
        addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
        -- Webhook
        local elapsed = tick() - huntStartTime
        local gender = currentBattle.enemyStats and currentBattle.enemyStats.gender or "?"
        sendRareWebhook(enemyName, currentBattle.enemyStats and currentBattle.enemyStats.level, gender, encounterCount, formatTime(elapsed))
    elseif not rareFound then
        currentEnemy = nil
    end
end

local function handleEVT(args)
    local cmd = args[1]
    if type(cmd) ~= "string" then return end

    lastBattleTick = tick()

    local cmdLower = string.lower(cmd)

    -- =============================================
    -- COMMAND: "start" — new battle begins
    -- =============================================
    if cmdLower == "start" then
        log("BATTLE", ">>> Battle START <<<")
        addBattleLog(">>> Battle START <<<", C.Green)
        resetBattleAccumulator()
        currentBattle.active = true
        currentBattle.startTime = tick()
        battleState = "active"
        stateVal.Text = "In Battle"
        stateVal.TextColor3 = C.Green
        return
    end

    -- =============================================
    -- COMMAND: "player" — identifies battle participants
    -- Format: "player", identifier, tag/info, ...
    -- tag might contain "#Wild" for wild battles
    -- =============================================
    if cmdLower == "player" then
        local identifier = args[2]
        local tag = args[3]
        log("BATTLE", "Player event:", tostring(identifier), "|", tostring(tag))

        if type(tag) == "string" then
            if string.find(tag, "#Wild") then
                currentBattle.battleType = "Wild"
                log("BATTLE", "  -> Wild battle detected")
            else
                currentBattle.battleType = "Trainer"
                log("BATTLE", "  -> Trainer battle detected")
            end
        end

        -- arg5 might have side info: {side={id=p1, party={...}, nActive=1}, hasRoom=true}
        local data = args[5]
        if type(data) == "table" then
            logDebug("  Player data:", tablePreview(data))
        end
        return
    end

    -- =============================================
    -- COMMAND: "switch" — a Loomian enters the field
    -- Format: "switch", identifier, infoStr, extra/model data, ...
    -- identifier: "1p1a: Dripple" (p1=player) or "1p2a: Cathorn" (p2=enemy)
    -- infoStr: "Cathorn, L3, F;15/15;0;85/85"
    -- =============================================
    if cmdLower == "switch" then
        local identifier = args[2] -- e.g. "1p2a: Cathorn"
        local infoStr = args[3]    -- e.g. "Cathorn, L3, F;15/15;0;85/85"
        local extra = args[4]      -- might be a string or table

        log("BATTLE", "Switch event:", tostring(identifier), "|", tostring(infoStr))

        -- Extract name from identifier
        local rawName = nil
        if type(identifier) == "string" then
            rawName = identifier:match(":%s*(.+)$")
        end

        -- Try extra data for model name
        if not rawName then
            if type(extra) == "table" then
                if type(extra.model) == "table" and type(extra.model.name) == "string" then
                    rawName = extra.model.name
                elseif type(extra.name) == "string" then
                    rawName = extra.name
                end
            elseif type(extra) == "string" and extra ~= "" then
                -- extra might be the model name directly
                rawName = extra
            end
        end

        -- Fallback: extract from infoStr
        if not rawName and type(infoStr) == "string" then
            rawName = infoStr:match("^([^,]+)")
        end

        if rawName then
            local displayName = extractLoomianName(rawName)
            local stats = parseLoomianStats(type(infoStr) == "string" and infoStr or nil)

            log("BATTLE", "  Name:", displayName)
            if stats then
                log("BATTLE", "  Stats: Lv." .. tostring(stats.level), stats.gender, "HP " .. tostring(stats.hp) .. "/" .. tostring(stats.maxHP))
            end

            -- Determine side from identifier
            local isPlayer = false
            local isEnemy = false
            if type(identifier) == "string" then
                if string.find(identifier, "p1") then
                    isPlayer = true
                elseif string.find(identifier, "p2") then
                    isEnemy = true
                end
            end

            -- Fallback: first switch is enemy, second is player
            if not isPlayer and not isEnemy then
                if not currentBattle.enemy then
                    isEnemy = true
                else
                    isPlayer = true
                end
            end

            if isEnemy then
                currentBattle.enemy = displayName
                currentBattle.enemyStats = stats
                log("BATTLE", "  -> ENEMY:", displayName)

                -- If this is a wild battle, count encounter on enemy switch
                if currentBattle.battleType == "Wild" or battleState ~= "active" then
                    if currentBattle.battleType ~= "Trainer" then
                        currentBattle.battleType = "Wild"
                    end
                    encounterCount = encounterCount + 1
                    encounterVal.Text = tostring(encounterCount)

                    table.insert(encounterHistory, 1, {
                        name = displayName,
                        type = currentBattle.battleType,
                        time = os.date("%X"),
                        count = encounterCount
                    })
                    if #encounterHistory > 10 then table.remove(encounterHistory, 11) end
                end

                addBattleLog("Enemy: " .. displayName .. (stats and (" Lv." .. stats.level) or ""), C.Text)
            elseif isPlayer then
                currentBattle.player = displayName
                currentBattle.playerStats = stats
                log("BATTLE", "  -> PLAYER:", displayName)
                addBattleLog("Player: " .. displayName .. (stats and (" Lv." .. stats.level) or ""), C.TextDim)
            end

            -- Mark battle as active even without explicit "start"
            if not currentBattle.active then
                currentBattle.active = true
                battleState = "active"
                stateVal.Text = "In Battle"
                stateVal.TextColor3 = C.Green
            end

            updateBattleUI()
        else
            log("BATTLE", "  Switch event but couldn't extract name from:", tostring(identifier), tostring(infoStr), tostring(extra))
            addBattleLog("⚠ Switch event — name parse failed", C.Orange)
        end
        return
    end

    -- =============================================
    -- COMMAND: "end" / "flee" / "catch" — battle ends
    -- =============================================
    if cmdLower == "end" or cmdLower == "flee" or cmdLower == "catch" or cmdLower == "win" or cmdLower == "lose" then
        log("BATTLE", ">>> Battle END (" .. cmd .. ") <<<")
        addBattleLog("<<< Battle " .. cmd:upper() .. " >>>", C.Orange)
        battleState = "idle"
        stateVal.Text = "Idle"
        stateVal.TextColor3 = C.TextDim
        currentBattle.active = false
        return
    end

    -- =============================================
    -- COMMAND: "move" / "turn" / other battle commands — keep state active
    -- =============================================
    if cmdLower == "move" or cmdLower == "turn" or cmdLower == "damage" or cmdLower == "hp" or cmdLower == "faint" then
        if battleState ~= "active" then
            battleState = "active"
            stateVal.Text = "In Battle"
            stateVal.TextColor3 = C.Green
        end
        logDebug("Battle cmd:", cmd, "args:", #args)
        return
    end

    -- Unknown EVT command — log in verbose
    logDebug("EVT cmd (unhandled):", cmd, "| args:", #args)
end

-- Also handle the OLD array format just in case some servers still use it
local function handleLegacyArrayFormat(tbl, remoteName)
    if type(tbl) ~= "table" then return false end
    -- Check if this is an array of command tables
    local hasCommands = false
    for _, entry in pairs(tbl) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmd = string.lower(entry[1])
            if cmd == "switch" or cmd == "start" or cmd == "player" then
                hasCommands = true
                break
            end
        end
    end

    if not hasCommands then return false end

    log("BATTLE", "Legacy array format detected in", remoteName)
    addBattleLog("Legacy format in " .. remoteName, C.Orange)

    -- Process each entry as if it were an individual EVT fire
    for _, entry in ipairs(tbl) do
        if type(entry) == "table" then
            handleEVT(entry)
        end
    end
    return true
end

--------------------------------------------------
-- REMOTE HOOKING
--------------------------------------------------
local hooked = {}
local hookedCount = 0
local totalEventsReceived = 0

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    local remoteName = remote.Name

    remote.OnClientEvent:Connect(function(...)
        totalEventsReceived = totalEventsReceived + 1
        local args = {...}

        -- Discovery mode logging
        if discoveryMode then
            local argInfo = {}
            for i, arg in ipairs(args) do
                local info = "arg" .. i .. "=" .. type(arg)
                if type(arg) == "table" then
                    info = info .. "(#" .. tostring(#arg) .. ")"
                elseif type(arg) == "string" then
                    info = info .. '("' .. string.sub(tostring(arg), 1, 30) .. '")'
                end
                table.insert(argInfo, info)
            end
            local logLine = remoteName .. " | " .. table.concat(argInfo, ", ")
            addBattleLog("📡 " .. logLine, Color3.fromRGB(200, 200, 200))
            log("EVT", "DISCOVERY |", remote:GetFullName(), "|", table.concat(argInfo, ", "))

            -- In verbose + discovery, dump table args
            if VERBOSE_MODE then
                for i, arg in ipairs(args) do
                    if type(arg) == "table" then
                        log("DEBUG", " ", remoteName, "arg" .. i .. ":", tablePreview(arg, 0))
                    end
                end
            end
        end

        -- ========= MAIN EVT DETECTION =========
        -- The EVT remote sends: arg1=command(string), arg2..N=data
        -- We handle it if arg1 is a string command
        if type(args[1]) == "string" then
            local cmd = string.lower(args[1])
            -- Is this a known battle command?
            local battleCommands = {
                switch = true, start = true, player = true, ["end"] = true,
                move = true, turn = true, damage = true, hp = true,
                faint = true, flee = true, catch = true, win = true, lose = true,
                item = true, ability = true, status = true, weather = true,
                mega = true, boost = true, unboost = true
            }

            if battleCommands[cmd] then
                log("BATTLE", "EVT(" .. remoteName .. "): cmd=" .. cmd .. " | total_args=" .. #args)
                handleEVT(args)
                return
            end
        end

        -- ========= LEGACY ARRAY FORMAT =========
        -- Some versions may send arrays of commands in a single table arg
        for argIdx, arg in ipairs(args) do
            if type(arg) == "table" and #arg > 0 then
                if handleLegacyArrayFormat(arg, remoteName) then
                    return
                end
            end
        end
    end)
end

-- Hook ReplicatedStorage
log("HOOK", "Scanning ReplicatedStorage...")
local rsCount = 0
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") then
        hookEvent(obj)
        rsCount = rsCount + 1
    end
end
log("HOOK", "Hooked", rsCount, "RemoteEvents from ReplicatedStorage")

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then
        hookEvent(obj)
        log("HOOK", "New RemoteEvent hooked:", obj:GetFullName())
    end
end)

-- Hook Workspace
pcall(function()
    local wsCount = 0
    for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            hookEvent(obj)
            wsCount = wsCount + 1
        end
    end
    if wsCount > 0 then log("HOOK", "Hooked", wsCount, "from Workspace") end
end)

-- Hook PlayerGui
pcall(function()
    local pgCount = 0
    for _, obj in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            hookEvent(obj)
            pgCount = pgCount + 1
        end
    end
    if pgCount > 0 then log("HOOK", "Hooked", pgCount, "from PlayerGui") end
end)

addBattleLog("Hooked " .. hookedCount .. " remotes — ready", C.Green)

--------------------------------------------------
-- STARTUP
--------------------------------------------------
log("INFO", "========================================")
log("INFO", "LumiWare v3 READY")
log("INFO", "Player:", PLAYER_NAME)
log("INFO", "Total RemoteEvents hooked:", hookedCount)
log("INFO", "Rares tracked:", #RARE_LOOMIANS)
log("INFO", "Data format: Individual EVT fires (arg1=cmd)")
log("INFO", "========================================")
sendNotification("⚡ LumiWare v3", "Hooked " .. hookedCount .. " remotes.\nTracking " .. #RARE_LOOMIANS .. " rares.\nUse Discovery mode to debug.", 8)
