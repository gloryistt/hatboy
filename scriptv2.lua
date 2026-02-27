--------------------------------------------------
-- LUMIWARE V2 — Full Feature Suite
--------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

--------------------------------------------------
-- RARE LOOMIANS DB
--------------------------------------------------
local RARE_LOOMIANS = {
    "Duskit", "Ikazune", "Mutagon", "Protogon", "Metronette", "Wabalisc",
    "Cephalops", "Elephage", "Gargolem", "Celesting", "Nyxre", "Pyramind",
    "Terracolt", "Garbantis", "Cynamoth", "Avitross", "Snocub", "Eaglit",
    "Vambat", "Weevolt", "Dripple", "Fevine", "Embit", "Nevermare",
    "Akhalos", "Odasho", "Cosmiore", "Armenti"
}

local customRares = {} -- user-added rares

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
        sound.SoundId = "rbxassetid://6518811702" -- bell/ding sound
        sound.Volume = 1
        sound.Parent = SoundService
        sound:Play()
        task.delay(3, function() sound:Destroy() end)
    end)
end

--------------------------------------------------
-- STATE
--------------------------------------------------
local encounterCount = 0
local huntStartTime = tick()
local currentEnemy = nil
local isMinimized = false
local battleType = "N/A" -- "Wild" or "Trainer"

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
    -- e.g. "Craytal, L21, M;71/71;0;114/114"
    if type(infoStr) ~= "string" then return nil end
    local name, level, rest = infoStr:match("^(.+), L(%d+), (.+)$")
    if not name then return nil end
    local genderHP = rest
    local gender = genderHP:match("^(%a)") or "?"
    local hp, maxHP = genderHP:match("(%d+)/(%d+)")
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

--------------------------------------------------
-- GUI: CLEANUP OLD
--------------------------------------------------
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
if not ok then gui.Parent = player:WaitForChild("PlayerGui") end

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
}

--------------------------------------------------
-- MAIN FRAME
--------------------------------------------------
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(440, 420)
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

local topCorner = Instance.new("UICorner", topbar)
topCorner.CornerRadius = UDim.new(0, 10)

-- tiny rect to square off bottom corners of topbar
local topFill = Instance.new("Frame", topbar)
topFill.Size = UDim2.new(1, 0, 0, 10)
topFill.Position = UDim2.new(0, 0, 1, -10)
topFill.BackgroundColor3 = C.TopBar
topFill.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", topbar)
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "⚡ LumiWare v2"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextColor3 = C.Accent
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize button
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

-- Close button
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
-- TOP ROW: Stats Bar (Encounters, EPM, Timer, Battle Type)
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
statsLayout.Padding = UDim.new(0, 6)

local function makeStatCell(parent, label, value, color)
    local cell = Instance.new("Frame", parent)
    cell.Size = UDim2.new(0.24, -6, 1, -8)
    cell.BackgroundColor3 = C.PanelAlt
    cell.BorderSizePixel = 0
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", cell)
    lbl.Size = UDim2.new(1, 0, 0.45, 0)
    lbl.Position = UDim2.new(0, 0, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextColor3 = C.TextDim

    local val = Instance.new("TextLabel", cell)
    val.Name = "Value"
    val.Size = UDim2.new(1, 0, 0.55, 0)
    val.Position = UDim2.new(0, 0, 0.4, 0)
    val.BackgroundTransparency = 1
    val.Text = value
    val.Font = Enum.Font.GothamBold
    val.TextSize = 14
    val.TextColor3 = color or C.Text

    return val
end

local encounterVal = makeStatCell(statsBar, "ENCOUNTERS", "0", C.Green)
local epmVal = makeStatCell(statsBar, "ENC/MIN", "0.0", C.Text)
local timerVal = makeStatCell(statsBar, "HUNT TIME", "0m 00s", C.Text)
local typeVal = makeStatCell(statsBar, "BATTLE", "N/A", C.TextDim)

-- ═══════════════════════════════════════════════
-- MIDDLE: Current Encounter Panel
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
logPanel.Size = UDim2.new(1, 0, 0, 130)
logPanel.Position = UDim2.new(0, 0, 0, 152)
logPanel.BackgroundColor3 = C.Panel
logPanel.BorderSizePixel = 0
Instance.new("UICorner", logPanel).CornerRadius = UDim.new(0, 8)

local logTitle = Instance.new("TextLabel", logPanel)
logTitle.Size = UDim2.new(1, -16, 0, 24)
logTitle.Position = UDim2.new(0, 8, 0, 4)
logTitle.BackgroundTransparency = 1
logTitle.Text = "RARE FINDER LOG"
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
-- CUSTOM RARE LIST INPUT
-- ═══════════════════════════════════════════════
local customPanel = Instance.new("Frame", contentFrame)
customPanel.Size = UDim2.new(1, 0, 0, 62)
customPanel.Position = UDim2.new(0, 0, 0, 288)
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
customInput.Position = UDim2.new(0, 8, 0, 28)
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
addBtn.Position = UDim2.new(1, -82, 0, 28)
addBtn.BackgroundColor3 = C.Green
addBtn.Text = "+"
addBtn.Font = Enum.Font.GothamBold
addBtn.TextSize = 16
addBtn.TextColor3 = C.BG
addBtn.BorderSizePixel = 0
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 5)

