--------------------------------------------------
-- LUMIWARE V3 — Battle Detection Fix + Webhook
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
local LOG_LEVELS = { HOOK = "🔗", BATTLE = "⚔️", RARE = "⭐", INFO = "ℹ️", WARN = "⚠️", WEBHOOK = "📡", DEBUG = "🔍" }
local VERBOSE_MODE = false -- toggle via GUI

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
            avatar_url = "https://i.imgur.com/placeholder.png",
            embeds = { embedData }
        })
        -- Try executor HTTP methods
        local httpFunc = (syn and syn.request) or (http and http.request) or request or http_request
        if httpFunc then
            httpFunc({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = payload
            })
            log("WEBHOOK", "Sent webhook embed:", embedData.title or "untitled")
        else
            log("WARN", "No HTTP function available for webhooks")
        end
    end)
end

local function sendRareWebhook(loomianName, level, gender, encounterCount, huntTime)
    sendWebhook({
        title = "⭐ RARE LOOMIAN FOUND!",
        description = "**" .. loomianName .. "** has been detected!",
        color = 16766720, -- gold
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
        color = 7930367, -- purple
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
local battleState = "idle" -- idle / active / ended
local lastBattleTick = 0
local raresFoundCount = 0
local encounterHistory = {} -- last 10 encounters
local discoveryMode = false -- logs ALL remotes when true

-- Known battle-related remote names (case-insensitive matching)
local BATTLE_REMOTE_PATTERNS = {
    "evt", "event", "battle", "combat", "fight", "encounter",
    "wild", "turn", "action", "loomian", "switch", "move",
    "pvp", "trainer", "npc"
}

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
    if not name then return nil end
    local gender = rest:match("^(%a)") or "?"
    local hp, maxHP = rest:match("(%d+)/(%d+)")
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

-- Compact table preview for battle log
local function tablePreview(tbl, depth)
    depth = depth or 0
    if depth > 1 then return "{...}" end
    local parts = {}
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        if count > 4 then
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

-- Check if a remote name matches known battle patterns
local function isBattleRemote(remoteName)
    local lower = string.lower(remoteName)
    for _, pattern in ipairs(BATTLE_REMOTE_PATTERNS) do
        if string.find(lower, pattern) then
            return true
        end
    end
    return false
end

-- Count recognized battle commands in a table
local BATTLE_COMMANDS = { start = true, switch = true, player = true, move = true, turn = true, ["end"] = true, flee = true, catch = true, item = true }

local function countBattleCommands(tbl)
    local count = 0
    local found = {}
    if type(tbl) ~= "table" then return 0, found end
    for _, entry in pairs(tbl) do
        if type(entry) == "table" and type(entry[1]) == "string" then
            local cmd = string.lower(entry[1])
            if BATTLE_COMMANDS[cmd] then
                count = count + 1
                found[cmd] = true
            end
        end
    end
    return count, found
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
-- TOPBAR (draggable)
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
    log("INFO", "Close button pressed, sending session summary and destroying GUI")
    local elapsed = tick() - huntStartTime
    sendSessionWebhook(encounterCount, formatTime(elapsed), raresFoundCount)
    gui:Destroy()
end)

-- Drag logic
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
        -- Send a test message
        sendWebhook({
            title = "✅ Webhook Connected!",
            description = "LumiWare v3 is now sending alerts to this channel.",
            color = 5763719, -- green
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
-- BATTLE LOG (replaces old Remote Spy)
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
-- CONTROLS ROW (Reset, Discovery Mode, Verbose)
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
    encounterVal.Text = "0"
    epmVal.Text = "0.0"
    timerVal.Text = "0m 00s"
    typeVal.Text = "N/A"
    typeVal.TextColor3 = C.TextDim
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
    sendNotification("LumiWare", discoveryMode and "Discovery mode ON — logging all remotes" or "Discovery mode OFF", 3)
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
        -- Auto-update battle state to idle if no battle event in 30s
        if battleState == "active" and (tick() - lastBattleTick) > 30 then
            battleState = "ended"
            stateVal.Text = "Idle"
            stateVal.TextColor3 = C.TextDim
            log("BATTLE", "Battle state auto-reset to idle (timeout)")
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
-- DATA PARSING — uses the legacy ["switch",...] array format
-- found in battle remote events
--------------------------------------------------

local function buildLoomianNamesFromBattle(tbl)
    local names = { enemy = nil, player = nil, enemyStats = nil, playerStats = nil }
    if type(tbl) ~= "table" then return names end

    for i = 1, #tbl do
        local entry = tbl[i]
        if type(entry) == "table" and entry[1] == "switch" then
            local identifier = entry[2]  -- e.g. "1p2a: Cathorn" or "1p1a: Dripple"
            local infoStr = entry[3]     -- e.g. "Cathorn, L3, F;15/15;0;85/85"
            local extra = entry[4]       -- table with model info

            logDebug("  switch entry at index", i, "| id:", tostring(identifier))

            -- Try to get the name from extra.model.name or extra.name
            local rawName = nil
            if type(extra) == "table" then
                if type(extra.model) == "table" and type(extra.model.name) == "string" then
                    rawName = extra.model.name
                elseif type(extra.name) == "string" then
                    rawName = extra.name
                end
            end

            -- Fallback: extract name from identifier string (e.g. "1p2a: Cathorn" -> "Cathorn")
            if not rawName and type(identifier) == "string" then
                rawName = identifier:match(":%s*(.+)$")
            end

            -- Fallback 2: extract name from infoStr (e.g. "Cathorn, L3, ..." -> "Cathorn")
            if not rawName and type(infoStr) == "string" then
                rawName = infoStr:match("^([^,]+)")
            end

            if rawName then
                local displayName = extractLoomianName(rawName)
                local stats = parseLoomianStats(infoStr)

                log("BATTLE", "  Found:", displayName, identifier and ("(" .. tostring(identifier) .. ")") or "")

                -- Determine player vs enemy from identifier
                if identifier and type(identifier) == "string" then
                    if string.find(identifier, "p2") then
                        names.enemy = displayName
                        names.enemyStats = stats
                    elseif string.find(identifier, "p1") then
                        names.player = displayName
                        names.playerStats = stats
                    end
                end

                -- Fallback: positional assignment
                if not names.enemy and not (identifier and type(identifier) == "string" and string.find(identifier, "p1")) then
                    names.enemy = displayName
                    names.enemyStats = stats
                elseif not names.player and not (identifier and type(identifier) == "string" and string.find(identifier, "p2")) then
                    names.player = displayName
                    names.playerStats = stats
                end
            end
        end
    end
    return names
end

local function detectBattleType(tbl)
    if type(tbl) ~= "table" then return "N/A" end
    for _, entry in ipairs(tbl) do
        if type(entry) == "table" and entry[1] == "player" then
            local tag = entry[3]
            if type(tag) == "string" then
                if string.find(tag, "#Wild") then return "Wild"
                else return "Trainer" end
            end
        end
    end
    return "N/A"
end

local function processBattleData(tbl, remoteName)
    log("BATTLE", "=== PROCESSING BATTLE DATA === (from: " .. tostring(remoteName) .. ")")
    
    battleState = "active"
    lastBattleTick = tick()
    stateVal.Text = "In Battle"
    stateVal.TextColor3 = C.Green

    local names = buildLoomianNamesFromBattle(tbl)
    local enemyName = names.enemy or "Unknown"
    local playerName = names.player or "Unknown"

    log("BATTLE", "Result: Enemy =", enemyName, "| Player =", playerName)

    if enemyName == "Unknown" and playerName == "Unknown" then
        log("BATTLE", "Both unknown — data format may have changed. Dumping structure:")
        -- Only dump structure in verbose mode or if both are unknown (helps debugging)
        for i, entry in ipairs(tbl) do
            if type(entry) == "table" then
                local parts = {}
                for j = 1, math.min(#entry, 4) do
                    table.insert(parts, tostring(entry[j]))
                end
                log("BATTLE", "  [" .. i .. "]:", table.concat(parts, " | "))
            end
        end
        addBattleLog("⚠ Battle detected but couldn't parse names", C.Orange)
        return
    end

    -- Battle type
    battleType = detectBattleType(tbl)
    log("BATTLE", "Type:", battleType)

    if battleType == "Wild" then
        typeVal.Text = "Wild"
        typeVal.TextColor3 = C.Wild
    elseif battleType == "Trainer" then
        typeVal.Text = "Trainer"
        typeVal.TextColor3 = C.Trainer
    else
        typeVal.Text = "N/A"
        typeVal.TextColor3 = C.TextDim
    end

    -- Count encounters (wild only)
    if battleType == "Wild" then
        encounterCount = encounterCount + 1
        encounterVal.Text = tostring(encounterCount)
    end

    -- Encounter history
    table.insert(encounterHistory, 1, {
        name = enemyName,
        type = battleType,
        time = os.date("%X"),
        count = encounterCount
    })
    if #encounterHistory > 10 then
        table.remove(encounterHistory, 11)
    end

    -- Rare check
    local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)

    if rareFound then
        enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
        addBattleLog("⭐ RARE: " .. enemyName, C.Gold)
    else
        enemyLbl.Text = "Enemy: " .. enemyName
        addBattleLog(battleType .. ": " .. enemyName .. " vs " .. playerName, C.TextDim)
    end

    -- Enemy stats
    if names.enemyStats then
        local s = names.enemyStats
        local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        enemyStatsLbl.Text = string.format("Lv.%d  %s  HP %d/%d", s.level or 0, g, s.hp or 0, s.maxHP or 0)
    else
        enemyStatsLbl.Text = ""
    end

    -- Player display
    playerLbl.Text = "Your Loomian: " .. playerName
    if names.playerStats then
        local s = names.playerStats
        local g = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        playerLbl.Text = playerLbl.Text .. string.format("  (Lv.%d %s HP %d/%d)", s.level or 0, g, s.hp or 0, s.maxHP or 0)
    end

    -- Alert on rare
    if rareFound and currentEnemy ~= enemyName then
        currentEnemy = enemyName
        raresFoundCount = raresFoundCount + 1
        log("RARE", "🌟 RARE LOOMIAN FOUND:", enemyName)
        playRareSound()
        sendNotification("⭐ LumiWare Rare Finder", "RARE SPOTTED: " .. enemyName .. "!", 10)
        local extra = names.enemyStats and ("Lv." .. tostring(names.enemyStats.level)) or nil
        addRareLog(enemyName, extra)
        -- Webhook for rare
        local elapsed = tick() - huntStartTime
        local gender = names.enemyStats and names.enemyStats.gender or "?"
        sendRareWebhook(enemyName, names.enemyStats and names.enemyStats.level, gender, encounterCount, formatTime(elapsed))
    elseif not rareFound then
        currentEnemy = nil
    end
    log("BATTLE", "=== END BATTLE PROCESSING ===")
end

--------------------------------------------------
-- REMOTE HOOKING — Smart Filtering
--------------------------------------------------
local hooked = {}
local hookedCount = 0
local battleRemotesHooked = 0
local totalEventsReceived = 0

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    local remoteName = remote.Name
    local isBattle = isBattleRemote(remoteName)
    if isBattle then
        battleRemotesHooked = battleRemotesHooked + 1
    end

    remote.OnClientEvent:Connect(function(...)
        totalEventsReceived = totalEventsReceived + 1
        local args = {...}

        -- Discovery mode: log ALL remotes to help identify the right one
        if discoveryMode then
            local argTypes = {}
            for i, arg in ipairs(args) do
                local info = "arg" .. i .. "=" .. type(arg)
                if type(arg) == "table" then
                    info = info .. "(#" .. #arg .. ")"
                end
                table.insert(argTypes, info)
            end
            addBattleLog("📡 " .. remoteName .. " | " .. table.concat(argTypes, ", "), Color3.fromRGB(200, 200, 200))
            logDebug("DISCOVERY |", remoteName, "|", remote:GetFullName(), "|", table.concat(argTypes, ", "))
        end

        -- Verbose logging of table structure (only in verbose mode)
        if VERBOSE_MODE then
            for i, arg in ipairs(args) do
                if type(arg) == "table" then
                    logDebug("  " .. remoteName .. " arg" .. i .. ":", tablePreview(arg))
                end
            end
        end

        -- === BATTLE DETECTION ===
        -- Scan table args for battle data, but with confidence checks
        for argIdx, arg in ipairs(args) do
            if type(arg) == "table" then
                local cmdCount, foundCmds = countBattleCommands(arg)

                -- Require at least 2 recognized battle commands for high confidence
                -- OR require a "switch" command specifically (the key indicator)
                local isLikelyBattle = cmdCount >= 2 or foundCmds["switch"]

                if isLikelyBattle then
                    -- Additional validation: must have at least one switch entry with a valid identifier
                    local hasValidSwitch = false
                    for _, entry in pairs(arg) do
                        if type(entry) == "table" and entry[1] == "switch" and type(entry[2]) == "string" then
                            -- Check identifier format: should contain "p1" or "p2" or ": "
                            if string.find(entry[2], "p%d") or string.find(entry[2], ":") then
                                hasValidSwitch = true
                                break
                            end
                        end
                    end

                    if hasValidSwitch then
                        log("BATTLE", ">>> Battle data detected in", remoteName, "arg" .. argIdx, "(cmds:", cmdCount, ") <<<")
                        addBattleLog(">>> BATTLE in " .. remoteName .. " <<<", C.Green)
                        processBattleData(arg, remoteName)
                    elseif cmdCount >= 3 then
                        -- High command count = likely battle even without perfect switch format
                        log("BATTLE", ">>> Probable battle in", remoteName, "arg" .. argIdx, "(cmds:", cmdCount, ", no valid switch format) <<<")
                        addBattleLog(">>> PROBABLE BATTLE in " .. remoteName .. " <<<", C.Orange)
                        processBattleData(arg, remoteName)
                    else
                        logDebug("Skipped table in", remoteName, "arg" .. argIdx, "- has switch but no valid identifier format")
                    end
                end
            end
        end
    end)
end

-- Hook ReplicatedStorage
log("HOOK", "Scanning ReplicatedStorage for RemoteEvents...")
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
    log("HOOK", "Scanning Workspace for RemoteEvents...")
    local wsCount = 0
    for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            hookEvent(obj)
            wsCount = wsCount + 1
        end
    end
    log("HOOK", "Hooked", wsCount, "RemoteEvents from Workspace")
end)

-- Hook PlayerGui
pcall(function()
    log("HOOK", "Scanning PlayerGui for RemoteEvents...")
    local pgCount = 0
    for _, obj in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            hookEvent(obj)
            pgCount = pgCount + 1
        end
    end
    log("HOOK", "Hooked", pgCount, "RemoteEvents from PlayerGui")
end)

addBattleLog("Hooked " .. hookedCount .. " remotes (" .. battleRemotesHooked .. " battle-related)", C.Green)

--------------------------------------------------
-- STARTUP
--------------------------------------------------
log("INFO", "========================================")
log("INFO", "LumiWare v3 READY")
log("INFO", "Player:", PLAYER_NAME)
log("INFO", "Total RemoteEvents hooked:", hookedCount)
log("INFO", "Battle-related remotes:", battleRemotesHooked)
log("INFO", "Rare Loomians tracked:", #RARE_LOOMIANS)
log("INFO", "Waiting for battle events...")
log("INFO", "========================================")
sendNotification("⚡ LumiWare v3", "Hooked " .. hookedCount .. " remotes, tracking " .. #RARE_LOOMIANS .. " rares.\nUse Discovery mode if battles aren't detected.", 8)
