-- Improved version of the wild battle automation script.
-- Focuses on readability, safer nil checks, and easier configuration.

local clickOffsets = Vector2.new(0, 0)

-- Select ONE move slot to use (1-4).
local ACTIVE_MOVE = 3

-- Minimum energy required before using your selected move.
local maxEnergyMove = 20

local KeepPokemon = {
    duskit = true,
    ikazune = true,
    protogon = true,
    dakuda = true,
    cosmeleon = true,
    cephalops = true,
    elephage = true,
    glacadia = true,
    arceros = true,
    metronette = true,
    nevermare = true,
    gargolem = true,
    odoyaga = true,
    wabalisc = true,
    akhalos = true,
    celesting = true,
    mimask = true,
    grimyuline = true,
    phagenaut = true,
    novadeaus = true,
    cosmiore = true,
    nymaurae = true,
    nymesis = true,
}

local uis = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local restColor3 = Color3.fromRGB(218, 83, 255)
local fightColor3 = Color3.fromRGB(255, 102, 102)

local eject = false
local ended = false
local Main

for _, v in pairs(getgc(true)) do
    if typeof(v) == "table" and rawget(v, "DataManager") then
        Main = v
        break
    end
end

if not Main or not Main.Battle or not Main.DataManager then
    warn("Could not find battle/data manager table. Stopping script.")
    return
end

local function getCenterPosition(button)
    local absPos = button.AbsolutePosition
    local absSize = button.AbsoluteSize
    local centerX = math.floor(absPos.X + absSize.X / 2)
    local centerY = math.floor(absPos.Y + absSize.Y / 2)
    return centerX + clickOffsets.X, centerY + clickOffsets.Y
end

local function clickButton(button)
    if not button then
        return false
    end

    local parent = button.Parent
    if not parent or not parent:IsA("GuiObject") or not parent.Visible then
        return false
    end

    mousemoveabs(getCenterPosition(button))
    mouse1click()
    return true
end

local function getBattleGui()
    return PlayerGui:FindFirstChild("BattleGui", true)
end

local function collectActionButtons(battleGui)
    local clickFight
    local restFight

    for _, v in ipairs(battleGui:GetChildren()) do
        if v.ClassName == "ImageLabel" then
            if v.ImageColor3 == restColor3 then
                restFight = v:FindFirstChild("Button")
            elseif v.ImageColor3 == fightColor3 then
                clickFight = v:FindFirstChild("Button")
            end
        end
    end

    return clickFight, restFight
end

local function getMoveButtons(battleGui)
    local moves = {}
    for i = 1, 4 do
        local moveFrame = battleGui:FindFirstChild("Move" .. i, true)
        moves[i] = moveFrame and moveFrame:FindFirstChild("Button") or nil
    end
    return moves
end

local function currentEnergy()
    local active = Main.Battle.currentBattle
        and Main.Battle.currentBattle.p1
        and Main.Battle.currentBattle.p1.active
        and Main.Battle.currentBattle.p1.active[1]

    return active and active.energy or 0
end

local function enoughEnergy()
    return currentEnergy() >= maxEnergyMove
end

local function isKeepEncounter()
    local ok, species = pcall(function()
        return Main.Battle.currentBattle.p1.foe.active[1].species
    end)

    if not ok or not species then
        return false
    end

    return KeepPokemon[string.lower(species)] == true
end

local function startBattle()
    task.spawn(function()
        ended = false
        Main.Battle.doWildBattle(Main.Battle, Main.DataManager.currentChunk.regionData.Grass, {})
        ended = true
    end)
end

uis.InputBegan:Connect(function(key, proc)
    if key.KeyCode == Enum.KeyCode.E and not proc then
        eject = true
    end
end)

while not eject do
    startBattle()

    local battleGui = getBattleGui()
    while not battleGui and not eject do
        task.wait()
        battleGui = getBattleGui()
    end

    if eject or not battleGui then
        break
    end

    local clickFight, restFight = collectActionButtons(battleGui)

    if not battleGui:FindFirstChild("Move1", true) then
        task.wait(2)
        clickButton(clickFight)
        clickFight, restFight = collectActionButtons(battleGui)
    end

    while not battleGui:FindFirstChild("Move1", true) and not eject do
        clickButton(clickFight)
        task.wait()
    end

    local moveButtons = getMoveButtons(battleGui)

    while not ended and not eject do
        task.wait()

        pcall(function()
            Main.Battle.currentBattle.fastForward = true
        end)

        if isKeepEncounter() then
            eject = true
            break
        end

        if clickFight and clickFight.Parent.Visible and not (moveButtons[1] and moveButtons[1].Parent.Visible) then
            clickButton(clickFight)
        elseif moveButtons[ACTIVE_MOVE] and enoughEnergy() then
            clickButton(moveButtons[ACTIVE_MOVE])
        elseif restFight and restFight.Parent.Visible and not enoughEnergy() then
            clickButton(restFight)
        end
    end
end