local clearBtn = Instance.new("TextButton", customPanel)
clearBtn.Size = UDim2.fromOffset(36, 26)
clearBtn.Position = UDim2.new(1, -42, 0, 28)
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
        end
    end
    customInput.Text = ""
    sendNotification("LumiWare", "Added to custom rare list!", 3)
end)

clearBtn.MouseButton1Click:Connect(function()
    customRares = {}
    sendNotification("LumiWare", "Custom rare list cleared.", 3)
end)

--------------------------------------------------
-- MINIMIZE / MAXIMIZE
--------------------------------------------------
local fullSize = mainFrame.Size

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
            Size = UDim2.fromOffset(440, 36)
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
        task.wait(1)
    end
end)

--------------------------------------------------
-- DATA PARSING
--------------------------------------------------
local function buildLoomianNamesFromRaw(tbl)
    local names = { enemy = nil, player = nil, enemyStats = nil, playerStats = nil }
    if type(tbl) ~= "table" then return names end

    for i = 1, #tbl do
        local entry = tbl[i]
        if type(entry) == "table" and entry[1] == "switch" then
            local identifier = entry[2]
            local infoStr = entry[3]
            local extra = entry[4]

            if type(extra) == "table" and type(extra.model) == "table" and type(extra.model.name) == "string" then
                local rawName = extra.model.name
                local displayName = extractLoomianName(rawName)
                local stats = parseLoomianStats(infoStr)

                if identifier and string.find(identifier, "p2") then
                    names.enemy = displayName
                    names.enemyStats = stats
                elseif identifier and string.find(identifier, "p1") then
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
                if string.find(tag, "#Wild") then
                    return "Wild"
                else
                    return "Trainer"
                end
            end
        end
    end
    return "N/A"
end

local function processBattleData(tbl)
    local names = buildLoomianNamesFromRaw(tbl)
    local enemyName = names.enemy or "Unknown"
    local playerName = names.player or "Unknown"

    if enemyName == "Unknown" and playerName == "Unknown" then return end

    -- Detect battle type
    battleType = detectBattleType(tbl)
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

    -- Increment encounter count (only for wild)
    if battleType == "Wild" then
        encounterCount = encounterCount + 1
        encounterVal.Text = tostring(encounterCount)
    end

    -- Rare check
    local rareFound = isRareLoomian(enemyName) or isRareModifier(enemyName)

    if rareFound then
        enemyLbl.Text = 'Enemy: <font color="#FFD700">⭐ ' .. enemyName .. ' (RARE!)</font>'
    else
        enemyLbl.Text = "Enemy: " .. enemyName
    end

    -- Stats display
    if names.enemyStats then
        local s = names.enemyStats
        local genderIcon = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        enemyStatsLbl.Text = string.format("Lv.%d  %s  HP %d/%d", s.level or 0, genderIcon, s.hp or 0, s.maxHP or 0)
    else
        enemyStatsLbl.Text = ""
    end

    playerLbl.Text = "Your Loomian: " .. playerName
    if names.playerStats then
        local s = names.playerStats
        local genderIcon = s.gender == "M" and "♂" or (s.gender == "F" and "♀" or "?")
        playerLbl.Text = playerLbl.Text .. string.format("  (Lv.%d %s HP %d/%d)", s.level or 0, genderIcon, s.hp or 0, s.maxHP or 0)
    end

    -- Alert on NEW rare
    if rareFound and currentEnemy ~= enemyName then
        currentEnemy = enemyName
        playRareSound()
        sendNotification("⭐ LumiWare Rare Finder", "RARE SPOTTED: " .. enemyName .. "!", 10)
        local extraInfo = nil
        if names.enemyStats then
            extraInfo = "Lv." .. tostring(names.enemyStats.level)
        end
        addRareLog(enemyName, extraInfo)
    elseif not rareFound then
        currentEnemy = nil
    end
end

--------------------------------------------------
-- REMOTE SPY / DEBUG LOG PANEL
--------------------------------------------------
local spyPanel = Instance.new("Frame", contentFrame)
spyPanel.Size = UDim2.new(1, 0, 0, 90)
spyPanel.Position = UDim2.new(0, 0, 0, 356)
spyPanel.BackgroundColor3 = C.Panel
spyPanel.BorderSizePixel = 0
Instance.new("UICorner", spyPanel).CornerRadius = UDim.new(0, 8)

local spyTitle = Instance.new("TextLabel", spyPanel)
spyTitle.Size = UDim2.new(1, -16, 0, 20)
spyTitle.Position = UDim2.new(0, 8, 0, 4)
spyTitle.BackgroundTransparency = 1
spyTitle.Text = "REMOTE SPY (DEBUG)"
spyTitle.Font = Enum.Font.GothamBold
spyTitle.TextSize = 11
spyTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
spyTitle.TextXAlignment = Enum.TextXAlignment.Left

local spyScroll = Instance.new("ScrollingFrame", spyPanel)
spyScroll.Size = UDim2.new(1, -16, 1, -28)
spyScroll.Position = UDim2.new(0, 8, 0, 24)
spyScroll.BackgroundTransparency = 1
spyScroll.ScrollBarThickness = 3
spyScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 100, 100)
spyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
spyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local spyLayout = Instance.new("UIListLayout", spyScroll)
spyLayout.SortOrder = Enum.SortOrder.LayoutOrder
spyLayout.Padding = UDim.new(0, 2)

local spyOrder = 0
local spyItemCount = 0
local MAX_SPY_ITEMS = 50

local function addSpyLog(text, color)
    spyOrder = spyOrder + 1
    spyItemCount = spyItemCount + 1
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 16)
    item.BackgroundTransparency = 1
    item.Text = "[" .. os.date("%X") .. "] " .. text
    item.Font = Enum.Font.Code
    item.TextSize = 10
    item.TextColor3 = color or C.TextDim
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.LayoutOrder = spyOrder
    item.Parent = spyScroll

    -- Keep log from growing too large
    if spyItemCount > MAX_SPY_ITEMS then
        local children = spyScroll:GetChildren()
        for _, child in ipairs(children) do
            if child:IsA("TextLabel") then
                child:Destroy()
                spyItemCount = spyItemCount - 1
                break
            end
        end
    end
end

-- Expand mainFrame to fit the new panel
mainFrame.Size = UDim2.fromOffset(440, 500)
fullSize = mainFrame.Size

-- Simple table preview for spy log
local function tablePreview(tbl, depth)
    depth = depth or 0
    if depth > 1 then return "{...}" end
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

--------------------------------------------------
-- REMOTE HOOKING
--------------------------------------------------
local hooked = {}
local hookedCount = 0

local function hookEvent(remote)
    if hooked[remote] then return end
    hooked[remote] = true
    hookedCount = hookedCount + 1

    remote.OnClientEvent:Connect(function(...)
        local args = {...}
        -- Log to spy
        local argPreview = ""
        for i, arg in ipairs(args) do
            if type(arg) == "table" then
                argPreview = argPreview .. " arg" .. i .. "=" .. tablePreview(arg)
            else
                argPreview = argPreview .. " arg" .. i .. "=" .. tostring(arg)
            end
        end
        addSpyLog(remote.Name .. argPreview, C.TextDim)

        -- Try to detect battle data
        for _, arg in ipairs(args) do
            if type(arg) == "table" then
                -- Method 1: Check for "start" or "switch" entries (array of arrays)
                local isBattle = false
                for _, entry in pairs(arg) do
                    if type(entry) == "table" and (entry[1] == "start" or entry[1] == "switch") then
                        isBattle = true
                        break
                    end
                end
                if isBattle then
                    addSpyLog(">>> BATTLE DATA DETECTED <<<", C.Green)
                    processBattleData(arg)
                end
            end
        end
    end)
end

-- Hook everything in ReplicatedStorage
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") then hookEvent(obj) end
end
ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then hookEvent(obj) end
end)

-- Also try hooking remotes in other common locations
pcall(function()
    for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then hookEvent(obj) end
    end
end)

addSpyLog("Hooked " .. hookedCount .. " remote events", C.Green)

--------------------------------------------------
-- STARTUP
--------------------------------------------------
sendNotification("⚡ LumiWare v2", "Loaded! Hooked " .. hookedCount .. " remotes, tracking " .. #RARE_LOOMIANS .. " rares.", 5)
